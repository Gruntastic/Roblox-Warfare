--!strict
-- Interface between MatchService and the objective mode modules in this folder.
-- MatchService owns players, teams, spawning, scores and XP; a mode only reads the world through
-- the Context it is given and reports results back through it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

export type KillInfo = {
	victim: Player,
	killer: Player?,
	weaponId: string?,
	headshot: boolean,
	assisters: { Player },
	position: Vector3?, -- victim's root position at death
}

export type Context = {
	mode: any, -- ModesConfig ModeDef
	map: Model,
	now: () -> number, -- server time (workspace:GetServerTimeNow)
	teams: { string }, -- team ids in config order
	teamOf: (Player) -> string?,
	participants: () -> { Player }, -- players deployed in this match (alive or dead)
	isAlive: (Player) -> boolean,
	root: (Player) -> BasePart?, -- HumanoidRootPart of a living participant
	addTeamScore: (team: string, amount: number) -> (),
	setTeamScore: (team: string, value: number) -> (),
	-- Scoreboard points plus objective XP (`xp` goes through ProgressionService.onObjective).
	award: (player: Player, points: number, reason: string, xp: number) -> (),
	event: (kind: string, data: { [string]: any }) -> (), -- ObjectiveEvent to everyone
	changed: () -> (), -- the ObjectivePayload must be re-sent
	-- Round control (S&D)
	respawnAll: () -> (), -- respawn every participant, frozen, at their side's spawns
	setFrozen: (frozen: boolean) -> (),
	setClock: (endsAt: number) -> (), -- the HUD match timer (0 hides it)
	-- Phase 5: multiplier on a player's S&D plant / defuse time (Bomb Tech perk; 1 = normal)
	objectiveTimeMultiplier: (player: Player) -> number,
}

export type Impl = {
	kind: "None" | "Domination" | "Hardpoint" | "SnD" | "KillConfirmed",
	-- Called once the map is loaded and teams are assigned, before the frozen countdown.
	prepare: (ctx: Context) -> (),
	-- Called when the match goes live (players unfrozen).
	start: (ctx: Context) -> (),
	-- Called about 10 times a second while Playing.
	step: (ctx: Context, dt: number) -> (),
	payload: (ctx: Context) -> Types.ObjectivePayload,
	onKilled: ((ctx: Context, info: KillInfo) -> ())?,
	onPlayerRemoving: ((ctx: Context, player: Player) -> ())?,
	onInteract: ((ctx: Context, player: Player, holding: boolean) -> ())?,
	-- Overrides the shared score / time limit check.
	isOver: ((ctx: Context) -> boolean)?,
	-- Overrides the shared winner (highest team score).
	winner: ((ctx: Context) -> string?)?,
	-- false blocks the automatic respawn after a death (S&D mid-round).
	allowRespawn: ((ctx: Context, player: Player) -> boolean)?,
	-- Which team's spawn set a team uses ("Sable" | "Talon"); S&D swaps sides.
	spawnTag: ((ctx: Context, team: string) -> string)?,
	-- Called when the match ends or errors; must remove anything the mode put in the world.
	stop: (ctx: Context) -> (),
}

return nil
