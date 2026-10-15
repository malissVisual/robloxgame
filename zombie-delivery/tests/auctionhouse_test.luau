-- 8.8 SANDBOX, the Auction House (shared/AuctionHouseLayout.luau, Config.Auction.House; server/SandboxWorld.luau builds
-- it only while Config.Auction.On): its place (on Depot Row east of the crossroads, its door to the road, across from
-- the plots, near the TOP MOVERS board), every part inside its footprint and within its budget, a walk free from the
-- steps through the doorway down the aisle to the stage, the desk, the lot's pedestal, the sign and the lot display;
-- clear of today's map (the roads and their 12 studs, the plots, the vans' ways, the house, the signpost, the lamps, the
-- trees, the flowers, the board; flat meadow) and of design/jinocany/plan.json (JinocanyPlan.luau: the village's roads,
-- landmarks, fields, houses and tree lines: it stays where it stands when the village is built); turned with its spot;
-- and the world SandboxWorld builds: nothing of it while the auction is off; on, the model, its parts as laid out, its
-- words, the desk's prompt, the lamps, nothing of the map within 1.5 studs of it, the map's budget and rules kept.
-- Run with tests/run_tests.py.
local Mock = require("./WorldMock")
local G = Mock.globals
local Enum = G.Enum
local workspace = Mock.workspace
local Config = require("./Config")
local Layout = require("./AuctionHouseLayout")
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")
local Leaders = require("./SandboxLeadersRules")
local Plan = require("./JinocanyPlan")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

type Rect = { x0: number, x1: number, z0: number, z1: number }
local H = Config.Auction.House
local C = SandboxScenery.Clear
local MAIN, DEPOT = SandboxMap.Roads[1], SandboxMap.Roads[2]
local EPS = 1e-6

local function rectDistance(r: Rect, x: number, z: number): number
	return SandboxScenery.rectDistance(r, x, z)
end
-- The point in the spot's frame (u across, v into the hall).
local function toLocal(x: number, z: number): (number, number)
	local s = Layout.spot()
	local a = math.rad(s.yaw)
	local dx, dz = x - s.x, z - s.z
	return dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
end
-- A part's box in the spot's frame (its turn a multiple of 90° from the spot's)
local function localBox(p: Layout.Part): (number, number, number, number)
	local u, v = toLocal(p.x, p.z)
	local turn = math.rad(p.yaw - Layout.spot().yaw)
	local c, s = math.abs(math.cos(turn)), math.abs(math.sin(turn))
	local hu, hv = (c * p.sx + s * p.sz) / 2, (s * p.sx + c * p.sz) / 2
	return u - hu, u + hu, v - hv, v + hv
end
-- Points all over the footprint (every stud) grown by `by` studs, on the map.
local function samples(by: number): { { number } }
	local f = Layout.footprint()
	local out = {}
	local nu, nv = math.ceil((f.u1 - f.u0 + 2 * by)), math.ceil((f.v1 - f.v0 + 2 * by))
	for i = 0, nu do
		for j = 0, nv do
			local x, z = Layout.toWorld(f.u0 - by + (f.u1 - f.u0 + 2 * by) * i / nu, f.v0 - by + (f.v1 - f.v0 + 2 * by) * j / nv)
			table.insert(out, { x, z })
		end
	end
	return out
end
local function overlaps(a: Rect, b: Rect, grow: number): boolean
	return a.x0 < b.x1 + grow and b.x0 < a.x1 + grow and a.z0 < b.z1 + grow and b.z0 < a.z1 + grow
end

-- ── Its place ───────────────────────────────────────────────────────────────
local function placeChecks(label: string)
	local f = Layout.footprint()
	local corners = Layout.corners()
	local site = Layout.site()
	local w = math.sqrt((corners[1].x - corners[2].x) ^ 2 + (corners[1].z - corners[2].z) ^ 2)
	local d = math.sqrt((corners[2].x - corners[3].x) ^ 2 + (corners[2].z - corners[3].z) ^ 2)
	check(`{label}: the footprint: the hall, the roof's overhang, the canopy and the steps; its corners turned with the spot`, math.abs(w - (f.u1 - f.u0)) < EPS and math.abs(d - (f.v1 - f.v0)) < EPS
		and f.u1 - f.u0 == H.Width + 2 * Layout.Over and f.v0 == -Layout.Porch and f.v1 == H.Depth + Layout.Over)
	local within = true
	for _, c in corners do
		within = within and c.x >= site.x0 - EPS and c.x <= site.x1 + EPS and c.z >= site.z0 - EPS and c.z <= site.z1 + EPS
	end
	local mx, mz = Layout.toWorld(0, H.Depth / 2)
	local bx, bz = Layout.toWorld(0, f.v1 + 1)
	check(`{label}: the site holds its corners; covers() is the footprint`, within and Layout.covers(mx, mz) and not Layout.covers(bx, bz) and Layout.covers(bx, bz, 1.5))
	local parts = Layout.parts()
	local outside: string? = nil
	for _, p in parts do
		local u0, u1, v0, v1 = localBox(p)
		if u0 < f.u0 - 0.05 or u1 > f.u1 + 0.05 or v0 < f.v0 - 0.05 or v1 > f.v1 + 0.05 or p.y - p.sy / 2 < -0.5 then
			outside = `{p.name} at {u0}…{u1}, {v0}…{v1}`
		end
	end
	check(`{label}: every one of its {#parts} parts inside the footprint, none under the ground`, outside == nil, outside)
	-- the walk in: from the steps through the doorway, down the aisle to the stage, nothing solid at body height
	local aisle = Layout.aisle()
	local blocked: string? = nil
	for _, p in parts do
		if p.solid then
			local u0, u1, v0, v1 = localBox(p)
			local y0, y1 = p.y - p.sy / 2, p.y + p.sy / 2
			if u0 < aisle.u1 and u1 > aisle.u0 and v0 < aisle.v1 and v1 > aisle.v0 and y1 > Layout.Floor + 0.05 and y0 < Layout.Floor + 6 then
				blocked = p.name
			end
		end
	end
	check(`{label}: the way in is free: the steps, the doorway ({H.Door[1]} wide), the aisle to the stage`, blocked == nil and aisle.v0 < 0 and aisle.v1 > H.Depth / 2 and aisle.u1 - aisle.u0 >= 6, blocked)
	local deskSpot = Layout.desk()
	local du, dv = toLocal(deskSpot.x, deskSpot.z)
	local inSolid: string? = nil
	for _, p in parts do
		local u0, u1, v0, v1 = localBox(p)
		local y0, y1 = p.y - p.sy / 2, p.y + p.sy / 2
		if p.solid and y1 > Layout.Floor + 0.05 and y0 < Layout.Floor + 6 and du > u0 - 1 and du < u1 + 1 and dv > v0 - 1 and dv < v1 + 1 then
			inSolid = p.name
		end
	end
	check(`{label}: the desk's front: in the hall, a stud clear of anything solid at body height`, inSolid == nil and du > -H.Width / 2 + 1 and du < H.Width / 2 - 1 and dv > 1 and dv < H.Depth - 1, inSolid)
end

do
	local spot = Layout.spot()
	check("one place for it: Config.Auction.House.Spot (on the ground)", spot == H.Spot and spot.y == 0)
	local site = Layout.site()
	check("on Depot Row east of the crossroads (the Jinočany plan's Corner Drugstore keeps x 40 – 120): x 132 … 184, z -26 … 12", site.x0 == 132 and site.x1 == 184 and site.z0 == -26 and site.z1 == 12,
		`{site.x0} … {site.x1}, {site.z0} … {site.z1}`)
	local door = Layout.door()
	local lx, lz = -math.sin(math.rad(door.yaw)), -math.cos(math.rad(door.yaw))
	check("its door looks out over Depot Row, 20 studs off its edge (players see it from their plots)", lx == 0 and lz == -1 and math.abs(door.z - DEPOT.z1 - 20) < EPS and SandboxMap.plotAt(door.x, DEPOT.z0 - 20) ~= nil)
	local board = Leaders.spot()
	local cross = { x = (MAIN.x0 + MAIN.x1) / 2, z = (DEPOT.z0 + DEPOT.z1) / 2 }
	check("near the TOP MOVERS board and the crossroads", math.sqrt((door.x - board.x) ^ 2 + (door.z - board.z) ^ 2) < 130 and math.sqrt((door.x - cross.x) ^ 2 + (door.z - cross.z) ^ 2) < 170)
	local tags: { [string]: number } = {}
	for _, p in Layout.parts() do
		if p.tag then
			tags[p.tag] = (tags[p.tag] or 0) + 1
		end
	end
	check("its parts: one sign, one lot display, one notice, one desk, one pedestal, two lamps", tags.sign == 1 and tags.screen == 1 and tags.notice == 1 and tags.desk == 1 and tags.stand == 1 and tags.lamp == 2)
	check(`within its budget ({#Layout.parts()} parts, at most {H.Budget})`, #Layout.parts() <= H.Budget and #Layout.parts() >= 60)
	check("the same parts every time", Layout.parts() == Layout.parts())
	local names: { [string]: boolean } = {}
	local named = true
	for _, p in Layout.parts() do
		named = named and string.sub(p.name, 1, 7) == "Auction" and (p.shape == "block" or p.shape == "wedge")
		names[p.name] = true
	end
	check("every part named Auction… (no name of the map's: Path, LampPole, SignBoard …), a block or a wedge", named and names.AuctionDesk and names.AuctionScreen and names.AuctionLotStand and names.AuctionBench)
	local screen, sign
	for _, p in Layout.parts() do
		if p.tag == "screen" then
			screen = p
		elseif p.tag == "sign" then
			sign = p
		end
	end
	local _, sv = toLocal(screen.x, screen.z)
	local _, gv = toLocal(sign.x, sign.z)
	check("the lot display on the back wall over the stage, facing the hall; the sign over the door, facing the road", sv > H.Depth - 2 and screen.y > Layout.Floor + 5 and screen.yaw == H.Spot.yaw
		and gv < 0 and sign.y > H.Door[2] and sign.yaw == H.Spot.yaw)
	placeChecks("as placed")
end

-- ── Clear of today's map ────────────────────────────────────────────────────
do
	local B = SandboxMap.Bounds
	local inset = SandboxScenery.FenceInset + C.Edge
	local why: string? = nil
	local trees = SandboxScenery.trees()
	local flowers = SandboxScenery.flowers()
	local lamps = SandboxScenery.lamps()
	local sign = SandboxScenery.Signpost
	local margin = 3
	for _, p in samples(0) do
		local x, z = p[1], p[2]
		if x < B.x0 + inset or x > B.x1 - inset or z < B.z0 + inset or z > B.z1 - inset then
			why = "outside the fence"
		end
		local rule = SandboxScenery.treeRule(x, z, 0) -- (the roads' 12 studs, the turnaround, the plots, the house, its path, the vans' ways, the signpost)
		if rule or SandboxMap.plotAt(x, z) then
			why = `where SandboxScenery says no ({rule or "a plot"}) at {x}, {z}`
		end
		for n, way in SandboxScenery.vanPaths() do
			if rectDistance(way, x, z) < C.Plot then
				why = `on van way {n}`
			end
		end
		if math.sqrt((x - sign.x) ^ 2 + (z - sign.z) ^ 2) < C.Sign + margin then
			why = "on the signpost"
		end
		for _, l in lamps do
			for t = 0, 4.4, 0.4 do
				if math.sqrt((x - (l.x + l.rx * t)) ^ 2 + (z - (l.z + l.rz * t)) ^ 2) < margin then
					why = `on the lamp at {l.x}, {l.z}`
				end
			end
		end
		for _, t in trees do
			if math.sqrt((x - t.x) ^ 2 + (z - t.z) ^ 2) < t.canopy + margin then
				why = `under the tree at {math.floor(t.x)}, {math.floor(t.z)}`
			end
		end
		for _, f in flowers do
			if math.sqrt((x - f.x) ^ 2 + (z - f.z) ^ 2) < f.size + margin then
				why = `on the wildflowers at {math.floor(f.x)}, {math.floor(f.z)}`
			end
		end
		if math.abs(SandboxScenery.groundAt(x, z) - SandboxMap.GroundTop) > 1e-9 then
			why = `on a mound at {x}, {z}`
		end
		for _, c in Leaders.corners() do
			if math.sqrt((x - c.x) ^ 2 + (z - c.z) ^ 2) < 8 then
				why = "within 8 studs of the TOP MOVERS board"
			end
		end
	end
	check("clear of today's map: inside the fence, 12 studs off every road, off the plots, the vans' ways, the house and its path, the signpost, the lamps, the trees, the flowers and the TOP MOVERS board, on flat meadow", why == nil, why)
end

-- ── Clear of the Jinočany plan (design/jinocany/plan.json) ──────────────────
do
	local site = Layout.site()
	local b = Plan.bounds
	local why: string? = nil
	if site.x0 < b.x0 or site.x1 > b.x1 or site.z0 < b.z0 or site.z1 > b.z1 then
		why = "outside the plan's bounds"
	end
	for _, area in Plan.areas do
		local road = string.sub(area.name, 1, 5) == "road "
		if overlaps(site, area.rect, if road then 12 else 6) then
			why = `on (or within {if road then 12 else 6} studs of) the plan's {area.name}`
		end
	end
	for n, line in Plan.treeLines do
		for i = 2, #line do
			local a, c = line[i - 1], line[i]
			local length = math.sqrt((c[1] - a[1]) ^ 2 + (c[2] - a[2]) ^ 2)
			for t = 0, length, 2 do
				local k = if length > 0 then t / length else 0
				if rectDistance(site, a[1] + (c[1] - a[1]) * k, a[2] + (c[2] - a[2]) * k) < 10 then
					why = `on tree line {n}`
				end
			end
		end
	end
	check(`clear of the Jinočany plan: its {#Plan.areas} roads, landmarks, fields and houses (12 studs off a road, 6 off the rest) and its tree lines`, why == nil and #Plan.areas > 100, why)
	local drugstore: Rect? = nil
	for _, area in Plan.areas do
		if area.name == "drugstore" then
			drugstore = area.rect
		end
	end
	check("…beside the plan's Corner Drugstore on Depot Row (east of it, a street front together)", drugstore ~= nil and site.x0 > (drugstore :: Rect).x1 and site.x0 - (drugstore :: Rect).x1 < 20)
end

-- ── Turned with its spot ────────────────────────────────────────────────────
do
	local saved = H.Spot
	H.Spot = { x = -150, y = 0, z = 120, yaw = 90 }
	local door = Layout.door()
	local a = math.rad(door.yaw)
	check("a spot turned 90°: the door looks west, the hall behind it to the east", -math.sin(a) < -0.99 and Layout.site().x1 > H.Spot.x + H.Depth and door.x < H.Spot.x)
	placeChecks("turned 90°")
	H.Spot = saved
	check("…and back: the parts follow the spot again", Layout.site().x0 == 132)
end

-- ── The world SandboxWorld builds ───────────────────────────────────────────
require("./HouseMeshServer")
local SandboxWorld = require("./SandboxWorldServer")
local off = SandboxWorld.build()
check("the auction off (the default): no Auction House on the map", Config.Auction.On == false and off:FindFirstChild("AuctionHouse") == nil)
off:Destroy()
Config.Auction.On = true
local world = SandboxWorld.build()
local house = world:FindFirstChild("AuctionHouse")
check("the auction on: the model AuctionHouse in workspace.Sandbox, streamed whole", house ~= nil and house:IsA("Model") and house.ModelStreamingMode == Enum.ModelStreamingMode.Atomic and house:GetAttribute("AuctionHouse") == true)
do
	local specs = Layout.parts()
	local built = {}
	for _, d in house:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(built, d)
		end
	end
	local same = #built == #specs
	for i, p in specs do
		local b = built[i]
		if not b then
			same = false
			break
		end
		local x, y, z = b.CFrame:GetComponents()
		same = same and b.Name == p.name and math.abs(x - p.x) < 1e-6 and math.abs(y - p.y) < 1e-6 and math.abs(z - p.z) < 1e-6 and b.Anchored
			and b.Size.X == p.sx and b.Size.Y == p.sy and b.Size.Z == p.sz and b.CanCollide == p.solid and b:IsA(if p.shape == "wedge" then "WedgePart" else "Part")
	end
	check(`its {#built} parts as laid out: where, how big, anchored, solid or decoration, block or wedge`, same, #built)
	local shadows: string? = nil
	for _, b in built do
		local s = b.Size
		local long, short = math.max(s.X, s.Y, s.Z), math.min(s.X, s.Y, s.Z)
		if b.CastShadow and (long < SandboxScenery.Shadow.Long or s.X + s.Y + s.Z - long - short < SandboxScenery.Shadow.Wide) then
			shadows = b.Name
		end
	end
	check("shadows only from its bigger parts", shadows == nil, shadows)
	local function words(tag: string): any
		for i, p in specs do
			if p.tag == tag then
				return built[i]:FindFirstChild("Words")
			end
		end
		return nil
	end
	local sign, screen, notice = words("sign"), words("screen"), words("notice")
	local function text(gui: any, name: string): string?
		local found = gui and gui:FindFirstChild(name)
		return if found then found.Text else nil
	end
	local signOk = sign ~= nil and sign:IsA("SurfaceGui") and sign.Face == Enum.NormalId.Front
	for _, name in Layout.SignLabels do
		signOk = signOk and sign:FindFirstChild(name) ~= nil
	end
	local screenOk = screen ~= nil and screen.Face == Enum.NormalId.Front and screen.MaxDistance == H.Range
	for _, name in Layout.ScreenLabels do
		screenOk = screenOk and screen:FindFirstChild(name) ~= nil
	end
	check("the sign's words (AUCTION HOUSE, the next auction's line) and the lot display's (title, piece, facts, price, leader, clock), empty for the client to paint",
		signOk and text(sign, "Title") == "AUCTION HOUSE" and text(sign, "Next") == "" and screenOk and text(screen, "Title") == "AUCTION HOUSE" and text(screen, "Price") == "")
	check("the desk's board faces the hall: CONSIGN HERE", notice ~= nil and notice.Face == Enum.NormalId.Left and text(notice, "Title") == "CONSIGN HERE")
	local prompt, stand, lights = nil, nil, 0
	for _, d in house:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			prompt = d
		elseif d:IsA("BasePart") and d:GetAttribute("AuctionLotStand") then
			stand = d
		elseif d:IsA("PointLight") then
			lights += 1
		end
	end
	check("the desk's prompt: Consign a piece (E, no hold, attribute AuctionDesk; the client opens the window)", prompt ~= nil and prompt.Parent.Name == "AuctionDesk" and prompt.ActionText == "Consign a piece"
		and prompt.HoldDuration == 0 and prompt.KeyboardKeyCode == Enum.KeyCode.E and prompt:GetAttribute("AuctionDesk") == true and prompt.Enabled ~= false)
	check("the lot's pedestal (AuctionLotStand: the server's step shows the piece there) and the two lamps' light", stand ~= nil and stand.Name == "AuctionLotStand" and lights == 2)
end
do
	-- nothing else of the map within 1.5 studs of its footprint (a separating-axis test against each part's box)
	local f = Layout.footprint()
	local a = math.rad(Layout.spot().yaw)
	local axes = { { math.cos(a), -math.sin(a) }, { math.sin(a), math.cos(a) } }
	local mu, mv = (f.u0 + f.u1) / 2, (f.v0 + f.v1) / 2
	local cx, cz = Layout.toWorld(mu, mv)
	local halves = { (f.u1 - f.u0) / 2 + 1.5, (f.v1 - f.v0) / 2 + 1.5 }
	local function hits(x0: number, x1: number, z0: number, z1: number): boolean
		local px = math.abs(axes[1][1]) * halves[1] + math.abs(axes[2][1]) * halves[2]
		local pz = math.abs(axes[1][2]) * halves[1] + math.abs(axes[2][2]) * halves[2]
		if cx + px < x0 or cx - px > x1 or cz + pz < z0 or cz - pz > z1 then
			return false
		end
		local bx, bz, hx, hz = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2, (z1 - z0) / 2
		for n, axis in axes do
			local centre = (bx - cx) * axis[1] + (bz - cz) * axis[2]
			if math.abs(centre) > halves[n] + math.abs(axis[1]) * hx + math.abs(axis[2]) * hz then
				return false
			end
		end
		return true
	end
	local hit: string? = nil
	local seen, total, out = 0, 0, nil
	local B = SandboxMap.Bounds
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") then
			total += 1
			local size = d.Size
			local x, _, z, r00, r01, r02, _, _, _, r20, r21, r22 = d.CFrame:GetComponents()
			local hx = (math.abs(r00) * size.X + math.abs(r01) * size.Y + math.abs(r02) * size.Z) / 2
			local hz = (math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2
			if d:IsDescendantOf(house) then
				if x - hx < B.x0 or x + hx > B.x1 or z - hz < B.z0 or z + hz > B.z1 then
					out = d.Name
				end
				for _, road in SandboxMap.Roads do
					if d.CanCollide and overlaps({ x0 = x - hx, x1 = x + hx, z0 = z - hz, z1 = z + hz }, road :: any, 0) then
						out = `{d.Name} on {road.name}`
					end
				end
			elseif d.Name ~= "Meadow" and d.Name ~= "Mound" and d.Shape ~= Enum.PartType.Ball then
				seen += 1
				if hits(x - hx, x + hx, z - hz, z + hz) then
					hit = `{d.Name} at {math.floor(x)}, {math.floor(z)}`
				end
			end
		end
	end
	check(`nothing else the map builds within 1.5 studs of it, only meadow under it ({seen} parts looked at)`, hit == nil and seen > 300, hit)
	check("its parts inside the Bounds, nothing of it on a road", out == nil, out)
	check(`the map's part budget holds with it ({total} parts, at most {SandboxScenery.Budget})`, total <= SandboxScenery.Budget, total)
end
Config.Auction.On = false

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
