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
	tokens: number, -- fire-rate token bucket (1 token per shot)
	tokensAt: number,
	readyAt: number, -- after equip
}

local WeaponState = {}

-- Fire rate uses a token bucket refilled at rpm/60 tokens per second. The bucket holds
-- 1 + BURST tokens, so network jitter can bunch shots by up to BURST intervals, but the
-- long-run rate can never exceed the weapon's rpm (at most BURST extra shots ever).
WeaponState.BURST = 0.5

function WeaponState.new(def: { id: string, rpm: number, fireMode: any, magSize: number, reserveAmmo: number }): WeaponState
	return {
		defId = def.id,
		rpm = def.rpm,
		fireMode = def.fireMode,
		mag = def.magSize,
		magSize = def.magSize,
		reserve = def.reserveAmmo,
		reloadEndsAt = nil,
		reloadTarget = 0,
		tokens = 1 + WeaponState.BURST,
		tokensAt = 0,
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
	local cap = 1 + WeaponState.BURST
	s.tokens = math.min(cap, s.tokens + math.max(0, now - s.tokensAt) * s.rpm / 60)
	s.tokensAt = now
	if s.tokens < 1 then
		return false, "rate"
	end
	s.tokens -= 1
	s.mag -= 1
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
