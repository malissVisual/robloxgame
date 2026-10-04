# Zombie Delivery

A second Roblox game in this repository (Merge Blades lives in the root). **You run a delivery company** in a world
gone wrong: take a job, carry the cargo to your vehicle with your own hands (or lead the horses on a rope), drive it
across the map while bandits shoot at you from roadblocks and zombies chase you, carry it to the receiver under fire,
get paid, and buy better cars, guns, items and upgrades. Friends ride along
in your passenger seats, shoot out of the windows and share the pay.

Everything is built in code (the world, the cars, the enemies, the interface), so the game needs no assets: open an
empty place and sync.

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
| Shoot (driver: roof gun, passenger: out of the window, on foot: the gun in your hand) | left mouse | FIRE |
| Shoot the nearest enemy (auto-aim) | hold F | hold FIRE |
| Switch gun | Q (or click the weapon bar) | the weapon bar |
| Items (repair, medkit, nitro, molotov, mine) | 1 – 5 | the hotbar |
| Free the mouse (click the interface) | hold Alt (any window frees it too) | – |
| Jobs / map / backpack | J / M / B | the buttons |
| Get in your car / ride in a friend's car | E / R | the prompt |
| Get out | Space | jump button |
| Pick up / Load / Take out / Hand over / Lead a horse (on foot, at a stop) | hold E | the prompt |
| Put down / Let go (to shoot; anybody of the crew can pick it up again) | G (gamepad B) | the prompt |
| Admin panel (testing tools; only for admins: a Studio Play test, the place's owner, `Config.Admin.UserIds`) | F7 | the ADMIN button |

While you carry something (or lead a horse) you cannot shoot, sprint or drive, and you walk slower.

1. The **start screen** flies over the city; **PLAY** starts the game and brings your car.
2. You start at the **depot** in the middle of Downtown. Around it is the **safe zone** (green line) with the shops:
   **Dead End Motors** (cars, walk among the showroom cars), **Lead & Co.** (guns), **Wrench Garage** (upgrades, paint
   jobs, free repairs inside), **Last Stop Supplies** (items). Walk in and use the counter.
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
     (twice the enemies), each pays more.
   * Sometimes the **Winter Run** is on the board: through the tunnel and over the **frozen lake** (the car slides on
     the ice) to the Ski Lodge.
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
4. **Enemies**: **bandit pickups** come after you on the road (from ★★ up), ram you and shoot from the bed; destroy
   them with guns, ramming, mines or molotovs ($75). **Bandits** and **gunners** on foot set up roadblocks ahead of
   you, camp at the far places and shoot your car. Bandits next to your car **steal whole pieces** of your cargo.
   Zombies (walkers, runners, brutes, soldiers at the base) are rarer: run them over or shoot them (a **headshot
   kills** at once, a brute takes 4×); they grab a slow car and bite it until you shoot them off. The crosshair is a
   **dot** that turns white over an enemy; an **X** shows only on a headshot.
   A wrecked car (or dying) does **not** end the job: a wreck ruins 25 % of the pieces in it (at least one), press
   CAR for a new car (the company vehicle on a special job) and keep going while the time lasts.
5. The pay: the job's pay × the share of the pieces delivered × cargo condition (50 – 100 %), + 25 % for finishing
   in the first half of the time, + $3 per enemy killed; an ordinary delivery also pays $15 per piece. The job fails
   only if nothing arrived. Every kill also pays on the spot, and so do the **supply crates** (? on the map).
6. **Crews**: friends press R at your car to ride along. Their kills count for your job, each passenger gets half of
   the pay and you +15 % per passenger.

## The world

Downtown (the depot and the shops), the river with **Rust Bridge** and **Old Bridge**, the **Harbor** (warehouses,
containers, the docks on the sea, the **Harbor Fuel Depot** south of the warehouses), the **Suburbs** and, down
**Riding School Lane**, the **Riverside Riding School** by the river, the **North Highway** past the **Gas Station** (an
employer now) through the **Mount Rot tunnel** to the snowy north: the **Military Base** and, over the frozen lake, the
**Ski Lodge**; the **West Highway** to the **Radio Station** and the **Old Farm**, with the **Ranch Road** off it to
**Silver Spur Ranch**. The minimap (bottom left; top left on touch screens) turns with the camera; it and the big map
(M) show it all. The big map lists every shop, employer and far place with what you can do there: click one to set
the **GPS**. The route there is drawn along the roads on both maps (yellow to the job's next stop, purple to the GPS
point), with an arrow over your car and a light beam. Big icons over the buildings show them in the world.

## Content

* **Cars**: at Dead End Motors the Old Van (free), the Pickup and the Muscle Car; earned by working: School Bus,
  Armored Truck, Ice Cream Truck, Moving Truck, Monster Truck, Livestock Truck, Fuel Truck.
* **Guns** (Lead & Co.): Pistol (free), SMG, Shotgun, Hunting Rifle, Minigun, Grenade Launcher, each with its own model in
  your hand (`shared/GunModels.luau`, the bandits carry the same pistol and rifle): a muzzle flash and a recoil kick on
  every shot, the tracers start at the muzzle. A headshot kills. Earned by working, not sold: the **Ranch Revolver**
  (Silver Spur Ranch) and the **Army Carbine** (Military Base).
* **Upgrades** (Wrench Garage, 5 levels each): Engine, Handling, Armor, Ram Plow, Gun Damage, Fire Rate; paint jobs.
* **Items** (Last Stop Supplies): Repair Kit, Medkit, Nitro, Molotov, Landmine.
* **Enemies**: Bandit, Gunner, Walker, Runner, Brute, Soldier.
* **People**: the employers, givers, receivers and kids are R15 NPCs that talk, turn to you and walk; the ranch's
  **horses** graze, walk on a rope and ride in the livestock truck's stalls.

All numbers are in `src/shared/Config.luau`, the world layout in `src/shared/Map.luau`, the formulas in
`src/shared/Economy.luau`.

## Code

```
src/shared/   Config (all numbers), Map (world layout, roads, addresses, cargo spots), Roads (the road graph and the
              GPS routes), Economy (prices, stats, pay), Net (remotes), Joints (Motor6D or AnimationConstraint),
              GunModels (the guns in the hands)
src/server/   Main (wiring, PLAY), World (builds the world), PlayerData (saves, leaderstats), Vehicles (cars, seats,
              cargo slots), Zombies (zombies and bandits, roadblocks), BanditCars (the chasing pickups, driven by the
              server), Gun (shots, server checked), Jobs (job board, stops, special jobs, crews), Cargo (the cargo you
              carry, lead or board at a stop, the pieces in the vehicle), Npcs (the R15 people: givers, receivers,
              kids, employers), Animals (the horses: build, walk, lead rope, stalls), Items (consumables, supply
              crates), Shops (counters, showroom, purchases), Admin (the admin commands, checked on the server)
src/client/   Main, Menu (start screen), Hud (interface, the on-foot guide), MapView (minimap, big map, GPS routes),
              CameraRig (GTA-style aim camera), ArmPose (the arms come up to aim or carry, seen by everybody),
              Drive (car controller, ice), Shooting (aim, crosshair, tracers, hit numbers), CarVisuals (tyres,
              prompts, name tags), ZombieAnimator, AnimalAnimator (the horses' legs, neck and tail), AdminPanel (F7),
              Weather, Ui
tests/        run_tests.py runs every *_test.luau: logic (Economy, Map), cargo (pieces and pay), roads (the GPS)
```

**Driving** is arcade, not wheel physics: invisible frictionless wheel colliders and two constraints on the chassis
(`LinearVelocity` in the ground plane, `AngularVelocity` for turning and staying upright). The driver's client owns the
car and sets both from the VehicleSeat (`client/Drive.luau`); on ice the velocity follows the nose only slowly.

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

Runs every `tests/*_test.luau` (logic, cargo, roads). Needs the standalone Luau CLI
(https://github.com/luau-lang/luau/releases).

**Testing in Studio**: the admin panel (F7, or the ADMIN button top right) unlocks everything, gives money, spawns
cars, guns and enemies, teleports to every place, starts any job, sets the time of day, heals, finishes the current
stop and switches god mode. It
is there for a Studio Play test, for the owner of a user-owned place and for the user ids in `Config.Admin.UserIds`;
the server checks every command again.

## Ideas for later

More special jobs (an armoured cash transport, a hospital run with a patient, a pizza
rush with a timer per stop), night shifts, sounds and music, hiring AI couriers that earn while you are away.
