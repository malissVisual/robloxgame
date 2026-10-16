-- 9.4 SANDBOX, the countryside's art kit (shared/CountryLooks.luau; design/countryside/plan.py): every landmark kind
-- built in the map's own boxes (SandboxMap.Landmarks: each at its yaw) and in a few others, within its budget
-- (Config.Country.Budget), every piece inside its box and nothing under the ground (the haystack's rounded top's lower
-- half the one piece that reaches under it), its pieces sane (sizes, colours, materials, shapes VillageLooks knows),
-- the same every time; the jetty out over the pond's water, the boat on it, the bench and the willows on its bank; the
-- railway's portal at its back; the halt's MEADOW HALT sign; the lines (hedges, fences: posts at most Lines.Post apart, one
-- at each bend) and the stream (its water on its bed, every other segment a hair higher, its ends at its points) on the
-- map; the far rails outside the Bounds; nothing of a village (no chapel, no shop, no house) in the kit.
-- Run with tests/run_tests.py.
local Config = require("./Config")
local CountryLooks = require("./CountryLooks")
local VillageLooks = require("./VillageLooks")
local SandboxMap = require("./SandboxMap")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

type Box = VillageLooks.Box
local C = Config.Country
local EPS = 1e-3
local SHAPES: { [string]: boolean } = {}
for _, s in VillageLooks.Shapes do
	SHAPES[s] = true
end
local UNDER = { HaystackTop = true } -- (its rounded top's lower half in its straight sides, under the ground)

local function rect(r: any): Box
	return { x0 = r.x0, x1 = r.x1, z0 = r.z0, z1 = r.z1 }
end

-- ── The landmarks ──────────────────────────────────────────────────────────

do
	local kinds: { [string]: number } = {}
	for _, kind in CountryLooks.Landmarks do
		kinds[kind] = 0
		check(`{kind}: a budget (Config.Country.Budget)`, (C.Budget[kind] or 0) > 0 and CountryLooks.budget(kind) == C.Budget[kind])
	end
	-- every landmark of the map in its own box at its own yaw, and each kind in a box turned the other way too
	local cases: { { kind: string, box: Box, yaw: number, seed: number, name: string } } = {}
	for _, l in SandboxMap.Landmarks do
		if kinds[l.kind] then
			kinds[l.kind] += 1
			table.insert(cases, { kind = l.kind, box = rect(l), yaw = l.yaw, seed = VillageLooks.seedOf(l.id), name = l.id })
			table.insert(cases, { kind = l.kind, box = rect(l), yaw = (l.yaw + 180) % 360, seed = 7, name = `{l.id} turned` })
		end
	end
	local missing: { string } = {}
	for kind, n in kinds do
		if n == 0 then
			table.insert(missing, kind)
		end
	end
	check("every kind of the kit stands on the map (SandboxMap.Landmarks)", #missing == 0, table.concat(missing, ", "))
	local bad: string? = nil
	for _, c in cases do
		local pieces = CountryLooks.landmark(c.kind, c.box, c.yaw, c.seed)
		local again = CountryLooks.landmark(c.kind, c.box, c.yaw, c.seed)
		if #pieces == 0 or #pieces > CountryLooks.budget(c.kind) then
			bad = `{c.name}: {#pieces} parts (budget {CountryLooks.budget(c.kind)})`
		elseif #again ~= #pieces then
			bad = `{c.name}: not the same twice`
		end
		local f = VillageLooks.frame(c.box, c.yaw)
		for n, p in pieces do
			local x0, x1, y0, y1, z0, z1 = VillageLooks.box(p)
			local q = again[n]
			if x0 < -f.w / 2 - EPS or x1 > f.w / 2 + EPS or z0 < -f.d / 2 - EPS or z1 > f.d / 2 + EPS then
				bad = `{c.name}: its {p.name} out of its box ({x0}, {x1}, {z0}, {z1} in {f.w} × {f.d})`
			elseif y0 < -EPS and not UNDER[p.name] then
				bad = `{c.name}: its {p.name} under the ground ({y0})`
			elseif not SHAPES[p.shape] or #p.size ~= 3 or p.size[1] <= 0 or p.size[2] <= 0 or p.size[3] <= 0 or #p.color ~= 3 or type(p.material) ~= "string" then
				bad = `{c.name}: its {p.name} not a sane piece`
			elseif q.at[1] ~= p.at[1] or q.at[2] ~= p.at[2] or q.at[3] ~= p.at[3] or q.name ~= p.name then
				bad = `{c.name}: its {p.name} not the same twice`
			elseif p.chunk ~= (if c.kind == "railway" then "far" else VillageLooks.chunkOf(f.x, f.z)) then
				bad = `{c.name}: its {p.name} in chunk {p.chunk}`
			end
		end
	end
	check(`the map's landmarks of the kit ({#cases / 2}) and each turned round: within their budgets, inside their boxes, nothing under the ground, sane pieces, the same every time, in their chunk (the railway "far")`,
		bad == nil, bad)
	check("an unknown kind is an error", not pcall(CountryLooks.landmark, "chapel", { x0 = 0, x1 = 10, z0 = 0, z1 = 10 }, 0, 1))
	local village = { chapel = true, green = true, shop = true, hardware = true, barrier = true, school = true, pitch = true, station = true }
	local found: string? = nil
	for _, kind in CountryLooks.Landmarks do
		found = found or (if village[kind] then kind else nil)
	end
	check("nothing of a village in the kit (no chapel, green, shop, school, pitch, station)", found == nil, found)
end

-- the pond: its jetty over the water, the boat on it, the bench and the willows on its bank
do
	local pond: SandboxMap.Landmark? = nil
	for _, l in SandboxMap.Landmarks do
		if l.kind == "fishpond" then
			pond = l
		end
	end
	assert(pond, "no fish pond on the map")
	local pieces = CountryLooks.landmark("fishpond", rect(pond), pond.yaw, 1)
	local waters: { { number } } = {}
	local named: { [string]: { VillageLooks.Piece } } = {}
	for _, p in pieces do
		named[p.name] = named[p.name] or {}
		table.insert(named[p.name], p)
		if p.name == "Water" then
			table.insert(waters, { p.at[1], p.at[3], p.size[2] / 2, p.at[2] + p.size[1] / 2 })
		end
	end
	local function wet(x: number, z: number): boolean
		for _, w in waters do
			if (x - w[1]) ^ 2 + (z - w[2]) ^ 2 < w[3] ^ 2 then
				return true
			end
		end
		return false
	end
	local jetty = (named.Jetty or {})[1]
	local tops: { [number]: boolean } = {}
	for _, w in waters do
		tops[w[4]] = true
	end
	local distinct = 0
	for _ in tops do
		distinct += 1
	end
	check("the pond: three waters, each its own top (no two on one plane), over their banks", #waters == 3 and distinct == 3 and #(named.PondBank or {}) == 3
		and (function(): boolean
			for _, b in named.PondBank do
				for _, w in waters do
					if b.at[2] + b.size[1] / 2 >= w[4] then
						return false
					end
				end
			end
			return true
		end)())
	check("…its jetty from the front shore out over the water (its far end wet, its shore end dry), solid, over the water",
		jetty ~= nil and jetty.solid and wet(jetty.at[1], jetty.at[3] - jetty.size[3] / 2 + 1) and not wet(jetty.at[1], jetty.at[3] + jetty.size[3] / 2 - 0.5)
			and jetty.at[2] - jetty.size[2] / 2 > 0.34)
	local boat = (named.BoatFloor or {})[1]
	check("…the rowing boat on the water by the jetty, its oars, its seat", boat ~= nil and wet(boat.at[1], boat.at[3]) and #(named.Oar or {}) == 2 and #(named.BoatSeat or {}) == 1)
	local bench = (named.BenchSeat or {})[1]
	local dryTrees = true
	for _, t in named.Trunk or {} do
		dryTrees = dryTrees and not wet(t.at[1], t.at[3])
	end
	check("…a bench and two willows on the bank, reeds in the shallows", bench ~= nil and not wet(bench.at[1], bench.at[3]) and #(named.Trunk or {}) == 2 and dryTrees
		and #(named.Reeds or {}) >= 4)
end

-- the railway: its portal at its back (-Z: the D5's embankment), the rails its whole length; the halt's sign
do
	local p = CountryLooks.landmark("railway", { x0 = 0, x1 = 12, z0 = 0, z1 = 400 }, 0, 1)
	local frame = VillageLooks.frame({ x0 = 0, x1 = 12, z0 = 0, z1 = 400 }, 0)
	local rails, portal = 0, 0
	for _, q in p do
		if q.name == "Rail" and math.abs(q.size[3] - frame.d) < EPS then
			rails += 1
		elseif q.name == "Underpass" or q.name == "PortalLintel" or q.name == "PortalWall" then
			portal += if q.at[3] < -frame.d / 2 + 2.01 then 1 else 0
		end
	end
	check("the railway: two rails its whole length, its underpass's portal at its back", rails == 2 and portal == 4)
	local sign: VillageLooks.Piece? = nil
	for _, q in CountryLooks.landmark("halt", { x0 = 0, x1 = 80, z0 = 0, z1 = 16 }, 0, 1) do
		if q.tag == "sign" then
			sign = q
		end
	end
	check("the halt: its MEADOW HALT sign (its words to its front)", sign ~= nil and sign.text == "MEADOW HALT")
end

-- ── The lines and the stream (on the map) ──────────────────────────────────

do
	local square = { { x = 0, z = 0 }, { x = 100, z = 0 }, { x = 100, z = 50 } }
	local fence = CountryLooks.line("fence", square, 1)
	local posts, rails = 0, 0
	for _, p in fence do
		posts += if p.name == "FencePostCountry" then 1 else 0
		rails += if p.name == "FenceRailCountry" then 1 else 0
	end
	-- 100 / Post: ceil(100 / 24) = 5 bays (6 posts), 50: 3 bays (4 posts), the bend's shared
	local want = math.ceil(100 / C.Lines.Post) + math.ceil(50 / C.Lines.Post) + 1
	check(`a fence: its posts {C.Lines.Post} apart at most, one at the bend ({posts}), two rails a segment`, posts == want and rails == 4, `{posts} vs {want}`)
	local hedge = CountryLooks.line("hedge", square, 1)
	check("a hedge: a piece a segment, every other a hair taller, decoration", #hedge == 2 and hedge[1].size[2] ~= hedge[2].size[2] and not hedge[1].solid)
	check("an unknown line kind is an error", not pcall(CountryLooks.line, "wall", square, 1))
	local points = { { x = 0, z = 0 }, { x = 0, z = 100 }, { x = 30, z = 180 } }
	local stream = CountryLooks.stream(points, 8, 1)
	local beds, waters = {}, {}
	for _, p in stream do
		if p.name == "StreamBed" then
			table.insert(beds, p)
		elseif p.name == "Water" then
			table.insert(waters, p)
		end
	end
	local function top(p: VillageLooks.Piece): number
		return p.at[2] + p.size[2] / 2
	end
	-- (the first segment ends at its first point: along z from 0, its far end on past the bend by its half width)
	local first = waters[1]
	local x0, x1, _, _, z0, z1 = VillageLooks.box(first)
	check("a stream: its bed and its water each segment, the water over its bed, every other segment a hair higher",
		#beds == 2 and #waters == 2 and top(waters[1]) > top(beds[1]) and top(waters[2]) > top(beds[2]) and top(waters[1]) ~= top(waters[2])
			and not first.solid and math.abs(first.size[3] - 8) < EPS)
	check("…its first segment ending at its first point, reaching on past the bend", math.abs(z0 - 0) < EPS and math.abs(z1 - 104) < EPS and math.abs(x0 + 4) < EPS and math.abs(x1 - 4) < EPS,
		`{x0} {x1} {z0} {z1}`)
	-- the far rails: outside the Bounds, only where a railway meets their edge
	local B = SandboxMap.Bounds
	local far = CountryLooks.farRails({ { x0 = B.x0, x1 = B.x0 + 100, z0 = 700, z1 = 712 }, { x0 = 0, x1 = 10, z0 = 0, z1 = 12 } }, B)
	local outside = #far == 3
	for _, p in far do
		local a, b = VillageLooks.box(p)
		outside = outside and b <= B.x0 + EPS and a < B.x0 - 100 and p.chunk == "far"
	end
	check("the far rails: the railway going on past the Bounds at the edge it meets (none for one that does not)", outside, #far)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
