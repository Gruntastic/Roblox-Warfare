--!strict
-- Image assets made with ForgeGUI and published to Roblox (creator: user 2930909850). Each entry is
-- a Roblox image asset id; 0 means "not made yet" and the UI draws its code-built fallback, so art
-- can arrive one slot at a time. docs/ASSETS.md lists the prompt and ForgeGUI job behind every id.
--
-- Use from code through Assets.image(key) -> "rbxassetid://..." or nil.

local Assets = {}

Assets.Images = {
	-- brand
	Emblem = 118115512723395, -- helmet + crossed rifles crest, no text (transparent)
	Wordmark = 70671837095623, -- "BLOX OPS" wordmark (transparent). Text is AI-drawn: check spelling before relying on it
	WordmarkAlt = 128654814891850, -- second wordmark take (unused; same spelling caveat)
	-- skin (9-slice candidates; not wired until their slice margins are measured in Studio)
	ButtonPlate = 123335665778673,
	PanelFrame = 136481523974556,
	-- menu icons (transparent, white glyph with amber accent)
	["Icon.Invite"] = 119113864005333,
	["Icon.Gunsmith"] = 0, -- ForgeGUI job outcome unknown; nav draws its fallback
	["Icon.Shop"] = 82267407289363,
	["Icon.Queue"] = 75984596555566,
	["Icon.Operator"] = 102981023062353,
	["Icon.Barracks"] = 71773357024240,
	["Icon.Perks"] = 98292108000414,
	["Icon.Streaks"] = 135539716720049,
	["Icon.Credits"] = 90338914172903,
	["Icon.Loadout"] = 128230900418279,
	-- mode select cards (Config/Modes ids, plus Any)
	["Mode.TDM"] = 138888433675654,
	["Mode.FFA"] = 137768731021610,
	["Mode.DOM"] = 93084643899574,
	["Mode.SND"] = 88033669720864,
	["Mode.HP"] = 122104109212964,
	["Mode.KC"] = 122982218119264,
	["Mode.Any"] = 120164935087933,
	-- map vote cards (map module ids)
	["Map.DustlineTerminal"] = 71148569132712,
	["Map.AshwoodEstate"] = 106950438266405,
	["Map.Breakwater"] = 139382392145510,
	["Map.FrostRelay"] = 81657916482451,
	["Map.IronBorough"] = 97584074198696,
	["Map.RedMesa"] = 73695390093233,
	-- store crates (Config/Store crate ids)
	["Crate.Supply"] = 89203956507124,
	["Crate.Gear"] = 135572800292611,
	-- staging room back wall
	StagingBackdrop = 131024147372939,
} :: { [string]: number }

-- Classic clothing templates (585x559) per team (Sable/Talon) and gear set, used as Shirt/Pants templates on operators.
-- 0 keeps the code-coloured body instead (see GearBuilder).
Assets.Clothing = {
	["Sable.Shirt"] = 107310306442215,
	["Sable.Pants"] = 108995154010417,
	["Talon.Shirt"] = 0,
	["Talon.Pants"] = 85793974904905,
	-- Gear-set pairs are used only when both pieces exist (Arctic and the NightOps shirt did not finish)
	["NightOps.Shirt"] = 0,
	["NightOps.Pants"] = 98347295472879,
	["Arctic.Shirt"] = 0,
	["Arctic.Pants"] = 0,
} :: { [string]: number }

-- Optional mesh gear (ForgeGUI 3D models published as Roblox Models). GearBuilder could load them with
-- InsertService, which only works when the experience is owned by the same creator. 0 or a failed
-- load keeps the part-built gear. None are made yet (images only so far), so nothing loads them.
Assets.GearModels = {
	Helmet = 0,
	PlateCarrier = 0,
	Backpack = 0,
} :: { [string]: number }

local function content(id: number?): string?
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. tostring(id)
	end
	return nil
end

function Assets.image(key: string): string?
	return content(Assets.Images[key])
end

function Assets.clothing(key: string): string?
	return content(Assets.Clothing[key])
end

return Assets
