--!strict
-- 3.4: your garages and the repair shops on the client.
--
--   * The garage window (the "Garage" remote, server/Garages.luau): opened by the 🅿 GARAGE prompt at one of your
--     garages (or the depot lot's terminal). Every car you own: its name, the cargo slots (📦), the health (🔧 %),
--     the upgrades, and TAKE OUT for the cars kept here (the one you drive is parked in its place). It closes when you
--     walk away, when another window opens, or with ✕.
--   * The GARAGE prompts and their tags are shown only at your own garages (the player attribute "Estates", set by
--     server/Estate.luau): somebody else's garage has nothing for you.
--   * The repair timer (the "Repair" remote, server/Repair.luau): a card in the HUD's top stack (Hud.topSlot) while
--     the mechanics work on your car: the car, the shop, the seconds left, the fee and a bar.
-- While the window is open the mouse is free (Main: CameraRig.mouseNeeded checks GarageUi.isOpen()).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Hud = require(script.Parent.Hud)

local C = Ui.Colors
local GarageUi = {}

-- Set by Main: opening this window closes the HUD's windows (one window at a time).
GarageUi.onOpen = nil :: (() -> ())?

local player = Players.LocalPlayer
local WIDTH, HEIGHT = 560, 440
local WALK_AWAY = 45 -- studs from where the window was opened
local REPAIR_COLOR = Color3.fromRGB(170, 218, 137)

local gui: ScreenGui? = nil
local window: any = nil
local scale: any = nil
local refs: { [string]: any } = {}
local state: any = nil
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

-- ── The window ─────────────────────────────────────────────────────────────

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
	window = Ui.panel(made, UDim2.fromOffset(WIDTH, HEIGHT), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	window.Visible = false
	window.BackgroundTransparency = 0.04
	scale = Ui.make("UIScale", {}, window)
	local rule = Ui.make("Frame", { Size = UDim2.new(1, -16, 0, 3), Position = UDim2.fromOffset(8, 0), BackgroundColor3 = C.yellow, BorderSizePixel = 0 }, window)
	Ui.corner(rule, 2)
	refs.title = Ui.label(window, "🅿  GARAGE", UDim2.new(1, -80, 0, 36), {
		Position = UDim2.fromOffset(18, 10),
		TextSize = 24,
		Font = Theme.DisplayFont,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.subtitle = Ui.label(window, "", UDim2.new(1, -36, 0, 34), {
		Position = UDim2.fromOffset(20, 46),
		TextSize = 13,
		Font = Theme.Font,
		TextColor3 = C.dim,
	})
	Ui.closeButton(window, function()
		GarageUi.close()
	end)
	local list = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -28, 1, -96),
		Position = UDim2.fromOffset(14, 86),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, window)
	Ui.list(list, true, 8)
	refs.list = list
end

local function healthColor(share: number): Color3
	return if share >= 0.75 then C.green elseif share >= 0.35 then C.yellow else C.red
end

local function render()
	if not window or not state then
		return
	end
	Ui.clear(refs.list)
	refs.title.Text = `🅿  {string.upper(tostring(state.name or "GARAGE"))}`
	local slots = tonumber(state.slots) or 1
	local used = tonumber(state.used) or 0
	refs.subtitle.Text = if state.depot
		then `The depot lot keeps your starting van (and the company vehicles). Your other cars wait in your garages. Slots: {used} / {slots}.`
		else `Your cars: {used} / {slots} garage slots. TAKE OUT puts a car at the door; the one you drive is parked here.`
	for order, car in (if type(state.cars) == "table" then state.cars else {}) do
		local row = Ui.make("Frame", {
			Size = UDim2.new(1, -8, 0, 70),
			BackgroundColor3 = if car.out then C.panelLight:Lerp(C.yellow, 0.1) else C.panelLight,
			BorderSizePixel = 0,
			LayoutOrder = order,
		}, refs.list)
		Ui.corner(row, 8)
		if car.out then
			Ui.edge(row, C.yellow)
		end
		local health = math.clamp(tonumber(car.health) or 1, 0, 1)
		Ui.label(row, tostring(car.name), UDim2.new(1, -170, 0, 24), {
			Position = UDim2.fromOffset(16, 6),
			TextSize = 17,
			Font = Theme.DisplayFont,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		Ui.label(row, `📦 {tonumber(car.capacity) or 0} slots   ·   🔧 {math.floor(health * 100 + 0.5)} %{if health < 0.995 then " (a repair shop fixes it)" else ""}`, UDim2.new(1, -170, 0, 18), {
			Position = UDim2.fromOffset(16, 30),
			TextSize = 13,
			Font = Theme.Font,
			TextColor3 = healthColor(health),
		})
		Ui.label(row, `{if car.company then "🚚" else "⚙"} {tostring(car.upgrades or "stock")}`, UDim2.new(1, -170, 0, 16), {
			Position = UDim2.fromOffset(16, 49),
			TextSize = 12,
			Font = Theme.Font,
			TextColor3 = C.dim,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local id = tostring(car.id)
		local button: any
		if car.out then
			button = Ui.ghostButton(row, "DRIVING", UDim2.fromOffset(140, 42), nil, function() end)
			button.TextColor3 = C.dim
		elseif car.here then
			button = Ui.button(row, "TAKE OUT", UDim2.fromOffset(140, 42), C.green, function()
				getRemote():FireServer("take", id)
			end)
		else
			button = Ui.ghostButton(row, "IN A GARAGE", UDim2.fromOffset(140, 42), nil, function()
				Hud.toast("This car waits in your garages: take it out at one of them (🅿 GARAGE).")
			end)
			button.TextColor3 = C.dim
		end
		button.TextSize = 15
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -12, 0.5, 0)
	end
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

local function open()
	build()
	local hook = GarageUi.onOpen
	if hook then
		pcall(hook)
	end
	scale.Scale = Ui.screenScale()
	window.Visible = true
	openedAt = rootPosition()
	render()
	running += 1
	local mine = running
	task.spawn(function()
		while running == mine and window.Visible do
			task.wait(0.4)
			local here = rootPosition()
			if running == mine and here and openedAt and Vector3.new(here.X - openedAt.X, 0, here.Z - openedAt.Z).Magnitude > WALK_AWAY then
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
	local tag = prompt.Parent and prompt.Parent:FindFirstChild("GarageTag")
	if tag and tag:IsA("BillboardGui") then
		tag.Enabled = on
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

local function buildRepairCard()
	if repairCard then
		return
	end
	repairCard = Ui.panel(Hud.topSlot("repair"), UDim2.new(0.78, 0, 0, 44), UDim2.new(), nil)
	repairCard.Name = "Repair"
	repairCard.Visible = false
	Ui.stroke(repairCard, REPAIR_COLOR, 1.5)
	Ui.edge(repairCard, REPAIR_COLOR)
	repairRefs.text = Ui.label(repairCard, "", UDim2.new(1, -120, 0, 24), {
		Position = UDim2.fromOffset(18, 5),
		TextSize = 15,
		Font = Theme.HeadingFont,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	repairRefs.time = Ui.label(repairCard, "", UDim2.fromOffset(96, 24), {
		Position = UDim2.new(1, -108, 0, 5),
		TextSize = 15,
		Font = Theme.DisplayFont,
		TextColor3 = REPAIR_COLOR,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local back, fill = Ui.bar(repairCard, UDim2.new(1, -32, 0, 4), REPAIR_COLOR)
	back.Position = UDim2.new(0, 16, 1, -10)
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
