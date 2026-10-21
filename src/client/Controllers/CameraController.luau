--!strict
-- Lobby / spectator camera when not deployed; default first-person camera when deployed.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientState = require(script.Parent.Parent.ClientState)
local StagingScene = require(script.Parent.StagingScene)

local player = Players.LocalPlayer
local CameraController = {}

local drift = 0
local facedCharacter: Model? = nil -- the character whose spawn facing the camera already took

local function lobbyCFrame(): CFrame?
	local map = workspace:FindFirstChild("Map")
	local part = map and map:FindFirstChild("LobbyCamera") :: BasePart?
	return part and part.CFrame
end

local function update(dt: number)
	local cam = workspace.CurrentCamera
	if ClientState.deployed then
		if cam.CameraType ~= Enum.CameraType.Custom then
			cam.CameraType = Enum.CameraType.Custom
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				cam.CameraSubject = humanoid
			end
		end
		-- Once per life, look where the spawn faces. Otherwise the camera keeps its old yaw and the
		-- first-person character turns to match it, often towards the spawn's back wall.
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and root and character ~= facedCharacter then
			facedCharacter = character
			local look = root.CFrame.LookVector
			local eye = root.Position + Vector3.new(0, 1.5, 0)
			cam.CFrame = CFrame.lookAt(eye, eye + Vector3.new(look.X, 0, look.Z))
		end
		UserInputService.MouseIconEnabled = false
		return
	end
	-- [Phase 4 / UI] S&D spectating: UI/Objectives sets this LocalPlayer attribute while dead in a
	-- live round and points CameraSubject at a living teammate. Follow it instead of the death /
	-- lobby views. On respawn the branch above sees CameraType ~= Custom and restores our own view.
	if player:GetAttribute("COR_Spectating") == true then
		if cam.CameraType ~= Enum.CameraType.Follow then
			cam.CameraType = Enum.CameraType.Follow
		end
		UserInputService.MouseIconEnabled = true
		return
	end
	-- Keep the death view on our body briefly; otherwise show the lobby overview.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 and character and character.Parent then
		cam.CameraType = Enum.CameraType.Scriptable
		local head = character:FindFirstChild("Head") :: BasePart?
		if head then
			local target = CFrame.lookAt(head.Position + Vector3.new(6, 7, 6), head.Position)
			cam.CFrame = cam.CFrame:Lerp(target, math.min(1, dt * 3))
		end
		UserInputService.MouseIconEnabled = true
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	-- the lobby films the staging room (the Lobby screen turns it on while it is shown)
	if StagingScene.isActive() then
		cam.CFrame = StagingScene.cameraCFrame()
		cam.FieldOfView = StagingScene.FOV
		return
	end
	local base = lobbyCFrame()
	if base then
		drift += dt
		cam.CFrame = base * CFrame.Angles(0, math.sin(drift * 0.05) * 0.25, 0)
	end
end

function CameraController.init() end

function CameraController.start()
	RunService:BindToRenderStep("COR_Camera", Enum.RenderPriority.Camera.Value + 2, update)
end

return CameraController
