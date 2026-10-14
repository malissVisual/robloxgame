--!strict
-- 8.3 SANDBOX: the HUD's chips (📦 STOCK, 📖 BOOK, 📋 TASKS) on every device (the words and the D-pad map:
-- shared/SandboxPad.luau). client/SandboxHud.luau and client/SandboxTasksUi.luau draw a chip's key outline with it,
-- client/SandboxHud.luau, client/CollectionBookUi.luau and client/SandboxTasksUi.luau open their window with it.
--   PadGlyph.device() -> Device             "touch" (a touch screen without keys), "pad" (a gamepad used last), "keys"
--   PadGlyph.show(keyLabel, id) -> boolean  a chip's key outline (a TextLabel) shows what opens it now: its key's letter
--                                           on a computer ("C"), with a gamepad the D-pad's glyph (the platform's
--                                           picture, UserInputService:GetImageForKeyCode, in an ImageLabel "Pad"; else
--                                           an arrow "→"), nothing on a touch screen (false: hidden)
--   PadGlyph.watch(fn)                      fn() when the device changes (a gamepad picked up, the keys or the mouse
--                                           used again): the chips are drawn again
--   PadGlyph.pressed(input, processed, id) -> boolean   the gamepad's button for chip `id`, pressed with nothing else
--                                           taking it: not typing, not taken by a GUI (processed) and no gamepad
--                                           selection in a window (the D-pad moves that selection then; B closes it)
--   PadGlyph.words(text) -> string          a server's words for this device (SandboxPad.notice)
--   PadGlyph.image(pad) -> string           8.3 keys: the platform's picture of a gamepad button (an Enum.KeyCode name,
--                                           "ButtonR2"), "" when it gives none (then its word: SandboxPad.button)
-- Presentation only.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SandboxPad = require(Shared.SandboxPad)
local Ui = require(script.Parent.Ui)

local PadGlyph = {}

function PadGlyph.device(): SandboxPad.Device
	return SandboxPad.device(Ui.touchLayout(), Ui.gamepadActive())
end

-- The platform's picture of a gamepad button (Xbox, PlayStation …: asked of the gamepad connected now), "" when none.
local function imageOf(pad: string): string
	local ok, found = pcall(function(): any
		return UserInputService:GetImageForKeyCode((Enum.KeyCode :: any)[pad])
	end)
	return if ok and type(found) == "string" then found else ""
end

function PadGlyph.show(keyLabel: any, id: string): boolean
	local chip = SandboxPad.chip(id)
	local device = PadGlyph.device()
	local glyph = keyLabel:FindFirstChild("Pad")
	if not chip or device == "touch" then
		keyLabel.Visible = false
		return false
	end
	keyLabel.Visible = true
	if device == "pad" then
		local image = imageOf(chip.pad)
		if image ~= "" then
			if not glyph then
				glyph = Ui.make("ImageLabel", {
					Name = "Pad",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Fit,
				}, keyLabel)
			end
			glyph.Image = image
			glyph.Visible = true
			keyLabel.Text = ""
			return true
		end
		keyLabel.Text = SandboxPad.arrow(chip.pad)
	else
		keyLabel.Text = chip.key
	end
	if glyph then
		glyph.Visible = false
	end
	return true
end

function PadGlyph.watch(fn: () -> ())
	local was = PadGlyph.device()
	local changed = (UserInputService :: any).LastInputTypeChanged
	if not changed then
		return
	end
	changed:Connect(function()
		local now = PadGlyph.device()
		if now ~= was then
			was = now
			fn()
		end
	end)
end

function PadGlyph.pressed(input: InputObject, processed: boolean, id: string): boolean
	local chip = SandboxPad.chip(id)
	if not chip or processed or input.KeyCode.Name ~= chip.pad or UserInputService:GetFocusedTextBox() then
		return false
	end
	-- (8.3 review: not while carrying: B puts the piece down there, so a window's B would put it down too)
	local character = game:GetService("Players").LocalPlayer.Character
	if character and character:GetAttribute("Carrying") ~= nil then
		return false
	end
	return GuiService.SelectedObject == nil
end

function PadGlyph.words(text: string): string
	return SandboxPad.notice(text, PadGlyph.device())
end

function PadGlyph.image(pad: string): string
	return imageOf(pad)
end

return PadGlyph
