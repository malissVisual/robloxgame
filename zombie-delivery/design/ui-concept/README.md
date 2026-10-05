# Postage & Trouble — UI concept

A proposed layout for **Zombie Delivery 3.4**, based on `main` at `475cb1b`. This is a standalone interactive design prototype and a handoff for Claude. It does not change the game's Luau modules, remotes, economy, artwork or tests.

## Open the concept

Open `index.html` in a browser. Keep it in this folder: it reuses the existing `../../art/ui/menu_background.png` as an atmospheric backdrop. That image is menu artwork, **not a gameplay screenshot**. The two schematic maps and van drawing illustrate layout; they are not the actual world geometry or a replacement vehicle model. No web fonts, libraries, trackers or external downloads are used.

Use the five tabs to try **On route**, **Load cargo**, **Dispatch**, **Garage**, and **Map**. Switch to **Touch** to inspect a landscape HUD with reserved joystick/jump areas. Smaller browser widths show a stacked review layout; this is not a claim that Roblox supports portrait gameplay.

Working interactions:

- J opens Dispatch, M opens Map, K opens Crew, Esc closes a window.
- Filter jobs, accept an available job, or inspect a capacity-locked job.
- Hold E or press and hold the loading card for two seconds to load a piece. Releasing early cancels progress. After the final piece, close the doors to return to the route view.
- Find a repair bay from Garage, select a map destination, and set GPS.
- Take out the sample parked van **in the owned-garage scenario**.
- Use the compact menu and consumable buttons to preview feedback. Missions, Backpack, Properties, Settings and Crew Board have feedback placeholders; their full windows are not designed in this iteration.

All values and actions are sample state. Accepting a job does not take a real Roblox job, taking out a car does not change a real profile, and GPS does not move a game character. The prototype deliberately does not emulate vehicle physics or a live world.

## Why change the layout

The owner wants a playful courier identity, especially custom silhouettes and hover/press behavior, with gentle colors. The design uses shipping labels, ticket perforations, tilted item tags and a round instrument dial. The information hierarchy still serves the current game:

- `Hud.luau` currently exposes eight navigation actions and several independently updating panels. A job, mission, crew, car call, repair, level-up and toasts share the top stack.
- A driver needs a clear answer to **where next**, **how much time**, **what is in the van**, and **whether the vehicle is usable**. Secondary progression and collection screens should not compete with that information.
- Cargo capacity, per-car damage, repair bays and owned garages became important in 3.4. Show the constraint before a commitment and explain the remedy beside a disabled action.

## Screen hierarchy

| Area | On route | Handling cargo | In a window |
| --- | --- | --- | --- |
| Top centre | One objective, next stop, time, loaded/total slots, estimated payout | Short action verb, cargo progress, loading location | Window title, location/context and close action |
| Upper right | Map, Crew, compact menu | Same navigation, clear of interaction | Secondary navigation inside the selected window |
| Bottom left (desktop) | Cash/rank, minimap with next turn, player health | Same essential information | Covered by the modal |
| Bottom right (desktop) | Weapon and ammo, speed, vehicle condition, cargo occupancy | Speed hidden; weapon visibly holstered; vehicle condition retained | Covered by the modal |
| Bottom centre | Consumables and quiet control hint | One hold action, duration, progress and next step | No competing HUD controls |
| Touch landscape | Money/map above the joystick; large right-side Fire; compact vehicle status left of Fire | Load action replaces irrelevant shooting emphasis | Larger controls, scrollable content, preserved native inset |

The visual priority is **current objective → immediate interaction → vehicle/weapon condition → route → optional menus**. Do not display repair, car-call and mission cards simultaneously merely because there is space: use the existing state to show what matters. A dangerous state must have a text/icon warning, not color alone.

## Visual system

Use light cream and powder-lavender surfaces with dark plum text. Pastels belong on surfaces, not critical text. Introduce these semantic values in `Theme` when implementing the concept rather than scattering new colors through `Hud`.

| Token | Value | Use |
| --- | --- | --- |
| Paper | `#FAF4E4` | Current objective ticket |
| Ticket | `#FCF7ED` | Available job cards |
| Lavender | `#EEE6F3` | Modal surface |
| Primary ink | `#493750` | Objectives, prices and large values |
| Secondary ink | `#74617D` | Routes, labels and explanations |
| Sage | `#E5EDCE` | Main action surface |
| Violet | `#846699` | Crew/GPS identity |

### Shapes and motion

- **Objective:** a slightly tilted delivery ticket with clipped corners and a perforated timer stub. Time remains aligned and easy to scan.
- **Job cards:** semicircular edge cutouts, numbered icon spine, perforation and a separate payout/action stub. Disabled jobs use hatching and a written capacity remedy.
- **Vehicle:** a round speed dial with ticks, condition and cargo occupancy; the weapon gets a separate curved label above it.
- **Consumables:** individual softly colored, alternating tilted tags. Hover/focus lifts a tag 9 px, straightens it and scales to 1.12 over 220 ms; its icon tilts and a label appears. Press depresses it 2 px and scales to .97.
- **Job hover:** lift 5 px and rotate -.4 degrees over 220 ms; focus inside a card shows the same treatment. Accept raises 3 px on hover and depresses 2 px on press.
- **Utilities:** asymmetric shapes open their text labels on desktop hover/focus. Press removes the shadow. Touch and narrow layouts keep icons with accessible labels rather than relying on hover.
- **Close:** a round control turns 90 degrees on hover and shrinks on press. Modal switching is immediate; navigation does not wait for an animation.
- **Reduced motion:** all transitions and animations are disabled when the browser preference requests it. Information and controls remain available.

In Roblox, reproduce simple silhouettes with layered `Frame` pieces and the existing `Ui` helpers; exact ticket cutouts may use a reusable transparent nine-slice image. CSS masks and clip paths do not translate directly into Roblox. Keep hit areas rectangular and at least 44×44 physical pixels on touch, even where the drawn silhouette is smaller. Use `TweenService` for hover/press with connection cleanup; keyboard/gamepad focus should receive equivalent feedback. A touch tap activates immediately without a preliminary hover step.

In the actual game use at least 14 px body copy and 12 px labels at a 1150×680 reference size. Compact labels in this browser drawing are not an approved minimum for the live HUD. Use `Theme.DisplayFont`, `HeadingFont` and `Font` as appropriate. Leave the existing scene artwork and game world unchanged; no paid assets, CSS blur dependency or web font upload is needed.

## Functional details for implementation

**Job board:** sort/select with existing offers; show route, cargo slots required, danger, time and estimated reward before Accept. A capacity lock must say both required and available slots and give the existing Cargo Rack/larger-vehicle remedy. A level lock must show the required level. Do not silently accept when a selected offer is stale; keep server validation and existing error feedback.

**Cargo:** distinguish three concepts: pieces loaded, pieces required for the current stop/job, and vehicle capacity. A hold action reads from the actual existing prompt/state. Respect carrying restrictions, back-door state, crew ownership and server-confirmed loading. Do not synthesize a completed load from a UI timer. The browser's two-second hold is illustrative; use `Economy.loadHold`/existing job timings in Roblox.

**Vehicle and garage:** show condition, cargo slots and parked location. Global menus may inspect vehicles or guide the player to a garage; only the existing owned-garage interaction may take a vehicle out. Preserve the 3.4 free-slot and ownership rules. Repair navigation points to a bay; do not turn the Find Repair Bay button into a remote/global repair purchase. During an actual repair show remaining time/cost from `Repair` state. No fuel gauge: there is no fuel mechanic to support one.

**Navigation:** keep J/U/M/B/K/H, the existing CAR action and leaderboard reachable. Secondary menus group the actions rather than removing them. The sample collapsed menu omits some destinations for scope; the production menu must also include CAR and TOP. Keep admin controls restricted to admins. Map destinations and routes must come from `Map`/`Roads`, not the schematic SVG.

**HUD ownership:** no new top-level locals in `Hud.luau` (the 200-register limit). Extract a presentation-only module for the objective/vehicle card or use the existing `do ... end` blocks. Existing remotes, public Hud callbacks and state remain the source of truth. Changing arrangement must not change who can accept jobs, use items, invite crew, buy property, switch cars or earn money.

**Roblox controls:** honor `GuiService`/ScreenGui insets and safe areas. Reserve desktop chat at upper left and the player list at upper right; the small utility group must move below/left of an expanded player list. On touch use the actual thumbstick/jump control rectangles, not the browser's illustrative circles. Avoid shrinking readable text to fit; collapse optional data first. Handle changing input devices and window size without rebuilding listeners every frame.

**Accessibility and feedback:** labels alongside icons, visible keyboard focus, a proper modal focus boundary in the browser; equivalent selected gamepad controls in Roblox. Do not communicate risk solely with red. Brief, queued notifications cannot push the mission off-screen. Cancel holds on release/focus loss/window opening. Avoid flashing danger effects or excessive camera motion; respect the player's sound/motion preferences.

## Suggested delivery order for Claude

1. Start with the job board card layout and capacity/level explanations using existing `Hud` callbacks. It is easy to verify without rearranging the full HUD.
2. Introduce a compact objective presentation backed by the existing job/mission state. Explicitly preserve mission twists, crew status, timer/payout changes, cancellation and failure feedback.
3. Refine the vehicle/cargo card and garage inspection view. Validate per-car damage and garage-only take-out in 3.4.
4. Collapse secondary navigation and test touch layouts last, using existing responsive helpers and native-control safe areas. Keep the current keyboard bindings and all reachable actions.

Do not bump `Config.Version` in this concept branch; the merger owns the release/version change.

## Checks and acceptance criteria

Browser prototype: inspect the five screens and hover/focus/press states, filter/select a job, verify locked-capacity state, complete and cancel a loading hold, choose a repair/GPS route, close modals with Esc, and test keyboard focus. Review desktop at 1600, 1280 and 1024 px and touch landscape at 1180 and 844 px. A 390 px stacked rendering is for reviewing the concept, not an approved game orientation.

Before a production UI merge run the existing `tests/run_tests.py` suite and `luau-compile -O0 -g2` checks. In Studio verify: driving while under fire; loading with the back closed/open; a too-large offer; vehicle damage and repair completion; taking out vehicles at owned versus unowned garages; job rewards/failure; crew missions; resizing; keyboard/touch/gamepad; chat/player list and native touch controls. Browser screenshots do not establish those gameplay checks.

For this proposal, screenshots under `previews/` come from the working HTML, including `hover-item.png` and `hover-ticket.png`. Browser interaction and layout checks pass at 1600, 1280 and 1024 px desktop, 1440 and 844 px touch landscape, and 390 px stacked review. No JavaScript errors were observed. All 13 existing game test files pass and all 64 source modules compile at `-O0 -g2`. No game source or test files changed; Studio gameplay has not been tested.
