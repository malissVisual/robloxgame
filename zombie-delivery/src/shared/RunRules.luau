--!strict
-- 9.7 RUNS (Config.Runs; the owner: "like Dungeon Quest: from the lobby you go into a house, alone, with friends or with
-- Danny"): the rules of a run, pure (no Roblox: tests/runrules_test.luau). server/Runs.luau runs the runs with them,
-- client/RunUi.luau shows them. 10.4: the parties gather in lobbies at the PLAY circle first (shared/PartyRules.luau;
-- the portals' pads and their countdowns are gone).
--
-- The difficulties (Config.Runs.Difficulties, in order: easy, normal, hard, insane, nightmare): a run's
-- contract.difficulty. A player has the first `count` of them open (profile.runUnlocked: Open at first); finishing a
-- run at one opens the next (any house).
--   RunRules.list()                  the difficulties in order
--   RunRules.index(id) -> n?         its place in the order (nil: no such difficulty)
--   RunRules.def(id) -> def?         its Config entry
--   RunRules.clean(id) -> id         a known difficulty's id, else Config.Runs.Default
--   RunRules.time(base, id) -> s     the run's clock: a house's base time × the difficulty's time, whole seconds
--   RunRules.fromSave(saved) -> n    the migration (server/PlayerData.luau): a real save (money in it) written with the
--                                    flag (Config.Runs.Flag) keeps its count (Open … all); anything else Open
--   RunRules.isOpen(count, id)       is that difficulty open with `count` open?
--   RunRules.unlock(count, id) -> (count, opened?)   a run finished at `id`: the count after it and the id it opened
--                                    (nil: none new)
--   RunRules.choose(count, want) -> id   the difficulty a host gets: `want` when open, else the hardest open one under
--                                    it (10.4: a party lobby's host's pick: shared/PartyRules.luau)
--
-- In a run:
--   RunRules.voteDone(votes, members) -> bool   everybody in the run (still there) asked to FINISH
--   RunRules.stockOwner(loader, host, present) -> id   whose stock a piece in the truck goes into: whoever loaded it
--                                    while they are still in the game (present(id)), else the host
--   RunRules.summary(pieces, me) -> Summary   the results card's sums: every piece (count, value) and `me`'s own
--   RunRules.clock(seconds) -> "m:ss"
local Config = require(script.Parent.Config)

local RunRules = {}

local R = Config.Runs
local LIST = R.Difficulties

export type Piece = { value: number, to: number }
export type Summary = { count: number, value: number, mine: number, mineValue: number }

function RunRules.list(): { Config.RunDifficulty }
	return LIST
end

function RunRules.index(id: any): number?
	if type(id) ~= "string" then
		return nil
	end
	for n, def in LIST do
		if def.id == id then
			return n
		end
	end
	return nil
end

function RunRules.def(id: any): Config.RunDifficulty?
	local n = RunRules.index(id)
	return if n then LIST[n] else nil
end

function RunRules.clean(id: any): string
	return if RunRules.index(id) then id :: string else R.Default
end

function RunRules.time(base: number, id: any): number
	local def = RunRules.def(id) or (RunRules.def(R.Default) :: Config.RunDifficulty)
	return math.max(60, math.floor(base * def.time + 0.5))
end

function RunRules.fromSave(saved: any): number
	if type(saved) ~= "table" or saved.money == nil or saved[R.Flag] ~= true then
		return R.Open
	end
	local count = saved.runUnlocked
	if type(count) ~= "number" or count ~= count or count ~= math.floor(count) then
		return R.Open
	end
	return math.clamp(count, R.Open, #LIST)
end

function RunRules.isOpen(count: number, id: any): boolean
	local n = RunRules.index(id)
	return n ~= nil and n <= math.max(count, R.Open)
end

function RunRules.unlock(count: number, id: any): (number, string?)
	local n = RunRules.index(id)
	local now = math.clamp(count, R.Open, #LIST)
	if not n or n + 1 <= now or n >= #LIST then
		return now, nil
	end
	return n + 1, LIST[n + 1].id
end

function RunRules.choose(count: number, want: any): string
	local n = RunRules.index(want) or (RunRules.index(R.Default) :: number)
	local open = math.clamp(count, R.Open, #LIST)
	return LIST[math.min(n, open)].id
end

-- ── In a run ───────────────────────────────────────────────────────────────

function RunRules.voteDone(votes: { [number]: boolean }, members: { number }): boolean
	if #members == 0 then
		return false
	end
	for _, id in members do
		if votes[id] ~= true then
			return false
		end
	end
	return true
end

function RunRules.stockOwner(loader: number?, host: number, present: (number) -> boolean): number
	if loader ~= nil and present(loader) then
		return loader
	end
	return host
end

function RunRules.summary(pieces: { Piece }, me: number): Summary
	local out: Summary = { count = 0, value = 0, mine = 0, mineValue = 0 }
	for _, p in pieces do
		local value = math.max(0, tonumber(p.value) or 0)
		out.count += 1
		out.value += value
		if p.to == me then
			out.mine += 1
			out.mineValue += value
		end
	end
	out.value = math.floor(out.value + 0.5)
	out.mineValue = math.floor(out.mineValue + 0.5)
	return out
end

function RunRules.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", s // 60, s % 60)
end

return RunRules
