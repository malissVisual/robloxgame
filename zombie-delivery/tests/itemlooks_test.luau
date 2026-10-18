-- Logic test of the 3D pictures' camera (shared/ItemLooks.luau, Config.ItemModel) in the standalone Luau CLI: the
-- collection book's cards and the warehouse's STOCK list and picker look at a copy of a piece's model from the 3/4
-- angle. Every piece the houses hold (shared/FurnitureLooks.luau's catalogue, the collectibles too, built by the real
-- builder on the recorder tools/fixtures/item-mock.luau) gets a sound box and a camera that fits it; the framing's
-- maths on a plain box. 10.6: the city's inventory looks are gone.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local M = require("./ItemMock")
local Config = require("./Config")
local ItemLooks = require("./ItemLooks")
local FurnitureLooks = require("./FurnitureLooks")

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
local function length(a: { number }, b: { number }): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end

-- Every piece: its box holds its Root (the piece's own size) and the camera stands off it, above it, on its front right.
do
	local bad: { string } = {}
	local count = 0
	for _, id in FurnitureLooks.Order do
		count += 1
		local model = FurnitureLooks.build(id)
		local lo, hi = ItemLooks.bounds(model)
		local root = model:FindFirstChild("Root") :: any
		local size = if root then root.Size else nil
		local span = math.max(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
		local sound = finite(span) and span > 0 and size ~= nil
			and hi[1] - lo[1] >= size.X - 1e-3 and hi[2] - lo[2] >= size.Y - 1e-3 and hi[3] - lo[3] >= size.Z - 1e-3
		local eye, centre = ItemLooks.frame(lo, hi, 1)
		local distance = length(eye, centre)
		local framed = finite(distance) and distance > span * 0.5 and eye[2] > centre[2] and eye[1] > centre[1] and eye[3] < centre[3]
		if not (sound and framed) then
			table.insert(bad, id)
		end
	end
	check(`every piece of the catalogue ({count}) has a sound box and a camera on its front right, above it`, count > 0 and #bad == 0, table.concat(bad, ", "))
	local collectibles = 0
	for _, id in FurnitureLooks.Collectibles do
		local lo, hi = ItemLooks.bounds(FurnitureLooks.build(id))
		if hi[1] > lo[1] then
			collectibles += 1
		end
	end
	check(`the collectibles too ({collectibles})`, collectibles == #FurnitureLooks.Collectibles and collectibles > 0)
end

-- An empty model: a unit box (nothing to measure, still a camera).
do
	local lo, hi = ItemLooks.bounds(M.Instance.new("Model"))
	check("an empty model: a unit box", lo[1] == -0.5 and hi[2] == 0.5)
end

-- The framing's maths.
do
	local lo, hi = { -1, -1, -1 }, { 1, 1, 1 }
	local eye, centre = ItemLooks.frame(lo, hi, 1)
	local still = length(eye, centre)
	local wide = ItemLooks.frame(lo, hi, 2)
	check("a wide frame lets the camera closer", length(wide, centre) <= still)
	local big = ItemLooks.frame({ -2, -2, -2 }, { 2, 2, 2 }, 1)
	check("a box twice as big: the camera twice as far", math.abs(length(big, centre) - 2 * still) < 1e-6)
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
