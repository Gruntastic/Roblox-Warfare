--!strict
-- Builds a weapon Model from its data definition. Used for first-person viewmodels (client)
-- and third-person world models (server). The PrimaryPart "Grip" sits at the grip origin.
local WeaponModel = {}

function WeaponModel.build(def: any, opts: { collide: boolean?, castShadow: boolean? }?): Model
	local model = Instance.new("Model")
	model.Name = def.id
	local grip = Instance.new("Part")
	grip.Name = "GripOrigin"
	grip.Size = Vector3.new(0.1, 0.1, 0.1)
	grip.Transparency = 1
	grip.CanCollide = false
	grip.CanQuery = false
	grip.CanTouch = false
	grip.Massless = true
	grip.CFrame = CFrame.new()
	grip.Parent = model
	model.PrimaryPart = grip

	for _, spec in def.model do
		local p = Instance.new("Part")
		p.Name = spec.name
		p.Shape = if spec.shape == "Cylinder" then Enum.PartType.Cylinder else Enum.PartType.Block
		p.Size = spec.size
		p.Color = spec.color
		p.Material = spec.material
		p.CanCollide = opts ~= nil and opts.collide == true
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = opts == nil or opts.castShadow ~= false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = spec.offset
		local weld = Instance.new("Weld")
		weld.Part0 = grip
		weld.Part1 = p
		weld.C0 = spec.offset
		weld.Parent = p
		p.Parent = model
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = def.muzzleOffset
	muzzle.Parent = grip
	return model
end

return WeaponModel
