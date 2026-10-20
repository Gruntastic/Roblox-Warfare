--!strict
-- Pure ray vs oriented-box intersection for server-side lag-compensated hit detection.
-- Uses only CFrame/Vector3 math so it runs under Lune for tests.
local Hitbox = {}

-- Returns the distance along the (unit) direction at which the ray enters the box, or nil.
function Hitbox.rayOBB(origin: Vector3, dir: Vector3, maxDist: number, cf: CFrame, size: Vector3): number?
	local o = cf:PointToObjectSpace(origin)
	local d = cf:VectorToObjectSpace(dir)
	local half = size / 2
	local tmin, tmax = 0, maxDist
	for _, axis in { "X", "Y", "Z" } do
		local oa: number = (o :: any)[axis]
		local da: number = (d :: any)[axis]
		local h: number = (half :: any)[axis]
		if math.abs(da) < 1e-8 then
			if oa < -h or oa > h then
				return nil
			end
		else
			local t1 = (-h - oa) / da
			local t2 = (h - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
			if tmin > tmax then
				return nil
			end
		end
	end
	return tmin
end

export type Snapshot = { t: number, head: CFrame, root: CFrame }

-- Hitbox layout relative to a character snapshot. Sizes are slightly generous of the
-- R15 default rig; the server also confirms line-of-sight against world geometry.
Hitbox.HEAD_SIZE = Vector3.new(1.4, 1.4, 1.4)
Hitbox.BODY_SIZE = Vector3.new(2.4, 2.2, 1.4)
Hitbox.BODY_OFFSET = CFrame.new(0, 0.35, 0)
Hitbox.LEGS_SIZE = Vector3.new(2.0, 2.2, 1.2)
Hitbox.LEGS_OFFSET = CFrame.new(0, -1.9, 0)

-- Tests a ray against one character snapshot. Returns (distance, zone) of the nearest hit.
function Hitbox.testCharacter(origin: Vector3, dir: Vector3, maxDist: number, snap: Snapshot): (number?, string?)
	local best: number?, zone: string? = nil, nil
	local function consider(t: number?, z: string)
		if t and (best == nil or t < best) then
			best, zone = t, z
		end
	end
	consider(Hitbox.rayOBB(origin, dir, maxDist, snap.head, Hitbox.HEAD_SIZE), "Head")
	consider(Hitbox.rayOBB(origin, dir, maxDist, snap.root * Hitbox.BODY_OFFSET, Hitbox.BODY_SIZE), "Body")
	consider(Hitbox.rayOBB(origin, dir, maxDist, snap.root * Hitbox.LEGS_OFFSET, Hitbox.LEGS_SIZE), "Limb")
	return best, zone
end

-- Interpolates a snapshot history (sorted ascending by t) at time `t`.
function Hitbox.sample(history: { Snapshot }, t: number): Snapshot?
	local n = #history
	if n == 0 then
		return nil
	end
	if t <= history[1].t then
		return history[1]
	end
	if t >= history[n].t then
		return history[n]
	end
	for i = n - 1, 1, -1 do
		local a = history[i]
		if a.t <= t then
			local b = history[i + 1]
			local alpha = (t - a.t) / math.max(b.t - a.t, 1e-6)
			return { t = t, head = a.head:Lerp(b.head, alpha), root = a.root:Lerp(b.root, alpha) }
		end
	end
	return history[1]
end

return Hitbox
