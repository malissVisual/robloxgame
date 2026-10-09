--!strict
-- 6.12: the cosmetics' rules (Config.Cosmetics), the pure part. server/StyleWear.luau decides with them (the Style
-- remote: buy, wear, unwear), client/StyleApp.luau shows the same answers before you press anything, and
-- server/PlayerData.luau cleans a saved wardrobe with them. Looks only: nothing here touches a number of the game.
--
--   Style.find(id) / Style.slot(id)          an item / a slot of Config.Cosmetics, or nil
--   Style.slots(tab) / Style.items(slot)     a tab's slots ("courier" | "vehicle"), a slot's items, in Config's order
--   Style.empty() / Style.sanitize(raw)      a new wardrobe { owned = { id → true }, worn = { slot → id } }; a saved
--                                            one cleaned: known items only, each worn one owned and in its own slot
--   Style.buyable(def)                       sold (not a reward), with a price
--   Style.canBuy(style, def, money, level)   true, or false and why: "owned" | "reward" | "level" | "money"
--   Style.canWear(style, def)                true, or false and "owned" (buy it first)
--   Style.state(style, def)                  "wearing" | "owned" | "reward" | "sale" (what its card says)
--   Style.worn(style, slot)                  the item worn in a slot, or nil
--   Style.forVehicle(slot, car)              does a vehicle slot show on this Config.Cars vehicle (wraps and decals on
--                                            the cars, vans and trucks, bike paint on the bikes and the E-Scooter; never
--                                            on a company vehicle)
--   Style.key(style, slots)                  the worn items of these slots as one string (a look changed?)
--   Style.say(kind, def, slot?)              the toast for an answer (English, the game's words)
--   Style.rgb(c, k?)                         a colour { r, g, b } scaled by k (a shade), clamped to 0 … 255
-- The clerks (the owner: "things are bought only from the NPCs in the shops, for the vibe"): the phone shows, tries
-- and wears; a look is bought only at a shop that sells its slot (Config.Cosmetics: a slot's `shops`, the Counters).
--   Style.shopsFor(def or slot)              the Map.Shops ids that sell it, in Config's order
--   Style.sells(shop, def or slot)           does that shop sell it
--   Style.shopAt(def or slot, x, z)          the one of its shops you stand at (server/Shops.luau's nearShop: the
--                                            horizontal distance to Map.Shops[id] under Map.shopRadius(id)), or nil
--   Style.counterFor(def or slot)            the counter that sells it (its first shop with a clerk) and that shop's id
--   Style.canBuyAt(style, def, money, level, shop?)  Style.canBuy, and the shop you stand at (`shop`, nil: none) must
--                                            sell it: false and "shop" (checked after "level", before "money")
--   Style.atLabel(def) / Style.soldBy(tab)   "AT WRENCH GARAGE" (the app's button away from the shop); "Gus at Wrench
--                                            Garage and Kip at Dead End Motors" (who sells a tab's looks)
-- Pure Luau (tests/style_test.luau).

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)

local Style = {}

export type Wardrobe = { owned: { [string]: boolean }, worn: { [string]: string } }

local byId: { [string]: Config.CosmeticDef } = {}
for _, def in Config.Cosmetics.Items do
	byId[def.id] = def
end
local slotById: { [string]: Config.CosmeticSlot } = {}
for _, slot in Config.Cosmetics.Slots do
	slotById[slot.id] = slot
end

function Style.find(id: any): Config.CosmeticDef?
	return if type(id) == "string" then byId[id] else nil
end

function Style.slot(id: any): Config.CosmeticSlot?
	return if type(id) == "string" then slotById[id] else nil
end

function Style.slots(tab: string): { Config.CosmeticSlot }
	local out: { Config.CosmeticSlot } = {}
	for _, slot in Config.Cosmetics.Slots do
		if slot.tab == tab then
			table.insert(out, slot)
		end
	end
	return out
end

function Style.items(slot: string): { Config.CosmeticDef }
	local out: { Config.CosmeticDef } = {}
	for _, def in Config.Cosmetics.Items do
		if def.slot == slot then
			table.insert(out, def)
		end
	end
	return out
end

function Style.empty(): Wardrobe
	return { owned = {}, worn = {} }
end

-- A saved (or sent) wardrobe, cleaned: unknown ids and slots are dropped, a worn item must be owned and of its slot.
function Style.sanitize(raw: any): Wardrobe
	local out = Style.empty()
	if type(raw) ~= "table" then
		return out
	end
	if type(raw.owned) == "table" then
		for id, on in raw.owned do
			if on == true and Style.find(id) then
				out.owned[id :: string] = true
			end
		end
	end
	if type(raw.worn) == "table" then
		for slot, id in raw.worn do
			local def = Style.find(id)
			if def and type(slot) == "string" and def.slot == slot and out.owned[def.id] then
				out.worn[slot] = def.id
			end
		end
	end
	return out
end

function Style.buyable(def: Config.CosmeticDef): boolean
	return def.reward == nil and def.price > 0
end

function Style.canBuy(style: Wardrobe, def: Config.CosmeticDef, money: number, level: number): (boolean, string?)
	if style.owned[def.id] then
		return false, "owned"
	elseif not Style.buyable(def) then
		return false, "reward"
	elseif level < (def.level or 1) then
		return false, "level"
	elseif money < def.price then
		return false, "money"
	end
	return true, nil
end

function Style.canWear(style: Wardrobe, def: Config.CosmeticDef): (boolean, string?)
	if not style.owned[def.id] then
		return false, "owned"
	end
	return true, nil
end

function Style.state(style: Wardrobe, def: Config.CosmeticDef): string
	if style.worn[def.slot] == def.id then
		return "wearing"
	elseif style.owned[def.id] then
		return "owned"
	elseif not Style.buyable(def) then
		return "reward"
	end
	return "sale"
end

function Style.worn(style: Wardrobe, slot: string): Config.CosmeticDef?
	local def = Style.find(style.worn[slot])
	return if def and def.slot == slot and style.owned[def.id] then def else nil
end

function Style.forVehicle(slot: string, car: Config.CarDef?): boolean
	if not car or car.company == true then
		return false
	end
	if slot == "bikepaint" then
		return car.bike == true
	end
	return (slot == "wrap" or slot == "decal") and car.bike ~= true
end

function Style.key(style: Wardrobe, slots: { string }): string
	local parts: { string } = {}
	for _, slot in slots do
		table.insert(parts, `{slot}={style.worn[slot] or ""}`)
	end
	return table.concat(parts, ";")
end

-- ── Where it is sold (the clerks) ─────────────────────────────────────────────

local function slotOf(item: Config.CosmeticDef | string): Config.CosmeticSlot?
	return Style.slot(if type(item) == "string" then item else item.slot)
end

function Style.shopsFor(item: Config.CosmeticDef | string): { string }
	local slot = slotOf(item)
	return if slot and slot.shops then slot.shops else {}
end

function Style.sells(shop: string?, item: Config.CosmeticDef | string): boolean
	return shop ~= nil and table.find(Style.shopsFor(item), shop) ~= nil
end

function Style.shopAt(item: Config.CosmeticDef | string, x: number, z: number): string?
	for _, id in Style.shopsFor(item) do
		local shop = Map.Shops[id]
		if shop then
			local dx, dz = x - shop.x, z - shop.z
			if math.sqrt(dx * dx + dz * dz) < Map.shopRadius(id) then
				return id
			end
		end
	end
	return nil
end

function Style.counterFor(item: Config.CosmeticDef | string): (Config.CosmeticCounter?, string?)
	for _, id in Style.shopsFor(item) do
		local counter = Config.Cosmetics.Counters[id]
		if counter then
			return counter, id
		end
	end
	return nil, nil
end

function Style.canBuyAt(style: Wardrobe, def: Config.CosmeticDef, money: number, level: number, shop: string?): (boolean, string?)
	local ok, why = Style.canBuy(style, def, money, level)
	if (ok or why == "money") and not Style.sells(shop, def) then
		return false, "shop"
	end
	return ok, why
end

function Style.atLabel(def: Config.CosmeticDef | string): string
	local counter = Style.counterFor(def)
	return if counter then `AT {string.upper(counter.place)}` else "AT A SHOP"
end

-- "Gus at Wrench Garage" for each counter that sells these slots (each once, in Config's order), joined with `join`.
local function clerks(slots: { string }, join: string): string
	local names: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, slot in slots do
		for _, id in Style.shopsFor(slot) do
			local counter = Config.Cosmetics.Counters[id]
			if counter and not seen[id] then
				seen[id] = true
				table.insert(names, `{counter.clerk} at {counter.place}`)
			end
		end
	end
	return if #names > 0 then table.concat(names, join) else "the shops"
end

function Style.soldBy(tab: string): string
	local slots: { string } = {}
	for _, slot in Style.slots(tab) do
		table.insert(slots, slot.id)
	end
	return clerks(slots, " and ")
end

local function money(n: number): string
	local text = tostring(math.floor(n))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. (if formatted:sub(1, 1) == "," then formatted:sub(2) else formatted)
end
Style.money = money

function Style.say(kind: string, def: Config.CosmeticDef?, slot: string?): string
	local name = if def then def.name else "It"
	if kind == "bought" then
		return `{name} is yours. You're wearing it.`
	elseif kind == "wear" then
		return `You're wearing {name}.`
	elseif kind == "off" then
		if def then
			return `{def.name} is off.`
		end
		local s = Style.slot(slot)
		return `{if s then s.name else "That"} off: your own look again.`
	elseif kind == "money" then
		return `Not enough money: {name} costs {if def then money(def.price) else "more"}.`
	elseif kind == "level" then
		return `{name} unlocks at level {if def then def.level or 1 else 1}.`
	elseif kind == "reward" then
		return `{name} is not for sale: it is a reward.`
	elseif kind == "owned" then
		return `{name} is yours already: WEAR it.`
	elseif kind == "notOwned" then
		return if def then `Buy {name} first, from {clerks({ def.slot }, " or ")}.` else `Buy {name} first.`
	elseif kind == "shop" then
		-- (the server's refusal away from its shops: who sells it, and where)
		return `Buy it from {if def then clerks({ def.slot }, " or ") else "the shops"}.`
	elseif kind == "where" then
		-- (the app's button away from its shops: its GPS goes to the first one)
		local counter = if def then Style.counterFor(def) else nil
		return if counter then `{counter.clerk} sells it at {counter.place}. It's on your GPS.` else "It's sold at the shops."
	elseif kind == "sold" then
		local counter = if def then Style.counterFor(def) else nil
		return if counter then `{counter.clerk} sells it at {counter.place}.` else ""
	end
	return name
end

function Style.rgb(c: { number }, k: number?): { number }
	local f = k or 1
	return { math.clamp(math.floor(c[1] * f + 0.5), 0, 255), math.clamp(math.floor(c[2] * f + 0.5), 0, 255), math.clamp(math.floor(c[3] * f + 0.5), 0, 255) }
end

return Style
