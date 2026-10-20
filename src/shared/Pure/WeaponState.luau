--!strict
-- Pure, server-authoritative weapon state machine: fire-rate gate, ammo and reloads.
-- `now` is always passed in so it can be driven by tests.
export type WeaponState = {
	defId: string,
	rpm: number,
	fireMode: string,
	mag: number,
	magSize: number,
	reserve: number,
	reloadEndsAt: number?,
	reloadTarget: number,
	nextFireAt: number,
	burstCredit: number,
	readyAt: number, -- after equip
}

local WeaponState = {}

-- Network jitter tolerance: a shot may arrive up to this fraction of an interval early,
-- but the accumulated credit can never exceed one full interval.
WeaponState.JITTER_FRACTION = 0.35

function WeaponState.new(def: { id: string, rpm: number, fireMode: string, magSize: number, reserveAmmo: number }): WeaponState
	return {
		defId = def.id,
		rpm = def.rpm,
		fireMode = def.fireMode,
		mag = def.magSize,
		magSize = def.magSize,
		reserve = def.reserveAmmo,
		reloadEndsAt = nil,
		reloadTarget = 0,
		nextFireAt = 0,
		burstCredit = 0,
		readyAt = 0,
	}
end

function WeaponState.interval(s: WeaponState): number
	return 60 / s.rpm
end

-- Completes a reload whose timer has elapsed. Call before reading ammo.
function WeaponState.update(s: WeaponState, now: number)
	if s.reloadEndsAt and now >= s.reloadEndsAt then
		local take = math.min(s.magSize - s.mag, s.reserve)
		s.mag += take
		s.reserve -= take
		s.reloadEndsAt = nil
	end
end

-- Returns (ok, reason). On success one round is consumed.
function WeaponState.tryFire(s: WeaponState, now: number): (boolean, string?)
	WeaponState.update(s, now)
	if now < s.readyAt then
		return false, "equipping"
	end
	if s.reloadEndsAt then
		return false, "reloading"
	end
	if s.mag <= 0 then
		return false, "empty"
	end
	local interval = WeaponState.interval(s)
	if now < s.nextFireAt then
		local early = s.nextFireAt - now
		if early > interval * WeaponState.JITTER_FRACTION or s.burstCredit + early > interval then
			return false, "rate"
		end
		s.burstCredit += early
	else
		-- paying back credit over time when the player fires slower than the cap
		s.burstCredit = math.max(0, s.burstCredit - (now - s.nextFireAt))
	end
	s.mag -= 1
	s.nextFireAt = math.max(now, s.nextFireAt) + interval
	return true, nil
end

function WeaponState.startReload(s: WeaponState, now: number, tactical: number, empty: number): (boolean, string?)
	WeaponState.update(s, now)
	if s.reloadEndsAt then
		return false, "reloading"
	end
	if s.mag >= s.magSize then
		return false, "full"
	end
	if s.reserve <= 0 then
		return false, "noreserve"
	end
	s.reloadEndsAt = now + (if s.mag == 0 then empty else tactical)
	return true, nil
end

function WeaponState.cancelReload(s: WeaponState)
	s.reloadEndsAt = nil
end

function WeaponState.equip(s: WeaponState, now: number, equipTime: number)
	s.reloadEndsAt = nil
	s.readyAt = now + equipTime
end

return WeaponState
