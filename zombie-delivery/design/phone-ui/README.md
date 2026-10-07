# Courier phone UI

The owner approved `approved-preview.png` on 2026-10-06 and requested implementation. This branch is based on `main` at `c19ff92` (5.4.1). The PNG is the approved generated concept, **not a screenshot of the implementation or a Studio test**.

`client/Phone.luau` now uses square charcoal surfaces, white app glyphs, thin rules and red actions. Home shows ZDC branding, the current courier balance/rank/transport, a live focused contract, eight apps and unread messages. The order detail uses the actual destination and Roads route with Discovery fog; SHOW ROUTE opens the existing full map. Existing order pinning, other-order clocks, bag, add-order board, gear/shop GPS, career, messages, bike/car switch, tow and PhoneHold callbacks stay in use.

`PhoneContract` draws the native depot silhouette, white glyph fallbacks and contract card. Uploaded icons are resolved through `Icons.get(Icons.app(id))`; no upload is required. `PhoneLayout` keeps text readable by shortening the scrollable body on small screens. 6.0.1: the phone always stands upright; every app opens in a centred popup over the game (`PhonePopup`: a dim, lightly blurred backdrop, a 760 × 520 ZDC panel with `Ui.window`'s header that grows from the tapped tile, two columns for BOARD / CAREER / SHOP when wide). `PhoneRoute` renders only while ORDERS is open, redraws after resize/discovery or 48 studs of movement, caches one graph route, reuses its road/fog instances across unchanged-destination Job updates and disconnects listeners when its parent is destroyed. Home and the popup's app content scroll independently of their controls; automatic lists prevent kit/tow/messages from overlapping the launcher.

The game remains in English, matching its existing UI. The concept's Czech copy and example values are illustrative. BANK displays the existing courier cash balance; it adds no transactions or bank currency. SETTINGS calls the existing sound cycle and explains controls. Countdown, pay, open-order count and destination come from server payloads; distance is explicitly in Roblox studs. No server gameplay, Config, remotes, joints or global theme were changed. Q opens the phone; T remains the weapon wheel.

## Validation and review

From `zombie-delivery/`:

```sh
python3 tests/run_tests.py /path/to/luau
python3 tools/phone-ui/check.py /path/to/luau
```

All 38 test files, style/capacity checks and every source module's `luau-compile --null -O0 -g2` pass. The phone recorder passes actual client-module checks for eight apps, native icons with empty IDs, incoming/nil jobs, multiple orders/pinning, board/map/bag access, current balance, sound cycle, gamepad focus, resizing, PhoneHold and destroyed route listener cleanup. `rojo build default.project.json` from the repository root also succeeds.

The recorder checks construction and callbacks; it is **not** a Roblox UI layout or font emulator. Claude should check in Studio: Marge giving the phone; Q/T, back/HOME/CLOSE and right-mouse camera; every app and unread badges; long names/messages; one/multiple orders, PIN and new destination, expiry/completion; discovery fog/route; kit/bike/car/tow actions; keyboard/gamepad/touch and portrait/landscape resize (320px phone, 667/844px landscape, tablet, desktop); readable text and hit targets, scrolling and frame time. Merge through the normal collaboration workflow, then bump Config.Version during the release.
