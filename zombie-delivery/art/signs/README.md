# Signs of life — Zombie Delivery building signs

54 original building name boards based on [`buildings-brief.md`](../../design/buildings-brief.md). The owner approved the [first art-direction sheet](../../design/building-signs/first-preview.png) on 2026-10-05. These are individual vector adaptations with simplified mascots and lettering for the required upload dimensions, not crops of that sheet.

Open [the gallery](index.html) to inspect all signs. It groups them in the brief's order, links each PNG and SVG, and switches between light and dark transparency backgrounds. [Review screenshots](../../design/building-signs/previews/) are separate from the upload folder.

## Files and coverage

- **40 wide boards:** `1024 × 256`, for shops, employers, city/industrial/out-of-town places and office door plates.
- **14 square badges:** `512 × 512`, for the five garages and nine houses/villas/mansions. Maple and Oak have large house numbers, 12 and 7.
- Every board has `sign_<id>.png` and `sign_<id>.svg`. PNGs are full-color RGBA with a genuinely transparent exterior. SVGs contain editable vector paths with all lettering outlined; no font installation, embedded raster image or remote resource is required to render them.
- `assets.json` lists name, PNG file, SVG source, size, intended use, building id, aliases and full label. It is a production manifest, not a map of uploaded Roblox asset IDs. The brief's `art/icons/assets.json` reference is absent in this repository; the requested metadata fields are supplied explicitly.
- `catalog.json` is the editable source of names, line breaks, slogans, shapes, motifs and palette. `make_signs.py` and `symbols.py` deterministically build the assets.

The two slash-separated brief entries each describe one building: `sign_army` also serves the `base` mission place, and `sign_icecream` also serves `frosty`. The aliases are in the manifest; do not upload duplicate images for them. The three office signs name Harbor Point Office / Suite 7, Dispatch Tower / Suite 8, and Dispatch Tower / Penthouse.

## Visual direction

Cream, dusty lavender and sage connect the signs to `Theme.Postage`; businesses also use faded coral, blue and teal. Dark plum outlines and chunky, gently irregular lettering carry the names. Dark teal boards use cream lettering. Corners, perforations, arrowheads, gear teeth, mailbox arches and padlock silhouettes give different buildings their own identities.

Original mascots include the depot's parcel and zombie hand, a patched dealer van, an ammunition crate, a smiling wrench, bundled supplies, an anchor, a horse, a flask and a lighthouse. Small edge chips, bolts and a tape patch suggest a city that keeps repairing itself. Wear never cuts through the name. Slogans are optional flavor: navigation must work from the large name and symbol alone.

## Upload and integration handoff

1. In Roblox Studio use **Asset Manager → Bulk Import** and select only this folder's **54 `sign_*.png` files**. SVG sources, the HTML gallery and the concept/review sheets are not upload textures.
2. Record each asset ID under its exact `sign_<id>` name. The owner supplies those IDs; this branch contains no fabricated IDs.
3. Claude adds the slots in `shared/Icons.luau` and updates `server/World.luau`'s `sign()` to prefer the image, preserving the current English text fallback when an ID is missing. Use `ImageColor3 = Color3.new(1, 1, 1)`; these are full-color boards, not tintable white icon silhouettes.
4. Preserve aspect ratio: wide boards are 4:1 and square badges 1:1. Use `ScaleType.Fit` or suitably sized physical plates; do not stretch square badges across the old wide text boards. Retain alpha around their custom silhouettes.
5. Treat these as building-name art. Keep functional **JOBS**, **WORK HERE**, **GARAGE**, **BAY 1 / BAY 2**, prices, ownership and **FOR SALE** prompts/listings available as existing dynamic text and interactions. A fixed illustration must not replace those state-dependent signs.

No `World`, `Icons`, UI, map or gameplay module is changed here. The brief's optional 3D building work is a separate future task, one building per branch. Claude is implementing the UI in parallel; this branch only adds artwork and handoff documents.

## Rebuild

Python 3.10+ and the two DejaVu fonts are required by the builder, not by the exported images:

```sh
python3 -m pip install -r zombie-delivery/art/signs/requirements.txt
python3 zombie-delivery/art/signs/make_signs.py
# On another system, pass the folder containing the DejaVu .ttf files:
python3 zombie-delivery/art/signs/make_signs.py --font-dir /path/to/dejavu
```

The builder uses `DejaVuSansCondensed-Bold.ttf` and `DejaVuSansMono-Bold.ttf`. Font outline attribution and permission are in [LICENSE-FONTS.txt](LICENSE-FONTS.txt). All mascots and board geometry are original for this game; no real brand or existing business logo was used.

## Validation and Studio review

Asset checks cover all 54 brief entries, unique PNG/SVG pairs, exact dimensions, nonempty RGBA/alpha, transparent corners and uncropped outer bounds, SVG labels/metadata, outlined type, no external SVG dependencies and the two aliases. Main name/background contrast is at least 4.65:1 before scene lighting. The gallery loads all 54 images without JavaScript errors, switches its checkerboard background and fits a 390 px browser window. Existing game tests and `-O0 -g2` compilation pass; game source is unchanged.

After uploading/integrating, review in Studio at day and night and from driving distance: complete names, full-color images, transparent outlines, correctly proportioned square badges, correct building/alias assignment, text fallback with a missing ID, and unobstructed prompts/cargo paths. Studio integration has not been tested in this artwork branch.
