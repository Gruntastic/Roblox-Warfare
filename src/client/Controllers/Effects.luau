--!strict
-- Pooled client-side visual effects: tracers, impacts, muzzle flashes. Cosmetic only.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Effects = {}

local POOL_SIZE = 48
local tracerPool: { BasePart } = {}
local impactPool: { BasePart } = {}
local folder: Folder

local function effectsFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "ClientEffects"
	f.Parent = workspace.CurrentCamera
	folder = f
	return f
end

local function newTracer(): BasePart
	local p = Instance.new("Part")
	p.Name = "Tracer"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 214, 140)
	p.Size = Vector3.new(0.06, 0.06, 1)
	p.Transparency = 1
	p.Parent = effectsFolder()
	return p
end

local function newImpact(): BasePart
	local p = Instance.new("Part")
	p.Name = "Impact"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 190, 110)
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.35, 0.35, 0.35)
	p.Transparency = 1
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Enabled = false
	dust.Lifetime = NumberRange.new(0.25, 0.5)
	dust.Speed = NumberRange.new(4, 9)
	dust.SpreadAngle = Vector2.new(35, 35)
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.9) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Color = ColorSequence.new(Color3.fromRGB(190, 175, 150))
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Parent = p
	p.Parent = effectsFolder()
	return p
end

local function take(pool: { BasePart }, factory: () -> BasePart): BasePart
	local p = table.remove(pool)
	if p and p.Parent then
		return p
	end
	return factory()
end

function Effects.tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 1 then
		return
	end
	local p = take(tracerPool, newTracer)
	local visible = math.min(length, 12)
	p.Size = Vector3.new(0.06, 0.06, visible)
	local dir = (to - from).Unit
	local startCF = CFrame.lookAt(from + dir * (visible / 2), to)
	p.CFrame = startCF
	p.Transparency = 0.15
	local travel = math.max(length - visible, 0)
	local duration = math.clamp(length / 900, 0.04, 0.25)
	local tween = TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = startCF + dir * travel,
		Transparency = 0.7,
	})
	tween:Play()
	tween.Completed:Once(function()
		p.Transparency = 1
		if #tracerPool < POOL_SIZE then
			table.insert(tracerPool, p)
		else
			p:Destroy()
		end
	end)
end

function Effects.impact(position: Vector3, normal: Vector3?)
	local p = take(impactPool, newImpact)
	p.CFrame = CFrame.lookAt(position, position + (normal or Vector3.yAxis)) * CFrame.Angles(-math.pi / 2, 0, 0)
	p.Transparency = 0.1
	p.Size = Vector3.new(0.35, 0.35, 0.35)
	local dust = p:FindFirstChild("Dust") :: ParticleEmitter?
	if dust then
		dust:Emit(6)
	end
	local tween = TweenService:Create(p, TweenInfo.new(0.12), { Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) })
	tween:Play()
	task.delay(0.6, function()
		if #impactPool < POOL_SIZE then
			table.insert(impactPool, p)
		else
			p:Destroy()
		end
	end)
end

-- Short-lived muzzle flash parented to a muzzle attachment.
function Effects.muzzleFlash(attachment: Attachment)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Range = 10
	light.Brightness = 4
	light.Shadows = false
	light.Parent = attachment
	Debris:AddItem(light, 0.05)

	local flash = attachment:FindFirstChild("Flash") :: ParticleEmitter?
	if not flash then
		local e = Instance.new("ParticleEmitter")
		e.Name = "Flash"
		e.Enabled = false
		e.LightEmission = 1
		e.Lifetime = NumberRange.new(0.03, 0.05)
		e.Speed = NumberRange.new(0.5, 1)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05) })
		e.Color = ColorSequence.new(Color3.fromRGB(255, 220, 150), Color3.fromRGB(255, 140, 60))
		e.Rotation = NumberRange.new(0, 360)
		e.LockedToPart = true
		e.Parent = attachment
		flash = e
	end
	(flash :: ParticleEmitter):Emit(3)
end

return Effects
