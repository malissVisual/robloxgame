# Zombie Delivery: the approved contract UI direction

**Owner approved on 2026-10-05:** “to je vončo super takto”. [approved-preview.png](approved-preview.png) is the visual reference for the next interface. This handoff is based on `main` at `fa0d413` (3.6.3).

The owner wants delivery work presented with the restraint and seriousness of a cinematic stealth-game contract, inspired by modern Hitman interfaces. The subject remains Zombie Delivery: contracts, cargo, vans, crews, hazards and rewards. This is a presentation change, not a new stealth system.

The owner superseded the earlier Postage & Trouble **UI** direction (`design/ui-concept/`). They rejected its comforting pink/pastel appearance, then rejected the bulky distressed-metal alternative as looking like a mobile game. Keep the approved **building signs** and world branding; this decision concerns the interface.

## What the approved image represents

One image-generated art-direction preview, not a screenshot of the running game, an interactive prototype or a finished Roblox interface. The rendered harbor, character, van and lighting are illustrative. Use the existing game world and camera when implementing; do not import this full image as a ScreenGui background. Values, modifiers and contract number are sample data.

## Visual rules

- Compact white typography over the scene, generous spacing, flat square geometry and fine separator lines.
- Small precise red accents for the contract marker, route destination and important status. Preserve text/icon explanations for warnings.
- The world is the main view. Aim for approximately 15% HUD coverage in an ordinary desktop on-foot state; this is an art-direction target, not a reason to hide essential information.
- Use a subtle localized charcoal scrim or text outline where the actual scene needs contrast. Do not sacrifice legibility on white walls, daylight or bright effects to match the preview's dark harbor.
- Replace tilted tickets, perforated timer stubs, round speed dials, pastel tags and thick decorative frames with compact typographic groups. No bolts, illustrated button plates, distressed type, neon glow or large brand logo on the gameplay HUD.

Suggested centralized tokens, to tune in Studio:

| Token | Value | Role |
| --- | --- | --- |
| Text | `#F2F2F0` | Main text and icons |
| Secondary | `#C4C7CB` | Supporting text; maintain contrast over the scene |
| Charcoal | `#14171C` | Localized readability backing / window surface |
| Line | `#858B93` | Fine separators, with suitable transparency |
| Red | `#D74A46` | Contract / destination / urgent feedback |

Use the existing `Theme` font family with medium/bold weights and restrained tracking. At a 1600×900 reference size, start around 20–24 px for the objective heading, 14–16 px for objectives and 12–14 px for metadata. Do not scale body copy below a readable size on smaller devices. Preserve semantic success/damage states, including icons and words; the predominantly white/red identity does not require turning every positive state red.

## HUD composition

| Area | Content and behavior |
| --- | --- |
| Upper left | Small contract label; destination heading; current objective(s); a thin rule; deadline and estimated reward. Align to native chat/insets, move below expanded chat as needed. |
| World destination | Small monochrome waypoint with destination/distance; existing GPS/job routing remains authoritative. |
| Upper right | Quiet MAP / CREW / MENU text actions. Place below/left of an expanded player list. All remaining actions stay reachable in MENU. |
| Lower left | Cash/rank text, compact monochrome minimap with a red destination/route accent, thin health bar plus number. Preserve actual road geometry and GPS/job route distinctions. |
| Lower right, on foot | Small weapon icon/ammo when usable; a secondary vehicle condition/cargo line when relevant. While carrying, show cargo information and the existing carrying restriction rather than an usable-looking weapon action. |
| Lower right, driving | Compact speed text with unit, condition and occupied/total cargo slots; retain the same alignment without a large circular instrument. |
| Lower center | One contextual key/action, short instruction and fine hold-progress line. Keep the center of the world clear. |
| Inventory | Compact access text/shortcut. Keep all consumables reachable; hide unnecessary hotbar presentation while carrying. Preserve Q weapon-wheel access and item shortcuts. |

The image's `027`, “sealed crates”, “Keep the cargo intact” and `3 OF 4` are illustrative. Read the actual job/mission identity, cargo types/counts, modifiers, payout and capacity from existing state. Show a fragile-cargo objective only when it applies. Since 3.5, the Old Van starts with 2 slots and its Cargo Van stage has 4; do not hard-code the old prototype's 4-slot default or revive Cargo Rack advice.

## Hover, press and navigation

- **Text action hover/focus:** brighten the label and reveal a thin underline or small red edge marker over 100–140 ms. Its hit area remains stable.
- **Press:** briefly reduce opacity or move the label by at most 1 px. Do not lift/tilt or bounce the entire control.
- **Selectable rows:** a quiet charcoal highlight and narrow red selection rule. Keyboard/gamepad selection receives equivalent emphasis.
- **Tooltips:** small plain text beside the control; show the shortcut when useful. Keep them clear of the contextual action and native controls.
- **Windows:** immediate input response, optional brief opacity transition. Rectangular charcoal surface, light text, concise header, slim rows and one clear action. Job selection reads as a delivery briefing: route, cargo, risk/modifiers, deadline, payout, capacity/level lock and remedy.
- **Touch:** a tap activates directly. Keep at least 44×44 px hit areas and label access without a hover step. Enlarge usable touch targets while preserving the restrained visible style. Respect native thumbstick/jump/fire areas.
- **Accessibility:** visible focus, no warning conveyed by color alone, no flashing or decorative motion; honor existing motion preferences. Maintain all current keyboard bindings, including J/U/M/B/K/H/L/N, Q, Alt, item keys and contextual controls.

## Implementation handoff for Claude

1. Use this preview and specification as the approved UI reference. Inspect the current 3.6.3 implementation in `client/Theme`, `Ui`, `Hud`, `DispatchUi`, `MapView`, `MissionsUi`, `GarageUi`, `CrewPanel` and the other windows.
2. Add/rework shared theme and presentation helpers for compact contract groups, plain text actions and rectangular windows. `Theme.Colors` is currently mapped to Postage tokens: update all applicable shared helpers consistently so lavender surfaces do not remain in secondary windows or world UI markers.
3. Rebuild the objective, contextual action and vehicle presentation without adding top-level locals in `Hud.luau` (the 200-register limit). Use existing scoped blocks or small presentation-only modules.
4. Preserve the existing state, public callbacks, remotes and server validation. Holds must complete from server-confirmed cargo behavior, not from an invented UI timer. Repair stays at bays and vehicle take-out stays at owned garages. Menu access must retain GIVE UP and all currently reachable actions.
5. Change presentation progressively and check actual day/night, input devices and native-control safe areas. The approved harbor render does not authorize changing map layout, world assets, vehicle physics or gameplay tuning.

This branch only saves the approved reference and handoff; it does not modify production game modules. Claude owns the game implementation/release through the usual review and merge workflow. Do not treat the concept image as a completed Studio test.

## Checks before implementation release

Run the repository's existing test suite and all `luau-compile -O0 -g2` checks. In Studio verify on foot, driving, carrying, loading/open-back restrictions, cancel/failure/reward feedback, locked job offers and current stage capacities, repair timers, owned-garage take-out, crew/mission stacks, every window and menu action, keyboard/gamepad/touch, resizing, bright/day/night scenery and expanded native chat/player list.

Reference handoff verification: preview PNG integrity passes; all existing test files and source-module `-O0 -g2` compilation pass on this branch. Production source and tests are unchanged from `fa0d413`.
