--!strict
--[[
	Iron Borough: a dense, rainy industrial city block at night. The close-quarters map.
	Small/medium 6v6 map, ~256 x 196 studs playable (boundary inner faces at X = +-128, Z = +-98).

	Axes: +X = east, -Z = north (top of the ASCII sketch in docs/maps/IronBorough.md).
	All walkable ground has its top surface at Y = 0, except the underpass (floor Y -10) and
	the bandstand platform (Y 1). The bottom of every ground slab is Y -14 (BoundsMin.Y),
	because the underpass reaches lower than the street. KillY is -40.

	Bands, north -> south:
	  Z  -98.. -82  Back alleys (north flank; cross alleys at X +-33 and the arcade at X 0)
	  Z  -82.. -50  Brick shop row (north lane: walk-through shops, flats above, arcade)
	  Z  -50..  -6  Iron Street (middle lane) under the rail viaduct (deck Y 18..21, Z -34..-22)
	  Z   -6..  62  Park square in the centre, print works (west) and tram substation (east)
	  Z   56..  76  Canal Row strip (south edge of the park, stair down into the underpass)
	  Z   76..  98  Goods-line embankment with the pedestrian underpass beneath (south flank)
	Service lanes at |X| 96..106 run north-south just inside each base wall.
	Sable spawn = west yard (X < -108), Talon spawn = east yard (X > 108).
	The layout is mirror-symmetric across X = 0; only accent colours and shop dressing differ.

	Objectives (see docs/maps/IronBorough.md, "Objectives"):
	  Flags     A west street, B bandstand, C east street
	  Hardpoint 1 west corner shop, 2 bandstand, 3 east corner shop, 4 underpass, 5 under the viaduct
	  S&D       Sable attacks in round 1; sites A (east shop row) and B (tram substation)

	build() only uses Instance.new / Vector3 / CFrame / Color3 / Enum / math so it also runs under Lune.
]]

type Style = {
	mat: Enum.Material,
	color: Color3,
	transparency: number?,
	collide: boolean?,
	reflect: number?,
}

local function style(mat: Enum.Material, r: number, g: number, b: number, transparency: number?): Style
	return { mat = mat, color = Color3.fromRGB(r, g, b), transparency = transparency }
end

local function wet(st: Style, reflect: number): Style
	return { mat = st.mat, color = st.color, transparency = st.transparency, collide = st.collide, reflect = reflect }
end

local M = Enum.Material

-- Rain-soaked night palette: dark brick, wet slate and asphalt, warm sodium and neon light.
local P = {
	brick = style(M.Brick, 132, 64, 50),
	brickDark = style(M.Brick, 92, 46, 40),
	brickSoot = style(M.Brick, 70, 58, 56),
	asphalt = wet(style(M.Asphalt, 46, 48, 54), 0.08),
	slate = wet(style(M.Slate, 64, 70, 80), 0.1),
	slateDark = wet(style(M.Slate, 44, 48, 56), 0.08),
	paving = wet(style(M.Slate, 98, 100, 108), 0.06),
	cobble = wet(style(M.Cobblestone, 84, 84, 90), 0.05),
	concrete = style(M.Concrete, 122, 122, 126),
	concreteDark = style(M.Concrete, 84, 86, 92),
	metal = style(M.Metal, 110, 114, 122),
	metalDark = style(M.DiamondPlate, 62, 66, 74),
	iron = style(M.CorrodedMetal, 86, 70, 62),
	ironGreen = style(M.Metal, 46, 82, 70),
	wood = style(M.WoodPlanks, 104, 78, 58),
	woodDark = style(M.Wood, 70, 52, 42),
	tile = style(M.CeramicTiles, 180, 176, 164),
	tileBlack = style(M.CeramicTiles, 40, 40, 44),
	grass = style(M.Grass, 52, 78, 48),
	hedge = style(M.LeafyGrass, 40, 66, 40),
	leaves = style(M.Grass, 44, 70, 46),
	bark = style(M.Wood, 64, 50, 42),
	rubber = style(M.Rubber, 30, 30, 34),
	glass = style(M.Glass, 140, 170, 190, 0.5),
	glassDark = wet(style(M.Glass, 34, 40, 52), 0.3),
	board = style(M.SmoothPlastic, 28, 30, 36),
	puddle = wet(style(M.SmoothPlastic, 30, 34, 42), 0.45),
	paintYellow = style(M.SmoothPlastic, 214, 176, 60),
	paintWhite = style(M.SmoothPlastic, 210, 212, 214),
	paintRed = style(M.SmoothPlastic, 150, 40, 40),
	paintTeal = style(M.SmoothPlastic, 40, 110, 110),
	paintCream = style(M.SmoothPlastic, 206, 192, 160),
	lamp = style(M.Neon, 255, 186, 110),
	neonPink = style(M.Neon, 255, 92, 160),
	neonTeal = style(M.Neon, 70, 230, 220),
	neonAmber = style(M.Neon, 255, 150, 50),
	neonRed = style(M.Neon, 255, 60, 50),
	windowLit = style(M.Neon, 255, 196, 128),
	sable = style(M.SmoothPlastic, 52, 96, 130),
	talon = style(M.SmoothPlastic, 196, 120, 46),
}

local MapModule = {}

MapModule.id = "IronBorough"
MapModule.displayName = "Iron Borough"

-- Night, but readable: bright moon, high ambient, warm colour shift from the street lamps.
MapModule.lighting = {
	ClockTime = 0.5,
	GeographicLatitude = 52,
	Brightness = 2,
	ExposureCompensation = 0.6,
	Ambient = Color3.fromRGB(122, 118, 132),
	OutdoorAmbient = Color3.fromRGB(132, 132, 152),
	ColorShift_Top = Color3.fromRGB(255, 196, 140),
	ColorShift_Bottom = Color3.fromRGB(70, 84, 120),
	EnvironmentDiffuseScale = 0.6,
	EnvironmentSpecularScale = 0.7,
	ShadowSoftness = 0.3,
	GlobalShadows = true,
	FogColor = Color3.fromRGB(52, 58, 74),
	FogStart = 260,
	FogEnd = 1000,
}

-- Low rain haze; density kept moderate so players stay visible across the whole map.
MapModule.atmosphere = {
	Density = 0.28,
	Offset = 0.05,
	Color = Color3.fromRGB(110, 118, 140),
	Decay = Color3.fromRGB(76, 70, 96),
	Glare = 0.2,
	Haze = 2,
}

MapModule.killY = -40

local BOUNDS_MIN = Vector3.new(-132, -14, -102)
local BOUNDS_MAX = Vector3.new(132, 60, 102)

-- Base wall gaps (Z ranges) on each team's wall at |X| 106..108, shared by geometry and docs.
local WALL_X = 106
local GAPS = { { -94, -84 }, { -38, -26 }, { 24, 34 }, { 80, 92 } }

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

	-- Props: parts built inside prop("Key", fn) are tagged so EnvironmentService can lay a ForgeGUI
	-- mesh (Assets.Models["Prop.Key"]) over them. Nested props belong to the outermost one.
	local propKey: string? = nil
	local propCount = 0
	local function prop(key: string, fn: () -> ())
		local outer = propKey
		if outer == nil then
			propCount += 1
			propKey = key
		end
		fn()
		propKey = outer
	end

	local function finish(p: BasePart, st: Style, name: string?)
		p.Anchored = true
		p.CanQuery = true
		p.CanCollide = if st.collide == nil then true else st.collide
		p.Material = st.mat
		p.Color = st.color
		p.Transparency = st.transparency or 0
		p.Reflectance = st.reflect or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Name = name or "Part"
		if propKey then
			p:SetAttribute("Prop", propKey)
			p:SetAttribute("PropId", propCount)
		end
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

	-- Vertical cylinder (post, trunk, bollard).
	local function cylY(x: number, y0: number, z: number, y1: number, d: number, st: Style, name: string?): Part
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(y1 - y0, d, d)
		p.CFrame = CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
		finish(p, st, name)
		return p
	end

	-- Horizontal cylinder along X (pipes, paper rolls) or Z (wheels, cable drums).
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

	local function light(p: BasePart, color: Color3, range: number, brightness: number)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Shadows = false
		l.Parent = p
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
		prop("Crate", function()
			box(CFrame.new(x, y + s / 2, z) * CFrame.Angles(0, yaw or 0, 0), Vector3.new(s, s, s), P.wood, "Crate")
		end)
	end

	-- Wheelie dumpster, long axis along X (alongZ = false) or Z.
	local function dumpster(x: number, z: number, alongZ: boolean, st: Style)
		prop("Dumpster", function()
			local hx, hz = if alongZ then 1.8 else 3.2, if alongZ then 3.2 else 1.8
			blk(x - hx, 0.4, z - hz, x + hx, 4.4, z + hz, st, "Dumpster")
			blk(x - hx - 0.1, 4.4, z - hz - 0.1, x + hx + 0.1, 4.8, z + hz + 0.1, P.rubber, "DumpsterLid")
		end)
	end

	-- Parked car: body + cabin + 4 wheels. Long axis along X.
	local function car(x: number, z: number, st: Style)
		prop("Car", function()
			blk(x - 5, 0.8, z - 2.4, x + 5, 3, z + 2.4, st, "CarBody")
			blk(x - 2.6, 3, z - 2.1, x + 2.4, 4.8, z + 2.1, st, "CarCabin")
			blk(x - 2.5, 3.2, z - 2.15, x + 2.3, 4.6, z + 2.15, P.glassDark, "CarWindows")
			for _, w in { { -3.3, -2.3 }, { 3.3, -2.3 }, { -3.3, 2.3 }, { 3.3, 2.3 } } do
				cylH(x + w[1], 1, z + w[2], 0.8, 2, true, P.rubber, "Wheel")
			end
		end)
	end

	-- Delivery van: taller, full cover. Long axis along X.
	local function van(x: number, z: number, st: Style)
		prop("Van", function()
			blk(x - 7, 0.8, z - 2.8, x + 7, 7.4, z + 2.8, st, "VanBody")
			blk(x + 4.8, 4, z - 2.85, x + 6.8, 6.6, z + 2.85, P.glassDark, "VanWindscreen")
			for _, w in { { -4.6, -2.7 }, { 4.6, -2.7 }, { -4.6, 2.7 }, { 4.6, 2.7 } } do
				cylH(x + w[1], 1.1, z + w[2], 0.8, 2.2, true, P.rubber, "Wheel")
			end
		end)
	end

	-- Warm sodium/neon street lamp with a real light.
	local function streetLamp(x: number, z: number, armDir: number)
		prop("StreetLamp", function()
			cylY(x, 0, z, 13, 0.7, P.ironGreen, "LampPost")
			blk(x - 0.5, 0, z - 0.5, x + 0.5, 1.2, z + 0.5, P.ironGreen, "LampBase")
			blk(x - 0.25, 12.6, z, x + 0.25, 13, z + armDir * 2.6, P.ironGreen, "LampArm")
			blk(x - 0.7, 12, z + armDir * 2.2 - 0.7, x + 0.7, 12.6, z + armDir * 2.2 + 0.7, P.metalDark, "LampHood")
			local bulb = blk(x - 0.5, 11.6, z + armDir * 2.2 - 0.5, x + 0.5, 12, z + armDir * 2.2 + 0.5, P.lamp, "LampBulb")
			light(bulb, P.lamp.color, 30, 1.6)
		end)
	end

	local function bench(x: number, z: number, len: number, alongZ: boolean)
		prop("Bench", function()
			local hx, hz = if alongZ then 0.9 else len / 2, if alongZ then len / 2 else 0.9
			blk(x - hx, 0, z - hz, x + hx, 1.6, z + hz, P.woodDark, "Bench")
			local bx, bz = if alongZ then 0.25 else len / 2, if alongZ then len / 2 else 0.25
			blk(x - bx, 1.6, z - bz, x + bx, 3.4, z + bz, P.wood, "BenchBack")
		end)
	end

	local function tree(x: number, z: number, h: number)
		prop("StreetTree", function()
			cylY(x, 0, z, h, 1.6, P.bark, "Trunk")
			blk(x - 4.5, h - 1, z - 4.5, x + 4.5, h + 5, z + 4.5, P.leaves, "Canopy")
			blk(x - 3, h + 5, z - 3, x + 3, h + 7, z + 3, P.leaves, "Canopy")
		end)
	end

	local function puddle(x: number, z: number, sx: number, sz: number)
		blk(x - sx / 2, 0, z - sz / 2, x + sx / 2, 0.04, z + sz / 2, P.puddle, "Puddle")
	end

	-------------------------------------------------------------------------------------------
	-- Ground. Every slab reaches down to Y -14 and they abut exactly, so there are no holes.
	-------------------------------------------------------------------------------------------
	section("Ground")
	blk(-132, -14, -102, 132, 0, -82, P.cobble, "AlleyGround")
	blk(-132, -14, -82, 132, 0, -50, P.tile, "ShopFloors")
	blk(-132, -14, -50, 132, 0, -44, P.paving, "PavementN")
	blk(-132, -14, -44, 132, 0, -12, P.asphalt, "IronStreet")
	blk(-132, -14, -12, 132, 0, -6, P.paving, "PavementS")
	blk(-132, -14, -6, -44, 0, 62, P.slate, "Ground")
	blk(-44, -14, -6, 44, 0, 62, P.grass, "ParkLawn")
	blk(44, -14, -6, 132, 0, 62, P.slate, "Ground")
	-- Canal Row strip: split around the stairwell down to the underpass (X -7..7)
	blk(-132, -14, 62, -7, 0, 76, P.paving, "CanalRow")
	blk(7, -14, 62, 132, 0, 76, P.paving, "CanalRow")
	blk(-7, -14, 62, 7, -10, 76, P.concreteDark, "StairwellFloor")
	-- embankment band: base yards at the ends, cuttings, underpass floor
	blk(-132, -14, 76, -106, 0, 98, P.slate, "Ground")
	blk(106, -14, 76, 132, 0, 98, P.slate, "Ground")
	blk(-106, -14, 76, 106, -10, 98, P.concreteDark, "UnderpassFloor")
	blk(-132, -14, 98, 132, 0, 102, P.slate, "Ground")
	-- road markings, kerbs (0.05-0.3 thick, walkable) and puddles
	for x = -96, 96, 16 do
		blk(x - 3, 0, -28.25, x + 3, 0.05, -27.75, P.paintWhite, "LaneDash")
	end
	blk(-106, 0, -44.4, 106, 0.3, -43.6, P.concrete, "Kerb")
	blk(-106, 0, -12.4, 106, 0.3, -11.6, P.concrete, "Kerb")
	for _, x in { -44, 44 } do
		for i = 0, 5 do
			blk(x - 4, 0, -42 + i * 2.6, x + 4, 0.05, -41 + i * 2.6, P.paintWhite, "Crossing")
		end
	end
	for _, pd in { { -70, -40, 6, 3 }, { 24, -16, 8, 3 }, { -18, -88, 5, 4 }, { 60, -92, 6, 3 }, { -60, 70, 7, 3 }, { 30, 68, 5, 4 }, { 100, -30, 4, 6 }, { -100, 10, 4, 7 } } do
		puddle(pd[1], pd[2], pd[3], pd[4])
	end

	-------------------------------------------------------------------------------------------
	-- Boundary: tall soot-brick backs of neighbouring buildings. Inner faces X +-128, Z +-98.
	-------------------------------------------------------------------------------------------
	section("Boundary")
	blk(-132, -14, -102, 132, 34, -98, P.brickSoot, "BoundaryN")
	blk(-132, -14, 98, 132, 34, 102, P.brickSoot, "BoundaryS")
	blk(-132, -14, -98, -128, 34, 98, P.brickSoot, "BoundaryW")
	blk(128, -14, -98, 132, 34, 98, P.brickSoot, "BoundaryE")
	-- window grid on the north wall (dark glass, a few lit)
	local lit = 0
	for x = -116, 116, 16 do
		for _, y in { 16, 24 } do
			lit += 1
			local st = if lit % 5 == 0 then P.windowLit else P.glassDark
			blk(x - 2.5, y, -98.2, x + 2.5, y + 4, -98, st, "BackWindow")
		end
	end
	for z = -80, 80, 20 do
		blk(-128, 20, z - 2.5, -127.8, 24, z + 2.5, P.glassDark, "BackWindow")
		blk(127.8, 20, z - 2.5, 128, 24, z + 2.5, P.glassDark, "BackWindow")
	end
	-- drainpipes
	for x = -104, 104, 52 do
		blk(x - 0.4, 0, -98.8, x + 0.4, 30, -98, P.metalDark, "Drainpipe")
	end

	-------------------------------------------------------------------------------------------
	-- Back alleys (north flank): Z -98..-82. Cross alleys X +-30..36 and the arcade at X 0.
	-------------------------------------------------------------------------------------------
	section("BackAlleys")
	for _, s in { -1, 1 } do
		dumpster(s * 16, -95.6, false, P.ironGreen)
		dumpster(s * 46, -84.4, false, P.paintTeal)
		dumpster(s * 66, -95.6, false, P.ironGreen)
		dumpster(s * 86, -84.4, false, P.paintRed)
		crate(s * 24, 0, -94.5, 3, 0.2)
		crate(s * 76, 0, -84.5, 3, -0.3)
		crate(s * 76, 3, -84.6, 2.2, 0.1)
		-- pallets stacked against the boundary, bins
		blk(s * 100, 0, -97.8, s * 104, 3.6, -92, P.wood, "PalletStack")
		cylY(s * 56, 0, -96.6, 3, 2, P.metalDark, "Bin")
		cylY(s * 36.5, 0, -96.6, 3, 2, P.metalDark, "Bin")
		-- fire escapes on the shop backs (lowest landing Y 12: out of reach)
		for _, x in { 60, 20 } do
			blk(s * x - 6, 12, -84.6, s * x + 6, 12.4, -82, P.metalDark, "FireEscape")
			blk(s * x - 6, 18, -84.6, s * x + 6, 18.4, -82, P.metalDark, "FireEscape")
			blk(s * x - 6, 12.4, -84.6, s * x + 6, 13.6, -84.4, P.metal, "FireEscapeRail")
			blk(s * x - 6, 18.4, -84.6, s * x + 6, 19.6, -84.4, P.metal, "FireEscapeRail")
		end
		-- AC units and vents on the back walls (above head height)
		blk(s * 84, 8, -83.4, s * 88, 11, -82, P.metal, "ACUnit")
		blk(s * 40, 8, -83.4, s * 44, 11, -82, P.metal, "ACUnit")
		local al = blk(s * 72 - 1, 9, -82.6, s * 72 + 1, 9.6, -82, P.lamp, "AlleyLight")
		light(al, P.lamp.color, 20, 1)
		-- cross-alley clutter (kept to one side)
		crate(s * 34.5, 0, -66, 2.4)
		cylY(s * 31.5, 0, -80, 3, 2, P.metalDark, "Bin")
	end
	local cl = blk(-1, 9, -97.6, 1, 9.6, -97, P.lamp, "AlleyLight")
	light(cl, P.lamp.color, 20, 1)

	-------------------------------------------------------------------------------------------
	-- Brick shop row (north lane): Z -82..-50. Shops at ground level, solid flats above (Y 12..24).
	-- Blocks: west X -96..-36, centre X -30..30 (arcade X -4..4), east X 36..96.
	-------------------------------------------------------------------------------------------
	section("ShopRow")
	local SH = 12
	local Z_BACK, Z_FRONT = -82, -50
	local signs = { P.neonPink, P.neonTeal, P.neonAmber, P.neonRed }
	local signIndex = 0

	-- One shop between x0 and x1 (x0 < x1): front door + display windows, back door.
	local function shopFront(x0: number, x1: number)
		local cx = (x0 + x1) / 2
		local front: { Opening } = { { cx - 4, cx + 4, 0, 9.5 }, { x0 + 1.5, cx - 5.5, 2.5, 8.5 }, { cx + 5.5, x1 - 1.5, 2.5, 8.5 } }
		wall(false, x0, x1, Z_FRONT - 1, Z_FRONT, 0, SH, front, P.brick, "ShopFront")
		blk(x0 + 1.5, 2.5, Z_FRONT - 0.6, cx - 5.5, 8.5, Z_FRONT - 0.4, P.glass, "DisplayGlass")
		blk(cx + 5.5, 2.5, Z_FRONT - 0.6, x1 - 1.5, 8.5, Z_FRONT - 0.4, P.glass, "DisplayGlass")
		blk(x0 + 1.5, 0, Z_FRONT - 0.2, cx - 5.5, 2.5, Z_FRONT + 0.3, P.woodDark, "Stallriser")
		blk(cx + 5.5, 0, Z_FRONT - 0.2, x1 - 1.5, 2.5, Z_FRONT + 0.3, P.woodDark, "Stallriser")
		wall(false, x0, x1, Z_BACK, Z_BACK + 1, 0, SH, { { cx - 3, cx + 3, 0, 9.5 } }, P.brickDark, "ShopBack")
		-- fascia board, neon sign and awning over the front
		signIndex += 1
		local sign = signs[(signIndex - 1) % #signs + 1]
		blk(x0 + 0.5, 9.6, Z_FRONT, x1 - 0.5, 11.6, Z_FRONT + 0.4, P.board, "Fascia")
		local n = blk(cx - 5, 10.2, Z_FRONT + 0.4, cx + 5, 11, Z_FRONT + 0.6, sign, "ShopSign")
		light(n, sign.color, 16, 0.9)
		blk(x0 + 1, 9.2, Z_FRONT, x1 - 1, 9.6, Z_FRONT + 3.5, if signIndex % 2 == 0 then P.paintTeal else P.paintRed, "Awning")
		-- ceiling light
		local cl2 = blk(cx - 1.5, SH - 0.5, -67, cx + 1.5, SH, -65, P.lamp, "ShopLight")
		light(cl2, P.lamp.color, 18, 0.8)
	end

	-- Wall along Z between shops (or at a block end) with an optional doorway.
	local function partyWall(x: number, door: boolean)
		wall(true, Z_BACK + 1, Z_FRONT - 1, x - 0.5, x + 0.5, 0, SH, if door then { { -70, -63, 0, 9.5 } } else {}, P.brickDark, "PartyWall")
	end

	-- Flats above a block: solid mass with window insets and a cornice.
	local function flats(x0: number, x1: number)
		blk(x0, SH, Z_BACK, x1, 24, Z_FRONT, P.brick, "Flats")
		blk(x0 - 0.3, 24, Z_BACK - 0.3, x1 + 0.3, 25, Z_FRONT + 0.3, P.concreteDark, "Cornice")
		blk(x0 - 0.2, SH, Z_FRONT, x1 + 0.2, SH + 0.8, Z_FRONT + 0.3, P.concrete, "StringCourse")
		local k = 0
		for x = x0 + 5, x1 - 5, 8 do
			k += 1
			for _, y in { 14.5, 19.5 } do
				local st = if (k + math.floor(y)) % 4 == 0 then P.windowLit else P.glassDark
				blk(x - 1.8, y, Z_FRONT, x + 1.8, y + 3.4, Z_FRONT + 0.2, st, "FlatWindow")
				blk(x - 1.8, y, Z_BACK - 0.2, x + 1.8, y + 3.4, Z_BACK, P.glassDark, "FlatWindow")
			end
		end
		cylY(x0 + 4, 25, -70, 30, 2.4, P.brickDark, "Chimney")
		blk(x1 - 8, 25, -76, x1 - 3, 29, -71, P.woodDark, "WaterTank")
	end

	for _, s in { -1, 1 } do
		-- outer block: three shops; the block ends face a service lane and a cross alley
		local a, b, c, d = s * 96, s * 76, s * 56, s * 36
		local lo = function(p: number, q: number): (number, number)
			return math.min(p, q), math.max(p, q)
		end
		local x0, x1 = lo(a, b)
		shopFront(x0, x1)
		x0, x1 = lo(b, c)
		shopFront(x0, x1)
		x0, x1 = lo(c, d)
		shopFront(x0, x1)
		-- end walls: service-lane end has a side door, cross-alley end has a side door
		wall(true, Z_BACK, Z_FRONT, a - s * 0.5, a + s * 0.5, 0, SH, { { -62, -55, 0, 9.5 } }, P.brickDark, "BlockEnd")
		wall(true, Z_BACK, Z_FRONT, d - s * 0.5, d + s * 0.5, 0, SH, { { -62, -55, 0, 9.5 } }, P.brickDark, "BlockEnd")
		partyWall(b, true)
		partyWall(c, true)
		local f0, f1 = lo(a, d)
		flats(f0 - 0.5, f1 + 0.5)

		-- centre block half: one shop between the cross alley and the arcade
		local e, g = s * 30, s * 4
		x0, x1 = lo(e, g)
		shopFront(x0, x1)
		wall(true, Z_BACK, Z_FRONT, e - s * 0.5, e + s * 0.5, 0, SH, { { -76, -70, 0, 9.5 } }, P.brickDark, "BlockEnd")
		wall(true, Z_BACK, Z_FRONT, g - s * 0.5, g + s * 0.5, 0, SH, { { -70, -62, 0, 9.5 } }, P.brickDark, "ArcadeWall")

		-- shop interiors (counters crouch-high, shelving full height, all clear of the centres)
		-- outermost shop: hardware store
		blk(s * 94, 0, -80, s * 91, 7.5, -66, P.woodDark, "Shelving")
		blk(s * 83, 0, -64, s * 77.5, 3.6, -61, P.wood, "Counter")
		crate(s * 79, 0, -78, 3, 0.2)
		-- middle shop: diner (booths and counter)
		blk(s * 75, 0, -80, s * 69.5, 3.6, -77, P.wood, "DinerCounter")
		for _, z in { -60, -54.5 } do
			blk(s * 74, 0, z - 1.5, s * 70, 3.2, z + 1.5, P.paintRed, "Booth")
		end
		blk(s * 61, 0, -62, s * 58, 6.5, -53, P.metal, "Fridge")
		-- inner shop (Hardpoint 1 / 3): pawn shop with glass cases along the walls
		for _, cx in { { 38.5, 42.5 }, { 49.5, 54 } } do
			blk(s * cx[1], 0, -80, s * cx[2], 3.8, -77.5, P.wood, "DisplayCase")
			blk(s * cx[1], 3.8, -79.5, s * cx[2], 6, -77.8, P.glass, "CaseGlass")
		end
		blk(s * 54.5, 0, -60, s * 52, 7, -53, P.woodDark, "Shelving")
		blk(s * 37, 0, -76, s * 40, 4.5, -72, P.metalDark, "Safe")
		-- centre block shop: records / launderette
		blk(s * 28.5, 0, -80, s * 22, 7, -77.5, P.metal, "Machines")
		blk(s * 20, 0, -66, s * 12, 3.4, -63, P.wood, "Racks")
		blk(s * 7, 0, -80, s * 5.5, 7.5, -74, P.woodDark, "Shelving")
	end
	-- flats over the centre block and the arcade (arcade ceiling Y 12, lit)
	flats(-30.5, 30.5)
	for _, z in { -76, -66, -56 } do
		local al2 = blk(-1, SH - 0.5, z - 1, 1, SH, z + 1, P.lamp, "ArcadeLight")
		light(al2, P.lamp.color, 14, 0.8)
	end
	blk(-4, 9, Z_FRONT - 0.4, 4, 12, Z_FRONT, P.ironGreen, "ArcadeArch")
	blk(-4, 9, Z_BACK, 4, 12, Z_BACK + 0.4, P.ironGreen, "ArcadeArch")
	blk(-2.5, 0, -68, 2.5, 0.05, -64, P.tileBlack, "ArcadeMosaic")

	-------------------------------------------------------------------------------------------
	-- Iron Street (middle lane) and the rail viaduct overhead (deck Z -34..-22, Y 18..21).
	-------------------------------------------------------------------------------------------
	section("Viaduct")
	local DECK = 18
	local piers = { -99, -77, -55, -33, -11, 11, 33, 55, 77, 99 }
	for _, x in piers do
		blk(x - 2.5, 0, -32, x + 2.5, DECK, -24, P.brick, "Pier")
		blk(x - 3, 0, -32.5, x + 3, 1.5, -23.5, P.concreteDark, "PierPlinth")
		blk(x - 3, DECK - 3, -32.5, x + 3, DECK - 2.2, -23.5, P.concrete, "PierCap")
	end
	-- spandrels between piers (arch look), deck, parapets
	for i = 1, #piers - 1 do
		local xa, xb = piers[i] + 2.5, piers[i + 1] - 2.5
		blk(xa, DECK - 3, -33, xa + 3, DECK, -23, P.brick, "Haunch")
		blk(xb - 3, DECK - 3, -33, xb, DECK, -23, P.brick, "Haunch")
		blk(xa + 3, DECK - 1.2, -33, xb - 3, DECK, -23, P.brick, "Spandrel")
	end
	blk(-128, DECK, -34, 128, DECK + 3, -22, P.brickDark, "Deck")
	blk(-128, DECK + 3, -34, 128, DECK + 5.5, -33, P.brickDark, "Parapet")
	blk(-128, DECK + 3, -23, 128, DECK + 5.5, -22, P.brickDark, "Parapet")
	blk(-128, DECK + 1.8, -34.3, 128, DECK + 2.6, -21.7, P.iron, "DeckGirder")
	for _, z in { -30.5, -25.5 } do
		blk(-128, DECK + 3, z - 0.3, 128, DECK + 3.5, z + 0.3, P.metal, "Rail")
	end
	-- a stopped commuter train on the viaduct (signature silhouette for the lobby camera)
	for i, x0 in { -62, -34, -6 } do
		blk(x0, DECK + 3.6, -31.5, x0 + 26, DECK + 12, -24.5, P.metal, "TrainCar")
		blk(x0 - 0.1, DECK + 7, -31.6, x0 + 26.1, DECK + 9.6, -24.4, P.glassDark, "TrainWindows")
		local band = blk(x0, DECK + 9.8, -31.6, x0 + 26, DECK + 10.4, -24.4, P.neonAmber, "TrainBand")
		if i == 2 then
			light(band, P.neonAmber.color, 30, 0.8)
		end
		blk(x0 + 1, DECK + 12, -30.5, x0 + 25, DECK + 12.6, -25.5, P.metalDark, "TrainRoof")
	end
	-- lamps hung under the deck between the piers
	for _, x in { -88, -44, 0, 44, 88 } do
		local ul = blk(x - 1, DECK - 1.6, -29, x + 1, DECK - 1.2, -27, P.lamp, "UnderLamp")
		light(ul, P.lamp.color, 24, 1.2)
	end

	section("IronStreet")
	-- parked cars and vans along both kerbs, staggered; roadworks in the middle of each half
	local carCols = { style(M.Metal, 120, 30, 34), style(M.Metal, 40, 60, 90), style(M.Metal, 170, 160, 140), style(M.Metal, 30, 30, 34) }
	for _, s in { -1, 1 } do
		car(s * 22, -40.5, carCols[1])
		car(s * 66, -40.5, carCols[2])
		van(s * 88, -15.5, carCols[3])
		car(s * 44, -15.5, carCols[4])
		car(s * 4 + s * 12, -15.5, carCols[2])
		-- roadworks barrier and cones beside the piers
		blk(s * 44 - 4, 0, -36, s * 44 + 4, 3.4, -35.2, P.paintRed, "RoadworkBarrier")
		blk(s * 44 - 4, 1.2, -36.1, s * 44 + 4, 2, -35.1, P.paintWhite, "BarrierStripe")
		for _, x in { 40, 48 } do
			blk(s * x - 0.6, 0, -21.6, s * x + 0.6, 2.4, -20.4, P.neonAmber, "Cone")
		end
		-- pavement furniture
		streetLamp(s * 16, -48.5, 1)
		streetLamp(s * 62, -48.5, 1)
		streetLamp(s * 88, -48.5, 1)
		streetLamp(s * 32, -7.5, -1)
		streetLamp(s * 76, -7.5, -1)
		blk(s * 52 - 0.8, 0, -47, s * 52 + 0.8, 4.4, -45.4, P.paintRed, "PostBox")
		cylY(s * 26, 0, -9, 2.4, 1, P.paintRed, "Hydrant")
		bench(s * 54, -9, 6, false)
	end
	-- bus shelter on the north pavement (east) and newspaper kiosk (west), mirrored partners
	for _, s in { -1, 1 } do
		blk(s * 72, 0, -48.8, s * 82, 8, -48.4, P.glass, "ShelterBack")
		blk(s * 71.6, 8, -49.2, s * 82.4, 8.5, -44.8, P.metalDark, "ShelterRoof")
		blk(s * 72, 0, -48.8, s * 72.4, 8, -45.2, P.metalDark, "ShelterEnd")
		blk(s * 81.6, 0, -48.8, s * 82, 8, -45.2, P.board, "ShelterAdvert")
		bench(s * 77, -47.6, 6, false)
		blk(s * 4 + s * 4, 0, -11, s * 4 + s * 9, 7, -7, P.ironGreen, "Kiosk")
		blk(s * 4 + s * 3.6, 7, -11.4, s * 4 + s * 9.4, 7.6, -6.6, P.paintCream, "KioskRoof")
		blk(s * 98.5, 0, -10.5, s * 101.5, 8, -7.5, P.paintRed, "PhoneBox")
		local pl = blk(s * 98.6, 7.4, -10.4, s * 101.4, 7.8, -7.6, P.windowLit, "PhoneBoxSign")
		light(pl, P.windowLit.color, 10, 0.6)
	end

	-------------------------------------------------------------------------------------------
	-- Park square (south lane centre): X -44..44, Z -6..62. Hedges, trees, bandstand.
	-------------------------------------------------------------------------------------------
	section("ParkSquare")
	-- railings on a low brick plinth with four gates (N, S, E, W)
	local function railing(alongZ: boolean, a0: number, a1: number, c: number, gaps: { Opening })
		wall(alongZ, a0, a1, c - 0.5, c + 0.5, 0, 1.2, gaps, P.brickDark, "Plinth")
		wall(alongZ, a0, a1, c - 0.15, c + 0.15, 1.2, 4.5, gaps, style(M.Metal, 30, 34, 30, 0.75), "Railings")
	end
	railing(false, -44, 44, -6, { { -8, 8, 0, 9 } })
	railing(false, -44, 44, 62, { { -8, 8, 0, 9 } })
	railing(true, -6, 62, -44, { { 20, 36, 0, 9 } })
	railing(true, -6, 62, 44, { { 20, 36, 0, 9 } })
	for _, x in { -44, -8, 8, 44 } do
		for _, z in { -6, 62 } do
			blk(x - 0.8, 0, z - 0.8, x + 0.8, 5.5, z + 0.8, P.brickDark, "GatePier")
		end
	end
	-- cross paths
	blk(-8, 0, -6, 8, 0.05, 62, P.paving, "ParkPath")
	blk(-44, 0, 20, 44, 0.05, 36, P.paving, "ParkPath")
	-- bandstand: platform (top Y 1, a 1-stud step), corner columns, roof and cupola
	blk(-10, 0, 18, 10, 1, 38, P.concrete, "BandstandBase")
	blk(-10.3, 0.6, 17.7, 10.3, 1, 38.3, P.paintCream, "BandstandEdge")
	for _, c in { { -9, 19 }, { 9, 19 }, { -9, 37 }, { 9, 37 }, { -9, 28 }, { 9, 28 } } do
		cylY(c[1], 1, c[2], 11, 0.8, P.ironGreen, "BandstandColumn")
	end
	blk(-11, 11, 17, 11, 11.8, 39, P.ironGreen, "BandstandRoof")
	blk(-7, 11.8, 21, 7, 13.4, 35, P.ironGreen, "BandstandRoof")
	blk(-3, 13.4, 25, 3, 15.6, 31, P.paintCream, "Cupola")
	local bl = blk(-1, 10.4, 27, 1, 11, 29, P.lamp, "BandstandLight")
	light(bl, P.lamp.color, 22, 1.2)
	blk(-6, 1, 33.5, -2, 2.6, 35.5, P.woodDark, "MusicStand")
	blk(3, 1, 20, 6, 3.4, 22, P.woodDark, "PianoCrate")
	-- hedge blocks in each quadrant (crouch-to-head-height cover), trees, benches
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local zc = 28 + sz * 20
			blk(sx * 16, 0, zc - 2, sx * 34, 4, zc + 2, P.hedge, "Hedge")
			blk(sx * 34, 0, zc - 2, sx * 38, 4, zc + sz * 10, P.hedge, "Hedge")
			tree(sx * 26, 28 + sz * 30, 9)
			bench(sx * 22, 28 + sz * 11, 8, false)
		end
		tree(sx * 38, 28, 10)
		blk(sx * 16 - 2, 0, 0, sx * 16 + 2, 2.6, 4, P.concrete, "Planter")
		blk(sx * 16 - 1.8, 2.6, 0.2, sx * 16 + 1.8, 2.9, 3.8, P.grass, "PlanterSoil")
		streetLamp(sx * 12, 14, 1)
		streetLamp(sx * 12, 44, -1)
	end
	-- drinking fountain and noticeboard on the cross path
	cylY(-26, 0, 28, 3.2, 2, P.concrete, "DrinkingFountain")
	blk(25, 0, 27.5, 28, 6, 28.5, P.woodDark, "Noticeboard")

	-------------------------------------------------------------------------------------------
	-- Print works (west) and tram substation (east): brick sheds X 52..96, Z 2..56.
	-------------------------------------------------------------------------------------------
	local function shed(s: number, name: string)
		section(name)
		local i0, o0 = s * 52, s * 96
		local H = 14
		-- inner wall (park side): two doors; outer wall (service lane): one door
		wall(true, 2, 56, i0, i0 + s * 1, 0, H, { { 20, 28, 0, 9.5 }, { 40, 47, 0, 9.5 }, { 6, 14, 4, 8 } }, P.brick, "ShedWall")
		wall(true, 2, 56, o0 - s * 1, o0, 0, H, { { 25, 33, 0, 9.5 }, { 8, 16, 4, 8 }, { 42, 50, 4, 8 } }, P.brick, "ShedWall")
		wall(false, i0, o0, 2, 3, 0, H, { { s * 70, s * 78, 0, 9.5 }, { s * 56, s * 64, 4, 8 }, { s * 84, s * 92, 4, 8 } }, P.brick, "ShedWall")
		wall(false, i0, o0, 55, 56, 0, H, { { s * 62, s * 70, 0, 9.5 }, { s * 80, s * 90, 4, 8 } }, P.brick, "ShedWall")
		blk(i0 - s * 0.6, H, 1.4, o0 + s * 0.6, H + 1, 56.6, P.slateDark, "ShedRoof")
		blk(i0 - s * 0.6, H - 1.6, 1.4, o0 + s * 0.6, H - 0.8, 1.7, P.concrete, "ShedBand")
		blk(i0 - s * 0.6, H - 1.6, 55.3, o0 + s * 0.6, H - 0.8, 55.6, P.concrete, "ShedBand")
		-- roof lights (skylight look) and a chimney stack
		for _, z in { 14, 42 } do
			blk(s * 64, H + 1, z - 4, s * 84, H + 1.6, z + 4, P.glassDark, "Rooflight")
		end
		blk(s * 90, H + 1, 46, s * 94, H + 12, 50, P.brickSoot, "Stack")
		for _, z in { 12, 30, 46 } do
			local sl = blk(s * 73, H - 0.6, z - 1, s * 75, H, z + 1, P.lamp, "ShedLight")
			light(sl, P.lamp.color, 20, 0.9)
		end
		-- doorway lamp over the inner doors
		local dl = blk(i0 - s * 0.4, 10, 23, i0 - s * 0.9, 10.6, 25, P.lamp, "DoorLamp")
		light(dl, P.lamp.color, 14, 0.8)
	end

	shed(-1, "PrintWorks")
	-- print works interior: presses, paper rolls, type cases
	for _, z in { 12, 46 } do
		blk(-88, 0, z - 3, -62, 4.5, z + 3, P.metalDark, "PrintPress")
		blk(-84, 4.5, z - 2, -66, 6.5, z + 2, P.iron, "PressRollers")
	end
	cylH(-91, 2, 38, 4, 4, true, P.paintCream, "PaperRoll")
	cylH(-91, 2, 18, 4, 4, true, P.paintCream, "PaperRoll")
	cylH(-60, 2, 30, 4, 4, true, P.paintCream, "PaperRoll")
	blk(-80, 0, 26, -78, 7, 34, P.woodDark, "TypeCases")
	crate(-68, 0, 33, 3, 0.2)

	shed(1, "TramSubstation")
	-- substation interior: transformers, switchgear, cable drum (cover around Bomb B)
	for _, z in { 12, 46 } do
		blk(62, 0, z - 4, 86, 6, z + 4, P.ironGreen, "Transformer")
		blk(64, 6, z - 3, 84, 7.2, z + 3, P.metalDark, "TransformerFins")
	end
	blk(88, 0, 17, 94, 7.5, 21, P.metal, "Switchgear")
	blk(87.9, 2, 17.5, 88, 6.5, 20.5, P.neonTeal, "SwitchgearLights")
	cylH(66, 2.5, 30, 3, 5, false, P.wood, "CableDrum")
	blk(80, 0, 33, 83, 3.2, 37, P.metalDark, "Cabinet")
	blk(64, 0, 35, 68, 3.2, 38, P.metalDark, "Cabinet")

	-------------------------------------------------------------------------------------------
	-- Side streets (|X| 44..52), service lanes (|X| 96..106) and Canal Row (Z 56..76).
	-------------------------------------------------------------------------------------------
	section("SideStreets")
	for _, s in { -1, 1 } do
		-- service lanes: clutter breaks the long north-south line
		blk(s * 98, 0, -44, s * 102, 3.6, -40, P.wood, "PalletStack")
		dumpster(s * 101, 12, true, P.ironGreen)
		blk(s * 97.5, 0, 44, s * 100.5, 7, 50, P.metal, "Electrical")
		crate(s * 102, 0, 60, 3)
		crate(s * 102, 3, 60.2, 2.2, 0.3)
		-- side streets beside the park: bollards and a parked van
		for _, z in { -4, 10 } do
			cylY(s * 48, 0, z, 3, 1, P.metalDark, "Bollard")
		end
		dumpster(s * 50.1, 51, true, P.paintTeal)
		blk(s * 44.5, 0, 10, s * 48.5, 3.4, 11, P.paintRed, "RoadworkBarrier")
		-- Canal Row: cover every 15-25 studs along the strip
		blk(s * 20 - 3, 0, 66, s * 20 + 3, 2.8, 70, P.concrete, "Planter")
		blk(s * 20 - 2.8, 2.8, 66.2, s * 20 + 2.8, 3.1, 69.8, P.grass, "PlanterSoil")
		car(s * 38, 72.5, carCols[3])
		blk(s * 58 - 1.5, 0, 62, s * 58 + 1.5, 8, 65, P.paintRed, "PhoneBox")
		van(s * 76, 70, carCols[4])
		blk(s * 92 - 3, 0, 62, s * 92 + 3, 4, 66, P.ironGreen, "GritBin")
		streetLamp(s * 30, 63, 1)
		streetLamp(s * 86, 59, 1)
	end
	-- stairwell parapets down to the underpass (X +-6..7)
	for _, s in { -1, 1 } do
		blk(s * 6, -10, 62, s * 7, 3, 76, P.concreteDark, "StairwellWall")
	end
	stairs(-6, 62, 6, 76, "-Z", -10, 0, P.concrete)
	blk(-7, 8, 70, 7, 9, 76, P.metalDark, "StairCanopy")
	blk(-6.5, 3, 75, -5.5, 8, 76, P.metalDark, "CanopyPost")
	blk(5.5, 3, 75, 6.5, 8, 76, P.metalDark, "CanopyPost")
	local sg = blk(-3, 7, 75.6, 3, 8, 76, P.neonRed, "SubwaySign")
	light(sg, P.neonRed.color, 14, 0.8)

	-------------------------------------------------------------------------------------------
	-- Goods-line embankment and the underpass beneath it (south flank).
	-- Underpass interior Z 78..94, floor Y -10, ceiling Y -1; stairs up at both ends.
	-------------------------------------------------------------------------------------------
	section("Underpass")
	local UY = -10
	wall(false, -92, 92, 76, 78, UY, -1, { { -6, 6, UY, -1 } }, P.tile, "UnderpassWallN")
	blk(-92, UY, 94, 92, -1, 98, P.tile, "UnderpassWallS")
	blk(-92, -1, 76, 92, 0, 98, P.concreteDark, "UnderpassRoof")
	-- embankment above (unreachable: 12 tall retaining wall on the Canal Row side)
	blk(-92, 0, 77, 92, 12, 98, P.brickSoot, "Embankment")
	blk(-92, 0, 76, -7, 12, 77, P.brickDark, "RetainingWall")
	blk(7, 0, 76, 92, 12, 77, P.brickDark, "RetainingWall")
	blk(-7, 9, 76, 7, 12, 77, P.brickDark, "RetainingWall")
	blk(-92.5, 12, 75.5, 92.5, 12.8, 98, P.concrete, "Coping")
	blk(-92, 12.8, 80, 92, 13.4, 96, P.grass, "EmbankmentTop")
	-- tiled bands, columns, lights, baffles
	blk(-92, UY + 3, 78, 92, UY + 3.6, 78.2, P.paintTeal, "TileBand")
	blk(-92, UY + 3, 93.8, 92, UY + 3.6, 94, P.paintTeal, "TileBand")
	for _, x in { -84, -60, -36, -12, 12, 36, 60, 84 } do
		blk(x - 1.2, UY, 84.8, x + 1.2, -1, 87.2, P.concrete, "UnderpassColumn")
	end
	for x = -80, 80, 20 do
		local ul2 = blk(x - 2, -1.6, 85.6, x + 2, -1, 86.4, P.lamp, "UnderpassLight")
		if x % 40 == 0 then
			light(ul2, P.lamp.color, 20, 1)
		end
	end
	for _, s in { -1, 1 } do
		-- zig-zag baffles near each end
		blk(s * 70 - 1, UY, 78, s * 70 + 1, -1, 85, P.tile, "UnderpassBaffle")
		blk(s * 78 - 1, UY, 87, s * 78 + 1, -1, 94, P.tile, "UnderpassBaffle")
		-- cuttings: open-air stairs up to the base wall gap, retaining walls either side
		stairs(s * 92, 78, s * 106, 94, if s < 0 then "-X" else "+X", UY, 0, P.concrete)
		blk(s * 92, UY, 76, s * 106, 3, 78, P.concreteDark, "CuttingWall")
		blk(s * 92, UY, 94, s * 106, 3, 98, P.concreteDark, "CuttingWall")
		blk(s * 92, 0, 77, s * 92 + s * 0.6, 12, 98, P.brickDark, "PortalFace")
		-- underpass clutter (crouch cover)
		crate(s * 24, UY, 80.5, 3, 0.15)
		blk(s * 48 - 2, UY, 90, s * 48 + 2, UY + 3.2, 94, P.metalDark, "FuseBox")
		cylY(s * 30, UY, 92, UY + 3, 2, P.metalDark, "Bin")
		blk(s * 50, UY, 78, s * 54, UY + 2.6, 80, P.wood, "Pallet")
	end

	-------------------------------------------------------------------------------------------
	-- Team bases: Sable west yard, Talon east yard (|X| 108..128). Mirror symmetric layout.
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
		-- yard wall (16 tall, under the viaduct deck) with four gaps
		local open: { Opening } = {}
		for _, g in GAPS do
			table.insert(open, { g[1], g[2], 0, 30 })
		end
		wall(true, -98, 98, s * WALL_X, s * (WALL_X + 2), 0, 16, open, P.brick, "YardWall")
		wall(true, -98, 98, s * (WALL_X - 0.2), s * (WALL_X + 2.2), 16, 16.8, open, P.concrete, "YardWallCoping")
		for _, g in GAPS do
			blk(s * (WALL_X - 0.1), 0, g[1] - 0.6, s * (WALL_X + 2.1), 16, g[1], accent, "GapMarker")
			blk(s * (WALL_X - 0.1), 0, g[2], s * (WALL_X + 2.1), 16, g[2] + 0.6, accent, "GapMarker")
			-- loading-bay screen behind each gap (spawn side) catches lines through the gap
			local z0 = math.max(g[1] - 6, -98)
			local z1 = math.min(g[2] + 6, 98)
			blk(s * 113, 0, z0, s * 116, 12, z1, P.brickDark, "Screen")
			blk(s * 112.8, 12, z0 - 0.2, s * 116.2, 12.6, z1 + 0.2, P.concrete, "ScreenCoping")
			blk(s * 112.9, 6, z0, s * 112.8, 7, z1, accent, "ScreenStripe")
			local gl = blk(s * 112.7, 9, (z0 + z1) / 2 - 1, s * 112.9, 10, (z0 + z1) / 2 + 1, P.lamp, "ScreenLamp")
			light(gl, P.lamp.color, 18, 1)
		end
		-- yard dressing at the back wall (clear of the spawn columns at |X| 120 / 125.5)
		for _, z in { -70, -50, -10, 10, 50, 70 } do
			blk(s * 122.3, 0, z - 4, s * 122.7, 0.05, z + 4, accent, "BayMarking")
		end
		crate(s * 125.5, 0, -16, 3)
		blk(s * 124, 0, 60, s * 127.8, 4, 64, P.metal, "ToolChest")

		-- team spawns: two columns, facing into the map. Nothing sits in front of the screens that
		-- cover the gaps (|Z| 78..98), or the first view after spawning is a wall 4 studs away.
		for _, z in { -72, -52, -18, 16, 52, 70 } do
			spawnPart(s * 120, 0, z, 0, z * 0.5, team, false)
		end
		for _, z in { -68, -36, 0, 36, 68 } do
			spawnPart(s * 125.5, 0, z, 0, z * 0.5, team, false)
		end
	end

	-------------------------------------------------------------------------------------------
	-- FFA spawns spread around the whole map. { x, floorY, z, lookX, lookZ }
	-------------------------------------------------------------------------------------------
	local ffa = {
		{ -122, 0, -60, 0, -60 },
		{ 122, 0, 44, 0, 44 },
		{ -60, 0, -90, 0, -90 },
		{ 24, 0, -90, 0, -90 },
		{ -86, 0, -66, -86, -50 },
		{ 16, 0, -70, 16, -50 },
		{ 86, 0, -64, 86, -50 },
		{ -44, 0, -24, 0, -24 },
		{ 24, 0, -21, 0, -28 },
		{ -101, 0, -16, 0, -16 },
		{ -26, 0, 14, 0, 28 },
		{ 28, 0, 52, 0, 28 },
		{ -74, 0, 30, -52, 30 },
		{ 74, 0, 20, 52, 20 },
		{ -40, 0, 68, 0, 68 },
		{ 64, 0, 66, 0, 66 },
		{ -40, UY, 86, 0, 86 },
		{ 40, UY, 82, 0, 82 },
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
		for k, v in attrs do
			p:SetAttribute(k, v)
		end
		p.Parent = objectives
	end

	-- Domination: A west street (between piers), B bandstand, C east street.
	zone("FlagA", "Flag", -66, 0, -28, 16, 16, { Label = "A" })
	zone("FlagB", "Flag", 0, 1, 28, 18, 18, { Label = "B" })
	zone("FlagC", "Flag", 66, 0, -28, 16, 16, { Label = "C" })

	-- Hardpoint rotation: west shop -> bandstand -> east shop -> underpass -> under the viaduct.
	zone("Hardpoint1_WestPawnShop", "Hardpoint", -46, 0, -66, 18, 24, { Order = 1 })
	zone("Hardpoint2_Bandstand", "Hardpoint", 0, 1, 28, 20, 20, { Order = 2 })
	zone("Hardpoint3_EastPawnShop", "Hardpoint", 46, 0, -66, 18, 24, { Order = 3 })
	zone("Hardpoint4_Underpass", "Hardpoint", 0, UY, 86, 22, 16, { Order = 4 })
	zone("Hardpoint5_ViaductArches", "Hardpoint", 0, 0, -28, 20, 16, { Order = 5 })

	-- Search and Destroy: Sable (west) attacks first, so both sites sit on the Talon (east) side.
	-- A: east diner (counter, booths, fridge). B: tram substation between the transformers.
	zone("BombSiteA", "BombSite", 66, 0, -67, 14, 14, { Label = "A" })
	zone("BombSiteB", "BombSite", 74, 0, 29, 14, 14, { Label = "B" })

	-------------------------------------------------------------------------------------------
	-- Lobby camera (frames the viaduct and its stopped train over Iron Street) + attributes.
	-------------------------------------------------------------------------------------------
	local cam = Instance.new("Part")
	cam.Name = "LobbyCamera"
	cam.Size = Vector3.new(1, 1, 1)
	cam.CFrame = CFrame.lookAt(Vector3.new(-96, 42, 40), Vector3.new(-10, 18, -30))
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
