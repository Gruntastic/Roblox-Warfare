--!strict
-- Single client-side store. Mirrors server pushes and exposes signals for controllers and UI.
-- The server is authoritative for everything in here; nothing is written back except via Net.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Pure.Signal)
local Types = require(Shared.Types)

type AmmoInfo = { mag: number, reserve: number, reloading: boolean }

local ClientState = {
	matchState = nil :: Types.MatchStatePayload?,
	profile = nil :: Types.ProfileSummary?,
	ammo = {} :: { [string]: AmmoInfo },
	deployed = false, -- local character is alive in the match
	equippedSlot = "Primary" :: Types.Slot,
	equippedWeaponId = nil :: string?,
	equippedStats = nil :: any, -- WeaponStats.Effective of the equipped weapon (attachments applied)
	ads = false,
	sprinting = false,
	objective = nil :: Types.ObjectivePayload?, -- latest ObjectiveState (nil until the first one arrives)
	interacting = false, -- Interact (plant / defuse) is held
	-- Phase 5
	streak = nil :: Types.StreakStatePayload?, -- latest StreakState (nil until the first one arrives)
	ping = nil :: Types.PingPayload?, -- latest Recon Drone ping (HUD compass fades it at expiresAt)
	jammedUntil = 0, -- server time: our compass is jammed by an enemy Counter-Recon until then
	blackoutUntil = 0, -- server time: our HUD is knocked out by an enemy Blackout until then
	menus = {} :: { [string]: boolean }, -- full-screen menus open right now (Gunsmith, Barracks)

	MatchStateChanged = Signal.new() :: Signal.Signal<Types.MatchStatePayload>,
	ProfileChanged = Signal.new() :: Signal.Signal<Types.ProfileSummary>,
	AmmoChanged = Signal.new() :: Signal.Signal<string, AmmoInfo>,
	KillFeed = Signal.new() :: Signal.Signal<Types.KillFeedPayload>,
	HitConfirm = Signal.new() :: Signal.Signal<Types.HitConfirmPayload>,
	DamageTaken = Signal.new() :: Signal.Signal<Types.DamageTakenPayload>,
	XPGain = Signal.new() :: Signal.Signal<Types.XPGainPayload>,
	MatchResults = Signal.new() :: Signal.Signal<Types.MatchResultsPayload>,
	Notify = Signal.new() :: Signal.Signal<string, string>,
	DeployedChanged = Signal.new() :: Signal.Signal<boolean>,
	WeaponChanged = Signal.new() :: Signal.Signal<string, string?>, -- slot, weaponId
	AdsChanged = Signal.new() :: Signal.Signal<boolean>,
	Fired = Signal.new() :: Signal.Signal<string>, -- local shot fired (weaponId), for crosshair bloom
	ObjectiveChanged = Signal.new() :: Signal.Signal<Types.ObjectivePayload>,
	ObjectiveEvent = Signal.new() :: Signal.Signal<string, { [string]: any }>, -- kind, data (see docs/CONTRACTS.md)
	-- Phase 5
	StreakStateChanged = Signal.new() :: Signal.Signal<Types.StreakStatePayload>,
	StreakEvent = Signal.new() :: Signal.Signal<string, { [string]: any }>, -- kind, data (see docs/PHASE5_CONTRACT.md)
	PingReceived = Signal.new() :: Signal.Signal<Types.PingPayload>,
	Mark = Signal.new() :: Signal.Signal<number, number>, -- victimUserId, seconds (Tracker perk)
	HudEffectsChanged = Signal.new() :: Signal.Signal<()>, -- jammedUntil / blackoutUntil changed
	MenuChanged = Signal.new() :: Signal.Signal<()>,
	-- Phase 7: on-screen touch controls (UI/TouchControls) -> controllers. name: "Fire" | "ADS" |
	-- "Reload" | "Swap" | "Melee" | "Sprint" | "Crouch"; down = pressed (true) or released (false)
	-- sound cue: Config/Audio slot name, optional world position (nil = 2D), optional pitch offset
	Sfx = Signal.new() :: Signal.Signal<string, Vector3?, number?>,
	TouchAction = Signal.new() :: Signal.Signal<string, boolean>,
}

-- Full-screen menus register here so gameplay input (killstreak keys) can ignore presses meanwhile.
function ClientState.setMenuOpen(name: string, open: boolean)
	local was = ClientState.menus[name] == true
	if was == open then
		return
	end
	if open then
		ClientState.menus[name] = true
	else
		ClientState.menus[name] = nil
	end
	ClientState.MenuChanged:Fire()
end

function ClientState.isMenuOpen(): boolean
	return next(ClientState.menus) ~= nil
end

-- True while an enemy Blackout knocks out the local HUD / Counter-Recon jams our compass.
function ClientState.isBlackedOut(): boolean
	return ClientState.blackoutUntil > workspace:GetServerTimeNow()
end

function ClientState.isJammed(): boolean
	return ClientState.jammedUntil > workspace:GetServerTimeNow()
end

local function onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	ClientState.deployed = true
	ClientState.DeployedChanged:Fire(true)
	humanoid.Died:Connect(function()
		ClientState.deployed = false
		ClientState.DeployedChanged:Fire(false)
	end)
end

function ClientState.init()
	Net.event("MatchState").OnClientEvent:Connect(function(payload)
		ClientState.matchState = payload
		ClientState.MatchStateChanged:Fire(payload)
	end)
	Net.event("ProfileSync").OnClientEvent:Connect(function(profile)
		ClientState.profile = profile
		ClientState.ProfileChanged:Fire(profile)
	end)
	Net.event("AmmoState").OnClientEvent:Connect(function(slot, mag, reserve, reloading)
		local info = { mag = mag, reserve = reserve, reloading = reloading }
		ClientState.ammo[slot] = info
		ClientState.AmmoChanged:Fire(slot, info)
	end)
	Net.event("KillFeed").OnClientEvent:Connect(function(p)
		ClientState.KillFeed:Fire(p)
	end)
	Net.event("HitConfirm").OnClientEvent:Connect(function(p)
		ClientState.HitConfirm:Fire(p)
	end)
	Net.event("DamageTaken").OnClientEvent:Connect(function(p)
		ClientState.DamageTaken:Fire(p)
	end)
	Net.event("XPGain").OnClientEvent:Connect(function(p)
		ClientState.XPGain:Fire(p)
	end)
	Net.event("MatchResults").OnClientEvent:Connect(function(p)
		ClientState.MatchResults:Fire(p)
	end)
	Net.event("Notify").OnClientEvent:Connect(function(text, kind)
		ClientState.Notify:Fire(text, kind)
	end)
	Net.event("ObjectiveState").OnClientEvent:Connect(function(p)
		ClientState.objective = p
		ClientState.ObjectiveChanged:Fire(p)
	end)
	Net.event("ObjectiveEvent").OnClientEvent:Connect(function(kind, data)
		ClientState.ObjectiveEvent:Fire(kind, data or {})
	end)

	Net.event("StreakState").OnClientEvent:Connect(function(p)
		if type(p) == "table" then
			ClientState.streak = p
			ClientState.StreakStateChanged:Fire(p)
		end
	end)
	Net.event("StreakEvent").OnClientEvent:Connect(function(kind, data)
		if type(kind) == "string" then
			ClientState.StreakEvent:Fire(kind, if type(data) == "table" then data else {})
		end
	end)
	Net.event("Ping").OnClientEvent:Connect(function(p)
		if type(p) == "table" and type(p.targets) == "table" and type(p.expiresAt) == "number" then
			ClientState.ping = p
			ClientState.PingReceived:Fire(p)
		end
	end)
	Net.event("Mark").OnClientEvent:Connect(function(victimUserId, seconds)
		if type(victimUserId) == "number" and type(seconds) == "number" then
			ClientState.Mark:Fire(victimUserId, seconds)
		end
	end)

	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		ClientState.deployed = false
		ClientState.DeployedChanged:Fire(false)
	end)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	task.spawn(function()
		local ok, profile = pcall(function()
			return Net.func("GetProfile"):InvokeServer()
		end)
		if ok and profile then
			ClientState.profile = profile
			ClientState.ProfileChanged:Fire(profile)
		end
	end)
end

return ClientState
