--!strict
-- 5.0: Last Stop Supplies' KIT tab (the shop window in client/Hud.luau draws it with KitShop.render, beside ITEMS):
-- your personal gear (Config.Kit; profile.kit in the state as `kit`, missing = none). It is yours for good, on foot
-- and (5.1) on a bike: what you carry (shared/Transport.luau), how fast you walk, how warm the food stays.
--
-- On top YOUR ROOM: "HANDS 2 / BACKPACK 3" with a pip for every light piece you can carry and the walk speed; then
-- every piece as a slim contract row (like 4.6's client/GearShop.luau): its icon and name, its level and price,
-- OWNED or not, what it does, and the one action that fits: BUY (at the counter, with the money), OWNED, a dim
-- "🔒 LEVEL n", or "MORE ROOM ALREADY" for a backpack smaller than the one you have. The server checks everything again
-- (server/Shops.luau, the "Kit" remote: at the counter, not owned yet, the level, the money). Presentation only:
-- KitShop.tab (the shop's open tab: "items" | "kit", nil = KIT while some piece is still to buy) is its only state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Transport = require(Shared.Transport)
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
function KitShop.currentTab(state: any): string
	local picked = KitShop.tab
	if picked then
		return picked
	end
	local kit = KitShop.owned(state)
	for _, def in Config.Kit do
		if not kit[def.id] then
			return "kit"
		end
	end
	return "items"
end

-- A piece's short name for the room line ("Courier Backpack" → "BACKPACK").
local function shortName(def: Config.KitDef): string
	return string.upper((string.gsub(def.name, "^Courier ", "")))
end

-- What you carry, in words: "HANDS 2" or "HANDS 2 / BACKPACK 3" (the best backpack owned). Also for the job board and
-- the phone.
function KitShop.roomText(kit: Transport.Kit): string
	local hands = Config.Cargo.HandsMax
	local room = Transport.handsRoom(kit)
	local best: Config.KitDef? = nil
	for _, def in Config.Kit do
		local r = def.room
		if kit[def.id] and r and (best == nil or r > (best.room or 0)) then
			best = def
		end
	end
	if best and room > hands then
		return `HANDS {hands} / {shortName(best)} {room}`
	end
	return `HANDS {room}`
end

-- What a piece does, in a few words (the row's stat line).
local function effect(def: Config.KitDef): string
	local parts: { string } = {}
	if def.room then
		table.insert(parts, `📦 {def.room} light pieces`)
	end
	if def.speed then
		table.insert(parts, `👟 walk & sprint +{math.floor((def.speed - 1) * 100 + 0.5)}%`)
	end
	if def.warm then
		table.insert(parts, `🔥 food cools ×{def.warm}`)
	end
	return table.concat(parts, "  ·  ")
end

local function action(row: any, text: string, kind: P.ButtonKind, onClick: () -> ())
	local button = P.button(row, text, UDim2.fromOffset(BUTTON_W, 40), kind, if kind == "off" then function() end else onClick)
	button.Position = UDim2.new(1, -BUTTON_W - 12, 0.5, -20)
	button.TextSize = 14
	return button
end

-- Draws the KIT tab into `body` (the shop's scrolling body, a vertical list; Hud clears it and puts the tabs at
-- LayoutOrder 0 first). `here`: at the counter (only there BUY works).
function KitShop.render(body: Instance, state: any, here: boolean)
	local kit = KitShop.owned(state)
	local level = myLevel(state)
	local money = tonumber(state.money) or 0
	local room = Transport.handsRoom(kit)
	local speed = Transport.speedMult(kit)

	-- YOUR ROOM: a pip for every light piece you can carry, the walk speed.
	local head = Ui.make("Frame", { Name = "KitRoom", Size = UDim2.new(1, -12, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, body)
	Ui.list(head, true, 4)
	P.caps(head, "Personal gear · yours for good, on foot and on a bike", UDim2.new(1, 0, 0, 16), { LayoutOrder = 1, TextStrokeTransparency = 1 })
	local line = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 2 }, head)
	Ui.list(line, false, 6)
	P.text(line, KitShop.roomText(kit), UDim2.fromOffset(0, 28), { AutomaticSize = Enum.AutomaticSize.X, Font = Theme.HeadingFont, TextSize = 20, TextStrokeTransparency = 1, LayoutOrder = 1 })
	local most = Config.Cargo.HandsMax
	for _, def in Config.Kit do
		most = math.max(most, def.room or 0)
	end
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
	P.caps(line, if speed > 1.001 then `  ·  SPEED ×{string.format("%.2g", speed)}` else "  ·  SPEED ×1", UDim2.fromOffset(0, 28), { AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, TextStrokeTransparency = 1, LayoutOrder = most + 2 })
	Ui.label(head, "On foot you carry light things only (letters, medicine, pizza, parcels): two in your hands, more with a backpack. The best backpack you own counts; so do the best shoes. Bought once, kept for good.", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		TextColor3 = P.ink2,
		TextSize = 14,
		Font = Theme.Font,
	})

	for order, def in Config.Kit do
		local owned = kit[def.id] == true
		-- A backpack smaller than (or as big as) the room you have already adds nothing.
		local outgrown = not owned and def.room ~= nil and def.speed == nil and def.warm == nil and def.room <= room
		local row = P.row(body, ROW_H, order + 2, owned)
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
		Ui.label(row, `Level {def.level} · {Ui.money(def.price)} · {status}`, UDim2.new(1, -(left + BUTTON_W + 24), 0, 18), {
			Position = UDim2.fromOffset(left, 32),
			TextSize = 13,
			Font = Theme.HeadingFont,
			TextColor3 = P.ink2,
			RichText = true,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		Ui.label(row, def.description, UDim2.new(1, -(left + BUTTON_W + 24), 0, 34), { Position = UDim2.fromOffset(left, 52), TextSize = 13, Font = Theme.Font, TextColor3 = P.ink2, TextYAlignment = Enum.TextYAlignment.Top })
		if owned then
			action(row, "OWNED", "off", function() end)
		elseif level < def.level then
			action(row, `🔒 LEVEL {def.level}`, "off", function() end)
		elseif outgrown then
			action(row, "MORE ROOM ALREADY", "off", function() end)
		elseif not here then
			action(row, `BUY {Ui.money(def.price)}`, "off", function() end)
		else
			action(row, `BUY {Ui.money(def.price)}`, if money >= def.price then "main" else "off", function()
				Net.get("Kit"):FireServer("buy", def.id)
			end)
		end
	end
end

return KitShop
