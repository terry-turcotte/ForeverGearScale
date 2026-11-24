-- Commands.lua
-- /fgs (or /gearscale) — see what the addon read, and tune it in game.

local _, NS = ...
local Commands = {}
NS.Commands = Commands

local P = "|cffe3bb5eGear Scale|r "
local function say(msg) print(P .. msg) end

local function fmtW(w) return string.format("%g", math.floor(w * 100 + 0.5) / 100) end

-- Export/import format: str=10;agi=3.5;...  (points per stat, 1 AP = 5).
-- Imports also accept the older 3-axis strings (str=10/0.3/0;...|prio=...):
-- only the DPS number is kept.
function Commands.Export(profile)
    local ids = {}
    for _, s in ipairs(NS.STATS) do
        local w = profile.weights[s.id]
        if w then  -- zeros included, so "hit = 0 once capped" survives a round trip
            ids[#ids + 1] = s.id .. "=" .. fmtW(w)
        end
    end
    return table.concat(ids, ";")
end

-- Returns weights or nil, error.
function Commands.ParseImport(str)
    local weights = {}
    local body = str:match("^(.-)|prio=") or str
    for id, v in body:gmatch("([%w_]+)=(%-?[%d%.]+)") do
        if NS.STAT_BY_ID[id] then weights[id] = tonumber(v) end
    end
    if not next(weights) then return nil, "nothing recognised" end
    return weights
end

local function help()
    say("commands (Retribution Paladin):")
    print("  /fgs status — character stats read, the model's DPS and Vengeance uptime")
    print("  /fgs weights — points per stat, live from your stats (1 AP = 5, * = pinned by you)")
    print("  /fgs weight <stat> <points> — pin one stat's weight (no longer live)")
    print("  /fgs unpin <stat> — let that stat follow the model again")
    print("  /fgs set target||judge||execute <value> — boss level, sec between Judgements, execute share (0-1)")
    print("  /fgs build — the talent build used (12/8/31) and what each talent does in the model")
    print("  /fgs set <talent> <rank||auto> — change a rank: divinestrength, divineintellect, improvedseals,")
    print("      precision, vengeance, champion, arbiter, unsealed (auto = back to the build)")
    print("  /fgs set uwstacks 2||3 — Unsealed Wrath: Command stacks you bank before the Righteousness swing")
    print("  /fgs set holystrike 0||1 — take Holy Strike out of (or back into) the rotation")
    print("  /fgs reset — unpin everything, default fight and talent settings")
    print("  /fgs export — print the weights as a string; /fgs import <string> to pin them")
    print("  /fgs spells — Hammer of Wrath, Holy Strike, Seal of Command numbers read from your spellbook")
    print("  /fgs on||off — show or hide the tooltip lines")
end

local function changed()
    NS.Profile.Invalidate()
end

local function profileOrSay()
    local p = NS.Profile.Get()
    if not p then say("this addon only scores gear for Paladins.") end
    return p
end

local handlers = {}

function handlers.status()
    local p = profileOrSay()
    if not p then return end
    local st, t = p.state, p.state.talents
    say(string.format("Retribution · model %.0f DPS vs a level %d target%s", p.dps, st.target,
        p.overridden and " · some weights pinned" or ""))
    print(string.format("  AP %d · crit %.2f%% · hit %.1f%% · weapon skill %d · weapon %.1f DPS, %.2f speed",
        st.ap, st.crit, st.hit, st.wskill, st.wdps, st.speed))
    print(string.format("  Holy spell damage %d · spell crit %.2f%% · spell hit %.1f%%", st.sp, st.spcrit, st.spellhit))
    print(string.format("  build %s as a level %d: Divine Strength %d · Divine Intellect %d · Improved Seals %d · Precision %d",
        NS.BUILD.name, st.level, t.divineStrength or 0, t.divineIntellect or 0, t.improvedSeals or 0, t.precision or 0))
    print(string.format("    Vengeance %d · Champion of the Light %d · Sacred Arbiter %d · Unsealed Wrath %d · Holy Strike %s (/fgs build)",
        t.vengeance or 0, t.champion or 0, t.sacredArbiter or 0, t.unsealedWrath or 0,
        (t.holyStrike or 1) > 0 and "on" or "off"))
    if (t.unsealedWrath or 0) > 0 then
        local M = NS.Model
        local function at(n)
            local c = {}
            for k, v in pairs(st) do c[k] = v end
            c.fight = { judge = st.fight.judge, execute = st.fight.execute, uwStacks = n }
            return (M.Dps(c))
        end
        local off = {}
        for k, v in pairs(st) do off[k] = v end
        off.talents = {}
        for k, v in pairs(t) do off.talents[k] = v end
        off.talents.unsealedWrath = 0
        local base = M.Dps(off)
        print(string.format("  Unsealed Wrath (swap at %d stacks): +%.1f DPS · at 2 stacks %.0f DPS, at 3 stacks %.0f DPS",
            st.fight.uwStacks, p.dps - base, at(2), at(3)))
    end
    local how = (p.parts.how or 0) > 0 and "yes"
        or (st.level < NS.Model.CONST.howLevel and ("no, learned at " .. NS.Model.CONST.howLevel))
        or ((st.spells and st.spells.how and st.spells.how.known == false) and "no, not in your spellbook")
        or "no"
    print("  Hammer of Wrath: " .. how .. " · spell numbers from "
        .. (st.spells and "your spell tooltips (/fgs spells)" or "built-in defaults"))
    local x = p.parts
    print(string.format("  melee miss %.1f%% · spell miss %.0f%% · Vengeance %.1f stacks avg (+%.1f%% damage)",
        x.miss * 100, x.spellMiss * 100, x.stacks, x.vengeance * 100))
    print(string.format("  DPS: white %.0f · Seal of Command %.0f · Righteousness %.0f · Holy Strike %.0f · Judgement %.0f · Hammer %.0f",
        x.white, x.soc, x.sor, x.holyStrike, x.joc, x.how))
    if #p.estimated > 0 then
        print("  not readable, using defaults: " .. table.concat(p.estimated, ", "))
    end
end

function handlers.weights()
    local p = profileOrSay()
    if not p then return end
    say("DPS points per stat (1 AP = 5 pts):")
    for _, s in ipairs(NS.STATS) do
        local w = p.weights[s.id]
        if w and w ~= 0 or p.pinned[s.id] then
            print(string.format("  %s%-9s %s: %s", p.pinned[s.id] and "*" or " ", s.id, s.name, fmtW(w)))
        end
    end
end

function handlers.weight(arg)
    local id, v = (arg or ""):match("^(%S+)%s+(%-?[%d%.]+)$")
    if not id or not NS.STAT_BY_ID[id] then
        return say("usage: /fgs weight <stat> <points> — stat ids: see /fgs weights")
    end
    NS.db.pins[id] = tonumber(v)
    changed()
    say(NS.STAT_BY_ID[id].name .. " pinned at " .. fmtW(NS.db.pins[id]))
end

function handlers.unpin(arg)
    if not NS.db.pins[arg or ""] then return say("not pinned: " .. tostring(arg)) end
    NS.db.pins[arg] = nil
    changed(); say(NS.STAT_BY_ID[arg].name .. " follows the model again.")
end

local FIGHT = { target = { 1, 83 }, judge = { 1, 60 }, execute = { 0, 1 }, uwstacks = { 1, 3 } }
local TALENT = { vengeance = "vengeance", champion = "champion", arbiter = "sacredArbiter",
    unsealed = "unsealedWrath", divinestrength = "divineStrength", divineintellect = "divineIntellect",
    improvedseals = "improvedSeals", precision = "precision", holyconduit = "holyConduit", sacredduty = "sacredDuty",
    holystrike = "holyStrike" }

function handlers.set(arg)
    local key, val = (arg or ""):lower():match("^(%S+)%s+(%S+)$")
    local n = tonumber(val)
    if key and FIGHT[key] then
        if val == "auto" then NS.db.fight[key] = nil
        elseif n and n >= FIGHT[key][1] and n <= FIGHT[key][2] then NS.db.fight[key] = n
        else return say(string.format("%s must be between %g and %g, or auto", key, FIGHT[key][1], FIGHT[key][2])) end
    elseif key and TALENT[key] then
        if val == "auto" then NS.db.talents[TALENT[key]] = nil
        elseif n and n >= 0 and n <= (NS.BUILD.maxRank[TALENT[key]] or 1) then NS.db.talents[TALENT[key]] = n
        else return say(string.format("%s must be a rank from 0 to %d, or auto", key, NS.BUILD.maxRank[TALENT[key]] or 1)) end
    else
        return say("usage: /fgs set target||judge||execute||uwstacks||holystrike <value> or /fgs set <talent> <rank> (see /fgs build)")
    end
    changed(); handlers.status()
end

function handlers.reset()
    NS.db.pins, NS.db.fight, NS.db.talents = {}, {}, {}
    changed(); say("weights unpinned; fight settings and talents back to the " .. NS.BUILD.name .. " build.")
end

function handlers.export()
    local p = profileOrSay()
    if not p then return end
    say("copy this string:")
    print(Commands.Export(p))
end

function handlers.import(arg)
    local weights, err = Commands.ParseImport(arg or "")
    if not weights then return say("import failed: " .. tostring(err)) end
    for id, w in pairs(weights) do NS.db.pins[id] = w end
    changed(); say("imported (those stats are now pinned; /fgs reset to go back to live weights).")
end

function handlers.on() NS.db.enabled = true; say("on.") end
function handlers.off() NS.db.enabled = false; say("off.") end
-- Raw talent API dump, to check talent reading on a client we can't test.
local function show(v)
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for k, x in pairs(v) do
        if type(x) ~= "table" and type(x) ~= "function" then parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ", ") .. "}"
end

function handlers.build()
    local B, t = NS.BUILD, NS.db.talents
    say("talent build " .. B.name .. " (computed as a level " .. B.level .. "; * = changed by you):")
    for _, e in ipairs(B.order) do
        local key, label = e[1], e[2]
        local rank = t[key] or B.talents[key]
        print(string.format("  %s%s %d/%d — %s", t[key] and "*" or " ", label, rank, B.maxRank[key], B.effect[key]))
    end
    print("  change one: /fgs set <talent> <rank>, e.g. /fgs set improvedseals 3 (auto = back to the build)")
end
handlers.talents = handlers.build

local SPELL_LABEL = { how = "Hammer of Wrath", holyStrike = "Holy Strike", soc = "Seal of Command (Judgement)",
    sor = "Seal of Righteousness (per hit)" }

function handlers.spells()
    local spells = NS.Character.ReadSpells()
    if not spells then
        return say("no spell found in your spellbook (unknown client language or spell API): using built-in numbers.")
    end
    local K = NS.Model.CONST
    local DEF = {
        how = { base = K.howBase, cd = K.howCD }, holyStrike = { base = K.holyStrikeBase, weapon = K.holyStrikeWeapon, cd = K.holyStrikeCD },
        soc = { base = K.jocBase, weapon = K.socWeapon }, sor = { base = K.sorBase },
    }
    say("spell numbers read from your spellbook (default in brackets when not found):")
    for _, key in ipairs({ "how", "holyStrike", "soc", "sor" }) do
        local sp, d = spells[key], DEF[key]
        if sp.id then
            local function f(field, fmt)
                if sp[field] then return string.format(fmt, sp[field]) end
                if d[field] then return "[" .. string.format(fmt, d[field]) .. "]" end
                return "-"
            end
            print(string.format("  %s (id %s): damage %s · weapon %s · cooldown %s", SPELL_LABEL[key], tostring(sp.id),
                f("base", "%.1f"), sp.weapon and string.format("%d%%", sp.weapon * 100)
                    or (d.weapon and string.format("[%d%%]", d.weapon * 100) or "-"), f("cd", "%g sec")))
            local text = table.concat(sp.lines or {}, " / ")
            if #text > 200 then text = text:sub(1, 200) .. "..." end
            print("    " .. text)
        else
            print("  " .. SPELL_LABEL[key] .. ": not in your spellbook")
        end
    end
end

function handlers.debug() NS.db.debug = not NS.db.debug; say("debug " .. (NS.db.debug and "on" or "off")) end
function handlers.hint() NS.db.showHint = not NS.db.showHint; say("shift hint " .. (NS.db.showHint and "on" or "off")) end

function Commands.Run(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local h = handlers[(cmd or ""):lower()]
    if h then h(arg) else help() end
end

function Commands.Init()
    SLASH_FOREVERGEARSCALE1 = "/fgs"
    SLASH_FOREVERGEARSCALE2 = "/gearscale"
    SlashCmdList.FOREVERGEARSCALE = Commands.Run
end
