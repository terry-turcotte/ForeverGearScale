-- Data/Presets.lua
-- The Retribution Paladin weights: the "local db in codebase".
--
-- Each weight is { DPS, Defense, Sustain } = points per 1 point of the stat.
-- The DPS column here is only the fallback: in game it is replaced by the
-- live weights from Model.lua, computed on your character sheet. Defense and
-- Sustain stay as below.
--
-- Scale anchors (same as the web page):
--   DPS:      1 Attack Power = 5 pts
--   Defense:  1 pt ~ 1 effective HP (1 Stamina = 10 HP = 10 pts)
--   Sustain:  1 pt ~ 2.5 mana over a fight

local _, NS = ...

NS.RET = {
    name = "Retribution",
    axes = { "DPS", "Defense", "Sustain" },
    prio = { 100, 25, 40 },
    -- Same numbers as the Retribution web page.
    weights = {
        -- offense
        str = { 10, 0.3, 0 }, agi = { 3.5, 4, 0 }, ap = { 5, 0, 0 },
        hit = { 70, 0, 0 }, crit = { 70, 0, 0 }, wskill = { 25, 0, 0 }, wdps = { 70, 0, 0 },
        int = { 1, 0, 6 }, spdmg = { 2.5, 0, 0 }, spboth = { 2.5, 0, 1.5 }, heal = { 0, 0, 2 },
        spcrit = { 8, 0, 12 }, spellhit = { 10, 0, 0 },
        -- defense
        sta = { 0, 10, 0 }, armor = { 0, 0.5, 0 }, hp = { 0, 1, 0 },
        res = { 0, 1.5, 0 }, allres = { 0, 6, 0 }, def = { 0, 15, 0 },
        dodge = { 0, 60, 0 }, parry = { 0, 55, 0 }, block = { 0, 30, 0 },
        blockval = { 0, 0.5, 0 }, hp5 = { 0, 3, 6 },
        -- mana
        spi = { 0, 0, 4 }, mp5 = { 0, 0, 25 }, mana = { 0, 0, 0.4 },
    },
}
