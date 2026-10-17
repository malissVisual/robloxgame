# Deliveros: rules for the AI helpers (Codex, Claude Code)

Two AI helpers build this game for the owner: **Claude Code** and **Codex**. They help each other through this repository.
This file holds the rules both follow. `COLLAB.md` next to it is the shared task board.

Read `README.md` first. It describes the whole game: the lobby, the runs, the danger, loot, the crew, your warehouse,
saving and the code map.

## The game is the sandbox (10.5)
- Since 10.5 the game is only what was the 8.0 sandbox: the lobby, the runs into the countryside's houses and the
  warehouse. The old city game (Zombie Delivery 1.0 – 7.x: deliveries, missions, the city, the phone, guns, bikes,
  traffic, day and night) is gone, with its code, tests, tools, art and designs. It is in git's history up to 10.4.
- Do not bring city code back, and do not build on it. Work on what the game has; if an idea needs something the city
  had, take it from git's history into a new module of the game.
- Many names still say Sandbox (`SandboxBoot`, `SandboxMap`, `Config.Sandbox`): they are the game's.

## The repository
- The game is in `zombie-delivery/` and is synced into Roblox Studio by `node tools/rojo-sync.js zombie-delivery`
  from the repository root (keep that command working; `node tools/rojo-sync.test.js` tests the sync).
- Merge Blades is archived in `archive/merge-blades/`. Do not change it unless the owner asks. The root project targets
  this game, and the shared synchronizer stays in `tools/rojo-sync.js`.
- The owner pulls **`main`** (the default branch). Only work that lands on `main` reaches the game. Claude's working
  branch is `claude/adoring-mendel-v77f7v`; every finished version goes from there to `main` through a pull request.

## How we work together
1. **Before starting, read `COLLAB.md`.** Pick a task from "Ideas / next", or write your own in "In progress" with your name (Codex / Claude), the files you will touch and the date. Commit that change to the board first, so the other helper sees it.
2. **One file, one helper at a time.** Do not edit a file the other helper lists under "In progress". If you must, write a note under "Questions / handoff" instead.
3. **Branches:**
   - **Codex** works on its own branch `codex/<topic>` (e.g. `codex/loot-sparkle`), based on the latest `main`. It pushes there and writes the branch under "Ready for review".
   - **Claude** reviews the branch, runs the checks, fixes small things, merges it into `claude/adoring-mendel-v77f7v`, brings that to `main` (a pull request) and moves the entry to "Done".
   - Claude works on `claude/adoring-mendel-v77f7v` directly and lists bigger work in "In progress" too.
4. **Small commits** with a clear message (`Deliveros <version>: what changed`). The `Config.Version` bump (and the two
   `BuildStamp.luau` files with it) is done by whoever merges.
5. **When done**, move your entry to "Ready for review" (Codex) or "Done" (Claude). Write in one or two lines what changed and what to test in Studio.
6. **Found something in the other helper's area** (a bug, an idea)? Write it under "Questions / handoff". Do not rewrite it silently.

## Code rules
- Luau `--!strict` for Roblox. Every module starts with a header comment that says what it does (what the game does,
  not what the city did). Follow the surrounding style: names, comments, the `Ui` / `Theme` / `CardKit` helpers for
  interfaces, and emoji for icons.
- **The 200-register limit:** a Luau function may hold at most 200 locals/registers. Roblox Studio compiles with `-O0 -g2`, where constants count too.
  - `src/client/Hud.luau` has been right at that limit: **never add new top-level locals there**. Put new code inside its existing `do ... end` blocks or in a new module.
- **Joints:**
  - Characters' joints are AnimationConstraints (the Avatar Joint Upgrade). Never write `C0` on them.
  - Use `src/shared/Joints.luau` and write `Transform` in `RunService.PreSimulation`.
- **Server first:** the server decides money, loot, the collection, the upgrades and rewards. The client only asks
  through the remotes in `src/shared/Net.luau`.
- **Numbers live in `src/shared/Config.luau`:** prices, levels and tuning. The houses' layouts are
  `src/shared/HouseLayout.luau` and `src/shared/Layouts/`, the furniture and collectibles `src/shared/FurnitureLooks.luau`;
  the lobby's and the countryside's plans are `design/lobby/plan.py` and `design/countryside/plan.py` (their
  `tools/*/sandboxmap.py` write `src/shared/SandboxMap.luau`'s sections).
- **Saves stay byte-compatible:** the store `Config.Sandbox.Store`, its keys (and the save slots' own), the lock, every
  field with its `*Kept` flag and `rewards`' short keys (README, **Saving**). Never rename or drop one without a
  migration the owner agreed to.
- **Performance:**
  - throttle loops (0.1–0.5 s);
  - no `GetDescendants` every frame;
  - clean up connections and instances.

## Checks before you push
From `zombie-delivery/`:
```
python3 tests/run_tests.py <path to the luau binary>
python3 tools/phone-ui/check.py <path to the luau binary>
python3 tools/check-requires.py
```
- **What they run:**
  - every `tests/*_test.luau` must print `ALL CHECKS PASSED`, and `run_tests.py` must end with `ALL TEST FILES PASSED`;
  - every module must compile at `-O0 -g2` (the register limit) with `luau-compile`, which sits next to the `luau` binary;
  - `run_tests.py` also checks the build stamps, the plans' data (`tools/countryside/sandboxmap.py`,
    `tools/lobby/sandboxmap.py`) and the Blender imports (`tools/sprinter/`, `tools/warehouse/`, `tools/fixtures-art/`);
  - `tools/phone-ui/check.py` checks the windows on phones, computers and gamepads; `tools/check-requires.py` that every
    require resolves where Rojo puts the module.
- **The tools:**
  - The Luau CLI is the `luau` and `luau-compile` binaries from https://github.com/luau-lang/luau/releases.
  - An optional type check: `luau-lsp analyze` (https://github.com/JohnnyMorganz/luau-lsp/releases) with a Rojo sourcemap and the Roblox definitions.
- **If you cannot run the checks**, say so in `COLLAB.md`, and Claude runs them during the review.

## Good areas for each helper
These are suggestions; the board decides.
- **Codex:** graphics and art (the owner's Blender models in `design/blender-*`, the store art in `design/store-art/`),
  sounds (`art/audio/make_audio.py`), UI polish of single windows, the lobby's and the countryside's decoration (their
  plans, `server/LobbyWorld.luau`, `shared/CountryLooks.luau`; one place at a time), the houses' furniture and layouts,
  texts, balancing numbers in `Config.luau`, new tests.
- **Claude:** game systems that span many files (the runs, the danger, loot, the crew, the moves, the warehouse, the
  trades, saving), the HUD layout, merging and reviewing, releases.
