--!strict
-- ForgeGUI environment art (docs/ASSETS.md):
--   * loads every published mesh model in Config/Assets.Models into ReplicatedStorage.ForgeModels
--     (InsertService only loads assets owned by the experience's creator), where ModelSkin finds
--     them for map props, weapons and gear;
--   * registers the tiled materials as MaterialVariants in MaterialService and applies them to map
--     parts by base material (only the map, so weapons and characters keep Roblox's materials);
--   * swaps the Sky per map;
--   * dresses tagged map props (parts carrying the "Prop" / "PropId" attributes) with their mesh.
local InsertService = game:GetService("InsertService")
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Assets = require(Shared.Config.Assets)
local ModelSkin = require(Shared.ModelSkin)

local EnvironmentService = {}

local LOAD_WAIT = 20 -- seconds a map waits for models that are still loading
-- Part colours are multiplied into the texture; lifting them keeps textured surfaces from going muddy.
local TINT_LIFT = 0.55

local folder = Instance.new("Folder")
folder.Name = "ForgeModels"
local pending = 0

local function loadModel(key: string, id: number)
	pending += 1
	local ok, result = pcall(function(): any
		return InsertService:LoadAsset(id)
	end)
	pending -= 1
	if not ok or typeof(result) ~= "Instance" then
		warn(("[EnvironmentService] model %s (%d) did not load: %s"):format(key, id, tostring(result)))
		return
	end
	local container = result :: Instance
	local inner = container:FindFirstChildWhichIsA("Model")
	local model: Model
	if inner and #container:GetChildren() == 1 then
		model = inner
	else
		model = Instance.new("Model")
		for _, child in container:GetChildren() do
			child.Parent = model
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model.Name = key
	model.Parent = folder
end

local function registerMaterials()
	for key, m in Assets.Materials do
		local color = Assets.content(m.color)
		if color then
			local variant = Instance.new("MaterialVariant")
			variant.Name = "Forge" .. key
			local okBase = pcall(function()
				variant.BaseMaterial = (Enum.Material :: any)[m.base]
			end)
			if okBase then
				variant.ColorMap = color
				variant.NormalMap = Assets.content(m.normal) or ""
				variant.StudsPerTile = m.studsPerTile
				variant.Parent = MaterialService
			else
				variant:Destroy()
			end
		end
	end
end

local function applyMaterials(map: Model)
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local key = Assets.MaterialForName[d.Name] or Assets.MaterialFor[d.Material.Name]
			local m = key and Assets.Materials[key]
			if m and Assets.content(m.color) and MaterialService:FindFirstChild("Forge" .. key) then
				-- the variant's own base must match, so set the part's material to it
				d.Material = (Enum.Material :: any)[m.base]
				d.MaterialVariant = "Forge" .. key
				d.Color = d.Color:Lerp(Color3.new(1, 1, 1), TINT_LIFT)
			end
		end
	end
end

local function applySky(mapId: string)
	local old = Lighting:FindFirstChild("ForgeSky")
	if old then
		old:Destroy()
	end
	local faces = Assets.Skies[mapId]
	if not faces then
		return
	end
	for _, face in { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" } do
		if not Assets.content(faces[face]) then
			return -- a partial sky looks worse than the default one
		end
	end
	for _, s in Lighting:GetChildren() do
		if s:IsA("Sky") then
			s:Destroy()
		end
	end
	local sky = Instance.new("Sky")
	sky.Name = "ForgeSky"
	sky.SkyboxBk = Assets.content(faces.Bk) :: string
	sky.SkyboxDn = Assets.content(faces.Dn) :: string
	sky.SkyboxFt = Assets.content(faces.Ft) :: string
	sky.SkyboxLf = Assets.content(faces.Lf) :: string
	sky.SkyboxRt = Assets.content(faces.Rt) :: string
	sky.SkyboxUp = Assets.content(faces.Up) :: string
	sky.Parent = Lighting
end

local function dressProps(map: Model)
	local groups: { [number]: { parts: { BasePart }, key: string } } = {}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			local key = d:GetAttribute("Prop")
			local id = d:GetAttribute("PropId")
			if type(key) == "string" and type(id) == "number" then
				local g = groups[id]
				if not g then
					g = { parts = {}, key = key }
					groups[id] = g
				end
				table.insert(g.parts, d)
			end
		end
	end
	local deadline = os.clock() + LOAD_WAIT
	while pending > 0 and os.clock() < deadline do
		task.wait(0.25)
	end
	for _, g in groups do
		local modelKey = "Prop." .. g.key
		if map.Parent and ModelSkin.template(modelKey) then
			ModelSkin.dress(g.parts, modelKey, { flip = Assets.ModelFlip[modelKey] })
		end
	end
end

-- Called by MatchService after a map is built and parented.
function EnvironmentService.dressMap(map: Model, mapId: string)
	applySky(mapId)
	applyMaterials(map)
	task.spawn(dressProps, map)
end

function EnvironmentService.init()
	folder.Parent = ReplicatedStorage
	registerMaterials()
end

function EnvironmentService.start()
	for key, id in Assets.Models do
		if id > 0 then
			task.spawn(loadModel, key, id)
		end
	end
end

return EnvironmentService
