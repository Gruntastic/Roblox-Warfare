--!strict
-- Puts ForgeGUI mesh models over part-built objects. The parts stay where they are (collision,
-- hit detection, weld anchors and attachment points are unchanged) and only turn invisible; a
-- clone of the mesh template is stretched to fill their bounding box and welded or anchored in
-- place. Templates live in ReplicatedStorage.ForgeModels (loaded by the server's ModelLibrary
-- from Config/Assets.Models); when a template is missing, nothing changes.
--
-- Mesh orientation is not known in advance, so fitting matches axes by size: the mesh's longer
-- horizontal side goes along the target's longer horizontal side and Y stays up. A mesh that ends up
-- facing backwards can be turned with Assets.ModelFlip[key] = true.
local ModelSkin = {}

export type Options = {
	frame: CFrame?, -- orientation of the target box (defaults to the largest part's yaw)
	weldTo: BasePart?, -- weld the skin to this part (else the skin is anchored)
	flip: boolean?, -- turn the mesh 180 degrees about Y
	parent: Instance?, -- defaults to the first part's parent
}

function ModelSkin.template(key: string): Model?
	if (game :: any) == nil then
		return nil -- pure tests (Lune) have no DataModel
	end
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("ForgeModels")
	local found = folder and folder:FindFirstChild(key)
	return if found and found:IsA("Model") then found else nil
end

-- Bounding box of `parts` measured in `frame`'s axes: returns the box centre CFrame and size.
function ModelSkin.boundsIn(parts: { BasePart }, frame: CFrame): (CFrame, Vector3)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in parts do
		local half = p.Size / 2
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local corner = frame:PointToObjectSpace(p.CFrame:PointToWorldSpace(half * Vector3.new(sx, sy, sz)))
					lo = lo:Min(corner)
					hi = hi:Max(corner)
				end
			end
		end
	end
	return frame * CFrame.new((lo + hi) / 2), hi - lo
end

-- Clone template `key` and stretch it to fill a box of `size` centred on `box`. Returns the clone
-- (not parented) or nil when there is no template.
function ModelSkin.fit(key: string, box: CFrame, size: Vector3, flip: boolean?): Model?
	local template = ModelSkin.template(key)
	if not template then
		return nil
	end
	local clone = template:Clone()
	local parts: { BasePart } = {}
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	if #parts == 0 then
		clone:Destroy()
		return nil
	end
	local srcBox, srcSize = clone:GetBoundingBox()
	-- turn 90 degrees when the long horizontal sides disagree
	local turn = (srcSize.X >= srcSize.Z) ~= (size.X >= size.Z)
	local rot = CFrame.Angles(0, (if turn then math.pi / 2 else 0) + (if flip then math.pi else 0), 0)
	local turned = if turn then Vector3.new(srcSize.Z, srcSize.Y, srcSize.X) else srcSize
	local scale = Vector3.new(
		size.X / math.max(turned.X, 1e-3),
		size.Y / math.max(turned.Y, 1e-3),
		size.Z / math.max(turned.Z, 1e-3)
	)
	for _, p in parts do
		local rel = rot * srcBox:ToObjectSpace(p.CFrame)
		local pos = rel.Position * scale
		local rotation = rel.Rotation
		-- stretch each part along its own axes by how much those axes line up with the box axes
		local function along(axis: Vector3): number
			return math.abs(axis.X) * scale.X + math.abs(axis.Y) * scale.Y + math.abs(axis.Z) * scale.Z
		end
		p.Size = Vector3.new(
			p.Size.X * along(rotation.RightVector),
			p.Size.Y * along(rotation.UpVector),
			p.Size.Z * along(-rotation.LookVector)
		)
		p.CFrame = box * CFrame.new(pos) * rotation
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
	end
	return clone
end

-- Dress `parts` with template `key`: the skin fills their bounding box and the parts turn
-- invisible. Returns the skin model, or nil (and leaves the parts alone) without a template.
function ModelSkin.dress(parts: { BasePart }, key: string, opts: Options?): Model?
	if #parts == 0 or not ModelSkin.template(key) then
		return nil
	end
	local frame = opts and opts.frame
	if not frame then
		local largest = parts[1]
		for _, p in parts do
			if p.Size.Magnitude > largest.Size.Magnitude then
				largest = p
			end
		end
		local look = largest.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		frame = if flat.Magnitude > 1e-3
			then CFrame.lookAt(largest.Position, largest.Position + flat)
			else CFrame.new(largest.Position)
	end
	local box, size = ModelSkin.boundsIn(parts, frame :: CFrame)
	local skin = ModelSkin.fit(key, box, size, opts and opts.flip)
	if not skin then
		return nil
	end
	skin.Name = "Skin"
	local weldTo = opts and opts.weldTo
	for _, d in skin:GetDescendants() do
		if d:IsA("BasePart") and weldTo then
			d.Anchored = false
			local weld = Instance.new("Weld")
			weld.Part0 = weldTo
			weld.Part1 = d
			weld.C0 = weldTo.CFrame:ToObjectSpace(d.CFrame)
			weld.Parent = d
		end
	end
	for _, p in parts do
		p.Transparency = 1
		p:SetAttribute("Skinned", true)
	end
	skin.Parent = (opts and opts.parent) or parts[1].Parent
	return skin
end

return ModelSkin
