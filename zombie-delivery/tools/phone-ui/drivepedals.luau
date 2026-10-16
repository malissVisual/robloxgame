-- 9.1 the drive pedals: GAS and BRAKE while you drive (client/DrivePedals.luau with shared/PedalRules.luau), run for
-- real on sandbox_mock.luau's recorder (the folder: tools/phone-ui/drivepedalsenv.py) beside the HUD's pieces where
-- client/Hud.luau's layout puts them (the right column with the speed and the fuel, docked as on a touch screen; the left
-- column; the EXIT button where client/TouchControls.luau's place puts it) and the real client/OfferCard.luau, on phones
-- held sideways (844 × 354, 750 × 354, 667 × 317, 640 × 316) and upright (390 × 750), tablets (1180 × 784, 1024 × 564)
-- and computers (1280 × 800, 1920 × 1080, 1024 × 600):
--   * hidden on foot, in somebody else's car, in a passenger's seat, with the HUD hidden (the start screen), under a
--     window (DrivePedals.covered), dead; shown in your own car's driver's seat;
--   * on the screen, GAS tall and narrow, BRAKE wider and shorter (BRAKE on the left), a finger's size on a touch screen,
--     their words fitting; clear of Roblox's jump button, its thumbstick's corner, EXIT, the speed and the fuel, the
--     left column; at the bottom right beside EXIT's column on a phone held sideways; compact over the speed on a
--     computer;
--   * a touch held on GAS drives (Drive.setPedal 1), on BRAKE brakes and backs up (-1), both the brake to a stop; the
--     left thumb on the stick at the same time changes nothing; let go: 0; a touch sliding from BRAKE onto GAS holds
--     GAS; pressed, a pedal goes down (lower, shorter, the dark veil, the red line) and eases back up when let go;
--   * a computer: W (Drive.foot 1) shows GAS down, S BRAKE, a gamepad's trigger part way (nothing held: no input); the
--     mouse held on a pedal drives like a finger; with a gamepad R2 / L2 under them (the platform's picture, else the
--     word), still clear of the speed;
--   * a visitor's offer card while they show: the card clear of them, they stay where they were, clear of it;
--   * hidden while held: let go (Drive.setPedal 0); no warnings.
-- `luau drivepedals.luau -a dump` prints the preview's scenes as JSON instead (drivepedals_preview.py).
local dump = select(1, ...) == "dump"
local M = require("./sandbox_mock")
local Config = require("./Config")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local Inventory = require("./Inventory")
local Holding = require("./Holding")

local C = Config.DrivePedals
local function check(name, condition, detail)
	if not condition then
		error(`FAIL {name}{if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""}`)
	end
	if not dump then
		print("ok    " .. name)
	end
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
local box, overlap = M.box, TouchLayout.overlap
local function show(b)
	return string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1)
end
local function inside(b)
	return MoveLayout.inside(b, M.width, M.height)
end
local function shown(object)
	local node = object
	while node do
		if node.Visible == false then
			return false
		end
		node = node.Parent
	end
	return true
end

-- ── The stand-ins the pedals need on top of sandbox_mock's ─────────────────
local UIS = M.services.UserInputService
UIS.TouchEnded = UIS.TouchEnded or M.signal()
UIS.TouchMoved = UIS.TouchMoved or M.signal()
UIS.WindowFocusReleased = UIS.WindowFocusReleased or M.signal()
local RS = M.services.RunService
RS.RenderStepped = RS.RenderStepped or M.signal()
-- client/Drive.luau: the seat you sit in, your car, the speed, the driver's foot, what the pedals give it
local mine = M.make("Model", { Name = "Sprinter" })
local theirs = M.make("Model", { Name = "TheirVan" })
local drive = { car = nil, driving = false, speed = 0, foot = 0, pedal = 0, calls = 0 }
M.PedalDrive = {
	seatedCar = function()
		return drive.car, drive.driving
	end,
	myCar = function()
		return mine
	end,
	setPedal = function(value)
		drive.pedal = value
		drive.calls += 1
	end,
	speed = function()
		return drive.speed
	end,
	foot = function()
		return drive.foot
	end,
}
local humanoid = M.make("Humanoid", { Name = "Humanoid", Health = 100 }, M.player.Character)
local K = M.MTheme.Contract

-- client/Hud.luau's pieces: the right column (its weapon line hidden in the sandbox, the speed row at its bottom), the
-- left column, the EXIT button (client/TouchControls.luau's, in the hand button's place)
local hud = M.hudGui
local right = M.make("Frame", { Name = "RightStack", BackgroundTransparency = 1 }, hud)
local weapon = M.make("Frame", { Name = "WeaponBar", BackgroundTransparency = 1, Visible = false }, right)
M.make("Frame", { Name = "Row", Size = M.UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, weapon)
local vehicle = M.make("Frame", { Name = "Vehicle", BackgroundTransparency = 1 }, right)
local speedRow = M.make("Frame", { Name = "Speed", BackgroundTransparency = 1, Size = M.UDim2.fromScale(1, 1) }, vehicle)
local speedText = M.make("TextLabel", { Name = "Value", Text = "48  KM/H", TextColor3 = K.text, BackgroundTransparency = 1, Font = M.Enum.Font.GothamBold,
	TextXAlignment = M.Enum.TextXAlignment.Right, Size = M.UDim2.fromScale(1, 1), TextSize = 20 }, speedRow)
local fuel = M.make("Frame", { Name = "Fuel", BackgroundColor3 = K.good, BackgroundTransparency = 0.1, AnchorPoint = M.Vector2.new(1, 0.5) }, speedRow)
local leftStack = M.make("Frame", { Name = "LeftStack", BackgroundColor3 = K.charcoal, BackgroundTransparency = 0.5 }, hud)
local exit = M.make("TextButton", { Name = "TouchAct", Text = "EXIT", TextColor3 = K.text, BackgroundColor3 = K.charcoal, BackgroundTransparency = 0.35,
	Font = M.Enum.Font.GothamBold, TextSize = 13, Visible = false }, hud)
M.make("UIStroke", { Color = K.text, Thickness = 1, Transparency = 0.3 }, exit)
local function place(object, b)
	object.Position = M.UDim2.fromOffset(b.x0, b.y0)
	object.Size = M.UDim2.fromOffset(b.x1 - b.x0, b.y1 - b.y0)
end
local camera = M.workspace.CurrentCamera
local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	local S = M.MUi.scaleFor(M.Vector2.new(w, h))
	if touch then
		local c = TouchLayout.cluster(w, h, S)
		local rowScale = math.max(S, 0.8)
		local barW, barH = Inventory.size(#Holding.Order + 2, true)
		local barScale = math.max(S, Inventory.minScale(true))
		place(right, TouchLayout.dock(c, w, h, 300 * S, 130 * S, 16 + 44 * rowScale, w - 16 - 170 * rowScale, barW * barScale, barH * barScale))
		place(leftStack, M.leftColumn)
		place(exit, c.act)
		exit.Visible = true
	else
		place(right, { x0 = w - 16 - 240 * S, y0 = h - 16 - 84 * S, x1 = w - 16, y1 = h - 16 })
		place(leftStack, { x0 = 16, y0 = h - 16 - 44 * S, x1 = 16 + 200 * S, y1 = h - 16 })
		exit.Visible = false
	end
	local rw, rh = right.Size.X.Offset, right.Size.Y.Offset
	vehicle.Position = M.UDim2.fromOffset(0, rh - 30 * S)
	vehicle.Size = M.UDim2.fromOffset(rw, 30 * S)
	speedText.TextSize = math.floor(20 * S + 0.5)
	fuel.Position = M.UDim2.new(1, -96 * S, 0.5, 0)
	fuel.Size = M.UDim2.fromOffset(40 * S, 6 * S)
	camera.ViewportSize = M.Vector2.new(w, h + 36)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	M.flush()
end
-- the looks (a few times a second) and the frames (every one: the input, the press drawn)
local function look()
	RS.Heartbeat:Fire(C.Place + 0.01)
	M.flush()
end
local function frames(count, dt)
	for _ = 1, count or 1 do
		RS.RenderStepped:Fire(dt or 1 / 60)
	end
end
local touchId = 0
local function touch(pedalButton)
	touchId += 1
	local input = { UserInputType = M.Enum.UserInputType.Touch, UserInputState = M.Enum.UserInputState.Begin, Position = { X = 0, Y = 0 }, id = touchId }
	if pedalButton then
		pedalButton.InputBegan:Fire(input)
	end
	return input
end
local function lift(input)
	UIS.TouchEnded:Fire(input, false)
	UIS.InputEnded:Fire(input, false)
end

-- ── The preview's scenes (drivepedals_preview.py) ───────────────────────────
local scenes = {}
local function color(c)
	return if type(c) == "table" and c.R then { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } else nil
end
local function udim2(u)
	return if type(u) == "table" and type(u.X) == "table" then { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset } else nil
end
local function node(n)
	local p = n._p
	local out = { c = p.ClassName, n = p.Name }
	if p.Visible == false then
		out.vis = false
	end
	out.pos, out.size = udim2(p.Position), udim2(p.Size)
	if p.AnchorPoint then
		out.anchor = { p.AnchorPoint.X, p.AnchorPoint.Y }
	end
	out.z, out.order = p.ZIndex, p.LayoutOrder
	out.bg, out.bgT = color(p.BackgroundColor3), p.BackgroundTransparency
	out.clip = p.ClipsDescendants
	if p.Text and p.Text ~= "" then
		out.text, out.ts = p.Text, p.TextSize
		out.tc, out.tt = color(p.TextColor3), p.TextTransparency
		out.xa = if p.TextXAlignment then p.TextXAlignment.Name else nil
		out.font = if p.Font then p.Font.Name else nil
		out.wrap = p.TextWrapped == true
	end
	if p.ClassName == "UICorner" then
		out.radius = { p.CornerRadius.Scale, p.CornerRadius.Offset }
	elseif p.ClassName == "UIStroke" then
		out.color, out.thick, out.tr = color(p.Color), p.Thickness, p.Transparency
	elseif p.ClassName == "UIScale" then
		out.scale = p.Scale
	elseif p.ClassName == "ScreenGui" then
		out.display = p.DisplayOrder or 0
		out.enabled = p.Enabled ~= false
	end
	local kids = {}
	for _, child in n:GetChildren() do
		table.insert(kids, node(child))
	end
	if #kids > 0 then
		out.kids = kids
	end
	return out
end
local function scene(name)
	if not dump then
		return
	end
	local overlay = {}
	if M.touch then
		local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── Off: nothing ────────────────────────────────────────────────────────────
local DrivePedals = require("./DrivePedals")
C.On = false
DrivePedals.start()
check("Config.DrivePedals.On false: DrivePedals.start() builds nothing", M.gui:FindFirstChild("DrivePedals") == nil)
C.On = true

-- ── On ──────────────────────────────────────────────────────────────────────
screen(true, 844, 354)
DrivePedals.start()
local gui = M.gui:FindFirstChild("DrivePedals")
local pair = gui and gui:FindFirstChild("Pedals")
local gas = pair and pair:FindFirstChild("Gas")
local brake = pair and pair:FindFirstChild("Brake")
check("built: a ScreenGui \"DrivePedals\" (over the HUD, under the windows) with the pair \"Pedals\": \"Gas\" and \"Brake\"",
	gui ~= nil and pair ~= nil and gas ~= nil and brake ~= nil and gui.DisplayOrder >= 1 and gui.DisplayOrder < 6)
check("… real pedals: a face with rubber ribs (GAS more), the words GAS and BRAKE, a red accent, a shadow", #all(named(gas, "Face"), function(o)
	return o.Name == "Rib"
end) > #all(named(brake, "Face"), function(o)
	return o.Name == "Rib"
end) and named(gas, "Label").Text == "GAS" and named(brake, "Label").Text == "BRAKE" and named(gas, "Accent").BackgroundColor3 == K.red and named(gas, "Shadow") ~= nil)
check("… never the gamepad's selection (R2 / L2 are its pedals)", gas.Selectable == false and brake.Selectable == false)

-- Hidden and shown.
look()
check("on foot: hidden", not DrivePedals.shown() and not pair.Visible)
drive.car, drive.driving = theirs, true
look()
check("in somebody else's car's driver's seat: hidden", not DrivePedals.shown())
drive.car, drive.driving = mine, false
look()
check("a passenger in your own car: hidden (a passenger does not drive)", not DrivePedals.shown())
drive.car, drive.driving = mine, true
look()
check("your own car's driver's seat: shown", DrivePedals.shown() and pair.Visible)

-- Where they are, on every screen.
local function placeChecks(label)
	local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	local g, b = box(gas), box(brake)
	check(`{label}: both on the screen`, inside(g) and inside(b), `{show(b)} {show(g)}`)
	check(`{label}: GAS tall and narrow, BRAKE wider and shorter, BRAKE on the left`, g.y1 - g.y0 > b.y1 - b.y0 and g.x1 - g.x0 < b.x1 - b.x0 and b.x1 < g.x0)
	check(`{label}: never one on the other`, not overlap(g, b))
	local blocks = { ["the speed and the fuel"] = box(speedRow), ["the left column"] = box(leftStack) }
	if M.touch then
		local c = TouchLayout.cluster(M.width, M.height, S)
		blocks["Roblox's jump button"] = c.jump
		blocks["the thumbstick's corner"] = c.thumb
		blocks["EXIT"] = box(exit)
		check(`{label}: a finger's size each way (44 px or more)`, math.min(g.x1 - g.x0, g.y1 - g.y0, b.x1 - b.x0, b.y1 - b.y0) >= 44 - 0.01, `{show(b)} {show(g)}`)
		check(`{label}: never over the thumbstick's corner (the left thumb's)`, b.x0 >= c.thumb.x1)
		if c.small then
			check(`{label}: comfortable to hold on a phone (GAS {math.floor(g.y1 - g.y0)} px tall)`, g.y1 - g.y0 >= 70 and g.y1 - g.y0 <= 110)
		end
		if M.width > M.height then
			check(`{label}: at the bottom right beside EXIT's column, where the thumb rests`, g.y1 >= M.height * 0.85 and box(exit).x0 - g.x1 <= C.Clear + 1 and g.x1 > M.width * 0.5, `{show(g)} / {show(box(exit))}`)
		end
	else
		-- (the right column's room over the speed is empty on a computer in the sandbox: its weapon line is hidden)
		check(`{label}: compact (GAS {math.floor(g.y1 - g.y0)} px tall), at the right edge over the speed`, g.y1 - g.y0 <= 90 and g.x1 >= M.width - C.Margin.Desk - 1
			and box(pair).y1 <= box(speedRow).y0 + 0.5, `{show(g)} / {show(box(speedRow))}`)
	end
	for name, other in blocks do
		check(`{label}: clear of {name}`, not overlap(g, other) and not overlap(b, other), `{show(b)} {show(g)} / {show(other)}`)
	end
	for _, pedal in { gas, brake } do
		local face, words = named(pedal, "Face"), named(pedal, "Label")
		local f = box(face)
		local need = M.textWidth(words.Text, words.TextSize * M.scaleOf(words), words.Font)
		check(`{label}: "{words.Text}" fits its pedal ({math.floor(need)} of {math.floor(f.x1 - f.x0)} px)`, need <= (f.x1 - f.x0) - 6 and words.TextSize >= 8)
		local ribsIn = true
		for _, rib in all(face, function(o)
			return o.Name == "Rib"
		end) do
			local r = box(rib)
			ribsIn = ribsIn and r.x0 >= f.x0 and r.x1 <= f.x1 and r.y0 >= f.y0 and r.y1 <= f.y1
		end
		check(`{label}: {words.Text}'s ribs on its face, the face in its box`, ribsIn and f.y0 >= box(pedal).y0 - 0.5 and f.y1 <= box(pedal).y1 + 0.5)
	end
end
local SCREENS = {
	{ "a phone held sideways (844 × 354)", true, 844, 354 },
	{ "an iPhone 14 with its notch (750 × 354)", true, 750, 354 },
	{ "an iPhone SE, the new top bar (667 × 317)", true, 667, 317 },
	{ "a small Android (640 × 316)", true, 640, 316 },
	{ "a phone held upright (390 × 750)", true, 390, 750 },
	{ "an iPad held sideways (1180 × 784)", true, 1180, 784 },
	{ "an Android tablet (1024 × 564)", true, 1024, 564 },
	{ "a computer (1280 × 800)", false, 1280, 800 },
	{ "a big screen (1920 × 1080)", false, 1920, 1080 },
	{ "a small window (1024 × 600)", false, 1024, 600 },
}
for _, s in SCREENS do
	screen(s[2], s[3], s[4])
	look()
	placeChecks(s[1])
	if s[3] == 844 or s[3] == 1180 or s[3] == 390 or s[3] == 1280 then
		scene(`pedals-{s[3]}x{s[4]}`)
	end
end

-- ── A touch screen: held to drive ───────────────────────────────────────────
screen(true, 844, 354)
look()
local function faceTop(pedal)
	return box(named(pedal, "Face")).y0
end
local function faceHeight(pedal)
	local f = box(named(pedal, "Face"))
	return f.y1 - f.y0
end
frames(30)
local restTop, restHeight = faceTop(gas), faceHeight(gas)
check("nothing held: no input", drive.pedal == 0)
local stick = touch(nil) -- (the left thumb on Roblox's thumbstick: not ours)
local onGas = touch(gas)
frames(1)
check("a finger on GAS: forward (Drive.setPedal 1)", drive.pedal == 1 and select(1, DrivePedals.held()) == true)
frames(20)
local face = named(gas, "Face")
check("… GAS goes down: lower, shorter (it tips away), a dark veil, the fine line red, the red edge wider", faceTop(gas) > restTop and faceHeight(gas) < restHeight
	and named(gas, "Veil").BackgroundTransparency < 1 and named(face, "UIStroke").Color == K.red and named(gas, "Accent").Size.X.Offset > C.Press.Accent[1])
check("… BRAKE stays up", named(named(brake, "Face"), "UIStroke").Color ~= K.red and named(brake, "Veil").BackgroundTransparency == 1)
scene("pedals-844x354-gas")
lift(stick)
frames(1)
check("the left thumb leaving the stick: GAS still held", drive.pedal == 1)
local onBrake = touch(brake)
drive.speed = 20
frames(1)
check("both held rolling forward: the brake (-1)", drive.pedal == -1)
drive.speed = 0
frames(1)
check("both held standing: it stands (0), never backs up", drive.pedal == 0)
lift(onGas)
frames(1)
check("GAS let go, BRAKE held: brakes, then backs up (-1)", drive.pedal == -1 and select(2, DrivePedals.held()) == true and select(1, DrivePedals.held()) == false)
frames(30)
local arm = named(pair, "Arm")
check("… BRAKE down, its arm (a hanging pedal) following its face", arm ~= nil and arm.Visible and math.abs(box(arm).y1 - faceTop(brake) - 2) < 1.01, arm and `{show(box(arm))} / {faceTop(brake)}`)
scene("pedals-844x354-brake")
-- the finger slides from BRAKE onto GAS: GAS
local g = box(gas)
onBrake.Position = { X = (g.x0 + g.x1) / 2, Y = (g.y0 + g.y1) / 2 }
UIS.TouchMoved:Fire(onBrake, false)
frames(1)
check("the finger sliding from BRAKE onto GAS: GAS held, BRAKE let go", drive.pedal == 1 and select(1, DrivePedals.held()) == true and select(2, DrivePedals.held()) == false)
lift(onBrake)
frames(1)
check("lifted: no input (0)", drive.pedal == 0 and not select(1, DrivePedals.held()) and not select(2, DrivePedals.held()))
-- a touch that ended without its signal (the app sent to the background): it holds nothing
local lost = touch(brake)
frames(1)
lost.UserInputState = M.Enum.UserInputState.End
frames(1)
check("a touch ended without its signal reaching us: let go (0)", drive.pedal == 0 and not select(2, DrivePedals.held()))
local away = touch(gas)
frames(1)
UIS.WindowFocusReleased:Fire()
frames(1)
check("the game window losing the focus: nothing held (0)", drive.pedal == 0 and not select(1, DrivePedals.held()))
lift(away)
lift(lost)
local backFrames = 0
while (faceTop(gas) ~= restTop or faceHeight(gas) ~= restHeight) and backFrames < 120 do
	frames(1)
	backFrames += 1
end
check(`… and GAS comes back up quickly ({backFrames} frames), the fine line light again`, backFrames <= 30 and named(face, "UIStroke").Color == K.text)
-- hidden while held: let go
local held = touch(gas)
frames(1)
drive.car = nil
look()
check("out of the seat while GAS is held: hidden, let go (Drive.setPedal 0)", not DrivePedals.shown() and drive.pedal == 0 and not select(1, DrivePedals.held()))
drive.car = mine
look()
frames(1)
check("back in the seat: shown, nothing held", DrivePedals.shown() and drive.pedal == 0)
lift(held)
check("a touch on a hidden pedal does nothing", (function()
	drive.car = nil
	look()
	touch(gas)
	frames(1)
	local quiet = drive.pedal == 0 and not select(1, DrivePedals.held())
	drive.car = mine
	look()
	return quiet
end)())

-- ── A computer: the feet ────────────────────────────────────────────────────
screen(false, 1280, 800)
look()
drive.foot = 1 -- (W, or R2 all the way)
frames(30)
local gasTop = faceTop(gas)
drive.foot = 0
frames(40)
local gasRest = faceTop(gas)
check("W (the foot on GAS): GAS drawn down, nothing given to the drive (the seat drives)", gasTop > gasRest and drive.pedal == 0)
drive.foot = -0.5 -- (L2 half way)
frames(40)
local brakeHalf = faceTop(brake)
drive.foot = -1
frames(40)
local brakeFull = faceTop(brake)
drive.foot = 0
frames(40)
local brakeRest = faceTop(brake)
check("a gamepad's L2 half way: BRAKE half way down; S: all the way", brakeHalf > brakeRest and brakeFull > brakeHalf)
drive.foot = 1
frames(30)
scene("pedals-1280x800-w")
drive.foot = 0
frames(40)
gas.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.MouseButton1 })
frames(1)
check("the mouse held on GAS: forward, like a finger", drive.pedal == 1)
UIS.InputEnded:Fire({ UserInputType = M.Enum.UserInputType.MouseButton1 }, false)
frames(1)
check("… let go: 0", drive.pedal == 0)
-- a gamepad: R2 / L2 under them
M.gamepad = true
M.inputChanged()
look()
local keyGas, keyBrake = named(gas.Parent, "Key"), nil
for _, child in pair:GetChildren() do
	if child.Name == "Key" and child ~= keyGas then
		keyBrake = child
	end
end
check("a gamepad: R2 / L2 under them (the platform's pictures)", keyGas ~= nil and keyBrake ~= nil and shown(keyGas) and shown(keyBrake)
	and named(keyGas, "Pad").Visible and string.find(named(keyGas, "Pad").Image .. named(keyBrake, "Pad").Image, "ButtonR2", 1, true) ~= nil
	and string.find(named(keyGas, "Pad").Image .. named(keyBrake, "Pad").Image, "ButtonL2", 1, true) ~= nil)
check("… the pair with them still clear of the speed and in the corner", not overlap(box(pair), box(speedRow)) and inside(box(pair)))
scene("pedals-1280x800-pad")
M.padImages = false
M.gamepad = false
M.inputChanged()
look()
M.gamepad = true
M.inputChanged()
look()
local words = keyGas.Text .. " " .. keyBrake.Text
check("… no picture from the platform: the words R2 and L2", string.find(words, "R2", 1, true) ~= nil and string.find(words, "L2", 1, true) ~= nil, words)
M.padImages = true
M.gamepad = false
M.inputChanged()
look()
check("the keys again: no R2 / L2", not shown(keyGas) and not shown(keyBrake))

-- ── Hidden with the HUD, under a window, dead ───────────────────────────────
hud.Enabled = false
look()
check("the HUD hidden (the start screen): hidden", not DrivePedals.shown())
hud.Enabled = true
look()
check("the HUD back: shown", DrivePedals.shown())
local covered = true
DrivePedals.covered = function()
	return covered
end
look()
check("a window over the game (DrivePedals.covered): hidden", not DrivePedals.shown())
covered = false
look()
check("… closed: shown", DrivePedals.shown())
humanoid.Health = 0
look()
check("dead: hidden", not DrivePedals.shown())
humanoid.Health = 100
look()

-- ── A visitor's offer card while they show ──────────────────────────────────
local OfferCard = require("./OfferCard")
OfferCard.start()
OfferCard.covered = function()
	return false
end
local remote = M.Net.get("Visitors")
for index, s in { { true, 844, 354 }, { true, 667, 317 }, { false, 1280, 800 } } do
	screen(s[1], s[2], s[3])
	look()
	local before = { box(gas), box(brake) }
	remote.OnClientEvent:Fire({ kind = "offer", id = `p{index}`, name = "Gramophone", item = "gramophone", price = 340, base = 260, who = "Collector", seconds = 30, rarity = "rare" })
	M.flush()
	local card = box(OfferCard.card())
	local label = `an offer card at {s[2]} × {s[3]}`
	check(`{label}: open, clear of the pedals`, OfferCard.isOpen() and not overlap(card, before[1]) and not overlap(card, before[2]), `{show(card)} / {show(before[1])} {show(before[2])}`)
	look()
	local g2, b2 = box(gas), box(brake)
	check(`{label}: the pedals stay where they were, clear of it`, show(g2) == show(before[1]) and show(b2) == show(before[2]) and not overlap(card, g2) and not overlap(card, b2),
		`{show(card)} / {show(before[1])} {show(before[2])} → {show(g2)} {show(b2)}`)
	check(`{label}: they still show (a visitor's offer is no window over the game for them)`, DrivePedals.shown())
	if s[2] == 844 then
		scene("pedals-844x354-offer")
	end
	remote.OnClientEvent:Fire({ kind = "closed", id = `p{index}` })
	M.flush()
end

-- ── Something over their spot (the quick chat's button here), then gone ────
screen(true, 844, 354)
look()
local home = { box(gas), box(brake) }
local chatGui = M.make("ScreenGui", { Name = "QuickChat" }, M.gui)
local chatButton = M.make("TextButton", { Name = "QuickChatButton", Text = "💬" }, chatGui)
place(chatButton, { x0 = home[1].x0 - 10, y0 = home[1].y0 + 10, x1 = home[1].x1 + 4, y1 = home[1].y0 + 54 })
look()
check("something lying on them: they move, clear of it", show(box(gas)) ~= show(home[1]) and not overlap(box(gas), box(chatButton)) and not overlap(box(brake), box(chatButton)),
	`{show(box(brake))} {show(box(gas))} / {show(box(chatButton))}`)
local held2 = touch(gas)
frames(1)
local moved = box(gas)
chatButton.Visible = false
look()
check("… gone while GAS is held: they stay (never from under a finger)", show(box(gas)) == show(moved) and drive.pedal == 1)
lift(held2)
frames(1)
look()
check("… let go: back on their spot", show(box(gas)) == show(home[1]) and show(box(brake)) == show(home[2]), `{show(box(gas))} / {show(home[1])}`)
chatGui:Destroy()

check("no warnings", #M.warnings == 0, M.warnings[1])
if dump then
	local function encode(value, out)
		local t = type(value)
		if t == "number" then
			if value ~= value or value == math.huge or value == -math.huge then
				table.insert(out, "null")
			elseif value == math.floor(value) and math.abs(value) < 1e15 then
				table.insert(out, string.format("%d", value))
			else
				table.insert(out, string.format("%.3f", value))
			end
		elseif t == "string" then
			table.insert(out, '"' .. string.gsub(value, '[%c"\\]', function(ch)
				return string.format("\\u%04x", string.byte(ch))
			end) .. '"')
		elseif t == "boolean" then
			table.insert(out, tostring(value))
		elseif t == "table" then
			if #value > 0 or next(value) == nil then
				table.insert(out, "[")
				for k, v in value do
					if k > 1 then
						table.insert(out, ",")
					end
					encode(v, out)
				end
				table.insert(out, "]")
			else
				table.insert(out, "{")
				local first = true
				for k, v in value do
					if not first then
						table.insert(out, ",")
					end
					first = false
					encode(tostring(k), out)
					table.insert(out, ":")
					encode(v, out)
				end
				table.insert(out, "}")
			end
		else
			table.insert(out, "null")
		end
	end
	local out = {}
	encode(scenes, out)
	print(table.concat(out))
else
	print("ALL DRIVE PEDALS CHECKS PASSED")
end
