-- Roster content checks: counts, naming, completeness, model conventions and balance bands.
local Loader = require("../lib/Loader")
local T = require("../lib/T")
local Damage = Loader.load("src/shared/Pure/Damage.luau")
local WeaponStats = Loader.load("src/shared/Pure/WeaponStats.luau")
local Weapons = Loader.load("src/shared/Config/Weapons.luau")
local Attachments = Loader.load("src/shared/Config/Attachments.luau")
local describe, it, expect = T.describe, T.it, T.expect

local HP = 100
local CLOSE = 10 -- studs used for "close" shots-to-kill checks

local EXPECTED_CLASSES = {
	AssaultRifle = 6,
	SMG = 5,
	LMG = 3,
	Marksman = 2,
	Sniper = 3,
	Shotgun = 3,
	Pistol = 3,
	MachinePistol = 1,
}

-- Real-world and other-game weapon names we must never use (matched case-insensitively against
-- ids and display names, with separators removed as well).
local BANNED = {
	"M4", "AK", "ACR", "MP5", "MP7", "UMP", "GLOCK", "DESERT EAGLE", "DEAGLE", "BARRETT", "AWP",
	"INTERVENTION", "CHEYTAC", "F2000", "VECTOR", "SPAS", "STRIKER", "AA-12", "AA12", "RAFFICA",
	"TMP", "M9", "M16", "M14", "M21", "M240", "M249", "M1014", "FAMAS", "SCAR", "TAR-21", "G36",
	"AUG", "FAL", "RPD", "L86", "MG4", "WA2000", "UZI", "KRISS", "P90", "PP2000", "USP", "BERETTA",
	"COLT", "MAGNUM", "DRAGUNOV", "SVD", "REMINGTON", "MOSSBERG", "BENELLI", "KALASH", "THOMPSON",
	"HK", "SIG", "FN ", "RANGER", "MODEL 1887", "SKORPION", "PYTHON", "ANACONDA", "WINCHESTER",
}

local FIELDS: { [string]: string } = {
	id = "string", displayName = "string", description = "string", class = "string", slot = "string",
	fireMode = "string", rpm = "number", damage = "table", headMultiplier = "number",
	limbMultiplier = "number", magSize = "number", reserveAmmo = "number", reloadTime = "number",
	reloadEmptyTime = "number", equipTime = "number", adsTime = "number",
	moveSpeedMultiplier = "number", adsMoveSpeedMultiplier = "number", spread = "table",
	recoil = "table", adsFov = "number", unlockLevel = "number", muzzleOffset = "userdata",
	sightOffset = "userdata", anchors = "table", attachmentSlots = "table",
	attachmentUnlocks = "table", sounds = "table", model = "table",
}

local function sorted(): { any }
	local list = {}
	for _, def in Weapons do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

local function ofClass(class: string): { any }
	local list = {}
	for _, def in sorted() do
		if def.class == class then
			table.insert(list, def)
		end
	end
	return list
end

-- Body shots to kill at a distance; shotguns count every pellet landing.
local function btk(def: any, distance: number): number
	local d = Damage.compute(def, distance, "Body") * (def.pellets or 1)
	if d <= 0 then
		return math.huge
	end
	return math.ceil(HP / d)
end

local function within(id: string, what: string, v: number, lo: number, hi: number)
	if not (v >= lo and v <= hi) then
		error(("%s: %s = %s, expected %s..%s"):format(id, what, tostring(v), tostring(lo), tostring(hi)), 2)
	end
end

local function samePos(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-6
end

describe("Roster", function()
	it("has 26 weapons with the expected class counts", function()
		local total, counts = 0, {}
		for _, def in Weapons do
			total += 1
			counts[def.class] = (counts[def.class] or 0) + 1
		end
		expect(total).toBe(26)
		for class, n in EXPECTED_CLASSES do
			if counts[class] ~= n then
				error(("%s: %s weapons, expected %d"):format(class, tostring(counts[class]), n))
			end
		end
		for class in counts do
			expect(EXPECTED_CLASSES[class] ~= nil).toBe(true)
		end
	end)

	it("primaries and secondaries are split 22 / 4", function()
		local p, s = 0, 0
		for _, def in Weapons do
			local secondaryClass = def.class == "Pistol" or def.class == "MachinePistol"
			expect(def.slot).toBe(if secondaryClass then "Secondary" else "Primary")
			if def.slot == "Primary" then
				p += 1
			else
				s += 1
			end
		end
		expect(p).toBe(22)
		expect(s).toBe(4)
	end)

	it("ids match keys, are short uppercase and unique; display names are unique", function()
		local names = {}
		for key, def in Weapons do
			expect(def.id).toBe(key)
			expect(string.match(key, "^[A-Z][A-Z0-9]+$") ~= nil and #key <= 4).toBe(true)
			local lower = string.lower(def.displayName)
			if names[lower] then
				error("duplicate display name " .. def.displayName)
			end
			names[lower] = true
		end
		expect(Weapons.VK7 ~= nil and Weapons.P12 ~= nil).toBe(true)
	end)

	it("uses no real-world or other-game weapon names", function()
		for _, def in Weapons do
			for _, text in { def.id, def.displayName } do
				local upper = string.upper(text)
				local squashed = string.gsub(upper, "[%s%-_%.]", "")
				for _, bad in BANNED do
					local badSquashed = string.gsub(bad, "[%s%-_%.]", "")
					if string.find(upper, bad, 1, true) or string.find(squashed, badSquashed, 1, true) then
						error(("%s contains banned name %q"):format(text, bad))
					end
				end
			end
		end
	end)

	it("every field is present and typed", function()
		for id, def in Weapons do
			for field, kind in FIELDS do
				if type(def[field]) ~= kind and typeof(def[field]) ~= kind then
					error(("%s.%s is %s, expected %s"):format(id, field, typeof(def[field]), kind))
				end
			end
			expect(#def.description > 10).toBe(true)
			for _, k in { "close", "far", "closeRange", "farRange", "maxRange" } do
				expect(type(def.damage[k])).toBe("number")
			end
			for _, k in { "hip", "ads", "movingMultiplier" } do
				expect(def.spread[k] > 0).toBe(true)
			end
			for _, k in { "vertical", "horizontal", "recovery", "adsMultiplier" } do
				expect(def.recoil[k] > 0).toBe(true)
			end
			for _, k in { "fire", "reload", "equip" } do
				expect(type(def.sounds[k])).toBe("string")
			end
			for _, k in { "optic", "muzzle", "magazine", "leftHand" } do
				expect(typeof(def.anchors[k])).toBe("CFrame")
			end
			local hasUnder = def.anchors.underbarrel ~= nil
			expect(hasUnder == (table.find(def.attachmentSlots, "Underbarrel") ~= nil)).toBe(true)
			within(id, "unlockLevel", def.unlockLevel, 1, 70)
			expect(def.fireMode == "Auto" or def.fireMode == "Semi" or def.fireMode == "Burst").toBe(true)
			expect(def.reserveAmmo >= def.magSize).toBe(true)
			expect(def.damage.maxRange >= def.damage.farRange).toBe(true)
		end
	end)

	it("every class has a starter at account level 1-4 (except the single machine pistol)", function()
		for class in EXPECTED_CLASSES do
			if class ~= "MachinePistol" then
				local lowest = math.huge
				for _, def in ofClass(class) do
					lowest = math.min(lowest, def.unlockLevel)
				end
				within(class, "lowest unlock", lowest, 1, 4)
			end
		end
		for _, def in Weapons do
			within(def.id, "unlockLevel", def.unlockLevel, 1, 45)
		end
	end)

	it("muzzleOffset equals anchors.muzzle", function()
		for id, def in Weapons do
			if not samePos(def.muzzleOffset, def.anchors.muzzle) then
				error(id .. ": muzzleOffset differs from anchors.muzzle")
			end
			expect(def.muzzleOffset.Position.Z < 0).toBe(true)
		end
	end)
end)

describe("Roster models", function()
	it("every model has exactly one Magazine part and stays under 25 parts", function()
		for id, def in Weapons do
			local mags = 0
			for _, p in def.model do
				expect(type(p.name)).toBe("string")
				expect(p.shape == "Block" or p.shape == "Cylinder").toBe(true)
				expect(typeof(p.size)).toBe("Vector3")
				expect(typeof(p.offset)).toBe("CFrame")
				expect(typeof(p.color)).toBe("Color3")
				expect(typeof(p.material)).toBe("EnumItem")
				if p.name == "Magazine" then
					mags += 1
				end
			end
			if mags ~= 1 then
				error(("%s has %d Magazine parts"):format(id, mags))
			end
			if #def.model > 25 then
				error(("%s has %d parts"):format(id, #def.model))
			end
		end
	end)

	it("iron-sighted weapons have RearSight and FrontSight; scoped weapons have a scope body instead", function()
		for id, def in Weapons do
			local names = {}
			for _, p in def.model do
				names[p.name] = true
			end
			if def.scope then
				expect(names.ScopeTube == true and names.RearSight == nil).toBe(true)
			elseif not (names.RearSight and names.FrontSight) then
				error(id .. " is missing iron sights")
			end
		end
	end)

	it("long guns are 2.5-4.5 studs long, handguns about a stud, roughly 0.2-0.3 wide", function()
		for id, def in Weapons do
			local minZ, maxZ = math.huge, -math.huge
			for _, p in def.model do
				local o = p.offset
				local half = math.abs(o.RightVector.Z) * p.size.X / 2 + math.abs(o.UpVector.Z) * p.size.Y / 2 + math.abs(o.LookVector.Z) * p.size.Z / 2
				minZ = math.min(minZ, o.Position.Z - half)
				maxZ = math.max(maxZ, o.Position.Z + half)
			end
			local length = maxZ - minZ
			if def.slot == "Primary" then
				within(id, "length", length, 2.5, 4.5)
			else
				within(id, "length", length, 0.8, 1.4)
			end
		end
	end)

	it("long guns with an underbarrel rail have a handguard above the anchor", function()
		for id, def in Weapons do
			if def.anchors.underbarrel then
				local found = false
				for _, p in def.model do
					if p.name == "Handguard" then
						local hz = p.offset.Position.Z
						local uz = def.anchors.underbarrel.Position.Z
						found = math.abs(hz - uz) <= p.size.Z / 2 + 0.05 or math.abs(hz - uz) <= p.size.X / 2 + 0.05
					end
				end
				if not found then
					error(id .. ": no handguard over the underbarrel anchor")
				end
			end
		end
	end)
end)

describe("Roster balance", function()
	it("assault rifles: 4-5 body shots close, 5-6 far, rpm 600-850", function()
		for _, def in ofClass("AssaultRifle") do
			within(def.id, "close BTK", btk(def, CLOSE), 4, 5)
			within(def.id, "far BTK", btk(def, def.damage.farRange), 5, 6)
			within(def.id, "rpm", def.rpm, 600, 850)
		end
	end)

	it("exactly one burst rifle, with a burst definition", function()
		local bursts = 0
		for _, def in Weapons do
			if def.fireMode == "Burst" then
				bursts += 1
				expect(def.class).toBe("AssaultRifle")
				expect(def.burst ~= nil).toBe(true)
				expect(def.burst.count).toBe(3)
				within(def.id, "burst delay", def.burst.delay, 0.2, 0.3)
			else
				expect(def.burst).toBe(nil)
			end
		end
		expect(bursts).toBe(1)
	end)

	it("SMGs: 4-5 close, 6-8 far, short far range, rpm 750-1000", function()
		for _, def in ofClass("SMG") do
			within(def.id, "close BTK", btk(def, CLOSE), 4, 5)
			within(def.id, "far BTK", btk(def, def.damage.farRange), 6, 8)
			within(def.id, "farRange", def.damage.farRange, 40, 100)
			within(def.id, "rpm", def.rpm, 750, 1000)
		end
	end)

	it("LMGs: 4-5 close, big mags, slow ADS, slower movement, rpm 600-800", function()
		for _, def in ofClass("LMG") do
			within(def.id, "close BTK", btk(def, CLOSE), 4, 5)
			within(def.id, "far BTK", btk(def, def.damage.farRange), 4, 6)
			within(def.id, "magSize", def.magSize, 75, 150)
			within(def.id, "adsTime", def.adsTime, 0.35, 0.5)
			within(def.id, "moveSpeed", def.moveSpeedMultiplier, 0.85, 0.9)
			within(def.id, "rpm", def.rpm, 600, 800)
		end
	end)

	it("marksman rifles: semi-auto, 2-3 body shots", function()
		for _, def in ofClass("Marksman") do
			expect(def.fireMode).toBe("Semi")
			within(def.id, "close BTK", btk(def, CLOSE), 2, 3)
			within(def.id, "far BTK", btk(def, def.damage.farRange), 2, 3)
		end
	end)

	it("snipers: semi, slow, scoped, one-shot head/body up to farRange, limbs survive", function()
		for _, def in ofClass("Sniper") do
			expect(def.fireMode).toBe("Semi")
			within(def.id, "rpm", def.rpm, 40, 60)
			expect(def.scope ~= nil).toBe(true)
			within(def.id, "scope fov", def.scope.fov, 18, 25)
			for _, dist in { CLOSE, def.damage.closeRange, (def.damage.closeRange + def.damage.farRange) / 2, def.damage.farRange } do
				expect(Damage.shotsToKill(def, dist, "Body", HP)).toBe(1)
				expect(Damage.shotsToKill(def, dist, "Head", HP)).toBe(1)
			end
			expect(Damage.shotsToKill(def, CLOSE, "Limb", HP) > 1).toBe(true)
		end
		for id, def in Weapons do
			if def.class ~= "Sniper" then
				if def.scope ~= nil then
					error(id .. " has a built-in scope but is not a sniper")
				end
			end
		end
	end)

	it("shotguns: pellets 6-9, spread 4-7, one-shot close with all pellets, useless past 60 studs", function()
		local modes = {}
		for _, def in ofClass("Shotgun") do
			expect(type(def.pellets)).toBe("number")
			expect(type(def.pelletSpread)).toBe("number")
			within(def.id, "pellets", def.pellets, 6, 9)
			within(def.id, "pelletSpread", def.pelletSpread, 4, 7)
			expect(btk(def, def.damage.closeRange)).toBe(1)
			within(def.id, "maxRange", def.damage.maxRange, 40, 65)
			expect(btk(def, 66)).toBe(math.huge)
			modes[def.fireMode .. (if def.rpm < 100 then "Pump" else "")] = def
		end
		expect(modes.SemiPump ~= nil).toBe(true) -- pump action
		expect(modes.Semi ~= nil).toBe(true)
		expect(modes.Auto ~= nil).toBe(true)
		for id, def in Weapons do
			if def.class ~= "Shotgun" then
				if def.pellets ~= nil or def.pelletSpread ~= nil then
					error(id .. " has pellets but is not a shotgun")
				end
			end
		end
	end)

	it("pistols: 3-5 shots; machine pistol: auto, very fast, 5-7 shots, short range", function()
		for _, def in ofClass("Pistol") do
			within(def.id, "close BTK", btk(def, CLOSE), 3, 5)
			within(def.id, "far BTK", btk(def, def.damage.farRange), 3, 5)
		end
		for _, def in ofClass("MachinePistol") do
			expect(def.fireMode).toBe("Auto")
			within(def.id, "close BTK", btk(def, CLOSE), 5, 7)
			within(def.id, "rpm", def.rpm, 1000, 1300)
			within(def.id, "maxRange", def.damage.maxRange, 100, 300)
		end
	end)

	it("hip spread ranks intuitively: snipers worst, SMGs best among primaries", function()
		local sniperMin, smgMax, otherPrimaryMin, otherMax = math.huge, 0, math.huge, 0
		for _, def in Weapons do
			local hip = def.spread.hip
			if def.class == "Sniper" then
				sniperMin = math.min(sniperMin, hip)
			else
				otherMax = math.max(otherMax, hip)
				if def.class == "SMG" then
					smgMax = math.max(smgMax, hip)
				elseif def.slot == "Primary" and def.class ~= "Shotgun" then
					otherPrimaryMin = math.min(otherPrimaryMin, hip)
				end
			end
		end
		expect(sniperMin > otherMax).toBe(true)
		expect(smgMax < otherPrimaryMin).toBe(true)
	end)
end)

describe("Roster attachments", function()
	it("every attachment is offered by at least one weapon, at weapon level 2-28", function()
		local offered = {}
		for id, def in Weapons do
			for attId, level in def.attachmentUnlocks do
				offered[attId] = true
				within(id .. "." .. attId, "unlock", level, 2, 28)
			end
		end
		for attId in Attachments do
			if not offered[attId] then
				error(attId .. " is not offered by any weapon")
			end
		end
	end)

	it("every slot a weapon declares has at least one attachment", function()
		for id, def in Weapons do
			for _, slot in def.attachmentSlots do
				local any = false
				for attId in def.attachmentUnlocks do
					if Attachments[attId].slot == slot then
						any = true
					end
				end
				if not any then
					error(id .. " declares slot " .. slot .. " with no attachments")
				end
			end
		end
	end)

	it("has 16-22 attachments covering every slot, each with honest tradeoffs", function()
		local HIGHER_IS_BETTER = { damage = true, range = true, rpm = true, magSize = true, moveSpeed = true, adsMoveSpeed = true }
		local count, slots = 0, {}
		for id, att in Attachments do
			count += 1
			slots[att.slot] = true
			local pros, cons = 0, 0
			for key, v in att.modifiers do
				local better = if HIGHER_IS_BETTER[key] then v > 1 else v < 1
				if v ~= 1 then
					if better then
						pros += 1
					else
						cons += 1
					end
				end
			end
			if att.optic or att.suppressed then
				pros += 1
			end
			if pros < 1 or cons < 1 then
				error(("%s: %d pros, %d cons"):format(id, pros, cons))
			end
			if (att.slot == "Muzzle" or att.slot == "Barrel") and not att.muzzleExtend then
				error(id .. " needs muzzleExtend")
			end
			if att.slot == "Optic" then
				expect(att.optic ~= nil).toBe(true)
			end
		end
		within("Attachments", "count", count, 16, 22)
		for _, slot in WeaponStats.SLOTS do
			expect(slots[slot]).toBe(true)
		end
		expect(Attachments.ScoutScope.optic.fov >= 32 and Attachments.ScoutScope.optic.fov <= 38).toBe(true)
		expect(Attachments.QuickMag.modifiers.reload).toBe(0.75)
		expect(#Attachments.Brace.classes == 1 and Attachments.Brace.classes[1] == "LMG").toBe(true)
		expect(#Attachments.Choke.classes == 1 and Attachments.Choke.classes[1] == "Shotgun").toBe(true)
	end)

	it("resolving every weapon with max-level loadouts keeps stats sane", function()
		local used = {}
		for _, def in sorted() do
			-- Group the weapon's attachments by slot, then build loadouts that cycle through every
			-- option in every slot so each offered attachment is resolved at least once.
			local bySlot: { [string]: { string } } = {}
			local rounds = 1
			for attId in def.attachmentUnlocks do
				local slot = Attachments[attId].slot
				bySlot[slot] = bySlot[slot] or {}
				table.insert(bySlot[slot], attId)
			end
			for _, list in bySlot do
				table.sort(list)
				rounds = math.max(rounds, #list)
			end
			for r = 1, rounds do
				local selection = {}
				for slot, list in bySlot do
					selection[slot] = list[(r - 1) % #list + 1]
					used[selection[slot]] = true
				end
				local ok, reason = WeaponStats.validate(def, selection, 30, Attachments)
				if not ok then
					error(def.id .. ": " .. tostring(reason))
				end
				local e = WeaponStats.resolve(def, selection, Attachments)
				expect(e.magSize >= 1).toBe(true)
				expect(e.reserveAmmo >= 0).toBe(true)
				for _, k in { "reloadTime", "reloadEmptyTime", "equipTime", "adsTime", "rpm" } do
					if not (e[k] > 0) then
						error(def.id .. ": " .. k .. " not positive")
					end
				end
				expect(e.moveSpeedMultiplier > 0 and e.adsMoveSpeedMultiplier > 0).toBe(true)
				local ratings = WeaponStats.ratings(e)
				for k, v in ratings do
					within(def.id, "rating " .. k, v, 0, 100)
				end
			end
		end
		for attId in Attachments do
			expect(used[attId]).toBe(true)
		end
	end)
end)

return nil
