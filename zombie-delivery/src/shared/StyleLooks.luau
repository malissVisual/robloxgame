--!strict
-- 6.12: the cosmetics' geometry (Config.Cosmetics), pure data. shared/StyleBuild.luau makes the parts: on the server
-- (server/StyleWear.luau, for everybody) and in the phone's STYLE preview (client/StylePreview.luau). Studs.
--
--   StyleLooks.hat(look)        a hat's pieces on the Head, drawn on the classic R15 head (Config.Cosmetics.Fit.Head,
--                               1.2 every way, its middle at 0; the face looks down -Z, the top at +0.6). Crowns are
--                               upright cylinders a little wider than the head, so the hat sits on it.
--   StyleLooks.jacket(look)     a jacket's pieces: thin shells over the UpperTorso, the LowerTorso and the four arm
--                               parts (each part's own nominal size, StyleLooks.Nominal, + Fit.Shell a side) and their
--                               details (a hood, cuffs, a zip, stripes …), drawn on the classic R15 body
--   StyleLooks.factors(bone, size)  the x / y / z scale of a real body part against StyleLooks.Nominal (a head: one
--                               factor across and deep, so the crowns stay round; clamped like shared/KitFit.luau)
--   StyleLooks.decals(look, panels, blocks)  a decal's pieces in the chassis' space, laid on the car's painted panels
--                               (`panels`: the Hood, the CabRoof, the CargoRoof / RearDeck on top; the CargoSide and the
--                               FrontFender on both sides) clear of every other visible part (`blocks`: lamps, racks,
--                               labels, stripes, glass, doors, the gun, the kit), each a box { min, max } in that space
--   StyleLooks.BikeFrame / Scooter   the art parts a bike's or the E-Scooter's paint takes (server/BikeArt, ScooterArt)
--   StyleLooks.Vest / StyleLooks.Bags   the Courier Vest's cloth and each bag's body (their dye: name → shade)
-- Every piece: { name, attach (a body part, or "Chassis"), size, at, turn? (degrees, CFrame.Angles order), shape?
-- ("Cylinder" | "Ball" | "Wedge"), paint ("main" | "trim" | "shade" | "dark" | "metal" | "white"), text?, face?
-- ("Top" | "Right" | "Left": the side a text or a checker is drawn on), checker? { rows, size } }.
-- Pure Luau (tests/style_test.luau; the fit on the body and the vehicles: tools/character-art/style-check.luau,
-- tools/vehicle-preview/decal-check.luau).

local Config = require(script.Parent.Config)

local StyleLooks = {}

export type Triple = { number }
export type Piece = {
	name: string,
	attach: string,
	size: Triple,
	at: Triple,
	turn: Triple?,
	shape: string?,
	paint: string,
	text: string?,
	face: string?,
	checker: { rows: number, size: number }?,
}
export type Box = { min: Triple, max: Triple }
export type Panel = { name: string, min: Triple, max: Triple }

local Fit = Config.Cosmetics.Fit
local UP = { 0, 0, 90 } -- a cylinder standing up (Roblox's cylinder runs along X)

-- The classic R15's parts the looks are drawn on (the native block body of server/CharacterArt "walker" has them).
StyleLooks.Nominal = {
	Head = { Fit.Head, Fit.Head, Fit.Head },
	UpperTorso = { 2, 1.6, 1 },
	LowerTorso = { 2, 0.4, 1 },
	LeftUpperArm = { 1, 1.17, 1 },
	RightUpperArm = { 1, 1.17, 1 },
	LeftLowerArm = { 1, 0.53, 1 },
	RightLowerArm = { 1, 0.53, 1 },
} :: { [string]: Triple }

StyleLooks.Hats = { "cap", "beanie", "hardhat", "cowboy", "helmet" }
StyleLooks.Jackets = { "hoodie", "track", "bomber", "puffer", "leather" }
StyleLooks.Decals = { "stripes", "flames", "logo", "checker", "pinstripe" }

-- The art parts of a bike's frame (BikeArt: the tubes, the Cargo Bike's beam and box sides) and of the E-Scooter
-- (ScooterArt: its deck, neck, dropouts and clamp): what its paint covers. The lamps, the reflectors, the steel and
-- the rubber keep their own colours.
StyleLooks.BikeFrame = {
	"TopTube", "DownTube", "SeatTube", "ChainStay-1", "ChainStay1", "SeatStay-1", "SeatStay1", "LowCargoBeam",
	"BoxSide-1", "BoxSide1", "BoxBack",
	"Deck", "Neck", "Dropout-1", "Dropout1", "StemClamp",
}

-- The Courier Vest's cloth (server/CharacterArt/Geometry.luau hivis; its reflective bands and badge stay silver) and
-- each bag's body (server/KitArt/Geometry.luau): name → the share of the colour (a pocket a little darker).
StyleLooks.Vest = { VestL = 1, VestR = 1, VestBack = 1, CollarL = 1, CollarR = 1, PocketL = 0.82, PocketR = 0.82 } :: { [string]: number }
StyleLooks.Bags = {
	bag = { BagBody = 1, BagBottom = 1, BagHandleF = 1, BagHandleB = 1, BagKnot = 1 },
	tote = { ToteBody = 1, ToteSeamF = 0.85, ToteSeamB = 0.85 }, -- (its seams are its narrow sides)
	thermal = { ThermBody = 1 },
	padded = { MessBody = 1 },
	duffel = { DuffBody = 1, DuffPocket = 0.85 },
} :: { [string]: { [string]: number } }

local function add(out: { Piece }, name: string, attach: string, size: Triple, at: Triple, paint: string, turn: Triple?, shape: string?)
	table.insert(out, { name = name, attach = attach, size = size, at = at, paint = paint, turn = turn, shape = shape })
end

-- ── Hats ──────────────────────────────────────────────────────────────────

function StyleLooks.hat(look: string): { Piece }
	local out: { Piece } = {}
	local function cyl(name: string, height: number, diameter: number, y: number, paint: string)
		add(out, name, "Head", { height, diameter, diameter }, { 0, y, 0 }, paint, UP, "Cylinder")
	end
	if look == "cap" then
		-- worn the courier way: the peak at the back (+Z), the snap strap over the forehead
		cyl("CapCrown", 0.36, 1.3, 0.47, "main")
		cyl("CapTop", 0.08, 1.1, 0.68, "main")
		cyl("CapButton", 0.05, 0.16, 0.735, "trim")
		add(out, "CapPeak", "Head", { 0.92, 0.05, 0.56 }, { 0, 0.31, 0.84 }, "trim", { 8, 0, 0 })
		add(out, "CapSnap", "Head", { 0.42, 0.1, 0.03 }, { 0, 0.37, -0.66 }, "trim")
	elseif look == "beanie" then
		cyl("BeanieCuff", 0.16, 1.36, 0.3, "trim")
		cyl("BeanieBody", 0.4, 1.32, 0.5, "main")
		cyl("BeanieTop", 0.1, 1.1, 0.73, "main")
		add(out, "BeaniePom", "Head", { 0.3, 0.3, 0.3 }, { 0, 0.88, 0 }, "trim", nil, "Ball")
	elseif look == "hardhat" then
		cyl("HardBrim", 0.05, 1.6, 0.3, "main")
		cyl("HardShell", 0.42, 1.36, 0.5, "main")
		cyl("HardDome", 0.12, 1.12, 0.76, "main")
		add(out, "HardRidge", "Head", { 0.16, 0.12, 1.24 }, { 0, 0.8, 0 }, "main")
		add(out, "HardPeak", "Head", { 0.9, 0.05, 0.32 }, { 0, 0.31, -0.86 }, "main", { -6, 0, 0 })
		add(out, "HardBadge", "Head", { 0.32, 0.2, 0.02 }, { 0, 0.5, -0.69 }, "trim")
	elseif look == "cowboy" then
		cyl("CowboyBrim", 0.06, 2.1, 0.36, "main")
		for _, side in { -1, 1 } do
			-- the brim's sides rolled up
			add(out, if side < 0 then "CowboyRollL" else "CowboyRollR", "Head", { 0.42, 0.06, 1.4 }, { side * 0.93, 0.43, 0 }, "main", { 0, 0, side * 25 })
		end
		cyl("CowboyBand", 0.1, 1.31, 0.45, "trim")
		cyl("CowboyCrown", 0.5, 1.28, 0.64, "main")
		add(out, "CowboyTop", "Head", { 0.9, 0.08, 1.0 }, { 0, 0.9, 0 }, "main")
		add(out, "CowboyCrease", "Head", { 0.16, 0.05, 0.84 }, { 0, 0.94, 0 }, "shade")
	elseif look == "helmet" then
		cyl("HelmetRim", 0.06, 1.4, 0.3, "trim")
		cyl("HelmetShell", 0.4, 1.38, 0.5, "main")
		cyl("HelmetTop", 0.14, 1.16, 0.76, "main")
		add(out, "HelmetCrest", "Head", { 0.5, 0.1, 1.3 }, { 0, 0.86, 0.02 }, "main")
		for _, side in { -1, 1 } do
			add(out, if side < 0 then "HelmetVentL" else "HelmetVentR", "Head", { 0.07, 0.04, 1.1 }, { side * 0.14, 0.92, 0.02 }, "trim")
		end
		add(out, "HelmetVisor", "Head", { 1.0, 0.05, 0.3 }, { 0, 0.38, -0.8 }, "trim", { -14, 0, 0 })
	else
		error("Unknown hat look: " .. tostring(look))
	end
	return out
end

-- ── Jackets ───────────────────────────────────────────────────────────────

local SIDES: { { string } } = { { "Left", "L" }, { "Right", "R" } }

function StyleLooks.jacket(look: string): { Piece }
	assert(table.find(StyleLooks.Jackets, look), "Unknown jacket look: " .. tostring(look))
	local out: { Piece } = {}
	local T = Fit.Shell
	local front = -(0.5 + T) -- the shell's front face on the torso (the back is +)
	-- The shell: the torso (over the shoulders by T), the waist over the top of the LowerTorso, both arms.
	add(out, "JacketTorso", "UpperTorso", { 2 + 2 * T, 1.6 + T, 1 + 2 * T }, { 0, T / 2, 0 }, "main")
	add(out, "JacketWaist", "LowerTorso", { 2 + 2 * T, 0.3, 1 + 2 * T }, { 0, 0.05, 0 }, "main")
	for _, side in SIDES do
		add(out, `Sleeve{side[2]}`, `{side[1]}UpperArm`, { 1 + 2 * T, 1.17 + T, 1 + 2 * T }, { 0, T / 2, 0 }, "main")
		add(out, `Forearm{side[2]}`, `{side[1]}LowerArm`, { 1 + 2 * T, 0.53, 1 + 2 * T }, { 0, 0, 0 }, "main")
	end
	local rib = { 2 + 2 * T + 0.02, 0.08, 1 + 2 * T + 0.02 }
	local cuff = { 1 + 2 * T + 0.02, 0.08, 1 + 2 * T + 0.02 }
	local function cuffs(paint: string)
		for _, side in SIDES do
			add(out, `Cuff{side[2]}`, `{side[1]}LowerArm`, cuff, { 0, -0.2, 0 }, paint)
		end
	end
	local function zip(paint: string)
		add(out, "Zip", "UpperTorso", { 0.05, 1.45, 0.02 }, { 0, -0.04, front - 0.01 }, paint)
	end
	if look == "hoodie" then
		add(out, "Hood", "UpperTorso", { 1.3, 0.36, 0.36 }, { 0, 0.72, 0.62 }, "main", { -22, 0, 0 })
		add(out, "Pocket", "UpperTorso", { 1.0, 0.4, 0.03 }, { 0, -0.47, front - 0.015 }, "shade")
		for _, x in { -0.16, 0.16 } do
			add(out, if x < 0 then "StringL" else "StringR", "UpperTorso", { 0.04, 0.34, 0.03 }, { x, 0.5, front - 0.015 }, "white")
		end
		add(out, "Hem", "LowerTorso", rib, { 0, -0.08, 0 }, "trim")
		cuffs("trim")
	elseif look == "track" then
		zip("trim")
		add(out, "Hem", "LowerTorso", rib, { 0, -0.08, 0 }, "trim")
		cuffs("trim")
		-- two stripes down the outside of each sleeve, the upper and the lower arm
		for _, side in SIDES do
			local x = (if side[1] == "Left" then -1 else 1) * (0.5 + T + 0.01)
			for n, z in { -0.08, 0.08 } do
				add(out, `Stripe{side[2]}{n}`, `{side[1]}UpperArm`, { 0.02, 1.17 + T, 0.07 }, { x, T / 2, z }, "trim")
				add(out, `StripeLow{side[2]}{n}`, `{side[1]}LowerArm`, { 0.02, 0.53, 0.07 }, { x, 0, z }, "trim")
			end
		end
	elseif look == "bomber" then
		zip("metal")
		add(out, "Hem", "LowerTorso", rib, { 0, -0.08, 0 }, "trim")
		cuffs("trim")
		add(out, "ArmPocket", "LeftUpperArm", { 0.02, 0.3, 0.38 }, { -(0.5 + T + 0.01), 0.12, 0 }, "trim")
		for _, x in { -0.5, 0.5 } do
			add(out, if x < 0 then "WeltL" else "WeltR", "UpperTorso", { 0.42, 0.06, 0.03 }, { x, -0.42, front - 0.015 }, "shade", { 0, 0, if x < 0 then 30 else -30 })
		end
	elseif look == "puffer" then
		zip("dark")
		for n, y in { -0.48, -0.08, 0.32 } do
			add(out, `Quilt{n}`, "UpperTorso", { 2 + 2 * T + 0.04, 0.07, 1 + 2 * T + 0.04 }, { 0, y, 0 }, "shade")
		end
		for _, side in SIDES do
			add(out, `ArmQuilt{side[2]}`, `{side[1]}UpperArm`, { 1 + 2 * T + 0.04, 0.07, 1 + 2 * T + 0.04 }, { 0, -0.05, 0 }, "shade")
			add(out, `ArmQuiltLow{side[2]}`, `{side[1]}LowerArm`, { 1 + 2 * T + 0.04, 0.07, 1 + 2 * T + 0.04 }, { 0, 0.02, 0 }, "shade")
		end
	elseif look == "leather" then
		for _, x in { -1, 1 } do
			add(out, if x < 0 then "LapelL" else "LapelR", "UpperTorso", { 0.32, 0.7, 0.03 }, { x * 0.36, 0.38, front - 0.015 }, "shade", { 0, 0, x * -18 })
		end
		add(out, "Zip", "UpperTorso", { 0.04, 1.3, 0.02 }, { 0.15, -0.12, front - 0.01 }, "metal", { 0, 0, 8 })
		add(out, "Belt", "LowerTorso", rib, { 0, -0.02, 0 }, "shade")
		add(out, "Buckle", "LowerTorso", { 0.22, 0.12, 0.03 }, { 0, -0.02, -(0.5 + T + 0.025) }, "metal")
		for _, side in SIDES do
			add(out, `CuffZip{side[2]}`, `{side[1]}LowerArm`, { 0.04, 0.4, 0.02 }, { 0, -0.04, -(0.5 + T + 0.01) }, "metal")
		end
	end
	return out
end

-- The pieces of a courier look (a hat or a jacket), nil for a colour-only one.
function StyleLooks.courier(def: Config.CosmeticDef): { Piece }?
	if def.slot == "hat" then
		return StyleLooks.hat(def.look)
	elseif def.slot == "jacket" then
		return StyleLooks.jacket(def.look)
	end
	return nil
end

-- The scale of a real body part of `size` against its nominal one (unknown parts: 1). The head is scaled with one
-- factor across and deep (its crowns stay round), clamped to Fit.HeadMin … HeadMax; the others like KitFit.factors.
function StyleLooks.factors(bone: string, size: Triple): Triple
	local nominal = StyleLooks.Nominal[bone]
	if not nominal then
		return { 1, 1, 1 }
	end
	local raw: Triple = {}
	for i = 1, 3 do
		local f = (size[i] or 0) / nominal[i]
		raw[i] = if f == f and f > 0 and f < math.huge then f else 1
	end
	if bone == "Head" then
		local across = math.clamp((raw[1] + raw[3]) / 2, Fit.HeadMin, Fit.HeadMax)
		return { across, math.clamp(raw[2], Fit.HeadMin, Fit.HeadMax), across }
	end
	return { math.clamp(raw[1], 0.5, 2), math.clamp(raw[2], 0.5, 2), math.clamp(raw[3], 0.5, 2) }
end

-- ── Decals ────────────────────────────────────────────────────────────────
-- The chassis' space: X across (+X the right side), Y up, the front at -Z. A decal lies Fit.Lift over its panel's
-- face, Fit.Thick thick, and keeps Fit.Margin (in the face's plane) from every block; a long one is cut into pieces
-- round the blocks (a piece shorter than Fit.MinRun is left out).

local EPS = 1e-4

-- Does the box (lo, hi) touch a block (another panel counts as a block too; `skip` is the panel it lies on)?
local function blocked(lo: Triple, hi: Triple, blocks: { Box }, skip: any?): boolean
	for _, b in blocks do
		if b ~= skip and hi[1] > b.min[1] + EPS and lo[1] < b.max[1] - EPS and hi[2] > b.min[2] + EPS and lo[2] < b.max[2] - EPS
			and hi[3] > b.min[3] + EPS and lo[3] < b.max[3] - EPS then
			return true
		end
	end
	return false
end

-- The free stretches of [z0, z1] for a box spanning `lo` … `hi` on the other two axes (its own z replaced), the
-- in-plane margin `m` on the axis `across` (1 = x for a top decal, 2 = y for a side one).
local function runs(z0: number, z1: number, lo: Triple, hi: Triple, across: number, blocks: { Box }, skip: any?): { { number } }
	local m = Fit.Margin
	local cuts: { { number } } = {}
	local a, b = table.clone(lo), table.clone(hi)
	a[across] -= m
	b[across] += m
	for _, block in blocks do
		if block ~= skip and b[1] > block.min[1] + EPS and a[1] < block.max[1] - EPS and b[2] > block.min[2] + EPS and a[2] < block.max[2] - EPS
			and block.max[3] > z0 and block.min[3] < z1 then
			table.insert(cuts, { block.min[3] - m, block.max[3] + m })
		end
	end
	table.sort(cuts, function(p, q)
		return p[1] < q[1]
	end)
	local out: { { number } } = {}
	local at = z0
	for _, cut in cuts do
		if cut[1] > at then
			table.insert(out, { at, math.min(cut[1], z1) })
		end
		at = math.max(at, cut[2])
		if at >= z1 then
			break
		end
	end
	if at < z1 then
		table.insert(out, { at, z1 })
	end
	local kept: { { number } } = {}
	for _, r in out do
		if r[2] - r[1] >= Fit.MinRun then
			table.insert(kept, r)
		end
	end
	return kept
end

-- The half extents of a box of `size` turned by `turn` (degrees: CFrame.Angles order) on each axis.
local function extents(size: Triple, turn: Triple?): Triple
	local r = turn or { 0, 0, 0 }
	local a, b, c = math.rad(r[1]), math.rad(r[2]), math.rad(r[3])
	local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
	-- the rotation's columns (the piece's own axes in the chassis' space)
	local x = { cb * cc, ca * sc + sa * sb * cc, sa * sc - ca * sb * cc }
	local y = { -cb * sc, ca * cc - sa * sb * sc, sa * cc + ca * sb * sc }
	local z = { sb, -sa * cb, ca * cb }
	local h = { size[1] / 2, size[2] / 2, size[3] / 2 }
	return {
		math.abs(x[1]) * h[1] + math.abs(y[1]) * h[2] + math.abs(z[1]) * h[3],
		math.abs(x[2]) * h[1] + math.abs(y[2]) * h[2] + math.abs(z[2]) * h[3],
		math.abs(x[3]) * h[1] + math.abs(y[3]) * h[2] + math.abs(z[3]) * h[3],
	}
end
StyleLooks.extents = extents

-- A piece's box (lo, hi) in the chassis' space.
local function boxOf(piece: Piece): (Triple, Triple)
	local e = extents(piece.size, piece.turn)
	local at = piece.at
	return { at[1] - e[1], at[2] - e[2], at[3] - e[3] }, { at[1] + e[1], at[2] + e[2], at[3] + e[3] }
end

-- Within the panel's face (the two in-plane axes), `inset` inside its edges?
local function inside(panel: Panel, lo: Triple, hi: Triple, axes: { number }, inset: number): boolean
	for _, i in axes do
		if lo[i] < panel.min[i] + inset - EPS or hi[i] > panel.max[i] - inset + EPS then
			return false
		end
	end
	return true
end

-- Adds the piece when it lies on the panel's face and touches no block; true when added.
local function place(out: { Piece }, piece: Piece, panel: Panel, axes: { number }, blocks: { Box }, skip: any?): boolean
	local lo, hi = boxOf(piece)
	local m = Fit.Margin
	local a, b = table.clone(lo), table.clone(hi)
	for _, i in axes do
		a[i] -= m
		b[i] += m
	end
	if not inside(panel, lo, hi, axes, 0.05) or blocked(a, b, blocks, skip) then
		return false
	end
	piece.attach = "Chassis"
	table.insert(out, piece)
	return true
end

-- The panels of a name: the top ones (from the front back), or one side's (+1 / -1).
local function tops(panels: { Panel }, names: { string }): { Panel }
	local out: { Panel } = {}
	for _, p in panels do
		if table.find(names, p.name) then
			table.insert(out, p)
		end
	end
	table.sort(out, function(a, b)
		return a.min[3] < b.min[3]
	end)
	return out
end

local function side(panels: { Panel }, name: string, s: number): Panel?
	local best: Panel? = nil
	for _, p in panels do
		local middle = (p.min[1] + p.max[1]) / 2
		if p.name == name and middle * s > 0 and (best == nil or (p.max[3] - p.min[3]) > (best.max[3] - best.min[3])) then
			best = p
		end
	end
	return best
end

-- A side decal's x: just outside the panel's outer face on side s.
local function outX(panel: Panel, s: number, lift: number?): number
	local face = if s > 0 then panel.max[1] else panel.min[1]
	return face + s * ((lift or 0) + Fit.Lift + Fit.Thick / 2)
end

local TOPS = { "Hood", "CabRoof", "CargoRoof", "RearDeck" }

local function stripes(out: { Piece }, panels: { Panel }, blocks: { Box }, names: { string }, width: number, offsets: { number }, label: string)
	local t, lift = Fit.Thick, Fit.Lift
	for _, p in tops(panels, names) do
		local w = p.max[1] - p.min[1]
		local c = (p.min[1] + p.max[1]) / 2
		if w < 1.6 then
			continue
		end
		local y = p.max[2] + lift + t / 2
		for _, dx in offsets do
			local x = c + dx
			local lo, hi = { x - width / 2, y - t / 2, 0 }, { x + width / 2, y + t / 2, 0 }
			for _, r in runs(p.min[3] + 0.15, p.max[3] - 0.15, lo, hi, 1, blocks, p) do
				place(out, { name = label, attach = "Chassis", size = { width, t, r[2] - r[1] }, at = { x, y, (r[1] + r[2]) / 2 }, paint = "main" }, p, { 1, 3 }, blocks, p)
			end
		end
	end
end

-- A row of flame tongues from `base` toward +Z (the car's back), on a top panel (axis "top") or a side (axis "side",
-- s = the side), out of a flame body across their roots: each tongue tapers (a wide root, a narrower middle, a pointed
-- tip: a square turned 45°) round a hot core (trim). A tongue that meets a block is cut short before it (left out
-- under 0.5 studs).
local function tongues(out: { Piece }, panel: Panel, blocks: { Box }, axis: string, s: number, spots: { number }, lengths: { number }, width: number, base: number)
	local t = Fit.Thick
	local axes = if axis == "top" then { 1, 3 } else { 2, 3 }
	local function at(across: number, z: number, lift: number): Triple
		if axis == "top" then
			return { across, panel.max[2] + Fit.Lift + t / 2 + lift, z }
		end
		return { outX(panel, s, lift), across, z }
	end
	local function size(across: number, along: number): Triple
		return if axis == "top" then { across, t, along } else { t, across, along }
	end
	local function add(piece: Piece): boolean
		return place(out, piece, panel, axes, blocks, panel)
	end
	local tipTurn: Triple = if axis == "top" then { 0, 45, 0 } else { 45, 0, 0 }
	local tip = width * 0.5
	local reach = tip * 0.55 -- how far the tip's point goes past the tongue's length
	local laid: { number } = {}
	for n, across in spots do
		local want = lengths[n]
		-- cut short at the first block in its way (the tip's point too)
		local lo, hi = boxOf({ name = "", attach = "", size = size(width, want), at = at(across, base + want / 2, 0), paint = "main" })
		local free = runs(base, base + want + reach, lo, hi, if axis == "top" then 1 else 2, blocks, panel)
		local first = free[1]
		if not first or first[1] > base + 1e-3 then
			continue
		end
		local length = math.min(want, first[2] - base - reach)
		if length < 0.5 then
			continue
		end
		if not add({ name = "FlameRoot", attach = "Chassis", size = size(width, length * 0.55), at = at(across, base + length * 0.275, 0), paint = "main" }) then
			continue
		end
		table.insert(laid, across)
		-- the middle runs on to the tip (no gap before its point)
		local from, to = base + length * 0.45, base + length - tip * 0.45
		add({ name = "Flame", attach = "Chassis", size = size(width * 0.62, to - from), at = at(across, (from + to) / 2, 0), paint = "main" })
		add({ name = "FlameTip", attach = "Chassis", size = size(tip, tip), at = at(across, base + length - tip * 0.2, 0), turn = tipTurn, paint = "main" })
		add({ name = "FlameCore", attach = "Chassis", size = size(width * 0.38, length * 0.42), at = at(across, base + 0.05 + length * 0.21, 0.006), paint = "trim" })
	end
	if #laid >= 2 then
		-- the flame body the tongues come out of, across their roots
		local a, b = math.min(table.unpack(laid)) - width / 2, math.max(table.unpack(laid)) + width / 2
		add({ name = "FlameBody", attach = "Chassis", size = size(b - a, 0.4), at = at((a + b) / 2, base + 0.2, 0), paint = "main" })
	end
end

local function flames(out: { Piece }, panels: { Panel }, blocks: { Box })
	-- the hood: five tongues back from its nose
	for _, hood in tops(panels, { "Hood" }) do
		local w = hood.max[1] - hood.min[1]
		local width = math.clamp(w * 0.12, 0.35, 0.75)
		local length = hood.max[3] - hood.min[3] - 0.3 - width * 0.3
		if w >= 2 and length >= 1 then
			local c = (hood.min[1] + hood.max[1]) / 2
			local spots = { c - w * 0.3, c - w * 0.15, c, c + w * 0.15, c + w * 0.3 }
			local lengths = { length * 0.58, length * 0.84, length, length * 0.78, length * 0.54 }
			tongues(out, hood, blocks, "top", 1, spots, lengths, width, hood.min[3] + 0.15)
		end
	end
	-- the sides: three tongues along the cargo side (a van, a truck) or the front fender (a long-nosed car)
	for _, s in { -1, 1 } do
		local cargo = side(panels, "CargoSide", s)
		local fender = side(panels, "FrontFender", s)
		local panel: Panel? = nil
		if cargo and cargo.max[3] - cargo.min[3] >= 4 and cargo.max[2] - cargo.min[2] >= 1.6 then
			panel = cargo
		elseif fender and fender.max[3] - fender.min[3] >= 2 and fender.max[2] - fender.min[2] >= 0.7 then
			panel = fender
		end
		if not panel then
			continue
		end
		local p = panel :: Panel
		local tall = p.max[2] - p.min[2]
		local h = if tall < 1.2 then tall - 0.3 else math.min(1.9, tall * 0.5)
		local y0 = p.min[2] + 0.15
		local rows = if h < 0.8 then 2 else 3
		local width = h / rows * 0.86
		local long = math.min(p.max[3] - p.min[3] - 0.4 - width * 0.3, math.max(2.5, h * 3.4))
		local spots, lengths = {}, {}
		local shares: { number } = if rows == 2 then { 0.8, 1.0 } else { 0.72, 1.0, 0.6 }
		for k, share in shares do
			table.insert(spots, y0 + h * (k - 0.5) / rows)
			table.insert(lengths, long * share)
		end
		tongues(out, p, blocks, "side", s, spots, lengths, width, p.min[3] + 0.2)
	end
end
-- The ZDC roundel (a ring in the trim colour, the face with "ZDC" on it) on both sides: the cargo side's upper back
-- first, else another free spot of it or of the front fender (a smaller one where a big one finds no room); a side with
-- no room for it puts one on the hood instead, else on the cab's roof (lying on it, read from the car's front).
local SPOTS: { { number } } = {
	{ 0.82, 0.72 }, { 0.82, 0.45 }, { 0.18, 0.72 }, { 0.5, 0.8 }, { 0.5, 0.3 }, { 0.18, 0.35 }, { 0.82, 0.2 },
	{ 0.97, 0.5 }, { 0.03, 0.5 }, { 0.65, 0.6 }, { 0.35, 0.6 }, { 0.97, 0.9 }, { 0.03, 0.9 }, { 0.5, 0.05 },
}

local function roundel(out: { Piece }, panel: Panel, blocks: { Box }, d: number, at: Triple, top: boolean, s: number): boolean
	local t = Fit.Thick
	local ring: Piece = { name = "LogoRing", attach = "Chassis", size = { t, d, d }, at = at, turn = if top then UP else nil, shape = "Cylinder", paint = "trim" }
	local lift = if top then { at[1], at[2] + 0.006, at[3] } else { at[1] + s * 0.006, at[2], at[3] }
	local mark: Piece = { name = "LogoFace", attach = "Chassis", size = { t, d * 0.8, d * 0.8 }, at = lift, turn = if top then { 0, 90, 90 } else nil, shape = "Cylinder", paint = "main", text = "ZDC", face = if top or s > 0 then "Right" else "Left" }
	local axes = if top then { 1, 3 } else { 2, 3 }
	local count = #out
	if place(out, ring, panel, axes, blocks, panel) then
		if place(out, mark, panel, axes, blocks, panel) then
			return true
		end
		table.remove(out, count + 1)
	end
	return false
end

local function logo(out: { Piece }, panels: { Panel }, blocks: { Box })
	local missing = 0
	for _, s in { -1, 1 } do
		local done = false
		for _, name in { "CargoSide", "FrontFender" } do
			local p = side(panels, name, s)
			if done or not p then
				continue
			end
			local panel = p :: Panel
			local h, l = panel.max[2] - panel.min[2], panel.max[3] - panel.min[3]
			local big = math.min(math.clamp(h * 0.42, 0.9, 2.6), h - 0.2, l - 0.3)
			for _, d in { big, big * 0.72 } do
				if done or d < 0.55 then
					continue
				end
				for _, spot in SPOTS do
					local z = panel.min[3] + 0.15 + d / 2 + spot[1] * (l - 0.3 - d)
					local y = panel.min[2] + 0.1 + d / 2 + spot[2] * (h - 0.2 - d)
					if roundel(out, panel, blocks, d, { outX(panel, s), y, z }, false, s) then
						done = true
						break
					end
				end
			end
		end
		if not done then
			missing += 1
		end
	end
	if missing == 0 then
		return
	end
	-- the hood instead (else the cab's roof): lying on it, its face up, the text read from the front of the car
	for _, top in tops(panels, { "Hood", "CabRoof" }) do
		local w, l = top.max[1] - top.min[1], top.max[3] - top.min[3]
		local big = math.min(2.2, w * 0.4, l - 0.4)
		for _, d in { big, big * 0.72 } do
			if d < 0.55 then
				continue
			end
			local x = (top.min[1] + top.max[1]) / 2
			local y = top.max[2] + Fit.Lift + Fit.Thick / 2
			for _, share in { 0.5, 0.3, 0.7, 0.15, 0.85 } do
				local z = top.min[3] + 0.2 + d / 2 + share * (l - 0.4 - d)
				if roundel(out, top, blocks, d, { x, y, z }, true, 1) then
					return
				end
			end
		end
	end
end

-- Bands along both sides (the checker, the pinstripes): `candidates(panel)` gives the bands to try, each a list of
-- rows { y0, y1 }; the first whose every row runs free along at least half the panel is laid (cut round the blocks).
local function sideBands(out: { Piece }, panels: { Panel }, blocks: { Box }, names: { string }, candidates: (Panel) -> { { { number } } }, label: string, checker: boolean)
	local minRun = if checker then 1.2 else Fit.MinRun
	for _, s in { -1, 1 } do
		for _, name in names do
			local p = side(panels, name, s)
			if not p then
				continue
			end
			local panel = p :: Panel
			local x = outX(panel, s)
			local z0, z1 = panel.min[3] + 0.15, panel.max[3] - 0.15
			for _, band in candidates(panel) do
				local laid: { { row: { number }, found: { { number } } } } = {}
				local ok = true
				for _, row in band do
					local found = runs(z0, z1, { x - Fit.Thick / 2, row[1], 0 }, { x + Fit.Thick / 2, row[2], 0 }, 2, blocks, panel)
					local free = 0
					for _, r in found do
						if r[2] - r[1] >= minRun then
							free += r[2] - r[1]
						end
					end
					if free < (z1 - z0) * 0.5 then
						ok = false
						break
					end
					table.insert(laid, { row = row, found = found })
				end
				if not ok then
					continue
				end
				for _, entry in laid do
					local row, found = entry.row, entry.found
					for _, r in found do
						if r[2] - r[1] < minRun then
							continue
						end
						local piece: Piece = { name = label, attach = "Chassis", size = { Fit.Thick, row[2] - row[1], r[2] - r[1] }, at = { x, (row[1] + row[2]) / 2, (r[1] + r[2]) / 2 }, paint = "main" }
						if checker then
							piece.checker = { rows = 2, size = (row[2] - row[1]) / 2 }
							piece.face = if s > 0 then "Right" else "Left"
						end
						place(out, piece, panel, { 2, 3 }, blocks, panel)
					end
				end
				break
			end
		end
	end
end

-- The decal's pieces on a vehicle: `panels` its painted panels by name, `blocks` every other visible part (both as
-- boxes in the chassis' space). An unknown look or a vehicle with no room: no pieces.
function StyleLooks.decals(look: string, panels: { Panel }, blocks: { Box }): { Piece }
	local out: { Piece } = {}
	-- every panel is a block for the decals laid on the others
	local all: { Box } = table.clone(blocks)
	for _, p in panels do
		table.insert(all, p :: any)
	end
	if look == "stripes" then
		stripes(out, panels, all, TOPS, 0.45, { -0.38, 0.38 }, "Stripe")
	elseif look == "flames" then
		flames(out, panels, all)
	elseif look == "logo" then
		logo(out, panels, all)
	elseif look == "checker" then
		sideBands(out, panels, all, { "CargoSide", "FrontFender" }, function(panel: Panel): { { { number } } }
			local h = panel.max[2] - panel.min[2]
			local square = math.min(Fit.Checker, (h - 0.3) / 2)
			if square < 0.15 or panel.max[3] - panel.min[3] < 1.5 then
				return {}
			end
			local top = panel.max[2] - 0.12
			local low = panel.min[2] + 0.2
			return { { { top - 2 * square, top } }, { { low, low + 2 * square } } }
		end, "Checker", true)
	elseif look == "pinstripe" then
		sideBands(out, panels, all, { "CargoSide", "FrontFender" }, function(panel: Panel): { { { number } } }
			local h = panel.max[2] - panel.min[2]
			if h < 0.6 then
				return {}
			end
			local bands: { { { number } } } = {}
			for _, share in { 0.55, 0.35, 0.75, 0.2, 0.88 } do
				local y = panel.min[2] + 0.1 + (h - 0.4) * share
				table.insert(bands, { { y - 0.025, y + 0.025 }, { y + 0.1, y + 0.15 } })
			end
			return bands
		end, "Pinstripe", false)
		for _, hood in tops(panels, { "Hood" }) do
			local w = hood.max[1] - hood.min[1]
			if w >= 2 then
				stripes(out, { hood }, all, { "Hood" }, 0.05, { -(w / 2 - 0.35), w / 2 - 0.35 }, "Pinstripe")
			end
		end
	end
	return out
end

return StyleLooks
