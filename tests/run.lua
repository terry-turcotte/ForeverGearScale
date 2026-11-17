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
local PLAYER = { class = "PALADIN", tabs = { 5, 11, 31 } }
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
function GetNumTalentTabs() return 3 end
local TAB_NAMES = { "Holy", "Protection", "Retribution" }
function GetTalentTabInfo(i) return TAB_NAMES[i], "icon", PLAYER.tabs[i], "file" end
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

---------------------------------------------------------------- presets
test("presets: 9 classes x 3 specs, sane weights", function()
    local n = 0
    for classFile, specs in pairs(NS.PRESETS) do
        for i = 1, 3 do
            local p = specs[i]
            assert(p and p.name and p.weights and #p.axes == 3 and #p.prio == 3, classFile .. i)
            for id, w in pairs(p.weights) do
                assert(NS.STAT_BY_ID[id], classFile .. i .. " unknown stat " .. id)
                assert(#w == 3, classFile .. i .. " " .. id)
            end
            n = n + 1
        end
        assert(specs.defaultSpec >= 1 and specs.defaultSpec <= 3)
    end
    eq(n, 27)
end)

test("presets: Retribution matches the web page", function()
    local w = NS.PRESETS.PALADIN[3].weights
    local expect = { str = { 10, 0.3, 0 }, agi = { 3.5, 4, 0 }, sta = { 0, 10, 0 }, int = { 1, 0, 6 },
        spi = { 0, 0, 4 }, ap = { 5, 0, 0 }, hit = { 70, 0, 0 }, mp5 = { 0, 0, 25 }, spcrit = { 8, 0, 12 },
        armor = { 0, 0.5, 0 }, hp5 = { 0, 3, 6 }, spboth = { 2.5, 0, 1.5 } }
    for id, e in pairs(expect) do for i = 1, 3 do eq(w[id][i], e[i], id .. "[" .. i .. "]") end end
    eq(NS.PRESETS.WARRIOR[1].weights.int, nil, "warriors get no mana stats")
end)

---------------------------------------------------------------- scoring
test("scoring: verdicts", function()
    local w = NS.PRESETS.PALADIN[3].weights
    local prio = { 100, 25, 40 }
    eq(NS.Scoring.Compare({ str = 10 }, { str = 20 }, w, prio).verdict, "upgrade")
    eq(NS.Scoring.Compare({ str = 20 }, { str = 10 }, w, prio).verdict, "downgrade")
    eq(NS.Scoring.Compare({ str = 20 }, { str = 20 }, w, prio).verdict, "sidegrade")
    local r = NS.Scoring.Compare({ sta = 20 }, { str = 20 }, w, prio)
    eq(r.verdict, "tradeoff")
    near(r.D[1], 200); near(r.D[2], 6 - 200)
    near(r.total, 200 + (6 - 200) * 0.25)
    eq(r.swings[1].id, "str")
end)

test("scoring: axis with 0 priority is ignored in the verdict", function()
    local w = NS.PRESETS.PALADIN[3].weights
    eq(NS.Scoring.Compare({ sta = 20 }, { str = 20 }, w, { 100, 0, 40 }).verdict, "upgrade")
end)

---------------------------------------------------------------- profile
test("profile: spec from talent points, override, reset", function()
    local p = NS.Profile.Get()
    eq(p.classFile, "PALADIN"); eq(p.specIndex, 3); eq(p.specName, "Retribution"); eq(p.source, "talents")
    NS.Commands.Run("spec 2"); p = NS.Profile.Get()
    eq(p.specIndex, 2); eq(p.role, "tank"); eq(p.axes[1], "Threat"); eq(p.source, "manual")
    NS.Commands.Run("spec auto")
    PLAYER.tabs = { 0, 0, 0 }; NS.Profile.Invalidate()
    eq(NS.Profile.Get().source, "default")
    PLAYER.tabs = { 5, 11, 31 }; NS.Profile.Invalidate()
end)

test("profile: unreliable tab info falls back to counting talent ranks", function()
    -- id-first tab info whose pointsSpent slot isn't pointsSpent (e.g. a file id):
    -- Holy used to win with a huge bogus count.
    local oldTab = GetTalentTabInfo
    GetTalentTabInfo = function(i) return 380 + i, TAB_NAMES[i], "desc", 135920, ({ 999999, 0.5, -3 })[i] end
    NS.Profile.Invalidate()
    eq(NS.Profile.Get().source, "default", "garbage counts are ignored")
    -- Ranks counted talent by talent: 0 / 0 / 27, like the screenshot.
    local RANKS = { {}, {}, { 5, 5, 3, 3, 2, 5, 1, 3 } }
    function GetNumTalents(tab) return math.max(#RANKS[tab], 4) end
    function GetTalentInfo(tab, i) return "T", "icon", 1, 1, RANKS[tab][i] or 0, 5 end
    NS.Profile.Invalidate()
    local p = NS.Profile.Get()
    eq(p.specIndex, 3); eq(p.specName, "Retribution"); eq(p.source, "talents"); eq(p.talentPoints[3], 27)
    GetTalentTabInfo, GetNumTalents, GetTalentInfo = oldTab, nil, nil
    NS.Profile.Invalidate()
end)

test("tooltip text is plain ASCII (the game font shows boxes otherwise)", function()
    local src = io.open(ROOT .. "Tooltip.lua"):read("*a"):gsub("\194\183", "")  -- middle dot renders fine
    assert(not src:find("[\128-\255]"), "non-ASCII character in Tooltip.lua")
end)

test("commands: weight / prio / export / import round trip", function()
    NS.Commands.Run("weight hit 0 0 0")
    NS.Commands.Run("prio 100 50 10")
    local p = NS.Profile.Get()
    eq(p.weights.hit[1], 0); eq(p.prio[2], 50); assert(p.overridden)
    local s = NS.Commands.Export(p)
    assert(s:find("str=10/0.3/0", 1, true), s)
    assert(s:find("|prio=100/50/10", 1, true), s)
    NS.Commands.Run("reset")
    eq(NS.Profile.Get().weights.hit[1], 70)
    NS.Commands.Run("import " .. s)
    p = NS.Profile.Get()
    eq(p.weights.hit[1], 0); eq(p.prio[2], 50)
    NS.Commands.Run("reset")
    local w, err = NS.Commands.ParseImport("garbage")
    eq(w, nil); eq(err, "nothing recognised")
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
    assert(out:find("+150", 1, true), "DPS delta 8 str*10 + 1 hit*70 = 150\n" .. out)
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
