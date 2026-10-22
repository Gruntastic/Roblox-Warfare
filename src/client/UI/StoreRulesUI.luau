--!strict
-- Pure helpers for the Store screen (no Instances), so the display logic is unit tested.
local StoreRulesUI = {}

export type ButtonState = { text: string, enabled: boolean }

-- What a shop card's button shows. `owned` comes from the server's ProfileSummary.
function StoreRulesUI.shopButton(price: number, credits: number, owned: boolean): ButtonState
	if owned then
		return { text = "OWNED", enabled = false }
	end
	if credits < price then
		return { text = string.format("NEED %s", StoreRulesUI.credits(price - credits)), enabled = false }
	end
	return { text = "BUY  " .. StoreRulesUI.credits(price), enabled = true }
end

-- What a premium bundle's button shows. A product id of 0 is not created yet.
function StoreRulesUI.premiumButton(productId: number, robux: number, owned: boolean): ButtonState
	if owned then
		return { text = "OWNED", enabled = false }
	end
	if productId == 0 then
		return { text = "COMING SOON", enabled = false }
	end
	return { text = string.format("R$ %d", robux), enabled = true }
end

-- "12,500 CR"
function StoreRulesUI.credits(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return out .. " CR"
end

-- Ownership from a CosmeticsView (`owned.titles`, `owned.emblems`, `owned.gears`, `owned.camos[weaponId]`).
-- Store camos cover every weapon, so any weapon's list answers for a camo.
function StoreRulesUI.owns(cosmetics: any, kind: string, id: string): boolean
	if type(cosmetics) ~= "table" or type(cosmetics.owned) ~= "table" then
		return false
	end
	local owned = cosmetics.owned
	if kind == "Title" then
		return type(owned.titles) == "table" and table.find(owned.titles, id) ~= nil
	elseif kind == "Emblem" then
		return type(owned.emblems) == "table" and table.find(owned.emblems, id) ~= nil
	elseif kind == "Gear" then
		return type(owned.gears) == "table" and table.find(owned.gears, id) ~= nil
	elseif kind == "Camo" and type(owned.camos) == "table" then
		for _, list in owned.camos do
			if type(list) == "table" and table.find(list, id) ~= nil then
				return true
			end
		end
	end
	return false
end

-- "CAMO", "TITLE", "EMBLEM"
function StoreRulesUI.kindText(kind: string?): string
	return if kind then string.upper(kind) else ""
end

-- Result line after opening a crate.
function StoreRulesUI.resultText(result: any, nameOf: (string, string) -> string): string
	if type(result) ~= "table" then
		return ""
	end
	if type(result.kind) == "string" and type(result.id) == "string" then
		return string.format("%s  %s", StoreRulesUI.kindText(result.kind), string.upper(nameOf(result.kind, result.id)))
	end
	return string.format("ALL ITEMS OWNED  +%s", StoreRulesUI.credits(result.credits or 0))
end

return StoreRulesUI
