--!strict
-- Pure damage math. Zones: "Head" | "Body" | "Limb".
export type Profile = { close: number, far: number, closeRange: number, farRange: number, maxRange: number }

local Damage = {}

function Damage.atRange(profile: Profile, distance: number): number
	if distance > profile.maxRange then
		return 0
	elseif distance <= profile.closeRange then
		return profile.close
	elseif distance >= profile.farRange then
		return profile.far
	end
	local alpha = (distance - profile.closeRange) / (profile.farRange - profile.closeRange)
	return profile.close + (profile.far - profile.close) * alpha
end

function Damage.compute(def: { damage: Profile, headMultiplier: number, limbMultiplier: number }, distance: number, zone: string): number
	local base = Damage.atRange(def.damage, distance)
	local mult = if zone == "Head" then def.headMultiplier elseif zone == "Limb" then def.limbMultiplier else 1
	return math.floor(base * mult + 0.5)
end

-- Shots needed to kill `health` at a distance and zone; used by tests and balance tooling.
function Damage.shotsToKill(def: any, distance: number, zone: string, health: number): number
	local d = Damage.compute(def, distance, zone)
	if d <= 0 then
		return math.huge
	end
	return math.ceil(health / d)
end

return Damage
