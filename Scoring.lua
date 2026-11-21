-- Scoring.lua
-- Pure math: score each side for DPS, diff them, and turn that into a
-- verdict. No game API here.

local _, NS = ...
local Scoring = {}
NS.Scoring = Scoring

-- weights: { statId = points per 1 point of the stat } (1 AP = 5 pts)
function Scoring.Score(stats, weights)
    local t = 0
    for id, v in pairs(stats) do t = t + v * (weights[id] or 0) end
    return t
end

-- "even" unless the change is larger than 1% of the score (and at least 3 pts).
local function classify(d, ref)
    local th = math.max(3, math.abs(ref) * 0.01)
    if d > th then return "gain" elseif d < -th then return "loss" else return "even" end
end
Scoring.Classify = classify

local VERDICT = { gain = "upgrade", loss = "downgrade", even = "sidegrade" }

-- equipped = stats of what you wear (A), candidate = stats of the item (B).
-- delta (optional) replaces the linear difference with the model's.
function Scoring.Compare(equipped, candidate, weights, delta)
    local A, B = Scoring.Score(equipped, weights), Scoring.Score(candidate, weights)
    if delta then B = A + delta end
    local D = B - A
    local status = classify(D, math.max(math.abs(A), math.abs(B)))

    -- Biggest swings, per stat (linear weights).
    local seen, swings = {}, {}
    local function consider(id)
        if seen[id] then return end
        seen[id] = true
        local dv = (candidate[id] or 0) - (equipped[id] or 0)
        local w = weights[id] or 0
        if dv ~= 0 and w ~= 0 then swings[#swings + 1] = { id = id, dv = dv, c = dv * w } end
    end
    for id in pairs(equipped) do consider(id) end
    for id in pairs(candidate) do consider(id) end
    table.sort(swings, function(x, y) return math.abs(x.c) > math.abs(y.c) end)

    return { A = A, B = B, D = D, status = status, verdict = VERDICT[status], swings = swings }
end
