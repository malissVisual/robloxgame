--!strict
-- 5.5, the city buses on this client (server/Buses.luau, shared/BusLines.luau):
--   * The buses glide: every frame each bus near the camera is placed where the timetable puts it now
--     (BusLines.position from workspace:GetServerTimeNow(), the same function the server steps them by 10 times a
--     second), its wheels rolling with the way it moved. A rider sits welded to the seat, so the ride is smooth too.
--     5.9.2: every frame within NEAR_RANGE, MID_EVERY seconds apart out to RANGE, the farther ones left to the server;
--     the timetable worked out once per bus and frame (the doors read it again).
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
--   * 5.7, getting on and off like into a car (Config.Interact; the routes and poses: shared/InteractPose.luau,
--     client/Interact.luau): the front-right door folds open (two leaves turning in on their outer edges) while the bus
--     stands at a stop and shuts BusDoorShut before it leaves (kept open while somebody is still on its step). Board:
--     the server keeps your seat and marks you (BusBoard / BusBoardAt: server/Buses.luau); your client walks you to
--     the kerb by the door, up its step, along the aisle and turns you onto your seat (in the bus's own space, so a
--     bus pulling away carries the move along) in BusBoard, the server seats you then. Off at a stop (BusOff /
--     BusOffAt / BusOffTo): up from the seat, along the aisle to the door and down its step onto the kerb, in
--     BusAlight. Your controls are off meanwhile; everybody's walks near the camera are posed from the same attributes.
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
local InteractPose = require(Shared:WaitForChild("InteractPose"))
local Map = require(Shared:WaitForChild("Map"))
local Net = require(Shared:WaitForChild("Net"))
local Drive = require(script.Parent.Drive)
local Interact = require(script.Parent.Interact)
local Bodies = require(script.Parent.Bodies)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local Sounds = require(script.Parent.Sounds)

local BusRide = {}

local player = Players.LocalPlayer
local Tuning = Config.Bus
local RANGE = 700 -- the buses within this of the camera are placed here (farther: the server's steps)
local NEAR_RANGE = 250 -- 5.9.2: … every frame within this, else MID_EVERY seconds apart
local MID_EVERY = 1 / 12
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
	due: number, -- 5.9.2: os.clock() of its next placing out of NEAR_RANGE
	when: number, -- the server time its timetable was worked out last (at, leaveIn then)
	at: number,
	leaveIn: number,
}
type Ride = { model: Model, line: BusLines.Line, index: number }

local tracks: { [Model]: Track } = {}
local ride: Ride? = nil
local hiddenPrompts: { ProximityPrompt } = {} -- your bus's Board prompts hidden while you ride it (given back after)
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
	local track: Track = { line = line, index = index, offset = offset, wheels = nil, spin = 0, last = nil, due = 0, when = -1, at = 0, leaveIn = 0 }
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

local function place(dt: number?, now: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local clock = os.clock()
	for model, track in tracks do
		local chassis = model.PrimaryPart
		if not chassis then
			continue -- (not streamed in)
		end
		local distance = (chassis.Position - eye).Magnitude
		if distance > RANGE then
			track.last = nil
			continue
		end
		if distance > NEAR_RANGE then
			-- 5.9.2: the middle distance, MID_EVERY seconds apart
			if clock < track.due then
				continue
			end
			track.due = clock + MID_EVERY
		end
		local x, z, hx, hz, at, _, leaveIn = BusLines.position(track.line, track.index, now)
		track.when, track.at, track.leaveIn = now, at, leaveIn
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
			-- (StreamingEnabled: the board part streamed out; look again when it is back, keep the model)
			local again = if model.Parent then model:FindFirstChild("Arrivals", true) else nil
			if again and again:IsA("TextLabel") then
				boards[model] = again
				label = again
			else
				if not model.Parent then
					boards[model] = nil
				end
				continue
			end
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
	task.spawn(function()
		local label = item:FindFirstChild("Arrivals", true) or item:WaitForChild("ArrivalsBoard", 30)
		if label and not label:IsA("TextLabel") then
			label = label:FindFirstChild("Arrivals", true)
		end
		if label and label:IsA("TextLabel") and item.Parent then
			boards[item] = label
		end
	end)
end

-- ── 5.7: the folding door ─────────────────────────────────────────────────

local DOOR_RANGE = 220 -- the doors of the buses within this of the camera move
local DOOR_FOLD = math.rad(82) -- each leaf turns in this far, open

type Door = {
	panel: BasePart, -- the real door (hidden here while it is open)
	trims: { BasePart },
	centre: Vector3, -- chassis space
	size: Vector3,
	leaves: { Part }?, -- the two local leaves while it is open
	open: number, -- 0 shut … 1 open
}
local doors: { [Model]: Door | false } = {}
local heldOpen: { [Model]: boolean } = {} -- somebody gets on or off it now (the poll fills it)

-- The bus's folding door: its CarDoor panel on the right (+X) side and the trims welded to it.
local function doorOf(model: Model, chassis: BasePart): Door?
	local known = doors[model]
	if known ~= nil then
		return if known then known :: Door else nil
	end
	local panel: BasePart? = nil
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name == "CarDoor" and chassis.CFrame:PointToObjectSpace(child.Position).X > 0 then
			panel = child
			break
		end
	end
	if not panel then
		doors[model] = false
		return nil
	end
	local trims: { BasePart } = {}
	for _, child in model:GetChildren() do
		local weld = if child:IsA("BasePart") and child.Name == "DoorTrim" then child:FindFirstChildOfClass("WeldConstraint") else nil
		if weld and (weld.Part0 == panel or weld.Part1 == panel) then
			table.insert(trims, child :: BasePart)
		end
	end
	local door: Door = {
		panel = panel,
		trims = trims,
		centre = chassis.CFrame:PointToObjectSpace(panel.Position),
		size = panel.Size,
		leaves = nil,
		open = 0,
	}
	doors[model] = door
	return door
end

local function showPanel(door: Door, shown: boolean)
	local modifier = if shown then 0 else 1
	door.panel.LocalTransparencyModifier = modifier
	for _, trim in door.trims do
		trim.LocalTransparencyModifier = modifier
	end
end

local function shut(door: Door)
	door.open = 0
	local leaves = door.leaves
	if leaves then
		for _, leaf in leaves do
			leaf:Destroy()
		end
		door.leaves = nil
	end
	showPanel(door, true)
end

-- Every door near the camera toward its goal: open while the bus stands at a stop (until BusDoorShut before it
-- leaves) or somebody is on its step.
local function updateDoors(dt: number, now: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local tuning = Config.Interact
	for model, track in tracks do
		local chassis = model.PrimaryPart
		local door = if chassis then doorOf(model, chassis) else nil
		if not chassis or not door then
			continue
		end
		if (chassis.Position - eye).Magnitude > DOOR_RANGE then
			if door.open > 0 then
				shut(door :: Door)
			end
			continue
		end
		-- (5.9.2: the timetable as place worked it out this frame)
		local at, leaveIn = track.at, track.leaveIn
		if track.when ~= now then
			local _, _, _, _, a, _, l = BusLines.position(track.line, track.index, now)
			at, leaveIn = a, l
		end
		local goal = if (at > 0 and leaveIn > tuning.BusDoorShut) or heldOpen[model] then 1 else 0
		local open = if goal > door.open then math.min(1, door.open + dt / tuning.BusDoor) else math.max(0, door.open - dt / tuning.BusDoor)
		if open <= 0 then
			if door.open > 0 or door.leaves then
				shut(door :: Door)
			end
			continue
		end
		door.open = open
		local leaves = door.leaves
		if not leaves then
			local made: { Part } = {}
			for n = 1, 2 do
				local leaf = Instance.new("Part")
				leaf.Name = "BusDoorLeaf"
				leaf.Anchored = true
				leaf.CanCollide = false
				leaf.CanQuery = false
				leaf.CanTouch = false
				leaf.CastShadow = false
				leaf.Color = door.panel.Color
				leaf.Material = door.panel.Material
				leaf.Size = Vector3.new(door.size.X, door.size.Y, door.size.Z / 2 - 0.04)
				leaf.Parent = workspace.CurrentCamera or workspace
				made[n] = leaf
			end
			leaves = made
			door.leaves = made
			showPanel(door, false)
		end
		-- each leaf on its outer edge (the front one on the door's front, the back one on its back), turning in
		local angle = DOOR_FOLD * InteractPose.ease(open)
		local c, quarter = door.centre, door.size.Z / 4
		local frame = chassis.CFrame
		local list = leaves :: { Part }
		list[1].CFrame = frame * CFrame.new(c.X, c.Y, c.Z - door.size.Z / 2) * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, quarter)
		list[2].CFrame = frame * CFrame.new(c.X, c.Y, c.Z + door.size.Z / 2) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -quarter)
	end
	for model, door in doors do
		if not model.Parent then
			if door then
				shut(door :: Door)
			end
			doors[model] = nil
		end
	end
end

-- ── 5.7: getting on and off ────────────────────────────────────────────────

local MOVE_HOLD = 1.2 -- after the walk in, waiting this long for the seat
local MOVE_MIN = 0.3 -- a late start plays quicker, never quicker than this
local MOVE_RANGE = 160 -- the others' walks are posed within this of the camera
local AISLE_WALK = 9 -- studs / s along the aisle (the route is then fitted to its time)
local OWNER = "bus" -- (client/Interact.luau)

type Move = {
	kind: string, -- "board" | "alight"
	model: Model,
	chassis: BasePart,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	route: InteractPose.Route,
	world: boolean, -- the route in the world's space (getting off), else the bus's
	value: number, -- the BusBoardAt / BusOffAt it plays
	started: number, -- os.clock()
	span: number, -- seconds it plays over here
}

local move: Move? = nil
local played: { [string]: number } = {} -- the last BusBoardAt / BusOffAt played here (the server clears them later)
local lastSeat: { [Model]: BasePart } = {} -- the bus seat each character sat in last (for the walk off)
type Seen = { value: number, route: InteractPose.Route, total: number }
local seenMoves: { [Model]: Seen } = {}

local function busByKey(line: number, index: number): Model?
	for model, track in tracks do
		if track.line.id == line and track.index == index and model.Parent then
			return model
		end
	end
	return nil
end

local function seatOf(model: Model, seatNo: number): BasePart?
	for _, child in model:GetChildren() do
		if child:IsA("Seat") and child:GetAttribute("Index") == seatNo then
			return child
		end
	end
	return nil
end

-- A point of a route in the bus's space, facing (fx, fz) there.
local function pointAt(kind: string, position: Vector3, fx: number, fz: number, seconds: number, arc: number?): InteractPose.Point
	return InteractPose.point(position.X, position.Y, position.Z, kind, seconds, fx, fz, arc)
end

local function walkTime(a: Vector3, b: Vector3): number
	return math.max(0.12, (b - a).Magnitude / AISLE_WALK)
end

-- The places of a walk in or out, in the bus's space: the kerb by the door, inside its step, the aisle by the door, the
-- aisle at the seat's row and the seated root. lift: the root over the feet.
local function places(model: Model, chassis: BasePart, seat: BasePart, lift: number): (Vector3, Vector3, Vector3, Vector3, CFrame)
	local half = BusLines.HalfWidth
	local doorZ = -BusLines.DoorAhead
	local inside = chassis.Size.Y / 2 + lift -- (the floor is the chassis' top)
	local frame = chassis.CFrame
	local kerbWorld = frame * Vector3.new(half + 1.3, 0, doorZ)
	local ground = Interact.groundY(kerbWorld.X, frame.Position.Y + 2, kerbWorld.Z, { model })
	local kerbY = if ground then frame:PointToObjectSpace(Vector3.new(kerbWorld.X, ground + lift, kerbWorld.Z)).Y else inside - 1.2
	local seated = frame:ToObjectSpace(seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + Config.Cargo.BoardSitLift, 0))
	local seatZ = seated.Position.Z
	return Vector3.new(half + 1.3, kerbY, doorZ), Vector3.new(half - 0.9, inside, doorZ), Vector3.new(0, inside, doorZ + 0.6), Vector3.new(0, inside, seatZ), seated
end

-- The walk in (the bus's space) from `start`: to the kerb by the door, up the step, along the aisle, a turn to the
-- seat, sit. Fitted to Config.Interact.BusBoard.
local function boardRoute(model: Model, chassis: BasePart, seat: BasePart, start: CFrame, lift: number): InteractPose.Route
	local kerb, step, front, row, seated = places(model, chassis, seat, lift)
	local p0 = start.Position
	local look = start.LookVector
	local side = if seated.Position.X >= 0 then 1 else -1
	local seatLook = seated.LookVector
	local points = {
		pointAt("walk", p0, look.X, look.Z, 0),
		pointAt("walk", kerb, kerb.X - p0.X, kerb.Z - p0.Z, math.max(0.2, (Vector3.new(kerb.X, 0, kerb.Z) - Vector3.new(p0.X, 0, p0.Z)).Magnitude / Config.Movement.Walk)),
		pointAt("step", step, -1, 0, 0.4, 0.5),
		pointAt("walk", front, front.X - step.X, front.Z - step.Z, walkTime(step, front)),
		pointAt("walk", row, 0, 1, walkTime(front, row)),
		pointAt("turn", row, side, 0, 0.25),
		pointAt("sit", seated.Position, seatLook.X, seatLook.Z, 0.5),
	}
	return InteractPose.fit(InteractPose.route(points), Config.Interact.BusBoard)
end

-- The walk off (the world's space, from the bus where it stands now) from `start`: up from the seat into the aisle,
-- along it to the door, down the step onto the kerb at `kerb` (the server's spot). Fitted to BusAlight.
local function alightRoute(model: Model, chassis: BasePart, seat: BasePart, start: CFrame, kerb: Vector3, lift: number): InteractPose.Route
	local _, step, front, row, seated = places(model, chassis, seat, lift)
	local frame = chassis.CFrame
	local side = if seated.Position.X >= 0 then 1 else -1
	local function world(v: Vector3): Vector3
		return frame * v
	end
	local function way(x: number, z: number): (number, number)
		local v = frame:VectorToWorldSpace(Vector3.new(x, 0, z))
		return v.X, v.Z
	end
	local ground = Interact.groundY(kerb.X, kerb.Y, kerb.Z, { model })
	local landing = Vector3.new(kerb.X, if ground then ground + lift else kerb.Y, kerb.Z)
	local p0 = start.Position
	local look = start.LookVector
	local rowW, frontW, stepW = world(row), world(front), world(step)
	local ax, az = way(-side, 0)
	local fx, fz = way(0, -1)
	local dx, dz = way(1, 0)
	local points = {
		pointAt("walk", p0, look.X, look.Z, 0),
		pointAt("stand", rowW, ax, az, 0.5),
		pointAt("walk", frontW, fx, fz, walkTime(row, front)),
		pointAt("walk", stepW, dx, dz, walkTime(front, step)),
		pointAt("step", landing, landing.X - stepW.X, landing.Z - stepW.Z, 0.45, 0.3),
	}
	return InteractPose.fit(InteractPose.route(points), Config.Interact.BusAlight)
end

-- A walk's pose t seconds in (the stride fading in and out at its ends).
local function movePose(route: InteractPose.Route, t: number): InteractPose.Pose
	local _, _, _, _, _, kind, u, dist = InteractPose.sample(route, t)
	if kind == "walk" then
		return InteractPose.walk(dist, math.clamp(t / 0.15, 0, 1) * math.clamp((route.total - t) / 0.2, 0, 1))
	end
	return InteractPose.forKind(kind, u, dist)
end

local function stopMove()
	local m = move
	move = nil
	if not m then
		return
	end
	played[m.kind] = m.value
	Interact.release(m.character, OWNER)
	Interact.freeze(nil, false)
	Drive.setBoarding(nil, false)
	if m.root.Parent then
		m.root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function startMove(kind: string, model: Model, seat: BasePart, character: Model, humanoid: Humanoid, root: BasePart, value: number, kerb: Vector3?)
	local chassis = model.PrimaryPart
	if not chassis then
		return
	end
	local lift = Interact.standHeight(humanoid, root)
	local route = if kind == "board" then boardRoute(model, chassis, seat, chassis.CFrame:ToObjectSpace(root.CFrame), lift)
		else alightRoute(model, chassis, seat, root.CFrame, kerb or (chassis.CFrame * Vector3.new(BusLines.HalfWidth + 2, 0, -BusLines.DoorAhead)), lift)
	local late = workspace:GetServerTimeNow() - value
	move = {
		kind = kind,
		model = model,
		chassis = chassis,
		character = character,
		humanoid = humanoid,
		root = root,
		route = route,
		world = kind ~= "board",
		value = value,
		started = os.clock(),
		span = math.max(MOVE_MIN, route.total - math.max(0, late)),
	}
	Interact.freeze(humanoid, true)
	Drive.setBoarding(model, false) -- (no aiming, the walk left alone; the view stays the walk's)
end

-- Your own walk on or off this frame.
local function moveStep(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	local m = move
	if m and (m.character ~= character or not humanoid or not root or humanoid.Health <= 0 or not m.chassis.Parent) then
		stopMove()
		m = nil
	end
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local seat = humanoid.SeatPart
	if seat and seat.Parent and seat.Parent:IsA("Model") and seat.Parent:GetAttribute("BusLine") ~= nil then
		lastSeat[character] = seat
	end
	local now = workspace:GetServerTimeNow()
	local tuning = Config.Interact
	if not m and seat == nil then
		local boardAt = character:GetAttribute("BusBoardAt")
		local offAt = character:GetAttribute("BusOffAt")
		if type(boardAt) == "number" and boardAt ~= played.board and now - boardAt < tuning.BusBoard then
			local line, index, seatNo = string.match(tostring(character:GetAttribute("BusBoard")), "^(%d+):(%d+):(%d+)$")
			local model = if line and index then busByKey(tonumber(line) :: number, tonumber(index) :: number) else nil
			local target = if model and seatNo then seatOf(model, tonumber(seatNo) :: number) else nil
			if model and target then
				startMove("board", model, target, character, humanoid, root, boardAt)
			else
				played.board = boardAt -- (the bus is not streamed in here: the server seats you anyway)
			end
		elseif type(offAt) == "number" and offAt ~= played.alight and now - offAt < tuning.BusAlight then
			local line, index = string.match(tostring(character:GetAttribute("BusOff")), "^(%d+):(%d+)$")
			local model = if line and index then busByKey(tonumber(line) :: number, tonumber(index) :: number) else nil
			local from = lastSeat[character]
			local kerb = character:GetAttribute("BusOffTo")
			if model and from and from.Parent == model then
				startMove("alight", model, from, character, humanoid, root, offAt, if typeof(kerb) == "Vector3" then kerb else nil)
			else
				played.alight = offAt
			end
		end
		m = move
	end
	if not m then
		return
	end
	local since = os.clock() - m.started
	if m.kind == "board" then
		if seat then
			stopMove() -- seated: the seat holds you now
			return
		elseif since >= m.span + MOVE_HOLD then
			stopMove() -- no seat came (the server puts you on the kerb)
			return
		end
	elseif seat then
		stopMove()
		return
	end
	local t = m.route.total * math.clamp(since / m.span, 0, 1)
	local x, y, z, fx, fz = InteractPose.sample(m.route, t)
	local frame = Interact.frame(x, y, z, fx, fz)
	Interact.place(root, if m.world then frame else m.chassis.CFrame * frame, dt)
	Interact.pose(character, movePose(m.route, t), dt, OWNER)
	if m.kind == "alight" and since >= m.span then
		stopMove()
	end
end

-- Everybody else's walks on and off near the camera: the pose from their attributes (their own clients move them).
local function othersStep(dt: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local now = workspace:GetServerTimeNow()
	local tuning = Config.Interact
	local live: { [Model]: boolean } = {}
	for _, other in Bodies.players() do
		local character = other.Character
		if other == player or not character then
			continue
		end
		-- (5.9.2: the far ones skipped first, the body's parts looked up once)
		local humanoid, root = Bodies.near(character, eye, MOVE_RANGE)
		if not humanoid or not root then
			continue
		end
		local seat = humanoid.SeatPart
		if seat and seat.Parent and seat.Parent:IsA("Model") and seat.Parent:GetAttribute("BusLine") ~= nil then
			lastSeat[character] = seat
			continue
		end
		local boardAt = character:GetAttribute("BusBoardAt")
		local offAt = character:GetAttribute("BusOffAt")
		local value: number? = nil
		local route: InteractPose.Route? = nil
		local seen = seenMoves[character]
		if type(boardAt) == "number" and now - boardAt < tuning.BusBoard then
			value = boardAt
			if not seen or seen.value ~= boardAt then
				local line, index, seatNo = string.match(tostring(character:GetAttribute("BusBoard")), "^(%d+):(%d+):(%d+)$")
				local model = if line and index then busByKey(tonumber(line) :: number, tonumber(index) :: number) else nil
				local target = if model and seatNo then seatOf(model, tonumber(seatNo) :: number) else nil
				local chassis = model and model.PrimaryPart
				if model and target and chassis then
					local kerb = chassis.CFrame:ToObjectSpace(CFrame.new(root.Position))
					route = boardRoute(model, chassis, target, kerb, 3)
				end
			end
		elseif type(offAt) == "number" and now - offAt < tuning.BusAlight then
			value = offAt
			if not seen or seen.value ~= offAt then
				local line, index = string.match(tostring(character:GetAttribute("BusOff")), "^(%d+):(%d+)$")
				local model = if line and index then busByKey(tonumber(line) :: number, tonumber(index) :: number) else nil
				local from = lastSeat[character]
				local kerb = character:GetAttribute("BusOffTo")
				local chassis = model and model.PrimaryPart
				if model and from and from.Parent == model and chassis and typeof(kerb) == "Vector3" then
					route = alightRoute(model, chassis, from, root.CFrame, kerb, 3)
				end
			end
		end
		if value and route then
			seenMoves[character] = { value = value, route = route, total = route.total }
			seen = seenMoves[character]
		end
		if value and seen and seen.value == value then
			live[character] = true
			Interact.pose(character, movePose(seen.route, math.clamp(now - value, 0, seen.total)), dt, OWNER)
		end
	end
	for character in seenMoves do
		if not live[character] then
			seenMoves[character] = nil
			Interact.release(character, OWNER)
		end
	end
	for character in lastSeat do
		if not character.Parent then
			lastSeat[character] = nil
		end
	end
end

-- The buses somebody gets on or off now (their doors stay open), from everybody's attributes (the poll).
local function updateHeld()
	table.clear(heldOpen)
	local now = workspace:GetServerTimeNow()
	local tuning = Config.Interact
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if not character then
			continue
		end
		local boardAt, offAt = character:GetAttribute("BusBoardAt"), character:GetAttribute("BusOffAt")
		local key: string? = nil
		if type(boardAt) == "number" and now - boardAt < tuning.BusBoard then
			key = tostring(character:GetAttribute("BusBoard"))
		elseif type(offAt) == "number" and now - offAt < tuning.BusAlight then
			key = tostring(character:GetAttribute("BusOff"))
		end
		local line, index = nil, nil
		if key then
			line, index = string.match(key, "^(%d+):(%d+)")
		end
		local model = if line and index then busByKey(tonumber(line) :: number, tonumber(index) :: number) else nil
		if model then
			heldOpen[model] = true
		end
	end
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
	-- The Board prompts hidden while riding come back (the server sets Enabled only when a dwell starts or ends).
	for _, prompt in hiddenPrompts do
		local bus = prompt:FindFirstAncestorOfClass("Model")
		while bus and bus:GetAttribute("BusLine") == nil and bus.Parent and bus.Parent:IsA("Model") do
			bus = bus.Parent :: Model
		end
		if prompt.Parent then
			prompt.Enabled = bus ~= nil and bus:GetAttribute("BusAt") ~= nil
		end
	end
	table.clear(hiddenPrompts)
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
		local riding = ride
		if riding and prompt:GetAttribute("BusLine") ~= nil and prompt:IsDescendantOf(riding.model) then
			prompt.Enabled = false
			table.insert(hiddenPrompts, prompt)
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
	-- 5.7: the walks on and off, before the physics step (what is set here is what is simulated and sent)
	RunService.PreSimulation:Connect(function(dt: number)
		moveStep(dt)
		othersStep(dt)
	end)
	task.spawn(function()
		local folder = workspace:WaitForChild("Buses", 60)
		if not folder then
			return -- no buses on this server
		end
		watchFolder(folder)
		RunService.RenderStepped:Connect(function(dt: number)
			local now = workspace:GetServerTimeNow()
			place(dt, now) -- (once a frame: the buses are anchored and never collide)
			updateDoors(dt, now) -- 5.7: the folding doors (after the buses moved)
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
				updateHeld()
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
