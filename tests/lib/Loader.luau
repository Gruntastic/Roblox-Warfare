-- Loads a project module from disk under Lune with Roblox datatypes available as globals.
-- `require(script.Parent.X)`-style requires are resolved through a fake `script` object so
-- that simple Instance-path requires inside src/ also work in tests.
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local fs = require("@lune/fs")

local Loader = {}
local cache: { [string]: any } = {}

local GLOBALS = {
	"Vector3", "Vector2", "CFrame", "Color3", "Enum", "Instance", "UDim", "UDim2",
	"NumberRange", "NumberSequence", "ColorSequence", "BrickColor", "Ray", "Rect",
	"NumberSequenceKeypoint", "ColorSequenceKeypoint", "PhysicalProperties", "TweenInfo",
}

local function pathObject(path: string)
	-- A minimal stand-in for `script` that maps Instance navigation onto file paths.
	local obj = {}
	local function resolve(p: string)
		for _, candidate in { p .. ".luau", p .. "/init.luau" } do
			if fs.isFile(candidate) then
				return candidate
			end
		end
		return nil
	end
	return setmetatable(obj, {
		__index = function(_, key)
			if key == "Parent" then
				local parent = string.match(path, "^(.*)/[^/]+$")
				return pathObject(parent or ".")
			elseif key == "__path" then
				return path
			elseif key == "Name" then
				return string.match(path, "([^/]+)$")
			elseif key == "WaitForChild" or key == "FindFirstChild" then
				return function(self, name)
					return pathObject(path .. "/" .. name)
				end
			end
			return pathObject(path .. "/" .. key)
		end,
		__tostring = function()
			return path
		end,
		__resolve = resolve,
	})
end

function Loader.load(file: string, extraEnv: { [string]: any }?): any
	local key = file
	if cache[key] ~= nil and not extraEnv then
		return cache[key]
	end
	local source = fs.readFile(file)
	local env = {}
	for _, name in GLOBALS do
		env[name] = (roblox :: any)[name]
	end
	env.script = pathObject((string.gsub(file, "%.luau$", "")))
	env.require = function(target)
		if type(target) == "table" and getmetatable(target) then
			local p = target.__path
			local resolved = getmetatable(target).__resolve(p)
			assert(resolved, "Loader: cannot resolve module " .. tostring(p))
			return Loader.load(resolved)
		end
		return require(target)
	end
	env.task = { wait = function() end, spawn = function(f, ...) return f(...) end, defer = function(f, ...) return f(...) end }
	if extraEnv then
		for k, v in extraEnv do
			env[k] = v
		end
	end
	setmetatable(env, { __index = _G })
	local fn = luau.load(source, { debugName = file, environment = env })
	local result = fn()
	if not extraEnv then
		cache[key] = result
	end
	return result
end

Loader.roblox = roblox
return Loader
