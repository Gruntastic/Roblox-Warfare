--!strict
-- Mode select ("Join"). Shown over the lobby whenever the player is not in a match and has not
-- queued: they pick a mode (or ANY) and the server puts them into the next match of that mode, or
-- straight into the running match when it is that mode. The server confirms the pick with the
-- player attribute QueuedMode; the lobby then shows the queue status and a CHANGE MODE button.
-- LOADOUT closes the menu to edit classes first; PlayMenu.open() brings it back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local PlayMenu = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer

local BLURBS: { [string]: string } = {
	Any = "Jump into whatever plays next. Fastest way in.",
	TDM = "Two teams. First to the kill limit wins.",
	DOM = "Capture and hold flags A, B and C.",
	KC = "Kills count only when you grab the tag.",
	HP = "Hold the moving hardpoint to score.",
	FFA = "Every operator for themselves.",
	SND = "One life per round. Plant or defuse the bomb.",
}

local gui: ScreenGui
local cards: { [string]: { count: TextLabel, live: TextLabel, button: TextButton } } = {}
local statusLabel: TextLabel
local dismissed = false
local pending: string? = nil

local function shouldShow(): boolean
	return not dismissed and not ClientState.deployed and localPlayer:GetAttribute("QueuedMode") == nil
end

local function refresh()
	gui.Enabled = shouldShow()
	if not gui.Enabled then
		return
	end
	local ms: Types.MatchStatePayload? = ClientState.matchState
	local running = ms ~= nil and (ms.phase == "Playing" or ms.phase == "Countdown")
	for id, card in cards do
		local n = if ms and ms.queue then ms.queue[id] or 0 else 0
		card.count.Text = if n == 1 then "1 PLAYER QUEUED" else n .. " PLAYERS QUEUED"
		card.live.Visible = running and ms ~= nil and (id == "Any" or ms.modeId == id)
		card.button.Text = if pending == id then "JOINING..." else ""
	end
	if ms and running then
		statusLabel.Text = "NOW PLAYING: " .. string.upper(ms.modeName) .. " ON " .. string.upper(ms.mapName)
			.. "   ·   PICK IT (OR ANY) TO JOIN NOW"
	elseif ms and ms.phase == "Results" then
		statusLabel.Text = "MATCH ENDING. PICK A MODE FOR THE NEXT ONE"
	else
		statusLabel.Text = "PICK A MODE. THE NEXT MATCH PLAYS THE MOST PICKED MODE"
	end
end

local function pick(id: string)
	pending = id
	Net.event("JoinQueue"):FireServer(id)
	refresh()
	task.delay(3, function()
		if pending == id then
			pending = nil
			refresh()
		end
	end)
end

local function card(id: string, name: string, order: number, parent: Instance)
	local button = Theme.button({
		Name = "Mode_" .. id,
		LayoutOrder = order,
		Text = "",
		Size = UDim2.fromOffset(300, 132),
		Parent = parent,
	}, if id == "Any" then "Primary" else nil)
	local textColor = if id == "Any" then C.OnAccent else C.Text
	local dimColor = if id == "Any" then C.OnAccent else C.TextDim
	Theme.label({
		Text = string.upper(name),
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextColor3 = textColor,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 30),
		Parent = button,
	})
	Theme.label({
		Text = BLURBS[id] or "",
		Font = Theme.Fonts.Medium,
		TextSize = 15,
		TextColor3 = dimColor,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 46),
		Size = UDim2.new(1, -32, 0, 40),
		Parent = button,
	})
	local count = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = if id == "Any" then C.OnAccent else C.Accent,
		Position = UDim2.new(0, 16, 1, -32),
		Size = UDim2.new(1, -110, 0, 20),
		Parent = button,
	})
	local live = Theme.label({
		Text = "● LIVE",
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = if id == "Any" then C.OnAccent else C.Positive,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 1, -32),
		Size = UDim2.fromOffset(90, 20),
		Visible = false,
		Parent = button,
	})
	button.Activated:Connect(function()
		pick(id)
	end)
	cards[id] = { count = count, live = live, button = button }
end

function PlayMenu.open()
	dismissed = false
	refresh()
end

function PlayMenu.isOpen(): boolean
	return (gui :: ScreenGui?) ~= nil and gui.Enabled
end

function PlayMenu.init()
	local canvas
	gui, canvas = Theme.screen("PlayMenu", 12)
	local root: Frame = Theme.new("Frame", {
		Name = "PlayMenu",
		BackgroundColor3 = C.Backdrop,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = canvas,
	})
	Theme.label({
		Text = "SELECT MODE",
		Font = Theme.Fonts.Title,
		TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(900, 52),
		Parent = root,
	})
	statusLabel = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.fromOffset(1000, 24),
		Parent = root,
	})
	local grid: Frame = Theme.new("Frame", {
		Name = "Modes",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 180),
		Size = UDim2.fromOffset(940, 440),
		Parent = root,
	})
	Theme.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(300, 132),
		CellPadding = UDim2.fromOffset(20, 18),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	card("Any", "Any mode", 0, grid)
	for i, id in Theme.Match.ModeRotation do
		local m = Theme.Modes[id]
		card(id, if m then m.displayName else id, i, grid)
	end
	local loadout = Theme.button({
		Name = "Loadout",
		Text = "EDIT LOADOUT FIRST",
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 640),
		Size = UDim2.fromOffset(320, 52),
		Parent = root,
	})
	loadout.Activated:Connect(function()
		dismissed = true
		refresh()
	end)
	Theme.mount(gui)

	localPlayer:GetAttributeChangedSignal("QueuedMode"):Connect(function()
		pending = nil
		if localPlayer:GetAttribute("QueuedMode") == nil then
			dismissed = false -- left the queue: back to mode select
		end
		refresh()
	end)
	ClientState.MatchStateChanged:Connect(refresh)
	ClientState.DeployedChanged:Connect(refresh)
	refresh()
end

return PlayMenu
