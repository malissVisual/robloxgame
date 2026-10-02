# Merge Blades

A Roblox merge autobattler. You summon soldiers at an altar in the lobby and they land in your **inventory**,
which is at the same time the **3D merge room**: every soldier in the inventory automatically
stands on a pad of the merge board in the lobby. You merge two identical ones into a stronger one
right in the UI inventory (drag a card onto another card) or in 3D (drag a soldier onto another),
**equip** your best into the battle squad (one row of six) and send the squad into battle against a wave. Both
sides walk from their rows onto a big round fight arena and fight on their own, PvE only. PC first, mobile later.

**Current state (Mage only):** the game has ONE class, the **Mage** (30 merge levels, the R15 evolution). The Knight,
the Archer, the Hunter, the Tank, the Berserker and the Soldier were removed (a saved soldier of a removed class
loads as a Mage of the same level). **You do not cast anything**: the Mages fight and cast every spell on their own
(`Config/MageSpells.luau`, `MageBrain.luau`), and you only walk around with your character; there is no Q / E, no
SPELLS tab and no spell drops. Older passages below about other classes or "your own spells" describe the removed
version.

Most things are 3D in the world. The UI is the PLAY button, the HUD with the account level and
coins (bottom left), the left panel (a single Inventory page: the mages; a click on a mage opens its popup and
outlines it lightly, no Characters / Upgrades tabs, merging is never capped), the battle panel (opened
with PLAY) and short toast messages. Every soldier has its name and level (e.g. "Mage · Lv 3")
floating above it.

## Running

```bash
node tools/rojo-sync.js
```

Then in Studio: **Plugins → Rojo → Connect** (localhost, 34872) and **Play**.
(`rojo serve` works too if it is allowed to run: `rokit install && rojo serve`.)

**On a Mac without the terminal:** double-click `nastav-mac.command` once (it checks Git and Node, downloads the
Rojo 7.7.0 Studio plugin into `~/Documents/Roblox/Plugins`, pulls the latest version and starts the sync), and from
then on double-click `aktualizuj-a-spust.command` (pull + sync). Keep the window it opens; in Studio: Stop → Rojo
Disconnect → Connect → Play. Connect only while the game is NOT playing (otherwise "Http requests can only be executed
by game server").

## Game loop

**Current simplifications:** the game is silent (no sounds, no music; `playSound` is a no-op), there are **no
summoning altars and no level-upgrade station** in the lobby (a new player starts with four level 1 Mages in the
squad, and every won wave drops new characters), and there is **no countdown**: PLAY fades the
screen to black for 1.1 s with FIGHT! on it (you stay where you are, the fight starts as it
clears, `Balance.BattleCountdown`), and the end of the battle fades to black for 1 s while you are put back at
your spawn (remote `Countdown` carries "start" / "end").

```
Summon (altar, E) → the soldiers land in the INVENTORY (= the 3D merge room)
   ↑                                        │ drag a card onto a card (UI) or a pad onto a pad (3D): merge
   │                                        │ click a card → EQUIP (into the battle squad)
   │                        BATTLE SQUAD (3D, 3 x 2 = 6 places) → PLAY (pick difficulty + wave, START WAVE) → arena
   └── coins from kills go straight to you, XP drops as orbs; a win = a soldier drop + next wave ────────┘
```

The server decides everything (buying, merging, rolling, the battle simulation).

## Merge levels

Every soldier has a **level** (`Config/Levels.luau`; the **Mage goes to 30**, see below). Merging
two soldiers of the same class and level makes one soldier one level higher. A level makes the soldier
stronger (×1.8 HP and damage per level) and changes its look. The limit is per class (`Units.maxTier(class)`,
from `maxTier` in `Units.Classes`); `Balance.TierUnlocks` has the price of every level up to 30.

**The Soldier** has its own model with **9 stages of gear** (designed in Claude Design, the project
`soldier-merge`; built in `Soldier.luau`, `buildStageSoldier`). The gear is cumulative, and a Soldier
card's popup shows what its level added:

| Level | Soldier gear | Level color |
|---|---|---|
| Lv 1 | Starting gear: cap and pistol | Common (gray) |
| Lv 2 | Combat helmet | Common (gray) |
| Lv 3 | Assault rifle | Uncommon (green) |
| Lv 4 | Tactical vest | Uncommon (green) |
| Lv 5 | Shades | Rare (blue) |
| Lv 6 | Minigun | Rare (blue) |
| Lv 7 | Medals and an aura (glow + sparkles) | Epic (purple) |
| Lv 8 | Golden gear (helmet and minigun) | Legendary (orange) |
| Lv 9 | Hero cape | Mythic (red) |

The **Knight** and the **Archer** also have their own designed models with **9 stages** (`design/Knight_AllStages.rbxmx` and `design/Archer_AllStages.rbxmx`, turned
into data by `tools/stages_from_rbxmx.py` → `src/shared/StageModels/<Class>.luau`; run the tool again after
changing the design, e.g. `python tools/stages_from_rbxmx.py design/Knight_AllStages.rbxmx
src/shared/StageModels/Knight.luau`). Stage 7, 8 and 9 have an aura (glow + sparkles in the level color).

The **Mage** is an R15 character with **9 designed stages** too (`src/shared/SoldierRig.luau`, `MAGE`, from the
purple mage cards): Novice · Sorcerer · Wizard · Mage · Arcanist · Archmage · Cosmic Mage · Grand Mage · Legend —
a pointy hat, a robe and a staff in the left hand from the start; later a beard, a cloak, floating orbs and a rune
circle, a hood with glowing eyes, planets, flying books, a halo and wings of light.

The **Hunter**, the **Berserker** and the **Tank** have their 9 designed stages in `SoldierRig.luau` too (`HUNTER`,
`BERSERKER`, `TANK`, from their card sheets):

| Class | Levels 1 → 9 |
|---|---|
| Hunter | Scout · Trapper · Tracker · Sharpshooter · Nightstalker · Hawkeye · Phantom Ranger · Royal Huntsman · Legend — crossbow → long rifle with a scope; a cap, a hood, goggles, night vision, a mechanical eye and a hawk, floating reticles, antlers, wings of light |
| Berserker | Brawler · Raider · Marauder · Berserker · Bloodrager · Warlord · Firebrand · Warchief · Legend — a bare chest and one axe → two flaming great axes; fur, horns, war paint, tattoos, chains, skull trophies, burning hair, a wolf pelt, wings of fire |
| Tank | Guard · Shieldbearer · Defender · Bulwark · Juggernaut · Ironwall · Titan · Colossus · Legend — a round wooden shield and a club → a tower shield and a war hammer; plate, a closed helm with a glowing slit, glowing runes, an energy barrier, a banner, a halo and wings of light |

Every class now has a design of its own; the generic level gear (`Soldier.luau`) is only the fallback for a class without one.

**Size and aura.** In the UI the soldiers are called **characters**. A character grows gently with its level
(`Soldier.scale`: 0.9 at level 1, 1.26 at level 9 — a 2x level 9 used to crowd its neighbours), the pads are
`Balance.SlotSpacing` (7) apart, and the lights and sparkles of the designs come out soft (`AURA_*` in
`SoldierRig.luau`; the level outline is faint, the stage auras have no sparkles). The fight arena
(`FightArena.luau`) is 76 x 72 studs with the fighters 16 (yours) / 13 (enemies) apart and 10 between rows.

The level colors (label, card outline, pad under the soldier, effects) follow the rarity colors of the
Soldier design, so Lv 1 and 2, 3 and 4, 5 and 6 share a color.

- **Buying** gives a random unlocked class at Lv 1. **Wave drops** give a random class at a higher
  level as the waves go on (Lv 1 + wave / 7, up to Lv 5). They go to the inventory; when it is full
  they are sold for coins (`Levels.sellValue`).

## Inventory, merge room and equipping

- **The inventory IS the merge board.** There is only one storage: the 36 pads of the merge board in
  the lobby. Every soldier you own that is not equipped stands on one of them, and the same soldiers
  are the cards of the **Inventory** tab (left panel), so what is in the inventory is automatically
  visible in the 3D merge room. New soldiers (bought or dropped) take the first free pad, front row
  first; when it is full they are sold for coins (`Levels.sellValue`).
- **Its size is an upgrade:** you start with 6 usable pads (the front row) = 6 inventory places. The
  **"+" card** at the end of the inventory grid (a big plus that breathes, brighter when you can afford it) buys
  +3 places; every upgrade costs 60% more (`Balance.BoardUpgrade*`) up to
  36. Locked pads are dark and half-transparent.
- **Merging in the UI:** drag a card onto another card. The target card's outline lights up (gold =
  they will merge: same class and level, blue = swap, white = move) and a 3D soldier follows your
  cursor. Dropping on a 3D pad works too. Merging in 3D (drag a soldier onto another) works as
  before, and the merge effect plays in the 3D room either way.
- **Equipping:** **click** a card: a small popup offers **EQUIP** (into the first free squad slot;
  it shows how many are free). The **EQUIPPED** row at the top of the panel shows the squad, and
  clicking an equipped card offers **UNEQUIP** (back to the first free inventory place). You can
  also drag between the rows, or drop a squad soldier from the 3D world onto the panel to unequip it.
  Only equipped soldiers fight.

## Controls

**You only control your character** (walk around, watch the fight). The Mages cast their spells themselves; there
are no player spells, no Q / E and no mouse aiming any more.

The battle is started with the big green **PLAY** button at the bottom right (its own little dock, movable by the grip
on top): it opens the battle panel (difficulty, wave, START WAVE). The main panel (inventory, characters, upgrades)
starts at the top of the screen and hides while the battle panel is open, so the two never lie over each
other; it comes back when the battle panel closes, and opening it from the dock (or H) closes the battle panel.

- **Movable panels:** the left panel (grab its title bar), the daily quests and the settings can be dragged
  anywhere on the screen. The positions are saved in the player's settings (`layout`, a JSON string the client
  owns) and come back on the next join; **RESET LAYOUT** in the settings puts everything back.
- **The inventory icon** (the bag on the left edge of the screen) hides the whole panel and shows it again
  (saved with the layout).
- **Folding the panel:** the − / + button in its title bar, or **H**, folds it to the title bar and back
  (saved with the layout). The panel is a wide one (640 × 420, two columns on every page), starts in the
  middle of the screen and is drawn at `UI.PANEL_SCALE` (1.15) of its layout size.
- **Drag & drop:** press the mouse (or a finger) anywhere on a pad with a soldier (you do not
  have to hit the soldier itself) and drag it onto another pad. The target lights up: **gold** = the two will merge (class + level must match), **blue** =
  swap, **white** = move to an empty pad. The server decides the result.
- **Hover:** with nothing grabbed, the pad under the mouse gets a pulsing disc and the soldier on
  it lifts a little and glows, so you see what you would grab (client-side only).
- **Summoning altars (lobby):** soldiers cost coins and come from the glowing green altar right of the merge
  board: walk up and press **E** ("Summon soldiers"). One summon gives **2 soldiers for 15 coins**
  (`Balance.SummonCost`, `SummonCount`); they land on the first free pads of your inventory **right away** (a light
  beam on each and a quick reveal: the altar flashes, the cards pop in with a climbing chime and drop away in about
  a second; no roll to wait for). Only a short **0.8 s cooldown**
  (`Balance.SummonCooldown`) stops spamming. With fewer than 2 free places you get fewer
  soldiers and pay only for those; with a full inventory you get a message. The prompt is made on the client,
  so only you see it on your own plot. There is no buy button in the UI.
- **Better summoner (lobby):** the gold altar next to it. It needs **10 cleared waves** of Training Camp and
  works the same way (2 soldiers, no waiting) for **150 coins**, but every soldier starts at level 2
  or higher (your start level, if that is higher) with a 35% chance of +1, 15% of +2 and 5% of +3 levels, even
  above the merge limit you have bought for its class (`Balance.BetterSummon*`, `rollBetterTier`).
- **Selling:** click a card in the inventory (or the squad) and press **SELL**: the soldier goes for coins
  (`Levels.sellValue`: 2 coins at level 1, doubling every level, so 4, 8, 16 … 512 at level 9). It also works
  for the equipped squad, only not during a battle or a roll. The server does the sale (`onSell`).
- **Level upgrade station (lobby):** the glowing purple pad with the crystal, left of the merge board. Stand
  on it and a panel opens: buy a higher **start level** for bought soldiers (they normally start at level
  1; levels 2 – 5 cost 250 / 750 / 2250 / 6750 coins, `Balance.StartLevel*`); it can never be higher than
  your unlocked merge level. The server checks that you stand in the station's zone (`Plots.isInUpgradeZone`).
- **AUTO MERGE** (in the Inventory tab) merges every possible pair of the merge board **and the battle squad** (same class and level; a pair with a squad soldier stays in the squad) again
  and again until nothing is left, with a burst on the result pads; it shows how many merges are possible.
  **EQUIP BEST** puts the strongest soldiers (squad + inventory, by hp × damage / cooldown) into the battle
  squad and the rest back into the inventory. Both are server-checked (`onAutoMerge`, `onEquipBest`) and
  locked during rolls and battles.
- **Merge levels are bought per soldier** (UPGRADES tab of the left panel): every class has its own merge
  level limit. You start unable to merge a class at all; to merge it up to level N you buy that level for
  that class with **coins and enough cleared waves** (`Balance.TierUnlocks`, the same price list for every
  class): Lv 2 = 50 coins, Lv 3 = wave 1 + 150, Lv 4 = 3 + 400, Lv 5 = 8 + 1000, Lv 6 = 15 + 2500, Lv 7 = 25 + 6000,
  Lv 8 = 40 + 15000, Lv 9 = 60 + 40000. Locked merges do nothing (a message explains); auto merge, drops
  and the start level respect the limit of each class (`profile.tierUnlocked[class]`).
- **Saving:** (the HUD says "progress saved" or, in red, "saving OFF"; it is also saved after every won wave) progress (coins, soldiers, inventory / squad, merge slots, waves, unlocked classes and
  levels, difficulty, start level) is saved to a DataStore (`Balance.DataStoreName`) when you leave, every
  `Balance.SaveInterval` seconds, on level unlocks and when the server shuts down. It needs "Enable Studio
  Access to API Services" in Game Settings > Security (and a published place) to work in Studio. If a save cannot be read, that
  session is not saved (the old save is never overwritten).
- **Admin tools:** the game owner, everyone in Studio and the ids in `Balance.AdminUserIds` see a small red
  **ADMIN** panel (top right): **+ PROGRESS** (+1 wave and `Balance.AdminProgressCoins` coins), **UNLOCK ALL** (every class with all its merge levels, every spell, all merge slots, the best start
  level, every wave and `Balance.AdminUnlockCoins` coins) and **RESET**
  (asks first, wipes all progress and the saved data). The server checks the admin rights (`isAdmin`).
- **FIGHT** (bottom bar) opens the battle panel (wave, difficulty, START WAVE) from anywhere; the button
  shows the wave and difficulty, or "Next wave in Ns" (see "The FIGHT button and the battle panel").
- **Merge effect** (`Plots.mergeEffect`): orbs fly in arcs, then a white flash, colored core, 2–3
  shockwave rings, a light pillar, sparks, the new soldier popping in with an overshoot and a
  rising "MERGE! Lv 3". It scales with the level.
- **Roll animation (UI only):** `playRollAnimation(pool, classes, tiers, onLanded)` in `Main.client.luau` is kept for
  a future shop; summoning does not use it any more (no waiting).
- Labels in the world only show when you are close.

## Plot layout (along the z axis)

```
lobby (-68 … -4)              →  road (-4 … 30)  →  gate  →  ARENA 1 – Training (30 … 228), the plot is 160 wide
your spawn (z = -9)              ~34 studs of grass   name    SQUAD, one row of six        z = 43 (six holographic rings 12 apart)
MERGE BOARD 6 × 6 (z = -50…-20)  with a worn road             ROUND FIGHT ARENA, one step up (z = 56 … 196, 140 across)
                                                              enemy wave, one row side by side (z = 204), visible before the battle
```

## Fight arena (placeholder)

Both sides stand visible in their rows: your six on their pads at z = 43, the wave in one row at z = 204. **Nobody
is teleported**: when the battle starts both sides turn to each other and **walk** up onto the round fight arena,
which is **one step (2 studs) higher** than the rest of the plot, and fight there (every tick the server snaps a
fighter's height to the ground under it, so they walk up the step and down past the edge). The arena is a simple
placeholder: a round platform 140 studs across (twice the old arena's depth) with a darker rim and a low ring step,
isolated in `src/server/Services/FightArena.luau`: replace `FightArena.build` with your own design. The rest of the
game only needs the returned `heightAt(worldPos)`, `center`, `radius` and `spot(side, index, count)` (see the comment
at the top of that file). The part named `FightArena` carries a `TopY` attribute (the height of its top).

**The squad is exactly six** (`Balance.SquadSize`, ONE row of six side by side, `Balance.SquadColumns` = 6), nothing
more to buy around it. In the arena the six pads stand 12 studs apart (`Balance.SquadSpacing`, the merge board is
tighter) so the characters have room and are seen one by one, just before the round platform's step (z 43 of a plot
that is 160 wide and 296 long). They are **holographic rings** (`holoPad` in `Plots.luau`): an empty ring glows cyan
and breathes (the client pulses it) to ask for a soldier; with a soldier on it, it turns grey and quiet. They give
**no bonuses**: where a soldier stands only decides which enemies it meets first. The **squad bar** (top left) shows
the same six places in one row, left to right like the pads ("▲ ENEMIES" above it); drag cards onto it from the
inventory, between its slots, or onto the main panel to unequip. The bar moves by its grip and hides during a battle.
The dock and PLAY sit under it, the HUD (level, coins) in the bottom left corner. (A profile saved with the old 3 × 3
squad keeps its soldiers: the three beyond the sixth place move to free pads of the merge board, or are sold when
there is none.)

**The rows and who fights whom:** the enemies stand in ONE row too (`Plots.enemyGround`: 7 studs apart, centered,
the boss in the middle, melee around it and the shooters on the flanks; the PINCER twist splits the row into two
groups with a 24 stud gap, `Mutators.Defs.pincer.Gap`). Everybody fights the nearest enemy and walks straight at it
over the platform, so **where you put a soldier decides what it fights**: a soldier on the left pad meets the enemies
on the left. The enemy formations of `Config/Formations.luau` are no longer used to place anybody (nobody is moved
into the arena); the module and its test stay for a future layout mode. Battles are long (`Balance.BattleTimeLimit`
= 90 s).

## Multiple players

Every player gets their **own plot** (own spawn, merge board, squad, arena, enemy preview), so
nothing is shared and nobody sees another player's soldiers move. Plots are laid out in a grid
(`Balance.PlotsPerRow` = 4 per row, `PlotSpacingX` / `PlotSpacingZ` apart) and the slot is freed
when a player leaves. Each plot has its own `SpawnLocation` (`player.RespawnLocation`), and a
safety check moves the character there if it spawned somewhere else. Client-side effects (hover
disc, drag) only look at the player's own plot; server-made effects (roll, merge, drops)
replicate to everyone.

## Soldier classes

**There is one class now: the Mage** (`Units.ClassList = { "Mage" }`, unlocked from the start, four level 1 Mages in a
new squad). The table below is the removed roster; the lucky-drop machinery stays in the code for a future class
(with no locked class the draw is empty).

| Class | In the lucky-drop draw from | |
|---|---|---|
| Knight, Archer | — | start classes |
| Hunter | wave 3 | new in Arena 1 (very long range) |
| Mage | wave 6 | new in Arena 1 (splash damage) |
| Tank | wave 10 | new in Arena 1 (lots of HP) |
| Berserker | wave 15 | reserved for the wave system, for now |
| **Soldier** | wave 15 | **LEGENDARY**: the 9-stage designed soldier, a rare lucky drop (a quarter of the normal chance inside the draw) |

The **Soldiers** tab (left panel) is the index: every class with a 3D preview, its stats and
either "Unlocked" or "Lucky drop from wave N".

## Coins and XP from kills

There is **no coin bonus for clearing a wave**. Every enemy you kill **drops coins that fall on
the ground**: a few gold coins pop out, bounce and lie spinning where the enemy died (only you see
your coins). **Walk close and they fly to you smoothly** (`Balance.CoinMagnetRadius`), your coin
counter pulses, and only then are they paid. The coins of a kill land close together and the pull
radius is generous, so collecting them is easy. So you have to step into the arena to collect them;
after `Balance.CoinLifetime` seconds they fly to you on their own, and when the next battle starts
the leftovers are paid automatically, so nothing is ever lost. A wave you lose still drops coins
for what you killed, so you can always progress.

One kill's coins are

`floor((KillCoinBase + KillCoinPerWave × wave) × (1 + KillCoinPerLevel × (enemy level − 1)))`

times the difficulty's reward multiplier (Easy ×0.7, Normal ×1, Hard ×1.6, Nightmare ×2.6), split into at most
`CoinsPerKillMax` pickups. With the defaults (`KillCoinBase` 8, `KillCoinPerWave` 2,
`KillCoinPerLevel` 0.5) a wave-1 enemy pays 10 coins, a wave-5 enemy 18, and a level-2 enemy 1.5×
as much.

**Bonus:** every kill also rolls a chance for **more** (`Balance.CoinBonus`): 15% for ×2, 4% for ×3 and
1% for ×5 (about one kill in five has a bonus). A bonus multiplies the coins and the XP of the kill: it
drops bigger, colored XP orbs, more of them, and a floating **BONUS xN!**. The coins go straight to your
balance and the result screen shows the total of the wave as one small line.

## Battle timing and the rewards

- **Countdown:** confirming the wave shows a big **3 · 2 · 1 · FIGHT!** before the soldiers march into the
  arena (`Balance.BattleCountdown`).
- **After a wave** there is no result box: the rewards **drop in one after another at the top of the screen**
  (a small pill each): the title (WAVE n CLEARED / BOSS / ELITE), `+N coins` (and the streak), every dropped
  soldier with a little 3D card (and BONUS LEVEL), a lucky drop ("LUCKY DROP: X unlocked!", chance by difficulty,
  guaranteed after `Balance.LuckyDropPity` clears without luck). The drops go **straight into the
  inventory** (`CollectDrops` right away; `Balance.DropCollectTime` is the server's fallback). After a defeat one
  pill says "DEFEAT · +N coins" and there is a `DefeatCooldown` (3 s) pause. You are brought back to your spawn.

## Enemies and waves (Training Camp: 100 waves, 20 phases, 20 bosses)

**The enemies are the 13 designed goblins** of the sheet "Roblox R15 — Goblin NPC" (`Enemy.luau`): five standard
goblins (Prcek with a dagger, Rubáč with sword and shield, Lučištník with a bow, Mág in purple, Léčitel in white), three
minibosses (Železný tesák in red armor with a cleaver and a skull shield, Jedový stopař with a crossbow and poison vials,
Runový šaman with a skull headdress and runes) and five bosses (Král Grubnak, Kovář Morg, Morová matka, Arcimág Vex,
Houbový titán). Every one is a stocky R15 rig (big head, short body) with the design's clothes, armor and weapon
welded on the right body parts, so the idle / run / attack / death animations work. `Enemies.luau` spreads them over
the roster: a mob archetype takes turns between its designs family by family (Grunt = Prcek / Rubáč, Archer = Lučištník /
Jedový stopař, Brute = Železný tesák / Rubáč, Shaman = Mág / Léčitel / Runový šaman), a boss archetype boss by boss
(Brute = Kovář Morg / Houbový titán, Chief = Král Grubnak, Archer = Jedový stopař, Shaman = Morová matka / Arcimág
Vex); the family still tints the skin. A boss's ability comes from its archetype, not its look.

The **Archer** too (Apprentice, Marksman, Tracker, Ranger, Elven Archer, Shadow Stalker, Storm Archer, Royal
Master, Legend; a bow in the left hand and a quiver on the back).

### The Knight, the Archer and the Mage: 30 merge levels (the R15 evolutions)

The **Knight**, the **Archer** and the **Mage** have **30 merge levels** (`maxTier = 30` in `Units.Classes`). Every
level is a complete R15 character of its own, from 30 models per class: `design/KnightEvolution/`
(`Evolution_L01_…rbxmx` … `Evolution_L30_…rbxmx`), `design/ArcherEvolution/modely/` (`Archer_L01_…rbxmx` …, the archer
woman with her bow, quiver and hairstyles) and `design/MageEvolution/Mage_R15_30_levelu/modely/` (`Mage_L01_…rbxmx` …,
the mage with his staffs, crystals, robes and hats; the crystals' lights come along); the names are in each
package's `prehled-levelu.csv`, the overviews in `vsech-30-levelu.png` (under `nahledy/`): six eras of five levels,
from prehistory to the year 3000.

| Levels | Era | Ranks |
|---|---|---|
| 1 – 5 | Pravěk (prehistory) | První člověk, Sběrač, Lovec, Stopař, Náčelník |
| 6 – 10 | Starověk (antiquity) | Osadník, Měděný strážce, Bronzový bojovník, Falanga, Legionář |
| 11 – 15 | Středověk (Middle Ages) | Zbrojnoš, Pěší rytíř, Plátový rytíř, Velitel, Královský rytíř |
| 16 – 20 | Průmysl (industrial) | Průzkumník, Mechanik, Parní strážce, Ocelový veterán, Dieselový titán |
| 21 – 25 | Moderní (modern) | Taktický strážce, Specialista, Těžký operativ, Exo prototyp, Exo elita |
| 26 – 30 | Budoucnost (future) | Sentinel, Vanguard, Nano strážce, Nova velitel, Apex |

| Levels | Archer ranks |
|---|---|
| 1 – 5 | První lovkyně, Stopařka, Lovkyně, Sběratelka trofejí, Náčelnice lovkyň |
| 6 – 10 | Lučištnice osady, Měděná strážkyně, Bronzová lovkyně, Pouštní průzkumnice, Velitelka střelkyň |
| 11 – 15 | Lesní lučištnice, Hraničářka, Ocelová střelkyně, Královská lučištnice, Mistryně luku |
| 16 – 20 | Průzkumnice, Mechanická střelkyně, Parní lučištnice, Ocelová průzkumnice, Dieselová lovkyně |
| 21 – 25 | Taktická lučištnice, Specialistka, Elitní průzkumnice, Exo střelkyně, Exo mistryně |
| 26 – 30 | Sentinel, Vega, Nova, Astral, Apex lučištnice |

| Levels | Mage ranks |
|---|---|
| 1 – 5 | Učeň, Zaříkávač, Kostěný šaman, Šaman totemu, Velký šaman |
| 6 – 10 | Chrámový kněz, Faraonův mág, Věštec, Učenec z Alexandrie, Velekněz |
| 11 – 15 | Čaroděj, Kouzelník, Runový mág, Hvězdný mág, Velmistr magie |
| 16 – 20 | Alchymista, Parní mág, Mechanik éteru, Elektromág, Mistr éteru |
| 21 – 25 | Technomág, Kybermág, Datový šaman, Strážce sítě, Plazmový velitel |
| 26 – 30 | Hvězdný poutník, Kosmický mág, Nebeský mudrc, Arcimág, Apex mág |

`tools/evolution_from_rbxmx.py` turns the models into data (`python3 tools/evolution_from_rbxmx.py
design/KnightEvolution src/shared/StageModels/KnightEvolution Knight`, `python3 tools/evolution_from_rbxmx.py
design/ArcherEvolution/modely src/shared/StageModels/ArcherEvolution Archer`, `python3 tools/evolution_from_rbxmx.py
design/MageEvolution/Mage_R15_30_levelu/modely src/shared/StageModels/MageEvolution Mage`): one module per era (body parts, the 15 joints and
the gear relative to its body part) plus `init.luau`, which loads an era the first time one of its levels is asked
for. `SoldierRig.luau` (`buildEvolution`) builds the character from that data at runtime: the body parts with the
model's own proportions, Motor6D joints and a Humanoid (so the battle animations work), the gear welded on; for
UI previews and holograms it is a statue (everything anchored). **What the hands hold is separate**: the converter
writes the right hand's parts as `weapon` and the left hand's as `offhand` (relative to the hand, following weld
chains such as staff → Handle → hand), and `shared/Weapons.luau` builds them as the models `Weapon` / `Offhand`
inside the character, gripped by a Motor6D (`RightGrip` / `LeftGrip`, as Roblox tools are). The grip is the
design's rest pose (no "hold" animation turns it), the attack animation swings the hand and the weapon with it,
and `Weapons.equip(character, "RightHand", parts, scale, static)` can give a character another weapon later. Levels 10 … 30 have their own level colors
(`Levels.Colors`) and prices (`Balance.TierUnlocks`: two more waves and 25 % more coins per level). The old
9 knight, archer and mage cards stay in the file only as a fallback without data. Run the tool again after changing a model.

The **Soldier class is an R15 character** too (`src/shared/SoldierRig.luau`, from `design/SoldierMerge_R15_Builder.lua`):
9 designed ranks, one per merge level (Recruit, Private, Corporal, Sergeant, Lieutenant, Captain, Major, General,
Legend), with gear welded on the limbs, and it is animated in the battle (idle, run, attack, death). The base rig
is made once on the server and kept in ReplicatedStorage (`R15Base`, see `src/shared/Rig.luau`) so the client can
clone it for the cards; UI previews and holograms are still statues of it. The other classes are block models.

Enemies are **R15 characters** (a rig made once on the server and cloned; goblin ears, nose, eyes, clothes and a
weapon are welded on) with animations: idle, run, an attack swing (slash / bow lunge / cast), boss abilities and a
fall when they die. Their attacks are shown (a flying arrow, a glowing orb, a slash arc). If the rig cannot be
made, the old block model is used. `EnemyHpBoost` (1.7) and `EnemyDamageBoost` (1.4) in `Balance.luau` make every
enemy stronger in one place.

Enemies are **not** your soldier classes. Every map has its own enemy folk (`Config/Enemies.luau`, models
in `src/shared/Enemy.luau`). The Training Camp has **100 waves split into 20 phases of 5 waves**
(`Balance.PhaseLength`), and the game changes every 5 waves: **one new mob joins** (the newest is twice as
common, the mobs of the last three phases stay) and the phase ends with **its own boss**. The mobs come
in five families that rank up every 4 phases (a bit stronger and bigger each time), and every family has
four archetypes: a grunt, an **archer** (ranged), a **brute** (tanky) and a **shaman** (splash).

| Phases | Waves | Family | New mobs, one per phase | Bosses (waves 5, 10, 15 …) |
|---|---|---|---|---|
| 1 – 4 | 1 – 20 | **Goblin** | Goblin, Goblin Archer, Goblin Brute, Goblin Shaman | Grubnak the Bully, Goblin Chief, Goblin King, Shaman Elder |
| 5 – 8 | 21 – 40 | **Hobgoblin** | Hobgoblin, Archer, Brute, Shaman | Hobgoblin Warlord, Deadeye Hob, Bonecrusher, Hexmaster |
| 9 – 12 | 41 – 60 | **Orc** | Orc, Archer, Brute, Shaman | Orc Chieftain, Orc Sniper Lord, Mountain Breaker, Orc Warlock |
| 13 – 16 | 61 – 80 | **Troll** | Troll, Archer, Brute, Shaman | Troll King, Troll Stalker, Colossus, Troll Witch Doctor |
| 17 – 20 | 81 – 100 | **Demon** | Demon, Archer, Brute, Shaman | Demon Lord, Hellbow, Infernal Titan, **The Demon Emperor** (wave 100) |

The rules (`Config/Waves.luau`): a phase starts with a few enemies and gets bigger every wave, later phases
start bigger (`EnemyBase + 2 + (phase - 1) // 3 + place in the phase`, 12 at most); the enemy **level is the
phase number** and every level makes enemies `EnemyLevelScale` = 1.2× stronger (wave 100 = level 20, about
30x wave 1, plus the family bonus), so the game stays fair for a first arena; every 5th wave the last enemy
is the phase's boss. Bosses and better mobs drop more coins (`coins` in `Enemies.luau`), and the coins of a
kill grow only a little with the level (`KillCoinPerLevel`). Clearing wave 100
the first time **completes the map** ("TRAINING CAMP CLEARED!"); you can still repeat
any wave. The wave heading over the enemies shows the phase, `WAVE n / 100` and the count. A new map is a new
block in `Config/Maps.luau` (`phases` can be written by hand or generated like the Training Camp's).

## The final boss: Grubnak — The Rift King (wave 100)

The last boss of the Training Camp (`Boss20`, archetype `RiftKing`) has his own fight: `server/Services/RiftKing.luau`,
all numbers in `shared/Config/RiftKing.luau` (health, damage, ranges, cooldowns, warning windows), the model in
`shared/Enemy.luau` (look `RiftKing`: black plate with gold trim, purple rift crystals, a gold crown with crystal
points, a red cape, a rift orb in the left hand and the giant crystal hammer in the right; about twice a player's
height). You stand in the arena during the battle, so you dodge too: every attack goes **ground warning → dodge
window → impact**. Warnings lie flat on the floor with a bright border and a translucent fill, never hurt, mark
exactly the area that is hit, and are removed after the impact. Your soldiers in the area take a multiple of the
boss's damage, your character takes health points; one impact hits a target once.

1. **Crystal Volley** – three crystals fly along arcs onto red circles (radius 5) locked 1.3 s before they land.
2. **Hammer Slam** – the hammer goes up and an orange cone (16 studs, ±35°) is locked in front of him; it comes down after 1 s.
3. **Rift Shockwave** – a 0.9 s wind-up (a pulsing glow at his feet), then a purple ring runs outward at 14 studs/s;
   only the moving band hurts, the inside never does, and a character mid-jump (or 2.2 studs up) is over it.
4. **Meteor Rain** – 4 red circles (6 enraged) with at least a 4-stud path between them; purple crystal meteors
   land 1.5 s later.

A hit of 6 % of his health or more **staggers** him (a flash and a step back). Below 30 % he is **enraged**: the
crystals glow brighter with their own lights, glowing cracks appear on the armor plates, cooldowns shrink to 60 %
and attacks come in pairs (a shockwave is followed by a volley, a slam by meteors), each with its own full warning.
A wide **boss health bar** at the top of the screen (remote `BossHp`) shows his health and turns red with an
ENRAGED tag. Targeting, health and damage are the server's (the battle simulation), several players in the arena
all dodge, and `RiftKing.cleanup` removes every warning, crystal and ring when he dies or the battle ends.
To test him: ADMIN → wave 100 (the admin tools set the wave), then PLAY. `python3 tools/tests/run_riftking_test.py
[luau]` runs the fight's logic test (standalone Luau with Roblox stubs: timings, locked warnings, one hit per impact,
the jump over the ring, meteor gaps, enrage, stagger, cleanup); the model and animations need a Studio playtest.

## The Mage's battle AI (utility AI)

The **Mage** does not just stand and shoot: every Mage in a battle gets a **brain** (`server/Services/MageBrain.luau`,
one instance per Mage, created by BattleService at the start of the fight and stepped every simulation tick). Every
0.2–0.4 s (random offset, so the mages never think in the same tick) it scores the possible actions 0–1 and runs
the best one, with a little inertia for the current action: **attack** (the basic spell on its target), **strong**
(an AoE into the centroid of a cluster of enemies, a chain, a singularity, or a finisher on a low-HP target),
**escape** (it steps out of a telegraphed enemy area such as the Rift King's circles, which carry the `Hazard`
attribute), **shield** (below 35 % HP or when threatened), **blink** (surrounded), **support** (heal the ally with
the lowest HP, from level 21), **approach** (nothing in range: it walks toward the nearest enemy and stops the moment it has one in range) and **idle**. A Mage
**stands still while it has anyone in range** and never backs into the enemies: its intelligence shows in whom it
targets and which spell it uses, not in running around. Targets are chosen by a weighted
score (proximity, low HP, hate toward whoever hurt it, enemy type: archers and shamans before brutes) with
memory (a target is held 1.5 s unless a clearly better one appears) and a level-scaled reaction time (0.6 s at
level 1, 0.15 s at level 30); it sometimes hesitates or aims an AoE a little off (less at higher levels).

The Mage casts all the spells of the game (the player has none). A **Healing Light** (the old player's Heal) is the
Mage's from level 2: the newest heal spell is always carried, besides the strong spells and the repel.
Spells (`shared/Config/MageSpells.luau`) come by era and level: a basic bolt per era (fire stone, sun ray, magic
missile, arc bolt, plasma beam, quantum bolt) plus the newest unlocked strong spells, 1–10: one extra, 11–20: two,
21–30: three and a heal (spark swarm, sandstorm, chain lightning, ice barrier, steam blast, electric arc, EMP slow,
med drone, quantum blink, gravitational singularity, star rain, nano heal). Strong spells cost **mana** (regenerating)
and have cooldowns, so the brain saves them; before one, the staff's crystals brighten and grow and the arm
rises (the telegraph), then the spell fires. All numbers live in `shared/Config/MageConfig.luau`; set
`Debug = true` there or `workspace:SetAttribute("MageDebug", true)` at runtime for a label over every Mage with
its action, score, target, mana and HP. `python3 tools/tests/run_magebrain_test.py [luau]` runs the brain's logic
test in standalone Luau (spell unlocks, attacks, standing still in range, strong spells and mana, healing, bounds).

## The battle panel is a wave browser

PLAY opens the battle panel (640 × 380, drawn at 1.3×). Left: the **difficulty** as four rows (Easy, Normal, Hard,
Nightmare) each saying what it multiplies (enemies, coins, XP, extra drops) and the squad's synergy. Right: **every
wave of the map as a tile**, five per row (a row is a phase with its name, the fifth tile is the phase's BOSS):
cleared waves are green, your next wave orange, locked waves dark, the selected one has a white frame, and every
tile shows a colored dot per **twist** of that wave (`Config/Mutators.luau`, deterministic, so the browser can show
them in advance). Click a tile (or `<` `>`) to select a wave you have reached; under the grid the selected wave is
described: phase, enemy count, the boss, its twists with one line of advice each, and whether it is cleared (coins
and a drop, no progress) or your next one. START WAVE names the wave and the difficulty.

## The FIGHT button and the battle panel (starting a wave, difficulty and wave choice)

Nothing pops up when you walk onto the raised fight arena. The **FIGHT** button in the bottom bar opens
the **battle panel** in the middle of the screen (click FIGHT again, the X or Esc to close it). In the
panel you choose:

- the **difficulty** (`Config/Difficulties.luau`): **Easy / Normal / Hard / Nightmare** change the enemies' power
  (×0.7 / ×1 / ×1.6 / **×2.4**), the coins per kill (×0.7 / ×1 / ×1.6 / ×2.6), the XP (×0.7 / ×1 / ×1.5 / ×2.5)
  and the lucky-drop chance (25 / 35 / 50 / 60%). **Nightmare** is the hardest but pays the most: **one extra
  drop** after every won wave (a second card next to the first), much more XP and coins;
- **which wave to fight**, with `<` and `>`: any wave up to the highest one you reached, so you can
  repeat earlier ones. It also shows the phase, how many goblins the wave has and whether it is a boss
  wave. Clearing a wave you already cleared gives coins, a drop and a lucky-drop roll but **no
  progress**; clearing the newest wave moves you on;
- then **START WAVE** (it shows "Next wave in Ns" during the pause after a wave).

The server checks everything (not during rolls and battles; the wave has to be one you reached). The
(invisible) **BattleZone** box over the fight arena is not used for any menu now, it only stays as a marker
of the fight place (`FightArena.build`). The enemy preview and its heading follow your choice.

## Tactics, rewards and the long game

**Tactics before the fight**
- **One row:** the six pads stand side by side; a Mage on the left pad meets the enemies on the left. The pads
  give no stat bonuses.
- **Synergies** (`Synergy.luau`, shown in the battle panel): **Ranged** (the Mage) 2 = +10% damage, 3+ = +20%
  (the Frontline and mixed-class bonuses need classes that no longer exist).

**During the fight**
- **No spells of your own any more** (the Mages cast everything, see "The Mage" below). The paragraph that follows
  describes the removed player spells: you carried **two spells at a time**, one on **Q** and one on **E**, chosen in the
  **SPELLS tab** of the left panel (click Q or E on a spell you own; if it is in the other slot the two swap;
  not during a battle). You start with **Meteor** and **Heal**; every other spell is **found only by grinding**:
  after a won wave of its wave or higher it can drop (chance = the difficulty's lucky-drop chance x
  `Balance.SpellDropFactor`, doubled on a boss wave, one spell at a time, and it stays yours for good, also after
  for good). The spells (`Config/Spells.luau`, the wave they can drop from in brackets):
  **Meteor** (start) damages the enemies in a 9 stud circle (12% of their max HP, cooldown 7 s): a warning disc, a
  burning fireball, shockwaves and sparks; **Heal** (start) heals your soldiers in a 10 stud circle (35% of their
  max HP, 18 s); **Smite** (wave 25) calls a jagged lightning bolt on every enemy (20%, 30 s); **Frost Nova**
  (wave 50) hurts the enemies in a circle (6%) and makes them act at half speed for 4 s (14 s); **Divine Shield**
  (wave 75) lets your soldiers in a circle take 85% less damage for 4 s (24 s); **Armageddon** (wave 100) rains six
  meteors on random enemies (10% each, 45 s). Percent-damage spells do only 35% of their damage to a boss.
  In a battle two buttons in the bottom right show your two spells with their cooldowns (Q / E or a click).
  **Auto aim:** the spells aim themselves (damage spells at the biggest group of enemies, Heal at the group
  that lacks the most HP, Divine Shield at the biggest group of your soldiers; Smite and Armageddon need no aim;
  with no target you get a message and the spell is not used up); **hold SHIFT** to aim with the mouse (a ring
  shows where it lands). Every slot has its own cooldown and is ready at the start of every wave; the server
  checks the cooldown, the aim (inside `Balance.SpellRange`) and that a battle is running (`BattleService.spell`).
  E summons at the altars in the lobby, so there is no conflict.
- **Damage numbers** float above every hit (white on enemies, red on your soldiers; not more than 14 per tick).
- **Boss waves** (5, 10, 15) get a big red banner during the countdown, double account XP and a guaranteed
  **bonus drop** (one level higher). Any drop has an 8% chance to be a bonus drop ("BONUS LEVEL!").

**Rewards**
- **Account level rewards:** every level gives coins (50 × the level), every 5th level also +3 merge slots.
  New maps and soldiers are meant to unlock with the level later.
- **Win streak:** every wave won in a row gives +5% coins from kills, up to +25% (a defeat resets it; the result
  screen shows "streak xN").

**Content and the long game**
- **Ascended soldiers:** two **level 9** soldiers of a class whose level 9 is bought merge into one **ASCENDED**
  soldier (`Grid.mergeResult`): +50% HP and damage (`Units.AscendedBonus`), its class passive doubled, a golden
  halo, sparkles and a "★" on its card, sells for 3x. It cannot be merged further.
- **The Mage's attack is an arcane fireball** (`effect` in BattleService): the staff tilts toward the enemy (the grip's
  Motor6D turns, with a thrust animation), its crystal charges for 0.22 s with a growing purple glow, then a purple ball
  with a trail flies straight at the target and bursts over the splash area (`Balance.SplashRadius`); its splash damage
  is the Mage's Arcane Burst passive.
- **Class passive** (`Units.Passives`, shown on a card's popup): Mage **Arcane Burst**
  (hits splash 50% to nearby enemies). Ascended = doubled. (The other passives in the table belong to removed
  classes.)
- **Boss abilities** (`Balance.Boss*`): a Brute boss **slams** every 8 s (2x damage + 1 s stun around it), a Chief
  **summons** two mobs of the phase at half HP, an Archer boss fires a **volley** at every soldier in range every
  6 s, a Shaman boss **heals** its whole wave 8% every 7 s. The boss's look decides (Config/Enemies.luau).
- **Elite waves** (`Balance.Elite*`): from wave 3 a normal wave has a 10% chance to be ELITE: golden, 1.5x stronger
  enemies, a "ELITE WAVE" banner, double coins, a guaranteed extra drop and a doubled spell-drop chance.
- **Battle speed** (`Balance.BattleSpeeds`): the SPEED button in the battle panel cycles 1x / 2x, also during a
  battle (every tick of the simulation counts double). **SKIP** on the result screen delivers the drops at once
  and the next wave may start right away.
- **Achievements** (`Config/Achievements.luau`, the ACHIEVEMENTS button under the daily quests): 18 one-time
  goals (kills, merges, level 5 / 9 / Ascended soldiers, waves, bosses, Nightmare, summons, account
  level) with coins + XP; the latest one is your **title**, shown over your head (★ Warlord).
- **Offline income** (`Balance.Offline*`): while you are away your camp earns 6 coins per hour for every wave
  of your best wave, up to 8 hours; a WELCOME BACK popup pays it when you come back.
- **Into the arena:** START WAVE moves you (the player, not the squad) onto the near edge of the round fight arena,
  behind your squad and looking at the enemies, so you are in the fight for your Q / E spells. After the battle you are brought back to
  your spawn. The camera stays yours; only the left
  panel, the quests and the achievements button hide while the battle runs.
- **Sounds** (`Config/Sounds.luau`): Roblox's built-in sounds for clicks, summons, merges, level ups, spells,
  boss intros, won / lost waves … replace any id with your own asset; `Sounds.Music` (empty by default) loops
  as music. The server asks for sounds with the `Sfx` remote.
- **Settings** (the gear, top right): volume, damage numbers (the server stops sending them), music. Saved with
  the profile (`profile.settings`).
- **Mobile:** the UI scales down on small screens (`UIScale` by viewport height), drag & drop works with a finger,
  spells always aim themselves on touch (no SHIFT).

## Squad pad auras (the designed battle rings)

A soldier on a **squad pad** lights it up with the aura of its level's rarity (`design/BattleRing_Auras.rbxmx`,
turned into data by `tools/rings_from_rbxmx.py` → `src/server/Services/DecorData/BattleRingAuras.luau`, built by
`setRingAura` in Plots.luau): **Common** (Lv 1–2) a soft glow disk, **Uncommon** (3–4) + rising sparks, **Rare**
(5–6) + a light pillar, **Epic** (7) + a ring of runes, **Legendary** (8) + circling orbs, **Mythic** (9 and Ascended)
+ a second rune ring and beams. The client spins the runes and orbs and pulses the glow. Run the tool again
after changing the design (`python tools/rings_from_rbxmx.py design/BattleRing_Auras.rbxmx
src/server/Services/DecorData/BattleRingAuras.luau`).

## Signs and labels

The world stays quiet: the small area signs (MERGE BOARD, SQUAD, the altars …) show only from about 16 studs
and are faint, a soldier's name / level label shows from 40 studs (in a battle the HP bar widens it, because
the battle is watched from above), and the **bonus tags of the squad pads are hidden**: hover a pad with the
mouse to see its bonus (also while dragging).

## The look of the pads (the designed fight slot)

The **merge board** is kept minimal: every one of its 36 pads is only a flat dark disc with a thin ring in the
state's color (grey empty, the soldier's level color glowing, dark and faint when locked). The squad pads and the
enemy preview use the full **fight slot** of the design
(`design/TrainingArena1.server.lua`, `design/FightSlot_Variants.rbxmx`): a stone base, a glowing ring, a wooden
top, four posts with gold caps and a word on top. `Plots.decoratePad` builds it around the invisible
`Slot<id>` block, and `Plots.render` changes the state: an **empty** pad has a grey ring and a "+" (the squad
pads keep their bonus color: green = HP, orange = damage), a pad with a **soldier** has a glowing ring in the
soldier's **level color** (gold at the maximum level), a pad that is **not bought yet** is dark and says
"LOCKED", the enemy pads have a red ring. While you drag a soldier the ring of the target shows the result
(gold = merge, blue = swap, white = move). Pads are now 0.6 studs high (`PAD_TOP`), the soldiers stand on the
wooden top.

There are no holograms on the fight arena any more: the soldiers fight from where they stand, so the pads
themselves show the line-up.

## The look of Arena 1 (designed in Claude Design)

`design/TrainingArena1.rbxmx` is turned into data by `tools/decor_from_rbxmx.py`
(`python tools/decor_from_rbxmx.py design/TrainingArena1.rbxmx src/server/Services/DecorData/TrainingArena1.luau`)
and built by `Services/ArenaDecor.luau`: the **entrance arch** ("TRAINING ARENA 1") over the gate with fences on
both sides, torches and banners, and around the fight place weapon rack, training dummies, archery targets,
hay, sandbags, barrels and crates, plus the **ring marks** on the fight platform. The sand floor and the
wood colors of the map come from the design too (`Config/Maps.luau`). One copy of every prop is stored; the
list of where the copies stand is `PLACEMENTS` in `ArenaDecor.luau` (x / z relative to the plot, optional
rotation), so moving or adding props is a one-line change. Props never block clicks (`CanQuery = false`) and
stay out of the fight area. A map with `decor = "..."` in `Config/Maps.luau` gets its own design the same way.

## Maps

One map: the **Training Camp** (Arena 1, goblins → demons, 100 waves). `Config/Maps.luau` holds the look (floor /
road / fence, decor id), the gate text and the roster's phases (`makePhases(prefix, names)`); `Config/Enemies.luau`
builds the roster with `buildRoster(prefix, families, bosses, power)`. A second map would be a new roster and a new
block in `Maps.Defs` / `Maps.Order`.

## Tuning

| File | What |
|---|---|
| `src/shared/Config/Balance.luau` | Board / squad / inventory sizes, merge-slot upgrades, prices, distances, timings |
| `src/shared/Config/Units.luau` | Classes, stats, power growth per level, unlock conditions |
| `src/shared/Config/Levels.luau` | Level colors, labels, sell value |
| `src/shared/Config/Difficulties.luau` | Easy / Normal / Hard / Nightmare: enemy power, coin and XP multipliers, extra drops, lucky-drop chance |
| `src/shared/Config/Waves.luau` | Wave rules (count, enemy level, phases, bosses) and coin rewards |
| `src/shared/Config/Enemies.luau` | Goblin kinds: stats, size, coin multiplier |
| `src/shared/Enemy.luau` | 3D goblin models |
| `src/shared/Config/Maps.luau` | Map looks |
| `src/shared/Grid.luau` | Pure merge / move / swap logic and slot ids |
| `src/shared/Soldier.luau` | 3D soldier models (also used by the UI previews) and the level looks |
| `src/server/Services/Plots.luau` | The 3D plot: lobby, road, board, squad, roll and merge effects, enemy preview |
| `src/server/Services/FightArena.luau` | The raised fight arena (placeholder) |
| `src/server/Services/BattleService.luau` | March into the arena and the battle simulation |
| `src/server/Services/GameService.luau` | Player flow: buying, inventory, merging, upgrades, drops |
| `src/client/Main.client.luau` | Bottom bar, left panel (Inventory / Soldiers / Waves), drag & drop, hover, toasts |

A new class = a block in `Units.luau` (with `unlock = { wave }` if it must be unlocked) plus a branch
in `Soldier.luau` for its look.

## TODO

- [ ] Own design of the fight arena platform (the props and slots are designed, the platform is a block)
- [ ] Real music and custom sound assets (Config/Sounds.luau)
- [ ] Game passes (2x coins, auto merge)
- [ ] A second map
- [ ] Trading / gifting soldiers between players
