-- 8.0 SANDBOX: the real server/Admin.luau's "sandbox" command (the admin panel's SANDBOX tab), built by
-- tests/run_tests.py as AdminServer.luau on tests/runtime/AdminRuntime.luau's fakes: a non-admin is refused (nothing
-- happens, nothing is said), outside the sandbox world it is refused and says why, anything but a button's id is refused,
-- the clicks go through Net.limit (Config.Robust.Limits.AdminSandbox), every button's server side (the money, the
-- house's move through Moving.admin, the stock through the Collection API, the van and the teleports to
-- shared/SandboxMap.luau's spots) and the TARGET (another player, the notices to both). Run with tests/run_tests.py.
local E = require("./AdminRuntime")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local SandboxAdmin = require("./SandboxAdmin")
local FurnitureLooks = require("./FurnitureLooks")
local Admin = require("./AdminServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: any, b: any, eps: number?): boolean
	return (a - b).Magnitude <= (eps or 0.01)
end
local function count(list: { any }, keep: (any) -> boolean): number
	local n = 0
	for _, item in list do
		if keep(item) then
			n += 1
		end
	end
	return n
end

E.game.CreatorId = 1 -- the place's owner (Admin.isAdmin: the creator of a user-owned place)
local owner = E.player(1, "Owner")
local guest = E.player(2, "Guest")
Admin.start()
check("the owner is an admin, the guest is not", owner:GetAttribute("Admin") == true and guest:GetAttribute("Admin") == nil)
E.plots[owner] = 1
E.plots[guest] = 2

-- One click of the SANDBOX tab (a second later each: the double-click guard is 0.15 s).
local function click(from: any, id: any, target: any?): number
	E.clock += 1
	local mark = #E.notices
	E.fire(from, "sandbox", id, target)
	return mark
end

-- ── Who may ─────────────────────────────────────────────────────────────────

local mark = click(guest, "money")
check("a non-admin's SANDBOX click does nothing", #E.money == 0 and E.profiles[guest].money == 500 and #E.limits == 0)
check("…and is told nothing", #E.notices == mark)
click(guest, "money", owner.UserId)
click(guest, "broke", owner.UserId)
click(guest, "fill")
click(guest, "van")
check("a non-admin can't aim it at the owner either, nor fill, nor bring a van", #E.money == 0 and E.profiles[owner].money == 500 and #E.collection.added == 0 and #E.spawned == 0)

mark = click(owner, "money")
check("the owner's 💰 +$10K: $10 000 more, the Admin reason", #E.money == 1 and E.money[1].amount == SandboxAdmin.Money and E.money[1].reason == "Admin" and E.profiles[owner].money == 10_500)
check("…and the answer in a notice", string.find(E.said(owner, mark), "$10,000", 1, true) ~= nil, E.said(owner, mark))
check("the click went through the rate limit: AdminSandbox at Config.Robust.Limits'", #E.limits == 1 and E.limits[1].name == "AdminSandbox" and E.limits[1].rate == Config.Robust.Limits.AdminSandbox and E.limits[1].player == owner)

E.limitOpen = false
click(owner, "money")
check("over the rate limit: dropped", #E.money == 1 and E.profiles[owner].money == 10_500)
E.limitOpen = true

E.clock += 1
E.fire(owner, "sandbox", "money")
E.fire(owner, "sandbox", "money") -- the same moment: a double click
check("a double click runs once", #E.money == 2)

Config.Sandbox.On = false
mark = click(owner, "money")
check("outside the sandbox world: refused, the owner told why", #E.money == 2 and string.find(E.said(owner, mark), "Config.Sandbox.On", 1, true) ~= nil, E.said(owner, mark))
Config.Sandbox.On = true

local junk: { any } = { "nuke", 5, true, {}, 0 / 0, string.rep("x", 200), "MONEY" }
local before = #E.money
local refused = 0
for _, arg in junk do
	mark = click(owner, arg)
	if string.find(E.said(owner, mark), "unknown SANDBOX command", 1, true) then
		refused += 1
	end
end
mark = click(owner, nil)
check("anything but a button's id: refused and said so, nothing done", #E.money == before and refused == #junk and string.find(E.said(owner, mark), "unknown", 1, true) ~= nil)

-- ── Every button has a server side ───────────────────────────────────────────

local unanswered: { string } = {}
for _, action in SandboxAdmin.Actions do
	mark = click(owner, action.id)
	local text = E.said(owner, mark)
	if text == "" or string.find(text, "unknown", 1, true) or string.find(text, "failed", 1, true) then
		table.insert(unanswered, `{action.id}: {text}`)
	end
end
check("every SANDBOX button runs and answers", #unanswered == 0, table.concat(unanswered, " / "))

-- ── Money ────────────────────────────────────────────────────────────────────

click(owner, "broke")
check("💸 MONEY 0: the money is $0, the client told", E.profiles[owner].money == 0 and E.notified > 0)

-- ── Moves (Moving.admin) ──────────────────────────────────────────────────────

local function lastMove(): string?
	local last = E.moving[#E.moving]
	return if last then last.arg else nil
end
table.clear(E.moving)
click(owner, "start")
check("▶ START MOVE: Moving.admin start", lastMove() == "start")
click(owner, "clock")
check("⏩ SKIP CLOCK: Moving.admin time (one minute left)", lastMove() == "time")
click(owner, "horde")
check("🧟 HORDE NOW: Moving.admin horde", lastMove() == "horde")
table.clear(E.moving)
mark = click(owner, "refill")
check("🏠 REFILL HOUSE with no move: nothing ended; 8.0.1: Moving.admin refill (the card's seed forgotten): the next START gets a new seed", #E.moving == 1
	and E.moving[1].arg == "refill" and E.moving[1].player == owner and string.find(E.said(owner, mark), "new seed", 1, true) ~= nil, E.said(owner, mark))
table.clear(E.moving)
E.onMove[owner] = true
mark = click(owner, "refill")
check("🏠 REFILL HOUSE on a move: the move ends cleanly (Moving.admin end), then Moving.admin refill", #E.moving == 2 and E.moving[1].arg == "end"
	and lastMove() == "refill" and E.onMove[owner] == nil and string.find(E.said(owner, mark), "called off", 1, true) ~= nil, E.said(owner, mark))

-- ── Collection ───────────────────────────────────────────────────────────────

table.clear(E.collection.added)
click(owner, "fill")
local added = E.collection.added
local wrong = count(added, function(entry)
	local piece = entry.entry
	return entry.player ~= owner or not FurnitureLooks.Items[piece.item] or piece.condition < SandboxAdmin.Fill.Condition[1] or piece.condition > SandboxAdmin.Fill.Condition[2] or piece.variant < 1 or piece.variant > SandboxAdmin.Fill.Variants
end)
check("📦 FILL STOCK: Collection.add × 10 of the catalogue's pieces, random condition, to the owner", #added == SandboxAdmin.Fill.Count and wrong == 0, wrong)
local kinds: { [string]: boolean } = {}
for _, entry in added do
	kinds[entry.entry.item] = true
end
local distinct = 0
for _ in kinds do
	distinct += 1
end
check("…random pieces", distinct > 2, distinct)

local config: any = Config
local warehouseConfig = config.Warehouse -- (8.0 merge: the warehouse worker's Config.Warehouse is there now)
config.Warehouse = nil
mark = click(owner, "stands")
check("⭐ FILL STANDS without Config.Warehouse: says so, shows nothing", #E.collection.shown == 0 and string.find(E.said(owner, mark), "Config.Warehouse.Stands", 1, true) ~= nil, E.said(owner, mark))
config.Warehouse = { Stands = 4 }
local stock = E.collection.stock[owner]
stock[2].stand = 2 -- one piece on show already
click(owner, "stands")
local shown = E.collection.shown
check("⭐ FILL STANDS: the stock's pieces on the free stands 1, 3, 4 (Collection.display)", #shown == 3 and shown[1].stand == 1 and shown[2].stand == 3 and shown[3].stand == 4 and shown[1].uid == stock[1].uid and shown[2].uid == stock[3].uid)
mark = click(owner, "stands")
check("…again: no free stand, nothing more", #shown == 3 and string.find(E.said(owner, mark), "nothing to put on show", 1, true) ~= nil)
config.Warehouse = warehouseConfig

E.profiles[owner].money, E.profiles[owner].earned = 700, 900
table.clear(E.collection.sold)
click(owner, "clear")
check("🗑 CLEAR STOCK (no Collection.clear): every piece sold, the money and earnings as they were", #E.collection.stock[owner] == 0 and #E.collection.sold == 10 and E.profiles[owner].money == 700 and E.profiles[owner].earned == 900)
E.Collection.clear = function(player: any)
	E.collection.cleared += 1
	E.collection.stock[player] = {}
	return 3
end
mark = click(owner, "clear")
check("🗑 CLEAR STOCK with Collection.clear: that is used", E.collection.cleared == 1 and string.find(E.said(owner, mark), "3 pieces gone", 1, true) ~= nil, E.said(owner, mark))
E.Collection.clear = nil
E.Collection.add = function()
	error("the collection is mid-change")
end
mark = click(owner, "fill")
check("a Collection that errors: the command says so instead of failing", string.find(E.said(owner, mark), "the stock took nothing", 1, true) ~= nil, E.said(owner, mark))

-- ── Travel and the van ───────────────────────────────────────────────────────

local plot = SandboxMap.Plots[1]
local spot = plot.vanSpot
E.cars[owner] = nil
table.clear(E.spawned)
click(owner, "van")
local made = E.spawned[1]
local south = E.Mock.Vector3.new(0, 0, 1)
check("🚐 BRING VAN with no van: the sandbox van built at the plot's vanSpot", #E.spawned == 1 and made.player == owner and near(made.ground.Position, E.Mock.Vector3.new(spot.x, spot.y, spot.z)))
check("…its nose to the street (south), so its back doors face the roller door", near(made.ground.LookVector, south))
local van = E.cars[owner]
van.model:PivotTo(E.Mock.CFrame.new(300, 5, 300))
click(owner, "van")
check("🚐 BRING VAN with the van far away: the same van moved (its load with it), not a new one", #E.spawned == 1 and near(van.chassis.Position, E.Mock.Vector3.new(spot.x, spot.y + 3 + 0.5, spot.z), 0.1) and near(van.chassis.CFrame.LookVector, south), van.chassis.Position)
E.plots[owner] = nil
mark = click(owner, "van")
check("no plot: says so", #E.spawned == 1 and string.find(E.said(owner, mark), "no plot", 1, true) ~= nil)
E.plots[owner] = 1

local door = SandboxMap.House.door
click(owner, "house")
local root = owner.Character:FindFirstChild("HumanoidRootPart")
check("📍 TO HOUSE on foot: at the front door, out in front of it, facing it", near(root.Position, E.Mock.Vector3.new(door.x, door.y + 3, door.z - 4)) and near(root.CFrame.LookVector, E.Mock.Vector3.new(0, 0, 1)), root.Position)
click(owner, "warehouse")
local spawn = plot.spawn
check("📍 TO WAREHOUSE on foot: at the plot's spawn", near(root.Position, E.Mock.Vector3.new(spawn.x, spawn.y + 0.5, spawn.z)), root.Position)
E.seated[owner] = van
click(owner, "house")
local curb = SandboxMap.House.curb
check("📍 TO HOUSE driving the van: the van to the house's curb, nose north", near(van.chassis.Position, E.Mock.Vector3.new(curb.x, curb.y + 3.5, curb.z), 0.1) and near(van.chassis.CFrame.LookVector, E.Mock.Vector3.new(0, 0, -1)), van.chassis.Position)
click(owner, "warehouse")
check("📍 TO WAREHOUSE driving the van: the van to the vanSpot", near(van.chassis.Position, E.Mock.Vector3.new(spot.x, spot.y + 3.5, spot.z), 0.1))
E.seated[owner] = nil

-- ── The TARGET ───────────────────────────────────────────────────────────────

E.profiles[guest].money = 50
mark = click(owner, "money", guest.UserId)
check("aimed at the guest: the guest gets the money, not the owner", E.profiles[guest].money == 50 + SandboxAdmin.Money and E.profiles[owner].money == 700)
check("…the guest is told who did it, the owner gets a copy", string.find(E.said(guest, mark), "ADMIN Owner", 1, true) ~= nil and string.find(E.said(owner, mark), "Guest", 1, true) ~= nil, E.said(guest, mark))
click(owner, "warehouse", guest.UserId)
local guestRoot = guest.Character:FindFirstChild("HumanoidRootPart")
local guestSpawn = SandboxMap.Plots[2].spawn
check("📍 TO WAREHOUSE aimed at the guest: the guest to their own plot's spawn", near(guestRoot.Position, E.Mock.Vector3.new(guestSpawn.x, guestSpawn.y + 0.5, guestSpawn.z)), guestRoot.Position)
mark = click(owner, "money", 999)
check("a target not in the server: refused", E.profiles[owner].money == 700 and string.find(E.said(owner, mark), "not in this server", 1, true) ~= nil)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
