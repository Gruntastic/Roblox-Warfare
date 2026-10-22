--!strict
-- Operators: the military kit players wear, the lobby staging avatars and third-person aim.
--   * dress(player, character): MatchService calls it on every spawn. The kit (Shared/GearBuilder)
--     uses the player's equipped gear set and team colour, and is applied again once the avatar
--     appearance has finished loading so late avatar accessories and clothing are replaced.
--   * Staging avatars: one R15 model per player in ReplicatedStorage.StagingAvatars (named by
--     UserId), built from the player's avatar and dressed in their gear. The client lobby clones
--     them into its staging room. Attributes: Primary (weapon id of the active loadout), Level.
--   * AimPitch (client -> server, ~10 Hz): the camera pitch in degrees, clamped and rate limited,
--     mirrored as the character attribute AimPitch so other clients can pose the upper body.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Modes = require(Shared.Config.Modes)
local GearBuilder = require(Shared.GearBuilder)
local CosmeticRules = require(Shared.Pure.CosmeticRules)
local DataService = require(script.Parent.DataService)

local OperatorService = {}

local AIM_INTERVAL = 0.07 -- seconds between accepted AimPitch updates per player
local AVATAR_FOLDER = "StagingAvatars"

local avatarFolder: Folder
local lastAim: { [Player]: number } = {}
local building: { [Player]: boolean } = {}
local avatarGear: { [Player]: string } = {}
local failures: { [Player]: number } = {}
local MAX_BUILD_TRIES = 3

local function teamColor(teamId: any): Color3?
	for _, t in Modes.Match.Teams do
		if t.id == teamId then
			return t.color
		end
	end
	return nil
end

local function gearOf(player: Player): string
	local profile = DataService.getProfile(player)
	return if profile then CosmeticRules.gearOf(profile) else "Ranger"
end

function OperatorService.dress(player: Player, character: Model)
	local teamId = player:GetAttribute("Team")
	local options = { teamId = if type(teamId) == "string" then teamId else nil, teamColor = teamColor(teamId) }
	local ok, err = pcall(function(): any
		GearBuilder.apply(character, gearOf(player), options)
		return nil
	end)
	if not ok then
		warn("[OperatorService] dress failed: " .. tostring(err))
		return
	end
	if not player:HasAppearanceLoaded() then
		task.spawn(function()
			local deadline = os.clock() + 8
			while player.Parent and player.Character == character and not player:HasAppearanceLoaded() and os.clock() < deadline do
				task.wait(0.25)
			end
			if player.Parent and player.Character == character and character.Parent then
				pcall(GearBuilder.apply, character, gearOf(player), options)
			end
		end)
	end
end

---------------------------------------------------------------------------------------------
-- Staging avatars
---------------------------------------------------------------------------------------------

local function primaryOf(player: Player): string?
	local profile = DataService.getProfile(player)
	if not profile then
		return nil
	end
	local lo = profile.loadouts[profile.selectedLoadout]
	return if lo then lo.primary else nil
end

local function stamp(model: Model, player: Player)
	model:SetAttribute("Primary", primaryOf(player))
	local profile = DataService.getProfile(player)
	model:SetAttribute("Level", if profile then profile.account.level else 1)
end

local function buildAvatar(player: Player)
	if building[player] then
		return
	end
	building[player] = true
	local description: HumanoidDescription? = nil
	local ok, result = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(math.max(player.UserId, 1))
	end)
	if ok then
		description = result
	end
	local model: Model? = nil
	local built, made = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description or Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if built then
		model = made
	else
		warn("[OperatorService] staging avatar failed for " .. player.Name .. ": " .. tostring(made))
	end
	building[player] = nil
	if not model then
		failures[player] = (failures[player] or 0) + 1
	end
	if not model or not player.Parent then
		return
	end
	model.Name = tostring(player.UserId)
	-- a display model: no scripts, no physics
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = d.Name == "HumanoidRootPart"
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local gearId = gearOf(player)
	pcall(GearBuilder.apply, model, gearId, {})
	avatarGear[player] = gearId
	stamp(model, player)
	local old = avatarFolder:FindFirstChild(model.Name)
	if old then
		old:Destroy()
	end
	model.Parent = avatarFolder
end

-- Re-dresses the staging avatar after a gear change and refreshes its loadout attributes.
function OperatorService.refreshAvatar(player: Player)
	local model = avatarFolder:FindFirstChild(tostring(player.UserId))
	if not model or not model:IsA("Model") then
		if (failures[player] or 0) < MAX_BUILD_TRIES then
			task.spawn(buildAvatar, player)
		end
		return
	end
	local gearId = gearOf(player)
	if avatarGear[player] ~= gearId then
		avatarGear[player] = gearId
		pcall(GearBuilder.apply, model, gearId, {})
	end
	stamp(model, player)
end

---------------------------------------------------------------------------------------------
-- Aim pitch
---------------------------------------------------------------------------------------------

local function onAimPitch(player: Player, pitch: any)
	if type(pitch) ~= "number" or pitch ~= pitch then
		return
	end
	local now = os.clock()
	if now - (lastAim[player] or 0) < AIM_INTERVAL then
		return
	end
	lastAim[player] = now
	local character = player.Character
	if character then
		character:SetAttribute("AimPitch", math.floor(math.clamp(pitch, -80, 80) + 0.5))
	end
end

function OperatorService.init()
	local existing = ReplicatedStorage:FindFirstChild(AVATAR_FOLDER)
	if existing and existing:IsA("Folder") then
		avatarFolder = existing
	else
		avatarFolder = Instance.new("Folder")
		avatarFolder.Name = AVATAR_FOLDER
		avatarFolder.Parent = ReplicatedStorage
	end
	Net.event("AimPitch").OnServerEvent:Connect(onAimPitch)
	DataService.ProfileLoaded:Connect(function(player)
		task.spawn(buildAvatar, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAim[player] = nil
		building[player] = nil
		avatarGear[player] = nil
		failures[player] = nil
		local model = avatarFolder:FindFirstChild(tostring(player.UserId))
		if model then
			model:Destroy()
		end
	end)
end

function OperatorService.start()
	-- keep the avatars' loadout attributes current (loadout and gear changes happen in the lobby)
	while true do
		task.wait(2)
		for _, player in Players:GetPlayers() do
			if DataService.getProfile(player) then
				OperatorService.refreshAvatar(player)
			end
		end
	end
end

return OperatorService
