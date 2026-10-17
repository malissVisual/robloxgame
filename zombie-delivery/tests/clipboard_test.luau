--!strict
-- 8.5 Danny's clipboard, orders mode (shared/ClipboardRules.luau; the owner: "I'll hold a paper in my hand, like a
-- notepad … a kind of ordering mode and I click on what he should carry"), pure, in the standalone Luau CLI:
--   * when it may be out (a helper on your move: 10.1 free, every move's; alive, the right hand there, on foot, the hands free, the phone away,
--     no gun up: the reasons in their order) and the notices for a refusal (a key in brackets: a phone and a gamepad
--     lose it, SandboxPad.notice);
--   * the server's assign check (MoveHelperBrain.assignCheck) refuses a piece without it and allows it with it;
--   * its art: a board, a sheet of paper, a clip, lines on the right hand (Builder pieces with known finishes, the paper
--     on the board's face, the clip at the fingers' end), in the courier's small hand (KitFit.fit: the palm) a real
--     clipboard's size, never bigger than the courier's torso is wide;
--   * a piece as the client sees it (its prompt shown: home; a body's weld: carried, Danny's: his; the van's: in it);
--   * the words: the outline's (green to give, orange on his list with its number, red with the reason), the bottom
--     line, the status line's and the card's on every device (Q, R1 / B, 📋), Q free in the sandbox.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local ClipboardRules = require("./ClipboardRules")
local Brain = require("./MoveHelperBrain")
local KitFit = require("./KitFit")
local SandboxPad = require("./SandboxPad")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local H = Config.MoveHelper
local C = H.Clipboard

-- ── May it be out ───────────────────────────────────────────────────────────
local function can(fields: { [string]: any }?): (boolean, string?)
	local c: ClipboardRules.Can = { hired = true, alive = true, hand = true, seated = false, carrying = false, pushing = false, phone = false, aiming = false }
	for key, value in fields or {} do
		(c :: any)[key] = value
	end
	return ClipboardRules.check(c)
end
local ok, why = can()
check("a helper on your move (10.1: every move's, free), alive, on foot, the hands free: out", ok and why == nil)
check("no helper on your move (no move, the move over): no (none; 10.1 was \"hire\")", select(2, can({ hired = false })) == "none" and not (can({ hired = false })))
check("dead: no (dead); no right hand: no (hand)", select(2, can({ alive = false })) == "dead" and select(2, can({ hand = false })) == "hand")
check("in a seat: no (seat)", select(2, can({ seated = true })) == "seat")
check("a piece in your hands: no (carry): you can't carry with it out", select(2, can({ carrying = true })) == "carry")
check("a trolley, the phone, a gun up: no (push, phone, aim)", select(2, can({ pushing = true })) == "push" and select(2, can({ phone = true })) == "phone"
	and select(2, can({ aiming = true })) == "aim")
check("…the helper first, then life, the hand, the seat, the hands", select(2, can({ hired = false, alive = false, seated = true, carrying = true })) == "none"
	and select(2, can({ alive = false, seated = true })) == "dead" and select(2, can({ seated = true, carrying = true })) == "seat")
check("the notices: hands full (G), a seat, no helper (10.1: never \"hire him first\"); nothing for death or a missing hand", ClipboardRules.why("carry") == "Put down what you carry first (G): then take out your clipboard."
	and string.find(ClipboardRules.why("seat") or "", "Get out first", 1, true) ~= nil and string.find(ClipboardRules.why("none") or "", "your helper", 1, true) ~= nil
	and ClipboardRules.why("hire") == nil and string.find(ClipboardRules.why("seat", "Zip") or "", "give Zip orders", 1, true) ~= nil
	and ClipboardRules.why("dead") == nil and ClipboardRules.why("hand") == nil and ClipboardRules.why(nil) == nil, ClipboardRules.why("carry"))
check("…on a phone and with a gamepad the (G) goes (SandboxPad.notice)", SandboxPad.notice(ClipboardRules.why("carry") or "", "touch") == "Put down what you carry first: then take out your clipboard.")

-- ── The server's check: no clipboard, no orders ─────────────────────────────
local function assign(fields: { [string]: any }): string
	local a: Brain.Assign = { crew = true, mine = true, state = "home", held = false, his = false, queued = false, count = 0, near = true, clipboard = true }
	for key, value in fields do
		(a :: any)[key] = value
	end
	return Brain.assignCheck(a)
end
check("8.5 assign refused without the clipboard (\"clipboard\"), allowed with it (add)", assign({ clipboard = false }) == "clipboard" and assign({}) == "add")
check("…a piece of his list: taken back only with it out", assign({ clipboard = false, queued = true }) == "clipboard" and assign({ queued = true }) == "remove")

-- ── Its art ─────────────────────────────────────────────────────────────────
local pieces = ClipboardRules.pieces()
local byName: { [string]: ClipboardRules.Piece } = {}
local finishes = { parcel = true, white = true, steel = true, sole = true, red = true } -- (server/ModelArt/Builder.luau's)
local known, onHand = true, true
for _, piece in pieces do
	byName[piece.name] = piece
	known = known and finishes[piece.finish] == true
	onHand = onHand and piece.attach == "RightHand" and #piece.size == 3 and #piece.at == 3
end
local board, paper, clip = byName.Board, byName.Paper, byName.Clip
check("a board, a sheet of paper, a clip and its lever, lines, ticks", board ~= nil and paper ~= nil and clip ~= nil and byName.ClipLever ~= nil and byName.Line1 ~= nil
	and byName.Line4 ~= nil and byName.Tick1 ~= nil and #pieces >= 8, #pieces)
check("…every piece on the right hand with a finish Builder knows", known and onHand)
check("…the paper on the board's face (in front of it, -Z, smaller), the lines and the clip on the paper", board ~= nil and paper ~= nil and clip ~= nil
	and paper.at[3] < board.at[3] - board.size[3] / 2 + 1e-6 and paper.size[1] < board.size[1] and paper.size[2] < board.size[2]
	and byName.Line1.at[3] < paper.at[3] and clip.at[3] < paper.at[3])
check("…the clip at the fingers' end (-Y), the board out past the fingers from the palm", board ~= nil and clip ~= nil and clip.at[2] < board.at[2] - board.size[2] / 3
	and board.at[2] - board.size[2] / 2 < -1)
-- the courier's hand (0.22 × 0.36 × 0.4: KitFit's one factor, HandMin) holds it in its palm: a real clipboard's size there
local scales = { RightHand = KitFit.factors("RightHand", { 0.22, 0.36, 0.4 }) }
local fitted = KitFit.fit(pieces, scales)
local fittedBoard: any = nil
for _, piece in fitted do
	if piece.name == "Board" then
		fittedBoard = piece
	end
end
local long = if fittedBoard then math.max(fittedBoard.size[1], fittedBoard.size[2], fittedBoard.size[3]) else 0
local thin = if fittedBoard then math.min(fittedBoard.size[1], fittedBoard.size[2], fittedBoard.size[3]) else 1
check("in the courier's hand (in its palm, KitFit.Palm): about 0.6 × 0.9 studs, thin, narrower than the courier's torso (1.24)", fittedBoard ~= nil and scales.RightHand[1] < KitFit.SlabHand
	and long > 0.75 and long < 1.0 and thin < 0.06 and math.min(fittedBoard.size[1], fittedBoard.size[2]) < 1.24, long)

-- ── A piece as the client sees it ───────────────────────────────────────────
local function holder(on: boolean, by: string?): string
	local state, held, his = ClipboardRules.holder(on, by)
	return `{state}:{held}:{his}`
end
check("its prompt shown: home (nobody holds it)", holder(true, nil) == "home:false:false" and holder(true, "van") == "home:false:false")
check("welded to a player's body: carried, held; to Danny's: his", holder(false, "player") == "carried:true:false" and holder(false, "danny") == "carried:true:true")
check("welded to the van: in the van; nothing: lost", holder(false, "van") == "truck:false:false" and holder(false, nil) == "lost:false:false")
local function lookFor(on: boolean, by: string?, fields: { [string]: any }?): string
	local state, held, his = ClipboardRules.holder(on, by)
	local all: { [string]: any } = { state = state, held = held, his = his }
	for key, value in fields or {} do
		all[key] = value
	end
	return assign(all)
end
check("…in the server's terms: a home piece add, the van's van, a crew mate's held, Danny's his", lookFor(true, nil) == "add" and lookFor(false, "van") == "van"
	and lookFor(false, "player") == "held" and lookFor(false, "danny") == "his")

-- ── The words ───────────────────────────────────────────────────────────────
local function look(verdict: string, index: number?, count: number?): string
	local words, tone = ClipboardRules.look(verdict, index, count)
	return `{words}|{tone}`
end
check("the outline: green to give (\"✔ Give to Danny\")", look("add") == "✔ Give to Danny|give")
check("…orange on his list, with its number (take it back)", look("remove", 2) == "↩ #2 on his list · take back|back")
check("…red with the reason: too far, in the van, his list full (6/6)", look("far") == "✖ Too far: get closer|no" and look("van") == "✖ In the van already|no"
	and look("full", nil, 6) == "✖ His list is full (6/6)|no", look("full", nil, 6))
check("…held, his, gone: red (10.1: no \"hire\" any more)", look("held") == "✖ Somebody holds it|no" and look("his") == "✖ Danny has it already|no" and look("gone") == "✖ Not now|no"
	and (ClipboardRules.look("hire")) == nil and (ClipboardRules.look("add", nil, nil, "Lucy")) == "✔ Give to Lucy")
check("…not your move's piece: no words", (ClipboardRules.look("piece")) == nil and (ClipboardRules.look("crew")) == nil)
check("its key: Q on a computer, R1 with a gamepad, 📋 on a touch screen", ClipboardRules.key("keys") == "Q" and ClipboardRules.key("pad") == "R1" and ClipboardRules.key("touch") == "📋"
	and C.Key == "Q")
check("the status line: \"Take out your clipboard (Q) to give Danny pieces\" (R1, 📋; 10.1 the helper's name)", ClipboardRules.carries("keys") == "Take out your clipboard (Q) to give Danny pieces"
	and ClipboardRules.carries("pad") == "Take out your clipboard (R1) to give Danny pieces" and ClipboardRules.carries("touch") == "Take out your clipboard (📋) to give Danny pieces"
	and ClipboardRules.carries("keys", "Zip") == "Take out your clipboard (Q) to give Zip pieces")
check("the bottom line: \"📋 Pick what Danny carries: E or click · Q put away\" (9.0: E by a piece too; a gamepad's R1 by it and B, a phone's tap 📋)", ClipboardRules.hint("keys") == "📋 Pick what Danny carries: E or click · Q put away"
	and ClipboardRules.hint("pad") == "📋 Pick what Danny carries: R1 by it · B put away" and ClipboardRules.hint("touch") == "📋 Tap what Danny carries · tap 📋 to put away",
	ClipboardRules.hint("pad"))
check("9.0 E gives a piece (client/DannyOrders.luau's prompts): the pieces' own key, near enough for their reach, a few at once",
	C.GiveKey == "E" and C.PromptNear >= Config.Moving.Reach.Item and C.Prompts >= 1 and C.Prompts <= 8 and C.GiveKey ~= C.Key)
check("the buttons: 📋 ORDERS / 📋 PUT AWAY on the status line, 📋 CLIPBOARD / 📋 PUT AWAY on his card", ClipboardRules.orders(false) == "📋 ORDERS"
	and ClipboardRules.orders(true) == "📋 PUT AWAY" and ClipboardRules.cardButton(false) == "📋 CLIPBOARD" and ClipboardRules.cardButton(true) == "📋 PUT AWAY")
check("his card's words: the key, then how a piece goes to him (a click, a tap, R1)", string.find(ClipboardRules.cardHint("keys"), "(Q): click a piece to give it to Danny", 1, true) ~= nil
	and string.find(ClipboardRules.cardHint("touch"), "tap a piece to give it to Danny", 1, true) ~= nil
	and string.find(ClipboardRules.cardHint("pad"), "(R1): R1 by a piece to give it to Danny", 1, true) ~= nil
	and string.find(ClipboardRules.cardHint("keys", "Bruno"), "give it to Bruno", 1, true) ~= nil)
check("Config: the look throttled (0.1 … 0.5 s), the touch button a finger's size, three colours", C.Look >= 0.1 and C.Look <= 0.5 and C.ButtonMin >= 44 and C.Button >= C.ButtonMin
	and #C.Give == 3 and #C.Back == 3 and #C.No == 3 and C.Flash > 0)
check("the rate limit: Config.Robust.Limits.Clipboard (a few a second)", Config.Robust.Limits.Clipboard >= 1 and Config.Robust.Limits.Clipboard <= 10)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
