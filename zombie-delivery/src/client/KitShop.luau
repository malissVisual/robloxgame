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
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)

local KitShop = {}

-- The supplies window's open tab ("items" | "kit"); nil until picked: KIT while some piece is still to buy.
KitShop.tab = nil :: string?

local player = Players.LocalPlayer
local ROW_H = 92
local BUTTON_W = 150

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
	local hands = Config.Cargo.HandsMax
	local room = Transport.handsRoom(kit, bag)
	local active = Transport.activeBag(kit, bag)
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

-- 5.8, the courier phone's tag line (design/phone-ui/): the small red square and the caps label, over a head.
local function tagLine(parent: Instance, text: string, order: number): any
	local row = Ui.make("Frame", { Name = "Tag", Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	P.marker(row, 8, { Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0, 0.5) })
	P.caps(row, text, UDim2.new(1, -16, 1, 0), { Position = UDim2.fromOffset(16, 0), TextStrokeTransparency = 1 })
	return row
end

local function action(row: any, text: string, kind: P.ButtonKind, onClick: () -> ())
	local button = P.button(row, text, UDim2.fromOffset(BUTTON_W, 40), kind, if kind == "off" then function() end else onClick)
	button.Position = UDim2.new(1, -BUTTON_W - 12, 0.5, -20)
	button.TextSize = 14
	return button
end

-- Draws the KIT tab into `body` (the shop's scrolling body, a vertical list; Hud clears it and puts the tabs at
-- LayoutOrder 0 first). `here`: at the counter (only there BUY works). 6.6: `only` "bags" draws ZDC Bags' list (the
-- bags), else Last Stop Supplies' KIT (the rest of the kit; 6.7: not the bat, Lead & Co.'s: KitShop.rows "guns").
function KitShop.render(body: Instance, state: any, here: boolean, only: string?)
	local bags = only == "bags"
	local kit = KitShop.owned(state)
	local bag: string? = if type(state.bag) == "string" then state.bag else nil -- 6.4: the bag in use (the server's)
	local room = Transport.handsRoom(kit, bag)
	local speed = Transport.speedMult(kit)

	-- YOUR ROOM: a pip for every light piece you can carry, the walk speed.
	local head = Ui.make("Frame", { Name = "KitRoom", Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, body)
	Ui.list(head, true, 4)
	tagLine(head, if bags then "ZDC Bags · one bag at a time, sprint with your deliveries" else "Personal gear · yours for good, on foot and on a bike", 1)
	local line = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 2 }, head)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, line)
	P.text(line, KitShop.roomText(kit, bag), UDim2.fromOffset(0, 30), { AutomaticSize = Enum.AutomaticSize.X, Font = Theme.DisplayFont, TextSize = 22, TextStrokeTransparency = 1, LayoutOrder = 1 })
	local everything: Transport.Kit = {}
	for _, def in Config.Kit do
		everything[def.id] = true
	end
	local most = Transport.handsRoom(everything) -- (6.0: the hands and the biggest bag)
	for n = 1, most do
		local pip = Ui.make("Frame", {
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = if n <= room then P.ink else P.surface,
			BackgroundTransparency = if n <= room then 0 else 0.4,
			BorderSizePixel = 0,
			LayoutOrder = 1 + n,
		}, line)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = 0.2 }, pip)
	end
	local armour = Armour.percent(kit) -- 6.0: the best vest's share
	P.caps(line, (if math.abs(speed - 1) > 0.001 then `  ·  SPEED ×{string.format("%.2g", speed)}` else "  ·  SPEED ×1")
		.. (if armour > 0 then `  ·  ARMOUR {armour}%` else ""), UDim2.fromOffset(0, 30), { AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, TextStrokeTransparency = 1, LayoutOrder = most + 2 })
	Ui.label(head, if bags then "Your room on foot is your hands + ONE bag: what you pick up drops straight in, and you sprint with it (the hands' pieces stop the sprint). On a bike, its own bag takes the pickups too. Of your bags, the one IN USE counts. Bought once, kept for good." else "On foot you carry light things only (letters, medicine, pizza, parcels): two in your hands, more in a bag (ZDC Bags, the counter next door). The best vest counts. Bought once, kept for good.", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		TextColor3 = P.ink2,
		TextSize = 14,
		Font = Theme.Font,
	})
	P.rule(head, UDim2.new(1, 0, 0, 1), { LayoutOrder = 4 })
	KitShop.rows(body, state, here, if bags then "bags" else "supplies", 2)
end

-- 6.7: the rows of one shop's kit (Transport.kitShop == `shopId`: "bags", "supplies", "guns") into `body` from
-- LayoutOrder `first` + 1 on (a row a piece, in Config.Kit's order). `here`: at the counter. Returns the last order used.
function KitShop.rows(body: Instance, state: any, here: boolean, shopId: string, first: number): number
	local kit = KitShop.owned(state)
	local level = myLevel(state)
	local money = tonumber(state.money) or 0
	local bag: string? = if type(state.bag) == "string" then state.bag else nil -- 6.4: the bag in use (the server's)
	local armour = Armour.percent(kit) -- 6.0: the best vest's share
	local last = first
	for order, def in Config.Kit do
		if Transport.kitShop(def) ~= shopId then
			continue -- (6.6: the bags at ZDC Bags, the rest at Last Stop Supplies; 6.7: the bat at Lead & Co.)
		end
		last = first + order
		local owned = kit[def.id] == true
		-- 6.0: a vest no better than the one you have adds nothing either (the best vest counts).
		local outclassed = not owned and def.armour ~= nil and def.armour * 100 <= armour
		local row = P.row(body, ROW_H, first + order, owned)
		-- (its icon, art/icons/kit_*, once uploaded: shared/Icons.luau; the emoji until then)
		Ui.icon(row, Icons.kit(def.id), def.icon, UDim2.fromOffset(40, 40), {
			Position = UDim2.fromOffset(14, ROW_H / 2 - 20),
			TextSize = 26,
			TextXAlignment = Enum.TextXAlignment.Center,
			ImageColor3 = P.ink,
		})
		local left = 64
		local textW = UDim2.new(1, -(left + BUTTON_W + 24), 0, 22)
		Ui.label(row, def.name, textW, { Position = UDim2.fromOffset(left, 8), TextSize = 17, Font = Theme.HeadingFont, TextColor3 = P.ink, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local status = if owned then `<font color="{P.hex(P.good)}">✓ OWNED</font>`
			elseif level < def.level then `<font color="{P.hex(P.warn)}">LEVEL {def.level}</font>`
			else effect(def)
		-- 6.7: a starter piece (the plastic bag) is never sold: "STARTER · yours" and what it does
		local line = if def.starter then `<font color="{P.hex(P.good)}">STARTER · yours</font> · {effect(def)}`
			else `Level {def.level} · {Ui.money(def.price)} · {status}`
		Ui.label(row, line, UDim2.new(1, -(left + BUTTON_W + 24), 0, 18), {
			Position = UDim2.fromOffset(left, 32),
			TextSize = 13,
			Font = Theme.HeadingFont,
			TextColor3 = P.ink2,
			RichText = true,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		Ui.label(row, def.description, UDim2.new(1, -(left + BUTTON_W + 24), 0, 34), { Position = UDim2.fromOffset(left, 52), TextSize = 13, Font = Theme.Font, TextColor3 = P.ink2, TextYAlignment = Enum.TextYAlignment.Top })
		local active = Transport.activeBag(kit, bag)
		if owned and def.extra and active and active.id == def.id then
			action(row, "IN USE", "off", function() end) -- 6.4: the bag in your hand
		elseif owned and def.extra then
			action(row, "USE", "main", function()
				Net.get("Kit"):FireServer("use", def.id) -- 6.4 (the server refuses while your bag is loaded)
			end)
		elseif owned then
			action(row, "OWNED", "off", function() end)
		elseif def.starter then
			action(row, "STARTER", "off", function() end) -- 6.7 (the server gives a missing one back for free)
		elseif level < def.level then
			action(row, `🔒 LEVEL {def.level}`, "off", function() end)
		elseif outclassed then
			action(row, "BETTER VEST ALREADY", "off", function() end)
		elseif not here then
			action(row, `BUY {Ui.money(def.price)}`, "off", function() end)
		else
			action(row, `BUY {Ui.money(def.price)}`, if money >= def.price then "primary" else "off", function()
				Net.get("Kit"):FireServer("buy", def.id)
			end)
		end
	end
	return last
end

return KitShop
