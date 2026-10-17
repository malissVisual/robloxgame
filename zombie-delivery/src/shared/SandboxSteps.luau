--!strict
-- 8.0 SANDBOX, the guide's steps (design/sandbox/KONTRAKT.md; client/SandboxGuide.luau draws them): what a player new
-- to the sandbox does next, decided from what the client can see. Pure (no Roblox: tests/sandboxsteps_test.luau).
--
-- The state (client/SandboxGuide.luau fills one table again every Config.SandboxGuide.Every seconds):
--   plot          your plot (the player attribute Plot, server/SandboxPlots.luau; nil: none yet)
--   move          a move runs (the Moving remote's "state" is a table, client/MovingHud.luau; 9.7: a run)
--   pad           9.7: you stand on a portal's pad (client/RunUi.luau's pad view); padHost: you are its host (you pick
--                 the difficulty)
--   inside        you are in the house (the state's `inside`, server/HouseInterior.luau)
--   carrying      you carry a piece (one of the state's items is `mine` and "carried")
--   vanLoad       the pieces in the truck now (the state's counts.out)
--   delivered     the pieces unloaded at home on this move (the state's counts.delivered: a trip or more done)
--   atHouse       you stand (or drive) at the house (SandboxSteps.atHouse: the move's)
--   house         the move's place (the Moving state's `contract`: a SandboxMap.Houses id; nil: the farmstead)
--   seated        you sit in a vehicle
--   planning      the move's planning lobby is open (the MoveLobby remote's "lobby"); planningMine: yours (LAUNCH)
--   stock         your pieces in the stock, not on show (the Collection remote's "state")
--   shown         your pieces on show on a display stand
--   freeStands    the empty display stands (nil: not known, taken as some)
--   8.3, for the soft steps (nil or false: not known, nothing said):
--   money         your money (the State remote's)
--   levels        the UPGRADES' levels (the Upgrades remote's state: shared/UpgradeRules.luau)
--   hot           the name of a hot piece (today's market) in your stock; hotCount how many; hotSold a hot kind sold
--                 today (the market's demand); day the market's day (the Collection remote's state: its market)
--   painted       something of the PAINT shop is yours (the VanPaint remote's state: owned)
--   vanHome       9.7: you are in the lobby (no run, no planning): the PAINT shop's booth is there
--   window        the sandbox window open now (its client module's name: "UpgradeUi", "WarehouseUi", "VanPaintUi", …)
--   covered       something covers the screen (client/SandboxHintsUi.luau isCovered: a grip check, the move's cards,
--                 a sandbox window, Danny's card, the start screen)
--   hush          something else talks now (a first-time hint waits or just showed; a soft step just ended)
--   8.4, Danny (server/MoveHelper.luau; nil or false: not known, nothing said):
--   helper        a helper on your move: "hired" (the player attribute MoveHelper: 10.1 always so, free; nil: none)
--   helperName    10.1 his name (MoveHelperName: the crew's helper's; nil: Danny's)
--   helperQueue   the pieces on his list (MoveHelperQueue)
--   waiting       you wait for him at a two-person piece (MoveHelperCall: you pressed its Lift)
--   heavy         the two-person pieces still to carry out (the Moving state's items: class "pair", home or set down)
--   heavyNear     one of them within Config.SandboxGuide.HeavyNear studs of you, its Lift shown (the client's look)
--   8.9, trading between players (nil: not known, nothing said):
--   players       the players on the server, you too (the client's Players list)
--   signs         your pieces on show with a FOR SALE sign (the Collection remote's "state": its views' `sale`)
--
-- The steps (SandboxSteps.decide, the first that fits; the owner's table; 9.7 runs: the lobby's words, no driving):
--   in the house                        inside    "Carry the loot out to the truck (E to pick up)"        (no target)
--   carrying, outside                   load      "Load the truck: walk in or E at its back"              the truck's back
--   the truck has things, the run is on finish    "Finish or beat the clock: FINISH at the truck …"       the truck's back
--   a run, outside, nothing loaded      door      "Walk in through the front door"                        its door
--   no move, the planning open          plan      "Press LAUNCH to start the move" / the crew waits       (no target)
--   on a portal's pad, the host         pick      "Pick a difficulty: the run starts when the clock runs out" (no target)
--   on a portal's pad                   waitPad   "Stay on the pad: the run starts in a moment"           (no target)
--   no move, pieces in the stock        show      "Put your pieces on show: E at an empty stand"          a free stand
--   no move, pieces on show             earn      "Your pieces earn money while you play. …"              a portal
--   no move                             portal    "Walk to a portal: step onto a house's glowing pad"     the nearest portal
--
-- Done once, a step stays quiet for the session (SandboxSteps.doneBy: what the player did, seen this session: a count
-- that went up, not one a save brought along; `earn` only says something, so the client counts it done after
-- Config.SandboxGuide.InfoSeconds on the screen). A quiet step shows no hint and no 3D guide, except the drive steps
-- (nav: 9.7 none any more: nobody drives): their arrow stays while you drive.
--   SandboxSteps.decide(state, done?) -> Step          the step now (8.4: with `done`, Danny's step first in a move)
--   SandboxSteps.doneBy(state, done, last)             marks in `done` (id → true) the steps this state shows done;
--                                                      `last` keeps the counts of the look before (vanLoad, delivered,
--                                                      shown: nil = not known yet, then only taken, nothing marked)
--   SandboxSteps.visible(step, done, seated) -> (hint, guide)   show the hint line? the 3D guide?
--   SandboxSteps.text(step, touch) -> string           the hint's words ("E" is "tap" on a touch screen)
--   SandboxSteps.atHouse(x, z, margin, house?) -> boolean   in the house's lot or within `margin` studs of it (
--                                                      `house` a SandboxMap.Houses id, the move's; nil: the farmstead)
--   SandboxSteps.route(fx, fz, tx, tz, out, direct) -> n   the path on the ground: n points written into `out` as x1,
--                                                      z1, x2, z2 … (no table made: the guide calls it five times a
--                                                      second); 9.7 runs: always straight (the lobby and the run zones
--                                                      are small, no road to follow: `direct` is kept for its callers)
--   SandboxSteps.collection(msg, total?) -> Summary    the Collection remote's "state": stock, shown, free, taken (8.3:
--                                                      the hot pieces in the stock, the first one's name, the market's
--                                                      day, a hot kind sold today; 8.9: the pieces on show with a FOR
--                                                      SALE sign)
--   SandboxSteps.nearestFree(x, z, spots, taken) -> index?   the nearest empty stand (spots[i] = { x, y, z }, taken[i])
--   SandboxSteps.nearestShown(x, z, spots, taken) -> index?  8.9: the nearest stand with a piece on show (taken[i])
--
-- 8.3, the soft steps: what 8.3 added, each said at its moment and never nagging (SandboxSteps.choose). The core loop
-- always wins: a run (in the house, carrying, the truck loaded), the planning, a portal's pad, and a core step not
-- done yet (walk to a portal, put your pieces on show); only `earn` (it only says something) gives way. Nothing soft while
-- something covers the screen (a grip check, the move's result card, a sandbox window, the start screen: `covered`) or
-- while something else talks (a first-time hint, shared/SandboxHints.luau busy; a soft step just ended: `hush`). The
-- first that fits, in this order (SandboxSteps.Soft):
--   grow     the warehouse's next level bought now and the stock fills the free stands (stock ≥ free, some pieces)
--            "Your warehouse is full: grow it at the UPGRADES desk ($1,000)"              the desk (its level's spot)
--   hot      a hot piece of today's market in the stock, none of the hot kinds sold today
--            "🔥 Your Jukebox is hot today: sell it or show it"                           a free stand, else the 📦 chip
--   upgrade  another upgrade the money buys now (the cheapest; the window's order breaks a tie; never a locked one:
--            UpgradeRules.locked, More stands below the Big Warehouse)
--            "💡 New upgrade in reach: Showroom lights at the UPGRADES desk ($1,500)"     the desk
--   paint    nothing bought at the PAINT shop yet, you in the lobby (9.7: its booth there; no van parked any more), and
--            a warehouse past the Garage (UpgradeRules.warehouseLevel) or Config.SandboxGuide.PaintMoney ($2,000) in
--            your pocket
--            "🎨 Make your truck your own at the PAINT SHOP"                              the booth's counter
--   sell     8.9 (8.7 trading between players, while Config.PlayerTrade.On): Config.SandboxGuide.SellPlayers players on
--            the server or more (you too), SellShown pieces of yours on show or more, none with a FOR SALE sign yet
--            "🏷 Sell to players: set a price on a piece on show"                        your nearest piece on show
--            (its Set price prompt); done once a sign is set (one from a save too: the player knows it)
-- (The collection book and the TASKS have their first-time hints, shared/SandboxHints.luau "book" and "tasks": no step
-- here; 8.9: nor the clipboard, a visit, a player's offer: "orders", "visit", "deal".) A soft step is done for the
-- session by what the player did (its window opened while it fits, a level bought, a hot piece sold or put on show, a
-- paint bought, 8.9: a FOR SALE sign set), after Config.SandboxGuide.SoftSeconds on the screen (the client's) or
-- by the guide's ✕ (SandboxSteps.dismiss: only that step goes, the guide stays on). `hot` is once a market day: a new
-- day may say it again, unless it was dismissed (done.hotGone).
--   SandboxSteps.choose(state, done) -> Step           the step now: the core's (decide) or a soft one
--   SandboxSteps.dismiss(step, done) -> boolean        the ✕ on a soft step: gone for the session (false: a core step)
--   SandboxSteps.words(step, state) -> string          its words with the price or the piece in them (8.5: give's
--                                                      once your clipboard is out)
--   SandboxSteps.detail(step, state) -> (string?, number?)   what its words depend on (the client makes them again only
--                                                      when it changes: no string a look)
--   SandboxSteps.growPrice(state) -> number?           the next warehouse level's price when `grow` fits (nil: not now)
--   SandboxSteps.upgradeFor(state) -> (id?, price?)    the upgrade `upgrade` names (nil: none in reach)
--
-- 8.4, Danny (server/MoveHelper.luau, client/MoveHelperCard.luau; the owner: "… click on something, and that assigns it
-- to him"): two steps of the move (10.1: the third, "Hire Danny", is gone with the hire), each said once as a soft step is
-- (SoftSeconds at most, its ✕ dismisses it, SoftGap after the one before; never while something covers the screen, his
-- card too, or something else talks). In a move the first that fits and is not done comes before the move's own step
-- (SandboxSteps.decide with `done`; he only comes with a move: nothing before LAUNCH). None while you sit in a vehicle,
-- carry a piece or wait for him. The order (SandboxSteps.Danny):
--   lift   hired, one of the move's two-person pieces near you (heavyNear)
--          "Heavy piece: press Lift and wait for Danny"                          (the hint only)
--   give   hired, his list empty, you in the house (where the pieces are)
--          8.5 (orders mode, shared/ClipboardRules.luau): "Take out your clipboard (Q) and pick a piece for Danny"
--          (the device's way: "(R1)", "(tap 📋)"); with your clipboard out (`clipboard`) "Pick a piece to give it to
--          Danny" (a gamepad's "(R1)": it points at nothing)                      (the hint only)
-- (10.1: the words name the crew's helper, helperName, Danny's without one: SandboxSteps.words.)
-- Done by what the player did (doneBy): give once his list went up while you play or his card opened (it says how);
-- lift once you waited for him at a piece (your Lift called him).
--   SandboxSteps.danny(state, done) -> Step?           Danny's step now (nil: none)
--   SandboxSteps.onDevice(step, words?, device) -> string   the words for "keys" | "pad" | "touch": a prompt's E a
--                                                      phone's "tap", a gamepad's X; a Danny step's gamepad button
--                                                      in brackets (SandboxPad's "danny" L1, 8.5 "clipboard" R1);
--                                                      8.5 words that name their step's own key ("(Q)") say it in the
--                                                      device's way instead ("(R1)", "(tap 📋)": SandboxPad.say)

local SandboxMap = require(script.Parent.SandboxMap)
local Config = require(script.Parent.Config)
local UpgradeRules = require(script.Parent.UpgradeRules) -- 8.3: the UPGRADES desk's prices (the soft steps)
local SandboxPad = require(script.Parent.SandboxPad) -- 8.4: the device's words (onDevice)

local SandboxSteps = {}

export type State = {
	plot: number?,
	move: boolean,
	pad: boolean?, -- 9.7: on a portal's pad (padHost: its host)
	padHost: boolean?,
	inside: boolean,
	carrying: boolean,
	vanLoad: number,
	delivered: number,
	atHouse: boolean,
	seated: boolean,
	planning: boolean,
	planningMine: boolean,
	stock: number,
	shown: number,
	freeStands: number?,
	-- 8.3, the soft steps (all optional: a state without them has none)
	money: number?,
	levels: { [string]: number }?,
	hot: string?,
	hotCount: number?,
	hotSold: boolean?,
	day: number?,
	painted: boolean?,
	vanHome: boolean?,
	window: string?,
	covered: boolean?,
	hush: boolean?,
	-- 8.4, Danny (all optional: a state without them has no Danny step)
	helper: string?,
	helperName: string?, -- 10.1 his name (the crew's helper's)
	helperQueue: number?,
	waiting: boolean?,
	heavy: number?,
	heavyNear: boolean?,
	clipboard: boolean?, -- 8.5 your clipboard is out (orders mode: the character attribute ClipboardHeld)
	-- 8.9, trading between players (all optional: a state without them has no sell step)
	players: number?,
	signs: number?,
	-- the move's place (a SandboxMap.Houses id; nil: the farmstead)
	house: string?,
}

-- target: what the 3D guide points at (client/SandboxGuide.luau finds it): 9.7 "portal" (the nearest portal's pad) |
-- "door" | "van" (the truck's back) | "stand" | 8.3: "desk" (the UPGRADES desk) | "hot" (a free stand, else the 📦 STOCK
-- chip) | "paint" (9.7: the PAINT shop's booth) | 8.4: "danny" (Danny's body) | 8.9: "sale" (your nearest piece on
-- show: its Set price prompt) | nil (the hint only). nav: the arrow stays while you drive, done or not.
-- info: it only says something (done after a while on the screen). soft: 8.3, a soft step (SandboxSteps.choose; its ✕
-- dismisses it; 8.4: Danny's steps too). pad: 8.4, the SandboxPad action whose gamepad button follows its words in
-- brackets (SandboxSteps.onDevice; nil: none).
export type Step = { id: string, hint: string, target: string?, nav: boolean, info: boolean, soft: boolean, pad: string? }

-- 8.3: hot the hot pieces in the stock (not on show, not broken), hotName the first one's name, day the market's day,
-- hotSold a hot kind sold today. 8.9: signs the pieces on show with a FOR SALE sign.
export type Summary = {
	stock: number,
	shown: number,
	free: number?,
	taken: { [number]: boolean },
	hot: number,
	hotName: string?,
	day: number?,
	hotSold: boolean,
	signs: number,
}

-- The counts of the look before (SandboxSteps.doneBy): a step is done when its count goes up while you play. 8.3: the
-- warehouse's level, the other upgrades' levels added up, the hot pieces in the stock and the market's day. 8.4: the
-- pieces on Danny's list.
export type Last = { vanLoad: number?, delivered: number?, shown: number?, level: number?, bought: number?, hot: number?, day: number?, queue: number? }

-- A display stand's place in the world (client/SandboxGuide.luau reads them from shared/WarehouseLayout.luau).
export type Place = { x: number, y: number, z: number }

local HOUSE = SandboxMap.House.name -- (the farmstead: the steps' own words)
local DANNY = Config.MoveHelper.Name -- 8.4

local function step(id: string, hint: string, target: string?, nav: boolean, info: boolean, soft: boolean?, pad: string?): Step
	return { id = id, hint = hint, target = target, nav = nav, info = info, soft = soft == true, pad = pad }
end

SandboxSteps.Steps = {
	-- 9.7 runs: the lobby's (no contract board, no driving: drive, back and home are gone)
	portal = step("portal", "Walk to a portal: step onto a house's glowing pad", "portal", false, false),
	pick = step("pick", "Pick a difficulty: the run starts when the clock runs out", nil, false, false),
	waitPad = step("waitPad", "Stay on the pad: the run starts in a moment", nil, false, false),
	plan = step("plan", "Press LAUNCH to start the move", nil, false, false),
	planCrew = step("planCrew", "Get ready: the move's owner presses LAUNCH", nil, false, false),
	door = step("door", "Walk in through the front door", "door", false, false), -- (8.1 walk-in doors: no E)
	inside = step("inside", "Carry the loot out to the truck (E to pick up)", nil, false, false),
	load = step("load", "Load the truck: walk in or E at its back", "van", false, false),
	finish = step("finish", "Finish or beat the clock: load more, or FINISH at the truck", "van", false, false),
	show = step("show", "Put your pieces on show: E at an empty stand", "stand", false, false),
	earn = step("earn", "Your pieces earn money while you play. Walk into another house for more!", "portal", false, true),
	-- 8.3, the soft steps (their words with the price or the piece: SandboxSteps.words)
	grow = step("grow", "Your warehouse is full: grow it at the UPGRADES desk", "desk", false, false, true),
	hot = step("hot", "🔥 Your piece is hot today: sell it or show it", "hot", false, false, true),
	upgrade = step("upgrade", "New upgrade in reach at the UPGRADES desk", "desk", false, false, true),
	paint = step("paint", "🎨 Make your truck your own at the PAINT SHOP", "paint", false, false, true),
	-- 8.4, Danny (soft: said once; their words the same on every device, a gamepad's button added: onDevice; 10.1 no
	-- "hire" step: he is free)
	lift = step("lift", `Heavy piece: press Lift and wait for {DANNY}`, nil, false, false, true),
	-- (8.5 orders mode: its words say the clipboard's key, SandboxSteps.words without it out)
	give = step("give", `Take out your clipboard ({Config.MoveHelper.Clipboard.Key}) and pick a piece for {DANNY}`, nil, false, false, true, "clipboard"),
	-- 8.9, trading between players (8.7): the last soft step (its words the same on every device: the stand's Set price
	-- prompt shows its own key)
	sell = step("sell", "🏷 Sell to players: set a price on a piece on show", "sale", false, false, true),
} :: { [string]: Step }

-- 8.3: the soft steps in their order (the first that fits shows). 8.9: sell last (after every step before it; never in a
-- move or its planning, as every soft step).
SandboxSteps.Soft = { "grow", "hot", "upgrade", "paint", "sell" } :: { string }

-- 8.4: Danny's steps in their order (the first that fits and is not done shows, before the move's own step; 10.1 no
-- "hire" any more).
SandboxSteps.Danny = { "lift", "give" } :: { string }

local S = SandboxSteps.Steps
local G = Config.SandboxGuide

function SandboxSteps.decide(s: State, done: { [string]: boolean }?): Step
	if s.move then
		-- 8.4 Danny (see the header): his step that fits and is not done comes first
		local danny = if done then SandboxSteps.danny(s, done) else nil
		if danny then
			return danny
		end
		if s.inside then
			return S.inside
		end
		if s.carrying then
			return S.load
		end
		if s.vanLoad > 0 then
			return S.finish -- (9.7 runs: no drive home: FINISH, or the clock)
		end
		return S.door
	end
	if s.planning then
		return if s.planningMine then S.plan else S.planCrew -- (8.4: no Danny yet: he comes with the move)
	end
	if s.pad == true then -- 9.7 runs: on a portal's pad
		return if s.padHost == true then S.pick else S.waitPad
	end
	local free = s.freeStands
	if s.stock > 0 and (free == nil or free > 0) then
		return S.show
	end
	if s.shown > 0 then
		return S.earn
	end
	return S.portal
end

-- Did the count go up since the look before (nil before: not known yet, nothing to say)?
local function rose(before: number?, now: number): boolean
	return before ~= nil and now > before
end

-- What this state shows done (each mark stays for the session; `earn` is the client's, by time). The counts mark a step
-- when they go up (a piece loaded, a trip unloaded, a piece put on show), so what a save or a crew brought along before
-- you looked does not.
function SandboxSteps.doneBy(s: State, done: { [string]: boolean }, last: Last)
	if s.move or s.planning or s.pad == true then
		done.portal = true -- (9.7 runs: on a pad, or in the run)
	end
	if s.move then
		done.plan = true
		done.planCrew = true
		done.pick = true
		done.waitPad = true
		if s.inside then
			done.door = true
		elseif s.carrying then
			done.door = true -- (out of the house with a piece: it was emptied from inside)
			done.inside = true
		end
	end
	if s.move and rose(last.vanLoad, s.vanLoad) then
		done.load = true
	end
	if not s.move and (last.vanLoad or 0) > 0 then
		done.finish = true -- (9.7 runs: the run ended with something in the truck: it went home)
	end
	if rose(last.shown, s.shown) then
		done.show = true
	end
	last.vanLoad = if s.move then s.vanLoad else 0
	last.delivered = if s.move then s.delivered else 0
	last.shown = s.shown
	-- 8.3, the soft steps: found alone (its window opened while the step fits: the player sees what it would say)
	local window = s.window
	if window == "UpgradeUi" then
		if SandboxSteps.growPrice(s) then
			done.grow = true
		end
		if SandboxSteps.upgradeFor(s) then
			done.upgrade = true
		end
	elseif window == "WarehouseUi" and s.hot ~= nil then
		done.hot = true -- (the STOCK list or the picker: the 🔥 tags are there)
	elseif window == "VanPaintUi" then
		done.paint = true
	end
	if s.painted == true then
		done.paint = true
	end
	-- 8.9: a FOR SALE sign on one of your pieces (set now, or a save's: the player knows how)
	local signs = s.signs
	if signs ~= nil and signs > 0 then
		done.sell = true
	end
	-- … bought: the warehouse's level, another upgrade's (a count that goes up while you play, as above)
	local levels = s.levels
	if levels then
		local bought = 0
		for _, id in UpgradeRules.Order do
			if id ~= "warehouse" then
				bought += UpgradeRules.level(levels, id)
			end
		end
		local level = UpgradeRules.warehouseLevel(levels)
		if rose(last.level, level) then
			done.grow = true
		end
		if rose(last.bought, bought) then
			done.upgrade = true
		end
		last.level, last.bought = level, bought
	end
	-- … the market: a hot piece sold or put on show (fewer in the stock) says it today; a new day may say it again
	-- (never after its ✕: done.hotGone)
	local hot = s.hotCount or 0
	local day = s.day
	local newDay = day ~= nil and last.day ~= nil and day ~= last.day
	if newDay then
		if done.hotGone ~= true then
			done.hot = nil :: any
		end
	elseif last.hot ~= nil and hot < last.hot then
		done.hot = true
	end
	last.hot = hot
	if day ~= nil then
		last.day = day
	end
	-- 8.4 Danny: his card opened (it says how to give him pieces), or a piece given him while you play (his list went
	-- up); your Lift called him to a heavy piece (you wait for him). (10.1: no hire step any more.)
	local helper, queue = s.helper, s.helperQueue
	if s.move and helper ~= nil then
		if helper == "hired" and (window == "MoveHelperCard" or (queue ~= nil and rose(last.queue, queue))) then
			done.give = true
		end
		if s.waiting == true then
			done.lift = true
		end
	end
	last.queue = if s.move and helper == "hired" then queue else nil
end

-- The hint line and the 3D guide: a step not done yet shows both (the guide when it has a target); a done one is quiet,
-- but a drive step's arrow stays while you sit in a vehicle.
function SandboxSteps.visible(s: Step, done: { [string]: boolean }, seated: boolean): (boolean, boolean)
	local fresh = done[s.id] ~= true
	return fresh, s.target ~= nil and (fresh or (s.nav and seated))
end

-- The words: on a touch screen a prompt is tapped ("E at the back" → "tap at the back"). 8.3: `words` (a soft step's,
-- SandboxSteps.words) instead of the step's own.
function SandboxSteps.text(s: Step, touch: boolean, words: string?): string
	local hint = words or s.hint
	if not touch then
		return hint
	end
	return (string.gsub(hint, "%f[%w]E%f[%W]", "tap"))
end

-- 8.4: the words on a device (SandboxPad's "keys" | "pad" | "touch"): a computer's as they are, a phone's taps
-- (SandboxSteps.text), a gamepad's prompts on X (SandboxPad.say "use") and a Danny step's button after them ("(R1)":
-- a gamepad points at nothing). `words`: a soft step's (SandboxSteps.words) instead of the step's own.
function SandboxSteps.onDevice(s: Step, words: string?, device: string): string
	local hint = words or s.hint
	-- 8.5: words that name their step's own key in brackets ("(Q)": the clipboard's) say it in this device's way
	local action = if s.pad then SandboxPad.Actions[s.pad] else nil
	local named = action ~= nil and string.find(hint, `({action.key})`, 1, true) ~= nil
	if named and s.pad then
		hint = SandboxPad.say(hint, s.pad, device)
	end
	if device ~= "pad" then
		return SandboxSteps.text(s, device == "touch", hint)
	end
	local said = SandboxPad.say(hint, "use", device)
	return if s.pad and not named then SandboxPad.withKey(said, s.pad, device) else said
end

-- ── 8.4, Danny ─────────────────────────────────────────────────────────────

-- Does Danny's step fit (never while you sit, carry or wait for him; each only with what it needs known)?
local function dannyFits(id: string, s: State): boolean
	if s.seated or s.carrying or s.waiting == true then
		return false
	elseif id == "give" then
		return s.helper == "hired" and s.helperQueue == 0 and s.inside
	elseif id == "lift" then
		return s.helper == "hired" and s.heavyNear == true and (s.heavy or 0) > 0
	end
	return false
end

function SandboxSteps.danny(s: State, done: { [string]: boolean }): Step?
	if not s.move or s.helper == nil or s.covered or s.hush then
		return nil
	end
	for _, id in SandboxSteps.Danny do
		if done[id] ~= true and dannyFits(id, s) then
			return S[id]
		end
	end
	return nil
end

-- ── 8.3, the soft steps ────────────────────────────────────────────────────

function SandboxSteps.growPrice(s: State): number?
	local levels, money, free = s.levels, s.money, s.freeStands
	if levels == nil or money == nil or free == nil or s.stock < free or s.stock + s.shown <= 0 then
		return nil
	end
	local price = UpgradeRules.price("warehouse", UpgradeRules.level(levels, "warehouse")) -- (its upgrade level: warehouse level - 1)
	return if price and money >= price then price else nil
end

function SandboxSteps.upgradeFor(s: State): (string?, number?)
	local levels, money = s.levels, s.money
	if levels == nil or money == nil then
		return nil, nil
	end
	local best: string?, bestPrice: number? = nil, nil
	for _, id in UpgradeRules.Order do
		if id ~= "warehouse" and UpgradeRules.locked(levels, id) == nil then -- (8.3: never a locked one: More stands in a garage)
			local price = UpgradeRules.price(id, UpgradeRules.level(levels, id))
			if price and money >= price and (bestPrice == nil or price < bestPrice) then
				best, bestPrice = id, price
			end
		end
	end
	return best, bestPrice
end

local function paintFits(s: State): boolean
	if s.painted ~= false or s.vanHome ~= true or s.move then -- (9.7: vanHome: in the lobby, the booth there)
		return false
	end
	local levels, money = s.levels, s.money
	return (levels ~= nil and UpgradeRules.warehouseLevel(levels) > 1) or (money ~= nil and money >= G.PaintMoney) -- (past the Garage)
end

-- 8.9: trading on, others on the server to buy, pieces enough on show and no sign yet.
local function sellFits(s: State): boolean
	local trade = (Config :: any).PlayerTrade
	local players, signs = s.players, s.signs
	return type(trade) == "table" and trade.On == true and players ~= nil and players >= G.SellPlayers and s.shown >= G.SellShown
		and signs == 0
end

local function fits(id: string, s: State): boolean
	if id == "grow" then
		return SandboxSteps.growPrice(s) ~= nil
	elseif id == "hot" then
		return s.hot ~= nil and s.hotSold ~= true
	elseif id == "upgrade" then
		return (SandboxSteps.upgradeFor(s)) ~= nil
	elseif id == "paint" then
		return paintFits(s)
	elseif id == "sell" then
		return sellFits(s)
	end
	return false
end

-- The step now: the core loop's while it has something to do (a move, the planning, a core step not done yet; `earn`,
-- which only says something, gives way), else the first soft step that fits and is not done (none while the screen is
-- covered or something else talks), else the core's (quiet). 8.4: in a move Danny's step first (decide's).
function SandboxSteps.choose(s: State, done: { [string]: boolean }): Step
	local core = SandboxSteps.decide(s, done)
	if s.move or s.planning or (done[core.id] ~= true and not core.info) or s.covered or s.hush then
		return core
	end
	for _, id in SandboxSteps.Soft do
		if done[id] ~= true and fits(id, s) then
			return S[id]
		end
	end
	return core
end

function SandboxSteps.dismiss(s: Step, done: { [string]: boolean }): boolean
	if not s.soft then
		return false
	end
	done[s.id] = true
	if s.id == "hot" then
		done.hotGone = true -- (not again on a new market day either)
	end
	return true
end

function SandboxSteps.detail(step: Step, s: State): (string?, number?)
	if step.id == "grow" then
		return nil, SandboxSteps.growPrice(s)
	elseif step.id == "upgrade" then
		return SandboxSteps.upgradeFor(s)
	elseif step.id == "hot" then
		return s.hot, nil
	elseif step.id == "give" or step.id == "lift" then
		-- (8.5: its words change once the clipboard is out; 10.1 and with the crew's helper's name)
		local clip = if step.id == "give" and s.clipboard == true then "clipboard" else nil
		local name = if s.helperName and s.helperName ~= DANNY then s.helperName else nil
		return if clip and name then `{clip}:{name}` else clip or name, nil
	end
	return nil, nil
end

-- "The Pond Cabin", the place's name (nil or an unknown id: the farmstead's; 9.7: no road to drive along).
function SandboxSteps.houseWords(id: string?): string
	local h = SandboxMap.house(id)
	return if h then h.name else HOUSE
end

function SandboxSteps.words(step: Step, s: State): string
	if step.id == "grow" then
		local price = SandboxSteps.growPrice(s)
		if price then
			return `{step.hint} ({UpgradeRules.money(price)})`
		end
	elseif step.id == "upgrade" then
		local id, price = SandboxSteps.upgradeFor(s)
		local def = if id then UpgradeRules.def(id) else nil
		if def and price then
			return `{def.icon} New upgrade in reach: {def.name} at the UPGRADES desk ({UpgradeRules.money(price)})`
		end
	elseif step.id == "hot" and s.hot then
		return `🔥 Your {s.hot} is hot today: sell it or show it`
	elseif step.id == "give" and s.clipboard == true then
		return `Pick a piece to give it to {s.helperName or DANNY}` -- (8.5: the clipboard out, orders mode; 10.1 his name)
	elseif (step.id == "give" or step.id == "lift") and s.helperName and s.helperName ~= DANNY then
		return (string.gsub(step.hint, DANNY, s.helperName)) -- (10.1 the crew's helper's name)
	end
	return step.hint
end

function SandboxSteps.atHouse(x: number, z: number, margin: number, house: string?): boolean
	local lot = (SandboxMap.house(house) or SandboxMap.House).lot
	return x >= lot.x0 - margin and x <= lot.x1 + margin and z >= lot.z0 - margin and z <= lot.z1 + margin
end

-- ── The path along the roads (9.7: none: SandboxMap.Roads are the run zones' yards, nothing to follow) ──────────
-- Along the roads' middle lines (SandboxMap.Roads: Depot Row, the plots' road; Pražská down to the farmstead;
-- 9.4: the country lanes and their yards too, each one east-west when it is longer along X). The path goes out from the start
-- to the middle line of the road nearest it, along the roads the shortest way to the middle line of the road nearest
-- the target (through the junctions where two roads meet: the crossing of their middle lines; Dijkstra on those few
-- points), then in. A point on the line it already runs along replaces the last one (no bend), MaxPoints at most (the
-- target always last). Every table is made once, here: the guide calls it five times a second.

SandboxSteps.MaxPoints = 8 -- (client/SandboxGuide.luau: a path of seven beams)
local MIN_STEP = 3 -- studs: a point this close to the last one is left out
local ROADS: { SandboxMap.Road } = {} -- (9.7 runs: no road to follow: a straight path in the lobby and the zones)
-- each road's middle line: along X (at z = mid, from lo to hi) or along Z (at x = mid)
local ALONG_X: { boolean } = {}
local MID: { number } = {}
for i, r in ROADS do
	ALONG_X[i] = r.x1 - r.x0 >= r.z1 - r.z0
	MID[i] = if ALONG_X[i] then (r.z0 + r.z1) / 2 else (r.x0 + r.x1) / 2
end
-- the junctions (two roads whose rects meet): where their middle lines cross (two along one axis: the middle of where
-- they meet), the nodes 1 … #JX; the search adds the start's (#JX + 1) and the target's (#JX + 2)
local JX: { number }, JZ: { number }, JA: { number }, JB: { number } = {}, {}, {}, {}
for i, a in ROADS do
	for j, b in ROADS do
		if j > i and a.x0 <= b.x1 + 1e-6 and b.x0 <= a.x1 + 1e-6 and a.z0 <= b.z1 + 1e-6 and b.z0 <= a.z1 + 1e-6 then
			local x: number, z: number = 0, 0
			if ALONG_X[i] ~= ALONG_X[j] then
				x, z = if ALONG_X[i] then MID[j] else MID[i], if ALONG_X[i] then MID[i] else MID[j]
			elseif ALONG_X[i] then
				x, z = (math.max(a.x0, b.x0) + math.min(a.x1, b.x1)) / 2, (MID[i] + MID[j]) / 2
			else
				x, z = (MID[i] + MID[j]) / 2, (math.max(a.z0, b.z0) + math.min(a.z1, b.z1)) / 2
			end
			table.insert(JX, x)
			table.insert(JZ, z)
			table.insert(JA, i)
			table.insert(JB, j)
		end
	end
end
local NODES = #JX + 2
for k = #JX + 1, NODES do -- (the start's and the target's: set every search, on one road each)
	JX[k], JZ[k], JA[k], JB[k] = 0, 0, 0, 0
end
local DIST: { number }, PREV: { number }, DONE: { boolean }, ORDER: { number } = {}, {}, {}, {}
for k = 1, NODES do
	DIST[k], PREV[k], DONE[k], ORDER[k] = 0, 0, false, 0
end

-- The road nearest (x, z) (its rect; a tie: the first) and the point of its middle line there.
local function nearestRoad(x: number, z: number): (number, number, number)
	local best, bestD = 1, math.huge
	for i, r in ROADS do
		local dx = math.max(r.x0 - x, 0, x - r.x1)
		local dz = math.max(r.z0 - z, 0, z - r.z1)
		local d = dx * dx + dz * dz
		if d < bestD - 1e-9 then
			best, bestD = i, d
		end
	end
	local r = ROADS[best]
	if ALONG_X[best] then
		return best, math.clamp(x, r.x0, r.x1), MID[best]
	end
	return best, MID[best], math.clamp(z, r.z0, r.z1)
end

local function push(out: { number }, n: number, x: number, z: number): number
	if n > 0 then
		local dx, dz = x - out[n * 2 - 1], z - out[n * 2]
		if dx * dx + dz * dz < MIN_STEP * MIN_STEP then
			return n
		end
		if n > 1 then
			-- (on along the line the last two points run: the last one moves on instead, no bend in a straight run)
			local ax, az = out[n * 2 - 1] - out[n * 2 - 3], out[n * 2] - out[n * 2 - 2]
			if math.abs(ax * dz - az * dx) < 1e-6 * math.max(1, math.abs(ax) + math.abs(az)) * math.max(1, math.abs(dx) + math.abs(dz)) and ax * dx + az * dz > 0 then
				out[n * 2 - 1], out[n * 2] = x, z
				return n
			end
		end
		if n >= SandboxSteps.MaxPoints then -- (no room left: the last point gives way)
			out[n * 2 - 1], out[n * 2] = x, z
			return n
		end
	end
	n += 1
	out[n * 2 - 1] = x
	out[n * 2] = z
	return n
end

-- Do nodes u and v lie on one road?
local function shares(u: number, v: number): boolean
	local a, b = JA[u], JB[u]
	local c, d = JA[v], JB[v]
	return (a ~= 0 and (a == c or a == d)) or (b ~= 0 and (b == c or b == d))
end

function SandboxSteps.route(fx: number, fz: number, tx: number, tz: number, out: { number }, direct: number): number
	local n = push(out, 0, fx, fz)
	local dx, dz = tx - fx, tz - fz
	if #ROADS > 0 and dx * dx + dz * dz > direct * direct then
		local from, ex, ez = nearestRoad(fx, fz)
		local to, qx, qz = nearestRoad(tx, tz)
		n = push(out, n, ex, ez)
		if from ~= to then
			-- the shortest way through the junctions from the start's road to the target's
			local s, t = NODES - 1, NODES
			JX[s], JZ[s], JA[s], JB[s] = ex, ez, from, 0
			JX[t], JZ[t], JA[t], JB[t] = qx, qz, to, 0
			for k = 1, NODES do
				DIST[k], PREV[k], DONE[k] = math.huge, 0, false
			end
			DIST[s] = 0
			for _ = 1, NODES do
				local u, best = 0, math.huge
				for k = 1, NODES do
					if not DONE[k] and DIST[k] < best then
						u, best = k, DIST[k]
					end
				end
				if u == 0 or u == t then
					break
				end
				DONE[u] = true
				for v = 1, NODES do
					if not DONE[v] and shares(u, v) then
						local alt = best + math.abs(JX[u] - JX[v]) + math.abs(JZ[u] - JZ[v])
						if alt < DIST[v] then
							DIST[v], PREV[v] = alt, u
						end
					end
				end
			end
			-- the junctions on it, from the start's side (none found: straight on to the target's road)
			local count, at = 0, PREV[t]
			while at ~= 0 and at ~= s and count < NODES do
				count += 1
				ORDER[count] = at
				at = PREV[at]
			end
			for k = count, 1, -1 do
				n = push(out, n, JX[ORDER[k]], JZ[ORDER[k]])
			end
		end
		n = push(out, n, qx, qz)
	end
	n = push(out, n, tx, tz)
	if n == 1 then -- (already there: a path of one point is the target twice)
		n = 2
		out[3], out[4] = tx, tz
	end
	return n
end

-- ── The collection ─────────────────────────────────────────────────────────

-- The Collection remote's { kind = "state", stock = { Entry }, stands = n }: the pieces in the stock (no stand) and on
-- show (a stand), the stands taken and the empty ones out of `total` (the warehouse level's, the layout's count;
-- else the message's `stands` when it says more than are shown; nil: not known). 8.3: its market (a piece's `market`
-- "hot", the state's `market` View: its day, its hot kinds and the demand's `sold` today).
local MAX_NAME = 48 -- (a longer name from the network is no piece of ours: "piece")
function SandboxSteps.collection(msg: any, total: number?): Summary
	local summary: Summary = { stock = 0, shown = 0, free = nil, taken = {}, hot = 0, hotName = nil, day = nil, hotSold = false, signs = 0 }
	if type(msg) ~= "table" then
		return summary
	end
	local list = msg.stock
	if type(list) == "table" then
		for _, entry in list do
			if type(entry) == "table" then
				local stand = entry.stand
				if type(stand) == "number" then
					summary.shown += 1
					summary.taken[stand] = true
					local sale = entry.sale
					if type(sale) == "number" and sale > 0 and sale < math.huge then
						summary.signs += 1 -- (8.9: a FOR SALE sign)
					end
				else
					summary.stock += 1
					if entry.market == "hot" and entry.broken ~= true then
						summary.hot += 1
						if summary.hotName == nil then
							local name = entry.name
							summary.hotName = if type(name) == "string" and #name > 0 and #name <= MAX_NAME then name else "piece"
						end
					end
				end
			end
		end
	end
	local market = msg.market
	if type(market) == "table" then
		local day = market.day
		if type(day) == "number" and day == day and day > -math.huge and day < math.huge then
			summary.day = math.floor(day)
		end
		local hot, demand = market.hot, market.demand
		if type(hot) == "table" and type(demand) == "table" then
			for _, item in hot do
				local d = if type(item) == "string" then demand[item] else nil
				if type(d) == "table" and type(d.sold) == "number" and d.sold > 0 then
					summary.hotSold = true
				end
			end
		end
	end
	local all = total
	if all == nil and type(msg.stands) == "number" and msg.stands > summary.shown then
		all = msg.stands
	end
	if all ~= nil then
		summary.free = math.max(0, all - summary.shown)
	end
	return summary
end

-- The nearest spot whose taken[i] is `want` (true: a piece on show there; false: empty).
local function nearest(x: number, z: number, spots: { [number]: Place }, taken: { [number]: boolean }, want: boolean): number?
	local best: number? = nil
	local bestD = math.huge
	for index, spot in spots do
		if (taken[index] == true) == want then
			local dx, dz = spot.x - x, spot.z - z
			local d = dx * dx + dz * dz
			if d < bestD then
				best, bestD = index, d
			end
		end
	end
	return best
end

function SandboxSteps.nearestFree(x: number, z: number, spots: { [number]: Place }, taken: { [number]: boolean }): number?
	return nearest(x, z, spots, taken, false)
end

function SandboxSteps.nearestShown(x: number, z: number, spots: { [number]: Place }, taken: { [number]: boolean }): number?
	return nearest(x, z, spots, taken, true)
end

return SandboxSteps
