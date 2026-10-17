# Phone UI recorder

Run from `zombie-delivery/`: `python3 tools/phone-ui/check.py /path/to/luau`.

The game's windows and HUD pieces run for real against a narrow UI instance recorder (`mock.luau`, `missions_mock.luau`, `sandbox_mock.luau`): construction, the server's data, callbacks, resizing and cleanup, on phones held sideways (844 x 390, 667 x 375 and smaller), tablets, computers (1280 x 800) and big screens (1920 x 1080). Each scene copies the real client modules and the real shared data into a temporary folder (its `*env.py` builds it) and checks that everything is on the screen, clear of the touch controls and of each other, its words fitting and a phone's buttons a finger's size:

- `movehud.luau`: the move's panel, Danny's status line and the quick chat (MovingHud, MoveHelperHud, QuickChat);
- `carrygrip.luau`: the carry's timing check (CarryGripUi) beside the move's HUD and the HUD's groups;
- `adminpanel.luau`: the admin panel's SANDBOX and OP tabs (AdminPanel);
- `sandboxguide.luau`: the guide's line and its steps (SandboxGuide);
- `sandbox.luau`, `upgrades.luau`, `collectionbook.luau`, `sandboxtasks.luau`, `sandboxpad.luau`, `vanpaint.luau`, `auction.luau`: the money and stock HUD, the warehouse picker and STOCK list, the UPGRADES desk, the collection book, the TASKS panel, every device's way to the chips, the PAINT shop, the Auction House;
- `dannycard.luau`, `dannyorders.luau`, `offercard.luau`, `trade.luau`, `sandboxhints.luau`: Danny's card and orders mode, a visitor's offer, trading between players, the first-time hints;
- `keyhints.luau`, `runs.luau`, `loot.luau`, `sandboxmap.luau`, `crew.luau`: the key hints, the runs' pad panel and results card, the loot's stars and outlines, the big map and the minimap, the CREW window.

The `*_preview.py` scripts draw the same scenes in headless Chromium (`sandbox_preview.mjs`).

This is a behavior check, not a Roblox renderer: fonts, automatic layout, touch hit testing, animation and actual device performance still require Studio. Production files are never rewritten by this tool. A warning or a failed check stops the command with a nonzero exit code.
