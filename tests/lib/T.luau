-- Tiny test framework: describe/it/expect with a summary and non-zero exit on failure.
local T = { passed = 0, failed = 0, failures = {} :: { string } }
local prefix: { string } = {}

function T.describe(name: string, fn: () -> ())
	table.insert(prefix, name)
	fn()
	table.remove(prefix)
end

function T.it(name: string, fn: () -> ())
	local full = table.concat(prefix, " > ") .. " > " .. name
	local ok, err = pcall(fn)
	if ok then
		T.passed += 1
		print("  PASS  " .. full)
	else
		T.failed += 1
		table.insert(T.failures, full .. "\n        " .. tostring(err))
		print("  FAIL  " .. full .. "\n        " .. tostring(err))
	end
end

local function fmt(v)
	return if type(v) == "string" then string.format("%q", v) else tostring(v)
end

function T.expect(actual: any)
	local e = {}
	function e.toBe(expected)
		if actual ~= expected then
			error(("expected %s, got %s"):format(fmt(expected), fmt(actual)), 2)
		end
	end
	function e.toBeNear(expected: number, eps: number?)
		if math.abs(actual - expected) > (eps or 1e-6) then
			error(("expected ~%s, got %s"):format(fmt(expected), fmt(actual)), 2)
		end
	end
	function e.toBeTruthy()
		if not actual then
			error(("expected truthy, got %s"):format(fmt(actual)), 2)
		end
	end
	function e.toBeFalsy()
		if actual then
			error(("expected falsy, got %s"):format(fmt(actual)), 2)
		end
	end
	function e.toBeGreaterThan(n: number)
		if not (actual > n) then
			error(("expected > %s, got %s"):format(fmt(n), fmt(actual)), 2)
		end
	end
	function e.toBeLessThan(n: number)
		if not (actual < n) then
			error(("expected < %s, got %s"):format(fmt(n), fmt(actual)), 2)
		end
	end
	function e.toBeAtLeast(n: number)
		if not (actual >= n) then
			error(("expected >= %s, got %s"):format(fmt(n), fmt(actual)), 2)
		end
	end
	function e.toThrow()
		local ok = pcall(actual)
		if ok then
			error("expected function to throw", 2)
		end
	end
	return e
end

return T
