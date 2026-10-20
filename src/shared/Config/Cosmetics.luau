--!strict
-- Cosmetic catalogue: weapon camos, player titles and prestige emblems. Cosmetics never change
-- gameplay. Everything here is earned by play and ownership is DERIVED from progress
-- (Pure/CosmeticRules.luau), so nothing has to be granted or stored when it is earned.
-- Items with a `source` ("shop", "crate" or "premium") are not earned by progress: they are owned
-- only through an inventory entry "<Kind>:<id>" granted by the store (Config/Store.luau).

export type CamoDef = {
	id: string,
	name: string,
	-- unlock, per weapon: kills with that weapon, and optionally headshots with it
	kills: number,
	headshots: number?,
	-- look: body parts take this colour and material; `accent` (optional) tints the secondary parts
	color: Color3,
	material: Enum.Material,
	accent: Color3?,
	source: string?, -- nil = earned by kills; otherwise owned only through the inventory
}

export type TitleDef = {
	id: string,
	name: string, -- shown in capitals under the player name
	-- unlock: a lifetime stat reaching a value (nil = owned by everyone)
	stat: string?,
	value: number?,
	description: string,
	source: string?,
}

export type EmblemDef = {
	id: string,
	name: string,
	prestige: number, -- owned once the player has reached this prestige
	color: Color3,
	glyph: string, -- short text drawn on the badge
	source: string?, -- nil = prestige emblem; otherwise owned only through the inventory
}

local camos: { CamoDef } = {
	{ id = "Factory", name = "Factory", kills = 0, color = Color3.fromRGB(40, 42, 46), material = Enum.Material.Metal },
	{ id = "DesertStipple", name = "Desert Stipple", kills = 25, color = Color3.fromRGB(176, 148, 104), material = Enum.Material.Sand, accent = Color3.fromRGB(120, 96, 64) },
	{ id = "ForestSplinter", name = "Forest Splinter", kills = 75, color = Color3.fromRGB(70, 92, 58), material = Enum.Material.Fabric, accent = Color3.fromRGB(44, 56, 38) },
	{ id = "UrbanHex", name = "Urban Hex", kills = 150, color = Color3.fromRGB(110, 114, 122), material = Enum.Material.DiamondPlate, accent = Color3.fromRGB(64, 66, 72) },
	{ id = "ArcticTiger", name = "Arctic Tiger", kills = 300, color = Color3.fromRGB(214, 222, 232), material = Enum.Material.Snow, accent = Color3.fromRGB(92, 104, 120) },
	{ id = "Gilded", name = "Gilded", kills = 300, headshots = 100, color = Color3.fromRGB(212, 168, 64), material = Enum.Material.Foil, accent = Color3.fromRGB(150, 110, 36) },
	-- Phase 6 store camos: one purchase covers every weapon
	{ id = "Obsidian", name = "Obsidian", kills = 0, source = "shop", color = Color3.fromRGB(24, 24, 30), material = Enum.Material.Glass, accent = Color3.fromRGB(70, 60, 110) },
	{ id = "Cobalt", name = "Cobalt", kills = 0, source = "shop", color = Color3.fromRGB(40, 80, 160), material = Enum.Material.SmoothPlastic, accent = Color3.fromRGB(24, 40, 80) },
	{ id = "Ember", name = "Ember", kills = 0, source = "shop", color = Color3.fromRGB(190, 70, 30), material = Enum.Material.CrackedLava, accent = Color3.fromRGB(60, 24, 16) },
	{ id = "RustBloom", name = "Rust Bloom", kills = 0, source = "crate", color = Color3.fromRGB(150, 80, 50), material = Enum.Material.CorrodedMetal, accent = Color3.fromRGB(90, 60, 40) },
	{ id = "Tidewater", name = "Tidewater", kills = 0, source = "crate", color = Color3.fromRGB(50, 120, 130), material = Enum.Material.Slate, accent = Color3.fromRGB(30, 70, 80) },
	{ id = "Sandstorm", name = "Sandstorm", kills = 0, source = "crate", color = Color3.fromRGB(200, 170, 120), material = Enum.Material.Sandstone, accent = Color3.fromRGB(150, 120, 80) },
	{ id = "Founder", name = "Founder", kills = 0, source = "premium", color = Color3.fromRGB(30, 34, 40), material = Enum.Material.Metal, accent = Color3.fromRGB(255, 176, 32) },
}

local titles: { TitleDef } = {
	{ id = "Recruit", name = "Recruit", description = "Everyone starts here." },
	{ id = "FirstBlood", name = "First Blood", stat = "kills", value = 1, description = "Get a kill." },
	{ id = "Centurion", name = "Centurion", stat = "kills", value = 100, description = "Get 100 kills." },
	{ id = "Veteran", name = "Veteran", stat = "kills", value = 1000, description = "Get 1,000 kills." },
	{ id = "Marksman", name = "Marksman", stat = "headshots", value = 100, description = "Get 100 headshot kills." },
	{ id = "Victor", name = "Victor", stat = "wins", value = 25, description = "Win 25 matches." },
	{ id = "FlagBearer", name = "Flag Bearer", stat = "captures", value = 50, description = "Capture 50 Domination flags." },
	{ id = "Demolitionist", name = "Demolitionist", stat = "plants", value = 25, description = "Plant 25 bombs." },
	{ id = "WireCutter", name = "Wire Cutter", stat = "defuses", value = 10, description = "Defuse 10 bombs." },
	{ id = "Collector", name = "Collector", stat = "tags", value = 100, description = "Collect 100 tags in Kill Confirmed." },
	{ id = "DailyDriver", name = "Daily Driver", stat = "dailies", value = 30, description = "Complete 30 daily challenges." },
	{ id = "Quartermaster", name = "Quartermaster", source = "shop", description = "Bought in the store." },
	{ id = "Scrapper", name = "Scrapper", source = "crate", description = "Found in a supply crate." },
	{ id = "NightOwl", name = "Night Owl", source = "crate", description = "Found in a supply crate." },
	{ id = "LuckyCharm", name = "Lucky Charm", source = "crate", description = "Found in a supply crate." },
	{ id = "Founder", name = "Founder", source = "premium", description = "Part of the Founder Pack." },
}

local EMBLEM_COLORS = {
	Color3.fromRGB(150, 160, 170),
	Color3.fromRGB(120, 170, 120),
	Color3.fromRGB(90, 150, 210),
	Color3.fromRGB(150, 110, 210),
	Color3.fromRGB(210, 120, 70),
	Color3.fromRGB(210, 80, 80),
	Color3.fromRGB(70, 190, 190),
	Color3.fromRGB(230, 200, 90),
	Color3.fromRGB(235, 235, 240),
	Color3.fromRGB(255, 176, 32),
}
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }

local emblems: { EmblemDef } = {}
for i = 1, 10 do
	table.insert(emblems, { id = "Prestige" .. i, name = "Prestige " .. ROMAN[i], prestige = i, color = EMBLEM_COLORS[i], glyph = ROMAN[i] })
end
-- Phase 6 store emblems (`prestige` is unreachable; they are owned only through the inventory)
for _, e in {
	{ id = "Wolf", name = "Wolf", source = "shop", color = Color3.fromRGB(120, 130, 140), glyph = "W" },
	{ id = "Anchor", name = "Anchor", source = "crate", color = Color3.fromRGB(60, 110, 170), glyph = "A" },
	{ id = "Star", name = "Star", source = "crate", color = Color3.fromRGB(230, 200, 90), glyph = "★" },
	{ id = "Skull", name = "Skull", source = "crate", color = Color3.fromRGB(200, 200, 205), glyph = "☠" },
	{ id = "Founder", name = "Founder", source = "premium", color = Color3.fromRGB(255, 176, 32), glyph = "F" },
} do
	table.insert(emblems, { id = e.id, name = e.name, prestige = math.huge, color = e.color, glyph = e.glyph, source = e.source })
end

local Cosmetics = {
	camos = camos,
	titles = titles,
	emblems = emblems,
	camoById = {} :: { [string]: CamoDef },
	titleById = {} :: { [string]: TitleDef },
	emblemById = {} :: { [string]: EmblemDef },
	DefaultCamo = "Factory",
	DefaultTitle = "Recruit",
	-- Weapon body parts a camo repaints: "Main" takes the camo colour, "Accent" its accent colour
	-- (or the main colour when it has none). Barrels, sights, optics and attachments keep their look.
	CamoParts = {
		Receiver = "Main",
		Stock = "Main",
		StockTop = "Main",
		FoldedStock = "Main",
		Handguard = "Main",
		Slide = "Main",
		Frame = "Main",
		CarryHandle = "Accent",
		HandguardCap = "Accent",
		CheekRest = "Accent",
		CheekPiece = "Accent",
		Magazine = "Accent",
		Grip = "Accent",
		ScopeTube = "Accent",
	} :: { [string]: string },
}
for _, c in camos do
	Cosmetics.camoById[c.id] = c
end
for _, t in titles do
	Cosmetics.titleById[t.id] = t
end
for _, e in emblems do
	Cosmetics.emblemById[e.id] = e
end

return Cosmetics
