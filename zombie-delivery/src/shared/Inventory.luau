--!strict
-- 6.21, the inventory as a clean hotbar (the owner picked redesign B, "Clean hotbar + kit"): the pure part, no Roblox
-- (tests/inventory_test.luau). client/Hotbar.luau draws the bottom bar with it, client/BagUi.luau BAG & ITEMS.
--
--   Inventory.category(kind, id)        "weapon" | "medical" | "explosive" | "cargo" | "gear": a gun or the bat is a
--                                       weapon, a consumable by Config.Inventory.Items (else gear), cargo and the bags
--                                       cargo (blue), a vest gear
--   Inventory.rgb(category)             its colour { r, g, b } (Config.Inventory.Colors)
--   Inventory.stack(pieces, max)        6.19's grouping: one entry a kind of piece ({ look, count }) in the order they
--                                       first come, at most `max` kinds; returns them and how many pieces did not fit
--   Inventory.fill(pieces, room)        the bag slot's ring and pill: the share filled (0 .. 1) and "5/6"
--   Inventory.ring(share)               the ring's two halves' gradient turns (degrees, clockwise from the top): the
--                                       right half shows 0 .. 50 %, the left half 50 .. 100 %
--   Inventory.size(slots, touch)        the bar's size (unscaled px) with `slots` slots in its tray: its width and its
--                                       height (the line over it, the lifted slot, the tray); a touch screen's slots
--                                       closer (Config.Hotbar TouchGap / TouchPad: the 640 px phone)
--   Inventory.minScale(touch)           the least scale of the bar: a touch screen's slot at least Config.Hotbar.TouchMin
--   Inventory.slotX(index, touch)       a slot's centre in the tray (px from its left edge)
--   Inventory.shown(owned, slots, touch)  how many item slots show: every slot on a computer (the empty ones dim), only
--                                       the filled ones on a touch screen
--   Inventory.handLine(hand, info)      the line over the bar for what is in your hand: its name and one short count

local Config = require(script.Parent.Config)

local Inventory = {}

local H = Config.Hotbar
local INV = Config.Inventory

function Inventory.category(kind: string, id: string?): string
	if kind == "weapon" or kind == "melee" then
		return "weapon"
	elseif kind == "item" then
		return (id and INV.Items[id]) or "gear"
	elseif kind == "cargo" or kind == "bag" then
		return "cargo"
	end
	return "gear"
end

function Inventory.rgb(category: string): { number }
	return INV.Colors[category] or INV.Colors.gear
end

export type Group = { look: string, count: number }

function Inventory.stack(pieces: { any }?, max: number): ({ Group }, number)
	local out: { Group } = {}
	local at: { [string]: Group } = {}
	local hidden = 0
	if type(pieces) ~= "table" then
		return out, 0
	end
	for _, piece in pieces do
		if type(piece) ~= "table" then
			continue
		end
		local look = if type(piece.look) == "string" then piece.look else "parcel"
		local group = at[look]
		if group then
			group.count += 1
		elseif #out < max then
			local made: Group = { look = look, count = 1 }
			at[look] = made
			table.insert(out, made)
		else
			hidden += 1
		end
	end
	return out, hidden
end

function Inventory.fill(pieces: number, room: number): (number, string)
	local have = math.max(0, math.floor(pieces))
	local total = math.max(0, math.floor(room))
	local share = if total > 0 then math.min(1, have / total) else (if have > 0 then 1 else 0)
	return share, `{have}/{total}`
end

-- The ring is two half rings, each clipped to its half of the slot, each with a hard-edged gradient on its stroke
-- (opaque on one side of a line through the centre). Turning the gradient sweeps the line: 0° shows none of the right
-- half, 90° its top quarter, 180° all of it; the left half from 180° (none) to 360° (all).
function Inventory.ring(share: number): (number, number)
	local s = math.clamp(share, 0, 1)
	return math.min(s, 0.5) * 360, math.max(s, 0.5) * 360
end

-- The gap between two slots and the tray's side padding (a touch screen's are tighter: the 640 px phone).
local function spacing(touch: boolean?): (number, number)
	if touch then
		return H.TouchGap, H.TouchPad
	end
	return H.Gap, H.PadX
end

function Inventory.size(slots: number, touch: boolean?): (number, number)
	local n = math.max(1, slots)
	local gap, pad = spacing(touch)
	local width = 2 * pad + n * H.Tile + (n - 1) * gap
	local tray = H.Tile + 2 * H.PadY
	local rise = math.max(0, H.Lift + (H.Selected - H.Tile) - H.PadY) -- (the lifted slot over the tray's top edge)
	return width, H.Line + H.LineGap + rise + tray
end

function Inventory.minScale(touch: boolean): number
	return if touch then H.TouchMin / H.Tile else 0
end

function Inventory.slotX(index: number, touch: boolean?): number
	local gap, pad = spacing(touch)
	return pad + (index - 1) * (H.Tile + gap) + H.Tile / 2
end

function Inventory.shown(owned: number, slots: number, touch: boolean): number
	return if touch then math.clamp(owned, 0, slots) else slots
end

export type HandInfo = {
	ownsBag: boolean,
	bagName: string?,
	pieces: number,
	room: number,
	down: boolean,
	carJob: boolean,
	gun: string?, -- the equipped gun's name
	damage: number?, -- its damage a shot (Config.Weapons damage × pellets)
	bat: boolean,
	keys: boolean,
}

function Inventory.handLine(hand: string, info: HandInfo): (string, string)
	if hand == "bag" then
		local name = string.upper(info.bagName or "Bag")
		if not info.ownsBag then
			return "NO BAG", Config.BagShop.BuyHint -- 6.23: bags are bought for each game ("BUY A BAG")
		elseif info.down then
			return name, "ON THE GROUND"
		elseif info.carJob then
			return name, "HANDS ONLY ON THIS JOB"
		end
		return name, `{math.floor(info.pieces)} / {math.floor(info.room)}`
	elseif hand == "gun" then
		if not info.gun then
			return "NO GUN", ""
		end
		return string.upper(info.gun), if info.damage then `{math.floor(info.damage + 0.5)} DMG` else ""
	end
	return "FISTS", if info.bat then (if info.keys then "V SWINGS THE BAT" else "THE BAT SWINGS") else (if info.keys then "V PUNCHES" else "")
end

return Inventory
