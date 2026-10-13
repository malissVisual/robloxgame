--!strict
-- 7.0, the moving rework's world (design/rework/NAVRH.md: the city is evacuated district by district, the army builds
-- the Wall round the safe zone, ZDC turns into ZDC Moving & Evacuation), as plain numbers: every set piece's parts in its
-- own frame and where each set stands (Config.MoveSites, Config.Moving). server/MoveSites.luau builds them (anchored,
-- CanTouch off; only the pieces marked solid collide and stop bullets), tests/movesites_test.luau checks them (the part
-- budget, nothing in the truck's lane, nothing on a house's path from its door to its kerb or on the people's walk line
-- round a block, the evacuation spots clear of the street props), tools/move-sites/check.py checks the built parts and
-- tools/move-sites/render.py draws them. Pure Luau.
--
-- A piece: name (unique in its set), size, at (its middle in the set's frame: +X right, +Y up from the walk, -Z forward,
-- the way the set faces), color (0 … 255), material (an Enum.Material name), yaw (degrees about its vertical axis, first),
-- rotation (degrees about X, Y, Z after that, as CFrame.Angles), shape (Block | Cylinder | Wedge; a cylinder's axis is its
-- X and its Y and Z are the same), solid (it collides and stops bullets: CanCollide and CanQuery; else neither), glow
-- (its colour at night: DayNight's lamp glass, Neon), light (a PointLight's range in it, on at night), transparency,
-- words (text on its faces: one SurfaceGui each; a line's size is its share of the face's height; back: a coloured
-- panel behind the lines, inset from the face's edges; lit: the text does not dim in the dark).
--
--   MoveSiteLooks.checkpoint()          the Wall's checkpoint round the moving drop-off (frame: the drop-off's middle on
--                                       the walk, -Z north into the depot's yard, +Z out to Bone St): the bay painted on
--                                       the yard, the gantry with the SAFE ZONE sign, the Wall's stubs and jersey
--                                       barriers, the booth, the raised barrier, the floodlights, sandbags, the army truck
--   MoveSiteLooks.board()               the Moving contracts kiosk (frame: its foot, -Z toward the yard); Moving hangs its
--                                       prompt on the piece named "Board" (the corkboard)
--   MoveSiteLooks.house(title, park)    a contract's house dressed for moving day (frame: its front door's foot, -Z out
--                                       to the street; park: studs from the door to the truck's kerb spot, Map.Home park)
--   MoveSiteLooks.banner()              the depot's ZDC MOVING & EVACUATION banner (frame: its middle, -Z to the yard)
--   MoveSiteLooks.spot(seed)            an evacuation spot on a kerb: a poster board and abandoned moving boxes (frame: on
--                                       the kerb, -Z out to the street)
--   MoveSiteLooks.checkpointPlace() / boardPlace() / bannerPlace() / doorPlace(home) / spotPlaces()   where they stand
--   MoveSiteLooks.all()                 every set with its place (the checks', the preview's)
--   MoveSiteLooks.box(place, piece)     a piece's axis-aligned box in the world: x0, x1, y0, y1, z0, z1
--   MoveSiteLooks.shadow(piece, baseY)  does it throw a shadow (shared/RenderBudget.luau's rule)?
--   MoveSiteLooks.pixels(w, h), textRange(h)   a face's SurfaceGui PixelsPerStud and MaxDistance

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local RenderBudget = require(script.Parent.RenderBudget)

local MoveSiteLooks = {}

export type Line = { text: string, color: { number }, size: number, font: string? }
export type Words = { face: string, lines: { Line }, back: { number }?, inset: number?, lit: boolean? }
export type Piece = {
	name: string,
	size: { number },
	at: { number },
	color: { number },
	material: string,
	yaw: number?,
	rotation: { number }?,
	shape: string?,
	solid: boolean?,
	glow: { number }?,
	light: number?,
	transparency: number?,
	words: { Words }?,
}
export type Place = { x: number, y: number, z: number, yaw: number, seed: number? }
export type Set = { id: string, place: Place, pieces: { Piece } }

MoveSiteLooks.Materials = {
	"SmoothPlastic", "Metal", "Concrete", "Fabric", "Wood", "WoodPlanks", "Glass", "Neon", "Rubber", "DiamondPlate",
} :: { string }
MoveSiteLooks.Shapes = { "Block", "Cylinder", "Wedge" } :: { string }
MoveSiteLooks.Faces = { "Front", "Back", "Left", "Right", "Top" } :: { string }

-- The palette: the movers' orange (the Moving Truck's), the army's olive and sand, the Wall's concrete.
local ORANGE = { 240, 132, 44 }
local INK = { 242, 242, 240 }
local CHARCOAL = { 28, 30, 34 }
local GREY = { 196, 199, 203 }
local CONCRETE = { 163, 160, 150 }
local JERSEY = { 182, 180, 172 }
local OLIVE = { 86, 98, 64 }
local OLIVE_DARK = { 54, 64, 42 }
local CANVAS = { 112, 116, 82 }
local SAND = { 176, 156, 112 }
local YELLOW = { 240, 196, 40 }
local SIGN_YELLOW = { 255, 214, 90 }
local BLACK = { 26, 27, 29 }
local RED = { 196, 48, 40 }
local WHITE = { 236, 236, 230 }
local STEEL = { 120, 126, 128 }
local DARK = { 40, 42, 44 }
local CARDBOARD = { 186, 142, 92 }
local TAPE = { 214, 192, 146 }
local CORK = { 178, 132, 84 }
local PAPER = { 238, 234, 222 }
local GLASS = { 60, 78, 88 }
local WOOD = { 96, 72, 50 }
local COOL = { 236, 242, 255 } -- a floodlight's glow
local WARM = { 255, 224, 168 } -- a lamp's
local AMBER = { 255, 170, 60 }

type Opts = {
	yaw: number?,
	rotation: { number }?,
	shape: string?,
	solid: boolean?,
	glow: { number }?,
	light: number?,
	transparency: number?,
	words: { Words }?,
}

local function add(list: { Piece }, name: string, size: { number }, at: { number }, color: { number }, material: string, opts: Opts?): Piece
	local o: Opts = opts or {}
	local piece: Piece = {
		name = name,
		size = size,
		at = at,
		color = color,
		material = material,
		yaw = o.yaw,
		rotation = o.rotation,
		shape = o.shape,
		solid = o.solid,
		glow = o.glow,
		light = o.light,
		transparency = o.transparency,
		words = o.words,
	}
	table.insert(list, piece)
	return piece
end

-- A group's pieces (built in its own frame) into the set's: its middle at (ox, oy, oz), turned `yaw` degrees.
local function group(list: { Piece }, ox: number, oy: number, oz: number, yaw: number, parts: { Piece })
	local r = math.rad(yaw)
	local c, s = math.cos(r), math.sin(r)
	for _, piece in parts do
		local x, y, z = piece.at[1], piece.at[2], piece.at[3]
		piece.at = { ox + x * c + z * s, oy + y, oz - x * s + z * c }
		piece.yaw = (piece.yaw or 0) + yaw
		table.insert(list, piece)
	end
end

local function line(text: string, color: { number }, size: number, font: string?): Line
	return { text = text, color = color, size = size, font = font }
end

-- The yaw (degrees) of a frame whose -Z points along (fx, fz): CFrame.Angles(0, yaw, 0) turns -Z onto it.
local function facingYaw(fx: number, fz: number): number
	return math.deg(math.atan2(-fx, -fz))
end
MoveSiteLooks.facingYaw = facingYaw

-- ── The Wall's checkpoint ───────────────────────────────────────────────────

-- A floodlight mast (its own frame: -Z toward what it lights): the pole, the bar with its light, two heads tilted down
-- (`tag` ends every name: W, E).
local function mast(tag: string): { Piece }
	local p: { Piece } = {}
	add(p, "MastPole" .. tag, { 0.8, 17.6, 0.8 }, { 0, 8.8, 0 }, STEEL, "Metal", { solid = true })
	add(p, "MastBar" .. tag, { 4.2, 0.35, 0.35 }, { 0, 17.0, -0.3 }, DARK, "Metal")
	for _, side in { -1, 1 } do
		local s = (if side < 0 then "L" else "R") .. tag
		add(p, "Flood" .. s, { 1.4, 1.0, 0.7 }, { side * 1.5, 17.0, -0.8 }, DARK, "Metal", { rotation = { -30, 0, 0 } })
		-- (the glass on the head's front: its middle 0.39 in front of the head's, turned with it; one light a mast)
		add(p, "FloodGlass" .. s, { 1.2, 0.8, 0.08 }, { side * 1.5, 16.805, -1.138 }, { 150, 156, 160 }, "Glass", {
			rotation = { -30, 0, 0 },
			glow = COOL,
			light = if side < 0 then 34 else nil,
		})
	end
	return p
end

-- The army truck (its own frame: the nose to -Z), parked: six wheels, the cab, the canvas over the bed.
local function armyTruck(): { Piece }
	local p: { Piece } = {}
	add(p, "TruckChassis", { 6.2, 1.0, 14.4 }, { 0, 1.9, 0.2 }, DARK, "Metal", { solid = true })
	add(p, "TruckHood", { 6.0, 1.9, 3.0 }, { 0, 3.35, -5.7 }, OLIVE, "Metal", { solid = true })
	add(p, "TruckCab", { 6.8, 4.1, 3.6 }, { 0, 4.45, -2.4 }, OLIVE, "Metal", { solid = true })
	add(p, "TruckWindscreen", { 5.8, 1.5, 0.12 }, { 0, 5.4, -4.22 }, GLASS, "Glass")
	add(p, "TruckGrille", { 4.4, 1.4, 0.14 }, { 0, 3.25, -7.25 }, DARK, "Metal")
	add(p, "TruckBumper", { 6.9, 0.7, 0.6 }, { 0, 2.0, -7.55 }, DARK, "Metal")
	add(p, "TruckBed", { 6.8, 1.5, 7.8 }, { 0, 3.15, 3.3 }, OLIVE, "Metal", { solid = true })
	local stencil = { line("EVACUATION", WHITE, 0.3, "Black"), line("ARMY · THE WALL", WHITE, 0.14) }
	add(p, "TruckTarp", { 6.9, 3.8, 7.6 }, { 0, 5.8, 3.3 }, CANVAS, "Fabric", { solid = true, words = {
		{ face = "Right", lines = stencil },
		{ face = "Left", lines = stencil },
	} })
	add(p, "TarpRidge", { 6.2, 0.4, 7.6 }, { 0, 7.9, 3.3 }, CANVAS, "Fabric")
	add(p, "TruckTank", { 2.0, 1.1, 1.1 }, { 3.25, 2.0, -1.6 }, STEEL, "Metal", { shape = "Cylinder", yaw = 90 })
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		add(p, "TruckGlass" .. s, { 0.12, 1.3, 2.0 }, { side * 3.42, 5.45, -2.6 }, GLASS, "Glass")
		add(p, "TruckLamp" .. s, { 0.9, 0.6, 0.12 }, { side * 2.5, 3.65, -7.26 }, { 214, 210, 176 }, "SmoothPlastic")
		add(p, "Star" .. s, { 0.06, 1.3, 1.3 }, { side * 3.43, 4.2, -2.4 }, OLIVE, "Metal", { words = {
			{ face = if side < 0 then "Left" else "Right", lines = { line("★", WHITE, 0.9) } },
		} })
		for n, z in { -5.0, 2.0, 5.2 } do
			add(p, `Wheel{s}{n}`, { 0.9, 2.8, 2.8 }, { side * 3.1, 1.4, z }, DARK, "Rubber", { shape = "Cylinder" })
		end
	end
	return p
end

function MoveSiteLooks.checkpoint(): { Piece }
	local t = Config.MoveSites
	local w, d = t.Bay[1], t.Bay[2]
	local clear = t.Clear
	local p: { Piece } = {}
	-- The bay on the yard (the drop-off: its orange outline as before), two chevrons into it, a stop bar at its end.
	add(p, "LineNorth", { w, 0.1, 0.6 }, { 0, 0.05, -d / 2 + 0.3 }, ORANGE, "Neon")
	add(p, "LineSouth", { w, 0.1, 0.6 }, { 0, 0.05, d / 2 - 0.3 }, ORANGE, "Neon") -- (on the yard, not the kerb)
	add(p, "LineWest", { 0.6, 0.1, d }, { -w / 2, 0.05, 0 }, ORANGE, "Neon")
	add(p, "LineEast", { 0.6, 0.1, d }, { w / 2, 0.05, 0 }, ORANGE, "Neon")
	for n, z in { d / 2 - 4.5, d / 2 - 10 } do
		for _, side in { -1, 1 } do
			add(p, `Chevron{n}{if side < 0 then "L" else "R"}`, { 4.6, 0.06, 0.8 }, { side * 1.75, 0.04, z }, WHITE, "SmoothPlastic", { yaw = -side * 40.6 })
		end
	end
	add(p, "StopBar", { w - 4, 0.06, 0.7 }, { 0, 0.04, -d / 2 + 1.6 }, WHITE, "SmoothPlastic")
	for n, z in { d / 2 - 2.2, d / 2 - 6.8, d / 2 - 11.4 } do -- the lane's dashed edges in from the kerb
		for _, side in { -1, 1 } do
			add(p, `LaneDash{n}{if side < 0 then "W" else "E"}`, { 0.4, 0.06, 2.6 }, { side * 5.2, 0.04, z }, YELLOW, "SmoothPlastic")
		end
	end

	-- The gantry over the bay's mouth on the yard's edge: two posts, the beam, the SAFE ZONE sign (to the street and to
	-- the yard), amber beacons on top. Its sign hangs over `clear` studs: the trucks pass under it.
	local gx, gz = w / 2 + 2, d / 2 - 1.5
	local postHeight = clear + 4.9
	for _, side in { -1, 1 } do
		local s = if side < 0 then "W" else "E"
		add(p, "GantryPost" .. s, { 1, postHeight, 1 }, { side * gx, postHeight / 2, gz }, YELLOW, "Metal", { solid = true })
		for n, y in { 1.6, 3.6 } do
			add(p, `PostBand{s}{n}`, { 1.06, 0.7, 1.06 }, { side * gx, y, gz }, BLACK, "Metal")
		end
		add(p, "Beacon" .. s, { 0.6, 0.5, 0.6 }, { side * gx, postHeight + 0.25, gz }, AMBER, "SmoothPlastic", { glow = AMBER })
	end
	add(p, "GantryBeam", { 2 * gx + 1, 0.7, 0.7 }, { 0, clear + 4.35, gz }, STEEL, "Metal")
	local title = line("SAFE ZONE — EVACUATION CHECKPOINT", SIGN_YELLOW, 0.44, "Black")
	add(p, "CheckpointSign", { 2 * gx - 2, 4, 0.4 }, { 0, clear + 2, gz }, OLIVE_DARK, "Metal", { words = {
		{ face = "Back", lit = true, lines = { title, line("THE WALL · ZDC MOVING DROP-OFF · DRIVE THE TRUCK IN", ORANGE, 0.22, "Bold") } },
		{ face = "Front", lit = true, lines = { title, line("THE WALL · ZDC MOVING DROP-OFF", ORANGE, 0.24, "Bold") } },
	} })
	add(p, "SignTrim", { 2 * gx - 2, 0.3, 0.46 }, { 0, clear - 0.15, gz }, RED, "Metal")

	-- The Wall's stubs: T-wall panels (a footing and a slab) along the yard's edge each side of the gate and north along
	-- the block's east edge, the fence and the wire over them, hazard bands on the panels by the gate.
	local wz = d / 2 - 1.2 -- the panels along the edge (their slabs' middle)
	local ex = w / 2 + 8.9 -- the east run's (along the block's east edge)
	local function panel(name: string, x: number, z: number, alongX: boolean, words: { Words }?)
		local long = 3.4
		add(p, name .. "Foot", if alongX then { long, 1.2, 2.2 } else { 2.2, 1.2, long }, { x, 0.6, z }, CONCRETE, "Concrete", { solid = true })
		add(p, name, if alongX then { long, 9.8, 1 } else { 1, 9.8, long }, { x, 6.1, z }, CONCRETE, "Concrete", { solid = true, words = words })
	end
	local stencil = function(a: string, b: string): { Words }
		return { { face = "Back", lines = { line(a, BLACK, 0.06, "Black"), line(b, BLACK, 0.032, "Bold") } } }
	end
	panel("WallW1", -15.5, wz, true)
	panel("WallW2", -18.9, wz, true, stencil("NO ENTRY", "AUTHORIZED VEHICLES ONLY"))
	panel("WallE1", 15.5, wz, true)
	panel("WallE2", 18.9, wz, true, stencil("SAFE ZONE", "ARMY CHECKPOINT 01"))
	for n, z in { 5.6, 2.2, -1.2, -4.6 } do
		panel(`WallN{n}`, ex, z, false)
	end
	local fence = { 150, 156, 158 }
	local function run(name: string, x: number, z: number, alongX: boolean, length: number)
		add(p, name .. "Fence", if alongX then { length, 3.4, 0.12 } else { 0.12, 3.4, length }, { x, 12.7, z }, fence, "Metal", { transparency = 0.5 })
		add(p, name .. "Wire", { length, 0.8, 0.8 }, { x, 14.8, z }, { 70, 74, 76 }, "Metal", { shape = "Cylinder", yaw = if alongX then 0 else 90, transparency = 0.15 })
		for n, k in { -1, 1 } do
			local along = k * (length / 2 - 0.15)
			add(p, `{name}Post{n}`, { 0.25, 4.2, 0.25 }, if alongX then { x + along, 13.1, z } else { x, 13.1, z + along }, STEEL, "Metal")
		end
	end
	run("RunW", -17.2, wz, true, 6.8)
	run("RunE", 17.2, wz, true, 6.8)
	run("RunN", ex, 0.5, false, 13.6)
	for _, x in { -15.5, 15.5 } do
		local s = if x < 0 then "W" else "E"
		add(p, "Hazard" .. s, { 3.44, 0.9, 1.06 }, { x, 3.0, wz }, YELLOW, "SmoothPlastic")
		add(p, "HazardStripe" .. s, { 3.46, 0.3, 1.08 }, { x, 3.0, wz }, BLACK, "SmoothPlastic")
	end

	-- The floodlights: one at the west stub's end, one at the north end of the east run, each turned to the bay.
	group(p, -22.0, 0, wz - 1.2, facingYaw(22.0, -(wz - 1.2)), mast("W"))
	group(p, ex, 0, -7.4, facingYaw(-ex, 7.4), mast("E"))

	-- The barrier arm, raised, hinged on the east post (red and white).
	add(p, "BarrierHinge", { 0.7, 0.6, 0.9 }, { gx - 0.85, 3.4, gz }, YELLOW, "Metal")
	add(p, "BarrierArm", { 0.32, 11.5, 0.32 }, { gx - 0.85, 9.45, gz }, WHITE, "SmoothPlastic")
	for n, y in { 5.6, 8.6, 11.6, 14.6 } do
		add(p, `ArmBand{n}`, { 0.36, 1.1, 0.36 }, { gx - 0.85, y, gz }, RED, "SmoothPlastic")
	end
	-- The army's booth by the lane east of the bay (its window to the lane), sandbags north of it. The people's walk
	-- line round the depot's block (4.5 in from its curbs, TrafficLanes) passes south and east of it: kept clear.
	add(p, "Booth", { 3.2, 7.2, 3.2 }, { 13.3, 3.6, 1.0 }, OLIVE, "Metal", { solid = true })
	add(p, "BoothGlass", { 3.3, 1.5, 3.3 }, { 13.3, 5.2, 1.0 }, GLASS, "Glass", { transparency = 0.25, glow = WARM })
	add(p, "BoothRoof", { 3.5, 0.45, 4.0 }, { 13.3, 7.42, 1.0 }, OLIVE_DARK, "Metal")
	add(p, "BoothDoor", { 1.5, 4.6, 0.1 }, { 13.9, 2.3, -0.65 }, OLIVE_DARK, "Metal")
	add(p, "BoothSign", { 3.0, 0.7, 0.1 }, { 11.66, 6.55, 1.0 }, OLIVE_DARK, "Metal", { yaw = 90, words = {
		{ face = "Front", lines = { line("ARMY CHECKPOINT", WHITE, 0.8, "Black") } },
	} })
	add(p, "Antenna", { 0.1, 3.6, 0.1 }, { 14.6, 9.45, 2.3 }, STEEL, "Metal")
	for n, b in { { 12.5, 0.375, 3 }, { 14.0, 0.375, -4 }, { 13.25, 1.1, 2 } } do
		add(p, `Sandbag{n}`, { 1.6, 0.75, 1.0 }, { b[1], b[2], -1.9 }, SAND, "Fabric", { yaw = b[3], solid = true })
	end
	-- North of the east stub the Wall goes on as a line of jersey barriers along the block's edge.
	for n, z in { -12.5, -19.5 } do
		add(p, `JerseyBase{n}`, { 6, 1.0, 2.0 }, { ex, 0.5, z }, JERSEY, "Concrete", { yaw = 90, solid = true })
		add(p, `JerseyTop{n}`, { 6, 1.9, 0.9 }, { ex, 1.95, z }, JERSEY, "Concrete", { yaw = 90, solid = true })
		add(p, `JerseyStripe{n}`, { 6.02, 0.3, 0.92 }, { ex, 2.55, z }, RED, "SmoothPlastic", { yaw = 90 })
	end

	-- The army truck west of the gate, its nose to the Wall.
	group(p, t.Truck[1], 0, t.Truck[2], 180, armyTruck())
	return p
end

-- ── The Moving contracts kiosk ──────────────────────────────────────────────

-- A pinned paper or photo on the corkboard (its front just off the cork) and its pin.
local function pinned(p: { Piece }, name: string, size: { number }, x: number, y: number, turn: number, color: { number }, words: { Words }, pin: { number })
	add(p, name, { size[1], size[2], 0.04 }, { x, y, 0.43 }, color, "SmoothPlastic", { rotation = { 0, 0, turn }, words = words })
	add(p, name .. "Pin", { 0.16, 0.16, 0.1 }, { x, y + size[2] / 2 - 0.14, 0.38 }, pin, "SmoothPlastic")
end

local function photo(emoji: string, caption: string, sky: { number }): { Words }
	return { { face = "Front", back = sky, inset = 0.07, lines = { line(emoji, INK, 0.6), line(caption, CHARCOAL, 0.2, "Bold") } } }
end

function MoveSiteLooks.board(): { Piece }
	local p: { Piece } = {}
	add(p, "Plinth", { 7.8, 0.5, 2.0 }, { 0, 0.25, 0.5 }, CONCRETE, "Concrete", { solid = true })
	for _, side in { -1, 1 } do
		add(p, if side < 0 then "KioskPostL" else "KioskPostR", { 0.45, 8.8, 0.45 }, { side * 3.7, 4.4, 0.8 }, CHARCOAL, "Metal", { solid = true })
	end
	add(p, "Backing", { 7.4, 5.4, 0.3 }, { 0, 4.9, 0.8 }, { 44, 52, 50 }, "Metal", { solid = true })
	add(p, "Board", { 6.8, 3.6, 0.2 }, { 0, 4.9, 0.55 }, CORK, "Fabric", { solid = true })
	add(p, "Header", { 7.4, 1.1, 0.3 }, { 0, 8.15, 0.8 }, ORANGE, "Metal", { words = {
		{ face = "Front", lit = true, lines = { line("MOVING CONTRACTS", CHARCOAL, 0.54, "Black"), line("ZDC MOVING & EVACUATION", CHARCOAL, 0.28, "Bold") } },
	} })
	add(p, "Canopy", { 8.4, 0.25, 2.4 }, { 0, 9.0, 0.4 }, CHARCOAL, "Metal", { rotation = { -6, 0, 0 } })
	add(p, "LampArm", { 0.12, 0.12, 1.4 }, { 0, 8.82, -0.95 }, CHARCOAL, "Metal")
	add(p, "LampShade", { 1.6, 0.35, 0.6 }, { 0, 8.6, -1.75 }, CHARCOAL, "Metal")
	add(p, "LampGlass", { 1.4, 0.06, 0.45 }, { 0, 8.4, -1.75 }, PAPER, "Glass", { glow = WARM, light = 16 })
	add(p, "Slogan", { 6.8, 0.42, 0.05 }, { 0, 2.55, 0.62 }, CHARCOAL, "SmoothPlastic", { words = {
		{ face = "Front", lines = { line("We move your life. They eat everything else.", GREY, 0.8, "Bold") } },
	} })
	add(p, "Ledge", { 6.4, 0.12, 0.6 }, { 0, 2.15, 0.35 }, CHARCOAL, "Metal")
	add(p, "Folders", { 1.0, 0.2, 0.45 }, { -1.8, 2.31, 0.35 }, { 226, 196, 128 }, "SmoothPlastic", { yaw = 6 }) -- (contracts to take)
	-- The corkboard: four columns, two rows. The houses on the list (Marge's first), the notices, the ZDC logo.
	local top, low = 5.75, 3.95
	pinned(p, "PhotoMarge", { 1.3, 1.15 }, -2.55, top, 3, PAPER, photo("🏠", "MARGE · WILLOW LN", { 148, 196, 228 }), RED)
	pinned(p, "FlyerEvac", { 1.3, 1.5 }, -0.85, top, -2, PAPER, { { face = "Front", lines = {
		line("EVACUATION NOTICE", RED, 0.16, "Black"),
		line("ZONE 3 CLOSES SOON", CHARCOAL, 0.12, "Bold"),
		line("Pack one truck. Go to the Wall.", CHARCOAL, 0.1),
	} } }, YELLOW)
	pinned(p, "PhotoRanch", { 1.3, 1.15 }, 0.85, top, -4, PAPER, photo("🐄", "WALT'S RANCH", { 170, 206, 140 }), { 60, 110, 200 })
	add(p, "Logo", { 1.4, 1.4, 0.06 }, { 2.55, top, 0.42 }, CHARCOAL, "SmoothPlastic", { words = {
		{ face = "Front", lit = true, lines = { line("ZDC", ORANGE, 0.5, "Black"), line("MOVING", INK, 0.2, "Bold") } },
	} })
	pinned(p, "FlyerThieves", { 1.3, 1.1 }, -2.55, low, 4, { 255, 236, 150 }, { { face = "Front", lines = {
		line("WARNING", RED, 0.26, "Black"),
		line("BIG MOVE MOVERS STEAL CARGO", CHARCOAL, 0.2, "Bold"),
	} } }, RED)
	pinned(p, "PhotoHotel", { 1.3, 1.15 }, -0.85, low, 2, PAPER, photo("🏨", "GRAND HOTEL", { 196, 180, 220 }), YELLOW)
	pinned(p, "FlyerPiano", { 1.2, 1.2 }, 0.85, low, -3, PAPER, { { face = "Front", lines = {
		line("HELP! A PIANO", CHARCOAL, 0.24, "Black"),
		line("Two strong movers wanted", CHARCOAL, 0.15),
	} } }, { 60, 150, 80 })
	pinned(p, "PhotoClinic", { 1.3, 1.15 }, 2.55, low, -2, PAPER, photo("🏥", "CITY CLINIC", { 210, 226, 236 }), RED)
	return p
end

-- ── A house on moving day ───────────────────────────────────────────────────

type Box = { name: string, size: { number }, at: { number }, turn: number, label: string?, ink: { number }? }

-- None of it is solid (the crew carries sofas past it); nothing on the path from the door to the street.
function MoveSiteLooks.house(title: string, park: number): { Piece }
	local p: { Piece } = {}
	-- The yard sign left of the path (the mailbox stands right of it), facing the street.
	add(p, "YardSign", { 4.6, 2.3, 0.15 }, { -6.5, 3.35, -4.6 }, CHARCOAL, "SmoothPlastic", { words = {
		{ face = "Front", lit = true, lines = {
			line("ZDC MOVING", ORANGE, 0.34, "Black"),
			line(string.upper(title), INK, 0.28, "Bold"),
			line("Moving day · We move your life.", GREY, 0.13),
		} },
	} })
	add(p, "YardSignTop", { 4.8, 0.35, 0.22 }, { -6.5, 4.68, -4.6 }, ORANGE, "SmoothPlastic")
	for _, x in { -8.6, -4.4 } do
		add(p, if x < -6.5 then "YardPostL" else "YardPostR", { 0.22, 4.9, 0.22 }, { x, 2.45, -4.45 }, WOOD, "Wood")
	end
	-- Packed boxes by the door (a stack on its left, one and a rolled rug on its right).
	local boxes: { Box } = {
		{ name = "BoxA", size = { 1.8, 1.4, 1.5 }, at = { -3.7, 0.7, -1.05 }, turn = 4, label = "FRAGILE", ink = RED },
		{ name = "BoxB", size = { 1.5, 1.2, 1.3 }, at = { -3.6, 2.0, -1.0 }, turn = -7 },
		{ name = "BoxC", size = { 1.3, 1.0, 1.2 }, at = { -5.5, 0.5, -1.1 }, turn = 12 },
		{ name = "BoxD", size = { 1.7, 1.3, 1.4 }, at = { 3.8, 0.65, -1.0 }, turn = -5, label = "KITCHEN", ink = CHARCOAL },
	}
	for _, b in boxes do
		local label = b.label
		add(p, b.name, b.size, b.at, CARDBOARD, "SmoothPlastic", { yaw = b.turn, words = if label then {
			{ face = "Front", lines = { line(label, b.ink or CHARCOAL, 0.26, "Black") } },
		} else nil })
		add(p, b.name .. "Tape", { 0.32, 0.04, b.size[3] + 0.02 }, { b.at[1], b.at[2] + b.size[2] / 2 + 0.02, b.at[3] }, TAPE, "SmoothPlastic", { yaw = b.turn })
	end
	add(p, "Rug", { 3.0, 0.8, 0.8 }, { 5.6, 1.45, -0.55 }, { 150, 60, 52 }, "Fabric", { shape = "Cylinder", rotation = { 0, 0, 78 } })
	-- MOVING DAY over the door.
	add(p, "DayBanner", { 8.4, 1.3, 0.06 }, { 0, 8.55, -0.1 }, { 250, 246, 236 }, "Fabric", { words = {
		{ face = "Front", lines = { line("MOVING DAY!", ORANGE, 0.58, "Black"), line("ZDC MOVING & EVACUATION", CHARCOAL, 0.24, "Bold") } },
	} })
	-- The realtor's sign right of the mailbox: FOR SALE, and the army's EVACUATED strip across it.
	add(p, "RealtorPost", { 0.22, 4.4, 0.22 }, { 8.9, 2.2, -5.0 }, WHITE, "Wood")
	add(p, "RealtorArm", { 2.3, 0.18, 0.18 }, { 7.85, 4.25, -5.0 }, WHITE, "Wood")
	add(p, "ForSale", { 2.0, 1.3, 0.08 }, { 7.75, 3.35, -5.0 }, WHITE, "SmoothPlastic", { words = {
		{ face = "Front", lines = { line("FOR SALE", RED, 0.36, "Black"), line("Willow Realty", CHARCOAL, 0.16) } },
	} })
	add(p, "EvacStrip", { 2.3, 0.42, 0.04 }, { 7.75, 3.25, -5.07 }, RED, "SmoothPlastic", { rotation = { 0, 0, -14 }, words = {
		{ face = "Front", lit = true, lines = { line("EVACUATED", INK, 0.8, "Black") } },
	} })
	-- Cones on the road at the four corners of the truck's spot (the truck along the kerb, its middle `park` out).
	local road = Map.RoadTop - Map.WalkTop
	local n = 0
	for _, z in { -(park - 3.4), -(park + 3.4) } do
		for _, x in { -10.5, 10.5 } do
			n += 1
			add(p, `ConeBase{n}`, { 0.95, 0.12, 0.95 }, { x, road + 0.06, z }, BLACK, "Rubber")
			add(p, `Cone{n}`, { 1.3, 0.55, 0.55 }, { x, road + 0.77, z }, { 255, 112, 32 }, "SmoothPlastic", { shape = "Cylinder", rotation = { 0, 0, 90 } })
			add(p, `ConeBand{n}`, { 0.26, 0.6, 0.6 }, { x, road + 0.92, z }, WHITE, "SmoothPlastic", { shape = "Cylinder", rotation = { 0, 0, 90 } })
		end
	end
	return p
end

-- ── The depot's banner ──────────────────────────────────────────────────────

function MoveSiteLooks.banner(): { Piece }
	local b = Config.MoveSites.Banner
	local p: { Piece } = {}
	add(p, "Banner", { b.Width, b.Height, 0.12 }, { 0, 0, 0 }, ORANGE, "Fabric", { words = {
		{ face = "Front", lines = {
			line("ZDC MOVING & EVACUATION", CHARCOAL, 0.54, "Black"),
			line("We move your life. They eat everything else.", CHARCOAL, 0.26, "Bold"),
		} },
	} })
	add(p, "BannerRod", { b.Width + 0.6, 0.2, 0.2 }, { 0, b.Height / 2 + 0.05, 0 }, STEEL, "Metal")
	for _, side in { -1, 1 } do
		add(p, if side < 0 then "BannerTieL" else "BannerTieR", { 0.14, b.Hang, 0.14 }, { side * (b.Width / 2 - 1), b.Height / 2 + b.Hang / 2, 0 }, STEEL, "Metal")
	end
	return p
end

-- ── An evacuation spot ──────────────────────────────────────────────────────

-- A poster board on its feet (EVACUATE to the street and to the walk) and a pile of moving boxes left on the kerb
-- beside it (on its right or, for an odd seed, its left), one of them open with a lamp in it.
function MoveSiteLooks.spot(seed: number): { Piece }
	local p: { Piece } = {}
	local poster = { line("EVACUATE", INK, 0.42, "Black"), line("ZONE CLOSING", SIGN_YELLOW, 0.24, "Black"), line("Go to the Wall · Army orders", INK, 0.14, "Bold") }
	add(p, "PosterBoard", { 4.4, 2.9, 0.14 }, { 0, 3.5, 0 }, RED, "SmoothPlastic", { words = {
		{ face = "Front", lines = poster },
		{ face = "Back", lines = poster },
	} })
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		add(p, "PosterLeg" .. s, { 0.18, 4.9, 0.18 }, { side * 1.9, 2.45, 0.12 }, STEEL, "Metal")
		add(p, "PosterFoot" .. s, { 0.5, 0.14, 1.3 }, { side * 1.9, 0.07, 0.12 }, DARK, "Metal")
	end
	local k = if seed % 2 == 0 then 1 else -1
	local turn = (seed % 5) * 4
	add(p, "OldBoxA", { 1.6, 1.3, 1.3 }, { k * 3.6, 0.65, 0.2 }, CARDBOARD, "SmoothPlastic", { yaw = 8 + turn })
	add(p, "OldBoxATape", { 0.3, 0.04, 1.32 }, { k * 3.6, 1.32, 0.2 }, TAPE, "SmoothPlastic", { yaw = 8 + turn })
	add(p, "OldBoxB", { 1.4, 1.1, 1.2 }, { k * 5.2, 0.55, 0.2 }, CARDBOARD, "SmoothPlastic", { yaw = -15 - turn })
	add(p, "OldBoxFlap", { 1.3, 0.04, 0.55 }, { k * 5.2, 1.18, -0.38 }, CARDBOARD, "SmoothPlastic", { yaw = -15 - turn, rotation = { 40, 0, 0 } })
	add(p, "OldBoxC", { 1.25, 1.0, 1.1 }, { k * 3.75, 1.8, 0.25 }, CARDBOARD, "SmoothPlastic", { yaw = 20 - turn })
	add(p, "OldBoxCTape", { 0.3, 0.04, 1.12 }, { k * 3.75, 2.32, 0.25 }, TAPE, "SmoothPlastic", { yaw = 20 - turn })
	add(p, "LampStem", { 0.1, 1.1, 0.1 }, { k * 5.35, 1.6, 0.25 }, STEEL, "Metal")
	add(p, "LampHat", { 0.6, 0.65, 0.65 }, { k * 5.35, 2.25, 0.25 }, { 222, 206, 160 }, "Fabric", { shape = "Cylinder", rotation = { 0, 0, 90 } })
	return p
end

-- ── Where they stand ────────────────────────────────────────────────────────

function MoveSiteLooks.checkpointPlace(): Place
	local d = Config.Moving.DropOff
	return { x = Map.Depot.x + d[1], y = Map.WalkTop, z = Map.Depot.z + d[2], yaw = 0 }
end

function MoveSiteLooks.boardPlace(): Place
	local b = Config.Moving.Board
	return { x = Map.Depot.x + b[1], y = Map.WalkTop, z = Map.Depot.z + b[2], yaw = facingYaw(-1, 0) } -- facing the yard (-X)
end

function MoveSiteLooks.bannerPlace(): Place
	local b = Config.MoveSites.Banner
	return { x = Map.Depot.x + b.X, y = Map.WalkTop + b.Y, z = Map.Depot.z + b.Z, yaw = facingYaw(0, 1) } -- facing the yard (+Z)
end

function MoveSiteLooks.doorPlace(home: Map.Home): Place
	return { x = home.door.x, y = Map.WalkTop, z = home.door.z, yaw = facingYaw(home.facing.x, home.facing.z) }
end

-- Studs from a home's door out to its park (the truck's kerb spot), along its facing.
function MoveSiteLooks.parkDepth(home: Map.Home): number
	return (home.park.x - home.door.x) * home.facing.x + (home.park.z - home.door.z) * home.facing.z
end

-- The block sides as StreetProps has them: (nx, nz) out of the block, (tx, tz) along it.
local SIDES: { [string]: { number } } = { n = { 0, -1, 1, 0 }, e = { 1, 0, 0, 1 }, s = { 0, 1, -1, 0 }, w = { -1, 0, 0, -1 } }

function MoveSiteLooks.spotPlaces(): { Place }
	local t = Config.MoveSites
	local list: { Place } = {}
	for index, spot in t.Spots do
		local district: Map.District? = nil
		for _, d in Map.Districts do
			if d.id == spot.district then
				district = d
			end
		end
		local side = SIDES[spot.side]
		assert(district and side, "MoveSiteLooks: an unknown evacuation spot")
		local cx, cz = district.ox + spot.i * Map.Cell, district.oz + spot.j * Map.Cell
		local out = Map.BlockSize / 2 - t.Depth
		table.insert(list, {
			x = cx + side[1] * out + side[3] * spot.along,
			y = Map.WalkTop,
			z = cz + side[2] * out + side[4] * spot.along,
			yaw = facingYaw(side[1], side[2]),
			seed = index,
		})
	end
	return list
end

function MoveSiteLooks.all(): { Set }
	local sets: { Set } = {
		{ id = "checkpoint", place = MoveSiteLooks.checkpointPlace(), pieces = MoveSiteLooks.checkpoint() },
		{ id = "board", place = MoveSiteLooks.boardPlace(), pieces = MoveSiteLooks.board() },
		{ id = "banner", place = MoveSiteLooks.bannerPlace(), pieces = MoveSiteLooks.banner() },
	}
	for _, contract in Config.Moving.Contracts do
		local home = Map.home(contract.home)
		if home then
			table.insert(sets, { id = "house_" .. contract.id, place = MoveSiteLooks.doorPlace(home), pieces = MoveSiteLooks.house(contract.name, MoveSiteLooks.parkDepth(home)) })
		end
	end
	for _, place in MoveSiteLooks.spotPlaces() do
		table.insert(sets, { id = `spot{place.seed}`, place = place, pieces = MoveSiteLooks.spot(place.seed or 1) })
	end
	return sets
end

-- ── Geometry ────────────────────────────────────────────────────────────────

-- A piece's turn as a 3 × 3 matrix (rows), with its set's yaw: Ry(set + piece yaw) × CFrame.Angles(rotation).
local function matrix(yaw: number, rotation: { number }?): { number }
	local r = rotation or { 0, 0, 0 }
	local x, y, z = math.rad(r[1]), math.rad(r[2]), math.rad(r[3])
	local sx, cx, sy, cy, sz, cz = math.sin(x), math.cos(x), math.sin(y), math.cos(y), math.sin(z), math.cos(z)
	local a = {
		cy * cz, -cy * sz, sy,
		cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy,
		sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy,
	}
	local s, c = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
	local m = { c, 0, s, 0, 1, 0, -s, 0, c }
	local out = table.create(9, 0)
	for i = 0, 2 do
		for j = 0, 2 do
			local sum = 0
			for k = 0, 2 do
				sum += m[i * 3 + k + 1] * a[k * 3 + j + 1]
			end
			out[i * 3 + j + 1] = sum
		end
	end
	return out
end
MoveSiteLooks.matrix = matrix

function MoveSiteLooks.box(place: Place, piece: Piece): (number, number, number, number, number, number)
	local m = matrix(place.yaw + (piece.yaw or 0), piece.rotation)
	local s, c = math.sin(math.rad(place.yaw)), math.cos(math.rad(place.yaw))
	local ax, ay, az = piece.at[1], piece.at[2], piece.at[3]
	local x, y, z = place.x + ax * c + az * s, place.y + ay, place.z - ax * s + az * c
	local half = { 0, 0, 0 }
	for i = 0, 2 do
		half[i + 1] = (math.abs(m[i * 3 + 1]) * piece.size[1] + math.abs(m[i * 3 + 2]) * piece.size[2] + math.abs(m[i * 3 + 3]) * piece.size[3]) / 2
	end
	return x - half[1], x + half[1], y - half[2], y + half[2], z - half[3], z + half[3]
end

-- Does it throw a shadow (RenderBudget.casts: its thinnest side's axis how upright, its middle's height)?
function MoveSiteLooks.shadow(piece: Piece, baseY: number): boolean
	local size = piece.size
	local m = matrix(piece.yaw or 0, piece.rotation)
	local k = 1
	if size[2] < size[k] then
		k = 2
	end
	if size[3] < size[k] then
		k = 3
	end
	return RenderBudget.casts(size[1], size[2], size[3], math.abs(m[3 + k]), baseY + piece.at[2])
end

-- A face's width and height (studs) on a part of this size.
function MoveSiteLooks.faceSize(face: string, size: { number }): (number, number)
	if face == "Left" or face == "Right" then
		return size[3], size[2]
	elseif face == "Top" then
		return size[1], size[3]
	end
	return size[1], size[2]
end

-- A face's SurfaceGui: about 1,000 pixels across its longer side (sharp scaled text, never huge), drawn this close.
function MoveSiteLooks.pixels(width: number, height: number): number
	return math.clamp(math.floor(1000 / math.max(width, height, 0.1)), 25, 100)
end

function MoveSiteLooks.textRange(height: number): number
	local p = Config.Performance
	return math.clamp(p.SignPerStud * height, Config.MoveSites.TextRange, p.NameBoardRange)
end

return MoveSiteLooks
