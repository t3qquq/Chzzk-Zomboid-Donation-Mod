-- t3RandomWeaponServer: builds the melee weapon-box pools on the SERVER from
-- the actual world loot distribution tables, then syncs them to clients.
--
-- Why server-side: ProceduralDistributions / SuburbsDistributions /
-- VehicleDistributions live in media/lua/server, which MP clients never load.
-- The box-opening recipe OnCreate runs on the client, so the server scans the
-- tables once, builds the 6-category pools, and pushes them down via
-- sendServerCommand. In singleplayer this file is loaded locally, so
-- t3RandomWeapon (shared) calls BuildPools() directly with no round trip.
--
-- Whitelist rule: an item may enter a pool only if its name appears somewhere
-- in the loot distribution tables, i.e. it can naturally spawn in the world.
-- This excludes transform-only items such as Arsenal Gunfighter's Home-key
-- bayonet forms (never distributed) while keeping modded melee weapons that
-- legitimately spawn. Known gap: spawn paths outside these tables (foraging,
-- zone stories) are not seen, but no melee weapon relies solely on those.

t3RandomWeaponServer = t3RandomWeaponServer or {}

local LOG = "[PongDu][RandomWeaponServer] "

local cachedPools = nil

-- ── Distribution scan ───────────────────────────────────────────────────────
-- Collects every string that appears in an "items" / "junk" array anywhere in
-- the distribution tables. Entries alternate name, weight, name, weight ...
-- Names may or may not carry a module prefix ("Axe" vs "Base.Axe"), so the
-- whitelist stores both the raw string and its last dot-segment.

local function addName(set, name)
    if type(name) ~= "string" then return end
    set[name] = true
    local short = string.match(name, "([^%.]+)$")
    if short then set[short] = true end
end

local function scanTable(tbl, set, depth, visited)
    if type(tbl) ~= "table" or depth > 8 or visited[tbl] then return end
    visited[tbl] = true
    for k, v in pairs(tbl) do
        if (k == "items" or k == "junk") and type(v) == "table" then
            for i = 1, #v, 2 do
                addName(set, v[i])
            end
        elseif type(v) == "table" then
            scanTable(v, set, depth + 1, visited)
        end
    end
end

local function buildWhitelist()
    local set = {}
    local visited = {}
    local sources = 0
    if ProceduralDistributions and ProceduralDistributions.list then
        scanTable(ProceduralDistributions.list, set, 1, visited)
        sources = sources + 1
    end
    if SuburbsDistributions then
        scanTable(SuburbsDistributions, set, 1, visited)
        sources = sources + 1
    end
    if VehicleDistributions then
        scanTable(VehicleDistributions, set, 1, visited)
        sources = sources + 1
    end
    local count = 0
    for _ in pairs(set) do count = count + 1 end
    print(LOG .. "distribution whitelist built: " .. count .. " names from " .. sources .. " tables")
    if sources == 0 then
        print(LOG .. "WARNING: no distribution tables found; whitelist empty")
    end
    return set, sources
end

-- ── Pool build ──────────────────────────────────────────────────────────────
-- Category rules mirror t3RandomWeapon (shared): 6 skill categories,
-- Improvised excluded except for Spear.

local ALLOW_IMPROVISED = { Spear = true }

function t3RandomWeaponServer.BuildPools()
    if cachedPools then return cachedPools end
    local whitelist, sources = buildWhitelist()
    local pools = {}
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        pools[entry.category] = {}
    end
    local rejectedNotDistributed = 0
    local allItems = getScriptManager():getAllItems()
    for i = 1, allItems:size() do
        local scriptItem = allItems:get(i - 1)
        if scriptItem:getTypeString() == "Weapon" and not scriptItem:getObsolete() then
            local inWorld = whitelist[scriptItem:getFullName()] or whitelist[scriptItem:getName()]
            if inWorld then
                local cats = scriptItem:getCategories()
                for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
                    if cats:contains(entry.category)
                            and (ALLOW_IMPROVISED[entry.category] or not cats:contains("Improvised")) then
                        table.insert(pools[entry.category], scriptItem:getFullName())
                        break
                    end
                end
            else
                rejectedNotDistributed = rejectedNotDistributed + 1
            end
        end
    end
    print(LOG .. "rejected " .. rejectedNotDistributed .. " weapon items not present in world distributions")
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        print(LOG .. "pool built: " .. entry.category .. " = " .. #pools[entry.category] .. " items")
        if #pools[entry.category] == 0 then
            print(LOG .. "WARNING: empty pool for category " .. entry.category)
        end
    end
    -- Only cache a meaningful result; if the distribution tables were missing
    -- entirely, retry on the next request instead of freezing empty pools.
    if sources > 0 then
        cachedPools = pools
    end
    return pools
end

-- ── Client sync ─────────────────────────────────────────────────────────────
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "PongDuRandomWeapon" then return end
    if command == "RequestPools" then
        print(LOG .. "pool request from " .. tostring(player and player:getUsername()))
        sendServerCommand(player, "PongDuRandomWeapon", "Pools", { pools = t3RandomWeaponServer.BuildPools() })
    end
end)
