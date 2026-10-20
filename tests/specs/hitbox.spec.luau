local Loader = require("../lib/Loader")
local T = require("../lib/T")
local Hitbox = Loader.load("src/shared/Pure/Hitbox.luau")
local roblox = Loader.roblox
local V3, CF = roblox.Vector3, roblox.CFrame
local describe, it, expect = T.describe, T.it, T.expect

local function snap(t, pos)
	local root = CF.new(pos)
	return { t = t, root = root, head = root * CF.new(0, 1.6, 0) }
end

describe("Hitbox", function()
	it("ray hits an axis-aligned box at the right distance", function()
		local d = Hitbox.rayOBB(V3.new(0, 0, 0), V3.new(0, 0, -1), 100, CF.new(0, 0, -10), V3.new(2, 2, 2))
		expect(d).toBeNear(9, 1e-4)
	end)
	it("ray misses a box off to the side", function()
		expect(Hitbox.rayOBB(V3.new(0, 0, 0), V3.new(0, 0, -1), 100, CF.new(5, 0, -10), V3.new(2, 2, 2))).toBe(nil)
	end)
	it("respects max distance", function()
		expect(Hitbox.rayOBB(V3.new(0, 0, 0), V3.new(0, 0, -1), 5, CF.new(0, 0, -10), V3.new(2, 2, 2))).toBe(nil)
	end)
	it("works for rotated boxes", function()
		local cf = CF.new(0, 0, -10) * CF.Angles(0, math.rad(45), 0)
		local d = Hitbox.rayOBB(V3.new(0, 0, 0), V3.new(0, 0, -1), 100, cf, V3.new(2, 2, 2))
		expect(d).toBeNear(10 - math.sqrt(2), 1e-3)
	end)
	it("classifies head, body and legs", function()
		local s = snap(0, V3.new(0, 3, -20))
		local _, zHead = Hitbox.testCharacter(V3.new(0, 4.6, 0), V3.new(0, 0, -1), 100, s)
		local _, zBody = Hitbox.testCharacter(V3.new(0, 3.3, 0), V3.new(0, 0, -1), 100, s)
		local _, zLegs = Hitbox.testCharacter(V3.new(0, 1.0, 0), V3.new(0, 0, -1), 100, s)
		expect(zHead).toBe("Head")
		expect(zBody).toBe("Body")
		expect(zLegs).toBe("Limb")
	end)
	it("lag compensation: sample() interpolates history", function()
		local h = { snap(0, V3.new(0, 3, 0)), snap(0.1, V3.new(10, 3, 0)) }
		local s = Hitbox.sample(h, 0.05)
		expect(s.root.Position.X).toBeNear(5, 1e-4)
		expect(Hitbox.sample(h, -1).root.Position.X).toBe(0)
		expect(Hitbox.sample(h, 5).root.Position.X).toBe(10)
	end)
	it("a shot at a rewound position hits where the current position misses", function()
		local h = { snap(0, V3.new(0, 3, -30)), snap(0.2, V3.new(12, 3, -30)) }
		local origin, dir = V3.new(0, 3.3, 0), V3.new(0, 0, -1)
		expect((Hitbox.testCharacter(origin, dir, 100, h[2]))).toBe(nil)
		expect(Hitbox.testCharacter(origin, dir, 100, Hitbox.sample(h, 0.0))).toBeTruthy()
	end)
end)
return nil
