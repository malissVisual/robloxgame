--!strict
-- 8.3 SANDBOX, the PAINT shop's rules (Config.VanPaint): the catalogue (the body colours and the liveries), what each
-- costs and whether you may buy or wear it, the look a van wears for what you wear (its colours, the roof's stripes),
-- the window's swatches and the save checked and migrated. Pure (no Roblox at its top level; tests/vanpaint_test.luau):
-- server/VanPaint.luau decides every purchase with it, shared/VanLook.luau paints a van from its Look,
-- client/VanPaintUi.luau draws its swatches.
--
-- The save (profile.vanPaint) is { owned = { [id] = true }, worn = { paint = id, livery = id } }: the items bought (an
-- everybody's item is never kept: it is owned anyway) and the paint and the livery on the van.
--   VanPaintRules.Paints / Liveries      the catalogue's items in the window's order (Config.VanPaint), with their kind
--   VanPaintRules.Default                { paint, livery }: the factory's (the first of each)
--   VanPaintRules.find(id)               the item (nil: none; any type)
--   VanPaintRules.free(item)             everybody's: no price, no unlock
--   VanPaintRules.owns(saved, id)        bought, or everybody's
--   VanPaintRules.unlocked(item, paid)   no unlock, or its milestone paid (paid: { [milestone id] = true })
--   VanPaintRules.lockText(item)         what unlocks it, in words ("" with no unlock)
--   VanPaintRules.check(saved, id, money, paid)   may it be bought now? → ok, why (said to the player), its price
--   VanPaintRules.buy(saved, id)         owned from now and worn (after check and the payment)
--   VanPaintRules.wear(saved, id)        → ok, why: an item you own on the van (free)
--   VanPaintRules.look(worn)             the Look a van wears (its body's colour, material and reflectance, the stripes',
--                                        the roof's pieces, whether each is the factory's)
--   VanPaintRules.contrast(color)        the "contrast" stripe for a body colour
--   VanPaintRules.roof(id, stripe)       a roof decoration's pieces (the van's frame) in the stripe's colour
--   VanPaintRules.rows(saved, money, paid, kind)   the window's swatches of a kind ("paint" | "livery")
--   VanPaintRules.inked()                the parts look's labels inked in the stripe's colour (shared/SprinterLooks.luau)
--   VanPaintRules.money(n)               "$1,234"
--   The save:
--   VanPaintRules.empty()                a new player's: nothing bought, the factory's worn
--   VanPaintRules.all()                  everything owned (the admin's UNLOCK PAINTS), the factory's worn
--   VanPaintRules.clean(raw)             a saved one checked, never trusted: known ids bought, worn only what is owned
--   VanPaintRules.fromSave(saved)        the migration (server/PlayerData.luau applySaved): only a real save (money in
--                                        it) written with the flag keeps its paint; any other starts with the empty one
--   VanPaintRules.Flag                   that flag

local Config = require(script.Parent.Config)
local SprinterLooks = require(script.Parent.SprinterLooks)

local VanPaintRules = {}

export type Item = {
	id: string,
	kind: string, -- "paint" | "livery"
	name: string,
	price: number,
	color: { number }?, -- a paint's
	stripe: any?, -- a livery's: RGB or "contrast"
	material: string?,
	roof: string?,
	unlock: string?,
	premium: boolean,
}
export type Worn = { paint: string, livery: string }
export type Saved = { owned: { [string]: boolean }, worn: Worn }
export type Piece = { name: string, size: { number }, at: { number }, color: { number }, material: string }
export type Look = {
	paint: string,
	livery: string,
	body: { number },
	bodyMaterial: string,
	bodyReflectance: number,
	factoryPaint: boolean, -- the factory's paint (the Blender look keeps its own cream)
	stripe: { number },
	stripeMaterial: string,
	stripeReflectance: number,
	factoryLivery: boolean, -- the factory's livery (the ZDC red)
	roof: { Piece },
}
export type Row = {
	id: string,
	kind: string,
	name: string,
	price: number,
	color: { number }, -- the swatch: a paint's colour, a livery's stripe on the body you wear
	body: { number }, -- the swatch's ground (a livery's: the body you wear)
	premium: boolean,
	owned: boolean,
	worn: boolean,
	locked: boolean,
	lock: string, -- what unlocks it ("" with no unlock)
	can: boolean, -- not owned, unlocked and the money buys it
	short: number, -- the money missing for it (0: none)
}

local function tune(): any
	return Config.VanPaint
end

VanPaintRules.Flag = tune().Flag :: string

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function rgb(c: any, fallback: { number }): { number }
	if type(c) == "table" and finite(c[1]) and finite(c[2]) and finite(c[3]) then
		return { math.clamp(math.floor(c[1]), 0, 255), math.clamp(math.floor(c[2]), 0, 255), math.clamp(math.floor(c[3]), 0, 255) }
	end
	return table.clone(fallback)
end

-- The catalogue: the items of Config's two lists in order, each id once (a paint and a livery never share one).
local byId: { [string]: Item } = {}
local function list(defs: { any }, kind: string): { Item }
	local out: { Item } = {}
	for _, def in defs do
		assert(type(def.id) == "string" and byId[def.id] == nil, `Config.VanPaint: the id {tostring(def.id)} twice`)
		local item: Item = {
			id = def.id,
			kind = kind,
			name = def.name,
			price = if finite(def.price) then math.max(0, math.floor(def.price)) else 0,
			color = def.color,
			stripe = def.stripe,
			material = def.material,
			roof = def.roof,
			unlock = def.unlock,
			premium = def.premium == true,
		}
		byId[def.id] = item
		table.insert(out, item)
	end
	return out
end
VanPaintRules.Paints = list(tune().Paints, "paint")
VanPaintRules.Liveries = list(tune().Liveries, "livery")
VanPaintRules.Default = { paint = VanPaintRules.Paints[1].id, livery = VanPaintRules.Liveries[1].id } :: Worn

function VanPaintRules.find(id: any): Item?
	if type(id) ~= "string" or #id > 32 then
		return nil
	end
	return byId[id]
end

function VanPaintRules.free(item: Item): boolean
	return item.price <= 0 and item.unlock == nil
end

function VanPaintRules.owns(saved: any, id: any): boolean
	local item = VanPaintRules.find(id)
	if not item then
		return false
	end
	if VanPaintRules.free(item) then
		return true
	end
	local owned = if type(saved) == "table" then saved.owned else nil
	return type(owned) == "table" and owned[item.id] == true
end

function VanPaintRules.unlocked(item: Item, paid: any): boolean
	local unlock = item.unlock
	return unlock == nil or (type(paid) == "table" and paid[unlock] == true)
end

-- The milestone's name ("Found every collectible"), else its id.
local function milestoneName(id: string): string
	local book = (Config :: any).CollectionBook
	if type(book) == "table" and type(book.Milestones) == "table" then
		for _, milestone in book.Milestones do
			if milestone.id == id then
				return milestone.name
			end
		end
	end
	return id
end

function VanPaintRules.lockText(item: Item): string
	local unlock = item.unlock
	if unlock == nil then
		return ""
	end
	return `Collection book: {milestoneName(unlock)}`
end

-- "$1,234" (whole dollars; the window's prices and the server's refusals).
function VanPaintRules.money(n: any): string
	local amount = if finite(n) then math.max(0, math.floor(n + 0.5)) else 0
	local out = string.reverse((string.gsub(string.reverse(string.format("%d", amount)), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return "$" .. out
end

function VanPaintRules.check(saved: any, id: any, money: any, paid: any): (boolean, string?, number)
	local item = VanPaintRules.find(id)
	if not item then
		return false, "That's no paint.", 0
	end
	if VanPaintRules.owns(saved, item.id) then
		return false, `{item.name} is yours already: wear it for free.`, 0
	end
	if not VanPaintRules.unlocked(item, paid) then
		return false, `{item.name} unlocks with the collection book's "{milestoneName(item.unlock :: string)}".`, item.price
	end
	local cash = if finite(money) then money :: number else 0
	if cash < item.price then
		return false, `{item.name} costs {VanPaintRules.money(item.price)}: you have {VanPaintRules.money(cash)}.`, item.price
	end
	return true, nil, item.price
end

-- (A save made fit for writing: owned a table, worn both kinds.)
local function fit(saved: Saved): Saved
	if type(saved.owned) ~= "table" then
		saved.owned = {}
	end
	if type(saved.worn) ~= "table" then
		saved.worn = table.clone(VanPaintRules.Default)
	end
	return saved
end

function VanPaintRules.buy(saved: Saved, id: string)
	local item = VanPaintRules.find(id)
	if not item then
		return
	end
	fit(saved)
	if not VanPaintRules.free(item) then
		saved.owned[item.id] = true
	end
	if item.kind == "paint" then
		saved.worn.paint = item.id
	else
		saved.worn.livery = item.id
	end
end

function VanPaintRules.wear(saved: Saved, id: any): (boolean, string?)
	local item = VanPaintRules.find(id)
	if not item then
		return false, "That's no paint."
	end
	if not VanPaintRules.owns(saved, item.id) then
		return false, `{item.name} isn't yours yet: buy it first.`
	end
	fit(saved)
	if item.kind == "paint" then
		saved.worn.paint = item.id
	else
		saved.worn.livery = item.id
	end
	return true, nil
end

-- ── The look ───────────────────────────────────────────────────────────────

local function luminance(c: { number }): number
	return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

function VanPaintRules.contrast(color: { number }): { number }
	local t = tune().Contrast
	return table.clone(if luminance(color) < t.Threshold then t.Light else t.Dark)
end

-- Glossy finishes: a little reflectance (as the city's paint jobs: server/Vehicles.luau applyPaint).
local function reflectance(material: string): number
	return if material == "Glass" then 0.25 elseif material == "Foil" then 0.1 else 0
end

function VanPaintRules.roof(id: string?, stripe: { number }): { Piece }
	local out: { Piece } = {}
	local stripes = if id then tune().Roofs[id] else nil
	if type(stripes) ~= "table" then
		return out
	end
	local r = tune().Roof
	local y = Config.Sprinter.Height + r.Lift
	for index, s in stripes do
		table.insert(out, {
			name = `RoofStripe{index}`,
			size = { s.w, r.Thick, r.To - r.From },
			at = { s.x, y, (r.From + r.To) / 2 },
			color = rgb(s.color, stripe),
			material = "SmoothPlastic",
		})
	end
	return out
end

-- The Look for what is worn (an unknown id: the factory's).
function VanPaintRules.look(worn: any): Look
	local paint = VanPaintRules.find(if type(worn) == "table" then worn.paint else nil)
	if not paint or paint.kind ~= "paint" then
		paint = VanPaintRules.find(VanPaintRules.Default.paint) :: Item
	end
	local livery = VanPaintRules.find(if type(worn) == "table" then worn.livery else nil)
	if not livery or livery.kind ~= "livery" then
		livery = VanPaintRules.find(VanPaintRules.Default.livery) :: Item
	end
	local p, l = paint :: Item, livery :: Item
	local body = rgb(p.color, { 232, 226, 210 })
	local bodyMaterial = p.material or "SmoothPlastic"
	local stripe = if l.stripe == "contrast" then VanPaintRules.contrast(body) else rgb(l.stripe, { 179, 38, 30 })
	local stripeMaterial = l.material or "SmoothPlastic"
	return {
		paint = p.id,
		livery = l.id,
		body = body,
		bodyMaterial = bodyMaterial,
		bodyReflectance = reflectance(bodyMaterial),
		factoryPaint = p.id == VanPaintRules.Default.paint,
		stripe = stripe,
		stripeMaterial = stripeMaterial,
		stripeReflectance = reflectance(stripeMaterial),
		factoryLivery = l.id == VanPaintRules.Default.livery,
		roof = VanPaintRules.roof(l.roof, stripe),
	}
end

-- ── The window ─────────────────────────────────────────────────────────────

function VanPaintRules.rows(saved: any, money: any, paid: any, kind: string): { Row }
	local cash = if finite(money) then money :: number else 0
	local worn: Worn = if type(saved) == "table" and type(saved.worn) == "table" then saved.worn else VanPaintRules.Default
	local look = VanPaintRules.look(worn)
	local out: { Row } = {}
	for _, item in if kind == "livery" then VanPaintRules.Liveries else VanPaintRules.Paints do
		local owned = VanPaintRules.owns(saved, item.id)
		local locked = not owned and not VanPaintRules.unlocked(item, paid)
		local shows = if item.kind == "paint" then rgb(item.color, look.body) else VanPaintRules.look({ paint = look.paint, livery = item.id }).stripe
		table.insert(out, {
			id = item.id,
			kind = item.kind,
			name = item.name,
			price = item.price,
			color = shows,
			body = if item.kind == "paint" then shows else table.clone(look.body),
			premium = item.premium,
			owned = owned,
			worn = (if item.kind == "paint" then look.paint else look.livery) == item.id,
			locked = locked,
			lock = VanPaintRules.lockText(item),
			can = not owned and not locked and cash >= item.price,
			short = if not owned and cash < item.price then math.ceil(item.price - cash) else 0,
		})
	end
	return out
end

-- The parts look's labels whose letters are the stripe's ink (the ZDC logo on the sides and the back door).
local inkedNames: { [string]: boolean }? = nil
function VanPaintRules.inked(): { [string]: boolean }
	local known = inkedNames
	if known then
		return known
	end
	local names: { [string]: boolean } = {}
	local function scan(pieces: { SprinterLooks.Piece })
		for _, piece in pieces do
			if piece.text and piece.ink == "stripe" then
				names[piece.name] = true
			end
		end
	end
	scan(SprinterLooks.body())
	scan(SprinterLooks.door(-1))
	scan(SprinterLooks.door(1))
	for _, leaf in SprinterLooks.leaves() do
		scan(leaf.pieces)
	end
	scan((SprinterLooks.slider()))
	inkedNames = names
	return names
end

-- ── The save ───────────────────────────────────────────────────────────────

function VanPaintRules.empty(): Saved
	return { owned = {}, worn = table.clone(VanPaintRules.Default) }
end

function VanPaintRules.all(): Saved
	local saved = VanPaintRules.empty()
	for _, items in { VanPaintRules.Paints, VanPaintRules.Liveries } do
		for _, item in items do
			if not VanPaintRules.free(item) then
				saved.owned[item.id] = true
			end
		end
	end
	return saved
end

-- A saved one, checked: only known, not everybody's ids bought (true); worn a known item of its kind that is owned,
-- else the factory's. Never an error.
function VanPaintRules.clean(raw: any): Saved
	local saved = VanPaintRules.empty()
	if type(raw) ~= "table" then
		return saved
	end
	if type(raw.owned) == "table" then
		for _, items in { VanPaintRules.Paints, VanPaintRules.Liveries } do
			for _, item in items do
				if raw.owned[item.id] == true and not VanPaintRules.free(item) then
					saved.owned[item.id] = true
				end
			end
		end
	end
	local worn = if type(raw.worn) == "table" then raw.worn else {}
	local paint = VanPaintRules.find(worn.paint)
	if paint and paint.kind == "paint" and VanPaintRules.owns(saved, paint.id) then
		saved.worn.paint = paint.id
	end
	local livery = VanPaintRules.find(worn.livery)
	if livery and livery.kind == "livery" and VanPaintRules.owns(saved, livery.id) then
		saved.worn.livery = livery.id
	end
	return saved
end

-- The migration: a real save (money in it) written with the flag keeps its paint (cleaned); every other one (from
-- before 8.3, a new player's nil, a lock-only record) starts with the empty one. Running it again gives the same.
function VanPaintRules.fromSave(saved: any): Saved
	if type(saved) ~= "table" or saved.money == nil or saved[VanPaintRules.Flag] ~= true then
		return VanPaintRules.empty()
	end
	return VanPaintRules.clean(saved.vanPaint)
end

return VanPaintRules
