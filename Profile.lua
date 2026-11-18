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

local CSI = function() return C_SpecializationInfo or {} end

-- Talent API, whichever one this client has. Newer Classic clients removed the
-- GetTalentTabInfo / GetNumTalents / GetTalentInfo globals and moved them to
-- C_SpecializationInfo (tab info -> GetSpecializationInfo).
local function tabInfoFn() return GetTalentTabInfo or CSI().GetSpecializationInfo end
local function talentInfoFn() return GetTalentInfo or CSI().GetTalentInfo end
local function numTabs()
    local f = GetNumTalentTabs or CSI().GetNumSpecializations
    local ok, n = pcall(f or error)
    return (ok and type(n) == "number" and n > 0) and math.min(n, 3) or 3
end
NS.TalentAPI = { tabInfo = tabInfoFn, talentInfo = talentInfoFn }

-- Tab info changed shape across clients:
--   classic era:   name, icon, pointsSpent, fileName
--   wrath/cata:    id, name, description, icon, pointsSpent, background, ...
--   spec info:     id, name, description, icon, role, primaryStat, pointsSpent, ...
local function readTalentTab(i)
    local f = tabInfoFn()
    if not f then return nil, nil end
    local r = { pcall(f, i) }
    if not r[1] then return nil, nil end
    if type(r[2]) == "table" then
        local t = r[2]
        return t.name, points(t.pointsSpent)
    end
    if type(r[2]) == "string" then return r[2], points(r[4]) end
    local name = (type(r[3]) == "string") and r[3] or nil
    if type(r[6]) == "string" then return name, points(r[8]) end   -- role sits before pointsSpent
    return name, points(r[6])
end

-- One talent's rank and max rank, from whichever GetTalentInfo this client has:
-- the global (name, icon, tier, column, rank, maxRank) or the table-based
-- C_SpecializationInfo.GetTalentInfo({ specializationIndex, talentIndex }).
local function talentRank(tab, i)
    if GetTalentInfo then
        local r = { pcall(GetTalentInfo, tab, i) }
        if not r[1] then return nil end
        if type(r[2]) == "table" then return r[2].rank, r[2].maxRank, true end
        if r[2] == nil then return nil end
        return r[6], r[7], true
    end
    local f = CSI().GetTalentInfo
    if not f then return nil end
    local ok, t = pcall(f, { specializationIndex = tab, talentIndex = i })
    if not ok or type(t) ~= "table" then return nil end
    return t.rank, t.maxRank, true
end

-- Sum of the ranks of every talent in a tree; nil if the client can't tell.
local function countRanks(tab)
    if not talentInfoFn() then return nil end
    local n
    local numFn = GetNumTalents or CSI().GetNumTalents
    if numFn then
        local ok, v = pcall(numFn, tab)
        if ok and type(v) == "number" and v > 0 then n = v end
    end
    local total, found = 0, false
    for i = 1, n or 40 do
        local rank, maxRank, exists = talentRank(tab, i)
        if not exists then
            if n then return nil end
            break                       -- no count given: walk until talents run out
        end
        rank, maxRank = points(rank), points(maxRank)
        if not rank or (maxRank and rank > maxRank) then return nil end
        total, found = total + rank, true
    end
    return found and total or nil
end

-- Returns specIndex (1-3) or nil, the client's spec names, the points read
-- per tree (shown by /fgs status) and whether a talent API was found at all.
local function detectSpec()
    local names, pts = {}, {}
    local n = numTabs()
    local ranks, rankTotal, tabPts, any = {}, 0, {}, false
    for i = 1, n do
        names[i], tabPts[i] = readTalentTab(i)
        ranks[i] = countRanks(i)
        rankTotal = rankTotal + (ranks[i] or 0)
        any = any or ranks[i] ~= nil or tabPts[i] ~= nil
    end
    if any then
        -- Prefer counting the ranks ourselves; fall back to the tab summary.
        local src = rankTotal > 0 and ranks or tabPts
        local best, bestPts = nil, 0
        for i = 1, n do
            pts[i] = src[i] or ranks[i] or tabPts[i]
            if (pts[i] or 0) > bestPts then best, bestPts = i, pts[i] end
        end
        -- Talents readable but none spent: let the preset default decide.
        return best, names, pts
    end
    -- No talent info at all: last resort, the client's own spec index. Forever
    -- returns 1 here whatever the talents, so it's labelled as a guess.
    local getSpec = CSI().GetSpecialization or GetSpecialization
    if getSpec then
        local ok, s = pcall(getSpec)
        if ok and type(s) == "number" and s >= 1 and s <= 3 then return s, names, pts, "client" end
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
    local detected, names, pts, how = detectSpec()
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
        source = override and "manual" or (detected and (how or "talents") or "default"),
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
    if profile.source == "default" or profile.source == "client" then current = nil end
    return profile
end
