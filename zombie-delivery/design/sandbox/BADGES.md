# 8.3 SANDBOX: Roblox badges, the setup guide

The sandbox can award twelve Roblox badges for its milestones, such as the first move, the first sale or a full
collection book. The code is ready, but every badge is **off** until you create it on Roblox and paste its id into the
game. A badge whose id is `0` is never awarded, and nothing breaks. You can set up all twelve badges at once, a few at a
time, or none.

## The badges

Type the **name** and the **description** into Roblox's form exactly as written here. They are also in
`src/shared/Config.luau` (`Config.SandboxBadges`), so you can copy them from there.

| Key in Config | Name | Description | When the game awards it |
| --- | --- | --- | --- |
| `firstMove` | First Move | Finish your first move. | A move ends as done or late with at least one piece brought home. Everyone in the crew gets it. |
| `tenMoves` | Seasoned Mover | Finish 10 moves. | The tenth finished move. The game counts finished moves in the save from version 8.3 on. |
| `cleanMove` | Handle With Care | Finish a move with nothing broken. | A finished move in which no piece broke. |
| `firstShow` | On Display | Put a piece on a display stand in your warehouse. | A piece of yours stands on one of your display stands. |
| `firstSale` | First Sale | Sell a piece from your collection. | Any sale: one piece, SELL… for many, or a visitor's offer accepted. |
| `hotSale` | Hot Seller | Sell one of today's hot items. | A sale with a piece of today's hot kind in it (the market). |
| `legendary` | Legendary Find | Bring home a legendary piece. | A legendary piece comes home, or the collection book already holds one. |
| `fullBook` | Completionist | Find every piece in the collection book. | Every piece of the book is found. |
| `firstUpgrade` | Upgraded | Buy your first upgrade. | Anything bought at the UPGRADES desk, including a bigger warehouse. |
| `warehouse5` | Logistics Tycoon | Grow your warehouse to level 5. | The warehouse reaches level 5, the Logistics centre. |
| `painted` | Fresh Paint | Paint your van at the PAINT shop. | Anything bought at the PAINT shop. |
| `topMover` | Top Mover | Top the TOP MOVERS board on a full server. | At least 4 players are on the server, and one of them is alone at the top of the board with a collection worth more than $0. |

Milestones a player reached earlier also count. The game checks them each time the player joins. If you set up the
Completionist badge later, a player whose book is already full gets it on their next visit. The exceptions are First
Sale, Hot Seller and Handle With Care. They happen at a single moment, so only the next sale, the next hot sale or the
next clean move awards them. Top Mover is checked whenever the board can change: a collection changes, or a player joins.

## 1. Create a badge on Roblox

1. Open **create.roblox.com** and sign in with the account that owns the game.
2. Go to **Creations** and open the published sandbox experience.
3. In its menu on the left, open **Engagement → Badges**. In an older layout, it can be called **Associated Items →
   Badges**. Click **Create a Badge**.
4. Fill in the form:
   - **Image**: a square picture. 512 × 512 pixels is a good size. Roblox shows it inside a circle, so keep the
     important part in the middle, away from the corners. Roblox moderates the image, so it can take a little while
     before it shows.
   - **Name** and **Description**: copy them from the table above.
   - Leave the badge **enabled**.
5. **The price:** creating a badge can cost Robux. Roblox has also given a few free badges a day for each experience.
   These rules change, so check what the **Create a Badge** page says right now before you create all twelve. If
   only a few are free today, create the most important ones first, for example First Move, First Sale and On Display,
   and the rest on later days.
6. Click **Create**. The badge now appears in the list.

## 2. Copy the badge's id

In the list of badges, open the **⋯** menu next to the badge and choose **Copy Asset ID**. The id is a long number, for
example `2124567890123`. You can also find it in the badge's web address on roblox.com, in the part after `/badges/`.

## 3. Paste the id into the game

1. Open `zombie-delivery/src/shared/Config.luau` and search for `Config.SandboxBadges`.
2. Find the badge's line by its key. Replace `id = 0` with the number you copied. For example:

   ```lua
   firstMove = { id = 2124567890123, name = "First Move", description = "Finish your first move." },
   ```

   Change only the number. Keep the key (`firstMove`) and the comma at the end of the line.
3. Repeat this for every badge you created. Badges you have not created yet stay at `id = 0`.
4. Sync the game into Studio as usual (`node tools/rojo-sync.js zombie-delivery` from the repository's root) and
   **publish** it. Badges are only awarded in the published game.

## 4. Check that it works

**In the admin panel.** Press P, open the **SANDBOX** tab and find the **Badges** line under the heading. It says how
many badges are set up, which ones still have id 0, whether this server awards badges, and how many it has awarded since
it started. Before you paste any id, it says that no badge is set up.

**In Studio.** As shipped (`Studio = false` in `Config.SandboxBadges`), the game never awards a badge in Studio, so
tests cannot hand out real badges. To try the real calls in Studio anyway, set `Studio = true`. Then watch the Output
for lines that start with `[SandboxBadges]`. Roblox may refuse badge calls in Studio, and that is fine. Set it back to
`false` before you publish.

**In the live game** (the real test):
1. Join the published game. A second account works best, because the badges then stay off your own profile.
2. Reach a milestone, for example finish a move with at least one piece brought home.
3. Roblox shows its own notification that a badge was awarded. The badge also appears on the account's profile under
   **Inventory → Badges**, and the admin panel's Badges line counts it.
4. To earn the same badge again for another test, remove it from the account on roblox.com: **Inventory → Badges**, the
   badge's **⋯** menu, **Delete from Inventory**. Then leave the game and join again. The game asks Roblox only once per
   visit whether a player has a badge.

**Fast ways to milestones** (admin panel, SANDBOX tab). These buttons count just like real play. Use them on a test
account, not on a player.
- **📖 FILL BOOK**: Completionist and Legendary Find. They are awarded when the book's milestones pay out, or the next
  time your money changes (for example **💰 +$10K**).
- **🏗 LV 5**: Logistics Tycoon and Upgraded.
- **📦 FILL STOCK** and then **⭐ FILL STANDS**: On Display, and Legendary Find when a legendary piece is among them.
- **🎨 UNLOCK PAINTS**: Fresh Paint. It is awarded the next time your money changes (for example **💰 +$10K**, or the
  stands' income) or when you join again.
- For Top Mover you need four players on one server: four accounts in the live game, or in Studio **Test → Clients
  and Servers** with 4 players and `Studio = true`.

## Good to know

- **Server only, once per visit.** The server decides every badge. For each badge, it asks Roblox once per visit whether
  the player has it already, and awards it only if not. If Roblox has a short outage, the award is tried again a
  moment later, up to three times. After that the game gives up until the next visit. No error ever reaches the
  players.
- **Turning a badge off.** Set its id back to `0`, or disable the badge on create.roblox.com. A disabled badge is simply
  not awarded.
- **Changing a badge's picture or text** on create.roblox.com needs no change in the game. Only the id matters.
- **Finished moves before 8.3** were never counted, so Seasoned Mover counts from this version on. First Move is
  awarded by the next finished move, or on joining once the count is at least 1.
- **Errors** show in the server's Output as `[SandboxBadges] …`, once for each badge. A badge id typed wrong (a badge of
  another game, or a deleted badge) shows there as well, as an error or as "Roblox did not award it".
