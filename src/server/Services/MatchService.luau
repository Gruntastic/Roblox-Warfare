--!strict
-- Match lifecycle for a single server: lobby -> countdown -> playing -> results -> lobby.
-- Owns teams, spawns, map loading, scoring and the authoritative MatchState broadcast. Objective
-- rules live in ../Modes (one module per objective mode); this service hosts them through a
-- ModeTypes.Context.
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
local KillstreakService = require(script.Parent.KillstreakService)
local MovementGuard = require(script.Parent.MovementGuard)
local ModeTypes = require(script.Parent.Parent.Modes.ModeTypes)
local Domination = require(script.Parent.Parent.Modes.Domination)
local Hardpoint = require(script.Parent.Parent.Modes.Hardpoint)
local KillConfirmed = require(script.Parent.Parent.Modes.KillConfirmed)
local SearchAndDestroy = require(script.Parent.Parent.Modes.SearchAndDestroy)

local MapsFolder = script.Parent.Parent.Maps
local MODE_FACTORIES: { [string]: () -> ModeTypes.Impl } = {
	Domination = Domination.new,
	Hardpoint = Hardpoint.new,
	KillConfirmed = KillConfirmed.new,
	SnD = SearchAndDestroy.new,
}
local STEP_INTERVAL = 0.1 -- objective step rate while Playing
local OBJECTIVE_SEND_INTERVAL = 0.2 -- ObjectiveState broadcast cap
local Match = ModesConfig.Match

type Line = Types.PlayerLine & { joinedAt: number }

local MatchService = {
	phase = "Lobby" :: Types.Phase,
}

local mode = ModesConfig.Modes[Match.DefaultMode]
local impl: ModeTypes.Impl? = nil -- objective rules for the current match (nil for TDM / FFA)
local ctx: ModeTypes.Context
local phaseEndsAt = 0
local mapId = Match.Maps[1]
local mapDef: any = nil
local mapModel: Model? = nil
local teamScores: { [string]: number } = {}
local lines: { [Player]: Line } = {}
local votes: { [Player]: string } = {} -- player -> VoteOption id
local options: { Types.VoteOption } = {}
local roundFrozen = false -- S&D pre-round: (re)spawned characters stay frozen
local objectiveDirty = false
local lastObjectiveSent = 0
local lastInteract: { [Player]: number } = {}
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
	if mode.teams then
		for _, t in Match.Teams do
			table.insert(teams, { id = t.id, displayName = t.displayName, score = teamScores[t.id] or 0, color = t.color })
		end
	end
	local players = {}
	for _, player in Players:GetPlayers() do
		-- Everyone on the server is listed; players not yet in the match get an empty line.
		local line = lines[player] or { userId = player.UserId, name = player.DisplayName, team = nil, kills = 0, deaths = 0, assists = 0, score = 0 }
		do
			local profile = DataService.getProfile(player)
			local cosmetics = if profile then ProgressionService.cosmeticsFor(player) else nil
			table.insert(players, {
				level = if profile then profile.account.level else nil,
				prestige = if profile then profile.account.prestige else nil,
				title = if cosmetics then cosmetics.title else nil,
				emblem = if cosmetics then cosmetics.emblem else nil,
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
		if not mode.teams and a.kills ~= b.kills then
			return a.kills > b.kills -- FFA is a kill race
		end
		return a.score > b.score
	end)
	local voteCounts = {}
	for _, o in options do
		voteCounts[o.id] = 0
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
		teamMode = mode.teams,
		mapId = mapId,
		mapName = if mapDef then mapDef.displayName else mapId,
		phaseEndsAt = phaseEndsAt,
		scoreLimit = mode.scoreLimit,
		teams = teams,
		players = players,
		options = if MatchService.phase == "Lobby" then options else {},
		votes = voteCounts,
		inMatch = inMatch,
	}
end

local function broadcast()
	stateDirty = false
	Net.event("MatchState"):FireAllClients(buildState())
end

-- Runs a mode callback; a broken mode logs instead of killing the match loop.
local function safely(what: string, fn: (...any) -> ...any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(("[MatchService] mode %s error: %s"):format(what, tostring(err)))
	end
end

local function objectivePayload(): Types.ObjectivePayload
	if impl then
		return impl.payload(ctx)
	end
	return { kind = "None", zones = {} }
end

local function sendObjective()
	objectiveDirty = false
	lastObjectiveSent = os.clock()
	Net.event("ObjectiveState"):FireAllClients(objectivePayload())
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
	-- S&D swaps which base each team uses
	local tag = if team and impl and impl.spawnTag then impl.spawnTag(ctx, team) else team
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") then
			if (mode.teams and p:GetAttribute("Team") == tag) or (not mode.teams and p:GetAttribute("FFA")) then
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
	local frozen = MatchService.phase == "Countdown" or roundFrozen
	character:SetAttribute("Frozen", frozen)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and frozen then
		root.Anchored = true
	end
	local loadout = ProgressionService.currentLoadout(player)
	CombatService.onSpawned(player, character, loadout, mode.spawnProtection)
	KillstreakService.onSpawned(player, loadout)
	stateDirty = true
	objectiveDirty = true
end

local function setFrozen(frozen: boolean)
	roundFrozen = frozen
	for player in deployed do
		local character = player.Character
		if character then
			character:SetAttribute("Frozen", frozen)
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.Anchored = frozen
			end
		end
	end
end

local function onKilled(info: CombatService.KillInfo)
	local victimCharacter = info.victim.Character
	local victimRoot = victimCharacter and victimCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
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
		if kl.team and mode.pointsPerKill > 0 then
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
	if impl and impl.onKilled and MatchService.phase == "Playing" then
		safely("onKilled", impl.onKilled, ctx, {
			victim = info.victim,
			killer = info.killer,
			weaponId = info.weaponId,
			headshot = info.headshot,
			assisters = info.assisters,
			position = if victimRoot then victimRoot.Position else nil,
		})
	end

	local victim = info.victim
	task.delay(mode.respawnDelay, function()
		if MatchService.phase ~= "Playing" or not deployed[victim] or not victim.Parent or CombatService.isAlive(victim) then
			return
		end
		if impl and impl.allowRespawn and not impl.allowRespawn(ctx, victim) then
			return
		end
		spawnPlayer(victim)
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

-- Maps that actually exist on this server, in config order.
local function availableMaps(): { string }
	local list = {}
	for _, id in Match.Maps do
		if MapsFolder:FindFirstChild(id) then
			table.insert(list, id)
		end
	end
	return list
end

local function mapDisplayName(id: string): string
	local module = MapsFolder:FindFirstChild(id)
	if module and module:IsA("ModuleScript") then
		local ok, def = pcall(require, module)
		if ok and type(def) == "table" and type((def :: any).displayName) == "string" then
			return (def :: any).displayName
		end
	end
	return id
end

-- Fresh lobby vote: distinct maps (the one just played last, when there is a choice) paired with
-- modes taken from the rotation, starting after the mode just played.
local function makeOptions()
	table.clear(options)
	table.clear(votes)
	local maps = availableMaps()
	for i = #maps, 2, -1 do
		local j = math.random(1, i)
		maps[i], maps[j] = maps[j], maps[i]
	end
	if #maps > 1 then
		local at = table.find(maps, mapId)
		if at then
			table.remove(maps, at)
			table.insert(maps, mapId)
		end
	end
	local rotation = Match.ModeRotation
	local start = (table.find(rotation, mode.id) or 0) % #rotation
	for i = 1, math.min(Match.VoteOptions, #maps) do
		local modeId = rotation[(start + i - 1) % #rotation + 1]
		local m = ModesConfig.Modes[modeId]
		table.insert(options, {
			id = tostring(i),
			mapId = maps[i],
			mapName = mapDisplayName(maps[i]),
			modeId = modeId,
			modeName = if m then m.displayName else modeId,
		})
	end
	stateDirty = true
end

-- The most voted option; ties go to the earliest option.
local function tallyVotes(): Types.VoteOption?
	local counts = {}
	for _, id in votes do
		counts[id] = (counts[id] or 0) + 1
	end
	local best, bestCount = nil, -1
	for _, o in options do
		local c = counts[o.id] or 0
		if c > bestCount then
			best, bestCount = o, c
		end
	end
	return best
end

local function participants(): { Player }
	local list = {}
	for player in deployed do
		if player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

local function award(player: Player, points: number, reason: string, xp: number)
	local line = lines[player]
	if line and points > 0 then
		line.score += points
		stateDirty = true
	end
	if xp > 0 then
		ProgressionService.onObjective(player, reason, xp)
	end
end

local function respawnAll()
	for _, player in participants() do
		CombatService.despawn(player)
		task.spawn(spawnPlayer, player)
	end
end

local teamIds = {}
for _, t in Match.Teams do
	table.insert(teamIds, t.id)
end

ctx = {
	mode = mode,
	map = nil :: any,
	now = now,
	teams = teamIds,
	teamOf = teamOf,
	participants = participants,
	isAlive = function(player: Player): boolean
		return CombatService.isAlive(player)
	end,
	root = function(player: Player): BasePart?
		if not CombatService.isAlive(player) then
			return nil
		end
		local character = player.Character
		return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	end,
	addTeamScore = function(team: string, amount: number)
		teamScores[team] = (teamScores[team] or 0) + amount
		stateDirty = true
	end,
	setTeamScore = function(team: string, value: number)
		teamScores[team] = value
		stateDirty = true
	end,
	award = award,
	event = function(kind: string, data: { [string]: any })
		Net.event("ObjectiveEvent"):FireAllClients(kind, data)
	end,
	changed = function()
		objectiveDirty = true
	end,
	respawnAll = respawnAll,
	setFrozen = setFrozen,
	setClock = function(endsAt: number)
		phaseEndsAt = endsAt
		stateDirty = true
	end,
	objectiveTimeMultiplier = function(player: Player): number
		local perks = CombatService.perksOf(player)
		return if perks then math.clamp(perks.objectiveTime, 0.1, 1) else 1
	end,
}

local function stopMode()
	if impl then
		safely("stop", impl.stop, ctx)
		impl = nil
	end
	roundFrozen = false
	objectiveDirty = true
end

-- FFA kills per userId, for the winner.
local function ffaKills(): { [number]: number }
	local kills = {}
	for _, line in lines do
		kills[line.userId] = line.kills
	end
	return kills
end

local function matchOver(): boolean
	if impl and impl.isOver then
		return impl.isOver(ctx)
	end
	if not mode.teams then
		for _, line in lines do
			if line.kills >= mode.scoreLimit then
				return true
			end
		end
		return mode.timeLimit > 0 and phaseEndsAt > 0 and now() >= phaseEndsAt
	end
	return (MatchRules.isOver(mode.scoreLimit, teamScores, now(), phaseEndsAt))
end

local lastStep = os.clock()

local function waitPhase(condition: (() -> boolean)?)
	lastStep = os.clock()
	while true do
		if MatchService.phase == "Playing" and impl then
			local t = os.clock()
			safely("step", impl.step, ctx, math.min(t - lastStep, 0.5))
			lastStep = t
		end
		if stateDirty then
			broadcast()
		end
		if objectiveDirty and os.clock() - lastObjectiveSent >= OBJECTIVE_SEND_INTERVAL then
			sendObjective()
		end
		if phaseEndsAt > 0 and now() >= phaseEndsAt and not (MatchService.phase == "Playing" and impl and impl.isOver) then
			return
		end
		if condition and condition() then
			return
		end
		task.wait(STEP_INTERVAL)
	end
end

local function runMatch()
	-- Lobby: wait for enough players, then count down with map + mode voting.
	makeOptions()
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
		-- QA hook, Studio only: while workspace attribute QA_HoldLobby is set, the countdown stalls.
		if RunService:IsStudio() and workspace:GetAttribute("QA_HoldLobby") and phaseEndsAt - now() < 10 then
			phaseEndsAt = now() + Match.LobbyCountdown
			stateDirty = true
		end
		return false
	end)
	if aborted then
		return
	end

	local chosen = tallyVotes()
	-- QA hook, Studio only: workspace attributes QA_Mode / QA_Map force the next match.
	local forcedMode = if RunService:IsStudio() then workspace:GetAttribute("QA_Mode") else nil
	local forcedMap = if RunService:IsStudio() then workspace:GetAttribute("QA_Map") else nil
	local nextMode = if type(forcedMode) == "string" and ModesConfig.Modes[forcedMode] then forcedMode elseif chosen then chosen.modeId else mode.id
	local nextMap = if type(forcedMap) == "string" and MapsFolder:FindFirstChild(forcedMap) then forcedMap elseif chosen then chosen.mapId else mapId
	mode = ModesConfig.Modes[nextMode]
	ctx.mode = mode
	if nextMap ~= mapId or not mapModel then
		loadMap(nextMap)
	end
	table.clear(votes)
	table.clear(options)
	table.clear(teamScores)
	table.clear(startLevels)
	for _, t in Match.Teams do
		teamScores[t.id] = 0
	end
	for player in lines do
		lines[player] = nil
	end
	ProgressionService.beginMatch()
	KillstreakService.beginMatch(mapModel)

	-- Countdown: everyone present is deployed, frozen in place.
	local roster = eligiblePlayers()
	for _, player in roster do
		assignTeam(player)
	end
	local factory = MODE_FACTORIES[mode.objective or "None"]
	impl = if factory then factory() else nil
	ctx.map = mapModel :: Model
	if impl then
		impl.prepare(ctx)
	end
	objectiveDirty = true
	setPhase("Countdown", now() + Match.PreMatchCountdown)
	for _, player in roster do
		task.spawn(spawnPlayer, player)
	end
	waitPhase()

	-- Playing
	local matchStart = now()
	setPhase("Playing", if mode.timeLimit > 0 then now() + mode.timeLimit else 0)
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
	if impl then
		impl.start(ctx)
	end
	waitPhase(function()
		-- QA hook, Studio only: set workspace attribute QA_EndMatch to end the match early.
		if RunService:IsStudio() and workspace:GetAttribute("QA_EndMatch") then
			workspace:SetAttribute("QA_EndMatch", nil)
			return true
		end
		return matchOver()
	end)

	-- Results
	local winner: string? = nil
	local winnerUserId: number? = nil
	if not mode.teams then
		winnerUserId = MatchRules.ffaWinner(ffaKills())
	elseif impl and impl.winner then
		winner = impl.winner(ctx)
	else
		winner = MatchRules.winner(teamScores)
	end
	stopMode()
	KillstreakService.endMatch()
	sendObjective()
	setPhase("Results", now() + Match.ResultsDuration)
	local state = buildState()
	for player, line in lines do
		if player.Parent and deployed[player] then
			local seconds = now() - math.max(matchStart, line.joinedAt)
			local won = if mode.teams then winner ~= nil and line.team == winner else winnerUserId == player.UserId
			local xp = ProgressionService.endMatch(player, seconds, won, true)
			local summary = ProgressionService.summary(player)
			if xp and summary then
				Net.event("MatchResults"):FireClient(player, {
					winnerTeam = winner,
					winnerUserId = winnerUserId,
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
	KillstreakService.rules.teamOf = teamOf
	KillstreakService.rules.teamMode = function(): boolean
		return mode.teams
	end
	KillstreakService.rules.teams = teamIds
	KillstreakService.rules.canUse = MatchService.canFight

	Net.event("VoteMap").OnServerEvent:Connect(function(player, id)
		if MatchService.phase ~= "Lobby" or type(id) ~= "string" then
			return
		end
		for _, o in options do
			if o.id == id then
				votes[player] = id
				stateDirty = true
				return
			end
		end
	end)

	Net.event("Interact").OnServerEvent:Connect(function(player, holding)
		if type(holding) ~= "boolean" or not deployed[player] or MatchService.phase ~= "Playing" then
			return
		end
		-- presses are rate limited; releases always go through so an action can't get stuck
		local t = os.clock()
		if holding and t - (lastInteract[player] or 0) < 0.2 then
			return
		end
		lastInteract[player] = t
		if impl and impl.onInteract then
			safely("onInteract", impl.onInteract, ctx, player, holding)
		end
	end)

	Net.event("RequestDeploy").OnServerEvent:Connect(function(player)
		if deployed[player] or not DataService.getProfile(player) then
			return
		end
		if MatchService.phase == "Playing" or MatchService.phase == "Countdown" then
			ensureLine(player)
			if impl and impl.allowRespawn and MatchService.phase == "Playing" and not impl.allowRespawn(ctx, player) then
				-- S&D mid-round: join the match now, spawn at the next round
				assignTeam(player)
				deployed[player] = true
				stateDirty = true
				objectiveDirty = true
				return
			end
			task.spawn(spawnPlayer, player)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		stateDirty = true
		-- Send current state as soon as the client can listen.
		task.delay(1, function()
			if player.Parent then
				Net.event("MatchState"):FireClient(player, buildState())
				Net.event("ObjectiveState"):FireClient(player, objectivePayload())
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		if impl and impl.onPlayerRemoving then
			safely("onPlayerRemoving", impl.onPlayerRemoving, ctx, player)
		end
		lines[player] = nil
		votes[player] = nil
		deployed[player] = nil
		startLevels[player] = nil
		lastInteract[player] = nil
		stateDirty = true
		objectiveDirty = true
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
			stopMode()
			pcall(KillstreakService.endMatch)
			for player in deployed do
				pcall(CombatService.despawn, player)
			end
			table.clear(deployed)
			task.wait(2)
		end
	end
end

return MatchService
