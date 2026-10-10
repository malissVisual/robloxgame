-- Logic test of 6.21's clean hotbar (shared/Inventory.luau, Config.Hotbar, Config.Inventory) in the standalone Luau
-- CLI: the kinds' colours, 6.19's cargo grouping, the bag slot's fill and ring, the bar's size (a computer's eight
-- slots, a touch screen's five at 48 px or more), the slots' places, the touch screen's filled slots only and the line
-- over the bar.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Inventory = require("./Inventory")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function same(a: { number }, b: { number }): boolean
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local H = Config.Hotbar
local INV = Config.Inventory

-- The kinds and their colours (the mock's: weapons red, medical green, explosives orange, cargo blue, gear grey).
check("a gun is a weapon (red)", Inventory.category("weapon", "pistol") == "weapon" and same(Inventory.rgb("weapon"), { 215, 74, 70 }))
check("the bat is a weapon too", Inventory.category("melee", "bat") == "weapon")
check("a medkit and the energy drink are medical (green)", Inventory.category("item", "medkit") == "medical" and Inventory.category("item", "energy") == "medical" and same(Inventory.rgb("medical"), { 126, 196, 120 }))
check("a molotov and a landmine are explosives (orange)", Inventory.category("item", "molotov") == "explosive" and Inventory.category("item", "mine") == "explosive" and same(Inventory.rgb("explosive"), { 240, 138, 58 }))
check("cargo and the bags are blue", Inventory.category("cargo", "pizza") == "cargo" and Inventory.category("bag", "tote") == "cargo" and same(Inventory.rgb("cargo"), { 90, 162, 230 }))
check("a vest is gear (grey)", Inventory.category("kit", "kevlar") == "gear" and same(Inventory.rgb("gear"), { 154, 163, 174 }))
check("an unknown item is gear", Inventory.category("item", "nothing") == "gear" and same(Inventory.rgb("nothing"), Inventory.rgb("gear")))
for _, def in Config.Items do
	check(`{def.id} has a kind in Config.Inventory.Items`, INV.Items[def.id] ~= nil and INV.Colors[INV.Items[def.id]] ~= nil)
end
for kind, rgb in INV.Colors do
	check(`{kind}'s colour is RGB`, #rgb == 3 and rgb[1] >= 0 and rgb[1] <= 255 and rgb[2] >= 0 and rgb[2] <= 255 and rgb[3] >= 0 and rgb[3] <= 255)
end

-- 6.19's grouping: one entry a kind, in the order they first come, ×n; past `max` kinds the pieces are hidden.
do
	local pieces = { { look = "pizza" }, { look = "pizza" }, { look = "parcel" }, { look = "bouquet" }, { look = "cake" }, { look = "pizza" } }
	local groups, hidden = Inventory.stack(pieces, 6)
	check("the stack groups the kinds (🍕 ×3, 📦, 💐, 🎂)", #groups == 4 and groups[1].look == "pizza" and groups[1].count == 3 and groups[2].look == "parcel" and groups[4].look == "cake" and hidden == 0)
	local few, rest = Inventory.stack(pieces, 2)
	check("past its kinds the stack hides the pieces", #few == 2 and few[1].count == 3 and rest == 2, rest)
	local none, zero = Inventory.stack(nil, 6)
	check("nothing carried: an empty stack", #none == 0 and zero == 0)
	local anyLook = Inventory.stack({ { where = "pack" } }, 6)
	check("a piece without a look (the satchel's) is a parcel", #anyLook == 1 and anyLook[1].look == "parcel")
end

-- The bag slot's fill: the ring's share and the pill's "5/6".
do
	local share, text = Inventory.fill(5, 6)
	check("5 of 6: the ring 5/6 full, the pill 5/6", math.abs(share - 5 / 6) < 1e-9 and text == "5/6", text)
	local full = Inventory.fill(8, 6)
	check("more than the room: the ring full", full == 1)
	local empty, words = Inventory.fill(0, 0)
	check("no room, nothing: an empty ring, 0/0", empty == 0 and words == "0/0")
	check("Strong Back's room counts (5 of 7)", select(2, Inventory.fill(5, 7)) == "5/7")
end

-- The ring's two halves: 0 % none, 25 % the right half's top quarter, 50 % the right half, 75 % and the left's bottom
-- quarter, 100 % both.
do
	local r0, l0 = Inventory.ring(0)
	local r1, l1 = Inventory.ring(0.25)
	local r2, l2 = Inventory.ring(0.5)
	local r3, l3 = Inventory.ring(0.75)
	local r4, l4 = Inventory.ring(1)
	check("the ring at 0 %", r0 == 0 and l0 == 180)
	check("the ring at 25 %", r1 == 90 and l1 == 180)
	check("the ring at 50 %", r2 == 180 and l2 == 180)
	check("the ring at 75 %", r3 == 180 and l3 == 270)
	check("the ring at 100 %", r4 == 180 and l4 == 360)
	local rOver, lOver = Inventory.ring(2)
	check("the ring never over 100 %", rOver == 180 and lOver == 360)
end

-- The bar's size: a computer's 3 hands + 5 items; a touch screen's 3 + 2 at 48 px a slot.
do
	local w8, h8 = Inventory.size(3 + Config.ItemTuning.BarSlots)
	check("eight 72 px slots, 10 apart, 14 padding: 682 wide", w8 == 2 * 14 + 8 * 72 + 7 * 10, w8)
	check("the bar's height: the line, the lifted slot's rise, the tray", h8 == H.Line + H.LineGap + (H.Lift + H.Selected - H.Tile - H.PadY) + H.Tile + 2 * H.PadY, h8)
	local w5 = Inventory.size(5, true)
	check("a touch screen's slots closer", w5 == 2 * H.TouchPad + 5 * H.Tile + 4 * H.TouchGap and w5 < Inventory.size(5), w5)
	local scale = Inventory.minScale(true)
	check("a touch screen's slot at least 48 px", H.Tile * scale >= 48 - 1e-9, H.Tile * scale)
	check("a touch screen's bar about two thirds (the mock's 62 % kept above 48 px slots)", scale > 0.6 and scale < 0.7, scale)
	check("a touch screen's bar 300 px wide at most (the iPhone SE)", w5 * scale <= 300, w5 * scale)
	check("a computer has no least scale", Inventory.minScale(false) == 0)
	check("the selected slot lifts 12 px and grows to 80", H.Lift == 12 and H.Selected == 80 and H.Tile == 72)
end

-- The slots' places in the tray: centred in their columns, the selected slot's growth inside the gaps.
do
	check("the first slot's centre", Inventory.slotX(1) == H.PadX + H.Tile / 2)
	check("one slot to the next", Inventory.slotX(2) - Inventory.slotX(1) == H.Tile + H.Gap)
	local w = Inventory.size(8)
	check("the last slot ends at the padding", Inventory.slotX(8) + H.Tile / 2 + H.PadX == w)
	check("the grown slot stays in its gaps", (H.Selected - H.Tile) / 2 <= math.min(H.Gap, H.PadX, H.TouchGap, H.TouchPad))
	check("a touch screen's slots: the same rule", Inventory.slotX(5, true) + H.Tile / 2 + H.TouchPad == Inventory.size(5, true) and Inventory.slotX(2, true) - Inventory.slotX(1, true) == H.Tile + H.TouchGap)
end

-- Which item slots show: every slot on a computer, the filled ones only on a touch screen.
check("a computer shows its five item slots", Inventory.shown(2, 5, false) == 5)
check("a touch screen shows the filled ones only", Inventory.shown(1, 2, true) == 1 and Inventory.shown(0, 2, true) == 0 and Inventory.shown(4, 2, true) == 2)

-- The line over the bar for what is in your hand.
do
	local info = { ownsBag = true, bagName = "Canvas Tote", pieces = 5, room = 6, down = false, carJob = false, gun = "Pistol", damage = 18, bat = false, keys = true }
	local name, sub = Inventory.handLine("bag", info)
	check("the bag: its name and 5 / 6", name == "CANVAS TOTE" and sub == "5 / 6", sub)
	name, sub = Inventory.handLine("gun", info)
	check("the gun: its name and its damage (no ammo: the game has none)", name == "PISTOL" and sub == "18 DMG", sub)
	name, sub = Inventory.handLine("fists", info)
	check("the fists: V punches", name == "FISTS" and sub == "V PUNCHES")
	info.bat = true
	check("the fists with the bat", select(2, Inventory.handLine("fists", info)) == "V SWINGS THE BAT")
	info.down = true
	check("the bag on the ground", select(2, Inventory.handLine("bag", info)) == "ON THE GROUND")
	info.down, info.carJob = false, true
	check("a car job: hands only", select(2, Inventory.handLine("bag", info)) == "HANDS ONLY ON THIS JOB")
	info.ownsBag = false
	check("no bag (6.23: this game: BUY A BAG)", Inventory.handLine("bag", info) == "NO BAG" and select(2, Inventory.handLine("bag", info)) == "BUY A BAG")
	info.gun = nil
	check("no gun", Inventory.handLine("gun", info) == "NO GUN")
	info.keys = false
	check("a touch screen names no keys", select(2, Inventory.handLine("fists", info)) == "THE BAT SWINGS")
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
