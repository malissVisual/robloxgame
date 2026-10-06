--!strict
-- The game's pictures (the icon set and the logo): THE ONE PLACE to paste their Roblox asset ids. Pure data and a few
-- helpers, used by the client (client/Ui.luau Ui.icon, client/Theme.luau, Hud, MapView) and the server (the landmark
-- tags and the building signs in server/World.luau).
--
-- How to fill it in:
--   1. In Studio open View → Asset Manager, then Bulk Import, and pick the PNGs from zombie-delivery/art/
--      (weapons/, cargo/, map/, logo/zombie_delivery_logo.png, ui/menu_background.png, signs/sign_*.png, 5.0:
--      icons/kit_*.png and icons/app_*.png). The file name without .png is the name below (art/cargo/item_medkit.png →
--      item_medkit).
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
	-- 5.4, fuel (Codex's art/icons/jerrycan and fuel, 256 x 256 white; not uploaded yet: the emoji shows).
	jerrycan = "",
	fuel = "",
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
	sign_depot = "rbxassetid://87089552846632",
	sign_dealer = "rbxassetid://115639569125054",
	sign_guns = "rbxassetid://123141460573831",
	sign_mechanic = "rbxassetid://97072018684004",
	sign_supplies = "rbxassetid://91098163594033",
	sign_repairs = "rbxassetid://83064667353023",
	sign_garage_rented = "rbxassetid://130485099373410",
	sign_garage_south = "rbxassetid://79137409643362",
	sign_garage_harbor = "rbxassetid://119040217906033",
	sign_garage_north = "rbxassetid://125571483565293",
	sign_garage_downtown = "rbxassetid://102306588187308",
	sign_school = "rbxassetid://134831566615207",
	sign_army = "rbxassetid://73021774283333",
	sign_icecream = "rbxassetid://112565245860312",
	sign_movers = "rbxassetid://100052589557486",
	sign_farm = "rbxassetid://124679704618247",
	sign_ranch = "rbxassetid://89041333593753",
	sign_clinic = "rbxassetid://94068641536738",
	sign_gas = "rbxassetid://119898422260530",
	sign_bank = "rbxassetid://102213195192335",
	sign_pharmacy = "rbxassetid://140285318433038",
	sign_market = "rbxassetid://87728803525889",
	sign_firestation = "rbxassetid://103734155347474",
	sign_police = "rbxassetid://72000919671523",
	sign_cityhall = "rbxassetid://126428500923451",
	sign_dispatchtower = "rbxassetid://124046349643095",
	sign_harborpoint = "rbxassetid://84043645079818",
	sign_docks = "rbxassetid://127916586301620",
	sign_warehouse = "rbxassetid://103754751141675",
	sign_fueldepot = "rbxassetid://116197782627584",
	sign_powerplant = "rbxassetid://102674461898579",
	sign_waterworks = "rbxassetid://121867152934774",
	sign_trainyard = "rbxassetid://74037540854230",
	sign_radio = "rbxassetid://88067436002095",
	sign_lodge = "rbxassetid://72042482914607",
	sign_stables = "rbxassetid://108042587549363",
	sign_airfield = "rbxassetid://122019931233089",
	sign_lab = "rbxassetid://125707012545018",
	sign_prison = "rbxassetid://85941874495490",
	sign_lighthouse = "rbxassetid://115473458028380",
	sign_camp = "rbxassetid://78085955478596",
	sign_stadium = "rbxassetid://95957878226769",
	sign_hilltop = "rbxassetid://133159699715834",
	sign_oceanview = "rbxassetid://84790406621047",
	sign_pinecrest = "rbxassetid://72900693374404",
	sign_lakeside = "rbxassetid://114054270820568",
	sign_sunset = "rbxassetid://108824816687993",
	sign_maple = "rbxassetid://130770177975719",
	sign_oak = "rbxassetid://102196593157052",
	sign_birch = "rbxassetid://125910362508535",
	sign_elm = "rbxassetid://117757032087688",
	sign_office_harbor = "rbxassetid://98838604316825",
	sign_office_tower = "rbxassetid://123929738866726",
	sign_office_penthouse = "rbxassetid://84138164235299",
	-- 5.0, the personal kit (art/icons/kit_*, 256 x 256; Config.Kit ids, the cart is not sold yet): the KIT tab.
	kit_backpack = "",
	kit_bigpack = "",
	kit_shoes = "",
	kit_jacket = "",
	kit_cart = "",
	-- 5.0, the phone's apps (art/icons/app_*, 256 x 256; client/Phone.luau's app ids, bank and settings for later).
	app_orders = "",
	app_board = "",
	app_career = "",
	app_shop = "",
	app_map = "",
	app_messages = "",
	app_bank = "",
	app_settings = "",
	-- 5.1, the bikes, their gear and the bike shop's map marker (art/icons, Codex's; 256 x 256 white). Empty: not
	-- uploaded yet (the emoji shows).
	bike_rust = "",
	bike_city = "",
	bike_cargo = "",
	bike_ebike = "",
	gear_basket = "",
	gear_panniers = "",
	gear_trailer = "",
	map_bikes = "",
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

-- An item (Config.Items id). 5.4: the jerry can's picture is Codex's art/icons/jerrycan (no item_ prefix).
local ITEM_NAMES: { [string]: string } = { jerrycan = "jerrycan" }
function Icons.item(itemId: string?): string?
	local name = if itemId then ITEM_NAMES[itemId] else nil
	if name then
		return if Icons.Ids[name] ~= nil then name else nil
	end
	return named("item_", itemId)
end

-- 5.1: a bike (a Config.Cars id with bike = true); nil for anything else.
local BIKE_ICONS: { [string]: string } = { rustbike = "bike_rust", citybike = "bike_city", cargobike = "bike_cargo", ebike = "bike_ebike" }
function Icons.bike(carId: string?): string?
	local name = if carId then BIKE_ICONS[carId] else nil
	return if name and Icons.Ids[name] ~= nil then name else nil
end

-- 5.1: a piece of gear (Config.Gear id) with a picture of its own (the bike gear); nil for the others (the emoji).
function Icons.gear(gearId: string?): string?
	return named("gear_", gearId)
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
	pallet = "crate", -- 4.0, freight: a pallet of boxes
	-- 5.3, the storefronts' own pieces
	burger = "pizza", -- a food bag
	noodles = "soup",
	pastry = "sack",
	newspaper = "parcel",
	bouquet = "sack",
	icecream = "icebox",
	gadget = "crate",
}

-- 5.0: a piece of personal kit (Config.Kit id: backpack, bigpack, shoes, jacket).
function Icons.kit(kitId: string?): string?
	return named("kit_", kitId)
end

-- 5.0: an app of the phone (client/Phone.luau: orders, board, career, shop, map, messages).
function Icons.app(appId: string?): string?
	return named("app_", appId)
end

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
	earl = "dealer", -- 5.0, Earl's Used Wheels: a car for sale
	gas_downtown = "gas", -- 5.4, the new gas stations (Map.GasStations): the Gas Station's pump
	gas_harbor = "gas",
	gas_suburbs = "gas",
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
	-- 5.3, the storefronts (Map.Venues): what they send
	luigis = "cargo_pizza",
	dailybread = "cargo_sack", -- bread
	lastbite = "cargo_pizza", -- a food box
	wokdead = "cargo_soup",
	grindhouse = "cargo_soup", -- a hot cup
	postoffice = "cargo_parcel",
	dailyundead = "cargo_sack", -- the mail bag
	boltnail = "item_repair",
	volt = "cargo_crate",
	secondlife = "cargo_ammo",
	bloom = "cargo_sack", -- the plants
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
