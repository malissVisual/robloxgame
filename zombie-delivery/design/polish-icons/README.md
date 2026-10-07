# 5.x polish icons

29 distinct white silhouettes with transparent backgrounds: 4 transport markers, 21 landmarks and 4 exclusive guns.
Map PNGs/SVGs are 128 × 128 in art/map; guns are 256 × 256 in art/weapons, barrels pointing left.
See [sheet.png](sheet.png) and [assets.json](assets.json) for the exact upload list.

The Icons.Ids slots are intentionally empty. Existing borrowed landmark/weapon routing stays in place until upload.
Claude: after the owner uploads the PNGs, fill those slots and remove the corresponding LANDMARK_BORROWED and
WEAPON_ALIASES entries. Dynamic transport markers can use Icons.get("map_bus"/"map_zip"/"map_rental"/"map_shortcut").
The updated icon test checks that every staged landmark really exists and that uploaded artwork is routed.

Reproduce with Python 3, Pillow and CairoSVG:

```bash
python3 tools/polish-icons/make.py
python3 tests/run_tests.py /path/to/luau
```

SVGs use editable luminance masks. The generator explicitly renders their luminance into PNG alpha because
CairoSVG itself supports alpha masks only. Audits cover exact dimensions, white visible pixels, transparent margins
and unique silhouettes. No game UI, gameplay, icon uploads or asset IDs are changed by this branch.
