-- Core.lua
-- Wires everything to game events. Loaded last.

local ADDON, NS = ...
local C = NS.Compat

local DEFAULTS = {
    enabled = true,
    showHint = true,
    ignoreEnchants = true,
    debug = false,
    pins = {},      -- stats whose DPS weight you set by hand: { hit = 0, ... }
    fight = {},     -- { target = 63, judge = 9, execute = 0.2 } (only what you changed)
    talents = {},   -- talent ranks set by hand: { vengeance = 3, champion = 5, sacredArbiter = 1, holyStrike = 0 }
}

local function initDB()
    local db = ForeverGearScaleDB or {}
    -- 0.1.x kept one entry per class and spec: keep the Ret ones, drop the rest.
    if type(db.weights) == "table" then
        db.pins = db.pins or db.weights["PALADIN:3"]
        db.weights = nil
    end
    -- 0.2 betas pinned { dps, defense, sustain }: keep the DPS number. No more
    -- axis priority.
    for id, w in pairs(db.pins or {}) do
        if type(w) == "table" then db.pins[id] = tonumber(w[1]) or 0 end
    end
    db.prio, db.specOverride = nil, nil
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = type(v) == "table" and {} or v end
    end
    ForeverGearScaleDB = db
    NS.db = db
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

-- Anything that changes the character sheet or talents. Not every client
-- knows every event.
local REFRESH_EVENTS = {
    "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED",
    "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "UNIT_STATS", "UNIT_ATTACK_POWER",
    "UNIT_ATTACK_SPEED", "COMBAT_RATING_UPDATE", "SPELL_POWER_CHANGED", "PLAYER_LEVEL_UP",
    "SKILL_LINES_CHANGED",
}
local UNIT_EVENTS = { UNIT_INVENTORY_CHANGED = true, UNIT_STATS = true, UNIT_ATTACK_POWER = true,
    UNIT_ATTACK_SPEED = true }

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        initDB()
        NS.Commands.Init()
        NS.Tooltip.Init()
    elseif event == "PLAYER_LOGIN" then
        if not NS.Profile.IsPaladin() then return end   -- nothing to do for other classes
        for _, e in ipairs(REFRESH_EVENTS) do C.SafeRegister(frame, e) end
        C.SafeRegister(frame, "MODIFIER_STATE_CHANGED")
        NS.Profile.Invalidate()
    elseif event == "MODIFIER_STATE_CHANGED" then
        if arg1 == "LSHIFT" or arg1 == "RSHIFT" then NS.Tooltip.OnModifierChanged() end
    elseif UNIT_EVENTS[event] and arg1 ~= "player" then
        -- someone else's stats
    else
        NS.Profile.Invalidate()
    end
end)
