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
--                             (client/SandboxZones.luau: this screen only, no command)
--   Money                     $ the 💰 button gives
--   Fill                      📦 FILL STOCK: Count pieces a press, their condition Condition[1] … [2] (two decimals:
--                             a piece at Config.Moving.Damage.BrokenAt or under is broken), their colours 1 … Variants
--                             (shared/HouseLayout.luau's range), Most pieces at most whatever is asked
--   Van                       a van's footprint (studs: width, length) for SHOW ZONES' curb (SandboxMap: "~20 long")
--
--   SandboxAdmin.find(id)                   the action with that id, nil for anything else (any type)
--   SandboxAdmin.check(admin, sandbox, id)  the action, else nil and why: not an admin, not the sandbox, unknown
--   SandboxAdmin.tabs(base, sandbox)        the panel's tabs ({ id, name }): SANDBOX first when the sandbox is on
--   SandboxAdmin.picks(ids, count, int, unit)   FILL STOCK's pieces { item, variant, condition }: int(a, b) a whole
--                                           number a … b, unit() a number 0 … 1 (the server's Random)
--   SandboxAdmin.standPlan(stock, stands)   FILL STANDS: { uid, stand } for the stock's pieces not on show (in
--                                           stock order), each on the next free stand of 1 … stands
--   SandboxAdmin.standCount(warehouse)      Config.Warehouse's Stands (a count, or a list of stands), 0 without it
--   SandboxAdmin.zones()                    SHOW ZONES' fixed marks (shared/SandboxMap.luau): each plot's unload
--                                           circle and the house's curb (a van's footprint at the spot)

local SandboxMap = require(script.Parent.SandboxMap)

local SandboxAdmin = {}

export type Group = { id: string, name: string, hint: string }
export type Action = { id: string, group: string, label: string, color: string }
export type Pick = { item: string, variant: number, condition: number }
export type Zone = {
	kind: string, -- "unload" | "curb"
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
		id = "moves",
		name = "Moves",
		hint = "The sandbox house (Moving's admin). REFILL calls a running move off: the next START brings a new seed, the house filled anew. SKIP CLOCK: one minute left. HORDE NOW: the horde comes.",
	},
	{
		id = "collection",
		name = "Collection",
		hint = "The TARGET's warehouse stock. FILL: 10 random pieces in random condition. CLEAR: every piece gone ($0 for them). FILL STANDS: the stock's pieces on the free display stands.",
	},
	{
		id = "travel",
		name = "Travel and the van",
		hint = "BRING VAN: the sandbox van to the TARGET's plot, its back to the roller door. TO HOUSE / TO WAREHOUSE: the TARGET (and the van they drive) there.",
	},
	{
		id = "debug",
		name = "Debug",
		hint = "SHOW ZONES (only on your screen): the plots' unload circles, the house's curb, the display stands and every van's cargo bay.",
	},
} :: { Group }

SandboxAdmin.Actions = {
	{ id = "money", group = "money", label = "💰 +$10K", color = "green" },
	{ id = "broke", group = "money", label = "💸 MONEY 0", color = "grey" },
	{ id = "refill", group = "moves", label = "🏠 REFILL HOUSE", color = "gold" },
	{ id = "start", group = "moves", label = "▶ START MOVE", color = "yellow" },
	{ id = "clock", group = "moves", label = "⏩ SKIP CLOCK", color = "grey" },
	{ id = "horde", group = "moves", label = "🧟 HORDE NOW", color = "red" },
	{ id = "fill", group = "collection", label = "📦 FILL STOCK", color = "green" },
	{ id = "clear", group = "collection", label = "🗑 CLEAR STOCK", color = "red" },
	{ id = "stands", group = "collection", label = "⭐ FILL STANDS", color = "yellow" },
	{ id = "van", group = "travel", label = "🚐 BRING VAN", color = "blue" },
	{ id = "house", group = "travel", label = "📍 TO HOUSE", color = "violet" },
	{ id = "warehouse", group = "travel", label = "📍 TO WAREHOUSE", color = "violet" },
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
	for _, plot in SandboxMap.Plots do
		local circle = plot.unload
		table.insert(list, {
			kind = "unload",
			label = `UNLOAD · PLOT {plot.id}`,
			shape = "circle",
			x = circle.x,
			y = SandboxMap.RoadTop, -- (the van's apron: vanSpot stands at the asphalt's top)
			z = circle.z,
			yaw = 0,
			r = circle.r,
			sx = 0,
			sy = 0,
			sz = 0,
		})
	end
	local curb = SandboxMap.House.curb
	table.insert(list, {
		kind = "curb",
		label = "HOUSE CURB · the van here, nose north",
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
	return list
end

return SandboxAdmin
