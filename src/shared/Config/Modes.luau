--!strict
export type ModeDef = {
	id: string,
	displayName: string,
	teams: boolean,
	maxPlayers: number,
	scoreLimit: number,
	timeLimit: number, -- seconds
	pointsPerKill: number,
	respawnDelay: number,
	spawnProtection: number,
	minPlayersToStart: number,
	-- objective tuning (only the fields a mode uses are set)
	objective: ("None" | "Domination" | "Hardpoint" | "SnD" | "KillConfirmed")?,
	captureTime: number?, -- Domination: seconds for one player to capture a neutral flag
	scoreInterval: number?, -- Domination: seconds between points for each held flag
	hardpointDuration: number?, -- Hardpoint: seconds each zone stays live
	hardpointFirstDelay: number?, -- Hardpoint: seconds before the first zone goes live
	roundsToWin: number?, -- S&D
	roundTime: number?, -- S&D: seconds per round before defenders win on time
	bombTimer: number?, -- S&D: seconds from plant to detonation
	plantTime: number?, -- S&D: seconds to plant (hold Interact)
	defuseTime: number?, -- S&D: seconds to defuse (hold Interact)
	roundPause: number?, -- S&D: seconds of post-round pause before the next round's countdown
	swapSidesAfter: number?, -- S&D: teams swap attack / defence after this many rounds
	tagLifetime: number?, -- Kill Confirmed: seconds a dropped tag stays before it expires
}

local Modes: { [string]: ModeDef } = {
	TDM = {
		id = "TDM",
		displayName = "Team Deathmatch",
		teams = true,
		maxPlayers = 12,
		scoreLimit = 75,
		timeLimit = 600,
		pointsPerKill = 1,
		respawnDelay = 3,
		spawnProtection = 2,
		minPlayersToStart = 1, -- 1 lets a solo player test; raise for live servers
		objective = "None",
	},
	FFA = {
		id = "FFA",
		displayName = "Free-for-All",
		teams = false,
		maxPlayers = 8,
		scoreLimit = 30, -- kills by one player
		timeLimit = 600,
		pointsPerKill = 1,
		respawnDelay = 2.5,
		spawnProtection = 2,
		minPlayersToStart = 1,
		objective = "None",
	},
	DOM = {
		id = "DOM",
		displayName = "Domination",
		teams = true,
		maxPlayers = 12,
		scoreLimit = 200,
		timeLimit = 600,
		pointsPerKill = 0,
		respawnDelay = 4,
		spawnProtection = 2,
		minPlayersToStart = 1,
		objective = "Domination",
		captureTime = 10,
		scoreInterval = 5,
	},
	SND = {
		id = "SND",
		displayName = "Search and Destroy",
		teams = true,
		maxPlayers = 12,
		scoreLimit = 4, -- round wins
		timeLimit = 0, -- no match clock; each round has its own
		pointsPerKill = 0,
		respawnDelay = 0, -- no respawns during a round
		spawnProtection = 0,
		minPlayersToStart = 1,
		objective = "SnD",
		roundsToWin = 4,
		roundTime = 150,
		bombTimer = 40,
		plantTime = 5,
		defuseTime = 7,
		roundPause = 6,
		swapSidesAfter = 3,
	},
	HP = {
		id = "HP",
		displayName = "Hardpoint",
		teams = true,
		maxPlayers = 12,
		scoreLimit = 250,
		timeLimit = 600,
		pointsPerKill = 0,
		respawnDelay = 4,
		spawnProtection = 2,
		minPlayersToStart = 1,
		objective = "Hardpoint",
		hardpointDuration = 60,
		hardpointFirstDelay = 10,
	},
	KC = {
		id = "KC",
		displayName = "Kill Confirmed",
		teams = true,
		maxPlayers = 12,
		scoreLimit = 65,
		timeLimit = 600,
		pointsPerKill = 0, -- points come from collecting enemy tags
		respawnDelay = 3,
		spawnProtection = 2,
		minPlayersToStart = 1,
		objective = "KillConfirmed",
		tagLifetime = 30,
	},
}

local Match = {
	LobbyCountdown = 20, -- seconds of lobby / loadout selection once enough players are present
	PreMatchCountdown = 5, -- frozen countdown after spawning in
	ResultsDuration = 12,
	Teams = {
		{ id = "Sable", displayName = "Task Force Sable", color = Color3.fromRGB(70, 140, 230) },
		{ id = "Talon", displayName = "Red Talon", color = Color3.fromRGB(220, 70, 60) },
	},
	-- Every map supports every mode (see docs/MAP_CONTRACT.md). The lobby offers VoteOptions random
	-- map + mode pairings from these lists, never repeating the map that was just played.
	Maps = { "DustlineTerminal", "FrostRelay", "IronBorough", "RedMesa", "Breakwater", "AshwoodEstate" },
	ModeRotation = { "TDM", "DOM", "KC", "HP", "FFA", "SND" },
	VoteOptions = 3,
	DefaultMode = "TDM",
	MaxHealth = 100,
	HealthRegenDelay = 4,
	HealthRegenPerSecond = 25,
	BaseWalkSpeed = 16,
	SprintSpeed = 24,
	CrouchSpeed = 8,
}

return { Modes = Modes, Match = Match }
