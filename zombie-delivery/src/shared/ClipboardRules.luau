--!strict
-- 8.5 Danny's clipboard, ORDERS MODE (the owner: "When I want to give work to my employee, the helper, I'll hold a paper
-- in my hand, like a notepad. At that moment I'm in a kind of ordering mode and I click on what he should carry."): the
-- pure part (no Roblox at its top level: tests/clipboard_test.luau). server/Clipboard.luau holds the clipboard in your
-- right hand while Danny works for your move (your player attribute MoveHelper = "hired"); only then does a click, a
-- tap, a gamepad's R1 or (9.0) E by a piece give it to him or take it back (server/MoveHelper.luau's assign refuses one
-- without it: MoveHelperBrain.assignCheck's "clipboard"). client/DannyOrders.luau shows the mode;
-- Config.MoveHelper.Clipboard has its numbers.
--   ClipboardRules.check(c) -> (boolean, string?)   may it be out now (a Can: Danny hired, alive, on foot, the right
--                                              hand there, the hands free, the phone away, no gun up): (true, nil) or
--                                              (false, why: "hire" | "dead" | "hand" | "seat" | "carry" | "push" |
--                                              "phone" | "aim"); the same rule keeps it out (anything that fails it puts
--                                              it away: a pick, a seat, death, the move's end, the hire over)
--   ClipboardRules.why(why) -> string?         the notice for a refusal ("Put down what you carry first (G)."; a key in
--                                              brackets goes on a phone and with a gamepad: SandboxPad.notice); nil: none
--   ClipboardRules.pieces() -> { Piece }       its art: a board, a sheet of paper, a clip and its lever, a few lines and
--                                              ticks (server/ModelArt/Builder.luau pieces on the RightHand, authored on
--                                              the block hand's front like the phone, server/PhoneArt/Geometry.luau:
--                                              shared/KitFit.luau fits them into a small hand's palm, the paper facing
--                                              out of it; the clip at the fingers' end)
--   ClipboardRules.holder(promptOn, holder) -> (state, held, his)   a piece as this client sees it (its own Pick up /
--                                              Lift prompt shown: home; else welded to a body: carried, his when that
--                                              body is Danny's; else to the van: in the van) in MoveHelperBrain.Assign's
--                                              terms
--   ClipboardRules.look(verdict, index?, count?) -> (string?, string)   the piece pointed at in orders mode
--                                              (MoveHelperBrain.assignCheck's verdict): its words and its tone, "give"
--                                              (green: "✔ Give to Danny"), "back" (orange: on his list, "↩ #2 on his
--                                              list · take back"), "no" (red with the reason: "✖ Too far: get closer",
--                                              "✖ In the van already", "✖ His list is full (6/6)" …); nil words: none
--                                              (not a piece of yours)
--   ClipboardRules.key(device) -> string       how it comes out on that device: "Q", "R1", "📋" (the touch button)
--   ClipboardRules.carries(device) -> string   Danny's status line: "Take out your clipboard (Q) to give him pieces"
--   ClipboardRules.hint(device) -> string      the bottom line in orders mode: "📋 Pick what Danny carries: E or click · Q
--                                              put away" (9.0: E by a piece gives it too; a gamepad's "R1 by it · B put
--                                              away", a phone's "📋 Tap what Danny carries · tap 📋 to put away")
--   ClipboardRules.orders(on) -> string        the status line's button: "📋 ORDERS" (take it out), "📋 PUT AWAY"
--   ClipboardRules.cardButton(on) -> string    his card's: "📋 CLIPBOARD", "📋 PUT AWAY"
--   ClipboardRules.cardHint(device) -> string  his card's words, hired: "📋 Clipboard out (Q): click a piece to give it
--                                              to him, again to take it back."

local Config = require(script.Parent.Config)
local SandboxPad = require(script.Parent.SandboxPad)

local ClipboardRules = {}

-- What the server knows of you when it decides (server/Clipboard.luau fills it).
export type Can = {
	hired: boolean, -- Danny works for your move (your player attribute MoveHelper = "hired")
	alive: boolean,
	hand: boolean, -- your body has its right hand (the clipboard's art hangs on it)
	seated: boolean,
	carrying: boolean, -- a piece in your hands (the character's Carrying)
	pushing: boolean, -- a trolley's handle (Pushing)
	phone: boolean, -- the phone in your right hand (PhoneHeld, server/KitWear.luau)
	aiming: boolean, -- a gun up (Aiming: the city's; the sandbox has none)
}

-- A Builder piece (server/ModelArt/Builder.luau's Piece).
export type Piece = { name: string, size: { number }, at: { number }, attach: string, finish: string, turn: { number }?, shadow: boolean? }

local function cfg(): any
	return (Config :: any).MoveHelper
end

-- ── May it be out ───────────────────────────────────────────────────────────

function ClipboardRules.check(c: Can): (boolean, string?)
	if not c.hired then
		return false, "hire"
	elseif not c.alive then
		return false, "dead"
	elseif not c.hand then
		return false, "hand"
	elseif c.seated then
		return false, "seat"
	elseif c.carrying then
		return false, "carry"
	elseif c.pushing then
		return false, "push"
	elseif c.phone then
		return false, "phone"
	elseif c.aiming then
		return false, "aim"
	end
	return true, nil
end

local WHY: { [string]: string } = {
	hire = "📋 The clipboard is for %s's orders: hire him first.",
	seat = "📋 Get out first: you give %s his orders on foot.",
	carry = "Put down what you carry first (G): then take out your clipboard.",
	push = "Let go of what you push first (G): then take out your clipboard.",
	phone = "Put your phone away first: then take out your clipboard.",
	aim = "Lower your gun first: then take out your clipboard.",
}

function ClipboardRules.why(why: string?): string?
	local text = if why then WHY[why] else nil
	return if text then string.format(text, cfg().Name) else nil
end

-- ── Its art ─────────────────────────────────────────────────────────────────
-- Authored on the block hand's front as the phone is (its middle at { 0, -0.12, -0.3 }, the face to -Z, the wrist +Y,
-- the fingers -Y): the board lies on the palm from just short of the wrist out past the fingers, the clip at its far
-- end; in the courier's hand (KitFit.Palm, its one factor HandMin: 0.45) about 0.63 × 0.88 studs, a real clipboard in
-- that hand.
local BOARD_Y, BOARD_H = -0.47, 1.95
local FACE = -0.35 -- the board's paper side (its middle at -0.3, 0.1 thick)

function ClipboardRules.pieces(): { Piece }
	local far = BOARD_Y - BOARD_H / 2 -- (the fingers' end)
	local out: { Piece } = {
		{ name = "Board", size = { 1.4, BOARD_H, 0.1 }, at = { 0, BOARD_Y, -0.3 }, attach = "RightHand", finish = "parcel", shadow = true },
		{ name = "Paper", size = { 1.24, 1.66, 0.02 }, at = { 0, BOARD_Y - 0.06, FACE - 0.01 }, attach = "RightHand", finish = "white" },
		{ name = "Clip", size = { 0.62, 0.18, 0.08 }, at = { 0, far + 0.2, FACE - 0.04 }, attach = "RightHand", finish = "steel" },
		{ name = "ClipLever", size = { 0.34, 0.07, 0.07 }, at = { 0, far + 0.34, FACE - 0.1 }, attach = "RightHand", finish = "steel" },
	}
	-- the order's lines (dark, the last one shorter) and a red tick before the first two (two pieces given already)
	for index, length in { 0.82, 0.82, 0.82, 0.56 } do
		local y = far + 0.55 + (index - 1) * 0.3
		table.insert(out, { name = `Line{index}`, size = { length, 0.05, 0.012 }, at = { 0.14 - (0.82 - length) / 2, y, FACE - 0.026 }, attach = "RightHand", finish = "sole" })
		if index <= 2 then
			table.insert(out, { name = `Tick{index}`, size = { 0.14, 0.05, 0.012 }, at = { -0.44, y, FACE - 0.026 }, attach = "RightHand", finish = "red", turn = { 0, 0, -35 } })
		end
	end
	return out
end

-- ── A piece as this client sees it ─────────────────────────────────────────

-- promptOn: its own Pick up / Lift prompt is shown (home or on the ground, nobody holding it: server/Moving.luau
-- rewire). holder: what its weld holds it to, "player" | "danny" (a body: its carrier) | "van" | nil (none).
function ClipboardRules.holder(promptOn: boolean, holder: string?): (string, boolean, boolean)
	if promptOn then
		return "home", false, false
	elseif holder == "player" or holder == "danny" then
		return "carried", true, holder == "danny"
	elseif holder == "van" then
		return "truck", false, false
	end
	return "lost", false, false
end

-- ── The words ───────────────────────────────────────────────────────────────

function ClipboardRules.look(verdict: string, index: number?, count: number?): (string?, string)
	local name = cfg().Name
	if verdict == "add" then
		return `✔ Give to {name}`, "give"
	elseif verdict == "remove" then
		return if index then `↩ #{index} on his list · take back` else "↩ On his list · take back", "back"
	elseif verdict == "far" then
		return "✖ Too far: get closer", "no"
	elseif verdict == "van" then
		return "✖ In the van already", "no"
	elseif verdict == "full" then
		return `✖ His list is full ({count or cfg().Queue}/{cfg().Queue})`, "no"
	elseif verdict == "held" then
		return "✖ Somebody holds it", "no"
	elseif verdict == "his" then
		return `✖ {name} has it already`, "no"
	elseif verdict == "gone" then
		return "✖ Not now", "no"
	elseif verdict == "hire" then
		return `✖ Hire {name} first`, "no"
	end
	return nil, "no"
end

function ClipboardRules.key(device: SandboxPad.Device): string
	if device == "touch" then
		return SandboxPad.Actions.clipboard.tap or "📋"
	end
	return SandboxPad.keyWord("clipboard", device) or cfg().Clipboard.Key
end

function ClipboardRules.carries(device: SandboxPad.Device): string
	return `Take out your clipboard ({ClipboardRules.key(device)}) to give him pieces`
end

function ClipboardRules.hint(device: SandboxPad.Device): string
	local name = cfg().Name
	if device == "touch" then
		return `📋 Tap what {name} carries · tap {ClipboardRules.key(device)} to put away`
	end
	-- 9.0: how a piece is given on this device (E by it or a click on it; a gamepad's R1 by it: SandboxPad's "dannygive")
	local give = if device == "pad" then `{SandboxPad.keyWord("dannygive", device) or "R1"} by it` else `{cfg().Clipboard.GiveKey} or click`
	return `📋 Pick what {name} carries: {give} · {SandboxPad.keyWord("stow", device) or cfg().Clipboard.Key} put away`
end

function ClipboardRules.orders(on: boolean): string
	return if on then "📋 PUT AWAY" else "📋 ORDERS"
end

function ClipboardRules.cardButton(on: boolean): string
	return if on then "📋 PUT AWAY" else "📋 CLIPBOARD"
end

function ClipboardRules.cardHint(device: SandboxPad.Device): string
	if device == "touch" then
		return "📋 Clipboard out: tap a piece to give it to him, again to take it back."
	elseif device == "pad" then
		local button = ClipboardRules.key(device)
		return `📋 Clipboard out ({button}): {button} by a piece to give it to him, again to take it back.`
	end
	return `📋 Clipboard out ({ClipboardRules.key(device)}): click a piece to give it to him, again to take it back.`
end

return ClipboardRules
