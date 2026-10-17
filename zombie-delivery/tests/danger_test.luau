-- 10.x DANGER (the owner: "both: on the easier difficulties only a timer and traps, on the harder ones zombies too";
-- "it has to be designed to be fun"): the pure rules (shared/DangerRules.luau, Config.Runs.Danger …) in the standalone
-- Luau CLI, on the REAL plans of the six places to empty (shared/HouseLayout.luau on the recorder, tests/run_tests.py):
-- the big house, the family house, the cabin, the lodge, the mill and the cottage, several seeds each, every difficulty.
--   * the counts per difficulty: locks from Easy (more on the harder ones), the vault from Normal (a Legendary chance on
--     Nightmare only), the hazards more and nastier, zombies from Hard (a wave from Insane, the boss on Nightmare), the
--     bat from Hard; every plan within its difficulty's counts, the same house and difficulty always the same plan
--   * the locks: a lockable doorway cuts rooms off the way in (never a room you come in by); every lock's key in a
--     searchable piece of ANOTHER room you can get to (with the locks before it shut; never behind its own lock): opening
--     them one by one opens them all, and the vault's key is reachable then, never in the vault
--   * the hazards: on a room's floor, never in or by a doorway (Gap.Door), off the pieces and the way in; never on the way
--     out: with every piece standing, every doorway and every piece a body could get to from the way in it still can,
--     the hazards in its way (HouseRoute's A* on its own grid, not DangerRules' flood)
--   * the vault's pieces: Epic or better (LootRules.lift), Legendary only on Nightmare; a locked room's pieces a tier up
--   * Danny's route (shared/HouseRoute.luau shut): through a locked doorway no way and no sight; opened, his way to the
--     piece behind it again; a hazard closes its floor (he walks round it) but not his sight
--   * the small rules: a hazard under a point, the nearest, the wave's time, a zombie's kind by the weights, the words
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local DangerRules = require("./DangerRules")
local HouseLayout = require("./HouseLayout")
local HouseRoute = require("./HouseRoute")
local LootRules = require("./LootRules")
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

local R = Config.Runs
local ORDER = { "easy", "normal", "hard", "insane", "nightmare" }
local KINDS = { "big", "house", "cabin", "lodge", "mill", "cottage" }
local SEEDS = { 7919, 15838, 23757, 31676, 104729 }
type Rect = HouseRoute.Rect

local function hazards(level: any): number
	return level.Creak + level.Puddle + level.Plaster
end

-- ── The counts per difficulty ──────────────────────────────────────────────
do
	local every = true
	for _, id in ORDER do
		every = every and R.Danger[id] ~= nil and DangerRules.level(id) == R.Danger[id]
	end
	check("Config.Runs.Danger: one entry per difficulty (easy … nightmare), an unknown one is the default's", every
		and DangerRules.difficulty("chaos") == R.Default and DangerRules.difficulty(nil) == R.Default)
	local rising, zombies, wave, boss, weapon, vault, legendary = true, true, true, true, true, true, true
	for n, id in ORDER do
		local d = R.Danger[id]
		local before = R.Danger[ORDER[n - 1] or id]
		rising = rising and d.Locks >= before.Locks and hazards(d) >= hazards(before) and d.Harm >= before.Harm and d.Speed >= before.Speed
			and d.Inside >= before.Inside and d.Yard >= before.Yard and d.Vault >= before.Vault and d.Wave >= before.Wave
		local hard = n >= 3
		zombies = zombies and (if hard then d.Inside > 0 and d.Yard > 0 else d.Inside == 0 and d.Yard == 0)
		wave = wave and (if n >= 4 then d.Wave > 0 else d.Wave == 0)
		boss = boss and d.Boss == (id == "nightmare")
		weapon = weapon and d.Weapon == hard
		vault = vault and (if n >= 2 then d.Vault >= 1 else d.Vault == 0)
		legendary = legendary and (if id == "nightmare" then d.Legendary > 0 and d.Legendary < 1 else d.Legendary == 0)
	end
	check("… every difficulty at least as dangerous as the one before (locks, hazards, harm, zombies, speed, the vault, the wave)", rising)
	check("… locked rooms from Easy, more on the harder ones", R.Danger.easy.Locks >= 1 and R.Danger.nightmare.Locks > R.Danger.easy.Locks)
	check("… the vault from Normal (none on Easy)", vault)
	check("… hazards from Easy (only creaks and a puddle there), the plaster from Normal, nastier further up",
		hazards(R.Danger.easy) > 0 and R.Danger.easy.Plaster == 0 and R.Danger.normal.Plaster > 0 and R.Danger.nightmare.Harm > R.Danger.easy.Harm)
	check("… zombies only from Hard (inside and in the yard), a wave from Insane, the boss on Nightmare alone", zombies and wave and boss)
	check("… Insane and Nightmare's zombies faster, of more kinds", R.Danger.insane.Speed > 1 and R.Danger.nightmare.Speed >= R.Danger.insane.Speed
		and R.Danger.nightmare.Kinds.brute ~= nil and R.Danger.hard.Kinds.walker ~= nil)
	check("… the bat from Hard (every run player then)", weapon and R.Weapon.Kind == "bat" and Config.Melee.Kinds[R.Weapon.Kind] ~= nil)
	check("… a Legendary vault piece only on Nightmare (a chance)", legendary)
	local known = true
	for _, id in R.Search.Items do
		known = known and FurnitureLooks.Items[id] ~= nil and (FurnitureLooks.Items[id] :: any).rarity == nil
	end
	check("Config.Runs.Search.Items: real catalogue pieces, never a collectible", known)
	check("… wardrobes, dressers, desks, drawers and chests are searched; a collectible or an unknown piece never",
		DangerRules.searchable("wardrobe") and DangerRules.searchable("dresser") and DangerRules.searchable("desk") and DangerRules.searchable("carved_chest")
			and not DangerRules.searchable("gold_record") and not DangerRules.searchable("nope") and not DangerRules.searchable(nil))
	check("… a key's name by its room", DangerRules.keyName("bedroom") == "Bedroom key" and DangerRules.keyName("millers") == "Miller's Room key"
		and DangerRules.keyName(nil) == "Vault key" and DangerRules.roomName("attic") == "Attic")
end

-- ── The real plans ─────────────────────────────────────────────────────────
type Case = { kind: string, seed: number, plan: any }
local cases: { Case } = {}
for _, kind in KINDS do
	for _, seed in SEEDS do
		table.insert(cases, { kind = kind, seed = seed, plan = HouseLayout.plan(seed, kind) })
	end
end

local function apart(a: Rect, b: Rect): number
	local dx = math.max(a.x0 - b.x1, 0, b.x0 - a.x1)
	local dz = math.max(a.z0 - b.z1, 0, b.z0 - a.z1)
	return math.sqrt(dx * dx + dz * dz)
end

local function roomOf(plan: any, spot: number): string?
	for _, s in plan.spots do
		if s.id == spot then
			return s.room
		end
	end
	return nil
end

local function spotOf(plan: any, spot: number): any
	for _, s in plan.spots do
		if s.id == spot then
			return s
		end
	end
	return nil
end

do
	local within, same, locksMade, vaultsMade, hazardsMade = true, true, 0, 0, 0
	local detail = ""
	for _, c in cases do
		for _, id in ORDER do
			local level = R.Danger[id]
			local p = DangerRules.plan(c.plan, id)
			local q = DangerRules.plan(c.plan, id)
			local counts = { creak = 0, puddle = 0, plaster = 0 }
			for _, h in p.hazards do
				counts[h.kind] += 1
			end
			local ok = #p.locks <= level.Locks and counts.creak <= level.Creak and counts.puddle <= level.Puddle and counts.plaster <= level.Plaster
				and (if p.vault then #p.vault.spots >= 1 and #p.vault.spots <= level.Vault else true) and (level.Vault > 0 or p.vault == nil)
			if not ok and detail == "" then
				detail = `{c.kind} {c.seed} {id}`
			end
			within = within and ok
			same = same and #p.locks == #q.locks and #p.hazards == #q.hazards and (p.vault == nil) == (q.vault == nil)
			for n, lock in p.locks do
				same = same and q.locks[n].door == lock.door and q.locks[n].key == lock.key
			end
			for n, h in p.hazards do
				same = same and q.hazards[n].x == h.x and q.hazards[n].z == h.z
			end
			locksMade += #p.locks
			hazardsMade += #p.hazards
			vaultsMade += if p.vault then 1 else 0
		end
	end
	check(`every plan (6 places × {#SEEDS} seeds × 5 difficulties) within its difficulty's counts`, within, detail)
	check("… the same house at the same difficulty, the same danger (its locks, keys, hazards)", same)
	check(`… and they hold some: {locksMade} locks, {vaultsMade} vaults, {hazardsMade} hazards`, locksMade >= #cases * 5 and vaultsMade >= #cases * 3 and hazardsMade >= #cases * 10)
end

-- ── The locks and their keys ───────────────────────────────────────────────
do
	local lockable, keys, chain, vaultKey, lifted = true, true, true, true, true
	local detail = ""
	for _, c in cases do
		local plan = c.plan
		for _, option in DangerRules.lockable(plan) do
			local door = plan.doors[option.door]
			lockable = lockable and door.rooms[1] ~= "outside" and door.rooms[2] ~= "outside" and #option.behind > 0
				and table.find(option.behind, option.room) ~= nil
			local reach = DangerRules.reachable(plan, { [option.door] = true })
			for _, room in option.behind do
				lockable = lockable and not reach[room]
			end
		end
		for _, id in ORDER do
			local p = DangerRules.plan(plan, id)
			local shut: { [number]: boolean } = {}
			for _, lock in p.locks do
				shut[lock.door] = true
				local keyRoom = roomOf(plan, lock.key)
				local ok = keyRoom ~= nil and keyRoom ~= lock.room and table.find(lock.behind, keyRoom) == nil and DangerRules.searchable(spotOf(plan, lock.key).item)
					and p.keys[lock.key] ~= nil
				if not ok and detail == "" then
					detail = `{c.kind} {c.seed} {id}: the {lock.name}'s key in {keyRoom}`
				end
				keys = keys and ok
			end
			-- open them as a party would: a lock whose key lies in a room you can get to now, one after the other
			local opened = 0
			local progress = true
			while progress do
				progress = false
				local open = DangerRules.reachable(plan, shut)
				for _, lock in p.locks do
					if shut[lock.door] and open[roomOf(plan, lock.key) :: string] then
						shut[lock.door] = nil
						opened += 1
						progress = true
						break
					end
				end
			end
			chain = chain and opened == #p.locks
			local vault = p.vault
			if vault then
				local all = DangerRules.reachable(plan, nil)
				vaultKey = vaultKey and all[roomOf(plan, vault.key) :: string] == true and table.find(vault.spots, vault.key) == nil and p.keys[vault.key] == "vault"
					and table.find(p.searchable, vault.key) ~= nil
				for _, spot in vault.spots do
					vaultKey = vaultKey and table.find(p.searchable, spot) == nil and p.lifts[spot] == nil
						and (FurnitureLooks.Items[spotOf(plan, spot).item] :: any).class ~= "pair"
				end
			end
			for _, lock in p.locks do
				for _, s in plan.spots do
					if table.find(lock.behind, s.room) and not (vault and table.find(vault.spots, s.id)) then
						lifted = lifted and p.lifts[s.id] == R.Locks.Lift
					end
				end
			end
		end
	end
	check("a lockable doorway is an inside one and cuts its rooms off the way in (never a room you come in by)", lockable)
	check("every lock's key in a searchable piece of another room, never behind its own lock", keys, detail)
	check("… so the locks open one after the other: every key reachable before its lock (no key locked in for good)", chain)
	check("the vault's gold key: in a reachable searchable piece, never in the vault; its pieces never two-person, never searched", vaultKey)
	check("a locked room's pieces a tier up (Config.Runs.Locks.Lift; the vault's own floor instead)", lifted)
end

-- ── The hazards: never in a doorway, never on the way out ──────────────────
do
	local placed, doorway, ways = true, true, true
	local detail = ""
	local G = R.Hazard.Gap
	for index, c in cases do
		local plan = c.plan
		local pieces: { Rect } = {}
		for _, s in plan.spots do
			table.insert(pieces, DangerRules.footprint(s))
		end
		local doors: { Rect } = {}
		for _, door in plan.doors do
			table.insert(doors, DangerRules.doorRect(plan, door))
		end
		local entry = plan.entry.Position
		-- (an A* on its own grid, from the way in: the doorways and the pieces it gets to with the pieces standing)
		local grid = HouseRoute.grid(plan, R.Hazard.Radius, 1) :: HouseRoute.Grid
		HouseRoute.block(grid, pieces)
		local doorsBefore: { [number]: boolean } = {}
		for n, door in plan.doors do
			doorsBefore[n] = HouseRoute.path(grid, entry.X, entry.Z, door.at.X, door.at.Z, 2) ~= nil
		end
		local deep = index % 2 == 0 -- (every other plan: every piece's reach too, the slow check)
		local piecesBefore: { [number]: boolean } = {}
		if deep then
			for n, r in pieces do
				piecesBefore[n] = HouseRoute.reach(grid, entry.X, entry.Z, r, 3) ~= nil
			end
		end
		for _, id in ORDER do
			local p = DangerRules.plan(plan, id)
			for _, h in p.hazards do
				local inRoom = false
				for _, room in plan.rooms do
					inRoom = inRoom or (h.rect.x0 >= room.min.X and h.rect.x1 <= room.max.X and h.rect.z0 >= room.min.Z and h.rect.z1 <= room.max.Z)
				end
				local clear = HouseRoute.toRect(entry.X, entry.Z, h.rect) >= G.Entry - 1e-6
				for _, r in pieces do
					clear = clear and apart(h.rect, r) >= G.Piece - 1e-6
				end
				placed = placed and inRoom and clear
				for _, d in doors do
					doorway = doorway and apart(h.rect, d) >= G.Door - 1e-6
				end
			end
			if #p.hazards == 0 then
				continue
			end
			local blocked = table.clone(pieces)
			for _, h in p.hazards do
				table.insert(blocked, h.rect)
			end
			HouseRoute.block(grid, blocked)
			for n, door in plan.doors do
				if doorsBefore[n] and HouseRoute.path(grid, entry.X, entry.Z, door.at.X, door.at.Z, 2) == nil then
					ways = false
					detail = `{c.kind} {c.seed} {id}: door {n}`
				end
			end
			if deep and (id == "hard" or id == "nightmare") then
				for n, r in pieces do
					if piecesBefore[n] and HouseRoute.reach(grid, entry.X, entry.Z, r, 3) == nil then
						ways = false
						detail = `{c.kind} {c.seed} {id}: piece {n}`
					end
				end
			end
			HouseRoute.block(grid, pieces)
		end
	end
	check("every hazard on a room's floor, off every piece (Gap.Piece) and the way in (Gap.Entry)", placed)
	check("… never in or by a doorway (Gap.Door studs from every doorway's opening)", doorway)
	check("… never on the way out: every doorway and every piece reachable without them still is, with them", ways, detail)
end

-- ── The vault's pieces ─────────────────────────────────────────────────────
do
	local epic, legendaryOnly, value = true, true, true
	local legendaries = 0
	for _, c in cases do
		for _, id in ORDER do
			local p = DangerRules.plan(c.plan, id)
			local vault = p.vault
			if not vault then
				continue
			end
			local list: { LootRules.Piece } = {}
			for _, s in c.plan.spots do
				table.insert(list, { spot = s.id, item = s.item })
			end
			local rolled = LootRules.roll(list, id, c.plan.seed)
			for _, spot in vault.spots do
				local floor = vault.floors[spot]
				local roll = rolled[spot]
				local lifted = LootRules.lift(roll, 0, floor)
				epic = epic and LootRules.rank(lifted.rarity) >= LootRules.rank("epic")
				value = value and lifted.value >= roll.value
				if floor == "legendary" then
					legendaries += 1
					legendaryOnly = legendaryOnly and id == "nightmare" and lifted.rarity == "legendary"
				end
				legendaryOnly = legendaryOnly and (floor == "epic" or floor == "legendary")
			end
		end
	end
	check("the vault's pieces come Epic or better (LootRules.lift to its floor), worth more, never less", epic and value)
	check(`… a Legendary floor only on Nightmare ({legendaries} of them over the plans)`, legendaryOnly and legendaries > 0)
	local roll: LootRules.Roll = { rarity = "rare", stars = 3, value = 450, own = "uncommon", base = 300 }
	local up = LootRules.lift(roll, 1)
	local top = LootRules.lift({ rarity = "legendary", stars = 5, value = 7000, own = "legendary", base = 7000 }, 2)
	local old = LootRules.lift({ rarity = "common", stars = 1, value = 90, own = "common" }, 1)
	check("LootRules.lift: a tier up worth Config.Loot.Lift more (from its base), never past Legendary, an older roll from its value",
		up.rarity == "epic" and up.value == math.floor(300 * Config.Loot.Lift ^ 2 + 0.5) and top.rarity == "legendary" and top.value == 7000
			and old.rarity == "uncommon" and old.value == math.floor(90 * Config.Loot.Lift + 0.5) and LootRules.lift(roll, 0) == roll)
end

-- ── Danny's route through a locked, then opened, door ─────────────────────
do
	local tried, shutOk, openOk, sightOk, floorOk, sameKey = 0, true, true, true, true, true
	for _, c in cases do
		local p = DangerRules.plan(c.plan, "hard")
		local lock = p.locks[1]
		if not lock then
			continue
		end
		local behind: any = nil
		for _, s in c.plan.spots do
			if s.room == lock.room then
				behind = s
				break
			end
		end
		if not behind then
			continue
		end
		tried += 1
		local plan = c.plan
		local grid = HouseRoute.grid(plan, nil, nil, Config.MoveHelper.Walk.Clear) :: HouseRoute.Grid
		local pieces: { Rect } = {}
		for _, s in plan.spots do
			table.insert(pieces, DangerRules.footprint(s))
		end
		HouseRoute.block(grid, pieces)
		local entry = plan.entry.Position
		local piece = DangerRules.footprint(behind)
		local door = plan.doors[lock.door]
		local before = HouseRoute.reach(grid, entry.X, entry.Z, piece) ~= nil
		local changed = HouseRoute.shut(grid, { lock.rect }, {}, "locked")
		sameKey = sameKey and changed and not HouseRoute.shut(grid, { lock.rect }, {}, "locked")
		local mx, mz = (piece.x0 + piece.x1) / 2, (piece.z0 + piece.z1) / 2
		local across = if door.axis == "X" then 3 else 0
		local acrossX = if door.axis == "X" then 0 else 3
		shutOk = shutOk and HouseRoute.reach(grid, entry.X, entry.Z, piece) == nil
		sightOk = sightOk and not HouseRoute.sees(grid, door.at.X - acrossX, door.at.Z - across, door.at.X + acrossX, door.at.Z + across)
		HouseRoute.shut(grid, {}, {}, "open")
		openOk = openOk and (not before or HouseRoute.reach(grid, entry.X, entry.Z, piece) ~= nil)
			and HouseRoute.sees(grid, door.at.X - acrossX, door.at.Z - across, door.at.X + acrossX, door.at.Z + across)
		-- a hazard's floor: closed for his feet, never for his eyes
		local h = DangerRules.plan(plan, "nightmare").hazards[1]
		if h then
			HouseRoute.shut(grid, {}, { h.rect }, "floor")
			floorOk = floorOk and not HouseRoute.open(grid, h.x, h.z) and HouseRoute.sees(grid, h.rect.x0 - 1, h.z, h.rect.x1 + 1, h.z)
			HouseRoute.shut(grid, {}, {}, "none")
			floorOk = floorOk and HouseRoute.open(grid, h.x, h.z)
		end
		local _ = mx + mz
	end
	check(`Danny's route through a locked doorway: no spot by the piece behind it, no sight through it ({tried} houses)`, tried >= #KINDS * 2 and shutOk and sightOk)
	check("… opened, his way to that piece and his sight through the doorway again", openOk)
	check("… the same set again changes nothing (HouseRoute.shut's key)", sameKey)
	check("… a hazard's floor closed for his feet (he walks round it), never for his sight, and open again once gone", floorOk)
end

-- ── The small rules ────────────────────────────────────────────────────────
do
	local hs: { DangerRules.Hazard } = {
		{ kind = "creak", x = 0, z = 0, sx = 4, sz = 4, rect = { x0 = -2, z0 = -2, x1 = 2, z1 = 2 } },
		{ kind = "puddle", x = 10, z = 0, sx = 5, sz = 3, rect = { x0 = 7.5, z0 = -1.5, x1 = 12.5, z1 = 1.5 } },
	}
	local near, far = DangerRules.nearest(hs, 6, 0, 10)
	check("a hazard under a point (its rect), none off it; the nearest within a range and its studs",
		(DangerRules.hazardAt(hs, 1, 1) :: any).kind == "creak" and DangerRules.hazardAt(hs, 4, 4) == nil and (near :: any).kind == "puddle" and math.abs(far - 1.5) < 1e-9
			and DangerRules.nearest(hs, 40, 40, 10) == nil)
	check("the wave once Zombies.WaveAt of the clock is gone (and never on a bad clock)", not DangerRules.waveDue(100, 600, 100 + 600 * R.Zombies.WaveAt - 1)
		and DangerRules.waveDue(100, 600, 100 + 600 * R.Zombies.WaveAt) and not DangerRules.waveDue(100, 0, 1000))
	local seen: { [string]: number } = {}
	for n = 0, 999 do
		local kind = DangerRules.pickKind(R.Danger.nightmare.Kinds, n / 1000)
		seen[kind] = (seen[kind] or 0) + 1
	end
	check("a zombie's kind by the weights (Nightmare: walkers most, every kind of its list), a walker without any",
		(seen.walker or 0) > (seen.runner or 0) and (seen.brute or 0) > 0 and (seen.bloater or 0) > 0 and DangerRules.pickKind({}, 0.5) == "walker")
	check("a creak's knock and the plaster's damage grow with the difficulty", DangerRules.knock("nightmare") > DangerRules.knock("easy")
		and DangerRules.plasterDamage("nightmare") > DangerRules.plasterDamage("normal") and DangerRules.plasterDamage("normal") > 0)
	check("the HUD's words: a hint per hazard, the party's lines", DangerRules.hint("creak"):find("Creaky") ~= nil and DangerRules.hint("puddle"):find("puddle") ~= nil
		and DangerRules.hint("plaster"):find("plaster") ~= nil and DangerRules.keyText("Bedroom key", "Ann") == "🔑 Bedroom key found by Ann"
		and DangerRules.vaultText("Ann") == "🗝 Ann opened the vault" and DangerRules.lockText("Study", "Bob") == "🔓 Bob unlocked the Study")
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
