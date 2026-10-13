-- 7.2, the Alps on the maps: the real client/MapView.luau (with the real shared/MapStyle.luau, AlpineLayout, Map,
-- Roads, Explore, BusLines, RentalDocks, Icons) built on tools/phone-ui/mapmock.luau's recorder. Checks that the
-- minimap and the big map are built with the paper map's ground at once and the Alps a moment later, once: the ring
-- and the forest worked out once, every alpine layer filled once and its frames within Config.MapStyle.Budget; that
-- it is all there (the valley, the water with its shore, the snowfield, the peaks with their caps and shadow sides,
-- the minimap's rock and snow, the forest bands with their tree dots, the meadows and the huts, the West Pass's road
-- and its ROAD CLOSED sign, the ⛲ on the Hauptplatz, the Altstadt over Downtown, the captions) and in the right order
-- under the fog, the routes and the markers; and that the frame loop (moving, turning, the routes, the fog, the big
-- map open and shut) makes nothing new and leaves the Alps alone, the ⛲ and the ⛔ upright on the turning minimap. Run
-- by check.py; `luau mapview.luau -a dump` prints the preview's scenes as JSON instead (mapview_preview.py).
local M = require("./mapmock")
local Config = require("./Config")
local Map = require("./Map")
local AlpineLayout = require("./AlpineLayout")
local MapStyle = require("./MapStyle")

local dump = select(1, ...) == "dump"
local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		if not dump then
			print("ok    " .. name)
		end
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local S = Config.MapStyle
local B = Map.Bounds

-- The ring and the forest: how often MapView has them worked out (forest() asks for the ring itself: not counted).
local calls = { ring = 0, forest = 0, ringTime = 0, forestTime = 0 }
local ring0, forest0 = AlpineLayout.ring, AlpineLayout.forest
local inForest = false
AlpineLayout.ring = function(box)
	if not inForest then
		calls.ring += 1
	end
	local t = os.clock()
	local made = ring0(box)
	if not inForest then
		calls.ringTime += os.clock() - t
	end
	return made
end
AlpineLayout.forest = function(ring)
	calls.forest += 1
	inForest = true
	local t = os.clock()
	local made = forest0(ring)
	calls.forestTime += os.clock() - t
	inForest = false
	return made
end

local MapView = require("./MapView")

local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	return root:FindFirstChild(name, true)
end
local function findAll(root: any, test: (any) -> boolean): { any }
	local out = {}
	M.walk(root, function(node)
		if test(node) then
			table.insert(out, node)
		end
	end)
	return out
end
local function rgb(c: any): string
	return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function style(name: string, kind: string?): string
	local c = MapStyle.rgb(name, kind)
	return string.format("%d,%d,%d", c[1], c[2], c[3])
end

-- ── Built: the ground at once, the Alps a moment later ─────────────────────

M.place(0, -60)
local madeBefore = M.made
MapView.start(M.hud, M.column)
local mini = find(M.column, "Minimap")
local big = find(M.hud, "BigMap")
check("the minimap and the big map are built", mini ~= nil and big ~= nil)
local miniRelief, bigPeaks = find(mini, "Relief"), find(big, "Peaks")
local miniForest, bigForest = find(mini, "Forest"), find(big, "Forest")
local miniMeadows, bigMeadows = find(mini, "Meadows"), find(big, "Meadows")
check("7.2: each map has its ring layer (the big map's peaks, the minimap's relief), its forest and its meadows", miniRelief and bigPeaks and miniForest and bigForest and miniMeadows and bigMeadows and find(mini, "Peaks") == nil and find(big, "Relief") == nil)
check("the Alps wait for the start screen: nothing of the ring or the forest yet", calls.ring == 0 and calls.forest == 0 and #miniRelief._children == 0 and #bigPeaks._children == 0 and #bigForest._children == 0 and not MapView.alpine.started)
local baseMade = M.made - madeBefore
local miniBefore, bigBefore = M.count(mini), M.count(big) -- (GuiObjects before the Alps)

-- The deferred thread: a frame between the ring, the forest and each map.
local steps = 0
local dressT = os.clock()
while not MapView.alpine.done and steps < 20 do
	M.frame()
	M.resume()
	steps += 1
end
dressT = os.clock() - dressT - calls.ringTime - calls.forestTime
check("the Alps are drawn after a few frames", MapView.alpine.done and steps >= 4, steps)
check("no summary from the server: this client worked the plan out itself", MapView.alpine.source == "client", MapView.alpine.source)
check("the ring and the forest are worked out once", calls.ring == 1 and calls.forest == 1, `{calls.ring} rings, {calls.forest} forests`)
local alpineMade = M.made - madeBefore - baseMade

-- ── What MapStyle plans ────────────────────────────────────────────────────

local ring = ring0()
local forest = forest0()
local E = MapStyle.extent()
local peaks = MapStyle.peaks(ring)
local relief = MapStyle.relief(ring)
local runs = MapStyle.forestRuns(forest)
local meadows = MapStyle.meadows(forest)
local huts = MapStyle.huts(forest)
local passes = MapStyle.passes(ring)
check("the drawn area is the bounds and the margin round them", E.x0 == B.x0 - S.Margin and E.z1 == B.z1 + S.Margin)
do
	local inside, south, capped, rows = true, true, 0, {}
	for _, p in peaks do
		local tx, tz = p.x + p.ox * p.half, p.z + p.oz * p.half -- (its top)
		inside = inside and p.x >= E.x0 and p.x <= E.x1 and p.z >= E.z0 and p.z <= E.z1 + 1e-6
		inside = inside and tx >= E.x0 - 1e-6 and tx <= E.x1 + 1e-6 and tz >= E.z0 - 1e-6 and tz <= E.z1 + 1e-6
		inside = inside and math.abs(p.ox * p.sx + p.oz * p.sz) < 1e-9 -- (its shadow side across it)
		if p.side == "south" then
			south = south and tz >= B.z1
		elseif p.side == "west" or p.side == "east" then
			-- (its inner foot at most Into × Margin over the valley's edge)
			local inner = if p.side == "west" then p.x + p.half - B.x0 else B.x1 - (p.x - p.half)
			south = south and inner <= S.Peaks.Into * S.Margin + 1e-6
		end
		if p.cap > 0 then
			capped += 1
			inside = inside and p.cap < p.half
		end
		rows[p.side] = (rows[p.side] or 0) + 1
	end
	local wanted = 0
	for _, c in ring.cones do
		local across = math.abs(c.nx) > math.abs(c.nz) -- (east or west)
		wanted += if c.row ~= "shoulder" or across then 1 else 0
	end
	check("a peak for every cone of the ring (the shoulders east and west only)", #peaks == wanted, #peaks)
	check("every peak's foot and top on the paper, its cap under its top", inside)
	check("the south's peaks rise toward the valley but never into it, the sides' feet at most a little over its edge", south)
	check("peaks on all four sides, most of them snowcapped", (rows.north or 0) > 5 and (rows.south or 0) > 5 and (rows.east or 0) > 5 and (rows.west or 0) > 5 and capped > #peaks / 2, `{capped} of {#peaks}`)
	local sorted = true
	for k = 2, #peaks do
		sorted = sorted and peaks[k - 1].z <= peaks[k].z
	end
	check("the peaks back to front (by their foot line, down the map)", sorted)
end
do
	local covered, total, inside, apart = 0, 0, true, true
	for _, t in forest.trees do
		if not t.slope then
			total += 1
			for _, run in runs do
				local half = S.Forest.Cell / 2
				if t.x >= run.x0 and t.x < run.x1 and math.abs(t.z - run.z) <= half then
					covered += 1
					break
				end
			end
		end
	end
	local snowy = 0
	for k, run in runs do
		inside = inside and run.x0 >= B.x0 and run.x1 <= B.x1 and run.z > B.z0 and run.z < B.z1 and run.cells >= 1
		if run.snowy then
			snowy += 1
		end
		local next = runs[k + 1]
		if next and next.z == run.z then
			apart = apart and next.x0 >= run.x1
		end
	end
	check("the forest bands hold most of the valley's trees", covered >= total * 0.85, `{covered} of {total}`)
	check("the forest bands lie in the valley, apart on their row", inside and apart)
	check("the winter's forests are snowy bands", snowy > 0, snowy)
	check("the meadows and the huts come from the forest", #meadows == #forest.patches and #huts == #forest.huts and #huts > 0)
	check("the West Pass: a closed road out of the valley", #passes >= 1 and passes[1].name == "WEST PASS" and passes[1].x == B.x0)
end
do
	-- The Alps' step 2 (design/rework: Map.AlpineLake an ellipse, Map.Winter a rectangle, the old sea, frozen lake and
	-- mountain left as stand-ins far off the valley, the villages named): MapStyle reads them as they come.
	local M2 = Map :: any
	local saved = { Sea = M2.Sea, Lake = M2.Lake, Mountain = M2.Mountain, AlpineLake = M2.AlpineLake, Winter = M2.Winter, Villages = M2.Villages }
	M2.Sea = { x0 = 1e7 }
	M2.Lake = { x0 = 1e7, x1 = 1e7 + 10, z0 = 1e7, z1 = 1e7 + 10 }
	M2.Mountain = { x = 1e7, z = 1e7, radius = 10 }
	M2.AlpineLake = { x0 = 1230, x1 = 1480, z0 = -540, z1 = 470 }
	M2.Winter = { x0 = 120, x1 = 760, z0 = B.z0, z1 = B.z0 + 260 }
	M2.Villages = { { name = "Sankt Alm", x = -1000, z = -1000 }, Bergdorf = { x = 1300, z = -850 }, { name = "Seewinkel", x = 1100, z = 0 } }
	local waters = MapStyle.waters(E)
	local kinds = {}
	for _, w in waters do
		kinds[w.kind] = w
	end
	check("step 2: the alpine lake round and named, the river on, no sea nor frozen lake off the valley", kinds.lake ~= nil and kinds.lake.round == math.huge and kinds.lake.x0 == 1230 and kinds.river ~= nil and kinds.sea == nil and kinds.ice == nil and #waters == 2)
	check("step 2: the old mountain gone when Map moves it off the valley", MapStyle.mountain(E) == nil)
	local field = MapStyle.winter(E)
	check("step 2: the snowfield is Map.Winter, on into the ring north of it", field ~= nil and field.x0 == 120 and field.x1 == 760 and field.z0 == E.z0 and field.z1 == B.z0 + 260)
	local villages = MapStyle.villages()
	local names = {}
	for _, v in villages do
		table.insert(names, v.name .. (if v.placeholder then "*" else ""))
	end
	check("step 2: Map's villages named in order, the Altstadt's placeholder still over Downtown", table.concat(names, ",") == "Bergdorf,Sankt Alm,Seewinkel,Altstadt*", table.concat(names, ","))
	table.insert(M2.Villages, { name = "Altstadt", x = 0, z = -300 })
	local named = MapStyle.villages()
	check("…and no placeholder once Map names the Altstadt", #named == 4 and not named[1].placeholder and not named[4].placeholder)
	for _, key in { "Sea", "Lake", "Mountain", "AlpineLake", "Winter", "Villages" } do
		M2[key] = saved[key] -- (nil puts back an absent one)
	end
end
do
	local kinds = {}
	for _, d in relief do
		kinds[d.kind] = (kinds[d.kind] or 0) + 1
	end
	check("the minimap's relief: the grassy feet, rock, snow and the winter's snowy cones", (kinds.foot or 0) > 20 and (kinds.rock or 0) > 20 and (kinds.snow or 0) > 5 and (kinds.winter or 0) > 0)
	local seen = true
	for _, d in relief do
		seen = seen and AlpineLayout.boxDistance(ring.box, d.x, d.z) - d.r <= S.Relief.Reach
	end
	check("only the discs the minimap can see from inside the bounds", seen)
end

-- ── Counts and budgets ─────────────────────────────────────────────────────

local nPeaks, nRelief = M.count(bigPeaks), M.count(miniRelief)
local nForestBig, nForestMini = M.count(bigForest), M.count(miniForest)
local nMeadowsBig, nMeadowsMini = M.count(bigMeadows), M.count(miniMeadows)
local expectPeaks = 0
for _, p in peaks do
	expectPeaks += if p.cap > 0 then 3 else 2
end
check("the big map: a peak is its rock, its cap and its shadow side", nPeaks == expectPeaks, `{nPeaks} frames for {#peaks} peaks`)
check("the minimap: a disc a cone's foot, rock or snow", nRelief == #relief, nRelief)
check("a forest band a run, on each map", nForestBig == #runs and nForestMini == #runs, nForestBig)
-- (7.2 review: a meadow is one disc with its flower the dot on it: the minimap's CanvasGroup draws every object again
-- on every move)
check("7.2 review: a meadow is one disc, its flower on it; the huts", nMeadowsBig == #meadows + #huts and nMeadowsMini == nMeadowsBig, nMeadowsBig)
check(`budget: the peaks ≤ {S.Budget.Peaks}`, nPeaks <= S.Budget.Peaks, nPeaks)
check(`budget: the relief ≤ {S.Budget.Relief}`, nRelief <= S.Budget.Relief, nRelief)
check(`budget: the forests ≤ {S.Budget.Forest} a map`, nForestBig <= S.Budget.Forest, nForestBig)
check(`budget: the meadows and huts ≤ {S.Budget.Meadows} a map`, nMeadowsBig <= S.Budget.Meadows, nMeadowsBig)
local bigAlpine = nPeaks + nForestBig + nMeadowsBig + 4 * #passes
local miniAlpine = nRelief + nForestMini + nMeadowsMini + 3 * #passes
check(`budget: all of the Alps ≤ {S.Budget.Alpine} GuiObjects a map`, bigAlpine <= S.Budget.Alpine and miniAlpine <= S.Budget.Alpine, `big {bigAlpine}, mini {miniAlpine}`)
check(`7.2 review: budget: the minimap's Alps ≤ {S.Budget.Mini} GuiObjects (its CanvasGroup draws them all again on every move)`, miniAlpine <= S.Budget.Mini, miniAlpine)
do
	-- 7.2 review: no TextScaled label among the minimap's forests and meadows (one fits its text again on every redraw)
	local scaled = findAll(miniForest, function(node)
		return node.TextScaled == true
	end)
	for _, node in findAll(miniMeadows, function(node)
		return node.TextScaled == true
	end) do
		table.insert(scaled, node)
	end
	check("7.2 review: the minimap's forests and meadows: no TextScaled label", #scaled == 0, #scaled)
end

-- ── What is there ──────────────────────────────────────────────────────────

local function content(root: any): any
	return find(root, "Ground").Parent
end
local miniContent, bigContent = content(mini), content(big)
check("the big map's paper round the ring, the minimap's grass", rgb(bigContent.BackgroundColor3) == style("Paper") and rgb(miniContent.BackgroundColor3) == style("Slope"))
check("the drawn area: the bounds and the margin, at each map's scale", math.abs(miniContent.Size.X.Offset - (E.x1 - E.x0) * 0.6) < 1e-6 and math.abs(bigContent.Size.X.Offset - (E.x1 - E.x0) * 0.16) < 1e-6)
local valley = find(big, "Valley")
check("the valley green over the bounds", valley and rgb(valley.BackgroundColor3) == style("Valley") and math.abs(valley.Position.X.Offset - S.Margin * 0.16) < 1e-6)
for _, root in { mini, big } do
	local waters = findAll(root, function(node)
		return node.Name == "Water"
	end)
	local shore = 0
	for _, w in waters do
		if w:FindFirstChildOfClass("UIStroke") then
			shore += 1
		end
	end
	check(`{root.Name}: the water (river, sea, lakes) blue with its shore`, #waters == #MapStyle.waters(E) and #waters >= 1 and shore == #waters, #waters)
	check(`{root.Name}: the snowfield`, (find(root, "Winter") ~= nil) == (MapStyle.winter() ~= nil))
	local field, inside = MapStyle.winter(E), MapStyle.winter()
	check(`{root.Name}: the snowfield goes on into the ring where it meets the bounds`, field == nil or inside ~= nil and (field.x0 == (if inside.x0 <= B.x0 then E.x0 else inside.x0)) and field.z1 == inside.z1)
	local fountain = find(root, "Fountain")
	check(`{root.Name}: the Hauptplatz's ⛲`, fountain ~= nil and fountain.Text == "⛲")
	local closed = find(root, "RoadClosed")
	check(`{root.Name}: the West Pass's ROAD CLOSED`, closed ~= nil and (if root == big then string.find(closed.Text, "ROAD CLOSED", 1, true) ~= nil else closed.Text == "⛔"))
	local forestLayer = find(root, "Forest")
	if root == big then
		local bands = findAll(forestLayer, function(node)
			return node.ClassName == "TextLabel"
		end)
		local dotted = #bands > 0
		for _, band in bands do
			dotted = dotted and string.find(band.Text, "●", 1, true) ~= nil and band:FindFirstChildOfClass("UICorner") ~= nil
		end
		check(`{root.Name}: the forest bands are rounded, full of tree dots`, dotted)
	else
		-- 7.2 review: the minimap's bands are plain rounded frames in the forest's colours (no dots to fit on a redraw)
		local plain = #forestLayer._children > 0
		for _, band in forestLayer._children do
			plain = plain and band.ClassName == "Frame" and band:FindFirstChildOfClass("UICorner") ~= nil
				and (rgb(band.BackgroundColor3) == style("Forest") or rgb(band.BackgroundColor3) == style("SnowForest"))
		end
		check(`{root.Name}: 7.2 review: the forest bands are plain rounded frames, the forest's colour`, plain)
	end
	local meadowsLayer = find(root, "Meadows")
	local flowered = #meadows > 0
	for _, node in meadowsLayer._children do
		if node.Name ~= "Hut" then
			flowered = flowered and node.ClassName == "TextLabel" and node.Text == "●" and not node.TextScaled and node:FindFirstChildOfClass("UICorner") ~= nil
				and rgb(node.BackgroundColor3) == style("Meadow")
		end
	end
	check(`{root.Name}: 7.2 review: a meadow's disc carries its flower (its dot, a fixed size)`, flowered)
	check(`{root.Name}: the huts`, #findAll(root, function(node)
		return node.Name == "Hut"
	end) == #huts)
end
do
	local caps, shades, rock = 0, 0, 0
	for _, frame in bigPeaks._children do
		local gradient = frame:FindFirstChildOfClass("UIGradient")
		if rgb(frame.BackgroundColor3) == style("Snow") then
			caps += 1
		elseif rgb(frame.BackgroundColor3) == style("Shadow") then
			shades += if frame.BackgroundTransparency == S.Peaks.Shade and gradient and math.abs(gradient.Rotation % 90 - 45) < 1e-6 then 1 else 0
		elseif frame.Rotation == 45 and gradient and math.abs(gradient.Rotation % 90 - 45) < 1e-6 then
			rock += 1 -- (the rock, the farther the paler)
		end
	end
	check("the peaks: grey rock (a diamond cut in half), white caps, a see-through shadow side", rock == #peaks and shades == #peaks and caps > 0, `{rock} rock, {caps} caps, {shades} shadows`)
	local order = true
	local last = 0
	for _, frame in bigPeaks._children do
		order = order and frame.ZIndex > last
		last = frame.ZIndex
	end
	check("the peaks' frames each over the last (their ZIndex climbs)", order)
	local lit = 0
	for _, frame in miniRelief._children do
		local gradient = frame:FindFirstChildOfClass("UIGradient")
		lit += if gradient and gradient.Rotation == 45 and frame:FindFirstChildOfClass("UICorner") then 1 else 0
	end
	check("the minimap's discs: round, lit from the north-west", lit == nRelief)
end
do
	local function captions(root: any): { [string]: any }
		local out = {}
		M.walk(root, function(node)
			if node.ClassName == "TextLabel" and node.Text ~= "" then
				out[node.Text] = node
			end
		end)
		return out
	end
	local texts = captions(bigContent)
	check("the Altstadt over Downtown, its own name small under it", texts.ALTSTADT ~= nil and texts.DOWNTOWN ~= nil and texts.ALTSTADT.TextSize > texts.DOWNTOWN.TextSize and texts.ALTSTADT.Name == "Village")
	check("the other districts named", texts.HARBOR ~= nil and texts.SUBURBS ~= nil)
	check("the captions in dark ink on a light halo", rgb(texts.HARBOR.TextColor3) == style("Ink") and rgb(texts.HARBOR.TextStrokeColor3) == style("Halo"))
	check("WEST PASS over its sign, HAUPTPLATZ, SAFE ZONE", texts["WEST PASS"] ~= nil and texts.HAUPTPLATZ ~= nil and texts["SAFE ZONE"] ~= nil)
	check("the minimap stays quiet (no captions)", captions(miniContent).ALTSTADT == nil and captions(miniContent).HARBOR == nil)
end
do
	-- the roads: light on a brown edge, the highways amber; the pass's road in them
	local highway, edges = 0, 0
	for _, node in bigContent._children do
		if node.ClassName == "Frame" and node.ZIndex == 5 and rgb(node.BackgroundColor3) == style("Highway") then
			highway += 1
		elseif node.ClassName == "Frame" and node.ZIndex == 4 and rgb(node.BackgroundColor3) == style("RoadEdge") then
			edges += 1
		end
	end
	local segments = 0
	for _, s in Map.Segments do
		segments += if s.kind == "highway" then 1 else 0
	end
	check("the roads on their edges, the highways amber, the pass's road too", highway == segments and edges == #Map.Segments + #passes, `{highway} highways, {edges} edges`)
end
do
	-- the layers' order: the ground, the ring, the town, the roads, the captions, the fog, the routes, the markers
	local z = {}
	for _, node in bigContent._children do
		z[node.Name] = node.ZIndex
	end
	check("under the town: the ground (1), the ring (2)", z.Ground == 1 and z.Peaks == 2)
	check("over everything drawn: the fog (8), then the routes and the markers", z.Fog == 8 and find(big, "Fog").ZIndex == 8)
	local ground = find(big, "Ground")
	local gz = {}
	for _, node in ground._children do
		gz[node.Name] = math.max(gz[node.Name] or 0, node.ZIndex)
	end
	check("in the ground: the valley, the snowfield, the meadows, the forests, then the water", gz.Valley < gz.Winter and gz.Winter < gz.Meadows and gz.Meadows < gz.Forest and gz.Forest < gz.Water)
end

-- ── Built once: the frame loop leaves the Alps alone ───────────────────────

local function snapshot(): { number }
	return { M.count(bigPeaks), M.count(miniRelief), M.count(bigForest), M.count(miniForest), M.count(bigMeadows), M.count(miniMeadows) }
end
local before = snapshot()
local fogBefore = M.count(find(big, "Fog"))
-- Drive about: the camera turns, the fog lifts, a job and the GPS, the big map open and shut.
M.known.square = true
M.known.depot = true
MapView.setTarget(M.Vector3.new(400, 0, 400))
MapView.setWaypoint(M.Vector3.new(-400, 0, -300))
local lifted = M.uncover(function(x, z)
	return math.abs(x) < 900 and math.abs(z) < 900
end)
for n = 1, 120 do
	local a = n / 120 * math.pi * 2
	M.place(math.cos(a) * 200, math.sin(a) * 200 - 60, -math.sin(a), math.cos(a))
	M.look(math.sin(a), -math.cos(a))
	if n == 30 or n == 60 then
		MapView.toggle()
	end
	M.frame(1 / 60)
end
check("the fog lifts where you have been (its rows drawn again)", lifted > 0 and M.count(find(big, "Fog")) ~= fogBefore)
local after = snapshot()
local same = true
for k, v in before do
	same = same and after[k] == v
end
check("the Alps' layers are the same after the frame loop, the fog and the big map", same)
check("still one ring and one forest worked out", calls.ring == 1 and calls.forest == 1)
-- Steady: nothing new is made frame after frame.
for _ = 1, 30 do
	M.frame(1 / 60)
end
local steady = M.made
for _ = 1, 90 do
	M.frame(1 / 60)
end
check("the frame loop makes nothing new (the routes and markers are pooled)", M.made == steady, M.made - steady)
-- The minimap turns with the camera; the ⛲ and the ⛔ stay upright like the icons.
M.look(1, 0) -- (facing east)
for _ = 1, 3 do
	M.frame(1 / 60)
end
local upright = true
for _, name in { "Fountain", "RoadClosed" } do
	local node = find(mini, name)
	upright = upright and node ~= nil and math.abs(node.Rotation - 90) < 1e-6
end
check("the minimap turns, the ⛲ and the ⛔ stay upright", upright)

-- ── The server's summary ───────────────────────────────────────────────────

local summaryLength = 0
do
	local plan = MapStyle.plan(ring, forest)
	local text = MapStyle.encode(plan)
	summaryLength = #text
	check(`the summary is short: ≤ {S.Budget.Summary} characters (a StringValue holds 200,000)`, #text <= S.Budget.Summary and #text < 200000, #text)
	check("the summary is plain ASCII (no separators, nothing to escape)", string.find(text, "[^%w%-_]") == nil)
	local back = MapStyle.decode(text)
	local same = back ~= nil
	local function near(a: number, b: number, tolerance: number): boolean
		return math.abs(a - b) <= tolerance
	end
	if back then
		same = #back.peaks == #plan.peaks and #back.relief == #plan.relief and #back.runs == #plan.runs and #back.meadows == #plan.meadows and #back.huts == #plan.huts and #back.passes == #plan.passes
		for k, p in plan.peaks do
			local q = back.peaks[k]
			same = same and q and near(p.x, q.x, 0.05) and near(p.z, q.z, 0.05) and near(p.half, q.half, 0.05) and near(p.cap, q.cap, 0.05) and near(p.depth, q.depth, 0.0005)
			same = same and q.ox == p.ox and q.oz == p.oz and q.sx == p.sx and q.sz == p.sz and q.winter == p.winter and q.side == p.side
		end
		for k, d in plan.relief do
			local e = back.relief[k]
			same = same and e and e.kind == d.kind and near(d.x, e.x, 0.05) and near(d.z, e.z, 0.05) and near(d.r, e.r, 0.05)
		end
		for k, run in plan.runs do
			local r = back.runs[k]
			same = same and r and near(run.x0, r.x0, 0.05) and near(run.x1, r.x1, 0.05) and near(run.z, r.z, 0.05) and r.cells == run.cells and r.snowy == run.snowy
		end
		for k, spot in plan.meadows do
			same = same and near(spot.x, back.meadows[k].x, 0.05) and near(spot.z, back.meadows[k].z, 0.05)
		end
		for k, hut in plan.huts do
			same = same and back.huts[k].kind == hut.kind and near(hut.x, back.huts[k].x, 0.05)
		end
		for k, pass in plan.passes do
			local q = back.passes[k]
			same = same and q.id == pass.id and q.name == pass.name and q.x == pass.x and q.z == pass.z and q.nx == pass.nx and q.from == pass.from and q.face == pass.face and q.text == pass.text
		end
	end
	check("the summary unpacks to the same plan (to a tenth of a stud)", same)
	check("not a summary: nil (garbage, cut short, another version)", MapStyle.decode("hello") == nil and MapStyle.decode(string.sub(text, 1, #text - 3)) == nil and MapStyle.decode("MS9" .. string.sub(text, 4)) == nil and MapStyle.decode("") == nil)
	local x0 = B.x0
	B.x0 -= 100
	check("a summary made for other bounds: nil (the client works its own plan out)", MapStyle.decode(text) == nil)
	B.x0 = x0

	-- The server's publish (MapStyle with the recorder's Instance): a StringValue in ReplicatedStorage, the same one
	-- when it publishes again; a failure only warns.
	local Server = require("./MapStyleServer")
	local storage = M.make("Folder", { Name = "ReplicatedStorage" })
	Server.publish(storage)
	local value = storage:FindFirstChild("MapStyle")
	check("the server publishes the summary in ReplicatedStorage.MapStyle (a StringValue)", value ~= nil and value.ClassName == "StringValue" and value.Value == text)
	Server.publish(storage)
	check("…the same StringValue when it publishes again", #storage._children == 1 and storage:FindFirstChild("MapStyle") == value)
	local warned = #M.warnings
	local broken = M.make("Folder", { Name = "Broken" })
	local ring1 = AlpineLayout.ring
	AlpineLayout.ring = function()
		error("no ring")
	end
	Server.publish(broken)
	AlpineLayout.ring = ring1
	check("a summary that fails only warns (no StringValue: the clients work it out)", #broken._children == 0 and #M.warnings == warned + 1)

	-- A second MapView with the summary published: built from it, the ring and the forest not worked out again, the
	-- same layers as the first one's.
	M.published.MapStyle = M.make("StringValue", { Name = "MapStyle", Value = text })
	local before = { ring = calls.ring, forest = calls.forest }
	local hud2 = M.make("ScreenGui", { Name = "ZombieDeliveryHud2" }, M.gui)
	local column2 = M.make("Frame", { Name = "LeftStack", Size = M.UDim2.fromOffset(200, 300), BackgroundTransparency = 1 }, hud2)
	local MapView2 = require("./MapViewServer")
	MapView2.start(hud2, column2)
	local frames = 0
	while not MapView2.alpine.done and frames < 20 do
		M.frame()
		M.resume()
		frames += 1
	end
	check("from the server's summary: drawn, the ring and the forest not worked out on the client", MapView2.alpine.done and MapView2.alpine.source == "server" and calls.ring == before.ring and calls.forest == before.forest, `{MapView2.alpine.source}, {calls.ring - before.ring} rings`)
	local mini2, big2 = find(column2, "Minimap"), find(hud2, "BigMap")
	local alike = true
	for _, pair in { { bigPeaks, find(big2, "Peaks") }, { miniRelief, find(mini2, "Relief") }, { bigForest, find(big2, "Forest") }, { miniForest, find(mini2, "Forest") }, { bigMeadows, find(big2, "Meadows") } } do
		local a, b = pair[1], pair[2]
		alike = alike and M.count(a) == M.count(b)
		for k, node in a._children do
			local other = b._children[k]
			alike = alike and other ~= nil and math.abs(node.Position.X.Offset - other.Position.X.Offset) < 0.1 and math.abs(node.Size.Y.Offset - other.Size.Y.Offset) < 0.1
		end
	end
	check("…the same frames in the same places as the client's own plan", alike)
	M.published.MapStyle = nil
end

if not dump then
	print(string.format("map: base %d instances, the Alps %d more; peaks %d (%d frames), relief %d, forest bands %d, meadows %d, huts %d", baseMade, alpineMade, #peaks, nPeaks, nRelief, #runs, #meadows, #huts))
	print(string.format("map: GuiObjects of the Alps a map: big %d, mini %d (the maps had %d and %d); ring %.0f ms, forest %.0f ms, plan and frames %.0f ms (this machine)", bigAlpine, miniAlpine, bigBefore, miniBefore, calls.ringTime * 1000, calls.forestTime * 1000, dressT * 1000))
	print(string.format("map: the server's summary is %d characters (budget %d; a StringValue holds 200,000)", summaryLength, S.Budget.Summary))
end

-- ── The preview's scenes (mapview_preview.py) ──────────────────────────────

if dump then
	local function encode(value: any, out: { string })
		local t = type(value)
		if t == "number" then
			if value ~= value or value == math.huge or value == -math.huge then
				table.insert(out, "null")
			elseif value == math.floor(value) and math.abs(value) < 1e15 then
				table.insert(out, string.format("%d", value))
			else
				table.insert(out, string.format("%.3f", value))
			end
		elseif t == "string" then
			table.insert(out, '"' .. string.gsub(value, '[%c"\\]', function(c)
				return string.format("\\u%04x", string.byte(c))
			end) .. '"')
		elseif t == "boolean" then
			table.insert(out, tostring(value))
		elseif t == "table" then
			if #value > 0 or next(value) == nil then
				table.insert(out, "[")
				for k, v in value do
					if k > 1 then
						table.insert(out, ",")
					end
					encode(v, out)
				end
				table.insert(out, "]")
			else
				table.insert(out, "{")
				local first = true
				for k, v in value do
					if not first then
						table.insert(out, ",")
					end
					first = false
					encode(tostring(k), out)
					table.insert(out, ":")
					encode(v, out)
				end
				table.insert(out, "}")
			end
		else
			table.insert(out, "null")
		end
	end
	local function color(c: any): any
		return if type(c) == "table" and c.R then { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } else nil
	end
	local function udim2(u: any): any
		return if type(u) == "table" and u.X then { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset } else nil
	end
	local function node(n: any): any
		local p = n._p
		local out: { [string]: any } = { c = p.ClassName, n = p.Name }
		if p.Visible == false then
			out.vis = false
		end
		out.pos, out.size = udim2(p.Position), udim2(p.Size)
		if p.AnchorPoint then
			out.anchor = { p.AnchorPoint.X, p.AnchorPoint.Y }
		end
		out.rot, out.z = p.Rotation, p.ZIndex
		out.bg, out.bgT = color(p.BackgroundColor3), p.BackgroundTransparency
		out.clip = p.ClipsDescendants
		if p.Text and p.Text ~= "" then
			out.text, out.ts, out.scaled, out.rich = p.Text, p.TextSize, p.TextScaled, p.RichText
			out.tc, out.tt, out.sc, out.st = color(p.TextColor3), p.TextTransparency, color(p.TextStrokeColor3), p.TextStrokeTransparency
			out.xa = if p.TextXAlignment then p.TextXAlignment.Name else nil
			out.font = if p.Font then p.Font.Name else nil
		end
		if p.ClassName == "UICorner" then
			out.radius = { p.CornerRadius.Scale, p.CornerRadius.Offset }
		elseif p.ClassName == "UIStroke" then
			out.color, out.thick, out.tr = color(p.Color), p.Thickness, p.Transparency
		elseif p.ClassName == "UIGradient" then
			local seq = p.Color
			out.colors = if seq then { color(seq.a), color(seq.b) } else nil
			local tr = p.Transparency
			if tr and tr.Keypoints then
				local points = {}
				for _, k in tr.Keypoints do
					table.insert(points, { k.Time, k.Value })
				end
				out.tr = points
			end
			out.rot = p.Rotation
		elseif p.ClassName == "UIScale" then
			out.scale = p.Scale
		elseif p.ClassName == "UIListLayout" then
			out.pad = if p.Padding then p.Padding.Offset else 0
		end
		out.order = p.LayoutOrder
		if #n._children > 0 then
			local kids = {}
			for _, child in n._children do
				table.insert(kids, node(child))
			end
			out.kids = kids
		end
		return out
	end
	local scenes = {}
	local function scene(name: string, width: number, height: number, touch: boolean, bigOpen: boolean, x: number, z: number, lookX: number, lookZ: number)
		M.screen(width, height)
		-- (Hud's left stack: under the money panel at the bottom left on a computer, the top left on a touch screen)
		M.column.Position = if touch then M.UDim2.fromOffset(12, 64) else M.UDim2.fromOffset(16, height - 330)
		M.place(x, z, lookX, lookZ)
		M.look(lookX, lookZ)
		if MapView.isOpen() ~= bigOpen then
			MapView.toggle()
		end
		for _ = 1, 4 do
			M.frame(1 / 60)
		end
		table.insert(scenes, { name = name, width = width, height = height, tree = node(M.hud) })
	end
	-- Most of the valley uncovered, a stretch of the east and of the west still fog; every landmark known.
	M.uncover(function(x, z)
		return not (x > 1300 and z > -500 and z < 700) and not (x < -1400 and z > -1700 and z < -700)
	end)
	for _, landmark in Map.Landmarks do
		M.known[landmark.id] = true
	end
	M.Discovery.changed:Fire({})
	MapView.setTarget(M.Vector3.new(-1880, 0, 520)) -- the Old Farm, by the West Pass
	MapView.setWaypoint(M.Vector3.new(146, 0, -900)) -- the Gas Station
	scene("computer-big", 1280, 800, false, true, 0, -60, 0, -1)
	scene("computer-mini-pass", 1280, 800, false, false, -2095, 545, -1, 0)
	scene("phone-big", 844, 390, true, true, 0, -60, 0, -1)
	scene("phone-mini-town", 844, 390, true, false, 20, -200, 0, -1)
	scene("mini-north", 844, 390, true, false, -2080, -2880, -0.6, -1)
	scene("mini-south", 844, 390, true, false, 1600, 1420, 0.5, 1)
	local out = {}
	encode(scenes, out)
	print(table.concat(out))
end

if failures > 0 then
	error(`{failures} map check(s) failed`)
end
if not dump then
	print("ALL CHECKS PASSED")
end
