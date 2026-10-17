--!strict
-- 10.x THE MAP, the drawing (Config.SandboxMapUi's colours; the maths shared/SandboxMapRules.luau; the data
-- client/SandboxMapData.luau): client/SandboxMapUi.luau's big map and client/SandboxMiniMap.luau's minimap draw with
-- it, in the game's contract look (client/Theme.luau: a charcoal ground, small white caps on dark pills, fine lines).
-- A canvas is drawn once (an open, a run): every piece a plain Frame or TextLabel, siblings ordered by ZIndex (the
-- ground 1, the buildings and the rooms 2 - 4, the words 6, the markers 8 - 11); the markers are pooled and only moved.
--   * The lobby (SandboxMap.Lobby, north up): the meadow in its hedge, the plaza and the fountain, the trees and the
--     lamps, the four plots with their warehouses at their level (WarehouseLayout.site) and their UPGRADES desks (yours
--     outlined in gold: YOUR WAREHOUSE, the others' their owner's name or FREE), the PAINT shop, the TOP MOVERS board,
--     the ZDC DISPATCH (and the Auction House while Config.Auction.On), the six portals: the gate in its house's colours
--     (Config.Runs.Portal.Styles), the pad in its state's colour (Free, Waiting, InUse) and its name with its state's
--     line beside it on the plaza's side (a button: onPortal). The words are placed one by one, each at the first of its
--     spots that is on the map and on no other (the portals' first; a map too crowded for their lines: their names).
--   * A run's house (its plan, the front door at the bottom): the yard's strip (its grass, its asphalt), the house's
--     walls (its box) with the rooms' floors in them (their kinds' colours, their names where they fit), the doorways
--     (the ways out green: FRONT DOOR, BACK DOOR), the windows, the fixtures that stand in the way.
--   * The markers (marks): the loot (a dot in its tier's colour, a dark ring round it; an uncarried Epic or Legendary
--     pulses: a looping tween, no frame loop), the dangers (their icons: Config.SandboxMapUi.Danger, a hazard's by its
--     Kind), the truck, the zombies (red dots), the helpers (orange) and the party or the players (gold / blue) with
--     their names, you a white ▲ turned your way (on top). A pinned one (out of the yard's strip) is drawn faded.
--   SandboxMapDraw.lobby(parent, frame, u, w, h, onPortal?, plots?) -> Canvas   a w × h px canvas (plots: SandboxMapData's)
--   SandboxMapDraw.house(parent, frame, u, w, h, place, mini?) -> Canvas        (the minimap's: no names, its own size)
--   SandboxMapDraw.portals(canvas, states, now)      the pads' colours and the lines (a look)
--   SandboxMapDraw.marks(canvas, people, loot, dangers, truck)   the markers (a look)
--   SandboxMapDraw.width(text, size, font) -> px     a text's width (TextService)
-- Presentation only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SandboxMap = require(Shared.SandboxMap)
local Rules = require(Shared.SandboxMapRules)
local WarehouseLayout = require(Shared.WarehouseLayout)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local SandboxMapDraw = {}

local C = Config.SandboxMapUi
local K = Theme.Contract
local R = Config.Runs

export type Canvas = {
	root: Frame,
	frame: Rules.Frame,
	u: number,
	mini: boolean,
	portals: { [string]: { pad: Frame, line: TextLabel, name: TextLabel, key: string } },
	pool: { people: { any }, loot: { any }, danger: { any }, truck: any?, me: any? },
	onPortal: ((house: string) -> ())?,
	placed: { { x0: number, y0: number, x1: number, y1: number } }, -- (the lobby's words placed: none on another)
	long: boolean, -- (a roomy lobby: its portals' lines with who is there; a small one's short: the side column says who)
	portalWords: { { name: TextLabel, line: TextLabel, spots: { { number } } } }, -- (the portals' words, placed together)
	lines: boolean, -- (the portals' state lines on the map: false when they would cover each other)
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function color(name: string): Color3
	return rgb(C.Colors[name] or { 255, 0, 255 })
end

function SandboxMapDraw.width(text: string, size: number, font: Enum.Font): number
	local ok, bounds = pcall(function(): Vector2
		return TextService:GetTextSize(text, size, font, Vector2.new(4000, 400))
	end)
	return math.ceil(if ok and bounds then bounds.X else #text * size * 0.6) + 2
end

local function block(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number, c: Color3, z: number, transparency: number?): Frame
	return Ui.make("Frame", {
		Name = name,
		Position = UDim2.fromOffset(math.floor(x0 + 0.5), math.floor(y0 + 0.5)),
		Size = UDim2.fromOffset(math.max(1, math.floor(x1 - x0 + 0.5)), math.max(1, math.floor(y1 - y0 + 0.5))),
		BackgroundColor3 = c,
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
end

-- A box of content studs on the canvas.
local function area(canvas: Canvas, name: string, x0: number, z0: number, x1: number, z1: number, c: Color3, z: number, transparency: number?): Frame
	local px0, py0, px1, py1 = Rules.rectOn(canvas.frame, x0, z0, x1, z1)
	return block(canvas.root, name, px0, py0, px1, py1, c, z, transparency)
end

local function round(frame: Frame)
	Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, frame)
end

local function edge(frame: GuiObject, c: Color3, thickness: number, transparency: number?)
	Ui.make("UIStroke", { Color = c, Thickness = thickness, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
end

-- Words on a dark pill (or bare), sized to them; anchor as a Roblox AnchorPoint at (x, y).
local function words(parent: Instance, name: string, text: string, x: number, y: number, ax: number, ay: number, size: number, c: Color3, z: number, pill: boolean, bold: boolean?): TextLabel
	local font = if bold == false then Theme.Font else Theme.HeadingFont
	local w = SandboxMapDraw.width(text, size, font) + (if pill then 10 else 2)
	local h = size + (if pill then 6 else 2)
	local label = Ui.make("TextLabel", {
		Name = name,
		Text = text,
		TextSize = size,
		Font = font,
		TextColor3 = c,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = if pill then 0.22 else 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(w, h),
		Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5)),
		AnchorPoint = Vector2.new(ax, ay),
		ZIndex = z,
	}, parent)
	if pill then
		Ui.make("UICorner", { CornerRadius = UDim.new(0, 4) }, label)
	end
	return label
end

local function newCanvas(parent: Instance, frame: Rules.Frame, u: number, mini: boolean, w: number, h: number): Canvas
	local root = Ui.make("Frame", {
		Name = "Canvas",
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = color("Back"),
		BackgroundTransparency = if mini then 1 else 0,
		BorderSizePixel = 0,
		ClipsDescendants = not mini,
	}, parent)
	return { root = root, frame = frame, u = u, mini = mini, portals = {}, pool = { people = {}, loot = {}, danger = {}, truck = nil, me = nil }, onPortal = nil, placed = {}, long = frame.scale >= C.LongScale, portalWords = {}, lines = true }
end

-- ── The lobby ────────────────────────────────────────────────────────────────

-- Words where they are clear: the first of `spots` ({ x, y, ax, ay } px: an AnchorPoint at that point) where the labels
-- (stacked, 2 px apart, aligned by ax) stay in the canvas and off every label placed before; none: the first spot when
-- they must show, else they hide. The portals go first, then your warehouse, then the rest.
type Spot = { number }
local function settle(canvas: Canvas, labels: { TextLabel }, spots: { Spot }, must: boolean): boolean
	local w, h = 0, 0
	for _, l in labels do
		w = math.max(w, l.Size.X.Offset)
		h += l.Size.Y.Offset
	end
	h += 2 * (#labels - 1)
	local W, H = canvas.root.Size.X.Offset, canvas.root.Size.Y.Offset
	local chosen: Spot? = nil
	for _, s in spots do
		local x0, y0 = s[1] - s[3] * w, s[2] - s[4] * h
		local clear = x0 >= 2 and y0 >= 2 and x0 + w <= W - 2 and y0 + h <= H - 2
		if clear then
			for _, other in canvas.placed do
				if math.min(x0 + w, other.x1) - math.max(x0, other.x0) > 0 and math.min(y0 + h, other.y1) - math.max(y0, other.y0) > 0 then
					clear = false
					break
				end
			end
		end
		if clear then
			chosen = s
			break
		end
	end
	if not chosen then
		if not must then
			for _, l in labels do
				l.Visible = false
			end
			return false
		end
		chosen = spots[1]
	end
	local s = chosen :: Spot
	local x0, y0 = s[1] - s[3] * w, s[2] - s[4] * h
	local y = y0
	local align = if s[3] == 0 then Enum.TextXAlignment.Left elseif s[3] == 1 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
	for _, l in labels do
		l.AnchorPoint = Vector2.new(s[3], 0)
		l.Position = UDim2.fromOffset(math.floor(x0 + s[3] * w + 0.5), math.floor(y + 0.5))
		l.TextXAlignment = align -- (a line wider than its words keeps them by its side)
		y += l.Size.Y.Offset + 2
	end
	table.insert(canvas.placed, { x0 = x0, y0 = y0, x1 = x0 + w, y1 = y0 + h })
	return true
end

-- A box of content studs as px (x0, y0, x1, y1) and its middle.
local function pxBox(canvas: Canvas, x0: number, z0: number, x1: number, z1: number): (number, number, number, number, number, number)
	local a, b, c, d = Rules.rectOn(canvas.frame, x0, z0, x1, z1)
	return a, b, c, d, (a + c) / 2, (b + d) / 2
end

-- Spots round a px box: right of it, left, under, over (astride its middle), then beside its corners.
local function around(x0: number, y0: number, x1: number, y1: number, gap: number): { Spot }
	local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	return {
		{ x1 + gap, cy, 0, 0.5 },
		{ x0 - gap, cy, 1, 0.5 },
		{ cx, y1 + gap, 0.5, 0 },
		{ cx, y0 - gap, 0.5, 1 },
		{ x1 + gap, y0, 0, 0 },
		{ x1 + gap, y1, 0, 1 },
		{ x0 - gap, y0, 1, 0 },
		{ x0 - gap, y1, 1, 1 },
	}
end

local function portal(canvas: Canvas, p: SandboxMap.Portal, size: number)
	local style = R.Portal.Styles[p.house] or R.Portal.Styles.sandbox_house
	local foot = area(canvas, `Portal_{p.house}`, p.foot.x0, p.foot.z0, p.foot.x1, p.foot.z1, rgb(style.wall), 3)
	edge(foot, rgb(style.trim), 2)
	local pad = area(canvas, `Pad_{p.house}`, p.pad.x0, p.pad.z0, p.pad.x1, p.pad.z1, rgb(R.Portal.Free), 3)
	edge(pad, K.charcoal, 1, 0.3)
	-- its name (on a dark pill) over its state's line (its colour's words with a dark edge) on the plaza's side of the pad
	-- (the way the gate looks), else on another side where they are clear; the line's room is kept for the longest
	-- words it says (a roomy map's: LineEm × its size, cut at their end past it; a small map's short line: FREE,
	-- STARTING IN 10, IN USE · NIGHTMARE)
	local small = Rules.textSize(C.Text.Small, canvas.u)
	local name = words(canvas.root, `PortalName_{p.house}`, string.upper(p.name), 0, 0, 0, 0, size, K.text, 6, true)
	local line = words(canvas.root, `PortalLine_{p.house}`, if canvas.long then "FREE · WALK ONTO THE PAD" else "FREE", 0, 0, 0, 0, small, rgb(R.Portal.Free), 6, false, true)
	line.TextStrokeColor3 = K.charcoal
	line.TextStrokeTransparency = 0.15
	local room = math.floor(small * C.LineEm + 2)
	if not canvas.long then
		room = SandboxMapDraw.width("STARTING IN 10", small, Theme.HeadingFont) + 2
		for _, def in R.Difficulties do
			room = math.max(room, SandboxMapDraw.width(`IN USE · {string.upper(def.name)}`, small, Theme.HeadingFont) + 2)
		end
	end
	line.Size = UDim2.fromOffset(math.max(line.Size.X.Offset, room), line.Size.Y.Offset)
	line.TextTruncate = Enum.TextTruncate.AtEnd
	local x0, y0, x1, y1, cx, cy = pxBox(canvas, p.pad.x0, p.pad.z0, p.pad.x1, p.pad.z1)
	local yaw = p.yaw % 360
	local gap = 3
	local right: { Spot } = { { x1 + gap, cy, 0, 0.5 }, { x1 + gap, y1, 0, 0 }, { x1 + gap, y0, 0, 1 } }
	local left: { Spot } = { { x0 - gap, cy, 1, 0.5 }, { x0 - gap, y1, 1, 0 }, { x0 - gap, y0, 1, 1 } }
	local over: { Spot } = { { cx, y0 - gap, 0.5, 1 }, { x1, y0 - gap, 0, 1 }, { x0, y0 - gap, 1, 1 } }
	local under: { Spot } = { { cx, y1 + gap, 0.5, 0 }, { x1, y1 + gap, 0, 0 }, { x0, y1 + gap, 1, 0 } }
	local order: { { Spot } } = if yaw == 270 then { right, over, under, left } elseif yaw == 90 then { left, over, under, right } elseif yaw == 180 then { under, right, left, over } else { over, right, left, under }
	local spots: { Spot } = {}
	for _, side in order do
		for _, spot in side do
			table.insert(spots, spot)
		end
	end
	table.insert(canvas.portalWords, { name = name, line = line, spots = spots })
	canvas.portals[p.house] = { pad = pad, line = line, name = name, key = "" }
	-- a button over the gate and the pad: a click or a tap guides you there
	local onPortal = canvas.onPortal
	if onPortal then
		local bx0, by0, bx1, by1 = Rules.rectOn(canvas.frame, math.min(p.foot.x0, p.pad.x0), math.min(p.foot.z0, p.pad.z0), math.max(p.foot.x1, p.pad.x1), math.max(p.foot.z1, p.pad.z1))
		local least = if Ui.touchLayout() then Ui.MinTouch else 24
		local mx, my = (bx0 + bx1) / 2, (by0 + by1) / 2
		local w, h = math.max(least, bx1 - bx0), math.max(least, by1 - by0)
		local button = Ui.make("TextButton", {
			Name = `PortalButton_{p.house}`,
			Text = "",
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(math.ceil(w), math.ceil(h)),
			Position = UDim2.fromOffset(math.floor(mx - w / 2 + 0.5), math.floor(my - h / 2 + 0.5)),
			ZIndex = 7,
		}, canvas.root)
		button:SetAttribute("Portal", p.house)
		button.Activated:Connect(function()
			onPortal(p.house)
		end)
	end
end

type Named = { labels: { TextLabel }, spots: { Spot }, must: boolean }

function SandboxMapDraw.lobby(parent: Instance, frame: Rules.Frame, u: number, w: number, h: number, onPortal: ((string) -> ())?, plots: { any }?): Canvas
	local canvas = newCanvas(parent, frame, u, false, w, h)
	canvas.onPortal = onPortal
	local L = SandboxMap.Lobby
	local b = L.bounds
	local label = Rules.textSize(C.Text.Label, u)
	local small = Rules.textSize(C.Text.Small, u)
	area(canvas, "Hedge", b.x0, b.z0, b.x1, b.z1, color("Hedge"), 1)
	local inset = L.hedge + 1.3
	area(canvas, "Meadow", b.x0 + inset, b.z0 + inset, b.x1 - inset, b.z1 - inset, color("Meadow"), 1)
	local plaza = L.plaza
	area(canvas, "Plaza", plaza.x0, plaza.z0, plaza.x1, plaza.z1, color("Plaza"), 2)
	local fountain = area(canvas, "Fountain", L.fountain.x - L.fountain.r, L.fountain.z - L.fountain.r, L.fountain.x + L.fountain.r, L.fountain.z + L.fountain.r, color("Water"), 3)
	round(fountain)
	edge(fountain, rgb({ 150, 146, 140 }), 2)
	for n, t in L.trees do
		local tree = area(canvas, `Tree{n}`, t.x - 4, t.z - 4, t.x + 4, t.z + 4, color("Tree"), 2)
		round(tree)
	end
	for n, l in L.lamps do
		local lamp = area(canvas, `Lamp{n}`, l.x - 0.8, l.z - 0.8, l.x + 0.8, l.z + 0.8, color("Lamp"), 3)
		round(lamp)
	end
	-- the buildings
	local views: { [number]: any } = {}
	local given: { any } = plots or {}
	for _, v in given do
		views[v.id] = v
	end
	local later: { Named } = {}
	local mineFirst: Named? = nil
	for _, plot in SandboxMap.Plots do
		local view = views[plot.id] or { id = plot.id, mine = false, level = WarehouseLayout.levelOf(plot) }
		local r = plot.rect
		local ground = area(canvas, `Plot{plot.id}`, r.x0, r.z0, r.x1, r.z1, color("Plot"), 2, 0.25)
		local site = WarehouseLayout.site(plot, view.level) or plot
		local wh = site.warehouse
		area(canvas, `Warehouse{plot.id}`, wh.x - wh.sx / 2, wh.z - wh.sz / 2, wh.x + wh.sx / 2, wh.z + wh.sz / 2, color("Warehouse"), 3)
		local desk = WarehouseLayout.terminal(site)
		area(canvas, `Desk{plot.id}`, desk.x - 2.5, desk.z - 2, desk.x + 2.5, desk.z + 2, color("Desk"), 4)
		-- its name on the bay in front of its door, else in the hall (yours in gold over two lines, its UPGRADES desk
		-- named; another's its owner's, else FREE)
		local cx = Rules.toMap(frame, (r.x0 + r.x1) / 2, 0)
		local _, bayY = Rules.toMap(frame, 0, (wh.z + wh.sz / 2 + r.z1) / 2)
		local _, hallY = Rules.toMap(frame, 0, wh.z)
		local spots = { { cx, bayY, 0.5, 0.5 }, { cx, hallY, 0.5, 0.5 } }
		if view.mine then
			edge(ground, color("Yours"), 2)
			local top = words(canvas.root, `PlotName{plot.id}`, "YOUR", 0, 0, 0, 0, label, color("Yours"), 6, true)
			local bottom = words(canvas.root, `PlotName{plot.id}b`, "WAREHOUSE", 0, 0, 0, 0, label, color("Yours"), 6, true)
			top.Size = UDim2.fromOffset(bottom.Size.X.Offset, top.Size.Y.Offset)
			mineFirst = { labels = { top, bottom }, spots = spots, must = true }
			local dx0, dy0, dx1, dy1 = pxBox(canvas, desk.x - 2.5, desk.z - 2, desk.x + 2.5, desk.z + 2)
			local up = words(canvas.root, "Upgrades", "UPGRADES", 0, 0, 0, 0, small, color("Desk"), 6, true)
			table.insert(later, 1, { labels = { up }, spots = around(dx0, dy0, dx1, dy1, 2), must = false })
		else
			local owner = if type(view.owner) == "string" then string.upper(view.owner) else "FREE"
			local tag = words(canvas.root, `PlotName{plot.id}`, owner, 0, 0, 0, 0, small, K.secondary, 6, true)
			local room = ground.Size.X.Offset - 4
			if tag.Size.X.Offset > room then
				tag.Size = UDim2.fromOffset(room, tag.Size.Y.Offset)
				tag.TextTruncate = Enum.TextTruncate.AtEnd
			end
			table.insert(later, { labels = { tag }, spots = spots, must = false })
		end
	end
	-- the shops and the desks (their names before the other plots')
	local shops = L.shops
	local function shop(name: string, rect: SandboxMap.Rect, c: Color3, text: string)
		area(canvas, name, rect.x0, rect.z0, rect.x1, rect.z1, c, 3)
		local x0, y0, x1, y1 = pxBox(canvas, rect.x0, rect.z0, rect.x1, rect.z1)
		local tag = words(canvas.root, `{name}Name`, text, 0, 0, 0, 0, small, K.text, 6, true)
		table.insert(later, 2, { labels = { tag }, spots = around(x0, y0, x1, y1, 3), must = false })
	end
	shop("Paint", shops.paint.rect, color("Paint"), "PAINT")
	shop("Leaders", shops.leaders.rect, color("Leaders"), "TOP MOVERS")
	local s = L.dispatch
	shop("Dispatch", { x0 = s.x - 4, z0 = s.z - 2.5, x1 = s.x + 4, z1 = s.z + 2.5 }, color("Dispatch"), "DISPATCH")
	if Config.Auction.On then
		shop("Auction", shops.auction.rect, color("Auction"), "AUCTION HOUSE")
	end
	-- the words: the portals first (each its name over its state's line; when one of them finds no clear place, every
	-- portal's name alone: their pads' colours and the side column's HOUSES say the state), your warehouse, then the
	-- rest where they are clear
	for _, p in L.portals do
		portal(canvas, p, label)
	end
	canvas.placed = {}
	for _, pw in canvas.portalWords do
		if not settle(canvas, { pw.name, pw.line }, pw.spots, false) then
			canvas.lines = false
			break
		end
	end
	if not canvas.lines then
		canvas.placed = {}
		for _, pw in canvas.portalWords do
			pw.line.Visible = false
			pw.name.Visible = true
			settle(canvas, { pw.name }, pw.spots, true)
		end
	end
	if mineFirst then
		settle(canvas, mineFirst.labels, mineFirst.spots, true)
	end
	for _, n in later do
		settle(canvas, n.labels, n.spots, n.must)
	end
	return canvas
end

function SandboxMapDraw.portals(canvas: Canvas, states: { any }, now: number)
	local P = R.Portal
	for _, s in states do
		local view = canvas.portals[s.house]
		if view then
			local who: { string } = {}
			if type(s.who) == "string" then
				who = string.split(s.who, ", ")
			end
			local text, tone = Rules.portal(s.state, s.endsAt, now, Rules.names(who, C.MapNames), s.difficulty, if canvas.long then "long" else "short")
			local key = `{text}|{tone}`
			if key ~= view.key then
				view.key = key
				local c = rgb(if tone == "use" then P.InUse elseif tone == "wait" then P.Waiting else P.Free)
				view.pad.BackgroundColor3 = c
				view.line.Text = text
				view.line.TextColor3 = c
			end
		end
	end
end

-- ── A run's house ────────────────────────────────────────────────────────────

local ROOM_NAMES: { [string]: string } = {
	hall = "HALL",
	corridor = "CORRIDOR",
	living = "LIVING ROOM",
	kitchen = "KITCHEN",
	bedroom = "BEDROOM",
	kids = "KIDS' ROOM",
	bath = "BATHROOM",
	garage = "GARAGE",
	study = "STUDY",
	guest = "GUEST ROOM",
	main = "MAIN ROOM",
	bunks = "BUNK ROOM",
	store = "STORE",
	gunroom = "GUN ROOM",
	workroom = "WORKROOM",
	millers = "MILLER'S ROOM",
}

function SandboxMapDraw.house(parent: Instance, frame: Rules.Frame, u: number, w: number, h: number, place: any, mini: boolean?): Canvas
	local canvas = newCanvas(parent, frame, u, mini == true, w, h)
	local plan: Rules.Plan? = place.plan
	local yard: Rules.Yard? = place.yard
	local small = Rules.textSize(C.Text.Small, u)
	if yard then
		local s = yard.strip
		area(canvas, "Yard", s.x0, s.z0, s.x1, s.z1, color("Grass"), 1)
		local road = yard.road
		if road then
			area(canvas, "Road", road.x0, road.z0, road.x1, road.z1, color("Road"), 2)
		end
	end
	if not plan then
		return canvas
	end
	local b = plan.box
	area(canvas, "Walls", b.x0, b.z0, b.x1, b.z1, color("Wall"), 2)
	for _, room in plan.rooms do
		local floor = area(canvas, `Room_{room.id}`, room.x0, room.z0, room.x1, room.z1, rgb(C.Rooms[room.kind] or C.Colors.Floor), 3)
		if not mini then
			local name = ROOM_NAMES[room.id] or ROOM_NAMES[room.kind] or string.upper(room.id)
			local roomW, roomH = floor.Size.X.Offset, floor.Size.Y.Offset
			local need = SandboxMapDraw.width(name, small, Theme.HeadingFont) + 6
			if need <= roomW and small + 6 <= roomH then
				local cx, cy = Rules.toMap(frame, (room.x0 + room.x1) / 2, (room.z0 + room.z1) / 2)
				local tag = words(canvas.root, `RoomName_{room.id}`, name, cx, cy, 0.5, 0.5, small, K.charcoal, 5, false)
				tag.TextTransparency = 0.35
			end
		end
	end
	for n, f in plan.fixtures do
		area(canvas, `Fixture{n}`, f.x - f.sx / 2, f.z - f.sz / 2, f.x + f.sx / 2, f.z + f.sz / 2, color("Fixture"), 4, 0.15)
	end
	local half = plan.wall / 2 + 0.15
	for n, wnd in plan.windows do
		if wnd.axis == "X" then
			area(canvas, `Window{n}`, wnd.x - wnd.w / 2, wnd.z - half, wnd.x + wnd.w / 2, wnd.z + half, color("Glass"), 4)
		else
			area(canvas, `Window{n}`, wnd.x - half, wnd.z - wnd.w / 2, wnd.x + half, wnd.z + wnd.w / 2, color("Glass"), 4)
		end
	end
	for n, d in plan.doors do
		local c = if d.out then color("Exit") else color("Door")
		local gap = if d.out then half + 0.4 else half
		if d.axis == "X" then
			area(canvas, `Door{n}`, d.x - d.w / 2, d.z - gap, d.x + d.w / 2, d.z + gap, c, 4)
		else
			area(canvas, `Door{n}`, d.x - gap, d.z - d.w / 2, d.x + gap, d.z + d.w / 2, c, 4)
		end
		if d.out and not mini then
			-- its name outside the house (the front door's in the yard under it)
			local ox, oz = d.x, d.z
			if d.axis == "X" then
				oz += if d.z <= (b.z0 + b.z1) / 2 then -half - 1 else half + 1
			else
				ox += if d.x <= (b.x0 + b.x1) / 2 then -half - 1 else half + 1
			end
			local x, y = Rules.toMap(frame, ox, oz)
			local below = d.axis == "X" and d.z <= (b.z0 + b.z1) / 2
			words(canvas.root, `DoorName{n}`, if d.front then "FRONT DOOR" else "BACK DOOR", x, y, if d.axis == "X" then 0.5 elseif x > frame.ox then 0 else 1,
				if d.axis == "X" then (if below then 0 else 1) else 0.5, small, color("Exit"), 6, true)
		end
	end
	return canvas
end

-- ── The markers ──────────────────────────────────────────────────────────────

local function poolEntry(canvas: Canvas, list: { any }, n: number, make: () -> any): any
	local entry: any = list[n]
	if not entry then
		entry = make()
		list[n] = entry
	end
	return entry
end

local function place(object: GuiObject, x: number, y: number)
	local at = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	if object.Position ~= at then
		object.Position = at
	end
end

local function show(object: GuiObject, on: boolean)
	if object.Visible ~= on then
		object.Visible = on
	end
end

local KIND_COLOR: { [string]: string } = { party = "Party", player = "Player", helper = "Helper", zombie = "Zombie" }

function SandboxMapDraw.marks(canvas: Canvas, people: { any }, loot: { any }, dangers: { any }, truck: { x: number, z: number }?)
	local f = canvas.frame
	local u = canvas.u
	local mini = canvas.mini
	local small = Rules.textSize(C.Text.Small, u)
	-- the truck (under everybody)
	if truck then
		local pool = canvas.pool
		local body: any = pool.truck
		if not body then
			local px0, py0, px1, py1 = Rules.rectOn(f, -4, -C.Yard.Truck / 2, 4, C.Yard.Truck / 2)
			body = block(canvas.root, "Truck", 0, 0, px1 - px0, py1 - py0, color("Truck"), 8)
			body.AnchorPoint = Vector2.new(0.5, 0.5)
			Ui.make("UICorner", { CornerRadius = UDim.new(0, 3) }, body)
			edge(body, K.charcoal, 1.5)
			if not mini then
				local tag = words(body, "TruckName", "TRUCK", 0, 0, 0.5, 0.5, small, K.charcoal, 9, false)
				tag.Position = UDim2.fromScale(0.5, 0.5)
				tag.Rotation = if body.Size.Y.Offset > body.Size.X.Offset then 90 else 0
			end
			pool.truck = body
		end
		local x, y = Rules.toMap(f, truck.x, truck.z)
		place(body, x, y)
		show(body, true)
	elseif canvas.pool.truck then
		show(canvas.pool.truck, false)
	end
	-- the loot
	local dotSize = math.max(if mini then 6 else 8, math.floor(2.2 * f.scale + 0.5))
	for n, item in loot do
		local entry = poolEntry(canvas, canvas.pool.loot, n, function(): any
			local dot = block(canvas.root, "Loot", 0, 0, dotSize, dotSize, K.text, 9)
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			round(dot)
			edge(dot, K.charcoal, 1.5)
			local ring = block(dot, "Pulse", 0, 0, dotSize, dotSize, K.text, 9, 1)
			ring.AnchorPoint = Vector2.new(0.5, 0.5)
			ring.Position = UDim2.fromScale(0.5, 0.5)
			round(ring)
			local stroke = Ui.make("UIStroke", { Name = "Ring", Color = K.text, Thickness = 2, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
			ring.Visible = false
			return { dot = dot, ring = ring, stroke = stroke, tweens = nil :: { Tween }?, rarity = "" }
		end)
		local x, y = Rules.toMap(f, item.x, item.z)
		place(entry.dot, x, y)
		show(entry.dot, true)
		if entry.rarity ~= item.rarity then
			entry.rarity = item.rarity
			local tier = Config.Collection.Tiers[item.rarity] or Config.Collection.Tiers.common
			entry.dot.BackgroundColor3 = rgb(tier.color)
			entry.stroke.Color = rgb(tier.color)
		end
		local pulsing = item.pulse == true
		if pulsing and not entry.tweens then
			entry.ring.Visible = true
			entry.ring.Size = UDim2.fromOffset(dotSize, dotSize)
			entry.stroke.Transparency = 0
			local info = TweenInfo.new(C.Pulse.Seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, -1)
			local grow = TweenService:Create(entry.ring, info, { Size = UDim2.fromOffset(dotSize * 2.4, dotSize * 2.4) })
			local fade = TweenService:Create(entry.stroke, info, { Transparency = 1 })
			entry.tweens = { grow, fade }
			grow:Play()
			fade:Play()
		elseif not pulsing and entry.tweens then
			for _, tween in entry.tweens do
				tween:Cancel()
			end
			entry.tweens = nil
			entry.ring.Visible = false
		end
	end
	for n = #loot + 1, #canvas.pool.loot do
		local entry = canvas.pool.loot[n]
		show(entry.dot, false)
		if entry.tweens then
			for _, tween in entry.tweens do
				tween:Cancel()
			end
			entry.tweens = nil
			entry.ring.Visible = false
		end
	end
	-- the dangers
	local icon = math.max(small + 2, math.floor(3 * f.scale + 0.5))
	for n, d in dangers do
		local entry = poolEntry(canvas, canvas.pool.danger, n, function(): any
			local label = words(canvas.root, "Danger", "⚠", 0, 0, 0.5, 0.5, icon, K.text, 10, true)
			return { label = label, key = "" }
		end)
		local def = C.Danger[d.tag]
		local text = if def then (if d.open and def.open then def.open else def.icon) else "⚠"
		if d.tag == "RunHazard" and d.kind then
			text = C.Hazards[string.lower(d.kind)] or text
		end
		if entry.key ~= text then
			entry.key = text
			entry.label.Text = text
			entry.label.Size = UDim2.fromOffset(SandboxMapDraw.width(text, icon, Theme.HeadingFont) + 6, icon + 4)
		end
		entry.label.TextTransparency = if d.open and d.tag ~= "RunKey" then 0.4 else 0
		local x, y = Rules.toMap(f, d.x, d.z)
		place(entry.label, x, y)
		show(entry.label, true)
	end
	for n = #dangers + 1, #canvas.pool.danger do
		show(canvas.pool.danger[n].label, false)
	end
	-- the people: everybody but you, then you on top
	local named = not mini
	local n = 0
	local me: any = nil
	for _, person in people do
		if person.kind == "you" then
			me = person
			continue
		end
		n += 1
		local entry = poolEntry(canvas, canvas.pool.people, n, function(): any
			local size = if mini then 7 else 10
			local dot = block(canvas.root, "Person", 0, 0, size, size, K.text, 10)
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			round(dot)
			edge(dot, K.charcoal, 1.5)
			local name: TextLabel? = nil
			if named then
				name = words(canvas.root, "PersonName", "", 0, 0, 0, 0.5, small, K.text, 10, true, false)
			end
			return { dot = dot, name = name, key = "" }
		end)
		local zombie = person.kind == "zombie"
		local c = color(KIND_COLOR[person.kind] or "Player")
		local x, y = Rules.toMap(f, person.x, person.z)
		place(entry.dot, x, y)
		show(entry.dot, true)
		entry.dot.BackgroundColor3 = c
		entry.dot.BackgroundTransparency = if person.pinned then 0.45 else 0
		local name = entry.name
		if name then
			local text = if zombie then "" else person.name
			if entry.key ~= text then
				entry.key = text
				name.Text = text
				name.Size = UDim2.fromOffset(SandboxMapDraw.width(text, small, Theme.Font) + 10, small + 6)
			end
			name.TextColor3 = c
			place(name, x + 8, y)
			show(name, text ~= "")
		end
	end
	for i = n + 1, #canvas.pool.people do
		local entry = canvas.pool.people[i]
		show(entry.dot, false)
		if entry.name then
			show(entry.name, false)
		end
	end
	local arrow: any = canvas.pool.me
	if me then
		if not arrow then
			local size = if mini then 16 else math.max(18, math.floor(20 * u + 0.5))
			arrow = Ui.make("TextLabel", {
				Name = "You",
				Text = "▲",
				TextSize = size,
				Font = Theme.HeadingFont,
				TextColor3 = color("You"),
				TextStrokeColor3 = K.charcoal, -- (a dark edge: it reads on every floor)
				TextStrokeTransparency = 0,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(math.ceil(size * 1.3), math.ceil(size * 1.3)), -- (room for the glyph, turned too)
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 11,
			}, canvas.root)
			canvas.pool.me = arrow
		end
		local x, y = Rules.toMap(f, me.x, me.z)
		place(arrow, x, y)
		local rotation = if me.lookX then Rules.heading(f, me.lookX, me.lookZ) else 0
		if math.abs((arrow.Rotation or 0) - rotation) > 0.5 then
			arrow.Rotation = rotation
		end
		arrow.TextTransparency = if me.pinned then 0.4 else 0
		show(arrow, true)
	elseif arrow then
		show(arrow, false)
	end
end

return SandboxMapDraw
