--!strict
-- 5.0: Last Stop Supplies' KIT tab (the shop window in client/Hud.luau draws it with KitShop.render, beside ITEMS):
-- your personal gear (Config.Kit; profile.kit in the state as `kit`, missing = none). It is yours for good, on foot
-- and (5.1) on a bike: what you carry (shared/Transport.luau), how fast you walk, how warm the food stays.
--
-- On top YOUR ROOM: "HANDS 2 / TOTE 5" with a pip for every light piece you can carry and the walk speed; then
-- every piece as a slim contract row (like 4.6's client/GearShop.luau): its icon and name, its level and price,
-- OWNED or not, what it does, and the one action that fits: BUY (at the counter, with the money), OWNED, a dim
-- "🔒 LEVEL n", or "BETTER VEST ALREADY". The server checks everything again (server/Shops.luau, the "Kit" remote: at
-- the counter, not owned yet, the level, the money).
-- 6.6, one carrying item: no backpacks. KitShop.render draws one shop's share (`only`): "bags" for ZDC Bags, the
-- depot's bag kiosk (the bags, Config.Kit pieces with `extra`), "kit" for Last Stop Supplies' KIT tab (the rest). Presentation only:
-- KitShop.tab (the shop's open tab: "items" | "kit", nil = KIT while some piece is still to buy) is its only state.
-- 5.8, the courier phone's look: YOUR ROOM is the phone's card (the red square and caps, the room in big type, a thin
-- rule under it); BUY is the phone's red primary.
-- 6.4: five bags; an owned bag's row says IN USE (the state's `bag`) or USE (the Kit remote's ("use", id), anywhere;
-- the server refuses while your bag holds pieces); the stat line leads with the sprint (every bag's point), then
-- the perk. The I window's BAGS tab lists the bags you own the same way (client/BagUi.luau BagUi.bags).
-- 6.7: every piece is drawn at its own shop (shared/Transport.luau kitShop: "bags", "supplies" = the KIT tab, "guns" =
-- Lead & Co.'s Baseball Bat: KitShop.rows, which client/Hud.luau's guns tab calls too). A starter piece (the plastic
-- bag) says "STARTER · yours" and is never sold; the Courier Vest's line says its tip.
-- 6.18 wave 2, the UI kit (design/ui-kit/README.md): the pieces are items for client/ShopView.luau (KitShop.items: the
-- picture, the name, what it does in one line, the price big, the one action; the description on a tap) and YOUR ROOM
-- is the counter's chip (KitShop.roomChip); client/ShopWindow.luau draws them at ZDC Bags, Last Stop Supplies' KIT tab
-- and Lead & Co.'s MELEE tab.
-- 6.23, bags for each game (Config.BagShop): ZDC Bags sells every bag FOR THIS GAME (its row: "FOR THIS GAME · $60",
-- the per-game price); one bought this game says "✓ BOUGHT THIS GAME" with USE / IN USE (the state's kit carries this
-- game's bags: the server's PlayerData.kitNow). No bag is a starter any more.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Transport = require(Shared.Transport)
local Armour = require(Shared.Armour)
local Melee = require(Shared.Melee) -- 6.7: the bat's numbers
local Ui = require(script.Parent.Ui)
local CardKit = require(script.Parent.CardKit)
local ShopView = require(script.Parent.ShopView)

local KitShop = {}

-- The supplies window's open tab ("items" | "kit"); nil until picked: KIT while some piece is still to buy.
KitShop.tab = nil :: string?

local player = Players.LocalPlayer

local function myLevel(state: any): number
	local xp = tonumber(player:GetAttribute("Xp"))
	if xp == nil and type(state.xp) == "number" then
		xp = state.xp
	end
	return Levels.levelFor(xp or 0)
end

-- The kit owned (state.kit; a state without it: none).
function KitShop.owned(state: any): Transport.Kit
	return if state and type(state.kit) == "table" then state.kit else {}
end

-- The tab to show: the one picked, else KIT while a piece is still to buy (the new player's first stop), else ITEMS.
-- (6.6: the bags are ZDC Bags', not this tab's; 6.7: only Last Stop Supplies' own pieces, Transport.kitShop)
function KitShop.currentTab(state: any): string
	local picked = KitShop.tab
	if picked then
		return picked
	end
	local kit = KitShop.owned(state)
	for _, def in Config.Kit do
		if not kit[def.id] and Transport.kitShop(def) == "supplies" then
			return "kit"
		end
	end
	return "items"
end

-- A bag's short name for the room line (6.0: "Plastic Bag" → "BAG").
-- 6.4: "Canvas Tote" → "TOTE", "Thermal Delivery Bag" → "THERMAL BAG", "Padded Messenger Bag" → "MESSENGER BAG",
-- "Big Delivery Duffel" → "DUFFEL".
local function shortName(def: Config.KitDef): string
	local name = def.name
	if def.extra then
		for _, cut in { "^Plastic ", "^Canvas ", "^Padded ", "^Big ", "Delivery " } do
			name = string.gsub(name, cut, "")
		end
	end
	return string.upper(name)
end

-- What you carry, in words: "HANDS 2" or "HANDS 2 / TOTE 5" (the hands + the bag: 6.6, one carrying item). Also for
-- the job board and the phone. 6.4: `bag` the active bag (the state's `bag`; nil = the best owned): only that one counts.
function KitShop.roomText(kit: Transport.Kit, bag: string?): string
	local Skills = require(Shared.Skills) -- (6.20: + Strong Back's pieces, Config.Skills)
	local ranks = Skills.decode(player:GetAttribute("Skills"))
	local active = Transport.activeBag(kit, bag)
	local hands = Config.Cargo.HandsMax + Skills.effect(ranks, "hands")
	local room = Transport.handsRoom(kit, bag) + Skills.effect(ranks, "hands") + (if active then Skills.effect(ranks, "bag") else 0)
	if active and room > hands then
		return `HANDS {hands} / {shortName(active)} {room}`
	end
	return `HANDS {room}`
end

-- What a piece does, in a few words (the row's stat line).
local function effect(def: Config.KitDef): string
	local parts: { string } = {}
	if def.armour then
		table.insert(parts, `🛡 −{math.floor(def.armour * 100 + 0.5)}% damage`) -- 6.0: the vests
	end
	if def.extra then
		-- 6.0: the plastic bag; 6.4: every bag: its room (you sprint with it), then its perk
		table.insert(parts, `🏃 sprint with +{def.extra} light pieces`)
		if def.bagWarm then
			table.insert(parts, `🔥 food in it cools ×{def.bagWarm}`)
		end
		if def.padded then
			table.insert(parts, "🛡 fragile safe in it")
		end
		if def.bagBreath then
			table.insert(parts, `💨 sprint breath ×{def.bagBreath}`)
		end
	end
	if def.speed then
		local change = math.floor((def.speed - 1) * 100 + 0.5)
		table.insert(parts, if change >= 0 then `👟 walk & sprint +{change}%` else `walk & sprint −{-change}%`)
	end
	if def.tips then
		table.insert(parts, `💵 +{math.floor(def.tips * 100 + 0.5)}% tips`) -- 6.7: the Courier Vest
	end
	if def.melee then
		local swing = Melee.def(def.melee)
		table.insert(parts, `🏏 V: {swing.damage} damage, {Melee.reachOf(def.melee)} studs`) -- 6.7: the bat
	end
	if #parts == 0 then
		return "just the look"
	end
	return table.concat(parts, "  ·  ")
end

-- 6.18 wave 2: YOUR ROOM as the counter's chip ("✋ HANDS 2 / TOTE 5 · 🛡 25%").
function KitShop.roomChip(state: any): CardKit.Chip
	local kit = KitShop.owned(state)
	local bag: string? = if type(state.bag) == "string" then state.bag else nil -- 6.4: the bag in use (the server's)
	local armour = Armour.percent(kit) -- 6.0: the best vest's share
	return { name = "RoomChip", text = `✋ {KitShop.roomText(kit, bag)}{if armour > 0 then ` · 🛡 {armour}%` else ""}`, static = true }
end

-- 6.7: one shop's kit as items (Transport.kitShop == `shopId`: "bags", "supplies", "guns"), in Config.Kit's order.
-- `here`: at the counter. 6.18 wave 2: client/ShopView.luau draws them (the hero, the rows, the details); each keeps
-- the one action that fits: USE / IN USE (a bag you own), OWNED, STARTER, a level's lock, BETTER VEST ALREADY, BUY.
function KitShop.items(state: any, here: boolean, shopId: string): { ShopView.Item }
	local kit = KitShop.owned(state)
	local level = myLevel(state)
	local money = tonumber(state.money) or 0
	local bag: string? = if type(state.bag) == "string" then state.bag else nil -- 6.4: the bag in use (the server's)
	local armour = Armour.percent(kit) -- 6.0: the best vest's share
	local active = Transport.activeBag(kit, bag)
	local out: { ShopView.Item } = {}
	for _, def in Config.Kit do
		if Transport.kitShop(def) ~= shopId then
			continue -- (6.6: the bags at ZDC Bags, the rest at Last Stop Supplies; 6.7: the bat at Lead & Co.)
		end
		local owned = kit[def.id] == true
		local game = Transport.perGame(def) -- 6.23: a bag is bought for this game only
		-- 6.0: a vest no better than the one you have adds nothing either (the best vest counts).
		local outclassed = not owned and def.armour ~= nil and def.armour * 100 <= armour
		local id = def.id
		local item: ShopView.Item = {
			id = def.id,
			name = def.name,
			picture = { icon = Icons.kit(def.id), emoji = def.icon },
			-- (6.23: a bag still to buy this game: "FOR THIS GAME · $60" first)
			fact = if game and not owned then `{Config.BagShop.ForGame} · {Ui.money(def.price)} · {effect(def)}` else effect(def),
			price = if owned or def.starter then nil else def.price,
			-- (a bag of yours: the light pieces it carries is its big number; one for sale: its price)
			value = if def.extra and (owned or def.starter) then `+{def.extra}` else nil,
			forSale = not def.starter,
			owned = owned,
			current = shopId == "bags" and owned and active ~= nil and active.id == def.id,
			lines = {
				def.description,
				if game then `Level {def.level} · {Ui.money(def.price)} for this game: bags are bought for each game (leaving the game loses them).`
					else `Level {def.level}{if def.starter then " · STARTER: yours" else ` · {Ui.money(def.price)}`}`,
			},
		}
		if owned and def.extra and active and active.id == def.id then
			item.act = { text = "IN USE", on = false } -- 6.4: the bag in your hand
			item.fact = `✓ IN USE{if game then " · BOUGHT THIS GAME" else ""} · {item.fact}`
		elseif owned and def.extra then
			item.act = { text = "USE THIS BAG", short = "USE", on = true, kind = "good", run = function()
				Net.get("Kit"):FireServer("use", id) -- 6.4 (the server refuses while your bag is loaded)
			end }
			item.fact = `{if game then "✓ BOUGHT THIS GAME" else "✓ OWNED"} · {item.fact}`
		elseif owned then
			item.act = { text = "OWNED", on = false }
			item.fact = `✓ OWNED · {item.fact}`
		elseif def.starter then
			item.act = { text = "STARTER", on = false } -- 6.7 (the server gives a missing one back for free)
		elseif level < def.level then
			item.lock = `🔒 LV {def.level}`
			item.act = { text = `🔒 LEVEL {def.level}`, on = false, why = `Opens at level {def.level}: deliveries give XP.` }
		elseif outclassed then
			item.act = { text = "BETTER VEST ALREADY", on = false, why = "Your vest is better already: the best one counts." }
		else
			item.act = {
				text = `BUY {Ui.money(def.price)}`,
				on = here and money >= def.price,
				why = if not here then "Walk into the shop to buy here." else `Not enough money: {def.name} costs {Ui.money(def.price)}.`,
				run = function()
					Net.get("Kit"):FireServer("buy", id)
				end,
			}
		end
		table.insert(out, item)
	end
	return out
end

return KitShop
