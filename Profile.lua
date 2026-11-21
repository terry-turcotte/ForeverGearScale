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

local function copy(w) return { w[1], w[2], w[3] } end

function Profile.Get()
    if current then return current end
    if not Profile.IsPaladin() then return nil end
    local db, Model, RET = NS.db, NS.Model, NS.RET

    local st, estimated = NS.Character.Read(db.fight, db.talents)
    local live = Model.Weights(st)

    local weights, pinned = {}, {}
    for id, w in pairs(RET.weights) do weights[id] = copy(w) end
    for id, v in pairs(live) do
        weights[id] = weights[id] or { 0, 0, 0 }
        weights[id][1] = v
    end
    for id, w in pairs(db.pins) do weights[id], pinned[id] = copy(w), true end

    local dps, parts = Model.Dps(st)
    current = {
        specName = RET.name,
        axes = RET.axes,
        prio = db.prio or RET.prio,
        weights = weights,
        pinned = pinned,
        overridden = next(pinned) ~= nil,
        state = st,
        estimated = estimated,
        dps = dps,
        parts = parts,
    }

    -- DPS-axis change for a swap: full model for the stats it knows, the
    -- linear weight for pinned stats and anything else with a DPS weight.
    function current.dpsDelta(equipped, candidate)
        local d = Model.Delta(st, equipped, candidate, pinned)
        local seen = {}
        local function linear(id)
            if seen[id] then return end
            seen[id] = true
            if pinned[id] or not Model.STEP[id] then
                local w = weights[id]
                if w and w[1] ~= 0 then d = d + ((candidate[id] or 0) - (equipped[id] or 0)) * w[1] end
            end
        end
        for id in pairs(equipped) do linear(id) end
        for id in pairs(candidate) do linear(id) end
        return d
    end
    return current
end
