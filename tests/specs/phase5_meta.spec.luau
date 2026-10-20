local Loader = require("../lib/Loader")
local T = require("../lib/T")
local Weapons = Loader.load("src/shared/Config/Weapons.luau")
local Attachments = Loader.load("src/shared/Config/Attachments.luau")
local Challenges = Loader.load("src/shared/Config/Challenges.luau")
local Progression = Loader.load("src/shared/Config/Progression.luau")
local ChallengeRules = Loader.load("src/shared/Pure/ChallengeRules.luau")
local CosmeticRules = Loader.load("src/shared/Pure/CosmeticRules.luau")
local ProfileSchema = Loader.load("src/shared/Pure/ProfileSchema.luau")
local WeaponStats = Loader.load("src/shared/Pure/WeaponStats.luau")
local ChallengeEvents = Loader.load("src/server/Services/ChallengeEvents.luau")
local describe, it, expect = T.describe, T.it, T.expect

local function weaponOfClass(class: string): string
	for id, def in Weapons do
		if def.class == class then
			return id
		end
	end
	error("no weapon of class " .. class)
end

describe("ChallengeEvents kill mapping", function()
	it("maps weapon ids to their class, Melee and killstreak ids", function()
		local sniper = weaponOfClass("Sniper")
		expect(ChallengeEvents.killClass(sniper, Weapons)).toBe("Sniper")
		expect(ChallengeEvents.killClass("SP3", Weapons)).toBe("MachinePistol")
		expect(ChallengeEvents.killClass("Melee", Weapons)).toBe("Melee")
		expect(ChallengeEvents.killClass("Streak:MortarBarrage", Weapons)).toBe("Streak")
		expect(ChallengeEvents.killClass("Nope", Weapons)).toBe(nil)
		expect(ChallengeEvents.killClass(nil, Weapons)).toBe(nil)
		expect(ChallengeEvents.isStreakKill("Streak:SentryGun")).toBe(true)
		expect(ChallengeEvents.isStreakKill("VK7")).toBe(false)
		expect(ChallengeEvents.isStreakKill(nil)).toBe(false)
	end)
	it("kill events count toward the right challenges; streak kills never count", function()
		local kills, pistol, sniper, heads = Challenges.byId.Kills, Challenges.byId.PistolKills, Challenges.byId.SniperKills, Challenges.byId.Headshots
		local mp = ChallengeEvents.killEvent("SP3", false, Weapons)
		expect(ChallengeRules.amount(pistol, mp)).toBe(1) -- machine pistols count as pistols
		expect(ChallengeRules.amount(kills, mp)).toBe(1)
		expect(ChallengeRules.amount(heads, mp)).toBe(0)
		local hs = ChallengeEvents.killEvent(weaponOfClass("Sniper"), true, Weapons)
		expect(ChallengeRules.amount(sniper, hs)).toBe(1)
		expect(ChallengeRules.amount(heads, hs)).toBe(1)
		local streak = ChallengeEvents.killEvent("Streak:MortarBarrage", false, Weapons)
		expect(ChallengeRules.amount(kills, streak)).toBe(0)
		expect(ChallengeRules.amount(Challenges.byId.MeleeKills, ChallengeEvents.killEvent("Melee", false, Weapons))).toBe(1)
	end)
end)

describe("ChallengeEvents objective mapping", function()
	it("maps award reasons to events per the contract", function()
		expect(ChallengeEvents.objectiveEvent("Capture").kind).toBe("capture")
		expect(ChallengeEvents.objectiveEvent("Bomb Planted").kind).toBe("plant")
		expect(ChallengeEvents.objectiveEvent("Bomb Defused").kind).toBe("defuse")
		expect(ChallengeEvents.objectiveEvent("Kill Confirmed").kind).toBe("tag")
		expect(ChallengeEvents.objectiveEvent("Kill Denied").kind).toBe("tag")
		local hp = ChallengeEvents.objectiveEvent("Hardpoint")
		expect(hp.kind).toBe("hardpointSecond")
		expect(hp.amount).toBe(5)
		expect(ChallengeEvents.objectiveEvent("Round Win")).toBe(nil)
		expect(ChallengeEvents.objectiveEvent("Kill")).toBe(nil)
	end)
	it("returns a fresh table each time", function()
		local a = ChallengeEvents.objectiveEvent("Hardpoint")
		a.amount = 99
		expect(ChallengeEvents.objectiveEvent("Hardpoint").amount).toBe(5)
	end)
	it("Hardpoint awards advance the hold challenge by five seconds", function()
		expect(ChallengeRules.amount(Challenges.byId.Hardpoint, ChallengeEvents.objectiveEvent("Hardpoint"))).toBe(5)
	end)
end)

describe("ChallengeEvents lifetime stats", function()
	it("bumps the matching stat and leaves kills, matches and wins to their callers", function()
		local p = ProfileSchema.default(0, 1)
		expect(ChallengeEvents.applyStats(p.stats, { kind = "assist" })).toBe(true)
		expect(ChallengeEvents.applyStats(p.stats, ChallengeEvents.objectiveEvent("Capture"))).toBe(true)
		expect(ChallengeEvents.applyStats(p.stats, ChallengeEvents.objectiveEvent("Bomb Planted"))).toBe(true)
		expect(ChallengeEvents.applyStats(p.stats, ChallengeEvents.objectiveEvent("Bomb Defused"))).toBe(true)
		expect(ChallengeEvents.applyStats(p.stats, ChallengeEvents.objectiveEvent("Kill Denied"))).toBe(true)
		expect(p.stats.assists).toBe(1)
		expect(p.stats.captures).toBe(1)
		expect(p.stats.plants).toBe(1)
		expect(p.stats.defuses).toBe(1)
		expect(p.stats.tags).toBe(1)
		for _, kind in { "kill", "match", "win", "hardpointSecond", "streakEarned" } do
			expect(ChallengeEvents.applyStats(p.stats, { kind = kind })).toBe(false)
		end
		expect(p.stats.kills).toBe(0)
		expect(p.stats.matches).toBe(0)
		expect(ChallengeEvents.applyStats(p.stats, { kind = "tag", amount = -3 })).toBe(false)
		expect(p.stats.tags).toBe(1)
	end)
	it("every stat key it writes exists in the profile schema", function()
		local p = ProfileSchema.default(0, 1)
		for _, key in ChallengeEvents.EVENT_STATS do
			expect(type(p.stats[key])).toBe("number")
		end
	end)
end)

describe("QA helpers", function()
	it("completionEvent completes each challenge in the pool from any progress", function()
		for _, def in Challenges.pool do
			local state = { day = 1, daily = { { id = def.id, progress = 0, done = false } } }
			local done = ChallengeRules.record(state, ChallengeEvents.completionEvent(def, 0))
			expect(#done).toBe(1)
			expect(state.daily[1].done).toBe(true)
			local half = math.floor(def.target / 2)
			local state2 = { day = 1, daily = { { id = def.id, progress = half, done = false } } }
			expect(#ChallengeRules.record(state2, ChallengeEvents.completionEvent(def, half))).toBe(1)
		end
	end)
	it("raiseStats unlocks stat titles and kill camos without lowering anything", function()
		local p = ProfileSchema.default(0, 1)
		p.stats.kills = 5000
		local ids = {}
		for id in Weapons do
			table.insert(ids, id)
		end
		ChallengeEvents.raiseStats(p, 300, ids)
		expect(p.stats.kills).toBe(5000)
		expect(p.stats.dailies).toBe(300)
		expect(CosmeticRules.ownsTitle(p, "Victor")).toBe(true)
		expect(CosmeticRules.ownsTitle(p, "Veteran")).toBe(true)
		for _, id in ids do
			expect(p.weapons[id].kills).toBe(300)
			expect(p.weapons[id].headshots).toBe(100)
			expect(CosmeticRules.ownsCamo(p, id, "Gilded")).toBe(true)
		end
	end)
end)

describe("Prestige keeps unlocks", function()
	it("resets account level only; weapon levels and so attachment unlocks are untouched", function()
		local p = ProfileSchema.default(0, 1)
		p.account.level = Progression.MaxAccountLevel
		p.account.xp = 123
		local id = weaponOfClass("AssaultRifle")
		p.weapons[id] = { level = Progression.MaxWeaponLevel, xp = 0, kills = 10, headshots = 2 }
		-- the highest-level attachment for that weapon validates before and after
		local def = Weapons[id]
		local bestSlot, bestId, bestLevel = nil, nil, -1
		for attId, lvl in def.attachmentUnlocks do
			if lvl > bestLevel and Attachments[attId] then
				bestSlot, bestId, bestLevel = Attachments[attId].slot, attId, lvl
			end
		end
		expect(bestId ~= nil).toBe(true)
		local sel = { [bestSlot] = bestId }
		expect((WeaponStats.validate(def, sel, p.weapons[id].level, Attachments))).toBe(true)
		expect(CosmeticRules.canPrestige(p, Progression.MaxAccountLevel, Progression.MaxPrestige)).toBe(true)
		CosmeticRules.applyPrestige(p)
		expect(p.account.level).toBe(1)
		expect(p.account.prestige).toBe(1)
		expect(p.weapons[id].level).toBe(Progression.MaxWeaponLevel)
		expect((WeaponStats.validate(def, sel, p.weapons[id].level, Attachments))).toBe(true)
		expect(CosmeticRules.canPrestige(p, Progression.MaxAccountLevel, Progression.MaxPrestige)).toBe(false)
		expect(CosmeticRules.ownsEmblem(p, "Prestige1")).toBe(true)
		expect(CosmeticRules.ownsEmblem(p, "Prestige2")).toBe(false)
	end)
end)
