--!strict
-- First-person weapon handling: viewmodel, input, ADS, recoil, spread, prediction and effects.
-- The client only reports intent (Fire/Reload/Equip/Melee); the server validates everything.
local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Weapons = require(Shared.Config.Weapons)
local Attachments = require(Shared.Config.Attachments)
local WeaponStats = require(Shared.Pure.WeaponStats)
local PerkRules = require(Shared.Pure.PerkRules)
local Pellets = require(Shared.Pure.Pellets)
local Audio = require(Shared.Config.Audio)
local Gear = require(Shared.Config.Gear)
local WeaponModel = require(Shared.WeaponModel)
local ClientState = require(script.Parent.Parent.ClientState)
local Effects = require(script.Parent.Effects)

local player = Players.LocalPlayer
local BASE_FOV = 70
local HIP_OFFSET = CFrame.new(0.85, -0.95, -1.55)
local SPRINT_OFFSET = CFrame.new(0.55, -1.15, -1.25) * CFrame.Angles(math.rad(-12), math.rad(40), math.rad(10))

type Slot = "Primary" | "Secondary"
type Equipped = {
	slot: Slot,
	def: WeaponStats.Effective, -- attachments and perks applied; the server holds the authoritative copy
	viewmodel: Model,
	muzzle: Attachment,
	sight: Vector3, -- ADS eye point relative to the grip origin
}

local WeaponController = {}

local viewmodels: { [string]: Equipped } = {}
local current: Equipped? = nil
local character: Model? = nil
local localMag: { [string]: number } = {}
local reloadingUntil = 0
local reloadDuration = 1
local equipUntil = 0
local nextFireAt = 0
local triggerHeld = false
local semiLatch = false
local adsHeld = false
local adsAlpha = 0
local sprintAlpha = 0
local shotId = 0
local burstRemaining = 0 -- rounds left in the current burst (Burst weapons)
local recoilPending = Vector2.zero -- degrees still to apply (pitch, yaw)
local recoilRecover = 0 -- degrees of pitch to recover
local kick = 0 -- viewmodel kick spring
local bobTime = 0
local lastMeleeAt = 0
local meleeAnimUntil = 0
local swayX, swayY = 0, 0
local rng = Random.new()

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function camera(): Camera
	return workspace.CurrentCamera
end

-- Sleeves and gloves match the equipped operator gear set (Config/Gear).
local function gearColors(): (Color3, Color3, Color3)
	local profile = ClientState.profile
	local eq = profile and profile.cosmetics and profile.cosmetics.equipped
	local gear = Gear.byId[if eq and eq.gear then eq.gear else Gear.Default] or Gear.byId[Gear.Default]
	return gear.shirt, gear.gloves, gear.webbing
end

local function buildArms(model: Model, grip: BasePart)
	local sleeve, glove, cuff = gearColors()
	local specs = {
		{ name = "RightArm", size = Vector3.new(0.35, 0.35, 1.6), cf = CFrame.new(0.15, -0.35, 0.85) * CFrame.Angles(math.rad(10), 0, 0), color = sleeve },
		{ name = "RightHand", size = Vector3.new(0.3, 0.32, 0.36), cf = CFrame.new(0, -0.15, 0.05), color = glove },
		{ name = "LeftArm", size = Vector3.new(0.35, 0.35, 1.7), cf = CFrame.new(-0.45, -0.3, -0.45) * CFrame.Angles(math.rad(8), math.rad(-28), 0), color = sleeve },
		{ name = "LeftHand", size = Vector3.new(0.3, 0.3, 0.36), cf = CFrame.new(-0.02, -0.08, -1.2), color = glove },
		-- glove cuffs and a wrist watch for a bit of kit in first person
		{ name = "RightCuff", size = Vector3.new(0.38, 0.38, 0.14), cf = CFrame.new(0.13, -0.27, 0.32) * CFrame.Angles(math.rad(10), 0, 0), color = cuff },
		{ name = "LeftCuff", size = Vector3.new(0.38, 0.38, 0.14), cf = CFrame.new(-0.12, -0.13, -0.98) * CFrame.Angles(math.rad(8), math.rad(-28), 0), color = cuff },
		{ name = "Watch", size = Vector3.new(0.4, 0.2, 0.2), cf = CFrame.new(-0.16, -0.06, -0.9) * CFrame.Angles(math.rad(8), math.rad(-28), 0), color = Color3.fromRGB(24, 24, 26) },
	}
	for _, spec in specs do
		local p = Instance.new("Part")
		p.Name = spec.name
		p.Size = spec.size
		p.Color = spec.color
		p.Material = Enum.Material.Fabric
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		local weld = Instance.new("Weld")
		weld.Part0 = grip
		weld.Part1 = p
		weld.C0 = spec.cf
		weld.Parent = p
		p.Parent = model
	end
end

-- Perks and camos of the loadout this life was spawned with, read from the latest ProfileSummary
-- (display and feel only; the server applies the same PerkRules call authoritatively).
local function spawnLoadoutExtras(): (PerkRules.Combined, { [string]: string })
	local profile = ClientState.profile
	if not profile then
		return PerkRules.combine({}), {}
	end
	local loadout = profile.loadouts and profile.loadouts[profile.selectedLoadout]
	local perks = if loadout and loadout.perks then loadout.perks else {}
	local camos = if profile.cosmetics and profile.cosmetics.equipped then profile.cosmetics.equipped.camos else nil
	return PerkRules.combine(perks), camos or {}
end

local function makeViewmodel(slot: Slot, weaponId: string, selection: { [string]: string }, perks: PerkRules.Combined, camo: string?): Equipped?
	local def = Weapons[weaponId]
	if not def then
		return nil
	end
	local model = WeaponModel.build(def, { castShadow = false, attachments = selection, camo = camo })
	model.Name = "Viewmodel_" .. slot
	local grip = model.PrimaryPart :: BasePart
	grip.Anchored = true
	buildArms(model, grip)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	local muzzle = grip:FindFirstChild("Muzzle") :: Attachment
	local sight = grip:FindFirstChild("Sight") :: Attachment
	local stats = PerkRules.applyToWeapon(WeaponStats.resolve(def, selection, Attachments), perks)
	return { slot = slot, def = stats, viewmodel = model, muzzle = muzzle, sight = sight.Position }
end

local function clearViewmodels()
	for _, e in viewmodels do
		e.viewmodel:Destroy()
	end
	table.clear(viewmodels)
	current = nil
	ClientState.equippedWeaponId = nil
	ClientState.equippedStats = nil
end

local function setAds(on: boolean)
	if ClientState.ads ~= on then
		ClientState.ads = on
		ClientState.AdsChanged:Fire(on)
		UserInputService.MouseDeltaSensitivity = if on then 0.65 else 1
	end
end

local function equip(slot: Slot, notifyServer: boolean)
	local target = viewmodels[slot]
	if not target or (current and current.slot == slot) then
		return
	end
	if current then
		current.viewmodel.Parent = nil
	end
	current = target
	target.viewmodel.Parent = camera()
	reloadingUntil = 0
	equipUntil = os.clock() + target.def.equipTime
	burstRemaining = 0
	ClientState.equippedSlot = slot
	ClientState.equippedWeaponId = target.def.id
	ClientState.equippedStats = target.def
	ClientState.WeaponChanged:Fire(slot, target.def.id)
	ClientState.Sfx:Fire("Equip")
	if notifyServer then
		Net.event("Equip"):FireServer(slot)
	end
end

local function canAct(): boolean
	return ClientState.deployed and current ~= nil and character ~= nil and character:GetAttribute("Frozen") ~= true
end

local function startReload()
	local cur = current
	if not cur or not canAct() or os.clock() < reloadingUntil then
		return
	end
	local ammo = ClientState.ammo[cur.slot]
	local mag = localMag[cur.slot] or (ammo and ammo.mag) or 0
	if mag >= cur.def.magSize or (ammo and ammo.reserve <= 0) then
		return
	end
	reloadDuration = if mag == 0 then cur.def.reloadEmptyTime else cur.def.reloadTime
	reloadingUntil = os.clock() + reloadDuration
	setAds(false)
	-- reload sounds: shotguns load shells, everything else swaps the magazine
	local token = reloadingUntil
	local shotgun = cur.def.class == "Shotgun"
	local handgun = cur.def.class == "Pistol" or cur.def.class == "MachinePistol"
	local full = if handgun then "Reload.Handgun" elseif not shotgun then "Reload.Rifle" else nil
	if full and Audio[full] and Audio[full].id ~= 0 then
		ClientState.Sfx:Fire(full) -- one recorded reload covers the whole action
	else
		ClientState.Sfx:Fire(if shotgun then "ShellLoad" else "MagOut")
		task.delay(reloadDuration * 0.55, function()
			if reloadingUntil == token then
				ClientState.Sfx:Fire(if shotgun then "ShellLoad" else "MagIn")
			end
		end)
		if mag == 0 and not shotgun then
			task.delay(reloadDuration * 0.85, function()
				if reloadingUntil == token then
					ClientState.Sfx:Fire("BoltRack")
				end
			end)
		end
	end
	Net.event("Reload"):FireServer(cur.slot)
end

local function currentSpread(def: any): number
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local speed = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
	local base = def.spread.hip + (def.spread.ads - def.spread.hip) * adsAlpha
	if speed > 2 then
		base *= def.spread.movingMultiplier
	end
	return base
end

local lastDryAt = 0

local function impactSlot(material: Enum.Material): string
	local name = material.Name
	if string.find(name, "Metal") or name == "CorrodedMetal" or name == "DiamondPlate" or name == "Foil" then
		return "Impact.Metal"
	elseif string.find(name, "Wood") then
		return "Impact.Wood"
	elseif name == "Grass" or name == "Sand" or name == "Ground" or name == "Mud" or name == "Snow" or name == "LeafyGrass" or name == "Fabric" then
		return "Impact.Dirt"
	end
	return "Impact.Concrete"
end

-- A small fixed pitch offset per weapon, so guns of one class sharing a sound still differ.
local function weaponPitch(id: string): number
	local h = 0
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % 1000
	end
	return (h / 1000 - 0.5) * 0.12
end

local function fireOnce(): boolean
	local cur = current
	local ms = ClientState.matchState
	-- The server rejects shots outside Playing; don't fake them locally (no flash, no mag drift).
	if not cur or not canAct() or not ms or ms.phase ~= "Playing" then
		return false
	end
	local def = cur.def
	local now = os.clock()
	if now < nextFireAt or now < equipUntil or now < reloadingUntil or ClientState.sprinting then
		return false
	end
	local mag = localMag[cur.slot] or 0
	if mag <= 0 then
		burstRemaining = 0
		if now - lastDryAt > 0.3 then
			lastDryAt = now
			ClientState.Sfx:Fire("Dry")
		end
		startReload()
		return false
	end
	nextFireAt = now + 60 / def.rpm
	if def.burst then
		burstRemaining = math.max(burstRemaining - 1, 0)
		if burstRemaining == 0 then
			nextFireAt += def.burst.delay
		end
	end
	localMag[cur.slot] = mag - 1
	shotId += 1
	-- The server only syncs ammo on reloads, rejects and an empty mag; show the predicted count meanwhile.
	local shown = ClientState.ammo[cur.slot]
	if shown then
		shown.mag = mag - 1
		ClientState.AmmoChanged:Fire(cur.slot, shown)
	end

	local cam = camera()
	local spread = math.rad(currentSpread(def))
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = spread * math.sqrt(rng:NextNumber())
	local dirCF = cam.CFrame * CFrame.Angles(math.sin(angle) * radius, math.cos(angle) * radius, 0)
	local origin = cam.CFrame.Position
	local direction = dirCF.LookVector

	Net.event("Fire"):FireServer(shotId, cur.slot, origin, direction)

	-- Cosmetic local trace for immediate feedback (server decides damage independently).
	local ignore: { Instance } = { cam }
	if character then
		table.insert(ignore, character)
	end
	raycastParams.FilterDescendantsInstances = ignore
	local pelletCount = def.pellets or 1
	local dirs: { Vector3 } = if pelletCount > 1 then Pellets.directions(CFrame.lookAt(origin, origin + direction), pelletCount, def.pelletSpread or 5) else { direction }
	for i, d in ipairs(dirs) do
		local result = workspace:Raycast(origin, d * def.damage.maxRange, raycastParams)
		local hitPos = if result then result.Position else origin + d * def.damage.maxRange
		Effects.tracer(cur.muzzle.WorldPosition, hitPos)
		if result and not (result.Instance:FindFirstAncestorOfClass("Model") and (result.Instance:FindFirstAncestorOfClass("Model") :: Model):FindFirstChildOfClass("Humanoid")) then
			Effects.impact(result.Position, result.Normal)
			if i == 1 then
				ClientState.Sfx:Fire(impactSlot(result.Material), result.Position)
			end
		end
	end
	if not def.suppressed then
		Effects.muzzleFlash(cur.muzzle)
	end
	ClientState.Sfx:Fire(if def.suppressed then "Shot.Suppressed" else "Shot." .. def.class, nil, weaponPitch(def.id))
	if def.class == "Sniper" and (localMag[cur.slot] or 0) > 0 then
		task.delay(math.min(0.35, 60 / def.rpm * 0.5), function()
			ClientState.Sfx:Fire("BoltCycle")
		end)
	end

	local adsMult = 1 + (def.recoil.adsMultiplier - 1) * adsAlpha
	recoilPending += Vector2.new(def.recoil.vertical * adsMult, rng:NextNumber(-1, 1) * def.recoil.horizontal * adsMult)
	kick = math.min(kick + 1, 3)
	ClientState.Fired:Fire(def.id)
	if localMag[cur.slot] == 0 then
		task.delay(0.15, startReload)
	end
	return true
end

local function melee()
	if not canAct() or os.clock() - lastMeleeAt < 0.9 then
		return
	end
	lastMeleeAt = os.clock()
	meleeAnimUntil = lastMeleeAt + 0.35
	ClientState.Sfx:Fire("Melee")
	Net.event("Melee"):FireServer()
end

-- Attachment selections arrive as JSON character attributes set by the server.
local function decodeSelection(value: any): { [string]: string }
	if type(value) ~= "string" then
		return {}
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, value)
	local out = {}
	if ok and type(decoded) == "table" then
		for slot, id in decoded do
			if type(slot) == "string" and type(id) == "string" then
				out[slot] = id
			end
		end
	end
	return out
end

local function onCharacterReady(char: Model)
	character = char
	clearViewmodels()
	local function waitAttr(name: string): string?
		local deadline = os.clock() + 10
		while char.Parent and char:GetAttribute(name) == nil and os.clock() < deadline do
			task.wait()
		end
		return char:GetAttribute(name) :: string?
	end
	local primary, secondary = waitAttr("PrimaryWeapon"), waitAttr("SecondaryWeapon")
	if character ~= char then
		return
	end
	local perks, camos = spawnLoadoutExtras()
	if primary then
		viewmodels.Primary = makeViewmodel("Primary", primary, decodeSelection(char:GetAttribute("PrimaryAttachments")), perks, camos[primary]) :: Equipped
	end
	if secondary then
		viewmodels.Secondary = makeViewmodel("Secondary", secondary, decodeSelection(char:GetAttribute("SecondaryAttachments")), perks, camos[secondary]) :: Equipped
	end
	for slot, e in viewmodels do
		local ammo = ClientState.ammo[slot]
		localMag[slot] = if ammo then ammo.mag else e.def.magSize
	end
	reloadingUntil, nextFireAt, adsAlpha, sprintAlpha = 0, 0, 0, 0
	recoilPending, recoilRecover, kick = Vector2.zero, 0, 0
	equip("Primary", false)
end

local function render(dt: number)
	local cur = current
	local cam = camera()
	if not cur or not ClientState.deployed then
		if cam.FieldOfView ~= BASE_FOV and not ClientState.deployed then
			cam.FieldOfView = BASE_FOV
		end
		return
	end
	local def = cur.def
	local now = os.clock()

	-- Trigger: Auto fires while held; Semi once per press; Burst queues `burst.count` rounds per press.
	if burstRemaining > 0 then
		if canAct() then
			fireOnce()
		else
			burstRemaining = 0
		end
	elseif triggerHeld and canAct() then
		if def.fireMode == "Auto" then
			fireOnce()
		elseif not semiLatch then
			semiLatch = true
			if def.burst then
				burstRemaining = def.burst.count
			end
			fireOnce()
		end
	end

	-- ADS / sprint blending
	local wantAds = adsHeld and canAct() and now >= reloadingUntil and not ClientState.sprinting
	setAds(wantAds)
	local adsTarget = if wantAds then 1 else 0
	adsAlpha += (adsTarget - adsAlpha) * math.min(1, dt / math.max(def.adsTime, 0.05) * 3.5)
	local sprintTarget = if ClientState.sprinting then 1 else 0
	sprintAlpha += (sprintTarget - sprintAlpha) * math.min(1, dt * 10)

	-- Recoil applied to the camera, then recovered over time
	if recoilPending.Magnitude > 0.001 then
		local step = recoilPending * math.min(1, dt * 30)
		recoilPending -= step
		recoilRecover += step.X
		cam.CFrame *= CFrame.Angles(math.rad(step.X), math.rad(step.Y), 0)
	elseif recoilRecover > 0.001 and not triggerHeld then
		local back = math.min(recoilRecover, def.recoil.recovery * dt)
		recoilRecover -= back
		cam.CFrame *= CFrame.Angles(math.rad(-back), 0, 0)
	end
	if not triggerHeld then
		recoilRecover = math.min(recoilRecover, 6)
	end
	kick += (0 - kick) * math.min(1, dt * 14)

	-- FOV
	local sprintFov = BASE_FOV + 6
	local targetFov = BASE_FOV + (def.adsFov - BASE_FOV) * adsAlpha + (sprintFov - BASE_FOV) * sprintAlpha
	cam.FieldOfView += (targetFov - cam.FieldOfView) * math.min(1, dt * 12)

	-- Procedural animation layers
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local speed = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
	bobTime += dt * (if speed > 1 then speed * 0.55 else 1.2)
	local bobAmp = (if speed > 1 then 0.045 else 0.012) * (1 - adsAlpha * 0.85)
	local bob = CFrame.new(math.sin(bobTime) * bobAmp, math.abs(math.cos(bobTime)) * bobAmp, 0)
	local mouseDelta = UserInputService:GetMouseDelta()
	swayX += (math.clamp(-mouseDelta.X * 0.004, -0.08, 0.08) - swayX) * math.min(1, dt * 8)
	swayY += (math.clamp(-mouseDelta.Y * 0.004, -0.08, 0.08) - swayY) * math.min(1, dt * 8)
	local sway = CFrame.Angles(swayY * (1 - adsAlpha * 0.8), swayX * (1 - adsAlpha * 0.8), 0)

	local adsOffset = CFrame.new(-cur.sight.X, -cur.sight.Y, -1.15)
	local base = HIP_OFFSET:Lerp(adsOffset, adsAlpha):Lerp(SPRINT_OFFSET, sprintAlpha * (1 - adsAlpha))
	local kickCF = CFrame.new(0, 0, kick * 0.06) * CFrame.Angles(math.rad(kick * 1.6), 0, 0)

	local reloadCF = CFrame.identity
	if now < reloadingUntil then
		local t = 1 - (reloadingUntil - now) / reloadDuration
		local dip = math.sin(math.clamp(t, 0, 1) * math.pi)
		reloadCF = CFrame.new(0, -0.35 * dip, 0.1 * dip) * CFrame.Angles(math.rad(-25 * dip), 0, math.rad(35 * dip))
	end
	local equipCF = CFrame.identity
	if now < equipUntil then
		local t = (equipUntil - now) / math.max(def.equipTime, 0.05)
		equipCF = CFrame.new(0, -1.1 * t, 0) * CFrame.Angles(math.rad(-40 * t), 0, 0)
	end
	local meleeCF = CFrame.identity
	if now < meleeAnimUntil then
		local t = 1 - (meleeAnimUntil - now) / 0.35
		local s = math.sin(t * math.pi)
		meleeCF = CFrame.new(-0.4 * s, 0.1 * s, -0.6 * s) * CFrame.Angles(0, math.rad(35 * s), math.rad(-25 * s))
	end

	cur.viewmodel:PivotTo(cam.CFrame * base * bob * sway * kickCF * reloadCF * equipCF * meleeCF)
	-- Magnified scopes: the HUD draws the scope overlay; hide the gun once mostly aimed in.
	local scopedIn = def.scoped and adsAlpha > 0.85
	local wantParent = if scopedIn then nil else cam
	if cur.viewmodel.Parent ~= wantParent then
		cur.viewmodel.Parent = wantParent
	end

	-- Hide our own third-person weapon in first person.
	local worldWeapon = character and character:FindFirstChild("WorldWeapon")
	if worldWeapon then
		for _, d in worldWeapon:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end
	end
end

local function bindInput()
	local function fireAction(_: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			triggerHeld = true
			semiLatch = false
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			triggerHeld = false
			semiLatch = false
		end
		return if ClientState.deployed then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end
	local function adsAction(_: string, state: Enum.UserInputState)
		adsHeld = state == Enum.UserInputState.Begin
		return if ClientState.deployed then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end
	local function reloadAction(_: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			startReload()
		end
		return Enum.ContextActionResult.Pass
	end
	local function swapAction(_: string, state: Enum.UserInputState, input: InputObject)
		if state ~= Enum.UserInputState.Begin or not canAct() then
			return Enum.ContextActionResult.Pass
		end
		local target: Slot
		if input.KeyCode == Enum.KeyCode.One then
			target = "Primary"
		elseif input.KeyCode == Enum.KeyCode.Two then
			target = "Secondary"
		else
			target = if ClientState.equippedSlot == "Primary" then "Secondary" else "Primary"
		end
		equip(target, true)
		return Enum.ContextActionResult.Pass
	end
	local function meleeAction(_: string, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			melee()
		end
		return Enum.ContextActionResult.Pass
	end
	ContextActionService:BindAction("COR_Fire", fireAction, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("COR_ADS", adsAction, false, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	ContextActionService:BindAction("COR_Reload", reloadAction, false, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("COR_Swap", swapAction, false, Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.ButtonY)
	ContextActionService:BindAction("COR_Melee", meleeAction, false, Enum.KeyCode.V, Enum.KeyCode.ButtonR3)

	-- Phase 7: on-screen touch buttons. ADS toggles on touch (holding a second finger is awkward).
	ClientState.TouchAction:Connect(function(name: string, down: boolean)
		local state = if down then Enum.UserInputState.Begin else Enum.UserInputState.End
		if name == "Fire" then
			fireAction(name, state)
		elseif name == "ADS" and down then
			adsHeld = not adsHeld
		elseif name == "Reload" and down then
			startReload()
		elseif name == "Swap" and down and canAct() then
			equip(if ClientState.equippedSlot == "Primary" then "Secondary" else "Primary", true)
		elseif name == "Melee" and down then
			melee()
		end
	end)
	ClientState.DeployedChanged:Connect(function()
		adsHeld = false
		triggerHeld = false
	end)

	UserInputService.InputChanged:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel or not canAct() then
			return
		end
		equip(if ClientState.equippedSlot == "Primary" then "Secondary" else "Primary", true)
	end)
end

function WeaponController.init()
	ClientState.AmmoChanged:Connect(function(slot, info)
		-- Server is authoritative: adopt its magazine count, and its reload state.
		localMag[slot :: Slot] = info.mag
		if current and current.slot == slot and not info.reloading then
			reloadingUntil = 0
		end
	end)
	ClientState.DeployedChanged:Connect(function(isDeployed)
		if isDeployed then
			local char = player.Character
			if char then
				task.spawn(onCharacterReady, char)
			end
		else
			clearViewmodels()
			character = nil
			triggerHeld = false
			setAds(false)
		end
	end)
	Net.event("Tracer").OnClientEvent:Connect(function(_shooterId: number, origin: Vector3, hitPos: Vector3)
		Effects.tracer(origin, hitPos)
		Effects.impact(hitPos, nil)
	end)
end

function WeaponController.start()
	bindInput()
	RunService:BindToRenderStep("COR_Weapon", Enum.RenderPriority.Camera.Value + 1, render)
	if ClientState.deployed and player.Character then
		onCharacterReady(player.Character)
	end
	camera().FieldOfView = BASE_FOV
end

return WeaponController
