# Zombie Delivery

The active Roblox game in this repository (Merge Blades is preserved in `../archive/merge-blades`). **You run a delivery company** in a world
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
**Dead End**, the gun nobody else has (see **Challenges, secrets and rewards**). Version 3.2 is about **progression**:
a real level curve where the cars, guns, campaigns and real estate open one after another and the mansions, the
offices and your company are the **endgame**; every campaign now needs the one before it; a new **DUO campaign** of 10
missions only for two (pair lifts, twin switches); every cargo vehicle gets a **back that opens** (doors, a tailgate,
a trunk lid, a ramp) and the loading goes through it; and the rest of the **HUD** gets the glass look of the 3.1
right side (see **Driver levels and the progression**, **Missions**, **The DUO campaign**, **Loading through the back**).
Version 3.3 brings **five more vans** to buy between the Old Van and the endgame (the Courier Van, the High-Roof Van,
the Box Truck, the Armored Van and the Rally Van) and **upgrades you can see**: the car upgrades now belong to one
car and show on it (a bull bar, armor plates and window grilles, a hood scoop and twin pipes) (see **The vans and the
upgrades you can see**).
Version 3.4 makes the cars **real and earned**: every car has a **cargo capacity** (the Old Van holds 4 pieces, the
High-Roof Van and the Box Truck 6) and a new **Cargo Rack** upgrade adds a slot per level on a roof rack you can see;
a job or a mission with more pieces than your car holds waits until your car is big enough. You keep your first van
and upgrade it (the first levels are cheap). Damage stays with a car until a **repair shop** fixes it (Wrench Garage
and the new Rust Bridge Repairs: drive into a bay, get out, wait up to a minute, pay a small fee), and every car
beyond the starting van needs a **garage** slot: the first garage comes at level 2, and you **switch cars only at your
garages** (see **Cars, cargo, garages and the repair shop**).
Version 3.5 is about **building your van up instead of saving for the next one**: the Cargo Rack is gone, every car has
**stages** you buy at Wrench Garage, and every stage **changes how the car looks**. The Old Van starts as a **Rusty
Van** (2 slots, rust and primer patches), becomes a **Work Van** (3: clean paint, a side ladder, shelves behind the
doors) and a **Cargo Van** (4: a high roof with a roof rack, a light bar, mud flaps), and 4 is where a van ends: more
needs a bigger vehicle. The other cars are not "the next van" but have a **role** (the fast Courier Van, the tougher
High-Roof Van, the Box Truck as the only way to 6 – 8 pieces, the Armored Van as the car-gun platform …), each with one
or two small stages of its own. **Dead End Motors** sells from a **catalog** at its sales counter: no more lot of
every car outside, three display cars stand inside (see **Stages and the cars' roles**).
Version 3.6, **Postage & Trouble**, is a new interface built from **Codex's concept** (`design/ui-concept/`): light
cream paper and powder lavender with dark plum ink instead of the dark glass. The job is a tilted **delivery ticket**
with its timer on a perforated stub, the car a round **speed dial** with its condition and cargo pips, the items
tilted **tags** that lift under the mouse, the job board a new **Dispatch board** of die-cut tickets that says why a
job is locked and what to do about it, and every window the same lavender window (see **The HUD**).
Version 3.7 is the **first day on the job**:
- **Marge, the dispatcher at the depot,** greets a new player, gives the first job and explains each step until it is
  delivered (`server/Tutorial.luau`, `client/TutorialUi.luau`; SKIP is always there).
- **The job board fills itself:** every `Config.Jobs.RefreshSeconds` (4.0.2: 2 min) with a countdown instead of a refresh
  button. It is sorted from ★ (level 1, on top) to the best jobs at the bottom.
- **A faster walk (14) and sprint (28),** but the sprint has a **breath** (about 6 s) shown by a thin bar
  (`client/Stamina.luau`, `Config.Movement`).
- **The map is discovered:** the map and the minimap stay fogged until you have been near, a **NEW LOCATION
  DISCOVERED** banner names each place you find, and the floating markers over the buildings are gone, so the
  buildings' signs and the map tell you what is where (`shared/Explore.luau`, `server/Explore.luau`,
  `client/Discovery.luau`). The job's destination and route always show through the fog.
- **Cars have doors:** **E** shows only at a door. The driver's door is on the left, passengers get in on the right,
  and the door swings open and shut.
- **Light pieces** (pizza, parcels, mail, medicine …) can be carried **two at a time**. With one in your hands you can
  still open the back; with two your hands are full: put one down with **G**, or let a crew mate open it
  (`Config.Cargo.LightLooks`).
Version 4.0.4: dying on a job or a mission brings you back **near where you fell** (the nearest sidewalk), not home;
nobody shoots **through walls** any more (your shots start at the muzzle and stop at a wall in front of it; the
bandits need a clear line from their head and must have you in sight `Config.Horde.SpotTime` (0.7 s) before they fire;
behind a wall they move round for a line instead of shooting into it).
Version 3.8 is **the contract UI**: Codex's approved direction (`design/ui-contract/`) replaces the 3.6 paper look
everywhere: compact white type, charcoal, fine lines and red accents, a quiet HUD around the world (see **The HUD**).
Version 3.9 puts **the gun away**: you no longer walk around with it in your hand.
- **B holsters or draws the gun.** Holstered, the gun is gone from your hand for everybody and the arms hang normally.
  You start holstered after every spawn. Aiming (right mouse) or shooting (left mouse, F, FIRE) while holstered draws
  it on that first press without firing; picking a gun (Q, the weapon wheel) draws it too. In a car nothing changes.
- **V fights hand to hand:** holstered a **punch** (weak, quick), with the gun out a **strike** with it (a
  pistol-whip, a rifle butt: harder, slower). It hits the nearest zombie or bandit right in front of you and pushes it
  back; everybody sees the arm swing (`Config.Melee`, `shared/Melee.luau`, `server/CloseCombat.luau`,
  `client/Holster.luau`).
- **The bag moved to I.**
Version 3.10 is **getting in and out of the car**: no more teleporting into the seat.
- **E at a door:** you step to the handle, your hand takes it, the door swings open, you slide in through it (ducking
  a little) and it shuts behind you, about half a second in all. Passengers do the same at their own door (the bus
  through its folding door); a seat with no door (a pickup's bed, a roof, a jump seat) is a quick climb in an arc.
  Everybody sees it. The server keeps the seat for you meanwhile and seats you at the end (if the car drives off, you
  die or the car is wrecked, you just stand at the door).
- **E in a seat gets you out** (Space still does, gamepad X): the door opens at once, you slide out at your side and
  it shuts behind you. While you sit in a car the prompts around you stay quiet so E means "out", except a 🅿 GARAGE
  post (E opens it, Space gets you out). Out of a fast car you are put out at the door at once.
- Tuning in `Config.Cargo` (BoardSeconds, AlightSeconds, DoorShutSeconds …), the timing and curves in
  `shared/Boarding.luau`, the move in `client/CarBoarding.luau`.
Version 4.2 makes **phones and tablets** play everything a keyboard does (and a gamepad the main things):
- **SPRINT** (a toggle left of Roblox's jump button) runs on the same breath as Shift; it turns itself off when the
  breath runs dry. The breath bar sits over the contextual action.
- The hand button left of FIRE is **PUNCH / STRIKE** on foot, **EXIT** in a car seat (the jump button still gets you
  out too) and **PUT DOWN / LET GO / SET DOWN** while you carry, lead a horse or push the trolley or the pallet jack
  (what G does; the server checks it). DRAW / HOLSTER sits over it. Every button is 44 px or more.
- A tap on the **weapon line** opens the weapon wheel; tap a gun to take it.
- On a small phone (844 × 390) the buttons, the right column, the contextual action and the breath bar keep clear of
  each other, of the thumbstick and of the jump button (`client/TouchLayout.luau`, `tests/touchlayout_test.luau`);
  the hints and Marge drop the (E) / (G) keys, and her dialog sits in the middle at a readable size.
- A gamepad: **Y** opens MENU with the selection on JOBS (the stick moves on, A takes it), the job board starts on its
  first ACCEPT JOB, **d-pad up** takes the next gun.

Everything is built in code (the world, the cars, the enemies, the interface), so the game needs no assets: open an
empty place and sync. The icon set and the logo are optional (see **Graphics**).

## Working on the game with AI helpers

Claude Code and Codex both work on this game and share the work through the repository: the rules are in
[`AGENTS.md`](AGENTS.md), the task board is [`COLLAB.md`](COLLAB.md) (who works on what, branches to review).

## Running

```bash
node tools/rojo-sync.js zombie-delivery
```

(from the repository root). In Studio open a **new Baseplate place** (not the Merge Blades one), then
**Plugins → Rojo → Connect** and **Play**. Turn on **StreamingEnabled** in the place (Workspace → StreamingEnabled;
the city has thousands of parts, and the server warns in the Output when it is off). Instead of the command you can double-click
`zombie-delivery/spust-zombie-delivery.cmd` (Windows) or `zombie-delivery/spust-zombie-delivery.command` (Mac):
git pull + the sync.

**6.8.1, the sync after a `git pull`:**
- On every **Connect** in Studio, `tools/rojo-sync.js` reads the disk again. It also checks the files every 5 s.
- Starting the sync a second time stops the old one, even when the old one is in another window. A running old sync
  used to keep the new one off the port.
- Before 6.8.1, a big pull could leave Studio with a mix of old and new scripts. 6.7 and 6.8 hit this: Studio kept the
  6.6 `CharacterArt/Geometry`, so it built the old block courier, and the Output said `[Npcs] no realistic body …
  Unknown character art: person`.
- After a pull, start the sync, then use Disconnect / Connect in Rojo. The Output must show the new version:
  `[Server] Zombie Delivery 6.8.1 is running`.

A Play test in Studio starts like a new player, with `Config.StudioStartMoney` ($150; the admin panel, P, gives money
for testing). A published game starts with `Config.StartMoney` and saves to the DataStore `Config.DataStoreName`.
Since 4.2 a save is locked to the server that plays it (UpdateAsync, `Config.SaveLockWait` / `SaveLockStale`): a quick
rejoin on another server waits up to 15 s for the last server's leave save, a stale server never overwrites newer
data, leave and shutdown saves retry, and a save that cannot be read on a live server kicks with "please rejoin" instead
of letting you play a profile that would not be saved.

## How to play

| Input | PC | Touch |
|---|---|---|
| Drive / walk | WASD / arrows | thumbstick |
| Sprint (on foot; the body speeds up and slows down with weight, leans into the run, and out of a sprint the gun comes up slower) | hold Shift (gamepad: click the left stick) | SPRINT left of the jump button (4.2: a toggle; it turns off when the breath runs dry) |
| Aim (GTA style: the mouse is locked, the camera follows it, crosshair in the middle) | move the mouse | – |
| Aim (on foot you walk slowly with both arms up, the gun fires once it is up; in a car the camera moves in for a drive-by) | hold right mouse | – |
| Shoot (on foot: the gun in your hand; driver: the car gun on the roof if the car has one, else a one-handed gun out of the window; passenger: a one-handed gun out of the window) | left mouse | FIRE |
| Shoot the nearest enemy (auto-aim) | hold F | hold FIRE |
| What you hold (6.1): fists / the plastic bag / your gun (a loaded bag that leaves your hand is set down on the ground: E picks it up) | 1 / 2 / 3 (gamepad: d-pad left / right cycles) | tap the hand slots at the left of the bottom bar |
| Holster / draw the gun (3.9; on foot, you start holstered; 6.1.1: aiming or shooting no longer draws it, with fists the left mouse punches; 6.1: 3 draws your gun too, not over a loaded bag) | B | DRAW / HOLSTER (over PUNCH) |
| Melee (3.9; on foot): a punch while holstered, a strike with the gun while it is out | V (gamepad: L1) | PUNCH / STRIKE left of FIRE |
| Throw at a home's door (6.0; 6.1: with the bag in your hand or a light piece in your hands, else it says why; 6.2: it aims itself, let go in the gold zone for a PERFECT tip) | hold X (gamepad R1) | THROW |
| Key hints (6.1: fold / unfold the strip under the top buttons) | F1, or its KEYS chip | – |
| Switch gun | hold T: the weapon wheel (point at a gun, let go); tap T: the next gun (5.4.1: Q is the phone); or click the weapon label (gamepad: d-pad up, the next gun) | tap the weapon label: the weapon wheel, tap a gun (4.2) |
| Items (repair, medkit, nitro, molotov, mine) | 4 – 8 (6.1; 9 a sixth kind; or click a slot) | the slots |
| Free the mouse (click the interface) | hold Alt (any window frees it too) | – |
| The Dispatch board (the jobs) / map / bag & items | J / M / I (3.9; B before) | BOARD on the phone / MAP / BAG on the phone |
| The phone (5.0; 5.7: the HUD's MENU button says PHONE once you have it; 6.5: six tiles JOBS, MAP, SHOP, BAG & ITEMS, GARAGE, MORE, and in MORE: CAREER, MISSIONS, CREW, TOP, ESTATE, BANK, MESSAGES, SETTINGS) | Q, or click PHONE (gamepad: Y) | tap PHONE |
| The career (your level, the road, the licences) | C | CAREER on the phone |
| Close a window, the big map or MENU | the ✕ at the top right, or the window's own key again (J, U, K, H, L, I, M); ESC / gamepad B still work | ✕ |
| Call your car or bring your bike (or reset it while you sit in it) | Q → GARAGE: CALL CAR / MY BIKE | PHONE → GARAGE |
| Give up the delivery | Q → ORDERS → GIVE UP, twice (or on the Dispatch board) | the same |
| Rent / return a ZDC RIDE scooter (5.6; 6.3: a rack of six right behind the spawn) | hold E at a dock | the prompt |
| Ride a city bus (5.5) | E at its door (Board); E in your seat rings the bell (STOP) | the prompts |
| Show or hide the bus lines on the big map (6.3) | the BUS chip in the map's header | the same |
| Zip line: climb the ladder yourself, zip, let go (5.6; 6.10) | walk into the ladder; on the start platform E (Zip) or a jump; Space lets go low over a roof | the prompt, the jump button |
| Music and sound (on / music off / all off) | N | SOUND in MENU |
| Missions (6.8: who you work for: the clients and their story chapters, START, the stars; 3.1: the CHALLENGES, SECRETS and REWARDS tabs) | U | MORE → MISSIONS on the phone |
| Crew panel (invite / accept / leave / kick, the crew board) | K | CREW |
| Leaderboard | L | TOP in MENU |
| Get in your car / ride in a friend's car (3.10: at a door, a quick move in) | E (gamepad X) | the prompt |
| Get out (3.10: you slide out at your door) | E or Space (gamepad X) | EXIT left of FIRE (4.2), or the jump button |
| Pick up / Load / Take out / Hand over / Lead a horse (on foot, at a stop) | hold E | the prompt |
| Open / close the back (doors, tailgate, trunk, ramp; 3.2: with empty hands, the car standing) | hold E at the back | the prompt |
| Put down / Let go / set the trolley or the pallet jack down (to shoot; anybody of the crew can pick it up again) | G (gamepad B) | PUT DOWN / LET GO / SET DOWN left of FIRE (4.2), or the prompt |
| Open a lost package (3.1) | hold E | the prompt |
| Real estate list (every property, buy, sell, set your home, GPS) | H | ESTATE in MENU |
| View a property's listing (at its FOR SALE sign) | E | the prompt |
| Run your company (at your office's computer: hire, upgrades, collect the safe) | E | the prompt |
| Ride a tower elevator (step on a pad under a floor sign) | walk onto it | walk onto it |
| Admin panel (testing tools; only for admins: a Studio Play test, the place's owner, `Config.Admin.UserIds`) | P | the ADMIN button |

**How fast everything goes** (5.7; studs per second, at the top: `Config.Movement`, `Config.Rental`, `Config.Cars`
maxSpeed, `Config.Bus`, `Config.ZipLines`):

| On foot and two wheels | Top | | Cars | Top |
|---|---|---|---|---|
| Walk (Running Shoes ×1.1) | 14 (15.4) | | Old Van: Rusty / Patched / Work / Long Cargo | 42 / 48 / 54 / 56 |
| Sprint (about 6 s of breath) | 28 | | Freight Truck | 45 |
| ZDC RIDE rental scooter (free) | 26 | | High-Roof Van | 62 |
| Rusty Bike | 30 | | Box Truck | 64 |
| Cargo Bike | 32 | | Courier Van | 70 |
| E-Scooter (bought) | 36 | | Pickup | 72 |
| Courier Bike | 38 | | Armored Van | 74 |
| E-Bike | 48 | | Muscle Car | 95 |
| City bus (free, express on its timetable; 6.3) | 55 | | Rally Van | 98 |
| Zip line | 55 | | (the Engine upgrade: +8 % a level) | |

While you carry something (or lead a horse) you cannot shoot, sprint or drive, and you walk slower. A car with its
back open does not drive (3.2).

**Guns and cars.** You buy guns for your hands (Lead & Co.); you start with the pistol. From a car seat (driver or
passenger) only a **one-handed** gun fires, out of the side window: the **pistol, the revolver and the SMG**. The
two-handed ones (shotgun, rifle, carbine, minigun, grenade launcher) do not fire from a car (a short hint says so; the
weapon label says ON FOOT ONLY for them and WINDOW READY for the others). **Car guns** are something else: bolted on the roof at
**Wrench Garage** (CAR GUNS tab), one per car, and the driver fires them (the turret turns to the target, the weapon label
shows it). A car starts with none. They fit every car of the dealer (3.3: the five new vans too), the Armored Truck and
the Monster Truck, not the work vehicles (bus, ice cream, moving, livestock, fuel truck). A driver without a car gun shoots a
one-handed gun out of the window (a drive-by); passengers always use their own gun.

1. The **start screen** flies over the city; **PLAY** starts the game and brings your car. With a **home** (see
   **Real estate and your company**) you spawn there after PLAY and after every death, and your car waits in front of
   the home's garage (walk to it and press E); without one the car is placed next to you and you sit in it.
2. Without a home you start at the **depot** in the middle of Downtown. Around it is the **safe zone** (green line) with the shops:
   **Dead End Motors** (cars: 3.5, the car catalog at the sales counter, three display cars inside), **Lead & Co.**
   (guns), **Wrench Garage** (upgrades, 3.5 the car's **stages**, paint jobs, car guns and, 3.4, two **repair
   bays**), **Last Stop Supplies** (items). Walk in and use the counter. The
   depot's **Depot Garage** terminal is your starting van's lot (3.4: your other cars wait in your garages).
3. **JOBS** (or the job board at the depot): one special job and one delivery of every danger level.
   * Every delivery has stops: **pick up** at the blue circle, **deliver** at the yellow one. Park in the circle, **get
     out** and handle the cargo yourself: **Pick up** (E) a piece from the giver's pile, carry it to the back of the
     vehicle, put it down (G), **open the back** (E), pick it up again and **Load** it (E); the loaded pieces ride
     visibly in the vehicle; **close the back** (E) and drive on. At the drop open the back, **Take out** (E), carry
     it to the receiver and **Hand over** (E), and close it again (see **Loading through the back**). Horses are **led on a rope** into the truck's stalls and
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
     ★★★★ 7), and so do the special jobs and (3.2) the employers' jobs (see **Driver levels and the progression**).
   * 3.4: a job with more pieces than your car holds shows **📦 NEEDS N SLOTS** ("your Old Van holds 2") instead of
     ACCEPT; the dangerous levels sometimes send a **bulk order** (3.5: ★★ up to 4 pieces, ★★★ up to 5, ★★★★ up to 8;
     a ★ delivery never more than 2, the Rusty Van's slots).
   * **Work for the people who run things** (the WORK HERE boards, ★ yellow on the map). They lend you their vehicle
     for the job; after enough jobs the vehicle is yours, and some of them also give you a **gun** (not sold anywhere):
     * **Sunny Hill School** (Suburbs; level 2): School Run, pick up kids at 3 homes → **School Bus** after 3 jobs
     * **Military Base** (north, through the tunnel; level 7): Army Supply, ammo from the docks → **Army Carbine**
       after 2 jobs, **Armored Truck** after 4
     * **Frosty's Ice Cream** (Harbor; level 2): Ice Cream Route, sell at 4 stops → **Ice Cream Truck** after 3
     * **Big Move Movers** (Downtown; level 3): Moving Day, furniture to a new home → **Moving Truck** after 3
     * **Old Farm** (west; level 8): Farm Run, food to two city markets → **Monster Truck** after 3
     * **Silver Spur Ranch** (off the West Highway; level 5): Horse Transport, two horses to the Riverside Riding
       School → **Ranch Revolver** after 2 jobs, **Livestock Truck** after 4
     * **Gas Station** (North Highway; level 4): Fuel Run, fuel barrels from the Harbor Fuel Depot → **Fuel Truck**
       after 3
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
   CAR entry of the … menu counts down. Since 3.9.1 the chauffeur stops at red traffic lights and waits in the queue
   like everybody; it takes the time it takes. Only a car that gets no closer for **10 s** (`Config.CarCall.StuckFor`)
   is rescued: out of your sight it is put back on a road out of sight and drives on; the second time it is placed
   next to you and you sit in it, the old way. If the car is wrecked on the way the HUD says so (press CAR again); a respawn
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
   its clock. Friends who press E at your car's passenger door to ride along are paid the same way while they stay with the job (in
   your car, or on foot within `Config.Crew.RiderRange` = 250 studs of you); at most `MaxMembers` are paid, the
   members first. Every member and rider gets half of the pay and the same XP, you get +15 % per member: nobody
   loses money (the panel shows the split of the base pay). Since 3.0 the crew **stays together** when a job ends:
   it breaks up only when you break it up, or for a member who leaves (LEAVE), is taken out (KICK), takes a job of
   their own or quits; a piece a former member was carrying drops where they stand. The **crew board** (LOOKING FOR
   CREW in the crew window) lists the players who want a crew, for one mission or any, with INVITE; your own toggle
   puts you on it, and FIND CREW on a co-op mission does that and opens the window.

**Driver levels and the progression.** Every delivery gives XP: stars × 60 + 10 per piece delivered + 4 per kill,
× 1.25 at night; a failed job gives 25 % (once something was done). 15 levels, each with a rank name (Rookie Courier,
Courier, Runner, Road Rat, Road Warrior, Veteran Driver, Wasteland Trucker at 8, Convoy Captain at 10, Dead End Legend
at 12, King of the Road at 15). Since 3.2 the levels are a real progression (it is not a game about buying things):
the levels open the gear one step after another, the campaigns open one after another (see **Missions**), and the
real estate and your company come at the very end. Everything locked shows **🔒 LEVEL N** (or **FINISH <CAMPAIGN>**)
until then:

| Level | Rank | XP | Opens | Reward |
|---|---|---|---|---|
| 1 | Rookie Courier | 0 | On-foot runs: letters, medicine, pizza, Plastic Bag (kit, ZDC Bags), Running Shoes (kit), Thermal Jacket (kit), Pistol | – |
| 2 | Courier | 575 | **Rusty Bike at Spoke & Chain** ($300), **Courier Bike at Spoke & Chain** ($1,100), Front Basket (gear), Canvas Tote (kit), Rented Lockup | $500, 2 Medkits |
| 3 | Runner | 1,265 | **Cargo Bike at Spoke & Chain** ($2,400), Panniers (gear), Thermal Delivery Bag (kit), SMG | $750, 2 Medkits, the Canvas Tote (6.6) |
| 4 | Road Rat | 2,093 | ★ Easy jobs, School Run (Sunny Hill School), Ice Cream Route (Frosty's Ice Cream), Moving Day (Big Move Movers), Fuel Run (Gas Station), Ambulance Run (City Clinic), Pizza Rush, **Old Van: Earl's Used Wheels (Marge's quest at level 4)** ($1,800), **E-Scooter at Spoke & Chain** ($2,800), the Patched Van stage, Hand Trolley (gear), Ratchet Straps (gear), Bike Trailer (gear), Padded Messenger Bag (kit), Shotgun, First Shift (campaign), Southside Garage | $1,000, 2 Medkits, the Running Shoes |
| 5 | Road Warrior | 3,087 | ★★ Risky jobs, Horse Transport (Silver Spur Ranch), Cash Transport, **Courier Van** ($3,500), **High-Roof Van** ($7,000), **E-Bike at Spoke & Chain** ($6,500), the Work Van stage, Cooler Box (gear), Roof Machine Gun, Code Red (campaign), Harbor Lockup | $1,500, 2 Repair Kits, Hi-Vis Orange paint |
| 6 | Veteran Driver | 4,279 | ★★★ Deadly jobs (licence: 5 jobs rated ★★+ at ★★), Freight Run, **Pickup** ($12,000), the Long Cargo Van stage, the Express Courier stage, Big Delivery Duffel (kit), Hunting Rifle, Empty Shelves (campaign), Partners in Crime (campaign), Highway Garage, Elm Bungalow | $2,000, 4 Molotovs |
| 7 | Veteran Driver | 5,710 | Army Supply (Military Base), **Box Truck** ($22,000), the Tall Hauler stage, the Ranch Pickup stage, Roof Rack (gear), Smoke and Sirens (campaign), Downtown Parking, Birch Cottage | $2,500, 2 Landmines |
| 8 | Wasteland Trucker | 7,427 | 7 Oak Lane | $3,500, 3 Nitros |
| 9 | Wasteland Trucker | 9,487 | ★★★★ INSANE jobs (licence: 10 jobs rated ★★+ at ★★★), Farm Run (Old Farm), Winter Run, **Muscle Car** ($40,000), the Liftgate Truck stage, Iron Supply (campaign), 12 Maple Street | $4,500, 3 Repair Kits |
| 10 | Convoy Captain | 11,959 | **Freight Truck** ($45,000), the Street Machine stage, Minigun, Roof Minigun, Lights Out (campaign), Sunset Villa | $6,000, the title “Iron Courier” |
| 11 | Convoy Captain | 14,926 | **Armored Van** ($55,000), the Freight Hauler stage, Wild West End (campaign), Lakeside Villa | $7,000, 3 Medkits |
| 12 | Dead End Legend | 18,486 | the Fortress Van stage, Grenade Launcher, Roof Grenade Launcher, Patient Zero (campaign), Harbor Point Office | $8,500, 3 Nitros, 4 Molotovs |
| 13 | Dead End Legend | 22,758 | **Rally Van** ($80,000), Dirty Money (campaign), Pinecrest Mansion | $10,000, 3 Landmines |
| 14 | Dead End Legend | 27,885 | the Works Rally stage, Last Convoy (campaign), Ocean View Mansion, Dispatch Tower, 8th floor | $12,000, 3 Repair Kits, 3 Medkits |
| 15 | King of the Road | 34,037 | Hilltop Mansion, Dispatch Tower Penthouse | $15,000, Legend Chrome paint, the title “Legend of the Last Road” |

(5.7: the table is `Career.road()` as the CAREER window shows it: every unlock from Config, the reward from
`Config.Levels.Rewards`. A car's gear, the Hand Trolley, shows with the first car at level 4.)

* **Cars** (5.0): you start on foot; bikes from level 2 at Spoke & Chain, Earl's Old Van at 4, then the dealer's cars
  (level and price rise together). The company vehicles come with their employer's job level; the **stages** open by
  level too (see **Stages and the cars' roles**).
* **Rewards** (5.7): levels 2 – 4 give what a courier on foot or on a bike uses (medkits, the Canvas Tote (6.6: no
  backpacks), the Running Shoes; a kit you own already pays its price instead); the car's items (repair kits, nitro, mines) start at
  level 5, once you drive.
* **Real estate** (the endgame): garages 2 – 7 (3.4: the two small ones early), houses 6 – 9, villas 10 – 11, mansions 13 – 15 ($3 – 6 million), and
  the offices 12, 14 and 15, each also needing a campaign's finale (Iron Supply, Dirty Money, Last Convoy; the ESTATE
  list says "Finish Iron Supply first"). Hiring a courier costs $40,000.
* **The XP curve** (`Config.Levels`): level 2 needs 575 XP, every next step × 1.2; level 15 needs 34,037 XP. The first
  clears of the 100 story missions (their job XP × 1.5) give about 32,000; with the kills on the way you never wait for
  a level on the story path: level 4 after First Shift, 8 after Empty Shelves, 13 after Wild West End, 14 by the end
  of Dirty Money and 15 inside Last Convoy. Without kills you come a little short around Patient Zero (a couple of
  board jobs). The job board, the replays for stars and the DUO campaign come on top.
* **Old saves**: a 3.1 save keeps its level: its XP (on the old 120 × 1.35 curve) is moved once to the same level and
  the same share of the next one on the new curve (`Levels.fromLegacy`; the save's `xpCurve` marks it done). A
  campaign you already started stays open even without the campaign before it, and a mission you already cleared can
  be replayed for stars at any level. Gear you own stays yours.

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

Press **U** (or **MISSIONS**, or the phone's MORE → MISSIONS) anywhere: **who you work for** (6.8). Every client has
**one chapter of six missions** told in order (`shared/Missions.luau`, the people in `shared/Cast.luau`): each
briefing picks up where the last debrief stopped, and the finale pays the chapter's big reward. Ten story chapters
and the DUO one, 66 missions; the stars on top (X / 198, every count computed from the data).

**The window** (`client/MissionsUi.luau`; its measures in `client/MissionsLayout.luau`): on the left a card per client
with their **portrait** (`client/Portrait.luau`: a bust of their NPC, dressed from `shared/NpcLooks.luau`, in a
ViewportFrame over the chapter's colour), the name, the role and the place, the progress "2 / 6", or why it is shut
("🔒 Level 6", "🔒 Finish Raj's chapter first"), and NEW / ✓ DONE / 🤝 DUO badges. On the right the chosen client big:
the portrait, the name, the role, the pitch; the **action card** with the next mission (the briefing in the client's
words, the route, the twists, what the pay is made of); **THE STORY**: the six missions as a path (✓ done, ▶ next, 🔒
locked: "Finish 'X' first" / "Level 7"), each with a one-line description and its pay; then the finale's reward with
its picture. Under the chapter, never scrolled away (6.8 review), the **action bar**: the pay ("FIRST TIME · ≈ $1,220 +
540 XP" or "REPLAY · ≈ $300"), why START would be refused, FIND CREW on a co-op or DUO mission and a big **START** (GO TO
<client> for a shut chapter). A small screen (a phone held sideways) stacks the clients as a strip on top of the
chapter, with a smaller hero portrait. With a gamepad START is selected on opening and the selection stays put when the
server's state comes (a page that did not change is not drawn again) or a client or a step is chosen. A member of somebody else's crew sees "Your crew leader picks the
mission"; the mission starts right where you are; a NIGHT ONLY one starts only after dark.

**The order** (`Missions.unlocked` / `statusOf` / `nextUp` / `chapterState`): in a chapter only the **next** mission
(the first not done) starts; the later ones wait for it; a done one replays. The chapters open one after another
(`Campaign.requires`: every story chapter needs the finale of the one before it, Last Convoy all nine), then at their
level; inside a chapter the missions sit at its level and the finale at the next chapter's (`Missions.levelOf`). Played
in order the story itself carries you to level 15 (tests/missions_story_test.luau).

| Client | Chapter | Opens | The six missions, in order | Finale's reward |
|---|---|---|---|---|
| Marge, the dispatcher | 📦 First Shift | level 4 | Paper Trail → Mail Call → Birthday Emergency → Dead Letter Office → Wheels of Commerce → **Rush Hour of the Dead** | $2,500 · Dispatch Yellow paint · "Dispatcher's Favourite" |
| Doctor Ellie, the City Clinic | 🏥 Code Red | 5, after Marge | House Call → Code Blue → Many Hands → Ambulance Chaser → Quarantine Zone → **Code Red** | $4,000 · Medic Mint paint · "Field Medic" |
| Raj, FreshMart | 🛒 Empty Shelves | 6, after Ellie | Stock Up → Bread Line → Farm to Table → Seeds of Hope → Price War → **Empty Shelves** | $5,500 · Fresh Lime paint · "Grocery Hero" |
| Rosa & Rico, the twins (DUO) | 🤝 Partners in Crime | 6, after Marge | Double Act → Flood Gate → Two Keys → Cold Hands → Mirror Run → **Partners in Crime** | $7,500 · Tandem Twin paint · "Partners in Crime" |
| Chief Carlos, Fire Station 9 | 🚒 Smoke and Sirens | 7, after Raj | Hose Down → Smoke Eaters → Fuel the Engines → Firebreak → Oil Fire → **Smoke and Sirens** | $7,000 · Fire Engine paint · "Smoke Eater" |
| Captain Maria, the Military Base | 🪖 Iron Supply | 9, after Carlos | Ammo Run → Mess Hall → Boom Sticks → Wounded in Action → Eyes in the Sky → **Iron Supply** | $9,000 · Maria's Carbine · "Quartermaster" |
| Engineer Ivan, the Power Plant | ⚡ Lights Out | 10, after Maria | Spare Parts → Battery Life → Blackout → Copper Thieves → Cooling Water → **Lights Out** | $11,000 · Volt Neon paint · "Live Wire" |
| Walt, the rancher | 🐴 Wild West End | 11, after Ivan | Saddle Up → Feed Run → Horse Whisperer → Moonlight Rustlers → Showdown → **Wild West End** | $13,000 · Walt's Lever Rifle · "Outlaw Tamer" |
| Doctor Hiro, the lab chief | 🧪 Patient Zero | 12, after Walt | Lab Rats → Deep Freeze → Power Hungry → Patient Zero → Midnight Formula → **The Cure** | $16,000 · Toxic Glow paint · "Cure Runner" |
| Vinnie, the fixer | 💰 Dirty Money | 13, after Hiro | No Questions Asked → Laundry Day → Art Appreciation → Heavy Business → Fireworks → **Dirty Money** | $20,000 · Vinnie's Golden Pistol · "Made Man" |
| Mayor Ruth, City Hall | 🚌 Last Convoy | 14, after all nine | Evacuation Plan → Fuel for the Flight → Seed Vault → The Mayor's Kids → Last Boat → **Last Convoy** | $30,000 · Sunrise Chrome paint · "Last Convoy Captain" |

* **Stars** (`Missions.rate`): done = ★; the cargo still at 75 % or more = ★★; and 30 % or more of the clock left =
  ★★★. Your best rating per mission is saved (a rating of 1 or more = done).
* **Rewards** (6.8, `Missions.creditFor`, server/Missions.luau, server/Jobs.luau): the **first time** a mission is done
  it pays the job's pay (× the twists), its **first-time reward** ($400 – $11,000) and the job's XP × 2.5
  (`FirstClearXp`); the chapter's finale pays the **chapter's reward** once (the money, and its exclusive gun or paint
  and title, `Config.Rewards.Campaigns`). A **replay** pays only a quarter of the job's pay and of its XP
  (`Config.Missions.ReplayPay` / `ReplayXp`): no reward, no XP bonus, no unlock; the window and the card say
  "REPLAY · $X". A new best rating still pays $150 a new star (`StarBonus`, once per star). A celebration card shows
  it: the stars, the client's debrief, FIRST CLEAR! or REPLAY · $X, the rewards and NEXT (the chapter's next mission).
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
  | 🤝 PAIR LIFT (3.2, DUO only) | the pieces only move with two: no pick-up or take-out without another job member within 10 studs, and the piece goes down when the partner is gone for 1.5 s | × 1.3 |
  | 🎛 TWIN SWITCHES (3.2, DUO only) | two levers 22 studs apart at the stop: two different players pull them within 1.5 s of each other to open the gate | × 1.25 |

* **Co-op** (CO-OP chips; outside the DUO chapter they can be played alone): for every crew mate besides you
  (members and riders, `MaxMembers` at most) the pay is × (1 + 0.25 per mate) for everybody and the enemies (waves,
  foot waves, hordes) × (1 + 0.35 per mate), recounted when the crew changes (a toast says so).
* **The crew gets the stars too** (`Config.Missions.CrewCredit`): the members and riders with you at the finish get
  the rating, the first time's reward and the chapter as if it were theirs, if the mission is open for them (it is
  their next one, or one they have done); otherwise only their share of the pay. A crew member who has done the
  mission before gets the replay's share of their pay.
* During a mission a **banner** in the HUD's top stack shows "MISSION 3/6 · Name", the twists, the crew count, the
  HOLD OUT countdown and (3.2) the TWIN SWITCHES lever count; the crew members' strip and banner show it too.
* The leaderboard (L) has a **STARS** column (ties on the level go to the stars).

### The DUO chapter

**Partners in Crime** (3.2, 🤝, Rosa & Rico, the twins; level 6, after First Shift's finale) is six missions **only
for a crew** (`duo = true`, all co-op), told for two: Double Act, Flood Gate, Two Keys, Cold Hands, Mirror Run and the
finale Partners in Crime (levels 6 → 10). The window marks it **NEEDS A PARTNER** and it is a side story: no story
chapter, no property and none of the "every …" challenges need it (6.8).

* **Start rule** (server/Missions.luau): START needs at least `Config.Missions.Duo.MinCrew` = 1 crew member online
  and within `StartRange` = 120 studs; otherwise `Config.Missions.Duo.NeedsPartner` ("NEEDS A PARTNER: invite a friend
  to your crew (K) and bring them here …"; the card shows FIND CREW). If the crew drops below that during the mission
  (a partner leaves the crew or the game), the mission fails: "Your partner left."
* **Pair lift** (`pair`): Jobs passes `Info.pair` to Cargo; a piece is picked up, carried or taken out only while
  another job member is within `PairRange` = 10 studs ("Pair lift: you need your partner on the other side.");
  alone for more than 1.5 s, the piece goes down.
* **Twin switches** (`switches`, `server/DuoGates.luau`): at the last drop (or every pick-up of a mission with
  `gates = "pickup"`) a gate with two lever posts `LeverApart` = 22 studs apart blocks the stop
  (`Cargo.setBlocked`, the hint "Pull both levers together!"). A pull holds its lever down for `LeverWindow` = 1.5 s;
  both down at once, pulled by **two different players**, and the boom swings up and the stop opens. The gate goes
  when the stop is done or the job ends.
* **Reward**: $7,500, the **Tandem Twin** paint (metal) and the title **Partners in Crime**.

## Loading through the back

Since 3.2 every vehicle that takes cargo by hand has a **back that opens** (`Style.back` in server/Vehicles.luau):

| Vehicle | The back |
|---|---|
| Old Van, Courier Van, High-Roof Van, Box Truck, Armored Van, Rally Van, Ice Cream Truck, Armored Truck, Moving Truck, Ambulance | two rear doors |
| Freight Truck (4.0) | a roll-up door (one slatted leaf that turns up and in under the roof: "Open roll-up door") |
| Pickup, Monster Truck (new bed rails), Fuel Truck (the flatbed) | a tailgate |
| Muscle Car | a trunk lid (the spoiler rides on it) |
| Livestock Truck | a horse ramp down to the ground |

The leaves hang on Motor6Ds "BackHinge"; the server sets the car's `BackOpen` attribute and every client swings them
(client/CarVisuals.luau, an eased 0.45 s). Traffic, bandit, NPC and showroom cars have them welded shut. The
**BackPrompt** at the back ("Open doors" / "Close doors", "Open tailgate", "Lower ramp" …) needs **empty hands**, the
car standing, and the owner or the job's crew (it shows only to them).

The loading at a **carry** or **lead** stop:

1. Pick up a piece at the pile (E) and walk to the car. With the back shut the hint says "Put it down (G) and open
   the back doors (E)".
2. Put it down (G), open the back (E), pick the piece up again (E) and **Load** it (E): Load and Take out only work
   through an open back, and the BackPrompt and the Load prompt take turns on the one E.
3. When the stop's pieces are in: "Close the back doors (E), then drive on". **A car with its back open does not
   drive**: the Drive prompt refuses the owner, client/Drive.luau holds the throttle and toasts "Close the back
   first"; the chauffeur closes it at the hand-over, a new car starts closed, and a job's end closes it too.
4. At the drop the same way round: park in the circle, open the back, **Take out** (only with the car in the stop's
   circle), carry it to the receiver, Hand over, close the back.

The holds are short (`Config.Cargo.HoldDuration`), so the extra steps add a few seconds per stop. **board** stops
(the bus, the ambulance's patients, the survivors) and **serve** stops (the ice cream) do not use the back.

## Freight: the hand trolley, pallets and the warehouse (4.0)

The rules are in `shared/Freight.luau` (pure, tested in `tests/freight_test.luau`), the tools in
`server/Equipment.luau`, the pieces in `server/Cargo.luau`, the numbers in `Config.Cargo` (TrolleyPieces …
PalletPay).

- **The hand trolley** (a car with the Hand Trolley upgrade: its `TrolleyMount`). "Take trolley" (E) at the mount
  while the back is open, at the back corner while it is shut. You push it (character attributes `Pushing =
  "trolley"`, `Carrying`, `CarryHands = 1`, `CarrySpeed` 10 empty / 8.5 loaded): no gun, no sprint, a hand free for
  the doors. "Load onto trolley" (E) at the pile loads as many as fit (4, any kind but people, horses and pallets;
  not on a lift or pair mission), "Load all" at the open back puts them in (as many as there is room for), at a drop
  "Take out" fills it and "Hand over" gives them all. **G**: at your car's open back "Stow trolley", anywhere else
  "Set down trolley" (it stands there, its pieces on it, "Take trolley" again). Left with nobody within 40 studs it
  goes back to the car after 60 s (its pieces go on the ground). Death, leaving and sitting set it down. The pieces
  on a trolley count exactly like the ones in your hands (`Held.tool`) or put down (`Loose.tool`).
- **Pallets** (the cargo kind `pallet`, about 4×4×4 of shrink-wrapped boxes) never go by hand ("Too heavy: use a
  pallet jack"). **The pallet jack** (ještěrka): on the jack spots of the warehouse docks and of every receiving
  dock, and in the Freight Truck (`JackMount`, inside its back). `Pushing = "jack"`, walk 6. "Lift pallet" (E), "Load
  pallet" at the open back of a vehicle that takes pallets (`Economy.palletsOf`; a pallet uses 4 slots and stands on
  its 2×2 slot group, or the chassis' `PalletSlotN` attachments if a body has them), at the drop "Unload pallet" and
  "Set down pallet" on the receiving pad. G parks a dock's jack on its spot, stows the truck's, else sets it down; a
  jack left alone goes back after 90 s.
- **The Harbor Warehouse** is a freight hub (`Map.FreightDocks`): two loading docks with a raised dock floor (a
  truck's load floor), ramps, dock plates and bumpers, painted bays, staging squares inside the doors, two jack
  spots, forklifts and pallet racks. The old mission door and its cargo spot stay as they were (the forklift and
  the lost package moved south). **Receiving docks** (`Map.ReceivingDocks`): FreshMart, Big Move Movers and the Power
  Plant, a marked pad with a RECEIVING sign and the place's own jack.
- **The Freight Run** (`Config.JobTypes` "freightrun", ★★★, level 6): 1 – 3 pallets from a dock to a receiving dock,
  good pay (+ `PalletPay` a pallet). On every board from its level; without a vehicle that takes its pallets it shows
  locked "NEEDS N PALLETS". Ordinary jobs with 4+ carried pieces say on their card that a trolley helps.
- **Later: a semi truck with a trailer.** Nothing here is tied to one truck: a hub is a list of docks (a longer bay
  is one more dock with its own park and staging), a vehicle says how many pallets it takes (`palletsOf`) and where
  they stand (its slot groups or `PalletSlotN` attachments, else a row behind the last), and a trailer's body can
  carry its own `JackMount`.

## The vans and the upgrades you can see

Version 3.3 (`Config.Cars`, `Config.Upgrades`, server/Vehicles.luau `STYLES` and `buildKit`).

**Five more vans** at Dead End Motors, each with its own body built from boxes like the Old Van: two rear doors that
open for the loading (3.2), cargo slots in the back, a roof that takes a car gun, and passenger seats. They paint like
the Old Van (the body panels and the doors; the steel plates, grilles and lights keep their colours); the courier
van, the high-roof van and the box truck also drive past in the traffic.

| Car | Level | Price | Top speed | Health | Ram | Passengers | The look |
|---|---|---|---|---|---|---|---|
| Old Van | 1 | free | 42 (4.0; 60 before) | 300 | × 1.0 | 1 | the start (3.5: rusty, it grows in stages; 4.0: slow off the line, four stages) |
| **Courier Van** | 2 | $3,500 | 70 | 320 | × 1.0 | 1 | compact and low, a sliding-door line, an amber light bar on the roof |
| **High-Roof Van** | 3 | $7,000 | 62 | 450 | × 1.1 | 2 | a tall roof, windows down the box, a jump seat |
| Pickup | 4 | $12,000 | 72 | 420 | × 1.15 | 3 | |
| **Box Truck** | 6 | $22,000 | 64 | 650 | × 1.4 | 2 | a cab and a big separate box, a wind deflector, a red stripe |
| Muscle Car | 8 | $40,000 | 95 | 340 | × 1.0 | 1 | |
| **Freight Truck** (4.0) | 9 | $45,000 | 45 | 900 | × 2.0 | 1 | a cab-over truck with a long box, a roll-up door, twin rear tyres (see **Freight vehicles and the upgrades you see**) |
| **Armored Van** | 10 | $55,000 | 74 | 900 | × 1.6 | 2 | steel plates on the box, the hood and the nose, grilles over the windows |
| **Rally Van** | 12 | $80,000 | 98 | 420 | × 1.1 | 1 | lowered, big wheels under flares, stripes, a roof spoiler |

A car needs a free car slot: since 3.4 the depot holds only your starting van, every further car needs a garage slot
(see **Cars, cargo, garages and the repair shop**).

**The upgrades belong to one car.** At Wrench Garage the car tracks (Engine, Tyres & Suspension, Armor, Ram Plow; 4.0: the Hand Trolley)
upgrade the car you have equipped (`profile.carUpgrades[carId]`; the window says "Upgrades for: Courier Van", the price
grows with that car's level); a new car starts stock. Gun Damage and Fire Rate stay for all your guns and car guns
("For all your guns"). The employers' company vehicles cannot be upgraded. An older save's upgrades (they were for
every car) are copied once to every car it owns (`Economy.migrateCarUpgrades`).

**You see them on the car** (`buildKit`, the folder "UpgradeKit", fitted to every body from its width, length, front
end, hood and first window; rebuilt when you upgrade):

* **Ram Plow** from level 1: a bull bar in front of the nose (two posts, two bars), wider and thicker with every level,
  a plow blade under it from level 3 and rubber pads at 5.
* **Armor** from level 1: steel plates along both sides between the wheels, taller with the level (a rim from 4); from
  level 3 **grilles** over the windscreen and the front side windows (the Armored Van has its own).
* **Engine** from level 3: a **hood scoop** (taller at 5) and **twin exhaust pipes** under the back. 4.0: level 1 stops
  the Rusty Van's **smoking exhaust**.
* **Tyres & Suspension** (4.0; the id stays `handling`, +8 % steering a level): from level 1 **new black tyres** with a
  tread ring (bald grey ones before, on the Rusty and the Patched Van), from 3 **alloy rims** (silver discs), at 5 a
  **lower stance** (the body sits 0.25 lower: the car is built again).
* **Hand Trolley** (4.0, one level, $600, only the vans and trucks: `CarDef.trolley`): folded **inside the back doors**
  (seen when they open) on the Attachment `TrolleyMount`; take it out to carry up to 4 pieces at once (server/Cargo.luau).
* Opening the back, picking up, loading, taking out and handing over are instant on E (`Config.Cargo.HoldDuration` 0;
  4.0.1 refunded the old loading upgrade's levels once, 5.7 took out its last code).

* ~~Cargo Rack~~ (3.4, gone in 3.5): the car's **stages** give the room now, each with its own look (see **Stages
  and the cars' roles**). A 3.4 save's cars became the stage that holds the slots they had (see there).

The kit is cosmetic: welded, massless, no collisions, not hit by bullets, a few parts; the stats come from the levels
(`Economy.carStats` with the car's own levels).

New in 4.4, **the fleet models** (Codex, `design/vehicle-models/`): the nine cars you can own, at all 20 stages, have
panelled bodies built from Roblox parts (framed windows, mirrors, grilles, bumpers, steel or alloy wheels, stage gear
such as the Long Cargo Van's roof rack), and the upgrades you buy show on them (bull bar, armour, windshield guard,
intake and exhaust, new tyres, alloys). The skin is massless and never collides or blocks a ray: the old hull, seats,
doors, wheels, cargo points and physics are unchanged (`server/VehicleArt/Geometry.luau` describes the pieces,
`Builder.luau` welds them). The garage shows your car in 3D (`client/VehiclePreview.luau`, parked cars from
`shared/VehiclePreviewData.luau`). Traffic, bandits and company vehicles keep the old bodies.

## Cars, cargo, garages and the repair shop

Version 3.4: a car is something you **earn and keep**. You get the Old Van at the start and you upgrade it; a new car
needs a garage, and a damaged one a mechanic.

**Cargo capacity** (`Config.Cars` capacity = the car body's cargo slots in server/Vehicles.luau `STYLES`, checked by
`tests/run_tests.py`; `Economy.capacity`, `Economy.cargoNeed`; 3.5: the slots of the car's **stage**, see **Stages and
the cars' roles**). Only what you **carry or lead by hand** takes a slot (all of a job's pieces ride at once: every
pick-up comes before the drops); passengers (board) and the ice cream route (serve) take none. The company vehicles
hold what their jobs need: Armored Truck 8, Moving Truck 10, Monster Truck 6, Fuel Truck 6, Ice Cream Truck 6,
Livestock Truck 2 (two stalls), Ambulance 1, School Bus 8 (seats); they have no stages.

* **The job board** (server/Jobs.luau): every offer knows its pieces; one with more than your equipped car holds
  shows **📦 NEEDS N SLOTS** and "NEEDS 4 SLOTS · your Old Van holds 2" (the server refuses it too) and tells you what
  would hold it: "Build it up at Wrench Garage: as a Long Cargo Van it holds 4." or "That needs a bigger vehicle: the Box
  Truck or the Freight Truck (your garage, or Dead End Motors)." (`Economy.roomAdvice`). The ordinary deliveries are 1 – 3 pieces, a ★ one
  never more than 2 (`Config.Jobs.EasyMaxPieces`: the Rusty Van); the dangerous levels sometimes send a **bulk order**
  (`Config.Jobs.BulkChance` / `BulkExtra`: ★★ 20 % +1, ★★★ 45 % +1 – 2, ★★★★ 60 % +3 – 6), more pay per piece, a
  bigger car. A ★ job always fits the Rusty Van, a ★★ one the Work Van (a bulk order the Long Cargo Van).
* **A special job or a mission that lends a vehicle** uses that vehicle's room (the horse missions bring two horses,
  the two stalls of the Livestock Truck).
* **Missions** (server/Missions.luau): one with more pieces than your car holds is refused at START: "This mission
  needs a vehicle with 4 slots (your Old Van holds 3). Build it up at Wrench Garage: as a Long Cargo Van it holds 4." The
  MISSIONS window shows a red **📦 needs N slots** chip and line. 3.5: **First Shift** fits the Rusty Van (2) at level
  1 and the Work Van (3) at level 2; **Code Red** and **Empty Shelves** (and the DUO campaign) need at most the Long
  Cargo Van (4); later a few **big loads** (5 – 8 pieces, and the mission says so: Oil Fire 5, Mess Hall 6, Cooling Water 6,
  Wagon Wheels 6, Heavy Business 5, The Cure 8, Landing Gear 8) need a Tall Hauler or the Box Truck. Every mission
  fits a car (and a stage) you can have by its level. `tests/capacity_test.luau` lists what every one of the 110
  missions needs and from which level a car holds it.

**Garages and slots** (`Config.Estate`, server/Estate.luau, server/Garages.luau). The depot holds only your starting
van (`BaseCarSlots` = **1**); every other car needs a slot of a garage or a home's garage. The first garages come early:

| Garage | Level | Price | Slots | Where |
|---|---|---|---|---|
| **Rented Lockup** | 2 | $2,500 | +1 | south of Downtown, on a street down to the Suburbs (just west of the depot's line) |
| **Southside Garage** | 4 | $12,000 | +2 | south of Downtown, on the street to the Suburbs east of it |
| Harbor Lockup | 5 | $25,000 | +4 | the Harbor |
| Highway Garage | 6 | $45,000 | +4 | the North Highway |
| Downtown Parking | 7 | $70,000 | +6 | Downtown, in the safe zone |

So the Courier Van (level 2) needs the Rented Lockup first. Dead End Motors refuses a car without a free slot: "No
free garage slot. Buy or rent a garage (ESTATE, H) first." (the card says 🅿 NEEDS A GARAGE). A bought car goes into
your garage. The company vehicles the employers give you take no slot. **An older save** with more cars than slots
keeps them all; they wait at the depot lot, and the save cannot buy more until it has room.

**Switching cars** happens **only at a garage**: walk to the **🅿 GARAGE** post at the drive-out spot of a garage you
own (or of your home; only your own show it) and press E, or use the Depot Garage terminal for the depot lot (the
starting van, the company vehicles, an older save's extra cars). The garage window (client/GarageUi.luau) lists your
cars: name, 📦 capacity, 🔧 health, the upgrades, **TAKE OUT** (it closes when you walk out of the garage's range).
The car you drive is parked inside (its damage kept), the chosen one stands at the door (from the driver's seat you
sit in it). Not during a delivery. Anywhere else the dealer says IN GARAGE and the server "Switch cars at one of your
garages". **CAR** still brings your equipped car anywhere (the chauffeur).

**Damage stays** (`profile.carHealth`, saved): every car keeps its share of health when it is parked, called or
respawned; a wrecked car comes back (CAR) at 20 % (`Config.Repair.WreckedHealth`). There are **no free repairs** any
more (the depot yard and Wrench Garage healed before 3.4). The **Repair Kit** (Last Stop Supplies, 40 %) stays the
emergency fix on the road. A company vehicle lent for a job always comes fresh from its employer.

**The repair shops** (server/Repair.luau, `Config.Repair`, `Map.RepairShops`): **Wrench Garage** (two bays straight in
from the wide door) and **Rust Bridge Repairs** (a new workshop on the Harbor block where the Rust Bridge comes over,
two bays, on the map with a wrench). Drive into a bay (yellow lines, BAY 1 · REPAIRS over it), stop and **get out**:
after 1.5 s the mechanics take the car: it is locked on the lift (anchored, the back closed, passengers out) for
**20 – 60 s** by the damage (`Economy.repairTime`), the HUD shows a timer card and the bay's billboard the time
left; then it is as good as new: "Your Old Van is repaired". The fee is paid at the end, **$20 – $300** by the
damage (`Economy.repairFee`; you need the money at the start and still at the end, else the repair is cancelled; damage
the car takes on the lift counts too). Getting back in, calling the car away or switching cars cancels it, nothing to
pay. A job's clock keeps running meanwhile (your choice). Any car can be repaired, a
lent company vehicle too.

## Stages and the cars' roles

Version 3.5 (`Config.Cars` stages and role, `Economy.stageOf` / `stageCapacity` / `carTitle` / `roomAdvice`,
server/Vehicles.luau `LOOKS` and `styleFor`, server/Shops.luau `buyStage`).

You keep your first van and **build it up**; you buy another car for what it is good at, not because it is "the next
van". Every car you can buy has **stages** (stage 0 is the car as sold), bought one after the other at **Wrench
Garage** for the car you drive: the UPGRADES tab shows a **STAGE card** with the next stage's name, its price, its
level lock, what it adds and **before → after** (📦 slots, health, speed). A stage is kept with the car
(`profile.carUpgrades[carId].stage`) and **changes its look**: the mechanics rebuild the car where it stands (not
during a delivery, not on a repair lift). The upgrades (Engine, Tyres & Suspension, Armor, Ram Plow, the
Hand Trolley) stay as they were and their UpgradeKit (tyres, bull bar, plates, scoop, the trolley) fits every stage; the paint covers the new body panels too (a high
roof, a roof pod); the car gun moves up onto a high roof.

| Car | Role | Stages: name · 📦 slots · price · level |
|---|---|---|
| **Old Van** (free) | your first van: it grows with you | 4.0: **Rusty Van** 2 (max 42, accel 11: big corroded rust patches, a primer-grey driver's door, a dented crooked bumper, a cracked windscreen, bald grey tyres, a yellowed dim headlight, a smoking exhaust) → **Patched Van** 2 · $250 · 1 (the rust ground off and primed grey, a straight new bumper; 48 / 15, +20 health) → **Work Van** 3 · $700 · 2 (**1.5 studs longer**; clean paint, a chrome bumper, a new windscreen and lamps, new tyres, a rear step, a ladder, shelves; 54 / 19, +40 health) → **Long Cargo Van** 4 · $2,200 · 4 (**3.5 studs longer** with a high roof, a roof rack, a light bar, mud flaps; 56 / 21, +70 health) |
| **Courier Van** (2, $3,500) | fast and nimble: the rush jobs | Courier Van 2 → **Express Courier** 3 · $1,200 · 3 (a roof pod, a checker stripe; +2 speed) |
| **High-Roof Van** (3, $7,000) | tougher, the in-between | High-Roof Van 4 → **Tall Hauler** 5 · $3,000 · 5 (a ladder rack with a spare wheel, side steps, a stacked shelf; +60 health) |
| **Pickup** (4, $12,000) | the crew car: two friends shoot from the bed | Pickup 2 → **Ranch Pickup** 3 · $2,500 · 6 (a roll bar with spotlights, chrome bed rails; +50 health) |
| **Box Truck** (6, $22,000) | the big one: the only way to 6 and more | Box Truck 6 → **Liftgate Truck** 7 · $7,500 · 8 (a liftgate, marker lights, a chrome bumper; +80 health) → **Freight Hauler** 8 · $15,000 · 10 (4.0: **a box 3 studs longer**, four rows on the floor, **takes a pallet**; a tall wind deflector, side skirts; +150 health, −2 speed) |
| **Muscle Car** (8, $40,000) | the getaway car: one piece, all speed | Muscle Car 1 → **Street Machine** 2 · $6,000 · 9 (a blower through the hood, side pipes; +3 speed) |
| **Freight Truck** (9, $45,000, 4.0) | warehouse freight: pallets and 12 slots | Freight Truck 12 slots or **3 pallets** (one stage) |
| **Armored Van** (10, $55,000) | very tough: the car-gun platform | Armored Van 3 → **Fortress Van** 4 · $14,000 · 11 (a gun shield round the roof gun, side lockers, a spare wheel; +200 health, −2 speed) |
| **Rally Van** (12, $80,000) | the fastest van (98): rush jobs | Rally Van 2 → **Works Rally** 2 · $10,000 · 13 (a light pod, a roof scoop, mud flaps; +3 speed, cosmetic: no more room) |
| the company vehicles | lent for their jobs | no stages, their own fixed room |

* **4 is where a van ends**: the Old Van, the Courier Van, the Pickup and the Armored Van stop at 3 – 4, the High-Roof
  Van at 5; only the **Box Truck** carries 6 – 8 and (4.0) the **Freight Truck** 12. `tests/capacity_test.luau` checks it.
* **The looks** (server/Vehicles.luau `LOOKS`, built by `styleFor` on top of the car's `STYLES` body and cached): a look
  `drop`s boxes and trim by tag (the Rusty Van's `rust`, `primer`, `crack` and loose `bumper`; the Box Truck's `bumper`
  and `deflector`), 4.0: may `stretch` the body (see **Freight vehicles and the upgrades you see**) and be `fresh` (the
  Rusty Van's faults fixed), adds solid `boxes` (a "body" box is painted like the body) and cosmetic `trim` (no collisions, not hit
  by rays), has its own cargo **slots** (exactly as many as the stage holds: `tests/run_tests.py` counts them, so the
  loading through the back always has a place for every piece) and maybe a new `roof` height for the gun. Stage 0 is
  the plain body. A few dozen small parts at most.
* **The traffic** drives the vans at random stages (rusty, patched, work, long cargo vans …); bandit cars and the
  showroom are built the same way. It never drives the Freight Truck.
* **Older saves**: every car a 3.4 save owns becomes the first stage that holds the slots it had in 3.4 (its 3.4
  capacity plus its Cargo Rack; `Economy.legacyStage`), once, when the save loads (the save's `carStages` marks it
  done), whatever your level: the Old Van (4 in 3.4) the **Long Cargo Van** (4.0), the Muscle Car the Street Machine, the Armored
  Van the Fortress Van, the Box Truck with a rack of 1 the Liftgate Truck, of 2 – 3 the Freight Hauler. Where no stage
  holds that much, the car gets the first stage with its most room, and **holds less than in 3.4**: the Old Van with
  a rack 4 (was 5 – 7), the Courier Van and the Pickup 3 (were 4+), the High-Roof Van 5 (was 6+), the Box Truck with
  rack 3 8 (was 9), the Rally Van 2 (was 4+: its only stage adds no room, so it stays at stage 0), the Armored Van and
  the Muscle Car with a rack 4 and 2. That is the 3.5 rule (4 is where a van ends); the bigger loads need the Box Truck.
* **4.0 saves**: a 3.5 – 3.10 save's Old Van keeps its room on the new stages, once (`Economy.migrateStage40`; the save's
  `vanStages` marks it done): its Work Van (old stage 1, 3 slots) is the **Work Van** (stage 2), its Cargo Van (old
  stage 2, 4 slots) the **Long Cargo Van** (stage 3); a Rusty Van stays the Rusty Van. A 3.4 save goes straight onto
  the new stages (`legacyStage`).
* **Admin** (P): UNLOCK EVERYTHING and MAX UPGRADES + STAGES put every car you own at its last stage too.

**Dead End Motors** (server/World.luau `buildDealer`, server/Shops.luau): no more lot with every car lined up by the
street. You buy from the **car catalog** at the sales counter (the dealer window: every car's card with its role and
📦 from → to its last stage, 4.0: the pallets it takes, BUY, 🔒 LEVEL, 🅿 NEEDS A GARAGE; the catalog's note: "more
room makes the body longer … more needs the High-Roof Van, the Box Truck or the Freight Truck (pallets)"); inside, three
display cars stand well apart on turntables, turned a little toward the door: the Old Van as a **Long Cargo Van** (what
your van becomes, "BUILD YOURS AT
WRENCH GARAGE"), the **Box Truck** and the **Rally Van**; their "Look" prompt opens the catalog on that car. A bought
car waits in your garage as before (take it out at a 🅿 GARAGE post); every car beyond the starting van needs a slot.

## Freight vehicles and the upgrades you see

Version 4.0, **Freight** (the vehicles: `Config.Cars`, `Config.Upgrades`, `shared/Economy.luau`, server/Vehicles.luau,
client/Drive.luau, client/CarVisuals.luau; the warehouse, the trolley and the pallet jack in use: server/Cargo.luau).

**A slow start.** The Old Van starts as a heavy, tired **Rusty Van**: top speed 42, accel 11, about **3.6 s** to its top
speed. Pulling away follows a **torque curve** (`Economy.torque`, client/Drive.luau): 55 % of its accel from a
standstill, 135 % in the mid-range, a soft creep to the top (40 % there); the speed always changes smoothly. Every
stage adds speed and acceleration (`StageDef.speed`, `StageDef.accel`): Patched Van 48 / 15 (3.0 s), Work Van 54 / 19
(2.7 s), Long Cargo Van 56 / 21 (2.5 s); the **Engine** (+8 % speed and accel a level) is the other way up.
`Economy.timeToTop` gives the seconds; `tests/vehicles40_test.luau` checks them.

**A real rusty van.** The Rusty Van has big orange-brown corroded patches (CorrodedMetal: the sills, the arches, the
hood, the roof), a **primer-grey driver's door** from another van, a dented **crooked bumper**, a **cracked
windscreen** (thin dark lines from a stone chip), **bald grey tyres**, a **yellowed dim headlight** (a weak yellow beam
at night) and a little **exhaust smoke** at idle (`Smoky` attribute; client/CarVisuals.luau puffs it at the
Attachment `Exhaust`, more standing than moving, only near the camera). The Patched Van grinds the rust off and primes
it grey and gets a straight bumper; the Work Van is clean (`Look.fresh`: new windscreen, lamps, tyres, no smoke).

**More room makes the car bigger.** A stage's look can **stretch** the body (`Look.stretch`, `stretchStyle`): the
style's boxes behind its `split` (the middle of the cargo box) move back, the long boxes across it get longer, and the
rear axle, the back doors, the rear lights, the cargo slots, the CargoDoor and back prompt, the TrolleyMount and the
seats and doors behind the split move with them; the whole car then moves forward by half the stretch, so the chassis
(and its wheel colliders) stays centred and both axles move out. The Work Van is **1.5 studs** longer, the Long Cargo
Van **3.5** (and a high roof), the Box Truck's Freight Hauler **3** (and takes a pallet). A stretched look is a style of
its own, cached per look, so its doors (3.10 boarding) are cached with it.

**The Freight Truck** (`"freight"`, style `"freighttruck"`, level 9, $45,000 at Dead End Motors): a cab-over truck,
9 wide, 30 long, 12 high, a long box with its **loading floor at dock height** (about 3.4 studs over the ground), **12
slots** in three 2 × 2 **pallet bays** front to back, or **3 pallets** (`CarDef.pallets`), a **roll-up door**, twin
rear tyres (6 wheels, `Style.dual`), side skirts, a fuel tank, an exhaust stack, marker lights. Slow and heavy (max 45,
accel 12, turn 1.2, health 900, ram × 2), **no car gun**, one passenger. Its own **pallet jack** stands inside at the
back (the Attachment `JackMount`; server/Cargo.luau builds it). The traffic never drives it. At a garage it comes out
further from the door (`Vehicles.placeAt`: the back a stud clear of the wall).

**The contract** (Config, Economy):

* `CarDef.pallets` / `StageDef.pallets` (the stage's wins), `Economy.palletsOf(carId, stage)`: the Freight Truck 3, the
  Box Truck 1 at its last stage, the Moving Truck 1. A pallet fills `Config.Cargo.PalletSlots` (4) slots: a car's
  first slots are a 2 × 2 group at the front of its box.
* `CarDef.trolley`: the Old Van, the Courier Van, the High-Roof Van, the Box Truck and the Freight Truck may buy the
  **Hand Trolley** (`Economy.upgradeFits`, `Economy.hasTrolley`; Wrench Garage refuses it for the others, the card says
  VANS & TRUCKS). With it the car has the Attachment `TrolleyMount` inside the back and the folded trolley there (the
  model `FoldedTrolley` in the UpgradeKit).

**You see the upgrades** (the UpgradeKit, rebuilt when a level changes): Tyres & Suspension's new tyres and tread
rings (1), alloy rims (3) and lower stance (5); the Engine's end of the smoke (1), scoop and pipes (3); the Armor's
plates and grilles; the Ram Plow's bull bar; the folded Hand Trolley in the back.

## Challenges, secrets and rewards

Version 3.1 (`shared/Challenges.luau`, `server/Challenges.luau`, `Config.Rewards`). Everything is saved, and every
reward is given **once** (the save marks it given).

**Campaign rewards.** Finishing a chapter (6.8: its six missions, the finale last) still pays its money (see **Missions**), and now also
gives a **title** and an **exclusive gun or paint** (`Config.Rewards.Campaigns`). Campaigns finished before 3.1 give
theirs on the next join.

| Campaign | Exclusive reward | Title |
|---|---|---|
| 📦 First Shift | Dispatch Yellow paint (metal) | Dispatcher's Favourite |
| 🏥 Code Red | Medic Mint paint | Field Medic |
| 🛒 Empty Shelves | Fresh Lime paint | Grocery Hero |
| 🚒 Smoke and Sirens | Fire Engine paint (metal) | Smoke Eater |
| 🪖 Iron Supply | **Maria's Carbine** (gun) | Quartermaster |
| ⚡ Lights Out | Volt Neon paint (neon) | Live Wire |
| 🐴 Wild West End | **Walt's Lever Rifle** (gun, a round hits 2 in a row) | Outlaw Tamer |
| 🧪 Patient Zero | Toxic Glow paint (neon) | Cure Runner |
| 💰 Dirty Money | **Vinnie's Golden Pistol** (gun, one-handed) | Made Man |
| 🚌 Last Convoy | Sunrise Chrome paint (foil) | Last Convoy Captain |
| 🤝 Partners in Crime (3.2) | Tandem Twin paint (metal) | Partners in Crime |

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
| 🎯 Missions | On the Clock (5 missions · $500), Story Time (1 campaign · $1,000), Night Shift (15 at night · $2,000), Hold the Line (10 HOLD OUT won · $2,000), Wave Rider (100 waves · $2,000), Trusted Courier (25 missions · $2,500), Flawless (25 at 3 stars · $2,500), Star Collector (100 stars · $3,000), Top of the Ladder (level 15 · $10,000), Legendary Courier (all 60 story missions · $15,000 · Legendary Courier), Saviour of the City (all 10 story chapters · $20,000), Three-Star General (all 180 story stars · $20,000 · Three-Star General; 6.8: the "all" ones count the story, not the DUO chapter); hidden: Ghost Courier (a NO SHOOTING mission without a shot · $2,000 · The Ghost), Horse Whisperer (25 horses · $2,500 · Horse Whisperer), Against the Clock (10 timed missions · $3,000) |
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
* **REWARDS**: the eleven campaign rewards (earned, or "finish <campaign>"; a click opens the campaign), your titles with
  EQUIP, and the exclusive guns and paints.
* The MISSIONS tab's campaign header shows the campaign's reward too ("Reward: Maria's Carbine + title Quartermaster").
* **Popups** at the top centre, one at a time: a strip for a new place, a card for a package or a challenge (its money
  and title), and a BIG card with a glow and confetti for a campaign's, every package's and every challenge's
  reward. They wait while the DELIVERY result, the mission's celebration card or the MISSIONS window is up, so
  nothing covers them; a flood (many at once) merges into one card per kind. A click dismisses one.

## Real estate and your company

Press **H** (or **ESTATE**) for the list of every property (filters ALL / HOMES / GARAGES / OFFICES / OWNED): price,
driver level, car slots or couriers, who owns it on this server, GPS. Each property has a **FOR SALE** sign in front
(E opens its listing; the board shows OWNED and the owners' names once somebody on the server has it). You **buy at
the property** (within reach of its sign or on its lot; away from it the BUY button turns into GO THERE TO BUY and
sets the GPS) with the money you made, if your driver level is high enough (3.2: the real estate is the endgame, and
the offices also need a campaign finished: `EstateDef.requires`, checked in `Estate.buy`, shown in the list and on
the plates as "Finish Iron Supply first"; 3.4: the two small garages come at levels 2 and 4). Every player owns their own copy: two
owners of the same mansion both use it. Everything you own is saved.

| Property | Kind | Where | Price | Level | Car slots / couriers |
|---|---|---|---|---|---|
| Hilltop Mansion | mansion | the top of **Sunset Hills** (north-east of Downtown, up the winding Sunset Drive) | $6,000,000 | 15 | 8 cars |
| Ocean View Mansion | mansion | on the sea cliffs north of the Harbor, up Cliff Road (a private pier) | $4,500,000 | 14 | 8 cars |
| Pinecrest Mansion | mansion | in the pines south of the West Highway, down Pine Lane | $3,000,000 | 13 | 6 cars |
| Lakeside Villa | villa | far north by the frozen lake, on the Lodge Road (a jetty onto the ice) | $1,500,000 | 11 | 4 cars |
| Sunset Villa | villa | in the west, at the end of Sunset Lane off the Radio Road | $1,000,000 | 10 | 4 cars |
| 12 Maple Street | house | a Suburbs lot | $300,000 | 9 | 2 cars |
| 7 Oak Lane | house | a Suburbs lot | $220,000 | 8 | 2 cars |
| Birch Cottage | house | the west edge of the Suburbs, at the end of Birch Lane | $150,000 | 7 | 2 cars |
| Elm Bungalow | house | a Suburbs lot | $90,000 | 6 | 1 car |
| Rented Lockup (3.4) | garage | south of Downtown, on the way to the Suburbs | $2,500 | 2 | 1 car |
| Southside Garage (3.4) | garage | south of Downtown, on the way to the Suburbs | $12,000 | 4 | 2 cars |
| Harbor Lockup | garage | the Harbor | $25,000 | 5 | 4 cars |
| Highway Garage | garage | on the North Highway | $45,000 | 6 | 4 cars |
| Downtown Parking | garage | Downtown, in the safe zone | $70,000 | 7 | 6 cars |
| Harbor Point Office | office | **Harbor Point** tower (the Harbor, by the docks), 7th floor | $500,000 | 12 + Iron Supply | 3 couriers |
| Dispatch Tower, 8th floor | office | **Dispatch Tower** (Downtown, by the depot), 8th floor | $900,000 | 14 + Dirty Money | 6 couriers |
| Dispatch Tower Penthouse | office | Dispatch Tower, the top (14th) floor | $2,500,000 | 15 + Last Convoy | 12 couriers |

* **Homes** (mansions, villas, houses) are furnished, two storeys for the big ones. Your first home becomes **your
  home** at once; SET AS HOME picks another one, SPAWN AT THE DEPOT none. You spawn at your home after PLAY and after
  every death, and the car you get then waits in front of its garage.
* **Car slots**: you can own `Config.Estate.BaseCarSlots` = **1** car without any property (3.4: the starting van,
  on the depot lot); every home and garage adds its garage's slots. Buying a car at Dead End Motors needs a free slot
  (the dealer tells you to buy or rent a garage otherwise). Company vehicles earned by working do not count, and cars
  you already own are never taken away. 3.4: you switch cars at your garages (see **Cars, cargo, garages and the
  repair shop**).
* **Selling** (SELL, click twice to confirm) pays back **60 %** of the price (`Config.Estate.SellBack`). The home you
  spawn at cannot be sold until you set another home or the depot.
* **Offices** are in the two towers: **Dispatch Tower** (14 floors, Downtown, next to the depot) and **Harbor Point**
  (12 floors, the Harbor). Each has a lobby with a receptionist and the office directory (FOR SALE signs of its
  offices), glass office floors and a roof terrace with a helipad. The floors are joined by **elevator pads**: step on
  the pad under a floor sign and you ride to that floor.

**Your delivery company.** Owning an office starts it; the office with the most courier seats runs it. Use the
**computer** on your office desk (E, "Run your company"; you must stand at it):

* **Couriers**: HIRE costs $40,000 each (`Config.Business.CourierCost`), up to the office's seats (3, 6 or 12); FIRE
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

New in 3.4: the **Rented Lockup** and the **Southside Garage** south of Downtown on the streets down to the Suburbs,
**Rust Bridge Repairs** (a repair shop on the Harbor block where the Rust Bridge comes over) and the repair bays in
Wrench Garage; a 🅿 GARAGE post at every home's and garage's drive-out spot (only your own show it).

**Traffic and pedestrians.** Civilian cars drive the roads around every player (on the right, slowing for the turns,
a random road at every junction; none in the winter, on the ice road or in the tunnel) and people walk the city's
sidewalks and cross the streets (fewer at night; they run from zombies). The cars stop for anything in their lane
(your car, a bandit, somebody on foot) and turn around after a while behind something that stays. Ram one at speed
and it is a smoking wreck, towed away later. They appear out of sight and vanish far away, with caps per player and
per server (`Config.Traffic`); during a job a bandit pickup can hide among them.

New in 3.9, **living streets**: more people (13 around a player by day, 48 on a server), many of them standing in
groups of two to four by the shops and on the corners, talking (they turn to whoever speaks, nod, say a line in a
bubble) until they break up and walk off; walkers stop at a shop window or for a word with somebody they pass. People
cross a street only over the **crosswalks** painted next to the junctions, and at the districts' four-way junctions
**traffic lights** run one cycle (12 s green, 3 s amber, 1 s all red per way): the traffic cars stop at the line on red
(and on amber when they can), the people cross on their walk phase. Every client colours the lights itself from the
server's clock (`shared/Crossings.luau`); the chauffeur of a called car stops too, your own car and the bandits do not have to.

New in 4.1, **the cinematic looks**: every building with a facade wears the same restrained, wet-city style as Codex's
six approved locations (`design/location-looks/`): concrete, charcoal metal, brick and glazing, fascias and canopies,
window reveals with caps and sills, pilasters, roof extracts, a narrow red accent line, small wayfinding plates and warm
practical lamps that glow at night. Each building is a pure-data blueprint in `src/server/BuildingLooks/<Name>.luau`
that `BuildingLooks/Kit.luau` renders as anchored decoration (no collision, no ray hits), so doors, prompts, cargo
spots, signs and car paths are unchanged. Forty buildings have one: the depot, the shops, the employers (School,
Frosty's, Movers, Clinic, Gas Station, Bank, Pharmacy, FreshMart), the city (Fire Station, Precinct 13, City Hall), the
garages, the repair shop, Downtown Parking, the Dispatch Tower and Harbor Point, and out of town the Fuel Depot, Power
Plant, Water Works, Train Yard, Radio Station, Ski Lodge, Riding School, Ranch, Farm, Military Base, Airfield, Biotech
Lab, Prison, Lighthouse and Stadium. `tools/check-building-looks.py` keeps every blueprint inside its footprint, off the
door openings (`Blueprint.entries`) and the name boards, under 80 parts and 2 light beams.

New in 4.3: **the name boards** are no longer pictures floating over the roofs. Every building's name (the shops, the
employers, the places, the garages, the houses' badges, the road signs to them) is a solid charcoal band on the facade
in the contract look of the UI: a small red square, the name in white caps, a second line where the name has one
(LEAD & CO. over GUNS), a fine line along the bottom (`sign()` in `server/World.luau`; the sign pictures stay in
`art/signs`). **The open halls are lit** day and night (`Blueprint.interior` in `BuildingLooks/Kit.luau`: warm ceiling
panels with a downward light in the depot, the Harbor Warehouse, Fire Station 9, the hangar, the barns and stables and
the four garages), and the shops' own ceiling light is brighter. **The location tag**: walk (or drive slowly) up to a
place you have discovered and a quiet caption names it on the left over the minimap, in the style of the location
previews: ■ LEAD & CO. over GUN SHOP (`client/LocationTag.luau`, the choice in `shared/LocationTags.luau`: within 45
studs, 75 for a shop, gone past 70 / 100 or after 4.5 s, each place once per 90 s, never over the NEW LOCATION banner or
an open window).

## The HUD

3.8, **the contract UI** (Codex's `design/ui-contract/`, approved by the owner): the world is the main view, the
interface is compact white type over a subtle charcoal scrim, fine grey lines and small red accents (`Theme.Contract`
in `client/Theme.luau`; `client/HudContract.luau` holds the HUD's pieces). It replaces the 3.6 look described below;
what each part shows is the same.

6.5, **a clean screen and one clear goal** (the owner: "When I join I don't know what to do. I can't find my way in
anything. The UI is a terrible mess."): every thing shows once. The **NEXT card** (`client/Objective.luau`, its words
from `shared/Goal.luau`, tested by `tests/goal_test.luau`) is always the first thing at the upper left: "▶ NEXT", what
to do now in big type ("Pick up 2 pizzas", "Deliver to Sarah", "Hand it over (E), or hold X to throw", the server's
own step at the stop, "HOLD OUT 0:23", Marge's hint on her first day, "Delivered! +$45 · Press J for the next job"),
the place and the live distance, and with a job ▼ DETAILS (a click unfolds the contract group under it). Off duty it
says "Take a delivery job · Press J · or the job board" and a click opens the board. In the world the beam is taller
and brighter and the waypoint one pin "TONY'S PIZZA · 120 m"; with no job the pin stands on the depot's job board
("JOB BOARD · 25 m"). The pill at the lower centre shows only what you can press right now ("E  Pick up pizza").
Gone: CREW from the top row (K, and the MENU list), the weapon line (the bottom bar's hand slots), the vehicle line,
INVENTORY [I] (I still works), "J FOR THE BOARD" / "Q → GARAGE" and the other hint texts, the contract's bag chip
(the bottom bar shows the bag). The numbers are in `Config.Goal`.

| Where | What |
|---|---|
| Upper left | 6.5: the NEXT card (above); under it, folded, ■ DELIVERY CONTRACT (type, stars, stop), the destination in caps, the objectives as checkboxes, a rule, the time left (red under 30 s) / EST. pay; the tutorial's strip, the crew strip and the toasts sit under it |
| Upper right | 6.5: MAP [M] · PHONE [Q] (MENU before Marge's phone: every other action, JOBS, MISSIONS, CAREER, CREW, BAG, CAR, TOP, ESTATE, SOUND, GIVE UP), a red dot for news; under them the small "? KEYS [F1]" |
| Lower left | money / level and rank (XP on hover), the minimap (thin frame, the job's route in red, the GPS in white, the fog), health |
| Lower right | 6.5: the speed and the fuel while you drive, the PHONE action over it; a touch screen keeps the weapon line too (its tap opens the weapon wheel) |
| Bottom centre | 6.0.1, the bottom bar (`client/Hotbar.luau`): 6.1: three hand slots first (✊ fists 1, 🛍 the bag 2 with its fill, 🔫 the gun 3 with its name; the one you hold outlined red) and a divider, then five square item slots (the consumables you own in their order, the count, keys 4-8; a click or a tap uses one, a flash and the cooldown shade), a thin divider and what you carry (a tile a piece with ✋ / 🛍 / 🎒 / 🚲 for where it is, grey for another order, your free room dim, "+N" over 8; a click opens the BAG tab). Touch: the tiles over the slots (48 px or more; 6.1: the hands and two item slots). It hides while a window, the phone or a dialog is open |
| Lower centre | 6.5: the action pill, only while you can press something: a key box, the action, a short instruction and the hold line; the breath bar just over it (both over the bottom bar) |
| In the world | 6.5: the beam and one pin with the place and the distance ("TONY'S PIZZA · 120 m"); with no job on the depot's job board |

Every window is a charcoal rectangle (a small caps label, the title, a thin line, slim rows, one main action with a red
rule); the job board reads like a delivery briefing (route, cargo, deadline, risk, payout, the lock and its remedy).

3.6, **Postage & Trouble**: the interface follows **Codex's concept** (`design/ui-concept/`: `index.html` and the
`previews/`): soft courier colours, light cream paper and powder-lavender surfaces with dark plum ink, pastels only on
surfaces (never for the important words), shipping-ticket shapes and buttons that lift under the mouse and sink when
pressed. Every colour is a token in `client/Theme.luau` (`Theme.Postage`: paper, ticket, lavender, the two inks, sage
for the main action, violet for the crew and the GPS, good / warn / danger, the bar track, the cream pill behind
words over the world); the old names (`Theme.Colors`) are now inks that read on paper, and `Theme.soft` gives each its
pastel face. Everything is laid out from the screen size, so nothing overlaps on a PC or a phone:

* **The objective ticket** (top centre): a slightly tilted paper delivery ticket. Small caps say the stage
  (DELIVERY IN PROGRESS, PICKUP · STEP 1 OF 3, the danger stars, a modifier), the stop is big, a pin line gives the job,
  the stop and the distance, and under it the cargo slots (loaded / your car's) and the estimated pay, plus what went
  wrong (cargo condition, pieces lost, a wave). The timer sits in the perforated stub on the right and turns red in the
  last seconds. With no job and nothing else on top a small **OFF DUTY** ticket opens the Dispatch board. The same
  stack, under the ticket, holds the crew strip (a member sees the leader's job), the mission banner, the car call
  line, the repair timer, the level-up banner and the toasts: only what matters right now shows.
* **The money and rank card** (bottom left; top left on touch, clear of the thumbstick): the level in a lavender
  circle, the money big over AVAILABLE CASH, the rank and a thin XP bar (the XP numbers on hover, or a tap).
* **The minimap** under it, in a paper frame: the map itself is paper too (cream land, pastel blocks and water, white
  streets on a plum edge, butter highways) with the routes and markers vivid on an ink edge. Over its top edge the way
  you face and where you are ("N · HARBOR") and an EXPAND M chip; under it the **turn line**: the next turn of the
  route ("↰ Left onto Maple St · 120 m"; with no route, the address you are at).
* **Health** under the minimap: a heart, a thin bar (violet, red when low) and the number, on a cream pill.
* **The speed dial** (bottom right): a round cream instrument with ticks and a violet needle, the car's name (its
  stage's), the speed big over KM/H, the **vehicle condition** (a bar and the %, amber then red as it drops) and the
  **cargo pips** (one per slot, the loaded ones filled, "3 / 4 cargo slots"). On foot it dims and keeps the parked car's
  condition; without a car it says how to get one.
* **The weapon label** on top of the dial: the gun in your hands (or the car gun while you drive a car that has one),
  WINDOW READY when it fires from a car seat, the key T (hold T: the weapon wheel). Click it for the next gun.
* **The consumable tags** (bottom centre): repair, medkit, nitro, molotov, mine as tilted pastel tags with their key
  (1 – 5) and how many you have; under the mouse a tag lifts, straightens, grows and shows its name. The **hint** over
  them is a cream pill: what to do right now ("Get out and open the back (E)").
* **The utilities** (on a computer over the weapon label, clear of Roblox's player list; on touch top right): **MAP**
  (M), **CREW** (K) and a round **…** that opens the menu with every other action and its key: **JOBS** (J),
  **MISSIONS** (U), **BAG** (I; B before 3.9), **CAR** (calls your car; it counts down while the car is on the way), **TOP** (L),
  **ESTATE** (H), **SOUND** (N) and, while a job runs, **GIVE UP** (press it twice). A computer shows a button's name
  and key on hover; a touch screen keeps the names under the buttons. The ADMIN button (admins only) keeps its corner.
* **The Dispatch board** (J, JOBS, the depot counter, NEXT JOB; `client/DispatchUi.luau`): the job board as a lavender
  window of die-cut delivery tickets. On the left the filters (All jobs / Deliveries / Special jobs, with counts) and a
  card for your car (its cargo slots and condition: your vehicle sets your job capacity). Every ticket has a numbered
  icon spine, the danger and the twists as chips (the modifier, SPECIAL, RUSH CLOCK, BANDITS), the title, the route,
  the stops, the distance, the cargo slots and the time, and a payout stub with **ACCEPT JOB →** (NIGHT × 1.4 while
  night pay is up). Hover lifts a ticket. A locked ticket is hatched and says why and what to do: **🔒 LEVEL N** (the
  level and rank you need) or **📦 NEEDS N SLOTS** (what your car holds, and the next stage at Wrench Garage or a
  bigger car from your garage). On a delivery the board shows that job and GIVE UP THIS DELIVERY. ↻ NEW OFFERS asks
  for fresh ones; the server checks every offer again.
* **The window style** (`Ui.window`, every window: the shops, the backpack, the employers, the delivery result, the
  Dispatch board, Missions, the garage, the crew, real estate, the company, the leaderboard, the admin panel): a
  lavender surface with a soft offset shadow; a header with an icon in a sage circle, the title, a subtitle and a round
  ✕ that turns on hover; a dashed line under the header; a footer with ESC · Close window and the window's context on
  the right. The rows are paper tickets, the main action is sage (`Ui.button`, with a lip that sinks when pressed), a
  locked one quiet lavender with the reason on it. One window at a time; ESC (or the gamepad's B) closes it.
* **Over the 3D world** the words sit on a cream pill in ink, so they read over a night street and a sunny one: the
  delivery label over the target (lined in the route's colour), the YOUR CAR marker of a car call, the owner's name over
  other players' cars and the crew tags. The crosshair dot and the hit numbers keep their outline.

On touch FIRE sits over the jump button; 4.2: SPRINT, the hand button (PUNCH / STRIKE, EXIT in a seat, PUT DOWN /
LET GO / SET DOWN while you carry or push) and DRAW / HOLSTER stand in a column left of them, every one 44 px or more,
and the right column goes left of them (on a narrow phone or upright, over them). `client/TouchLayout.luau` places
them and `tests/touchlayout_test.luau` checks phones and tablets for overlaps.

The big map (M, or EXPAND) lists every shop, employer and far place with what you can do there: click one to set
the **GPS**. The route there is drawn along the roads on both maps (yellow to the job's next stop, purple to the GPS
point), with a red marker over the stop and a light beam. Big icons over the buildings show them in the world.

## Content

* **Cars**: at Dead End Motors (3.5: the car catalog at the counter, three display cars inside) the Old Van (free), the Courier Van
  (level 2, $3,500), the High-Roof Van (3, $7,000), the Pickup (4, $12,000), the Box Truck (6, $22,000), the Muscle Car
  (8, $40,000), the Freight Truck (9, $45,000, 4.0), the Armored Van (10, $55,000) and the Rally Van (12, $80,000),
  each with 1 – 3 stages (3.5; 4.0: the Old Van's Patched, Work and Long Cargo Van); earned by
  working: School Bus, Armored Truck, Ice Cream Truck, Moving Truck, Monster Truck, Livestock Truck, Fuel Truck,
  Ambulance.
* **Guns** (Lead & Co.): Pistol (free), SMG, Shotgun, Hunting Rifle, Minigun, Grenade Launcher, each with its own model in
  your hand (`shared/GunModels.luau`, the bandits carry the same pistol and rifle): a muzzle flash and a recoil kick on
  every shot, the tracers start at the muzzle. A headshot kills. Earned by working, not sold: the **Ranch Revolver**
  (Silver Spur Ranch) and the **Army Carbine** (Military Base). One-handed (they also fire out of a car window):
  Pistol, Ranch Revolver, SMG, Vinnie's Golden Pistol.
* **Exclusive gear** (3.1, `exclusive` in `Config.Weapons` / `Config.Paints`, never sold; see **Challenges, secrets
  and rewards**): the guns **Maria's Carbine** (an olive carbine with a scope), **Walt's Lever Rifle** (wood, a round
  hits 2 in a row), **Vinnie's Golden Pistol** and **Dead End** (a round hits 4 in a row), each with its own model; the paints
  Dispatch Yellow, Medic Mint, Fresh Lime, Fire Engine, Volt Neon, Toxic Glow, Sunrise Chrome and Phantom, some with
  a **finish** (metal, neon, foil, glass) on the body panels (`PaintDef.material`). The shops show them as dimmed
  **REWARD** cards with how to earn them ("REWARD · finish Iron Supply", "REWARD · find every lost package", "??? · a
  secret reward" for Dead End, its stats hidden); once yours they show normally with a ★ EXCLUSIVE badge and are
  equipped and painted like any other.
* **Car guns** (Wrench Garage, on the roof of the equipped car, one per car; a new one replaces the old one, no
  refund): Roof Machine Gun (a slim barrel with an ammo box), Roof Minigun (a rotary barrel cluster), Roof Grenade
  Launcher (a fat tube). The Gun Damage and Fire Rate upgrades work for them too.
* **Upgrades** (Wrench Garage): for the equipped car (3.3: each car its own) Engine, Tyres & Suspension (4.0), Armor,
  Ram Plow (5 levels), the Hand Trolley (4.0, vans and trucks; 4.6: gear) and
  the car's **STAGE** (3.5), the visible ones on the
  car; for all your guns Gun Damage, Fire Rate (5 levels); paint jobs; car guns. Repairs (3.4): the repair bays of
  Wrench Garage and Rust Bridge Repairs.
* **Items** (Last Stop Supplies): Repair Kit (the emergency fix on the road), Medkit, Nitro, Molotov, Landmine.
* **Enemies**: Walker, Runner, Brute (zombies, around you all the time, in waves during a job); Bandit, Gunner,
  Soldier (people: only during a job).
* **People**: the employers, givers, receivers and kids are R15 NPCs that talk, turn to you and walk; the ranch's
  **horses** graze, walk on a rope and ride in the livestock truck's stalls; your **chauffeur** brings your car.
* **Real estate** (`Config.Estate`): 3 mansions, 2 villas, 4 houses, 5 garages (3.4: + the Rented Lockup and the
  Southside Garage), 3 offices. **Your company**
  (`Config.Business`): couriers, 3 upgrades, the safe.
* **Missions** (`shared/Missions.luau`, 3.0; 3.2: + the DUO campaign; 6.8: story chapters): 11 clients × 6 missions,
  10 twists, 32 co-op missions, 15 new places, the story's people in `shared/Cast.luau`;
  new cargo (water, generators, batteries, TNT, documents, electronics, weapons, paintings, mail, tyres, plants) and
  survivors who walk aboard by themselves.
* **Challenges, secrets, rewards** (3.1): 42 challenges (`shared/Challenges.luau`), 30 lost packages (`Map.Secrets`),
  11 campaign rewards (3.2: the DUO one), the Phantom and Dead End rewards, 11 + 13 titles (`Config.Rewards`).

All numbers are in `src/shared/Config.luau`, the world layout in `src/shared/Map.luau`, the formulas in
`src/shared/Economy.luau`.

## From the bottom: on foot, your kit, the phone, Earl's van (5.0)

**Everybody starts again** (the DataStore is `ZombieDelivery_v2`; the old saves stay stored, unread). A new courier has
no vehicle, $40 and a pistol. Marge welcomes you, gives you **the phone** (Q since 5.4.1, or the PHONE button: ORDERS, BOARD,
CAREER, SHOP, MAP, MESSAGES; `client/Phone.luau`) and the first delivery **on foot**: two letter bundles on one street.

**On foot** (`Config.Jobs.Foot`, `offer.mode = "foot"`): the board's ON FOOT section, three light-cargo runs (mail,
documents, medicine, pizza, parcels …) a short walk away, $60–110, about 8 runs to level 2; no zombie waves, now and then a
stray walker. Your hands hold 2 pieces; more go into **your backpack** (the pack: hand over takes the hands first, then
the pack; it drops when you die). **Your kit** (`Config.Kit`, Last Stop Supplies → KIT, `profile.kit`): the Courier
Backpack (3), the Big Backpack (4), Running Shoes (+10% speed), a Thermal Jacket (food stays warm) — you wear them
(Codex's models, `server/KitWear.luau`; a parcel sticks out of the backpack while it holds cargo), and the phone shows
in your hand while it is open. `shared/Transport.luau` / `server/Transport.luau` say what you carry (on foot or by car).

**Earl's van** (`shared/VanQuest.luau`): at level 4 Marge texts you about a guy out west. Earl's Used Wheels (on the
West Highway, ~1600 studs from the depot) sells his rusty Old Van for $1 800 — your first vehicle, then ★ car jobs and
missions. The dealer no longer sells it. Every other car, job tier and campaign moved up (the Courier and High-Roof at
5, car tiers ★ 4 / ★★ 5 / ★★★ 6 / ★★★★ 9 with their licences, campaigns from 4).

## The vest and a ZDC bag spin over the gear stall (6.12.8)

The owner, about Last Stop's old building: "that shop has nothing, put those props on my stalls".

- **Over the gear stall at the spawn** (`server/GearStall.luau` calls `ShopProps.place`), two giant props turn
  slowly behind the board "LAST STOP SUPPLIES · ZDC BAGS". Both are about 10 studs tall and fit the stall.
  - Over **GEAR** (Dot): the hi-vis vest (`gearvest`) on a hanger on a short pole.
  - Over **BAGS** (Nell): a new red **ZDC thermal bag** (`zdcbag`) on a turntable: black lid and piping, the ZDC
    logo front and back, a reflective strip all round, straps and a grip.
  - They spin at different speeds (Art.Motion "spin"; `client/ShopPropMotion.luau`). At night the vest's stripes and
    the bag's logo and strip glow.
- **Last Stop's old building** on (0, −1) has a bare roof now. The vest and the shoe are gone from it; shoes are not
  in the game since 6.12.2.
- `tools/polish-art/check.py shops` has a stall case. It runs the real stall, the JOBS booth and the depot hall, and
  checks the props sit over their counters, show over the board from the spawn and clear the hall's canopy.

## Fuel lasts five times as long, two gas stations by the safe zone (6.12.7)

The owner: "one or two gas stations closer, and the fuel lasts really long".

- **Fuel:** `Config.Fuel.Lasts` = 5 (`shared/FuelMath.luau` burn and range). A tank now lasts about 15 – 25 typical
  jobs instead of 3 – 5. The Old Van goes about 16,700 studs on a tank. Price, pumps, tow and jerry can are as before.
- **Two new stations** (`Map.GasStations`), just outside the safe zone on its corner streets:
  - **Depot Gas:** east of Dead End Motors (block 2, 0), a block from the depot.
  - **Tower Gas:** west of the Dispatch Tower (block −2, −1).
  - Each has the pumps, the kiosk with jerry cans, the map icon and GPS, built like the 5.4 stations on a row of lots
    that held apartments and a car park.
  - There are six stations in all. No storefront, zip line or alley moved.

## The slow-mo sprint (6.12.6)

The owner: "make the sprint look like a slow-mo sprint". The body still runs at the sprint's speed; the run cycle on it
(`shared/RunCycle.luau`, `client/SprintPose.luau`, every client sees it) now looks like a slow-motion shot:

- **Big strides at about half the old cadence:** `Config.Courier.Sprint.Stride` 7 → 13 studs a cycle (about two
  cycles a second at 28 studs / s).
- **It hangs in the air:** `RunCycle.hang` and `Sprint.Hang` (0.45). The cycle slows in the two flights and hurries
  through the steps, so the runner sails and the feet only touch down.
- **A longer reach:** the thighs swing +66 / −42 (55 / 35), the arms ±76 (60), the lean 16 (14), the float 0.32 studs
  (0.15).
- Tuning: `Stride` (higher = slower legs) and `Hang` (0 = no hang) in `Config.Courier.Sprint`.

## JOBS, MISSIONS and TASKS up front in the phone (6.12.5)

The owner: "the main things in the phone, jobs, missions and tasks, make them more visible".

- **MAIN apps:** the phone's home opens with three big red-edged tiles (`Phone.luau` MAIN, `mainTile`):
  - **JOBS** across the top. Its line says "Your run · 2 orders", "3 new runs on the board" or "Take a delivery";
    its badge counts the orders or the new runs.
  - **MISSIONS** and **TASKS** side by side under it, each with its live line and a progress bar:
    - MISSIONS: the chapter you are at, e.g. "Code Red · 2 / 6", or why it is shut ("🔒 First Shift ·
      Level 4"). NEW shows on a chapter newly open (`MissionsUi.summary`, `Phone.missionInfo`).
    - TASKS: "1 to claim · 1 / 3 today" in green when a reward waits, or "All done today ✓"
      (`TasksApp.summary`). Its badge counts the rewards waiting.
- **The other tiles,** smaller and two to a row: MAP, SHOP, BAG & ITEMS, GARAGE, STYLE (out of MORE) and MORE.
  MORE keeps CAREER, CREW, TOP, ESTATE, BANK, MESSAGES and SETTINGS.
- The texts that said "MORE → TASKS" now say TASKS.

## The third sound sheet is uploaded (6.12.4)

The owner uploaded `art/audio/sfx3.ogg`: `SoundSheet.Sfx3Id` is `rbxassetid://86357789297571`. The doors, horns,
footsteps by surface, the pond's splash, the ambience loops and the UI stings (a task done, a purchase) play their
own sounds now, not the stand-ins.

## Style: looks for you and your rides, bought from the clerks (6.12.3)

The owner: "something to spend the money on, looks only" and "things are bought only from the NPCs in the shops,
for the vibe". Nothing here changes a game number.

- **The catalogue** (`Config.Cosmetics`, 51 items: 44 for sale, 7 reward-only for later tasks, events and passes):
  - COURIER: hats, jackets, the Courier Vest's colour, the bag's colour;
  - VEHICLE: wraps for cars, vans and trucks, bike and E-Scooter paint, decals (stripes, flames, the ZDC logo, a
    checker band).
- **Bought from a clerk.** Each clerk has a second prompt, "Style" [R] (gamepad L2), under "Shop". It opens the
  phone's STYLE app on their tab, where BUY works while you stand at their shop (`Config.Cosmetics.Counters`,
  `Style.shopAt`; the server checks it):
  - Dot at the gear stall: COURIER;
  - Gus at Wrench Garage: wraps, decals and bike paint;
  - Kip at Spoke & Chain: bike paint.
- **The phone's STYLE** (MORE → STYLE) is the wardrobe. It has a live 3D preview, TRY, and WEAR / TAKE OFF
  anywhere. Away from the shop, an item not owned reads "AT WRENCH GARAGE" and sets the GPS there.
- **On the courier and vehicles** (`server/StyleWear.luau`, `shared/StyleBuild.luau`, `shared/StyleLooks.luau`):
  - Hats fit the player's own head and hide their hat and hair.
  - Jackets are thin shells under the vest and the bag.
  - Vest and bag colours go on through `KitWear.tint`.
  - Wraps go over the paint. Decals are laid around lamps, labels and doors.
  - Every part is massless, welded, never colliding.
  - A rental or a lent company vehicle takes none.
- **Save:** `profile.style = { owned, worn }`, from real saves only.
- **Checks:** `tests/style_test.luau`, `tools/character-art/style-check.luau` and
  `tools/vehicle-preview/decal-check.luau`, and the phone recorder covers STYLE.

## The spawn's corner: a JOBS spot and one gear stall, no more shoes (6.12.2)

The owner: "the jobs spot at the spawn gets a look, next to it a stall for the bags and gear, the shoes away, the
spawn as it is; the shops are needlessly big". Keep the spinning models over the buildings.

- **The JOBS spot** (`server/JobsSpot.luau`): the job board gets a booth with a canopy and a lamp, a big red JOBS
  sign that glows at night, a ticker, two screens, a mat, a bench and parcels. The board, Marge, the terminal and
  the spawn stay where they were.
- **One gear stall** west of the spawn (`server/GearStall.luau`, `Config.GearStall`), under one awning "LAST STOP
  SUPPLIES · ZDC BAGS":
  - the GEAR counter with Dot (Last Stop Supplies: vests, medkits, drinks, the car items);
  - the BAGS counter with Nell (ZDC Bags).
  - It replaces the 6.6 bag kiosk (`server/BagKiosk.luau` is gone). `Map.Shops.supplies` and `Map.Shops.bags` are
    the two counters.
- **Last Stop's old building** on block (0, -1) (`Map.LastStop`) is an ordinary building: no counter, clerk or name
  board. Its giant vest and sneaker still spin on the roof.
- **No Running Shoes:**
  - They are gone from `Config.Kit` (`Config.RetiredKit`), the outfit and the texts.
  - A save that owned them gets $250 back once (`noShoes`, `profile.shoeRefund`, Marge's text with the GPS on the
    GEAR counter).
  - Level 4's reward is the Thermal Delivery Bag.
- `tests/gearstall_test.luau` covers the stall's layout, the old block and the refund.

## Clerks in the shops, real estate from the phone, a bigger health bar (6.12.1)

The owner after playing 6.12: "the job hint shows all game long", "the health and the shield at the bottom bigger",
"I don't want the FOR SALE signs; buy everything through the phone, and things only from the people in the shops,
for the vibe", "MAP away, keep PHONE, ALT for the mouse next to it on the right".

- **The NEXT card:** "Take a delivery job" and the job board's marker show only to a new courier, up to
  `Config.Goal.HintJobs` (3) deliveries. After that, with no job, they stay away and J still opens the board
  (`client/Objective.luau` `quiet`, `client/Hud.luau` boardMark).
- **Health and shield** (Hud's health row, 18 → 44 px):
  - Health is a thick green bar (red when low) with a big + and the number in big type.
  - The vest's shield is its own blue bar over it, with its percent.
- **The top-right buttons:**
  - MAP [M] is gone: the minimap's EXPAND [M] opens the big map.
  - PHONE [Q] stays. MOUSE [ALT] is to its right: Alt held frees the mouse for a moment, and a click keeps it free
    until the next click (`CameraRig.toggleFreeMouse`).
- **Real estate from the phone** (`server/Estate.luau`, `client/EstateUi.luau`):
  - BUY works in the ESTATE app (H) from anywhere.
  - The floating FOR SALE name plates and the signs' prompts are gone. The signs' own boards still say FOR SALE or
    OWNED.
- **Clerks** (`server/ShopClerks.luau`):
  - **Who stands where:** a person stands behind every shop counter: Dot at Last Stop Supplies, Ray at Lead & Co.,
    Kip at Spoke & Chain, Sal at Dead End Motors, Gus at Wrench Garage, Nell at the ZDC Bags kiosk.
  - **The Shop prompt** is on them ("Shop · Ray · Lead & Co.").
  - **When you come to the counter:** they look at you, wave and say a line.

## Daily and weekly tasks, more sounds (6.12)

The owner asked for a proposal of what the game needs and picked tasks, live events, cosmetics, sounds and getting
ready to publish. 6.12 brings the tasks and the sounds; cosmetics, live events and the release kit come next.

**Daily and weekly tasks** (`shared/Tasks.luau`, `server/Tasks.luau`, `client/TasksApp.luau`, `Config.Tasks`)
- **What you get:** MORE → TASKS on the phone gives every courier three daily tasks and one weekly task, picked for
  each player and the same all day. Examples: "Deliver 3 pizza stacks", "Land 2 PERFECT throws", "Ride a zip line",
  "Kill 20 zombies at night", "Deliver 50 pieces of cargo".
- **When they change:** new dailies at 00:00 UTC, a new weekly on Monday at 00:00 UTC.
- **Your level:** only tasks open at it are picked, and the rewards grow with it.
- **Claiming:** each card shows the progress and the reward; press CLAIM when it is done.
  - Finishing all three dailies opens a bonus.
  - A finished task you forgot to claim is paid at the reset.
  - A red dot on PHONE and on MORE shows rewards waiting.
- **Where progress comes from:** the hooks are one call each: `Tasks.note` in Jobs, Cargo (throws), ZipLines, Wheelie,
  Buses, RunEvents, Missions and the zombie kills.

**More sounds** (`art/audio/sfx3.ogg`, `SoundSheet.Sfx3Id`, `shared/SoundPlan.luau`, `client/SoundScape.luau`,
`Config.Soundscape`)
- **Vehicles:**
  - Car doors click open and thunk shut; a van's rear doors swing and slam; a roll-up door rattles.
  - **H** behind the wheel honks for everybody nearby (`server/Horn.luau`): car, van, truck, a bike's bell, a
    scooter's beep.
- **Footsteps** follow the ground, for you and the players near you:
  - concrete;
  - the park's grass;
  - the wooden bridge and gazebo;
  - metal ladders and platforms;
  - wading.
- **Water:** you splash into the pond or the river.
- **The city:** traffic and birds by day; wind, crickets and far-off groans at night; wind on the rooftops; the
  fountain babbles.
- **Purchases** ring the till, and a finished task has its own sting.
- **Uploading:** upload `sfx3.ogg` and paste its id (`art/audio/NAHRAT-SFX3.md`). Until then stand-ins play.

## The Central Park in the middle, the depot north-east of it, giant rooftop props (6.11)

The owner: "Make the middle of the map, the safe zone, nice: nature, water in the middle, a park; move the houses so
people remember where the safe zone and the shops are; big set pieces over the main shops: a giant pizza slice over
the pizza place, a 3D GUN STORE sign with a bullet casing." They picked the layout with the park in the very middle.

**The Central Park** is Downtown block (0, 0) (`Map.Park`, `server/CentralPark.luau`), in the middle of the safe zone
with every shop around it.
- **The pond:** a stone-edged octagon of real Terrain water, 38 studs across and 3.5 deep. You can swim in it.
- **The island and bridge:** the island in the middle has a fountain whose jet shows from afar and glows at night. A
  wooden footbridge leads to it.
- **Around the pond:** paths to every side and corner, 21 trees, flowerbeds, benches facing the water, lamps, a gazebo
  and ducks.
- **Signs and the map:** a CENTRAL PARK · SAFE ZONE sign faces each street. On the map (M) it is the one green block,
  with the pond.
- **No hole to the void:** the pond's floor and water are made with the ground's hole in `World.buildGround`.
- **Vehicles:** a vehicle that rolls into the pond sinks (`Map.inPond`, server/Vehicles.luau), so you can call a new
  one.

**The depot** moved one block north-east (block (1, −1), `Map.Depot`), laid out as before with its yard open to
Bone St.
- **What moved with it:** the spawn (144, −118), Marge, the job board, the garage terminal, the ZDC Bags kiosk and the
  scooter rack are all placed from the depot's middle.
- **The four plain towers** that stood there are gone. Their dice are still rolled (`Map.FormerBlocks`,
  `tower(lot, true)`), so the rest of the city is identical: addresses, homes, zip lines, bus stops and docks.
  `tests/centre_test.luau` holds that.

**The rooftop props** (`server/ShopArt/Geometry.luau`, `server/ShopProps.luau`; checked by
`tools/polish-art/check.py shops`):
- the depot's ZDC parcel;
- GUN STORE in 3D block letters with a brass cartridge;
- a hi-vis vest and a sneaker;
- a bicycle;
- a 50s car tipped up on a pylon;
- a wrench across a tyre;
- Luigi's pizza slice, which bobs;
- the bank's gold coin, which spins (`client/ShopPropMotion.luau`);
- the clinic's red cross.

Letters, bulbs, logos and lamps glow at night.

**6.11.1:** a bike or a scooter no longer loses speed in a turn (the owner: "it slows down so much when I turn").
- `client/Drive.luau`'s wall check compares with how fast it really moves, not only along its nose: in a quick turn
  the nose leads the way it moves for a moment, and that share was taken off the speed.
- In Studio, a scooter that is still much slower than it should be while turning prints `[Drive] scooter in a turn: …`
  with the numbers, at most every 2 s.

**Review fixes:**
- the moving props turn about their own rest frame, through a PivotOffset on the PrimaryPart;
- vehicles sink in the pond;
- the pond's floor is built with the ground.

## Zip lines by hand, scooters you hop on, curbs (6.10)

The owner, after 6.9:
- "At the zip line E walks me there by itself, then E walks me back down. Let me climb the building myself and just
  jump onto the zip line."
- "Don't teleport me onto the scooter: I want to grab it and jump on quickly. Better controls, and a wheelie."
- "Sidewalks a little higher than the roads, and I want to drive onto them with the car, the bike and the scooter."

**Zip lines** (`Config.ZipLines`, `shared/ZipLines.luau`, `server/ZipLines.luau`, `client/ZipRide.luau`):
- The ladders are real (`ZipData.truss`). You climb them yourself with Roblox's own climb.
- You walk across the roof and onto the platform through the gap in its back rail (`RailGap`).
- To grab the trolley, **jump** anywhere on the start platform (the Zip remote's `"grab"`, checked by
  `ZipData.canStart`) or press **E** (Zip) there.
- Space lets go low over a roof.
- Getting down is your own business: climb the ladder or just jump off. There is no fall damage, but fragile cargo
  still takes a hard landing.
- The automatic climb and its "Climb" / "Climb down" prompts are gone. Your bag rides along; full hands don't.

**Scooters** (`shared/ScooterRide.luau`, `server/Wheelie.luau`, `client/Drive.luau`, `client/CarBoarding.luau`,
`client/CarVisuals.luau`, `client/BikeRider.luau`, `server/Rental.luau`):
- **Getting on:** press E right beside your E-Scooter, or at any docked ZDC RIDE scooter. Each docked scooter has its
  own Ride prompt, with no hold. Your courier hops straight onto the deck in a third of a second; getting off is a
  quick hop to the side.
- **MY BIKE** puts your scooter right next to you.
- **Steering:** quick and precise at low speed, calm at full speed. S is a firm brake, and the scooter coasts further
  when you let go.
- **Wheelie:** hold **Shift** (a gamepad's **R1**, the touch **WHEELIE** button) while rolling to pop onto the back
  wheel.
  - The front lifts about 24°, your rider leans back on the bar, steering gets lighter and top speed rises 8%.
  - It drops after up to 3.5 seconds. Everyone around sees it (the scooter's `WheelieAt` attribute).
- Bikes keep their step-and-leg-over mount.

**Curbs** (`shared/CurbShape.luau`, `server/Curbs.luau`, `client/CurbRide.luau`):
- The sidewalks stand half a stud (about 15 cm) over the road: `Map.WalkTop` 0.9, `Map.RoadTop` 0.4.
- Every block has a light-grey sloped kerb all round its edge, `Map.CurbRun` = 2 studs out onto the road. It is one
  union cloned per block, or eight wedges if the union fails.
- Every car, van, truck, bike and E-Scooter can drive up and down it anywhere: slowly or fast, straight on or at an
  angle. Pedestrians cross every crosswalk without a step.
- Over a kerb, the vehicle you drive rises at most `Config.City.CurbHop` studs/s, so it climbs onto the sidewalk
  without jumping.
- Things that stood at the old sidewalk height were moved:
  - the lost packages;
  - the far employer boards;
  - the bus-bay lines and posts;
  - the safe-zone border, now lying on the walk, the roads and the slopes;
  - abandoned cars, now leaning on the kerb;
  - road wrecks.

**Also:** the bandits' roadblock stands on the road. It floated 0.4 over it.

**Review fixes:**
- The touch WHEELIE button lets go even when the finger slides off it.
- The gamepad wheelie is R1, not B: B also closes the phone and the windows.
- The Zip remote is rate-limited (`Config.Robust.Limits.Zip`).

## One body for every courier: Roblox's classic R15 with your own look (6.9)

The owner, after seeing 6.7's body for the first time: "the figure is weird; people like Roblox's own blocky R15. Keep
the player's clothes and face, but give everybody the same figure, and the same walk and animations". And: "no cube
head: a Roblox head with the player's face; if the player has other body parts, give them the blocky R15 ones".

- **Your body** (`server/CourierAvatar.luau`, `shared/AvatarLook.luau`):
  - The StarterCharacter is Roblox's own classic blocky R15, built with `Players:CreateHumanoidModelFromDescription`
    (AvatarLook `Body`: the default torso, arms and legs, the classic proportions). It wears the courier's workwear
    (`AvatarLook.Workwear`) and the game's Animate.
  - Once you spawn, your own avatar goes on it: `GetHumanoidDescriptionFromUserId`, then `ApplyDescriptionAsync`. The
    torso, the arms, the legs, the proportions and your avatar's animations are reset. Your head and face (a dynamic
    head too), your clothes, your skin colours, your hair, your hats and your other accessories stay.
  - A player whose look cannot load keeps the workwear: a Studio test player, or Roblox's avatar service down.
  - As on the native body, only the root has mass, so riders don't change how vehicles handle, and the root stays out
    of raycasts.
  - KitWear dresses the kit again when your head is replaced.
- **The people** (`server/Npcs.luau`) are Roblox's classic R15 again, dressed as before 6.7. Kids are smaller.
- **The infected** keep their native block body, which already has the classic R15's proportions.
- **The numbers tuned on 6.7's taller body** are back on the classic R15's:
  - the zip line: `Hang` 3.9, `HandleDrop` 1.55, `ZipLines.Feet` 3 (the feet still 0.1 over the end platform);
  - the carry: `CarryLow` 0.05, `CarryMiddle` 1.1;
  - the throw's release: `Config.Throw.Release` (1.9, 2.0, 0.1), worked out on the block body in
    `tests/throws_test.luau`.
- **The 6.7 animations stay** (the idle life, the pick-up, the carry grip, the landing, the flinch). They are written on
  the R15 joints, so they play on any R15 body.
- **The 6.7 native courier** (CharacterArt `courier`) is only a fallback, used if Roblox's body cannot be made at
  server start. Players on it keep the workwear: no look of their own is put on it.
- **Review fixes:**
  - The title over your head (`server/Challenges.luau`) moves onto your own head when it is put on.
  - The phone's wrist roll applies only to a hand that holds it in its palm (`client/ArmPose.luau`). On the classic hand,
    the screen already faces you.
- **Back since 5.8:** the classic body's parts register touches again, so the tower's elevator pads (`World.luau`
  ridePad) carry you again.
- **Tests:**
  - `tests/avatarlook_test.luau`;
  - `tools/character-art/avatar-check.luau`: the classic template, Roblox's Animate swapped for the game's, your
    look's head, face and clothes kept while the body is reset;
  - the bag check on a classic R15 stand-in.

## 6.7 + 6.8 in short

The owner's wishes after 6.6: "the bags and the character aren't realistic, no animations… the shop has useless
things… the tutorial annoys… the missions menu is a mess, I want a picture of who gives them and a story". Released
together as 6.8: real-size bags with their pieces inside and items in the hand (6.7 A), a more realistic courier and
NPC body with idle life, pick-up, carry grip, landing and flinch (6.7 B), the shops cleaned up with the vest's tips,
car-only items, the bat and the energy drink (6.7 C), Marge's arrow tour and no automatic job (6.7 D), the missions as
story chapters with portraits, first-time and replay rewards (6.8). Review fixes: the bags 15% wider and deeper for the
new body (KitArt `Geometry.BagScale`), the replay cut per person, the missions screen keeping the gamepad's selection and
START in a fixed bar, the tour's NEXT on Y, the body's root at the hips (G 3.8, HipHeight 2.8: seats, the zip line's
handle, the stride scaled to the leg), the throw leaving the raised hand (`Config.Throw.Release` up 2.6).

## Who you work for: the missions as story chapters (6.8)

The owner: "Look at the missions and check the logic. The menu is weird, I can't find my way in it. I want to see it
big, with a picture of who I go to for a set of missions. And the sets should be right: they tell a story, one mission
after another. A mission you complete once gives its rewards; after that only something small."

**Chapters** (`shared/Missions.luau`): every client has one chapter of **six** missions (was ten), each briefing
continuing from the last debrief, ending in a finale with the chapter's big reward (the table in **Missions**). The
stories were rewritten to hold together: First Shift is your first week (parcels, the post office's lost mail, a
birthday, files on who sold the army's food, the bandits' answer: every van's tires slashed, the dispatch moving into
the Stadium Shelter); Code Red follows a fever to a new strain and Doctor Hiro's booster; Raj fights Tusk's price war;
Carlos's fires lead to Ivan's plant; Maria readies the base for the big horde; Ivan's blackout turns out to be copper
thieves; Walt's feud with the Rust Riders ends at the ranch; Hiro's cure is enough for one camp only, so it has to
leave the city; Vinnie leaves on his yacht and gives his pier to the mayor; Mayor Ruth's Last Convoy carries the cure
out. Each briefing names the client who sent you on ("Marge says you're her best driver…").

**The people** (`shared/Cast.luau`, `shared/NpcLooks.luau`): one entry per story character (the name, the "Name, the
title" line, the role line, the place, the NPC look), so a name always comes with the same words and the same face
(Npcs.look hashes the name and the role). The looks moved from `server/Npcs.luau` to `shared/NpcLooks.luau` (Npcs.look
calls it) so the client draws the same people; a new **firefighter** look (a red helmet, a dark turnout coat with
hi-vis stripes) dresses Chief Carlos at Fire Station 9 and Firefighter Duke. Fixed on the way: Mayor Ruth was still
"he"; two bank managers (Gordon stays; the bank's Simon is its teller); Rocco was "the warehouse boss" and "the dock
foreman" (now the harbor boss of both, in Config.Jobs too); the bandit boss "Big Earl" clashed with Earl who sells you
the van (now **Tusk**); a second Kenji, Lucy and "Mama Rosa" renamed (Yuki, Tess, Mama Lu) and the Gas Station's
owner is Dolly (Rosa is a twin); Doctor Hiro / Ellie and Nurse Kim wear the doctor's / nurse's look in Config.Jobs,
Vinnie the banker's, Molly the ice cream look, Emma the rider's, Tony the attendant's, Engineer Ivan the foreman's; the
Rust Riders were finished at the ranch and back later (Vinnie's rival is the Crimson Syndicate); three "bitten but
never turned" subjects became one (Patient Zero); the Stadium was "sealed for good" and used after; Maria praised
herself in the third person; firehouse's first briefing called a veteran "Rookie". A test keeps the 6.3 surnames out.

**The logic** (bugs fixed):
* **Rewards paid on every replay**: a mission's full job pay (and XP) was paid again every time (≈ $5,000 for a
  replay of Last Convoy). Now a replay pays `Config.Missions.ReplayPay` (25 %) of its pay and `ReplayXp` (25 %) of
  its XP (`Jobs.startMission(…, replay)`, `Missions.replayPay` / `replayXp`); a crew member who has done it gets the
  replay's share too. What a finish gives is one pure function, `Missions.creditFor` (the first time: the reward and
  the XP bonus; the finale: the chapter's reward once; a replay: nothing but a new star's StarBonus).
* **Only the next mission**: before, any mission whose predecessor was done could start; now only a chapter's next
  (`Missions.nextUp`), the later ones say "Finish 'X' first".
* **Hard-coded tens**: the finale was `<campaign>_10` and the previous mission `<campaign>_<n-1>` (string-built
  ids), the banner "3/10", the cards "finish all ten" — all from the chapter's list now.
* **A chapter that can't be finished on the way**: the levels inside a chapter rose too fast (the story waited for
  board jobs, First Shift's fourth mission already needed level 5); a chapter's missions now sit at its level, its
  finale at the next chapter's, and the story played in order reaches level 15 (`FirstClearXp` 2.5).
  First Shift fits the Rusty Van (2 slots); a NIGHT ONLY mission never opens a chapter (three in all, the window says
  "starts after dark").
* **DUO blocking**: the "every mission / campaign / star" challenges counted the DUO chapter (a solo player could
  never finish them, nor Dead End); they count the story now (60 missions, 10 chapters, 180 stars).

**The saves** (`server/PlayerData.luau`): the mission ids did not change: every chapter kept six of its ten old
missions in their old order, with the old first and the old finale, so a save's ratings mean the same missions
(rating ≥ 1 = done: no second first-time reward), an old save's progress stays a run from the chapter's start, and a
finished campaign stays finished (`profile.campaigns`). The 44 retired ids (`Missions.isRetired`: dispatch 4–7,
clinic 3 6 8 9, market 4 5 6 8, duo 3 5 6 8, firehouse 4 6 7 8, army 5–8, power 3 4 5 9, ranch 4 6 7 9, lab 1 3 4 6,
underworld 3 6 7 9, exodus 2 4 5 6) stay in the save untouched and count nowhere.

**The screen** (`client/MissionsUi.luau`, `client/MissionsLayout.luau`, `client/Portrait.luau`): see **Missions**. The
portraits need no uploaded image and no server template: the client builds the bust from the NPC look (a flat
silhouette with the role's emoji if that ever fails). The phone's MORE → MISSIONS opens it.

**Tests**: `tests/missions_test.luau` (the data and the design rules), `tests/missions_story_test.luau` (the order and
the locks, every `requires` valid, every chapter finishable in story order, first time against replay, the old saves,
the cast), `tests/missions_layout_test.luau` (1280 × 720 and an iPhone SE sideways), and `tools/phone-ui/check.py` runs
the real window against recorded instances (`tools/phone-ui/missions.luau`).

Test in Studio: open U at level 4 with the van: Marge's chapter chosen, START on Paper Trail; finish it (the cleared
card: FIRST CLEAR!, the reward, NEXT); replay it (REPLAY · $X on the card and in the DELIVERY result: a quarter); a
locked step's "Finish 'X' first"; Ellie's card "🔒 Finish Marge's chapter first"; the portraits (Marge, Chief Carlos's
helmet, the twins side by side) in the list and big; a phone sideways (the clients on top, START in view); a gamepad
(START selected and still selected a second later, the cards and the steps reachable and kept selected when chosen);
MORE → MISSIONS on the phone; the admin's missionsAll / missionsReset.
## The shops cleaned up: the vest's tips, car-only items, the bat and the energy drink (6.7)

The owner: "In the shop there are useless things. Go through it, delete them, make it better, add or remove."

- **Not for sale any more.** The **Pistol** and the **Plastic Bag** are every courier's from the start (`starter`:
  "STARTER · yours", $0; the server gives a missing one back for free). Marge's old "buy a pistol" text, the shooting
  "no gun yet" note and the weapon wheel's pistol price are gone (they could never show: every profile has the pistol
  since 6.0.2). The **Thermal Jacket** (food ×0.8) is retired: the Thermal Delivery Bag does that job (×0.35). A real
  save that owned it gets **$300 back once** (`Config.RetiredKit` with its own save flag `noJacket`,
  `Transport.retiredRefunds`, `server/PlayerData.luau`; Marge says so after PLAY: `Config.Courier.JacketRefund`); its
  food drain (`server/Jobs.luau`), KitWear's jacket slot and KitFit's are gone.
- **Rewards apart.** The reward-only guns (revolver, carbine, Maria's Carbine, the Lever Rifle, the Golden Pistol, Dead
  End) and the 11 never-sold paints sit in a folded **🏆 REWARDS** section at the bottom of their tab (SHOW / HIDE).
- **The Courier Vest** has a real effect: **+5% tips on every delivery** (`Config.Kit` hivis `tips = 0.05`,
  `Transport.tipShare`, `JobRules.kitTip`, added in `server/Jobs.luau` payOrder with a line on the result card; not on
  missions; it counts under a Kevlar or heavy vest too).
- **Car-only items** (`Config.Items` `car`: the repair kit, nitro, the landmine, the jerry can; their words start with
  "Car only"): in Last Stop Supplies' ITEMS, the bottom bar, the phone's and the I window's lists and the supply crates
  only once you own a car (`Economy.ownsCar`: any vehicle that is not a bike; `itemShown` / `itemsFor`); the server
  (and a gas kiosk) sells them only then. The on-foot items come first in the bar. **The bar's overflow:** more kinds
  than slots (5, a touch screen 2): the last slot is **MORE** ("+N", its key and key 9): the I window's ITEMS.
- **Lead & Co.** sells the gun upgrades now (**Gun Damage**, **Fire Rate**: moved from Wrench Garage, the same save
  keys) and the **Baseball Bat** ($150, level 1, `Config.Kit` bat with `shop = "guns"`): owned, **V with the gun away
  swings the bat** (`Config.Melee.Kinds` bat: 30 damage, 0.7 s, push 44, 7 studs of reach; a punch is 12) with the
  gun's overhead strike (`Melee.pose`) and a bat welded into the right hand for the swing (`server/CloseCombat.luau`).
- **The Energy Drink** ($40, at most 5, Last Stop Supplies): the breath full at once and **×1.3 breath for 30 s**
  (the character's `EnergyUntil`, `client/Stamina.luau` energized / refill; `Config.ItemTuning` EnergyTime /
  EnergyBreath), on foot.
- **Reworked:** the **E-Scooter** holds 3 (two on the rack, one on the deck) for $1,900 at level 3, below the Cargo
  Bike (the owner's speed 32 stays); the **Hunting Rifle** hits 60 (132 a second: more than the SMG's 117, even
  before its spread misses far out; one shot drops a walker or a runner); the **Works Rally** stage adds +100 health;
  bike runs take **up to 8 pieces** (6 before), so the **Bike Trailer**'s +4 counts on one run (fitting it on the
  Cargo Bike would not have helped: its box + panniers already passed the old cap of 6); the **Ram Plow** also takes
  12% a level off the dent a zombie you don't kill leaves (`Economy.ramGuard`, at most down to 25%); the **Roof
  Rack** takes 2 light pieces side by side; the **Muscle Car** holds 2 (the Street Machine 3).
- **Words that are true:** every item, kit piece and gear says what it does and its limits ("Car only", "5 at most
  down", "heavy cargo by hand", "not on the E-Scooter"); the map's shop lines and the phone's SHOP list say what each
  shop really sells; the depot is listed on its own on the map (the Depot Garage is the garage terminal, no shop
  window).

Tests: `tests/shop67_test.luau` (the energy drink, the bat's numbers, the jacket refund, the car-only filter, the vest's
tips, where each piece is sold, the reworked numbers), `bags_test`, `transport_test`, `kitfit_test`, `armour_test`,
`cargun_test`, `capacity_test`, `career_test`, `bikes_test`, `logic_test`, `melee_test`, `icons_test`, the phone's check.
**Test in Studio:** Lead & Co. (STARTER pistol, the gun upgrades, buy the bat, V with fists and with the bag: the bat in
the hand, a walker in two swings; REWARDS folded and opened), Last Stop Supplies with no car (no car items, the energy
drink: sprint ~8 s) and with a car (all seven, the bar's MORE slot and key 9), a delivery with the Courier Vest (the
tip line), an old save with a jacket ($300 and Marge's text once), the E-Scooter's third piece on its deck, the Roof
Rack's two pieces, ramming with the plow.

## One bag, the bike's own bag, the ZDC Bags kiosk (6.6)

The owner: "The backpacks, the bag and the bike work weirdly. When I don't know how to put something on the bike, I take
it into the bag." and "You can't have a bag and a backpack at the same time; they're in the same category. I need a shop
for them." **One carrying item, one simple story.**

- **No backpacks.** The Courier Backpack and the Big Backpack are gone from `Config.Kit` (and KitFit's / KitWear's
  `pack` and `load` slots, `Transport.backpackRoom`, 5.3's `Config.Cargo.PackLooks` / `Bag.fits` / `Bag.room` /
  `Bag.makeRoom`, the shops, the phone, the I window). **Your room on foot = your hands (2) + your bag** (the active one:
  `Transport.handsRoom`). Every light piece fits the bag (a bouquet, a cake, groceries too); a heavy one goes only in
  the hands.
- **Money back, once.** A real save (`saved.money ~= nil`) without the `noPacks` flag gets the price of every backpack it
  owned (`Config.RetiredKit`: $150 / $400, `Transport.packRefund`, `server/PlayerData.luau` applySaved); Marge texts
  once after PLAY: "Backpacks are gone: bags do it all now. You got $X back." (`Config.Courier.PackRefund`,
  `server/Tutorial.luau`, the kiosk on your GPS). Level 3's career reward is the Canvas Tote now.
- **The bike has its own bag** (its rack, basket or box with its bike gear: `Cargo.Info.rack`, `Transport.bikeBagOf`;
  a bike run, or a foot run while your bike is your vehicle; the numbers are the bike's capacity + gear as before).
  A pickup goes **onto the bike** while it is within `Config.Cargo.BikeReach` (12) studs of you or you sit on it
  (`Holding.bikeNear`), else **into the bag in your hand**, else **your hands** (`Holding.place`). **Getting on your
  bike loads your hands onto it** when it has room (the bike's door no longer says "Load it first (E at the back)":
  `Vehicles.bikeStows`, `Cargo.canStowHands`, `Cargo.update`). At a drop **E** takes the piece from wherever it is: your
  hands, your bag, the bike within reach; a bike too far away: "Your bike has it: bring it closer." Throws take the
  near bike's pieces too. The bike's pieces stay on it when you die, and a fall on foot does not knock them.
- **The HUD tells one story:** the CARRYING pill reads `CARRYING 🍕🍕 · 3/4` with a small mark on each piece (✋ hands,
  🛍 bag, 🚲 the bike's bag, 📰 a round's satchel: `Bag.Marks`); the bag slot shows n/room; the I window (now "Bag &
  items", its run tab 📦 CARRYING), BagUi, the phone's ORDERS chip (`CARRYING n / room`), the board and the shop never
  say backpack.
- **ZDC Bags** (`Map.Shops.bags`, `Config.BagShop`: a kiosk at (26, 30) in the depot's safe yard, east of the spawn pad,
  its counter facing it; clear of the scooter rack, the job board, the garage terminal and Marge; `server/BagKiosk.luau`,
  built from World's buildDepot with its helpers): a counter with the shop prompt, the five bags on its back wall, a
  striped awning, a lamp and the name board; its own 16-stud radius (`Map.shopRadius`), the plastic bag's picture on
  the map. It sells **the five bags** (KitShop's "bags" list, USE there too); **Last Stop Supplies keeps the vests,
  the shoes, the jacket and the items**. Marge's bag texts, the tutorial's last page and the phone's SHOP list ("ZDC Bags
  · bags (sprint with your deliveries)", first, GPS) send you there.

Tests: `tests/bag_test.luau`, `holding_test.luau` (the bike's reach, where a pickup goes, room = hands + bag),
`bags_test.luau` (the refund, the kiosk's place), `kitfit_test`, `bagfill_test`, `transport_test`, `career_test`,
`icons_test`, `locationtag_test`, the phone's check. **Test in Studio:** an old save with a backpack (the money and
Marge's text once), a bike run (pickups onto the bike next to you, into the bag away from it; get on with a piece in
your hands; E at a door with the bike far, then near), the kiosk (E at its counter, BUY a bag, USE).

## Marge shows you the screen, you pick your first job (6.7)

The owner: "Make the tutorial not annoy you. It should simply show with an arrow where things are in the menu, then
that you take one job, and you either say yes or skip tutorial. But don't automatically give a job."

- **Her welcome comes on its own**, 2 s after PLAY on a new save (`Config.Tutorial.StartDelay`): one page, "Hi, I'm
  Marge, dispatch. You're a courier now: take jobs, deliver, get paid. Let me show you around in 20 seconds." **SHOW
  ME** gives you her phone and starts the tour; **SKIP TUTORIAL** ends it. TALK TO MARGE over her head only shows while
  that welcome waits unseen; E at her shows it again.
- **The arrow tour** (`client/TutorialArrow.luau`, driven by `client/TutorialUi.luau`, the stops in
  `TutorialSteps.ScreenTour`): a big bouncing red arrow, a pulsing frame round the thing and a one-sentence caption with
  NEXT › and SKIP TUTORIAL. The NEXT card, PHONE [Q], then the phone opens by itself for JOBS, MAP, SHOP and BAG & ITEMS,
  it goes away for the bottom bar (1 fists, 2 bag, 3 gun, 4–8 items), then the minimap (M). Nothing stops: you can
  walk meanwhile. It follows its target every frame (a phone sliding in, a HUD laid out again); `TutorialSteps.placeArrow`
  (tested) picks the side with room. Enter is NEXT (Space still jumps), touch taps; a gamepad's Y is NEXT (the caption
  says "Y"; 6.8 review: A jumps, and NEXT is selected only at the phone's stops, so the stick walks the rest of the
  tour). Close the phone during its stops and the tour moves on past them; take a job meanwhile and it ends quietly (and
  if the arrow ever fails, the tour ends instead of half-running).
- **No automatic job:** the last page asks "Ready? Take your first job" with **TAKE A JOB** (the phone opens on JOBS,
  you pick any job) or SKIP TUTORIAL. Then nothing of hers during play: the **first delivery of any job** pays the $50
  (`Config.Tutorial.Reward`) with a "First delivery! +$50 from Marge." toast; a failed one just goes back to "Take your
  first job (J)" on the NEXT card. The strip under the card says FIRST DAY · +$50 ON YOUR FIRST DELIVERY with SKIP (it
  asks first; a skip pays nothing). Her special two-letter job (`Jobs.startTutorialJob`) is no longer used; her done,
  board and retry pages are gone. A save that finished or skipped it never sees it again.
- **Again, any time:** the phone's MORE → SETTINGS has SHOW ME THE SCREEN (this tour) and SHOW ME AROUND (the 5.7
  world tour: the ZDC RIDE dock, the nearest bus stop, then JOBS).
## A more realistic courier, idle life, the pick-up, the carry's grip, landing, flinching (6.7, part B)

The owner: "The character isn't realistic at all, there are no animations … I want better graphics and better
animations." He chose a more realistic body.

**The body** (`server/CharacterArt/Geometry.luau`, native parts only): 5.9 studs from the sole to the crown, the head
0.92 (about 1/6.4 of it, an egg-shaped Roblox sphere mesh with a jaw, eye whites and irises, brows, a nose, a mouth,
ears, short hair under the backwards black cap); slim upper arms (0.6) and forearms (0.52, nearly as long as the upper
arms), legs 0.64 × 0.8 and 0.56 × 0.68, the fingertips at mid-thigh; balls round the shoulders, the elbows and the
knees on the joints, so a bent arm or knee has no gap; a neck; hands of a palm (0.22 × 0.36 × 0.4), a thumb and curled
fingers, the palms facing the body, with a `LeftGripAttachment` / `RightGripAttachment` inside each fist (0.28 under
the palm's middle: guns, `server/HandItem.luau`'s one-handed grips and the bag's handles sit there); an open charcoal
jacket over a grey shirt, a collar, pocket flaps, black cuffs, trousers with a belt, boots with round toes. 52 parts
(63 with the red Courier Vest, within the 64). The R15 part, joint and attachment names are unchanged. The people of
the world (`server/Npcs.luau`) wear the same body (`Geometry.spec("person")`, a kid at 0.75), dressed in their looks;
the infected keep the 6.0 block body. The kit stays authored on the block body: `shared/KitFit.luau` scales it onto the
slimmer one, and a small hand holds the art in its palm (the phone: `KitFit.Palm`, the wrist rolled screen up).

**The animations** (procedural, the joints' Transform in PreSimulation, through one book of the poses,
`client/PoseLedger.luau`, so the layers add up instead of piling up; numbers in `Config.Body`, the maths in
`shared/BodyMotion.luau`, tested): `client/BodyLife.luau` breathes (quicker after a sprint), shifts the weight from foot
to foot standing still, turns the head to a person near and in front (your courier also to the job's ring), blinks,
dips the knees landing by the fall's speed, flinches when hit and adds the walk's weight (a bob from the stock walk's
own thighs, a little more arm swing, the chest turning) under the sprint's run; on every player and person within 120
studs, at most 40, the small motions within 50. The stock walk and run play slower for the longer legs
(`CourierMotion.stride`, the leg measured on the rig). `client/ArmPose.luau`: carrying, both hands reach the box's sides (a two-bone reach from
`CarryAt` / `CarrySize`, which `server/Cargo.luau` sets from the held piece) and the body leans back with a heavy load;
a piece picked up off the ground plays "pickup": down on the knees, the back bent, the hands on the piece, which comes
up into them after `Config.Body.PickupLift` (also picking up a set-down bag); gestures with the legs keep the feet where
they stood.

**Test in Studio:** the courier from all sides and in the dark (the face, the cap, the hands), with the Courier Vest,
the shoes, each bag and the phone (in the palm, screen up); the people (hats, hair, coats, kids); idle 20 s (breath,
weight shift, blinks, the head to Marge and to the ring), walk / sprint / stop, jump and fall from a roof (the dip),
a zombie hit (the flinch); pick up a piece you put down (G, then E) and a set-down bag; carry one and two pieces and a
heavy one (the hands on the box, walking); seats, bikes, the scooter, zip lines and ladders (nothing posed there); the
feet on the ground everywhere (Output: no Unstuck lifts).

**6.8 review, the body fixed:** the root's bottom is at the hips as on every R15 body (`Geometry` G 3.8, HipHeight 2.8
= the leg; 6.7 had the root 0.6 lower in the body), so the seat weld (the root 1.5 over a seat) puts the thighs on car,
bus and bike seats instead of 0.8 over them, and the numbers tuned on the 6.0 block body fit again. The walk, the run
and the sprint's stride are paced by the leg measured on the rig (`CourierMotion.leg` / `stride`: 2.8 / 2), so the
feet stop sliding. On a zip line the hands hold the trolley's handle (a two-bone reach of each arm,
`Config.ZipLines.HandleDrop` / `HandSpread`; `Hang` 3.1, `ZipLines.Feet` 3.8). A thrown piece leaves the hand where
the hand is at the whip (`Config.Throw.Release`, worked out from the rig in `tests/throws_test.luau`). Putting a box
down, the arms blend out of their last reach to it; the carry lean lets go of the waist off one's feet; the carry sits
`Config.Cargo.CarryLow` / `CarryMiddle` lower on the root (where the forearms are). **Test in Studio:** sit in a car,
a bus, a bike and stand on a scooter (the thighs on the seat, the head under the roof); walk and run on a flat road
(the feet planted); a zip line (the hands on the handle, the feet clear of both platforms); a throw (the piece leaves
the raised hand); put a box down (no snap); a bus walk-in and a ladder climb (no lean on the waist).

## Real-size bags, items in the hand, the throw's wind-up (6.7, part A)

The owner: "The bags and the character aren't realistic at all, there are no animations, the bag is small, the things
would never really fit in it."

**Real-size bags** (`server/KitArt/Geometry.luau`, 1 stud ≈ 35 cm): the plastic bag is 40 × 45 × 20 cm (gussets, a
hem, two handles into the fist), the canvas tote 40 × 40 × 13 on long handles under the arm, the thermal food bag
45 × 37 × 38 (zip-round lid, mesh pocket, ZDC patches, two straps to a padded grip), the messenger 40 × 30 × 15 (a
flap, a zip, buckles; now at the back of the hip, clear of the arm), the duffel 70 cm long and 35 across. Each shows a
dark open mouth; loaded, the thermal bag's lid stands open behind its straps (`Geometry.open`). A bag in the hand stays
at least `Config.Courier.Bag.Clear` (0.25) over the ground: `tools/character-art/bag-check.luau` measures it on the
real body (today 0.33 at the lowest), `tools/model-art/export.py` checks each bag's reach (≤ 20 parts a bag).

**Real-size pieces in them** (`shared/BagFill.luau`, `Config.Courier.BagFill.Packed`, tested): a pizza box is 33 × 4 ×
33 cm, a parcel, a bouquet a stud tall, a cake box 23 cm … They are packed like a courier packs: lanes along the bag,
side by side across it, then a layer below; the last one in lies on top. Pizza boxes lie flat and stacked in the
thermal bag (the top one at the rim, seen through the open lid) and stand on their edge in a plastic bag; a bouquet,
a cake, a take-out bag stay upright. The top layer sticks out of the opening by 20–40 %, nothing goes under the bottom,
a piece that fits no way is shrunk to 70 % at the least, and the body swells up to its own amount (the plastic bag
25 %, the rigid thermal bag 4 %).

**Pieces in the hands at their real size** (`Config.Cargo.LightScale` / `LookScale`): a light piece is built at half
its old size (a box carried in both hands is about a stud wide, a cake box 0.65), heavy cargo as before; carried, it
rests on the forearms in front of the chest (`CarryLow`, `CarryFront`).

**Items in the hand** (`server/HandItem.luau`, `shared/Gestures.luau`): handing over at a door, the piece is in your
hands held out ("give", 0.4 s), then in the receiver's ("receive", 0.85 s), then on the door's stack. A pickup into
the bag: you bring the bag up with the left hand, look down, put the piece in with the right ("bag", 0.5 s); the bag
shows it from that moment. A throw: the piece is in your hand through a 0.18 s wind-up (`Config.Throw.WindUp`: the arm
back, the torso turned) and leaves it at the whip; the server decides everything at the throw and only starts the
flight then. The two-handed grips are worked out from each body's own rig attachments and the gesture's angles.

**The bag arm** (`client/BagSway.luau`, `Config.Courier.BagArm`): with a bag in the left hand the arm is a little
straighter, out from the body and swings less; a loaded bag leans the torso slightly the other way (standing or slow);
the throw turns the torso and the bag gesture tips the head down. Only while nothing else (aiming, carrying, the
phone, a gesture, the sprint) has those joints; let go to the identity otherwise.

**Test in Studio:** each bag in the hand and worn (2, then 1 / 3), empty and full: the size against the courier, the
contents in the mouth, the thermal lid opening, nothing in the ground or the leg; a pickup into the bag (the piece in
the right hand, then in the bag); a hand-over at a door (the piece from your hands into the receiver's, then the
stack; nobody home: onto the stack); a throw (the arm winds back, the piece leaves at the whip, the arc and the tips as
before); carrying two light pieces (smaller, on the forearms).

## The bag shows, and what is in it (6.4.1)

The owner: "the bag isn't visible when I have it; and it would be good if it were more visible, and that there is
something in it."

**Why no bag showed in 6.4:** `server/KitWear.luau` asked `KitArt.pieces` for the art of every slot before it built
it, and 6.4 had made the bag's slot key `"id@place"` (`"bag@hand"`): KitArt threw `Unknown kit id: bag@hand` inside
every refresh, so the bag was never built (and nothing after it in that refresh). The hand slot now takes its look
from `KitFit.parseBagKey`, and a slot that fails to build only warns (`[KitWear] hand …`): the rest is still put on.
`tools/character-art/check.py` now builds every bag with the real KitWear and Builder (`bag-check.luau`) on the
courier's R15 body and on an R6 body, in every way it is worn, empty and full: no error, the joint from the right
part, nothing anchored or colliding, every part within 3 studs of the hand (or the torso), its pieces shown.

**Every body:** on an R6 body the bag hangs under the `Left Arm`, its strap, the backpack, the vest and the bag's
shoulder / hip / back places go on the `Torso` (`KitFit.R6`, scaled to it by `KitFit.factors`).

**What is in it shows** (`shared/BagFill.luau`, `Config.Courier.BagFill`, tested): the pieces in the bag stick out
of its opening as small shapes of their looks: a pizza box, a bouquet, letters, a rolled newspaper, a folder, a food
box, a loaf, a cake box, a medicine box, greens, a gadget, else a parcel. Up to the bag's room, one row along the
opening (two side by side from four), each leaning a little. The body swells up to 16 % across (6 % along) as it
fills. Cargo sets the player's `BagLooks` attribute next to `BagCount`; KitWear builds only the bag's art again when
they change (the pivot and its swinging joint stay), so everybody sees it and nothing runs per frame. The bag set
down on the ground shows its pieces too.

**Easier to see:** the plastic bag is a light-tinted, less see-through plastic (`bagplastic`) with a red ZDC stripe
round it and the ZDC print on both sides; the messenger is courier blue and the duffel a lighter army green against
the charcoal clothes; a full duffel hangs a little further out (`HandOut`) so it clears the leg.

**The self-check:** once per spawn, three seconds after your bag shows (`Config.Courier.BagCheck`),
`client/BagSway.luau` looks whether it really is on you and, when not, says why in the Output, e.g.
`[BagSway] your bag is 37.2 studs from your hand (style hand, joint LeftHand → KitBagPivot, C0 (0.00, -0.27, 0.00),
Transform (0.00, 0.00, 0.00))`; also "has no parts on your character", "sits … studs from its place", "its parts are
all see-through" or "its joint is …". Paste such a line to us. The KEYS chip reads `KEYS · HIDE  [F1]` (the font had
no "▴").

## Five bags: sprint with your deliveries (6.4)

The owner's wish: "bags that make the work easier, bigger, but realistic". **The point of every bag: you sprint with
your deliveries.** Pieces in your hands stop the sprint and slow the step; what rides in the bag in your hand (or the
backpack) never does (it never sets the Carrying attribute: `client/CameraRig.luau`). Sold at Last Stop Supplies (KIT):

| Bag | Level | Price | Room | Perk |
|---|---|---|---|---|
| Plastic Bag (`bag`, the start kit) | 1 | $25 | +2 | – |
| Canvas Tote (`tote`) | 2 | $120 | +3 | – |
| Thermal Delivery Bag (`thermal`) | 3 | $300 | +4 | food in it cools ×0.35 (`bagWarm`; × the Thermal Jacket's 0.8 on top) |
| Padded Messenger Bag (`padded`) | 4 | $650 | +4 | fragile pieces in it take no knocks (`padded`) |
| Big Delivery Duffel (`duffel`) | 6 | $1,200 | +6 | heavy: sprinting with it costs 15% more breath (`bagBreath` 1.15) |

- **One bag at a time** (`shared/Transport.luau` `activeBag` / `bagRoom`): the bag in your hand (key 2) is the
  **active** one, by default the best you own (the most room; a tie goes to the later, pricier one), and its room is
  the bag's part of what you carry. Owning several never adds up. Every room (Cargo's pack and `BagRoom`, Jobs' room
  checks and the 6.3 bag line, the board, the hotbar, the shop) asks `Transport.bagRoom(kit, choice)`.
- **USE** (`profile.activeBag`, saved; a missing or unowned choice falls back to the best): the KIT tab and the I window's
  new **BAGS** tab show IN USE / USE on your bags (the Kit remote's `("use", id)`, anywhere). Refused while your bag
  holds pieces or lies on the ground ("Empty your bag first"). A bag you buy goes into use at once when yours is empty.
  On a run the pack follows the switch (`Cargo` `bagSync`).
- **The perks** work only for the active bag while it is your hand: the thermal bag keeps an order's food warm by the
  share of its pieces in it (`Cargo.bagWarm`, `Transport.mixWarm`); the duffel's `BreathCost` attribute
  (`server/Transport.luau`) makes `client/Stamina.luau` drain the breath faster.
- **Fragile on foot** (new; `Config.Jobs.CargoRules` FootFall…): a hard landing (a drop of ~14 studs and more) or a bite
  knocks each order with a fragile piece with you (a cake, a gadget, electronics: −10% / −5% condition, one knock every
  1.5 s, "CAREFUL — FRAGILE!"); the pieces in the Padded Messenger Bag in your hand are safe (`Cargo.footKnock`,
  `JobRules.footKnock` / `knockLoss`). Fragile pieces still can't be thrown.
- **Looks** (`server/KitArt/Geometry.luau`, placeholders until Codex's): a beige canvas tote on long handles, a boxy red
  insulated bag with a black lid and a ZDC patch, a grey messenger bag with a dark flap held by its strap, a big
  dark-green duffel on its carry handles; the bag set down on the ground is the active one (`KitWear.bagDrop`). Each
  swings its own way (`Config.Courier.Bags`, `BagSwing.tuning`): the bigger, the slower and the less flutter.
- **Hotbar:** the bag slot shows the active bag's icon, name ("· SPRINT WITH YOUR DELIVERIES") and room. Marge texts once
  when a level opens a bag you don't own (`Config.Courier.BagUnlock`). Tests: `tests/bags_test.luau`.
- **How each bag is carried** (the owner: "you put the bag on your back, in different ways as fits"; Config.Kit
  `carry` / `stays`, `Holding.wornAs` / `bagLeaves`, `Config.Courier.BagPlaces`, `server/KitWear.luau`):

  | Bag | While it is your hand (2) | When you take fists or the gun (1 / 3 / B) |
  |---|---|---|
  | Plastic Bag, Thermal Delivery Bag | in the left hand (the thermal by its top handle, off the leg) | as in 6.1: stowed when empty, set down on the ground when loaded |
  | Canvas Tote | over the left shoulder, the bag at the hip | slung on the back by a strap across the chest |
  | Padded Messenger Bag | cross-body: the strap over the right shoulder, the bag on the left hip | slid behind the hip |
  | Big Delivery Duffel | in the hand by its carry handles | slung across the back by its strap |

  A bag on your back keeps its pieces **with you** (they count, you hand them over at the door, the padded one keeps
  them safe) and your hands are free for the gun or the fists; pickups go into it and you throw from it only while
  it is your hand, so press 2 to swing it to the front again. The move takes ~0.5 s (`Config.Courier.Switch`): the
  right hand reaches over the left shoulder (the `sling` / `unsling` gestures, `shared/Gestures.luau`, played by
  `client/ArmPose.luau`) while `client/BagSway.luau` moves the bag from where it was to its new place (the character's
  `BagWorn` and `BagSwitchAt` attributes; still the joint's only writer, Transform in PreSimulation). Its motion
  follows where it is: in the hand the pendulum, on the shoulder or the hip a stiff little swing and a bounce with the
  steps (`Config.Courier.Wear`, `Bounce`, `BagSwing.bob`), on the back a soft bob (`BackBob`). In a seat a bag that
  stays sits on the back; a hand bag is put away.

**6.4 review:** a fragile knock counts only a real fall (a look in the air, then a landing), never a teleport (an
elevator pad, a PivotTo), a zip line's climb down or getting off a bus; on a run of several orders only the orders hit
lose condition, and a spotless mission checks at once. With a bag worn on your back the shown room counts only its
filled places (pickups need it in your hand). The I window's five tabs fit during a run; the sling gesture plays only
for a change of hand.

## Scooters at the spawn, express buses, the bus map, the bag, English names (6.3)

**The spawn's rack** (`Config.Rental.SpawnRack`, the first dock of `shared/RentalDocks.luau`): six ZDC RIDE scooters
side by side in the depot's yard, right behind the spawn pad, noses toward the street: hold E, rent one and go. It
works like every dock (Return here or anywhere); the street dock just outside the safe zone stays.

**Express buses** (`Config.Bus`, `shared/BusLines.luau`): the bus is for the long way now. A stop about every 4 blocks
(`StopGap` 560) and at the key places: each next stop is the lane nearest the shops, places and storefronts within a
window, and a stop by one is named after it ("City Hall", "Fire Station 9", "Sunny Hill School"; else "Oak St / 6th
Ave"). 14 stops, 15 buses (6 / 5 / 4), 55 studs/s on a straight, a bus every ~19 s. The contract suggests a bus for
trips over 500 studs.

**The bus map**: the big map (M) draws the three lines and their stops (the **BUS** chip hides them); every stop has a
map board next to its shelter, and near it (60 studs) your client draws the lines, the stops' names and **YOU ARE
HERE** on it (`client/BusMapBoard.luau`, one board at a time).

**The bag takes your pickups** (the owner: "things don't go into the bag, a new inventory slot appears"): on a foot or
bike job with the bag in your hand **every light piece** goes into it (`Bag.fitsBag`: bouquets, cakes and groceries
too; the backpack still takes `PackLooks` only), and an order of light pieces counts the bag's room. The bag slot shows
the server's numbers (the BagRoom attribute) with a count badge; a job whose pickups go to the hands (a car job) says
"HANDS ONLY". The slot-like strip tiles are gone: a "CARRYING …" pill over the bar lists what you carry and where. Holding
something else, a light pickup tells you once a job to hold the bag (2). A supply crate's consumable says it went to
your item bar.

**English first names** (the owner: "the people's names without surnames, in English; the whole game is English"):
residents are a single English first name (or a nickname: "Lucky Jim"), the story people a first name and a role
(Doctor Ellie, Raj at FreshMart, Chief Carlos, Engineer Ivan, Mayor Ruth, Old Man Jed, Captain Maria …), and no Czech is
left in any game text. Review: the throw's line and power meter sit over the breath bar (Hud places them, `Throw.place`).

## Auto-aim throws and the PERFECT tip (6.2)

The owner's wish: "auto aim when throwing, and a perfect hit gets a bigger tip from the customer". Holding X at a home's
door (within 45 studs) no longer aims with the camera: your courier turns to the door and the throw picks its own angle
(`Config.Throw.AutoAngles` 35° / 45° / 55° / 65°: the first whose arc, traced with the world's rays, comes down on the
door, so it lobs over a fence or a car when it has to). You only time the power: a meter over the "Hold X" line shows
the swinging needle, the **green zone** (it lands at the door: delivered) and the **gold PERFECT zone**. Let go in the
gold and the piece lands within `PerfectRadius` (1.5 studs) of the door's spot: the customer says something nice and
tips **+$20** (`PerfectTip`; at most `PerfectCap` $80 a job, on top of the TRICKSHOT tip and its own cap). The banner
says "PERFECT! +$n". The landing ring turns gold, green or white as you aim. The power swings a little slower
(`ChargeTime` 1.3 s). The server still traces the real arc and decides (server/Cargo.luau throwAt); the maths are
`Throws.solve` / `powerFor` / `direction` / `landFlat` / `perfect` (shared/Throws.luau, tested in throws_test).
6.2 review: you stand still while aiming (the move keys, the stick and jump wait), the throw is sent with your own
release point (the server takes it within 3 studs of your body, so its PERFECT matches what you saw), the needle you let
go on is the power thrown, no zones show when something blocks every arc (the ring alone tells) and a newspaper round
shows no gold zone (its papers tip nothing); the customer's PERFECT line only comes with the tip (not past the cap).

## What you hold: fists, the bag or your gun; X fixed; the bag swings (6.1)

**What you hold** (the owner's wish: "you choose to hold the pistol or the bag; when there is cargo in the bag you can
only put it down, you can't hide it"; `shared/Holding.luau`, `server/Hand.luau`, the Hand remote, `Config.Hand`): the
bottom bar has three HAND slots at its left: **1 fists ✊**, **2 the plastic bag 🛍** (its fill, "2/2"), **3 your gun
🔫** (its name; T still picks which gun on the weapon wheel). The one you hold has the red outline. Keys 1 / 2 / 3, a
click or a tap on the slot, a gamepad's d-pad left / right (the melee moved to L1). The items moved
to keys **4 – 8** (a touch screen shows two item slots beside the hands; the I window lists them all). B still draws and
holsters (it makes the gun the hand and goes back to the bag or the fists). The server decides (the character's Hand
and Holstered attributes): never in a seat, never the gun with cargo in your hands.
- **Fists:** the gun holstered, V punches. **Gun:** drawn. **Bag:** in your left hand, the gun holstered; a light
  piece you pick up drops into it while it has room (then the backpack); you throw from it (X).
- **The bag leaves your hand** (1 or 3): **empty, it is stowed** (nothing shows, its room is not yours: pieces you pick
  up go into the hands, then the backpack, as before 6.0). **Loaded, it is set down on the ground** where you stand,
  its cargo in it: a "Pick up bag" prompt (E, only you), the HUD points at it, its pieces are not with you (no hand
  over, no throw from them) but the stop waits for them. You have to go back for it; picking it up makes it your hand
  again. It lies there until then or until the job ends (its pieces are lost, as a dropped piece). Zombies leave it.
- **6.1.1:** with fists or the bag in your hand you can't shoot or aim: a click no longer draws the gun (3 or B
  takes it; with fists the left mouse punches, anything else shows "press 3"). The weapon wheel still draws the gun
  you pick on it.
- **6.1.1:** the holstered gun no longer comes back into your hand after 1 (fists) or 2 (the bag). Roblox's camera
  shows every part of your character again whenever one is added or removed (the bag going on or off), so the client
  now hides the gun again as soon as that happens (`client/ArmPose.luau` showGun).
- **6.1 review:** in mid-air, on a ladder, in water or on a zip line the bag waits in your hand's place until your feet
  are on the ground, then it is set down (never hanging out of reach). The touch THROW button and R1 appear only when a
  throw is possible (X alone still explains why not). The number keys do nothing while a window or the phone is open.
  The key hints show only the keys that work there (the driver's keys, a bus's E: Stop) and flow onto shorter lines
  beside the contract on a narrow window. The prompt on a set-down bag counts its pieces as they change.
  Dying drops the bag's pieces with the backpack's. An aim or a shot press does not set a loaded bag down (3, B or the
  wheel do, on purpose).
- **X fixed** ("after pressing X nothing shows"): X was bound only while the server's ThrowTo was set (a home's door is
  the current stop and a piece for it is with you), so anywhere else it did nothing. The server's ThrowTo logic was
  traced and is right for a home drop with a light piece in the hands or the bag (`Cargo.throwShown`); X is now bound
  whenever you could throw at all (the new ThrowReady attribute: a light piece in your hands, or the bag in your hand
  with one in it) and a press without a door in range says why: "Get within 45 studs of the delivery door to throw",
  "Too fragile to throw" or "Nothing to throw". At a door within range the "Hold X" line shows, as before.
- **The bag no longer blinks:** 6.0 took it off and built it again every time the hands took or gave a piece (KitWear
  put it away while Carrying was set) and swung it with a Transform built from the pivot's last solved CFrame (any
  frame it was stale compounded the error) plus an 8 Hz step jolt. Now it stays in the hand while you carry, and
  `client/BagSway.luau` (its only writer; `client/SprintPose.luau` no longer touches it) swings it as a **pendulum on a
  spring** (`shared/BagSwing.luau`, `Config.Courier.Bag`): the grip's real acceleration swings it (it trails when you
  start, swings forward when you stop, out on a turn), the air leans it back at a run, a small flutter and twist at
  speed; within 120 studs of the camera, in PreSimulation, the Transform straight from the hand's frame.
- **Key hints** (`client/KeyHints.luau`, `Config.KeyHints`): a quiet strip under the top buttons with what the keys do
  now (6.5, only the keys of the moment: on foot 1 / 2 / 3, E use or pick up bag, G put down, X throw only while a
  throw is possible, V; in a seat W/S, A/D, E get out, F). A keyboard only; it hides with the bottom bar. F1 or its
  "? KEYS [F1]" chip folds it (for the session); a courier with fewer than 2 deliveries starts with it open.

## The courier on foot: the bag, throws, sprint, armour, no free gun (6.0)

**6.0.2:** a new courier starts with the phone (Marge), a **pistol** and the **plastic bag**; the Courier Vest is still bought ($20, Marge texts about it). Older saves get the pistol and the bag once.

**The plastic bag** (Kit "bag", $25, level 1, `extra = 2`): two more light pieces on top of your hands and any backpack,
carried in the left hand — it swings with your stride and flies back when you sprint. A light piece you pick up (a
pile or the ground) goes straight into the bag with a quick move of the arm.

**The Courier Vest** (6.0.1, Kit "hivis", $20, level 1, just the look): a new courier starts with Marge's cash and phone
in plain charcoal workwear; the red reflective ZDC vest is bought next to the bag and put on with the vest move. A Kevlar
or heavy vest is worn instead of it. Players from before 6.0.1 get it once on load, so their look does not change.

**Throwing** (`shared/Throws.luau`, `client/Throw.luau`, the Throw remote, `Cargo.throwAt`, `Config.Throw`): at a home
drop hold **X** (gamepad R1, touch THROW): a dotted arc and a landing ring (green over the door) with a swinging power;
let go to throw. The server checks the piece, the range, the line of sight and traces the same arc. Landing at the door
delivers it (the receiver catches it, or the door opens). **TRICKSHOT** tips for a long throw, a throw over something or
off a wall. A miss lies where it fell — pick it up again. Fragile cargo (cake, electronics, samples …) can't be thrown.

**Sprinting** (`client/SprintPose.luau`, 6.0.1 `shared/RunCycle.luau`, `Config.Courier.Sprint`): from 20 studs / s on
foot the stock run gives way to a real run cycle — the thighs swing +55° / −35°, the heels kick up high, the arms pump
±60° with square elbows against the legs, the upper body leans 14° forward with the head kept level, and the body bobs
twice a stride. The cadence follows the speed (7 studs a cycle); the arms stay with aiming, carrying, the phone and
gestures. The bag in the left hand trails behind and jolts with every step. Everybody within 150 studs.

**No free gun** (`Config.Arms`): a new courier has fists (V punches). The pistol costs $250 at Lead & Co.; Marge texts
you with a GPS once you can afford it. Old saves keep their guns.

**Armour** (`shared/Armour.luau`, `server/Armour.luau`): the Kevlar vest (−30% damage, $600, level 3) and Heavy armour
(−50%, a little slower, $1 500, level 5) at Last Stop Supplies; the best vest you own counts and shows on you (a put-on
move when you buy it) and as 🛡 on the HUD. Every hit on a player goes through `Armour.hurt`.

**Scooters**: the E-Scooter tops out at 32 but pulls away hard (accel 42); ZDC RIDE rentals at 26 with a quick start.

## Couriers and infected, worn street props, new icons, a proper scooter stance (5.9)

**Every player is a ZDC courier** (Codex, `design/character-models/`; `server/CourierAvatar.luau`,
`server/CharacterArt/`, `shared/CourierMotion.luau`): one native-part R15 body for everybody — warm skin, a red reflective
vest (bought kit since 6.0.1), charcoal workwear, a backwards cap — instead of personal avatars (`StarterPlayer.StarterCharacter`, appearance
loading off). Roblox's standard R15 animations (idle, walk, run, jump, fall, climb, swim, sit) play from the server by
the real speed; ArmPose, BikeRider and the interactions still pose on top. The kit (backpacks, shoes, jacket) is worn as
before. **The infected** are native too: walker, runner, soldier (helmet, chest plate) and brute (a reinforced shoulder)
with a green face and glowing eyes, on the same AI, animations and type numbers.

**Worn street props** (Codex, `design/street-props/`; `server/StreetArt/Geometry.luau` built by
`server/PolishArt/Builder.luau` in `server/StreetDressing.luau`): bins, hydrants, barricades with a beacon, sandbags,
rubble, trash bags, boarded shopfronts with a warning, abandoned cars (flat tyres, broken glass, an ajar door, rust) and
flares; a prop whose art fails falls back to the simple one. **Icons** (Codex, `design/polish-icons/`): 29 new ones
(transport, landmarks, the exclusive guns) waiting for their upload ids in `Icons.luau`.

**Standing on the scooter** (5.8.2, `client/BikeRider.luau`, `RiderPose.Upright`, `RiderPose.armIk`): the E-Scooter
and ZDC RIDE rider stands straight (an absolute pose, not on top of the sit animation), the body raised or lowered until
the feet rest on the deck (measured, any leg length) and both hands on the bar's grips (a two-bone reach).

## Every window in the courier-phone style (5.8)

**5.8.1:** `tools/rojo-sync.js` sends a big change (a `git pull` of many large scripts) to Studio in small messages,
one script each — before, Studio could drop the whole message and keep a mix of old and new scripts (errors like
`CameraRig: attempt to index nil`). The Output's start line shows the version: `[Server] Zombie Delivery 5.8.1 is
running`. After a pull: stop the sync (Ctrl+C), start it again, and Disconnect / Connect in Studio's Rojo plugin.
(6.8.1: this alone did not always work. See **Running** above.)


The windows now share the approved ZDC phone look (`design/phone-ui/`): a ZDC header (the red square, ZDC, a line glyph,
the title in caps, a square ✕) on every `Ui.window`; **one red primary action** per view (ACCEPT, START, BUY, PLAY,
CONTINUE, COLLECT, TAKE OUT; `HudContract.button(…, "primary")` / `Ui.button(…, Theme.Contract.red)`); square tabs with a
red underline (`Ui.tabs`); slim charcoal rows with a red left rule when selected (`Ui.ticket`, `Ui.selectRow`). Restyled:
the job board (filters as tabs, phone-style offer cards), missions and the cleared card, crew, garage, estate, company,
top, career and the level-up card, Marge's dialog, the start menu (ZDC courier terminal, red PLAY), the big map's frame,
the shops / kit / bike shop / bag, and the delivery result (laid out like the phone's order card, red CONTINUE).
The admin panel only takes the shared header. The old Postage tokens map to the contract colours.

## A better whole game (5.7)

**Getting on and off like the car** (`client/Interact.luau`, `shared/InteractPose.luau`, `Config.Interact`): you step
to a bike's side and swing a leg over the saddle, or step onto a scooter's deck, hands to the bar (and back off); a
ZDC RIDE scooter slides out of its dock first. The bus's door folds open, you walk up the step to a seat and sit, and
walk out onto the kerb. Zip line ladders are climbed hand over hand (no more fade), and your hands reach up to the
trolley.

**Balance and life on foot** (`shared/FootEvents.luau`, `server/RunEvents.luau`, `client/PayFloat.luau`): the E-Scooter
tops out at 36 (two rack slots), ZDC RIDE rentals at 26; ★ car jobs give +40 XP and up to 4 pieces (what your car holds).
About one foot or bike run in four meets a runner zombie, a survivor with a tip or a locked gate, and some drops have a
few walkers. A short run ends in a toast and a "+$ · +XP" float, not the big window; the board replaces a taken offer
with one near you. Level 3 gives the Courier Backpack, level 4 the Running Shoes; car items start at 5. After the first
delivery Marge offers SHOW ME AROUND (the scooter dock, a bus stop, the board in the phone). MENU reads PHONE once you
have it.

**A living city** (`shared/TowerLooks.luau`, `shared/StreetProps.luau`, `server/StreetDressing.luau`,
`shared/WeatherPlan.luau`, `client/WorldFx.luau`, `Config.LivingCity`): towers in four looks (shopfronts, roofs with
tanks, fire escapes, boarded windows), streets with bins, barricades, sandbags, debris, abandoned cars and flares; rare
rain and fog (wet roads, river mist, dawn rays, flickering lamps); the night lights switch on every client (no server
burst) and the clock runs smoothly; a little camera shake on blasts, rams and hits, a wider view at speed and on a zip.

**Sound and juice** (`art/audio/sfx2.ogg`, `SoundSheet.Sfx2Id`, `client/Juice.luau`, `shared/Gestures.luau`):
footsteps, a knock and a door creak, the zip whirr, the scooter hum and the bikes' freewheel (no van engine on a bike),
bus brakes and door hiss, the phone buzz, coins, city ambience and wind. **Upload `sfx2.ogg` and paste its id into
`SoundSheet.Sfx2Id`** — until then those sounds stay quiet (a few borrow older ones). The money counts up, ★★★ throws
confetti, people at doors and counters wave and reach for the piece.

**Under the hood** (`Config.Robust`): PLAY, the job start and the tickers can no longer strand you; the leave save is
safer; zombies think at 20 Hz; remotes are rate-limited (`Net.limit` / `Net.latest`); a failed rental gives your own
vehicle back. Turn on **StreamingEnabled** in the place (the Output warns when it is off).

## ZDC RIDE scooters, zip lines, alley shortcuts (5.6)

**ZDC RIDE** (`Config.Rental`, `shared/RentalDocks.luau`, `server/Rental.luau`, `client/RentalUi.luau`): 20 docks
(14 Downtown, 6 in the Suburbs, one just outside the depot; 6.3: and the rack at the spawn) with free e-scooters. **Rent** at a dock and you ride at
once (your own car or bike goes home first); it works like the E-Scooter for foot and bike jobs. Get off and walk 30
studs away, leave it for 45 s or **Return** it at any dock and it goes back. Not for car jobs or missions; never yours to
keep, paint or fuel. The phone's GARAGE shows the nearest dock with a GPS button; both maps mark the docks.

**Zip lines** (`Config.ZipLines`, `shared/ZipLines.luau`, `server/ZipLines.luau`, `client/ZipRide.luau`): 8 cables from
one Downtown roof across a street to a lower roof, 130–210 studs. **Climb** by the ladder, **Zip** at the platform:
hands up on the trolley, 55 studs/s; Space lets go low over a roof. Your backpack rides along; full hands don't.

**Shortcuts** (`shared/Shortcuts.luau`, `server/Shortcuts.luau`): 8 lit alleys through Downtown blocks over open lots,
with a low fence to hop at each end and a SHORTCUT sign.

## City buses, people in every building, the courier phone (5.5)

**City buses** (`shared/BusLines.luau`, `server/Buses.luau`, `server/BusStops.luau`, `client/BusRide.luau`, `Config.Bus`):
three free lines run on a fixed timetable — **1 Downtown Ring** (red), **2 Downtown Cross** (yellow, around the depot)
and **3 Suburbs Link** (blue) — 21 buses, 28 stops with a shelter, a bench and an arrivals board (6.3: express, 15
buses, 14 stops, a map board at each). Near a stop a card
shows the next buses ("Line 1 Ring 0:12"); a bus waits 4 s at every stop: **Board** at its door, sit, and the banner
shows the next stop; **E** (STOP) rings the bell and you get off at the next stop, or right away while it stands.
Held pieces go into your backpack first. On a far foot or bike job the contract suggests a line ("🚌 Line 2 from …").
Buses never stop for traffic (every client agrees where they are), pass through people and cars, and cars give way.

**People in every building** (`shared/Residents.luau`, `Config.Residents`): every Downtown tower that faces a street
has an entrance (170 apartment buildings, 214 homes with the houses), and about 3 000 named residents live in their
flats and houses. A bigger building has more people, so more deliveries go there; a delivery names its resident and
flat ("DELIVER to Jana Nováková, Apt 4C, 40 6th Ave"), and the one who opens the door carries that name.

**The courier phone** (Codex's approved ZDC design, `design/phone-ui/`; `client/Phone.luau`, `PhoneContract`,
`PhoneLayout`, `PhoneRoute`, `PhoneApps`, `PhoneMotion`): square charcoal apps with white glyphs, the live contract on the
home screen, the route on the order's map. The MENU lives in the phone now (Missions, Crew, Top, Estate, Bag, Garage,
Settings with every key, Bank), and once you have the phone MENU opens it. **6.0.1: every app opens in a centred
popup** over the game (`PhonePopup`: a dimmed, lightly blurred backdrop, the ZDC header, two columns for BOARD, CAREER
and SHOP; ✕, a tap beside it, Q, ESC or B return to the phone, which never turns sideways); the board in the phone takes jobs (ACCEPT / + ADD ORDER, FULL BOARD for the big one). Banners drop
for new messages and new jobs. GIVE UP is in ORDERS (press twice). **6.5: the home of everything** is six big tiles,
each with a one-line subtitle: **JOBS** (the board, ORDERS during a run, the open orders on its badge), **MAP**, **SHOP**
(the shops and what they sell: a tap sets the GPS and says "GPS set: Last Stop Supplies"; under them what to save up
for), **BAG & ITEMS** (the I window's BAG / ITEMS / BAGS tabs), **GARAGE** and **MORE** (Career, Missions, Crew, Top,
Estate, Bank, Messages, Settings; ESC goes back to the tiles). A messages row under the tiles shows the unread count.
The tutorial shows instead of talks: Marge's welcome and her done screen are one page each, the run has no pages (the
goal card shows each step, `TutorialSteps.hint`), SHOW ME AROUND stays optional.

## Deliveries from real shops to real doors, the bag, newspaper rounds, fuel, the new phone (5.3, 5.4)

**Real deliveries (5.3, `shared/Deliveries.luau`):** every pick-up is at the business's own storefront (`Map.Venues`): a
pizza comes from Luigi's, bread from Daily Bread, parcels from the Post Office, and the cook or clerk hands it over at
the door. Home deliveries go to a real front door (`Map.Homes`): you knock, someone opens and takes it, now and then
nobody is in and you leave it at the door. Business rules: the bakery works mornings, pizza / burgers / noodles pay
more in the evening and at night, the pharmacy sends medicine to patients, hardware goes to houses and the Harbor,
electronics to apartments.

**The bag** (`shared/Bag.luau`, `client/BagUi.luau`, the I window's BAG tab and the phone's 🎒 BAG): what you carry and
where — hands, backpack, the bike's rack or box, the car — piece by piece, for whom and for which order. Small things go
in the backpack (`Config.Cargo.PackLooks`: mail, newspapers, documents, medicine, pizza, food boxes, bread, small
parcels); flowers, cakes, groceries and electronics ride in your hands or on a rack (two on the E-Scooter, one on a ZDC RIDE rental).

**Newspaper rounds** (`Config.Jobs.Round`, on foot or by bike, mornings): pick up a bundle of 8–12 papers at The Daily
Undead and deliver one to every door on one or two streets — walk up or toss it onto the porch (the server checks the
throw). A tip when you miss none.

**Fuel (5.4, `Config.Fuel`, `shared/FuelMath.luau`, `server/Fuel.luau`):** cars burn fuel as they drive (a tank lasts
about 3–5 jobs; bikes and the scooter need none). The gauge sits by the speed (`client/FuelGauge.luau`, red under 15%).
Empty, the car crawls at 6 studs/s — reach a pump or call a **tow** from the phone ($150: your car goes to the nearest
station with 5 L). Four stations: the old Gas Station on the North Highway, Westside Gas, Harbor Gas and Willow Gas.
At a pump hold **Refuel** with the car parked beside it: $2 a litre, it pours until full or your money runs out. A
jerry can (+10 L, $35) is sold in the kiosks and at Last Stop Supplies. The Fuel Run delivery stays; there is no work at
the stations, only deliveries.

**The phone, redone (5.4):** a clean header with a round back button, cards that fit their text, one type scale. ORDERS
shows "No active orders" with OPEN BOARD when you have none, else the current order (timer, pay, its stops ✓ ▶ ● ○, your
load) and every other order with a small PIN. MESSAGES is a chat list (avatars, time, an unread dot).

**5.4.1:** the phone moved to **Q** (the weapon wheel to **T**); with only the phone open, holding the right mouse still
turns the camera. A job whose payload fails no longer gets stuck (the server sends a short one and warns once in the
Output), so the first delivery, Marge and the board work again.

## Several orders at once, real shops and homes in town (5.2)

**Several orders at once** (`Config.Jobs.Orders`, `job.orders`): while an ordinary run goes (on foot, by bike, or a ★ / ★★
car job), the board offers **+ ADD ORDER** as long as your free room allows (hands + backpack, bike + gear + backpack, the
car's slots) — up to 2 on foot, 3 by bike, 4 by car. Pick up and drop in any order; a drop opens once its pieces are with
you; the GPS goes to the nearest open stop or the order you **pin** in the phone's ORDERS app (`client/OrdersUi.luau`,
`JobRules.nextOpenStop`). Every order has its own clock, pay, rating and condition; when one runs out the others go on.
Missions, specials, employers, the Freight Run, DUO and the tutorial stay one at a time.

**The town got real places** (`Map.makeLots`, `Map.Venues`, `Map.Homes`): eleven storefronts — Luigi's Pizza, Daily Bread
Bakery, Last Bite Burgers, Wok Dead, Grind House café, the Post Office, The Daily Undead (newspapers), Bolt & Nail
Hardware, Volt Electronics, Second Life Pawn, Bloom flowers — and 95 delivery homes: apartment entrances downtown (steps,
a buzzer, a number) and suburb houses facing the street (a path, a mailbox, a number). 5.3 sends the deliveries there.

## Bikes and Spoke & Chain Cycles (5.1)

At level 2 Marge texts you: **Spoke & Chain Cycles** on Main St (Downtown block -1, 1) sells bikes — the Rusty Bike
($300, L2), the Courier Bike ($1 100, L2), the Cargo Bike with a front box ($2 400, L3, 4 slots) and the E-Bike
($6 500, L5) (`Config.Cars` with `bike = true`, Codex's `BikeArt`); 5.1.1 adds the **E-Scooter** ($2 800, L4: quick, you
stand on the deck, 1 slot on its rear rack (5.7: 2, and 36 at the top instead of 44), the basket fits; `ScooterArt`, `shared/RiderPose.luau`). CAR (or the phone's MY BIKE) puts your bike by the
kerb and seats you; it leans into turns, the cranks and wheels turn, the rider pedals (`client/BikeRider.luau`). Bike
gear at the shop (`bikeOnly` in `Config.Gear`): a basket (+2), panniers (+3), a trailer (+4, not on the cargo bike),
installed in the bike's gear slots. **Bike jobs** (`Config.Jobs.Bike`, the board's BIKE section): light cargo, 300–1 000
studs, 2–6 pieces by your room (bike + gear + your backpack), $90–240. Car jobs and missions still need a car; the phone
switches MY BIKE / CALL CAR when you own both.

## Your career and your gear (4.6)

**The career** (MENU → CAREER, or **C**): your rank and level, the XP to the next one (about how many deliveries), what
it opens and its reward, and the road from level 1 to 15 — every level's unlocks (job tiers and types, cars and their
stages, gear, guns, car guns, campaigns, garages, homes) and its reward (`Config.Levels.Rewards`: $500 at level 2 up to
$15 000 at 15, items, the Hi-Vis Orange paint at 5, the Iron Courier title at 10, Legend Chrome and Legend of the Last
Road at 15; paid once, `profile.levelRewards`). A level-up shows a card: what you unlocked, the reward, what comes next
(`shared/Career.luau` builds the road from Config, `client/CareerUi.luau` shows it).

**Gear** (Wrench Garage → GEAR, `Config.Gear`): bought per car, installed in the car's gear slots (`gearSlots`: the
Old Van 1 / 1 / 2 / 3 by stage, the Courier 2, the High-Roof 3, the Box Truck 3 / 3 / 4, the Freight Truck 4 …; free to
install or remove at the garage). The Hand Trolley (level 3, $600: 4 pieces at once), Ratchet Straps (level 4: the
cargo takes less damage), the Cooler Box (level 5: food stays fresh longer), the Roof Rack (level 7: +1 light piece, it
rides on the roof). You see each piece on the car (`profile.carGear`).

## Jobs you choose and get rated for (4.7)

**The board** offers three ordinary jobs on every tier you can take: always a short, safe one, and two of a long haul
(×1.15), a risky one (a forced modifier, ×1.1, bandits want it) and a bulk order; each row says why. REROLL a tier once
per refresh for $50 × its stars (`Config.Jobs.Choice`, the RerollTier remote). **Every job is rated** ★ / ★★ / ★★★
(`shared/JobRules.luau`, `Config.Jobs.Rating`): a star off for under 25% of the clock left, the cargo under 85% (two
under 50%), a wreck, a piece lost. ★★★ pays +20% and ×1.25 XP, ★ pays −10%; a **streak** of jobs rated ★★+ adds +5% each,
up to +25% (`profile.streak`; a ★ or a failed job resets it). **Licences** (`Config.Jobs.Licences`): ★★★ jobs need level 4
and 5 jobs rated ★★+ at ★★ or above; ★★★★ need level 7 and 10 such jobs at ★★★ or above (the board shows LICENCE 3 / 5,
the CAREER window your progress). Saves from before 4.7 with deliveries keep every tier their level opens.

## Cargo with rules, several drops, things on the road (4.8)

`Config.Jobs.CargoRules` (the maths in `shared/JobRules.luau`), on the board's jobs (not missions or the tutorial):
**fragile** cargo (cakes, vaccines, samples, electronics, paintings) loses condition when you brake hard, bump or hit
something ("CAREFUL — FRAGILE"); **food** (pizza, bread, groceries, soup, cakes) loses freshness every minute once picked
up (the contract shows "Fresh 82%"; under 70% a star off, the pay down to 0.7×; a Cooler Box halves it); **heavy** cargo
(barrels, strongboxes, furniture, generators) is a slow walk alone, normal on the hand trolley or with a crew mate;
**cash** brings the bandits sooner; **passengers** complain at every bump. Ratchet Straps take 40% off every condition
loss from driving. **Multi-drop** (`Config.Jobs.MultiDrop`): ★★★ and ★★★★ offers may have 2–3 drops, every piece tagged
FOR its customer. **Road events** (`Config.Jobs.RoadEvents`, one in three jobs at most one): a survivor waving by the
road (stop and they ride with you to the depot for a bonus), an ADD-ON pickup near your route (Y or TAKE IT within
15 s), a blocked street ahead. The admin panel can force each event.

## The admin panel (4.5)

P (or the ADMIN button on touch) opens it for admins (a Studio Play test, the place's owner, `Config.Admin.UserIds`);
every command is checked again on the server (`server/Admin.luau`, its header lists them all). At the top a **TARGET**:
you or any player in the server, and the tabs act on that player.
- **PLAYER**: GIVE ALL (everything unlocked and upgraded, +$1 000 000), money, XP, the driver level, items, guns, a
  car next to you, any car's stage, any upgrade track, the car gun, paints, heal, RESET MY SAVE (you only, asks twice).
- **OP** (toggles, kept over a respawn): god, fly (WASD toward the camera, Space up, Ctrl down, Shift faster), noclip,
  super jump, walk speed 1× / 2× / 4×, car boost ×2, hidden (no enemy goes after you), one-hit kills; bring the target
  to you or go to them, clear the bandits after them.
- **WORLD**: the time of day, kill every enemy on the map, freeze them all, a horde of 10 / 20 / 30, any enemy kind, a
  bandit car, traffic cars, teleport to any place.
- **JOBS & MISSIONS**: finish the stop or the whole job (paid as usual), start any job or mission, all missions at 3★,
  the challenges, titles. **ESTATE**: give or take properties, the home, the company's safe.
- **BUDDIES**: up to 3 NPC companions (`server/Buddy.luau`, `Config.Buddy`): they follow you, ride in your car's
  passenger seats, shoot the zombies and bandits around you (their kills pay nobody), fall and come back after 10 s;
  FOLLOW / STAY / GUARD, DISMISS. A friend at a full car's door takes a buddy's seat.

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
              GPS routes), Economy (prices, stats, pay, what fires from a car seat), Goal (6.5: the NEXT card's words), Net (remotes), Joints (Motor6D or
              AnimationConstraint), GunModels (the guns in the hands), Icons (the asset ids of the icon set and the logo),
              Levels (XP, levels, rank names; 3.2: fromLegacy, the old saves' XP), TrafficLanes (the traffic's lanes, turns and sidewalks), Crossings (3.9: the crosswalks, the traffic-light junctions and the light cycle), SoundSheet
              (where each sound and music loop sits in the two audio assets), Missions (3.0: the campaigns and missions,
              unlocking, the rating, the stars, the twists' pay; 3.2: the campaign chain `requires`, the computed
              mission levels levelOf, the DUO campaign; 6.8: 11 chapters of 6, only the next one starts, nextUp /
              statusOf / chapterState, creditFor (first time / replay), replayPay / replayXp, the retired ids), Cast
              (6.8: the story's people: name, title line, role line, place, NPC look), NpcLooks (6.8: the NPCs'
              clothes per role, moved from server/Npcs; the portraits use it too), Challenges (3.1: the 42 challenges, the
              counters, value / progress / doneCount / allTitles), Melee (3.9: punch or strike, the cone in front of
              you, the arm's swing curve), Boarding (3.10: getting in and out: the timing, the curve, the hand's
              reach, the doors' swing, the Boarding attribute), Freight (4.0: who takes what on a trolley or a jack, the
              walks, pallet room and places, the lock and the tip)
src/server/   Main (wiring, PLAY: the one Play listener), World (builds the world, also the homes, garages, towers,
              elevators, FOR SALE signs and office computers; 3.4: the repair bays, the GARAGE posts), PlayerData (saves, leaderstats; the save also holds the
              properties, the home and the business; 3.2: moves a 3.1 save's XP to the new curve once; 3.4: every
              car's damage), Vehicles (cars,
              seats, cargo slots, the roof turret of a car gun, the instant spawns and the home garage spot; 3.2: the
              back that opens, its hinges, BackOpen and the BackPrompt; 3.3: the five new vans' bodies, the
              UpgradeKit of the car's upgrades; 3.4: every car's damage kept, the car on a repair
              lift; 3.5: the stages' LOOKS, styleFor, the rebuild on a new stage; 4.0: the stretch, the Rusty Van's
              faults, the Freight Truck, the tyres and the folded trolley in the kit, TrolleyMount / JackMount /
              Exhaust; 3.10: getting in (the seat reserved,
              seated on time or cancelled), out (the CarDoor remote), the doors' DoorOpenAt / DoorCloseAt), Zombies (zombies and bandits, roadblocks, the roamers,
              who goes after whom), BanditCars (the chasing pickups, driven by the server), Gun (shots, server checked: the hand gun, the car gun or out of
              the window; 3.1: piercing rounds), Jobs (job board, stops, special jobs, crews, the zombie waves; 3.2: the DUO
              rules, drives DuoGates; 3.4: the cargo slots on the board, the bulk orders), Cargo (the cargo you carry, lead or board at a stop, the pieces in the vehicle;
              3.2: loading through the back, the pair lift; 4.0: pieces on a trolley, pallets on a jack, the tools' hints), Equipment (4.0: the
              hand trolley and the pallet jacks: take, push, stow, set down, go home), DuoGates (3.2: the TWIN SWITCHES gate, its two levers), Npcs (the R15 people: givers, receivers, kids, employers; 6.8: their looks from shared/NpcLooks), Animals (the
              horses: build, walk, lead rope, stalls), Items (consumables, supply crates), Shops (counters, showroom,
              purchases; 3.5: the three display cars, the stages; 6.6: ZDC Bags' bags), GearStall (6.12.2: the depot's gear stall,
              ZDC Bags and Last Stop Supplies; 6.6's BagKiosk before it), JobsSpot (6.12.2: the job board's booth), Admin (the admin commands, checked on the server), DayNight (the clock, the Night attribute,
              the night lights), Traffic (civilian cars and pedestrians, bandits among them), Crew (invitations, crews,
              the crew state), Ranking (the leaderboard rows), Estate (buying, selling, the home, car slots, the home
              respawn, the owners on the signs), CarCall (the chauffeur who drives your car to you), Business (your
              company: couriers, upgrades, the safe, online and offline earnings, the office computer), Missions (3.0: the
              MISSIONS window's state, START checked, the rewards, stars and crew credit when one is done; 3.4: the
              cargo slots at START; 6.8: a replay starts as one, Missions.creditFor pays), Garages (3.4: your cars at your garages, the garage window's TAKE OUT, the depot
              lot), Repair (3.4: the repair bays, the timer, the fee), Challenges
              (3.1: counts the stats from the other modules' hooks, the distance and the places visited, checks and
              pays the challenges, the lost packages' prompts, the campaign / secrets / Dead End rewards, the title over
              the head, the Challenges remote), CloseCombat (3.9: the holster, the Holstered attribute, the melee
              checked and dealt: the nearest enemy in the cone, MeleeAt / MeleeKind for the swing), Hand (6.1: what you hold,
              fists / bag / gun: the Hand remote, the Hand and Holstered attributes; Cargo sets a loaded bag down)
src/client/   Main, Menu (start screen), Hud (interface, the on-foot guide), Hotbar (6.0.1: the bottom bar, 6.1: the
              hand slots 1-3, the item slots 4-8 and what you carry), BagSway (6.1: the bag's pendulum, the BagSwing
              joint's only writer), KeyHints (6.1: the key hints under the top buttons, F1), Objective (6.5: the NEXT
              card, its words from shared/Goal.luau), TutorialUi (Marge's pages; 6.7: drives the arrow tour) and
              TutorialArrow (6.7: the tour's arrow, frame and caption), MapView (minimap, big map, GPS routes),
              Theme (3.6: the Postage & Trouble tokens), Ui (the shared pieces; 3.6: window, ticket, tag, dial, tactile),
              DispatchUi (3.6: the Dispatch board),
              CameraRig (GTA-style aim camera), ArmPose (the arms come up to aim or carry, seen by everybody),
              Drive (car controller, ice; 3.2: no throttle with the back open; 4.0: the torque curve), Shooting (aim, crosshair, tracers, hit
              numbers), CarVisuals (tyres, prompts, name tags; 3.2: swings the back, its prompt only for the crew; 4.0: the exhaust smoke), ZombieAnimator, AnimalAnimator (the horses' legs, neck and tail), AdminPanel (P),
              Weather (the day and night look; 3.0.1: the readable night, the town glow, your own light), Ui, Leaderboard (L), CrewPanel (K, the invitation card, the member's
              job strip and GPS), TrafficAnimator (smooths the traffic cars and spins their wheels; 3.9: colours the traffic lights), EstateUi (H, the
              real estate list and listings), BusinessUi (the company window at the office computer, the welcome-back
              card), Sounds (the music and every sound effect, N / SOUND), WeaponWheel (hold T), MissionsUi (6.8: who you work for: the
              clients' cards, the chosen chapter, the story path, START; 3.0: the MISSIONS window (U),
              the mission banner in the top stack, the celebration card; 3.1: the CHALLENGES, SECRETS and REWARDS
              tabs and the unlock popups; 3.2: the lock texts, the DUO badge, FIND CREW; 3.4: the 📦 needs N slots
              chip), MissionsLayout (6.8: the window's measures: wide or a strip on top), Portrait (6.8: the clients' busts in a
              ViewportFrame, from shared/NpcLooks), Secrets (3.1: hides the lost packages you found, animates the others nearby), GarageUi (3.4: the
              garage window, only your own GARAGE prompts, the repair timer card), Holster (3.9: B holsters / draws,
              V punches or strikes, the first aim or shot draws a holstered gun; ArmPose hides a holstered gun and
              swings the arm), CarBoarding (3.10: plays your move into and out of a seat, E in a seat gets you out;
              ArmPose puts the hand on the handle, CarVisuals swings the door, CameraRig eases into the car's view),
              TouchLayout (4.2: where the touch buttons, the right column and the contextual action sit; pure, tested),
              TouchControls (4.2: SPRINT, and EXIT / PUT DOWN / LET GO / SET DOWN in the hand button's place)
tests/        run_tests.py runs every *_test.luau: logic (Economy, Map, the zombie waves and roamers), cargo (pieces
              and pay), roads (the GPS), cargun (car guns, one-handed guns, which cars mount a gun, what fires from a
              seat), icons (every picture has its id slot, every gun, item, cargo and landmark has an icon), levels
              (XP and ranks; 3.2: the whole progression: the gear and estate levels, the XP curve against the story
              path, the old saves keep their level), jobs25 (the 2.5 jobs and places), traffic (lanes, turns, spawn spots, sidewalks; 3.9: the light cycle, the light junctions, the crosswalks); the
              2.6 real estate checks are in logic (every property placed, no overlaps, the towers and offices, the
              roads to every property, the landmarks) and so are the 3.0 places (every one placed, on its road, with
              its cargo spot); audio (every sound has its region, every gun its shot); missions (the 11 campaigns and
              110 missions valid against Config and Map, the design rules, unlocked, rate, stars, twistPay; 3.2: the
              campaign chain, the computed levels, the DUO rules, the old saves' started campaigns); 3.1:
              challenges (the list, the must-have goals, the titles, the hidden ones, the helpers on a fake profile),
              gear (piercing rounds, the paint finishes, every exclusive item a reward) and the lost packages in logic
              (one per place, near it, in bounds, dry, off the roads); 3.2: cargo also checks the back's extra
              steps stay quick holds; 3.3: logic checks the car tracks per car and the old saves'
              migration, levels the five new vans (levels and prices together), cargun that every dealer car takes
              a car gun, and run_tests.py reads Vehicles.luau's STYLES: every car has a body, every dealer car cargo
              slots and a back; 3.4: capacity (the capacities, what every job and every one of the 110 missions
              needs against the car that does it; the repair's time and fee; the garages; 3.5: the stages, the Old Van
              2 → 3 → 4, 6+ only in the Box Truck, every mission fits a car and a stage by its level, the early
              campaigns the Old Van, the big loads say so, the rack migration), run_tests.py checks every car's
              capacity is its body's slot count (3.5: and every stage's its look's), levels the early garages, logic the cheap first levels;
              3.9: melee (the punch and the strike, the reach cone, the swing curve); 3.10: boarding (the move's timing,
              a late start, the curve, the hand, the doors' swing); 4.0: freight (the trolley and jack rules, pallet
              places, the Freight Run, the warehouse and receiving docks)
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
animations: the aiming arms (`client/ArmPose.luau`; 3.9: the melee swing too), the bandits' raised guns, the ragdolls. The horses are not
characters: they have their own `Motor6D`s, swung on the clients by `client/AnimalAnimator.luau`.

**Enemies** are R15 bodies made from a HumanoidDescription (blocky custom rigs as the fallback) animated by their
Animator, the blocky ones on the clients by joint transforms. Cars and enemies do not collide physically (collision groups): running one over and grabbing the car are
computed on the server from the car's box (`server/Zombies.luau`).

## Tests

```bash
python3 zombie-delivery/tests/run_tests.py [path to the luau binary]
```

Runs every `tests/*_test.luau` (logic with the 2.6 real estate, the 3.0 places and the 3.1 lost packages, cargo,
roads, cargun, icons, levels with the 3.2 progression, jobs25, traffic, audio, missions with the 3.2 campaign chain
and DUO campaign, 6.8's missions_story (the chapters' order and locks, first time and replays, the saves, the cast)
and missions_layout (the window on a monitor and a phone), challenges, gear, the 3.4 capacity test, the 3.9 melee test, the 4.0 vehicles40 test: the slow
van and its stages, the torque curve, the van's save migration, the pallets, the Hand Trolley, the Freight Truck, and
the 4.2 touchlayout test: the touch buttons on phones and tablets, clear of each other and of the HUD) and
compiles every module (`luau-compile -O0 -g2`: at most 200 registers a
function, as Studio compiles). Needs the standalone Luau CLI
(https://github.com/luau-lang/luau/releases).

**Testing in Studio**: the admin panel (P, or the ADMIN button top right) unlocks everything, gives money, spawns
cars, puts any car gun on your car (or none), guns and enemies, teleports to every place, starts any job, sets the
driver level (the LV buttons, LEVEL -1 / +1; UNLOCK also sets the top level and, 3.3, maxes every owned car's
upgrades, like MAX UPGRADES), sets the time of day (dusk, night,
dawn … through `DayNight.setClock`), heals, finishes the current stop and switches god mode. The **Estate, company**
tab gives every property (or one), takes them all, sets the home (or the depot), teleports to any property and
fills, adds $50,000 to or empties the company safe (UNLOCK also gives every property and, without a home, the most
expensive mansion as the home). The **Missions** tab starts any of the 66 missions now (locks ignored; a running job
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

A crew leaderboard, company vans driving past in traffic.
