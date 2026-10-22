local Loader = require("../lib/Loader")
local T = require("../lib/T")
local Gear = Loader.load("src/shared/Config/Gear.luau")
local Store = Loader.load("src/shared/Config/Store.luau")
local Assets = Loader.load("src/shared/Config/Assets.luau")
local CosmeticRules = Loader.load("src/shared/Pure/CosmeticRules.luau")
local StoreRules = Loader.load("src/shared/Pure/StoreRules.luau")
local ProfileSchema = Loader.load("src/shared/Pure/ProfileSchema.luau")
local StoreRulesUI = Loader.load("src/client/UI/StoreRulesUI.luau")
local describe, it, expect = T.describe, T.it, T.expect

local function profile(level: number?): any
	local p = ProfileSchema.default(1000, 5) :: any
	p.account.level = level or 1
	return p
end

describe("Gear config", function()
	it("has a level-1 default set and unique ids with known sources", function()
		local default = Gear.byId[Gear.Default]
		expect(default ~= nil).toBe(true)
		expect(default.source).toBe(nil)
		expect(default.level).toBe(1)
		local seen = {}
		for _, g in Gear.sets do
			expect(seen[g.id]).toBe(nil)
			seen[g.id] = true
			expect(g.source == nil or g.source == "shop" or g.source == "crate").toBe(true)
			expect(#g.id <= 32).toBe(true)
		end
	end)

	it("puts every crate set in a crate and every shop set in the shop", function()
		local inCrate, inShop = {}, {}
		for _, crate in Store.crates do
			for _, e in crate.pool do
				if e.kind == "Gear" then
					inCrate[e.id] = true
				end
			end
		end
		for _, item in Store.shop do
			if item.grant.kind == "Gear" then
				inShop[item.grant.id] = true
			end
		end
		for _, g in Gear.sets do
			if g.source == "crate" then
				expect(inCrate[g.id]).toBe(true)
			elseif g.source == "shop" then
				expect(inShop[g.id]).toBe(true)
			end
		end
	end)
end)

describe("Gear ownership", function()
	it("unlocks level sets by account level and keeps them after a prestige", function()
		local p = profile(9)
		expect(CosmeticRules.ownsGear(p, "Ranger")).toBe(true)
		expect(CosmeticRules.ownsGear(p, "Woodland")).toBe(false)
		p.account.level = 10
		expect(CosmeticRules.ownsGear(p, "Woodland")).toBe(true)
		CosmeticRules.applyPrestige(p)
		expect(p.account.level).toBe(1)
		expect(CosmeticRules.ownsGear(p, "Urban")).toBe(true)
	end)

	it("owns store and crate sets only through the inventory", function()
		local p = profile(55)
		expect(CosmeticRules.ownsGear(p, "Arctic")).toBe(false)
		expect(CosmeticRules.ownsGear(p, "DesertRecon")).toBe(false)
		p.inventory["Gear:Arctic"] = 1
		expect(CosmeticRules.ownsGear(p, "Arctic")).toBe(true)
		expect(CosmeticRules.ownsGear(p, "Nope")).toBe(false)
	end)

	it("validates equips and falls back to the default set", function()
		local p = profile(1)
		expect((CosmeticRules.canEquip(p, "Gear", "Ranger"))).toBe(true)
		local ok, why = CosmeticRules.canEquip(p, "Gear", "Urban")
		expect(ok).toBe(false)
		expect(why).toBe("locked")
		p.equipped.gear = "Urban"
		expect(CosmeticRules.gearOf(p)).toBe("Ranger")
		expect(CosmeticRules.sanitizeEquipped(p, p.equipped).gear).toBe(nil)
		p.account.level = 25
		expect(CosmeticRules.gearOf(p)).toBe("Urban")
		expect(CosmeticRules.sanitizeEquipped(p, p.equipped).gear).toBe("Urban")
		expect(table.find(CosmeticRules.owned(p, {}).gears, "Urban") ~= nil).toBe(true)
	end)

	it("keeps the equipped gear id through a profile migration", function()
		local p = profile(1)
		p.equipped.gear = "Woodland"
		local migrated = ProfileSchema.migrate(p, 2000, 5, { VK7 = "Primary", P12 = "Secondary" })
		expect(migrated.equipped.gear).toBe("Woodland")
		p.equipped.gear = 5
		expect(ProfileSchema.migrate(p, 2000, 5, { VK7 = "Primary", P12 = "Secondary" }).equipped.gear).toBe(nil)
	end)
end)

describe("Gear crates and shop", function()
	it("earns a Gear Crate each time a multiple of the level step is crossed", function()
		local every = Store.GearCrateEveryLevels
		expect(StoreRules.gearCratesForLevels(every - 1, every)).toBe(1)
		expect(StoreRules.gearCratesForLevels(every, every * 2 - 1)).toBe(0)
		expect(StoreRules.gearCratesForLevels(every - 2, every * 2 + 1)).toBe(2)
		expect(StoreRules.gearCratesForLevels(5, 5)).toBe(0)
	end)

	it("opens a Gear Crate into a gear set and never repeats one", function()
		local p = profile(1)
		local crate = Store.crateById.Gear
		StoreRules.addCrates(p, "Gear", #crate.pool + 1)
		local got = {}
		for i = 1, #crate.pool do
			local result = StoreRules.open(p, "Gear", (i * 0.29) % 1)
			expect(result.kind).toBe("Gear")
			expect(got[result.id]).toBe(nil)
			got[result.id] = true
			expect(CosmeticRules.ownsGear(p, result.id)).toBe(true)
		end
		local last = StoreRules.open(p, "Gear", 0.5)
		expect(last.kind).toBe(nil)
		expect(last.credits).toBe(crate.duplicateCredits)
	end)

	it("sells the shop gear set once", function()
		local p = profile(1)
		p.wallet.credits = 10000
		expect((StoreRules.buy(p, "GearDesertRecon"))).toBe(true)
		expect(CosmeticRules.ownsGear(p, "DesertRecon")).toBe(true)
		expect(select(2, StoreRules.buy(p, "GearDesertRecon"))).toBe("owned")
	end)

	it("shows gear ownership in the store view", function()
		local view = { owned = { titles = {}, emblems = {}, gears = { "Arctic" }, camos = {} } }
		expect(StoreRulesUI.owns(view, "Gear", "Arctic")).toBe(true)
		expect(StoreRulesUI.owns(view, "Gear", "NightOps")).toBe(false)
	end)
end)

describe("Asset slots", function()
	it("returns content ids only for published assets", function()
		expect(Assets.image("Emblem")).toBe("rbxassetid://" .. tostring(Assets.Images.Emblem))
		expect(Assets.image("NoSuchKey")).toBe(nil)
		for key, id in Assets.Images do
			expect(type(key)).toBe("string")
			expect(id >= 0 and id == math.floor(id)).toBe(true)
		end
		for _, id in Assets.Clothing do
			expect(id >= 0).toBe(true)
		end
	end)
end)
