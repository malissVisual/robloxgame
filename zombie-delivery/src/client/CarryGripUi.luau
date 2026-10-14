--!strict
-- 8.1 grip (the owner: "when I fail, something must always happen, but make it easier; it is hard to keep pressing and
-- walk at the same time. When we pick it up the first time I should have to hit a target: I'm feeling for the grip"):
-- the timing check on this client. server/Moving.luau's grip block opens a check (the Moving remote's ("grip", "open",
-- wire): a lift check when you Pick up / Lift / Help lift a piece with a grip, a WOBBLE! now and then while you carry
-- it), judges the answer and sends the outcome ("grip", "result", r) or takes the check off ("grip", "close", id);
-- shared/CarryGrip.luau has the needle's maths (the same on both sides). Nothing to hold any more: walking is free.
--   * The widget (client/MoveLayout.luau gripCheck: in the middle under the character, else as near as is clear of
--     the HUD's groups, the move's top blocks with the sandbox's guide line, the quick chat's button, the move's list
--     and the touch controls), in the UI kit's look: a charcoal card, the piece's icon and the title (GET A GRIP! /
--     WOBBLE! / LAST CHANCE! when its miss drops the piece), a track with the green zone and the needle sweeping it,
--     the time left as a thin bar, the key under it (the first Ui.Tutorial checks: "… in the green"; LAST CHANCE!:
--     "A miss drops it · …").
--   * One press: the left mouse button or F (a computer), R2 (a gamepad), the round GRIP button on a touch screen (at
--     the right over the touch buttons, at least Config.CarryGrip.Ui.TapMin px), or a tap or click on the widget. The
--     needle stops where you pressed; the client says ("grip", id, "ok" | "miss", s into the check) at once (the
--     server judges it again), no press within the window: ("grip", id, "miss").
--   * The outcome (the server's): BALANCED! (+10% walk), SLIPPED BACK! (a knock: try again), STEADY!, STAGGER! (a knock,
--     slower a moment, the next miss drops it), DROPPED! (it fell). A miss shakes the widget (a pixel with Reduced
--     Motion) and the camera a little (client/CameraRig.luau shake), flashes red; it stays Ui.Linger s.
--   * The sounds (art/audio/sfx4.ogg): grip_tick at a lift check's start and each time the needle enters the zone,
--     grip_warning at a wobble's (louder when its miss drops it) and at a stagger, ding on a hit, furniture_putdown on a
--     lift's knock, client/MoveSounds.luau slipped() on a drop (one thud, not two).
--   * A door's fade (the Moving remote's "fade") hides it (the server takes the check off); off a move ("state" nil)
--     it goes.
-- Performance: nothing runs without a check; with one, a frame's step (RenderStepped) makes no tables, closures or
-- strings and sets a property only when it changes (a UDim2 only when a piece moved a whole pixel). The layout is asked
-- again on a resize, when the top blocks move, and once a second while it shows.
--   CarryGripUi.start(), CarryGripUi.active() (a check or its outcome shows), CarryGripUi.panel(), CarryGripUi.tapButton()

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local CarryGrip = require(Shared.CarryGrip)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local TouchLayout = require(script.Parent.TouchLayout)
local MoveLayout = require(script.Parent.MoveLayout)
local TopBlocks = require(script.Parent.TopBlocks)

local CarryGripUi = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local G = Config.CarryGrip
local ORANGE = Color3.fromRGB(240, 132, 44)
-- the HUD's groups (client/Hud.luau's panels, Hotbar's bar, KeyHints) the widget and the GRIP button keep clear of
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar", "KeyHints" }
-- the widget's insides (px at scale 1; MoveLayout.CHECK_W × CHECK_H)
local PAD = 12
local TRACK_Y, TRACK_H = 36, 26
local TRACK_W = MoveLayout.CHECK_W - 2 * PAD
local TIMER_Y = 68
local NEEDLE_W = 5
local WAIT_FOR = 2.5 -- s an answered check waits for the server's outcome before it goes

-- The outcomes' words (the title, its colour's tone, the line under it).
local OUTCOMES = {
	balanced = { "BALANCED!", "good" },
	knock = { "SLIPPED BACK!", "red" },
	steady = { "STEADY!", "good" },
	stagger = { "STAGGER!", "warn" },
	drop = { "DROPPED!", "red" },
} :: { [string]: { string } }

local remote = Net.get("Moving")
local gui: ScreenGui? = nil
local parts: any = nil -- the widget's pieces (built once)
local faded = false -- a door's fade is on
local checks = 0 -- checks so far (the tutorial's longer hint)

-- The check on now, or its outcome (nil: none).
type Run = {
	id: number,
	check: CarryGrip.Check?, -- (nil: an outcome of a check this client never saw)
	what: string,
	drop: boolean, -- a miss drops it (the server says)
	icon: string,
	number: number, -- this check's number (the tutorial's hint on the first Ui.Tutorial)
	at: number, -- os.clock when it opened
	pressed: number?, -- s into it the press came (the needle stops there)
	verdict: string?, -- "ok" | "miss" (this client's, sent)
	answeredAt: number,
	outcome: string?, -- the server's
	left: number?, -- the piece's condition after it (%)
	goneAt: number, -- os.clock it goes (0: not yet)
	inside: boolean, -- the needle in the zone at the last frame (the zone's tick)
	shakeUntil: number,
	flash: Color3?,
	flashUntil: number,
	title: string, -- the words as they are now (made when they change, not every frame)
	tone: string,
	hint: string,
}
local run: Run? = nil
local frameHook: RBXScriptConnection? = nil

-- What was drawn last (a property is set only when it changes).
local drawnNeedle, drawnTimer, drawnZone0, drawnZoneW = -1, -1, -1, -1
local drawnTitle, drawnHint, drawnTone = "", "", ""
local baseX, baseY, shakeX, shakeY = 0, 0, 0, 0

-- ── Small helpers ──────────────────────────────────────────────────────────

local function screen(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local made = Ui.make("ScreenGui", {
		Name = "CarryGrip",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 8, -- (over the move's panel and list: the GRIP button stays at hand)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = made
	return made
end

-- The sounds (client/Sounds.luau; the drop is client/MoveSounds.luau's), the camera's shake (client/CameraRig.luau),
-- found once (a frame's tick makes no closure).
local soundsModule: any = nil
local function loadSounds(): any
	return require(script.Parent.Sounds)
end
local function sound(name: string, volume: number, pitch: number?)
	if soundsModule == nil then
		local ok, found = pcall(loadSounds)
		soundsModule = if ok and type(found) == "table" then found else false
	end
	if soundsModule then
		pcall(soundsModule.play, name, volume, pitch)
	end
end
local function loadMoveSounds(): any
	return require(script.Parent.MoveSounds)
end
local function slipped()
	local ok, found = pcall(loadMoveSounds)
	if ok and type(found) == "table" and type(found.slipped) == "function" then
		pcall(found.slipped) -- (grip_slip: a whoosh and a thud; no put-down after it)
	end
end
local cameraModule: any = nil
local function loadCamera(): any
	return require(script.Parent.CameraRig)
end
local function shakeCamera(amount: number)
	if cameraModule == nil then
		local ok, found = pcall(loadCamera)
		cameraModule = if ok and type(found) == "table" then found else false
	end
	if cameraModule and type(cameraModule.shake) == "function" then
		pcall(cameraModule.shake, amount)
	end
end

-- Reduced Motion (the player's Roblox setting), looked at when a check opens and once a second.
local reduced = false
local function lookReduced()
	local ok, on = pcall(function(): boolean
		return (GuiService :: any).ReducedMotionEnabled == true
	end)
	reduced = ok and on == true
end

local function keysText(): string
	if Ui.touchLayout() then
		return "Tap GRIP"
	elseif Ui.gamepadActive() then
		return "Press R2"
	end
	return "Press LMB / F"
end

-- ── The widget ─────────────────────────────────────────────────────────────

local function build(root: ScreenGui): any
	local panel = Ui.make("Frame", {
		Name = "GripPanel",
		Size = UDim2.fromOffset(MoveLayout.CHECK_W, MoveLayout.CHECK_H),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		Visible = false,
	}, root)
	Ui.corner(panel, 12)
	local scale = Ui.make("UIScale", { Name = "Scale", Scale = 1 }, panel)
	local edge = Ui.make("UIStroke", { Name = "Edge", Color = ORANGE, Thickness = 2, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	local flash = Ui.make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.red, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6 }, panel)
	Ui.corner(flash, 12)
	local piece = Ui.label(panel, "📦", UDim2.fromOffset(26, 24), {
		Name = "Piece",
		Position = UDim2.fromOffset(PAD - 2, 7),
		Font = Theme.Font,
		TextSize = 19,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 7,
	})
	local title = Ui.label(panel, "GET A GRIP!", UDim2.fromOffset(TRACK_W - 30, 24), {
		Name = "Title",
		Position = UDim2.fromOffset(PAD + 30, 7),
		Font = Theme.HeadingFont,
		TextSize = 19,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		ZIndex = 7,
	})
	local track = Ui.make("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(PAD, TRACK_Y),
		Size = UDim2.fromOffset(TRACK_W, TRACK_H),
		BackgroundColor3 = K.recessed,
		BorderSizePixel = 0,
	}, panel)
	Ui.corner(track, 8)
	for _, at in { 0.25, 0.5, 0.75 } do -- (a faint ruler)
		Ui.make("Frame", { Name = "Rule", Position = UDim2.new(at, 0, 0, 6), Size = UDim2.new(0, 1, 1, -12), BackgroundColor3 = K.rule, BackgroundTransparency = 0.5, BorderSizePixel = 0 }, track)
	end
	local zone = Ui.make("Frame", {
		Name = "Zone",
		Position = UDim2.fromOffset(0, 2),
		Size = UDim2.fromOffset(60, TRACK_H - 4),
		BackgroundColor3 = K.good,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, track)
	Ui.corner(zone, 6)
	local zoneEdge = Ui.make("UIStroke", { Name = "ZoneEdge", Color = K.good, Thickness = 2, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, zone)
	local needle = Ui.make("Frame", {
		Name = "Needle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, TRACK_H / 2),
		Size = UDim2.fromOffset(NEEDLE_W, TRACK_H + 12),
		BackgroundColor3 = K.text,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, track)
	Ui.corner(needle, 3)
	Ui.make("UIStroke", { Name = "NeedleEdge", Color = K.charcoal, Thickness = 1, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, needle)
	local timer = Ui.make("Frame", {
		Name = "Timer",
		Position = UDim2.fromOffset(PAD, TIMER_Y),
		Size = UDim2.fromOffset(TRACK_W, 4),
		BackgroundColor3 = K.track,
		BorderSizePixel = 0,
	}, panel)
	Ui.corner(timer, 2)
	local timerFill = Ui.make("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = ORANGE, BorderSizePixel = 0, ZIndex = 2 }, timer)
	Ui.corner(timerFill, 2)
	local hint = Ui.label(panel, "", UDim2.fromOffset(TRACK_W, 18), {
		Name = "Hint",
		Position = UDim2.fromOffset(PAD, TIMER_Y + 8),
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		ZIndex = 7,
	})
	-- a tap or a click on the widget is a press too (the mouse's click there is the GUI's, not the world's)
	local press = Ui.make("TextButton", {
		Name = "Press",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 8,
	}, panel)
	-- the touch GRIP button (a round one, at the right over the touch buttons: MoveLayout.gripCheck)
	local tap = Ui.make("TextButton", {
		Name = "GripTap",
		Size = UDim2.fromOffset(G.Ui.TapMin, G.Ui.TapMin),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "GRIP",
		Font = Theme.HeadingFont,
		TextSize = 20,
		TextColor3 = K.text,
		Visible = false,
		ZIndex = 3,
	}, root)
	Ui.corner(tap, G.Ui.TapMin)
	local tapEdge = Ui.make("UIStroke", { Name = "TapEdge", Color = ORANGE, Thickness = 3, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tap)
	return {
		panel = panel,
		scale = scale,
		edge = edge,
		flash = flash,
		title = title,
		piece = piece,
		track = track,
		zone = zone,
		zoneEdge = zoneEdge,
		needle = needle,
		timer = timer,
		timerFill = timerFill,
		hint = hint,
		press = press,
		tap = tap,
		tapEdge = tapEdge,
	}
end

-- Where the widget and the GRIP button go now (client/MoveLayout.luau gripCheck).
local function place()
	local root = gui
	local p = parts
	if not root or not p then
		return
	end
	local size = root.AbsoluteSize
	local W, H = size.X, size.Y
	if W < 2 or H < 2 then
		size = Ui.screenSize()
		W, H = size.X, size.Y
	end
	local origin = root.AbsolutePosition
	local blocks: { TouchLayout.Box } = {}
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud then
		for _, name in HUD_GROUPS do
			local group = hud:FindFirstChild(name)
			if group and group:IsA("GuiObject") and group.Visible and group.AbsoluteSize.X > 1 and group.AbsoluteSize.Y > 1 then
				local at, s = group.AbsolutePosition - origin, group.AbsoluteSize
				table.insert(blocks, TouchLayout.box(at.X, at.Y, at.X + s.X, at.Y + s.Y))
			end
		end
	end
	for _, r in TopBlocks.rects(origin) do -- (the move's panel, Danny's strip, the sandbox's guide line)
		table.insert(blocks, r)
	end
	-- the quick chat's touch button, the move's list (O) while it is open
	local chat = playerGui and playerGui:FindFirstChild("QuickChat")
	local moving = playerGui and playerGui:FindFirstChild("MovingHud")
	for _, other in { chat and chat:FindFirstChild("QuickChatButton"), moving and moving:FindFirstChild("MoveList", true) } do
		if other and other:IsA("GuiObject") and other.Visible and other.AbsoluteSize.X > 1 then
			local at, s = other.AbsolutePosition - origin, other.AbsoluteSize
			table.insert(blocks, TouchLayout.box(at.X, at.Y, at.X + s.X, at.Y + s.Y))
		end
	end
	local touch = Ui.touchLayout()
	local panelBox, scale, tapBox = MoveLayout.gripCheck(W, H, Ui.screenScale(), touch, blocks, {
		tap = G.Ui.Tap,
		tapMin = G.Ui.TapMin,
		scale = G.Ui.Scale,
		min = G.Ui.Min,
	})
	baseX, baseY = math.floor(panelBox.x0 + 0.5), math.floor(panelBox.y0 + 0.5)
	shakeX, shakeY = 0, 0
	p.panel.Position = UDim2.fromOffset(baseX, baseY)
	if math.abs(p.scale.Scale - scale) > 0.001 then
		p.scale.Scale = scale
	end
	if tapBox then
		local side = math.floor(tapBox.x1 - tapBox.x0 + 0.5)
		p.tap.Position = UDim2.fromOffset(math.floor(tapBox.x0 + 0.5), math.floor(tapBox.y0 + 0.5))
		p.tap.Size = UDim2.fromOffset(side, side)
		p.tap.TextSize = math.max(18, math.floor(side * 0.22))
	end
	local r = run
	p.tap.Visible = touch and r ~= nil and r.check ~= nil and r.verdict == nil
end

-- ── Drawing ────────────────────────────────────────────────────────────────

local function resetDrawn()
	drawnNeedle, drawnTimer, drawnZone0, drawnZoneW = -1, -1, -1, -1
	drawnTitle, drawnHint, drawnTone = "", "", ""
	shakeX, shakeY = 0, 0
end

local function toneColor(tone: string): Color3
	return if tone == "good" then K.good elseif tone == "warn" then K.warn elseif tone == "red" then K.red else ORANGE
end

-- The title, its tone and the line under it as the run has them now (asked when the run changes: open, a press, the
-- timeout, the outcome).
local function words(r: Run)
	local outcome = r.outcome
	if outcome then
		local o = OUTCOMES[outcome]
		local left = if r.left then `{r.left}% left · ` else ""
		r.title, r.tone = if o then o[1] else "", if o then o[2] else ""
		r.hint = if outcome == "balanced" then "Balanced: +10% walk"
			elseif outcome == "knock" then `{left}try again (E)`
			elseif outcome == "steady" then "Steady again: +10% walk"
			elseif outcome == "stagger" then `{left}don't miss again`
			else `It fell{if r.left then ` · {r.left}% left` else ""}`
	elseif r.verdict then
		r.title, r.tone, r.hint = if r.verdict == "ok" then "NICE!" else "MISSED!", if r.verdict == "ok" then "good" else "red", ""
	else
		r.title = if r.what == "wobble" then (if r.drop then "LAST CHANCE!" else "WOBBLE!") else "GET A GRIP!"
		r.tone = if r.what == "wobble" and r.drop then "red" elseif r.what == "wobble" then "warn" else ""
		r.hint = if r.what == "wobble" and r.drop then `A miss drops it · {keysText()}`
			elseif r.number <= G.Ui.Tutorial then `{keysText()} in the green`
			else keysText()
	end
end

-- The widget as the run has it (a property only when it changed).
local function draw(r: Run, now: number)
	local p = parts
	local check = r.check
	local elapsed = now - r.at
	if check then
		local zone0 = math.floor(check.zone0 * TRACK_W + 0.5)
		local zoneW = math.floor(check.zone * TRACK_W + 0.5)
		if zone0 ~= drawnZone0 or zoneW ~= drawnZoneW then
			drawnZone0, drawnZoneW = zone0, zoneW
			p.zone.Position = UDim2.fromOffset(zone0, 2)
			p.zone.Size = UDim2.fromOffset(zoneW, TRACK_H - 4)
		end
		local at = CarryGrip.needle(check, r.pressed or math.min(elapsed, check.window))
		local x = math.floor(at * TRACK_W + 0.5)
		if x ~= drawnNeedle then
			drawnNeedle = x
			p.needle.Position = UDim2.fromOffset(x, TRACK_H / 2)
		end
		local left = if r.verdict then 0 else math.clamp(1 - elapsed / check.window, 0, 1)
		local timer = math.floor(left * 200 + 0.5)
		if timer ~= drawnTimer then
			drawnTimer = timer
			p.timerFill.Size = UDim2.fromScale(timer / 200, 1)
			p.timerFill.BackgroundColor3 = if left > 0.35 then ORANGE else K.red
		end
	end
	local title, tone, hint = r.title, r.tone, r.hint
	if title ~= drawnTitle or tone ~= drawnTone then
		drawnTitle, drawnTone = title, tone
		p.title.Text = title
		local color = toneColor(tone)
		p.title.TextColor3 = if tone == "" then K.text else color
		p.edge.Color = color
	end
	if hint ~= drawnHint then
		drawnHint = hint
		p.hint.Text = hint
	end
	-- a miss: a shake; a hit or a miss: a flash
	local amp = if now < r.shakeUntil then (if reduced then G.Ui.ReducedShake else G.Ui.Shake) else 0
	local dx = math.floor(math.sin(now * 53) * amp + 0.5)
	local dy = math.floor(math.cos(now * 41) * amp * 0.5 + 0.5)
	if dx ~= shakeX or dy ~= shakeY then
		shakeX, shakeY = dx, dy
		p.panel.Position = UDim2.fromOffset(baseX + dx, baseY + dy)
	end
	local flash = r.flash
	if flash and now < r.flashUntil then
		p.flash.BackgroundColor3 = flash
		p.flash.BackgroundTransparency = 0.55 + 0.45 * (1 - (r.flashUntil - now) / 0.35)
	elseif p.flash.BackgroundTransparency < 1 then
		p.flash.BackgroundTransparency = 1
	end
	if p.tap.Visible and r.verdict ~= nil then
		p.tap.Visible = false
	end
end

-- ── The run ────────────────────────────────────────────────────────────────

local function stop()
	local hook = frameHook
	if hook then
		hook:Disconnect()
		frameHook = nil
	end
	run = nil
	local p = parts
	if p then
		p.panel.Visible = false
		p.tap.Visible = false
	end
end

-- The press: the needle stops, the answer goes at once (the server judges it again).
local function press()
	local r = run
	if not r or faded or r.verdict or r.outcome then
		return
	end
	local check = r.check
	if not check then
		return
	end
	local now = os.clock()
	local elapsed = math.min(now - r.at, check.window)
	local hit = CarryGrip.hits(check, elapsed)
	r.pressed, r.verdict, r.answeredAt = elapsed, if hit then "ok" else "miss", now
	remote:FireServer("grip", r.id, r.verdict, elapsed)
	r.flash, r.flashUntil = if hit then K.good else K.red, now + 0.35
	words(r)
	if hit then
		sound("ding", G.Ui.Hit, 1.4)
	end
	if parts then
		parts.tap.BackgroundColor3 = K.raised
		parts.tapEdge.Color = K.text
	end
end

-- One frame: the timeout, the zone's tick, the outcome's end, the drawing.
local function frame()
	local r = run
	local p = parts
	if not r or not p then
		return
	end
	local now = os.clock()
	if r.goneAt > 0 and now >= r.goneAt then
		stop()
		return
	end
	local check = r.check
	if check and not r.verdict and not faded then
		local elapsed = now - r.at
		if elapsed >= check.window then
			-- no press in time: a miss (the needle stops at the end)
			r.pressed, r.verdict, r.answeredAt = check.window, "miss", now
			remote:FireServer("grip", r.id, "miss")
			r.flash, r.flashUntil = K.red, now + 0.35
			words(r)
		else
			local inside = CarryGrip.inZone(check, CarryGrip.needle(check, elapsed))
			if inside and not r.inside then
				sound("grip_tick", G.Ui.Tick)
			end
			r.inside = inside
		end
	end
	if r.verdict and not r.outcome and r.goneAt == 0 and now - r.answeredAt > WAIT_FOR then
		r.goneAt = now -- (no outcome came: the move ended, the check was off)
	end
	if faded then
		p.panel.Visible = false
		p.tap.Visible = false
		return
	end
	if not p.panel.Visible then
		p.panel.Visible = true
	end
	draw(r, now)
end

local function show(r: Run)
	local root = screen()
	if not root then
		return
	end
	if not parts then
		parts = build(root)
	end
	local p = parts
	run = r
	resetDrawn()
	lookReduced()
	p.piece.Text = r.icon
	p.track.Visible = r.check ~= nil
	p.timer.Visible = r.check ~= nil
	p.tap.BackgroundColor3 = K.charcoal
	p.tapEdge.Color = if r.what == "wobble" then K.warn else ORANGE
	p.panel.Visible = not faded
	place()
	draw(r, os.clock())
	if not frameHook then
		frameHook = RunService.RenderStepped:Connect(frame)
	end
end

local function newRun(id: number, check: CarryGrip.Check?, raw: any): Run
	return {
		id = id,
		check = check,
		what = if check then check.what elseif type(raw) == "table" and raw.what == "wobble" then "wobble" else "lift",
		drop = type(raw) == "table" and raw.drop == true,
		icon = if type(raw) == "table" and type(raw.icon) == "string" then raw.icon else "📦",
		number = checks,
		at = os.clock(),
		pressed = nil,
		verdict = nil,
		answeredAt = 0,
		outcome = nil,
		left = nil,
		goneAt = 0,
		inside = false,
		shakeUntil = 0,
		flash = nil,
		flashUntil = 0,
		title = "",
		tone = "",
		hint = "",
	}
end

-- ("grip", "open", wire): a new check (any other one goes).
local function opened(raw: any)
	local check = CarryGrip.fromWire(raw)
	if not check or type(raw.id) ~= "number" then
		return
	end
	checks += 1
	local r = newRun(raw.id, check, raw)
	words(r)
	show(r)
	if r.what == "wobble" then
		sound("grip_warning", if r.drop then G.Ui.Warning else G.Ui.Warning * 0.6)
	else
		sound("grip_tick", G.Ui.Open)
	end
end

-- ("grip", "result", r): the server's outcome (of the check on, or one this client no longer shows).
local function outcome(raw: any)
	if type(raw) ~= "table" or type(raw.outcome) ~= "string" or not OUTCOMES[raw.outcome] then
		return
	end
	local current = run
	local id = if type(raw.id) == "number" then raw.id else 0
	if current and current.id > id then
		return -- (an older check's: the one on now is newer)
	end
	local r: Run = if current and current.id == id then current else newRun(id, nil, raw)
	if r ~= current then
		show(r)
	end
	local now = os.clock()
	local result = raw.outcome :: string
	r.outcome = result
	r.left = if type(raw.left) == "number" then math.clamp(math.floor(raw.left), 0, 100) else nil
	r.verdict = r.verdict or (if result == "balanced" or result == "steady" then "ok" else "miss")
	r.goneAt = now + G.Ui.Linger
	words(r)
	if result == "balanced" or result == "steady" then
		r.flash, r.flashUntil = K.good, now + 0.35
		return
	end
	r.flash, r.flashUntil = K.red, now + 0.35
	r.shakeUntil = now + 0.4
	if result == "drop" then
		slipped()
		shakeCamera(G.Ui.CameraDrop)
	else
		sound(if result == "knock" then "furniture_putdown" else "grip_warning", if result == "knock" then G.Ui.Knock else G.Ui.Warning)
		shakeCamera(G.Ui.Camera)
	end
end

-- ── Start ──────────────────────────────────────────────────────────────────

function CarryGripUi.active(): boolean
	return run ~= nil
end

function CarryGripUi.panel(): GuiObject?
	return if parts then parts.panel else nil
end

function CarryGripUi.tapButton(): GuiObject?
	return if parts then parts.tap else nil
end

function CarryGripUi.start()
	local root = screen()
	if root and not parts then
		parts = build(root)
	end
	-- the presses: the left mouse button or F, R2; the touch GRIP button and the widget (their own)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or run == nil or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			press()
		end
	end)
	local p = parts
	if p then
		for _, button in { p.tap, p.press } do
			button.InputBegan:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
					press()
				end
			end)
		end
	end
	-- the checks, the outcomes, the door's fade, the move's end
	remote.OnClientEvent:Connect(function(kind: any, a: any, b: any)
		if kind == "grip" then
			if a == "open" then
				opened(b)
			elseif a == "result" then
				outcome(b)
			elseif a == "close" then
				local r = run
				if r and r.id == b and not r.outcome then
					stop()
				end
			end
		elseif kind == "fade" then
			faded = a == "out"
		elseif kind == "state" and a == nil then
			stop() -- (off a move)
		end
	end)
	-- the screen and the top blocks: the widget's place
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then
			camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				if run then
					pcall(place)
				end
			end)
		end
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	TopBlocks.onChanged(function()
		if run then
			pcall(place)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if run then
				lookReduced()
				pcall(place) -- (the HUD's groups come and go)
			end
		end
	end)
end

return CarryGripUi
