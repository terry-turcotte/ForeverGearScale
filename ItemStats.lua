-- ItemStats.lua
-- "input: stats from both gears". Reads an item link's tooltip text through
-- the Blizzard API and parses it into stat values, with a small cache.

local _, NS = ...
local C = NS.Compat
local ItemStats = {}
NS.ItemStats = ItemStats

local cache = {}

-- Drop the enchant (and gems) from an item link so the equipped piece isn't
-- favoured by its enchant against a fresh drop.
-- item:itemID:enchantID:gem1:gem2:gem3:gem4:...
function ItemStats.StripEnchant(link)
    return (link:gsub("(item:%-?%d+):[^:|]*:[^:|]*:[^:|]*:[^:|]*:[^:|]*", "%1:::::"))
end

-- Key used for "is this the same item": the item string without enchant/gems.
function ItemStats.Key(link)
    local s = ItemStats.StripEnchant(link)
    return s:match("item:[%-%d:]+") or s
end

-- Returns stats, misses — or nil when the item isn't in the client cache yet.
function ItemStats.Get(link)
    if not link or C.IsSecret(link) then return nil end
    if NS.db and NS.db.ignoreEnchants ~= false then link = ItemStats.StripEnchant(link) end
    local hit = cache[link]
    if hit then return hit.stats, hit.miss end

    local ok, lines = pcall(C.GetTooltipLines, link)
    if not ok or not lines or #lines < 2 then return nil end
    -- Uncached items come back as a single "Retrieving item information" line.
    local stats, miss = NS.Parser.Parse(lines)
    cache[link] = { stats = stats, miss = miss }
    return stats, miss
end

-- Sum the stats of several links (e.g. main hand + off hand).
function ItemStats.Sum(links)
    local total, miss = {}, {}
    for _, link in ipairs(links) do
        local s, m = ItemStats.Get(link)
        if not s then return nil end
        for k, v in pairs(s) do total[k] = (total[k] or 0) + v end
        for _, x in ipairs(m) do miss[#miss + 1] = x end
    end
    return total, miss
end

function ItemStats.ClearCache() wipe(cache) end
