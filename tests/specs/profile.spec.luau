local Loader = require("../lib/Loader")
local T = require("../lib/T")
local ProfileSchema = Loader.load("src/shared/Pure/ProfileSchema.luau")
local SessionLock = Loader.load("src/shared/Pure/SessionLock.luau")
local describe, it, expect = T.describe, T.it, T.expect

local valid = { VK7 = "Primary", P12 = "Secondary" }

describe("ProfileSchema", function()
	it("creates defaults for new players", function()
		local p, changed = ProfileSchema.migrate(nil, 100, 5, valid)
		expect(changed).toBe(true)
		expect(p.version).toBe(ProfileSchema.VERSION)
		expect(#p.loadouts).toBe(5)
		expect(p.account.level).toBe(1)
	end)
	it("migrates v1 flat profiles to the current version keeping progress", function()
		local v1 = { version = 1, level = 12, xp = 340, stats = { kills = 50 }, weapons = { VK7 = { level = 4, xp = 10, kills = 40 } } }
		local p, changed = ProfileSchema.migrate(v1, 100, 5, valid)
		expect(changed).toBe(true)
		expect(p.version).toBe(ProfileSchema.VERSION)
		expect(p.account.level).toBe(12)
		expect(p.account.xp).toBe(340)
		expect(p.stats.kills).toBe(50)
		expect(p.stats.deaths).toBe(0)
		expect(p.weapons.VK7.level).toBe(4)
	end)
	it("repairs corrupted / forged values", function()
		local bad = {
			version = 2,
			account = { level = 9999, xp = -50, prestige = "x" },
			stats = { kills = 0 / 0 },
			loadouts = { { name = string.rep("A", 100), primary = "P12", secondary = "HACKGUN" } },
			selectedLoadout = 42,
		}
		local p = ProfileSchema.migrate(bad, 100, 5, valid)
		expect(p.account.level).toBe(70)
		expect(p.account.xp).toBe(0)
		expect(p.account.prestige).toBe(0)
		expect(p.stats.kills).toBe(0)
		expect(p.loadouts[1].primary).toBe("VK7") -- P12 is not a primary
		expect(p.loadouts[1].secondary).toBe("P12")
		expect(#p.loadouts[1].name).toBe(24)
		expect(p.selectedLoadout).toBe(5)
	end)
	it("migrates v2 loadouts to v3 with empty attachment selections", function()
		local v2 = { version = 2, account = { level = 5, xp = 0, prestige = 0 }, loadouts = { { name = "A", primary = "VK7", secondary = "P12" } } }
		local p, changed = ProfileSchema.migrate(v2, 100, 5, valid)
		expect(changed).toBe(true)
		expect(p.version).toBe(3)
		expect(next(p.loadouts[1].primaryAttachments)).toBe(nil)
		expect(next(p.loadouts[5].secondaryAttachments)).toBe(nil)
	end)
	it("keeps attachment maps by shape only, capped at five entries", function()
		local v3 = {
			version = 3,
			loadouts = {
				{ name = "A", primary = "VK7", secondary = "P12", primaryAttachments = { Optic = "RedDot", [1] = "x", Muzzle = 5 }, secondaryAttachments = "bad" },
			},
		}
		local p = ProfileSchema.migrate(v3, 100, 5, valid)
		expect(p.loadouts[1].primaryAttachments.Optic).toBe("RedDot")
		expect(p.loadouts[1].primaryAttachments.Muzzle).toBe(nil)
		expect(p.loadouts[1].primaryAttachments[1]).toBe(nil)
		expect(next(p.loadouts[1].secondaryAttachments)).toBe(nil)
		local big = {}
		for i = 1, 20 do
			big["S" .. i] = "A"
		end
		local count = 0
		for _ in ProfileSchema.attachmentMap(big) do
			count += 1
		end
		expect(count).toBe(5)
	end)
	it("drops attachments when the stored weapon is replaced", function()
		local v3 = { version = 3, loadouts = { { name = "A", primary = "HACKGUN", secondary = "P12", primaryAttachments = { Optic = "RedDot" }, secondaryAttachments = {} } } }
		local p = ProfileSchema.migrate(v3, 100, 5, valid)
		expect(p.loadouts[1].primary).toBe("VK7")
		expect(next(p.loadouts[1].primaryAttachments)).toBe(nil)
	end)
	it("refuses to load profiles from a newer schema", function()
		expect(function()
			ProfileSchema.migrate({ version = 99 }, 0, 5, valid)
		end).toThrow()
	end)
end)

describe("SessionLock", function()
	it("acquires a fresh record", function()
		local rec, status = SessionLock.acquire(nil, "A", 100, 300)
		expect(status).toBe("acquired")
		expect(rec.lock.jobId).toBe("A")
	end)
	it("blocks while another live server holds the lock", function()
		local rec = { data = { x = 1 }, lock = { jobId = "B", time = 90 } }
		local new, status = SessionLock.acquire(rec, "A", 100, 300)
		expect(new).toBe(nil)
		expect(status).toBe("locked")
	end)
	it("steals an expired lock and keeps data", function()
		local rec = { data = { x = 1 }, lock = { jobId = "B", time = 0 } }
		local new, status = SessionLock.acquire(rec, "A", 1000, 300)
		expect(status).toBe("stolen")
		expect(new.data.x).toBe(1)
		expect(new.lock.jobId).toBe("A")
	end)
	it("save refuses to overwrite when the lock was lost", function()
		local rec = { data = { x = 1 }, lock = { jobId = "B", time = 0 } }
		local new, status = SessionLock.save(rec, "A", 10, { x = 2 }, false)
		expect(new).toBe(nil)
		expect(status).toBe("lost")
	end)
	it("save with release clears the lock", function()
		local rec = { data = { x = 1 }, lock = { jobId = "A", time = 0 } }
		local new, status = SessionLock.save(rec, "A", 10, { x = 2 }, true)
		expect(status).toBe("saved")
		expect(new.lock).toBe(nil)
		expect(new.data.x).toBe(2)
	end)
	it("reconnect flow: release then reacquire on another server keeps data", function()
		local rec = SessionLock.acquire(nil, "A", 0, 300)
		rec = SessionLock.save(rec, "A", 5, { level = 7 }, true)
		local rec2, status = SessionLock.acquire(rec, "B", 6, 300)
		expect(status).toBe("acquired")
		expect(rec2.data.level).toBe(7)
	end)
end)
return nil
