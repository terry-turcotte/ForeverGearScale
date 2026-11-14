-- Profile.lua
-- "pull: current class + preset class weights". Works out the player's class
-- and spec, then merges the preset with the player's saved overrides.

local _, NS = ...
local Profile = {}
NS.Profile = Profile

local current

-- Talent tab info changed shape across clients:
--   classic era: name, icon, pointsSpent, fileName
--   later:       id, name, description, icon, pointsSpent, ...
local function readTalentTab(i)
    local r = { pcall(GetTalentTabInfo, i) }
    if not r[1] then return nil, 0 end
    if type(r[2]) == "number" then
        return r[3], tonumber(r[6]) or 0
    end
    return r[2], tonumber(r[4]) or 0
end

-- Returns specIndex (1-3) or nil, plus the client's spec names when known.
local function detectSpec()
    local names = {}
    -- Talent points are the most reliable signal on a Classic-style tree.
    if GetTalentTabInfo then
        local best, bestPts = nil, 0
        local n = (GetNumTalentTabs and GetNumTalentTabs()) or 3
        for i = 1, math.min(n, 3) do
            local name, pts = readTalentTab(i)
            names[i] = name
            if pts > bestPts then best, bestPts = i, pts end
        end
        if best then return best, names end
    end
    -- Modern specialization API, if Forever exposes it.
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    if getSpec then
        local ok, s = pcall(getSpec)
        if ok and type(s) == "number" and s >= 1 and s <= 3 then return s, names end
    end
    return nil, names
end

function Profile.Invalidate() current = nil end

function Profile.Get()
    if current then return current end
    local _, classFile = UnitClass("player")
    local presets = classFile and NS.PRESETS[classFile]
    if not presets then return nil end

    local db = NS.db
    local detected, names = detectSpec()
    local override = db.specOverride[classFile]
    local specIndex = override or detected or presets.defaultSpec
    local preset = presets[specIndex]
    local key = classFile .. ":" .. specIndex

    local weights = {}
    for id, w in pairs(preset.weights) do weights[id] = { w[1], w[2], w[3] } end
    for id, w in pairs(db.weights[key] or {}) do weights[id] = { w[1], w[2], w[3] } end

    current = {
        classFile = classFile,
        specIndex = specIndex,
        specName = (names and names[specIndex]) or preset.name,
        source = override and "manual" or (detected and "talents" or "default"),
        key = key,
        role = preset.role,
        axes = preset.axes,
        prio = db.prio[key] or preset.prio,
        weights = weights,
        overridden = db.weights[key] ~= nil,
    }
    return current
end
