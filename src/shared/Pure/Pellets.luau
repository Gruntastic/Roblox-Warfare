--!strict
-- Fixed shotgun pellet pattern shared by client and server. The client sends one aim direction;
-- both sides expand it into the same pellet directions, so the server never trusts per-pellet
-- input and the client's cosmetic traces match what the server tests.
local Pellets = {}

-- Pellet `i` of `count` as a (yaw, pitch) offset in radians inside a cone of `spreadDeg` radius.
-- Pellet 1 is centred; the rest sit on two rings (inner at 45% radius, outer at 100%).
function Pellets.offset(i: number, count: number, spreadDeg: number): (number, number)
	if i == 1 or count <= 1 then
		return 0, 0
	end
	local radius = math.rad(spreadDeg)
	local rest = count - 1
	local inner = math.max(1, math.floor(rest / 3))
	local k = i - 1 -- 1..rest
	local ringRadius, index, ringSize
	if k <= inner then
		ringRadius, index, ringSize = radius * 0.45, k, inner
	else
		ringRadius, index, ringSize = radius, k - inner, rest - inner
	end
	-- Offset the outer ring by half a step so pellets don't line up with the inner ring.
	local phase = if ringRadius == radius then math.pi / ringSize else 0
	local angle = phase + (index - 1) / ringSize * math.pi * 2
	return math.cos(angle) * ringRadius, math.sin(angle) * ringRadius
end

-- World-space unit directions for every pellet around `aim` (a CFrame whose LookVector is the shot).
function Pellets.directions(aim: CFrame, count: number, spreadDeg: number): { Vector3 }
	local out = table.create(count)
	for i = 1, count do
		local yaw, pitch = Pellets.offset(i, count, spreadDeg)
		out[i] = (aim * CFrame.Angles(pitch, yaw, 0)).LookVector
	end
	return out
end

return Pellets
