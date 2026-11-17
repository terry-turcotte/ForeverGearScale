-- Profile.lua
-- "pull: current class + preset class weights". Works out the player's class
-- and spec, then merges the preset with the player's saved overrides.

local _, NS = ...
local Profile = {}
NS.Profile = Profile

local current

-- A talent point count we can trust: a whole number in a sane range. Some
-- clients return ids, file ids or icons where older ones had pointsSpent, so
-- anything else is treated as "unknown".
local function points(v)
    v = tonumber(v)
    if v and v >= 0 and v <= 100 and v == math.floor(v) then return v end
end

-- Talent tab info changed shape across clients:
--   classic era: name, icon, pointsSpent, fileName
--   later:       id, name, description, icon, pointsSpent, ...
local function readTalentTab(i)
    local r = { pcall(GetTalentTabInfo, i) }
    if not r[1] then return nil, nil end
    if type(r[2]) == "string" then return r[2], points(r[4]) end
    return (type(r[3]) == "string") and r[3] or nil, points(r[6])
end

-- Sum of the ranks of every talent in a tree; nil if the client can't tell.
-- GetTalentInfo has been stable for this: name, icon, tier, column, rank, maxRank.
local function countRanks(tab)
    if not (GetNumTalents and GetTalentInfo) then return nil end
    local ok, n = pcall(GetNumTalents, tab)
    if not ok or type(n) ~= "number" or n <= 0 then return nil end
    local total = 0
    for i = 1, n do
        local r = { pcall(GetTalentInfo, tab, i) }
        if not r[1] then return nil end
        local rank, maxRank
        if type(r[2]) == "table" then
            rank, maxRank = r[2].rank, r[2].maxRank
        else
            rank, maxRank = r[6], r[7]
        end
        rank, maxRank = points(rank), points(maxRank)
        if not rank or (maxRank and rank > maxRank) then return nil end
        total = total + rank
    end
    return total
end

-- Returns specIndex (1-3) or nil, the client's spec names, and the points
-- read per tree (shown by /fgs status).
local function detectSpec()
    local names, pts = {}, {}
    -- Talent points are the most reliable signal on a Classic-style tree.
    if GetTalentTabInfo then
        local n = (GetNumTalentTabs and GetNumTalentTabs()) or 3
        local ranks, rankTotal, tabPts = {}, 0, {}
        for i = 1, math.min(n, 3) do
            names[i], tabPts[i] = readTalentTab(i)
            ranks[i] = countRanks(i)
            rankTotal = rankTotal + (ranks[i] or 0)
        end
        -- Prefer counting the ranks ourselves; fall back to the tab summary.
        local src = rankTotal > 0 and ranks or tabPts
        local best, bestPts = nil, 0
        for i = 1, math.min(n, 3) do
            pts[i] = src[i] or 0
            if pts[i] > bestPts then best, bestPts = i, pts[i] end
        end
        if best then return best, names, pts end
    end
    -- Modern specialization API, if Forever exposes it.
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    if getSpec then
        local ok, s = pcall(getSpec)
        if ok and type(s) == "number" and s >= 1 and s <= 3 then return s, names, pts end
    end
    return nil, names, pts
end

function Profile.Invalidate() current = nil end

function Profile.Get()
    if current then return current end
    local _, classFile = UnitClass("player")
    local presets = classFile and NS.PRESETS[classFile]
    if not presets then return nil end

    local db = NS.db
    local detected, names, pts = detectSpec()
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
        talentPoints = pts,
    }
    -- Talent data can arrive after the first tooltip; don't freeze the
    -- fallback, try again next time.
    local profile = current
    if profile.source == "default" then current = nil end
    return profile
end
