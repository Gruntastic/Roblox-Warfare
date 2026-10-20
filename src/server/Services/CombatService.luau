--!strict
-- Server-authoritative combat: weapon state, fire-rate/ammo validation, lag-compensated
-- hitscan against rewound hitboxes, damage, assists, regeneration and melee.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Signal = require(Shared.Pure.Signal)
local WeaponState = require(Shared.Pure.WeaponState)
local Hitbox = require(Shared.Pure.Hitbox)
local Damage = require(Shared.Pure.Damage)
local WeaponModel = require(Shared.WeaponModel)
local Weapons = require(Shared.Config.Weapons)
local ModesConfig = require(Shared.Config.Modes)

local Match = ModesConfig.Match

local HISTORY_SECONDS = 1.0
local MAX_REWIND = 0.3
local INTERP_ALLOWANCE = 0.05
local MAX_ORIGIN_OFFSET = 8 -- studs between the claimed muzzle origin and the server head position
local MAX_FIRE_EVENTS_PER_SECOND = 30
local ASSIST_WINDOW = 10
local ASSIST_MIN_DAMAGE = 20
local MELEE_RANGE = 6.5
local MELEE_DAMAGE = 135
local MELEE_COOLDOWN = 0.9

type Slot = "Primary" | "Secondary"
type Damager = { amount: number, t: number, weaponId: string? }
type CombatState = {
	weapons: { [string]: WeaponState.WeaponState },
	equipped: Slot,
	lastDamaged: number,
	damagers: { [Player]: Damager },
	protectedUntil: number,
	dead: boolean,
	character: Model?,
	worldModel: Model?,
	fireWindowStart: number,
	fireWindowCount: number,
	lastMelee: number,
	lastHeadshot: boolean,
	connections: { RBXScriptConnection },
}

export type KillInfo = {
	victim: Player,
	killer: Player?,
	weaponId: string?,
	headshot: boolean,
	assisters: { Player },
}

local CombatService = {
	Killed = Signal.new() :: Signal.Signal<KillInfo>,
	killY = -200,
	-- Set by MatchService. Defaults allow free-for-all damage.
	rules = {
		canFight = function(_player: Player): boolean
			return true
		end,
		isEnemy = function(a: Player, b: Player): boolean
			return a ~= b
		end,
	},
	stats = { shotsAccepted = 0, shotsRejected = 0, hits = 0, rejectReasons = {} :: { [string]: number } },
}

local states: { [Player]: CombatState } = {}
local history: { [Player]: { Hitbox.Snapshot } } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function reject(reason: string)
	CombatService.stats.shotsRejected += 1
	CombatService.stats.rejectReasons[reason] = (CombatService.stats.rejectReasons[reason] or 0) + 1
end

local function isFiniteVector(v: any): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local vec = v :: Vector3
	for _, c in { vec.X, vec.Y, vec.Z } do
		if c ~= c or math.abs(c) > 1e6 then
			return false
		end
	end
	return true
end

local function aliveHumanoid(player: Player): (Humanoid?, Model?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid, character
	end
	return nil, nil
end

local function refreshRayFilter()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	local effects = workspace:FindFirstChild("Effects")
	if effects then
		table.insert(list, effects)
	end
	rayParams.FilterDescendantsInstances = list
end

local function sendAmmo(player: Player, slot: string)
	local s = states[player]
	local w = s and s.weapons[slot]
	if w then
		WeaponState.update(w, os.clock())
		Net.event("AmmoState"):FireClient(player, slot, w.mag, w.reserve, w.reloadEndsAt ~= nil)
	end
end

local function attachWorldModel(player: Player, weaponId: string)
	local s = states[player]
	local character = s and s.character
	if not s or not character then
		return
	end
	if s.worldModel then
		s.worldModel:Destroy()
		s.worldModel = nil
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local def = Weapons[weaponId]
	if not torso or not def then
		return
	end
	local model = WeaponModel.build(def, { castShadow = true })
	model.Name = "WorldWeapon"
	local grip = model.PrimaryPart :: BasePart
	local weld = Instance.new("Weld")
	weld.Part0 = torso :: BasePart
	weld.Part1 = grip
	weld.C0 = CFrame.new(0.55, 0.05, -1.1)
	weld.Parent = grip
	model.Parent = character
	s.worldModel = model
	character:SetAttribute("EquippedWeapon", weaponId)
end

local function clearState(player: Player)
	local s = states[player]
	if s then
		for _, c in s.connections do
			c:Disconnect()
		end
		if s.worldModel then
			s.worldModel:Destroy()
		end
	end
	states[player] = nil
	history[player] = nil
end

local function handleDeath(victim: Player, killer: Player?, weaponId: string?, headshot: boolean)
	local s = states[victim]
	if not s or s.dead then
		return
	end
	s.dead = true
	local now = os.clock()
	local assisters = {}
	for p, d in s.damagers do
		if p ~= killer and p.Parent and now - d.t <= ASSIST_WINDOW and d.amount >= ASSIST_MIN_DAMAGE then
			table.insert(assisters, p)
		end
	end
	CombatService.Killed:Fire({
		victim = victim,
		killer = killer,
		weaponId = weaponId,
		headshot = headshot,
		assisters = assisters,
	})
end

-- Applies validated damage. Returns true if damage was dealt.
function CombatService.applyDamage(victim: Player, attacker: Player?, amount: number, weaponId: string?, headshot: boolean, fromPos: Vector3?): boolean
	local s = states[victim]
	local humanoid = aliveHumanoid(victim)
	if not s or s.dead or not humanoid then
		return false
	end
	local now = os.clock()
	if now < s.protectedUntil then
		return false
	end
	if attacker and attacker ~= victim and not CombatService.rules.isEnemy(attacker, victim) then
		return false
	end
	amount = math.max(0, math.floor(amount))
	humanoid.Health = math.max(0, humanoid.Health - amount)
	s.lastDamaged = now
	if attacker and attacker ~= victim then
		local d: Damager = s.damagers[attacker] or { amount = 0, t = now, weaponId = weaponId }
		d.amount += amount
		d.t = now
		d.weaponId = weaponId
		s.damagers[attacker] = d
	end
	Net.event("DamageTaken"):FireClient(victim, { amount = amount, fromPosition = fromPos, health = humanoid.Health })
	local killed = humanoid.Health <= 0
	if attacker and attacker ~= victim then
		Net.event("HitConfirm"):FireClient(attacker, { damage = amount, headshot = headshot, killed = killed })
	end
	if killed then
		handleDeath(victim, attacker, weaponId, headshot)
	end
	return true
end

local function recordHistory()
	local t = os.clock()
	for _, player in Players:GetPlayers() do
		local s = states[player]
		local character = if s and not s.dead then s.character else nil
		if character then
			local head = character:FindFirstChild("Head") :: BasePart?
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if head and root then
				local h = history[player]
				if not h then
					h = {}
					history[player] = h
				end
				table.insert(h, { t = t, head = head.CFrame, root = root.CFrame })
				while #h > 0 and t - h[1].t > HISTORY_SECONDS do
					table.remove(h, 1)
				end
				if root.Position.Y < CombatService.killY then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						humanoid.Health = 0
					end
				end
			end
		end
	end
end

local regenAccumulator = 0
local function regenerate(dt: number)
	regenAccumulator += dt
	if regenAccumulator < 0.1 then
		return
	end
	local step = regenAccumulator
	regenAccumulator = 0
	local now = os.clock()
	for player, s in states do
		if not s.dead and now - s.lastDamaged >= Match.HealthRegenDelay then
			local humanoid = aliveHumanoid(player)
			if humanoid and humanoid.Health < humanoid.MaxHealth then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + Match.HealthRegenPerSecond * step)
				if humanoid.Health >= humanoid.MaxHealth then
					table.clear(s.damagers)
				end
			end
		end
	end
end

local function breakProtection(player: Player, s: CombatState)
	if s.protectedUntil > 0 then
		s.protectedUntil = 0
		local character = s.character
		local ff = character and character:FindFirstChildOfClass("ForceField")
		if ff then
			ff:Destroy()
		end
	end
end

-- Finds the nearest enemy hit along a ray, testing both rewound and current hitboxes.
local function traceEnemies(shooter: Player, origin: Vector3, dir: Vector3, maxDist: number): (Player?, number?, string?)
	local now = os.clock()
	local rewind = math.clamp(shooter:GetNetworkPing() + INTERP_ALLOWANCE, 0, MAX_REWIND)
	local bestPlayer, bestDist, bestZone = nil, maxDist, nil
	for target, h in history do
		local ts = states[target]
		if target ~= shooter and ts and not ts.dead and #h > 0 and CombatService.rules.isEnemy(shooter, target) then
			for _, snap in { Hitbox.sample(h, now - rewind), h[#h] } do
				if snap then
					local d, zone = Hitbox.testCharacter(origin, dir, bestDist, snap)
					if d and d < bestDist then
						bestPlayer, bestDist, bestZone = target, d, zone
					end
				end
			end
		end
	end
	if bestPlayer then
		return bestPlayer, bestDist, bestZone
	end
	return nil, nil, nil
end

local function onFire(player: Player, shotId: any, slot: any, origin: any, direction: any)
	local s = states[player]
	if not s or s.dead then
		return reject("nostate")
	end
	if type(shotId) ~= "number" or type(slot) ~= "string" or not isFiniteVector(origin) or not isFiniteVector(direction) then
		return reject("types")
	end
	local now = os.clock()
	if now - s.fireWindowStart >= 1 then
		s.fireWindowStart, s.fireWindowCount = now, 0
	end
	s.fireWindowCount += 1
	if s.fireWindowCount > MAX_FIRE_EVENTS_PER_SECOND then
		return reject("spam")
	end
	if not CombatService.rules.canFight(player) then
		return reject("phase")
	end
	if slot ~= s.equipped then
		sendAmmo(player, s.equipped)
		return reject("slot")
	end
	local _, character = aliveHumanoid(player)
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not head then
		return reject("nohead")
	end
	local o = origin :: Vector3
	if (o - head.Position).Magnitude > MAX_ORIGIN_OFFSET then
		return reject("origin")
	end
	local mag = (direction :: Vector3).Magnitude
	if mag < 0.9 or mag > 1.1 then
		return reject("direction")
	end
	local dir = (direction :: Vector3).Unit
	local w = s.weapons[slot]
	local def = Weapons[w.defId]
	local ok, reason = WeaponState.tryFire(w, now)
	if not ok then
		if reason ~= "rate" then
			sendAmmo(player, slot)
		end
		return reject(reason or "weapon")
	end
	CombatService.stats.shotsAccepted += 1
	breakProtection(player, s)

	local maxDist = def.damage.maxRange
	local world = workspace:Raycast(o, dir * maxDist, rayParams)
	local worldDist = if world then world.Distance else maxDist
	local target, dist, zone = traceEnemies(player, o, dir, worldDist)
	local hitPos = if target and dist then o + dir * dist elseif world then world.Position else o + dir * maxDist

	for _, other in Players:GetPlayers() do
		if other ~= player then
			Net.event("Tracer"):FireClient(other, player.UserId, o, hitPos)
		end
	end

	if target and dist and zone then
		CombatService.stats.hits += 1
		local amount = Damage.compute(def, dist, zone)
		CombatService.applyDamage(target, player, amount, def.id, zone == "Head", o)
	end
	if w.mag == 0 then
		sendAmmo(player, slot)
	end
end

local function onReload(player: Player, slot: any)
	local s = states[player]
	if not s or s.dead or type(slot) ~= "string" or slot ~= s.equipped then
		return
	end
	local w = s.weapons[slot]
	local def = Weapons[w.defId]
	local now = os.clock()
	local ok = WeaponState.startReload(w, now, def.reloadTime, def.reloadEmptyTime)
	sendAmmo(player, slot)
	if ok then
		task.delay((w.reloadEndsAt :: number) - now + 0.02, function()
			if states[player] == s and s.equipped == slot then
				sendAmmo(player, slot)
			end
		end)
	end
end

local function onEquip(player: Player, slot: any)
	local s = states[player]
	if not s or s.dead or type(slot) ~= "string" or not s.weapons[slot] or slot == s.equipped then
		return
	end
	local current = s.weapons[s.equipped]
	WeaponState.cancelReload(current)
	local w = s.weapons[slot]
	WeaponState.equip(w, os.clock(), Weapons[w.defId].equipTime)
	s.equipped = slot :: Slot
	attachWorldModel(player, w.defId)
	sendAmmo(player, s.equipped)
end

local function onMelee(player: Player)
	local s = states[player]
	if not s or s.dead or not CombatService.rules.canFight(player) then
		return
	end
	local now = os.clock()
	if now - s.lastMelee < MELEE_COOLDOWN then
		return
	end
	s.lastMelee = now
	local root = s.character and s.character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local best, bestDist = nil, MELEE_RANGE
	for target, ts in states do
		if target ~= player and not ts.dead and CombatService.rules.isEnemy(player, target) then
			local troot = ts.character and ts.character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if troot then
				local offset = troot.Position - root.Position
				local dist = offset.Magnitude
				local facing = if dist > 0.01 then root.CFrame.LookVector:Dot(offset.Unit) else 1
				if dist < bestDist and facing > 0.35 then
					local blocked = workspace:Raycast(root.Position, offset, rayParams)
					if not blocked then
						best, bestDist = target, dist
					end
				end
			end
		end
	end
	breakProtection(player, s)
	if best then
		CombatService.applyDamage(best, player, MELEE_DAMAGE, "Melee", false, root.Position)
	end
end

-- Called by MatchService after a character is spawned and positioned.
function CombatService.onSpawned(player: Player, character: Model, loadout: { primary: string, secondary: string }, protection: number)
	clearState(player)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.MaxHealth = Match.MaxHealth
	humanoid.Health = Match.MaxHealth
	humanoid.BreakJointsOnDeath = false
	local s: CombatState = {
		weapons = {
			Primary = WeaponState.new(Weapons[loadout.primary]),
			Secondary = WeaponState.new(Weapons[loadout.secondary]),
		},
		equipped = "Primary",
		lastDamaged = 0,
		damagers = {},
		protectedUntil = os.clock() + protection,
		dead = false,
		character = character,
		worldModel = nil,
		fireWindowStart = 0,
		fireWindowCount = 0,
		lastMelee = 0,
		lastHeadshot = false,
		connections = {},
	}
	states[player] = s
	if protection > 0 then
		local ff = Instance.new("ForceField")
		ff.Visible = true
		ff.Parent = character
		task.delay(protection, function()
			if ff.Parent then
				ff:Destroy()
			end
		end)
	end
	table.insert(s.connections, humanoid.Died:Connect(function()
		-- Deaths not caused by applyDamage (falling, reset) count as suicides.
		handleDeath(player, nil, nil, false)
	end))
	character:SetAttribute("PrimaryWeapon", loadout.primary)
	character:SetAttribute("SecondaryWeapon", loadout.secondary)
	WeaponState.equip(s.weapons.Primary, os.clock(), Weapons[loadout.primary].equipTime)
	attachWorldModel(player, loadout.primary)
	refreshRayFilter()
	sendAmmo(player, "Primary")
	sendAmmo(player, "Secondary")
end

function CombatService.despawn(player: Player)
	clearState(player)
	local character = player.Character
	if character then
		player.Character = nil
		character:Destroy()
	end
	refreshRayFilter()
end

function CombatService.isAlive(player: Player): boolean
	local s = states[player]
	return s ~= nil and not s.dead
end

function CombatService.init()
	Net.event("Fire").OnServerEvent:Connect(onFire)
	Net.event("Reload").OnServerEvent:Connect(onReload)
	Net.event("Equip").OnServerEvent:Connect(onEquip)
	Net.event("Melee").OnServerEvent:Connect(onMelee)
	Players.PlayerRemoving:Connect(function(player)
		clearState(player)
		task.defer(refreshRayFilter)
	end)
end

function CombatService.start()
	RunService.Heartbeat:Connect(function(dt)
		recordHistory()
		regenerate(dt)
	end)
end

return CombatService
