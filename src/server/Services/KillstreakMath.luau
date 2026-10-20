--!strict
-- Pure helpers for KillstreakService (Phase 5): aim validation, explosion falloff, shell scatter,
-- strike-run lines and sentry lock-on. No Roblox services, so the Lune specs can load it
-- (tests/specs/phase5_gameplay.spec.luau).
local KillstreakMath = {}

local MAX_COMPONENT = 1e6

local function finite(n: number): boolean
	return n == n and math.abs(n) <= MAX_COMPONENT
end

-- The client's aim direction as a unit vector, or nil when it is not a finite Vector3 of
-- length 0.5..1.5 (contract: normalise anything in range, refuse everything else).
function KillstreakMath.aimDirection(v: any): Vector3?
	if typeof(v) ~= "Vector3" then
		return nil
	end
	local vec = v :: Vector3
	if not (finite(vec.X) and finite(vec.Y) and finite(vec.Z)) then
		return nil
	end
	local mag = vec.Magnitude
	if mag < 0.5 or mag > 1.5 then
		return nil
	end
	return vec / mag
end

-- Radial damage: full at the centre, falling linearly to 0 at `radius`.
function KillstreakMath.falloff(damage: number, radius: number, distance: number): number
	if radius <= 0 or distance >= radius then
		return 0
	end
	return damage * (1 - math.max(distance, 0) / radius)
end

-- A landing point inside a horizontal disc of `scatter` studs around `aim`. `u1` and `u2` are
-- uniform 0..1 numbers (sqrt keeps the spread even over the disc's area).
function KillstreakMath.scatter(aim: Vector3, scatter: number, u1: number, u2: number): Vector3
	local r = scatter * math.sqrt(math.clamp(u1, 0, 1))
	local a = u2 * math.pi * 2
	return aim + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
end

-- The horizontal part of a direction, normalised. A straight up / down aim gives `fallback`.
function KillstreakMath.flatDirection(dir: Vector3, fallback: Vector3?): Vector3
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-3 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

-- Strike Run blast centres: `blasts` points from `aim` along the horizontal aim, `spacing` apart.
-- Heights are the aim point's; the service drops each one to the ground.
function KillstreakMath.strikeLine(aim: Vector3, dir: Vector3, blasts: number, spacing: number): { Vector3 }
	local flat = KillstreakMath.flatDirection(dir)
	local out = {}
	for i = 1, math.max(0, math.floor(blasts)) do
		out[i] = aim + flat * (spacing * (i - 1))
	end
	return out
end

-- Seconds after activation that each of `count` impacts lands.
function KillstreakMath.impactDelays(warning: number, interval: number, count: number): { number }
	local out = {}
	for i = 1, math.max(0, math.floor(count)) do
		out[i] = warning + interval * (i - 1)
	end
	return out
end

-- Seconds a sentry must keep a target in sight before it fires.
function KillstreakMath.lockOnTime(params: { [string]: number }, ghost: boolean): number
	return if ghost then params.ghostLockOn or params.lockOn or 0 else params.lockOn or 0
end

-- Seconds between sentry shots.
function KillstreakMath.fireInterval(rpm: number): number
	return 60 / math.max(rpm, 1)
end

-- The "side" an effect belongs to: the team id in team modes, a per-player key in Free-for-All
-- (where every other player is an enemy). nil = not in the match.
function KillstreakMath.side(teamMode: boolean, team: string?, userId: number): string?
	if teamMode then
		return team
	end
	return "#" .. tostring(userId)
end

-- The team an effect is aimed at: the other team in a two-team mode, nil in Free-for-All
-- (clients then treat everyone but the owner as affected).
function KillstreakMath.victimTeam(teams: { string }, ownerTeam: string?): string?
	if not ownerTeam then
		return nil
	end
	for _, t in teams do
		if t ~= ownerTeam then
			return t
		end
	end
	return nil
end

return KillstreakMath
