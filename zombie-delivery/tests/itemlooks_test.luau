-- Logic test of 6.22's looks (shared/ItemLooks.luau, Config.ItemModel) in the standalone Luau CLI: every thing the
-- bottom bar and BAG & ITEMS show (every gun, the bat, the fists, every consumable, every bag and vest, every cargo
-- look the game makes pieces of) has a model of its own, built by the real builders (ItemLooks, shared/GunModels.luau,
-- shared/CargoLooks.luau, shared/KitArt.luau) on a recorder (tools/fixtures/item-mock.luau): none is left as an icon,
-- each stays within Config.ItemModel.MaxParts parts, its parts are sound, and the camera's framing fits it.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local ItemLooks = require("./ItemLooks")
local GunModels = require("./GunModels")
local CargoLooks = require("./CargoLooks")
local KitArt = require("./KitArt")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local LOOK = Config.ItemModel
local function finite(x: number): boolean
	return x == x and x > -math.huge and x < math.huge
end

local keys = ItemLooks.all()
local inAll: { [string]: boolean } = {}
for _, key in keys do
	inAll[key] = true
end

-- Coverage: Config's every gun, consumable, kit and cargo look is in the list (no thing left as an icon).
do
	local missing: { string } = {}
	local function want(key: string)
		if not inAll[key] then
			table.insert(missing, key)
		end
	end
	for _, def in Config.Weapons do
		want(`gun:{def.id}`)
	end
	for _, def in Config.Items do
		want(`item:{def.id}`)
	end
	for _, def in Config.Kit do
		want(if def.melee then `melee:{def.melee}` else `kit:{def.id}`)
	end
	for _, kind in Config.Cargo.Kinds do
		want(`cargo:{kind.look}`)
	end
	for look in Config.Cargo.LightLooks do
		want(`cargo:{look}`)
	end
	for _, business in (Config :: any).Jobs.Businesses do
		want(`cargo:{business.look}`)
	end
	want("fists")
	-- the bottom bar's hands: the fists, the starter bag (no bag yet: faint), the starter gun (no gun yet: faint)
	want(`kit:{Config.Courier.BagKit}`)
	want(`gun:{Config.Arms.Starter}`)
	check(`every gun, item, kit and cargo look is listed ({#keys} things)`, #missing == 0, table.concat(missing, ", "))
end

-- Every gun has its own look (GunModels: none falls back to the pistol), every cargo look a model of its own (not the
-- unknown look's crate).
do
	local guns, cargo = {}, {}
	for _, def in Config.Weapons do
		if not GunModels.has(def.id) then
			table.insert(guns, def.id)
		end
	end
	for _, key in keys do
		local kind, id = ItemLooks.parse(key)
		if kind == "cargo" and not CargoLooks.Looks[id] and not ItemLooks.Cargo[id] then
			table.insert(cargo, id)
		end
	end
	check("every gun has its own model (GunModels)", #guns == 0, table.concat(guns, ", "))
	check("every cargo look has its own model (CargoLooks, a horse here; not the unknown look's crate)", #cargo == 0, table.concat(cargo, ", "))
end

-- Build every look: a look of its own, at most MaxParts sound parts, a box and a camera that fit.
local most, mostKey, total = 0, "", 0
for _, key in keys do
	check(`{key} has a look`, ItemLooks.has(key))
	local ok, model = pcall(ItemLooks.build, key)
	if not ok then
		check(`{key} builds`, false, model)
		continue
	end
	local parts, sound = 0, true
	local why = ""
	for _, obj in model:GetDescendants() do
		if obj:IsA("BasePart") then
			parts += 1
			local s, p = obj.Size, obj.CFrame.Position
			if not (finite(s.X) and finite(s.Y) and finite(s.Z) and s.X > 0 and s.Y > 0 and s.Z > 0 and finite(p.X) and finite(p.Y) and finite(p.Z)) then
				sound = false
				why = obj.Name
			end
			if obj.Anchored ~= true and model.Name == "ItemLook" and key:sub(1, 4) ~= "gun:" and key:sub(1, 6) ~= "cargo:" then
				sound = false
				why = `{obj.Name} not anchored`
			end
		end
	end
	total += parts
	if parts > most then
		most, mostKey = parts, key
	end
	check(`{key}: {parts} parts (1 .. {LOOK.MaxParts}), all sound`, parts >= 1 and parts <= LOOK.MaxParts and sound, why)
	check(`{key}: named and marked`, model.Name == "ItemLook" and model:GetAttribute("Look") == key)
	local lo, hi = ItemLooks.bounds(model)
	local eye, centre = ItemLooks.frame(lo, hi, 1)
	local ex, ey, ez = eye[1] - centre[1], eye[2] - centre[2], eye[3] - centre[3]
	local distance = math.sqrt(ex * ex + ey * ey + ez * ez)
	local span = math.max(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
	check(`{key}: framed (the camera {string.format("%.1f", distance)} studs off, above it, on its front right)`,
		finite(distance) and distance > span * 0.5 and ey > 0 and ex > 0 and ez < 0)
end
print(`(the most parts: {mostKey}, {most}; {total} parts in {#keys} looks)`)

-- The bags are KitArt's own art; the vests KitArt's (the Courier Vest the character art's pieces) on a form.
do
	for id in KitArt.bags do
		local model = ItemLooks.build(`kit:{id}`)
		local names: { [string]: boolean } = {}
		for _, obj in model:GetDescendants() do
			names[obj.Name] = true
		end
		local same = true
		for _, piece in KitArt.pieces(id) do
			same = same and names[piece.name] == true
		end
		check(`kit:{id} is KitArt's own bag (every piece)`, same)
	end
	local used: { [string]: boolean } = {}
	for _, id in { "bag", "tote", "thermal", "padded", "duffel", "kevlar", "heavy" } do
		for _, piece in KitArt.pieces(id) do
			used[piece.finish] = true
		end
	end
	local unknown: { string } = {}
	for finish in used do
		if not ItemLooks.Finish[finish] then
			table.insert(unknown, finish)
		end
	end
	check("ItemLooks.Finish has every finish the bags and vests use", #unknown == 0, table.concat(unknown, ", "))
	local vest = ItemLooks.build("kit:hivis")
	check("the Courier Vest: its red panels and reflectors on a form", vest:FindFirstChild("VestL") ~= nil and vest:FindFirstChild("BackReflector") ~= nil and vest:FindFirstChild("Form") ~= nil)
	local heavy = ItemLooks.build("kit:heavy")
	check("the heavy armour's guards on the form's arms", heavy:FindFirstChild("LeftUpperArmGuard") ~= nil and heavy:FindFirstChild("FormArm") ~= nil)
end

-- The guns turn their barrels across the view, the bat lies across, the cargo is the server's own piece.
do
	local pistol = ItemLooks.build("gun:pistol")
	local lo, hi = ItemLooks.bounds(pistol)
	check("a gun lies across the view (wider than it is tall)", (hi[1] - lo[1]) > (hi[2] - lo[2]))
	local pizza = ItemLooks.build("cargo:pizza")
	check("a pizza stack is the server's (its boxes, the light look's real size)", pizza:FindFirstChild("Box") ~= nil and pizza:GetAttribute("Scale") == Config.Cargo.LightScale)
	local fist = ItemLooks.build("fists")
	check("the fists: four knuckles and a red cuff", fist:FindFirstChild("Knuckle4") ~= nil and fist:FindFirstChild("Cuff") ~= nil)
	local bat = ItemLooks.build("melee:bat")
	local blo, bhi = ItemLooks.bounds(bat)
	check("the bat: its length from Config.Melee.BatLook", bhi[1] - blo[1] > Config.Melee.BatLook.Length * 0.6 and bat:FindFirstChild("Barrel") ~= nil)
end

-- Keys and the framing's maths.
do
	check("a key and back", ItemLooks.key("item", "medkit") == "item:medkit" and ItemLooks.key("fists") == "fists" and select(2, ItemLooks.parse("cargo:pizza")) == "pizza")
	check("an unknown thing has no look and does not build", not ItemLooks.has("item:nothing") and not ItemLooks.has("car:van") and not pcall(ItemLooks.build, "item:nothing"))
	local lo, hi = { -1, -1, -1 }, { 1, 1, 1 }
	local eye, centre = ItemLooks.frame(lo, hi, 1)
	local still = math.sqrt((eye[1] - centre[1]) ^ 2 + (eye[2] - centre[2]) ^ 2 + (eye[3] - centre[3]) ^ 2)
	local turning = ItemLooks.frame(lo, hi, 1, true)
	local far = math.sqrt((turning[1] - centre[1]) ^ 2 + (turning[2] - centre[2]) ^ 2 + (turning[3] - centre[3]) ^ 2)
	check("a turning model's camera stands back for its whole footprint", far > still)
	local wide = ItemLooks.frame(lo, hi, 2)
	local nearer = math.sqrt((wide[1] - centre[1]) ^ 2 + (wide[2] - centre[2]) ^ 2 + (wide[3] - centre[3]) ^ 2)
	check("a wide frame lets the camera closer", nearer <= still)
	check("the camera's angle: from the front right, looking down", eye[1] > 0 and eye[2] > 0 and eye[3] < 0)
	-- every corner of the box inside the view (its right and up over its depth within the field of view)
	local look = { centre[1] - eye[1], centre[2] - eye[2], centre[3] - eye[3] }
	local n = math.sqrt(look[1] ^ 2 + look[2] ^ 2 + look[3] ^ 2)
	look = { look[1] / n, look[2] / n, look[3] / n }
	local right = { -look[3], 0, look[1] }
	local rn = math.sqrt(right[1] ^ 2 + right[3] ^ 2)
	right = { right[1] / rn, 0, right[3] / rn }
	local up = { right[2] * look[3] - right[3] * look[2], right[3] * look[1] - right[1] * look[3], right[1] * look[2] - right[2] * look[1] }
	local t = math.tan(math.rad(LOOK.Fov / 2))
	local worst = 0
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local v = { x - eye[1], y - eye[2], z - eye[3] }
				local depth = v[1] * look[1] + v[2] * look[2] + v[3] * look[3]
				local sx = math.abs(v[1] * right[1] + v[3] * right[3]) / depth
				local sy = math.abs(v[1] * up[1] + v[2] * up[2] + v[3] * up[3]) / depth
				worst = math.max(worst, sx / t, sy / t)
			end
		end
	end
	check("the whole box fits the view (at most the frame's edge)", worst <= 1 and worst > 0.5, worst)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECKS FAILED`)
end
