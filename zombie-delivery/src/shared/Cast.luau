--!strict
-- The story's people (6.8): one entry per character the mission chapters (shared/Missions.luau) and the world share,
-- so a name always comes with the same words, the same look (an NPC role of shared/NpcLooks.luau: Npcs.look hashes the
-- name and the role, so both must match for the same face) and the same place.
--
--   id     the key the missions use (Campaign.clientId, a Spec's giver / receiver)
--   name   the name over the head and in the texts ("Doctor Ellie"); NpcLooks.look(look, name) draws them
--   label  the giver / receiver line of a mission ("Doctor Ellie, the City Clinic"; server/Jobs.luau personFrom
--          splits it at the comma into the name and the title)
--   job    the MISSIONS window's role line ("Head doctor")
--   place  where you find them ("City Clinic")
--   look   the NPC role (shared/NpcLooks.luau): their clothes
--
-- The world's people with the same name use the same look: Chief Carlos at Fire Station 9 (server/World.luau),
-- Captain Maria, Doctor Ellie, Walt and Old Man Jed at their boards (Config.Employers), Marge at the depot
-- (Config.Tutorial), Engineer Ivan, Doctor Hiro, Vinnie, Rocco and Emma in Config.Jobs (tests/missions_test.luau
-- checks the names it can see).
-- Pure data: required by shared/Missions.luau, the client's portraits (client/Portrait.luau) and the tests.

local Cast = {}

export type Person = {
	id: string,
	name: string,
	label: string,
	job: string,
	place: string,
	look: string,
}

Cast.People = {
	-- The clients: one chapter each (shared/Missions.luau Campaign.clientId).
	{ id = "marge", name = "Marge", label = "Marge, the dispatcher", job = "Dispatcher", place = "Dead End Dispatch", look = "clerk" },
	{ id = "ellie", name = "Doctor Ellie", label = "Doctor Ellie, the City Clinic", job = "Head doctor", place = "City Clinic", look = "doctor" },
	{ id = "raj", name = "Raj", label = "Raj, FreshMart's owner", job = "Grocer", place = "FreshMart", look = "grocer" },
	{ id = "rosa", name = "Rosa", label = "Rosa, the planner twin", job = "Courier, the one who plans", place = "Survivor Camp", look = "mover" },
	{ id = "rico", name = "Rico", label = "Rico, Rosa's twin", job = "Courier, the one who jokes", place = "Survivor Camp", look = "mover" },
	{ id = "carlos", name = "Chief Carlos", label = "Chief Carlos, Fire Station 9", job = "Fire chief", place = "Fire Station 9", look = "firefighter" },
	{ id = "maria", name = "Captain Maria", label = "Captain Maria, the Military Base", job = "Base commander", place = "Military Base", look = "officer" },
	{ id = "ivan", name = "Engineer Ivan", label = "Engineer Ivan, the Power Plant", job = "Chief engineer", place = "Power Plant", look = "foreman" },
	{ id = "walt", name = "Walt", label = "Walt, the rancher", job = "Rancher", place = "Silver Spur Ranch", look = "rancher" },
	{ id = "hiro", name = "Doctor Hiro", label = "Doctor Hiro, the lab chief", job = "Lab chief", place = "Biotech Lab", look = "doctor" },
	{ id = "vinnie", name = "Vinnie", label = "Vinnie, the fixer", job = "Fixer", place = "Second Life Pawn", look = "banker" },
	{ id = "ruth", name = "Mayor Ruth", label = "Mayor Ruth, City Hall", job = "Mayor", place = "City Hall", look = "clerk" },
	-- The people who come back from chapter to chapter.
	{ id = "ada", name = "Nurse Ada", label = "Nurse Ada", job = "Nurse", place = "City Clinic", look = "nurse" },
	{ id = "rocco", name = "Rocco", label = "Rocco, the harbor boss", job = "Harbor boss", place = "Harbor Warehouse", look = "foreman" },
	{ id = "jed", name = "Old Man Jed", label = "Old Man Jed, the farmer", job = "Farmer", place = "Old Farm", look = "farmer" },
	{ id = "dan", name = "Coach Dan", label = "Coach Dan, the shelter warden", job = "Shelter warden", place = "Stadium Shelter", look = "guard" },
	{ id = "luna", name = "DJ Luna", label = "DJ Luna, the radio host", job = "Radio host", place = "Radio Station", look = "clerk" },
	{ id = "sue", name = "Detective Sue", label = "Detective Sue", job = "Detective", place = "Precinct 13", look = "officer" },
	{ id = "jo", name = "Captain Jo", label = "Captain Jo, the last pilot", job = "Pilot", place = "Old Airfield", look = "officer" },
	{ id = "tom", name = "Old Tom", label = "Old Tom, the lighthouse keeper", job = "Lighthouse keeper", place = "Lighthouse Point", look = "townsperson" },
	{ id = "martha", name = "Martha", label = "Martha, the camp leader", job = "Camp leader", place = "Survivor Camp", look = "townsperson" },
	{ id = "gus", name = "Gus", label = "Gus, the yard foreman", job = "Yard foreman", place = "Train Yard", look = "foreman" },
	{ id = "hugo", name = "Hugo", label = "Hugo, the waterworks keeper", job = "Waterworks keeper", place = "Water Works", look = "worker" },
	{ id = "danny", name = "Corporal Danny", label = "Corporal Danny, the pilot", job = "Chopper pilot", place = "Military Base", look = "soldier" },
	{ id = "roy", name = "Sergeant Roy", label = "Sergeant Roy", job = "Quartermaster", place = "Military Base", look = "soldier" },
	{ id = "cole", name = "Warden Cole", label = "Warden Cole, Blackrock Prison", job = "Prison warden", place = "Blackrock Prison", look = "guard" },
	{ id = "gordon", name = "Gordon", label = "Gordon, the bank manager", job = "Bank manager", place = "First Zombie Bank", look = "banker" },
	{ id = "jesse", name = "Jesse", label = "Jesse, the ranch hand", job = "Ranch hand", place = "Silver Spur Ranch", look = "rancher" },
	{ id = "emma", name = "Emma", label = "Emma, the riding instructor", job = "Riding instructor", place = "Riverside Riding School", look = "rider" },
	{ id = "percy", name = "Percy", label = "Percy, the city clerk", job = "City clerk", place = "City Hall", look = "clerk" },
	{ id = "hank", name = "Hank", label = "Hank, the depot worker", job = "Depot worker", place = "Harbor Fuel Depot", look = "worker" },
	{ id = "hal", name = "Doc Hal", label = "Doc Hal, the camp medic", job = "Camp medic", place = "Survivor Camp", look = "doctor" },
	{ id = "duke", name = "Firefighter Duke", label = "Firefighter Duke", job = "Firefighter", place = "Fire Station 9", look = "firefighter" },
	{ id = "petra", name = "Petra", label = "Petra, the pharmacist", job = "Pharmacist", place = "Corner Pharmacy", look = "shopkeeper" },
	{ id = "otto", name = "Otto", label = "Otto, the old postman", job = "Postman", place = "Dead End Dispatch", look = "worker" },
	{ id = "rosie", name = "Rosie", label = "Rosie, the baker", job = "Baker", place = "Rosie's Bakery", look = "cook" },
	{ id = "kim", name = "Nurse Kim", label = "Nurse Kim", job = "Nurse", place = "City Clinic", look = "nurse" },
	{ id = "molly", name = "Molly", label = "Molly, at the counter", job = "Ice cream seller", place = "Frosty's Ice Cream", look = "icecream" },
	{ id = "tony", name = "Tony", label = "Tony, the pump attendant", job = "Pump attendant", place = "Gas Station", look = "attendant" },
	{ id = "amy", name = "Miss Amy", label = "Miss Amy, the teacher", job = "Teacher", place = "Sunny Hill School", look = "teacher" },
} :: { Person }

local byId: { [string]: Person } = {}
for _, person in Cast.People do
	byId[person.id] = person
end

-- The person with this id, or nil.
function Cast.find(id: string): Person?
	return byId[id]
end

-- The person whose name (the part of a label before its comma) is `name`, or nil: tests use it to catch a story
-- character written by hand with another role.
function Cast.named(name: string): Person?
	for _, person in Cast.People do
		if person.name == name then
			return person
		end
	end
	return nil
end

return Cast
