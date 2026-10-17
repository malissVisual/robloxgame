--!strict
-- 8.3 SANDBOX, the HUD's three chips on every device (the 8.2 review: no gamepad button opened 📖 BOOK, 📋 TASKS or
-- 📦 STOCK, and the texts that named a key read wrong on a phone). Pure (no Roblox: tests/sandboxpad_test.luau);
-- client/PadGlyph.luau shows it on the chips and routes the gamepad's buttons.
--   * The chips and what opens each: 📦 STOCK (the key Config.SandboxHud.StockKey, B; the gamepad's
--     Config.SandboxHud.StockPad, the D-pad's ←), 📖 BOOK (Config.CollectionBook.Key / Pad: C, the D-pad's →), 📋 TASKS
--     (Config.SandboxTasks.Key / Pad: J, the D-pad's ↓). Why the D-pad: in the sandbox nothing else of the game is on it
--     (the city's weapon wheel (↑), phone (↓) and hands (← →) never start there: client/Main.client.luau), A, B, X, Y,
--     the bumpers, the triggers and the sticks are taken (jump, closing, the prompts, Danny's "Talk to Danny" on L1
--     (client/MoveHelperCard.luau), the grip, the sprint, the camera), and the D-pad's ↑ is left to Roblox (its emote
--     wheel). While a window has the gamepad's selection the D-pad moves it instead (client/PadGlyph.luau pressed).
--     tests/run_tests.py checks the sandbox's modules leave the D-pad alone.
--   * A device: "keys" (a keyboard and a mouse), "pad" (a gamepad used last) or "touch" (a touch screen without keys).
--   SandboxPad.Ids                          the chips in the HUD's order: "stock", "book", "tasks"
--   SandboxPad.chip(id) -> Chip?            { id, icon, word, key, pad } (key a key's name, pad an Enum.KeyCode name)
--   SandboxPad.device(touch, pad) -> Device what the player plays with now (a gamepad used last wins)
--   SandboxPad.padWord(pad) -> string       "D-pad ←" for a D-pad's KeyCode name, another button's name as it is
--   SandboxPad.arrow(pad) -> string         "←": the glyph's stand-in when the platform gives no picture for it
--   SandboxPad.keyOf(id, device) -> string? what opens a chip on that device: "J", "D-pad ↓", nil on a touch screen
--   SandboxPad.named(id, device, icon?)     "TASKS (J)", "TASKS (D-pad ↓)", "TASKS" (icon: "📋 TASKS (J)")
--   SandboxPad.how(id, device) -> string    "Press J", "Press D-pad ↓", "Tap 📋 TASKS"
--   SandboxPad.chipOf(pad) -> string?       the chip a gamepad button opens (nil: none)
--   SandboxPad.notice(text, device)         a server's words for this device (the sandbox's notices: client/SandboxHud
--                                           notice): on a touch screen and with a gamepad a key in brackets ("(E)",
--                                           "(G)": the prompts show their own button, a phone taps them) goes; the
--                                           chips' names ("📋 TASKS") get their key or D-pad where the words give none
--                                           (not on a touch screen: the chip is tapped)
-- 8.3 keys, the sandbox's actions on every device (one place decides how an action is shown: client/KeyHints.luau's
-- strip, client/CarryGripUi.luau's grip check, client/MovingHud.luau's next step, client/SandboxGuide.luau's line).
-- The gamepad's map: X the prompts (Use, Pick up, Load, Display; out of a seat), Y held for Sell and the van's Take out,
-- R2 the grip, B Put down and closing (held: the guide on and off, as a held G), L1 "Talk to Danny" (reserved for
-- him; 8.3 Danny: R1 his "Give to Danny" at a piece), R2 / L2 and the left stick Roblox's driving. A word names
-- a gamepad button as Roblox does ("X", "R2").
-- 8.5 Danny's clipboard (orders mode: client/DannyOrders.luau, server/Clipboard.luau): "clipboard" takes it out, on a
-- computer Config.MoveHelper.Clipboard.Key (Q: free in the sandbox, where E, F, C, J, K, B, G, P, O, T, Z, H and Tab are
-- taken and R is the city's clerks'), with a gamepad R1 (Danny's: with it out, R1 by a piece gives it to him, his
-- "dannygive"), on a touch screen its 📋 button; "stow" puts it away (Q again, a gamepad's B: back).
--   SandboxPad.Actions                     the actions (id → { key, pad, tap?, hold? }): key the keyboard's ("E"),
--                                           pad the gamepad's buttons (Enum.KeyCode names, never the D-pad: the chips'),
--                                           tap a touch screen's button for it ("GRIP", "💡"; nil: the thing itself, a
--                                           prompt, is tapped)
--   SandboxPad.keyFor(id, device) -> string?   what a key strip shows: the key ("E") on a computer, the buttons'
--                                           Enum.KeyCode names with a gamepad ("ButtonX", "ButtonR2/ButtonL2": their
--                                           glyphs, client/PadGlyph.luau), nil on a touch screen or with no button
--   SandboxPad.pads(id) -> { string }       the gamepad's buttons for it (empty: none; read only)
--   SandboxPad.button(pad) -> string        a button's word: "X", "R2", "left stick", "D-pad ←"
--   SandboxPad.keyWord(id, device) -> string?  the key in words: "E", "X", "R2/L2"; nil on a touch screen or none
--   SandboxPad.withKey(text, id, device)    "try again (E)", "try again (X)", "try again" (a phone: the prompt is tapped)
--   SandboxPad.howTo(id, device) -> string? "Press E", "Hold G", "Press R2", "Hold B", "Tap GRIP", "Tap 💡"; nil: no way
--   SandboxPad.say(text, id, device)        the action's key standing alone in the words ("E at the back", "hold G") in
--                                           this device's: "X at the back", "hold B"; a phone's "tap at the back" (a
--                                           prompt's key: the prompt is tapped)

local Config = require(script.Parent.Config)

local SandboxPad = {}

export type Device = string -- "keys" | "pad" | "touch"
export type Chip = { id: string, icon: string, word: string, key: string, pad: string }
export type Action = { key: string, pad: { string }, tap: string?, hold: boolean? }

-- (each one's own: the prompts' GamepadKeyCode is server/Moving.luau's, server/Warehouse.luau's and Roblox's default X;
-- the seat's way out client/CarBoarding.luau's; the grip client/CarryGripUi.luau's; Danny's client/MoveHelperCard.luau's)
SandboxPad.Actions = {
	use = { key = "E", pad = { "ButtonX" } }, -- a prompt: Use, Pick up, Load, Display, the UPGRADES desk
	getout = { key = "E", pad = { "ButtonX" } }, -- out of a seat
	putdown = { key = "G", pad = { "ButtonB" } }, -- Put down / Let go what you carry
	close = { key = "Esc", pad = { "ButtonB" } }, -- a window shut
	guide = { key = "G", pad = { "ButtonB" }, tap = "💡", hold = true }, -- the guide off and on again
	sell = { key = "F", pad = { "ButtonY" }, hold = true }, -- a stand's Sell
	takeout = { key = "Z", pad = { "ButtonY" }, hold = true }, -- the van's Take out
	grip = { key = "LMB / F", pad = { "ButtonR2" }, tap = "GRIP" }, -- the grip check's one press (a phone: its GRIP button)
	danny = { key = "E", pad = { "ButtonL1" } }, -- "Talk to Danny" (L1 his)
	dannygive = { key = `{Config.MoveHelper.Clipboard.GiveKey} / LMB`, pad = { "ButtonR1" } }, -- 8.3 Danny: a piece onto his list or off it (a click, a tap, R1 at it; 9.0 E by it)
	clipboard = { key = Config.MoveHelper.Clipboard.Key, pad = { "ButtonR1" }, tap = "📋" }, -- 8.5 Danny's clipboard out (orders mode)
	stow = { key = Config.MoveHelper.Clipboard.Key, pad = { "ButtonB" }, tap = "📋" }, -- 8.5 … and put away again
	drive = { key = "W/S", pad = { "ButtonR2", "ButtonL2" } }, -- Roblox's driving: R2 on, L2 back
	steer = { key = "A/D", pad = { "Thumbstick1" } },
	horn = { key = "H", pad = {} }, -- (no button: the keyboard's H only)
	list = { key = "O", pad = {} }, -- the move's list (a phone taps the move's panel)
	chat = { key = "T", pad = {}, hold = true }, -- the quick chat
} :: { [string]: Action }

local BUTTONS: { [string]: string } = {
	ButtonA = "A", ButtonB = "B", ButtonX = "X", ButtonY = "Y", ButtonL1 = "L1", ButtonR1 = "R1", ButtonL2 = "L2", ButtonR2 = "R2",
	ButtonL3 = "L3", ButtonR3 = "R3", Thumbstick1 = "left stick", Thumbstick2 = "right stick",
}

SandboxPad.Ids = { "stock", "book", "tasks" }

local CHIPS: { [string]: Chip } = {
	stock = { id = "stock", icon = "📦", word = "STOCK", key = Config.SandboxHud.StockKey, pad = Config.SandboxHud.StockPad },
	book = { id = "book", icon = "📖", word = "BOOK", key = Config.CollectionBook.Key, pad = Config.CollectionBook.Pad },
	tasks = { id = "tasks", icon = "📋", word = "TASKS", key = Config.SandboxTasks.Key, pad = Config.SandboxTasks.Pad },
}

local ARROWS: { [string]: string } = { DPadLeft = "←", DPadRight = "→", DPadDown = "↓", DPadUp = "↑" }

function SandboxPad.chip(id: string): Chip?
	return CHIPS[id]
end

function SandboxPad.device(touch: boolean, pad: boolean): Device
	if pad then
		return "pad"
	elseif touch then
		return "touch"
	end
	return "keys"
end

function SandboxPad.arrow(pad: string): string
	return ARROWS[pad] or pad
end

function SandboxPad.padWord(pad: string): string
	local arrow = ARROWS[pad]
	return if arrow then `D-pad {arrow}` else pad
end

function SandboxPad.keyOf(id: string, device: Device): string?
	local chip = CHIPS[id]
	if not chip or device == "touch" then
		return nil
	end
	return if device == "pad" then SandboxPad.padWord(chip.pad) else chip.key
end

function SandboxPad.named(id: string, device: Device, icon: boolean?): string
	local chip = CHIPS[id]
	if not chip then
		return id
	end
	local name = if icon then `{chip.icon} {chip.word}` else chip.word
	local key = SandboxPad.keyOf(id, device)
	return if key then `{name} ({key})` else name
end

function SandboxPad.how(id: string, device: Device): string
	local chip = CHIPS[id]
	if not chip then
		return id
	end
	local key = SandboxPad.keyOf(id, device)
	return if key then `Press {key}` else `Tap {chip.icon} {chip.word}`
end

function SandboxPad.chipOf(pad: string): string?
	for _, id in SandboxPad.Ids do
		if CHIPS[id].pad == pad then
			return id
		end
	end
	return nil
end

-- "📋 TASKS" → "📋 TASKS (J)" wherever no bracket follows it already.
local function withKeys(text: string, device: Device): string
	for _, id in SandboxPad.Ids do
		local chip = CHIPS[id]
		local name = `{chip.icon} {chip.word}`
		local key = SandboxPad.keyOf(id, device)
		if key then
			local out: { string } = {}
			local from = 1
			while true do
				local first, last = string.find(text, name, from, true)
				if not first or not last then
					break
				end
				local after = string.sub(text, last + 1, last + 2)
				table.insert(out, string.sub(text, from, last))
				if after ~= " (" and string.sub(after, 1, 1) ~= "(" then
					table.insert(out, ` ({key})`)
				end
				from = last + 1
			end
			table.insert(out, string.sub(text, from))
			text = table.concat(out)
		end
	end
	return text
end

function SandboxPad.notice(text: string, device: Device): string
	if device ~= "keys" then
		-- (a key's letter in brackets, "(E)" / "(G)", with the space before it; "(E at the back)" stays)
		text = (string.gsub(text, "%s*%(%u%)", ""))
	end
	if device ~= "touch" then
		text = withKeys(text, device)
	end
	return text
end

-- ── 8.3 keys: the actions ──────────────────────────────────────────────────

local NONE: { string } = {}

function SandboxPad.pads(id: string): { string }
	local action = SandboxPad.Actions[id]
	return if action then action.pad else NONE
end

function SandboxPad.button(pad: string): string
	local arrow = ARROWS[pad]
	return if arrow then `D-pad {arrow}` else BUTTONS[pad] or pad
end

function SandboxPad.keyFor(id: string, device: Device): string?
	local action = SandboxPad.Actions[id]
	if not action or device == "touch" then
		return nil
	elseif device ~= "pad" then
		return action.key
	end
	return if #action.pad > 0 then table.concat(action.pad, "/") else nil
end

function SandboxPad.keyWord(id: string, device: Device): string?
	local action = SandboxPad.Actions[id]
	if not action or device == "touch" then
		return nil
	elseif device ~= "pad" then
		return action.key
	elseif #action.pad == 0 then
		return nil
	end
	local words = table.create(#action.pad)
	for i, pad in action.pad do
		words[i] = SandboxPad.button(pad)
	end
	return table.concat(words, "/")
end

function SandboxPad.withKey(text: string, id: string, device: Device): string
	local word = SandboxPad.keyWord(id, device)
	return if word then `{text} ({word})` else text
end

function SandboxPad.howTo(id: string, device: Device): string?
	local action = SandboxPad.Actions[id]
	if not action then
		return nil
	elseif device == "touch" then
		return if action.tap then `Tap {action.tap}` else nil
	end
	local word = SandboxPad.keyWord(id, device)
	return if word then `{if action.hold then "Hold" else "Press"} {word}` else nil
end

function SandboxPad.say(text: string, id: string, device: Device): string
	local action = SandboxPad.Actions[id]
	if not action or device == "keys" or not string.match(action.key, "^%w+$") then
		return text
	end
	local word = if device ~= "touch" then SandboxPad.keyWord(id, device) elseif action.tap then `tap {action.tap}` else "tap"
	if not word then
		return text
	end
	return (string.gsub(text, `%f[%w]{action.key}%f[%W]`, (string.gsub(word, "%%", "%%%%"))))
end

return SandboxPad
