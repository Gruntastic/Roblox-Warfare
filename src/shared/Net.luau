--!strict
-- Interface contract for every client/server remote. The server creates these at boot;
-- clients wait for them. Payload shapes are documented in docs/CONTRACTS.md.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.Events = {
	-- client -> server
	"Fire", -- (shotId: number, slot: Slot, origin: Vector3, direction: Vector3)
	"Reload", -- (slot: Slot)
	"Equip", -- (slot: Slot)
	"Melee", -- () server picks the target in front of the character
	"SetLoadout", -- (index: number, loadout: { primary: string, secondary: string, primaryAttachments: {[slot]: id}?, secondaryAttachments: {[slot]: id}?, perks: {id}?, streaks: {id}? }) nil perks/streaks keep the stored ones
	"SelectLoadout", -- (index: number)
	"VoteMap", -- (optionId: string) one of MatchStatePayload.options
	"Interact", -- (holding: boolean) S&D plant / defuse: true on press, false on release
	"RequestDeploy", -- () ask to join the running match from the lobby (only when queued for its mode)
	"JoinQueue", -- (pick: string?) mode id or "Any" to queue (joins a running match of that mode); nil leaves the queue
	"ActivateStreak", -- (id: string, aimDirection: Vector3?) use an earned killstreak; targeted ones aim from the server head position
	"Prestige", -- (confirm: string) must be exactly "PRESTIGE"; only at max level, only outside a match
	"EquipCosmetic", -- (kind: "Camo" | "Title" | "Emblem", id: string, weaponId: string?) camo needs weaponId; Emblem "" unequips
	"BuyItem", -- (itemId: string) Config/Store shop item, paid with earned credits
	"OpenCrate", -- (crateId: string) opens one earned crate
	-- server -> client
	"MatchState", -- (MatchStatePayload)
	"KillFeed", -- (KillFeedPayload)
	"HitConfirm", -- (HitConfirmPayload) to shooter only
	"DamageTaken", -- (DamageTakenPayload) to victim only
	"AmmoState", -- (slot: Slot, mag: number, reserve: number, reloading: boolean)
	"XPGain", -- (XPGainPayload)
	"ProfileSync", -- (ProfileSummary)
	"MatchResults", -- (MatchResultsPayload)
	"Tracer", -- (shooterUserId: number, origin: Vector3, hitPos: Vector3) to everyone except shooter
	"Notify", -- (text: string, kind: "Info" | "Warning" | "LevelUp" | "Challenge")
	"ObjectiveState", -- (ObjectivePayload)
	"ObjectiveEvent", -- (kind: string, data: { [string]: any }) one-off banners, see docs/CONTRACTS.md
	"StreakState", -- (StreakStatePayload) to the owner
	"StreakEvent", -- (kind: string, data: { [string]: any }) killstreak banners and effects, see docs/PHASE5_CONTRACT.md
	"Ping", -- (PingPayload) Recon Drone pings, to the drone owner's team
	"Mark", -- (victimUserId: number, seconds: number) Tracker perk, to the attacker only
	"CrateOpened", -- (CrateResultPayload) to the opener
}

Net.Functions = {
	"GetProfile", -- () -> ProfileSummary?
}

local FOLDER_NAME = "Remotes"

function Net.init()
	assert(RunService:IsServer(), "Net.init is server-only")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) or Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in Net.Events do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in Net.Functions do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
end

local function folder(): Instance
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

function Net.event(name: string): RemoteEvent
	return folder():WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return folder():WaitForChild(name) :: RemoteFunction
end

return Net
