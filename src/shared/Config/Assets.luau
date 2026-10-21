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

-- ForgeGUI mesh models published as Roblox Models, keyed "Prop.<MapPropKey>", "Weapon.<WeaponId>",
-- "Streak.<KillstreakId>" or "Gear.<Piece>". The server's EnvironmentService loads them with
-- InsertService (only works when the experience is owned by the same creator) into
-- ReplicatedStorage.ForgeModels, and ModelSkin stretches them over the part-built object they
-- replace. 0, or a model that fails to load, keeps the part-built look.
Assets.Models = {
	["Prop.Container"] = 110711970414624,
	["Weapon.VK7"] = 73413732325934,
	["Weapon.KT9"] = 90059341898722,
	["Weapon.SW3"] = 132319886882773,
	["Weapon.HL4"] = 104328653393941,
	["Weapon.MN8"] = 95373454315857,
} :: { [string]: number }

-- Models that come out facing backwards after fitting (set while checking them in Studio).
Assets.ModelFlip = {} :: { [string]: boolean }

-- Tiled materials (ForgeGUI colour + normal maps) registered as MaterialVariants "Forge<Key>" and
-- put on map parts whose material is listed in MaterialFor. 0 = not made (the part keeps Roblox's
-- material).
export type MaterialDef = { base: string, color: number, normal: number, studsPerTile: number }
Assets.Materials = {
	Concrete = { base = "Concrete", color = 0, normal = 0, studsPerTile = 12 },
	Asphalt = { base = "Asphalt", color = 128206237673610, normal = 99681344651388, studsPerTile = 14 },
	RustMetal = { base = "CorrodedMetal", color = 91987101803394, normal = 104835294226821, studsPerTile = 8 },
	DiamondPlate = { base = "DiamondPlate", color = 76061249091139, normal = 122781367108140, studsPerTile = 4 },
	Sandstone = { base = "Sandstone", color = 95939512657764, normal = 116580111971117, studsPerTile = 16 },
	DesertSand = { base = "Sand", color = 138268408927558, normal = 112974311179565, studsPerTile = 16 },
	Snow = { base = "Snow", color = 85597390036945, normal = 84089334127592, studsPerTile = 16 },
	Brick = { base = "Brick", color = 75366507502959, normal = 124421313111907, studsPerTile = 8 },
	WoodPlanks = { base = "WoodPlanks", color = 84682361402687, normal = 125307711190017, studsPerTile = 8 },
	Rock = { base = "Rock", color = 112845177667095, normal = 106714473261989, studsPerTile = 14 },
	Grass = { base = "Grass", color = 0, normal = 0, studsPerTile = 12 },
	CorrugatedMetal = { base = "Metal", color = 126435293710946, normal = 0, studsPerTile = 6 },
} :: { [string]: MaterialDef }

-- Enum.Material name -> Materials key, for map parts.
Assets.MaterialFor = {
	Concrete = "Concrete",
	Asphalt = "Asphalt",
	CorrodedMetal = "RustMetal",
	DiamondPlate = "DiamondPlate",
	Sandstone = "Sandstone",
	Sand = "DesertSand",
	Snow = "Snow",
	Brick = "Brick",
	WoodPlanks = "WoodPlanks",
	Rock = "Rock",
	Slate = "Rock",
	Grass = "Grass",
} :: { [string]: string }

-- Part name -> Materials key, checked before MaterialFor (plain Metal is used for too many shapes to
-- texture as corrugated sheet everywhere).
Assets.MaterialForName = {
	Container = "CorrugatedMetal",
	ShedWall = "CorrugatedMetal",
} :: { [string]: string }

-- Skyboxes per map id (ForgeGUI panorama cut into six faces). A map with any face at 0 keeps the
-- default sky.
export type SkyDef = { Bk: number, Dn: number, Ft: number, Lf: number, Rt: number, Up: number }
Assets.Skies = {
	RedMesa = { Bk = 84010583750443, Dn = 97551706494257, Ft = 70858999278779, Lf = 130129960090215, Rt = 138072131914134, Up = 81176254382072 },
	FrostRelay = { Bk = 130115281041068, Dn = 100773550391758, Ft = 119269788470371, Lf = 95464509433132, Rt = 125857041545456, Up = 130609739813896 },
	DustlineTerminal = { Bk = 72515196917260, Dn = 117901660877437, Ft = 90169538536736, Lf = 115927860414524, Rt = 130196493495241, Up = 130474457331181 },
	Breakwater = { Bk = 123835844291604, Dn = 103798782546401, Ft = 99305049463582, Lf = 116655752376811, Rt = 133132420612531, Up = 83216081730017 },
	AshwoodEstate = { Bk = 76788942282428, Dn = 73216417426760, Ft = 128298763169967, Lf = 74483969156134, Rt = 74437120897601, Up = 72396254754420 },
} :: { [string]: SkyDef }

local function content(id: number?): string?
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. tostring(id)
	end
	return nil
end

-- "rbxassetid://<id>" for a published id, nil for 0 / missing.
function Assets.content(id: number?): string?
	return content(id)
end

function Assets.image(key: string): string?
	return content(Assets.Images[key])
end

function Assets.clothing(key: string): string?
	return content(Assets.Clothing[key])
end

return Assets
