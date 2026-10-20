require("../lib/MapContract")("src/server/Maps/Breakwater.luau", { id = "Breakwater", displayName = "Breakwater" })

-- Breakwater specific: the harbour water is a shallow walkable floor, not a pit.
local T = require("../lib/T")
local Loader = require("../lib/Loader")
local model = Loader.load("src/server/Maps/Breakwater.luau").build()
T.describe("Breakwater layout", function()
	T.it("harbour water is a collidable floor sunk 1 to 2 studs", function()
		local water = model:FindFirstChild("Geometry"):FindFirstChild("Ground"):FindFirstChild("HarbourWater")
		T.expect(water ~= nil).toBeTruthy()
		T.expect(water.CanCollide).toBe(true)
		local top = water.CFrame.Position.Y + water.Size.Y / 2
		T.expect(top <= -1 and top >= -2).toBeTruthy()
	end)
end)

return nil
