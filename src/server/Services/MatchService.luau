--!strict
-- Match lifecycle for a single server: lobby -> countdown -> playing -> results -> lobby.
-- Owns teams, spawns, map loading, scoring and the authoritative MatchState broadcast.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local TeamsLogic = require(Shared.Pure.Teams)
local MatchRules = require(Shared.Pure.MatchRules)
local ModesConfig = require(Shared.Config.Modes)
local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local CombatService = require(script.Parent.CombatService)
local MovementGuard = require(script.Parent.MovementGuard)

local MapsFolder = script.Parent.Parent.Maps
local Match = ModesConfig.Match

type Line = Types.PlayerLine & { joinedAt: number }

local MatchService = {
	phase = "Lobby" :: Types.Phase,
}

local mode = ModesConfig.Modes[Match.DefaultMode]
local phaseEndsAt = 0
local mapId = Match.Maps[1]
local mapDef: any = nil
local mapModel: Model? = nil
local teamScores: { [string]: number } = {}
local lines: { [Player]: Line } = {}
local votes: { [Player]: string } = {}
local deployed: { [Player]: boolean } = {}
local startLevels: { [Player]: number } = {}
local teamInstances: { [string]: Team } = {}
local stateDirty = true

local function now(): number
	return workspace:GetServerTimeNow()
end

local function teamOf(player: Player): string?
	local line = lines[player]
	return line and line.team
end

local function buildState(): Types.MatchStatePayload
	local teams = {}
	for _, t in Match.Teams do
		table.insert(teams, { id = t.id, displayName = t.displayName, score = teamScores[t.id] or 0, color = t.color })
	end
	local players = {}
	for _, player in Players:GetPlayers() do
		-- Everyone on the server is listed; players not yet in the match get an empty line.
		local line = lines[player] or { userId = player.UserId, name = player.DisplayName, team = nil, kills = 0, deaths = 0, assists = 0, score = 0 }
		do
			local profile = DataService.getProfile(player)
			table.insert(players, {
				level = if profile then profile.account.level else nil,
				prestige = if profile then profile.account.prestige else nil,
				userId = line.userId,
				name = line.name,
				team = line.team,
				kills = line.kills,
				deaths = line.deaths,
				assists = line.assists,
				score = line.score,
			})
		end
	end
	table.sort(players, function(a, b)
		return a.score > b.score
	end)
	local voteCounts = {}
	for _, id in Match.Maps do
		voteCounts[id] = 0
	end
	for _, id in votes do
		voteCounts[id] = (voteCounts[id] or 0) + 1
	end
	local inMatch = {}
	for player in deployed do
		table.insert(inMatch, player.UserId)
	end
	return {
		phase = MatchService.phase,
		modeId = mode.id,
		modeName = mode.displayName,
		mapId = mapId,
		mapName = if mapDef then mapDef.displayName else mapId,
		phaseEndsAt = phaseEndsAt,
		scoreLimit = mode.scoreLimit,
		teams = teams,
		players = players,
		votes = voteCounts,
		inMatch = inMatch,
	}
end

local function broadcast()
	stateDirty = false
	Net.event("MatchState"):FireAllClients(buildState())
end

local function setPhase(phase: Types.Phase, endsAt: number)
	MatchService.phase = phase
	phaseEndsAt = endsAt
	print(("[MatchService] phase -> %s"):format(phase))
	broadcast()
end

local function ensureLine(player: Player): Line
	local line = lines[player]
	if not line then
		line = { userId = player.UserId, name = player.DisplayName, team = nil, kills = 0, deaths = 0, assists = 0, score = 0, joinedAt = now() }
		lines[player] = line
	end
	return line
end

local function applyLighting(def: any)
	if def.lighting then
		for key, value in def.lighting do
			local ok, err = pcall(function()
				(Lighting :: any)[key] = value
			end)
			if not ok then
				warn("[MatchService] bad lighting property " .. tostring(key) .. ": " .. tostring(err))
			end
		end
	end
	local existing = Lighting:FindFirstChildOfClass("Atmosphere")
	if existing then
		existing:Destroy()
	end
	if def.atmosphere then
		local atmosphere = Instance.new("Atmosphere")
		for key, value in def.atmosphere do
			pcall(function()
				(atmosphere :: any)[key] = value
			end)
		end
		atmosphere.Parent = Lighting
	end
end

local function loadMap(id: string)
	local module = MapsFolder:FindFirstChild(id)
	if not module then
		warn("[MatchService] unknown map " .. id .. "; falling back to " .. Match.Maps[1])
		id = Match.Maps[1]
		module = MapsFolder:FindFirstChild(id)
	end
	if mapModel then
		mapModel:Destroy()
		mapModel = nil
	end
	local def = require(module :: ModuleScript) :: any
	local model = def.build()
	model.Name = "Map"
	model.Parent = workspace
	mapModel = model
	mapDef = def
	mapId = id
	CombatService.killY = model:GetAttribute("KillY") or -200
	applyLighting(def)
	stateDirty = true
end

local function spawnPoints(team: string?): { BasePart }
	local list = {}
	local folder = mapModel and mapModel:FindFirstChild("Spawns")
	if not folder then
		return list
	end
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") then
			if (mode.teams and p:GetAttribute("Team") == team) or (not mode.teams and p:GetAttribute("FFA")) then
				table.insert(list, p)
			end
		end
	end
	return list
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

local function chooseSpawn(player: Player): CFrame
	local team = teamOf(player)
	local candidates = spawnPoints(team)
	if #candidates == 0 then
		warn("[MatchService] no spawns for team " .. tostring(team))
		return CFrame.new(0, 20, 0)
	end
	local enemies, friends, enemyHeads = {}, {}, {}
	local characters: { Instance } = {}
	for other in deployed do
		local character = other.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if other ~= player and head and CombatService.isAlive(other) then
			table.insert(characters, character :: Model)
			if mode.teams and teamOf(other) == team then
				table.insert(friends, head.Position)
			else
				table.insert(enemies, head.Position)
				table.insert(enemyHeads, head)
			end
		end
	end
	losParams.FilterDescendantsInstances = characters
	local positions = {}
	for i, p in candidates do
		positions[i] = p.Position
	end
	local index = TeamsLogic.chooseSpawn(positions, enemies, friends, function(i)
		local target = positions[i] + Vector3.new(0, 3, 0)
		for _, head in enemyHeads do
			local offset = target - head.Position
			if offset.Magnitude < 180 and not workspace:Raycast(head.Position, offset, losParams) then
				return true
			end
		end
		return false
	end)
	local chosen = candidates[index or math.random(1, #candidates)]
	return chosen.CFrame
end

local function setupTeams()
	for _, t in Match.Teams do
		local team = Teams:FindFirstChild(t.displayName) :: Team?
		if not team then
			local newTeam = Instance.new("Team")
			newTeam.Name = t.displayName
			newTeam.TeamColor = BrickColor.new(t.color)
			newTeam.AutoAssignable = false
			newTeam.Parent = Teams
			team = newTeam
		end
		teamInstances[t.id] = team :: Team
	end
end

local function assignTeam(player: Player)
	local line = ensureLine(player)
	if not mode.teams then
		line.team = nil
		return
	end
	if line.team then
		return
	end
	local counts = {}
	for p, l in lines do
		if p ~= player and l.team and p.Parent then
			counts[l.team] = (counts[l.team] or 0) + 1
		end
	end
	local ids = {}
	for _, t in Match.Teams do
		table.insert(ids, t.id)
	end
	line.team = TeamsLogic.pick(ids, counts, teamScores)
	player.Team = teamInstances[line.team :: any]
	player:SetAttribute("Team", line.team)
end

local function spawnPlayer(player: Player)
	if not player.Parent or MatchService.phase == "Lobby" or MatchService.phase == "Results" then
		return
	end
	assignTeam(player)
	deployed[player] = true
	if not startLevels[player] then
		local profile = DataService.getProfile(player)
		startLevels[player] = if profile then profile.account.level else 1
	end
	player:LoadCharacter()
	local character = player.Character
	if not character or not player.Parent then
		return
	end
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameOcclusion = Enum.NameOcclusion.OccludeAll
	humanoid.WalkSpeed = Match.BaseWalkSpeed
	character:PivotTo(chooseSpawn(player) + Vector3.new(0, 3, 0))
	MovementGuard.reset(player)
	local frozen = MatchService.phase == "Countdown"
	character:SetAttribute("Frozen", frozen)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and frozen then
		root.Anchored = true
	end
	CombatService.onSpawned(player, character, ProgressionService.currentLoadout(player), mode.spawnProtection)
	stateDirty = true
end

local function onKilled(info: CombatService.KillInfo)
	local victimLine = lines[info.victim]
	if victimLine then
		victimLine.deaths += 1
	end
	ProgressionService.onDeath(info.victim)
	local killer = info.killer
	if MatchService.phase == "Playing" and killer and killer ~= info.victim and lines[killer] then
		local kl = lines[killer]
		kl.kills += 1
		kl.score += MatchRules.POINTS.Kill + (if info.headshot then MatchRules.POINTS.Headshot else 0)
		if kl.team then
			teamScores[kl.team] = (teamScores[kl.team] or 0) + mode.pointsPerKill
		end
		ProgressionService.onKill(killer, info.victim, info.weaponId, info.headshot)
		for _, assister in info.assisters do
			local al = lines[assister]
			if al then
				al.assists += 1
				al.score += MatchRules.POINTS.Assist
				ProgressionService.onAssist(assister, nil)
			end
		end
	end
	Net.event("KillFeed"):FireAllClients({
		killer = if killer and killer ~= info.victim then killer.DisplayName else nil,
		killerTeam = if killer then teamOf(killer) else nil,
		victim = info.victim.DisplayName,
		victimTeam = teamOf(info.victim),
		weaponId = info.weaponId,
		headshot = info.headshot,
		killerUserId = if killer and killer ~= info.victim then killer.UserId else nil,
		victimUserId = info.victim.UserId,
	})
	stateDirty = true

	local victim = info.victim
	task.delay(mode.respawnDelay, function()
		if MatchService.phase == "Playing" and deployed[victim] and victim.Parent and not CombatService.isAlive(victim) then
			spawnPlayer(victim)
		end
	end)
end

local function eligiblePlayers(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if DataService.getProfile(p) then
			table.insert(list, p)
		end
	end
	return list
end

local function tallyVotes(): string
	local counts = {}
	for _, id in votes do
		counts[id] = (counts[id] or 0) + 1
	end
	local best, bestCount = mapId, -1
	for _, id in Match.Maps do
		local c = counts[id] or 0
		if c > bestCount then
			best, bestCount = id, c
		end
	end
	return best
end

local function waitPhase(condition: (() -> boolean)?)
	while true do
		if stateDirty then
			broadcast()
		end
		if phaseEndsAt > 0 and now() >= phaseEndsAt then
			return
		end
		if condition and condition() then
			return
		end
		task.wait(0.2)
	end
end

local function runMatch()
	-- Lobby: wait for enough players, then count down with map voting.
	setPhase("Lobby", 0)
	waitPhase(function()
		return #eligiblePlayers() >= mode.minPlayersToStart
	end)
	setPhase("Lobby", now() + Match.LobbyCountdown)
	local aborted = false
	waitPhase(function()
		if #eligiblePlayers() < mode.minPlayersToStart then
			aborted = true
			return true
		end
		return false
	end)
	if aborted then
		return
	end

	local chosen = tallyVotes()
	if chosen ~= mapId or not mapModel then
		loadMap(chosen)
	end
	table.clear(votes)
	table.clear(teamScores)
	table.clear(startLevels)
	for _, t in Match.Teams do
		teamScores[t.id] = 0
	end
	for player in lines do
		lines[player] = nil
	end
	ProgressionService.beginMatch()

	-- Countdown: everyone present is deployed, frozen in place.
	setPhase("Countdown", now() + Match.PreMatchCountdown)
	local roster = eligiblePlayers()
	for _, player in roster do
		assignTeam(player)
	end
	for _, player in roster do
		task.spawn(spawnPlayer, player)
	end
	waitPhase()

	-- Playing
	local matchStart = now()
	setPhase("Playing", now() + mode.timeLimit)
	for player in deployed do
		local character = player.Character
		if character then
			character:SetAttribute("Frozen", false)
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = false
			end
		end
	end
	waitPhase(function()
		-- QA hook, Studio only: set workspace attribute QA_EndMatch to end the match early.
		if RunService:IsStudio() and workspace:GetAttribute("QA_EndMatch") then
			workspace:SetAttribute("QA_EndMatch", nil)
			return true
		end
		return MatchRules.isOver(mode.scoreLimit, teamScores, now(), phaseEndsAt)
	end)

	-- Results
	local winner = MatchRules.winner(teamScores)
	setPhase("Results", now() + Match.ResultsDuration)
	local state = buildState()
	for player, line in lines do
		if player.Parent and deployed[player] then
			local seconds = now() - math.max(matchStart, line.joinedAt)
			local won = winner ~= nil and line.team == winner
			local xp = ProgressionService.endMatch(player, seconds, won, true)
			local summary = ProgressionService.summary(player)
			if xp and summary then
				Net.event("MatchResults"):FireClient(player, {
					winnerTeam = winner,
					teams = state.teams,
					players = state.players,
					xp = xp,
					account = { level = summary.account.level, xp = summary.account.xp, needed = summary.account.needed },
					startLevel = startLevels[player] or summary.account.level,
				})
			end
		end
	end
	waitPhase()

	for player in deployed do
		CombatService.despawn(player)
		local p: any = player
		p.Team = nil
		player:SetAttribute("Team", nil)
	end
	table.clear(deployed)
	-- Back to the lobby with a clean board: no stale teams or scores from the finished match.
	table.clear(lines)
	for id in teamScores do
		teamScores[id] = 0
	end
	stateDirty = true
end

function MatchService.canFight(player: Player): boolean
	return MatchService.phase == "Playing" and deployed[player] == true
end

function MatchService.init()
	setupTeams()
	CombatService.rules.canFight = MatchService.canFight
	CombatService.rules.isEnemy = function(a: Player, b: Player): boolean
		if a == b then
			return false
		end
		if not mode.teams then
			return true
		end
		local ta, tb = teamOf(a), teamOf(b)
		return ta ~= nil and tb ~= nil and ta ~= tb
	end
	CombatService.Killed:Connect(onKilled)

	Net.event("VoteMap").OnServerEvent:Connect(function(player, id)
		if MatchService.phase ~= "Lobby" or type(id) ~= "string" or not table.find(Match.Maps, id) then
			return
		end
		votes[player] = id
		stateDirty = true
	end)

	Net.event("RequestDeploy").OnServerEvent:Connect(function(player)
		if deployed[player] or not DataService.getProfile(player) then
			return
		end
		if MatchService.phase == "Playing" or MatchService.phase == "Countdown" then
			ensureLine(player)
			task.spawn(spawnPlayer, player)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		stateDirty = true
		-- Send current state as soon as the client can listen.
		task.delay(1, function()
			if player.Parent then
				Net.event("MatchState"):FireClient(player, buildState())
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lines[player] = nil
		votes[player] = nil
		deployed[player] = nil
		startLevels[player] = nil
		stateDirty = true
	end)

	local effects = workspace:FindFirstChild("Effects") or Instance.new("Folder")
	effects.Name = "Effects"
	effects.Parent = workspace
end

function MatchService.start()
	loadMap(mapId)
	while true do
		local ok, err = pcall(runMatch :: any)
		if not ok then
			warn("[MatchService] match loop error: " .. tostring(err))
			for player in deployed do
				pcall(CombatService.despawn, player)
			end
			table.clear(deployed)
			task.wait(2)
		end
	end
end

return MatchService
