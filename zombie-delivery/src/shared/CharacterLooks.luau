--!strict
-- 10.1, the courier you make (Config.Characters; the start screen's character creator, client/CharacterCreator.luau):
-- a look checked, rolled and turned into what the body wears, pure data. server/CourierAvatar.luau puts a look on the
-- player's body (its colours through a HumanoidDescription, its pieces through shared/StyleBuild.luau's
-- StyleBuild.character); the creator's preview builds the same pieces on its mannequin, so what you pick is what
-- everybody sees. Studs on Roblox's classic R15 (shared/StyleLooks.luau's Nominal: the head 1.2 every way, its middle
-- at 0, the face looking down -Z, its top at +0.6).
--
--   CharacterLooks.default() -> Look            Config.Characters.Default (a copy)
--   CharacterLooks.clean(raw) -> Look           every field one of its list's ids, else the default's (a save's look,
--                                               a client's pick: never trusted); its name through CharacterLooks.name
--   CharacterLooks.random(roll) -> Look         a made courier of random parts (roll(n): a whole number 1 … n)
--   CharacterLooks.option(field, id) -> LookOption?   the option of a look's field ("skin", "hair" …)
--   CharacterLooks.Fields                       the fields in the creator's order, with their Config.Characters list
--   CharacterLooks.custom(look) -> boolean      a made courier (else the player's own Roblox avatar)
--   CharacterLooks.colors(look) -> { [field]: RGB }   the body's colours as a HumanoidDescription's fields (HeadColor,
--                                               TorsoColor, LeftArmColor …: the skin, the top, the trousers)
--   CharacterLooks.Groups                       each R15 part → the colour field that paints it (the preview's mannequin)
--   CharacterLooks.parts(look) -> { Group }     what is welded on: { name, def (a CosmeticDef: its colours), pieces }
--   CharacterLooks.hair(style, hatted) / top(style) / extra(id) -> { Piece }   the pieces of one choice
--   CharacterLooks.name(raw) -> string?          a courier's name trimmed (Config.SaveSlots.NameMin … NameMax letters,
--                                               no control characters), before Roblox's filter (server/SaveSlots.luau)
-- Pure Luau (tests/characterlooks_test.luau).

local Config = require(script.Parent.Config)
local StyleLooks = require(script.Parent.StyleLooks)

local CharacterLooks = {}

export type Look = {
	base: string,
	skin: string,
	hair: string,
	hairColor: string,
	hat: string,
	hatColor: string,
	top: string,
	topColor: string,
	pants: string,
	extra: string,
	name: string?, -- (the courier's name, filtered by Roblox before it is kept: server/SaveSlots.luau; nil: the player's)
}
export type Group = { name: string, def: Config.CosmeticDef, pieces: { StyleLooks.Piece } }

local C = Config.Characters
local T = Config.Cosmetics.Fit.Shell

-- The fields in the creator's order and their lists.
CharacterLooks.Fields = {
	{ field = "base", list = C.Bases },
	{ field = "skin", list = C.Skins },
	{ field = "hair", list = C.Hair },
	{ field = "hairColor", list = C.HairColors },
	{ field = "hat", list = C.Hats },
	{ field = "hatColor", list = C.Colors },
	{ field = "top", list = C.Tops },
	{ field = "topColor", list = C.Colors },
	{ field = "pants", list = C.Pants },
	{ field = "extra", list = C.Extras },
} :: { { field: string, list: { Config.LookOption } } }

local LISTS: { [string]: { Config.LookOption } } = {}
for _, entry in CharacterLooks.Fields do
	LISTS[entry.field] = entry.list
end

-- Each R15 part and the HumanoidDescription colour that paints it.
CharacterLooks.Groups = {
	Head = "HeadColor",
	UpperTorso = "TorsoColor",
	LowerTorso = "TorsoColor",
	LeftUpperArm = "LeftArmColor",
	LeftLowerArm = "LeftArmColor",
	LeftHand = "LeftArmColor",
	RightUpperArm = "RightArmColor",
	RightLowerArm = "RightArmColor",
	RightHand = "RightArmColor",
	LeftUpperLeg = "LeftLegColor",
	LeftLowerLeg = "LeftLegColor",
	LeftFoot = "LeftLegColor",
	RightUpperLeg = "RightLegColor",
	RightLowerLeg = "RightLegColor",
	RightFoot = "RightLegColor",
} :: { [string]: string }

function CharacterLooks.option(field: string, id: any): Config.LookOption?
	local list = LISTS[field]
	if not list or type(id) ~= "string" then
		return nil
	end
	for _, option in list do
		if option.id == id then
			return option
		end
	end
	return nil
end

function CharacterLooks.default(): Look
	return table.clone(C.Default) :: any
end

function CharacterLooks.clean(raw: any): Look
	local out = CharacterLooks.default()
	local given = if type(raw) == "table" then raw else {}
	for _, entry in CharacterLooks.Fields do
		local value = given[entry.field]
		if CharacterLooks.option(entry.field, value) then
			(out :: any)[entry.field] = value
		end
	end
	out.name = CharacterLooks.name(given.name)
	return out
end

function CharacterLooks.random(roll: (number) -> number): Look
	local out = CharacterLooks.default()
	for _, entry in CharacterLooks.Fields do
		if entry.field ~= "base" then
			local n = math.clamp(math.floor(roll(#entry.list)), 1, #entry.list);
			(out :: any)[entry.field] = entry.list[n].id
		end
	end
	out.base = "custom"
	return out
end

function CharacterLooks.custom(look: Look): boolean
	return look.base ~= "own"
end

local function rgb(field: string, id: string): { number }
	local option = CharacterLooks.option(field, id)
	local fallback = CharacterLooks.option(field, (C.Default :: any)[field])
	return table.clone((option and option.rgb) or (fallback and fallback.rgb) or { 128, 128, 128 })
end

function CharacterLooks.colors(look: Look): { [string]: { number } }
	local skin, top, pants = rgb("skin", look.skin), rgb("topColor", look.topColor), rgb("pants", look.pants)
	return {
		HeadColor = skin,
		LeftArmColor = skin,
		RightArmColor = skin,
		TorsoColor = top,
		LeftLegColor = pants,
		RightLegColor = table.clone(pants),
	}
end

local function add(out: { StyleLooks.Piece }, name: string, attach: string, size: { number }, at: { number }, paint: string, turn: { number }?, shape: string?)
	table.insert(out, { name = name, attach = attach, size = size, at = at, paint = paint, turn = turn, shape = shape })
end

-- ── The hair ───────────────────────────────────────────────────────────────
-- On the head; under a hat (`hatted`) only what shows below its crown: the back, the sides, a tail.

function CharacterLooks.hair(style: string, hatted: boolean): { StyleLooks.Piece }
	local out: { StyleLooks.Piece } = {}
	if style == "none" then
		return out
	end
	local function sides(height: number, y: number, depth: number, x: number)
		add(out, "HairSideL", "Head", { 0.1, height, depth }, { -x, y, 0.06 }, "main")
		add(out, "HairSideR", "Head", { 0.1, height, depth }, { x, y, 0.06 }, "main")
	end
	local function short()
		if hatted then
			add(out, "HairBack", "Head", { 1.3, 0.42, 0.12 }, { 0, 0.2, 0.6 }, "main")
			sides(0.3, 0.22, 1.0, 0.63)
		else
			add(out, "HairTop", "Head", { 1.3, 0.2, 1.3 }, { 0, 0.6, 0.02 }, "main")
			add(out, "HairBack", "Head", { 1.3, 0.62, 0.14 }, { 0, 0.32, 0.6 }, "main")
			sides(0.42, 0.4, 1.14, 0.63)
		end
	end
	if style == "short" then
		short()
		if not hatted then
			add(out, "HairFringe", "Head", { 1.3, 0.16, 0.12 }, { 0, 0.52, -0.6 }, "main")
		end
	elseif style == "buzz" then
		if not hatted then
			add(out, "HairTop", "Head", { 1.24, 0.06, 1.24 }, { 0, 0.62, 0 }, "main")
		end
		add(out, "HairBack", "Head", { 1.24, if hatted then 0.36 else 0.5, 0.05 }, { 0, if hatted then 0.22 else 0.36, 0.61 }, "main")
		add(out, "HairSideL", "Head", { 0.04, 0.3, 1.0 }, { -0.61, if hatted then 0.22 else 0.44, 0.05 }, "main")
		add(out, "HairSideR", "Head", { 0.04, 0.3, 1.0 }, { 0.61, if hatted then 0.22 else 0.44, 0.05 }, "main")
	elseif style == "spiky" then
		short()
		if not hatted then
			for n, s in { { -0.36, -0.2, -15, 15 }, { 0, -0.26, -20, 0 }, { 0.36, -0.2, -15, -15 }, { -0.2, 0.26, 15, 10 }, { 0.2, 0.26, 15, -10 } } do
				add(out, `HairSpike{n}`, "Head", { 0.26, 0.38, 0.26 }, { s[1], 0.84, s[2] }, "main", { s[3], 0, s[4] })
			end
		end
	elseif style == "long" then
		if not hatted then
			add(out, "HairTop", "Head", { 1.3, 0.2, 1.3 }, { 0, 0.6, 0.02 }, "main")
			add(out, "HairFringe", "Head", { 1.3, 0.16, 0.12 }, { 0, 0.52, -0.6 }, "main")
		end
		add(out, "HairLong", "Head", { 1.34, if hatted then 1.0 else 1.3, 0.16 }, { 0, if hatted then -0.15 else 0, 0.62 }, "main")
		sides(if hatted then 0.8 else 1.0, if hatted then 0.0 else 0.12, 1.0, 0.65)
	elseif style == "ponytail" then
		short()
		add(out, "HairTie", "Head", { 0.26, 0.26, 0.26 }, { 0, 0.3, 0.74 }, "main", nil, "Ball")
		add(out, "HairTail", "Head", { 0.28, 0.85, 0.28 }, { 0, -0.18, 0.84 }, "main", { 12, 0, 0 })
	elseif style == "bun" then
		short()
		if not hatted then
			add(out, "HairBun", "Head", { 0.62, 0.62, 0.62 }, { 0, 0.86, 0.3 }, "main", nil, "Ball")
		end
	elseif style == "afro" then
		if hatted then
			add(out, "HairPuffL", "Head", { 0.5, 0.7, 0.9 }, { -0.62, 0.2, 0.15 }, "main", nil, "Ball")
			add(out, "HairPuffR", "Head", { 0.5, 0.7, 0.9 }, { 0.62, 0.2, 0.15 }, "main", nil, "Ball")
			add(out, "HairPuffBack", "Head", { 1.2, 0.7, 0.5 }, { 0, 0.2, 0.55 }, "main", nil, "Ball")
		else
			add(out, "HairAfro", "Head", { 1.8, 1.55, 1.75 }, { 0, 0.6, 0.28 }, "main", nil, "Ball")
		end
	end
	return out
end

-- ── The top ────────────────────────────────────────────────────────────────
-- A T-shirt's and a long-sleeved top's sleeves and collar (the torso is the top's colour already: CharacterLooks.colors);
-- a jacket is StyleLooks' (its shells over the torso and the arms).

local SIDES: { { string } } = { { "Left", "L" }, { "Right", "R" } }

function CharacterLooks.top(style: string): { StyleLooks.Piece }
	if table.find(StyleLooks.Jackets, style) then
		return StyleLooks.jacket(style)
	end
	local out: { StyleLooks.Piece } = {}
	local front = -(0.5 + T)
	add(out, "Collar", "UpperTorso", { 0.72, 0.06, 0.03 }, { 0, 0.76, front - 0.01 }, "trim")
	for _, side in SIDES do
		if style == "long" then
			add(out, `Sleeve{side[2]}`, `{side[1]}UpperArm`, { 1 + 2 * T, 1.17 + T, 1 + 2 * T }, { 0, T / 2, 0 }, "main")
			add(out, `Forearm{side[2]}`, `{side[1]}LowerArm`, { 1 + 2 * T, 0.53, 1 + 2 * T }, { 0, 0, 0 }, "main")
			add(out, `Cuff{side[2]}`, `{side[1]}LowerArm`, { 1 + 2 * T + 0.02, 0.08, 1 + 2 * T + 0.02 }, { 0, -0.2, 0 }, "trim")
		else
			add(out, `Sleeve{side[2]}`, `{side[1]}UpperArm`, { 1 + 2 * T, 0.62, 1 + 2 * T }, { 0, 0.275 + T / 2, 0 }, "main")
			add(out, `SleeveBand{side[2]}`, `{side[1]}UpperArm`, { 1 + 2 * T + 0.02, 0.06, 1 + 2 * T + 0.02 }, { 0, -0.01, 0 }, "trim")
		end
	end
	return out
end

-- The trousers' top over the LowerTorso (a T-shirt or a long top: the whole of it; under a jacket: a band below its
-- waist) and a buckle.
local function belt(style: string): { StyleLooks.Piece }
	local out: { StyleLooks.Piece } = {}
	local jacket = table.find(StyleLooks.Jackets, style) ~= nil
	if jacket then
		add(out, "Belt", "LowerTorso", { 2 + 2 * T, 0.12, 1 + 2 * T }, { 0, -0.14, 0 }, "main")
	else
		add(out, "Belt", "LowerTorso", { 2 + 2 * T, 0.42, 1 + 2 * T }, { 0, 0, 0 }, "main")
		add(out, "Buckle", "LowerTorso", { 0.22, 0.12, 0.03 }, { 0, 0.06, -(0.5 + T + 0.02) }, "metal")
	end
	return out
end

-- ── The face ───────────────────────────────────────────────────────────────
-- Over the classic face (its eyes about 0.12 above the head's middle, its smile below): glasses, sunglasses, a
-- moustache, a beard (the hair's colour).

function CharacterLooks.extra(id: string): { StyleLooks.Piece }
	local out: { StyleLooks.Piece } = {}
	local z = -0.63
	local function frames(paint: string)
		for _, side in { -1, 1 } do
			local s = if side < 0 then "L" else "R"
			add(out, `GlassTop{s}`, "Head", { 0.34, 0.045, 0.04 }, { side * 0.24, 0.235, z }, paint)
			add(out, `GlassBottom{s}`, "Head", { 0.34, 0.045, 0.04 }, { side * 0.24, 0.005, z }, paint)
			add(out, `GlassOuter{s}`, "Head", { 0.045, 0.27, 0.04 }, { side * 0.41, 0.12, z }, paint)
			add(out, `GlassInner{s}`, "Head", { 0.045, 0.27, 0.04 }, { side * 0.07, 0.12, z }, paint)
			add(out, `GlassTemple{s}`, "Head", { 0.04, 0.04, 0.66 }, { side * 0.62, 0.2, -0.31 }, paint)
		end
		add(out, "GlassBridge", "Head", { 0.1, 0.04, 0.04 }, { 0, 0.16, z }, paint)
	end
	local function moustache()
		add(out, "Moustache", "Head", { 0.5, 0.1, 0.06 }, { 0, -0.12, z }, "main")
		add(out, "MoustacheL", "Head", { 0.12, 0.16, 0.06 }, { -0.24, -0.17, z }, "main", { 0, 0, 20 })
		add(out, "MoustacheR", "Head", { 0.12, 0.16, 0.06 }, { 0.24, -0.17, z }, "main", { 0, 0, -20 })
	end
	if id == "glasses" then
		frames("dark")
	elseif id == "sunglasses" then
		frames("dark")
		for _, side in { -1, 1 } do
			add(out, if side < 0 then "LensL" else "LensR", "Head", { 0.3, 0.2, 0.025 }, { side * 0.24, 0.12, -0.615 }, "dark")
		end
	elseif id == "moustache" then
		moustache()
	elseif id == "beard" then
		moustache()
		add(out, "BeardChin", "Head", { 0.84, 0.28, 0.14 }, { 0, -0.47, -0.56 }, "main")
		add(out, "BeardJawL", "Head", { 0.12, 0.62, 0.9 }, { -0.61, -0.22, -0.12 }, "main")
		add(out, "BeardJawR", "Head", { 0.12, 0.62, 0.9 }, { 0.61, -0.22, -0.12 }, "main")
	end
	return out
end

-- ── Everything welded on ───────────────────────────────────────────────────

-- A colour's stand-in CosmeticDef (shared/StyleBuild.luau paints a piece with its def: "main", "trim", "shade" …).
local function def(id: string, slot: string, look: string, color: { number }, trim: { number }?, material: string?): Config.CosmeticDef
	return { id = id, name = id, slot = slot, look = look, price = 0, color = color, trim = trim, material = material, description = "" }
end

function CharacterLooks.parts(look: Look): { Group }
	local out: { Group } = {}
	if not CharacterLooks.custom(look) then
		return out
	end
	local hatted = look.hat ~= "none"
	local hairColor = rgb("hairColor", look.hairColor)
	local hair = CharacterLooks.hair(look.hair, hatted)
	if #hair > 0 then
		table.insert(out, { name = "LookHair", def = def("look_hair", "hair", look.hair, hairColor, nil, "SmoothPlastic"), pieces = hair })
	end
	if hatted then
		local cloth = CharacterLooks.option("hatColor", look.hatColor)
		local color = rgb("hatColor", look.hatColor)
		table.insert(out, { name = "LookHat", def = def("look_hat", "hat", look.hat, color, cloth and cloth.trim), pieces = StyleLooks.hat(look.hat) })
	end
	local cloth = CharacterLooks.option("topColor", look.topColor)
	table.insert(out, { name = "LookTop", def = def("look_top", "jacket", look.top, rgb("topColor", look.topColor), cloth and cloth.trim), pieces = CharacterLooks.top(look.top) })
	table.insert(out, { name = "LookBelt", def = def("look_belt", "jacket", "belt", rgb("pants", look.pants)), pieces = belt(look.top) })
	local extra = CharacterLooks.extra(look.extra)
	if #extra > 0 then
		table.insert(out, { name = "LookExtra", def = def("look_extra", "hair", look.extra, hairColor, nil, "SmoothPlastic"), pieces = extra })
	end
	return out
end

-- ── The name ───────────────────────────────────────────────────────────────

function CharacterLooks.name(raw: any): string?
	if type(raw) ~= "string" or not utf8.len(raw) then
		return nil
	end
	local text = string.gsub(raw, "%c", "")
	text = string.gsub(text, "%s+", " ")
	text = string.match(text, "^%s*(.-)%s*$") or ""
	local length = utf8.len(text) or 0
	if length < Config.SaveSlots.NameMin then
		return nil
	end
	if length > Config.SaveSlots.NameMax then
		text = string.sub(text, 1, (utf8.offset(text, Config.SaveSlots.NameMax + 1) or (#text + 1)) - 1)
	end
	return text
end

return CharacterLooks
