--!strict
-- 10.x THE MAP (the owner: "I need you to add a way to look at the map"; Config.SandboxMapUi): the sandbox's big map (M)
-- and its corner minimap, the pure part (no Roblox: tests/sandboxmaprules_test.luau). client/SandboxMapData.luau reads
-- the world with it, client/SandboxMapDraw.luau draws with it, client/SandboxMapUi.luau (the big map) and
-- client/SandboxMiniMap.luau (the minimap) lay themselves out with it; server/HouseInterior.luau publishes a run's
-- floor plan with it (the interior model's attribute MapPlan); 10.4 server/Parties.luau publishes the PLAY circle's
-- lobbies and the runs (the PLAY circle model's attribute Config.Runs.Party.Attribute: shared/PartyRules.luau's entries).
--
--   The plan's code (one short string on the interior model, written once per interior):
--     SandboxMapRules.encode(plan, origin) -> string    a shared/HouseLayout.luau plan (its box, rooms, doorways, the
--                                                      solid fixtures standing on the floor, windows) and its origin
--                                                      ({ x, y, z, yaw }: the interior's pivot; yaw in degrees, the
--                                                      way its -Z looks, as SandboxMap's spots), numbers to a tenth
--     SandboxMapRules.decode(text) -> Plan?             the plan back (nil: no code, another version or broken)
--   Where things are (studs; a plan's own frame: the floor's top at the front door's middle, +Z into the house):
--     SandboxMapRules.toLocal(plan, x, z) -> (lx, lz)   a world point in the plan's frame (its origin's yaw undone)
--     SandboxMapRules.inside(plan, lx, lz, y) -> bool   on its floor (its box, Inside studs of slack; y a world height)
--     SandboxMapRules.yard(house) -> Yard?              a house's front yard in its plan's frame (SandboxMap.Houses,
--                                                      the id): out of its front door is -Z, the truck's curb, the
--                                                      yard's asphalt (SandboxMap.Roads: its street), the strip drawn
--                                                      (Yard.Depth past the truck's far end, the plan's width at least)
--     SandboxMapRules.toYard(yard, x, z) -> (lx, lz)    a world point of the yard in the plan's frame
--     SandboxMapRules.inYard(yard, lx, lz, slack?) -> bool   in the strip (grown by `slack`)
--     SandboxMapRules.clampYard(yard, lx, lz) -> (lx, lz)    pinned to the strip's edge
--     SandboxMapRules.turn(x, z, degrees) -> (x, z)    a direction turned as toLocal (yaw: the plan's origin's) and
--                                                      toYard (yaw: the house's) turn a point: a look on the map
--     SandboxMapRules.houseBox(plan, yard?) -> Box      what the run's map shows: the plan and the yard's strip
--     SandboxMapRules.lobbyBox() -> Box                 the lobby's island (10.8: SandboxMap.Islands' first: its bounds
--                                                      and the rim of grass round them to its edge)
--   Drawing (a Frame maps content studs to px: its centre cx, cz; rot in degrees, 0 north up, 180 the house's front
--   door at the bottom; scale px a stud; ox, oy the px the centre lands on):
--     SandboxMapRules.fit(box, rot, w, h, pad) -> Frame        the box as big as fits in w × h px, pad px round it
--     SandboxMapRules.follow(frame, x, z, w, h) -> Frame       the same frame moved so (x, z) is in the middle of w × h
--     SandboxMapRules.toMap(frame, x, z) -> (px, py)
--     SandboxMapRules.rectOn(frame, x0, z0, x1, z1) -> (px0, py0, px1, py1)   a box's corners on the map (sorted)
--     SandboxMapRules.heading(frame, lookX, lookZ) -> degrees  a ▲'s Rotation for a look (0: up on the map)
--   The fog (a run's loot: Config.SandboxMapUi.Fog):
--     SandboxMapRules.sees(distance, clear) -> bool    a piece seen now: within Fog.See studs and nothing in between
--     SandboxMapRules.out(state) -> bool               carried out: in the truck, home or lost (the Moving state's)
--     SandboxMapRules.shown(seen, state) -> bool       on the map: seen once and not carried out
--     SandboxMapRules.pulses(rarity, state) -> bool    an uncarried piece of Epic and up (on the floor, not in hands)
--     SandboxMapRules.rank(rarity) -> n                its tier's rank (Config.Collection; unknown: 1)
--   Words:
--     SandboxMapRules.lobbyLine(entry) -> (top, bottom, tone)   10.4: a row of the OPEN LOBBIES list (a PartyRules
--                                                      entry): "ANN · THE OLD MILL" over "NORMAL · 2/4 · FRIENDS ONLY"
--                                                      (tone "open"; full: "… · FULL", "full"), "STARTING · HARD · 3/4"
--                                                      ("starting"); a run: "THE POND CABIN" over "IN A RUN · HARD · Bob,
--                                                      Cid" ("run")
--     SandboxMapRules.playLine(entries) -> (line, tone)   10.4: the PLAY circle's line on the map: "STARTING"
--                                                      ("starting"), "2 OPEN LOBBIES" ("open"), "STEP IN" ("free")
--     SandboxMapRules.roundLine(round, now) -> (top, bottom, tone)   10.6 both in PLAY: the side column's QUICK ROUND row
--                                                      (`round`: client/SandboxMapData.luau's, the PLAY circle's Round…
--                                                      attributes; `now` the server's time): "⚡ THE OLD MILL" over "NEXT ·
--                                                      HARD · 0:42 · 3 QUEUED" ("starting"), the round on ("ON · 3:12
--                                                      LEFT · 5 MOVERS", "run"), over ("full"), nobody queued ("⚡ QUICK
--                                                      ROUND" over "NOBODY QUEUED · STEP INTO PLAY", "free"); nil: none
--                                                      ("off")
--     SandboxMapRules.names(list, most) -> string      "Ann, Bob +2"
--     SandboxMapRules.clock(seconds) -> "m:ss"
--   Layout (px under Roblox's top bar):
--     SandboxMapRules.window(W, H, S, touch) -> Window  the big map's window: its box, its text scale u, its header,
--                                                      its side column (0: none) and the map's area
--     SandboxMapRules.textSize(base, u) -> px          a text's size at u (never under Text.Least)
--     SandboxMapRules.mini(W, H, S, touch, avoid) -> Box?   the minimap's square: a touch screen's top right, a
--                                                      computer's bottom right, clear of `avoid` (shrunk to Mini.Least
--                                                      at most; nil: no room)

local Config = require(script.Parent.Config)
local SandboxMap = require(script.Parent.SandboxMap)

local SandboxMapRules = {}

local C = Config.SandboxMapUi
local VERSION = "1"

export type Box = { x0: number, z0: number, x1: number, z1: number }
export type Origin = { x: number, y: number, z: number, yaw: number }
export type Room = { id: string, kind: string, x0: number, z0: number, x1: number, z1: number }
export type Door = { x: number, z: number, w: number, axis: string, out: boolean, front: boolean }
export type Fixture = { kind: string, x: number, z: number, sx: number, sz: number }
export type Window = { x: number, z: number, w: number, axis: string }
export type Plan = {
	kind: string,
	origin: Origin,
	box: Box,
	wall: number,
	height: number,
	rooms: { Room },
	doors: { Door },
	fixtures: { Fixture },
	windows: { Window },
}
export type Yard = {
	house: string,
	yaw: number,
	door: { x: number, z: number },
	road: Box?, -- (the yard's asphalt in the plan's frame, cut to the strip)
	truck: { x: number, z: number, yaw: number }, -- (the curb: the truck's pivot; yaw its nose's way in the plan's frame)
	strip: Box,
}
export type Frame = { cx: number, cz: number, rot: number, scale: number, ox: number, oy: number }
export type MapBox = { x0: number, y0: number, x1: number, y1: number }
export type Layout = {
	x: number,
	y: number,
	w: number,
	h: number,
	u: number,
	header: number,
	side: number,
	pad: number,
	map: { x: number, y: number, w: number, h: number },
}

-- ── Small things ─────────────────────────────────────────────────────────────

local function num(n: number): string
	local text = string.format("%.1f", n)
	text = string.gsub(text, "%.0$", "")
	if text == "-0" then
		return "0"
	end
	return text
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- a 2D turn by `degrees` (x, z): x cos − z sin, x sin + z cos
local function turn(x: number, z: number, degrees: number): (number, number)
	local r = math.rad(degrees)
	local c, s = math.cos(r), math.sin(r)
	-- (whole quarter turns exactly: no -0.0000001 for a 0)
	if degrees % 90 == 0 then
		c, s = math.round(c), math.round(s)
	end
	return x * c - z * s, x * s + z * c
end

SandboxMapRules.turn = turn

-- the word with nothing the code splits on
local function word(text: any): string
	local s = if type(text) == "string" then text else tostring(text)
	return (string.gsub(s, "[|;:,]", "_"))
end

-- ── The plan's code ──────────────────────────────────────────────────────────

-- `plan` is a shared/HouseLayout.luau Plan (its Vector3s and CFrames read by field: .X, .Z, .Position).
function SandboxMapRules.encode(plan: any, origin: Origin): string
	local wall = tonumber(plan.wall) or 1
	local height = 0
	local rooms: { string } = {}
	for _, r in plan.rooms do
		height = math.max(height, r.max.Y)
		table.insert(rooms, table.concat({ word(r.id), word(r.kind), num(r.min.X), num(r.min.Z), num(r.max.X), num(r.max.Z) }, ":"))
	end
	local doors: { string } = {}
	for _, d in plan.doors do
		local out = false
		for _, room in d.rooms do
			out = out or room == "outside"
		end
		local flags = (if d.front then "f" else "") .. (if out then "o" else "")
		table.insert(doors, table.concat({ num(d.at.X), num(d.at.Z), num(d.width), if d.axis == "Z" then "Z" else "X", flags }, ":"))
	end
	local fixtures: { string } = {}
	for _, f in plan.fixtures do
		local at = f.at.Position
		-- (what stands on the floor and in the way: the counters, the stoves, the tub, the millstones; not the rugs, the
		-- pictures or what hangs from the ceiling)
		if f.solid and at.Y < 1 then
			local quarter = math.floor(((tonumber(f.turn) or 0) % 360) / 90 + 0.5) % 2
			local sx, sz = f.size.X, f.size.Z
			if quarter == 1 then
				sx, sz = sz, sx
			end
			table.insert(fixtures, table.concat({ word(f.kind), num(at.X), num(at.Z), num(sx), num(sz) }, ":"))
		end
	end
	local windows: { string } = {}
	for _, w in plan.windows do
		local n = w.normal
		local alongZ = math.abs(n.X) > math.abs(n.Z)
		-- (on the wall's middle line: the window's at is on its inside face, the normal into the room)
		local x, z = w.at.X - n.X * wall / 2, w.at.Z - n.Z * wall / 2
		table.insert(windows, table.concat({ num(x), num(z), num(w.width), if alongZ then "Z" else "X" }, ":"))
	end
	return table.concat({
		VERSION,
		word(plan.kind),
		table.concat({ num(origin.x), num(origin.y), num(origin.z), num(origin.yaw) }, ","),
		table.concat({ num(plan.min.X), num(plan.min.Z), num(plan.max.X), num(plan.max.Z), num(wall), num(height) }, ","),
		table.concat(rooms, ";"),
		table.concat(doors, ";"),
		table.concat(fixtures, ";"),
		table.concat(windows, ";"),
	}, "|")
end

local function numbers(text: string, count: number): { number }?
	local out: { number } = {}
	for _, part in string.split(text, ",") do
		local n = tonumber(part)
		if not finite(n) then
			return nil
		end
		table.insert(out, n :: number)
	end
	return if #out == count then out else nil
end

-- Each entry of a list ("a:b:c;d:e:f"), its fields split; nil when one has fewer than `least` fields.
local function entries(text: string, least: number): { { string } }?
	local out: { { string } } = {}
	if text == "" then
		return out
	end
	for _, entry in string.split(text, ";") do
		local fields = string.split(entry, ":")
		if #fields < least then
			return nil
		end
		table.insert(out, fields)
	end
	return out
end

local function decodeNow(text: string): Plan?
	local parts = string.split(text, "|")
	if #parts ~= 8 or parts[1] ~= VERSION then
		return nil
	end
	local o = numbers(parts[3], 4)
	local b = numbers(parts[4], 6)
	local roomList, doorList, fixtureList, windowList = entries(parts[5], 6), entries(parts[6], 5), entries(parts[7], 5), entries(parts[8], 4)
	if not o or not b or not roomList or not doorList or not fixtureList or not windowList then
		return nil
	end
	local plan: Plan = {
		kind = parts[2],
		origin = { x = o[1], y = o[2], z = o[3], yaw = o[4] },
		box = { x0 = b[1], z0 = b[2], x1 = b[3], z1 = b[4] },
		wall = b[5],
		height = b[6],
		rooms = {},
		doors = {},
		fixtures = {},
		windows = {},
	}
	for _, f in roomList do
		local x0, z0, x1, z1 = tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6])
		if not (finite(x0) and finite(z0) and finite(x1) and finite(z1)) then
			return nil
		end
		table.insert(plan.rooms, { id = f[1], kind = f[2], x0 = x0 :: number, z0 = z0 :: number, x1 = x1 :: number, z1 = z1 :: number })
	end
	for _, f in doorList do
		local x, z, w = tonumber(f[1]), tonumber(f[2]), tonumber(f[3])
		if not (finite(x) and finite(z) and finite(w)) then
			return nil
		end
		local flags = f[5] or ""
		table.insert(plan.doors, { x = x :: number, z = z :: number, w = w :: number, axis = if f[4] == "Z" then "Z" else "X",
			front = string.find(flags, "f", 1, true) ~= nil, out = string.find(flags, "o", 1, true) ~= nil })
	end
	for _, f in fixtureList do
		local x, z, sx, sz = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
		if not (finite(x) and finite(z) and finite(sx) and finite(sz)) then
			return nil
		end
		table.insert(plan.fixtures, { kind = f[1], x = x :: number, z = z :: number, sx = sx :: number, sz = sz :: number })
	end
	for _, f in windowList do
		local x, z, w = tonumber(f[1]), tonumber(f[2]), tonumber(f[3])
		if not (finite(x) and finite(z) and finite(w)) then
			return nil
		end
		table.insert(plan.windows, { x = x :: number, z = z :: number, w = w :: number, axis = if f[4] == "Z" then "Z" else "X" })
	end
	return plan
end

function SandboxMapRules.decode(text: any): Plan?
	if type(text) ~= "string" or text == "" then
		return nil
	end
	local ok, plan = pcall(decodeNow, text)
	return if ok then plan else nil
end

-- ── Where things are ─────────────────────────────────────────────────────────

-- (the origin's CFrame turns a local point by its yaw: world = origin + turn(local, −yaw) in this module's turn; so the
-- way back is turn(world − origin, yaw))
function SandboxMapRules.toLocal(plan: Plan, x: number, z: number): (number, number)
	local o = plan.origin
	return turn(x - o.x, z - o.z, o.yaw)
end

function SandboxMapRules.inside(plan: Plan, lx: number, lz: number, y: number?): boolean
	local slack = C.Inside
	local b = plan.box
	if lx < b.x0 - slack or lx > b.x1 + slack or lz < b.z0 - slack or lz > b.z1 + slack then
		return false
	end
	if y ~= nil then
		local up = y - plan.origin.y
		return up >= -C.Below and up <= plan.height + C.Above
	end
	return true
end

-- A house's look (out of its front door) turned by its own yaw is the plan's −Z (yaw 0 looks north, −Z: as it is; 180
-- south: a half turn; 90 west: (−1, 0) → (0, −1)): its yard as its inside's plan would have it, the door at 0, 0.
function SandboxMapRules.toYard(yard: Yard, x: number, z: number): (number, number)
	return turn(x - yard.door.x, z - yard.door.z, yard.yaw)
end

function SandboxMapRules.yard(houseId: any): Yard?
	local house = SandboxMap.house(houseId)
	if not house then
		return nil
	end
	local Y = C.Yard
	local door = { x = house.door.x, z = house.door.z }
	local probe: Yard = { house = house.id, yaw = house.yaw, door = door, road = nil, truck = { x = 0, z = 0, yaw = 0 }, strip = { x0 = 0, z0 = 0, x1 = 0, z1 = 0 } }
	local tx, tz = SandboxMapRules.toYard(probe, house.curb.x, house.curb.z)
	-- (the truck's nose looks away from the door: the plan's −Z; its yaw on the map's frame as a spot's: 0 looks −Z)
	probe.truck = { x = tx, z = tz, yaw = 0 }
	local far = tz - Y.Truck / 2 - Y.Depth
	probe.strip = { x0 = -Y.Half, z0 = far, x1 = Y.Half, z1 = 0 }
	for _, road in SandboxMap.Roads do
		if road.name == house.street and road.yard then
			local ax, az = SandboxMapRules.toYard(probe, road.x0, road.z0)
			local bx, bz = SandboxMapRules.toYard(probe, road.x1, road.z1)
			local box = { x0 = math.min(ax, bx), z0 = math.max(math.min(az, bz), far), x1 = math.max(ax, bx), z1 = math.min(math.max(az, bz), 0) }
			if box.z1 > box.z0 then
				probe.road = box
			end
		end
	end
	return probe
end

function SandboxMapRules.inYard(yard: Yard, lx: number, lz: number, slack: number?): boolean
	local s = slack or 0
	local b = yard.strip
	return lx >= b.x0 - s and lx <= b.x1 + s and lz >= b.z0 - s and lz <= b.z1 + s
end

function SandboxMapRules.clampYard(yard: Yard, lx: number, lz: number): (number, number)
	local b = yard.strip
	return math.clamp(lx, b.x0, b.x1), math.clamp(lz, b.z0, b.z1)
end

-- The yard's strip as wide as the plan (at least Yard.Half each side of the door).
function SandboxMapRules.houseBox(plan: Plan, yard: Yard?): Box
	local b = plan.box
	local box = { x0 = b.x0, z0 = b.z0, x1 = b.x1, z1 = b.z1 }
	if yard then
		box.x0 = math.min(box.x0, yard.strip.x0)
		box.x1 = math.max(box.x1, yard.strip.x1)
		box.z0 = math.min(box.z0, yard.strip.z0)
		yard.strip.x0, yard.strip.x1 = box.x0, box.x1
	end
	return box
end

function SandboxMapRules.lobbyBox(): Box
	local island = SandboxMap.Islands[1]
	local b = if island then island.rect else SandboxMap.Lobby.bounds
	return { x0 = b.x0, z0 = b.z0, x1 = b.x1, z1 = b.z1 }
end

-- ── Drawing ──────────────────────────────────────────────────────────────────

function SandboxMapRules.fit(box: Box, rot: number, w: number, h: number, pad: number): Frame
	local bw, bh = math.max(1, box.x1 - box.x0), math.max(1, box.z1 - box.z0)
	if rot % 180 ~= 0 then
		bw, bh = bh, bw
	end
	local scale = math.max(0.01, math.min((w - 2 * pad) / bw, (h - 2 * pad) / bh))
	return { cx = (box.x0 + box.x1) / 2, cz = (box.z0 + box.z1) / 2, rot = rot, scale = scale, ox = w / 2, oy = h / 2 }
end

function SandboxMapRules.follow(frame: Frame, x: number, z: number, w: number, h: number): Frame
	return { cx = x, cz = z, rot = frame.rot, scale = frame.scale, ox = w / 2, oy = h / 2 }
end

-- (rot turns the content clockwise on the screen: 180 puts +Z up)
function SandboxMapRules.toMap(frame: Frame, x: number, z: number): (number, number)
	local u, v = turn(x - frame.cx, z - frame.cz, frame.rot)
	return frame.ox + u * frame.scale, frame.oy + v * frame.scale
end

function SandboxMapRules.rectOn(frame: Frame, x0: number, z0: number, x1: number, z1: number): (number, number, number, number)
	local ax, ay = SandboxMapRules.toMap(frame, x0, z0)
	local bx, by = SandboxMapRules.toMap(frame, x1, z1)
	return math.min(ax, bx), math.min(ay, by), math.max(ax, bx), math.max(ay, by)
end

-- A ▲ points up at Rotation 0; Roblox turns a GuiObject clockwise.
function SandboxMapRules.heading(frame: Frame, lookX: number, lookZ: number): number
	local u, v = turn(lookX, lookZ, frame.rot)
	if u == 0 and v == 0 then
		return 0
	end
	return math.deg(math.atan2(u, -v))
end

-- ── The fog ──────────────────────────────────────────────────────────────────

local OUT: { [string]: boolean } = { truck = true, delivered = true, lost = true }

function SandboxMapRules.sees(distance: number, clear: boolean): boolean
	return clear and finite(distance) and distance <= C.Fog.See
end

function SandboxMapRules.out(state: any): boolean
	return type(state) == "string" and OUT[state] == true
end

function SandboxMapRules.shown(seen: boolean, state: any): boolean
	return seen and not SandboxMapRules.out(state)
end

function SandboxMapRules.rank(rarity: any): number
	local tier = if type(rarity) == "string" then Config.Collection.Tiers[rarity] else nil
	return if tier then tier.rank else 1
end

function SandboxMapRules.pulses(rarity: any, state: any): boolean
	local loose = state == nil or state == "home" or state == "ground"
	return loose and SandboxMapRules.rank(rarity) >= SandboxMapRules.rank(C.Pulse.From)
end

-- ── Words ────────────────────────────────────────────────────────────────────

function SandboxMapRules.names(list: { string }, most: number): string
	local shown: { string } = {}
	for n, name in list do
		if n > most then
			break
		end
		table.insert(shown, name)
	end
	local text = table.concat(shown, ", ")
	if #list > most then
		text ..= ` +{#list - most}`
	end
	return text
end

function SandboxMapRules.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

-- 10.4: a difficulty's name in capitals (an unknown one: the default's)
local function difficultyName(id: any): string
	for _, def in Config.Runs.Difficulties do
		if def.id == id then
			return string.upper(def.name)
		end
	end
	for _, def in Config.Runs.Difficulties do
		if def.id == Config.Runs.Default then
			return string.upper(def.name)
		end
	end
	return "NORMAL"
end

function SandboxMapRules.lobbyLine(entry: any): (string, string, string)
	if type(entry) ~= "table" then
		return "", "", "open"
	end
	local house = SandboxMap.house(entry.house)
	local place = string.upper(if house then house.name else tostring(entry.house or "?"))
	local difficulty = difficultyName(entry.difficulty)
	if entry.state == "run" then
		local who = if type(entry.who) == "string" and entry.who ~= "" then ` · {entry.who}` else ""
		return place, `IN A RUN · {difficulty}{who}`, "run"
	end
	local n = tonumber(entry.n) or 0
	local most = tonumber(entry.max) or Config.Runs.MaxParty
	local top = `{string.upper(tostring(entry.host or "?"))} · {place}`
	if entry.state == "starting" then
		return top, `STARTING · {difficulty} · {n}/{most}`, "starting"
	end
	local full = entry.state == "full"
	return top, `{difficulty} · {n}/{most}{if entry.friends == true then " · FRIENDS ONLY" else ""}{if full then " · FULL" else ""}`, if full then "full" else "open"
end

function SandboxMapRules.roundLine(round: any, now: number): (string, string, string)
	if type(round) ~= "table" or type(round.phase) ~= "string" or round.phase == "off" then
		return "", "", "off"
	end
	local house = SandboxMap.house(round.house)
	local top = if house then `⚡ {string.upper(house.name)}` else "⚡ QUICK ROUND"
	local queued = `{math.max(0, math.floor(tonumber(round.queued) or 0))} QUEUED`
	local left = if type(round.endsAt) == "number" then SandboxMapRules.clock(round.endsAt - now) else "–:––"
	if round.phase == "wait" and house then
		return top, `NEXT · {difficultyName(round.difficulty)} · {left} · {queued}`, "starting"
	elseif round.phase == "wait" then
		return top, `WAITING FOR A FREE HOUSE · {queued}`, "starting"
	elseif round.phase == "play" then
		return top, `ON · {left} LEFT · {math.max(0, math.floor(tonumber(round.movers) or 0))} MOVERS`, "run"
	elseif round.phase == "over" then
		return top, `OVER · THE NEXT ONE IS COMING`, "full"
	end
	return "⚡ QUICK ROUND", "NOBODY QUEUED · STEP INTO PLAY", "free"
end

function SandboxMapRules.playLine(entries: { any }): (string, string)
	local open, starting = 0, false
	for _, e in entries do
		if type(e) == "table" and e.state ~= "run" then
			open += 1
			starting = starting or e.state == "starting"
		end
	end
	if starting then
		return "STARTING", "starting"
	elseif open > 0 then
		return `{open} OPEN LOBB{if open == 1 then "Y" else "IES"}`, "open"
	end
	return "STEP IN", "free"
end

-- ── Layout ───────────────────────────────────────────────────────────────────

function SandboxMapRules.textSize(base: number, u: number): number
	return math.max(C.Text.Least, math.floor(base * u + 0.5))
end

function SandboxMapRules.window(W: number, H: number, S: number, touch: boolean): Layout
	local w = C.Window
	local u = if touch then w.TouchScale else math.clamp(S, w.LeastScale, 1.1)
	local margin = if touch then w.TouchMargin else w.Margin
	local width = math.floor(math.min(W - 2 * margin, w.Width * u))
	local height = math.floor(math.min(H - 2 * margin, w.Height * u))
	local header = math.floor(w.Header * u + 0.5)
	local pad = math.floor(w.Pad * u + 0.5)
	local side = math.floor((if touch then w.TouchSide else w.Side) * u + 0.5)
	-- (the side column only where the map keeps most of the window and stays wider than tall: a phone held sideways
	-- has the room, one held upright not)
	if width - side - 3 * pad < math.max(width * 0.45, height - header - pad) then
		side = 0
	end
	local mapW = width - 2 * pad - (if side > 0 then side + pad else 0)
	return {
		x = math.floor((W - width) / 2),
		y = math.floor((H - height) / 2),
		w = width,
		h = height,
		u = u,
		header = header,
		side = side,
		pad = pad,
		map = { x = pad, y = header, w = mapW, h = height - header - pad },
	}
end

local function overlap(a: MapBox, b: MapBox): boolean
	return math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 0 and math.min(a.y1, b.y1) - math.max(a.y0, b.y0) > 0
end

function SandboxMapRules.mini(W: number, H: number, S: number, touch: boolean, avoid: { MapBox }): MapBox?
	local m = C.Mini
	local most = if touch then m.TouchSize else math.floor(m.Size * math.clamp(S, 0.6, 1.1) + 0.5)
	local margin = m.Margin
	local size = most
	while size >= m.Least do
		local b: MapBox
		if touch then
			b = { x0 = W - margin - size, y0 = m.Top, x1 = W - margin, y1 = m.Top + size }
		else
			b = { x0 = W - margin - size, y0 = H - margin - size, x1 = W - margin, y1 = H - margin }
		end
		local clear = b.x0 >= 0 and b.y0 >= 0 and b.x1 <= W and b.y1 <= H
		if clear then
			for _, other in avoid do
				if overlap(b, other) then
					clear = false
					break
				end
			end
		end
		if clear then
			return b
		end
		size -= m.Step
	end
	return nil
end

return SandboxMapRules
