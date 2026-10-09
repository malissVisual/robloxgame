--!strict
-- 4.2: where the touch controls sit on a phone or a tablet without a keyboard (Ui.touchLayout), in the HUD's pixels
-- (W × H, the area under Roblox's top bar, and the HUD's scale S = Ui.scaleFor). Pure: Hud's layout() asks it, and
-- tests/touchlayout_test.luau checks it in the plain Luau CLI for phones and tablets (nothing here touches Roblox).
--
--   * Roblox's own jump button (the PlayerModule's TouchJump: 70 px at 95 / 90 px from the lower right corner on a
--     small screen, the shorter side ≤ 500 px; 120 px at 170 / 210 px on a big one) and its thumbstick's corner
--     (lower left) are not ours: nothing goes there.
--   * FIRE just over the jump button, at least 64 px.
--   * A column of three left of FIRE and the jump button, bottom up: SPRINT (the toggle, next to the jump button),
--     the hand button (PUNCH / STRIKE on foot; the same place says EXIT in a car seat and PUT DOWN / LET GO / SET DOWN
--     while you carry or push, client/TouchControls.luau) and DRAW / HOLSTER. Every one is at least 44 px each way.
--   * The HUD's right column (the weapon, the vehicle, the items) goes left of all that, down to the bottom; when that
--     leaves too little room for the contextual action between it and the thumbstick (a narrow phone, a phone held
--     upright), it goes over the buttons at the right edge instead, if it fits under the actions' row.
--   * The contextual action between the thumbstick's corner and the first of those (narrower, on more lines, on a
--     narrow phone); held upright, over all of them.
--   * 6.0.1, the bottom bar (client/Hotbar.luau: the items 1-5 over what you carry), TouchLayout.dock: at the bottom
--     between the thumbstick's corner and the right column; when that is too narrow, between the corner and the
--     buttons with the right column raised over the bar; else (upright) over everything at the bottom, across the
--     middle. The contextual action sits over the bar (TouchLayout.hint's `floor`).
--   * 6.14, the grind chips (client/GrindChips.luau: the streak and the shift), TouchLayout.chips: at the top between
--     the contract column and the actions' row (one over the other when it is narrow), or under the row at the right
--     edge, clear of all of the above.
--   * 6.14 review, the HUD's left column at the top left (the cash, 6.14's savings line, the minimap, the health),
--     TouchLayout.leftColumn: with the savings line it must end over the thumbstick's corner; it may shrink a little
--     for it (LEFT_SHRINK of the HUD's scale), else the line stays away (the column as it was before 6.14).

local TouchLayout = {}

export type Box = { x0: number, y0: number, x1: number, y1: number }

export type Cluster = {
	small: boolean, -- Roblox's small touch controls (the shorter side ≤ 500 px)
	jump: Box, -- Roblox's jump button (not ours)
	thumb: Box, -- the thumbstick's corner (not ours)
	fire: Box,
	sprint: Box,
	act: Box, -- the hand button: PUNCH / STRIKE, EXIT, PUT DOWN ...
	holster: Box, -- DRAW / HOLSTER
	top: number, -- the highest edge of our buttons
	left: number, -- the leftmost edge of our buttons
}

TouchLayout.MIN_HIT = 44 -- px: the smallest side of anything you tap
TouchLayout.GAP = 8 -- px between the buttons and the panels
TouchLayout.STACK_GAP = 6 -- px between the buttons of the column
TouchLayout.MARGIN = 16
TouchLayout.MIN_HINT = 160 -- px: the column leaves the contextual action this much at the bottom, or goes over the buttons

function TouchLayout.box(x0: number, y0: number, x1: number, y1: number): Box
	return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

-- Do two boxes share any area (touching edges do not count)?
function TouchLayout.overlap(a: Box, b: Box): boolean
	return math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 0 and math.min(a.y1, b.y1) - math.max(a.y0, b.y0) > 0
end

-- `value` px at scale S, never under `least`.
local function px(value: number, s: number, least: number): number
	return math.max(least, math.floor(value * s + 0.5))
end

-- The buttons for a W × H screen at the HUD's scale S.
function TouchLayout.cluster(W: number, H: number, S: number): Cluster
	local box = TouchLayout.box
	local small = math.min(W, H) <= 500
	-- Roblox's jump button and thumbstick (the PlayerModule's sizes).
	local jumpSize = if small then 70 else 120
	local jx, jy = W - (if small then 95 else 170), H - (if small then 90 else 210)
	local jump = box(jx, jy, jx + jumpSize, jy + jumpSize)
	local thumb = box(0, H - (if small then 190 else 260), math.max(if small then 170 else 230, W * 0.22), H)
	-- FIRE over the jump button (its right edge 40 px from the screen's).
	local fireSize = px(96, S, 64)
	local fireBottom = jump.y0 - 10
	local fire = box(W - 40 - fireSize, fireBottom - fireSize, W - 40, fireBottom)
	-- The column left of FIRE and the jump button: SPRINT at the jump button's height, the hand button, DRAW.
	local width = px(80, S, 60)
	local x1 = math.min(fire.x0, jump.x0) - TouchLayout.GAP
	local x0 = x1 - width
	local sprintH, actH, holsterH = px(60, S, 48), px(56, S, 48), px(44, S, TouchLayout.MIN_HIT)
	local sprint = box(x0, jump.y1 - sprintH, x1, jump.y1)
	local act = box(x0, sprint.y0 - TouchLayout.STACK_GAP - actH, x1, sprint.y0 - TouchLayout.STACK_GAP)
	local holster = box(x0, act.y0 - TouchLayout.STACK_GAP - holsterH, x1, act.y0 - TouchLayout.STACK_GAP)
	return {
		small = small,
		jump = jump,
		thumb = thumb,
		fire = fire,
		sprint = sprint,
		act = act,
		holster = holster,
		top = math.min(fire.y0, holster.y0, jump.y0),
		left = x0,
	}
end

-- Our buttons (not Roblox's): FIRE, SPRINT, the hand button, DRAW.
function TouchLayout.buttons(c: Cluster): { Box }
	return { c.fire, c.sprint, c.act, c.holster }
end

-- The HUD's right column (colW × colH px): left of the buttons down to the bottom, or over them at the right edge
-- when the bottom leaves the contextual action too little room and the column fits under `rowBottom` (the lowest
-- edge of the actions' row and the ADMIN button). Returns its box and whether it went over the buttons.
function TouchLayout.column(c: Cluster, W: number, H: number, colW: number, colH: number, rowBottom: number): (Box, boolean)
	local gap = TouchLayout.GAP
	local right, bottom = c.left - gap, H - gap
	local below = TouchLayout.box(right - colW, bottom - colH, right, bottom)
	if below.x0 >= c.thumb.x1 + 24 + TouchLayout.MIN_HINT then
		return below, false
	end
	local overBottom = c.top - gap
	local over = TouchLayout.box(W - TouchLayout.MARGIN - colW, overBottom - colH, W - TouchLayout.MARGIN, overBottom)
	if over.y0 >= rowBottom + gap then
		return over, true
	end
	return below, false -- (no better place: the action gets the narrow room)
end

-- The room the contextual action has at the bottom: from the thumbstick's corner to the first of `boxes` (our buttons,
-- the column) that reaches into the band `bandTop` .. H. Returns the left and right ends.
function TouchLayout.hintSpan(c: Cluster, boxes: { Box }, bandTop: number, W: number): (number, number)
	local left = c.thumb.x1 + 12
	local right = W - TouchLayout.MARGIN
	for _, b in boxes do
		if b.y1 > bandTop and b.x0 > left then
			right = math.min(right, b.x0 - 12)
		end
	end
	right = math.min(right, c.jump.x0 - 12)
	return left, right
end

-- The contextual action (Hud's hint: its bottom GAP + 18·S over the edge, 96·S of room reserved over it, as wide as
-- 480·S): between the thumbstick and the first button or the column, at least MIN_HINT_NARROW wide (it wraps to
-- more lines when narrow). A phone held upright has no room there: it goes over everything at the bottom, across.
-- Returns its centre x, its bottom and its width (px).
TouchLayout.HINT_W = 480
TouchLayout.MIN_HINT_NARROW = 120
-- 6.0.1: `floor`, the bottom bar's top edge: the action stays over it.
function TouchLayout.hint(c: Cluster, boxes: { Box }, W: number, H: number, S: number, floor: number?): (number, number, number)
	local bottom = H - TouchLayout.GAP - 18 * S
	if floor then
		bottom = math.min(bottom, floor - TouchLayout.GAP)
	end
	local left, right = TouchLayout.hintSpan(c, boxes, bottom - 96 * S, W)
	if right - left < TouchLayout.MIN_HINT_NARROW then
		local top = math.min(c.thumb.y0, c.jump.y0, floor or math.huge)
		for _, b in boxes do
			top = math.min(top, b.y0)
		end
		bottom = top - TouchLayout.GAP
		left, right = TouchLayout.MARGIN, W - TouchLayout.MARGIN
	end
	local width = math.max(TouchLayout.MIN_HINT_NARROW, math.min(TouchLayout.HINT_W * S, right - left))
	local x = math.clamp(W / 2, left + width / 2, math.max(left + width / 2, right - width / 2))
	return x, bottom, width
end

-- 6.0.1: the right column (colW × colH, as TouchLayout.column places it) and the bottom bar (barW × barH, the items
-- over what you carry, client/Hotbar.luau). Returns the column's box, whether it went over the buttons, and the bar's
-- box: at the bottom beside the column; else at the bottom up to the buttons, the column raised over the bar (under
-- the actions' row, `rowBottom`, or left of it: `rowLeft`, the row's and the ADMIN button's left edge); else over
-- everything at the bottom, centred.
function TouchLayout.dock(c: Cluster, W: number, H: number, colW: number, colH: number, rowBottom: number, rowLeft: number, barW: number, barH: number): (Box, boolean, Box)
	local gap = TouchLayout.GAP
	local buttons = TouchLayout.buttons(c)
	local column, over = TouchLayout.column(c, W, H, colW, colH, rowBottom)
	local function atBottom(boxes: { Box }): Box?
		local bottom = H - gap
		local left, right = TouchLayout.hintSpan(c, boxes, bottom - barH, W)
		if right - left < barW then
			return nil
		end
		local x = math.clamp(W / 2, left + barW / 2, right - barW / 2)
		-- 6.14 review: the left column (`base` px tall at scale 1 without the savings line, `line` px more with it; `height`:
-- its height now) from the top margin down. `fits`: with the line it ends over the thumbstick's corner at a scale of
-- at least LEFT_SHRINK × S (else the line stays away); `scale`: the column's scale for `height` (S without the line;
-- with it, as much of S as ends over the corner, never under LEFT_SHRINK × S).
TouchLayout.LEFT_SHRINK = 0.92
function TouchLayout.leftColumn(c: Cluster, S: number, base: number, line: number, height: number): (boolean, number)
	local room = c.thumb.y0 - TouchLayout.MARGIN
	local fits = room / math.max(1, base + line) >= S * TouchLayout.LEFT_SHRINK
	local scale = if height > base then math.min(S, math.max(S * TouchLayout.LEFT_SHRINK, room / height)) else S
	return fits, scale
end

return TouchLayout.box(x - barW / 2, bottom - barH, x + barW / 2, bottom)
	end
	local all = table.clone(buttons)
	table.insert(all, column)
	local bar = atBottom(all)
	if bar then
		return column, over, bar
	end
	bar = atBottom(buttons)
	if bar and not over then
		local raised = TouchLayout.box(column.x0, bar.y0 - gap - colH, column.x1, bar.y0 - gap)
		if raised.y0 >= rowBottom + gap then
			return raised, false, bar
		end
		-- Up beside the row instead (a small phone with the ADMIN button): moved left of it.
		local shift = math.max(0, raised.x1 - (rowLeft - gap))
		local beside = TouchLayout.box(raised.x0 - shift, raised.y0, raised.x1 - shift, raised.y1)
		if beside.y0 >= TouchLayout.MARGIN and beside.x0 >= c.thumb.x1 + 12 then
			return beside, false, bar
		end
	end
	-- Over everything at the bottom (the thumbstick's corner, the buttons, the column), across the middle.
	local top = math.min(c.thumb.y0, c.jump.y0, column.y0)
	for _, b in buttons do
		top = math.min(top, b.y0)
	end
	local x = math.clamp(W / 2, TouchLayout.MARGIN + barW / 2, math.max(TouchLayout.MARGIN + barW / 2, W - TouchLayout.MARGIN - barW / 2))
	return column, over, TouchLayout.box(x - barW / 2, top - gap - barH, x + barW / 2, top - gap)
end


-- 6.14, the grind chips (client/GrindChips.luau: ON A ROLL and SHIFT 3/5) at the top of the screen, on a computer and
-- on touch: side by side (`wide`, w × h px at scale 1) or one over the other (`stacked`, for a narrow top), at scale
-- `s` (the HUD's; on touch at least CHIPS_TOUCH) or smaller, down to CHIPS_MIN. The first of these that stays on the
-- screen, right of `leftEdge` (what the HUD keeps at the top left: the contract column, on touch the left column
-- beside it) and clear of `blocks` (the actions' row and ADMIN, the touch buttons, the thumbstick's corner, the right
-- column, the bottom bar, Roblox's player list ...) wins; `rowLeft` (the row's left edge, ADMIN's) and `rowBottom`
-- only say where to try:
--   1 side by side in the middle of the screen's top edge (`top`)
--   2 side by side in the middle of the span from `leftEdge` to the row;  3 stacked there;  4 stacked at its left end
--   5 side by side under the row (`rowBottom`) at the right edge;  6 stacked there
--   7 / 8 stacked at the span's left end / under the row, as small as it takes (CHIPS_MIN at least)
-- None clear: the last. Returns its box, its scale and whether it is stacked.
TouchLayout.CHIPS_TOUCH = 0.8
TouchLayout.CHIPS_MIN = 0.6
export type Shape = { w: number, h: number }
-- The chips' sizes at scale 1 (client/GrindChips.luau builds them so): ON A ROLL 168 × 40, SHIFT 120 × 40, 8 apart;
-- stacked both 168 wide, 6 apart.
TouchLayout.CHIPS_WIDE = { w = 296, h = 40 } :: Shape
TouchLayout.CHIPS_STACKED = { w = 168, h = 86 } :: Shape
function TouchLayout.chips(W: number, H: number, wide: Shape, stacked: Shape, s: number, leftEdge: number, top: number, rowLeft: number, rowBottom: number, blocks: { Box }): (Box, number, boolean)
	local gap = TouchLayout.GAP
	local least = math.min(s, TouchLayout.CHIPS_MIN)
	local spanLeft, spanRight = leftEdge + gap, rowLeft - gap
	local fit = math.clamp((spanRight - spanLeft) / stacked.w, least, s)
	local under = W - TouchLayout.MARGIN
	local candidates: { { box: Box, scale: number, stacked: boolean } } = {}
	local function add(shape: Shape, x0: number, y0: number, scale: number)
		table.insert(candidates, {
			box = TouchLayout.box(x0, y0, x0 + shape.w * scale, y0 + shape.h * scale),
			scale = scale,
			stacked = shape == stacked,
		})
	end
	add(wide, W / 2 - wide.w * s / 2, top, s)
	add(wide, (spanLeft + spanRight - wide.w * s) / 2, top, s)
	add(stacked, (spanLeft + spanRight - stacked.w * s) / 2, top, s)
	add(stacked, spanLeft, top, s)
	add(wide, under - wide.w * s, rowBottom + gap, s)
	add(stacked, under - stacked.w * s, rowBottom + gap, s)
	add(stacked, spanLeft, top, fit)
	add(stacked, under - stacked.w * least, rowBottom + gap, least)
	for _, candidate in candidates do
		local b = candidate.box
		local clear = b.x0 >= math.max(0, spanLeft) - 0.01 and b.y0 >= 0 and b.x1 <= W and b.y1 <= H
		for _, block in blocks do
			if clear and TouchLayout.overlap(b, block) then
				clear = false
			end
		end
		if clear then
			return b, candidate.scale, candidate.stacked
		end
	end
	local last = candidates[#candidates]
	return last.box, last.scale, last.stacked
end

return TouchLayout
