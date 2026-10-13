--!strict
-- 7.0, the story of the moves: "The Last Move" (the owner's design, design/rework/NAVRH.md §1; told for the owner in
-- Czech in design/rework/PRIBEH.md). The city is evacuated district by district, Captain Maria's army builds the Wall
-- round what is left, people may cross with what fits in one vehicle, and Marge turns the courier company into ZDC
-- Moving & Evacuation: "We move your life. The rest they eat." The clients are the people of the missions (shared/
-- Cast.luau); the villains are Big Move Movers (Config.Employers "movers": Dana, the boss), movers turned thieves.
-- Pure data and helpers (no Roblox at the top level: tests/movestory_test.luau); the numbers are Config.MoveStory's.
--
--   MoveStory.Chapters        the story road in its unlock order: the prologue (Marge's house: its `contract` is
--                             Config.Moving.Contracts' "marge"), six chapters and the finale; 7.x farm move: chapter 1
--                             plays Walt's Farm ("walt"), the others `soon = true`. A chapter: id, number (0 … 7), title,
--                             its client (a Cast id, a
--                             partner's for two faces), place, icon, colour, requires (the chapters before it), hook
--                             (two or three sentences), blurb (the client's line on the contract card), keepsakes (the
--                             ★ sentimental things and their stories: FurnitureLooks ids where the furniture exists),
--                             briefing (3 – 5 lines from Marge and the client before START), dispatch (Marge's text
--                             at the start), debrief (Marge's text after the end, by outcome: it leads to the next
--                             chapter), thanks (the client's line on the result card, by outcome) and taunt (Big Move
--                             Movers on the radio: the briefing's last card).
--   MoveStory.Intro           Marge's cards the first time somebody opens the Moving contracts board (the evacuation,
--                             the Wall, the new name); seen once a save: the "intro" seen key (server/PlayerData.luau
--                             profile.story, the player attribute MoveStory)
--   7.x farm move, the chapters done (the same save flags: MoveStory.doneKey(id) = "done:<chapter id>", set by
--   server/Moving.luau for the crew that delivered a chapter's move, read only from a real save):
--     MoveStory.doneKey(id) / unlocked(chapter, seen) / blocker(chapter, seen) / lockText(chapter, seen)
--     MoveStory.status(chapter, seen?)   "play" | "locked" (a chapter before it not done yet; only with `seen`) | "soon"
--   MoveStory.Villain         Dana of Big Move Movers as a Cast-shaped person (a portrait like the world's NPC)
--   MoveStory.find(id) / forContract(id or name) / label(chapter) / status(chapter) / speaker(who) / roleOf(person)
--   MoveStory.outcome(how, stars)   the move's end (MovingRules phase: done | late | cancelled | failed) and its stars
--                             as great | ok | late | failed (Config.MoveStory.Great stars and more: great)
--   MoveStory.dispatchText(contract) / debriefText(contract, how, stars)   Marge's phone texts (server/Moving.luau's
--                             MoveStory hook sends them through the Tutorial remote's "message")
--   MoveStory.thanksLine(contract, how, stars)   the client's line for the result card (client/MoveStoryUi.luau)
--   MoveStory.isSeenKey(key) / cleanSeen(saved, rewards?) / encodeSeen(seen) / decodeSeen(text)   the seen flags in the
--                             save and on the player attribute (a sorted, comma-separated list of keys); 7.2 review:
--                             isCardKey(key), the keys a client may mark (CardKeys: "intro", never a chapter done)
--   The greeters (7.0: the people who welcome a crew; server/MoveGreeters.luau says these in speech bubbles, each at
--   most Config.MoveStory.Limits.Bubble characters):
--     a chapter's `greeter`   its client on the porch of the house: hello (2 – 3 lines when the crew comes), star (a ★
--                             thing carried out past them; 7.x farm move: `stars`, a line of its own for a ★ piece by its
--                             FurnitureLooks id, else `star`), horde (the horde comes), leave (the loaded truck drives off)
--     MoveStory.starLine(greeter, item)   the line for this ★ piece
--     MoveStory.Wall          the soldier at the Wall's checkpoint: welcome (a move's truck delivered at the drop-off)
--     MoveStory.Kiosk         Marge at the depot's Moving contracts kiosk: her lines, one each time (kioskLine)
--     MoveStory.greeterOf(contract) / kioskLine(n)

local Config = require(script.Parent.Config)
local Cast = require(script.Parent.Cast)

local MoveStory = {}

-- A line on a story card: who says it (a Cast id, or MoveStory.Villain.id) and what.
export type Line = { who: string, text: string }
-- A ★ thing the client cares about: the furniture's id (shared/FurnitureLooks.luau, or the id it will have), its name
-- in the story and why it matters.
export type Keepsake = { item: string, name: string, story: string }
export type Outcomes = { great: string, ok: string, late: string, failed: string }
-- 7.0 greeters: what a chapter's client says on the porch (server/MoveGreeters.luau).
export type Greeter = { hello: { string }, star: string, stars: { [string]: string }?, horde: string, leave: string }
export type Chapter = {
	id: string,
	number: number, -- 0: the prologue, 1 … 6, 7: the finale
	title: string,
	clientId: string, -- shared/Cast.luau (the portrait, the name)
	partnerId: string?, -- a second face (Rico, Doctor Hiro)
	client: string, -- the name on the cards ("Rosa & Rico")
	place: string,
	icon: string,
	color: { number }, -- RGB: the portrait's background, the tile's accent
	contract: string?, -- the Config.Moving.Contracts id it plays (nil: not built yet)
	soon: boolean?, -- not playable yet (🔒 SOON)
	requires: { string }, -- the chapters that open it (each an earlier one)
	hook: string,
	blurb: string,
	keepsakes: { Keepsake },
	briefing: { Line },
	taunt: string,
	dispatch: string,
	debrief: Outcomes,
	thanks: Outcomes,
	greeter: Greeter?, -- 7.0 greeters: the client on the porch (a playable chapter's)
}

MoveStory.Outcomes = { "great", "ok", "late", "failed" }
MoveStory.Sender = "Marge" -- who the phone texts are from (client/Phone.luau's MESSAGES)
MoveStory.Tagline = "We move your life. The rest they eat."
MoveStory.Company = "ZDC Moving & Evacuation"

-- Dana runs Big Move Movers (Config.Employers "movers"); her look is the world's ("mover": her NPC at their board).
MoveStory.Villain = {
	id = "dana",
	name = "Dana",
	label = "Dana, Big Move Movers",
	job = "Boss",
	place = "Big Move Movers",
	look = "mover",
	color = { 120, 40, 36 },
}

-- Seen once a save (server/PlayerData.luau profile.story): only these keys are kept (7.x farm move: and a chapter done,
-- "done:<chapter id>", added after the chapters below).
MoveStory.SeenKeys = { "intro" }
-- 7.2 review: the cards a client marks seen itself (the Tutorial remote's ("story", key): server/Tutorial.luau asks
-- isCardKey). A chapter done is never one: only server/Moving.luau marks it.
MoveStory.CardKeys = { "intro" }

-- Marge's intro: the first time the Moving contracts board opens.
MoveStory.Intro = {
	{ who = "marge", text = "Sit down, rookie. The army is evacuating the city, one district at a time. Captain Maria is building a Wall round what's left." },
	{ who = "maria", text = "Civilians cross with what fits in one vehicle. Whatever stays outside the Wall belongs to the dead. That is not a suggestion." },
	{ who = "marge", text = "Nobody needs parcels any more. Everybody needs a truck. So we're ZDC Moving & Evacuation now. New sign and everything." },
	{ who = "marge", text = "We move your life. The rest they eat. The first job's an easy one: my house. Don't make me regret the word 'easy'." },
} :: { Line }

-- ── The chapters, in their unlock order ─────────────────────────────────────

MoveStory.Chapters = {
	{
		id = "prologue",
		number = 0,
		title = "Everything Must Go",
		clientId = "marge",
		client = "Marge",
		place = "155 Willow Ln, the Suburbs",
		icon = "🏠",
		color = { 255, 200, 70 },
		contract = "marge",
		requires = {},
		hook = "The Wall closes over Willow Lane tonight, and Marge's family house is on the wrong side of it. Forty years of her life, one truck, twelve minutes. Your first move, and your boss is the client.",
		blurb = "Grandpa's clock goes first. Then Mum's records. Then whatever you can carry. Then me.",
		-- (Marge's House, seed 1955 of shared/HouseLayout.luau's plan: its ★ pieces are the clock, the record player
		-- and the rocking horse; the photo album is the fourth sentimental piece another seed may pick)
		keepsakes = {
			{ item = "grandfather_clock", name = "Grandpa's clock", story = "Marge's father built it the year she was born. It has never once been on time." },
			{ item = "record_player", name = "Mum's record player", story = "Her mother danced to it every Sunday. One record left. Nobody knows which." },
			{ item = "rocking_horse", name = "The rocking horse", story = "Marge rode it as a girl. It lost an ear in a 'stampede' she still won't explain." },
			{ item = "photo_album", name = "The family photos", story = "Forty years of birthdays in one box. Marge pretends she never looks." },
		},
		briefing = {
			{ who = "marge", text = "Welcome to your first move. The client is me, so no pressure. None at all." },
			{ who = "marge", text = "Drive the truck to 155 Willow Lane. Walk in, pick things up, carry them out, load them in the back. Like any move, only faster." },
			{ who = "marge", text = "The ★ things matter: Grandpa's clock, Mum's record player, my old rocking horse. Furniture I can buy again. Those I can't." },
			{ who = "marge", text = "Big things take two people, or one very slow person. Heavy goes in first, fragile goes on top. Like groceries." },
			{ who = "marge", text = "With three minutes left, the dead come for dinner. What's in the truck goes to the Wall. What isn't, they keep." },
		},
		taunt = "Nice little house, Marge. Shame if your rookie's truck got lighter on the way to the Wall.",
		dispatch = "Grandpa's clock is in the living room. Don't you dare drop it.",
		debrief = {
			great = "The clock is ticking behind the Wall. Wrong time, as always. Walt called: his ranch is next on Maria's map. Get some sleep.",
			ok = "Most of my life made it. The rest is a zombie's problem now. Walt called about his ranch. Practise on cows, they don't judge.",
			late = "The Wall shut on half my kitchen. I'll live. Probably. Next time watch the clock, rookie. The other clock.",
			failed = "So my house belongs to the dead now. Fine, they can pay the mortgage. Come back to the depot and we'll try again.",
		},
		thanks = {
			great = "Every ★ thing, not a scratch. I'm not crying, the clock is dusty. Thank you, rookie.",
			ok = "Most of my life made it out. That's more than most people get today. Thank you.",
			late = "Half my house is behind the Wall, half is somebody's dinner table. Better than nothing.",
			failed = "My whole life is out there with the dead. Go back. I'll make coffee. Strong.",
		},
		-- 7.0 greeters: Marge on her porch (server/MoveGreeters.luau)
		greeter = {
			hello = { "Oh thank heavens, ZDC!", "The door's open. Everything inside goes.", "And mind Grandpa's clock!" },
			star = "Careful with that!",
			horde = "They're coming! Hurry!",
			leave = "Thank you… see you behind the Wall.",
		},
	},
	{
		id = "ranch",
		number = 1,
		title = "Hold Your Horses",
		clientId = "walt",
		client = "Walt",
		place = "Walt's farm, the Old Farm",
		icon = "🐴",
		color = { 200, 150, 90 },
		contract = "walt", -- 7.x farm move: Walt's Farm (Config.Moving.Contracts), open once the prologue is done
		requires = { "prologue" },
		hook = "The Wall stops a mile short of Walt's farm, and Walt isn't leaving a single saddle behind. A farmhouse, a barn full of feed and a hay wagon too wide for any door but the barn's. Heavy, loud and down a dirt road.",
		blurb = "Fifty years on this land, partner. The land stays. Everything that breathes or bucks comes with me.",
		-- (Walt's Farm, seed 1921 of shared/Layouts/Farm.luau's plan: its ★ pieces are Thunder's saddle, the
		-- branding iron and Grandma's milk churn; the cowbells are the fourth sentimental piece another seed may pick)
		keepsakes = {
			{ item = "thunders_saddle", name = "Thunder's saddle", story = "Walt's old stallion won't take a rider without it. Or with it, some days." },
			{ item = "branding_iron", name = "The branding iron", story = "The Silver Spur's mark since 1921. Walt's grandpa forged it in the barn." },
			{ item = "grandmas_churn", name = "Grandma's milk churn", story = "Grandma churned butter in it every morning for sixty years. Walt still can't." },
			{ item = "cowbells", name = "The cowbells", story = "One bell for every cow Walt ever named. He named all of them." },
		},
		briefing = {
			{ who = "walt", text = "Howdy, partner. Maria's Wall stops a mile short of my fence. So the farm goes to the Wall instead." },
			{ who = "walt", text = "The ★ things ride with me: Thunder's saddle, the branding iron and Grandma's milk churn. The rest rides with you." },
			{ who = "marge", text = "Two ways in, rookie: house and barn. The hay wagon only fits through the barn doors, and it rides hitched behind your van." },
			{ who = "walt", text = "Rust Riders are sniffing round the barn, and an outfit in orange trucks calls itself 'movers'. Keep your eyes open." },
		},
		taunt = "Nice horses, cowboy. We take anything with legs and a price tag.",
		dispatch = "Thunder's saddle is in the stable, the iron in the workshop. The hay wagon goes out the barn doors and rides on your van's hitch.",
		debrief = {
			great = "Walt says the horses rode better than his last wife. I don't want to know. Ellie called: the clinic can't wait.",
			ok = "Most of the herd made it, the tractor didn't. Walt is holding a funeral for it. Ellie needs us next.",
			late = "The Wall shut on Walt's barn. He sat on the fence and watched it go. Then he gave me Ellie's number. For you.",
			failed = "We lost the ranch run. Walt is still out there arguing with a gate. Go back for him.",
		},
		thanks = {
			great = "Every horse, every saddle, not a hoof hurt. Soft hands and a hard head, partner.",
			ok = "Lost a few things, kept what counts. Thunder's eating hay behind a wall. That'll do.",
			late = "Half my barn's on the wrong side now. The cows are the zombies' problem.",
			failed = "Fifty years, gone with the dust. Don't you dare quit on me now, partner.",
		},
		-- 7.x farm move: Walt at his farmhouse's door (server/MoveGreeters.luau)
		greeter = {
			hello = { "Howdy, ZDC! About time.", "House and barn are open. Take it all.", "The wagon goes out the barn doors!" },
			star = "Easy with that, partner!",
			stars = {
				thunders_saddle = "Easy with Thunder's saddle!",
				branding_iron = "Mind Grandpa's iron, it still bites!",
				grandmas_churn = "Gentle! That's Grandma's churn!",
				cowbells = "Don't ring 'em, the cows still listen!",
			},
			horde = "Here they come! Saddle up!",
			leave = "Much obliged. See you behind the Wall.",
		},
	},
	{
		id = "clinic",
		number = 2,
		title = "Handle With Care",
		clientId = "ellie",
		client = "Doctor Ellie",
		place = "City Clinic",
		icon = "🏥",
		color = { 240, 80, 80 },
		soon = true,
		requires = { "ranch" },
		hook = "The City Clinic is the last hospital outside the Wall. Doctor Ellie needs every scanner, fridge and patient moved without a bump or a germ. Fragile everything, and the dead can smell the blood bank.",
		blurb = "Scanners, insulin, twelve patients and one coffee machine. If anything arrives broken, I know who to stitch.",
		keepsakes = {
			{ item = "xray_machine", name = "The old X-ray machine", story = "Older than Ellie, louder than a truck. Still the best one in the city." },
			{ item = "coffee_machine", name = "The coffee machine", story = "Ellie runs the clinic on it. It is fragile. Do not test that." },
			{ item = "plant", name = "Nurse Ada's plant", story = "It survived the outbreak, two fires and Rico. Don't let it die now." },
		},
		briefing = {
			{ who = "ellie", text = "Everything in this clinic is fragile, including me. I haven't slept since the Wall went up." },
			{ who = "ellie", text = "The fridges stay plugged in until the last second. Blood doesn't care about your timer." },
			{ who = "marge", text = "Ellie's patients walk out on their own. You take everything else. The scanner costs more than you do." },
			{ who = "ellie", text = "Gloves on, doors shut. If you hear coughing, check it's a patient before you shoot it." },
		},
		taunt = "Hospital gear sells for triple, Doc. Thanks for packing it so nicely for us.",
		dispatch = "Ellie says the X-ray machine is older than her and twice as moody. Lift with your legs. Slowly.",
		debrief = {
			great = "Ellie opened a clinic behind the Wall in an hour. She said 'good job'. I didn't know she knew the words. Raj called.",
			ok = "The clinic is open again, minus a few machines. Ellie pretends that's fine. Raj needs us at the Grand Hotel.",
			late = "Half the clinic is still out there with the dead. Ellie isn't talking to anyone. Raj called. Go, quietly.",
			failed = "The clinic run went bad. The patients are safe, the gear is not. We go again. Ellie is buying the coffee.",
		},
		thanks = {
			great = "Not one cracked screen. You'd make a decent surgeon. A terrible one, but decent.",
			ok = "Some broken glass and nobody bleeding. In this city, that's a good day.",
			late = "We lost the blood fridge. Do you know how hard it is to find blood that isn't walking?",
			failed = "My clinic is out there, and so are my machines. Bring me something. Anything.",
		},
	},
	{
		id = "hotel",
		number = 3,
		title = "Room Service",
		clientId = "raj",
		client = "Raj",
		place = "Grand Hotel",
		icon = "🏨",
		color = { 110, 200, 90 },
		soon = true,
		requires = { "clinic" },
		hook = "When FreshMart closed, Raj took his shelves and forty neighbours up to the Grand Hotel. Now the Wall is moving and the hotel isn't. Six floors, a dead lift and guests barricaded in rooms who won't open for anyone.",
		blurb = "Six floors, forty guests and a kitchen full of food. The lift is dead. So is the doorman. Bring your legs.",
		keepsakes = {
			{ item = "store_sign", name = "FreshMart's sign", story = "Thirty-two years over Raj's door. He carried it up here on his back." },
			{ item = "piano", name = "The hotel piano", story = "Raj can't play. He just likes knowing somebody could." },
			{ item = "ledger", name = "Raj's ledger", story = "Every debt on the street since 1993. He forgave them all last week." },
		},
		briefing = {
			{ who = "raj", text = "Welcome to the Grand Hotel! Check-in is closed, check-out is today, and nobody gets a refund." },
			{ who = "raj", text = "The lift needs power, the power is in the basement, and the basement has guests. Not the paying kind." },
			{ who = "raj", text = "Some people upstairs barricaded their doors. Knock twice and say 'Raj sent me', or they throw furniture." },
			{ who = "marge", text = "Six floors of stairs, rookie. Carry the light things down, lower the heavy ones, don't fall with either." },
		},
		taunt = "Six floors of loot and one tired rookie, Raj. We'll take the stairs. And everything on them.",
		dispatch = "The guests on floor six only open for the password. It's 'Raj sent me'. He's very proud of it.",
		debrief = {
			great = "Raj opened FreshMart behind the Wall. His first customers were his forty guests. Free bananas. The twins called.",
			ok = "Most of the guests and most of the food made it. Raj is rationing bananas. Rosa and Rico want a word.",
			late = "The Wall shut on floors five and six. Raj is counting heads. Don't ask him the number. Rosa called.",
			failed = "The hotel run fell apart. The guests are still upstairs, and so is Raj. Go back up.",
		},
		thanks = {
			great = "Every guest, every crate, every banana. Five stars! My hotel never had five stars.",
			ok = "We lost some shelves, we kept the people. People don't fit on shelves anyway.",
			late = "Floor six is still up there with the dead. I'll never give out that password again.",
			failed = "My guests are waiting by the windows. Please don't make them wait for nothing.",
		},
	},
	{
		id = "villa",
		number = 4,
		title = "Hot Property",
		clientId = "rosa",
		partnerId = "rico",
		client = "Rosa & Rico",
		place = "Vinnie's villa",
		icon = "🖼️",
		color = { 236, 92, 60 },
		soon = true,
		requires = { "hotel" },
		hook = "Vinnie sailed off on his yacht and left his villa to Rosa and Rico, alarm codes not included. Paintings, a safe nobody lifts alone and a gallery of things that may be stolen. Big Move Movers want it first.",
		blurb = "Rosa: The paintings, the safe, the statue. Rico: And the hot tub? Rosa: Not the hot tub.",
		keepsakes = {
			{ item = "portrait", name = "Vinnie's mother's portrait", story = "The only painting in the villa he really paid for. He says." },
			{ item = "safe", name = "The safe", story = "Nobody has the code. Rico says he can open it. Nobody lets him." },
			{ item = "jukebox", name = "The jukebox", story = "The twins' first job together. They moved it twice. It still plays." },
		},
		briefing = {
			{ who = "rosa", text = "Vinnie's yacht left at dawn, his villa didn't. He wants the paintings, the safe and his mother's portrait at the Wall." },
			{ who = "rico", text = "The alarm still works. The guards don't. Well, they're zombies, so technically they still work here." },
			{ who = "rosa", text = "Two of us carry the safe, one holds the door, one watches the gate. Big Move Movers have circled all week." },
			{ who = "marge", text = "Rookie, if anything in that villa is stolen, we didn't see it. We just move it." },
		},
		taunt = "That villa's ours, twins. Everything in it was stolen once. We're keeping up the tradition.",
		dispatch = "The safe needs two people and Rico needs one idea less. The alarm code is on a napkin. Somewhere.",
		debrief = {
			great = "Vinnie sent a postcard from his yacht. It says 'grazie', on very expensive paper. Ivan called. He sounds scared.",
			ok = "Most of the paintings made it, and Vinnie's mother is safe. So is his opinion of us. Ivan called.",
			late = "The Wall shut on Vinnie's gallery. Big Move Movers are hanging his paintings in their office. Ivan needs us.",
			failed = "Dana's crew got the villa. Rosa is planning revenge, Rico is planning snacks. Go back in.",
		},
		thanks = {
			great = "Rosa: Every frame, the safe, the jukebox. Rico: Vinnie will cry. Rosa: Vinnie will pay.",
			ok = "Rosa: We lost a painting. Rico: It was ugly anyway. Rosa: It was a Monet. Rico: An ugly Monet.",
			late = "Rosa: Dana's crew has the villa now. Rico: I hope they like the hot tub. It's full of zombies.",
			failed = "Rosa: Big Move took everything. Rico: Everything? Rosa: The hot tub too. Rico: Monsters.",
		},
	},
	{
		id = "lab",
		number = 5,
		title = "The Zero Files",
		clientId = "ivan",
		partnerId = "hiro",
		client = "Ivan & Doctor Hiro",
		place = "Power Plant and Biotech Lab",
		icon = "🧪",
		color = { 160, 110, 255 },
		soon = true,
		requires = { "villa" },
		hook = "Engineer Ivan must shut the Power Plant down before the Wall closes, and Doctor Hiro's lab moves with it. Turbine parts, freezers, research. Then Hiro's Patient Zero files turn up, and the outbreak's story changes.",
		blurb = "Ivan: The turbine core, the freezers, my tools. Hiro: And the files. Especially the files. Please don't read them.",
		keepsakes = {
			{ item = "turbine_core", name = "Walrus, the turbine core", story = "It powered the city for thirty years. It still hums when Ivan talks to it." },
			{ item = "freezer", name = "The cure samples", story = "Patient Zero's blood, frozen. The only reason a cure exists." },
			{ item = "file_box", name = "The Zero files", story = "Day one, written down. Hiro hid them for a reason." },
		},
		briefing = {
			{ who = "ivan", text = "When I shut the plant down, the lights go out from here to the Wall. So we move fast, and we move Walrus first." },
			{ who = "hiro", text = "The freezers keep the cure samples alive. Unplug them last, carry them gently and never, ever open them." },
			{ who = "hiro", text = "There is also a box of files in my office. Patient Zero. Please don't read them. Please bring them." },
			{ who = "marge", text = "Rookie, a scientist begging you not to read something is the best reason I know to read it." },
		},
		taunt = "Leave the paperwork, Hiro. Some stories belong in a box. Ours, for example.",
		dispatch = "Ivan says Walrus weighs a ton and hums when it's happy. Hiro says the box of files is 'just paperwork'. He's lying.",
		debrief = {
			great = "I read Hiro's files. On day one a Big Move truck dropped a crate from his lab. Their driver was Patient Zero. Ruth called.",
			ok = "The files are safe, and so is the truth: the outbreak started in a Big Move truck, and Dana knew. Ruth needs us.",
			late = "The Wall shut on the plant, but the files made it. Dana's crew dropped the first crate. Now we know why they steal.",
			failed = "We lost the lab run, and Dana's people were in Hiro's office before us. They want those files burned. Go back.",
		},
		thanks = {
			great = "Ivan: Walrus sleeps behind the Wall. Hiro: The samples are cold, the files safe. You read them, didn't you?",
			ok = "Ivan: Some parts lost, the heart of the plant kept. Hiro: And the cure is alive. That is what matters.",
			late = "Ivan: The lights went out before the Wall shut. Hiro: Half my freezers are warm. Half the cure is gone.",
			failed = "Hiro: The files are out there with them. Ivan: Then we go back. Engineers don't leave parts behind.",
		},
	},
	{
		id = "museum",
		number = 6,
		title = "Heavy History",
		clientId = "ruth",
		client = "Mayor Ruth",
		place = "City Museum",
		icon = "🦖",
		color = { 235, 235, 240 },
		soon = true,
		requires = { "lab" },
		hook = "Mayor Ruth won't leave the city's memory outside the Wall. The museum has a bronze founder, a dinosaur skeleton and a hall of paintings, and the job runs at night. The heaviest move yet, and Big Move Movers know the way in.",
		blurb = "The founder's statue, the dinosaur, the city's charter. The city is lost. Its history doesn't have to be.",
		keepsakes = {
			{ item = "statue", name = "The founder's statue", story = "Two tons of bronze. The first mayor, and Ruth's great-great-grandfather." },
			{ item = "dinosaur", name = "Rex", story = "Every kid in the city has a picture with him. Every single one." },
			{ item = "charter", name = "The city charter", story = "Signed in 1871 by people who thought this city would last forever." },
		},
		briefing = {
			{ who = "ruth", text = "The museum holds everything this city ever was. When the Wall closes, all of it belongs to the dead." },
			{ who = "ruth", text = "We go at night, when the streets are quietest. Quiet is relative. Bring lights." },
			{ who = "marge", text = "The statue needs a crane, the dinosaur ten people, and the charter one person who doesn't sneeze." },
			{ who = "ruth", text = "Big Move Movers sell museum pieces to anyone with a boat. Tonight they don't get a single bone." },
		},
		taunt = "Dinosaur bones, Mayor. Boat buyers pay by the pound. Thanks for picking the heavy ones.",
		dispatch = "Ruth says Rex comes apart in nineteen pieces. Count them. Then count them again. Then hurry.",
		debrief = {
			great = "Rex stands behind the Wall, and kids are taking pictures with him again. Maria says the Wall closes for good at dawn.",
			ok = "The statue and most of Rex made it. Ruth found a tail bone in her coat. Maria called: the Wall closes at dawn.",
			late = "The Wall shut on half the museum. Ruth carried the charter out herself. Maria says dawn is the end. Come home.",
			failed = "Dana's trucks were at the museum before us. History lost. Maria says the Wall closes at dawn. Last chance.",
		},
		thanks = {
			great = "Every bone, every frame, the founder himself. You saved the city's memory. It will remember you.",
			ok = "We lost some history tonight, but we kept the parts people love. That's what history is for.",
			late = "Half the city's past is out there now. The other half is safe. I'll write it all down.",
			failed = "The museum is theirs now. We still have the people. Let's make sure we keep them.",
		},
	},
	{
		id = "finale",
		number = 7,
		title = "Last One Out",
		clientId = "marge",
		client = "ZDC, all of us",
		place = "The ZDC depot",
		icon = "🚚",
		color = { 240, 132, 44 },
		soon = true,
		requires = { "prologue", "ranch", "clinic", "hotel", "villa", "lab", "museum" },
		hook = "Maria's Wall closes at dawn, and the ZDC depot is on the wrong side of it. Every truck, every trophy, every friend you moved waits in the yard. Big Move Movers are coming for the files, and for you.",
		blurb = "The last move is our own: the trucks, the trophies, the coffee machine. And the people. Always the people.",
		keepsakes = {
			{ item = "dispatch_desk", name = "Marge's desk", story = "The dispatch desk since day one. It moves with her, or she doesn't move." },
			{ item = "trophy_shelf", name = "The trophy shelf", story = "Every keepsake you saved: a saddle, a jukebox, one of Rex's teeth." },
			{ item = "company_sign", name = "The ZDC sign", story = "Painted over twice: Dead End Dispatch, then ZDC Moving. One more coat to go." },
		},
		briefing = {
			{ who = "maria", text = "The Wall closes at dawn, civilian. When the gate shuts, it doesn't open again. For anyone." },
			{ who = "marge", text = "Everyone we ever moved is waiting behind it. Our turn now: the depot, the trucks, the sign." },
			{ who = "marge", text = "Dana's crew wants Hiro's files gone and our trucks for themselves. They're coming tonight. All of them." },
			{ who = "marge", text = "So we do what we do. We pack, we lift, we load, we drive. Last one out turns off the lights, rookie." },
		},
		taunt = "Lights out, Marge. Your files, your trucks, your Wall. We're moving in.",
		dispatch = "The last move. My desk goes first, the coffee machine second, you third. Don't make me choose the rest.",
		debrief = {
			great = "The gate is shut and we're all on the right side of it. Behind the Wall the sign is up: ZDC. Some things don't move.",
			ok = "We made it in, most of us and most of it. The sign is crooked. Leave it. It's ours.",
			late = "The gate shut on the yard. We got the people out. Trucks can be replaced. You can't. Get some sleep.",
			failed = "The yard fell and Dana drove off with our trucks. But we're alive, and the Wall still has a gate. Again.",
		},
		thanks = {
			great = "Every truck, every trophy, every friend. Welcome home, rookie. You moved a whole city.",
			ok = "We left some things behind. We didn't leave anyone. That's the job.",
			late = "The gate shut behind us. The trucks are outside with the dead, we're inside. I'll take it.",
			failed = "They took the yard. They didn't take us. Get up. We still have a truck somewhere.",
		},
	},
} :: { Chapter }

-- ── Helpers ─────────────────────────────────────────────────────────────────

local byId: { [string]: Chapter } = {}
for _, chapter in MoveStory.Chapters do
	byId[chapter.id] = chapter
end

-- 7.x farm move: a chapter done is a seen key of the save ("done:prologue"), in the story road's order.
function MoveStory.doneKey(id: string): string
	return `done:{id}`
end
for _, chapter in MoveStory.Chapters do
	table.insert(MoveStory.SeenKeys, MoveStory.doneKey(chapter.id))
end

function MoveStory.find(id: any): Chapter?
	return if type(id) == "string" then byId[id] else nil
end

-- The chapter a Config.Moving contract plays: by its id ("marge") or its name ("Marge's House": the result card has
-- only the name), nil for any other.
function MoveStory.forContract(key: any): Chapter?
	if type(key) ~= "string" or key == "" then
		return nil
	end
	local id = key
	for _, contract in (Config :: any).Moving.Contracts do
		if contract.name == key then
			id = contract.id
		end
	end
	for _, chapter in MoveStory.Chapters do
		if chapter.contract == id then
			return chapter
		end
	end
	return nil
end

-- "PROLOGUE", "CHAPTER 3", "FINALE".
function MoveStory.label(chapter: Chapter): string
	if chapter.number == 0 then
		return "PROLOGUE"
	elseif chapter.number == #MoveStory.Chapters - 1 then
		return "FINALE"
	end
	return `CHAPTER {chapter.number}`
end

-- 7.x farm move: every chapter before it done (`seen`: the save's flags, MoveStory.decodeSeen / cleanSeen)?
function MoveStory.unlocked(chapter: Chapter, seen: { [string]: boolean }?): boolean
	return MoveStory.blocker(chapter, seen) == nil
end

-- The first chapter before it that is not done yet (nil: none, it is open).
function MoveStory.blocker(chapter: Chapter, seen: { [string]: boolean }?): Chapter?
	for _, id in chapter.requires do
		if not (seen and seen[MoveStory.doneKey(id)] == true) then
			return byId[id]
		end
	end
	return nil
end

-- What a locked chapter's card says: "🔒 Finish the PROLOGUE, Everything Must Go, first." (nil: it is open).
function MoveStory.lockText(chapter: Chapter, seen: { [string]: boolean }?): string?
	local first = MoveStory.blocker(chapter, seen)
	return if first then `🔒 Finish the {MoveStory.label(first)}, {first.title}, first.` else nil
end

-- "play": its contract is on the board (with `seen`: and every chapter before it is done); "locked": a chapter before it
-- is not done yet (only with `seen`); "soon": not built yet.
function MoveStory.status(chapter: Chapter, seen: { [string]: boolean }?): string
	if chapter.soon == true or chapter.contract == nil then
		return "soon"
	elseif seen and not MoveStory.unlocked(chapter, seen) then
		return "locked"
	end
	return "play"
end

-- Who says a line: a Cast person or the villain (nil for an unknown id).
function MoveStory.speaker(who: string): Cast.Person?
	if who == MoveStory.Villain.id then
		local v = MoveStory.Villain
		return { id = v.id, name = v.name, label = v.label, job = v.job, place = v.place, look = v.look }
	end
	return Cast.find(who)
end

-- The small line under a speaker's name: "Rancher · Silver Spur Ranch" (Marge's place is the company's new name).
function MoveStory.roleOf(person: Cast.Person): string
	local place = if person.id == "marge" then MoveStory.Company else person.place
	return `{person.job} · {place}`
end

-- The move's end as a story outcome: done with Great stars or more: great, done: ok, late (the clock ran out): late,
-- called off or lost: failed.
function MoveStory.outcome(how: string?, stars: number?): string
	if how == "done" then
		return if (tonumber(stars) or 0) >= (Config :: any).MoveStory.Great then "great" else "ok"
	elseif how == "late" then
		return "late"
	end
	return "failed"
end

-- Marge's text when a move of this contract starts (nil: no story for it).
function MoveStory.dispatchText(contract: any): string?
	local chapter = MoveStory.forContract(contract)
	return if chapter then chapter.dispatch else nil
end

-- Marge's text after it ended (how: MovingRules' phase; stars: the rating).
function MoveStory.debriefText(contract: any, how: string?, stars: number?): string?
	local chapter = MoveStory.forContract(contract)
	return if chapter then (chapter.debrief :: any)[MoveStory.outcome(how, stars)] else nil
end

-- The client's line for the result card.
function MoveStory.thanksLine(contract: any, how: string?, stars: number?): string?
	local chapter = MoveStory.forContract(contract)
	return if chapter then (chapter.thanks :: any)[MoveStory.outcome(how, stars)] else nil
end

-- ── The greeters (7.0: server/MoveGreeters.luau) ──────────────────────────────────────────────────────────────────

-- The soldier at the Wall's checkpoint, when a move's truck is delivered at the drop-off.
MoveStory.Wall = {
	welcome = "Welcome to the safe zone. Unload over there.",
}

-- Marge at the depot's Moving contracts kiosk, to a player who walks up to it (one line each time, in turn).
MoveStory.Kiosk = {
	"New contract, sweetie?",
	"Back for more, sweetie? Pick a house.",
	"Trucks are fuelled. New contract, sweetie?",
} :: { string }

-- The client's lines on the porch of this contract's house (nil: nobody greets there).
function MoveStory.greeterOf(contract: any): Greeter?
	local chapter = MoveStory.forContract(contract)
	return if chapter then chapter.greeter else nil
end

-- 7.x farm move: the client's line for a ★ piece carried past (its own, else the greeter's `star`).
function MoveStory.starLine(greeter: Greeter, item: string?): string
	local own = greeter.stars
	return if own and item and own[item] then own[item] else greeter.star
end

-- Marge's kiosk line number `n` (1, 2, … round the list).
function MoveStory.kioskLine(n: number): string
	local count = #MoveStory.Kiosk
	return MoveStory.Kiosk[((math.max(1, math.floor(n)) - 1) % count) + 1]
end

-- ── The seen flags (the save, the player attribute MoveStory) ───────────────

function MoveStory.isSeenKey(key: any): boolean
	return type(key) == "string" and table.find(MoveStory.SeenKeys, key) ~= nil
end

-- 7.2 review: may a client mark this key (a card it was shown: CardKeys)?
function MoveStory.isCardKey(key: any): boolean
	return type(key) == "string" and table.find(MoveStory.CardKeys, key) ~= nil
end

-- A saved table checked: only known keys set to true (anything else: an empty table). 7.2 review: `rewards` (the save's
-- rewards) adds the chapters done kept there: an older server keeps only "intro" of the story but every short key of
-- the rewards (server/PlayerData.luau writes them to both).
function MoveStory.cleanSeen(saved: any, rewards: any?): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	for _, key in MoveStory.SeenKeys do
		local done = string.sub(key, 1, 5) == "done:"
		if (type(saved) == "table" and saved[key] == true) or (done and type(rewards) == "table" and rewards[key] == true) then
			seen[key] = true
		end
	end
	return seen
end

-- "intro" (the keys set, in SeenKeys' order, comma-separated); "" when none.
function MoveStory.encodeSeen(seen: { [string]: boolean }?): string
	local keys: { string } = {}
	for _, key in MoveStory.SeenKeys do
		if seen and seen[key] == true then
			table.insert(keys, key)
		end
	end
	return table.concat(keys, ",")
end

function MoveStory.decodeSeen(text: any): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	if type(text) == "string" then
		for key in string.gmatch(text, "[^,]+") do
			if MoveStory.isSeenKey(key) then
				seen[key] = true
			end
		end
	end
	return seen
end

return MoveStory
