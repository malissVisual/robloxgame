--!strict
-- 6.15, the LIVE EVENT on the HUD (server/LiveEvents.luau runs it, shared/LiveEvents.luau has the words; the state is
-- the workspace attributes shared/LiveEvents.luau Attr names). Presentation only.
--   * The banner at the top of the HUD: a charcoal strip with the event's colour on its left, its name ("🌕 BLOOD
--     MOON") and the time left ("3:12", red in the last URGENT s), a one-line hint under it ("Jobs pay ×2 · more zombies,
--     and faster"; the supply drop says where the crate is and who has it), for the horde its progress ("HORDE 34/60"
--     and a bar). Placed by TouchLayout.banner, looked at every CHECK s: under the 6.14 grind chips (client/GrindChips:
--     their box while they show) or beside them, clear of the HUD's groups, the touch buttons (TouchLayout.cluster),
--     ADMIN and Roblox's player list; the narrow shape on the most crowded screens. Hidden while a window, the phone or a
--     dialog covers the game (client/Hotbar.luau's `covered`), like the chips.
--   * A tap or a click on it (the supply drop, the horde): the GPS to the crate (to the depot's drop-off while you carry
--     it) or to the gate (MapView.setWaypoint, the HUD's beam: MapView.onWaypoint).
--   * The stings: client/Sounds.luau "event_start" when one starts, "event_end" when it ends (the server's Notice says
--     it in a toast). It pops in (a quick swell, a flash; reduced motion: the flash only) and fades out (a fade only).
--   * For the other windows: EventBanner.current() (the id), EventBanner.boardStrip(parent, order) (the job boards'
--     strip while an event pays, client/DispatchUi.luau and client/PhoneApps.luau: "🕑 RUSH HOUR · ×1.5 pay · 3:12",
--     its clock ticking), EventBanner.workLine() (the phone's WORK tile: "🌕 BLOOD MOON · jobs pay ×2").
-- client/Weather.luau draws the Blood Moon's sky, client/MapView.luau the spot on the maps (both read the attributes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local Rules = require(Shared.LiveEvents)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local TouchLayout = require(script.Parent.TouchLayout)
local PhoneMotion = require(script.Parent.PhoneMotion)
local Hotbar = require(script.Parent.Hotbar)

local EventBanner = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local A = Rules.Attr

local CHECK = 0.25 -- seconds between two looks: the clock, the place, covered or not
local URGENT = 30 -- the clock turns red in the last seconds
local HUD_GROUPS = { "LeftStack", "TopStack", "HudButtons", "RightStack", "Hint", "Fire", "BottomBar", "KeyHints" } -- client/Hud.luau's panels, Hotbar's bar, KeyHints
local PLAYER_LIST_W = 370 -- Roblox's player list on a computer
local ADMIN_BOX = { w = 90, h = 32, right = 16, top = 56 } -- client/AdminPanel.luau's ADMIN button (unscaled)

type Parts = {
	frame: TextButton,
	scale: UIScale,
	body: CanvasGroup,
	pop: UIScale,
	rule: Frame,
	tint: Frame,
	flash: Frame,
	title: TextLabel,
	clock: TextLabel,
	hint: TextLabel,
	count: TextLabel,
	track: Frame,
	fill: Frame,
	gps: TextLabel,
}

local gui: ScreenGui? = nil
local parts: Parts? = nil
local shownId: string? = nil -- the event the banner shows (nil: none)
local narrowNow: boolean? = nil
local fadeUntil = 0 -- os.clock() until an ended event's banner fades out
local strips: { { label: TextLabel, holder: GuiObject } } = {} -- the job boards' strips (their clocks tick here)

-- ── The state ──────────────────────────────────────────────────────────────

local function text(name: string): string?
	local value = workspace:GetAttribute(name)
	return if type(value) == "string" then value else nil
end

local function number(name: string): number?
	local value = workspace:GetAttribute(name)
	return if type(value) == "number" then value else nil
end

local function spot(name: string): Vector3?
	local value = workspace:GetAttribute(name)
	return if typeof(value) == "Vector3" then value else nil
end

-- The running event's id (nil: none).
function EventBanner.current(): string?
	local id = text(A.Id)
	return if id and Rules.def(id) then id else nil
end

-- Seconds to its end.
local function left(): number
	local ends = number(A.Ends)
	return if ends then math.max(0, ends - workspace:GetServerTimeNow()) else 0
end

local function viewNow(): Rules.View
	return {
		id = EventBanner.current(),
		left = left(),
		phase = text(A.Phase),
		carrier = text(A.Carrier),
		side = text(A.Side),
		done = number(A.Done),
		total = number(A.Total),
	}
end

-- The phone's WORK tile while an event pays (nil otherwise).
function EventBanner.workLine(): string?
	return Rules.workLine(EventBanner.current())
end

-- ── Small helpers ──────────────────────────────────────────────────────────

local function reduced(): boolean
	return PhoneMotion.reducedMotion()
end

local function sound(name: string, volume: number)
	pcall(function()
		require(script.Parent.Sounds).play(name, volume)
	end)
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1] or 220, c[2] or 220, c[3] or 220)
end

local function label(parent: Instance, name: string, props: { [string]: any }): TextLabel
	local made = Ui.label(parent, "", UDim2.fromOffset(0, 0), {
		Name = name,
		TextColor3 = P.ink,
		TextScaled = true,
		TextWrapped = false,
		TextStrokeColor3 = K.charcoal,
		TextStrokeTransparency = 1,
	})
	for key, value in props do
		(made :: any)[key] = value
	end
	return made
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

-- ── The GPS ────────────────────────────────────────────────────────────────

-- Where the banner's tap sends the GPS: the crate (the depot's drop-off while you carry it), or the horde's gate.
local function target(): (Vector3?, string?)
	local id = EventBanner.current()
	if id == "supply" then
		local character = player.Character
		if character and character:GetAttribute("Carrying") == "crate" then
			return spot(A.Goal), "Supply drop-off"
		end
		return spot(A.Spot), "Supply drop"
	elseif id == "horde" then
		return spot(A.Spot), "The horde's gate"
	end
	return nil, nil
end

local function gps()
	local at, name = target()
	if not at or not name then
		return
	end
	pcall(function()
		local MapView = require(script.Parent.MapView)
		MapView.setWaypoint(Vector3.new(at.X, Map.RoadTop, at.Z))
		MapView.onWaypoint({ id = "liveevent", name = name, icon = "📍", x = at.X, z = at.Z, kind = "place", description = "" } :: any)
	end)
	sound("ui_click", 0.6)
end

-- ── Building ───────────────────────────────────────────────────────────────

local function build(hud: ScreenGui)
	gui = hud
	local shape = TouchLayout.BANNER
	local frame = Ui.make("TextButton", {
		Name = "EventBanner",
		Size = UDim2.fromOffset(shape.w, shape.h),
		Position = UDim2.new(0.5, -shape.w / 2, 0, 60),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		Active = false,
		Selectable = false,
		ZIndex = 3,
	}, hud) :: TextButton
	local scale = Ui.make("UIScale", { Name = "LayoutScale" }, frame)
	local body = Ui.make("CanvasGroup", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, frame)
	local pop = Ui.make("UIScale", { Name = "Pop" }, body)
	-- (a faint wash of the event's colour, its rule on the left, a flash for the pop)
	local tint = Ui.make("Frame", { Name = "Tint", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0.88, BorderSizePixel = 0 }, body)
	Ui.make("UIGradient", { Transparency = NumberSequence.new(0, 1) }, tint)
	local rule = Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 3, 1, 0), BorderSizePixel = 0 }, body)
	local flash = Ui.make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.ink, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5 }, body)
	local title = label(body, "Title", { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -84, 0, 21), Font = Theme.HeadingFont, TextXAlignment = Enum.TextXAlignment.Left })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 8 }, title)
	local clock = label(body, "Clock", { Position = UDim2.new(1, -70, 0, 6), Size = UDim2.fromOffset(60, 21), Font = Theme.MonoFont, TextXAlignment = Enum.TextXAlignment.Right })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 8 }, clock)
	local hint = label(body, "Hint", { Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -40, 0, 14), Font = Theme.HeadingFont, TextColor3 = P.ink2, TextXAlignment = Enum.TextXAlignment.Left })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 6 }, hint)
	local count = label(body, "Count", { Position = UDim2.fromOffset(12, 30), Size = UDim2.fromOffset(92, 14), Font = Theme.HeadingFont, TextXAlignment = Enum.TextXAlignment.Left, Visible = false })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 6 }, count)
	local track = Ui.make("Frame", { Name = "Track", Position = UDim2.fromOffset(110, 34), Size = UDim2.new(1, -146, 0, 6), BackgroundColor3 = K.track, BorderSizePixel = 0, Visible = false }, body)
	local fill = Ui.make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BorderSizePixel = 0 }, track)
	local pin = label(body, "Gps", { Position = UDim2.new(1, -26, 0, 29), Size = UDim2.fromOffset(16, 16), Text = "📍", Visible = false, TextXAlignment = Enum.TextXAlignment.Center })
	frame.Activated:Connect(gps)
	parts = {
		frame = frame,
		scale = scale,
		body = body,
		pop = pop,
		rule = rule,
		tint = tint,
		flash = flash,
		title = title,
		clock = clock,
		hint = hint,
		count = count,
		track = track,
		fill = fill,
		gps = pin,
	}
end

-- ── Showing ────────────────────────────────────────────────────────────────

-- The words and the bar for the event as it is now.
local function render(p: Parts, view: Rules.View)
	local words = Rules.banner(view, narrowNow == true)
	if not words then
		return
	end
	local color = rgb(words.color)
	p.rule.BackgroundColor3 = color
	p.tint.BackgroundColor3 = color
	p.fill.BackgroundColor3 = color
	p.title.Text = words.title
	p.clock.Text = words.clock
	p.clock.TextColor3 = if view.left <= URGENT then P.danger else P.ink
	local horde = words.count ~= nil
	p.count.Visible = horde
	p.track.Visible = horde
	p.hint.Visible = not horde
	if horde then
		p.count.Text = words.count or ""
		p.fill.Size = UDim2.fromScale(math.clamp(words.progress or 0, 0, 1), 1)
	else
		p.hint.Text = words.hint
	end
	local _, name = target()
	p.gps.Visible = name ~= nil
	p.frame.Active = name ~= nil -- (only a banner with a GPS takes the tap; the others let it through to the game)
end

-- It pops in: a quick swell and a white flash (reduced motion: the flash only).
local function popIn(p: Parts)
	p.flash.BackgroundTransparency = 0.5
	TweenService:Create(p.flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	p.body.GroupTransparency = 0
	if reduced() then
		p.pop.Scale = 1
		return
	end
	p.pop.Scale = 0.82
	TweenService:Create(p.pop, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- The event changed: a new one pops in with its sting, an ended one plays its own.
local function changed(p: Parts, id: string?)
	local before = shownId
	shownId = id
	if id and id ~= before then
		sound("event_start", 0.9)
		popIn(p)
	elseif id == nil and before ~= nil then
		sound("event_end", 0.8)
		fadeUntil = os.clock() + 0.45
		TweenService:Create(p.body, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
	end
end

-- ── The place ──────────────────────────────────────────────────────────────

local function rectOf(object: GuiObject, origin: Vector2): TouchLayout.Box
	local position, size = object.AbsolutePosition - origin, object.AbsoluteSize
	return TouchLayout.box(position.X, position.Y, position.X + size.X, position.Y + size.Y)
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

-- Where it goes (TouchLayout.banner): the same blocks as the grind chips (client/GrindChips.luau), and the chips.
local function place(p: Parts)
	local hud = gui
	if not hud then
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
			if (name == "LeftStack" or name == "TopStack") and r.y0 < top + TouchLayout.CHIPS_STACKED.h * s then
				leftEdge = math.max(leftEdge, r.x1)
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
	local chips = hud:FindFirstChild("GrindChips")
	local chipsBox = if chips and chips:IsA("GuiObject") and chips.Visible then rectOf(chips, origin) else nil
	local box, scale, narrow = TouchLayout.banner(W, H, TouchLayout.BANNER, s, leftEdge, top, rowLeft, rowBottom, chipsBox, blocks)
	if narrowNow ~= narrow then
		narrowNow = narrow
		local shape = if narrow then TouchLayout.BANNER_NARROW else TouchLayout.BANNER
		p.frame.Size = UDim2.fromOffset(shape.w, shape.h)
	end
	local position = UDim2.fromOffset(math.floor(box.x0 + 0.5), math.floor(box.y0 + 0.5))
	if p.frame.Position ~= position then
		p.frame.Position = position
	end
	if math.abs(p.scale.Scale - scale) > 0.001 then
		p.scale.Scale = scale
	end
end

-- Every CHECK seconds: the event, its words, the place, shown or not; the boards' strips' clocks.
local function tick()
	local p = parts
	if not p then
		return
	end
	local view = viewNow()
	if view.id ~= shownId then
		changed(p, view.id)
	end
	local hidden = covered()
	local show = view.id ~= nil and not hidden
	if show then
		render(p, view)
		place(p)
	end
	p.frame.Visible = show or (view.id == nil and os.clock() < fadeUntil and not hidden) -- (an ended one fades out)
	for index = #strips, 1, -1 do
		local strip = strips[index]
		if not strip.label.Parent then
			table.remove(strips, index)
		else
			local line = Rules.boardLine(view.id, view.left)
			strip.holder.Visible = line ~= nil
			strip.label.Text = line or ""
		end
	end
end

-- ── The job boards' strip ──────────────────────────────────────────────────

-- While an event pays (the Blood Moon, rush hour): a strip in the event's colour at `order` in a job list (J's board,
-- the phone's JOBS), its clock ticking; nothing otherwise. Returns it (nil: no strip now).
function EventBanner.boardStrip(parent: Instance, order: number): Frame?
	local id = EventBanner.current()
	local line = Rules.boardLine(id, left())
	if not line then
		return nil
	end
	local color = rgb(Rules.color(id))
	local strip = Ui.make("Frame", {
		Name = "LiveEvent",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, strip)
	local words = label(strip, "Line", { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -20, 0, 18), Font = Theme.HeadingFont, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, Text = line })
	Ui.make("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 8 }, words)
	table.insert(strips, { label = words, holder = strip })
	return strip
end

-- ── Start ──────────────────────────────────────────────────────────────────

function EventBanner.start()
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("ZombieDeliveryHud", 30)
		if not hud or not hud:IsA("ScreenGui") then
			warn("[EventBanner] no HUD to sit in")
			return
		end
		build(hud)
		shownId = EventBanner.current() -- (an event running when you join: no sting, it is simply there)
		local p = parts
		if p and shownId then
			popIn(p)
		end
		while p and p.frame.Parent do
			local ok, err: any = pcall(tick)
			if not ok then
				warn(`[EventBanner] {err}`)
			end
			task.wait(CHECK)
		end
	end)
end

return EventBanner
