--!strict
-- The ZDC dispatch kiosk's look (9.7 runs: the lobby's dispatch, server/LobbyWorld.luau at SandboxMap.Lobby.dispatch),
-- as plain numbers: its parts in its own frame (Config.MoveSites). server/MoveSites.luau builds them (anchored, CanTouch
-- off; only the pieces marked solid collide and stop bullets), tests/movesites_test.luau checks them, tools/move-sites/
-- check.py checks the built parts. Pure Luau. 10.5: the city's moving world (the Wall's checkpoint, the depot's kiosk
-- and banner, the houses' moving-day dress, the evacuation spots, Walt's farm) went with the city.
--
-- A piece: name (unique in its set), size, at (its middle in the set's frame: +X right, +Y up from the ground, -Z
-- forward, the way the set faces), color (0 … 255), material (an Enum.Material name), yaw (degrees about its vertical
-- axis, first), rotation (degrees about X, Y, Z after that, as CFrame.Angles), shape (Block | Cylinder | Wedge; a
-- cylinder's axis is its X and its Y and Z are the same), solid (it collides and stops bullets: CanCollide and CanQuery;
-- else neither), glow (its lamp glass's colour, Neon at night: DayNight's lamp, the day look in the sandbox), light (a
-- PointLight's range in it), transparency, words (text on its faces: one SurfaceGui each; a line's size is its share of
-- the face's height; back: a coloured panel behind the lines, inset from the face's edges; lit: the text does not dim
-- in the dark).
--
--   MoveSiteLooks.board()               the kiosk (frame: its foot, -Z toward the plaza): its corkboard "Board" (the
--                                       prompt's part, server/Runs.luau's) with the countryside's places to empty
--                                       (SandboxMap.Houses, one card each) and notices about bringing it home to your
--                                       warehouse; DELIVEROS DISPATCH over it
--   MoveSiteLooks.box(place, piece)     a piece's axis-aligned box in the world: x0, x1, y0, y1, z0, z1
--   MoveSiteLooks.shadow(piece, baseY)  does it throw a shadow (shared/RenderBudget.luau's rule)?
--   MoveSiteLooks.faceSize(face, size), pixels(w, h), textRange(h)   a face's size, its SurfaceGui's PixelsPerStud and
--                                       MaxDistance

local Config = require(script.Parent.Config)
local RenderBudget = require(script.Parent.RenderBudget)
local SandboxMap = require(script.Parent.SandboxMap)

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
	"SmoothPlastic", "Metal", "Concrete", "Fabric", "Wood", "WoodPlanks", "Glass", "Neon", "Rubber", "DiamondPlate", "Grass",
} :: { string }
MoveSiteLooks.Shapes = { "Block", "Cylinder", "Wedge" } :: { string }
MoveSiteLooks.Faces = { "Front", "Back", "Left", "Right", "Top" } :: { string }

-- The palette: the movers' orange, the kiosk's charcoal and concrete, the corkboard's papers.
local ORANGE = { 240, 132, 44 }
local INK = { 242, 242, 240 }
local CHARCOAL = { 28, 30, 34 }
local GREY = { 196, 199, 203 }
local CONCRETE = { 163, 160, 150 }
local YELLOW = { 240, 196, 40 }
local RED = { 196, 48, 40 }
local CORK = { 178, 132, 84 }
local PAPER = { 238, 234, 222 }
local WARM = { 255, 224, 168 } -- a lamp's

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

local function line(text: string, color: { number }, size: number, font: string?): Line
	return { text = text, color = color, size = size, font = font }
end

-- ── The dispatch kiosk ──────────────────────────────────────────────────────

-- A pinned paper or photo on the corkboard (its front just off the cork) and its pin.
local function pinned(p: { Piece }, name: string, size: { number }, x: number, y: number, turn: number, color: { number }, words: { Words }, pin: { number })
	add(p, name, { size[1], size[2], 0.04 }, { x, y, 0.43 }, color, "SmoothPlastic", { rotation = { 0, 0, turn }, words = words })
	add(p, name .. "Pin", { 0.16, 0.16, 0.1 }, { x, y + size[2] / 2 - 0.14, 0.38 }, pin, "SmoothPlastic")
end

local function photo(emoji: string, caption: string, sky: { number }): { Words }
	return { { face = "Front", back = sky, inset = 0.07, lines = { line(emoji, INK, 0.6), line(caption, CHARCOAL, 0.2, "Bold") } } }
end

-- The corkboard (four columns, two rows): the houses to empty, what to do with them (9.7: the lobby's dispatch; its
-- portals take you to the places, SandboxMap.Houses).
local function sandboxPins(p: { Piece }, top: number, low: number)
	local count = #SandboxMap.Houses
	pinned(p, "PhotoHouse", { 1.3, 1.15 }, -2.55, top, 3, PAPER, photo("🏡", `{count} PLACES TO EMPTY`, { 148, 196, 228 }), RED)
	pinned(p, "FlyerHouse", { 1.3, 1.5 }, -0.85, top, -2, PAPER, { { face = "Front", lines = {
		line("THE COUNTRYSIDE", RED, 0.16, "Black"),
		line("WALK TO A PORTAL", CHARCOAL, 0.12, "Bold"),
		line("Bring it home to your warehouse.", CHARCOAL, 0.1),
	} } }, YELLOW)
	pinned(p, "PhotoStand", { 1.3, 1.15 }, 0.85, top, -4, PAPER, photo("🏺", "PUT IT ON SHOW", { 170, 206, 140 }), { 60, 110, 200 })
	add(p, "Logo", { 1.4, 1.4, 0.06 }, { 2.55, top, 0.42 }, CHARCOAL, "SmoothPlastic", { words = {
		{ face = "Front", lit = true, lines = { line("DELIVEROS", ORANGE, 0.5, "Black"), line("MOVING", INK, 0.2, "Bold") } },
	} })
	pinned(p, "FlyerRare", { 1.3, 1.1 }, -2.55, low, 4, { 255, 236, 150 }, { { face = "Front", lines = {
		line("RARE FINDS", RED, 0.26, "Black"),
		line("OLD HOUSES HIDE TREASURES", CHARCOAL, 0.2, "Bold"),
	} } }, RED)
	pinned(p, "PhotoWarehouse", { 1.3, 1.15 }, -0.85, low, 2, PAPER, photo("🏭", "YOUR WAREHOUSE", { 196, 180, 220 }), YELLOW)
	pinned(p, "FlyerRefill", { 1.2, 1.2 }, 0.85, low, -3, PAPER, { { face = "Front", lines = {
		line("NEW EVERY MOVE", CHARCOAL, 0.24, "Black"),
		line("The next house is full again", CHARCOAL, 0.15),
	} } }, { 60, 150, 80 })
	pinned(p, "PhotoEarn", { 1.3, 1.15 }, 2.55, low, -2, PAPER, photo("💰", "EARNS EVERY MINUTE", { 210, 226, 236 }), RED)
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
		{ face = "Front", lit = true, lines = { line("DELIVEROS DISPATCH", CHARCOAL, 0.54, "Black"), line("DELIVEROS MOVING", CHARCOAL, 0.28, "Bold") } },
	} })
	add(p, "Canopy", { 8.4, 0.25, 2.4 }, { 0, 9.0, 0.4 }, CHARCOAL, "Metal", { rotation = { -6, 0, 0 } })
	add(p, "LampArm", { 0.12, 0.12, 1.4 }, { 0, 8.82, -0.95 }, CHARCOAL, "Metal")
	add(p, "LampShade", { 1.6, 0.35, 0.6 }, { 0, 8.6, -1.75 }, CHARCOAL, "Metal")
	add(p, "LampGlass", { 1.4, 0.06, 0.45 }, { 0, 8.4, -1.75 }, PAPER, "Glass", { glow = WARM, light = 16 })
	add(p, "Slogan", { 6.8, 0.42, 0.05 }, { 0, 2.55, 0.62 }, CHARCOAL, "SmoothPlastic", { words = {
		{ face = "Front", lines = { line("We move it. You keep it.", GREY, 0.8, "Bold") } },
	} })
	add(p, "Ledge", { 6.4, 0.12, 0.6 }, { 0, 2.15, 0.35 }, CHARCOAL, "Metal")
	add(p, "Folders", { 1.0, 0.2, 0.45 }, { -1.8, 2.31, 0.35 }, { 226, 196, 128 }, "SmoothPlastic", { yaw = 6 }) -- (contracts to take)
	-- the corkboard: four columns, two rows (sandboxPins)
	sandboxPins(p, 5.75, 3.95)
	return p
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
