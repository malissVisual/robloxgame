--!strict
-- 6.14, the shift's pay on the server (shared/Shift.luau has the rules, Config.Jobs.Shift the numbers): every player's
-- shift for this play session (never saved; gone when they leave). server/Jobs.luau payOrder calls Shift.paid once for
-- every job finished and paid (at a run's last order; the owner's, and each crew member's own when they are there
-- with them; not a road event's add-on): the shift one further, and when it is full its pay through the economy's own paths (PlayerData.addMoney
-- "ShiftBonus", PlayerData.addXp: a level-up shows its card as always), the daily task "shift" (server/Tasks.luau),
-- and an analytics event (ShiftDone, through PlayerData.track). What Shift.paid returns goes into that
-- player's DeliveryResult as `shift`; Shift.view goes into the State (server/Main.server.luau sendState): the HUD's
-- SHIFT chip and SHIFT DONE (client/GrindChips.luau), the result window's line (client/Hud.luau).
--   Shift.paid(player)        a delivery paid: { count, target, idleUntil?, shifts, done?, money?, xp? } (nil when it
--                             could not count: no profile yet, an error; it never breaks the pay)
--   Shift.view(player)        { count, target, idleUntil?, shifts } for the State
--   Shift.set(player, count)  the admin panel's count (server/Admin.luau "shift"); the State goes out
--   Shift.start()             forgets a player who leaves

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShiftData = require(Shared.Shift)

local PlayerData = require(script.Parent.PlayerData)

local Shift = {}

local states: { [Player]: ShiftData.State } = {}

local function now(): number
	return workspace:GetServerTimeNow() -- (the client compares idleUntil with its own GetServerTimeNow)
end

local function stateOf(player: Player): ShiftData.State
	local state = states[player]
	if not state then
		state = ShiftData.new()
		states[player] = state
	end
	return state
end

-- The shift is full: its pay, the daily task, analytics (the HUD's SHIFT DONE says it). Guarded by the caller.
local function payShift(player: Player, state: ShiftData.State, info: { [string]: any })
	local level = PlayerData.level(player)
	local money, xp = ShiftData.pay(level)
	PlayerData.addMoney(player, money, "ShiftBonus")
	PlayerData.addXp(player, xp)
	info.done = true
	info.money = money
	info.xp = xp
	require(script.Parent.Tasks).note(player, "shift", 1) -- the daily task "Finish a shift"
	PlayerData.track("event", player, "ShiftDone", state.shifts, level) -- 6.13's hooks (a no-op without Analytics)
end

-- One delivery paid to `player` (server/Jobs.luau payOrder). Returns the result's `shift` table, nil when it could not
-- count. Never errors.
function Shift.paid(player: Player): { [string]: any }?
	if not player.Parent or not PlayerData.get(player) then
		return nil
	end
	local ok, result = pcall(function(): { [string]: any }
		local state = stateOf(player)
		local at = now()
		local done = ShiftData.count(state, at)
		local info: { [string]: any } = ShiftData.view(state, at) :: any
		if done then
			payShift(player, state, info)
		end
		return info
	end)
	if not ok then
		warn(`[Shift] a delivery could not count: {result}`)
		return nil
	end
	return result
end

-- The shift as the State sends it (a player without one yet: 0 of the shift).
function Shift.view(player: Player): ShiftData.View
	return ShiftData.view(states[player] or ShiftData.new(), now())
end

-- The admin panel: the shift at `count` (0 … Jobs − 1) as if the last delivery was just now; the State goes out.
function Shift.set(player: Player, count: number): number
	local state = stateOf(player)
	ShiftData.set(state, count, now())
	PlayerData.notify(player)
	return state.count
end

function Shift.start()
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return Shift
