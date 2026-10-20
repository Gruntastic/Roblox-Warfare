local Loader = require("../lib/Loader")
local T = require("../lib/T")
local XPRules = Loader.load("src/shared/Pure/XPRules.luau")
local Teams = Loader.load("src/shared/Pure/Teams.luau")
local MatchRules = Loader.load("src/shared/Pure/MatchRules.luau")
local Progression = Loader.load("src/shared/Config/Progression.luau")
local V3 = Loader.roblox.Vector3
local describe, it, expect = T.describe, T.it, T.expect

describe("XPRules", function()
	local decay = Progression.RepeatVictimDecay
	it("full XP for early kills on a victim, decaying when farmed", function()
		expect(XPRules.repeatMultiplier(decay, 1)).toBe(1)
		expect(XPRules.repeatMultiplier(decay, 8)).toBe(1)
		expect(XPRules.repeatMultiplier(decay, 9)).toBe(0.5)
		expect(XPRules.repeatMultiplier(decay, 16)).toBe(0.2)
		expect(XPRules.repeatMultiplier(decay, 26)).toBe(0)
	end)
	it("caps combat XP per minute", function()
		expect(XPRules.capCombat(0, 100, 60, 3500)).toBe(100)
		expect(XPRules.capCombat(3450, 100, 60, 3500)).toBe(50)
		expect(XPRules.capCombat(3500, 100, 60, 3500)).toBe(0)
		expect(XPRules.capCombat(3500, 100, 120, 3500)).toBe(100)
	end)
	it("match completion awards time, completion and win bonus", function()
		local list = XPRules.matchCompletion(Progression.AccountXP, 600, true, true)
		local total = 0
		for _, e in list do
			total += e.amount
		end
		expect(total).toBe(400 + 500 + 300)
		local quit = XPRules.matchCompletion(Progression.AccountXP, 30, false, false)
		expect(#quit).toBe(1)
	end)
end)

describe("Teams", function()
	it("balances to the smaller team", function()
		expect(Teams.pick({ "Sable", "Talon" }, { Sable = 3, Talon = 2 })).toBe("Talon")
		expect(Teams.pick({ "Sable", "Talon" }, {})).toBe("Sable")
		expect(Teams.pick({ "Sable", "Talon" }, { Sable = 2, Talon = 2 }, { Sable = 10, Talon = 3 })).toBe("Talon")
	end)
	it("assigns 12 players into 6v6", function()
		local counts = {}
		for _ = 1, 12 do
			local t = Teams.pick({ "Sable", "Talon" }, counts)
			counts[t] = (counts[t] or 0) + 1
		end
		expect(counts.Sable).toBe(6)
		expect(counts.Talon).toBe(6)
	end)
	it("chooses the spawn farthest from enemies and avoids blocked spawns", function()
		local spawns = { V3.new(0, 0, 0), V3.new(100, 0, 0), V3.new(200, 0, 0) }
		local enemies = { V3.new(10, 0, 0) }
		expect(Teams.chooseSpawn(spawns, enemies, {})).toBe(3)
		expect(Teams.chooseSpawn(spawns, enemies, {}, function(i)
			return i == 3
		end)).toBe(2)
	end)
end)

describe("MatchRules", function()
	it("score limit ends the match", function()
		local over, reason = MatchRules.isOver(75, { Sable = 75, Talon = 40 }, 10, 100)
		expect(over).toBe(true)
		expect(reason).toBe("score")
	end)
	it("time limit ends the match", function()
		local over, reason = MatchRules.isOver(75, { Sable = 5, Talon = 4 }, 101, 100)
		expect(over).toBe(true)
		expect(reason).toBe("time")
	end)
	it("winner or draw", function()
		expect(MatchRules.winner({ Sable = 10, Talon = 4 })).toBe("Sable")
		expect(MatchRules.winner({ Sable = 4, Talon = 4 })).toBe(nil)
	end)
end)
return nil
