--!strict
-- Sound effect slots. Put an uploaded audio asset id in each slot (a number, e.g. 1234567890).
-- A slot left at 0 is silent, so sounds can be added one at a time. See docs/AUDIO_SFX.md for
-- what each slot is for. Client playback: src/client/Controllers/SoundController.luau.
export type Slot = { id: number, volume: number?, pitchJitter: number? }

local function s(volume: number?, pitchJitter: number?): Slot
	return { id = 0, volume = volume, pitchJitter = pitchJitter }
end

local Audio: { [string]: Slot } = {
	-- gunshots, one per weapon class (each weapon gets a small fixed pitch offset of its own)
	["Shot.AssaultRifle"] = s(0.8, 0.04),
	["Shot.SMG"] = s(0.7, 0.04),
	["Shot.LMG"] = s(0.85, 0.04),
	["Shot.Marksman"] = s(0.85, 0.03),
	["Shot.Sniper"] = s(1, 0.02),
	["Shot.Shotgun"] = s(0.9, 0.03),
	["Shot.Pistol"] = s(0.7, 0.04),
	["Shot.MachinePistol"] = s(0.65, 0.04),
	["Shot.Suppressed"] = s(0.6, 0.05),
	["Shot.Distant"] = s(0.6, 0.06), -- other players' shots; falls back to the AR shot when 0
	-- handling
	Dry = s(0.6),
	MagOut = s(0.6),
	MagIn = s(0.6),
	BoltRack = s(0.6),
	ShellLoad = s(0.6, 0.03),
	BoltCycle = s(0.6),
	Equip = s(0.5),
	AdsIn = s(0.35),
	Melee = s(0.6, 0.05),
	MeleeHit = s(0.7),
	-- hits and feedback
	HitMarker = s(0.5),
	HitHeadshot = s(0.6),
	KillConfirm = s(0.6),
	HurtPlayer = s(0.6, 0.05),
	["Impact.Concrete"] = s(0.5, 0.08),
	["Impact.Metal"] = s(0.5, 0.08),
	["Impact.Wood"] = s(0.5, 0.08),
	["Impact.Dirt"] = s(0.5, 0.08),
	BulletWhiz = s(0.5, 0.08),
	-- movement (slots reserved; not wired yet)
	["Footstep.Hard"] = s(0.4, 0.08),
	["Footstep.Soft"] = s(0.4, 0.08),
	["Footstep.Metal"] = s(0.4, 0.08),
	Land = s(0.5),
	-- killstreaks, objectives, interface (slots reserved; not wired yet)
	["Streak.Earned"] = s(0.7),
	["Streak.Explosion"] = s(1),
	["Objective.Capture"] = s(0.7),
	["Objective.BombPlant"] = s(0.8),
	["UI.Click"] = s(0.4),
	["UI.LevelUp"] = s(0.7),
	["UI.Victory"] = s(0.8),
	["UI.Defeat"] = s(0.8),
}

return Audio
