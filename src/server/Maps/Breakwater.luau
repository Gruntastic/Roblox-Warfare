--!strict
--[[
	Breakwater: a small harbour container port on an overcast morning, between the fish market
	and the outer breakwater. Medium 6v6 map, ~360 x 260 studs playable
	(boundary inner faces at X = +-180, Z = +-130).

	Axes: +X = east, -Z = north (top of the ASCII sketch in docs/maps/Breakwater.md).
	Floor levels (top surfaces):
	  Y 14    Gantry crane catwalk (reached by two stairs, one per side)
	  Y 13    Harbourmaster office upper floor and balcony
	  Y  0    Quay, yards, pier deck and gangways
	  Y -1.5  Harbour water: a shallow, walkable floor (tinted glass over a seabed), Z 88..130
	Everything stands on a bedrock slab at BoundsMin.Y (-8), so there is never a hole to the void.

	Bands, north -> south:
	  Z -130..-116  Rail siding (north flank): flatcars and buffer stops
	  Z -116..-108  Wall of double-stacked containers with three gaps
	  Z -108.. -46  Fish market (north lane): market hall, cold store (west), net loft (east), trucks
	  Z  -46..  34  Container yard (middle lane): four container rows, three alleys, gantry crane
	  Z   34..  88  Quay apron (south lane): harbourmaster office, reefers, bollards
	  Z   88.. 130  Harbour water (south flank) with the pier at Z 100..112, boats and the breakwater
	Sable base = west terminal gate (X < -136), Talon base = east (X > 136). Both hide behind a
	double-stacked container rampart with outer container baffles.

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

-- Grey-blue harbour palette with bright container colours.
local P = {
	concrete = style(M.Concrete, 138, 144, 150),
	concreteDark = style(M.Concrete, 100, 106, 114),
	concreteLight = style(M.Concrete, 170, 176, 180),
	asphalt = style(M.Asphalt, 78, 84, 92),
	seabed = style(M.Sand, 74, 84, 82),
	water = style(M.Glass, 64, 104, 130, 0.35),
	steel = style(M.Metal, 92, 104, 118),
	steelDark = style(M.DiamondPlate, 66, 74, 84),
	craneYellow = style(M.Metal, 214, 168, 46),
	rust = style(M.CorrodedMetal, 120, 84, 64),
	planks = style(M.WoodPlanks, 112, 98, 84),
	planksDark = style(M.WoodPlanks, 82, 72, 64),
	panel = style(M.SmoothPlastic, 206, 212, 216),
	panelBlue = style(M.SmoothPlastic, 90, 116, 140),
	brick = style(M.Brick, 132, 92, 80),
	glass = style(M.Glass, 150, 176, 190, 0.5),
	rubber = style(M.Rubber, 40, 42, 46),
	rock = style(M.Rock, 110, 114, 116),
	rockDark = style(M.Slate, 82, 88, 92),
	net = style(M.Fabric, 60, 92, 84),
	tarp = style(M.Fabric, 70, 96, 128),
	lamp = style(M.Neon, 236, 240, 255),
	paintYellow = style(M.SmoothPlastic, 230, 190, 50),
	paintWhite = style(M.SmoothPlastic, 226, 228, 230),
	-- container colours
	cRed = style(M.CorrodedMetal, 176, 54, 42),
	cBlue = style(M.Metal, 40, 92, 164),
	cYellow = style(M.Metal, 222, 172, 40),
	cGreen = style(M.Metal, 48, 130, 82),
	cOrange = style(M.Metal, 224, 112, 32),
	cWhite = style(M.Metal, 222, 224, 226),
	cTeal = style(M.Metal, 34, 132, 140),
	frame = style(M.Metal, 60, 64, 70),
	sable = style(M.SmoothPlastic, 64, 90, 110),
	talon = style(M.SmoothPlastic, 182, 108, 50),
}

local CONTAINER_COLOURS = { P.cRed, P.cBlue, P.cYellow, P.cGreen, P.cOrange, P.cWhite, P.cTeal }

local MapModule = {}

MapModule.id = "Breakwater"
MapModule.displayName = "Breakwater"

-- Overcast early morning: soft, cool, low contrast. Only valid Lighting properties.
MapModule.lighting = {
	ClockTime = 8.2,
	GeographicLatitude = 52,
	Brightness = 1.7,
	ExposureCompensation = 0.25,
	Ambient = Color3.fromRGB(104, 112, 122),
	OutdoorAmbient = Color3.fromRGB(150, 160, 172),
	ColorShift_Top = Color3.fromRGB(204, 214, 226),
	ColorShift_Bottom = Color3.fromRGB(80, 90, 104),
	EnvironmentDiffuseScale = 0.6,
	EnvironmentSpecularScale = 0.35,
	ShadowSoftness = 0.8,
	GlobalShadows = true,
	FogColor = Color3.fromRGB(176, 186, 196),
	FogStart = 300,
	FogEnd = 1600,
}

-- Valid Atmosphere properties: grey sea haze, no glare.
MapModule.atmosphere = {
	Density = 0.36,
	Offset = 0.18,
	Color = Color3.fromRGB(192, 200, 208),
	Decay = Color3.fromRGB(118, 130, 146),
	Glare = 0,
	Haze = 2.2,
}

MapModule.killY = -40

local XB, ZB = 180, 130
local BOUNDS_MIN = Vector3.new(-184, -8, -134)
local BOUNDS_MAX = Vector3.new(184, 50, 134)
local QUAY_Z = 88 -- quay edge; water to the south
local WATER_Y = -1.5

-- Container rampart at |X| 136..144 (double stack) with gaps; outer baffles at |X| 122..130.
local RAMPART = { 136, 144 }
local BAFFLE = { 122, 130 }
local RAMPART_GAPS = { { -126, -118 }, { -80, -70 }, { -6, 4 }, { 56, 66 }, { 100, 112 } }
local BAFFLES = { { -92, -58 }, { -18, 16 }, { 44, 78 } }

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

	-- Vertical cylinder (bollard, pile, tank).
	local function cylY(x: number, y0: number, z: number, y1: number, d: number, st: Style, name: string?): Part
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(y1 - y0, d, d)
		p.CFrame = CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
		finish(p, st, name)
		return p
	end

	-- Horizontal cylinder along X or Z (wheels, fenders, pipes).
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

	-- Shipping container (9 tall, 8 wide) from corner (x0, z0) to (x1, z1), any orientation:
	-- the long axis is whichever side is longer. Body plus two darker end frames.
	local colourIndex = 0
	local function container(x0: number, x1: number, z0: number, z1: number, y0: number, st: Style?)
		colourIndex += 1
		local c = st or CONTAINER_COLOURS[(colourIndex * 3) % #CONTAINER_COLOURS + 1]
		local xa, xb = math.min(x0, x1), math.max(x0, x1)
		local za, zb = math.min(z0, z1), math.max(z0, z1)
		if xb - xa >= zb - za then
			blk(xa + 0.3, y0, za, xb - 0.3, y0 + 9, zb, c, "Container")
			blk(xa, y0, za - 0.15, xa + 0.6, y0 + 9, zb + 0.15, P.frame, "ContainerFrame")
			blk(xb - 0.6, y0, za - 0.15, xb, y0 + 9, zb + 0.15, P.frame, "ContainerFrame")
		else
			blk(xa, y0, za + 0.3, xb, y0 + 9, zb - 0.3, c, "Container")
			blk(xa - 0.15, y0, za, xb + 0.15, y0 + 9, za + 0.6, P.frame, "ContainerFrame")
			blk(xa - 0.15, y0, zb - 0.6, xb + 0.15, y0 + 9, zb, P.frame, "ContainerFrame")
		end
	end

	-- A run of containers along X from xa to xb (split into pieces of at most 20), 1 or 2 high.
	local function containerRow(xa: number, xb: number, z0: number, z1: number, high: number)
		local lo, hi = math.min(xa, xb), math.max(xa, xb)
		local n = math.ceil((hi - lo) / 20 - 1e-6)
		local len = (hi - lo) / n
		for i = 0, n - 1 do
			for level = 0, high - 1 do
				container(lo + i * len, lo + (i + 1) * len, z0, z1, level * 9)
			end
		end
	end

	local function crate(x: number, y: number, z: number, s: number, yaw: number?)
		box(CFrame.new(x, y + s / 2, z) * CFrame.Angles(0, yaw or 0, 0), Vector3.new(s, s, s), P.planks, "Crate")
	end

	local function pallet(x: number, z: number, h: number, st: Style)
		blk(x - 2.4, 0, z - 2, x + 2.4, 0.6, z + 2, P.planksDark, "Pallet")
		blk(x - 2.1, 0.6, z - 1.7, x + 2.1, 0.6 + h, z + 1.7, st, "PalletLoad")
	end

	local function bollard(x: number, y: number, z: number)
		cylY(x, y, z, y + 1.6, 1.4, P.steelDark, "Bollard")
		cylY(x, y + 1.6, z, y + 2, 1.9, P.steelDark, "BollardCap")
	end

	-- Fish/ice tote stack (crouch cover), blue plastic.
	local function totes(x: number, z: number)
		blk(x - 2, 0, z - 1.5, x + 2, 3.2, z + 1.5, P.panelBlue, "Totes")
		blk(x - 1.8, 3.2, z - 1.3, x + 1.8, 3.4, z + 1.3, P.paintWhite, "ToteIce")
	end

	-- Box truck: cargo box + cab + 4 wheels, long axis along X, cab on the +X side when
	-- face > 0 and on the -X side when face < 0.
	local function truck(x: number, z: number, face: number, st: Style)
		local f = if face < 0 then -1 else 1
		local function bx(a0: number, y0: number, z0: number, a1: number, y1: number, z1: number, s2: Style, name: string)
			blk(x + f * a0, y0, z + z0, x + f * a1, y1, z + z1, s2, name)
		end
		bx(-8, 1.6, -3.2, 4, 10, 3.2, st, "TruckBox")
		bx(4, 1.6, -3, 9, 7, 3, P.paintWhite, "TruckCab")
		bx(8.4, 4.4, -2.6, 9.05, 6.4, 2.6, P.glass, "TruckWindscreen")
		bx(-8, 1, -2.6, 9, 1.6, 2.6, P.steelDark, "TruckChassis")
		bx(-8.2, 6, -3.3, -8, 9, 3.3, P.paintYellow, "TruckDoorStripe")
		for _, w in { { -6, -3.2 }, { -6, 3.2 }, { 6, -3.2 }, { 6, 3.2 } } do
			cylH(x + f * w[1], 1.4, z + w[2], 0.9, 2.8, true, P.rubber, "Wheel")
		end
	end

	local function forklift(x: number, z: number, yaw: number)
		local base = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
		box(base * CFrame.new(0, 1.8, 0), Vector3.new(6, 2.6, 4), P.paintYellow, "Forklift")
		box(base * CFrame.new(-1, 4.4, 0), Vector3.new(3, 2.6, 3.6), P.steelDark, "ForkliftCage")
		box(base * CFrame.new(3.4, 3.5, 0), Vector3.new(0.6, 7, 3), P.steelDark, "ForkliftMast")
		box(base * CFrame.new(4.6, 0.4, 0), Vector3.new(2.6, 0.3, 3), P.steelDark, "Forks")
	end

	local function lightTower(x: number, z: number, h: number)
		blk(x - 1.6, 0, z - 1.6, x + 1.6, 1.4, z + 1.6, P.concreteDark, "LightBase")
		cylY(x, 1.4, z, h, 0.8, P.steel, "LightMast")
		blk(x - 2.2, h, z - 0.6, x + 2.2, h + 1.6, z + 0.6, P.steelDark, "LightHead")
		blk(x - 2, h - 0.2, z - 0.5, x + 2, h, z + 0.5, P.lamp, "Floodlight")
	end

	-- Small fishing boat in the water: hull, wheelhouse, mast. Long axis along X.
	local function boat(x: number, z: number, len: number, st: Style)
		local y = WATER_Y
		blk(x - len / 2, y, z - 3.5, x + len / 2 - 3, y + 3.5, z + 3.5, st, "Hull")
		wedge(CFrame.new(x + len / 2 - 1.5, y + 1.75, z) * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(7, 3.5, 3), st, "Bow")
		blk(x - len / 2 + 0.2, y + 3.5, z - 3.6, x + len / 2 - 3, y + 4, z + 3.6, P.paintWhite, "Gunwale")
		blk(x - 2, y + 3.5, z - 2.4, x + 3, y + 8.5, z + 2.4, P.paintWhite, "Wheelhouse")
		blk(x - 2.2, y + 8.5, z - 2.6, x + 3.2, y + 9, z + 2.6, P.panelBlue, "WheelhouseRoof")
		cylY(x - len / 4, y + 3.5, z, y + 15, 0.5, P.steelDark, "Mast")
	end

	-------------------------------------------------------------------------------------------
	-- Ground: bedrock slab over the whole footprint, the quay block to the north of Z 88 and
	-- the seabed + water surface to the south. Pieces abut exactly.
	-------------------------------------------------------------------------------------------
	section("Ground")
	blk(-184, -8, -134, 184, -6, 134, P.rockDark, "Bedrock")
	blk(-184, -6, -134, 184, 0, QUAY_Z, P.concrete, "Quay")
	blk(-184, -6, QUAY_Z, 184, WATER_Y - 0.2, 134, P.seabed, "Seabed")
	blk(-184, WATER_Y - 0.2, QUAY_Z, 184, WATER_Y, 134, P.water, "HarbourWater")
	-- yard surfaces (0.05 thick, walkable)
	blk(-122, 0, -46, 122, 0.05, 34, P.asphalt, "YardAsphalt")
	blk(-XB, 0, -130, XB, 0.05, -116, P.asphalt, "SidingAsphalt")
	-- painted lane lines in the alleys and along the quay edge
	for _, z in { -31, -6, 19 } do
		blk(-118, 0.05, z - 0.25, 118, 0.08, z + 0.25, P.paintYellow, "LaneLine")
	end
	blk(-XB, 0, 84, XB, 0.08, 85, P.paintYellow, "QuayEdgeLine")
	-- quay coping and rubber fenders on the quay face
	blk(-XB, -0.4, QUAY_Z - 1, XB, 0, QUAY_Z, P.concreteLight, "Coping")
	for x = -170, 170, 20 do
		blk(x - 1.5, -1.5, QUAY_Z, x + 1.5, -0.2, QUAY_Z + 0.8, P.rubber, "Fender")
	end

	-------------------------------------------------------------------------------------------
	-- Boundary: warehouse wall (north), dock walls (west/east), the breakwater (south).
	-------------------------------------------------------------------------------------------
	section("Boundary")
	blk(-184, 0, -134, 184, 24, -130, P.brick, "WarehouseWallN")
	blk(-184, 24, -134, 184, 26, -130, P.concreteDark, "WarehouseCoping")
	blk(-184, -6, -130, -180, 22, 130, P.concreteDark, "DockWallW")
	blk(180, -6, -130, 184, 22, 130, P.concreteDark, "DockWallE")
	blk(-184, -6, 130, 184, 14, 134, P.concrete, "SeaWallS")
	for x = -160, 160, 32 do
		blk(x - 1.5, 0, -130, x + 1.5, 24, -128.8, P.concreteDark, "Pilaster")
		blk(x - 6, 6, -130.1, x + 6, 18, -130, P.panelBlue, "LoadingDoor")
	end
	-- the breakwater: armour blocks piled against the sea wall (Z 122..130), cover for the water
	local seed = 0
	for x = -172, 172, 9 do
		seed += 1
		local h = 5 + (seed * 7) % 5
		box(CFrame.new(x, WATER_Y + h / 2 - 0.5, 126 + (seed % 3)) * CFrame.Angles(0.1 * (seed % 3), seed * 0.7, 0.12),
			Vector3.new(7, h, 6), if seed % 2 == 0 then P.rock else P.concreteLight, "ArmourBlock")
	end

	-------------------------------------------------------------------------------------------
	-- Rail siding (north flank, Z -130..-116) and the container wall (Z -116..-108).
	-------------------------------------------------------------------------------------------
	section("RailSiding")
	for _, z in { -125, -121 } do
		blk(-XB, 0.05, z - 0.3, XB, 0.5, z + 0.3, P.steel, "Rail")
	end
	for x = -172, 172, 8 do
		blk(x - 0.7, 0.05, -126.5, x + 0.7, 0.25, -119.5, P.planksDark, "Sleeper")
	end
	for _, s in { -1, 1 } do
		-- flatcars with low cargo (chest-high cover), staggered
		for _, xc in { 30, 92 } do
			local x = s * xc
			blk(x - 11, 0.5, -126, x + 11, 2.2, -120, P.rust, "Flatcar")
			crate(x - 6, 2.2, -123, 3.5, 0.1)
			blk(x - 2, 2.2, -125.5, x + 4, 5, -120.5, P.tarp, "TarpCargo")
			crate(x + 8, 2.2, -123, 3, 0.3)
		end
		blk(s * 170, 0, -127, s * 174, 3.5, -119, P.paintYellow, "BufferStop")
		blk(s * 58, 0, -129, s * 66, 3, -126, P.steelDark, "RailCabinet")
	end
	-- double-stacked container wall with gaps at X 0 and |X| 46..54, 96..104
	section("ContainerWall")
	for _, s in { -1, 1 } do
		for _, seg in { { 4, 46 }, { 54, 96 }, { 104, 136 } } do
			containerRow(s * seg[1], s * seg[2], -116, -108, 2)
		end
	end

	-------------------------------------------------------------------------------------------
	-- Fish market (north lane): market hall X -50..50, Z -100..-58, walls 14 tall.
	-------------------------------------------------------------------------------------------
	section("FishMarket")
	local MH = 14
	wall(false, -50, 50, -100, -99, 0, MH, { { -34, -26, 0, 10 }, { 26, 34, 0, 10 } }, P.brick, "HallWallN")
	wall(false, -50, 50, -59, -58, 0, MH, { { -42, -28, 0, 11 }, { -8, 8, 0, 11 }, { 28, 42, 0, 11 } }, P.brick, "HallWallS")
	wall(true, -99, -59, -50, -49, 0, MH, { { -84, -74, 0, 10 } }, P.brick, "HallWallW")
	wall(true, -99, -59, 49, 50, 0, MH, { { -84, -74, 0, 10 } }, P.brick, "HallWallE")
	-- sawtooth roof: four bays with glazed north faces
	for i = 0, 3 do
		local x0 = -51 + i * 25.5
		blk(x0, MH, -101, x0 + 25.5, MH + 1, -57, P.steelDark, "HallRoof")
		wedge(CFrame.new(x0 + 12.75, MH + 3, -79) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(44, 4, 25.5), P.steel, "Sawtooth")
	end
	-- roller doors rolled up (drums above the big south openings)
	for _, d in { { -42, -28 }, { -8, 8 }, { 28, 42 } } do
		cylH((d[1] + d[2]) / 2, 12, -58.6, d[2] - d[1], 2, false, P.steel, "DoorDrum")
	end
	blk(-50.3, 11.5, -58, 50.3, 12.5, -57.7, P.panelBlue, "HallSignBand")
	-- interior: stall counters in two rows (aisles at X 0 and between bays), ice tables, columns
	for _, s in { -1, 1 } do
		for _, seg in { { 14, 24 }, { 34, 46 } } do
			blk(s * seg[1], 0, -94, s * seg[2], 3.6, -90, P.panel, "StallCounter")
			blk(s * seg[1], 3.6, -93.6, s * seg[2], 3.9, -90.4, P.paintWhite, "IceBed")
			blk(s * seg[1], 0, -70, s * seg[2], 3.6, -66, P.panel, "StallCounter")
			blk(s * seg[1], 3.6, -69.6, s * seg[2], 3.9, -66.4, P.paintWhite, "IceBed")
		end
		blk(s * 28, 0, -82, s * 36, 3.4, -78, P.steel, "IceTable")
		for _, z in { -86, -72 } do
			blk(s * 26 - 0.8, 0, z - 0.8, s * 26 + 0.8, MH, z + 0.8, P.steelDark, "Column")
		end
		totes(s * 42, -80)
		totes(s * 16, -76)
		-- hanging price boards and lamps
		blk(s * 19 - 3, 10, -92.2, s * 19 + 3, 11.5, -92, P.paintYellow, "PriceBoard")
		blk(s * 19 - 3, 10, -68, s * 19 + 3, 11.5, -67.8, P.paintYellow, "PriceBoard")
		blk(s * 26 - 4, 12.4, -80.4, s * 26 + 4, 12.8, -79.6, P.lamp, "HallLamp")
	end
	-- auction clock pillar in the centre, north side of the centre zone
	blk(-2, 0, -98, 2, 9, -95, P.panelBlue, "AuctionPillar")
	blk(-1.6, 6, -95, 1.6, 8.5, -94.8, P.paintWhite, "AuctionClock")

	-- market front yard (Z -58..-46) and the side yards (|X| 50..122)
	section("MarketYards")
	for _, s in { -1, 1 } do
		-- cold store (west) / net loft (east): X 72..100, Z -96..-70, walls 12 tall
		local xa, xb = s * 72, s * 100
		local inner, outer = xa, xb -- inner faces the map centre, outer faces the base
		local body = if s < 0 then P.panel else P.planks
		wall(false, xa, xb, -96, -95, 0, 12, {}, body, "StoreWallN")
		wall(false, xa, xb, -71, -70, 0, 12, { { s * 82, s * 90, 0, 10 } }, body, "StoreWallS")
		wall(true, -95, -71, inner, inner + s * 1, 0, 12, { { -87, -79, 0, 10 } }, body, "StoreWallInner")
		wall(true, -95, -71, outer, outer - s * 1, 0, 12, { { -88, -80, 4, 8 } }, body, "StoreWallOuter")
		blk(math.min(xa, xb) - 1, 12, -97, math.max(xa, xb) + 1, 13, -69, P.steelDark, "StoreRoof")
		if s < 0 then
			-- racking along the north wall, pallets inside
			blk(-98, 0, -94.5, -74, 8, -91.5, P.steel, "Racking")
			pallet(-94, -76, 3, P.panelBlue)
			pallet(-94, -88, 3, P.panelBlue)
			blk(-100.6, 2, -96.4, -99.4, 10, -95.6, P.steelDark, "ChillerPipe")
		else
			-- net loft: hanging nets, net piles and a mending bench
			blk(74, 0, -94.5, 98, 5, -91.5, P.net, "NetPile")
			pallet(94, -76, 2.5, P.net)
			blk(92, 0, -90, 96, 3, -82, P.planksDark, "MendingBench")
		end
		-- trucks at the loading side yards
		truck(s * 112, -60, -s, if s < 0 then P.cWhite else P.cBlue)
		pallet(s * 62, -104, 3, P.tarp)
		crate(s * 68, 0, -103, 4, 0.3)
		forklift(s * 64, -52, s * 0.3)
		pallet(s * 80, -54, 3, P.panelBlue)
		pallet(s * 96, -50, 2, P.planks)
		totes(s * 58, -64)
		totes(s * 108, -78)
		crate(s * 112, 0, -94, 4, 0.2)
		crate(s * 115.5, 0, -90, 3, 0.5)
		lightTower(s * 60, -84, 18)
		-- market front yard
		totes(s * 20, -52)
		pallet(s * 40, -50, 2.5, P.planks)
	end
	blk(-3, 0, -54, 3, 3.5, -50, P.steel, "IceMachine")

	-------------------------------------------------------------------------------------------
	-- Container yard (middle lane): rows N (Z -46..-38), M1 (-24..-16), M2 (4..12), S (26..34);
	-- alleys between them; the gantry crane straddles the centre (|X| <= 13, Z -37..25).
	-------------------------------------------------------------------------------------------
	section("ContainerYard")
	local rows = {
		{ z0 = -46, z1 = -38, segs = { { 20, 40, 2 }, { 48, 68, 1 }, { 78, 98, 2 } }, centre = false },
		{ z0 = -24, z1 = -16, segs = { { 20, 40, 1 }, { 48, 68, 2 }, { 78, 98, 1 } }, centre = true },
		{ z0 = 4, z1 = 12, segs = { { 22, 42, 1 }, { 50, 70, 2 }, { 80, 100, 1 } }, centre = true },
		{ z0 = 26, z1 = 34, segs = { { 16, 36, 2 }, { 44, 64, 1 }, { 72, 92, 2 } }, centre = false },
	}
	for _, r in rows do
		for _, s in { -1, 1 } do
			for _, seg in r.segs do
				containerRow(s * seg[1], s * seg[2], r.z0, r.z1, seg[3])
			end
		end
		if r.centre then
			-- single-high under the catwalk, so the catwalk (Y 13.4) clears it
			container(-10, 10, r.z0, r.z1, 0)
		end
	end
	-- alley cover (every 15..25 studs): reefer gensets, lashing cages, single crates
	for _, s in { -1, 1 } do
		-- alley 1 (Z -38..-24)
		blk(s * 52, 0, -35, s * 57, 4, -31, P.steelDark, "LashingCage")
		crate(s * 76, 0, -27, 4, 0.2)
		blk(s * 100, 0, -36, s * 104, 5, -32, P.paintWhite, "Genset")
		-- central alley (Z -16..4)
		blk(s * 30, 0, -14, s * 36, 4.5, -10, P.steelDark, "TwistlockBin")
		blk(s * 56, 0, -2, s * 64, 4, 2, P.cOrange, "TerminalTractor")
		blk(s * 64, 0, -2, s * 66, 6.5, 2, P.steelDark, "TractorCab")
		crate(s * 108, 0, -13, 4, 0.1)
		blk(s * 20, 0, -9, s * 24, 4.5, -4, P.steelDark, "TwistlockBin")
		blk(s * 42, 0, -8, s * 46, 3.6, -3, P.concreteLight, "Barrier")
		blk(s * 78, 0, -15, s * 82, 5, -11, P.paintWhite, "Genset")
		crate(s * 98, 0, -1, 4, 0.2)
		-- alley 3 (Z 12..26)
		blk(s * 58, 0, 21, s * 62, 5, 25, P.paintWhite, "Genset")
		crate(s * 84, 0, 15, 4, 0.3)
		blk(s * 104, 0, 18, s * 109, 4, 22, P.steelDark, "LashingCage")
	end
	crate(-46, 0, 23, 4, 0.2)
	crate(46, 0, -35, 4, 0.2)

	-------------------------------------------------------------------------------------------
	-- Gantry crane: legs at (|X| 12, Z -36) and (|X| 12, Z 24), girders at Y 26..28.
	-- Catwalks at Y 14 (deck Y 13.4..14) along |X| 8..14, Z -32..20, joined by a cross span
	-- at Z -10..-2. West stairs climb +X in alley 3, east stairs climb -X in alley 1.
	-------------------------------------------------------------------------------------------
	section("GantryCrane")
	local CW = 14
	for _, s in { -1, 1 } do
		for _, z in { -36, 24 } do
			blk(s * 12 - 1, 0, z - 1, s * 12 + 1, 28, z + 1, P.craneYellow, "GantryLeg")
			blk(s * 12 - 2, 0, z - 3, s * 12 + 2, 2.4, z + 3, P.steelDark, "GantryBogie")
			cylH(s * 12, 1.4, z - 2, 4.2, 2.6, false, P.rubber, "GantryTyre")
			cylH(s * 12, 1.4, z + 2, 4.2, 2.6, false, P.rubber, "GantryTyre")
		end
		-- girder along Z and a diagonal stay inside the leg line
		blk(s * 12 - 1.2, 26, -37, s * 12 + 1.2, 28, 25, P.craneYellow, "Girder")
		box(CFrame.new(s * 12, 22, -30) * CFrame.Angles(-0.7, 0, 0), Vector3.new(0.8, 0.8, 14), P.craneYellow, "Stay")
		box(CFrame.new(s * 12, 22, 18) * CFrame.Angles(0.7, 0, 0), Vector3.new(0.8, 0.8, 14), P.craneYellow, "Stay")
		-- catwalk deck, kick plates and rails (open where the stairs land)
		blk(s * 8, CW - 0.6, -32, s * 14, CW, 20, P.steelDark, "Catwalk")
		local landing = if s < 0 then { 14, 20 } else { -32, -26 }
		wall(true, -32, 20, s * 13.7, s * 14, CW, CW + 3.5, { { landing[1], landing[2], CW, CW + 3.5 } }, P.craneYellow, "CatwalkRail")
		wall(true, -32, 20, s * 8, s * 8.3, CW, CW + 3.5, { { -10, -2, CW, CW + 3.5 } }, P.craneYellow, "CatwalkRail")
		blk(s * 8, CW, -32.3, s * 14, CW + 3.5, -32, P.craneYellow, "CatwalkRail")
		blk(s * 8, CW, 20, s * 14, CW + 3.5, 20.3, P.craneYellow, "CatwalkRail")
		-- hangers from the girder to the catwalk's outer edge
		for _, z in { -22, -6, 8 } do
			blk(s * 13.8 - 0.15, CW + 3.5, z - 0.15, s * 13.8 + 0.15, 26, z + 0.15, P.steel, "Hanger")
		end
		-- electrical cabinet on each catwalk (cover up top)
		blk(s * 8.3, CW, 4, s * 10, CW + 4, 7, P.steel, "CraneCabinet")
	end
	for _, z in { -36, 24 } do
		blk(-13, 26, z - 1.2, 13, 28, z + 1.2, P.craneYellow, "CrossBeam")
	end
	blk(-8, CW - 0.6, -10, 8, CW, -2, P.steelDark, "CrossSpan")
	blk(-8, CW, -10.3, 8, CW + 3.5, -10, P.craneYellow, "SpanRail")
	blk(-8, CW, -2, 8, CW + 3.5, -1.7, P.craneYellow, "SpanRail")
	-- trolley, operator cab and the hoisted spreader (well above the catwalk)
	blk(-7, 28, -12, 7, 31, 0, P.craneYellow, "Trolley")
	blk(-3, 22.5, -12, 3, 26, -6, P.paintWhite, "OperatorCab")
	blk(-2.8, 23.5, -12.1, 2.8, 25.5, -11.9, P.glass, "CabWindow")
	for _, x in { -4, 4 } do
		blk(x - 0.15, 21, -4.15, x + 0.15, 28, -3.85, P.steel, "HoistCable")
	end
	blk(-9, 20, -6, 9, 21, -2, P.craneYellow, "Spreader")
	-- stairs (14 steps, 2-stud runs) up to the catwalk landings
	stairs(-42, 14, -14, 20, "+X", 0, CW, P.steelDark)
	stairs(14, -32, 42, -26, "-X", 0, CW, P.steelDark)
	blk(-42, 0, 13.6, -14, CW + 3.5, 14, P.craneYellow, "StairRail")
	blk(14, 0, -26, 42, CW + 3.5, -25.6, P.craneYellow, "StairRail")

	-------------------------------------------------------------------------------------------
	-- Quay apron (south lane, Z 34..88): harbourmaster office + apron cover.
	-------------------------------------------------------------------------------------------
	section("HarbourmasterOffice")
	-- X -16..16, Z 48..72, ground floor Y 0..12, upper floor Y 13, roof Y 24
	local F2 = 13
	wall(false, -16, 16, 48, 49, 0, 12, { { -4, 4, 0, 10 }, { -13, -7, 4, 8 }, { 7, 13, 4, 8 } }, P.brick, "OfficeWallN")
	wall(false, -16, 16, 71, 72, 0, 12, { { -4, 4, 0, 10 } }, P.brick, "OfficeWallS")
	wall(true, 49, 71, -16, -15, 0, 12, { { 56, 64, 0, 10 } }, P.brick, "OfficeWallW")
	wall(true, 49, 71, 15, 16, 0, 12, { { 56, 64, 0, 10 } }, P.brick, "OfficeWallE")
	blk(-15, 12, 49, 15, F2, 71, P.planksDark, "OfficeFloor2")
	-- upper storey: big windows north (over the yard) and doors onto the south balcony
	wall(false, -16, 16, 48, 49, 12, 24, { { -13, -2, 16, 21 }, { 2, 13, 16, 21 } }, P.panel, "UpperWallN")
	wall(false, -16, 16, 71, 72, 12, 24, { { -14, -7, F2, F2 + 10 }, { -3, 3, 16, 21 }, { 7, 14, F2, F2 + 10 } }, P.panel, "UpperWallS")
	wall(true, 49, 71, -16, -15, 12, 24, { { 54, 66, 16, 21 } }, P.panel, "UpperWallW")
	wall(true, 49, 71, 15, 16, 12, 24, { { 54, 66, 16, 21 } }, P.panel, "UpperWallE")
	blk(-17, 24, 47, 17, 25, 73, P.steelDark, "OfficeRoof")
	blk(-2, 25, 56, 2, 33, 60, P.steel, "SignalMast")
	blk(-0.5, 33, 57.5, 0.5, 34, 58.5, P.lamp, "MastLight")
	blk(-16.3, 11, 48, 16.3, 12, 48.3, P.panelBlue, "OfficeBand")
	-- balcony (Y 12..13) along the south side with rails, posts down to the quay
	blk(-22, 12, 72, 22, F2, 80, P.steelDark, "Balcony")
	blk(-22, F2, 79.7, 22, F2 + 3.5, 80, P.steel, "BalconyRail")
	for _, x in { -21, 21 } do
		blk(x - 0.5, 0, 78.5, x + 0.5, 12, 79.5, P.steel, "BalconyPost")
	end
	-- exterior stairs on both ends of the balcony (13 steps, 2-stud runs)
	stairs(-48, 72, -22, 78, "+X", 0, F2, P.concreteDark)
	stairs(22, 72, 48, 78, "-X", 0, F2, P.concreteDark)
	-- interior: ground desks against the walls (centre clear), radio and chart table upstairs
	blk(-14.5, 0, 50, -8, 3, 53, P.planksDark, "Desk")
	blk(8, 0, 66, 14.5, 3, 70, P.planksDark, "Desk")
	blk(10, 0, 50, 14.5, 7, 52, P.steel, "FilingCabinet")
	blk(-6, F2, 60, 6, F2 + 3, 64, P.planksDark, "ChartTable")
	blk(-14.5, F2, 50, -10, F2 + 5, 53, P.steel, "RadioRack")
	blk(-15, 9, 59, -14.5, 11, 61, P.lamp, "WallLamp")

	section("QuayApron")
	for _, s in { -1, 1 } do
		-- reefers and cargo on the apron (cover every 15..25 studs)
		container(s * 34, s * 54, 40, 48, 0, P.cWhite)
		container(s * 70, s * 78, 50, 70, 0, if s < 0 then P.cRed else P.cTeal)
		container(s * 96, s * 116, 66, 74, 0, P.cYellow)
		pallet(s * 58, 62, 3, P.tarp)
		pallet(s * 90, 44, 3, P.planks)
		crate(s * 112, 0, 50, 4, 0.2)
		crate(s * 112, 0, 54.5, 3, 0.6)
		forklift(s * 30, 64, s * 0.4)
		lightTower(s * 60, 80, 20)
		blk(s * 122 - 4, 0, 36, s * 122 + 4, 7, 42, P.panelBlue, "IcePlant")
		cylY(s * 98, 0, 82, 6, 4, P.steel, "IceSilo")
		for x = 20, 170, 25 do
			bollard(s * x, 0, 86)
		end
	end

	-------------------------------------------------------------------------------------------
	-- Harbour water (south flank): the pier at Z 100..112 (deck top Y 0, piles to the water),
	-- gangways from the quay, steps out of the water, boats.
	-------------------------------------------------------------------------------------------
	section("Pier")
	blk(-176, -0.6, 100, 176, 0, 112, P.planks, "PierDeck")
	blk(-176, -1, 100, 176, -0.6, 100.6, P.planksDark, "PierStringer")
	blk(-176, -1, 111.4, 176, -0.6, 112, P.planksDark, "PierStringer")
	for x = -168, 168, 16 do
		cylY(x, WATER_Y, 100.5, -0.6, 1.2, P.planksDark, "Pile")
		cylY(x, WATER_Y, 111.5, -0.6, 1.2, P.planksDark, "Pile")
	end
	-- gangways from the quay (deck top Y 0) at X 0, |X| 44 and |X| 160 (base side)
	for _, g in { { -4, 4 }, { -48, -40 }, { 40, 48 }, { -164, -156 }, { 156, 164 } } do
		blk(g[1], -0.6, QUAY_Z, g[2], 0, 100, P.planksDark, "Gangway")
		blk(g[1] - 0.3, 0, QUAY_Z, g[1], 3, 100, P.steel, "GangwayRail")
		blk(g[2], 0, QUAY_Z, g[2] + 0.3, 3, 100, P.steel, "GangwayRail")
	end
	-- steps out of the water (2 x 0.75 rise): on the pier's south edge and onto the quay
	for _, s in { -1, 1 } do
		stairs(s * 24 - 4, 112, s * 24 + 4, 116, "-Z", WATER_Y, 0, P.concreteDark)
		stairs(s * 120 - 4, 112, s * 120 + 4, 116, "-Z", WATER_Y, 0, P.concreteDark)
		stairs(s * 80 - 4, QUAY_Z, s * 80 + 4, QUAY_Z + 4, "-Z", WATER_Y, 0, P.concreteDark)
		stairs(s * 80 - 4, 96, s * 80 + 4, 100, "+Z", WATER_Y, 0, P.concreteDark)
	end
	-- pier furniture: fish boxes, net piles, cleats, a davit, bait huts hung off the south edge
	for _, s in { -1, 1 } do
		for x = 12, 172, 32 do
			blk(s * x - 0.8, 0, 111, s * x + 0.8, 0.6, 111.8, P.steelDark, "Cleat")
		end
		blk(s * 36, 0, 101, s * 42, 2.6, 104, P.net, "NetPile")
		totes(s * 64, 109)
		crate(s * 104, 0, 102.5, 3.5, 0.2)
		blk(s * 140, 0, 108, s * 145, 3.5, 111, P.net, "NetPile")
		-- bait hut on its own piles south of the pier (open door onto the pier)
		blk(s * 50, -0.6, 112, s * 60, 0, 120, P.planks, "HutDeck")
		wall(false, s * 50, s * 60, 119, 120, 0, 9, {}, P.panelBlue, "HutWall")
		wall(true, 112, 119, s * 50, s * 50 + s * 1, 0, 9, {}, P.panelBlue, "HutWall")
		wall(true, 112, 119, s * 60 - s * 1, s * 60, 0, 9, {}, P.panelBlue, "HutWall")
		wall(false, s * 50, s * 60, 112, 113, 0, 9, { { s * 52, s * 58, 0, 9 } }, P.panelBlue, "HutWall")
		blk(s * 49.5, 9, 111.5, s * 60.5, 9.6, 120.5, P.steelDark, "HutRoof")
		cylY(s * 50, WATER_Y, 120, -0.6, 1, P.planksDark, "Pile")
		cylY(s * 60, WATER_Y, 120, -0.6, 1, P.planksDark, "Pile")
		-- moored boats
		boat(s * 92, 118, 22, if s < 0 then P.cRed else P.cTeal)
		boat(s * 10, 118, 14, P.panelBlue)
		boat(s * 118, 94, 14, P.paintWhite)
		boat(s * 22, 94, 12, P.cYellow)
		-- channel marker post in the water
		cylY(s * 150, WATER_Y, 120, 8, 1.2, P.cRed, "MarkerPost")
	end
	-- east pier fuel dock (bomb site B): pumps and drums as cover
	blk(83, 0, 100.6, 86, 6, 103, P.cRed, "FuelPump")
	blk(97, 0, 109, 101, 3.4, 111.4, P.steel, "FuelDrums")
	blk(-101, 0, 109, -97, 3.4, 111.4, P.steel, "FuelDrums")
	blk(-86, 0, 100.6, -83, 6, 103, P.cRed, "FuelPump")

	-------------------------------------------------------------------------------------------
	-- Team bases: Sable west gate, Talon east gate (|X| 144..180). Double-stacked container
	-- rampart at |X| 136..144 with five gaps (flank, north, middle, south, pier) and single
	-- containers as outer baffles in front of the three land-lane gaps.
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

	-- containers along Z between z0 and z1 at |X| RAMPART, standing on the quay or the water
	local function rampartRun(s: number, z0: number, z1: number)
		local pieces = {}
		if z0 < QUAY_Z and z1 > QUAY_Z then
			table.insert(pieces, { z0, QUAY_Z, 0 })
			table.insert(pieces, { QUAY_Z, z1, WATER_Y })
		else
			table.insert(pieces, { z0, z1, if z0 >= QUAY_Z then WATER_Y else 0 })
		end
		for _, pc in pieces do
			local len = pc[2] - pc[1]
			local n = math.ceil(len / 20 - 1e-6)
			local step = len / n
			for i = 0, n - 1 do
				for level = 0, 1 do
					container(s * RAMPART[1], s * RAMPART[2], pc[1] + i * step, pc[1] + (i + 1) * step, pc[3] + level * 9)
				end
			end
		end
	end

	for _, s in { -1, 1 } do
		local team = if s < 0 then "Sable" else "Talon"
		local accent = if s < 0 then P.sable else P.talon
		section(team .. "Base")
		local cursor = -ZB
		for _, g in RAMPART_GAPS do
			rampartRun(s, cursor, g[1])
			cursor = g[2]
			-- team colour gate posts
			local floorY = if g[1] >= QUAY_Z then WATER_Y else 0
			blk(s * RAMPART[1], floorY, g[1] - 0.8, s * (RAMPART[1] + 1), floorY + 14, g[1], accent, "GatePost")
			blk(s * RAMPART[1], floorY, g[2], s * (RAMPART[1] + 1), floorY + 14, g[2] + 0.8, accent, "GatePost")
		end
		rampartRun(s, cursor, ZB)
		-- outer baffles: single containers along Z
		for _, b in BAFFLES do
			local mid = (b[1] + b[2]) / 2
			container(s * BAFFLE[1], s * BAFFLE[2], b[1], mid, 0, P.cWhite)
			container(s * BAFFLE[1], s * BAFFLE[2], mid, b[2], 0, if s < 0 then P.cBlue else P.cOrange)
			blk(s * (BAFFLE[1] - 0.2), 5, b[1] + 1, s * BAFFLE[1], 6.5, b[2] - 1, accent, "BaffleStripe")
		end
		-- base yard: site cabins against the dock wall, gate barrier, lights, team markings
		blk(s * 172, 0, -100, s * 180, 9, -60, P.panelBlue, "SiteCabin")
		blk(s * 172, 0, 62, s * 180, 9, 84, P.panelBlue, "SiteCabin")
		blk(s * 171.6, 3, -96, s * 172, 7, -64, accent, "CabinStripe")
		blk(s * 171.6, 3, 66, s * 172, 7, 80, accent, "CabinStripe")
		lightTower(s * 176, -40, 20)
		lightTower(s * 176, 40, 20)
		pallet(s * 170, -112, 3, P.planks)
		pallet(s * 162, -104, 2, P.tarp)
		for _, z in { -48, -24, 0, 24, 48 } do
			blk(s * 159 - 0.5, 0.05, z - 6, s * 159 + 0.5, 0.1, z + 6, accent, "BayMarking")
		end

		-- team spawns: two columns of five behind the rampart, facing the map
		for _, z in { -48, -24, 0, 24, 48 } do
			for _, x in { 152, 166 } do
				spawnPart(s * x, 0.05, z + (if x == 166 then 6 else 0), 0, z, team, false)
			end
		end
	end

	-------------------------------------------------------------------------------------------
	-- FFA spawns spread over every zone.
	-------------------------------------------------------------------------------------------
	local ffa = {
		{ -160, 0.05, -76, 0, -76 },
		{ 160, 0.05, 74, 0, 74 },
		{ -120, 0.05, -123, 0, -123 },
		{ 120, 0.05, -128, 0, -128 },
		{ -12, 0.05, -128.3, 0, -128.3 },
		{ -86, 0, -83, -60, -83 },
		{ 86, 0, -76, 60, -76 },
		{ -38, 0, -86, 0, -86 },
		{ 36, 0, -62, 0, -80 },
		{ -70, 0.05, -31, 0, -31 },
		{ 74, 0.05, -6, 0, -6 },
		{ -30, 0.05, -2, 0, -2 },
		{ 30, 0.05, 18, 0, 18 },
		{ -11, CW, -20, -11, 0 },
		{ -90, 0, 60, 0, 60 },
		{ 104, 0, 46, 0, 46 },
		{ 0, 0, 60, 0, 0 },
		{ -130, 0, 106, 0, 106 },
		{ 30, 0, 106, 0, 106 },
		{ -36, WATER_Y, 116, 0, 116 },
		{ 150, WATER_Y, 94, 0, 94 },
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

	-- Domination: all three flags in the central alley of the container yard.
	zone("FlagA", "Flag", -90, 0.05, -6, 18, 18, { Label = "A" })
	zone("FlagB", "Flag", 0, 0.05, -6, 18, 18, { Label = "B" })
	zone("FlagC", "Flag", 90, 0.05, -6, 18, 18, { Label = "C" })
	-- Hardpoint rotation: under the gantry -> fish market -> cold store -> harbourmaster -> net loft.
	zone("Hardpoint1", "Hardpoint", 0, 0.05, -6, 24, 18, { Order = 1 })
	zone("Hardpoint2", "Hardpoint", 0, 0, -80, 24, 20, { Order = 2 })
	zone("Hardpoint3", "Hardpoint", -86, 0, -83, 20, 18, { Order = 3 })
	zone("Hardpoint4", "Hardpoint", 0, 0, 60, 24, 18, { Order = 4 })
	zone("Hardpoint5", "Hardpoint", 86, 0, -83, 20, 18, { Order = 5 })
	-- Search and Destroy: Sable attacks first; Talon defends the net loft and the fuel dock.
	zone("BombSiteA", "BombSite", 86, 0, -83, 14, 14, { Label = "A" })
	zone("BombSiteB", "BombSite", 91, 0, 106, 14, 10, { Label = "B" })

	-------------------------------------------------------------------------------------------
	-- Lobby camera (frames the gantry crane over the container yard) + model attributes.
	-------------------------------------------------------------------------------------------
	local cam = Instance.new("Part")
	cam.Name = "LobbyCamera"
	cam.Size = Vector3.new(1, 1, 1)
	cam.CFrame = CFrame.lookAt(Vector3.new(78, 46, 92), Vector3.new(0, 12, -8))
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
