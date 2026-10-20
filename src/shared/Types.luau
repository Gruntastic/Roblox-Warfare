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
	title: string?, -- Phase 5: equipped title id (Config/Cosmetics.titles)
	emblem: string?, -- Phase 5: equipped prestige emblem id, if any
}

-- One lobby vote option: a map + mode pairing. `votes` in MatchStatePayload is keyed by option id.
export type VoteOption = { id: string, mapId: string, mapName: string, modeId: string, modeName: string }

export type MatchStatePayload = {
	phase: Phase,
	modeId: string,
	modeName: string,
	teamMode: boolean, -- false for Free-for-All: `teams` is empty and players score individually
	mapId: string,
	mapName: string,
	phaseEndsAt: number, -- workspace:GetServerTimeNow() based; 0 = no timer
	scoreLimit: number, -- team score (team modes), player kills (FFA) or round wins (S&D)
	teams: { TeamScore },
	players: { PlayerLine },
	options: { VoteOption }, -- lobby vote options for the next match (empty outside the lobby)
	votes: { [string]: number }, -- option id -> vote count
	inMatch: { number }, -- userIds taking part in the match (alive or dead; S&D dead players stay listed)
}

-- Objective modes (Phase 4). Sent on `ObjectiveState` whenever it changes (at most ~5 per second),
-- and once to each player on join. kind = "None" for TDM / FFA.
export type ZoneState = {
	id: string, -- "A" | "B" | "C" for flags and bomb sites; "HP1".."HPn" for hardpoints
	label: string, -- marker text: "A", "B", "C"; hardpoints use "" (the HUD shows a generic icon)
	position: Vector3, -- zone centre at floor level
	size: Vector3, -- zone box size in the zone's own axes (rotated by `yaw` about +Y)
	yaw: number, -- radians
	owner: string?, -- Domination: team holding the flag. Hardpoint: team alone in the live zone. nil = neutral
	capturingTeam: string?, -- team the progress is moving towards
	progress: number, -- 0..1 towards capturingTeam
	contested: boolean, -- both teams present
	active: boolean, -- Hardpoint: true only for the live zone. Domination / S&D: always true
}

export type BombState = {
	state: "None" | "Carried" | "Dropped" | "Planted" | "Defused" | "Detonated",
	carrierUserId: number?, -- Carried
	position: Vector3?, -- Dropped / Planted
	site: string?, -- Planted / Defused / Detonated: "A" | "B"
	explodesAt: number?, -- Planted: server time of detonation
	actionUserId: number?, -- someone is planting / defusing right now
	actionKind: ("Plant" | "Defuse")?,
	actionEndsAt: number?, -- server time the plant / defuse completes
}

export type RoundState = {
	number: number, -- 1-based
	wins: { [string]: number }, -- team id -> rounds won
	roundsToWin: number,
	attackers: string, -- team id attacking this round
	alive: { [string]: number }, -- team id -> players alive
	live: boolean, -- false during the frozen pre-round countdown and the post-round pause
	endsAt: number, -- server time this round's clock (or the pause) ends
	lastWinner: string?, -- previous round's winner, shown during the pause
	lastReason: ("Elimination" | "Detonated" | "Defused" | "Time")?,
}

export type ObjectivePayload = {
	kind: "None" | "Domination" | "Hardpoint" | "SnD" | "KillConfirmed",
	zones: { ZoneState },
	hardpointMovesAt: number?, -- Hardpoint: server time the live zone rotates
	round: RoundState?, -- S&D
	bomb: BombState?, -- S&D
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

export type Loadout = {
	name: string,
	primary: string,
	secondary: string,
	primaryAttachments: { [string]: string }, -- attachment slot -> attachment id
	secondaryAttachments: { [string]: string },
	perks: { string }, -- Phase 5: one perk id per tier, sanitized (always three)
	streaks: { string }, -- Phase 5: up to three killstreak ids, sanitized
}

-- Phase 5 -------------------------------------------------------------------------------------

export type ChallengeView = { id: string, text: string, progress: number, target: number, xp: number, done: boolean }

export type CosmeticsView = {
	equipped: { title: string, emblem: string?, camos: { [string]: string } }, -- camos: weaponId -> camoId (absent = Factory)
	owned: { titles: { string }, emblems: { string }, camos: { [string]: { string } } }, -- camos per weapon id
}

-- Sent on `StreakState` to the owner whenever it changes (kill, death, use, match start).
export type StreakStatePayload = {
	count: number, -- kills this life that count toward streaks
	equipped: { { id: string, cost: number } }, -- in loadout order, costs after perk discounts
	ready: { string }, -- earned and not yet used, oldest first
	nextId: string?, -- the next streak to earn this life
	nextAt: number?, -- the kill count that earns it
}

-- Sent on `Ping` to every member of a team with an active Recon Drone (not to Ghost Signal targets'
-- team's benefit: they are left out of `targets`). Positions are a snapshot; the HUD fades them.
export type PingPayload = { targets: { { userId: number, position: Vector3 } }, expiresAt: number }

export type ProfileSummary = {
	userId: number,
	account: { level: number, xp: number, needed: number, prestige: number },
	weapons: { [string]: { level: number, xp: number, needed: number, kills: number, headshots: number } },
	stats: {
		kills: number,
		deaths: number,
		matches: number,
		wins: number,
		headshots: number,
		assists: number,
		captures: number,
		plants: number,
		defuses: number,
		tags: number,
		dailies: number,
	},
	loadouts: { Loadout },
	selectedLoadout: number,
	unlockedWeapons: { string },
	temporary: boolean, -- true when DataStores are unavailable (progress will NOT persist)
	-- Phase 5
	unlockedPerks: { string },
	unlockedStreaks: { string },
	challenges: { list: { ChallengeView }, resetsAt: number }, -- resetsAt: os.time() of the next UTC day
	cosmetics: CosmeticsView,
	canPrestige: boolean,
	maxPrestige: number,
	-- Phase 6
	store: StoreView,
}

-- Phase 6 store state, part of ProfileSummary.
export type StoreView = {
	credits: number,
	crates: { [string]: number }, -- crate id -> unopened count
	premiumOwned: { string }, -- premium bundle ids fully owned
	paidRandomItemsRestricted: boolean, -- PolicyService for this player (nothing paid is random either way)
}

-- Sent on `CrateOpened` to the opener.
export type CrateResultPayload = {
	crateId: string,
	kind: string?, -- "Camo" | "Title" | "Emblem"; nil when the crate gave credits
	id: string?,
	credits: number,
}

export type MatchResultsPayload = {
	winnerTeam: string?,
	winnerUserId: number?, -- Free-for-All winner (nil on a tie)
	teams: { TeamScore },
	players: { PlayerLine },
	xp: { total: number, breakdown: { { reason: string, amount: number } } }, -- per-recipient
	account: LevelProgress,
	startLevel: number,
}

return nil
