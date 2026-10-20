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
	ads = false,
	sprinting = false,

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
}

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
