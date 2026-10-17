-- 10.1, the courier you make (shared/CharacterLooks.luau, Config.Characters): every list sane (unique ids, names, colours
-- in range; the hats and the jackets StyleLooks'), the default one of each list's ids; clean (junk, wrong types, a
-- name trimmed, too short, too long, control characters), random (every id from its list, a made courier), the body's
-- colours, and every combination of hair × hat × top × face built into pieces on real R15 parts, sized, painted with a
-- known paint, uniquely named in its group, the hair under a hat below the crown's top; your own avatar: nothing welded.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local CharacterLooks = require("./CharacterLooks")
local StyleLooks = require("./StyleLooks")
local Config = require("./Config")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local C = Config.Characters

-- ── The lists ──────────────────────────────────────────────────────────────
do
	local problems = {}
	for _, entry in CharacterLooks.Fields do
		local seen = {}
		for _, option in entry.list do
			if seen[option.id] or type(option.name) ~= "string" or option.name == "" then
				table.insert(problems, `{entry.field}.{option.id}`)
			end
			seen[option.id] = true
			for _, c in { option.rgb or { 0, 0, 0 }, option.trim or { 0, 0, 0 } } do
				if #c ~= 3 or c[1] < 0 or c[1] > 255 or c[2] < 0 or c[2] > 255 or c[3] < 0 or c[3] > 255 then
					table.insert(problems, `{entry.field}.{option.id} colour`)
				end
			end
		end
		if not CharacterLooks.option(entry.field, (C.Default :: any)[entry.field]) then
			table.insert(problems, `default {entry.field}`)
		end
	end
	check("every list: unique ids, a name, colours 0 … 255; the default one of each list's ids", #problems == 0, table.concat(problems, ", "))
	local colours = true
	for _, field in { "skin", "hairColor", "hatColor", "topColor", "pants" } do
		for _, entry in CharacterLooks.Fields do
			if entry.field == field then
				for _, option in entry.list do
					colours = colours and option.rgb ~= nil
				end
			end
		end
	end
	check("…every colour list has a colour on each option", colours)
	local hats = true
	for _, option in C.Hats do
		hats = hats and (option.id == "none" or table.find(StyleLooks.Hats, option.id) ~= nil)
	end
	local tops = true
	for _, option in C.Tops do
		tops = tops and (option.id == "tee" or option.id == "long" or table.find(StyleLooks.Jackets, option.id) ~= nil)
	end
	check("…the hats are StyleLooks' (or none), the tops a T-shirt, long sleeves or StyleLooks' jackets", hats and tops)
	check("…two bases: a made courier and your own avatar", CharacterLooks.option("base", "custom") ~= nil and CharacterLooks.option("base", "own") ~= nil)
end

-- ── clean ──────────────────────────────────────────────────────────────────
do
	local d = CharacterLooks.default()
	local function same(a: any, b: any): boolean
		for _, entry in CharacterLooks.Fields do
			if a[entry.field] ~= b[entry.field] then
				return false
			end
		end
		return true
	end
	check("clean(nil), clean(junk): the default", same(CharacterLooks.clean(nil), d) and same(CharacterLooks.clean("x"), d) and same(CharacterLooks.clean(5), d))
	local mixed = CharacterLooks.clean({ base = "own", skin = "nope", hair = 7, hairColor = "pink", hat = "cowboy", top = { "x" }, extra = "beard", name = "  Pavel   the   Mover  " })
	check("…a valid field kept, a bad one the default's", mixed.base == "own" and mixed.skin == d.skin and mixed.hair == d.hair and mixed.hairColor == "pink"
		and mixed.hat == "cowboy" and mixed.top == d.top and mixed.extra == "beard", `{mixed.skin} {mixed.hair}`)
	check("…its name trimmed and its spaces squeezed", mixed.name == "Pavel the Mover", mixed.name)
	check("name: too short / not text: none", CharacterLooks.name("a") == nil and CharacterLooks.name("   ") == nil and CharacterLooks.name(42) == nil)
	local long = CharacterLooks.name(string.rep("ž", 40)) or ""
	check(`name: too long cut to {Config.SaveSlots.NameMax} letters (whole UTF-8 ones)`, utf8.len(long) == Config.SaveSlots.NameMax, utf8.len(long))
	check("name: control characters dropped", CharacterLooks.name("Ma\nrk\0") == "Mark", CharacterLooks.name("Ma\nrk\0"))
	check("name: not UTF-8: none", CharacterLooks.name("\255\254ab") == nil)
end

-- ── random ─────────────────────────────────────────────────────────────────
do
	local ok = true
	for _, roll in { function(_n: number): number return 1 end, function(n: number): number return n end, function(n: number): number return n + 5 end } do
		local look = CharacterLooks.random(roll)
		ok = ok and look.base == "custom"
		for _, entry in CharacterLooks.Fields do
			ok = ok and CharacterLooks.option(entry.field, (look :: any)[entry.field]) ~= nil
		end
	end
	check("random: a made courier, every field one of its list's (even a roll out of range)", ok)
end

-- ── The body's colours ─────────────────────────────────────────────────────
do
	local look = CharacterLooks.clean({ skin = "deep", topColor = "teal", pants = "khaki" })
	local c = CharacterLooks.colors(look)
	local skin = (CharacterLooks.option("skin", "deep") :: any).rgb
	local top = (CharacterLooks.option("topColor", "teal") :: any).rgb
	local pants = (CharacterLooks.option("pants", "khaki") :: any).rgb
	local function eq(a: { number }, b: { number }): boolean
		return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
	end
	check("colors: the head and the arms the skin, the torso the top, the legs the trousers", eq(c.HeadColor, skin) and eq(c.LeftArmColor, skin)
		and eq(c.RightArmColor, skin) and eq(c.TorsoColor, top) and eq(c.LeftLegColor, pants) and eq(c.RightLegColor, pants))
	local groups = 0
	for _, field in CharacterLooks.Groups do
		groups += 1
		check(`…{field} is one of them`, c[field] ~= nil)
	end
	check("Groups: the 15 parts of the R15 body", groups == 15)
end

-- ── The pieces ─────────────────────────────────────────────────────────────
do
	local bones = { Head = true, UpperTorso = true, LowerTorso = true, LeftUpperArm = true, RightUpperArm = true, LeftLowerArm = true, RightLowerArm = true }
	local paints = { main = true, trim = true, shade = true, dark = true, metal = true, white = true }
	local problems = {}
	local combos = 0
	for _, hair in C.Hair do
		for _, hat in C.Hats do
			for _, top in C.Tops do
				for _, extra in C.Extras do
					combos += 1
					local look = CharacterLooks.clean({ hair = hair.id, hat = hat.id, top = top.id, extra = extra.id })
					for _, group in CharacterLooks.parts(look) do
						local names = {}
						for _, piece in group.pieces do
							local where = `{hair.id}/{hat.id}/{top.id}/{extra.id} {group.name}.{piece.name}`
							if not bones[piece.attach] then
								table.insert(problems, where .. " on " .. piece.attach)
							end
							if piece.size[1] <= 0 or piece.size[2] <= 0 or piece.size[3] <= 0 then
								table.insert(problems, where .. " size")
							end
							if not paints[piece.paint] then
								table.insert(problems, where .. " paint " .. piece.paint)
							end
							if names[piece.name] then
								table.insert(problems, where .. " twice")
							end
							names[piece.name] = true
							if group.name == "LookHair" and hat.id ~= "none" and piece.at[2] + piece.size[2] / 2 > 0.6 then
								table.insert(problems, where .. " above the hat")
							end
						end
						if type(group.def.color) ~= "table" or #group.def.color ~= 3 then
							table.insert(problems, `{group.name} colour`)
						end
					end
				end
			end
		end
	end
	check(`every combination ({combos}): pieces on R15 parts, sized, a known paint, one of each name; hair under a hat below its top`, #problems == 0,
		table.concat(problems, ", ", 1, math.min(#problems, 6)))
	local plain = CharacterLooks.parts(CharacterLooks.clean({ hair = "none", hat = "none", top = "tee", extra = "none" }))
	local names = {}
	for _, group in plain do
		table.insert(names, group.name)
	end
	check("a bald courier in a T-shirt: the top and the belt only", table.concat(names, ",") == "LookTop,LookBelt", table.concat(names, ","))
	local full = CharacterLooks.parts(CharacterLooks.clean({ hair = "afro", hat = "cap", top = "hoodie", extra = "beard" }))
	names = {}
	for _, group in full do
		table.insert(names, group.name)
	end
	check("…an afro, a cap, a hoodie and a beard: the hair, the hat, the top, the belt, the face", table.concat(names, ",") == "LookHair,LookHat,LookTop,LookBelt,LookExtra", table.concat(names, ","))
	check("…the hoodie is StyleLooks' (its hood)", (function(): boolean
		for _, piece in full[3].pieces do
			if piece.name == "Hood" then
				return true
			end
		end
		return false
	end)())
	check("…the hat's colour and trim the hat colour's", full[2].def.color[1] == (CharacterLooks.option("hatColor", "orange") :: any).rgb[1]
		and full[2].def.trim ~= nil)
	check("your own avatar: nothing welded on", #CharacterLooks.parts(CharacterLooks.clean({ base = "own", hair = "afro", hat = "cap" })) == 0)
	check("a hat hides the afro's top (puffs below it instead)", (function(): boolean
		for _, piece in CharacterLooks.hair("afro", true) do
			if piece.name == "HairAfro" then
				return false
			end
		end
		return #CharacterLooks.hair("afro", true) > 0
	end)())
	check("bald: no hair pieces", #CharacterLooks.hair("none", false) == 0 and #CharacterLooks.hair("none", true) == 0)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
