-- Logic test of the 4.2 touch layout (client/TouchLayout.luau) in the standalone Luau CLI: on phones (held sideways
-- and upright) and tablets FIRE, SPRINT, the hand button (PUNCH / EXIT / PUT DOWN) and DRAW are big enough for a
-- finger, stay on the screen, clear of each other, of Roblox's jump button and thumbstick, of the HUD's right column,
-- of the actions' row (and the ADMIN button's room) and of the contextual action at the bottom.
-- Run: python3 tests/run_tests.py [path to the luau binary] (it copies client/TouchLayout.luau next to this test).

local TouchLayout = require("./TouchLayout")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

type Box = TouchLayout.Box

-- client/Ui.luau Ui.scaleFor (1 at 1150 × 680, 0.55 .. 1.1).
local function scaleFor(W: number, H: number): number
	return math.clamp(math.min(W / 1150, H / 680), 0.55, 1.1)
end

local function show(b: Box): string
	return string.format("%d,%d-%d,%d", b.x0, b.y0, b.x1, b.y1)
end

local function inside(b: Box, W: number, H: number): boolean
	return b.x0 >= 0 and b.y0 >= 0 and b.x1 <= W and b.y1 <= H
end

-- The HUD's area (the screen under Roblox's top bar, inside a phone's notch): name, W, H.
local SCREENS: { { any } } = {
	{ "iPhone 14 sideways (notch insets, old top bar)", 750, 354 },
	{ "iPhone 14 sideways (notch insets, new top bar)", 750, 332 },
	{ "iPhone 14 sideways (no insets)", 844, 354 },
	{ "iPhone 14 Pro Max sideways", 838, 372 },
	{ "iPhone SE sideways", 667, 339 },
	{ "iPhone SE sideways (new top bar)", 667, 317 },
	{ "Android 20:9 sideways", 800, 324 },
	{ "small Android sideways", 640, 324 },
	{ "iPad mini sideways", 1133, 708 },
	{ "iPad sideways", 1180, 784 },
	{ "iPad Pro 12.9 sideways", 1366, 988 },
	{ "Android tablet sideways", 1024, 564 },
	{ "iPhone 14 upright", 390, 750 },
	{ "iPhone SE upright", 375, 611 },
	{ "iPad upright", 820, 1144 },
}

for _, screen in SCREENS do
	local name, W, H = screen[1] :: string, screen[2] :: number, screen[3] :: number
	local S = scaleFor(W, H)
	local c = TouchLayout.cluster(W, H, S)
	local buttons = TouchLayout.buttons(c)
	local names = { "FIRE", "SPRINT", "hand button", "DRAW" }

	-- A finger's size, on the screen, clear of Roblox's controls and of each other.
	for i, b in buttons do
		check(`{name}: {names[i]} at least 44 px each way`, b.x1 - b.x0 >= 44 and b.y1 - b.y0 >= 44, show(b))
		check(`{name}: {names[i]} on the screen`, inside(b, W, H), show(b))
		check(`{name}: {names[i]} clear of the jump button`, not TouchLayout.overlap(b, c.jump), `{show(b)} / {show(c.jump)}`)
		check(`{name}: {names[i]} clear of the thumbstick`, not TouchLayout.overlap(b, c.thumb), `{show(b)} / {show(c.thumb)}`)
		for j = i + 1, #buttons do
			check(`{name}: {names[i]} clear of {names[j]}`, not TouchLayout.overlap(b, buttons[j]), `{show(b)} / {show(buttons[j])}`)
		end
	end
	check(`{name}: SPRINT next to the jump button`, c.sprint.x1 <= c.jump.x0 and c.jump.x0 - c.sprint.x1 <= 24 and c.sprint.y1 == c.jump.y1)
	check(`{name}: FIRE over the jump button`, c.fire.y1 <= c.jump.y0)

	-- The actions' row (MAP CREW MENU) top right, without and with the ADMIN button over it (Studio, admins).
	local rowScale = math.max(S, 0.8)
	local rowW, rowH = 210 * rowScale, 44 * rowScale
	for _, admin in { false, true } do
		local rowTop = if admin then 96 else 16
		local row = TouchLayout.box(W - 16 - rowW, rowTop, W - 16, rowTop + rowH)
		local rowBottom = row.y1
		if admin then
			rowBottom = math.max(rowBottom, 88) -- the ADMIN button itself: 56 .. 88
		end
		local tag = if admin then " (ADMIN)" else ""
		-- The tiniest phones (≤ 320 px under the top bar) are allowed to touch the row only with ADMIN showing.
		if not admin or H >= 320 then
			for i, b in buttons do
				check(`{name}{tag}: {names[i]} clear of the actions' row`, not TouchLayout.overlap(b, row), `{show(b)} / {show(row)}`)
			end
		end

		-- The right column (the weapon, the vehicle, the items: 300 × 190 at scale S).
		local colW, colH = 300 * S, 190 * S
		local column, over = TouchLayout.column(c, W, H, colW, colH, rowBottom)
		check(`{name}{tag}: the column on the screen`, inside(column, W, H), show(column))
		check(`{name}{tag}: the column clear of the jump button`, not TouchLayout.overlap(column, c.jump))
		for i, b in buttons do
			check(`{name}{tag}: the column clear of {names[i]}`, not TouchLayout.overlap(column, b), `{show(column)} / {show(b)}`)
		end
		if W > H then
			check(`{name}{tag}: the column clear of the thumbstick`, not TouchLayout.overlap(column, c.thumb), `{show(column)} / {show(c.thumb)}`)
		end
		if over then
			check(`{name}{tag}: the column over the buttons stays under the row`, column.y0 >= rowBottom + 8 and not TouchLayout.overlap(column, row))
		end

		-- The contextual action at the bottom (TouchLayout.hint, as Hud's layout places it; 96·S reserved over it).
		local boxes = table.clone(buttons)
		table.insert(boxes, column)
		local hintX, hintBottom, hintW = TouchLayout.hint(c, boxes, W, H, S)
		local hint = TouchLayout.box(hintX - hintW / 2, hintBottom - 96 * S, hintX + hintW / 2, hintBottom)
		check(`{name}{tag}: the contextual action on the screen`, inside(hint, W, H), show(hint))
		check(`{name}{tag}: the contextual action 120 px or wider`, hintW >= 120, hintW)
		if W > H and W >= 740 then
			check(`{name}{tag}: the contextual action 160 px or wider`, hintW >= 160, hintW)
		end
		check(`{name}{tag}: the contextual action clear of the thumbstick`, not TouchLayout.overlap(hint, c.thumb), `{show(hint)} / {show(c.thumb)}`)
		for i, b in buttons do
			check(`{name}{tag}: the contextual action clear of {names[i]}`, not TouchLayout.overlap(hint, b), `{show(hint)} / {show(b)}`)
		end
		check(`{name}{tag}: the contextual action clear of the column`, not TouchLayout.overlap(hint, column), `{show(hint)} / {show(column)}`)
		check(`{name}{tag}: the contextual action clear of the jump button`, not TouchLayout.overlap(hint, c.jump), `{show(hint)} / {show(c.jump)}`)

		-- 6.0.1, the bottom bar (client/Hotbar.luau: 5 item slots of 56 over the carried strip, 304 × 100 unscaled; a
		-- slot at least 48 px on a touch screen) with the right column (now 158 tall: the items left it) and the action.
		-- 6.1: the three hand slots, a divider and two item slots over the strip: 311 × 100 (wider fails the iPhone SE).
		local barScale = math.max(S, 48 / 56)
		local rowLeft = if admin then math.min(row.x0, W - 16 - 90) else row.x0
		local col2, over2, bar = TouchLayout.dock(c, W, H, 300 * S, 158 * S, rowBottom, rowLeft, 311 * barScale, 100 * barScale)
		check(`{name}{tag}: the bar's slots 48 px or bigger`, 56 * barScale >= 48)
		check(`{name}{tag}: the bar on the screen`, inside(bar, W, H), show(bar))
		check(`{name}{tag}: the bar clear of the thumbstick`, not TouchLayout.overlap(bar, c.thumb), `{show(bar)} / {show(c.thumb)}`)
		check(`{name}{tag}: the bar clear of the jump button`, not TouchLayout.overlap(bar, c.jump), `{show(bar)} / {show(c.jump)}`)
		check(`{name}{tag}: the bar clear of the column`, not TouchLayout.overlap(bar, col2), `{show(bar)} / {show(col2)}`)
		check(`{name}{tag}: the bar clear of the actions' row`, bar.y0 >= rowBottom or not TouchLayout.overlap(bar, row), `{show(bar)} / {show(row)}`)
		check(`{name}{tag}: the docked column on the screen`, inside(col2, W, H), show(col2))
		check(`{name}{tag}: the docked column clear of the actions' row`, over2 or col2.y0 >= rowBottom or col2.x1 <= rowLeft, `{show(col2)} / {show(row)}`)
		for i, b in buttons do
			check(`{name}{tag}: the bar clear of {names[i]}`, not TouchLayout.overlap(bar, b), `{show(bar)} / {show(b)}`)
			check(`{name}{tag}: the docked column clear of {names[i]}`, not TouchLayout.overlap(col2, b), `{show(col2)} / {show(b)}`)
		end
		if W > H then
			check(`{name}{tag}: the bar at the bottom`, bar.y1 >= H - 8 - 0.01, show(bar))
			check(`{name}{tag}: the docked column clear of the thumbstick`, not TouchLayout.overlap(col2, c.thumb), `{show(col2)} / {show(c.thumb)}`)
		end
		local boxes2 = table.clone(buttons)
		table.insert(boxes2, col2)
		local hx, hb, hw = TouchLayout.hint(c, boxes2, W, H, S, bar.y0)
		local hint2 = TouchLayout.box(hx - hw / 2, hb - 96 * S, hx + hw / 2, hb)
		check(`{name}{tag}: the action over the bar on the screen`, inside(hint2, W, H), show(hint2))
		check(`{name}{tag}: the action clear of the bar`, not TouchLayout.overlap(hint2, bar), `{show(hint2)} / {show(bar)}`)
		check(`{name}{tag}: the action clear of the docked column`, not TouchLayout.overlap(hint2, col2), `{show(hint2)} / {show(col2)}`)
		check(`{name}{tag}: the action (with the bar) clear of the thumbstick`, not TouchLayout.overlap(hint2, c.thumb), `{show(hint2)} / {show(c.thumb)}`)
		for i, b in buttons do
			check(`{name}{tag}: the action (with the bar) clear of {names[i]}`, not TouchLayout.overlap(hint2, b), `{show(hint2)} / {show(b)}`)
		end
	end
end

-- The small helpers.
local a = TouchLayout.box(0, 0, 10, 10)
check("overlap: shared area", TouchLayout.overlap(a, TouchLayout.box(5, 5, 15, 15)))
check("overlap: touching edges do not count", not TouchLayout.overlap(a, TouchLayout.box(10, 0, 20, 10)))
check("overlap: apart", not TouchLayout.overlap(a, TouchLayout.box(30, 30, 40, 40)))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
