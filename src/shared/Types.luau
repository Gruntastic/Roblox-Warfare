--!strict
-- Shared payload types for the Net contract.
export type Slot = "Primary" | "Secondary"
export type Phase = "Lobby" | "Countdown" | "Playing" | "Results"

export type TeamScore = { id: string, displayName: string, score: number, color: Color3 }

export type PlayerLine = {
	userId: number,
	name: string,
	team: string?,
	kills: number,
	deaths: number,
	assists: number,
	score: number,
	level: number?,
	prestige: number?,
}

export type MatchStatePayload = {
	phase: Phase,
	modeId: string,
	modeName: string,
	mapId: string,
	mapName: string,
	phaseEndsAt: number, -- workspace:GetServerTimeNow() based; 0 = no timer
	scoreLimit: number,
	teams: { TeamScore },
	players: { PlayerLine },
	votes: { [string]: number },
	inMatch: { number }, -- userIds currently deployed
}

export type KillFeedPayload = {
	killer: string?,
	killerTeam: string?,
	victim: string,
	victimTeam: string?,
	weaponId: string?,
	headshot: boolean,
	killerUserId: number?,
	victimUserId: number,
}

export type HitConfirmPayload = { damage: number, headshot: boolean, killed: boolean }
export type DamageTakenPayload = { amount: number, fromPosition: Vector3?, health: number }

export type LevelProgress = { level: number, xp: number, needed: number }
export type XPGainPayload = {
	amount: number,
	reason: string,
	account: LevelProgress,
	weaponId: string?,
	weapon: LevelProgress?,
	leveledUp: boolean,
	weaponLeveledUp: boolean,
}

export type Loadout = { name: string, primary: string, secondary: string }

export type ProfileSummary = {
	userId: number,
	account: { level: number, xp: number, needed: number, prestige: number },
	weapons: { [string]: { level: number, xp: number, needed: number, kills: number } },
	stats: { kills: number, deaths: number, matches: number, wins: number },
	loadouts: { Loadout },
	selectedLoadout: number,
	unlockedWeapons: { string },
	temporary: boolean, -- true when DataStores are unavailable (progress will NOT persist)
}

export type MatchResultsPayload = {
	winnerTeam: string?,
	teams: { TeamScore },
	players: { PlayerLine },
	xp: { total: number, breakdown: { { reason: string, amount: number } } }, -- per-recipient
	account: LevelProgress,
	startLevel: number,
}

return nil
