--!strict
-- Lobby / pre-deploy screen: title, match info + phase timer, operators by team, next-match vote
-- (MatchState.options: map + mode cards),
-- loadout slots + editor (weapon picker grouped by class, unlock gating, weapon levels, Gunsmith
-- entry points for attachments), account rank + XP bar, DataStore-offline warning and the DEPLOY
-- button for late joiners / respawn fallback.
-- Phase 5: the editor has WEAPONS / PERKS / KILLSTREAKS tabs (perks: one per tier; killstreaks: up
-- to three, costs shown after Hardline), loadout rows list the perks, operator rows show titles and
-- prestige emblems, the rank badge shows the prestige emblem and a BARRACKS button opens UI/Barracks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Theme = require(script.Parent.Theme)
local Gunsmith = require(script.Parent.Gunsmith)
local Barracks = require(script.Parent.Barracks)
local Phase5Rules = require(script.Parent.Phase5Rules)
local ClientState = require(script.Parent.Parent.ClientState)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local WeaponsConfig = require(Shared.Config.Weapons)
local AttachmentsConfig = require(Shared.Config.Attachments)
local PerksConfig = require(Shared.Config.Perks)
local KillstreaksConfig = require(Shared.Config.Killstreaks)
local StreakRules = require(Shared.Pure.StreakRules)

local Lobby = {}

local C = Theme.Colors
local localPlayer = Players.LocalPlayer

type WeaponDef = WeaponsConfig.WeaponDef
type Selection = { [string]: string } -- attachment slot -> attachment id
type Draft = {
	primary: string,
	secondary: string,
	primaryAttachments: Selection,
	secondaryAttachments: Selection,
	perks: { string }, -- Phase 5: one per tier
	streaks: { string }, -- Phase 5: up to three
}
type ClassGroup = { class: string, defs: { WeaponDef } }

local CLASS_ORDER = { "AssaultRifle", "SMG", "LMG", "Marksman", "Sniper", "Shotgun", "Pistol", "MachinePistol" }
local CLASS_TITLES: { [string]: string } = {
	AssaultRifle = "ASSAULT RIFLES",
	SMG = "SUBMACHINE GUNS",
	LMG = "LIGHT MACHINE GUNS",
	Marksman = "MARKSMAN RIFLES",
	Sniper = "SNIPER RIFLES",
	Shotgun = "SHOTGUNS",
	Pistol = "PISTOLS",
	MachinePistol = "MACHINE PISTOLS",
}
local SAVE_TIMEOUT = 6 -- seconds without a matching ProfileSync before a save counts as failed

-- state
local gui: ScreenGui
local root: Frame
local mainFrame: Frame
local lastDeployed = false
local shown = false
local diedAt: number? = nil
local editIndex: number? = nil
local draft: Draft? = nil
local myVote: string? = nil
local savePending = false
local saveToken = 0
local editorTab = "Weapons" -- "Weapons" | "Perks" | "Streaks"
local PERK_TIERS = Phase5Rules.perkTiers(PerksConfig.list)
local TIER_TITLES = { "TIER 1  //  MOVEMENT & TEMPO", "TIER 2  //  WEAPON HANDLING", "TIER 3  //  SURVIVAL & INTEL" }

-- widgets
local rankNumber: TextLabel
local rankXpText: TextLabel
local rankFill: Frame
local prestigeLabel: TextLabel
local rankBadge: Frame
local rankEmblemHolder: Frame
local barracksButton: TextButton
local barracksSub: TextLabel
local tabButtons: { [string]: TextButton } = {}
local warningBanner: Frame
local modeLabel: TextLabel
local mapLabel: TextLabel
local phaseLabel: TextLabel
local timerLabel: TextLabel
local teamsHolder: Frame
local voteList: Frame
local voteButtons: { [string]: TextButton } = {} -- option id -> card
local voteEmpty: TextLabel
local voteKey = ""
local refreshVotes: () -> ()
local MAX_VOTE_CARDS = 3
local VOTE_CARD_HEIGHT = 58
local slotList: Frame
local editorTitle: TextLabel
local editorBody: ScrollingFrame
type SummaryRow = { name: TextLabel, attachments: TextLabel, button: TextButton }
local summaryRows: { [string]: SummaryRow } = {}
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

-- Defensive copy: older saves may lack attachment maps, or hold junk.
local function copySelection(t: any): Selection
	local out: Selection = {}
	if type(t) == "table" then
		for k, v in t do
			if type(k) == "string" and type(v) == "string" then
				out[k] = v
			end
		end
	end
	return out
end

local function sameSelection(a: Selection, b: Selection): boolean
	for k, v in a do
		if b[k] ~= v then
			return false
		end
	end
	for k, v in b do
		if a[k] ~= v then
			return false
		end
	end
	return true
end

local function countSelection(t: any): number
	local n = 0
	if type(t) == "table" then
		for _, v in t do
			if type(v) == "string" then
				n += 1
			end
		end
	end
	return n
end

-- Defensive copy of a string list (older payloads may lack perks / streaks).
local function copyList(t: any): { string }
	local out: { string } = {}
	if type(t) == "table" then
		for _, v in t do
			if type(v) == "string" then
				table.insert(out, v)
			end
		end
	end
	return out
end

local function sameList(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	for i, v in a do
		if b[i] ~= v then
			return false
		end
	end
	return true
end

local function loadoutPerks(lo: Types.Loadout): { string }
	local perks = copyList((lo :: any).perks)
	return if #perks == 3 then perks else table.clone(PerksConfig.Defaults)
end

local function loadoutStreaks(lo: Types.Loadout): { string }
	local raw = (lo :: any).streaks
	return if type(raw) == "table" then copyList(raw) else table.clone(KillstreaksConfig.Defaults)
end

local function draftFrom(lo: Types.Loadout): Draft
	return {
		primary = lo.primary,
		secondary = lo.secondary,
		primaryAttachments = copySelection(lo.primaryAttachments),
		secondaryAttachments = copySelection(lo.secondaryAttachments),
		perks = loadoutPerks(lo),
		streaks = loadoutStreaks(lo),
	}
end

local function matchesLoadout(d: Draft, lo: Types.Loadout): boolean
	return d.primary == lo.primary
		and d.secondary == lo.secondary
		and sameSelection(d.primaryAttachments, copySelection(lo.primaryAttachments))
		and sameSelection(d.secondaryAttachments, copySelection(lo.secondaryAttachments))
		and sameList(d.perks, loadoutPerks(lo))
		and sameList(d.streaks, loadoutStreaks(lo))
end

local function perkName(id: string): string
	local def = PerksConfig.byId[id]
	return if def then def.name else id
end

local function streakName(id: string): string
	local def = KillstreaksConfig.byId[id]
	return if def then def.name else id
end

-- " +3" when attachments are equipped, "" otherwise.
local function attachmentSuffix(t: any): string
	local n = countSelection(t)
	return if n > 0 then " +" .. tostring(n) else ""
end

local groupCache: { [string]: { ClassGroup } } = {}

-- Weapons of one loadout slot grouped by class (fixed class order, unknown classes last), each
-- group sorted by unlockLevel then name. Config is static, so this is computed once per slot.
local function groupedWeapons(slot: string): { ClassGroup }
	local cached = groupCache[slot]
	if cached then
		return cached
	end
	local byClass: { [string]: { WeaponDef } } = {}
	for _, def in WeaponsConfig do
		if def.slot == slot then
			local list = byClass[def.class]
			if not list then
				list = {}
				byClass[def.class] = list
			end
			table.insert(list, def)
		end
	end
	local classes: { string } = {}
	for class in byClass do
		table.insert(classes, class)
	end
	table.sort(classes, function(a, b)
		local ia, ib = table.find(CLASS_ORDER, a) or math.huge, table.find(CLASS_ORDER, b) or math.huge
		if ia ~= ib then
			return ia < ib
		end
		return a < b
	end)
	local groups: { ClassGroup } = {}
	for _, class in classes do
		local defs = byClass[class]
		table.sort(defs, function(a, b)
			if a.unlockLevel ~= b.unlockLevel then
				return a.unlockLevel < b.unlockLevel
			end
			return a.displayName < b.displayName
		end)
		table.insert(groups, { class = class, defs = defs })
	end
	groupCache[slot] = groups
	return groups
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
		rankEmblemHolder.Visible = false
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
	prestigeLabel.Text = if acc.prestige and acc.prestige > 0 then "PRESTIGE " .. Phase5Rules.roman(acc.prestige) .. "  ·  RANK" else "OPERATOR RANK"
	-- Phase 5: the prestige emblem sits on the rank badge once the player has prestiged
	for _, child in rankEmblemHolder:GetChildren() do
		child:Destroy()
	end
	local emblemId = Phase5Rules.prestigeEmblem(acc.prestige, #Theme.Cosmetics.emblems)
	local emblem = Theme.emblemBadge(emblemId, 26, { Parent = rankEmblemHolder })
	rankEmblemHolder.Visible = emblem ~= nil
	rankBadge.BackgroundColor3 = C.Accent
	warningBanner.Visible = profile.temporary == true
	-- Barracks button: today's challenge progress
	local done, total = 0, 0
	local ch = (profile :: any).challenges
	if type(ch) == "table" and type(ch.list) == "table" then
		for _, c in ch.list do
			total += 1
			if c.done then
				done += 1
			end
		end
	end
	barracksSub.Text = if total > 0 then string.format("DAILIES %d/%d", done, total) else "CHALLENGES · CAREER"
	if (profile :: any).canPrestige == true then
		barracksSub.Text = "PRESTIGE AVAILABLE"
	end
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
	return draft ~= nil and lo ~= nil and not matchesLoadout(draft, lo)
end

local function setSaveStatus(text: string, color: Color3)
	saveStatus.Text = text
	saveStatus.TextColor3 = color
end

local function refreshSave()
	local dirty = isDirty()
	local canSave = dirty and not savePending
	saveButton.Active = canSave
	saveButton.AutoButtonColor = false
	Theme.setButtonColor(saveButton, if canSave then C.Accent else C.Locked)
	saveButton.TextColor3 = if canSave then C.OnAccent else C.TextMuted
	if savePending then
		setSaveStatus("SAVING...", C.TextDim)
	elseif dirty then
		if saveStatus.Text == "" or saveStatus.Text == "SAVED" then
			setSaveStatus("UNSAVED CHANGES", C.Accent)
		end
	elseif saveStatus.Text == "UNSAVED CHANGES" or saveStatus.Text == "SAVING..." then
		setSaveStatus("", C.TextDim)
	end
end

-- Sends the draft. The server validates everything and answers with ProfileSync (success) or a
-- Notify warning (rejected); a silent drop (rate limit) shows as failed after SAVE_TIMEOUT.
local function saveDraft()
	local d = draft
	local index = editIndex
	if not d or not index or not isDirty() or savePending then
		return
	end
	fire("SetLoadout", index, {
		primary = d.primary,
		secondary = d.secondary,
		primaryAttachments = copySelection(d.primaryAttachments),
		secondaryAttachments = copySelection(d.secondaryAttachments),
		perks = table.clone(d.perks),
		streaks = table.clone(d.streaks),
	})
	savePending = true
	saveToken += 1
	local token = saveToken
	refreshSave()
	task.delay(SAVE_TIMEOUT, function()
		if savePending and saveToken == token then
			savePending = false
			setSaveStatus("SAVE FAILED - TRY AGAIN", C.Danger)
			refreshSave()
		end
	end)
end

local function cancelPendingSave()
	savePending = false
	saveToken += 1
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
			Size = UDim2.new(1, 0, 0, 90),
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
			Text = Theme.weaponName(lo.primary)
				.. attachmentSuffix(lo.primaryAttachments)
				.. "  /  "
				.. Theme.weaponName(lo.secondary)
				.. attachmentSuffix(lo.secondaryAttachments),
			Font = Theme.Fonts.Regular,
			TextSize = 14,
			TextColor3 = C.TextDim,
			Position = UDim2.fromOffset(18, 38),
			Size = UDim2.new(1, -30, 0, 20),
			Parent = button,
		})
		-- Phase 5: perks at a glance
		local perkNames = {}
		for _, id in loadoutPerks(lo) do
			table.insert(perkNames, perkName(id))
		end
		Theme.label({
			Text = string.upper(table.concat(perkNames, " · ")),
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(18, 62),
			Size = UDim2.new(1, -30, 0, 16),
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
				draft = draftFrom(lo)
				cancelPendingSave()
				setSaveStatus("", C.TextDim)
				Gunsmith.close()
			end
			if profile.selectedLoadout ~= i then
				fire("SelectLoadout", i)
			end
			rebuildSlots()
			rebuildEditor()
		end)
	end
end

-- Draft weapon + attachments rows above the picker (cheap: no card rebuild).
local function refreshSummary()
	for _, slot in { "Primary", "Secondary" } do
		local row = summaryRows[slot]
		if row then
			local id = if draft then (if slot == "Primary" then draft.primary else draft.secondary) else nil
			local sel = if draft then (if slot == "Primary" then draft.primaryAttachments else draft.secondaryAttachments) else nil
			local def = if id then WeaponsConfig[id] else nil
			row.name.Text = if id then string.upper(Theme.weaponName(id)) .. attachmentSuffix(sel) else "-"
			local names = {}
			if def and sel then
				for _, attSlot in def.attachmentSlots do
					local att = AttachmentsConfig[sel[attSlot]]
					if att then
						table.insert(names, att.displayName)
					end
				end
			end
			row.attachments.Text = if #names > 0 then table.concat(names, "  ·  ") else "NO ATTACHMENTS EQUIPPED"
			local usable = def ~= nil and #def.attachmentSlots > 0 and ClientState.profile ~= nil
			row.button.Active = usable
			row.button.Text = if def ~= nil and #def.attachmentSlots == 0 then "NO SLOTS" else "GUNSMITH"
			row.button.TextColor3 = if usable then C.Text else C.TextMuted
			row.button.BackgroundTransparency = if usable then 0.1 else 0.5
		end
	end
end

local function openGunsmith(slot: string)
	local d = draft
	local index = editIndex
	if not d or not index then
		return
	end
	local weaponId = if slot == "Primary" then d.primary else d.secondary
	local current = if slot == "Primary" then d.primaryAttachments else d.secondaryAttachments
	local opened = Gunsmith.open(weaponId, current, function(selection: Selection)
		-- DONE: apply to the draft (only if it still edits the same loadout + weapon) and save.
		if not draft and shown then
			rebuildEditor()
		end
		local now = draft
		if not now or editIndex ~= index then
			return
		end
		if slot == "Primary" and now.primary == weaponId then
			now.primaryAttachments = copySelection(selection)
		elseif slot == "Secondary" and now.secondary == weaponId then
			now.secondaryAttachments = copySelection(selection)
		else
			return
		end
		refreshSummary()
		refreshSave()
		saveDraft()
	end, function()
		mainFrame.Visible = true
	end)
	if opened then
		mainFrame.Visible = false
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
		local d = draft
		if not unlocked or not d then
			return
		end
		local lo = currentLoadout()
		-- Changing a weapon clears its attachments; picking the saved weapon again restores them.
		if slot == "Primary" then
			if d.primary == def.id then
				return
			end
			d.primary = def.id
			d.primaryAttachments = if lo and lo.primary == def.id then copySelection(lo.primaryAttachments) else {}
		else
			if d.secondary == def.id then
				return
			end
			d.secondary = def.id
			d.secondaryAttachments = if lo and lo.secondary == def.id then copySelection(lo.secondaryAttachments) else {}
		end
		rebuildEditor()
	end)
end

local function pickerSection(profile: Types.ProfileSummary, slot: string, title: string, order: number): number
	Theme.label({
		Text = title,
		Font = Theme.Fonts.Title,
		TextSize = 16,
		TextColor3 = C.Text,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = order,
		Parent = editorBody,
	})
	order += 1
	for _, group in groupedWeapons(slot) do
		Theme.label({
			Text = string.format("%s  <font color=\"%s\">%d</font>", CLASS_TITLES[group.class] or string.upper(group.class), Theme.hex(C.TextMuted), #group.defs),
			RichText = true,
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			TextColor3 = C.Accent,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = order,
			Parent = editorBody,
		})
		local grid: Frame = Theme.new("Frame", {
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
		for i, def in group.defs do
			weaponCard(profile, def, slot, i, grid)
		end
		order += 2
	end
	return order
end

---------------------------------------------------------------------------------------------
-- Phase 5: perks + killstreaks
---------------------------------------------------------------------------------------------

local function hasId(list: any, id: string): boolean
	return type(list) == "table" and table.find(list, id) ~= nil
end

local function perkCard(profile: Types.ProfileSummary, def: PerksConfig.PerkDef, order: number, parent: Instance)
	local d = draft :: Draft
	local unlocked = hasId(profile.unlockedPerks, def.id)
	local selected = d.perks[def.tier] == def.id
	local card = Theme.button({ Name = def.id, LayoutOrder = order, Parent = parent })
	Theme.setButtonColor(card, if selected then C.PanelHover elseif unlocked then C.PanelLight else C.Locked)
	card.BackgroundTransparency = if unlocked then 0.1 else 0.45
	if selected then
		Theme.stroke(C.Accent, 2, 0).Parent = card
	end
	Theme.label({
		Text = string.upper(def.name),
		Font = Theme.Fonts.Bold,
		TextSize = 17,
		TextColor3 = if unlocked then C.Text else C.TextMuted,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -110, 0, 22),
		Parent = card,
	})
	Theme.label({
		Text = if selected then "EQUIPPED" elseif unlocked then "" else "LOCKED",
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = if selected then C.Accent else C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(90, 18),
		Parent = card,
	})
	Theme.label({
		Text = def.description,
		Font = Theme.Fonts.Regular,
		TextSize = 13,
		TextColor3 = if unlocked then C.TextDim else C.TextMuted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(14, 32),
		Size = UDim2.new(1, -28, 0, 34),
		Parent = card,
	})
	if not unlocked then
		Theme.label({
			Text = "UNLOCKS AT LEVEL " .. tostring(def.unlockLevel),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			TextColor3 = C.TextDim,
			Position = UDim2.fromOffset(14, 68),
			Size = UDim2.new(1, -28, 0, 16),
			Parent = card,
		})
	end
	card.Activated:Connect(function()
		local now = draft
		if not unlocked or not now or now.perks[def.tier] == def.id then
			return
		end
		now.perks[def.tier] = def.id
		rebuildEditor()
	end)
end

local function perksSection(profile: Types.ProfileSummary)
	local order = 1
	for tier, defs in PERK_TIERS do
		sectionTitle(TIER_TITLES[tier] or ("TIER " .. tier), editorBody, order)
		local grid: Frame = Theme.new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -6, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order + 1,
			Parent = editorBody,
		}, {
			Theme.new("UIGridLayout", {
				CellSize = UDim2.new(0.5, -6, 0, 92),
				CellPadding = UDim2.fromOffset(10, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for i, def in defs do
			perkCard(profile, def, i, grid)
		end
		order += 2
	end
end

local function draftDiscount(): number
	return if draft then Phase5Rules.streakDiscount(draft.perks, PerksConfig.byId) else 0
end

local function streakCard(profile: Types.ProfileSummary, def: KillstreaksConfig.StreakDef, order: number, parent: Instance)
	local d = draft :: Draft
	local unlocked = hasId(profile.unlockedStreaks, def.id)
	local slot = table.find(d.streaks, def.id)
	local selected = slot ~= nil
	local discount = draftDiscount()
	local cost = StreakRules.cost(def.id, discount)
	local card = Theme.button({ Name = def.id, LayoutOrder = order, Parent = parent })
	Theme.setButtonColor(card, if selected then C.PanelHover elseif unlocked then C.PanelLight else C.Locked)
	card.BackgroundTransparency = if unlocked then 0.1 else 0.45
	if selected then
		Theme.stroke(C.Accent, 2, 0).Parent = card
	end
	-- kill cost chip (Hardline: reduced cost in accent with the base cost struck through)
	local costText = tostring(cost)
	if cost ~= def.kills then
		costText = string.format('%d <font size="12" color="%s"><s>%d</s></font>', cost, Theme.hex(C.TextMuted), def.kills)
	end
	local chip: Frame = Theme.new("Frame", {
		BackgroundColor3 = if selected then C.Accent else C.Panel,
		BackgroundTransparency = if selected then 0 else 0.2,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 10),
		Size = UDim2.fromOffset(54, 54),
		Parent = card,
	}, { Theme.corner(6) })
	Theme.label({
		Text = costText,
		RichText = true,
		Font = Theme.Fonts.Title,
		TextSize = 24,
		TextColor3 = if selected then C.OnAccent elseif cost ~= def.kills then C.Accent else C.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 36),
		Parent = chip,
	})
	Theme.label({
		Text = "KILLS",
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		TextColor3 = if selected then C.OnAccent else C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = chip,
	})
	Theme.label({
		Text = string.upper(def.name),
		Font = Theme.Fonts.Bold,
		TextSize = 17,
		TextColor3 = if unlocked then C.Text else C.TextMuted,
		Position = UDim2.fromOffset(76, 8),
		Size = UDim2.new(1, -170, 0, 22),
		Parent = card,
	})
	Theme.label({
		Text = if selected then string.format("KEY %d", 4 + (slot :: number)) elseif unlocked then "" else "UNLOCKS AT LEVEL " .. tostring(def.unlockLevel),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = if selected then C.Accent else C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 10),
		Size = UDim2.fromOffset(160, 18),
		Parent = card,
	})
	Theme.label({
		Text = def.description,
		Font = Theme.Fonts.Regular,
		TextSize = 13,
		TextColor3 = if unlocked then C.TextDim else C.TextMuted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(76, 32),
		Size = UDim2.new(1, -90, 0, 34),
		Parent = card,
	})
	card.Activated:Connect(function()
		local now = draft
		if not unlocked or not now then
			return
		end
		local disc = draftDiscount()
		local list, changed = Phase5Rules.toggleStreak(now.streaks, def.id, KillstreaksConfig.MaxEquipped, function(id: string): number
			return StreakRules.cost(id, disc)
		end)
		if not changed then
			setSaveStatus(string.format("UP TO %d KILLSTREAKS - REMOVE ONE FIRST", KillstreaksConfig.MaxEquipped), C.Danger)
			return
		end
		now.streaks = list
		rebuildEditor()
	end)
end

local function streaksSection(profile: Types.ProfileSummary)
	local d = draft :: Draft
	local discount = draftDiscount()
	local names = {}
	for _, id in d.streaks do
		table.insert(names, string.format("%s (%d)", string.upper(streakName(id)), StreakRules.cost(id, discount)))
	end
	sectionTitle(string.format("KILLSTREAKS  //  %d / %d EQUIPPED", #d.streaks, KillstreaksConfig.MaxEquipped), editorBody, 1)
	Theme.label({
		Text = (if #names > 0 then table.concat(names, "  ·  ") else "NONE EQUIPPED")
			.. (if discount > 0 then string.format("   —   HARDLINE: -%d KILL", discount) else ""),
		Font = Theme.Fonts.Medium,
		TextSize = 13,
		TextColor3 = C.TextDim,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		Parent = editorBody,
	})
	Theme.label({
		Text = "Kills in one life earn them. Use with keys 5 / 6 / 7, D-pad up, or tap the tray.",
		Font = Theme.Fonts.Regular,
		TextSize = 12,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 3,
		Parent = editorBody,
	})
	local list: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -6, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Parent = editorBody,
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.new(1, 0, 0, 76),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	for i, def in KillstreaksConfig.list do
		streakCard(profile, def, i, list)
	end
end

local function refreshTabs()
	for name, button in tabButtons do
		local on = name == editorTab
		Theme.setButtonColor(button, if on then C.Accent else C.PanelLight)
		button.TextColor3 = if on then C.OnAccent else C.TextDim
	end
end

rebuildEditor = function()
	local scroll = editorBody.CanvasPosition
	clearChildren(editorBody)
	local profile = ClientState.profile
	if not profile then
		editorTitle.Text = "LOADING PROFILE..."
		refreshSummary()
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
		draft = nil
		refreshSummary()
		refreshSave()
		return
	end
	if not draft then
		draft = draftFrom(lo)
	end
	editorTitle.Text = "EDIT  //  " .. string.upper(lo.name ~= "" and lo.name or ("Loadout " .. tostring(editIndex)))
	refreshTabs()
	if editorTab == "Perks" then
		perksSection(profile)
	elseif editorTab == "Streaks" then
		streaksSection(profile)
	else
		local order = pickerSection(profile, "Primary", "PRIMARY", 1)
		pickerSection(profile, "Secondary", "SECONDARY", order + 1)
	end
	editorBody.CanvasPosition = scroll
	refreshSummary()
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
		-- Phase 5: prestige emblem + equipped title (small caps after the name)
		local emblem = Theme.emblemBadge(Phase5Rules.lineEmblem(line), 20, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Parent = rowFrame,
		})
		local nameX = if emblem then 32 else 10
		Theme.label({
			Text = Theme.nameWithTitle(line.name, line.title, 10),
			RichText = true,
			Font = if isMe then Theme.Fonts.Bold else Theme.Fonts.Medium,
			TextSize = 15,
			TextColor3 = if isMe then C.Accent else C.Text,
			Position = UDim2.fromOffset(nameX, 0),
			Size = UDim2.new(1, -70 - nameX + 10, 1, 0),
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

-- Vote options for the next match. Falls back to "map only" options built from the config map
-- list when an older server sends no `options`.
local function voteOptions(ms: Types.MatchStatePayload?): { Types.VoteOption }
	if not ms then
		return {}
	end
	if type(ms.options) == "table" then
		return ms.options
	end
	local list: { Types.VoteOption } = {}
	if ms.phase == "Lobby" then
		for _, mapId in Theme.Match.Maps do
			table.insert(list, { id = mapId, mapId = mapId, mapName = Theme.mapDisplayName(mapId), modeId = "", modeName = "" })
		end
	end
	return list
end

local function voteCard(option: Types.VoteOption, order: number): TextButton
	local button = Theme.button({ Name = "Vote_" .. option.id, Size = UDim2.new(1, 0, 0, VOTE_CARD_HEIGHT), LayoutOrder = order, Parent = voteList })
	local stroke = Theme.stroke(C.Accent, 2, 1)
	stroke.Name = "VoteStroke"
	stroke.Parent = button
	Theme.new("Frame", {
		Name = "Marker",
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 4, 1, -16),
		Position = UDim2.fromOffset(0, 8),
		Visible = false,
		Parent = button,
	})
	Theme.label({
		Text = string.upper(if (option.mapName or "") ~= "" then option.mapName else Theme.mapDisplayName(option.mapId or "")),
		Font = Theme.Fonts.Bold,
		TextSize = 17,
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -130, 0, 22),
		Parent = button,
	})
	Theme.label({
		Text = string.upper(option.modeName or ""),
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(14, 32),
		Size = UDim2.new(1, -130, 0, 18),
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
	local optionId = option.id
	button.Activated:Connect(function()
		local ms = ClientState.matchState
		if not ms or ms.phase ~= "Lobby" then
			return
		end
		myVote = optionId
		fire("VoteMap", optionId)
		refreshVotes()
	end)
	return button
end

function refreshVotes()
	local ms = ClientState.matchState
	local canVote = ms ~= nil and ms.phase == "Lobby"
	local options = voteOptions(ms)
	-- rebuild the cards only when the offered set changes
	local key = ""
	for i, option in options do
		if i > MAX_VOTE_CARDS then
			break
		end
		key ..= tostring(option.id) .. "|" .. tostring(option.mapName) .. "|" .. tostring(option.modeName) .. ";"
	end
	if key ~= voteKey then
		voteKey = key
		for _, button in voteButtons do
			button:Destroy()
		end
		table.clear(voteButtons)
		for i, option in options do
			if i > MAX_VOTE_CARDS then
				break
			end
			voteButtons[option.id] = voteCard(option, i)
		end
	end
	if myVote and not voteButtons[myVote] then
		myVote = nil -- a new set of options was offered
	end
	voteEmpty.Visible = next(voteButtons) == nil
	for optionId, button in voteButtons do
		local count = if ms and ms.votes then (ms.votes[optionId] or 0) else 0
		local countLabel = button:FindFirstChild("Count") :: TextLabel?
		if countLabel then
			countLabel.Text = tostring(count) .. (if count == 1 then " VOTE" else " VOTES")
		end
		local mine = myVote == optionId
		Theme.setButtonColor(button, if mine then C.PanelHover else C.PanelLight)
		local stroke = button:FindFirstChild("VoteStroke") :: UIStroke?
		if stroke then
			stroke.Transparency = if mine then 0 else 1
		end
		local marker = button:FindFirstChild("Marker") :: Frame?
		if marker then
			marker.Visible = mine
		end
		button.Active = canVote
		button.BackgroundTransparency = if canVote then 0.1 else 0.5
	end
end

-- The option the server would play right now: most votes, ties to the first listed.
local function leadingOption(ms: Types.MatchStatePayload): Types.VoteOption?
	local best: Types.VoteOption? = nil
	local bestVotes = -1
	for _, option in voteOptions(ms) do
		local n = if ms.votes then ms.votes[option.id] or 0 else 0
		if n > bestVotes then
			best, bestVotes = option, n
		end
	end
	return best
end

local function refreshMatchInfo()
	local ms = ClientState.matchState
	if not ms then
		modeLabel.Text = "CONNECTING..."
		mapLabel.Text = ""
		return
	end
	-- In the lobby show the pairing currently winning the vote (that is the mode that will be
	-- played); afterwards the chosen mode + map from the match state.
	local leader = if ms.phase == "Lobby" then leadingOption(ms) else nil
	if leader and (leader.modeName or "") ~= "" then
		modeLabel.Text = "NEXT  ·  " .. string.upper(leader.modeName)
		mapLabel.Text = string.upper(if (leader.mapName or "") ~= "" then leader.mapName else Theme.mapDisplayName(leader.mapId or ""))
	else
		modeLabel.Text = string.upper(ms.modeName)
		mapLabel.Text = string.upper(ms.mapName)
	end
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
			-- [Phase 4] S&D has no respawns: a dead participant spectates (UI/Objectives) until
			-- the next round respawns them, so the lobby must not take over.
			if Theme.isSnD() and table.find(ms.inMatch or {}, localPlayer.UserId) then
				return false
			end
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
		Gunsmith.close() -- e.g. the match deploys while the Gunsmith is open
		Barracks.close()
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
	rankBadge = badge
	-- Phase 5: prestige emblem pinned to the badge's corner (filled by refreshRank)
	rankEmblemHolder = Theme.new("Frame", {
		Name = "PrestigeEmblem",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(62, 62),
		Size = UDim2.fromOffset(26, 26),
		ZIndex = 3,
		Visible = false,
		Parent = rank,
	})
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

	-- Phase 5: BARRACKS (challenges, career, titles & emblems, prestige)
	barracksButton = Theme.button({
		Name = "Barracks",
		Text = "",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -396, 0, 6),
		Size = UDim2.fromOffset(220, 76),
		Parent = top,
	})
	Theme.stroke(C.Accent, 1, 0.35).Parent = barracksButton
	Theme.label({
		Text = "BARRACKS",
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = barracksButton,
	})
	barracksSub = Theme.label({
		Text = "CHALLENGES · CAREER",
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = barracksButton,
	})
	barracksButton.Activated:Connect(function()
		if Gunsmith.isOpen() or Barracks.isOpen() then
			return
		end
		local opened = Barracks.open(nil, function()
			if shown then
				mainFrame.Visible = true
			end
		end)
		if opened then
			mainFrame.Visible = false
		end
	end)
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

	-- draft summary: weapon + equipped attachments + GUNSMITH entry, one row per weapon slot
	local SUMMARY_ROW = 58
	for i, slot in { "Primary", "Secondary" } do
		local row: Frame = Theme.new("Frame", {
			Name = slot .. "Summary",
			BackgroundColor3 = C.PanelLight,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 30 + (i - 1) * (SUMMARY_ROW + 6)),
			Size = UDim2.new(1, 0, 0, SUMMARY_ROW),
			Parent = editor,
		}, { Theme.corner(6) })
		Theme.label({
			Text = string.upper(slot),
			Font = Theme.Fonts.Bold,
			TextSize = 11,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(12, 6),
			Size = UDim2.fromOffset(120, 14),
			Parent = row,
		})
		local name = Theme.label({
			Font = Theme.Fonts.Bold,
			TextSize = 17,
			Position = UDim2.fromOffset(12, 18),
			Size = UDim2.new(1, -190, 0, 20),
			Parent = row,
		})
		local attachments = Theme.label({
			Font = Theme.Fonts.Regular,
			TextSize = 12,
			TextColor3 = C.TextDim,
			Position = UDim2.fromOffset(12, 38),
			Size = UDim2.new(1, -190, 0, 14),
			Parent = row,
		})
		local button = Theme.button({
			Name = "Gunsmith",
			Text = "GUNSMITH",
			TextSize = 16,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -7, 0.5, 0),
			Size = UDim2.fromOffset(160, 46),
			Parent = row,
		})
		Theme.stroke(C.Accent, 1, 0.35).Parent = button
		button.Activated:Connect(function()
			if button.Active then
				openGunsmith(slot)
			end
		end)
		summaryRows[slot] = { name = name, attachments = attachments, button = button }
	end
	local tabsTop = 30 + 2 * (SUMMARY_ROW + 6) + 2
	local tabRow: Frame = Theme.new("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, tabsTop),
		Size = UDim2.new(1, 0, 0, 38),
		Parent = editor,
	}, { Theme.list(Enum.FillDirection.Horizontal, 8) })
	for i, spec in { { id = "Weapons", text = "WEAPONS" }, { id = "Perks", text = "PERKS" }, { id = "Streaks", text = "KILLSTREAKS" } } do
		local tab = Theme.button({
			Name = spec.id,
			Text = spec.text,
			TextSize = 15,
			Size = UDim2.new(1 / 3, -6, 1, 0),
			LayoutOrder = i,
			Parent = tabRow,
		})
		tabButtons[spec.id] = tab
		tab.Activated:Connect(function()
			if editorTab ~= spec.id then
				editorTab = spec.id
				editorBody.CanvasPosition = Vector2.zero
				rebuildEditor()
			end
		end)
	end
	local bodyTop = tabsTop + 38 + 8

	editorBody = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, bodyTop),
		Size = UDim2.new(1, 0, 1, -bodyTop - 62),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = editor,
	}, { Theme.list(Enum.FillDirection.Vertical, 8) })

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
	saveButton.Activated:Connect(saveDraft)
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

	-- next-match vote (bottom): MatchState.options map + mode cards, rebuilt by refreshVotes()
	local voteHeight = 44 + MAX_VOTE_CARDS * (VOTE_CARD_HEIGHT + 6)
	local votePanel = Theme.panel({
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, voteHeight),
		Parent = col,
	})
	Theme.padding(12, 14).Parent = votePanel
	sectionTitle("NEXT MATCH VOTE", votePanel)
	voteList = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 1, -28),
		Parent = votePanel,
	}, { Theme.list(Enum.FillDirection.Vertical, 6) })
	voteEmpty = Theme.label({
		Text = "VOTING OPENS IN THE LOBBY",
		Font = Theme.Fonts.Medium,
		TextSize = 15,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, VOTE_CARD_HEIGHT),
		LayoutOrder = 0,
		Parent = voteList,
	})

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
		if lo and draft and savePending and matchesLoadout(draft, lo) then
			cancelPendingSave()
			setSaveStatus("SAVED", C.Positive)
		end
		if not isDirty() then
			draft = nil -- re-sync draft from the authoritative profile
		end
		if shown then
			rebuildSlots()
			rebuildEditor()
		end
	end)
	ClientState.Notify:Connect(function(text: string, kind: string)
		-- server rejections of SetLoadout arrive as warnings ("Invalid loadout", "...still locked", ...)
		if not savePending or kind ~= "Warning" or type(text) ~= "string" then
			return
		end
		local lower = string.lower(text)
		if
			string.find(lower, "loadout", 1, true)
			or string.find(lower, "attachment", 1, true)
			or string.find(lower, "locked", 1, true)
			or string.find(lower, "perk", 1, true)
			or string.find(lower, "killstreak", 1, true)
		then
			cancelPendingSave()
			setSaveStatus("NOT SAVED: " .. string.upper(text), C.Danger)
			refreshSave()
		end
	end)
	ClientState.MatchStateChanged:Connect(function(ms)
		if ms.phase == "Lobby" or ms.phase == "Results" then
			diedAt = nil
		end
		if ms.phase == "Lobby" and ms.votes and myVote and (ms.votes[myVote] or 0) == 0 then
			myVote = nil -- votes were reset for a new lobby
		end
		if ms.phase ~= "Lobby" then
			myVote = nil
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
