# Complete job thumbnail set

The owner's direction: show the **business the courier works for**, with the customer and delivery address kept in live UI text. This set contains 25 standalone business PNGs covering all 19 ordinary delivery definitions and all 12 special job types in `Config.luau` at `882c11c`, plus the newspaper round and tutorial. Employer jobs are included even when they are offered at their own workplace rather than on the general board.

Open `index.html` for an offline, searchable gallery. Each picture has a download link and the exact ordinary/special IDs it serves. `../../art/job-thumbnails/manifest.json` holds the complete mapping, original file hashes, sizes, and empty Roblox image-ID slots; `upload.csv` is the upload checklist.

These are generated **2D UI illustrations**, inspired by the colors and recognizable objects in existing `BuildingLooks` modules. They are not exact Studio screenshots or new 3D buildings. The two full-interface PNGs are layout concepts; runtime labels, unlocks, prices and progress must come from game data.

## Shared pictures

- Bread and wedding-cake deliveries use Daily Bread Bakery (`bakery`, `cake`).
- Vaccine and sample deliveries use Research Lab (`lab`, `samples`; the map calls the place Biotech Lab).
- Regular and special pizza jobs use Luigi's (`pizzeria`, `pizzarush`).
- Ice-cream delivery and the company route use Frosty's (ordinary and special both have ID `icecream`, in separate maps).
- Ordinary generator-fuel delivery and the pallet Freight Run use Harbor Warehouse (`warehouse`, `freightrun`).
- Gold-bar delivery and Cash Transport use First Zombie Bank (`bank`, `cashrun`).
- A newspaper round uses The Daily Undead; tutorial letters use Post Office.

Special-job thumbnails identify the commissioning workplace, which can differ from pickup or destination: Army Supply shows Military Base (ammo is collected at the docks); Moving Day shows Big Move Movers (pickup is a customer's house); Fuel Run shows the Gas Station (pickup is Harbor Fuel Depot); Ambulance Run shows City Clinic. Winter Run has no configured employer or fixed pickup business: Ski Lodge is its representative commissioning/destination illustration, with the diner pickup still described by the live route. This choice does not add a new business.

## Claude integration handoff

1. Upload the 25 original PNGs as Roblox images under the game's owner/group and fill `assets[].robloxImage`. These are ordinary opaque RGB landscape pictures, not transparent icons. Preserve their aspect ratio with `UIAspectRatioConstraint` or `ScaleType.Fit`; arbitrary very-wide cropping can hide roof cues or signs. Keep a live business-name label and readable alt/fallback text.
2. Select `ordinary[businessId]` for an ordinary offer, `special[jobTypeId]` for a special, `round` for the paper round, and `tutorial` for letters. Do not select by customer, cargo-kind emoji or translated label. Duplicate businesses share one uploaded asset.
3. The current `Jobs.describe` payload has the special job information and round flag but does **not** expose a stable ordinary-business ID. Claude should carry the selected `business.id` into the offer/public data when wiring; this branch intentionally changes no gameplay or client modules. Do not infer the company by parsing the visible `first` sentence.
4. Keep job pay, acceptance/stacking, capacity locks and licence checks unchanged. A picture is descriptive and grants nothing. An empty/unavailable image ID must retain the current text fallback.
5. Reuse `special` mappings for `Career.road()` unlocks with kind `job`. `career-preview.png` shows separate picture tiles for available purchases/jobs and a framed panel for the actual level reward. Use `Career.road()`, `Career.rewardParts()` and existing given state; do not hard-code the concept's example XP, prices or unlock counts. Reward granting stays automatic/server-owned, with no new Claim action. The vehicle/gear pictures inside the career concept are illustrative; they are not standalone replacement assets in this job-business set.

The 100 story missions and challenge objectives have their own Missions/Tasks UI; this set covers configured **job** definitions and does not invent 100 additional job types. There are no added fuel-station jobs or new rewards.

## Validation

From `zombie-delivery/`:

```sh
python3 tools/job-thumbnails/check.py
python3 tools/job-thumbnails/gallery.py
python3 tests/run_tests.py /path/to/luau
```

The art audit checks coverage against current Config IDs, all aliases, unique original image files, valid PNGs and landscape dimensions, file hashes and the upload-ID format. The gallery builder leaves the PNG bytes untouched. The full existing Luau tests and compilation at `-O0 -g2` passed. Studio review after upload: every work type, repeated businesses, foot/bike/car cards, company job windows, a small phone, scroll performance and image-loading fallback.
