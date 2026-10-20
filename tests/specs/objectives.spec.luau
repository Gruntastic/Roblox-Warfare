local Loader = require("../lib/Loader")
local T = require("../lib/T")
local O = Loader.load("src/shared/Pure/Objectives.luau")
local V3 = Loader.roblox.Vector3
local CF = Loader.roblox.CFrame
local describe, it, expect = T.describe, T.it, T.expect

local function flag(owner: string?)
	return { owner = owner, capturingTeam = nil, progress = 0, contested = false }
end

-- Steps a flag in 0.1 s ticks for `seconds`; returns the first captured team, if any.
local function run(f, counts, seconds, captureTime)
	local captured = nil
	for _ = 1, math.floor(seconds * 10 + 0.5) do
		captured = O.stepFlag(f, counts, 0.1, captureTime) or captured
	end
	return captured
end

describe("Objectives.inBox", function()
	it("axis-aligned and rotated boxes", function()
		local cf = CF.new(10, 4, 10)
		local size = V3.new(20, 8, 10)
		expect(O.inBox(cf, size, V3.new(19, 1, 14))).toBe(true)
		expect(O.inBox(cf, size, V3.new(21, 1, 10))).toBe(false)
		expect(O.inBox(cf, size, V3.new(10, 9, 10))).toBe(false)
		local rotated = CF.new(0, 4, 0) * CF.Angles(0, math.pi / 2, 0) -- long axis now along Z
		expect(O.inBox(rotated, size, V3.new(0, 1, 9))).toBe(true)
		expect(O.inBox(rotated, size, V3.new(9, 1, 0))).toBe(false)
	end)
end)

describe("Domination capture", function()
	it("one player captures a neutral flag in captureTime", function()
		local f = flag(nil)
		expect(run(f, { Sable = 1 }, 9.8, 10)).toBe(nil)
		expect(f.capturingTeam).toBe("Sable")
		expect(run(f, { Sable = 1 }, 0.3, 10)).toBe("Sable")
		expect(f.owner).toBe("Sable")
		expect(f.progress).toBe(0)
	end)
	it("more capturers are faster, capped at three", function()
		expect(O.captureRate(1)).toBe(1)
		expect(O.captureRate(2)).toBe(1.5)
		expect(O.captureRate(3)).toBe(2)
		expect(O.captureRate(6)).toBe(2)
		local f = flag(nil)
		expect(run(f, { Talon = 3 }, 5.1, 10)).toBe("Talon")
	end)
	it("contested flags freeze", function()
		local f = flag(nil)
		run(f, { Sable = 1 }, 4, 10)
		local before = f.progress
		run(f, { Sable = 2, Talon = 1 }, 3, 10)
		expect(f.progress).toBeNear(before, 1e-9)
		expect(f.contested).toBe(true)
	end)
	it("an owned flag must be fully captured by the enemy, and the owner drains enemy progress", function()
		local f = flag("Sable")
		run(f, { Talon = 1 }, 5, 10)
		expect(f.owner).toBe("Sable")
		expect(f.progress).toBeNear(0.5, 1e-6)
		run(f, { Sable = 1 }, 2, 10)
		expect(f.progress).toBeNear(0.3, 1e-6)
		expect(f.owner).toBe("Sable")
		expect(run(f, { Talon = 1 }, 7.1, 10)).toBe("Talon")
		expect(f.owner).toBe("Talon")
	end)
	it("abandoned progress drains to neutral", function()
		local f = flag(nil)
		run(f, { Sable = 1 }, 3, 10)
		run(f, {}, 4, 10)
		expect(f.progress).toBe(0)
		expect(f.capturingTeam).toBe(nil)
	end)
	it("a team taking over another's partial capture first drains it", function()
		local f = flag(nil)
		run(f, { Sable = 1 }, 4, 10) -- 0.4 Sable
		run(f, { Talon = 1 }, 5, 10) -- drains 0.4, then 0.1 Talon
		expect(f.capturingTeam).toBe("Talon")
		expect(f.progress).toBeNear(0.1, 1e-6)
	end)
	it("presence ignores teams with zero players", function()
		local only, contested = O.presence({ Sable = 0, Talon = 2 })
		expect(only).toBe("Talon")
		expect(contested).toBe(false)
	end)
end)

describe("Hardpoint rotation", function()
	it("no zone before the first delay, then rotates in order and wraps", function()
		local idx, ends = O.hardpointAt(5, 10, 60, 4)
		expect(idx).toBe(nil)
		expect(ends).toBe(10)
		idx, ends = O.hardpointAt(10, 10, 60, 4)
		expect(idx).toBe(1)
		expect(ends).toBe(70)
		expect((O.hardpointAt(69.9, 10, 60, 4))).toBe(1)
		expect((O.hardpointAt(70, 10, 60, 4))).toBe(2)
		expect((O.hardpointAt(249, 10, 60, 4))).toBe(4)
		expect((O.hardpointAt(250, 10, 60, 4))).toBe(1)
	end)
end)

describe("Search and Destroy rounds", function()
	local function view(over)
		local v = {
			attackers = "Sable",
			defenders = "Talon",
			alive = { Sable = 3, Talon = 3 },
			started = { Sable = 3, Talon = 3 },
			bomb = "Carried",
			timeUp = false,
		}
		for k, val in over do
			v[k] = val
		end
		return v
	end
	it("in progress while both sides live and the clock runs", function()
		expect((O.roundOutcome(view({})))).toBe(nil)
	end)
	it("elimination either way before a plant", function()
		local w, why = O.roundOutcome(view({ alive = { Sable = 0, Talon = 2 } }))
		expect(w).toBe("Talon")
		expect(why).toBe("Elimination")
		w, why = O.roundOutcome(view({ alive = { Sable = 1, Talon = 0 } }))
		expect(w).toBe("Sable")
		expect(why).toBe("Elimination")
	end)
	it("after a plant, wiping the attackers does not end the round", function()
		expect((O.roundOutcome(view({ bomb = "Planted", alive = { Sable = 0, Talon = 2 } })))).toBe(nil)
		local w = O.roundOutcome(view({ bomb = "Planted", alive = { Sable = 1, Talon = 0 } }))
		expect(w).toBe("Sable")
	end)
	it("time favours defenders, unless the bomb is planted", function()
		local w, why = O.roundOutcome(view({ timeUp = true }))
		expect(w).toBe("Talon")
		expect(why).toBe("Time")
		expect((O.roundOutcome(view({ timeUp = true, bomb = "Planted" })))).toBe(nil)
	end)
	it("detonation and defusal decide the round", function()
		local w, why = O.roundOutcome(view({ bomb = "Detonated", alive = { Sable = 0, Talon = 3 } }))
		expect(w).toBe("Sable")
		expect(why).toBe("Detonated")
		w, why = O.roundOutcome(view({ bomb = "Defused" }))
		expect(w).toBe("Talon")
		expect(why).toBe("Defused")
	end)
	it("a team that started empty cannot be eliminated (solo testing)", function()
		local v = view({ alive = { Sable = 1, Talon = 0 }, started = { Sable = 1, Talon = 0 } })
		expect((O.roundOutcome(v))).toBe(nil)
	end)
	it("sides swap after the configured number of rounds", function()
		expect(O.attackersFor(1, "Sable", "Talon", 3)).toBe("Sable")
		expect(O.attackersFor(3, "Sable", "Talon", 3)).toBe("Sable")
		expect(O.attackersFor(4, "Sable", "Talon", 3)).toBe("Talon")
		expect(O.attackersFor(6, "Sable", "Talon", 3)).toBe("Talon")
		expect(O.attackersFor(7, "Sable", "Talon", 3)).toBe("Sable")
	end)
end)

return nil
