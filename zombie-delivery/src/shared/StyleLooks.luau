--!strict
-- The hats' and the jackets' geometry of the courier you make (the character creator: shared/CharacterLooks.luau picks
-- them, shared/StyleBuild.luau makes the parts, on the player's body and on the creator's mannequin), pure data. Studs.
--
--   StyleLooks.hat(look)        a hat's pieces on the Head, drawn on the classic R15 head (Config.Cosmetics.Fit.Head,
--                               1.2 every way, its middle at 0; the face looks down -Z, the top at +0.6). Crowns are
--                               upright cylinders a little wider than the head, so the hat sits on it.
--   StyleLooks.jacket(look)     a jacket's pieces: thin shells over the UpperTorso, the LowerTorso and the four arm
--                               parts (each part's own nominal size, StyleLooks.Nominal, + Fit.Shell a side) and their
--                               details (a hood, cuffs, a zip, stripes …), drawn on the classic R15 body
--   StyleLooks.factors(bone, size)  the x / y / z scale of a real body part against StyleLooks.Nominal (a head: one
--                               factor across and deep, so the crowns stay round; clamped like shared/KitFit.luau)
--   StyleLooks.Hats / Jackets   the looks there are (Config.Characters' hats and tops name them)
-- Every piece: { name, attach (a body part), size, at, turn? (degrees, CFrame.Angles order), shape? ("Cylinder" |
-- "Ball" | "Wedge"), paint ("main" | "trim" | "shade" | "dark" | "metal" | "white") }.
-- Pure Luau (tests/characterlooks_test.luau). 10.6: the city's STYLE shop is gone: its looks as worn cosmetics, the
-- Courier Vest's and the bags' dyes, the bikes' paint and the cars' decals.

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
}

local Fit = Config.Cosmetics.Fit
local UP = { 0, 0, 90 } -- a cylinder standing up (Roblox's cylinder runs along X)

-- The classic R15's parts the looks are drawn on.
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

return StyleLooks
