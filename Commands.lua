-- Commands.lua
-- /fgs (or /gearscale) — see what the addon read, and tune it in game.

local _, NS = ...
local Commands = {}
NS.Commands = Commands

local P = "|cffe3bb5eGear Scale|r "
local function say(msg) print(P .. msg) end

local function fmtW(w) return string.format("%g / %g / %g", w[1], w[2], w[3]) end

-- Export/import format, shared with the web page:
--   str=10/0.3/0;agi=3.5/4/0;...|prio=100/25/40
function Commands.Export(profile)
    local ids = {}
    for _, s in ipairs(NS.STATS) do
        local w = profile.weights[s.id]
        if w then  -- zeros included, so "hit = 0 once capped" survives a round trip
            ids[#ids + 1] = string.format("%s=%g/%g/%g", s.id, w[1], w[2], w[3])
        end
    end
    local p = profile.prio
    return table.concat(ids, ";") .. string.format("|prio=%g/%g/%g", p[1], p[2], p[3])
end

-- Returns weights, prio (either may be nil) or nil, error.
function Commands.ParseImport(str)
    local weights, prio = {}, nil
    local body, prioPart = str:match("^(.-)|prio=(.+)$")
    body = body or str
    if prioPart then
        local a, b, c = prioPart:match("^%s*([%d%.]+)/([%d%.]+)/([%d%.]+)")
        if not a then return nil, "bad prio" end
        prio = { tonumber(a), tonumber(b), tonumber(c) }
    end
    for id, a, b, c in body:gmatch("([%w_]+)=(%-?[%d%.]+)/(%-?[%d%.]+)/(%-?[%d%.]+)") do
        if NS.STAT_BY_ID[id] then weights[id] = { tonumber(a), tonumber(b), tonumber(c) } end
    end
    if not next(weights) and not prio then return nil, "nothing recognised" end
    return weights, prio
end

local function help()
    say("commands (Retribution Paladin):")
    print("  /fgs status — character stats and talents read, the model's DPS and Vengeance uptime")
    print("  /fgs weights — the weights in use (DPS ones are live, * = pinned by you)")
    print("  /fgs prio <dps> <def> <sus> — axis priority in % (e.g. 100 25 40)")
    print("  /fgs weight <stat> <dps> <def> <sus> — pin one stat's weight (no longer live)")
    print("  /fgs unpin <stat> — let that stat follow the model again")
    print("  /fgs set target||judge||execute <value> — boss level, sec between Judgements, execute share (0-1)")
    print("  /fgs set vengeance||champion||arbiter <rank||auto> — talent rank if the client can't read it")
    print("  /fgs set holystrike 0||1 — take Holy Strike out of (or back into) the rotation")
    print("  /fgs reset — unpin everything, default priority and fight settings")
    print("  /fgs export — print the weights as a string; /fgs import <string> to pin them")
    print("  /fgs talents — dump what the talent API returns (for bug reports)")
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
    local x = p.parts
    print(string.format("  melee miss %.1f%% · spell miss %.0f%% · Vengeance %.1f stacks avg (+%.1f%% damage)",
        x.miss * 100, x.spellMiss * 100, x.stacks, x.vengeance * 100))
    print(string.format("  DPS: white %.0f · Seal of Command %.0f · Holy Strike %.0f · Judgement %.0f · Hammer %.0f",
        x.white, x.soc, x.holyStrike, x.joc, x.how))
    print(string.format("  priority: %s %d%% · %s %d%% · %s %d%%",
        p.axes[1], p.prio[1], p.axes[2], p.prio[2], p.axes[3], p.prio[3]))
    if #p.estimated > 0 then
        print("  not readable, using defaults: " .. table.concat(p.estimated, ", "))
    end
end

function handlers.weights()
    local p = profileOrSay()
    if not p then return end
    say("points per stat (" .. table.concat(p.axes, " / ") .. "), 1 AP = 5 pts:")
    for _, s in ipairs(NS.STATS) do
        local w = p.weights[s.id]
        if w and (w[1] ~= 0 or w[2] ~= 0 or w[3] ~= 0) then
            local w1 = math.floor(w[1] * 100 + 0.5) / 100
            print(string.format("  %s%-9s %s: %s", p.pinned[s.id] and "*" or " ", s.id, s.name,
                fmtW({ w1, w[2], w[3] })))
        end
    end
end

function handlers.prio(arg)
    local a, b, c = (arg or ""):match("^(%d+)%s+(%d+)%s+(%d+)$")
    if not a then return say("usage: /fgs prio 100 25 40") end
    NS.db.prio = { tonumber(a), tonumber(b), tonumber(c) }
    changed(); handlers.status()
end

function handlers.weight(arg)
    local id, a, b, c = (arg or ""):match("^(%S+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)$")
    if not id or not NS.STAT_BY_ID[id] then
        return say("usage: /fgs weight <stat> <dps> <def> <sus> — stat ids: see /fgs weights")
    end
    NS.db.pins[id] = { tonumber(a), tonumber(b), tonumber(c) }
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
    NS.db.pins, NS.db.fight, NS.db.talents, NS.db.prio = {}, {}, {}, nil
    changed(); say("weights unpinned; priority, fight and talent settings back to default.")
end

function handlers.export()
    local p = profileOrSay()
    if not p then return end
    say("copy this string:")
    print(Commands.Export(p))
end

function handlers.import(arg)
    local weights, prio = Commands.ParseImport(arg or "")
    if not weights then return say("import failed: " .. tostring(prio)) end
    for id, w in pairs(weights) do NS.db.pins[id] = w end
    if prio then NS.db.prio = prio end
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
