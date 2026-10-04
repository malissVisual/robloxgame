# Zombie Delivery

A second Roblox game in this repository (Merge Blades lives in the root). **You run a delivery company** in a world
gone wrong: take a job, pick the cargo up, drive it across the map while bandits shoot at you from roadblocks and
zombies chase you, unload it under fire, get paid, and buy better cars, guns, items and upgrades. Friends ride along
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
| Drive | WASD / arrows | thumbstick |
| Aim (GTA style: the mouse is locked, the camera follows it, crosshair in the middle) | move the mouse | – |
| Aim on foot (over the shoulder, the gun goes up; walking you turn where you go, like GTA) | hold right mouse | – |
| Shoot (driver: roof gun, passenger: out of the window, on foot: the gun in your hand) | left mouse | FIRE |
| Shoot the nearest enemy (auto-aim) | hold F | hold FIRE |
| Switch gun | Q (or click the weapon bar) | the weapon bar |
| Items (repair, medkit, nitro, molotov, mine) | 1 – 5 | the hotbar |
| Free the mouse (click the interface) | hold Alt (any window frees it too) | – |
| Jobs / map / backpack | J / M / B | the buttons |
| Get in your car / ride in a friend's car | E / R | the prompt |
| Get out | Space | jump button |

1. The **start screen** flies over the city; **PLAY** starts the game and brings your car.
2. You start at the **depot** in the middle of Downtown. Around it is the **safe zone** (green line) with the shops:
   **Dead End Motors** (cars, walk among the showroom cars), **Lead & Co.** (guns), **Wrench Garage** (upgrades, paint
   jobs, free repairs inside), **Last Stop Supplies** (items). Walk in and use the counter.
3. **JOBS** (or the job board at the depot): one special job and one delivery of every danger level.
   * Every delivery has stops: **pick up** (stop in the blue circle and hold still while it is loaded), then
     **deliver** (stop in the yellow circle and hold still while it is unloaded).
   * ★ near and quiet · ★★ bandit roadblocks · ★★★ across the city, gunners and brutes · ★★★★ INSANE: the far places.
   * Modifiers on the far jobs: RUSH (less time), FRAGILE (hits cost double), HEAVY LOAD (slower car), WANTED
     (twice the enemies), each pays more.
   * Sometimes the **Winter Run** is on the board: through the tunnel and over the **frozen lake** (the car slides on
     the ice) to the Ski Lodge.
   * **Work for the people who run things** (the WORK HERE boards, ★ yellow on the map). They lend you their vehicle
     for the job, and after **3 jobs it is yours**:
     * **Sunny Hill School** (Suburbs): School Run, pick up kids at 3 homes → **School Bus**
     * **Military Base** (north, through the tunnel): Army Supply, ammo from the docks → **Armored Truck**
     * **Frosty's Ice Cream** (Harbor): Ice Cream Route, sell at 4 stops → **Ice Cream Truck**
     * **Big Move Movers** (Downtown): Moving Day, furniture to a new home → **Moving Truck**
     * **Old Farm** (west): Farm Run, food to two city markets → **Monster Truck**
4. **Enemies**: **bandit pickups** come after you on the road (from ★★ up), ram you and shoot from the bed; destroy
   them with guns, ramming, mines or molotovs ($75). **Bandits** and **gunners** on foot set up roadblocks ahead of
   you, camp at the far places and shoot your car. Bandits next to your car **steal your cargo** bit by bit (all of
   it gone = the job fails). Zombies (walkers, runners, brutes, soldiers at the base) are rarer: run them over or
   shoot them; they grab a slow car and bite it until you shoot them off.
   A wrecked car (or dying) does **not** end the job: some cargo is lost, press CAR for a new car (the company
   vehicle on a special job) and keep going while the time lasts.
5. The pay: the job's pay × cargo condition (50 – 100 %), + 25 % for finishing in the first half of the time,
   + $3 per enemy killed. Every kill also pays on the spot, and so do the **supply crates** (? on the map).
6. **Crews**: friends press R at your car to ride along. Their kills count for your job, each passenger gets half of
   the pay and you +15 % per passenger.

## The world

Downtown (the depot and the shops), the river with **Rust Bridge** and **Old Bridge**, the **Harbor** (warehouses,
containers, the docks on the sea), the **Suburbs**, the **North Highway** past the Gas Station through the
**Mount Rot tunnel** to the snowy north: the **Military Base** and, over the frozen lake, the **Ski Lodge**; the
**West Highway** to the **Radio Station** and the **Old Farm**. The minimap (bottom left; top left on touch screens) and
the big map (M) show it all. The big map lists every shop, employer and far place with what you can do there: click
one to set the **GPS** (an arrow over your car and a light beam). Big icons over the buildings show them in the world.

## Content

* **Cars**: at Dead End Motors the Old Van (free), the Pickup and the Muscle Car; earned by working: School Bus,
  Armored Truck, Ice Cream Truck, Moving Truck, Monster Truck.
* **Guns** (Lead & Co.): Pistol (free), SMG, Shotgun, Hunting Rifle, Minigun, Grenade Launcher. Head hits are ×2.
* **Upgrades** (Wrench Garage, 5 levels each): Engine, Handling, Armor, Ram Plow, Gun Damage, Fire Rate; paint jobs.
* **Items** (Last Stop Supplies): Repair Kit, Medkit, Nitro, Molotov, Landmine.
* **Enemies**: Bandit, Gunner, Walker, Runner, Brute, Soldier.

All numbers are in `src/shared/Config.luau`, the world layout in `src/shared/Map.luau`, the formulas in
`src/shared/Economy.luau`.

## Code

```
src/shared/   Config (all numbers), Map (world layout, roads, addresses), Economy (prices, stats, pay), Net (remotes)
src/server/   Main (wiring, PLAY), World (builds the world), PlayerData (saves, leaderstats), Vehicles (cars, seats),
              Zombies (zombies and bandits, roadblocks), BanditCars (the chasing pickups, driven by the server),
              Gun (shots, server checked), Jobs (job board, stops, special jobs, crews), Items (consumables, supply
              crates), Shops (counters, showroom, purchases)
src/client/   Main, Menu (start screen), Hud (interface), MapView (minimap, big map), CameraRig (GTA-style aim camera),
              Drive (car controller, ice),
              Shooting (aim, tracers, hit numbers), CarVisuals (tyres, prompts, name tags), ZombieAnimator, Weather, Ui
tests/        logic test of Economy and Map
```

**Driving** is arcade, not wheel physics: invisible frictionless wheel colliders and two constraints on the chassis
(`LinearVelocity` in the ground plane, `AngularVelocity` for turning and staying upright). The driver's client owns the
car and sets both from the VehicleSeat (`client/Drive.luau`); on ice the velocity follows the nose only slowly.

**Enemies** are custom rigs (R15 humanoid type so `HipHeight` works at any scale) animated on the clients by joint
transforms. Cars and enemies do not collide physically (collision groups): running one over and grabbing the car are
computed on the server from the car's box (`server/Zombies.luau`).

## Tests

```bash
python3 zombie-delivery/tests/run_tests.py [path to the luau binary]
```

Needs the standalone Luau CLI (https://github.com/luau-lang/luau/releases).

## Ideas for later

More special jobs (an armoured cash transport, a hospital run with a patient, a pizza
rush with a timer per stop), night shifts, sounds and music, hiring AI couriers that earn while you are away.
