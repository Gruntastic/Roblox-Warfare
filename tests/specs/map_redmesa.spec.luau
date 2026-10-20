require("../lib/MapContract")("src/server/Maps/RedMesa.luau", { id = "RedMesa", displayName = "Red Mesa" })

-- Red Mesa specific: every floor level (wash, street, ore terrace, ridge) gets FFA spawns.
local T = require("../lib/T")
local Loader = require("../lib/Loader")
local model = Loader.load("src/server/Maps/RedMesa.luau").build()
T.describe("Red Mesa layout", function()
	T.it("FFA spawns cover all four floor levels", function()
		local levels = { [-8] = 0, [0] = 0, [6] = 0, [12] = 0 }
		for _, s in model:FindFirstChild("Spawns"):GetChildren() do
			if s:GetAttribute("FFA") then
				local y = math.floor(s.CFrame.Position.Y - 0.5 + 0.5)
				if levels[y] ~= nil then
					levels[y] += 1
				end
			end
		end
		for y, n in levels do
			if n < 1 then
				error("no FFA spawn on level Y " .. y)
			end
		end
	end)
end)

return nil
