--!strict
-- Pure helpers for the Phase 4 objective UI: zone containment, S&D plant / defuse eligibility
-- (a client-side mirror of the server rules in docs/CONTRACTS.md, used only to show the prompt;
-- the server decides), Free-for-All placings, spectator cycling and banner text.
-- No `game` access; runs under Lune (tests/specs/objective_rules.spec.luau).
local Types = require(script.Parent.Parent.Types)

local ObjectiveRules = {}

ObjectiveRules.DEFUSE_RANGE = 6 -- studs from the planted bomb (CONTRACTS.md "Interact")
ObjectiveRules.ZONE_SLACK = 0.25 -- studs of vertical tolerance around the zone box

export type Relation = "Friendly" | "Enemy" | "Neutral"
export type Tone = "Friendly" | "Enemy" | "Neutral" | "Accent"
export type Banner = { title: string, sub: string?, tone: Tone, duration: number }
export type BannerContext = {
	userId: number,
	team: string?,
	attackers: string?, -- S&D: the attacking team this round (from ObjectivePayload.round)
	nameOf: ((number) -> string?)?,
	firstHardpoint: boolean?, -- true when no hardpoint has been announced yet this match
}
export type InteractContext = {
	objective: Types.ObjectivePayload?,
	userId: number,
	team: string?,
	position: Vector3?, -- the local character's root position
	alive: boolean,
}

type ZoneLike = { position: Vector3, size: Vector3, yaw: number }
type Line = Types.PlayerLine

-- True when `pos` lies inside the zone box. Mirrors the server's test (the zone part's box):
-- `position` is the box's floor centre, so the box spans 0..size.Y above it, rotated by `yaw`.
function ObjectiveRules.insideZone(pos: Vector3, zone: ZoneLike): boolean
	if typeof(zone.position) ~= "Vector3" or typeof(zone.size) ~= "Vector3" then
		return false
	end
	local yaw = if type(zone.yaw) == "number" then zone.yaw else 0
	local cf = CFrame.new(zone.position) * CFrame.Angles(0, yaw, 0)
	local p = cf:PointToObjectSpace(pos)
	return math.abs(p.X) <= zone.size.X / 2
		and math.abs(p.Z) <= zone.size.Z / 2
		and p.Y >= -ObjectiveRules.ZONE_SLACK
		and p.Y <= zone.size.Y + ObjectiveRules.ZONE_SLACK
end

-- "Plant" / "Defuse" when the local player may start that action now, else nil.
-- Plant: the living bomb carrier, on the attacking team, inside an active site, round live.
-- Defuse: a living defender within DEFUSE_RANGE of the planted bomb, round live.
-- Nobody else may be planting / defusing at the time.
-- While the server reports this player mid-action the current kind is kept, so the prompt does
-- not flicker if the client's containment test disagrees by a fraction of a stud.
function ObjectiveRules.interactKind(ctx: InteractContext): ("Plant" | "Defuse")?
	local obj = ctx.objective
	if not ctx.alive or not obj or obj.kind ~= "SnD" or not ctx.position or not ctx.team then
		return nil
	end
	local round, bomb = obj.round, obj.bomb
	if not round or not bomb or not round.live then
		return nil
	end
	if bomb.actionUserId ~= nil then
		if bomb.actionUserId == ctx.userId and (bomb.actionKind == "Plant" or bomb.actionKind == "Defuse") then
			return bomb.actionKind
		end
		return nil -- the server runs one action at a time
	end
	local pos = ctx.position :: Vector3
	if bomb.state == "Carried" and bomb.carrierUserId == ctx.userId and ctx.team == round.attackers then
		for _, zone in (obj.zones or {}) :: { Types.ZoneState } do
			if zone.active ~= false and ObjectiveRules.insideZone(pos, zone) then
				return "Plant"
			end
		end
	elseif bomb.state == "Planted" and ctx.team ~= round.attackers and typeof(bomb.position) == "Vector3" then
		if (bomb.position - pos).Magnitude <= ObjectiveRules.DEFUSE_RANGE then
			return "Defuse"
		end
	end
	return nil
end

-- Relation of a team to the local team.
function ObjectiveRules.relation(teamId: string?, myTeam: string?): Relation
	if teamId == nil then
		return "Neutral"
	end
	return if teamId == myTeam then "Friendly" else "Enemy"
end

-- Hardpoint status for the live zone: Contested, Friendly (we hold it), Enemy or Neutral.
function ObjectiveRules.hardpointStatus(zone: Types.ZoneState?, myTeam: string?): "Contested" | Relation
	if not zone then
		return "Neutral"
	end
	if zone.contested then
		return "Contested"
	end
	return ObjectiveRules.relation(zone.owner or zone.capturingTeam, myTeam)
end

function ObjectiveRules.ordinal(n: number): string
	local m100 = n % 100
	local suffix = "TH"
	if m100 < 11 or m100 > 13 then
		local m10 = n % 10
		suffix = if m10 == 1 then "ST" elseif m10 == 2 then "ND" elseif m10 == 3 then "RD" else "TH"
	end
	return tostring(n) .. suffix
end

-- Free-for-All placing by kills (the race the server decides on). Players on equal kills share a
-- place. Returns (place, tied) or (nil, false) when the user is not listed.
function ObjectiveRules.place(lines: { Line }, userId: number): (number?, boolean)
	local mine: Line? = nil
	for _, l in lines do
		if l.userId == userId then
			mine = l
			break
		end
	end
	if not mine then
		return nil, false
	end
	local better, tied = 0, false
	for _, l in lines do
		if l.userId ~= userId then
			if l.kills > mine.kills then
				better += 1
			elseif l.kills == mine.kills then
				tied = true
			end
		end
	end
	return better + 1, tied
end

-- Sorts a copy of the lines for Free-for-All display: kills, then score, then name.
function ObjectiveRules.sortFFA<T>(lines: { T }): { T }
	local copy = table.clone(lines)
	table.sort(copy, function(a: any, b: any)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if a.score ~= b.score then
			return a.score > b.score
		end
		return tostring(a.name) < tostring(b.name)
	end)
	return copy
end

-- HUD race readout: (myKills, rivalName, rivalKills, iLead). The rival is the leader, or the
-- runner-up when the local player leads (or shares the lead).
function ObjectiveRules.ffaRace(lines: { Line }, userId: number): (number, string?, number, boolean)
	local myKills = 0
	local best: Line? = nil
	for _, l in lines do
		if l.userId == userId then
			myKills = l.kills
		elseif not best or l.kills > best.kills or (l.kills == best.kills and l.score > best.score) then
			best = l
		end
	end
	if not best then
		return myKills, nil, 0, true
	end
	return myKills, best.name, best.kills, myKills >= best.kills
end

-- Next / previous id in a sorted list of candidates (spectator cycling). Wraps around; when the
-- current id is not in the list the first (dir >= 0) or last candidate is returned.
function ObjectiveRules.cycle(ids: { number }, current: number?, dir: number): number?
	local n = #ids
	if n == 0 then
		return nil
	end
	local index = if current then table.find(ids, current) else nil
	if not index then
		return if dir >= 0 then ids[1] else ids[n]
	end
	if dir == 0 then
		return ids[index]
	end
	return ids[((index - 1 + (if dir > 0 then 1 else -1)) % n) + 1]
end

local REASONS: { [string]: string } = {
	Elimination = "ELIMINATION",
	Detonated = "BOMB DETONATED",
	Defused = "BOMB DEFUSED",
	Time = "TIME EXPIRED",
}

local function str(v: any): string?
	return if type(v) == "string" and v ~= "" then v else nil
end

-- Short centre-screen banner for an ObjectiveEvent, or nil when the event is not worth one for
-- this player (e.g. someone else's tag pickup).
function ObjectiveRules.banner(kind: string, data: { [string]: any }, ctx: BannerContext): Banner?
	local me, myTeam = ctx.userId, ctx.team
	local function nameOf(uid: any): string?
		if type(uid) ~= "number" or not ctx.nameOf then
			return nil
		end
		local n = ctx.nameOf(uid)
		return if n then string.upper(n) else nil
	end
	local attacking = myTeam ~= nil and ctx.attackers ~= nil and myTeam == ctx.attackers
	local defending = myTeam ~= nil and ctx.attackers ~= nil and myTeam ~= ctx.attackers

	if kind == "ZoneCaptured" then
		local id = str(data.id) or "?"
		local rel = ObjectiveRules.relation(str(data.team), myTeam)
		return {
			title = "FLAG " .. id .. " CAPTURED",
			sub = if rel == "Friendly" then "YOUR TEAM" elseif rel == "Enemy" then "BY THE ENEMY" else nil,
			tone = if rel == "Friendly" then "Friendly" elseif rel == "Enemy" then "Enemy" else "Accent",
			duration = 2.2,
		}
	elseif kind == "HardpointMoved" then
		return {
			title = if ctx.firstHardpoint then "HARDPOINT ONLINE" else "HARDPOINT MOVED",
			sub = "CAPTURE AND HOLD",
			tone = "Accent",
			duration = 2.4,
		}
	elseif kind == "BombPickedUp" then
		if data.userId == me then
			return { title = "YOU HAVE THE BOMB", sub = "PLANT IT AT A SITE", tone = "Accent", duration = 2.4 }
		elseif attacking then
			return { title = "BOMB PICKED UP", sub = nameOf(data.userId), tone = "Friendly", duration = 1.8 }
		end
		return nil
	elseif kind == "BombDropped" then
		if attacking then
			return { title = "BOMB DROPPED", sub = "RECOVER IT", tone = "Enemy", duration = 2 }
		elseif defending then
			return { title = "BOMB DROPPED", sub = nil, tone = "Friendly", duration = 1.8 }
		end
		return { title = "BOMB DROPPED", sub = nil, tone = "Neutral", duration = 1.8 }
	elseif kind == "BombPlanted" then
		local site = str(data.site)
		return {
			title = if site then "BOMB PLANTED AT " .. site else "BOMB PLANTED",
			sub = if attacking then "DEFEND THE BOMB" elseif defending then "DEFUSE IT" else nil,
			tone = if attacking then "Friendly" elseif defending then "Enemy" else "Accent",
			duration = 2.6,
		}
	elseif kind == "BombDefused" then
		return {
			title = "BOMB DEFUSED",
			sub = nameOf(data.userId),
			tone = if defending then "Friendly" elseif attacking then "Enemy" else "Accent",
			duration = 2.2,
		}
	elseif kind == "BombDetonated" then
		local site = str(data.site)
		return {
			title = "BOMB DETONATED",
			sub = if site then "SITE " .. site .. " DESTROYED" else nil,
			tone = if attacking then "Friendly" elseif defending then "Enemy" else "Accent",
			duration = 2.2,
		}
	elseif kind == "RoundStart" then
		local number = if type(data.number) == "number" then data.number else nil
		local atk = str(data.attackers) or ctx.attackers
		local side = if myTeam and atk then (if myTeam == atk then "ATTACK" else "DEFEND") else nil
		local title = if number then "ROUND " .. tostring(number) else "NEW ROUND"
		if side then
			title ..= " · " .. side
		end
		return {
			title = title,
			sub = if side == "ATTACK" then "PLANT THE BOMB OR ELIMINATE THE ENEMY"
				elseif side == "DEFEND" then "PROTECT BOTH SITES"
				else nil,
			tone = "Accent",
			duration = 2.6,
		}
	elseif kind == "RoundLive" then
		return { title = "GO", sub = nil, tone = "Accent", duration = 1 }
	elseif kind == "RoundEnd" then
		local winner = str(data.winner)
		local reason = REASONS[str(data.reason) or ""]
		if not myTeam or not winner then
			return { title = "ROUND OVER", sub = reason, tone = "Neutral", duration = 2.8 }
		end
		local won = winner == myTeam
		return { title = if won then "ROUND WON" else "ROUND LOST", sub = reason, tone = if won then "Friendly" else "Enemy", duration = 2.8 }
	elseif kind == "SidesSwapped" then
		return { title = "SIDES SWAPPED", sub = "HALFTIME", tone = "Accent", duration = 2.4 }
	elseif kind == "TagConfirmed" then
		-- only the collector gets a banner; teammates' pickups would spam the centre of the screen
		if data.userId == me then
			return { title = "KILL CONFIRMED", sub = nil, tone = "Friendly", duration = 1.2 }
		end
		return nil
	elseif kind == "TagDenied" then
		if data.userId == me then
			return { title = "KILL DENIED", sub = nil, tone = "Friendly", duration = 1.2 }
		end
		return nil
	end
	return nil
end

return ObjectiveRules
