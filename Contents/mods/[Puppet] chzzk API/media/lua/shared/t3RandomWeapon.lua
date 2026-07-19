-- t3RandomWeapon: random_weapon donation feature.
-- Donation grants a melee or ranged weapon box (50/50, decided in rewardManager).
--
-- Melee box: rolls one of the 6 vanilla melee skill categories by weight
-- (CATEGORY_TABLE, weights sum to 100), then picks uniformly among ALL script
-- items belonging to that category. Item pools are enumerated at runtime from
-- getScriptManager():getAllItems() and cached on first open, so vanilla
-- weapons never need to be listed by hand.
--   Pool filters: Type == Weapon, not OBSOLETE, and "Improvised" excluded --
--   except for Spear, where Improvised is allowed (nearly every spear is
--   "Improvised;Spear" and they are real weapons, unlike spoons/plungers).
-- Ranged box: static weight table (clip/ammo pairing needs manual data).
--
-- Global table (no module return) so recipe OnCreate can resolve
-- "t3RandomWeapon.OpenMeleeBox" / "t3RandomWeapon.OpenRangedBox".

t3RandomWeapon = t3RandomWeapon or {}

local LOG = "[PongDu][RandomWeapon] "

-- ── Melee category table (weights sum = 100) ────────────────────────────────
-- Category strings must match vanilla script "Categories" values
-- (see XpUpdate.lua / HandWeapon.java).
t3RandomWeapon.CATEGORY_TABLE = {
    { category = "SmallBlunt", weight = 25 },
    { category = "SmallBlade", weight = 20 },
    { category = "Blunt",      weight = 20 },
    { category = "Spear",      weight = 15 },
    { category = "Axe",        weight = 12 },
    { category = "LongBlade",  weight = 8  },
}

-- Categories where "Improvised" items stay in the pool.
local ALLOW_IMPROVISED = { Spear = true }

-- ── Ranged table (weights sum = 100) ────────────────────────────────────────
-- clip/ammo pairings verified against vanilla ProceduralDistributions
-- (PistolCase1~3, RevolverCase1~3, RifleCase1~3).
t3RandomWeapon.RANGED_TABLE = {
    { item = "Base.AssaultRifle",       weight = 3,  clip = "Base.556Clip",  ammo = "Base.556Box"          },
    { item = "Base.AssaultRifle2",      weight = 4,  clip = "Base.M14Clip",  ammo = "Base.308Box"          },
    { item = "Base.Revolver_Long",      weight = 4,                          ammo = "Base.Bullets44Box"    },
    { item = "Base.Pistol3",            weight = 5,  clip = "Base.44Clip",   ammo = "Base.Bullets44Box"    },
    { item = "Base.Revolver_Short",     weight = 6,                          ammo = "Base.Bullets38Box"    },
    { item = "Base.HuntingRifle",       weight = 8,  clip = "Base.308Clip",  ammo = "Base.308Box"          },
    { item = "Base.DoubleBarrelShotgun", weight = 8,                         ammo = "Base.ShotgunShellsBox" },
    { item = "Base.VarmintRifle",       weight = 10, clip = "Base.223Clip",  ammo = "Base.223Box"          },
    { item = "Base.Revolver",           weight = 10,                         ammo = "Base.Bullets45Box"    },
    { item = "Base.Shotgun",            weight = 12,                         ammo = "Base.ShotgunShellsBox" },
    { item = "Base.Pistol2",            weight = 12, clip = "Base.45Clip",   ammo = "Base.Bullets45Box"    },
    { item = "Base.Pistol",             weight = 18, clip = "Base.9mmClip",  ammo = "Base.Bullets9mmBox"   },
}

-- ── Melee pool cache ────────────────────────────────────────────────────────
-- Authoritative pools come from the server (t3RandomWeaponServer), built from
-- the world loot distribution tables so only naturally-spawning weapons enter.
--   * SP / local host: server lua is loaded locally -> BuildPools() direct.
--   * MP client: requested at OnGameStart, received via OnServerCommand.
--   * Fallback (sync not yet arrived): local vanilla-only build via getModID(),
--     which cannot see distribution tables but at least blocks modded
--     transform-only items (e.g. bayonet-form rifles).
local syncedPools = nil -- server-authoritative (or locally built in SP)
local meleePools = nil  -- fallback cache (vanilla-only)

local function buildMeleePools()
    meleePools = {}
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        meleePools[entry.category] = {}
    end
    local rejectedModded = 0
    local allItems = getScriptManager():getAllItems()
    for i = 1, allItems:size() do
        local scriptItem = allItems:get(i - 1)
        -- Vanilla-only filter. NOTE: matching the "Base." module prefix on
        -- getFullName() is NOT enough — mods (e.g. Arsenal Gunfighter's
        -- Home-key bayonet-form weapons) can register items directly under
        -- module Base instead of their own namespace, so fullName alone lies
        -- about origin. getModID() tracks the actual source mod.info the item
        -- was loaded from; vanilla items report "pz-vanilla" regardless of
        -- which module they declare. Confirmed via Item.java: modID =
        -- ScriptManager.getCurrentLoadFileMod(), independent of module name.
        if scriptItem:getTypeString() == "Weapon" and not scriptItem:getObsolete()
                and scriptItem:getModID() == "pz-vanilla" then
            local cats = scriptItem:getCategories()
            for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
                if cats:contains(entry.category)
                        and (ALLOW_IMPROVISED[entry.category] or not cats:contains("Improvised")) then
                    table.insert(meleePools[entry.category], scriptItem:getFullName())
                    break -- one pool per item; first matching category wins
                end
            end
        elseif scriptItem:getTypeString() == "Weapon" and not scriptItem:getObsolete() then
            rejectedModded = rejectedModded + 1
        end
    end
    print(LOG .. "rejected " .. rejectedModded .. " non-vanilla weapon items (modID check)")
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        print(LOG .. "pool built: " .. entry.category .. " = " .. #meleePools[entry.category] .. " items")
        if #meleePools[entry.category] == 0 then
            print(LOG .. "WARNING: empty pool for category " .. entry.category)
        end
    end
end

-- Weighted pick. Weights must sum to 100.
local function pickWeighted(tbl)
    local roll = ZombRand(100)
    local acc = 0
    for _, entry in ipairs(tbl) do
        acc = acc + entry.weight
        if roll < acc then return entry end
    end
    return tbl[#tbl] -- safety net
end

-- Resolve the pools to draw from, best source first.
local function resolvePools()
    if syncedPools then return syncedPools, "synced" end
    if not isClient() and t3RandomWeaponServer then
        -- SP (or any context where server lua is loaded): build directly from
        -- the distribution tables, no network round trip needed.
        syncedPools = t3RandomWeaponServer.BuildPools()
        return syncedPools, "local-server"
    end
    if not meleePools then buildMeleePools() end
    return meleePools, "fallback"
end

-- Roll category by weight, then uniform pick inside the category pool.
local function pickMeleeItem()
    local pools, source = resolvePools()
    local catEntry = pickWeighted(t3RandomWeapon.CATEGORY_TABLE)
    local pool = pools[catEntry.category]
    if not pool or #pool == 0 then
        print(LOG .. "ERROR: no items in category " .. tostring(catEntry.category) .. " (source=" .. source .. "), falling back to Base.Hammer")
        return "Base.Hammer", catEntry.category
    end
    local itemName = pool[ZombRand(#pool) + 1]
    print(LOG .. "rolled category=" .. catEntry.category .. " item=" .. itemName .. " (pool size " .. #pool .. ", source=" .. source .. ")")
    return itemName, catEntry.category
end

-- Read the donor name stashed on the box item's modData at grant time.
-- OnCreate(items, result, player): items = source items consumed by the recipe.
local function findDonor(items)
    if not items then return "" end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getModData then
            local donor = it:getModData().t3Donor
            if donor and donor ~= "" then return donor end
        end
    end
    return ""
end

local function grant(player, itemName, donor, clip, ammo)
    local inv = player:getInventory()
    local weapon = inv:AddItem(itemName)
    if weapon then
        if donor ~= "" then
            weapon:setName(donor .. "'s " .. weapon:getDisplayName())
        end
        player:Say(weapon:getDisplayName() .. "!")
    else
        print(LOG .. "ERROR: AddItem failed for " .. tostring(itemName))
    end
    if clip then inv:AddItem(clip) end
    if ammo then inv:AddItem(ammo) end
end

-- Recipe OnCreate handlers -------------------------------------------------
-- Easter egg: 1% chance the melee box contains John Wick's Pencil instead of
-- a category roll. Item defined in t3_rewards_items.txt (Improvised category +
-- non-Base module keeps it out of the normal pools).
local EASTER_EGG_CHANCE = 1 -- percent
local EASTER_EGG_ITEM = "t3chzzkDonation.JohnWickPencil"

function t3RandomWeapon.OpenMeleeBox(items, result, player)
    if not player then return end
    local itemName
    if ZombRand(100) < EASTER_EGG_CHANCE then
        itemName = EASTER_EGG_ITEM
        print(LOG .. "EASTER EGG rolled: " .. itemName)
    else
        itemName = pickMeleeItem()
    end
    grant(player, itemName, findDonor(items))
end

function t3RandomWeapon.OpenRangedBox(items, result, player)
    if not player then return end
    local entry = pickWeighted(t3RandomWeapon.RANGED_TABLE)
    print(LOG .. "rolled ranged item=" .. entry.item)
    grant(player, entry.item, findDonor(items), entry.clip, entry.ammo)
end

-- ── MP pool sync ────────────────────────────────────────────────────────────
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuRandomWeapon" or command ~= "Pools" then return end
    if not args or not args.pools then
        print(LOG .. "WARNING: Pools command received without payload")
        return
    end
    syncedPools = args.pools
    local summary = {}
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        local pool = syncedPools[entry.category]
        table.insert(summary, entry.category .. "=" .. tostring(pool and #pool or 0))
    end
    print(LOG .. "pools synced from server: " .. table.concat(summary, " "))
end)

Events.OnGameStart.Add(function()
    if isClient() then
        print(LOG .. "requesting weapon pools from server")
        sendClientCommand("PongDuRandomWeapon", "RequestPools", {})
    end
end)
