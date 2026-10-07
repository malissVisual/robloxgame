# Phone UI recorder

Run from `zombie-delivery/`: `python3 tools/phone-ui/check.py /path/to/luau`.

Copies the actual Phone, PhoneContract, PhoneLayout, PhoneRoute, PhonePopup, PhoneApps, PhoneMotion, OrdersUi and shared data into a temporary directory. The fixture supplies narrow service/instance stand-ins, then exercises real construction, server payload updates, action callbacks, resize and lifecycle cleanup. 6.0.1: every app opens in the centred popup and closes back to home (✕, backdrop, Q / ESC / B), and the phone never turns. A warning or failed check stops the command with a nonzero exit code.

This is a behavior check, not a Roblox renderer: fonts, automatic layout, touch hit testing, animation and actual device performance still require Studio. Production files are never rewritten by this tool. The regular required suite additionally runs the pure PhoneLayout regressions and compiles every module at Roblox's `-O0 -g2` settings.
