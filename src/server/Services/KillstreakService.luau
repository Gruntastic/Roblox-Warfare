--!strict
-- Killstreaks (Phase 5): per-player streak state, activation and every streak's server effect.
-- Contract: docs/PHASE5_CONTRACT.md. MatchService tells this service when a match starts and ends,
-- who is on which team and when a player spawns; CombatService reports kills (Killed) and bullets
-- that hit a sentry (damageObject). All damage goes through CombatService.applyDamage with the
-- weapon id "Streak:<id>", so friendly fire, self damage and Blast Guard are handled there too.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Killstreaks = require(Shared.Config.Killstreaks)
local PerkRules = require(Shared.Pure.PerkRules)
local StreakRules = require(Shared.Pure.StreakRules)
local CombatService = require(script.Parent.CombatService)
local ProgressionService = require(script.Parent.ProgressionService)
local KillstreakMath = require(script.Parent.KillstreakMath)

local ACTIVATE_INTERVAL = 0.5 -- rate limit on ActivateStreak
local SENTRY_STEP = 0.05 -- sentry think rate
local SENTRY_SIZE = Vector3.new(2.4, 3.2, 2.4) -- footprint checked for room when placing
local STREAK_PREFIX = "Streak:"

type PlayerStreaks = {
	state: StreakRules.State,
	equipped: { string },
	discount: number,
	lastActivate: number,
}

-- One running killstreak. `finish` cancels its threads, disconnects and destroys what it made.
type Effect = {
	id: string,
	owner: Player,
	side: string, -- KillstreakMath.side of the owner at activation
	team: string?, -- owner's team (nil in FFA)
	endsAt: number, -- server time; math.huge for effects that end on their own (shells)
	threads: { thread },
	instances: { Instance },
	connections: { RBXScriptConnection },
	onEnd: (() -> ())?,
	ended: boolean,
}

type Sentry = { effect: Effect, health: number, model: Model }

local KillstreakService = {
	-- Set by MatchService. Defaults keep everything inert outside a match.
	rules = {
		teamOf = function(_player: Player): string?
			return nil
		end,
		teamMode = function(): boolean
			return false
		end,
		teams = {} :: { string },
		-- the match is Playing and the player is deployed in it
		canUse = function(_player: Player): boolean
			return false
		end,
	},
}

local players: { [Player]: PlayerStreaks } = {}
local effects: { Effect } = {}
local sentries: { [Instance]: Sentry } = {}
local matchActive = false
local folder: Folder? = nil
local geometryParams = RaycastParams.new() -- map geometry only (aim, line of sight, floors)
geometryParams.FilterType = Enum.RaycastFilterType.Include
geometryParams.IgnoreWater = true
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function streakFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local existing = workspace:FindFirstChild("Streaks")
	local newFolder = if existing and existing:IsA("Folder") then existing else Instance.new("Folder")
	newFolder.Name = "Streaks"
	newFolder.Parent = workspace
	folder = newFolder
	return newFolder
end

local function sideOf(player: Player): string?
	local rules = KillstreakService.rules
	return KillstreakMath.side(rules.teamMode(), rules.teamOf(player), player.UserId)
end

local function torsoOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")) :: BasePart?
end

-- Living players in the match on a side other than `side`.
local function livingEnemiesOf(side: string): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		local s = sideOf(p)
		if s ~= nil and s ~= side and CombatService.isAlive(p) then
			table.insert(list, p)
		end
	end
	return list
end

local function payload(ps: PlayerStreaks): Types.StreakStatePayload
	local equipped = {}
	for _, id in ps.equipped do
		table.insert(equipped, { id = id, cost = StreakRules.cost(id, ps.discount) })
	end
	local nextId, nextAt = StreakRules.nextUp(ps.state, ps.equipped, ps.discount)
	return { count = ps.state.count, equipped = equipped, ready = table.clone(ps.state.ready), nextId = nextId, nextAt = nextAt }
end

local function sendState(player: Player)
	local ps = players[player]
	if ps and player.Parent then
		Net.event("StreakState"):FireClient(player, payload(ps))
	end
end

local function event(kind: string, data: { [string]: any })
	Net.event("StreakEvent"):FireAllClients(kind, data)
end

-- Effects -------------------------------------------------------------------------------------

local function finish(effect: Effect)
	if effect.ended then
		return
	end
	effect.ended = true
	local i = table.find(effects, effect)
	if i then
		table.remove(effects, i)
	end
	local current = coroutine.running()
	for _, t in effect.threads do
		if t ~= current then
			pcall(task.cancel, t)
		end
	end
	for _, c in effect.connections do
		c:Disconnect()
	end
	for _, inst in effect.instances do
		sentries[inst] = nil
		inst:Destroy()
	end
	if effect.onEnd then
		effect.onEnd()
	end
end

local function newEffect(id: string, owner: Player, side: string, duration: number?): Effect
	local effect: Effect = {
		id = id,
		owner = owner,
		side = side,
		team = KillstreakService.rules.teamOf(owner),
		endsAt = if duration then now() + duration else math.huge,
		threads = {},
		instances = {},
		connections = {},
		onEnd = nil,
		ended = false,
	}
	table.insert(effects, effect)
	if duration then
		table.insert(effect.threads, task.delay(duration, finish, effect))
	end
	return effect
end

-- An enemy effect of kind `id` currently covers `side` (FFA: every other player is an enemy).
local function underEnemy(id: string, side: string?): boolean
	if side == nil then
		return false
	end
	for _, e in effects do
		if e.id == id and e.side ~= side and not e.ended then
			return true
		end
	end
	return false
end

-- Geometry -----------------------------------------------------------------------------------

local function dropToGround(pos: Vector3): Vector3
	local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -400, 0), geometryParams)
	return if hit then hit.Position else pos
end

-- Contract: aim from the server head along the (validated) direction against map geometry only;
-- with no hit, the point at max range dropped to the ground.
local function aimPoint(from: Vector3, dir: Vector3, maxRange: number): Vector3
	local hit = workspace:Raycast(from, dir * maxRange, geometryParams)
	if hit then
		return hit.Position
	end
	local far = from + dir * maxRange
	local down = workspace:Raycast(far, Vector3.new(0, -1000, 0), geometryParams)
	return if down then down.Position else far
end

local function canSee(from: Vector3, to: Vector3): boolean
	return workspace:Raycast(from, to - from, geometryParams) == nil
end

-- Radial damage to every enemy of the owner whose torso the blast can see.
local function explode(effect: Effect, center: Vector3, radius: number, damage: number)
	event("Impact", { streakId = effect.id, position = center, radius = radius })
	if not effect.owner.Parent then
		return
	end
	local from = center + Vector3.new(0, 0.5, 0)
	for _, victim in livingEnemiesOf(effect.side) do
		local torso = torsoOf(victim)
		if torso then
			local d = (torso.Position - center).Magnitude
			local amount = KillstreakMath.falloff(damage, radius, d)
			if amount > 0 and canSee(from, torso.Position) then
				CombatService.applyDamage(victim, effect.owner, amount, STREAK_PREFIX .. effect.id, false, center)
			end
		end
	end
end

-- Shells / blasts landing at `positions`, announced with one Incoming event.
local function barrage(effect: Effect, positions: { Vector3 }, params: { [string]: number })
	local delays = KillstreakMath.impactDelays(params.warning, params.interval, #positions)
	event("Incoming", {
		streakId = effect.id,
		team = effect.team,
		ownerUserId = effect.owner.UserId,
		positions = positions,
		radius = params.radius,
		impactAt = now() + (delays[1] or 0),
		interval = params.interval,
	})
	for i, pos in positions do
		table.insert(effect.threads, task.delay(delays[i], function()
			if effect.ended then
				return
			end
			explode(effect, pos, params.radius, params.damage)
			if i == #positions then
				finish(effect)
			end
		end))
	end
	if #positions == 0 then
		finish(effect)
	end
end

-- Sentry ---------------------------------------------------------------------------------------

local function sentryPart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = true -- bullets hit it (CombatService routes the damage here)
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Where a sentry would stand in front of the owner, or nil (no floor, or no room).
local function sentryPlacement(player: Player, params: { [string]: number }): CFrame?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local forward = KillstreakMath.flatDirection(root.CFrame.LookVector)
	local spot = root.Position + forward * params.placeDistance
	-- the way from the owner to the spot must be open
	if not canSee(root.Position, spot + forward * (SENTRY_SIZE.X / 2)) then
		return nil
	end
	local floor = workspace:Raycast(spot + Vector3.new(0, 1, 0), Vector3.new(0, -8, 0), geometryParams)
	if not floor or floor.Normal.Y < 0.7 then
		return nil
	end
	local base = CFrame.lookAt(floor.Position, floor.Position + forward)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = geometryParams.FilterDescendantsInstances
	-- the box starts a little above the floor so the floor itself does not count
	local box = base * CFrame.new(0, SENTRY_SIZE.Y / 2 + 0.3, 0)
	if #workspace:GetPartBoundsInBox(box, SENTRY_SIZE - Vector3.new(0.2, 0.6, 0.2), overlap) > 0 then
		return nil
	end
	local others = OverlapParams.new()
	others.FilterType = Enum.RaycastFilterType.Include
	others.FilterDescendantsInstances = { streakFolder() }
	if #workspace:GetPartBoundsInBox(box, SENTRY_SIZE, others) > 0 then
		return nil
	end
	return base
end

local function buildSentry(effect: Effect, base: CFrame, health: number): (Model, BasePart, BasePart)
	local model = Instance.new("Model")
	model.Name = "Sentry"
	model:SetAttribute("Team", effect.team or "")
	model:SetAttribute("OwnerUserId", effect.owner.UserId)
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", health)
	local dark = Color3.fromRGB(52, 56, 50)
	local olive = Color3.fromRGB(84, 92, 70)
	sentryPart("Tripod", Vector3.new(2.2, 0.4, 2.2), base * CFrame.new(0, 0.2, 0), dark, Enum.Material.Metal, model)
	sentryPart("Post", Vector3.new(0.5, 1.6, 0.5), base * CFrame.new(0, 1.2, 0), dark, Enum.Material.Metal, model)
	local head = sentryPart("Head", Vector3.new(1.4, 1, 1.8), base * CFrame.new(0, 2.5, 0), olive, Enum.Material.Metal, model)
	local barrel = sentryPart("Barrel", Vector3.new(0.3, 0.3, 1.6), head.CFrame * CFrame.new(0, 0.1, -1.6), dark, Enum.Material.Metal, model)
	local lamp = Instance.new("PointLight")
	lamp.Color = Color3.fromRGB(255, 80, 60)
	lamp.Range = 6
	lamp.Brightness = 1
	lamp.Parent = head
	-- Phase 7: health bar over the head (fill follows the Health attribute)
	local bill = Instance.new("BillboardGui")
	bill.Name = "HealthBar"
	bill.Size = UDim2.fromOffset(60, 7)
	bill.StudsOffset = Vector3.new(0, 1.6, 0)
	bill.AlwaysOnTop = false
	bill.MaxDistance = 120
	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 22)
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(1, 1)
	back.Parent = bill
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(255, 176, 32)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	fill.Parent = back
	bill.Parent = head
	model:GetAttributeChangedSignal("Health"):Connect(function()
		local hp, max = model:GetAttribute("Health"), model:GetAttribute("MaxHealth")
		if type(hp) == "number" and type(max) == "number" and max > 0 then
			fill.Size = UDim2.fromScale(math.clamp(hp / max, 0, 1), 1)
		end
	end)
	model.PrimaryPart = head
	model.Parent = streakFolder()
	return model, head, barrel
end

local function sentryDestroyedVisual(pos: Vector3)
	local boom = Instance.new("Explosion")
	boom.Position = pos
	boom.BlastRadius = 6
	boom.BlastPressure = 0 -- visual only: damage stays in CombatService
	boom.DestroyJointRadiusPercent = 0
	boom.Parent = workspace
end

local function runSentry(effect: Effect, base: CFrame, params: { [string]: number })
	local model, head, barrel = buildSentry(effect, base, params.health)
	table.insert(effect.instances, model)
	sentries[model] = { effect = effect, health = params.health, model = model }
	local pivot = head.Position
	local barrelOffset = head.CFrame:ToObjectSpace(barrel.CFrame)
	local interval = KillstreakMath.fireInterval(params.rpm)
	table.insert(effect.threads, task.spawn(function()
		local target: Player? = nil
		local lockedAt = 0
		local nextShot = 0
		while not effect.ended and model.Parent do
			task.wait(SENTRY_STEP)
			if effect.ended then
				break
			end
			local muzzle = barrel.CFrame * Vector3.new(0, 0, -barrel.Size.Z / 2)
			-- keep the current target while it stays valid; otherwise take the nearest one
			local best, bestDist = nil, params.range
			for _, p in livingEnemiesOf(effect.side) do
				local torso = torsoOf(p)
				if torso then
					local d = (torso.Position - pivot).Magnitude
					if d <= params.range and canSee(pivot, torso.Position) then
						if p == target then
							best, bestDist = p, -1
						elseif d < bestDist then
							best, bestDist = p, d
						end
					end
				end
			end
			local t = os.clock()
			if best ~= target then
				target = best
				lockedAt = t
			end
			local torso = target and torsoOf(target)
			if target and torso then
				local look = Vector3.new(torso.Position.X, pivot.Y, torso.Position.Z)
				if (look - pivot).Magnitude > 0.1 then
					head.CFrame = CFrame.lookAt(pivot, look)
					barrel.CFrame = head.CFrame * barrelOffset
				end
				local perks = CombatService.perksOf(target)
				local lock = KillstreakMath.lockOnTime(params, perks ~= nil and perks.ghost)
				if t - lockedAt >= lock and t >= nextShot and effect.owner.Parent then
					nextShot = t + interval
					local hitPos = torso.Position
					Net.event("Tracer"):FireAllClients(effect.owner.UserId, muzzle, hitPos)
					CombatService.applyDamage(target, effect.owner, params.damage, STREAK_PREFIX .. effect.id, false, muzzle)
				end
			end
		end
	end))
end

-- Bullets (CombatService) hitting a sentry. Only enemies of its owner damage it.
local function damageSentry(attacker: Player, object: Instance, amount: number)
	local sentry = sentries[object]
	if not sentry or sentry.effect.ended or amount <= 0 then
		return
	end
	local side = sideOf(attacker)
	if side == nil or side == sentry.effect.side then
		return
	end
	sentry.health = math.max(0, sentry.health - math.floor(amount))
	sentry.model:SetAttribute("Health", sentry.health)
	local destroyed = sentry.health <= 0
	Net.event("HitConfirm"):FireClient(attacker, { damage = math.floor(amount), headshot = false, killed = false })
	if destroyed then
		local pp = sentry.model.PrimaryPart
		if pp then
			sentryDestroyedVisual(pp.Position)
		end
		finish(sentry.effect)
	end
end

-- Streak runners ------------------------------------------------------------------------------

local function runRecon(effect: Effect, def: Killstreaks.StreakDef)
	local interval = def.params.pingInterval
	local teamMode = KillstreakService.rules.teamMode()
	table.insert(effect.threads, task.spawn(function()
		while not effect.ended and now() < effect.endsAt do
			-- suppressed while the owner's side is under an enemy Counter-Recon or Blackout
			if effect.owner.Parent and not underEnemy("CounterRecon", effect.side) and not underEnemy("Blackout", effect.side) then
				local targets = {}
				for _, p in livingEnemiesOf(effect.side) do
					local perks = CombatService.perksOf(p)
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root and not (perks and perks.ghost) then
						table.insert(targets, { userId = p.UserId, position = root.Position })
					end
				end
				local ping: Types.PingPayload = { targets = targets, expiresAt = now() + interval }
				if teamMode then
					for _, p in Players:GetPlayers() do
						if KillstreakService.rules.teamOf(p) == effect.team then
							Net.event("Ping"):FireClient(p, ping)
						end
					end
				else
					Net.event("Ping"):FireClient(effect.owner, ping)
				end
			end
			task.wait(interval)
		end
	end))
end

-- Counter-Recon and Blackout: timed effects on the enemy side with start / end banners.
local function runJam(effect: Effect, kind: string)
	local victimTeam = KillstreakMath.victimTeam(KillstreakService.rules.teams, effect.team)
	event(kind, { team = victimTeam, endsAt = effect.endsAt, ownerUserId = effect.owner.UserId })
	effect.onEnd = function()
		event("EffectEnded", { streakId = effect.id, team = victimTeam, ownerUserId = effect.owner.UserId })
	end
end

-- Activation -------------------------------------------------------------------------------------

local function onActivate(player: Player, id: any, aim: any)
	if type(id) ~= "string" then
		return
	end
	local ps = players[player]
	if not ps or not matchActive then
		return
	end
	local t = os.clock()
	if t - ps.lastActivate < ACTIVATE_INTERVAL then
		return
	end
	ps.lastActivate = t
	local def = Killstreaks.byId[id]
	if not def or not table.find(ps.state.ready, id) then
		return
	end
	if not KillstreakService.rules.canUse(player) or not CombatService.isAlive(player) then
		return
	end
	local side = sideOf(player)
	if not side then
		return
	end
	if underEnemy("Blackout", side) then
		Net.event("Notify"):FireClient(player, "Killstreaks grounded by an enemy Blackout", "Warning")
		return
	end
	local params = def.params
	local point: Vector3? = nil
	local dir: Vector3? = nil
	if def.targeted then
		dir = KillstreakMath.aimDirection(aim)
		local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
		if not dir or not head then
			return
		end
		point = aimPoint(head.Position, dir, params.maxRange)
	end
	local placement: CFrame? = nil
	if id == "SentryGun" then
		placement = sentryPlacement(player, params)
		if not placement then
			-- refused before taking it, so the reward stays ready
			Net.event("Notify"):FireClient(player, "No room to place the sentry here", "Warning")
			return
		end
	end

	if not StreakRules.take(ps.state, id) then
		return
	end
	sendState(player)
	event("Activated", { streakId = id, ownerUserId = player.UserId, ownerName = player.DisplayName, team = KillstreakService.rules.teamOf(player) })

	if id == "ReconDrone" then
		runRecon(newEffect(id, player, side, def.duration), def)
	elseif id == "CounterRecon" then
		runJam(newEffect(id, player, side, def.duration), "Jammed")
	elseif id == "Blackout" then
		runJam(newEffect(id, player, side, def.duration), "Blackout")
	elseif id == "SentryGun" and placement then
		runSentry(newEffect(id, player, side, def.duration), placement, params)
	elseif id == "MortarBarrage" and point then
		local positions = {}
		for i = 1, params.shells do
			positions[i] = dropToGround(KillstreakMath.scatter(point, params.scatter, rng:NextNumber(), rng:NextNumber()))
		end
		barrage(newEffect(id, player, side, nil), positions, params)
	elseif id == "StrikeRun" and point and dir then
		local positions = {}
		for i, p in KillstreakMath.strikeLine(point, dir, params.blasts, params.spacing) do
			positions[i] = dropToGround(p)
		end
		barrage(newEffect(id, player, side, nil), positions, params)
	end
end

-- Kills and deaths ------------------------------------------------------------------------------

local function onKilled(info: CombatService.KillInfo)
	if not matchActive then
		return
	end
	local victim = players[info.victim]
	if victim then
		StreakRules.onDeath(victim.state)
		sendState(info.victim)
	end
	local killer = info.killer
	local ps = if killer then players[killer] else nil
	if not killer or not ps or killer == info.victim or not KillstreakService.rules.canUse(killer) then
		return
	end
	local weaponId = info.weaponId
	local byStreak = weaponId ~= nil and string.sub(weaponId, 1, #STREAK_PREFIX) == STREAK_PREFIX
	local earned = StreakRules.onKill(ps.state, ps.equipped, ps.discount, byStreak)
	for _, id in earned do
		Net.event("StreakEvent"):FireClient(killer, "Earned", { streakId = id })
		ProgressionService.recordEvent(killer, { kind = "streakEarned" })
	end
	sendState(killer)
end

-- Public API (MatchService) --------------------------------------------------------------------

local function clearEffects()
	for i = #effects, 1, -1 do
		finish(effects[i])
	end
	table.clear(effects)
	table.clear(sentries)
	local f = workspace:FindFirstChild("Streaks")
	if f then
		f:ClearAllChildren()
	end
end

-- A new match: clears every player's streak state and all effects. `map` is the loaded map;
-- its Geometry folder is what aim, floors and line of sight are tested against.
function KillstreakService.beginMatch(map: Model?)
	clearEffects()
	table.clear(players)
	local geometry = map and (map:FindFirstChild("Geometry") or map)
	geometryParams.FilterDescendantsInstances = if geometry then { geometry } else {}
	matchActive = true
end

-- The match ended (or errored): every effect, sentry and pending shell is removed.
function KillstreakService.endMatch()
	matchActive = false
	clearEffects()
	table.clear(players)
end

-- Called by MatchService after CombatService.onSpawned, with the same resolved loadout.
function KillstreakService.onSpawned(player: Player, loadout: { perks: { string }, streaks: { string } })
	if not matchActive then
		return
	end
	local ps = players[player]
	if not ps then
		ps = { state = StreakRules.newState(), equipped = {}, discount = 0, lastActivate = 0 }
		players[player] = ps
	end
	ps.equipped = table.clone(loadout.streaks)
	ps.discount = PerkRules.combine(loadout.perks).streakDiscount
	sendState(player)
end

function KillstreakService.init()
	streakFolder()
	CombatService.damageObject = damageSentry
	CombatService.Killed:Connect(onKilled)
	Net.event("ActivateStreak").OnServerEvent:Connect(onActivate)
	Players.PlayerRemoving:Connect(function(player)
		players[player] = nil
		for i = #effects, 1, -1 do
			if effects[i].owner == player then
				finish(effects[i])
			end
		end
	end)
end

function KillstreakService.start() end

return KillstreakService
