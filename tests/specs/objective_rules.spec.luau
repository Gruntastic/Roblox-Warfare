local Loader = require("../lib/Loader")
local T = require("../lib/T")
local R = Loader.load("src/shared/Pure/ObjectiveRules.luau")
local V3 = Loader.roblox.Vector3
local describe, it, expect = T.describe, T.it, T.expect

local function zone(id: string, pos, size, yaw: number?)
	return {
		id = id,
		label = id,
		position = pos,
		size = size,
		yaw = yaw or 0,
		owner = nil,
		capturingTeam = nil,
		progress = 0,
		contested = false,
		active = true,
	}
end

local function snd(bomb, live: boolean?)
	return {
		kind = "SnD",
		zones = {
			zone("A", V3.new(0, 0, 0), V3.new(10, 6, 10)),
			zone("B", V3.new(100, 0, 0), V3.new(10, 6, 10)),
		},
		round = {
			number = 1,
			wins = { Sable = 0, Talon = 0 },
			roundsToWin = 4,
			attackers = "Sable",
			alive = { Sable = 3, Talon = 3 },
			live = if live == nil then true else live,
			endsAt = 0,
		},
		bomb = bomb,
	}
end

describe("ObjectiveRules.insideZone", function()
	it("tests the box footprint with a vertical allowance", function()
		local z = zone("A", V3.new(0, 0, 0), V3.new(10, 6, 4))
		expect(R.insideZone(V3.new(4.9, 3, 1.9), z)).toBeTruthy()
		expect(R.insideZone(V3.new(5.1, 3, 0), z)).toBeFalsy()
		expect(R.insideZone(V3.new(0, 3, 2.1), z)).toBeFalsy()
		expect(R.insideZone(V3.new(0, 30, 0), z)).toBeFalsy()
		expect(R.insideZone(V3.new(0, -2, 0), z)).toBeFalsy()
	end)
	it("respects yaw", function()
		local z = zone("A", V3.new(0, 0, 0), V3.new(10, 6, 2), math.pi / 2)
		-- rotated 90 degrees: the long axis now runs along world Z
		expect(R.insideZone(V3.new(0, 3, 4.5), z)).toBeTruthy()
		expect(R.insideZone(V3.new(4.5, 3, 0), z)).toBeFalsy()
	end)
end)

describe("ObjectiveRules.interactKind", function()
	local inA = V3.new(1, 3, 1)
	it("lets the carrying attacker plant inside a site", function()
		local obj = snd({ state = "Carried", carrierUserId = 1 })
		expect(R.interactKind({ objective = obj, userId = 1, team = "Sable", position = inA, alive = true })).toBe("Plant")
	end)
	it("refuses plant outside a site, for non-carriers, when dead or before the round is live", function()
		local obj = snd({ state = "Carried", carrierUserId = 1 })
		expect(R.interactKind({ objective = obj, userId = 1, team = "Sable", position = V3.new(50, 3, 0), alive = true })).toBe(nil)
		expect(R.interactKind({ objective = obj, userId = 2, team = "Sable", position = inA, alive = true })).toBe(nil)
		expect(R.interactKind({ objective = obj, userId = 1, team = "Sable", position = inA, alive = false })).toBe(nil)
		local frozen = snd({ state = "Carried", carrierUserId = 1 }, false)
		expect(R.interactKind({ objective = frozen, userId = 1, team = "Sable", position = inA, alive = true })).toBe(nil)
	end)
	it("lets a defender within 6 studs defuse, never an attacker", function()
		local obj = snd({ state = "Planted", position = V3.new(0, 0, 0), site = "A" })
		expect(R.interactKind({ objective = obj, userId = 5, team = "Talon", position = V3.new(3, 3, 0), alive = true })).toBe("Defuse")
		expect(R.interactKind({ objective = obj, userId = 5, team = "Talon", position = V3.new(7, 3, 0), alive = true })).toBe(nil)
		expect(R.interactKind({ objective = obj, userId = 1, team = "Sable", position = V3.new(1, 3, 0), alive = true })).toBe(nil)
	end)
	it("keeps the current action while the server reports it", function()
		local obj = snd({ state = "Carried", carrierUserId = 1, actionUserId = 1, actionKind = "Plant", actionEndsAt = 10 })
		expect(R.interactKind({ objective = obj, userId = 1, team = "Sable", position = V3.new(5.2, 3, 0), alive = true })).toBe("Plant")
	end)
	it("refuses while someone else is defusing", function()
		local obj = snd({ state = "Planted", position = V3.new(0, 0, 0), site = "A", actionUserId = 6, actionKind = "Defuse", actionEndsAt = 10 })
		expect(R.interactKind({ objective = obj, userId = 5, team = "Talon", position = V3.new(3, 3, 0), alive = true })).toBe(nil)
	end)
	it("is nil for other modes or missing data", function()
		expect(R.interactKind({ objective = { kind = "Domination", zones = {} }, userId = 1, team = "Sable", position = inA, alive = true })).toBe(nil)
		expect(R.interactKind({ objective = nil, userId = 1, team = "Sable", position = inA, alive = true })).toBe(nil)
		expect(R.interactKind({ objective = snd(nil), userId = 1, team = "Sable", position = inA, alive = true })).toBe(nil)
	end)
end)

describe("ObjectiveRules FFA", function()
	local lines = {
		{ userId = 1, name = "a", kills = 10, score = 900 },
		{ userId = 2, name = "b", kills = 12, score = 1000 },
		{ userId = 3, name = "c", kills = 10, score = 1100 },
		{ userId = 4, name = "d", kills = 3, score = 300 },
	}
	it("places by kills with shared places on ties", function()
		local p, tied = R.place(lines, 2)
		expect(p).toBe(1)
		expect(tied).toBeFalsy()
		p, tied = R.place(lines, 1)
		expect(p).toBe(2)
		expect(tied).toBeTruthy()
		expect((R.place(lines, 3))).toBe(2)
		expect((R.place(lines, 4))).toBe(4)
		expect((R.place(lines, 99))).toBe(nil)
	end)
	it("formats ordinals", function()
		expect(R.ordinal(1)).toBe("1ST")
		expect(R.ordinal(2)).toBe("2ND")
		expect(R.ordinal(3)).toBe("3RD")
		expect(R.ordinal(4)).toBe("4TH")
		expect(R.ordinal(11)).toBe("11TH")
		expect(R.ordinal(12)).toBe("12TH")
		expect(R.ordinal(21)).toBe("21ST")
	end)
	it("sorts by kills then score", function()
		local sorted = R.sortFFA(lines)
		expect(sorted[1].userId).toBe(2)
		expect(sorted[2].userId).toBe(3)
		expect(sorted[3].userId).toBe(1)
		expect(#lines).toBe(4)
		expect(lines[1].userId).toBe(1) -- input untouched
	end)
	it("reports the race against the leader or the runner-up", function()
		local mine, rival, rivalKills, lead = R.ffaRace(lines, 1)
		expect(mine).toBe(10)
		expect(rival).toBe("b")
		expect(rivalKills).toBe(12)
		expect(lead).toBeFalsy()
		mine, rival, rivalKills, lead = R.ffaRace(lines, 2)
		expect(mine).toBe(12)
		expect(rival).toBe("c")
		expect(rivalKills).toBe(10)
		expect(lead).toBeTruthy()
		local _, alone, _, soloLead = R.ffaRace({ lines[1] }, 1)
		expect(alone).toBe(nil)
		expect(soloLead).toBeTruthy()
	end)
end)

describe("ObjectiveRules.cycle", function()
	it("wraps in both directions and recovers from a missing current id", function()
		local ids = { 3, 7, 9 }
		expect(R.cycle(ids, 3, 1)).toBe(7)
		expect(R.cycle(ids, 9, 1)).toBe(3)
		expect(R.cycle(ids, 3, -1)).toBe(9)
		expect(R.cycle(ids, 5, 1)).toBe(3)
		expect(R.cycle(ids, nil, -1)).toBe(9)
		expect(R.cycle(ids, 7, 0)).toBe(7)
		expect(R.cycle({}, 1, 1)).toBe(nil)
	end)
end)

describe("ObjectiveRules relations", function()
	it("classifies teams and hardpoint status", function()
		expect(R.relation(nil, "Sable")).toBe("Neutral")
		expect(R.relation("Sable", "Sable")).toBe("Friendly")
		expect(R.relation("Talon", "Sable")).toBe("Enemy")
		local z = zone("HP1", V3.new(0, 0, 0), V3.new(10, 6, 10))
		expect(R.hardpointStatus(z, "Sable")).toBe("Neutral")
		z.owner = "Talon"
		expect(R.hardpointStatus(z, "Sable")).toBe("Enemy")
		z.contested = true
		expect(R.hardpointStatus(z, "Sable")).toBe("Contested")
		expect(R.hardpointStatus(nil, "Sable")).toBe("Neutral")
	end)
end)

describe("ObjectiveRules.banner", function()
	local ctx = { userId = 1, team = "Sable", attackers = "Sable", nameOf = function(uid)
		return if uid == 2 then "Buddy" else nil
	end }
	it("names flags and sites", function()
		expect(R.banner("ZoneCaptured", { id = "B", team = "Sable" }, ctx).title).toBe("FLAG B CAPTURED")
		expect(R.banner("ZoneCaptured", { id = "B", team = "Talon" }, ctx).tone).toBe("Enemy")
		expect(R.banner("BombPlanted", { site = "A", userId = 1 }, ctx).title).toBe("BOMB PLANTED AT A")
		expect(R.banner("HardpointMoved", { id = "HP2" }, ctx).title).toBe("HARDPOINT MOVED")
		expect(R.banner("HardpointMoved", { id = "HP1" }, { userId = 1, firstHardpoint = true }).title).toBe("HARDPOINT ONLINE")
	end)
	it("announces rounds from the local side", function()
		expect(R.banner("RoundStart", { number = 3, attackers = "Sable" }, ctx).title).toBe("ROUND 3 · ATTACK")
		expect(R.banner("RoundStart", { number = 3, attackers = "Talon" }, ctx).title).toBe("ROUND 3 · DEFEND")
		local won = R.banner("RoundEnd", { winner = "Sable", reason = "Elimination" }, ctx)
		expect(won.title).toBe("ROUND WON")
		expect(won.sub).toBe("ELIMINATION")
		expect(R.banner("RoundEnd", { winner = "Talon", reason = "Defused" }, ctx).title).toBe("ROUND LOST")
		expect(R.banner("SidesSwapped", {}, ctx).title).toBe("SIDES SWAPPED")
	end)
	it("only shows tag banners to the collector", function()
		expect(R.banner("TagConfirmed", { userId = 1, victimUserId = 9 }, ctx).title).toBe("KILL CONFIRMED")
		expect(R.banner("TagDenied", { userId = 1, victimUserId = 2 }, ctx).title).toBe("KILL DENIED")
		expect(R.banner("TagConfirmed", { userId = 2, victimUserId = 9 }, ctx)).toBe(nil)
	end)
	it("hides the bomb carrier from defenders and tolerates junk data", function()
		expect(R.banner("BombPickedUp", { userId = 2 }, ctx).sub).toBe("BUDDY")
		expect(R.banner("BombPickedUp", { userId = 2 }, { userId = 5, team = "Talon", attackers = "Sable" })).toBe(nil)
		expect(R.banner("ZoneCaptured", {}, ctx).title).toBe("FLAG ? CAPTURED")
		expect(R.banner("Unknown", {}, ctx)).toBe(nil)
	end)
end)
