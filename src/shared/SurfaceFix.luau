--!strict
-- Stops texture flicker (z-fighting) in code-built maps. Two visible blocks whose faces lie in
-- the same plane, face the same way and overlap make the renderer alternate between them. When
-- the two look different (colour or material), the smaller part is grown by INSET studs on that
-- axis so its face sits just in front and always wins. Parts that look identical are left alone:
-- there is nothing visible to flicker. Only axis-aligned blocks (90 degree rotations) are handled.
local SurfaceFix = {}

local EPS = 0.002 -- faces closer than this share a plane
local MIN_AREA = 0.04 -- ignore slivers
SurfaceFix.INSET = 0.04 -- total growth; each face moves out by half of this

export type Hit = { a: BasePart, b: BasePart, axis: string, area: number }

type Face = { part: BasePart, plane: number, u0: number, u1: number, v0: number, v1: number }

local SPECS = { { "X", "Y", "Z" }, { "Y", "X", "Z" }, { "Z", "X", "Y" } }

local function axisAligned(cf: CFrame): boolean
	for _, v in { cf.RightVector, cf.UpVector, cf.LookVector } do
		local ax, ay, az = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)
		local big = math.max(ax, ay, az)
		if big < 0.999 or ax + ay + az - big > 0.002 then
			return false
		end
	end
	return true
end

local function isBlock(p: Instance): boolean
	return p:IsA("Part") and (p :: Part).Shape.Name == "Block"
end

-- World half-extents of an axis-aligned part.
local function halfExtents(p: BasePart): { [string]: number }
	local cf, s = p.CFrame, p.Size
	local function ext(i: string): number
		return math.abs((cf.RightVector :: any)[i]) * s.X
			+ math.abs((cf.UpVector :: any)[i]) * s.Y
			+ math.abs((cf.LookVector :: any)[i]) * s.Z
	end
	return { X = ext("X") / 2, Y = ext("Y") / 2, Z = ext("Z") / 2 }
end

local function looksSame(a: BasePart, b: BasePart): boolean
	return a.Material == b.Material and a.Color == b.Color and a.Transparency == b.Transparency
end

-- Every coplanar, same-facing, overlapping pair whose parts look different.
function SurfaceFix.find(model: Instance): { Hit }
	local groups: { [string]: { Face } } = {}
	for _, d in model:GetDescendants() do
		if isBlock(d) then
			local p = d :: BasePart
			if p.Transparency < 1 and axisAligned(p.CFrame) then
				local h = halfExtents(p)
				local pos = p.CFrame.Position
				local c = { X = pos.X, Y = pos.Y, Z = pos.Z }
				for _, spec in SPECS do
					local ax, u, v = spec[1], spec[2], spec[3]
					for _, side in { -1, 1 } do
						local plane = c[ax] + side * h[ax]
						local key = ax .. side .. ":" .. math.floor(plane * 100 + 0.5)
						local g = groups[key]
						if not g then
							g = {}
							groups[key] = g
						end
						table.insert(g, { part = p, plane = plane, u0 = c[u] - h[u], u1 = c[u] + h[u], v0 = c[v] - h[v], v1 = c[v] + h[v] })
					end
				end
			end
		end
	end
	local out: { Hit } = {}
	for key, g in groups do
		if #g > 1 then
			table.sort(g, function(a, b)
				return a.u0 < b.u0
			end)
			for i = 1, #g do
				local a = g[i]
				for j = i + 1, #g do
					local b = g[j]
					if b.u0 >= a.u1 then
						break
					end
					if math.abs(a.plane - b.plane) < EPS and not looksSame(a.part, b.part) then
						local du = math.min(a.u1, b.u1) - math.max(a.u0, b.u0)
						local dv = math.min(a.v1, b.v1) - math.max(a.v0, b.v0)
						if du > 0 and dv > 0 and du * dv >= MIN_AREA then
							table.insert(out, { a = a.part, b = b.part, axis = string.sub(key, 1, 1), area = du * dv })
						end
					end
				end
			end
		end
	end
	return out
end

local function volume(p: BasePart): number
	return p.Size.X * p.Size.Y * p.Size.Z
end

-- One pass: grows the smaller part of each flickering pair along the shared axis.
-- `winners` carries over between passes: a part that was grown before keeps winning, so two
-- equal parts cannot take turns and line up again.
local function pass(model: Instance, winners: { [BasePart]: boolean }): number
	local grown: { [BasePart]: { [string]: boolean } } = {}
	local changed = 0
	for _, hit in SurfaceFix.find(model) do
		local p
		if winners[hit.a] ~= winners[hit.b] then
			p = if winners[hit.a] then hit.a else hit.b
		else
			p = if volume(hit.a) <= volume(hit.b) then hit.a else hit.b
		end
		winners[p] = true
		local done = grown[p]
		if not done then
			done = {}
			grown[p] = done
		end
		if not done[hit.axis] then
			done[hit.axis] = true
			local cf = p.CFrame
			-- which local axis of the part lies along the world axis
			local function along(v: Vector3): boolean
				return math.abs((v :: any)[hit.axis]) > 0.5
			end
			local g = SurfaceFix.INSET
			local add = if along(cf.RightVector)
				then Vector3.new(g, 0, 0)
				elseif along(cf.UpVector) then Vector3.new(0, g, 0)
				else Vector3.new(0, 0, g)
			p.Size += add
			p.CFrame = cf -- keep it centred
			changed += 1
		end
	end
	return changed
end

-- Repeats until nothing flickers (growing a part can line it up with a third one). Returns the
-- number of part growths made.
function SurfaceFix.apply(model: Instance): number
	local total = 0
	local winners: { [BasePart]: boolean } = {}
	for _ = 1, 6 do
		local n = pass(model, winners)
		total += n
		if n == 0 then
			break
		end
	end
	return total
end

return SurfaceFix
