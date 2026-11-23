-- Character.lua
-- Reads the live character sheet and talents through the Blizzard API and
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

---------------------------------------------------------------- talents

-- Talents we model, by name (English and French clients).
local TALENTS = {
    vengeance = { "vengeance" },
    champion = { "champion of the light", "champion de la lumière" },
    sacredArbiter = { "sacred arbiter", "arbitre sacré" },
    unsealedWrath = { "unsealed wrath", "courroux descellé" },
}
local MAX_RANK = { vengeance = 3, champion = 5, sacredArbiter = 1, unsealedWrath = 1 }
local BY_NAME = {}
for key, names in pairs(TALENTS) do for _, n in ipairs(names) do BY_NAME[n] = key end end

local CSI = function() return C_SpecializationInfo or {} end

-- Forever has no GetTalentInfo global; C_SpecializationInfo.GetTalentInfo
-- exists but its query shape isn't documented. We try every shape the modern
-- clients use, keep the first one that answers, and /fgs talents prints what
-- each one returns.

-- name, rank, maxRank from one call's results ({ ok, ... }); nil if empty.
local function parse(r)
    if not r[1] then return nil end
    local v = r[2]
    if type(v) == "table" then
        local name = v.name or v.talentName
        if not name and v.spellID and C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, v.spellID)
            name = ok and type(info) == "table" and info.name or nil
        end
        if type(name) ~= "string" or C.IsSecret(name) then return nil end
        local rank = v.rank or v.currentRank or v.pointsSpent or v.points or v.ranksPurchased
        -- Only "selected" and no rank: taken at its max rank (most builds max these).
        if rank == nil then rank = (v.selected or v.known or v.isSelected) and (v.maxRank or "max") or 0 end
        return name, rank, v.maxRank or v.maxRanks or v.numRanks
    end
    if type(v) == "string" and not C.IsSecret(v) then return v, r[6], r[7] end  -- name, icon, tier, column, rank, maxRank
end

-- Talent i of tree tab.
local INDEX_SHAPES = {
    { label = "GetTalentInfo(tab, i)", fn = function() return GetTalentInfo end,
      call = function(f, tab, i) return { pcall(f, tab, i) } end },
    { label = "{specializationIndex, talentIndex}", fn = function() return CSI().GetTalentInfo end,
      call = function(f, tab, i) return { pcall(f, { specializationIndex = tab, talentIndex = i }) } end },
    { label = "{specializationIndex, talentIndex, groupIndex}", fn = function() return CSI().GetTalentInfo end,
      call = function(f, tab, i) return { pcall(f, { specializationIndex = tab, talentIndex = i, groupIndex = 1, isInspect = false }) } end },
    { label = "{tabIndex, talentIndex}", fn = function() return CSI().GetTalentInfo end,
      call = function(f, tab, i) return { pcall(f, { tabIndex = tab, talentIndex = i }) } end },
    { label = "(tab, i)", fn = function() return CSI().GetTalentInfo end,
      call = function(f, tab, i) return { pcall(f, tab, i) } end },
}
-- Talent at tier/column (row/column of the tree), possibly with the tree.
local GRID_SHAPES = {
    { label = "{specializationIndex, tier, column}", fn = function() return CSI().GetTalentInfo end,
      call = function(f, tab, r, c) return { pcall(f, { specializationIndex = tab, tier = r, column = c }) } end },
    { label = "{tier, column, groupIndex}", fn = function() return CSI().GetTalentInfo end, noTab = true,
      call = function(f, _, r, c) return { pcall(f, { tier = r, column = c, groupIndex = 1, isInspect = false }) } end },
}
Character.TALENT_SHAPES = { index = INDEX_SHAPES, grid = GRID_SHAPES }

local function numTabs()
    local f = GetNumTalentTabs or CSI().GetNumSpecializations
    local n = num(call(f))
    return (n and n > 0) and math.min(n, 3) or 3
end

local workingShape   -- the shape that answered last time

-- All talents as { name, rank } with one shape; empty if it gives nothing.
local function readWith(shape, isGrid)
    local f = shape.fn()
    if not f then return {} end
    local list = {}
    local numFn = GetNumTalents or CSI().GetNumTalents
    for tab = 1, (shape.noTab and 1 or numTabs()) do
        if isGrid then
            for r = 1, 11 do
                for c = 1, 4 do
                    local name, rank = parse(shape.call(f, tab, r, c))
                    if name then list[#list + 1] = { name, rank } end
                end
            end
        else
            local n = num(call(numFn, tab))
            for i = 1, n or 40 do
                local name, rank = parse(shape.call(f, tab, i))
                if name == nil then break end
                list[#list + 1] = { name, rank }
            end
        end
    end
    return list
end

local function readAll()
    if workingShape then
        local list = readWith(workingShape.shape, workingShape.grid)
        if #list > 0 then return list, workingShape.shape.label end
    end
    for _, sh in ipairs(INDEX_SHAPES) do
        local list = readWith(sh, false)
        if #list > 0 then workingShape = { shape = sh, grid = false }; return list, sh.label end
    end
    for _, sh in ipairs(GRID_SHAPES) do
        local list = readWith(sh, true)
        if #list > 0 then workingShape = { shape = sh, grid = true }; return list, sh.label end
    end
    return {}, nil
end

-- Returns { vengeance = r, champion = r, sacredArbiter = r, unsealedWrath = r },
-- whether the talent API answered at all, and which call shape worked.
function Character.ReadTalents()
    local out = { vengeance = 0, champion = 0, sacredArbiter = 0, unsealedWrath = 0 }
    local list, how = readAll()
    for _, t in ipairs(list) do
        local key = BY_NAME[t[1]:lower()]
        if key then out[key] = t[2] == "max" and MAX_RANK[key] or num(t[2]) or 0 end
    end
    return out, #list > 0, how, #list
end

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

    set("level", call(UnitLevel, "player"))
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

    local talents, readable = Character.ReadTalents()
    if not readable then est[#est + 1] = "talents" end
    talents.holyStrike = 1   -- baseline ability, in the rotation unless you say otherwise
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
