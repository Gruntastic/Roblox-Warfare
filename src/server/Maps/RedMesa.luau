--!strict
--[[
	Red Mesa: a working copper-and-iron mining outpost cut into a red-rock canyon, at midday.
	Large map, ~420 x 300 studs playable (boundary inner faces at X = +-210, Z = +-150).
	It is the long-range map of the rotation: open terraces, a long main street and a high ridge.

	Axes: +X = east, -Z = north (top of the ASCII sketch in docs/maps/RedMesa.md).
	Floor levels (top surfaces):
	  Y 12  Ridge path (north flank), Z -140..-122
	  Y  6  Ore terrace (north lane), Z -122..-60
	  Y  0  Main street, camp and base yards
	  Y -8  Dry wash (a sunken north-south channel at X -14..14, Z -60..124)
	Every level stands on ground parts that reach down to BoundsMin.Y (-10), so there is never a
	hole to the void: the bedrock slab covers the whole footprint and every terrace is one solid block.

	Bands, north -> south:
	  Z -150..-140  Cliff face (unreachable rock)
	  Z -140..-122  Ridge path (north flank, Y 12): hoodoos and a lookout shack
	  Z -122.. -60  Ore terrace (north lane, Y 6): crusher house, ore conveyor, two ore loaders
	  Z  -60..  22  Main street (middle lane, Y 0): assay office / fuel depot, water towers,
	                and the trestle bridge over the dry wash at Z -8..8
	  Z   22..  56  Bunkhouse (west) and mess hall (east): walk-through buildings between the lanes
	  Z   56.. 124  Lower camp (south lane, Y 0): ore wagon spur, tool yard / powder magazine
	  Z  124.. 150  Rock-cut tunnel (south flank, ceiling Y 12)
	Sable base = west yard (X < -165), Talon base = east yard (X > 165), each behind a rock rampart.

	build() only uses Instance.new / Vector3 / CFrame / Color3 / Enum / math so it also runs under Lune.
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

local M = Enum.Material

-- Bright midday red-rock palette.
local P = {
	sandstone = style(M.Sandstone, 184, 96, 62),
	sandstoneLight = style(M.Sandstone, 206, 132, 88),
	sandstoneDark = style(M.Sandstone, 150, 74, 48),
	rock = style(M.Rock, 142, 72, 50),
	rockDark = style(M.Rock, 112, 58, 42),
	rockPale = style(M.Rock, 196, 150, 112),
	ground = style(M.Ground, 176, 108, 72),
	groundPale = style(M.Ground, 198, 146, 104),
	washSand = style(M.Sand, 214, 168, 120),
	ore = style(M.Slate, 92, 70, 64),
	rust = style(M.CorrodedMetal, 132, 70, 42),
	rustDark = style(M.CorrodedMetal, 94, 54, 36),
	metal = style(M.Metal, 128, 120, 112),
	planks = style(M.WoodPlanks, 150, 108, 70),
	planksDark = style(M.WoodPlanks, 108, 76, 50),
	timber = style(M.Wood, 120, 86, 56),
	plaster = style(M.Plaster, 222, 196, 160),
	canvas = style(M.Fabric, 206, 186, 150),
	water = style(M.Glass, 96, 140, 160, 0.4),
	lamp = style(M.Neon, 255, 204, 140),
	paintGreen = style(M.SmoothPlastic, 84, 120, 96),
	paintCream = style(M.SmoothPlastic, 230, 214, 182),
	sable = style(M.SmoothPlastic, 64, 90, 110),
	talon = style(M.SmoothPlastic, 182, 108, 50),
}

local MapModule = {}

MapModule.id = "RedMesa"
MapModule.displayName = "Red Mesa"

-- Bright, warm, high-sun desert. Only valid Lighting properties.
MapModule.lighting = {
	ClockTime = 12.6,
	GeographicLatitude = 34,
	Brightness = 3.2,
	ExposureCompensation = -0.1,
	Ambient = Color3.fromRGB(122, 92, 76),
	OutdoorAmbient = Color3.fromRGB(168, 130, 104),
	ColorShift_Top = Color3.fromRGB(255, 226, 186),
	ColorShift_Bottom = Color3.fromRGB(120, 70, 50),
	EnvironmentDiffuseScale = 0.5,
	EnvironmentSpecularScale = 0.3,
	ShadowSoftness = 0.15,
	GlobalShadows = true,
	FogColor = Color3.fromRGB(226, 182, 140),
	FogStart = 400,
	FogEnd = 2400,
}

-- Valid Atmosphere properties: thin, dusty, bright.
MapModule.atmosphere = {
	Density = 0.24,
	Offset = 0.08,
	Color = Color3.fromRGB(232, 196, 160),
	Decay = Color3.fromRGB(176, 108, 74),
	Glare = 0.35,
	Haze = 1.1,
}

MapModule.killY = -40

-- Playable box (inner faces of the boundary cliffs) and the walls themselves.
local XB, ZB = 210, 150
local BOUNDS_MIN = Vector3.new(-214, -10, -154)
local BOUNDS_MAX = Vector3.new(214, 64, 154)

-- Base rampart: rock wall at |X| 170..174 with three gaps, outer baffles at |X| 158..161.
local RAMPART = { 170, 174 }
local BAFFLE = { 158, 161 }
local GAP_STREET = { -20, -10 }
local GAP_SOUTH = { 80, 90 }
local GAP_TUNNEL = { 134, 144 }

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

	-- Vertical cylinder (post, tank, drum).
	local function cylY(x: number, y0: number, z: number, y1: number, d: number, st: Style, name: string?): Part
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(y1 - y0, d, d)
		p.CFrame = CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
		finish(p, st, name)
		return p
	end

	-- Horizontal cylinder along X (rollers) or Z (axles, wheels).
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

	-- Wedge ramp of footprint w x run rising by h toward world direction dir ("+X", "-X", "+Z", "-Z").
	-- A WedgePart's high end is at local +Z, so the part is yawed to point that end along dir.
	local function ramp(cx: number, cz: number, baseY: number, w: number, run: number, h: number, dir: string, st: Style)
		local yaw = if dir == "+Z" then 0 elseif dir == "-Z" then math.pi elseif dir == "+X" then math.pi / 2 else -math.pi / 2
		wedge(CFrame.new(cx, baseY + h / 2, cz) * CFrame.Angles(0, yaw, 0), Vector3.new(w, h, run), st, "Ramp")
	end

	-- Props --------------------------------------------------------------------------------

	-- Weathered boulder: two or three overlapping rotated blocks.
	local function boulder(x: number, y: number, z: number, s: number, seed: number)
		local a = seed * 0.73
		box(CFrame.new(x, y + s * 0.4, z) * CFrame.Angles(0, a, 0.08), Vector3.new(s, s * 0.8, s * 0.85), P.rock, "Boulder")
		box(CFrame.new(x + s * 0.3, y + s * 0.3, z - s * 0.25) * CFrame.Angles(0.12, a + 0.9, 0), Vector3.new(s * 0.7, s * 0.6, s * 0.6), P.rockDark, "Boulder")
		if seed % 2 == 0 then
			box(CFrame.new(x - s * 0.35, y + s * 0.2, z + s * 0.3) * CFrame.Angles(0, a + 0.4, -0.1), Vector3.new(s * 0.55, s * 0.4, s * 0.5), P.sandstoneDark, "Boulder")
		end
	end

	-- Hoodoo: stacked rock column with a cap stone.
	local function hoodoo(x: number, y: number, z: number, h: number, seed: number)
		box(CFrame.new(x, y + h * 0.3, z) * CFrame.Angles(0, seed * 0.5, 0), Vector3.new(7, h * 0.6, 6.5), P.rock, "Hoodoo")
		box(CFrame.new(x, y + h * 0.75, z) * CFrame.Angles(0, seed * 0.5 + 0.4, 0), Vector3.new(5, h * 0.3, 4.8), P.sandstone, "Hoodoo")
		box(CFrame.new(x, y + h * 0.95, z) * CFrame.Angles(0, seed * 0.5 + 0.2, 0), Vector3.new(7.5, h * 0.1, 7), P.rockPale, "HoodooCap")
	end

	local function crate(x: number, y: number, z: number, s: number, yaw: number?)
		box(CFrame.new(x, y + s / 2, z) * CFrame.Angles(0, yaw or 0, 0), Vector3.new(s, s, s), P.planks, "Crate")
	end

	local function barrels(x: number, y: number, z: number, n: number)
		local offs = { { 0, 0 }, { 2.4, 0.6 }, { 0.9, 2.3 }, { -1.6, 1.8 } }
		for i = 1, math.min(n, #offs) do
			local o = offs[i]
			cylY(x + o[1], y, z + o[2], y + 3.4, 2.4, if i % 2 == 0 then P.rust else P.timber, "Barrel")
		end
	end

	-- Stack of mine timbers along X or Z: crouch cover, 3.6 tall.
	local function timberStack(x: number, y: number, z: number, len: number, alongZ: boolean)
		for i = 0, 2 do
			local h = y + i * 1.2
			local w = 4.2 - i * 0.9
			if alongZ then
				blk(x - w / 2, h, z - len / 2, x + w / 2, h + 1.2, z + len / 2, P.timber, "Timbers")
			else
				blk(x - len / 2, h, z - w / 2, x + len / 2, h + 1.2, z + w / 2, P.timber, "Timbers")
			end
		end
	end

	-- Ore cart on a short rail: body, ore heap and two axles. Long axis along X.
	local function oreCart(x: number, y: number, z: number)
		blk(x - 3, y + 0.8, z - 2, x + 3, y + 4, z + 2, P.rust, "OreCart")
		blk(x - 2.6, y + 4, z - 1.6, x + 2.6, y + 4.6, z + 1.6, P.ore, "OreHeap")
		for _, ax in { -2, 2 } do
			cylH(x + ax, y + 0.8, z, 4.6, 1.6, true, P.rustDark, "CartAxle")
		end
	end

	-- Ore wagon: bigger, open-topped, on a flat bed. Long axis along X.
	local function oreWagon(x: number, z: number, st: Style)
		blk(x - 7, 1.2, z - 3, x + 7, 2.2, z + 3, P.rustDark, "WagonBed")
		wall(false, x - 7, x + 7, z - 3, z - 2.4, 2.2, 6.5, {}, st, "WagonSide")
		wall(false, x - 7, x + 7, z + 2.4, z + 3, 2.2, 6.5, {}, st, "WagonSide")
		blk(x - 7, 2.2, z - 2.4, x - 6.4, 6.5, z + 2.4, st, "WagonEnd")
		blk(x + 6.4, 2.2, z - 2.4, x + 7, 6.5, z + 2.4, st, "WagonEnd")
		blk(x - 6.4, 2.2, z - 2.4, x + 6.4, 5.4, z + 2.4, P.ore, "WagonOre")
		for _, ax in { -4.5, 4.5 } do
			cylH(x + ax, 1.1, z, 6.6, 2.2, true, P.metal, "WagonAxle")
		end
	end

	-- Water tower: four timber legs with low braces and a tank on top.
	local function waterTower(x: number, z: number)
		for _, c in { { -4, -4 }, { 4, -4 }, { -4, 4 }, { 4, 4 } } do
			blk(x + c[1] - 0.8, 0, z + c[2] - 0.8, x + c[1] + 0.8, 16, z + c[2] + 0.8, P.timber, "TowerLeg")
		end
		blk(x - 4.8, 0, z - 4.8, x + 4.8, 1, z + 4.8, P.sandstoneDark, "TowerFooting")
		blk(x - 5, 15, z - 5, x + 5, 16, z + 5, P.planksDark, "TowerDeck")
		cylY(x, 16, z, 26, 11, P.planks, "Tank")
		cylY(x, 26, z, 27, 9, P.rustDark, "TankLid")
		blk(x - 0.3, 3, z - 4.8, x + 0.3, 11, z - 4.2, P.timber, "TowerBrace")
		blk(x - 0.3, 3, z + 4.2, x + 0.3, 11, z + 4.8, P.timber, "TowerBrace")
	end

	local function lamp(x: number, y: number, z: number, h: number)
		blk(x - 0.4, y, z - 0.4, x + 0.4, y + h, z + 0.4, P.timber, "LampPole")
		blk(x - 0.6, y + h - 1.4, z - 0.6, x + 0.6, y + h - 0.6, z + 0.6, P.lamp, "Lantern")
	end

	-------------------------------------------------------------------------------------------
	-- Ground. A bedrock slab covers the whole footprint (Y -10..-8); every level above it is a
	-- solid block standing on it, so the ground check finds no hole anywhere.
	-------------------------------------------------------------------------------------------
	section("Ground")
	blk(-214, -10, -154, 214, -8, 154, P.rockDark, "Bedrock")
	-- dry wash bed is the bedrock top (Y -8); a thin sand skin on it, flush enough to walk
	blk(-14, -8, -60, 14, -7.9, 124, P.washSand, "WashSand")
	-- terraces (full width: they continue into both base yards)
	blk(-XB, -8, -ZB, XB, 12, -122, P.sandstone, "RidgeTerrace")
	blk(-XB, -8, -122, XB, 6, -60, P.sandstoneLight, "OreTerrace")
	-- street and camp level, split by the wash
	blk(-XB, -8, -60, -14, 0, 124, P.ground, "WestFlat")
	blk(14, -8, -60, XB, 0, 124, P.ground, "EastFlat")
	blk(-XB, -8, 124, XB, 0, ZB, P.groundPale, "TunnelFloor")
	-- worn track along the street (cosmetic, 0.05 thick)
	blk(-160, 0, -16, -14, 0.05, 4, P.groundPale, "StreetTrack")
	blk(14, 0, -16, 160, 0.05, 4, P.groundPale, "StreetTrack")
	-- terrace lips (rock trim on the terrace faces, flush with the faces' tops)
	blk(-XB, 5.4, -60.6, XB, 6, -60, P.rockPale, "TerraceLip")
	blk(-XB, 11.4, -122.6, XB, 12, -122, P.rockPale, "RidgeLip")
	-- strata bands on the terrace faces (paper-thin, cosmetic)
	blk(-XB, 2, -59.95, -14, 3, -59.9, P.sandstoneDark, "Strata")
	blk(14, 2, -59.95, XB, 3, -59.9, P.sandstoneDark, "Strata")
	blk(-XB, 8, -121.95, XB, 9, -121.9, P.sandstoneDark, "Strata")

	-------------------------------------------------------------------------------------------
	-- Boundary: canyon walls on all sides (rock, 40+ tall), plus the north cliff above the ridge.
	-------------------------------------------------------------------------------------------
	section("Boundary")
	blk(-214, -8, -154, 214, 46, -150, P.rock, "CliffN")
	blk(-214, -8, 150, 214, 40, 154, P.rock, "CliffS")
	blk(-214, -8, -150, -210, 40, 150, P.rock, "CliffW")
	blk(210, -8, -150, 214, 40, 150, P.rock, "CliffE")
	-- north cliff face above the ridge path (Z -150..-140), stepped buttresses
	blk(-XB, 12, -150, XB, 30, -140, P.sandstoneDark, "CliffFace")
	for x = -190, 190, 38 do
		local w = 6 + (x % 3)
		blk(x - w, 12, -140, x + w, 18 + (x % 5) * 2, -137.5, P.rock, "Buttress")
	end
	-- south and side cliff ribs (cosmetic, against the walls)
	for x = -180, 180, 45 do
		blk(x - 4, 16, 147, x + 4, 40, 150, P.rockDark, "CliffRib")
	end
	for z = -100, 120, 55 do
		blk(-XB, 8, z - 4, -207, 40, z + 4, P.rockDark, "CliffRib")
		blk(207, 8, z - 4, XB, 40, z + 4, P.rockDark, "CliffRib")
	end
	-- strata along the outer walls
	blk(-XB, 20, 149.9, XB, 22, 150, P.sandstoneLight, "Strata")
	blk(-XB, 24, -150.1, XB, 26, -150, P.sandstoneLight, "Strata")

	-------------------------------------------------------------------------------------------
	-- Terrace links: stairs and wedge cart ramps (step rise 1, wedges under 25 degrees).
	-------------------------------------------------------------------------------------------
	section("TerraceLinks")
	for _, s in { -1, 1 } do
		-- street (Y 0) -> ore terrace (Y 6): stairs at |X| 40 and 140, cart ramp at |X| 80
		for _, xc in { 40, 140 } do
			stairs(s * xc - 5, -60, s * xc + 5, -50, "-Z", 0, 6, P.sandstoneDark)
			blk(s * xc - 5.6, 0, -60, s * xc - 5, 6.6, -50, P.timber, "StairRail")
			blk(s * xc + 5, 0, -60, s * xc + 5.6, 6.6, -50, P.timber, "StairRail")
		end
		ramp(s * 80, -52, 0, 8, 16, 6, "-Z", P.planksDark)
		-- base yard -> ore terrace
		stairs(s * 205, -60, s * 193, -50, "-Z", 0, 6, P.sandstoneDark)
		-- ore terrace (Y 6) -> ridge (Y 12): stairs at |X| 80 and 185, wedge at |X| 130
		for _, xc in { 80, 185 } do
			stairs(s * xc - 5, -122, s * xc + 5, -112, "-Z", 6, 12, P.sandstoneDark)
		end
		ramp(s * 130, -114, 6, 8, 16, 6, "-Z", P.planksDark)
	end

	-------------------------------------------------------------------------------------------
	-- Ridge path (north flank, Y 12, Z -140..-122): hoodoos and the lookout shack.
	-------------------------------------------------------------------------------------------
	section("Ridge")
	local hoodoos = {
		{ -150, -131, 14 }, { -110, -127, 12 }, { -65, -133, 15 }, { -32, -128, 11 },
		{ 32, -128, 11 }, { 65, -133, 15 }, { 110, -127, 12 }, { 150, -131, 14 },
	}
	for i, h in hoodoos do
		hoodoo(h[1], 12, h[2], h[3], i)
	end
	for _, s in { -1, 1 } do
		boulder(s * 172, 12, -133, 5, 2)
		boulder(s * 92, 12, -136, 4, 3)
		lamp(s * 48, 12, -138.5, 8)
	end
	-- lookout shack: X -10..10, Z -140..-126, floor = ridge (Y 12), doors west/east, window south
	wall(false, -10, 10, -126, -125, 12, 22, { { -6, 6, 15.5, 19.5 } }, P.planks, "ShackWallS")
	wall(true, -140, -125, -10, -9, 12, 22, { { -137, -129, 12, 21.5 } }, P.planks, "ShackWallW")
	wall(true, -140, -125, 9, 10, 12, 22, { { -137, -129, 12, 21.5 } }, P.planks, "ShackWallE")
	blk(-11, 22, -141, 11, 23, -124, P.rust, "ShackRoof")
	blk(-8, 12, -139.5, -2, 15, -137.5, P.planksDark, "ShackDesk")
	blk(4, 12, -139.5, 8, 18, -137.5, P.metal, "ShackCabinet")

	-------------------------------------------------------------------------------------------
	-- Ore terrace (north lane, Y 6): crusher house, conveyor, ore loaders, carts and timbers.
	-------------------------------------------------------------------------------------------
	section("OreTerrace")
	local T = 6
	-- crusher house X -14..14, Z -112..-78, walls to Y 22, doors on all four sides
	local CH = 22
	wall(false, -14, 14, -112, -111, T, CH, { { -4, 4, T, T + 10 } }, P.rust, "CrusherWallN")
	wall(false, -14, 14, -79, -78, T, CH, { { -4, 4, T, T + 10 } }, P.rust, "CrusherWallS")
	wall(true, -111, -79, -14, -13, T, CH, { { -100, -92, T, T + 10 }, { -91, -85, T + 4, T + 8 } }, P.rust, "CrusherWallW")
	wall(true, -111, -79, 13, 14, T, CH, { { -100, -92, T, T + 10 }, { -91, -85, T + 4, T + 8 } }, P.rust, "CrusherWallE")
	blk(-15, CH, -113, 15, CH + 1, -77, P.rustDark, "CrusherRoof")
	blk(-14.3, T + 11, -112.3, 14.3, T + 12, -111.9, P.paintGreen, "CrusherBand")
	blk(-14.3, T + 11, -78.1, 14.3, T + 12, -77.7, P.paintGreen, "CrusherBand")
	-- jaw crusher machine against the north wall, feed hopper above it, catch bin in front
	blk(-9, T, -111, 9, T + 7, -105, P.metal, "CrusherBody")
	blk(-6, T + 7, -110, 6, T + 12, -106, P.rustDark, "CrusherJaw")
	wedge(CFrame.new(0, T + 14, -108) * CFrame.Angles(0, math.pi, 0), Vector3.new(10, 4, 6), P.rust, "FeedHopper")
	blk(-12.5, T, -84, -7, T + 3.5, -79, P.rust, "CatchBin")
	blk(7, T, -84, 12.5, T + 3.5, -79, P.rust, "CatchBin")
	cylH(0, T + 2, -103.5, 16, 1.6, false, P.metal, "Flywheel")

	-- conveyor: belt Z -98..-94 at Y 17..18 from the crusher walls out to each loader bin
	for _, s in { -1, 1 } do
		local x0, x1 = s * 14, s * 102
		blk(x0, 17, -98, x1, 18, -94, P.ore, "ConveyorBelt")
		blk(x0, 18, -98.4, x1, 19.2, -98, P.rust, "ConveyorSide")
		blk(x0, 18, -94, x1, 19.2, -93.6, P.rust, "ConveyorSide")
		blk(x0, 18, -97.6, x1, 18.6, -94.4, P.ore, "OreOnBelt")
		for x = 22, 94, 18 do
			local cx = s * x
			blk(cx - 0.6, T, -99.2, cx + 0.6, 17, -98, P.rustDark, "ConveyorLeg")
			blk(cx - 0.6, T, -94, cx + 0.6, 17, -92.8, P.rustDark, "ConveyorLeg")
			blk(cx - 0.6, 15.6, -99.2, cx + 0.6, 16.4, -92.8, P.rust, "ConveyorCross")
			blk(cx - 2.5, T, -100, cx + 2.5, T + 1, -92, P.sandstoneDark, "ConveyorFooting")
		end
	end

	-- ore loaders at |X| 100..124, Z -100..-76: bin on four legs (Y 16..24), chute, cribs
	for _, s in { -1, 1 } do
		local xc, zc = s * 112, -88
		for _, c in { { -9, -9 }, { 9, -9 }, { -9, 9 }, { 9, 9 } } do
			blk(xc + c[1] - 1, T, zc + c[2] - 1, xc + c[1] + 1, 16, zc + c[2] + 1, P.timber, "LoaderLeg")
		end
		blk(xc - 10.5, 16, zc - 10.5, xc + 10.5, 17, zc + 10.5, P.planksDark, "LoaderDeck")
		blk(xc - 10, 17, zc - 10, xc + 10, 24, zc - 9, P.planks, "LoaderBin")
		blk(xc - 10, 17, zc + 9, xc + 10, 24, zc + 10, P.planks, "LoaderBin")
		blk(xc - 10, 17, zc - 9, xc - 9, 24, zc + 9, P.planks, "LoaderBin")
		blk(xc + 9, 17, zc - 9, xc + 10, 24, zc + 9, P.planks, "LoaderBin")
		blk(xc - 9, 17, zc - 9, xc + 9, 22, zc + 9, P.ore, "LoaderOre")
		box(CFrame.new(xc + s * 12, 13.5, zc) * CFrame.Angles(0, 0, s * 0.6), Vector3.new(7, 1, 5), P.rust, "LoaderChute")
		-- cover: timber cribs on the corners and an ore pile, all off the zone centre
		blk(xc - 7, T, zc - 7, xc - 3, T + 4, zc - 3, P.timber, "Crib")
		blk(xc + 3, T, zc + 3, xc + 7, T + 4, zc + 7, P.timber, "Crib")
		boulder(xc + s * 14, T, zc + 13, 5, 4)
		oreCart(xc - s * 5, T, zc + 5)
	end

	-- terrace cover, mirrored: carts on the spur rail, ore piles, timber stacks, sheds
	blk(-160, T, -70.4, 160, T + 0.3, -69.8, P.metal, "SpurRail")
	blk(-160, T, -66.2, 160, T + 0.3, -65.6, P.metal, "SpurRail")
	for _, s in { -1, 1 } do
		oreCart(s * 30, T + 0.3, -68)
		oreCart(s * 68, T + 0.3, -68)
		oreCart(s * 150, T + 0.3, -68)
		boulder(s * 56, T, -112, 6, 1)
		boulder(s * 150, T, -106, 6, 2)
		boulder(s * 186, T, -76, 6, 5)
		timberStack(s * 46, T, -82, 10, false)
		timberStack(s * 94, T, -106, 10, false)
		timberStack(s * 140, T, -88, 10, true)
		timberStack(s * 172, T, -100, 10, true)
		barrels(s * 26, T, -116, 3)
		-- tool shed on the terrace (crouch-high windows, open front)
		wall(true, -84, -74, s * 60, s * 61, T, T + 9, {}, P.planks, "ShedWall")
		wall(false, s * 52, s * 61, -84, -83, T, T + 9, {}, P.planks, "ShedWall")
		wall(false, s * 52, s * 61, -75, -74, T, T + 9, {}, P.planks, "ShedWall")
		blk(s * 51, T + 9, -85, s * 62, T + 9.8, -73, P.rust, "ShedRoof")
		lamp(s * 34, T, -103, 10)
		lamp(s * 124, T, -66, 10)
	end

	-------------------------------------------------------------------------------------------
	-- Dry wash (X -14..14, Z -60..124, floor Y -8) and the trestle bridge (Z -8..8).
	-------------------------------------------------------------------------------------------
	section("DryWash")
	local W = -8
	-- bank stairs: north pair (Z -56..-40), south pair (Z 76..92), along the banks
	stairs(-14, -56, -8, -40, "-Z", W, 0, P.sandstoneDark)
	stairs(8, -56, 14, -40, "-Z", W, 0, P.sandstoneDark)
	stairs(-14, 76, -8, 92, "+Z", W, 0, P.sandstoneDark)
	stairs(8, 76, 14, 92, "+Z", W, 0, P.sandstoneDark)
	-- dry falls at the north end: rubble against the terrace face
	boulder(0, W, -56, 6, 6)
	boulder(5, W, -27, 5, 7)
	boulder(-6, W, 32, 6, 8)
	boulder(6, W, 56, 5, 9)
	boulder(-7, W, 117, 5, 10)
	boulder(7, W, 70, 4, 3)
	-- driftwood and a dead cottonwood trunk
	box(CFrame.new(-3, W + 0.6, -14) * CFrame.Angles(0, 0.5, 0), Vector3.new(10, 1.2, 1.2), P.timber, "Driftwood")
	box(CFrame.new(3, W + 0.8, 20) * CFrame.Angles(0, -0.3, 0), Vector3.new(14, 1.6, 1.6), P.timber, "DeadTrunk")

	-- trestle bridge: deck X -18..18 (overlapping both banks by 4), Z -8..8, top at Y 0
	section("TrestleBridge")
	blk(-18, -1, -8, 18, 0, 8, P.planks, "BridgeDeck")
	for _, z in { -6, 0, 6 } do
		blk(-16, -1.8, z - 0.6, 16, -1, z + 0.6, P.timber, "Stringer")
	end
	for _, x in { -12, -4, 4, 12 } do
		blk(x - 0.7, -2.6, -8, x + 0.7, -1.8, 8, P.timber, "CapBeam")
		for _, z in { -7, 0, 7 } do
			blk(x - 0.6, W, z - 0.6, x + 0.6, -2.6, z + 0.6, P.timber, "TrestlePost")
			blk(x - 1, W, z - 1, x + 1, W + 0.8, z + 1, P.sandstoneDark, "PostFooting")
		end
		-- X-bracing in the bent plane (thin, inside the bent line)
		for _, sgn in { -1, 1 } do
			box(CFrame.new(x, -5.3, sgn * 3.5) * CFrame.Angles(sgn * 0.62, 0, 0), Vector3.new(0.4, 0.4, 8.6), P.timber, "Brace")
		end
	end
	-- railings with posts (3.5 tall), open at both ends
	for _, z in { -8, 8 } do
		local zi = if z < 0 then z + 0.5 else z - 0.5
		blk(-18, 3, math.min(z, zi), 18, 3.5, math.max(z, zi), P.timber, "Handrail")
		for x = -18, 18, 6 do
			blk(x - 0.25, 0, math.min(z, zi), x + 0.25, 3, math.max(z, zi), P.timber, "RailPost")
		end
	end
	-- hanging lanterns at the bridge ends
	lamp(-19, 0, -9.5, 9)
	lamp(19, 0, 9.5, 9)

	-------------------------------------------------------------------------------------------
	-- Main street (middle lane, Y 0, Z -60..22).
	-------------------------------------------------------------------------------------------
	section("MainStreet")
	for _, s in { -1, 1 } do
		-- assay office (west) / fuel depot (east): X 92..118, Z -50..-30, doors south and inner end
		local xa, xb = s * 92, s * 118
		local inner, outer = xa, xb -- inner faces the map centre, outer faces the base
		wall(false, xa, xb, -50, -49, 0, 11, { { s * 98, s * 104, 4, 8 } }, P.plaster, "OfficeWallN")
		wall(false, xa, xb, -31, -30, 0, 11, { { s * 100, s * 108, 0, 10 } }, P.plaster, "OfficeWallS")
		wall(true, -49, -31, inner, inner + s * 1, 0, 11, { { -44, -36, 0, 10 } }, P.plaster, "OfficeWallInner")
		wall(true, -49, -31, outer, outer - s * 1, 0, 11, { { -43, -37, 4, 8 } }, P.plaster, "OfficeWallOuter")
		blk(xa - s * 1, 11, -51, xb + s * 1, 12, -29, P.rust, "OfficeRoof")
		blk(s * 100, 11, -29, s * 110, 11.5, -26, P.rustDark, "Awning")
		blk(s * 108, 0, -47, s * 116, 3.5, -44, P.planksDark, "Counter")
		blk(s * 112, 0, -38, s * 116, 6, -33, if s < 0 then P.metal else P.rust, if s < 0 then "AssaySafe" else "FuelPump")
		-- porch + hitching rail outside the south door
		blk(s * 96, 0, -30, s * 114, 0.6, -27, P.planksDark, "Porch")
		blk(s * 94, 2.4, -24.6, s * 106, 2.8, -24.2, P.timber, "HitchRail")
		for _, x in { 94, 106 } do
			blk(s * x - 0.2, 0, -24.6, s * x + 0.2, 2.4, -24.2, P.timber, "HitchPost")
		end

		-- water towers on the street, and a trough beside each
		waterTower(s * 60, -32)
		blk(s * 64, 0, -18, s * 72, 2.6, -15, P.planksDark, "Trough")
		blk(s * 64.4, 2, -17.6, s * 71.6, 2.4, -15.4, P.water, "TroughWater")

		-- cover across the street (every 15..25 studs along X)
		oreWagon(s * 132, -5, if s < 0 then P.rust else P.paintGreen)
		boulder(s * 150, 0, -36, 6, 2)
		boulder(s * 28, 0, -40, 5, 3)
		boulder(s * 30, 0, 12, 5, 4)
		barrels(s * 88, 0, 8, 4)
		crate(s * 98, 0, 8, 4)
		crate(s * 101.5, 0, 12, 3, 0.4)
		timberStack(s * 46, 0, -8, 10, false)
		timberStack(s * 120, 0, 14, 8, false)
		crate(s * 80, 0, -24, 4, 0.2)
		blk(s * 146, 0, 10, s * 150, 3, 16, P.planksDark, "Bench")
		lamp(s * 24, 0, -20, 10)
		lamp(s * 150, 0, -50, 10)
	end

	-------------------------------------------------------------------------------------------
	-- Bunkhouse (west) and mess hall (east): X 40..100, Z 26..54, walk-through, doors 8 x 10.
	-------------------------------------------------------------------------------------------
	for _, s in { -1, 1 } do
		section(if s < 0 then "Bunkhouse" else "MessHall")
		local x0, x1 = s * 40, s * 100
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		local doors: { Opening } = {
			{ s * 50, s * 58, 0, 10 },
			{ s * 64, s * 76, 4, 8 },
			{ s * 82, s * 90, 0, 10 },
		}
		local body = if s < 0 then P.planks else P.plaster
		wall(false, lo, hi, 26, 27, 0, 12, doors, body, "LongWall")
		wall(false, lo, hi, 53, 54, 0, 12, doors, body, "LongWall")
		wall(true, 27, 53, lo, lo + 1, 0, 12, { { 36, 44, 0, 10 } }, body, "EndWall")
		wall(true, 27, 53, hi - 1, hi, 0, 12, { { 36, 44, 0, 10 } }, body, "EndWall")
		blk(lo - 1, 12, 25, hi + 1, 13, 55, P.rust, "Roof")
		blk(lo - 1, 13, 38, hi + 1, 15, 42, P.rustDark, "RoofRidge")
		blk(lo, 0, 27, hi, 0.2, 53, P.planksDark, "Floorboards")
		-- interior: bunks against the long walls (between the doors), tables, stove
		for _, bx in { 46, 61, 79, 94 } do
			blk(s * bx - 2.5, 0.2, 27, s * bx + 2.5, 4, 31, P.planksDark, if s < 0 then "Bunk" else "Bench")
			blk(s * bx - 2.5, 0.2, 49, s * bx + 2.5, 4, 53, P.planksDark, if s < 0 then "Bunk" else "Bench")
		end
		blk(s * 52 - 3, 0.2, 37, s * 52 + 3, 3.2, 43, P.planks, "Table")
		blk(s * 88 - 3, 0.2, 37, s * 88 + 3, 3.2, 43, P.planks, "Table")
		cylY(s * 70, 0.2, 30.5, 5, 2.6, P.rustDark, "Stove")
		cylY(s * 70, 5, 30.5, 13, 0.8, P.rustDark, "Flue")
		blk(s * 68, 9.5, 39.6, s * 72, 10, 40.4, P.lamp, "CeilingLamp")
		-- porch along the south side and a sign board on the north side
		blk(lo, 0, 54, hi, 0.5, 57, P.planksDark, "Porch")
		blk(s * 64, 8.5, 25.6, s * 76, 10.5, 26, if s < 0 then P.sable else P.talon, "SignBoard")
	end

	-- between the buildings and the wash, and towards the bases: rotation alleys with cover
	section("Alleys")
	for _, s in { -1, 1 } do
		boulder(s * 27, 0, 36, 6, 5)
		timberStack(s * 120, 0, 40, 10, true)
		crate(s * 140, 0, 30, 4)
		crate(s * 140, 0, 34.5, 4, 0.3)
		crate(s * 140, 4, 32, 4, 0.1)
		barrels(s * 150, 0, 48, 3)
	end

	-------------------------------------------------------------------------------------------
	-- Lower camp (south lane, Y 0, Z 56..124): ore wagon spur, tool yard / powder magazine.
	-------------------------------------------------------------------------------------------
	section("LowerCamp")
	for _, s in { -1, 1 } do
		-- wagon spur rails Z 66 and two wagons per side
		blk(s * 20, 0, 63.4, s * 150, 0.3, 64, P.metal, "SpurRail")
		blk(s * 20, 0, 68, s * 150, 0.3, 68.6, P.metal, "SpurRail")
		oreWagon(s * 45, 66, P.rust)
		oreWagon(s * 112, 66, if s < 0 then P.paintGreen else P.rust)
		-- walled yard X 96..128, Z 84..108: west (tool yard) / east (powder magazine, bomb site B)
		local xa, xb = s * 96, s * 128
		local inner, outer = xa, xb -- inner faces the map centre, outer faces the base
		local stone = P.sandstoneDark
		wall(false, xa, xb, 84, 86, 0, 8, { { s * 104, s * 112, 0, 8 } }, stone, "YardWallN")
		wall(false, xa, xb, 106, 108, 0, 8, { { s * 112, s * 118, 0, 8 } }, stone, "YardWallS")
		wall(true, 86, 106, inner, inner + s * 2, 0, 8, { { 92, 100, 0, 8 } }, stone, "YardWallInner")
		wall(true, 86, 106, outer, outer - s * 2, 0, 8, {}, stone, "YardWallOuter")
		-- vault against the outer wall, with a heavy door frame
		local vx0, vx1 = s * 120, s * 126
		blk(vx0, 0, 87, vx1, 10, 105, P.rock, if s < 0 then "ToolVault" else "PowderVault")
		blk(vx0 - s * 0.3, 0, 92, vx0, 7, 100, P.rustDark, "VaultDoor")
		blk(vx0 - s * 1, 10, 86, vx1 + s * 1, 11, 106, P.rust, "VaultRoof")
		-- cover inside the yard (off the zone centre at |X| 110, Z 96)
		crate(s * 101, 0, 102, 4)
		crate(s * 101, 0, 89.5, 3.5, 0.3)
		crate(s * 116, 0, 89.5, 4, 0.1)
		barrels(s * 115, 0, 101, 3)
		-- rock outcrops and camp props
		boulder(s * 76, 0, 92, 8, 6)
		boulder(s * 40, 0, 110, 7, 7)
		boulder(s * 145, 0, 112, 6, 8)
		timberStack(s * 60, 0, 82, 10, false)
		timberStack(s * 140, 0, 92, 8, true)
		crate(s * 30, 0, 90, 4, 0.25)
		crate(s * 82, 0, 116, 4)
		-- canvas tents (closed, low): X 58..70, Z 100..112
		blk(s * 58, 0, 100, s * 70, 4, 112, P.canvas, "Tent")
		wedge(CFrame.new(s * 64, 5, 103) * CFrame.Angles(0, math.pi, 0), Vector3.new(12, 2, 6), P.canvas, "TentRoof")
		wedge(CFrame.new(s * 64, 5, 109), Vector3.new(12, 2, 6), P.canvas, "TentRoof")
		lamp(s * 92, 0, 78, 10)
		lamp(s * 26, 0, 118, 10)
	end

	-------------------------------------------------------------------------------------------
	-- Rock-cut tunnel (south flank): X -165..165, interior Z 128..150, ceiling Y 12.
	-------------------------------------------------------------------------------------------
	section("Tunnel")
	local tunnelDoors: { Opening } = {
		{ -104, -96, 0, 10 }, { -34, -26, 0, 10 }, { 26, 34, 0, 10 }, { 96, 104, 0, 10 },
	}
	wall(false, -165, 165, 124, 128, 0, 14, tunnelDoors, P.rock, "TunnelWallN")
	blk(-165, 12, 128, 165, 18, 150, P.rock, "TunnelCeiling")
	blk(-166, 14, 122, 166, 20, 128, P.sandstoneDark, "TunnelBrow")
	-- shoring sets every 24 studs: posts at the walls and a cap beam under the ceiling
	for x = -144, 144, 24 do
		blk(x - 0.6, 0, 128, x + 0.6, 12, 129.2, P.timber, "Shoring")
		blk(x - 0.6, 0, 148.8, x + 0.6, 12, 150, P.timber, "Shoring")
		blk(x - 0.6, 10.8, 128, x + 0.6, 12, 150, P.timber, "ShoringCap")
		blk(x - 0.3, 9.6, 138.6, x + 0.3, 10.8, 139.4, P.lamp, "TunnelLamp")
	end
	blk(-160, 0, 138.6, 160, 0.3, 139.2, P.metal, "TunnelRail")
	blk(-160, 0, 141.8, 160, 0.3, 142.4, P.metal, "TunnelRail")
	for _, s in { -1, 1 } do
		-- zig-zag baffles at each end stop end-to-end shots
		blk(s * 150, 0, 128, s * 147, 12, 143, P.rock, "TunnelBaffle")
		blk(s * 138, 0, 135, s * 135, 12, 150, P.rock, "TunnelBaffle")
		-- carts and a collapse in the middle stretch
		oreCart(s * 52, 0.3, 140.5)
		oreCart(s * 118, 0.3, 140.5)
		boulder(s * 12, 0, 132, 5, 9)
		timberStack(s * 80, 0, 146, 8, false)
	end

	-------------------------------------------------------------------------------------------
	-- Team bases: Sable west yard, Talon east yard (|X| 174..210). Rock rampart with three
	-- gaps (street, south lane, tunnel) and an outer baffle in front of the two open-air gaps.
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
		local gaps: { Opening } = {
			{ GAP_STREET[1], GAP_STREET[2], 0, 18 },
			{ GAP_SOUTH[1], GAP_SOUTH[2], 0, 18 },
			{ GAP_TUNNEL[1], GAP_TUNNEL[2], 0, 18 },
		}
		wall(true, -60, 150, s * RAMPART[1], s * RAMPART[2], 0, 16, gaps, P.rock, "Rampart")
		-- rough crest stones on the rampart
		for z = -50, 140, 22 do
			box(CFrame.new(s * 172, 16.6, z) * CFrame.Angles(0, 0.3, 0.1), Vector3.new(5, 2.4, 7), P.rockDark, "Crest")
		end
		-- outer baffles (map side) in front of the street and south gaps
		blk(s * BAFFLE[1], 0, -40, s * BAFFLE[2], 14, 10, P.rock, "Baffle")
		blk(s * BAFFLE[1], 0, 62, s * BAFFLE[2], 14, 108, P.rock, "Baffle")
		blk(s * (BAFFLE[1] - 0.3), 6, -40, s * BAFFLE[1], 7.5, 10, accent, "BaffleStripe")
		blk(s * (BAFFLE[1] - 0.3), 6, 62, s * BAFFLE[1], 7.5, 108, accent, "BaffleStripe")
		-- gap frames (timber headers) and team colour posts
		for _, g in { GAP_STREET, GAP_SOUTH, GAP_TUNNEL } do
			blk(s * RAMPART[1], 0, g[1] - 1, s * (RAMPART[1] - 1), 14, g[1], accent, "GapPost")
			blk(s * RAMPART[1], 0, g[2], s * (RAMPART[1] - 1), 14, g[2] + 1, accent, "GapPost")
		end
		-- base yard: changehouse shed against the back cliff, carts, barrels, lamps
		blk(s * 206, 0, -40, s * 210, 12, 90, P.planksDark, "Changehouse")
		blk(s * 204, 12, -42, s * 210, 13, 92, P.rust, "ChangehouseRoof")
		for z = -36, 84, 30 do
			blk(s * 205.6, 3, z - 4, s * 206, 9, z + 4, accent, "Banner")
		end
		barrels(s * 204, 0, 104, 4)
		crate(s * 200, 0, 116, 4)
		oreCart(s * 196, 0, 130)
		lamp(s * 178, 0, -55, 10)
		lamp(s * 178, 0, 120, 10)
		for _, z in { -40, -10, 20, 50, 80 } do
			blk(s * 193 - 0.5, 0, z - 6, s * 193 + 0.5, 0.06, z + 6, accent, "BayMarking")
		end
		-- base terrace: parapet along the edge above the yard (opening at the yard stairs) and a
		-- rampart on the terrace with one 10-wide gap, so the north lane enters the base through
		-- a single choke instead of overlooking the spawn yard from the terrace edge
		blk(s * 174, T, -62, s * 193, T + 4, -60.6, P.rock, "Parapet")
		blk(s * 205, T, -62, s * 210, T + 4, -60.6, P.rock, "Parapet")
		wall(true, -122, -62, s * RAMPART[1], s * RAMPART[2], T, T + 12, { { -96, -86, T, T + 12 } }, P.rock, "TerraceRampart")
		blk(s * RAMPART[1], T, -97, s * (RAMPART[1] - 1), T + 11, -96, accent, "GapPost")
		blk(s * RAMPART[1], T, -86, s * (RAMPART[1] - 1), T + 11, -85, accent, "GapPost")

		-- team spawns: two columns of five behind the rampart, each facing the nearest rampart gap
		-- (facing straight at the rampart put a rock wall 12 studs in front of the camera)
		for _, z in { -40, -10, 20, 50, 80 } do
			local gapZ = if z < 35 then (GAP_STREET[1] + GAP_STREET[2]) / 2 else (GAP_SOUTH[1] + GAP_SOUTH[2]) / 2
			for _, x in { 186, 200 } do
				spawnPart(s * x, 0, z + (if x == 200 then 6 else 0), s * RAMPART[1], gapZ, team, false)
			end
		end
	end

	-------------------------------------------------------------------------------------------
	-- FFA spawns spread over every zone (each on a known floor top).
	-------------------------------------------------------------------------------------------
	local ffa = {
		{ -196, 0, 112, 0, 112 },
		{ 196, 0, -28, 0, -28 },
		{ -192, 6, -88, 0, -88 },
		{ 192, 6, -104, 0, -104 },
		{ -150, 6, -78, 0, -78 },
		{ -40, 6, -112, 0, -112 },
		{ 58, 6, -63, 0, -63 },
		{ 150, 6, -112, 0, -112 },
		{ -120, 12, -134, 0, -134 },
		{ 122, 12, -132, 0, -132 },
		{ -140, 0, -24, 0, -24 },
		{ 140, 0, 0, 0, 0 },
		{ -42, 0, -26, 0, -26 },
		{ 42, 0, 4, 0, 4 },
		{ 0, -7.9, -30, 0, 0 },
		{ -140, 0, 76, 0, 76 },
		{ 140, 0, 118, 0, 118 },
		{ -60, 0, 96, 0, 96 },
		{ 62, 0, 78, 0, 78 },
		{ -80, 0, 133, 0, 133 },
		{ 80, 0, 133, 0, 133 },
		{ 0, 0, 145, 40, 145 },
	}
	for _, f in ffa do
		spawnPart(f[1], f[2], f[3], f[4], f[5], nil, true)
	end

	-------------------------------------------------------------------------------------------
	-- Objectives (invisible zones; bottom face on the floor, 10 tall).
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
		for k, v in attrs do
			p:SetAttribute(k, v)
		end
		p.Parent = objectives
	end

	-- Domination: A west street, B on the trestle bridge, C east street.
	zone("FlagA", "Flag", -112, 0, -6, 18, 18, { Label = "A" })
	zone("FlagB", "Flag", 0, 0, 0, 18, 14, { Label = "B" })
	zone("FlagC", "Flag", 112, 0, -6, 18, 18, { Label = "C" })
	-- Hardpoint rotation: bridge -> bunkhouse -> crusher house -> mess hall -> wash bend.
	zone("Hardpoint1", "Hardpoint", 0, 0, 0, 24, 16, { Order = 1 })
	zone("Hardpoint2", "Hardpoint", -70, 0.2, 40, 26, 18, { Order = 2 })
	zone("Hardpoint3", "Hardpoint", 0, T, -93, 22, 20, { Order = 3 })
	zone("Hardpoint4", "Hardpoint", 70, 0.2, 40, 26, 18, { Order = 4 })
	zone("Hardpoint5", "Hardpoint", 0, -7.9, 104, 18, 22, { Order = 5 })
	-- Search and Destroy: Sable attacks first, Talon defends the east loader and powder magazine.
	zone("BombSiteA", "BombSite", 112, T, -88, 14, 14, { Label = "A" })
	zone("BombSiteB", "BombSite", 110, 0, 96, 14, 14, { Label = "B" })

	-------------------------------------------------------------------------------------------
	-- Lobby camera (frames the trestle bridge and the conveyor behind it) + model attributes.
	-------------------------------------------------------------------------------------------
	local cam = Instance.new("Part")
	cam.Name = "LobbyCamera"
	cam.Size = Vector3.new(1, 1, 1)
	cam.CFrame = CFrame.lookAt(Vector3.new(62, 34, 78), Vector3.new(0, 2, -30))
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
