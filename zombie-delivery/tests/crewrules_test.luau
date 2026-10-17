-- 10.1 THE HELPERS' CREW: shared/CrewRules.luau, the rules of a player's crew of NPC helpers (Config.Crew): the kinds
-- (Danny the base, Bruno the strong one, Zip the quick one, Gus the guard, Lucy the finder) and what each may carry,
-- their speeds and health, their looks; the save (a new player's Danny, a saved crew cleaned, the migration only for a
-- real save with the flag); the hospital (its clock, healing, the discharge's price); who comes into a run (the pick, the
-- first ready one instead, nobody); the rescue (the odds per difficulty, who is trapped, the bonus); down in a run (the
-- revive's clock and health); the CREW window's rows. The server's side (the moves' runtime: Danny free from the start,
-- Bruno with a piece for two alone, a rescue into the saved crew, down, revive and out to hospital, the save):
-- tests/crew_runtime_test.luau and tests/saving_runtime_test.luau. Run with tests/run_tests.py.
local Config = require("./Config")
local CrewRules = require("./CrewRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local C = Config.Crew
local NOW = 1760000000

-- ── The kinds ──────────────────────────────────────────────────────────────

do
	local ids = CrewRules.kinds()
	check("five kinds in the window's order, Danny (the default) first", #ids == 5 and ids[1] == "danny" and ids[1] == C.Default
		and table.concat(ids, ",") == "danny,bruno,zip,gus,lucy", table.concat(ids, ","))
	local whole = true
	local names: { [string]: boolean } = {}
	for _, id in ids do
		local def = CrewRules.def(id)
		whole = whole and def ~= nil and type(def.Name) == "string" and #def.Name > 0 and type(def.Ability) == "string" and def.Speed > 0 and def.Health > 0
			and type(def.Hello) == "string" and type(def.Freed) == "string" and type(def.Up) == "string" and type(def.Look) == "table"
		if def then
			names[def.Name] = true
		end
	end
	check("…each has a name, an ability, a speed, health, its words and a look; no two the same name", whole and names.Danny and names.Bruno
		and names.Zip and names.Gus and names.Lucy)
	check("…an unknown kind is none", CrewRules.def("bob") == nil and CrewRules.def(nil) == nil and CrewRules.def(4) == nil)
	check("…the name tag's second line: \"Strong · ZDC Moving\" (Config.MoveHelper.Title)", CrewRules.title("bruno") == `Strong · {Config.MoveHelper.Title}`
		and CrewRules.title("danny") == `Mover · {Config.MoveHelper.Title}`)
	check("…Lucy is she, her; the others he, his", CrewRules.he("lucy") == "she" and CrewRules.his("lucy") == "her" and CrewRules.he("gus", true) == "He"
		and CrewRules.his("zip") == "his")
	-- a distinct look each: the shirt's colour, the hat or an apron
	local looks: { [string]: any } = {}
	local shirts: { [string]: boolean } = {}
	local distinct = true
	for _, id in ids do
		local look = CrewRules.look(id)
		looks[id] = look
		local key = table.concat(look.shirt or {}, ",")
		distinct = distinct and not shirts[key] and look.name == CrewRules.def(id).Name and look.title == CrewRules.title(id)
		shirts[key] = true
	end
	check("…a distinct look each: his own shirt's colour, his name and title on the tag", distinct)
	check("…Danny the orange mover with his cap; Bruno a dark beanie and a leather apron; Gus a helmet and a vest; Lucy a beanie and an apron",
		looks.danny.hat == "cap" and looks.danny.shirt[1] == 230 and looks.bruno.hat == "beanie" and looks.bruno.apron ~= nil and looks.gus.hat == "helmet"
		and looks.gus.vest ~= nil and looks.lucy.hat == "beanie" and looks.lucy.apron ~= nil and looks.zip.hat == "cap" and looks.zip.hatColor[3] == 230)
end

-- ── What each may carry ────────────────────────────────────────────────────

do
	local function may(id: string, class: string, weight: number): string
		local ok, why = CrewRules.mayCarry(id, class, weight)
		return if ok then "yes" else tostring(why)
	end
	check("Danny: one-hand, both-hands (any weight) and a piece for two (with you)", may("danny", "hand", 3) == "yes" and may("danny", "both", 6) == "yes"
		and may("danny", "pair", 10) == "yes" and CrewRules.lifts("danny") and not CrewRules.solo("danny"))
	check("Bruno: everything; a piece for two ALONE too (and with you)", may("bruno", "hand", 1) == "yes" and may("bruno", "both", 6) == "yes"
		and may("bruno", "pair", 10) == "yes" and CrewRules.solo("bruno") and CrewRules.lifts("bruno"))
	check(`Zip: one-hand; small both-hands up to weight {C.Kinds.zip.Carry.Both}; no heavy one, never a piece for two`, may("zip", "hand", 3) == "yes"
		and may("zip", "both", C.Kinds.zip.Carry.Both) == "yes" and may("zip", "both", C.Kinds.zip.Carry.Both + 1) == "heavy" and may("zip", "pair", 5) == "pair"
		and not CrewRules.lifts("zip") and not CrewRules.solo("zip"))
	check("Gus carries nothing at all (\"nothing\"), never lifts with you", may("gus", "hand", 1) == "nothing" and may("gus", "both", 2) == "nothing"
		and may("gus", "pair", 5) == "nothing" and not CrewRules.lifts("gus"))
	check(`Lucy: small pieces: one-hand, both-hands up to {C.Kinds.lucy.Carry.Both}; no piece for two`, may("lucy", "hand", 2) == "yes"
		and may("lucy", "both", C.Kinds.lucy.Carry.Both) == "yes" and may("lucy", "both", 3) == "heavy" and may("lucy", "pair", 5) == "pair"
		and not CrewRules.lifts("lucy"))
	check("…a weight that is no number counts as the heaviest", may("zip", "both", 0 / 0) == "heavy" and may("danny", "both", 0 / 0) == "yes")
	check("…the window's words for it", CrewRules.carryText("gus") == "Carries nothing" and string.find(CrewRules.carryText("bruno"), "two-person ones alone", 1, true) ~= nil
		and string.find(CrewRules.carryText("danny"), "with you", 1, true) ~= nil and string.find(CrewRules.carryText("zip"), "small both-hands", 1, true) ~= nil
		and string.find(CrewRules.carryText("zip"), "two-person", 1, true) == nil)
end

-- ── Speeds and health ──────────────────────────────────────────────────────

do
	check("speeds: Zip the fastest, Bruno the slowest, Danny 1", CrewRules.pace("zip") > CrewRules.pace("lucy") and CrewRules.pace("lucy") >= CrewRules.pace("danny")
		and CrewRules.pace("danny") == 1 and CrewRules.pace("bruno") < 1 and CrewRules.pace("zip") == C.Kinds.zip.Speed)
	check("…Bruno with a piece for two alone: × Solo on top of his carry's drag (slow, not crawling)", CrewRules.pace("bruno", true) == C.Kinds.bruno.Speed * C.Kinds.bruno.Solo
		and Config.Moving.Speed.Drag * CrewRules.pace("bruno", true) < Config.Moving.Speed.Both and Config.Moving.Speed.Drag * CrewRules.pace("bruno", true) > Config.Moving.Speed.Drag)
	check("…an unknown kind walks as Danny", CrewRules.pace("bob") == CrewRules.pace("danny"))
	check("health: Gus the toughest, Zip the frailest, Bruno over Danny", CrewRules.health("gus") > CrewRules.health("bruno") and CrewRules.health("bruno") > CrewRules.health("danny")
		and CrewRules.health("zip") < CrewRules.health("danny"))
	check("Lucy alone senses the loot (Sense), Gus alone guards", C.Kinds.lucy.Sense > 0 and C.Kinds.danny.Sense == 0 and C.Kinds.bruno.Sense == 0
		and C.Kinds.gus.Guard ~= nil and C.Kinds.danny.Guard == nil and C.Kinds.gus.Guard.Damage > 0 and C.Kinds.gus.Guard.Leash >= C.Kinds.gus.Guard.Range)
end

-- ── The save ───────────────────────────────────────────────────────────────

do
	local fresh = CrewRules.empty()
	check("a new player: Danny alone, picked, nobody in hospital", #fresh.have == 1 and fresh.have[1] == "danny" and fresh.pick == "danny" and next(fresh.hospital) == nil)
	local cleaned = CrewRules.clean({ have = { "lucy", "bob", "bruno", "lucy", 7 }, pick = "lucy", hospital = { lucy = NOW + 60, zip = NOW + 60, bruno = 2.5 } })
	check("a saved crew cleaned: known kinds once each in the order, Danny always first", table.concat(cleaned.have, ",") == "danny,bruno,lucy")
	check("…the pick kept when it is in the crew", cleaned.pick == "lucy")
	check("…hospital times only for the crew's own and whole numbers", cleaned.hospital.lucy == NOW + 60 and cleaned.hospital.zip == nil and cleaned.hospital.bruno == nil)
	check("…a pick out of the crew is Danny again", CrewRules.clean({ have = { "bruno" }, pick = "gus" }).pick == "danny")
	check("…junk is a new player's crew", #CrewRules.clean("x").have == 1 and CrewRules.clean(nil).pick == "danny" and #CrewRules.clean({ have = "x" }).have == 1)
	-- the migration: only a real save (money in it) written with the flag
	local real = { money = 100, crew = { have = { "danny", "zip" }, pick = "zip" }, [C.Flag] = true }
	check("the migration: a real save with the flag keeps its crew", table.concat(CrewRules.fromSave(real).have, ",") == "danny,zip" and CrewRules.fromSave(real).pick == "zip")
	check("…an older real save (no flag, from the hire's days: nothing about it saved): Danny alone, free", table.concat(CrewRules.fromSave({ money = 100, crew = real.crew }).have, ",") == "danny")
	check("…no real save (no money: a lock-only record): Danny alone", #CrewRules.fromSave({ crew = real.crew, [C.Flag] = true }).have == 1
		and #CrewRules.fromSave(nil).have == 1)
	local written = CrewRules.toSave(cleaned)
	check("what a save writes: a copy (have, pick, hospital)", written.have ~= cleaned.have and table.concat(written.have, ",") == "danny,bruno,lucy" and written.pick == "lucy"
		and written.hospital ~= cleaned.hospital and written.hospital.lucy == NOW + 60)
	local again = CrewRules.fromSave({ money = 5, crew = written, [C.Flag] = true })
	check("…read back the same", table.concat(again.have, ",") == "danny,bruno,lucy" and again.pick == "lucy" and again.hospital.lucy == NOW + 60)
	-- add
	local crew = CrewRules.empty()
	check("a rescue adds Gus (new: true), in the window's order", CrewRules.add(crew, "gus") and table.concat(crew.have, ",") == "danny,gus")
	check("…then Bruno before him", CrewRules.add(crew, "bruno") and table.concat(crew.have, ",") == "danny,bruno,gus")
	check("…Gus again: not new, nothing changes; an unknown kind: nothing", not CrewRules.add(crew, "gus") and not CrewRules.add(crew, "bob") and #crew.have == 3)
	check("…has", CrewRules.has(crew, "gus") and not CrewRules.has(crew, "zip") and not CrewRules.has(crew, nil))
end

-- ── The hospital ───────────────────────────────────────────────────────────

do
	local crew = CrewRules.clean({ have = { "danny", "bruno", "zip" }, pick = "bruno" })
	CrewRules.toHospital(crew, "bruno", NOW)
	check(`out of a run: in hospital {C.Hospital.Seconds} s`, CrewRules.hospitalLeft(crew, "bruno", NOW) == C.Hospital.Seconds and not CrewRules.ready(crew, "bruno", NOW)
		and CrewRules.ready(crew, "bruno", NOW + C.Hospital.Seconds))
	check("…a kind not in the crew never goes", (function()
		CrewRules.toHospital(crew, "gus", NOW)
		return crew.hospital.gus == nil
	end)())
	check("…time left counts down; none for one not in hospital", CrewRules.hospitalLeft(crew, "bruno", NOW + 100) == C.Hospital.Seconds - 100
		and CrewRules.hospitalLeft(crew, "zip", NOW) == 0)
	check("…heal drops the times past", not CrewRules.heal(crew, NOW + 10) and crew.hospital.bruno ~= nil and CrewRules.heal(crew, NOW + C.Hospital.Seconds)
		and crew.hospital.bruno == nil)
	local H = C.Hospital
	check(`the discharge's price: {H.Base} + {H.PerMinute} a minute left (whole minutes up), to {H.Round}`, CrewRules.dischargePrice(H.Seconds) == H.Base + H.PerMinute * math.ceil(H.Seconds / 60)
		and CrewRules.dischargePrice(61) == H.Base + H.PerMinute * 2 and CrewRules.dischargePrice(1) == H.Base + H.PerMinute)
	check("…nothing left: free; junk: free", CrewRules.dischargePrice(0) == 0 and CrewRules.dischargePrice(-5) == 0 and CrewRules.dischargePrice(0 / 0) == 0)
	check("…a price is whole dollars of Round", CrewRules.dischargePrice(H.Seconds) % H.Round == 0)
end

-- ── Who comes ──────────────────────────────────────────────────────────────

do
	local crew = CrewRules.clean({ have = { "danny", "bruno", "lucy" }, pick = "lucy" })
	check("the pick checked: yours ok, the same, not yours, unknown", CrewRules.pickCheck(crew, "bruno") == "ok" and CrewRules.pickCheck(crew, "lucy") == "same"
		and CrewRules.pickCheck(crew, "zip") == "locked" and CrewRules.pickCheck(crew, "bob") == "unknown")
	local who, instead = CrewRules.comes(crew, NOW)
	check("who comes: your pick when ready", who == "lucy" and instead == false)
	CrewRules.toHospital(crew, "lucy", NOW)
	who, instead = CrewRules.comes(crew, NOW)
	check("…your pick in hospital: the first ready one instead (Danny)", who == "danny" and instead == true)
	CrewRules.toHospital(crew, "danny", NOW)
	who, instead = CrewRules.comes(crew, NOW)
	check("…Danny too: Bruno", who == "bruno" and instead == true)
	CrewRules.toHospital(crew, "bruno", NOW)
	who = CrewRules.comes(crew, NOW)
	check("…all of them in hospital: nobody comes", who == nil)
	who, instead = CrewRules.comes(crew, NOW + C.Hospital.Seconds)
	check("…out of hospital again: your pick", who == "lucy" and instead == false)
	check("a new player: Danny comes", (CrewRules.comes(CrewRules.empty(), NOW)) == "danny")
end

-- ── The rescue ─────────────────────────────────────────────────────────────

do
	local last = -1
	local rising = true
	for _, id in Config.Runs.Difficulties do
		local chance = CrewRules.rescueChance(id.id)
		rising = rising and chance > last and chance > 0 and chance < 1
		last = chance
	end
	check("a trapped helper's odds rise with the difficulty (Easy the least, Nightmare the most), never sure", rising)
	check("…an unknown difficulty: Normal's", CrewRules.rescueChance("bob") == CrewRules.rescueChance("normal"))
	check("…the roll under the odds", CrewRules.rescueRoll("hard", CrewRules.rescueChance("hard") - 0.01) and not CrewRules.rescueRoll("hard", CrewRules.rescueChance("hard"))
		and not CrewRules.rescueRoll("easy", 0.5) and CrewRules.rescueRoll("nightmare", 0.5))
	check("who is trapped: the kind the most of the party lack", CrewRules.rescueKind({ bruno = 1, zip = 3, lucy = 2 }, 0) == "zip")
	check("…ties by the roll", CrewRules.rescueKind({ bruno = 2, gus = 2 }, 0) == "bruno" and CrewRules.rescueKind({ bruno = 2, gus = 2 }, 0.9) == "gus")
	check("…never Danny (everybody has him)", CrewRules.rescueKind({ danny = 4 }, 0.1) ~= "danny")
	local any: { [string]: boolean } = {}
	for n = 0, 9 do
		any[CrewRules.rescueKind({}, n / 10)] = true
	end
	check("…nobody lacks one: any kind but Danny (the bonus for everybody)", any.bruno and any.zip and any.gus and any.lucy and not any.danny)
	check("the bonus instead rises with the difficulty", CrewRules.rescueBonus("easy") < CrewRules.rescueBonus("normal") and CrewRules.rescueBonus("normal") < CrewRules.rescueBonus("hard")
		and CrewRules.rescueBonus("insane") < CrewRules.rescueBonus("nightmare") and CrewRules.rescueBonus("bob") == CrewRules.rescueBonus("normal"))
	check("…untie by holding E a few seconds", C.Rescue.Hold >= 2 and C.Rescue.Hold <= 4 and C.Rescue.Reach > 4)
end

-- ── Down in a run ──────────────────────────────────────────────────────────

do
	local D = C.Down
	check(`down: {D.Seconds} s to revive him`, CrewRules.downLeft(100, 100) == D.Seconds and CrewRules.downLeft(100, 100 + D.Seconds - 1) == 1
		and CrewRules.downLeft(100, 100 + D.Seconds) == 0 and CrewRules.downLeft(100, 500) == 0)
	check("…revived by holding E about 3 s", D.Revive >= 2 and D.Revive <= 4 and D.Revive < D.Seconds)
	check("…up with half his health", CrewRules.reviveHealth("danny") == math.floor(C.Kinds.danny.Health * D.Health + 0.5) and D.Health == 0.5
		and CrewRules.reviveHealth("gus") == C.Kinds.gus.Health / 2)
end

-- ── The window ─────────────────────────────────────────────────────────────

do
	local crew = CrewRules.clean({ have = { "danny", "bruno" }, pick = "bruno" })
	CrewRules.toHospital(crew, "danny", NOW)
	local rows = CrewRules.view(crew, NOW + 30)
	check("the window: every kind, in order", #rows == 5 and rows[1].id == "danny" and rows[5].id == "lucy")
	check("…Danny in hospital: the time left and the discharge's price", rows[1].state == "hospital" and rows[1].left == C.Hospital.Seconds - 30
		and rows[1].price == CrewRules.dischargePrice(C.Hospital.Seconds - 30) and rows[1].have)
	check("…Bruno ready and picked", rows[2].state == "ready" and rows[2].pick and rows[2].price == 0)
	check("…the rest not yet in the crew (rescue them in runs)", rows[3].state == "locked" and not rows[3].have and rows[4].state == "locked" and rows[5].state == "locked")
	check("…each row's words", rows[4].name == "Gus" and rows[4].icon == C.Kinds.gus.Icon and rows[4].carry == "Carries nothing" and rows[5].ability == C.Kinds.lucy.Ability)
	check("the clock's words", CrewRules.clock(240) == "4:00" and CrewRules.clock(61) == "1:01" and CrewRules.clock(0.2) == "0:01" and CrewRules.clock(-3) == "0:00")
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
