--!strict
-- Small stacked banners for ClientState.Notify(text, kind). kind: "Info" | "Warning" | "LevelUp".
local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)

local Notifications = {}

local MAX_VISIBLE = 4
local DURATION = 3.5

local container: Frame
local active: { Frame } = {}
local order = 0

local function kindColor(kind: string): Color3
	if kind == "Warning" then
		return Theme.Colors.Danger
	elseif kind == "LevelUp" then
		return Theme.Colors.Accent
	end
	return Theme.Colors.TextDim
end

local function dismiss(banner: Frame)
	local i = table.find(active, banner)
	if not i then
		return
	end
	table.remove(active, i)
	local group = banner:FindFirstChild("Group") :: CanvasGroup?
	if group then
		Theme.tween(group, Theme.Tween.Normal, { GroupTransparency = 1 })
	end
	task.delay(0.25, function()
		banner:Destroy()
	end)
end

local function show(text: string, kind: string?)
	local k = kind or "Info"
	order += 1
	local banner: Frame = Theme.new("Frame", {
		Name = "Banner",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(560, 44),
		LayoutOrder = order,
		Parent = container,
	})
	local group: CanvasGroup = Theme.new("CanvasGroup", {
		Name = "Group",
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, -12),
		GroupTransparency = 1,
		Parent = banner,
	}, { Theme.corner(6) })
	Theme.new("Frame", {
		Name = "Stripe",
		BackgroundColor3 = kindColor(k),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 5, 1, 0),
		Parent = group,
	})
	Theme.label({
		Text = text,
		Font = if k == "Info" then Theme.Fonts.Medium else Theme.Fonts.Bold,
		TextSize = 19,
		TextColor3 = if k == "Info" then Theme.Colors.Text else kindColor(k),
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -30, 1, 0),
		Parent = group,
	})
	Theme.tween(group, Theme.Tween.Pop, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })

	table.insert(active, banner)
	while #active > MAX_VISIBLE do
		dismiss(active[1])
	end
	task.delay(if k == "Warning" then DURATION + 1.5 else DURATION, dismiss, banner)
end

function Notifications.init()
	local gui, canvas = Theme.screen("Notifications", 40)
	container = Theme.new("Frame", {
		Name = "Stack",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(560, 4 * 52),
		Parent = canvas,
	}, { Theme.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })
	Theme.mount(gui)

	ClientState.Notify:Connect(function(text: string, kind: string)
		if typeof(text) == "string" and text ~= "" then
			show(text, kind)
		end
	end)
end

return Notifications
