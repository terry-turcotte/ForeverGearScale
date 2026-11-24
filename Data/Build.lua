-- Data/Build.lua
-- The talent build the model assumes. Forever's talent API can't be read
-- reliably, so we don't read talents: we go by build. Change a rank in game
-- with /fgs set <talent> <rank>, or here.
--
-- Ranks are the usual ones for a 12/8/31 Seal of Command raid build. Effects
-- come from the talent guides (vanilla values where Forever kept them); the
-- per-rank numbers live in Model.CONST.

local _, NS = ...

NS.BUILD = {
    name = "12/8/31",
    talents = {
        -- Holy / Protection
        divineStrength = 5,  -- +2% Strength per rank
        divineIntellect = 5, -- +2% Intellect per rank
        improvedSeals = 5,   -- +3% Seal and Judgement damage per rank
        precision = 3,       -- +1% melee hit per rank (already on your character sheet)
        holyConduit = 2,     -- mana cost of Hammer of Wrath & co: no DPS effect (mana isn't modelled)
        sacredDuty = 2,      -- defensive cooldowns: no DPS effect
        -- Retribution
        vengeance = 3,       -- +1% Physical and Holy damage per rank per stack, 5 stacks
        champion = 5,        -- Champion of the Light: 12% of Intellect as spell damage per rank
        sacredArbiter = 1,   -- Holy Strike +20%
        unsealedWrath = 1,   -- bank Seal of Command copies, release with another seal
    },
    -- Display order and names for /fgs build.
    order = {
        { "divineStrength", "Divine Strength" }, { "divineIntellect", "Divine Intellect" },
        { "improvedSeals", "Improved Seals" }, { "precision", "Precision" },
        { "holyConduit", "Holy Conduit" }, { "sacredDuty", "Sacred Duty" },
        { "vengeance", "Vengeance" }, { "champion", "Champion of the Light" },
        { "sacredArbiter", "Sacred Arbiter" }, { "unsealedWrath", "Unsealed Wrath" },
    },
    -- What each talent changes in the model ("" = nothing, said so in /fgs build).
    effect = {
        divineStrength = "Strength from gear x(1 + 2%/rank)",
        divineIntellect = "Intellect from gear x(1 + 2%/rank)",
        improvedSeals = "Seal of Command, Righteousness and Judgement damage +3%/rank",
        precision = "+1% hit/rank, already counted in your sheet's hit",
        holyConduit = "mana only: no DPS effect",
        sacredDuty = "defensive cooldowns: no DPS effect",
        vengeance = "+1%/rank damage per stack (5 stacks, 30 sec)",
        champion = "12%/rank of Intellect as spell damage",
        sacredArbiter = "Holy Strike +20%",
        unsealedWrath = "seal twist: banked Seal of Command procs",
    },
    maxRank = {
        divineStrength = 5, divineIntellect = 5, improvedSeals = 5, precision = 3, holyConduit = 3,
        sacredDuty = 2, vengeance = 3, champion = 5, sacredArbiter = 1, unsealedWrath = 1,
    },
    level = 60,   -- the model always plays a level 60 vs a level 63 boss
}
