--!strict
-- Killstreak HUD (Phase 5), visible while deployed in a match:
--   tray        bottom right above the ammo panel: each equipped streak with its kill cost and
--               progress this life; ready ones are highlighted with their key hint ([5]/[6]/[7],
--               "D-PAD UP" on the newest for gamepads) and are tappable on touch
--   banners     "MORTAR BARRAGE READY  [6]" when earned; an "Activated" notice for everyone,
--               friendly (team colour) or enemy (red)
--   blackout    "SIGNAL LOST" static overlay while an enemy Blackout hits our team (drawn below the
--               HUD so health and crosshair stay readable; HUD hides its other elements itself)
-- Input and world effects live in Controllers/StreakController.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Phase5Rules = require(script.Parent.Phase5Rules)
local ClientState = require(script.Parent.Parent.ClientState)
local StreakController = require(script.Parent.Parent.Controllers.StreakController)
local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local Streaks = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer
local ROW_HEIGHT = 44
local TRAY_WIDTH = 300
local TRAY_BOTTOM = 32 + 96 + 12 -- HUD ammo panel: 32 from the bottom, 96 tall
local STATIC_BARS = 14

local trayGui: ScreenGui
local trayCanvas: Frame
local tray: Frame
local trayHeader: TextLabel
local trayRows: Frame
local bannerGui: ScreenGui
local bannerHolder: Frame
local noticeHolder: Frame
local overlayGui: ScreenGui
local overlay: Frame
local overlayTimer: TextLabel
local staticBars: { Frame } = {}
local rowConns: { RBXScriptConnection } = {}
local usingGamepad = false
local noticeOrder = 0

local function streakName(id: string): string
	local def = Theme.Killstreaks.byId[id]
	return if def then string.upper(def.name) else string.upper(id)
end

local function inMatch(): boolean
	local ms = ClientState.matchState
	return ms ~= nil and (ms.phase == "Countdown" or ms.phase == "Playing")
end

local function keyHint(entry: Phase5Rules.TrayEntry): string
	if Theme.isTouchOnly() then
		return "TAP"
	elseif usingGamepad then
		return if entry.newest then "D-PAD UP" else ""
	end
	return "[" .. tostring(4 + entry.key) .. "]"
end

---------------------------------------------------------------------------------------------
-- Tray
---------------------------------------------------------------------------------------------

local function clearRows()
	for _, c in rowConns do
		c:Disconnect()
	end
	table.clear(rowConns)
	for _, child in trayRows:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function rebuildTray()
	clearRows()
	local state = ClientState.streak
	local entries = Phase5Rules.tray(state)
	local show = #entries > 0 and ClientState.deployed and inMatch() and not ClientState.isBlackedOut()
	tray.Visible = show
	if not show or not state then
		return
	end
	local count = state.count or 0
	local nextText = ""
	if state.nextId and state.nextAt then
		nextText = string.format("  ·  NEXT %s IN %d", streakName(state.nextId), math.max(state.nextAt - count, 0))
	end
	trayHeader.Text = string.format("STREAK %d%s", count, nextText)
	for i, e in entries do
		local isReady = e.ready > 0
		local row: TextButton = Theme.new("TextButton", {
			Name = e.id,
			Text = "",
			AutoButtonColor = false,
			Selectable = false, -- gamepads use D-pad up; keep GUI selection off the HUD
			BackgroundColor3 = if isReady then C.Accent else C.Panel,
			BackgroundTransparency = if isReady then 0.05 else 0.3,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			LayoutOrder = i,
			Parent = trayRows,
		}, { Theme.corner(5) })
		local textColor = if isReady then C.OnAccent else C.Text
		Theme.label({
			Text = tostring(e.cost),
			Font = Theme.Fonts.Title,
			TextSize = 20,
			TextColor3 = if isReady then C.OnAccent else C.Accent,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(0, 40, 1, 0),
			Parent = row,
		})
		Theme.label({
			Text = streakName(e.id) .. (if e.ready > 1 then string.format("  x%d", e.ready) else ""),
			Font = Theme.Fonts.Bold,
			TextSize = 15,
			TextColor3 = textColor,
			Position = UDim2.fromOffset(44, 4),
			Size = UDim2.new(1, -140, 0, 20),
			Parent = row,
		})
		Theme.label({
			Text = if isReady then "READY" else string.format("%d / %d KILLS", math.min(count, e.cost), e.cost),
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			TextColor3 = if isReady then C.OnAccent else C.TextMuted,
			Position = UDim2.fromOffset(44, 24),
			Size = UDim2.new(1, -140, 0, 14),
			Parent = row,
		})
		if not isReady then
			local _, fill = Theme.bar({
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 44, 1, -4),
				Size = UDim2.new(1, -56, 0, 3),
				Parent = row,
			})
			fill.Size = UDim2.fromScale(e.progress, 1)
		else
			Theme.label({
				Text = keyHint(e),
				Font = Theme.Fonts.Title,
				TextSize = 15,
				TextColor3 = C.OnAccent,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.new(0, 96, 1, 0),
				Parent = row,
			})
			local id = e.id
			table.insert(rowConns, row.Activated:Connect(function()
				if StreakController.activate(id) then
					Theme.tween(row, Theme.Tween.Fast, { BackgroundTransparency = 0.5 })
				end
			end))
		end
	end
	tray.Size = UDim2.fromOffset(TRAY_WIDTH, 30 + #entries * (ROW_HEIGHT + 4))
end

---------------------------------------------------------------------------------------------
-- Banners
---------------------------------------------------------------------------------------------

local function earnedBanner(id: string)
	local state = ClientState.streak
	local hint = ""
	if state then
		for _, e in Phase5Rules.tray(state) do
			if e.id == id then
				local h = keyHint(e)
				if usingGamepad and h == "" then
					h = "D-PAD UP"
				end
				hint = if h ~= "" then "  [" .. (string.gsub(h, "[%[%]]", "")) .. "]" else ""
			end
		end
	end
	for _, child in bannerHolder:GetChildren() do
		child:Destroy()
	end
	local group: CanvasGroup = Theme.new("CanvasGroup", {
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -10),
		Size = UDim2.fromOffset(560, 64),
		GroupTransparency = 1,
		Parent = bannerHolder,
	}, { Theme.corner(6) })
	Theme.label({
		Text = "KILLSTREAK EARNED",
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = C.OnAccent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = group,
	})
	Theme.label({
		Text = streakName(id) .. " READY" .. hint,
		Font = Theme.Fonts.Title,
		TextSize = 26,
		TextColor3 = C.OnAccent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = group,
	})
	Theme.tween(group, Theme.Tween.Pop, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0) })
	task.delay(3, function()
		if group.Parent then
			Theme.tween(group, Theme.Tween.Normal, { GroupTransparency = 1 })
			task.delay(0.3, function()
				group:Destroy()
			end)
		end
	end)
end

local function activatedNotice(data: { [string]: any })
	local id = if type(data.streakId) == "string" then data.streakId else nil
	if not id then
		return
	end
	local owner = if type(data.ownerUserId) == "number" then data.ownerUserId else nil
	local team = if type(data.team) == "string" and data.team ~= "" then data.team else nil
	local mine = owner == localPlayer.UserId
	local friendly = Phase5Rules.isFriendly(team, owner, Theme.localTeam(), localPlayer.UserId)
	local color = if mine then C.Accent elseif friendly then (if team then Theme.teamColor(team) else C.Positive) else C.Danger
	local who = if type(data.ownerName) == "string" then string.upper(data.ownerName) else "SOMEONE"
	local text = if mine
		then streakName(id) .. " ACTIVATED"
		elseif friendly then "FRIENDLY " .. streakName(id) .. "  ·  " .. who
		else "ENEMY " .. streakName(id) .. "  ·  " .. who
	noticeOrder += 1
	local row: Frame = Theme.new("Frame", {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(460, 34),
		LayoutOrder = noticeOrder,
		Parent = noticeHolder,
	}, { Theme.corner(4) })
	Theme.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 4, 1, 0), Parent = row })
	local label = Theme.label({
		Text = text,
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = row,
	})
	local rows = {}
	for _, child in noticeHolder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #rows - 3 do
		rows[i]:Destroy()
	end
	task.delay(4, function()
		if row.Parent then
			Theme.tween(row, Theme.Tween.Normal, { BackgroundTransparency = 1 })
			Theme.tween(label, Theme.Tween.Normal, { TextTransparency = 1 })
			task.delay(0.3, function()
				row:Destroy()
			end)
		end
	end)
end

---------------------------------------------------------------------------------------------
-- SIGNAL LOST overlay
---------------------------------------------------------------------------------------------

local function refreshOverlay()
	local on = ClientState.isBlackedOut() and ClientState.deployed and inMatch()
	overlayGui.Enabled = on
end

local function refreshVisibility()
	local show = ClientState.deployed and inMatch()
	trayGui.Enabled = show
	bannerGui.Enabled = inMatch()
	rebuildTray()
	refreshOverlay()
end

function Streaks.init()
	-- tray (same layer as the HUD)
	local canvas
	trayGui, canvas = Theme.screen("StreakTray", 6)
	trayCanvas = canvas
	trayGui.Enabled = false
	tray = Theme.new("Frame", {
		Name = "Tray",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -32, 1, -TRAY_BOTTOM),
		Size = UDim2.fromOffset(TRAY_WIDTH, 30),
		Visible = false,
		Parent = trayCanvas,
	})
	trayHeader = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.6,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = tray,
	})
	trayRows = Theme.new("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 1, -28),
		Parent = tray,
	}, { Theme.list(Enum.FillDirection.Vertical, 4) })
	Theme.mount(trayGui)

	-- banners + activation notices
	local bcanvas
	bannerGui, bcanvas = Theme.screen("StreakBanners", 39)
	bannerGui.Enabled = false
	bannerHolder = Theme.new("Frame", {
		Name = "Earned",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 0),
		Size = UDim2.fromOffset(560, 70),
		Parent = bcanvas,
	})
	noticeHolder = Theme.new("Frame", {
		Name = "Notices",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 80),
		Size = UDim2.fromOffset(460, 3 * 38),
		Parent = bcanvas,
	}, { Theme.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Center) })
	Theme.mount(bannerGui)

	-- SIGNAL LOST (below the HUD: DisplayOrder 4 < HUD 5)
	local ocanvas
	overlayGui, ocanvas = Theme.screen("SignalLost", 4)
	overlayGui.Enabled = false
	overlay = Theme.new("Frame", {
		Name = "SignalLost",
		BackgroundColor3 = Color3.fromRGB(10, 12, 14),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = ocanvas,
	})
	for i = 1, STATIC_BARS do
		local bar: Frame = Theme.new("Frame", {
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, (i - 1) / STATIC_BARS),
			Size = UDim2.new(1, 0, 0, 3),
			Parent = overlay,
		})
		table.insert(staticBars, bar)
	end
	Theme.label({
		Text = "SIGNAL LOST",
		Font = Theme.Fonts.Title,
		TextSize = 54,
		TextColor3 = C.Danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		Size = UDim2.fromOffset(700, 60),
		Parent = overlay,
	})
	overlayTimer = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 182),
		Size = UDim2.fromOffset(700, 24),
		Parent = overlay,
	})
	Theme.mount(overlayGui)

	usingGamepad = UserInputService:GetLastInputType().Name:find("Gamepad") ~= nil
	UserInputService.LastInputTypeChanged:Connect(function(t: Enum.UserInputType)
		local pad = t.Name:find("Gamepad") ~= nil
		local isMouseOrKey = t == Enum.UserInputType.Keyboard or t.Name:find("Mouse") ~= nil or t == Enum.UserInputType.Touch
		if pad ~= usingGamepad and (pad or isMouseOrKey) then
			usingGamepad = pad
			if trayGui.Enabled then
				rebuildTray()
			end
		end
	end)

	ClientState.StreakStateChanged:Connect(function(_: Types.StreakStatePayload)
		if trayGui.Enabled then
			rebuildTray()
		end
	end)
	ClientState.StreakEvent:Connect(function(kind: string, data: { [string]: any })
		if kind == "Earned" and type(data.streakId) == "string" and ClientState.deployed then
			earnedBanner(data.streakId)
		elseif kind == "Activated" then
			activatedNotice(data)
		end
	end)
	ClientState.HudEffectsChanged:Connect(function()
		rebuildTray()
		refreshOverlay()
	end)
	ClientState.DeployedChanged:Connect(refreshVisibility)
	ClientState.MatchStateChanged:Connect(function(ms)
		if ms.phase ~= "Playing" and ms.phase ~= "Countdown" then
			ClientState.streak = nil
		end
		refreshVisibility()
	end)
	refreshVisibility()
end

function Streaks.start()
	local lastText = ""
	local wasBlackedOut = false
	while true do
		local blacked = ClientState.isBlackedOut()
		if blacked ~= wasBlackedOut then
			-- endsAt passed without an EffectEnded (or before it arrived)
			wasBlackedOut = blacked
			rebuildTray()
			refreshOverlay()
		end
		if overlayGui.Enabled then
			local left = ClientState.blackoutUntil - Theme.serverNow()
			local text = "ENEMY BLACKOUT  ·  " .. Theme.formatTime(left)
			if text ~= lastText then
				lastText = text
				overlayTimer.Text = text
			end
			for _, bar in staticBars do
				bar.Position = UDim2.fromScale(0, math.random())
				bar.BackgroundTransparency = 0.75 + math.random() * 0.22
				bar.Size = UDim2.new(1, 0, 0, math.random(1, 6))
			end
			task.wait(0.06)
		else
			task.wait(0.25)
		end
	end
end

return Streaks
