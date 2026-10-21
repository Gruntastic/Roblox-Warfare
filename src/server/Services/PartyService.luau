--!strict
-- Squads ("parties") of up to Party.MaxSize players in the same server. The lobby shows the squad
-- in the staging room; the leader's queue pick carries the whole squad, and team modes keep a
-- squad on one team when the balance allows (MatchService).
--
-- Remotes (docs/CONTRACTS.md):
--   PartyInvite(userId)            invite a player in this server to your squad (you lead it if
--                                  you were alone). Any member may invite while there is room.
--   PartyRespond(fromUserId, ok)   accept or decline a pending invite; accepting leaves your old squad
--   PartyLeave()                   leave your squad (the next member leads if the leader leaves)
--   PartyKick(userId)              leader only
--   PartyState -> client           (PartyPayload) after every change that concerns that player
-- Friends outside the server are invited with SocialService on the client (they join the game).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local PartyService = {}

PartyService.MaxSize = 6
local INVITE_TTL = 60 -- seconds an invite stays open
local ACTION_INTERVAL = 0.4

type Party = { leader: Player, members: { Player } }

local partyOf: { [Player]: Party } = {}
local invites: { [Player]: { [Player]: number } } = {} -- target -> inviter -> expiry (os.clock)
local lastAction: { [Player]: number } = {}

local function rateLimited(player: Player): boolean
	local now = os.clock()
	if now - (lastAction[player] or 0) < ACTION_INTERVAL then
		return true
	end
	lastAction[player] = now
	return false
end

local function payloadFor(player: Player): Types.PartyPayload
	local party = partyOf[player]
	local members = {}
	if party then
		for _, m in party.members do
			table.insert(members, m.UserId)
		end
	end
	local pending = {}
	local now = os.clock()
	local list = invites[player]
	if list then
		for from, expires in list do
			if expires > now and from.Parent then
				table.insert(pending, { userId = from.UserId, name = from.DisplayName })
			end
		end
	end
	return {
		leader = if party then party.leader.UserId else nil,
		members = members,
		invites = pending,
		maxSize = PartyService.MaxSize,
	}
end

local function send(player: Player)
	if player.Parent then
		Net.event("PartyState"):FireClient(player, payloadFor(player))
	end
end

local function sendParty(party: Party)
	for _, m in party.members do
		send(m)
	end
	for _, m in party.members do
		m:SetAttribute("PartyLeader", party.leader.UserId)
	end
end

local function removeFrom(player: Player)
	local party = partyOf[player]
	if not party then
		return
	end
	partyOf[player] = nil
	player:SetAttribute("PartyLeader", nil)
	local i = table.find(party.members, player)
	if i then
		table.remove(party.members, i)
	end
	if #party.members <= 1 then
		-- a squad of one is no squad
		for _, m in party.members do
			partyOf[m] = nil
			m:SetAttribute("PartyLeader", nil)
			send(m)
		end
	else
		if party.leader == player then
			party.leader = party.members[1]
		end
		sendParty(party)
	end
	send(player)
end

local function onInvite(player: Player, userId: any)
	if rateLimited(player) or type(userId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player then
		return
	end
	local party = partyOf[player]
	if party and table.find(party.members, target) then
		return
	end
	if party and #party.members >= PartyService.MaxSize then
		Net.event("Notify"):FireClient(player, "Your squad is full", "Warning")
		return
	end
	invites[target] = invites[target] or {}
	invites[target][player] = os.clock() + INVITE_TTL
	Net.event("Notify"):FireClient(player, ("Squad invite sent to %s"):format(target.DisplayName), "Info")
	send(target)
end

local function onRespond(player: Player, fromUserId: any, accept: any)
	if rateLimited(player) or type(fromUserId) ~= "number" then
		return
	end
	local from = Players:GetPlayerByUserId(fromUserId)
	local pending = invites[player]
	local expires = if from and pending then pending[from] else nil
	if pending and from then
		pending[from] = nil
	end
	if not from or not expires or expires < os.clock() or accept ~= true then
		send(player)
		return
	end
	local party = partyOf[from]
	if party and #party.members >= PartyService.MaxSize then
		Net.event("Notify"):FireClient(player, "That squad is full", "Warning")
		send(player)
		return
	end
	if partyOf[player] then
		removeFrom(player)
	end
	if not party then
		party = { leader = from, members = { from } }
		partyOf[from] = party
	end
	local p = party :: Party
	table.insert(p.members, player)
	partyOf[player] = p
	-- the leader's current queue pick carries over to the new member
	local pick = p.leader:GetAttribute("QueuedMode")
	if type(pick) == "string" and PartyService.onJoinedQueue then
		PartyService.onJoinedQueue(player, pick)
	end
	sendParty(p)
end

local function onKick(player: Player, userId: any)
	if rateLimited(player) or type(userId) ~= "number" then
		return
	end
	local party = partyOf[player]
	local target = Players:GetPlayerByUserId(userId)
	if party and target and party.leader == player and target ~= player and partyOf[target] == party then
		removeFrom(target)
		Net.event("Notify"):FireClient(target, "You were removed from the squad", "Warning")
	end
end

-- Squad mates of `player` (not including them). Empty when not in a squad.
function PartyService.mates(player: Player): { Player }
	local party = partyOf[player]
	local out = {}
	if party then
		for _, m in party.members do
			if m ~= player then
				table.insert(out, m)
			end
		end
	end
	return out
end

function PartyService.isLeader(player: Player): boolean
	local party = partyOf[player]
	return party ~= nil and party.leader == player
end

-- Set by MatchService: queue `player` for `pick` (used when a leader's pick carries the squad).
PartyService.onJoinedQueue = nil :: ((Player, string?) -> ())?

function PartyService.init()
	Net.event("PartyInvite").OnServerEvent:Connect(onInvite)
	Net.event("PartyRespond").OnServerEvent:Connect(onRespond)
	Net.event("PartyLeave").OnServerEvent:Connect(function(player)
		if not rateLimited(player) then
			removeFrom(player)
		end
	end)
	Net.event("PartyKick").OnServerEvent:Connect(onKick)
	Players.PlayerAdded:Connect(function(player)
		task.delay(1, send, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		removeFrom(player)
		invites[player] = nil
		lastAction[player] = nil
		for target, list in invites do
			if list[player] then
				list[player] = nil
				send(target)
			end
		end
	end)
end

function PartyService.start()
	-- expire stale invites
	while true do
		task.wait(5)
		local now = os.clock()
		for target, list in invites do
			local changed = false
			for from, expires in list do
				if expires < now then
					list[from] = nil
					changed = true
				end
			end
			if changed then
				send(target)
			end
		end
	end
end

return PartyService
