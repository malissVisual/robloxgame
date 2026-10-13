--!strict
-- 7.0 review: where the move's own pieces sit on the screen, pure (no Roblox at its top level: tests/movelayout_test.luau
-- checks phones, tablets and computers; tools/phone-ui/movehud.luau runs the real modules at 844 × 390). In the HUD's
-- pixels like client/TouchLayout.luau: W × H the area under Roblox's top bar, S the HUD's scale (Ui.scaleFor).
--   MoveLayout.panel(W, S)                        the move's panel at the top in the middle (client/MovingHud.luau)
--   MoveLayout.strip(panel, S, rowH)              the depot helper's strip under it (client/MoveHelperHud.luau): its
--                                                 top left and its scale
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

return MoveLayout
