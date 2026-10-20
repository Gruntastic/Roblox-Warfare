--!strict
--[[
	Ashwood Estate: a wooded country estate in autumn, at golden hour.
	Medium 6v6 map, ~360 x 260 studs playable (boundary inner faces at X = +-180, Z = +-130).

	Axes: +X = east, -Z = north (top of the ASCII sketch in docs/maps/AshwoodEstate.md).
	All walkable ground has its top surface at Y = 0 (ground slabs Y -4..0, BoundsMin.Y = -4),
	except the manor's upper floor and galleries (Y 14).

	Bands, north -> south (shared play space X -122..122):
	  Z -130..-112  Woodland walk (north flank: trees, fallen logs; behind the brick garden wall)
	  Z -110.. -40  Gardens (north lane): fountain parterre (W), copper-beech hedge maze (C),
	                greenhouse (E)
	  Z  -40..  40  Manor house (middle lane): great hall with grand stairs and galleries (Y 14),
	                library (W wing), dining room (E wing), bedrooms / long gallery upstairs;
	                stone terraces either side
	  Z   40.. 110  Orchard (W, stone walled), cart track (C), carriage house + paddock (E)
	                (south lane)
	  Z  112.. 130  Kitchen walk (south flank: cold frames, woodpiles, potting shed)
	Sable spawn = gatehouse court (X < -122), Talon spawn = stable court (X > 122). Each base is
	closed by a 14-tall estate wall with five fenced gaps and spawn-side baffles; the centre gap
	is the arch of the gatehouse (Sable) / clock arch (Talon).

	build() only uses Instance.new / Vector3 / CFrame / Color3 / Enum so it also runs under Lune.
]]

type Style = {
	mat: Enum.Material,
	color: Color3,
	transparency: number?,
	collide: boolean?,
}

local function style(mat: Enum.Material, r: number, g: number, b: number, transparency: number?): Style
	return { mat = mat, color = Color3.fromRGB(r, g, b), transparency = transparency }
end

-- Same look, but not collidable (foliage canopies, light fittings): still blocks bullets and sight.
local function soft(st: Style): Style
	return { mat = st.mat, color = st.color, transparency = st.transparency, collide = false }
end

local M = Enum.Material

-- Autumn golden-hour palette.
local P = {
	brick = style(M.Brick, 156, 84, 62),
	brickDark = style(M.Brick, 118, 62, 48),
	cobble = style(M.Cobblestone, 150, 140, 124),
	cobbleWarm = style(M.Cobblestone, 170, 150, 120),
	cobbleDark = style(M.Cobblestone, 112, 106, 98),
	stone = style(M.Limestone, 206, 192, 164),
	marble = style(M.Marble, 222, 214, 198),
	slate = style(M.Slate, 74, 78, 86),
	slateDark = style(M.Slate, 56, 58, 64),
	planks = style(M.WoodPlanks, 136, 96, 62),
	planksDark = style(M.WoodPlanks, 92, 62, 42),
	floor = style(M.WoodPlanks, 120, 80, 50),
	wood = style(M.Wood, 104, 72, 48),
	bark = style(M.Wood, 82, 62, 48),
	paintWhite = style(M.WoodPlanks, 226, 220, 204),
	grass = style(M.Grass, 118, 124, 62),
	grassDry = style(M.Grass, 150, 136, 74),
	woodFloor = style(M.LeafyGrass, 120, 92, 50),
	path = style(M.Ground, 128, 104, 76),
	hedge = style(M.LeafyGrass, 150, 82, 38), -- copper beech
	boxHedge = style(M.LeafyGrass, 92, 100, 50),
	leafOrange = style(M.LeafyGrass, 214, 120, 40),
	leafRed = style(M.LeafyGrass, 176, 58, 36),
	leafGold = style(M.LeafyGrass, 222, 168, 60),
	glass = style(M.Glass, 196, 214, 206, 0.6),
	water = style(M.SmoothPlastic, 70, 104, 110),
	fabric = style(M.Fabric, 118, 40, 42),
	fabricGreen = style(M.Fabric, 56, 84, 62),
	books = style(M.Fabric, 112, 66, 50),
	hay = style(M.Grass, 206, 170, 92),
	iron = style(M.Metal, 54, 52, 50),
	lamp = style(M.Neon, 255, 196, 128),
	sable = style(M.SmoothPlastic, 52, 74, 96),
	talon = style(M.SmoothPlastic, 176, 96, 40),
}

local MapModule = {}

MapModule.id = "AshwoodEstate"
MapModule.displayName = "Ashwood Estate"

-- Low warm sun through autumn haze. Only valid Lighting properties.
MapModule.lighting = {
	ClockTime = 17.5,
	GeographicLatitude = 51,
	Brightness = 2.4,
	ExposureCompensation = 0.15,
	Ambient = Color3.fromRGB(104, 84, 72),
	OutdoorAmbient = Color3.fromRGB(150, 118, 92),
	ColorShift_Top = Color3.fromRGB(255, 186, 120),
	ColorShift_Bottom = Color3.fromRGB(92, 64, 52),
	EnvironmentDiffuseScale = 0.5,
	EnvironmentSpecularScale = 0.3,
	ShadowSoftness = 0.3,
	GlobalShadows = true,
	FogColor = Color3.fromRGB(226, 170, 116),
	FogStart = 300,
	FogEnd = 1500,
}

-- Valid Atmosphere properties.
MapModule.atmosphere = {
	Density = 0.3,
	Offset = 0.15,
	Color = Color3.fromRGB(232, 182, 130),
	Decay = Color3.fromRGB(150, 98, 72),
	Glare = 0.6,
	Haze = 1.6,
}

MapModule.killY = -30

local BOUNDS_MIN = Vector3.new(-184, -4, -134)
local BOUNDS_MAX = Vector3.new(184, 60, 134)

-- Estate wall (spawn screen) gap layout, Z ranges: N flank, N lane, centre arch, S lane, S flank.
local SCREEN_X = 122
local GAPS = { { -124, -114 }, { -80, -70 }, { -6, 6 }, { 66, 76 }, { 114, 124 } }

-- Manor storey heights.
local FLOOR2 = 14 -- upper floor top
local EAVES = 27 -- top of the outer walls

function MapModule.build(): Model
	local model = Instance.new("Model")
	model.Name = "Map"

	local geometry = Instance.new("Folder")
	geometry.Name = "Geometry"
	geometry.Parent = model

	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = model

	local objectives = Instance.new("Folder")
	objectives.Name = "Objectives"
	objectives.Parent = model

	local folder: Instance = geometry
	local function section(name: string)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = geometry
		folder = f
	end

	local function finish(p: BasePart, st: Style, name: string?)
		p.Anchored = true
		p.CanQuery = true
		p.CanCollide = if st.collide == nil then true else st.collide
		p.Material = st.mat
		p.Color = st.color
		p.Transparency = st.transparency or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Name = name or "Part"
		p.Parent = folder
	end

	-- Axis-aligned block from two opposite corners (any order).
	local function blk(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, st: Style, name: string?): Part
		local p = Instance.new("Part")
		p.Size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
		p.CFrame = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
		finish(p, st, name)
		return p
	end

	-- Oriented block.
	local function box(cf: CFrame, size: Vector3, st: Style, name: string?): Part
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = cf
		finish(p, st, name)
		return p
	end

	local function wedge(cf: CFrame, size: Vector3, st: Style, name: string?): WedgePart
		local p = Instance.new("WedgePart")
		p.Size = size
		p.CFrame = cf
		finish(p, st, name)
		return p
	end

	-- Vertical cylinder (post, trunk, urn, column).
	local function cylY(x: number, y0: number, z: number, y1: number, d: number, st: Style, name: string?): Part
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(y1 - y0, d, d)
		p.CFrame = CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
		finish(p, st, name)
		return p
	end

	-- Horizontal cylinder along X (logs) or Z (wheels on an X-facing axle).
	local function cylH(cx: number, cy: number, cz: number, len: number, d: number, alongZ: boolean, st: Style, name: string?): Part
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(len, d, d)
		p.CFrame = if alongZ
			then CFrame.new(cx, cy, cz) * CFrame.Angles(0, math.pi / 2, 0)
			else CFrame.new(cx, cy, cz)
		finish(p, st, name)
		return p
	end

	type Opening = { number } -- { a0, a1, y0, y1 } along-wall range and vertical range

	-- Wall running along X (alongZ = false) or Z (alongZ = true), with rectangular openings.
	-- a0..a1 is the extent along the wall, c0..c1 its thickness on the other horizontal axis.
	local function wall(alongZ: boolean, a0: number, a1: number, c0: number, c1: number, y0: number, y1: number, openings: { Opening }, st: Style, name: string?)
		local function piece(p0: number, p1: number, q0: number, q1: number)
			if p1 - p0 < 0.01 or q1 - q0 < 0.01 then
				return
			end
			if alongZ then
				blk(c0, q0, p0, c1, q1, p1, st, name)
			else
				blk(p0, q0, c0, p1, q1, c1, st, name)
			end
		end
		local lo, hi = math.min(a0, a1), math.max(a0, a1)
		local sorted = table.clone(openings)
		table.sort(sorted, function(a: Opening, b: Opening)
			return math.min(a[1], a[2]) < math.min(b[1], b[2])
		end)
		local cursor = lo
		for _, o in sorted do
			local oa, ob = math.min(o[1], o[2]), math.max(o[1], o[2])
			piece(cursor, oa, y0, y1)
			piece(oa, ob, y0, math.max(y0, o[3]))
			piece(oa, ob, math.min(y1, o[4]), y1)
			cursor = ob
		end
		piece(cursor, hi, y0, y1)
	end

	-- Solid stairs. Rises from baseY at the low end to topY at the high end in `dir`.
	-- dir: "+X" | "-X" | "+Z" | "-Z". Footprint x0..x1, z0..z1. Each step rise <= 1 stud.
	local function stairs(x0: number, z0: number, x1: number, z1: number, dir: string, baseY: number, topY: number, st: Style)
		local xa, xb = math.min(x0, x1), math.max(x0, x1)
		local za, zb = math.min(z0, z1), math.max(z0, z1)
		local rise = topY - baseY
		local n = math.ceil(rise - 1e-6)
		local alongX = dir == "+X" or dir == "-X"
		local len = if alongX then xb - xa else zb - za
		local run = len / n
		for i = 1, n do
			local top = baseY + rise * i / n
			local s0 = (i - 1) * run
			if dir == "+X" then
				blk(xa + s0, baseY, za, xb, top, zb, st, "Step")
			elseif dir == "-X" then
				blk(xa, baseY, za, xb - s0, top, zb, st, "Step")
			elseif dir == "+Z" then
				blk(xa, baseY, za + s0, xb, top, zb, st, "Step")
			else
				blk(xa, baseY, za, xb, top, zb - s0, st, "Step")
			end
		end
	end

	-- Props --------------------------------------------------------------------------------

	local function crate(x: number, y: number, z: number, s: number, yaw: number?)
		box(CFrame.new(x, y + s / 2, z) * CFrame.Angles(0, yaw or 0, 0), Vector3.new(s, s, s), P.planks, "Crate")
	end

	-- Tree: collidable trunk, two non-collidable canopy blocks starting well above head height.
	local function tree(x: number, z: number, h: number, leafA: Style, leafB: Style, r: number?)
		local rr = r or 5
		cylY(x, 0, z, h + 1, 2.2, P.bark, "Trunk")
		blk(x - rr, h - 1, z - rr, x + rr, h + 4, z + rr, soft(leafA), "Canopy")
		box(CFrame.new(x + 0.8, h + 4.5, z - 0.6) * CFrame.Angles(0, 0.7, 0), Vector3.new(rr * 1.3, 3.5, rr * 1.3), soft(leafB), "Canopy")
	end

	-- Bench of length len along X or Z with a centre back rail, standing on floor y (default 0).
	local function bench(x: number, z: number, len: number, alongZ: boolean, st: Style?, y: number?)
		local s = st or P.wood
		local y0 = y or 0
		local hx, hz = if alongZ then 0.9 else len / 2, if alongZ then len / 2 else 0.9
		blk(x - hx, y0, z - hz, x + hx, y0 + 1.6, z + hz, s, "Bench")
		local bx, bz = if alongZ then 0.25 else len / 2, if alongZ then len / 2 else 0.25
		blk(x - bx, y0 + 1.6, z - bz, x + bx, y0 + 3.4, z + bz, s, "BenchBack")
	end

	-- Stone urn on a plinth (5 tall total): crouch-to-standing cover.
	local function urn(x: number, z: number)
		blk(x - 1.6, 0, z - 1.6, x + 1.6, 3, z + 1.6, P.stone, "UrnPlinth")
		cylY(x, 3, z, 5, 2.4, P.stone, "Urn")
		cylY(x, 5, z, 5.6, 1.6, soft(P.leafRed), "UrnPlanting")
	end

	-- Statue on a plinth (blocks the line it stands on).
	local function statue(x: number, z: number)
		-- plinth 8.1 tall: too tall to jump onto
		blk(x - 2.5, 0, z - 2.5, x + 2.5, 7.5, z + 2.5, P.stone, "StatuePlinth")
		blk(x - 2.8, 7.5, z - 2.8, x + 2.8, 8.1, z + 2.8, P.marble, "StatueCap")
		blk(x - 0.9, 8.1, z - 0.7, x + 0.9, 13, z + 0.7, P.marble, "Statue")
		blk(x - 0.6, 13, z - 0.6, x + 0.6, 14.3, z + 0.6, P.marble, "StatueHead")
	end

	local function lampPost(x: number, z: number, h: number)
		cylY(x, 0, z, h, 0.6, P.iron, "LampPost")
		blk(x - 0.6, h, z - 0.6, x + 0.6, h + 1.4, z + 0.6, P.lamp, "Lantern")
		blk(x - 0.8, h + 1.4, z - 0.8, x + 0.8, h + 1.8, z + 0.8, P.iron, "LanternCap")
	end

	-- Round hay bale lying along X or Z.
	local function bale(x: number, z: number, alongZ: boolean)
		cylH(x, 1.8, z, 3, 3.6, alongZ, P.hay, "HayBale")
	end

	-- Square hay bales: a stack of n (each 4 x 2 x 2.4).
	local function hayStack(x: number, z: number, n: number, alongZ: boolean)
		for i = 0, n - 1 do
			local sx, sz = if alongZ then 2.4 else 4, if alongZ then 4 else 2.4
			local ox = if alongZ then 0 else (i % 2) * 0.6
			blk(x - sx / 2 + ox, i * 2, z - sz / 2, x + sx / 2 + ox, i * 2 + 2, z + sz / 2, P.hay, "Hay")
		end
	end

	-- Horse-drawn carriage (body + 4 wheels + shafts), long axis along X before yaw.
	local function carriage(x: number, z: number, yaw: number, st: Style)
		local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
		box(base * CFrame.new(0, 4, 0), Vector3.new(8, 4, 4.6), st, "CarriageBody")
		box(base * CFrame.new(0, 6.3, 0), Vector3.new(8.6, 0.6, 5.2), P.planksDark, "CarriageRoof")
		for _, w in { { -3, -2.7 }, { 3, -2.7 }, { -3, 2.7 }, { 3, 2.7 } } do
			local p = Instance.new("Part")
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(0.5, 3.6, 3.6)
			p.CFrame = base * CFrame.new(w[1], 1.8, w[2]) * CFrame.Angles(0, math.pi / 2, 0)
			finish(p, P.planksDark, "Wheel")
		end
		box(base * CFrame.new(-7.5, 2.2, 0), Vector3.new(7, 0.4, 3.6), P.wood, "Shafts")
	end

	-- Post-and-rail fence along X or Z at coordinate c, from a0..a1, skipping gate ranges.
	local function fence(alongZ: boolean, a0: number, a1: number, c: number, gates: { { number } })
		local cursor = a0
		local segs: { { number } } = {}
		for _, g in gates do
			table.insert(segs, { cursor, g[1] })
			cursor = g[2]
		end
		table.insert(segs, { cursor, a1 })
		for _, sg in segs do
			local s0, s1 = sg[1], sg[2]
			if s1 - s0 > 0.5 then
				for _, y in { 1.6, 3.2 } do
					if alongZ then
						blk(c - 0.2, y, s0, c + 0.2, y + 0.4, s1, P.planks, "FenceRail")
					else
						blk(s0, y, c - 0.2, s1, y + 0.4, c + 0.2, P.planks, "FenceRail")
					end
				end
				local n = math.max(1, math.floor((s1 - s0) / 10 + 0.5))
				for i = 0, n do
					local a = s0 + (s1 - s0) * i / n
					if alongZ then
						blk(c - 0.35, 0, a - 0.35, c + 0.35, 4, a + 0.35, P.wood, "FencePost")
					else
						blk(a - 0.35, 0, c - 0.35, a + 0.35, 4, c + 0.35, P.wood, "FencePost")
					end
				end
			end
		end
	end

	-- Topiary: a clipped yew column (8 tall, too tall to jump onto) with a gold crown.
	local function topiary(x: number, z: number)
		blk(x - 2, 0, z - 2, x + 2, 8, z + 2, P.boxHedge, "Topiary")
		blk(x - 1.2, 8, z - 1.2, x + 1.2, 10, z + 1.2, soft(P.leafGold), "TopiaryCrown")
	end

	-------------------------------------------------------------------------------------------
	-- Ground (all tops at Y = 0, bottoms at Y = -4). Pieces abut exactly: no gaps.
	-------------------------------------------------------------------------------------------
	section("Ground")
	blk(-184, -4, -134, -SCREEN_X, 0, 134, P.cobbleWarm, "GatehouseCourt")
	blk(SCREEN_X, -4, -134, 184, 0, 134, P.cobble, "StableCourt")
	blk(-SCREEN_X, -4, -134, SCREEN_X, 0, -110, P.woodFloor, "WoodlandFloor")
	blk(-SCREEN_X, -4, -110, SCREEN_X, 0, -40, P.grass, "GardenLawn")
	blk(-SCREEN_X, -4, -40, -66, 0, 40, P.cobble, "TerraceWest")
	blk(66, -4, -40, SCREEN_X, 0, 40, P.cobble, "TerraceEast")
	blk(-66, -4, -40, 66, 0, -30, P.cobble, "TerraceNorth")
	blk(-66, -4, 30, 66, 0, 40, P.cobble, "TerraceSouth")
	blk(-66, -4, -30, 66, 0, 30, P.floor, "ManorFloor")
	blk(-SCREEN_X, -4, 40, 0, 0, 112, P.grassDry, "OrchardGround")
	blk(0, -4, 40, SCREEN_X, 0, 112, P.cobbleDark, "StableYardGround")
	blk(-SCREEN_X, -4, 112, SCREEN_X, 0, 134, P.path, "KitchenWalk")
	-- gravel drives from each arch to the terraces (0.06 thick, walkable)
	blk(-SCREEN_X, 0, -6, -66, 0.06, 6, P.cobbleWarm, "Drive")
	blk(66, 0, -6, SCREEN_X, 0.06, 6, P.cobbleWarm, "Drive")
	-- great hall rug
	blk(-12, 0, -10, 12, 0.06, 10, P.fabric, "HallRug")

	-------------------------------------------------------------------------------------------
	-- Boundary: estate wall (cobble base, brick upper) with a woodland edge beyond.
	-------------------------------------------------------------------------------------------
	section("Boundary")
	blk(-184, -4, -134, 184, 14, -130, P.cobbleDark, "BoundaryN")
	blk(-184, 14, -134, 184, 26, -130, P.brickDark, "BoundaryN")
	blk(-184, -4, 130, 184, 14, 134, P.cobbleDark, "BoundaryS")
	blk(-184, 14, 130, 184, 26, 134, P.brickDark, "BoundaryS")
	blk(-184, -4, -130, -180, 14, 130, P.cobbleDark, "BoundaryW")
	blk(-184, 14, -130, -180, 26, 130, P.brickDark, "BoundaryW")
	blk(180, -4, -130, 184, 14, 130, P.cobbleDark, "BoundaryE")
	blk(180, 14, -130, 184, 26, 130, P.brickDark, "BoundaryE")
	for x = -160, 160, 40 do
		blk(x - 1.5, 0, -130, x + 1.5, 27, -128.8, P.cobble, "Buttress")
		blk(x - 1.5, 0, 128.8, x + 1.5, 27, 130, P.cobble, "Buttress")
	end
	-- treetops peeking over the boundary (non-collidable, above the wall)
	for x = -170, 170, 34 do
		local st = if (x // 34) % 2 == 0 then P.leafOrange else P.leafRed
		blk(x - 8, 22, -134, x + 8, 34, -130, soft(st), "BoundaryTrees")
		blk(x - 8, 22, 130, x + 8, 32, 134, soft(if st == P.leafRed then P.leafGold else P.leafRed), "BoundaryTrees")
	end

	-------------------------------------------------------------------------------------------
	-- Garden walls: brick walls (9 tall) between the gardens and the woodland walk, and
	-- between the orchard / stable yard and the kitchen walk.
	-------------------------------------------------------------------------------------------
	section("GardenWalls")
	local flankGapsN: { Opening } = { { -100, -92, 0, 10 }, { -46, -38, 0, 10 }, { 38, 46, 0, 10 }, { 92, 100, 0, 10 } }
	local flankGapsS: { Opening } = { { -80, -72, 0, 10 }, { -36, -28, 0, 10 }, { 28, 36, 0, 10 }, { 80, 88, 0, 10 } }
	wall(false, -121, 121, -112, -110, 0, 9, flankGapsN, P.brick, "GardenWallN")
	blk(-121, 9, -112.3, 121, 9.5, -109.7, P.cobble, "WallCap")
	wall(false, -121, 121, 110, 112, 0, 9, flankGapsS, P.brick, "GardenWallS")
	blk(-121, 9, 109.7, 121, 9.5, 112.3, P.cobble, "WallCap")
	for _, g in flankGapsN do
		for _, x in { g[1] - 1, g[2] + 1 } do
			blk(x - 1, 0, -112.5, x + 1, 11, -109.5, P.cobble, "GatePier")
		end
	end
	for _, g in flankGapsS do
		for _, x in { g[1] - 1, g[2] + 1 } do
			blk(x - 1, 0, 109.5, x + 1, 11, 112.5, P.cobble, "GatePier")
		end
	end

	-------------------------------------------------------------------------------------------
	-- Woodland walk (north flank, Z -130..-112).
	-------------------------------------------------------------------------------------------
	section("WoodlandWalk")
	local wood = {
		{ -104, -124 }, { -82, -117 }, { -60, -125 }, { -26, -118 }, { 2, -125 },
		{ 24, -117 }, { 58, -124 }, { 82, -117 }, { 106, -125 },
	}
	for i, t in wood do
		tree(t[1], t[2], 11 + (i % 3), if i % 2 == 0 then P.leafRed else P.leafOrange, P.leafGold, 5)
	end
	-- fallen logs and rocks: cover every ~20 studs along the walk
	cylH(-92, 1.5, -120.5, 10, 3, false, P.bark, "FallenLog")
	cylH(-44, 1.5, -126, 9, 3, false, P.bark, "FallenLog")
	cylH(-12, 1.5, -116, 9, 3, false, P.bark, "FallenLog")
	cylH(40, 1.5, -121, 10, 3, false, P.bark, "FallenLog")
	cylH(70, 1.5, -127, 8, 3, false, P.bark, "FallenLog")
	box(CFrame.new(-70, 1.5, -116) * CFrame.Angles(0, 0.4, 0), Vector3.new(5, 3, 4), P.cobbleDark, "Rock")
	box(CFrame.new(12, 1.8, -128) * CFrame.Angles(0, -0.3, 0), Vector3.new(6, 3.6, 3), P.cobbleDark, "Rock")
	box(CFrame.new(96, 1.5, -121) * CFrame.Angles(0, 0.8, 0), Vector3.new(4, 3, 4), P.cobbleDark, "Rock")
	-- leaf litter drifts (walkable, thin)
	for _, x in { -96, -30, 30, 92 } do
		blk(x - 7, 0, -129, x + 7, 0.2, -123, P.leafOrange, "LeafLitter")
	end

	-------------------------------------------------------------------------------------------
	-- Gardens, west: fountain parterre (X -112..-40, Z -108..-48).
	-------------------------------------------------------------------------------------------
	section("Parterre")
	local FX, FZ = -78, -76
	cylY(FX, 0, FZ, 2.5, 18, P.stone, "FountainBasin")
	cylY(FX, 2.5, FZ, 2.6, 16, P.water, "FountainWater")
	-- bowl at Y 10: 7.4 above the basin rim, out of jump reach
	cylY(FX, 2.6, FZ, 10, 2.4, P.marble, "FountainColumn")
	cylY(FX, 10, FZ, 11, 7, P.marble, "FountainBowl")
	cylY(FX, 11, FZ, 13, 1.2, P.marble, "FountainFinial")
	-- clipped box-hedge beds (3 tall: crouch cover)
	for _, b in {
		{ -104, -102, -92, -96 }, { -64, -102, -52, -96 }, { -104, -56, -92, -50 }, { -64, -56, -52, -50 },
		{ -107, -94, -101, -84 }, { -107, -66, -101, -56 },
	} do
		blk(b[1], 0, b[2], b[3], 3, b[4], P.boxHedge, "BoxHedge")
		blk(b[1] + 0.6, 3, b[2] + 0.6, b[3] - 0.6, 3.4, b[4] - 0.6, P.leafRed, "BedFlowers")
	end
	topiary(-58, -84)
	topiary(-58, -66)
	topiary(-96, -76)
	bench(-78, -94, 8, false, P.stone)
	bench(-78, -58, 8, false, P.stone)
	tree(-108, -102, 12, P.leafGold, P.leafOrange, 5)
	tree(-48, -104, 11, P.leafRed, P.leafOrange, 4)

	-------------------------------------------------------------------------------------------
	-- Gardens, centre: copper-beech hedge maze (X -40..40, Z -100..-48). Hedges 8 tall.
	-------------------------------------------------------------------------------------------
	section("HedgeMaze")
	local HH = 8
	wall(false, -40, 40, -100, -98, 0, HH, { { 20, 28, 0, 10 } }, P.hedge, "MazeHedge")
	wall(false, -40, 40, -50, -48, 0, HH, { { -28, -20, 0, 10 } }, P.hedge, "MazeHedge")
	wall(true, -98, -50, -40, -38, 0, HH, { { -90, -82, 0, 10 } }, P.hedge, "MazeHedge")
	wall(true, -98, -50, 38, 40, 0, HH, { { -66, -58, 0, 10 } }, P.hedge, "MazeHedge")
	wall(false, -22, 22, -84, -82, 0, HH, { { -16, -8, 0, 10 } }, P.hedge, "MazeHedge")
	wall(false, -22, 22, -66, -64, 0, HH, { { 8, 16, 0, 10 } }, P.hedge, "MazeHedge")
	wall(true, -82, -66, -22, -20, 0, HH, { { -78, -70, 0, 10 } }, P.hedge, "MazeHedge")
	wall(true, -82, -66, 20, 22, 0, HH, { { -78, -70, 0, 10 } }, P.hedge, "MazeHedge")
	-- spurs that turn the ring corridors into a loop with dead-end pockets
	blk(-30, 0, -98, -28, HH, -92, P.hedge, "MazeSpur")
	blk(28, 0, -56, 30, HH, -50, P.hedge, "MazeSpur")
	blk(-38, 0, -75, -30, HH, -73, P.hedge, "MazeSpur")
	blk(30, 0, -75, 38, HH, -73, P.hedge, "MazeSpur")
	-- maze centre: armillary on a plinth, two stone benches
	blk(-1, 0, -71, 1, 3, -69, P.stone, "ArmillaryPlinth")
	cylY(0, 3, -70, 4.6, 1.6, P.iron, "Armillary")
	bench(-14, -74, 6, true, P.stone)
	bench(14, -74, 6, true, P.stone)
	-- leaf-red tops on the outer ring corners (silhouette)
	for _, c in { { -40, -100 }, { 38, -100 }, { -40, -50 }, { 38, -50 } } do
		blk(c[1], HH, c[2], c[1] + 2, HH + 1.5, c[2] + 2, P.leafRed, "HedgeFinial")
	end

	-------------------------------------------------------------------------------------------
	-- Gardens, east: greenhouse (X 56..104, Z -96..-56). Glass is transparent but collidable.
	-------------------------------------------------------------------------------------------
	section("Greenhouse")
	local GX0, GX1, GZ0, GZ1 = 56, 104, -96, -56
	local PL = 2.5 -- brick plinth height
	local GH = 12 -- glass wall top
	local ghN: { Opening } = {}
	local ghS: { Opening } = { { 76, 84, 0, 10 } }
	local ghW: { Opening } = { { -84, -76, 0, 10 } }
	local ghE: { Opening } = { { -80, -72, 0, 10 } }
	wall(false, GX0, GX1, GZ0, GZ0 + 1, 0, PL, ghN, P.brick, "GreenhousePlinth")
	wall(false, GX0, GX1, GZ1 - 1, GZ1, 0, PL, ghS, P.brick, "GreenhousePlinth")
	wall(true, GZ0 + 1, GZ1 - 1, GX0, GX0 + 1, 0, PL, ghW, P.brick, "GreenhousePlinth")
	wall(true, GZ0 + 1, GZ1 - 1, GX1 - 1, GX1, 0, PL, ghE, P.brick, "GreenhousePlinth")
	wall(false, GX0, GX1, GZ0 + 0.3, GZ0 + 0.7, PL, GH, ghN, P.glass, "GreenhouseGlass")
	wall(false, GX0, GX1, GZ1 - 0.7, GZ1 - 0.3, PL, GH, ghS, P.glass, "GreenhouseGlass")
	wall(true, GZ0 + 1, GZ1 - 1, GX0 + 0.3, GX0 + 0.7, PL, GH, ghW, P.glass, "GreenhouseGlass")
	wall(true, GZ0 + 1, GZ1 - 1, GX1 - 0.7, GX1 - 0.3, PL, GH, ghE, P.glass, "GreenhouseGlass")
	-- white-painted frame: corner and intermediate posts, door frames, eaves beams
	for _, x in { 56, 68, 92, 104 } do
		blk(x - 0.4, PL, GZ0, x + 0.4, GH, GZ0 + 1, P.paintWhite, "GlazingBar")
		blk(x - 0.4, PL, GZ1 - 1, x + 0.4, GH, GZ1, P.paintWhite, "GlazingBar")
	end
	for _, z in { -96, -66, -56 } do
		blk(GX0, PL, z - (if z == -96 then 0 else 0.4), GX0 + 1, GH, z + (if z == -96 then 0.8 else 0), P.paintWhite, "GlazingBar")
	end
	for _, z in { -96, -88, -56 } do
		blk(GX1 - 1, PL, z - (if z == -96 then 0 else 0.4), GX1, GH, z + (if z == -96 then 0.8 else 0), P.paintWhite, "GlazingBar")
	end
	blk(GX0 - 0.2, GH, GZ0 - 0.2, GX1 + 0.2, GH + 0.6, GZ0 + 1, P.paintWhite, "EavesBeam")
	blk(GX0 - 0.2, GH, GZ1 - 1, GX1 + 0.2, GH + 0.6, GZ1 + 0.2, P.paintWhite, "EavesBeam")
	blk(GX0 - 0.2, GH, GZ0 + 1, GX0 + 1, GH + 0.6, GZ1 - 1, P.paintWhite, "EavesBeam")
	blk(GX1 - 1, GH, GZ0 + 1, GX1 + 0.2, GH + 0.6, GZ1 - 1, P.paintWhite, "EavesBeam")
	-- pitched glass roof, ridge along X
	local GRZ = (GZ0 + GZ1) / 2
	wedge(CFrame.new((GX0 + GX1) / 2, GH + 0.6 + 3, (GZ0 + GRZ) / 2), Vector3.new(GX1 - GX0, 6, GRZ - GZ0), P.glass, "GreenhouseRoof")
	wedge(CFrame.new((GX0 + GX1) / 2, GH + 0.6 + 3, (GRZ + GZ1) / 2) * CFrame.Angles(0, math.pi, 0), Vector3.new(GX1 - GX0, 6, GZ1 - GRZ), P.glass, "GreenhouseRoof")
	blk(GX0, GH + 6.6, GRZ - 0.4, GX1, GH + 7.2, GRZ + 0.4, P.paintWhite, "RidgeBeam")
	for _, x in { 68, 80, 92 } do
		blk(x - 0.3, GH, GZ0 + 1, x + 0.3, GH + 0.6, GZ1 - 1, P.paintWhite, "RoofBeam")
	end
	-- staging benches (3 tall), with pots
	local function stagingBench(x0: number, z0: number, x1: number, z1: number)
		blk(x0, 0, z0, x1, 3, z1, P.planks, "StagingBench")
		local n = math.floor((x1 - x0) / 4)
		for i = 0, n - 1 do
			local x = x0 + 2 + i * 4
			cylY(x, 3, (z0 + z1) / 2, 4.2, 1.4, if i % 2 == 0 then P.leafOrange else P.boxHedge, "Pot")
		end
	end
	stagingBench(60, -93, 100, -90)
	stagingBench(62, -80, 74, -77)
	stagingBench(86, -80, 98, -77)
	stagingBench(60, -60, 72, -57)
	stagingBench(88, -60, 100, -57)
	-- potted citrus trees
	for _, p in { { 66, -86 }, { 94, -86 }, { 66, -68 }, { 94, -68 } } do
		cylY(p[1], 0, p[2], 2.5, 3, P.brick, "TreePot")
		cylY(p[1], 2.5, p[2], 7, 0.6, P.bark, "TreeStem")
		blk(p[1] - 2, 6.5, p[2] - 2, p[1] + 2, 10, p[2] + 2, soft(P.boxHedge), "TreeCrown")
	end
	-- outside: rain barrels and a potting table
	cylY(50, 0, -92, 4, 3, P.planksDark, "RainBarrel")
	cylY(50, 0, -60, 4, 3, P.planksDark, "RainBarrel")
	blk(108, 0, -96, 111, 3.4, -86, P.planks, "PottingTable")

	-------------------------------------------------------------------------------------------
	-- Manor house (middle lane): X -66..66, Z -30..30. Ground Y 0, upper floor Y 14.
	-- Great hall X -24..24 is double height with galleries (Z -28..-20 and 20..28) at Y 14.
	-------------------------------------------------------------------------------------------
	section("Manor")
	-- outer walls, ground storey
	local groundNS: { Opening } = {
		{ -62, -56, 4, 9 }, { -52, -44, 0, 10 }, { -38, -32, 4, 9 }, { -18, -10, 4, 9 },
		{ -4, 4, 0, 10 }, { 10, 18, 4, 9 }, { 32, 38, 4, 9 }, { 44, 52, 0, 10 }, { 56, 62, 4, 9 },
	}
	local upperNS: { Opening } = {
		{ -60, -52, 17, 22 }, { -40, -32, 17, 22 }, { -18, -10, 17, 22 }, { 10, 18, 17, 22 },
		{ 32, 40, 17, 22 }, { 52, 60, 17, 22 },
	}
	local groundWE: { Opening } = { { -20, -14, 4, 9 }, { -4, 4, 0, 10 }, { 14, 20, 4, 9 } }
	local upperWE: { Opening } = { { -20, -12, 17, 22 }, { 12, 20, 17, 22 } }
	for _, s in { -1, 1 } do
		wall(false, -66, 66, s * 28, s * 30, 0, FLOOR2, groundNS, P.brick, "ManorWall")
		wall(false, -66, 66, s * 28, s * 30, FLOOR2, EAVES, upperNS, P.brick, "ManorWall")
		wall(true, -28, 28, s * 64, s * 66, 0, FLOOR2, groundWE, P.brick, "ManorWall")
		wall(true, -28, 28, s * 64, s * 66, FLOOR2, EAVES, upperWE, P.brick, "ManorWall")
		-- stone string course and plinth
		blk(-66.3, FLOOR2 - 0.6, s * 30 - 0.3, 66.3, FLOOR2 + 0.4, s * 30 + 0.3, P.stone, "StringCourse")
		blk(s * 66 - 0.3, FLOOR2 - 0.6, -30, s * 66 + 0.3, FLOOR2 + 0.4, 30, P.stone, "StringCourse")
		-- quoins at the corners
		for _, s2 in { -1, 1 } do
			blk(s * 66 - s * 2.5, 0, s2 * 30 - s2 * 2.5, s * 66 + s * 0.3, EAVES, s2 * 30 + s2 * 0.3, P.stone, "Quoin")
		end
	end
	-- interior partitions between the hall and the wings
	wall(true, -28, 28, -26, -24, 0, FLOOR2, { { -20, -12, 0, 10 } }, P.paintWhite, "Partition")
	wall(true, -28, 28, 24, 26, 0, FLOOR2, { { 12, 20, 0, 10 } }, P.paintWhite, "Partition")
	for _, s in { -1, 1 } do
		wall(true, -28, 28, s * 24, s * 26, FLOOR2, EAVES, { { -27, -21, FLOOR2, 24 }, { 21, 27, FLOOR2, 24 } }, P.paintWhite, "Partition")
	end
	-- upper floors: wings and the two galleries (open over the hall between Z -20..20)
	blk(-64, FLOOR2 - 1, -28, -26, FLOOR2, 28, P.floor, "UpperFloorWest")
	blk(26, FLOOR2 - 1, -28, 64, FLOOR2, 28, P.floor, "UpperFloorEast")
	blk(-24, FLOOR2 - 1, -28, 24, FLOOR2, -20, P.floor, "GalleryNorth")
	blk(-24, FLOOR2 - 1, 20, 24, FLOOR2, 28, P.floor, "GallerySouth")
	-- gallery balustrades (3.5 tall), open where the stairs arrive
	blk(-24, FLOOR2, -20.4, 17, FLOOR2 + 3.5, -20, P.planksDark, "Balustrade")
	blk(-17, FLOOR2, 20, 24, FLOOR2 + 3.5, 20.4, P.planksDark, "Balustrade")
	-- grand stairs: west flight rises south to the south gallery, east flight rises north
	stairs(-24, -6, -17, 20, "+Z", 0, FLOOR2, P.planksDark)
	stairs(17, -20, 24, 6, "-Z", 0, FLOOR2, P.planksDark)
	-- gallery columns and the chandelier
	for _, c in { { -8, -20.5 }, { 8, -20.5 }, { -8, 20.5 }, { 8, 20.5 } } do
		cylY(c[1], 0, c[2], FLOOR2 - 1, 1.6, P.marble, "HallColumn")
	end
	blk(-3, 21, -3, 3, 22, 3, soft(P.lamp), "Chandelier")
	cylY(0, 22, 0, EAVES, 0.3, soft(P.iron), "ChandelierChain")
	-- hall furniture: two settees facing a round table off-centre
	bench(0, -9, 10, false, P.fabric)
	bench(0, 9, 10, false, P.fabric)
	blk(-23.5, 0, -27.5, -19, 9, -24, P.marble, "HallFireplace")
	blk(19, 0, 24, 23.5, 9, 27.5, P.marble, "HallFireplace")
	-- roof: slate slab, gables (ridge along X), chimneys
	blk(-67, EAVES, -31, 67, EAVES + 1, 31, P.slateDark, "ManorRoofSlab")
	wedge(CFrame.new(0, EAVES + 1 + 5, -15.5), Vector3.new(134, 10, 31), P.slate, "ManorRoof")
	wedge(CFrame.new(0, EAVES + 1 + 5, 15.5) * CFrame.Angles(0, math.pi, 0), Vector3.new(134, 10, 31), P.slate, "ManorRoof")
	for _, x in { -46, -10, 10, 46 } do
		blk(x - 2.5, EAVES + 1, -2, x + 2.5, EAVES + 15, 2, P.brickDark, "Chimney")
		blk(x - 3, EAVES + 15, -2.5, x + 3, EAVES + 16, 2.5, P.stone, "ChimneyCap")
	end
	-- porticoes over the hall's north and south doors
	for _, s in { -1, 1 } do
		for _, x in { -6, 6 } do
			cylY(x, 0, s * 36, 12, 1.8, P.marble, "PorticoColumn")
		end
		blk(-8, 12, s * 30, 8, 13, s * 38, P.stone, "PorticoRoof")
		blk(-8.5, 13, s * 37.5, 8.5, 14.5, s * 38.5, P.stone, "PorticoPediment")
	end

	-- Library (west wing ground floor): book stacks with a central aisle on the west door axis.
	for _, x in { -56, -46, -36 } do
		for _, zz in { { -18, -6 }, { 6, 18 } } do
			blk(x - 0.8, 0, zz[1], x + 0.8, 10, zz[2], P.planksDark, "BookStack")
			blk(x - 0.85, 1, zz[1] + 0.3, x + 0.85, 9.4, zz[2] - 0.3, P.books, "Books")
		end
	end
	blk(-63.6, 0, -27.6, -27, 12, -26.6, P.planksDark, "WallShelves")
	blk(-63.6, 0, 26.6, -27, 12, 27.6, P.planksDark, "WallShelves")
	blk(-33, 0, -3, -29, 3, 3, P.wood, "ReadingTable")
	blk(-62, 0, 22, -58, 3, 26, P.fabricGreen, "Armchair")
	-- Dining room (east wing ground floor)
	blk(34, 0, -3, 56, 3, 3, P.wood, "DiningTable")
	blk(30, 0, -27.6, 42, 4, -25.6, P.planksDark, "Sideboard")
	blk(48, 0, 16, 54, 4, 21, P.wood, "Piano")
	blk(30, 0, 25, 38, 8, 28, P.marble, "DiningFireplace")
	-- Upper west: bedrooms (dividing wall with a door on the centre line)
	wall(true, -28, 28, -46, -44, FLOOR2, EAVES, { { -4, 4, FLOOR2, 24 } }, P.paintWhite, "BedroomWall")
	blk(-62, FLOOR2, -24, -54, FLOOR2 + 3, -14, P.fabric, "Bed")
	blk(-62, FLOOR2, 14, -54, FLOOR2 + 3, 24, P.fabricGreen, "Bed")
	blk(-36, FLOOR2, -27.5, -30, FLOOR2 + 8, -25, P.wood, "Wardrobe")
	blk(-36, FLOOR2, 25, -30, FLOOR2 + 8, 27.5, P.wood, "Wardrobe")
	blk(-38, FLOOR2, -4, -34, FLOOR2 + 3, 4, P.wood, "WritingDesk")
	-- Upper east: long gallery of portraits and display cases
	for _, z in { -12, 12 } do
		blk(36, FLOOR2, z - 2, 40, FLOOR2 + 4, z + 2, P.marble, "DisplayCase")
		blk(52, FLOOR2, z - 2, 56, FLOOR2 + 4, z + 2, P.marble, "DisplayCase")
	end
	bench(46, 0, 8, true, P.fabricGreen, FLOOR2)
	for _, x in { 34, 46, 58 } do
		blk(x - 3, FLOOR2 + 6, -27.9, x + 3, FLOOR2 + 11, -27.6, P.planks, "Portrait")
	end

	-------------------------------------------------------------------------------------------
	-- Terraces (middle band outside the manor): statues, urns, low balustrades.
	-------------------------------------------------------------------------------------------
	section("Terraces")
	for _, s in { -1, 1 } do
		-- statue on the drive axis blocks the long arch-to-door line
		statue(s * 92, 0)
		urn(s * 76, s * -16)
		urn(s * 76, s * 26)
		urn(s * 104, s * 10)
		bench(s * 88, s * -30, 8, false, P.stone)
		-- clipped yew planters break the north-south belt in front of each arch
		blk(s * 100, 0, s * 20, s * 108, 4, s * 26, P.boxHedge, "YewPlanter")
		blk(s * 100, 0, s * -26, s * 108, 4, s * -20, P.boxHedge, "YewPlanter")
		tree(s * 104, s * -34, 12, P.leafRed, P.leafOrange, 5)
		lampPost(s * 70, -8, 11)
		lampPost(s * 70, 8, 11)
		-- low balustrades along the garden and orchard edges of the terrace
		for _, seg in { { 8, 24 }, { 40, 60 }, { 80, 96 } } do
			blk(seg[1], 0, s * 40 - 0.5, seg[2], 3.5, s * 40 + 0.5, P.stone, "TerraceBalustrade")
			blk(-seg[2], 0, s * 40 - 0.5, -seg[1], 3.5, s * 40 + 0.5, P.stone, "TerraceBalustrade")
		end
		urn(-30, s * 35)
		urn(30, s * 35)
	end

	-------------------------------------------------------------------------------------------
	-- Orchard (south lane, west): stone-walled, X -100..-14, Z 46..110 (south side = garden wall).
	-------------------------------------------------------------------------------------------
	section("Orchard")
	local OW = 8
	wall(false, -100, -14, 46, 48, 0, OW, { { -90, -82, 0, 10 }, { -70, -62, 3, 10 }, { -50, -42, 0, 10 } }, P.cobble, "OrchardWall")
	wall(true, 48, 110, -100, -98, 0, OW, { { 64, 74, 0, 10 } }, P.cobble, "OrchardWall")
	wall(true, 48, 110, -16, -14, 0, OW, { { 58, 66, 0, 10 }, { 80, 88, 3, 10 }, { 96, 104, 0, 10 } }, P.cobble, "OrchardWall")
	blk(-100.3, OW, 45.7, -13.7, OW + 0.5, 48.3, P.slate, "WallCap")
	blk(-100.3, OW, 48, -97.7, OW + 0.5, 110, P.slate, "WallCap")
	blk(-16.3, OW, 48, -13.7, OW + 0.5, 110, P.slate, "WallCap")
	local orchardLeaves = { P.leafOrange, P.leafRed, P.leafGold }
	local k = 0
	for _, x in { -86, -66, -46, -28 } do
		for _, z in { 60, 78, 96 } do
			k += 1
			tree(x, z, 9, orchardLeaves[k % 3 + 1], orchardLeaves[(k + 1) % 3 + 1], 4.5)
		end
	end
	-- apple crates and a barrow between the rows
	crate(-76, 0, 69, 3)
	crate(-74, 0, 72, 2.4, 0.4)
	crate(-56, 0, 62, 3, 0.2)
	crate(-36, 0, 87, 3)
	crate(-38, 0, 90, 2.4, 0.3)
	crate(-56, 0, 94, 3, -0.2)
	crate(-88, 0, 86, 3)
	blk(-22, 0, 70, -18, 2.4, 76, P.planks, "Barrow")
	-- cider shed in the south-west corner
	for _, p in { { -96, 96 }, { -84, 96 } } do
		blk(p[1] - 0.5, 0, p[2] - 0.5, p[1] + 0.5, 9, p[2] + 0.5, P.wood, "ShedPost")
	end
	blk(-97.5, 0, 107, -82.5, 9, 108, P.planks, "ShedBackWall")
	blk(-98, 9, 95, -82, 9.6, 108.5, P.slate, "ShedRoof")
	blk(-94, 0, 101, -88, 5, 105, P.planksDark, "CiderPress")
	cylY(-86, 0, 102, 3.5, 3, P.planksDark, "CiderBarrel")

	-------------------------------------------------------------------------------------------
	-- Cart track (X -14..16): hay wagon, pump and trough, mounting block.
	-------------------------------------------------------------------------------------------
	section("CartTrack")
	blk(-3, 1.6, 52, 3, 3, 66, P.planks, "WagonBed")
	blk(-2.6, 3, 53, 2.6, 6.5, 65, P.hay, "WagonHay")
	for _, z in { 55, 63 } do
		cylH(-3.2, 1.8, z, 0.5, 3.6, false, P.planksDark, "WagonWheel")
		cylH(3.2, 1.8, z, 0.5, 3.6, false, P.planksDark, "WagonWheel")
	end
	blk(-0.3, 1.2, 46, 0.3, 1.6, 52, P.wood, "WagonTongue")
	blk(-4, 0, 85, 4, 2.5, 87.5, P.stone, "Trough")
	blk(-0.6, 0, 88, 0.6, 5, 89.2, P.iron, "Pump")
	blk(-8, 0, 98, -4, 2.5, 102, P.stone, "MountingBlock")
	bale(8, 102, true)
	bale(-8, 74, false)

	-------------------------------------------------------------------------------------------
	-- Carriage house (south lane, east): X 16..70, Z 52..90, brick, slate gable roof.
	-------------------------------------------------------------------------------------------
	section("CarriageHouse")
	local CH = 14
	wall(false, 16, 70, 52, 54, 0, CH, { { 24, 32, 0, 10 }, { 40, 46, 5, 9 }, { 54, 62, 0, 10 } }, P.brick, "CarriageWall")
	wall(false, 16, 70, 88, 90, 0, CH, { { 26, 32, 5, 9 }, { 38, 48, 0, 11 }, { 56, 62, 5, 9 } }, P.brick, "CarriageWall")
	wall(true, 54, 88, 16, 18, 0, CH, { { 66, 76, 0, 11 } }, P.brick, "CarriageWall")
	wall(true, 54, 88, 68, 70, 0, CH, { { 58, 62, 5, 9 }, { 66, 76, 0, 11 } }, P.brick, "CarriageWall")
	blk(15, CH, 51, 71, CH + 1, 91, P.slateDark, "CarriageRoofSlab")
	wedge(CFrame.new(43, CH + 1 + 3.5, 61), Vector3.new(56, 7, 20), P.slate, "CarriageRoof")
	wedge(CFrame.new(43, CH + 1 + 3.5, 81) * CFrame.Angles(0, math.pi, 0), Vector3.new(56, 7, 20), P.slate, "CarriageRoof")
	-- clock cupola on the ridge
	blk(40, CH + 8, 68, 46, CH + 12, 74, P.paintWhite, "Cupola")
	blk(41, CH + 9.5, 67.8, 45, CH + 11.5, 68, P.marble, "ClockFace")
	blk(39.5, CH + 12, 67.5, 46.5, CH + 13, 74.5, P.slate, "CupolaRoof")
	-- carriage door frames (timber)
	for _, z in { 66, 76 } do
		blk(15.6, 0, z - 0.6, 16, 11.4, z + 0.6, P.planksDark, "DoorFrame")
		blk(70, 0, z - 0.6, 70.4, 11.4, z + 0.6, P.planksDark, "DoorFrame")
	end
	-- carriages and hay inside
	carriage(30, 62, 0, P.sable)
	carriage(56, 81, math.pi, P.talon)
	hayStack(24, 84, 2, false)
	hayStack(62, 58, 2, false)
	hayStack(43, 57, 1, false)
	blk(18, 4, 58, 18.6, 8, 64, P.planksDark, "TackRack")
	blk(60, 0, 70, 64, 3, 72, P.planks, "FeedBin")

	-------------------------------------------------------------------------------------------
	-- Paddock (X 74..112): post-and-rail fence, field shelter, trough, round bales.
	-------------------------------------------------------------------------------------------
	section("Paddock")
	fence(false, 78, 110, 50, { { 90, 98 } })
	fence(false, 78, 110, 104, { { 86, 94 } })
	fence(true, 50, 104, 78, { { 66, 76 } })
	fence(true, 50, 104, 110, { { 64, 78 } })
	-- field shelter (3-sided, open to the north)
	blk(92, 0, 98, 106, 11, 99, P.planks, "ShelterWall")
	blk(92, 0, 88, 93, 11, 98, P.planks, "ShelterWall")
	blk(105, 0, 88, 106, 11, 98, P.planks, "ShelterWall")
	blk(91, 11, 87, 107, 11.6, 100, P.slate, "ShelterRoof")
	blk(86, 0, 62, 92, 2.5, 64, P.stone, "WaterTrough")
	bale(98, 60, false)
	bale(84, 84, true)
	bale(102, 76, true)
	tree(116, 96, 11, P.leafGold, P.leafRed, 4)

	-------------------------------------------------------------------------------------------
	-- Kitchen walk (south flank, Z 112..130).
	-------------------------------------------------------------------------------------------
	section("KitchenWalk")
	-- potting shed straddling the walk's south half (leaves a 10-wide passage)
	wall(false, -7, 7, 122, 123, 0, 9, { { -3, 3, 0, 9 } }, P.planks, "PottingShed")
	blk(-7, 0, 123, -6, 9, 130, P.planks, "PottingShed")
	blk(6, 0, 123, 7, 9, 130, P.planks, "PottingShed")
	blk(-8, 9, 121.5, 8, 9.6, 130, P.slate, "PottingShedRoof")
	-- cold frames (low brick with glass lids) and woodpiles
	for _, s in { -1, 1 } do
		blk(s * 60 - 6, 0, 124, s * 60 + 6, 2.2, 129, P.brick, "ColdFrame")
		blk(s * 60 - 5.6, 2.2, 124.4, s * 60 + 5.6, 2.6, 128.6, P.glass, "ColdFrameLid")
		blk(s * 22 - 5, 0, 125, s * 22 + 5, 4, 130, P.planksDark, "Woodpile")
		blk(s * 96 - 4, 0, 114, s * 96 + 4, 4, 118, P.planksDark, "Woodpile")
		blk(s * 40 - 3, 0, 126, s * 40 + 3, 4.5, 130, P.planks, "CompostBay")
		cylY(s * 78, 0, 116, 4, 3, P.planksDark, "WaterButt")
		lampPost(s * 50, 114, 10)
	end
	blk(-110, 0, 116, -104, 2.4, 120, P.planks, "Wheelbarrow")
	blk(104, 0, 124, 110, 2.4, 128, P.planks, "Wheelbarrow")

	-------------------------------------------------------------------------------------------
	-- Team bases: Sable gatehouse court (west), Talon stable court (east). Mirror symmetric
	-- in shape; only the arch dressing and accents differ.
	-------------------------------------------------------------------------------------------
	local function spawnPart(x: number, y: number, z: number, lookX: number, lookZ: number, team: string?, ffa: boolean)
		local p = Instance.new("Part")
		p.Name = if team then team .. "Spawn" else "FFASpawn"
		p.Size = Vector3.new(2, 1, 2)
		local pos = Vector3.new(x, y + 0.5, z)
		p.CFrame = CFrame.lookAt(pos, Vector3.new(lookX, y + 0.5, lookZ))
		p.Anchored = true
		p.Transparency = 1
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		if team then
			p:SetAttribute("Team", team)
		end
		if ffa then
			p:SetAttribute("FFA", true)
		end
		p.Parent = spawns
	end

	for _, s in { -1, 1 } do
		local team = if s < 0 then "Sable" else "Talon"
		local accent = if s < 0 then P.sable else P.talon
		section(team .. "Base")
		-- estate wall with five gaps, brick upper
		local open: { Opening } = {}
		for _, g in GAPS do
			table.insert(open, { g[1], g[2], -4, 14 })
		end
		wall(true, -130, 130, s * (SCREEN_X - 1), s * (SCREEN_X + 1), 0, 7, open, P.cobble, "EstateWall")
		wall(true, -130, 130, s * (SCREEN_X - 1), s * (SCREEN_X + 1), 7, 14, open, P.brick, "EstateWall")
		-- each gap is a short walled passage (fins X 112..128); a baffle on the spawn side
		-- (X 136..138) catches the shallow lines that pass through it
		for gi, g in GAPS do
			if gi ~= 3 then
				for _, edge in { { g[1] - 1, g[1] }, { g[2], g[2] + 1 } } do
					blk(s * 112, 0, edge[1], s * 128, 14, edge[2], P.brick, "GapFin")
					blk(s * 112, 14, edge[1] - 0.2, s * 128, 14.6, edge[2] + 0.2, P.cobble, "GapFinCap")
					blk(s * 112, 0, edge[1] - 0.05, s * 112.6, 14, edge[2] + 0.05, accent, "GapFinBanner")
				end
			end
			local z0 = math.max(g[1] - 8, -130)
			local z1 = math.min(g[2] + 8, 130)
			blk(s * 136, 0, z0, s * 138, 12, z1, P.brickDark, "Baffle")
			blk(s * 136, 6, z0, s * 135.7, 7.5, z1, accent, "BaffleStripe")
			blk(s * 138, 6, z0, s * 138.3, 7.5, z1, accent, "BaffleStripe")
		end
		-- centre arch: Sable gatehouse (stone towers, slate roof) / Talon clock arch (timber, cupola)
		local tower = if s < 0 then P.stone else P.brick
		for _, zz in { { -16, -6 }, { 6, 16 } } do
			blk(s * 114, 0, zz[1], s * 130, 22, zz[2], tower, "ArchTower")
		end
		blk(s * 114, 11, -6, s * 130, 22, 6, if s < 0 then P.stone else P.planks, "ArchLintel")
		blk(s * 113, 22, -17, s * 131, 23, 17, P.slateDark, "ArchRoofSlab")
		if s < 0 then
			-- gatehouse: hipped slate roof and crenellated parapet
			wedge(CFrame.new(-122, 26, -8.5), Vector3.new(18, 6, 17), P.slate, "GatehouseRoof")
			wedge(CFrame.new(-122, 26, 8.5) * CFrame.Angles(0, math.pi, 0), Vector3.new(18, 6, 17), P.slate, "GatehouseRoof")
			for _, z in { -16, -10, 10, 16 } do
				blk(-112.8, 16, z - 1, -112, 19, z + 1, P.stone, "Crest")
			end
			blk(-112.4, 11, -7, -112, 12, 7, accent, "ArchBand")
		else
			blk(117, 23, -4, 127, 29, 4, P.paintWhite, "ClockTower")
			blk(116.8, 25, -2.5, 117, 28, 2.5, P.marble, "ClockFace")
			wedge(CFrame.new(122, 31, -2.5), Vector3.new(11, 4, 5), P.slate, "ClockRoof")
			wedge(CFrame.new(122, 31, 2.5) * CFrame.Angles(0, math.pi, 0), Vector3.new(11, 4, 5), P.slate, "ClockRoof")
			blk(112, 11, -7, 112.4, 12, 7, accent, "ArchBand")
		end
		-- courtyard dressing kept off the spawn columns (|X| 150 and 167)
		for _, z in { -110, -26, 26, 110 } do
			lampPost(s * 158, z, 10)
		end
		tree(s * 158, -75, 13, P.leafOrange, P.leafRed, 5)
		tree(s * 158, 75, 13, P.leafRed, P.leafGold, 5)
		if s < 0 then
			cylY(-175, 0, -22, 3, 5, P.cobble, "Well")
			blk(-177.5, 3, -22.3, -172.5, 8, -21.7, P.wood, "WellFrame")
			blk(-177.5, 8, -24, -172.5, 8.6, -20, P.slate, "WellRoof")
			blk(-178, 0, 64, -172, 3, 70, P.planks, "Cart")
			crate(-174, 0, -64, 3)
		else
			-- stable range along the east boundary: stall partitions under a lean-to roof
			for z = -122, 122, 16 do
				blk(172, 0, z - 0.4, 180, 6, z + 0.4, P.planks, "StallPartition")
			end
			for z = -120, 120, 40 do
				blk(170.6, 0, z - 0.5, 171.6, 12, z + 0.5, P.wood, "StablePost")
			end
			blk(170, 12, -130, 180, 12.8, 130, P.slate, "StableRoof")
			blk(170, 11.4, -130, 170.4, 12.8, 130, accent, "StableFascia")
			blk(174, 0, -66, 178, 2.5, -60, P.stone, "Trough")
			hayStack(176, 32, 2, true)
		end
		blk(s * 166, 0, 116, s * 176, 3, 124, P.planksDark, "TackChest")

		-- team spawns: two columns of five, facing into the map
		for _, z in { -100, -50, 0, 50, 100 } do
			for _, x in { 150, 167 } do
				spawnPart(s * x, 0, z + (if x == 167 then 8 else 0), 0, z, team, false)
			end
		end
	end

	-------------------------------------------------------------------------------------------
	-- FFA spawns spread around the whole map. { x, floorY, z, lookX, lookZ }
	-------------------------------------------------------------------------------------------
	local ffa = {
		{ -160, 0, -118, 0, -118 },
		{ -160, 0, 30, 0, 30 },
		{ 160, 0, -30, 0, -30 },
		{ 160, 0, 118, 0, 118 },
		{ -70, 0, -121, 0, -121 },
		{ 50, 0, -116, 0, -116 },
		{ -100, 0, -60, 0, -60 },
		{ -20, 0, -92, 0, -92 },
		{ 80, 0, -85, 0, -85 },
		{ -49, 0, 10, 0, 10 },
		{ 45, 0, -10, 0, 0 },
		{ 0, FLOOR2, 24, 0, 0 },
		{ -60, 0, 70, 0, 70 },
		{ 0, 0, 74, 0, 0 },
		{ 30, 0, 80, 0, 0 },
		{ 95, 0, 75, 0, 75 },
		{ -40, 0, 120, 0, 120 },
		{ 40, 0, 118, 0, 118 },
		{ -96, 0, 36, 0, 36 },
		{ 96, 0, -36, 0, -36 },
	}
	for _, f in ffa do
		spawnPart(f[1], f[2], f[3], f[4], f[5], nil, true)
	end

	-------------------------------------------------------------------------------------------
	-- Objective zones (invisible boxes). floorY = top of the floor the zone sits on.
	-------------------------------------------------------------------------------------------
	local function zone(name: string, kind: string, x: number, floorY: number, z: number, sx: number, sz: number, attrs: { [string]: any })
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(sx, 10, sz)
		p.CFrame = CFrame.new(x, floorY + 5, z)
		p.Anchored = true
		p.Transparency = 1
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p:SetAttribute("Kind", kind)
		for key, v in attrs do
			p:SetAttribute(key, v)
		end
		p.Parent = objectives
	end

	-- Domination: A west terrace, B great hall, C east terrace (point symmetric).
	zone("FlagA", "Flag", -88, 0, 18, 18, 18, { Label = "A" })
	zone("FlagB", "Flag", 0, 0, 0, 20, 16, { Label = "B" })
	zone("FlagC", "Flag", 88, 0, -18, 18, 18, { Label = "C" })

	-- Hardpoint rotation: hall -> greenhouse -> orchard -> maze -> carriage house -> library.
	zone("Hardpoint1_GreatHall", "Hardpoint", 0, 0, 0, 28, 22, { Order = 1 })
	zone("Hardpoint2_Greenhouse", "Hardpoint", 80, 0, -72, 30, 22, { Order = 2 })
	zone("Hardpoint3_Orchard", "Hardpoint", -56, 0, 78, 26, 26, { Order = 3 })
	zone("Hardpoint4_HedgeMaze", "Hardpoint", 0, 0, -74, 28, 16, { Order = 4 })
	zone("Hardpoint5_CarriageHouse", "Hardpoint", 43, 0, 71, 28, 22, { Order = 5 })
	zone("Hardpoint6_Library", "Hardpoint", -45, 0, 0, 26, 24, { Order = 6 })

	-- Search and Destroy: Sable storms the estate through the gatehouse in round 1, so both sites
	-- are on the Talon (east) side. A: greenhouse. B: carriage house.
	zone("BombSiteA", "BombSite", 80, 0, -66, 14, 14, { Label = "A" })
	zone("BombSiteB", "BombSite", 43, 0, 71, 14, 14, { Label = "B" })

	-------------------------------------------------------------------------------------------
	-- Lobby camera (frames the manor from the north-west, over the gardens) + attributes.
	-------------------------------------------------------------------------------------------
	local cam = Instance.new("Part")
	cam.Name = "LobbyCamera"
	cam.Size = Vector3.new(1, 1, 1)
	cam.CFrame = CFrame.lookAt(Vector3.new(-150, 95, -190), Vector3.new(0, 14, -10))
	cam.Anchored = true
	cam.Transparency = 1
	cam.CanCollide = false
	cam.CanQuery = false
	cam.CanTouch = false
	cam.Parent = model

	model:SetAttribute("KillY", MapModule.killY)
	model:SetAttribute("DisplayName", MapModule.displayName)
	model:SetAttribute("BoundsMin", BOUNDS_MIN)
	model:SetAttribute("BoundsMax", BOUNDS_MAX)
	model:SetAttribute("SnDAttackBase", "Sable")

	return model
end

return MapModule
