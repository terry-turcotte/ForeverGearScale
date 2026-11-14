-- Scoring.lua
-- Pure math, same rules as the web page: score each side on 3 axes, diff them,
-- weight by axis priority, and turn that into a verdict. No game API here.

local _, NS = ...
local Scoring = {}
NS.Scoring = Scoring

function Scoring.Score(stats, weights)
    local t = { 0, 0, 0 }
    for id, v in pairs(stats) do
        local w = weights[id]
        if w then
            for i = 1, 3 do t[i] = t[i] + v * (w[i] or 0) end
        end
    end
    return t
end

-- "even" unless the change is larger than 1% of the axis (and at least 3 pts).
local function classify(d, ref)
    local th = math.max(3, math.abs(ref) * 0.01)
    if d > th then return "gain" elseif d < -th then return "loss" else return "even" end
end
Scoring.Classify = classify

-- equipped = stats of what you wear (A), candidate = stats of the item (B).
function Scoring.Compare(equipped, candidate, weights, prio)
    local A, B = Scoring.Score(equipped, weights), Scoring.Score(candidate, weights)
    local D, status = {}, {}
    local ups, downs = 0, 0
    for i = 1, 3 do
        D[i] = B[i] - A[i]
        status[i] = classify(D[i], math.max(math.abs(A[i]), math.abs(B[i])))
        if (prio[i] or 0) > 0 then
            if status[i] == "gain" then ups = ups + 1 elseif status[i] == "loss" then downs = downs + 1 end
        end
    end

    local total, ref = 0, 0
    for i = 1, 3 do
        total = total + D[i] * (prio[i] or 0) / 100
        ref = ref + math.abs(A[i]) * (prio[i] or 0) / 100
    end

    local verdict
    if ups == 0 and downs == 0 then verdict = "sidegrade"
    elseif downs == 0 then verdict = "upgrade"
    elseif ups == 0 then verdict = "downgrade"
    else verdict = "tradeoff" end

    -- Biggest weighted swings, per stat.
    local seen, swings = {}, {}
    local function consider(id)
        if seen[id] then return end
        seen[id] = true
        local dv = (candidate[id] or 0) - (equipped[id] or 0)
        if dv ~= 0 then
            local w, c = weights[id] or { 0, 0, 0 }, 0
            for i = 1, 3 do c = c + dv * (w[i] or 0) * (prio[i] or 0) / 100 end
            swings[#swings + 1] = { id = id, dv = dv, c = c }
        end
    end
    for id in pairs(equipped) do consider(id) end
    for id in pairs(candidate) do consider(id) end
    table.sort(swings, function(x, y) return math.abs(x.c) > math.abs(y.c) end)

    return {
        A = A, B = B, D = D, status = status,
        total = total, totalStatus = classify(total, ref),
        verdict = verdict, swings = swings,
    }
end
