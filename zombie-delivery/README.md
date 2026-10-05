# Zombie Delivery

A second Roblox game in this repository (Merge Blades lives in the root). **You run a delivery company** in a world
gone wrong: take a job, carry the cargo to your vehicle with your own hands (or lead the horses on a rope), drive it
across the map while bandits shoot at you from roadblocks and zombies chase you, carry it to the receiver under fire,
get paid, earn XP and climb the driver ranks, and buy better cars, guns, car guns, items and upgrades. The clock runs
from day into night (darker, more zombies, better pay), civilian traffic and people on foot fill the streets, and
friends join your crew: they ride along in your passenger seats or follow in their own car, shoot and share the pay.
With the money you make you buy **real estate** (version 2.6): homes to spawn at, garages for more cars, and offices in
the city's towers from which **your own delivery company** of hired couriers earns for you, even while you are away.
Version 2.7 brings the game's **own sound and music**: soft, minimal, made for it (see **Sound and music**).
Version 3.0 is about **missions and co-op**: **100 story missions** in 10 campaigns, each told by a client with a
briefing and a debrief, rated 1 – 3 stars and spiced with **twists** (hold out at the drop, no shooting, a horde at
every stop …); the co-op ones pay more and get harder with every crew mate. **Crews now stay together** from one
mission to the next, a crew board finds you mates, and 15 new places (an airfield, a prison, a lighthouse, a power
plant …) wait at the end of new roads (see **Missions**). Version 3.0.1 made the **night readable** (a brighter moon,
the town glowing back, your own soft light). Version 3.1 gives every place and every mission **a reason to keep
playing**: **42 challenges**, **30 lost packages** hidden at the places, and rewards nobody can buy: every campaign
gives a **title** and an **exclusive gun or paint**, every package found the Phantom paint, and every challenge done
**Dead End**, the gun nobody else has (see **Challenges, secrets and rewards**).

Everything is built in code (the world, the cars, the enemies, the interface), so the game needs no assets: open an
empty place and sync. The icon set and the logo are optional (see **Graphics**).

## Running

```bash
node tools/rojo-sync.js zombie-delivery
```

(from the repository root). In Studio open a **new Baseplate place** (not the Merge Blades one), then
**Plugins → Rojo → Connect** and **Play**. Instead of the command you can double-click
`zombie-delivery/spust-zombie-delivery.cmd` (Windows) or `zombie-delivery/spust-zombie-delivery.command` (Mac):
git pull + the sync.

A Play test in Studio without API access cannot save, so it starts with `Config.StudioStartMoney` ($25,000) to try the
shops. A published game starts with `Config.StartMoney` and saves to the DataStore `Config.DataStoreName`.

## How to play

| Input | PC | Touch |
|---|---|---|
| Drive / walk | WASD / arrows | thumbstick |
| Sprint (on foot; the body speeds up and slows down with weight, leans into the run, and out of a sprint the gun comes up slower) | hold Shift | – |
| Aim (GTA style: the mouse is locked, the camera follows it, crosshair in the middle) | move the mouse | – |
| Aim (on foot you walk slowly with both arms up, the gun fires once it is up; in a car the camera moves in for a drive-by) | hold right mouse | – |
| Shoot (on foot: the gun in your hand; driver: the car gun on the roof if the car has one, else a one-handed gun out of the window; passenger: a one-handed gun out of the window) | left mouse | FIRE |
| Shoot the nearest enemy (auto-aim) | hold F | hold FIRE |
| Switch gun | hold Q: the weapon wheel (point at a gun, let go); tap Q: the next gun; or click the weapon bar | the weapon bar |
| Items (repair, medkit, nitro, molotov, mine) | 1 – 5 | the hotbar |
| Free the mouse (click the interface) | hold Alt (any window frees it too) | – |
| Jobs / map / backpack | J / M / B | the buttons |
| Missions (the campaigns, START, the stars; 3.1: the CHALLENGES, SECRETS and REWARDS tabs) | U | MISSIONS button |
| Crew panel (invite / accept / leave / kick, the crew board) | K | CREW button |
| Leaderboard | L | TOP button |
| Get in your car / ride in a friend's car | E / R | the prompt |
| Get out | Space | jump button |
| Pick up / Load / Take out / Hand over / Lead a horse (on foot, at a stop) | hold E | the prompt |
| Put down / Let go (to shoot; anybody of the crew can pick it up again) | G (gamepad B) | the prompt |
| Open a lost package (3.1) | hold E | the prompt |
| Real estate list (every property, buy, sell, set your home, GPS) | H | ESTATE button |
| View a property's listing (at its FOR SALE sign) | E | the prompt |
| Run your company (at your office's computer: hire, upgrades, collect the safe) | E | the prompt |
| Ride a tower elevator (step on a pad under a floor sign) | walk onto it | walk onto it |
| Admin panel (testing tools; only for admins: a Studio Play test, the place's owner, `Config.Admin.UserIds`) | P | the ADMIN button |

While you carry something (or lead a horse) you cannot shoot, sprint or drive, and you walk slower.

**Guns and cars.** You buy guns for your hands (Lead & Co.); you start with the pistol. From a car seat (driver or
passenger) only a **one-handed** gun fires, out of the side window: the **pistol, the revolver and the SMG**. The
two-handed ones (shotgun, rifle, carbine, minigun, grenade launcher) do not fire from a car (a short hint says so; the
weapon bar greys them out and tags the others WINDOW). **Car guns** are something else: bolted on the roof at
**Wrench Garage** (CAR GUNS tab), one per car, and the driver fires them (the turret turns to the target, the weapon bar
shows it). A car starts with none. They fit the Old Van, the Pickup, the Muscle Car, the Armored Truck and the Monster
Truck, not the work vehicles (bus, ice cream, moving, livestock, fuel truck). A driver without a car gun shoots a
one-handed gun out of the window (a drive-by); passengers always use their own gun.

1. The **start screen** flies over the city; **PLAY** starts the game and brings your car. With a **home** (see
   **Real estate and your company**) you spawn there after PLAY and after every death, and your car waits in front of
   the home's garage (walk to it and press E); without one the car is placed next to you and you sit in it.
2. Without a home you start at the **depot** in the middle of Downtown. Around it is the **safe zone** (green line) with the shops:
   **Dead End Motors** (cars, walk among the showroom cars), **Lead & Co.** (guns), **Wrench Garage** (upgrades, paint
   jobs, car guns, free repairs inside), **Last Stop Supplies** (items). Walk in and use the counter.
3. **JOBS** (or the job board at the depot): one special job and one delivery of every danger level.
   * Every delivery has stops: **pick up** at the blue circle, **deliver** at the yellow one. Park in the circle, **get
     out** and handle the cargo yourself: **Pick up** (E) a piece from the giver's pile, carry it to the back of the
     vehicle and **Load** it (E); the loaded pieces ride visibly in the vehicle. At the drop **Take out** (E at the
     back), carry it to the receiver and **Hand over** (E). Horses are **led on a rope** into the truck's stalls and
     out again. Kids **walk** to the school bus and get on by themselves, and off again at the school: just park and
     wait. The ice cream route is the only stop where you hold still in the circle while the kids buy.
   * While you are on foot at a stop the enemies come **on foot** too: put the piece down (G), shoot, pick it up again.
     Every piece to handle adds time to the clock.
   * ★ near and quiet · ★★ bandit roadblocks · ★★★ across the city, gunners and brutes · ★★★★ INSANE: the far places.
   * Modifiers on the far jobs: RUSH (less time), FRAGILE (hits cost double), HEAVY LOAD (slower car), WANTED
     (bigger, faster zombie waves), each pays more.
   * Some special jobs come and go on the board (`Config.Jobs.BoardSpecials`):
     * **Winter Run**: through the tunnel and over the **frozen lake** (the car slides on the ice) to the Ski Lodge.
     * **Cash Transport** (★★★★, level 5): sacks of cash from the **First Zombie Bank** in the army's Armored Truck to
       the Military Base vault. Every bandit in town wants it: twice as many roadblocks and chases.
     * **Pizza Rush** (★, level 1): one hot pizza from Luigi's to a hungry customer, 3 minutes on the clock.
   * A locked job shows **🔒 LEVEL N** instead of ACCEPT: the danger levels need a driver level (★ 1, ★★ 2, ★★★ 4,
     ★★★★ 6), and so do some special jobs (see **Driver levels**).
   * **Work for the people who run things** (the WORK HERE boards, ★ yellow on the map). They lend you their vehicle
     for the job; after enough jobs the vehicle is yours, and some of them also give you a **gun** (not sold anywhere):
     * **Sunny Hill School** (Suburbs): School Run, pick up kids at 3 homes → **School Bus** after 3 jobs
     * **Military Base** (north, through the tunnel): Army Supply, ammo from the docks → **Army Carbine** after 2 jobs,
       **Armored Truck** after 4
     * **Frosty's Ice Cream** (Harbor): Ice Cream Route, sell at 4 stops → **Ice Cream Truck** after 3
     * **Big Move Movers** (Downtown): Moving Day, furniture to a new home → **Moving Truck** after 3
     * **Old Farm** (west): Farm Run, food to two city markets → **Monster Truck** after 3
     * **Silver Spur Ranch** (off the West Highway): Horse Transport, two horses to the Riverside Riding School →
       **Ranch Revolver** after 2 jobs, **Livestock Truck** after 4
     * **Gas Station** (North Highway): Fuel Run, fuel barrels from the Harbor Fuel Depot → **Fuel Truck** after 3
     * **City Clinic** (Downtown, south-west of the depot; level 3): Ambulance Run, pick up a patient at their home in
       the clinic's ambulance and rush them to the clinic within 2½ minutes (the patient shuffles in and out by
       themselves, slowly) → **Ambulance** after 3
4. **Enemies**:
   * **Without a job** (free roam) only **zombies** are around: 6 – 10 walkers and runners (rarely a brute) shamble
     around you, 150 – 320 studs away, wherever you are out of the safe zone. They wander slowly until they notice
     you: on foot within ~55 studs, a car further the faster (the louder) it goes, a **gunshot** within ~120 studs,
     or a hit. Then they hunt you, and give up a few seconds after they lose you. Kills pay as always.
   * **Bandits only come during a job.** Bandits, gunners and the soldiers at the military base never go after a
     player without a job: the camps at the far places and the base stand guard. Take a job and they wake up.
   * **During a job** the zombies come in **WAVES** (a toast says "WAVE 3 · 7 zombies", the job panel shows the
     wave): the first one ~15 s after you accept, around you and ahead of the car, then bigger and bigger ones.
     ★ Easy: 2 → 5 zombies every ~40 s · ★★ Risky: 3 → 7 every ~32 s · ★★★ Deadly: 4 → 10 every ~26 s, brutes and
     soldiers · ★★★★ INSANE: 6 → 14 every ~20 s (a cap of alive ones per tier; WANTED: bigger and faster). The waves
     wait while you are in the safe zone or handle the cargo on foot at a stop (then a few come on foot instead,
     bandits among them). When the job ends its zombies just roam on.
   * **Bandit pickups** come after you on the road (from ★★ up), ram you and shoot from the bed; destroy them with
     guns, ramming, mines or molotovs ($75). Now and then a **civilian car** behind you is no civilian: it turns into
     a bandit pickup right where it was (during a ★★+ job, out of the safe zone, one at a time). **Bandits** and **gunners** on foot set up roadblocks ahead of you and
     shoot your car. Bandits next to your car **steal whole pieces** of your cargo.
   * Zombies: run them over or shoot them (a **headshot kills** at once, a brute takes 4×); they grab a slow car and
     bite it until you shoot them off. The crosshair is a **dot** that turns white over an enemy; an **X** shows only
     on a headshot.
   A wrecked car (or dying) does **not** end the job: a wreck ruins 25 % of the pieces in it (at least one), press
   CAR for a new car (the company vehicle on a special job) and keep going while the time lasts.

   **CAR calls your car**: it does not appear out of thin air. A **chauffeur** (black suit, cap) drives it to you
   along the roads from out of sight, 110 – 200 studs away (or out of your nearest garage within 400 studs), brakes for
   traffic, overtakes what blocks the lane, parks at your curb, gets out, walks off and fades; then it is yours (walk
   to it, E). The HUD shows "Your car is on the way · N s" with a bar, a marker over the car and on the maps, and the
   CAR button counts down. If it is not there within **15 s** (`Config.CarCall.ArriveWithin`) the car is placed next
   to you and you sit in it, the old way. If the car is wrecked on the way the HUD says so (press CAR again); a respawn
   cancels the call and brings the car the instant way. Sitting in your own car, CAR still resets it on the spot
   (to unflip or unstick it).
5. The pay: the job's pay × the share of the pieces delivered × cargo condition (50 – 100 %), + 25 % for finishing
   in the first half of the time, + $3 per enemy killed; an ordinary delivery also pays $15 per piece. Finished **at
   night** it pays up to × 1.4 on top (the **Night bonus** line of the result; the job board tags the offers
   🌙 NIGHT × 1.4 while it is night). The job fails only if nothing arrived. Every kill also pays on the spot, and so
   do the **supply crates** (? on the map). Every job also gives **XP** (see **Driver levels**), a failed one a
   quarter of it.
6. **Crews**: press **K** (or **CREW**) and invite a player (up to `Config.Crew.MaxMembers` = 3 members; they get
   30 s to answer on the invitation card). You can invite with or without a job. Members work on your job: they
   carry the cargo, their kills count, the purple GPS leads them to your next stop and the panel shows your job and
   its clock. Friends who press R at your car to ride along are paid the same way while they stay with the job (in
   your car, or on foot within `Config.Crew.RiderRange` = 250 studs of you); at most `MaxMembers` are paid, the
   members first. Every member and rider gets half of the pay and the same XP, you get +15 % per member: nobody
   loses money (the panel shows the split of the base pay). Since 3.0 the crew **stays together** when a job ends:
   it breaks up only when you break it up, or for a member who leaves (LEAVE), is taken out (KICK), takes a job of
   their own or quits; a piece a former member was carrying drops where they stand. The **crew board** (LOOKING FOR
   CREW in the crew window) lists the players who want a crew, for one mission or any, with INVITE; your own toggle
   puts you on it, and FIND CREW on a co-op mission does that and opens the window.

**Driver levels.** Every delivery gives XP: stars × 60 + 10 per piece delivered + 4 per kill, × 1.25 at night; a
failed job gives 25 % (once something was done). 15 levels, each with a rank name (Rookie Courier, Courier, Runner,
Road Rat, Road Warrior, Veteran Driver, Wasteland Trucker at 8, Convoy Captain at 10, Dead End Legend at 12, King of
the Road at 15). The levels unlock things, which show **🔒 LEVEL N** until then:

* the danger levels on the job board: ★★ at level 2, ★★★ at 4, ★★★★ at 6
* special jobs: Ambulance Run 3, Cash Transport 5 (Pizza Rush from 1)
* cars: Pickup 2, Muscle Car 4
* guns: SMG 2, Shotgun 3, Hunting Rifle 5, Minigun 8, Grenade Launcher 10
* car guns: Roof Machine Gun 3, Roof Minigun 7, Roof Grenade Launcher 9

The HUD shows your level, rank and XP bar; the result window the XP of the job (and LEVEL UP). The player list shows
**Level** (leaderstats). **L** (or **TOP**) opens the server's leaderboard: everybody's level, rank, deliveries and
money earned, best first, the ones out on a job tagged.

**Day and night.** The clock runs: a whole day takes 16 minutes (`Config.DayNight`, the server starts at 09:00).
Night is from 18:15 to 06:15, lined up with the Roblox sun: the sky goes dark (the look fades in over dusk and out
over dawn), the **street lamps**, the lit windows and every car's **headlights** come on. At night the jobs pay
× 1.4, the waves are × 1.5 bigger and × 1.6 as many zombies roam (smoothly in between at dusk and dawn). Since
3.0.1 the night is dark but **readable** (`client/Weather.luau`): a brighter moon and night ambient with less haze; in
town the streets **glow back** (a warm haze and more light near the districts); you carry **your own soft light** (on
your client only), so a zombie is never hidden in the black; and the street lamps light a wider, brighter pool.

## Missions

Press **U** (or **MISSIONS**) anywhere: the window lists the **10 campaigns** of **10 missions** each
(`shared/Missions.luau`), with the total stars (X / 300) on top and ALL / CO-OP tabs. Every campaign has a client,
a story, a colour and the driver level it opens at; its missions open **one after another** (finish one, any rating,
and the next is open; some need a higher level of their own). Click a mission for its card: the briefing in the
client's words, the twists, the cargo, the vehicle, the danger level and the pay, and **START**. The mission starts
right where you are (the pick-up is near you, or at its fixed place); a member of somebody's crew sees "your crew
leader picks the mission" instead (the leader's START takes the crew along). A NIGHT ONLY mission starts only after
dark.

| Campaign | Client | Level | Campaign reward |
|---|---|---|---|
| 📦 First Shift | Marge, the dispatcher | 1 | $2,500 |
| 🏥 Code Red | Dr. Novak, the City Clinic | 2 | $4,000 |
| 🛒 Empty Shelves | Mr. Patel, FreshMart | 3 | $5,500 |
| 🚒 Smoke and Sirens | Chief Ramirez, Fire Station 9 | 4 | $7,000 |
| 🪖 Iron Supply | Captain Reyes, the Military Base | 5 | $9,000 |
| ⚡ Lights Out | Engineer Volkov, the Power Plant | 6 | $11,000 |
| 🐴 Wild West End | Walt, the rancher | 7 | $13,000 |
| 🧪 Patient Zero | Dr. Ito, the Biotech Lab | 9 | $16,000 |
| 💰 Dirty Money | Vinnie, the fixer | 11 | $20,000 |
| 🚌 Last Convoy | Mayor Grant, City Hall | 13 | $30,000 |

* **Stars** (`Missions.rate`): done = ★; the cargo still at 75 % or more = ★★; and 30 % or more of the clock left =
  ★★★. Your best rating per mission is saved.
* **Rewards** (server/Missions.luau): the job's own pay as always (× the twists' pay), plus the **first clear's
  reward** ($300 – $10,000, once) with × 1.5 the job's XP (`FirstClearXp`), **$150 for every new star**
  (`StarBonus`), and the **campaign reward** once all ten are done. A card celebrates it: the stars fly in, the
  client's debrief, the rewards and NEXT (it waits until the delivery result is closed).
* **Twists** (`Config.Missions.Twists`, each pays more):

  | Twist | What happens | Pay |
  |---|---|---|
  | 🛡 HOLD OUT | at the last drop hold the area (on foot within 45 studs of the receiver) while the dead come in waves; leaving pauses the countdown | × 1.3 |
  | 🏋 TWO-MAN LIFT | heavy pieces: alone you carry them slowly, with a crew mate within 10 studs at full speed | × 1.25 |
  | 🤫 NO SHOOTING | explosive cargo: every shot of yours, your crew's or a passenger's costs 6 % of the cargo; at 0 it goes BOOM | × 1.35 |
  | ☣ HOT ZONE | a horde waits at every stop | × 1.3 |
  | 🌙 NIGHT ONLY | starts only after dark | × 1.2 |
  | 🎯 SHOTGUN SEAT | kills from the passenger seats pay triple | × 1.1 |
  | 💎 SPOTLESS | below 60 % cargo the mission fails at once | × 1.4 |
  | 🏴 HUNTED | bandit cars and roadblocks come 2.5 times as often | × 1.35 |

* **Co-op** (46 of the missions, tagged CO-OP; they can still be played alone): for every crew mate besides you
  (members and riders, `MaxMembers` at most) the pay is × (1 + 0.25 per mate) for everybody and the enemies (waves,
  foot waves, hordes) × (1 + 0.35 per mate), recounted when the crew changes (a toast says so).
* **The crew gets the stars too** (`Config.Missions.CrewCredit`): the members and riders with you at the finish get
  the rating, the first clear and the campaign as if it were theirs, if the mission is open for them (its campaign,
  its level, the mission before it); otherwise only their share of the pay.
* During a mission a **banner** in the HUD's top stack shows "MISSION 3/10 · Name", the twists, the crew count and
  the HOLD OUT countdown; the crew members' strip shows it too.
* The leaderboard (L) has a **STARS** column (ties on the level go to the stars).

## Challenges, secrets and rewards

Version 3.1 (`shared/Challenges.luau`, `server/Challenges.luau`, `Config.Rewards`). Everything is saved, and every
reward is given **once** (the save marks it given).

**Campaign rewards.** Finishing all ten missions of a campaign still pays its money (see **Missions**), and now also
gives a **title** and an **exclusive gun or paint** (`Config.Rewards.Campaigns`). Campaigns finished before 3.1 give
theirs on the next join.

| Campaign | Exclusive reward | Title |
|---|---|---|
| 📦 First Shift | Dispatch Yellow paint (metal) | Dispatcher's Favourite |
| 🏥 Code Red | Medic Mint paint | Field Medic |
| 🛒 Empty Shelves | Fresh Lime paint | Grocery Hero |
| 🚒 Smoke and Sirens | Fire Engine paint (metal) | Smoke Eater |
| 🪖 Iron Supply | **Reyes' Carbine** (gun) | Quartermaster |
| ⚡ Lights Out | Volt Neon paint (neon) | Live Wire |
| 🐴 Wild West End | **Walt's Lever Rifle** (gun, a round hits 2 in a row) | Outlaw Tamer |
| 🧪 Patient Zero | Toxic Glow paint (neon) | Cure Runner |
| 💰 Dirty Money | **Vinnie's Golden Pistol** (gun, one-handed) | Made Man |
| 🚌 Last Convoy | Sunrise Chrome paint (foil) | Last Convoy Captain |

**The lost packages.** A worn cardboard box with tape, a faint glow and a "?" seen within 25 studs is hidden at every
one of the 29 places, plus one more up on the stadium stands: **30** in all (`Map.Secrets`, built by
`server/World.luau`). They are hidden but fair: behind a building or a stand, under a bench or a table, between parked
things, up on a platform you can climb; never in the water or inside a wall. Walk up and hold E (**Open**): **$300** each
(`Config.Rewards.SecretMoney`) and a popup "LOST PACKAGE 12/30". A package you found disappears **for you only**
(`client/Secrets.luau`); the ones you have not found bob, sway and sparkle a little when you come close. The server
checks that you stand next to the package, level with it. **All 30** give the **Phantom** paint (glass), the title
**Treasure Hunter** and **$25,000**. The places count too: the first visit to each (within 70 studs of its point)
shows "NEW PLACE DISCOVERED: Old Airfield (12/29)".

**The challenges.** 42 goals in six categories, from minutes to the long game; each pays **$200 – $20,000**, 11 also
give a title, and 4 are **hidden** (??? until done):

| Category | Challenges (goal · money · title) |
|---|---|
| ⚔️ Combat | First Blood (10 kills · $200), Sharpshooter (25 headshots · $500), The Bigger They Are (10 brutes · $800), Bandit Bounty (25 bandits on foot · $1,500), Demolition Crew (50 explosion kills · $1,500), Horde Breaker (500 kills · $2,000), Headhunter (250 headshots · $4,000 · Headhunter), Giant Slayer (100 brutes · $6,000 · Giant Slayer), The Undertaker (5,000 kills · $15,000 · The Undertaker) |
| 🚗 Driving | Sunday Driver (25,000 studs · $300), Speed Bump (run over 50 · $600), Highway Patrol (10 bandit cars · $2,000), Mounted Mayhem (100 car gun kills · $2,500), Long Haul (250,000 studs · $3,000), Road Warrior (1,000,000 studs · $12,000 · Road Warrior) |
| 🎯 Missions | On the Clock (5 missions · $500), Story Time (1 campaign · $1,000), Night Shift (15 at night · $2,000), Hold the Line (10 HOLD OUT won · $2,000), Wave Rider (100 waves · $2,000), Trusted Courier (25 missions · $2,500), Flawless (25 at 3 stars · $2,500), Star Collector (100 stars · $3,000), Top of the Ladder (level 15 · $10,000), Legendary Courier (all 100 missions · $15,000 · Legendary Courier), Saviour of the City (all 10 campaigns · $20,000), Three-Star General (all 300 stars · $20,000 · Three-Star General); hidden: Ghost Courier (a NO SHOOTING mission without a shot · $2,000 · The Ghost), Horse Whisperer (25 horses · $2,500 · Horse Whisperer), Against the Clock (10 timed missions · $3,000) |
| 🧭 Explorer | Sightseer (5 places · $300), Lost and Found (1 package · $300), Package Sniffer (10 packages · $2,500), Cartographer (all 29 places · $5,000 · Cartographer), Every Last Box (all 30 packages · $10,000) |
| 🤝 Co-op | Better Together (1 mission with a crew mate · $300), Riding Shotgun (50 kills from a passenger seat · $1,500), Crew Chief (25 missions with a crew mate · $4,000 · Crew Chief) |
| 💰 Wealth | First Paycheck (earn $10,000 · $300), Home Sweet Home (1 property · $1,000), Car Collector (5 cars · $2,000); hidden: Millionaire (earn $1,000,000 · $10,000 · Millionaire) |

How they count (`Challenges.Counters` in the save, the rest read from the profile): a **car gun kill** is a kill by
the roof gun, a **passenger seat kill** one by a passenger's gun out of the window (a mine or a fire is neither, and
a blast is an explosion kill); the distance is driven as the driver (a teleport does not count); the waves, HOLD OUT
wins, pieces, horses and passengers count for the job's owner and the crew **with them** (in the car or within
`Config.Crew.RiderRange`), and a mission's finish (co-op, night, 3 stars, timed, NO SHOOTING without a shot) for who
was there. The server checks them after every change (at most twice a second, everybody every 5 s) and pays at once.

**Dead End.** Finish **every** challenge and you get **Dead End** (`Config.Rewards.Challenges`): a black and purple
rifle with neon strips and a glow, purple tracers, 64 damage, and rounds that **go through 3 more** enemies (zombies
or bandit cars, each taking the full damage). Nobody can buy it; the shop shows it as "??? · a secret reward". It
comes with the title **The Last Courier** and **$50,000**.

**Titles.** Every title you earn (the challenges', the campaigns', Treasure Hunter, The Last Courier) is yours; pick
one to show in **REWARDS** (EQUIP, or none). It shows in gold over your head for everybody (within 80 studs) and next
to your name on the leaderboard (TOP). Your first title is shown at once.

**The new tabs** in the MISSIONS window (U):

* **CHALLENGES**: on top the Dead End card (a dark silhouette and "???" until it is yours, "Complete every challenge
  (X/42)"), then the challenges by category, each with its description, a progress bar, the money and the title, ✓
  when done; the hidden ones read ??? until then.
* **SECRETS**: found X/30 and the money so far, every place with ✓ for its package or its hint ("Visit <place>
  first" before you have been there), and the Phantom card.
* **REWARDS**: the ten campaign rewards (earned, or "finish <campaign>"; a click opens the campaign), your titles with
  EQUIP, and the exclusive guns and paints.
* The MISSIONS tab's campaign header shows the campaign's reward too ("Reward: Reyes' Carbine + title Quartermaster").
* **Popups** at the top centre, one at a time: a strip for a new place, a card for a package or a challenge (its money
  and title), and a BIG card with a glow and confetti for a campaign's, every package's and every challenge's
  reward. They wait while the DELIVERY result, the mission's celebration card or the MISSIONS window is up, so
  nothing covers them; a flood (many at once) merges into one card per kind. A click dismisses one.

## Real estate and your company

Press **H** (or **ESTATE**) for the list of every property (filters ALL / HOMES / GARAGES / OFFICES / OWNED): price,
driver level, car slots or couriers, who owns it on this server, GPS. Each property has a **FOR SALE** sign in front
(E opens its listing; the board shows OWNED and the owners' names once somebody on the server has it). You **buy at
the property** (within reach of its sign or on its lot; away from it the BUY button turns into GO THERE TO BUY and
sets the GPS) with the money you made, if your driver level is high enough. Every player owns their own copy: two
owners of the same mansion both use it. Everything you own is saved.

| Property | Kind | Where | Price | Level | Car slots / couriers |
|---|---|---|---|---|---|
| Hilltop Mansion | mansion | the top of **Sunset Hills** (north-east of Downtown, up the winding Sunset Drive) | $6,000,000 | 10 | 8 cars |
| Ocean View Mansion | mansion | on the sea cliffs north of the Harbor, up Cliff Road (a private pier) | $4,500,000 | 9 | 8 cars |
| Pinecrest Mansion | mansion | in the pines south of the West Highway, down Pine Lane | $3,000,000 | 8 | 6 cars |
| Lakeside Villa | villa | far north by the frozen lake, on the Lodge Road (a jetty onto the ice) | $1,500,000 | 7 | 4 cars |
| Sunset Villa | villa | in the west, at the end of Sunset Lane off the Radio Road | $1,000,000 | 6 | 4 cars |
| 12 Maple Street | house | a Suburbs lot | $400,000 | 4 | 2 cars |
| 7 Oak Lane | house | a Suburbs lot | $300,000 | 3 | 2 cars |
| Birch Cottage | house | the west edge of the Suburbs, at the end of Birch Lane | $200,000 | 2 | 2 cars |
| Elm Bungalow | house | a Suburbs lot | $150,000 | 1 | 1 car |
| Harbor Lockup | garage | the Harbor | $50,000 | 1 | 4 cars |
| Highway Garage | garage | on the North Highway | $80,000 | 2 | 4 cars |
| Downtown Parking | garage | Downtown, in the safe zone | $120,000 | 3 | 6 cars |
| Harbor Point Office | office | **Harbor Point** tower (the Harbor, by the docks), 7th floor | $500,000 | 5 | 3 couriers |
| Dispatch Tower, 8th floor | office | **Dispatch Tower** (Downtown, by the depot), 8th floor | $900,000 | 7 | 6 couriers |
| Dispatch Tower Penthouse | office | Dispatch Tower, the top (14th) floor | $2,500,000 | 11 | 12 couriers |

* **Homes** (mansions, villas, houses) are furnished, two storeys for the big ones. Your first home becomes **your
  home** at once; SET AS HOME picks another one, SPAWN AT THE DEPOT none. You spawn at your home after PLAY and after
  every death, and the car you get then waits in front of its garage.
* **Car slots**: you can own `Config.Estate.BaseCarSlots` = **2** cars without any property; every home and garage
  adds its garage's slots. Buying a car at Dead End Motors needs a free slot (the dealer tells you to look at ESTATE
  otherwise). Company vehicles earned by working do not count, and cars you already own are never taken away.
* **Selling** (SELL, click twice to confirm) pays back **60 %** of the price (`Config.Estate.SellBack`). The home you
  spawn at cannot be sold until you set another home or the depot.
* **Offices** are in the two towers: **Dispatch Tower** (14 floors, Downtown, next to the depot) and **Harbor Point**
  (12 floors, the Harbor). Each has a lobby with a receptionist and the office directory (FOR SALE signs of its
  offices), glass office floors and a roof terrace with a helipad. The floors are joined by **elevator pads**: step on
  the pad under a floor sign and you ride to that floor.

**Your delivery company.** Owning an office starts it; the office with the most courier seats runs it. Use the
**computer** on your office desk (E, "Run your company"; you must stand at it):

* **Couriers**: HIRE costs $25,000 each (`Config.Business.CourierCost`), up to the office's seats (3, 6 or 12); FIRE
  gives no refund. A courier earns **$120 per minute** while you are on the server. Couriers above the seats (after
  selling the bigger office) stay on the payroll but earn nothing (NO DESK).
* **Upgrades** (5 levels each, the price grows per level): Better vans (+15 % per level, from $60,000), Dispatch
  software (+10 %, from $40,000), Armed escorts (+12 %, from $80,000); all levels together make up to × 2.85.
* **The safe**: earnings go into the company safe (paid every 10 s online), not into your money. It holds at most
  **$500,000** (`SafeCap`); a full safe stops filling. **COLLECT** at the office computer moves it into your money.
* **While you are away** the couriers earn **40 %** (`OfflineShare`) for at most **8 hours** (`OfflineHours`), into the
  safe. After PLAY a card says what the company made while you were away, with a GPS button to the office.
* The window shows the safe counting up, the earnings per minute, the seats, the upgrades and the couriers "on the
  road" with a dispatch radio feed. Those runs are for show; the money is worked out on the server.

## The world

Downtown (the depot and the shops), the river with **Rust Bridge** and **Old Bridge**, the **Harbor** (warehouses,
containers, the docks on the sea, the **Harbor Fuel Depot** south of the warehouses), the **Suburbs** and, down
**Riding School Lane**, the **Riverside Riding School** by the river, the **North Highway** past the **Gas Station** (an
employer now) through the **Mount Rot tunnel** to the snowy north: the **Military Base** and, over the frozen lake, the
**Ski Lodge**; the **West Highway** to the **Radio Station** and the **Old Farm**, with the **Ranch Road** off it to
**Silver Spur Ranch**. Downtown also has the **First Zombie Bank** (just north of the safe zone, on 6th Ave: the Cash
Transport loads at its steps) and the **City Clinic** (south-west of the depot, the emergency canopy on 4th Ave).

New in 3.0, the 15 mission places, all on the map's list with GPS: in Downtown's blocks **City Hall** (north of the
depot), **Precinct 13** (north-west), **Fire Station 9** (east), the **Corner Pharmacy** (south) and the **FreshMart**
supermarket (west, with its car park); the **Harbor Warehouse** in the Harbor; and on the edges of the map, each at
the end of its road: the **Old Airfield** (a runway, far south-west down the **Airfield Road** off the West Highway),
**Blackrock Prison** (walls and towers, far north-west down **Blackrock Road** off the Radio Road), the **Survivor
Camp** (tents and barricades on the Radio Road), the **Biotech Lab** (**Lab Road** off the North Highway), the **Train
Yard** (rails and wagons, up **Rail Yard Road** north of Downtown), **Lighthouse Point** (on the coast, **Lighthouse
Road** on from Cliff Road), the **Power Plant** (chimneys, south of the Harbor), the **Water Works** (by the river,
**Waterworks Road**) and the **Stadium Shelter** (tents on the field, south of the Suburbs).

New in 2.6: **Sunset Hills** north-east of Downtown (Sunset Drive winds up to the Hilltop Mansion, with a gate, lamps
and pines), the **Dispatch Tower** next to the depot and **Harbor Point** by the docks (offices, elevators, roof
helipads), **Ocean View** on the sea cliffs (Cliff Road), **Pinecrest** in the western pines (Pine Lane), the
**Lakeside Villa** by the frozen lake, the **Sunset Villa** off the Radio Road (Sunset Lane), **Birch Cottage** (Birch
Lane), the houses for sale on Suburbs lots and the three garages (Harbor Lockup, Highway Garage, Downtown Parking). All
of them are on the map's list with GPS.

**Traffic and pedestrians.** Civilian cars drive the roads around every player (on the right, slowing for the turns,
a random road at every junction; none in the winter, on the ice road or in the tunnel) and people walk the city's
sidewalks and cross the streets (fewer at night; they run from zombies). The cars stop for anything in their lane
(your car, a bandit, somebody on foot) and turn around after a while behind something that stays. Ram one at speed
and it is a smoking wreck, towed away later. They appear out of sight and vanish far away, with caps per player and
per server (`Config.Traffic`); during a job a bandit pickup can hide among them.

**The HUD** (laid out from the screen size, so nothing overlaps on a PC or a phone): money and the minimap bottom
left on a PC (top left on touch screens, clear of the thumbstick); the job panel, the crew strip, the mission banner,
the car call line, the level-up banner and the toasts in one stack at the top centre; the buttons **JOBS, MISSIONS,
MAP, BAG, CAR, TOP, CREW, ESTATE** on the right edge in 1, 2 or 4 columns (on a PC down at the weapon bar, clear of Roblox's player list; the
ADMIN button above them for admins); the weapon bar and the hotbar bottom right; the car panel and the hint at the
bottom centre. On touch FIRE sits above the jump button and the panels move left of it.

The minimap (bottom left; top left on touch screens) turns with the camera; it and the big map
(M) show it all. The big map lists every shop, employer and far place with what you can do there: click one to set
the **GPS**. The route there is drawn along the roads on both maps (yellow to the job's next stop, purple to the GPS
point), with an arrow over your car and a light beam. Big icons over the buildings show them in the world.

## Content

* **Cars**: at Dead End Motors the Old Van (free), the Pickup (level 2) and the Muscle Car (level 4); earned by
  working: School Bus, Armored Truck, Ice Cream Truck, Moving Truck, Monster Truck, Livestock Truck, Fuel Truck,
  Ambulance.
* **Guns** (Lead & Co.): Pistol (free), SMG, Shotgun, Hunting Rifle, Minigun, Grenade Launcher, each with its own model in
  your hand (`shared/GunModels.luau`, the bandits carry the same pistol and rifle): a muzzle flash and a recoil kick on
  every shot, the tracers start at the muzzle. A headshot kills. Earned by working, not sold: the **Ranch Revolver**
  (Silver Spur Ranch) and the **Army Carbine** (Military Base). One-handed (they also fire out of a car window):
  Pistol, Ranch Revolver, SMG, Vinnie's Golden Pistol.
* **Exclusive gear** (3.1, `exclusive` in `Config.Weapons` / `Config.Paints`, never sold; see **Challenges, secrets
  and rewards**): the guns **Reyes' Carbine** (an olive carbine with a scope), **Walt's Lever Rifle** (wood, a round
  hits 2 in a row), **Vinnie's Golden Pistol** and **Dead End** (a round hits 4 in a row), each with its own model; the paints
  Dispatch Yellow, Medic Mint, Fresh Lime, Fire Engine, Volt Neon, Toxic Glow, Sunrise Chrome and Phantom, some with
  a **finish** (metal, neon, foil, glass) on the body panels (`PaintDef.material`). The shops show them as dimmed
  **REWARD** cards with how to earn them ("REWARD · finish Iron Supply", "REWARD · find every lost package", "??? · a
  secret reward" for Dead End, its stats hidden); once yours they show normally with a ★ EXCLUSIVE badge and are
  equipped and painted like any other.
* **Car guns** (Wrench Garage, on the roof of the equipped car, one per car; a new one replaces the old one, no
  refund): Roof Machine Gun (a slim barrel with an ammo box), Roof Minigun (a rotary barrel cluster), Roof Grenade
  Launcher (a fat tube). The Gun Damage and Fire Rate upgrades work for them too.
* **Upgrades** (Wrench Garage, 5 levels each): Engine, Handling, Armor, Ram Plow, Gun Damage, Fire Rate; paint jobs;
  car guns.
* **Items** (Last Stop Supplies): Repair Kit, Medkit, Nitro, Molotov, Landmine.
* **Enemies**: Walker, Runner, Brute (zombies, around you all the time, in waves during a job); Bandit, Gunner,
  Soldier (people: only during a job).
* **People**: the employers, givers, receivers and kids are R15 NPCs that talk, turn to you and walk; the ranch's
  **horses** graze, walk on a rope and ride in the livestock truck's stalls; your **chauffeur** brings your car.
* **Real estate** (`Config.Estate`): 3 mansions, 2 villas, 4 houses, 3 garages, 3 offices. **Your company**
  (`Config.Business`): couriers, 3 upgrades, the safe.
* **Missions** (`shared/Missions.luau`, 3.0): 10 campaigns × 10 missions, 8 twists, 46 co-op missions, 15 new places;
  new cargo (water, generators, batteries, TNT, documents, electronics, weapons, paintings, mail, tyres, plants) and
  survivors who walk aboard by themselves.
* **Challenges, secrets, rewards** (3.1): 42 challenges (`shared/Challenges.luau`), 30 lost packages (`Map.Secrets`),
  10 campaign rewards, the Phantom and Dead End rewards, 11 + 12 titles (`Config.Rewards`).

All numbers are in `src/shared/Config.luau`, the world layout in `src/shared/Map.luau`, the formulas in
`src/shared/Economy.luau`.

## Graphics

The art is in `zombie-delivery/art/`: white silhouette icons for the guns (`weapons/`), the cargo and the items
(`cargo/`) and the map markers (`map/`), the logo (`logo/zombie_delivery_logo.png`) and the start menu's background
(`ui/menu_background.png`); the SVG sources sit next to the PNGs. The game shows them once their Roblox asset ids are
filled in; until then it shows the emoji and the text wordmark it always did.

1. In Studio: **View → Asset Manager → Bulk Import**, pick the PNGs (not the SVGs) and upload them.
2. Right-click each uploaded image → **Copy Asset ID**.
3. Paste it into `src/shared/Icons.luau` (`Icons.Ids`, the one place for every id) as `"rbxassetid://<number>"`, under
   the name of the file without `.png` (`art/cargo/item_medkit.png` → `item_medkit`), and sync.

The interface tints the white icons (`ImageColor3`); `Ui.icon` (client) draws an icon or its emoji fallback, the
landmark tags over the buildings (server) use the same ids, and `client/Theme.luau` takes the logo and the menu
background from there too. The car guns have no icon (they keep their emoji).

## Sound and music

Every sound is synthesized for the game by `art/audio/make_audio.py` (numpy + ffmpeg, nothing borrowed): soft
gunshots per gun type, hit / headshot / kill ticks, explosions, cargo pickup / put down / load, cash, job done / failed,
level up, the wave alarm, UI clicks, notices, the chauffeur's horn, the elevator ding, two zombie groans and a seamless
engine loop; and four calm music loops: **menu**, **day**, **night** and **tension** (on a job when a zombie wave
arrives or zombies crowd you). Roblox limits audio uploads, so it is all in **two files**: `art/audio/sfx.ogg` (every
effect one after another) and `art/audio/music.ogg` (the loops); `src/shared/SoundSheet.luau` (written by the script)
says where each one sits, and `client/Sounds.luau` plays just that region (`PlaybackRegion` / `LoopRegion`).

1. In Studio: **View → Asset Manager → Bulk Import**, pick `art/audio/sfx.ogg` and `art/audio/music.ogg`.
2. Copy each one's asset id into `SoundSheet.SfxId` / `SoundSheet.MusicId` as `"rbxassetid://<number>"` and sync.

Until then the game is silent (one note in the Output). The **SOUND** button / **N** key cycles: everything on →
music off → all off; volumes, the crossfade and when the tense loop plays are in `Config.Audio`. To change a sound,
edit the script and run `python3 art/audio/make_audio.py` from `zombie-delivery/` (it rewrites both files and
SoundSheet; upload them again).

## Code

```
src/shared/   Config (all numbers), Map (world layout, roads, addresses, cargo spots), Roads (the road graph and the
              GPS routes), Economy (prices, stats, pay, what fires from a car seat), Net (remotes), Joints (Motor6D or
              AnimationConstraint), GunModels (the guns in the hands), Icons (the asset ids of the icon set and the logo),
              Levels (XP, levels, rank names), TrafficLanes (the traffic's lanes, turns and sidewalks), SoundSheet
              (where each sound and music loop sits in the two audio assets), Missions (3.0: the 10 campaigns and 100
              missions, unlocking, the rating, the stars, the twists' pay), Challenges (3.1: the 42 challenges, the
              counters, value / progress / doneCount / allTitles)
src/server/   Main (wiring, PLAY: the one Play listener), World (builds the world, also the homes, garages, towers,
              elevators, FOR SALE signs and office computers), PlayerData (saves, leaderstats; the save also holds the
              properties, the home and the business), Vehicles (cars, seats, cargo slots, the roof turret of a car gun,
              the instant spawns and the home garage spot), Zombies (zombies and bandits, roadblocks, the roamers,
              who goes after whom), BanditCars (the chasing pickups, driven by the server), Gun (shots, server checked: the hand gun, the car gun or out of
              the window; 3.1: piercing rounds), Jobs (job board, stops, special jobs, crews, the zombie waves), Cargo (the cargo you carry, lead or board at a
              stop, the pieces in the vehicle), Npcs (the R15 people: givers, receivers, kids, employers), Animals (the
              horses: build, walk, lead rope, stalls), Items (consumables, supply crates), Shops (counters, showroom,
              purchases), Admin (the admin commands, checked on the server), DayNight (the clock, the Night attribute,
              the night lights), Traffic (civilian cars and pedestrians, bandits among them), Crew (invitations, crews,
              the crew state), Ranking (the leaderboard rows), Estate (buying, selling, the home, car slots, the home
              respawn, the owners on the signs), CarCall (the chauffeur who drives your car to you), Business (your
              company: couriers, upgrades, the safe, online and offline earnings, the office computer), Missions (3.0: the
              MISSIONS window's state, START checked, the rewards, stars and crew credit when one is done), Challenges
              (3.1: counts the stats from the other modules' hooks, the distance and the places visited, checks and
              pays the challenges, the lost packages' prompts, the campaign / secrets / Dead End rewards, the title over
              the head, the Challenges remote)
src/client/   Main, Menu (start screen), Hud (interface, the on-foot guide), MapView (minimap, big map, GPS routes),
              CameraRig (GTA-style aim camera), ArmPose (the arms come up to aim or carry, seen by everybody),
              Drive (car controller, ice), Shooting (aim, crosshair, tracers, hit numbers), CarVisuals (tyres,
              prompts, name tags), ZombieAnimator, AnimalAnimator (the horses' legs, neck and tail), AdminPanel (P),
              Weather (the day and night look; 3.0.1: the readable night, the town glow, your own light), Ui, Leaderboard (L), CrewPanel (K, the invitation card, the member's
              job strip and GPS), TrafficAnimator (smooths the traffic cars and spins their wheels), EstateUi (H, the
              real estate list and listings), BusinessUi (the company window at the office computer, the welcome-back
              card), Sounds (the music and every sound effect, N / SOUND), WeaponWheel (hold Q), MissionsUi (3.0: the MISSIONS window (U),
              the mission banner in the top stack, the celebration card; 3.1: the CHALLENGES, SECRETS and REWARDS
              tabs and the unlock popups), Secrets (3.1: hides the lost packages you found, animates the others nearby)
tests/        run_tests.py runs every *_test.luau: logic (Economy, Map, the zombie waves and roamers), cargo (pieces
              and pay), roads (the GPS), cargun (car guns, one-handed guns, which cars mount a gun, what fires from a
              seat), icons (every picture has its id slot, every gun, item, cargo and landmark has an icon), levels
              (XP and ranks), jobs25 (the 2.5 jobs and places), traffic (lanes, turns, spawn spots, sidewalks); the
              2.6 real estate checks are in logic (every property placed, no overlaps, the towers and offices, the
              roads to every property, the landmarks) and so are the 3.0 places (every one placed, on its road, with
              its cargo spot); audio (every sound has its region, every gun its shot); missions (the 10 campaigns and
              100 missions valid against Config and Map, the design rules, unlocked, rate, stars, twistPay); 3.1:
              challenges (the list, the must-have goals, the titles, the hidden ones, the helpers on a fake profile),
              gear (piercing rounds, the paint finishes, every exclusive item a reward) and the lost packages in logic
              (one per place, near it, in bounds, dry, off the roads)
```

**Driving** is arcade, not wheel physics: invisible frictionless wheel colliders and two constraints on the chassis
(`LinearVelocity` in the ground plane, `AngularVelocity` for turning and staying upright). The driver's client owns the
car and sets both from the VehicleSeat (`client/Drive.luau`); on ice the velocity follows the nose only slowly. While
a chauffeur drives it (the model's `Chauffeured` attribute) the **server** owns the car and sets both constraints
(`server/CarCall.luau`), and its Drive / Ride prompts wait in a `ParkedPrompts` folder; at the hand-over the prompts
come back and the owner's client gets the car.

**Joints**: since Roblox's Avatar Joint Upgrade (default in every place since 2026) an R15 character's joints are
`AnimationConstraint`s, not `Motor6D`s (same names, but C0 / C1 are read-only). Everything that poses or ragdolls a
body goes through `shared/Joints.luau` (both kinds) and writes `Transform` in `RunService.PreSimulation`, after the
animations: the aiming arms (`client/ArmPose.luau`), the bandits' raised guns, the ragdolls. The horses are not
characters: they have their own `Motor6D`s, swung on the clients by `client/AnimalAnimator.luau`.

**Enemies** are R15 bodies made from a HumanoidDescription (blocky custom rigs as the fallback) animated by their
Animator, the blocky ones on the clients by joint transforms. Cars and enemies do not collide physically (collision groups): running one over and grabbing the car are
computed on the server from the car's box (`server/Zombies.luau`).

## Tests

```bash
python3 zombie-delivery/tests/run_tests.py [path to the luau binary]
```

Runs every `tests/*_test.luau` (logic with the 2.6 real estate, the 3.0 places and the 3.1 lost packages, cargo,
roads, cargun, icons, levels, jobs25, traffic, audio, missions, challenges, gear) and compiles every module. Needs the standalone Luau CLI
(https://github.com/luau-lang/luau/releases).

**Testing in Studio**: the admin panel (P, or the ADMIN button top right) unlocks everything, gives money, spawns
cars, puts any car gun on your car (or none), guns and enemies, teleports to every place, starts any job, sets the
driver level (the LV buttons, LEVEL -1 / +1; UNLOCK also sets the top level), sets the time of day (dusk, night,
dawn … through `DayNight.setClock`), heals, finishes the current stop and switches god mode. The **Estate, company**
tab gives every property (or one), takes them all, sets the home (or the depot), teleports to any property and
fills, adds $50,000 to or empties the company safe (UNLOCK also gives every property and, without a home, the most
expensive mansion as the home). The **Missions** tab starts any of the 100 missions now (locks ignored; a running job
is cancelled, a NIGHT ONLY one turns the clock to night), sets every mission to 3 stars and every campaign done (no
money; UNLOCK does it too) or clears the progress (commands `missionStart`, `missionsAll`, `missionsReset`); 3.1:
it gives every campaign's exclusive reward and title too. The **Challenges, secrets** tab (3.1) marks every challenge
done with its money and title, every campaign's reward and Dead End (`challengesAll`), finds every lost package
(`secretsAll`: no money each, then the Phantom reward), starts over (`challengesReset`: the stats, packages, places,
titles and rewards cleared, the exclusive guns and paints taken back; the challenges your profile still reaches, such
as kills, level, missions, money earned, stay done without paying again, and the campaign rewards come back on the
next join) and gives and shows any title (`title <name>`, `none`: no title; a reward's title comes without its
reward, which is still given when earned). It
is there for a Studio Play test, for the owner of a user-owned place and for the user ids in `Config.Admin.UserIds`;
the server checks every command again.

## Ideas for later

Traffic lights at the junctions, a crew leaderboard, company vans driving past in traffic.
