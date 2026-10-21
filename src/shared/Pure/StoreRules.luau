--!strict
-- Pure store logic: credit purchases, crate opening and Robux receipt processing. The server owns
-- every call; the client only displays. See Config/Store.luau for the policy.
local Store = require(script.Parent.Parent.Config.Store)
local CosmeticRules = require(script.Parent.CosmeticRules)

local StoreRules = {}

export type CrateResult = { kind: string?, id: string?, credits: number }

function StoreRules.owns(profile: any, kind: string, id: string): boolean
	if kind == "Camo" then
		-- store camos cover every weapon, so any weapon id checks the inventory entry
		return CosmeticRules.ownsCamo(profile, "", id)
	elseif kind == "Title" then
		return CosmeticRules.ownsTitle(profile, id)
	elseif kind == "Emblem" then
		return CosmeticRules.ownsEmblem(profile, id)
	elseif kind == "Gear" then
		return CosmeticRules.ownsGear(profile, id)
	end
	return false
end

-- Gear Crates earned by going from level `before` to level `after` (one per multiple crossed).
function StoreRules.gearCratesForLevels(before: number, after: number): number
	local every = Store.GearCrateEveryLevels
	if after <= before or every <= 0 then
		return 0
	end
	return math.floor(after / every) - math.floor(before / every)
end

local function give(profile: any, kind: string, id: string)
	profile.inventory[kind .. ":" .. id] = 1
end

function StoreRules.crates(profile: any, crateId: string): number
	local n = profile.inventory["Crate:" .. crateId]
	return if type(n) == "number" then n else 0
end

function StoreRules.addCrates(profile: any, crateId: string, n: number): number
	local before = StoreRules.crates(profile, crateId)
	local after = math.clamp(before + math.floor(n), 0, Store.MaxCrates)
	profile.inventory["Crate:" .. crateId] = if after > 0 then after else nil
	return after - before
end

function StoreRules.addCredits(profile: any, n: number): number
	local before = profile.wallet.credits
	profile.wallet.credits = math.clamp(before + math.floor(n), 0, Store.MaxCredits)
	return profile.wallet.credits - before
end

-- Returns (ok, reason). Reasons: "unknown", "owned", "funds".
function StoreRules.buy(profile: any, itemId: any): (boolean, string?)
	local item = if type(itemId) == "string" then Store.shopById[itemId] else nil
	if not item then
		return false, "unknown"
	end
	if StoreRules.owns(profile, item.grant.kind, item.grant.id) then
		return false, "owned"
	end
	if profile.wallet.credits < item.price then
		return false, "funds"
	end
	profile.wallet.credits -= item.price
	give(profile, item.grant.kind, item.grant.id)
	return true, nil
end

-- Odds as shown to the player: every entry with its chance in percent, over the whole pool. The
-- roll itself skips owned entries, so a player's real chance for each unowned item is never lower.
function StoreRules.odds(crate: Store.CrateDef): { { kind: string, id: string, percent: number } }
	local total = 0
	for _, e in crate.pool do
		total += e.weight
	end
	local out = {}
	for _, e in crate.pool do
		table.insert(out, { kind = e.kind, id = e.id, percent = math.floor(e.weight / total * 1000 + 0.5) / 10 })
	end
	return out
end

-- Picks a crate result. `r` is a server random number in [0, 1). Only entries the player does not
-- own can come out; with nothing left the crate gives `duplicateCredits`.
function StoreRules.roll(profile: any, crate: Store.CrateDef, r: number): CrateResult
	local open = {}
	local total = 0
	for _, e in crate.pool do
		if not StoreRules.owns(profile, e.kind, e.id) then
			table.insert(open, e)
			total += e.weight
		end
	end
	if total <= 0 then
		return { credits = crate.duplicateCredits }
	end
	local x = math.clamp(r, 0, 0.999999) * total
	for _, e in open do
		x -= e.weight
		if x < 0 then
			return { kind = e.kind, id = e.id, credits = 0 }
		end
	end
	local last = open[#open]
	return { kind = last.kind, id = last.id, credits = 0 }
end

-- Opens one crate. Returns (result, reason). Reasons: "unknown", "none".
function StoreRules.open(profile: any, crateId: any, r: number): (CrateResult?, string?)
	local crate = if type(crateId) == "string" then Store.crateById[crateId] else nil
	if not crate then
		return nil, "unknown"
	end
	if StoreRules.crates(profile, crate.id) < 1 then
		return nil, "none"
	end
	StoreRules.addCrates(profile, crate.id, -1)
	local result = StoreRules.roll(profile, crate, r)
	if result.kind and result.id then
		give(profile, result.kind, result.id)
	else
		StoreRules.addCredits(profile, result.credits)
	end
	profile.stats.cratesOpened += 1
	return result, nil
end

-- Robux receipt processing, idempotent by PurchaseId. Returns:
--   "granted"   the bundle was granted now (caller must save before acknowledging)
--   "duplicate" this PurchaseId was already granted (acknowledge again)
--   "unknown"   no bundle has this product id (do not acknowledge)
function StoreRules.processReceipt(profile: any, purchaseId: string, productId: number, now: number): string
	if profile.processedReceipts[purchaseId] then
		return "duplicate"
	end
	local bundle = Store.premiumByProduct[productId]
	if not bundle then
		return "unknown"
	end
	for _, g in bundle.grants do
		give(profile, g.kind, g.id)
	end
	profile.processedReceipts[purchaseId] = now
	return "granted"
end

-- Drops processed receipt ids older than the retention window.
function StoreRules.pruneReceipts(profile: any, now: number)
	local cutoff = now - Store.ReceiptRetentionDays * 86400
	for id, t in profile.processedReceipts do
		if type(t) ~= "number" or t < cutoff then
			profile.processedReceipts[id] = nil
		end
	end
end

-- Whether the player owns everything in a premium bundle (shown as OWNED, buying again is blocked).
function StoreRules.ownsBundle(profile: any, bundle: Store.PremiumBundle): boolean
	for _, g in bundle.grants do
		if not StoreRules.owns(profile, g.kind, g.id) then
			return false
		end
	end
	return true
end

return StoreRules
