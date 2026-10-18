--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md, the admin's row): the admin panel's SANDBOX tab, the owner's quick test
-- tools in the small sandbox world. client/AdminPanel.luau draws Groups and Actions in this order (only when
-- Config.Sandbox.On) and sends ("sandbox", action id) over the Admin remote; server/Admin.luau checks the id here
-- (SandboxAdmin.check) and runs it on the TARGET. Pure: numbers and strings, no services (tests/sandboxadmin_test.luau;
-- the real server command: tests/adminsandbox_runtime_test.luau).
--
--   Groups                    the tab's sections in order: id, name, hint
--   Actions                   the buttons: id (what the panel sends), group, label, color (a Ui.Colors / Theme.Postage
--                             name: green, grey, yellow, red, blue, gold, violet). 🔍 SHOW ZONES is the panel's own
--                             (client/SandboxZones.luau: this screen only, no command). 8.1: ⬆ MAX UPGRADES / ↺ RESET
--                             UPGRADES (server/Upgrades.luau admin) in the last group, Upgrades. 8.2: 📖 FILL BOOK / 📖
--                             CLEAR BOOK (server/CollectionBook.luau admin) in the Collection group. 8.3: 🏗 LV 1 … 🏗 LV 5
--                             (the TARGET's warehouse at that level for free: Upgrades.admin "level1" … "level5") in
--                             the Upgrades group; 🎨 UNLOCK PAINTS / 🎨 RESET PAINTS (server/VanPaint.luau admin: the
--                             PAINT shop) there too
--   Money                     $ the 💰 button gives
--   Fill                      📦 FILL STOCK: Count pieces a press, their condition Condition[1] … [2] (two decimals:
--                             a piece at Config.Moving.Damage.BrokenAt or under is broken), their colours 1 … Variants
--                             (shared/HouseLayout.luau's range), Most pieces at most whatever is asked
--   Van                       a van's footprint (studs: width, length) for SHOW ZONES' curb (SandboxMap: "~20 long")
--   9.7 runs (server/Runs.luau admin): the Runs group's 🎚 EASY … NIGHTMARE pick the difficulty of the admin's next run,
--   ▶ FARMSTEAD … ▶ ORCHARD start a run on that house for the TARGET alone (at the picked difficulty, open or not), ⏹ END
--   RUN ends the TARGET's run (what is in the truck goes home); SKIP CLOCK and HORDE NOW act on the TARGET's run. The
--   travel group's BRING VAN is gone (no van in the lobby); 📍 TO LOBBY: the TARGET to the lobby's plaza.
--
--   SandboxAdmin.find(id)                   the action with that id, nil for anything else (any type)
--   SandboxAdmin.check(admin, sandbox, id)  the action, else nil and why: not an admin, not the sandbox, unknown
--   SandboxAdmin.tabs(base, sandbox)        the panel's tabs ({ id, name }): SANDBOX first when the sandbox is on
--   SandboxAdmin.picks(ids, count, int, unit)   FILL STOCK's pieces { item, variant, condition }: int(a, b) a whole
--                                           number a … b, unit() a number 0 … 1 (the server's Random)
--   SandboxAdmin.standPlan(stock, stands)   FILL STANDS: { uid, stand } for the stock's pieces not on show (in
--                                           stock order), each on the next free stand of 1 … stands
--   SandboxAdmin.standCount(warehouse)      Config.Warehouse's Stands (a count, or a list of stands), 0 without it
--   SandboxAdmin.zones()                    SHOW ZONES' fixed marks (shared/SandboxMap.luau): 10.4 the lobby's PLAY
--                                           circle (where a party gathers) and the houses' curbs (the truck's footprint at the spot:
--                                           every place to empty's, SandboxMap.Houses' order, its name on it)
--   SandboxAdmin.runHouse(id) / runDifficulty(id)   9.7: the house a "run_<house>" button starts, the difficulty a
--                                           "rundiff_<id>" button picks (nil: not such a button)

local SandboxMap = require(script.Parent.SandboxMap)

local SandboxAdmin = {}

export type Group = { id: string, name: string, hint: string }
export type Action = { id: string, group: string, label: string, color: string }
export type Pick = { item: string, variant: number, condition: number }
export type Zone = {
	kind: string, -- "play" (10.4: the PLAY circle) | "curb"
	label: string,
	shape: string, -- "circle" (r) | "box" (sx, sy, sz, turned by yaw)
	x: number,
	y: number,
	z: number,
	yaw: number,
	r: number,
	sx: number,
	sy: number,
	sz: number,
}

SandboxAdmin.Groups = {
	{ id = "money", name = "Money", hint = "The TARGET's money: a pile to buy with, or none to try being broke." },
	{
		id = "runs",
		name = "Runs",
		hint = "9.7: the runs (server/Runs.luau). EASY … NIGHTMARE: the difficulty of the next run you start here (locks ignored). ▶ a house: a run there for the TARGET alone, now. END RUN: the TARGET's run ends (what is in the truck goes home). SKIP CLOCK: one minute left. HORDE NOW: the horde comes.",
	},
	{
		id = "collection",
		name = "Collection",
		hint = "The TARGET's warehouse stock. FILL: 10 random pieces in random condition. CLEAR: every piece gone ($0 for them). FILL STANDS: the stock's pieces on the free display stands. FILL BOOK: every piece of the collection book found (its milestones pay). CLEAR BOOK: the book and its milestones empty.",
	},
	{
		id = "travel",
		name = "Travel and the van",
		hint = "TO HOUSE: the TARGET to the front door of their run's house (else the farmstead's). TO WAREHOUSE: to their warehouse. TO LOBBY: to the lobby's plaza. (9.7: no van in the lobby, no BRING VAN.)",
	},
	{
		id = "debug",
		name = "Debug",
		hint = "SHOW ZONES (only on your screen): the PLAY circle, the houses' curbs (the truck's spot), the display stands and every van's cargo bay.",
	},
	{
		id = "upgrades",
		name = "Upgrades",
		hint = "8.1: the TARGET's upgrades (the UPGRADES desk). MAX: every one at its top for free (the Logistics centre's 24 stands and More stands' 8, the lights, the van, Danny). RESET: none (the Garage; the pieces on the lost stands go back to the stock). LV 1 – 5: the warehouse at that level (1 the Garage … 5 the Logistics centre), the rest as it is. 8.3: UNLOCK PAINTS: every paint and livery of the PAINT shop owned for free (wear them at the van). RESET PAINTS: none, the van back in Deliveros cream.",
	},
} :: { Group }

SandboxAdmin.Actions = {
	{ id = "money", group = "money", label = "💰 +$10K", color = "green" },
	{ id = "broke", group = "money", label = "💸 MONEY 0", color = "grey" },
	-- 9.7 runs: the next run's difficulty, a run on each house, its end
	{ id = "rundiff_easy", group = "runs", label = "🎚 EASY", color = "green" },
	{ id = "rundiff_normal", group = "runs", label = "🎚 NORMAL", color = "blue" },
	{ id = "rundiff_hard", group = "runs", label = "🎚 HARD", color = "yellow" },
	{ id = "rundiff_insane", group = "runs", label = "🎚 INSANE", color = "gold" },
	{ id = "rundiff_nightmare", group = "runs", label = "🎚 NIGHTMARE", color = "red" },
	{ id = "run_sandbox_house", group = "runs", label = "▶ FARMSTEAD", color = "violet" },
	{ id = "run_pond_cabin", group = "runs", label = "▶ POND CABIN", color = "violet" },
	{ id = "run_lone_house", group = "runs", label = "▶ LONE HOUSE", color = "violet" },
	{ id = "run_forest_lodge", group = "runs", label = "▶ FOREST LODGE", color = "violet" },
	{ id = "run_old_mill", group = "runs", label = "▶ OLD MILL", color = "violet" },
	{ id = "run_orchard_cottage", group = "runs", label = "▶ ORCHARD", color = "violet" },
	{ id = "runend", group = "runs", label = "⏹ END RUN", color = "red" },
	{ id = "clock", group = "runs", label = "⏩ SKIP CLOCK", color = "grey" },
	{ id = "horde", group = "runs", label = "🧟 HORDE NOW", color = "red" },
	{ id = "fill", group = "collection", label = "📦 FILL STOCK", color = "green" },
	{ id = "clear", group = "collection", label = "🗑 CLEAR STOCK", color = "red" },
	{ id = "stands", group = "collection", label = "⭐ FILL STANDS", color = "yellow" },
	{ id = "bookfill", group = "collection", label = "📖 FILL BOOK", color = "violet" }, -- 8.2: the collection book
	{ id = "bookclear", group = "collection", label = "📖 CLEAR BOOK", color = "grey" },
	{ id = "house", group = "travel", label = "📍 TO HOUSE", color = "violet" },
	{ id = "warehouse", group = "travel", label = "📍 TO WAREHOUSE", color = "violet" },
	{ id = "lobby", group = "travel", label = "📍 TO LOBBY", color = "violet" }, -- 9.7
	{ id = "upmax", group = "upgrades", label = "⬆ MAX UPGRADES", color = "gold" },
	{ id = "upreset", group = "upgrades", label = "↺ RESET UPGRADES", color = "grey" },
	{ id = "level1", group = "upgrades", label = "🏗 LV 1", color = "blue" }, -- 8.3: the warehouse's level
	{ id = "level2", group = "upgrades", label = "🏗 LV 2", color = "blue" },
	{ id = "level3", group = "upgrades", label = "🏗 LV 3", color = "blue" },
	{ id = "level4", group = "upgrades", label = "🏗 LV 4", color = "blue" },
	{ id = "level5", group = "upgrades", label = "🏗 LV 5", color = "blue" },
	{ id = "paintall", group = "upgrades", label = "🎨 UNLOCK PAINTS", color = "violet" }, -- 8.3: the PAINT shop
	{ id = "paintreset", group = "upgrades", label = "🎨 RESET PAINTS", color = "grey" },
} :: { Action }

SandboxAdmin.Money = 10_000
SandboxAdmin.Fill = { Count = 10, Condition = { 0.3, 1 } :: { number }, Variants = 12, Most = 50 }
SandboxAdmin.Van = { 8, 20 } :: { number }

function SandboxAdmin.find(id: any): Action?
	if type(id) ~= "string" or #id > 32 then
		return nil
	end
	for _, action in SandboxAdmin.Actions do
		if action.id == id then
			return action
		end
	end
	return nil
end

-- What the server runs for ("sandbox", id) from `admin`'s panel: the action, else nil and why (said to the admin).
function SandboxAdmin.check(admin: boolean, sandbox: boolean, id: any): (Action?, string?)
	if not admin then
		return nil, "not an admin"
	end
	if not sandbox then
		return nil, "the SANDBOX tools work only in the sandbox world (Config.Sandbox.On)."
	end
	local action = SandboxAdmin.find(id)
	if not action then
		return nil, "unknown SANDBOX command."
	end
	return action, nil
end

function SandboxAdmin.tabs(base: { { string } }, sandbox: boolean): { { string } }
	local list: { { string } } = if sandbox then { { "sandbox", "SANDBOX" } } else {}
	for _, tab in base do
		table.insert(list, tab)
	end
	return list
end

function SandboxAdmin.picks(ids: { string }, count: number, int: (number, number) -> number, unit: () -> number): { Pick }
	local list: { Pick } = {}
	local fill = SandboxAdmin.Fill
	if #ids == 0 or count ~= count then
		return list
	end
	local low, high = fill.Condition[1], fill.Condition[2]
	for _ = 1, math.clamp(math.floor(count), 0, fill.Most) do
		local item = ids[math.clamp(math.floor(int(1, #ids)), 1, #ids)]
		local condition = math.floor((low + (high - low) * math.clamp(unit(), 0, 1)) * 100 + 0.5) / 100
		local variant = math.clamp(math.floor(int(1, fill.Variants)), 1, fill.Variants)
		table.insert(list, { item = item, variant = variant, condition = math.clamp(condition, low, high) })
	end
	return list
end

function SandboxAdmin.standPlan(stock: { any }, stands: number): { { uid: string, stand: number } }
	local plan: { { uid: string, stand: number } } = {}
	local taken: { [number]: boolean } = {}
	for _, entry in stock do
		if type(entry) == "table" and type(entry.stand) == "number" then
			taken[entry.stand] = true
		end
	end
	local stand = 1
	for _, entry in stock do
		if type(entry) == "table" and entry.stand == nil and type(entry.uid) == "string" then
			while stand <= stands and taken[stand] do
				stand += 1
			end
			if stand > stands then
				break
			end
			table.insert(plan, { uid = entry.uid, stand = stand })
			taken[stand] = true
		end
	end
	return plan
end

function SandboxAdmin.standCount(warehouse: any): number
	local stands = if type(warehouse) == "table" then warehouse.Stands else nil
	if type(stands) == "number" and stands == stands then
		return math.clamp(math.floor(stands), 0, 100)
	elseif type(stands) == "table" then
		return #stands
	end
	return 0
end

function SandboxAdmin.zones(): { Zone }
	local list: { Zone } = {}
	local play = SandboxMap.Lobby.play -- (10.4: where a party gathers: the PLAY panel opens in it)
	table.insert(list, {
		kind = "play",
		label = "PLAY · step in: the PLAY panel",
		shape = "circle",
		x = play.x,
		y = SandboxMap.GroundTop,
		z = play.z,
		yaw = 0,
		r = play.r,
		sx = 0,
		sy = 0,
		sz = 0,
	})
	local NOSE = { [0] = "north", [90] = "west", [180] = "south", [270] = "east" } :: { [number]: string }
	for _, house in SandboxMap.Houses do -- (every place to empty's curb, the farmstead's first)
		local curb = house.curb
		table.insert(list, {
			kind = "curb",
			label = `CURB · {string.upper(house.name)} · the van here, nose {NOSE[curb.yaw % 360] or "out"}`,
			shape = "box",
			x = curb.x,
			y = curb.y,
			z = curb.z,
			yaw = curb.yaw,
			r = 0,
			sx = SandboxAdmin.Van[1],
			sy = 0.3,
			sz = SandboxAdmin.Van[2],
		})
	end
	return list
end

function SandboxAdmin.runHouse(id: any): string?
	if type(id) ~= "string" or string.sub(id, 1, 4) ~= "run_" then
		return nil
	end
	local house = string.sub(id, 5)
	return if SandboxMap.house(house) then house else nil
end

function SandboxAdmin.runDifficulty(id: any): string?
	if type(id) ~= "string" or string.sub(id, 1, 8) ~= "rundiff_" then
		return nil
	end
	return string.sub(id, 9)
end

return SandboxAdmin
