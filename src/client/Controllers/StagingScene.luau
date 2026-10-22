--!strict
-- The lobby staging room: a client-only hangar set far above the map where the local operator
-- stands in front of the camera with up to five squad mates around them, all in their gear,
-- holding their primary and idling (OperatorAnimator.stagingPose). The Lobby turns it on while it
-- is shown; CameraController then films it instead of the map overview.
--
-- Slots (StagingScene.SLOTS): 1 is always the local player; 2-6 are squad mates in join order.
-- Empty slots show a floor ring; the Lobby draws the INVITE buttons and name plates over them
-- using StagingScene.slotScreen().
--
-- Avatars come from ReplicatedStorage.StagingAvatars (built and dressed by the server's
-- OperatorService). They are re-cloned when the server re-dresses them or the loadout changes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)
local OperatorAnimator = require(script.Parent.OperatorAnimator)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local Weapons = require(Shared.Config.Weapons)
local WeaponModel = require(Shared.WeaponModel)

local StagingScene = {}

local player = Players.LocalPlayer
local ORIGIN = CFrame.new(0, 1200, 0) -- floor centre of the room; the camera looks down -Z
local FOV = 50

StagingScene.SLOTS = {
	Vector3.new(0, 0, 0),
	Vector3.new(-3.9, 0, -1.6),
	Vector3.new(3.9, 0, -1.6),
	Vector3.new(-7.6, 0, -3.4),
	Vector3.new(7.6, 0, -3.4),
	Vector3.new(0, 3, -6.8), -- on the catwalk behind
}
local CAMERA_LOCAL = CFrame.lookAt(Vector3.new(0, 4.6, 15.5), Vector3.new(0, 3.1, -1.5))

type Occupant = { key: string, model: Model, seed: number }

local active = false
local room: Model? = nil
local occupants: { [number]: Occupant } = {}
local rings: { [number]: BasePart } = {}
local clock = 0

---------------------------------------------------------------------------------------------
-- Room
---------------------------------------------------------------------------------------------

local function block(parent: Instance, name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = ORIGIN * at
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function crate(parent: Instance, at: CFrame, size: Vector3)
	local body = block(parent, "Crate", size, at, Color3.fromRGB(74, 80, 52), Enum.Material.Wood)
	for _, dy in { -0.35, 0.35 } do
		block(parent, "CrateBand", Vector3.new(size.X + 0.05, 0.18, size.Z + 0.05), at * CFrame.new(0, dy * size.Y, 0), Color3.fromRGB(40, 42, 34), Enum.Material.Metal)
	end
	-- stencilled hazard stripe on the front
	block(parent, "CrateStripe", Vector3.new(size.X * 0.5, 0.12, 0.04), at * CFrame.new(0, 0, -size.Z / 2 - 0.02), Color3.fromRGB(255, 182, 36), Enum.Material.SmoothPlastic)
	return body
end

local function lamp(parent: Instance, at: Vector3, color: Color3, brightness: number, range: number)
	local shade = block(parent, "Lamp", Vector3.new(1.4, 0.4, 1.4), CFrame.new(at), Color3.fromRGB(30, 32, 34), Enum.Material.Metal)
	local bulb = block(parent, "Bulb", Vector3.new(0.9, 0.12, 0.9), CFrame.new(at - Vector3.new(0, 0.26, 0)), color, Enum.Material.Neon)
	block(parent, "LampCable", Vector3.new(0.06, 14 - at.Y, 0.06), CFrame.new(at + Vector3.new(0, (14 - at.Y) / 2, 0)), Color3.fromRGB(20, 20, 20))
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = true
	light.Parent = bulb
	return shade
end

local function spot(parent: Instance, from: Vector3, toward: Vector3, color: Color3, brightness: number, range: number, angle: number)
	local p = block(parent, "Spot", Vector3.new(0.6, 0.6, 0.9), CFrame.lookAt(from, toward), Color3.fromRGB(26, 28, 30), Enum.Material.Metal)
	p.Transparency = 0
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Angle = angle
	light.Shadows = true
	light.Parent = p
end

local function buildRoom(): Model
	local model = Instance.new("Model")
	model.Name = "StagingRoom"
	local floorColor = Color3.fromRGB(46, 48, 50)
	local wall = Color3.fromRGB(38, 42, 44)
	local amber = Color3.fromRGB(255, 182, 36)

	-- shell: floor, back wall, side walls, ceiling
	block(model, "Floor", Vector3.new(64, 1, 44), CFrame.new(0, -0.5, 0), floorColor, Enum.Material.Concrete)
	local back = block(model, "BackWall", Vector3.new(64, 16, 1), CFrame.new(0, 7.5, -12), wall, Enum.Material.Metal)
	block(model, "LeftWall", Vector3.new(1, 16, 44), CFrame.new(-24, 7.5, 0), wall, Enum.Material.Metal)
	block(model, "RightWall", Vector3.new(1, 16, 44), CFrame.new(24, 7.5, 0), wall, Enum.Material.Metal)
	block(model, "Ceiling", Vector3.new(64, 1, 44), CFrame.new(0, 15.5, 0), Color3.fromRGB(24, 26, 28), Enum.Material.Metal)
	block(model, "FrontWall", Vector3.new(64, 16, 1), CFrame.new(0, 7.5, 22), wall, Enum.Material.Metal)

	-- back wall: ForgeGUI hangar art when published, ribbed steel otherwise
	local backdrop = Assets.image("StagingBackdrop")
	if backdrop then
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Front
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 24
		surface.LightInfluence = 0.6
		surface.Parent = back
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = backdrop
		image.ScaleType = Enum.ScaleType.Crop
		image.Parent = surface
	else
		for x = -30, 30, 3 do
			block(model, "Rib", Vector3.new(0.5, 15, 0.5), CFrame.new(x, 7.5, -11.4), Color3.fromRGB(52, 56, 58), Enum.Material.Metal)
		end
	end
	-- hazard band and a neon strip along the bottom of the back wall
	for x = -30, 30, 4 do
		block(model, "Hazard", Vector3.new(2, 0.6, 0.1), CFrame.new(x, 0.3, -11.45) * CFrame.Angles(0, 0, math.rad(35)), amber, Enum.Material.SmoothPlastic)
	end
	block(model, "Strip", Vector3.new(60, 0.12, 0.12), CFrame.new(0, 1.2, -11.4), amber, Enum.Material.Neon)

	-- catwalk for slot 6, with railings
	local slot6 = StagingScene.SLOTS[6]
	block(model, "Catwalk", Vector3.new(7, slot6.Y, 4), CFrame.new(slot6.X, slot6.Y / 2, slot6.Z), Color3.fromRGB(58, 62, 64), Enum.Material.DiamondPlate)
	block(model, "CatwalkEdge", Vector3.new(7.2, 0.15, 0.15), CFrame.new(slot6.X, slot6.Y, slot6.Z + 2), amber, Enum.Material.Neon)
	for _, side in { -1, 1 } do
		block(model, "Rail", Vector3.new(0.15, 3, 0.15), CFrame.new(slot6.X + side * 3.4, slot6.Y + 1.5, slot6.Z - 1.8), Color3.fromRGB(30, 32, 34), Enum.Material.Metal)
		block(model, "Step", Vector3.new(1.4, slot6.Y / 2, 2), CFrame.new(slot6.X + side * 4.3, slot6.Y / 4, slot6.Z), Color3.fromRGB(58, 62, 64), Enum.Material.DiamondPlate)
	end
	block(model, "RailTop", Vector3.new(7, 0.15, 0.15), CFrame.new(slot6.X, slot6.Y + 3, slot6.Z - 1.8), Color3.fromRGB(30, 32, 34), Enum.Material.Metal)

	-- props: crate stacks, barrels, sandbags, weapon rack
	crate(model, CFrame.new(-13, 1.25, -8) * CFrame.Angles(0, math.rad(8), 0), Vector3.new(4, 2.5, 3))
	crate(model, CFrame.new(-13.2, 3.5, -8.2) * CFrame.Angles(0, math.rad(-4), 0), Vector3.new(3, 2, 2.6))
	crate(model, CFrame.new(-10.2, 1, -9.5), Vector3.new(2.4, 2, 2.4))
	crate(model, CFrame.new(13, 1.25, -8.5) * CFrame.Angles(0, math.rad(-10), 0), Vector3.new(4, 2.5, 3))
	crate(model, CFrame.new(16.5, 1, -6.5) * CFrame.Angles(0, math.rad(20), 0), Vector3.new(2.4, 2, 2.4))
	for i, x in { 11.5, 12.9, 12.2 } do
		local barrel = block(model, "Barrel", Vector3.new(2.6, 1.3, 1.3), CFrame.new(x, 1.3, -4.5 - i * 0.2 + (if i == 3 then 1.3 else 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 82, 56), Enum.Material.Metal, Enum.PartType.Cylinder)
		barrel.Name = "Barrel"
	end
	for i = 0, 5 do
		block(model, "Sandbag", Vector3.new(1.8, 0.7, 1), CFrame.new(-12.5 + (i % 3) * 1.7 + (if i >= 3 then 0.85 else 0), 0.35 + (if i >= 3 then 0.7 else 0), -3.8), Color3.fromRGB(150, 132, 96), Enum.Material.Fabric)
	end
	local rack = block(model, "WeaponRack", Vector3.new(8, 4, 0.4), CFrame.new(0, 7, -11.2), Color3.fromRGB(34, 36, 38), Enum.Material.Metal)
	rack.Transparency = if backdrop then 1 else 0

	-- floor rings under each slot (the local player's is brighter)
	for i, pos in StagingScene.SLOTS do
		local ring = block(model, "SlotRing" .. i, Vector3.new(0.08, 3.6, 3.6), CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), amber, Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.Transparency = if i == 1 then 0.35 else 0.75
		rings[i] = ring
	end

	-- lighting: warm hanging lamps, a cool key from the front, amber rim from behind
	lamp(model, Vector3.new(-6, 11, -2), Color3.fromRGB(255, 196, 120), 1.4, 22)
	lamp(model, Vector3.new(6, 11, -2), Color3.fromRGB(255, 196, 120), 1.4, 22)
	lamp(model, Vector3.new(0, 11.5, -7), Color3.fromRGB(255, 186, 100), 1.2, 20)
	spot(model, Vector3.new(-9, 9, 12), Vector3.new(0, 3, -1), Color3.fromRGB(210, 225, 255), 3, 40, 50)
	spot(model, Vector3.new(9, 9, 12), Vector3.new(0, 3, -2), Color3.fromRGB(200, 215, 240), 2, 40, 55)
	spot(model, Vector3.new(0, 10, -10), Vector3.new(0, 3, 0), amber, 2.5, 30, 70)
	model.Parent = workspace
	return model
end

---------------------------------------------------------------------------------------------
-- Occupants
---------------------------------------------------------------------------------------------

local function slotUsers(): { [number]: number }
	local users: { [number]: number } = { [1] = player.UserId }
	local party = ClientState.party
	if party then
		local n = 1
		for _, userId in party.members do
			if userId ~= player.UserId and n < #StagingScene.SLOTS then
				n += 1
				users[n] = userId
			end
		end
	end
	return users
end

local function templateFor(userId: number): Model?
	local folder = ReplicatedStorage:FindFirstChild("StagingAvatars")
	local m = folder and folder:FindFirstChild(tostring(userId))
	return if m and m:IsA("Model") then m else nil
end

local function camoFor(weaponId: string): string?
	local profile = ClientState.profile
	local eq = profile and profile.cosmetics and profile.cosmetics.equipped
	return if eq then eq.camos[weaponId] else nil
end

local function placeOccupant(index: number, template: Model, isLocal: boolean): Model?
	local model = template:Clone()
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root then
		model:Destroy()
		return nil
	end
	local height = (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2
	local pos = StagingScene.SLOTS[index]
	-- face the camera, turned slightly towards the centre of the room
	local yaw = math.rad(math.clamp(-pos.X * 2.2, -16, 16))
	root.Anchored = true
	model:PivotTo(ORIGIN * CFrame.new(pos + Vector3.new(0, height, 0)) * CFrame.Angles(0, math.rad(180) + yaw, 0))
	-- primary weapon at low ready, mounted on the chest like the in-match world weapon
	local weaponId = template:GetAttribute("Primary")
	local def = if type(weaponId) == "string" then Weapons[weaponId] else nil
	local torso = model:FindFirstChild("UpperTorso") :: BasePart?
	if def and torso then
		local ok, gun = pcall(WeaponModel.build, def, { castShadow = true, camo = if isLocal then camoFor(def.id) else nil })
		if ok and gun then
			local grip = gun.PrimaryPart :: BasePart
			local weld = Instance.new("Weld")
			weld.Part0 = torso
			weld.Part1 = grip
			weld.C0 = CFrame.new(0.4, -0.35, -1.05) * CFrame.Angles(math.rad(-22), math.rad(18), 0)
			weld.Parent = grip
			gun.Parent = model
		end
	end
	model.Parent = room
	return model
end

-- Templates are replaced when the server rebuilds an avatar; a serial per instance notices that.
local serials: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local nextSerial = 0

local function keyFor(userId: number, template: Model?): string
	if not template then
		return tostring(userId) .. ":none"
	end
	local serial = serials[template]
	if not serial then
		nextSerial += 1
		serial = nextSerial
		serials[template] = serial
	end
	return table.concat({
		tostring(userId),
		tostring(serial),
		tostring(template:GetAttribute("Gear")),
		tostring(template:GetAttribute("Primary")),
	}, ":")
end

local function refreshOccupants()
	local users = slotUsers()
	for i = 1, #StagingScene.SLOTS do
		local userId = users[i]
		local template = if userId then templateFor(userId) else nil
		local key = if userId then keyFor(userId, template) else ""
		local current = occupants[i]
		if not current or current.key ~= key then
			if current then
				current.model:Destroy()
				occupants[i] = nil
			end
			if userId and template then
				local model = placeOccupant(i, template, i == 1)
				if model then
					occupants[i] = { key = key, model = model, seed = i * 1.37 + (userId % 97) / 13 }
				end
			end
		end
		local ring = rings[i]
		if ring then
			ring.Transparency = if userId then 0.35 else 0.75
		end
	end
end

---------------------------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------------------------

function StagingScene.setActive(on: boolean)
	if on == active then
		return
	end
	active = on
	if on then
		if not room then
			room = buildRoom()
		end
		refreshOccupants()
	end
end

function StagingScene.isActive(): boolean
	return active
end

function StagingScene.cameraCFrame(): CFrame
	-- a slow breathing drift so the shot never looks frozen
	local drift = CFrame.new(math.sin(clock * 0.21) * 0.25, math.sin(clock * 0.33) * 0.12, 0)
	return ORIGIN * CAMERA_LOCAL * drift
end

StagingScene.FOV = FOV

export type SlotScreen = { index: number, userId: number?, position: Vector2, onScreen: boolean, filled: boolean }

-- Where each slot's name plate / INVITE button goes on screen (viewport pixels, under the feet
-- of the operator). Only meaningful while active.
function StagingScene.slotScreen(): { SlotScreen }
	local cam = workspace.CurrentCamera
	local users = slotUsers()
	local out = {}
	for i, pos in StagingScene.SLOTS do
		local world = (ORIGIN * CFrame.new(pos + Vector3.new(0, -0.2, 0))).Position
		local screen, onScreen = cam:WorldToViewportPoint(world)
		table.insert(out, {
			index = i,
			userId = users[i],
			position = Vector2.new(screen.X, screen.Y),
			onScreen = onScreen,
			filled = occupants[i] ~= nil,
		})
	end
	return out
end

-- Screen position of a point `height` studs above slot `index` (for name plates over heads).
function StagingScene.slotPoint(index: number, height: number): (Vector2, boolean)
	local cam = workspace.CurrentCamera
	local pos = StagingScene.SLOTS[index]
	local world = (ORIGIN * CFrame.new(pos + Vector3.new(0, height, 0))).Position
	local screen, onScreen = cam:WorldToViewportPoint(world)
	return Vector2.new(screen.X, screen.Y), onScreen
end

function StagingScene.init()
	ClientState.PartyChanged:Connect(function()
		if active then
			refreshOccupants()
		end
	end)
end

function StagingScene.start()
	RunService.PreSimulation:Connect(function(dt: number)
		if not active then
			return
		end
		clock += dt
		for _, occ in occupants do
			OperatorAnimator.stagingPose(occ.model, clock, occ.seed)
		end
	end)
	-- avatars are built by the server a moment after join and re-dressed on gear changes
	while true do
		task.wait(0.5)
		if active then
			refreshOccupants()
		end
	end
end

return StagingScene
