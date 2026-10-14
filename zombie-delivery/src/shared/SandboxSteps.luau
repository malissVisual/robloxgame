--!strict
-- 8.0 SANDBOX, the guide's steps (design/sandbox/KONTRAKT.md; client/SandboxGuide.luau draws them): what a player new
-- to the sandbox does next, decided from what the client can see. Pure (no Roblox: tests/sandboxsteps_test.luau).
--
-- The state (client/SandboxGuide.luau fills one table again every Config.SandboxGuide.Every seconds):
--   plot          your plot (the player attribute Plot, server/SandboxPlots.luau; nil: none yet)
--   move          a move runs (the Moving remote's "state" is a table, client/MovingHud.luau)
--   inside        you are in the house (the state's `inside`, server/HouseInterior.luau)
--   carrying      you carry a piece (one of the state's items is `mine` and "carried")
--   vanLoad       the pieces in the van now (the state's counts.out)
--   delivered     the pieces unloaded at home on this move (the state's counts.delivered: a trip or more done)
--   atHouse       you stand (or drive) at the house (SandboxSteps.atHouse)
--   seated        you sit in a vehicle
--   planning      the move's planning lobby is open (the MoveLobby remote's "lobby"); planningMine: yours (LAUNCH)
--   stock         your pieces in the stock, not on show (the Collection remote's "state")
--   shown         your pieces on show on a display stand
--   freeStands    the empty display stands (nil: not known, taken as some)
--
-- The steps (SandboxSteps.decide, the first that fits; the owner's table):
--   in the house                        inside    "Carry the furniture out to your van (E to pick up)"   (no target)
--   carrying, outside                   load      "Load it into the van: walk in or E at the back"        the van's back
--   the van has things, the move is on  home      "Drive home to your warehouse to unload (or keep loading)" unload
--   a move, at the house, outside       door      "Walk in through the front door"                        House.door
--   a move, not at the house            drive     "Drive to The Old Chalet"                               House.curb
--     (after a trip home)               back      "Drive back to The Old Chalet for more, or FINISH"      House.curb
--   no move, the planning open          plan      "Press LAUNCH to start the move" / the crew waits       (no target)
--   no move, pieces in the stock        show      "Put your pieces on show: E at an empty stand"          a free stand
--   no move, pieces on show             earn      "Your pieces earn money while you play. …"              the board
--   no move                             contract  "Take a contract at the board"                          the board
--
-- Done once, a step stays quiet for the session (SandboxSteps.doneBy: what the player did, seen this session: a count
-- that went up, not one a save brought along; `earn` only says something, so the client counts it done after
-- Config.SandboxGuide.InfoSeconds on the screen). A quiet step shows no hint and no 3D guide, except the drive steps
-- (nav: drive, back, home): their arrow stays while you drive.
--   SandboxSteps.decide(state) -> Step                 the step now
--   SandboxSteps.doneBy(state, done, last)             marks in `done` (id → true) the steps this state shows done;
--                                                      `last` keeps the counts of the look before (vanLoad, delivered,
--                                                      shown: nil = not known yet, then only taken, nothing marked)
--   SandboxSteps.visible(step, done, seated) -> (hint, guide)   show the hint line? the 3D guide?
--   SandboxSteps.text(step, touch) -> string           the hint's words ("E" is "tap" on a touch screen)
--   SandboxSteps.atHouse(x, z, margin) -> boolean       in the house's lot or within `margin` studs of it
--   SandboxSteps.route(fx, fz, tx, tz, out, direct) -> n   the path on the ground, along the roads: n points written
--                                                      into `out` as x1, z1, x2, z2 … (no table made: the guide calls
--                                                      it five times a second); straight when within `direct` studs
--   SandboxSteps.collection(msg, total?) -> Summary    the Collection remote's "state": stock, shown, free, taken
--   SandboxSteps.nearestFree(x, z, spots, taken) -> index?   the nearest empty stand (spots[i] = { x, y, z }, taken[i])

local SandboxMap = require(script.Parent.SandboxMap)

local SandboxSteps = {}

export type State = {
	plot: number?,
	move: boolean,
	inside: boolean,
	carrying: boolean,
	vanLoad: number,
	delivered: number,
	atHouse: boolean,
	seated: boolean,
	planning: boolean,
	planningMine: boolean,
	stock: number,
	shown: number,
	freeStands: number?,
}

-- target: what the 3D guide points at (client/SandboxGuide.luau finds it): "board" | "curb" | "door" | "van" |
-- "unload" | "stand" | nil (the hint only). nav: the arrow stays while you drive, done or not. info: it only says
-- something (done after a while on the screen).
export type Step = { id: string, hint: string, target: string?, nav: boolean, info: boolean }

export type Summary = { stock: number, shown: number, free: number?, taken: { [number]: boolean } }

-- The counts of the look before (SandboxSteps.doneBy): a step is done when its count goes up while you play.
export type Last = { vanLoad: number?, delivered: number?, shown: number? }

-- A display stand's place in the world (client/SandboxGuide.luau reads them from shared/WarehouseLayout.luau).
export type Place = { x: number, y: number, z: number }

local HOUSE = SandboxMap.House.name

local function step(id: string, hint: string, target: string?, nav: boolean, info: boolean): Step
	return { id = id, hint = hint, target = target, nav = nav, info = info }
end

SandboxSteps.Steps = {
	contract = step("contract", "Take a contract at the board", "board", false, false),
	plan = step("plan", "Press LAUNCH to start the move", nil, false, false),
	planCrew = step("planCrew", "Get ready: the move's owner presses LAUNCH", nil, false, false),
	drive = step("drive", `Drive to {HOUSE}`, "curb", true, false),
	back = step("back", `Drive back to {HOUSE} for more, or FINISH`, "curb", true, false),
	door = step("door", "Walk in through the front door", "door", false, false), -- (8.1 walk-in doors: no E)
	inside = step("inside", "Carry the furniture out to your van (E to pick up)", nil, false, false),
	load = step("load", "Load it into the van: walk in or E at the back", "van", false, false),
	home = step("home", "Drive home to your warehouse to unload (or keep loading)", "unload", true, false),
	show = step("show", "Put your pieces on show: E at an empty stand", "stand", false, false),
	earn = step("earn", "Your pieces earn money while you play. Take another contract for more!", "board", false, true),
} :: { [string]: Step }

local S = SandboxSteps.Steps

function SandboxSteps.decide(s: State): Step
	if s.move then
		if s.inside then
			return S.inside
		end
		if s.carrying then
			return S.load
		end
		if s.vanLoad > 0 then
			return S.home
		end
		if s.atHouse then
			return S.door
		end
		return if s.delivered > 0 then S.back else S.drive
	end
	if s.planning then
		return if s.planningMine then S.plan else S.planCrew
	end
	local free = s.freeStands
	if s.stock > 0 and (free == nil or free > 0) then
		return S.show
	end
	if s.shown > 0 then
		return S.earn
	end
	return S.contract
end

-- Did the count go up since the look before (nil before: not known yet, nothing to say)?
local function rose(before: number?, now: number): boolean
	return before ~= nil and now > before
end

-- What this state shows done (each mark stays for the session; `earn` is the client's, by time). The counts mark a step
-- when they go up (a piece loaded, a trip unloaded, a piece put on show), so what a save or a crew brought along before
-- you looked does not.
function SandboxSteps.doneBy(s: State, done: { [string]: boolean }, last: Last)
	if s.move or s.planning then
		done.contract = true
	end
	if s.move then
		done.plan = true
		done.planCrew = true
		if s.atHouse then
			done.drive = true
			if s.delivered > 0 then
				done.back = true
			end
		end
		if s.inside then
			done.door = true
		elseif s.carrying then
			done.door = true -- (out of the house with a piece: it was emptied from inside)
			done.inside = true
		end
	end
	if s.move and rose(last.vanLoad, s.vanLoad) then
		done.load = true
	end
	if s.move and rose(last.delivered, s.delivered) then
		done.home = true
	end
	if rose(last.shown, s.shown) then
		done.show = true
	end
	last.vanLoad = if s.move then s.vanLoad else 0
	last.delivered = if s.move then s.delivered else 0
	last.shown = s.shown
end

-- The hint line and the 3D guide: a step not done yet shows both (the guide when it has a target); a done one is quiet,
-- but a drive step's arrow stays while you sit in a vehicle.
function SandboxSteps.visible(s: Step, done: { [string]: boolean }, seated: boolean): (boolean, boolean)
	local fresh = done[s.id] ~= true
	return fresh, s.target ~= nil and (fresh or (s.nav and seated))
end

-- The words: on a touch screen a prompt is tapped ("E at the back" → "tap at the back").
function SandboxSteps.text(s: Step, touch: boolean): string
	if not touch then
		return s.hint
	end
	return (string.gsub(s.hint, "%f[%w]E%f[%W]", "tap"))
end

function SandboxSteps.atHouse(x: number, z: number, margin: number): boolean
	local lot = SandboxMap.House.lot
	return x >= lot.x0 - margin and x <= lot.x1 + margin and z >= lot.z0 - margin and z <= lot.z1 + margin
end

-- ── The path along the roads ───────────────────────────────────────────────
-- Depot Row (the plots' road, east-west) and Main Street (north-south, down to the house). A point north of Depot
-- Row's far edge is on the depot's side (the plots, the row itself), the rest is Main Street's side (the street, the
-- meadow, the house). The path goes out to the row's middle line, along it to Main Street's, along that, then in.

local ROW = SandboxMap.Roads[2]
local MAIN = SandboxMap.Roads[1]
local ROW_Z = (ROW.z0 + ROW.z1) / 2
local MAIN_X = (MAIN.x0 + MAIN.x1) / 2
local DEPOT_EDGE = ROW.z1 -- (z grows southwards: smaller z is north, the plots' side)
local MIN_STEP = 3 -- studs: a point this close to the last one is left out

local function push(out: { number }, n: number, x: number, z: number): number
	if n > 0 then
		local dx, dz = x - out[n * 2 - 1], z - out[n * 2]
		if dx * dx + dz * dz < MIN_STEP * MIN_STEP then
			return n
		end
	end
	n += 1
	out[n * 2 - 1] = x
	out[n * 2] = z
	return n
end

function SandboxSteps.route(fx: number, fz: number, tx: number, tz: number, out: { number }, direct: number): number
	local n = push(out, 0, fx, fz)
	local dx, dz = tx - fx, tz - fz
	if dx * dx + dz * dz > direct * direct then
		local fromDepot, toDepot = fz <= DEPOT_EDGE, tz <= DEPOT_EDGE
		if fromDepot and toDepot then
			n = push(out, n, fx, ROW_Z)
			n = push(out, n, tx, ROW_Z)
		elseif fromDepot then
			n = push(out, n, fx, ROW_Z)
			n = push(out, n, MAIN_X, ROW_Z)
			n = push(out, n, MAIN_X, tz)
		elseif toDepot then
			n = push(out, n, MAIN_X, fz)
			n = push(out, n, MAIN_X, ROW_Z)
			n = push(out, n, tx, ROW_Z)
		else
			n = push(out, n, MAIN_X, fz)
			n = push(out, n, MAIN_X, tz)
		end
	end
	n = push(out, n, tx, tz)
	if n == 1 then -- (already there: a path of one point is the target twice)
		n = 2
		out[3], out[4] = tx, tz
	end
	return n
end

-- ── The collection ─────────────────────────────────────────────────────────

-- The Collection remote's { kind = "state", stock = { Entry }, stands = n }: the pieces in the stock (no stand) and on
-- show (a stand), the stands taken and the empty ones out of `total` (Config.Warehouse.Stands or the layout's count;
-- else the message's `stands` when it says more than are shown; nil: not known).
function SandboxSteps.collection(msg: any, total: number?): Summary
	local summary: Summary = { stock = 0, shown = 0, free = nil, taken = {} }
	if type(msg) ~= "table" then
		return summary
	end
	local list = msg.stock
	if type(list) == "table" then
		for _, entry in list do
			if type(entry) == "table" then
				local stand = entry.stand
				if type(stand) == "number" then
					summary.shown += 1
					summary.taken[stand] = true
				else
					summary.stock += 1
				end
			end
		end
	end
	local all = total
	if all == nil and type(msg.stands) == "number" and msg.stands > summary.shown then
		all = msg.stands
	end
	if all ~= nil then
		summary.free = math.max(0, all - summary.shown)
	end
	return summary
end

function SandboxSteps.nearestFree(x: number, z: number, spots: { [number]: Place }, taken: { [number]: boolean }): number?
	local best: number? = nil
	local bestD = math.huge
	for index, spot in spots do
		if not taken[index] then
			local dx, dz = spot.x - x, spot.z - z
			local d = dx * dx + dz * dz
			if d < bestD then
				best, bestD = index, d
			end
		end
	end
	return best
end

return SandboxSteps
