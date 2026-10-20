--!strict
-- Lobby / pre-deploy screen: title, match info + phase timer, operators by team, map vote,
-- loadout slots + editor (with unlock gating and weapon levels), account rank + XP bar,
-- DataStore-offline warning and the DEPLOY button for late joiners / respawn fallback.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)

local Lobby = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer

type WeaponDef = typeof(Theme.Weapons.VK7)

-- state
local gui: ScreenGui
local root: Frame
local mainFrame: Frame
local lastDeployed = false
local shown = false
local diedAt: number? = nil
local editIndex: number? = nil
local draft: { primary: string, secondary: string }? = nil
local myVote: string? = nil

-- widgets
local rankNumber: TextLabel
local rankXpText: TextLabel
local rankFill: Frame
local prestigeLabel: TextLabel
local warningBanner: Frame
local modeLabel: TextLabel
local mapLabel: TextLabel
local phaseLabel: TextLabel
local timerLabel: TextLabel
local teamsHolder: Frame
local voteList: Frame
local voteButtons: { [string]: TextButton } = {}
local slotList: Frame
local editorTitle: TextLabel
local editorBody: ScrollingFrame
local primaryGrid: Frame
local secondaryGrid: Frame
local saveButton: TextButton
local saveStatus: TextLabel
local deployButton: TextButton
local bottomStatus: TextLabel

---------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------

local function clearChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function fire(remote: string, ...: any)
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(function()
			Net.event(remote):FireServer(table.unpack(args, 1, args.n))
		end)
		if not ok then
			warn("[Lobby] " .. remote .. " failed: " .. tostring(err))
		end
	end)
end

local function weaponsForSlot(slot: string): { WeaponDef }
	local list: { WeaponDef } = {}
	for _, def in Theme.Weapons do
		if def.slot == slot then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		if a.unlockLevel ~= b.unlockLevel then
			return a.unlockLevel < b.unlockLevel
		end
		return a.displayName < b.displayName
	end)
	return list
end

local function isUnlocked(profile: Types.ProfileSummary, def: WeaponDef): boolean
	if profile.account.level >= def.unlockLevel then
		return true
	end
	return table.find(profile.unlockedWeapons, def.id) ~= nil
end

local function sectionTitle(text: string, parent: Instance, order: number?): TextLabel
	return Theme.label({
		Text = text,
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		TextColor3 = C.Accent,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = order or 0,
		Parent = parent,
	})
end

---------------------------------------------------------------------------------------------
-- Rank / warning
---------------------------------------------------------------------------------------------

local function refreshRank()
	local profile = ClientState.profile
	if not profile then
		rankNumber.Text = "-"
		rankXpText.Text = "LOADING PROFILE"
		rankFill.Size = UDim2.fromScale(0, 1)
		prestigeLabel.Text = ""
		warningBanner.Visible = false
		return
	end
	local acc = profile.account
	rankNumber.Text = tostring(acc.level)
	if acc.needed > 0 then
		rankXpText.Text = string.format("%d / %d XP", acc.xp, acc.needed)
		Theme.tween(rankFill, Theme.Tween.Slow, { Size = UDim2.fromScale(math.clamp(acc.xp / acc.needed, 0, 1), 1) })
	else
		rankXpText.Text = "MAX RANK"
		rankFill.Size = UDim2.fromScale(1, 1)
	end
	prestigeLabel.Text = if acc.prestige and acc.prestige > 0 then "PRESTIGE " .. tostring(acc.prestige) else "OPERATOR RANK"
	warningBanner.Visible = profile.temporary == true
end

---------------------------------------------------------------------------------------------
-- Loadouts
---------------------------------------------------------------------------------------------

local rebuildEditor: () -> ()

local function currentLoadout(): Types.Loadout?
	local profile = ClientState.profile
	if not profile or not editIndex then
		return nil
	end
	return profile.loadouts[editIndex]
end

local function isDirty(): boolean
	local lo = currentLoadout()
	return draft ~= nil and lo ~= nil and (draft.primary ~= lo.primary or draft.secondary ~= lo.secondary)
end

local function refreshSave()
	local dirty = isDirty()
	saveButton.Active = dirty
	saveButton.AutoButtonColor = false
	Theme.setButtonColor(saveButton, if dirty then C.Accent else C.Locked)
	saveButton.TextColor3 = if dirty then C.OnAccent else C.TextMuted
	if dirty then
		saveStatus.Text = "UNSAVED CHANGES"
		saveStatus.TextColor3 = C.Accent
	elseif saveStatus.Text == "UNSAVED CHANGES" then
		saveStatus.Text = ""
	end
end

local function rebuildSlots()
	clearChildren(slotList)
	local profile = ClientState.profile
	if not profile then
		return
	end
	for i, lo in profile.loadouts do
		local selected = i == editIndex
		local active = i == profile.selectedLoadout
		local button = Theme.button({
			Name = "Slot" .. i,
			Size = UDim2.new(1, 0, 0, 72),
			LayoutOrder = i,
			Parent = slotList,
		})
		Theme.setButtonColor(button, if selected then C.PanelHover else C.PanelLight)
		if selected then
			Theme.stroke(C.Accent, 1, 0.2).Parent = button
		end
		Theme.new("Frame", {
			BackgroundColor3 = if active then C.Accent else C.Stroke,
			BackgroundTransparency = if active then 0 else 0.5,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 4, 1, 0),
			Parent = button,
		})
		Theme.label({
			Text = string.upper(lo.name ~= "" and lo.name or ("Loadout " .. i)),
			Font = Theme.Fonts.Bold,
			TextSize = 18,
			Position = UDim2.fromOffset(18, 10),
			Size = UDim2.new(1, -110, 0, 24),
			Parent = button,
		})
		Theme.label({
			Text = Theme.weaponName(lo.primary) .. "  /  " .. Theme.weaponName(lo.secondary),
			Font = Theme.Fonts.Regular,
			TextSize = 14,
			TextColor3 = C.TextDim,
			Position = UDim2.fromOffset(18, 38),
			Size = UDim2.new(1, -30, 0, 20),
			Parent = button,
		})
		if active then
			Theme.label({
				Text = "ACTIVE",
				Font = Theme.Fonts.Bold,
				TextSize = 12,
				TextColor3 = C.Accent,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 12),
				Size = UDim2.fromOffset(80, 16),
				Parent = button,
			})
		end
		button.Activated:Connect(function()
			if editIndex ~= i then
				editIndex = i
				draft = { primary = lo.primary, secondary = lo.secondary }
				saveStatus.Text = ""
			end
			if profile.selectedLoadout ~= i then
				fire("SelectLoadout", i)
			end
			rebuildSlots()
			rebuildEditor()
		end)
	end
end

local function weaponCard(profile: Types.ProfileSummary, def: WeaponDef, slot: string, order: number, parent: Instance)
	local unlocked = isUnlocked(profile, def)
	local selected = draft ~= nil and (if slot == "Primary" then draft.primary else draft.secondary) == def.id
	local card = Theme.button({
		Name = def.id,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.setButtonColor(card, if selected then C.PanelHover elseif unlocked then C.PanelLight else C.Locked)
	card.BackgroundTransparency = if unlocked then 0.1 else 0.45
	if selected then
		Theme.stroke(C.Accent, 2, 0).Parent = card
	end
	Theme.label({
		Text = string.upper(def.displayName),
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = if unlocked then C.Text else C.TextMuted,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 22),
		Parent = card,
	})
	Theme.label({
		Text = string.upper((def.class:gsub("(%l)(%u)", "%1 %2"))),
		Font = Theme.Fonts.Regular,
		TextSize = 13,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(14, 34),
		Size = UDim2.new(1, -28, 0, 16),
		Parent = card,
	})
	if unlocked then
		local wp = profile.weapons[def.id]
		local level = if wp then wp.level else 1
		local xp = if wp then wp.xp else 0
		local needed = if wp then wp.needed else 0
		Theme.label({
			Text = "LV " .. tostring(level),
			Font = Theme.Fonts.Bold,
			TextSize = 14,
			TextColor3 = C.Accent,
			Position = UDim2.fromOffset(14, 58),
			Size = UDim2.fromOffset(60, 18),
			Parent = card,
		})
		local _, fill = Theme.bar({
			Position = UDim2.fromOffset(70, 64),
			Size = UDim2.new(1, -84, 0, 6),
			Parent = card,
		})
		fill.Size = UDim2.fromScale(if needed > 0 then math.clamp(xp / needed, 0, 1) elseif wp then 1 else 0, 1)
	else
		Theme.label({
			Text = "UNLOCKS AT LEVEL " .. tostring(def.unlockLevel),
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			TextColor3 = C.TextDim,
			Position = UDim2.fromOffset(14, 58),
			Size = UDim2.new(1, -28, 0, 18),
			Parent = card,
		})
	end
	card.Activated:Connect(function()
		if not unlocked or not draft then
			return
		end
		if slot == "Primary" then
			draft.primary = def.id
		else
			draft.secondary = def.id
		end
		rebuildEditor()
	end)
end

rebuildEditor = function()
	clearChildren(primaryGrid)
	clearChildren(secondaryGrid)
	local profile = ClientState.profile
	if not profile then
		editorTitle.Text = "LOADING PROFILE..."
		refreshSave()
		return
	end
	if not editIndex or not profile.loadouts[editIndex] then
		editIndex = math.clamp(profile.selectedLoadout, 1, math.max(#profile.loadouts, 1))
		draft = nil
	end
	local lo = profile.loadouts[editIndex :: number]
	if not lo then
		editorTitle.Text = "NO LOADOUTS"
		refreshSave()
		return
	end
	if not draft then
		draft = { primary = lo.primary, secondary = lo.secondary }
	end
	editorTitle.Text = "EDIT  //  " .. string.upper(lo.name ~= "" and lo.name or ("Loadout " .. tostring(editIndex)))
	for i, def in weaponsForSlot("Primary") do
		weaponCard(profile, def, "Primary", i, primaryGrid)
	end
	for i, def in weaponsForSlot("Secondary") do
		weaponCard(profile, def, "Secondary", i, secondaryGrid)
	end
	refreshSave()
end

---------------------------------------------------------------------------------------------
-- Match info / players / votes
---------------------------------------------------------------------------------------------

local function teamColumn(title: string, color: Color3, lines: { Types.PlayerLine }, widthScale: number, order: number)
	local col: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(widthScale, if widthScale < 1 then -6 else 0, 1, 0),
		LayoutOrder = order,
		Parent = teamsHolder,
	})
	Theme.new("Frame", { BackgroundColor3 = color, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), Parent = col })
	Theme.label({
		Text = string.format("%s  (%d)", string.upper(title), #lines),
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = color,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = col,
	})
	local list: ScrollingFrame = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		Parent = col,
	}, { Theme.list(Enum.FillDirection.Vertical, 3) })
	local profile = ClientState.profile
	for i, line in lines do
		local isMe = line.userId == localPlayer.UserId
		local rowFrame: Frame = Theme.new("Frame", {
			BackgroundColor3 = if isMe then C.Accent else C.PanelLight,
			BackgroundTransparency = if isMe then 0.8 else 0.5,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -4, 0, 28),
			LayoutOrder = i,
			Parent = list,
		}, { Theme.corner(3) })
		Theme.label({
			Text = line.name,
			Font = if isMe then Theme.Fonts.Bold else Theme.Fonts.Medium,
			TextSize = 15,
			TextColor3 = if isMe then C.Accent else C.Text,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -70, 1, 0),
			Parent = rowFrame,
		})
		local level = if isMe and profile then profile.account.level else line.level
		if level then
			Theme.label({
				Text = "RANK " .. tostring(level),
				Font = Theme.Fonts.Bold,
				TextSize = 11,
				TextColor3 = if isMe then C.Accent else C.TextDim,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 0),
				Size = UDim2.new(0, 60, 1, 0),
				Parent = rowFrame,
			})
		end
	end
end

local function rebuildPlayers()
	clearChildren(teamsHolder)
	local ms = ClientState.matchState
	if not ms then
		return
	end
	local anyAssigned = false
	for _, line in ms.players do
		if line.team then
			anyAssigned = true
			break
		end
	end
	-- FFA, or a lobby where teams are not picked yet: one list of everyone present.
	if #ms.teams == 0 or not anyAssigned then
		local everyone = table.clone(ms.players)
		table.sort(everyone, function(a, b)
			return a.name < b.name
		end)
		teamColumn("Operators", C.Accent, everyone, 1, 1)
		return
	end
	local width = 1 / #ms.teams
	for i, team in ms.teams do
		local lines = {}
		for _, line in ms.players do
			if line.team == team.id then
				table.insert(lines, line)
			end
		end
		table.sort(lines, function(a, b)
			return a.name < b.name
		end)
		teamColumn(team.displayName, Theme.teamColor(team.id), lines, width, i)
	end
	-- players not yet assigned to a team
	local unassigned = {}
	for _, line in ms.players do
		if not line.team then
			table.insert(unassigned, line)
		end
	end
	if #unassigned > 0 and #ms.teams > 0 then
		-- show them under the first column header count only; keeps the layout to team columns
		local first = teamsHolder:FindFirstChildWhichIsA("Frame")
		if first then
			local label = Theme.label({
				Text = string.format("+%d UNASSIGNED", #unassigned),
				Font = Theme.Fonts.Medium,
				TextSize = 12,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Right,
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.new(1, 0, 0, 18),
			})
			label.Parent = first
		end
	end
end

local function refreshVotes()
	local ms = ClientState.matchState
	local canVote = ms ~= nil and ms.phase == "Lobby"
	for mapId, button in voteButtons do
		local count = if ms and ms.votes then (ms.votes[mapId] or 0) else 0
		local countLabel = button:FindFirstChild("Count") :: TextLabel?
		if countLabel then
			countLabel.Text = tostring(count) .. (if count == 1 then " VOTE" else " VOTES")
		end
		local mine = myVote == mapId
		Theme.setButtonColor(button, if mine then C.PanelHover else C.PanelLight)
		local stroke = button:FindFirstChild("VoteStroke") :: UIStroke?
		if stroke then
			stroke.Transparency = if mine then 0 else 1
		end
		button.Active = canVote
		button.BackgroundTransparency = if canVote then 0.1 else 0.5
	end
end

local function refreshMatchInfo()
	local ms = ClientState.matchState
	if not ms then
		modeLabel.Text = "CONNECTING..."
		mapLabel.Text = ""
		return
	end
	modeLabel.Text = string.upper(ms.modeName)
	mapLabel.Text = string.upper(ms.mapName)
end

local function phaseText(ms: Types.MatchStatePayload?): string
	if not ms then
		return "CONNECTING"
	end
	if ms.phase == "Lobby" then
		return if ms.phaseEndsAt > 0 then "MATCH STARTS IN" else "WAITING FOR OPERATORS"
	elseif ms.phase == "Countdown" then
		return "DEPLOYING IN"
	elseif ms.phase == "Playing" then
		return "MATCH IN PROGRESS"
	end
	return "MATCH ENDED"
end

---------------------------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------------------------

local function shouldShow(): boolean
	local ms = ClientState.matchState
	if ClientState.deployed then
		return false
	end
	if not ms then
		return true
	end
	if ms.phase == "Lobby" or ms.phase == "Countdown" then
		return true
	end
	if ms.phase == "Playing" then
		-- Dead players awaiting the automatic respawn see the death screen, not the lobby; if no
		-- respawn arrives within respawnDelay + grace, fall back to the lobby (DEPLOY button).
		-- Late joiners (never deployed this match) see the lobby straight away.
		if diedAt then
			return os.clock() - diedAt > Theme.respawnDelay() + Theme.RespawnGrace
		end
		return true
	end
	return false
end

local function refreshDeploy()
	local ms = ClientState.matchState
	local canDeploy = ms ~= nil and ms.phase == "Playing" and not ClientState.deployed
	deployButton.Visible = canDeploy
	bottomStatus.Visible = not canDeploy
end

local function setShown(show: boolean)
	if show == shown then
		return
	end
	shown = show
	if show then
		gui.Enabled = true
		root.BackgroundTransparency = 1
		Theme.tween(root, Theme.Tween.Slow, { BackgroundTransparency = 0.3 })
		mainFrame.Position = UDim2.fromOffset(48, 208)
		Theme.tween(mainFrame, Theme.Tween.Slow, { Position = UDim2.fromOffset(48, 178) })
		rebuildPlayers()
		rebuildSlots()
		rebuildEditor()
	else
		gui.Enabled = false
	end
end

local function refreshVisibility()
	setShown(shouldShow())
	refreshDeploy()
end

---------------------------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------------------------

local function buildTopBar(parent: Instance)
	local top: Frame = Theme.new("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 28),
		Size = UDim2.new(1, -96, 0, 88),
		Parent = parent,
	})
	-- Original text logo: stacked "CALL OF" / "ROBLOX" with an accent chevron bar.
	local logo: Frame = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(460, 88), Parent = top })
	Theme.new("Frame", {
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.fromOffset(8, 72),
		Parent = logo,
	})
	Theme.label({
		Text = "C A L L   O F",
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(22, 6),
		Size = UDim2.fromOffset(420, 22),
		Parent = logo,
	})
	Theme.label({
		Text = "ROBLOX",
		Font = Theme.Fonts.Title,
		TextSize = 56,
		TextColor3 = C.Text,
		Position = UDim2.fromOffset(20, 26),
		Size = UDim2.fromOffset(420, 58),
		Parent = logo,
	})

	-- Rank badge
	local rank = Theme.panel({
		Name = "Rank",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 6),
		Size = UDim2.fromOffset(380, 76),
		Parent = top,
	})
	local badge: Frame = Theme.new("Frame", {
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(56, 56),
		Parent = rank,
	}, { Theme.corner(6) })
	rankNumber = Theme.label({
		Text = "-",
		Font = Theme.Fonts.Title,
		TextSize = 28,
		TextColor3 = C.OnAccent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
	})
	prestigeLabel = Theme.label({
		Text = "OPERATOR RANK",
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(80, 12),
		Size = UDim2.new(1, -94, 0, 18),
		Parent = rank,
	})
	rankXpText = Theme.label({
		Text = "",
		Font = Theme.Fonts.Medium,
		TextSize = 13,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(80, 12),
		Size = UDim2.new(1, -94, 0, 18),
		Parent = rank,
	})
	local _, fill = Theme.bar({
		Position = UDim2.fromOffset(80, 42),
		Size = UDim2.new(1, -94, 0, 10),
		Parent = rank,
	})
	rankFill = fill
end

local function buildWarning(parent: Instance)
	warningBanner = Theme.new("Frame", {
		Name = "TemporaryWarning",
		BackgroundColor3 = Color3.fromRGB(90, 18, 14),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 126),
		Size = UDim2.new(1, -96, 0, 40),
		Visible = false,
		Parent = parent,
	}, { Theme.corner(6) :: Instance, Theme.stroke(C.Danger, 1, 0.1) })
	Theme.label({
		Text = "!  Progress saving unavailable (DataStores offline) — progress this session will not be kept",
		Font = Theme.Fonts.Bold,
		TextSize = 17,
		TextColor3 = Color3.fromRGB(255, 205, 200),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = warningBanner,
	})
end

local function buildLoadoutColumns(parent: Instance)
	-- left: slots
	local slotsPanel = Theme.panel({ Name = "Loadouts", Size = UDim2.new(0.22, -14, 1, 0), LayoutOrder = 1, Parent = parent })
	Theme.padding(14).Parent = slotsPanel
	sectionTitle("LOADOUTS", slotsPanel)
	slotList = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		Parent = slotsPanel,
	}, { Theme.list(Enum.FillDirection.Vertical, 8) })

	-- middle: editor
	local editor = Theme.panel({ Name = "Editor", Size = UDim2.new(0.43, -14, 1, 0), LayoutOrder = 2, Parent = parent })
	Theme.padding(14).Parent = editor
	editorTitle = sectionTitle("LOADING PROFILE...", editor)
	editorBody = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30 - 62),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		Parent = editor,
	}, { Theme.list(Enum.FillDirection.Vertical, 10) })
	local function grid(title: string, order: number): Frame
		Theme.label({
			Text = title,
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = order,
			Parent = editorBody,
		})
		return Theme.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -6, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order + 1,
			Parent = editorBody,
		}, {
			Theme.new("UIGridLayout", {
				CellSize = UDim2.new(0.5, -6, 0, 86),
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end
	primaryGrid = grid("PRIMARY", 1)
	secondaryGrid = grid("SECONDARY", 3)

	local saveRow: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 50),
		Parent = editor,
	})
	saveButton = Theme.button({
		Text = "SAVE LOADOUT",
		TextSize = 18,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 220, 1, 0),
		Parent = saveRow,
	}, "Primary")
	saveStatus = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.TextDim,
		Size = UDim2.new(1, -236, 1, 0),
		Parent = saveRow,
	})
	saveButton.Activated:Connect(function()
		if not isDirty() or not editIndex or not draft then
			return
		end
		fire("SetLoadout", editIndex, { primary = draft.primary, secondary = draft.secondary })
		saveStatus.Text = "SAVING..."
		saveStatus.TextColor3 = C.TextDim
	end)
end

local function buildRightColumn(parent: Instance)
	local col: Frame = Theme.new("Frame", {
		Name = "Match",
		BackgroundTransparency = 1,
		Size = UDim2.new(0.35, 0, 1, 0),
		LayoutOrder = 3,
		Parent = parent,
	})

	-- match info
	local info = Theme.panel({ Size = UDim2.new(1, 0, 0, 124), Parent = col })
	Theme.padding(14, 16).Parent = info
	modeLabel = Theme.label({ Font = Theme.Fonts.Bold, TextSize = 15, TextColor3 = C.Accent, Size = UDim2.new(0.6, 0, 0, 20), Parent = info })
	mapLabel = Theme.label({ Font = Theme.Fonts.Title, TextSize = 28, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(0.62, 0, 0, 34), Parent = info })
	phaseLabel = Theme.label({ Font = Theme.Fonts.Bold, TextSize = 13, TextColor3 = C.TextDim, Position = UDim2.fromOffset(0, 66), Size = UDim2.new(0.62, 0, 0, 18), Parent = info })
	timerLabel = Theme.label({
		Text = "",
		Font = Theme.Fonts.Title,
		TextSize = 52,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.4, 0, 0, 60),
		Parent = info,
	})

	-- map vote (bottom)
	local maps = Theme.Match.Maps
	local voteHeight = 44 + #maps * 56
	local votePanel = Theme.panel({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, voteHeight),
		Parent = col,
	})
	Theme.padding(12, 14).Parent = votePanel
	sectionTitle("MAP VOTE", votePanel)
	voteList = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 1, -28),
		Parent = votePanel,
	}, { Theme.list(Enum.FillDirection.Vertical, 6) })
	for i, mapId in maps do
		local button = Theme.button({ Name = mapId, Size = UDim2.new(1, 0, 0, 50), LayoutOrder = i, Parent = voteList })
		local stroke = Theme.stroke(C.Accent, 2, 1)
		stroke.Name = "VoteStroke"
		stroke.Parent = button
		Theme.label({
			Text = string.upper(Theme.mapDisplayName(mapId)),
			Font = Theme.Fonts.Bold,
			TextSize = 17,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(1, -130, 1, 0),
			Parent = button,
		})
		Theme.label({
			Name = "Count",
			Text = "0 VOTES",
			Font = Theme.Fonts.Bold,
			TextSize = 14,
			TextColor3 = C.Accent,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.new(0, 110, 1, 0),
			Parent = button,
		})
		button.Activated:Connect(function()
			local ms = ClientState.matchState
			if not ms or ms.phase ~= "Lobby" then
				return
			end
			myVote = mapId
			fire("VoteMap", mapId)
			refreshVotes()
		end)
		voteButtons[mapId] = button
	end

	-- players
	local playersPanel = Theme.panel({
		Position = UDim2.fromOffset(0, 136),
		Size = UDim2.new(1, 0, 1, -136 - voteHeight - 12),
		Parent = col,
	})
	Theme.padding(12, 14).Parent = playersPanel
	sectionTitle("OPERATORS", playersPanel)
	teamsHolder = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 1, -28),
		Parent = playersPanel,
	}, { Theme.list(Enum.FillDirection.Horizontal, 12) })
end

local function buildBottom(parent: Instance)
	deployButton = Theme.button({
		Name = "Deploy",
		Text = "DEPLOY",
		Font = Theme.Fonts.Title,
		TextSize = 34,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28),
		Size = UDim2.fromOffset(380, 74),
		Visible = false,
		Parent = parent,
	}, "Primary")
	deployButton.Activated:Connect(function()
		fire("RequestDeploy")
		deployButton.Text = "DEPLOYING..."
		task.delay(3, function()
			deployButton.Text = "DEPLOY"
		end)
	end)
	bottomStatus = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 20,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -44),
		Size = UDim2.fromOffset(700, 30),
		Parent = parent,
	})
end

function Lobby.init()
	local canvas
	gui, canvas = Theme.screen("Lobby", 10)
	root = Theme.new("Frame", {
		Name = "Lobby",
		BackgroundColor3 = C.Backdrop,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = canvas,
	})
	Theme.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.6, 0.25),
			NumberSequenceKeypoint.new(1, 0.1),
		}),
		Parent = root,
	})
	gui.Enabled = false

	buildTopBar(root)
	buildWarning(root)
	mainFrame = Theme.new("Frame", {
		Name = "Main",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 178),
		Size = UDim2.new(1, -96, 1, -178 - 120),
		Parent = root,
	}, { Theme.list(Enum.FillDirection.Horizontal, 20) })
	buildLoadoutColumns(mainFrame)
	buildRightColumn(mainFrame)
	buildBottom(root)
	Theme.mount(gui)

	ClientState.ProfileChanged:Connect(function()
		refreshRank()
		local lo = currentLoadout()
		if lo and draft and saveStatus.Text == "SAVING..." and draft.primary == lo.primary and draft.secondary == lo.secondary then
			saveStatus.Text = "SAVED"
			saveStatus.TextColor3 = C.Positive
		end
		if not isDirty() then
			draft = nil -- re-sync draft from the authoritative profile
		end
		if shown then
			rebuildSlots()
			rebuildEditor()
		end
	end)
	ClientState.MatchStateChanged:Connect(function(ms)
		if ms.phase == "Lobby" or ms.phase == "Results" then
			diedAt = nil
		end
		if ms.phase == "Lobby" and ms.votes and myVote and (ms.votes[myVote] or 0) == 0 then
			myVote = nil -- votes were reset for a new lobby
		end
		refreshMatchInfo()
		refreshVotes()
		if shown then
			rebuildPlayers()
		end
		refreshVisibility()
	end)
	ClientState.DeployedChanged:Connect(function(deployed: boolean)
		local ms = ClientState.matchState
		local was = lastDeployed
		lastDeployed = deployed
		if deployed then
			diedAt = nil
		elseif was and ms and ms.phase == "Playing" and diedAt == nil then
			diedAt = os.clock()
		end
		refreshVisibility()
	end)

	lastDeployed = ClientState.deployed
	refreshRank()
	refreshMatchInfo()
	refreshVotes()
	refreshVisibility()
end

function Lobby.start()
	local lastTimer, lastPhase, lastBottom = "", "", ""
	while true do
		local ms = ClientState.matchState
		-- re-evaluate the respawn fallback (time based)
		if not ClientState.deployed then
			refreshVisibility()
		end
		if shown then
			local timer = ""
			if ms and ms.phaseEndsAt > 0 then
				timer = Theme.formatTime(ms.phaseEndsAt - Theme.serverNow())
			end
			local phase = phaseText(ms)
			local bottom = ""
			if ms then
				if ms.phase == "Lobby" then
					bottom = if ms.phaseEndsAt > 0 then "SELECT YOUR LOADOUT  -  MATCH STARTS IN " .. timer else "WAITING FOR MORE OPERATORS..."
				elseif ms.phase == "Countdown" then
					bottom = "DEPLOYING IN " .. timer
				end
			end
			if timer ~= lastTimer then
				lastTimer = timer
				timerLabel.Text = timer
			end
			if phase ~= lastPhase then
				lastPhase = phase
				phaseLabel.Text = phase
			end
			if bottom ~= lastBottom then
				lastBottom = bottom
				bottomStatus.Text = bottom
			end
		end
		task.wait(0.2)
	end
end

return Lobby
