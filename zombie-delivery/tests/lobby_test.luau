-- 9.7 RUNS, the lobby (design/lobby/plan.py, plan.json; shared/SandboxMap.luau Lobby, written by tools/lobby/sandboxmap.py;
-- server/LobbyWorld.luau builds it, server/SandboxWorld.luau calls it): the owner's "shrink the map and put things quite
-- close together, so that it's one little lobby"; 10.4 "make the map smaller, and on the map just one circle where you'd
-- stand, like PLAY".
--   * the data: SandboxMap.Lobby is the plan's (LobbyPlan.luau, tests/run_tests.py writes it from plan.json): its
--     bounds (smaller than 9.7's 480 × 400), its PLAY circle (its radius Config.Runs.Play.Radius, on the plaza, the way
--     back off it facing it), the Auction House's, the TOP MOVERS board's and the PAINT shop's spots; every run zone far
--     from it (Lobby.far: 10.6 every other island's walls), the plots in it, the spawn on its plaza; a few seconds' walk
--     from the circle to the spawn, every warehouse's door and every shop; 10.6 its island (SandboxMap.Islands' first)
--     its bounds and a rim of grass round them, at GroundTop, its walls the bounds, its home the spawn;
--   * the world the real server/SandboxWorld.luau builds (SandboxWorldServer.luau on tools/perf/world-mock.luau, the
--     Auction House on): the Lobby model (Persistent) in workspace.Sandbox, every part of it in the lobby's bounds and
--     anchored; the plaza flush with the grass; the low hedge round it (10.6: Config.Islands.LobbyHedge, the other
--     islands seen over it) and the invisible walls on its bounds; the PLAY
--     circle (its glowing ring, its floor and glow, PLAY on the ground, its four lit posts outside it, the floating sign:
--     ▶ PLAY, STEP IN TO PLAY; nothing on its ground collides; the map's attribute "[]"); no portals any more; the
--     Deliveros dispatch (RunDispatch), the PAINT shop's booth (its prompt), the lamps and the trees as the plan has
--     them; nothing that collides in the circle, on the way back, the spawns, the dispatch's or the paint shop's front;
--     the Auction House in the lobby off the circle; nothing of the countryside in the lobby.
-- Run with tests/run_tests.py.
local Mock = require("./WorldMock")
local G = Mock.globals
local Enum = G.Enum
local workspace = Mock.workspace
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local AuctionHouseLayout = require("./AuctionHouseLayout")
local Plan = require("./LobbyPlan")

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
local L = SandboxMap.Lobby
local EPS = 1e-6
local function same(a: Rect, b: Rect): boolean
	return math.abs(a.x0 - b.x0) < EPS and math.abs(a.x1 - b.x1) < EPS and math.abs(a.z0 - b.z0) < EPS and math.abs(a.z1 - b.z1) < EPS
end
local function overlaps(a: Rect, b: Rect, margin: number?): boolean
	local m = margin or 0
	return a.x0 < b.x1 + m and b.x0 < a.x1 + m and a.z0 < b.z1 + m and b.z0 < a.z1 + m
end
local function distance(a: Rect, b: Rect): number
	local dx = math.max(a.x0 - b.x1, 0, b.x0 - a.x1)
	local dz = math.max(a.z0 - b.z1, 0, b.z0 - a.z1)
	return math.sqrt(dx * dx + dz * dz)
end
local function around(x: number, z: number, r: number): Rect
	return { x0 = x - r, x1 = x + r, z0 = z - r, z1 = z + r }
end

-- ── The data ───────────────────────────────────────────────────────────────

do
	check("SandboxMap.Lobby's bounds and Far the plan's", same(L.bounds, Plan.bounds) and L.far == Plan.far and L.far >= 250)
	local island = SandboxMap.Islands[1]
	local ib = island.rect
	check("10.6 the lobby's island: the first, its top the bounds and a rim of grass round them at GroundTop, its walls the bounds, its home the spawn",
		island.id == "lobby" and island.house == nil and island.top == SandboxMap.GroundTop and ib.x0 < L.bounds.x0 and ib.x1 > L.bounds.x1 and ib.z0 < L.bounds.z0
			and ib.z1 > L.bounds.z1 and same(island.walls, L.bounds) and island.home.x == L.spawn.x and island.home.z == L.spawn.z
			and SandboxMap.islandAt(L.spawn.x, L.spawn.z) == island and SandboxMap.groundAt(L.play.x, L.play.z) == SandboxMap.GroundTop)
	local p = L.play
	check("10.4 …its PLAY circle the plan's (its middle, its radius, the way back); its radius Config.Runs.Play.Radius", p.x == Plan.play.x and p.z == Plan.play.z
		and p.r == Plan.play.r and p.back.x == Plan.play.back.x and p.back.z == Plan.play.back.z and p.back.yaw == Plan.play.back.yaw and p.r == Config.Runs.Play.Radius
		and p.r >= 12)
	check("…no portals any more (one circle for every house)", (L :: any).portals == nil and (SandboxMap :: any).portal == nil)
	local spotsOk = L.shops.auction.spot.x == Plan.auction.x and L.shops.auction.spot.z == Plan.auction.z and L.shops.leaders.spot.x == Plan.leaders.x
		and L.shops.leaders.spot.z == Plan.leaders.z and same(L.shops.paint.rect, Plan.paint)
	check("…the Auction House's, the TOP MOVERS board's and the PAINT shop's spots the plan's; Config.Auction.House.Spot the lobby's", spotsOk
		and Config.Auction.House.Spot.x == L.shops.auction.spot.x and Config.Auction.House.Spot.z == L.shops.auction.spot.z
		and Config.Auction.House.Spot.yaw == L.shops.auction.spot.yaw)
	check("SandboxMap.inPlay: the circle's middle and its edge in it, a stud past it not (nor a margin's worth more)", SandboxMap.inPlay(p.x, p.z)
		and SandboxMap.inPlay(p.x + p.r - 0.01, p.z) and not SandboxMap.inPlay(p.x + p.r + 1, p.z) and SandboxMap.inPlay(p.x + p.r + 1, p.z, 2))
	local b = L.bounds
	local diagonal = math.sqrt((b.x1 - b.x0) ^ 2 + (b.z1 - b.z0) ^ 2)
	check(`10.4 small: {b.x1 - b.x0} × {b.z1 - b.z0} studs (the four plots side by side its width; 9.7: 480 × 400), corner to corner in under 40 s on foot`,
		diagonal / Config.Movement.Walk < 40 and b.x1 - b.x0 <= 460 and b.z1 - b.z0 <= 240, diagonal / Config.Movement.Walk)
	local far = math.huge
	for _, z in SandboxMap.Zones do
		far = math.min(far, distance(z.rect, b))
	end
	check(`every run zone (10.6: every other island's walls) {L.far} studs and more off the lobby (the nearest {math.floor(far)})`, far >= L.far, far)
	local inside = SandboxMap.inLobby(L.spawn.x, L.spawn.z) and not SandboxMap.inLobby(SandboxMap.House.door.x, SandboxMap.House.door.z)
	for _, plot in SandboxMap.Plots do
		inside = inside and SandboxMap.inLobby(plot.rect.x0, plot.rect.z0) and SandboxMap.inLobby(plot.rect.x1, plot.rect.z1)
			and SandboxMap.inLobby(plot.warehouse.x, plot.warehouse.z) and SandboxMap.inLobby(plot.vanSpot.x, plot.vanSpot.z)
	end
	check("SandboxMap.inLobby: the spawn, the four plots (their warehouses) in it; a house to empty not", inside)
	local plaza = L.plaza
	local function inside(x: number, z: number, r: Rect): boolean
		return x > r.x0 and x < r.x1 and z > r.z0 and z < r.z1
	end
	check("the spawn on the plaza, looking north at the PLAY circle; the circle on the plaza; the dispatch beside the circle, looking at it",
		inside(L.spawn.x, L.spawn.z, plaza) and L.spawn.yaw == 0 and L.spawn.z > p.z + p.r and inside(p.x - p.r, p.z - p.r, plaza) and inside(p.x + p.r, p.z + p.r, plaza)
		and math.abs(L.dispatch.z - p.z) < 1 and L.dispatch.x < p.x - p.r and L.dispatch.yaw == 270)
	local back = p.back
	local clear = back.yaw == 0 and SandboxMap.inLobby(back.x, back.z)
	for n = 0, 3 do
		local across = (if n % 2 == 1 then -1 else 1) * math.ceil(n / 2) * Config.Runs.Apart
		clear = clear and not SandboxMap.inPlay(back.x + across, back.z, 2)
	end
	check("the way back from a run: in the lobby, a party of four off the circle (2 studs to spare), facing it", clear and back.z > p.z + p.r)
	local walk = Config.Movement.Walk
	local function far(ax: number, az: number, bx: number, bz: number): number
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2) / walk
	end
	local slow: string? = nil
	if far(L.spawn.x, L.spawn.z, p.x, p.z) > 4 then
		slow = "the spawn"
	end
	for _, plot in SandboxMap.Plots do
		if far(p.x, p.z, plot.door.x, plot.door.z) > 14 then
			slow = `plot {plot.id}'s door`
		end
	end
	for name, shop in L.shops do
		if far(p.x, p.z, shop.spot.x, shop.spot.z) > 10 then
			slow = `the {name}`
		end
	end
	check("10.4 a few seconds' walk: the spawn to PLAY in 4 s, PLAY to every warehouse's door in 14 s, to every shop in 10 s", slow == nil, slow)
end

-- ── The worldend

-- ── The world ──────────────────────────────────────────────────────────────

Config.Auction.On = true -- (the most it holds)
local SandboxWorld = require("./SandboxWorldServer")
local world = SandboxWorld.build()
type Box = { part: any, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number }
local function boxOf(d: any): Box
	local size = d.Size
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
	local hx = (math.abs(r00) * size.X + math.abs(r01) * size.Y + math.abs(r02) * size.Z) / 2
	local hy = (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2
	local hz = (math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2
	return { part = d, x0 = x - hx, x1 = x + hx, y0 = y - hy, y1 = y + hy, z0 = z - hz, z1 = z + hz }
end
local lobby = world:FindFirstChild("Lobby")
local parts: { Box } = {}
for _, d in (if lobby then lobby:GetDescendants() else {}) do
	if d:IsA("BasePart") then
		table.insert(parts, boxOf(d))
	end
end
local function named(name: string): { Box }
	local out = {}
	for _, b in parts do
		if b.part.Name == name then
			table.insert(out, b)
		end
	end
	return out
end

do
	check("the Lobby model in workspace.Sandbox, Persistent (every client always has it: coming back from a run never streams it in)", lobby ~= nil
		and lobby.ModelStreamingMode == Enum.ModelStreamingMode.Persistent, lobby and lobby.ModelStreamingMode)
	local out: string? = nil
	local anchored = true
	for _, b in parts do
		local r = L.bounds
		if b.x0 < r.x0 - EPS or b.x1 > r.x1 + EPS or b.z0 < r.z0 - EPS or b.z1 > r.z1 + EPS then
			out = `{b.part.Name} at {math.floor(b.x0)}, {math.floor(b.z0)}`
		end
		anchored = anchored and b.part.Anchored
	end
	check(`every part of it ({#parts}) in the lobby's bounds, anchored`, out == nil and anchored and #parts > 60, out)
	check(`…a lobby within its share of the map's budget ({#parts} parts, at most 400)`, #parts <= 400, #parts)
	local plaza = named("Plaza")[1]
	check("the plaza: its slab on SandboxMap.Lobby.plaza, its top flush with the grass", plaza ~= nil and math.abs(plaza.y1 - SandboxMap.GroundTop) < EPS
		and math.abs(plaza.x0 - L.plaza.x0) < 0.01 and math.abs(plaza.x1 - L.plaza.x1) < 0.01 and math.abs(plaza.z0 - L.plaza.z0) < 0.01, plaza and plaza.y1)
	check("…its fountain where the plan has it", #named("FountainBasin") == 1 and math.abs((named("FountainBasin")[1].x0 + named("FountainBasin")[1].x1) / 2 - L.fountain.x) < 0.01)
	local hedges, walls = named("LobbyHedge"), named("LobbyWall")
	local wallsOk = #walls == 4
	for _, w in walls do
		wallsOk = wallsOk and w.part.Transparency == 1 and w.part.CanCollide and w.y1 - w.y0 >= 40
	end
	local hedgeOk = #hedges == 4
	for _, h in hedges do
		hedgeOk = hedgeOk and h.part.CanCollide and math.abs(h.y1 - h.y0 - Config.Islands.LobbyHedge) < EPS and h.y1 - h.y0 <= 3.5
	end
	check("the hedge round it (4 solid rows, Lobby.hedge in; 10.6 low: the other islands seen over it) and the invisible walls on its bounds (4, high: a jump over the hedge goes nowhere)", hedgeOk and wallsOk)
	check("the plaza's lamps and the lobby's trees as the plan has them", #named("LampPole") == #L.lamps and #named("Trunk") == #L.trees and #L.trees > 0)
end

do
	local p = L.play
	local circle = lobby and lobby:FindFirstChild("PlayCircle")
	local function all(name: string): { any }
		local out = {}
		for _, d in (if circle then circle:GetDescendants() else {}) do
			if d.Name == name then
				table.insert(out, d)
			end
		end
		return out
	end
	check("10.4 no portals any more: the PLAY circle (PlayCircle) in their place, the map's attribute empty", lobby and lobby:FindFirstChild("Portals") == nil and circle ~= nil
		and circle:GetAttribute("PlayCircle") == true and circle:GetAttribute(Config.Runs.Party.Attribute) == "[]")
	local ring = all("PlayRing")[1]
	local rb = ring and boxOf(ring)
	check("…its glowing ring (Neon, Play.Free) on the ground round its middle, its radius; nothing on the ground collides", ring ~= nil and ring.Material == Enum.Material.Neon
		and ring.CanCollide == false and rb ~= nil and math.abs((rb.x0 + rb.x1) / 2 - p.x) < 0.01 and math.abs((rb.z0 + rb.z1) / 2 - p.z) < 0.01
		and math.abs((rb.x1 - rb.x0) - 2 * p.r) < 0.05 and rb.y1 < SandboxMap.GroundTop + 0.5 and all("PlayFloor")[1] ~= nil and all("PlayFloor")[1].CanCollide == false
		and all("PlayGlow")[1] ~= nil and all("PlayRim")[1] ~= nil)
	local letters = all("PlayLetter")
	local lettersIn = #letters == 14
	for _, l in letters do
		local lb = boxOf(l)
		lettersIn = lettersIn and not l.CanCollide and SandboxMap.inPlay(lb.x0, lb.z0) and SandboxMap.inPlay(lb.x1, lb.z1) and lb.y1 < SandboxMap.GroundTop + 0.5
	end
	check("…PLAY on the ground in it (14 bars of light, inside the ring, read from the south)", lettersIn, #letters)
	local posts = all("PlayPost")
	local postsOk = #posts == 4 and #all("PlayLamp") == 4
	for _, post in posts do
		local pb = boxOf(post)
		local dx, dz = (pb.x0 + pb.x1) / 2 - p.x, (pb.z0 + pb.z1) / 2 - p.z
		postsOk = postsOk and post.CanCollide and math.sqrt(dx * dx + dz * dz) > p.r + 1 and math.abs(math.abs(dx) - math.abs(dz)) < 0.01
	end
	check("…four lit posts outside it at its corners (the four ways in open)", postsOk)
	local sign = all("PlaySign")[1]
	local gui = sign and sign:FindFirstChild("Words")
	local title = gui and gui:FindFirstChild("Title")
	local status = gui and gui:FindFirstChild("Status")
	check("…the floating sign over it: ▶ PLAY, STEP IN TO PLAY (server/Parties.luau's line)", sign ~= nil and sign.Transparency == 1 and not sign.CanCollide
		and gui ~= nil and gui.ClassName == "BillboardGui" and title ~= nil and title.Text == "▶ PLAY" and status ~= nil and status.Text == "STEP IN TO PLAY"
		and boxOf(sign).y0 > SandboxMap.GroundTop + 8)
	local dispatch = lobby and lobby:FindFirstChild("ZdcDispatch")
	local board = dispatch and dispatch:FindFirstChild("Board", true)
	check("the Deliveros dispatch kiosk at Lobby.dispatch, its corkboard marked RunDispatch (server/Runs.luau's prompt there)", dispatch ~= nil and board ~= nil
		and board:GetAttribute("RunDispatch") == true and math.abs(dispatch:GetPivot().Position.X - L.dispatch.x) < 1)
	local paint: any = nil
	for _, d in lobby:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d:GetAttribute("PaintShop") == true then
			paint = d
		end
	end
	local stand = L.shops.paint.stand
	local at = paint and paint.Parent.Position
	check("the PAINT shop's booth: its counter's prompt \"Paint your truck\" (PaintShop), in reach from its stand", paint ~= nil and paint.ActionText == "Paint your truck"
		and at ~= nil and math.sqrt((at.X - stand.x) ^ 2 + (at.Z - stand.z) ^ 2) <= paint.MaxActivationDistance)
end

-- nothing that collides where people stand: the pads, the back spots, the spawns, the dispatch's and the paint shop's fronts
do
	local spots: { { name: string, rect: Rect } } = {}
	local back = L.play.back
	for n = 0, 3 do
		local across = (if n % 2 == 1 then -1 else 1) * math.ceil(n / 2) * Config.Runs.Apart
		table.insert(spots, { name = `the way back {n}`, rect = around(back.x + across, back.z, 1.5) })
	end
	for n = -2, 2 do
		local a = math.rad(L.spawn.yaw)
		local across = n * L.spawnApart
		table.insert(spots, { name = `the spawn {n}`, rect = around(L.spawn.x + math.cos(a) * across, L.spawn.z - math.sin(a) * across, 1.5) })
	end
	local d = L.dispatch
	local dl = { x = -math.sin(math.rad(d.yaw)), z = -math.cos(math.rad(d.yaw)) }
	table.insert(spots, { name = "the dispatch's front", rect = around(d.x + dl.x * 4, d.z + dl.z * 4, 1.5) })
	table.insert(spots, { name = "the paint shop's stand", rect = around(L.shops.paint.stand.x, L.shops.paint.stand.z, 1.5) })
	local blocked: string? = nil
	for _, d2 in world:GetDescendants() do
		if d2:IsA("BasePart") and d2.CanCollide and d2.Name ~= "LobbyWall" then
			local b = boxOf(d2)
			if b.y1 <= SandboxMap.GroundTop + 0.3 or b.y0 >= 8 then
				continue
			end
			for _, s in spots do
				local r = s.rect
				if b.x0 < r.x1 - EPS and b.x1 > r.x0 + EPS and b.z0 < r.z1 - EPS and b.z1 > r.z0 + EPS then
					blocked = `{d2.Name} on {s.name}`
				end
			end
		end
	end
	local inPlay: string? = nil
	for _, d2 in world:GetDescendants() do
		if d2:IsA("BasePart") and d2.CanCollide and d2.Name ~= "LobbyWall" and d2.Name ~= "Plaza" then
			local b = boxOf(d2)
			local dx = math.max(b.x0 - L.play.x, 0, L.play.x - b.x1)
			local dz = math.max(b.z0 - L.play.z, 0, L.play.z - b.z1)
			if b.y1 > SandboxMap.GroundTop + 0.3 and b.y0 < 8 and dx * dx + dz * dz < L.play.r * L.play.r then
				inPlay = d2.Name
			end
		end
	end
	check("nothing that collides in the PLAY circle, on the way back, the spawns, the dispatch's front or the paint shop's stand", blocked == nil and inPlay == nil,
		blocked or inPlay)
	-- the Auction House in the lobby, off the PLAY circle
	local site = AuctionHouseLayout.site()
	local play = L.play
	local clear = SandboxMap.inLobby(site.x0, site.z0) and SandboxMap.inLobby(site.x1, site.z1)
		and not overlaps(site, { x0 = play.x - play.r, x1 = play.x + play.r, z0 = play.z - play.r, z1 = play.z + play.r }, 8)
	check("the Auction House (on) in the lobby, off the PLAY circle (8 studs and more)", clear and world:FindFirstChild("AuctionHouse", true) ~= nil)
	-- nothing of the countryside in the lobby
	local village = world:FindFirstChild("Village")
	local stray: string? = nil
	for _, d2 in (if village then village:GetDescendants() else {}) do
		if d2:IsA("BasePart") then
			local b = boxOf(d2)
			if overlaps({ x0 = b.x0, x1 = b.x1, z0 = b.z0, z1 = b.z1 }, L.bounds) then
				stray = d2.Name
			end
		end
	end
	check("nothing of the countryside (Village's chunks) in the lobby", stray == nil, stray)
end

Config.Auction.On = false

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
