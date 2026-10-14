-- 8.3 keys: the key hints under the HUD's top buttons (client/KeyHints.luau, its actions shared/SandboxPad.luau, the
-- device and the glyphs client/PadGlyph.luau) in the sandbox on every device, run for real on sandbox_mock.luau's
-- recorder (the folder: tools/phone-ui/keyhintsenv.py) on a computer (1280 × 800), a console and a phone held sideways
-- (844 × 390):
--   * a computer: the move's keys as before ([E] Use, [G] Put down, [LMB/F] Grip, [O] List, [T] Chat (hold); in the
--     driver's seat [W/S] Drive, [A/D] Steer, [H] Horn, [E] Get out), the KEYS chip with its F1;
--   * a gamepad used last on that computer: no keyboard key left; each chip its buttons' glyphs (the platform's
--     pictures: X Use, B Put down, R2 Grip; in the seat R2 and L2 Drive, the left stick Steer, X Get out), only what a
--     button does (no Horn, List or Chat), the KEYS chip without F1; a button's word in brackets when the platform gives
--     no picture; the strip follows the gamepad picked up and put down at once (no look needed);
--   * a console (a gamepad, no keyboard): the glyphs; a phone: no strip; a phone with a gamepad used last: the glyphs;
--   * F1 folds it and unfolds it; the city's strip (Config.Sandbox.On false) a keyboard's, a gamepad or not, as before;
--   * no warnings.
local M = require("./sandbox_mock")
local Config = require("./Config")
local SandboxPad = require("./SandboxPad")

local function check(name, condition, detail)
	if not condition then
		error(`FAIL {name}{if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""}`)
	end
	print("ok    " .. name)
end
local function all(root, predicate)
	local out = {}
	local function visit(object)
		if predicate(object) then
			table.insert(out, object)
		end
		for _, child in object:GetChildren() do
			visit(child)
		end
	end
	visit(root)
	return out
end
local function named(root, name)
	return all(root, function(object)
		return object.Name == name
	end)[1]
end

-- ── The stand-ins KeyHints needs ────────────────────────────────────────────
local function color(hex)
	return setmetatable({}, { __index = { ToHex = function()
		return hex
	end } })
end
M.KeyHintsP = { ink = color("f2f2f0"), ink2 = color("c4c7cb"), surface = color("14171c"), text = M.MUi.label }
M.KeyHintsHolster = { hand = function()
	return "fists"
end }
M.car, M.driving = nil, false
M.KeyHintsDrive = { seatedCar = function()
	return M.car, M.driving
end }
local input = M.services.UserInputService
input.KeyboardEnabled = true

-- The HUD's top buttons (client/Hud.luau's "HudButtons") at the top right: the strip right-aligned under them
local hud = M.gui:FindFirstChild("ZombieDeliveryHud")
local buttons = M.make("Frame", { Name = "HudButtons", AnchorPoint = M.Vector2.new(1, 0), Position = M.UDim2.new(1, -16, 0, 16), Size = M.UDim2.fromOffset(260, 40) }, hud)
local character = M.player.Character
local humanoid = M.make("Humanoid", { Name = "Humanoid", Health = 100 }, character)

local function screen(touch, w, h, keyboard)
	M.touch, M.width, M.height = touch, w, h
	input.KeyboardEnabled = keyboard
	M.placeHud()
	M.flush()
end
local function gamepad(on)
	M.gamepad = on
	M.inputChanged()
	M.flush()
end
local function look()
	M.resume()
	M.flush()
end

local KeyHints = require("./KeyHints")
screen(false, 1280, 800, true)
KeyHints.start()
look()
local root = named(hud, "KeyHints")
local toggle = named(root, "Toggle")
check("the strip under the HUD's top buttons", root ~= nil and toggle ~= nil)

-- What the strip shows: the keys' lines (their plain text) and a gamepad's rows (each chip's glyphs or bracketed words, and its word)
local function textLines()
	local out = {}
	for _, child in root:GetChildren() do
		if child.ClassName == "TextLabel" and child.Visible and child.Text ~= "" then
			table.insert(out, { order = child.LayoutOrder, text = (string.gsub(child.Text, "<[^>]+>", "")) })
		end
	end
	table.sort(out, function(a, b)
		return a.order < b.order
	end)
	local texts = {}
	for _, item in out do
		table.insert(texts, item.text)
	end
	return texts
end
local function padRows()
	local rows = {}
	for index = 1, 5 do
		local row = named(root, `PadLine{index}`)
		if row and row.Visible then
			local chips = {}
			local list = {}
			for _, chip in row:GetChildren() do
				if chip.ClassName == "Frame" then
					table.insert(list, chip)
				end
			end
			table.sort(list, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			for _, chip in list do
				local parts = {}
				local word = ""
				for _, piece in chip:GetChildren() do
					if piece.Name == "Pad" then
						table.insert(parts, { order = piece.LayoutOrder, text = `<{string.match(piece.Image, "Controls/(%w+)%.png") or "?"}>` })
					elseif piece.Name == "Key" then
						table.insert(parts, { order = piece.LayoutOrder, text = piece.Text })
					elseif piece.Name == "Word" then
						word = piece.Text
					end
				end
				table.sort(parts, function(a, b)
					return a.order < b.order
				end)
				local keys = {}
				for _, part in parts do
					table.insert(keys, part.text)
				end
				table.insert(chips, `{table.concat(keys)} {word}`)
			end
			table.insert(rows, table.concat(chips, "  "))
		end
	end
	return rows
end
local function joined(list)
	return table.concat(list, " | ")
end
local function anyKeyText()
	-- a keyboard key in brackets anywhere visible in the strip ("[E]", "[LMB/F]")
	for _, object in all(root, function(o)
		return o.ClassName == "TextLabel" and o.Visible
	end) do
		local visible = true
		local parent = object.Parent
		while parent and parent ~= root do
			visible = visible and parent.Visible
			parent = parent.Parent
		end
		if visible and string.find(object.Text, "%[[EGOTHF]%]") or (visible and string.find(object.Text, "LMB", 1, true)) or (visible and string.find(object.Text, "W/S", 1, true)) then
			return object.Text
		end
	end
	return nil
end

-- ── A computer: the keys as before ──────────────────────────────────────────
check("a computer on foot: \"[E] Use\" only (nothing in your arms)", root.Visible and joined(textLines()) == "[E] Use" and #padRows() == 0, joined(textLines()))
check("… the KEYS chip with its F1", toggle.Text == "KEYS · HIDE  [F1]", toggle.Text)
character:SetAttribute("Carrying", "sofa")
character:SetAttribute("CarryGrip", "both 4 fragile")
M.player:SetAttribute("MoveWith", 14)
look()
check("carrying a piece with a grip on a move: \"[E] Use  [G] Put down  [LMB/F] Grip | [O] List  [T] Chat (hold)\"",
	joined(textLines()) == "[E] Use  [G] Put down  [LMB/F] Grip | [O] List  [T] Chat (hold)", joined(textLines()))

-- ── The same computer, a gamepad picked up: its glyphs at once ─────────────
gamepad(true)
check("a gamepad picked up: the strip changes at once (no look): no keyboard key left", #textLines() == 0 and anyKeyText() == nil, anyKeyText())
check("… X Use, B Put down, R2 Grip as the platform's glyphs; no List or Chat (no button)", joined(padRows()) == "<ButtonX> Use  <ButtonB> Put down  <ButtonR2> Grip", joined(padRows()))
check("… the KEYS chip without F1 (a gamepad has none)", toggle.Text == "KEYS · HIDE", toggle.Text)
local firstRow = named(root, "PadLine1")
local glyph = named(firstRow, "Pad")
check("… a glyph the words' height or a little more, a picture fitted in", glyph ~= nil and glyph.ClassName == "ImageLabel" and glyph.Size.X.Offset == glyph.Size.Y.Offset
	and glyph.Size.Y.Offset >= Config.KeyHints.TextSize and glyph.ScaleType.Name == "Fit")
check("… the glyphs are shared/SandboxPad.luau's map", SandboxPad.pads("use")[1] == "ButtonX" and SandboxPad.pads("putdown")[1] == "ButtonB" and SandboxPad.pads("grip")[1] == "ButtonR2")
look()
check("… the next look: the same (nothing drawn again)", named(root, "PadLine1") == firstRow and named(firstRow, "Pad") == glyph)
humanoid.SeatPart = M.make("VehicleSeat", { Name = "DriverSeat" })
M.car, M.driving = M.make("Model", { Name = "Van" }), true
look()
check("in the driver's seat: R2 + L2 Drive, the left stick Steer, X Get out (no Horn: no button)",
	joined(padRows()) == "<ButtonR2><ButtonL2> Drive  <Thumbstick1> Steer  <ButtonX> Get out", joined(padRows()))
M.padImages = false
gamepad(true) -- (the platform gives no pictures now: asked again when the device is)
gamepad(false)
gamepad(true)
check("no pictures from the platform: the buttons' words in brackets", joined(padRows()) == "[R2][L2] Drive  [left stick] Steer  [X] Get out", joined(padRows()))
M.padImages = true
gamepad(false)
check("the gamepad put down (the keys used): the keys at once, the gamepad's rows gone", joined(textLines()) == "[W/S] Drive  [A/D] Steer  [H] Horn  [E] Get out" and #padRows() == 0
	and toggle.Text == "KEYS · HIDE  [F1]", joined(textLines()))
check("… the rows emptied (no glyph left behind)", #all(root, function(o)
	return o.Name == "Pad" or o.Name == "Word"
end) == 0)
humanoid.SeatPart = nil
M.car, M.driving = nil, false

-- ── F1 folds it ─────────────────────────────────────────────────────────────
input.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.F1 }, false)
look()
check("F1: folded to \"? KEYS  [F1]\"", #textLines() == 0 and toggle.Text == "? KEYS  [F1]", toggle.Text)
gamepad(true)
check("… with a gamepad: \"? KEYS\", no rows", #padRows() == 0 and toggle.Text == "? KEYS", toggle.Text)
toggle.Activated:Fire()
look()
check("… a click on it (the gamepad's selection): open again, the glyphs", joined(padRows()) == "<ButtonX> Use  <ButtonB> Put down  <ButtonR2> Grip", joined(padRows()))
gamepad(false)

-- ── A console: a gamepad and no keyboard ────────────────────────────────────
screen(false, 1280, 800, false)
gamepad(true)
look()
check("a console (no keyboard): the glyphs", root.Visible and joined(padRows()) == "<ButtonX> Use  <ButtonB> Put down  <ButtonR2> Grip", joined(padRows()))
gamepad(false)
look()
check("… its gamepad not used last (no keyboard either): no strip", not root.Visible)

-- ── A phone ─────────────────────────────────────────────────────────────────
screen(true, 844, 354, false)
look()
check("a phone: no strip (its buttons say what they do)", not root.Visible)
input.KeyboardEnabled = true
look()
check("… a phone with a keyboard as well (a touch screen's layout to the game): none", not root.Visible)
input.KeyboardEnabled = false
gamepad(true)
look()
check("a phone with a gamepad used last: the glyphs", root.Visible and joined(padRows()) == "<ButtonX> Use  <ButtonB> Put down  <ButtonR2> Grip", joined(padRows()))
gamepad(false)
look()
check("… the screen touched again: none", not root.Visible)

-- ── The city: as before (a keyboard's strip only, a gamepad or not) ─────────
screen(false, 1280, 800, true)
Config.Sandbox.On = false
character:SetAttribute("Carrying", nil)
character:SetAttribute("CarryGrip", nil)
M.player:SetAttribute("MoveWith", nil)
look()
local city = joined(textLines())
check("the city on a computer: its keys", root.Visible and string.find(city, "[1] Fists", 1, true) ~= nil and string.find(city, "[E] Use", 1, true) ~= nil and #padRows() == 0, city)
gamepad(true)
look()
check("… with a gamepad: the same keys as before (the city's strip unchanged)", joined(textLines()) == city and #padRows() == 0 and toggle.Text == "KEYS · HIDE  [F1]", joined(textLines()))
gamepad(false)
Config.Sandbox.On = true
look()
check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL KEY HINTS CHECKS PASSED")
