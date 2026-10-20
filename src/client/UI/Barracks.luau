--!strict
-- Barracks (Phase 5): full-screen lobby menu with four tabs.
--   CHALLENGES        today's daily challenges (progress, XP reward, done state, time until reset)
--   CAREER            lifetime stats and the top weapons by kills
--   TITLES & EMBLEMS  owned ones equip with EquipCosmetic; locked ones show their requirement
--   PRESTIGE          current prestige + emblem, what prestiging does, and a two-step confirm that
--                     fires Prestige("PRESTIGE") (enabled only when ProfileSummary.canPrestige)
--
-- Public API (the Lobby's BARRACKS button is the caller):
--   Barracks.open(tab?, onClosed?) -> boolean    tab: "Challenges" | "Career" | "Cosmetics" | "Prestige"
--   Barracks.close()
--   Barracks.isOpen() -> boolean
-- BACK button / Backspace / gamepad B close it (Escape is not bound: it opens the Roblox menu).
-- It closes by itself when the local player deploys. Everything here is a view of the server's
-- ProfileSummary; the server validates every request.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Phase5Rules = require(script.Parent.Phase5Rules)
local ClientState = require(script.Parent.Parent.ClientState)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local CosmeticsConfig = require(Shared.Config.Cosmetics)
local Progression = require(Shared.Config.Progression)

local Barracks = {}

local C = Theme.Colors
local BACK_ACTION = "COR_BarracksBack"
local ARM_TIMEOUT = 12 -- seconds an armed prestige stays armed
local PRESTIGE_TEXT =
	"Your level goes back to 1. Weapons, attachments, perks, killstreaks and camos stay unlocked. You earn the next prestige emblem."

type Tab = "Challenges" | "Career" | "Cosmetics" | "Prestige"
local TABS: { { id: Tab, text: string } } = {
	{ id = "Challenges", text = "CHALLENGES" },
	{ id = "Career", text = "CAREER" },
	{ id = "Cosmetics", text = "TITLES & EMBLEMS" },
	{ id = "Prestige", text = "PRESTIGE" },
}

-- state
local gui: ScreenGui
local root: TextButton
local content: Frame
local body: Frame
local subtitle: TextLabel
local tabButtons: { [string]: TextButton } = {}
local isOpenFlag = false
local currentTab: Tab = "Challenges"
local onClosedCb: (() -> ())? = nil
local openConns: { any } = {}
local resetLabel: TextLabel? = nil -- live countdown on the CHALLENGES tab
local armed = false
local armedAt = 0
local prestigePending = false
local pendingPrestigeFrom = -1
local prestigeNote = ""
local pendingTitle: string? = nil
local pendingEmblem: string? = nil

---------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------

local function clearGuiChildren(parent: Instance)
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
			warn("[Barracks] " .. remote .. " failed: " .. tostring(err))
		end
	end)
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

local function scroll(parent: Instance, props: { [string]: any }?, spacing: number?): ScrollingFrame
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local s: ScrollingFrame = Theme.new("ScrollingFrame", base, { Theme.list(Enum.FillDirection.Vertical, spacing or 10) })
	return s
end

local function inMatchPhase(): boolean
	local ms = ClientState.matchState
	return ms ~= nil and (ms.phase == "Countdown" or ms.phase == "Playing")
end

local function cosmetics(profile: Types.ProfileSummary): Types.CosmeticsView?
	local c = (profile :: any).cosmetics
	return if type(c) == "table" and type(c.equipped) == "table" and type(c.owned) == "table" then c else nil
end

local function equippedTitle(profile: Types.ProfileSummary): string
	local c = cosmetics(profile)
	return pendingTitle or (if c and type(c.equipped.title) == "string" then c.equipped.title else CosmeticsConfig.DefaultTitle)
end

local function equippedEmblem(profile: Types.ProfileSummary): string
	if pendingEmblem then
		return pendingEmblem
	end
	local c = cosmetics(profile)
	return if c and type(c.equipped.emblem) == "string" then c.equipped.emblem else ""
end

local function owns(profile: Types.ProfileSummary, kind: "titles" | "emblems", id: string): boolean
	local c = cosmetics(profile)
	local list = if c then (c.owned :: any)[kind] else nil
	return type(list) == "table" and table.find(list, id) ~= nil
end

local function emptyNote(text: string)
	Theme.label({
		Text = text,
		Font = Theme.Fonts.Medium,
		TextSize = 18,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 60),
		Parent = body,
	})
end

---------------------------------------------------------------------------------------------
-- CHALLENGES
---------------------------------------------------------------------------------------------

local function resetText(profile: Types.ProfileSummary): string
	local ch = (profile :: any).challenges
	local at = if type(ch) == "table" and type(ch.resetsAt) == "number" then ch.resetsAt else 0
	if at <= 0 then
		return ""
	end
	return "NEW CHALLENGES IN " .. Phase5Rules.countdown(at - os.time())
end

local function renderChallenges(profile: Types.ProfileSummary)
	local panel = Theme.panel({ Size = UDim2.fromScale(1, 1), Parent = body })
	Theme.padding(18).Parent = panel
	sectionTitle("DAILY CHALLENGES", panel)
	resetLabel = Theme.label({
		Text = resetText(profile),
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = panel,
	})
	local list = scroll(panel, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34) }, 12)
	local ch = (profile :: any).challenges
	local items: { Types.ChallengeView } = if type(ch) == "table" and type(ch.list) == "table" then ch.list else {}
	if #items == 0 then
		Theme.label({
			Text = "No challenges available right now.",
			Font = Theme.Fonts.Medium,
			TextSize = 18,
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = list,
		})
	end
	for i, c in items do
		local target = math.max(c.target, 1)
		local progress = math.clamp(c.progress, 0, target)
		local card: Frame = Theme.new("Frame", {
			BackgroundColor3 = if c.done then C.PanelHover else C.PanelLight,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, 104),
			LayoutOrder = i,
			Parent = list,
		}, { Theme.corner(6) })
		if c.done then
			Theme.stroke(C.Accent, 2, 0).Parent = card
		end
		Theme.new("Frame", {
			BackgroundColor3 = if c.done then C.Accent else C.Stroke,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 5, 1, 0),
			Parent = card,
		})
		Theme.label({
			Text = string.upper(Phase5Rules.challengeText(c.text, c.target)),
			Font = Theme.Fonts.Bold,
			TextSize = 22,
			TextColor3 = if c.done then C.Accent else C.Text,
			Position = UDim2.fromOffset(24, 14),
			Size = UDim2.new(1, -240, 0, 28),
			Parent = card,
		})
		Theme.label({
			Text = "+" .. tostring(c.xp) .. " XP",
			Font = Theme.Fonts.Title,
			TextSize = 24,
			TextColor3 = C.Accent,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -20, 0, 14),
			Size = UDim2.fromOffset(200, 28),
			Parent = card,
		})
		Theme.label({
			Text = if c.done then "COMPLETE" else string.format("%d / %d", progress, target),
			Font = Theme.Fonts.Bold,
			TextSize = 15,
			TextColor3 = if c.done then C.Accent else C.TextDim,
			Position = UDim2.fromOffset(24, 50),
			Size = UDim2.new(1, -48, 0, 18),
			Parent = card,
		})
		local _, fill = Theme.bar({ Position = UDim2.fromOffset(24, 76), Size = UDim2.new(1, -48, 0, 12), Parent = card })
		fill.Size = UDim2.fromScale(if c.done then 1 else progress / target, 1)
	end
	Theme.label({
		Text = "Challenges change every day at 00:00 UTC. Rewards are account XP. Killstreak kills do not count.",
		Font = Theme.Fonts.Regular,
		TextSize = 14,
		TextColor3 = C.TextMuted,
		TextWrapped = true,
		Size = UDim2.new(1, -8, 0, 40),
		LayoutOrder = 100,
		Parent = list,
	})
end

---------------------------------------------------------------------------------------------
-- CAREER
---------------------------------------------------------------------------------------------

local function statTile(label: string, value: string, order: number, parent: Instance)
	local tile: Frame = Theme.new("Frame", {
		BackgroundColor3 = C.PanelLight,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	}, { Theme.corner(6) })
	Theme.label({
		Text = label,
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 16),
		Parent = tile,
	})
	Theme.label({
		Text = value,
		Font = Theme.Fonts.Title,
		TextSize = 32,
		Position = UDim2.fromOffset(16, 32),
		Size = UDim2.new(1, -32, 0, 38),
		Parent = tile,
	})
end

local function renderCareer(profile: Types.ProfileSummary)
	local st = profile.stats or ({} :: any)
	local function n(key: string): number
		local v = (st :: any)[key]
		return if type(v) == "number" then v else 0
	end
	local left = Theme.panel({ Size = UDim2.new(0.62, -10, 1, 0), Parent = body })
	Theme.padding(18).Parent = left
	sectionTitle("LIFETIME", left)
	local grid: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		Parent = left,
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.new(0.25, -9, 0, 84),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local kills, deaths, matches, wins = n("kills"), n("deaths"), n("matches"), n("wins")
	local tiles = {
		{ "KILLS", tostring(kills) },
		{ "DEATHS", tostring(deaths) },
		{ "K/D RATIO", string.format("%.2f", kills / math.max(deaths, 1)) },
		{ "ASSISTS", tostring(n("assists")) },
		{ "MATCHES", tostring(matches) },
		{ "WINS", tostring(wins) },
		{ "WIN RATE", string.format("%d%%", math.floor(wins / math.max(matches, 1) * 100 + 0.5)) },
		{ "HEADSHOT KILLS", tostring(n("headshots")) },
		{ "FLAG CAPTURES", tostring(n("captures")) },
		{ "BOMB PLANTS", tostring(n("plants")) },
		{ "DEFUSES", tostring(n("defuses")) },
		{ "TAGS", tostring(n("tags")) },
		{ "DAILIES DONE", tostring(n("dailies")) },
		{ "ACCOUNT LEVEL", tostring(profile.account.level) },
		{ "PRESTIGE", if profile.account.prestige > 0 then Phase5Rules.roman(profile.account.prestige) else "-" },
	}
	for i, t in tiles do
		statTile(t[1], t[2], i, grid)
	end

	local right = Theme.panel({ Size = UDim2.new(0.38, -10, 1, 0), Parent = body })
	Theme.padding(18).Parent = right
	sectionTitle("TOP WEAPONS", right)
	local list = scroll(right, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34) }, 6)
	local weapons = {}
	for id, w in (profile.weapons or {}) :: { [string]: any } do
		if type(w) == "table" and (w.kills or 0) > 0 then
			table.insert(weapons, { id = id, kills = w.kills or 0, headshots = w.headshots or 0, level = w.level or 1 })
		end
	end
	table.sort(weapons, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.id < b.id
	end)
	if #weapons == 0 then
		Theme.label({ Text = "No weapon kills yet.", TextSize = 16, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 30), Parent = list })
	end
	for i = 1, math.min(8, #weapons) do
		local w = weapons[i]
		local row: Frame = Theme.new("Frame", {
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -6, 0, 52),
			LayoutOrder = i,
			Parent = list,
		}, { Theme.corner(4) })
		Theme.label({
			Text = string.format("%d  %s", i, string.upper(Theme.weaponName(w.id))),
			Font = Theme.Fonts.Bold,
			TextSize = 16,
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.new(1, -24, 0, 20),
			Parent = row,
		})
		Theme.label({
			Text = string.format("LV %d  ·  %d KILLS  ·  %d HEADSHOTS", w.level, w.kills, w.headshots),
			Font = Theme.Fonts.Medium,
			TextSize = 12,
			TextColor3 = C.TextDim,
			Position = UDim2.fromOffset(12, 28),
			Size = UDim2.new(1, -24, 0, 16),
			Parent = row,
		})
	end
end

---------------------------------------------------------------------------------------------
-- TITLES & EMBLEMS
---------------------------------------------------------------------------------------------

local render: () -> ()

local function renderCosmetics(profile: Types.ProfileSummary)
	local equippedT = equippedTitle(profile)
	local equippedE = equippedEmblem(profile)

	-- titles
	local left = Theme.panel({ Size = UDim2.new(0.55, -10, 1, 0), Parent = body })
	Theme.padding(18).Parent = left
	sectionTitle("TITLES  //  SHOWN UNDER YOUR NAME", left)
	local list = scroll(left, { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 1, -34) }, 8)
	for i, t in CosmeticsConfig.titles do
		local owned = owns(profile, "titles", t.id) or (t.stat == nil and t.source == nil)
		local isOn = equippedT == t.id
		local card = Theme.button({ Name = t.id, Size = UDim2.new(1, -8, 0, 64), LayoutOrder = i, Parent = list })
		Theme.setButtonColor(card, if isOn then C.PanelHover elseif owned then C.PanelLight else C.Locked)
		card.BackgroundTransparency = if owned then 0.1 else 0.45
		if isOn then
			Theme.stroke(C.Accent, 2, 0).Parent = card
		end
		Theme.label({
			Text = string.upper(t.name),
			Font = Theme.Fonts.Bold,
			TextSize = 18,
			TextColor3 = if owned then C.Text else C.TextMuted,
			Position = UDim2.fromOffset(16, 8),
			Size = UDim2.new(1, -200, 0, 22),
			Parent = card,
		})
		Theme.label({
			Text = t.description,
			Font = Theme.Fonts.Regular,
			TextSize = 13,
			TextColor3 = C.TextDim,
			Position = UDim2.fromOffset(16, 34),
			Size = UDim2.new(1, -200, 0, 18),
			Parent = card,
		})
		local status, color = "EQUIP", C.TextDim
		if isOn then
			status, color = "EQUIPPED", C.Accent
		elseif not owned then
			local req = Phase5Rules.titleRequirement(t, profile.stats)
			status, color = req.progress, C.TextMuted
			local _, fill = Theme.bar({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -16, 0, 40),
				Size = UDim2.fromOffset(160, 6),
				Parent = card,
			})
			fill.Size = UDim2.fromScale(req.alpha, 1)
		end
		Theme.label({
			Text = status,
			Font = Theme.Fonts.Bold,
			TextSize = 14,
			TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 12),
			Size = UDim2.fromOffset(160, 20),
			Parent = card,
		})
		card.Activated:Connect(function()
			if not isOpenFlag or not owned or equippedTitle(profile) == t.id then
				return
			end
			pendingTitle = t.id
			fire("EquipCosmetic", "Title", t.id)
			render()
		end)
	end

	-- emblems
	local right = Theme.panel({ Size = UDim2.new(0.45, -10, 1, 0), Parent = body })
	Theme.padding(18).Parent = right
	sectionTitle("PRESTIGE EMBLEMS", right)
	local grid: ScrollingFrame = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = right,
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.new(0.5, -8, 0, 84),
			CellPadding = UDim2.fromOffset(10, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local function emblemCard(id: string, order: number)
		local def = CosmeticsConfig.emblemById[id]
		local owned = id == "" or owns(profile, "emblems", id)
		local isOn = equippedE == id
		local card = Theme.button({ Name = if id == "" then "None" else id, LayoutOrder = order, Parent = grid })
		Theme.setButtonColor(card, if isOn then C.PanelHover elseif owned then C.PanelLight else C.Locked)
		card.BackgroundTransparency = if owned then 0.1 else 0.45
		if isOn then
			Theme.stroke(C.Accent, 2, 0).Parent = card
		end
		local badge = Theme.emblemBadge(if id == "" then nil else id, 52, {
			Position = UDim2.fromOffset(14, 16),
			BackgroundTransparency = if owned then 0 else 0.6,
			Parent = card,
		})
		if not badge then
			Theme.new("Frame", {
				BackgroundColor3 = C.Panel,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(14, 16),
				Size = UDim2.fromOffset(52, 52),
				Parent = card,
			}, { Theme.corner(9) :: Instance, Theme.stroke(C.Stroke, 1, 0.3) })
		end
		Theme.label({
			Text = if def then string.upper(def.name) else "NO EMBLEM",
			Font = Theme.Fonts.Bold,
			TextSize = 15,
			TextColor3 = if owned then C.Text else C.TextMuted,
			Position = UDim2.fromOffset(78, 18),
			Size = UDim2.new(1, -88, 0, 20),
			Parent = card,
		})
		Theme.label({
			Text = if isOn then "EQUIPPED" elseif owned then "EQUIP" elseif def and def.source then Phase5Rules.sourceText(def.source) :: string elseif def then "REACH PRESTIGE " .. tostring(def.prestige) else "",
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			TextColor3 = if isOn then C.Accent else C.TextDim,
			Position = UDim2.fromOffset(78, 42),
			Size = UDim2.new(1, -88, 0, 18),
			Parent = card,
		})
		card.Activated:Connect(function()
			if not isOpenFlag or not owned or equippedEmblem(profile) == id then
				return
			end
			pendingEmblem = id
			fire("EquipCosmetic", "Emblem", id)
			render()
		end)
	end
	emblemCard("", 0)
	for i, e in CosmeticsConfig.emblems do
		emblemCard(e.id, i)
	end
end

---------------------------------------------------------------------------------------------
-- PRESTIGE
---------------------------------------------------------------------------------------------

local function renderPrestige(profile: Types.ProfileSummary)
	local acc = profile.account
	local maxPrestige = if type((profile :: any).maxPrestige) == "number" then (profile :: any).maxPrestige else Progression.MaxPrestige
	local canPrestige = (profile :: any).canPrestige == true
	local panel = Theme.panel({ Size = UDim2.fromScale(1, 1), Parent = body })
	Theme.padding(28).Parent = panel

	-- current prestige (left)
	local left: Frame = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.36, 0, 1, 0), Parent = panel })
	sectionTitle("CURRENT", left)
	local currentId = Phase5Rules.prestigeEmblem(acc.prestige, Progression.MaxPrestige)
	local badge = Theme.emblemBadge(currentId, 160, { Position = UDim2.fromOffset(0, 40), Parent = left })
	if not badge then
		Theme.new("Frame", {
			BackgroundColor3 = C.PanelLight,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 40),
			Size = UDim2.fromOffset(160, 160),
			Parent = left,
		}, {
			Theme.corner(28) :: Instance,
			Theme.stroke(C.Stroke, 1, 0.3) :: Instance,
			Theme.label({
				Text = "-",
				Font = Theme.Fonts.Title,
				TextSize = 64,
				TextColor3 = C.TextMuted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
			}),
		})
	end
	Theme.label({
		Text = if acc.prestige > 0 then "PRESTIGE " .. Phase5Rules.roman(acc.prestige) else "NO PRESTIGE YET",
		Font = Theme.Fonts.Title,
		TextSize = 32,
		Position = UDim2.fromOffset(0, 216),
		Size = UDim2.new(1, 0, 0, 38),
		Parent = left,
	})
	Theme.label({
		Text = string.format("%d / %d  ·  LEVEL %d / %d", acc.prestige, maxPrestige, acc.level, Progression.MaxAccountLevel),
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(0, 258),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = left,
	})

	-- explanation + action (right)
	local right: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.4, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		Parent = panel,
	})
	sectionTitle("WHAT PRESTIGE DOES", right)
	Theme.label({
		Text = PRESTIGE_TEXT,
		Font = Theme.Fonts.Medium,
		TextSize = 20,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 84),
		Parent = right,
	})
	local nextId = Phase5Rules.prestigeEmblem(acc.prestige + 1, Progression.MaxPrestige)
	local nextDef = if nextId and acc.prestige < maxPrestige then CosmeticsConfig.emblemById[nextId] else nil
	if nextDef then
		local row: Frame = Theme.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 128), Size = UDim2.new(1, 0, 0, 56), Parent = right })
		Theme.emblemBadge(nextDef.id, 52, { Parent = row })
		Theme.label({
			Text = "NEXT REWARD: " .. string.upper(nextDef.name) .. " EMBLEM",
			Font = Theme.Fonts.Bold,
			TextSize = 17,
			Position = UDim2.fromOffset(66, 0),
			Size = UDim2.new(1, -66, 1, 0),
			Parent = row,
		})
	end

	local requirement: string
	if acc.prestige >= maxPrestige then
		requirement = "MAXIMUM PRESTIGE REACHED"
	elseif canPrestige then
		requirement = if inMatchPhase() then "AVAILABLE BETWEEN MATCHES" else "READY TO PRESTIGE"
	else
		requirement = string.format("REACH LEVEL %d TO PRESTIGE  (LEVEL %d NOW)", Progression.MaxAccountLevel, acc.level)
	end
	Theme.label({
		Text = if prestigeNote ~= "" then prestigeNote else requirement,
		Font = Theme.Fonts.Bold,
		TextSize = 15,
		TextColor3 = if canPrestige then C.Accent else C.TextDim,
		Position = UDim2.fromOffset(0, 200),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = right,
	})

	local enabled = canPrestige and not inMatchPhase() and not prestigePending
	local actions: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 232),
		Size = UDim2.new(1, 0, 0, 150),
		Parent = right,
	})
	if not armed or not enabled then
		local button = Theme.button({
			Name = "Prestige",
			Text = if prestigePending then "PRESTIGING..." else "PRESTIGE",
			Font = Theme.Fonts.Title,
			TextSize = 26,
			Size = UDim2.fromOffset(320, 64),
			Parent = actions,
		}, if enabled then "Primary" else nil)
		button.Active = enabled
		button.Selectable = enabled
		if not enabled then
			Theme.setButtonColor(button, C.Locked)
			button.TextColor3 = C.TextMuted
		end
		button.Activated:Connect(function()
			if not button.Active or not isOpenFlag then
				return
			end
			armed = true
			armedAt = os.clock()
			render()
		end)
	else
		-- step two: an explicit, differently coloured confirm button (and a way out)
		local warnBox: Frame = Theme.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(90, 18, 14),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 56),
			Parent = actions,
		}, { Theme.corner(6) :: Instance, Theme.stroke(C.Danger, 1, 0.1) })
		Theme.label({
			Text = string.format("ARE YOU SURE? YOUR LEVEL RESETS TO 1 (FROM %d).", acc.level),
			Font = Theme.Fonts.Bold,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(255, 205, 200),
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = warnBox,
		})
		local row: Frame = Theme.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 70),
			Size = UDim2.new(1, 0, 0, 64),
		Parent = actions,
		}, { Theme.list(Enum.FillDirection.Horizontal, 12) })
		local confirm = Theme.button({
			Name = "ConfirmPrestige",
			Text = "CONFIRM PRESTIGE",
			Font = Theme.Fonts.Title,
			TextSize = 22,
			TextColor3 = C.White,
			Size = UDim2.fromOffset(320, 64),
			LayoutOrder = 1,
			Parent = row,
		})
		Theme.setButtonColor(confirm, C.Danger)
		local cancel = Theme.button({ Name = "Cancel", Text = "CANCEL", TextSize = 20, Size = UDim2.fromOffset(180, 64), LayoutOrder = 2, Parent = row })
		confirm.Activated:Connect(function()
			if not isOpenFlag or not armed or prestigePending then
				return
			end
			local p = ClientState.profile
			if not p or (p :: any).canPrestige ~= true or inMatchPhase() then
				armed = false
				render()
				return
			end
			armed = false
			prestigePending = true
			pendingPrestigeFrom = p.account.prestige
			prestigeNote = ""
			fire("Prestige", "PRESTIGE")
			render()
			task.delay(8, function()
				if prestigePending then
					prestigePending = false
					prestigeNote = "PRESTIGE NOT CONFIRMED - TRY AGAIN"
					if isOpenFlag then
						render()
					end
				end
			end)
		end)
		cancel.Activated:Connect(function()
			armed = false
			render()
		end)
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = cancel
		end
	end
end

---------------------------------------------------------------------------------------------
-- render / tabs
---------------------------------------------------------------------------------------------

render = function()
	if not isOpenFlag then
		return
	end
	resetLabel = nil
	clearGuiChildren(body)
	for id, button in tabButtons do
		local on = id == currentTab
		Theme.setButtonColor(button, if on then C.Accent else C.PanelLight)
		button.TextColor3 = if on then C.OnAccent else C.TextDim
	end
	local profile = ClientState.profile
	if not profile then
		subtitle.Text = "LOADING PROFILE..."
		emptyNote("Loading profile...")
		return
	end
	subtitle.Text = string.format(
		"%s  ·  LEVEL %d%s  ·  %s",
		string.upper(Players.LocalPlayer.DisplayName),
		profile.account.level,
		if profile.account.prestige > 0 then "  ·  PRESTIGE " .. Phase5Rules.roman(profile.account.prestige) else "",
		Theme.titleName(equippedTitle(profile))
	)
	if currentTab == "Challenges" then
		renderChallenges(profile)
	elseif currentTab == "Career" then
		renderCareer(profile)
	elseif currentTab == "Cosmetics" then
		renderCosmetics(profile)
	else
		renderPrestige(profile)
	end
end

local function selectTab(tab: Tab)
	if currentTab ~= tab then
		currentTab = tab
		armed = false
	end
	render()
end

---------------------------------------------------------------------------------------------
-- open / close
---------------------------------------------------------------------------------------------

function Barracks.isOpen(): boolean
	return isOpenFlag
end

function Barracks.close()
	if not isOpenFlag then
		return
	end
	isOpenFlag = false
	for _, conn in openConns do
		conn:Disconnect()
	end
	table.clear(openConns)
	ContextActionService:UnbindAction(BACK_ACTION)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
	gui.Enabled = false
	clearGuiChildren(body)
	resetLabel = nil
	armed = false
	ClientState.setMenuOpen("Barracks", false)
	local cb = onClosedCb
	onClosedCb = nil
	if cb then
		task.spawn(cb)
	end
end

function Barracks.open(tab: string?, onClosed: (() -> ())?): boolean
	if isOpenFlag then
		Barracks.close()
	end
	if ClientState.deployed then
		return false
	end
	for _, t in TABS do
		if t.id == tab then
			currentTab = t.id
		end
	end
	isOpenFlag = true
	onClosedCb = onClosed
	armed = false
	prestigeNote = ""
	ClientState.setMenuOpen("Barracks", true)
	gui.Enabled = true
	root.BackgroundTransparency = 1
	Theme.tween(root, Theme.Tween.Normal, { BackgroundTransparency = 0 })
	content.Position = UDim2.fromOffset(0, 24)
	Theme.tween(content, Theme.Tween.Slow, { Position = UDim2.fromOffset(0, 0) })
	render()

	table.insert(openConns, ClientState.ProfileChanged:Connect(function(profile: Types.ProfileSummary)
		pendingTitle = nil
		pendingEmblem = nil
		if prestigePending and profile.account.prestige > pendingPrestigeFrom then
			prestigePending = false
			prestigeNote = "PRESTIGE " .. Phase5Rules.roman(profile.account.prestige) .. " REACHED"
		end
		render()
	end))
	table.insert(openConns, ClientState.DeployedChanged:Connect(function(deployed: boolean)
		if deployed then
			Barracks.close()
		end
	end))
	table.insert(openConns, ClientState.MatchStateChanged:Connect(function()
		if currentTab == "Prestige" then
			render() -- the button depends on the match phase
		end
	end))
	table.insert(openConns, ClientState.Notify:Connect(function(text: string, kind: string)
		-- a refused equip / prestige comes back as a warning: drop the optimistic state
		if kind == "Warning" and type(text) == "string" then
			pendingTitle = nil
			pendingEmblem = nil
			render()
		end
	end))
	ContextActionService:BindActionAtPriority(BACK_ACTION, function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
		if state == Enum.UserInputState.Begin then
			if armed then
				armed = false
				task.defer(render)
			else
				task.defer(Barracks.close)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 50, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = tabButtons[currentTab]
	end
	return true
end

---------------------------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------------------------

function Barracks.init()
	local canvas
	gui, canvas = Theme.screen("Barracks", 11)
	gui.Enabled = false
	root = Theme.new("TextButton", {
		Name = "Barracks",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = C.Backdrop,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = canvas,
	})
	content = Theme.new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })

	-- header
	local top: Frame = Theme.new("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 28),
		Size = UDim2.new(1, -96, 0, 96),
		Parent = content,
	})
	Theme.new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(8, 80), Parent = top })
	Theme.label({
		Text = "B A R R A C K S",
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(22, 6),
		Size = UDim2.new(0.6, 0, 0, 22),
		Parent = top,
	})
	Theme.label({
		Text = "SERVICE RECORD",
		Font = Theme.Fonts.Title,
		TextSize = 44,
		Position = UDim2.fromOffset(20, 28),
		Size = UDim2.new(1, -40, 0, 48),
		Parent = top,
	})
	subtitle = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(22, 76),
		Size = UDim2.new(1, -40, 0, 18),
		Parent = top,
	})

	-- tabs
	local tabRow: Frame = Theme.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 140),
		Size = UDim2.new(1, -96, 0, 48),
		Parent = content,
	}, { Theme.list(Enum.FillDirection.Horizontal, 10) })
	for i, t in TABS do
		local button = Theme.button({
			Name = t.id,
			Text = t.text,
			TextSize = 17,
			Size = UDim2.new(0.25, -8, 1, 0),
			LayoutOrder = i,
			Parent = tabRow,
		})
		tabButtons[t.id] = button
		button.Activated:Connect(function()
			if isOpenFlag then
				selectTab(t.id)
			end
		end)
	end

	body = Theme.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 204),
		Size = UDim2.new(1, -96, 1, -204 - 104),
		Parent = content,
	}, { Theme.list(Enum.FillDirection.Horizontal, 20) })

	-- footer
	local footer: Frame = Theme.new("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 48, 1, -28),
		Size = UDim2.new(1, -96, 0, 60),
		Parent = content,
	})
	Theme.label({
		Text = if Theme.isTouchOnly() then "" else "BACKSPACE / B TO GO BACK",
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, -200, 1, 0),
		Parent = footer,
	})
	local back = Theme.button({
		Name = "Back",
		Text = "BACK",
		TextSize = 18,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 180, 1, 0),
		Parent = footer,
	})
	back.Activated:Connect(Barracks.close)
	Theme.mount(gui)
end

function Barracks.start()
	while true do
		if isOpenFlag then
			local profile = ClientState.profile
			local label = resetLabel
			if label and profile then
				local text = resetText(profile)
				if label.Text ~= text then
					label.Text = text
				end
			end
			if armed and os.clock() - armedAt > ARM_TIMEOUT then
				armed = false
				render()
			end
		end
		task.wait(0.5)
	end
end

return Barracks
