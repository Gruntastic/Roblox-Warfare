--!strict
-- Gunsmith: full-screen attachment editor for one weapon of the Lobby's draft loadout.
--
-- Public API (the Lobby is the only caller):
--   Gunsmith.open(weaponId, selection, onDone, onClosed?) -> boolean
--       Opens the editor on a copy of `selection` (attachment slot -> attachment id). The copy is
--       sanitized the same way the server does on load (unknown / locked / wrong-slot ids dropped).
--       DONE calls `onDone(newSelection)` and closes; BACK / Backspace / gamepad B / auto-close only close
--       (Escape is not bound: it opens the Roblox menu).
--       `onClosed` runs on every close (DONE included). Returns false if the weapon id is unknown.
--   Gunsmith.preview(weaponId, onClosed?) -> boolean
--       Opens the same screen as a look-only preview for any weapon, locked ones included: the 3D
--       view, stats and camos work, attachments can be tried on, nothing is saved (no DONE).
--   Gunsmith.close()       closes without applying (no-op when closed).
--   Gunsmith.isOpen() -> boolean
--   Gunsmith.prosCons(attachmentDef) -> { { text: string, positive: boolean } }
--
-- It never opens by itself: init() only builds the (disabled) ScreenGui. It closes automatically
-- when the local player deploys or the match moves to Results. Client-side checks are UX only;
-- the server re-validates every SetLoadout (WeaponStats.validate).
--
-- Phase 5: a CAMO strip under the preview lists every camo for the weapon. Owned ones equip at once
-- with EquipCosmetic("Camo", camoId, weaponId) (independent of DONE / BACK: camos are cosmetics,
-- not loadout data); locked ones show their requirement and progress and can be previewed.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponsConfig = require(Shared.Config.Weapons)
local AttachmentsConfig = require(Shared.Config.Attachments)
local WeaponStats = require(Shared.Pure.WeaponStats)
local WeaponModel = require(Shared.WeaponModel)
local Net = require(Shared.Net)
local CosmeticsConfig = require(Shared.Config.Cosmetics)
local Phase5Rules = require(script.Parent.Phase5Rules)

type WeaponDef = WeaponsConfig.WeaponDef
type AttachmentDef = AttachmentsConfig.AttachmentDef
export type Selection = { [string]: string }
export type ProCon = { text: string, positive: boolean }

local Gunsmith = {}

local C = Theme.Colors
local BACK_ACTION = "COR_GunsmithBack"
local PREVIEW_FOV = 30
local PREVIEW_PITCH = -0.18 -- radians; camera slightly above the weapon
local AUTO_SPIN = 0.25 -- radians per second while idle
local DRAG_SPEED = 0.012 -- radians per screen pixel
local DRAG_IDLE = 2.5 -- seconds after a drag before the auto spin resumes
local SIDE_YAW = math.rad(90) -- camera on the weapon's right side, muzzle pointing left
local ZOOM_MIN, ZOOM_MAX = 0.55, 1.6 -- scroll zoom, as a fraction of the fit distance

local SLOT_TITLES: { [string]: string } = {
	Optic = "OPTIC",
	Muzzle = "MUZZLE",
	Barrel = "BARREL",
	Underbarrel = "UNDERBARREL",
	Magazine = "MAGAZINE",
}

-- kind "more": >1 is a gain ("+25% Range"). "time": a duration multiplier, >1 is a loss shown as a
-- speed ("-8% ADS speed"). "less": <1 is a gain ("-15% Vertical recoil").
local MODIFIER_SPECS: { { key: string, label: string, kind: string } } = {
	{ key = "damage", label = "Damage", kind = "more" },
	{ key = "range", label = "Range", kind = "more" },
	{ key = "rpm", label = "Fire rate", kind = "more" },
	{ key = "magSize", label = "Mag size", kind = "more" },
	{ key = "reload", label = "Reload speed", kind = "time" },
	{ key = "adsTime", label = "ADS speed", kind = "time" },
	{ key = "equipTime", label = "Draw speed", kind = "time" },
	{ key = "moveSpeed", label = "Move speed", kind = "more" },
	{ key = "adsMoveSpeed", label = "ADS move speed", kind = "more" },
	{ key = "hipSpread", label = "Hip-fire spread", kind = "less" },
	{ key = "adsSpread", label = "ADS spread", kind = "less" },
	{ key = "recoilVertical", label = "Vertical recoil", kind = "less" },
	{ key = "recoilHorizontal", label = "Horizontal recoil", kind = "less" },
}

local STAT_SPECS: { { key: string, label: string } } = {
	{ key = "damage", label = "DAMAGE" },
	{ key = "range", label = "RANGE" },
	{ key = "fireRate", label = "FIRE RATE" },
	{ key = "accuracy", label = "ACCURACY" },
	{ key = "mobility", label = "MOBILITY" },
	{ key = "control", label = "CONTROL" },
}

type NumberSpec = { label: string, get: (WeaponStats.Effective) -> number, fmt: (number) -> string, higherBetter: boolean }
local NUMBER_SPECS: { NumberSpec } = {
	{
		label = "MAG SIZE",
		get = function(e)
			return e.magSize
		end,
		fmt = function(v)
			return tostring(math.floor(v + 0.5))
		end,
		higherBetter = true,
	},
	{
		label = "FIRE RATE",
		get = function(e)
			return e.rpm
		end,
		fmt = function(v)
			return string.format("%d RPM", math.floor(v + 0.5))
		end,
		higherBetter = true,
	},
	{
		label = "RELOAD",
		get = function(e)
			return e.reloadTime
		end,
		fmt = function(v)
			return string.format("%.2fs", v)
		end,
		higherBetter = false,
	},
	{
		label = "ADS TIME",
		get = function(e)
			return e.adsTime * 1000
		end,
		fmt = function(v)
			return string.format("%d ms", math.floor(v + 0.5))
		end,
		higherBetter = false,
	},
	{
		label = "DAMAGE RANGE",
		get = function(e)
			return e.damage.farRange
		end,
		fmt = function(v)
			return string.format("%d studs", math.floor(v + 0.5))
		end,
		higherBetter = true,
	},
	{
		label = "MOVE SPEED",
		get = function(e)
			return e.moveSpeedMultiplier * 100
		end,
		fmt = function(v)
			return string.format("%d%%", math.floor(v + 0.5))
		end,
		higherBetter = true,
	},
}

-- state
local gui: ScreenGui
local root: TextButton
local content: Frame
local isOpenFlag = false
local def: WeaponDef? = nil
local selection: Selection = {}
local baseEffective: WeaponStats.Effective? = nil
local baseRatings: WeaponStats.Ratings? = nil
local selectedSlot: string? = nil
local onDoneCb: ((Selection) -> ())? = nil
local onClosedCb: (() -> ())? = nil
local openConns: { any } = {} -- RBXScriptConnections and Signal connections (both :Disconnect())
local previewCamo: string? = nil -- camo shown on the preview (equipped, or a locked one being previewed)
local pendingCamo: string? = nil -- equip sent, ProfileSync not yet seen
local camoRow: ScrollingFrame
local camoStatus: TextLabel

-- preview state (numbers only, so the render step allocates no tables)
local previewModel: Model? = nil
local yaw = math.rad(115)
local camDist = 8
local targetDist = 8
local camFocus = Vector3.zero
local targetFocus = Vector3.zero
local dragging = false
local dragInput: InputObject? = nil
local dragLastX = 0
local lastDragAt = -math.huge
local zoom = 1
local fitDist = 8
local previewOnly = false
local doneButton: TextButton
local footerHint: TextLabel

-- widgets
local weaponTitle: TextLabel
local weaponInfo: TextLabel
local levelLabel: TextLabel
local levelFill: Frame
local nextUnlockLabel: TextLabel
local timerLabel: TextLabel
local slotsTitle: TextLabel
local slotList: Frame
local optionsTitle: TextLabel
local optionsList: ScrollingFrame
local viewport: ViewportFrame
local vpCamera: Camera
local tagsLabel: TextLabel
type StatRow = { value: TextLabel, diff: TextLabel, base: Frame, delta: Frame }
local statRows: { StatRow } = {}
type NumberRow = { value: TextLabel }
local numberRows: { NumberRow } = {}

---------------------------------------------------------------------------------------------
-- data helpers
---------------------------------------------------------------------------------------------

local function clearGuiChildren(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

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

local function weaponLevel(id: string): number
	local profile = ClientState.profile
	local wp = if profile and profile.weapons then profile.weapons[id] else nil
	return if wp and type(wp.level) == "number" then wp.level else 1
end

local function attachment(id: string?): AttachmentDef?
	if not id then
		return nil
	end
	return AttachmentsConfig[id]
end

local function rating(r: WeaponStats.Ratings?, key: string): number
	if not r then
		return 0
	end
	local v = (r :: any)[key]
	return if type(v) == "number" then v else 0
end

-- Attachments this weapon offers for `slot`, sorted by unlock level then name.
local function optionsFor(d: WeaponDef, slot: string): { AttachmentDef }
	local list: { AttachmentDef } = {}
	for id, _ in d.attachmentUnlocks do
		local att = AttachmentsConfig[id]
		if att and att.slot == slot and table.find(att.classes, d.class) ~= nil then
			table.insert(list, att)
		end
	end
	table.sort(list, function(a, b)
		local la, lb = d.attachmentUnlocks[a.id] or 0, d.attachmentUnlocks[b.id] or 0
		if la ~= lb then
			return la < lb
		end
		return a.displayName < b.displayName
	end)
	return list
end

local function pct(v: number): number
	return math.floor(math.abs(v - 1) * 100 + 0.5)
end

function Gunsmith.prosCons(att: AttachmentDef): { ProCon }
	local pros: { ProCon } = {}
	local cons: { ProCon } = {}
	local mods = (att.modifiers or {}) :: any
	for _, spec in MODIFIER_SPECS do
		local v = mods[spec.key]
		if type(v) == "number" and v ~= 1 then
			local p = pct(v)
			if p > 0 then
				local gain: boolean
				local sign: string
				if spec.kind == "time" then
					gain = v < 1
					sign = if v < 1 then "+" else "-"
				elseif spec.kind == "less" then
					gain = v < 1
					sign = if v < 1 then "-" else "+"
				else
					gain = v > 1
					sign = if v > 1 then "+" else "-"
				end
				local entry = { text = string.format("%s%d%% %s", sign, p, spec.label), positive = gain }
				table.insert(if gain then pros else cons, entry)
			end
		end
	end
	if att.suppressed then
		table.insert(pros, 1, { text = "Hidden from enemies", positive = true })
	end
	for _, c in cons do
		table.insert(pros, c)
	end
	return pros
end

---------------------------------------------------------------------------------------------
-- preview
---------------------------------------------------------------------------------------------

local function rebuildPreview(snap: boolean)
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	local d = def
	if not d then
		return
	end
	local ok, result = pcall(WeaponModel.build, d, { attachments = selection, castShadow = false, camo = previewCamo })
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		warn("[Gunsmith] preview build failed: " .. tostring(result))
		return
	end
	local model = result :: Model
	model.Parent = viewport
	previewModel = model
	local cf, size = model:GetBoundingBox()
	local radius = math.max(size.Magnitude * 0.5, 0.5)
	targetFocus = cf.Position
	fitDist = radius / math.tan(math.rad(PREVIEW_FOV * 0.5)) * 0.8
	targetDist = fitDist * zoom
	if snap then
		camFocus = targetFocus
		camDist = targetDist
	end
end

local function renderStep(dt: number)
	if not dragging and os.clock() - lastDragAt > DRAG_IDLE then
		yaw += dt * AUTO_SPIN
	end
	local k = 1 - math.exp(-dt * 10)
	camDist += (targetDist - camDist) * k
	camFocus = camFocus:Lerp(targetFocus, k)
	local rot = CFrame.fromOrientation(PREVIEW_PITCH, yaw, 0)
	vpCamera.CFrame = rot + (camFocus + rot.ZVector * camDist)
end

---------------------------------------------------------------------------------------------
-- camos (Phase 5)
---------------------------------------------------------------------------------------------

local function equippedCamo(weaponId: string): string
	local profile = ClientState.profile
	local cos = if profile then (profile :: any).cosmetics else nil
	local camos = if type(cos) == "table" and type(cos.equipped) == "table" then cos.equipped.camos else nil
	local id = if type(camos) == "table" then camos[weaponId] else nil
	return if type(id) == "string" then id else CosmeticsConfig.DefaultCamo
end

local function ownsCamo(weaponId: string, camoId: string): boolean
	if camoId == CosmeticsConfig.DefaultCamo then
		return true
	end
	local profile = ClientState.profile
	local cos = if profile then (profile :: any).cosmetics else nil
	local owned = if type(cos) == "table" and type(cos.owned) == "table" and type(cos.owned.camos) == "table" then cos.owned.camos[weaponId] else nil
	return type(owned) == "table" and table.find(owned, camoId) ~= nil
end

local function fireEquip(kind: string, id: string, weaponId: string?)
	task.spawn(function()
		local ok, err = pcall(function()
			Net.event("EquipCosmetic"):FireServer(kind, id, weaponId)
		end)
		if not ok then
			warn("[Gunsmith] EquipCosmetic failed: " .. tostring(err))
		end
	end)
end

local rebuildCamos: () -> ()

local function camoCard(d: WeaponDef, camo: CosmeticsConfig.CamoDef, order: number)
	local owned = ownsCamo(d.id, camo.id)
	local equipped = (pendingCamo or equippedCamo(d.id)) == camo.id
	local previewing = previewCamo == camo.id or (previewCamo == nil and camo.id == CosmeticsConfig.DefaultCamo)
	local profile = ClientState.profile
	local wp = if profile and profile.weapons then profile.weapons[d.id] else nil
	local card = Theme.button({ Name = camo.id, Size = UDim2.fromOffset(148, 78), LayoutOrder = order, Parent = camoRow })
	Theme.setButtonColor(card, if previewing then C.PanelHover elseif owned then C.PanelLight else C.Locked)
	card.BackgroundTransparency = if owned then 0.05 else 0.3
	if equipped then
		Theme.stroke(C.Accent, 2, 0).Parent = card
	elseif previewing then
		Theme.stroke(C.Text, 1, 0.3).Parent = card
	end
	-- swatch: main colour with an accent stripe
	local swatch: Frame = Theme.new("Frame", {
		BackgroundColor3 = camo.color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(28, 28),
		Parent = card,
	}, { Theme.corner(4) })
	Theme.new("Frame", {
		BackgroundColor3 = camo.accent or camo.color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0.35, 0),
		Parent = swatch,
	})
	Theme.label({
		Text = string.upper(camo.name),
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = if owned then C.Text else C.TextMuted,
		Position = UDim2.fromOffset(42, 6),
		Size = UDim2.new(1, -48, 0, 16),
		Parent = card,
	})
	Theme.label({
		Text = if equipped then "EQUIPPED" elseif owned then "OWNED" else "LOCKED",
		Font = Theme.Fonts.Bold,
		TextSize = 10,
		TextColor3 = if equipped then C.Accent else C.TextMuted,
		Position = UDim2.fromOffset(42, 22),
		Size = UDim2.new(1, -48, 0, 14),
		Parent = card,
	})
	if not owned then
		local req = Phase5Rules.camoRequirement(camo, wp)
		Theme.label({
			Text = req.text,
			Font = Theme.Fonts.Bold,
			TextSize = 10,
			TextColor3 = C.TextDim,
			Position = UDim2.fromOffset(8, 40),
			Size = UDim2.new(1, -16, 0, 13),
			Parent = card,
		})
		Theme.label({
			Text = req.progress,
			Font = Theme.Fonts.Medium,
			TextSize = 10,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(8, 52),
			Size = UDim2.new(1, -16, 0, 12),
			Parent = card,
		})
		local _, fill = Theme.bar({ Position = UDim2.new(0, 8, 1, -9), Size = UDim2.new(1, -16, 0, 4), Parent = card })
		fill.Size = UDim2.fromScale(req.alpha, 1)
	end
	card.Activated:Connect(function()
		local current = def
		if not isOpenFlag or not current or current.id ~= d.id then
			return
		end
		previewCamo = camo.id
		if owned then
			if (pendingCamo or equippedCamo(d.id)) ~= camo.id then
				pendingCamo = camo.id
				fireEquip("Camo", camo.id, d.id)
			end
			camoStatus.Text = string.upper(camo.name) .. " EQUIPPED"
			camoStatus.TextColor3 = C.Accent
		else
			local req = Phase5Rules.camoRequirement(camo, wp)
			camoStatus.Text = string.format("PREVIEW  ·  LOCKED: %s  %s", req.text, req.progress)
			camoStatus.TextColor3 = C.TextDim
		end
		rebuildPreview(false)
		rebuildCamos()
	end)
end

rebuildCamos = function()
	clearGuiChildren(camoRow)
	local d = def
	if not d then
		return
	end
	for i, camo in CosmeticsConfig.camos do
		camoCard(d, camo, i)
	end
end

---------------------------------------------------------------------------------------------
-- stats
---------------------------------------------------------------------------------------------

local function refreshStats()
	local d = def
	if not d or not baseEffective then
		return
	end
	local e = WeaponStats.resolve(d, selection, AttachmentsConfig)
	local r = WeaponStats.ratings(e)
	for i, spec in STAT_SPECS do
		local row = statRows[i]
		local new, base = rating(r, spec.key), rating(baseRatings, spec.key)
		local lo, hi = math.min(new, base) / 100, math.max(new, base) / 100
		Theme.tween(row.base, Theme.Tween.Normal, { Size = UDim2.fromScale(lo, 1) })
		row.delta.BackgroundColor3 = if new > base then C.Positive else C.Danger
		row.delta.Visible = new ~= base
		Theme.tween(row.delta, Theme.Tween.Normal, { Position = UDim2.fromScale(lo, 0), Size = UDim2.fromScale(hi - lo, 1) })
		row.value.Text = tostring(new)
		if new > base then
			row.diff.Text = "+" .. tostring(new - base)
			row.diff.TextColor3 = C.Positive
		elseif new < base then
			row.diff.Text = "-" .. tostring(base - new)
			row.diff.TextColor3 = C.Danger
		else
			row.diff.Text = ""
		end
	end
	local be = baseEffective :: WeaponStats.Effective
	for i, spec in NUMBER_SPECS do
		local row = numberRows[i]
		local new, base = spec.get(e), spec.get(be)
		local changed = math.abs(new - base) > 1e-6 and spec.fmt(new) ~= spec.fmt(base)
		if changed then
			local better = if spec.higherBetter then new > base else new < base
			row.value.Text = string.format(
				'<font color="%s">%s</font>  <font color="%s">(%s)</font>',
				Theme.hex(if better then C.Positive else C.Danger),
				spec.fmt(new),
				Theme.hex(C.TextMuted),
				spec.fmt(base)
			)
		else
			row.value.Text = spec.fmt(new)
		end
	end
	local tags = {}
	if e.suppressed then
		table.insert(tags, "SUPPRESSED")
	end
	if e.scoped then
		table.insert(tags, "MAGNIFIED SCOPE")
	end
	if d.fireMode == "Burst" and d.burst then
		table.insert(tags, string.format("%d-ROUND BURST", d.burst.count))
	else
		table.insert(tags, string.upper(d.fireMode))
	end
	if d.pellets then
		table.insert(tags, string.format("%d PELLETS", d.pellets))
	end
	tagsLabel.Text = table.concat(tags, "  ·  ")
end

---------------------------------------------------------------------------------------------
-- slots + options
---------------------------------------------------------------------------------------------

local refreshAll: (rebuildModel: boolean) -> ()

local function chip(text: string, positive: boolean, order: number, parent: Instance)
	local color = if positive then C.Positive else C.Danger
	local l = Theme.label({
		Text = text,
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = color,
		TextTruncate = Enum.TextTruncate.None,
		BackgroundColor3 = color,
		BackgroundTransparency = 0.86,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 22),
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.corner(4).Parent = l
	Theme.padding(0, 8).Parent = l
end

local function optionCard(d: WeaponDef, att: AttachmentDef?, order: number, level: number)
	local slot = selectedSlot :: string
	local id = if att then att.id else nil
	local required = if id then (d.attachmentUnlocks[id] or math.huge) else 0
	local unlocked = level >= required
	local equipped = selection[slot] == id
	local card = Theme.button({
		Name = id or "None",
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = optionsList,
	})
	Theme.setButtonColor(card, if equipped then C.PanelHover elseif unlocked then C.PanelLight else C.Locked)
	card.BackgroundTransparency = if unlocked then 0.1 else 0.45
	if equipped then
		Theme.stroke(C.Accent, 2, 0).Parent = card
	end
	Theme.padding(12, 14).Parent = card
	Theme.list(Enum.FillDirection.Vertical, 6).Parent = card

	local header: Frame = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Parent = card })
	Theme.label({
		Text = if att then string.upper(att.displayName) else "NONE",
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = if unlocked then C.Text else C.TextMuted,
		Size = UDim2.new(1, -170, 1, 0),
		Parent = header,
	})
	local status, statusColor = "", C.TextMuted
	if equipped then
		status, statusColor = "EQUIPPED", C.Accent
	elseif not unlocked then
		status, statusColor = "WEAPON LEVEL " .. tostring(required), C.TextDim
	end
	Theme.label({
		Text = status,
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = statusColor,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 170, 1, 0),
		Parent = header,
	})
	Theme.label({
		Text = if att then att.description else "No attachment in this slot.",
		Font = Theme.Fonts.Regular,
		TextSize = 14,
		TextColor3 = if unlocked then C.TextDim else C.TextMuted,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 2,
		Parent = card,
	})
	if att then
		local list = Gunsmith.prosCons(att)
		if #list > 0 then
			local chips: Frame = Theme.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 3,
				Parent = card,
			})
			local layout = Theme.list(Enum.FillDirection.Horizontal, 6)
			layout.Wraps = true
			layout.Parent = chips
			for i, pc in list do
				chip(pc.text, pc.positive, i, chips)
			end
		end
	end
	card.Activated:Connect(function()
		if not isOpenFlag or not unlocked or selectedSlot ~= slot then
			return
		end
		if id then
			selection[slot] = id
		else
			selection[slot] = nil
		end
		refreshAll(true)
	end)
end

local function rebuildOptions()
	local scroll = optionsList.CanvasPosition
	clearGuiChildren(optionsList)
	local d = def
	local slot = selectedSlot
	if not d or not slot then
		optionsTitle.Text = "OPTIONS"
		Theme.label({
			Text = "This weapon has no attachment slots.",
			Font = Theme.Fonts.Medium,
			TextSize = 15,
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, 0, 0, 30),
			Parent = optionsList,
		})
		return
	end
	optionsTitle.Text = (SLOT_TITLES[slot] or string.upper(slot)) .. "  //  OPTIONS"
	local level = weaponLevel(d.id)
	optionCard(d, nil, 0, level)
	local opts = optionsFor(d, slot)
	for i, att in opts do
		optionCard(d, att, i, level)
	end
	if #opts == 0 then
		Theme.label({
			Text = "No attachments for this slot yet.",
			Font = Theme.Fonts.Medium,
			TextSize = 14,
			TextColor3 = C.TextMuted,
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 1,
			Parent = optionsList,
		})
	end
	optionsList.CanvasPosition = scroll
end

local function rebuildSlots()
	clearGuiChildren(slotList)
	local d = def
	if not d then
		return
	end
	local level = weaponLevel(d.id)
	for i, slot in d.attachmentSlots do
		local isSel = slot == selectedSlot
		local equippedId = selection[slot]
		local att = attachment(equippedId)
		local opts = optionsFor(d, slot)
		local unlockedCount = 0
		for _, o in opts do
			if level >= (d.attachmentUnlocks[o.id] or math.huge) then
				unlockedCount += 1
			end
		end
		local button = Theme.button({ Name = slot, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = i, Parent = slotList })
		Theme.setButtonColor(button, if isSel then C.PanelHover else C.PanelLight)
		if isSel then
			Theme.stroke(C.Accent, 1, 0.2).Parent = button
		end
		Theme.new("Frame", {
			BackgroundColor3 = if att then C.Accent else C.Stroke,
			BackgroundTransparency = if att then 0 else 0.5,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 4, 1, 0),
			Parent = button,
		})
		Theme.label({
			Text = SLOT_TITLES[slot] or string.upper(slot),
			Font = Theme.Fonts.Bold,
			TextSize = 15,
			Position = UDim2.fromOffset(16, 6),
			Size = UDim2.new(0.45, -16, 0, 20),
			Parent = button,
		})
		Theme.label({
			Text = string.format("%d / %d UNLOCKED", unlockedCount, #opts),
			Font = Theme.Fonts.Medium,
			TextSize = 11,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(16, 28),
			Size = UDim2.new(0.45, -16, 0, 16),
			Parent = button,
		})
		Theme.label({
			Text = if att then string.upper(att.displayName) else "NONE",
			Font = Theme.Fonts.Bold,
			TextSize = 14,
			TextColor3 = if att then C.Accent else C.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.new(0.55, -14, 1, 0),
			Parent = button,
		})
		button.Activated:Connect(function()
			if not isOpenFlag or selectedSlot == slot then
				return
			end
			selectedSlot = slot
			optionsList.CanvasPosition = Vector2.zero
			rebuildSlots()
			rebuildOptions()
		end)
	end
end

local function refreshHeader()
	local d = def
	if not d then
		return
	end
	weaponTitle.Text = string.upper(d.displayName)
	local count = 0
	for _ in selection do
		count += 1
	end
	weaponInfo.Text = (if previewOnly then "PREVIEW  ·  " else "") .. string.format(
		"%s  ·  %s  ·  %d / %d ATTACHMENTS",
		string.upper((d.class:gsub("(%l)(%u)", "%1 %2"))),
		string.upper(d.slot),
		count,
		#d.attachmentSlots
	)
	local profile = ClientState.profile
	local wp = if profile and profile.weapons then profile.weapons[d.id] else nil
	local level = weaponLevel(d.id)
	levelLabel.Text = "WEAPON LV " .. tostring(level)
	local needed = if wp then wp.needed else 0
	levelFill.Size = UDim2.fromScale(if wp and needed > 0 then math.clamp(wp.xp / needed, 0, 1) elseif wp then 1 else 0, 1)
	-- next unlock among the attachments this weapon offers
	local nextAtt: AttachmentDef? = nil
	local nextLevel = math.huge
	for id, req in d.attachmentUnlocks do
		local att = AttachmentsConfig[id]
		if att and req > level and (req < nextLevel or (req == nextLevel and nextAtt and att.displayName < nextAtt.displayName)) then
			nextAtt, nextLevel = att, req
		end
	end
	if nextAtt then
		nextUnlockLabel.Text = string.format("NEXT: %s AT LV %d", string.upper(nextAtt.displayName), nextLevel)
	elseif next(d.attachmentUnlocks) ~= nil then
		nextUnlockLabel.Text = "ALL ATTACHMENTS UNLOCKED"
	else
		nextUnlockLabel.Text = ""
	end
end

refreshAll = function(rebuildModel: boolean)
	refreshHeader()
	rebuildSlots()
	rebuildOptions()
	refreshStats()
	if rebuildModel then
		rebuildPreview(false)
	end
end

---------------------------------------------------------------------------------------------
-- open / close
---------------------------------------------------------------------------------------------

local function refreshTimer()
	local ms = ClientState.matchState
	local text = ""
	if ms and ms.phaseEndsAt > 0 and (ms.phase == "Lobby" or ms.phase == "Countdown") then
		local t = Theme.formatTime(ms.phaseEndsAt - Theme.serverNow())
		text = (if ms.phase == "Lobby" then "MATCH STARTS IN " else "DEPLOYING IN ") .. t
	end
	if timerLabel.Text ~= text then
		timerLabel.Text = text
	end
end

function Gunsmith.isOpen(): boolean
	return isOpenFlag
end

function Gunsmith.close()
	if not isOpenFlag then
		return
	end
	isOpenFlag = false
	for _, conn in openConns do
		conn:Disconnect()
	end
	table.clear(openConns)
	ContextActionService:UnbindAction(BACK_ACTION)
	dragging = false
	dragInput = nil
	gui.Enabled = false
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
	clearGuiChildren(optionsList)
	clearGuiChildren(slotList)
	clearGuiChildren(camoRow)
	previewCamo = nil
	pendingCamo = nil
	ClientState.setMenuOpen("Gunsmith", false)
	local closed = onClosedCb
	onDoneCb = nil
	onClosedCb = nil
	def = nil
	if closed then
		task.spawn(closed)
	end
end

local function done()
	if not isOpenFlag or previewOnly then
		return
	end
	local cb = onDoneCb
	local result = copySelection(selection)
	onDoneCb = nil
	Gunsmith.close()
	if cb then
		task.spawn(cb, result)
	end
end

function Gunsmith.open(id: string, current: { [string]: string }?, onDone: (Selection) -> (), onClosed: (() -> ())?): boolean
	if isOpenFlag then
		Gunsmith.close()
	end
	local d = WeaponsConfig[id]
	if not d then
		warn("[Gunsmith] unknown weapon id: " .. tostring(id))
		return false
	end
	def = d
	previewOnly = false
	doneButton.Visible = true
	footerHint.Text = "DONE SAVES THIS LOADOUT  ·  BACK DISCARDS CHANGES"
	selection = WeaponStats.sanitize(d, copySelection(current), weaponLevel(id), AttachmentsConfig)
	baseEffective = WeaponStats.resolve(d, nil, AttachmentsConfig)
	baseRatings = WeaponStats.ratings(baseEffective :: WeaponStats.Effective)
	selectedSlot = d.attachmentSlots[1]
	onDoneCb = onDone
	onClosedCb = onClosed
	isOpenFlag = true

	-- slot list height depends on the weapon's slot count
	local slotsHeight = math.max(#d.attachmentSlots, 1) * 58 - 6
	slotList.Size = UDim2.new(1, 0, 0, slotsHeight)
	optionsTitle.Position = UDim2.fromOffset(0, 30 + slotsHeight + 14)
	optionsList.Position = UDim2.fromOffset(0, 30 + slotsHeight + 44)
	optionsList.Size = UDim2.new(1, 0, 1, -(30 + slotsHeight + 44))
	optionsList.CanvasPosition = Vector2.zero
	slotsTitle.Text = if #d.attachmentSlots > 0 then "ATTACHMENT SLOTS" else "NO ATTACHMENT SLOTS"

	yaw = SIDE_YAW + math.rad(20)
	zoom = 1
	lastDragAt = -math.huge
	pendingCamo = nil
	previewCamo = equippedCamo(id)
	camoStatus.Text = "CAMOS EQUIP INSTANTLY  ·  LOCKED CAMOS CAN BE PREVIEWED"
	camoStatus.TextColor3 = C.TextMuted
	camoRow.CanvasPosition = Vector2.zero
	rebuildCamos()
	ClientState.setMenuOpen("Gunsmith", true)
	refreshAll(false)
	rebuildPreview(true)
	refreshTimer()
	renderStep(0)

	gui.Enabled = true
	root.BackgroundTransparency = 1
	Theme.tween(root, Theme.Tween.Normal, { BackgroundTransparency = 0 })
	content.Position = UDim2.fromOffset(0, 24)
	Theme.tween(content, Theme.Tween.Slow, { Position = UDim2.fromOffset(0, 0) })

	table.insert(openConns, RunService.RenderStepped:Connect(renderStep))
	table.insert(openConns, UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput then
			local x = input.Position.X
			yaw -= (x - dragLastX) * DRAG_SPEED
			dragLastX = x
		end
	end))
	table.insert(openConns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input == dragInput then
			dragging = false
			dragInput = nil
			lastDragAt = os.clock()
		end
	end))
	table.insert(openConns, ClientState.ProfileChanged:Connect(function()
		local d = def
		if isOpenFlag and d then
			-- weapon level may have changed: drop anything no longer valid, as the server would
			local clean = WeaponStats.sanitize(d, selection, weaponLevel(d.id), AttachmentsConfig)
			local changed = false
			for slot, id in selection do
				if clean[slot] ~= id then
					changed = true
				end
			end
			selection = clean
			-- Phase 5: camo equip confirmed (or refused) by the authoritative profile
			if pendingCamo and equippedCamo(d.id) == pendingCamo then
				pendingCamo = nil
			end
			refreshAll(changed)
			rebuildCamos()
		end
	end))
	table.insert(openConns, ClientState.DeployedChanged:Connect(function(deployed: boolean)
		if deployed then
			Gunsmith.close()
		end
	end))
	table.insert(openConns, ClientState.MatchStateChanged:Connect(function(ms)
		if ms.phase == "Results" or ClientState.deployed then
			Gunsmith.close()
		end
	end))
	ContextActionService:BindActionAtPriority(BACK_ACTION, function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
		if state == Enum.UserInputState.Begin then
			task.defer(Gunsmith.close)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 50, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
	return true
end

---------------------------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------------------------

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

local function buildHeader(parent: Instance)
	local top: Frame = Theme.new("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 28),
		Size = UDim2.new(1, -96, 0, 104),
		Parent = parent,
	})
	Theme.new("Frame", {
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.fromOffset(8, 88),
		Parent = top,
	})
	Theme.label({
		Text = "G U N S M I T H",
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(22, 6),
		Size = UDim2.new(0.6, 0, 0, 22),
		Parent = top,
	})
	weaponTitle = Theme.label({
		Font = Theme.Fonts.Title,
		TextSize = 48,
		Position = UDim2.fromOffset(20, 28),
		Size = UDim2.new(1, -480, 0, 52),
		Parent = top,
	})
	weaponInfo = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(22, 80),
		Size = UDim2.new(1, -480, 0, 18),
		Parent = top,
	})

	local levelPanel = Theme.panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 8),
		Size = UDim2.fromOffset(420, 88),
		Parent = top,
	})
	Theme.padding(12, 16).Parent = levelPanel
	levelLabel = Theme.label({ Font = Theme.Fonts.Bold, TextSize = 18, TextColor3 = C.Accent, Size = UDim2.new(1, 0, 0, 22), Parent = levelPanel })
	timerLabel = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = levelPanel,
	})
	local _, fill = Theme.bar({ Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 8), Parent = levelPanel })
	levelFill = fill
	nextUnlockLabel = Theme.label({
		Font = Theme.Fonts.Medium,
		TextSize = 13,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = levelPanel,
	})
end

local function buildLeft(parent: Instance)
	local panel = Theme.panel({ Name = "Slots", Size = UDim2.new(0.32, -14, 1, 0), LayoutOrder = 1, Parent = parent })
	Theme.padding(14).Parent = panel
	slotsTitle = sectionTitle("ATTACHMENT SLOTS", panel)
	slotList = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 0),
		Parent = panel,
	}, { Theme.list(Enum.FillDirection.Vertical, 6) })
	optionsTitle = sectionTitle("OPTIONS", panel)
	optionsList = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	}, { Theme.list(Enum.FillDirection.Vertical, 8) })
end

local function buildPreview(parent: Instance)
	local panel = Theme.panel({ Name = "Preview", Size = UDim2.new(0.42, -14, 1, 0), LayoutOrder = 2, Parent = parent })
	panel.BackgroundColor3 = Color3.fromRGB(70, 76, 86) -- lighter than the other panels so dark guns read
	Theme.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(0.7, 0.1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = panel,
	})
	viewport = Theme.new("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(175, 180, 190),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -0.8, -0.5),
		Active = true,
		Parent = panel,
	})
	vpCamera = Theme.new("Camera", { FieldOfView = PREVIEW_FOV, Parent = viewport })
	viewport.CurrentCamera = vpCamera
	viewport.InputBegan:Connect(function(input: InputObject)
		if not isOpenFlag then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragInput = if input.UserInputType == Enum.UserInputType.Touch then input else nil
			dragLastX = input.Position.X
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			zoom = math.clamp(zoom * (1 - input.Position.Z * 0.1), ZOOM_MIN, ZOOM_MAX)
			targetDist = fitDist * zoom
		end
	end)
	viewport.InputChanged:Connect(function(input: InputObject)
		if isOpenFlag and input.UserInputType == Enum.UserInputType.MouseWheel then
			zoom = math.clamp(zoom * (1 - input.Position.Z * 0.1), ZOOM_MIN, ZOOM_MAX)
			targetDist = fitDist * zoom
		end
	end)
	Theme.label({
		Text = if Theme.isTouchOnly() then "DRAG TO ROTATE" else "DRAG TO ROTATE  ·  SCROLL TO ZOOM  ·  BACKSPACE TO GO BACK",
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, 16),
		Parent = panel,
	})
	tagsLabel = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 13,
		TextColor3 = C.TextDim,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 18),
		Parent = panel,
	})

	-- Phase 5: CAMO strip along the bottom of the preview
	local strip: Frame = Theme.new("Frame", {
		Name = "Camos",
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -36),
		Size = UDim2.new(1, -24, 0, 132),
		Parent = panel,
	}, { Theme.corner(6) })
	Theme.label({
		Text = "CAMO",
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.fromOffset(60, 18),
		Parent = strip,
	})
	camoStatus = Theme.label({
		Font = Theme.Fonts.Bold,
		TextSize = 11,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.new(1, -90, 0, 16),
		Parent = strip,
	})
	camoRow = Theme.new("ScrollingFrame", {
		Name = "Row",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(8, 28),
		Size = UDim2.new(1, -16, 1, -32),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 3,
		Parent = strip,
	}, { Theme.list(Enum.FillDirection.Horizontal, 8) })
end

local function buildStats(parent: Instance)
	local panel = Theme.panel({ Name = "Stats", Size = UDim2.new(0.26, -12, 1, 0), LayoutOrder = 3, Parent = parent })
	Theme.padding(14).Parent = panel
	local scroll: ScrollingFrame = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	}, { Theme.list(Enum.FillDirection.Vertical, 10) })
	sectionTitle("STATS", scroll, 0)
	for i, spec in STAT_SPECS do
		local row: Frame = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 40), LayoutOrder = i, Parent = scroll })
		Theme.label({ Text = spec.label, Font = Theme.Fonts.Bold, TextSize = 14, TextColor3 = C.TextDim, Size = UDim2.new(0.6, 0, 0, 20), Parent = row })
		local diff = Theme.label({
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -42, 0, 0),
			Size = UDim2.fromOffset(50, 20),
			Parent = row,
		})
		local value = Theme.label({
			Font = Theme.Fonts.Bold,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(40, 20),
			Parent = row,
		})
		local track, base = Theme.bar({ Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 10), Parent = row }, C.Text)
		local delta: Frame = Theme.new("Frame", {
			Name = "Delta",
			BorderSizePixel = 0,
			BackgroundColor3 = C.Positive,
			Size = UDim2.fromScale(0, 1),
			Visible = false,
			Parent = track,
		})
		statRows[i] = { value = value, diff = diff, base = base, delta = delta }
	end
	local divider: Frame = Theme.new("Frame", {
		BackgroundColor3 = C.Stroke,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -6, 0, 1),
		LayoutOrder = 20,
		Parent = scroll,
	})
	divider.Name = "Divider"
	sectionTitle("DETAILS", scroll, 21)
	for i, spec in NUMBER_SPECS do
		local row: Frame = Theme.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 24), LayoutOrder = 21 + i, Parent = scroll })
		Theme.label({ Text = spec.label, Font = Theme.Fonts.Bold, TextSize = 13, TextColor3 = C.TextMuted, Size = UDim2.new(0.45, 0, 1, 0), Parent = row })
		local value = Theme.label({
			Font = Theme.Fonts.Bold,
			TextSize = 15,
			RichText = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0.55, 0, 1, 0),
			Parent = row,
		})
		numberRows[i] = { value = value }
	end
end

local function buildFooter(parent: Instance)
	local bar: Frame = Theme.new("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 48, 1, -28),
		Size = UDim2.new(1, -96, 0, 60),
		Parent = parent,
	})
	footerHint = Theme.label({
		Text = "DONE SAVES THIS LOADOUT  ·  BACK DISCARDS CHANGES",
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.TextDim,
		Size = UDim2.new(1, -620, 1, 0),
		Parent = bar,
	})
	local buttons: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 600, 1, 0),
		Parent = bar,
	}, { Theme.list(Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Right) })
	local back = Theme.button({ Name = "Back", Text = "BACK", TextSize = 18, Size = UDim2.new(0, 160, 1, 0), LayoutOrder = 1, Parent = buttons })
	local reset = Theme.button({ Name = "Reset", Text = "RESET", TextSize = 18, Size = UDim2.new(0, 160, 1, 0), LayoutOrder = 2, Parent = buttons })
	doneButton = Theme.button({ Name = "Done", Text = "DONE", TextSize = 20, Size = UDim2.new(0, 240, 1, 0), LayoutOrder = 3, Parent = buttons }, "Primary")
	back.Activated:Connect(function()
		Gunsmith.close()
	end)
	reset.Activated:Connect(function()
		if not isOpenFlag or next(selection) == nil then
			return
		end
		selection = {}
		refreshAll(true)
	end)
	doneButton.Activated:Connect(done)
end

function Gunsmith.init()
	local canvas
	gui, canvas = Theme.screen("Gunsmith", 11)
	gui.Enabled = false
	-- full-screen backdrop button: hides the lobby and swallows clicks meant for it
	root = Theme.new("TextButton", {
		Name = "Gunsmith",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = C.Backdrop,
		BackgroundTransparency = 0, -- opaque: lobby text must not bleed through the preview
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = canvas,
	})
	content = Theme.new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	buildHeader(content)
	local body: Frame = Theme.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 148),
		Size = UDim2.new(1, -96, 1, -148 - 104),
		Parent = content,
	}, { Theme.list(Enum.FillDirection.Horizontal, 20) })
	buildLeft(body)
	buildPreview(body)
	buildStats(body)
	buildFooter(content)
	Theme.mount(gui)
end

function Gunsmith.start()
	while true do
		if isOpenFlag then
			refreshTimer()
		end
		task.wait(0.25)
	end
end

-- Look-only Gunsmith for any weapon (locked ones too): nothing is saved.
function Gunsmith.preview(id: string, onClosed: (() -> ())?): boolean
	local opened = Gunsmith.open(id, nil, function() end, onClosed)
	if opened then
		previewOnly = true
		doneButton.Visible = false
		footerHint.Text = "PREVIEW ONLY  ·  ATTACHMENTS CAN BE TRIED ON, NOTHING IS SAVED"
		refreshAll(false)
	end
	return opened
end

return Gunsmith
