--!strict
-- 3.4: your garages and the repair shops on the client.
--
--   * The garage window (the "Garage" remote, server/Garages.luau): opened by the 🅿 GARAGE prompt at one of your
--     garages (or the depot lot's terminal). It closes when you walk away, when another window opens, with ✕ or ESC.
--     3.8 (the contract UI, design/ui-contract/): the charcoal window. On the left a cached 3D preview of the selected owned car
--     (its current model and kit when live; otherwise its stage and paint, no uploaded assets), its role, and two boxes: the cargo capacity and the free
--     garage slots. On the right every car you own as a flat row (the shown one with the red rule): the name, an ACTIVE /
--     PARKED HERE / IN ANOTHER GARAGE tag, the cargo slots and upgrades, the vehicle condition with a bar, and the
--     action: TAKE OUT VEHICLE for a car kept here (the one you drive is parked in its place), FIND REPAIR BAY for the
--     damaged one you drive (the GPS to the nearest repair shop, Map.RepairShops: a route, never a remote repair).
--     A click on a card shows that car on the left. Under the cards: where repairs happen.
--   * The GARAGE prompts and their tags are shown only at your own garages (the player attribute "Estates", set by
--     server/Estate.luau): somebody else's garage has nothing for you.
--   * The repair timer (the "Repair" remote, server/Repair.luau): a compact charcoal scrim in the HUD's top stack
--     (Hud.topSlot("repair")) while the mechanics work on your car: the car, the shop, the seconds left, the fee and
--     a bar.
-- While the window is open the mouse is free (Main: CameraRig.mouseNeeded checks GarageUi.isOpen()).
-- 5.8, the courier phone's look (design/phone-ui/): the ZDC window header with the garage glyph, the cars as slim
-- hairline rows (no corners; the shown one selected: raised, the red rule), the status as the phone's outlined caps
-- tags, the two boxes and the repairs note as flat hairline cards. TAKE OUT VEHICLE is the red primary action on the
-- car shown on the left (the one main action of the view) and the main action on the others.
-- 6.18 wave 2, the UI kit's look (the owner: "I need it unified so the phone looks like that [6.17's JOBS], and the
-- other popups too"; design/ui-kit/README.md; client/ShopView.luau draws it): the car shown is the HERO card (its 3D
-- preview or drawing over it, its name, its cargo slots big, its condition and where it is as facts, its one button:
-- TAKE OUT VEHICLE, 🔧 FIND REPAIR BAY for the damaged one you drive, grey else), beside the other cars as compact rows
-- (the picture, the name, 🔧 condition · ACTIVE / PARKED HERE / ELSEWHERE, 📦 slots big, a round TAKE for one kept
-- here; a tap shows that car in the hero). The free garage slots and the place are chips; the repairs one short line.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Hud = require(script.Parent.Hud)
local MapView = require(script.Parent.MapView)
local VehiclePreview = require(script.Parent.VehiclePreview)
local CardKit = require(script.Parent.CardKit) -- 6.18 wave 2: the UI kit
local ShopView = require(script.Parent.ShopView)
local CardLayout = require(Shared.CardLayout)

local C = Ui.Colors
local P = Theme.Postage -- 3.8: remapped to the contract values (see Theme)
local K = Theme.Contract
local GarageUi = {}

-- Set by Main: opening this window closes the HUD's windows (one window at a time).
GarageUi.onOpen = nil :: (() -> ())?

local player = Players.LocalPlayer
local WIDTH, HEIGHT = 860, 540 -- the window at scale 1 (Ui.screenScale)
local WALK_AWAY = 45 -- studs from where the window was opened (when the server sends no center / range)
local REPAIR_ACCENT = C.green -- the repair card's edge and bar (a "fixed / good" ink once Theme.Colors is remapped)

local gui: ScreenGui? = nil
local window: any = nil
local chrome: any = nil
local scale: any = nil
local refs: { [string]: any } = {}
local state: any = nil
local selected: string? = nil -- the car drawn on the left (nil: the one you drive, else the first)
local openedAt: Vector3? = nil
local running = 0 -- bumps on every open / close: the old watch loop stops
local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.get("Garage")
	end
	return remote :: RemoteEvent
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- ── Small pieces (the window is Ui.window) ──────────────────────────────────

-- ── The car drawing (garage.png's van, from frames) ────────────────────────

-- The silhouette of a car's style: the body box, the cab (the front with the windscreen and a side window), the side
-- windows in the body, the wheels (radius, centres), a pickup bed's rail; in a 300 × 150 box (x from the back, y from
-- the top; the car faces right).
type Shape = { body: { number }, cab: { number }, windows: number, wheel: number, wheels: { number }, bed: boolean? }
local SHAPES: { [string]: Shape } = {
	van = { body = { 20, 34, 200, 76 }, cab = { 216, 46, 66, 64 }, windows = 3, wheel = 19, wheels = { 64, 236 } },
	truck = { body = { 8, 20, 196, 92 }, cab = { 204, 46, 80, 66 }, windows = 0, wheel = 19, wheels = { 52, 150, 246 } },
	pickup = { body = { 24, 74, 132, 36 }, cab = { 150, 38, 120, 72 }, windows = 0, wheel = 21, wheels = { 70, 228 }, bed = true },
	low = { body = { 24, 70, 252, 38 }, cab = { 96, 42, 118, 32 }, windows = 0, wheel = 18, wheels = { 72, 226 } },
	monster = { body = { 30, 46, 120, 34 }, cab = { 146, 22, 110, 58 }, windows = 0, wheel = 32, wheels = { 76, 222 }, bed = true },
}
local WHEEL_Y = 114 -- the wheels' centres
local STYLE_SHAPE: { [string]: string } = {
	boxtruck = "truck", movingtruck = "truck", livestock = "truck", fueltruck = "truck", bus = "truck", armored = "truck",
	icecream = "truck", ambulance = "truck", pickup = "pickup", monster = "monster", muscle = "low", courier = "low",
}

local function carColor(carId: string): Color3
	local def = Economy.findCar(carId)
	local rgb = if def then def.color else nil
	return if rgb then Color3.fromRGB(rgb[1] or 200, rgb[2] or 200, rgb[3] or 200) else K.secondary
end

local function block(parent: Instance, box: { number }, color: Color3, radius: number, z: number): any
	local frame = Ui.make("Frame", {
		Position = UDim2.fromOffset(box[1], box[2]),
		Size = UDim2.fromOffset(box[3], box[4]),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	Ui.corner(frame, radius)
	return frame
end

-- Draws the car `carId` in `holder` (cleared first): a soft shadow, the body in the car's colour with a darker lower
-- band, the cab, the windows in ink, the wheels and a cream headlight.
local function drawCar(holder: Instance, car: any)
	if VehiclePreview.show(holder, car) then return end
	local carId = tostring(car.id)
	Ui.clear(holder)
	local def = Economy.findCar(carId)
	local shape = SHAPES[STYLE_SHAPE[if def then def.style else ""] or "van"]
	local paint = carColor(carId)
	local shade = paint:Lerp(K.charcoal, 0.35)
	local glass = K.charcoal:Lerp(K.line, 0.3)
	local shadow = Ui.make("Frame", { Position = UDim2.fromOffset(10, 124), Size = UDim2.fromOffset(280, 16), BackgroundColor3 = P.shadow, BackgroundTransparency = 0.75, BorderSizePixel = 0 }, holder)
	Ui.corner(shadow)
	local body = shape.body
	block(holder, body, paint, 8, 2)
	block(holder, { body[1], body[2] + body[4] * 0.62, body[3], body[4] * 0.38 }, shade, 6, 3)
	local cab = shape.cab
	block(holder, cab, paint:Lerp(K.text, 0.12), 10, 2)
	block(holder, { cab[1], cab[2] + cab[4] * 0.62, cab[3], cab[4] * 0.38 }, shade, 6, 3)
	-- The windscreen, the cab's side window, the body's windows.
	block(holder, { cab[1] + cab[3] * 0.52, cab[2] + 6, cab[3] * 0.38, cab[4] * 0.4 }, glass, 4, 4)
	block(holder, { cab[1] + 8, cab[2] + 6, cab[3] * 0.36, cab[4] * 0.4 }, glass, 4, 4)
	for index = 1, shape.windows do
		local w = (body[3] - 24) / math.max(shape.windows, 1) - 10
		block(holder, { body[1] + 12 + (index - 1) * (w + 10), body[2] + 10, w, math.min(24, body[4] * 0.3) }, glass, 3, 4)
	end
	if shape.bed then
		block(holder, { body[1] + 6, body[2] - 6, body[3] - 12, 8 }, shade, 3, 4)
	end
	-- The headlight and the wheels (a tyre, a rim).
	block(holder, { cab[1] + cab[3] - 10, cab[2] + cab[4] * 0.5, 8, 10 }, K.text, 3, 5)
	for _, x in shape.wheels do
		local r = shape.wheel
		block(holder, { x - r, WHEEL_Y - r, r * 2, r * 2 }, P.veil, r, 5)
		block(holder, { x - r * 0.45, WHEEL_Y - r * 0.45, r * 0.9, r * 0.9 }, P.line, r, 6)
	end
end

-- ── The window ─────────────────────────────────────────────────────────────

local render: () -> any

local function build()
	if gui then
		return
	end
	local made = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryGarage",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
		IgnoreGuiInset = false,
	}, player:WaitForChild("PlayerGui"))
	gui = made
	local content
	window, content, chrome = Ui.window(made, "Your garage", "", "🅿", UDim2.fromOffset(WIDTH, HEIGHT))
	window.Visible = false
	scale = window:FindFirstChildOfClass("UIScale") or Ui.make("UIScale", {}, window)
	chrome.onClose = function()
		GarageUi.close()
	end

	-- 6.18 wave 2: one scrolling body (the hero card beside the rows, client/ShopView.luau)
	local list = Ui.make("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, -36, 1, -12),
		Position = UDim2.fromOffset(20, 6),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = K.line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, content)
	Ui.list(list, true, 8)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10) }, list)
	refs.list = list
end

-- The car the window shows in its hero: the one picked, else the one you drive, else the first.
local function shownCar(cars: { any }): any
	for _, car in cars do
		if selected and tostring(car.id) == selected then
			return car
		end
	end
	for _, car in cars do
		if car.out then
			return car
		end
	end
	return cars[1]
end

-- The nearest repair shop (Map.RepairShops) to where you stand: the GPS to it (MapView's route and the HUD's beam).
local function findRepairBay()
	local here = rootPosition() or Vector3.zero
	local best: Map.RepairShop? = nil
	local bestDistance = math.huge
	for _, shop in Map.RepairShops do
		local distance = Vector3.new(shop.x - here.X, 0, shop.z - here.Z).Magnitude
		if distance < bestDistance then
			best, bestDistance = shop, distance
		end
	end
	if not best then
		Hud.toast("No repair shop on the map.")
		return
	end
	local shop = best :: Map.RepairShop
	MapView.setWaypoint(Vector3.new(shop.x, Map.RoadTop, shop.z))
	local landmark: Map.Landmark? = nil
	for _, entry in Map.Landmarks do
		if entry.id == shop.id then
			landmark = entry
		end
	end
	local ok, err = pcall(function()
		MapView.onWaypoint(landmark or {
			id = shop.id,
			name = shop.name,
			icon = "🔧",
			x = shop.x,
			z = shop.z,
			kind = "shop",
			description = "A repair shop: drive into a bay, get out and wait.",
		})
	end)
	if not ok then
		warn(`[GarageUi] GPS: {err}`)
	end
	GarageUi.close()
end

-- One car as an item of the view (see the header). `shown`: the car in the hero.
local function carItem(car: any, shown: boolean): ShopView.Item
	local id = tostring(car.id)
	local def = Economy.findCar(id)
	local health = math.clamp(tonumber(car.health) or 1, 0, 1)
	local damaged = health < 0.995
	local active = car.out == true
	local percent = math.floor(health * 100 + 0.5)
	local where = if active then "ACTIVE" elseif car.here then "PARKED HERE" else "ELSEWHERE"
	local slots = tonumber(car.capacity) or 0
	local item: ShopView.Item = {
		id = id,
		name = tostring(car.name),
		picture = ShopView.vehicle(def),
		fact = `{if health < 0.35 then "⚠ " else "🔧 "}{percent}% · {where}{if def and def.role then ` · {string.upper(def.role)}` else ""}`,
		value = `📦 {slots}`,
		valueColor = if health < 0.35 then K.red else nil,
		accent = if health < 0.35 then K.red elseif active then K.red elseif car.here then K.good else C.grey,
		owned = true,
		current = shown,
		lines = {
			`{slots} cargo {if slots == 1 then "slot" else "slots"} · {if car.company then "🚚 " else ""}{tostring(car.upgrades or "stock")}`,
			`Vehicle condition {percent}%{if damaged and not active then " · a repair shop fixes it" else ""}.`,
		},
	}
	if active and damaged then
		item.act = { text = "🔧  FIND REPAIR BAY", short = "🔧", on = true, kind = "warn", run = findRepairBay, name = "RepairBay" } -- (a GPS action)
	elseif active then
		item.act = { text = "YOU ARE DRIVING IT", on = false }
	elseif car.here then
		item.act = { text = "TAKE OUT VEHICLE", short = "TAKE", on = true, name = "TakeOut", run = function()
			getRemote():FireServer("take", id)
		end }
	else
		item.act = { text = "IN ANOTHER GARAGE", on = false, why = "Take it out at the garage that keeps it (🅿 GARAGE)." }
	end
	return item
end

render = function()
	if not window or not state then
		return
	end
	if refs.drawing then
		VehiclePreview.clear(refs.drawing)
		refs.drawing = nil
	end
	Ui.clear(refs.list)
	local cars: { any } = if type(state.cars) == "table" then state.cars else {}
	local slots = tonumber(state.slots) or 1
	local used = tonumber(state.used) or 0
	local place = tostring(state.name or "Garage")
	chrome.title.Text = if state.depot then "The depot lot" else "Your garage"
	chrome.subtitle.Text = if state.depot then `{place} · your starting van and the company vehicles` else `{place} · vehicle status and cargo capacity`
	-- The footer: the car you drive, your rank and level.
	local driving = nil
	for _, car in cars do
		if car.out then
			driving = car
		end
	end
	local level = tonumber(player:GetAttribute("Level")) or 1
	local rank = Levels.rank(level)
	chrome.context.Text = if driving
		then `<b>{string.upper(tostring(driving.name))} · {tonumber(driving.capacity) or 0} CARGO SLOTS</b> · {rank} / level {level}`
		else `{rank} / level {level}`
	-- The cars: the one you drive first, then the ones kept here, then the rest; the shown one is the hero.
	local sorted = table.clone(cars)
	local function rankOf(car: any): number
		return if car.out then 0 elseif car.here then 1 else 2
	end
	table.sort(sorted, function(a, b)
		return rankOf(a) < rankOf(b)
	end)
	local shown = shownCar(sorted)
	local byId: { [string]: any } = {}
	local items: { ShopView.Item } = {}
	for _, car in sorted do
		byId[tostring(car.id)] = car
		table.insert(items, carItem(car, car == shown))
	end
	-- Where repairs happen (Map.RepairShops), and the depot's rule.
	local shops: { string } = {}
	for _, shop in Map.RepairShops do
		table.insert(shops, shop.name)
	end
	local size = ShopView.measure(refs.list, Vector2.new(WIDTH - 40, HEIGHT - 110))
	local first = ShopView.draw(refs.list, {
		key = "garage",
		items = items,
		money = 0,
		side = CardLayout.side(size.X),
		room = size.Y,
		order = 0,
		chips = {
			{ name = "PlaceChip", text = if state.depot then "🅿 THE DEPOT LOT" else `🅿 {string.upper(place)}`, static = true },
			{ name = "SlotsChip", text = `FREE {math.max(0, slots - used)} / {slots}`, static = true, ink = if slots - used > 0 then CardKit.Color.money else K.secondary },
		},
		foot = `Repairs: {table.concat(shops, " or ")}. Park in a bay, get out and wait.{if state.depot then " The depot lot keeps your starting van and the company vehicles." else ""}`,
		empty = "No car here yet.",
		redraw = render,
		toast = Hud.toast,
		heroArt = function(card: any, item: ShopView.Item)
			local car = byId[item.id]
			if not car then
				return
			end
			local mark = card:FindFirstChild("Emoji") or card:FindFirstChild("Icon")
			if mark then
				mark:Destroy() -- (the drawing is its picture)
			end
			local holder = Ui.make("Frame", { Name = "Drawing", Size = UDim2.fromOffset(300, 150), Position = UDim2.new(0.5, 0, 0, 34), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, ZIndex = 3 }, card)
			refs.drawing = holder
			drawCar(holder, car)
		end,
		onPick = function(item: ShopView.Item)
			selected = item.id
			render()
		end,
	})
	return first
end

function GarageUi.isOpen(): boolean
	return window ~= nil and window.Visible == true
end

function GarageUi.close()
	running += 1
	if window then
		window.Visible = false
	end
	-- The model preview (a ViewportFrame with a local copy of the car) is not kept while the window is shut.
	if refs.drawing then
		VehiclePreview.clear(refs.drawing)
	end
end

-- The window's size on this screen: the design size scaled (Ui.screenScale), never wider or taller than the screen.
local function fit()
	local s = Ui.screenScale()
	local screen = Ui.screenSize()
	scale.Scale = s
	window.Size = UDim2.fromOffset(math.floor(math.min(WIDTH, (screen.X - 16) / s)), math.floor(math.min(HEIGHT, (screen.Y - 16) / s)))
end

local function open()
	build()
	local hook = GarageUi.onOpen
	if hook then
		pcall(hook)
	end
	if not window.Visible then
		selected = nil
		ShopView.home("garage") -- (6.18 review: never back on the last car's details)
	end
	fit()
	window.Visible = true
	openedAt = rootPosition()
	Ui.gamepadFocus(render()) -- 6.18 wave 2: the hero's button, else the first row
	running += 1
	local mine = running
	task.spawn(function()
		while running == mine and window.Visible do
			task.wait(0.4)
			local here = rootPosition()
			-- Out of the range where the server takes a swap (Garages.where), the window closes.
			local center = if state and typeof(state.center) == "Vector3" then state.center else openedAt
			local range = if state and type(state.range) == "number" then state.range else WALK_AWAY
			if running == mine and here and center and Vector3.new(here.X - center.X, 0, here.Z - center.Z).Magnitude > range then
				GarageUi.close()
			end
		end
	end)
end

local function onState(data: any)
	if type(data) ~= "table" then
		return
	end
	state = data
	if data.open == true then
		open()
	elseif GarageUi.isOpen() then
		render()
	end
end

-- ── Your garages' prompts ──────────────────────────────────────────────────

local prompts: { [ProximityPrompt]: string } = {}

local function owned(): { [string]: boolean }
	local list: { [string]: boolean } = {}
	local text = player:GetAttribute("Estates")
	if type(text) == "string" then
		for id in string.gmatch(text, "[^,]+") do
			list[id] = true
		end
	end
	return list
end

local function showPrompt(prompt: ProximityPrompt, mine: { [string]: boolean })
	local id = prompts[prompt]
	local on = id ~= nil and mine[id] == true
	prompt.Enabled = on
	local tagGui = prompt.Parent and prompt.Parent:FindFirstChild("GarageTag")
	if tagGui and tagGui:IsA("BillboardGui") then
		tagGui.Enabled = on
	end
end

local function watchPrompt(item: Instance)
	if not item:IsA("ProximityPrompt") or item.Name ~= "GaragePrompt" then
		return
	end
	local id = item:GetAttribute("Garage")
	if type(id) ~= "string" then
		return
	end
	prompts[item] = id
	showPrompt(item, owned())
	item.Destroying:Connect(function()
		prompts[item] = nil
	end)
end

local function refreshPrompts()
	local mine = owned()
	for prompt in prompts do
		if prompt.Parent then
			showPrompt(prompt, mine)
		end
	end
end

-- ── The repair timer ───────────────────────────────────────────────────────

local repairCard: any = nil
local repairRefs: { [string]: any } = {}
local repairToken = 0

-- 3.6: a compact paper card like the HUD's car call line: an accent edge, the words in ink, the seconds on the
-- right, a thin bar at the bottom.
local function buildRepairCard()
	if repairCard then
		return
	end
	repairCard = Ui.make("Frame", { Name = "Repair", Size = UDim2.new(0.78, 0, 0, 44), BackgroundColor3 = K.charcoal, BackgroundTransparency = K.scrim, BorderSizePixel = 0, Visible = false }, Hud.topSlot("repair"))
	Ui.edge(repairCard, REPAIR_ACCENT)
	repairRefs.text = Ui.label(repairCard, "", UDim2.new(1, -112, 0, 24), {
		Position = UDim2.fromOffset(18, 5),
		TextSize = 15,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	repairRefs.time = Ui.label(repairCard, "", UDim2.fromOffset(84, 24), {
		Position = UDim2.new(1, -96, 0, 5),
		TextSize = 15,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local back, fill = Ui.bar(repairCard, UDim2.new(1, -36, 0, 4), REPAIR_ACCENT)
	back.Position = UDim2.new(0, 18, 1, -10)
	repairRefs.fill = fill
end

local function onRepair(info: any)
	buildRepairCard()
	repairToken += 1
	if type(info) ~= "table" then
		repairCard.Visible = false
		return
	end
	local total = math.max(1, tonumber(info.total) or 1)
	local endsAt = os.clock() + (tonumber(info.seconds) or total)
	local fee = tonumber(info.fee) or 0
	repairRefs.text.Text = `🔧 Repairing your {tostring(info.car or "car")} · {tostring(info.shop or "the shop")} · {Ui.money(fee)}`
	repairCard.Visible = true
	local mine = repairToken
	task.spawn(function()
		while repairToken == mine do
			local left = math.max(0, endsAt - os.clock())
			repairRefs.time.Text = `{math.ceil(left)} s`
			repairRefs.fill.Size = UDim2.fromScale(math.clamp(1 - left / total, 0, 1), 1)
			if left <= 0 then
				break
			end
			task.wait(0.2)
		end
	end)
end

function GarageUi.start()
	build()
	getRemote().OnClientEvent:Connect(onState)
	local ok, err = pcall(function()
		Net.get("Repair").OnClientEvent:Connect(onRepair)
	end)
	if not ok then
		warn(`[GarageUi] no Repair remote: {err}`)
	end
	player:GetAttributeChangedSignal("Estates"):Connect(refreshPrompts)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if GarageUi.isOpen() then
				fit()
			end
		end)
	end
	task.spawn(function()
		local world = workspace:WaitForChild("World", 60)
		if not world then
			return
		end
		for _, item in world:GetDescendants() do
			watchPrompt(item)
		end
		world.DescendantAdded:Connect(watchPrompt)
		-- 6.13.1 (StreamingEnabled): a prompt that streams out is forgotten (one that streams back in is a new one)
		world.DescendantRemoving:Connect(function(item: Instance)
			if item:IsA("ProximityPrompt") then
				prompts[item] = nil
			end
		end)
	end)
end

return GarageUi
