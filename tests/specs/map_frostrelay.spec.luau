require("../lib/MapContract")("src/server/Maps/FrostRelay.luau", { id = "FrostRelay", displayName = "Frost Relay" })

-- Frost Relay specific checks.
local T = require("../lib/T")
local Loader = require("../lib/Loader")
local MapModule = Loader.load("src/server/Maps/FrostRelay.luau")
local describe, it, expect = T.describe, T.it, T.expect

describe("Frost Relay specifics", function()
	it("fog and atmosphere do not hide players inside 250 studs", function()
		expect(MapModule.lighting.FogStart).toBeAtLeast(250)
		expect(MapModule.lighting.GlobalShadows).toBe(true)
		expect(MapModule.atmosphere.Density).toBeLessThan(0.4)
	end)

	it("the frozen reservoir is a walkable ice floor (not a pit) and reaches the bottom of the ground", function()
		local model = MapModule.build()
		local ice = model:FindFirstChild("ReservoirIce", true)
		expect(ice ~= nil).toBeTruthy()
		expect(ice.CanCollide).toBe(true)
		expect(ice.Material.Name).toBe("Ice")
		local top = ice.CFrame.Position.Y + ice.Size.Y / 2
		local bottom = ice.CFrame.Position.Y - ice.Size.Y / 2
		expect(top).toBeNear(-3)
		expect(bottom).toBeNear(model:GetAttribute("BoundsMin").Y)
	end)
end)

return nil
