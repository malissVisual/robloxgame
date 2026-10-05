--!strict
-- The game's pictures (the icon set and the logo): THE ONE PLACE to paste their Roblox asset ids. Pure data and a few
-- helpers, used by the client (client/Ui.luau Ui.icon, client/Theme.luau, Hud, MapView) and the server (the landmark
-- tags and the building signs in server/World.luau).
--
-- How to fill it in:
--   1. In Studio open View → Asset Manager, then Bulk Import, and pick the PNGs from zombie-delivery/art/
--      (weapons/, cargo/, map/, logo/zombie_delivery_logo.png, ui/menu_background.png, signs/sign_*.png). The file
--      name without .png is the name below (art/cargo/item_medkit.png → item_medkit).
--   2. Right-click an uploaded image → Copy Asset ID.
--   3. Paste it here as "rbxassetid://<the number>", e.g. weapon_pistol = "rbxassetid://1234567890".
-- An empty id means "not uploaded": the game then shows the emoji / text it always showed. The icons are white
-- silhouettes; the interface tints them (ImageColor3). The logo, the menu background and the signs are colour images.

local Icons = {}

Icons.Ids = {
	-- Hand guns (art/weapons, 256 x 256, barrels point left).
	weapon_pistol = "rbxassetid://101331767609013",
	weapon_smg = "rbxassetid://119449303683660",
	weapon_shotgun = "rbxassetid://72257395735033",
	weapon_rifle = "rbxassetid://82838152114688",
	weapon_minigun = "rbxassetid://134770850536162",
	weapon_launcher = "rbxassetid://131909691904753",
	weapon_revolver = "rbxassetid://80356375284220",
	weapon_carbine = "rbxassetid://81347117341771",
	-- Cargo pieces (art/cargo, 256 x 256).
	cargo_crate = "rbxassetid://75523684257726",
	cargo_ammo = "rbxassetid://111611924653943",
	cargo_sack = "rbxassetid://104931137634009",
	cargo_barrel = "rbxassetid://89493457007448",
	cargo_icebox = "rbxassetid://109142175639855",
	cargo_furniture = "rbxassetid://112902178929303",
	cargo_soup = "rbxassetid://74803741916590",
	cargo_horse = "rbxassetid://98278372955887",
	cargo_kid = "rbxassetid://129744118068463",
	cargo_parcel = "rbxassetid://78241225705599",
	cargo_pizza = "rbxassetid://130054548111151",
	cargo_medicine = "rbxassetid://110277502418757",
	-- Items (art/cargo, 256 x 256).
	item_repair = "rbxassetid://121885914064020",
	item_medkit = "rbxassetid://116950241930496",
	item_nitro = "rbxassetid://124345149039037",
	item_molotov = "rbxassetid://94641923810845",
	item_mine = "rbxassetid://109583785484960",
	-- Map markers: shops, employers, far places (art/map, 128 x 128).
	map_depot = "rbxassetid://137094707646902",
	map_dealer = "rbxassetid://109132509782464",
	map_guns = "rbxassetid://121011856009443",
	map_mechanic = "rbxassetid://95899926226207",
	map_supplies = "rbxassetid://80168046703740",
	map_school = "rbxassetid://122226254141090",
	map_army = "rbxassetid://105972531529923",
	map_icecream = "rbxassetid://129133942150435",
	map_movers = "rbxassetid://91004454844161",
	map_farm = "rbxassetid://121563658262528",
	map_ranch = "rbxassetid://80193448380170",
	map_gas = "rbxassetid://84875113894227",
	map_stables = "rbxassetid://104885950795696",
	map_fueldepot = "rbxassetid://112795570877883",
	map_lodge = "rbxassetid://128717549830291",
	map_radio = "rbxassetid://119834540744939",
	map_docks = "rbxassetid://83445442717149",
	-- Colour images: the wordmark on the start menu (art/logo) and its background (art/ui).
	zombie_delivery_logo = "rbxassetid://104053473081511",
	menu_background = "rbxassetid://138860042447767",
	-- Building signs (art/signs: 1024 x 256 boards, 512 x 512 badges), colour images on the buildings (server/World).
	sign_depot = "", sign_dealer = "", sign_guns = "", sign_mechanic = "",
	sign_supplies = "", sign_repairs = "", sign_garage_rented = "", sign_garage_south = "",
	sign_garage_harbor = "", sign_garage_north = "", sign_garage_downtown = "", sign_school = "",
	sign_army = "", sign_icecream = "", sign_movers = "", sign_farm = "",
	sign_ranch = "", sign_clinic = "", sign_gas = "", sign_bank = "",
	sign_pharmacy = "", sign_market = "", sign_firestation = "", sign_police = "",
	sign_cityhall = "", sign_dispatchtower = "", sign_harborpoint = "", sign_docks = "",
	sign_warehouse = "", sign_fueldepot = "", sign_powerplant = "", sign_waterworks = "",
	sign_trainyard = "", sign_radio = "", sign_lodge = "", sign_stables = "",
	sign_airfield = "", sign_lab = "", sign_prison = "", sign_lighthouse = "",
	sign_camp = "", sign_stadium = "", sign_hilltop = "", sign_oceanview = "",
	sign_pinecrest = "", sign_lakeside = "", sign_sunset = "", sign_maple = "",
	sign_oak = "", sign_birch = "", sign_elm = "", sign_office_harbor = "",
	sign_office_tower = "", sign_office_penthouse = "",
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

-- The exclusive guns (3.1) have no picture of their own yet: the closest one.
local WEAPON_ALIASES: { [string]: string } = {
	reyes = "carbine",
	lever = "rifle",
	goldpistol = "pistol",
	deadend = "rifle",
}

-- A hand gun (Config.Weapons id). The car guns (Config.CarGuns) have no icon: nil.
function Icons.weapon(weaponId: string?): string?
	if weaponId == nil then
		return nil
	end
	return named("weapon_", WEAPON_ALIASES[weaponId] or weaponId)
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
	cash = "crate",
	patient = "kid",
	-- 3.0, the missions' cargo
	water = "barrel",
	generator = "crate",
	battery = "crate",
	tnt = "ammo",
	documents = "parcel",
	electronics = "crate",
	weapons = "ammo",
	painting = "furniture",
	mail = "sack",
	tires = "crate",
	plants = "sack",
	survivor = "kid",
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
	-- The real estate (2.6) has no map icons of its own: the closest ones.
	sunsethills = "lodge", -- a house (the Hilltop Mansion)
	oceanview = "lodge", -- the other mansions and the villas that stand on their own
	pinecrest = "lodge",
	lakeside = "lodge",
	sunset = "lodge",
	dispatchtower = "depot", -- where your delivery company is run from
	harborpoint = "depot",
	garage_harbor = "dealer", -- a car
	garage_north = "dealer",
	garage_downtown = "dealer",
	garage_rented = "dealer", -- 3.4, the small garages
	garage_south = "dealer",
	repairs = "mechanic", -- 3.4, the second repair shop: a wrench like Wrench Garage
	-- The missions' places (3.0) have no map icons of their own either: the closest ones.
	market = "supplies", -- a shop full of things
	airfield = "army",
	powerplant = "fueldepot", -- energy
	prison = "guns",
	lighthouse = "docks", -- the sea
	trainyard = "movers", -- freight
	cityhall = "school", -- a public building with a flag
}
-- Landmarks with no map icon of their own yet: another icon's full name.
local LANDMARK_BORROWED: { [string]: string } = {
	bank = "cargo_crate",
	clinic = "cargo_medicine",
	-- 3.0, the missions' places
	pharmacy = "item_medkit",
	warehouse = "cargo_parcel",
	firestation = "item_molotov", -- the flame
	police = "weapon_revolver",
	waterworks = "cargo_barrel",
	lab = "cargo_medicine",
	camp = "cargo_soup",
	stadium = "cargo_kid", -- people sheltering there
}

function Icons.landmark(landmarkId: string?): string?
	if landmarkId == nil then
		return nil
	end
	local borrowed = LANDMARK_BORROWED[landmarkId]
	if borrowed then
		return if Icons.Ids[borrowed] ~= nil then borrowed else nil
	end
	return named("map_", LANDMARK_ALIASES[landmarkId] or landmarkId)
end

-- The building signs (art/signs). The square badges (512 x 512): the garages and the homes; every other sign is a
-- wide board (1024 x 256, 4 : 1). Two places use their employer's sign.
local SQUARE_SIGNS: { [string]: boolean } = {
	garage_rented = true,
	garage_south = true,
	garage_harbor = true,
	garage_north = true,
	garage_downtown = true,
	hilltop = true,
	oceanview = true,
	pinecrest = true,
	lakeside = true,
	sunset = true,
	maple = true,
	oak = true,
	birch = true,
	elm = true,
}
local SIGN_ALIASES: { [string]: string } = {
	base = "army", -- the Military Base as a place
	frosty = "icecream", -- Frosty's Ice Cream as a place
}

-- The sign of a building (Map / Config id: a shop, an employer, a place, a tower, a home, a garage, an office).
function Icons.sign(buildingId: string?): string?
	if buildingId == nil then
		return nil
	end
	return named("sign_", SIGN_ALIASES[buildingId] or buildingId)
end

-- How wide a building's sign is for its height: 1 for a square badge, 4 for a board.
function Icons.signAspect(buildingId: string?): number
	local name = Icons.sign(buildingId)
	return if name ~= nil and SQUARE_SIGNS[string.sub(name, 6)] then 1 else 4
end

return Icons
