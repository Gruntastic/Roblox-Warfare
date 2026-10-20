local Loader = require("../lib/Loader")
local T = require("../lib/T")
local Perks = Loader.load("src/shared/Config/Perks.luau")
local Killstreaks = Loader.load("src/shared/Config/Killstreaks.luau")
local Challenges = Loader.load("src/shared/Config/Challenges.luau")
local Cosmetics = Loader.load("src/shared/Config/Cosmetics.luau")
local Weapons = Loader.load("src/shared/Config/Weapons.luau")
local Attachments = Loader.load("src/shared/Config/Attachments.luau")
local PerkRules = Loader.load("src/shared/Pure/PerkRules.luau")
local StreakRules = Loader.load("src/shared/Pure/StreakRules.luau")
local ChallengeRules = Loader.load("src/shared/Pure/ChallengeRules.luau")
local CosmeticRules = Loader.load("src/shared/Pure/CosmeticRules.luau")
local WeaponStats = Loader.load("src/shared/Pure/WeaponStats.luau")
local describe, it, expect = T.describe, T.it, T.expect

describe("Perk catalogue", function()
	it("four perks per tier, unique ids, a level-1 perk in every tier matching the defaults", function()
		local perTier = { 0, 0, 0 }
		for _, def in Perks.list do
			perTier[def.tier] += 1
		end
		expect(perTier[1]).toBe(4)
		expect(perTier[2]).toBe(4)
		expect(perTier[3]).toBe(4)
		for tier, id in Perks.Defaults do
			expect(Perks.byId[id].tier).toBe(tier)
			expect(Perks.byId[id].unlockLevel).toBe(1)
		end
	end)
end)

describe("PerkRules", function()
	it("validates one unlocked perk per tier, in tier order", function()
		expect((PerkRules.validate({ "Fleetfoot", "Quickhands", "SecondWind" }, 1, 0))).toBe(true)
		expect(select(2, PerkRules.validate({ "Quickhands", "Fleetfoot", "SecondWind" }, 70, 0))).toBe("tier")
		expect(select(2, PerkRules.validate({ "Hardline", "Quickhands", "SecondWind" }, 10, 0))).toBe("locked")
		expect((PerkRules.validate({ "Hardline", "Quickhands", "SecondWind" }, 10, 1))).toBe(true) -- prestige keeps unlocks
		expect(select(2, PerkRules.validate({ "Fleetfoot", "Quickhands" }, 70, 0))).toBe("unknown")
		expect(select(2, PerkRules.validate({ "Fleetfoot", "Quickhands", "SecondWind", "Tracker" }, 70, 0))).toBe("shape")
		expect(select(2, PerkRules.validate("x", 70, 0))).toBe("shape")
	end)
	it("sanitize keeps valid picks and falls back per tier", function()
		local out = PerkRules.sanitize({ "Hardline", "DeepPockets", "Nope" }, 10, 0)
		expect(table.concat(out, ",")).toBe("Fleetfoot,DeepPockets,SecondWind")
	end)
	it("combines effects and applies them to a weapon without mutating it", function()
		local c = PerkRules.combine({ "Fleetfoot", "Quickhands", "SecondWind" })
		expect(c.moveSpeed).toBeNear(1.08)
		expect(c.reloadTime).toBeNear(0.75)
		expect(c.regenDelay).toBeNear(0.6)
		local base = WeaponStats.resolve(Weapons.VK7, {}, Attachments)
		local reload = base.reloadTime
		local out = PerkRules.applyToWeapon(base, PerkRules.combine({ "Fleetfoot", "Quickhands", "SecondWind" }))
		expect(out.reloadTime).toBeNear(reload * 0.75)
		expect(base.reloadTime).toBe(reload)
		local pockets = PerkRules.applyToWeapon(base, PerkRules.combine({ "Fleetfoot", "DeepPockets", "SecondWind" }))
		expect(pockets.reserveAmmo).toBe(math.floor(base.reserveAmmo * 1.5 + 0.5))
		local steady = PerkRules.applyToWeapon(base, PerkRules.combine({ "Fleetfoot", "SteadyHand", "SecondWind" }))
		expect(steady.spread.hip).toBeNear(base.spread.hip * 0.65)
		expect(base.spread.hip).toBe(WeaponStats.resolve(Weapons.VK7, {}, Attachments).spread.hip)
		expect(PerkRules.combine({ "Hardline", "Quickhands", "GhostSignal" }).ghost).toBe(true)
		expect(PerkRules.combine({ "Hardline", "Quickhands", "GhostSignal" }).streakDiscount).toBe(1)
	end)
end)

describe("StreakRules", function()
	it("validates up to three distinct unlocked streaks", function()
		expect((StreakRules.validate({}, 1, 0))).toBe(true)
		expect((StreakRules.validate({ "ReconDrone", "MortarBarrage" }, 1, 0))).toBe(true)
		expect(select(2, StreakRules.validate({ "ReconDrone", "ReconDrone" }, 70, 0))).toBe("duplicate")
		expect(select(2, StreakRules.validate({ "Blackout" }, 20, 0))).toBe("locked")
		expect(select(2, StreakRules.validate({ "ReconDrone", "CounterRecon", "MortarBarrage", "SentryGun" }, 70, 0))).toBe("shape")
		expect(select(2, StreakRules.validate({ [2] = "ReconDrone" }, 70, 0))).toBe("shape")
		expect(select(2, StreakRules.validate({ "Gunship" }, 70, 0))).toBe("unknown")
	end)
	it("earns each streak once per life at its cost; streak kills do not count", function()
		local s = StreakRules.newState()
		local eq = { "ReconDrone", "MortarBarrage", "SentryGun" }
		expect(#StreakRules.onKill(s, eq, 0, false)).toBe(0)
		expect(#StreakRules.onKill(s, eq, 0, false)).toBe(0)
		expect(StreakRules.onKill(s, eq, 0, false)[1]).toBe("ReconDrone")
		expect(#StreakRules.onKill(s, eq, 0, true)).toBe(0) -- a streak kill
		expect(s.count).toBe(3)
		StreakRules.onKill(s, eq, 0, false)
		expect(StreakRules.onKill(s, eq, 0, false)[1]).toBe("MortarBarrage")
		local nextId, need = StreakRules.nextUp(s, eq, 0)
		expect(nextId).toBe("SentryGun")
		expect(need).toBe(6)
		StreakRules.onDeath(s)
		expect(s.count).toBe(0)
		expect(#s.ready).toBe(2) -- earned rewards survive death
		expect(StreakRules.take(s, "MortarBarrage")).toBe(true)
		expect(StreakRules.take(s, "MortarBarrage")).toBe(false)
		expect(#s.ready).toBe(1)
	end)
	it("Hardline discounts every streak but never below the minimum", function()
		expect(StreakRules.cost("ReconDrone", 1)).toBe(2)
		expect(StreakRules.cost("ReconDrone", 5)).toBe(Killstreaks.MinKills)
		local s = StreakRules.newState()
		StreakRules.onKill(s, { "ReconDrone" }, 1, false)
		expect(StreakRules.onKill(s, { "ReconDrone" }, 1, false)[1]).toBe("ReconDrone")
	end)
	it("sanitize drops locked, unknown and duplicate entries", function()
		expect(table.concat(StreakRules.sanitize({ "Blackout", "ReconDrone", "ReconDrone", "X" }, 5, 0), ",")).toBe("ReconDrone")
		expect(table.concat(StreakRules.sanitize(nil, 1, 0), ",")).toBe("ReconDrone,MortarBarrage")
	end)
end)

describe("ChallengeRules", function()
	it("gives three distinct known challenges, stable for a player and day", function()
		local a = ChallengeRules.dailyFor(12345, 20000)
		local b = ChallengeRules.dailyFor(12345, 20000)
		expect(#a).toBe(Challenges.DailyCount)
		expect(table.concat(a, ",")).toBe(table.concat(b, ","))
		local seen = {}
		for _, id in a do
			expect(Challenges.byId[id] ~= nil).toBeTruthy()
			expect(seen[id]).toBe(nil)
			seen[id] = true
		end
	end)
	it("varies across days and players", function()
		local distinct = {}
		for day = 20000, 20030 do
			distinct[table.concat(ChallengeRules.dailyFor(777, day), ",")] = true
		end
		local n = 0
		for _ in distinct do
			n += 1
		end
		expect(n).toBeAtLeast(20)
		local differs = 0
		for user = 1, 30 do
			if table.concat(ChallengeRules.dailyFor(user, 20000), ",") ~= table.concat(ChallengeRules.dailyFor(user + 1, 20000), ",") then
				differs += 1
			end
		end
		expect(differs).toBeAtLeast(25)
	end)
	it("refresh rolls the set on a new UTC day and keeps it within the day", function()
		local s = { day = 0, daily = {} }
		local t = 20000 * 86400 + 5
		expect(ChallengeRules.refresh(s, 42, t)).toBe(true)
		s.daily[1].progress = 3
		expect(ChallengeRules.refresh(s, 42, t + 80000)).toBe(false)
		expect(s.daily[1].progress).toBe(3)
		expect(ChallengeRules.refresh(s, 42, t + 86400)).toBe(true)
		expect(s.daily[1].progress).toBe(0)
		expect(ChallengeRules.secondsLeft(20000 * 86400 + 86000)).toBe(400)
	end)
	it("counts matching events, caps at the target and completes once", function()
		local s = { day = 1, daily = { { id = "SniperKills", progress = 0, done = false }, { id = "Headshots", progress = 0, done = false }, { id = "Hardpoint", progress = 0, done = false } } }
		expect(#ChallengeRules.record(s, { kind = "kill", class = "Sniper", headshot = true })).toBe(0)
		expect(s.daily[1].progress).toBe(1)
		expect(s.daily[2].progress).toBe(1)
		ChallengeRules.record(s, { kind = "kill", class = "AssaultRifle" })
		expect(s.daily[1].progress).toBe(1)
		ChallengeRules.record(s, { kind = "kill", class = "Streak", headshot = true })
		expect(s.daily[2].progress).toBe(1) -- streak kills never count
		local done = ChallengeRules.record(s, { kind = "hardpointSecond", amount = 75 })
		expect(#done).toBe(1)
		expect(done[1].id).toBe("Hardpoint")
		expect(s.daily[3].progress).toBe(60)
		expect(#ChallengeRules.record(s, { kind = "hardpointSecond" })).toBe(0)
		expect(ChallengeRules.text(Challenges.byId.Kills)).toBe("Get 15 kills")
	end)
	it("machine pistols count as pistols", function()
		local s = { day = 1, daily = { { id = "PistolKills", progress = 0, done = false } } }
		ChallengeRules.record(s, { kind = "kill", class = "MachinePistol" })
		expect(s.daily[1].progress).toBe(1)
	end)
end)

describe("CosmeticRules", function()
	local function profile()
		return {
			account = { level = 70, xp = 0, prestige = 0 },
			weapons = { VK7 = { level = 30, xp = 0, kills = 310, headshots = 40 } },
			stats = { kills = 150, headshots = 12, wins = 3, captures = 0, plants = 0, defuses = 0, tags = 0, dailies = 0 },
			inventory = {},
		}
	end
	it("camos unlock per weapon by kills, the mastery camo also needs headshots", function()
		local p = profile()
		expect(CosmeticRules.ownsCamo(p, "VK7", "ArcticTiger")).toBe(true)
		expect(CosmeticRules.ownsCamo(p, "VK7", "Gilded")).toBe(false)
		expect(CosmeticRules.ownsCamo(p, "KT9", "DesertStipple")).toBe(false)
		expect(CosmeticRules.ownsCamo(p, "KT9", "Factory")).toBe(true)
		p.weapons.VK7.headshots = 100
		expect(CosmeticRules.ownsCamo(p, "VK7", "Gilded")).toBe(true)
		p.inventory["Camo:Gilded"] = 1
		expect(CosmeticRules.ownsCamo(p, "KT9", "Gilded")).toBe(true)
	end)
	it("titles follow lifetime stats; emblems follow prestige", function()
		local p = profile()
		expect(CosmeticRules.ownsTitle(p, "Recruit")).toBe(true)
		expect(CosmeticRules.ownsTitle(p, "Centurion")).toBe(true)
		expect(CosmeticRules.ownsTitle(p, "Veteran")).toBe(false)
		expect(CosmeticRules.ownsEmblem(p, "Prestige1")).toBe(false)
		p.account.prestige = 2
		expect(CosmeticRules.ownsEmblem(p, "Prestige2")).toBe(true)
		expect(CosmeticRules.ownsEmblem(p, "Prestige3")).toBe(false)
		local owned = CosmeticRules.owned(p, { "VK7", "P12" })
		expect(#owned.emblems).toBe(2)
		expect(#owned.camos.VK7).toBe(5)
		expect(#owned.camos.P12).toBe(1)
	end)
	it("sanitizeEquipped drops anything not owned", function()
		local p = profile()
		local eq = CosmeticRules.sanitizeEquipped(p, { title = "Veteran", emblem = "Prestige1", camos = { VK7 = "UrbanHex", KT9 = "UrbanHex", P12 = "Factory" } })
		expect(eq.title).toBe("Recruit")
		expect(eq.emblem).toBe(nil)
		expect(eq.camos.VK7).toBe("UrbanHex")
		expect(eq.camos.KT9).toBe(nil)
		expect(eq.camos.P12).toBe(nil) -- the default camo is implied
	end)
	it("canEquip checks kind, shape and ownership", function()
		local p = profile()
		expect((CosmeticRules.canEquip(p, "Camo", "UrbanHex", "VK7"))).toBe(true)
		expect(select(2, CosmeticRules.canEquip(p, "Camo", "Gilded", "VK7"))).toBe("locked")
		expect((CosmeticRules.canEquip(p, "Camo", "Factory", "KT9"))).toBe(true)
		expect(select(2, CosmeticRules.canEquip(p, "Camo", "UrbanHex", nil))).toBe("shape")
		expect((CosmeticRules.canEquip(p, "Title", "Centurion"))).toBe(true)
		expect((CosmeticRules.canEquip(p, "Emblem", ""))).toBe(true)
		expect(select(2, CosmeticRules.canEquip(p, "Hat", "x"))).toBe("kind")
		expect(select(2, CosmeticRules.canEquip(p, "Title", string.rep("a", 40)))).toBe("shape")
	end)
	it("prestige needs max level, stops at the cap and keeps progress", function()
		local p = profile()
		expect(CosmeticRules.canPrestige(p, 70, 10)).toBe(true)
		CosmeticRules.applyPrestige(p)
		expect(p.account.prestige).toBe(1)
		expect(p.account.level).toBe(1)
		expect(p.weapons.VK7.kills).toBe(310)
		expect(CosmeticRules.canPrestige(p, 70, 10)).toBe(false)
		p.account.level, p.account.prestige = 70, 10
		expect(CosmeticRules.canPrestige(p, 70, 10)).toBe(false)
	end)
	it("camos repaint weapon body parts only", function()
		local WeaponModel = Loader.load("src/shared/WeaponModel.luau")
		local plain = WeaponModel.build(Weapons.VK7, { attachments = { Optic = "RedDot" } })
		local camo = WeaponModel.build(Weapons.VK7, { attachments = { Optic = "RedDot" }, camo = "ArcticTiger" })
		local tiger = Cosmetics.camoById.ArcticTiger
		local changed, kept = 0, 0
		for _, part in camo:GetChildren() do
			if part:IsA("BasePart") and part.Name ~= "GripOrigin" then
				local before = plain:FindFirstChild(part.Name)
				if Cosmetics.CamoParts[part.Name] and part:GetAttribute("WeaponBody") then
					changed += 1
					expect(part.Material).toBe(tiger.material)
				elseif before then
					kept += 1
					expect(part.Material).toBe(before.Material)
				end
			end
		end
		expect(changed).toBeAtLeast(3)
		expect(kept).toBeAtLeast(3)
		expect(camo:FindFirstChild("Receiver").Color).toBe(tiger.color)
		local factory = WeaponModel.build(Weapons.VK7, { camo = "Factory" })
		expect(factory:FindFirstChild("Receiver").Color).toBe(plain:FindFirstChild("Receiver").Color)
	end)
	it("catalogue ids are unique and there are ten prestige emblems", function()
		expect(#Cosmetics.emblems).toBe(10)
		local seen = {}
		for _, list in { Cosmetics.camos, Cosmetics.titles, Cosmetics.emblems } do
			for _, item in list do
				expect(seen[item.id]).toBe(nil)
				seen[item.id] = true
			end
		end
	end)
end)

return nil
