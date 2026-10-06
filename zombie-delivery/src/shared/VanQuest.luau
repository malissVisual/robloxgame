--!strict
-- 5.0, Earl's van (Config.VanQuest): the first vehicle is bought second-hand. Dead End Motors does not sell the Old
-- Van; when you reach its level without one Marge texts you about Earl, who sells his at Earl's Used Wheels far out on
-- the West Highway (Map.VanSeller). The quest's state is saved in the profile (profile.vanQuest: nil, "open" or
-- "done"). Pure Luau (tests/vanquest_test.luau); server/VanQuest.luau runs it, the clients read the words.
--
--   VanQuest.def()                          the van (Config.Cars, Config.VanQuest.Car)
--   VanQuest.isQuestCar(carId)              is this the car Earl sells (not at the dealer)?
--   VanQuest.status(quest, ownsVan, level)  "locked" (below the van's level), "open" (go to Earl) or "done"
--   VanQuest.shouldOpen(quest, ownsVan, level)  Marge's message is due now (reached the level, no van, not told yet)
--   VanQuest.canBuy(info)                   true, or false and why: "far" | "level" | "quest" | "owned" | "money"
--   VanQuest.sellerLine(why)                what Earl says to that ("Come back with $1,800, kid.")
--   VanQuest.greeting()                     Earl's pitch
--   VanQuest.priceText(), promptText()      "$1,800", "Buy the van ($1,800)"

local Config = require(script.Parent.Config)

local VanQuest = {}

export type BuyInfo = {
	distance: number, -- studs from Earl
	level: number,
	quest: string?, -- profile.vanQuest
	ownsVan: boolean,
	money: number,
}

local function money(amount: number): string
	local text = tostring(math.floor(amount))
	while true do
		local done = 0
		text, done = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		if done == 0 then
			break
		end
	end
	return "$" .. text
end

function VanQuest.def(): Config.CarDef
	for _, def in Config.Cars do
		if def.id == Config.VanQuest.Car then
			return def
		end
	end
	return Config.Cars[1]
end

function VanQuest.isQuestCar(carId: string?): boolean
	return carId ~= nil and carId == Config.VanQuest.Car
end

-- The van's level (when Marge texts) and its price (what Earl asks).
function VanQuest.level(): number
	return VanQuest.def().level or 1
end

function VanQuest.price(): number
	return VanQuest.def().price
end

function VanQuest.status(quest: string?, ownsVan: boolean, level: number): string
	if ownsVan or quest == "done" then
		return "done"
	end
	if quest == "open" or level >= VanQuest.level() then
		return "open"
	end
	return "locked"
end

function VanQuest.shouldOpen(quest: string?, ownsVan: boolean, level: number): boolean
	return quest == nil and not ownsVan and level >= VanQuest.level()
end

function VanQuest.canBuy(info: BuyInfo): (boolean, string?)
	if info.distance ~= info.distance or info.distance > Config.VanQuest.Range then
		return false, "far"
	end
	if info.ownsVan or info.quest == "done" then
		return false, "owned"
	end
	if info.level < VanQuest.level() then
		return false, "level"
	end
	if info.quest ~= "open" then
		return false, "quest"
	end
	if info.money < VanQuest.price() then
		return false, "money"
	end
	return true, nil
end

function VanQuest.sellerLine(why: string?): string
	local words = Config.VanQuest
	if why == "money" then
		return `Come back with {money(VanQuest.price())}, kid.`
	elseif why == "owned" then
		return words.Sold
	elseif why == "level" or why == "quest" then
		return words.TooYoung
	elseif why == nil then
		return words.Keys
	end
	return VanQuest.greeting()
end

function VanQuest.greeting(): string
	return `Old van, one owner, never hit anybody important. {money(VanQuest.price())}.`
end

-- The price in words: "$1,800".
function VanQuest.priceText(): string
	return money(VanQuest.price())
end

-- The prompt's words: "Buy the van ($1,800)".
function VanQuest.promptText(): string
	return `Buy the van ({money(VanQuest.price())})`
end

return VanQuest
