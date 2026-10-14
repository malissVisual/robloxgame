--!strict
-- 8.0 SANDBOX, the warehouse: the few server modules the real server/Warehouse.luau needs in the Luau CLI
-- (tests/warehouse_runtime_test.luau through tests/run_tests.py, which builds WarehouseServer.luau from
-- src/server/Warehouse.luau with these in place of its requires; Config, FurnitureLooks, SandboxMap and WarehouseLayout
-- are the real ones, FurnitureMesh the real one without an import). The recorder, the players, the signals (a prompt's
-- Triggered), the remotes (Runtime.messages, Runtime.lastNotice) and task.delay (at once) are
-- tests/runtime/MovingRuntime.luau's. Here: a fake SandboxPlots (Runtime.claim, Runtime.free) and a fake Collection
-- (a stock per player the test fills, Runtime.give / Runtime.changed; it records Runtime.calls). 8.1: the fake
-- Collection's stands (Runtime.standCount: player → how many, else the real rule: UpgradeRules.totalStands of their
-- levels) and boost (Runtime.boosts), a fake Upgrades (its open recorded in Runtime.calls as "openUpgrades").
-- 8.3, the warehouse levels: the fake Upgrades' levels (Runtime.levels: player → { [id]: level }; Upgrades.levels gives
-- a copy) and its listeners (Runtime.upgrade(player, levels): the levels set, Upgrades.onChanged's fns told, as the
-- real one does after a purchase and when a save loads); Runtime.fakeArt() puts a stand-in of the owner's Blender
-- import (ZDCWarehouseArt: its markers and one piece a level, made from WarehouseLayout's own numbers of each level)
-- into the workspace, so the real server/WarehouseMesh.luau dresses every warehouse, and fills the recorder's CFrame
-- gaps WarehouseMesh uses (fromMatrix, a CFrame minus a Vector3).
local E = require("./MovingRuntime") :: any
local SandboxMap = require("./SandboxMap")
local Config = require("./Config")
local UpgradeRules = require("./UpgradeRules")
local WarehouseLayout = require("./WarehouseLayout")

local Mock = E.Mock
local Runtime: any = {
	Mock = Mock,
	Net = E.Net,
	task = E.task,
	os = E.os,
	player = E.player,
	leave = E.leave,
	messages = E.messages,
	lastNotice = E.lastNotice,
	calls = {}, -- { { name, player, a } } every Collection call that changes something (and openPicker)
	income = {}, -- player → Collection.incomePerMinute
	stocks = {}, -- player → { Entry }
	standCount = {}, -- 8.1: player → Collection.stands (else UpgradeRules.totalStands of their levels)
	boosts = {}, -- 8.1: player → Collection.boost (else 1)
	levels = {}, -- 8.3: player → their upgrades' levels (Upgrades.levels; none: the garage)
}

-- The Shared folder (empty: no CollectionRules) under the services MovingRuntime fakes.
local shared = Mock.Instance.new("Folder")
shared.Name = "Shared"
Runtime.game = {
	GetService = function(_, name: string): any
		if name == "ReplicatedStorage" then
			return {
				WaitForChild = function()
					return shared
				end,
			}
		end
		return E.game:GetService(name)
	end,
}

-- ── SandboxPlots ───────────────────────────────────────────────────────────

local owners: { [number]: any } = {}
local plotListeners: { (number, any) -> () } = {}
Runtime.SandboxPlots = {
	of = function(player: any): any
		for id, owner in owners do
			if owner == player then
				return SandboxMap.Plots[id]
			end
		end
		return nil
	end,
	owner = function(id: number): any
		return owners[id]
	end,
	onChanged = function(fn: (number, any) -> ())
		table.insert(plotListeners, fn)
	end,
}
function Runtime.claim(id: number, player: any)
	owners[id] = player
	player:SetAttribute("Plot", id)
	for _, fn in plotListeners do
		fn(id, player)
	end
end
function Runtime.free(id: number)
	owners[id] = nil
	for _, fn in plotListeners do
		fn(id, nil)
	end
end

-- ── Collection ─────────────────────────────────────────────────────────────

local changedListeners: { (any) -> () } = {}
function Runtime.changed(player: any)
	for _, fn in changedListeners do
		fn(player)
	end
end
local function find(player: any, uid: string): (any, number?)
	for index, entry in Runtime.stocks[player] or {} do
		if entry.uid == uid then
			return entry, index
		end
	end
	return nil, nil
end
-- One piece into the player's stock (stand: on show there) and the change told.
function Runtime.give(player: any, entry: any)
	Runtime.stocks[player] = Runtime.stocks[player] or {}
	table.insert(Runtime.stocks[player], entry)
	Runtime.changed(player)
end
Runtime.Collection = {
	stock = function(player: any): any
		local list = {}
		for _, entry in Runtime.stocks[player] or {} do
			table.insert(list, table.clone(entry))
		end
		return list
	end,
	incomePerMinute = function(player: any): number
		return Runtime.income[player] or 0
	end,
	openPicker = function(player: any, stand: number)
		table.insert(Runtime.calls, { "openPicker", player, stand })
	end,
	display = function(player: any, uid: string, stand: number): (boolean, string?)
		table.insert(Runtime.calls, { "display", player, uid })
		local entry = find(player, uid)
		if not entry then
			return false, "No such piece."
		end
		entry.stand = stand
		Runtime.changed(player)
		return true, nil
	end,
	undisplay = function(player: any, uid: string): (boolean, string?)
		table.insert(Runtime.calls, { "undisplay", player, uid })
		local entry = find(player, uid)
		if not entry or entry.stand == nil then
			return false, "It isn't on show."
		end
		entry.stand = nil
		Runtime.changed(player)
		return true, nil
	end,
	sell = function(player: any, uid: string): (number?, string?)
		table.insert(Runtime.calls, { "sell", player, uid })
		local _, index = find(player, uid)
		if not index then
			return nil, "No such piece."
		end
		table.remove(Runtime.stocks[player], index)
		Runtime.changed(player)
		return 100, nil
	end,
	onChanged = function(fn: (any) -> ())
		table.insert(changedListeners, fn)
	end,
	stands = function(player: any): number
		return Runtime.standCount[player] or UpgradeRules.totalStands(Runtime.levels[player] or {})
	end,
	boost = function(player: any): number
		return Runtime.boosts[player] or 1
	end,
	marketIncome = function(): number -- (8.3: no hot kinds here)
		return 1
	end,
}

-- 8.1: server/Upgrades.luau's open (the UPGRADES desk's prompt); 8.3: its levels and listeners
local upgradeListeners: { (any) -> () } = {}
Runtime.Upgrades = {
	open = function(player: any)
		table.insert(Runtime.calls, { "openUpgrades", player })
	end,
	levels = function(player: any): any
		return table.clone(Runtime.levels[player] or {})
	end,
	onChanged = function(fn: (any) -> ())
		table.insert(upgradeListeners, fn)
	end,
}
-- 8.3: the player's levels are these now (a purchase, the admin's MAX / RESET, a save loaded): Upgrades.onChanged's fns
-- hear it (the real one also tells the collection: Runtime.changed is the test's to call when it matters).
function Runtime.upgrade(player: any, levels: any)
	Runtime.levels[player] = table.clone(levels)
	for _, fn in upgradeListeners do
		fn(player)
	end
end

-- ── 8.3: a stand-in of the owner's Blender import ───────────────────────────

local F = getmetatable(Mock.CFrame.new())
-- (the recorder's gaps server/WarehouseMesh.luau's loadArt uses)
if Mock.CFrame.fromMatrix == nil then
	Mock.CFrame.fromMatrix = function(at: any, vx: any, vy: any, vz: any): any
		return Mock.CFrame.new(at.X, at.Y, at.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
	end
end
if F.__sub == nil then
	F.__sub = function(a: any, v: any): any
		return a + (-v)
	end
end

-- ZDCWarehouseArt in the workspace as the importer leaves it (unturned, unscaled): mark_o / x / y / z, each level's
-- origin far apart (mark_lvl<N>) and its markers from WarehouseLayout's level N on plot 1 (the box's corner: half its
-- width, its wall's height, its depth; the door's half width and height; the top), and two pieces a level
-- ("lvl<N>_metal", "lvl<N>_orange": what WarehouseMesh clones onto a warehouse of that level). → the model.
function Runtime.fakeArt(): any
	local art = Mock.Instance.new("Model")
	art.Name = "ZDCWarehouseArt"
	local function mark(name: string, at: any)
		local p = Mock.Instance.new("Part")
		p.Name = name
		p.Size = Mock.Vector3.new(0.2, 0.2, 0.2)
		p.CFrame = Mock.CFrame.new(at.X, at.Y, at.Z)
		p.Parent = art
	end
	local V3 = Mock.Vector3.new
	mark("mark_o", V3(0, 0, 0))
	mark("mark_x", V3(10, 0, 0))
	mark("mark_y", V3(0, 10, 0))
	mark("mark_z", V3(0, 0, 10))
	for n = 1, WarehouseLayout.Levels do
		local site = WarehouseLayout.site(SandboxMap.Plots[1], n) :: SandboxMap.Plot
		local outline = WarehouseLayout.outline(site)
		local door = WarehouseLayout.door(site)
		local origin = V3(n * 300, 0, 0)
		local width, depth = outline.x1 - outline.x0, outline.z1 - outline.z0
		mark(`mark_lvl{n}`, origin)
		mark(`mark_lvl{n}_box`, origin + V3(width / 2, site.warehouse.sy, depth))
		mark(`mark_lvl{n}_door`, origin + V3(door.width / 2, door.height, 0))
		mark(`mark_lvl{n}_top`, origin + V3(0, outline.top, 0))
		for _, finish in { "metal", "orange" } do
			local piece = Mock.Instance.new("Part")
			piece.Name = `lvl{n}_{finish}`
			piece.Size = V3(width, 1, 1)
			piece.CFrame = Mock.CFrame.new(origin.X, site.warehouse.sy / 2, origin.Z + depth / 2)
			piece.Parent = art
		end
	end
	art.Parent = Mock.workspace
	return art
end

-- A second later on os.clock (a player's prompts are a short moment apart at least).
function Runtime.later()
	E.clock += 1
end

-- The last Collection call of this name.
function Runtime.lastCall(name: string): any
	for index = #Runtime.calls, 1, -1 do
		if Runtime.calls[index][1] == name then
			return Runtime.calls[index]
		end
	end
	return nil
end

return Runtime
