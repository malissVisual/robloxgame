--!strict
-- 6.12.11: the job pictures (Codex's 25 business pictures, art/job-thumbnails/ and design/job-thumbnails/README.md):
-- which business's picture a job shows on the job lists (client/JobThumbUi.luau: the phone's BOARD and J's board).
-- Pure data, no Roblox: the tests and tools/job-thumbnails/check.py read it.
--
--   * A picture is the business the courier works for: an ordinary delivery's business (Config.Jobs.Businesses id, the
--     offer's `business`), a special job's job type (Config.JobTypes id, its `jobType.id` or `special`), the newspaper
--     round, the tutorial's letters. Shared businesses share one picture (the bakery's bread and its cakes, the lab's
--     vaccines and samples, Luigi's and the Pizza Rush ...). Never chosen by the customer, the cargo or a label.
--   * JobThumbs.Images[assetId]: the uploaded image ("rbxassetid://…"), "" until the owner uploads it
--     (design/job-thumbnails/NAHRAT-OBRAZKY.md; tools/job-thumbnails/fill-ids.py fills it and the manifest). Same ids
--     in the same order as art/job-thumbnails/manifest.json `assets` (tools/job-thumbnails/check.py checks it).
--   * JobThumbs.forJob(info) -> (image?, name?, emoji?): the image id (nil while empty or for a job without a picture:
--     a mission), the business's name (the label over the picture, the fallback banner) and its cargo emoji (the
--     fallback banner). `info` is a board row (server/Jobs.luau describe), a job payload, one of its `orders` or a
--     NEXT UP row: `tutorial`, `round`, `special` (a job type id) or `jobType.id`, `business`.
-- A picture is descriptive: it grants nothing, the server decides every job.

local JobThumbs = {}

export type Asset = { name: string, emoji: string }

-- The uploaded images by asset id (the manifest's `robloxImage`; "" = not uploaded: the fallback banner shows).
JobThumbs.Images = {
	pizzeria = "rbxassetid://91963074701428",
	bakery = "rbxassetid://130362504045896",
	post = "rbxassetid://71494169743693",
	pharmacy = "rbxassetid://130988254467816",
	supermarket = "rbxassetid://86937538732690",
	hardware = "rbxassetid://109369523878067",
	electronics = "rbxassetid://125480714446949",
	pawnshop = "rbxassetid://113370379567912",
	warehouse = "rbxassetid://116407199140336",
	lab = "rbxassetid://76972147837833",
	bank = "rbxassetid://122608291106176",
	burgers = "rbxassetid://80354187224207",
	noodles = "rbxassetid://81573576815530",
	cafe = "rbxassetid://102327903261633",
	news = "rbxassetid://76214613950013",
	flowers = "rbxassetid://135968676828733",
	icecream = "rbxassetid://79776599305090",
	school = "rbxassetid://124942050305126",
	army = "rbxassetid://99583451138108",
	movers = "rbxassetid://81705688621032",
	farm = "rbxassetid://74299509276956",
	ranch = "rbxassetid://74425535950175",
	clinic = "rbxassetid://118124034008185",
	gas = "rbxassetid://88366178538289",
	lodge = "rbxassetid://131113412451571",
} :: { [string]: string }

-- Each picture's business (the manifest's `name`: the game's own name for it) and the emoji of what it sends.
JobThumbs.Assets = {
	pizzeria = { name = "Luigi's Pizza", emoji = "🍕" },
	bakery = { name = "Daily Bread Bakery", emoji = "🍞" },
	post = { name = "Post Office", emoji = "✉️" },
	pharmacy = { name = "Corner Pharmacy", emoji = "💊" },
	supermarket = { name = "FreshMart", emoji = "🛒" },
	hardware = { name = "Bolt & Nail Hardware", emoji = "🔧" },
	electronics = { name = "Volt Electronics", emoji = "📻" },
	pawnshop = { name = "Second Life Pawn", emoji = "🧰" },
	warehouse = { name = "Harbor Warehouse", emoji = "📦" },
	lab = { name = "Research Lab", emoji = "🧪" },
	bank = { name = "First Zombie Bank", emoji = "💰" },
	burgers = { name = "Last Bite Burgers", emoji = "🍔" },
	noodles = { name = "Wok Dead", emoji = "🍜" },
	cafe = { name = "Grind House", emoji = "☕" },
	news = { name = "The Daily Undead", emoji = "📰" },
	flowers = { name = "Bloom", emoji = "💐" },
	icecream = { name = "Frosty's Ice Cream", emoji = "🍦" },
	school = { name = "Sunny Hill School", emoji = "🧒" },
	army = { name = "Military Base", emoji = "🧰" },
	movers = { name = "Big Move Movers", emoji = "🛋️" },
	farm = { name = "Old Farm", emoji = "🌽" },
	ranch = { name = "Silver Spur Ranch", emoji = "🐴" },
	clinic = { name = "City Clinic", emoji = "🚑" },
	gas = { name = "Gas Station", emoji = "⛽" },
	lodge = { name = "Ski Lodge", emoji = "🍲" },
} :: { [string]: Asset }

-- An ordinary delivery's business (Config.Jobs.Businesses id) → its picture.
JobThumbs.Ordinary = {
	pizzeria = "pizzeria",
	bakery = "bakery",
	post = "post",
	pharmacy = "pharmacy",
	supermarket = "supermarket",
	hardware = "hardware",
	electronics = "electronics",
	pawnshop = "pawnshop",
	warehouse = "warehouse",
	lab = "lab",
	samples = "lab",
	bank = "bank",
	cake = "bakery",
	burgers = "burgers",
	noodles = "noodles",
	cafe = "cafe",
	news = "news",
	flowers = "flowers",
	icecream = "icecream",
} :: { [string]: string }

-- A special job (Config.JobTypes id) → the workplace that commissions it.
JobThumbs.Special = {
	schoolrun = "school",
	armysupply = "army",
	icecream = "icecream",
	moving = "movers",
	farmrun = "farm",
	winter = "lodge",
	horses = "ranch",
	fuelrun = "gas",
	cashrun = "bank",
	ambulance = "clinic",
	pizzarush = "pizzeria",
	freightrun = "warehouse",
} :: { [string]: string }

JobThumbs.Round = "news" -- the newspaper round: The Daily Undead
JobThumbs.Tutorial = "post" -- the tutorial's letters: the Post Office

-- The picture (asset id) a job shows, nil for none: the tutorial, the round, a special, else an ordinary business.
function JobThumbs.assetFor(info: any): string?
	if type(info) ~= "table" then
		return nil
	end
	if info.tutorial == true then
		return JobThumbs.Tutorial
	elseif info.round == true then
		return JobThumbs.Round
	end
	local special = if type(info.special) == "string" then info.special
		elseif type(info.jobType) == "table" and type(info.jobType.id) == "string" then info.jobType.id
		else nil
	if special then
		return JobThumbs.Special[special]
	end
	return if type(info.business) == "string" then JobThumbs.Ordinary[info.business] else nil
end

-- The image id (nil while not uploaded or without a picture), the business's name and its emoji (nil without one).
function JobThumbs.forJob(info: any): (string?, string?, string?)
	local id = JobThumbs.assetFor(info)
	local asset = if id then JobThumbs.Assets[id] else nil
	if not id or not asset then
		return nil, nil, nil
	end
	local image = JobThumbs.Images[id]
	return if type(image) == "string" and image ~= "" then image else nil, asset.name, asset.emoji
end

return JobThumbs
