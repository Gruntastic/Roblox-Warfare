--!strict
-- End-of-match results: VICTORY / DEFEAT / DRAW banner (Free-for-All: "1ST PLACE" etc. by kills),
-- team scores (FFA: top three players), top players, XP breakdown
-- and an animated account XP bar from payload.startLevel to payload.account. Hidden when the
-- match returns to the Lobby phase.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Leveling = require(Shared.Pure.Leveling)
local ObjectiveRules = require(Shared.Pure.ObjectiveRules)
local Progression = require(Shared.Config.Progression)
local Phase5Rules = require(script.Parent.Phase5Rules)

local Results = {}

local TOP_PLAYERS = 8

local localUserId = Players.LocalPlayer.UserId
local gui: ScreenGui
local root: Frame
local contentScale: UIScale
local outcomeLabel: TextLabel
local winnerLabel: TextLabel
local stripe: Frame
local teamsRow: Frame
local playersList: Frame
local xpList: Frame
local xpTotal: TextLabel
local rankLabel: TextLabel
local rankXpLabel: TextLabel
local xpFill: Frame
local nextLabel: TextLabel
local visible = false
local animToken = 0

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function hide()
	if not visible then
		return
	end
	visible = false
	animToken += 1
	Theme.tween(root, Theme.Tween.Normal, { BackgroundTransparency = 1 })
	Theme.tween(contentScale, Theme.Tween.Normal, { Scale = 0.96 })
	task.delay(0.2, function()
		if not visible then
			gui.Enabled = false
		end
	end)
end

-- Derive where the bar started from the end state and the XP total (falls back to startLevel @ 0).
local function startState(p: Types.MatchResultsPayload): (number, number)
	local curve = Progression.AccountCurve
	local finalTotal = Leveling.totalToReach(curve, p.account.level) + p.account.xp
	local remaining = math.max(0, finalTotal - (p.xp and p.xp.total or 0))
	local level = 1
	while level < Progression.MaxAccountLevel and remaining >= Leveling.needed(curve, level) do
		remaining -= Leveling.needed(curve, level)
		level += 1
	end
	if level ~= p.startLevel then
		return p.startLevel, 0
	end
	return level, remaining
end

local function animateXP(p: Types.MatchResultsPayload)
	animToken += 1
	local token = animToken
	local curve = Progression.AccountCurve
	local finalLevel, finalXP, finalNeeded = p.account.level, p.account.xp, p.account.needed
	local level, xp = startState(p)
	local function setLevelText(l: number, x: number, n: number)
		rankLabel.Text = "RANK " .. tostring(l)
		rankXpLabel.Text = if n > 0 then string.format("%d / %d XP", math.floor(x), n) else "MAX RANK"
	end
	local needed = if level >= finalLevel then finalNeeded else Leveling.needed(curve, level)
	xpFill.Size = UDim2.fromScale(if needed > 0 then math.clamp(xp / needed, 0, 1) else 1, 1)
	setLevelText(level, xp, needed)
	task.spawn(function()
		task.wait(0.8)
		while token == animToken do
			local isFinal = level >= finalLevel
			local n = if isFinal then finalNeeded else Leveling.needed(curve, level)
			local target = if isFinal then (if n > 0 then math.clamp(finalXP / n, 0, 1) else 1) else 1
			local info = TweenInfo.new(0.35 + 0.9 * target, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			Theme.tween(xpFill, info, { Size = UDim2.fromScale(target, 1) })
			task.wait(info.Time)
			if token ~= animToken then
				return
			end
			if isFinal then
				setLevelText(finalLevel, finalXP, finalNeeded)
				return
			end
			level += 1
			xpFill.Size = UDim2.fromScale(0, 1)
			local nn = if level >= finalLevel then finalNeeded else Leveling.needed(curve, level)
			setLevelText(level, 0, nn)
			rankLabel.TextColor3 = Theme.Colors.White
			Theme.tween(rankLabel, Theme.Tween.Slow, { TextColor3 = Theme.Colors.Accent })
		end
	end)
end

local function show(p: Types.MatchResultsPayload)
	if typeof(p) ~= "table" then
		return
	end
	-- Outcome relative to the local player's team.
	local myTeam: string? = nil
	for _, line in p.players do
		if line.userId == localUserId then
			myTeam = line.team
		end
	end
	local winnerColor = Theme.Colors.Text
	local winnerName = ""
	for _, t in p.teams do
		if t.id == p.winnerTeam then
			winnerColor = if typeof(t.color) == "Color3" then t.color else Theme.teamColor(t.id)
			winnerName = t.displayName
		end
	end
	local ffa = Theme.isFFA() or #(p.teams or {}) == 0
	local players: { Types.PlayerLine } = p.players or {}
	if ffa then
		-- Free-for-All: placing by kills ("1ST PLACE", "2ND PLACE", ...) and the server's winner.
		local place, tied = ObjectiveRules.place(players, localUserId)
		local ffaWinner: string? = nil
		for _, line in players do
			if line.userId == p.winnerUserId then
				ffaWinner = line.name
			end
		end
		if place then
			outcomeLabel.Text = ObjectiveRules.ordinal(place) .. " PLACE"
			outcomeLabel.TextColor3 = if place == 1 then Theme.Colors.Accent elseif place <= 3 then Theme.Colors.Text else Theme.Colors.TextDim
		else
			outcomeLabel.Text = "MATCH OVER"
			outcomeLabel.TextColor3 = Theme.Colors.Text
		end
		if p.winnerUserId == localUserId then
			winnerLabel.Text = "YOU WIN THE MATCH"
			winnerLabel.TextColor3 = Theme.Colors.Accent
		elseif ffaWinner then
			winnerLabel.Text = string.upper(ffaWinner) .. " WINS"
			winnerLabel.TextColor3 = Theme.Colors.Text
		else
			winnerLabel.Text = if tied and place == 1 then "TIED FOR FIRST" else "NO OUTRIGHT WINNER"
			winnerLabel.TextColor3 = Theme.Colors.TextDim
		end
		stripe.BackgroundColor3 = if place == 1 then Theme.Colors.Accent else Theme.Colors.Stroke
	elseif not p.winnerTeam then
		outcomeLabel.Text = "DRAW"
		outcomeLabel.TextColor3 = Theme.Colors.Text
		winnerLabel.Text = "NO TEAM CLAIMED THE FIELD"
		winnerLabel.TextColor3 = Theme.Colors.TextDim
	elseif myTeam == p.winnerTeam then
		outcomeLabel.Text = "VICTORY"
		outcomeLabel.TextColor3 = Theme.Colors.Accent
		winnerLabel.Text = string.upper(winnerName) .. " WINS"
		winnerLabel.TextColor3 = winnerColor
	else
		outcomeLabel.Text = if myTeam then "DEFEAT" else "MATCH OVER"
		outcomeLabel.TextColor3 = if myTeam then Theme.Colors.Danger else Theme.Colors.Text
		winnerLabel.Text = string.upper(winnerName) .. " WINS"
		winnerLabel.TextColor3 = winnerColor
	end
	if not ffa then
		stripe.BackgroundColor3 = if p.winnerTeam then winnerColor else Theme.Colors.Stroke
	end

	-- Team scores (Free-for-All: the top three players by kills instead)
	clearChildren(teamsRow)
	if ffa then
		local podium = ObjectiveRules.sortFFA(players)
		for i = 1, math.min(3, #podium) do
			local line = podium[i]
			local isMe = line.userId == localUserId
			local color = if isMe then Theme.Colors.Accent else Theme.Colors.Text
			local box = Theme.panel({
				Size = UDim2.fromOffset(300, 74),
				LayoutOrder = i,
				Parent = teamsRow,
			})
			Theme.new("Frame", {
				BackgroundColor3 = if i == 1 then Theme.Colors.Accent else Theme.Colors.Stroke,
				BorderSizePixel = 0,
				Size = UDim2.new(0, 5, 1, 0),
				Parent = box,
			})
			Theme.label({
				Text = string.format("%s  %s", ObjectiveRules.ordinal((ObjectiveRules.place(players, line.userId)) or i), string.upper(line.name)),
				Font = Theme.Fonts.Bold,
				TextSize = 18,
				TextColor3 = color,
				Position = UDim2.fromOffset(20, 0),
				Size = UDim2.new(1, -110, 1, 0),
				Parent = box,
			})
			Theme.label({
				Text = tostring(line.kills),
				Font = Theme.Fonts.Title,
				TextSize = 40,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -18, 0, 0),
				Size = UDim2.new(0, 90, 1, 0),
				Parent = box,
			})
		end
	end
	for i, t in (if ffa then {} else p.teams) :: { Types.TeamScore } do
		local color = if typeof(t.color) == "Color3" then t.color else Theme.teamColor(t.id)
		local box = Theme.panel({
			Size = UDim2.fromOffset(300, 74),
			LayoutOrder = i,
			Parent = teamsRow,
		})
		Theme.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(0, 5, 1, 0), Parent = box })
		Theme.label({
			Text = string.upper(t.displayName),
			Font = Theme.Fonts.Bold,
			TextSize = 18,
			TextColor3 = color,
			Position = UDim2.fromOffset(20, 0),
			Size = UDim2.new(1, -110, 1, 0),
			Parent = box,
		})
		Theme.label({
			Text = tostring(t.score),
			Font = Theme.Fonts.Title,
			TextSize = 40,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, 0),
			Size = UDim2.new(0, 90, 1, 0),
			Parent = box,
		})
	end

	-- Top players
	clearChildren(playersList)
	local lines = table.clone(players)
	if ffa then
		lines = ObjectiveRules.sortFFA(players)
	else
		table.sort(lines, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.kills > b.kills
		end)
	end
	local function playerRow(cells: { string }, order: number, isHeader: boolean, isMe: boolean, teamId: string?, line: Types.PlayerLine?)
		local rowFrame: Frame = Theme.new("Frame", {
			BackgroundColor3 = if isMe then Theme.Colors.Accent else Theme.Colors.PanelLight,
			BackgroundTransparency = if isHeader then 1 elseif isMe then 0.78 else 0.6,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, if isHeader then 24 else 34),
			LayoutOrder = order,
			Parent = playersList,
		}, { Theme.corner(3) })
		if teamId then
			Theme.new("Frame", {
				BackgroundColor3 = Theme.teamColor(teamId),
				BorderSizePixel = 0,
				Size = UDim2.new(0, 4, 1, 0),
				Parent = rowFrame,
			})
		end
		local widths = { 0.48, 0.16, 0.12, 0.12, 0.12 }
		local x = 0
		-- Phase 5: prestige emblem badge before the name, equipped title in small caps after it
		local emblem = if line
			then Theme.emblemBadge(Phase5Rules.lineEmblem(line), 22, {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 12, 0.5, 0),
				Parent = rowFrame,
			})
			else nil
		local nameInset = if emblem then 42 else 14
		for i, text in cells do
			local rich = i == 1 and line ~= nil
			Theme.label({
				Text = if rich and line then Theme.nameWithTitle(text, line.title, 12) else text,
				RichText = rich,
				Font = if isHeader then Theme.Fonts.Bold elseif i <= 2 then Theme.Fonts.Bold else Theme.Fonts.Medium,
				TextSize = if isHeader then 14 else 18,
				TextColor3 = if isHeader then Theme.Colors.TextMuted elseif isMe and i == 1 then Theme.Colors.Accent else Theme.Colors.Text,
				TextXAlignment = if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
				Position = UDim2.new(x, if i == 1 then nameInset else 0, 0, 0),
				Size = UDim2.new(widths[i], if i == 1 then -nameInset else 0, 1, 0),
				Parent = rowFrame,
			})
			x += widths[i]
		end
	end
	playerRow({ "PLAYER", "SCORE", "K", "D", "A" }, 0, true, false, nil)
	for i = 1, math.min(TOP_PLAYERS, #lines) do
		local l = lines[i]
		playerRow({ string.format("%d  %s", i, l.name), tostring(l.score), tostring(l.kills), tostring(l.deaths), tostring(l.assists) }, i, false, l.userId == localUserId, if ffa then nil else l.team, l)
	end

	-- XP breakdown
	clearChildren(xpList)
	local breakdown: { { reason: string, amount: number } } = if p.xp and p.xp.breakdown then p.xp.breakdown else {}
	for i, item in breakdown do
		local rowFrame: Frame = Theme.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 30),
			LayoutOrder = i,
			Parent = xpList,
		})
		Theme.label({ Text = string.upper(item.reason), TextSize = 18, TextColor3 = Theme.Colors.TextDim, Size = UDim2.fromScale(0.7, 1), Parent = rowFrame })
		Theme.label({
			Text = "+" .. tostring(math.floor(item.amount)),
			Font = Theme.Fonts.Bold,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromScale(0.7, 0),
			Size = UDim2.fromScale(0.3, 1),
			Parent = rowFrame,
		})
	end
	if #breakdown == 0 then
		Theme.label({ Text = "No XP earned this match", TextSize = 18, TextColor3 = Theme.Colors.TextMuted, Size = UDim2.new(1, 0, 0, 30), Parent = xpList })
	end
	xpTotal.Text = "+" .. tostring(math.floor(if p.xp then p.xp.total else 0)) .. " XP"

	visible = true
	gui.Enabled = true
	root.BackgroundTransparency = 1
	contentScale.Scale = 1.06
	Theme.tween(contentScale, Theme.Tween.Slow, { Scale = 1 })
	Theme.tween(root, Theme.Tween.Slow, { BackgroundTransparency = 0.12 })
	outcomeLabel.TextTransparency = 1
	outcomeLabel.Position = UDim2.fromOffset(0, -30)
	Theme.tween(outcomeLabel, Theme.Tween.Pop, { TextTransparency = 0, Position = UDim2.fromOffset(0, 0) })
	if p.account then
		animateXP(p)
	end
end

local function sectionTitle(text: string, parent: Instance)
	Theme.label({
		Text = text,
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		TextColor3 = Theme.Colors.Accent,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = parent,
	})
end

function Results.init()
	local canvas
	gui, canvas = Theme.screen("Results", 50)
	gui.Enabled = false
	root = Theme.new("Frame", {
		Name = "Results",
		BackgroundColor3 = Theme.Colors.Backdrop,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = canvas,
	})
	local content: Frame = Theme.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.86, 0, 1, -120),
		Parent = root,
	}, { Theme.new("UISizeConstraint", { MaxSize = Vector2.new(1500, 960) }) })
	contentScale = Theme.new("UIScale", { Parent = content })

	-- Banner
	local banner: Frame = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 150), Parent = content })
	outcomeLabel = Theme.label({
		Text = "VICTORY",
		Font = Theme.Fonts.Title,
		TextSize = 96,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 104),
		Parent = banner,
	})
	stripe = Theme.new("Frame", {
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 106),
		Size = UDim2.fromOffset(220, 5),
		Parent = banner,
	})
	winnerLabel = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 116),
		Size = UDim2.new(1, 0, 0, 32),
		Parent = banner,
	})

	teamsRow = Theme.new("Frame", {
		Name = "Teams",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 166),
		Size = UDim2.new(1, 0, 0, 74),
		Parent = content,
	}, { Theme.list(Enum.FillDirection.Horizontal, 20, Enum.HorizontalAlignment.Center) })

	-- Lower area: players (left) and XP (right)
	local lower: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 262),
		Size = UDim2.new(1, 0, 1, -262 - 50),
		Parent = content,
	})
	local left = Theme.panel({ Size = UDim2.new(0.58, -10, 1, 0), Parent = lower })
	Theme.padding(16).Parent = left
	sectionTitle("TOP OPERATORS", left)
	playersList = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = left,
	}, { Theme.list(Enum.FillDirection.Vertical, 3) })

	local right = Theme.panel({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.42, -10, 1, 0), Parent = lower })
	Theme.padding(16).Parent = right
	sectionTitle("XP EARNED", right)
	xpList = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30 - 132),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = right,
	}, { Theme.list(Enum.FillDirection.Vertical, 2) })
	local summary: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 124),
		Parent = right,
	})
	Theme.new("Frame", { BackgroundColor3 = Theme.Colors.Stroke, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 1), Parent = summary })
	Theme.label({ Text = "TOTAL", Font = Theme.Fonts.Bold, TextSize = 20, Position = UDim2.fromOffset(0, 10), Size = UDim2.new(0.5, 0, 0, 34), Parent = summary })
	xpTotal = Theme.label({
		Font = Theme.Fonts.Title,
		TextSize = 30,
		TextColor3 = Theme.Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0.5, 0, 0, 34),
		Parent = summary,
	})
	rankLabel = Theme.label({ Font = Theme.Fonts.Title, TextSize = 22, TextColor3 = Theme.Colors.Accent, Position = UDim2.fromOffset(0, 58), Size = UDim2.new(0.5, 0, 0, 28), Parent = summary })
	rankXpLabel = Theme.label({
		TextSize = 16,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.new(0.5, 0, 0, 28),
		Parent = summary,
	})
	local _, fill = Theme.bar({ Position = UDim2.fromOffset(0, 94), Size = UDim2.new(1, 0, 0, 14), Parent = summary })
	xpFill = fill

	nextLabel = Theme.label({
		Font = Theme.Fonts.Medium,
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = content,
	})
	Theme.mount(gui)

	ClientState.MatchResults:Connect(show)
	ClientState.MatchStateChanged:Connect(function(ms)
		if ms.phase == "Lobby" or ms.phase == "Countdown" or ms.phase == "Playing" then
			hide()
		end
	end)
end

function Results.start()
	local lastText = ""
	while true do
		if visible then
			local ms = ClientState.matchState
			local text = ""
			if ms and ms.phase == "Results" and ms.phaseEndsAt > 0 then
				text = "RETURNING TO LOBBY IN " .. Theme.formatTime(ms.phaseEndsAt - Theme.serverNow())
			end
			if text ~= lastText then
				lastText = text
				nextLabel.Text = text
			end
		end
		task.wait(0.25)
	end
end

return Results
