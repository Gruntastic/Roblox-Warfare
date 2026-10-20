--!strict
-- "ELIMINATED" overlay shown when the local character dies during Playing, with killer name
-- (from the most recent KillFeed entry naming us as victim) and a respawn countdown.
local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)
local Types = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Types)

local DeathScreen = {}

local KILL_MATCH_WINDOW = 3 -- seconds a KillFeed entry and the death event may be apart

local localName = Players.LocalPlayer.Name
local root: Frame
local center: CanvasGroup
local centerScale: UIScale
local killerLabel: TextLabel
local weaponLabel: TextLabel
local countdownLabel: TextLabel
local showing = false
local showToken = 0
local lastDeployed = ClientState.deployed
local lastKill: Types.KillFeedPayload? = nil
local lastKillAt = -math.huge

local function applyKiller(p: Types.KillFeedPayload?)
	if p and p.killer and p.killer ~= localName then
		killerLabel.RichText = true
		killerLabel.Text = string.format('KILLED BY  <font color="%s">%s</font>', Theme.hex(Theme.teamColor(p.killerTeam)), Theme.escape(p.killer))
		local parts = {}
		if p.weaponId then
			table.insert(parts, string.upper(Theme.weaponName(p.weaponId)))
		end
		if p.headshot then
			table.insert(parts, "HEADSHOT")
		end
		weaponLabel.Text = table.concat(parts, "  //  ")
	else
		killerLabel.RichText = false
		killerLabel.Text = "KILLED IN ACTION"
		weaponLabel.Text = ""
	end
end

local function hide()
	if not showing then
		return
	end
	showing = false
	showToken += 1
	Theme.tween(root, Theme.Tween.Normal, { BackgroundTransparency = 1 })
	Theme.tween(center, Theme.Tween.Normal, { GroupTransparency = 1 })
	local token = showToken
	task.delay(0.25, function()
		if token == showToken then
			root.Visible = false
		end
	end)
end

local function show()
	showing = true
	showToken += 1
	local token = showToken
	applyKiller(if os.clock() - lastKillAt <= KILL_MATCH_WINDOW then lastKill else nil)
	root.Visible = true
	root.BackgroundTransparency = 1
	center.GroupTransparency = 1
	centerScale.Scale = 1.15
	Theme.tween(centerScale, Theme.Tween.Pop, { Scale = 1 })
	Theme.tween(root, Theme.Tween.Normal, { BackgroundTransparency = 0.55 })
	Theme.tween(center, Theme.Tween.Normal, { GroupTransparency = 0 })

	local endsAt = os.clock() + Theme.respawnDelay()
	task.spawn(function()
		while token == showToken do
			local left = endsAt - os.clock()
			if left > 0 then
				countdownLabel.Text = string.format("RESPAWNING IN %d", math.ceil(left))
			elseif left > -Theme.RespawnGrace then
				countdownLabel.Text = "RESPAWNING..."
			else
				-- no respawn arrived; the Lobby screen takes over with its Deploy button
				hide()
				break
			end
			task.wait(0.1)
		end
	end)
end

function DeathScreen.init()
	local gui, canvas = Theme.screen("DeathScreen", 25)
	root = Theme.new("Frame", {
		Name = "Death",
		BackgroundColor3 = Color3.fromRGB(40, 4, 4),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = canvas,
	})
	Theme.new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.5, 0.75),
			NumberSequenceKeypoint.new(1, 0.2),
		}),
		Rotation = 90,
		Parent = root,
	})
	center = Theme.new("CanvasGroup", {
		Name = "Center",
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(900, 240),
		Parent = root,
	})
	centerScale = Theme.new("UIScale", { Parent = center })
	Theme.label({
		Text = "ELIMINATED",
		Font = Theme.Fonts.Title,
		TextSize = 84,
		TextColor3 = Theme.Colors.Danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 96),
		Parent = center,
	})
	Theme.new("Frame", {
		BackgroundColor3 = Theme.Colors.Accent,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 102),
		Size = UDim2.fromOffset(120, 4),
		Parent = center,
	})
	killerLabel = Theme.label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 118),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = center,
	})
	weaponLabel = Theme.label({
		Text = "",
		Font = Theme.Fonts.Medium,
		TextSize = 20,
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 160),
		Size = UDim2.new(1, 0, 0, 28),
		Parent = center,
	})
	countdownLabel = Theme.label({
		Text = "",
		Font = Theme.Fonts.Bold,
		TextSize = 22,
		TextColor3 = Theme.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 204),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = center,
	})
	Theme.mount(gui)

	ClientState.KillFeed:Connect(function(p: Types.KillFeedPayload)
		if typeof(p) == "table" and p.victim == localName then
			lastKill = p
			lastKillAt = os.clock()
			if showing then
				applyKiller(p) -- feed entry arrived after the death event
			end
		end
	end)
	ClientState.DeployedChanged:Connect(function(deployed: boolean)
		local was = lastDeployed
		lastDeployed = deployed
		if deployed then
			hide()
			return
		end
		local ms = ClientState.matchState
		if was and not showing and ms and ms.phase == "Playing" then
			show()
		end
	end)
	ClientState.MatchStateChanged:Connect(function(ms)
		if ms.phase ~= "Playing" then
			hide()
		end
	end)
end

return DeathScreen
