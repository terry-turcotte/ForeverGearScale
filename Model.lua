-- Model.lua
-- A small Retribution Paladin damage model (Seal of Command rotation). Pure
-- Lua, no game API, so it runs in the offline tests.
--
-- The DPS axis comes from here: weights are the marginal DPS of each stat at
-- your *current* character sheet, so they move as you gear (hit is worth 0
-- once capped, crit is worth less once Vengeance never drops).
--
-- Rotation modelled:
--   white swings (2H) + Seal of Command procs (7 PPM, 70% weapon damage)
--   + Holy Strike on cooldown (10 sec) + Judgement of Command every `judge`
--   sec + Hammer of Wrath during the last `execute` part of the fight, all
--   multiplied by the average Vengeance bonus.
--
-- Spell numbers (base damage, weapon %, cooldown) are read in game from your
-- own spell tooltips when possible (st.spells, see Character.lua); the
-- constants below are the fallback: vanilla level-60 / pre-launch values.

local _, NS = ...
local Model = {}
NS.Model = Model

Model.CONST = {
    apPerStr = 2,           -- paladins: 1 Strength = 2 Attack Power
    agiPerCrit = 20,        -- 20 Agility = 1% melee crit
    intPerSpellCrit = 54,   -- 54 Intellect = 1% spell crit
    championPerRank = 0.12, -- Champion of the Light: 12% of Intellect as spell damage per rank (60% at 5/5)
    vengeancePerRank = 1,   -- Vengeance: +1% damage per rank per stack (3% at 3/3)
    vengeanceStacks = 5,
    vengeanceDuration = 30,
    socPPM = 7, socWeapon = 0.7, socCoef = 0.2,
    -- Judgement of Command, rank 5: 68.5 to 73.5 Holy damage (double only on a
    -- stunned target, which bosses never are).
    jocBase = 71, jocCoef = 0.429,
    -- Holy Strike (baseline, rank 8): instant melee strike, Holy damage =
    -- 50% weapon damage + 0.429 x spell damage. Sacred Arbiter: +20%.
    holyStrikeWeapon = 0.5, holyStrikeBase = 0, holyStrikeCoef = 0.429, holyStrikeCD = 10,
    sacredArbiterBonus = 0.2,
    -- Hammer of Wrath: learned at 44 in Forever (ranks at 44 / 52 / 60), 6 sec
    -- cooldown, 1 sec cast (instant with Champion of the Light 5/5).
    howBase = 370, howCoef = 0.429, howCD = 6, howLevel = 44,
}
local K = Model.CONST

Model.DEFAULT_FIGHT = { judge = 9, execute = 0.2 }

-- A level-60 Ret with blues/epics, used when the client gives us nothing.
function Model.DefaultState()
    return {
        level = 60, target = 63,
        ap = 1100, crit = 18, hit = 3, wskill = 300, wdps = 60, speed = 3.6,
        sp = 60, spcrit = 8, spellhit = 0,
        talents = { vengeance = 0, champion = 0, sacredArbiter = 0, holyStrike = 1 },
        fight = { judge = 9, execute = 0.2 },
    }
end

local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end

-- Average number of Vengeance stacks over the events that can benefit from it.
-- p = chance an event is a crit, n = events per buff duration (the buff drops
-- after n non-crits in a row). Exact solution of the stack chain:
--   at 0 stacks you wait 1/p events for a crit;
--   at s >= 1 you spend (1 - q^n)/p events, then go up (prob a = 1 - q^n) or
--   drop to 0.
function Model.VengeanceStacks(p, n, maxStacks)
    maxStacks = maxStacks or K.vengeanceStacks
    if p <= 0 or n <= 0 then return 0 end
    if p >= 1 then return maxStacks end
    local q = 1 - p
    local a = 1 - q ^ n
    if a >= 1 - 1e-12 then return maxStacks end
    -- embedded chain weights (pi), time spent per visit (T)
    local pi = { [0] = 1, 1 }
    for s = 2, maxStacks - 1 do pi[s] = pi[s - 1] * a end
    pi[maxStacks] = (maxStacks > 1 and pi[maxStacks - 1] or 1) * a / (1 - a)
    local num, den = 0, pi[0] / p
    for s = 1, maxStacks do
        local t = pi[s] * a / p
        num, den = num + s * t, den + t
    end
    return num / den
end

-- Returns total DPS and a breakdown.
function Model.Dps(st)
    local f = st.fight or Model.DEFAULT_FIGHT
    local t = st.talents or {}
    local level, target = st.level or 60, st.target or 63
    local skill = st.wskill or level * 5

    -- Melee attack table (vanilla rules).
    local d = math.max(0, target * 5 - skill)
    -- 8% vs a level 63 boss, +1% because the first 1% of hit is ignored
    -- there: the usual "9% hit cap".
    local miss = 5 + d * (d > 10 and 0.2 or 0.1) + (d > 10 and 1 or 0)
    miss = math.max(0, miss - (st.hit or 0)) / 100
    local dodge = math.max(0, 5 + d * 0.1) / 100
    local glance = clamp(10 + (target * 5 - math.min(skill, level * 5)) * 2, 0, 60) / 100
    if target < level then glance = 0 end
    local glanceLow = clamp(1.3 - 0.05 * d, 0.01, 0.91)
    local glanceHigh = clamp(1.2 - 0.03 * d, 0.2, 0.99)
    local glanceMult = (glanceLow + glanceHigh) / 2
    local crit = math.max(0, (st.crit or 0) - (d > 10 and 0.2 * d or 0.04 * d)) / 100

    local landed = math.max(0, 1 - miss - dodge)
    local whiteCrit = math.min(crit, math.max(0, landed - glance))
    local specialCrit = math.min(crit, landed)

    local speed = (st.speed and st.speed > 0) and st.speed or 3.6
    local swing = ((st.wdps or 0) + (st.ap or 0) / 14) * speed
    local white = swing / speed * (glance * glanceMult + whiteCrit * 2 + (landed - glance - whiteCrit))

    -- Seal of Command: 7 procs per minute on landed swings, own melee roll.
    -- Spell numbers read from the tooltips win over the constants.
    local S = st.spells or {}
    local function val(key, field, default)
        local v = S[key] and S[key][field]
        return type(v) == "number" and v or default
    end
    local function known(key) return not (S[key] and S[key].known == false) end

    local socPerSec = K.socPPM / 60 * landed
    local sp = st.sp or 0
    local soc = socPerSec * (val("soc", "weapon", K.socWeapon) * swing + K.socCoef * sp) * (landed + specialCrit)

    -- Spells: spell hit table, Judgement and Hammer of Wrath crit with melee crit (x2).
    local spellMissBase = ({ [0] = 4, 5, 6, 17 })[clamp(target - level, 0, 3)]
        + math.max(0, target - level - 3) * 11
    local sHit = 1 - math.max(1, spellMissBase - (st.spellhit or 0)) / 100
    local spcrit = math.max(0, st.spcrit or 0) / 100
    local judge = math.max(1, f.judge or 9)
    local joc = (val("soc", "base", K.jocBase) + K.jocCoef * sp) * sHit * (1 + crit) / judge
    -- Holy Strike: a melee special (miss/dodge, melee crit x2), on cooldown.
    local useHS = (t.holyStrike or 1) > 0 and known("holyStrike")
    local hsCD = math.max(1, val("holyStrike", "cd", K.holyStrikeCD))
    local hs = 0
    if useHS then
        hs = (val("holyStrike", "weapon", K.holyStrikeWeapon) * swing + val("holyStrike", "base", K.holyStrikeBase)
            + K.holyStrikeCoef * sp)
            * (1 + (t.sacredArbiter or 0) * K.sacredArbiterBonus)
            * (landed + specialCrit) / hsCD
    end
    -- Hammer of Wrath: only once learned (level 44), only in the execute phase.
    local useHoW = known("how") and level >= K.howLevel
    local exec = useHoW and clamp(f.execute or 0, 0, 1) or 0
    local howCD = math.max(1, val("how", "cd", K.howCD))
    local how = exec * (val("how", "base", K.howBase) + K.howCoef * sp) * (1 - miss) * (1 + crit) / howCD

    -- Vengeance: every non-periodic hit above can crit and refresh the buff.
    local dur = K.vengeanceDuration
    local events = {
        { dur / speed, whiteCrit },
        { dur * socPerSec, specialCrit },
        { dur / judge, sHit * crit },
        { useHS and dur / hsCD or 0, specialCrit },
        { exec * dur / howCD, (1 - miss) * crit },
    }
    local n, pc = 0, 0
    for _, e in ipairs(events) do n, pc = n + e[1], pc + e[1] * e[2] end
    local stacks = n > 0 and Model.VengeanceStacks(pc / n, math.floor(n + 0.5)) or 0
    local veng = (t.vengeance or 0) * K.vengeancePerRank / 100 * stacks

    local raw = white + soc + joc + hs + how
    return raw * (1 + veng), {
        white = white, soc = soc, joc = joc, holyStrike = hs, how = how,
        vengeance = veng, stacks = stacks, miss = miss, spellMiss = 1 - sHit,
    }
end

-- Stats the model understands, and the step used to measure each one.
Model.STEP = {
    str = 10, agi = 10, int = 10, ap = 10, crit = 1, hit = 1, wskill = 1, wdps = 1,
    spdmg = 10, spboth = 10, spcrit = 1, spellhit = 1,
}

-- New state with item stats `d` added (sign = -1 removes them).
function Model.Apply(st, d, sign)
    sign = sign or 1
    local t = st.talents or {}
    local n = {}
    for k, v in pairs(st) do n[k] = v end
    local function g(id) return (d[id] or 0) * sign end
    local champ = (t.champion or 0) * K.championPerRank
    n.ap = (st.ap or 0) + g("ap") + g("str") * K.apPerStr
    n.crit = (st.crit or 0) + g("crit") + g("agi") / K.agiPerCrit
    n.hit = (st.hit or 0) + g("hit")
    n.wskill = (st.wskill or 300) + g("wskill")
    n.wdps = (st.wdps or 0) + g("wdps")
    n.sp = (st.sp or 0) + g("spdmg") + g("spboth") + g("int") * champ
    n.spcrit = (st.spcrit or 0) + g("spcrit") + g("int") / K.intPerSpellCrit
    n.spellhit = (st.spellhit or 0) + g("spellhit")
    return n
end

-- DPS gained per Attack Power: the anchor of the scale (1 AP = 5 pts).
local function perAP(st, base)
    local up = Model.Dps(Model.Apply(st, { ap = 10 }))
    local v = (up - base) / 10
    return v > 0 and v or nil
end

-- Points per 1 stat on the DPS axis, at the current state.
function Model.Weights(st)
    local base = Model.Dps(st)
    local ap = perAP(st, base)
    local w = {}
    if not ap then return w end
    for id, step in pairs(Model.STEP) do
        local up = Model.Dps(Model.Apply(st, { [id] = step }))
        w[id] = 5 * (up - base) / step / ap
    end
    return w
end

-- Points gained by swapping `equipped` for `candidate`, computed on the full
-- model (not linear), so crossing the hit cap is counted right. Also returns
-- the raw DPS change and the current DPS. Stats in `skip` are left out (the
-- player pinned their weight).
function Model.Delta(st, equipped, candidate, skip)
    local base = Model.Dps(st)
    local ap = perAP(st, base)
    if not ap then return 0, 0, base end
    local d = {}
    for id in pairs(Model.STEP) do
        if not (skip and skip[id]) then
            d[id] = (candidate[id] or 0) - (equipped[id] or 0)
        end
    end
    local n = Model.Apply(st, d)
    -- Weapon swap: the new weapon's speed replaces the old one.
    if candidate.speed and candidate.speed > 0 then n.speed = candidate.speed end
    local gain = Model.Dps(n) - base
    return 5 * gain / ap, gain, base
end

-- Points per 1 DPS at the current state (to turn pinned points back into DPS).
function Model.PointsPerDps(st)
    local ap = perAP(st, Model.Dps(st))
    return ap and 5 / ap or nil
end
