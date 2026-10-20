--!strict
-- Pure objective rules shared by the objective modes: zone membership, Domination capture,
-- Hardpoint rotation and Search and Destroy round outcomes. No Roblox services, Lune-testable.
local Objectives = {}

---------------------------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------------------------

-- True when `point` is inside the box `cf`/`size` (any rotation). Uses the box's own axes.
function Objectives.inBox(cf: CFrame, size: Vector3, point: Vector3): boolean
	local p = cf:PointToObjectSpace(point)
	return math.abs(p.X) <= size.X / 2 and math.abs(p.Y) <= size.Y / 2 and math.abs(p.Z) <= size.Z / 2
end

-- Teams present (count > 0), and whether more than one is.
function Objectives.presence(counts: { [string]: number }): (string?, boolean)
	local only: string? = nil
	for team, n in counts do
		if n > 0 then
			if only then
				return nil, true
			end
			only = team
		end
	end
	return only, false
end

---------------------------------------------------------------------------------------------
-- Domination capture
---------------------------------------------------------------------------------------------

export type Flag = {
	owner: string?,
	capturingTeam: string?,
	progress: number, -- 0..1 towards capturingTeam
	contested: boolean,
}

-- Capture speed multiplier for n capturers: 1, 1.5, 2 (capped at three players).
function Objectives.captureRate(n: number): number
	return 1 + 0.5 * (math.clamp(n, 1, 3) - 1)
end

-- Advances one flag by dt seconds. counts = team id -> players inside. Returns the team that
-- completed a capture this step, if any.
--  * Both teams inside: contested, frozen.
--  * Nobody inside: partial progress drains back to zero.
--  * The owner alone: drains any enemy partial progress.
--  * Another team alone: first drains a third team's partial progress, then builds its own;
--    at 1 the flag flips to it.
function Objectives.stepFlag(flag: Flag, counts: { [string]: number }, dt: number, captureTime: number): string?
	local team, contested = Objectives.presence(counts)
	flag.contested = contested
	if contested then
		return nil
	end
	if not team then
		flag.progress = math.max(0, flag.progress - dt / captureTime)
		if flag.progress == 0 then
			flag.capturingTeam = nil
		end
		return nil
	end
	local rate = Objectives.captureRate(counts[team]) / captureTime
	if flag.owner == team then
		flag.progress = math.max(0, flag.progress - rate * dt)
		if flag.progress == 0 then
			flag.capturingTeam = nil
		end
		return nil
	end
	if flag.capturingTeam ~= nil and flag.capturingTeam ~= team then
		flag.progress -= rate * dt
		if flag.progress > 0 then
			return nil
		end
		-- carry the remainder into this team's own capture
		flag.progress = -flag.progress
		flag.capturingTeam = team
	else
		flag.capturingTeam = team
		flag.progress += rate * dt
	end
	if flag.progress >= 1 then
		flag.owner = team
		flag.capturingTeam = nil
		flag.progress = 0
		return team
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Hardpoint rotation
---------------------------------------------------------------------------------------------

-- Live zone index (1..count) at `elapsed` seconds into the match, or nil before the first zone
-- opens. Also returns the elapsed time at which the current (or first) zone ends.
function Objectives.hardpointAt(elapsed: number, firstDelay: number, duration: number, count: number): (number?, number)
	if elapsed < firstDelay then
		return nil, firstDelay
	end
	local slot = math.floor((elapsed - firstDelay) / duration)
	return slot % count + 1, firstDelay + (slot + 1) * duration
end

---------------------------------------------------------------------------------------------
-- Search and Destroy
---------------------------------------------------------------------------------------------

export type RoundView = {
	attackers: string,
	defenders: string,
	alive: { [string]: number },
	started: { [string]: number }, -- players each team had when the round went live
	bomb: string, -- BombState.state
	timeUp: boolean,
}

-- Winner and reason for the current round state, or nil while it is still being played.
-- A team that started the round with nobody cannot be eliminated.
function Objectives.roundOutcome(v: RoundView): (string?, string?)
	if v.bomb == "Detonated" then
		return v.attackers, "Detonated"
	end
	if v.bomb == "Defused" then
		return v.defenders, "Defused"
	end
	local function wiped(team: string): boolean
		return (v.started[team] or 0) > 0 and (v.alive[team] or 0) == 0
	end
	if wiped(v.defenders) then
		return v.attackers, "Elimination"
	end
	if v.bomb ~= "Planted" then
		-- once the bomb is down, killing every attacker no longer wins: it must be defused
		if wiped(v.attackers) then
			return v.defenders, "Elimination"
		end
		if v.timeUp then
			return v.defenders, "Time"
		end
	end
	return nil, nil
end

-- Attacking team for a 1-based round: the first attackers attack until `swapAfter` rounds have
-- been played, then the sides alternate in blocks of `swapAfter`.
function Objectives.attackersFor(round: number, firstAttackers: string, other: string, swapAfter: number): string
	local block = math.floor((round - 1) / math.max(swapAfter, 1))
	return if block % 2 == 0 then firstAttackers else other
end

return Objectives
