local Loader = require("../lib/Loader")
local T = require("../lib/T")
local Assets = Loader.load("src/shared/Config/Assets.luau")
local describe, it, expect = T.describe, T.it, T.expect
local Enum = (require("@lune/roblox") :: any).Enum

local function isMaterial(name: string): boolean
	local ok, value = pcall(function()
		return Enum.Material[name]
	end)
	return ok and value ~= nil
end

local MAPS = { "AshwoodEstate", "Breakwater", "DustlineTerminal", "FrostRelay", "IronBorough", "RedMesa" }

describe("Environment assets", function()
	it("keeps every asset id a whole non-negative number", function()
		for _, id in Assets.Models do
			expect(id >= 0 and id == math.floor(id)).toBe(true)
		end
		for _, m in Assets.Materials do
			expect(m.color >= 0 and m.normal >= 0 and m.studsPerTile > 0).toBe(true)
			expect(isMaterial(m.base)).toBe(true)
		end
		for _, faces in Assets.Skies do
			for _, face in { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" } do
				expect(type(faces[face])).toBe("number")
			end
		end
	end)

	it("maps materials only to known material keys", function()
		for materialName, key in Assets.MaterialFor do
			expect(isMaterial(materialName)).toBe(true)
			expect(Assets.Materials[key] ~= nil).toBe(true)
		end
		for _, key in Assets.MaterialForName do
			expect(Assets.Materials[key] ~= nil).toBe(true)
		end
	end)

	it("only names skies for real maps", function()
		for mapId in Assets.Skies do
			expect(table.find(MAPS, mapId) ~= nil).toBe(true)
		end
	end)
end)

describe("Map prop tags", function()
	it("tags props with a key and one id per prop, so meshes can be laid over them", function()
		for _, mapId in MAPS do
			local model = Loader.load("src/server/Maps/" .. mapId .. ".luau").build()
			local keyOf: { [number]: string } = {}
			local count = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					local key = d:GetAttribute("Prop")
					local id = d:GetAttribute("PropId")
					if key ~= nil then
						expect(type(key)).toBe("string")
						expect(type(id)).toBe("number")
						-- every part of one prop shares its key
						expect(keyOf[id] == nil or keyOf[id] == key).toBe(true)
						keyOf[id] = key
						count += 1
					end
				end
			end
			expect(count > 0).toBe(true)
		end
	end)

	it("tags the shipping containers on the container maps", function()
		for _, mapId in { "Breakwater", "DustlineTerminal" } do
			local model = Loader.load("src/server/Maps/" .. mapId .. ".luau").build()
			local found = false
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("Prop") == "Container" then
					found = true
					break
				end
			end
			expect(found).toBe(true)
		end
	end)
end)
