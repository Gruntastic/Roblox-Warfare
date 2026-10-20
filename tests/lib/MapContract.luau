-- Shared map contract checks (docs/MAP_CONTRACT.md). Each map spec calls:
--   require("../lib/MapContract")("src/server/Maps/FrostRelay.luau", { id = "FrostRelay", displayName = "Frost Relay" })
local T = require("./T")
local Loader = require("./Loader")

local describe, it, expect = T.describe, T.it, T.expect

type Box = { min: any, max: any, part: any }

local VALID_LIGHTING = {
	Ambient = true, Brightness = true, ClockTime = true, ColorShift_Bottom = true, ColorShift_Top = true,
	EnvironmentDiffuseScale = true, EnvironmentSpecularScale = true, ExposureCompensation = true,
	FogColor = true, FogEnd = true, FogStart = true, GeographicLatitude = true, GlobalShadows = true,
	OutdoorAmbient = true, ShadowSoftness = true,
}
local VALID_ATMOSPHERE = { Density = true, Offset = true, Color = true, Decay = true, Glare = true, Haze = true }

return function(file: string, expected: { id: string, displayName: string })
	local MapModule = Loader.load(file)
	local Vector3 = (Loader.roblox :: any).Vector3

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
	local objectivesFolder = model:FindFirstChild("Objectives")
	local bmin = model:GetAttribute("BoundsMin")
	local bmax = model:GetAttribute("BoundsMax")

	local parts: { any } = {}
	local boxes: { Box } = {}
	local solids: { Box } = {}
	if geometry then
		for _, d in geometry:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
				local b = aabb(d)
				table.insert(boxes, b)
				if d.CanCollide then
					table.insert(solids, b)
				end
			end
		end
	end

	local sable, talon, ffa, allSpawns = {}, {}, {}, {}
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

	local flags, hardpoints, sites, allObjectives = {}, {}, {}, {}
	if objectivesFolder then
		for _, o in objectivesFolder:GetChildren() do
			table.insert(allObjectives, o)
			local kind = o:GetAttribute("Kind")
			if kind == "Flag" then
				flags[o:GetAttribute("Label")] = o
			elseif kind == "Hardpoint" then
				table.insert(hardpoints, o)
			elseif kind == "BombSite" then
				sites[o:GetAttribute("Label")] = o
			end
		end
	end
	table.sort(hardpoints, function(a, b)
		return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0)
	end)

	local function centroid(list: { any })
		local x, y, z = 0, 0, 0
		for _, s in list do
			x += s.CFrame.Position.X
			y += s.CFrame.Position.Y
			z += s.CFrame.Position.Z
		end
		local n = math.max(#list, 1)
		return Vector3.new(x / n, y / n, z / n)
	end

	local function flat(v: any)
		return Vector3.new(v.X, 0, v.Z)
	end

	-- A collidable part whose top is between 0 and 1.5 studs below pos.
	local function hasFloor(pos: any): boolean
		for _, b in solids do
			local drop = pos.Y - b.max.Y
			if drop >= -0.01 and drop <= 1.5 and pos.X >= b.min.X and pos.X <= b.max.X and pos.Z >= b.min.Z and pos.Z <= b.max.Z then
				return true
			end
		end
		return false
	end

	-- Solid part overlapping a character-sized box standing at pos (pos = floor-level centre + 0.5).
	local function blockedBy(pos: any): any?
		local mn = Vector3.new(pos.X - 1, pos.Y - 0.4, pos.Z - 1)
		local mx = Vector3.new(pos.X + 1, pos.Y + 5, pos.Z + 1)
		for _, b in solids do
			if mn.X < b.max.X and mx.X > b.min.X and mn.Y < b.max.Y and mx.Y > b.min.Y and mn.Z < b.max.Z and mx.Z > b.min.Z then
				return b.part
			end
		end
		return nil
	end

	-- Horizontal ray against opaque part AABBs; returns the hit distance or maxT.
	local function castXZ(ox: number, oy: number, oz: number, dx: number, dz: number, maxT: number): number
		local best = maxT
		for _, b in boxes do
			if b.part.Transparency < 0.3 and oy >= b.min.Y and oy <= b.max.Y then
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

	local function zoneStand(o: any): any
		-- standing point at the zone centre, floor level + 0.5 (same convention as spawns)
		local p = o.CFrame.Position
		return Vector3.new(p.X, p.Y - o.Size.Y / 2 + 0.5, p.Z)
	end

	local function checkInvisibleMarker(p: any, what: string)
		if not p:IsA("BasePart") then
			error(what .. " is not a BasePart: " .. p:GetFullName())
		end
		if p.Transparency ~= 1 or not p.Anchored or p.CanCollide or p.CanQuery or p.CanTouch then
			error(what .. " must be invisible, anchored and non-colliding/query/touch: " .. p:GetFullName())
		end
	end

	describe("Map contract: " .. expected.id, function()
		it("exports id, displayName, valid lighting and atmosphere, build", function()
			expect(MapModule.id).toBe(expected.id)
			expect(MapModule.displayName).toBe(expected.displayName)
			expect(type(MapModule.build)).toBe("function")
			for k in MapModule.lighting or {} do
				if not VALID_LIGHTING[k] then
					error("invalid Lighting property " .. tostring(k))
				end
			end
			for k in MapModule.atmosphere or {} do
				if not VALID_ATMOSPHERE[k] then
					error("invalid Atmosphere property " .. tostring(k))
				end
			end
		end)

		it("builds an unparented Model named Map with the required children and attributes", function()
			expect(model.ClassName).toBe("Model")
			expect(model.Name).toBe("Map")
			expect(model.Parent).toBe(nil)
			expect(geometry ~= nil and geometry:IsA("Folder")).toBeTruthy()
			expect(spawnsFolder ~= nil and spawnsFolder:IsA("Folder")).toBeTruthy()
			expect(objectivesFolder ~= nil and objectivesFolder:IsA("Folder")).toBeTruthy()
			local cam = model:FindFirstChild("LobbyCamera")
			expect(cam ~= nil and cam:IsA("BasePart")).toBeTruthy()
			expect(cam.Transparency).toBe(1)
			expect(cam.Anchored).toBe(true)
			expect(cam.CanQuery).toBe(false)
			expect(type(model:GetAttribute("KillY"))).toBe("number")
			expect(typeof(bmin)).toBe("Vector3")
			expect(typeof(bmax)).toBe("Vector3")
			expect(model:GetAttribute("KillY")).toBeLessThan(bmin.Y)
			local base = model:GetAttribute("SnDAttackBase")
			expect(base == "Sable" or base == "Talon").toBeTruthy()
		end)

		it("geometry is anchored, queryable, within bounds, and 300..2500 parts", function()
			print(("        (part count: %d)"):format(#parts))
			expect(#parts).toBeAtLeast(300)
			expect(#parts).toBeLessThan(2500)
			for _, b in boxes do
				local p = b.part
				if not p.Anchored or not p.CanQuery then
					error("unanchored/non-query part: " .. p:GetFullName())
				end
				if b.min.X < bmin.X - 2 or b.max.X > bmax.X + 2 or b.min.Z < bmin.Z - 2 or b.max.Z > bmax.Z + 2 or b.min.Y < bmin.Y - 2 then
					error("part outside BoundsMin/BoundsMax: " .. p:GetFullName() .. " " .. tostring(p.CFrame.Position))
				end
			end
		end)

		it("ground covers the whole footprint (no holes to the void, 6-stud grid)", function()
			local ground = {}
			for _, b in solids do
				if b.min.Y <= bmin.Y + 2 then
					table.insert(ground, b)
				end
			end
			for x = bmin.X + 3, bmax.X - 3, 6 do
				for z = bmin.Z + 3, bmax.Z - 3, 6 do
					local ok = false
					for _, b in ground do
						if x >= b.min.X and x <= b.max.X and z >= b.min.Z and z <= b.max.Z then
							ok = true
							break
						end
					end
					if not ok then
						error(("hole in ground at (%.0f, %.0f)"):format(x, z))
					end
				end
			end
		end)

		it("spawn counts and properties", function()
			expect(#sable).toBeAtLeast(8)
			expect(#talon).toBeAtLeast(8)
			expect(#ffa).toBeAtLeast(16)
			for _, s in allSpawns do
				checkInvisibleMarker(s, "spawn")
				expect(s.Size.X).toBeNear(2)
				expect(s.Size.Y).toBeNear(1)
				expect(s.Size.Z).toBeNear(2)
				if math.abs(s.CFrame.LookVector.Y) > 0.01 then
					error("spawn look vector is not horizontal at " .. tostring(s.CFrame.Position))
				end
			end
		end)

		it("team bases are far apart", function()
			local span = math.max(bmax.X - bmin.X, bmax.Z - bmin.Z)
			local sep = (flat(centroid(sable)) - flat(centroid(talon))).Magnitude
			expect(sep).toBeAtLeast(math.min(150, span * 0.6))
			local minD = math.huge
			for _, t in talon do
				for _, s in sable do
					minD = math.min(minD, (t.CFrame.Position - s.CFrame.Position).Magnitude)
				end
			end
			expect(minD).toBeAtLeast(math.min(100, span * 0.45))
		end)

		it("team spawns face into the map", function()
			local mid = flat(centroid(sable) + centroid(talon)) / 2
			for _, list in { sable, talon } do
				for _, s in list do
					local toMid = (mid - flat(s.CFrame.Position)).Unit
					if s.CFrame.LookVector:Dot(toMid) < 0 then
						error("team spawn faces away from the map at " .. tostring(s.CFrame.Position))
					end
				end
			end
		end)

		it("FFA spawns are pairwise >= 20 studs apart", function()
			for i = 1, #ffa do
				for j = i + 1, #ffa do
					local d = (ffa[i].CFrame.Position - ffa[j].CFrame.Position).Magnitude
					if d < 20 then
						error(("FFA spawns %s and %s are %.1f apart"):format(tostring(ffa[i].CFrame.Position), tostring(ffa[j].CFrame.Position), d))
					end
				end
			end
		end)

		it("every spawn stands on a floor with headroom", function()
			for _, s in allSpawns do
				local pos = s.CFrame.Position
				if not hasFloor(pos) then
					error("no floor under spawn at " .. tostring(pos))
				end
				local hit = blockedBy(pos)
				if hit then
					error(("spawn at %s overlaps %s"):format(tostring(pos), hit:GetFullName()))
				end
			end
		end)

		it("team spawns open onto at least 8 studs of space ahead", function()
			-- the first view after spawning should not be a wall in your face
			local bad = {}
			for _, list in { sable, talon } do
				for _, s in list do
					local pos = s.CFrame.Position
					local look = s.CFrame.LookVector
					local d = castXZ(pos.X, pos.Y + 4.5, pos.Z, look.X, look.Z, 8)
					if d < 8 then
						table.insert(bad, ("%s (%.1f)"):format(tostring(pos), d))
					end
				end
			end
			if #bad > 0 then
				error("team spawns facing a wall: " .. table.concat(bad, "; "))
			end
		end)

		it("team spawns have no eye-level sightline towards the enemy longer than 120 studs", function()
			-- Only rays within 60 degrees of the direction to the enemy base count: those are the lines
			-- an enemy could use to fire into the spawn.
			local worst, where = 0, nil
			local cs, ct = flat(centroid(sable)), flat(centroid(talon))
			for _, list in { sable, talon } do
				local enemyDir = if list == sable then (ct - cs).Unit else (cs - ct).Unit
				for _, s in list do
					local pos = s.CFrame.Position
					for i = 0, 71 do
						local a = (i / 72) * math.pi * 2
						local dx, dz = math.cos(a), math.sin(a)
						if dx * enemyDir.X + dz * enemyDir.Z >= 0.5 then
							local d = castXZ(pos.X, pos.Y + 4.5, pos.Z, dx, dz, 1000)
							if d > worst then
								worst, where = d, pos
							end
						end
					end
				end
			end
			print(("        (longest team-spawn sightline: %.1f studs at %s)"):format(worst, tostring(where)))
			expect(worst).toBeLessThan(120)
		end)

		it("objective markers are invisible boxes sitting on a floor", function()
			expect(#allObjectives).toBeGreaterThan(0)
			for _, o in allObjectives do
				checkInvisibleMarker(o, "objective")
				if math.abs(o.CFrame.UpVector.Y - 1) > 1e-3 then
					error("objective rotated off the Y axis: " .. o.Name)
				end
				if o.Size.Y < 8 then
					error("objective Size.Y < 8: " .. o.Name)
				end
				local stand = zoneStand(o)
				if not hasFloor(stand) then
					error("no floor under the centre of objective " .. o.Name .. " at " .. tostring(stand))
				end
				local hit = blockedBy(stand)
				if hit then
					error(("objective %s centre is blocked by %s"):format(o.Name, hit:GetFullName()))
				end
			end
		end)

		it("Domination: flags A, B, C placed by base", function()
			local a, b, c = flags.A, flags.B, flags.C
			expect(a ~= nil and b ~= nil and c ~= nil).toBeTruthy()
			local cs, ct = flat(centroid(sable)), flat(centroid(talon))
			local sep = (cs - ct).Magnitude
			local function d(o, p)
				return (flat(o.CFrame.Position) - p).Magnitude
			end
			expect(d(a, cs)).toBeLessThan(d(a, ct))
			expect(d(c, ct)).toBeLessThan(d(c, cs))
			expect(math.abs(d(b, cs) - d(b, ct))).toBeLessThan(sep * 0.25 + 1e-6)
			for _, f in { a, b, c } do
				local w = math.min(f.Size.X, f.Size.Z)
				local l = math.max(f.Size.X, f.Size.Z)
				if w < 14 - 1e-6 or l > 22 + 1e-6 then
					error(("flag %s must be 14..22 studs across, got %.1f x %.1f"):format(f.Name, f.Size.X, f.Size.Z))
				end
			end
		end)

		it("Hardpoint: 4..6 zones in order, spaced out, away from spawns", function()
			expect(#hardpoints).toBeAtLeast(4)
			expect(#hardpoints <= 6).toBeTruthy()
			for i, h in hardpoints do
				expect(h:GetAttribute("Order")).toBe(i)
				local w = math.min(h.Size.X, h.Size.Z)
				local l = math.max(h.Size.X, h.Size.Z)
				if w < 16 - 1e-6 or l > 30 + 1e-6 then
					error(("hardpoint %d must be 16..30 studs across"):format(i))
				end
				local nextH = hardpoints[i % #hardpoints + 1]
				local gap = (flat(h.CFrame.Position) - flat(nextH.CFrame.Position)).Magnitude
				if gap < 40 then
					error(("hardpoints %d and %d are only %.1f apart"):format(i, nextH:GetAttribute("Order"), gap))
				end
				for _, list in { sable, talon } do
					for _, s in list do
						if (flat(s.CFrame.Position) - flat(h.CFrame.Position)).Magnitude < 40 then
							error(("hardpoint %d is within 40 studs of a team spawn"):format(i))
						end
					end
				end
			end
		end)

		it("S&D: bomb sites A and B on the defenders' side, 50+ apart", function()
			local a, b = sites.A, sites.B
			expect(a ~= nil and b ~= nil).toBeTruthy()
			local attack = model:GetAttribute("SnDAttackBase")
			local atk = flat(centroid(if attack == "Sable" then sable else talon))
			local def = flat(centroid(if attack == "Sable" then talon else sable))
			for _, site in { a, b } do
				local p = flat(site.CFrame.Position)
				if (p - def).Magnitude >= (p - atk).Magnitude then
					error("bomb site " .. site.Name .. " is not on the defenders' side")
				end
				local w = math.min(site.Size.X, site.Size.Z)
				local l = math.max(site.Size.X, site.Size.Z)
				if w < 10 - 1e-6 or l > 16 + 1e-6 then
					error("bomb site " .. site.Name .. " must be 10..16 studs across")
				end
			end
			expect((flat(a.CFrame.Position) - flat(b.CFrame.Position)).Magnitude).toBeAtLeast(50)
		end)
	end)
end
