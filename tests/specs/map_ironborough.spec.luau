require("../lib/MapContract")("src/server/Maps/IronBorough.luau", { id = "IronBorough", displayName = "Iron Borough" })

-- Iron Borough specific checks.
local T = require("../lib/T")
local Loader = require("../lib/Loader")
local MapModule = Loader.load("src/server/Maps/IronBorough.luau")
local describe, it, expect = T.describe, T.it, T.expect

local function luminance(c: any): number
	return (c.R + c.G + c.B) / 3
end

describe("Iron Borough specifics", function()
	it("night lighting stays readable", function()
		local L = MapModule.lighting
		expect(L.Brightness).toBeAtLeast(1.5)
		expect(luminance(L.Ambient)).toBeAtLeast(0.4)
		expect(luminance(L.OutdoorAmbient)).toBeAtLeast(0.4)
		expect(L.FogStart).toBeAtLeast(250)
		expect(L.GlobalShadows).toBe(true)
		expect(MapModule.atmosphere.Density).toBeLessThan(0.4)
	end)

	it("street lamps carry real lights", function()
		local model = MapModule.build()
		local lamps, lit = 0, 0
		for _, d in model:GetDescendants() do
			if d.Name == "LampBulb" then
				lamps += 1
				if d:FindFirstChildOfClass("PointLight") then
					lit += 1
				end
			end
		end
		expect(lamps).toBeAtLeast(16)
		expect(lit).toBe(lamps)
	end)

	it("the underpass floor sits on the bottom of the ground", function()
		local model = MapModule.build()
		local floor = model:FindFirstChild("UnderpassFloor", true)
		expect(floor ~= nil).toBeTruthy()
		expect(floor.CFrame.Position.Y + floor.Size.Y / 2).toBeNear(-10)
		expect(floor.CFrame.Position.Y - floor.Size.Y / 2).toBeNear(model:GetAttribute("BoundsMin").Y)
	end)
end)

return nil
