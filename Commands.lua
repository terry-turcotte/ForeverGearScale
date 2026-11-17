-- Commands.lua
-- /fgs (or /gearscale) — view and tune the weights in game.

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
    say("commands:")
    print("  /fgs status — class, spec and axis priority in use")
    print("  /fgs weights — list the weights in use")
    print("  /fgs spec auto||1||2||3 — pick the spec (auto = from talents)")
    print("  /fgs prio <dps> <def> <sus> — axis priority in % (e.g. 100 25 40)")
    print("  /fgs weight <stat> <dps> <def> <sus> — change one stat (e.g. hit 0 0 0 once hit-capped)")
    print("  /fgs reset — back to the preset for this spec")
    print("  /fgs export — print the weights as a string; /fgs import <string> to load one")
    print("  /fgs on||off — show or hide the tooltip lines")
end

local function changed()
    NS.Profile.Invalidate()
end

local handlers = {}

function handlers.status()
    local p = NS.Profile.Get()
    if not p then return say("no preset for this class.") end
    say(string.format("%s · %s (spec %d, %s)%s", p.classFile, p.specName, p.specIndex, p.source,
        p.overridden and " · custom weights" or ""))
    print(string.format("  priority: %s %d%% · %s %d%% · %s %d%%",
        p.axes[1], p.prio[1], p.axes[2], p.prio[2], p.axes[3], p.prio[3]))
    local t = p.talentPoints or {}
    print(string.format("  talent points read: %s / %s / %s", t[1] or "?", t[2] or "?", t[3] or "?"))
end

function handlers.weights()
    local p = NS.Profile.Get()
    if not p then return end
    say(p.specName .. " — points per stat (" .. table.concat(p.axes, " / ") .. "):")
    for _, s in ipairs(NS.STATS) do
        local w = p.weights[s.id]
        if w and (w[1] ~= 0 or w[2] ~= 0 or w[3] ~= 0) then
            print(string.format("  %-9s %s: %s", s.id, s.name, fmtW(w)))
        end
    end
end

function handlers.spec(arg)
    local _, classFile = UnitClass("player")
    if arg == "auto" then
        NS.db.specOverride[classFile] = nil
    else
        local n = tonumber(arg)
        if not n or n < 1 or n > 3 then return say("usage: /fgs spec auto||1||2||3") end
        NS.db.specOverride[classFile] = n
    end
    changed(); handlers.status()
end

function handlers.prio(arg)
    local a, b, c = (arg or ""):match("^(%d+)%s+(%d+)%s+(%d+)$")
    if not a then return say("usage: /fgs prio 100 25 40") end
    local p = NS.Profile.Get()
    NS.db.prio[p.key] = { tonumber(a), tonumber(b), tonumber(c) }
    changed(); handlers.status()
end

function handlers.weight(arg)
    local id, a, b, c = (arg or ""):match("^(%S+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)$")
    if not id or not NS.STAT_BY_ID[id] then
        return say("usage: /fgs weight <stat> <dps> <def> <sus> — stat ids: see /fgs weights")
    end
    local p = NS.Profile.Get()
    NS.db.weights[p.key] = NS.db.weights[p.key] or {}
    NS.db.weights[p.key][id] = { tonumber(a), tonumber(b), tonumber(c) }
    changed()
    say(NS.STAT_BY_ID[id].name .. " = " .. fmtW(NS.db.weights[p.key][id]))
end

function handlers.reset()
    local p = NS.Profile.Get()
    NS.db.weights[p.key], NS.db.prio[p.key] = nil, nil
    changed(); say("weights and priority reset to the " .. p.specName .. " preset.")
end

function handlers.export()
    local p = NS.Profile.Get()
    if not p then return end
    say("copy this string:")
    print(Commands.Export(p))
end

function handlers.import(arg)
    local weights, prio = Commands.ParseImport(arg or "")
    if not weights then return say("import failed: " .. tostring(prio)) end
    local p = NS.Profile.Get()
    NS.db.weights[p.key] = NS.db.weights[p.key] or {}
    for id, w in pairs(weights) do NS.db.weights[p.key][id] = w end
    if prio then NS.db.prio[p.key] = prio end
    changed(); say("imported into " .. p.specName .. ".")
end

function handlers.on() NS.db.enabled = true; say("on.") end
function handlers.off() NS.db.enabled = false; say("off.") end
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
