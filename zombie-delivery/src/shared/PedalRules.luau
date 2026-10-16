--!strict
-- 9.1, the drive pedals (the owner: "Add a drive pedal to the game"; asked how: "just visible pedals on PC, and on
-- mobile as driving buttons"): the pure part of client/DrivePedals.luau, GAS (tall and narrow) and BRAKE (wider and
-- shorter) at the lower right while you drive your car. No Roblox here: tests/drivepedals_test.luau checks it in the
-- plain Luau CLI on phones and tablets (sideways and upright) and computers; tools/phone-ui/drivepedals.luau runs the
-- real module beside the HUD. The numbers are Config.DrivePedals'. A box is px in the HUD's area (W × H under Roblox's
-- top bar), as client/TouchLayout.luau's; a touch cluster is TouchLayout.cluster's (only its thumb, jump, act and left).
--   PedalRules.mode(device) -> string             "buttons" on a touch screen (held to drive), "show" with the keys or
--                                                 a gamepad (your feet on them; a mouse may hold them too)
--   PedalRules.throttle(gas, brake, speed) -> number   the pedals held → the drive's input (client/Drive.luau
--                                                 setPedal): GAS 1; BRAKE -1 (it brakes, then backs up, as S does); both
--                                                 the brake while the car still rolls (Rolling studs/s, either way), then
--                                                 0 (it stands, never backs up); none 0
--   PedalRules.target(held, foot, sign) -> number how far down a pedal is drawn (0 … 1): all the way while held, else
--                                                 the driver's foot on its side (sign 1 GAS, -1 BRAKE; client/Drive.luau
--                                                 foot: W / S, a gamepad's R2 / L2 part way, the thumbstick)
--   PedalRules.ease(at, target, dt) -> number     the drawn press easing to its target: Press.In a second going down,
--                                                 Press.Out coming back (quick, no bounce); settled: the target itself
--   PedalRules.look(press) -> Look                a press drawn: the face's px down (at scale 1) and its height share (it
--                                                 tips away), the dark veil over it, the red edge's px, lit past half way
--   PedalRules.scales(S, touch) -> { number }     the scales to try, the biggest first (a touch screen: the HUD's S
--                                                 between Touch.Min and Max, every side MinSide px at least; a computer:
--                                                 S × Desk.Scale down to Desk.Min)
--   PedalRules.sizes(scale, captioned?) -> Sizes  GAS and BRAKE (w × h px), the gap between them and the pair's w × h
--                                                 (with a gamepad's caption strip under them when captioned)
--   PedalRules.split(pair, sizes) -> (gas, brake) the two faces in the pair's box: BRAKE left, GAS right (as in a car),
--                                                 their bottoms on the caption strip
--   PedalRules.layout(W, H, S, touch, cluster?, blocks, captioned?) -> (gas, brake, scale, clear, cost)
--       where they go: on a touch screen (with its cluster) at the bottom just left of the touch buttons' column (the
--       EXIT button's), where the right thumb rests; on a computer in the lower right corner. Never on Roblox's jump
--       button, its thumbstick's corner (nor over it: the left thumb's) or the EXIT button, nor on `blocks` (the HUD's
--       groups: the speed and the fuel; a visitor's offer card …), Clear px kept from each; on the screen inside Margin,
--       in its lower part (their top under TopShare of the height) and its right half. The place nearest that spot
--       among those flush against an edge of what is there, a smaller scale counting as ShrinkCost px further a share
--       it loses (at the bottom a little smaller beats big further up). None anywhere: the place that covers the least
--       (the controls Weight × as bad as a HUD group). `clear`: a place clear of everything was found; `cost`: its
--       way from the spot (math.huge when none was clear).
--   PedalRules.cost(W, H, S, touch, cluster?, gas, scale, captioned?) -> number   a placed pair's way from the spot
--       (GAS's box and their scale), as layout counts it: a fresh place with a lower cost is a better one
--   PedalRules.free(gas, brake, blocks) -> boolean   nothing of `blocks` on either (client/DrivePedals.luau keeps
--                                                 them where they are while so: a pedal never jumps from under a finger
--                                                 because a card opened beside it)
--   PedalRules.overlap(a, b) -> boolean           do two boxes share any area (touching edges do not count)

local Config = require(script.Parent.Config)

local PedalRules = {}

export type Box = { x0: number, y0: number, x1: number, y1: number }
export type Cluster = { thumb: Box, jump: Box, act: Box, left: number }
export type Sizes = { gasW: number, gasH: number, brakeW: number, brakeH: number, gap: number, caption: number, w: number, h: number }
export type Look = { down: number, height: number, shade: number, accent: number, lit: boolean }
type Place = { pair: Box, sizes: Sizes, scale: number }

local function cfg(): any
	return Config.DrivePedals
end

function PedalRules.box(x0: number, y0: number, x1: number, y1: number): Box
	return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

function PedalRules.overlap(a: Box, b: Box): boolean
	return math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 0 and math.min(a.y1, b.y1) - math.max(a.y0, b.y0) > 0
end

function PedalRules.free(gas: Box, brake: Box, blocks: { Box }): boolean
	for _, b in blocks do
		if PedalRules.overlap(gas, b) or PedalRules.overlap(brake, b) then
			return false
		end
	end
	return true
end

-- The px two boxes share (0: none).
local function shared(a: Box, b: Box): number
	local w = math.min(a.x1, b.x1) - math.max(a.x0, b.x0)
	local h = math.min(a.y1, b.y1) - math.max(a.y0, b.y0)
	return if w > 0 and h > 0 then w * h else 0
end

function PedalRules.mode(device: string): string
	return if device == "touch" then "buttons" else "show"
end

function PedalRules.throttle(gas: boolean, brake: boolean, speed: number): number
	if gas and brake then
		local rolling = cfg().Rolling
		return if speed > rolling then -1 elseif speed < -rolling then 1 else 0
	elseif gas then
		return 1
	elseif brake then
		return -1
	end
	return 0
end

function PedalRules.target(held: boolean, foot: number, sign: number): number
	if held then
		return 1
	end
	return math.clamp(foot * sign, 0, 1)
end

function PedalRules.ease(at: number, target: number, dt: number): number
	local press = cfg().Press
	local rate = if target > at then press.In else press.Out
	local nextAt = at + (target - at) * math.clamp(rate * dt, 0, 1)
	if math.abs(target - nextAt) < 0.01 then
		return target
	end
	return nextAt
end

function PedalRules.look(press: number): Look
	local p = cfg().Press
	local t = math.clamp(press, 0, 1)
	return {
		down = p.Depth * t,
		height = 1 - p.Squash * t,
		shade = p.Shade * t,
		accent = p.Accent[1] + (p.Accent[2] - p.Accent[1]) * t,
		lit = t >= 0.5,
	}
end

-- The smallest scale a touch screen may take: every side MinSide px.
local function leastTouch(): number
	local c = cfg()
	return c.Touch.MinSide / math.min(c.Gas[1], c.Gas[2], c.Brake[1], c.Brake[2])
end

function PedalRules.scales(S: number, touch: boolean): { number }
	local c = cfg()
	local first: number, least: number, step: number = 0, 0, 0
	if touch then
		least = leastTouch()
		first = math.max(least, math.clamp(S, c.Touch.Min, c.Touch.Max))
		step = c.Touch.Shrink
	else
		least = c.Desk.Min
		first = math.max(least, S * c.Desk.Scale)
		step = c.Desk.Shrink
	end
	local list = { first }
	local s = first - step
	while s > least + 1e-6 do
		table.insert(list, s)
		s -= step
	end
	if first > least + 1e-6 then
		table.insert(list, least)
	end
	return list
end

function PedalRules.sizes(scale: number, captioned: boolean?): Sizes
	local c = cfg()
	local gasW, gasH = c.Gas[1] * scale, c.Gas[2] * scale
	local brakeW, brakeH = c.Brake[1] * scale, c.Brake[2] * scale
	local gap = c.Gap * scale
	local caption = if captioned then c.Caption * scale else 0
	return {
		gasW = gasW,
		gasH = gasH,
		brakeW = brakeW,
		brakeH = brakeH,
		gap = gap,
		caption = caption,
		w = brakeW + gap + gasW,
		h = math.max(gasH, brakeH) + caption,
	}
end

function PedalRules.split(pair: Box, s: Sizes): (Box, Box)
	local bottom = pair.y1 - s.caption
	local gas = PedalRules.box(pair.x1 - s.gasW, bottom - s.gasH, pair.x1, bottom)
	local brake = PedalRules.box(gas.x0 - s.gap - s.brakeW, bottom - s.brakeH, gas.x0 - s.gap, bottom)
	return gas, brake
end

-- Their spot (the pair's lower right corner: by EXIT's column at the bottom of a touch screen, the lower right corner
-- of a computer's) and the left edge they never cross (a touch screen: the thumbstick's corner).
local function spot(W: number, H: number, touch: boolean, cluster: Cluster?): (number, number, number)
	local c = cfg()
	local margin = if touch then c.Margin.Touch else c.Margin.Desk
	if touch and cluster then
		return cluster.left - c.Clear, H - margin, cluster.thumb.x1 + c.Clear
	end
	return W - margin, H - margin, margin
end

-- How far a place is from the spot (px), a smaller scale counting ShrinkCost px further a share of the biggest it loses.
local function costAt(x1: number, y1: number, scale: number, first: number, ax: number, ay: number): number
	return math.abs(x1 - ax) + math.abs(y1 - ay) + (1 - scale / first) * cfg().ShrinkCost
end

function PedalRules.cost(W: number, H: number, S: number, touch: boolean, cluster: Cluster?, gas: Box, scale: number, captioned: boolean?): number
	local ax, ay = spot(W, H, touch, cluster)
	local s = PedalRules.sizes(scale, captioned)
	return costAt(gas.x1, gas.y1 + s.caption, scale, PedalRules.scales(S, touch)[1], ax, ay)
end

function PedalRules.layout(W: number, H: number, S: number, touch: boolean, cluster: Cluster?, blocks: { Box }, captioned: boolean?): (Box, Box, number, boolean, number)
	local c = cfg()
	local clear = c.Clear
	local margin = if touch then c.Margin.Touch else c.Margin.Desk
	local controls: { Box } = {}
	local ax, ay, leftmost = spot(W, H, touch, cluster)
	if touch and cluster then
		controls = { cluster.thumb, cluster.jump, cluster.act }
	end
	local avoid: { Box } = table.clone(controls)
	for _, b in blocks do
		table.insert(avoid, b)
	end
	local top = H * c.TopShare
	local function fits(b: Box): boolean
		if b.x0 < leftmost - 0.01 or b.y0 < top - 0.01 or b.x1 > W - margin + 0.01 or b.y1 > H - margin + 0.01 or b.x1 < W * 0.5 then
			return false
		end
		for _, a in avoid do
			if PedalRules.overlap(b, PedalRules.box(a.x0 - clear, a.y0 - clear, a.x1 + clear, a.y1 + clear)) then
				return false
			end
		end
		return true
	end
	local function clash(b: Box): number
		local cost = 0
		for _, a in controls do
			cost += shared(b, a) * c.Weight
		end
		for _, a in blocks do
			cost += shared(b, a)
		end
		return cost
	end
	local best: Place? = nil
	local bestCost = math.huge
	local fallback: Place? = nil
	local fallbackCost = math.huge
	local scales = PedalRules.scales(S, touch)
	for _, scale in scales do
		local s = PedalRules.sizes(scale, captioned)
		-- the right edges and the bottoms to try: the spot, the screen's edge, flush against every edge of what is there
		local xs, ys = { ax, W - margin }, { ay }
		for _, a in avoid do
			table.insert(xs, a.x0 - clear)
			table.insert(xs, a.x1 + clear + s.w)
			table.insert(ys, a.y0 - clear)
			table.insert(ys, a.y1 + clear + s.h)
		end
		for _, y in ys do
			local y1 = math.clamp(y, math.min(top + s.h, H - margin), H - margin)
			for _, x in xs do
				local x1 = math.clamp(x, math.min(leftmost + s.w, W - margin), W - margin)
				local b = PedalRules.box(x1 - s.w, y1 - s.h, x1, y1)
				local near = costAt(x1, y1, scale, scales[1], ax, ay) -- (at the bottom a little smaller beats big further up)
				if near < bestCost and fits(b) then
					best, bestCost = { pair = b, sizes = s, scale = scale }, near
				end
				local cost = clash(b) + 1e-3 * near
				if cost < fallbackCost then
					fallback, fallbackCost = { pair = b, sizes = s, scale = scale }, cost
				end
			end
		end
	end
	local chosen = (best or fallback) :: Place
	local gas, brake = PedalRules.split(chosen.pair, chosen.sizes)
	return gas, brake, chosen.scale, best ~= nil, if best then bestCost else math.huge
end

return PedalRules
