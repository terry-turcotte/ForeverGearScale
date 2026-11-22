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
    print("  /fgs status — character stats and talents read, the model's DPS and Vengeance uptime")
    print("  /fgs weights — points per stat, live from your stats (1 AP = 5, * = pinned by you)")
    print("  /fgs weight <stat> <points> — pin one stat's weight (no longer live)")
    print("  /fgs unpin <stat> — let that stat follow the model again")
    print("  /fgs set target||judge||execute <value> — boss level, sec between Judgements, execute share (0-1)")
    print("  /fgs set vengeance||champion||arbiter <rank||auto> — talent rank if the client can't read it")
    print("  /fgs set holystrike 0||1 — take Holy Strike out of (or back into) the rotation")
    print("  /fgs reset — unpin everything, default fight and talent settings")
    print("  /fgs export — print the weights as a string; /fgs import <string> to pin them")
    print("  /fgs talents — dump what the talent API returns (for bug reports)")
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
    print(string.format("  talents: Vengeance %d · Champion of the Light %d · Sacred Arbiter %d · Holy Strike %s",
        t.vengeance or 0, t.champion or 0, t.sacredArbiter or 0, (t.holyStrike or 1) > 0 and "on" or "off"))
    local how = (p.parts.how or 0) > 0 and "yes"
        or (st.level < NS.Model.CONST.howLevel and ("no, learned at " .. NS.Model.CONST.howLevel))
        or ((st.spells and st.spells.how and st.spells.how.known == false) and "no, not in your spellbook")
        or "no"
    print("  Hammer of Wrath: " .. how .. " · spell numbers from "
        .. (st.spells and "your spell tooltips (/fgs spells)" or "built-in defaults"))
    local x = p.parts
    print(string.format("  melee miss %.1f%% · spell miss %.0f%% · Vengeance %.1f stacks avg (+%.1f%% damage)",
        x.miss * 100, x.spellMiss * 100, x.stacks, x.vengeance * 100))
    print(string.format("  DPS: white %.0f · Seal of Command %.0f · Holy Strike %.0f · Judgement %.0f · Hammer %.0f",
        x.white, x.soc, x.holyStrike, x.joc, x.how))
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

local FIGHT = { target = { 1, 83 }, judge = { 1, 60 }, execute = { 0, 1 } }
local TALENT = { vengeance = "vengeance", champion = "champion", arbiter = "sacredArbiter",
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
        elseif n and n >= 0 and n <= 5 then NS.db.talents[TALENT[key]] = n
        else return say(key .. " must be a rank from 0 to 5, or auto") end
    else
        return say("usage: /fgs set target||judge||execute||vengeance||champion||arbiter||holystrike <value||auto>")
    end
    changed(); handlers.status()
end

function handlers.reset()
    NS.db.pins, NS.db.fight, NS.db.talents = {}, {}, {}
    changed(); say("weights unpinned; fight and talent settings back to default.")
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

function handlers.talents()
    local CSI = C_SpecializationInfo or {}
    say("talent API on this client:")
    local fns = {}
    for _, name in ipairs({ "GetNumTalentTabs", "GetNumTalents", "GetTalentInfo" }) do
        fns[#fns + 1] = name .. (_G[name] and "+" or "-")
    end
    print("  globals: " .. table.concat(fns, " ") .. " · C_SpecializationInfo.GetTalentInfo"
        .. (CSI.GetTalentInfo and "+" or "-"))
    if GetTalentInfo then
        local r = { pcall(GetTalentInfo, 3, 1) }
        local out = {}
        for i = 2, math.max(#r, 2) do out[#out + 1] = show(r[i]) end
        print("  talent 3,1: " .. (r[1] and "" or "ERROR ") .. table.concat(out, ", "))
    end
    local t, any = NS.Character.ReadTalents()
    print(string.format("  read: Vengeance %d · Champion of the Light %d · Sacred Arbiter %d%s",
        t.vengeance, t.champion, t.sacredArbiter, any and "" or " (talent API gave nothing)"))
end

local SPELL_LABEL = { how = "Hammer of Wrath", holyStrike = "Holy Strike", soc = "Seal of Command (Judgement)" }

function handlers.spells()
    local spells = NS.Character.ReadSpells()
    if not spells then
        return say("no spell found in your spellbook (unknown client language or spell API): using built-in numbers.")
    end
    local K = NS.Model.CONST
    local DEF = {
        how = { base = K.howBase, cd = K.howCD }, holyStrike = { base = K.holyStrikeBase, weapon = K.holyStrikeWeapon, cd = K.holyStrikeCD },
        soc = { base = K.jocBase, weapon = K.socWeapon },
    }
    say("spell numbers read from your spellbook (default in brackets when not found):")
    for _, key in ipairs({ "how", "holyStrike", "soc" }) do
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
