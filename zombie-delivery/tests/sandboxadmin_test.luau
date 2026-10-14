-- 8.0 SANDBOX: the admin panel's SANDBOX tab (shared/SandboxAdmin.luau): the buttons and their ids, the check every
-- ("sandbox", id) passes on the server (a non-admin refused, outside the sandbox refused, anything unknown refused),
-- the tab only in the sandbox world, FILL STOCK's random pieces, FILL STANDS' plan, SHOW ZONES' marks from
-- shared/SandboxMap.luau and the rate limit. Run with tests/run_tests.py (the real server command:
-- tests/adminsandbox_runtime_test.luau; the real panel: tools/phone-ui/check.py's adminpanel.luau).
local SandboxAdmin = require("./SandboxAdmin")
local SandboxMap = require("./SandboxMap")
local Config = require("./Config")
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

-- The buttons ---------------------------------------------------------------------------------------------------------

local groups: { [string]: boolean } = {}
for _, group in SandboxAdmin.Groups do
	groups[group.id] = true
end
local ids: { [string]: boolean } = {}
local colors = { green = true, grey = true, yellow = true, red = true, blue = true, gold = true, violet = true }
local bad: { string } = {}
for _, action in SandboxAdmin.Actions do
	if ids[action.id] or not groups[action.group] or not colors[action.color] or #action.label == 0 or #action.label > 24 then
		table.insert(bad, action.id)
	end
	ids[action.id] = true
end
check("every button: a new id, a group of the tab, a known colour, a short label", #bad == 0, table.concat(bad, ", "))
local wanted = { "money", "broke", "refill", "start", "clock", "horde", "fill", "clear", "stands", "van", "house", "warehouse", "upmax", "upreset" } -- (8.1: the upgrades' two)
local missing: { string } = {}
for _, id in wanted do
	if not ids[id] then
		table.insert(missing, id)
	end
end
check("the owner's twelve server buttons (8.1: and the upgrades' MAX / RESET) are all there", #missing == 0 and #SandboxAdmin.Actions == #wanted, table.concat(missing, ", "))
check("the groups in the asked order", SandboxAdmin.Groups[1].id == "money" and SandboxAdmin.Groups[2].id == "moves" and SandboxAdmin.Groups[3].id == "collection" and SandboxAdmin.Groups[4].id == "travel" and SandboxAdmin.Groups[5].id == "debug")
check("the labels the owner asked for", SandboxAdmin.find("money").label == "💰 +$10K" and SandboxAdmin.find("broke").label == "💸 MONEY 0" and SandboxAdmin.find("clock").label == "⏩ SKIP CLOCK")
check("+$10K is 10 000", SandboxAdmin.Money == 10_000)
local maxUp, resetUp = SandboxAdmin.find("upmax"), SandboxAdmin.find("upreset")
check("8.1: ⬆ MAX UPGRADES / ↺ RESET UPGRADES in the last group, Upgrades", maxUp ~= nil and resetUp ~= nil and maxUp.label == "⬆ MAX UPGRADES" and resetUp.label == "↺ RESET UPGRADES"
	and maxUp.group == "upgrades" and resetUp.group == "upgrades" and SandboxAdmin.Groups[#SandboxAdmin.Groups].id == "upgrades" and SandboxAdmin.Groups[#SandboxAdmin.Groups].name == "Upgrades")

-- The check (the server's) ------------------------------------------------------------------------------------------

local action, why = SandboxAdmin.check(true, true, "fill")
check("an admin in the sandbox: FILL STOCK goes", action ~= nil and action.id == "fill" and why == nil)
action, why = SandboxAdmin.check(false, true, "money")
check("a non-admin is refused (whatever they send)", action == nil and why == "not an admin")
action, why = SandboxAdmin.check(false, false, "nonsense")
check("…before anything else is looked at", action == nil and why == "not an admin")
action, why = SandboxAdmin.check(true, false, "money")
check("outside the sandbox world: refused, and says why", action == nil and type(why) == "string" and string.find(why :: string, "Config.Sandbox.On", 1, true) ~= nil)
local junk: { any } = { "nuke", "", 5, true, {}, 0 / 0, string.rep("m", 100), "MONEY", " money" }
local passed = 0
for _, arg in junk do
	if SandboxAdmin.check(true, true, arg) then
		passed += 1
	end
end
check("anything that is not a button's id is refused", passed == 0 and SandboxAdmin.check(true, true, nil) == nil)

-- The tab ------------------------------------------------------------------------------------------------------------

local base = { { "player", "PLAYER" }, { "op", "OP" } }
local on = SandboxAdmin.tabs(base, true)
local off = SandboxAdmin.tabs(base, false)
check("in the sandbox: SANDBOX is the first tab, the rest after it", #on == 3 and on[1][1] == "sandbox" and on[1][2] == "SANDBOX" and on[2][1] == "player" and on[3][1] == "op")
check("outside it: no SANDBOX tab", #off == 2 and off[1][1] == "player" and off[2][1] == "op")
check("the base list is not changed", #base == 2)

-- FILL STOCK ---------------------------------------------------------------------------------------------------------

-- a fixed sequence for the server's Random
local seq = 0
local function int(a: number, b: number): number
	seq += 1
	return a + (seq * 7) % (b - a + 1)
end
local function unit(): number
	seq += 1
	return (seq % 11) / 10 -- 0 … 1 (and over 1, clamped)
end
local picks = SandboxAdmin.picks(FurnitureLooks.Order, SandboxAdmin.Fill.Count, int, unit)
local wrong: { string } = {}
for _, pick in picks do
	if not FurnitureLooks.Items[pick.item] or pick.variant < 1 or pick.variant > SandboxAdmin.Fill.Variants or pick.variant % 1 ~= 0 then
		table.insert(wrong, pick.item)
	elseif pick.condition < SandboxAdmin.Fill.Condition[1] or pick.condition > SandboxAdmin.Fill.Condition[2] then
		table.insert(wrong, `{pick.item} at {pick.condition}`)
	elseif math.abs(pick.condition * 100 - math.floor(pick.condition * 100 + 0.5)) > 1e-6 then
		table.insert(wrong, `{pick.item}: {pick.condition} has more than two decimals`)
	end
end
check("ten pieces of the catalogue, colours 1 … 12, a condition in 0.3 … 1", #picks == 10 and #wrong == 0, table.concat(wrong, ", "))
check("never broken (over Config.Moving.Damage.BrokenAt)", SandboxAdmin.Fill.Condition[1] > Config.Moving.Damage.BrokenAt)
local spread: { [string]: boolean } = {}
local kinds = 0
for _, pick in picks do
	if not spread[pick.item] then
		spread[pick.item] = true
		kinds += 1
	end
end
check("random pieces, not one piece ten times", kinds > 1, kinds)
local wild = SandboxAdmin.picks({ "sofa" }, 3, function()
	return 99
end, function()
	return -5
end)
check("a Random out of range is kept in range", #wild == 3 and wild[1].item == "sofa" and wild[1].variant == SandboxAdmin.Fill.Variants and wild[1].condition == SandboxAdmin.Fill.Condition[1])
check("no catalogue, nothing; a silly count is bounded", #SandboxAdmin.picks({}, 10, int, unit) == 0 and #SandboxAdmin.picks({ "sofa" }, 1e9, int, unit) == SandboxAdmin.Fill.Most and #SandboxAdmin.picks({ "sofa" }, 0 / 0, int, unit) == 0 and #SandboxAdmin.picks({ "sofa" }, -3, int, unit) == 0)

-- FILL STANDS --------------------------------------------------------------------------------------------------------

local stock = {
	{ uid = "a", stand = nil },
	{ uid = "b", stand = 2 },
	{ uid = "c", stand = nil },
	{ uid = "d", stand = nil },
	{ uid = "e", stand = 4 },
	{ uid = "f", stand = nil },
}
local plan = SandboxAdmin.standPlan(stock, 5)
check("the pieces in the stock on the free stands in order (2 and 4 are taken)", #plan == 3 and plan[1].uid == "a" and plan[1].stand == 1 and plan[2].uid == "c" and plan[2].stand == 3 and plan[3].uid == "d" and plan[3].stand == 5, #plan)
check("no stands, no plan; every stand taken, no plan", #SandboxAdmin.standPlan(stock, 0) == 0 and #SandboxAdmin.standPlan({ { uid = "x", stand = 1 }, { uid = "y" } }, 1) == 0)
check("more stands than pieces: every piece goes up", #SandboxAdmin.standPlan({ { uid = "x" }, { uid = "y" } }, 12) == 2)
check("junk in the stock is passed over", #SandboxAdmin.standPlan({ 5 :: any, { uid = 7 }, { uid = "ok" } }, 3) == 1)
check("Config.Warehouse.Stands: a count, a list, or none", SandboxAdmin.standCount({ Stands = 8 }) == 8 and SandboxAdmin.standCount({ Stands = { {}, {}, {} } }) == 3 and SandboxAdmin.standCount(nil) == 0 and SandboxAdmin.standCount({ Stands = 0 / 0 }) == 0 and SandboxAdmin.standCount({ Stands = 6.7 }) == 6)

-- SHOW ZONES ---------------------------------------------------------------------------------------------------------

local zones = SandboxAdmin.zones()
local unloads, curbs = 0, 0
local off2: { string } = {}
for _, zone in zones do
	if zone.kind == "unload" then
		unloads += 1
		local plot = SandboxMap.plotAt(zone.x, zone.z)
		if zone.shape ~= "circle" or zone.r <= 0 or not plot or plot.unload.x ~= zone.x or plot.unload.r ~= zone.r then
			table.insert(off2, zone.label)
		end
	elseif zone.kind == "curb" then
		curbs += 1
		local curb = SandboxMap.House.curb
		if zone.shape ~= "box" or zone.x ~= curb.x or zone.z ~= curb.z or zone.yaw ~= curb.yaw or zone.sx <= 0 or zone.sz <= zone.sx then
			table.insert(off2, zone.label)
		end
	end
end
check("SHOW ZONES: every plot's unload circle at its plot, the house's curb at its spot", unloads == #SandboxMap.Plots and curbs == 1 and #off2 == 0, table.concat(off2, ", "))

-- The rate limit -----------------------------------------------------------------------------------------------------

local limit = Config.Robust.Limits.AdminSandbox
check("the SANDBOX commands' rate limit in Config.Robust.Limits (a few a second)", type(limit) == "number" and limit >= 1 and limit <= 10, limit)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
