-- Data/Presets.lua
-- Preset stat weights per class and spec: the "local db in codebase".
--
-- Each weight is { axis1, axis2, axis3 } = points per 1 point of the stat.
-- Axes are DPS / Defense / Sustain (renamed per role: tanks see Threat /
-- Mitigation / Sustain, healers see Healing / Defense / Mana).
--
-- Scale anchors (same as the web page):
--   physical: 1 Attack Power = 5 pts      casters: 1 spell power = 5 pts
--   defense:  1 pt ~ 1 effective HP (1 Stamina = 10 HP = 10 pts)
--   sustain:  1 pt ~ 2.5 mana over a fight
--
-- These are starting points built on level-60 vanilla rules. Forever reworked
-- every talent tree, so tune them in game with /fgs weight.
--
-- Spec index = talent tab order (1, 2, 3), the same order the client uses.

local _, NS = ...

local ROLES = {
    dps  = { axes = { "DPS", "Defense", "Sustain" },     prio = { 100, 25, 40 } },
    tank = { axes = { "Threat", "Mitigation", "Sustain" }, prio = { 50, 100, 30 } },
    heal = { axes = { "Healing", "Defense", "Mana" },     prio = { 100, 20, 70 } },
}
NS.ROLES = ROLES

-- Every spec starts from this, then its own table overrides whole entries.
local BASE_DEFENSE = {
    sta = { 0, 10, 0 }, armor = { 0, 0.5, 0 }, hp = { 0, 1, 0 },
    res = { 0, 1.5, 0 }, allres = { 0, 6, 0 }, def = { 0, 15, 0 },
    dodge = { 0, 60, 0 }, parry = { 0, 55, 0 }, block = { 0, 30, 0 },
    blockval = { 0, 0.5, 0 }, hp5 = { 0, 3, 6 },
}
local BASE_MANA = {
    int = { 0, 0, 6 }, spi = { 0, 0, 4 }, mp5 = { 0, 0, 25 }, mana = { 0, 0, 0.4 },
}

-- Shared building blocks
local MELEE = {
    str = { 10, 0.3, 0 }, agi = { 3.5, 4, 0 }, ap = { 5, 0, 0 },
    hit = { 70, 0, 0 }, crit = { 70, 0, 0 }, wskill = { 25, 0, 0 }, wdps = { 70, 0, 0 },
}
local CASTER = {
    spdmg = { 5, 0, 0 }, spboth = { 5, 0, 0 }, spcrit = { 40, 0, 0 },
    spellhit = { 60, 0, 0 }, int = { 0.6, 0, 6 },
}
local HEALER = {
    heal = { 5, 0, 0 }, spboth = { 5, 0, 1 }, int = { 2, 0, 8 },
    spcrit = { 40, 0, 10 }, mp5 = { 0, 0, 30 },
}
local TANK = {
    sta = { 0, 12, 0 }, armor = { 0, 0.8, 0 }, def = { 0, 20, 0 },
    dodge = { 0, 70, 0 }, parry = { 0, 65, 0 }, block = { 0, 40, 0 },
    blockval = { 0, 1.5, 0 },
}

local function merge(...)
    local out = {}
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if t then for k, v in pairs(t) do out[k] = { v[1], v[2], v[3] } end end
    end
    return out
end

local function spec(name, role, ...)
    return { name = name, role = role, parts = { ... } }
end

-- usesMana: whether BASE_MANA applies. defaultSpec: used before talents are spent.
local CLASSES = {
    WARRIOR = { usesMana = false, defaultSpec = 2,
        spec("Arms", "dps", MELEE),
        spec("Fury", "dps", MELEE, { hit = { 80, 0, 0 }, wskill = { 30, 0, 0 }, wdps = { 60, 0, 0 } }),
        spec("Protection", "tank", TANK, {
            str = { 6, 0.5, 0 }, agi = { 2, 6, 0 }, ap = { 3, 0, 0 }, hit = { 40, 0, 0 },
            crit = { 25, 0, 0 }, wskill = { 12, 8, 0 }, wdps = { 35, 0, 0 } }),
    },
    ROGUE = { usesMana = false, defaultSpec = 2,
        spec("Assassination", "dps", MELEE, { agi = { 7.5, 4, 0 }, str = { 5, 0.3, 0 }, hit = { 80, 0, 0 }, crit = { 75, 0, 0 } }),
        spec("Combat", "dps", MELEE, { agi = { 7.5, 4, 0 }, str = { 5, 0.3, 0 }, hit = { 85, 0, 0 }, wskill = { 35, 0, 0 }, wdps = { 75, 0, 0 } }),
        spec("Subtlety", "dps", MELEE, { agi = { 7.5, 4, 0 }, str = { 5, 0.3, 0 }, hit = { 75, 0, 0 }, crit = { 65, 0, 0 } }),
    },
    HUNTER = { usesMana = true, defaultSpec = 2,
        spec("Beast Mastery", "dps", { agi = { 11, 4, 0 }, rap = { 5, 0, 0 }, ap = { 0.5, 0, 0 }, str = { 0.5, 0.3, 0 },
            hit = { 70, 0, 0 }, crit = { 55, 0, 0 }, wdps = { 70, 0, 0 }, int = { 0.5, 0, 5 } }),
        spec("Marksmanship", "dps", { agi = { 11, 4, 0 }, rap = { 5, 0, 0 }, ap = { 0.5, 0, 0 }, str = { 0.5, 0.3, 0 },
            hit = { 70, 0, 0 }, crit = { 70, 0, 0 }, wdps = { 70, 0, 0 }, int = { 0.5, 0, 5 } }),
        spec("Survival", "dps", { agi = { 12, 4.5, 0 }, rap = { 5, 0, 0 }, ap = { 1, 0, 0 }, str = { 0.5, 0.3, 0 },
            hit = { 70, 0, 0 }, crit = { 65, 0, 0 }, wdps = { 70, 0, 0 }, int = { 0.5, 0, 5 } }),
    },
    PALADIN = { usesMana = true, defaultSpec = 3,
        spec("Holy", "heal", HEALER),
        spec("Protection", "tank", TANK, {
            str = { 4, 0.3, 0 }, agi = { 1.5, 5, 0 }, spdmg = { 4, 0, 0 }, spboth = { 4, 0, 1 },
            hit = { 40, 0, 0 }, block = { 0, 45, 0 }, blockval = { 0, 2, 0 } }),
        -- Same numbers as the Retribution web page.
        spec("Retribution", "dps", MELEE, {
            int = { 1, 0, 6 }, spdmg = { 2.5, 0, 0 }, spboth = { 2.5, 0, 1.5 }, heal = { 0, 0, 2 },
            spcrit = { 8, 0, 12 }, spellhit = { 10, 0, 0 } }),
    },
    PRIEST = { usesMana = true, defaultSpec = 2,
        spec("Discipline", "heal", HEALER, { int = { 2.5, 0, 8 }, spi = { 0.5, 0, 5 }, spcrit = { 35, 0, 8 } }),
        spec("Holy", "heal", HEALER, { spi = { 1, 0, 6 } }),
        spec("Shadow", "dps", CASTER, { spcrit = { 20, 0, 0 }, int = { 0.5, 0, 6 }, spi = { 0.5, 0, 4 } }),
    },
    MAGE = { usesMana = true, defaultSpec = 3,
        spec("Arcane", "dps", CASTER, { int = { 1, 0, 7 } }),
        spec("Fire", "dps", CASTER, { spcrit = { 55, 0, 0 } }),
        spec("Frost", "dps", CASTER, { spcrit = { 35, 0, 0 } }),
    },
    WARLOCK = { usesMana = true, defaultSpec = 1,
        spec("Affliction", "dps", CASTER, { spcrit = { 15, 0, 0 }, int = { 0.3, 0, 4 }, sta = { 0, 10, 1 } }),
        spec("Demonology", "dps", CASTER, { spcrit = { 25, 0, 0 }, int = { 0.3, 0, 4 }, sta = { 0, 10, 1.5 } }),
        spec("Destruction", "dps", CASTER, { spcrit = { 45, 0, 0 }, int = { 0.4, 0, 4 }, sta = { 0, 10, 1 } }),
    },
    SHAMAN = { usesMana = true, defaultSpec = 3,
        spec("Elemental", "dps", CASTER),
        spec("Enhancement", "dps", MELEE, { hit = { 75, 0, 0 }, wdps = { 75, 0, 0 }, spdmg = { 1.5, 0, 0 },
            spboth = { 1.5, 0, 0 }, int = { 0.5, 0, 5 } }),
        spec("Restoration", "heal", HEALER, { mp5 = { 0, 0, 35 }, spcrit = { 35, 0, 8 } }),
    },
    DRUID = { usesMana = true, defaultSpec = 3,
        spec("Balance", "dps", CASTER),
        -- Feral covers cat and bear, so Defense counts more than for other DPS.
        spec("Feral", "dps", MELEE, { agi = { 7.5, 6, 0 }, sta = { 0, 12, 0 }, armor = { 0, 1, 0 },
            dodge = { 0, 70, 0 }, wdps = { 0, 0, 0 }, wskill = { 0, 0, 0 }, int = { 0, 0, 2 } }),
        spec("Restoration", "heal", HEALER, { spi = { 0.5, 0, 6 }, spcrit = { 30, 0, 5 } }),
    },
}

-- Feral wants a different axis priority than the generic DPS role.
local PRIO_OVERRIDE = { ["DRUID:2"] = { 100, 50, 10 } }

-- Build the flat preset table: NS.PRESETS["PALADIN"][3] = { name, role, axes, prio, weights }
NS.PRESETS = {}
for classFile, cls in pairs(CLASSES) do
    NS.PRESETS[classFile] = { defaultSpec = cls.defaultSpec }
    for i = 1, 3 do
        local s = cls[i]
        local role = ROLES[s.role]
        local weights = merge(BASE_DEFENSE, cls.usesMana and BASE_MANA or nil, unpack(s.parts))
        NS.PRESETS[classFile][i] = {
            name = s.name,
            role = s.role,
            axes = role.axes,
            prio = PRIO_OVERRIDE[classFile .. ":" .. i] or role.prio,
            weights = weights,
        }
    end
end
