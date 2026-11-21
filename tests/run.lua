-- Offline tests: run from the addon folder with  lua5.1 tests/run.lua
-- Stubs just enough of the WoW API to load every addon file in TOC order and
-- drive a full tooltip comparison.

local ROOT = (arg and arg[0] or ""):match("^(.*)tests[/\\]run%.lua$") or "./"

---------------------------------------------------------------- tiny runner
local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1 else failed = failed + 1; (print_real or print)("FAIL " .. name .. "\n     " .. tostring(err)) end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function near(a, b, msg)
    if math.abs(a - b) > 1e-6 then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

---------------------------------------------------------------- fake game
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
SlashCmdList = {}
local printed = {}
print_real = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

local ITEMS = {}       -- link -> { equipLoc = ..., lines = {...} }
local EQUIPPED = {}    -- slot -> link
local PLAYER = { class = "PALADIN" }
local SHIFT = false

C_Item = { GetItemInfoInstant = function(link)
    local it = ITEMS[(link:gsub("(item:%-?%d+):[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*", "%1:::::"))] or ITEMS[link]
    if it then return 1, "Armor", "Plate", it.equipLoc end
end }
C_TooltipInfo = { GetHyperlink = function(link)
    local it = ITEMS[link]
    if not it then return nil end
    local lines = {}
    for i, t in ipairs(it.lines) do lines[i] = { leftText = t } end
    return { lines = lines }
end }
function UnitClass() return "Paladin", PLAYER.class end
-- Character sheet: a geared level 60 Ret.
local SHEET = { level = 60, ap = 1200, crit = 20, hit = 5, spellhit = 0, spcrit = 9, sp = 80,
    speed = 3.6, skill = 300 }
function UnitLevel() return SHEET.level end
function UnitAttackPower() return SHEET.ap - 200, 200, 0 end
function GetCritChance() return SHEET.crit end
function GetHitModifier() return SHEET.hit end
function GetSpellHitModifier() return SHEET.spellhit end
function GetSpellCritChance() return SHEET.spcrit end
function GetSpellBonusDamage() return SHEET.sp end
function UnitAttackSpeed() return SHEET.speed end
function UnitAttackBothHands() return SHEET.skill, 0 end
function UnitDamage()   -- 60 weapon DPS at 3.6 speed, AP included
    local avg = (60 + SHEET.ap / 14) * SHEET.speed
    return avg - 20, avg + 20
end
-- Talents: Retribution tree like the screenshots (names, ranks).
local TALENTS = {
    { { "Divine Strength", 0, 5 }, { "Holy Shock", 0, 1 } },
    { { "Redoubt", 0, 5 } },
    { { "Benediction", 5, 5 }, { "Conviction", 1, 5 }, { "Vengeance", 3, 3 }, { "Champion of the Light", 5, 5 },
        { "Sacred Arbiter", 1, 1 } },
}
function GetNumTalentTabs() return 3 end
function GetNumTalents(tab) return #TALENTS[tab] end
function GetTalentInfo(tab, i)
    local t = TALENTS[tab][i]
    if t then return t[1], "icon", 1, i, t[2], t[3] end
end
function GetInventoryItemLink(_, slot) return EQUIPPED[slot] end
function IsShiftKeyDown() return SHIFT end

-- Fake tooltip that records added lines.
local function newTooltip()
    local tt = { lines = {}, item = nil }
    function tt:AddLine(t) self.lines[#self.lines + 1] = t end
    function tt:AddDoubleLine(l, r) self.lines[#self.lines + 1] = l .. " || " .. r end
    function tt:Show() end
    function tt:GetItem() return "name", self.item end
    return tt
end
GameTooltip = newTooltip()
ItemRefTooltip = newTooltip()

local postCall
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) postCall = fn end }
Enum = { TooltipDataType = { Item = 0 } }

local events = {}
function CreateFrame()
    local f = { registered = {} }
    function f:RegisterEvent(e) self.registered[e] = true end
    function f:SetScript(_, fn) events.handler = fn; events.frame = self end
    return f
end

---------------------------------------------------------------- load addon
local NS = {}
local toc = io.open(ROOT .. "ForeverGearScale.toc"):read("*a")
for file in toc:gmatch("[^\r\n]+") do
    if not file:match("^##") and file:match("%S") then
        local path = ROOT .. file:gsub("\\", "/")
        local chunk = assert(loadfile(path))
        chunk("ForeverGearScale", NS)
    end
end
events.handler(events.frame, "ADDON_LOADED", "ForeverGearScale")
events.handler(events.frame, "PLAYER_LOGIN")

local function item(id, equipLoc, lines)
    local link = "|cffa335ee|Hitem:" .. id .. ":::::|h[" .. lines[1] .. "]|h|r"
    ITEMS[link] = { equipLoc = equipLoc, lines = lines }
    return link
end
local function hover(link, tt)
    tt = tt or GameTooltip
    tt.lines, tt.item = {}, link
    postCall(tt)
    return table.concat(tt.lines, "\n")
end

---------------------------------------------------------------- parser
test("parser: English vanilla tooltip", function()
    local s, miss = NS.Parser.Parse({
        "Lionheart Helm", "Binds when picked up", "Head  Plate", "565 Armor",
        "+18 Strength", "Durability 100 / 100", "Requires Level 60",
        "Equip: Improves your chance to get a critical strike by 2%.",
        "Equip: Improves your chance to hit by 2%.",
        "Equip: Restores 4 mana per 5 sec.",
        "Use: Increases your Strength by 50 for 20 sec.",
        "Chance on hit: Increases your attack power by 100 for 10 sec.",
        "(3) Set: +40 Attack Power.",
        "\"A helm forged for kings.\"",
    })
    eq(s.str, 18, "str"); eq(s.armor, 565, "armor"); eq(s.crit, 2, "crit"); eq(s.hit, 2, "hit"); eq(s.mp5, 4, "mp5")
    eq(s.ap, nil, "proc/set AP must not count")
    eq(#miss, 2, "use + chance on hit reported")
end)

test("parser: French tooltip", function()
    local s = NS.Parser.Parse({
        "Heaume de cœur-de-lion", "Tête  Plaques", "565 Armure", "+18 Force", "+10 Endurance",
        "Équipé : Augmente vos chances d'infliger un coup critique de 2%.",
        "Équipé : Augmente vos chances de toucher de 1%.",
        "Équipé : Rend 4 points de mana toutes les 5 sec.",
        "Équipé : +30 à la puissance d'attaque.",
    })
    eq(s.str, 18); eq(s.sta, 10); eq(s.armor, 565); eq(s.crit, 2); eq(s.hit, 1); eq(s.mp5, 4); eq(s.ap, 30)
end)

test("parser: caster, weapon and defense lines", function()
    local s = NS.Parser.Parse({
        "Some Staff", "Two-Hand  Staff", "(54.3 damage per second)", "+10 Intellect +12 Stamina",
        "+10 Fire Resistance",
        "Equip: Increases damage and healing done by magical spells and effects by up to 23.",
        "Equip: Improves your chance to get a critical strike with spells by 1%.",
        "Equip: Increases healing done by spells and effects by up to 22.",
        "Equip: Increased Defense +7.",
        "Equip: Increased Swords +5.",
        "Equip: +24 Ranged Attack Power.",
        "Equip: +36 Attack Power when fighting Undead.",
    })
    near(s.wdps, 54.3); eq(s.int, 10); eq(s.sta, 12); eq(s.res, 10); eq(s.spboth, 23)
    eq(s.spcrit, 1); eq(s.heal, 22); eq(s.def, 7); eq(s.wskill, 5); eq(s.rap, 24); eq(s.ap, nil)
end)

---------------------------------------------------------------- data
test("parser: weapon speed from the right-hand text", function()
    local s = NS.Parser.Parse({ "Axe", "Two-Hand  Axe", "Speed 3.80", "(60.5 damage per second)" })
    near(s.speed, 3.8); near(s.wdps, 60.5)
    eq(NS.Parser.Parse({ "Hache", "Vitesse 3,60" }).speed, 3.6)
end)

test("weights: Retribution table only, known stats", function()
    eq(NS.PRESETS, nil, "the other classes are gone")
    for id, w in pairs(NS.RET.weights) do
        assert(NS.STAT_BY_ID[id], "unknown stat " .. id); eq(#w, 3, id)
    end
    eq(NS.RET.weights.sta[2], 10); eq(NS.RET.weights.int[3], 6)
end)

---------------------------------------------------------------- model
local M = NS.Model
local function state(over)
    local st = M.DefaultState()
    st.talents = { vengeance = 3, champion = 5, sacredArbiter = 1, holyStrike = 1 }
    for k, v in pairs(over or {}) do st[k] = v end
    return st
end

test("model: Vengeance stacks, exact chain", function()
    eq(M.VengeanceStacks(0, 15), 0); eq(M.VengeanceStacks(1, 15), 5)
    -- one event per window: every non-crit drops the buff
    -- p = 0.5, n = 1: stays at s with prob 1/2 per step -> simple check against a simulation
    local a, b, c = M.VengeanceStacks(0.1, 15), M.VengeanceStacks(0.2, 15), M.VengeanceStacks(0.3, 15)
    assert(a < b and b < c and c < 5, "more crit, more stacks")
    assert((b - a) > (c - b), "diminishing returns")
    -- Monte Carlo cross-check
    math.randomseed(7)
    local stacks, gap, sum, N = 0, 0, 0, 200000
    for _ = 1, N do
        sum = sum + stacks
        if math.random() < 0.2 then stacks, gap = math.min(5, stacks + 1), 0
        else gap = gap + 1; if gap >= 15 then stacks, gap = 0, 0 end end
    end
    assert(math.abs(sum / N - b) < 0.05, "sim " .. sum / N .. " vs " .. b)
end)

test("model: hit is worth nothing past the cap", function()
    assert(M.Weights(state({ hit = 5 })).hit > 50)
    near(M.Weights(state({ hit = 9 })).hit, 0)
    near(M.Weights(state({ hit = 12 })).hit, 0)
    local sh = M.Weights(state({ spellhit = 16 }))
    near(sh.spellhit, 0)
end)

test("model: crit loses value as Vengeance saturates; no Vengeance, flatter", function()
    local lo, hi = M.Weights(state({ crit = 10 })).crit, M.Weights(state({ crit = 30 })).crit
    assert(lo > hi * 1.5, lo .. " vs " .. hi)
    local nv = state({ crit = 10 }); nv.talents = { vengeance = 0, champion = 5, sacredArbiter = 1, holyStrike = 1 }
    assert(M.Weights(nv).crit < lo)
end)

test("model: Champion of the Light turns Intellect into spell damage", function()
    local w5 = M.Weights(state())
    local s0 = state(); s0.talents = { vengeance = 3, champion = 0, sacredArbiter = 1, holyStrike = 1 }
    local w0 = M.Weights(s0)
    assert(math.abs((w5.int - w0.int) - 0.6 * w5.spdmg) < 0.01, "60% of Int as spell damage")
    near(w5.str, 10, "1 Str = 2 AP = 10 pts"); near(w5.ap, 5); near(w5.wdps, 70, "1 weapon DPS = 14 AP")
end)

test("model: Holy Strike on cooldown, Sacred Arbiter +20%", function()
    local st = state()
    local _, a = M.Dps(st)
    st.talents = { vengeance = 3, champion = 5, sacredArbiter = 0, holyStrike = 1 }
    local _, b = M.Dps(st)
    near(a.holyStrike, b.holyStrike * 1.2)
    st.talents.holyStrike = 0
    local _, c = M.Dps(st)
    eq(c.holyStrike, 0)
    -- it's a melee strike: hit counts for it, spell hit doesn't
    local s1 = state({ hit = 5 })
    local _, x = M.Dps(s1); local _, y = M.Dps(M.Apply(s1, { hit = 1 }))
    assert(y.holyStrike > x.holyStrike)
end)

test("model: swap delta is exact across the hit cap", function()
    local st = state({ hit = 8 })
    -- +3% hit only gives 1% before the cap
    local d = M.Delta(st, {}, { hit = 3 })
    near(d, M.Delta(st, {}, { hit = 1 }))
    -- a slower weapon with the same DPS is better (Seal of Command scales with swing damage)
    assert(M.Delta(st, { wdps = 60, speed = 3.6 }, { wdps = 60, speed = 3.9 }) > 0)
end)

---------------------------------------------------------------- scoring
test("scoring: verdicts", function()
    local w = NS.RET.weights
    local prio = { 100, 25, 40 }
    eq(NS.Scoring.Compare({ str = 10 }, { str = 20 }, w, prio).verdict, "upgrade")
    eq(NS.Scoring.Compare({ str = 20 }, { str = 10 }, w, prio).verdict, "downgrade")
    eq(NS.Scoring.Compare({ str = 20 }, { str = 20 }, w, prio).verdict, "sidegrade")
    local r = NS.Scoring.Compare({ sta = 20 }, { str = 20 }, w, prio)
    eq(r.verdict, "tradeoff")
    near(r.D[1], 200); near(r.D[2], 6 - 200)
    near(r.total, 200 + (6 - 200) * 0.25)
    eq(r.swings[1].id, "str")
    near(NS.Scoring.Compare({}, { hit = 2 }, w, prio, 33).D[1], 33, "model delta overrides DPS")
end)

test("scoring: axis with 0 priority is ignored in the verdict", function()
    local w = NS.RET.weights
    eq(NS.Scoring.Compare({ sta = 20 }, { str = 20 }, w, { 100, 0, 40 }).verdict, "upgrade")
end)

---------------------------------------------------------------- profile
test("profile: reads the sheet and talents, live weights", function()
    local p = NS.Profile.Get()
    eq(p.specName, "Retribution")
    eq(p.state.ap, 1200); eq(p.state.crit, 20); eq(p.state.hit, 5); eq(p.state.sp, 80); eq(p.state.target, 63)
    eq(p.state.talents.vengeance, 3); eq(p.state.talents.champion, 5); eq(p.state.talents.sacredArbiter, 1)
    eq(p.state.talents.holyStrike, 1)
    eq(#p.estimated, 0, table.concat(p.estimated, ","))
    near(p.state.wdps, 60, "weapon DPS backed out of the sheet damage")
    near(p.weights.str[1], 10); assert(p.weights.hit[1] > 50); eq(p.weights.sta[2], 10)
    SHEET.hit = 10; NS.Profile.Invalidate()
    near(NS.Profile.Get().weights.hit[1], 0, "capped")
    SHEET.hit = 5; NS.Profile.Invalidate()
end)

test("profile: other classes get nothing", function()
    PLAYER.class = "WARRIOR"; NS.Profile.Invalidate()
    eq(NS.Profile.Get(), nil)
    NS.Commands.Run("status")
    assert(printed[#printed]:find("Paladins", 1, true))
    PLAYER.class = "PALADIN"; NS.Profile.Invalidate()
end)

test("profile: missing API falls back to defaults, talents can be set by hand", function()
    local old = GetCritChance
    GetCritChance = nil
    local oldTI = GetTalentInfo
    GetTalentInfo = nil
    NS.Profile.Invalidate()
    local p = NS.Profile.Get()
    eq(p.state.crit, 20, "last good reading is kept")
    eq(p.state.talents.vengeance, 0)
    NS.Commands.Run("set vengeance 3"); NS.Commands.Run("set target 62")
    p = NS.Profile.Get()
    eq(p.state.talents.vengeance, 3); eq(p.state.target, 62)
    NS.Commands.Run("set vengeance auto"); NS.Commands.Run("set target auto")
    GetCritChance, GetTalentInfo = old, oldTI
    NS.Profile.Invalidate()
end)

test("profile: secret values in combat keep the last reading", function()
    issecretvalue = function(v) return v == 1200 - 200 end
    NS.Profile.Invalidate()
    eq(NS.Profile.Get().state.ap, 1200)
    issecretvalue = nil
    NS.Profile.Invalidate()
end)

test("tooltip text is plain ASCII (the game font shows boxes otherwise)", function()
    local src = io.open(ROOT .. "Tooltip.lua"):read("*a"):gsub("\194\183", "")  -- middle dot renders fine
    assert(not src:find("[\128-\255]"), "non-ASCII character in Tooltip.lua")
end)

test("commands: pin / unpin / prio / export / import round trip", function()
    NS.Commands.Run("weight hit 0 0 0")
    NS.Commands.Run("prio 100 50 10")
    local p = NS.Profile.Get()
    eq(p.weights.hit[1], 0); eq(p.prio[2], 50); assert(p.overridden); assert(p.pinned.hit)
    local s = NS.Commands.Export(p)
    assert(s:find("hit=0/0/0", 1, true), s)
    assert(s:find("|prio=100/50/10", 1, true), s)
    NS.Commands.Run("unpin hit")
    assert(NS.Profile.Get().weights.hit[1] > 50)
    NS.Commands.Run("reset")
    eq(NS.Profile.Get().prio[2], 25)
    NS.Commands.Run("import hit=0/0/0|prio=100/50/10")
    p = NS.Profile.Get()
    eq(p.weights.hit[1], 0); eq(p.prio[2], 50)
    NS.Commands.Run("reset")
    local w, err = NS.Commands.ParseImport("garbage")
    eq(w, nil); eq(err, "nothing recognised")
    NS.Commands.Run("weights"); NS.Commands.Run("talents"); NS.Commands.Run("status")
end)

test("saved variables from 0.1.x are migrated", function()
    ForeverGearScaleDB = { weights = { ["PALADIN:3"] = { hit = { 0, 0, 0 } }, ["WARRIOR:2"] = {} },
        prio = { ["PALADIN:3"] = { 100, 10, 10 } }, specOverride = { PALADIN = 3 } }
    events.handler(events.frame, "ADDON_LOADED", "ForeverGearScale")
    eq(NS.db.pins.hit[1], 0); eq(NS.db.prio[2], 10); eq(NS.db.weights, nil); eq(NS.db.specOverride, nil)
    NS.Commands.Run("reset")
end)

---------------------------------------------------------------- tooltip flow
local equippedHelm = item(1001, "INVTYPE_HEAD", { "Old Helm", "Head  Plate", "400 Armor", "+10 Strength", "+10 Stamina" })
local newHelm = item(1002, "INVTYPE_HEAD", { "New Helm", "Head  Plate", "565 Armor", "+18 Strength",
    "Equip: Improves your chance to hit by 1%.", "Use: Something fun." })
EQUIPPED[1] = equippedHelm

test("tooltip: upgrade lines added", function()
    local out = hover(newHelm)
    assert(out:find("Gear Scale", 1, true), out)
    assert(out:find("Retribution", 1, true), out)
    assert(out:find("Upgrade", 1, true) or out:find("Trade%-off"), out)
    assert(out:find("DPS", 1, true) and out:find("Defense", 1, true) and out:find("Sustain", 1, true), out)
    local d = NS.Profile.Get().dpsDelta(NS.ItemStats.Get(equippedHelm), NS.ItemStats.Get(newHelm))
    assert(d > 80, d)   -- 8 Str (80 pts) + 1% hit under the cap
    assert(out:find("+" .. math.floor(d + 0.5), 1, true), "DPS delta from the model\n" .. out)
end)

test("tooltip: hovering the equipped item shows its own scores", function()
    local out = hover(equippedHelm)
    assert(out:find("Equipped", 1, true), out)
end)

test("tooltip: shift shows stat swings and unscored effects", function()
    SHIFT = true
    local out = hover(newHelm)
    SHIFT = false
    assert(out:find("Strength", 1, true) and out:find("Hit %", 1, true), out)
    assert(out:find("1 special effect", 1, true), out)
end)

test("tooltip: rings pick the weaker equipped ring", function()
    EQUIPPED[11] = item(2001, "INVTYPE_FINGER", { "Good Ring", "Finger", "+20 Strength" })
    EQUIPPED[12] = item(2002, "INVTYPE_FINGER", { "Bad Ring", "Finger", "+5 Strength" })
    local cand = item(2003, "INVTYPE_FINGER", { "New Ring", "Finger", "+12 Strength" })
    local out = hover(cand)
    assert(out:find("vs Ring 2", 1, true), out)
    assert(out:find("Upgrade", 1, true), out)
end)

test("tooltip: two-hander compares against main + off hand", function()
    EQUIPPED[16] = item(3001, "INVTYPE_WEAPONMAINHAND", { "Sword", "Main Hand  Sword", "(40.0 damage per second)", "+5 Strength" })
    EQUIPPED[17] = item(3002, "INVTYPE_SHIELD", { "Shield", "Off Hand  Shield", "2000 Armor", "+10 Stamina" })
    local cand = item(3003, "INVTYPE_2HWEAPON", { "Big Axe", "Two-Hand  Axe", "(60.0 damage per second)", "+25 Strength" })
    local out = hover(cand)
    assert(out:find("Main + Off hand", 1, true), out)
    NS.Profile.Invalidate()
    near(NS.Profile.Get().state.wdps, 40, "weapon DPS read from the main hand tooltip")
end)

test("tooltip: empty slot is a pure upgrade, non-gear is ignored", function()
    local cloak = item(4001, "INVTYPE_CLOAK", { "Cloak", "Back", "40 Armor", "+5 Agility" })
    assert(hover(cloak):find("Upgrade", 1, true))
    local potion = item(4002, "", { "Potion", "Use: Restores 500 health." })
    eq(hover(potion), "")
end)

test("tooltip: shopping tooltips and disabled addon are skipped", function()
    local other = newTooltip()
    eq(hover(newHelm, other), "")
    NS.Commands.Run("off")
    eq(hover(newHelm), "")
    NS.Commands.Run("on")
end)

print_real(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
