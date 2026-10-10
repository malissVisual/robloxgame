--!strict
-- 6.22, every thing in the inventory has a look (the owner: "každá věc musí nějak vypadat a ne mít jen ikonku": every
-- thing must look like something, not only an icon). Each thing the bottom bar (client/Hotbar.luau) and BAG & ITEMS
-- (client/BagUi.luau) show is a small native model, drawn by client/ItemModel.luau in a ViewportFrame:
--   gun:<id>     a gun (Config.Weapons): shared/GunModels.luau's own look, as the hands hold it
--   melee:bat    the Baseball Bat, from Config.Melee.BatLook (the bat CloseCombat puts in the hand)
--   fists        your fists: a courier's glove clenched, its red cuff
--   item:<id>    a consumable (Config.Items): a medkit, an energy drink, a molotov, a repair kit, nitro, a landmine, a
--                jerry can, each built here
--   kit:<id>     a bag (shared/KitArt.luau's art, the one on your character) or a vest (KitArt's Kevlar and heavy
--                armour; the Courier Vest's pieces as server/CharacterArt/Geometry.luau hivis draws them) on a dim form
--   cargo:<look> a piece of cargo (shared/CargoLooks.luau: the very model the server builds in the world; a horse on
--                the lead drawn here, server/Animals.luau's live one is server-only)
-- Builders here make anchored, inert parts; nothing runs per frame. The camera's framing is pure maths (frame).
--
--   ItemLooks.key(kind, id)            "kind:id" ("fists" without an id)
--   ItemLooks.parse(key)               its kind and id
--   ItemLooks.all()                    every key the inventory can show (Config's guns, items, kit and cargo looks, the
--                                      fists): tests/itemlooks_test.luau builds each one
--   ItemLooks.has(key)                 whether that thing has a look of its own (an unknown key: no)
--   ItemLooks.build(key)               its model (errors on an unknown key: client/ItemModel.luau pcalls it); turned
--                                      to face the camera (Turn), at most Config.ItemModel.MaxParts parts
--   ItemLooks.bounds(model)            its parts' box: the low and the high corner ({ x, y, z })
--   ItemLooks.frame(lo, hi, aspect, spin)  the camera for that box: where it looks from and at ({ x, y, z } each) at
--                                      Config.ItemModel's 3/4 angle; `spin`: room for the box to turn round
--   ItemLooks.Finish                   the bags' and vests' finishes (server/ModelArt/Builder.luau's colours and
--                                      materials: tests/run_tests.py checks they agree)

local Config = require(script.Parent.Config)

local ItemLooks = {}

type V = { number }

local LOOK = Config.ItemModel

-- The turn (degrees about Y) each kind is drawn at, so its long side lies across the 3/4 view: a gun's barrel to the
-- right, a bag's broad printed side toward the camera, the bat across.
ItemLooks.Turn = { gun = -125, melee = 0, kit = 0, bag = 55, item = 0, cargo = 0, fists = -20 } :: { [string]: number }

-- server/ModelArt/Builder.luau's finishes the bags and vests use (KitArt's `finish`).
ItemLooks.Finish = {
	charcoal = { color = { 35, 40, 43 }, material = "Metal" },
	cloth = { color = { 44, 49, 48 }, material = "Fabric" },
	red = { color = { 153, 49, 43 }, material = "SmoothPlastic" },
	steel = { color = { 166, 176, 174 }, material = "Metal" },
	worn = { color = { 110, 118, 110 }, material = "Metal" },
	sole = { color = { 23, 27, 29 }, material = "Rubber" },
	foam = { color = { 111, 119, 119 }, material = "SmoothPlastic" },
	parcel = { color = { 147, 120, 84 }, material = "SmoothPlastic" },
	reflector = { color = { 188, 200, 192 }, material = "SmoothPlastic" },
	canvas = { color = { 201, 186, 150 }, material = "Fabric" },
	nylon = { color = { 58, 104, 156 }, material = "Fabric" },
	olive = { color = { 92, 122, 62 }, material = "Fabric" },
	bagplastic = { color = { 214, 230, 238 }, material = "SmoothPlastic" },
} :: { [string]: { color: V, material: string } }

-- ── Keys ────────────────────────────────────────────────────────────────────

function ItemLooks.key(kind: string, id: string?): string
	return if id and id ~= "" then `{kind}:{id}` else kind
end

function ItemLooks.parse(key: string): (string, string)
	local kind, id = string.match(key, "^(%w+):(.+)$")
	if kind and id then
		return kind, id
	end
	return key, ""
end

-- Every cargo look the game makes pieces of: the special jobs' kinds, the light looks, the storefronts' and the
-- tutorial's.
local function cargoLooks(): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	local function add(look: any)
		if type(look) == "string" and not seen[look] then
			seen[look] = true
			table.insert(out, look)
		end
	end
	for _, kind in Config.Cargo.Kinds do
		add(kind.look)
	end
	for look in Config.Cargo.LightLooks do
		add(look)
	end
	local jobs = (Config :: any).Jobs
	if type(jobs) == "table" then
		if type(jobs.Businesses) == "table" then
			for _, business in jobs.Businesses do
				if type(business) == "table" then
					add(business.look)
				end
			end
		end
		if type(jobs.TutorialCargo) == "table" then
			add(jobs.TutorialCargo.look)
		end
	end
	table.sort(out)
	return out
end

function ItemLooks.all(): { string }
	local out: { string } = { "fists", "melee:bat" }
	for _, def in Config.Weapons do
		table.insert(out, `gun:{def.id}`)
	end
	for _, def in Config.Items do
		table.insert(out, `item:{def.id}`)
	end
	for _, def in Config.Kit do
		if not def.melee then
			table.insert(out, `kit:{def.id}`)
		end
	end
	for _, look in cargoLooks() do
		table.insert(out, `cargo:{look}`)
	end
	return out
end

-- ── The parts ───────────────────────────────────────────────────────────────

local function rgb(c: V): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local MATERIAL: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Fabric = Enum.Material.Fabric,
	Rubber = Enum.Material.Rubber,
	Glass = Enum.Material.Glass,
	Neon = Enum.Material.Neon,
	Wood = Enum.Material.Wood,
	Leather = Enum.Material.Leather,
}

-- A part of a look: `shape` "Block" (nil), "Cylinder" (its axis along X; `up` stands it up) or "Ball"; `turn` in
-- degrees; `base` a frame the piece sits in (the bat's tilt).
type Spec = { shape: string?, up: boolean?, turn: V?, material: string?, alpha: number?, base: CFrame? }

local function part(model: Model, name: string, size: V, at: V, color: V, spec: Spec?): Part
	local s: Spec = spec or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(size[1], size[2], size[3])
	if s.shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif s.shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	end
	local cf = CFrame.new(at[1], at[2], at[3])
	if s.turn then
		cf = cf * CFrame.Angles(math.rad(s.turn[1]), math.rad(s.turn[2]), math.rad(s.turn[3]))
	end
	if s.up then
		cf = cf * CFrame.Angles(0, 0, math.rad(90)) -- (a cylinder standing up)
	end
	p.CFrame = if s.base then s.base * cf else cf
	p.Color = rgb(color)
	p.Material = MATERIAL[s.material or "SmoothPlastic"] or Enum.Material.SmoothPlastic
	p.Transparency = s.alpha or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = model
	return p
end

-- ── The consumables (Config.Items) ──────────────────────────────────────────

local WHITE = { 236, 238, 234 }
local STEEL = { 170, 176, 180 }
local BLACK = { 40, 42, 46 }
local RED = { 206, 40, 40 }

local ITEMS: { [string]: (Model) -> () } = {}

-- A white first-aid case: the red cross on its front, the lid's seam, two latches, a carry handle.
function ITEMS.medkit(m: Model)
	part(m, "Case", { 2.0, 1.3, 0.7 }, { 0, 0.65, 0 }, WHITE)
	part(m, "Seam", { 2.04, 0.1, 0.74 }, { 0, 0.95, 0 }, { 168, 172, 176 })
	part(m, "CrossH", { 0.84, 0.26, 0.04 }, { 0, 0.58, -0.37 }, RED)
	part(m, "CrossV", { 0.26, 0.84, 0.04 }, { 0, 0.58, -0.37 }, RED)
	part(m, "Handle", { 0.8, 0.12, 0.16 }, { 0, 1.54, 0 }, BLACK)
	for _, x in { -0.36, 0.36 } do
		part(m, "Post", { 0.12, 0.28, 0.14 }, { x, 1.4, 0 }, BLACK)
		part(m, "Latch", { 0.16, 0.2, 0.06 }, { x * 2, 0.95, -0.38 }, STEEL, { material = "Metal" })
	end
end

-- A tall black can with a lime band and a yellow bolt, its silver rims and tab.
function ITEMS.energy(m: Model)
	part(m, "Can", { 1.5, 0.82, 0.82 }, { 0, 0.75, 0 }, { 28, 30, 32 }, { shape = "Cylinder", up = true })
	part(m, "Band", { 0.62, 0.84, 0.84 }, { 0, 0.82, 0 }, { 140, 230, 60 }, { shape = "Cylinder", up = true })
	part(m, "BoltTop", { 0.12, 0.36, 0.04 }, { 0.03, 0.96, -0.43 }, { 250, 220, 60 }, { turn = { 0, 0, -28 } })
	part(m, "BoltLow", { 0.12, 0.36, 0.04 }, { -0.03, 0.7, -0.43 }, { 250, 220, 60 }, { turn = { 0, 0, -28 } })
	part(m, "Top", { 0.06, 0.74, 0.74 }, { 0, 1.53, 0 }, STEEL, { shape = "Cylinder", up = true, material = "Metal" })
	part(m, "Bottom", { 0.06, 0.74, 0.74 }, { 0, 0.03, 0 }, STEEL, { shape = "Cylinder", up = true, material = "Metal" })
	part(m, "Tab", { 0.18, 0.03, 0.26 }, { 0, 1.57, 0.08 }, STEEL, { material = "Metal" })
end

-- A green glass bottle of fuel, a rag stuffed in its neck, the rag alight.
function ITEMS.molotov(m: Model)
	local glass = { 96, 124, 70 }
	part(m, "Bottle", { 1.1, 0.72, 0.72 }, { 0, 0.55, 0 }, glass, { shape = "Cylinder", up = true, material = "Glass", alpha = 0.35 })
	part(m, "Fuel", { 0.8, 0.62, 0.62 }, { 0, 0.44, 0 }, { 226, 128, 40 }, { shape = "Cylinder", up = true, alpha = 0.15 })
	part(m, "Shoulder", { 0.72, 0.72, 0.72 }, { 0, 1.1, 0 }, glass, { shape = "Ball", material = "Glass", alpha = 0.35 })
	part(m, "Neck", { 0.6, 0.28, 0.28 }, { 0, 1.5, 0 }, glass, { shape = "Cylinder", up = true, material = "Glass", alpha = 0.3 })
	part(m, "Knot", { 0.34, 0.14, 0.32 }, { 0, 1.78, 0 }, { 200, 186, 150 }, { material = "Fabric" })
	part(m, "Rag", { 0.26, 0.7, 0.2 }, { 0.08, 2.0, 0 }, { 222, 206, 170 }, { turn = { 0, 0, -18 }, material = "Fabric" })
	part(m, "Flame", { 0.46, 0.46, 0.46 }, { 0.2, 2.42, 0 }, { 255, 140, 30 }, { shape = "Ball", material = "Neon" })
	part(m, "Core", { 0.26, 0.26, 0.26 }, { 0.18, 2.36, -0.12 }, { 255, 222, 90 }, { shape = "Ball", material = "Neon" })
end

-- A red metal toolbox, its handle and latches, a steel wrench lying on the lid.
function ITEMS.repair(m: Model)
	part(m, "Box", { 2.0, 0.9, 0.9 }, { 0, 0.45, 0 }, { 196, 44, 40 }, { material = "Metal" })
	part(m, "Lid", { 2.06, 0.22, 0.96 }, { 0, 1.0, 0 }, { 150, 32, 30 }, { material = "Metal" })
	part(m, "Handle", { 0.9, 0.12, 0.16 }, { 0, 1.42, 0.18 }, BLACK)
	for _, x in { -0.4, 0.4 } do
		part(m, "Post", { 0.12, 0.3, 0.14 }, { x, 1.26, 0.18 }, BLACK)
		part(m, "Latch", { 0.18, 0.22, 0.06 }, { x * 1.5, 0.86, -0.47 }, STEEL, { material = "Metal" })
	end
	part(m, "Wrench", { 1.1, 0.07, 0.18 }, { -0.1, 1.15, -0.22 }, STEEL, { turn = { 0, 20, 0 }, material = "Metal" })
	part(m, "Jaw", { 0.07, 0.38, 0.38 }, { 0.42, 1.15, -0.41 }, STEEL, { shape = "Cylinder", up = true, material = "Metal" })
	part(m, "Ring", { 0.07, 0.26, 0.26 }, { -0.62, 1.15, -0.03 }, STEEL, { shape = "Cylinder", up = true, material = "Metal" })
end

-- A blue nitrous bottle: a white label with a red stripe, a valve and its nozzle on the dome.
function ITEMS.nitro(m: Model)
	local blue = { 40, 110, 220 }
	part(m, "Bottle", { 2.0, 0.8, 0.8 }, { 0, 1.0, 0 }, blue, { shape = "Cylinder", up = true, material = "Metal" })
	part(m, "Dome", { 0.8, 0.8, 0.8 }, { 0, 2.0, 0 }, blue, { shape = "Ball", material = "Metal" })
	part(m, "Base", { 0.08, 0.82, 0.82 }, { 0, 0.04, 0 }, { 30, 34, 40 }, { shape = "Cylinder", up = true })
	part(m, "Label", { 0.6, 0.82, 0.82 }, { 0, 1.1, 0 }, WHITE, { shape = "Cylinder", up = true })
	part(m, "Stripe", { 0.12, 0.83, 0.83 }, { 0, 1.1, 0 }, RED, { shape = "Cylinder", up = true })
	part(m, "Valve", { 0.3, 0.3, 0.3 }, { 0, 2.48, 0 }, STEEL, { shape = "Cylinder", up = true, material = "Metal" })
	part(m, "Knob", { 0.08, 0.42, 0.42 }, { 0, 2.66, 0 }, BLACK, { shape = "Cylinder", up = true })
	part(m, "Nozzle", { 0.4, 0.14, 0.14 }, { 0.26, 2.48, 0 }, STEEL, { shape = "Cylinder", material = "Metal" })
end

-- An olive anti-vehicle mine: a flat drum, its pressure plate, the fuse's prongs, a red arming light.
function ITEMS.mine(m: Model)
	part(m, "Drum", { 0.45, 2.0, 2.0 }, { 0, 0.225, 0 }, { 84, 96, 58 }, { shape = "Cylinder", up = true, material = "Metal" })
	part(m, "Rim", { 0.08, 2.04, 2.04 }, { 0, 0.45, 0 }, { 62, 70, 44 }, { shape = "Cylinder", up = true, material = "Metal" })
	part(m, "Plate", { 0.12, 0.9, 0.9 }, { 0, 0.53, 0 }, { 108, 118, 80 }, { shape = "Cylinder", up = true, material = "Metal" })
	part(m, "Fuse", { 0.14, 0.3, 0.3 }, { 0, 0.64, 0 }, STEEL, { shape = "Cylinder", up = true, material = "Metal" })
	for n, at in { { 0.08, 0 }, { -0.04, 0.07 }, { -0.04, -0.07 } } do
		part(m, `Prong{n}`, { 0.05, 0.24, 0.05 }, { at[1], 0.82, at[2] }, STEEL, { material = "Metal" })
	end
	part(m, "Light", { 0.16, 0.16, 0.16 }, { 0.55, 0.5, -0.5 }, { 255, 50, 40 }, { shape = "Ball", material = "Neon" })
end

-- A red jerry can: the X pressed into both sides, the three-post handle, the spout and its cap.
function ITEMS.jerrycan(m: Model)
	local red = { 196, 40, 34 }
	local dark = { 150, 28, 24 }
	part(m, "Can", { 1.5, 1.9, 0.7 }, { 0, 0.95, 0 }, red, { material = "Metal" })
	for _, z in { -0.36, 0.36 } do
		part(m, "RibA", { 0.12, 1.9, 0.04 }, { 0, 0.92, z }, dark, { turn = { 0, 0, 36 }, material = "Metal" })
		part(m, "RibB", { 0.12, 1.9, 0.04 }, { 0, 0.92, z }, dark, { turn = { 0, 0, -36 }, material = "Metal" })
	end
	part(m, "Grip", { 1.2, 0.14, 0.18 }, { -0.15, 2.18, 0 }, dark, { material = "Metal" })
	for _, x in { -0.65, -0.15, 0.35 } do
		part(m, "Post", { 0.14, 0.26, 0.16 }, { x, 2.02, 0 }, dark, { material = "Metal" })
	end
	part(m, "Spout", { 0.34, 0.36, 0.36 }, { 0.58, 2.06, 0 }, dark, { shape = "Cylinder", up = true, material = "Metal" })
	part(m, "Cap", { 0.12, 0.42, 0.42 }, { 0.58, 2.28, 0 }, BLACK, { shape = "Cylinder", up = true })
end

-- ── The hands ───────────────────────────────────────────────────────────────

-- Your fists: a right hand clenched in the courier's charcoal glove (knuckles toward the camera), its knuckle pad, the
-- thumb across the fingers, the red cuff with its reflective strip.
local function fists(m: Model)
	local glove = { 46, 50, 56 }
	part(m, "Back", { 1.0, 0.9, 0.75 }, { 0, 0.45, 0.15 }, glove, { material = "Fabric" })
	part(m, "Fingers", { 1.0, 0.62, 0.26 }, { 0, 0.42, -0.33 }, { 58, 62, 70 }, { material = "Fabric" })
	for n, x in { -0.36, -0.12, 0.12, 0.36 } do
		part(m, `Knuckle{n}`, { 0.42, 0.3, 0.3 }, { x, 0.72, -0.24 }, glove, { shape = "Cylinder", turn = { 0, 90, 0 }, material = "Fabric" })
	end
	for n, x in { -0.24, 0, 0.24 } do
		part(m, `Crease{n}`, { 0.03, 0.5, 0.02 }, { x, 0.4, -0.465 }, { 26, 28, 32 })
	end
	part(m, "Pad", { 0.92, 0.14, 0.34 }, { 0, 0.88, -0.1 }, { 30, 32, 36 }, { material = "Rubber" })
	part(m, "Thumb", { 0.62, 0.26, 0.28 }, { -0.16, 0.18, -0.5 }, glove, { turn = { 0, 0, 10 }, material = "Fabric" })
	part(m, "Cuff", { 0.5, 0.96, 0.96 }, { 0, 0.45, 0.78 }, { 188, 39, 37 }, { shape = "Cylinder", turn = { 0, 90, 0 }, material = "Fabric" })
	part(m, "Strip", { 0.08, 0.98, 0.98 }, { 0, 0.45, 0.78 }, { 213, 218, 202 }, { shape = "Cylinder", turn = { 0, 90, 0 } })
end

-- The Baseball Bat (Config.Melee.BatLook: its length, the taped handle's and the barrel's thickness, the wood and the
-- grip's colours): a knob, the handle, the taper, the barrel's rounded end, laid across at a tilt.
local function bat(m: Model)
	local look = Config.Melee.BatLook
	local base = CFrame.Angles(0, math.rad(-35), math.rad(24))
	local grip = look.Length * 0.4
	local taper = look.Length * 0.18
	local barrel = look.Length - grip - taper
	local x = -look.Length / 2
	local function along(name: string, length: number, thick: number, color: V, material: string)
		part(m, name, { length, thick, thick }, { x + length / 2, 0, 0 }, color, { shape = "Cylinder", material = material, base = base })
		x += length
	end
	part(m, "Knob", { 0.08, look.Handle * 1.7, look.Handle * 1.7 }, { x - 0.04, 0, 0 }, look.Grip, { shape = "Cylinder", base = base })
	along("Handle", grip, look.Handle, look.Grip, "SmoothPlastic")
	part(m, "Tape", { 0.06, look.Handle * 1.12, look.Handle * 1.12 }, { x - 0.1, 0, 0 }, { 230, 230, 226 }, { shape = "Cylinder", base = base })
	along("Taper", taper, (look.Handle + look.Barrel) / 2, look.Wood, "Wood")
	along("Barrel", barrel, look.Barrel, look.Wood, "Wood")
	part(m, "End", { look.Barrel, look.Barrel, look.Barrel }, { x, 0, 0 }, look.Wood, { shape = "Ball", material = "Wood", base = base })
	part(m, "Brand", { 0.5, look.Barrel * 1.02, look.Barrel * 1.02 }, { x - barrel / 2, 0, 0 }, { 150, 104, 60 }, { shape = "Cylinder", material = "Wood", base = base })
end

-- ── The kit (bags and vests) ────────────────────────────────────────────────

-- shared/KitArt.luau's pieces (a Builder piece: name, size, at, its target, finish, turn, shape) built at `origins`
-- (the target's place: KitArt.spec's origins, made relative), with the plastic bag's see-through pieces.
local function art(m: Model, pieces: { any }, origins: { [string]: V }, translucent: { [string]: number })
	for _, piece in pieces do
		local finish = ItemLooks.Finish[piece.finish] or ItemLooks.Finish.cloth
		local o = origins[piece.attach] or { 0, 0, 0 }
		local made = Instance.new(if piece.shape == "Wedge" then "WedgePart" else "Part") :: BasePart
		made.Name = piece.name
		made.Size = Vector3.new(piece.size[1], piece.size[2], piece.size[3])
		local turn = piece.turn or { 0, 0, 0 }
		made.CFrame = CFrame.new(o[1] + piece.at[1], o[2] + piece.at[2], o[3] + piece.at[3]) * CFrame.Angles(math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3]))
		if piece.shape == "Cylinder" then
			(made :: Part).Shape = Enum.PartType.Cylinder
		end
		made.Color = rgb(finish.color)
		made.Material = MATERIAL[finish.material] or Enum.Material.SmoothPlastic
		made.Transparency = translucent[piece.name] or 0
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.CastShadow = false
		made.Parent = m
	end
end

-- The Courier Vest (Config.Kit "hivis"): its pieces as server/CharacterArt/Geometry.luau hivis draws them on the
-- nominal torso (server-only art; the same sizes and colours).
local HIVIS_RED = { 188, 39, 37 }
local HIVIS_SILVER = { 213, 218, 202 }
local function hivis(): { any }
	local out: { any } = {}
	local function add(name: string, size: V, at: V, color: V, turn: V?)
		table.insert(out, { name = name, size = size, at = at, color = color, turn = turn })
	end
	for _, side in { -1, 1 } do
		local suffix = if side < 0 then "L" else "R"
		add("Vest" .. suffix, { 0.83, 1.44, 0.07 }, { side * 0.535, -0.04, -0.535 }, HIVIS_RED)
		add("Reflector" .. suffix, { 0.83, 0.17, 0.025 }, { side * 0.535, -0.22, -0.581 }, HIVIS_SILVER)
		add("Collar" .. suffix, { 0.25, 0.49, 0.06 }, { side * 0.29, 0.46, -0.585 }, HIVIS_RED, { 0, 0, side * -22 })
		add("Pocket" .. suffix, { 0.48, 0.3, 0.03 }, { side * 0.55, -0.53, -0.585 }, { 155, 32, 31 })
	end
	add("VestBack", { 1.96, 1.45, 0.06 }, { 0, -0.04, 0.53 }, HIVIS_RED)
	add("BackReflector", { 1.88, 0.17, 0.025 }, { 0, -0.22, 0.578 }, HIVIS_SILVER)
	add("DispatchBadge", { 0.33, 0.2, 0.025 }, { -0.55, 0.21, -0.581 }, HIVIS_SILVER)
	return out
end

-- A dim display form under a vest (the torso it is worn on; `arms` the upper arms a heavy vest's guards sit on).
local FORM = { 128, 132, 138 }
local function form(m: Model, arms: boolean)
	part(m, "Form", { 1.84, 1.36, 0.96 }, { 0, -0.06, 0 }, FORM)
	part(m, "FormNeck", { 0.5, 0.3, 0.5 }, { 0, 0.72, 0 }, FORM)
	if arms then
		for _, x in { -1.5, 1.5 } do
			part(m, "FormArm", { 0.86, 1.0, 0.86 }, { x, -0.05, 0 }, FORM)
		end
	end
end

local function kit(m: Model, id: string)
	local KitArt = require(script.Parent.KitArt) :: any
	if KitArt.bags[id] then
		art(m, KitArt.pieces(id), { BagPivot = { 0, 0, 0 } }, KitArt.translucent)
	elseif id == "kevlar" or id == "heavy" then
		form(m, id == "heavy")
		art(m, KitArt.pieces(id), { UpperTorso = { 0, 0, 0 }, LeftUpperArm = { -1.5, 0.05, 0 }, RightUpperArm = { 1.5, 0.05, 0 } }, {})
	elseif id == "hivis" then
		form(m, false)
		for _, piece in hivis() do
			part(m, piece.name, piece.size, piece.at, piece.color, { turn = piece.turn, material = if string.match(piece.name, "^Vest") then "Fabric" else nil })
		end
	elseif id == Config.Melee.BatKit then
		bat(m)
	else
		error(`ItemLooks: no look for kit {id}`)
	end
end

-- ── The cargo the server does not build as a piece ──────────────────────────

-- A horse on the lead (Config.Cargo.Kinds horse: server/Animals.luau builds the live one, jointed, server-only): a bay
-- in the same proportions and colours, a red halter, standing.
local function horse(m: Model)
	local coat, hair, dark = { 118, 72, 42 }, { 34, 26, 22 }, { 89, 54, 32 }
	local neck = { -40, 0, 0 }
	part(m, "Body", { 4.4, 2.5, 2.5 }, { 0, 3.95, 0 }, coat, { shape = "Cylinder", turn = { 0, 90, 0 } })
	part(m, "Chest", { 2.6, 2.6, 2.6 }, { 0, 4.02, -2.1 }, coat, { shape = "Ball" })
	part(m, "Rump", { 2.75, 2.75, 2.75 }, { 0, 4.1, 2.05 }, coat, { shape = "Ball" })
	part(m, "Neck", { 1.0, 3.2, 1.55 }, { 0, 5.6, -3.39 }, coat, { turn = neck })
	part(m, "Mane", { 0.3, 3.0, 0.5 }, { 0, 5.95, -2.9 }, hair, { turn = neck, material = "Fabric" })
	part(m, "Head", { 0.92, 0.98, 1.45 }, { 0, 6.32, -4.67 }, coat, { turn = neck })
	part(m, "Nose", { 0.78, 0.78, 0.85 }, { 0, 5.66, -5.3 }, dark, { turn = neck })
	part(m, "Halter", { 0.86, 0.86, 0.16 }, { 0, 5.75, -5.05 }, { 170, 40, 36 }, { turn = neck, material = "Fabric" })
	for _, x in { -0.27, 0.27 } do
		part(m, "Ear", { 0.18, 0.58, 0.3 }, { x, 7.19, -4.75 }, coat, { turn = neck })
	end
	part(m, "Tail", { 0.42, 1.5, 0.42 }, { 0, 4.38, 3.5 }, hair, { turn = { -28, 0, 0 }, material = "Fabric" })
	part(m, "TailHair", { 0.6, 1.9, 0.55 }, { 0, 3.17, 4.2 }, hair, { turn = { -28, 0, 0 }, material = "Fabric" })
	for _, leg in { { -0.62, -2.0 }, { 0.62, -2.0 }, { -0.66, 2.0 }, { 0.66, 2.0 } } do
		local x, z = leg[1], leg[2]
		local front = z < 0
		part(m, "Leg", if front then { 0.62, 1.7, 0.78 } else { 0.7, 1.7, 1.0 }, { x, 2.65, z }, coat)
		part(m, "Cannon", { 0.38, 1.5, 0.42 }, { x, 1.15, z }, dark)
		part(m, "Hoof", { 0.52, 0.42, 0.6 }, { x, 0.21, z - 0.05 }, { 40, 34, 30 })
	end
end

-- The cargo looks drawn here (no piece of CargoLooks: a crate would stand in).
ItemLooks.Cargo = { horse = horse } :: { [string]: (Model) -> () }

-- ── Every look ──────────────────────────────────────────────────────────────

local KIT_LOOKS: { [string]: boolean } = { hivis = true, kevlar = true, heavy = true }

function ItemLooks.has(key: string): boolean
	local kind, id = ItemLooks.parse(key)
	if kind == "fists" or (kind == "melee" and id == "bat") then
		return true
	elseif kind == "item" then
		return ITEMS[id] ~= nil
	elseif kind == "gun" then
		return (require(script.Parent.GunModels) :: any).has(id)
	elseif kind == "kit" then
		local KitArt = require(script.Parent.KitArt) :: any
		return KIT_LOOKS[id] == true or KitArt.bags[id] == true or id == Config.Melee.BatKit
	elseif kind == "cargo" then
		return ItemLooks.Cargo[id] ~= nil or (require(script.Parent.CargoLooks) :: any).Looks[id] == true
	end
	return false
end

-- Each part turned `degrees` about Y round the origin.
local function turn(m: Model, degrees: number)
	if degrees == 0 then
		return
	end
	local spin = CFrame.Angles(0, math.rad(degrees), 0)
	for _, obj in m:GetDescendants() do
		if obj:IsA("BasePart") then
			obj.CFrame = spin * obj.CFrame
		end
	end
end

function ItemLooks.build(key: string): Model
	local kind, id = ItemLooks.parse(key)
	local m: Model
	local facing = ItemLooks.Turn[kind] or 0
	if kind == "gun" then
		m = (require(script.Parent.GunModels) :: any).display(id)
	elseif kind == "cargo" and not ItemLooks.Cargo[id] then
		m = (require(script.Parent.CargoLooks) :: any).build(id, 0)
	elseif kind == "cargo" then
		m = Instance.new("Model")
		ItemLooks.Cargo[id](m)
	else
		m = Instance.new("Model")
		if kind == "fists" then
			fists(m)
		elseif kind == "melee" and id == "bat" then
			bat(m)
		elseif kind == "item" then
			local make = ITEMS[id]
			if not make then
				error(`ItemLooks: no look for item {id}`)
			end
			make(m)
		elseif kind == "kit" then
			kit(m, id)
			if ((require(script.Parent.KitArt) :: any).bags[id]) then
				facing = ItemLooks.Turn.bag
			end
		else
			error(`ItemLooks: unknown thing {key}`)
		end
	end
	m.Name = "ItemLook"
	m:SetAttribute("Look", key)
	turn(m, facing)
	return m
end

-- ── The camera ──────────────────────────────────────────────────────────────

function ItemLooks.bounds(m: Model): (V, V)
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, obj in m:GetDescendants() do
		if obj:IsA("BasePart") then
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = obj.CFrame:GetComponents()
			local h = obj.Size / 2
			local ex = math.abs(r00) * h.X + math.abs(r01) * h.Y + math.abs(r02) * h.Z
			local ey = math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z
			local ez = math.abs(r20) * h.X + math.abs(r21) * h.Y + math.abs(r22) * h.Z
			lo = { math.min(lo[1], x - ex), math.min(lo[2], y - ey), math.min(lo[3], z - ez) }
			hi = { math.max(hi[1], x + ex), math.max(hi[2], y + ey), math.max(hi[3], z + ez) }
		end
	end
	if lo[1] > hi[1] then
		return { -0.5, -0.5, -0.5 }, { 0.5, 0.5, 0.5 }
	end
	return lo, hi
end

-- The camera on that box at Config.ItemModel's angle (Yaw from the front toward the right, Pitch down), far enough
-- that the box fills Fill of the frame (`aspect`: its width over its height). `spin`: the box's footprint as the
-- circle round it, so it still fits as it turns. Returns the eye and the box's middle.
function ItemLooks.frame(lo: V, hi: V, aspect: number, spin: boolean?): (V, V)
	local c = { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }
	local hx, hy, hz = (hi[1] - lo[1]) / 2, (hi[2] - lo[2]) / 2, (hi[3] - lo[3]) / 2
	if spin then
		local r = math.sqrt(hx * hx + hz * hz)
		hx, hz = r, r
	end
	local yaw, pitch = math.rad(LOOK.Yaw), math.rad(LOOK.Pitch)
	local d = { math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch) } -- toward the eye
	-- the view's right (d × up, flat) and up (right × d)
	local rl = math.sqrt(d[3] * d[3] + d[1] * d[1])
	local right = { -d[3] / rl, 0, d[1] / rl }
	local up = { right[2] * d[3] - right[3] * d[2], right[3] * d[1] - right[1] * d[3], right[1] * d[2] - right[2] * d[1] }
	local function extent(a: V): number
		return math.abs(a[1]) * hx + math.abs(a[2]) * hy + math.abs(a[3]) * hz
	end
	local t = math.tan(math.rad(LOOK.Fov / 2))
	local fit = math.max(extent(up) / t, extent(right) / (t * math.max(0.2, aspect)))
	local distance = fit / LOOK.Fill + extent(d)
	return { c[1] + d[1] * distance, c[2] + d[2] * distance, c[3] + d[3] * distance }, c
end

return ItemLooks
