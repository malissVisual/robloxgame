--!strict
-- The 3/4 camera on a small 3D picture: the collection book's cards (client/CollectionBookUi.luau) and the warehouse's
-- STOCK list and stand picker (client/WarehouseUi.luau) put a copy of a piece's model (shared/FurnitureLooks.luau, a
-- collectible too) in a ViewportFrame and look at it from Config.ItemModel's angle. Pure maths on the model's parts;
-- nothing runs per frame. 10.6: the city's inventory looks (its guns, the bat, the fists, the consumables, the bags,
-- the vests and the cargo, and the 3D picture client/ItemModel.luau drew of them) are gone with the city.
--
--   ItemLooks.bounds(model)            its parts' box: the low and the high corner ({ x, y, z })
--   ItemLooks.frame(lo, hi, aspect)    the camera for that box: where it looks from and at ({ x, y, z } each) at
--                                      Config.ItemModel's 3/4 angle
--
-- tests/itemlooks_test.luau frames the real furniture with it.

local Config = require(script.Parent.Config)

local ItemLooks = {}

type V = { number }

local LOOK = Config.ItemModel

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
-- that the box fills Fill of the frame (`aspect`: its width over its height). Returns the eye and the box's middle.
function ItemLooks.frame(lo: V, hi: V, aspect: number): (V, V)
	local c = { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }
	local hx, hy, hz = (hi[1] - lo[1]) / 2, (hi[2] - lo[2]) / 2, (hi[3] - lo[3]) / 2
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
