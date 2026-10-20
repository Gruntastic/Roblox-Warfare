--!strict
-- In-match HUD (visible while deployed): health + damage vignette, ammo, crosshair, hit markers,
-- directional damage indicators, team scores + timer, a heading compass and the scope overlay
-- (shown while aiming a weapon whose def has a built-in `scope`). Free-for-All shows your kills vs
-- the leader instead of team scores; in S&D the team scores are round wins and the timer is the
-- round clock (or the bomb timer once planted).
-- Phase 5: Recon Drone pings show as red diamonds on the compass (fading out at expiresAt), an enemy
-- Counter-Recon fills the compass with static, and an enemy Blackout hides everything except
-- health, crosshair and hit markers (UI/Streaks draws the SIGNAL LOST overlay).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)
local ObjectiveRules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Pure.ObjectiveRules)

local HUD = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer

-- Tunables
local CROSS_BASE_GAP = 9
local CROSS_SPEED_GAP = 0.65 -- extra px per stud/s of horizontal speed
local CROSS_BLOOM_PER_SHOT = 7
local CROSS_BLOOM_MAX = 26
local CROSS_BLOOM_DECAY = 9 -- per second (exponential)
local CROSS_LEN = 12
local CROSS_THICK = 2
local LOW_HEALTH = 0.35
local INDICATOR_COUNT = 6
local HIT_SHOW = TweenInfo.new(0.02)
local INDICATOR_LIFETIME = 1.6
local INDICATOR_RADIUS = 150
local COMPASS_WIDTH = 620
local COMPASS_PX_PER_DEG = 4
local COMPASS_MIN_DEG = -180
local COMPASS_MAX_DEG = 540

local gui: ScreenGui
local canvas: Frame
local renderConn: RBXScriptConnection? = nil

-- health
local healthFill: Frame
local healthText: TextLabel
local healthTween: Tween? = nil
local vignette: { Frame } = {}
local damageFlash = 0
local healthAlpha = 1
local lastHealth = 100

-- character tracking
local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local charConns: { RBXScriptConnection } = {}

-- ammo
local weaponLabel: TextLabel
local magLabel: TextLabel
local reserveLabel: TextLabel
local centerPrompt: TextLabel
local ammoPanel: Frame

-- crosshair
local crosshair: Frame
local crossLines: { Frame } = {}
local bloom = 0
local lastGap = -1
local crossVisible = true

-- hit marker
local hitMarker: Frame
local hitScale: UIScale
local hitLines: { Frame } = {}
local hitToken = 0

-- damage indicators
type Indicator = { holder: Frame, bar: Frame, from: Vector3?, started: number, active: boolean }
local indicators: { Indicator } = {}
local nextIndicator = 1

-- top
local scoresHolder: Frame
local timerLabel: TextLabel
local limitLabel: TextLabel
local leftScore: TextLabel
local rightScore: TextLabel
local leftName: TextLabel
local rightName: TextLabel
local leftFill: Frame
local rightFill: Frame
local leftStripe: Frame
local rightStripe: Frame
local compassInner: Frame
local headingLabel: TextLabel
local lastHeading = -1
local compassGroup: CanvasGroup
local compassCaret: Frame
local PING_POOL = 16
local pingDiamonds: { Frame } = {}
local jamStatic: Frame
local jamBars: { Frame } = {}
local jamShown = false
local blackoutShown = false

-- scope overlay
local SCOPE_IN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SCOPE_OUT = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SCOPE_LENS = 0.92 -- lens diameter as a fraction of the virtual screen height
local SCOPE_RINGS = { 0.04, 0.09, 0.15 } -- vignette ring widths as fractions of the lens diameter
local scopeGroup: CanvasGroup
local scopeLens: Frame
local scopeSurround: UIStroke
local scopeRings: { { frame: Frame, stroke: UIStroke, width: number } } = {}
local scopeShown = false
local scopeTween: Tween? = nil

-- optic reticle (red dot / holo / chevron), centred on the point of aim while aiming through an optic
local RETICLE_COLOR = Color3.fromRGB(255, 64, 48)
local reticleGroup: CanvasGroup
local reticleKinds: { [string]: Frame } = {}
local reticleTween: Tween? = nil
local reticleShown: string? = nil

---------------------------------------------------------------------------------------------
-- Health + vignette
---------------------------------------------------------------------------------------------

local function setHealth(health: number, maxHealth: number)
	local alpha = if maxHealth > 0 then math.clamp(health / maxHealth, 0, 1) else 0
	if health < lastHealth - 0.5 then
		damageFlash = math.min(1, damageFlash + 0.35 + (lastHealth - health) / 60)
	end
	lastHealth = health
	healthAlpha = alpha
	healthText.Text = tostring(math.ceil(math.max(health, 0)))
	if healthTween then
		healthTween:Cancel()
	end
	healthTween = Theme.tween(healthFill, Theme.Tween.Fast, { Size = UDim2.fromScale(alpha, 1) })
	healthFill.BackgroundColor3 = if alpha <= LOW_HEALTH then C.Danger else C.Text
end

local function clearCharacter()
	for _, conn in charConns do
		conn:Disconnect()
	end
	table.clear(charConns)
	humanoid = nil
	rootPart = nil
end

local function bindCharacter(character: Model)
	clearCharacter()
	task.spawn(function()
		local hum = character:WaitForChild("Humanoid", 10)
		if not hum or not hum:IsA("Humanoid") or character.Parent == nil then
			return
		end
		if localPlayer.Character ~= character then
			return
		end
		humanoid = hum
		local hrp = character:WaitForChild("HumanoidRootPart", 10)
		rootPart = if hrp and hrp:IsA("BasePart") then hrp else nil
		lastHealth = hum.Health
		damageFlash = 0
		setHealth(hum.Health, hum.MaxHealth)
		table.insert(charConns, hum.HealthChanged:Connect(function(h: number)
			setHealth(h, hum.MaxHealth)
		end))
		table.insert(charConns, hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			setHealth(hum.Health, hum.MaxHealth)
		end))
	end)
end

---------------------------------------------------------------------------------------------
-- Ammo
---------------------------------------------------------------------------------------------

local function refreshAmmo()
	local slot = ClientState.equippedSlot
	local weaponId = ClientState.equippedWeaponId
	weaponLabel.Text = string.upper(Theme.weaponName(weaponId))
	local info = ClientState.ammo[slot]
	if not info then
		magLabel.Text = "--"
		reserveLabel.Text = "/ --"
		centerPrompt.Visible = false
		return
	end
	magLabel.Text = tostring(info.mag)
	reserveLabel.Text = "/ " .. tostring(info.reserve)
	local def = if weaponId then Theme.Weapons[weaponId] else nil
	local magSize = if def then def.magSize else 30
	local low = info.mag <= math.max(1, math.ceil(magSize * 0.25))
	magLabel.TextColor3 = if info.mag == 0 then C.Danger elseif low then C.Accent else C.Text
	reserveLabel.TextColor3 = if info.reserve == 0 then C.Danger else C.TextDim
	if info.reloading then
		centerPrompt.Text = "RELOADING"
		centerPrompt.TextColor3 = C.Text
		centerPrompt.Visible = true
	elseif info.mag == 0 and info.reserve == 0 then
		centerPrompt.Text = "NO AMMO"
		centerPrompt.TextColor3 = C.Danger
		centerPrompt.Visible = true
	elseif blackoutShown then
		centerPrompt.Visible = false
	elseif low and info.reserve > 0 then
		centerPrompt.Text = if Theme.isTouchOnly() then "RELOAD" else "[R]  RELOAD"
		centerPrompt.TextColor3 = C.Accent
		centerPrompt.Visible = true
	else
		centerPrompt.Visible = false
	end
end

---------------------------------------------------------------------------------------------
-- Hit marker + damage indicators
---------------------------------------------------------------------------------------------

local function onHit(p: Types.HitConfirmPayload)
	if typeof(p) ~= "table" then
		return
	end
	hitToken += 1
	local token = hitToken
	local color = if p.killed then C.Danger elseif p.headshot then C.Accent else C.White
	local thickness = if p.killed or p.headshot then 3 else 2
	for _, line in hitLines do
		line.BackgroundColor3 = color
		-- a (near-instant) tween rather than a direct set, so it overrides any running fade-out
		Theme.tween(line, HIT_SHOW, { BackgroundTransparency = 0 })
		line.Size = UDim2.fromOffset(if p.killed then 14 else 10, thickness)
	end
	hitMarker.Visible = true
	hitScale.Scale = if p.killed then 1.7 elseif p.headshot then 1.4 else 1.2
	Theme.tween(hitScale, Theme.Tween.Fast, { Scale = if p.killed then 1.25 else 1 })
	task.delay(if p.killed then 0.35 else 0.18, function()
		if token ~= hitToken then
			return
		end
		for _, line in hitLines do
			Theme.tween(line, Theme.Tween.Normal, { BackgroundTransparency = 1 })
		end
	end)
end

local function onDamage(p: Types.DamageTakenPayload)
	if typeof(p) ~= "table" then
		return
	end
	damageFlash = math.min(1, damageFlash + 0.25)
	if typeof(p.fromPosition) ~= "Vector3" then
		return
	end
	local ind = indicators[nextIndicator]
	nextIndicator = nextIndicator % INDICATOR_COUNT + 1
	ind.from = p.fromPosition
	ind.started = os.clock()
	ind.active = true
	ind.holder.Visible = true
	ind.bar.BackgroundTransparency = 0.05
end

---------------------------------------------------------------------------------------------
-- Top bar: scores, timer
---------------------------------------------------------------------------------------------

local function refreshScores()
	local ms = ClientState.matchState
	if not ms then
		scoresHolder.Visible = false
		return
	end
	scoresHolder.Visible = not blackoutShown
	local limit = math.max(ms.scoreLimit, 1)
	if Theme.isFFA(ms) then
		-- Free-for-All: your kills vs the leader's (or the runner-up's while you lead).
		local myKills, rivalName, rivalKills, iLead = ObjectiveRules.ffaRace(ms.players, localPlayer.UserId)
		leftName.Text = "YOU"
		leftName.TextColor3 = C.Accent
		leftScore.Text = tostring(myKills)
		leftFill.BackgroundColor3 = C.Accent
		leftStripe.BackgroundColor3 = C.Accent
		Theme.tween(leftFill, Theme.Tween.Normal, { Size = UDim2.fromScale(math.clamp(myKills / limit, 0, 1), 1) })
		local rivalColor = C.TextDim
		if rivalName then
			rightName.Text = (if iLead then "2ND  " else "LEADER  ") .. string.upper(rivalName)
			rightScore.Text = tostring(rivalKills)
		else
			rightName.Text = "NO RIVALS"
			rightScore.Text = ""
		end
		rightName.TextColor3 = rivalColor
		rightFill.BackgroundColor3 = rivalColor
		rightStripe.BackgroundColor3 = rivalColor
		Theme.tween(rightFill, Theme.Tween.Normal, { Size = UDim2.fromScale(math.clamp(rivalKills / limit, 0, 1), 1) })
		limitLabel.Text = if ms.scoreLimit > 0 then "FIRST TO " .. tostring(ms.scoreLimit) else ""
		return
	end
	-- Search and Destroy: team scores are round wins (scoreLimit = rounds to win). Prefer the live
	-- objective round state when present so the bar updates the instant a round ends.
	local snd = Theme.isSnD()
	local obj = ClientState.objective
	local roundWins = if snd and obj and obj.round and type(obj.round.wins) == "table" then obj.round.wins else nil
	local myTeam = Theme.localTeam()
	local mine: Types.TeamScore? = nil
	local other: Types.TeamScore? = nil
	for _, t in ms.teams do
		if t.id == myTeam and not mine then
			mine = t
		elseif not other then
			other = t
		end
	end
	if not mine then
		mine = ms.teams[1]
		other = ms.teams[2]
	end
	local function apply(t: Types.TeamScore?, nameL: TextLabel, scoreL: TextLabel, fill: Frame, stripe: Frame)
		if t then
			local color = Theme.teamColor(t.id)
			local score = if roundWins and type(roundWins[t.id]) == "number" then roundWins[t.id] else t.score
			nameL.Text = string.upper(t.displayName)
			nameL.TextColor3 = color
			scoreL.Text = tostring(score)
			fill.BackgroundColor3 = color
			stripe.BackgroundColor3 = color
			Theme.tween(fill, Theme.Tween.Normal, { Size = UDim2.fromScale(math.clamp(score / limit, 0, 1), 1) })
		else
			nameL.Text = ""
			scoreL.Text = ""
			fill.Size = UDim2.fromScale(0, 1)
		end
	end
	apply(mine, leftName, leftScore, leftFill, leftStripe)
	apply(other, rightName, rightScore, rightFill, rightStripe)
	if ms.scoreLimit <= 0 then
		limitLabel.Text = ""
	elseif snd then
		limitLabel.Text = "FIRST TO " .. tostring(ms.scoreLimit) .. (if ms.scoreLimit == 1 then " ROUND" else " ROUNDS")
	else
		limitLabel.Text = "FIRST TO " .. tostring(ms.scoreLimit)
	end
end

---------------------------------------------------------------------------------------------
-- Scope overlay
---------------------------------------------------------------------------------------------

-- Sizes in virtual (canvas) pixels; recomputed on each show so resolution changes are picked up.
local function layoutScope()
	local scale = Theme.getScale()
	local virtualHeight = if scale > 0 then canvas.AbsoluteSize.Y / scale else 1080
	if virtualHeight < 100 then
		virtualHeight = 1080
	end
	local d = math.floor(virtualHeight * SCOPE_LENS + 0.5)
	scopeLens.Size = UDim2.fromOffset(d, d)
	-- the big black stroke covers the corners between the lens circle and its bounding square;
	-- the four Surround frames (children of the lens) cover everything beyond that square
	scopeSurround.Thickness = math.ceil(d * 0.3)
	for _, ring in scopeRings do
		local w = math.max(2, math.floor(d * ring.width + 0.5))
		ring.frame.Size = UDim2.new(1, -2 * w, 1, -2 * w)
		ring.stroke.Thickness = w
	end
end

local function setScope(on: boolean, instant: boolean?)
	if on == scopeShown and not instant then
		return
	end
	scopeShown = on
	if scopeTween then
		scopeTween:Cancel()
		scopeTween = nil
	end
	if on then
		layoutScope()
		scopeGroup.Visible = true
		if instant then
			scopeGroup.GroupTransparency = 0
		else
			scopeTween = Theme.tween(scopeGroup, SCOPE_IN, { GroupTransparency = 0 })
		end
	elseif instant or not scopeGroup.Visible then
		scopeGroup.GroupTransparency = 1
		scopeGroup.Visible = false
	else
		local tween = Theme.tween(scopeGroup, SCOPE_OUT, { GroupTransparency = 1 })
		scopeTween = tween
		tween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and not scopeShown then
				scopeGroup.Visible = false
			end
		end)
	end
end

-- Fades in over the second half of the ADS transition so the dot appears as the glass lines up.
local function setReticle(kind: string?, adsTime: number)
	if kind == reticleShown then
		return
	end
	reticleShown = kind
	if reticleTween then
		reticleTween:Cancel()
		reticleTween = nil
	end
	if kind then
		for name, frame in reticleKinds do
			frame.Visible = name == kind
		end
		reticleGroup.GroupTransparency = 1
		reticleGroup.Visible = true
		local info = TweenInfo.new(adsTime * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, adsTime * 0.5)
		reticleTween = Theme.tween(reticleGroup, info, { GroupTransparency = 0 })
	else
		reticleGroup.Visible = false
	end
end

local function refreshScope()
	local weaponId = ClientState.equippedWeaponId
	local def = if weaponId then Theme.Weapons[weaponId] else nil
	local aiming = gui.Enabled and ClientState.deployed and ClientState.ads and def ~= nil
	local want = aiming and def ~= nil and def.scope ~= nil
	if gui.Enabled then
		setScope(want)
	else
		setScope(false, true)
	end
	local stats = ClientState.equippedStats
	local kind = if aiming and not want and stats and stats.id == weaponId then stats.reticle else nil
	setReticle(kind, if stats then stats.adsTime else 0.2)
end

---------------------------------------------------------------------------------------------
-- Per-frame update (connected only while the HUD is shown; no table allocations)
---------------------------------------------------------------------------------------------

local function renderStep(dt: number)
	local now = os.clock()

	-- vignette: damage flash decays; low health pulses
	damageFlash = math.max(0, damageFlash - dt * 1.6)
	local pulse = 0
	if healthAlpha <= LOW_HEALTH and humanoid then
		local severity = 1 - healthAlpha / LOW_HEALTH
		pulse = (0.35 + 0.25 * severity) * (0.65 + 0.35 * math.sin(now * (5 + 4 * severity)))
	end
	local intensity = math.max(damageFlash, pulse)
	local transparency = 1 - intensity
	for _, edge in vignette do
		edge.BackgroundTransparency = transparency
	end

	-- crosshair gap from movement speed + shot bloom
	bloom = bloom * math.exp(-CROSS_BLOOM_DECAY * dt)
	local speed = 0
	if rootPart then
		local v = rootPart.AssemblyLinearVelocity
		speed = math.sqrt(v.X * v.X + v.Z * v.Z)
	end
	local gap = math.floor(CROSS_BASE_GAP + speed * CROSS_SPEED_GAP + bloom + 0.5)
	if gap ~= lastGap and crossVisible then
		lastGap = gap
		crossLines[1].Position = UDim2.fromOffset(0, -gap) -- top
		crossLines[2].Position = UDim2.fromOffset(0, gap) -- bottom
		crossLines[3].Position = UDim2.fromOffset(-gap, 0) -- left
		crossLines[4].Position = UDim2.fromOffset(gap, 0) -- right
	end

	-- camera-relative work
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cf = camera.CFrame
	local look = cf.LookVector

	-- compass
	local heading = math.deg(math.atan2(look.X, -look.Z)) % 360
	local rounded = math.floor(heading * 4 + 0.5) / 4
	if rounded ~= lastHeading then
		lastHeading = rounded
		compassInner.Position = UDim2.fromOffset(COMPASS_WIDTH / 2 - (rounded - COMPASS_MIN_DEG) * COMPASS_PX_PER_DEG, 0)
		headingLabel.Text = tostring(math.floor(heading + 0.5) % 360)
	end

	-- [Phase 5] compass: Recon Drone pings, Counter-Recon static
	local ping = ClientState.ping
	local jammedUntil = ClientState.jammedUntil
	if ping or jammedUntil > 0 or jamShown then
		local sNow = workspace:GetServerTimeNow()
		local jammed = jammedUntil > sNow
		if jammed ~= jamShown then
			jamShown = jammed
			jamStatic.Visible = jammed
			compassInner.Visible = not jammed
		end
		if jammed then
			for _, bar in jamBars do
				bar.Position = UDim2.fromScale(math.random(), 0)
				bar.BackgroundTransparency = 0.3 + math.random() * 0.6
			end
		end
		local used = 0
		if ping and not jammed and ping.expiresAt > sNow then
			local alpha = math.clamp((ping.expiresAt - sNow) / 2, 0, 1)
			local camPosition = cf.Position
			for _, t in ping.targets do
				if used >= PING_POOL then
					break
				end
				local pos = t.position
				if typeof(pos) == "Vector3" then
					local bearing = math.deg(math.atan2(pos.X - camPosition.X, -(pos.Z - camPosition.Z)))
					local delta = (bearing - heading + 540) % 360 - 180
					local x = COMPASS_WIDTH / 2 + delta * COMPASS_PX_PER_DEG
					if x > 8 and x < COMPASS_WIDTH - 8 then
						used += 1
						local d = pingDiamonds[used]
						d.Position = UDim2.fromOffset(x, 17)
						d.BackgroundTransparency = 1 - alpha
						d.Visible = true
					end
				end
			end
		elseif ping and ping.expiresAt <= sNow then
			ClientState.ping = nil
		end
		for i = used + 1, PING_POOL do
			local d = pingDiamonds[i]
			if d.Visible then
				d.Visible = false
			end
		end
	end

	-- damage direction indicators
	local right = cf.RightVector
	local flatLookX, flatLookZ = look.X, look.Z
	local flatRightX, flatRightZ = right.X, right.Z
	local camPos = cf.Position
	for _, ind in indicators do
		if ind.active then
			local age = now - ind.started
			if age >= INDICATOR_LIFETIME then
				ind.active = false
				ind.holder.Visible = false
			else
				local from = ind.from
				if from then
					local dx, dz = from.X - camPos.X, from.Z - camPos.Z
					local fwd = dx * flatLookX + dz * flatLookZ
					local side = dx * flatRightX + dz * flatRightZ
					ind.holder.Rotation = math.deg(math.atan2(side, fwd))
				end
				ind.bar.BackgroundTransparency = 0.05 + 0.95 * (age / INDICATOR_LIFETIME) ^ 2
			end
		end
	end
end

-- [Phase 5] enemy Blackout: knock out everything except health, crosshair, hit markers and
-- damage indicators.
local function refreshBlackout()
	local on = ClientState.isBlackedOut()
	if on == blackoutShown then
		return
	end
	blackoutShown = on
	compassGroup.Visible = not on
	compassCaret.Visible = not on
	headingLabel.Visible = not on
	scoresHolder.Visible = not on and ClientState.matchState ~= nil
	ammoPanel.Visible = not on
	if on then
		centerPrompt.Visible = false
	else
		refreshAmmo()
		refreshScores()
	end
end

local function setShown(shown: boolean)
	if gui.Enabled == shown then
		return
	end
	gui.Enabled = shown
	if shown then
		lastGap = -1
		lastHeading = -1
		refreshAmmo()
		refreshScores()
		if not renderConn then
			renderConn = RunService.RenderStepped:Connect(renderStep)
		end
		canvas.Position = UDim2.fromOffset(0, 12)
		Theme.tween(canvas, Theme.Tween.Normal, { Position = UDim2.fromOffset(0, 0) })
	else
		if renderConn then
			renderConn:Disconnect()
			renderConn = nil
		end
		for _, ind in indicators do
			ind.active = false
			ind.holder.Visible = false
		end
		damageFlash = 0
	end
	refreshScope()
end

local function refreshShown()
	local ms = ClientState.matchState
	local phaseOk = ms == nil or ms.phase == "Countdown" or ms.phase == "Playing"
	setShown(ClientState.deployed and phaseOk)
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------

local function buildVignette()
	local holder: Frame = Theme.new("Frame", { Name = "Vignette", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0, Parent = canvas })
	-- each edge: red band whose UIGradient fades it towards the screen centre
	local specs = {
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, 0.32), rot = 90 },
		{ pos = UDim2.fromScale(0, 0.68), size = UDim2.fromScale(1, 0.32), rot = -90 },
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(0.26, 1), rot = 0 },
		{ pos = UDim2.fromScale(0.74, 0), size = UDim2.fromScale(0.26, 1), rot = 180 },
	}
	for _, s in specs do
		local edge: Frame = Theme.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(170, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = s.pos,
			Size = s.size,
			Parent = holder,
		})
		Theme.new("UIGradient", {
			Rotation = s.rot,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(0.45, 0.75),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = edge,
		})
		table.insert(vignette, edge)
	end
end

local function buildScope()
	-- ZIndex -1: drawn under every other HUD element (health, ammo, hit markers stay readable)
	scopeGroup = Theme.new("CanvasGroup", {
		Name = "Scope",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = -1,
		GroupTransparency = 1,
		Visible = false,
		Parent = canvas,
	})
	scopeLens = Theme.new("Frame", {
		Name = "Lens",
		BackgroundColor3 = Color3.fromRGB(12, 20, 26),
		BackgroundTransparency = 0.93,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(994, 994),
		Parent = scopeGroup,
	}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
	scopeSurround = Theme.new("UIStroke", {
		Color = C.Black,
		Thickness = 300,
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		BorderStrokePosition = Enum.BorderStrokePosition.Outer,
		Parent = scopeLens,
	})
	local big = 6000
	local surrounds = {
		{ anchor = Vector2.new(0.5, 1), pos = UDim2.fromScale(0.5, 0), size = UDim2.fromOffset(big, big) }, -- above
		{ anchor = Vector2.new(0.5, 0), pos = UDim2.fromScale(0.5, 1), size = UDim2.fromOffset(big, big) }, -- below
		{ anchor = Vector2.new(1, 0.5), pos = UDim2.fromScale(0, 0.5), size = UDim2.new(0, big, 1, 0) }, -- left
		{ anchor = Vector2.new(0, 0.5), pos = UDim2.fromScale(1, 0.5), size = UDim2.new(0, big, 1, 0) }, -- right
	}
	for _, spec in surrounds do
		Theme.new("Frame", {
			Name = "Surround",
			BackgroundColor3 = C.Black,
			BorderSizePixel = 0,
			AnchorPoint = spec.anchor,
			Position = spec.pos,
			Size = spec.size,
			Parent = scopeLens,
		})
	end
	-- soft vignette: stacked translucent rings darken the lens towards its rim
	for i, width in SCOPE_RINGS do
		local ring: Frame = Theme.new("Frame", {
			Name = "Vignette",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
			Parent = scopeLens,
		}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		local stroke: UIStroke = Theme.new("UIStroke", {
			Color = C.Black,
			Thickness = 10,
			Transparency = 0.72 + i * 0.06,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			BorderStrokePosition = Enum.BorderStrokePosition.Outer,
			Parent = ring,
		})
		table.insert(scopeRings, { frame = ring, stroke = stroke, width = width })
	end
	-- duplex reticle: thin full-width cross plus heavy posts towards the rim
	local function line(anchor: Vector2, pos: UDim2, size: UDim2)
		Theme.new("Frame", {
			Name = "Reticle",
			BackgroundColor3 = C.Black,
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			AnchorPoint = anchor,
			Position = pos,
			Size = size,
			ZIndex = 2,
			Parent = scopeLens,
		})
	end
	local mid = Vector2.new(0.5, 0.5)
	line(mid, UDim2.fromScale(0.5, 0.5), UDim2.new(1, 0, 0, 2))
	line(mid, UDim2.fromScale(0.5, 0.5), UDim2.new(0, 2, 1, 0))
	line(Vector2.new(0, 0.5), UDim2.fromScale(0, 0.5), UDim2.new(0.34, 0, 0, 6)) -- left post
	line(Vector2.new(1, 0.5), UDim2.fromScale(1, 0.5), UDim2.new(0.34, 0, 0, 6)) -- right post
	line(Vector2.new(0.5, 1), UDim2.fromScale(0.5, 1), UDim2.new(0, 6, 0.34, 0)) -- bottom post
end

local function buildReticle()
	reticleGroup = Theme.new("CanvasGroup", {
		Name = "Reticle",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(64, 64),
		GroupTransparency = 1,
		Visible = false,
		Parent = canvas,
	})
	local function holder(name: string): Frame
		local f = Theme.new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = reticleGroup,
		})
		reticleKinds[name] = f
		return f
	end
	local function dot(parent: Frame, size: number)
		local d = Theme.new("Frame", {
			Name = "Dot",
			BackgroundColor3 = RETICLE_COLOR,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			Parent = parent,
		})
		Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = d })
		Theme.new("UIStroke", { Color = RETICLE_COLOR, Transparency = 0.6, Thickness = 2, Parent = d }) -- glow
	end

	dot(holder("Dot"), 5)

	local holo = holder("Holo")
	dot(holo, 4)
	local ring = Theme.new("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(40, 40),
		Parent = holo,
	})
	Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
	Theme.new("UIStroke", { Color = RETICLE_COLOR, Thickness = 2, Transparency = 0.1, Parent = ring })

	-- chevron: two short strokes meeting at the point of aim, plus a hairline drop below
	local chevron = holder("Chevron")
	for _, side in { -1, 1 } do
		Theme.new("Frame", {
			Name = "Arm",
			BackgroundColor3 = RETICLE_COLOR,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, side * 5, 0.5, 4),
			Size = UDim2.fromOffset(13, 2),
			Rotation = side * -38,
			Parent = chevron,
		})
	end
	Theme.new("Frame", {
		Name = "Drop",
		BackgroundColor3 = RETICLE_COLOR,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 12),
		Size = UDim2.fromOffset(1, 18),
		Parent = chevron,
	})
end

local function buildHealth()
	local panel = Theme.panel({
		Name = "Health",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 32, 1, -32),
		Size = UDim2.fromOffset(360, 62),
		Parent = canvas,
	})
	Theme.label({
		Text = "HP",
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(16, 8),
		Size = UDim2.fromOffset(60, 16),
		Parent = panel,
	})
	healthText = Theme.label({
		Text = "100",
		Font = Theme.Fonts.Title,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 4),
		Size = UDim2.fromOffset(90, 32),
		Parent = panel,
	})
	local _, fill = Theme.bar({
		Position = UDim2.new(0, 16, 0, 40),
		Size = UDim2.new(1, -32, 0, 10),
		Parent = panel,
	}, C.Text)
	healthFill = fill
	healthFill.Size = UDim2.fromScale(1, 1)
end

local function buildAmmo()
	ammoPanel = Theme.panel({
		Name = "Ammo",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -32, 1, -32),
		Size = UDim2.fromOffset(300, 96),
		Parent = canvas,
	})
	Theme.new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), Parent = ammoPanel })
	weaponLabel = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(20, 8),
		Size = UDim2.new(1, -36, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = ammoPanel,
	})
	magLabel = Theme.label({
		Text = "--",
		Font = Theme.Fonts.Title,
		TextSize = 52,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(20, 30),
		Size = UDim2.new(1, -136, 0, 56),
		Parent = ammoPanel,
	})
	reserveLabel = Theme.label({
		Text = "/ --",
		Font = Theme.Fonts.Bold,
		TextSize = 24,
		TextColor3 = C.TextDim,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 50),
		Size = UDim2.fromOffset(104, 30),
		Parent = ammoPanel,
	})
end

local function buildCrosshair()
	crosshair = Theme.new("Frame", {
		Name = "Crosshair",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		Parent = canvas,
	})
	local sizes = {
		Vector2.new(CROSS_THICK, CROSS_LEN),
		Vector2.new(CROSS_THICK, CROSS_LEN),
		Vector2.new(CROSS_LEN, CROSS_THICK),
		Vector2.new(CROSS_LEN, CROSS_THICK),
	}
	local anchors = { Vector2.new(0.5, 1), Vector2.new(0.5, 0), Vector2.new(1, 0.5), Vector2.new(0, 0.5) }
	for i = 1, 4 do
		local line: Frame = Theme.new("Frame", {
			BackgroundColor3 = C.White,
			BorderSizePixel = 0,
			AnchorPoint = anchors[i],
			Size = UDim2.fromOffset(sizes[i].X, sizes[i].Y),
			Parent = crosshair,
		}, { Theme.new("UIStroke", { Color = C.Black, Transparency = 0.55, Thickness = 1 }) })
		crossLines[i] = line
	end
	-- center dot
	Theme.new("Frame", {
		Name = "Dot",
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(2, 2),
		Parent = crosshair,
	})

	hitMarker = Theme.new("Frame", {
		Name = "HitMarker",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		Parent = canvas,
	})
	hitScale = Theme.new("UIScale", { Parent = hitMarker })
	local diag = { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) }
	for i, d in diag do
		local line: Frame = Theme.new("Frame", {
			BackgroundColor3 = C.White,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(d.X * 13, d.Y * 13),
			Size = UDim2.fromOffset(10, 2),
			Rotation = if d.X * d.Y > 0 then 45 else -45,
			Parent = hitMarker,
		})
		hitLines[i] = line
	end

	centerPrompt = Theme.label({
		Name = "Prompt",
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 70),
		Size = UDim2.fromOffset(300, 24),
		Visible = false,
		Parent = canvas,
	})
end

local function buildIndicators()
	for i = 1, INDICATOR_COUNT do
		local holder: Frame = Theme.new("Frame", {
			Name = "DamageIndicator",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0),
			Visible = false,
			Parent = canvas,
		})
		local bar: Frame = Theme.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(235, 40, 30),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(0, -INDICATOR_RADIUS),
			Size = UDim2.fromOffset(150, 9),
			Parent = holder,
		}, { Theme.corner(5) })
		Theme.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = bar,
		})
		indicators[i] = { holder = holder, bar = bar, from = nil, started = 0, active = false }
	end
end

local function buildTop()
	-- compass strip
	local compass: CanvasGroup = Theme.new("CanvasGroup", {
		Name = "Compass",
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(COMPASS_WIDTH, 34),
		Parent = canvas,
	}, { Theme.corner(4) })
	Theme.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0),
			NumberSequenceKeypoint.new(0.85, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = compass,
	})
	compassGroup = compass
	compassInner = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset((COMPASS_MAX_DEG - COMPASS_MIN_DEG) * COMPASS_PX_PER_DEG, 34),
		Parent = compass,
	})
	-- [Phase 5] Recon Drone ping diamonds (pooled; positioned by renderStep)
	for i = 1, PING_POOL do
		local d: Frame = Theme.new("Frame", {
			Name = "Ping",
			BackgroundColor3 = Color3.fromRGB(255, 60, 48),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(11, 11),
			Rotation = 45,
			ZIndex = 3,
			Visible = false,
			Parent = compass,
		}, { Theme.new("UIStroke", { Color = C.Black, Transparency = 0.4, Thickness = 1 }) })
		pingDiamonds[i] = d
	end
	-- [Phase 5] Counter-Recon static
	jamStatic = Theme.new("Frame", {
		Name = "Jammed",
		BackgroundColor3 = Color3.fromRGB(40, 44, 50),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Visible = false,
		Parent = compass,
	})
	for i = 1, 24 do
		local bar: Frame = Theme.new("Frame", {
			BackgroundColor3 = if i % 3 == 0 then C.Danger else C.TextDim,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 2 + (i % 4) * 2, 1, 0),
			Parent = jamStatic,
		})
		jamBars[i] = bar
	end
	Theme.label({
		Text = "COMPASS JAMMED",
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.Danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = jamStatic,
	})
	local cardinals: { [number]: string } = { [0] = "N", [45] = "NE", [90] = "E", [135] = "SE", [180] = "S", [225] = "SW", [270] = "W", [315] = "NW" }
	for deg = COMPASS_MIN_DEG, COMPASS_MAX_DEG, 15 do
		local norm = deg % 360
		local x = (deg - COMPASS_MIN_DEG) * COMPASS_PX_PER_DEG
		local card = cardinals[norm]
		if card then
			Theme.label({
				Text = card,
				Font = Theme.Fonts.Bold,
				TextSize = if #card == 1 then 20 else 15,
				TextColor3 = if card == "N" then C.Accent else C.Text,
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(x, 4),
				Size = UDim2.fromOffset(40, 26),
				Parent = compassInner,
			})
		else
			Theme.new("Frame", {
				BackgroundColor3 = C.TextDim,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(x, 4),
				Size = UDim2.fromOffset(2, 8),
				Parent = compassInner,
			})
			Theme.label({
				Text = tostring(norm),
				Font = Theme.Fonts.Medium,
				TextSize = 11,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(x, 14),
				Size = UDim2.fromOffset(30, 14),
				Parent = compassInner,
			})
		end
	end
	-- centre caret + heading readout (outside the clipped group)
	compassCaret = Theme.new("Frame", {
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(2, 12),
		Parent = canvas,
	})
	headingLabel = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 50),
		Size = UDim2.fromOffset(60, 16),
		Parent = canvas,
	})

	-- scores + timer
	scoresHolder = Theme.new("Frame", {
		Name = "Scores",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(560, 64),
		Parent = canvas,
	})
	local timerBox = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(120, 46),
		Parent = scoresHolder,
	})
	timerLabel = Theme.label({
		Text = "0:00",
		Font = Theme.Fonts.Title,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = timerBox,
	})
	limitLabel = Theme.label({
		Font = Theme.Fonts.Medium,
		TextSize = 12,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 48),
		Size = UDim2.fromOffset(160, 16),
		Parent = scoresHolder,
	})
	local function side(isLeft: boolean): (TextLabel, TextLabel, Frame, Frame)
		local box = Theme.panel({
			AnchorPoint = Vector2.new(if isLeft then 1 else 0, 0),
			Position = UDim2.new(0.5, if isLeft then -68 else 68, 0, 0),
			Size = UDim2.fromOffset(200, 46),
			Parent = scoresHolder,
		})
		local stripe: Frame = Theme.new("Frame", {
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0),
			Position = UDim2.fromScale(if isLeft then 0 else 1, 0),
			Size = UDim2.new(0, 4, 1, 0),
			Parent = box,
		})
		local nameL = Theme.label({
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			TextXAlignment = if isLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(14, 4),
			Size = UDim2.new(1, -28, 0, 14),
			Parent = box,
		})
		local scoreL = Theme.label({
			Font = Theme.Fonts.Title,
			TextSize = 24,
			TextXAlignment = if isLeft then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(14, 16),
			Size = UDim2.new(1, -28, 0, 24),
			Parent = box,
		})
		local track, fill = Theme.bar({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 3),
			Parent = box,
		})
		if not isLeft then
			-- fill grows from the right edge for the enemy side
			track.Rotation = 180
		end
		return nameL, scoreL, fill, stripe
	end
	leftName, leftScore, leftFill, leftStripe = side(true)
	rightName, rightScore, rightFill, rightStripe = side(false)
end

function HUD.init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	gui, canvas = Theme.screen("HUD", 5)
	gui.Enabled = false
	buildScope()
	buildReticle()
	buildVignette()
	buildIndicators()
	buildHealth()
	buildAmmo()
	buildCrosshair()
	buildTop()
	Theme.mount(gui)

	-- character / health
	localPlayer.CharacterAdded:Connect(bindCharacter)
	localPlayer.CharacterRemoving:Connect(clearCharacter)
	if localPlayer.Character then
		bindCharacter(localPlayer.Character)
	end

	ClientState.DeployedChanged:Connect(function()
		refreshShown()
		refreshScope()
	end)
	ClientState.MatchStateChanged:Connect(function()
		refreshShown()
		if gui.Enabled then
			refreshScores()
		end
	end)
	ClientState.ObjectiveChanged:Connect(function()
		-- S&D round wins come from the objective state
		if gui.Enabled and Theme.isSnD() then
			refreshScores()
		end
	end)
	ClientState.AmmoChanged:Connect(function(slot: string)
		if slot == ClientState.equippedSlot then
			refreshAmmo()
		end
	end)
	ClientState.WeaponChanged:Connect(function()
		refreshAmmo()
		refreshScope()
		local scale = ammoPanel:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Theme.new("UIScale", { Parent = ammoPanel })
		end
		if scale then
			scale.Scale = 1.06
			Theme.tween(scale, Theme.Tween.Pop, { Scale = 1 })
		end
	end)
	ClientState.Fired:Connect(function()
		bloom = math.min(CROSS_BLOOM_MAX, bloom + CROSS_BLOOM_PER_SHOT)
	end)
	ClientState.AdsChanged:Connect(function(ads: boolean)
		crossVisible = not ads
		lastGap = -1
		for _, line in crossLines do
			Theme.tween(line, Theme.Tween.Fast, { BackgroundTransparency = if ads then 1 else 0 })
			local stroke = line:FindFirstChildOfClass("UIStroke")
			if stroke then
				Theme.tween(stroke, Theme.Tween.Fast, { Transparency = if ads then 1 else 0.55 })
			end
		end
		local dot = crosshair:FindFirstChild("Dot")
		if dot and dot:IsA("Frame") then
			dot.Visible = not ads
		end
		refreshScope()
	end)
	ClientState.HitConfirm:Connect(onHit)
	ClientState.DamageTaken:Connect(onDamage)
	ClientState.HudEffectsChanged:Connect(refreshBlackout)

	refreshShown()
end

function HUD.start()
	-- match timer (4 Hz is plenty; only touches text when the second changes)
	local lastText = ""
	while true do
		refreshBlackout() -- also catches a Blackout whose endsAt passed without an EffectEnded
		if gui.Enabled then
			local ms = ClientState.matchState
			local text = "--:--"
			local danger = false
			local obj = ClientState.objective
			local round = if obj then obj.round else nil
			local bomb = if obj then obj.bomb else nil
			if Theme.isSnD() and bomb and bomb.state == "Planted" and type(bomb.explodesAt) == "number" then
				-- S&D: the detonation countdown replaces the round clock once the bomb is planted
				text = Theme.formatTime(bomb.explodesAt - Theme.serverNow())
				danger = true
			elseif Theme.isSnD() and round and type(round.endsAt) == "number" and round.endsAt > 0 then
				text = Theme.formatTime(round.endsAt - Theme.serverNow())
			elseif ms and ms.phaseEndsAt > 0 then
				text = Theme.formatTime(ms.phaseEndsAt - Theme.serverNow())
			end
			if text ~= lastText then
				lastText = text
				timerLabel.Text = text
				timerLabel.TextColor3 = if danger then C.Danger else C.Text
			end
		end
		task.wait(0.25)
	end
end

return HUD
