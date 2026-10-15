# The auction (8.8): the plan

This is the groundwork for the Auction House. It covers the rules, the building and the window. The server's part comes
in the next step. Until then `Config.Auction.On = false`, so nothing of it shows in the game.

## Why

- **The problem.** A piece on show earns money every minute. Selling it to the game pays about a quarter of an hour of
  that income (`Config.Collection` sell), so selling never makes sense.
- **The owner's direction.** Selling should make sense; he asked about "an auction in the finale". The plan, in order:
  - 8.7: offers between players and a FOR SALE price (done: `server/PlayerTrade.luau`, `Collection.transfer`,
    `Config.PlayerTrade`).
  - 8.8: the auction (this plan).
  - Later: the Grand Auction, with exclusive legendaries as an end-game goal.
- **Turned down.** No "display fatigue": a piece never earns less over time.

## What 8.8 built

| Piece | Where | What |
| --- | --- | --- |
| The numbers | `src/shared/Config.luau` `Config.Auction` | `On = false`; the round, the lot, the steps, the collectors, the building, the window |
| The rules | `src/shared/AuctionRules.luau` (pure) | schedule, lot clock, anti-snipe, bids, NPC collectors, settlement, consigning, view, words |
| The building | `src/shared/AuctionHouseLayout.luau` (pure), `src/server/SandboxWorld.luau` | the Auction House's 101 parts, built only while `On` |
| The window | `src/client/AuctionUi.luau`, `src/client/Main.client.luau` | LIVE LOT, CONSIGN, RESULTS; the building's sign and display painted |
| The remote | `src/shared/Net.luau` `"Auction"`, `Config.Robust.Limits.Auction` / `AuctionBid` | the protocol, no server listener yet |
| The money | `src/shared/AnalyticsPlan.luau` | `AuctionSale` (source, Sale), `AuctionBuy` (sink, Shop), `AuctionFee` (sink) |
| Tests | `tests/auction_test.luau`, `tests/auctionhouse_test.luau`, `tests/clientboot_test.luau`, `tools/phone-ui/auction.luau` | see **Tests** |

Nothing is paid and no piece moves yet.

## The rules

### The round
- **When.** Every 30 minutes (`Every = 1800`), at :00 and :30 UTC (`Offset = 0`). Every server shares the schedule
  because it comes from the clock alone, like the market's hot and cold days.
- **Phases** (`AuctionRules.phase`):
  - `consign`: from the end of the last round's results until 20 s before the start (`Close`);
  - `closing`: the last 20 s, when the lots are drawn up;
  - `live`: the lots, one after another;
  - `results`: 90 s after the last lot (`Results`).
  A round with no lots goes straight back to `consign`.
- **Lots.** At most 4 (`MaxLots` = `Config.Sandbox.MaxPlayers`): one per player on a full server. They go cheapest
  first, so the best lot is the finale (`AuctionRules.order`).
- **Length.** A full round runs 198 s as planned (4 × 45 s lots and 6 s gaps), and 278 s if every lot runs to its
  latest. That gives the 3 – 5 minutes the design asked for.

### Consigning
- **Where.** At the Auction House's desk ("Consign a piece"), or from the window's CONSIGN tab.
- **What may go:** one piece per player per round (`AuctionRules.canConsign`):
  - rare, epic or legendary (`Rarities`);
  - never broken;
  - only while the phase is `consign`;
  - not once the round is full.
- **Why Rare is in.** A big move brings home about 0.6 rares, 0.12 epics and 0.06 legendaries
  (`Config.Furniture.Collectibles`, `Config.Furniture.Big`). With epic and legendary alone, most rounds would have no lot.
- **A consigned piece** comes off its stand and earns nothing until its lot is settled or withdrawn. WITHDRAW is free
  before the round starts.

### A lot
- **Opening price.** It opens at the piece's **worth** (value × condition), rounded up to a whole bid step
  (`AuctionRules.opening`). It never sells for less: "a lot never sells below its value".
- **Clock.** Each lot runs 45 s (`LotSeconds`). A bid with less than 8 s left (`Snipe.Window`) puts the clock back to
  8 s, but never more than 20 s past the planned end (`Snipe.Most`). A sniping war therefore ends, and a round stays
  within its 5 minutes.
- **Bids** (`AuctionRules.canBid`):
  - always the next step: the price plus the step of its band (`Steps`);
  - never on your own piece;
  - never while you already lead;
  - never more than your money.
  A tap on BID sends `{ kind = "bid", lot, amount }`. A stale amount is refused, with the next bid named.

| Price from | $0 | $500 | $1,000 | $2,500 | $5,000 | $10,000 | $25,000 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Step | $25 | $50 | $100 | $200 | $250 | $500 | $1,000 |

### The NPC collectors
These keep the auction lively with only two players. They follow a pure bidding model (`AuctionRules.collectors`,
`npcNext`), seeded by the lot, so the same lot always plays the same way.

- **Who.** Three per lot, with names drawn from six fictional collectors (`Collectors.Names`).
- **Their max.** Worth × rarity's keenness (rare 1.05, epic 1.1, legendary 1.2) × the day's market (hot 1.15,
  cold 0.9) × a die in 0.9 – 1.2.
- **The floor.** The keenest one goes at least to the opening price, so every lot sells and never below its worth.
- **How they bid.** One answers a bid after 1.5 – 5 s (`Delay`), never later than 1 s before the end (`Last`). None
  outbids itself or goes past its max. An answer to a last-second bid comes at once, and the anti-snipe extension gives
  it room.

### The settlement (`AuctionRules.settle`, `payments`)
- **Who wins.** The top bid whose bidder can pay. A collector always can. A player who left or spent the money is
  skipped, and the next bid down wins at its own price. With no bid at all, the keenest collector buys at the opening
  price.
- **The fee** is the trades' own: `Config.PlayerTrade.Fee` (8 %), rounded by `PlayerTradeRules.fee`. There is no
  auction fee of its own, so one number serves both.
- **The money:**
  - the seller gets `+price` (`AuctionSale`) and pays `−fee` (`AuctionFee`);
  - a player buyer pays `−price` (`AuctionBuy`);
  - a house lot (the Grand Auction's) pays nobody and has no fee.
- **The buyer's side.** The winner's piece goes into their stock, and their collection book marks it found (see **The
  server step**).

## The numbers, and why

| | Number | Why |
| --- | --- | --- |
| A round | every 30 min, ≤ 4 lots, 3 – 5 min | often enough to plan for in a session, short enough to stay for |
| A lot | 45 s, +8 s anti-snipe, ≤ +20 s | time for a few bids; a sniper can't win by the last tick |
| Opening | the worth (value × condition) | the design's floor; already 4.6 – 8 × what the game pays |
| Collectors | ×1.05 / ×1.1 / ×1.2 rarity, ×1.15 hot, ×0.9 cold, die 0.9 – 1.2 | medians over 1,200 played lots (`auction_test`): **×1.12 rare, ×1.13 epic, ×1.25 legendary** of the worth |
| Fee | 8 % (the trades') | a money sink on every sale; one fee across all player sales |

**What a seller gets.** Even at the floor (no player bids, the fee paid), a piece nets at least **4.6×** what the game
pays (the worst case is a legendary: its game price is 20 % of its value). That is also at least **66 minutes** of its
own income on show:

| Rarity | Worth | Minutes of its income |
| --- | --- | --- |
| legendary | $5,500 – 7,000 | about 65 |
| epic | $2,800 – 3,400 | about 100 |
| rare | $900 – 1,900 | about 125 |

Selling is now a real decision: you get a lump sum now and a free stand, against an hour or two of income.

**What a buyer pays.** A player must beat the keenest collector, so expect 10 – 35 % over the worth. A buyer pays that
premium for the collection book (its "new" pieces and milestones), the TOP MOVERS board and a legendary of their own,
not for the income.

**The economy.** Per player there is at most one lot per 30 minutes, and lots come only from rare finds. The fee takes
8 % out of every player sale.

## The building

### Where and why
**Where.** On Depot Row, east of the crossroads, at `Config.Auction.House.Spot = { x = 158, z = -22, yaw = 0 }`. That
is the middle of its front wall, and the door looks north to the road. The footprint is x 132 … 184, z −26 … 12.

**Why there:**
- It sits across the road from plots 3 and 4, so players see it from their warehouses. It is 20 studs off Depot Row and
  about 120 studs from the TOP MOVERS board.
- It is clear of everything on today's map: 12 studs off every road, off the plots, the vans' ways, the house, the
  signpost, the lamps, the trees and the flowers, on flat meadow. `tests/auctionhouse_test.luau` checks all of this.
- It is clear of the Jinočany plan (`design/jinocany/plan.json`): its roads, landmarks, fields, houses and tree lines
  (the same test reads the plan).
- The plan keeps the crossroads' south-east corner (x 40 – 120) for the **Corner Drugstore**. The Auction House stands
  just east of it, so together they make a small street front on Depot Row.
- Its place and turn are in one line (`House.Spot`), and every part follows the spot. A test turns it 90° and checks
  again.

**Other spots the plan offers (for the owner):**
- **The village green** (náves, x −800 … −584, z −190 … −80, on Hlavní): a "village hall" next to the chapel would fit
  a Czech village very well. It is about 650 studs west of the plots, though, so it suits the Grand Auction (a daily
  event worth the drive) better than a round every 30 minutes.
- **Pražská, by the Little Pond** (x 50 – 210, z 145 – 255): free ground east of the road between the drugstore and the
  pond. It is quieter, but players pass it on every move.

### Its look
The look is a small Central European auction hall, not alpine:
- **Outside:**
  - a cream rendered hall on a granite plinth, with white corner pilasters and a cornice;
  - a red clay-tile gable roof with its ridge along the front;
  - tall white-framed windows;
  - a doorway with a burgundy canopy, and the gold AUCTION HOUSE sign over it.
- **Inside:**
  - a red carpet down the aisle, with three rows of benches either side of it and standing room behind them;
  - a stage at the back with the lot's velvet pedestal (`AuctionLotStand`) and the lectern;
  - the lot display between two curtains;
  - the consignment desk by the door with its CONSIGN HERE board;
  - two hanging lamps.

It has 101 parts (`House.Budget` 140). The map goes from 985 to 1,086 parts, under its 2,500.

### Built only while `On` (the choice)
SandboxWorld builds the Auction House only when `Config.Auction.On` is true. The other option was to build it always
and keep the desk's prompt off. This one was chosen because:
- **Nothing shows until it works.** The brief says nothing of the auction should show before the server part lands.
  An empty hall with a dead desk would invite players in for nothing.
- **No cost while off.** The map stays at 985 parts and keeps its tests as they are. The Jinočany rebuild can also move
  or restyle the building before anyone has seen it.
- **The owner can still look at it.** Set `Config.Auction.On = true` in Studio: the hall stands, the desk opens the
  window, and the sign and the display count down to the next round from the schedule alone.

The map's tests run both ways: `auctionhouse_test` builds the world with the auction off and on, and with it on, the
whole `sandboxworld_test` passes too (tried once).

## The window (`client/AuctionUi.luau`)
- **LIVE LOT:**
  - the piece: picture, name, rarity, the day's market, condition, $/min, "📖 New for your book!", the seller, its
    worth;
  - the current price, the leading bidder and the countdown (red in its last 10 s);
  - **BID +$X · $Y**, or why not: YOUR PIECE, YOU LEAD, NEED $X, SOLD;
  - the lots after it, the anti-snipe line, and a strip of the round's lots (sold with their prices, now, to come).
- **CONSIGN:** your stock's pieces that may go, best first, each showing "Opens at $X". Then CONSIGN <name> · opens at
  $X, or WITHDRAW, or why not.
- **RESULTS:** each lot, who bought it and for how much. Your own are marked: what you got after the fee, or what you
  bought.
- **The stub.** Until the server's step, a request nobody answers is given up after 4 s with a toast.
- **The building.** The sign ("Next auction in 12:34" / "LIVE NOW · lot 2 of 4") and the lot display are painted on
  each client from the same view.
- **Behaviour like the other sandbox windows:** a modal card that closes the other windows, with ✕ / ESC / B / the menu
  / a tap beside it, and the gamepad kept inside. On a phone every button is at least `Ui.MinTouch`.

## The server step (still to do)
1. **`server/Auction.luau`.** Start it from `server/SandboxBoot.luau` (`optional("Auction", "start")`, after
   PlayerTrade), only while `Config.Auction.On`. It keeps the current round:
   - the round: `{ round, lots = { Lot }, current, endedAt }`;
   - one loop at `Config.Visitors.Tick`'s pace for the schedule (`AuctionRules.phase`), opening a lot, the collectors'
     next bids (`npcNext`, recomputed after every bid) and the hammer.
2. **The remote.** Answer `"Auction"`, rate-limited with `Net.limit` (`Config.Robust.Limits.Auction`, `AuctionBid`):
   - `state`: a per-player view with `lotView(lot, userId, fresh)`, where `fresh` is the buyer's collection book not
     holding the item (`CollectionBook`);
   - `consign`: `canConsign`, then take the piece off its stand and mark it held;
   - `withdraw`;
   - `bid`: `canBid` with the money the bidder has now, then `place`;
   - a `state` to everybody after every change, and `note` toasts ("Outbid: Lady Fairbanks bid $7,500").
3. **Holding a piece.** A consigned piece is held in the server's memory, not in the save:
   - add `Collection.hold(player, uid)` / `release`, which `display`, `sell`, `sellmany`, `setSale` and `transfer`
     check, so a held piece can't be shown, sold, put on sale or traded;
   - its stand is freed when it is consigned (`undisplay`), so the save writes it as a plain piece in the stock;
   - a round lives on one server, so a rejoin, a crash or a shutdown leaves the piece simply in its owner's stock.
4. **The settlement, at the hammer.** It happens in one step with no yield, like the trades:
   - **A player buys.** Use `Collection.transfer`. It needs two small changes:
     - `stand` may be `nil` for a held piece in the seller's stock (today it must be on stand `stand`);
     - an optional `reasons` (`{ buy = "AuctionBuy", sale = "AuctionSale", fee = "AuctionFee" }`; today it is fixed
       to `PlayerBuy` / `PlayerSale` / `TradeFee`).

     Its checks already cover the rest: both players present, room in the buyer's stock, the buyer's money. The fee is
     `AuctionRules.fee(price)` (= `PlayerTradeRules.fee`). If the transfer refuses (the buyer's money is gone, their
     stock is full), settle again without that bidder (`settle(lot, collectors, canPay)`).
   - **A collector buys.** Call `Collection.sellAt(seller, uid, price, "AuctionSale")` (a piece in the stock at a price
     the server set), then `PlayerData.spend(seller, fee, "AuctionFee", item)`.
   - **The book.** `transfer` doesn't touch the book: call `CollectionBook.record(buyer, item, condition)` after it,
     as `server/PlayerTrade.luau` does.
   - **Analytics.** Log an `AuctionLotSold` custom event (value: the price; fields: rarity, "player" / "collector").
     Add the name to `AnalyticsPlan.Events`.
5. **Saves.** Call `PlayerData.saveSoon` on both sides (`transfer` does). At shutdown (`BindToClose`), the round is
   abandoned: held pieces are released, and nothing is half paid because each settlement is one step.
6. **Leaving mid-auction.** The round goes on; only the lots and bids that need the player change:
   - The **seller** leaves before their lot: the lot is withdrawn and the piece stays theirs. Their save releases the
     hold on the next load.
   - The **seller** leaves during their lot: it is withdrawn at once, and the bids are void. `transfer` needs the seller
     present, and paying an absent player would need an offline write.
   - A **bidder** leaves: their bids no longer count. `canPay` returns false, and the bid below wins.
   - **Admins:** START A ROUND NOW and END ROUND buttons in the admin panel's SANDBOX tab, for testing in Studio.
7. **The rest:**
   - the piece's 3D model on the pedestal (`FurnitureLooks.build` at `AuctionLotStand`) while its lot runs;
   - a toast to everybody a minute before a round, and when a lot opens;
   - STOCK's 🔨 AUCTION on a piece, which opens `AuctionUi.open("consign")` with it picked;
   - the daily tasks ("Sell a piece at auction") and a badge ("Under the Hammer");
   - the guide's soft step to the Auction House once a rare piece is in stock;
   - the desk's prompt handled on the server too (it can check the stock first).

## The Grand Auction (later; hooks only)
- **When.** `Config.Auction.Grand = { On = false, Hour = 19, Lots = 3, Reserve = 1.5, Items = {} }`. `grandAt(now)`
  gives the next start (19:00 UTC daily), and `isGrand(startsAt)` says whether a round is one.
- **What it sells.** House lots (`AuctionRules.houseLot(item, condition, seed, reserve)`): no seller, no fee, nobody
  paid. They open at 1.5 × their worth.
- **The catalogue.** `Grand.Items` lists the exclusive legendaries, none yet. They need their own catalogue entries in
  `FurnitureLooks` (never in a house) and a book section of their own.
- **For it later:**
  - the round's view already carries `grand`;
  - the lot strip and the display work for any number of lots;
  - the village green (see **The building**) is a natural stage for it.

## Tests
- **`tests/auction_test.luau`** (the rules):
  - the numbers (off by default, 3 – 5 minutes, about 30 minutes apart);
  - the schedule's phases and the server's real end;
  - worth, steps and opening;
  - the lot clock and the anti-snipe cap;
  - every bid refusal;
  - the collectors: seeded, never over their max, never outbidding themselves; 1,200 played lots all at or over their
    worth, the rarer the keener, hot over cold;
  - a keen player wins and a shy one loses;
  - the settlement: no bids, a player who can't pay, the house's lots, the payments and their reasons, the trades' fee;
  - consigning (the rarities, broken, the phases, one a player, a full round);
  - the Grand hooks;
  - the client's view checked (junk dropped, lists capped) and every line of words;
  - that a piece nets at least 4× the game's price.
- **`tests/auctionhouse_test.luau`** (the building):
  - its place, door and footprint;
  - every part inside the footprint;
  - the way in free, from the steps through the door and down the aisle to the stage;
  - the desk;
  - clear of today's map and of the Jinočany plan (`JinocanyPlan.luau`, which `tests/run_tests.py` writes from
    `plan.json`);
  - turned 90°;
  - the built world: nothing while off; while on, the model, its parts as laid out, the words, the prompt, the
    pedestal, the lamps, nothing of the map within 1.5 studs, the part budget.
- **`tests/clientboot_test.luau`:** the window starts with the sandbox's own modules, frees the mouse, and closes and is
  closed like the others.
- **`tools/phone-ui/auction.luau`** (`check.py`): the live lot, the consign picker and the results at 844 × 390,
  667 × 375, 1280 × 800 and 1920 × 1080:
  - on the screen, nothing on each other, the words fitting, a finger's buttons;
  - BID, CONSIGN and WITHDRAW's requests;
  - the stub giving up;
  - the building painted;
  - every way to close it;
  - nothing at all while off.
