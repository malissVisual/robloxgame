--!strict
-- 7.0 grip (the owner, like the Roblox game Fisch's reeling: "while you carry something a bar shows, the load keeps
-- slipping away and you click / hold to keep it under control; hold it and you get it to the truck"): the grip bar on
-- this client. shared/CarryGrip.luau runs it (pure), server/Moving.luau decides: its grip hook gives the character the
-- attribute CarryGrip (the carry's kind, weight, fragile) next to MoveCarry (the spot) while you carry a thing with a
-- bar (a "both" or a "pair" thing, a fragile one-hand thing; Danny never has one); the bar shows while both are there.
-- 7.x: while Danny holds the other end of your piece (the character attribute GripSteady, server/MoveHelper.luau) the
-- grip box is Config.CarryGrip.Steadied × bigger (he steadies it).
--   * The panel right of the screen's middle (client/MoveLayout.luau grip: clear of the HUD's groups, the move's top
--     blocks, the quick chat's button and the touch buttons), in the UI kit's look: a charcoal panel, the bar (its
--     track), the grip box (green steady, amber, red slipping), the LOAD as the thing's icon (from the Moving remote's
--     state, its items by spot), the meter beside it, the title saying GRIP / STEADY +10% / SLIPPING! / DROPPED!
--     (7.1 review: STEADY +10% only while the server gives it: the meter full and the last report steady as the server
--     takes it, at most Config.CarryGrip.Server.SteadyOutside of it outside the box)
--   * Hold: the left mouse button or F (a computer), R2 (a gamepad), the round HOLD button on a touch screen (at the
--     right over the touch buttons, at least Config.CarryGrip.Ui.HoldMin px; jump, SPRINT and PUT DOWN stay free).
--     With a thing in your arms the gun is away, so these presses neither shoot nor punch.
--   * The body says how wild the load is: your speed and turns (the humanoid's MoveDirection), going up or down (the
--     root's vertical speed on the ground), a jump (in the air), a bite (health lost); standing still it calms down.
--   * The sounds (7.1, art/audio/sfx4.ogg): grip_tick as the meter moves a notch (like a reel's click, TickEvery s apart
--     at least), grip_warning on each entry into SLIPPING!, client/MoveSounds.luau slipped() at the slip.
--   * SLIPPING!: the panel shakes (a pixel with Reduced Motion) and flashes red. At 0 it slips: the Moving remote's
--     ("slip", spot); the server drops it (the damage, the notice) and the bar goes once MoveCarry does (DROPPED! a
--     moment first; still in your hands a second later: asked again). Picked up again, even the same piece inside
--     DROPPED!'s moment, it is a new bar (7.1 review: never the old one, which would ask "slip" again). About once a
--     Config.CarryGrip.Report s ("grip", spot, quality, steady): the share of the time outside the box (the server
--     wears the thing a little) and whether you are steady (the server's +10% walk: the meter full and at most
--     Server.SteadyOutside outside).
--   * The first Ui.Tutorial carries with a bar show "Hold to keep it steady!" beside it (the key's hint on the first
--     one only), until you are steady or a while has passed.
--   * Paused (and dark) while a door's fade is on (the Moving remote's "fade").
-- Performance: nothing runs without a bar (one light look four times a second at the attributes); with one, a step a
-- frame (RenderStepped) that makes no tables, closures or strings, and sets a property only when it changes (a UDim2
-- only when a piece moved a whole pixel). The layout is asked again on a resize, when the top blocks move, and once a
-- second while it shows.
--   CarryGripUi.start(), CarryGripUi.active() (a bar shows), CarryGripUi.panel(), CarryGripUi.holdButton()

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
-- the HUD's groups (client/Hud.luau's panels, Hotbar's bar, KeyHints) the panel and the HOLD button keep clear of
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar", "KeyHints" }
-- the panel's insides (px at scale 1; MoveLayout.GRIP_W × GRIP_H)
local TRACK_X, TRACK_Y, TRACK_W, TRACK_H = 14, 28, 44, 216
local METER_X, METER_W = 68, 14
local MARKER = 34
local TIP_FOR = 8 -- s the tip stays at most (it goes sooner once you are steady)
local LINGER = 0.8 -- s DROPPED! stays after a slip

local remote = Net.get("Moving")
local gui: ScreenGui? = nil
local parts: any = nil -- the panel's pieces (built once)
local icons: { [number]: string } = {} -- the things' icons by spot (the Moving remote's state)
local faded = false -- a door's fade is on
local carries = 0 -- carries with a bar so far (the tutorial's tip)

-- The carry with a bar now (nil: none).
type Run = {
	spot: number,
	code: string,
	mover: boolean,
	sim: CarryGrip.Sim,
	input: CarryGrip.Input,
	tutorial: number, -- this carry's number (the tip on the first Ui.Tutorial ones)
	tipUntil: number,
	since: number, -- s since the last report
	honoured: boolean, -- 7.1 review: the last report was steady as the server takes it (its +10% walk: the title)
	slipSent: number, -- os.clock of the last "slip" sent (0: none, or the server dropped it: the attributes went)
	linger: number, -- os.clock until DROPPED! stays
	heading: number?, -- the last MoveDirection's heading (the turn)
	health: number, -- the humanoid's health a step ago (a bite)
	bite: number,
	warned: boolean,
	wasSteady: boolean,
	steadied: boolean, -- 7.x Danny holds the other end (the character attribute GripSteady: a bigger box)
	notch: number, -- the meter's notch at the last grip_tick (Ui.TickNotches a meter)
	tickAt: number, -- the bar's time (sim.time) of the last grip_tick
	hooks: { RBXScriptConnection },
}
local run: Run? = nil

-- What is held down (any of them holds the grip).
local mouseHeld, keyHeld, padHeld, touchHeld = false, false, false, false
local touchInput: InputObject? = nil

-- What was drawn last (a property is set only when it changes).
local drawnZone, drawnZoneH, drawnMarker, drawnMeter = -1, -1, -1, -1
local drawnTone, drawnInside, drawnTitle = -1, -1, ""
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
		DisplayOrder = 8, -- (over the move's panel and list: the HOLD button stays at hand)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = made
	return made
end

-- The sounds (client/Sounds.luau, 7.1's sfx4: grip_tick, grip_warning; the slip is client/MoveSounds.luau's), found
-- once (a frame's tick makes no closure).
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

-- Reduced Motion (the player's Roblox setting), looked at when a bar starts and once a second (not every frame).
local reduced = false
local function lookReduced()
	local ok, on = pcall(function(): boolean
		return (GuiService :: any).ReducedMotionEnabled == true
	end)
	reduced = ok and on == true
end

local function holding(): boolean
	return mouseHeld or keyHeld or padHeld or touchHeld
end

local function keysText(): string
	if Ui.touchLayout() then
		return "Hold the HOLD button"
	elseif Ui.gamepadActive() then
		return "HOLD  R2"
	end
	return "HOLD  LMB / F"
end

-- ── The panel ──────────────────────────────────────────────────────────────

local function build(root: ScreenGui): any
	local panel = Ui.make("Frame", {
		Name = "GripPanel",
		Size = UDim2.fromOffset(MoveLayout.GRIP_W, MoveLayout.GRIP_H),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		Visible = false,
	}, root)
	Ui.corner(panel, 10)
	local scale = Ui.make("UIScale", { Name = "Scale", Scale = 1 }, panel)
	local edge = Ui.make("UIStroke", { Name = "Edge", Color = ORANGE, Thickness = 1, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
	local flash = Ui.make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.red, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6 }, panel)
	Ui.corner(flash, 10)
	local title = Ui.label(panel, "GRIP", UDim2.new(1, -8, 0, 16), {
		Name = "Title",
		Position = UDim2.fromOffset(4, 7),
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 7,
	})
	local track = Ui.make("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(TRACK_X, TRACK_Y),
		Size = UDim2.fromOffset(TRACK_W, TRACK_H),
		BackgroundColor3 = K.recessed,
		BorderSizePixel = 0,
	}, panel)
	Ui.corner(track, 8)
	for _, at in { 0.25, 0.5, 0.75 } do -- (a faint ruler)
		Ui.make("Frame", { Name = "Rule", Position = UDim2.new(0, 6, at, 0), Size = UDim2.new(1, -12, 0, 1), BackgroundColor3 = K.rule, BackgroundTransparency = 0.5, BorderSizePixel = 0 }, track)
	end
	local zone = Ui.make("Frame", {
		Name = "Zone",
		Position = UDim2.fromOffset(3, 0),
		Size = UDim2.fromOffset(TRACK_W - 6, 40),
		BackgroundColor3 = K.good,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, track)
	Ui.corner(zone, 6)
	local zoneEdge = Ui.make("UIStroke", { Name = "ZoneEdge", Color = K.good, Thickness = 2, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, zone)
	local marker = Ui.make("Frame", {
		Name = "Marker",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(TRACK_W / 2, TRACK_H / 2),
		Size = UDim2.fromOffset(MARKER, MARKER),
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, track)
	Ui.corner(marker, MARKER / 2)
	local markerEdge = Ui.make("UIStroke", { Name = "MarkerEdge", Color = K.text, Thickness = 2, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, marker)
	local icon = Ui.label(marker, "📦", UDim2.fromScale(1, 1), {
		Name = "Icon",
		Font = Theme.Font,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 5,
	})
	local meter = Ui.make("Frame", {
		Name = "Meter",
		Position = UDim2.fromOffset(METER_X, TRACK_Y),
		Size = UDim2.fromOffset(METER_W, TRACK_H),
		BackgroundColor3 = K.track,
		BorderSizePixel = 0,
	}, panel)
	Ui.corner(meter, 5)
	local fill = Ui.make("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = K.good,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, meter)
	Ui.corner(fill, 5)
	local status = Ui.label(panel, "", UDim2.new(1, -8, 0, 14), {
		Name = "Status",
		Position = UDim2.fromOffset(4, MoveLayout.GRIP_H - 22),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 7,
	})
	-- the tutorial's tip, left of the panel (it scales with it)
	local tip = Ui.label(panel, "", UDim2.fromOffset(176, 46), {
		Name = "Tip",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -8, 0.5, 0),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Visible = false,
		ZIndex = 7,
	})
	Ui.corner(tip, 8)
	Ui.make("UIStroke", { Color = ORANGE, Thickness = 1, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tip)
	-- the touch HOLD button (a round one, at the right over the touch buttons: MoveLayout.grip)
	local hold = Ui.make("TextButton", {
		Name = "GripHold",
		Size = UDim2.fromOffset(G.Ui.HoldMin, G.Ui.HoldMin),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "HOLD",
		Font = Theme.HeadingFont,
		TextSize = 18,
		TextColor3 = K.text,
		Visible = false,
		ZIndex = 3,
	}, root)
	Ui.corner(hold, G.Ui.HoldMin)
	local holdEdge = Ui.make("UIStroke", { Name = "HoldEdge", Color = ORANGE, Thickness = 2, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, hold)
	hold.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			touchHeld = true
			touchInput = input
		end
	end)
	hold.InputEnded:Connect(function(input: InputObject)
		if input == touchInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
			touchHeld = false
			touchInput = nil
		end
	end)
	return {
		panel = panel,
		scale = scale,
		edge = edge,
		flash = flash,
		title = title,
		track = track,
		zone = zone,
		zoneEdge = zoneEdge,
		marker = marker,
		markerEdge = markerEdge,
		icon = icon,
		fill = fill,
		status = status,
		tip = tip,
		hold = hold,
		holdEdge = holdEdge,
	}
end

-- Where the panel and the HOLD button go now (client/MoveLayout.luau grip).
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
	for _, r in TopBlocks.rects(origin) do
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
	local panelBox, scale, holdBox = MoveLayout.grip(W, H, Ui.screenScale(), touch, blocks, {
		hold = G.Ui.Hold,
		holdMin = G.Ui.HoldMin,
		scale = G.Ui.Scale,
		min = G.Ui.Min,
	})
	baseX, baseY = math.floor(panelBox.x0 + 0.5), math.floor(panelBox.y0 + 0.5)
	shakeX, shakeY = 0, 0
	p.panel.Position = UDim2.fromOffset(baseX, baseY)
	if math.abs(p.scale.Scale - scale) > 0.001 then
		p.scale.Scale = scale
	end
	if holdBox then
		local side = math.floor(holdBox.x1 - holdBox.x0 + 0.5)
		p.hold.Position = UDim2.fromOffset(math.floor(holdBox.x0 + 0.5), math.floor(holdBox.y0 + 0.5))
		p.hold.Size = UDim2.fromOffset(side, side)
		p.hold.TextSize = math.max(16, math.floor(side * 0.24))
	end
	p.hold.Visible = touch and run ~= nil
end

-- ── Drawing ────────────────────────────────────────────────────────────────

local TONES = { K.good, K.warn, K.red }

-- Steady as the server has it (7.1 review): the meter full and the last report honoured (not over
-- Server.SteadyOutside outside), so STEADY +10% never shows while the walk has no +10%.
local function shownSteady(r: Run): boolean
	return r.sim.steady and r.honoured
end

-- The bar as the run's sim has it (a property only when it changed).
local function draw(r: Run, now: number)
	local p = parts
	local sim = r.sim
	local prof = sim.profile
	local steady = shownSteady(r)
	local zoneH = math.floor(prof.zone * TRACK_H + 0.5)
	local zoneY = math.floor((1 - sim.zone - prof.zone) * TRACK_H + 0.5)
	if zoneY ~= drawnZone then
		drawnZone = zoneY
		p.zone.Position = UDim2.fromOffset(3, zoneY)
	end
	if zoneH ~= drawnZoneH then
		drawnZoneH = zoneH
		p.zone.Size = UDim2.fromOffset(TRACK_W - 6, zoneH)
	end
	local markerY = math.floor((1 - sim.marker) * TRACK_H + 0.5)
	if markerY ~= drawnMarker then
		drawnMarker = markerY
		p.marker.Position = UDim2.fromOffset(TRACK_W / 2, markerY)
	end
	local meter = math.floor(sim.meter * 200 + 0.5)
	if meter ~= drawnMeter then
		drawnMeter = meter
		p.fill.Size = UDim2.fromScale(1, meter / 200)
	end
	local tone = if sim.meter >= 0.66 then 1 elseif sim.meter > G.Meter.Warn then 2 else 3
	if tone ~= drawnTone then
		drawnTone = tone
		local color = TONES[tone]
		p.zone.BackgroundColor3 = color
		p.zoneEdge.Color = color
		p.fill.BackgroundColor3 = color
	end
	local inside = if sim.inside then 1 else 0
	if inside ~= drawnInside then
		drawnInside = inside
		p.markerEdge.Color = if sim.inside then K.text else K.red
	end
	-- the title: DROPPED! / SLIPPING! / STEADY +10% / GRIP
	local title = if sim.slipped then "DROPPED!" elseif sim.warn then "SLIPPING!" elseif steady then "STEADY +10%" else "GRIP"
	if title ~= drawnTitle then
		drawnTitle = title
		p.title.Text = title
		p.title.TextColor3 = if sim.slipped or sim.warn then K.red elseif steady then K.good else K.secondary
		p.status.Text = if sim.slipped then "" elseif sim.warn then "HOLD!" else ""
		p.edge.Color = if sim.slipped or sim.warn then K.red elseif steady then K.good else ORANGE
	end
	-- SLIPPING!: a shake and a red flash
	local alarm = sim.warn or sim.slipped
	local amp = if alarm then (if reduced then G.Ui.ReducedShake else G.Ui.Shake) else 0
	local dx = math.floor(math.sin(now * 47) * amp + 0.5)
	local dy = math.floor(math.cos(now * 39) * amp * 0.5 + 0.5)
	if dx ~= shakeX or dy ~= shakeY then
		shakeX, shakeY = dx, dy
		p.panel.Position = UDim2.fromOffset(baseX + dx, baseY + dy)
	end
	p.flash.BackgroundTransparency = if alarm then 0.62 + 0.3 * (0.5 + 0.5 * math.sin(now * 14)) else 1
	-- the touch HOLD lit while held
	if p.hold.Visible then
		local lit = touchHeld
		p.hold.BackgroundColor3 = if lit then K.raised else K.charcoal
		p.holdEdge.Color = if lit then K.text else ORANGE
	end
end

local function resetDrawn()
	drawnZone, drawnZoneH, drawnMarker, drawnMeter = -1, -1, -1, -1
	drawnTone, drawnInside, drawnTitle = -1, -1, ""
	shakeX, shakeY = 0, 0
end

-- ── The run ────────────────────────────────────────────────────────────────

-- The carry with a bar (code: the character's CarryGrip, spot: its MoveCarry), or nil.
local function current(): (string?, number?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local code = character:GetAttribute("CarryGrip")
	local spot = character:GetAttribute("MoveCarry")
	if type(code) ~= "string" or type(spot) ~= "number" then
		return nil, nil
	end
	return code, spot
end

local function profileOf(code: string, mover: boolean, steadied: boolean): CarryGrip.Profile?
	local kind, weight, fragile = CarryGrip.decode(code)
	if not kind then
		return nil
	end
	return CarryGrip.profile(kind, weight, fragile, mover, steadied)
end

local function bodyOf(): (BasePart?, Humanoid?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if root and root:IsA("BasePart") then root else nil, humanoid
end

local function stop()
	local r = run
	if not r then
		return
	end
	for _, hook in r.hooks do
		hook:Disconnect()
	end
	run = nil
	touchHeld, touchInput = false, nil
	local p = parts
	if p then
		p.panel.Visible = false
		p.hold.Visible = false
		p.tip.Visible = false
	end
end

-- One frame of the bar: the body's state, a step, the reports, the drawing.
local function frame(dt: number)
	local r = run
	local p = parts
	if not r or not p then
		return
	end
	local now = os.clock()
	local sim = r.sim
	if faded then
		return -- (a door's fade: paused)
	end
	if not sim.slipped then
		local input = r.input
		local root, humanoid = bodyOf()
		input.hold = holding()
		if root and humanoid then
			local v = root.AssemblyLinearVelocity
			input.speed = math.sqrt(v.X * v.X + v.Z * v.Z)
			input.air = humanoid.FloorMaterial == Enum.Material.Air
			input.climb = if input.air then 0 else v.Y
			-- the turn: how fast the way you walk swings round
			local way = humanoid.MoveDirection
			local turn = 0
			if way.X * way.X + way.Z * way.Z > 0.01 then
				local heading = math.atan2(way.X, way.Z)
				local last = r.heading
				if last and dt > 0 then
					local d = heading - last
					if d > math.pi then
						d -= 2 * math.pi
					elseif d < -math.pi then
						d += 2 * math.pi
					end
					turn = d / dt
				end
				r.heading = heading
			else
				r.heading = nil
			end
			input.turn = input.turn + (turn - input.turn) * math.min(1, dt * 8) -- (smoothed: no spike a frame)
			local health = humanoid.Health
			if health < r.health and health > 0 then
				r.bite += r.health - health
			end
			r.health = health
		else
			input.speed, input.climb, input.air = 0, 0, false
		end
		input.bite = r.bite
		r.bite = 0
		local event = CarryGrip.step(sim, input, dt)
		-- the report about once a second
		r.since += dt
		if r.since >= G.Report then
			r.since = 0
			local quality, steady = CarryGrip.report(sim)
			r.honoured = steady and quality <= G.Server.SteadyOutside -- (7.1 review: as the server takes it)
			remote:FireServer("grip", r.spot, quality, r.honoured)
		end
		-- the reel's tick as the meter moves a notch (TickEvery s apart at least), the warning on each entry into SLIPPING!
		local notch = math.floor(sim.meter * G.Ui.TickNotches)
		if notch ~= r.notch and sim.time - r.tickAt >= G.Ui.TickEvery then
			r.notch, r.tickAt = notch, sim.time
			sound("grip_tick", G.Ui.Tick)
		end
		if sim.warn and not r.warned then
			r.warned = true
			sound("grip_warning", G.Ui.Warning)
		elseif not sim.warn then
			r.warned = false
		end
		local steady = shownSteady(r)
		if steady and not r.wasSteady then
			sound("ding", 0.25, 1.4)
			if r.tipUntil > now then
				r.tipUntil = now + 0.6 -- (got it: the tip goes)
			end
		end
		r.wasSteady = steady
		if event == "slip" then
			r.slipSent = now
			r.linger = now + LINGER
			remote:FireServer("slip", r.spot)
			slipped()
		end
	elseif r.slipSent > 0 and now - r.slipSent > 1 then
		r.slipSent = now -- (still in your hands a second later: asked again)
		remote:FireServer("slip", r.spot)
	end
	if p.tip.Visible and now > r.tipUntil then
		p.tip.Visible = false
	end
	draw(r, now)
end

local function begin(code: string, spot: number, profile: CarryGrip.Profile, mover: boolean)
	local root = screen()
	if not root then
		return
	end
	if not parts then
		parts = build(root)
	end
	local p = parts
	carries += 1
	lookReduced()
	local seed = (math.floor(os.clock() * 1000) + spot * 7919) % 2147483647
	local _, humanoid = bodyOf()
	local r: Run = {
		spot = spot,
		code = code,
		mover = mover,
		sim = CarryGrip.new(profile, seed),
		input = CarryGrip.newInput(),
		tutorial = carries,
		tipUntil = if carries <= G.Ui.Tutorial then os.clock() + TIP_FOR else 0,
		since = 0,
		honoured = false,
		slipSent = 0,
		linger = 0,
		heading = nil,
		health = if humanoid then humanoid.Health else 100,
		bite = 0,
		warned = false,
		wasSteady = false,
		steadied = false,
		notch = math.floor(profile.start * G.Ui.TickNotches),
		tickAt = -math.huge,
		hooks = {},
	}
	run = r
	resetDrawn()
	p.icon.Text = icons[spot] or "📦"
	p.tip.Text = if carries <= 1 and not Ui.touchLayout() then `Hold to keep it steady!\n{keysText()}` else "Hold to keep it steady!"
	p.tip.Visible = r.tipUntil > 0
	p.panel.Visible = true
	place()
	draw(r, os.clock())
	table.insert(r.hooks, RunService.RenderStepped:Connect(frame))
end

-- The carry's bar shows while the character has CarryGrip and MoveCarry (a new carry: a new bar; another kind, a role
-- switch: the same bar, its profile changed).
local function refresh()
	local code, spot = current()
	local r = run
	local mover = player:GetAttribute("MoveRole") == "mover"
	local character = player.Character
	local steadied = character ~= nil and character:GetAttribute("GripSteady") == true -- 7.x Danny steadies it
	if not code or not spot then
		if r and r.sim.slipped and os.clock() < r.linger then
			r.slipSent = 0 -- (the server dropped it: never asked again)
			return -- (DROPPED! stays a moment)
		end
		stop()
		return
	end
	-- the same carry (a slipped bar still in your hands: the server has not dropped it yet, "slip" asked again each
	-- second). 7.1 review: a slipped bar the server dropped (its slipSent 0 since the attributes went) is over: the same
	-- piece picked up again inside DROPPED!'s moment is a new bar, not the old one (DROPPED! and a second "slip").
	-- 7.x: Danny took or let go of the other end (GripSteady): the same bar, its profile changed.
	if r and r.spot == spot and not (r.sim.slipped and r.slipSent == 0) then
		if r.code ~= code or r.mover ~= mover or r.steadied ~= steadied then
			local profile = profileOf(code, mover, steadied)
			if profile then
				CarryGrip.setProfile(r.sim, profile)
				if r.code ~= code then
					r.honoured = false -- (another kind: the server's steady starts over)
				end
				r.code, r.mover, r.steadied = code, mover, steadied
			end
		end
		return
	end
	stop()
	local profile = profileOf(code, mover, steadied)
	if profile then
		begin(code, spot, profile, mover)
		local started = run
		if started then
			started.steadied = steadied
		end
	end
end

-- ── Start ──────────────────────────────────────────────────────────────────

function CarryGripUi.active(): boolean
	return run ~= nil
end

function CarryGripUi.panel(): GuiObject?
	return if parts then parts.panel else nil
end

function CarryGripUi.holdButton(): GuiObject?
	return if parts then parts.hold else nil
end

function CarryGripUi.start()
	screen()
	-- the presses: the left mouse button or F, R2; the touch HOLD (its own button)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHeld = true
		elseif input.KeyCode == Enum.KeyCode.F then
			keyHeld = true
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			padHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHeld = false
		elseif input.KeyCode == Enum.KeyCode.F then
			keyHeld = false
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			padHeld = false
		end
		if touchInput and input == touchInput then
			touchHeld, touchInput = false, nil
		end
	end)
	-- (Alt-Tab swallows a button's end)
	UserInputService.WindowFocusReleased:Connect(function()
		mouseHeld, keyHeld, padHeld, touchHeld, touchInput = false, false, false, false, nil
	end)
	-- the things' icons (the move's state) and the door's fade
	remote.OnClientEvent:Connect(function(kind: any, a: any)
		if kind == "state" then
			table.clear(icons)
			if type(a) == "table" and type(a.items) == "table" then
				for _, item in a.items do
					if type(item) == "table" and type(item.spot) == "number" and type(item.icon) == "string" then
						icons[item.spot] = item.icon
					end
				end
			end
			local r = run
			if r and parts then
				parts.icon.Text = icons[r.spot] or "📦"
			end
		elseif kind == "fade" then
			faded = a == "out"
		end
	end)
	-- the carry's attributes: at once when they change, and a light look four times a second (a new body, a missed one)
	local watched: Model? = nil
	local function watch()
		local character = player.Character
		if character and character ~= watched then
			watched = character
			character:GetAttributeChangedSignal("MoveCarry"):Connect(refresh)
			character:GetAttributeChangedSignal("CarryGrip"):Connect(refresh)
			character:GetAttributeChangedSignal("GripSteady"):Connect(refresh) -- 7.x Danny took the other end
		end
	end
	player.CharacterAdded:Connect(function()
		watch()
		refresh()
	end)
	player:GetAttributeChangedSignal("MoveRole"):Connect(refresh)
	watch()
	-- the screen and the top blocks: the panel's place
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
		local ticks = 0
		while true do
			task.wait(0.25)
			watch()
			pcall(refresh)
			ticks += 1
			if run and ticks % 4 == 0 then
				lookReduced()
				pcall(place) -- (the HUD's groups come and go)
			end
		end
	end)
	refresh()
end

return CarryGripUi
