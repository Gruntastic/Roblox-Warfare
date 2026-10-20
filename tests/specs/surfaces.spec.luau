-- Texture flicker: no two different-looking parts may share a face plane after SurfaceFix runs
-- (MatchService applies it to every map it loads).
local T = require("../lib/T")
local Loader = require("../lib/Loader")
local SurfaceFix = Loader.load("src/shared/SurfaceFix.luau")
local roblox = require("@lune/roblox")
local Instance, Vector3, Color3 = roblox.Instance, roblox.Vector3, roblox.Color3

T.describe("Map surfaces (z-fighting)", function()
	for _, id in { "DustlineTerminal", "IronBorough", "Breakwater", "FrostRelay", "AshwoodEstate", "RedMesa" } do
		T.it(id .. " has no flickering faces after SurfaceFix", function()
			local model = Loader.load("src/server/Maps/" .. id .. ".luau").build()
			local before: { [any]: any } = {}
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					before[d] = { d.CFrame.Position, d.Size }
				end
			end
			SurfaceFix.apply(model)
			local left = SurfaceFix.find(model)
			if #left > 0 then
				error(("%d left, e.g. %s / %s"):format(#left, left[1].a.Name, left[1].b.Name))
			end
			-- parts stay where they were and grow by at most a few hundredths of a stud
			for part, old in before do
				assert((part.CFrame.Position - old[1]).Magnitude < 1e-4, part.Name .. " moved")
				local g = part.Size - old[2]
				assert(math.max(g.X, g.Y, g.Z) <= 0.25, part.Name .. " grew too much")
			end
		end)
	end
	T.it("finds a planted overlay and fixes it", function()
		local m = Instance.new("Model")
		local floor = Instance.new("Part")
		floor.Size = Vector3.new(20, 1, 20)
		floor.Parent = m
		local stripe = Instance.new("Part")
		stripe.Size = Vector3.new(2, 1, 20)
		stripe.Color = Color3.new(1, 1, 0)
		stripe.Parent = m
		assert(#SurfaceFix.find(m) > 0, "overlay not found")
		SurfaceFix.apply(m)
		assert(#SurfaceFix.find(m) == 0, "overlay not fixed")
		assert(stripe.Size.Y > 1, "smaller part should win")
	end)
end)

return nil
