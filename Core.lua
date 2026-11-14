-- Core.lua
-- Wires everything to game events. Loaded last.

local ADDON, NS = ...
local C = NS.Compat

local DEFAULTS = {
    enabled = true,
    showHint = true,
    ignoreEnchants = true,
    debug = false,
    specOverride = {},   -- [classFile] = 1..3
    weights = {},        -- ["PALADIN:3"] = { str = {10, 0.3, 0}, ... } (only the changed stats)
    prio = {},           -- ["PALADIN:3"] = {100, 25, 40}
}

local function initDB()
    ForeverGearScaleDB = ForeverGearScaleDB or {}
    for k, v in pairs(DEFAULTS) do
        if ForeverGearScaleDB[k] == nil then
            ForeverGearScaleDB[k] = type(v) == "table" and {} or v
        end
    end
    NS.db = ForeverGearScaleDB
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

-- Anything that can change the spec. Not every client knows every event.
local SPEC_EVENTS = {
    "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE",
    "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "TRAIT_CONFIG_UPDATED",
}

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        initDB()
        NS.Commands.Init()
        NS.Tooltip.Init()
    elseif event == "PLAYER_LOGIN" then
        for _, e in ipairs(SPEC_EVENTS) do C.SafeRegister(frame, e) end
        C.SafeRegister(frame, "MODIFIER_STATE_CHANGED")
        NS.Profile.Invalidate()
    elseif event == "MODIFIER_STATE_CHANGED" then
        if arg1 == "LSHIFT" or arg1 == "RSHIFT" then NS.Tooltip.OnModifierChanged() end
    else
        NS.Profile.Invalidate()
    end
end)
