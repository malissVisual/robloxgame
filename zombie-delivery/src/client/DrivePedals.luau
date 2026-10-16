--!strict
-- 9.1, the drive pedals (the owner: "Add a drive pedal to the game"; asked how: "just visible pedals on PC, and on
-- mobile as driving buttons"): GAS and BRAKE at the lower right while you drive your car, in a ScreenGui of their own
-- ("DrivePedals", its "Pedals" frame the pair), shaped as a car's pedals in the 3.8 contract look (a charcoal face,
-- white type, a fine light line, the red accent): GAS tall and narrow, standing on the floor; BRAKE wider and shorter,
-- hanging from its arm; rubber ribs across them, "GAS" / "BRAKE" under the ribs. The pure part (the input, the press,
-- where they go): shared/PedalRules.luau.
--   * A touch screen (no keys: client/PadGlyph.luau's "touch"): they are buttons, held to drive (client/Drive.luau
--     setPedal): GAS forward, BRAKE brakes and then backs up (as S does), both the brake to a stop; Roblox's thumbstick
--     still steers (and still drives while no pedal is held). Every touch is its own: the left thumb on the stick, the
--     right on a pedal; a touch that began on a pedal holds it until it ends, sliding onto the other one holds that one.
--     Placed at the bottom just left of the EXIT button's column, where the right thumb rests, clear of Roblox's jump
--     button and thumbstick, EXIT and the HUD's groups (the speed and the fuel), at least Ui.MinTouch each way. Placed
--     again on a resize, a device change or when something comes to lie on them; else they stay (a pedal never jumps
--     from under a finger) and take a better place that opened only while none is held.
--   * A computer (the keys, a gamepad): they show your feet (Drive.foot: W / S, a gamepad's R2 / L2 part way through
--     the seat's throttle), compact in the lower right corner over the speed; the mouse may hold them like a finger.
--     With a gamepad R2 / L2 under them (the platform's picture, PadGlyph.image; else the word).
--   * Pressed, a pedal goes down: it tips away (shorter, a few px lower over its shadow), a dark veil, a more solid face,
--     the red edge wider and the fine line red; let go, it comes back quickly (drawn every frame only while one moves).
--   * Shown only while you sit in your own car's driver's seat (a passenger does not drive), the HUD shows (its
--     ScreenGui "ZombieDeliveryHud" enabled: not on the start screen) and nothing covers the game (DrivePedals.covered,
--     set by client/Main.client.luau: a window, a menu, the result card; a visitor's offer card is no reason: it keeps
--     clear of the pedals, client/OfferCard.luau, and they of it). Hidden, nothing is held (Drive.setPedal(0)).
-- Numbers: Config.DrivePedals (On = false: none). Presentation and the local driver's input only.
--   DrivePedals.start()                 builds them (once) and starts the looks
--   DrivePedals.covered                 set by client/Main.client.luau: does something cover the game now?
--   DrivePedals.shown() -> boolean      are they on the screen
--   DrivePedals.held() -> (gas, brake)  held by a finger or the mouse

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local PedalRules = require(Shared.PedalRules)
local SandboxPad = require(Shared.SandboxPad)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Drive = require(script.Parent.Drive)
local PadGlyph = require(script.Parent.PadGlyph)
local TouchLayout = require(script.Parent.TouchLayout)

local DrivePedals = {}

DrivePedals.covered = nil :: (() -> boolean)?

local C = Config.DrivePedals
local K = Theme.Contract
local player = Players.LocalPlayer
-- the HUD's groups (client/Hud.luau's; the right column by its rows: the speed and the fuel), its touch buttons
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "Hint", "Fire", "BottomBar", "KeyHints", "TouchAct", "Sprint" }

type Pedal = {
	kind: string, -- "gas" | "brake"
	sign: number, -- 1 GAS, -1 BRAKE (the foot's side)
	pad: string, -- the gamepad's button (an Enum.KeyCode name): R2, L2
	button: TextButton, -- the pedal's box (the hit area, still)
	shadow: Frame,
	face: Frame,
	veil: Frame,
	stroke: UIStroke,
	accent: Frame,
	label: TextLabel,
	caption: TextLabel, -- a gamepad's R2 / L2 under it
	glyph: ImageLabel,
	ribs: { Frame },
	corners: { UICorner },
	arm: Frame?, -- BRAKE hangs from its arm (GAS stands on the floor)
	touches: { [InputObject]: boolean },
	mouse: boolean,
	press: number, -- 0 … 1, drawn
	drawn: number, -- the press last drawn (-1: never)
}

local started = false
local gui: ScreenGui? = nil
local pair: Frame? = nil
local pedals: { Pedal } = {}
local showing = false
local scale = 1
local placedKey = ""
local placedBase = "" -- the screen, the layout and the caption they were placed for
local placedGas: PedalRules.Box? = nil
local placedBrake: PedalRules.Box? = nil
local device = "keys"
local sinceCheck = math.huge
local sinceLayout = math.huge

-- ── Building ────────────────────────────────────────────────────────────────

local function build(kind: string, parent: Instance): Pedal
	local gas = kind == "gas"
	local ribs = if gas then C.Ribs.Gas else C.Ribs.Brake
	local button: TextButton = Ui.make("TextButton", {
		Name = if gas then "Gas" else "Brake",
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = false, -- (the gamepad's selection never lands here: R2 / L2 are its pedals)
		Active = true, -- (a finger on it does not turn the camera)
		ZIndex = 2,
	}, parent)
	-- BRAKE hangs from its arm, up behind the face to the pair's top (GAS stands on the floor, hinged under it)
	local arm: Frame? = nil
	if not gas then
		local made: Frame = Ui.make("Frame", { Name = "Arm", BackgroundColor3 = K.recessed, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 1 }, parent)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, made)
		arm = made
	end
	local corners: { UICorner } = {}
	local shadow: Frame = Ui.make("Frame", { Name = "Shadow", BackgroundColor3 = K.recessed, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 1 }, button)
	table.insert(corners, Ui.make("UICorner", { CornerRadius = UDim.new(0, 5) }, shadow))
	local face: Frame = Ui.make("Frame", { Name = "Face", BackgroundColor3 = K.charcoal, BackgroundTransparency = C.Face.Rest, BorderSizePixel = 0, ZIndex = 2 }, button)
	table.insert(corners, Ui.make("UICorner", { CornerRadius = UDim.new(0, 5) }, face))
	local stroke: UIStroke = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.text, Thickness = 1, Transparency = 0.3 }, face)
	-- the rubber ribs across its upper part (they squash with it as it tips away)
	local ribFrames: { Frame } = {}
	for index = 1, ribs do
		local y = 0.1 + (index - 1) * (0.56 / math.max(1, ribs - 1))
		local rib: Frame = Ui.make("Frame", {
			Name = "Rib",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.54, y),
			Size = UDim2.new(0.58, 0, 0, 3),
			BackgroundColor3 = K.line,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, face)
		Ui.make("UICorner", { CornerRadius = UDim.new(0, 2) }, rib)
		table.insert(ribFrames, rib)
	end
	-- the dark veil of a press (over the ribs), the red accent over it: a short edge down the middle of its left side
	-- (clear of the round corners) that lights up as it goes down
	local veil: Frame = Ui.make("Frame", { Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 }, face)
	table.insert(corners, Ui.make("UICorner", { CornerRadius = UDim.new(0, 5) }, veil))
	local accent: Frame = Ui.make("Frame", {
		Name = "Accent",
		Position = UDim2.fromScale(0, 0.14),
		Size = UDim2.new(0, C.Press.Accent[1], 0.72, 0),
		BackgroundColor3 = K.red,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, face)
	local label: TextLabel = Ui.make("TextLabel", {
		Name = "Label",
		Text = if gas then "GAS" else "BRAKE",
		Position = UDim2.fromScale(0, 0.74),
		Size = UDim2.fromScale(1, 0.22),
		BackgroundTransparency = 1,
		TextColor3 = K.text,
		Font = Theme.HeadingFont,
		TextSize = 12,
		ZIndex = 6,
	}, face)
	local caption: TextLabel = Ui.make("TextLabel", {
		Name = "Key",
		Text = "",
		BackgroundTransparency = 1,
		TextColor3 = K.secondary,
		Font = Theme.HeadingFont,
		TextSize = 11,
		Visible = false,
	}, parent)
	local glyph: ImageLabel = Ui.make("ImageLabel", { Name = "Pad", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Visible = false }, caption)
	local pads = SandboxPad.pads("drive") -- (R2 on, L2 back: Roblox's driving)
	return {
		kind = kind,
		sign = if gas then 1 else -1,
		pad = (if gas then pads[1] else pads[2]) or (if gas then "ButtonR2" else "ButtonL2"),
		button = button,
		shadow = shadow,
		face = face,
		veil = veil,
		stroke = stroke,
		accent = accent,
		label = label,
		caption = caption,
		glyph = glyph,
		ribs = ribFrames,
		corners = corners,
		arm = arm,
		touches = {},
		mouse = false,
		press = 0,
		drawn = -1,
	}
end

-- ── Held ────────────────────────────────────────────────────────────────────

local function isHeld(p: Pedal): boolean
	return p.mouse or next(p.touches) ~= nil
end

-- A touch that ended without its signal reaching us (the app sent to the background …) holds nothing.
local function prune(p: Pedal)
	for input in p.touches do
		local state = input.UserInputState
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			p.touches[input] = nil
		end
	end
end

local function release()
	for _, p in pedals do
		table.clear(p.touches)
		p.mouse = false
	end
end

local function inside(p: Pedal, position: Vector3): boolean
	local at, size = p.button.AbsolutePosition, p.button.AbsoluteSize
	return position.X >= at.X and position.X <= at.X + size.X and position.Y >= at.Y and position.Y <= at.Y + size.Y
end

local function hook(p: Pedal)
	p.button.InputBegan:Connect(function(input: InputObject)
		if not showing then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch then
			p.touches[input] = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			p.mouse = true
		end
	end)
end

-- ── Drawing ─────────────────────────────────────────────────────────────────

local function put(object: GuiObject, b: PedalRules.Box)
	object.Position = UDim2.fromOffset(math.floor(b.x0 + 0.5), math.floor(b.y0 + 0.5))
	object.Size = UDim2.fromOffset(math.floor(b.x1 - b.x0 + 0.5), math.floor(b.y1 - b.y0 + 0.5))
end

-- A pedal at its press (its box's size is the layout's).
local function draw(p: Pedal)
	local look = PedalRules.look(p.press)
	local size = p.button.Size
	local w, h = size.X.Offset, size.Y.Offset
	local depth = C.Press.Depth * scale
	local rest = math.max(1, h - depth)
	local faceH = rest * look.height
	local bottom = rest + look.down * scale
	p.shadow.Position = UDim2.fromOffset(0, depth)
	p.shadow.Size = UDim2.fromOffset(w, rest)
	local faceTop = math.floor(bottom - faceH + 0.5)
	p.face.Position = UDim2.fromOffset(0, faceTop)
	p.face.Size = UDim2.fromOffset(w, math.floor(faceH + 0.5))
	local arm = p.arm
	if arm then
		-- BRAKE's arm reaches down to its face's top edge (a hanging pedal: it follows the face down)
		arm.Size = UDim2.fromOffset(arm.Size.X.Offset, math.max(0, p.button.Position.Y.Offset + faceTop + 2))
	end
	local t = math.clamp(p.press, 0, 1)
	p.face.BackgroundTransparency = C.Face.Rest + (C.Face.Pressed - C.Face.Rest) * t
	p.veil.BackgroundTransparency = 1 - look.shade
	p.accent.Size = UDim2.new(0, math.max(1, math.floor(look.accent * math.max(scale, 0.6) + 0.5)), 0.72, 0)
	p.accent.BackgroundTransparency = if look.lit then 0 else 0.2
	p.stroke.Color = if look.lit then K.red else K.text
	p.stroke.Transparency = if look.lit then 0 else 0.3
	p.drawn = p.press
end

-- The gamepad's R2 / L2 under each (only with a gamepad).
local function drawCaptions(captioned: boolean)
	for _, p in pedals do
		p.caption.Visible = captioned
		if captioned then
			local image = PadGlyph.image(p.pad)
			p.glyph.Image = image
			p.glyph.Visible = image ~= ""
			p.caption.Text = if image ~= "" then "" else SandboxPad.button(p.pad)
		end
	end
end

-- ── Where they go ───────────────────────────────────────────────────────────

-- What they keep clear of, in their ScreenGui's px.
local function blocksNow(origin: Vector2): { PedalRules.Box }
	local list: { PedalRules.Box } = {}
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local function add(object: Instance?)
		if object and object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1 then
			local at, size = object.AbsolutePosition - origin, object.AbsoluteSize
			table.insert(list, PedalRules.box(at.X, at.Y, at.X + size.X, at.Y + size.Y))
		end
	end
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud then
		for _, name in HUD_GROUPS do
			add(hud:FindFirstChild(name))
		end
		-- the right column by what shows in it (the speed and the fuel, a touch screen's weapon line), not its whole room
		local right = hud:FindFirstChild("RightStack")
		if right and right:IsA("GuiObject") and right.Visible then
			for _, child in right:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					for _, row in child:GetChildren() do
						if row:IsA("GuiObject") and row.Visible then
							add(row)
						end
					end
				end
			end
		end
	end
	local offer = playerGui and playerGui:FindFirstChild("OfferCard")
	if offer and (offer :: any).Enabled ~= false then
		add(offer:FindFirstChild("OfferCard"))
	end
	local chat = playerGui and playerGui:FindFirstChild("QuickChat")
	add(chat and chat:FindFirstChild("QuickChatButton"))
	return list
end

local function key(list: { PedalRules.Box }): string
	local parts = table.create(#list)
	for index, b in list do
		parts[index] = string.format("%d,%d,%d,%d", math.floor(b.x0), math.floor(b.y0), math.floor(b.x1), math.floor(b.y1))
	end
	return table.concat(parts, ";")
end

local function place(force: boolean?)
	local screen, frame = gui, pair
	if not screen or not frame then
		return
	end
	local size = screen.AbsoluteSize
	local W, H = size.X, size.Y
	if W < 2 or H < 2 then
		local s = Ui.screenSize()
		W, H = s.X, s.Y
	end
	local touch = Ui.touchLayout()
	local captioned = device == "pad"
	local blocks = blocksNow(screen.AbsolutePosition)
	local base = `{W}x{H}|{touch}|{captioned}`
	local now = `{base}|{key(blocks)}`
	if now == placedKey and not force then
		return
	end
	local S = Ui.scaleFor(Vector2.new(W, H))
	local cluster = if touch then TouchLayout.cluster(W, H, S) else nil
	local gasBox, brakeBox, at, _, cost = PedalRules.layout(W, H, S, touch, cluster, blocks, captioned)
	-- only something else moved (a card opened, the column moved): they stay while nothing lies on them; with nothing
	-- held they take a better place that opened (a card gone). A pedal never jumps from under a finger.
	local was = placedGas
	if not force and base == placedBase and was and placedBrake and PedalRules.free(was, placedBrake, blocks) then
		if isHeld(pedals[1]) or isHeld(pedals[2]) then
			return -- (looked at again once let go)
		end
		if cost >= PedalRules.cost(W, H, S, touch, cluster, was, scale, captioned) - 0.5 then
			placedKey = now
			return
		end
	end
	placedKey = now
	placedBase = base
	scale = at
	placedGas, placedBrake = gasBox, brakeBox
	local sizes = PedalRules.sizes(at, captioned)
	local all = PedalRules.box(brakeBox.x0, math.min(gasBox.y0, brakeBox.y0), gasBox.x1, gasBox.y1 + sizes.caption)
	put(frame, all)
	local text = math.max(8, math.floor(14 * at + 0.5))
	local rib = math.max(1, math.floor(3 * at + 0.5))
	local round = math.max(2, math.floor(6 * at + 0.5))
	for _, p in pedals do
		local b = if p.kind == "gas" then gasBox else brakeBox
		put(p.button, PedalRules.box(b.x0 - all.x0, b.y0 - all.y0, b.x1 - all.x0, b.y1 - all.y0))
		p.label.TextSize = text
		for _, r in p.ribs do
			r.Size = UDim2.new(0.58, 0, 0, rib)
		end
		for _, corner in p.corners do
			corner.CornerRadius = UDim.new(0, round)
		end
		local arm = p.arm
		if arm then
			-- (from the pair's top down to the face's top edge: draw() follows the face as it goes down)
			local armW = math.max(3, math.floor((b.x1 - b.x0) * 0.14 + 0.5))
			local middle = (b.x0 + b.x1) / 2 - all.x0
			arm.Position = UDim2.fromOffset(math.floor(middle - armW / 2 + 0.5), 0)
			arm.Size = UDim2.fromOffset(armW, 0)
			arm.Visible = b.y0 - all.y0 >= 4
		end
		p.caption.TextSize = math.max(8, math.floor(12 * at + 0.5))
		p.caption.Position = UDim2.fromOffset(math.floor(b.x0 - all.x0 + 0.5), math.floor(b.y1 - all.y0 + 0.5))
		p.caption.Size = UDim2.fromOffset(math.floor(b.x1 - b.x0 + 0.5), math.floor(sizes.caption + 0.5))
		draw(p)
	end
	drawCaptions(captioned)
end

-- ── Showing ─────────────────────────────────────────────────────────────────

local function isCovered(): boolean
	local check = DrivePedals.covered
	if type(check) ~= "function" then
		return false
	end
	local ok, covered = pcall(check)
	return ok and covered == true
end

-- Should they show now: your own car's driver's seat, the HUD up, nothing over the game.
local function wanted(): boolean
	if C.On ~= true then
		return false
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	if not hud or (hud :: any).Enabled ~= true then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	local car, driving = Drive.seatedCar()
	if not car or not driving or car ~= Drive.myCar() then
		return false
	end
	return not isCovered()
end

local function setShown(on: boolean)
	local frame = pair
	if not frame or on == showing then
		return
	end
	showing = on
	frame.Visible = on
	if not on then
		release()
		Drive.setPedal(0)
		for _, p in pedals do
			p.press = 0
			draw(p)
		end
	else
		place(true)
	end
end

-- Every frame while they show: the input (what is held) and the press drawn.
local function frameStep(dt: number)
	if not showing then
		return
	end
	local gasPedal, brakePedal = pedals[1], pedals[2]
	prune(gasPedal)
	prune(brakePedal)
	Drive.setPedal(PedalRules.throttle(isHeld(gasPedal), isHeld(brakePedal), Drive.speed()))
	local foot = Drive.foot()
	for _, p in pedals do
		p.press = PedalRules.ease(p.press, PedalRules.target(isHeld(p), foot, p.sign), dt)
		if p.press ~= p.drawn then
			draw(p)
		end
	end
end

-- A few times a second: whether they show, the device, where they go.
local function look(dt: number)
	sinceCheck += dt
	sinceLayout += dt
	if sinceCheck < C.Check then
		return
	end
	sinceCheck = 0
	local was = device
	device = PadGlyph.device()
	setShown(wanted())
	if showing and (device ~= was or sinceLayout >= C.Place) then
		sinceLayout = 0
		place(device ~= was)
	end
end

function DrivePedals.shown(): boolean
	return showing
end

function DrivePedals.held(): (boolean, boolean)
	if #pedals < 2 then
		return false, false
	end
	return isHeld(pedals[1]), isHeld(pedals[2])
end

function DrivePedals.start()
	if started or C.On ~= true then
		return
	end
	started = true
	local playerGui = player:WaitForChild("PlayerGui")
	local screen: ScreenGui = Ui.make("ScreenGui", {
		Name = "DrivePedals",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- (the HUD's area: TouchLayout's boxes are in it)
		DisplayOrder = 1, -- (over the HUD, under the windows)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = screen
	local frame: Frame = Ui.make("Frame", { Name = "Pedals", BackgroundTransparency = 1, Visible = false }, screen)
	pair = frame
	pedals = { build("gas", frame), build("brake", frame) }
	for _, p in pedals do
		hook(p)
		draw(p)
	end
	-- a touch ends (wherever it is): the pedal it held lets go; one sliding onto the other pedal holds that one
	UserInputService.TouchEnded:Connect(function(input: InputObject)
		for _, p in pedals do
			p.touches[input] = nil
		end
	end)
	UserInputService.TouchMoved:Connect(function(input: InputObject)
		local from: Pedal? = nil
		for _, p in pedals do
			if p.touches[input] then
				from = p
			end
		end
		if not from then
			return
		end
		for _, p in pedals do
			if p ~= from and inside(p, input.Position) then
				from.touches[input] = nil
				p.touches[input] = true
				return
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			for _, p in pedals do
				p.mouse = false
			end
		elseif input.UserInputType == Enum.UserInputType.Touch then
			for _, p in pedals do
				p.touches[input] = nil
			end
		end
	end)
	-- the game window losing the focus (alt-tab, the app sent away): nothing stays held
	local focusLost = (UserInputService :: any).WindowFocusReleased
	if focusLost then
		focusLost:Connect(release)
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if showing then
			place(true)
		end
	end)
	RunService.RenderStepped:Connect(frameStep)
	RunService.Heartbeat:Connect(look)
end

return DrivePedals
