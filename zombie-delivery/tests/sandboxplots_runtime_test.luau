-- 8.0.1 review, who owns which plot: the real server/SandboxPlots.luau (as SandboxPlotsServer.luau, a function of the
-- globals it reads) on this test's own Players. One plot a player, the lowest free one, for the players here at the
-- start and every one who joins; more players than plots wait without one (the attribute Plot nil); a player who
-- leaves frees theirs, and it goes at once to the first player here without one (who came first), never to one who
-- is leaving too; a free plot with nobody waiting goes to the next who joins; onChanged hears every claim and every
-- freeing. Run with tests/run_tests.py.
local SandboxMap = require("./SandboxMap")
local make = require("./SandboxPlotsServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- ── The players ─────────────────────────────────────────────────────────────
local function signal(): any
	local fns: { (...any) -> () } = {}
	return {
		Connect = function(_, fn: (...any) -> ())
			table.insert(fns, fn)
			return { Disconnect = function() end }
		end,
		Fire = function(_, ...: any)
			for _, fn in fns do
				fn(...)
			end
		end,
	}
end

type FakePlayer = { Name: string, attributes: { [string]: any }, GetAttribute: (any, string) -> any, SetAttribute: (any, string, any) -> () }
local here: { FakePlayer } = {}
local Players: any = { PlayerAdded = signal(), PlayerRemoving = signal() }
function Players.GetPlayers(_: any): { FakePlayer }
	return table.clone(here)
end
local function newPlayer(name: string): FakePlayer
	return {
		Name = name,
		attributes = {},
		GetAttribute = function(self: any, key: string): any
			return self.attributes[key]
		end,
		SetAttribute = function(self: any, key: string, value: any)
			self.attributes[key] = value
		end,
	}
end
local function join(name: string): FakePlayer
	local player = newPlayer(name)
	table.insert(here, player)
	Players.PlayerAdded:Fire(player)
	return player
end
-- (as Roblox does: PlayerRemoving fires while the player is still in Players:GetPlayers())
local function leave(player: FakePlayer)
	Players.PlayerRemoving:Fire(player)
	local at = table.find(here, player)
	if at then
		table.remove(here, at)
	end
end

local Shared = {
	WaitForChild = function(_, name: string): string
		return name
	end,
}
local game = {
	GetService = function(_, name: string): any
		if name == "Players" then
			return Players
		elseif name == "ReplicatedStorage" then
			return {
				WaitForChild = function(_, child: string): any
					assert(child == "Shared", child)
					return Shared
				end,
			}
		end
		error(`no service {name}`)
	end,
}
local task = {
	spawn = function(fn: (...any) -> (), ...: any)
		fn(...)
	end,
}
local function fakeRequire(module: any): any
	assert(module == "SandboxMap", tostring(module))
	return SandboxMap
end

local SandboxPlots = make(game, task, fakeRequire)
local heard: { string } = {}
SandboxPlots.onChanged(function(id: number, player: any)
	table.insert(heard, `{id}:{if player then player.Name else "free"}`)
end)
local function plotOf(player: FakePlayer): number?
	local plot = SandboxPlots.of(player :: any)
	return if plot then plot.id else nil
end
local function since(n: number): string
	return table.concat(heard, " ", n + 1)
end

check("four plots (Config.Sandbox.MaxPlayers' worth)", #SandboxMap.Plots == 4, #SandboxMap.Plots)

-- ── The start and joining ───────────────────────────────────────────────────
local ann = newPlayer("Ann")
table.insert(here, ann) -- (here before the start: nobody listened yet)
SandboxPlots.start()
check("start(): a player already here gets plot 1", plotOf(ann) == 1 and ann:GetAttribute("Plot") == 1 and SandboxPlots.owner(1) == (ann :: any), since(0))
local bob, cid, dan = join("Bob"), join("Cid"), join("Dan")
check("the next ones get the lowest free plots: 2, 3, 4", plotOf(bob) == 2 and plotOf(cid) == 3 and plotOf(dan) == 4 and bob:GetAttribute("Plot") == 2)
local eve, fay = join("Eve"), join("Fay")
check("more players than plots: Eve and Fay wait without one (Plot nil)", plotOf(eve) == nil and plotOf(fay) == nil and eve:GetAttribute("Plot") == nil and fay:GetAttribute("Plot") == nil)
check("onChanged heard each claim, in order", since(0) == "1:Ann 2:Bob 3:Cid 4:Dan", since(0))

-- ── A plot freed ────────────────────────────────────────────────────────────
local mark = #heard
leave(bob)
check("Bob leaves: plot 2 goes to Eve (the first waiting), at once", plotOf(eve) == 2 and eve:GetAttribute("Plot") == 2 and SandboxPlots.owner(2) == (eve :: any) and plotOf(bob) == nil, since(mark))
check("… onChanged: plot 2 freed, then Eve's", since(mark) == "2:free 2:Eve", since(mark))
check("… Fay still waits", plotOf(fay) == nil)
mark = #heard
leave(eve)
check("Eve leaves: plot 2 goes to Fay", plotOf(fay) == 2 and since(mark) == "2:free 2:Fay", since(mark))

-- ── Nobody waiting ──────────────────────────────────────────────────────────
mark = #heard
leave(ann)
check("Ann leaves with nobody waiting: plot 1 stays free", SandboxPlots.owner(1) == nil and since(mark) == "1:free", since(mark))
local gus = join("Gus")
check("… the next who joins gets it (the lowest free)", plotOf(gus) == 1 and since(mark) == "1:free 1:Gus", since(mark))

-- ── Someone waiting leaves; two going at once ───────────────────────────────
local hal, ida = join("Hal"), join("Ida")
mark = #heard
leave(hal)
check("a waiting player (Hal) leaves: nothing changes", since(mark) == "" and plotOf(ida) == nil, since(mark))
local jon = join("Jon")
Players.PlayerRemoving:Fire(ida) -- (Ida is going, still in the list)
leave(cid)
check("Cid leaves while Ida is going too: plot 3 skips her and goes to Jon", plotOf(jon) == 3 and plotOf(ida) == nil and ida:GetAttribute("Plot") == nil and SandboxPlots.owner(3) == (jon :: any), since(mark))
table.remove(here, table.find(here, ida) :: number)
check("a player with a plot never gets a second one", plotOf(gus) == 1 and plotOf(fay) == 2 and plotOf(dan) == 4)
local owners = {}
for id = 1, #SandboxMap.Plots do
	local owner = SandboxPlots.owner(id)
	owners[id] = if owner then (owner :: any).Name else "-"
end
check("the plots now: Gus, Fay, Jon, Dan", table.concat(owners, ",") == "Gus,Fay,Jon,Dan", table.concat(owners, ","))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
