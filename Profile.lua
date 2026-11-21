-- Profile.lua
-- "pull: current character + weights". Paladin only: reads the character
-- sheet and talents, runs the Ret model to get live DPS weights, then applies
-- the stats the player pinned with /fgs weight.

local _, NS = ...
local Profile = {}
NS.Profile = Profile

local current

function Profile.Invalidate() current = nil end

function Profile.IsPaladin()
    local _, classFile = UnitClass("player")
    return classFile == "PALADIN"
end

function Profile.Get()
    if current then return current end
    if not Profile.IsPaladin() then return nil end
    local db, Model, RET = NS.db, NS.Model, NS.RET

    local st, estimated = NS.Character.Read(db.fight, db.talents)

    local weights, pinned = {}, {}
    for id, w in pairs(RET.weights) do weights[id] = w end
    for id, w in pairs(Model.Weights(st)) do weights[id] = w end
    for id, w in pairs(db.pins) do weights[id], pinned[id] = w, true end

    local dps, parts = Model.Dps(st)
    local ptsPerDps = Model.PointsPerDps(st)
    current = {
        specName = RET.name,
        weights = weights,
        pinned = pinned,
        overridden = next(pinned) ~= nil,
        state = st,
        estimated = estimated,
        dps = dps,
        parts = parts,
    }

    -- Swap `equipped` for `candidate`: points, and the DPS change. Full model
    -- for the stats it knows; the weight for pinned stats and anything else.
    function current.dpsDelta(equipped, candidate)
        local pts, gain = Model.Delta(st, equipped, candidate, pinned)
        local extra, seen = 0, {}
        local function linear(id)
            if seen[id] then return end
            seen[id] = true
            if pinned[id] or not Model.STEP[id] then
                local w = weights[id]
                if w and w ~= 0 then extra = extra + ((candidate[id] or 0) - (equipped[id] or 0)) * w end
            end
        end
        for id in pairs(equipped) do linear(id) end
        for id in pairs(candidate) do linear(id) end
        if ptsPerDps then gain = gain + extra / ptsPerDps end
        return pts + extra, gain
    end
    return current
end
