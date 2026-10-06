--!strict
-- 5.5, the city buses on this client (server/Buses.luau, shared/BusLines.luau):
--   * The buses glide: every frame each bus near the camera is placed where the timetable puts it now
--     (BusLines.position from workspace:GetServerTimeNow(), the same function the server steps them by 10 times a
--     second), its wheels rolling with the way it moved. A rider sits welded to the seat, so the ride is smooth too.
--   * At a stop (within Config.Bus.NearStop of its kerb, on foot): a small card in the contract column (the Hud's top
--     stack, Hud.topSlot("bus"), under the contract) with the next bus of every line there: "BUS · CEDAR ST / 6TH AVE"
--     over "■ Line 1 Ring 0:12 · ■ Line 3 Suburbs 1:05". The shelters' arrivals boards nearby show the same.
--   * On board: a banner at the top, "LINE 2 · CROSS" over "Next stop: Oak St" and STOP [E] (a button to tap on a
--     touch screen): the bell (the Bus remote's "stop"; the server gets you off at that stop: "Stopping at Oak St").
--     While the bus stands at a stop: "At Oak St · leaves in 3 s" and GET OFF [E]. Jumping is off while you ride
--     (no hopping out mid-ride), the bus's own Board prompt hidden.
--   * During a foot or bike job (the Job payload's mode), on foot, with the stop farther than Config.Bus.HintDistance:
--     when BusLines.route says the bus is quicker (at your walk now: the carry walk with a piece in your hands), a
--     hint line under the contract: "🚌 Line 2 from Cedar St / 6th Ave (3 stops)".
-- (The big map does not draw the lines yet: client/MapView.luau has no overlay for other modules.)

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BusLines = require(Shared:WaitForChild("BusLines"))
local Config = require(Shared:WaitForChild("Config"))
local Map = require(Shared:WaitForChild("Map"))
local Net = require(Shared:WaitForChild("Net"))
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local Sounds = require(script.Parent.Sounds)

local BusRide = {}

local player = Players.LocalPlayer
local Tuning = Config.Bus
local RANGE = 700 -- the buses within this of the camera are placed every frame (farther: the server's steps)
local WHEEL_RANGE = 220
local POLL = 0.25 -- the cards, the banner and the hint, times a second
local BOARD_RANGE = 160 -- the shelters' arrivals boards are written within this of the camera
local BOARD_EVERY = 0.5
local STOP_ACTION = "ZombieDeliveryBusStop"
local CARRY_WALK = 8 -- the walk with a piece in the hands (client/CameraRig.luau)
local STOP_TAG = "BusStop" -- (server/BusStops.luau)

type Wheel = { motor: Motor6D, radius: number }
type Track = {
	line: BusLines.Line,
	index: number,
	offset: CFrame,
	wheels: { Wheel }?,
	spin: number,
	last: Vector3?,
}
type Ride = { model: Model, line: BusLines.Line, index: number }

local tracks: { [Model]: Track } = {}
local ride: Ride? = nil
local job: { [string]: any }? = nil
local boards: { [Model]: TextLabel } = {}
local view: { [string]: any } = {}
local started = false

local function hex(c: { number }): string
	return string.format("#%02X%02X%02X", c[1], c[2], c[3])
end

local function title(word: string): string
	return word:sub(1, 1) .. word:sub(2):lower()
end

local function ground(x: number, z: number, hx: number, hz: number): CFrame
	local at = Vector3.new(x, Map.RoadTop, z)
	if hx * hx + hz * hz < 1e-6 then
		return CFrame.new(at)
	end
	return CFrame.lookAt(at, at + Vector3.new(hx, 0, hz))
end

-- ── The buses glide ────────────────────────────────────────────────────────

local function trackOf(model: Model): Track?
	local existing = tracks[model]
	if existing then
		return existing
	end
	local lineId, index, offset = model:GetAttribute("BusLine"), model:GetAttribute("BusIndex"), model:GetAttribute("BusOffset")
	if type(lineId) ~= "number" or type(index) ~= "number" or typeof(offset) ~= "CFrame" then
		return nil
	end
	local line = BusLines.line(lineId)
	if not line then
		return nil
	end
	local track: Track = { line = line, index = index, offset = offset, wheels = nil, spin = 0, last = nil }
	tracks[model] = track
	return track
end

local function wheelsOf(chassis: BasePart): { Wheel }
	local list: { Wheel } = {}
	for _, child in chassis:GetChildren() do
		if child:IsA("Motor6D") and child.Name == "WheelMotor" then
			local radius = child:GetAttribute("Radius")
			table.insert(list, { motor = child, radius = if type(radius) == "number" then radius else 1.6 })
		end
	end
	return list
end

local function place(dt: number?)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local now = workspace:GetServerTimeNow()
	for model, track in tracks do
		local chassis = model.PrimaryPart
		if not chassis then
			continue -- (not streamed in)
		end
		if (chassis.Position - eye).Magnitude > RANGE then
			track.last = nil
			continue
		end
		local x, z, hx, hz = BusLines.position(track.line, track.index, now)
		local frame = ground(x, z, hx, hz) * track.offset
		chassis.CFrame = frame
		if dt and dt > 0 then
			local last = track.last
			track.last = frame.Position
			if last and (frame.Position - eye).Magnitude < WHEEL_RANGE then
				local wheels = track.wheels or wheelsOf(chassis)
				track.wheels = wheels
				track.spin -= (frame.Position - last):Dot(frame.LookVector)
				for _, wheel in wheels do
					if wheel.motor.Parent then
						wheel.motor.Transform = CFrame.Angles(track.spin / wheel.radius, 0, 0)
					end
				end
			end
		end
	end
end

local function watchFolder(folder: Instance)
	local function add(child: Instance)
		if child:IsA("Model") then
			if not trackOf(child) then
				-- (the attributes may come a moment later)
				child:GetAttributeChangedSignal("BusOffset"):Once(function()
					trackOf(child)
				end)
			end
		end
	end
	for _, child in folder:GetChildren() do
		add(child)
	end
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			tracks[child] = nil
		end
	end)
end

-- ── The interface ──────────────────────────────────────────────────────────

local function build()
	local touch = Ui.touchLayout()
	-- The card and the hint in the contract column, right under the contract.
	local slot = Hud.topSlot("bus")
	slot.LayoutOrder = 2
	local card = Ui.make("Frame", { Name = "BusCard", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false, LayoutOrder = 1 }, slot)
	P.scrim(card, 0.7)
	Ui.make("Frame", { Name = "Edge", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = P.ink, BorderSizePixel = 0, ZIndex = 2 }, card)
	local body = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, card)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 8) }, body)
	Ui.list(body, true, 3)
	view.cardTitle = P.caps(body, "", UDim2.new(1, 0, 0, 16), { LayoutOrder = 1, TextColor3 = P.ink })
	view.cardText = P.text(body, "", UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, RichText = true, TextWrapped = true, TextSize = 14, LayoutOrder = 2 })
	view.card = card
	local hint = Ui.make("Frame", { Name = "BusHint", Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Visible = false, LayoutOrder = 2 }, slot)
	P.scrim(hint, 0.6)
	view.hintText = P.text(hint, "", UDim2.new(1, -14, 1, 0), { Position = UDim2.fromOffset(10, 0), RichText = true, TextSize = 13, TextColor3 = P.ink })
	view.hint = hint

	-- The banner while you ride: top centre, under Roblox's top bar.
	local gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryBus",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
	}, player:WaitForChild("PlayerGui"))
	local banner = Ui.make("Frame", {
		Name = "Banner",
		Size = UDim2.fromOffset(420, 58),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
	}, gui)
	Ui.make("UIScale", { Scale = Ui.screenScale() }, banner)
	view.edge = Ui.make("Frame", { Name = "Edge", Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = P.ink, BorderSizePixel = 0 }, banner)
	view.bannerTitle = P.caps(banner, "", UDim2.new(1, -150, 0, 18), { Position = UDim2.fromOffset(16, 7), TextColor3 = P.ink2 })
	view.bannerText = P.text(banner, "", UDim2.new(1, -150, 0, 24), { Position = UDim2.fromOffset(16, 26), Font = Theme.HeadingFont, TextSize = 18 })
	view.stop = P.button(banner, "", UDim2.fromOffset(122, 40), "main", function()
		BusRide.press()
	end)
	view.stop.Position = UDim2.new(1, -10, 0.5, 0)
	view.stop.AnchorPoint = Vector2.new(1, 0.5)
	view.touch = touch
	view.banner = banner
end

local function setButton(text: string, kind: string)
	local button = view.stop
	local words = if view.touch then text else `{text}  [E]`
	if kind == "off" then
		words = text
	end
	if button.Text ~= words then
		button.Text = words
	end
	local main = kind == "main"
	button.BackgroundTransparency = if main then 0 else 0.4
	button.BackgroundColor3 = if main then P.ink else P.raised
	button.TextColor3 = if main then P.surface else P.ink2
end

-- The banner while riding.
local function updateBanner(now: number)
	local current = ride
	view.banner.Visible = current ~= nil
	if not current then
		return
	end
	local line = current.line
	local _, _, _, _, at, nextStop, leaveIn = BusLines.position(line, current.index, now)
	view.edge.BackgroundColor3 = Color3.fromRGB(line.color[1], line.color[2], line.color[3])
	view.bannerTitle.Text = `LINE {line.id} · {line.short}`
	local bell = player:GetAttribute("BusBell")
	if at > 0 then
		view.bannerText.Text = `At {line.stops[at].name} · leaves in {math.max(1, math.ceil(leaveIn))} s`
		setButton("GET OFF", "main")
	elseif type(bell) == "string" then
		view.bannerText.Text = `Stopping at {bell}`
		setButton("STOPPING", "off")
	else
		view.bannerText.Text = `Next stop: {line.stops[nextStop].name}`
		setButton("STOP", "main")
	end
end

-- The arrivals at a stop, one entry per line ("■ Line 1 Ring 0:12").
local function arrivals(stop: BusLines.Stop, now: number, rich: boolean): string
	local parts: { string } = {}
	for _, id in stop.lines do
		local line = BusLines.line(id)
		local index = if line then BusLines.indexOf(line, stop) else nil
		if line and index then
			local wait = BusLines.nextArrival(line, index, now)
			if rich then
				table.insert(parts, `<font color="{hex(line.color)}">■</font> Line {id} {title(line.short)} <b>{BusLines.clock(wait)}</b>`)
			else
				table.insert(parts, string.format("%d %-8s %s", id, line.short, BusLines.clock(wait)))
			end
		end
	end
	return table.concat(parts, if rich then "  ·  " else "\n")
end

local function rootOf(): (BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	return root, humanoid
end

-- The stop card and the job's hint (on foot only).
local function updateCards(now: number)
	local root, humanoid = rootOf()
	local onFoot = root ~= nil and humanoid ~= nil and humanoid.Health > 0 and humanoid.SeatPart == nil and ride == nil
	local stop: BusLines.Stop? = nil
	if onFoot and root then
		local near = BusLines.stopsNear(root.Position.X, root.Position.Z, Tuning.NearStop)
		if #near > 0 then
			stop = near[1].stop
		end
	end
	if stop then
		view.cardTitle.Text = `BUS · {string.upper(stop.name)}`
		view.cardText.Text = arrivals(stop, now, true)
	end
	view.card.Visible = stop ~= nil

	local hintText: string? = nil
	local current = job
	if onFoot and root and current and (current.mode == "foot" or current.mode == "bike") and typeof(current.position) == "Vector3" then
		local target: Vector3 = current.position
		local from = root.Position
		if Vector3.new(target.X - from.X, 0, target.Z - from.Z).Magnitude > Tuning.HintDistance then
			local character = player.Character
			local walk = if character and character:GetAttribute("Carrying") ~= nil then CARRY_WALK else Config.Movement.Walk
			local route = BusLines.route(from.X, from.Z, target.X, target.Z, walk)
			if route then
				hintText = `🚌 <font color="{hex(route.line.color)}">Line {route.line.id}</font> from {route.boardStop.name} ({route.stops} {if route.stops == 1 then "stop" else "stops"})`
			end
		end
	end
	if hintText then
		view.hintText.Text = hintText
	end
	view.hint.Visible = hintText ~= nil
end

-- The shelters' boards near the camera.
local function updateBoards(now: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for model, label in boards do
		if not label.Parent then
			boards[model] = nil
			continue
		end
		local id = model:GetAttribute("StopId")
		local stop = if type(id) == "number" then BusLines.allStops()[id] else nil
		local pivot = model:GetPivot().Position
		if stop and (pivot - eye).Magnitude <= BOARD_RANGE then
			label.Text = arrivals(stop, now, false)
		end
	end
end

local function addBoard(item: Instance)
	if not item:IsA("Model") then
		return
	end
	task.defer(function()
		local label = item:FindFirstChild("Arrivals", true)
		if label and label:IsA("TextLabel") then
			boards[item] = label
		end
	end)
end

-- ── Riding ─────────────────────────────────────────────────────────────────

local function busOf(seat: Instance?): Model?
	local model = seat and seat.Parent
	if model and model:IsA("Model") and model:GetAttribute("BusLine") ~= nil then
		return model
	end
	return nil
end

-- E or the button: the bell while it drives, off while it stands at a stop (the server decides).
function BusRide.press()
	local current = ride
	if not current then
		return
	end
	local _, _, _, _, at = BusLines.position(current.line, current.index, workspace:GetServerTimeNow())
	if at == 0 and player:GetAttribute("BusBell") == nil then
		Sounds.play("ding", 0.8)
	end
	Net.get("Bus"):FireServer("stop")
end

local function onStop(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not ride or UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end
	BusRide.press()
	return Enum.ContextActionResult.Sink
end

local function endRide(humanoid: Humanoid?)
	if not ride then
		return
	end
	ride = nil
	ContextActionService:UnbindAction(STOP_ACTION)
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	updateBanner(workspace:GetServerTimeNow())
end

local function onSeated(humanoid: Humanoid, active: boolean, seat: Instance?)
	local model = if active then busOf(seat) else nil
	if not model then
		endRide(humanoid)
		return
	end
	local track = trackOf(model)
	if not track then
		return
	end
	ride = { model = model, line = track.line, index = track.index }
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) -- (no hopping out mid-ride)
	ContextActionService:BindActionAtPriority(STOP_ACTION, onStop, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	updateBanner(workspace:GetServerTimeNow())
end

local function watchCharacter(character: Model)
	endRide(nil)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.Seated:Connect(function(active: boolean, seat: Instance?)
		onSeated(humanoid, active, seat)
	end)
	if humanoid.SeatPart then
		onSeated(humanoid, true, humanoid.SeatPart)
	end
end

function BusRide.start()
	if started then
		return
	end
	started = true
	build()
	Net.get("Job").OnClientEvent:Connect(function(data: any)
		job = if type(data) == "table" then data else nil
	end)
	-- Your own bus's Board prompt while you ride it: hidden (E gets you off).
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if ride and prompt:GetAttribute("BusLine") ~= nil then
			prompt.Enabled = false
		end
	end)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	for _, item in CollectionService:GetTagged(STOP_TAG) do
		addBoard(item)
	end
	CollectionService:GetInstanceAddedSignal(STOP_TAG):Connect(addBoard)
	CollectionService:GetInstanceRemovedSignal(STOP_TAG):Connect(function(item)
		if item:IsA("Model") then
			boards[item] = nil
		end
	end)
	task.spawn(function()
		local folder = workspace:WaitForChild("Buses", 60)
		if not folder then
			return -- no buses on this server
		end
		watchFolder(folder)
		RunService.RenderStepped:Connect(function(dt: number)
			place(dt)
		end)
		RunService.PreSimulation:Connect(function()
			place(nil)
		end)
	end)
	task.spawn(function()
		local boardAt = 0
		while true do
			task.wait(POLL)
			local ok, err = pcall(function()
				local now = workspace:GetServerTimeNow()
				updateBanner(now)
				updateCards(now)
				if os.clock() >= boardAt then
					boardAt = os.clock() + BOARD_EVERY
					updateBoards(now)
				end
			end)
			if not ok then
				warn(`[BusRide] {err}`)
			end
		end
	end)
end

return BusRide
