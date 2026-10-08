-- 6.12.2, the spawn's corner and the shoes (Config.GearStall, Map.Shops.bags / supplies, Map.LastStop,
-- Config.Goal.BoardSpot; Config.RetiredKit's noShoes, shared/Transport.luau retiredRefunds / packRefund,
-- shared/KitFit.luau): the gear stall's two counters (ZDC Bags, Last Stop Supplies) side by side on the depot's block in
-- the safe zone, clear of the spawn pad, the scooter rack, the JOBS spot round the job board, the garage terminal and
-- Marge, their radius the stall's and not the yard's; Last Stop's old block an ordinary building's; the Running Shoes
-- gone and paid back once. Run with tests/run_tests.py.
local Config = require("./Config")
local Map = require("./Map")
local Transport = require("./Transport")
local KitFit = require("./KitFit")
local Career = require("./Career")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- ── The gear stall ─────────────────────────────────────────────────────────

local D, S = Map.Depot, Config.GearStall
local bags, gear = Map.Shops.bags, Map.Shops.supplies
check("both counters are shops with the stall's radius", bags ~= nil and gear ~= nil and bags.radius == S.Radius and gear.radius == S.Radius
	and Map.shopRadius("bags") == S.Radius and Map.shopRadius("supplies") == S.Radius)
check("the names stay: ZDC Bags and Last Stop Supplies", bags.name == "ZDC Bags" and gear.name == "Last Stop Supplies")
check("side by side on the stall's front: BAGS to the north, GEAR to the south", bags.x == gear.x and bags.x == D.x + S.X + S.Depth / 2
	and math.abs(gear.z - bags.z - 2 * S.Counter) < 1e-9 and math.abs((bags.z + gear.z) / 2 - (D.z + S.Z)) < 1e-9)
check("Config.BagShop is the BAGS counter (in the depot's studs)", bags.x == D.x + Config.BagShop.X and bags.z == D.z + Config.BagShop.Z and Config.BagShop.Radius == S.Radius)
check("room for two counters and the partition", S.Width >= 4 * S.Counter and S.Width / 2 - S.Counter >= 5)

-- The stall's footprint with its awning (the front +3.6 studs), in the depot's studs.
local x0, x1 = S.X - S.Depth / 2 - 0.5, S.X + S.Depth / 2 + 3.6
local z0, z1 = S.Z - S.Width / 2 - 0.5, S.Z + S.Width / 2 + 0.5
local onBlock = true
for _, corner in { { x0, z0 }, { x0, z1 }, { x1, z0 }, { x1, z1 } } do
	local d, i, j = Map.blockAt(D.x + corner[1], D.z + corner[2])
	onBlock = onBlock and d ~= nil and d.id == "downtown" and i == D.i and j == D.j and Map.isSafe(D.x + corner[1], D.z + corner[2])
		and math.abs(corner[1]) < Config.City.BlockSize / 2 - 2 and math.abs(corner[2]) < Config.City.BlockSize / 2 - 2
end
check("the whole stall on the depot's block, in the safe zone, off the kerb", onBlock)
local function overlaps(ax0: number, az0: number, ax1: number, az1: number): boolean
	return ax0 < x1 and x0 < ax1 and az0 < z1 and z0 < az1
end
-- the depot's hall: its open front 9 studs north of the middle (World buildDepot: backZ + depth), its walls ±40
check("clear of the depot's hall", not overlaps(-40, -55, 40, -9))
check("clear of the spawn pad (0, 26; 10 × 10) and its radius not over it", not overlaps(-5, 21, 5, 31) and (function()
	for _, shop in { bags, gear } do
		local dx, dz = shop.x - D.x, shop.z - (D.z + 26)
		if math.sqrt(dx * dx + dz * dz) - 5 * math.sqrt(2) <= S.Radius then
			return false
		end
	end
	return true
end)())
local rack = Config.Rental.SpawnRack
local half = rack.slots * rack.pitch / 2
check("clear of the scooter rack", not overlaps(rack.x - half - 2, rack.z - 3, rack.x + half + 2, rack.z + 3))
-- the JOBS spot: the booth round the job board (server/JobsSpot.luau: 25 wide, 7.6 out into the yard, the bench and the
-- parcels 19 studs to its west), in the depot's studs
local board = Config.Goal.BoardSpot
check("clear of the JOBS spot round the job board", not overlaps(board[1] - 19.5, board[2] - 3.5, board[1] + 13, board[2] + 8))
local function far(x: number, z: number): number
	local best = math.huge
	for _, shop in { bags, gear } do
		best = math.min(best, math.sqrt((shop.x - D.x - x) ^ 2 + (shop.z - D.z - z) ^ 2))
	end
	return best
end
local marge = Config.Tutorial.NpcSpot
check("its radius short of the job board, Marge and the garage terminal", far(board[1], board[2]) > S.Radius + 5 and far(marge[1], marge[2]) > S.Radius + 5 and far(18, -25) > S.Radius + 20,
	`{far(board[1], board[2])} {far(marge[1], marge[2])}`)
check("its radius covers its counter (a customer anywhere along it)", math.sqrt((S.Width / 4) ^ 2 + 6 ^ 2) < S.Radius)
check("but not the whole yard (the spawn, the yard's middle)", far(0, 26) > S.Radius + 10 and far(0, 10) > S.Radius)
check("the landmarks follow the counters (the GPS, the map, the location tag)", (function()
	local found = 0
	for _, landmark in Map.Landmarks do
		local shop = Map.Shops[landmark.id]
		if (landmark.id == "bags" or landmark.id == "supplies") and shop and landmark.x == shop.x and landmark.z == shop.z and landmark.kind == "shop" then
			found += 1
		end
	end
	return found == 2
end)())

-- ── Last Stop's old building ───────────────────────────────────────────────

local L = Map.LastStop
check("Last Stop's old block stays special (its dice as before, no lots)", Map.special("downtown", L.i, L.j) == "supplies" and L.x == L.i * Map.Cell and L.z == L.j * Map.Cell
	and #Map.lotsAt("downtown", L.i, L.j) == 0)
check("no shop on it any more", (function()
	for _, shop in Map.Shops do
		local d, i, j = Map.blockAt(shop.x, shop.z)
		if d and d.id == "downtown" and i == L.i and j == L.j then
			return false
		end
	end
	return true
end)())

-- ── The Running Shoes, retired ─────────────────────────────────────────────

check("no Running Shoes in the kit", Transport.findKit("shoes") == nil)
local retired = nil
for _, def in Config.RetiredKit do
	if def.id == "shoes" then
		retired = def
	end
end
check("retired at their price, $250, with their own save flag", retired ~= nil and retired.price == 250 and retired.flag == "noShoes" and retired.name == "Running Shoes")
local money, names = Transport.packRefund({ shoes = true, bag = true, backpack = true }, "noShoes")
check("their refund alone: $250 (the backpacks' flag apart)", money == 250 and #names == 1 and names[1] == "Running Shoes", money)
local a = Transport.retiredRefunds({ money = 1200, noPacks = true, noJacket = true, kit = { shoes = true, bag = true, hivis = true } })
check("a 6.12.1 save with the shoes: $250 back, once", a.noShoes == 250 and a.noPacks == nil and a.noJacket == nil and a.noShoes ~= nil)
local all = Transport.retiredRefunds({ money = 10, kit = { shoes = true, jacket = true, backpack = true } })
check("an old save with all the retired kit: each flag its own", all.noShoes == 250 and all.noJacket == 300 and all.noPacks == 150)
check("paid back already (noShoes): nothing again", next(Transport.retiredRefunds({ money = 1, noPacks = true, noJacket = true, noShoes = true, kit = { shoes = true } })) == nil)
check("no shoes: nothing", next(Transport.retiredRefunds({ money = 1, noPacks = true, noJacket = true, kit = { bag = true, kevlar = true } })) == nil)
check("a false entry, a lock-only record (a new player) or a broken save: nothing", next(Transport.retiredRefunds({ money = 1, noPacks = true, noJacket = true, kit = { shoes = false } })) == nil
	and next(Transport.retiredRefunds({ kit = { shoes = true } })) == nil and next(Transport.retiredRefunds({ money = 1, kit = "shoes" })) == nil)
local words = string.gsub(Config.Courier.ShoeRefund, "{money}", "$250")
check("Marge's words name the shoes and the money", string.find(words, "Running Shoes", 1, true) ~= nil and string.find(words, "$250", 1, true) ~= nil, words)
check("an old save's shoes are never worn and make nobody faster", (KitFit.outfit({ shoes = true }) :: any).shoes == nil and Transport.speedMult({ shoes = true }) == 1)
check("no level reward gives them (level 4: the Thermal Delivery Bag)", (function()
	for level = 2, 20 do
		local reward = Career.reward(level)
		if reward and reward.kit == "shoes" then
			return false
		end
	end
	return (Career.kitOf(Career.reward(4)) :: any).id == "thermal"
end)())
check("the shops never mention them", (function()
	for _, landmark in Map.Landmarks do
		if string.find(string.lower(landmark.description), "shoe", 1, true) then
			return false
		end
	end
	return true
end)())

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
