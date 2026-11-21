-- Data/Stats.lua
-- The stat vocabulary. Same ids as the "Gear Scale" web page so weights can be
-- copied between the two with /fgs import.

local _, NS = ...

NS.STATS = {
    -- id          display name             group
    { id = "str",      name = "Strength",             group = "primary" },
    { id = "agi",      name = "Agility",              group = "primary" },
    { id = "sta",      name = "Stamina",              group = "primary" },
    { id = "int",      name = "Intellect",            group = "primary" },
    { id = "spi",      name = "Spirit",               group = "primary" },
    { id = "ap",       name = "Attack Power",         group = "offense" },
    { id = "rap",      name = "Ranged Attack Power",  group = "offense" },
    { id = "hit",      name = "Hit %",                group = "offense" },
    { id = "crit",     name = "Crit %",               group = "offense" },
    { id = "wskill",   name = "Weapon skill",         group = "offense" },
    { id = "wdps",     name = "Weapon DPS",           group = "offense" },
    { id = "speed",    name = "Weapon speed",         group = "offense" },
    { id = "spdmg",    name = "Spell damage",         group = "spell" },
    { id = "spboth",   name = "Spell dmg + healing",  group = "spell" },
    { id = "heal",     name = "Healing power",        group = "spell" },
    { id = "spcrit",   name = "Spell crit %",         group = "spell" },
    { id = "spellhit", name = "Spell hit %",          group = "spell" },
    { id = "armor",    name = "Armor",                group = "defense" },
    { id = "def",      name = "Defense skill",        group = "defense" },
    { id = "dodge",    name = "Dodge %",              group = "defense" },
    { id = "parry",    name = "Parry %",              group = "defense" },
    { id = "block",    name = "Block %",              group = "defense" },
    { id = "blockval", name = "Block value",          group = "defense" },
    { id = "hp",       name = "Health (flat)",        group = "defense" },
    { id = "res",      name = "Resistance (1 school)", group = "defense" },
    { id = "allres",   name = "All resistances",      group = "defense" },
    { id = "mp5",      name = "Mana per 5 sec",       group = "sustain" },
    { id = "mana",     name = "Mana (flat)",          group = "sustain" },
    { id = "hp5",      name = "Health per 5 sec",     group = "sustain" },
}

NS.STAT_BY_ID = {}
for _, s in ipairs(NS.STATS) do NS.STAT_BY_ID[s.id] = s end
