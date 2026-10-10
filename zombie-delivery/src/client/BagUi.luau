--!strict
-- 5.3, your bag (the inventory of a run): every piece you carry and where it is (shared/Bag.luau groups them): in your
-- hands, in your bag, in your bike's own bag (6.6: its rack / basket / box), a round's satchel, your vehicle. Each piece
-- shows its picture (shared/Icons.luau, an emoji without one), its name, its order and who it is for and where (the job
-- payload's `carried`, server/Jobs.luau), and over them the room you have: ✋ the hands, 🛍 the bag, 🚲 the bike's bag
-- (6.6: no backpack). The phone's ORDERS app (🛍 BAG) and the contract ticket's chip ("📦 2 newspapers · 1 pizza stack",
-- Bag.line) open the I window on it (BagUi.open: Hud sets BagUi.onOpen; 6.0.1: the bottom bar's carried strip too).
-- Presentation only: the server decides what you carry.
-- 6.4: BAGS, the bags you own: IN USE / USE (the Kit remote's ("use", id); the server refuses while your bag holds
-- pieces or lies on the ground).
-- 6.18 wave 2, BAG & ITEMS in the UI kit's look (the owner: "I need it unified so the phone looks like that [6.17's
-- JOBS], and the other popups too"; design/ui-kit/README.md). BagUi.draw draws it for the I window (client/Hud.luau)
-- and the phone's BAG & ITEMS (client/PhoneApps.luau) with client/ShopView.luau; the tabs are chips (Tab_<id>):
--   * the HERO is your bag: during a run its fill big ("3/7"; a bar; "✋ 1/2 · 🛍 2/5 · 🚲 0/4"), off duty what it
--     carries ("7": your hands and the bag in use); on BAGS the bag in use, on CARS the vehicle you drive, on GUNS the
--     gun in your hand;
--   * 📦 CARRYING (during a run, "BagRows"): a row a piece (its picture, name, order, who for, where: ✋ 🛍 🚲);
--   * ITEMS ("ItemRows"): a row a consumable, its COUNT big (×2), its key in the bottom bar and a round USE (the bar's
--     path: Hud's useItem, the UseItem remote with your aim); 6.7: a car-only item without a car only while you have one;
--   * BAGS ("BagsRows"): the bags you own (USE), how many more ZDC Bags sells;
--   * CARS and GUNS (the I window): yours (📦 slots big; EQUIP), the employers' still to earn (locked).
-- A tap on a row opens its details (what it does, the stats).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Icons = require(Shared.Icons)
local Bag = require(Shared.Bag)
local Transport = require(Shared.Transport)
local Net = require(Shared.Net) -- 6.4: USE a bag
local CardKit = require(script.Parent.CardKit)
local ShopView = require(script.Parent.ShopView)

local C = CardKit.Color
local BagUi = {}

-- Set by client/Hud.luau: opens the I window on its BAG tab.
BagUi.onOpen = nil :: (() -> ())?

function BagUi.open()
	local cb = BagUi.onOpen
	if cb then
		cb()
	end
end

-- The chip's words for a job payload ("📦 2 newspapers · 1 pizza stack"), nil when you carry nothing.
function BagUi.line(job: any): string?
	if type(job) ~= "table" or type(job.carried) ~= "table" then
		return nil
	end
	return Bag.line(job.carried)
end

local EMOJI: { [string]: string } = {
	pizza = "🍕",
	burger = "🍔",
	noodles = "🍜",
	pastry = "🥐",
	bread = "🥖",
	newspaper = "📰",
	mail = "✉",
	parcel = "📦",
	medicine = "💊",
	bouquet = "💐",
	cake = "🎂",
	groceries = "🛒",
	icecream = "🍦",
	gadget = "📻",
	documents = "💼",
}

-- 6.0.1: a piece's emoji when its icon has no id yet (the bottom bar's carried strip, client/Hotbar.luau, too).
function BagUi.emoji(look: string?): string
	return if look then EMOJI[look] or "📦" else "📦"
end

local function capital(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

-- What BAG & ITEMS needs from its window (the I window's or the phone's popup).
export type Ctx = {
	tab: string, -- "bag" | "items" | "bags" | "cars" | "guns"
	tabs: { { string } },
	pick: (id: string) -> (),
	state: any,
	job: any,
	side: boolean,
	room: number,
	bar: (() -> (any, number))?,
	redraw: () -> (),
	toast: (text: string) -> (),
	use: (id: string) -> (), -- an item's USE (the bottom bar's path)
	slotOf: (id: string) -> number?, -- its key in the bottom bar
	keys: boolean, -- name the keys (not on a touch screen)
	findEmployer: ((id: string?) -> any)?,
}

type Item = ShopView.Item

-- The bag in use and what you carry on foot (Transport: the hands + ONE bag).
-- 6.20: + Strong Back's pieces (Config.Skills: the state's skills), a bag's only with a bag. Returns the bag, the room
-- and the hands' part of it.
local function myBag(state: any): (Config.KitDef?, number, number)
	local kit = if type(state) == "table" and type(state.kit) == "table" then state.kit else {}
	local inUse = if type(state) == "table" and type(state.bag) == "string" then state.bag else nil
	local Skills = require(Shared.Skills)
	local ranks = if type(state) == "table" and type(state.skills) == "table" then state.skills else {}
	local active = Transport.activeBag(kit, inUse)
	local hands = Config.Cargo.HandsMax + Skills.effect(ranks, "hands")
	return active, Transport.handsRoom(kit, inUse) + Skills.effect(ranks, "hands") + (if active then Skills.effect(ranks, "bag") else 0), hands
end

-- The hero: your bag (see the header).
local function bagHero(state: any, job: any): Item
	local active, room, hands = myBag(state)
	local picture: CardKit.Picture = if active then { icon = Icons.kit(active.id), emoji = active.icon } else { emoji = "✋" }
	local name = if active then active.name else "Your hands"
	if type(job) ~= "table" then
		return { id = "yourbag", name = name, picture = picture, value = tostring(room), valueColor = C.money, fact = `LIGHT PIECES ON FOOT · ✋ {hands} + 🛍 {room - hands}`, current = true,
			lines = { `On foot you carry light things: {hands} in your hands, the rest in your bag (the one IN USE). On a bike, its own bag takes pickups too.` } }
	end
	local carried = if type(job.carried) == "table" then job.carried else {}
	local mode = if type(job.mode) == "string" then job.mode else "car"
	if mode ~= "foot" and mode ~= "bike" then
		return { id = "yourbag", name = name, picture = { emoji = "🚚" }, value = tostring(#carried), valueColor = C.money, fact = "🚚 IN YOUR VEHICLE AND YOUR HANDS", current = true }
	end
	local packRoom = tonumber(job.packRoom) or 0
	local rack = tonumber(job.rack) or 0
	local bagRoom = tonumber(job.bagRoom) or 0
	local count: { [string]: number } = { hands = 0, bag = 0, rack = 0, pack = 0 }
	for _, piece in carried do
		if type(piece) == "table" and type(piece.where) == "string" and count[piece.where] then
			count[piece.where] += 1
		end
	end
	local parts: { string } = {}
	local have, total = 0, 0
	for _, place in Bag.places(mode, packRoom, rack, math.max(bagRoom, count.bag), hands) do
		if place.where == "hands" or place.room > 0 or count[place.where] > 0 then
			local roomHere = math.max(place.room, count[place.where])
			table.insert(parts, `{Bag.Marks[place.where]} {count[place.where]}/{roomHere}`)
			have += count[place.where]
			total += roomHere
		end
	end
	return {
		id = "yourbag",
		name = name,
		picture = picture,
		value = `{have}/{total}`,
		valueColor = if have >= total and total > 0 then C.gold else C.money,
		fact = table.concat(parts, " · "),
		current = true,
		lines = { "Pieces ride where they fit: your hands, your bag, your bike's bag, the car." },
	}
end

-- 📦 CARRYING: a row a piece.
local function pieces(job: any): { Item }
	local carried = if type(job) == "table" and type(job.carried) == "table" then job.carried else {}
	local mode = if type(job) == "table" and type(job.mode) == "string" then job.mode else "car"
	local out: { Item } = {}
	for _, group in Bag.groups(carried, mode) do
		for index, piece in group.pieces do
			local look = if type(piece.look) == "string" then piece.look else ""
			local who = if type(piece.dest) == "string" then `for {piece.dest}` else "for the customer"
			local place = if type(piece.place) == "string" and piece.place ~= piece.dest then ` · {piece.place}` else ""
			local fits = if Bag.fitsBag(look) then "" else " · hands only" -- (6.3; 6.6: a light piece fits every bag)
			table.insert(out, {
				id = `{group.where}{index}`,
				name = capital(tostring(piece.name or "piece")),
				picture = { icon = Icons.cargo(look), emoji = EMOJI[look] or "📦" },
				fact = `{group.icon} #{tonumber(piece.order) or 1} · {who}{fits}`,
				owned = true,
				lines = { `Order {tonumber(piece.order) or 1} · {who}{place}{fits}.`, `It rides: {group.title}.` },
			})
		end
	end
	return out
end

-- ITEMS: your consumables.
local function consumables(ctx: Ctx): { Item }
	local state = ctx.state
	local have = if type(state) == "table" and type(state.items) == "table" then state.items else {}
	local cars = if type(state) == "table" and type(state.cars) == "table" then state.cars else nil
	local out: { Item } = {}
	for _, def in Config.Items do
		local count = tonumber(have[def.id]) or 0
		if count <= 0 and not Economy.itemShown(def, cars) then
			continue -- 6.7: a car item without a car (one you have still shows)
		end
		local slot = if count > 0 then ctx.slotOf(def.id) else nil
		local id = def.id
		table.insert(out, {
			id = def.id,
			name = def.name,
			picture = { icon = Icons.item(def.id), emoji = def.icon },
			fact = if count <= 0 then "NONE LEFT" elseif slot and ctx.keys then `Key {slot}.` elseif slot then "ON THE BAR" else "NOT ON THE BAR: USE IT HERE",
			value = `×{count}`,
			valueColor = if count > 0 then C.money else C.dim,
			owned = count > 0,
			act = { text = "USE", short = "USE", on = count > 0, kind = "good", why = `No {def.name} left. Last Stop Supplies sells them (SHOP sets the GPS).`, run = function()
				ctx.use(id)
			end },
			actionName = "Use",
			lines = { def.description, `You have {count} (at most {def.max}).` },
		})
	end
	return out
end

-- BAGS: the bags you own.
local function bags(ctx: Ctx): ({ Item }, number)
	local state = ctx.state
	local kit = if type(state) == "table" and type(state.kit) == "table" then state.kit else {}
	local active = myBag(state)
	local out: { Item } = {}
	local missing = 0
	for _, def in Config.Kit do
		if not def.extra then
			continue
		end
		if kit[def.id] ~= true then
			missing += 1
			continue
		end
		local mine = active ~= nil and active.id == def.id
		local id = def.id
		local perk = if def.bagWarm then ` · 🔥 ×{def.bagWarm}` elseif def.padded then " · 🛡 FRAGILE" elseif def.bagBreath then ` · 💨 ×{def.bagBreath}` else ""
		table.insert(out, {
			id = def.id,
			name = def.name,
			picture = { icon = Icons.kit(def.id), emoji = def.icon },
			fact = (if mine then "✓ IN USE · " else "") .. `🏃 LIGHT PIECES{perk}`,
			value = `+{def.extra}`,
			owned = true,
			current = mine,
			act = if mine then { text = "IN USE", on = false } else { text = "USE THIS BAG", short = "USE", on = true, kind = "good", run = function()
				Net.get("Kit"):FireServer("use", id)
			end },
			lines = { def.description },
		})
	end
	return out, missing
end

-- CARS (the I window): your vehicles, the employers' still to earn.
local function cars(ctx: Ctx): { Item }
	local state = ctx.state
	local ShopWindow = require(script.Parent.ShopWindow) :: any -- (the stats words; the I window only)
	local out: { Item } = {}
	for _, def in Config.Cars do
		if not state.cars[def.id] and def.employer then
			local find = ctx.findEmployer
			local employer = if find then find(def.employer) else nil
			if employer then
				local done = state.rep[employer.id] or 0
				table.insert(out, { id = def.id, name = def.name, picture = ShopView.vehicle(def), fact = `WORK FOR {string.upper(employer.name)} · {math.min(done, employer.needed)}/{employer.needed}`, lock = "🔒 WORK", lines = { def.description } })
			end
			continue
		end
		if state.cars[def.id] then
			local levels = Economy.carLevels(state.carUpgrades, def.id)
			local gunId = if def.mount and state.carGuns then state.carGuns[def.id] else nil
			local gun = if gunId then Economy.findCarGun(gunId) else nil
			local health = if type(state.carHealth) == "table" and type(state.carHealth[def.id]) == "number" then state.carHealth[def.id] else 1
			table.insert(out, {
				id = def.id,
				name = def.name,
				picture = ShopView.vehicle(def),
				fact = `🔧 {math.floor(health * 100 + 0.5)}%{if gun then ` · 🔫 {string.upper(gun.name)}` else ""}{if state.car == def.id then " · DRIVING" else ""}`,
				value = if def.bike then nil else `📦 {Economy.capacity(def.id, levels)}`,
				owned = true,
				current = state.car == def.id,
				act = if state.car == def.id then { text = "DRIVING", on = false } else nil,
				lines = { ShopWindow.carStats(def, levels), def.description, "Switch cars at one of your garages (🅿 GARAGE), the starting van at the depot lot. Repairs: Wrench Garage and Rust Bridge Repairs." },
			})
		end
	end
	return out
end

-- GUNS (the I window): yours (EQUIP, IN HAND), the earned ones still to earn.
local function guns(ctx: Ctx): { Item }
	local state = ctx.state
	local ShopWindow = require(script.Parent.ShopWindow) :: any
	local out: { Item } = {}
	for _, def in Config.Weapons do
		if state.weapons[def.id] then
			local id = def.id
			table.insert(out, {
				id = def.id,
				name = def.name,
				picture = { icon = Icons.weapon(def.id), emoji = "🔫" },
				fact = ShopWindow.gunFact(def) .. (if def.oneHanded then " · 1-HAND" else ""),
				owned = true,
				special = def.exclusive ~= nil, -- 3.1: a reward nobody can buy
				ribbon = if def.exclusive then "★ EXCLUSIVE" else nil,
				current = state.weapon == def.id,
				act = if state.weapon == def.id then { text = "IN HAND", on = false } else { text = "EQUIP", short = "EQUIP", on = true, kind = "good", run = function()
					Net.get("Equip"):FireServer("weapon", id)
				end },
				lines = { ShopWindow.gunStats(def) .. (if def.pierce then ` · Pierces {def.pierce}` else "") .. (if def.oneHanded then " · One-handed" else ""), def.description },
			})
		elseif def.earned then
			-- Earned by working, not bought.
			local find = ctx.findEmployer
			local employer = if find then find(def.earned) else nil
			if employer then
				local done = state.rep[employer.id] or 0
				local at = employer.weaponAt or employer.needed
				table.insert(out, { id = def.id, name = def.name, picture = { icon = Icons.weapon(def.id), emoji = "🔫" }, fact = `EARNED AT {string.upper(employer.name)} · {math.min(done, at)}/{at}`, lock = "🔒 WORK", lines = { def.description } })
			end
		end
	end
	return out
end

-- Draws BAG & ITEMS' open tab into `list` (the caller cleared it) from layout order `order` on. Returns the gamepad's
-- first stop.
function BagUi.draw(list: Instance, ctx: Ctx, order: number): any
	local state = ctx.state
	local items: { Item }
	local name = "ItemRows"
	local foot: string? = nil
	local empty: string? = nil
	local hero: Item? = bagHero(state, ctx.job)
	if ctx.tab == "bag" then
		items = pieces(ctx.job)
		name = "BagRows"
		empty = "Nothing in your bag. Pick up an order at a shop: the cook or the clerk hands it over at the door."
		foot = if #items == 0 then empty else nil
	elseif ctx.tab == "bags" then
		local missing
		items, missing = bags(ctx)
		name = "BagsRows"
		if #items > 0 then
			hero = nil -- (the bag in use is the hero: `current`; no bag at all: your hands)
		end
		foot = if missing > 0 then `{missing} more {if missing == 1 then "bag" else "bags"} at {Config.BagShop.Name}, by the spawn.` else nil
	elseif ctx.tab == "cars" then
		items = cars(ctx)
		hero = nil
		name = "CarRows"
		foot = "Buy at Dead End Motors, or earn one by working (M = map)."
	elseif ctx.tab == "guns" then
		items = guns(ctx)
		hero = nil
		name = "GunRows"
	else
		items = consumables(ctx)
		foot = "Last Stop Supplies (the gear stall) sells more."
	end
	if hero then
		table.insert(items, 1, hero)
	end
	local first = ShopView.draw(list, {
		key = `bag:{ctx.tab}`,
		items = items,
		money = tonumber(state and state.money) or 0,
		side = ctx.side,
		room = ctx.room,
		order = order,
		tabs = { tabs = ctx.tabs, selected = ctx.tab, onPick = ctx.pick },
		bar = ctx.bar,
		foot = foot,
		empty = empty,
		redraw = ctx.redraw,
		toast = ctx.toast,
	})
	-- (the rows' column by what it holds: BagRows, ItemRows, BagsRows …)
	local cards = list:FindFirstChild("ShopCards")
	if cards then
		cards.Name = name
	end
	return first
end

return BagUi
