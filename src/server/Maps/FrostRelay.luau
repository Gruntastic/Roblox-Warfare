--!strict
--[[
	Frost Relay: a snowbound mountain radio-relay station at dusk.
	Medium 6v6 map, ~356 x 256 studs playable (boundary inner faces at X = +-178, Z = +-128).

	Axes: +X = east, -Z = north (top of the ASCII sketch in docs/maps/FrostRelay.md).
	All walkable ground has its top surface at Y = 0, except:
	  the frozen reservoir (ice floor, Y -3), the pipeline trench (Y -3),
	  the operations block upper floor (Y 13) and the mast pad (Y 0.6).
	The bottom of every ground slab is Y -6 (BoundsMin.Y). KillY is -40.

	Bands, north -> south:
	  Z -128..-112  Dam gallery (north flank: roofed concrete walkway, windows over the ice)
	  Z -112.. -58  Frozen reservoir (north lane: ice floor, pump house, ice-locked barges, huts)
	  Z  -57..  26  Relay compound (middle lane: operations block, lattice mast, radio cabins)
	  Z   26..  34  Snow berm line
	  Z   34.. 104  Motor pool (south lane: vehicle shed in the centre, fuel depots east and west)
	  Z  108.. 124  Pipeline trench (south flank, Y -3, timber snow sheds)
	Sable spawn = west camp (X < -126), Talon spawn = east camp (X > 126).
	The layout is mirror-symmetric across X = 0; only accent colours and base dressing differ.

	Objectives (see docs/maps/FrostRelay.md, "Objectives"):
	  Flags     A west compound yard, B mast pad, C east compound yard
	  Hardpoint 1 operations block, 2 vehicle shed, 3 pump house (ice), 4 west depot, 5 east depot
	  S&D       Sable attacks in round 1; sites A (east radio cabin) and B (east fuel depot)

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

-- Cold blue-white dusk palette.
local P = {
	snow = style(M.Snow, 236, 242, 250),
	snowShade = style(M.Snow, 206, 218, 234),
	ice = style(M.Ice, 164, 204, 232),
	iceDark = style(M.Ice, 118, 160, 196),
	glacier = style(M.Glacier, 184, 218, 240),
	concrete = style(M.Concrete, 172, 178, 188),
	concreteDark = style(M.Concrete, 118, 126, 140),
	slate = style(M.Slate, 84, 92, 108),
	slateDark = style(M.Slate, 58, 64, 78),
	rock = style(M.Rock, 98, 106, 120),
	metal = style(M.Metal, 142, 150, 162),
	metalBlue = style(M.Metal, 96, 116, 140),
	metalDark = style(M.DiamondPlate, 82, 88, 100),
	tankWhite = style(M.Metal, 214, 220, 228),
	paintRed = style(M.SmoothPlastic, 184, 58, 50),
	paintWhite = style(M.SmoothPlastic, 232, 236, 240),
	paintYellow = style(M.SmoothPlastic, 222, 182, 64),
	paintOrange = style(M.SmoothPlastic, 214, 110, 44),
	wood = style(M.WoodPlanks, 118, 104, 92),
	woodDark = style(M.Wood, 82, 72, 66),
	rubber = style(M.Rubber, 38, 40, 46),
	board = style(M.SmoothPlastic, 34, 40, 50),
	glass = style(M.Glass, 170, 204, 228, 0.5),
	mesh = style(M.Metal, 150, 160, 172, 0.7),
	lampWarm = style(M.Neon, 255, 200, 140),
	lampCold = style(M.Neon, 196, 224, 255),
	beacon = style(M.Neon, 255, 64, 52),
	screen = style(M.Neon, 110, 200, 220),
	sable = style(M.SmoothPlastic, 52, 96, 130),
	talon = style(M.SmoothPlastic, 196, 120, 46),
}

local MapModule = {}

MapModule.id = "FrostRelay"
MapModule.displayName = "Frost Relay"

-- Clear, cold dusk: low warm sun, blue shadows, light snow haze. Fog starts well past 250 studs.
MapModule.lighting = {
	ClockTime = 17.7,
	GeographicLatitude = 58,
	Brightness = 2.4,
	ExposureCompensation = 0.25,
	Ambient = Color3.fromRGB(106, 116, 140),
	OutdoorAmbient = Color3.fromRGB(142, 154, 182),
	ColorShift_Top = Color3.fromRGB(255, 196, 168),
	ColorShift_Bottom = Color3.fromRGB(92, 112, 152),
	EnvironmentDiffuseScale = 0.5,
	EnvironmentSpecularScale = 0.35,
	ShadowSoftness = 0.4,
	GlobalShadows = true,
	FogColor = Color3.fromRGB(196, 208, 230),
	FogStart = 320,
	FogEnd = 1500,
}

MapModule.atmosphere = {
	Density = 0.3,
	Offset = 0.1,
	Color = Color3.fromRGB(204, 216, 238),
	Decay = Color3.fromRGB(122, 132, 172),
	Glare = 0.3,
	Haze = 1.6,
}

MapModule.killY = -40

local BOUNDS_MIN = Vector3.new(-182, -6, -132)
local BOUNDS_MAX = Vector3.new(182, 96, 132)

-- Base wall gaps (Z ranges) on each team's wall at |X| 126..128, shared by geometry and docs.
local WALL_X = 126
local GAPS = { { -128, -114 }, { -96, -84 }, { -22, -10 }, { 54, 66 }, { 110, 122 } }

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

	local function wedge(cf: CFrame, size: Vector3, st: Style, name: string?): WedgePart
		local p = Instance.new("WedgePart")
		p.Size = size
		p.CFrame = cf
		finish(p, st, name)
		return p
	end

	-- Vertical cylinder (post, drum, stack).
	local function cylY(x: number, y0: number, z: number, y1: number, d: number, st: Style, name: string?): Part
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(y1 - y0, d, d)
		p.CFrame = CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.pi / 2)
		finish(p, st, name)
		return p
	end

	-- Horizontal cylinder along X (pipes, tanks) or Z (wheels, cable drums).
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

	-- Equipment case (blue-grey) of size s, optional yaw.
	local function case(x: number, y: number, z: number, s: number, yaw: number?)
		prop("EquipmentCase", function()
			box(CFrame.new(x, y + s / 2, z) * CFrame.Angles(0, yaw or 0, 0), Vector3.new(s * 1.3, s, s), P.metalBlue, "Case")
		end)
	end

	local function drums(x: number, y: number, z: number, n: number)
		local offs = { { 0, 0 }, { 2.4, 0.6 }, { 0.9, 2.3 }, { -1.6, 1.8 } }
		for i = 1, math.min(n, #offs) do
			local o = offs[i]
			cylY(x + o[1], y, z + o[2], y + 3.2, 2.2, if i % 2 == 0 then P.paintOrange else P.metalBlue, "Drum")
		end
	end

	-- Snow berm: two wedges back to back, long axis along X (alongZ = false) or Z.
	local function berm(x: number, z: number, len: number, h: number, depth: number, alongZ: boolean)
		local yaw = if alongZ then math.pi / 2 else 0
		local base = CFrame.new(x, h / 2, z) * CFrame.Angles(0, yaw, 0)
		wedge(base * CFrame.new(0, 0, -depth / 4), Vector3.new(len, h, depth / 2), P.snow, "Berm")
		wedge(base * CFrame.new(0, 0, depth / 4) * CFrame.Angles(0, math.pi, 0), Vector3.new(len, h, depth / 2), P.snow, "Berm")
	end

	-- Ice pressure ridge / boulder: a tilted glacier slab on floor y.
	local function ridge(x: number, y: number, z: number, sx: number, sy: number, sz: number, yaw: number, st: Style?)
		box(CFrame.new(x, y + sy / 2, z) * CFrame.Angles(0, yaw, 0), Vector3.new(sx, sy, sz), st or P.glacier, "Ridge")
		box(CFrame.new(x, y + sy + 0.3, z) * CFrame.Angles(0, yaw, 0), Vector3.new(sx - 1, 0.6, sz - 1), P.snow, "RidgeSnow")
	end

	local function lampPost(x: number, z: number, h: number, st: Style)
		prop("LampPost", function()
			cylY(x, 0, z, h, 0.8, P.metalDark, "LampPost")
			blk(x - 0.6, h - 0.6, z - 0.6, x + 0.6, h + 0.4, z + 0.6, P.metal, "LampHead")
			local bulb = blk(x - 0.45, h - 1.0, z - 0.45, x + 0.45, h - 0.6, z + 0.45, st, "LampBulb")
			light(bulb, st.color, 26, 1.2)
		end)
	end

	-- Snowcat: tracked over-snow vehicle, long axis along X. Crouch-to-standing cover.
	local function snowcat(x: number, z: number, flip: boolean, st: Style)
		prop("Snowcat", function()
			local f = if flip then -1 else 1
			blk(x - 6, 0, z - 3.2, x + 6, 2.4, z - 1.6, P.rubber, "Track")
			blk(x - 6, 0, z + 1.6, x + 6, 2.4, z + 3.2, P.rubber, "Track")
			blk(x - 5.5, 1.2, z - 1.6, x + 5.5, 2.4, z + 1.6, P.metalDark, "Chassis")
			blk(x - 5.8, 2.4, z - 3, x + 5.8, 4.4, z + 3, st, "Body")
			blk(x + f * 0.5 - 3, 4.4, z - 2.8, x + f * 0.5 + 3, 7.6, z + 2.8, st, "Cab")
			blk(x + f * 3.5 - 0.1, 5, z - 2.4, x + f * 3.5 + 0.1, 7.2, z + 2.4, P.glass, "Windscreen")
			blk(x - f * 5.8 - 0.4, 0.6, z - 3.4, x - f * 5.8 + 0.4, 3.6, z + 3.4, P.metal, "Blade")
		end)
	end

	-- Small timber hut with a pitched-look roof cap and stovepipe (solid, not enterable).
	local function hut(x0: number, z0: number, x1: number, z1: number, h: number, st: Style, accent: Style?)
		blk(x0, 0, z0, x1, h, z1, st, "Hut")
		blk(x0 - 0.6, h, z0 - 0.6, x1 + 0.6, h + 0.8, z1 + 0.6, P.slateDark, "HutRoof")
		blk(x0 - 0.4, h + 0.8, z0 - 0.4, x1 + 0.4, h + 1.4, z1 + 0.4, P.snow, "HutSnow")
		if accent then
			blk(x0 - 0.1, h - 2, z0 - 0.1, x1 + 0.1, h - 1.2, z1 + 0.1, accent, "HutStripe")
		end
		cylY(x1 - 1.5, h + 0.8, z0 + 1.5, h + 4, 0.6, P.metalDark, "Stovepipe")
	end

	-------------------------------------------------------------------------------------------
	-- Ground. Every slab reaches down to Y -6 and they abut exactly, so there are no holes.
	-------------------------------------------------------------------------------------------
	section("Ground")
	-- dam gallery band
	blk(-182, -6, -132, -124, 0, -112, P.snowShade, "Ground")
	blk(-124, -6, -132, 124, 0, -112, P.concrete, "GalleryFloor")
	blk(124, -6, -132, 182, 0, -112, P.snowShade, "Ground")
	-- reservoir band: ice floor sits 3 lower than the shore
	blk(-182, -6, -112, -124, 0, -58, P.snow, "Shore")
	blk(-124, -6, -112, 124, -3, -58, P.ice, "ReservoirIce")
	blk(124, -6, -112, 182, 0, -58, P.snow, "Shore")
	-- compound band
	blk(-182, -6, -58, -100, 0, 28, P.snow, "Ground")
	blk(-100, -6, -58, 100, 0, 28, P.concrete, "CompoundYard")
	blk(100, -6, -58, 182, 0, 28, P.snow, "Ground")
	-- motor pool band
	blk(-182, -6, 28, 182, 0, 108, P.snow, "Ground")
	-- trench band
	blk(-182, -6, 108, -112, 0, 124, P.snow, "Ground")
	blk(-112, -6, 108, 112, -3, 124, P.concreteDark, "TrenchFloor")
	blk(112, -6, 108, 182, 0, 124, P.snow, "Ground")
	blk(-182, -6, 124, 182, 0, 132, P.snowShade, "Ground")
	-- packed-snow tyre tracks through the motor pool (0.05 thick, walkable)
	for _, z in { 40, 100 } do
		blk(-120, 0, z - 1.5, 120, 0.05, z + 1.5, P.snowShade, "TyreTrack")
	end
	-- painted lines in the compound yard
	for _, x in { -84, -40, 40, 84 } do
		blk(x - 0.25, 0, -20, x + 0.25, 0.05, 0, P.paintYellow, "YardLine")
	end

	-------------------------------------------------------------------------------------------
	-- Boundary: rock cliffs with a snow cap. Inner faces at X = +-178, Z = +-128.
	-------------------------------------------------------------------------------------------
	section("Boundary")
	blk(-182, -6, -132, 182, 26, -128, P.rock, "CliffN")
	blk(-182, 26, -132, 182, 28, -128, P.snow, "CliffSnow")
	blk(-182, -6, 128, 182, 26, 132, P.rock, "CliffS")
	blk(-182, 26, 128, 182, 28, 132, P.snow, "CliffSnow")
	blk(-182, -6, -128, -178, 26, 128, P.rock, "CliffW")
	blk(-182, 26, -128, -178, 28, 128, P.snow, "CliffSnow")
	blk(178, -6, -128, 182, 26, 128, P.rock, "CliffE")
	blk(178, 26, -128, 182, 28, 128, P.snow, "CliffSnow")
	-- buttresses break up the cliff faces (kept short of anything climbable)
	for x = -150, 150, 50 do
		if math.abs(x) > 130 then
			blk(x - 4, 0, 125.5, x + 4, 22, 128, P.slate, "Buttress")
		end
		blk(x - 3, 0, 126, x + 3, 18, 128, P.slateDark, "Buttress")
	end
	for z = -100, 100, 50 do
		blk(-178, 0, z - 4, -175.5, 20, z + 4, P.slate, "Buttress")
		blk(175.5, 0, z - 4, 178, 20, z + 4, P.slate, "Buttress")
	end

	-------------------------------------------------------------------------------------------
	-- Dam gallery (north flank): Z -128..-114 interior, roof Y 11, windows over the ice.
	-------------------------------------------------------------------------------------------
	section("DamGallery")
	local galleryOpen: { Opening } = {
		{ -94, -86, 0, 9.5 },
		{ -4, 4, 0, 9.5 },
		{ 86, 94, 0, 9.5 },
	}
	for _, x in { -110, -66, -44, -22, 22, 44, 66, 110 } do
		table.insert(galleryOpen, { x - 4, x + 4, 4, 8 })
	end
	wall(false, -124, 124, -114, -112, 0, 11, galleryOpen, P.concrete, "GalleryWall")
	blk(-125, 11, -128, 125, 12, -111, P.concreteDark, "GalleryRoof")
	blk(-125, 12, -128, 125, 12.6, -111.5, P.snow, "GalleryRoofSnow")
	blk(-124.5, 9, -112, 124.5, 11, -111.6, P.paintYellow, "GalleryFascia")
	-- pipes along the dam face, ceiling lights
	cylH(0, 9.2, -127, 248, 1.6, false, P.metalBlue, "DamPipe")
	cylH(0, 7.4, -127.2, 248, 1, false, P.metal, "DamPipe")
	for x = -110, 110, 22 do
		local l = blk(x - 2, 10.6, -121.5, x + 2, 11, -120.5, P.lampCold, "GalleryLight")
		if x % 44 == 0 then
			light(l, P.lampCold.color, 22, 0.9)
		end
	end
	for _, s in { -1, 1 } do
		-- zig-zag baffles near each end stop end-to-end shots
		blk(s * 103, 0, -128, s * 105, 11, -121, P.concreteDark, "GalleryBaffle")
		blk(s * 113, 0, -121, s * 115, 11, -114, P.concreteDark, "GalleryBaffle")
		-- pump motors against the dam face, cases near the windows
		blk(s * 18, 0, -128, s * 24, 5, -123, P.metalBlue, "PumpMotor")
		cylH(s * 21, 5.6, -125.5, 4, 1.4, false, P.metalDark, "MotorShaft")
		blk(s * 58, 0, -128, s * 64, 5, -123, P.metalBlue, "PumpMotor")
		cylH(s * 61, 5.6, -125.5, 4, 1.4, false, P.metalDark, "MotorShaft")
		case(s * 40, 0, -117, 3, 0.1)
		case(s * 43.5, 0, -117.5, 2.4, -0.2)
		blk(s * 78, 0, -128, s * 82, 8, -125.5, P.metalDark, "Switchgear")
		blk(s * 78.4, 3, -125.6, s * 81.6, 6, -125.4, P.screen, "SwitchgearPanel")
		cylY(s * 96, 0, -117, 3, 2, P.metalDark, "Bin")
		-- shore boulders beside the gallery doors
		ridge(s * 72, 0, -109, 7, 4, 4, 0.2 * s, P.rock)
		ridge(s * 32, 0, -109.5, 6, 3, 3.5, -0.3 * s, P.rock)
	end

	-------------------------------------------------------------------------------------------
	-- Frozen reservoir (north lane): ice floor Y -3, shore steps on every side.
	-------------------------------------------------------------------------------------------
	section("Reservoir")
	stairs(-124, -112, 124, -106, "-Z", -3, 0, P.snowShade)
	stairs(-124, -64, 124, -58, "+Z", -3, 0, P.snowShade)
	stairs(-124, -106, -118, -64, "-X", -3, 0, P.snowShade)
	stairs(118, -106, 124, -64, "+X", -3, 0, P.snowShade)
	-- darker ice cracks and a survey line (0.05 thick)
	for i, c in { { -90, -96, 0.4 }, { -36, -72, -0.3 }, { 24, -100, 0.7 }, { 70, -74, -0.5 }, { 104, -92, 0.2 } } do
		box(CFrame.new(c[1], -2.975, c[2]) * CFrame.Angles(0, c[3], 0), Vector3.new(18 + i * 2, 0.05, 1.2), P.iceDark, "Crack")
	end
	for x = -110, 110, 20 do
		cylY(x, -3, -66.5, 1, 0.3, P.paintOrange, "SurveyStake")
	end

	-- pump house: intake hut in the middle of the ice (Hardpoint 3)
	local PY = -3
	wall(true, -95, -75, -11, -10, PY, PY + 11, { { -89, -81, PY, PY + 9.5 } }, P.concrete, "PumpHouseWall")
	wall(true, -95, -75, 10, 11, PY, PY + 11, { { -89, -81, PY, PY + 9.5 } }, P.concrete, "PumpHouseWall")
	wall(false, -10, 10, -95, -94, PY, PY + 11, { { -6, 6, PY + 4, PY + 7.5 } }, P.concrete, "PumpHouseWall")
	wall(false, -10, 10, -76, -75, PY, PY + 11, { { -6, 6, PY + 4, PY + 7.5 } }, P.concrete, "PumpHouseWall")
	blk(-12, PY + 11, -96, 12, PY + 12, -74, P.slate, "PumpHouseRoof")
	blk(-11.5, PY + 12, -95.5, 11.5, PY + 12.6, -74.5, P.snow, "PumpHouseSnow")
	blk(-11.2, PY + 8.4, -95.2, 11.2, PY + 9.4, -74.8, P.paintRed, "PumpHouseBand")
	-- intake machinery in the corners keeps the centre clear
	blk(-9.5, PY, -93.5, -5.5, PY + 4, -89.5, P.metalBlue, "IntakeValve")
	blk(5.5, PY, -80.5, 9.5, PY + 4, -76.5, P.metalBlue, "IntakeValve")
	cylY(-7.5, PY + 4, -91.5, PY + 7, 1.2, P.metalDark, "ValveStem")
	cylY(7.5, PY + 4, -78.5, PY + 7, 1.2, P.metalDark, "ValveStem")
	blk(5, PY, -94, 9.5, PY + 7, -92, P.metalDark, "ControlCabinet")
	blk(5.4, PY + 3, -92.1, 9.1, PY + 6, -91.9, P.screen, "ControlScreen")
	blk(-9.5, PY, -78, -5, PY + 2.6, -76, P.wood, "Workbench")
	blk(-3, PY - 0.05, -86, 3, PY + 0.02, -84, P.metalDark, "IntakeGrate")
	local pumpLamp = blk(-1, PY + 10.4, -86, 1, PY + 11, -84, P.lampCold, "PumpHouseLight")
	light(pumpLamp, P.lampCold.color, 18, 1)

	for _, s in { -1, 1 } do
		-- ice-locked work barge: hull 4 above the ice, wheelhouse on the outer end
		local x0, x1 = s * 40, s * 64
		blk(x0, PY, -94, x1, PY + 4, -82, P.metalDark, "BargeHull")
		blk(x0 - s * 0.3, PY + 2.4, -94.3, x1 + s * 0.3, PY + 3.2, -81.7, P.paintRed, "BargeStripe")
		blk(s * 56, PY + 4, -92, s * 62, PY + 12.5, -84, P.paintWhite, "Wheelhouse")
		blk(s * 55.9, PY + 9, -91.5, s * 56, PY + 11.5, -84.5, P.glass, "WheelhouseGlass")
		blk(s * 55.5, PY + 12.5, -92.5, s * 62.5, PY + 13.1, -83.5, P.snow, "WheelhouseSnow")
		drums(s * 46, PY + 4, -90, 3)
		case(s * 50, PY + 4, -85, 2.4)
		-- pressure ridges and drifts spaced 15-25 studs apart along the ice
		ridge(s * 24, PY, -101, 11, 6, 4.5, 0.35 * s)
		ridge(s * 22, PY, -71, 9, 5, 4, -0.25 * s)
		ridge(s * 44, PY, -70, 8, 3.2, 5, 0.6 * s, P.snow)
		ridge(s * 72, PY, -98, 10, 6.5, 5, -0.4 * s)
		ridge(s * 102, PY, -86, 6, 7, 14, 0.15 * s)
		ridge(s * 98, PY, -70, 7, 3.5, 4, 0.9 * s, P.snow)
		-- ice-fishing huts
		hut(s * 79, -75, s * 86, -68, 6.5 - 3, P.wood, nil)
		blk(s * 79, PY, -75, s * 86, 0, -68, P.wood, "HutBase")
		hut(s * 84, -106, s * 90, -100, 6.5 - 3, P.paintRed, nil)
		blk(s * 84, PY, -106, s * 90, 0, -100, P.paintRed, "HutBase")
		-- sled with crates
		blk(s * 64, PY, -76, s * 70, PY + 0.8, -72, P.woodDark, "Sled")
		case(s * 66, PY + 0.8, -74, 2.2, 0.2)
	end

	-------------------------------------------------------------------------------------------
	-- Relay compound (middle lane): Z -57..26, fenced X -100..100.
	-------------------------------------------------------------------------------------------
	section("CompoundFence")
	local northGaps: { Opening } = { { -64, -56, 0, 20 }, { -4, 4, 0, 20 }, { 56, 64, 0, 20 } }
	wall(false, -100, 100, -57, -56, 0, 1.5, northGaps, P.concreteDark, "FenceKerb")
	wall(false, -100, 100, -56.8, -56.2, 1.5, 9, northGaps, P.mesh, "FenceMesh")
	for x = -100, 100, 10 do
		local inGap = (math.abs(x) >= 56 and math.abs(x) <= 64) or math.abs(x) <= 4
		if not inGap then
			blk(x - 0.3, 1.5, -56.8, x + 0.3, 9.6, -56.2, P.metalDark, "FencePost")
		end
	end
	for _, s in { -1, 1 } do
		local sideGaps: { Opening } = { { -26, -14, 0, 20 }, { 0, 12, 0, 20 } }
		wall(true, -57, 26, s * 100, s * 101, 0, 1.5, sideGaps, P.concreteDark, "FenceKerb")
		wall(true, -57, 26, s * 100.2, s * 100.8, 1.5, 9, sideGaps, P.mesh, "FenceMesh")
		for _, z in { -50, -38, -4, 20 } do
			blk(s * 100.2, 1.5, z - 0.3, s * 100.8, 9.6, z + 0.3, P.metalDark, "FencePost")
		end
		-- gate posts with warning caps
		for _, z in { -26, -14, 0, 12 } do
			blk(s * 99.6, 0, z - 0.6, s * 101.4, 10, z + 0.6, P.paintYellow, "GatePost")
		end
	end

	section("OperationsBlock")
	-- Two storeys at X -24..24, Z -50..-24. Upper floor Y 13, roof Y 24.
	-- Ground floor: doors north (ice side) and south (mast side).
	-- Upper floor: doors west and east from exterior stair landings; big windows north and south.
	local FLOOR2 = 13
	local groundNS: { Opening } = { { -4, 4, 0, 10 }, { -18, -10, 4, 8 }, { 10, 18, 4, 8 } }
	wall(false, -24, 24, -50, -49, 0, 12, groundNS, P.concrete, "OpsWallN")
	wall(false, -24, 24, -25, -24, 0, 12, groundNS, P.concrete, "OpsWallS")
	local upperNS: { Opening } = { { -20, -6, 15.5, 20.5 }, { 6, 20, 15.5, 20.5 } }
	wall(false, -24, 24, -50, -49, 12, 24, upperNS, P.concrete, "OpsWallN")
	wall(false, -24, 24, -25, -24, 12, 24, upperNS, P.concrete, "OpsWallS")
	for _, s in { -1, 1 } do
		wall(true, -49, -25, s * 23, s * 24, 0, 12, {}, P.concrete, "OpsWallSide")
		wall(true, -49, -25, s * 23, s * 24, 12, 24, { { -49, -43, 13, 22.5 } }, P.concrete, "OpsWallSide")
		-- exterior stair along the side wall, rising north to a landing at Y 13
		stairs(s * 24, -42, s * 31, -24, "-Z", 0, FLOOR2, P.concreteDark)
		blk(s * 24, 0, -50, s * 31, FLOOR2, -42, P.concreteDark, "Landing")
		blk(s * 30.7, FLOOR2, -50, s * 31, FLOOR2 + 3.2, -42, P.metal, "LandingRail")
		blk(s * 24, FLOOR2, -50.3, s * 31, FLOOR2 + 3.2, -50, P.metal, "LandingRail")
		blk(s * 24, FLOOR2 - 0.6, -42.2, s * 31, FLOOR2 + 0.05, -41.8, P.paintYellow, "StairNosing")
		-- ground floor: radio racks against the side walls, desks either side of the centre
		blk(s * 20, 0, -47, s * 23, 7.5, -40, P.metalDark, "RadioRack")
		blk(s * 19.9, 2, -46.5, s * 20, 6.5, -40.5, P.screen, "RackLights")
		blk(s * 20, 0, -34, s * 23, 7.5, -28, P.metalDark, "RadioRack")
		blk(s * 10, 0, -38, s * 15, 3, -35, P.woodDark, "Desk")
		blk(s * 11, 3, -37.5, s * 14, 5, -37.2, P.board, "Monitor")
		-- upper floor: consoles under the windows, chart table
		blk(s * 6, FLOOR2, -48.8, s * 20, FLOOR2 + 3, -46.8, P.metalDark, "Console")
		blk(s * 6, FLOOR2 + 3, -48.8, s * 20, FLOOR2 + 4, -48.2, P.screen, "ConsoleScreens")
		blk(s * 6, FLOOR2, -27.2, s * 20, FLOOR2 + 3, -25.2, P.metalDark, "Console")
		blk(s * 18, FLOOR2, -40, s * 22, FLOOR2 + 6.5, -34, P.metal, "Cabinet")
	end
	blk(-23, 12, -49, 23, FLOOR2, -25, P.metalDark, "OpsFloor2")
	blk(-3, FLOOR2, -39, 3, FLOOR2 + 3, -35, P.wood, "ChartTable")
	blk(-25, 24, -51, 25, 25, -23, P.slate, "OpsRoof")
	blk(-24.5, 25, -50.5, 24.5, 25.6, -23.5, P.snow, "OpsRoofSnow")
	blk(-24.3, 10.5, -50.3, 24.3, 11.8, -23.7, P.paintRed, "OpsBand")
	for _, z in { -46, -28 } do
		local l = blk(-1.5, 11.4, z - 0.5, 1.5, 12, z + 0.5, P.lampCold, "OpsLight")
		light(l, P.lampCold.color, 20, 0.8)
	end
	-- roof kit: dish, aerials, condenser (unreachable roof)
	cylY(-14, 25, -32, 29, 0.8, P.metal, "DishPost")
	box(CFrame.new(-14, 31, -32) * CFrame.Angles(0, 0, math.rad(60)), Vector3.new(0.6, 7, 7), P.paintWhite, "Dish")
	cylY(16, 25, -44, 40, 0.5, P.metal, "Aerial")
	cylY(19, 25, -44, 36, 0.4, P.metal, "Aerial")
	blk(4, 25, -34, 12, 28, -28, P.metal, "Condenser")

	section("RelayMast")
	-- Lattice mast on a raised pad (top Y 0.6). Legs at X +-5, Z 1 / 11. The lowest bay is open.
	blk(-12, 0, -4, 12, 0.6, 16, P.concrete, "MastPad")
	blk(-12, 0.6, -4, 12, 0.65, -3.4, P.paintYellow, "PadEdge")
	blk(-12, 0.6, 15.4, 12, 0.65, 16, P.paintYellow, "PadEdge")
	local MAST_TOP = 62
	local legs = { { -5, 1 }, { 5, 1 }, { -5, 11 }, { 5, 11 } }
	local bands = 6
	for _, lg in legs do
		for i = 0, bands - 1 do
			local y0 = 0.6 + (MAST_TOP - 0.6) * i / bands
			local y1 = 0.6 + (MAST_TOP - 0.6) * (i + 1) / bands
			blk(lg[1] - 0.6, y0, lg[2] - 0.6, lg[1] + 0.6, y1, lg[2] + 0.6, if i % 2 == 0 then P.paintRed else P.paintWhite, "MastLeg")
		end
		blk(lg[1] - 1, 0.6, lg[2] - 1, lg[1] + 1, 1.6, lg[2] + 1, P.concreteDark, "LegFooting")
	end
	for i = 1, bands do
		local y = 0.6 + (MAST_TOP - 0.6) * i / bands
		blk(-5, y - 0.4, 0.6, 5, y + 0.4, 1.4, P.metal, "MastRing")
		blk(-5, y - 0.4, 10.6, 5, y + 0.4, 11.4, P.metal, "MastRing")
		blk(-5.4, y - 0.4, 1, -4.6, y + 0.4, 11, P.metal, "MastRing")
		blk(4.6, y - 0.4, 1, 5.4, y + 0.4, 11, P.metal, "MastRing")
		if i >= 2 then
			-- diagonal braces on each face of bays 2..6 (all well above head height)
			local yb = 0.6 + (MAST_TOP - 0.6) * (i - 1) / bands
			local h = y - yb
			local diag = math.sqrt(100 + h * h)
			local ang = math.atan2(h, 10)
			for _, zf in { 1, 11 } do
				box(CFrame.new(0, (y + yb) / 2, zf) * CFrame.Angles(0, 0, if i % 2 == 0 then ang else -ang), Vector3.new(diag, 0.5, 0.5), P.metal, "Brace")
			end
			for _, xf in { -5, 5 } do
				box(CFrame.new(xf, (y + yb) / 2, 6) * CFrame.Angles(if i % 2 == 0 then ang else -ang, 0, 0), Vector3.new(0.5, 0.5, diag), P.metal, "Brace")
			end
		end
	end
	blk(-6.5, MAST_TOP, -0.5, 6.5, MAST_TOP + 1, 12.5, P.metalDark, "MastPlatform")
	cylY(0, MAST_TOP + 1, 6, 86, 1.2, P.metal, "Antenna")
	for _, y in { 70, 78 } do
		blk(-4, y - 0.3, 5.7, 4, y + 0.3, 6.3, P.metal, "AntennaArm")
	end
	local beacon = blk(-0.9, 86, 5.1, 0.9, 87.8, 6.9, P.beacon, "Beacon")
	light(beacon, P.beacon.color, 40, 2)
	for _, y in { 32, 52 } do
		local b = blk(-5.8, y, 0.2, -4.2, y + 1, 1.8, P.beacon, "ObstructionLight")
		light(b, P.beacon.color, 16, 0.6)
	end
	-- microwave dishes on the mast faces
	cylH(0, 44, -0.6, 1, 7, true, P.paintWhite, "MastDish")
	cylH(0, 36, 12.6, 1, 6, true, P.paintWhite, "MastDish")
	cylH(-6.6, 50, 6, 1, 6, false, P.paintWhite, "MastDish")
	-- equipment cabinets at the pad corners (cover around Flag B)
	blk(-11, 0.6, -3, -8, 5.6, 1, P.metalBlue, "MastCabinet")
	blk(8, 0.6, 11, 11, 5.6, 15, P.metalBlue, "MastCabinet")
	blk(8, 0.6, -3, 11, 3.2, 0, P.metalDark, "CableBox")
	blk(-11, 0.6, 12, -8, 3.2, 15, P.metalDark, "CableBox")
	-- cable tray from the mast to the ops block
	blk(-1, 0, -24, 1, 0.6, -4, P.metalDark, "CableTray")

	section("CompoundYards")
	for _, s in { -1, 1 } do
		-- radio cabin X 52..68, Z -42..-26: doors on the inner side and the south face (Bomb A east)
		local cx0, cx1 = s * 52, s * 68
		local inner = if s < 0 then -52 else 52
		local outer = if s < 0 then -68 else 68
		wall(true, -42, -26, inner, inner + s * 1, 0, 10, { { -38, -31, 0, 9.5 } }, P.metalBlue, "CabinWall")
		wall(true, -42, -26, outer - s * 1, outer, 0, 10, { { -37, -31, 4, 7 } }, P.metalBlue, "CabinWall")
		wall(false, cx0, cx1, -42, -41, 0, 10, { { s * 56, s * 64, 4, 7 } }, P.metalBlue, "CabinWall")
		wall(false, cx0, cx1, -27, -26, 0, 10, { { s * 57, s * 64, 0, 9.5 } }, P.metalBlue, "CabinWall")
		blk(cx0 - s * 0.6, 10, -42.6, cx1 + s * 0.6, 11, -25.4, P.slate, "CabinRoof")
		blk(cx0 - s * 0.4, 11, -42.4, cx1 + s * 0.4, 11.6, -25.6, P.snow, "CabinSnow")
		blk(s * 63, 0, -41, s * 67, 7, -36, P.metalDark, "CabinRack")
		blk(s * 62.9, 2, -40.5, s * 63, 6, -36.5, P.screen, "CabinRackLights")
		blk(s * 53, 0, -40.5, s * 57, 3, -38, P.woodDark, "CabinDesk")
		blk(s * 64.2, 0, -30, s * 67, 3.4, -27, P.metal, "CabinBench")
		local cl = blk(s * 59.5, 9.4, -34.5, s * 60.5, 10, -33.5, P.lampCold, "CabinLight")
		light(cl, P.lampCold.color, 14, 0.8)
		cylY(s * 66, 11, -40, 22, 0.4, P.metal, "CabinAerial")
		-- generator shed (solid) with exhaust stack
		blk(s * 52, 0, 0, s * 68, 8, 12, P.concreteDark, "GeneratorShed")
		blk(s * 51.6, 8, -0.4, s * 68.4, 8.8, 12.4, P.slate, "GeneratorRoof")
		blk(s * 51.7, 2, 2, s * 51.9, 6, 10, P.metalDark, "Louvre")
		cylY(s * 64, 8.8, 9, 16, 1.2, P.metalDark, "ExhaustStack")
		-- yard cover: cases, cable drums, barriers
		case(s * 36, 0, -4, 3, 0.15)
		case(s * 36.5, 3, -4.3, 2.2, 0.3)
		cylH(s * 40, 2.5, -16, 3, 5, false, P.wood, "CableDrum")
		cylH(s * 84, 2.5, -38, 3, 5, false, P.wood, "CableDrum")
		blk(s * 18, 0, -16, s * 24, 3.6, -14, P.concrete, "Barrier")
		blk(s * 84, 0, -6, s * 88, 3.6, 2, P.concrete, "Barrier")
		blk(s * 82, 0, 14, s * 88, 4, 19, P.metalBlue, "Transformer")
		cylY(s * 85, 4, 16.5, 7, 0.8, P.paintWhite, "Insulator")
		case(s * 40, 0, -46, 3, -0.2)
		drums(s * 88, 0, -50, 3)
		-- satellite dish on a stand
		cylY(s * 36, 0, 18, 5, 1.2, P.metalDark, "DishStand")
		box(CFrame.new(s * 36, 7.5, 18) * CFrame.Angles(0, s * 0.6, math.rad(55)), Vector3.new(0.6, 8, 8), P.paintWhite, "SatDish")
		-- yard lamps
		lampPost(s * 90, -48, 14, P.lampWarm)
		lampPost(s * 30, 22, 14, P.lampWarm)
		lampPost(s * 92, 22, 14, P.lampWarm)
	end

	-------------------------------------------------------------------------------------------
	-- Snow berm line (Z 26..34) and motor pool (south lane, Z 34..104).
	-------------------------------------------------------------------------------------------
	section("Berms")
	for _, x in { -84, -36, 36, 84 } do
		berm(x, 30, 20, 4.5, 8, false)
	end
	for _, s in { -1, 1 } do
		berm(s * 46, 96, 14, 4, 7, false)
		berm(s * 112, 38, 12, 4.5, 7, true)
		berm(s * 108, 96, 12, 4, 7, true)
	end
	berm(0, 98, 16, 4, 7, false)

	section("VehicleShed")
	-- X -32..32, Z 44..84, eaves Y 16. Big roller doors at both ends, side doors, high windows.
	local SH = 16
	for _, s in { -1, 1 } do
		wall(true, 44, 84, s * 31, s * 32, 0, SH, { { 56, 72, 0, 12 } }, P.metalBlue, "ShedEnd")
		blk(s * 31.2, 12, 56, s * 31.8, 14.5, 72, P.paintYellow, "RollerDoor")
		cylH(s * 30.4, 15, 64, 16, 1.4, true, P.metalDark, "DoorDrum")
		blk(s * 32, 0, 55, s * 32.6, 12, 56, P.paintYellow, "DoorJamb")
		blk(s * 32, 0, 72, s * 32.6, 12, 73, P.paintYellow, "DoorJamb")
	end
	wall(false, -32, 32, 44, 45, 0, SH, { { -20, -12, 0, 9.5 }, { 12, 20, 0, 9.5 }, { -8, 8, 11, 14 } }, P.metalBlue, "ShedSide")
	wall(false, -32, 32, 83, 84, 0, SH, { { -4, 4, 0, 9.5 }, { -24, -12, 11, 14 }, { 12, 24, 11, 14 } }, P.metalBlue, "ShedSide")
	blk(-33, SH, 43, 33, SH + 1, 85, P.slate, "ShedRoof")
	blk(-32.5, SH + 1, 43.5, 32.5, SH + 1.8, 84.5, P.snow, "ShedRoofSnow")
	blk(-32.3, 8, 43.7, 32.3, 9, 84.3, P.paintRed, "ShedBand")
	-- interior: two snowcats, gantry, benches, drums
	snowcat(-14, 52, false, P.paintOrange)
	snowcat(14, 76, true, P.paintRed)
	blk(-30, 13, 63, 30, 14, 65, P.paintYellow, "Gantry")
	blk(-6, 10.6, 63.5, -4, 13, 64.5, P.metalDark, "Hoist")
	blk(-30, 0, 76, -26, 3.4, 82, P.wood, "Workbench")
	blk(26, 0, 46, 30, 7, 52, P.metalDark, "ToolWall")
	blk(25.9, 1, 46.5, 26, 6.5, 51.5, P.paintYellow, "ToolBoard")
	drums(-27, 0, 48, 3)
	case(27, 0, 79, 3, 0.1)
	case(23, 0, 80.5, 2.2, -0.2)
	for _, z in { 52, 76 } do
		local l = blk(-2, SH - 0.6, z - 1, 2, SH, z + 1, P.lampWarm, "ShedLight")
		light(l, P.lampWarm.color, 24, 1)
	end

	section("FuelDepots")
	for _, s in { -1, 1 } do
		-- bund wall X 62..100, Z 50..88, 3 tall, gaps on every side
		local i0, o0 = s * 62, s * 100
		wall(false, i0, o0, 50, 51, 0, 3, { { s * 76, s * 86, 0, 3 } }, P.concrete, "BundWall")
		wall(false, i0, o0, 87, 88, 0, 3, { { s * 76, s * 86, 0, 3 } }, P.concrete, "BundWall")
		wall(true, 51, 87, i0, i0 + s * 1, 0, 3, { { 62, 74, 0, 3 } }, P.concrete, "BundWall")
		wall(true, 51, 87, o0 - s * 1, o0, 0, 3, { { 62, 74, 0, 3 } }, P.concrete, "BundWall")
		-- two horizontal tanks on saddles
		for _, z in { 57, 79 } do
			for _, x in { 72, 90 } do
				blk(s * x - 1, 0, z - 3, s * x + 1, 2.4, z + 3, P.concreteDark, "Saddle")
			end
			cylH(s * 81, 5.4, z, 26, 8, false, P.tankWhite, "FuelTank")
			cylH(s * 81, 5.4, z, 1.2, 8.3, false, P.paintRed, "TankBand")
			cylY(s * 75, 9.2, z, 10.4, 1.2, P.metalDark, "TankHatch")
		end
		-- pump units between the tanks (cover for Hardpoint 4/5 and Bomb B)
		blk(s * 70, 0, 66, s * 74, 4.5, 70, P.metalBlue, "PumpUnit")
		blk(s * 88, 0, 66, s * 92, 4.5, 70, P.metalBlue, "PumpUnit")
		blk(s * 69.9, 2.5, 66.5, s * 70, 4, 69.5, P.screen, "PumpDisplay")
		cylH(s * 81, 0.6, 62.6, 14, 0.9, false, P.metalDark, "FuelLine")
		-- fuel drums and a light tower outside the bund
		drums(s * 104, 0, 52, 4)
		drums(s * 58, 0, 92, 3)
		lampPost(s * 102, 86, 15, P.lampWarm)
		lampPost(s * 48, 40, 15, P.lampWarm)
		-- parked plough truck near the base wall (also screens the wall gap)
		local px = s * 112
		blk(px - 4, 0, 74, px + 4, 2.2, 88, P.rubber, "TruckChassis")
		blk(px - 4, 2.2, 74, px + 4, 7, 82, P.paintOrange, "TruckBox")
		blk(px - 3.6, 2.2, 82, px + 3.6, 8, 87, P.paintYellow, "TruckCab")
		blk(px - 5, 0.4, 87.4, px + 5, 3.4, 88.2, P.metal, "PloughBlade")
	end

	-------------------------------------------------------------------------------------------
	-- Pipeline trench (south flank): Z 108..124, floor Y -3, X -112..112.
	-------------------------------------------------------------------------------------------
	section("PipelineTrench")
	local TY = -3
	stairs(-112, 108, -104, 124, "-X", TY, 0, P.concrete)
	stairs(104, 108, 112, 124, "+X", TY, 0, P.concrete)
	for _, x in { -50, 0, 50 } do
		stairs(x - 4, 108, x + 4, 113, "-Z", TY, 0, P.concrete)
	end
	cylH(0, -1.4, 121.8, 208, 2.6, false, P.metalBlue, "Pipeline")
	for x = -96, 96, 16 do
		blk(x - 0.8, TY, 120, x + 0.8, -2.2, 123.6, P.concreteDark, "PipeSupport")
	end
	-- zig-zag blocks (valve pits) break the trench into short sections
	for _, s in { -1, 1 } do
		blk(s * 94 - 2, TY, 116, s * 94 + 2, 6, 124, P.concreteDark, "ValvePit")
		blk(s * 80 - 2, TY, 108, s * 80 + 2, 6, 116, P.concreteDark, "ValvePit")
		blk(s * 30 - 2, TY, 115, s * 30 + 2, 6, 124, P.concreteDark, "ValvePit")
		cylH(s * 30, 2, 114.6, 0.4, 2.4, true, P.paintRed, "ValveWheel")
		case(s * 64, TY, 111, 2.6, 0.2)
		cylH(s * 18, -1, 111, 3, 4, false, P.wood, "CableDrum")
		-- timber snow sheds over two sections (roof Y 9, out of reach)
		for _, span in { { 20, 44 }, { 66, 90 } } do
			local xa, xb = s * span[1], s * span[2]
			for _, x in { xa, xb } do
				blk(x - 0.5, 0, 106.5, x + 0.5, 9, 107.5, P.woodDark, "ShedPost")
				blk(x - 0.5, 0, 124.5, x + 0.5, 9, 125.5, P.woodDark, "ShedPost")
			end
			blk(math.min(xa, xb) - 1, 9, 106, math.max(xa, xb) + 1, 9.6, 126, P.wood, "SnowShedRoof")
			blk(math.min(xa, xb) - 0.6, 9.6, 106.4, math.max(xa, xb) + 0.6, 10.3, 125.6, P.snow, "SnowShedSnow")
		end
		local tl = blk(s * 55 - 1, -0.4, 123.4, s * 55 + 1, 0.4, 124, P.lampWarm, "TrenchLight")
		light(tl, P.lampWarm.color, 18, 0.8)
	end
	blk(-3, TY, 116, 3, 0, 124, P.concreteDark, "ManifoldBlock")
	cylY(0, 0, 120, 3, 1.4, P.paintRed, "ManifoldValve")

	-------------------------------------------------------------------------------------------
	-- Team bases: Sable west camp, Talon east camp. Mirror symmetric layout.
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
		-- blast wall (14 tall) with five gaps, one per lane / flank
		local open: { Opening } = {}
		for _, g in GAPS do
			table.insert(open, { g[1], g[2], 0, 20 })
		end
		wall(true, -128, 128, s * WALL_X, s * (WALL_X + 2), 0, 14, open, P.concrete, "BlastWall")
		local cap: { Opening } = {}
		for _, g in GAPS do
			table.insert(cap, { g[1], g[2], 0, 20 })
		end
		wall(true, -128, 128, s * (WALL_X - 0.2), s * (WALL_X + 2.2), 14, 14.6, cap, P.snow, "BlastWallSnow")
		for _, g in GAPS do
			blk(s * (WALL_X - 0.1), 0, g[1] - 0.6, s * (WALL_X + 2.1), 14, g[1], accent, "GapMarker")
			blk(s * (WALL_X - 0.1), 0, g[2], s * (WALL_X + 2.1), 14, g[2] + 0.6, accent, "GapMarker")
			-- barracks hut behind each gap (spawn side) blocks lines through the gap
			local z0 = math.max(g[1] - 8, -128)
			local z1 = math.min(g[2] + 8, 128)
			hut(math.min(s * 134, s * 142), z0, math.max(s * 134, s * 142), z1, 10, if s < 0 then P.wood else P.metalBlue, accent)
		end
		-- camp dressing (kept clear of the spawn columns at |X| 148 / 166)
		local light1 = blk(s * 157 - 1, 15, -121, s * 157 + 1, 15.6, -119, P.lampWarm, "CampLight")
		cylY(s * 157, 0, -120, 15, 0.8, P.metalDark, "CampLightPole")
		light(light1, P.lampWarm.color, 30, 1.2)
		local light2 = blk(s * 157 - 1, 15, 119, s * 157 + 1, 15.6, 121, P.lampWarm, "CampLight")
		cylY(s * 157, 0, 120, 15, 0.8, P.metalDark, "CampLightPole")
		light(light2, P.lampWarm.color, 30, 1.2)
		for _, z in { -82, -46, -10, 26, 62, 98 } do
			blk(s * 156.5, 0, z - 6, s * 157.5, 0.06, z + 6, accent, "LaneMarking")
		end
		case(s * 174, 0, -112, 3)
		case(s * 174, 0, -106, 3, 0.2)
		drums(s * 173, 0, 30, 3)
		case(s * 174, 0, 104, 3, -0.1)
		if s < 0 then
			-- Sable: supply tent and snowmobiles
			blk(-178, 0, -70, -170, 7, -54, P.sable, "SupplyTent")
			blk(-178.2, 7, -70.4, -169.6, 7.6, -53.6, P.snow, "TentSnow")
			for _, z in { 66, 74 } do
				blk(-176, 0, z - 1.2, -170, 2.6, z + 1.2, P.paintRed, "Snowmobile")
			end
		else
			-- Talon: helipad marking and fuel bladder
			blk(157, 0, -40, 177, 0.06, -20, P.concreteDark, "Helipad")
			blk(166, 0.06, -37, 168, 0.1, -23, P.talon, "HelipadMark")
			blk(170, 0, 60, 177, 2.8, 76, P.rubber, "FuelBladder")
		end

		-- team spawns: two columns of six, facing into the map. The front column (|X| 148) sits in
		-- the lanes between the huts so the first view is not a hut wall a few studs away.
		for i, z in { -100, -64, -28, 8, 44, 80 } do
			spawnPart(s * 166, 0, z + 10 + (i % 2) * 2, 0, z * 0.5, team, false)
		end
		for _, z in { -72, -52, -36, 8, 30, 86 } do
			spawnPart(s * 148, 0, z, 0, z * 0.5, team, false)
		end
	end

	-------------------------------------------------------------------------------------------
	-- FFA spawns spread around the whole map. { x, floorY, z, lookX, lookZ }
	-------------------------------------------------------------------------------------------
	local ffa = {
		{ -156, 0, -116, 0, -116 },
		{ 156, 0, 112, 0, 112 },
		{ 156, 0, -46, 0, -46 },
		{ -156, 0, 46, 0, 46 },
		{ -100, 0, -122, 0, -122 },
		{ 52, 0, -120, 0, -120 },
		{ -72, -3, -84, 0, -84 },
		{ 34, -3, -86, 0, -86 },
		{ 104, -3, -100, 0, -86 },
		{ -40, 0, -6, 0, 0 },
		{ 74, 0, -16, 0, -16 },
		{ 8, 0, -31, 0, 0 },
		{ -14, FLOOR2, -36, 0, -36 },
		{ -78, 0, 40, 0, 40 },
		{ 0, 0, 62, 0, 100 },
		{ 82, 0, 100, 0, 100 },
		{ -40, -3, 118, 0, 118 },
		{ 66, -3, 114, 0, 114 },
		{ -116, 0, 70, 0, 70 },
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

	-- Domination: A west compound yard, B on the mast pad, C east compound yard.
	zone("FlagA", "Flag", -72, 0, -12, 18, 18, { Label = "A" })
	zone("FlagB", "Flag", 0, 0.6, 6, 18, 18, { Label = "B" })
	zone("FlagC", "Flag", 72, 0, -12, 18, 18, { Label = "C" })

	-- Hardpoint rotation: ops block -> shed -> pump house -> west depot -> east depot.
	zone("Hardpoint1_OpsBlock", "Hardpoint", 0, 0, -37, 22, 20, { Order = 1 })
	zone("Hardpoint2_VehicleShed", "Hardpoint", 0, 0, 64, 26, 20, { Order = 2 })
	zone("Hardpoint3_PumpHouse", "Hardpoint", 0, PY, -85, 18, 16, { Order = 3 })
	zone("Hardpoint4_WestDepot", "Hardpoint", -81, 0, 68, 20, 16, { Order = 4 })
	zone("Hardpoint5_EastDepot", "Hardpoint", 81, 0, 68, 20, 16, { Order = 5 })

	-- Search and Destroy: Sable (west) attacks first, so both sites sit on the Talon (east) side.
	-- A: inside the east radio cabin (rack, desk, bench). B: east fuel depot between the tanks.
	zone("BombSiteA", "BombSite", 60, 0, -34, 12, 12, { Label = "A" })
	zone("BombSiteB", "BombSite", 81, 0, 68, 14, 12, { Label = "B" })

	-------------------------------------------------------------------------------------------
	-- Lobby camera (frames the relay mast over the compound) + model attributes.
	-------------------------------------------------------------------------------------------
	local cam = Instance.new("Part")
	cam.Name = "LobbyCamera"
	cam.Size = Vector3.new(1, 1, 1)
	cam.CFrame = CFrame.lookAt(Vector3.new(-130, 70, 150), Vector3.new(0, 30, -6))
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
