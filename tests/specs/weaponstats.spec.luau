local Loader = require("../lib/Loader")
local T = require("../lib/T")
local WeaponStats = Loader.load("src/shared/Pure/WeaponStats.luau")
local Pellets = Loader.load("src/shared/Pure/Pellets.luau")
local Weapons = Loader.load("src/shared/Config/Weapons.luau")
local Attachments = Loader.load("src/shared/Config/Attachments.luau")
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
local describe, it, expect = T.describe, T.it, T.expect

-- Synthetic fixtures so these tests don't depend on roster balance numbers.
local function fixtureDef()
	return {
		id = "TEST",
		class = "AssaultRifle",
		fireMode = "Auto",
		rpm = 600,
		damage = { close = 30, far = 20, closeRange = 50, farRange = 150, maxRange = 800 },
		headMultiplier = 1.4,
		limbMultiplier = 0.9,
		magSize = 30,
		reserveAmmo = 120,
		reloadTime = 2,
		reloadEmptyTime = 2.5,
		equipTime = 0.5,
		adsTime = 0.25,
		moveSpeedMultiplier = 0.95,
		adsMoveSpeedMultiplier = 0.6,
		spread = { hip = 3, ads = 0.1, movingMultiplier = 1.5 },
		recoil = { vertical = 0.5, horizontal = 0.2, recovery = 9, adsMultiplier = 0.7 },
		adsFov = 55,
		muzzleOffset = CFrame.new(0, 0.1, -2),
		sightOffset = CFrame.new(0, 0.4, 0),
		anchors = { optic = CFrame.new(0, 0.3, -0.5), muzzle = CFrame.new(0, 0.1, -2), magazine = CFrame.new(0, -0.3, -0.7), leftHand = CFrame.new(0, -0.1, -1.2) },
		attachmentSlots = { "Optic", "Muzzle", "Magazine" },
		attachmentUnlocks = { Dot = 2, Can = 4, Mag = 6 },
	}
end
local catalog = {
	Dot = { id = "Dot", slot = "Optic", classes = { "AssaultRifle" }, modifiers = { adsTime = 1.1 }, optic = { fov = 50, sightHeight = 0.1, reticle = "Dot" } },
	Can = { id = "Can", slot = "Muzzle", classes = { "AssaultRifle" }, modifiers = { range = 0.8 }, suppressed = true, muzzleExtend = 0.5 },
	Mag = { id = "Mag", slot = "Magazine", classes = { "AssaultRifle" }, modifiers = { magSize = 1.5, reload = 1.2 } },
	Grip = { id = "Grip", slot = "Underbarrel", classes = { "AssaultRifle" }, modifiers = {} },
	SniperOnly = { id = "SniperOnly", slot = "Optic", classes = { "Sniper" }, modifiers = {} },
}

describe("WeaponStats.validate", function()
	local def = fixtureDef()
	it("accepts an empty selection and unlocked attachments", function()
		expect((WeaponStats.validate(def, {}, 1, catalog))).toBe(true)
		expect((WeaponStats.validate(def, { Optic = "Dot", Muzzle = "Can" }, 4, catalog))).toBe(true)
	end)
	it("rejects locked attachments", function()
		local ok, reason = WeaponStats.validate(def, { Muzzle = "Can" }, 3, catalog)
		expect(ok).toBe(false)
		expect(reason).toBe("locked")
	end)
	it("rejects wrong slot, unknown id, unsupported slot, wrong class, non-tables", function()
		expect(select(2, WeaponStats.validate(def, { Muzzle = "Dot" }, 30, catalog))).toBe("attachment")
		expect(select(2, WeaponStats.validate(def, { Optic = "Nope" }, 30, catalog))).toBe("attachment")
		expect(select(2, WeaponStats.validate(def, { Underbarrel = "Grip" }, 30, catalog))).toBe("slot")
		local def2 = fixtureDef()
		def2.attachmentUnlocks.SniperOnly = 1
		expect(select(2, WeaponStats.validate(def2, { Optic = "SniperOnly" }, 30, catalog))).toBe("class")
		expect(select(2, WeaponStats.validate(def, "x", 30, catalog))).toBe("selection")
		expect(select(2, WeaponStats.validate(def, { [1] = "Dot" }, 30, catalog))).toBe("types")
	end)
	it("rejects attachments the weapon does not offer", function()
		local def2 = fixtureDef()
		def2.attachmentUnlocks.Dot = nil
		expect(select(2, WeaponStats.validate(def2, { Optic = "Dot" }, 30, catalog))).toBe("notoffered")
	end)
	it("sanitize keeps valid entries and drops the rest", function()
		local clean = WeaponStats.sanitize(def, { Optic = "Dot", Muzzle = "Can", Magazine = "Bogus", Underbarrel = "Grip" }, 3, catalog)
		expect(clean.Optic).toBe("Dot")
		expect(clean.Muzzle).toBe(nil) -- locked at level 3
		expect(clean.Magazine).toBe(nil)
		expect(clean.Underbarrel).toBe(nil)
	end)
end)

describe("WeaponStats.resolve", function()
	local def = fixtureDef()
	it("no attachments leaves stats unchanged and does not alias the def", function()
		local e = WeaponStats.resolve(def, nil, catalog)
		expect(e.magSize).toBe(30)
		expect(e.adsFov).toBe(55)
		e.damage.close = 999
		expect(def.damage.close).toBe(30)
	end)
	it("applies multipliers, mag rounding, reserve scaling, suppression and muzzle extension", function()
		local e = WeaponStats.resolve(def, { Optic = "Dot", Muzzle = "Can", Magazine = "Mag" }, catalog)
		expect(e.adsTime).toBeNear(0.275, 1e-9)
		expect(e.damage.maxRange).toBeNear(640, 1e-9)
		expect(e.magSize).toBe(45)
		expect(e.reserveAmmo).toBe(180)
		expect(e.reloadTime).toBeNear(2.4, 1e-9)
		expect(e.suppressed).toBe(true)
		expect(e.muzzleOffset.Position.Z).toBeNear(-2.5, 1e-6)
		expect(e.adsFov).toBe(50)
		expect(e.sightOffset.Position.Y).toBeNear(0.4, 1e-6)
		expect(e.sightOffset.Position.Z).toBeNear(-0.5, 1e-6)
		expect(e.attachments.Magazine).toBe("Mag")
		expect(e.reticle).toBe("Dot")
		expect(WeaponStats.resolve(def, nil, catalog).reticle).toBe(nil)
	end)
	it("optics do not replace a built-in scope", function()
		local d = fixtureDef()
		d.scope = { fov = 20 }
		local e = WeaponStats.resolve(d, { Optic = "Dot" }, catalog)
		expect(e.adsFov).toBe(20)
		expect(e.scoped).toBe(true)
		expect(e.reticle).toBe(nil)
	end)
	it("ratings are within 0..100", function()
		local r = WeaponStats.ratings(WeaponStats.resolve(def, nil, catalog))
		for _, key in { "damage", "range", "fireRate", "accuracy", "mobility", "control" } do
			expect(r[key] >= 0 and r[key] <= 100).toBe(true)
		end
	end)
end)

describe("Roster attachment data", function()
	it("every offered attachment exists, fits a weapon slot and accepts the weapon class", function()
		for id, def in Weapons do
			for attId, level in def.attachmentUnlocks do
				local att = Attachments[attId]
				expect(att ~= nil).toBe(true)
				expect(table.find(def.attachmentSlots, att.slot) ~= nil).toBe(true)
				expect(table.find(att.classes, def.class) ~= nil).toBe(true)
				expect(level >= 1 and level <= 30).toBe(true)
			end
			-- full validation of everything at max level
			local all = {}
			for attId in def.attachmentUnlocks do
				all[Attachments[attId].slot] = attId
			end
			local ok, reason = WeaponStats.validate(def, all, 30, Attachments)
			if not ok then
				error(id .. ": " .. tostring(reason))
			end
		end
	end)
	it("every attachment id matches its key and has a model", function()
		for id, att in Attachments do
			expect(att.id).toBe(id)
			expect(#att.model > 0).toBe(true)
		end
	end)
end)

describe("Pellets", function()
	it("pellet 1 is the aim direction and every pellet stays inside the cone", function()
		local aim = CFrame.lookAt(Vector3.new(0, 0, 0), Vector3.new(1, 0.2, -3))
		local dirs = Pellets.directions(aim, 8, 6)
		expect(#dirs).toBe(8)
		expect((dirs[1] - aim.LookVector).Magnitude).toBeNear(0, 1e-6)
		for _, d in dirs do
			local angle = math.deg(math.acos(math.clamp(d:Dot(aim.LookVector), -1, 1)))
			expect(angle <= 6 * 1.42 + 1e-6).toBe(true) -- yaw and pitch each <= radius
		end
	end)
	it("pattern is deterministic and pellets are distinct", function()
		local aim = CFrame.new()
		local a, b = Pellets.directions(aim, 9, 5), Pellets.directions(aim, 9, 5)
		for i = 1, 9 do
			expect((a[i] - b[i]).Magnitude).toBe(0)
			for j = i + 1, 9 do
				expect((a[i] - a[j]).Magnitude > 1e-4).toBe(true)
			end
		end
	end)
end)
