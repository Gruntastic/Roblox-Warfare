--!strict
-- Phase 4 objective UI (Domination, Hardpoint, Search and Destroy, Kill Confirmed):
--   * top-centre objective strip under the HUD score bar (flags / hardpoint / S&D round state)
--   * world markers (AlwaysOnTop billboards + a subtle local ground outline) for active zones
--   * S&D plant / defuse prompt with a progress bar (ContextActionService: E, ButtonX, touch)
--   * Kill Confirmed dog-tag billboards (CONFIRM / DENY)
--   * queued centre-screen banners from ObjectiveEvent
--   * S&D spectating of living teammates while dead and the round is live
-- Everything is hidden outside a match or when the objective kind is "None" (TDM / FFA).
-- All world objects created here are client-only and non-colliding / non-query.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local Rules = require(Shared.Pure.ObjectiveRules)

local Objectives = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer
local myUserId = localPlayer.UserId

local NEUTRAL = Color3.fromRGB(196, 200, 206)
local TICK = 0.1 -- seconds between timer / distance / eligibility updates
local STRIP_Y = 142 -- virtual px: directly under the HUD score bar (70 + 64 + gap)
local INTERACT_ACTION = "COR_Interact"
local SPECTATE_ACTION = "COR_SpectateCycle"
local SPECTATE_ATTRIBUTE = "COR_Spectating" -- read by Controllers/CameraController
local MAX_WIN_PIPS = 8
local MAX_ALIVE_PIPS = 6
local MAX_QUEUED_BANNERS = 4
local PULSE = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local LINEAR = Enum.EasingStyle.Linear

---------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------

local gui: ScreenGui
local canvas: Frame
local active = false
local kind = "None"
local connections: { any } = {} -- RBXScriptConnections and Signal connections
local interactRemote: RemoteEvent? = nil

-- strip
local strip: Frame
local domFrame: Frame
type Chip = {
	holder: Frame,
	circle: CanvasGroup,
	fill: Frame,
	ring: UIStroke,
	letter: TextLabel,
	pulse: Tween?,
	progress: number,
	fillColor: Color3?,
}
local chips: { [string]: Chip } = {}
local chipKey = ""

local hpFrame: Frame
local hpStripe: Frame
local hpIcon: Frame
local hpStatus: TextLabel
local hpCaption: TextLabel
local hpTimer: TextLabel
local hpPulse: Tween? = nil
local hpTimerText = ""

local sndFrame: Frame
local roundLabel: TextLabel
local sndClock: TextLabel
local sndClockText = ""
local winPips: { left: { Frame }, right: { Frame } } = { left = {}, right = {} }
local alivePips: { left: { Frame }, right: { Frame } } = { left = {}, right = {} }
local aliveCount: { left: TextLabel?, right: TextLabel? } = { left = nil, right = nil }
local bombRow: Frame
local bombIcon: Frame
local bombLabel: TextLabel

-- markers
type Marker = {
	anchor: Part,
	edges: { Part },
	bb: BillboardGui,
	icon: Frame,
	letter: TextLabel,
	diamond: Frame,
	bombGlyph: Frame,
	dist: TextLabel,
	action: TextLabel,
	pulse: Tween?,
	gen: number,
	shown: boolean,
	lastDist: number,
	position: Vector3,
	size: Vector3?,
	yaw: number,
}
local fxFolder: Folder
local markers: { [string]: Marker } = {}
local markerGen = 0

-- dog tags
local tagGuis: { [Instance]: BillboardGui } = {}
local tagFolderConns: { RBXScriptConnection } = {}
local tagFolder: Instance? = nil

-- banners
local bannerGroup: CanvasGroup
local bannerScale: UIScale
local bannerTitle: TextLabel
local bannerSub: TextLabel
local bannerBar: Frame
local bannerQueue: { Rules.Banner } = {}
local bannerBusy = false
local bannerToken = 0
local hardpointAnnounced = false

-- interact
local promptFrame: Frame
local promptText: TextLabel
local promptTrack: Frame
local promptFill: Frame
local promptTween: Tween? = nil
local progressEndsAt: number? = nil
local boundKind: string? = nil
local holding = false

-- spectate / eliminated
local specFrame: Frame
local specTitle: TextLabel
local specName: TextLabel
local specHint: TextLabel
local specPrev: TextButton
local specNext: TextButton
local spectating = false
local specTarget: number? = nil
local diedAt: number? = nil
local savedCamera: { mode: Enum.CameraMode, minZoom: number, maxZoom: number }? = nil

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function track(conn: any)
	table.insert(connections, conn)
end

local function circleCorner(): UICorner
	return Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

local NO_ZONES: { Types.ZoneState } = {}
local NO_PLAYERS: { Types.PlayerLine } = {}

local function zonesOf(obj: Types.ObjectivePayload): { Types.ZoneState }
	return if type(obj.zones) == "table" then obj.zones else NO_ZONES
end

local function playersOf(ms: Types.MatchStatePayload): { Types.PlayerLine }
	return if type(ms.players) == "table" then ms.players else NO_PLAYERS
end

local function teamColorOrNeutral(teamId: string?): Color3
	return if teamId then Theme.teamColor(teamId) else NEUTRAL
end

local function lineFor(uid: number): Types.PlayerLine?
	local ms = ClientState.matchState
	if not ms then
		return nil
	end
	for _, line in playersOf(ms) do
		if line.userId == uid then
			return line
		end
	end
	return nil
end

local function nameOf(uid: number): string?
	local line = lineFor(uid)
	if line then
		return line.name
	end
	local p = Players:GetPlayerByUserId(uid)
	return if p then p.Name else nil
end

local function isInMatch(ms: Types.MatchStatePayload): boolean
	if ClientState.deployed then
		return true
	end
	for _, id in (ms.inMatch or {}) :: { number } do
		if id == myUserId then
			return true
		end
	end
	return false
end

local function computeActive(): boolean
	local ms = ClientState.matchState
	if not ms or (ms.phase ~= "Countdown" and ms.phase ~= "Playing") then
		return false
	end
	if Theme.objectiveKind() == "None" then
		return false
	end
	return isInMatch(ms)
end

local function localRoot(): BasePart?
	local character = localPlayer.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function setPulse(current: Tween?, inst: Instance, prop: string, on: boolean, rest: number, peak: number): Tween?
	if on then
		if current then
			return current
		end
		(inst :: any)[prop] = rest
		return Theme.tween(inst, PULSE, { [prop] = peak })
	end
	if current then
		current:Cancel();
		(inst :: any)[prop] = rest
	end
	return nil
end

local function toneColor(tone: string): Color3
	if tone == "Friendly" then
		local team = Theme.localTeam()
		return if team then Theme.teamColor(team) else C.Positive
	elseif tone == "Enemy" then
		return C.Danger
	elseif tone == "Accent" then
		return C.Accent
	end
	return C.Text
end

local function defendersOf(round: Types.RoundState?): string?
	return if round then Theme.otherTeam(round.attackers) else nil
end

---------------------------------------------------------------------------------------------
-- Banners (one at a time; queued, never overlapping)
---------------------------------------------------------------------------------------------

local function runBanners()
	bannerBusy = true
	local token = bannerToken
	while #bannerQueue > 0 and token == bannerToken do
		local b = table.remove(bannerQueue, 1) :: Rules.Banner
		local color = toneColor(b.tone)
		bannerTitle.Text = b.title
		bannerTitle.TextColor3 = if b.tone == "Neutral" then C.Text else color
		bannerSub.Text = b.sub or ""
		bannerSub.Visible = b.sub ~= nil
		bannerBar.BackgroundColor3 = color
		bannerGroup.Visible = true
		bannerGroup.GroupTransparency = 1
		bannerScale.Scale = 1.12
		Theme.tween(bannerScale, Theme.Tween.Pop, { Scale = 1 })
		Theme.tween(bannerGroup, Theme.Tween.Fast, { GroupTransparency = 0 })
		-- a backlog shortens each banner so announcements stay timely
		local hold = if #bannerQueue > 0 then b.duration * 0.65 else b.duration
		task.wait(0.15 + hold)
		if token ~= bannerToken then
			break
		end
		Theme.tween(bannerGroup, Theme.Tween.Normal, { GroupTransparency = 1 })
		task.wait(0.25)
	end
	if token == bannerToken then
		bannerGroup.Visible = false
		bannerBusy = false
	end
end

local function pushBanner(b: Rules.Banner)
	while #bannerQueue >= MAX_QUEUED_BANNERS do
		table.remove(bannerQueue, 1)
	end
	table.insert(bannerQueue, b)
	if not bannerBusy then
		task.spawn(runBanners)
	end
end

local function clearBanners()
	table.clear(bannerQueue)
	bannerToken += 1
	bannerBusy = false
	bannerGroup.Visible = false
end

---------------------------------------------------------------------------------------------
-- Domination chips
---------------------------------------------------------------------------------------------

local function buildChip(zone: Types.ZoneState, order: number): Chip
	local holder: Frame = Theme.new("Frame", {
		Name = "Flag" .. zone.id,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(52, 52),
		LayoutOrder = order,
		Parent = domFrame,
	})
	local circle: CanvasGroup = Theme.new("CanvasGroup", {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	}, { circleCorner() })
	local fill: Frame = Theme.new("Frame", {
		Name = "Progress",
		BorderSizePixel = 0,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		Parent = circle,
	})
	local ringFrame: Frame = Theme.new("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = holder,
	}, { circleCorner() })
	local ring: UIStroke = Theme.new("UIStroke", {
		Color = NEUTRAL,
		Thickness = 3,
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ringFrame,
	})
	local letter = Theme.label({
		Text = if zone.label ~= "" then zone.label else zone.id,
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = holder,
	})
	Theme.new("UIStroke", { Color = C.Black, Thickness = 1, Transparency = 0.5, Parent = letter })
	return { holder = holder, circle = circle, fill = fill, ring = ring, letter = letter, pulse = nil, progress = -1, fillColor = nil }
end

local function refreshDomination(obj: Types.ObjectivePayload)
	local zones = zonesOf(obj)
	local key = ""
	for _, z in zones do
		key ..= z.id .. ","
	end
	if key ~= chipKey then
		chipKey = key
		for _, chip in chips do
			if chip.pulse then
				chip.pulse:Cancel()
			end
			chip.holder:Destroy()
		end
		table.clear(chips)
		for i, z in zones do
			chips[z.id] = buildChip(z, i)
		end
	end
	for _, z in zones do
		local chip = chips[z.id]
		if chip then
			local ownerColor = teamColorOrNeutral(z.owner)
			chip.circle.BackgroundColor3 = if z.owner then ownerColor:Lerp(C.Black, 0.55) else C.Panel
			local fillColor = teamColorOrNeutral(z.capturingTeam)
			if chip.fillColor ~= fillColor then
				chip.fillColor = fillColor
				chip.fill.BackgroundColor3 = fillColor
			end
			local progress = math.clamp(if type(z.progress) == "number" then z.progress else 0, 0, 1)
			if z.capturingTeam == nil then
				progress = 0
			end
			if math.abs(progress - chip.progress) > 0.001 then
				chip.progress = progress
				Theme.tween(chip.fill, Theme.Tween.Normal, { Size = UDim2.fromScale(1, progress) })
			end
			chip.ring.Color = if z.contested then C.Accent else ownerColor
			chip.pulse = setPulse(chip.pulse, chip.ring, "Transparency", z.contested == true, 0, 0.75)
		end
	end
end

---------------------------------------------------------------------------------------------
-- Hardpoint strip
---------------------------------------------------------------------------------------------

local function liveHardpoint(obj: Types.ObjectivePayload): Types.ZoneState?
	for _, z in zonesOf(obj) do
		if z.active then
			return z
		end
	end
	return nil
end

local function refreshHardpoint(obj: Types.ObjectivePayload)
	local zone = liveHardpoint(obj)
	local myTeam = Theme.localTeam()
	local status = Rules.hardpointStatus(zone, myTeam)
	local color: Color3
	local text: string
	if not zone then
		color, text = NEUTRAL, "HARDPOINT INBOUND"
	elseif status == "Contested" then
		color, text = C.Accent, "CONTESTED"
	elseif status == "Friendly" then
		color, text = Theme.teamColor(myTeam), "SECURED"
	elseif status == "Enemy" then
		color, text = teamColorOrNeutral(zone.owner or zone.capturingTeam), "ENEMY HOLDS"
	else
		color, text = NEUTRAL, "UNCLAIMED"
	end
	hpStatus.Text = text
	hpStatus.TextColor3 = if status == "Neutral" then C.Text else color
	hpStripe.BackgroundColor3 = color
	hpIcon.BackgroundColor3 = color
	hpCaption.Text = if zone then "MOVES IN" else "ONLINE IN"
	hpPulse = setPulse(hpPulse, hpIcon, "BackgroundTransparency", status == "Contested", 0, 0.7)
end

local function updateHardpointTimer(obj: Types.ObjectivePayload)
	local at = obj.hardpointMovesAt
	local text = if type(at) == "number" and at > 0 then Theme.formatTime(at - Theme.serverNow()) else "--:--"
	if text ~= hpTimerText then
		hpTimerText = text
		hpTimer.Text = text
	end
end

---------------------------------------------------------------------------------------------
-- Search and Destroy strip
---------------------------------------------------------------------------------------------

local function teamSize(ms: Types.MatchStatePayload?, teamId: string?): number
	if not ms or not teamId then
		return 0
	end
	local n = 0
	for _, line in playersOf(ms) do
		if line.team == teamId then
			n += 1
		end
	end
	return n
end

local function paintPips(pips: { Frame }, filled: number, total: number, color: Color3)
	for i, pip in pips do
		pip.Visible = i <= total
		if i <= filled then
			pip.BackgroundColor3 = color
			pip.BackgroundTransparency = 0
		else
			pip.BackgroundColor3 = C.Locked
			pip.BackgroundTransparency = 0.35
		end
	end
end

local function bombStatus(obj: Types.ObjectivePayload, myTeam: string?): (string, Color3)
	local bomb, round = obj.bomb, obj.round
	if not bomb or not round then
		return "", C.Text
	end
	local attacking = myTeam ~= nil and myTeam == round.attackers
	local site = if type(bomb.site) == "string" then bomb.site else "?"
	if bomb.state == "Planted" then
		if bomb.actionKind == "Defuse" and bomb.actionUserId ~= nil then
			if bomb.actionUserId == myUserId then
				return "DEFUSING...", C.Accent
			end
			return "BOMB BEING DEFUSED", if attacking then C.Danger else C.Positive
		end
		return "BOMB PLANTED · SITE " .. site, C.Danger
	elseif bomb.state == "Carried" then
		if bomb.carrierUserId == myUserId then
			if bomb.actionKind == "Plant" and bomb.actionUserId == myUserId then
				return "PLANTING...", C.Accent
			end
			return "YOU HAVE THE BOMB", C.Accent
		elseif attacking then
			local who = if bomb.carrierUserId then nameOf(bomb.carrierUserId) else nil
			return "BOMB CARRIED" .. (if who then " · " .. string.upper(who) else ""), Theme.teamColor(myTeam)
		end
		return "", C.Text -- defenders are not told who carries the bomb
	elseif bomb.state == "Dropped" then
		return if attacking then "BOMB DROPPED · RECOVER IT" else "BOMB DROPPED", if attacking then C.Danger else C.TextDim
	elseif bomb.state == "Defused" then
		return "BOMB DEFUSED", C.TextDim
	elseif bomb.state == "Detonated" then
		return "SITE " .. site .. " DESTROYED", C.TextDim
	end
	return "", C.Text
end

local function refreshSnD(obj: Types.ObjectivePayload)
	local round = obj.round
	local ms = ClientState.matchState
	local myTeam = Theme.localTeam()
	if not round then
		roundLabel.Text = "SEARCH AND DESTROY"
		bombRow.Visible = false
		return
	end
	local mine = myTeam or round.attackers
	local enemy = Theme.otherTeam(mine)
	local attacking = mine == round.attackers
	local sideColor = if attacking then C.Danger else Theme.teamColor(mine)
	roundLabel.Text = string.format(
		'ROUND %d  ·  <font color="%s">%s</font>',
		if type(round.number) == "number" then round.number else 1,
		Theme.hex(sideColor),
		if myTeam then (if attacking then "ATTACK" else "DEFEND") else "SPECTATING"
	)

	local wins = round.wins or {}
	local toWin = math.clamp(if type(round.roundsToWin) == "number" then round.roundsToWin else 4, 1, MAX_WIN_PIPS)
	paintPips(winPips.left, wins[mine] or 0, toWin, Theme.teamColor(mine))
	paintPips(winPips.right, if enemy then wins[enemy] or 0 else 0, toWin, teamColorOrNeutral(enemy))

	local alive = round.alive or {}
	local function sideAlive(pips: { Frame }, label: TextLabel?, teamId: string?)
		local n = if teamId then alive[teamId] or 0 else 0
		local total = math.max(teamSize(ms, teamId), n)
		paintPips(pips, n, math.min(total, MAX_ALIVE_PIPS), teamColorOrNeutral(teamId))
		if label then
			label.Text = tostring(n)
			label.TextColor3 = if n > 0 then teamColorOrNeutral(teamId) else C.TextMuted
		end
	end
	sideAlive(alivePips.left, aliveCount.left, mine)
	sideAlive(alivePips.right, aliveCount.right, enemy)

	local text, color = bombStatus(obj, myTeam)
	bombRow.Visible = text ~= ""
	bombLabel.Text = text
	bombLabel.TextColor3 = color
	bombIcon.BackgroundColor3 = color
end

local function updateSnDClock(obj: Types.ObjectivePayload)
	local round, bomb = obj.round, obj.bomb
	local text = ""
	local danger = false
	if bomb and bomb.state == "Planted" and type(bomb.explodesAt) == "number" then
		text = Theme.formatTime(bomb.explodesAt - Theme.serverNow())
		danger = true
	elseif round and type(round.endsAt) == "number" and round.endsAt > 0 then
		text = Theme.formatTime(round.endsAt - Theme.serverNow())
	end
	if text ~= sndClockText then
		sndClockText = text
		sndClock.Text = text
		sndClock.TextColor3 = if danger then C.Danger else C.Text
	end
end

---------------------------------------------------------------------------------------------
-- World markers + ground outlines
---------------------------------------------------------------------------------------------

local function localPart(name: string, parent: Instance): Part
	return Theme.new("Part", {
		Name = name,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Material = Enum.Material.Neon,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		Parent = parent,
	})
end

local function buildMarker(id: string): Marker
	local anchor = localPart("Marker_" .. id, fxFolder)
	local edges = {}
	for i = 1, 4 do
		local edge = localPart("Edge", anchor)
		edge.Transparency = 1
		edges[i] = edge
	end
	local bb: BillboardGui = Theme.new("BillboardGui", {
		Name = "Marker",
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(96, 78),
		StudsOffsetWorldSpace = Vector3.new(0, 6, 0),
		MaxDistance = 10000,
		Enabled = false,
		Parent = anchor,
	})
	local icon: Frame = Theme.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = NEUTRAL,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = bb,
	}, { circleCorner() :: Instance, Theme.stroke(C.White, 2, 0.15) })
	local letter = Theme.label({
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		Parent = icon,
	})
	-- hardpoint glyph: a white diamond with a dark core
	local diamond: Frame = Theme.new("Frame", {
		Name = "Diamond",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		Rotation = 45,
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Visible = false,
		Parent = icon,
	})
	Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Parent = diamond,
	})
	-- bomb glyph: a small charge with a fuse stripe
	local bombGlyph: Frame = Theme.new("Frame", {
		Name = "Bomb",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(20, 13),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Visible = false,
		Parent = icon,
	}, { Theme.corner(2) :: Instance, Theme.stroke(C.White, 1, 0.2) })
	Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -6, 0, 3),
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Parent = bombGlyph,
	})
	local action = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = bb,
	})
	Theme.new("UIStroke", { Color = C.Black, Thickness = 1, Transparency = 0.35, Parent = action })
	local dist = Theme.label({
		Font = Theme.Fonts.Medium,
		TextSize = 11,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = bb,
	})
	Theme.new("UIStroke", { Color = C.Black, Thickness = 1, Transparency = 0.35, Parent = dist })
	return {
		anchor = anchor,
		edges = edges,
		bb = bb,
		icon = icon,
		letter = letter,
		diamond = diamond,
		bombGlyph = bombGlyph,
		dist = dist,
		action = action,
		pulse = nil,
		gen = 0,
		shown = false,
		lastDist = -1,
		position = Vector3.zero,
		size = nil,
		yaw = 0,
	}
end

type MarkerStyle = {
	position: Vector3,
	size: Vector3?, -- nil = no ground outline
	yaw: number,
	color: Color3,
	glyph: "Letter" | "Diamond" | "Bomb",
	letter: string,
	action: string,
	pulse: boolean,
	height: number,
}

local function placeOutline(m: Marker, position: Vector3, size: Vector3?, yaw: number)
	if m.position == position and m.size == size and m.yaw == yaw then
		return
	end
	m.position, m.size, m.yaw = position, size, yaw
	local base = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	m.anchor.CFrame = base
	if not size then
		for _, edge in m.edges do
			edge.Transparency = 1
		end
		return
	end
	local t, h, lift = 0.35, 0.12, 0.08
	local hx, hz = size.X / 2, size.Z / 2
	m.edges[1].Size = Vector3.new(size.X, h, t)
	m.edges[1].CFrame = base * CFrame.new(0, lift, -hz)
	m.edges[2].Size = Vector3.new(size.X, h, t)
	m.edges[2].CFrame = base * CFrame.new(0, lift, hz)
	m.edges[3].Size = Vector3.new(t, h, size.Z)
	m.edges[3].CFrame = base * CFrame.new(-hx, lift, 0)
	m.edges[4].Size = Vector3.new(t, h, size.Z)
	m.edges[4].CFrame = base * CFrame.new(hx, lift, 0)
end

local function showMarker(id: string, style: MarkerStyle)
	local m = markers[id]
	if not m then
		m = buildMarker(id)
		markers[id] = m
	end
	m.gen = markerGen
	placeOutline(m, style.position, style.size, style.yaw)
	if style.size then
		for _, edge in m.edges do
			edge.Color = style.color
			edge.Transparency = 0.55
		end
	end
	m.bb.StudsOffsetWorldSpace = Vector3.new(0, style.height, 0)
	m.icon.BackgroundColor3 = style.color
	m.letter.Text = if style.glyph == "Letter" then style.letter else ""
	m.diamond.Visible = style.glyph == "Diamond"
	m.bombGlyph.Visible = style.glyph == "Bomb"
	m.action.Text = style.action
	m.action.TextColor3 = style.color
	m.pulse = setPulse(m.pulse, m.icon, "BackgroundTransparency", style.pulse, 0.2, 0.75)
	if not m.shown then
		m.shown = true
		m.lastDist = -1
		m.bb.Enabled = true
	end
end

local function hideStaleMarkers()
	for _, m in markers do
		if m.gen ~= markerGen and m.shown then
			m.shown = false
			m.bb.Enabled = false
			m.pulse = setPulse(m.pulse, m.icon, "BackgroundTransparency", false, 0.2, 0.75)
			for _, edge in m.edges do
				edge.Transparency = 1
			end
		end
	end
end

local function zoneHeight(z: Types.ZoneState): number
	local y = if typeof(z.size) == "Vector3" then z.size.Y else 6
	return math.max(y, 4) + 2.5
end

local function refreshMarkers(obj: Types.ObjectivePayload)
	markerGen += 1
	local myTeam = Theme.localTeam()
	if kind == "Domination" then
		for _, z in zonesOf(obj) do
			if typeof(z.position) == "Vector3" then
				local color = if z.contested then C.Accent else teamColorOrNeutral(z.owner)
				showMarker(z.id, {
					position = z.position,
					size = z.size,
					yaw = z.yaw or 0,
					color = color,
					glyph = "Letter",
					letter = if z.label ~= "" then z.label else z.id,
					action = if z.contested then "CONTESTED" elseif z.owner ~= nil and z.owner == myTeam then "DEFEND" else "CAPTURE",
					pulse = z.contested == true,
					height = zoneHeight(z),
				})
			end
		end
	elseif kind == "Hardpoint" then
		local z = liveHardpoint(obj)
		if z and typeof(z.position) == "Vector3" then
			local status = Rules.hardpointStatus(z, myTeam)
			local color = if status == "Contested" then C.Accent elseif status == "Neutral" then NEUTRAL else teamColorOrNeutral(z.owner or z.capturingTeam)
			showMarker(z.id, {
				position = z.position,
				size = z.size,
				yaw = z.yaw or 0,
				color = color,
				glyph = "Diamond",
				letter = "",
				action = if status == "Contested" then "CONTESTED" elseif status == "Friendly" then "DEFEND" else "CAPTURE",
				pulse = status == "Contested",
				height = zoneHeight(z),
			})
		end
	elseif kind == "SnD" then
		local round, bomb = obj.round, obj.bomb
		local attackers = if round then round.attackers else nil
		local attacking = myTeam ~= nil and myTeam == attackers
		local planted = bomb ~= nil and bomb.state == "Planted"
		if not planted then
			local siteColor = teamColorOrNeutral(defendersOf(round))
			local carrying = bomb ~= nil and bomb.state == "Carried" and bomb.carrierUserId == myUserId
			for _, z in zonesOf(obj) do
				if z.active ~= false and typeof(z.position) == "Vector3" then
					showMarker(z.id, {
						position = z.position,
						size = z.size,
						yaw = z.yaw or 0,
						color = siteColor,
						glyph = "Letter",
						letter = if z.label ~= "" then z.label else z.id,
						action = if carrying then "PLANT" elseif attacking then "ATTACK" elseif myTeam then "DEFEND" else "",
						pulse = false,
						height = zoneHeight(z),
					})
				end
			end
		end
		if bomb and typeof(bomb.position) == "Vector3" then
			if planted then
				showMarker("__bomb", {
					position = bomb.position :: Vector3,
					size = nil,
					yaw = 0,
					color = C.Danger,
					glyph = "Letter",
					letter = if type(bomb.site) == "string" then bomb.site else "!",
					action = if attacking then "DEFEND" elseif myTeam then "DEFUSE" else "BOMB",
					pulse = true,
					height = 3,
				})
			elseif bomb.state == "Dropped" and attacking then
				showMarker("__bomb", {
					position = bomb.position :: Vector3,
					size = nil,
					yaw = 0,
					color = C.Accent,
					glyph = "Bomb",
					letter = "",
					action = "PICK UP",
					pulse = false,
					height = 3,
				})
			end
		end
	end
	hideStaleMarkers()
end

local function updateDistances()
	local root = localRoot()
	local camera = workspace.CurrentCamera
	local from = if root then root.Position elseif camera then camera.CFrame.Position else nil
	if not from then
		return
	end
	for _, m in markers do
		if m.shown then
			local d = math.floor((m.position - from).Magnitude + 0.5)
			if d ~= m.lastDist then
				m.lastDist = d
				m.dist.Text = string.format("%d STUDS", d)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Kill Confirmed dog tags
---------------------------------------------------------------------------------------------

local function styleTag(tag: Instance, bb: BillboardGui)
	local team = tag:GetAttribute("Team")
	local myTeam = Theme.localTeam()
	local friendly = type(team) == "string" and myTeam ~= nil and team == myTeam
	local color = if friendly then Theme.teamColor(myTeam) else Color3.fromRGB(235, 88, 72)
	local icon = bb:FindFirstChild("Icon") :: Frame?
	local label = bb:FindFirstChild("Label") :: TextLabel?
	if icon then
		icon.BackgroundColor3 = color
	end
	if label then
		label.Text = if friendly then "DENY" else "CONFIRM"
		label.TextColor3 = color
	end
end

local function decorateTag(tag: Instance)
	if tagGuis[tag] then
		return
	end
	local adornee: BasePart? = nil
	if tag:IsA("BasePart") then
		adornee = tag
	elseif tag:IsA("Model") then
		adornee = tag.PrimaryPart or tag:FindFirstChildWhichIsA("BasePart")
	end
	if not adornee then
		return
	end
	local bb: BillboardGui = Theme.new("BillboardGui", {
		Name = "COR_TagMarker",
		Adornee = adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(80, 34),
		StudsOffsetWorldSpace = Vector3.new(0, 1.8, 0),
		MaxDistance = 250,
		Enabled = active,
	})
	Theme.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(11, 11),
		Rotation = 45,
		BorderSizePixel = 0,
		Parent = bb,
	}, { Theme.stroke(C.White, 1, 0.2) })
	local label = Theme.label({
		Name = "Label",
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = bb,
	})
	Theme.new("UIStroke", { Color = C.Black, Thickness = 1, Transparency = 0.35, Parent = label })
	styleTag(tag, bb)
	bb.Parent = tag
	tagGuis[tag] = bb
end

local function restyleTags()
	for tag, bb in tagGuis do
		if tag.Parent then
			styleTag(tag, bb)
			bb.Enabled = active
		else
			tagGuis[tag] = nil
		end
	end
end

local function unwatchTags()
	for _, conn in tagFolderConns do
		conn:Disconnect()
	end
	table.clear(tagFolderConns)
	for _, bb in tagGuis do
		bb:Destroy()
	end
	table.clear(tagGuis)
	tagFolder = nil
end

local function watchTags(folder: Instance)
	if tagFolder == folder then
		return
	end
	unwatchTags()
	tagFolder = folder
	table.insert(tagFolderConns, folder.ChildAdded:Connect(decorateTag))
	table.insert(
		tagFolderConns,
		folder.ChildRemoved:Connect(function(child)
			tagGuis[child] = nil
		end)
	)
	for _, child in folder:GetChildren() do
		decorateTag(child)
	end
end

---------------------------------------------------------------------------------------------
-- Interact (plant / defuse)
---------------------------------------------------------------------------------------------

local function sendInteract(on: boolean)
	if holding == on then
		return
	end
	holding = on
	ClientState.interacting = on
	if interactRemote then
		interactRemote:FireServer(on)
	end
end

local function interactAction(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		sendInteract(true)
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		sendInteract(false)
	end
	return Enum.ContextActionResult.Sink
end

local function keyText(): string
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return ""
	end
	local name = last.Name
	if string.sub(name, 1, 7) == "Gamepad" then
		return "X"
	end
	return "E"
end

local function refreshPromptText()
	if not boundKind then
		return
	end
	local verb = if boundKind == "Plant" then "PLANT" else "DEFUSE"
	local key = keyText()
	if key == "" then
		promptText.Text = string.format("HOLD  <font color=\"%s\">%s</font>", Theme.hex(C.Accent), verb)
	else
		promptText.Text = string.format("HOLD  <font color=\"%s\">[%s]</font>  TO %s", Theme.hex(C.Accent), key, verb)
	end
end

local function unbindInteract()
	if boundKind then
		boundKind = nil
		ContextActionService:UnbindAction(INTERACT_ACTION)
	end
	sendInteract(false)
end

local function bindInteract(k: string)
	if boundKind == k then
		return
	end
	if boundKind then
		ContextActionService:UnbindAction(INTERACT_ACTION)
	end
	boundKind = k
	-- High priority so ButtonX plants instead of reloading while eligible; unbound otherwise.
	ContextActionService:BindActionAtPriority(
		INTERACT_ACTION,
		interactAction,
		true,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.E,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:SetTitle(INTERACT_ACTION, if k == "Plant" then "PLANT" else "DEFUSE")
	refreshPromptText()
end

local function setProgress(obj: Types.ObjectivePayload?)
	local bomb = if obj then obj.bomb else nil
	local mine = bomb ~= nil and bomb.actionUserId == myUserId and type(bomb.actionEndsAt) == "number"
	if not mine or not bomb then
		if progressEndsAt then
			progressEndsAt = nil
			if promptTween then
				promptTween:Cancel()
				promptTween = nil
			end
			promptFill.Size = UDim2.fromScale(0, 1)
		end
		promptTrack.Visible = false
		return
	end
	promptTrack.Visible = true
	local endsAt = bomb.actionEndsAt :: number
	if progressEndsAt == endsAt then
		return
	end
	progressEndsAt = endsAt
	local ms = ClientState.matchState
	local mode = if ms then Theme.Modes[ms.modeId] else nil
	local total = (if bomb.actionKind == "Defuse" then mode and mode.defuseTime else mode and mode.plantTime) or 5
	local remaining = math.max(0, endsAt - Theme.serverNow())
	local alpha = math.clamp(1 - remaining / math.max(total, 0.1), 0, 1)
	if promptTween then
		promptTween:Cancel()
	end
	promptFill.Size = UDim2.fromScale(alpha, 1)
	-- one linear tween to the server's completion time: no per-frame work
	promptTween = Theme.tween(promptFill, TweenInfo.new(remaining, LINEAR), { Size = UDim2.fromScale(1, 1) })
end

local function refreshInteract()
	local obj = ClientState.objective
	local root = localRoot()
	local eligible: string? = nil
	if active and kind == "SnD" and ClientState.deployed and root then
		eligible = Rules.interactKind({
			objective = obj,
			userId = myUserId,
			team = Theme.localTeam(),
			position = root.Position,
			alive = true,
		})
	end
	if eligible then
		bindInteract(eligible)
	else
		unbindInteract()
	end
	promptFrame.Visible = eligible ~= nil
	setProgress(if eligible then obj else nil)
end

---------------------------------------------------------------------------------------------
-- Spectating (S&D, dead, round live)
---------------------------------------------------------------------------------------------

local function humanoidOf(uid: number): Humanoid?
	local p = Players:GetPlayerByUserId(uid)
	local character = p and p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

local function livingTeammates(): { number }
	local ids = {}
	local myTeam = Theme.localTeam()
	local ms = ClientState.matchState
	if not myTeam or not ms then
		return ids
	end
	for _, line in playersOf(ms) do
		if line.team == myTeam and line.userId ~= myUserId and humanoidOf(line.userId) then
			table.insert(ids, line.userId)
		end
	end
	table.sort(ids)
	return ids
end

local function setSpectateTarget(uid: number?)
	specTarget = uid
	local humanoid = if uid then humanoidOf(uid) else nil
	local camera = workspace.CurrentCamera
	if humanoid and camera then
		camera.CameraSubject = humanoid
	end
	if uid and humanoid then
		specName.Text = string.upper(nameOf(uid) or "TEAMMATE")
		specName.TextColor3 = Theme.teamColor(Theme.localTeam())
		specTitle.Text = "SPECTATING"
	else
		specName.Text = "NO TEAMMATES ALIVE"
		specName.TextColor3 = C.TextDim
		specTitle.Text = ""
	end
end

local function cycleSpectate(dir: number)
	if not spectating then
		return
	end
	setSpectateTarget(Rules.cycle(livingTeammates(), specTarget, dir))
end

local function spectateAction(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		local back = input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL1
		cycleSpectate(if back then -1 else 1)
	end
	return Enum.ContextActionResult.Sink
end

local function startSpectating()
	if spectating then
		return
	end
	spectating = true
	savedCamera = {
		mode = localPlayer.CameraMode,
		minZoom = localPlayer.CameraMinZoomDistance,
		maxZoom = localPlayer.CameraMaxZoomDistance,
	}
	-- third-person follow view of the teammate (the game is otherwise LockFirstPerson)
	localPlayer.CameraMode = Enum.CameraMode.Classic
	localPlayer.CameraMaxZoomDistance = 16
	localPlayer.CameraMinZoomDistance = 9
	localPlayer:SetAttribute(SPECTATE_ATTRIBUTE, true)
	ContextActionService:BindActionAtPriority(
		SPECTATE_ACTION,
		spectateAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.MouseButton2,
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.ButtonL1
	)
	specHint.Visible = true
	specPrev.Visible = UserInputService.TouchEnabled
	specNext.Visible = UserInputService.TouchEnabled
	setSpectateTarget(Rules.cycle(livingTeammates(), specTarget, 1))
end

local function stopSpectating()
	if not spectating then
		return
	end
	spectating = false
	specTarget = nil
	ContextActionService:UnbindAction(SPECTATE_ACTION)
	localPlayer:SetAttribute(SPECTATE_ATTRIBUTE, nil)
	if savedCamera then
		localPlayer.CameraMinZoomDistance = savedCamera.minZoom
		localPlayer.CameraMaxZoomDistance = savedCamera.maxZoom
		localPlayer.CameraMode = savedCamera.mode
		savedCamera = nil
	end
	-- give the camera back to our own character if we already respawned (CameraController also
	-- re-applies this once it sees CameraType ~= Custom)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local camera = workspace.CurrentCamera
	if humanoid and humanoid.Health > 0 and camera then
		camera.CameraSubject = humanoid
	end
	specHint.Visible = false
	specPrev.Visible = false
	specNext.Visible = false
	specTitle.Text = ""
	specName.Text = ""
end

local function refreshSpectate()
	local obj = ClientState.objective
	local round = if obj then obj.round else nil
	local ms = ClientState.matchState
	local deadInSnD = active and kind == "SnD" and not ClientState.deployed and ms ~= nil and ms.phase == "Playing"
	specFrame.Visible = deadInSnD
	local want = deadInSnD
		and round ~= nil
		and round.live == true
		and Theme.localTeam() ~= nil
		and diedAt ~= nil
		and os.clock() - (diedAt :: number) >= Theme.SnDDeathHold
	if not want then
		stopSpectating()
		return
	end
	startSpectating()
	-- keep following someone alive; switch when the current target dies
	if not specTarget or not humanoidOf(specTarget) then
		setSpectateTarget(Rules.cycle(livingTeammates(), specTarget, 1))
	end
end

---------------------------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------------------------

local function refreshAll()
	if not active then
		return
	end
	local obj = ClientState.objective
	if not obj then
		return
	end
	domFrame.Visible = kind == "Domination"
	hpFrame.Visible = kind == "Hardpoint"
	sndFrame.Visible = kind == "SnD"
	if kind == "Domination" then
		refreshDomination(obj)
	elseif kind == "Hardpoint" then
		refreshHardpoint(obj)
		updateHardpointTimer(obj)
	elseif kind == "SnD" then
		refreshSnD(obj)
		updateSnDClock(obj)
	end
	refreshMarkers(obj)
	updateDistances()
	refreshInteract()
	restyleTags()
end

local function refreshActive()
	local was = active
	active = computeActive()
	kind = if active then Theme.objectiveKind() else "None"
	if active ~= was then
		gui.Enabled = active
		fxFolder.Parent = if active then workspace else nil
		if not active then
			clearBanners()
			unbindInteract()
			promptFrame.Visible = false
			stopSpectating()
			specFrame.Visible = false
			hardpointAnnounced = false
			restyleTags()
		end
	end
	refreshAll()
	refreshSpectate()
end

local function onObjectiveEvent(eventKind: string, data: { [string]: any })
	if not active or type(eventKind) ~= "string" then
		return
	end
	local obj = ClientState.objective
	local round = if obj then obj.round else nil
	local banner = Rules.banner(eventKind, if type(data) == "table" then data else {}, {
		userId = myUserId,
		team = Theme.localTeam(),
		attackers = if round then round.attackers else nil,
		nameOf = nameOf,
		firstHardpoint = not hardpointAnnounced,
	})
	if eventKind == "HardpointMoved" then
		hardpointAnnounced = true
	end
	if banner then
		pushBanner(banner)
	end
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------

local function buildStrip()
	strip = Theme.new("Frame", {
		Name = "Strip",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, STRIP_Y),
		Size = UDim2.fromOffset(560, 100),
		Parent = canvas,
	})

	-- Domination: A / B / C chips
	domFrame = Theme.new("Frame", {
		Name = "Domination",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 52),
		Visible = false,
		Parent = strip,
	}, { Theme.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center) })

	-- Hardpoint: status + rotation countdown
	hpFrame = Theme.panel({
		Name = "Hardpoint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(330, 46),
		Visible = false,
		Parent = strip,
	})
	hpStripe = Theme.new("Frame", { BorderSizePixel = 0, BackgroundColor3 = NEUTRAL, Size = UDim2.new(0, 4, 1, 0), Parent = hpFrame })
	hpIcon = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 28, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		Rotation = 45,
		BackgroundColor3 = NEUTRAL,
		BorderSizePixel = 0,
		Parent = hpFrame,
	})
	Theme.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Parent = hpIcon,
	})
	hpStatus = Theme.label({
		Font = Theme.Fonts.Title,
		TextSize = 18,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -150, 1, 0),
		Parent = hpFrame,
	})
	hpCaption = Theme.label({
		Text = "MOVES IN",
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 5),
		Size = UDim2.fromOffset(90, 12),
		Parent = hpFrame,
	})
	hpTimer = Theme.label({
		Text = "--:--",
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 17),
		Size = UDim2.fromOffset(90, 24),
		Parent = hpFrame,
	})

	-- Search and Destroy: round / side / clock, win pips, alive pips, bomb status
	sndFrame = Theme.new("Frame", {
		Name = "SnD",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = strip,
	})
	local top = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(460, 50),
		Parent = sndFrame,
	})
	roundLabel = Theme.label({
		RichText = true,
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(220, 18),
		Parent = top,
	})
	sndClock = Theme.label({
		Font = Theme.Fonts.Title,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 23),
		Size = UDim2.fromOffset(120, 22),
		Parent = top,
	})
	local function winRow(isLeft: boolean): { Frame }
		local holder: Frame = Theme.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(if isLeft then 0 else 1, 0.5),
			Position = UDim2.new(if isLeft then 0 else 1, if isLeft then 16 else -16, 0.5, 0),
			Size = UDim2.fromOffset(110, 16),
			Parent = top,
		}, {
			Theme.list(
				Enum.FillDirection.Horizontal,
				6,
				if isLeft then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right,
				Enum.VerticalAlignment.Center
			),
		})
		local pips = {}
		for i = 1, MAX_WIN_PIPS do
			pips[i] = Theme.new("Frame", {
				Size = UDim2.fromOffset(10, 10),
				Rotation = 45,
				BorderSizePixel = 0,
				BackgroundColor3 = C.Locked,
				LayoutOrder = if isLeft then i else -i,
				Visible = false,
				Parent = holder,
			})
		end
		return pips
	end
	winPips.left = winRow(true)
	winPips.right = winRow(false)

	local function aliveRow(isLeft: boolean): ({ Frame }, TextLabel)
		local holder: Frame = Theme.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(if isLeft then 1 else 0, 0),
			Position = UDim2.new(0.5, if isLeft then -8 else 8, 0, 56),
			Size = UDim2.fromOffset(150, 18),
			Parent = sndFrame,
		}, {
			Theme.list(
				Enum.FillDirection.Horizontal,
				4,
				if isLeft then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left,
				Enum.VerticalAlignment.Center
			),
		})
		local count = Theme.label({
			Font = Theme.Fonts.Bold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(22, 18),
			LayoutOrder = if isLeft then 0 else 100,
			Parent = holder,
		})
		local pips = {}
		for i = 1, MAX_ALIVE_PIPS do
			pips[i] = Theme.new("Frame", {
				Size = UDim2.fromOffset(7, 16),
				BorderSizePixel = 0,
				BackgroundColor3 = C.Locked,
				LayoutOrder = 10 + i,
				Visible = false,
				Parent = holder,
			}, { Theme.corner(2) })
		end
		return pips, count
	end
	local leftPips, leftCount = aliveRow(true)
	local rightPips, rightCount = aliveRow(false)
	alivePips.left, alivePips.right = leftPips, rightPips
	aliveCount.left, aliveCount.right = leftCount, rightCount
	bombRow = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 78),
		Size = UDim2.fromOffset(400, 20),
		Visible = false,
		Parent = sndFrame,
	}, { Theme.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	bombIcon = Theme.new("Frame", {
		Size = UDim2.fromOffset(14, 9),
		BorderSizePixel = 0,
		BackgroundColor3 = C.Accent,
		LayoutOrder = 1,
		Parent = bombRow,
	}, { Theme.corner(2) })
	bombLabel = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		AutomaticSize = Enum.AutomaticSize.X,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = 2,
		Parent = bombRow,
	})
	Theme.new("UIStroke", { Color = C.Black, Thickness = 1, Transparency = 0.5, Parent = bombLabel })
end

local function buildBanner()
	bannerGroup = Theme.new("CanvasGroup", {
		Name = "Banner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromOffset(900, 96),
		GroupTransparency = 1,
		Visible = false,
		Parent = canvas,
	})
	bannerScale = Theme.new("UIScale", { Parent = bannerGroup })
	bannerTitle = Theme.label({
		Font = Theme.Fonts.Title,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 52),
		Parent = bannerGroup,
	})
	Theme.new("UIStroke", { Color = C.Black, Thickness = 1.5, Transparency = 0.4, Parent = bannerTitle })
	bannerBar = Theme.new("Frame", {
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(110, 3),
		Parent = bannerGroup,
	})
	bannerSub = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 64),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = bannerGroup,
	})
	Theme.new("UIStroke", { Color = C.Black, Thickness = 1, Transparency = 0.5, Parent = bannerSub })
end

local function buildPrompt()
	promptFrame = Theme.panel({
		Name = "InteractPrompt",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.64),
		Size = UDim2.fromOffset(340, 52),
		Visible = false,
		Parent = canvas,
	})
	promptText = Theme.label({
		RichText = true,
		Font = Theme.Fonts.Bold,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 26),
		Parent = promptFrame,
	})
	local trackFrame, fill = Theme.bar({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 36),
		Size = UDim2.new(1, -32, 0, 6),
		Visible = false,
		Parent = promptFrame,
	}, C.Accent)
	promptTrack, promptFill = trackFrame, fill
end

local function buildSpectate()
	specFrame = Theme.new("Frame", {
		Name = "Spectate",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(560, 120),
		Visible = false,
		Parent = canvas,
	})
	local eliminated = Theme.label({
		RichText = true,
		Text = string.format(
			'<font color="%s">ELIMINATED</font>  ·  WAITING FOR NEXT ROUND',
			Theme.hex(C.Danger)
		),
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = specFrame,
	})
	Theme.new("UIStroke", { Color = C.Black, Thickness = 1, Transparency = 0.5, Parent = eliminated })
	local panel = Theme.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 32),
		Size = UDim2.fromOffset(380, 76),
		Parent = specFrame,
	})
	specTitle = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = panel,
	})
	specName = Theme.label({
		Font = Theme.Fonts.Title,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(60, 20),
		Size = UDim2.new(1, -120, 0, 32),
		Parent = panel,
	})
	specHint = Theme.label({
		Text = "LMB / RMB  ·  LB / RB  TO SWITCH",
		Font = Theme.Fonts.Medium,
		TextSize = 11,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 14),
		Visible = false,
		Parent = panel,
	})
	specPrev = Theme.button({
		Text = "<",
		Font = Theme.Fonts.Title,
		TextSize = 24,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		Visible = false,
		Parent = panel,
	})
	specNext = Theme.button({
		Text = ">",
		Font = Theme.Fonts.Title,
		TextSize = 24,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		Visible = false,
		Parent = panel,
	})
	track(specPrev.Activated:Connect(function()
		cycleSpectate(-1)
	end))
	track(specNext.Activated:Connect(function()
		cycleSpectate(1)
	end))
end

function Objectives.init()
	gui, canvas = Theme.screen("Objectives", 8)
	gui.Enabled = false
	buildStrip()
	buildBanner()
	buildPrompt()
	buildSpectate()
	Theme.mount(gui)

	fxFolder = Theme.new("Folder", { Name = "COR_ObjectiveFX" })

	track(ClientState.MatchStateChanged:Connect(function(ms: Types.MatchStatePayload)
		if ms.phase ~= "Playing" then
			diedAt = nil
		end
		refreshActive()
	end))
	track(ClientState.ObjectiveChanged:Connect(function()
		refreshActive()
	end))
	track(ClientState.ObjectiveEvent:Connect(onObjectiveEvent))
	track(ClientState.DeployedChanged:Connect(function(deployed: boolean)
		if deployed then
			diedAt = nil
		else
			-- released on death (the server also cancels, this keeps the client state honest)
			unbindInteract()
			local ms = ClientState.matchState
			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local alive = humanoid ~= nil and humanoid.Health > 0 -- e.g. a round-start respawn
			if ms and ms.phase == "Playing" and diedAt == nil and not alive then
				diedAt = os.clock()
			end
		end
		refreshActive()
	end))
	track(GuiService.MenuOpened:Connect(function()
		sendInteract(false)
	end))
	track(UserInputService.WindowFocusReleased:Connect(function()
		sendInteract(false)
	end))
	track(UserInputService.LastInputTypeChanged:Connect(refreshPromptText))

	-- Kill Confirmed tags (folder is created by the server while KC runs)
	track(workspace.ChildAdded:Connect(function(child)
		if child.Name == "DogTags" then
			watchTags(child)
		end
	end))
	track(workspace.ChildRemoved:Connect(function(child)
		if child == tagFolder then
			unwatchTags()
		end
	end))
	local existing = workspace:FindFirstChild("DogTags")
	if existing then
		watchTags(existing)
	end

	refreshActive()
end

function Objectives.start()
	task.spawn(function()
		interactRemote = Net.event("Interact")
	end)
	while true do
		if active then
			local obj = ClientState.objective
			if obj then
				if kind == "Hardpoint" then
					updateHardpointTimer(obj)
				elseif kind == "SnD" then
					updateSnDClock(obj)
					refreshInteract()
				end
			end
			updateDistances()
		end
		refreshSpectate()
		task.wait(TICK)
	end
end

return Objectives
