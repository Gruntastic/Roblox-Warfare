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
	Maps = { "DustlineTerminal" },
	DefaultMode = "TDM",
	MaxHealth = 100,
	HealthRegenDelay = 4,
	HealthRegenPerSecond = 25,
	BaseWalkSpeed = 16,
	SprintSpeed = 24,
	CrouchSpeed = 8,
}

return { Modes = Modes, Match = Match }
