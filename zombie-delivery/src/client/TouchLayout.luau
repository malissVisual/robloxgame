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
function TouchLayout.hint(c: Cluster, boxes: { Box }, W: number, H: number, S: number): (number, number, number)
	local bottom = H - TouchLayout.GAP - 18 * S
	local left, right = TouchLayout.hintSpan(c, boxes, bottom - 96 * S, W)
	if right - left < TouchLayout.MIN_HINT_NARROW then
		local top = math.min(c.thumb.y0, c.jump.y0)
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

return TouchLayout
