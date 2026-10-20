-- Map contract + layout sanity checks for Dustline Terminal.
local T = require("../lib/T")
local Loader = require("../lib/Loader")

local MapModule = Loader.load("src/server/Maps/DustlineTerminal.luau")
local Vector3 = (Loader.roblox :: any).Vector3

local describe, it, expect = T.describe, T.it, T.expect

type Box = { min: any, max: any, part: any }

-- Conservative world AABB for a (possibly rotated) part.
local function aabb(part: any): Box
	local cf, size = part.CFrame, part.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local hx = math.abs(r.X) * size.X / 2 + math.abs(u.X) * size.Y / 2 + math.abs(l.X) * size.Z / 2
	local hy = math.abs(r.Y) * size.X / 2 + math.abs(u.Y) * size.Y / 2 + math.abs(l.Y) * size.Z / 2
	local hz = math.abs(r.Z) * size.X / 2 + math.abs(u.Z) * size.Y / 2 + math.abs(l.Z) * size.Z / 2
	local p = cf.Position
	return {
		min = Vector3.new(p.X - hx, p.Y - hy, p.Z - hz),
		max = Vector3.new(p.X + hx, p.Y + hy, p.Z + hz),
		part = part,
	}
end

local model = MapModule.build()
local geometry = model:FindFirstChild("Geometry")
local spawnsFolder = model:FindFirstChild("Spawns")

local parts: { any } = {}
local boxes: { Box } = {}
if geometry then
	for _, d in geometry:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(boxes, aabb(d))
		end
	end
end

local sable, talon, ffa = {}, {}, {}
local allSpawns = {}
if spawnsFolder then
	for _, s in spawnsFolder:GetChildren() do
		table.insert(allSpawns, s)
		local team = s:GetAttribute("Team")
		if team == "Sable" then
			table.insert(sable, s)
		elseif team == "Talon" then
			table.insert(talon, s)
		end
		if s:GetAttribute("FFA") == true then
			table.insert(ffa, s)
		end
	end
end

local function centroid(list: { any })
	local x, y, z = 0, 0, 0
	for _, s in list do
		x += s.CFrame.Position.X
		y += s.CFrame.Position.Y
		z += s.CFrame.Position.Z
	end
	return Vector3.new(x / #list, y / #list, z / #list)
end

local function hasFloor(pos: any): boolean
	for _, b in boxes do
		if b.part.CanCollide then
			local drop = pos.Y - b.max.Y
			if drop >= -0.01 and drop <= 1.5 and pos.X >= b.min.X and pos.X <= b.max.X and pos.Z >= b.min.Z and pos.Z <= b.max.Z then
				return true
			end
		end
	end
	return false
end

local function blockedBy(pos: any): any?
	local mn = Vector3.new(pos.X - 1, pos.Y - 0.4, pos.Z - 1)
	local mx = Vector3.new(pos.X + 1, pos.Y + 5, pos.Z + 1)
	for _, b in boxes do
		if b.part.CanCollide then
			if mn.X < b.max.X and mx.X > b.min.X and mn.Y < b.max.Y and mx.Y > b.min.Y and mn.Z < b.max.Z and mx.Z > b.min.Z then
				return b.part
			end
		end
	end
	return nil
end

-- Horizontal ray vs AABB list; returns hit distance (or maxT).
local function castXZ(ox: number, oy: number, oz: number, dx: number, dz: number, maxT: number): number
	local best = maxT
	for _, b in boxes do
		local p = b.part
		if p.Transparency < 0.3 and oy >= b.min.Y and oy <= b.max.Y then
			local t0, t1 = 0, best
			local ok = true
			for axis = 1, 2 do
				local o = if axis == 1 then ox else oz
				local d = if axis == 1 then dx else dz
				local lo = if axis == 1 then b.min.X else b.min.Z
				local hi = if axis == 1 then b.max.X else b.max.Z
				if math.abs(d) < 1e-9 then
					if o < lo or o > hi then
						ok = false
						break
					end
				else
					local ta, tb = (lo - o) / d, (hi - o) / d
					if ta > tb then
						ta, tb = tb, ta
					end
					t0 = math.max(t0, ta)
					t1 = math.min(t1, tb)
					if t0 > t1 then
						ok = false
						break
					end
				end
			end
			if ok and t0 < best then
				best = t0
			end
		end
	end
	return best
end

-- Longest distance a spawn's eye-level view travels into the shared play space (|X| < 121).
local function spawnExposure(s: any): number
	local pos = s.CFrame.Position
	local worst = 0
	local n = 144
	for i = 0, n - 1 do
		local a = (i / n) * math.pi * 2
		local dx, dz = math.cos(a), math.sin(a)
		local hit = castXZ(pos.X, pos.Y + 4.5, pos.Z, dx, dz, 600)
		-- interval of t where |x| < 121
		local tIn, tOut
		if math.abs(dx) < 1e-9 then
			if math.abs(pos.X) < 121 then
				tIn, tOut = 0, math.huge
			else
				tIn, tOut = math.huge, math.huge
			end
		else
			local ta, tb = (-121 - pos.X) / dx, (121 - pos.X) / dx
			tIn, tOut = math.max(0, math.min(ta, tb)), math.max(ta, tb)
		end
		local seen = math.min(hit, tOut) - tIn
		if seen > worst then
			worst = seen
		end
	end
	return worst
end

describe("Dustline Terminal map", function()
	it("exports id, displayName, lighting, atmosphere and build", function()
		expect(MapModule.id).toBe("DustlineTerminal")
		expect(MapModule.displayName).toBe("Dustline Terminal")
		expect(type(MapModule.build)).toBe("function")
		local validLighting = {
			Ambient = true, Brightness = true, ClockTime = true, ColorShift_Bottom = true, ColorShift_Top = true,
			EnvironmentDiffuseScale = true, EnvironmentSpecularScale = true, ExposureCompensation = true,
			FogColor = true, FogEnd = true, FogStart = true, GeographicLatitude = true, GlobalShadows = true,
			OutdoorAmbient = true, ShadowSoftness = true,
		}
		for k in MapModule.lighting do
			expect(validLighting[k]).toBeTruthy()
		end
		local validAtmo = { Density = true, Offset = true, Color = true, Decay = true, Glare = true, Haze = true }
		for k in MapModule.atmosphere do
			expect(validAtmo[k]).toBeTruthy()
		end
	end)

	it("builds an unparented Model named Map with required children", function()
		expect(model.ClassName).toBe("Model")
		expect(model.Name).toBe("Map")
		expect(model.Parent).toBe(nil)
		expect(geometry ~= nil and geometry:IsA("Folder")).toBeTruthy()
		expect(spawnsFolder ~= nil and spawnsFolder:IsA("Folder")).toBeTruthy()
		local cam = model:FindFirstChild("LobbyCamera")
		expect(cam ~= nil and cam:IsA("BasePart")).toBeTruthy()
		expect(cam.Transparency).toBe(1)
		expect(cam.Anchored).toBe(true)
		expect(cam.CanQuery).toBe(false)
		expect(type(model:GetAttribute("KillY"))).toBe("number")
		expect(model:GetAttribute("KillY")).toBeLessThan(-7)
	end)

	it("has enough spawns per contract", function()
		expect(#sable).toBeAtLeast(8)
		expect(#talon).toBeAtLeast(8)
		expect(#ffa).toBeAtLeast(12)
	end)

	it("spawns are invisible, anchored, non-colliding, non-query, non-touch, size 2x1x2", function()
		for _, s in allSpawns do
			expect(s:IsA("BasePart")).toBeTruthy()
			expect(s.Transparency).toBe(1)
			expect(s.Anchored).toBe(true)
			expect(s.CanCollide).toBe(false)
			expect(s.CanQuery).toBe(false)
			expect(s.CanTouch).toBe(false)
			expect(s.Size.X).toBeNear(2)
			expect(s.Size.Y).toBeNear(1)
			expect(s.Size.Z).toBeNear(2)
		end
	end)

	it("team spawn centroids are >= 150 studs apart", function()
		local d = (centroid(sable) - centroid(talon)).Magnitude
		expect(d).toBeAtLeast(150)
	end)

	it("every Talon spawn is >= 100 studs from the nearest Sable spawn", function()
		local minD = math.huge
		for _, t in talon do
			for _, s in sable do
				minD = math.min(minD, (t.CFrame.Position - s.CFrame.Position).Magnitude)
			end
		end
		expect(minD).toBeAtLeast(100)
	end)

	it("FFA spawns are pairwise >= 20 studs apart", function()
		for i = 1, #ffa do
			for j = i + 1, #ffa do
				local d = (ffa[i].CFrame.Position - ffa[j].CFrame.Position).Magnitude
				if d < 20 then
					error(("%s and %s are %.1f apart"):format(tostring(ffa[i].CFrame.Position), tostring(ffa[j].CFrame.Position), d))
				end
			end
		end
	end)

	it("spawns face into the map (horizontal look vector toward the centre)", function()
		for _, s in allSpawns do
			local look = s.CFrame.LookVector
			expect(math.abs(look.Y)).toBeLessThan(0.01)
		end
		for _, s in sable do
			expect(s.CFrame.LookVector.X).toBeGreaterThan(0.5)
		end
		for _, s in talon do
			expect(s.CFrame.LookVector.X).toBeLessThan(-0.5)
		end
	end)

	it("all geometry is anchored and queryable", function()
		for _, p in parts do
			if not p.Anchored or not p.CanQuery then
				error("unanchored/non-query part: " .. p:GetFullName())
			end
		end
	end)

	it("part count is under 2000", function()
		print(("        (part count: %d)"):format(#parts))
		expect(#parts).toBeGreaterThan(100)
		expect(#parts).toBeLessThan(2000)
	end)

	it("geometry stays inside the outer boundary footprint", function()
		for _, b in boxes do
			if b.min.X < -185 or b.max.X > 185 or b.min.Z < -133 or b.max.Z > 133 or b.min.Y < -8 then
				error("part outside footprint: " .. b.part:GetFullName())
			end
		end
	end)

	it("every spawn has a floor part directly beneath it", function()
		for _, s in allSpawns do
			if not hasFloor(s.CFrame.Position) then
				error("no floor under spawn at " .. tostring(s.CFrame.Position))
			end
		end
	end)

	it("no spawn's character volume overlaps a solid part", function()
		for _, s in allSpawns do
			local hit = blockedBy(s.CFrame.Position)
			if hit then
				error(("spawn at %s overlaps %s"):format(tostring(s.CFrame.Position), hit:GetFullName()))
			end
		end
	end)

	it("floor is continuous across the playable footprint (4-stud grid)", function()
		local floors = {}
		for _, b in boxes do
			if b.part.CanCollide and b.min.Y < 0.01 and b.max.Y >= -3.1 and b.min.Y <= -3 then
				table.insert(floors, b)
			end
		end
		for x = -178, 178, 4 do
			for z = -126, 126, 4 do
				local ok = false
				for _, b in floors do
					if x >= b.min.X and x <= b.max.X and z >= b.min.Z and z <= b.max.Z then
						ok = true
						break
					end
				end
				if not ok then
					error(("hole in floor at (%d, %d)"):format(x, z))
				end
			end
		end
	end)

	it("spawns have no long eye-level sightline into the shared play space", function()
		local worst, where = 0, nil
		for _, list in { sable, talon } do
			for _, s in list do
				local e = spawnExposure(s)
				if e > worst then
					worst, where = e, s.CFrame.Position
				end
			end
		end
		print(("        (worst team-spawn exposure: %.1f studs at %s)"):format(worst, tostring(where)))
		expect(worst).toBeLessThan(40)
	end)
end)

return nil
