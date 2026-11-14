-- Tooltip.lua
-- The event from the sketch: an item tooltip is shown. We find what the player
-- wears in that slot, score both items with the current class/spec weights,
-- and add the result to the tooltip.

local _, NS = ...
local C = NS.Compat
local ItemStats = NS.ItemStats
local Tooltip = {}
NS.Tooltip = Tooltip

local GOLD = "|cffe3bb5e"
local GREY = "|cff9b8f80"
local COLOR = {
    gain = { 0.47, 0.83, 0.54 },
    loss = { 1.00, 0.44, 0.44 },
    even = { 0.61, 0.56, 0.50 },
}
local AXIS_COLOR = { "|cfff0a04b", "|cff6aa8ff", "|cffb48cff" }
local VERDICT = {
    upgrade   = "|cff78d48a▲ Upgrade|r",
    downgrade = "|cffff6f6f▼ Downgrade|r",
    tradeoff  = GOLD .. "⚖ Trade-off|r",
    sidegrade = GREY .. "≈ Sidegrade|r",
}

-- equipLoc -> inventory slots it can go in
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 },
    INVTYPE_RELIC = { 18 },
}
local SLOT_NAME = {
    [11] = "Ring 1", [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2",
    [16] = "Main hand", [17] = "Off hand",
}
local OFFHAND_WEAPON = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }

local function fmt(x, signed)
    local r = math.floor(x + 0.5)
    if signed and r > 0 then return "+" .. r end
    return tostring(r)
end
local function fmtStat(x)
    local r = math.floor(x * 100 + 0.5) / 100
    return (r > 0 and "+" or "") .. r
end

-- Every way the candidate could be worn: a list of { label, links }.
local function equippedOptions(equipLoc)
    local slots = SLOTS[equipLoc]
    if not slots then return nil end
    local opts = {}
    if equipLoc == "INVTYPE_2HWEAPON" then
        local links = {}
        for _, s in ipairs({ 16, 17 }) do
            local l = GetInventoryItemLink("player", s)
            if l then links[#links + 1] = l end
        end
        opts[1] = { label = "Main + Off hand", links = links }
        return opts
    end
    for _, s in ipairs(slots) do
        local l = GetInventoryItemLink("player", s)
        local skip = false
        -- A one-hander only competes with the off hand if you already dual-wield.
        if equipLoc == "INVTYPE_WEAPON" and s == 17 then
            skip = not (l and OFFHAND_WEAPON[C.GetEquipLoc(l)])
        end
        if not skip then
            local label = SLOT_NAME[s]
            if s == 16 and l and C.GetEquipLoc(l) == "INVTYPE_2HWEAPON" then label = "Two-hand" end
            opts[#opts + 1] = { label = label, slot = s, links = { l } }
        end
    end
    return opts
end

local function addSpacer(tt) tt:AddLine(" ") end

local function render(tt, profile, res, label, missCount, isEquipped)
    addSpacer(tt)
    local header = GOLD .. "Gear Scale|r " .. GREY .. "· " .. (profile.specName or "?") .. "|r"
    if isEquipped then
        tt:AddDoubleLine(header, GREY .. "Equipped|r")
        for i = 1, 3 do
            if (profile.prio[i] or 0) > 0 then
                tt:AddDoubleLine("  " .. AXIS_COLOR[i] .. profile.axes[i] .. "|r", fmt(res.B[i]), 1, 1, 1, 1, 1, 1)
            end
        end
        return
    end

    tt:AddDoubleLine(header, VERDICT[res.verdict])
    for i = 1, 3 do
        if (profile.prio[i] or 0) > 0 then
            local c = COLOR[res.status[i]]
            tt:AddDoubleLine(
                "  " .. AXIS_COLOR[i] .. profile.axes[i] .. "|r " .. GREY .. fmt(res.A[i]) .. " → " .. fmt(res.B[i]) .. "|r",
                fmt(res.D[i], true), 1, 1, 1, c[1], c[2], c[3])
        end
    end
    local c = COLOR[res.totalStatus]
    tt:AddDoubleLine("  Weighted total" .. (label and (GREY .. "  vs " .. label .. "|r") or ""),
        fmt(res.total, true), 1, 1, 1, c[1], c[2], c[3])

    if IsShiftKeyDown() then
        for n = 1, math.min(4, #res.swings) do
            local s = res.swings[n]
            local sc = COLOR[s.c > 0 and "gain" or (s.c < 0 and "loss" or "even")]
            local name = (NS.STAT_BY_ID[s.id] and NS.STAT_BY_ID[s.id].name) or s.id
            tt:AddDoubleLine("    " .. name .. " " .. GREY .. fmtStat(s.dv) .. "|r", fmt(s.c, true),
                0.8, 0.8, 0.8, sc[1], sc[2], sc[3])
        end
        if missCount > 0 then
            tt:AddLine("    " .. GREY .. missCount .. " special effect(s) not scored|r")
        end
    elseif NS.db.showHint then
        tt:AddLine("  " .. GREY .. "Shift: biggest stat swings|r")
    end
end

local function onItemTooltip(tt)
    if not NS.db or not NS.db.enabled then return end
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end   -- skip shopping/compare tooltips
    local link = C.GetTooltipItem(tt)
    if not link or C.IsSecret(link) then return end

    local equipLoc = C.GetEquipLoc(link)
    local opts = equipLoc and equippedOptions(equipLoc)
    if not opts or #opts == 0 then return end

    local profile = NS.Profile.Get()
    if not profile then return end

    local candidate, candMiss = ItemStats.Get(link)
    if not candidate then return end

    -- Hovering something you already wear: just show its scores.
    local key = ItemStats.Key(link)
    for _, o in ipairs(opts) do
        for _, l in ipairs(o.links) do
            if ItemStats.Key(l) == key then
                local res = NS.Scoring.Compare({}, candidate, profile.weights, profile.prio)
                render(tt, profile, res, nil, 0, true)
                tt:Show()
                return
            end
        end
    end

    -- Otherwise compare against each slot it could replace; keep the best.
    local best, bestLabel
    for _, o in ipairs(opts) do
        local eq = ItemStats.Sum(o.links)
        if eq then
            local res = NS.Scoring.Compare(eq, candidate, profile.weights, profile.prio)
            if not best or res.total > best.total then best, bestLabel = res, o.label end
        end
    end
    if not best then return end
    render(tt, profile, best, bestLabel, #candMiss, false)
    tt:Show()   -- resize to fit the new lines
end

function Tooltip.Init()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
            local ok, err = pcall(onItemTooltip, tt)
            if not ok and NS.db and NS.db.debug then print("|cffe3bb5eGearScale|r error: " .. tostring(err)) end
        end)
    else
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            if tt and tt.HookScript then
                pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self) pcall(onItemTooltip, self) end)
            end
        end
    end
end

-- Re-draw the tooltip when Shift is pressed/released.
function Tooltip.OnModifierChanged()
    if GameTooltip and GameTooltip:IsShown() and GameTooltip.RefreshData then
        pcall(GameTooltip.RefreshData, GameTooltip)
    end
end
