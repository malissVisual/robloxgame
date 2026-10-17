-- 10.4 THE WAREHOUSE IN TWO (Config.Showroom; shared/CollectionRules.luau, shared/WarehouseLayout.luau): the collection
-- HALL earns, the SHOWROOM sells. The rules: a stand's area by its number; only the hall's pieces count in the income,
-- every piece on a stand counts as shown; a showroom piece sells for the showroom's factor (never a broken one's scrap),
-- its view says its area; FOR SALE signs only in the showroom (the save's clean); the showroom's stands past its count
-- back to the stock (fitStands); the migration of a save from before the split (its pieces on stands stay in the hall,
-- earning as before; its signs come down); the hall's bonuses (the room sets, Collector's corner on Epic and Legendary
-- only). The layout, every level: the showroom's plinths as many as Config's Most, by the door, inside the walls, on
-- none of the hall's stands, the desk or the way in, each holding most pieces (a sofa on a runway plinth turned to its
-- walk, never a bed), plates S1 …, the carpet and both areas' signs; a visitor reaches every showroom piece from the door
-- (shared/Visitors.luau's hall with every stand in the way); standAt finds a turned plinth. Run with tests/run_tests.py.
local Config = require("./Config")
local Rules = require("./CollectionRules")
local WarehouseLayout = require("./WarehouseLayout")
local Visitors = require("./Visitors")
local SandboxMap = require("./SandboxMap")
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
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local BASE = Config.Showroom.Base
local function piece(uid: string, item: string, stand: number?, condition: number?, extra: { [string]: any }?): Rules.Entry
	local e: any = { uid = uid, item = item, variant = 1, condition = condition or 1, name = item, stand = stand, got = 0 }
	for k, v in extra or {} do
		e[k] = v
	end
	return e
end

-- ── The areas ───────────────────────────────────────────────────────────────
check("a stand's area by its number: 1 … the hall's, past Config.Showroom.Base the showroom's", Rules.area(3) == "hall" and Rules.area(BASE + 1) == "show" and Rules.area(nil) == nil
	and Rules.isShow(BASE + 2) and not Rules.isShow(BASE) and not Rules.isShow(nil) and Rules.ShowBase == BASE and WarehouseLayout.ShowBase == BASE)

-- ── Income only from the hall, prices up in the showroom ───────────────────
do
	local hall = piece("1-1", "piano", 1)
	local show = piece("1-2", "piano", BASE + 1)
	local stock = piece("1-3", "piano", nil)
	local totals = Rules.totals({ hall, show, stock })
	check("totals: three pianos, two on stands (shown), the income only the hall's one", totals.count == 3 and totals.shown == 2 and near(totals.income, Rules.income(hall)))
	local factor = Rules.showFactor({ sandboxUpgrades = {} })
	check("the showroom's factor: SellBonus (no Sales pitch), × 1.06 a rank of it", near(factor, Config.Showroom.SellBonus)
		and near(Rules.showFactor({ sandboxUpgrades = { haggle = 2 } }), Config.Showroom.SellBonus * 1.12))
	check("a showroom piece sells for the factor × its price, a hall or stock piece for its price", Rules.sell(show, nil, factor) == math.floor(Rules.sell(hall) * factor + 0.5)
		and Rules.sell(hall, nil, factor) == Rules.sell(hall) and Rules.sell(stock, nil, factor) == Rules.sell(stock))
	local broken = piece("1-4", "piano", BASE + 2, 0.05)
	check("… never a broken one's scrap", Rules.sell(broken, nil, factor) == Rules.sell(broken))
	local view = Rules.view(show, 1, nil, factor)
	check("its view: area \"show\", the price × the factor, base the market-free price, its income what it would earn in the hall", view.area == "show"
		and view.price == Rules.sell(show, nil, factor) and view.base == Rules.sell(show) and near(view.income, math.floor(Rules.income(show) * 100 + 0.5) / 100)
		and Rules.view(hall).area == "hall" and Rules.view(stock).area == nil)
	check("totals' sell with the factor: the showroom piece's price × it", totals.sell < Rules.totals({ hall, show, stock }, 1, nil, factor).sell)
end

-- ── The hall's bonuses ──────────────────────────────────────────────────────
do
	-- three different kitchen pieces in the hall make a set; the showroom's and a second of an item don't count
	local items: { [string]: { string } } = {}
	for id, def in FurnitureLooks.Items do
		items[def.room] = items[def.room] or {}
		table.insert(items[def.room], id)
	end
	for _, list in items do
		table.sort(list)
	end
	local k = items.kitchen
	local hall = { piece("a", k[1], 1), piece("b", k[2], 2), piece("c", k[3], 3) }
	check("a room set: three different pieces of one room in the hall", Rules.sets(hall) == 1)
	check("… a duplicate or a showroom piece is no third", Rules.sets({ piece("a", k[1], 1), piece("b", k[2], 2), piece("c", k[2], 3) }) == 0
		and Rules.sets({ piece("a", k[1], 1), piece("b", k[2], 2), piece("c", k[3], BASE + 1) }) == 0)
	check("… only stands the player has (open)", Rules.sets(hall, function(stand: number): boolean
		return stand <= 2
	end) == 0)
	local levels = { lights = 2, sets = 2, rare = 1 }
	local bonus = Rules.bonus({ sandboxUpgrades = levels, collection = { entries = hall } }, hall)
	check("the hall's Bonus: Hall spotlights × (1 + Room sets × the sets), Collector's corner apart", bonus.sets == 0 or near(bonus.all, 1.21 * (1 + 0.08 * bonus.sets)))
	-- (a Garage has 2 hall stands: give the profile a warehouse whose three stands are open)
	local big = Rules.bonus({ sandboxUpgrades = { lights = 2, sets = 2, rare = 1, warehouse = 2 } }, hall)
	check("… with the stands open: one set, all ×1.21 × 1.08, rare ×1.2", big.sets == 1 and near(big.all, 1.21 * 1.08) and near(big.rare, 1.2))
	local epic = piece("e", "jukebox", 1)
	local common = piece("f", "box", 2)
	check("Collector's corner only on an Epic or Legendary piece", near(Rules.income(epic, big), Rules.income(epic) * big.all * big.rare)
		and near(Rules.income(common, big), Rules.income(common) * big.all))
	check("a plain boost (a number) as before", near(Rules.income(common, 1.5), Rules.income(common) * 1.5))
end

-- ── The save ────────────────────────────────────────────────────────────────
do
	local raw = { entries = {
		{ uid = "1-1", item = "piano", condition = 1, stand = 1, sale = 900, got = 1 },
		{ uid = "1-2", item = "sofa", condition = 1, stand = BASE + 1, sale = 700, got = 1 },
		{ uid = "1-3", item = "tv", condition = 1, stand = BASE + 2, got = 1 },
	}, nextUid = 4 }
	local clean = Rules.clean(raw)
	check("clean: a FOR SALE sign only on a showroom stand", clean.entries[1].sale == nil and clean.entries[2].sale == 700 and clean.entries[3].stand == BASE + 2)
	local moved = Rules.fitStands(clean, 2, nil, 1)
	check("fitStands: a showroom piece past the showroom's count back to the stock (its sign with it), the rest stays", moved == 1 and clean.entries[3].stand == nil
		and clean.entries[2].stand == BASE + 1 and clean.entries[1].stand == 1)
	local old = { money = 10, collectionKept = true, collection = { entries = {
		{ uid = "1-1", item = "piano", condition = 1, stand = 1, sale = 900, got = 1 },
		{ uid = "1-2", item = "sofa", condition = 1, stand = 2, got = 1 },
		{ uid = "1-3", item = "tv", condition = 1, got = 1 },
	}, nextUid = 4 } }
	local migrated = Rules.fromSave(old)
	check("migration: a save from before the showroom keeps every piece on its stand (the hall's: their income as before), the signs down",
		migrated.entries[1].stand == 1 and migrated.entries[2].stand == 2 and migrated.entries[3].stand == nil and migrated.entries[1].sale == nil
		and near(Rules.totals(migrated.entries).income, Rules.income(migrated.entries[1]) + Rules.income(migrated.entries[2])))
	local kept = Rules.fromSave({ money = 10, collectionKept = true, showroomKept = true, collection = raw })
	check("… a save with the flag keeps its showroom and its signs", kept.entries[2].stand == BASE + 1 and kept.entries[2].sale == 700 and kept.entries[3].stand == BASE + 2)
	check("… run again on what it gave, the same", #Rules.fromSave({ money = 10, collectionKept = true, collection = migrated }).entries == 3)
end

-- ── The layout, every level ─────────────────────────────────────────────────
local plot = SandboxMap.Plots[1]
local function overlaps(a: WarehouseLayout.Stand, bx0: number, bx1: number, bz0: number, bz1: number, grow: number): boolean
	local hx, hz = WarehouseLayout.extent(a)
	return a.x - hx < bx1 + grow and a.x + hx > bx0 - grow and a.z - hz < bz1 + grow and a.z + hz > bz0 - grow
end
for level = 1, #Config.Warehouse.Levels do
	local site = WarehouseLayout.site(plot, level) :: SandboxMap.Plot
	local L = `level {level} {WarehouseLayout.level(level).name}`
	local most = WarehouseLayout.showCapacity(level)
	local shows = WarehouseLayout.showStands(site)
	check(`{L}: {most} showroom stands (Config's Most), numbered past the base`, most == Config.Showroom.Levels[level].Most and #shows == most and shows[1].index == BASE + 1 and shows[1].show == true)
	local inside = WarehouseLayout.inside(site)
	local path = WarehouseLayout.doorPath(site)
	local desk = WarehouseLayout.terminal(site)
	local bad: { string } = {}
	local hall = WarehouseLayout.stands(site, WarehouseLayout.capacity(level))
	for _, s in shows do
		local hx, hz = WarehouseLayout.extent(s)
		if s.x - hx < inside.x0 - 1e-6 or s.x + hx > inside.x1 + 1e-6 or s.z - hz < inside.z0 - 1e-6 or s.z + hz > inside.z1 + 1e-6 then
			table.insert(bad, `S{s.index - BASE} outside the walls`)
		end
		if overlaps(s, path.x0, path.x1, path.z0, path.z1, -1e-6) and overlaps(s, path.x0, path.x1, WarehouseLayout.receiving(site).z0, inside.z1, -1e-6) then
			table.insert(bad, `S{s.index - BASE} in the receiving zone`)
		end
		if overlaps(s, desk.x - desk.sx / 2, desk.x + desk.sx / 2, desk.z - desk.sz / 2, desk.z + desk.sz / 2, 0.5) then
			table.insert(bad, `S{s.index - BASE} at the desk`)
		end
		for _, h in hall do
			local ex, ez = WarehouseLayout.extent(h)
			if overlaps(s, h.x - ex, h.x + ex, h.z - ez, h.z + ez, 0) then
				table.insert(bad, `S{s.index - BASE} on hall stand {h.index}`)
			end
		end
		for _, o in shows do
			if o ~= s then
				local ex, ez = WarehouseLayout.extent(o)
				if overlaps(s, o.x - ex, o.x + ex, o.z - ez, o.z + ez, 0) then
					table.insert(bad, `S{s.index - BASE} on S{o.index - BASE}`)
				end
			end
		end
		if inside.z1 - (s.z - hz) > (inside.z1 - inside.z0) * 0.65 then
			table.insert(bad, `S{s.index - BASE} not by the door`)
		end
		if WarehouseLayout.standAt(site, s.x, s.z) ~= s.index then
			table.insert(bad, `standAt misses S{s.index - BASE}`)
		end
	end
	for i, a in hall do
		local ax, az = WarehouseLayout.extent(a)
		for j = i + 1, #hall do
			local b = hall[j]
			if overlaps(b, a.x - ax, a.x + ax, a.z - az, a.z + az, 0) then
				table.insert(bad, `hall stands {a.index} and {b.index}`)
			end
		end
	end
	check(`{L}: the showroom by the door, inside the walls, on no hall stand, desk or receiving zone, nothing on anything; standAt finds each`, #bad == 0, table.concat(bad, "; "))
	-- what stands on a plinth: every collectible but the alphorn and the oil painting on a Garage's, and most furniture
	local fits, total, sofa, bed = 0, 0, false, false
	for id, def in FurnitureLooks.Items do
		if def.rarity then
			total += 1
			if WarehouseLayout.fits(BASE + 1, def.size, level) then
				fits += 1
			end
		end
	end
	sofa = WarehouseLayout.fits(BASE + 1, FurnitureLooks.Items.sofa.size, level)
	bed = WarehouseLayout.fits(BASE + 1, FurnitureLooks.Items.bed.size, level)
	check(`{L}: a showroom plinth holds {fits} of the {total} collectibles{if level == 1 then "" else ", and a sofa"}; never a bed`, fits >= total - 2 and (level == 1 or sofa) and not bed, fits)
	-- the pieces: the plinths, their plates, the carpet, both areas' signs
	local names: { [string]: WarehouseLayout.Piece } = {}
	local unique = true
	for _, p in WarehouseLayout.pieces(site) do
		unique = unique and names[p.name] == nil
		names[p.name] = p
	end
	local plate = names[`Plate{BASE + 1}`]
	local signs = names.ShowSign1 ~= nil and (level == 1 or names.HallSign1 ~= nil) and names.HallFloorText1 ~= nil
	check(`{L}: its pieces: unique names, the plinths (Stand{BASE + 1}…), the plate "S1", the carpet, the showroom's and the hall's signs`, unique and names[`Stand{BASE + most}`] ~= nil
		and plate ~= nil and (plate.words :: any)[1].lines[1].text == "S1" and names.ShowCarpet1 ~= nil and signs)
	-- a visitor reaches every showroom piece from the door: the hall with all its stands in the way
	local podiums: { Visitors.Podium } = {}
	for _, s in hall do
		table.insert(podiums, { index = s.index, x = s.x, z = s.z, sx = s.sx, sz = s.sz, yaw = s.yaw })
	end
	for _, s in shows do
		table.insert(podiums, { index = s.index, x = s.x, z = s.z, sx = s.sx, sz = s.sz, yaw = s.yaw })
	end
	local door = WarehouseLayout.door(site)
	local walk = Visitors.hall({
		inside = { x0 = inside.x0, x1 = inside.x1, z0 = inside.z0, z1 = inside.z1 },
		door = { x = door.x, z = door.z, width = door.width },
		doorPath = { x0 = path.x0, x1 = path.x1, z0 = path.z0, z1 = path.z1 },
		desk = { index = 0, x = desk.x, z = desk.z, sx = desk.sx, sz = desk.sz, yaw = desk.yaw },
		stands = podiums,
	})
	local way = Visitors.doorway(walk, 1)
	local missing: { string } = {}
	for _, s in shows do
		local spot = Visitors.spot(walk, s.index, 0.4)
		if not spot then
			table.insert(missing, `S{s.index - BASE}: no spot`)
		elseif not Visitors.route(walk, way.inside, { x = spot.x, z = spot.z }) then
			table.insert(missing, `S{s.index - BASE}: no way`)
		end
	end
	check(`{L}: a visitor stands by every showroom plinth and walks there from the door`, #missing == 0, table.concat(missing, "; "))
end
check("a runway plinth is turned to its walk: a sofa (7.2 across) on it, its box 4.6 × 8 on the floor", (function()
	local site = WarehouseLayout.site(plot, 4) :: SandboxMap.Plot
	local s = WarehouseLayout.stand(site, BASE + 1) :: WarehouseLayout.Stand
	local hx, hz = WarehouseLayout.extent(s)
	return math.abs(s.yaw) == 90 and near(2 * hx, 4.6) and near(2 * hz, 8) and WarehouseLayout.fits(BASE + 1, FurnitureLooks.Items.sofa.size, 4)
end)())
check("words: plates \"7\" / \"S2\", \"hall stand 7\" / \"showroom stand 2\", a showroom tag's price line", WarehouseLayout.plateText(7) == "7" and WarehouseLayout.plateText(BASE + 2) == "S2"
	and WarehouseLayout.standName(BASE + 2) == "showroom stand 2" and WarehouseLayout.showTagLines("Sofa", "rare", 450)[2].text == "RARE · 🏷 $450")

if failures > 0 then
	error(`{failures} check(s) failed`)
end
print("ALL CHECKS PASSED")
