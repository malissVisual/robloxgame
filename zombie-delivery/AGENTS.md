# Zombie Delivery: rules for the AI helpers (Codex, Claude Code)

Two AI helpers build this game for the owner: **Claude Code** and **Codex**. They help each other through this repository.
This file holds the rules both follow. `COLLAB.md` next to it is the shared task board.

Read `README.md` first. It describes the whole game: missions, challenges, the HUD, the progression and the code map.

## The repository
- The game is in `zombie-delivery/` and is synced into Roblox Studio by Rojo (`node tools/rojo-sync.js zombie-delivery`).
- Merge Blades is archived in `archive/merge-blades/`. Do not change it unless the owner asks. The root project targets Zombie Delivery, and the shared synchronizer stays in `tools/rojo-sync.js`.
- The owner pulls one branch, **`claude/adoring-mendel-v77f7v`**. Only work that lands there reaches the game.

## How we work together
1. **Before starting, read `COLLAB.md`.** Pick a task from "Ideas / next", or write your own in "In progress" with your name (Codex / Claude), the files you will touch and the date. Commit that change to the board first, so the other helper sees it.
2. **One file, one helper at a time.** Do not edit a file the other helper lists under "In progress". If you must, write a note under "Questions / handoff" instead.
3. **Branches:**
   - **Codex** works on its own branch `codex/<topic>` (e.g. `codex/hud-icons`), based on the latest `claude/adoring-mendel-v77f7v`. It pushes there and writes the branch under "Ready for review".
   - **Claude** reviews the branch, runs the checks, fixes small things, merges it into `claude/adoring-mendel-v77f7v` and moves the entry to "Done".
   - Claude works on `claude/adoring-mendel-v77f7v` directly and lists bigger work in "In progress" too.
4. **Small commits** with a clear message (`Zombie Delivery <version>: what changed`). The `Config.Version` bump is done by whoever merges.
5. **When done**, move your entry to "Ready for review" (Codex) or "Done" (Claude). Write in one or two lines what changed and what to test in Studio.
6. **Found something in the other helper's area** (a bug, an idea)? Write it under "Questions / handoff". Do not rewrite it silently.

## Code rules
- Luau `--!strict` for Roblox. Every module starts with a header comment that says what it does. Follow the surrounding style: names, comments, the `Ui` / `Theme` helpers for interfaces, `shared/Icons.luau` for pictures, and emoji fallbacks.
- **The 200-register limit:** a Luau function may hold at most 200 locals/registers. Roblox Studio compiles with `-O0 -g2`, where constants count too.
  - `src/client/Hud.luau` is right at that limit: **never add new top-level locals there**. Put new code inside its existing `do ... end` blocks or in a new module.
- **Joints:**
  - Characters' joints are AnimationConstraints (the Avatar Joint Upgrade). Never write `C0` on them.
  - Use `src/shared/Joints.luau` and write `Transform` in `RunService.PreSimulation`.
- **Server first:** the server decides money, items, missions and rewards. The client only asks through the remotes in `src/shared/Net.luau`.
- **Numbers live in `src/shared/Config.luau`:** prices, levels and tuning. The mission data lives in `src/shared/Missions.luau`; the challenges in `src/shared/Challenges.luau`.
- **Performance:**
  - throttle loops (0.1–0.5 s);
  - no `GetDescendants` every frame;
  - clean up connections and instances.

## Checks before you push
From `zombie-delivery/`:
```
python3 tests/run_tests.py <path to the luau binary>
```
- **What it runs:**
  - every `tests/*_test.luau` must print `ALL CHECKS PASSED`;
  - every module must compile at `-O0 -g2` (the register limit) with `luau-compile`, which sits next to the `luau` binary.
- **The tools:**
  - The Luau CLI is the `luau` and `luau-compile` binaries from https://github.com/luau-lang/luau/releases.
  - An optional type check: `luau-lsp analyze` (https://github.com/JohnnyMorganz/luau-lsp/releases) with a Rojo sourcemap and the Roblox definitions.
- **If you cannot run the checks**, say so in `COLLAB.md`, and Claude runs them during the review.

## Good areas for each helper
These are suggestions; the board decides.
- **Codex:** graphics and art (`art/`, icons in `src/shared/Icons.luau`), sounds (`art/audio/make_audio.py`), UI polish of single windows, map decoration in `src/server/World.luau` (one place at a time), mission and challenge texts, balancing numbers in `Config.luau`, new tests.
- **Claude:** game systems that span many files (missions, jobs, cargo, vehicles, crews, saving), the HUD layout, merging and reviewing, releases.
