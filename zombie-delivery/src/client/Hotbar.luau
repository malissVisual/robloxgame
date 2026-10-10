--!strict
-- 6.0.1, the bottom bar (the owner's wish: "a place at the bottom for 5 things in the inventory"), bottom centre in the
-- HUD's ScreenGui (client/Hud.luau's layout() places and scales it: Hotbar.size, Hotbar.place). Three parts:
--   * 6.1, the HAND slots at its left (shared/Holding.luau, server/Hand.luau): what you hold, key 1 fists ✊, 2 the
--     plastic bag 🛍 (its fill "2/2"; "DOWN" while it lies on the ground where you set it), 3 your gun 🔫 (its name; T
--     still picks which gun). The one you hold has the red outline; one you can't take now is dim. A key (Hud's keys
--     call Hotbar.useKey), a click or a tap asks for it (client/Holster.luau's choose); a gamepad's d-pad left / right
--     cycles. Then a thin divider.
--   * Five square item slots: the consumables you own (Config.Items, in the hotbar's order: the first five you have),
--     each with its icon (shared/Icons.luau, the emoji without one), the count and its key in the corner (6.1: 4-8; a
--     touch screen shows two slots, no keys); an empty slot is a dim outline. A key, a click or a tap uses it through
--     Hud's use path (Hotbar.onUse: Hud's useItem, the UseItem remote): a short flash and the red outline on the slot,
--     then a shade while the server's cooldown runs (Config.ItemTuning.UseCooldown, one for every item). 6.7: only
--     the kinds that are for you (Economy.itemShown: the car-only ones once you own a car); more kinds than slots (6
--     kinds for 5 slots, 3 for a touch screen's 2): the last slot is MORE ("+N", its key too, and key 9) and opens the
--     I window's ITEMS (Hotbar.onMore), where every kind has its USE. (6.1's "a sixth kind on key 9" is gone.)
--   * 6.3, over the bar, what you carry as one compact CARRYING pill (shared/Bag.luau Bag.places / Bag.strip are still
--     the data): "CARRYING 🍕✋ 💐🛍 · 2/4", a small cargo icon a piece (Icons.cargo, client/BagUi.luau's emoji) with a
--     badge for where it is (Bag.Marks: ✋ hands, 🛍 the bag, 🚲 6.6: the bike's own bag, 📰 a round's satchel; no
--     backpack any more), greyed when it belongs to
--     another order than the one in focus, "+N" over 8 pieces (5 on a touch screen), then the pieces and the room. No
--     slot frames and no tile a free place: the owner read the 6.0.1 tiles as new inventory slots ("a new inventory
--     slot is created when you pick something up"). From the job payload's `carried` and the PackCount / PackRoom /
--     BagRoom attributes; off duty it hides while you carry nothing. A click opens the I window's BAG tab (BagUi.open).
-- 6.4: the bag slot is the ACTIVE bag's (the state's `bag`: its icon, its name, its room off duty: Transport.bagRoom).
-- 6.3: the bag slot's "n/room" is the server's (the BagRoom attribute) on a job, the kit's off duty; a car job says
-- "HANDS ONLY" (a job whose pickups go to your hands: a car job); a count badge on the slot says the pieces in the bag.
-- The bar: the pill over the row of the hands and the items. A touch screen: the slots at least 48 px, two item slots,
-- no keys. It hides with the HUD (it lives in its ScreenGui) and while a window, the phone or a dialog covers the game
-- (Hotbar.covered, set by the client's Main; checked 10 times a second). Drawn again only when what it shows changed (a
-- State, a job update, the pack attributes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local Bag = require(Shared.Bag)
local Transport = require(Shared.Transport)
local Holding = require(Shared.Holding) -- 6.1: the hand slots
local Economy = require(Shared.Economy)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local BagUi = require(script.Parent.BagUi)
local Holster = require(script.Parent.Holster) -- 6.1: what you hold

local Hotbar = {}

local touch = Ui.touchLayout()
Hotbar.SLOTS = if touch then 2 else Config.ItemTuning.BarSlots -- (6.1: a touch screen keeps room for the hands: 311 wide fits an iPhone SE)
Hotbar.FIRST_KEY = #Holding.Order + 1 -- 6.1: the item slots' keys start after the hands' (4)
-- Set by client/Hud.luau: uses an item (its existing path: the count check, the UseItem remote with the aim point).
Hotbar.onUse = nil :: ((id: string) -> ())?
-- Set by client/Hud.luau: a toast (an empty slot's key).
Hotbar.toast = nil :: ((text: string) -> ())?
-- 6.7, set by client/Hud.luau: opens the I window on its ITEMS tab (the MORE slot).
Hotbar.onMore = nil :: (() -> ())?
-- Set by client/Main.client.luau: does a window, the phone or a dialog cover the game now (the bar hides)?
Hotbar.covered = nil :: (() -> boolean)?

local SLOT, SLOT_GAP = 56, 6 -- the item slots (unscaled)
local PILL_H, PILL_GAP = 26, 6 -- 6.3: the CARRYING pill over the row, and the room between them
local PIECE_W, PIECE_ICON = 24, 18 -- a piece in the pill: its width, its icon
local DIVIDER = if touch then 13 else 25 -- the room of a divider between two parts (12 · the line · 12)
local TOUCH_MIN = 48 -- px: the smallest slot on a touch screen
local ITEMS_W = Hotbar.SLOTS * SLOT + (Hotbar.SLOTS - 1) * SLOT_GAP
local HANDS_W = #Holding.Order * SLOT + (#Holding.Order - 1) * SLOT_GAP -- 6.1
local ROW_W = HANDS_W + DIVIDER + ITEMS_W -- the hands and the items (6.3: the pill over them)
local HAND_ICON: { [string]: string } = { fists = "✊", bag = "🛍", gun = "🔫" }
local FLASH = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LIT = 0.6 -- seconds the used slot keeps its red outline

type Slot = {
	button: any,
	outline: any,
	key: any,
	count: any,
	name: any,
	shade: any,
	flash: any,
	icon: any,
	id: string?,
	hover: boolean,
	lit: number,
	more: boolean, -- 6.7: the MORE slot (more kinds than slots): "+N", opens the I window
}

-- 6.1: a hand slot. 6.3: `badge` the bag slot's count of the pieces in it.
type HandSlot = { button: any, outline: any, caption: any, name: any, icon: any, badge: any, hand: string, hover: boolean }

local player = Players.LocalPlayer
local maxPieces = if touch then 5 else 8 -- 6.3: the pieces the pill shows ("+N" after them)
local root: any = nil
local rootScale: any = nil
local pill: any = nil -- 6.3: the CARRYING pill (a button: the BAG tab)
local pillRow: any = nil -- … its pieces in a row
local pillCount: any = nil -- … and "2/4" at its end
local slots: { Slot } = {}
local hands: { HandSlot } = {}
local shownHands = ""
local owned: { string } = {} -- the item ids you have, in Config.Items order (slot n = owned[n])
local onBar = 0 -- 6.7: how many of them have a slot (all, or SLOTS - 1 when the last slot is MORE)
local state: any = nil
local job: any = nil
local shownStrip = ""

local function itemDef(id: string): Config.ItemDef?
	for _, def in Config.Items do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- ── The item slots ─────────────────────────────────────────────────────────

local function paint(slot: Slot)
	local filled = slot.id ~= nil or slot.more
	local red = filled and (slot.hover or os.clock() < slot.lit)
	slot.outline.Color = if red then P.red else P.line
	slot.outline.Transparency = if red then 0 elseif filled then 0.35 else 0.72
	slot.button.BackgroundTransparency = if not filled then 0.72 elseif slot.hover then 0.15 else 0.3
	slot.key.TextTransparency = if filled then 0 else 0.55
	slot.name.Visible = slot.hover and filled and not touch
end

-- The server's cooldown after a use (one for every item): a charcoal shade over the slots that sinks away.
local function cooldown()
	local seconds = tonumber(Config.ItemTuning.UseCooldown) or 0
	if seconds <= 0 then
		return
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Linear)
	for _, slot in slots do
		local shade = slot.shade
		if slot.id then
			shade.Size = UDim2.fromScale(1, 1)
			shade.Visible = true
			local tween = TweenService:Create(shade, info, { Size = UDim2.fromScale(1, 0) })
			tween.Completed:Once(function(playback: Enum.PlaybackState)
				if playback == Enum.PlaybackState.Completed then
					shade.Visible = false
				end
			end)
			tween:Play()
		end
	end
end

-- 6.7: the I window's ITEMS (the MORE slot, or key 9 while there are more kinds than slots).
local function openMore()
	local more = Hotbar.onMore
	if more then
		more()
	end
end

local function use(index: number)
	if #owned > onBar and index >= onBar + 1 then
		openMore() -- 6.7: the MORE slot (and the key after the bar)
		return
	end
	local id = owned[index]
	if not id then
		local say = Hotbar.toast
		if say and index <= Hotbar.SLOTS then
			say(`Key {index + Hotbar.FIRST_KEY - 1} is empty: Last Stop Supplies (the gear stall by the spawn) sells medkits, energy drinks, molotovs (and car items once you own a car).`)
		end
		return
	end
	local slot = slots[index]
	if slot then
		slot.lit = os.clock() + LIT
		paint(slot)
		slot.flash.BackgroundTransparency = 0.55
		TweenService:Create(slot.flash, FLASH, { BackgroundTransparency = 1 }):Play()
		task.delay(LIT + 0.02, function()
			paint(slot)
		end)
	end
	cooldown()
	local onUse = Hotbar.onUse
	if onUse then
		onUse(id)
	end
end

local function buildSlot(parent: Instance, index: number): Slot
	local button = Ui.make("TextButton", {
		Name = `Slot{index}`,
		Size = UDim2.fromOffset(SLOT, SLOT),
		Position = UDim2.fromOffset((index - 1) * (SLOT + SLOT_GAP), 0),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, parent)
	local slot: Slot = {
		button = button,
		outline = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = 0.72 }, button),
		-- the key in small caps, top left (no keys on a touch screen)
		key = P.caps(button, tostring(index + Hotbar.FIRST_KEY - 1), UDim2.fromOffset(14, 14), { Position = UDim2.fromOffset(5, 3), TextSize = 11, TextStrokeTransparency = 1, ZIndex = 5, Visible = not touch }),
		-- the count, white, bottom right
		count = P.text(button, "", UDim2.fromOffset(SLOT - 10, 16), {
			Position = UDim2.new(1, -5, 1, -3),
			AnchorPoint = Vector2.new(1, 1),
			Font = Theme.HeadingFont,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 5,
		}),
		-- the name over the slot while the mouse (or the gamepad) is on it
		name = P.caps(button, "", UDim2.fromOffset(0, 18), {
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.new(0.5, 0, 0, -6),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = P.surface,
			BackgroundTransparency = 0.15,
			TextColor3 = P.ink,
			Visible = false,
			ZIndex = 6,
		}),
		shade = Ui.make("Frame", {
			Name = "Cooldown",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = P.surface,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 3,
		}, button),
		flash = Ui.make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.ink, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 }, button),
		icon = nil,
		id = nil,
		hover = false,
		lit = 0,
		more = false,
	}
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, slot.name)
	local function hover(on: boolean)
		slot.hover = on
		paint(slot)
	end
	button.MouseEnter:Connect(function()
		hover(true)
	end)
	button.MouseLeave:Connect(function()
		hover(false)
	end)
	button.SelectionGained:Connect(function()
		hover(true)
	end)
	button.SelectionLost:Connect(function()
		hover(false)
	end)
	button.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		use(index)
	end)
	return slot
end

-- The slots from the State's items: the first five kinds you have, their icons only when a slot's kind changed.
-- 6.7: only the kinds that are for you (Economy.itemShown: a car item once you own a car); more kinds than slots: the
-- last slot is MORE ("+N" kinds, the I window).
local function drawItems()
	table.clear(owned)
	local items = if state and type(state.items) == "table" then state.items else {}
	local cars = if state and type(state.cars) == "table" then state.cars else nil
	for _, def in Config.Items do
		if (tonumber(items[def.id]) or 0) > 0 and Economy.itemShown(def, cars) then
			table.insert(owned, def.id)
		end
	end
	local overflow = #owned > Hotbar.SLOTS
	onBar = if overflow then Hotbar.SLOTS - 1 else #owned
	local moreText = `+{#owned - onBar}`
	for index, slot in slots do
		local more = overflow and index == Hotbar.SLOTS
		local id = if index <= onBar then owned[index] else nil
		if id ~= slot.id or more ~= slot.more or (more and slot.icon ~= nil and slot.icon.Text ~= moreText) then
			if slot.icon then
				slot.icon:Destroy()
				slot.icon = nil
			end
			slot.id = id
			slot.more = more
			local def = if id then itemDef(id) else nil
			if more then
				-- 6.7: "+N" kinds more, in the I window
				slot.icon = P.text(slot.button, moreText, UDim2.fromOffset(SLOT - 8, 28), {
					Position = UDim2.new(0.5, 0, 0.5, -2),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Font = Theme.DisplayFont,
					TextSize = 22,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextStrokeTransparency = 1,
					ZIndex = 2,
				})
				slot.name.Text = "MORE ITEMS · THE I WINDOW"
			elseif id and def then
				slot.icon = Ui.icon(slot.button, Icons.item(id), def.icon, UDim2.fromOffset(28, 28), {
					Position = UDim2.new(0.5, 0, 0.5, -2),
					AnchorPoint = Vector2.new(0.5, 0.5),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					ImageColor3 = P.ink,
					ZIndex = 2,
				})
				slot.name.Text = string.upper(def.name)
			end
			paint(slot)
		end
		local text = if id then tostring(math.floor(tonumber(items[id]) or 0)) elseif more then "MORE" else ""
		if slot.count.Text ~= text then
			slot.count.Text = text
		end
	end
end

-- ── 6.1: the hand slots ────────────────────────────────────────────────────

local function kitOwned(): { [string]: boolean }
	return if state and type(state.kit) == "table" then state.kit else {}
end

-- Whether you own the bag, what is in it, its room, whether it lies on the ground and (6.3) whether this is a car job.
-- 6.3: the room is the server's on a job (the BagRoom attribute: 0 on a car job, whose pickups go to the hands), the
-- kit's extra off duty, so the slot never promises room the server does not give.
-- 6.4: the active bag (the server's state.bag) and its room off duty (Transport.bagRoom: that bag's, never the sum).
local function bagId(): string?
	return if state and type(state.bag) == "string" then state.bag else nil
end

local function bagNow(): (boolean, number, number, boolean, boolean)
	local kit = kitOwned()
	local owned = bagId() ~= nil
	-- (6.3 review: the server decides: no BagRoom on this job = the bag takes nothing here; a mission's foot job is
	-- built with the car mode, so the mode alone said "CAR JOB" wrongly)
	local carJob = job ~= nil and player:GetAttribute("BagRoom") == nil
	local room = if job then math.floor(tonumber(player:GetAttribute("BagRoom")) or 0)
		else Transport.bagRoom(kit, bagId())
	local count = math.floor(tonumber(player:GetAttribute("BagCount")) or 0)
	return owned, count, room, typeof(player:GetAttribute("BagDown")) == "Vector3", carJob
end

local function buildHand(parent: Instance, index: number, hand: string): HandSlot
	local button = Ui.make("TextButton", {
		Name = `Hand{index}`,
		Size = UDim2.fromOffset(SLOT, SLOT),
		Position = UDim2.fromOffset((index - 1) * (SLOT + SLOT_GAP), 0),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, parent)
	local slot: HandSlot = {
		button = button,
		outline = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = 0.35 }, button),
		caption = P.caps(button, "", UDim2.new(1, -6, 0, 12), {
			Position = UDim2.new(0.5, 0, 1, -3),
			AnchorPoint = Vector2.new(0.5, 1),
			TextSize = 9,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 1,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 5,
		}),
		name = P.caps(button, "", UDim2.fromOffset(0, 18), {
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.new(0.5, 0, 0, -6),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = P.surface,
			BackgroundTransparency = 0.15,
			TextColor3 = P.ink,
			Visible = false,
			ZIndex = 6,
		}),
		icon = nil,
		-- 6.3: the bag's pieces as a count in its top right corner (hidden while it is empty)
		badge = if hand == "bag" then P.text(button, "", UDim2.fromOffset(18, 18), {
			Position = UDim2.new(1, 4, 0, -4),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = P.red,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextStrokeTransparency = 1,
			Visible = false,
			ZIndex = 7,
		}) else nil,
		hand = hand,
		hover = false,
	}
	if slot.badge then
		Ui.corner(slot.badge, 9)
	end
	P.caps(button, tostring(index), UDim2.fromOffset(14, 14), { Position = UDim2.fromOffset(5, 3), TextSize = 11, TextStrokeTransparency = 1, ZIndex = 5, Visible = not touch })
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, slot.name)
	local function hover(on: boolean)
		slot.hover = on
		slot.name.Visible = on and not touch
	end
	button.MouseEnter:Connect(function()
		hover(true)
	end)
	button.MouseLeave:Connect(function()
		hover(false)
	end)
	button.SelectionGained:Connect(function()
		hover(true)
	end)
	button.SelectionLost:Connect(function()
		hover(false)
	end)
	button.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		Holster.choose(hand)
	end)
	return slot
end

-- The hand slots as they are now (drawn again only when something they show changed: checked 10 times a second).
local function drawHands(): boolean
	if #hands == 0 then
		return false
	end
	local held = Holster.hand()
	local owned, count, room, down, carJob = bagNow()
	local weapon = if state and type(state.weapon) == "string" then state.weapon else nil
	local bat = kitOwned().bat == true -- 6.7: the Baseball Bat (V swings it with the gun away)
	local key = `{held}|{owned}|{count}|{room}|{down}|{carJob}|{weapon}|{bagId()}|{bat}`
	if key == shownHands then
		return false
	end
	shownHands = key
	local def = if weapon then Economy.findWeapon(weapon) else nil
	for _, slot in hands do
		local hand = slot.hand
		local can = Holding.can(hand, owned, def ~= nil, down)
		local caption, title, image = "", "", nil
		if hand == "fists" then
			caption, title = "FISTS", if bat then "FISTS · V SWINGS THE BAT" else "FISTS · V PUNCHES"
		elseif hand == "bag" then
			caption = if not owned then "NO BAG" elseif down then `DOWN {count}` elseif carJob then "HANDS ONLY" else `{count}/{room}`
			-- 6.4: the active bag's name and icon; its point first: you sprint with what rides in it
			local bagDef = Transport.findKit(bagId() or Config.Courier.BagKit)
			local name = if bagDef then string.upper(bagDef.name) else "BAG"
			title = if down then "YOUR BAG IS ON THE GROUND" elseif owned and carJob then `{name} · NOT ON THIS JOB: PICKUPS GO TO YOUR HANDS` else `{name} · SPRINT WITH YOUR DELIVERIES`
			image = Icons.kit(bagId() or Config.Courier.BagKit)
		else
			caption = if def then string.upper(def.name) else "NO GUN"
			title = if def then `{string.upper(def.name)} · T PICKS THE GUN` else "NO GUN"
			image = if def then Icons.weapon(def.id) else nil
		end
		if slot.icon then
			slot.icon:Destroy()
		end
		slot.icon = Ui.icon(slot.button, image, HAND_ICON[hand], UDim2.fromOffset(26, 26), {
			Position = UDim2.new(0.5, 0, 0.5, -5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ImageColor3 = P.ink,
			TextTransparency = if can then 0 else 0.55,
			ImageTransparency = if can then 0 else 0.55,
			ZIndex = 2,
		})
		slot.caption.Text = caption
		local badge = slot.badge
		if badge then
			badge.Text = tostring(count)
			badge.Visible = owned and count > 0 and not down
		end
		slot.caption.TextColor3 = if hand == "bag" and down then P.warn else P.ink
		slot.caption.TextTransparency = if can or down then 0 else 0.5
		slot.name.Text = title
		local mine = held == hand
		slot.outline.Color = if mine then P.red else P.line
		slot.outline.Thickness = if mine then 2 else 1
		slot.outline.Transparency = if mine then 0 elseif can then 0.35 else 0.72
		slot.button.BackgroundTransparency = if mine then 0.12 elseif can then 0.3 else 0.72
	end
	return true
end

-- ── What you carry ─────────────────────────────────────────────────────────

-- Your room by place: the job's (the payload, the live PackRoom attribute), off duty your kit's on foot. 6.6: the
-- hands + the bag (one carrying item) + on a run with a bike its own bag.
local function placesNow(): { Bag.Place }
	local kit = if state and type(state.kit) == "table" then state.kit else {}
	-- (6.1: the bag's room only while it is in your hand, a bag on your back its pieces; 6.3: on a job the server's,
	-- the BagRoom attribute)
	local _, count, room = bagNow()
	local active = Transport.activeBag(kit, bagId())
	local bagRoom = if Holster.hand() == "bag" then room elseif active and active.stays then math.min(count, room) else 0
	if job then
		local mode = if type(job.mode) == "string" then job.mode else "car"
		local packRoom = tonumber(player:GetAttribute("PackRoom")) or tonumber(job.packRoom) or 0
		return Bag.places(mode, packRoom, tonumber(job.rack) or 0, bagRoom)
	end
	return Bag.places("foot", bagRoom, 0, bagRoom)
end

-- The pieces: the payload's `carried`; the live PackCount attribute adds the pack's pieces the payload has not yet.
local function carriedNow(): { any }
	local list: { any } = {}
	if not job then
		return list
	end
	local inPack = 0
	if type(job.carried) == "table" then
		for _, piece in job.carried do
			if type(piece) == "table" then
				table.insert(list, piece)
				if piece.where == "pack" or piece.where == "rack" or piece.where == "bag" then -- (6.19: the bag's pieces too: "7/6")
					inPack += 1
				end
			end
		end
	end
	local packed = tonumber(player:GetAttribute("PackCount")) or 0
	for _ = inPack + 1, packed do
		table.insert(list, { where = "pack" })
	end
	return list
end

-- 6.3: one piece in the pill: its small icon and, at its corner, the badge of where it is ("+N" when `more`).
local function pillPiece(piece: any, _where: string, _other: boolean, order: number, count: number?)
	-- 6.19: the kind's icon, and ×n when there are more of it (the place badges are gone)
	local n = count or 1
	local holder = Ui.make("Frame", {
		Name = "Piece",
		Size = UDim2.fromOffset(if n > 1 then PIECE_W + 18 else PIECE_W, PILL_H),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, pillRow)
	local look = if type(piece.look) == "string" then piece.look else nil
	Ui.icon(holder, Icons.cargo(look), BagUi.emoji(look), UDim2.fromOffset(PIECE_ICON, PIECE_ICON), {
		Position = UDim2.new(0, PIECE_W / 2 - 2, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ImageColor3 = P.ink,
	})
	if n > 1 then
		Ui.label(holder, `×{n}`, UDim2.fromOffset(20, PILL_H), {
			Name = "Count",
			Position = UDim2.fromOffset(PIECE_W - 4, 0),
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = P.ink,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
end

local function drawStrip()
	if not root then
		return
	end
	local places = placesNow()
	local carried = carriedNow()
	local focus = if job and type(job.focus) == "number" then job.focus else nil
	-- (Bag.strip still sorts the pieces by place and fills the bag first; the pill draws the pieces only: the free room
	-- is a number, not empty tiles)
	local tiles, _, morePieces = Bag.strip(carried, places, focus, maxPieces + 1)
	local pieces, room = 0, 0
	for _, place in places do
		room += place.room
	end
	-- 6.19 (the owner: "CARRYING looks all weird"): one icon per kind of piece with its count (×3), no badge per piece
	local parts: { string } = {}
	local shown: { Bag.Tile } = {}
	local counts: { [string]: number } = {}
	local hidden = 0
	for _, t in tiles do
		local piece = t.piece
		if piece then
			pieces += 1
			local look = tostring(piece.look)
			if counts[look] then
				counts[look] += 1
			elseif #shown < maxPieces then
				counts[look] = 1
				table.insert(shown, t)
			else
				hidden += 1
			end
		end
	end
	pieces += morePieces
	for _, t in shown do
		local look = tostring((t.piece :: any).look)
		table.insert(parts, `{look}:{counts[look]}`)
	end
	local more = hidden + morePieces
	local count = `{pieces}/{room}`
	local visible = pieces > 0 or job ~= nil
	local key = `{table.concat(parts, ",")}|{more}|{count}|{visible}`
	if key == shownStrip then
		return
	end
	shownStrip = key
	Ui.clear(pillRow)
	for index, t in shown do
		pillPiece(t.piece, t.where, false, index, counts[tostring((t.piece :: any).look)])
	end
	if more > 0 then
		P.text(pillRow, `+{more}`, UDim2.fromOffset(0, PILL_H), {
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextStrokeTransparency = 1,
			LayoutOrder = #shown + 1,
		})
	end
	pillCount.Text = `· {count}` -- (6.6: "CARRYING 🍕🍕 · 3/4")
	pillCount.TextColor3 = if pieces > 0 then P.ink else P.ink2
	pill.Visible = visible
end

-- ── The bar ────────────────────────────────────────────────────────────────

-- The bar's biggest size (unscaled; Hud's layout() fits that) and the smallest scale it may take (a touch screen: the
-- slots at least TOUCH_MIN px).
function Hotbar.size(): (Vector2, number)
	-- (6.3: the CARRYING pill over the row, on a computer too)
	return Vector2.new(ROW_W, PILL_H + PILL_GAP + SLOT), if touch then TOUCH_MIN / SLOT else 0
end

-- Hud's layout(): the bar's bottom centre (px in the HUD's ScreenGui) and its scale.
function Hotbar.place(x: number, bottom: number, scale: number)
	if not root then
		return
	end
	local position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(bottom + 0.5))
	if root.Position ~= position then
		root.Position = position
	end
	if math.abs(rootScale.Scale - scale) > 0.001 then
		rootScale.Scale = scale
	end
end

-- The item in that place of the ones you own (1 = the first item slot).
function Hotbar.useSlot(index: number)
	use(index)
end

-- 6.1, a number key (Hud's keys): 1 / 2 / 3 what you hold, 4 - 8 the item slots (6.7: the last one MORE while more kinds
-- than slots; 9 then opens the I window too).
function Hotbar.useKey(key: number)
	-- (6.1 review: not while a window, the phone or a dialog covers the game: a stray 1 or 3 there set the bag down)
	local covered = Hotbar.covered
	if covered then
		local ok, value = pcall(covered)
		if ok and value == true then
			return
		end
	end
	local hand = Holding.ofKey(key)
	if hand then
		Holster.choose(hand)
		return
	end
	use(key - Hotbar.FIRST_KEY + 1)
end

-- The key of an item you own (6.1: 4 - 8 its place in the bar), nil when you have none or (6.7) it is behind MORE.
function Hotbar.slotOf(id: string): number?
	local index = table.find(owned, id)
	return if index and index <= onBar then index + Hotbar.FIRST_KEY - 1 else nil
end

function Hotbar.setState(newState: any)
	state = newState
	drawItems() -- (before start: the list of what you own only, for Hotbar.slotOf)
	drawStrip()
	drawHands()
end

function Hotbar.setJob(newJob: any)
	job = newJob
	drawStrip()
end

-- Builds the bar into the HUD's ScreenGui (Hud.start, before its first layout).
function Hotbar.start(gui: Instance)
	if root then
		return
	end
	local size = Hotbar.size()
	root = Ui.make("Frame", {
		Name = "BottomBar",
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
	}, gui)
	rootScale = Ui.make("UIScale", { Name = "LayoutScale" }, root)
	local rowY = PILL_H + PILL_GAP -- (6.3: the pill over the row)
	-- 6.1: the hand slots at the left, a divider, the items.
	local handRow = Ui.make("Frame", {
		Name = "Hands",
		Size = UDim2.fromOffset(HANDS_W, SLOT),
		Position = UDim2.fromOffset(0, rowY),
		BackgroundTransparency = 1,
	}, root)
	for index, hand in Holding.Order do
		hands[index] = buildHand(handRow, index, hand)
	end
	P.rule(root, UDim2.fromOffset(1, 40), { Position = UDim2.fromOffset(HANDS_W + math.floor(DIVIDER / 2), rowY + SLOT - 40) })
	local items = Ui.make("Frame", {
		Name = "Items",
		Size = UDim2.fromOffset(ITEMS_W, SLOT),
		Position = UDim2.fromOffset(HANDS_W + DIVIDER, rowY),
		BackgroundTransparency = 1,
	}, root)
	for index = 1, Hotbar.SLOTS do
		slots[index] = buildSlot(items, index)
	end
	-- 6.3: what you carry, one pill over the row (a click opens the BAG tab): CARRYING, the pieces, "n/room".
	pill = Ui.make("TextButton", {
		Name = "Carried",
		Size = UDim2.fromOffset(0, PILL_H),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
	}, root)
	Ui.corner(pill, math.floor(PILL_H / 2))
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = 0.6 }, pill)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, pill)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pill)
	P.caps(pill, "CARRYING", UDim2.fromOffset(0, PILL_H), { AutomaticSize = Enum.AutomaticSize.X, TextSize = 10, TextStrokeTransparency = 1, LayoutOrder = 1 })
	pillRow = Ui.make("Frame", {
		Name = "Pieces",
		Size = UDim2.fromOffset(0, PILL_H),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, pill)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pillRow)
	pillCount = P.text(pill, "", UDim2.fromOffset(0, PILL_H), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextStrokeTransparency = 1,
		LayoutOrder = 3,
	})
	pill.MouseEnter:Connect(function()
		pill.BackgroundTransparency = 0.12
	end)
	pill.MouseLeave:Connect(function()
		pill.BackgroundTransparency = 0.3
	end)
	pill.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		BagUi.open()
	end)
	player:GetAttributeChangedSignal("PackCount"):Connect(drawStrip)
	player:GetAttributeChangedSignal("PackRoom"):Connect(drawStrip)
	player:GetAttributeChangedSignal("BagRoom"):Connect(drawStrip) -- 6.3
	drawItems()
	drawStrip()
	drawHands()
	-- Hidden while a window, the phone or a dialog covers the game (10 times a second, not every frame).
	task.spawn(function()
		while root and root.Parent do
			task.wait(0.1)
			local covered = Hotbar.covered
			local hide = false
			if covered then
				local ok, value = pcall(covered)
				hide = ok and value == true
			end
			if root.Visible == hide then
				root.Visible = not hide
			end
			if not hide and drawHands() then -- 6.1 (only when what the hand slots show changed)
				drawStrip() -- (the bag's room is yours only in your hand)
			end
		end
	end)
end

return Hotbar
