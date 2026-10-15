-- 7.0 review: where the move's pieces sit (client/MoveLayout.luau, pure) on phones (held sideways and upright), tablets
-- and computers: the move's panel at the top in the middle, Danny's strip under it, the quick chat's touch button beside
-- them (a finger's size, clear of the touch buttons, the thumbstick and the jump button), the ring's lines a finger's
-- height on a touch screen and on the screen, never on each other; the list a sheet over the whole height on a touch
-- screen, at the right under the panel and Roblox's player list on a computer. Run with tests/run_tests.py.
local MoveLayout = require("./MoveLayout")
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
local function scaleFor(W: number, H: number): number -- (client/Ui.luau scaleFor: ScaleBase 1150 × 680, 0.55 … 1.1)
	return math.clamp(math.min(W / 1150, H / 680), 0.55, 1.1)
end
local function show(b: TouchLayout.Box): string
	return string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1)
end

local PILL_W, PILL_H, RADIUS = 210, 44, 150 -- client/QuickChat.luau's ring
local TOUCH = {
	{ 844, 354, "a phone sideways (844 × 390 under the top bar)" },
	{ 844, 390, "a phone sideways (the whole height)" },
	{ 667, 339, "a small phone sideways" },
	{ 932, 394, "a big phone sideways" },
	{ 390, 808, "a phone upright" },
	{ 360, 640, "a small phone upright" },
	{ 1024, 732, "a tablet" },
	{ 1366, 988, "a big tablet" },
}
local DESK = {
	{ 1920, 1044, "a full HD screen" },
	{ 1280, 684, "a laptop" },
	{ 1150, 680, "the base size" },
	{ 800, 564, "a small window" },
}

for _, case in TOUCH do
	local W, H, name = case[1], case[2], case[3]
	local S = scaleFor(W, H)
	local cluster = TouchLayout.cluster(W, H, S)
	local touchBlocks = TouchLayout.buttons(cluster)
	table.insert(touchBlocks, cluster.thumb)
	table.insert(touchBlocks, cluster.jump)
	local panel = MoveLayout.panel(W, S)
	check(`{name}: the panel on the screen, at the top in the middle`, MoveLayout.inside(panel, W, H) and panel.y0 == MoveLayout.TOP
		and math.abs((panel.x0 + panel.x1) / 2 - W / 2) < 0.5, show(panel))
	local strip = MoveLayout.strip(panel, S, math.max(30, math.ceil(MoveLayout.MIN_TOUCH / S)))
	check(`{name}: Danny's strip under the panel, a finger's buttons`, strip.y0 > panel.y1 and not MoveLayout.overlap(strip, panel) and MoveLayout.inside(strip, W, H))
	local clearPanel = true
	for _, b in touchBlocks do
		if MoveLayout.overlap(panel, b) or MoveLayout.overlap(strip, b) then
			clearPanel = false
		end
	end
	check(`{name}: the panel and the strip clear of the touch buttons`, clearPanel)
	local blocks = table.clone(touchBlocks)
	table.insert(blocks, panel)
	table.insert(blocks, strip)
	local chat = MoveLayout.chatButton(W, H, S, panel, blocks)
	local clearChat = MoveLayout.inside(chat, W, H)
	for _, b in blocks do
		if MoveLayout.overlap(chat, b) then
			clearChat = false
		end
	end
	check(`{name}: the 💬 button on the screen, clear of the panel, the strip and the touch buttons`, clearChat, show(chat))
	check(`{name}: … a finger's size`, chat.x1 - chat.x0 >= MoveLayout.MIN_TOUCH and chat.y1 - chat.y0 >= MoveLayout.MIN_TOUCH)
	local ringScale, r, width = MoveLayout.ring(W, H, S, true, RADIUS, PILL_W, PILL_H)
	check(`{name}: the ring's lines a finger's height`, PILL_H * ringScale >= MoveLayout.MIN_TOUCH - 0.01, PILL_H * ringScale)
	check(`{name}: … the whole ring on the screen`, (2 * r + PILL_H) * ringScale <= H - 2 * MoveLayout.GAP + 0.01 and (2 * r + width) * ringScale <= W - 2 * MoveLayout.GAP + 0.01,
		`{r} × {ringScale}, lines {width}`)
	check(`{name}: … its lines wide enough for two lines of words`, width >= MoveLayout.PILL_MIN_W and width <= PILL_W)
	check(`{name}: … its lines never on each other (neighbours r/2 apart up and down)`, r / 2 > PILL_H)
	local list, listScale, sheet = MoveLayout.list(W, H, S, true, strip.y1, nil)
	check(`{name}: the list a sheet over the whole height, in the middle, on the screen`, sheet and MoveLayout.inside(list, W, H) and list.y0 == MoveLayout.TOP
		and list.y1 == H - MoveLayout.TOP and math.abs((list.x0 + list.x1) / 2 - W / 2) < 0.5, show(list))
	check(`{name}: … readable (at least the planning's size, or the screen's width)`, listScale >= math.min(MoveLayout.SHEET_SCALE, (W - 2 * MoveLayout.SHEET_MARGIN) / MoveLayout.LIST_W) - 0.001
		and list.x1 - list.x0 <= W - 2 * MoveLayout.SHEET_MARGIN + 0.01, listScale)
end

for _, case in DESK do
	local W, H, name = case[1], case[2], case[3]
	local S = scaleFor(W, H)
	local panel = MoveLayout.panel(W, S)
	local strip = MoveLayout.strip(panel, S, 30)
	local players = TouchLayout.box(W - 16 - MoveLayout.PLAYER_LIST_W, 0, W, math.min(H * 0.45, 52 + 40 * 4))
	local list, listScale, sheet = MoveLayout.list(W, H, S, false, strip.y1, players)
	check(`{name}: the list at the right, not a sheet, the HUD's scale`, not sheet and listScale == S and math.abs(list.x1 - (W - 16)) < 0.01, show(list))
	check(`{name}: … under the panel, the strip and Roblox's player list`, list.y0 >= strip.y1 and list.y0 >= players.y1 and not MoveLayout.overlap(list, panel)
		and not MoveLayout.overlap(list, strip) and not MoveLayout.overlap(list, players), show(list))
	check(`{name}: … on the screen, a useful height`, MoveLayout.inside(list, W, H) and list.y1 - list.y0 >= 160 * S - 0.01, show(list))
	local noList = MoveLayout.list(W, H, S, false, strip.y1, nil)
	check(`{name}: without the player list right under the panel`, math.abs(noList.y0 - (strip.y1 + 10)) < 0.01)
	local ringScale, r, width = MoveLayout.ring(W, H, S, false, RADIUS, PILL_W, PILL_H)
	check(`{name}: a computer's ring at the HUD's scale, its lines whole`, ringScale == S and r == RADIUS and width == PILL_W)
end

-- 8.4: Danny's strip clear of the HUD's chips at the top left (MoveLayout.stripClear): the sandbox's money block (170 ×
-- 92 right of the touch screen's left column) and the TASKS chip under it, as client/SandboxHud.luau and
-- client/SandboxTasksUi.luau put them on a phone (tools/phone-ui/dannycard.luau runs the real ones)
do
	local box = TouchLayout.box
	local function chipsFor(S: number): { TouchLayout.Box }
		local x0 = 16 + 200 * S + 8 -- (right of the left column: client/Hud.luau's TopStack)
		return { box(x0, 16, x0 + 170, 108), box(x0, 113, x0 + 100, 157) }
	end
	local function keepFor(W: number, H: number, S: number): { TouchLayout.Box }
		local cluster = TouchLayout.cluster(W, H, S)
		local list = table.clone(TouchLayout.buttons(cluster))
		table.insert(list, cluster.thumb)
		table.insert(list, cluster.jump)
		return list
	end
	for _, size in { { 667, 339 }, { 740, 324 }, { 780, 324 } } do
		local W, H = size[1], size[2]
		local S = scaleFor(W, H)
		local panel = MoveLayout.panel(W, S)
		local strip = MoveLayout.strip(panel, S, math.ceil(MoveLayout.MIN_TOUCH / S))
		local chips, keep = chipsFor(S), keepFor(W, H, S)
		local hits = MoveLayout.overlap(strip, chips[1]) or MoveLayout.overlap(strip, chips[2])
		local clear = MoveLayout.stripClear(strip, W, H, chips, keep)
		local free = true
		for _, b in chips do
			free = free and not MoveLayout.overlap(clear, b)
		end
		for _, b in keep do
			free = free and not MoveLayout.overlap(clear, b)
		end
		check(`8.4 {W} × {H + 36}: the strip under the panel lay on the chips; moved: off them and the touch controls, shifted right just past them, still under the panel, on the screen`,
			hits and free and clear.y0 == strip.y0 and math.abs(clear.x0 - (chips[1].x1 + MoveLayout.GAP)) < 0.01 and clear.x0 < panel.x1
			and clear.x1 <= W - MoveLayout.GAP and clear.x1 - clear.x0 == strip.x1 - strip.x0, `{show(strip)} → {show(clear)}`)
	end
	for _, size in { { 844, 354 }, { 932, 394 }, { 1024, 732 }, { 1280, 684 }, { 1920, 1044 } } do
		local W, H = size[1], size[2]
		local S = scaleFor(W, H)
		local strip = MoveLayout.strip(MoveLayout.panel(W, S), S, math.ceil(MoveLayout.MIN_TOUCH / S))
		check(`8.4 {W} × {H}: nothing in its way: the strip where it was (the same box)`, MoveLayout.stripClear(strip, W, H, chipsFor(S), keepFor(W, H, S)) == strip)
	end
	-- no room to the right (a strip as wide as the screen's middle): under the chips, in its place across
	local wide = box(150, 80, 600, 130)
	local under = MoveLayout.stripClear(wide, 667, 339, { box(134, 16, 304, 108), box(134, 113, 234, 157) }, {})
	check("8.4 no room right of the chips: just under them, in its place across", under.x0 == 150 and under.y0 == 157 + MoveLayout.GAP and under.x1 == 600, show(under))
	local stuck = MoveLayout.stripClear(wide, 667, 200, { box(134, 16, 304, 108), box(134, 113, 234, 157) }, {})
	check("8.4 … no room under them either: where it was", stuck == wide)
end

-- a very short screen: the ring shrinks to stay whole, never folds onto itself
local tinyScale, tinyR, tinyW = MoveLayout.ring(568, 280, 0.55, true, RADIUS, PILL_W, PILL_H)
check("a very short screen: the ring smaller but whole", (2 * tinyR + PILL_H) * tinyScale <= 280 - 2 * MoveLayout.GAP + 0.01
	and (2 * tinyR + tinyW) * tinyScale <= 568 - 2 * MoveLayout.GAP + 0.01 and tinyR / 2 > PILL_H, `{tinyR} × {tinyScale}`)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
