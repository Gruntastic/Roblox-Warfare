--!strict
-- On-screen controls for touch devices (Phase 7). Shown while deployed on a touch-only device (or in
-- Studio with workspace attribute QA_ForceTouch = true). Buttons report through
-- ClientState.TouchAction(name, down); WeaponController and MovementController act on them, so the
-- server sees exactly the same requests as from a mouse or gamepad. Moving and looking use Roblox's
-- default thumbstick and camera drag, which these buttons leave free (left half and the middle).
--
-- Layout (right thumb, kept above the streak tray and ammo panel in the bottom-right corner): a large FIRE button, ADS beside it, RELOAD / SWAP above, and MELEE, CROUCH
-- and SPRINT in a column at the right edge above the jump button. A small FIRE on the left lets
-- players shoot while steering the camera with the right thumb.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.ClientState)

local TouchControls = {}

local C = Theme.Colors

type Spec = { name: string, text: string, size: number, pos: UDim2, hold: boolean?, toggle: boolean? }

-- Positions are anchored at each button's centre, in the Theme's virtual canvas (820 units tall on
-- touch), from the top so the cluster stays above the streak tray and ammo panel on every screen.
local SPECS: { Spec } = {
	{ name = "Fire", text = "FIRE", size = 118, pos = UDim2.new(1, -160, 0, 330), hold = true },
	{ name = "FireLeft", text = "FIRE", size = 84, pos = UDim2.new(0, 110, 0.42, 0), hold = true },
	{ name = "ADS", text = "AIM", size = 84, pos = UDim2.new(1, -290, 0, 360), toggle = true },
	{ name = "Reload", text = "RELOAD", size = 68, pos = UDim2.new(1, -160, 0, 190) },
	{ name = "Swap", text = "SWAP", size = 68, pos = UDim2.new(1, -270, 0, 240) },
	{ name = "Melee", text = "MELEE", size = 60, pos = UDim2.new(1, -56, 0, 130) },
	{ name = "Crouch", text = "CROUCH", size = 60, pos = UDim2.new(1, -56, 0, 210), toggle = true },
	{ name = "Sprint", text = "SPRINT", size = 60, pos = UDim2.new(1, -56, 0, 290), toggle = true },
}

local gui: ScreenGui
local canvas: Frame
local buttons: { [string]: TextButton } = {}
local toggled: { [string]: boolean } = {}

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function paint(name: string, down: boolean)
	local b = buttons[name]
	if b then
		b.BackgroundColor3 = if down then C.Accent else C.Panel
		b.TextColor3 = if down then C.OnAccent else C.Text
	end
end

local function resetToggles()
	for name in toggled do
		toggled[name] = false
		paint(name, false)
	end
end

local function build(spec: Spec)
	local action = if spec.name == "FireLeft" then "Fire" else spec.name
	local b: TextButton = Theme.new("TextButton", {
		Name = spec.name,
		Text = spec.text,
		Font = Theme.Fonts.Bold,
		TextSize = math.floor(spec.size * 0.2),
		TextColor3 = C.Text,
		AutoButtonColor = false,
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.35,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = spec.pos,
		Size = UDim2.fromOffset(spec.size, spec.size),
		Selectable = false,
		Parent = canvas,
	}, { Theme.new("UICorner", { CornerRadius = UDim.new(0.5, 0) }) :: Instance, Theme.stroke(C.Accent, 2, 0.4) })
	buttons[spec.name] = b
	local activeInput: InputObject? = nil
	b.InputBegan:Connect(function(input: InputObject)
		if not isPress(input) or activeInput then
			return
		end
		activeInput = input
		if spec.toggle then
			toggled[spec.name] = not toggled[spec.name]
			paint(spec.name, toggled[spec.name])
		else
			paint(spec.name, true)
		end
		ClientState.TouchAction:Fire(action, true)
	end)
	local function release(input: InputObject)
		if input ~= activeInput then
			return
		end
		activeInput = nil
		if not spec.toggle then
			paint(spec.name, false)
		end
		if spec.hold then
			ClientState.TouchAction:Fire(action, false)
		end
	end
	b.InputEnded:Connect(release)
	-- a finger that slides off the button still ends the press
	UserInputService.InputEnded:Connect(release)
end

local function refresh()
	local show = ClientState.deployed and Theme.isTouchOnly() and next(ClientState.menus) == nil
	gui.Enabled = show
	if not show then
		resetToggles()
	end
end

function TouchControls.isShown(): boolean
	return (gui :: ScreenGui?) ~= nil and gui.Enabled
end

function TouchControls.init()
	gui, canvas = Theme.screen("TouchControls", 6)
	gui.Enabled = false
	for _, spec in SPECS do
		build(spec)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ClientState.DeployedChanged:Connect(function()
		resetToggles()
		refresh()
	end)
	ClientState.MenuChanged:Connect(refresh)
	ClientState.AdsChanged:Connect(function(on: boolean)
		-- keep the AIM button in step when ADS ends for another reason (reload, sprint, death)
		toggled.ADS = on
		paint("ADS", on)
	end)
	workspace:GetAttributeChangedSignal("QA_ForceTouch"):Connect(refresh)
	refresh()
end

return TouchControls
