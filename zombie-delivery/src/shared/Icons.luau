--!strict
-- The game's pictures (the icon set and the logo): THE ONE PLACE to paste their Roblox asset ids. Pure data and a few
-- helpers, used by the client (client/Ui.luau Ui.icon, client/Theme.luau, Hud, MapView) and the server (the landmark
-- tags in server/World.luau).
--
-- How to fill it in:
--   1. In Studio open View → Asset Manager, then Bulk Import, and pick the PNGs from zombie-delivery/art/
--      (weapons/, cargo/, map/, logo/zombie_delivery_logo.png, ui/menu_background.png). The file name without .png is
--      the name below (art/cargo/item_medkit.png → item_medkit).
--   2. Right-click an uploaded image → Copy Asset ID.
--   3. Paste it here as "rbxassetid://<the number>", e.g. weapon_pistol = "rbxassetid://1234567890".
-- An empty id means "not uploaded": the game then shows the emoji / text it always showed. The icons are white
-- silhouettes; the interface tints them (ImageColor3). The logo and the menu background are colour images.

local Icons = {}

Icons.Ids = {
	-- Hand guns (art/weapons, 256 x 256, barrels point left).
	weapon_pistol = "",
	weapon_smg = "",
	weapon_shotgun = "",
	weapon_rifle = "",
	weapon_minigun = "",
	weapon_launcher = "",
	weapon_revolver = "",
	weapon_carbine = "",
	-- Cargo pieces (art/cargo, 256 x 256).
	cargo_crate = "",
	cargo_ammo = "",
	cargo_sack = "",
	cargo_barrel = "",
	cargo_icebox = "",
	cargo_furniture = "",
	cargo_soup = "",
	cargo_horse = "",
	cargo_kid = "",
	cargo_parcel = "",
	cargo_pizza = "",
	cargo_medicine = "",
	-- Items (art/cargo, 256 x 256).
	item_repair = "",
	item_medkit = "",
	item_nitro = "",
	item_molotov = "",
	item_mine = "",
	-- Map markers: shops, employers, far places (art/map, 128 x 128).
	map_depot = "",
	map_dealer = "",
	map_guns = "",
	map_mechanic = "",
	map_supplies = "",
	map_school = "",
	map_army = "",
	map_icecream = "",
	map_movers = "",
	map_farm = "",
	map_ranch = "",
	map_gas = "",
	map_stables = "",
	map_fueldepot = "",
	map_lodge = "",
	map_radio = "",
	map_docks = "",
	-- Colour images: the wordmark on the start menu (art/logo) and its background (art/ui).
	zombie_delivery_logo = "",
	menu_background = "",
} :: { [string]: string }

-- The asset id of an icon, or nil while it is empty (not uploaded) or unknown.
function Icons.get(name: string?): string?
	if name == nil then
		return nil
	end
	local id = Icons.Ids[name]
	return if id ~= nil and id ~= "" then id else nil
end

-- The icon name for `prefix_id` if the set has one.
local function named(prefix: string, id: string?): string?
	if id == nil then
		return nil
	end
	local name = prefix .. id
	return if Icons.Ids[name] ~= nil then name else nil
end

-- A hand gun (Config.Weapons id). The car guns (Config.CarGuns) have no icon: nil.
function Icons.weapon(weaponId: string?): string?
	return named("weapon_", weaponId)
end

-- An item (Config.Items id).
function Icons.item(itemId: string?): string?
	return named("item_", itemId)
end

-- The cargo kinds (Config.Cargo.Kinds, the job types' itemKind) and the looks of the pieces (Config.Jobs.Businesses
-- look, server/Cargo.luau) that have no picture of their own: the closest one.
local CARGO_ALIASES: { [string]: string } = {
	bread = "sack",
	groceries = "crate",
	tools = "crate",
	gold = "crate",
	cake = "crate",
	vaccine = "medicine",
	sample = "medicine",
}

-- A piece of cargo: a kind (crate, ammo, sack, barrel, icebox, furniture, soup, horse, kid) or a look (pizza, parcel,
-- medicine, bread, groceries, tools, gold, cake, vaccine, sample, ...). Unknown ones get nil.
function Icons.cargo(kindOrLook: string?): string?
	if kindOrLook == nil then
		return nil
	end
	return named("cargo_", CARGO_ALIASES[kindOrLook] or kindOrLook)
end

-- A landmark on the maps and in the world (shared/Map.luau Map.Landmarks id: the shops, the employers, the far
-- places). The ids are the icons' names; the place ids that differ from them are listed here.
local LANDMARK_ALIASES: { [string]: string } = {
	frosty = "icecream", -- Frosty's Ice Cream as a place (Map.Places); the employer is "icecream"
	base = "army", -- the Military Base as a place; the employer is "army"
}

function Icons.landmark(landmarkId: string?): string?
	if landmarkId == nil then
		return nil
	end
	return named("map_", LANDMARK_ALIASES[landmarkId] or landmarkId)
end

return Icons
