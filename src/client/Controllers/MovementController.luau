--!strict
-- Tactical movement: sprint (Shift / L3), crouch (C / LeftControl / B), weapon speed penalties.
-- Movement is client-simulated as in all Roblox games; the server's MovementGuard bounds speed.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Config.Weapons)
local ModesConfig = require(Shared.Config.Modes)
local PerkRules = require(Shared.Pure.PerkRules)
local ClientState = require(script.Parent.Parent.ClientState)

local Match = ModesConfig.Match
local player = Players.LocalPlayer

local MovementController = {}

local sprintHeld = false
local crouched = false
local defaultHipHeight: number? = nil
local CROUCH_HIP_DROP = 1.1
local CROUCH_CAMERA = Vector3.new(0, -1.2, 0)
local perkSpeed = 1 -- combined moveSpeed of the perks this life spawned with (Fleetfoot)

-- Read once per deploy from the selected loadout in the latest ProfileSummary.
local function readPerkSpeed(): number
	local profile = ClientState.profile
	local loadout = profile and profile.loadouts and profile.loadouts[profile.selectedLoadout]
	if not loadout or not loadout.perks then
		return 1
	end
	return PerkRules.combine(loadout.perks).moveSpeed
end

local function humanoidAndRoot(): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setCrouch(on: boolean)
	local humanoid = humanoidAndRoot()
	if not humanoid then
		return
	end
	if defaultHipHeight == nil then
		defaultHipHeight = humanoid.HipHeight
	end
	crouched = on
	humanoid.HipHeight = if on then (defaultHipHeight :: number) - CROUCH_HIP_DROP else defaultHipHeight :: number
end

local function update(dt: number)
	local humanoid, root = humanoidAndRoot()
	if not humanoid or not root or humanoid.Health <= 0 then
		if ClientState.sprinting then
			ClientState.sprinting = false
		end
		return
	end
	local character = player.Character :: Model
	if character:GetAttribute("Frozen") == true then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		ClientState.sprinting = false
		return
	end
	humanoid.JumpHeight = if crouched then 0 else 4.2

	local def = ClientState.equippedStats or (ClientState.equippedWeaponId and Weapons[ClientState.equippedWeaponId])
	local weaponMult = if def then def.moveSpeedMultiplier else 1
	local adsMult = if def and ClientState.ads then def.adsMoveSpeedMultiplier else 1

	-- Sprint only while moving mostly forward and not aiming.
	local move = humanoid.MoveDirection
	local forward = workspace.CurrentCamera.CFrame.LookVector
	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	local forwardDot = if move.Magnitude > 0.1 and flatForward.Magnitude > 0.01 then move.Unit:Dot(flatForward.Unit) else 0
	local sprinting = sprintHeld and forwardDot > 0.5 and not ClientState.ads
	if sprinting and crouched then
		setCrouch(false)
	end
	ClientState.sprinting = sprinting

	local speed
	if sprinting then
		speed = Match.SprintSpeed * weaponMult * perkSpeed
	elseif crouched then
		speed = Match.CrouchSpeed * adsMult
	else
		speed = Match.BaseWalkSpeed * weaponMult * adsMult * perkSpeed
	end
	humanoid.WalkSpeed = speed

	local targetOffset = if crouched then CROUCH_CAMERA else Vector3.zero
	humanoid.CameraOffset = humanoid.CameraOffset:Lerp(targetOffset, math.min(1, dt * 12))
end

function MovementController.init()
	ClientState.DeployedChanged:Connect(function(isDeployed)
		sprintHeld = false
		crouched = false
		defaultHipHeight = nil
		ClientState.sprinting = false
		if not isDeployed then
			return
		end
		perkSpeed = readPerkSpeed()
	end)
	ClientState.Fired:Connect(function()
		-- Firing cancels sprint until the key is pressed again.
		sprintHeld = false
	end)
end

function MovementController.start()
	ContextActionService:BindAction("COR_Sprint", function(_, state)
		if state == Enum.UserInputState.Begin then
			sprintHeld = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			sprintHeld = false
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:BindAction("COR_Crouch", function(_, state)
		if state == Enum.UserInputState.Begin and ClientState.deployed then
			setCrouch(not crouched)
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	RunService:BindToRenderStep("COR_Movement", Enum.RenderPriority.Input.Value + 1, update)
end

return MovementController
