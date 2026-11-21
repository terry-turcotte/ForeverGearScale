-- Compat.lua
-- Thin wrappers over the Blizzard API. WoW Forever (Interface 16001) runs the
-- modern addon API (C_Item, C_TooltipInfo, TooltipDataProcessor), but we keep
-- fallbacks to the older globals so the addon degrades instead of erroring.

local _, NS = ...
local C = {}
NS.Compat = C

-- Midnight-era clients can hand addons "secret" values during combat.
function C.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

function C.GetItemInfoInstant(item)
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(item)
    elseif GetItemInfoInstant then
        return GetItemInfoInstant(item)
    end
end

function C.GetEquipLoc(link)
    local _, _, _, equipLoc = C.GetItemInfoInstant(link)
    return equipLoc
end

-- Item currently shown in a tooltip.
function C.GetTooltipItem(tooltip)
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local _, link = TooltipUtil.GetDisplayedItem(tooltip)
        if link then return link end
    end
    if tooltip.GetItem then
        local _, link = tooltip:GetItem()
        return link
    end
end

local function cleanText(t)
    if not t then return nil end
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return t
end
C.CleanText = cleanText

-- Weapon speed sits in the right-hand text of the damage line; that's the only
-- right-hand text we keep ("Speed 3.60", "Vitesse 3,60").
local function isSpeed(t)
    return type(t) == "string" and not C.IsSecret(t) and t:find("%d[%.,]%d%d") ~= nil
        and (t:find("Speed", 1, true) or t:find("Vitesse", 1, true)) ~= nil
end

-- Legacy path: render the link into a hidden tooltip and read its font strings.
local scanTip
local function linesFromScanTooltip(link)
    if not CreateFrame then return nil end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "ForeverGearScaleScanTip", nil, "GameTooltipTemplate")
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetHyperlink(link)
    local out = {}
    for i = 1, scanTip:NumLines() do
        local fs = _G["ForeverGearScaleScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t then out[#out + 1] = cleanText(t) end
        local r = _G["ForeverGearScaleScanTipTextRight" .. i]
        r = r and r:GetText()
        if isSpeed(r) then out[#out + 1] = cleanText(r) end
    end
    scanTip:Hide()
    return out
end

-- Returns the left-hand text of every tooltip line for an item link.
function C.GetTooltipLines(link)
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local data = C_TooltipInfo.GetHyperlink(link)
        if data and data.lines then
            local out = {}
            for _, line in ipairs(data.lines) do
                if line.leftText == nil and TooltipUtil and TooltipUtil.SurfaceArgs then
                    TooltipUtil.SurfaceArgs(line)
                end
                if line.leftText then out[#out + 1] = cleanText(line.leftText) end
                if isSpeed(line.rightText) then out[#out + 1] = cleanText(line.rightText) end
            end
            return out
        end
    end
    return linesFromScanTooltip(link)
end

-- Registering an event the client doesn't know raises an error on modern
-- clients, so do it under pcall.
function C.SafeRegister(frame, event)
    return pcall(frame.RegisterEvent, frame, event)
end
