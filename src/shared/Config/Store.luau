--!strict
-- Phase 6 store. Policy, enforced by Pure/StoreRules and the specs:
--   * Everything sold or dropped is cosmetic (Config/Cosmetics `source` items). Nothing changes gameplay.
--   * Credits are earned by play only. They are never sold for Robux, so nothing random is ever
--     paid for, directly or through a currency.
--   * Supply and Gear crates are earned by play only (level-ups, finishing all three dailies).
--     Their odds are shown before opening, and they never give an item the player already owns.
--   * Robux buys fixed, named bundles (developer products). The player always knows exactly what
--     they get. Product ids are 0 until the owner creates the products on the published game; a
--     bundle with id 0 is shown as unavailable and cannot be bought.

export type Grant = { kind: string, id: string } -- kind: "Camo" | "Title" | "Emblem" | "Gear"

export type ShopItem = {
	id: string,
	name: string,
	price: number, -- credits
	grant: Grant,
}

export type CrateEntry = { kind: string, id: string, weight: number }
export type CrateDef = {
	id: string,
	name: string,
	pool: { CrateEntry },
	duplicateCredits: number, -- given instead when the player already owns everything in the pool
}

export type PremiumBundle = {
	id: string,
	name: string,
	description: string,
	productId: number, -- Roblox developer product id; 0 = not created yet (unavailable)
	robux: number, -- display price; the real price is the one set on the product
	grants: { Grant },
}

local shop: { ShopItem } = {
	{ id = "CamoObsidian", name = "Obsidian camo", price = 2500, grant = { kind = "Camo", id = "Obsidian" } },
	{ id = "CamoCobalt", name = "Cobalt camo", price = 2500, grant = { kind = "Camo", id = "Cobalt" } },
	{ id = "CamoEmber", name = "Ember camo", price = 4000, grant = { kind = "Camo", id = "Ember" } },
	{ id = "TitleQuartermaster", name = "Quartermaster title", price = 1500, grant = { kind = "Title", id = "Quartermaster" } },
	{ id = "EmblemWolf", name = "Wolf emblem", price = 2000, grant = { kind = "Emblem", id = "Wolf" } },
	{ id = "GearDesertRecon", name = "Desert Recon gear", price = 3000, grant = { kind = "Gear", id = "DesertRecon" } },
}

local crates: { CrateDef } = {
	{
		id = "Supply",
		name = "Supply Crate",
		duplicateCredits = 500,
		pool = {
			{ kind = "Camo", id = "RustBloom", weight = 20 },
			{ kind = "Camo", id = "Tidewater", weight = 20 },
			{ kind = "Camo", id = "Sandstorm", weight = 10 },
			{ kind = "Title", id = "Scrapper", weight = 15 },
			{ kind = "Title", id = "NightOwl", weight = 10 },
			{ kind = "Title", id = "LuckyCharm", weight = 5 },
			{ kind = "Emblem", id = "Anchor", weight = 10 },
			{ kind = "Emblem", id = "Star", weight = 6 },
			{ kind = "Emblem", id = "Skull", weight = 4 },
		},
	},
	{
		-- operator gear sets (Config/Gear source "crate")
		id = "Gear",
		name = "Gear Crate",
		duplicateCredits = 750,
		pool = {
			{ kind = "Gear", id = "Jungle", weight = 35 },
			{ kind = "Gear", id = "Arctic", weight = 30 },
			{ kind = "Gear", id = "Highlander", weight = 20 },
			{ kind = "Gear", id = "NightOps", weight = 15 },
		},
	},
}

local premium: { PremiumBundle } = {
	{
		id = "FounderPack",
		name = "Founder Pack",
		description = "Founder camo for every weapon, the Founder title and the Founder emblem.",
		productId = 3720442629,
		robux = 199,
		grants = {
			{ kind = "Camo", id = "Founder" },
			{ kind = "Title", id = "Founder" },
			{ kind = "Emblem", id = "Founder" },
		},
	},
}

local Store = {
	shop = shop,
	crates = crates,
	premium = premium,
	shopById = {} :: { [string]: ShopItem },
	crateById = {} :: { [string]: CrateDef },
	premiumById = {} :: { [string]: PremiumBundle },
	premiumByProduct = {} :: { [number]: PremiumBundle },

	-- Credits earned by play
	Credits = {
		MatchComplete = 100,
		MatchWin = 50,
		DailyChallenge = 150,
	},
	-- Crates earned by play
	CratePerLevelUp = 1, -- per account level gained (and per prestige)
	CrateForAllDailies = 1, -- once per day, when all daily challenges are done
	GearCrateEveryLevels = 5, -- one Gear Crate each time the account reaches a multiple of this level
	MaxCredits = 1000000,
	MaxCrates = 99,
	ReceiptRetentionDays = 120, -- processed purchase ids kept this long (Roblox retries for 3 days)
}
for _, s in shop do
	Store.shopById[s.id] = s
end
for _, c in crates do
	Store.crateById[c.id] = c
end
for _, b in premium do
	Store.premiumById[b.id] = b
	if b.productId ~= 0 then
		Store.premiumByProduct[b.productId] = b
	end
end

return Store
