--!strict
-- Builds a weapon Model from its data definition plus an optional attachment selection. Used for
-- first-person viewmodels (client), third-person world models (server) and Gunsmith previews.
-- The PrimaryPart "GripOrigin" sits at the grip origin. Two Attachments are added to it:
-- "Muzzle" (tracer / flash origin) and "Sight" (the eye point ADS aligns the camera to).
local Shared = script.Parent
local Attachments = require(Shared.Config.Attachments)
local WeaponStats = require(Shared.Pure.WeaponStats)

local WeaponModel = {}

local function addPart(model: Model, grip: BasePart, spec: any, offset: CFrame, opts: any)
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
	p.CFrame = offset
	local weld = Instance.new("Weld")
	weld.Part0 = grip
	weld.Part1 = p
	weld.C0 = offset
	weld.Parent = p
	p.Parent = model
end

function WeaponModel.build(def: any, opts: { collide: boolean?, castShadow: boolean?, attachments: { [string]: string }? }?): Model
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

	local selection = opts and opts.attachments
	local hasMag = selection ~= nil and selection.Magazine ~= nil and Attachments[selection.Magazine] ~= nil
	for _, spec in def.model do
		if not (hasMag and spec.name == "Magazine") then
			addPart(model, grip, spec, spec.offset, opts)
		end
	end

	local effective = WeaponStats.resolve(def, selection, Attachments)
	if selection then
		local barrel = if selection.Barrel then Attachments[selection.Barrel] else nil
		local barrelExtend = if barrel and barrel.muzzleExtend then barrel.muzzleExtend else 0
		local anchors = def.anchors
		for _, slot in WeaponStats.SLOTS do
			local att = effective.attachments[slot] and Attachments[effective.attachments[slot]]
			if att then
				local anchor: CFrame? = if slot == "Optic"
					then anchors.optic
					elseif slot == "Underbarrel" then anchors.underbarrel
					elseif slot == "Magazine" then anchors.magazine
					elseif slot == "Barrel" then anchors.muzzle
					else anchors.muzzle * CFrame.new(0, 0, -barrelExtend)
				if anchor then
					for _, spec in att.model do
						addPart(model, grip, spec, anchor * spec.offset, opts)
					end
				end
			end
		end
	end

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.CFrame = effective.muzzleOffset
	muzzle.Parent = grip
	local sight = Instance.new("Attachment")
	sight.Name = "Sight"
	sight.CFrame = effective.sightOffset
	sight.Parent = grip
	return model
end

return WeaponModel
