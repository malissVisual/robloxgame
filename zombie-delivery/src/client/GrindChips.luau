--!strict
-- 6.14, the fun grind on the HUD (the owner: "I want it to be a bit MORE grind, but a FUN grind"): two small chips at
-- the top of the screen and one big moment. The words and the numbers come from shared/Shift.luau.
--   * ON A ROLL (4.7's streak of good jobs, profile.streak; shared/JobRules.luau's rules as they are): from one job
--     rated ★★ or better in a row, "ON A ROLL ×1.2" (what the next ★★+ job's pay is multiplied by) over "4 GOOD JOBS
--     IN A ROW". It pops with a bell (higher the longer the streak) when it grows; when a ★ job or a failed one ends
--     it, it turns red, cracks, shakes and says "STREAK LOST · 4" for a moment before it goes.
--   * SHIFT 3/5 (server/Shift.luau, Config.Jobs.Shift: this session's deliveries toward the shift's pay) with a bar of
--     five, from the first delivery on; it pops (quietly) with every one. It starts over (0) once IdleReset passed
--     without a delivery, as the server does.
--   * SHIFT DONE: the shift's last delivery: a banner in the upper middle ("SHIFT DONE", "+$300 · +250 XP", the five
--     pips lighting up one by one), the till and the task sting, a little confetti (client/Juice.luau); then 0/5.
-- Where: in the HUD's ScreenGui (ZombieDeliveryHud) at the top, placed by TouchLayout.chips (side by side in the top
-- middle; on a small phone one over the other between the contract column and MAP / PHONE), looked at every CHECK
-- seconds; clear of the HUD's groups, the touch buttons, ADMIN and Roblox's player list. Hidden while a window, the
-- phone or a dialog covers the game (client/Hotbar.luau's `covered`); a pop, the crack or SHIFT DONE that happened
-- meanwhile plays when they show again, so the DELIVERY result window comes first. Reduced motion: no pop, shake,
-- slide or confetti (the colours and the fades only).
-- The data: the State (streak, shift: server/Main.server.luau), the DeliveryResult (rating.streak, rating.streakLost,
-- streakLost, shift: the moment itself). GrindChips.streak() gives the job board the streak as it is now.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local ShiftData = require(Shared.Shift)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local TouchLayout = require(script.Parent.TouchLayout)
local PhoneMotion = require(script.Parent.PhoneMotion)
local Hotbar = require(script.Parent.Hotbar)

local GrindChips = {}

local player = Players.LocalPlayer
local K = Theme.Contract

local WIDE, STACKED = TouchLayout.CHIPS_WIDE, TouchLayout.CHIPS_STACKED
local STREAK_W, SHIFT_W, CHIP_H = 168, 120, 40 -- (TouchLayout.CHIPS_WIDE / CHIPS_STACKED are these)
local CHECK = 0.25 -- seconds between two looks: the place, covered or not, the shift's idle end, what waits
local NEXT_EFFECT = 0.7 -- seconds between two effects that waited
local MAX_WAITING = 6 -- effects kept while the chips are covered
local LOST_SECONDS = 2.6 -- the broken chip shows this long
local BANNER_SECONDS = 3.4 -- SHIFT DONE stays this long
local HOLD_FULL = 60 -- seconds at most the shift chip waits full for SHIFT DONE to play
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar", "KeyHints" } -- client/Hud.luau's panels, Hotbar's bar, KeyHints
local PLAYER_LIST_W = 370 -- Roblox's player list on a computer (client/Hud.luau's layout says the same)
local ADMIN_BOX = { w = 90, h = 32, right = 16, top = 56 } -- client/AdminPanel.luau's ADMIN button (unscaled)
local TRACK = K.track
local AMBER = P.warn

type Chip = {
	holder: Frame,
	body: CanvasGroup,
	pop: UIScale,
	rule: Frame,
	flash: Frame,
	title: TextLabel,
	sub: TextLabel?,
}

local gui: ScreenGui? = nil
local root: Frame? = nil
local rootScale: UIScale? = nil
local rootList: UIListLayout? = nil
local streakChip: Chip? = nil
local shiftChip: Chip? = nil
local crack: Frame? = nil
local segments: { Frame } = {}
local banner: any = nil -- { frame, scale, line, pay, pips }

local streakNow: number? = nil -- the streak on the chip (nil before the first State: that one never pops)
local lostUntil = 0 -- os.clock() until the broken chip shows
local shift: ShiftData.View = { count = 0, target = Config.Jobs.Shift.Jobs, idleUntil = nil, shifts = 0 }
local waiting: { () -> () } = {} -- effects that wait for the chips to show
local nextEffectAt = 0
local stackedNow: boolean? = nil
local bannerToken = 0
local fullUntil = 0 -- os.clock() until the shift chip shows the shift full (SHIFT DONE's moment)

-- ── Small helpers ──────────────────────────────────────────────────────────

local function reduced(): boolean
	return PhoneMotion.reducedMotion()
end

local function sound(name: string, volume: number, pitch: number?)
	pcall(function()
		require(script.Parent.Sounds).play(name, volume, pitch)
	end)
end

-- Does a window, the phone or a dialog cover the game (the bottom bar's rule), or is the HUD off (the start screen)?
local function covered(): boolean
	local hud = gui
	if not hud or not hud.Enabled then
		return true
	end
	local check = Hotbar.covered
	if check then
		local ok, value = pcall(check)
		return ok and value == true
	end
	return false
end

-- An effect now, or once the chips show again (a window covers them: the DELIVERY result first).
local function later(effect: () -> ())
	table.insert(waiting, effect)
	if #waiting > MAX_WAITING then
		table.remove(waiting, 1) -- (a window open for long: the oldest pops go, the newest play)
	end
end

-- The shift's deliveries now (0 once its idle end passed: the server starts it over then too).
local function shiftCount(): number
	local untilAt = shift.idleUntil
	if shift.count > 0 and untilAt ~= nil and workspace:GetServerTimeNow() > untilAt then
		return 0
	end
	return shift.count
end

-- ── Building ───────────────────────────────────────────────────────────────

local function text(parent: Instance, value: string, props: { [string]: any }): TextLabel
	local label = Ui.label(parent, value, UDim2.fromOffset(0, 0), {
		TextColor3 = P.ink,
		TextScaled = true,
		TextWrapped = false,
		TextStrokeColor3 = K.charcoal,
		TextStrokeTransparency = 1,
	})
	for key, v in props do
		(label :: any)[key] = v
	end
	return label
end

-- A chip: a charcoal body with a colour rule on its left (its holder keeps the room; the body pops and shakes).
local function chip(parent: Instance, name: string, width: number, color: Color3, order: number): Chip
	local holder = Ui.make("Frame", { Name = name, Size = UDim2.fromOffset(width, CHIP_H), BackgroundTransparency = 1, LayoutOrder = order, Visible = false }, parent)
	local body = Ui.make("CanvasGroup", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
	}, holder)
	local pop = Ui.make("UIScale", { Name = "Pop" }, body)
	local rule = Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, body)
	local flash = Ui.make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.ink, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, body)
	return { holder = holder, body = body, pop = pop, rule = rule, flash = flash, title = (nil :: any), sub = nil }
end

local function buildStreak(parent: Instance): Chip
	local c = chip(parent, "Streak", STREAK_W, AMBER, 1)
	text(c.body, "🔥", { Name = "Flame", Position = UDim2.fromOffset(9, 9), Size = UDim2.fromOffset(20, 22), TextScaled = false, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center })
	c.title = text(c.body, "", { Name = "Title", Position = UDim2.fromOffset(34, 4), Size = UDim2.new(1, -40, 0, 18), Font = Theme.HeadingFont })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 8 }, c.title)
	local sub = text(c.body, "", { Name = "Sub", Position = UDim2.fromOffset(34, 23), Size = UDim2.new(1, -40, 0, 12), Font = Theme.HeadingFont, TextColor3 = P.ink2 })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 10, MinTextSize = 6 }, sub)
	c.sub = sub
	-- The crack across it (shown as the streak breaks): two thin white strokes.
	local lines = Ui.make("Frame", { Name = "Crack", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 4 }, c.body)
	for _, def in { { 0.42, 0.5, 72, -18 }, { 0.6, 0.62, 40, 24 } } do
		Ui.make("Frame", {
			Size = UDim2.fromOffset(def[3], 2),
			Position = UDim2.fromScale(def[1], def[2]),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = def[4],
			BackgroundColor3 = P.ink,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
		}, lines)
	end
	crack = lines
	return c
end

local function buildShift(parent: Instance): Chip
	local c = chip(parent, "Shift", SHIFT_W, P.good, 2)
	c.title = text(c.body, "", { Name = "Title", Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -18, 0, 18), Font = Theme.HeadingFont })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 8 }, c.title)
	local bar = Ui.make("Frame", { Name = "Bar", Position = UDim2.fromOffset(12, 27), Size = UDim2.new(1, -20, 0, 6), BackgroundTransparency = 1 }, c.body)
	local count = math.max(1, Config.Jobs.Shift.Jobs)
	segments = {}
	for index = 1, count do
		table.insert(segments, Ui.make("Frame", {
			Name = `Pip{index}`,
			Size = UDim2.new(1 / count, -3, 1, 0),
			Position = UDim2.fromScale((index - 1) / count, 0),
			BackgroundColor3 = TRACK,
			BorderSizePixel = 0,
		}, bar))
	end
	return c
end

-- SHIFT DONE: a charcoal band in the upper middle, over everything of the HUD.
local function buildBanner(parent: Instance)
	local frame = Ui.make("CanvasGroup", {
		Name = "ShiftDone",
		Size = UDim2.fromOffset(360, 122),
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 40,
	}, parent)
	local scale = Ui.make("UIScale", {}, frame)
	Ui.make("Frame", { Name = "Rule", Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = P.good, BorderSizePixel = 0 }, frame)
	local line = text(frame, "", { Name = "Line", Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 13), Font = Theme.HeadingFont, TextColor3 = P.ink2, TextXAlignment = Enum.TextXAlignment.Center })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 11 }, line)
	local big = text(frame, "SHIFT DONE", { Name = "Big", Position = UDim2.fromOffset(0, 27), Size = UDim2.new(1, 0, 0, 40), Font = Theme.DisplayFont, TextXAlignment = Enum.TextXAlignment.Center })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 38 }, big)
	local pay = text(frame, "", { Name = "Pay", Position = UDim2.fromOffset(0, 69), Size = UDim2.new(1, 0, 0, 24), Font = Theme.HeadingFont, TextColor3 = P.good, TextXAlignment = Enum.TextXAlignment.Center })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 21 }, pay)
	local pipRow = Ui.make("Frame", { Name = "Pips", Position = UDim2.new(0.5, 0, 0, 102), AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(0, 8), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, frame)
	Ui.list(pipRow, false, 6)
	local pips: { Frame } = {}
	for index = 1, math.max(1, Config.Jobs.Shift.Jobs) do
		table.insert(pips, Ui.make("Frame", { Name = `Pip{index}`, Size = UDim2.fromOffset(26, 8), BackgroundColor3 = TRACK, BorderSizePixel = 0, LayoutOrder = index }, pipRow))
	end
	banner = { frame = frame, scale = scale, line = line, pay = pay, pips = pips }
end

local function build(hud: ScreenGui)
	gui = hud
	local frame = Ui.make("Frame", {
		Name = "GrindChips",
		Size = UDim2.fromOffset(WIDE.w, WIDE.h),
		Position = UDim2.new(0.5, -WIDE.w / 2, 0, 8),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
	}, hud)
	rootScale = Ui.make("UIScale", { Name = "LayoutScale" }, frame)
	rootList = Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, frame)
	root = frame
	streakChip = buildStreak(frame)
	shiftChip = buildShift(frame)
	buildBanner(hud)
end

-- ── Showing ────────────────────────────────────────────────────────────────

local function setChipColor(c: Chip, color: Color3)
	c.rule.BackgroundColor3 = color
end

local function renderStreak()
	local c = streakChip
	if not c or os.clock() < lostUntil then
		return -- (the broken chip keeps its words until it goes)
	end
	local view = ShiftData.streakChip(streakNow or 0)
	c.holder.Visible = view ~= nil
	if crack then
		crack.Visible = false
	end
	c.body.BackgroundColor3 = P.surface
	c.body.Position = UDim2.fromScale(0.5, 0.5)
	c.body.Rotation = 0
	setChipColor(c, AMBER)
	if view then
		c.title.Text = view.title
		c.title.TextColor3 = P.ink
		local sub = c.sub
		if sub then
			sub.Text = view.sub
			sub.TextColor3 = if view.max then AMBER else P.ink2
		end
	end
end

-- (SHIFT DONE's moment shows the shift full, whatever State comes meanwhile)
local function renderShift()
	local c = shiftChip
	if not c then
		return
	end
	local count = shiftCount()
	c.holder.Visible = count > 0 or shift.shifts > 0
	local on = if os.clock() < fullUntil then shift.target else count
	c.title.Text = `SHIFT {on}/{shift.target}`
	for index, segment in segments do
		segment.BackgroundColor3 = if index <= on then P.good else TRACK
	end
end

-- A chip pops: a quick swell and a white flash (reduced motion: the flash only).
local function pop(c: Chip, size: number)
	c.flash.BackgroundTransparency = 0.55
	TweenService:Create(c.flash, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	if reduced() then
		return
	end
	c.pop.Scale = size
	TweenService:Create(c.pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- The streak grew: the new numbers, a pop and a bell, higher the longer the streak.
local function grew(n: number)
	renderStreak()
	local c = streakChip
	if c then
		pop(c, 1.24)
		sound("ding", 0.4, 1 + 0.07 * math.min(n, 6))
	end
end

-- The streak broke: red, a crack, a shake, "STREAK LOST · 4"; then it goes (renderStreak once lostUntil passed).
local function broke(lost: number, failed: boolean)
	local c = streakChip
	if not c then
		return
	end
	lostUntil = os.clock() + LOST_SECONDS
	local view = ShiftData.lostChip(lost, failed)
	c.holder.Visible = true
	c.title.Text = view.title
	c.title.TextColor3 = P.danger
	local sub = c.sub
	if sub then
		sub.Text = view.sub
		sub.TextColor3 = P.ink2
	end
	setChipColor(c, P.danger)
	c.body.BackgroundColor3 = Color3.fromRGB(46, 20, 22)
	if crack then
		crack.Visible = true
	end
	sound("putdown", 0.7, 0.62)
	if reduced() then
		return
	end
	task.spawn(function()
		-- A short shake that dies down (8 steps, 0.4 s), a small tilt as it cracks.
		for step = 1, 8 do
			if os.clock() >= lostUntil then
				break
			end
			local side = if step % 2 == 0 then 1 else -1
			local strength = (9 - step) / 8
			c.body.Position = UDim2.new(0.5, side * 6 * strength, 0.5, 0)
			c.body.Rotation = side * 3 * strength
			task.wait(0.05)
		end
		c.body.Position = UDim2.fromScale(0.5, 0.5)
		c.body.Rotation = -2
	end)
end

-- SHIFT DONE: the banner, the pips one by one, the till and the task sting, confetti; the chip full, then 0.
local function done(money: number, xp: number, target: number)
	local b = banner
	if not b then
		return
	end
	bannerToken += 1
	local token = bannerToken
	b.line.Text = `{target} JOBS IN ONE GO`
	b.pay.Text = `+{Ui.money(money)}   ·   +{xp} XP`
	for _, pip in b.pips do
		pip.BackgroundColor3 = TRACK
	end
	local frame: CanvasGroup = b.frame
	local hud = gui
	local S = if hud then Ui.scaleFor(hud.AbsoluteSize) else 1
	local scale = if Ui.touchLayout() then math.max(S, TouchLayout.CHIPS_TOUCH) else S
	frame.Visible = true
	if reduced() then
		b.scale.Scale = scale
		frame.GroupTransparency = 0
	else
		b.scale.Scale = scale * 0.7
		frame.GroupTransparency = 1
		TweenService:Create(b.scale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = scale }):Play()
		TweenService:Create(frame, TweenInfo.new(0.2), { GroupTransparency = 0 }):Play()
		pcall(function()
			require(script.Parent.Juice).confetti()
		end)
	end
	sound("cash", 0.9)
	task.delay(0.35, sound, "task_done", 0.8)
	fullUntil = os.clock() + BANNER_SECONDS
	renderShift() -- (the chip full for the moment)
	local c = shiftChip
	if c then
		pop(c, 1.2)
	end
	for index, pip in b.pips do
		task.delay(0.15 + 0.11 * index, function()
			if bannerToken == token then
				pip.BackgroundColor3 = P.good
			end
		end)
	end
	task.delay(BANNER_SECONDS, function()
		if bannerToken ~= token then
			return
		end
		fullUntil = 0
		renderShift()
		TweenService:Create(frame, TweenInfo.new(0.45), { GroupTransparency = 1 }):Play()
		task.wait(0.5)
		if bannerToken == token then
			frame.Visible = false
		end
	end)
end

-- ── The data ───────────────────────────────────────────────────────────────

-- The streak as the server says it now. `failed`: a failed job ended it (else a ★ one), when the result says so.
local function setStreak(n: number, failed: boolean?)
	local before = streakNow
	streakNow = n
	if before == nil or n == before then
		renderStreak()
		return
	end
	if n > before then
		later(function()
			grew(n)
		end)
	elseif n == 0 then
		later(function()
			broke(before, failed == true)
		end)
	else
		renderStreak() -- (an admin's lower number)
	end
end

-- The shift as the server says it now ({ count, target, idleUntil?, shifts, done?, money?, xp? }).
local function setShift(view: any)
	if type(view) ~= "table" then
		return
	end
	local before = shiftCount()
	local beforeShifts = shift.shifts
	shift = {
		count = math.max(0, math.floor(tonumber(view.count) or 0)),
		target = math.max(1, math.floor(tonumber(view.target) or Config.Jobs.Shift.Jobs)),
		idleUntil = tonumber(view.idleUntil),
		shifts = math.max(0, math.floor(tonumber(view.shifts) or 0)),
	}
	if view.done == true then
		local money, xp, target = tonumber(view.money) or 0, tonumber(view.xp) or 0, shift.target
		fullUntil = os.clock() + HOLD_FULL -- (full, not 0, until SHIFT DONE plays: it may wait for a window)
		later(function()
			done(money, xp, target)
		end)
	elseif shift.count > before and shift.shifts == beforeShifts then
		later(function()
			renderShift()
			local c = shiftChip
			if c then
				pop(c, 1.12)
			end
		end)
	end
	renderShift()
end

local function onState(state: any)
	if type(state) ~= "table" then
		return
	end
	local streak = tonumber(state.streak)
	if streak then
		setStreak(math.max(0, math.floor(streak)), nil)
	end
	if type(state.shift) == "table" then
		setShift(state.shift)
	end
end

-- A delivery's result comes before the State it changed: it says why a streak ended and the shift's moment.
local function onResult(r: any)
	if type(r) ~= "table" then
		return
	end
	local rating = if type(r.rating) == "table" then r.rating else nil
	if r.success ~= true and (tonumber(r.streakLost) or 0) > 0 then
		setStreak(0, true) -- a failed job (or a lost order) ended it
	elseif rating and not r.rider and (tonumber(rating.streakLost) or 0) > 0 then
		setStreak(0, false) -- a ★ job ended it
	elseif rating and not r.rider and (tonumber(rating.streak) or 0) > 0 then
		setStreak(math.floor(tonumber(rating.streak) or 0), nil)
	end
	if r.success == true and type(r.shift) == "table" then
		setShift(r.shift)
	end
end

-- ── The place ──────────────────────────────────────────────────────────────

local function rectOf(object: GuiObject, origin: Vector2): TouchLayout.Box
	local p, s = object.AbsolutePosition - origin, object.AbsoluteSize
	return TouchLayout.box(p.X, p.Y, p.X + s.X, p.Y + s.Y)
end

local function adminShown(): boolean
	return player:GetAttribute("Admin") == true or (Config.Admin.InStudio and RunService:IsStudio())
end

local function playerListOn(): boolean
	local ok, on = pcall(function()
		return game:GetService("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
	end)
	return not ok or on == true
end

-- The chips side by side or one over the other.
local function arrange(stacked: boolean)
	if stackedNow == stacked then
		return
	end
	stackedNow = stacked
	local frame, list = root, rootList
	if not frame or not list then
		return
	end
	local shape = if stacked then STACKED else WIDE
	frame.Size = UDim2.fromOffset(shape.w, shape.h)
	list.FillDirection = if stacked then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
	list.HorizontalAlignment = if stacked then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, if stacked then STACKED.h - 2 * CHIP_H else 8)
	local c = shiftChip
	if c then
		c.holder.Size = UDim2.fromOffset(if stacked then STREAK_W else SHIFT_W, CHIP_H)
	end
end

local function place()
	local hud, frame, scaleObject = gui, root, rootScale
	if not hud or not frame or not scaleObject then
		return
	end
	local size = hud.AbsoluteSize
	local W, H = size.X, size.Y
	if W < 2 or H < 2 then
		return
	end
	local origin = hud.AbsolutePosition
	local touch = Ui.touchLayout()
	local S = Ui.scaleFor(size)
	local s = if touch then math.max(S, TouchLayout.CHIPS_TOUCH) else S
	local top = if touch then TouchLayout.MARGIN else 8
	local blocks: { TouchLayout.Box } = {}
	local leftEdge = 0
	local rowLeft, rowBottom = W - TouchLayout.MARGIN, top
	for _, name in HUD_GROUPS do
		local group = hud:FindFirstChild(name)
		if group and group:IsA("GuiObject") and group.Visible and group.AbsoluteSize.X > 1 and group.AbsoluteSize.Y > 1 then
			local r = rectOf(group, origin)
			table.insert(blocks, r)
			if (name == "LeftStack" or name == "TopStack") and r.y0 < top + STACKED.h * s then
				leftEdge = math.max(leftEdge, r.x1) -- (at the top left: the chips go right of it)
			elseif name == "HudButtons" then
				rowLeft, rowBottom = r.x0, r.y1
			end
		end
	end
	if adminShown() then
		local a = TouchLayout.box(W - ADMIN_BOX.right - ADMIN_BOX.w, ADMIN_BOX.top, W - ADMIN_BOX.right, ADMIN_BOX.top + ADMIN_BOX.h)
		table.insert(blocks, a)
		rowLeft, rowBottom = math.min(rowLeft, a.x0), math.max(rowBottom, a.y1)
	end
	if touch then
		local c = TouchLayout.cluster(W, H, S)
		for _, b in TouchLayout.buttons(c) do
			table.insert(blocks, b)
		end
		table.insert(blocks, c.thumb)
		table.insert(blocks, c.jump)
	elseif playerListOn() then
		table.insert(blocks, TouchLayout.box(W - TouchLayout.MARGIN - PLAYER_LIST_W, 0, W, math.min(H * 0.45, 52 + 40 * #Players:GetPlayers())))
	end
	local box, scale, stacked = TouchLayout.chips(W, H, WIDE, STACKED, s, leftEdge, top, rowLeft, rowBottom, blocks)
	arrange(stacked)
	local position = UDim2.fromOffset(math.floor(box.x0 + 0.5), math.floor(box.y0 + 0.5))
	if frame.Position ~= position then
		frame.Position = position
	end
	if math.abs(scaleObject.Scale - scale) > 0.001 then
		scaleObject.Scale = scale
	end
end

-- Every CHECK seconds: the shift's idle end, the broken chip's end, the place, shown or not, what waited.
local function tick()
	local frame = root
	if not frame then
		return
	end
	if shift.count > 0 and shiftCount() == 0 then
		shift = { count = 0, target = shift.target, idleUntil = nil, shifts = shift.shifts } -- (the idle end: 0, quietly)
		renderShift()
	end
	if lostUntil > 0 and os.clock() >= lostUntil then
		lostUntil = 0
		renderStreak()
	end
	local hidden = covered()
	local any = (streakChip ~= nil and streakChip.holder.Visible) or (shiftChip ~= nil and shiftChip.holder.Visible)
	if not hidden and (any or #waiting > 0) then -- (nothing to show: no placing either)
		place()
		if #waiting > 0 and os.clock() >= nextEffectAt then
			local effect = table.remove(waiting, 1) :: () -> ()
			nextEffectAt = os.clock() + NEXT_EFFECT
			local ok, err: any = pcall(effect)
			if not ok then
				warn(`[GrindChips] {err}`)
			end
			any = (streakChip ~= nil and streakChip.holder.Visible) or (shiftChip ~= nil and shiftChip.holder.Visible)
		end
	end
	frame.Visible = any and not hidden
end

-- ── The API ────────────────────────────────────────────────────────────────

-- The streak of good jobs as the HUD knows it now (nil before the first State): the job board's caption.
function GrindChips.streak(): number?
	return streakNow
end

function GrindChips.start()
	Net.get("State").OnClientEvent:Connect(onState)
	Net.get("DeliveryResult").OnClientEvent:Connect(onResult)
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("ZombieDeliveryHud", 30)
		if not hud or not hud:IsA("ScreenGui") then
			warn("[GrindChips] no HUD to sit in")
			return
		end
		build(hud)
		renderStreak()
		renderShift()
		while root and root.Parent do
			local ok, err: any = pcall(tick)
			if not ok then
				warn(`[GrindChips] {err}`)
			end
			task.wait(CHECK)
		end
	end)
end

return GrindChips
