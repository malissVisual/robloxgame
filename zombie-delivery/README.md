# Zombie Delivery

A second Roblox game in this repository (Merge Blades lives in the root). **You run a delivery company in a city
full of zombies**: take a job, drive the cargo to the customer while zombies chase you, run them over or shoot them
with the gun on your roof, get paid, and buy better cars, guns and upgrades.

Everything is built in code (the city, the cars, the zombies, the interface), so the game needs no assets: open an
empty place and sync.

## Running

```bash
node tools/rojo-sync.js zombie-delivery
```

(from the repository root). In Studio open a **new Baseplate place** (not the Merge Blades one), then
**Plugins → Rojo → Connect** and **Play**. On a Mac you can double-click `zombie-delivery/spust-zombie-delivery.command`
instead (git pull + the sync).

A Play test in Studio without API access cannot save, so it starts with `Config.StudioStartMoney` ($25,000) to try the
shop. A published game starts with `Config.StartMoney` and saves to the DataStore `Config.DataStoreName`.

## How to play

| Input | PC | Touch |
|---|---|---|
| Drive | WASD / arrows | thumbstick |
| Shoot where you aim | hold left mouse | – |
| Shoot the nearest zombie (auto-aim) | hold F | hold FIRE |
| Get out | Space | jump button |
| Get in | walk to the car, E | tap the prompt |

1. You spawn at the **depot** (Zombie Delivery Co., the green circle in the middle of the city) and get your car on the
   road in front of it. The depot is safe: no zombies, the car is repaired there and the shop only works there.
2. **JOBS** opens the job board: one offer for every danger level, measured from where you are.
   ★ near, a few walkers · ★★ further, runners, a horde at the door · ★★★ far across the city, brutes, a big horde.
3. Follow the **arrow over your car** and the **yellow beacon**. Zombies keep coming while the job runs.
   * Fast (18+ studs/s) you **run them over**. A brute survives a hit, slows you down and dents the car.
   * Slow or standing, they **grab the car** (sides, back, roof) and bite it until you shoot them off.
   * Every bite costs car health **and cargo condition**.
4. **Stop in the yellow circle** to deliver: the pay × the cargo condition (50 % … 100 %), + 25 % for finishing in
   the first half of the time, + $3 for every zombie killed on the way. Every kill also pays on the spot.
   The job fails when the timer runs out or the car is destroyed (press **CAR** for a new one).
5. **GARAGE** (in the depot): cars, guns and upgrades.

## Content

* **Cars**: Old Van (free), Pickup, Muscle Car, Armored Truck, Monster Truck (speed, health, ram power).
* **Guns**: Roof Pistol (free), SMG, Shotgun (7 pellets), Minigun. A head hit is a ×2 crit.
* **Upgrades** (5 levels each): Engine, Armor, Ram Plow, Gun Damage, Fire Rate.
* **Zombies**: Walker, Runner, Brute.

All numbers are in `src/shared/Config.luau`; the formulas are in `src/shared/Economy.luau`.

## Code

```
src/shared/   Config (all numbers), Economy (prices, stats, pay), CityGrid (blocks, roads, addresses), Net (remotes)
src/server/   Main (wiring, shop), World (builds the city), PlayerData (saves), Vehicles (cars), Zombies,
              Gun (the roof gun, server checked), Jobs (job board, deliveries, zombie director)
src/client/   Main, Drive (car controller), Shooting (gun input, tracers, numbers), ZombieAnimator, Hud, Ui
tests/        logic test of Economy and CityGrid
```

**Driving** is arcade, not wheel physics: the wheels are welded frictionless colliders and the chassis has a
`LinearVelocity` (in the ground plane, gravity still works) and an `AngularVelocity` (turning, keeps the car upright).
The driver's client owns the car and sets both from the VehicleSeat's throttle / steer (`client/Drive.luau`).

**Zombies** are custom rigs (R15 humanoid type so `HipHeight` works at any scale) animated on the clients by joint
transforms (`client/ZombieAnimator.luau`). Cars and zombies do not collide physically (collision groups): running one
over and grabbing the car are computed on the server from the car's box (`server/Zombies.luau`).

## Tests

```bash
python3 zombie-delivery/tests/run_tests.py [path to the luau binary]
```

Needs the standalone Luau CLI (https://github.com/luau-lang/luau/releases).

## Ideas for later

Night shifts (double pay, more zombies), spitters and zombie dogs, a boss customer, co-op (one drives, one shoots),
nitro, more maps, sounds and music, hiring AI couriers that earn while you are away.
