--!strict
-- Shared UI theme + construction helpers. Helper module only: exports no init/start.
--
-- Responsive strategy: every ScreenGui gets a "Canvas" frame driven by a UIScale so that the
-- canvas always has a virtual height of REF_HEIGHT (1080 on desktop, smaller on touch-only
-- devices so text stays legible). Layouts inside use Scale for big containers and Offset (in
-- virtual 1080p pixels) for text and fine detail, so 1280x720 through 4K and phones all look alike.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModesConfig = require(Shared.Config.Modes)
local WeaponsConfig = require(Shared.Config.Weapons)
local CosmeticsConfig = require(Shared.Config.Cosmetics)
local KillstreaksConfig = require(Shared.Config.Killstreaks)
local ClientState = require(script.Parent.Parent.ClientState)
local Types = require(Shared.Types)

local Theme = {}

Theme.Colors = {
	Backdrop = Color3.fromRGB(8, 10, 12),
	Panel = Color3.fromRGB(16, 19, 22),
	PanelLight = Color3.fromRGB(28, 32, 37),
	PanelHover = Color3.fromRGB(40, 45, 51),
	Stroke = Color3.fromRGB(70, 76, 84),
	Text = Color3.fromRGB(236, 238, 240),
	TextDim = Color3.fromRGB(168, 174, 182),
	TextMuted = Color3.fromRGB(105, 111, 119),
	Accent = Color3.fromRGB(255, 182, 36), -- the single UI accent (signal amber)
	AccentDark = Color3.fromRGB(150, 104, 14),
	OnAccent = Color3.fromRGB(18, 16, 10),
	Danger = Color3.fromRGB(232, 64, 52),
	Positive = Color3.fromRGB(120, 210, 120),
	Locked = Color3.fromRGB(60, 63, 68),
	White = Color3.new(1, 1, 1),
	Black = Color3.new(0, 0, 0),
}

Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Medium = Enum.Font.GothamMedium,
	Regular = Enum.Font.Gotham,
}

Theme.PanelTransparency = 0.18

-- Seconds past the mode respawnDelay after which a dead, still-undeployed player falls back to the
-- Lobby screen (with its DEPLOY button) instead of the death screen. Shared by Lobby + DeathScreen.
Theme.RespawnGrace = 2.5

-- Search and Destroy (no respawns): seconds the death screen / death cam stays up before the
-- spectator view (UI/Objectives) takes over. Shared by DeathScreen + Objectives.
Theme.SnDDeathHold = 2.5

Theme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
}

Theme.Modes = ModesConfig.Modes
Theme.Match = ModesConfig.Match
Theme.Weapons = WeaponsConfig

local localPlayer = Players.LocalPlayer

---------------------------------------------------------------------------------------------
-- Instance construction
---------------------------------------------------------------------------------------------

-- Creates an instance, applies props (Parent applied last), parents children. Returns `any` so
-- call sites can annotate the concrete class: `local f: Frame = Theme.new("Frame", {...})`.
function Theme.new(className: string, props: { [string]: any }?, children: { any }?): any
	local inst = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			(child :: Instance).Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.corner(radius: number?): UICorner
	return Theme.new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function Theme.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Theme.new("UIStroke", {
		Color = color or Theme.Colors.Stroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0.4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.padding(all: number, horizontal: number?): UIPadding
	local h = horizontal or all
	return Theme.new("UIPadding", {
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
	})
end

function Theme.list(direction: Enum.FillDirection?, spacing: number?, hAlign: Enum.HorizontalAlignment?, vAlign: Enum.VerticalAlignment?): UIListLayout
	return Theme.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, spacing or 0),
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = vAlign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- Dark translucent panel with a hairline stroke.
function Theme.panel(props: { [string]: any }?, children: { any }?): Frame
	local base: { [string]: any } = {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local frame: Frame = Theme.new("Frame", base, children)
	Theme.corner(6).Parent = frame
	Theme.stroke().Parent = frame
	return frame
end

function Theme.label(props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Theme.Fonts.Medium,
		TextColor3 = Theme.Colors.Text,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = "",
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	return Theme.new("TextLabel", base)
end

-- Button with hover / press feedback. `style` = "Primary" (accent fill) | "Secondary" (dark).
function Theme.button(props: { [string]: any }?, style: string?): TextButton
	local isPrimary = style == "Primary"
	local idle = if isPrimary then Theme.Colors.Accent else Theme.Colors.PanelLight
	local hover = if isPrimary then Color3.fromRGB(255, 204, 92) else Theme.Colors.PanelHover
	local base: { [string]: any } = {
		AutoButtonColor = false,
		BackgroundColor3 = idle,
		BackgroundTransparency = if isPrimary then 0 else 0.1,
		BorderSizePixel = 0,
		Font = Theme.Fonts.Bold,
		TextColor3 = if isPrimary then Theme.Colors.OnAccent else Theme.Colors.Text,
		TextSize = 20,
		Text = "",
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local button: TextButton = Theme.new("TextButton", base)
	Theme.corner(6).Parent = button
	local scale: UIScale = Theme.new("UIScale", { Parent = button })
	button:SetAttribute("IdleColor", idle)
	button.MouseEnter:Connect(function()
		if button.Active then
			TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = hover }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		local c = button:GetAttribute("IdleColor")
		TweenService:Create(button, Theme.Tween.Fast, { BackgroundColor3 = if typeof(c) == "Color3" then c else idle }):Play()
		TweenService:Create(scale, Theme.Tween.Fast, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		if button.Active then
			TweenService:Create(scale, Theme.Tween.Fast, { Scale = 0.96 }):Play()
		end
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, Theme.Tween.Pop, { Scale = 1 }):Play()
	end)
	return button
end

-- Changes a Theme.button's resting colour (keeps hover logic consistent).
function Theme.setButtonColor(button: TextButton, color: Color3)
	button:SetAttribute("IdleColor", color)
	button.BackgroundColor3 = color
end

-- Thin progress bar. Returns (track, fill); set fill.Size = UDim2.fromScale(alpha, 1).
function Theme.bar(props: { [string]: any }?, fillColor: Color3?): (Frame, Frame)
	local base: { [string]: any } = {
		BackgroundColor3 = Theme.Colors.Black,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local track: Frame = Theme.new("Frame", base)
	Theme.corner(3).Parent = track
	local fill: Frame = Theme.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = fillColor or Theme.Colors.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	})
	Theme.corner(3).Parent = fill
	return track, fill
end

function Theme.tween(inst: Instance, info: TweenInfo, goals: { [string]: any }): Tween
	local t = TweenService:Create(inst, info, goals)
	t:Play()
	return t
end

---------------------------------------------------------------------------------------------
-- Screens + responsive scaling
---------------------------------------------------------------------------------------------

local scaled: { { scale: UIScale, canvas: Frame } } = {}
local currentScale = 1
local cameraConn: RBXScriptConnection? = nil

-- Touch layout. In Studio, workspace attribute QA_ForceTouch = true turns it on with a mouse, so the
-- touch controls can be playtested on a desktop (the buttons also accept mouse clicks).
local function isTouchOnly(): boolean
	if RunService:IsStudio() and workspace:GetAttribute("QA_ForceTouch") == true then
		return true
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end
Theme.isTouchOnly = isTouchOnly

local function computeScale(): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 1
	end
	local vp = camera.ViewportSize
	if vp.X < 2 or vp.Y < 2 then
		return 1
	end
	local refHeight = if isTouchOnly() then 820 else 1080
	local s = vp.Y / refHeight
	-- keep a sane minimum virtual width (very tall/narrow windows): virtual width >= 1280
	local virtualWidth = vp.X / s
	if virtualWidth < 1280 then
		s = vp.X / 1280
	end
	return math.max(s, 0.2)
end

local function applyScale()
	currentScale = computeScale()
	local inv = 1 / currentScale
	for _, entry in scaled do
		entry.scale.Scale = currentScale
		entry.canvas.Size = UDim2.fromScale(inv, inv)
	end
end

local function hookCamera()
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
	end
	applyScale()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(hookCamera)
hookCamera()

function Theme.getScale(): number
	return currentScale
end

-- Creates a ScreenGui (not yet parented) plus a scaled full-screen canvas frame to build into.
function Theme.screen(name: string, displayOrder: number, ignoreInset: boolean?): (ScreenGui, Frame)
	local gui: ScreenGui = Theme.new("ScreenGui", {
		Name = "COR_" .. name,
		ResetOnSpawn = false,
		IgnoreGuiInset = if ignoreInset == nil then true else ignoreInset,
		DisplayOrder = displayOrder,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = true,
	})
	local canvas: Frame = Theme.new("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	local uiScale: UIScale = Theme.new("UIScale", { Parent = canvas })
	table.insert(scaled, { scale = uiScale, canvas = canvas })
	uiScale.Scale = currentScale
	canvas.Size = UDim2.fromScale(1 / currentScale, 1 / currentScale)
	return gui, canvas
end

-- Parents a ScreenGui to PlayerGui without yielding the caller.
function Theme.mount(gui: ScreenGui)
	task.spawn(function()
		gui.Parent = localPlayer:WaitForChild("PlayerGui")
	end)
end

---------------------------------------------------------------------------------------------
-- Data helpers (read-only views of ClientState / Config)
---------------------------------------------------------------------------------------------

function Theme.serverNow(): number
	return workspace:GetServerTimeNow()
end

function Theme.formatTime(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Theme.hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

function Theme.escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

-- Team colour/name: prefer live matchState teams, fall back to Config Match.Teams.
function Theme.teamColor(teamId: string?): Color3
	if not teamId then
		return Theme.Colors.Text
	end
	local ms = ClientState.matchState
	if ms then
		for _, t in ms.teams do
			if t.id == teamId and typeof(t.color) == "Color3" then
				return t.color
			end
		end
	end
	for _, t in Theme.Match.Teams do
		if t.id == teamId then
			return t.color
		end
	end
	return Theme.Colors.Text
end

function Theme.teamName(teamId: string?): string
	if not teamId then
		return ""
	end
	local ms = ClientState.matchState
	if ms then
		for _, t in ms.teams do
			if t.id == teamId then
				return t.displayName
			end
		end
	end
	for _, t in Theme.Match.Teams do
		if t.id == teamId then
			return t.displayName
		end
	end
	return teamId
end

-- The local player's team id according to the latest matchState (nil in FFA / not yet assigned).
function Theme.localTeam(): string?
	local ms = ClientState.matchState
	if not ms then
		return nil
	end
	local uid = localPlayer.UserId
	for _, line in ms.players do
		if line.userId == uid then
			return line.team
		end
	end
	return nil
end

-- Free-for-All match (Phase 4): `teamMode == false`. Older payloads without the field fall back to
-- "no teams listed".
function Theme.isFFA(ms: Types.MatchStatePayload?): boolean
	local state = ms or ClientState.matchState
	if not state then
		return false
	end
	if state.teamMode ~= nil then
		return state.teamMode == false
	end
	return #(state.teams or {}) == 0
end

-- The other team's id (two-team modes), or nil when unknown.
function Theme.otherTeam(teamId: string?): string?
	if not teamId then
		return nil
	end
	local ms = ClientState.matchState
	if ms and ms.teams and #ms.teams > 0 then
		for _, t in ms.teams do
			if t.id ~= teamId then
				return t.id
			end
		end
		return nil
	end
	for _, t in Theme.Match.Teams do
		if t.id ~= teamId then
			return t.id
		end
	end
	return nil
end

-- Current objective kind, or "None". Guards against a stale ObjectiveState from the previous match
-- by cross-checking the mode config of the current MatchState.
function Theme.objectiveKind(): string
	local obj = ClientState.objective
	if not obj or type(obj.kind) ~= "string" then
		return "None"
	end
	local ms = ClientState.matchState
	local mode = if ms then Theme.Modes[ms.modeId] else nil
	if mode and mode.objective and mode.objective ~= obj.kind then
		return "None"
	end
	return obj.kind
end

-- Search and Destroy is running (used by the death screen, lobby and HUD).
function Theme.isSnD(): boolean
	local ms = ClientState.matchState
	local mode = if ms then Theme.Modes[ms.modeId] else nil
	if mode and mode.objective then
		return mode.objective == "SnD"
	end
	return Theme.objectiveKind() == "SnD"
end

function Theme.weaponName(weaponId: string?): string
	if not weaponId then
		return ""
	end
	local def = WeaponsConfig[weaponId]
	if def then
		return def.displayName
	end
	-- Phase 5: kills made by a killstreak use the weapon id "Streak:<StreakId>"
	local streakId = string.match(weaponId, "^Streak:(.+)$")
	local streak = if streakId then KillstreaksConfig.byId[streakId] else nil
	return if streak then streak.name else weaponId
end

---------------------------------------------------------------------------------------------
-- Phase 5: titles and prestige emblems
---------------------------------------------------------------------------------------------

Theme.Cosmetics = CosmeticsConfig
Theme.Killstreaks = KillstreaksConfig

-- Display name of a title id in capitals ("" for unknown / missing ids).
function Theme.titleName(titleId: string?): string
	local def = if type(titleId) == "string" then CosmeticsConfig.titleById[titleId] else nil
	return if def then string.upper(def.name) else ""
end

-- RichText "Name  TITLE" with the title in small muted caps. Escapes the player name.
function Theme.nameWithTitle(name: string, titleId: string?, titleSize: number?): string
	local title = Theme.titleName(titleId)
	local escaped = Theme.escape(name)
	if title == "" then
		return escaped
	end
	return string.format(
		'%s  <font size="%d" color="%s">%s</font>',
		escaped,
		titleSize or 11,
		Theme.hex(Theme.Colors.TextMuted),
		Theme.escape(title)
	)
end

-- Square prestige emblem badge (catalogue colour + roman numeral glyph), or nil for unknown ids.
function Theme.emblemBadge(emblemId: string?, size: number, props: { [string]: any }?): Frame?
	local def = if type(emblemId) == "string" then CosmeticsConfig.emblemById[emblemId] else nil
	if not def then
		return nil
	end
	local base: { [string]: any } = {
		Name = "Emblem",
		BackgroundColor3 = def.color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		Rotation = 0,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local badge: Frame = Theme.new("Frame", base)
	Theme.corner(math.max(2, math.floor(size * 0.18))).Parent = badge
	Theme.new("UIStroke", { Color = Theme.Colors.Black, Transparency = 0.5, Thickness = 1, Parent = badge })
	Theme.label({
		Name = "Glyph",
		Text = def.glyph,
		Font = Theme.Fonts.Title,
		TextSize = math.max(8, math.floor(size * (if #def.glyph >= 3 then 0.38 else 0.5))),
		TextColor3 = Theme.Colors.OnAccent,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 1),
		Parent = badge,
	})
	return badge
end

-- "DustlineTerminal" -> "Dustline Terminal" (no shared map display-name table on the client).
function Theme.mapDisplayName(mapId: string): string
	local ms = ClientState.matchState
	if ms and ms.mapId == mapId and ms.mapName ~= "" then
		return ms.mapName
	end
	return (mapId:gsub("(%l)(%u)", "%1 %2"))
end

function Theme.respawnDelay(): number
	local ms = ClientState.matchState
	local mode = (ms and Theme.Modes[ms.modeId]) or Theme.Modes[Theme.Match.DefaultMode] or Theme.Modes.TDM
	return if mode then mode.respawnDelay else 3
end

return Theme
