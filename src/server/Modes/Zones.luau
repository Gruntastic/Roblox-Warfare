--!strict
-- Reads objective zones from a map's Objectives folder (docs/MAP_CONTRACT.md) and counts players
-- inside them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Objectives = require(ReplicatedStorage.Shared.Pure.Objectives)
local Types = require(ReplicatedStorage.Shared.Types)
local ModeTypes = require(script.Parent.ModeTypes)

local Zones = {}

export type Zone = {
	id: string,
	label: string,
	part: BasePart,
}

-- Zones of one Kind, sorted by Label (flags, sites) or Order (hardpoints).
function Zones.collect(map: Model, kind: string): { Zone }
	local list: { Zone } = {}
	local folder = map:FindFirstChild("Objectives")
	if not folder then
		return list
	end
	for _, p in folder:GetChildren() do
		if p:IsA("BasePart") and p:GetAttribute("Kind") == kind then
			local label = p:GetAttribute("Label")
			local order = p:GetAttribute("Order")
			local id = if type(label) == "string" then label elseif type(order) == "number" then "HP" .. order else p.Name
			table.insert(list, { id = id, label = if type(label) == "string" then label else "", part = p })
		end
	end
	table.sort(list, function(a, b)
		local oa, ob = a.part:GetAttribute("Order"), b.part:GetAttribute("Order")
		if type(oa) == "number" and type(ob) == "number" then
			return oa < ob
		end
		return a.id < b.id
	end)
	return list
end

function Zones.contains(zone: Zone, point: Vector3): boolean
	return Objectives.inBox(zone.part.CFrame, zone.part.Size, point)
end

-- Living participants inside the zone, grouped by team.
function Zones.occupants(ctx: ModeTypes.Context, zone: Zone): ({ [string]: number }, { [string]: { Player } })
	local counts: { [string]: number } = {}
	local who: { [string]: { Player } } = {}
	for _, player in ctx.participants() do
		local team = ctx.teamOf(player)
		local root = if team then ctx.root(player) else nil
		if team and root and Zones.contains(zone, root.Position) then
			counts[team] = (counts[team] or 0) + 1
			local list = who[team]
			if not list then
				list = {}
				who[team] = list
			end
			table.insert(list, player)
		end
	end
	return counts, who
end

-- ZoneState for the client; callers fill in owner / progress / contested / active.
function Zones.state(zone: Zone): Types.ZoneState
	local cf = zone.part.CFrame
	local size = zone.part.Size
	local look = cf.LookVector
	return {
		id = zone.id,
		label = zone.label,
		position = cf.Position - Vector3.new(0, size.Y / 2, 0),
		size = size,
		yaw = math.atan2(-look.X, -look.Z),
		owner = nil,
		capturingTeam = nil,
		progress = 0,
		contested = false,
		active = true,
	}
end

return Zones
