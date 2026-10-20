--!strict
-- Client bootstrap: initialize shared state, then every controller and UI module.
-- Each module may export `init()` (wire-up, no yielding) and `start()` (may spawn work).
local ClientState = require(script.ClientState)
ClientState.init()

local modules = {}
for _, folderName in { "Controllers", "UI" } do
	local folder = script:FindFirstChild(folderName)
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("ModuleScript") then
				local ok, mod = pcall(require, child)
				if ok then
					table.insert(modules, { name = child.Name, mod = mod })
				else
					warn(("[Client] failed to load %s: %s"):format(child.Name, tostring(mod)))
				end
			end
		end
	end
end

for _, entry in modules do
	if type(entry.mod) == "table" and entry.mod.init then
		local ok, err = pcall(entry.mod.init)
		if not ok then
			warn(("[Client] %s.init failed: %s"):format(entry.name, tostring(err)))
		end
	end
end
for _, entry in modules do
	if type(entry.mod) == "table" and entry.mod.start then
		task.spawn(entry.mod.start)
	end
end
