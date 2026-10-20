--!strict
--[[
	Dustline Terminal: an abandoned regional bus/rail terminal on the edge of the desert.
	Medium 6v6 TDM map, ~360 x 260 studs playable (boundary inner faces at X = +-180, Z = +-128).

	Axes: +X = east, -Z = north (top of the ASCII sketch in docs/maps/DustlineTerminal.md).
	All walkable ground has its top surface at Y = 0, except the sunken track bed (Y = -3)
	and the control office upper floor (Y = 13).

	Bands, north -> south:
	  Z -128..-116  North alley (flank, behind a wall of double-stacked containers)
	  Z -116..-50   Loading yard (north lane: cars, barriers, taxi booth, loading dock)
	  Z  -50.. 21   Terminal hall (middle lane: interior, ticket office + departures pylon)
	  Z   21.. 60   Platform A (control office, 2 storeys, exterior stairs)
	  Z   60.. 74   Sunken track bed (walk-through train car, flatcar)
	  Z   74.. 92   Platform B (canopy)
	  Z   92..113   Bus bays (south lane: two walk-through buses)
	  Z  113..128   Service tunnel (south flank)
	Sable spawn = west depot (X < -122), Talon spawn = east freight gate (X > 122).
	A thin continuous base slab (Y -8..-7) under the whole footprint is the bottom of the ground
	(BoundsMin.Y = -8), because the track bed reaches lower than the other ground pieces.

	Objectives (see docs/maps/DustlineTerminal.md, "Objectives"):
	  Flags     A west hall half, B Platform A in front of the office, C east hall half
	  Hardpoint 1 ticket hall centre, 2 west bus bays, 3 loading dock, 4 control office, 5 service tunnel
	  S&D       Sable attacks in round 1; sites A (east loading yard) and B (east bus bays)

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

local M = Enum.Material

-- Dusty late-afternoon palette.
local P = {
	concrete = style(M.Concrete, 178, 166, 146),
	concreteDark = style(M.Concrete, 128, 118, 104),
	concreteWarm = style(M.Concrete, 196, 172, 136),
	plaster = style(M.Plaster, 214, 198, 170),
	tile = style(M.CeramicTiles, 192, 178, 152),
	tileDark = style(M.CeramicTiles, 150, 132, 108),
	asphalt = style(M.Asphalt, 92, 86, 80),
	ballast = style(M.Pebble, 122, 106, 88),
	sand = style(M.Sand, 204, 178, 136),
	rust = style(M.CorrodedMetal, 134, 80, 50),
	rustDark = style(M.CorrodedMetal, 96, 62, 44),
	metal = style(M.Metal, 116, 114, 108),
	metalDark = style(M.DiamondPlate, 78, 76, 72),
	paintTeal = style(M.SmoothPlastic, 78, 126, 120),
	paintRed = style(M.SmoothPlastic, 158, 76, 58),
	paintYellow = style(M.SmoothPlastic, 214, 176, 80),
	paintCream = style(M.SmoothPlastic, 226, 212, 184),
	busCream = style(M.Metal, 214, 196, 160),
	wood = style(M.WoodPlanks, 130, 98, 68),
	woodDark = style(M.Wood, 98, 72, 52),
	fabric = style(M.Fabric, 122, 70, 56),
	tarp = style(M.Fabric, 112, 116, 84),
	glass = style(M.Glass, 160, 186, 182, 0.55),
	rubber = style(M.Rubber, 44, 42, 40),
	board = style(M.SmoothPlastic, 40, 42, 44),
	lamp = style(M.Neon, 255, 206, 150),
	grass = style(M.Grass, 128, 120, 72),
	sable = style(M.SmoothPlastic, 64, 90, 110),
	talon = style(M.SmoothPlastic, 182, 108, 50),
}

local MapModule = {}

MapModule.id = "DustlineTerminal"
MapModule.displayName = "Dustline Terminal"

-- Warm, hazy late-afternoon desert. Only valid Lighting properties.
MapModule.lighting = {
	ClockTime = 16.6,
	GeographicLatitude = 32,
	Brightness = 2.6,
	ExposureCompensation = 0.1,
	Ambient = Color3.fromRGB(112, 96, 82),
	OutdoorAmbient = Color3.fromRGB(150, 128, 104),
	ColorShift_Top = Color3.fromRGB(255, 212, 160),
	ColorShift_Bottom = Color3.fromRGB(96, 72, 56),
	EnvironmentDiffuseScale = 0.45,
	EnvironmentSpecularScale = 0.25,
	ShadowSoftness = 0.35,
	GlobalShadows = true,
	FogColor = Color3.fromRGB(214, 186, 148),
	FogStart = 250,
	FogEnd = 1400,
}

-- Valid Atmosphere properties.
MapModule.atmosphere = {
	Density = 0.34,
	Offset = 0.12,
	Color = Color3.fromRGB(224, 192, 150),
	Decay = Color3.fromRGB(164, 112, 78),
	Glare = 0.45,
	Haze = 1.9,
}

MapModule.killY = -40

-- Playable box (outer faces of the boundary walls; Y from the bottom of the base slab).
local BOUNDS_MIN = Vector3.new(-184, -8, -132)
local BOUNDS_MAX = Vector3.new(184, 40, 132)

-- Spawn gap layout on each team's screen wall (Z ranges), shared by geometry and docs.
local SCREEN_X = 122 -- screen wall centre line |X|
local GAPS = { { -100, -88 }, { -20, -8 }, { 44, 56 }, { 96, 108 } }

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

	-- Vertical cylinder (post, drum, column).
	local function cylY(x: number, y0: number, z: number, y1: number, d: number, st: Style, name: string?): Part
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(y1 - y0, d, d)
		p.CFrame = CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
		finish(p, st, name)
		return p
	end

	-- Horizontal cylinder along X (pipes) or Z (wheels).
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
			-- step i occupies the i-th slice counted from the low end
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
		box(CFrame.new(x, y + s / 2, z) * CFrame.Angles(0, yaw or 0, 0), Vector3.new(s, s, s), P.wood, "Crate")
	end

	local function drums(x: number, z: number, n: number)
		local offs = { { 0, 0 }, { 2.4, 0.6 }, { 0.9, 2.3 }, { -1.6, 1.8 } }
		for i = 1, math.min(n, #offs) do
			local o = offs[i]
			cylY(x + o[1], 0, z + o[2], 3.2, 2.2, if i % 2 == 0 then P.paintTeal else P.rust, "Drum")
		end
	end

	-- Derelict car: body + cabin + 4 wheels. Long axis along X before yaw.
	local function car(x: number, z: number, yaw: number, st: Style)
		local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
		box(base * CFrame.new(0, 2.1, 0), Vector3.new(10, 2.2, 4.8), st, "CarBody")
		box(base * CFrame.new(-0.6, 4.1, 0), Vector3.new(5.6, 1.8, 4.4), st, "CarCabin")
		for _, w in { { -3.4, -2.3 }, { 3.4, -2.3 }, { -3.4, 2.3 }, { 3.4, 2.3 } } do
			local p = Instance.new("Part")
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(0.9, 2, 2)
			p.CFrame = base * CFrame.new(w[1], 1, w[2]) * CFrame.Angles(0, math.pi / 2, 0)
			finish(p, P.rubber, "Wheel")
		end
	end

	-- Jersey barrier (2 parts) of length len, along X or Z.
	local function barrier(x: number, z: number, len: number, alongZ: boolean)
		local hx, hz = if alongZ then 1 else len / 2, if alongZ then len / 2 else 1
		blk(x - hx, 0, z - hz, x + hx, 1.2, z + hz, P.concrete, "Barrier")
		local tx, tz = if alongZ then 0.45 else len / 2, if alongZ then len / 2 else 0.45
		blk(x - tx, 1.2, z - tz, x + tx, 3.6, z + tz, P.concrete, "Barrier")
	end

	-- Bench of length len along X or Z, back on the +side if back > 0.
	local function bench(x: number, z: number, len: number, alongZ: boolean)
		local hx, hz = if alongZ then 0.9 else len / 2, if alongZ then len / 2 else 0.9
		blk(x - hx, 0, z - hz, x + hx, 1.6, z + hz, P.woodDark, "Bench")
		local bx, bz = if alongZ then 0.25 else len / 2, if alongZ then len / 2 else 0.25
		blk(x - bx, 1.6, z - bz, x + bx, 3.4, z + bz, P.wood, "BenchBack")
	end

	local function lampPost(x: number, z: number, h: number)
		cylY(x, 0, z, h, 0.8, P.metalDark, "LampPost")
		blk(x - 0.5, h - 0.6, z - 0.5, x + 0.5, h + 0.4, z + 0.5, P.metal, "LampHead")
		blk(x - 0.4, h - 1.0, z - 0.4, x + 0.4, h - 0.6, z + 0.4, P.lamp, "LampBulb")
	end

	local function vending(x: number, z: number, st: Style)
		blk(x - 1.6, 0, z - 1.4, x + 1.6, 7, z + 1.4, st, "Vending")
		blk(x - 1.2, 2.5, z - 1.5, x + 1.2, 6.2, z + 1.5, P.glass, "VendingGlass")
	end

	-- Shipping container occupying x0..x1 (along X), z0..z1, from y0 (9 tall).
	local function container(x0: number, x1: number, z0: number, z1: number, y0: number, st: Style)
		blk(x0 + 0.3, y0, z0, x1 - 0.3, y0 + 9, z1, st, "Container")
		blk(x0, y0, z0 - 0.15, x0 + 0.6, y0 + 9, z1 + 0.15, P.rustDark, "ContainerFrame")
		blk(x1 - 0.6, y0, z0 - 0.15, x1, y0 + 9, z1 + 0.15, P.rustDark, "ContainerFrame")
	end

	-------------------------------------------------------------------------------------------
	-- Ground (all tops at Y = 0 except the track bed). Pieces abut exactly: no gaps.
	-------------------------------------------------------------------------------------------
	section("Ground")
	blk(-SCREEN_X, -4, -132, SCREEN_X, 0, -50, P.asphalt, "YardGround")
	blk(-100, -4, -50, 100, 0, 21, P.tile, "HallFloor")
	blk(-SCREEN_X, -4, -50, -100, 0, 21, P.concrete, "PlazaWest")
	blk(100, -4, -50, SCREEN_X, 0, 21, P.concrete, "PlazaEast")
	blk(-SCREEN_X, -4, 21, SCREEN_X, 0, 60, P.concrete, "PlatformA")
	blk(-SCREEN_X, -7, 60, SCREEN_X, -3, 74, P.ballast, "TrackBed")
	blk(-SCREEN_X, -4, 74, SCREEN_X, 0, 92, P.concrete, "PlatformB")
	blk(-SCREEN_X, -4, 92, SCREEN_X, 0, 113, P.asphalt, "BusLane")
	blk(-SCREEN_X, -4, 113, SCREEN_X, 0, 132, P.concreteDark, "TunnelFloor")
	blk(-184, -4, -132, -SCREEN_X, 0, 132, P.concreteWarm, "SableDepotGround")
	blk(SCREEN_X, -4, -132, 184, 0, 132, P.concreteWarm, "TalonGateGround")
	-- continuous base slab under everything (the track bed bottom is lower than the rest)
	blk(-184, -8, -132, 184, -7, 132, P.concreteDark, "BaseSlab")
	-- painted markings (0.06 thick, walkable)
	blk(-SCREEN_X, 0, 57.5, SCREEN_X, 0.06, 59, P.paintYellow, "PlatformEdgeA")
	blk(-SCREEN_X, 0, 75, SCREEN_X, 0.06, 76.5, P.paintYellow, "PlatformEdgeB")
	blk(-SCREEN_X, 0, 91.5, SCREEN_X, 0.3, 92.5, P.concreteWarm, "Curb")
	for _, x in { -100, -78, -56, -34, 34, 56, 78, 100 } do
		blk(x - 0.25, 0, -103, x + 0.25, 0.06, -89, P.paintCream, "ParkingLine")
	end

	-------------------------------------------------------------------------------------------
	-- Boundary: tall perimeter walls (concrete base, rusted sheet upper) with pilasters.
	-------------------------------------------------------------------------------------------
	section("Boundary")
	blk(-184, -4, -132, 184, 18, -128, P.concreteDark, "BoundaryN")
	blk(-184, 18, -132, 184, 30, -128, P.rust, "BoundaryN")
	blk(-184, -4, 128, 184, 18, 132, P.concreteDark, "BoundaryS")
	blk(-184, 18, 128, 184, 30, 132, P.rust, "BoundaryS")
	blk(-184, -4, -128, -180, 18, 128, P.concreteDark, "BoundaryW")
	blk(-184, 18, -128, -180, 30, 128, P.rust, "BoundaryW")
	blk(180, -4, -128, 184, 18, 128, P.concreteDark, "BoundaryE")
	blk(180, 18, -128, 184, 30, 128, P.rust, "BoundaryE")
	for x = -160, 160, 32 do
		blk(x - 1.5, 0, -128, x + 1.5, 30, -126.8, P.concrete, "Pilaster")
		if math.abs(x) > 140 then
			blk(x - 1.5, 0, 126.8, x + 1.5, 30, 128, P.concrete, "Pilaster")
		end
	end
	for z = -96, 96, 48 do
		blk(-180, 0, z - 1.5, -178.8, 30, z + 1.5, P.concrete, "Pilaster")
		blk(178.8, 0, z - 1.5, 180, 30, z + 1.5, P.concrete, "Pilaster")
	end

	-------------------------------------------------------------------------------------------
	-- Terminal hall (middle lane). Shell X -100..100, Z -50..21, walls 20 tall.
	-------------------------------------------------------------------------------------------
	section("TerminalHall")
	local H = 20
	-- north wall (yard side): two doors near the corners, roll-up door panel at centre
	wall(false, -100, 100, -50, -48, 0, H, { { -66, -56, 0, 10 }, { 56, 66, 0, 10 } }, P.plaster, "HallWallN")
	blk(-9, 0, -50.4, 9, 11, -50, P.rust, "RollUpDoor")
	-- south wall (platform side): doors at +-60..70, office door + office window in the middle
	wall(false, -100, 100, 19, 21, 0, H, { { -70, -60, 0, 10 }, { -18, 18, 0, H }, { 60, 70, 0, 10 } }, P.plaster, "HallWallS")
	blk(-18, 0, 19, -4, 15.5, 21, P.plaster, "HallWallS")
	blk(4, 0, 19, 18, 15.5, 21, P.plaster, "HallWallS")
	blk(-4, 10, 19, 4, 15.5, 21, P.plaster, "HallWallS")
	blk(-18, 19, 19, 18, H, 21, P.plaster, "HallWallS")
	-- west / east walls (plaza side)
	for _, s in { -1, 1 } do
		wall(true, -50, 21, s * 98, s * 100, 0, H, { { -40, -32, 0, 10 }, { 4, 12, 0, 10 } }, P.plaster, "HallWallSide")
		-- door awnings
		for _, zc in { -36, 8 } do
			blk(s * 100, 11, zc - 6, s * 103.5, 11.6, zc + 6, P.rust, "Awning")
		end
	end
	-- faded teal band and dado around the exterior
	blk(-100.3, 13, -50.3, 100.3, 14.5, -50, P.paintTeal, "Band")
	blk(-100.3, 13, 21, -24.5, 14.5, 21.3, P.paintTeal, "Band")
	blk(24.5, 13, 21, 100.3, 14.5, 21.3, P.paintTeal, "Band")
	blk(-100.3, 13, -50, -100, 14.5, 21, P.paintTeal, "Band")
	blk(100, 13, -50, 100.3, 14.5, 21, P.paintTeal, "Band")
	-- roof with two skylight slots and cross beams
	blk(-101, H, -51, 101, H + 1, -32, P.rustDark, "HallRoof")
	blk(-101, H, -28, 101, H + 1, -4, P.rustDark, "HallRoof")
	blk(-101, H, 0, 101, H + 1, 22, P.rustDark, "HallRoof")
	for x = -90, 90, 20 do
		blk(x - 0.5, H, -32, x + 0.5, H + 1, -28, P.metalDark, "SkylightBeam")
		blk(x - 0.5, H, -4, x + 0.5, H + 1, 0, P.metalDark, "SkylightBeam")
	end
	-- interior trim: floor border tiles
	blk(-98, 0, -48, 98, 0.05, -46.5, P.tileDark, "TileBorder")
	blk(-98, 0, 17.5, 98, 0.05, 19, P.tileDark, "TileBorder")

	-- centre: ticket office block (Z -40..-6) and departures pylon (Z 0..12)
	blk(-14, 0, -40, 14, 4, -6, P.wood, "TicketCounter")
	blk(-12, 4, -38, 12, 12, -8, P.plaster, "TicketOffice")
	blk(-13.7, 4, -38, -13.4, 10, -8, P.glass, "TicketGlass")
	blk(13.4, 4, -38, 13.7, 10, -8, P.glass, "TicketGlass")
	blk(-14, 10, -40, 14, 12, -6, P.paintTeal, "TicketSign")
	blk(-14.5, 12, -40.5, 14.5, 12.8, -5.5, P.rustDark, "TicketCap")
	blk(-6, 0, 0, 6, 14, 12, P.concrete, "DeparturesPylon")
	blk(-6.3, 8, 1, -6, 12.5, 11, P.board, "DepartureBoard")
	blk(6, 8, 1, 6.3, 12.5, 11, P.board, "DepartureBoard")
	for i = 0, 3 do
		local y = 8.6 + i * 1
		blk(-6.4, y, 2, -6.3, y + 0.35, 10, P.paintYellow, "BoardLine")
		blk(6.3, y, 2, 6.4, y + 0.35, 10, P.paintYellow, "BoardLine")
	end
	bench(-9, 6, 10, true)
	bench(9, 6, 10, true)

	-- halves (mirrored)
	for _, s in { -1, 1 } do
		-- structural columns
		for _, c in { { 34, -30 }, { 70, -30 }, { 34, 4 }, { 70, 4 } } do
			blk(s * c[1] - 1.5, 0, c[2] - 1.5, s * c[1] + 1.5, H, c[2] + 1.5, P.concrete, "Column")
			blk(s * c[1] - 1.8, 0, c[2] - 1.8, s * c[1] + 1.8, 1.2, c[2] + 1.8, P.concreteDark, "ColumnBase")
		end
		-- ticket counters with glass
		blk(s * 76, 0, -17.5, s * 92, 4, -15, P.wood, "Counter")
		blk(s * 76, 4, -16.4, s * 92, 7, -16.1, P.glass, "CounterGlass")
		-- closed kiosk shops against the north wall
		blk(s * 40, 0, -48, s * 52, 10, -42, P.paintCream, "Shop")
		blk(s * 40, 6.5, -42, s * 52, 8, -41.4, if s < 0 then P.paintRed else P.paintTeal, "ShopSign")
		-- waiting benches
		bench(s * 52, -14, 12, false)
		bench(s * 52, -7, 12, false)
		bench(s * 22, -30, 8, true)
		-- luggage trolley + bins
		blk(s * 56, 0, 8, s * 62, 2.6, 11, P.metal, "Trolley")
		crate(s * 58, 2.6, 9.5, 2.4, 0.2)
		cylY(s * 90, 0, -44, 3, 2, P.metalDark, "Bin")
		cylY(s * 26, 0, 14, 3, 2, P.metalDark, "Bin")
		-- hanging lamps
		for _, z in { -40, -14, 12 } do
			blk(s * 52 - 4, 17, z - 0.4, s * 52 + 4, 17.5, z + 0.4, P.lamp, "HallLamp")
		end
	end

	-------------------------------------------------------------------------------------------
	-- Control office: 2 storeys at X -24.5..24.5, Z 21..40.5. Upper floor Y 13.
	-------------------------------------------------------------------------------------------
	section("ControlOffice")
	local FLOOR2 = 13
	for _, s in { -1, 1 } do
		-- side walls: ground side door (Z 22.5..28.5), upper door at top of the exterior stair
		wall(true, 21, 40.5, s * 23.5, s * 24.5, 0, 12, { { 22.5, 28.5, 0, 9.6 } }, P.plaster, "OfficeWallSide")
		wall(true, 21, 40.5, s * 23.5, s * 24.5, 12, 23, { { 30, 37, 12, 22.5 } }, P.plaster, "OfficeWallSide")
		-- exterior stairs: 13 x 1-stud steps rising toward the office
		stairs(s * 24.5, 30, s * 45.3, 37, if s < 0 then "+X" else "-X", 0, FLOOR2, P.concrete)
		blk(s * 24.5, 0, 29.6, s * 45.3, 1, 30, P.paintYellow, "StairEdge")
		-- desks downstairs, consoles upstairs
		blk(s * 9, 0, 28, s * 15, 3, 31.5, P.woodDark, "Desk")
		blk(s * 19, 0, 37, s * 23.5, 6.5, 39.5, P.metal, "Cabinet")
		blk(s * 6, FLOOR2, 36.5, s * 18, FLOOR2 + 3.2, 39.5, P.metalDark, "Console")
		blk(s * 6, FLOOR2 + 3.2, 38.6, s * 18, FLOOR2 + 4.4, 39.5, P.board, "ConsoleScreens")
		blk(s * 14, FLOOR2, 22, s * 20, FLOOR2 + 3, 25, P.woodDark, "MapTable")
	end
	-- south wall: ground door + 2 windows, upper big windows over the platforms
	wall(false, -24.5, 24.5, 39.5, 40.5, 0, 12, { { -20, -10, 4, 8 }, { -4, 4, 0, 10 }, { 10, 20, 4, 8 } }, P.plaster, "OfficeWallS")
	wall(false, -24.5, 24.5, 39.5, 40.5, 12, 23, { { -21, -3, 16.5, 20 }, { 3, 21, 16.5, 20 } }, P.plaster, "OfficeWallS")
	-- upper floor slab and roof
	blk(-23.5, 12, 21, 23.5, FLOOR2, 39.5, P.woodDark, "OfficeFloor2")
	blk(-25.5, 23, 19, 25.5, 24, 41.5, P.rustDark, "OfficeRoof")
	blk(-25.5, 21, 40.5, 25.5, 23, 40.8, P.paintTeal, "OfficeBand")
	cylY(18, 24, 24, 34, 0.5, P.metal, "Antenna")
	blk(-6, 24, 26, 2, 27, 32, P.metal, "ACUnit")

	-------------------------------------------------------------------------------------------
	-- Loading yard (north lane) and north alley flank.
	-------------------------------------------------------------------------------------------
	section("LoadingYard")
	-- double-stacked containers form the alley wall (Z -116..-108), unclimbable at 18 studs
	local cStyles = { P.rust, P.paintTeal, P.paintCream, P.paintRed, P.rust }
	for i, span in { { -108, -84 }, { -56, -32 }, { -12, 12 }, { 32, 56 }, { 84, 108 } } do
		container(span[1], span[2], -116, -108, 0, cStyles[i])
		container(span[1] + 1, span[2] - 1, -116, -108, 9, cStyles[(i % 5) + 1])
	end
	-- loading dock against the hall: Y 4 deck, stairs at both ends
	blk(-40, 0, -62, 40, 4, -50, P.concreteDark, "Dock")
	blk(-40, 4, -62, 40, 4.06, -61, P.paintYellow, "DockEdge")
	for x = -36, 36, 12 do
		blk(x - 1, 1, -62.6, x + 1, 3.4, -62, P.rubber, "DockBumper")
	end
	for _, s in { -1, 1 } do
		stairs(s * 40, -62, s * 48, -52, if s < 0 then "+X" else "-X", 0, 4, P.concrete)
	end
	-- forklift ramp (wedge, ~22 degrees) up the front of the dock
	wedge(CFrame.new(16, 2, -67), Vector3.new(8, 4, 10), P.metalDark, "DockRamp")
	crate(-22, 4, -56, 4)
	crate(-17.5, 4, -55.5, 4, 0.15)
	crate(-20, 8, -56, 4, 0.3)
	crate(27, 4, -57, 4)
	blk(4, 4, -55, 8, 6.5, -52, P.paintYellow, "Forklift")
	blk(5, 6.5, -54.5, 5.6, 11, -52.5, P.metalDark, "ForkliftMast")
	-- yard props, mirrored (cosmetic colour differences only)
	local carStyles = { style(M.Metal, 150, 92, 68), style(M.Metal, 108, 128, 126), style(M.Metal, 196, 178, 140) }
	for _, s in { -1, 1 } do
		car(s * 104, -96, s * 1.45, carStyles[1])
		car(s * 62, -97, s * 0.08, carStyles[2])
		car(s * 22, -95, s * -0.1, carStyles[3])
		car(s * 48, -78, s * 0.38, carStyles[1])
		barrier(s * 30, -74, 10, false)
		barrier(s * 80, -76, 10, false)
		barrier(s * 104, -66, 10, true)
		lampPost(s * 30, -104, 16)
		lampPost(s * 92, -60, 16)
		-- pallets near the hall north doors
		crate(s * 78, 0, -58, 4)
		crate(s * 82.5, 0, -57.5, 3, 0.4)
		-- alley clutter (low)
		blk(s * 72, 0, -125, s * 78, 3, -121, P.paintTeal, "Dumpster")
		blk(s * 28, 0, -127, s * 32, 1.2, -123, P.wood, "Pallet")
		drums(s * 118, -124, 3)
	end
	-- taxi booth: breaks the centre of the yard
	blk(-4, 0, -88, 4, 9, -80, P.paintCream, "TaxiBooth")
	blk(-4.2, 4.5, -88.2, 4.2, 7, -79.8, P.paintYellow, "TaxiBand")
	blk(-5.5, 9, -89.5, 5.5, 9.6, -78.5, P.rust, "TaxiRoof")

	-------------------------------------------------------------------------------------------
	-- Platform A (Z 21..60) props.
	-------------------------------------------------------------------------------------------
	section("PlatformA")
	for _, s in { -1, 1 } do
		vending(s * 51.5, 22.6, if s < 0 then P.paintRed else P.paintTeal)
		vending(s * 85.5, 22.6, P.paintRed)
		bench(s * 58, 48, 10, false)
		bench(s * 104, 46, 10, false)
		blk(s * 80, 0, 44, s * 88, 7, 50, P.paintCream, "Newsstand")
		blk(s * 79.5, 7, 43.5, s * 88.5, 7.6, 50.5, P.rust, "NewsstandRoof")
		blk(s * 36, 0, 48, s * 42, 2.8, 52, P.metal, "LuggageCart")
		crate(s * 38, 2.8, 50, 2.4)
		for _, x in { 20, 66, 112 } do
			lampPost(s * x, 56, 13)
		end
		-- steps down into the track bed
		stairs(s * 96, 60, s * 104, 64, "-Z", -3, 0, P.concrete)
		stairs(s * 96, 70, s * 104, 74, "+Z", -3, 0, P.concrete)
	end
	-- transition belts (X +-100..122) between each spawn screen and the hall: break the long
	-- north-south lines a player gets when stepping out of a screen gap
	for _, s in { -1, 1 } do
		blk(s * 108, 0, -28, s * 112, 8, -23, P.paintRed, "PhoneBooth")
		blk(s * 107.8, 6.5, -28.2, s * 112.2, 7.5, -22.8, P.paintCream, "PhoneBoothSign")
		blk(s * 107, 0, 13, s * 115, 3, 19, P.concrete, "Planter")
		blk(s * 107.3, 3, 13.3, s * 114.7, 3.3, 18.7, P.grass, "PlanterSoil")
		cylY(s * 111, 3.3, 16, 13, 1.4, P.woodDark, "DeadPalm")
		blk(s * 112, 0, 28, s * 118, 8, 34, P.metal, "Lockers")
		blk(s * 111.8, 1, 28.5, s * 112, 7.5, 33.5, P.metalDark, "LockerDoors")
	end
	blk(-3, 0, 48, 3, 2.8, 53, P.metal, "LuggageCart")
	crate(0, 2.8, 50.5, 3, 0.25)

	-------------------------------------------------------------------------------------------
	-- Track bed (Z 60..74, top Y -3): walk-through passenger car, flatcar, rails.
	-------------------------------------------------------------------------------------------
	section("Tracks")
	for _, z in { 65, 69 } do
		blk(-118, -3, z - 0.3, 118, -2.5, z + 0.3, P.metal, "Rail")
	end
	for x = -114, 114, 8 do
		blk(x - 0.8, -3, 63.5, x + 0.8, -2.8, 70.5, P.woodDark, "Sleeper")
	end
	for _, s in { -1, 1 } do
		blk(s * 117, -3, 62, s * 121, 0.5, 72, P.concreteDark, "BufferStop")
		blk(s * 116.6, -1.5, 63, s * 117, -0.3, 71, P.paintRed, "BufferBeam")
	end
	-- passenger car X -46..10
	local cx0, cx1 = -46, 10
	blk(cx0 + 1, -3, 63, cx1 - 1, -0.4, 71, P.metalDark, "Undercarriage")
	blk(-42, -2.7, 62.4, -34, -0.4, 71.6, P.rubber, "Bogie")
	blk(-2, -2.7, 62.4, 6, -0.4, 71.6, P.rubber, "Bogie")
	blk(cx0, -0.4, 62, cx1, 0.4, 72, P.metal, "CarFloor")
	local carOpenings: { Opening } = {
		{ -45.4, -39, 4.4, 7.6 },
		{ -38, -32, 0.4, 9.6 },
		{ -31, -7, 4.4, 7.6 },
		{ -6, 0, 0.4, 9.6 },
		{ 1, 9.4, 4.4, 7.6 },
	}
	wall(false, cx0, cx1, 62, 62.6, 0.4, 10.4, carOpenings, P.busCream, "CarSide")
	wall(false, cx0, cx1, 71.4, 72, 0.4, 10.4, carOpenings, P.busCream, "CarSide")
	blk(cx0, 1.6, 61.9, cx1, 2.6, 62, P.paintTeal, "CarStripe")
	blk(cx0, 1.6, 72, cx1, 2.6, 72.1, P.paintTeal, "CarStripe")
	wall(true, 62.6, 71.4, cx0, cx0 + 0.6, 0.4, 10.4, { { 65, 69, 4.4, 7.6 } }, P.busCream, "CarEnd")
	wall(true, 62.6, 71.4, cx1 - 0.6, cx1, 0.4, 10.4, { { 65, 69, 4.4, 7.6 } }, P.busCream, "CarEnd")
	blk(cx0 - 0.4, 10.4, 61.6, cx1 + 0.4, 11.2, 72.4, P.metal, "CarRoof")
	blk(cx0 + 1, 11.2, 64, cx1 - 1, 11.8, 70, P.metal, "CarRoofCrown")
	-- bridge plates at each door
	for _, d in { { -38, -32 }, { -6, 0 } } do
		blk(d[1], 0, 59.5, d[2], 0.2, 62, P.metalDark, "BridgePlate")
		blk(d[1], 0, 72, d[2], 0.2, 74.5, P.metalDark, "BridgePlate")
	end
	-- seats + mid-car partitions
	for _, r in { { -45.4, -39.5 }, { -31.5, -21 }, { -17, -6.5 }, { 0.5, 9.4 } } do
		blk(r[1], 0.4, 62.6, r[2], 1.9, 64.4, P.fabric, "Seat")
		blk(r[1], 0.4, 69.6, r[2], 1.9, 71.4, P.fabric, "Seat")
	end
	blk(-19.5, 0.4, 62.6, -18.5, 7.4, 65.2, P.woodDark, "Partition")
	blk(-19.5, 0.4, 68.8, -18.5, 7.4, 71.4, P.woodDark, "Partition")
	-- flatcar X 22..58 with cargo (kept low so the car roof stays unreachable)
	blk(23, -3, 64, 57, -1.2, 70, P.metalDark, "FlatcarFrame")
	blk(22, -1.2, 63, 58, 0.4, 71, P.rust, "Flatcar")
	crate(28, 0.4, 65.5, 4)
	crate(28.5, 0.4, 69, 3, 0.3)
	blk(36, 0.4, 64, 44, 5.4, 70, P.tarp, "TarpCargo")
	crate(50, 0.4, 66, 4)
	crate(50, 4.4, 66, 4, 0.2)
	crate(54, 0.4, 69, 3)
	-- maintenance handcar on the west stretch, drums on the east
	blk(-86, -3, 64, -78, -1, 70, P.paintYellow, "Handcar")
	blk(-83, -1, 66, -81, 1.5, 68, P.metalDark, "HandcarLever")
	drums(80, 66, 2)

	-------------------------------------------------------------------------------------------
	-- Platform B (Z 74..92): canopy, advert pylons, benches.
	-------------------------------------------------------------------------------------------
	section("PlatformB")
	for _, s in { -1, 1 } do
		for _, x in { 12, 36, 60, 84, 108 } do
			cylY(s * x, 0, 83, 15, 1.2, P.metalDark, "CanopyPost")
		end
		blk(s * 20, 0, 82.5, s * 28, 7, 83.5, P.board, "AdvertPylon")
		blk(s * 20.2, 1.5, 82.4, s * 27.8, 6.5, 83.6, P.paintCream, "AdvertPoster")
		blk(s * 68, 0, 82.5, s * 76, 7, 83.5, P.board, "AdvertPylon")
		blk(s * 68.2, 1.5, 82.4, s * 75.8, 6.5, 83.6, if s < 0 then P.paintRed else P.paintTeal, "AdvertPoster")
		bench(s * 48, 87, 10, false)
		bench(s * 96, 87, 10, false)
		crate(s * 114, 0, 79, 4, 0.2)
	end
	blk(-120, 15, 76, 120, 15.6, 90, P.rust, "Canopy")
	blk(-120, 14.2, 89.6, 120, 15, 90, P.paintTeal, "CanopyFascia")
	blk(-120, 14.2, 76, 120, 15, 76.4, P.paintTeal, "CanopyFascia")

	-------------------------------------------------------------------------------------------
	-- Bus bays (south lane, Z 92..113): two walk-through buses + bay island.
	-------------------------------------------------------------------------------------------
	section("BusBays")
	local function bus(xa: number, xb: number, st: Style, stripe: Style)
		local x0, x1 = math.min(xa, xb), math.max(xa, xb)
		local z0, z1 = 97, 107
		blk(x0 + 0.5, 0, z0 + 0.6, x1 - 0.5, 1, z1 - 0.6, P.metalDark, "BusChassis")
		local L = x1 - x0
		local function at(f: number): number
			return x0 + f * L
		end
		local o: { Opening } = {
			{ at(0.03), at(0.12), 5, 8.5 },
			{ at(0.15), at(0.33), 1, 10 },
			{ at(0.36), at(0.64), 5, 8.5 },
			{ at(0.67), at(0.85), 1, 10 },
			{ at(0.88), at(0.97), 5, 8.5 },
		}
		wall(false, x0, x1, z0, z0 + 0.5, 1, 11, o, st, "BusSide")
		wall(false, x0, x1, z1 - 0.5, z1, 1, 11, o, st, "BusSide")
		blk(x0, 3, z0 - 0.1, x1, 4, z0, stripe, "BusStripe")
		blk(x0, 3, z1, x1, 4, z1 + 0.1, stripe, "BusStripe")
		wall(true, z0 + 0.5, z1 - 0.5, x0, x0 + 0.5, 1, 11, { { z0 + 1.5, z1 - 1.5, 5.5, 9 } }, st, "BusEnd")
		wall(true, z0 + 0.5, z1 - 0.5, x1 - 0.5, x1, 1, 11, { { z0 + 1.5, z1 - 1.5, 5.5, 9 } }, st, "BusEnd")
		blk(x0 - 0.2, 11, z0 - 0.2, x1 + 0.2, 11.6, z1 + 0.2, P.metal, "BusRoof")
		for _, f in { 0.07, 0.93 } do
			cylH(at(f), 1.4, z0 - 0.2, 1, 2.8, true, P.rubber, "BusWheel")
			cylH(at(f), 1.4, z1 + 0.2, 1, 2.8, true, P.rubber, "BusWheel")
		end
		-- seats along the windows of the long middle section
		blk(at(0.38), 1, z0 + 0.5, at(0.62), 2.6, z0 + 2.3, P.fabric, "BusSeat")
		blk(at(0.38), 1, z1 - 2.3, at(0.62), 2.6, z1 - 0.5, P.fabric, "BusSeat")
	end
	bus(-90, -54, P.busCream, P.paintTeal)
	bus(54, 90, P.busCream, P.paintRed)
	-- central bay island
	blk(-24, 0, 99, 24, 0.6, 105, P.concreteWarm, "BayIsland")
	blk(-2, 0.6, 101, 2, 5.6, 103, P.paintTeal, "TicketMachine")
	for _, s in { -1, 1 } do
		cylY(s * 18, 0.6, 102, 9, 0.5, P.metal, "BaySignPost")
		blk(s * 18 - 1.5, 7, 101.8, s * 18 + 1.5, 9, 102.2, P.paintYellow, "BaySign")
		blk(s * 8, 0.6, 100, s * 12, 3.2, 104, P.concrete, "Planter")
		blk(s * 8.2, 3.2, 100.2, s * 11.8, 3.5, 103.8, P.grass, "PlanterSoil")
		barrier(s * 34, 95, 10, false)
		barrier(s * 34, 110, 10, false)
		barrier(s * 106, 102, 8, true)
	end

	-------------------------------------------------------------------------------------------
	-- Service tunnel (south flank, Z 115..128 interior, X -140..140, ceiling Y 12).
	-------------------------------------------------------------------------------------------
	section("ServiceTunnel")
	wall(false, -140, 140, 113, 115, 0, 12, { { -74, -66, 0, 10 }, { -4, 4, 0, 10 }, { 66, 74, 0, 10 } }, P.concreteDark, "TunnelWall")
	blk(-140, 12, 113, 140, 13, 128, P.concreteDark, "TunnelRoof")
	blk(-141, 9, 112.8, 141, 13, 113, P.paintTeal, "TunnelFascia")
	cylH(0, 9.5, 126.6, 280, 1.4, false, P.rust, "Pipe")
	cylH(0, 11, 126.9, 280, 1, false, P.metal, "Pipe")
	for x = -120, 120, 40 do
		blk(x - 2, 11.6, 120.5, x + 2, 12, 121.5, P.lamp, "TunnelLight")
	end
	for _, s in { -1, 1 } do
		-- zig-zag baffles near each end kill the end-to-end sightline
		blk(s * 106, 0, 115, s * 108, 12, 122, P.concrete, "TunnelBaffle")
		blk(s * 98, 0, 121, s * 100, 12, 128, P.concrete, "TunnelBaffle")
		-- centre clutter
		blk(s * 14, 0, 122, s * 20, 6, 128, P.metal, "ValveUnit")
		crate(s * 40, 0, 117.5, 4)
		crate(s * 44, 0, 118, 3, 0.4)
		blk(s * 58, 0, 124, s * 61, 7, 128, P.metalDark, "ElectricalCabinet")
	end

	-------------------------------------------------------------------------------------------
	-- Team bases: Sable depot (west), Talon freight gate (east). Mirror symmetric.
	-------------------------------------------------------------------------------------------
	local function spawnPart(x: number, z: number, lookX: number, lookZ: number, team: string?, ffa: boolean)
		local p = Instance.new("Part")
		p.Name = if team then team .. "Spawn" else "FFASpawn"
		p.Size = Vector3.new(2, 1, 2)
		local pos = Vector3.new(x, 0.5, z)
		p.CFrame = CFrame.lookAt(pos, Vector3.new(lookX, 0.5, lookZ))
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
		-- screen wall with four gaps, rusted upper sheeting
		local open: { Opening } = {}
		for _, g in GAPS do
			table.insert(open, { g[1], g[2], -3, 14 })
		end
		wall(true, -128, 113, s * (SCREEN_X - 1), s * (SCREEN_X + 1), -3, 7, open, P.concrete, "ScreenWall")
		wall(true, -128, 113, s * (SCREEN_X - 1), s * (SCREEN_X + 1), 7, 14, open, P.rust, "ScreenWall")
		-- each gap is a short fenced corridor (fins X 112..128) so only shallow-angle lines pass,
		-- and a baffle on the spawn side (X 136..138) catches those shallow lines
		for _, g in GAPS do
			for _, edge in { { g[1] - 1, g[1] }, { g[2], g[2] + 1 } } do
				blk(s * 112, 0, edge[1], s * 128, 14, edge[2], P.rust, "GapFin")
				blk(s * 112, 0, edge[1] - 0.05, s * 112.6, 14, edge[2] + 0.05, accent, "GapFinCap")
			end
			local z0 = math.max(g[1] - 8, -128)
			local z1 = math.min(g[2] + 8, 113)
			blk(s * 136, 0, z0, s * 138, 12, z1, P.concreteWarm, "Baffle")
			blk(s * 136, 6, z0, s * 135.7, 7.5, z1, accent, "BaffleStripe")
			blk(s * 138, 6, z0, s * 138.3, 7.5, z1, accent, "BaffleStripe")
		end
		-- depot canopy over the spawn strip
		for z = -120, 120, 40 do
			blk(s * 143.5, 0, z - 0.6, s * 144.7, 17, z + 0.6, P.metalDark, "DepotPost")
			blk(s * 177.5, 0, z - 0.6, s * 178.7, 17, z + 0.6, P.metalDark, "DepotPost")
		end
		blk(s * 142, 17, -128, s * 180, 17.8, 128, P.rust, "DepotRoof")
		blk(s * 142, 16.2, -128, s * 142.4, 17.8, 128, accent, "DepotFascia")
		-- floor markings + low clutter (kept away from walls so nothing becomes a ladder)
		for _, z in { -100, -50, 0, 50, 100 } do
			blk(s * 158, 0, z - 6, s * 159, 0.06, z + 6, accent, "BayMarking")
		end
		drums(s * 174, -112, 4)
		drums(s * 174, 24, 3)
		crate(s * 172, 0, 66, 4)
		crate(s * 172, 0, 72, 3, 0.3)
		crate(s * 174, 0, -66, 4, 0.1)
		blk(s * 166, 0, 116, s * 176, 3, 124, P.metal, "ToolChest")

		-- team spawns: two columns of five, facing into the map
		for _, z in { -100, -50, 0, 50, 100 } do
			for _, x in { 150, 167 } do
				spawnPart(s * x, z + (if x == 167 then 8 else 0), 0, z, team, false)
			end
		end
	end

	-------------------------------------------------------------------------------------------
	-- FFA spawns spread around the whole map.
	-------------------------------------------------------------------------------------------
	local ffa = {
		{ -158, -80, 0, -80 },
		{ -158, 75, 0, 40 },
		{ 158, -28, 0, -28 },
		{ 158, 122, 100, 122 },
		{ -84, -121, 0, -121 },
		{ 76, -88, 0, -80 },
		{ -60, -24, 0, -20 },
		{ 64, -2, 0, -20 },
		{ -84, 34, 0, 40 },
		{ 98, 32, 0, 40 },
		{ -30, 86, 0, 86 },
		{ 112, 102, 0, 102 },
		{ -118, 121, 0, 121 },
		{ 50, 121, 0, 121 },
		{ 0, -98, 0, -60 },
		{ 0, 30, 0, 50 },
	}
	for _, f in ffa do
		spawnPart(f[1], f[2], f[3], f[4], nil, true)
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
		for k, v in attrs do
			p:SetAttribute(k, v)
		end
		p.Parent = objectives
	end

	-- Domination: A west hall half, B Platform A outside the office door, C east hall half.
	zone("FlagA", "Flag", -60, 0, -22, 18, 18, { Label = "A" })
	zone("FlagB", "Flag", 0, 0, 46, 20, 14, { Label = "B" })
	zone("FlagC", "Flag", 60, 0, -22, 18, 18, { Label = "C" })

	-- Hardpoint rotation: centre -> south -> north -> centre -> south flank (every hop 88+ studs).
	zone("Hardpoint1_TicketHall", "Hardpoint", 0, 0, -3, 28, 16, { Order = 1 })
	zone("Hardpoint2_BusBays", "Hardpoint", -40, 0, 102, 26, 18, { Order = 2 })
	zone("Hardpoint3_LoadingDock", "Hardpoint", 0, 4, -58, 26, 16, { Order = 3 })
	zone("Hardpoint4_ControlOffice", "Hardpoint", 0, 0, 30, 24, 16, { Order = 4 })
	zone("Hardpoint5_ServiceTunnel", "Hardpoint", 30, 0, 121, 24, 16, { Order = 5 })

	-- Search and Destroy: Sable (west) attacks first, so both sites sit on the Talon (east) side.
	-- A: east loading yard between the parked car, the jersey barrier and the pallets.
	-- B: east bus bays between the bay island, the barriers and the walk-through bus.
	zone("BombSiteA", "BombSite", 66, 0, -68, 14, 14, { Label = "A" })
	zone("BombSiteB", "BombSite", 42, 0, 102, 14, 14, { Label = "B" })

	-------------------------------------------------------------------------------------------
	-- Lobby camera + model attributes.
	-------------------------------------------------------------------------------------------
	local cam = Instance.new("Part")
	cam.Name = "LobbyCamera"
	cam.Size = Vector3.new(1, 1, 1)
	cam.CFrame = CFrame.lookAt(Vector3.new(-120, 150, 230), Vector3.new(10, 0, 10))
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
