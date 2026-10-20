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
	"SetLoadout", -- (index: number, loadout: { primary: string, secondary: string })
	"SelectLoadout", -- (index: number)
	"SetStance", -- (stance: "Stand" | "Crouch" | "Sprint")
	"VoteMap", -- (mapId: string)
	"RequestDeploy", -- () ask to join the running match from the lobby
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
	"Notify", -- (text: string, kind: "Info" | "Warning" | "LevelUp")
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
