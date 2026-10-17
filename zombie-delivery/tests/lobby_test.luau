-- 9.7 RUNS, the lobby (design/lobby/plan.py, plan.json; shared/SandboxMap.luau Lobby, written by tools/lobby/sandboxmap.py;
-- server/LobbyWorld.luau builds it, server/SandboxWorld.luau calls it): the owner's "shrink the map and put things quite
-- close together, so that it's one little lobby".
--   * the data: SandboxMap.Lobby is the plan's (LobbyPlan.luau, tests/run_tests.py writes it from plan.json): its
--     bounds, its six portals (one a place to empty, their pads), the Auction House's, the TOP MOVERS board's and the
--     PAINT shop's spots; small (crossed in under a minute), every run zone far from it (Lobby.far), the plots in it,
--     the spawn on its plaza; every pad apart, a party's back spot off every pad;
--   * the world the real server/SandboxWorld.luau builds (SandboxWorldServer.luau on tools/perf/world-mock.luau, the
--     Auction House on): the Lobby model (Persistent) in workspace.Sandbox, every part of it in the lobby's bounds and
--     anchored; the plaza flush with the meadow; the hedge round it and the invisible walls on its bounds; each portal
--     its gate, facade (its house's detail), sign (its name, WALK ONTO THE PAD) and glowing pad (RunPad: Neon, no
--     collision); the ZDC dispatch (RunDispatch), the PAINT shop's booth (its prompt), the lamps and the trees as the
--     plan has them; nothing that collides on a pad, a back spot, the spawns, the dispatch's or the paint shop's front;
--     the Auction House in the lobby off every portal; nothing of the countryside in the lobby.
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
	check("SandboxMap.Lobby's bounds and Far the plan's", same(L.bounds, Plan.bounds) and L.far == Plan.far and L.far >= 1000)
	local portalsOk = #L.portals == #Plan.portals and #L.portals == 6
	for n, p in Plan.portals do
		local mine = L.portals[n]
		portalsOk = portalsOk and mine ~= nil and mine.house == p.house and mine.x == p.x and mine.z == p.z and mine.yaw == p.yaw and same(mine.pad, p.pad)
	end
	check("…its six portals the plan's (house, gate, yaw, pad)", portalsOk)
	local spotsOk = L.shops.auction.spot.x == Plan.auction.x and L.shops.auction.spot.z == Plan.auction.z and L.shops.leaders.spot.x == Plan.leaders.x
		and L.shops.leaders.spot.z == Plan.leaders.z and same(L.shops.paint.rect, Plan.paint)
	check("…the Auction House's, the TOP MOVERS board's and the PAINT shop's spots the plan's; Config.Auction.House.Spot the lobby's", spotsOk
		and Config.Auction.House.Spot.x == L.shops.auction.spot.x and Config.Auction.House.Spot.z == L.shops.auction.spot.z)
	local houses: { [string]: number } = {}
	for _, p in L.portals do
		houses[p.house] = (houses[p.house] or 0) + 1
	end
	local each = true
	for _, h in SandboxMap.Houses do
		each = each and houses[h.id] == 1 and SandboxMap.portal(h.id) ~= nil and SandboxMap.portal(h.id).name == h.name
	end
	check("a portal for each of the six places to empty, once (SandboxMap.portal: by its house's id, its name the place's)", each and SandboxMap.portal("nowhere") == nil)
	local b = L.bounds
	local diagonal = math.sqrt((b.x1 - b.x0) ^ 2 + (b.z1 - b.z0) ^ 2)
	check(`small: {b.x1 - b.x0} × {b.z1 - b.z0} studs (the four plots side by side its width), corner to corner in under 45 s on foot`,
		diagonal / Config.Movement.Walk < 45 and b.x1 - b.x0 <= 500 and b.z1 - b.z0 <= 500, diagonal / Config.Movement.Walk)
	local far = math.huge
	for _, z in SandboxMap.Zones do
		far = math.min(far, distance(z.rect, b))
	end
	check(`every run zone out of sight, {L.far} studs and more off the lobby (the nearest {math.floor(far)})`, far >= L.far, far)
	local inside = SandboxMap.inLobby(L.spawn.x, L.spawn.z) and not SandboxMap.inLobby(SandboxMap.House.door.x, SandboxMap.House.door.z)
	for _, plot in SandboxMap.Plots do
		inside = inside and SandboxMap.inLobby(plot.rect.x0, plot.rect.z0) and SandboxMap.inLobby(plot.rect.x1, plot.rect.z1)
			and SandboxMap.inLobby(plot.warehouse.x, plot.warehouse.z) and SandboxMap.inLobby(plot.vanSpot.x, plot.vanSpot.z)
	end
	check("SandboxMap.inLobby: the spawn, the four plots (their warehouses) in it; a house to empty not", inside)
	local p = L.plaza
	check("the spawn on the plaza; the dispatch at its edge", L.spawn.x > p.x0 and L.spawn.x < p.x1 and L.spawn.z > p.z0 and L.spawn.z < p.z1
		and math.abs(L.dispatch.z - p.z0) < 15 and L.dispatch.x > p.x0 and L.dispatch.x < p.x1)
	local apart, backs = true, true
	for i, a in L.portals do
		for j, c in L.portals do
			if j > i and overlaps(a.pad, c.pad, 4) then
				apart = false
			end
			if overlaps(around(a.back.x, a.back.z, 2), c.pad, 1) then
				backs = false
			end
		end
		backs = backs and SandboxMap.inLobby(a.back.x, a.back.z) and a.back.yaw == a.yaw
	end
	check("every pad 4 studs and more from the next; a party's back spot in the lobby, off every pad, facing the plaza (the portal's way)", apart and backs)
end

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
	check(`every part of it ({#parts}) in the lobby's bounds, anchored`, out == nil and anchored and #parts > 100, out)
	check(`…a lobby within its share of the map's budget ({#parts} parts, at most 700)`, #parts <= 700, #parts)
	local plaza = named("Plaza")[1]
	check("the plaza: its slab on SandboxMap.Lobby.plaza, its top flush with the meadow", plaza ~= nil and math.abs(plaza.y1 - SandboxMap.GroundTop) < EPS
		and math.abs(plaza.x0 - L.plaza.x0) < 0.01 and math.abs(plaza.x1 - L.plaza.x1) < 0.01 and math.abs(plaza.z0 - L.plaza.z0) < 0.01, plaza and plaza.y1)
	check("…its fountain in the middle of it", #named("FountainBasin") == 1 and math.abs((named("FountainBasin")[1].x0 + named("FountainBasin")[1].x1) / 2 - L.fountain.x) < 0.01)
	local hedges, walls = named("LobbyHedge"), named("LobbyWall")
	local wallsOk = #walls == 4
	for _, w in walls do
		wallsOk = wallsOk and w.part.Transparency == 1 and w.part.CanCollide and w.y1 - w.y0 >= 40
	end
	local hedgeOk = #hedges == 4
	for _, h in hedges do
		hedgeOk = hedgeOk and h.part.CanCollide and h.y1 - h.y0 >= 4
	end
	check("the hedge round it (4 solid rows, Lobby.hedge in) and the invisible walls on its bounds (4, high: a jump over the hedge goes nowhere)", hedgeOk and wallsOk)
	check("the plaza's lamps and the lobby's trees as the plan has them", #named("LampPole") == #L.lamps and #named("Trunk") == #L.trees and #L.trees > 0)
end

do
	local folder = lobby and lobby:FindFirstChild("Portals")
	local detail: { [string]: string } = { sandbox_house = "Bale", pond_cabin = "Boat", lone_house = "Mailbox", forest_lodge = "Antler", old_mill = "MillWheel",
		orchard_cottage = "AppleTrunk" }
	local bad: string? = nil
	for _, p in L.portals do
		local model = folder and folder:FindFirstChild(`Portal_{p.house}`)
		if not model then
			bad = `{p.house}: no portal`
			continue
		end
		local function has(name: string): any
			for _, d in model:GetDescendants() do
				if d.Name == name then
					return d
				end
			end
			return nil
		end
		local pad = model:FindFirstChild("RunPad")
		local sign = model:FindFirstChild("GateSign")
		local words = sign and sign:FindFirstChild("Words")
		local title = words and words:FindFirstChild("Title")
		local status = words and words:FindFirstChild("Status")
		if model:GetAttribute("RunPortal") ~= p.house or not has("GatePost") or not has("GateLintel") or not has("Facade") or not has(detail[p.house]) then
			bad = `{p.house}: its gate, facade or detail`
		elseif not pad or pad:GetAttribute("RunPad") ~= p.house or pad.CanCollide ~= false or pad.Material ~= Enum.Material.Neon then
			bad = `{p.house}: its pad`
		elseif not title or title.Text ~= string.upper(p.name) or not status or status.Text ~= "WALK ONTO THE PAD" then
			bad = `{p.house}: its sign`
		else
			local b = boxOf(pad)
			if math.abs(b.x0 - p.pad.x0) > 0.01 or math.abs(b.x1 - p.pad.x1) > 0.01 or math.abs(b.z0 - p.pad.z0) > 0.01 or math.abs(b.z1 - p.pad.z1) > 0.01 then
				bad = `{p.house}: its pad off its rect`
			end
		end
	end
	check("six portals (Portal_<house>, RunPortal), each its gate and a facade with its house's detail (bales, a boat, a mailbox, antlers, a mill wheel, an apple tree), its sign (its name, WALK ONTO THE PAD) and its glowing pad on its rect (RunPad: Neon, no collision)",
		folder ~= nil and #folder:GetChildren() == 6 and bad == nil, bad)
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
	for _, p in L.portals do
		table.insert(spots, { name = `{p.house}'s pad`, rect = p.pad })
		table.insert(spots, { name = `{p.house}'s back spot`, rect = around(p.back.x, p.back.z, 3) })
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
	check("nothing that collides on a pad, a back spot, the spawns, the dispatch's front or the paint shop's stand", blocked == nil, blocked)
	-- the Auction House in the lobby, off every portal and pad
	local site = AuctionHouseLayout.site()
	local clear = SandboxMap.inLobby(site.x0, site.z0) and SandboxMap.inLobby(site.x1, site.z1)
	for _, p in L.portals do
		clear = clear and not overlaps(site, p.pad, 2) and not overlaps(site, p.foot, 2)
	end
	check("the Auction House (on) in the lobby, off every portal and its pad", clear and world:FindFirstChild("AuctionHouse", true) ~= nil)
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
