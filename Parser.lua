-- Parser.lua
-- Turns an item's tooltip lines into { statId = value }. A Lua port of the
-- web page's parser: English and French clients, vanilla-style item text
-- ("+15 Strength", "Equip: Improves your chance to hit by 1%.").
-- Pure Lua, no game API, so it runs in the offline tests.

local _, NS = ...
local Parser = {}
NS.Parser = Parser

local PRIMARY = {
    strength = "str", force = "str",
    agility = "agi", ["agilité"] = "agi",
    stamina = "sta", endurance = "sta",
    intellect = "int", intelligence = "int",
    spirit = "spi", esprit = "spi",
}

local function has(l, ...)
    for i = 1, select("#", ...) do
        if l:find((select(i, ...)), 1, true) then return true end
    end
    return false
end

local function tonum(s)
    return s and tonumber((s:gsub(",", "."))) or nil
end
local function firstNumber(l) return tonum(l:match("(%d+[%.,]?%d*)")) end
local function percent(l) return tonum(l:match("(%d+[%.,]?%d*)%s*%%")) end

-- Lines that never carry stats we score.
local function skipped(raw, l)
    if raw:sub(1, 1) == '"' then return true end                        -- flavor text
    if l:match("^%(%d%)") then return true end                          -- "(2) Set: ..."
    if l:match("^set%s*:") or l:match("^ensemble%s*:") then return true end
    return false
end

-- Lines that carry effects we don't model (procs, on-use, conditional AP).
local function isEffect(l)
    return l:match("^use%s*:") or l:match("^utiliser%s*:")
        or l:match("^chance on hit%s*:") or l:match("^chances quand vous touchez%s*:")
end

-- Returns stats, misses (list of "Equip:" lines that were not understood).
function Parser.Parse(lines)
    local out, miss = {}, {}
    local function add(id, v)
        if id and v then out[id] = math.floor(((out[id] or 0) + v) * 100 + 0.5) / 100 end
    end

    for idx, raw in ipairs(lines) do
        raw = raw:gsub("^%s+", ""):gsub("%s+$", "")
        -- line 1 is the item name; never parse it
        if idx > 1 and raw ~= "" then
            local lower = raw:lower()
            local isEquip = lower:match("^equip%s*:") or lower:match("^équipé%s*:") or lower:match("^Équipé%s*:")
            local l = lower:gsub("^equip%s*:%s*", ""):gsub("^équipé%s*:%s*", ""):gsub("^Équipé%s*:%s*", "")

            if skipped(raw, lower) then
                -- nothing
            elseif isEffect(lower) then
                miss[#miss + 1] = raw
            else
                local done = false
                -- "+15 Strength" / "+15 Force"  (several on one line is fine)
                for sign, n, word in l:gmatch("([%+%-])%s?(%d+)%s+([%a\128-\255]+)") do
                    local id = PRIMARY[word]
                    if id then add(id, tonumber(n) * (sign == "-" and -1 or 1)); done = true end
                end
                -- "Force +15"
                if not done then
                    local word, n = l:match("^([%a\128-\255]+)%s*%+%s*(%d+)")
                    if word and PRIMARY[word] then add(PRIMARY[word], tonumber(n)); done = true end
                end

                if not done then
                    local m = l:match("%(([%d%.,]+)%s*damage per second") or l:match("%(([%d%.,]+)%s*dégâts par seconde")
                    if m then add("wdps", tonum(m)); done = true end
                end
                -- "Speed 3.60" / "Vitesse 3,60" (the right-hand text of the damage line)
                if not done then
                    local m = l:match("^speed%s+([%d%.,]+)$") or l:match("^vitesse%s+([%d%.,]+)$")
                    if m then add("speed", tonum(m)); done = true end
                end

                if not done then
                    local spell = has(l, "spell", "sort")
                    local id, v
                    if l:find("%", 1, true) then
                        local p = percent(l)
                        if has(l, "crit") then id = spell and "spcrit" or "crit"
                        elseif has(l, "hit", "toucher") then id = spell and "spellhit" or "hit"
                        elseif has(l, "dodge", "esquiv") then id = "dodge"
                        elseif has(l, "parry", "parer") then id = "parry"
                        elseif has(l, "block", "bloquer") then id = "block"
                        end
                        v = p
                    end

                    if not id then
                        v = firstNumber(l)
                        if has(l, "ranged attack power", "puissance d'attaque à distance") then
                            id = "rap"
                        elseif has(l, "attack power", "puissance d'attaque") then
                            if has(l, "beast", "demon", "undead", "bête", "démon", "mort-vivant") then
                                miss[#miss + 1] = raw; done = true
                            else
                                id = "ap"
                            end
                        elseif has(l, "damage and healing", "dégâts et les soins", "dégâts et soins") then
                            id = "spboth"
                        elseif has(l, "healing", "soins") and spell then
                            id = "heal"
                        elseif (has(l, "damage done by", "dégâts infligés par", "dégâts des sorts", "dégâts de vos sorts"))
                            and (spell or has(l, "magi")) then
                            id = "spdmg"
                        elseif has(l, "mana per 5", "mana every 5", "mana toutes les 5", "mana par 5") then
                            id = "mp5"
                        elseif has(l, "health per 5", "health every 5", "vie toutes les 5", "vie par 5") then
                            id = "hp5"
                        elseif has(l, "block value", "valeur de blocage") or l:match("^%d+%s*block$") or l:match("^%d+%s*blocage$") then
                            id = "blockval"
                        elseif has(l, "defense", "défense") then
                            id = "def"
                        elseif has(l, "sword", "mace", "axe", "polearm", "dagger", "épée", "masse", "hache", "arme d'hast", "dague")
                            and l:match("%+%s?(%d+)") then
                            id, v = "wskill", tonumber(l:match("%+%s?(%d+)"))
                        elseif has(l, "all resistances", "toutes les résistances") then
                            id = "allres"
                        elseif has(l, "resistance", "résistance") then
                            id = "res"
                        elseif has(l, "armor", "armure") and l:find("%d") then
                            id = "armor"
                        elseif l:match("^%+%d+%s*health$") or l:match("^%+%d+%s*points de vie$") or l:match("^%+%d+%s*vie$") then
                            id = "hp"
                        elseif l:match("^%+%d+%s*mana$") or l:match("^%+%d+%s*points de mana$") then
                            id = "mana"
                        end
                    end

                    if id and v then
                        add(id, v)
                    elseif not done and isEquip then
                        miss[#miss + 1] = raw
                    end
                end
            end
        end
    end
    return out, miss
end

-- Spell tooltip text -> { base = average damage, weapon = share of weapon
-- damage (0-1), cd = cooldown in sec }. Any field may be missing. English and
-- French. For a Seal, the damage range is the Judgement's (the text after
-- "judge" / "jugement"), and the first range there is the normal one (the
-- second is "if the target is stunned").
function Parser.Spell(lines)
    local text = table.concat(lines or {}, "\n"):lower()
    local out = {}

    local from = text:find("judge", 1, true) or text:find("jugement", 1, true) or 1
    local part = text:sub(from)
    local a, b = part:match("(%d+[%.,]?%d*)%s*to%s*(%d+[%.,]?%d*)")
    if not a then a, b = part:match("(%d+[%.,]?%d*)%s*à%s*(%d+[%.,]?%d*)") end
    if a then
        out.base = (tonum(a) + tonum(b)) / 2
    else
        -- "... weapon damage plus 45 Holy damage" / "... plus 45 points de dégâts"
        local n = text:match("plus%s+(%d+[%.,]?%d*)") or text:match("additional%s+(%d+[%.,]?%d*)")
        if n then out.base = tonum(n) end
    end

    local pct = text:match("(%d+[%.,]?%d*)%%[^%d\n]-weapon") or text:match("(%d+[%.,]?%d*)%%[^%d\n]-arme")
    if pct then out.weapon = tonum(pct) / 100 end

    local cd = text:match("(%d+[%.,]?%d*)%s*sec%s*cooldown")
        or text:match("recharge%s*:?%s*(%d+[%.,]?%d*)%s*sec")
        or text:match("(%d+[%.,]?%d*)%s*sec%.?%s*de recharge")
    if cd then
        out.cd = tonum(cd)
    else
        local m = text:match("(%d+[%.,]?%d*)%s*min%s*cooldown") or text:match("recharge%s*:?%s*(%d+[%.,]?%d*)%s*min")
        if m then out.cd = tonum(m) * 60 end
    end
    return out
end

-- A seal's per-hit Holy damage ("each melee attack 33 additional Holy
-- damage" / "33 points de dégâts du Sacré supplémentaires"), ignoring the
-- Judgement part of the text.
function Parser.SealHit(lines)
    local text = table.concat(lines or {}, "\n"):lower()
    local cut = text:find("judge", 1, true) or text:find("jugement", 1, true)
    if cut then text = text:sub(1, cut - 1) end
    local n = text:match("(%d+[%.,]?%d*)%s+additional")
        or text:match("additional%s+(%d+[%.,]?%d*)")
        or text:match("(%d+[%.,]?%d*)%s+points? de dégâts du sacré supplémentaires")
    return n and tonum(n) or nil
end
