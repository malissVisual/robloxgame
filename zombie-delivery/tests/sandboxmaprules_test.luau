-- 10.x THE MAP: shared/SandboxMapRules.luau, the big map's and the minimap's pure part (Config.SandboxMapUi). Checked:
-- the floor plan's code (server/HouseInterior.luau writes it on the interior: every sandbox house's plan of a few seeds
-- encoded and decoded back: its box, rooms, doorways (the front door and the ways out flagged), the solid fixtures on the
-- floor only, the windows on the walls' middle lines, the origin; short; junk and another version give none); world to
-- the plan's frame (a turned origin too) and back, its floor's box and height; every house's front yard in its plan's
-- frame (the door at 0, 0, out of it is -Z, the truck's curb straight out in front, its asphalt in the strip, pinned to
-- the strip's edge); the frames (the lobby fitted into a phone's and a big screen's map, north up, east right; a house
-- with its front door at the bottom, never a mirror image; following you; a ▲'s heading); the fog's rules (seen within
-- See studs with nothing between, shown until carried out, Epic and up pulse while loose); 10.4 the lobbies' words; the
-- window's layout on phones and computers; the minimap's corner kept clear of the HUD, shrunk, else none; the sandbox
-- houses' plan kinds all different (the client finds a run's inside by its kind); SandboxPad's "map" action (M, L2, a
-- tap). Run with tests/run_tests.py.
local M = require("./ItemMock")
local Config = require("./Config")
local HouseLayout = require("./HouseLayout")
local SandboxMap = require("./SandboxMap")
local SandboxPad = require("./SandboxPad")
local Rules = require("./SandboxMapRules")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 0.051)
end

local C = Config.SandboxMapUi
local KINDS = { "big", "cabin", "house", "lodge", "mill", "cottage" }

-- ── The plan's code ──────────────────────────────────────────────────────────

do
	local bad: { string } = {}
	local longest = 0
	for _, kind in KINDS do
		for _, seed in { 7, 1955, 424242 } do
			local plan = HouseLayout.plan(seed, kind)
			local origin = { x = 9000 + seed % 7 * 600, y = 400, z = 9000, yaw = 0 }
			local code = Rules.encode(plan, origin)
			longest = math.max(longest, #code)
			local back = Rules.decode(code)
			local label = `{kind} {seed}`
			if not back then
				table.insert(bad, `{label}: no plan back`)
				continue
			end
			if back.kind ~= kind or not near(back.origin.x, origin.x) or not near(back.origin.z, origin.z) or not near(back.origin.y, 400) or back.origin.yaw ~= 0 then
				table.insert(bad, `{label}: its kind or origin`)
			end
			if not (near(back.box.x0, plan.min.X) and near(back.box.z0, plan.min.Z) and near(back.box.x1, plan.max.X) and near(back.box.z1, plan.max.Z) and near(back.wall, plan.wall)) then
				table.insert(bad, `{label}: its box`)
			end
			if #back.rooms ~= #plan.rooms then
				table.insert(bad, `{label}: {#back.rooms} rooms of {#plan.rooms}`)
			else
				for n, r in plan.rooms do
					local b = back.rooms[n]
					if b.id ~= r.id or b.kind ~= r.kind or not (near(b.x0, r.min.X) and near(b.z0, r.min.Z) and near(b.x1, r.max.X) and near(b.z1, r.max.Z)) then
						table.insert(bad, `{label}: room {r.id}`)
					end
					if back.height < r.max.Y - 0.05 then
						table.insert(bad, `{label}: the height under room {r.id}'s ceiling`)
					end
				end
			end
			local exits, fronts = 0, 0
			if #back.doors ~= #plan.doors then
				table.insert(bad, `{label}: {#back.doors} doors of {#plan.doors}`)
			else
				for n, d in plan.doors do
					local b = back.doors[n]
					local out = table.find(d.rooms, "outside") ~= nil
					if not (near(b.x, d.at.X) and near(b.z, d.at.Z) and near(b.w, d.width) and b.axis == d.axis and b.out == out and b.front == d.front) then
						table.insert(bad, `{label}: door {n}`)
					end
					exits += if b.out then 1 else 0
					fronts += if b.front then 1 else 0
				end
			end
			local want = if kind == "big" then 2 else 1
			if exits ~= want or fronts ~= 1 or not back.doors[1].front then
				table.insert(bad, `{label}: {exits} ways out, {fronts} front doors (want {want}, 1, the first)`)
			end
			local solid = 0
			for _, f in plan.fixtures do
				if f.solid and f.at.Position.Y < 1 then
					solid += 1
				end
			end
			if #back.fixtures ~= solid then
				table.insert(bad, `{label}: {#back.fixtures} fixtures of {solid} solid ones on the floor`)
			end
			for _, f in back.fixtures do
				if f.kind == "rug" or f.kind == "picture" or f.kind == "antlers" or f.sx <= 0 or f.sz <= 0 then
					table.insert(bad, `{label}: a fixture {f.kind} drawn`)
				end
			end
			if #back.windows ~= #plan.windows then
				table.insert(bad, `{label}: {#back.windows} windows of {#plan.windows}`)
			end
			-- every window on the house's outer walls' middle lines (half a wall out of its inside face)
			for _, w in back.windows do
				local onEdge = near(w.x, plan.min.X + plan.wall / 2, 0.11) or near(w.x, plan.max.X - plan.wall / 2, 0.11)
					or near(w.z, plan.min.Z + plan.wall / 2, 0.11) or near(w.z, plan.max.Z - plan.wall / 2, 0.11)
				if not onEdge then
					table.insert(bad, `{label}: a window off the outer walls ({w.x}, {w.z})`)
				end
			end
		end
	end
	check("every sandbox house's plan (6 kinds × 3 seeds) encoded and decoded back: its box, rooms, doorways (the front door first, the ways out flagged: the big house's two), the solid fixtures on the floor only, the windows on the outer walls, the origin", #bad == 0, bad[1])
	check(`… in one short string (the longest {longest} characters: an attribute's room)`, longest > 200 and longest < 6000, longest)
	local plan = HouseLayout.plan(3, "cabin")
	local turned = Rules.decode(Rules.encode(plan, { x = 1.04, y = -2.06, z = 3, yaw = 90 }))
	check("… a turned origin's yaw kept, its numbers to a tenth", turned ~= nil and turned.origin.yaw == 90 and turned.origin.x == 1 and turned.origin.y == -2.1)
	local code = Rules.encode(plan, { x = 0, y = 0, z = 0, yaw = 0 })
	check("junk, another version, a broken entry, a number that is none or nothing: no plan", Rules.decode("nonsense") == nil and Rules.decode("2" .. string.sub(code, 2)) == nil
		and Rules.decode("1|cabin|0,0,0,0|0,0,1,1,1,3|a:b:1|||") == nil and Rules.decode("1|cabin|0,0,0,0|0,0,1,1,1,3|a:b:x:0:1:1|||") == nil
		and Rules.decode("1|cabin|0,0,0|0,0,1,1,1,3||||") == nil and Rules.decode(nil) == nil and Rules.decode("") == nil and Rules.decode(5) == nil)
	check("… the least plan (a room, nothing else) decodes", Rules.decode("1|cabin|0,0,0,0|0,0,1,1,1,3|a:b:0:0:1:1|||") ~= nil)
	local odd = { kind = "cab|in", wall = 1, min = M.Vector3.new(-1, 0, -1), max = M.Vector3.new(1, 3, 1), rooms = { { id = "a;b", kind = "c:d", min = M.Vector3.new(0, 0, 0), max = M.Vector3.new(1, 3, 1) } },
		doors = {}, fixtures = {}, windows = {} }
	local back = Rules.decode(Rules.encode(odd, { x = 0, y = 0, z = 0, yaw = 0 }))
	check("… a name with the code's own marks in it is written safely", back ~= nil and back.kind == "cab_in" and back.rooms[1].id == "a_b" and back.rooms[1].kind == "c_d")
end

-- ── Where things are ─────────────────────────────────────────────────────────

do
	local plan = Rules.decode(Rules.encode(HouseLayout.plan(11, "house"), { x = 9600, y = 400, z = 9000, yaw = 0 })) :: Rules.Plan
	local lx, lz = Rules.toLocal(plan, 9600 + 3, 9000 + 12)
	check("a world point in the plan's frame: less its origin", near(lx, 3) and near(lz, 12))
	check("… on its floor in its box, not under it, over its roof or beside it", Rules.inside(plan, 3, 12, 402) and not Rules.inside(plan, 3, 12, 400 - C.Below - 1)
		and not Rules.inside(plan, 3, 12, 400 + plan.height + C.Above + 1) and not Rules.inside(plan, plan.box.x1 + C.Inside + 1, 12, 402) and Rules.inside(plan, 3, 12))
	-- a turned origin: the interior's CFrame.Angles(0, rad(90), 0) puts the local (3, 7) at world (7, -3) from it
	local turned = Rules.decode(Rules.encode(HouseLayout.plan(11, "house"), { x = 100, y = 0, z = 200, yaw = 90 })) :: Rules.Plan
	local tx, tz = Rules.toLocal(turned, 100 + 7, 200 - 3)
	check("… a turned origin turned back (yaw 90: world (7, -3) off it is (3, 7))", near(tx, 3, 1e-6) and near(tz, 7, 1e-6), `{tx}, {tz}`)
	local wx, wz = Rules.turn(-1, 0, 90)
	check("… a look turned the same way (yaw 90: west in the world is the plan's -Z)", near(wx, 0, 1e-9) and near(wz, -1, 1e-9), `{wx}, {wz}`)
end

do
	local bad: { string } = {}
	for _, h in SandboxMap.Houses do
		local yard = Rules.yard(h.id)
		if not yard then
			table.insert(bad, `{h.id}: no yard`)
			continue
		end
		local dx, dz = Rules.toYard(yard, h.door.x, h.door.z)
		local ox, oz = Rules.toYard(yard, h.door.x + (if h.yaw == 90 then -10 elseif h.yaw == 270 then 10 else 0), h.door.z + (if h.yaw == 0 then -10 elseif h.yaw == 180 then 10 else 0))
		local tx, tz = Rules.toYard(yard, h.curb.x, h.curb.z)
		if not (near(dx, 0, 1e-6) and near(dz, 0, 1e-6)) then
			table.insert(bad, `{h.id}: its door at {dx}, {dz}`)
		end
		if not (near(ox, 0, 1e-6) and near(oz, -10, 1e-6)) then
			table.insert(bad, `{h.id}: 10 studs out of its door at {ox}, {oz} (want 0, -10)`)
		end
		if not (near(tx, 0, 0.5) and tz < -10 and near(yard.truck.x, tx) and near(yard.truck.z, tz)) then
			table.insert(bad, `{h.id}: its truck at {tx}, {tz}`)
		end
		if not (Rules.inYard(yard, 0, -1) and Rules.inYard(yard, tx, tz) and yard.strip.z1 == 0 and yard.strip.z0 <= tz - C.Yard.Truck / 2) then
			table.insert(bad, `{h.id}: the strip misses the door or the truck`)
		end
		local road = yard.road
		if not road or road.z1 > 0 or road.z0 < yard.strip.z0 - 1e-6 or road.x1 - road.x0 < 20 then
			table.insert(bad, `{h.id}: its asphalt not in the strip`)
		end
		local px, pz = Rules.clampYard(yard, 500, -1000)
		if not (px == yard.strip.x1 and pz == yard.strip.z0) or Rules.inYard(yard, 0, 5) or not Rules.inYard(yard, 0, 1, 2) then
			table.insert(bad, `{h.id}: pinned or the strip's edge`)
		end
	end
	check("every house's front yard in its plan's frame: its door at 0, 0, out of it -Z, its truck's curb straight out in front, the strip from the door past the truck, its asphalt in it, pinned to its edge", #bad == 0, bad[1])
	check("… no yard for an unknown house", Rules.yard("nope") == nil and Rules.yard(nil) == nil)
	local plan = Rules.decode(Rules.encode(HouseLayout.plan(5, "big"), { x = 0, y = 0, z = 0, yaw = 0 })) :: Rules.Plan
	local yard = Rules.yard("sandbox_house") :: Rules.Yard
	local box = Rules.houseBox(plan, yard)
	check("what a run's map shows: the plan and the yard's strip under it, as wide as the plan", box.x0 == plan.box.x0 and box.x1 == plan.box.x1 and box.z1 == plan.box.z1 and box.z0 == yard.strip.z0
		and yard.strip.x0 == plan.box.x0 and yard.strip.x1 == plan.box.x1)
	local lobby = Rules.lobbyBox()
	check("the lobby's map: its bounds", lobby.x0 == SandboxMap.Lobby.bounds.x0 and lobby.z1 == SandboxMap.Lobby.bounds.z1)
end

-- ── Drawing ──────────────────────────────────────────────────────────────────

do
	local box = Rules.lobbyBox()
	for _, size in { { 600, 290, "a phone's map" }, { 1500, 900, "a big screen's map" } } do
		local w, h = size[1], size[2]
		local f = Rules.fit(box, 0, w, h, 6)
		local x0, y0, x1, y1 = Rules.rectOn(f, box.x0, box.z0, box.x1, box.z1)
		check(`{size[3]} ({w} × {h}): the lobby fitted inside it, 6 px round it, as big as it fits`, x0 >= 6 - 1e-6 and y0 >= 6 - 1e-6 and x1 <= w - 6 + 1e-6 and y1 <= h - 6 + 1e-6
			and (near(x1 - x0, w - 12, 0.01) or near(y1 - y0, h - 12, 0.01)), `{x0},{y0}-{x1},{y1}`)
	end
	local f = Rules.fit(box, 0, 600, 290, 6)
	local nx, ny = Rules.toMap(f, 1800, -150)
	local sx, sy = Rules.toMap(f, 1800, 150)
	local ex, ey = Rules.toMap(f, 2000, 0)
	local wx, wy = Rules.toMap(f, 1600, 0)
	check("… north up, east right (the plots at the top, the PAINT shop right of the PLAY circle)", ny < sy and ex > wx and near(nx, sx) and near(ey, wy))
	check("… a ▲'s heading: north 0°, east 90°, south 180°, west -90°", near(Rules.heading(f, 0, -1), 0, 1e-6) and near(Rules.heading(f, 1, 0), 90, 1e-6)
		and near(math.abs(Rules.heading(f, 0, 1)), 180, 1e-6) and near(Rules.heading(f, -1, 0), -90, 1e-6))
	local plan = Rules.decode(Rules.encode(HouseLayout.plan(9, "house"), { x = 0, y = 0, z = 0, yaw = 0 })) :: Rules.Plan
	local yard = Rules.yard("lone_house") :: Rules.Yard
	local hb = Rules.houseBox(plan, yard)
	local hf = Rules.fit(hb, 180, 600, 290, 10)
	local _, doorY = Rules.toMap(hf, 0, 0)
	local _, backY = Rules.toMap(hf, 0, plan.box.z1)
	local _, truckY = Rules.toMap(hf, yard.truck.x, yard.truck.z)
	local lx = Rules.toMap(hf, plan.box.x0, 10)
	local rx = Rules.toMap(hf, plan.box.x1, 10)
	check("a house: its front door at the bottom, its back up, the truck under the door", doorY > backY and truckY > doorY, `{doorY} {backY} {truckY}`)
	check("… seen from above, never a mirror image (the plan's +X is on the left when +Z is up)", lx > rx)
	check("… a ▲ walking into the house points up", near(Rules.heading(hf, 0, 1), 0, 1e-6))
	local x0, y0, x1, y1 = Rules.rectOn(hf, hb.x0, hb.z0, hb.x1, hb.z1)
	check("… the plan and its yard fitted inside the map", x0 >= 10 - 1e-6 and y0 >= 10 - 1e-6 and x1 <= 590 + 1e-6 and y1 <= 280 + 1e-6, `{x0},{y0}-{x1},{y1}`)
	local follow = Rules.follow(hf, 5, 12, 140, 140)
	local mx, my = Rules.toMap(follow, 5, 12)
	check("the minimap follows you: you in its middle, at the same scale", near(mx, 70, 1e-6) and near(my, 70, 1e-6) and follow.scale == hf.scale and follow.rot == 180)
end

-- ── The fog ──────────────────────────────────────────────────────────────────

do
	local See = C.Fog.See
	check("a piece is seen within Fog.See studs with nothing between, not farther, not through a wall", Rules.sees(See - 1, true) and Rules.sees(See, true) and not Rules.sees(See + 0.5, true)
		and not Rules.sees(5, false) and not Rules.sees(0 / 0, true))
	check("… shown once seen until carried out (in the truck, home, lost)", Rules.shown(true, "home") and Rules.shown(true, "carried") and Rules.shown(true, "ground") and Rules.shown(true, nil)
		and not Rules.shown(true, "truck") and not Rules.shown(true, "delivered") and not Rules.shown(true, "lost") and not Rules.shown(false, "home"))
	check("… out: the truck, home, lost", Rules.out("truck") and Rules.out("delivered") and Rules.out("lost") and not Rules.out("home") and not Rules.out(nil))
	check("an uncarried piece of Epic and up pulses (where the house holds it or on the ground), not in hands, not Rare", Rules.pulses("epic", "home") and Rules.pulses("legendary", "ground")
		and Rules.pulses("legendary", nil) and not Rules.pulses("legendary", "carried") and not Rules.pulses("rare", "home") and not Rules.pulses("common", nil) and not Rules.pulses("epic", "truck"))
	check("… the tiers' ranks (unknown: 1)", Rules.rank("legendary") == 5 and Rules.rank("epic") == 4 and Rules.rank("common") == 1 and Rules.rank("nope") == 1 and Rules.rank(nil) == 1)
end

-- ── Words ────────────────────────────────────────────────────────────────────

do
	-- 10.4 the OPEN LOBBIES rows (PartyRules' entries: the PLAY circle's attribute)
	local top, bottom, tone = Rules.lobbyLine({ host = "Ann", house = "old_mill", difficulty = "normal", n = 2, max = 4, friends = false, state = "open" })
	check("an open lobby: ANN · THE OLD MILL over NORMAL · 2/4 (open)", top == "ANN · THE OLD MILL" and bottom == "NORMAL · 2/4" and tone == "open", `{top} / {bottom}`)
	top, bottom, tone = Rules.lobbyLine({ host = "Bob", house = "pond_cabin", difficulty = "hard", n = 4, max = 4, friends = true, state = "full" })
	check("… full, friends only: HARD · 4/4 · FRIENDS ONLY · FULL (full)", top == "BOB · THE POND CABIN" and bottom == "HARD · 4/4 · FRIENDS ONLY · FULL" and tone == "full", bottom)
	top, bottom, tone = Rules.lobbyLine({ host = "Cid", house = "lone_house", difficulty = "insane", n = 3, max = 4, friends = false, state = "starting" })
	check("… counting down: STARTING · INSANE · 3/4 (starting)", bottom == "STARTING · INSANE · 3/4" and tone == "starting", bottom)
	top, bottom, tone = Rules.lobbyLine({ host = "Dee", house = "forest_lodge", difficulty = "nightmare", n = 2, max = 4, friends = false, state = "run", who = "Dee, Eve" })
	check("a run: THE FOREST LODGE over IN A RUN · NIGHTMARE · Dee, Eve (run)", top == "THE FOREST LODGE" and bottom == "IN A RUN · NIGHTMARE · Dee, Eve" and tone == "run", bottom)
	top, bottom = Rules.lobbyLine({ host = "Eve", house = "nowhere", difficulty = "odd", state = "open" })
	check("… junk: an unknown house as it is, an unknown difficulty the default's, 0/4", top == "EVE · NOWHERE" and bottom == "NORMAL · 0/4", bottom)
	check("… not a table: nothing", Rules.lobbyLine(nil) == "")
	local line
	line, tone = Rules.playLine({})
	check("the PLAY circle's line: STEP IN (no lobby)", line == "STEP IN" and tone == "free")
	line, tone = Rules.playLine({ { state = "open" }, { state = "full" }, { state = "run" } })
	check("… 2 OPEN LOBBIES (a run is no lobby)", line == "2 OPEN LOBBIES" and tone == "open", line)
	check("… 1 OPEN LOBBY", Rules.playLine({ { state = "open" } }) == "1 OPEN LOBBY")
	line, tone = Rules.playLine({ { state = "open" }, { state = "starting" } })
	check("… one counting down: STARTING", line == "STARTING" and tone == "starting")
	check("names: the first few, +n for the rest", Rules.names({ "A", "B", "C", "D", "E" }, 3) == "A, B, C +2" and Rules.names({ "A" }, 3) == "A" and Rules.names({}, 3) == "")
	check("the clock: m:ss", Rules.clock(463) == "7:43" and Rules.clock(59.6) == "1:00" and Rules.clock(-5) == "0:00")
end

-- ── Layout ───────────────────────────────────────────────────────────────────

do
	local bad: { string } = {}
	for _, s in { { 844, 354, true }, { 667, 339, true }, { 1280, 764, false }, { 1920, 1044, false } } do
		local W, H, touch = s[1], s[2], s[3]
		local S = math.clamp(math.min(W / 1150, H / 680), 0.55, 1.1)
		local L = Rules.window(W, H, S, touch)
		local label = `{W} × {H}`
		if L.x < 0 or L.y < 0 or L.x + L.w > W or L.y + L.h > H then
			table.insert(bad, `{label}: the window off the screen`)
		end
		if L.w > C.Window.Width * L.u + 1 or L.h > C.Window.Height * L.u + 1 then
			table.insert(bad, `{label}: the window too big`)
		end
		local m = L.map
		if m.w < 200 or m.h < 200 or m.x + m.w + (if L.side > 0 then L.side + L.pad else 0) > L.w - L.pad + 1 or m.y + m.h > L.h then
			table.insert(bad, `{label}: the map's area {m.w} × {m.h}`)
		end
		if L.side <= 0 then
			table.insert(bad, `{label}: no side column (it has the room)`)
		end
		if Rules.textSize(C.Text.Small, L.u) < C.Text.Least then
			table.insert(bad, `{label}: small words`)
		end
		-- the lobby and a big house fitted in its map: a phone's lobby still readable (at least 0.6 px a stud)
		local f = Rules.fit(Rules.lobbyBox(), 0, m.w, m.h, 6)
		if f.scale < 0.6 then
			table.insert(bad, `{label}: the lobby at {f.scale} px a stud`)
		end
	end
	check("the window on phones (844 × 390, 667 × 375) and computers (1280 × 800, 1920 × 1080): on the screen, its map's area and side column, readable words, the lobby big enough", #bad == 0, bad[1])
	check("a narrow screen: no side column", Rules.window(420, 700, 0.55, true).side == 0)
	check("text sizes never under Text.Least", Rules.textSize(8, 0.5) == C.Text.Least and Rules.textSize(20, 1) == 20)
end

do
	-- the minimap's square: clear of what a phone in a run has (the touch buttons, the thumbstick, the jump button, the
	-- 📋 button's first place, the move's panel and Danny's line), a computer's bottom right corner
	local bad: { string } = {}
	for _, s in { { 844, 354 }, { 667, 339 } } do
		local W, H = s[1], s[2]
		local S = math.clamp(math.min(W / 1150, H / 680), 0.55, 1.1)
		local c = TouchLayout.cluster(W, H, S)
		local avoid = {}
		for _, b in TouchLayout.buttons(c) do
			table.insert(avoid, b)
		end
		table.insert(avoid, c.thumb)
		table.insert(avoid, c.jump)
		local clip = Config.MoveHelper.Clipboard
		table.insert(avoid, MoveLayout.tapSpots(W, H, S, math.max(clip.ButtonMin, 44, clip.Button * S))[1])
		local panel = MoveLayout.panel(W, S)
		table.insert(avoid, panel)
		table.insert(avoid, MoveLayout.strip(panel, S, 44))
		local box = Rules.mini(W, H, S, true, avoid)
		if not box then
			table.insert(bad, `{W} × {H}: none`)
			continue
		end
		local size = box.x1 - box.x0
		if box.x1 ~= W - C.Mini.Margin or box.y0 ~= C.Mini.Top or size < C.Mini.Least or size > C.Mini.TouchSize or box.y1 - box.y0 ~= size then
			table.insert(bad, `{W} × {H}: {box.x0},{box.y0}-{box.x1},{box.y1}`)
		end
		for _, b in avoid do
			if TouchLayout.overlap(box :: any, b) then
				table.insert(bad, `{W} × {H}: on {b.x0},{b.y0}-{b.x1},{b.y1}`)
			end
		end
	end
	check("a touch screen's minimap: its top right corner, square, clear of the touch controls, the 📋 button's place, the move's panel and Danny's line", #bad == 0, bad[1])
	local box = Rules.mini(1280, 764, 1.1, false, {}) :: Rules.MapBox
	check("… a computer's: its bottom right corner at the HUD's scale", box ~= nil and box.x1 == 1280 - C.Mini.Margin and box.y1 == 764 - C.Mini.Margin
		and near(box.x1 - box.x0, math.floor(C.Mini.Size * 1.1 + 0.5), 0.01))
	local shrunk = Rules.mini(1280, 764, 1.1, false, { { x0 = 0, y0 = 0, x1 = 1280, y1 = 764 - 16 - C.Mini.Least - 1 } })
	check("… shrunk (by Mini.Step) to keep clear of what is there", shrunk ~= nil and shrunk.x1 - shrunk.x0 < C.Mini.Size and shrunk.x1 - shrunk.x0 >= C.Mini.Least)
	check("… no room even at Mini.Least: none", Rules.mini(1280, 764, 1.1, false, { { x0 = 0, y0 = 0, x1 = 1280, y1 = 764 } }) == nil)
end

-- ── The houses' kinds, the gamepad ───────────────────────────────────────────

do
	local seen: { [string]: string } = {}
	local clash: string? = nil
	for _, h in SandboxMap.Houses do
		local own = (Config.Moving.Sandbox.Houses :: any)[h.id]
		local kind = if own then own.Kind else h.kind
		if seen[kind] then
			clash = `{h.id} and {seen[kind]}: {kind}`
		end
		seen[kind] = h.id
	end
	check("the six houses' plan kinds all different (a run's inside is found by its kind)", clash == nil, clash)
	check("SandboxPad's map: M, the gamepad's L2, a tap on 🗺 MAP", SandboxPad.keyWord("map", "keys") == "M" and SandboxPad.keyWord("map", "pad") == "L2"
		and SandboxPad.howTo("map", "touch") == "Tap 🗺 MAP" and SandboxPad.howTo("map", "pad") == "Press L2" and C.Key == "M")
	local A = SandboxPad.Actions
	check("… L2 on foot only: the D-pad stays the chips', nothing else of the sandbox's on foot on L2", (function()
		for id, action in A do
			if table.find(action.pad, "ButtonL2") and id ~= "map" and id ~= "drive" then
				return false
			end
		end
		return string.sub(A.map.pad[1], 1, 4) ~= "DPad"
	end)())
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
