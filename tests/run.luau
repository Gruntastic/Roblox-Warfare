-- Runs every tests/specs/*.spec.luau under Lune. Usage: lune run tests/run.luau [filter]
-- With a filter, only spec files whose name contains it run (plain substring match).
local fs = require("@lune/fs")
local process = require("@lune/process")
local T = require("./lib/T")

local files = fs.readDir("tests/specs")
table.sort(files)
for _, name in files do
	local filter = process.args[1]
	if string.match(name, "%.spec%.luau$") and (filter == nil or string.find(name, filter, 1, true)) then
		print("\n" .. name)
		local ok, err = pcall(function()
			return require("./specs/" .. name)
		end)
		if not ok then
			T.failed += 1
			table.insert(T.failures, name .. ": " .. tostring(err))
			print("  ERROR loading " .. name .. ": " .. tostring(err))
		end
	end
end

print(("\n%d passed, %d failed"):format(T.passed, T.failed))
if T.failed > 0 then
	for _, f in T.failures do
		print(" - " .. f)
	end
	process.exit(1)
end
