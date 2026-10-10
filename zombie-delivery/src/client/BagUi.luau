--!strict
-- 5.3, your bag (the inventory of a run): every piece you carry and where it is (shared/Bag.luau groups them): in your
-- hands, in your bag, in your bike's own bag (6.6: its rack / basket / box), a round's satchel, your vehicle. Each piece
-- shows its picture (shared/Icons.luau, an emoji without one), its name, its order and who it is for and where (the job
-- payload's `carried`, server/Jobs.luau). The phone's ORDERS app (🛍 BAG), the contract ticket's chip ("📦 2 newspapers
-- · 1 pizza stack", Bag.line) and (6.21) the bottom bar's bag pill open the I window on it (BagUi.open: Hud sets
-- BagUi.onOpen). Presentation only: the server decides what you carry.
-- 6.4: BAGS, the bags you own: IN USE / USE (the Kit remote's ("use", id); the server refuses while your bag holds
-- pieces or lies on the ground).
-- 6.18 wave 2: BAG & ITEMS in the UI kit's look (design/ui-kit/README.md), drawn with client/ShopView.luau for the I
-- window (client/Hud.luau) and the phone's BAG & ITEMS (client/PhoneApps.luau); the tabs are chips (Tab_<id>).
-- 6.21, a clean hotbar's window (the owner picked redesign B "Clean hotbar + kit"; the colours in Config.Inventory, the
-- pure maths in shared/Inventory.luau):
--   * the header chips: ✋ IN HAND · PISTOL (what is in your hand: BagUi.hand), 📦 5/6 (what you carry, blue) and cash;
--   * the HERO is YOUR BAG (CARRYING, ITEMS, BAGS): a blue frame and ribbon, "CANVAS TOTE · OVER THE SHOULDER", what
--     you carry big ("5 / 6"; 6.20 Strong Back's pieces counted), the cargo as a stack of tiles (6.19's grouping:
--     🍕 ×2, a dim tile a free place), a blue fill bar, one facts line (where the pieces ride on a run, else the bag's
--     perks) and ONE red button, HOLD BAG · [2]: the bottom bar's key 2, the same path (Holster.choose through
--     BagUi.choose: the Hand remote); IN YOUR HAND while you hold it, its why while you can't (no bag, on the ground);
--   * 📦 CARRYING (during a run, "BagRows"): a row a piece (its picture, name, order, who for, where: ✋ 🛍 🚲);
--   * ITEMS ("ItemRows", ON YOU): your gun (DRAW: the hotbar's key 3, the same path; IN HAND), the bat, your consumables
--     (their COUNT big, ×2, their key in the bottom bar and a round USE: the bar's path, Hud's useItem, the UseItem
--     remote with your aim; 6.7: a car-only item without a car only while you have one), your vests (WORN) and MY BAGS
--     (a tap: the BAGS tab);
--   * BAGS ("BagsRows"): the bags you own (USE), how many more ZDC Bags sells;
--   * CARS and GUNS (the I window): yours (📦 slots big; EQUIP), the employers' still to earn (locked).
-- Every row has its kind's colour on its left edge (Inventory.category: weapons red, medical green, explosives orange,
-- cargo and bags blue, gear grey). A tap on a row opens its details (what it does, the stats).
-- 6.22, every thing has a look (the owner: "every thing must look like something, not only an icon"): the hero's bag (or
-- your fists), the cargo stack's tiles, every row's thumb (the pieces, the gun, the bat, the items, the vests, the bags,
-- the guns) are small 3D models (client/ItemModel.luau, shared/ItemLooks.luau keys through CardKit's picture `model`);
-- the icon or the emoji only when a model can't be built. The cars keep their pictures.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Icons = require(Shared.Icons)
local Bag = require(Shared.Bag)
local Transport = require(Shared.Transport)
local Holding = require(Shared.Holding) -- 6.21: HOLD BAG's rules
local KitFit = require(Shared.KitFit) -- 6.21: the vest you wear
local Inventory = require(Shared.Inventory) -- 6.21
local Net = require(Shared.Net) -- 6.4: USE a bag
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)
local ShopView = require(script.Parent.ShopView)
local ItemModel = require(script.Parent.ItemModel) -- 6.22: the cargo stack's models

local C = CardKit.Color
local K = Theme.Contract
local STACK = Config.Inventory.Stack
local BagUi = {}

-- Set by client/Hud.luau: opens the I window on its BAG tab.
BagUi.onOpen = nil :: (() -> ())?
-- 6.21, set by client/Hud.luau: what is in your hand ("fists" | "bag" | "gun": Holster.hand) and asks for a hand
-- (Holster.choose: the Hand remote, the bottom bar's keys 1 / 2 / 3).
BagUi.hand = nil :: (() -> string)?
BagUi.choose = nil :: ((hand: string) -> ())?

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

-- 6.0.1: a piece's emoji when its icon has no id yet (the bottom bar too).
function BagUi.emoji(look: string?): string
	return if look then EMOJI[look] or "📦" else "📦"
end

local function capital(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

-- 6.21: a kind's colour (Config.Inventory.Colors).
local function tint(kind: string, id: string?): Color3
	local rgb = Inventory.rgb(Inventory.category(kind, id))
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end
BagUi.tint = tint
local BLUE = tint("cargo")
local INK_ON_BLUE = Color3.fromRGB(11, 22, 34)

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

-- What you carry and your room as the hero counts them (a run: the payload's places; off duty: nothing of your room),
-- the places' words ("✋ 1/2 · 🛍 2/5") and the pieces that ride on you (not in the vehicle).
local function carrying(state: any, job: any): (number, number, string?, { any })
	local _, room, hands = myBag(state)
	if type(job) ~= "table" then
		return 0, room, nil, {}
	end
	local carried = if type(job.carried) == "table" then job.carried else {}
	local onYou: { any } = {}
	for _, piece in carried do
		if type(piece) == "table" and piece.where ~= "vehicle" then
			table.insert(onYou, piece)
		end
	end
	local mode = if type(job.mode) == "string" then job.mode else "car"
	if mode ~= "foot" and mode ~= "bike" then
		return #onYou, hands, "🚚 IN YOUR VEHICLE AND YOUR HANDS", onYou
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
	return have, total, table.concat(parts, " · "), onYou
end

-- What is in your hand now ("fists" | "bag" | "gun"), nil when nobody told (the checks' mock).
local function heldNow(): string?
	local hand = BagUi.hand
	if hand then
		local ok, value = pcall(hand)
		if ok and type(value) == "string" then
			return value
		end
	end
	return nil
end

local function choose(hand: string, ctx: Ctx)
	local pick = BagUi.choose
	if pick then
		pick(hand)
	end
	task.delay(0.35, ctx.redraw) -- (the server answers with the Hand attribute: the button and the chip follow)
end

local function bagDown(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and typeof(player:GetAttribute("BagDown")) == "Vector3"
end

-- HOLD BAG · [2] (the hotbar's key 2: Holster.choose("bag"), the Hand remote), or why it can't now.
local function holdAct(ctx: Ctx): ShopView.Act
	local state = ctx.state
	local owns = type(state) == "table" and type(state.bag) == "string"
	if heldNow() == "bag" then
		return { name = "HoldBag", text = "IN YOUR HAND", on = false }
	end
	local can, why = Holding.can("bag", owns, true, bagDown())
	if not can then
		return { name = "HoldBag", text = if why == "bagdown" then "BAG ON THE GROUND" else "NO BAG YET", on = false, why = Holding.whyText(why or "nobag") }
	end
	local key = Holding.keyOf("bag") or 2
	return {
		name = "HoldBag",
		text = if ctx.keys then `HOLD BAG · [{key}]` else "HOLD BAG",
		on = true,
		kind = "primary",
		run = function()
			choose("bag", ctx)
		end,
	}
end

local CARRY: { [string]: string } = { shoulder = "OVER THE SHOULDER", hip = "ON YOUR HIP", hand = "IN YOUR HAND" }

-- A bag's perks in one line ("🏃 SPRINT WITH CARGO · STAYS ON WHEN YOU DRAW").
local function perks(def: Config.KitDef): string
	local out = { "🏃 SPRINT WITH CARGO" }
	if def.stays then
		table.insert(out, "STAYS ON WHEN YOU DRAW")
	end
	if def.bagWarm then
		table.insert(out, `🔥 COOLS ×{def.bagWarm}`)
	end
	if def.padded then
		table.insert(out, "🛡 FRAGILE SAFE")
	end
	if def.bagBreath then
		table.insert(out, `💨 BREATH ×{def.bagBreath}`)
	end
	return table.concat(out, " · ")
end

-- The hero: YOUR BAG (see the header).
local function bagHero(ctx: Ctx): Item
	local state = ctx.state
	local active, _, hands = myBag(state)
	local have, total, places = carrying(state, ctx.job)
	local share = Inventory.fill(have, total)
	local name = if active then `{active.name} · {CARRY[active.carry or "hand"] or "IN YOUR HAND"}` else "Your hands"
	local fact = places or (if active then perks(active) else `✋ {hands} LIGHT PIECES IN YOUR HANDS`)
	return {
		id = "yourbag",
		name = name,
		picture = if active then { model = `kit:{active.id}`, icon = Icons.kit(active.id), emoji = active.icon } else { model = "fists", emoji = "✋" },
		value = `{have} / {total}`,
		valueColor = if have >= total and total > 0 then C.gold else C.text,
		fact = fact,
		current = true,
		accent = BLUE,
		strong = true,
		ribbon = "YOUR BAG",
		ribbonFace = BLUE,
		ribbonInk = INK_ON_BLUE,
		bar = { share = share, color = BLUE },
		act = holdAct(ctx),
		lines = {
			"Pieces ride where they fit: your hands, your bag (the one in your hand: key 2), your bike's bag, the car.",
			`On foot you carry light things: {hands} in your hands, the rest in your bag.`,
		},
	}
end

-- 6.21: the hero's cargo stack: a tile a kind of piece (6.19's grouping, ×n), then the free places dim.
local function drawStack(card: any, ctx: Ctx)
	local have, total, _, onYou = carrying(ctx.state, ctx.job)
	local groups, hidden = Inventory.stack(onYou, STACK.Max)
	local shade = card:FindFirstChild("Shade")
	local shadeH = if shade then shade.Size.Y.Offset else 140
	local strip = Ui.make("Frame", {
		Name = "CargoStack",
		Size = UDim2.new(1, -32, 0, STACK.Tile),
		Position = UDim2.new(0, 16, 1, -(shadeH + STACK.Tile + 8)),
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, card)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, STACK.Gap), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, strip)
	local n = 0
	for _, group in groups do
		n += 1
		local tile = Ui.make("Frame", { Name = `Stack_{group.look}`, Size = UDim2.fromOffset(STACK.Tile, STACK.Tile), BackgroundColor3 = Color3.fromRGB(27, 39, 53), BorderSizePixel = 0, LayoutOrder = n, ZIndex = 4 }, strip)
		Ui.corner(tile, 10)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = BLUE, Thickness = 1, Transparency = 0.55 }, tile)
		local inset = Config.ItemModel.Tile
		-- 6.22: the piece as its model (the icon only if it can't be built)
		if not ItemModel.view(tile, `cargo:{group.look}`, { size = UDim2.new(1, -2 * inset, 1, -2 * inset), z = 5 }) then
			Ui.icon(tile, Icons.cargo(group.look), BagUi.emoji(group.look), UDim2.fromOffset(26, 26), {
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				ImageColor3 = K.text,
				ZIndex = 5,
			})
		end
		if group.count > 1 then
			Ui.label(tile, `×{group.count}`, UDim2.fromOffset(STACK.Tile - 4, 14), {
				Name = "Count",
				Position = UDim2.new(1, -2, 1, -1),
				AnchorPoint = Vector2.new(1, 1),
				Font = Theme.HeadingFont,
				TextSize = 11,
				TextColor3 = K.text,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 6,
			})
		end
	end
	if hidden > 0 then
		n += 1
		Ui.label(strip, `+{hidden}`, UDim2.fromOffset(STACK.Tile, STACK.Tile), { Name = "More", Font = Theme.HeadingFont, TextSize = 14, TextColor3 = K.text, LayoutOrder = n, ZIndex = 4 })
	end
	-- the free places: dim outlines while the stack has room for them
	for _ = 1, math.clamp(total - have, 0, STACK.Max - n) do
		n += 1
		local free = Ui.make("Frame", { Name = "Free", Size = UDim2.fromOffset(STACK.Tile, STACK.Tile), BackgroundTransparency = 1, LayoutOrder = n, ZIndex = 4 }, strip)
		Ui.corner(free, 10)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.55 }, free)
	end
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
				picture = { model = `cargo:{if look ~= "" then look else "parcel"}`, icon = Icons.cargo(look), emoji = EMOJI[look] or "📦" },
				fact = `{group.icon} #{tonumber(piece.order) or 1} · {who}{fits}`,
				owned = true,
				accent = BLUE,
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
			picture = { model = `item:{def.id}`, icon = Icons.item(def.id), emoji = def.icon },
			fact = if count <= 0 then "NONE LEFT" elseif slot and ctx.keys then `Key {slot}.` elseif slot then "ON THE BAR" else "NOT ON THE BAR: USE IT HERE",
			value = `×{count}`,
			valueColor = if count > 0 then C.money else C.dim,
			owned = count > 0,
			accent = tint("item", def.id),
			act = { text = "USE", short = "USE", on = count > 0, kind = "good", why = `No {def.name} left. Last Stop Supplies sells them (SHOP sets the GPS).`, run = function()
				ctx.use(id)
			end },
			actionName = "Use",
			lines = { def.description, `You have {count} (at most {def.max}).` },
		})
	end
	return out
end

-- 6.21, ITEMS' ON YOU: your gun, the bat, the consumables, your vests and MY BAGS (see the header).
local function onYou(ctx: Ctx): { Item }
	local state = ctx.state
	local kit = if type(state) == "table" and type(state.kit) == "table" then state.kit else {}
	local out: { Item } = {}
	local held = heldNow()
	local weapon = if type(state) == "table" and type(state.weapon) == "string" then state.weapon else nil
	local gun = if weapon then Economy.findWeapon(weapon) else nil
	if gun then
		local key = Holding.keyOf("gun") or 3
		local inHand = held == "gun"
		table.insert(out, {
			id = "gun",
			name = gun.name,
			picture = { model = `gun:{gun.id}`, icon = Icons.weapon(gun.id), emoji = "🔫" },
			fact = `🎯 {math.floor(gun.damage * math.max(1, gun.pellets) + 0.5)} DMG · {gun.range} STUDS{if gun.oneHanded then " · 1-HAND" else ""}`,
			value = if inHand then "IN HAND" elseif ctx.keys then `KEY {key}` else nil,
			valueColor = if inHand then K.red else C.secondary,
			owned = true,
			accent = tint("weapon"),
			act = if inHand then nil else { text = "DRAW", short = "DRAW", on = true, kind = "primary", run = function()
				choose("gun", ctx)
			end },
			actionName = "Draw",
			lines = { gun.description, "T picks the gun (the GUNS tab equips another)." },
		})
	end
	local melee = Config.Melee.Kinds.bat
	for _, def in Config.Kit do
		if kit[def.id] ~= true then
			continue
		end
		if def.melee then
			table.insert(out, {
				id = def.id,
				name = def.name,
				picture = { model = "melee:bat", icon = Icons.kit(def.id), emoji = def.icon },
				fact = `💥 {melee.damage} DMG · V SWINGS IT`,
				owned = true,
				accent = tint("melee"),
				lines = { def.description },
			})
		end
	end
	for _, item in consumables(ctx) do
		table.insert(out, item)
	end
	local worn = KitFit.outfit(kit, nil).vest
	for _, def in Config.Kit do
		if kit[def.id] ~= true or not (def.armour or def.tips) then
			continue
		end
		local wearing = def.id == worn or def.tips ~= nil -- (the tips count under an armoured vest too)
		table.insert(out, {
			id = def.id,
			name = def.name,
			picture = { model = `kit:{def.id}`, icon = Icons.kit(def.id), emoji = def.icon },
			fact = if def.armour then `🛡 −{math.floor(def.armour * 100 + 0.5)}% DAMAGE{if def.speed then ` · 🐢 ×{def.speed}` else ""}` else `💵 +{math.floor((def.tips or 0) * 100 + 0.5)}% TIPS`,
			value = if wearing then "WORN" else "SPARE",
			valueColor = if wearing then K.good else C.dim,
			owned = true,
			accent = tint("gear"),
			lines = { def.description },
		})
	end
	local names: { string } = {}
	local shown: string? = nil -- 6.22: MY BAGS shows the bag in use (else the last one owned)
	local using = myBag(state)
	for _, def in Config.Kit do
		if def.extra and kit[def.id] == true then
			table.insert(names, `{def.icon} {string.match(def.name, "^(%S+)") or def.name}`)
			shown = if using then using.id else def.id
		end
	end
	if #names > 0 then
		table.insert(out, {
			id = "mybags",
			name = "My bags",
			picture = { model = if shown then `kit:{shown}` else nil, emoji = "👜" },
			fact = table.concat(names, " · "),
			value = tostring(#names),
			valueColor = C.secondary,
			owned = true,
			accent = BLUE,
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
			picture = { model = `kit:{def.id}`, icon = Icons.kit(def.id), emoji = def.icon },
			fact = (if mine then "✓ IN USE · " else "") .. `🏃 LIGHT PIECES{perk}`,
			value = `+{def.extra}`,
			owned = true,
			accent = BLUE,
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
				picture = { model = `gun:{def.id}`, icon = Icons.weapon(def.id), emoji = "🔫" },
				fact = ShopWindow.gunFact(def) .. (if def.oneHanded then " · 1-HAND" else ""),
				owned = true,
				accent = if def.exclusive then nil else tint("weapon"),
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
				table.insert(out, { id = def.id, name = def.name, picture = { model = `gun:{def.id}`, icon = Icons.weapon(def.id), emoji = "🔫" }, fact = `EARNED AT {string.upper(employer.name)} · {math.min(done, at)}/{at}`, lock = "🔒 WORK", lines = { def.description } })
			end
		end
	end
	return out
end

-- 6.21: the header chips: what is in your hand, what you carry, your cash.
local function chips(ctx: Ctx): { CardKit.Chip }
	local state = ctx.state
	local out: { CardKit.Chip } = {}
	local held = heldNow()
	if held then
		local what = "FISTS"
		if held == "bag" then
			local active = myBag(state)
			what = if active then string.upper(active.name) else "BAG"
		elseif held == "gun" then
			local gun = Economy.findWeapon(if type(state) == "table" then state.weapon else nil)
			what = if gun then string.upper(gun.name) else "GUN"
		end
		table.insert(out, { name = "InHand", text = `✋ IN HAND · {what}`, static = true })
	end
	local have, total = carrying(state, ctx.job)
	table.insert(out, { name = "Carrying", text = `📦 {have}/{total}`, ink = BLUE, static = true })
	table.insert(out, { name = "Cash", text = Ui.money(tonumber(state and state.money) or 0), ink = C.money, static = true })
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
	local section: string? = nil
	local hero: Item? = bagHero(ctx)
	if ctx.tab == "bag" then
		items = pieces(ctx.job)
		name = "BagRows"
		empty = "Nothing in your bag. Pick up an order at a shop: the cook or the clerk hands it over at the door."
		foot = if #items == 0 then empty else nil
		section = if #items > 0 then `CARRYING · {#items}` else nil
	elseif ctx.tab == "bags" then
		local missing
		items, missing = bags(ctx)
		name = "BagsRows"
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
		items = onYou(ctx)
		section = `ON YOU · {#items}`
		foot = "Last Stop Supplies (the gear stall) sells more."
	end
	if hero then
		table.insert(items, 1, hero)
	end
	local key = `bag:{ctx.tab}`
	local first = ShopView.draw(list, {
		key = key,
		items = items,
		money = tonumber(state and state.money) or 0,
		side = ctx.side,
		room = ctx.room,
		order = order,
		tabs = { tabs = ctx.tabs, selected = ctx.tab, onPick = ctx.pick },
		chips = chips(ctx),
		bar = ctx.bar,
		section = section,
		foot = foot,
		empty = empty,
		redraw = ctx.redraw,
		toast = ctx.toast,
		heroArt = function(card: any, item: Item)
			if item.id == "yourbag" then
				drawStack(card, ctx)
			end
		end,
		-- MY BAGS opens the BAGS tab; every other row its details
		onPick = function(item: Item)
			if item.id == "mybags" then
				ctx.pick("bags")
				return
			end
			ShopView.opened[key] = item.id
			ctx.redraw()
		end,
	})
	-- (the rows' column by what it holds: BagRows, ItemRows, BagsRows …)
	local cards = list:FindFirstChild("ShopCards")
	if cards then
		cards.Name = name
	end
	return first
end

return BagUi
