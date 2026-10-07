--!strict
-- 3.7: the first-day tutorial on screen (server/Tutorial.luau decides, the words are in shared/TutorialSteps.luau).
--
--   * Marge's dialog: a charcoal panel at the lower centre, the speaker in small caps with a short red rule under it,
--     her line in white, a thin line and the actions: the red primary and a quiet second action. Space or Enter (or
--     the gamepad's A) does the primary, so does a click or a tap on the panel. While it is open those keys do nothing
--     else (no jump) and the mouse is free (CameraRig.mouseNeeded). 4.4.1: the keys go through client/DialogKeys.luau.
--   * The strip under the NEXT card (Hud.topSlot("tutorial")): FIRST DAY · +$50 ON YOUR FIRST DELIVERY and SKIP (it
--     asks first), while she waits for your first job and while it runs. 6.5: the goal card shows each step
--     (TutorialSteps.hint, shared/Goal.luau), so the strip has no line of its own.
--   * A marker over Marge (TALK TO MARGE ▼), only while her welcome waits and is not on screen.
-- 4.2, a phone: the dialog sits in the middle at a readable size (at least 0.8, as wide as the screen allows), its
-- actions a finger tall (ACTION_H); a tap anywhere on it still does the primary.
-- Everything lives in ScreenGuis that survive a respawn; the look is the contract direction (Theme.Contract) with
-- 5.8's red primary.
--
-- 6.7, a tutorial that never annoys (the owner: "It should simply show with an arrow where things are in the menu,
-- then that you take one job, and you either say yes or skip tutorial. But don't automatically give a job."):
--   1 her welcome shows on its own 2 s after PLAY (one page): SHOW ME / SKIP TUTORIAL. SHOW ME asks the server for the
--     phone ("tour") and starts the arrow tour at once.
--   2 the arrow tour of the screen (TutorialSteps.ScreenTour; client/TutorialArrow.luau draws it): the NEXT card,
--     PHONE [Q], then the phone opens on its own (the tour opens it) for JOBS, MAP, SHOP and BAG & ITEMS, it is put
--     away for the bottom bar, then the minimap. Each stop one sentence, NEXT › (Enter, the gamepad's A, a tap) and
--     SKIP TUTORIAL. Nothing stops: you can walk meanwhile. The mouse is free for the buttons (so the bottom bar, which
--     hides while the mouse is free, is let show while the arrow points at it: Hotbar.covered is wrapped). The phone
--     closed by you during its stops: on to the stop after them. A job taken meanwhile ends the tour quietly.
--   3 "ready" (one page): TAKE A JOB (the server's "board"; the phone opens on JOBS, you pick any job) / SKIP TUTORIAL.
--   4 then nothing of hers during play: the server pays the first delivery of any job (a toast); TutorialUi.isOpen()
--     is only her dialog, and the tour until it opened the phone (the phone's NEW PHONE pop-up waits for it: the
--     tour opens the phone itself).
--   SHOW ME AROUND in the phone's SETTINGS (Phone.onTour): the 5.7 world tour (the ZDC RIDE dock and the bus stop
--   nearest the depot on the GPS, then Q → JOBS), and SHOW ME THE SCREEN, this arrow tour again (no server, no
--   "ready").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local TutorialSteps = require(Shared.TutorialSteps)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Hud = require(script.Parent.Hud)
local CameraRig = require(script.Parent.CameraRig)
local MapView = require(script.Parent.MapView)
local DialogKeys = require(script.Parent.DialogKeys)
local TutorialArrow = require(script.Parent.TutorialArrow)

local TutorialUi = {}

-- The contract tokens (design/ui-contract/README.md), from Theme since 3.8.
local CONTRACT = Theme.Contract
local DIALOG_W = 540
local TOUCH = Ui.touchLayout() -- 4.2: a phone or a tablet without a keyboard
local ACTION_H = if TOUCH then 56 else 44 -- the actions' height (unscaled): 44 px or more for a finger at 0.8
local KEYS_ID = "tutorial" -- her dialog's entry in client/DialogKeys.luau
local RADIO_GUARD = 0.8 -- seconds before a key turns a page that came on its own (maybe mid-jump)
local PHONE_TRIES = 12 -- 6.7: the tour's looks (4 a second) for a phone it may open before it goes on without

local player = Players.LocalPlayer
local remote: RemoteEvent
local phase: string? = nil -- the server's phase while the tutorial runs (nil: none, or over)
local job: any = nil -- the latest Job payload
local npc: Model? = nil -- Marge

type Shown = { kind: string, dialog: TutorialSteps.Dialog, page: number, openedAt: number }
local shown: Shown? = nil

-- 6.7: the arrow tour while it runs. first: the first day's (its end asks "ready", its SKIP skips the tutorial);
-- phoneSeen: the tour has had the phone open; tries: looks for a phone to open at the stop.
type Touring = { index: number, first: boolean, phoneSeen: boolean, tries: number }
local touring: Touring? = nil

local view: any = {} -- the instances (one table: few locals)

-- ── Building ───────────────────────────────────────────────────────────────

-- A plain text action: caps, a thin red line under it on hover; at least 44 px tall for a finger.
local function textAction(parent: Instance, text: string, color: Color3, order: number, onClick: () -> ()): any
	local button = Ui.make("TextButton", {
		Size = UDim2.fromOffset(0, ACTION_H),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = text,
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = color,
		LayoutOrder = order,
	}, parent)
	local underline = Ui.make("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0.5, 10),
		BackgroundColor3 = CONTRACT.red,
		BorderSizePixel = 0,
		Visible = false,
	}, button)
	button.MouseEnter:Connect(function()
		underline.Visible = true
		button.TextColor3 = CONTRACT.text
	end)
	button.MouseLeave:Connect(function()
		underline.Visible = false
		button.TextColor3 = color
	end)
	button.Activated:Connect(function()
		local sound = Ui.onClick
		if sound then
			sound()
		end
		onClick()
	end)
	return button
end

-- 5.8: the dialog's main action, the phone's red primary (PhoneContract.primary): a red face, white caps, square,
-- ACTION_H tall; hover / press brightens the face.
local function primaryAction(parent: Instance, order: number, onClick: () -> ()): any
	local button = Ui.make("TextButton", {
		Size = UDim2.fromOffset(0, ACTION_H),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = CONTRACT.red,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = CONTRACT.text,
		LayoutOrder = order,
	}, parent)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20) }, button)
	local function lit(on: boolean)
		button.BackgroundColor3 = if on then CONTRACT.red:Lerp(CONTRACT.text, 0.1) else CONTRACT.red
	end
	button.MouseEnter:Connect(function() lit(true) end)
	button.MouseLeave:Connect(function() lit(false) end)
	button.SelectionGained:Connect(function() lit(true) end)
	button.SelectionLost:Connect(function() lit(false) end)
	button.Activated:Connect(function()
		local sound = Ui.onClick
		if sound then
			sound()
		end
		onClick()
	end)
	return button
end

local function buildDialog(advance: () -> (), second: () -> ())
	local gui = Ui.make("ScreenGui", {
		Name = "TutorialDialog",
		ResetOnSpawn = false,
		DisplayOrder = 6, -- over the HUD
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	-- The whole panel is a button: a click or a tap anywhere on it does the primary.
	local panel = Ui.make("TextButton", {
		Name = "Dialog",
		Size = UDim2.fromOffset(DIALOG_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = if TOUCH then Vector2.new(0.5, 0.5) else Vector2.new(0.5, 1),
		Position = if TOUCH then UDim2.fromScale(0.5, 0.55) else UDim2.new(0.5, 0, 1, -150),
		BackgroundColor3 = CONTRACT.charcoal,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, gui)
	view.scale = Ui.make("UIScale", {}, panel)
	local stroke = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = CONTRACT.line, Thickness = 1, Transparency = 0.6 }, panel)
	stroke.Name = "Line"
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20), PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 4) }, panel)
	Ui.list(panel, true, 8)
	panel.Activated:Connect(advance)

	view.speaker = Ui.label(panel, "", UDim2.new(1, 0, 0, 16), {
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = CONTRACT.secondary,
		TextWrapped = false,
		LayoutOrder = 1,
	})
	Ui.make("Frame", { Name = "Rule", Size = UDim2.fromOffset(28, 2), BackgroundColor3 = CONTRACT.red, BorderSizePixel = 0, LayoutOrder = 2 }, panel)
	view.line = Ui.label(panel, "", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Font,
		TextSize = 18,
		LineHeight = 1.1,
		TextColor3 = CONTRACT.text,
		LayoutOrder = 3,
	})
	Ui.make("Frame", { Name = "Sep", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = CONTRACT.line, BackgroundTransparency = 0.6, BorderSizePixel = 0, LayoutOrder = 4 }, panel)

	local footer = Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, 0, 0, ACTION_H), BackgroundTransparency = 1, LayoutOrder = 5 }, panel)
	local left = Ui.make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundTransparency = 1 }, footer)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, left)
	view.pageLabel = Ui.label(left, "", UDim2.fromOffset(0, ACTION_H), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.MonoFont,
		TextSize = 12,
		TextColor3 = CONTRACT.secondary,
		TextWrapped = false,
		LayoutOrder = 1,
	})
	view.second = textAction(left, "", CONTRACT.secondary, 2, second)
	local right = Ui.make("Frame", { Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(0.5, 0), BackgroundTransparency = 1 }, footer)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, right)
	view.primary = primaryAction(right, 1, advance) -- 5.8: the red primary
	view.keyHint = Ui.label(right, if TOUCH then "" else DialogKeys.hint(), UDim2.fromOffset(0, ACTION_H), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.MonoFont,
		TextSize = 11,
		TextColor3 = CONTRACT.secondary,
		TextWrapped = false,
		LayoutOrder = 2,
	})
	view.dialogGui = gui
end

-- 6.7: the strip under the NEXT card: FIRST DAY · the bonus, and SKIP (the goal card says what to do).
local function buildHint(onSkip: () -> ())
	local slot = Hud.topSlot("tutorial")
	slot.LayoutOrder = 2 -- right under the NEXT card (Hud's slot 1; the crew strip shows only without a job)
	local strip = Ui.make("Frame", {
		Name = "TutorialHint",
		Size = UDim2.new(1, 0, 0, if TOUCH then 44 else 30),
		BackgroundColor3 = CONTRACT.charcoal,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Visible = false,
	}, slot)
	Ui.make("Frame", { Name = "Accent", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = CONTRACT.red, BorderSizePixel = 0 }, strip)
	Ui.label(strip, string.upper(`First day · +${Config.Tutorial.Reward} on your first delivery`), UDim2.new(1, -84, 1, 0), {
		Position = UDim2.fromOffset(14, 0),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = CONTRACT.secondary,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local skip = textAction(strip, "SKIP", CONTRACT.secondary, 1, onSkip)
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -10, 0.5, 0)
	skip.Size = UDim2.fromOffset(0, if TOUCH then 44 else 28) -- 4.2: a finger's height on touch
	skip.ZIndex = 2
	view.hint = strip
end

local function buildMarker()
	local marker = Ui.make("BillboardGui", {
		Name = "TutorialMarker",
		Size = UDim2.fromOffset(150, 44),
		StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0), -- over her name tag
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	Ui.list(marker, true, 0, Enum.HorizontalAlignment.Center)
	Ui.label(marker, string.upper(`Talk to {Config.Tutorial.NpcName}`), UDim2.new(1, 0, 0, 22), {
		Name = "Text",
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = CONTRACT.text,
		TextStrokeColor3 = CONTRACT.charcoal,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		LayoutOrder = 1,
	})
	Ui.label(marker, "▼", UDim2.new(1, 0, 0, 20), {
		Font = Theme.HeadingFont,
		TextSize = 18,
		TextColor3 = CONTRACT.red,
		TextStrokeColor3 = CONTRACT.charcoal,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
	})
	view.marker = marker
end

-- ── Showing ────────────────────────────────────────────────────────────────

-- The strip and the marker for the phase right now.
local function refresh()
	if view.hint then
		local on = phase == "board" or phase == "job" or phase == "retry" -- (6.7: not over her welcome or the tour)
		if view.hint.Visible ~= on then
			view.hint.Visible = on
		end
	end
	local marker = view.marker
	if marker then
		-- 6.7: only while her welcome waits and is not on screen (it shows on its own after PLAY)
		local head = npc and (npc:FindFirstChild("Head") or npc.PrimaryPart)
		local wanted = head ~= nil and job == nil and phase == "welcome" and shown == nil and touring == nil
		marker.Adornee = if wanted then head else nil
		marker.Enabled = wanted
	end
end

-- The mouse is free while her dialog or the tour is up (CameraRig asks Main's mouseNeeded; ours is put in front).
local wrapped: (() -> boolean)? = nil
local function freeMouse()
	if CameraRig.mouseNeeded == wrapped then
		return
	end
	local previous = CameraRig.mouseNeeded
	local function needed(): boolean
		return TutorialUi.isOpen() or touring ~= nil or previous()
	end
	wrapped = needed
	CameraRig.mouseNeeded = needed
end

-- 6.7: the phone (client/Phone.luau), or nil when it did not load.
local function phoneApi(): any
	local ok, phone = pcall(function(): any
		return require(script.Parent.Phone)
	end)
	return if ok then phone else nil
end

-- 6.7: the bottom bar hides while the mouse is free (Main's Hotbar.covered): it shows while the tour points at it
-- (unless a window, the phone or a result covers the game).
local coveredWrapped: (() -> boolean)? = nil
local function showHotbar()
	local ok, Hotbar = pcall(function(): any
		return require(script.Parent.Hotbar)
	end)
	if not ok or Hotbar.covered == coveredWrapped then
		return
	end
	local previous = Hotbar.covered
	local function covered(): boolean
		local tour = touring
		local stop = if tour then TutorialSteps.ScreenTour[tour.index] else nil
		if stop and stop.target == "hotbar" then
			local phone = phoneApi()
			return CameraRig.windowOpen() or Hud.resultOpen() or (phone ~= nil and phone.isOpen())
		end
		return if previous then previous() else false
	end
	coveredWrapped = covered
	Hotbar.covered = covered
end

local function render()
	local current = shown
	if not current then
		return
	end
	local dialog = current.dialog
	local count = #dialog.pages
	local last = current.page >= count
	view.speaker.Text = dialog.speaker
	local line = dialog.pages[current.page] or ""
	view.line.Text = if TOUCH then TutorialSteps.forTouch(line) else line
	view.pageLabel.Text = if count > 1 then `{current.page} / {count}` else ""
	view.primary.Text = string.upper(if last then dialog.primary else "CONTINUE")
	local second = dialog.secondary
	view.second.Text = second or ""
	view.second.Visible = second ~= nil
	local scale = Ui.screenScale()
	if TOUCH then
		-- 4.2: readable on a phone (the HUD's 0.55 would make 10 px text), never wider than the screen.
		scale = math.min(math.max(scale, 0.8), (Ui.screenSize().X - 32) / DIALOG_W)
	end
	view.scale.Scale = scale
end

local function close()
	shown = nil
	if view.dialogGui then
		view.dialogGui.Enabled = false
	end
	DialogKeys.close(KEYS_ID)
	refresh()
end

local function show(kind: string, dialog: TutorialSteps.Dialog?)
	if not dialog or not view.dialogGui then
		return
	end
	shown = { kind = kind, dialog = dialog, page = 1, openedAt = os.clock() }
	render()
	view.dialogGui.Enabled = true
	freeMouse()
	refresh()
	-- Space / Enter / A do the primary (4.4.1: a page that comes on its own, maybe mid-jump or mid-drive, waits a
	-- little longer: a jump pressed just as she starts talking does not take her first action).
	local radio = kind == "welcome" or kind == "say" or kind == "talk" or string.sub(kind, 1, 7) == "around_"
	DialogKeys.open(KEYS_ID, TutorialUi.advance, { guard = if radio then RADIO_GUARD else 0.3, layer = 2 })
end

-- Her board: the phone's JOBS (6.7: you pick any job there), else the Dispatch board.
local function openBoard()
	local phone = phoneApi()
	if phone and phone.has() then
		phone.open("board")
		return
	end
	local open = (Hud :: any).onJobs -- (Main: DispatchUi.open)
	if type(open) == "function" then
		open()
	end
end

-- ── 6.7: the arrow tour of the screen ──────────────────────────────────────

-- A part of the HUD by its path of names (client/Hud.luau, client/Objective.luau, client/MapView.luau, Hotbar).
local function hudPart(path: { string }): GuiObject?
	local playerGui = player:FindFirstChild("PlayerGui")
	local node: Instance? = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	for _, name in path do
		node = if node then node:FindFirstChild(name) else nil
	end
	return if node and node:IsA("GuiObject") then node else nil
end

-- What a tour stop points at (TutorialSteps.ScreenTour target), by name; nil while it is not there.
local function tourTarget(name: string): GuiObject?
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end
	if name == "next" then
		return hudPart({ "TopStack", "Slot_job", "Goal" }) -- the NEXT card (client/Objective.luau)
	elseif name == "phone" then
		-- PHONE [Q] top right (Hud's row: "moreButton"); the phone's own PHONE action (touch) when that one hides
		local button = hudPart({ "HudButtons", "Row", "moreButton" })
		if button and button.Visible then
			return button
		end
		local phoneGui = playerGui:FindFirstChild("ZombieDeliveryPhone")
		local other = phoneGui and phoneGui:FindFirstChild("PhoneButton")
		return if other and other:IsA("GuiObject") then other else button
	elseif name == "hotbar" then
		return hudPart({ "BottomBar" }) -- client/Hotbar.luau
	elseif name == "minimap" then
		return hudPart({ "LeftStack", "Minimap" }) -- client/MapView.luau
	end
	-- a tile of the phone's home (client/Phone.luau: jobsApp, mapApp, shopApp, bagApp)
	local phoneGui = playerGui:FindFirstChild("ZombieDeliveryPhone")
	local body = phoneGui and phoneGui:FindFirstChild("Phone")
	local tiles = body and body:FindFirstChild("Tiles", true)
	local tile = tiles and tiles:FindFirstChild(name)
	return if tile and tile:IsA("GuiObject") then tile else nil
end

local applyStop: () -> ()

-- The tour is over (skipped: SKIP TUTORIAL on the first day's).
local function finishTour(skipped: boolean)
	local tour = touring
	touring = nil
	TutorialArrow.hide()
	refresh()
	if not tour or not tour.first then
		return
	end
	if skipped then
		remote:FireServer("skip")
	elseif phase ~= nil and job == nil then
		show("ready", TutorialSteps.dialog("ready", { reward = Config.Tutorial.Reward }))
	end
end

-- Ends the tour without a word (a job started, the tutorial ended).
local function stopTour()
	if touring then
		touring = nil
		TutorialArrow.hide()
		refresh()
	end
end

local function nextStop()
	local tour = touring
	if not tour then
		return
	end
	tour.index += 1
	tour.tries = 0
	applyStop()
end

-- The phone was put away during its stops (Q, ESC, a tile that opens a window), or it never came: on to the first
-- stop after them.
local function pastPhone()
	local tour = touring
	if not tour then
		return
	end
	local index = tour.index
	while TutorialSteps.ScreenTour[index] and TutorialSteps.ScreenTour[index].phone == "open" do
		index += 1
	end
	tour.index = index
	tour.tries = 0
	applyStop()
end

-- Shows the tour's stop (its phone opened or put away first); past the last one it is over.
applyStop = function()
	local tour = touring
	if not tour then
		return
	end
	local stops = TutorialSteps.ScreenTour
	local stop = stops[tour.index]
	if not stop then
		finishTour(false)
		return
	end
	local phone = phoneApi()
	if phone then
		if stop.phone == "open" then
			if phone.isOpen() then
				if phone.appOpen() then
					phone.back() -- (an app's popup over the tiles: back to them)
				end
			elseif tour.phoneSeen then
				pastPhone() -- (you put it away during its stops)
				return
			elseif phone.has() then
				phone.open()
			end
		elseif phone.isOpen() then
			phone.close()
		end
	end
	freeMouse()
	showHotbar()
	local last = tour.index == #stops
	TutorialArrow.show({
		find = function(): GuiObject?
			return tourTarget(stop.target)
		end,
		text = TutorialSteps.tourLine(stop, TOUCH),
		side = stop.side,
		step = tour.index,
		count = #stops,
		next = if last and not tour.first then "DONE" else "NEXT ›",
		skip = if tour.first then "SKIP TUTORIAL" else "CLOSE",
		onNext = nextStop,
		onSkip = function()
			finishTour(true)
		end,
	})
	refresh()
end

-- Four times a second while the tour runs: its phone stops (the phone it opens, or the player who put it away).
local function tourTick()
	local tour = touring
	local stop = if tour then TutorialSteps.ScreenTour[tour.index] else nil
	if not tour or not stop or stop.phone ~= "open" then
		return
	end
	local phone = phoneApi()
	if not phone then
		pastPhone()
		return
	end
	if phone.isOpen() then
		if not tour.phoneSeen then
			tour.phoneSeen = true -- (from now on the NEW PHONE pop-up finds it open and stays away)
			TutorialArrow.focus() -- (the phone put the gamepad's selection on its first tile)
		end
	elseif tour.phoneSeen or tour.tries >= PHONE_TRIES then
		pastPhone() -- (you put it away: the tour never opens it against you; or it never came)
	else
		tour.tries += 1
		if phone.has() then
			phone.open() -- (the state with the phone may come a moment after SHOW ME)
		end
	end
end

-- Starts the arrow tour (first: the first day's, after SHOW ME).
local function startTour(first: boolean)
	close()
	local tour: Touring = { index = 1, first = first, phoneSeen = false, tries = 0 }
	touring = tour
	applyStop()
	task.spawn(function()
		while touring == tour do
			local ok, err = pcall(function()
				tourTick()
			end)
			if not ok then
				warn(`[TutorialUi] tour: {err}`)
			end
			task.wait(0.25)
		end
	end)
end

-- ── 5.7: SHOW ME AROUND, the world tour ─────────────────────────────────────

-- A place on the GPS (the white route and the HUD's beam: MapView.onWaypoint, set by the Hud); nil clears it.
local function tourGps(id: string?, name: string?, x: number?, z: number?)
	local ok, err = pcall(function()
		if id and name and x and z then
			MapView.setWaypoint(Vector3.new(x, Map.RoadTop, z))
			MapView.onWaypoint({ id = id, name = name, icon = "📍", x = x, z = z, kind = "place", description = "" } :: Map.Landmark)
		else
			MapView.setWaypoint(nil)
			MapView.onWaypoint(nil)
		end
	end)
	if not ok then
		warn(`[TutorialUi] tour GPS: {err}`)
	end
end

-- Where the tour goes: the dock and the bus stop nearest the depot (shared/RentalDocks.luau, shared/BusLines.luau).
-- 6.3: the nearest dock is the spawn's rack in the depot's yard (spawn: its page names no street).
local function tourPlaces(): ({ name: string, x: number, z: number, spawn: boolean }?, { name: string, x: number, z: number }?)
	local depot = Map.Shops.depot
	local dock: { name: string, x: number, z: number, spawn: boolean }? = nil
	local stop: { name: string, x: number, z: number }? = nil
	pcall(function()
		local near = require(Shared.RentalDocks).nearest(depot.x, depot.z)
		if near then
			dock = { name = near.name, x = near.x, z = near.z, spawn = near.spawn }
		end
	end)
	pcall(function()
		local best = math.huge
		for _, candidate in require(Shared.BusLines).allStops() do
			local d = (candidate.kx - depot.x) ^ 2 + (candidate.kz - depot.z) ^ 2
			if d < best then
				best = d
				stop = { name = candidate.name, x = candidate.kx, z = candidate.kz }
			end
		end
	end)
	return dock, stop
end

-- Shows the world tour's step `index` (TutorialSteps.Tour) with its place on the GPS; past the last one it is over.
local function around(index: number)
	local step = TutorialSteps.Tour[index]
	if not step then
		return
	end
	local dock, stop = tourPlaces()
	if step == "dock" and dock then
		tourGps("tour_dock", `ZDC RIDE · {dock.name}`, dock.x, dock.z)
	elseif step == "bus" and stop then
		tourGps("tour_bus", `Bus stop · {stop.name}`, stop.x, stop.z)
	else
		tourGps(nil)
	end
	show(`around_{index}`, TutorialSteps.tourDialog(step, { dock = if dock and not dock.spawn then dock.name else nil, stop = if stop then stop.name else nil }))
end

-- ── Her dialogs' actions ───────────────────────────────────────────────────

-- What the last page's actions do.
local function finishDialog(kind: string, primary: boolean)
	if kind == "welcome" then
		if primary then
			remote:FireServer("tour") -- 6.7: SHOW ME: the phone (the server) and the arrow tour
			startTour(true)
		else
			remote:FireServer("skip")
		end
	elseif kind == "ready" then
		if primary then
			remote:FireServer("board") -- 6.7: TAKE A JOB: you pick any job; the first delivery pays her bonus
			openBoard()
		else
			remote:FireServer("skip")
		end
	elseif kind == "skip" and primary then
		remote:FireServer("skip")
	elseif kind == "talk" and primary then
		openBoard()
	elseif string.sub(kind, 1, 7) == "around_" then
		local index = tonumber(string.sub(kind, 8)) or #TutorialSteps.Tour
		if primary and index < #TutorialSteps.Tour then
			around(index + 1)
			return
		end
		tourGps(nil)
		if primary then
			openBoard() -- the last page: OPEN THE BOARD
		end
	end
end

-- Is her dialog open (6.7: or the tour, until it has opened the phone: the NEW PHONE pop-up waits for it, Main's
-- Phone.blocked; the bottom bar hides meanwhile)? Main asks it for the mouse, the bottom bar and the phone's pop-up.
function TutorialUi.isOpen(): boolean
	local tour = touring
	return shown ~= nil or (tour ~= nil and not tour.phoneSeen)
end

-- 6.7: is the arrow tour on screen?
function TutorialUi.touring(): boolean
	return touring ~= nil
end

-- 6.7, the phone's SETTINGS (Phone.onTour): "screen" the arrow tour again, "around" SHOW ME AROUND (the world tour).
function TutorialUi.tour(kind: string)
	if touring or shown then
		return
	end
	local phone = phoneApi()
	if phone and phone.isOpen() then
		phone.close()
	end
	if kind == "screen" then
		startTour(false)
	else
		around(1)
	end
end

-- The next page, or the dialog's own action on the last one.
function TutorialUi.advance()
	local current = shown
	if not current then
		return
	end
	if current.page < #current.dialog.pages then
		current.page += 1
		render()
		return
	end
	close()
	finishDialog(current.kind, true)
end

local function secondary()
	local current = shown
	if not current then
		return
	end
	close()
	finishDialog(current.kind, false)
end

local function onTutorial(newPhase: any, data: any)
	local info: { [string]: any } = if type(data) == "table" then data else {}
	if typeof(info.npc) == "Instance" and info.npc:IsA("Model") then
		npc = info.npc
	end
	if type(newPhase) ~= "string" or newPhase == "done" then
		-- Over (skipped, or 6.7: the first delivery, its toast is the server's): her tutorial dialogs and the first
		-- day's tour go, a line she said stays.
		phase = nil
		if touring and touring.first then
			stopTour()
		end
		local current = shown
		if current and current.kind ~= "say" and string.sub(current.kind, 1, 7) ~= "around_" then
			close()
		end
		refresh()
		return
	end
	if newPhase == "say" then
		show(if info.board == true then "talk" else "say", TutorialSteps.dialog("say", info))
		return
	end
	if newPhase == "phone" or newPhase == "message" then
		-- 5.0: Marge gave the phone (client/Phone.luau shows its NEW PHONE moment), or texted it (server/VanQuest.luau:
		-- a message for the phone's MESSAGES); neither is a phase of hers
		return
	end
	phase = newPhase
	if newPhase == "welcome" then
		if not touring and (shown == nil or shown.kind == "welcome") then
			show("welcome", TutorialSteps.dialog("welcome", info))
		end
	elseif newPhase == "job" then
		-- (a job taken from the board or the phone during her welcome or the tour: they go quietly)
		if touring and touring.first then
			stopTour()
		end
		local current = shown
		if current and (current.kind == "welcome" or current.kind == "ready") then
			close()
		end
	end
	refresh() -- (6.7: tour, board, retry: no page of hers)
end

function TutorialUi.start()
	remote = Net.get("Tutorial")
	buildDialog(TutorialUi.advance, secondary)
	buildHint(function()
		show("skip", TutorialSteps.dialog("skip"))
	end)
	buildMarker()
	remote.OnClientEvent:Connect(onTutorial)
	-- 6.7: the phone's SETTINGS offers the tours again (a hook: the phone does not require this module)
	local phone = phoneApi()
	if phone then
		phone.onTour = TutorialUi.tour
	end
	-- (Main connects the HUD to "Job" right after the modules start; no job is sent before PLAY, so nothing queued is
	-- taken from it.)
	Net.get("Job").OnClientEvent:Connect(function(payload)
		job = if type(payload) == "table" then payload else nil
		if phase then
			refresh()
		end
	end)
	-- Marge may have been built before this client joined (her model comes with the welcome too).
	task.defer(function()
		local folder = workspace:FindFirstChild("Npcs")
		if not npc and folder then
			for _, child in folder:GetChildren() do
				if child:IsA("Model") and child:GetAttribute("Dispatcher") == true then
					npc = child
				end
			end
		end
	end)
end

return TutorialUi
