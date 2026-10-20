local Loader = require("../lib/Loader")
local T = require("../lib/T")
local WeaponState = Loader.load("src/shared/Pure/WeaponState.luau")
local Weapons = Loader.load("src/shared/Config/Weapons.luau")
local describe, it, expect = T.describe, T.it, T.expect

describe("WeaponState", function()
	it("consumes ammo and blocks when empty", function()
		local s = WeaponState.new({ id = "X", rpm = 600, fireMode = "Auto", magSize = 2, reserveAmmo = 10 })
		expect((WeaponState.tryFire(s, 0))).toBe(true)
		expect((WeaponState.tryFire(s, 0.1))).toBe(true)
		local ok, reason = WeaponState.tryFire(s, 0.2)
		expect(ok).toBe(false)
		expect(reason).toBe("empty")
	end)
	it("enforces fire rate: a rapid-fire exploit gets at most rpm + one interval of credit", function()
		local def = Weapons.VK7
		local s = WeaponState.new({ id = def.id, rpm = def.rpm, fireMode = def.fireMode, magSize = 1000, reserveAmmo = 0 })
		local accepted = 0
		-- attacker sends a shot every millisecond for 2 seconds
		for i = 0, 2000 do
			if WeaponState.tryFire(s, i / 1000) then
				accepted += 1
			end
		end
		local legit = 2 * def.rpm / 60
		expect(accepted).toBeLessThan(legit + 3)
		expect(accepted).toBeAtLeast(legit - 1)
	end)
	it("tolerates network jitter on legitimate fire", function()
		local s = WeaponState.new({ id = "X", rpm = 600, fireMode = "Auto", magSize = 100, reserveAmmo = 0 })
		local t, accepted = 0, 0
		for i = 1, 40 do
			-- alternating early/late arrivals around a 0.1s cadence
			local jitter = if i % 2 == 0 then -0.02 else 0.02
			if WeaponState.tryFire(s, t + jitter) then
				accepted += 1
			end
			t += 0.1
		end
		expect(accepted).toBe(40)
	end)
	it("reload blocks firing and refills from reserve when done", function()
		local s = WeaponState.new({ id = "X", rpm = 600, fireMode = "Auto", magSize = 30, reserveAmmo = 40 })
		for i = 1, 10 do
			WeaponState.tryFire(s, i)
		end
		expect(s.mag).toBe(20)
		expect((WeaponState.startReload(s, 100, 2, 3))).toBe(true)
		local ok, reason = WeaponState.tryFire(s, 101)
		expect(ok).toBe(false)
		expect(reason).toBe("reloading")
		WeaponState.update(s, 102.01)
		expect(s.mag).toBe(30)
		expect(s.reserve).toBe(30)
	end)
	it("empty reload uses the longer time; full mag cannot reload", function()
		local s = WeaponState.new({ id = "X", rpm = 600, fireMode = "Auto", magSize = 1, reserveAmmo = 5 })
		local _, r = WeaponState.startReload(s, 0, 2, 3)
		expect(r).toBe("full")
		WeaponState.tryFire(s, 0)
		WeaponState.startReload(s, 1, 2, 3)
		expect(s.reloadEndsAt).toBe(4)
	end)
	it("cannot fire during equip", function()
		local s = WeaponState.new({ id = "X", rpm = 600, fireMode = "Auto", magSize = 10, reserveAmmo = 5 })
		WeaponState.equip(s, 10, 0.5)
		local ok, reason = WeaponState.tryFire(s, 10.2)
		expect(ok).toBe(false)
		expect(reason).toBe("equipping")
		expect((WeaponState.tryFire(s, 10.6))).toBe(true)
	end)
end)
return nil
