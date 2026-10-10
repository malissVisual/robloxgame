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
	{ "small Android sideways (new top bar)", 640, 316 }, -- 6.13.1: a 640 x 360 phone, the smallest the game is tested on
	{ "old 16:9 phone sideways (new top bar)", 712, 316 },
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

		-- 6.14, the grind chips (client/GrindChips.luau: ON A ROLL and SHIFT 3/5, side by side or stacked) at the top,
		-- clear of the left column (cash, minimap, health: 200 × 258) and the contract column as Hud's layout puts it
		-- (beside the left column up to the row and ADMIN, 380 wide at most; upright: under them, across), the row,
		-- ADMIN, the buttons, the docked column and the bar. Big enough to read: CHIPS_TOUCH on a sideways phone 700 px
		-- or wider (its 16 px title at 12.8 px), never under CHIPS_MIN (9.6 px: still over the HUD's 8.8 px cash line).
		local leftCol = TouchLayout.box(16, 16, 16 + 200 * S, 16 + 258 * S)
		local topX = leftCol.x1 + 8
		local limit = math.min(row.x0 - 8, if admin then W - 16 - 90 - 8 else W - 16)
		local width = math.clamp((limit - topX) / S, 300, 380)
		local topScale = math.min(S, (limit - topX) / width)
		local contract = TouchLayout.box(topX, 16, topX + width * topScale, 16 + 200 * topScale)
		if topScale < S * 0.8 then
			contract = TouchLayout.box(16, math.max(leftCol.y1, rowBottom) + 8, W - 16, H - 8)
		end
		local chipScale = math.max(S, TouchLayout.CHIPS_TOUCH)
		local leftEdge = leftCol.x1
		if contract.y0 < 16 + TouchLayout.CHIPS_STACKED.h * chipScale then
			leftEdge = math.max(leftEdge, contract.x1)
		end
		local blocks: { Box } = table.clone(buttons)
		for _, b in { c.thumb, c.jump, col2, bar, leftCol, contract, row } do
			table.insert(blocks, b)
		end
		local adminBox = TouchLayout.box(W - 16 - 90, 56, W - 16, 88)
		if admin then
			table.insert(blocks, adminBox)
		end
		local chips, scale = TouchLayout.chips(W, H, TouchLayout.CHIPS_WIDE, TouchLayout.CHIPS_STACKED, chipScale, leftEdge, 16, rowLeft, rowBottom, blocks)
		check(`{name}{tag}: the chips on the screen`, inside(chips, W, H), show(chips))
		check(`{name}{tag}: the chips clear of the actions' row`, not TouchLayout.overlap(chips, row), `{show(chips)} / {show(row)}`)
		check(`{name}{tag}: the chips clear of the left column`, not TouchLayout.overlap(chips, leftCol), `{show(chips)} / {show(leftCol)}`)
		check(`{name}{tag}: the chips clear of the contract column`, not TouchLayout.overlap(chips, contract), `{show(chips)} / {show(contract)}`)
		check(`{name}{tag}: the chips clear of the thumbstick, the jump button, the column and the bar`, not (TouchLayout.overlap(chips, c.thumb) or TouchLayout.overlap(chips, c.jump) or TouchLayout.overlap(chips, col2) or TouchLayout.overlap(chips, bar)), show(chips))
		if admin then
			check(`{name}{tag}: the chips clear of ADMIN`, not TouchLayout.overlap(chips, adminBox), show(chips))
		end
		for i, b in buttons do
			check(`{name}{tag}: the chips clear of {names[i]}`, not TouchLayout.overlap(chips, b), `{show(chips)} / {show(b)}`)
		end
		check(`{name}{tag}: the chips at CHIPS_MIN or bigger`, scale >= TouchLayout.CHIPS_MIN - 1e-9, scale)
		if W > H and W >= 700 and not admin then
			check(`{name}: the chips big enough to read ({math.floor(16 * scale * 10 + 0.5) / 10} px title)`, scale >= TouchLayout.CHIPS_TOUCH - 1e-9, scale)
		end

		-- 6.15, the live event's banner (client/EventBanner.luau) with the chips showing (and without them): on the
		-- screen, clear of the chips, the touch buttons, the thumbstick, the row, ADMIN and the columns; never under
		-- BANNER_MIN (its 16 px title at 9.6 px).
		for _, withChips in { true, false } do
			local chipsBox = if withChips then chips else nil
			local banner, bannerScale = TouchLayout.banner(W, H, TouchLayout.BANNER, chipScale, leftEdge, 16, rowLeft, rowBottom, chipsBox, blocks)
			local what = if withChips then " (with the chips)" else ""
			check(`{name}{tag}: the banner on the screen{what}`, inside(banner, W, H), show(banner))
			if withChips then
				check(`{name}{tag}: the banner clear of the chips`, not TouchLayout.overlap(banner, chips), `{show(banner)} / {show(chips)}`)
			end
			check(`{name}{tag}: the banner clear of the row, the columns and the bar{what}`, not (TouchLayout.overlap(banner, row) or TouchLayout.overlap(banner, leftCol) or TouchLayout.overlap(banner, contract) or TouchLayout.overlap(banner, col2) or TouchLayout.overlap(banner, bar)), show(banner))
			check(`{name}{tag}: the banner clear of the thumbstick and the jump button{what}`, not (TouchLayout.overlap(banner, c.thumb) or TouchLayout.overlap(banner, c.jump)), show(banner))
			for i, b in buttons do
				check(`{name}{tag}: the banner clear of {names[i]}{what}`, not TouchLayout.overlap(banner, b), `{show(banner)} / {show(b)}`)
			end
			if admin then
				check(`{name}{tag}: the banner clear of ADMIN{what}`, not TouchLayout.overlap(banner, adminBox), show(banner))
			end
			check(`{name}{tag}: the banner at BANNER_TINY or bigger{what}`, bannerScale >= TouchLayout.BANNER_TINY - 1e-9, bannerScale)
			if W > H and W >= 700 and not admin then
				check(`{name}: the banner big enough to read{what} ({math.floor(16 * bannerScale * 10 + 0.5) / 10} px title)`, bannerScale >= TouchLayout.BANNER_MIN - 1e-9, bannerScale)
			end
		end
	end
end

-- 6.14: a computer's wide screen: the chips in the middle of the top edge at the HUD's scale.
do
	local W, H = 1920, 1020
	local S = scaleFor(W, H)
	local wide, stacked = TouchLayout.CHIPS_WIDE, TouchLayout.CHIPS_STACKED
	local chips, scale, isStacked = TouchLayout.chips(W, H, wide, stacked, S, 16 + 380 * S, 8, W - 16 - 370 - 200 * S, 4 + 44 * S, {})
	check("a computer: the chips side by side in the top middle at the HUD's scale", scale == S and not isStacked and math.abs((chips.x0 + chips.x1) / 2 - W / 2) < 1 and chips.y0 == 8, `{show(chips)} {scale}`)
	-- Little room up there (a narrow window): still on the screen, clear of the column and the row.
	local narrow, small = TouchLayout.chips(900, 600, wide, stacked, 0.78, 16 + 380 * 0.78, 8, 900 - 16 - 200 * 0.78, 4 + 44 * 0.78, {})
	check("a narrow computer window: the chips fit somewhere on the screen", inside(narrow, 900, 600) and small >= TouchLayout.CHIPS_MIN, `{show(narrow)} {small}`)
	-- 6.15: the live event's banner right under the chips in the top middle, at the HUD's scale; without the chips at
	-- the top edge itself.
	local playerList = TouchLayout.box(W - 16 - 370, 0, W, 52 + 40 * 4)
	local banner, bannerScale = TouchLayout.banner(W, H, TouchLayout.BANNER, S, 16 + 380 * S, 8, W - 16 - 370 - 200 * S, 4 + 44 * S, chips, { playerList })
	check("a computer: the banner under the chips in the top middle at the HUD's scale", bannerScale == S and math.abs((banner.x0 + banner.x1) / 2 - W / 2) < 1 and banner.y0 == chips.y1 + TouchLayout.GAP and not TouchLayout.overlap(banner, chips), `{show(banner)} {bannerScale}`)
	local alone = TouchLayout.banner(W, H, TouchLayout.BANNER, S, 16 + 380 * S, 8, W - 16 - 370 - 200 * S, 4 + 44 * S, nil, { playerList })
	check("a computer without the chips: the banner at the top edge", alone.y0 == 8 and math.abs((alone.x0 + alone.x1) / 2 - W / 2) < 1, show(alone))
end

-- 6.14 review: the HUD's left column at the top left (client/Hud.luau LEFT_H: the cash 30 + 6 + the minimap 172 + 6 +
-- the health 44 = 258 px at scale 1) with the savings line (Config.Readiness.LineHeight 20 px) ends over the
-- thumbstick's corner, at LEFT_SHRINK of the HUD's scale at least; else the line stays away and the column keeps the
-- HUD's scale (as before 6.14).
do
	local BASE, LINE = 258, 20
	local shown, hidden = 0, 0
	for _, screen in SCREENS do
		local name, W, H = screen[1] :: string, screen[2] :: number, screen[3] :: number
		local S = scaleFor(W, H)
		local c = TouchLayout.cluster(W, H, S)
		local fits, scale = TouchLayout.leftColumn(c, S, BASE, LINE, BASE + LINE)
		local _, plain = TouchLayout.leftColumn(c, S, BASE, LINE, BASE)
		check(`{name}: the left column without the line keeps the HUD's scale`, plain == S, plain)
		if fits then
			shown += 1
			local bottom = TouchLayout.MARGIN + (BASE + LINE) * scale
			check(`{name}: with the savings line the left column ends over the thumbstick ({math.floor(bottom)} ≤ {c.thumb.y0})`, bottom <= c.thumb.y0 + 1e-6 and scale >= S * TouchLayout.LEFT_SHRINK - 1e-9 and scale <= S, `{scale} of {S}`)
		else
			hidden += 1
			-- (the line goes: the column is BASE tall again and keeps S)
			check(`{name}: no room for the savings line over the thumbstick: it stays away`, (BASE + LINE) * S * TouchLayout.LEFT_SHRINK > c.thumb.y0 - TouchLayout.MARGIN, S)
		end
	end
	check("the savings line shows on most phones, the iPhone 14 among them", shown >= 5 and (TouchLayout.leftColumn(TouchLayout.cluster(844, 354, scaleFor(844, 354)), scaleFor(844, 354), BASE, LINE, BASE + LINE)), `{shown} shown, {hidden} hidden`)
	check("… and stays away on the smallest phone (640 × 316)", not (TouchLayout.leftColumn(TouchLayout.cluster(640, 316, scaleFor(640, 316)), scaleFor(640, 316), BASE, LINE, BASE + LINE)))
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
