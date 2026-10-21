--!strict
-- Sound effect slots. Put an uploaded audio asset id in each slot (a number, e.g. 1234567890).
-- A slot left at 0 is silent, so sounds can be added one at a time. See docs/AUDIO_SFX.md for
-- what each slot is for. Client playback: src/client/Controllers/SoundController.luau.
export type Slot = { id: number, volume: number?, pitchJitter: number?, pitch: number? } -- pitch: fixed offset, e.g. 0.15 = 15% higher

local function s(volume: number?, pitchJitter: number?): Slot
	return { id = 0, volume = volume, pitchJitter = pitchJitter }
end

local Audio: { [string]: Slot } = {
	-- gunshots, one per weapon class (each weapon gets a small fixed pitch offset of its own)
	["Shot.AssaultRifle"] = { id = 107457358196366, volume = 0.8, pitchJitter = 0.04 }, -- Toolbox (free)
	["Shot.SMG"] = { id = 77130830495173, volume = 0.7, pitchJitter = 0.04 }, -- Toolbox (free)
	["Shot.LMG"] = { id = 79937855461190, volume = 0.85, pitchJitter = 0.04 },
	["Shot.Marksman"] = { id = 96758012917494, volume = 0.85, pitchJitter = 0.03 },
	["Shot.Sniper"] = { id = 108771415543794, volume = 1, pitchJitter = 0.02 },
	["Shot.Shotgun"] = { id = 132255180302885, volume = 0.9, pitchJitter = 0.03 }, -- Toolbox (free)
	["Shot.Pistol"] = { id = 131413092560803, volume = 0.7, pitchJitter = 0.04 }, -- Toolbox (free)
	["Shot.MachinePistol"] = { id = 77130830495173, volume = 0.6, pitchJitter = 0.04, pitch = 0.12 }, -- SMG shot, pitched up
	["Shot.Suppressed"] = { id = 5707240744, volume = 0.6, pitchJitter = 0.05 }, -- Toolbox (free)
	["Shot.Distant"] = { id = 130108908845542, volume = 0.6, pitchJitter = 0.06 }, -- Toolbox (free); other players' shots -- other players' shots; falls back to the AR shot when 0
	-- handling. A full reload sound (Reload.*) replaces MagOut / MagIn / BoltRack for its guns.
	["Reload.Rifle"] = { id = 72669885741351, volume = 0.6 }, -- every long gun except shotguns
	["Reload.Handgun"] = { id = 136363539986502, volume = 0.6 }, -- pistols and machine pistols
	Dry = { id = 117629133235583, volume = 0.6 }, -- Toolbox (free)
	MagOut = s(0.6),
	MagIn = s(0.6),
	BoltRack = s(0.6),
	ShellLoad = { id = 110912571549014, volume = 0.6, pitchJitter = 0.03 }, -- Toolbox (free)
	BoltCycle = { id = 97965897393802, volume = 0.6 }, -- Toolbox (free)
	Equip = s(0.5),
	AdsIn = s(0.35),
	Melee = s(0.6, 0.05),
	MeleeHit = s(0.7),
	-- hits and feedback
	HitMarker = { id = 84433276658992, volume = 0.5 }, -- "Machine Impact"
	HitHeadshot = { id = 84433276658992, volume = 0.65, pitch = 0.18 }, -- same sound, pitched up
	KillConfirm = { id = 73943243843673, volume = 0.6 }, -- Toolbox (free)
	HurtPlayer = { id = 9120417632, volume = 0.6, pitchJitter = 0.05 }, -- Pro Sound Effects (Roblox library)
	["Impact.Concrete"] = { id = 79671891898982, volume = 0.5, pitchJitter = 0.08 }, -- Toolbox (free)
	["Impact.Metal"] = { id = 79671891898982, volume = 0.5, pitchJitter = 0.08, pitch = 0.25 }, -- concrete hit, brighter
	["Impact.Wood"] = { id = 79671891898982, volume = 0.45, pitchJitter = 0.08, pitch = -0.15 }, -- concrete hit, duller
	["Impact.Dirt"] = { id = 79671891898982, volume = 0.35, pitchJitter = 0.08, pitch = -0.3 }, -- concrete hit, muffled
	BulletWhiz = s(0.5, 0.08),
	-- movement (slots reserved; not wired yet)
	["Footstep.Hard"] = s(0.4, 0.08),
	["Footstep.Soft"] = s(0.4, 0.08),
	["Footstep.Metal"] = s(0.4, 0.08),
	Land = s(0.5),
	-- killstreaks (mortar / strike run wired), objectives and interface (reserved; not wired yet)
	["Streak.Earned"] = s(0.7),
	["Streak.MortarIncoming"] = { id = 117658983323549, volume = 0.9 }, -- also Strike Run
	["Streak.Explosion"] = { id = 115461656921873, volume = 1, pitchJitter = 0.06 },
	["Objective.Capture"] = s(0.7),
	["Objective.BombPlant"] = s(0.8),
	["UI.Click"] = s(0.4),
	["UI.LevelUp"] = s(0.7),
	["UI.Victory"] = s(0.8),
	["UI.Defeat"] = s(0.8),
}

return Audio
