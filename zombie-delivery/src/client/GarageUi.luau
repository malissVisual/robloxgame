--!strict
-- 3.4: your garages and the repair shops on the client.
--
--   * The garage window (the "Garage" remote, server/Garages.luau): opened by the 🅿 GARAGE prompt at one of your
--     garages (or the depot lot's terminal). It closes when you walk away, when another window opens, with ✕ or ESC.
--     3.8 (the contract UI, design/ui-contract/): the charcoal window. On the left a drawing of the selected car (its
--     silhouette by style, in its own colour; no new assets), its role, and two boxes: the cargo capacity and the free
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

-- A compact tag ("ACTIVE", "PARKED HERE"): a dark face, a fine outline, caps.
local function tag(parent: Instance, text: string, face: Color3, ink: Color3): any
	local label = Ui.label(parent, text, UDim2.new(0, 0, 0, 22), {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = face,
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = ink,
		TextWrapped = false,
	})
	Ui.corner(label)
	Ui.stroke(label, P.line, 1).Transparency = 0
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, label)
	return label
end

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
	return if rgb then Color3.fromRGB(rgb[1] or 200, rgb[2] or 200, rgb[3] or 200) else P.sage
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
local function drawCar(holder: Instance, carId: string)
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
	block(holder, cab, paint:Lerp(P.paper, 0.12), 10, 2)
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

local render: () -> ()

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

	-- The left side: the drawing over a fine floor line, its caption, the two boxes.
	local left = Ui.make("Frame", { Name = "Preview", Size = UDim2.new(0.47, 0, 1, 0), BackgroundColor3 = K.row, BorderSizePixel = 0 }, content)
	Ui.make("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = P.line, BorderSizePixel = 0 }, left)
	Ui.make("Frame", { Size = UDim2.new(1, -40, 0, 1), Position = UDim2.fromOffset(20, 178), BackgroundColor3 = P.line, BorderSizePixel = 0 }, left)
	refs.drawing = Ui.make("Frame", { Size = UDim2.fromOffset(300, 150), Position = UDim2.new(0.5, 0, 0, 44), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, left)
	refs.carName = Ui.label(left, "", UDim2.new(1, -40, 0, 22), {
		Position = UDim2.fromOffset(20, 204),
		Font = Theme.DisplayFont,
		TextSize = 18,
		TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.caption = Ui.caps(left, "", UDim2.new(1, -40, 0, 18), {
		Position = UDim2.fromOffset(20, 228),
		TextSize = 12,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	local boxes = Ui.make("Frame", { Size = UDim2.new(1, -40, 0, 80), Position = UDim2.new(0, 20, 1, -100), BackgroundTransparency = 1 }, left)
	for index, name in { "capacity", "slots" } do
		local box = Ui.make("Frame", {
			Size = UDim2.new(0.5, -5, 1, 0),
			Position = UDim2.new((index - 1) * 0.5, (index - 1) * 5, 0, 0),
			BackgroundColor3 = P.lavender,
			BorderSizePixel = 0,
		}, boxes)
		Ui.corner(box)
		Ui.stroke(box, P.line, 1).Transparency = 0
		Ui.caps(box, if index == 1 then "Cargo capacity" else "Free garage slots", UDim2.new(1, -24, 0, 16), {
			Position = UDim2.fromOffset(12, 14),
			TextSize = 12,
			TextColor3 = P.ink2,
		})
		refs[name] = Ui.label(box, "", UDim2.new(1, -24, 0, 30), {
			Position = UDim2.fromOffset(12, 36),
			Font = Theme.DisplayFont,
			TextSize = 22,
			TextColor3 = P.ink,
			TextWrapped = false,
		})
	end

	-- The right side: the cars as paper cards, the note under them.
	local right = Ui.make("Frame", { Name = "Cars", Size = UDim2.new(0.53, 0, 1, 0), Position = UDim2.fromScale(0.47, 0), BackgroundTransparency = 1 }, content)
	refs.listTitle = Ui.caps(right, "", UDim2.new(1, -48, 0, 16), {
		Position = UDim2.fromOffset(24, 18),
		TextSize = 12,
		TextColor3 = P.ink2,
	})
	local list = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -36, 1, -48),
		Position = UDim2.fromOffset(22, 42),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = P.ink2,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, right)
	Ui.list(list, true, 10)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, list)
	refs.list = list
end

local function healthText(share: number): (string, Color3)
	local percent = math.floor(share * 100 + 0.5)
	if share < 0.35 then
		return `⚠ {percent}% · badly damaged`, P.danger
	end
	return `{percent}%`, P.violet
end

-- The car the window shows on the left: the one picked, else the one you drive, else the first.
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

-- One car as a paper card.
local function carCard(car: any, order: number)
	local id = tostring(car.id)
	local health = math.clamp(tonumber(car.health) or 1, 0, 1)
	local damaged = health < 0.995
	local active = car.out == true
	local hasAction = car.here == true or active
	local card = Ui.make("TextButton", {
		Name = id,
		Size = UDim2.new(1, -4, 0, if hasAction and not (active and not damaged) then 168 else 124),
		BackgroundColor3 = P.ticket,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, refs.list)
	Ui.corner(card)
	local isShown = selected == id or (selected == nil and active)
	Ui.stroke(card, P.line, 1).Transparency = 0
	if isShown then
		Ui.selectRow(card, true) -- the car shown on the left: the quiet highlight and the narrow red rule
	end
	Ui.tactile(card)
	card.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		selected = id
		render()
	end)
	Ui.label(card, tostring(car.name), UDim2.new(1, -150, 0, 24), {
		Position = UDim2.fromOffset(16, 12),
		Font = Theme.DisplayFont,
		TextSize = 18,
		TextColor3 = P.ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local status = if active then tag(card, "ACTIVE", P.sage, P.ink)
		elseif car.here then tag(card, "PARKED HERE", P.sage, P.ink)
		else tag(card, "IN ANOTHER GARAGE", P.lavenderDeep, P.ink2)
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.new(1, -14, 0, 14)
	local slots = tonumber(car.capacity) or 0
	Ui.label(card, `{slots} cargo {if slots == 1 then "slot" else "slots"} · {if car.company then "🚚 " else ""}{tostring(car.upgrades or "stock")}`, UDim2.new(1, -32, 0, 18), {
		Position = UDim2.fromOffset(16, 42),
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local text, color = healthText(health)
	Ui.label(card, `Vehicle condition <b><font color="#{color:ToHex()}">{text}</font></b>{if damaged and not active then " · a repair shop fixes it" else ""}`, UDim2.new(1, -32, 0, 18), {
		Position = UDim2.fromOffset(16, 64),
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = P.ink2,
		RichText = true,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local back, fill = Ui.bar(card, UDim2.new(1, -32, 0, 5), color)
	back.Position = UDim2.fromOffset(16, 90)
	fill.Size = UDim2.fromScale(health, 1)
	-- The action.
	local button: any = nil
	if active and damaged then
		button = Ui.button(card, "🔧  FIND REPAIR BAY", UDim2.new(1, -32, 0, 44), P.violet, findRepairBay)
	elseif active then
		Ui.label(card, "You are driving it · in top shape", UDim2.new(1, -32, 0, 18), {
			Position = UDim2.fromOffset(16, 100),
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = P.ink2,
		})
	elseif car.here then
		button = Ui.button(card, "TAKE OUT VEHICLE", UDim2.new(1, -32, 0, 44), P.sage, function()
			getRemote():FireServer("take", id)
		end)
	else
		Ui.label(card, "Take it out at the garage that keeps it (🅿 GARAGE).", UDim2.new(1, -32, 0, 18), {
			Position = UDim2.fromOffset(16, 100),
			Font = Theme.Font,
			TextSize = 12,
			TextColor3 = P.ink2,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	if button then
		button.Position = UDim2.fromOffset(16, 108)
		button.TextSize = 14
		button.TextColor3 = P.ink
	end
end

render = function()
	if not window or not state then
		return
	end
	Ui.clear(refs.list)
	local cars: { any } = if type(state.cars) == "table" then state.cars else {}
	local slots = tonumber(state.slots) or 1
	local used = tonumber(state.used) or 0
	local place = tostring(state.name or "Garage")
	chrome.title.Text = if state.depot then "The depot lot" else "Your garage"
	chrome.subtitle.Text = if state.depot then `{place} · your starting van and the company vehicles` else `{place} · vehicle status and cargo capacity`
	refs.listTitle.Text = if state.depot then "YOUR VEHICLES · AT THE DEPOT LOT" else "YOUR VEHICLES · AT THIS GARAGE"
	-- The left side: the car shown.
	local shown = shownCar(cars)
	if shown then
		drawCar(refs.drawing, tostring(shown.id))
		local def = Economy.findCar(tostring(shown.id))
		refs.carName.Text = tostring(shown.name)
		refs.caption.Text = string.upper(if def and def.role then def.role else "")
		local capacity = tonumber(shown.capacity) or 0
		refs.capacity.Text = `{capacity} {if capacity == 1 then "slot" else "slots"}`
	else
		Ui.clear(refs.drawing)
		refs.carName.Text = "No car yet"
		refs.caption.Text = ""
		refs.capacity.Text = "—"
	end
	refs.slots.Text = `{math.max(0, slots - used)} / {slots}`
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
	-- The cars: the one you drive first, then the ones kept here, then the rest.
	local sorted = table.clone(cars)
	local function rankOf(car: any): number
		return if car.out then 0 elseif car.here then 1 else 2
	end
	table.sort(sorted, function(a, b)
		return rankOf(a) < rankOf(b)
	end)
	for order, car in sorted do
		carCard(car, order)
	end
	-- Where repairs happen (Map.RepairShops), and the depot's rule.
	local shops: { string } = {}
	for _, shop in Map.RepairShops do
		table.insert(shops, shop.name)
	end
	local note = Ui.make("Frame", { Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = P.tags[4], BorderSizePixel = 0, LayoutOrder = 100 }, refs.list)
	Ui.corner(note)
	Ui.padding(note, 12)
	local repairs = `Repairs take place at {table.concat(shops, " or ")}. Park in a bay, get out and let the mechanic work.`
	Ui.label(note, if state.depot then `The depot lot keeps your starting van and the company vehicles; your other cars wait in your garages. {repairs}` else repairs, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = P.ink2,
	})
end

function GarageUi.isOpen(): boolean
	return window ~= nil and window.Visible == true
end

function GarageUi.close()
	running += 1
	if window then
		window.Visible = false
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
	end
	fit()
	window.Visible = true
	openedAt = rootPosition()
	render()
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
	Ui.corner(repairCard)
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
	end)
end

return GarageUi
