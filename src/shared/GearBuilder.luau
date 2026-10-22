--!strict
-- Dresses a character as an operator: team uniform, then part-built military kit welded to the
-- body (helmet with headset / night vision, plate carrier with mag pouches, belt kit, pack, gloves,
-- boots, knee pads, team armband and helmet strobe). Sizes and offsets scale with each body part,
-- so the kit fits default R15 bodies and most avatar proportions; R6 gets helmet, vest and belt.
--
-- Used by the server for in-match characters (GearService) and for the lobby staging avatars.
-- Every gear part is massless and cannot collide, be touched or be hit by raycasts, so hit
-- detection and movement are unchanged. Re-dressing replaces the previous kit.
local Gear = require(script.Parent.Config.Gear)
local Assets = require(script.Parent.Config.Assets)

local GearBuilder = {}

GearBuilder.FOLDER = "OperatorGear"

export type Options = {
	teamId: string?, -- picks the team uniform template (Config/Assets.Clothing "<team>.Shirt")
	teamColor: Color3?, -- armband and helmet strobe; nil = neutral amber
	keepAccessories: boolean?, -- default false: avatar accessories are removed so the kit reads clearly
}

local NEUTRAL = Color3.fromRGB(255, 182, 36)
local METAL = Color3.fromRGB(46, 48, 52)

local function part(folder: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p.Parent = folder
	return p
end

local function weld(p: BasePart, to: BasePart, offset: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.CFrame = to.CFrame * offset
end

-- A part welded to `to` at `offset`, all in one call.
local function add(folder: Instance, to: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = part(folder, name, size, color, material, shape)
	weld(p, to, offset)
	return p
end

local function sphere(p: Part)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
end

local function find(character: Model, name: string): BasePart?
	local p = character:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

---------------------------------------------------------------------------------------------
-- Uniform
---------------------------------------------------------------------------------------------

-- A gear set's uniform is used only as a matched pair, so half a set never mixes with a team piece;
-- otherwise each piece falls back to the team template (or to plain colour when that is missing).
local function clothingFor(gear: Gear.GearDef, teamId: string?, piece: string): string?
	if Assets.clothing(gear.id .. ".Shirt") and Assets.clothing(gear.id .. ".Pants") then
		return Assets.clothing(gear.id .. "." .. piece)
	end
	return if teamId then Assets.clothing(teamId .. "." .. piece) else nil
end

local function applyUniform(character: Model, gear: Gear.GearDef, options: Options)
	if not options.keepAccessories then
		for _, child in character:GetChildren() do
			if child:IsA("Accessory") then
				child:Destroy()
			end
		end
	end
	for _, child in character:GetChildren() do
		if child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end
	local shirtId = clothingFor(gear, options.teamId, "Shirt")
	local pantsId = clothingFor(gear, options.teamId, "Pants")
	local shirt = character:FindFirstChildOfClass("Shirt")
	local pants = character:FindFirstChildOfClass("Pants")
	if shirtId then
		local s: Shirt = shirt or Instance.new("Shirt")
		s.ShirtTemplate = shirtId
		s.Parent = character
	elseif shirt then
		shirt:Destroy()
	end
	if pantsId then
		local p: Pants = pants or Instance.new("Pants")
		p.PantsTemplate = pantsId
		p.Parent = character
	elseif pants then
		pants:Destroy()
	end
	-- base colours under (or instead of) the templates
	local colors = character:FindFirstChildOfClass("BodyColors")
	if colors then
		colors.TorsoColor3 = gear.shirt
		colors.LeftArmColor3 = gear.shirt
		colors.RightArmColor3 = gear.shirt
		colors.LeftLegColor3 = gear.pants
		colors.RightLegColor3 = gear.pants
	end
	for _, name in { "UpperTorso", "LowerTorso", "Torso", "LeftUpperArm", "LeftLowerArm", "RightUpperArm", "RightLowerArm", "Left Arm", "Right Arm" } do
		local p = find(character, name)
		if p then
			p.Color = gear.shirt
		end
	end
	for _, name in { "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg", "Left Leg", "Right Leg" } do
		local p = find(character, name)
		if p then
			p.Color = gear.pants
		end
	end
end

---------------------------------------------------------------------------------------------
-- Kit
---------------------------------------------------------------------------------------------

local function buildHelmet(folder: Instance, head: BasePart, gear: Gear.GearDef, team: Color3)
	local u = head.Size.Y -- 1.2 on a default R15 head, 1 on R6
	local dome = add(folder, head, "HelmetShell", Vector3.new(1.14 * u, 0.78 * u, 1.2 * u), CFrame.new(0, 0.24 * u, 0.04 * u), gear.helmet, gear.material)
	sphere(dome)
	-- brim band and side rails
	add(folder, head, "HelmetBand", Vector3.new(1.12 * u, 0.1 * u, 1.14 * u), CFrame.new(0, 0.2 * u, 0.04 * u), gear.webbing)
	for _, side in { -1, 1 } do
		add(folder, head, "HelmetRail", Vector3.new(0.06 * u, 0.12 * u, 0.62 * u), CFrame.new(side * 0.57 * u, 0.3 * u, 0.02 * u), METAL, Enum.Material.Metal)
	end
	-- night-vision shroud on the front; tubes flipped up when the set has NVGs
	add(folder, head, "NVGMount", Vector3.new(0.26 * u, 0.18 * u, 0.1 * u), CFrame.new(0, 0.42 * u, -0.56 * u), METAL, Enum.Material.Metal)
	if gear.nvg then
		local arm = add(folder, head, "NVGArm", Vector3.new(0.2 * u, 0.1 * u, 0.24 * u), CFrame.new(0, 0.56 * u, -0.64 * u), METAL, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			local tube = part(folder, "NVGTube", Vector3.new(0.3 * u, 0.12 * u, 0.12 * u), Color3.fromRGB(26, 28, 30), Enum.Material.Metal, Enum.PartType.Cylinder)
			weld(tube, arm, CFrame.new(side * 0.09 * u, 0.1 * u, -0.02 * u) * CFrame.Angles(0, 0, math.rad(90)))
			local lens = part(folder, "NVGLens", Vector3.new(0.02 * u, 0.1 * u, 0.1 * u), Color3.fromRGB(70, 220, 120), Enum.Material.Neon, Enum.PartType.Cylinder)
			weld(lens, tube, CFrame.new(0.15 * u, 0, 0))
		end
	end
	-- team strobe on the back of the helmet
	add(folder, head, "Strobe", Vector3.new(0.14 * u, 0.1 * u, 0.06 * u), CFrame.new(0, 0.4 * u, 0.6 * u), team, Enum.Material.Neon)
	if gear.headset then
		for _, side in { -1, 1 } do
			local cup = part(folder, "EarCup", Vector3.new(0.12 * u, 0.36 * u, 0.36 * u), Color3.fromRGB(34, 36, 34), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
			weld(cup, head, CFrame.new(side * 0.6 * u, 0, 0.02 * u))
		end
		add(folder, head, "BoomMic", Vector3.new(0.04 * u, 0.04 * u, 0.4 * u), CFrame.new(-0.5 * u, -0.22 * u, -0.28 * u) * CFrame.Angles(0, math.rad(-35), 0), Color3.fromRGB(30, 30, 30), Enum.Material.SmoothPlastic)
	end
	if gear.faceWrap then
		add(folder, head, "FaceWrap", Vector3.new(1.04 * u, 0.42 * u, 1.04 * u), CFrame.new(0, -0.3 * u, 0), gear.faceWrap, Enum.Material.Fabric)
	end
end

local function buildVest(folder: Instance, torso: BasePart, gear: Gear.GearDef, r15: boolean)
	local s = torso.Size
	local plateY = if r15 then 0.08 * s.Y else 0.12 * s.Y
	local plateH = if r15 then 0.8 * s.Y else 0.62 * s.Y
	local plateDepth = 0.2
	local frontZ = -(s.Z / 2 + plateDepth / 2)
	add(folder, torso, "FrontPlate", Vector3.new(0.8 * s.X, plateH, plateDepth), CFrame.new(0, plateY, frontZ), gear.vest, gear.material)
	add(folder, torso, "BackPlate", Vector3.new(0.8 * s.X, plateH, plateDepth), CFrame.new(0, plateY, -frontZ), gear.vest, gear.material)
	-- shoulder straps and side cummerbund
	for _, side in { -1, 1 } do
		add(folder, torso, "ShoulderStrap", Vector3.new(0.3, 0.1, s.Z + 2 * plateDepth), CFrame.new(side * 0.26 * s.X, s.Y / 2 + 0.03, 0), gear.webbing)
		add(folder, torso, "Cummerbund", Vector3.new(0.1, 0.42 * s.Y, s.Z + 0.1), CFrame.new(side * (s.X / 2 - 0.04), -0.18 * s.Y, 0), gear.webbing)
	end
	-- triple mag pouch with magazines peeking out, admin pouch and a radio on the chest
	local pouchW = 0.22 * s.X
	local pouchH = 0.3 * plateH
	local pouchZ = frontZ - plateDepth / 2 - 0.1
	local pouchY = plateY - plateH / 2 + pouchH / 2 + 0.02
	for i = -1, 1 do
		local x = i * (pouchW + 0.05)
		add(folder, torso, "MagPouch", Vector3.new(pouchW, pouchH, 0.2), CFrame.new(x, pouchY, pouchZ), gear.pouches, gear.material)
		add(folder, torso, "Magazine", Vector3.new(pouchW * 0.6, 0.12, 0.12), CFrame.new(x, pouchY + pouchH / 2 + 0.05, pouchZ + 0.02), METAL, Enum.Material.Metal)
	end
	add(folder, torso, "AdminPouch", Vector3.new(0.42 * s.X, 0.22 * plateH, 0.12), CFrame.new(0, pouchY + pouchH / 2 + 0.2 * plateH, frontZ - plateDepth / 2 - 0.06), gear.pouches, gear.material)
	add(folder, torso, "ChestRadio", Vector3.new(0.18, 0.3, 0.14), CFrame.new(0.3 * s.X, plateY + plateH / 2 - 0.12, frontZ - plateDepth / 2 - 0.07), Color3.fromRGB(36, 38, 36), Enum.Material.SmoothPlastic)
	-- grab handle on the back plate
	add(folder, torso, "DragHandle", Vector3.new(0.3, 0.06, 0.08), CFrame.new(0, plateY + plateH / 2 - 0.05, -frontZ + plateDepth / 2 + 0.04), gear.webbing)
end

local function buildPack(folder: Instance, torso: BasePart, gear: Gear.GearDef)
	local s = torso.Size
	local backZ = s.Z / 2 + 0.2
	if gear.pack == "Radio" then
		local radio = add(folder, torso, "RadioPack", Vector3.new(0.42 * s.X, 0.56 * s.Y, 0.36), CFrame.new(0.12 * s.X, 0.02 * s.Y, backZ + 0.18), gear.pouches, gear.material)
		add(folder, radio, "Antenna", Vector3.new(0.04, 1.6, 0.04), CFrame.new(-0.12, 0.28 * s.Y + 0.8, 0.06), Color3.fromRGB(24, 24, 24), Enum.Material.SmoothPlastic)
	elseif gear.pack == "Assault" then
		local pack = add(folder, torso, "AssaultPack", Vector3.new(0.62 * s.X, 0.66 * s.Y, 0.44), CFrame.new(0, 0.02 * s.Y, backZ + 0.22), gear.pouches, gear.material)
		add(folder, pack, "PackFlap", Vector3.new(0.64 * s.X, 0.12, 0.48), CFrame.new(0, 0.33 * s.Y + 0.04, 0), gear.vest, gear.material)
		add(folder, pack, "PackPocket", Vector3.new(0.4 * s.X, 0.28 * s.Y, 0.12), CFrame.new(0, -0.12 * s.Y, 0.27), gear.webbing, gear.material)
	end
end

local function buildBelt(folder: Instance, hips: BasePart, gear: Gear.GearDef, r15: boolean)
	local s = hips.Size
	local y = if r15 then 0.1 * s.Y else -0.42 * s.Y
	local h = if r15 then 0.55 * s.Y else 0.16 * s.Y
	add(folder, hips, "Belt", Vector3.new(s.X + 0.06, h, s.Z + 0.06), CFrame.new(0, y, 0), gear.webbing, gear.material)
	for _, side in { -1, 1 } do
		add(folder, hips, "HipPouch", Vector3.new(0.26, h + 0.16, 0.3), CFrame.new(side * (s.X / 2 - 0.12), y - 0.06, s.Z / 2 + 0.12), gear.pouches, gear.material)
	end
	add(folder, hips, "Buckle", Vector3.new(0.2, h * 0.7, 0.04), CFrame.new(0, y, -(s.Z / 2 + 0.05)), METAL, Enum.Material.Metal)
end

local function buildLimbs(folder: Instance, character: Model, gear: Gear.GearDef, team: Color3)
	-- gloves and boots: shells slightly bigger than the hand / foot
	for _, name in { "LeftHand", "RightHand" } do
		local hand = find(character, name)
		if hand then
			add(folder, hand, "Glove", hand.Size * 1.1, CFrame.identity, gear.gloves, Enum.Material.Fabric)
		end
	end
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = find(character, name)
		if foot then
			add(folder, foot, "Boot", foot.Size * Vector3.new(1.1, 1.15, 1.1), CFrame.new(0, 0.02, 0), gear.boots, Enum.Material.Fabric)
		end
	end
	if gear.kneePads then
		for _, name in { "LeftLowerLeg", "RightLowerLeg" } do
			local leg = find(character, name)
			if leg then
				local s = leg.Size
				add(folder, leg, "KneePad", Vector3.new(0.7 * s.X, 0.28 * s.Y, 0.14), CFrame.new(0, s.Y / 2 - 0.16 * s.Y, -(s.Z / 2 + 0.05)), gear.vest, Enum.Material.SmoothPlastic)
			end
		end
	end
	-- team armband (left) and a holster on the right thigh
	local arm = find(character, "LeftUpperArm") or find(character, "Left Arm")
	if arm then
		local s = arm.Size
		add(folder, arm, "Armband", Vector3.new(s.X + 0.06, 0.16, s.Z + 0.06), CFrame.new(0, 0.12 * s.Y, 0), team, Enum.Material.Neon)
	end
	local thigh = find(character, "RightUpperLeg")
	if thigh then
		local s = thigh.Size
		add(folder, thigh, "Holster", Vector3.new(0.14, 0.5 * s.Y, 0.36), CFrame.new(s.X / 2 + 0.07, 0.05 * s.Y, 0), gear.webbing, gear.material)
	end
end

-- Dresses `character` in the gear set `gearId` (unknown ids fall back to the default set).
function GearBuilder.apply(character: Model, gearId: string?, options: Options?)
	local opts: Options = options or {}
	local gear = Gear.byId[gearId or ""] or Gear.byId[Gear.Default]
	local old = character:FindFirstChild(GearBuilder.FOLDER)
	if old then
		old:Destroy()
	end
	applyUniform(character, gear, opts)

	local folder = Instance.new("Model")
	folder.Name = GearBuilder.FOLDER
	local team = opts.teamColor or NEUTRAL
	local head = find(character, "Head")
	local upper = find(character, "UpperTorso")
	local torso = upper or find(character, "Torso")
	local hips = find(character, "LowerTorso") or find(character, "Torso")
	local r15 = upper ~= nil
	if head then
		buildHelmet(folder, head, gear, team)
	end
	if torso then
		buildVest(folder, torso, gear, r15)
		buildPack(folder, torso, gear)
	end
	if hips then
		buildBelt(folder, hips, gear, r15)
	end
	buildLimbs(folder, character, gear, team)
	folder.Parent = character
	character:SetAttribute("Gear", gear.id)
end

return GearBuilder
