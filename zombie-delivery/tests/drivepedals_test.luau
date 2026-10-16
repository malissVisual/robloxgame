-- Logic test of 9.1's drive pedals (shared/PedalRules.luau, Config.DrivePedals) in the standalone Luau CLI: the input
-- (GAS, BRAKE, both), the press drawn (down quickly, back quickly, no overshoot), the shapes (GAS tall and narrow, BRAKE
-- wider and shorter, a finger's size on a touch screen) and where they go: on phones and tablets held sideways and
-- upright at the bottom just left of the EXIT button's column, clear of Roblox's jump button, its thumbstick's corner,
-- EXIT and the HUD's speed and fuel (the sandbox's right column, docked as client/Hud.luau's layout docks it), with and
-- without the ADMIN button, the city's FIRE too; on computers compact in the lower right corner over the speed, a
-- gamepad's R2 / L2 caption under them; an offer card in their way; a screen with no room at all.
-- Run: python3 tests/run_tests.py [path to the luau binary] (it copies shared/PedalRules.luau, shared/Config.luau and
-- client/TouchLayout.luau next to this test).

local PedalRules = require("./PedalRules")
local TouchLayout = require("./TouchLayout")
local Config = require("./Config")
local Inventory = require("./Inventory") -- (client/Hud.luau's layout docks its right column beside the bottom bar's room)
local Holding = require("./Holding")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

type Box = PedalRules.Box
local C = Config.DrivePedals

local function show(b: Box): string
	return string.format("%d,%d-%d,%d", b.x0, b.y0, b.x1, b.y1)
end
local function width(b: Box): number
	return b.x1 - b.x0
end
local function height(b: Box): number
	return b.y1 - b.y0
end
-- Clear of `other` by at least `px` (touching after the margin does not count).
local function apart(b: Box, other: Box, px: number): boolean
	return not PedalRules.overlap(b, PedalRules.box(other.x0 - px + 0.01, other.y0 - px + 0.01, other.x1 + px - 0.01, other.y1 + px - 0.01))
end
-- client/Ui.luau Ui.scaleFor (1 at 1150 × 680, 0.55 .. 1.1)
local function scaleFor(W: number, H: number): number
	return math.clamp(math.min(W / 1150, H / 680), 0.55, 1.1)
end

-- ── Config ──────────────────────────────────────────────────────────────────
check("Config.DrivePedals is on", type(C) == "table" and C.On == true)
check("GAS is taller and narrower than BRAKE", C.Gas[2] > C.Brake[2] and C.Gas[1] < C.Brake[1], `{C.Gas[1]}x{C.Gas[2]} / {C.Brake[1]}x{C.Brake[2]}`)
check("the press numbers are sane", C.Press.Depth > 0 and C.Press.Squash > 0 and C.Press.Squash < 0.5 and C.Press.In > C.Press.Out and C.Press.Out > 0
	and C.Face.Pressed < C.Face.Rest and C.Press.Accent[2] > C.Press.Accent[1])

-- ── The device ──────────────────────────────────────────────────────────────
check("a touch screen holds them to drive", PedalRules.mode("touch") == "buttons")
check("the keys and a gamepad see them", PedalRules.mode("keys") == "show" and PedalRules.mode("pad") == "show")

-- ── The input ───────────────────────────────────────────────────────────────
check("GAS held: forward", PedalRules.throttle(true, false, 0) == 1 and PedalRules.throttle(true, false, -20) == 1)
check("BRAKE held: brakes, then backs up (as S)", PedalRules.throttle(false, true, 30) == -1 and PedalRules.throttle(false, true, 0) == -1)
check("none held: nothing", PedalRules.throttle(false, false, 12) == 0)
check("both held rolling forward: the brake", PedalRules.throttle(true, true, 20) == -1)
check("both held rolling back: the brake (against the way it rolls)", PedalRules.throttle(true, true, -20) == 1)
check("both held standing: it stands (never backs up)", PedalRules.throttle(true, true, 0) == 0 and PedalRules.throttle(true, true, C.Rolling * 0.5) == 0)

-- ── The press drawn ─────────────────────────────────────────────────────────
check("held: all the way down", PedalRules.target(true, 0, 1) == 1 and PedalRules.target(true, 1, -1) == 1)
check("the foot on its side: W down on GAS, BRAKE up", PedalRules.target(false, 1, 1) == 1 and PedalRules.target(false, 1, -1) == 0)
check("a gamepad's trigger part way: part way down", math.abs(PedalRules.target(false, 0.4, 1) - 0.4) < 1e-9 and math.abs(PedalRules.target(false, -0.6, -1) - 0.6) < 1e-9)
check("no foot: up", PedalRules.target(false, 0, 1) == 0 and PedalRules.target(false, 0, -1) == 0)
do
	-- 60 frames a second: down, then let go
	local at, frames, steady = 0, 0, true
	while at < 1 and frames < 600 do
		local was = at
		at = PedalRules.ease(at, 1, 1 / 60)
		steady = steady and at >= was and at <= 1
		frames += 1
	end
	check(`pressed, it is all the way down quickly ({frames} frames)`, at == 1 and frames <= 15, frames)
	check("… never past the bottom, never back up on the way", steady)
	local back = 0
	while at > 0 and back < 600 do
		local was = at
		at = PedalRules.ease(at, 0, 1 / 60)
		steady = steady and at <= was and at >= 0
		back += 1
	end
	check(`let go, it is back quickly ({back} frames), slower than down`, at == 0 and back <= 25 and back >= frames, back)
	check("… no bounce", steady)
	check("a long frame lands on the target, not past it", PedalRules.ease(0, 1, 5) == 1 and PedalRules.ease(1, 0, 5) == 0)
end
do
	local up, down, half = PedalRules.look(0), PedalRules.look(1), PedalRules.look(0.5)
	check("up: as built", up.down == 0 and up.height == 1 and up.shade == 0 and not up.lit and up.accent == C.Press.Accent[1])
	check("down: lower, shorter (it tips away), darker, the accent wide and lit", down.down == C.Press.Depth and down.height < 1 and down.shade > 0
		and down.lit and down.accent == C.Press.Accent[2])
	check("half way: in between, lit", half.down > 0 and half.down < down.down and half.height < 1 and half.height > down.height and half.lit)
	check("out of range: held to 0 … 1", PedalRules.look(3).down == down.down and PedalRules.look(-1).down == 0)
end

-- ── The shapes ──────────────────────────────────────────────────────────────
for _, touch in { true, false } do
	for _, S in { 0.55, 0.7, 0.85, 1, 1.1 } do
		local scales = PedalRules.scales(S, touch)
		local ordered = #scales >= 1
		for index = 2, #scales do
			ordered = ordered and scales[index] < scales[index - 1]
		end
		local where = if touch then "a touch screen" else "a computer"
		check(`{where} at S {S}: the scales the biggest first`, ordered, table.concat(scales, ", "))
		for _, scale in scales do
			local s = PedalRules.sizes(scale)
			check(`{where} at S {S}, scale {math.floor(scale * 100) / 100}: GAS tall and narrow, BRAKE wider and shorter`, s.gasH > s.brakeH and s.gasW < s.brakeW)
			if touch then
				check(`{where} at S {S}, scale {math.floor(scale * 100) / 100}: every side a finger's (44 px)`,
					math.min(s.gasW, s.gasH, s.brakeW, s.brakeH) >= C.Touch.MinSide - 1e-6, `{s.gasW}x{s.gasH} {s.brakeW}x{s.brakeH}`)
			end
		end
	end
end
do
	local s = PedalRules.sizes(1, true)
	check("a gamepad's caption under them makes the pair taller", s.h == C.Gas[2] + C.Caption and PedalRules.sizes(1).h == C.Gas[2])
	local gas, brake = PedalRules.split(PedalRules.box(100, 100, 100 + s.w, 100 + s.h), s)
	check("split: BRAKE left of GAS (as in a car), the gap between", brake.x1 < gas.x0 and math.abs(gas.x0 - brake.x1 - s.gap) < 1e-6)
	check("split: their bottoms on the caption strip", gas.y1 == brake.y1 and gas.y1 == 100 + s.h - s.caption)
end

-- ── Where they go on a touch screen ─────────────────────────────────────────
-- The HUD's area (under Roblox's top bar, inside a phone's notch): name, W, H.
local SCREENS: { { any } } = {
	{ "iPhone 14 sideways (notch insets, old top bar)", 750, 354 },
	{ "iPhone 14 sideways (notch insets, new top bar)", 750, 332 },
	{ "iPhone 14 sideways (no insets)", 844, 354 },
	{ "iPhone 14 Pro Max sideways", 838, 372 },
	{ "iPhone SE sideways", 667, 339 },
	{ "iPhone SE sideways (new top bar)", 667, 317 },
	{ "Android 20:9 sideways", 800, 324 },
	{ "small Android sideways (new top bar)", 640, 316 },
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
	local phone = c.small
	for _, admin in { false, true } do
		-- client/Hud.luau's layout: the right column (300 × 130 at S on a touch screen) docked beside the bottom bar's
		-- room; the sandbox shows only its speed row (30 at S) at its bottom while you drive
		local rowScale = math.max(S, 0.8)
		local rowBottom = (if admin then 96 else 16) + 44 * rowScale
		local rowLeft = math.min(W - 16 - 170 * rowScale, if admin then W - 16 - 90 else W)
		local barW, barH = Inventory.size(#Holding.Order + 2, true)
		local barScale = math.max(S, Inventory.minScale(true))
		local column = TouchLayout.dock(c, W, H, 300 * S, 130 * S, rowBottom, rowLeft, barW * barScale, barH * barScale)
		local speed = TouchLayout.box(column.x0, column.y1 - 30 * S, column.x1, column.y1)
		local leftColumn = TouchLayout.box(16, 16, 16 + 200 * S, 16 + 258 * S) -- (the health, the sandbox's money beside it)
		local tag = name .. (if admin then " (ADMIN)" else "")
		for _, city in { false, true } do
			local blocks = { speed, leftColumn }
			if city then
				-- the city's FIRE shows in a car too (a car gun): the pedals keep clear of it as well
				table.insert(blocks, c.fire)
			end
			local where = tag .. (if city then " with FIRE" else "")
			local gas, brake, scale, clear = PedalRules.layout(W, H, S, true, c, blocks)
			check(`{where}: a clear place`, clear, `{show(brake)} {show(gas)}`)
			check(`{where}: each a finger's size or more`, math.min(width(gas), height(gas), width(brake), height(brake)) >= 44 - 1e-6, `{show(brake)} {show(gas)}`)
			check(`{where}: GAS tall and narrow, BRAKE wider and shorter, BRAKE on the left`, height(gas) > height(brake) and width(gas) < width(brake) and brake.x1 < gas.x0)
			if phone then
				check(`{where}: comfortable to hold on a phone (GAS {math.floor(height(gas))} px tall)`, height(gas) >= 70 and height(gas) <= 110 and height(brake) >= 56)
			end
			check(`{where}: never one on the other`, not PedalRules.overlap(gas, brake))
			for _, b in { gas, brake } do
				local which = if b == gas then "GAS" else "BRAKE"
				check(`{where}: {which} on the screen`, b.x0 >= 0 and b.y0 >= 0 and b.x1 <= W and b.y1 <= H, show(b))
				check(`{where}: {which} clear of the jump button`, apart(b, c.jump, C.Clear), `{show(b)} / {show(c.jump)}`)
				check(`{where}: {which} clear of the thumbstick's corner (and never over it)`, apart(b, c.thumb, C.Clear) and b.x0 >= c.thumb.x1, `{show(b)} / {show(c.thumb)}`)
				check(`{where}: {which} clear of EXIT`, apart(b, c.act, C.Clear), `{show(b)} / {show(c.act)}`)
				check(`{where}: {which} clear of the speed and the fuel`, apart(b, speed, C.Clear), `{show(b)} / {show(speed)}`)
				check(`{where}: {which} clear of the left column`, apart(b, leftColumn, C.Clear), show(b))
				if city then
					check(`{where}: {which} clear of FIRE`, apart(b, c.fire, C.Clear), `{show(b)} / {show(c.fire)}`)
				end
				check(`{where}: {which} in the lower part, right of the middle`, b.y0 >= H * C.TopShare - 0.01 and gas.x1 >= W * 0.5, show(b))
			end
			if W > H and not city then
				-- sideways: at the bottom where the right thumb rests, right beside EXIT's column
				check(`{where}: at the bottom (where the thumb rests)`, gas.y1 >= H * 0.85, show(gas))
				check(`{where}: right beside EXIT's column`, c.act.x0 - gas.x1 <= C.Clear + 1, `{show(gas)} / {show(c.act)}`)
			end
		end
	end
end

-- ── Where they go on a computer ─────────────────────────────────────────────
for _, screen in { { 1280, 800 }, { 1920, 1080 }, { 1366, 768 }, { 1024, 600 }, { 800, 600 } } do
	local W, H = screen[1], screen[2]
	local S = scaleFor(W, H)
	-- client/Hud.luau's right column (240 × 84 at S) at the lower right corner: the speed and the fuel at its bottom;
	-- the health at the lower left
	local column = TouchLayout.box(W - 16 - 240 * S, H - 16 - 84 * S, W - 16, H - 16)
	local speed = TouchLayout.box(column.x0, column.y1 - 30 * S, column.x1, column.y1)
	local health = TouchLayout.box(16, H - 16 - 44 * S, 16 + 200 * S, H - 16)
	for _, captioned in { false, true } do
		local where = `a computer {W} × {H}` .. (if captioned then " with a gamepad" else "")
		local gas, brake, scale, clear = PedalRules.layout(W, H, S, false, nil, { speed, health }, captioned)
		local sizes = PedalRules.sizes(scale, captioned)
		check(`{where}: a clear place`, clear)
		check(`{where}: compact (GAS {math.floor(height(gas))} px tall)`, height(gas) <= 90 and height(gas) >= 40 and width(brake) <= 70, `{show(brake)} {show(gas)}`)
		check(`{where}: at the right edge, right over the speed`, math.abs(gas.x1 - (W - C.Margin.Desk)) < 0.5 and gas.y1 + sizes.caption <= speed.y0 - C.Clear + 0.01
			and gas.y1 + sizes.caption >= speed.y0 - C.Clear - 1, `{show(gas)} / {show(speed)}`)
		for _, b in { gas, brake } do
			check(`{where}: clear of the speed and the health`, apart(b, speed, C.Clear) and apart(b, health, C.Clear), show(b))
		end
		if captioned then
			check(`{where}: the caption strip clear of the speed too`, gas.y1 + sizes.caption <= speed.y0 - C.Clear + 0.01)
		end
	end
end

-- ── In the way ──────────────────────────────────────────────────────────────
do
	-- a visitor's offer card over their spot on a phone: they go elsewhere, clear of it and of the controls
	local W, H = 844, 354
	local S = scaleFor(W, H)
	local c = TouchLayout.cluster(W, H, S)
	local card = TouchLayout.box(470, 150, 670, 346)
	local gas, brake, _, clear = PedalRules.layout(W, H, S, true, c, { card })
	check("an offer card in the way: still a clear place", clear, `{show(brake)} {show(gas)}`)
	check("… clear of the card", apart(gas, card, C.Clear) and apart(brake, card, C.Clear), `{show(brake)} {show(gas)}`)
	check("… and of the controls", apart(gas, c.act, C.Clear) and apart(gas, c.jump, C.Clear) and apart(brake, c.thumb, C.Clear) and brake.x0 >= c.thumb.x1)
	-- staying put (client/DrivePedals.luau): free while nothing lies on them; a fresh place is better only when its cost
	-- is lower (the card gone), never when it only dodges something beside them
	local home, homeBrake, homeScale, _, homeCost = PedalRules.layout(W, H, S, true, c, {})
	check("the cost a layout gives is the placed pair's cost", math.abs(homeCost - PedalRules.cost(W, H, S, true, c, home, homeScale)) < 1e-6, homeCost)
	local beside = TouchLayout.box(home.x0 - 300, home.y0 - 60, home.x0 - 4, home.y0 - 4)
	check("a card beside them (not on them): still free", PedalRules.free(home, homeBrake, { beside }))
	check("a card on them: not free", not PedalRules.free(home, homeBrake, { TouchLayout.box(home.x0 + 4, home.y0 + 4, home.x1 + 40, home.y1) }))
	local _, _, _, _, dodging = PedalRules.layout(W, H, S, true, c, { beside })
	check("… a fresh place dodging the card beside them costs more (they stay)", dodging > homeCost)
	local _, _, _, _, away = PedalRules.layout(W, H, S, true, c, { card })
	check("… a place away from a card on their spot costs more than their spot once it is gone (they come back)", away > homeCost)
	-- no room at all: the place that covers the least, on the screen, never on the controls when it can help it
	local wall = TouchLayout.box(0, 0, W, H)
	local g2, b2, s2, clear2 = PedalRules.layout(W, H, S, true, c, { wall })
	check("no room at all: no clear place, but a place on the screen", not clear2 and g2.x0 >= 0 and g2.y1 <= H and b2.x0 >= 0 and s2 > 0, `{show(b2)} {show(g2)}`)
	check("… off the controls", not PedalRules.overlap(g2, c.jump) and not PedalRules.overlap(g2, c.act) and not PedalRules.overlap(b2, c.thumb), `{show(b2)} {show(g2)}`)
end

-- The small helpers.
local a = PedalRules.box(0, 0, 10, 10)
check("overlap: shared area", PedalRules.overlap(a, PedalRules.box(5, 5, 15, 15)))
check("overlap: touching edges do not count", not PedalRules.overlap(a, PedalRules.box(10, 0, 20, 10)))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
