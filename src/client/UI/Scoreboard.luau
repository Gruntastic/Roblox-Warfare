--!strict
-- Hold Tab (or tap the touch button) to show the scoreboard: teams side by side, sorted by score
-- (a single list sorted by kills in Free-for-All).
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)
local ObjectiveRules = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Pure.ObjectiveRules)

local Scoreboard = {}

local COLUMNS = { { key = "score", title = "SCORE" }, { key = "kills", title = "K" }, { key = "deaths", title = "D" }, { key = "assists", title = "A" } }
local NAME_WIDTH = 0.44
local STAT_WIDTH = (1 - NAME_WIDTH) / #COLUMNS
local ROW_HEIGHT = 34

local gui: ScreenGui
local root: Frame
local columnsHolder: Frame
local header: TextLabel
local touchButton: TextButton
local holding = false
local toggled = false
local isOpen = false
local localUserId = Players.LocalPlayer.UserId

local function row(line: Types.PlayerLine, index: number, parent: Instance)
	local isMe = line.userId == localUserId
	local frame: Frame = Theme.new("Frame", {
		Name = "Row",
		BackgroundColor3 = if isMe then Theme.Colors.Accent else Theme.Colors.PanelLight,
		BackgroundTransparency = if isMe then 0.78 else (if index % 2 == 0 then 0.55 else 0.75),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = index + 1,
		Parent = parent,
	}, { Theme.corner(3) })
	Theme.label({
		Text = string.format("%d   %s", index, line.name),
		Font = if isMe then Theme.Fonts.Bold else Theme.Fonts.Medium,
		TextSize = 18,
		TextColor3 = if isMe then Theme.Colors.Accent else Theme.Colors.Text,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(NAME_WIDTH, -12, 1, 0),
		Parent = frame,
	})
	for i, col in COLUMNS do
		local value = (line :: any)[col.key]
		Theme.label({
			Text = tostring(if typeof(value) == "number" then value else 0),
			Font = if i == 1 then Theme.Fonts.Bold else Theme.Fonts.Medium,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(NAME_WIDTH + STAT_WIDTH * (i - 1), 0),
			Size = UDim2.new(STAT_WIDTH, 0, 1, 0),
			Parent = frame,
		})
	end
end

local function column(title: string, color: Color3, score: number?, lines: { Types.PlayerLine }, layoutOrder: number): Frame
	local col = Theme.panel({
		Name = "Team",
		Size = UDim2.new(0.5, -8, 1, 0),
		LayoutOrder = layoutOrder,
		Parent = columnsHolder,
	})
	Theme.padding(12).Parent = col
	Theme.new("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 4),
		Position = UDim2.fromOffset(0, -12),
		Parent = col,
	})
	Theme.label({
		Text = string.upper(title),
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextColor3 = color,
		Size = UDim2.new(0.75, 0, 0, 34),
		Parent = col,
	})
	if score then
		Theme.label({
			Text = tostring(score),
			Font = Theme.Fonts.Title,
			TextSize = 30,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.25, 0, 0, 34),
			Parent = col,
		})
	end
	local list: ScrollingFrame = Theme.new("ScrollingFrame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 1, -44),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		Parent = col,
	}, { Theme.list(Enum.FillDirection.Vertical, 2) })
	-- column header
	local headerRow: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = 0,
		Parent = list,
	})
	Theme.label({
		Text = "PLAYER",
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = Theme.Colors.TextMuted,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(NAME_WIDTH, -12, 1, 0),
		Parent = headerRow,
	})
	for i, c in COLUMNS do
		Theme.label({
			Text = c.title,
			Font = Theme.Fonts.Bold,
			TextSize = 14,
			TextColor3 = Theme.Colors.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(NAME_WIDTH + STAT_WIDTH * (i - 1), 0),
			Size = UDim2.new(STAT_WIDTH, 0, 1, 0),
			Parent = headerRow,
		})
	end
	for i, line in lines do
		row(line, i, list)
	end
	return col
end

local function sortLines(lines: { Types.PlayerLine })
	table.sort(lines, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.name < b.name
	end)
end

local function rebuild()
	for _, child in columnsHolder:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local ms = ClientState.matchState
	if not ms then
		header.Text = "SCOREBOARD"
		return
	end
	header.Text = string.format("%s  //  %s", string.upper(ms.modeName), string.upper(ms.mapName))
	if Theme.isFFA(ms) or #ms.teams == 0 then
		-- Free-for-All: one list, ordered by the kill race (kills, then score).
		local all = ObjectiveRules.sortFFA(ms.players)
		local title = if ms.scoreLimit > 0 then string.format("Players  ·  first to %d", ms.scoreLimit) else "Players"
		local col = column(title, Theme.Colors.Accent, nil, all, 1)
		col.Size = UDim2.fromScale(1, 1)
		return
	end
	local myTeam = Theme.localTeam()
	for i, team in ms.teams do
		local lines = {}
		for _, line in ms.players do
			if line.team == team.id then
				table.insert(lines, line)
			end
		end
		sortLines(lines)
		local orderIndex = if team.id == myTeam then 0 else i
		column(team.displayName, Theme.teamColor(team.id), team.score, lines, orderIndex)
	end
end

local function setOpen(open: boolean)
	if open == isOpen then
		return
	end
	isOpen = open
	if open then
		rebuild()
		root.Visible = true
		root.Position = UDim2.new(0.5, 0, 0.5, 16)
		Theme.tween(root, Theme.Tween.Fast, { Position = UDim2.fromScale(0.5, 0.5) })
	else
		root.Visible = false
	end
end

local function refreshOpen()
	local ms = ClientState.matchState
	local allowed = ms ~= nil and (ms.phase == "Countdown" or ms.phase == "Playing")
	setOpen(allowed and (holding or toggled))
	touchButton.Visible = UserInputService.TouchEnabled and allowed
end

function Scoreboard.init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)

	local canvas
	gui, canvas = Theme.screen("Scoreboard", 30)
	root = Theme.new("Frame", {
		Name = "Board",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.66),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = canvas,
	}, {
		Theme.new("UISizeConstraint", { MaxSize = Vector2.new(1500, 900), MinSize = Vector2.new(900, 420) }),
	})
	header = Theme.label({
		Text = "SCOREBOARD",
		Font = Theme.Fonts.Title,
		TextSize = 26,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = root,
	})
	columnsHolder = Theme.new("Frame", {
		Name = "Columns",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		Parent = root,
	}, { Theme.list(Enum.FillDirection.Horizontal, 16) })

	touchButton = Theme.button({
		Name = "ScoreToggle",
		Text = "SCORES",
		TextSize = 16,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 300),
		Size = UDim2.fromOffset(110, 44),
		Visible = false,
		Parent = canvas,
	})
	touchButton.Activated:Connect(function()
		toggled = not toggled
		refreshOpen()
	end)

	Theme.mount(gui)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Tab and not processed then
			holding = true
			refreshOpen()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab then
			holding = false
			refreshOpen()
		end
	end)
	ClientState.MatchStateChanged:Connect(function()
		if isOpen then
			rebuild()
		end
		refreshOpen()
	end)
	refreshOpen()
end

return Scoreboard
