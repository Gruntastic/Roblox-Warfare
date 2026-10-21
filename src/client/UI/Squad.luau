--!strict
-- Squad layer of the lobby, drawn over the 3D staging room (Controllers/StagingScene):
--   * a name plate under every operator in the room (name, rank, LEADER tag)
--   * an INVITE button on each empty slot, opening the invite panel: players in this server with
--     INVITE, plus INVITE FRIENDS (Roblox game invite prompt) for friends who are not here yet
--   * incoming squad invites with ACCEPT / DECLINE, and LEAVE SQUAD while in one
-- Helper module for UI/Lobby: Squad.build(parent), Squad.update() each frame while shown.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local StagingScene = require(script.Parent.Parent.Controllers.StagingScene)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Assets = require(Shared.Config.Assets)

local Squad = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer
local SLOT_COUNT = #StagingScene.SLOTS

type Plate = { frame: Frame, name: TextLabel, sub: TextLabel, invite: TextButton }

local layer: Frame
local plates: { Plate } = {}
local invitePanel: Frame
local inviteList: ScrollingFrame
local incoming: Frame
local leaveButton: TextButton
local lastInviteKey = ""

local function fire(remote: string, ...: any)
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(function()
			Net.event(remote):FireServer(table.unpack(args, 1, args.n))
		end)
		if not ok then
			warn("[Squad] " .. remote .. " failed: " .. tostring(err))
		end
	end)
end

local function icon(key: string, size: number, props: { [string]: any }): ImageLabel?
	local image = Assets.image(key)
	if not image then
		return nil
	end
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Image = image,
		ScaleType = Enum.ScaleType.Fit,
		Size = UDim2.fromOffset(size, size),
	}
	for k, v in props do
		base[k] = v
	end
	return Theme.new("ImageLabel", base)
end

local function lineFor(userId: number): any
	local ms = ClientState.matchState
	if ms then
		for _, line in ms.players do
			if line.userId == userId then
				return line
			end
		end
	end
	return nil
end

local function inSquad(userId: number): boolean
	local party = ClientState.party
	return party ~= nil and table.find(party.members, userId) ~= nil
end

local function squadFull(): boolean
	local party = ClientState.party
	return party ~= nil and #party.members >= party.maxSize
end

---------------------------------------------------------------------------------------------
-- Invite panel
---------------------------------------------------------------------------------------------

local function rebuildInviteList()
	for _, child in inviteList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= localPlayer and not inSquad(p.UserId) then
			table.insert(others, p)
		end
	end
	table.sort(others, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	if #others == 0 then
		Theme.label({
			Text = "NO OTHER OPERATORS IN THIS SERVER YET",
			Font = Theme.Fonts.Medium,
			TextSize = 14,
			TextColor3 = C.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = inviteList,
		})
	end
	for i, p in others do
		local row = Theme.new("Frame", {
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 48),
			LayoutOrder = i,
			Parent = inviteList,
		}, { Theme.corner(4) })
		local line = lineFor(p.UserId)
		Theme.label({
			Text = string.upper(p.DisplayName),
			Font = Theme.Fonts.Bold,
			TextSize = 16,
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -150, 0, 22),
			Parent = row,
		})
		Theme.label({
			Text = if line and line.level then "RANK " .. tostring(line.level) else "@" .. p.Name,
			Font = Theme.Fonts.Medium,
			TextSize = 12,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(12, 26),
			Size = UDim2.new(1, -150, 0, 16),
			Parent = row,
		})
		local button = Theme.button({
			Text = "INVITE",
			TextSize = 14,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(120, 36),
			Parent = row,
		}, "Primary")
		button.Activated:Connect(function()
			fire("PartyInvite", p.UserId)
			button.Text = "SENT"
			button.Active = false
			Theme.setButtonColor(button, C.Locked)
		end)
	end
end

local function promptFriends()
	task.spawn(function()
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(localPlayer)
		end)
		if ok and can then
			pcall(function()
				SocialService:PromptGameInvite(localPlayer)
			end)
		else
			ClientState.Notify:Fire("Game invites are not available on this account", "Warning")
		end
	end)
end

function Squad.openInvites()
	if squadFull() then
		ClientState.Notify:Fire("Your squad is full", "Warning")
		return
	end
	rebuildInviteList()
	invitePanel.Visible = true
	invitePanel.Position = UDim2.new(0.5, 0, 0.5, 24)
	Theme.tween(invitePanel, Theme.Tween.Pop, { Position = UDim2.fromScale(0.5, 0.5) })
end

function Squad.closeInvites()
	invitePanel.Visible = false
end

local function buildInvitePanel(parent: Instance)
	invitePanel = Theme.panel({
		Name = "InvitePanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(520, 560),
		BackgroundTransparency = 0.04,
		ZIndex = 20,
		Visible = false,
		Parent = parent,
	})
	Theme.padding(18).Parent = invitePanel
	Theme.label({
		Text = "INVITE TO SQUAD",
		Font = Theme.Fonts.Title,
		TextSize = 26,
		Size = UDim2.new(1, -60, 0, 32),
		Parent = invitePanel,
	})
	local close = Theme.button({
		Text = "X",
		TextSize = 18,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(40, 32),
		Parent = invitePanel,
	})
	close.Activated:Connect(Squad.closeInvites)
	Theme.label({
		Text = "OPERATORS IN THIS SERVER",
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = invitePanel,
	})
	inviteList = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 1, -68 - 70),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		Parent = invitePanel,
	}, { Theme.list(Enum.FillDirection.Vertical, 6) })
	local friends = Theme.button({
		Text = "INVITE FRIENDS TO BLOX OPS",
		TextSize = 16,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 54),
		Parent = invitePanel,
	})
	Theme.stroke(C.Accent, 1, 0.3).Parent = friends
	friends.Activated:Connect(promptFriends)
end

---------------------------------------------------------------------------------------------
-- Incoming invites
---------------------------------------------------------------------------------------------

local function rebuildIncoming()
	local party = ClientState.party
	local list: { { userId: number, name: string } } = if party then party.invites else {}
	local key = ""
	for _, inv in list do
		key ..= tostring(inv.userId) .. ","
	end
	leaveButton.Visible = party ~= nil and #party.members > 1
	if key == lastInviteKey then
		return
	end
	lastInviteKey = key
	for _, child in incoming:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for i, inv in list do
		local card = Theme.panel({
			Size = UDim2.new(1, 0, 0, 64),
			BackgroundTransparency = 0.05,
			LayoutOrder = i,
			Parent = incoming,
		})
		Theme.stroke(C.Accent, 1, 0.2).Parent = card
		Theme.label({
			Text = "SQUAD INVITE",
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			TextColor3 = C.Accent,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -240, 0, 16),
			Parent = card,
		})
		Theme.label({
			Text = string.upper(inv.name),
			Font = Theme.Fonts.Bold,
			TextSize = 18,
			Position = UDim2.fromOffset(14, 26),
			Size = UDim2.new(1, -240, 0, 26),
			Parent = card,
		})
		local accept = Theme.button({
			Text = "ACCEPT",
			TextSize = 14,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -116, 0.5, 0),
			Size = UDim2.fromOffset(100, 40),
			Parent = card,
		}, "Primary")
		local decline = Theme.button({
			Text = "DECLINE",
			TextSize = 14,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(100, 40),
			Parent = card,
		})
		accept.Activated:Connect(function()
			fire("PartyRespond", inv.userId, true)
			card.Visible = false
		end)
		decline.Activated:Connect(function()
			fire("PartyRespond", inv.userId, false)
			card.Visible = false
		end)
	end
end

---------------------------------------------------------------------------------------------
-- Plates
---------------------------------------------------------------------------------------------

local function buildPlate(index: number): Plate
	local frame: Frame = Theme.new("Frame", {
		Name = "Slot" .. index,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(200, 64),
		Visible = false,
		Parent = layer,
	})
	local nameLabel = Theme.label({
		Font = Theme.Fonts.Title,
		TextSize = if index == 1 then 22 else 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = frame,
	})
	local sub = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.6,
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = frame,
	})
	local invite = Theme.button({
		Name = "Invite",
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(150, 46),
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = frame,
	})
	Theme.stroke(C.Accent, 1, 0.3).Parent = invite
	local glyph = icon("Icon.Invite", 28, { Position = UDim2.fromOffset(10, 9), Parent = invite })
	Theme.label({
		Text = if glyph then "INVITE" else "+  INVITE",
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		TextXAlignment = if glyph then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(if glyph then 46 else 0, 0),
		Size = UDim2.new(1, if glyph then -50 else 0, 1, 0),
		Parent = invite,
	})
	invite.Activated:Connect(Squad.openInvites)
	return { frame = frame, name = nameLabel, sub = sub, invite = invite }
end

function Squad.build(parent: Instance)
	layer = Theme.new("Frame", {
		Name = "Squad",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	for i = 1, SLOT_COUNT do
		plates[i] = buildPlate(i)
	end
	incoming = Theme.new("Frame", {
		Name = "Incoming",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 130),
		Size = UDim2.fromOffset(520, 220),
		ZIndex = 15,
		Parent = parent,
	}, { Theme.list(Enum.FillDirection.Vertical, 6) })
	leaveButton = Theme.button({
		Name = "LeaveSquad",
		Text = "LEAVE SQUAD",
		TextSize = 14,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -36),
		Size = UDim2.fromOffset(180, 40),
		Visible = false,
		Parent = parent,
	})
	leaveButton.Activated:Connect(function()
		fire("PartyLeave")
	end)
	buildInvitePanel(parent)
	ClientState.PartyChanged:Connect(function()
		rebuildIncoming()
		if invitePanel.Visible then
			rebuildInviteList()
		end
	end)
	Players.PlayerAdded:Connect(function()
		if invitePanel.Visible then
			rebuildInviteList()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if invitePanel.Visible then
			task.defer(rebuildInviteList)
		end
	end)
end

-- Moves the plates under the operators. Call every frame while the lobby is shown.
function Squad.update()
	if not StagingScene.isActive() then
		layer.Visible = false
		return
	end
	layer.Visible = true
	local scale = Theme.getScale()
	local party = ClientState.party
	local full = squadFull()
	for _, slot in StagingScene.slotScreen() do
		local plate = plates[slot.index]
		if plate then
			local pos = slot.position / scale
			plate.frame.Position = UDim2.fromOffset(pos.X, pos.Y + 8)
			plate.frame.Visible = slot.onScreen
			local userId = slot.userId
			if userId then
				local p = Players:GetPlayerByUserId(userId)
				local line = lineFor(userId)
				plate.name.Text = string.upper(if p then p.DisplayName else "OPERATOR")
				local rank = if line and line.level then "RANK " .. tostring(line.level) else ""
				local leader = party ~= nil and party.leader == userId and #party.members > 1
				plate.sub.Text = if leader then (if rank ~= "" then rank .. "  ·  " else "") .. "SQUAD LEADER" else rank
				plate.name.Visible = true
				plate.sub.Visible = true
				plate.invite.Visible = false
			else
				plate.name.Visible = false
				plate.sub.Visible = false
				plate.invite.Visible = not full
			end
		end
	end
end

function Squad.init() end

return Squad
