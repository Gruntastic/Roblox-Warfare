--!strict
-- Procedural operator animation on R15 rigs, layered on top of the Animator each frame
-- (Motor6D.Transform written in PreSimulation, after animations are applied):
--   * In matches, every other player's character holds its rifle at the ready: both arms on the
--     torso-mounted world weapon, upper body and head following their aim pitch (character
--     attribute AimPitch, sent by this controller for the local player), and a lowered carry while
--     sprinting.
--   * The lobby staging room calls OperatorAnimator.stagingPose for its display operators: rifle
--     ready, breathing, weight shifts, head turns and the occasional weapon check, desynchronised
--     per operator by `seed`.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientState = require(script.Parent.Parent.ClientState)
local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local OperatorAnimator = {}

local player = Players.LocalPlayer
local rad = math.rad

local SEND_INTERVAL = 0.1
local SEND_THRESHOLD = 1.5 -- degrees
local SPRINT_SPEED = 19 -- studs/s above which the carry lowers

type Joints = {
	waist: Motor6D?,
	neck: Motor6D?,
	root: Motor6D?,
	rShoulder: Motor6D?,
	rElbow: Motor6D?,
	lShoulder: Motor6D?,
	lElbow: Motor6D?,
}

local jointCache: { [Model]: Joints } = setmetatable({}, { __mode = "k" }) :: any
local carry: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- 0 ready .. 1 sprint carry

local function motor(model: Model, partName: string, jointName: string): Motor6D?
	local part = model:FindFirstChild(partName)
	local m = part and part:FindFirstChild(jointName)
	return if m and m:IsA("Motor6D") then m else nil
end

local function jointsOf(model: Model): Joints
	local j = jointCache[model]
	if j and j.rShoulder and j.rShoulder.Parent then
		return j
	end
	local fresh: Joints = {
		waist = motor(model, "UpperTorso", "Waist"),
		neck = motor(model, "Head", "Neck"),
		root = motor(model, "LowerTorso", "Root"),
		rShoulder = motor(model, "RightUpperArm", "RightShoulder"),
		rElbow = motor(model, "RightLowerArm", "RightElbow"),
		lShoulder = motor(model, "LeftUpperArm", "LeftShoulder"),
		lElbow = motor(model, "LeftLowerArm", "LeftElbow"),
	}
	jointCache[model] = fresh
	return fresh
end

-- Rotation applied X (raise forward) first, then Y (swing across the body) in torso axes.
local function arm(raise: number, across: number): CFrame
	return CFrame.Angles(0, rad(across), 0) * CFrame.Angles(rad(raise), 0, 0)
end

-- Rifle pose for the arms; `low` 0 = shouldered ready, 1 = lowered carry.
local function rifleArms(j: Joints, low: number)
	if j.rShoulder then
		j.rShoulder.Transform = arm(40 - 22 * low, 18)
	end
	if j.rElbow then
		j.rElbow.Transform = CFrame.Angles(rad(75 - 10 * low), 0, 0)
	end
	if j.lShoulder then
		j.lShoulder.Transform = arm(80 - 35 * low, -36 + 6 * low)
	end
	if j.lElbow then
		j.lElbow.Transform = CFrame.Angles(rad(15 + 20 * low), 0, 0)
	end
end

-- Exposed for the staging room: one display operator at time `t`.
function OperatorAnimator.stagingPose(model: Model, t: number, seed: number)
	local j = jointsOf(model)
	local s = seed * 1.7
	local breathe = math.sin(t * 1.6 + s)
	-- every ~9 s: a 1.6 s weapon check (look down at the rifle, rotate it in)
	local cycle = (t + seed * 3.1) % 9
	local check = if cycle < 1.6 then math.sin(cycle / 1.6 * math.pi) else 0
	local low = 0.55 + 0.1 * math.sin(t * 0.37 + s) - 0.45 * check
	rifleArms(j, low)
	if j.waist then
		j.waist.Transform = CFrame.Angles(rad(1.2 * breathe - 6 * check), rad(4 * math.sin(t * 0.21 + s) + 14 * check), 0)
	end
	if j.neck then
		local look = math.sin(t * 0.29 + s * 2) * 18 * (1 - check)
		j.neck.Transform = CFrame.Angles(rad(-3 + 1.5 * breathe - 22 * check), rad(look), 0)
	end
	if j.root then
		j.root.Transform = CFrame.new(0, 0.03 * breathe, 0) * CFrame.Angles(0, 0, rad(1.6 * math.sin(t * 0.45 + s)))
	end
end

local function poseCharacter(character: Model, dt: number)
	local j = jointsOf(character)
	if not j.rShoulder then
		return -- not R15
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local v = if root then root.AssemblyLinearVelocity else Vector3.zero
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local target = if speed > SPRINT_SPEED then 1 else 0
	local c = carry[character] or 0
	c += (target - c) * math.min(1, dt * 8)
	carry[character] = c
	rifleArms(j, c)
	local pitch = character:GetAttribute("AimPitch")
	local p = if type(pitch) == "number" then pitch * (1 - c) else 0
	if j.waist then
		-- absolute, never multiplied: a joint no animation drives would otherwise accumulate
		j.waist.Transform = CFrame.Angles(rad(p * 0.55), 0, 0)
	end
	if j.neck then
		j.neck.Transform = CFrame.Angles(rad(p * 0.45), 0, 0)
	end
end

local lastSent = 0
local lastPitch = 999

local function sendPitch()
	if not ClientState.deployed then
		return
	end
	local now = os.clock()
	if now - lastSent < SEND_INTERVAL then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local pitch = math.deg(math.asin(math.clamp(cam.CFrame.LookVector.Y, -1, 1)))
	if math.abs(pitch - lastPitch) < SEND_THRESHOLD then
		return
	end
	lastSent = now
	lastPitch = pitch
	Net.event("AimPitch"):FireServer(pitch)
end

function OperatorAnimator.init() end

function OperatorAnimator.start()
	RunService.PreSimulation:Connect(function(dt: number)
		for _, other in Players:GetPlayers() do
			local character = other.Character
			if other ~= player and character and character:GetAttribute("EquippedWeapon") ~= nil then
				poseCharacter(character, dt)
			end
		end
		sendPitch()
	end)
end

return OperatorAnimator
