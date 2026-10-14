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

local Config = require(script.Parent.Config)

local SandboxPad = {}

export type Device = string -- "keys" | "pad" | "touch"
export type Chip = { id: string, icon: string, word: string, key: string, pad: string }

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

return SandboxPad
