-- Character.lua
-- Reads the live character sheet through the Blizzard API (talents come from
-- the build in Data/Build.lua, not from the game) and
-- turns them into a Model state. Every call is guarded: a missing function or
-- a secret value (combat) falls back to the last good reading, then to the
-- model's defaults, and the field is listed as "estimated".

local _, NS = ...
local C = NS.Compat
local Character = {}
NS.Character = Character

local lastGood = {}

-- First return values of f(...), or nil if f is missing, errors or is secret.
local function call(f, ...)
    if type(f) ~= "function" then return nil end
    local r = { pcall(f, ...) }
    if not r[1] then return nil end
    for i = 2, #r do if C.IsSecret(r[i]) then return nil end end
    return unpack(r, 2)
end
local function num(v) v = tonumber(v); if v and v == v then return v end end

---------------------------------------------------------------- spells

-- Spells whose numbers we read from their tooltip (English and French names).
local SPELLS = {
    how = { "Hammer of Wrath", "Marteau de courroux" },
    holyStrike = { "Holy Strike", "Frappe sacrée" },
    soc = { "Seal of Command", "Sceau d'autorité" },
    sor = { "Seal of Righteousness", "Sceau de piété" },
}
Character.SPELLS = SPELLS

-- Returns { how = { known, id, base, weapon, cd, lines }, ... }, or nil when
-- none of them can be found (unknown locale or no spell API): then the model
-- uses its constants and the level rule for Hammer of Wrath.
function Character.ReadSpells()
    local out, any = {}, false
    for key, names in pairs(SPELLS) do
        local id
        for _, n in ipairs(names) do
            id = C.GetKnownSpellID(n)
            if id then break end
        end
        if id then
            any = true
            local lines = C.GetSpellLines(id)
            local s = key == "sor" and { base = NS.Parser.SealHit(lines) } or NS.Parser.Spell(lines)
            s.known, s.id, s.lines = true, id, lines
            out[key] = s
        else
            out[key] = { known = false }
        end
    end
    if not any then return nil end
    out.soc.known, out.sor.known = nil, nil   -- not having a Seal doesn't turn anything off
    return out
end

---------------------------------------------------------------- stats

-- Main hand weapon DPS and speed from its tooltip (enchant stripped).
local function mainHand()
    local link = call(GetInventoryItemLink, "player", 16)
    if not link then return nil end
    local stats = NS.ItemStats.Get(link)
    return stats and stats.wdps, stats and stats.speed
end

-- Reads every number the model needs. Returns state, list of estimated fields.
function Character.Read(fight, overrides)
    local st = NS.Model.DefaultState()
    local est = {}
    local function set(field, v)
        v = num(v)
        if v then
            st[field], lastGood[field] = v, v
        elseif lastGood[field] then
            st[field] = lastGood[field]
        else
            est[#est + 1] = field
        end
    end

    st.level = NS.BUILD.level   -- always computed as a level 60
    local base, pos, neg = call(UnitAttackPower, "player")
    set("ap", base and (num(base) or 0) + (num(pos) or 0) + (num(neg) or 0))
    set("crit", call(GetCritChance))
    set("hit", call(GetHitModifier) or (GetHitModifier and 0))
    set("spellhit", call(GetSpellHitModifier) or (GetSpellHitModifier and 0))
    set("spcrit", call(GetSpellCritChance, 2))           -- 2 = Holy
    set("sp", call(GetSpellBonusDamage, 2))
    set("speed", (call(UnitAttackSpeed, "player")))
    local skill, mod = call(UnitAttackBothHands, "player")
    set("wskill", skill and (num(skill) or 0) + (num(mod) or 0))

    local wdps, wspeed = mainHand()
    if not wdps then
        -- No readable weapon: back out weapon DPS from the damage on the sheet.
        local lo, hi = call(UnitDamage, "player")
        if lo and hi and st.speed > 0 then wdps = (lo + hi) / 2 / st.speed - st.ap / 14 end
    end
    set("wdps", wdps and math.max(0, wdps))
    if wspeed and not num(call(UnitAttackSpeed, "player")) then st.speed = wspeed end

    st.spells = Character.ReadSpells()
    if not st.spells then est[#est + 1] = "spell tooltips" end

    local talents = { holyStrike = 1 }   -- baseline ability, in the rotation unless you say otherwise
    for k, v in pairs(NS.BUILD.talents) do talents[k] = v end
    for k, v in pairs(overrides or {}) do talents[k] = v end
    st.talents = talents

    fight = fight or {}
    st.fight = {
        judge = fight.judge or NS.Model.DEFAULT_FIGHT.judge,
        execute = fight.execute or NS.Model.DEFAULT_FIGHT.execute,
        uwStacks = fight.uwstacks or NS.Model.DEFAULT_FIGHT.uwStacks,
    }
    st.target = fight.target or (st.level + 3)
    return st, est
end
