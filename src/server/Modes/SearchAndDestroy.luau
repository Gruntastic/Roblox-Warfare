--!strict
-- Search and Destroy: rounds with no respawns. Attackers carry one bomb to site A or B and plant
-- it; defenders stop the plant or defuse it. A round also ends when one side is wiped out, or when
-- the clock runs out before a plant (defenders win). First to `roundsToWin`; sides swap every
-- `swapSidesAfter` rounds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Objectives = require(ReplicatedStorage.Shared.Pure.Objectives)
local MatchRules = require(ReplicatedStorage.Shared.Pure.MatchRules)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local ModesConfig = require(ReplicatedStorage.Shared.Config.Modes)
local Types = require(ReplicatedStorage.Shared.Types)
local ModeTypes = require(script.Parent.ModeTypes)
local Zones = require(script.Parent.Zones)

local PICKUP_RADIUS = 4
local DEFUSE_RADIUS = 6
local MAX_ACTION_DRIFT = 3 -- studs a planter / defuser may move before the action cancels
local PRE_ROUND = ModesConfig.Match.PreMatchCountdown

local SearchAndDestroy = {}

type Phase = "Pre" | "Live" | "Post"
type Action = { player: Player, kind: "Plant" | "Defuse", endsAt: number, origin: Vector3, site: string? }

function SearchAndDestroy.new(): ModeTypes.Impl
	local sites: { Zones.Zone } = {}
	local attackBase = "Sable"
	local teamA, teamB = "Sable", "Talon"
	local round = 1
	local wins: { [string]: number } = {}
	local attackers, defenders = "Sable", "Talon"
	local phase: Phase = "Pre"
	local phaseEndsAt = 0
	local started: { [string]: number } = {}
	local lastWinner: string? = nil
	local lastReason: string? = nil

	local bombState: string = "None"
	local carrier: Player? = nil
	local bombPos: Vector3? = nil
	local bombSite: string? = nil
	local explodesAt: number? = nil
	local bombPart: BasePart? = nil -- dropped / planted, in workspace
	local carriedPart: BasePart? = nil -- welded to the carrier
	local action: Action? = nil

	local floorParams = RaycastParams.new()
	floorParams.FilterType = Enum.RaycastFilterType.Include

	local function floorUnder(pos: Vector3): Vector3
		local hit = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -40, 0), floorParams)
		return if hit then hit.Position else pos - Vector3.new(0, 3, 0)
	end

	local function clearBombParts()
		if bombPart then
			bombPart:Destroy()
			bombPart = nil
		end
		if carriedPart then
			carriedPart:Destroy()
			carriedPart = nil
		end
	end

	local function placeWorldBomb(position: Vector3, state: string)
		clearBombParts()
		local p = Instance.new("Part")
		p.Name = "Bomb"
		p.Size = Vector3.new(1.6, 1, 2.4)
		p.Material = Enum.Material.Metal
		p.Color = Color3.fromRGB(60, 62, 58)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0))
		p:SetAttribute("State", state)
		local light = Instance.new("PointLight")
		light.Color = if state == "Planted" then Color3.fromRGB(255, 70, 50) else Color3.fromRGB(255, 200, 90)
		light.Range = 8
		light.Brightness = 2
		light.Parent = p
		p.Parent = workspace
		bombPart = p
	end

	local function giveBomb(ctx: ModeTypes.Context, player: Player)
		clearBombParts()
		bombState = "Carried"
		carrier = player
		bombPos = nil
		local character = player.Character
		local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
		if torso then
			local p = Instance.new("Part")
			p.Name = "CarriedBomb"
			p.Size = Vector3.new(1.2, 0.8, 1.6)
			p.Material = Enum.Material.Metal
			p.Color = Color3.fromRGB(60, 62, 58)
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CFrame = torso.CFrame * CFrame.new(0, 0.2, 0.9)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = p
			weld.Parent = p
			p.Parent = character
			carriedPart = p
		end
		ctx.event("BombPickedUp", { userId = player.UserId })
		ctx.changed()
	end

	local function dropBomb(ctx: ModeTypes.Context, at: Vector3)
		local pos = floorUnder(at)
		bombState = "Dropped"
		carrier = nil
		bombPos = pos
		placeWorldBomb(pos, "Dropped")
		ctx.event("BombDropped", { position = pos })
		ctx.changed()
	end

	local function cancelAction(ctx: ModeTypes.Context)
		if action then
			action = nil
			ctx.changed()
		end
	end

	local function aliveCounts(ctx: ModeTypes.Context): { [string]: number }
		local counts = { [teamA] = 0, [teamB] = 0 }
		for _, p in ctx.participants() do
			local team = ctx.teamOf(p)
			if team and ctx.isAlive(p) then
				counts[team] = (counts[team] or 0) + 1
			end
		end
		return counts
	end

	local function goLive(ctx: ModeTypes.Context)
		phase = "Live"
		phaseEndsAt = ctx.now() + (ctx.mode.roundTime or 150)
		ctx.setClock(phaseEndsAt)
		started = aliveCounts(ctx)
		ctx.setFrozen(false)
		-- hand the bomb to a random living attacker
		local candidates = {}
		for _, p in ctx.participants() do
			if ctx.teamOf(p) == attackers and ctx.isAlive(p) then
				table.insert(candidates, p)
			end
		end
		bombState = "None"
		carrier = nil
		if #candidates > 0 then
			giveBomb(ctx, candidates[math.random(1, #candidates)])
		end
		ctx.event("RoundLive", { number = round })
		ctx.changed()
	end

	local function beginRound(ctx: ModeTypes.Context)
		local nextAttackers = Objectives.attackersFor(round, attackBase, if attackBase == teamA then teamB else teamA, ctx.mode.swapSidesAfter or 3)
		if round > 1 and nextAttackers ~= attackers then
			ctx.event("SidesSwapped", {})
		end
		attackers = nextAttackers
		defenders = if attackers == teamA then teamB else teamA
		phase = "Pre"
		phaseEndsAt = ctx.now() + PRE_ROUND
		ctx.setClock(phaseEndsAt)
		clearBombParts()
		bombState, carrier, bombPos, bombSite, explodesAt = "None", nil, nil, nil, nil
		action = nil
		ctx.setFrozen(true)
		ctx.respawnAll()
		ctx.event("RoundStart", { number = round, attackers = attackers })
		ctx.changed()
	end

	local function endRound(ctx: ModeTypes.Context, winner: string, reason: string)
		phase = "Post"
		phaseEndsAt = ctx.now() + (ctx.mode.roundPause or 6)
		ctx.setClock(0)
		action = nil
		wins[winner] = (wins[winner] or 0) + 1
		ctx.setTeamScore(winner, wins[winner])
		lastWinner, lastReason = winner, reason
		if carriedPart then
			carriedPart:Destroy()
			carriedPart = nil
		end
		for _, p in ctx.participants() do
			if ctx.teamOf(p) == winner then
				ctx.award(p, 0, "Round Win", Progression.AccountXP.RoundWin)
			end
		end
		ctx.event("RoundEnd", { winner = winner, reason = reason })
		ctx.changed()
	end

	local function matchDecided(ctx: ModeTypes.Context): string?
		local need = ctx.mode.roundsToWin or 4
		for team, n in wins do
			if n >= need then
				return team
			end
		end
		return nil
	end

	local function completeAction(ctx: ModeTypes.Context, a: Action)
		action = nil
		local root = ctx.root(a.player)
		if a.kind == "Plant" then
			local pos = floorUnder(if root then root.Position else a.origin)
			bombState = "Planted"
			carrier = nil
			bombPos = pos
			bombSite = a.site
			explodesAt = ctx.now() + (ctx.mode.bombTimer or 40)
			ctx.setClock(explodesAt :: number)
			placeWorldBomb(pos, "Planted")
			ctx.award(a.player, MatchRules.POINTS.Plant, "Bomb Planted", Progression.AccountXP.Plant)
			ctx.event("BombPlanted", { site = a.site, userId = a.player.UserId })
		else
			bombState = "Defused"
			explodesAt = nil
			if bombPart then
				bombPart:SetAttribute("State", "Defused")
			end
			ctx.award(a.player, MatchRules.POINTS.Defuse, "Bomb Defused", Progression.AccountXP.Defuse)
			ctx.event("BombDefused", { userId = a.player.UserId })
		end
		ctx.changed()
	end

	local function detonate(ctx: ModeTypes.Context)
		bombState = "Detonated"
		explodesAt = nil
		if bombPos then
			local boom = Instance.new("Explosion")
			boom.Position = bombPos + Vector3.new(0, 1, 0)
			boom.BlastRadius = 18
			boom.BlastPressure = 0 -- visual only: damage stays in CombatService
			boom.DestroyJointRadiusPercent = 0
			boom.Parent = workspace
		end
		if bombPart then
			bombPart:Destroy()
			bombPart = nil
		end
		ctx.event("BombDetonated", { site = bombSite })
		ctx.changed()
	end

	local function siteAt(pos: Vector3): Zones.Zone?
		for _, s in sites do
			if Zones.contains(s, pos) then
				return s
			end
		end
		return nil
	end

	local impl: ModeTypes.Impl
	impl = {
		kind = "SnD",

		prepare = function(ctx)
			sites = Zones.collect(ctx.map, "BombSite")
			if #sites == 0 then
				warn("[SearchAndDestroy] map has no BombSite objectives")
			end
			teamA, teamB = ctx.teams[1], ctx.teams[2]
			local base = ctx.map:GetAttribute("SnDAttackBase")
			attackBase = if base == teamB then teamB else teamA
			local geometry = ctx.map:FindFirstChild("Geometry")
			floorParams.FilterDescendantsInstances = if geometry then { geometry } else { ctx.map }
			round = 1
			wins = { [teamA] = 0, [teamB] = 0 }
			attackers = attackBase
			defenders = if attackers == teamA then teamB else teamA
			phase = "Pre"
			phaseEndsAt = 0
			ctx.setClock(0)
			ctx.changed()
		end,

		start = function(ctx)
			-- the shared frozen countdown already ran: round 1 goes live straight away
			goLive(ctx)
		end,

		step = function(ctx, _dt)
			local now = ctx.now()
			if phase == "Pre" then
				if phaseEndsAt > 0 and now >= phaseEndsAt then
					goLive(ctx)
				end
				return
			elseif phase == "Post" then
				if now >= phaseEndsAt and not matchDecided(ctx) then
					round += 1
					beginRound(ctx)
				end
				return
			end

			-- Live: plant / defuse in progress
			local a = action
			if a then
				local root = ctx.root(a.player)
				if not root or (root.Position - a.origin).Magnitude > MAX_ACTION_DRIFT then
					cancelAction(ctx)
				elseif now >= a.endsAt then
					completeAction(ctx, a)
				end
			end

			-- a dropped bomb is picked up by any living attacker who walks over it
			if bombState == "Dropped" and bombPos then
				for _, p in ctx.participants() do
					local root = ctx.root(p)
					if root and ctx.teamOf(p) == attackers then
						local offset = root.Position - (bombPos :: Vector3)
						if Vector3.new(offset.X, 0, offset.Z).Magnitude <= PICKUP_RADIUS and math.abs(offset.Y) <= 5 then
							giveBomb(ctx, p)
							break
						end
					end
				end
			end

			if bombState == "Planted" and explodesAt and now >= explodesAt then
				detonate(ctx)
			end

			local alive = aliveCounts(ctx)
			local winner, reason = Objectives.roundOutcome({
				attackers = attackers,
				defenders = defenders,
				alive = alive,
				started = started,
				bomb = bombState,
				timeUp = now >= phaseEndsAt,
			})
			if winner then
				endRound(ctx, winner, reason :: string)
			end
		end,

		onKilled = function(ctx, info)
			if action and action.player == info.victim then
				cancelAction(ctx)
			end
			if bombState == "Carried" and carrier == info.victim then
				local character = info.victim.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local at = info.position or (root and root.Position)
				if at then
					dropBomb(ctx, at)
				end
			end
			ctx.changed() -- alive counts changed
		end,

		onPlayerRemoving = function(ctx, player)
			if action and action.player == player then
				cancelAction(ctx)
			end
			if bombState == "Carried" and carrier == player then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					dropBomb(ctx, root.Position)
				else
					bombState, carrier = "None", nil
					ctx.changed()
				end
			end
		end,

		onInteract = function(ctx, player, holding)
			if not holding then
				if action and action.player == player then
					cancelAction(ctx)
				end
				return
			end
			if phase ~= "Live" or action then
				return
			end
			local root = ctx.root(player)
			local team = ctx.teamOf(player)
			if not root or not team then
				return
			end
			local now = ctx.now()
			if team == attackers and bombState == "Carried" and carrier == player then
				local site = siteAt(root.Position)
				if site then
					action = { player = player, kind = "Plant", endsAt = now + (ctx.mode.plantTime or 5) * ctx.objectiveTimeMultiplier(player), origin = root.Position, site = site.id }
					ctx.changed()
				end
			elseif team == defenders and bombState == "Planted" and bombPos then
				if (root.Position - (bombPos :: Vector3)).Magnitude <= DEFUSE_RADIUS then
					action = { player = player, kind = "Defuse", endsAt = now + (ctx.mode.defuseTime or 7) * ctx.objectiveTimeMultiplier(player), origin = root.Position }
					ctx.changed()
				end
			end
		end,

		isOver = function(ctx)
			return phase == "Post" and ctx.now() >= phaseEndsAt and matchDecided(ctx) ~= nil
		end,

		winner = function(ctx)
			return matchDecided(ctx)
		end,

		allowRespawn = function(_ctx, _player)
			-- only during the frozen pre-round (late joiners); never mid-round
			return phase == "Pre"
		end,

		spawnTag = function(_ctx, team)
			local other = if attackBase == teamA then teamB else teamA
			return if team == attackers then attackBase else other
		end,

		payload = function(ctx): Types.ObjectivePayload
			local list = {}
			for _, s in sites do
				table.insert(list, Zones.state(s))
			end
			local a = action
			return {
				kind = "SnD",
				zones = list,
				round = {
					number = round,
					wins = table.clone(wins),
					roundsToWin = ctx.mode.roundsToWin or 4,
					attackers = attackers,
					alive = aliveCounts(ctx),
					live = phase == "Live",
					endsAt = phaseEndsAt,
					lastWinner = lastWinner,
					lastReason = lastReason :: any,
				},
				bomb = {
					state = bombState :: any,
					carrierUserId = if carrier then carrier.UserId else nil,
					position = bombPos,
					site = bombSite,
					explodesAt = explodesAt,
					actionUserId = if a then a.player.UserId else nil,
					actionKind = if a then a.kind else nil,
					actionEndsAt = if a then a.endsAt else nil,
				},
			}
		end,

		stop = function(_ctx)
			clearBombParts()
			action = nil
			carrier = nil
		end,
	}
	return impl
end

return SearchAndDestroy
