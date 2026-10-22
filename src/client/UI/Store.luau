--!strict
-- Store (Phase 6): full-screen lobby menu with three tabs.
--   LOOT CRATES    crates earned by play (Supply and Gear): pick a crate, OPEN (OpenCrate) with a
--                  shake-and-reveal animation, the last result, and the odds
--   SHOP           store cosmetics and gear sets bought with credits earned by play (BuyItem)
--   PREMIUM        fixed Robux bundles (MarketplaceService:PromptProductPurchase); the server grants
--                  them in ProcessReceipt. Bundles without a product id show COMING SOON.
--
-- Public API (the Lobby's STORE button is the caller):
--   Store.open(onClosed?, tab?) -> boolean, Store.close(), Store.isOpen() -> boolean
--   (tab: "Crates" | "Shop" | "Premium"; the lobby's SHOP button opens on the crates)
-- BACK / Backspace / gamepad B close it. Everything is a view of the server's ProfileSummary.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local StoreRulesUI = require(script.Parent.StoreRulesUI)
local ClientState = require(script.Parent.Parent.ClientState)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Types = require(Shared.Types)
local StoreConfig = require(Shared.Config.Store)
local CosmeticsConfig = require(Shared.Config.Cosmetics)
local StoreRules = require(Shared.Pure.StoreRules)
local GearConfig = require(Shared.Config.Gear)
local Assets = require(Shared.Config.Assets)
local TweenService = game:GetService("TweenService")

local Store = {}

local C = Theme.Colors
local BACK_ACTION = "COR_StoreBack"
local CRATE_NOTE = "Crates are earned by play only: a Supply Crate for every level-up and for finishing all three daily challenges, "
	.. "a Gear Crate every "
	.. tostring(StoreConfig.GearCrateEveryLevels)
	.. " levels. They cannot be bought. You never get an item you already own; once you own everything, a crate gives credits instead."
local PREMIUM_NOTE = "Every bundle is cosmetic and always gives exactly what is listed. Nothing paid is random."

type Tab = "Shop" | "Crates" | "Premium"
local TABS: { { id: Tab, text: string } } = {
	{ id = "Crates", text = "LOOT CRATES" },
	{ id = "Shop", text = "SHOP" },
	{ id = "Premium", text = "PREMIUM" },
}

local gui: ScreenGui
local root: TextButton
local body: Frame
local creditsLabel: TextLabel
local tabButtons: { [string]: TextButton } = {}
local isOpenFlag = false
local currentTab: Tab = "Crates"
local selectedCrate = "Supply"
local revealAt = 0 -- os.clock() of the last CrateOpened: the result card pops in once
local onClosedCb: (() -> ())? = nil
local openConns: { any } = {}
local lastResult: Types.CrateResultPayload? = nil
local opening = false

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
			warn("[Store] " .. remote .. " failed: " .. tostring(err))
		end
	end)
end

local function storeView(profile: Types.ProfileSummary?): Types.StoreView?
	local s = if profile then (profile :: any).store else nil
	return if type(s) == "table" and type(s.credits) == "number" then s else nil
end

local function nameOf(kind: string, id: string): string
	local def: any = if kind == "Camo"
		then CosmeticsConfig.camoById[id]
		elseif kind == "Title" then CosmeticsConfig.titleById[id]
		elseif kind == "Gear" then GearConfig.byId[id]
		else CosmeticsConfig.emblemById[id]
	return if def then def.name else id
end

-- A square preview of a cosmetic: camo swatch, emblem badge or title plate.
local function preview(kind: string, id: string, size: number, parent: Instance): GuiObject
	if kind == "Emblem" then
		local badge = Theme.emblemBadge(id, size, { Parent = parent })
		if badge then
			return badge
		end
	end
	local frame: Frame = Theme.new("Frame", {
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	}, { Theme.corner(8) :: Instance })
	if kind == "Gear" then
		-- helmet / vest / uniform stripes
		local def = GearConfig.byId[id]
		if def then
			frame.ClipsDescendants = true
			for i, color in { def.helmet, def.vest, def.shirt } do
				Theme.new("Frame", {
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					Position = UDim2.fromScale((i - 1) / 3, 0),
					Size = UDim2.fromScale(1 / 3, 1),
					Parent = frame,
				})
			end
		end
	elseif kind == "Camo" then
		local def = CosmeticsConfig.camoById[id]
		if def then
			frame.BackgroundColor3 = def.color
			Theme.new("Frame", {
				BackgroundColor3 = def.accent or def.color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1, 1),
				Size = UDim2.fromScale(0.45, 0.45),
				Parent = frame,
			}, { Theme.corner(6) :: Instance })
		end
	else
		Theme.label({
			Text = "T",
			Font = Theme.Fonts.Title,
			TextSize = math.floor(size * 0.5),
			TextColor3 = C.Accent,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		})
	end
	return frame
end

local function grid(parent: Instance, cell: Vector2): ScrollingFrame
	local s: ScrollingFrame = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	Theme.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = s,
	})
	return s
end

local function note(text: string, parent: Instance, props: { [string]: any }?)
	local base: { [string]: any } = {
		Text = text,
		Font = Theme.Fonts.Regular,
		TextSize = 14,
		TextColor3 = C.TextDim,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 40),
		Parent = parent,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return Theme.label(base)
end

local function actionButton(state: StoreRulesUI.ButtonState, props: { [string]: any }): TextButton
	local button = Theme.button(props, if state.enabled then "Primary" else nil)
	button.Text = state.text
	button.Active = state.enabled
	button.Selectable = state.enabled
	if not state.enabled then
		Theme.setButtonColor(button, C.Locked)
		button.TextColor3 = C.TextMuted
	end
	return button
end

local render: () -> ()

local function renderShop(profile: Types.ProfileSummary, view: Types.StoreView)
	local panel = Theme.panel({ Size = UDim2.fromScale(1, 1), Parent = body })
	Theme.padding(18).Parent = panel
	local list = grid(panel, Vector2.new(260, 250))
	for i, item in StoreConfig.shop do
		local owned = StoreRulesUI.owns((profile :: any).cosmetics, item.grant.kind, item.grant.id)
		local card = Theme.panel({ Name = item.id, Size = UDim2.fromScale(1, 1), LayoutOrder = i, Parent = list })
		card.BackgroundColor3 = C.PanelLight
		Theme.padding(14).Parent = card
		local pv = preview(item.grant.kind, item.grant.id, 96, card)
		pv.Position = UDim2.new(0.5, -48, 0, 0)
		Theme.label({
			Text = string.upper(nameOf(item.grant.kind, item.grant.id)),
			Font = Theme.Fonts.Bold,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 104),
			Size = UDim2.new(1, 0, 0, 22),
			Parent = card,
		})
		Theme.label({
			Text = StoreRulesUI.kindText(item.grant.kind) .. (if item.grant.kind == "Camo" then "  ·  EVERY WEAPON" else ""),
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			TextColor3 = C.TextDim,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, 128),
			Size = UDim2.new(1, 0, 0, 16),
			Parent = card,
		})
		local button = actionButton(StoreRulesUI.shopButton(item.price, view.credits, owned), {
			Name = "Buy",
			TextSize = 16,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 44),
			Parent = card,
		})
		button.Activated:Connect(function()
			if isOpenFlag and button.Active then
				fire("BuyItem", item.id)
			end
		end)
	end
end

-- Crate art from ForgeGUI, or a code-drawn crate when it is not published yet.
local function crateArt(crateId: string, size: number, parent: Instance): GuiObject
	local image = Assets.image("Crate." .. crateId)
	if image then
		return Theme.new("ImageLabel", {
			Name = "CrateArt",
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(size, size),
			Parent = parent,
		})
	end
	local box: Frame = Theme.new("Frame", {
		Name = "CrateArt",
		BackgroundColor3 = if crateId == "Gear" then Color3.fromRGB(30, 32, 36) else Color3.fromRGB(74, 80, 52),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size * 0.72),
		Parent = parent,
	}, { Theme.corner(6) :: Instance, Theme.stroke(C.Accent, 2, 0.3) })
	for _, y in { 0.22, 0.78 } do
		Theme.new("Frame", {
			BackgroundColor3 = Color3.fromRGB(40, 42, 34),
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, y),
			Size = UDim2.new(1, 0, 0, math.max(4, size * 0.06)),
			Parent = box,
		})
	end
	Theme.new("Frame", {
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.4, 0.08),
		Parent = box,
	})
	return box
end

local function renderCrates(profile: Types.ProfileSummary, view: Types.StoreView)
	if not StoreConfig.crateById[selectedCrate] then
		selectedCrate = StoreConfig.crates[1].id
	end
	local crate = StoreConfig.crateById[selectedCrate]
	local count = view.crates[crate.id] or 0

	-- crate picker
	local picker = Theme.panel({ Size = UDim2.new(0.22, -14, 1, 0), Parent = body })
	Theme.padding(14).Parent = picker
	Theme.label({ Text = "YOUR CRATES", Font = Theme.Fonts.Bold, TextSize = 15, TextColor3 = C.Accent, Size = UDim2.new(1, 0, 0, 22), Parent = picker })
	local pickList: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
		Parent = picker,
	}, { Theme.list(Enum.FillDirection.Vertical, 10) })
	for i, c in StoreConfig.crates do
		local n = view.crates[c.id] or 0
		local on = c.id == crate.id
		local card = Theme.button({ Name = c.id, Size = UDim2.new(1, 0, 0, 120), LayoutOrder = i, Parent = pickList })
		Theme.setButtonColor(card, if on then C.PanelHover else C.PanelLight)
		if on then
			Theme.stroke(C.Accent, 2, 0.1).Parent = card
		end
		local art = crateArt(c.id, 92, card)
		art.Position = UDim2.fromOffset(8, 14)
		Theme.label({ Text = string.upper(c.name), Font = Theme.Fonts.Bold, TextSize = 16, Position = UDim2.fromOffset(110, 30), Size = UDim2.new(1, -116, 0, 22), Parent = card })
		Theme.label({
			Text = string.format("%d TO OPEN", n),
			Font = Theme.Fonts.Bold,
			TextSize = 13,
			TextColor3 = if n > 0 then C.Accent else C.TextMuted,
			Position = UDim2.fromOffset(110, 56),
			Size = UDim2.new(1, -116, 0, 18),
			Parent = card,
		})
		card.Activated:Connect(function()
			if isOpenFlag and not opening and selectedCrate ~= c.id then
				selectedCrate = c.id
				lastResult = nil
				render()
			end
		end)
	end

	-- stage: the crate, OPEN, and the reveal
	local stage = Theme.panel({ Size = UDim2.new(0.4, -14, 1, 0), Parent = body })
	Theme.padding(22).Parent = stage
	Theme.label({ Text = string.upper(crate.name), Font = Theme.Fonts.Title, TextSize = 32, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 40), Parent = stage })
	Theme.label({
		Text = string.format("%d UNOPENED", count),
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		TextColor3 = if count > 0 then C.Accent else C.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = stage,
	})
	local holder: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(240, 240),
		Parent = stage,
	})
	local art = crateArt(crate.id, 240, holder)
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	if opening then
		-- shake while the server rolls
		task.spawn(function()
			local i = 0
			while opening and art.Parent do
				i += 1
				art.Rotation = if i % 2 == 0 then 6 else -6
				art.Position = UDim2.new(0.5, (i % 3 - 1) * 4, 0.5, 0)
				task.wait(0.05)
			end
		end)
	end
	local open = actionButton({ text = if opening then "OPENING..." else "OPEN CRATE", enabled = count > 0 and not opening }, {
		Name = "OpenCrate",
		Font = Theme.Fonts.Title,
		TextSize = 24,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(0, 330),
		Size = UDim2.new(1, 0, 0, 64),
		Parent = stage,
	})
	open.Activated:Connect(function()
		if isOpenFlag and open.Active and not opening then
			opening = true
			fire("OpenCrate", crate.id)
			render()
			task.delay(5, function()
				if opening then
					opening = false
					render()
				end
			end)
		end
	end)
	if lastResult and lastResult.crateId == crate.id and not opening then
		local resultBox = Theme.panel({ Name = "Result", Position = UDim2.fromOffset(0, 410), Size = UDim2.new(1, 0, 0, 120), Parent = stage })
		resultBox.BackgroundColor3 = C.PanelLight
		Theme.stroke(C.Accent, 2, 0).Parent = resultBox
		Theme.padding(12).Parent = resultBox
		if lastResult.kind and lastResult.id then
			preview(lastResult.kind, lastResult.id, 96, resultBox)
		end
		Theme.label({
			Text = "YOU GOT",
			Font = Theme.Fonts.Bold,
			TextSize = 12,
			TextColor3 = C.Accent,
			Position = UDim2.fromOffset(if lastResult.kind then 112 else 0, 14),
			Size = UDim2.new(1, -112, 0, 16),
			Parent = resultBox,
		})
		Theme.label({
			Text = StoreRulesUI.resultText(lastResult, nameOf),
			Font = Theme.Fonts.Bold,
			TextSize = 18,
			TextWrapped = true,
			Position = UDim2.fromOffset(if lastResult.kind then 112 else 0, 36),
			Size = UDim2.new(1, -112, 0, 48),
			Parent = resultBox,
		})
		-- reveal once: flash and pop the card in
		if os.clock() - revealAt < 0.3 then
			local scale: UIScale = Theme.new("UIScale", { Scale = 0.6, Parent = resultBox })
			TweenService:Create(scale, Theme.Tween.Pop, { Scale = 1 }):Play()
			local flash: Frame = Theme.new("Frame", {
				BackgroundColor3 = C.Accent,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 5,
				Parent = holder,
			}, { Theme.corner(120) :: Instance })
			TweenService:Create(flash, Theme.Tween.Slow, { BackgroundTransparency = 1, Size = UDim2.fromScale(1.6, 1.6), Position = UDim2.fromScale(-0.3, -0.3) }):Play()
		end
	end
	note(CRATE_NOTE, stage, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 70), TextSize = 12 })

	-- odds
	local right = Theme.panel({ Size = UDim2.new(0.38, -14, 1, 0), Parent = body })
	Theme.padding(22).Parent = right
	Theme.label({ Text = "CONTENTS AND ODDS", Font = Theme.Fonts.Bold, TextSize = 15, TextColor3 = C.Accent, Size = UDim2.new(1, 0, 0, 22), Parent = right })
	local rows: ScrollingFrame = Theme.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		Parent = right,
	}, { Theme.list(Enum.FillDirection.Vertical, 6) })
	for i, o in StoreRules.odds(crate) do
		local owned = StoreRulesUI.owns((profile :: any).cosmetics, o.kind, o.id)
		local row = Theme.panel({ Name = o.id, Size = UDim2.new(1, -8, 0, 52), LayoutOrder = i, Parent = rows })
		row.BackgroundColor3 = C.PanelLight
		row.BackgroundTransparency = if owned then 0.5 else 0.1
		local pv = preview(o.kind, o.id, 36, row)
		pv.Position = UDim2.fromOffset(8, 8)
		Theme.label({
			Text = string.upper(nameOf(o.kind, o.id)) .. "   " .. StoreRulesUI.kindText(o.kind),
			Font = Theme.Fonts.Bold,
			TextSize = 15,
			TextColor3 = if owned then C.TextMuted else C.Text,
			Position = UDim2.fromOffset(56, 0),
			Size = UDim2.new(1, -170, 1, 0),
			Parent = row,
		})
		Theme.label({
			Text = if owned then "OWNED" else string.format("%.1f%%", o.percent),
			Font = Theme.Fonts.Bold,
			TextSize = 15,
			TextColor3 = if owned then C.TextMuted else C.Accent,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 0),
			Size = UDim2.fromOffset(100, 52),
			Parent = row,
		})
	end
end

local function renderPremium(profile: Types.ProfileSummary, view: Types.StoreView)
	local panel = Theme.panel({ Size = UDim2.fromScale(1, 1), Parent = body })
	Theme.padding(22).Parent = panel
	note(PREMIUM_NOTE, panel, { Size = UDim2.new(1, 0, 0, 22) })
	local list: Frame = Theme.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -36),
		Parent = panel,
	}, { Theme.list(Enum.FillDirection.Vertical, 12) })
	for i, b in StoreConfig.premium do
		local owned = table.find(view.premiumOwned, b.id) ~= nil
		local card = Theme.panel({ Name = b.id, Size = UDim2.new(1, 0, 0, 150), LayoutOrder = i, Parent = list })
		card.BackgroundColor3 = C.PanelLight
		Theme.padding(16).Parent = card
		for j, g in b.grants do
			local pv = preview(g.kind, g.id, 72, card)
			pv.Position = UDim2.fromOffset((j - 1) * 84, 24)
		end
		local textX = #b.grants * 84 + 12
		Theme.label({ Text = string.upper(b.name), Font = Theme.Fonts.Title, TextSize = 28, Position = UDim2.fromOffset(textX, 10), Size = UDim2.new(1, -textX - 240, 0, 34), Parent = card })
		note(b.description, card, { Position = UDim2.fromOffset(textX, 52), Size = UDim2.new(1, -textX - 240, 0, 60) })
		local button = actionButton(StoreRulesUI.premiumButton(b.productId, b.robux, owned), {
			Name = "Buy",
			TextSize = 18,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(220, 56),
			Parent = card,
		})
		button.Activated:Connect(function()
			if isOpenFlag and button.Active and b.productId ~= 0 then
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, b.productId)
			end
		end)
	end
end

render = function()
	if not isOpenFlag then
		return
	end
	clearGuiChildren(body)
	for id, button in tabButtons do
		local on = id == currentTab
		Theme.setButtonColor(button, if on then C.Accent else C.PanelLight)
		button.TextColor3 = if on then C.OnAccent else C.TextDim
	end
	local profile = ClientState.profile
	local view = storeView(profile)
	if not profile or not view then
		creditsLabel.Text = ""
		note("Loading...", body)
		return
	end
	creditsLabel.Text = StoreRulesUI.credits(view.credits)
	if currentTab == "Shop" then
		renderShop(profile, view)
	elseif currentTab == "Crates" then
		renderCrates(profile, view)
	else
		renderPremium(profile, view)
	end
end

function Store.isOpen(): boolean
	return isOpenFlag
end

function Store.close()
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
	ClientState.setMenuOpen("Store", false)
	local cb = onClosedCb
	onClosedCb = nil
	if cb then
		task.spawn(cb)
	end
end

function Store.open(onClosed: (() -> ())?, tab: string?): boolean
	if isOpenFlag then
		Store.close()
	end
	if ClientState.deployed then
		return false
	end
	if tab == "Crates" or tab == "Shop" or tab == "Premium" then
		currentTab = tab
	end
	isOpenFlag = true
	onClosedCb = onClosed
	opening = false
	ClientState.setMenuOpen("Store", true)
	gui.Enabled = true
	render()
	table.insert(openConns, ClientState.ProfileChanged:Connect(function()
		render()
	end))
	table.insert(openConns, ClientState.DeployedChanged:Connect(function(deployed: boolean)
		if deployed then
			Store.close()
		end
	end))
	table.insert(openConns, ClientState.Notify:Connect(function(_: string, kind: string)
		if kind == "Warning" and opening then
			opening = false
			render()
		end
	end))
	ContextActionService:BindActionAtPriority(BACK_ACTION, function(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult?
		if state == Enum.UserInputState.Begin then
			task.defer(Store.close)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 50, Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = tabButtons[currentTab]
	end
	return true
end

function Store.init()
	local canvas
	gui, canvas = Theme.screen("Store", 11)
	gui.Enabled = false
	root = Theme.new("TextButton", {
		Name = "Store",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = C.Backdrop,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = canvas,
	})
	local top: Frame = Theme.new("Frame", { Name = "Header", BackgroundTransparency = 1, Position = UDim2.fromOffset(48, 28), Size = UDim2.new(1, -96, 0, 96), Parent = root })
	Theme.new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 8), Size = UDim2.fromOffset(8, 80), Parent = top })
	Theme.label({ Text = "Q U A R T E R M A S T E R", Font = Theme.Fonts.Bold, TextSize = 18, TextColor3 = C.Accent, Position = UDim2.fromOffset(22, 6), Size = UDim2.new(0.6, 0, 0, 22), Parent = top })
	Theme.label({ Text = "SHOP", Font = Theme.Fonts.Title, TextSize = 44, Position = UDim2.fromOffset(20, 28), Size = UDim2.new(0.6, 0, 0, 48), Parent = top })
	Theme.label({ Text = "CREDITS", Font = Theme.Fonts.Bold, TextSize = 14, TextColor3 = C.TextDim, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 14), Size = UDim2.fromOffset(300, 18), Parent = top })
	creditsLabel = Theme.label({
		Name = "Credits",
		Font = Theme.Fonts.Title,
		TextSize = 36,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 34),
		Size = UDim2.fromOffset(300, 44),
		Parent = top,
	})

	local tabRow: Frame = Theme.new("Frame", { Name = "Tabs", BackgroundTransparency = 1, Position = UDim2.fromOffset(48, 140), Size = UDim2.new(1, -96, 0, 48), Parent = root }, { Theme.list(Enum.FillDirection.Horizontal, 10) })
	for i, t in TABS do
		local button = Theme.button({ Name = t.id, Text = t.text, TextSize = 17, Size = UDim2.new(1 / #TABS, -8, 1, 0), LayoutOrder = i, Parent = tabRow })
		tabButtons[t.id] = button
		button.Activated:Connect(function()
			if isOpenFlag then
				currentTab = t.id
				render()
			end
		end)
	end

	body = Theme.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(48, 204),
		Size = UDim2.new(1, -96, 1, -204 - 104),
		Parent = root,
	}, { Theme.list(Enum.FillDirection.Horizontal, 20) })

	local footer: Frame = Theme.new("Frame", { Name = "Footer", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 48, 1, -28), Size = UDim2.new(1, -96, 0, 60), Parent = root })
	Theme.label({
		Text = if Theme.isTouchOnly() then "" else "BACKSPACE / B TO GO BACK",
		Font = Theme.Fonts.Bold,
		TextSize = 14,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, -200, 1, 0),
		Parent = footer,
	})
	local back = Theme.button({ Name = "Back", Text = "BACK", TextSize = 18, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 180, 1, 0), Parent = footer })
	back.Activated:Connect(Store.close)

	Net.event("CrateOpened").OnClientEvent:Connect(function(payload: Types.CrateResultPayload)
		lastResult = payload
		opening = false
		revealAt = os.clock()
		if isOpenFlag then
			render()
		end
	end)
	Theme.mount(gui)
end

return Store
