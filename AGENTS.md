# AI helpers in this repository

This repository holds two Roblox games:
- **Zombie Delivery**, the active game, in `zombie-delivery/`; the root `default.project.json` also targets it.
- **Merge Blades**, archived in `archive/merge-blades/` (its original source, project, tools and designs).

The shared synchronizer remains at `tools/rojo-sync.js`. From the repository root, the owner runs
`node tools/rojo-sync.js zombie-delivery`. Keep this command working.

When you work on **Zombie Delivery**, read `zombie-delivery/AGENTS.md` first. It holds the rules, how Codex and Claude Code
share the work, and the checks to run. The shared task board is `zombie-delivery/COLLAB.md`.

Do not change Merge Blades unless the owner asks for it.
