--!strict
-- Session-locked player profile persistence with retries, autosave, migration and
-- a clearly flagged in-memory fallback when DataStores are unavailable (e.g. unpublished place).
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local ProfileSchema = require(Shared.Pure.ProfileSchema)
local SessionLock = require(Shared.Pure.SessionLock)
local Signal = require(Shared.Pure.Signal)
local Weapons = require(Shared.Config.Weapons)
local Progression = require(Shared.Config.Progression)

local STORE_NAME = "PlayerProfiles_v1"
local LOCK_TTL = 300 -- seconds; refreshed by every autosave
local AUTOSAVE_INTERVAL = 60
local MAX_RETRIES = 5
local LOCK_WAIT_ATTEMPTS = 6 -- x LOCK_RETRY_DELAY seconds waiting for another server to release
local LOCK_RETRY_DELAY = 5

type Profile = ProfileSchema.Profile
type Session = { profile: Profile, key: string, loadedAt: number, dirty: boolean, releasing: boolean }

local DataService = {
	ProfileLoaded = Signal.new() :: Signal.Signal<Player, Profile>,
	temporary = false,
}

local store: DataStore? = nil
local sessions: { [Player]: Session } = {}
local jobId = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

local validWeapons: { [string]: string } = {}
for id, def in Weapons do
	validWeapons[id] = def.slot
end

local function keyFor(userId: number): string
	return "u_" .. userId
end

local function withRetries<T>(label: string, fn: () -> T): (boolean, T | string)
	local delay = 1
	local lastErr = ""
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = tostring(result)
		warn(("[DataService] %s failed (attempt %d/%d): %s"):format(label, attempt, MAX_RETRIES, lastErr))
		if attempt < MAX_RETRIES then
			task.wait(delay)
			delay = math.min(delay * 2, 16)
		end
	end
	return false, lastErr
end

local function probeStore()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if not ok then
		warn("[DataService] DataStores unavailable, using TEMPORARY in-memory profiles: " .. tostring(result))
		DataService.temporary = true
		return
	end
	local probeOk, err = pcall(function()
		(result :: DataStore):GetAsync("__probe")
	end)
	if not probeOk then
		warn("[DataService] DataStore probe failed, using TEMPORARY in-memory profiles: " .. tostring(err))
		DataService.temporary = true
		return
	end
	store = result
end

local function loadProfile(player: Player): Profile?
	local now = os.time()
	if DataService.temporary or not store then
		return ProfileSchema.default(now, Progression.DefaultLoadoutSlots)
	end
	local key = keyFor(player.UserId)
	for _ = 1, LOCK_WAIT_ATTEMPTS do
		local status = "error"
		local ok, record = withRetries("load " .. key, function()
			return (store :: DataStore):UpdateAsync(key, function(old)
				local new, s = SessionLock.acquire(old, jobId, os.time(), LOCK_TTL)
				status = s
				return new
			end)
		end)
		if not ok then
			return nil
		end
		if status ~= "locked" then
			if status == "stolen" then
				warn(("[DataService] took over expired session lock for %s"):format(key))
			end
			local rec = record :: any
			local profile = ProfileSchema.migrate(rec and rec.data, now, Progression.DefaultLoadoutSlots, validWeapons)
			return profile
		end
		if not player.Parent then
			return nil
		end
		task.wait(LOCK_RETRY_DELAY)
	end
	return nil
end

local function saveSession(player: Player, session: Session, release: boolean): boolean
	if DataService.temporary or not store then
		return true
	end
	session.profile.lastSeen = os.time()
	local status = "error"
	local ok = withRetries("save " .. session.key, function()
		return (store :: DataStore):UpdateAsync(session.key, function(old)
			local new, s = SessionLock.save(old, jobId, os.time(), session.profile, release)
			status = s
			return new
		end)
	end)
	if status == "lost" then
		warn(("[DataService] session lock for %s lost to another server; not overwriting"):format(session.key))
		return false
	end
	return ok and status == "saved"
end

local function onPlayerAdded(player: Player)
	local profile = loadProfile(player)
	if not player.Parent then
		return
	end
	if not profile then
		player:Kick("Your profile could not be loaded safely. Please rejoin in a moment.")
		return
	end
	sessions[player] = { profile = profile, key = keyFor(player.UserId), loadedAt = os.clock(), dirty = false, releasing = false }
	player:SetAttribute("ProfileLoaded", true)
	DataService.ProfileLoaded:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session or session.releasing then
		return
	end
	session.releasing = true
	saveSession(player, session, true)
	sessions[player] = nil
end

function DataService.getProfile(player: Player): Profile?
	local s = sessions[player]
	return s and s.profile
end

function DataService.markDirty(player: Player)
	local s = sessions[player]
	if s then
		s.dirty = true
	end
end

-- Waits (bounded) until the player's profile is loaded.
function DataService.waitForProfile(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and not sessions[player] and os.clock() < deadline do
		task.wait(0.1)
	end
	return DataService.getProfile(player)
end

function DataService.saveNow(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and saveSession(player, s, false)
end

function DataService.init()
	probeStore()
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	game:BindToClose(function()
		local pending = 0
		for player, session in sessions do
			if not session.releasing then
				session.releasing = true
				pending += 1
				task.spawn(function()
					saveSession(player, session, true)
					pending -= 1
				end)
			end
		end
		local deadline = os.clock() + (if RunService:IsStudio() then 5 else 25)
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for player, session in sessions do
			if not session.releasing then
				task.spawn(saveSession, player, session, false)
			end
		end
	end
end

return DataService
