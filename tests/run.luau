-- Runs every tests/specs/*.spec.luau under Lune. Usage: lune run tests/run.luau
local fs = require("@lune/fs")
local process = require("@lune/process")
local T = require("./lib/T")

local files = fs.readDir("tests/specs")
table.sort(files)
for _, name in files do
	if string.match(name, "%.spec%.luau$") then
		print("\n" .. name)
		local ok, err = pcall(require, "./specs/" .. string.gsub(name, "%.luau$", ""))
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
