-- 10.4 THE UPGRADE TREE's balance (Config.SandboxUpgrades.Balance; shared/UpgradeRules.luau): the prices summed and held
-- against the incomes a player has at each warehouse tier (Balance.Earn: the hall's income and the sales, $ a minute;
-- Balance.Hall: the hall's alone), so the economy stays sane as the tree grows:
--   * the whole tree (every rank but the soon nodes') costs between 20 and TotalHours hours of a Logistics Center's earn;
--   * each branch's first rank comes after a run or two (FirstMinutes of a Garage's earn), the trunk's first even sooner;
--   * every rank costs MinMinutes … MaxMinutes of the earn at the warehouse tier it needs (never a trifle, never out of
--     reach), and the costs grow along a branch (a node's first rank costs at least its parent's first);
--   * an income node pays itself back: its extra $ a minute in a Logistics Center's hall (Balance.Hall[5]: Hall
--     spotlights its 10 %, Collector's corner its share on the Epic and Legendary pieces, Room sets Balance.Sets sets, More
--     hall stands two more stands of an average piece) gives its price back within Payback hours;
--   * the showroom against the hall: a piece sells there for SellBonus × its price (more than the market pays), and a
--     piece earns its showroom price in the hall within 15 – 40 minutes: showing it for sale is for turning it into money,
--     the hall for keeping it (tests/showroom_test.luau has the split's rules).
-- Run with tests/run_tests.py.
local Config = require("./Config")
local Rules = require("./UpgradeRules")
local CollectionRules = require("./CollectionRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local U = Config.SandboxUpgrades
local B = U.Balance

local function tierOf(def: Config.SandboxUpgradeDef, rank: number): number
	if def.tiers then
		return def.tiers[rank] or 1
	end
	return 1
end

-- ── The references ──────────────────────────────────────────────────────────
do
	local rising = true
	for t = 2, 5 do
		rising = rising and B.Earn[t] > B.Earn[t - 1] and B.Hall[t] > B.Hall[t - 1] and B.Hall[t] < B.Earn[t]
	end
	check("the reference incomes rise tier by tier; the hall's is part of the earn", rising and #B.Earn == 5 and #B.Hall == 5)
	-- (Config.Collection's tuning: a first haul on 12 stands, the Big Warehouse's, earns about $40 – 50 a minute)
	check("… the Big Warehouse's hall within 2 × the first haul's $40 – 50 a minute (Config.Collection's tuning)", B.Hall[4] >= 40 and B.Hall[4] <= 2 * 50 * 1.25)
end

-- ── The whole tree ──────────────────────────────────────────────────────────
do
	local total = Rules.total()
	local hours = total / B.Earn[5] / 60
	check(`the whole tree: {Rules.money(total)} = {string.format("%.1f", hours)} hours of a Logistics Center's earn (20 … {B.TotalHours})`, hours >= 20 and hours <= B.TotalHours, hours)
	local legacy = 0
	for _, id in { "warehouse", "stands", "lights", "engine", "danny" } do
		for _, price in (Rules.def(id) :: Config.SandboxUpgradeDef).prices do
			legacy += price
		end
	end
	check("the legacy five still cost $352,000 (8.3 economy), the tree's own nodes the rest", legacy == 352000 and total > legacy)
	local byBranch: { [string]: number } = {}
	for _, id in Rules.Order do
		local def = Rules.def(id) :: Config.SandboxUpgradeDef
		if not def.soon then
			for _, price in def.prices do
				byBranch[def.branch or "?"] = (byBranch[def.branch or "?"] or 0) + price
			end
		end
	end
	local spread = true
	for _, b in U.Branches do
		local share = (byBranch[b.id] or 0) / total
		spread = spread and share > 0 and (b.id == "looks" or share <= 0.45)
	end
	check("no branch is most of the tree (each ≤ 45 %), every branch has something to buy", spread)
end

-- ── Every rank ──────────────────────────────────────────────────────────────
do
	local bad: { string } = {}
	local firsts: { [string]: number } = {}
	for _, id in Rules.Order do
		local def = Rules.def(id) :: Config.SandboxUpgradeDef
		for rank, price in def.prices do
			local tier = if id == "warehouse" then rank else tierOf(def, rank)
			local minutes = price / B.Earn[tier]
			if minutes < B.MinMinutes or minutes > B.MaxMinutes then
				table.insert(bad, `{id} {rank}: {math.floor(minutes)} min at tier {tier}`)
			end
		end
		local branch = def.branch or "?"
		if not def.soon and (firsts[branch] == nil or def.prices[1] < firsts[branch]) then
			firsts[branch] = def.prices[1]
		end
		for parent in def.needs or {} do
			local pdef = Rules.def(parent) :: Config.SandboxUpgradeDef
			if def.prices[1] < pdef.prices[1] then
				table.insert(bad, `{id} cheaper than its parent {parent}`)
			end
		end
	end
	check(`every rank: {B.MinMinutes} … {B.MaxMinutes} minutes of the earn at the tier it needs; a node's first rank at least its parent's`, #bad == 0, table.concat(bad, "; "))
	local early = true
	for _, b in U.Branches do
		early = early and (firsts[b.id] or math.huge) <= B.FirstMinutes * B.Earn[1]
	end
	check(`each branch's first rank within {B.FirstMinutes} minutes of a Garage's earn (a run or two); the trunk's first within an hour`, early and Rules.def("warehouse").prices[1] <= 60 * B.Earn[1])
end

-- ── The income nodes pay back ──────────────────────────────────────────────
do
	local hall = B.Hall[5]
	local hours = {}
	local function payback(id: string, perMinute: (rank: number) -> number)
		local def = Rules.def(id) :: Config.SandboxUpgradeDef
		local worst = 0
		for rank, price in def.prices do
			worst = math.max(worst, price / perMinute(rank) / 60)
		end
		hours[id] = worst
		return worst
	end
	local L = Rules.def("lights") :: Config.SandboxUpgradeDef
	payback("lights", function(rank: number): number
		return hall * L.step * (1 + L.step) ^ (rank - 1) -- (a rank on top of the ones before)
	end)
	payback("rare", function(): number
		return hall * B.EpicShare * (Rules.def("rare") :: Config.SandboxUpgradeDef).step
	end)
	payback("sets", function(): number
		return hall * B.Sets * (Rules.def("sets") :: Config.SandboxUpgradeDef).step
	end)
	payback("stands", function(): number
		return 2 * hall / Rules.totalStands({ warehouse = 4 }) -- (two more stands of the hall's average piece)
	end)
	local worst, which = 0, ""
	for id, h in hours do
		if h > worst then
			worst, which = h, id
		end
	end
	check(`the income nodes pay back within {B.Payback} hours in a Logistics Center's hall (the slowest: {which}, {string.format("%.1f", worst)} h)`, worst <= B.Payback, worst)
	check("… and none in minutes (they are worth saving up for: over an hour each)", hours.lights > 1 and hours.rare > 1 and hours.sets > 1 and hours.stands > 1)
end

-- ── The showroom against the hall ──────────────────────────────────────────
do
	local bonus = Config.Showroom.SellBonus
	check("the showroom sells for more than the market (SellBonus over 1, the tree's Sales pitch on top)", bonus > 1 and CollectionRules.showFactor({ sandboxUpgrades = { haggle = 3 } }) > bonus
		and math.abs(CollectionRules.showFactor({ sandboxUpgrades = {} }) - bonus) < 1e-9)
	local minutes: { number } = {}
	for _, id in Config.Collection.Order do
		local tier = Config.Collection.Tiers[id]
		-- (a whole piece: its showroom price over what it earns a minute in the hall)
		table.insert(minutes, bonus * tier.sell / tier.income)
	end
	local ok = true
	for _, m in minutes do
		ok = ok and m >= 15 and m <= 40
	end
	check("a piece earns its showroom price in the hall within 15 – 40 minutes (every rarity): the hall keeps, the showroom turns it into money", ok, table.concat(minutes, ", "))
end

if failures > 0 then
	error(`{failures} check(s) failed`)
end
print("ALL CHECKS PASSED")
