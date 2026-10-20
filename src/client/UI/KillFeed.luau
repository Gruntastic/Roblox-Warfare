--!strict
-- Top-right kill feed: last 5 entries, team-coloured names, fades out after a few seconds.
local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local KillFeed = {}

local MAX_ENTRIES = 5
local LIFETIME = 6

local container: Frame
local entries: { Frame } = {}
local order = 0
local localName = Players.LocalPlayer.Name

local function nameColor(name: string, teamId: string?): Color3
	if teamId then
		return Theme.teamColor(teamId)
	end
	-- FFA / unknown team: highlight self with the accent, everyone else neutral.
	return if name == localName then Theme.Colors.Accent else Theme.Colors.Text
end

local function coloured(name: string, teamId: string?): string
	return string.format('<font color="%s">%s</font>', Theme.hex(nameColor(name, teamId)), Theme.escape(name))
end

local function remove(entry: Frame)
	local i = table.find(entries, entry)
	if not i then
		return
	end
	table.remove(entries, i)
	local group = entry:FindFirstChild("Group") :: CanvasGroup?
	if group then
		Theme.tween(group, Theme.Tween.Slow, { GroupTransparency = 1 })
	end
	task.delay(0.5, function()
		entry:Destroy()
	end)
end

local function push(p: Types.KillFeedPayload)
	if typeof(p) ~= "table" or typeof(p.victim) ~= "string" then
		return
	end
	local parts = {}
	if p.killer and p.killer ~= p.victim then
		table.insert(parts, coloured(p.killer, p.killerTeam))
		local weapon = if p.weaponId then Theme.weaponName(p.weaponId) else ""
		local tag = if weapon ~= "" then string.upper(weapon) else "KILLED"
		table.insert(parts, string.format('<font color="%s" size="15">  %s  </font>', Theme.hex(Theme.Colors.TextDim), Theme.escape(tag)))
	else
		table.insert(parts, string.format('<font color="%s" size="15">ELIMINATED  </font>', Theme.hex(Theme.Colors.TextDim)))
	end
	table.insert(parts, coloured(p.victim, p.victimTeam))
	if p.headshot then
		table.insert(parts, string.format('<font color="%s" size="15">  HEADSHOT</font>', Theme.hex(Theme.Colors.Accent)))
	end

	local involvesMe = p.killer == localName or p.victim == localName
	order -= 1 -- newest on top
	local entry: Frame = Theme.new("Frame", {
		Name = "Entry",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		LayoutOrder = order,
		Parent = container,
	})
	local group: CanvasGroup = Theme.new("CanvasGroup", {
		Name = "Group",
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = if involvesMe then 0.05 else 0.3,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		GroupTransparency = 1,
		Parent = entry,
	}, { Theme.corner(4) :: Instance, Theme.padding(0, 12) })
	if involvesMe then
		Theme.new("Frame", {
			BackgroundColor3 = Theme.Colors.Accent,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 3, 1, 0),
			Position = UDim2.fromOffset(-12, 0),
			Parent = group,
		})
	end
	Theme.label({
		RichText = true,
		Text = table.concat(parts),
		Font = Theme.Fonts.Bold,
		TextSize = 18,
		TextTruncate = Enum.TextTruncate.None,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = group,
	})
	Theme.tween(group, Theme.Tween.Normal, { GroupTransparency = 0 })

	table.insert(entries, entry)
	while #entries > MAX_ENTRIES do
		remove(entries[1])
	end
	task.delay(LIFETIME, remove, entry)
end

function KillFeed.init()
	local gui, canvas = Theme.screen("KillFeed", 12)
	container = Theme.new("Frame", {
		Name = "Feed",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 84),
		Size = UDim2.fromOffset(620, MAX_ENTRIES * 40),
		Parent = canvas,
	}, { Theme.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Right) })
	Theme.mount(gui)

	ClientState.KillFeed:Connect(push)
	ClientState.MatchStateChanged:Connect(function(ms)
		gui.Enabled = ms.phase ~= "Lobby"
	end)
end

return KillFeed
