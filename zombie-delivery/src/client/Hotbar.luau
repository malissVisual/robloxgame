--!strict
-- 6.0.1, the bottom bar (the owner's wish: "a place at the bottom for 5 things in the inventory"), bottom centre in the
-- HUD's ScreenGui (client/Hud.luau's layout() places and scales it: Hotbar.size, Hotbar.place).
-- 6.21, a clean hotbar (the owner picked redesign B "Clean hotbar + kit"; the sizes in Config.Hotbar, the pure maths in
-- shared/Inventory.luau): one row of rounded square slots on a frosted tray, the keys small and grey, the counts as
-- pills at a slot's bottom right corner, and one line over the bar ("PISTOL 22 DMG"):
--   * 6.1, the HAND slots first (shared/Holding.luau, server/Hand.luau): key 1 fists ✊, 2 your bag, 3 your gun. The one
--     in your hand lifts (Config.Hotbar.Lift), grows, has the red frame and glow, and the line over the bar names it
--     (Inventory.handLine: the bag's "5 / 6", the gun's damage, the fists' V). One you can't take now is dim. A key
--     (Hud's keys call Hotbar.useKey), a click or a tap asks for it (client/Holster.luau's choose).
--   * The BAG slot carries what you carry (6.21: it replaces 6.3's CARRYING pill): a blue fill ring and a blue "5/6"
--     pill (Inventory.fill: the pieces you carry on foot over your room: the hands, the bag in your hand, the bike's
--     bag, a round's satchel; 6.20 Strong Back counted: the Skills attribute). A tap on the pill opens BAG & ITEMS on
--     what you carry (BagUi.open), where 6.19's grouped pieces (🍕 ×2) are; "DOWN" while the bag lies on the ground.
--   * Then the item slots: the consumables you own (Config.Items, in the hotbar's order: the first five you have),
--     each with its icon (shared/Icons.luau, the emoji without one), its count pill and its key (6.1: 4-8). A key, a
--     click or a tap uses it through Hud's use path (Hotbar.onUse: Hud's useItem, the UseItem remote): a short flash
--     and the red frame, then a shade while the server's cooldown runs (Config.ItemTuning.UseCooldown). 6.7: only the
--     kinds that are for you (Economy.itemShown); more kinds than slots: the last slot is MORE ("+N", key 9 too) and
--     opens the I window's ITEMS (Hotbar.onMore). An empty slot is a dim outline on a computer.
--   * A touch screen: two item slots, no keys, and only the filled slots show (the tray shrinks to them); the bar is
--     scaled with the HUD, a slot never under Config.Hotbar.TouchMin px (Inventory.minScale), between the thumbstick
--     and JUMP (client/TouchLayout.luau dock).
-- Hovering a slot (the mouse, a gamepad) puts its name in the line over the bar. The bar hides with the HUD (it lives
-- in its ScreenGui) and while a window, the phone or a dialog covers the game (Hotbar.covered, set by the client's
-- Main; checked 10 times a second). Drawn again only when what it shows changed (a State, a job update, the pack
-- attributes, the hand).

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
local Inventory = require(Shared.Inventory) -- 6.21
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local BagUi = require(script.Parent.BagUi)
local Holster = require(script.Parent.Holster) -- 6.1: what you hold

local Hotbar = {}

local touch = Ui.touchLayout()
Hotbar.SLOTS = if touch then 2 else Config.ItemTuning.BarSlots -- (6.1: a touch screen keeps room for the hands: the iPhone SE)
Hotbar.FIRST_KEY = #Holding.Order + 1 -- 6.1: the item slots' keys start after the hands' (4)
-- Set by client/Hud.luau: uses an item (its existing path: the count check, the UseItem remote with the aim point).
Hotbar.onUse = nil :: ((id: string) -> ())?
-- Set by client/Hud.luau: a toast (an empty slot's key).
Hotbar.toast = nil :: ((text: string) -> ())?
-- 6.7, set by client/Hud.luau: opens the I window on its ITEMS tab (the MORE slot).
Hotbar.onMore = nil :: (() -> ())?
-- Set by client/Main.client.luau: does a window, the phone or a dialog cover the game now (the bar hides)?
Hotbar.covered = nil :: (() -> boolean)?

local H = Config.Hotbar
local HANDS = #Holding.Order
local HAND_ICON: { [string]: string } = { fists = "✊", bag = "🛍", gun = "🔫" }
local FLASH = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LIT = 0.6 -- seconds the used slot keeps its red frame
-- the slots' faces (the mock's: a raised charcoal slot, a red-tinted one in your hand, a faint empty one)
local FACE = Color3.fromRGB(30, 34, 41)
local FACE_HELD = Color3.fromRGB(58, 34, 36)
local FACE_EMPTY = Color3.fromRGB(20, 23, 28)
local TRAY = Color3.fromRGB(14, 16, 20)
local PILL = Color3.fromRGB(58, 64, 72)
local TRACK = Color3.fromRGB(52, 57, 64)
local WHITE = Color3.new(1, 1, 1)
local BLUE = Color3.fromRGB(table.unpack(Inventory.rgb("cargo"))) -- the bag's ring and pill (cargo blue)

-- A slot of the bar: a hand's (`hand`) or an item's (`index`).
type Tile = {
	button: any,
	stroke: any,
	glow: any,
	key: any,
	pill: any,
	shade: any,
	flash: any,
	icon: any,
	ring: any, -- the bag's fill ring { right, left } (its gradients)
	hand: string?,
	index: number?,
	id: string?, -- an item slot's item
	more: boolean, -- 6.7: the MORE slot
	hover: boolean,
	lit: number,
	can: boolean, -- a hand you may take now
	line: { string }, -- what the line over the bar says while it is hovered
}

local player = Players.LocalPlayer
local root: any = nil
local rootScale: any = nil
local tray: any = nil
local lineName: any = nil
local lineSub: any = nil
local hands: { Tile } = {}
local slots: { Tile } = {}
local owned: { string } = {} -- the item ids you have, in Config.Items order (slot n = owned[n])
local onBar = 0 -- 6.7: how many of them have a slot (all, or SLOTS - 1 when the last slot is MORE)
local state: any = nil
local job: any = nil
local shownHands = ""
local shownLayout = ""
local heldLine = { "", "" }

local function itemDef(id: string): Config.ItemDef?
	for _, def in Config.Items do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- ── The line over the bar ──────────────────────────────────────────────────

local function showLine()
	if not lineName then
		return
	end
	local words = heldLine
	for _, tile in hands do
		if tile.hover then
			words = tile.line
		end
	end
	for _, tile in slots do
		if tile.hover and (tile.id or tile.more) then
			words = tile.line
		end
	end
	lineName.Text = words[1] or ""
	lineSub.Text = words[2] or ""
	lineSub.Visible = (words[2] or "") ~= ""
end

-- ── A slot ─────────────────────────────────────────────────────────────────

-- Its look: in your hand (lifted, bigger, the red frame and glow), lit (just used, hovered), filled, empty or dim.
local function paint(tile: Tile, held: boolean)
	local filled = tile.hand ~= nil or tile.id ~= nil or tile.more
	local red = held or (filled and tile.hand == nil and (tile.hover or os.clock() < tile.lit))
	local size = if held then H.Selected else H.Tile
	tile.button.Size = UDim2.fromOffset(size, size)
	tile.button.Position = UDim2.new(0, tile.button.Position.X.Offset, 1, -H.PadY - (if held then H.Lift else 0))
	tile.button.BackgroundColor3 = if held then FACE_HELD elseif filled then FACE else FACE_EMPTY
	tile.button.BackgroundTransparency = if held then 0.04 elseif not filled then 0.55 elseif tile.hand and not tile.can then 0.45 elseif tile.hover then 0 else 0.08
	tile.stroke.Color = if red then P.red else WHITE
	tile.stroke.Thickness = if held then 2 else 1
	tile.stroke.Transparency = if red then 0 elseif filled then 0.9 else 0.93
	tile.glow.Visible = held
	tile.key.TextColor3 = if held then P.ink else P.ink2
	tile.key.TextTransparency = if filled then 0.15 else 0.6
	local pill = tile.pill
	if pill and tile.hand ~= "bag" then
		pill.BackgroundColor3 = if held or (red and tile.hand == nil) then P.red else PILL
	end
end

local function buildTile(name: string, x: number): Tile
	local button = Ui.make("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(H.Tile, H.Tile),
		Position = UDim2.new(0, x, 1, -H.PadY),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = FACE,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 2,
	}, tray)
	Ui.corner(button, H.Corner)
	-- the red glow of the slot in your hand: a soft red frame behind it
	local glow = Ui.make("Frame", {
		Name = "Glow",
		Size = UDim2.new(1, 14, 1, 14),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = P.red,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 1,
	}, button)
	Ui.corner(glow, H.Corner + 7)
	local tile: Tile = {
		button = button,
		stroke = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = WHITE, Thickness = 1, Transparency = 0.9 }, button),
		glow = glow,
		-- the key, small and grey, top left (no keys on a touch screen)
		key = P.caps(button, "", UDim2.fromOffset(14, 14), { Name = "Key", Position = UDim2.fromOffset(8, 5), TextSize = 11, TextStrokeTransparency = 1, ZIndex = 5, Visible = not touch }),
		pill = nil,
		shade = nil,
		flash = Ui.make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.ink, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 }, button),
		icon = nil,
		ring = nil,
		hand = nil,
		index = nil,
		id = nil,
		more = false,
		hover = false,
		lit = 0,
		can = true,
		line = { "", "" },
	}
	Ui.corner(tile.flash, H.Corner)
	-- the count pill at the bottom right corner, a little out of the slot
	local pill = P.text(button, "", UDim2.fromOffset(H.PillMin, H.Pill), {
		Name = "Count",
		Position = UDim2.new(1, H.Overhang, 1, H.Overhang),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = PILL,
		BackgroundTransparency = 0,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 1,
		Visible = false,
		ZIndex = 7,
	})
	Ui.corner(pill, H.Pill // 2)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = TRAY, Thickness = 2, Transparency = 0 }, pill)
	tile.pill = pill
	local function hover(on: boolean)
		tile.hover = on
		paint(tile, tile.hand ~= nil and Holster.hand() == tile.hand)
		showLine()
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
	return tile
end

-- A pill's words (its width follows them).
local function setPill(tile: Tile, text: string)
	local pill = tile.pill
	pill.Visible = text ~= ""
	if pill.Text ~= text then
		pill.Text = text
		pill.Size = UDim2.fromOffset(math.max(H.PillMin, 14 + #text * 8), H.Pill)
	end
end

-- ── The item slots ─────────────────────────────────────────────────────────

-- The server's cooldown after a use (one for every item): a charcoal shade over the slots that sinks away.
local function cooldown()
	local seconds = tonumber(Config.ItemTuning.UseCooldown) or 0
	if seconds <= 0 then
		return
	end
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Linear)
	for _, slot in slots do
		local shade = slot.shade
		if slot.id and shade then
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
		paint(slot, false)
		slot.flash.BackgroundTransparency = 0.55
		TweenService:Create(slot.flash, FLASH, { BackgroundTransparency = 1 }):Play()
		task.delay(LIT + 0.02, function()
			paint(slot, false)
		end)
	end
	cooldown()
	local onUse = Hotbar.onUse
	if onUse then
		onUse(id)
	end
end

-- The tray's slots in place: the hands, then the item slots that show (a touch screen: the filled ones only), the
-- tray as wide as them.
local function arrange()
	if not tray then
		return
	end
	local visible = HANDS + Inventory.shown(if #owned > Hotbar.SLOTS then Hotbar.SLOTS else #owned, Hotbar.SLOTS, touch)
	local key = tostring(visible)
	if key == shownLayout then
		return
	end
	shownLayout = key
	local n = 0
	for _, tile in hands do
		n += 1
		tile.button.Position = UDim2.new(0, Inventory.slotX(n, touch), tile.button.Position.Y.Scale, tile.button.Position.Y.Offset)
	end
	for index, tile in slots do
		local shows = index + HANDS <= visible
		tile.button.Visible = shows
		if shows then
			n += 1
			tile.button.Position = UDim2.new(0, Inventory.slotX(n, touch), tile.button.Position.Y.Scale, tile.button.Position.Y.Offset)
		end
	end
	local width = Inventory.size(n, touch)
	tray.Size = UDim2.fromOffset(width, H.Tile + 2 * H.PadY)
end

local function buildSlot(index: number): Tile
	local tile = buildTile(`Slot{index}`, Inventory.slotX(HANDS + index, touch))
	tile.index = index
	tile.key.Text = tostring(index + Hotbar.FIRST_KEY - 1)
	local shade = Ui.make("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
	}, tile.button)
	Ui.corner(shade, H.Corner)
	tile.shade = shade
	tile.button.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		use(index)
	end)
	paint(tile, false)
	return tile
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
				slot.icon = P.text(slot.button, moreText, UDim2.fromOffset(H.Tile - 12, 30), {
					Name = "More",
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Font = Theme.DisplayFont,
					TextSize = 24,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextStrokeTransparency = 1,
					ZIndex = 2,
				})
				slot.line = { "MORE ITEMS", "THE I WINDOW" }
			elseif id and def then
				slot.icon = Ui.icon(slot.button, Icons.item(id), def.icon, UDim2.fromOffset(34, 34), {
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Center,
					ImageColor3 = P.ink,
					ZIndex = 2,
				})
			end
			paint(slot, false)
		end
		local count = if id then math.floor(tonumber(items[id]) or 0) else 0
		setPill(slot, if id then tostring(count) else "")
		local def = if id then itemDef(id) else nil
		if def then
			slot.line = { string.upper(def.name), `×{count}` }
		end
	end
	arrange()
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

local function skillRanks(): any
	return require(Shared.Skills).decode(player:GetAttribute("Skills"))
end

local function bagNow(): (boolean, number, number, boolean, boolean)
	local kit = kitOwned()
	local mine = bagId() ~= nil
	-- (6.3 review: the server decides: no BagRoom on this job = the bag takes nothing here; a mission's foot job is
	-- built with the car mode, so the mode alone said "CAR JOB" wrongly)
	local carJob = job ~= nil and player:GetAttribute("BagRoom") == nil
	-- (off duty: the bag's room + 6.20 Strong Back's piece, Config.Skills; on a job the server counted it)
	local room = if job then math.floor(tonumber(player:GetAttribute("BagRoom")) or 0)
		elseif mine then Transport.bagRoom(kit, bagId()) + require(Shared.Skills).effect(skillRanks(), "bag")
		else 0
	local count = math.floor(tonumber(player:GetAttribute("BagCount")) or 0)
	return mine, count, room, typeof(player:GetAttribute("BagDown")) == "Vector3", carJob
end

-- Your room by place: the job's (the payload, the live PackRoom attribute), off duty your kit's on foot. 6.6: the
-- hands + the bag (one carrying item) + on a run with a bike its own bag.
local function placesNow(): { Bag.Place }
	local kit = kitOwned()
	-- (6.1: the bag's room only while it is in your hand, a bag on your back its pieces; 6.3: on a job the server's,
	-- the BagRoom attribute)
	local _, count, room = bagNow()
	local active = Transport.activeBag(kit, bagId())
	local bagRoom = if Holster.hand() == "bag" then room elseif active and active.stays then math.min(count, room) else 0
	-- 6.20: the hands' room with Strong Back (Config.Skills, the player attribute Skills)
	local handsRoom = Config.Cargo.HandsMax + require(Shared.Skills).effect(skillRanks(), "hands")
	if job then
		local mode = if type(job.mode) == "string" then job.mode else "car"
		local packRoom = tonumber(player:GetAttribute("PackRoom")) or tonumber(job.packRoom) or 0
		return Bag.places(mode, packRoom, tonumber(job.rack) or 0, bagRoom, handsRoom)
	end
	return Bag.places("foot", bagRoom, 0, bagRoom, handsRoom)
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

-- What you carry on foot and your room (6.3's CARRYING pill's numbers, now the bag slot's ring and pill). The vehicle's
-- pieces are not counted (Bag.strip leaves them out).
local function carryNow(): (number, number)
	local places = placesNow()
	local focus = if job and type(job.focus) == "number" then job.focus else nil
	local tiles, _, morePieces = Bag.strip(carriedNow(), places, focus, 999)
	local pieces, room = morePieces, 0
	for _, t in tiles do
		if t.piece then
			pieces += 1
		end
	end
	for _, place in places do
		room += place.room
	end
	return pieces, room
end
Hotbar.carryNow = carryNow -- (the checks read it)

-- The bag slot's fill ring: a track, then two half rings each clipped to its half (Inventory.ring).
local function buildRing(button: any): any
	local size = H.Tile - 2 * H.RingInset
	local t = H.Ring
	local ring = Ui.make("Frame", { Name = "Ring", Size = UDim2.fromOffset(size, size), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 2 }, button)
	local track = Ui.make("Frame", { Name = "Track", Size = UDim2.new(1, -2 * t, 1, -2 * t), Position = UDim2.fromOffset(t, t), BackgroundTransparency = 1, ZIndex = 2 }, ring)
	Ui.corner(track, size)
	Ui.make("UIStroke", { Color = TRACK, Thickness = t, Transparency = 0 }, track)
	local halves: { [string]: any } = { Frame = ring }
	for _, side in { "Right", "Left" } do
		local clip = Ui.make("Frame", {
			Name = side,
			Size = UDim2.fromScale(0.5, 1),
			Position = UDim2.fromScale(if side == "Right" then 0.5 else 0, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 3,
		}, ring)
		local arc = Ui.make("Frame", {
			Name = "Arc",
			Size = UDim2.new(2, -2 * t, 1, -2 * t),
			Position = UDim2.new(if side == "Right" then -1 else 0, t, 0, t),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, clip)
		Ui.corner(arc, size)
		local stroke = Ui.make("UIStroke", { Color = BLUE, Thickness = t, Transparency = 0 }, arc)
		halves[side] = Ui.make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.501, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = 0,
		}, stroke)
	end
	return halves
end

local function buildHand(index: number, hand: string): Tile
	local tile = buildTile(`Hand{index}`, Inventory.slotX(index, touch))
	tile.hand = hand
	tile.key.Text = tostring(index)
	if hand == "bag" then
		tile.ring = buildRing(tile.button)
		-- the "5/6" pill, blue: a tap opens BAG & ITEMS on what you carry (6.3's CARRYING pill did)
		local pill = tile.pill
		pill.BackgroundColor3 = BLUE
		local open = Ui.make("TextButton", { Name = "Open", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 8 }, pill)
		open.Activated:Connect(function()
			local click = Ui.onClick
			if click then
				click()
			end
			BagUi.open()
		end)
	end
	tile.button.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		Holster.choose(hand)
	end)
	return tile
end

-- The hand slots as they are now (drawn again only when something they show changed: checked 10 times a second).
local function drawHands(): boolean
	if #hands == 0 then
		return false
	end
	local held = Holster.hand()
	local mine, count, _, down, carJob = bagNow()
	local pieces, room = carryNow()
	local weapon = if state and type(state.weapon) == "string" then state.weapon else nil
	local bat = kitOwned().bat == true -- 6.7: the Baseball Bat (V swings it with the gun away)
	local key = `{held}|{mine}|{count}|{pieces}|{room}|{down}|{carJob}|{weapon}|{bagId()}|{bat}`
	if key == shownHands then
		return false
	end
	shownHands = key
	local def = if weapon then Economy.findWeapon(weapon) else nil
	local bagDef = Transport.findKit(bagId() or Config.Courier.BagKit)
	local info: Inventory.HandInfo = {
		ownsBag = mine,
		bagName = if bagDef then bagDef.name else nil,
		pieces = pieces,
		room = room,
		down = down,
		carJob = carJob,
		gun = if def then def.name else nil,
		damage = if def then def.damage * math.max(1, def.pellets) else nil,
		bat = bat,
		keys = not touch,
	}
	for _, tile in hands do
		local hand = tile.hand :: string
		tile.can = Holding.can(hand, mine, def ~= nil, down)
		local image = nil
		if hand == "bag" then
			image = Icons.kit(bagId() or Config.Courier.BagKit)
		elseif hand == "gun" then
			image = if def then Icons.weapon(def.id) else nil
		end
		if tile.icon then
			tile.icon:Destroy()
		end
		tile.icon = Ui.icon(tile.button, image, if hand == "bag" and bagDef and mine then bagDef.icon else HAND_ICON[hand], UDim2.fromOffset(if hand == "bag" then 30 else 34, if hand == "bag" then 30 else 34), {
			Name = "Icon",
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			ImageColor3 = P.ink,
			TextTransparency = if tile.can then 0 else 0.55,
			ImageTransparency = if tile.can then 0 else 0.55,
			ZIndex = 4,
		})
		local name, sub = Inventory.handLine(hand, info)
		tile.line = { name, sub }
		if hand == "bag" then
			local share, text = Inventory.fill(pieces, room)
			local right, left = Inventory.ring(share)
			local ring = tile.ring
			ring.Right.Rotation = right
			ring.Left.Rotation = left
			ring.Frame.Visible = mine and not down
			setPill(tile, if not mine then "" elseif down then "DOWN" else text)
			tile.pill.BackgroundColor3 = if down then P.warn else BLUE
		end
		if hand == held then
			heldLine = tile.line
		end
		paint(tile, hand == held)
	end
	showLine()
	return true
end

-- ── The bar ────────────────────────────────────────────────────────────────

-- The bar's biggest size (unscaled; Hud's layout() fits that) and the smallest scale it may take (a touch screen: the
-- slots at least Config.Hotbar.TouchMin px).
function Hotbar.size(): (Vector2, number)
	local width, height = Inventory.size(HANDS + Hotbar.SLOTS, touch)
	return Vector2.new(width, height), Inventory.minScale(touch)
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
	shownHands = ""
	drawHands()
end

function Hotbar.setJob(newJob: any)
	job = newJob
	shownHands = ""
	drawHands()
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
	-- the line over the bar: what is in your hand (or the hovered slot) and its count
	local line = Ui.make("Frame", { Name = "Selected", Size = UDim2.new(1, 0, 0, H.Line), BackgroundTransparency = 1 }, root)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, line)
	lineName = P.text(line, "", UDim2.fromOffset(0, H.Line), { Name = "Name", AutomaticSize = Enum.AutomaticSize.X, Font = Theme.HeadingFont, TextSize = 15, TextColor3 = P.ink, LayoutOrder = 1 })
	lineSub = P.text(line, "", UDim2.fromOffset(0, H.Line), { Name = "Count", AutomaticSize = Enum.AutomaticSize.X, Font = Theme.HeadingFont, TextSize = 13, TextColor3 = P.ink2, LayoutOrder = 2 })
	-- the frosted tray at the bottom
	tray = Ui.make("Frame", {
		Name = "Tray",
		Size = UDim2.fromOffset(size.X, H.Tile + 2 * H.PadY),
		Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = TRAY,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	}, root)
	Ui.corner(tray, H.TrayCorner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = WHITE, Thickness = 1, Transparency = 0.94 }, tray)
	for index, hand in Holding.Order do
		hands[index] = buildHand(index, hand)
	end
	for index = 1, Hotbar.SLOTS do
		slots[index] = buildSlot(index)
	end
	player:GetAttributeChangedSignal("PackCount"):Connect(drawHands)
	player:GetAttributeChangedSignal("PackRoom"):Connect(drawHands)
	player:GetAttributeChangedSignal("BagRoom"):Connect(drawHands) -- 6.3
	shownLayout = ""
	drawItems()
	shownHands = ""
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
			if not hide then
				drawHands() -- 6.1 (only when what the hand slots show changed)
			end
		end
	end)
end

return Hotbar
