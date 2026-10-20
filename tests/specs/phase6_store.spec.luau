local Loader = require("../lib/Loader")
local T = require("../lib/T")
local Store = Loader.load("src/shared/Config/Store.luau")
local Cosmetics = Loader.load("src/shared/Config/Cosmetics.luau")
local StoreRules = Loader.load("src/shared/Pure/StoreRules.luau")
local CosmeticRules = Loader.load("src/shared/Pure/CosmeticRules.luau")
local ProfileSchema = Loader.load("src/shared/Pure/ProfileSchema.luau")
local describe, it, expect = T.describe, T.it, T.expect

local function profile()
	return ProfileSchema.default(1000, 5)
end

local function def(kind: string, id: string): any
	if kind == "Camo" then
		return Cosmetics.camoById[id]
	elseif kind == "Title" then
		return Cosmetics.titleById[id]
	end
	return Cosmetics.emblemById[id]
end

describe("Store policy", function()
	it("every shop, crate and premium grant is a cosmetic with a matching store source", function()
		for _, item in Store.shop do
			local d = def(item.grant.kind, item.grant.id)
			expect(d ~= nil).toBe(true)
			expect(d.source).toBe("shop")
			expect(item.price).toBeGreaterThan(0)
		end
		for _, crate in Store.crates do
			for _, e in crate.pool do
				local d = def(e.kind, e.id)
				expect(d ~= nil).toBe(true)
				expect(d.source).toBe("crate")
				expect(e.weight).toBeGreaterThan(0)
			end
		end
		for _, b in Store.premium do
			for _, g in b.grants do
				local d = def(g.kind, g.id)
				expect(d ~= nil).toBe(true)
				expect(d.source).toBe("premium")
			end
		end
	end)
	it("nothing random is sold for Robux: premium bundles are fixed grant lists, never crates or credits", function()
		for _, b in Store.premium do
			expect(#b.grants).toBeGreaterThan(0)
			for _, g in b.grants do
				expect(g.kind == "Camo" or g.kind == "Title" or g.kind == "Emblem").toBe(true)
			end
		end
		for _, crate in Store.crates do
			expect((crate :: any).productId).toBe(nil)
			expect((crate :: any).price).toBe(nil)
		end
	end)
	it("unconfigured products (id 0) cannot be bought", function()
		for _, b in Store.premium do
			if b.productId == 0 then
				expect(Store.premiumByProduct[0]).toBe(nil)
			end
		end
		local p = profile()
		expect(StoreRules.processReceipt(p, "abc", 0, 1)).toBe("unknown")
		expect(p.processedReceipts.abc).toBe(nil)
	end)
	it("store cosmetics are never owned through play progress", function()
		local p = profile()
		p.stats.kills = 100000
		p.account.prestige = 10
		p.weapons.VK7 = { level = 30, xp = 0, kills = 100000, headshots = 100000 }
		expect(CosmeticRules.ownsCamo(p, "VK7", "Obsidian")).toBe(false)
		expect(CosmeticRules.ownsTitle(p, "Quartermaster")).toBe(false)
		expect(CosmeticRules.ownsEmblem(p, "Wolf")).toBe(false)
		expect(CosmeticRules.ownsEmblem(p, "Prestige10")).toBe(true)
		p.inventory["Camo:Obsidian"] = 1
		expect(CosmeticRules.ownsCamo(p, "VK7", "Obsidian")).toBe(true)
		expect(CosmeticRules.ownsCamo(p, "P12", "Obsidian")).toBe(true)
	end)
end)

describe("StoreRules.buy", function()
	it("buys with earned credits once, refuses unknown items, owned items and short funds", function()
		local p = profile()
		expect(select(2, StoreRules.buy(p, "CamoObsidian"))).toBe("funds")
		StoreRules.addCredits(p, 3000)
		expect((StoreRules.buy(p, "CamoObsidian"))).toBe(true)
		expect(p.wallet.credits).toBe(500)
		expect(CosmeticRules.canEquip(p, "Camo", "Obsidian", "VK7")).toBe(true)
		StoreRules.addCredits(p, 5000)
		expect(select(2, StoreRules.buy(p, "CamoObsidian"))).toBe("owned")
		expect(p.wallet.credits).toBe(5500)
		expect(select(2, StoreRules.buy(p, "Nope"))).toBe("unknown")
		expect(select(2, StoreRules.buy(p, 5))).toBe("unknown")
	end)
	it("credits and crates are clamped", function()
		local p = profile()
		StoreRules.addCredits(p, 1e9)
		expect(p.wallet.credits).toBe(Store.MaxCredits)
		StoreRules.addCredits(p, -1e9)
		expect(p.wallet.credits).toBe(0)
		expect(StoreRules.addCrates(p, "Supply", 500)).toBe(Store.MaxCrates)
		StoreRules.addCrates(p, "Supply", -500)
		expect(StoreRules.crates(p, "Supply")).toBe(0)
		expect(p.inventory["Crate:Supply"]).toBe(nil)
	end)
end)

describe("Supply crates", function()
	it("odds add up to 100 percent", function()
		for _, crate in Store.crates do
			local sum = 0
			for _, o in StoreRules.odds(crate) do
				sum += o.percent
			end
			expect(sum).toBeNear(100, 0.5)
		end
	end)
	it("needs a crate, uses one, and never repeats an item", function()
		local p = profile()
		expect(select(2, StoreRules.open(p, "Supply", 0.5))).toBe("none")
		local crate = Store.crateById.Supply
		StoreRules.addCrates(p, "Supply", #crate.pool + 2)
		local seen = {}
		for i = 1, #crate.pool do
			local result = StoreRules.open(p, "Supply", (i * 0.37) % 1)
			expect(result.kind ~= nil).toBe(true)
			local key = result.kind .. ":" .. result.id
			expect(seen[key]).toBe(nil)
			seen[key] = true
			expect(p.inventory[key]).toBe(1)
		end
		-- everything owned: crates turn into credits
		local result = StoreRules.open(p, "Supply", 0.1)
		expect(result.kind).toBe(nil)
		expect(result.credits).toBe(crate.duplicateCredits)
		expect(p.wallet.credits).toBe(crate.duplicateCredits)
		expect(p.stats.cratesOpened).toBe(#crate.pool + 1)
		expect(StoreRules.crates(p, "Supply")).toBe(1)
	end)
	it("rolls follow the weights at the edges of [0, 1)", function()
		local p = profile()
		local crate = Store.crateById.Supply
		expect(StoreRules.roll(p, crate, 0).id).toBe(crate.pool[1].id)
		expect(StoreRules.roll(p, crate, 0.9999999).id).toBe(crate.pool[#crate.pool].id)
		expect(StoreRules.open(p, "Bogus", 0.5)).toBe(nil)
	end)
end)

describe("Robux receipts", function()
	it("grants a bundle once per PurchaseId and acknowledges repeats", function()
		local p = profile()
		local bundle = Store.premium[1]
		-- simulate a configured product
		Store.premiumByProduct[777] = bundle
		expect(StoreRules.processReceipt(p, "P1", 777, 5000)).toBe("granted")
		expect(StoreRules.ownsBundle(p, bundle)).toBe(true)
		local before = 0
		for _ in p.inventory do
			before += 1
		end
		expect(StoreRules.processReceipt(p, "P1", 777, 5001)).toBe("duplicate")
		local after = 0
		for _ in p.inventory do
			after += 1
		end
		expect(after).toBe(before)
		expect(p.processedReceipts.P1).toBe(5000)
		Store.premiumByProduct[777] = nil
	end)
	it("prunes receipts past the retention window only", function()
		local p = profile()
		local now = 1000 * 86400
		p.processedReceipts.old = now - (Store.ReceiptRetentionDays + 1) * 86400
		p.processedReceipts.recent = now - 3 * 86400
		StoreRules.pruneReceipts(p, now)
		expect(p.processedReceipts.old).toBe(nil)
		expect(p.processedReceipts.recent ~= nil).toBe(true)
	end)
end)

describe("Profile v5", function()
	it("migrates v4 to v5 with an empty wallet and keeps inventory and receipts", function()
		local v4 = ProfileSchema.default(10, 5) :: any
		v4.version = 4
		v4.wallet = nil
		v4.dailyCrateDay = nil
		v4.stats.cratesOpened = nil
		v4.inventory = { ["Camo:Obsidian"] = 1, ["Crate:Supply"] = 3, bad = "x", [5] = 1 }
		v4.processedReceipts = { R1 = 50 }
		local p, changed = ProfileSchema.migrate(v4, 100, 5, { VK7 = "Primary", P12 = "Secondary" })
		expect(changed).toBe(true)
		expect(p.version).toBe(5)
		expect(p.wallet.credits).toBe(0)
		expect(p.stats.cratesOpened).toBe(0)
		expect(p.inventory["Camo:Obsidian"]).toBe(1)
		expect(p.inventory["Crate:Supply"]).toBe(3)
		expect(p.inventory.bad).toBe(nil)
		expect(p.processedReceipts.R1).toBe(50)
	end)
	it("clamps a junk wallet", function()
		local d = ProfileSchema.default(10, 5) :: any
		d.wallet = { credits = -50 }
		expect(ProfileSchema.migrate(d, 10, 5, {}).wallet.credits).toBe(0)
		d.wallet = { credits = 0 / 0 }
		expect(ProfileSchema.migrate(d, 10, 5, {}).wallet.credits).toBe(0)
	end)
end)

local StoreRulesUI = Loader.load("src/client/UI/StoreRulesUI.luau")

describe("Store screen rules", function()
	it("shop buttons: owned, short funds, buyable", function()
		expect(StoreRulesUI.shopButton(2500, 9000, true).text).toBe("OWNED")
		local short = StoreRulesUI.shopButton(2500, 1000, false)
		expect(short.enabled).toBe(false)
		expect(short.text).toBe("NEED 1,500 CR")
		local ok = StoreRulesUI.shopButton(2500, 2500, false)
		expect(ok.enabled).toBe(true)
		expect(ok.text).toBe("BUY  2,500 CR")
	end)
	it("premium buttons: unconfigured products cannot be bought", function()
		expect(StoreRulesUI.premiumButton(0, 199, false).text).toBe("COMING SOON")
		expect(StoreRulesUI.premiumButton(0, 199, false).enabled).toBe(false)
		expect(StoreRulesUI.premiumButton(123, 199, false).text).toBe("R$ 199")
		expect(StoreRulesUI.premiumButton(123, 199, true).enabled).toBe(false)
	end)
	it("formats credits and reads ownership from the cosmetics view", function()
		expect(StoreRulesUI.credits(0)).toBe("0 CR")
		expect(StoreRulesUI.credits(1000000)).toBe("1,000,000 CR")
		local view = { owned = { titles = { "Scrapper" }, emblems = {}, camos = { VK7 = { "Factory", "Obsidian" } } } }
		expect(StoreRulesUI.owns(view, "Camo", "Obsidian")).toBe(true)
		expect(StoreRulesUI.owns(view, "Title", "Scrapper")).toBe(true)
		expect(StoreRulesUI.owns(view, "Emblem", "Wolf")).toBe(false)
		expect(StoreRulesUI.owns(nil, "Camo", "Obsidian")).toBe(false)
		expect(StoreRulesUI.resultText({ credits = 500 }, function() return "" end)).toBe("ALL ITEMS OWNED  +500 CR")
		expect(StoreRulesUI.resultText({ kind = "Camo", id = "Tidewater", credits = 0 }, function() return "Tidewater" end)).toBe("CAMO  TIDEWATER")
	end)
end)
