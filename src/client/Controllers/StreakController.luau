--!strict
-- Killstreak input and client-only world effects (Phase 5). Cosmetic only: the server validates
-- every activation and does all damage.
--
-- Input: keys 5 / 6 / 7 use the 1st / 2nd / 3rd equipped streak when it is ready; gamepad D-pad up
-- uses the most recently earned ready streak; UI/Streaks calls StreakController.activate for taps
-- on the touch tray. Every activation sends ActivateStreak(id, camera look vector). Presses are
-- ignored while the game processed them (chat, focused text boxes, GUI selection), while not
-- deployed, outside a Playing match, while a menu is open and under an enemy Blackout.
--
-- World effects (all parented to a client-only folder under workspace.CurrentCamera):
--   Incoming  red ground warning discs at each shell position until it lands
--   Impact    a damage-free Explosion (BlastPressure 0, DestroyJointRadiusPercent 0) + flash, and a
--             camera shake when close
--   Ping      short-lived red diamond markers over each target, fading out at expiresAt
--   Mark      a Highlight on the marked enemy's character (Tracker), only on this client
-- It also mirrors Jammed / Blackout / EffectEnded into ClientState (jammedUntil / blackoutUntil)
-- for the HUD, and clears everything when the match leaves Playing.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Killstreaks = require(Shared.Config.Killstreaks)
local ClientState = require(script.Parent.Parent.ClientState)
local Phase5Rules = require(script.Parent.Parent.UI.Phase5Rules)

local StreakController = {}

local player = Players.LocalPlayer
local KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.Five] = 1,
	[Enum.KeyCode.Six] = 2,
	[Enum.KeyCode.Seven] = 3,
}
local ACTIVATE_COOLDOWN = 0.5 -- matches the server's rate limit
local WARNING_COLOR = Color3.fromRGB(235, 40, 30)
local PING_COLOR = Color3.fromRGB(255, 60, 48)
local SHAKE_RANGE = 3 -- shake when within radius * SHAKE_RANGE of an impact
local SHAKE_TIME = 0.55

local folder: Folder? = nil
local lastActivate = 0

type Warning = { part: BasePart, position: Vector3, landsAt: number, tween: Tween? }
local warnings: { Warning } = {}
local pingParts: { BasePart } = {}
type MarkEntry = { highlight: Highlight, untilAt: number }
local marks: { [number]: MarkEntry } = {}

local shakeUntil = 0
local shakeStrength = 0
local rng = Random.new()

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function effectsFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = "COR_StreakEffects"
	newFolder.Parent = workspace.CurrentCamera
	folder = newFolder
	return newFolder
end

local function myTeam(): string?
	local ms = ClientState.matchState
	if not ms then
		return nil
	end
	for _, line in ms.players do
		if line.userId == player.UserId then
			return line.team
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Activation
---------------------------------------------------------------------------------------------

local function canActivate(): boolean
	local ms = ClientState.matchState
	return ClientState.deployed and ms ~= nil and ms.phase == "Playing" and not ClientState.isMenuOpen() and not ClientState.isBlackedOut()
end

-- Asks the server to use a ready streak. Returns true when the request was sent.
function StreakController.activate(id: string): boolean
	local state = ClientState.streak
	if not canActivate() or not state or not table.find(state.ready, id) then
		return false
	end
	local now = os.clock()
	if now - lastActivate < ACTIVATE_COOLDOWN then
		return false
	end
	lastActivate = now
	local camera = workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else nil
	task.spawn(function()
		local ok, err = pcall(function()
			Net.event("ActivateStreak"):FireServer(id, look)
		end)
		if not ok then
			warn("[StreakController] ActivateStreak failed: " .. tostring(err))
		end
	end)
	return true
end

local function onInput(input: InputObject, processed: boolean)
	if processed then
		return
	end
	local id: string? = nil
	if input.UserInputType == Enum.UserInputType.Keyboard then
		local index = KEYS[input.KeyCode]
		if index then
			id = Phase5Rules.pickByIndex(ClientState.streak, index)
		end
	elseif input.KeyCode == Enum.KeyCode.DPadUp then
		id = Phase5Rules.pickNewest(ClientState.streak)
	end
	if id then
		StreakController.activate(id)
	end
end

---------------------------------------------------------------------------------------------
-- World effects
---------------------------------------------------------------------------------------------

local function newPart(name: string, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	return p
end

local function removeWarning(i: number)
	local w = warnings[i]
	table.remove(warnings, i)
	if w.tween then
		w.tween:Cancel()
	end
	w.part:Destroy()
end

local function clearWarnings()
	for i = #warnings, 1, -1 do
		removeWarning(i)
	end
end

local function onIncoming(data: { [string]: any })
	local positions = data.positions
	if type(positions) ~= "table" then
		return
	end
	local def = if type(data.streakId) == "string" then Killstreaks.byId[data.streakId] else nil
	local radius = if type(data.radius) == "number" then math.clamp(data.radius, 2, 60) else 12
	local impactAt = if type(data.impactAt) == "number" then data.impactAt else serverNow() + 3
	local interval = if type(data.interval) == "number"
		then data.interval
		elseif def and type(def.params.interval) == "number" then def.params.interval
		else 1
	for i, pos in positions do
		if typeof(pos) == "Vector3" and i <= 32 then
			local disc = newPart("IncomingWarning", Enum.PartType.Cylinder)
			disc.Color = WARNING_COLOR
			disc.Size = Vector3.new(0.2, radius * 2, radius * 2)
			disc.CFrame = CFrame.new(pos + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
			disc.Transparency = 0.55
			-- inner ring + light column so it reads from a distance
			local core = newPart("Core", Enum.PartType.Cylinder)
			core.Color = WARNING_COLOR
			core.Size = Vector3.new(0.25, radius * 0.5, radius * 0.5)
			core.CFrame = disc.CFrame
			core.Transparency = 0.2
			core.Parent = disc
			local column = newPart("Column")
			column.Color = WARNING_COLOR
			column.Size = Vector3.new(0.4, 40, 0.4)
			column.CFrame = CFrame.new(pos + Vector3.new(0, 20, 0))
			column.Transparency = 0.6
			column.Parent = disc
			disc.Parent = effectsFolder()
			local tween = TweenService:Create(
				disc,
				TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Transparency = 0.85 }
			)
			tween:Play()
			table.insert(warnings, { part = disc, position = pos, landsAt = impactAt + (i - 1) * interval, tween = tween })
		end
	end
end

local function onImpact(data: { [string]: any })
	local pos = data.position
	if typeof(pos) ~= "Vector3" then
		return
	end
	local radius = if type(data.radius) == "number" then math.clamp(data.radius, 2, 60) else 12
	-- the warning closest to this impact goes away
	local best, bestDist = nil, math.huge
	for i, w in warnings do
		local d = (w.position - pos).Magnitude
		if d < bestDist then
			best, bestDist = i, d
		end
	end
	if best and bestDist < radius * 2 then
		removeWarning(best)
	end
	-- damage-free explosion (purely visual, local to this client)
	local explosion = Instance.new("Explosion")
	explosion.Position = pos
	explosion.BlastRadius = radius
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.ExplosionType = Enum.ExplosionType.NoCraters
	explosion.Parent = effectsFolder()
	local flash = newPart("ImpactFlash", Enum.PartType.Ball)
	flash.Color = Color3.fromRGB(255, 170, 80)
	flash.Size = Vector3.new(2, 2, 2)
	flash.CFrame = CFrame.new(pos)
	flash.Transparency = 0.1
	flash.Parent = effectsFolder()
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Range = radius * 2
	light.Brightness = 6
	light.Parent = flash
	local tween = TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius * 1.6, radius * 1.6, radius * 1.6),
		Transparency = 1,
	})
	tween:Play()
	tween.Completed:Once(function()
		flash:Destroy()
	end)
	task.delay(2, function()
		explosion:Destroy()
	end)
	-- shake when close
	local camera = workspace.CurrentCamera
	if camera and ClientState.deployed then
		local d = (camera.CFrame.Position - pos).Magnitude
		local range = radius * SHAKE_RANGE
		if d < range then
			local strength = 0.6 * (1 - d / range) + 0.1
			shakeStrength = math.max(if os.clock() < shakeUntil then shakeStrength else 0, strength)
			shakeUntil = os.clock() + SHAKE_TIME
		end
	end
end

local function clearPings()
	for _, p in pingParts do
		p:Destroy()
	end
	table.clear(pingParts)
end

local function onPing(p: { targets: { any }, expiresAt: number })
	clearPings()
	local life = math.clamp(p.expiresAt - serverNow(), 0.2, 10)
	for i, t in p.targets do
		if type(t) == "table" and typeof(t.position) == "Vector3" and i <= 32 then
			local anchor = newPart("PingMarker")
			anchor.Transparency = 1
			anchor.Size = Vector3.new(0.2, 0.2, 0.2)
			anchor.CFrame = CFrame.new(t.position + Vector3.new(0, 3, 0))
			local billboard = Instance.new("BillboardGui")
			billboard.AlwaysOnTop = true
			billboard.Size = UDim2.fromOffset(22, 22)
			billboard.LightInfluence = 0
			billboard.ResetOnSpawn = false
			billboard.Parent = anchor
			local diamond = Instance.new("Frame")
			diamond.AnchorPoint = Vector2.new(0.5, 0.5)
			diamond.Position = UDim2.fromScale(0.5, 0.5)
			diamond.Size = UDim2.fromScale(0.7, 0.7)
			diamond.Rotation = 45
			diamond.BorderSizePixel = 0
			diamond.BackgroundColor3 = PING_COLOR
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.new(0, 0, 0)
			stroke.Transparency = 0.4
			stroke.Parent = diamond
			diamond.Parent = billboard
			anchor.Parent = effectsFolder()
			table.insert(pingParts, anchor)
			TweenService:Create(diamond, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
			task.delay(life, function()
				local idx = table.find(pingParts, anchor)
				if idx then
					table.remove(pingParts, idx)
				end
				anchor:Destroy()
			end)
		end
	end
end

local function clearMark(userId: number)
	local m = marks[userId]
	if m then
		marks[userId] = nil
		m.highlight:Destroy()
	end
end

local function clearMarks()
	for userId in marks do
		clearMark(userId)
	end
end

local function onMark(victimUserId: number, seconds: number)
	local victim = Players:GetPlayerByUserId(victimUserId)
	local character = victim and victim.Character
	if not character or victim == player then
		return
	end
	local untilAt = os.clock() + math.clamp(seconds, 0.1, 10)
	local m = marks[victimUserId]
	if m and m.highlight.Parent and m.highlight.Adornee == character then
		m.untilAt = untilAt
		return
	end
	clearMark(victimUserId)
	local h = Instance.new("Highlight")
	h.Name = "TrackerMark"
	h.Adornee = character
	h.FillColor = PING_COLOR
	h.FillTransparency = 0.75
	h.OutlineColor = PING_COLOR
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = effectsFolder()
	marks[victimUserId] = { highlight = h, untilAt = untilAt }
end

---------------------------------------------------------------------------------------------
-- Jammed / Blackout bookkeeping
---------------------------------------------------------------------------------------------

local function setEffects(jammed: number?, blackout: number?)
	local changed = false
	if jammed and ClientState.jammedUntil ~= jammed then
		ClientState.jammedUntil = jammed
		changed = true
	end
	if blackout and ClientState.blackoutUntil ~= blackout then
		ClientState.blackoutUntil = blackout
		changed = true
	end
	if changed then
		ClientState.HudEffectsChanged:Fire()
	end
end

local function victimOf(data: { [string]: any }): boolean
	local team = if type(data.team) == "string" and data.team ~= "" then data.team else nil
	local owner = if type(data.ownerUserId) == "number" then data.ownerUserId else nil
	return Phase5Rules.isVictim(team, owner, myTeam(), player.UserId)
end

local function onStreakEvent(kind: string, data: { [string]: any })
	if kind == "Incoming" then
		onIncoming(data)
	elseif kind == "Impact" then
		onImpact(data)
	elseif kind == "Jammed" then
		if victimOf(data) and type(data.endsAt) == "number" then
			setEffects(data.endsAt, nil)
		end
	elseif kind == "Blackout" then
		if victimOf(data) and type(data.endsAt) == "number" then
			setEffects(nil, data.endsAt)
		end
	elseif kind == "EffectEnded" then
		-- only clear what applies to us (an ended enemy-of-someone-else effect is not ours)
		if victimOf(data) then
			if data.streakId == "CounterRecon" then
				setEffects(0, nil)
			elseif data.streakId == "Blackout" then
				setEffects(nil, 0)
			end
		end
	end
end

local function clearAll()
	clearWarnings()
	clearPings()
	clearMarks()
	ClientState.ping = nil
	setEffects(0, 0)
	shakeUntil = 0
end

---------------------------------------------------------------------------------------------
-- Per-frame: warnings past their landing time, mark expiry, camera shake
---------------------------------------------------------------------------------------------

local function step()
	local now = os.clock()
	if #warnings > 0 then
		local t = serverNow()
		for i = #warnings, 1, -1 do
			if t > warnings[i].landsAt + 1.5 then
				removeWarning(i) -- the Impact never arrived (or was missed): don't leave it behind
			end
		end
	end
	for userId, m in marks do
		if now > m.untilAt or not m.highlight.Parent then
			clearMark(userId)
		end
	end
	if now < shakeUntil and ClientState.deployed then
		local camera = workspace.CurrentCamera
		if camera then
			local k = (shakeUntil - now) / SHAKE_TIME
			local s = shakeStrength * k
			-- translation only, after the camera has updated: the camera module rebuilds the
			-- position next frame, so nothing accumulates
			camera.CFrame = camera.CFrame * CFrame.new(rng:NextNumber(-s, s), rng:NextNumber(-s, s), 0)
		end
	end
end

function StreakController.init()
	ClientState.StreakEvent:Connect(onStreakEvent)
	ClientState.PingReceived:Connect(onPing)
	ClientState.Mark:Connect(onMark)
	ClientState.MatchStateChanged:Connect(function(ms)
		if ms.phase ~= "Playing" and ms.phase ~= "Countdown" then
			clearAll()
		end
	end)
	ClientState.DeployedChanged:Connect(function(deployed: boolean)
		if not deployed then
			shakeUntil = 0
		end
	end)
	UserInputService.InputBegan:Connect(onInput)
end

function StreakController.start()
	RunService:BindToRenderStep("COR_StreakFX", Enum.RenderPriority.Camera.Value + 3, step)
end

return StreakController
