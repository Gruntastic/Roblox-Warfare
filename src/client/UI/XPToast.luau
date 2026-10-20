--!strict
-- "+100 Kill" popups stacked centre-right, plus level-up banners (account and weapon).
local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local XPToast = {}

local MAX_TOASTS = 6
local TOAST_LIFETIME = 2.2

local stack: Frame
local bannerHolder: Frame
local toasts: { Frame } = {}
local order = 0
local bannerQueue: { { title: string, subtitle: string } } = {}
local bannerBusy = false

local function removeToast(toast: Frame)
	local i = table.find(toasts, toast)
	if not i then
		return
	end
	table.remove(toasts, i)
	local group = toast:FindFirstChild("Group") :: CanvasGroup?
	if group then
		Theme.tween(group, Theme.Tween.Normal, { GroupTransparency = 1, Position = UDim2.fromOffset(30, 0) })
	end
	task.delay(0.25, function()
		toast:Destroy()
	end)
end

local function pushToast(amount: number, reason: string)
	order -= 1 -- newest on top
	local toast: Frame = Theme.new("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(300, 30),
		LayoutOrder = order,
		Parent = stack,
	})
	local group: CanvasGroup = Theme.new("CanvasGroup", {
		Name = "Group",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(-20, 0),
		GroupTransparency = 1,
		Parent = toast,
	})
	Theme.label({
		RichText = true,
		Text = string.format('<font color="%s">+%d</font>  %s', Theme.hex(Theme.Colors.Accent), math.floor(amount + 0.5), Theme.escape(string.upper(reason))),
		Font = Theme.Fonts.Bold,
		TextSize = 22,
		TextStrokeTransparency = 0.6,
		Size = UDim2.fromScale(1, 1),
		Parent = group,
	})
	local scale: UIScale = Theme.new("UIScale", { Scale = 1.25, Parent = group })
	Theme.tween(group, Theme.Tween.Pop, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
	Theme.tween(scale, Theme.Tween.Pop, { Scale = 1 })

	table.insert(toasts, toast)
	while #toasts > MAX_TOASTS do
		removeToast(toasts[1])
	end
	task.delay(TOAST_LIFETIME, removeToast, toast)
end

local function playNextBanner()
	if bannerBusy then
		return
	end
	local item = table.remove(bannerQueue, 1)
	if not item then
		return
	end
	bannerBusy = true
	local group: CanvasGroup = Theme.new("CanvasGroup", {
		Name = "LevelUp",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 120),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Parent = bannerHolder,
	}, { Theme.corner(8) })
	Theme.new("Frame", {
		BackgroundColor3 = Theme.Colors.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 4),
		Parent = group,
	})
	Theme.label({
		Text = item.title,
		Font = Theme.Fonts.Title,
		TextSize = 44,
		TextColor3 = Theme.Colors.Accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 14),
		Size = UDim2.new(1, 0, 0, 52),
		Parent = group,
	})
	Theme.label({
		Text = item.subtitle,
		Font = Theme.Fonts.Bold,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = group,
	})
	local scale: UIScale = Theme.new("UIScale", { Scale = 0.7, Parent = group })
	Theme.tween(group, Theme.Tween.Pop, { GroupTransparency = 0 })
	Theme.tween(scale, Theme.Tween.Pop, { Scale = 1 })
	task.delay(2.4, function()
		Theme.tween(group, Theme.Tween.Slow, { GroupTransparency = 1 })
		Theme.tween(scale, Theme.Tween.Slow, { Scale = 1.08 })
		task.wait(0.5)
		group:Destroy()
		bannerBusy = false
		playNextBanner()
	end)
end

local function queueBanner(title: string, subtitle: string)
	table.insert(bannerQueue, { title = title, subtitle = subtitle })
	playNextBanner()
end

local function onXP(p: Types.XPGainPayload)
	if typeof(p) ~= "table" then
		return
	end
	if typeof(p.amount) == "number" and p.amount > 0 then
		pushToast(p.amount, if typeof(p.reason) == "string" then p.reason else "XP")
	end
	if p.leveledUp and p.account then
		queueBanner("LEVEL UP", "Rank " .. tostring(p.account.level) .. " reached")
	end
	if p.weaponLeveledUp and p.weapon then
		queueBanner("WEAPON LEVEL UP", string.upper(Theme.weaponName(p.weaponId)) .. "  -  LEVEL " .. tostring(p.weapon.level))
	end
end

function XPToast.init()
	local gui, canvas = Theme.screen("XPToast", 20)
	stack = Theme.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 140, 0.5, -40),
		Size = UDim2.fromOffset(300, MAX_TOASTS * 34),
		Parent = canvas,
	}, { Theme.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Bottom) })
	bannerHolder = Theme.new("Frame", {
		Name = "Banners",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromOffset(620, 120),
		Parent = canvas,
	})
	Theme.mount(gui)
	ClientState.XPGain:Connect(onXP)
end

return XPToast
