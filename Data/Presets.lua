-- Data/Presets.lua
-- Fallback DPS weights for Retribution: points per 1 point of the stat,
-- 1 Attack Power = 5 pts. In game they are replaced by the live weights from
-- Model.lua; these only cover stats the model doesn't know.
-- Same numbers as the Retribution web page.

local _, NS = ...

NS.RET = {
    name = "Retribution",
    weights = {
        str = 10, agi = 3.5, ap = 5, hit = 70, crit = 70, wskill = 25, wdps = 70,
        int = 1, spdmg = 2.5, spboth = 2.5, spcrit = 8, spellhit = 10,
    },
}
