--!strict
-- 6.0.1, the bottom bar (the owner's wish: "a place at the bottom for 5 things in the inventory"), bottom centre in the
-- HUD's ScreenGui (client/Hud.luau's layout() places and scales it: Hotbar.size, Hotbar.place). Two parts:
--   * Five square item slots: the consumables you own (Config.Items, in the hotbar's order: the first five you have),
--     each with its icon (shared/Icons.luau, the emoji without one), the count and its key 1-5 in the corner; an empty
--     slot is a dim outline. A key (Hud's keys call Hotbar.useSlot), a click or a tap uses it through Hud's use path
--     (Hotbar.onUse: Hud's useItem, the UseItem remote): a short flash and the red outline on the slot, then a shade
--     while the server's cooldown runs (Config.ItemTuning.UseCooldown, one for every item). A sixth kind you own has
--     no slot: key 6 uses it (and the I window does).
--   * After a thin divider, what you carry (shared/Bag.luau Bag.places / Bag.strip): one small tile a piece, its cargo
--     icon (Icons.cargo, client/BagUi.luau's emoji) and a badge for where it is (✋ hands, 🛍 the plastic bag, 🎒 the
--     backpack, 🚲 the rack), greyed when it belongs to another order than the one in focus; the free room as dim
--     tiles, "+N" over 8 tiles (7 on a touch screen). From the job payload's `carried` and the PackCount / PackRoom
--     attributes; off duty your room. A click opens the I window's BAG tab (BagUi.open).
-- A computer: one row, a small CARRYING n/room over the tiles. A touch screen: the tiles over the slots, the slots at
-- least 48 px, no keys. It hides with the HUD (it lives in its ScreenGui) and while a window, the phone or a dialog
-- covers the game (Hotbar.covered, set by the client's Main; checked 10 times a second). Drawn again only when what it
-- shows changed (a State, a job update, the pack attributes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local Bag = require(Shared.Bag)
local Transport = require(Shared.Transport)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local BagUi = require(script.Parent.BagUi)

local Hotbar = {}

Hotbar.SLOTS = 5
-- Set by client/Hud.luau: uses an item (its existing path: the count check, the UseItem remote with the aim point).
Hotbar.onUse = nil :: ((id: string) -> ())?
-- Set by client/Hud.luau: a toast (an empty slot's key).
Hotbar.toast = nil :: ((text: string) -> ())?
-- Set by client/Main.client.luau: does a window, the phone or a dialog cover the game now (the bar hides)?
Hotbar.covered = nil :: (() -> boolean)?

local SLOT, SLOT_GAP = 56, 6 -- the item slots (unscaled)
local TILE, TILE_GAP = 38, 4 -- the carried tiles
local LABEL_H = 14 -- CARRYING n/room over the tiles (a computer)
local DIVIDER = 25 -- the room of the divider between the two parts (12 · the line · 12)
local TOUCH_MIN = 48 -- px: the smallest slot on a touch screen
local ITEMS_W = Hotbar.SLOTS * SLOT + (Hotbar.SLOTS - 1) * SLOT_GAP
local BADGE: { [string]: string } = { hands = "✋", bag = "🛍", pack = "🎒", rack = "🚲" }
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
}

local player = Players.LocalPlayer
local touch = Ui.touchLayout()
local maxTiles = if touch then 7 else 8
local root: any = nil
local rootScale: any = nil
local strip: any = nil
local stripLabel: any = nil
local tilesRow: any = nil
local slots: { Slot } = {}
local owned: { string } = {} -- the item ids you have, in Config.Items order (slot n = owned[n])
local state: any = nil
local job: any = nil
local shownStrip = ""
local carrying = 0 -- the pieces the strip shows (its label's colour)

local function stripWidth(tiles: number): number
	return math.max(0, tiles * TILE + (tiles - 1) * TILE_GAP)
end

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
	local filled = slot.id ~= nil
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

local function use(index: number)
	local id = owned[index]
	if not id then
		local say = Hotbar.toast
		if say and index <= Hotbar.SLOTS then
			say(`Slot {index} is empty: Last Stop Supplies sells medkits, repair kits, nitro and more.`)
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
		key = P.caps(button, tostring(index), UDim2.fromOffset(14, 14), { Position = UDim2.fromOffset(5, 3), TextSize = 11, TextStrokeTransparency = 1, ZIndex = 5, Visible = not touch }),
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
local function drawItems()
	table.clear(owned)
	local items = if state and type(state.items) == "table" then state.items else {}
	for _, def in Config.Items do
		if (tonumber(items[def.id]) or 0) > 0 then
			table.insert(owned, def.id)
		end
	end
	for index, slot in slots do
		local id = owned[index]
		if id ~= slot.id then
			if slot.icon then
				slot.icon:Destroy()
				slot.icon = nil
			end
			slot.id = id
			local def = if id then itemDef(id) else nil
			if id and def then
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
		local text = if id then tostring(math.floor(tonumber(items[id]) or 0)) else ""
		if slot.count.Text ~= text then
			slot.count.Text = text
		end
	end
end

-- ── What you carry ─────────────────────────────────────────────────────────

-- Your room by place: the job's (the payload, the live PackRoom attribute), off duty your kit's on foot.
local function placesNow(): { Bag.Place }
	local kit = if state and type(state.kit) == "table" then state.kit else {}
	local bagRoom = math.max(0, Transport.handsRoom(kit) - Transport.backpackRoom(kit))
	if job then
		local mode = if type(job.mode) == "string" then job.mode else "car"
		local packRoom = tonumber(player:GetAttribute("PackRoom")) or tonumber(job.packRoom) or 0
		return Bag.places(mode, packRoom, tonumber(job.rack) or 0, bagRoom)
	end
	return Bag.places("foot", Transport.packRoom(kit), 0, bagRoom)
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
				if piece.where == "pack" or piece.where == "rack" then
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

-- One tile: a piece (its icon and where it is), a free place (dim, its badge faint) or "+N" (`more`).
local function tile(t: Bag.Tile?, order: number, more: string?, moreDim: boolean?)
	local piece = if t then t.piece else nil
	local other = t ~= nil and t.other
	local frame = Ui.make("Frame", {
		Name = "Tile",
		Size = UDim2.fromOffset(TILE, TILE),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = if piece or (more and not moreDim) then 0.3 else 0.72,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, tilesRow)
	Ui.make("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = P.line,
		Thickness = 1,
		Transparency = if piece and not other then 0.35 else 0.72,
	}, frame)
	if more then
		P.text(frame, more, UDim2.fromScale(1, 1), {
			Font = Theme.HeadingFont,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = if moreDim then 0.5 else 0,
		})
		return
	end
	if piece then
		local look = if type(piece.look) == "string" then piece.look else nil
		Ui.icon(frame, Icons.cargo(look), BagUi.emoji(look), UDim2.fromOffset(22, 22), {
			Position = UDim2.new(0.5, 0, 0.5, -3),
			AnchorPoint = Vector2.new(0.5, 0.5),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = if other then 0.6 else 0,
			ImageColor3 = if other then P.ink2 else P.ink,
			ImageTransparency = if other then 0.6 else 0,
		})
	end
	Ui.label(frame, BADGE[if t then t.where else "pack"] or "🎒", UDim2.fromOffset(14, 14), {
		Position = UDim2.new(1, 0, 1, 0),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTransparency = if piece and not other then 0 else 0.6,
		ZIndex = 2,
	})
end

local function drawStrip()
	if not root then
		return
	end
	local places = placesNow()
	local carried = carriedNow()
	local focus = if job and type(job.focus) == "number" then job.focus else nil
	local tiles, more, morePieces = Bag.strip(carried, places, focus, maxTiles)
	local pieces, room = morePieces, 0
	for _, place in places do
		room += place.room
	end
	local parts: { string } = {}
	for _, t in tiles do
		local piece = t.piece
		if piece then
			pieces += 1
		end
		table.insert(parts, `{t.where}:{if piece then tostring(piece.look) else "-"}:{t.other}`)
	end
	carrying = pieces
	local label = `CARRYING {pieces}/{room}`
	local key = `{table.concat(parts, ",")}|{more}|{morePieces}|{label}`
	if key == shownStrip then
		return
	end
	shownStrip = key
	Ui.clear(tilesRow)
	for index, t in tiles do
		tile(t, index)
	end
	local count = #tiles
	if more > 0 then
		count += 1
		tile(nil, count, `+{more}`, morePieces == 0)
	end
	local width = stripWidth(count)
	if touch then
		strip.Size = UDim2.fromOffset(width, TILE)
	else
		strip.Size = UDim2.fromOffset(math.max(width, 90), SLOT)
		root.Size = UDim2.fromOffset(ITEMS_W + DIVIDER + math.max(width, 90), SLOT)
		stripLabel.Text = label
		stripLabel.TextColor3 = if pieces > 0 then P.ink else P.ink2
	end
end

-- ── The bar ────────────────────────────────────────────────────────────────

-- The bar's biggest size (unscaled; Hud's layout() fits that) and the smallest scale it may take (a touch screen: the
-- slots at least TOUCH_MIN px).
function Hotbar.size(): (Vector2, number)
	if touch then
		return Vector2.new(ITEMS_W, SLOT + SLOT_GAP + TILE), TOUCH_MIN / SLOT
	end
	return Vector2.new(ITEMS_W + DIVIDER + stripWidth(maxTiles), SLOT), 0
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

-- Key 1-6 (Hud's keys): the item in that place of the ones you own.
function Hotbar.useSlot(index: number)
	use(index)
end

-- The key of an item you own (its place in the bar; 6 for a sixth kind), nil when you have none.
function Hotbar.slotOf(id: string): number?
	return table.find(owned, id)
end

function Hotbar.setState(newState: any)
	state = newState
	drawItems() -- (before start: the list of what you own only, for Hotbar.slotOf)
	drawStrip()
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
	local items = Ui.make("Frame", {
		Name = "Items",
		Size = UDim2.fromOffset(ITEMS_W, SLOT),
		Position = if touch then UDim2.fromOffset(0, TILE + SLOT_GAP) else UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
	}, root)
	for index = 1, Hotbar.SLOTS do
		slots[index] = buildSlot(items, index)
	end
	-- What you carry: one button (a click opens the BAG tab), the tiles in a row.
	strip = Ui.make("TextButton", {
		Name = "Carried",
		Size = UDim2.fromOffset(stripWidth(maxTiles), if touch then TILE else SLOT),
		Position = if touch then UDim2.fromScale(0.5, 0) else UDim2.fromOffset(ITEMS_W + DIVIDER, 0),
		AnchorPoint = if touch then Vector2.new(0.5, 0) else Vector2.zero,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
	}, root)
	tilesRow = Ui.make("Frame", {
		Name = "Tiles",
		Size = UDim2.new(1, 0, 0, TILE),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
	}, strip)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = if touch then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, TILE_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, tilesRow)
	if not touch then
		P.rule(root, UDim2.fromOffset(1, 40), { Position = UDim2.fromOffset(ITEMS_W + 12, SLOT - 40) })
		stripLabel = P.caps(strip, "CARRYING", UDim2.new(1, 0, 0, LABEL_H), { TextSize = 10, TextStrokeTransparency = 1 })
	end
	strip.MouseEnter:Connect(function()
		if stripLabel then
			stripLabel.TextColor3 = P.ink
		end
	end)
	strip.MouseLeave:Connect(function()
		if stripLabel then
			stripLabel.TextColor3 = if carrying > 0 then P.ink else P.ink2
		end
	end)
	strip.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		BagUi.open()
	end)
	player:GetAttributeChangedSignal("PackCount"):Connect(drawStrip)
	player:GetAttributeChangedSignal("PackRoom"):Connect(drawStrip)
	drawItems()
	drawStrip()
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
		end
	end)
end

return Hotbar
