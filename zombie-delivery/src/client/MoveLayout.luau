--!strict
-- 7.0 review: where the move's own pieces sit on the screen, pure (no Roblox at its top level: tests/movelayout_test.luau
-- checks phones, tablets and computers; tools/phone-ui/movehud.luau runs the real modules at 844 × 390). In the HUD's
-- pixels like client/TouchLayout.luau: W × H the area under Roblox's top bar, S the HUD's scale (Ui.scaleFor).
--   MoveLayout.panel(W, S)                        the move's panel at the top in the middle (client/MovingHud.luau)
--   MoveLayout.strip(panel, S, rowH)              the depot helper's strip under it (client/MoveHelperHud.luau): its
--                                                 top left and its scale
--   MoveLayout.stripClear(b, W, H, chips, keep)   8.4: that strip `b` kept clear of the HUD's chips at the top left
--                                                 (`chips`: the sandbox's money block, the TASKS chip; a small phone,
--                                                 667 … 780 px wide, has them under its ends): shifted right just past
--                                                 them while it stays on the screen (GAP from its edge), off them and
--                                                 off `keep` (the touch controls), else just under them in its place
--                                                 across, else where it was. Returns `b` itself when nothing is in its
--                                                 way (every screen 844 px wide or more)
--   MoveLayout.list(W, H, S, touch, under, playerList?, floor?)   the move's list (L … client/MovingHud.luau): on a
--                                                 computer at the right under `under` (the lowest of the move's top
--                                                 blocks) and under Roblox's player list when that is in the way, down to
--                                                 `floor`; on a touch screen a modal sheet the whole height in the middle,
--                                                 at least SHEET_SCALE big (it covers the touch buttons while it is open:
--                                                 a tap beside it closes it). Returns (box, scale, sheet).
--   MoveLayout.chatButton(W, H, S, panel, blocks) the quick chat's touch button (client/QuickChat.luau), at least
--                                                 MIN_TOUCH: left of the panel at the top, else right of it, a row lower,
--                                                 else under it: the first on the screen and clear of `blocks` (the touch
--                                                 buttons, the HUD's groups, the move's own top blocks)
--   MoveLayout.ring(W, H, S, touch, radius, pillW, pillH)   the quick chat's ring: (scale, radius, line width): on
--                                                 a touch screen its lines at least MIN_TOUCH high, the ring shrunk (then
--                                                 its lines narrowed) to stay on a short or narrow screen, its lines never
--                                                 on each other
--   MoveLayout.overlap / MoveLayout.inside        boxes
--   MoveLayout.gripCheck(W, H, S, touch, blocks, sizes)   8.1 grip: the timing check's widget (client/CarryGripUi.luau,
--                                                 CHECK_W × CHECK_H at scale 1) and, on a touch screen, its TAP button
--                                                 (a square, sizes.tap × S, at least sizes.tapMin): the button at the
--                                                 right over the touch buttons (over FIRE, over the column, beside the
--                                                 column, a row higher); the widget clear of `blocks` (the HUD's groups,
--                                                 the move's top blocks with the sandbox's guide line, the quick chat's
--                                                 button, the move's list), the touch buttons, the thumbstick's corner,
--                                                 the jump button and the TAP button, on the screen, at the place
--                                                 nearest to the preferred one (in the middle, its top 60% down: under
--                                                 the character) among the preferred lines and the places flush against
--                                                 an edge of what is there (a short phone: beside its bottom bar), at
--                                                 sizes.scale (or the HUD's S), then smaller down to sizes.min. When no
--                                                 place is clear even then, the one that covers the least
--                                                 (MoveLayout.clash; the touch controls and the TAP button
--                                                 CONTROL_WEIGHT × as bad as a HUD group). Returns (widget box, its
--                                                 scale, the TAP button's box or nil).
--   MoveLayout.tapSpots(W, H, S, size)            the TAP button's places in order (a size × size square each)
--   MoveLayout.clash(b, W, H, blocks)             how much of b lies on `blocks` or off the screen (px², off the screen
--                                                 counted twice): 0 when it is clear

local TouchLayout = require(script.Parent.TouchLayout)

export type Box = TouchLayout.Box

local MoveLayout = {}

MoveLayout.PANEL_W = 380
MoveLayout.PANEL_H = 118
MoveLayout.TOP = 8
MoveLayout.LIST_W = 320
MoveLayout.SHEET_SCALE = 0.75 -- (as the planning's card: Config.MoveRoles.Lobby.TouchScale)
MoveLayout.SHEET_MARGIN = 16
MoveLayout.STRIP_GAP = 6
MoveLayout.CHAT = 48
MoveLayout.MIN_TOUCH = 44 -- (Ui.MinTouch)
MoveLayout.GAP = 8
MoveLayout.PILL_MIN_W = 120 -- the quick chat's lines at their narrowest (a phone upright: two lines of words)
MoveLayout.PLAYER_LIST_W = 370 -- Roblox's player list on a computer (client/Hud.luau's layout says the same)

local box = TouchLayout.box

function MoveLayout.overlap(a: Box, b: Box): boolean
	return TouchLayout.overlap(a, b)
end

function MoveLayout.inside(b: Box, W: number, H: number): boolean
	return b.x0 >= -0.5 and b.y0 >= -0.5 and b.x1 <= W + 0.5 and b.y1 <= H + 0.5
end

function MoveLayout.panel(W: number, S: number): Box
	local w, h = MoveLayout.PANEL_W * S, MoveLayout.PANEL_H * S
	local x0 = (W - w) / 2
	return box(x0, MoveLayout.TOP, x0 + w, MoveLayout.TOP + h)
end

function MoveLayout.strip(panel: Box, S: number, rowH: number): Box
	local y0 = panel.y1 + MoveLayout.STRIP_GAP * S
	local cx = (panel.x0 + panel.x1) / 2
	local w = MoveLayout.PANEL_W * S
	return box(cx - w / 2, y0, cx + w / 2, y0 + (26 + rowH + 8) * S)
end

function MoveLayout.stripClear(b: Box, W: number, H: number, chips: { Box }, keep: { Box }): Box
	local gap = MoveLayout.GAP
	local hit, right, below = false, -math.huge, -math.huge
	for _, chip in chips do
		hit = hit or TouchLayout.overlap(b, chip)
		if chip.y0 < b.y1 and chip.y1 > b.y0 then
			right = math.max(right, chip.x1) -- (beside it: what a shift right has to pass)
		end
		if chip.x0 < b.x1 and chip.x1 > b.x0 then
			below = math.max(below, chip.y1) -- (over or under it: what it goes under)
		end
	end
	if not hit then
		return b
	end
	local function free(c: Box): boolean
		if c.x0 < gap or c.x1 > W - gap or c.y1 > H - gap then
			return false
		end
		for _, other in chips do
			if TouchLayout.overlap(c, other) then
				return false
			end
		end
		for _, other in keep do
			if TouchLayout.overlap(c, other) then
				return false
			end
		end
		return true
	end
	local dx = right + gap - b.x0
	local shifted = box(b.x0 + dx, b.y0, b.x1 + dx, b.y1)
	if free(shifted) then
		return shifted
	end
	local dy = below + gap - b.y0
	local under = box(b.x0, b.y0 + dy, b.x1, b.y1 + dy)
	return if free(under) then under else b
end

function MoveLayout.list(W: number, H: number, S: number, touch: boolean, under: number, playerList: Box?, floor: number?): (Box, number, boolean)
	if touch then
		local margin = MoveLayout.SHEET_MARGIN
		local scale = math.max(S, MoveLayout.SHEET_SCALE)
		-- (never wider than the screen less its margins; a very narrow one: smaller)
		scale = math.min(scale, math.max(S, (W - 2 * margin) / MoveLayout.LIST_W))
		local width = math.min(MoveLayout.LIST_W * scale, W - 2 * margin)
		local x0 = (W - width) / 2
		return box(x0, MoveLayout.TOP, x0 + width, H - MoveLayout.TOP), scale, true
	end
	local x1 = W - 16
	local x0 = x1 - MoveLayout.LIST_W * S
	local y0 = under + 10
	if playerList and playerList.x0 < x1 and playerList.x1 > x0 then
		y0 = math.max(y0, playerList.y1 + MoveLayout.GAP)
	end
	local y1 = floor or (H - 120)
	if y1 - y0 < 160 * S then
		y1 = math.min(H - MoveLayout.TOP, y0 + 160 * S)
	end
	return box(x0, y0, x1, y1), S, false
end

function MoveLayout.chatButton(W: number, H: number, S: number, panel: Box, blocks: { Box }): Box
	local size = math.max(MoveLayout.MIN_TOUCH, MoveLayout.CHAT * S)
	local gap = MoveLayout.GAP
	local row = size + gap
	local candidates = {
		box(panel.x0 - gap - size, panel.y0, panel.x0 - gap, panel.y0 + size), -- left of the panel
		box(panel.x1 + gap, panel.y0, panel.x1 + gap + size, panel.y0 + size), -- right of it
		box(panel.x0 - gap - size, panel.y0 + row, panel.x0 - gap, panel.y0 + row + size), -- a row lower
		box(panel.x1 + gap, panel.y0 + row, panel.x1 + gap + size, panel.y0 + row + size),
		box(panel.x0, panel.y1 + gap, panel.x0 + size, panel.y1 + gap + size), -- under its left end
		box(panel.x1 - size, panel.y1 + gap, panel.x1, panel.y1 + gap + size), -- under its right end
	}
	for _, c in candidates do
		if MoveLayout.inside(c, W, H) then
			local clear = true
			for _, b in blocks do
				if TouchLayout.overlap(c, b) then
					clear = false
					break
				end
			end
			if clear then
				return c
			end
		end
	end
	return candidates[1]
end

function MoveLayout.ring(W: number, H: number, S: number, touch: boolean, radius: number, pillW: number, pillH: number): (number, number, number)
	local scale = if touch then math.max(S, MoveLayout.MIN_TOUCH / pillH) else S
	local margin = MoveLayout.GAP
	-- never on each other: neighbours 60° apart stand r / 2 apart up and down (more than a line's height)
	local least = 2 * pillH + 2
	-- on the screen: the ring's height 2 r + a line, its width 2 r + a line, a margin all round
	local r = math.min(radius, ((H - 2 * margin) / scale - pillH) / 2)
	local width = pillW
	local fitW = ((W - 2 * margin) / scale - width) / 2
	if fitW < r then
		-- a narrow screen (a phone upright): the ring narrower first, then its lines (their words wrap)
		r = math.max(least, math.min(r, fitW))
		width = math.max(MoveLayout.PILL_MIN_W, math.min(pillW, (W - 2 * margin) / scale - 2 * r))
	end
	if r < least then
		-- too small a screen for a finger's lines at this size: the ring smaller, so it stays whole
		r = least
		scale = math.min(scale, (H - 2 * margin) / (2 * r + pillH), (W - 2 * margin) / (2 * r + width))
	end
	return scale, r, width
end

-- 8.1 grip ------------------------------------------------------------------------------------------------------------

MoveLayout.CHECK_W = 240
MoveLayout.CHECK_H = 96
MoveLayout.MARGIN = 16
MoveLayout.CONTROL_WEIGHT = 4 -- 7.1 review: covering a touch control (or the TAP button) is this much worse than a HUD group

export type GripSizes = { tap: number, tapMin: number, scale: number, min: number }

local function clearOf(b: Box, W: number, H: number, blocks: { Box }): boolean
	if not MoveLayout.inside(b, W, H) then
		return false
	end
	for _, other in blocks do
		if TouchLayout.overlap(b, other) then
			return false
		end
	end
	return true
end

-- The area two boxes share (px²; touching edges: 0).
local function shared(a: Box, b: Box): number
	return math.max(0, math.min(a.x1, b.x1) - math.max(a.x0, b.x0)) * math.max(0, math.min(a.y1, b.y1) - math.max(a.y0, b.y0))
end

function MoveLayout.clash(b: Box, W: number, H: number, blocks: { Box }): number
	local area = (b.x1 - b.x0) * (b.y1 - b.y0)
	local total = 2 * math.max(0, area - shared(b, box(0, 0, W, H))) -- (off the screen: out of reach, counted twice)
	for _, other in blocks do
		total += shared(b, other)
	end
	return total
end

function MoveLayout.tapSpots(W: number, H: number, S: number, size: number): { Box }
	local gap = MoveLayout.GAP
	local c = TouchLayout.cluster(W, H, S)
	local wide = 2 * gap -- (beside the column: a little farther from PUT DOWN)
	return {
		box(c.fire.x1 - size, c.top - gap - size, c.fire.x1, c.top - gap), -- over FIRE
		box(c.left, c.top - gap - size, c.left + size, c.top - gap), -- over the column
		box(c.left - wide - size, c.act.y0, c.left - wide, c.act.y0 + size), -- beside the column
		box(c.left - wide - size, c.top - gap - size, c.left - wide, c.top - gap), -- beside it, higher
		box(c.fire.x1 - size, c.top - 2 * (gap + size), c.fire.x1, c.top - 2 * gap - size), -- a row higher
	}
end

-- The widget's places at w × h: flush against an edge of what is there (a gap off it), or on one of the preferred
-- lines (its top 60%, 66% or 54% down, its bottom 42% down, its middle in the middle), centred or beside a block;
-- (xs, ys) of their top left corners. The edges counted: the blocks that reach into the middle band of the screen.
local function checkPlaces(W: number, H: number, w: number, h: number, avoid: { Box }): ({ number }, { number })
	local gap = MoveLayout.GAP
	local xs = { W / 2 - w / 2 }
	local ys = { H * 0.6, H * 0.66, H * 0.54, H * 0.42 - h, H / 2 - h / 2 }
	for _, b in avoid do
		if b.y1 > H * 0.2 and b.y0 < H * 0.9 then
			table.insert(xs, b.x1 + gap)
			table.insert(xs, b.x0 - gap - w)
		end
		if b.x1 > W * 0.15 and b.x0 < W * 0.85 then
			table.insert(ys, b.y1 + gap)
			table.insert(ys, b.y0 - gap - h)
		end
	end
	return xs, ys
end

function MoveLayout.gripCheck(W: number, H: number, S: number, touch: boolean, blocks: { Box }, sizes: GripSizes): (Box, number, Box?)
	local gap, margin = MoveLayout.GAP, MoveLayout.MARGIN
	local avoid = table.clone(blocks)
	local controls: { Box } = {} -- (the touch buttons, the thumbstick's corner, the jump button, then TAP: worse to cover)
	-- how bad a place that is not clear is: what it covers, the controls CONTROL_WEIGHT × (the least is the fallback)
	local function cost(b: Box): number
		local total = MoveLayout.clash(b, W, H, avoid)
		for _, control in controls do
			total += (MoveLayout.CONTROL_WEIGHT - 1) * shared(b, control)
		end
		return total
	end
	local tap: Box? = nil
	if touch then
		local c = TouchLayout.cluster(W, H, S)
		for _, b in TouchLayout.buttons(c) do
			table.insert(controls, b)
		end
		table.insert(controls, c.thumb)
		table.insert(controls, c.jump)
		for _, b in controls do
			table.insert(avoid, b)
		end
		local size = math.max(sizes.tapMin, sizes.tap * S)
		-- the first clear place; none clear (a small screen, the HUD's groups in the way): the one that covers the least
		local best, bestCost = nil :: Box?, math.huge
		for _, candidate in MoveLayout.tapSpots(W, H, S, size) do
			if clearOf(candidate, W, H, avoid) then
				tap = candidate
				break
			end
			local bad = cost(candidate)
			if bad < bestCost then
				best, bestCost = candidate, bad
			end
		end
		local found = (tap or best) :: Box
		tap = found
		-- (the widget keeps a gap from it too)
		local around = box(found.x0 - gap, found.y0 - gap, found.x1 + gap, found.y1 + gap)
		table.insert(avoid, around)
		table.insert(controls, around)
	end
	-- the widget: at each scale (down to sizes.min) the clear place nearest to the preferred one (in the middle, its top
	-- 60% down: under the character); none clear at the smallest: the one that covers the least (then the nearest)
	local scale = math.max(S, sizes.scale)
	local least = math.min(scale, sizes.min)
	while true do
		local w, h = MoveLayout.CHECK_W * scale, MoveLayout.CHECK_H * scale
		local px, py = W / 2, H * 0.6 + h / 2
		local xs, ys = checkPlaces(W, H, w, h, avoid)
		local best: Box? = nil
		local bestNear = math.huge
		for _, y in ys do
			local y0 = math.clamp(y, margin, math.max(margin, H - margin - h))
			for _, x in xs do
				local x0 = math.clamp(x, margin, math.max(margin, W - margin - w))
				local near = math.abs(x0 + w / 2 - px) + math.abs(y0 + h / 2 - py)
				if near < bestNear then
					local b = box(x0, y0, x0 + w, y0 + h)
					if clearOf(b, W, H, avoid) then
						best, bestNear = b, near
					end
				end
			end
		end
		if best then
			return best, scale, tap
		end
		if scale <= least + 1e-6 then
			local fallback, fallbackCost = box(px - w / 2, py - h / 2, px + w / 2, py + h / 2), math.huge
			for _, y in ys do
				local y0 = math.clamp(y, margin, math.max(margin, H - margin - h))
				for _, x in xs do
					local x0 = math.clamp(x, margin, math.max(margin, W - margin - w))
					local b = box(x0, y0, x0 + w, y0 + h)
					local bad = cost(b) + 1e-3 * (math.abs(x0 + w / 2 - px) + math.abs(y0 + h / 2 - py))
					if bad < fallbackCost then
						fallback, fallbackCost = b, bad
					end
				end
			end
			return fallback, scale, tap
		end
		scale = math.max(least, scale * 0.88)
	end
end

return MoveLayout
