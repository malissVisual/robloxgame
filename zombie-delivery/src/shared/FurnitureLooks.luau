--!strict
-- 7.0 prototype, the moving (design/rework/NAVRH.md): every piece of furniture and household thing a moving job
-- carries out of a house: its catalogue entry and its look. Works on the server and the client (no services, nothing
-- per frame). shared/HouseLayout.luau places the pieces in a house, server/HouseInterior.luau builds them there.
--
--   FurnitureLooks.Items[id]          the catalogue: name, icon (an emoji), size (the bounding box in studs: X wide,
--                                     Y tall, Z deep; the front faces -Z), class ("hand": one hand; "both": two hands,
--                                     slower; "pair": two players, or one dragging it), weight (1..10), value ($),
--                                     fragile, room (the room kind it belongs in) and sentimental (the client's ★ ones)
--   FurnitureLooks.Order              every id in catalogue order (Items is a dictionary: iterate this for a fixed order)
--   FurnitureLooks.Rooms              the room kinds, in house order
--   FurnitureLooks.build(id, variant?)  the piece as a Model built at the origin: its PrimaryPart "Root" is an
--                                     invisible box of exactly `size` (Transparency 1, the only part that collides),
--                                     the box's middle its pivot (the bottom at Root.Position.Y - size.Y / 2); every
--                                     other part is welded to Root (WeldConstraint) and is CanCollide / CanQuery /
--                                     CanTouch false and Massless. Attributes FurnitureId, Class, Weight, Fragile.
--                                     Unanchored as built (the caller anchors Root when it places it; the welds hold
--                                     the rest). `variant` (a whole number, default 1) picks its colours. An unknown id
--                                     is a moving box (FurnitureId still the id asked for).
--   FurnitureLooks.grips(id)          where hands hold it, in Root's space (points on the box at hand height): a "pair"
--                                     piece's two ends of its long side, a "both" piece's two sides, a "hand" piece's
--                                     front
--   FurnitureLooks.parts(id)          how many parts its model has (Root included)

local Config = require(script.Parent.Config)

local Tuning = Config.Furniture

export type Class = "hand" | "both" | "pair"
export type ItemDef = {
	id: string,
	name: string,
	icon: string,
	size: Vector3,
	class: Class,
	weight: number,
	value: number,
	fragile: boolean,
	room: string,
	sentimental: boolean,
}

local FurnitureLooks = {}

FurnitureLooks.Rooms = { "hall", "living", "kitchen", "bedroom", "kids", "bath", "garage" }

local Items: { [string]: ItemDef } = {}
local Order: { string } = {}

local function item(id: string, name: string, icon: string, x: number, y: number, z: number, class: Class, weight: number, value: number, fragile: boolean, room: string, sentimental: boolean?)
	Items[id] = {
		id = id,
		name = name,
		icon = icon,
		size = Vector3.new(x, y, z),
		class = class,
		weight = weight,
		value = value,
		fragile = fragile,
		room = room,
		sentimental = sentimental == true,
	}
	table.insert(Order, id)
end

-- The catalogue. A "pair" piece's narrow side (min of X and Z) stays under Config.Furniture.Door: it goes through every
-- doorway carried end first (tests/furniture_test.luau).
--   id                  name                     icon  X    Y    Z    class   wt  value fragile room       ★
item("sofa", "Sofa", "🛋️", 7.2, 3.4, 3.2, "pair", 8, 350, false, "living")
item("armchair", "Armchair", "💺", 3.4, 3.4, 3.2, "both", 5, 140, false, "living")
item("tv", "Old TV", "📺", 3.4, 3.9, 2.4, "both", 4, 300, true, "living")
item("coffee_table", "Coffee Table", "☕", 4.2, 1.85, 2.4, "both", 4, 90, false, "living")
item("floor_lamp", "Floor Lamp", "💡", 1.4, 5.2, 1.4, "hand", 2, 45, true, "living")
item("bookshelf", "Bookshelf", "📚", 4.2, 6.6, 1.6, "pair", 7, 160, false, "living")
item("painting", "Painting", "🖼️", 3.0, 2.4, 0.4, "hand", 1, 250, true, "living")
item("plant", "Potted Plant", "🪴", 1.8, 3.6, 1.8, "hand", 2, 30, false, "living")
item("piano", "Upright Piano", "🎹", 5.2, 4.6, 2.2, "pair", 10, 1200, false, "living")
item("grandfather_clock", "Grandfather Clock", "🕰️", 2.0, 7.2, 1.4, "pair", 7, 900, true, "living", true)
item("record_player", "Old Record Player", "🎶", 2.3, 4.8, 2.0, "both", 4, 600, true, "living", true)
item("fridge", "Fridge", "🧊", 3.0, 6.4, 2.8, "pair", 9, 500, false, "kitchen")
item("microwave", "Microwave", "🍲", 2.2, 1.3, 1.5, "both", 3, 80, true, "kitchen")
item("dining_table", "Dining Table", "🍽️", 6.0, 3.3, 3.8, "pair", 6, 220, false, "kitchen")
item("dining_chair", "Chair", "🪑", 1.8, 3.8, 1.8, "both", 2, 40, false, "kitchen")
item("dishes_box", "Box of Dishes", "🥣", 2.0, 2.0, 2.0, "hand", 2, 70, true, "kitchen")
item("radio", "Kitchen Radio", "📻", 1.6, 1.1, 0.8, "hand", 1, 60, false, "kitchen")
item("bed", "Double Bed", "🛏️", 5.4, 3.6, 7.4, "pair", 8, 450, false, "bedroom")
item("wardrobe", "Wardrobe", "🚪", 4.4, 7.0, 2.2, "pair", 9, 300, false, "bedroom")
item("nightstand", "Nightstand", "🗄️", 1.8, 2.4, 1.6, "both", 3, 70, false, "bedroom")
item("dresser", "Dresser", "🧺", 3.8, 3.2, 1.8, "both", 6, 180, false, "bedroom")
item("mirror", "Standing Mirror", "🪞", 1.8, 5.0, 1.0, "both", 3, 120, true, "bedroom")
item("photo_album", "Family Photos", "📔", 1.8, 1.6, 1.4, "hand", 1, 500, false, "bedroom", true)
item("kids_bed", "Kid's Bed", "🛏️", 3.6, 3.0, 6.2, "pair", 5, 200, false, "kids")
item("rocking_horse", "Rocking Horse", "🐴", 3.8, 3.2, 1.4, "both", 3, 450, true, "kids", true)
item("toy_box", "Toy Chest", "🧸", 3.0, 2.4, 1.8, "both", 4, 60, false, "kids")
item("desk", "Kid's Desk", "✏️", 3.6, 3.2, 2.0, "both", 4, 90, false, "kids")
item("guitar", "Guitar", "🎸", 1.5, 4.0, 0.8, "both", 2, 220, true, "kids")
item("washing_machine", "Washing Machine", "🫧", 2.8, 3.4, 2.8, "pair", 9, 380, false, "bath")
item("laundry_basket", "Laundry Basket", "🧺", 1.8, 1.6, 1.4, "hand", 1, 15, false, "bath")
item("coat_rack", "Coat Rack", "🧥", 1.5, 5.6, 1.5, "hand", 2, 35, false, "hall")
item("shoe_cabinet", "Shoe Cabinet", "👟", 3.2, 2.9, 1.4, "both", 3, 60, false, "hall")
item("bicycle", "Bicycle", "🚲", 5.4, 3.1, 1.2, "both", 3, 180, false, "garage")
item("toolbox", "Toolbox", "🧰", 2.0, 1.25, 1.0, "hand", 3, 90, false, "garage")
item("lawn_mower", "Lawn Mower", "🌱", 2.2, 3.2, 4.2, "both", 5, 150, false, "garage")
item("box", "Moving Box", "📦", 2.0, 1.8, 2.0, "hand", 2, 40, false, "garage")

FurnitureLooks.Items = Items
FurnitureLooks.Order = Order

-- ── Drawing ─────────────────────────────────────────────────────────────────

local SMOOTH = Enum.Material.SmoothPlastic
local WOOD = Enum.Material.Wood
local PLANKS = Enum.Material.WoodPlanks
local FABRIC = Enum.Material.Fabric
local METAL = Enum.Material.Metal
local GLASS = Enum.Material.Glass
local NEON = Enum.Material.Neon
local CARD = Enum.Material.Cardboard
local LEATHER = Enum.Material.Leather
local RUBBER = Enum.Material.Rubber

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local function shade(c: Color3, t: number): Color3
	return c:Lerp(BLACK, t)
end
local function tint(c: Color3, t: number): Color3
	return c:Lerp(WHITE, t)
end

-- The house's palette (the game's warm, slightly worn look): upholstery, woods, painted kids' things, accents.
local FABRICS = { rgb(54, 124, 128), rgb(206, 160, 58), rgb(168, 70, 56), rgb(70, 92, 140), rgb(128, 150, 112), rgb(132, 130, 138), rgb(196, 120, 130) }
local WOODS = { rgb(176, 128, 82), rgb(122, 82, 54), rgb(208, 170, 120), rgb(96, 64, 44) }
local PAINTS = { rgb(120, 170, 210), rgb(236, 150, 160), rgb(150, 200, 140), rgb(244, 204, 96), rgb(186, 150, 214) }
local ACCENTS = { rgb(236, 196, 70), rgb(226, 110, 80), rgb(110, 170, 220), rgb(240, 236, 226), rgb(180, 120, 190) }
local BOOKS = { rgb(170, 52, 48), rgb(52, 86, 140), rgb(60, 120, 76), rgb(214, 170, 60), rgb(120, 70, 120), rgb(222, 218, 200), rgb(46, 46, 52), rgb(200, 110, 60) }
local APPLIANCES = { rgb(238, 238, 234), rgb(168, 214, 196), rgb(232, 226, 206), rgb(196, 70, 60) }
local BRASS = rgb(204, 164, 72)
local STEEL = rgb(170, 176, 180)
local DARK = rgb(36, 36, 40)
local CREAM = rgb(244, 238, 222)
local CARDBOARD = rgb(196, 158, 108)
local TAPE = rgb(222, 200, 160)
local SKIN_GLASS = rgb(40, 52, 62)

-- One piece being drawn: the model, its Root, the frame its parts are given in (the bottom centre of the box at the
-- origin, y up from the floor, the front -Z) and its colour pick.
type Ctx = { model: Model, root: Part, base: CFrame, v: number }

local function pick<T>(list: { T }, v: number, salt: number?): T
	return list[(v + (salt or 0) - 1) % #list + 1]
end

local function finish(ctx: Ctx, p: BasePart, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): BasePart
	p.Name = name
	p.Size = size
	p.CFrame = ctx.base * cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = size.X * size.Y * size.Z > 1.5 -- the small bits cast none
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = ctx.root
	weld.Part1 = p
	weld.Parent = p
	p.Parent = ctx.model
	return p
end

-- A block `sx` × `sy` × `sz` centred at (x, y, z) of the piece's frame, turned about its own centre by `turn`.
local function box(ctx: Ctx, name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, material: Enum.Material?, turn: CFrame?): BasePart
	local cf = CFrame.new(x, y, z)
	if turn then
		cf *= turn
	end
	return finish(ctx, Instance.new("Part"), name, Vector3.new(sx, sy, sz), cf, color, material or SMOOTH)
end

-- A cylinder `length` long, `diameter` across, its axis along `axis` ("x", "y" standing up, "z" a disc facing the front).
local function cyl(ctx: Ctx, name: string, length: number, diameter: number, x: number, y: number, z: number, axis: string, color: Color3, material: Enum.Material?, turn: CFrame?): BasePart
	local cf = CFrame.new(x, y, z)
	if turn then
		cf *= turn
	end
	if axis == "y" then
		cf *= CFrame.Angles(0, 0, math.pi / 2)
	elseif axis == "z" then
		cf *= CFrame.Angles(0, math.pi / 2, 0)
	end
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	return finish(ctx, p, name, Vector3.new(length, diameter, diameter), cf, color, material or SMOOTH)
end

local function ball(ctx: Ctx, name: string, diameter: number, x: number, y: number, z: number, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	return finish(ctx, p, name, Vector3.new(diameter, diameter, diameter), CFrame.new(x, y, z), color, material or SMOOTH)
end

local function wedge(ctx: Ctx, name: string, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: Color3, material: Enum.Material?, turn: CFrame?): BasePart
	local cf = CFrame.new(x, y, z)
	if turn then
		cf *= turn
	end
	return finish(ctx, Instance.new("WedgePart"), name, Vector3.new(sx, sy, sz), cf, color, material or SMOOTH)
end

-- A square rod `thickness` thick from (x1, y1) to (x2, y2), at depth z (a bicycle's tubes, a mower's handle).
local function rod(ctx: Ctx, name: string, x1: number, y1: number, x2: number, y2: number, z: number, thickness: number, color: Color3, material: Enum.Material?): BasePart
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)
	local turn = CFrame.Angles(0, 0, math.atan2(dy, dx))
	return box(ctx, name, length, thickness, thickness, (x1 + x2) / 2, (y1 + y2) / 2, z, color, material, turn)
end

-- Text printed on a face of a part (a label, a stencil on a box).
local function label(part: BasePart, text: string, color: Color3, face: Enum.NormalId, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(0.92, 0.8)
	text_.Position = UDim2.fromScale(0.04, 0.1)
	text_.BackgroundTransparency = 1
	text_.Text = text
	text_.TextScaled = true
	text_.Font = font or Enum.Font.GothamBlack
	text_.TextColor3 = color
	text_.Parent = gui
	gui.Parent = part
end

-- Four legs at (±x, ±z), `height` tall.
local function legs(ctx: Ctx, x: number, z: number, height: number, thick: number, color: Color3, material: Enum.Material?)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(ctx, "Leg", thick, height, thick, sx * x, height / 2, sz * z, color, material or WOOD)
		end
	end
end

local BUILDERS: { [string]: (Ctx) -> () } = {}

-- Living room ------------------------------------------------------------------

BUILDERS.sofa = function(c: Ctx)
	local fabric = pick(FABRICS, c.v)
	local light = tint(fabric, 0.12)
	local dark = shade(fabric, 0.18)
	box(c, "Base", 7.0, 1.0, 3.0, 0, 0.8, 0, dark, FABRIC)
	legs(c, 3.2, 1.2, 0.3, 0.3, pick(WOODS, c.v, 3))
	for _, s in { -1, 1 } do
		box(c, "Arm", 0.8, 1.3, 3.2, s * 3.2, 1.65, 0, fabric, FABRIC)
		box(c, "Cushion", 2.75, 0.6, 2.3, s * 1.4, 1.6, -0.3, light, FABRIC)
		box(c, "BackCushion", 2.7, 1.4, 0.6, s * 1.4, 2.5, 0.55, light, FABRIC)
		box(c, "Pillow", 1.0, 1.0, 0.35, s * 2.25, 2.3, 0.05, pick(ACCENTS, c.v, s), FABRIC, CFrame.Angles(-0.25, 0, s * 0.3))
	end
	box(c, "Back", 5.6, 2.0, 0.8, 0, 2.4, 1.2, fabric, FABRIC)
end

BUILDERS.armchair = function(c: Ctx)
	local fabric = pick(FABRICS, c.v, 2)
	local light = tint(fabric, 0.12)
	box(c, "Base", 3.2, 1.0, 3.0, 0, 0.8, 0, shade(fabric, 0.18), FABRIC)
	legs(c, 1.4, 1.2, 0.3, 0.3, pick(WOODS, c.v, 3))
	for _, s in { -1, 1 } do
		box(c, "Arm", 0.8, 1.4, 3.2, s * 1.3, 1.7, 0, fabric, FABRIC)
		box(c, "Wing", 0.45, 1.1, 1.3, s * 1.28, 2.85, 0.85, shade(fabric, 0.08), FABRIC)
	end
	box(c, "Back", 1.8, 2.0, 0.8, 0, 2.4, 1.2, fabric, FABRIC)
	box(c, "Cushion", 1.8, 0.6, 2.3, 0, 1.6, -0.3, light, FABRIC)
	box(c, "BackCushion", 1.75, 1.4, 0.6, 0, 2.5, 0.55, light, FABRIC)
	box(c, "Pillow", 0.9, 0.9, 0.3, 0, 2.3, 0.1, pick(ACCENTS, c.v), FABRIC, CFrame.Angles(-0.25, 0, 0.2))
end

BUILDERS.tv = function(c: Ctx)
	-- A sixties television on splayed legs: the wooden cabinet, the curved glass, the speaker, the rabbit ears.
	local wood = pick(WOODS, c.v, 1)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			cyl(c, "Leg", 0.95, 0.2, sx * 1.35, 0.47, sz * 0.8, "y", DARK, METAL, CFrame.Angles(sz * 0.12, 0, -sx * 0.12))
		end
	end
	box(c, "Cabinet", 3.4, 2.4, 2.2, 0, 2.1, 0.1, wood, WOOD)
	box(c, "Bezel", 2.4, 1.9, 0.12, -0.35, 2.15, -1.06, rgb(30, 30, 32))
	local glass = box(c, "Screen", 2.1, 1.6, 0.08, -0.35, 2.15, -1.16, SKIN_GLASS, GLASS)
	glass.Reflectance = 0.25
	box(c, "Speaker", 0.7, 1.2, 0.06, 1.2, 2.35, -1.03, rgb(200, 186, 150), FABRIC)
	for n, y in { 1.35, 1.7 } do
		cyl(c, "Knob", 0.12, 0.3, 1.2, y - 0.05 * n, -1.06, "z", rgb(220, 214, 196), METAL)
	end
	ball(c, "AntennaBase", 0.3, 0.4, 3.38, 0.4, DARK, METAL)
	for _, s in { -1, 1 } do
		local tilt = s * 0.55
		box(c, "Antenna", 0.07, 0.55, 0.07, 0.4 - math.sin(tilt) * 0.275, 3.4 + math.cos(tilt) * 0.275, 0.4, STEEL, METAL, CFrame.Angles(0, 0, tilt))
	end
end

BUILDERS.coffee_table = function(c: Ctx)
	local wood = pick(WOODS, c.v, 2)
	box(c, "Top", 4.2, 0.25, 2.4, 0, 1.375, 0, wood, WOOD)
	legs(c, 1.85, 1.0, 1.25, 0.3, shade(wood, 0.15))
	box(c, "Shelf", 3.7, 0.15, 1.9, 0, 0.4, 0, shade(wood, 0.1), WOOD)
	box(c, "Magazine", 1.0, 0.06, 0.75, -1.0, 1.53, -0.3, pick(ACCENTS, c.v, 1), SMOOTH, CFrame.Angles(0, 0.3, 0))
	box(c, "Magazine", 0.9, 0.06, 0.7, -0.85, 1.59, -0.2, pick(BOOKS, c.v, 2), SMOOTH, CFrame.Angles(0, -0.2, 0))
	cyl(c, "Mug", 0.34, 0.32, 1.1, 1.67, 0.3, "y", pick(ACCENTS, c.v, 3))
	box(c, "Book", 0.7, 0.18, 0.9, 0.3, 0.57, 0.1, pick(BOOKS, c.v, 5), SMOOTH)
end

BUILDERS.floor_lamp = function(c: Ctx)
	cyl(c, "Base", 0.2, 1.2, 0, 0.1, 0, "y", DARK, METAL)
	box(c, "Pole", 0.15, 3.95, 0.15, 0, 2.17, 0, BRASS, METAL)
	local shade_ = cyl(c, "Shade", 1.1, 1.4, 0, 4.65, 0, "y", pick({ CREAM, rgb(240, 214, 170), rgb(210, 226, 220) }, c.v), FABRIC)
	shade_.Transparency = 0.1
	ball(c, "Bulb", 0.5, 0, 4.3, 0, rgb(255, 236, 190), NEON)
	cyl(c, "Cap", 0.06, 0.5, 0, 5.17, 0, "y", BRASS, METAL)
end

BUILDERS.bookshelf = function(c: Ctx)
	local wood = pick(WOODS, c.v, 1)
	for _, s in { -1, 1 } do
		box(c, "Side", 0.25, 6.6, 1.6, s * 1.975, 3.3, 0, wood, WOOD)
	end
	box(c, "Top", 3.7, 0.25, 1.6, 0, 6.475, 0, wood, WOOD)
	box(c, "Bottom", 3.7, 0.4, 1.6, 0, 0.2, 0, shade(wood, 0.1), WOOD)
	box(c, "Back", 3.7, 6.0, 0.1, 0, 3.4, 0.74, shade(wood, 0.25), WOOD)
	for _, y in { 1.9, 3.4, 4.9 } do
		box(c, "Shelf", 3.7, 0.2, 1.5, 0, y, -0.05, wood, WOOD)
	end
	-- Books on every level: groups of spines, one leaning, the colours turning with the variant.
	local floors = { 0.4, 2.0, 3.5, 5.0 }
	for level, bottom in floors do
		local room = if level == 4 then 1.35 else 1.4
		local widths: { number } = if level % 2 == 1 then { 1.6, 0.9 } else { 2.1, 0.7 }
		local x = -1.75
		for n, w in widths do
			local h = room * (0.62 + ((level + n + c.v) % 3) * 0.12)
			local color = BOOKS[(level * 3 + n + c.v) % #BOOKS + 1]
			if n == 2 and level % 2 == 0 then
				box(c, "Book", w * 0.45, h, 1.0, x + 0.35, bottom + h / 2 - 0.05, -0.1, color, SMOOTH, CFrame.Angles(0, 0, -0.35))
			else
				box(c, "Books", w, h, 1.1, x + w / 2, bottom + h / 2, -0.1, color, SMOOTH)
			end
			x += w + 0.15
		end
	end
end

BUILDERS.painting = function(c: Ctx)
	local skies = { rgb(120, 170, 220), rgb(236, 170, 110), rgb(150, 120, 190), rgb(140, 200, 210) }
	box(c, "Frame", 3.0, 2.4, 0.2, 0, 1.2, 0, pick({ rgb(200, 160, 62), rgb(110, 76, 48), rgb(40, 40, 44) }, c.v), WOOD)
	box(c, "Canvas", 2.6, 2.0, 0.05, 0, 1.2, -0.12, pick(skies, c.v), SMOOTH)
	box(c, "Field", 2.6, 0.6, 0.04, 0, 0.5, -0.155, rgb(96, 150, 70), SMOOTH)
	wedge(c, "Hill", 0.03, 0.8, 1.2, -0.65, 1.0, -0.16, rgb(70, 120, 60), SMOOTH, CFrame.Angles(0, math.pi / 2, 0))
	wedge(c, "Hill", 0.03, 0.6, 1.0, 0.75, 0.9, -0.16, rgb(84, 136, 66), SMOOTH, CFrame.Angles(0, -math.pi / 2, 0))
	cyl(c, "Sun", 0.03, 0.45, 0.65, 1.7, -0.16, "z", rgb(250, 212, 80))
	box(c, "Strut", 0.3, 2.0, 0.12, 0, 1.0, 0.13, shade(CARDBOARD, 0.2), CARD, CFrame.Angles(-0.04, 0, 0))
	for _, s in { -1, 1 } do
		box(c, "Corner", 0.45, 0.45, 0.36, s * 1.25, 0.225, 0, CARDBOARD, CARD)
	end
end

BUILDERS.plant = function(c: Ctx)
	local pot = pick({ rgb(190, 100, 70), rgb(230, 226, 214), rgb(70, 110, 130) }, c.v)
	cyl(c, "Pot", 1.2, 1.3, 0, 0.6, 0, "y", pot)
	cyl(c, "Rim", 0.2, 1.45, 0, 1.15, 0, "y", shade(pot, 0.1))
	cyl(c, "Soil", 0.05, 1.2, 0, 1.25, 0, "y", rgb(72, 52, 36), Enum.Material.Ground)
	box(c, "Stem", 0.15, 1.1, 0.15, 0, 1.75, 0, rgb(90, 70, 40), WOOD)
	local greens = { rgb(64, 132, 62), rgb(84, 150, 70), rgb(56, 116, 58) }
	ball(c, "Leaves", 1.3, -0.2, 2.45, 0.15, greens[1], Enum.Material.Grass)
	ball(c, "Leaves", 1.2, 0.28, 2.75, -0.2, greens[2], Enum.Material.Grass)
	ball(c, "Leaves", 1.1, -0.1, 3.05, -0.05, greens[3], Enum.Material.Grass)
	ball(c, "Leaves", 0.9, 0.3, 2.2, 0.3, greens[2], Enum.Material.Grass)
end

BUILDERS.piano = function(c: Ctx)
	local body = pick({ rgb(24, 24, 28), rgb(92, 54, 36), rgb(40, 30, 26) }, c.v)
	local case = box(c, "Case", 5.2, 4.6, 1.2, 0, 2.3, 0.5, body, WOOD)
	case.Reflectance = 0.08
	box(c, "Keybed", 5.0, 0.4, 1.0, 0, 2.35, -0.6, body, WOOD)
	box(c, "Keys", 4.6, 0.12, 0.75, 0, 2.61, -0.68, rgb(246, 244, 236), SMOOTH)
	for n = 0, 3 do
		box(c, "BlackKeys", 0.9, 0.1, 0.4, -1.75 + n * 1.17, 2.72, -0.5, rgb(20, 20, 22), SMOOTH)
	end
	box(c, "Fallboard", 4.8, 1.6, 0.12, 0, 3.45, -0.16, shade(body, 0.1), WOOD)
	box(c, "Music", 0.9, 0.65, 0.03, 0.2, 3.5, -0.25, rgb(242, 238, 226), SMOOTH, CFrame.Angles(0.1, 0, 0))
	box(c, "Kneeboard", 4.6, 1.8, 0.1, 0, 1.2, -0.12, shade(body, 0.05), WOOD)
	for _, s in { -1, 1 } do
		box(c, "Post", 0.35, 2.15, 0.35, s * 2.3, 1.075, -0.85, body, WOOD)
	end
	for n = -1, 1 do
		box(c, "Pedal", 0.15, 0.08, 0.4, n * 0.35, 0.3, -0.3, BRASS, METAL)
	end
end

BUILDERS.grandfather_clock = function(c: Ctx)
	local wood = pick({ rgb(110, 58, 38), rgb(122, 82, 54), rgb(80, 52, 36) }, c.v)
	box(c, "Plinth", 2.0, 1.3, 1.4, 0, 0.65, 0, shade(wood, 0.1), WOOD)
	box(c, "Trunk", 1.6, 3.8, 1.1, 0, 3.2, 0.1, wood, WOOD)
	local door = box(c, "Glass", 0.9, 2.6, 0.06, 0, 3.3, -0.47, rgb(200, 220, 230), GLASS)
	door.Transparency = 0.45
	box(c, "Rod", 0.08, 1.8, 0.05, 0, 3.75, -0.38, BRASS, METAL)
	cyl(c, "Bob", 0.06, 0.55, 0, 2.8, -0.38, "z", BRASS, METAL)
	for _, s in { -1, 1 } do
		cyl(c, "Weight", 0.6, 0.2, s * 0.28, 4.0, -0.32, "y", BRASS, METAL)
	end
	box(c, "Hood", 2.0, 1.8, 1.3, 0, 6.0, 0.05, wood, WOOD)
	box(c, "Crown", 1.8, 0.2, 1.2, 0, 7.0, 0.05, shade(wood, 0.1), WOOD)
	ball(c, "Finial", 0.2, 0, 7.1, 0.05, BRASS, METAL)
	cyl(c, "Ring", 0.06, 1.55, 0, 6.0, -0.62, "z", BRASS, METAL)
	cyl(c, "Face", 0.08, 1.35, 0, 6.0, -0.64, "z", CREAM)
	box(c, "Hand", 0.07, 0.45, 0.02, 0.1, 6.15, -0.69, DARK, SMOOTH, CFrame.Angles(0, 0, -0.6))
	box(c, "Hand", 0.05, 0.6, 0.02, -0.12, 6.24, -0.69, DARK, SMOOTH, CFrame.Angles(0, 0, 0.45))
end

BUILDERS.record_player = function(c: Ctx)
	-- A gramophone on its little cabinet: the turntable and a record, the tone arm, the big brass horn.
	local wood = pick(WOODS, c.v, 2)
	legs(c, 0.85, 0.75, 0.35, 0.2, shade(wood, 0.2))
	box(c, "Cabinet", 2.0, 1.9, 1.8, 0, 1.3, 0, wood, WOOD)
	for _, s in { -1, 1 } do
		box(c, "Door", 0.85, 1.5, 0.06, s * 0.46, 1.3, -0.93, shade(wood, 0.12), WOOD)
	end
	box(c, "Deck", 1.6, 0.35, 1.4, 0, 2.425, 0, shade(wood, 0.25), WOOD)
	cyl(c, "Record", 0.06, 1.1, -0.15, 2.63, -0.05, "y", rgb(22, 22, 24))
	cyl(c, "Label", 0.07, 0.35, -0.15, 2.635, -0.05, "y", pick(ACCENTS, c.v, 1))
	box(c, "ToneArm", 0.08, 0.08, 0.75, 0.45, 2.72, 0.05, STEEL, METAL, CFrame.Angles(0, 0.35, 0))
	cyl(c, "Pipe", 0.8, 0.2, 0.4, 2.95, 0.45, "y", BRASS, METAL)
	-- the horn: rings of growing width along an axis tilted up and to the front
	local axis = CFrame.new(0.4, 3.3, 0.45) * CFrame.Angles(-0.6, 0, 0)
	local rings = { { 0.0, 0.3, 0.4 }, { 0.38, 0.6, 0.4 }, { 0.72, 1.0, 0.35 }, { 1.02, 1.5, 0.3 } }
	local function ring(name: string, along: number, diameter: number, length: number, color: Color3)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		finish(c, p, name, Vector3.new(length, diameter, diameter), axis * CFrame.new(0, along, 0) * CFrame.Angles(0, 0, math.pi / 2), color, METAL)
	end
	for n, r in rings do
		ring("Horn", r[1], r[2], r[3], if n == 4 then tint(BRASS, 0.1) else BRASS)
	end
	ring("Mouth", 1.18, 1.3, 0.05, rgb(60, 46, 26))
end

-- Kitchen ------------------------------------------------------------------------

BUILDERS.fridge = function(c: Ctx)
	local enamel = pick(APPLIANCES, c.v)
	box(c, "Body", 3.0, 6.2, 2.5, 0, 3.3, 0.15, enamel, SMOOTH)
	box(c, "Plinth", 2.8, 0.2, 2.4, 0, 0.1, 0.1, rgb(60, 60, 64), SMOOTH)
	box(c, "Freezer", 2.9, 1.9, 0.15, 0, 5.4, -1.18, tint(enamel, 0.05), SMOOTH)
	box(c, "Door", 2.9, 4.1, 0.15, 0, 2.35, -1.18, tint(enamel, 0.05), SMOOTH)
	box(c, "Handle", 0.15, 1.1, 0.12, 1.15, 4.95, -1.32, STEEL, METAL)
	box(c, "Handle", 0.15, 1.6, 0.12, 1.15, 3.5, -1.32, STEEL, METAL)
	-- a kid's drawing and a photo held by magnets
	box(c, "Drawing", 0.75, 0.95, 0.02, -0.55, 3.3, -1.265, rgb(250, 250, 246), SMOOTH, CFrame.Angles(0, 0, 0.06))
	box(c, "Sun", 0.3, 0.3, 0.02, -0.4, 3.55, -1.28, rgb(250, 200, 60), SMOOTH)
	box(c, "House", 0.4, 0.3, 0.02, -0.65, 3.05, -1.28, rgb(220, 80, 70), SMOOTH)
	box(c, "Photo", 0.55, 0.45, 0.02, 0.3, 5.5, -1.265, pick(ACCENTS, c.v, 2), SMOOTH, CFrame.Angles(0, 0, -0.08))
	ball(c, "Magnet", 0.16, -0.55, 3.75, -1.29, rgb(220, 60, 60))
	ball(c, "Magnet", 0.16, 0.3, 5.72, -1.29, rgb(60, 120, 220))
end

BUILDERS.microwave = function(c: Ctx)
	local enamel = pick({ rgb(238, 238, 234), rgb(60, 62, 66), rgb(176, 182, 186) }, c.v)
	box(c, "Body", 2.2, 1.3, 1.4, 0, 0.65, 0.05, enamel, SMOOTH)
	box(c, "DoorFrame", 1.55, 1.15, 0.04, -0.3, 0.65, -0.67, rgb(30, 30, 32), SMOOTH)
	local window = box(c, "Window", 1.25, 0.85, 0.04, -0.3, 0.65, -0.71, rgb(60, 50, 40), GLASS)
	window.Reflectance = 0.2
	box(c, "Panel", 0.5, 1.1, 0.04, 0.8, 0.65, -0.67, rgb(70, 72, 76), SMOOTH)
	box(c, "Display", 0.36, 0.16, 0.03, 0.8, 1.0, -0.7, rgb(120, 230, 140), NEON)
	for n = 0, 1 do
		cyl(c, "Dial", 0.06, 0.26, 0.8, 0.65 - n * 0.35, -0.71, "z", rgb(210, 210, 214), METAL)
	end
	box(c, "Handle", 0.08, 0.9, 0.06, 0.45, 0.65, -0.71, STEEL, METAL)
end

BUILDERS.dining_table = function(c: Ctx)
	local wood = pick(WOODS, c.v, 3)
	box(c, "Top", 6.0, 0.3, 3.8, 0, 2.55, 0, wood, WOOD)
	box(c, "Apron", 5.4, 0.4, 3.2, 0, 2.2, 0, shade(wood, 0.12), WOOD)
	legs(c, 2.7, 1.5, 2.4, 0.35, shade(wood, 0.12))
	box(c, "Runner", 5.0, 0.04, 1.0, 0, 2.72, 0, pick({ rgb(240, 236, 226), rgb(190, 60, 60), rgb(80, 120, 150) }, c.v), FABRIC)
	cyl(c, "Bowl", 0.25, 1.0, 0.4, 2.86, 0, "y", rgb(236, 232, 220))
	ball(c, "Apple", 0.38, 0.25, 3.08, 0.1, rgb(200, 40, 36))
	ball(c, "Orange", 0.38, 0.6, 3.08, -0.05, rgb(240, 150, 40))
	ball(c, "Lime", 0.34, 0.4, 3.1, 0.25, rgb(130, 190, 70))
	cyl(c, "Candle", 0.6, 0.18, -1.2, 3.0, 0, "y", CREAM)
end

BUILDERS.dining_chair = function(c: Ctx)
	local wood = pick(WOODS, c.v, 1)
	box(c, "Seat", 1.8, 0.25, 1.8, 0, 1.575, 0, wood, WOOD)
	box(c, "Cushion", 1.5, 0.15, 1.4, 0, 1.775, -0.1, pick(FABRICS, c.v, 4), FABRIC)
	legs(c, 0.75, 0.75, 1.45, 0.22, shade(wood, 0.1))
	for _, s in { -1, 1 } do
		box(c, "Post", 0.22, 2.1, 0.22, s * 0.75, 2.75, 0.79, shade(wood, 0.1), WOOD)
	end
	box(c, "Splat", 0.5, 1.25, 0.12, 0, 2.65, 0.79, wood, WOOD)
	box(c, "Rail", 1.3, 0.45, 0.18, 0, 3.5, 0.79, wood, WOOD)
end

BUILDERS.dishes_box = function(c: Ctx)
	local body = box(c, "Body", 1.96, 1.5, 1.96, 0, 0.75, 0, CARDBOARD, CARD)
	box(c, "Tape", 0.45, 1.52, 1.98, 0, 0.76, 0, TAPE, SMOOTH)
	for _, s in { -1, 1 } do
		box(c, "Flap", 0.05, 0.55, 1.9, s * 0.92, 1.72, 0, shade(CARDBOARD, 0.06), CARD, CFrame.Angles(0, 0, s * 0.2))
	end
	for n = -1, 1 do
		cyl(c, "Plate", 0.08, 1.0, n * 0.12, 1.48, n * 0.3, "z", pick({ rgb(246, 244, 238), rgb(150, 190, 220), rgb(240, 200, 120) }, c.v, n + 2))
	end
	label(body, "FRAGILE · KITCHEN", rgb(200, 40, 36), Enum.NormalId.Front)
end

BUILDERS.radio = function(c: Ctx)
	local enamel = pick({ rgb(232, 222, 196), rgb(200, 70, 60), rgb(90, 160, 160) }, c.v)
	box(c, "Body", 1.6, 0.9, 0.8, 0, 0.45, 0, enamel, SMOOTH)
	cyl(c, "Speaker", 0.04, 0.62, -0.38, 0.45, -0.41, "z", rgb(70, 60, 50), FABRIC)
	box(c, "Dial", 0.6, 0.28, 0.03, 0.38, 0.6, -0.41, rgb(250, 228, 160), NEON)
	for _, x in { 0.2, 0.56 } do
		cyl(c, "Knob", 0.06, 0.18, x, 0.25, -0.42, "z", rgb(220, 214, 196), METAL)
	end
	box(c, "Handle", 1.0, 0.08, 0.1, 0, 1.06, 0, STEEL, METAL)
	for _, s in { -1, 1 } do
		box(c, "Grip", 0.08, 0.18, 0.1, s * 0.46, 0.97, 0, STEEL, METAL)
	end
end

-- Bedroom --------------------------------------------------------------------------

BUILDERS.bed = function(c: Ctx)
	local wood = pick(WOODS, c.v, 1)
	local linen = pick(FABRICS, c.v, 3)
	box(c, "Frame", 5.4, 0.8, 7.0, 0, 0.8, 0.05, wood, WOOD)
	legs(c, 2.5, 3.2, 0.4, 0.4, shade(wood, 0.2))
	box(c, "Mattress", 5.0, 0.8, 6.8, 0, 1.6, 0.05, rgb(246, 244, 238), FABRIC)
	box(c, "Duvet", 5.2, 0.35, 4.8, 0, 2.1, -1.0, linen, FABRIC)
	box(c, "Fold", 5.25, 0.38, 0.5, 0, 2.12, 1.25, tint(linen, 0.35), FABRIC)
	for _, s in { -1, 1 } do
		box(c, "Pillow", 2.0, 0.5, 1.2, s * 1.15, 2.25, 2.6, rgb(250, 248, 242), FABRIC, CFrame.Angles(0.25, 0, 0))
	end
	box(c, "Headboard", 5.4, 3.6, 0.3, 0, 1.8, 3.55, wood, WOOD)
	box(c, "Panel", 4.6, 1.5, 0.1, 0, 2.65, 3.37, shade(linen, 0.2), FABRIC)
	box(c, "Footboard", 5.4, 1.6, 0.25, 0, 0.8, -3.575, wood, WOOD)
	box(c, "Throw", 5.25, 0.1, 1.1, 0, 2.32, -2.5, pick(ACCENTS, c.v, 2), FABRIC)
end

BUILDERS.wardrobe = function(c: Ctx)
	local wood = pick(WOODS, c.v, 2)
	local door = tint(wood, 0.06)
	box(c, "Plinth", 4.4, 0.35, 2.2, 0, 0.175, 0, shade(wood, 0.2), WOOD)
	box(c, "Body", 4.2, 6.35, 2.05, 0, 3.525, 0.075, wood, WOOD)
	box(c, "Cornice", 4.4, 0.3, 2.2, 0, 6.85, 0, shade(wood, 0.1), WOOD)
	for _, s in { -1, 1 } do
		box(c, "Door", 2.0, 6.0, 0.1, s * 1.03, 3.5, -1.0, door, WOOD)
		for _, y in { 2.0, 5.0 } do
			box(c, "Inset", 1.5, if y < 3 then 2.6 else 2.2, 0.05, s * 1.03, y, -1.07, shade(door, 0.12), WOOD)
		end
		box(c, "Knob", 0.12, 0.7, 0.12, s * 0.25, 3.6, -1.1, BRASS, METAL)
	end
end

BUILDERS.nightstand = function(c: Ctx)
	local wood = pick(WOODS, c.v, 2)
	legs(c, 0.75, 0.55, 0.4, 0.2, shade(wood, 0.2))
	box(c, "Body", 1.8, 1.6, 1.4, 0, 1.2, 0.1, wood, WOOD)
	for _, y in { 1.55, 0.85 } do
		box(c, "Drawer", 1.6, 0.6, 0.05, 0, y, -0.625, tint(wood, 0.06), WOOD)
		ball(c, "Knob", 0.14, 0, y, -0.68, BRASS, METAL)
	end
	box(c, "Clock", 0.55, 0.38, 0.28, 0.35, 2.19, 0.05, pick(ACCENTS, c.v, 3), SMOOTH)
	box(c, "ClockFace", 0.4, 0.24, 0.02, 0.35, 2.19, -0.1, rgb(240, 90, 70), NEON)
end

BUILDERS.dresser = function(c: Ctx)
	local wood = pick(WOODS, c.v, 4)
	legs(c, 1.7, 0.7, 0.3, 0.25, shade(wood, 0.2))
	box(c, "Body", 3.8, 2.7, 1.6, 0, 1.65, 0.1, wood, WOOD)
	box(c, "Top", 3.8, 0.2, 1.8, 0, 3.1, 0, shade(wood, 0.1), WOOD)
	for n = 0, 2 do
		local y = 0.75 + n * 0.85
		box(c, "Drawer", 3.5, 0.72, 0.06, 0, y, -0.73, tint(wood, 0.06), WOOD)
		box(c, "Pull", 0.8, 0.1, 0.08, 0, y + 0.1, -0.8, BRASS, METAL)
	end
end

BUILDERS.mirror = function(c: Ctx)
	local wood = pick(WOODS, c.v, 3)
	local lean = CFrame.Angles(0.1, 0, 0)
	box(c, "Frame", 1.7, 4.6, 0.14, 0, 2.6, -0.05, wood, WOOD, lean)
	local glass = box(c, "Glass", 1.4, 4.3, 0.04, 0, 2.6, -0.13, rgb(200, 216, 226), GLASS, lean)
	glass.Reflectance = 0.45
	for _, s in { -1, 1 } do
		box(c, "Foot", 0.2, 0.2, 1.0, s * 0.65, 0.1, 0, shade(wood, 0.15), WOOD)
	end
	box(c, "Prop", 0.15, 2.4, 0.15, 0, 1.25, 0.25, shade(wood, 0.15), WOOD, CFrame.Angles(-0.12, 0, 0))
end

BUILDERS.photo_album = function(c: Ctx)
	local body = box(c, "Box", 1.8, 0.9, 1.4, 0, 0.45, 0, rgb(186, 140, 96), CARD)
	box(c, "Inside", 1.7, 0.02, 1.3, 0, 0.91, 0, rgb(90, 66, 46), CARD)
	local covers = { rgb(150, 40, 50), rgb(40, 80, 130), rgb(60, 110, 70), rgb(200, 160, 70) }
	for n = 0, 2 do
		box(c, "Album", 0.32, 1.25, 1.1, -0.55 + n * 0.38, 0.75, 0.05, covers[(n + c.v) % #covers + 1], LEATHER, CFrame.Angles(0, 0, (n - 1) * 0.08))
	end
	box(c, "Photo", 0.6, 0.75, 0.06, 0.6, 1.15, -0.25, rgb(240, 236, 226), SMOOTH, CFrame.Angles(-0.2, 0, -0.1))
	box(c, "Picture", 0.45, 0.5, 0.02, 0.6, 1.2, -0.29, rgb(130, 170, 200), SMOOTH, CFrame.Angles(-0.2, 0, -0.1))
	box(c, "Heart", 0.25, 0.25, 0.02, -0.55, 0.45, -0.71, rgb(220, 60, 80), SMOOTH, CFrame.Angles(0, 0, math.pi / 4))
	label(body, "FAMILY PHOTOS", rgb(80, 40, 30), Enum.NormalId.Front, Enum.Font.PermanentMarker)
end

-- Kid's room ---------------------------------------------------------------------------

BUILDERS.kids_bed = function(c: Ctx)
	local paint = pick(PAINTS, c.v)
	local cover = pick(PAINTS, c.v, 2)
	box(c, "Frame", 3.6, 0.7, 5.9, 0, 0.65, 0, paint, WOOD)
	legs(c, 1.6, 2.75, 0.3, 0.3, shade(paint, 0.25))
	box(c, "Mattress", 3.2, 0.6, 5.6, 0, 1.3, 0, rgb(246, 244, 238), FABRIC)
	box(c, "Duvet", 3.4, 0.3, 4.0, 0, 1.7, -0.75, cover, FABRIC)
	for n, at in { { -0.7, -1.6 }, { 0.6, -0.2 } } do
		box(c, "Star", 0.6, 0.02, 0.6, at[1], 1.86, at[2], pick(ACCENTS, c.v, n), SMOOTH, CFrame.Angles(0, math.pi / 4, 0))
	end
	box(c, "Pillow", 2.2, 0.45, 1.0, 0, 1.82, 2.2, rgb(250, 248, 242), FABRIC, CFrame.Angles(0.2, 0, 0))
	box(c, "Headboard", 3.6, 3.0, 0.3, 0, 1.5, 2.95, paint, WOOD)
	cyl(c, "Moon", 0.06, 1.0, 0, 2.3, 2.77, "z", rgb(250, 220, 90))
	box(c, "Footboard", 3.6, 1.5, 0.25, 0, 0.75, -2.975, paint, WOOD)
	-- a teddy on the pillow
	local fur = rgb(176, 120, 70)
	ball(c, "Teddy", 0.7, 0.75, 2.2, 1.85, fur, FABRIC)
	ball(c, "TeddyHead", 0.55, 0.75, 2.65, 1.85, fur, FABRIC)
	ball(c, "TeddyEar", 0.22, 0.97, 2.86, 1.85, shade(fur, 0.15), FABRIC)
end

BUILDERS.rocking_horse = function(c: Ctx)
	-- Side on (the head toward -X): the rockers, the legs, a dappled body, the red saddle.
	local wood = pick(WOODS, c.v, 3)
	local coat = pick({ rgb(240, 236, 226), rgb(150, 96, 60), rgb(90, 64, 46) }, c.v)
	local mane = if c.v % 3 == 1 then rgb(90, 90, 96) else rgb(236, 226, 200)
	for _, z in { -0.55, 0.55 } do
		box(c, "Rocker", 1.8, 0.18, 0.15, 0, 0.12, z, wood, WOOD)
		for _, s in { -1, 1 } do
			box(c, "Rocker", 1.0, 0.18, 0.15, s * 1.35, 0.27, z, wood, WOOD, CFrame.Angles(0, 0, s * 0.33))
		end
	end
	for _, x in { -0.65, 0.65 } do
		for _, z in { -0.42, 0.42 } do
			box(c, "Leg", 0.18, 1.15, 0.18, x, 0.75, z, coat, WOOD, CFrame.Angles(z * 0.25, 0, 0))
		end
	end
	cyl(c, "Body", 2.0, 0.9, 0, 1.62, 0, "x", coat, WOOD)
	box(c, "Neck", 0.55, 1.05, 0.45, -0.95, 2.3, 0, coat, WOOD, CFrame.Angles(0, 0, 0.5))
	box(c, "Head", 0.95, 0.5, 0.45, -1.42, 2.78, 0, coat, WOOD, CFrame.Angles(0, 0, -0.35))
	box(c, "Mane", 0.16, 0.95, 0.12, -0.72, 2.45, 0, mane, FABRIC, CFrame.Angles(0, 0, 0.5))
	box(c, "Tail", 0.18, 0.75, 0.14, 1.12, 1.6, 0, mane, FABRIC, CFrame.Angles(0, 0, -0.55))
	for _, s in { -1, 1 } do
		wedge(c, "Ear", 0.12, 0.3, 0.15, -1.15, 3.08, s * 0.12, coat, WOOD)
		ball(c, "Eye", 0.12, -1.55, 2.86, s * 0.23, rgb(24, 24, 26))
	end
	box(c, "Saddle", 0.75, 0.15, 0.95, 0.05, 2.1, 0, rgb(200, 50, 46), LEATHER)
	cyl(c, "Handle", 0.9, 0.1, -1.1, 2.62, 0, "z", BRASS, METAL)
end

BUILDERS.toy_box = function(c: Ctx)
	local paint = pick(PAINTS, c.v, 1)
	local body = box(c, "Body", 3.0, 1.7, 1.8, 0, 0.85, 0, paint, WOOD)
	for _, y in { 0.15, 1.55 } do
		box(c, "Band", 3.02, 0.14, 1.82, 0, y, 0, pick(ACCENTS, c.v, 2), SMOOTH)
	end
	-- the lid ajar on its back hinge, a teddy and a ball peeking out
	local lid = CFrame.new(0, 1.7, 0.8) * CFrame.Angles(0.25, 0, 0) * CFrame.new(0, 0.1, -0.85)
	finish(c, Instance.new("Part"), "Lid", Vector3.new(3.0, 0.2, 1.7), lid, shade(paint, 0.08), WOOD)
	local fur = rgb(176, 120, 70)
	ball(c, "Teddy", 0.62, 0.65, 1.92, -0.3, fur, FABRIC)
	for _, s in { -1, 1 } do
		ball(c, "TeddyEar", 0.22, 0.65 + s * 0.22, 2.2, -0.3, shade(fur, 0.15), FABRIC)
	end
	ball(c, "Ball", 0.55, -0.7, 1.85, -0.25, pick({ rgb(230, 60, 60), rgb(60, 140, 230), rgb(250, 200, 60) }, c.v))
	label(body, "TOYS", WHITE, Enum.NormalId.Front)
end

BUILDERS.desk = function(c: Ctx)
	local paint = pick(PAINTS, c.v, 3)
	box(c, "Top", 3.6, 0.2, 2.0, 0, 2.3, 0, tint(paint, 0.2), WOOD)
	box(c, "Pedestal", 1.2, 2.2, 1.8, 1.1, 1.1, 0.05, paint, WOOD)
	for n, y in { 1.65, 0.75 } do
		box(c, "Drawer", 1.05, 0.7, 0.05, 1.1, y, -0.86, tint(paint, 0.1), WOOD)
		ball(c, "Knob", 0.14, 1.1, y, -0.92, pick(ACCENTS, c.v, n), SMOOTH)
	end
	for _, z in { -0.8, 0.8 } do
		box(c, "Leg", 0.2, 2.2, 0.2, -1.6, 1.1, z, paint, WOOD)
	end
	box(c, "Bar", 0.15, 0.15, 1.6, -1.6, 0.4, 0, paint, WOOD)
	box(c, "Book", 0.9, 0.18, 0.7, -0.9, 2.49, 0.2, pick(BOOKS, c.v, 1), SMOOTH, CFrame.Angles(0, 0.2, 0))
	box(c, "Book", 0.8, 0.16, 0.6, -0.85, 2.66, 0.2, pick(BOOKS, c.v, 4), SMOOTH, CFrame.Angles(0, -0.15, 0))
	cyl(c, "Cup", 0.5, 0.36, 0.2, 2.65, 0.5, "y", pick(ACCENTS, c.v, 3))
	box(c, "Pencils", 0.14, 0.6, 0.1, 0.2, 2.95, 0.5, rgb(250, 200, 60), SMOOTH, CFrame.Angles(0, 0, 0.15))
	ball(c, "Globe", 0.6, 1.2, 2.72, 0.3, rgb(80, 150, 210))
end

BUILDERS.guitar = function(c: Ctx)
	local wood = pick({ rgb(214, 150, 70), rgb(160, 80, 40), rgb(60, 40, 30) }, c.v)
	cyl(c, "Body", 0.35, 1.45, 0, 1.28, 0, "z", wood, WOOD)
	cyl(c, "Upper", 0.35, 1.1, 0, 2.05, 0, "z", wood, WOOD)
	cyl(c, "Hole", 0.02, 0.42, 0, 1.75, -0.18, "z", rgb(30, 22, 16))
	box(c, "Bridge", 0.55, 0.1, 0.05, 0, 1.0, -0.19, rgb(40, 28, 20), WOOD)
	box(c, "Neck", 0.28, 1.45, 0.16, 0, 3.15, 0, rgb(90, 56, 34), WOOD)
	box(c, "Head", 0.38, 0.55, 0.12, 0, 3.72, 0.02, rgb(40, 28, 20), WOOD, CFrame.Angles(0.15, 0, 0))
	box(c, "Strings", 0.16, 2.75, 0.02, 0, 2.38, -0.19, rgb(220, 220, 224), METAL)
	for _, s in { -1, 1 } do
		box(c, "StandLeg", 0.1, 1.4, 0.1, s * 0.45, 0.7, 0.16, DARK, METAL, CFrame.Angles(0.2, 0, -s * 0.2))
		box(c, "Foot", 0.12, 0.1, 0.8, s * 0.55, 0.05, 0, DARK, METAL)
	end
	box(c, "Cradle", 1.2, 0.12, 0.5, 0, 0.42, -0.1, DARK, METAL)
end

-- Bathroom and laundry ------------------------------------------------------------------

BUILDERS.washing_machine = function(c: Ctx)
	local enamel = pick({ rgb(240, 240, 238), rgb(230, 232, 236), rgb(200, 206, 210) }, c.v)
	box(c, "Body", 2.8, 3.3, 2.6, 0, 1.75, 0.1, enamel, SMOOTH)
	box(c, "Plinth", 2.6, 0.1, 2.5, 0, 0.05, 0.1, rgb(60, 60, 64), SMOOTH)
	box(c, "Panel", 2.75, 0.55, 0.05, 0, 3.05, -1.225, rgb(214, 218, 222), SMOOTH)
	cyl(c, "Dial", 0.1, 0.42, 0.8, 3.05, -1.27, "z", rgb(150, 156, 162), METAL)
	box(c, "Display", 0.5, 0.2, 0.03, 0.05, 3.05, -1.26, rgb(110, 210, 250), NEON)
	box(c, "Drawer", 0.75, 0.35, 0.06, -0.9, 3.05, -1.27, rgb(226, 228, 230), SMOOTH)
	cyl(c, "Ring", 0.12, 1.9, 0, 1.6, -1.26, "z", rgb(186, 192, 198), METAL)
	local glass = cyl(c, "Porthole", 0.06, 1.5, 0, 1.6, -1.33, "z", rgb(120, 160, 190), GLASS)
	glass.Transparency = 0.35
	ball(c, "Laundry", 1.2, 0, 1.45, -0.6, pick(ACCENTS, c.v, 2), FABRIC)
end

BUILDERS.laundry_basket = function(c: Ctx)
	local wicker = pick({ rgb(206, 176, 124), rgb(236, 236, 232), rgb(120, 170, 200) }, c.v)
	box(c, "Basket", 1.7, 1.1, 1.3, 0, 0.55, 0, wicker, if c.v % 3 == 1 then PLANKS else SMOOTH)
	box(c, "Rim", 1.8, 0.14, 1.4, 0, 1.1, 0, shade(wicker, 0.12), SMOOTH)
	for _, s in { -1, 1 } do
		box(c, "Handle", 0.06, 0.22, 0.5, s * 0.87, 0.92, 0, shade(wicker, 0.25), SMOOTH)
	end
	box(c, "Shirt", 1.2, 0.3, 0.9, -0.1, 1.25, 0.05, pick(FABRICS, c.v, 5), FABRIC, CFrame.Angles(0.1, 0.3, 0.08))
	box(c, "Towel", 0.9, 0.25, 0.7, 0.3, 1.42, -0.1, pick(ACCENTS, c.v, 1), FABRIC, CFrame.Angles(-0.1, -0.4, -0.1))
	cyl(c, "Sock", 0.6, 0.22, -0.45, 1.36, -0.2, "x", rgb(240, 240, 236), FABRIC, CFrame.Angles(0, 0.5, 0.3))
end

-- Hall --------------------------------------------------------------------------------------

BUILDERS.coat_rack = function(c: Ctx)
	local wood = pick(WOODS, c.v, 4)
	cyl(c, "Base", 0.15, 1.4, 0, 0.075, 0, "y", shade(wood, 0.2), WOOD)
	box(c, "Pole", 0.2, 5.0, 0.2, 0, 2.65, 0, wood, WOOD)
	ball(c, "Knob", 0.35, 0, 5.35, 0, wood, WOOD)
	for n = 0, 3 do
		local a = n * math.pi / 2
		box(c, "Hook", 0.1, 0.1, 0.55, math.sin(a) * 0.3, 4.95, -math.cos(a) * 0.3, BRASS, METAL, CFrame.Angles(0.5, a, 0))
	end
	box(c, "Coat", 1.1, 2.2, 0.5, 0, 3.75, -0.48, pick(FABRICS, c.v, 6), FABRIC)
	box(c, "Collar", 0.8, 0.3, 0.55, 0, 4.85, -0.42, shade(pick(FABRICS, c.v, 6), 0.2), FABRIC)
	box(c, "Scarf", 0.12, 1.6, 0.25, 0.55, 4.15, 0, pick(ACCENTS, c.v, 1), FABRIC)
	cyl(c, "Brim", 0.06, 0.85, -0.3, 5.12, 0.15, "y", rgb(60, 50, 44), FABRIC)
	cyl(c, "Crown", 0.38, 0.55, -0.3, 5.32, 0.15, "y", rgb(60, 50, 44), FABRIC)
end

BUILDERS.shoe_cabinet = function(c: Ctx)
	local paint = pick({ rgb(236, 232, 222), rgb(122, 82, 54), rgb(110, 140, 150) }, c.v)
	box(c, "Plinth", 3.1, 0.15, 1.3, 0, 0.075, 0.05, shade(paint, 0.3), SMOOTH)
	box(c, "Body", 3.2, 2.35, 1.3, 0, 1.325, 0.05, paint, WOOD)
	for n, y in { 1.85, 0.8 } do
		box(c, "Front", 3.0, 0.95, 0.06, 0, y, -0.63, tint(paint, 0.05), WOOD)
		box(c, "Pull", 0.9, 0.1, 0.08, 0, y + 0.3, -0.68, if n == 1 then BRASS else STEEL, METAL)
	end
	for _, x in { -0.75, -0.25 } do
		box(c, "Shoe", 0.42, 0.35, 0.95, x, 2.675, -0.05, pick({ rgb(200, 60, 50), rgb(60, 80, 140), rgb(240, 240, 236) }, c.v), FABRIC)
	end
	cyl(c, "Bowl", 0.22, 0.8, 0.9, 2.61, 0, "y", pick(ACCENTS, c.v, 2))
end

-- Garage --------------------------------------------------------------------------------------

BUILDERS.bicycle = function(c: Ctx)
	-- Side on, the front wheel toward -X.
	local paint = pick({ rgb(200, 50, 46), rgb(50, 120, 200), rgb(60, 160, 100), rgb(240, 190, 50) }, c.v)
	for _, x in { -1.55, 1.55 } do
		cyl(c, "Tyre", 0.18, 2.2, x, 1.1, 0, "z", rgb(28, 28, 30), RUBBER)
		cyl(c, "Rim", 0.22, 1.75, x, 1.1, 0, "z", rgb(196, 200, 206), METAL) -- (the spokes' silver inside the tyre)
	end
	local bb, seat, head, headLow = { 0.15, 0.95 }, { 0.45, 2.35 }, { -1.0, 2.45 }, { -1.1, 2.0 }
	rod(c, "SeatTube", bb[1], bb[2], seat[1], seat[2], 0, 0.16, paint, METAL)
	rod(c, "TopTube", seat[1], seat[2], head[1], head[2], 0, 0.16, paint, METAL)
	rod(c, "DownTube", headLow[1], headLow[2], bb[1], bb[2], 0, 0.18, paint, METAL)
	rod(c, "ChainStay", bb[1], bb[2], 1.55, 1.1, 0, 0.12, paint, METAL)
	rod(c, "SeatStay", seat[1], seat[2], 1.55, 1.1, 0, 0.12, paint, METAL)
	rod(c, "Fork", head[1], head[2], -1.55, 1.1, 0, 0.14, STEEL, METAL)
	rod(c, "Stem", head[1], head[2], -0.95, 2.95, 0, 0.12, STEEL, METAL)
	cyl(c, "Handlebar", 1.1, 0.12, -0.95, 2.95, 0, "z", DARK, RUBBER)
	rod(c, "SeatPost", seat[1], seat[2], 0.5, 2.85, 0, 0.1, STEEL, METAL)
	box(c, "Saddle", 0.9, 0.18, 0.42, 0.55, 2.95, 0, rgb(40, 32, 28), LEATHER)
	cyl(c, "Crank", 0.1, 0.55, bb[1], bb[2], 0, "z", STEEL, METAL)
	box(c, "Pedal", 0.35, 0.08, 0.5, bb[1] + 0.25, bb[2] - 0.2, -0.2, DARK, RUBBER)
	box(c, "Basket", 0.8, 0.6, 0.8, -1.45, 2.55, 0, rgb(206, 176, 124), PLANKS)
end

BUILDERS.toolbox = function(c: Ctx)
	local paint = pick({ rgb(200, 44, 40), rgb(40, 90, 170), rgb(230, 170, 40) }, c.v)
	box(c, "Body", 2.0, 0.8, 1.0, 0, 0.4, 0, paint, METAL)
	box(c, "Lid", 1.96, 0.16, 0.96, 0, 0.88, 0, shade(paint, 0.15), METAL)
	box(c, "Handle", 1.0, 0.1, 0.12, 0, 1.2, 0, DARK, RUBBER)
	for _, s in { -1, 1 } do
		box(c, "Post", 0.1, 0.25, 0.1, s * 0.45, 1.05, 0, DARK, METAL)
		box(c, "Latch", 0.2, 0.25, 0.04, s * 0.6, 0.75, -0.48, STEEL, METAL)
	end
end

BUILDERS.lawn_mower = function(c: Ctx)
	local paint = pick({ rgb(60, 150, 70), rgb(200, 50, 46), rgb(240, 160, 40) }, c.v)
	box(c, "Deck", 2.0, 0.6, 2.0, 0, 0.6, -0.9, paint, METAL)
	for _, x in { -0.95, 0.95 } do
		for _, z in { -1.7, -0.1 } do
			cyl(c, "Wheel", 0.25, 0.7, x * 0.97, 0.35, z, "x", DARK, RUBBER)
		end
	end
	cyl(c, "Engine", 0.6, 1.0, 0, 1.2, -0.9, "y", rgb(50, 52, 56), METAL)
	cyl(c, "Cap", 0.12, 0.5, 0, 1.56, -0.9, "y", rgb(200, 40, 40), SMOOTH)
	for _, x in { -0.75, 0.75 } do
		box(c, "Handle", 0.12, 3.05, 0.12, x, 1.95, 1.0, DARK, METAL, CFrame.Angles(0.72, 0, 0))
	end
	cyl(c, "Grip", 1.6, 0.14, 0, 3.08, 2.0, "x", DARK, RUBBER)
	box(c, "Bag", 1.4, 0.95, 1.2, 0, 0.95, 0.75, rgb(60, 64, 60), FABRIC)
end

BUILDERS.box = function(c: Ctx)
	local body = box(c, "Body", 1.96, 1.76, 1.96, 0, 0.88, 0, CARDBOARD, CARD)
	box(c, "Tape", 0.45, 1.8, 2.0, 0, 0.9, 0, TAPE, SMOOTH)
	local tag = box(c, "Tag", 0.9, 0.5, 0.02, 0.45, 0.95, -0.99, rgb(245, 245, 240), SMOOTH)
	label(tag, pick({ "BOOKS", "KITCHEN", "TOYS", "WINTER", "MISC" }, c.v), rgb(40, 40, 44), Enum.NormalId.Front, Enum.Font.PermanentMarker)
	label(body, "THIS SIDE UP ↑", shade(CARDBOARD, 0.5), Enum.NormalId.Back)
end

-- ── 7.x alpine pieces ─────────────────────────────────────────────────────────
-- The map turns into an Austrian alpine valley and Marge's house inside into a chalet (server/HouseInterior.luau):
-- the things of a chalet, in the catalogue after the others (Order) and in the house's recipes (shared/HouseLayout.luau).
-- The cuckoo clock and the accordion are sentimental (★ candidates: a house's ★ are its recipes' star entries, these
-- come in as extras, ★ only when a house is short of its star pieces).
--   id                  name                     icon  X    Y    Z    class   wt  value fragile room       ★
item("cuckoo_clock", "Cuckoo Clock", "🐦", 1.4, 2.8, 0.8, "hand", 1, 420, true, "living", true)
item("accordion", "Accordion", "🪗", 1.8, 1.7, 1.1, "both", 2, 520, true, "living", true)
item("heart_chair", "Alpine Armchair", "🪑", 2.2, 4.2, 2.2, "both", 3, 140, false, "living")
item("stein_crate", "Crate of Steins", "🍺", 2.2, 1.5, 1.6, "hand", 3, 140, true, "kitchen")
item("painted_cupboard", "Painted Cupboard", "🌷", 4.2, 7.0, 2.0, "pair", 9, 650, false, "bedroom")
item("carved_chest", "Carved Chest", "🗝️", 4.4, 2.6, 2.2, "pair", 7, 380, false, "bedroom")
item("edelweiss_frame", "Edelweiss Frame", "🌼", 2.0, 2.4, 0.4, "hand", 1, 180, true, "bedroom")
item("ski_bundle", "Skis & Poles", "🎿", 1.4, 6.4, 0.8, "both", 3, 160, false, "hall")

-- The chalet's palette: pine to old larch, the painted grounds of farmhouse furniture (blue-green, ox red, sage,
-- cream), the painted flowers, iron and pewter.
local PINES = { rgb(196, 146, 92), rgb(160, 110, 66), rgb(214, 172, 118), rgb(128, 86, 54) }
local PAINTED = { rgb(64, 108, 124), rgb(150, 62, 52), rgb(96, 124, 88), rgb(226, 212, 180) }
local BLOOMS = { rgb(206, 56, 52), rgb(244, 240, 228), rgb(236, 178, 60), rgb(72, 110, 172) }
local LEAF = rgb(70, 118, 66)
local IRON = rgb(56, 50, 46)
local PEWTER = rgb(150, 156, 160)

BUILDERS.cuckoo_clock = function(c: Ctx)
	-- The carved house clock taken off the wall, stood on its pine-cone weights: the chains, the pendulum, the case
	-- under its gable roof, the dial, and the bird looking out of its little door.
	local wood = pick(PINES, c.v, 1)
	local dark = shade(wood, 0.35)
	for _, s in { -1, 1 } do
		cyl(c, "Weight", 0.55, 0.26, s * 0.3, 0.275, 0.05, "y", IRON, METAL)
		box(c, "Chain", 0.04, 1.0, 0.04, s * 0.3, 1.05, 0.05, BRASS, METAL)
	end
	box(c, "Pendulum", 0.05, 0.6, 0.03, 0, 1.25, -0.1, BRASS, METAL)
	cyl(c, "Bob", 0.04, 0.32, 0, 0.95, -0.1, "z", dark, WOOD)
	box(c, "Case", 1.0, 0.85, 0.62, 0, 1.975, 0.07, wood, WOOD)
	box(c, "Gable", 0.36, 0.36, 0.5, 0, 2.4, 0.07, wood, WOOD, CFrame.Angles(0, 0, math.pi / 4))
	for _, s in { -1, 1 } do
		box(c, "Roof", 0.8, 0.09, 0.8, s * 0.33, 2.544, 0, dark, WOOD, CFrame.Angles(0, 0, -s * 0.5))
	end
	box(c, "Door", 0.2, 0.2, 0.04, 0, 2.48, -0.2, shade(wood, 0.5), WOOD)
	ball(c, "Cuckoo", 0.16, 0, 2.48, -0.27, pick({ rgb(120, 84, 50), rgb(236, 200, 70), rgb(70, 60, 54), rgb(200, 80, 60) }, c.v))
	cyl(c, "Dial", 0.05, 0.6, 0, 1.95, -0.265, "z", CREAM)
	box(c, "Hand", 0.05, 0.22, 0.02, 0.05, 2.02, -0.3, DARK, SMOOTH, CFrame.Angles(0, 0, -0.6))
	box(c, "Hand", 0.04, 0.28, 0.02, -0.06, 2.05, -0.3, DARK, SMOOTH, CFrame.Angles(0, 0, 0.4))
end

BUILDERS.accordion = function(c: Ctx)
	-- Grandad's accordion stood on its end: the treble side's keyboard (+X), the folded bellows, the bass side's
	-- buttons (-X), the shoulder strap at the back.
	local body = pick({ rgb(176, 36, 40), rgb(32, 32, 36), rgb(236, 228, 206), rgb(30, 96, 90) }, c.v)
	local fold = shade(body, 0.45)
	box(c, "Treble", 0.5, 1.65, 1.05, 0.65, 0.825, 0, body, SMOOTH)
	box(c, "Keys", 0.32, 1.35, 0.06, 0.62, 0.85, -0.54, rgb(246, 244, 236), SMOOTH)
	box(c, "Sharps", 0.14, 1.25, 0.05, 0.53, 0.86, -0.58, rgb(24, 24, 26), SMOOTH)
	box(c, "Bass", 0.45, 1.65, 1.05, -0.675, 0.825, 0, body, SMOOTH)
	box(c, "Buttons", 0.3, 0.8, 0.05, -0.66, 1.0, -0.55, rgb(232, 226, 214), SMOOTH)
	for n = 0, 3 do
		box(c, "Bellows", 0.2, 1.5, 0.95, -0.34 + n * 0.21, 0.8, 0, if n % 2 == 0 then fold else tint(body, 0.25), FABRIC)
	end
	box(c, "Strap", 0.12, 1.3, 0.05, 0.65, 0.85, 0.55, rgb(110, 70, 44), LEATHER)
end

BUILDERS.heart_chair = function(c: Ctx)
	-- A Stube's plank armchair: splayed legs, board arms, a cushion, and the tall back board with its heart cut out.
	local wood = pick(PINES, c.v, 2)
	local dark = shade(wood, 0.15)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(c, "Leg", 0.22, 1.6, 0.22, sx * 0.72, 0.8, sz * 0.62, dark, WOOD, CFrame.Angles(-sz * 0.12, 0, sx * 0.12))
		end
	end
	box(c, "Seat", 2.0, 0.25, 1.9, 0, 1.72, -0.05, wood, WOOD)
	box(c, "Cushion", 1.6, 0.15, 1.5, 0, 1.92, -0.15, pick(FABRICS, c.v, 2), FABRIC)
	for _, s in { -1, 1 } do
		box(c, "Arm", 0.22, 1.05, 1.8, s * 0.95, 2.35, -0.05, wood, WOOD)
	end
	-- the back board leans back a little; the heart (a turned square and two round lobes) cut through it
	local lean = 0.1
	local back = CFrame.new(0, 3.0, 0.88) * CFrame.Angles(lean, 0, 0)
	box(c, "Back", 1.7, 2.3, 0.2, 0, 3.0, 0.88, wood, WOOD, CFrame.Angles(lean, 0, 0))
	local hole = shade(wood, 0.75)
	local function onBack(name: string, part: BasePart, x: number, y: number, turn: CFrame)
		finish(c, part, name, part.Size, back * CFrame.new(x, y, -0.11) * turn, hole, WOOD)
	end
	local diamond = Instance.new("Part")
	diamond.Size = Vector3.new(0.5, 0.5, 0.04)
	onBack("Heart", diamond, 0, 0.2, CFrame.Angles(0, 0, math.pi / 4))
	for _, s in { -1, 1 } do
		local lobe = Instance.new("Part")
		lobe.Shape = Enum.PartType.Cylinder
		lobe.Size = Vector3.new(0.04, 0.5, 0.5)
		onBack("Heart", lobe, s * 0.177, 0.377, CFrame.Angles(0, math.pi / 2, 0))
	end
end

BUILDERS.stein_crate = function(c: Ctx)
	-- A beer crate of four stoneware steins with pewter lids, packed for the move.
	local wood = pick(PINES, c.v, 3)
	local glaze = pick({ rgb(150, 156, 170), rgb(226, 216, 190), rgb(120, 86, 60), rgb(70, 96, 140) }, c.v)
	local crate = box(c, "Crate", 2.16, 0.85, 1.56, 0, 0.425, 0, wood, PLANKS)
	box(c, "Rim", 2.2, 0.16, 1.6, 0, 0.8, 0, shade(wood, 0.2), WOOD)
	for _, x in { -0.5, 0.5 } do
		for _, z in { -0.37, 0.37 } do
			cyl(c, "Stein", 1.15, 0.62, x, 0.725, z, "y", glaze, SMOOTH)
			cyl(c, "Lid", 0.12, 0.66, x, 1.36, z, "y", PEWTER, METAL)
		end
	end
	label(crate, "PROST!", shade(wood, 0.6), Enum.NormalId.Front, Enum.Font.PermanentMarker)
end

BUILDERS.painted_cupboard = function(c: Ctx)
	-- A Bauernschrank: the farmhouse cupboard painted on a coloured ground, a flower on each door, its year on the
	-- cornice.
	local ground = pick(PAINTED, c.v)
	box(c, "Plinth", 4.2, 0.4, 2.0, 0, 0.2, 0, shade(ground, 0.3), WOOD)
	box(c, "Body", 3.95, 6.1, 1.85, 0, 3.45, 0.075, ground, WOOD)
	local cornice = box(c, "Cornice", 4.2, 0.5, 2.0, 0, 6.75, 0, shade(ground, 0.25), WOOD)
	for n, s in { -1, 1 } do
		box(c, "Door", 1.85, 5.7, 0.08, s * 0.96, 3.45, -0.88, tint(ground, 0.06), WOOD)
		box(c, "Panel", 1.3, 2.6, 0.04, s * 0.96, 4.1, -0.94, tint(ground, 0.55), SMOOTH)
		box(c, "Stem", 0.1, 1.2, 0.03, s * 0.96, 3.95, -0.97, LEAF, SMOOTH)
		box(c, "Leaves", 0.75, 0.14, 0.03, s * 0.96, 3.85, -0.975, LEAF, SMOOTH, CFrame.Angles(0, 0, s * 0.45))
		cyl(c, "Bloom", 0.04, 0.6, s * 0.96, 4.75, -0.98, "z", pick(BLOOMS, c.v, n))
	end
	box(c, "Keyhole", 0.14, 0.4, 0.05, 0, 3.45, -0.95, BRASS, METAL)
	label(cornice, pick({ "ANNO 1897", "ANNO 1902", "ANNO 1874", "ANNO 1911" }, c.v), tint(ground, 0.7), Enum.NormalId.Front, Enum.Font.Garamond)
end

BUILDERS.carved_chest = function(c: Ctx)
	-- The dowry chest from the foot of the bed: bun feet, three carved panels with painted rosettes, an iron hasp and
	-- rings to lift it by.
	local wood = pick(PINES, c.v, 4)
	legs(c, 1.85, 0.8, 0.35, 0.45, shade(wood, 0.3))
	box(c, "Body", 4.2, 1.85, 2.0, 0, 1.275, 0, wood, WOOD)
	box(c, "Lid", 4.4, 0.35, 2.2, 0, 2.375, 0, shade(wood, 0.12), WOOD)
	for n = -1, 1 do
		box(c, "Panel", 1.15, 1.2, 0.05, n * 1.33, 1.25, -1.02, shade(wood, 0.18), WOOD)
		cyl(c, "Rosette", 0.04, 0.62, n * 1.33, 1.25, -1.06, "z", pick(BLOOMS, c.v, n + 2))
	end
	box(c, "Hasp", 0.3, 0.55, 0.06, 0, 2.05, -1.1, IRON, METAL)
	for _, s in { -1, 1 } do
		cyl(c, "Ring", 0.06, 0.45, s * 2.13, 1.6, 0, "x", IRON, METAL)
	end
end

BUILDERS.edelweiss_frame = function(c: Ctx)
	-- Pressed edelweiss under glass in a pine frame, a handwritten label; cardboard corners for the move.
	local wood = pick(PINES, c.v, 2)
	local paper = pick({ rgb(120, 140, 112), rgb(104, 122, 146), rgb(170, 148, 112), rgb(112, 86, 76) }, c.v) -- (the mount)
	box(c, "Frame", 2.0, 2.4, 0.2, 0, 1.2, 0, wood, WOOD)
	box(c, "Paper", 1.6, 2.0, 0.04, 0, 1.2, -0.115, paper, SMOOTH)
	-- two flowers: a felt star of two squares, its yellow heart
	for n, at in { { -0.3, 1.6 }, { 0.32, 1.05 } } do
		local size = if n == 1 then 0.55 else 0.45
		box(c, "Petals", size, size, 0.02, at[1], at[2], -0.145, rgb(238, 238, 230), FABRIC, CFrame.Angles(0, 0, math.pi / 4))
		box(c, "Petals", size, size, 0.02, at[1], at[2], -0.15, rgb(226, 228, 220), FABRIC)
		ball(c, "Heart", 0.12, at[1], at[2], -0.16, rgb(206, 196, 110))
	end
	local tag = box(c, "Label", 0.8, 0.22, 0.02, 0.25, 0.42, -0.145, rgb(250, 248, 240), SMOOTH)
	label(tag, "Edelweiss", rgb(60, 50, 40), Enum.NormalId.Front, Enum.Font.Garamond)
	local glass = box(c, "Glass", 1.6, 2.0, 0.03, 0, 1.2, -0.235, rgb(220, 232, 236), GLASS)
	glass.Transparency = 0.8
	box(c, "Strut", 0.3, 2.0, 0.12, 0, 1.0, 0.13, shade(CARDBOARD, 0.2), CARD, CFrame.Angles(-0.04, 0, 0))
	for _, s in { -1, 1 } do
		box(c, "Corner", 0.45, 0.45, 0.36, s * 0.8, 0.225, 0, CARDBOARD, CARD)
	end
end

BUILDERS.ski_bundle = function(c: Ctx)
	-- Grandad's wooden skis strapped together on end, the tips curled, the bamboo poles beside them.
	local wood = pick({ rgb(176, 120, 66), rgb(150, 44, 40), rgb(206, 166, 108), rgb(60, 86, 120) }, c.v)
	local cane = rgb(214, 190, 130)
	local curl = 0.6
	for _, s in { -1, 1 } do
		box(c, "Ski", 0.36, 5.7, 0.1, s * 0.21, 2.85, 0.05, wood, WOOD)
		box(c, "Tip", 0.36, 0.75, 0.1, s * 0.21, 5.7 + 0.375 * math.cos(curl), 0.05 - 0.375 * math.sin(curl), wood, WOOD, CFrame.Angles(-curl, 0, 0))
		box(c, "Binding", 0.42, 0.5, 0.22, s * 0.21, 2.4, -0.07, rgb(60, 50, 44), LEATHER)
		cyl(c, "Pole", 5.6, 0.09, s * 0.56, 2.9, 0.24, "y", cane, WOOD)
		cyl(c, "Basket", 0.05, 0.36, s * 0.56, 0.5, 0.24, "y", rgb(60, 50, 44), LEATHER)
	end
	box(c, "Strap", 1.3, 0.22, 0.62, 0, 3.6, 0.1, rgb(120, 70, 40), LEATHER)
end

-- ── The model ────────────────────────────────────────────────────────────────

function FurnitureLooks.build(id: string, variant: number?): Model
	local def = Items[id] or Items.box
	local size = def.size
	local model = Instance.new("Model")
	model.Name = def.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the whole piece streams in at once
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = size
	root.CFrame = CFrame.new(0, 0, 0)
	root.Transparency = 1
	root.Anchored = false
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = true
	root.CastShadow = false
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	model.PrimaryPart = root
	local v = math.max(1, math.floor(variant or 1))
	local ctx: Ctx = { model = model, root = root, base = CFrame.new(0, -size.Y / 2, 0), v = v }
	local builder = BUILDERS[def.id]
	if builder then
		builder(ctx)
	end
	model:SetAttribute("FurnitureId", id)
	model:SetAttribute("Class", def.class)
	model:SetAttribute("Weight", def.weight)
	model:SetAttribute("Fragile", def.fragile)
	return model
end

-- Where the hands hold a piece (Root space): a "pair" piece at both ends of its long side, a "both" piece at its two
-- sides, a "hand" piece at its front; at two thirds of its height, at most hand height (3 studs over the floor).
function FurnitureLooks.grips(id: string): { Vector3 }
	local def = Items[id] or Items.box
	local s = def.size
	local y = math.min(s.Y * 2 / 3, 3) - s.Y / 2
	if def.class == "pair" then
		if s.X >= s.Z then
			return { Vector3.new(-s.X / 2, y, 0), Vector3.new(s.X / 2, y, 0) }
		end
		return { Vector3.new(0, y, -s.Z / 2), Vector3.new(0, y, s.Z / 2) }
	elseif def.class == "both" then
		return { Vector3.new(-s.X / 2, y, 0), Vector3.new(s.X / 2, y, 0) }
	end
	return { Vector3.new(0, y, -s.Z / 2) }
end

-- How many parts a piece's model has (its Root included): the part budget's count (Config.Furniture.MaxParts).
function FurnitureLooks.parts(id: string): number
	local model = FurnitureLooks.build(id)
	local count = 0
	for _, obj in model:GetDescendants() do
		if obj:IsA("BasePart") then
			count += 1
		end
	end
	model:Destroy()
	return count
end

FurnitureLooks.MaxParts = Tuning.MaxParts

return FurnitureLooks
