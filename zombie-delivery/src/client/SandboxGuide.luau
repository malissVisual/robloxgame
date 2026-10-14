--!strict
-- 8.0 SANDBOX, the guide (design/sandbox/KONTRAKT.md; the owner: "a player new to it must always know what to do next,
-- without a long tutorial"): a light pointer to the next goal, never a tutorial window.
--   * The hint line: one thin charcoal line at the top in the middle (a ZDC-orange edge, the words, a small ✕). It sits
--     under what holds the top's middle (client/TopBlocks.luau: the move's panel, Danny's strip, the planning's pill),
--     keeps clear of the top's sides (the money at the top left, client/SandboxHud.luau's ScreenGui "SandboxHud" when it
--     is there, Config.SandboxGuide.SideClear at least; on a computer Roblox's player list at the top right while it
--     reaches down to the line) and is itself a top block ("SandboxGuide"), so the quick chat's
--     lines and the banners go under it. Its words wrap rather than grow wide; on a touch screen it is at least
--     TouchScale big and its ✕ a finger's size.
--   * The 3D guide: a soft glowing path on the ground (Beams between Attachments in the Terrain: no parts) along the
--     roads (SandboxSteps.route: out to Depot Row, along Main Street, in), a floating orange chevron over the target and
--     its distance tag ("THE ALPINE LODGE · 420 m"). Inside the house only the hint (no target there).
--   * The steps come from shared/SandboxSteps.luau (pure, tested) on a state read from what the client sees: the player
--     attribute Plot (server/SandboxPlots.luau); the Moving remote's "state" (as client/MovingHud.luau reads it: a move
--     runs, `inside` the house, the van's load counts.out, counts.delivered, your piece in your hands: an item `mine` and
--     "carried"); the MoveLobby remote's "lobby" (the planning: LAUNCH); the Collection remote's "state" (the stock, the
--     pieces on show and their stands); where you stand and whether you sit in a vehicle.
--   * Each step goes quiet once done (per session: SandboxSteps.doneBy); the arrow to the house and home stays while you
--     drive. Hold G (not while you carry: G puts a piece down) or the ✕ hides the guide ("Guide off" for a moment); hold G
--     again, or on a touch screen the 💡 chip left in its place, brings it back. SandboxGuide.setEnabled for a settings row.
--   * Cheap: one loop every Config.SandboxGuide.Every seconds (no frame-by-frame work, no tables made in it: the state,
--     the path's points and the instances are made once and reused; a string only when the words or the metres change).
-- Everything waits for Config.Sandbox.On (client/Main.client.luau starts it in the sandbox).
--   SandboxGuide.start()            builds it and starts the loop (once; nothing outside the sandbox)
--   SandboxGuide.setEnabled(on)     shows or hides the guide (the G hold, the ✕, a settings row)
--   SandboxGuide.enabled()          is it on?
--   SandboxGuide.step()             the step now (its id, SandboxSteps.Steps), nil before the first look
--   SandboxGuide.hint()             the hint line (a top block), for the layout checks
-- Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SandboxMap = require(Shared.SandboxMap)
local SandboxSteps = require(Shared.SandboxSteps)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local TopBlocks = require(script.Parent.TopBlocks)
local MoveLayout = require(script.Parent.MoveLayout) -- (Roblox's player list's width on a computer)

local SandboxGuide = {}

local G = Config.SandboxGuide
local K = Theme.Contract
local player = Players.LocalPlayer
local COLOR = Color3.fromRGB(G.Color[1], G.Color[2], G.Color[3])
local ABOVE = { "MovePanel", "MoveHelper", "PlanningPill" } -- the top's middle blocks the line goes under (TopBlocks)
local SIDE_GUIS = { "SandboxHud", "SandboxTasksChip" } -- the HUD at the top's sides the line keeps clear of (client/SandboxHud.luau; 8.2: client/SandboxTasksUi.luau's chip)
local MAX_POINTS = 6 -- SandboxSteps.route's most points: a path of five beams
local PAD_L, PAD_R, PAD_V = 14, 4, 5 -- the line's padding (at scale 1)
local LINE_H = G.TextSize + 4 -- one line of words
local CLOSE_W = 28 -- the ✕'s column (at scale 1; a finger's size on a touch screen)
local MIN_ROOM = 220 -- px at scale 1: narrower than this beside the sides' HUD, the line goes under it
local LABELS: { [string]: string } = {
	board = "CONTRACTS",
	curb = string.upper(SandboxMap.House.name),
	door = "FRONT DOOR",
	van = "YOUR VAN",
	unload = "UNLOAD HERE",
	stand = "EMPTY STAND",
	warehouse = "WAREHOUSE",
}

local started = false
local on = true -- the guide shown (the G hold, the ✕)
local offUntil = 0 -- os.clock(): the "Guide off" line shows until then
local done: { [string]: boolean } = {} -- the steps done this session
local last: SandboxSteps.Last = {} -- the counts of the look before (SandboxSteps.doneBy)
local state: SandboxSteps.State = {
	plot = nil,
	move = false,
	inside = false,
	carrying = false,
	vanLoad = 0,
	delivered = 0,
	atHouse = false,
	seated = false,
	planning = false,
	planningMine = false,
	stock = 0,
	shown = 0,
	freeStands = nil,
}
local move: any = nil -- the Moving remote's last "state" (nil: no move)
local mine = true -- the move is yours (else a crew's: its owner's van and drop-off)
local summary = SandboxSteps.collection(nil) -- the Collection remote's last "state"
local current: SandboxSteps.Step? = nil
local seen = 0 -- s the current info step has shown
local gDownAt: number? = nil -- os.clock() G went down (a hold that may hide the guide)
local gUsed = false -- (this hold already toggled)
local path: { number } = table.create(MAX_POINTS * 2, 0) -- the path's x, z pairs (reused)
local ui: any = {} -- the hint line's instances and what it shows
local world: any = {} -- the 3D guide's instances and what it shows
local standSpots: { [number]: { [number]: SandboxSteps.Place } } = {} -- a plot's display stands (found once)

-- ── What the client sees ───────────────────────────────────────────────────

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function seated(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

-- The Moving remote's state: what the steps read from it (once a message, not every look).
local function readMove(view: any)
	move = if type(view) == "table" then view else nil
	local carrying, inVan, delivered = false, 0, 0
	if move then
		local counts = if type(move.counts) == "table" then move.counts else {}
		inVan = tonumber(counts.out) or 0
		delivered = tonumber(counts.delivered) or 0
		if type(move.items) == "table" then
			for _, item in move.items do
				if type(item) == "table" and item.mine == true and item.state == "carried" then
					carrying = true
				end
			end
		end
		mine = move.mine ~= false
	end
	state.move = move ~= nil
	state.inside = move ~= nil and move.inside == true
	state.carrying = carrying
	state.vanLoad = inVan
	state.delivered = delivered
end

-- shared/WarehouseLayout.luau (the warehouse's, written alongside: required only when it is there).
local function warehouseLayout(): any
	local module = Shared:FindFirstChild("WarehouseLayout")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, layout = pcall(require, module :: ModuleScript)
	return if ok and type(layout) == "table" then layout else nil
end

-- A stand's place in whatever shape the layout gives it (a spot { x, y, z }, a Vector3, a CFrame, a table holding one),
-- in the world (the plot's own coordinates or the warehouse's middle's taken in).
local function placeOf(value: any, plot: SandboxMap.Plot, depth: number): SandboxSteps.Place?
	local x, y, z
	if typeof(value) == "Vector3" then
		x, y, z = value.X, value.Y, value.Z
	elseif typeof(value) == "CFrame" then
		x, y, z = value.Position.X, value.Position.Y, value.Position.Z
	elseif type(value) == "table" then
		if type(value.x) == "number" and type(value.z) == "number" then
			x, y, z = value.x, tonumber(value.y) or 0, value.z
		elseif depth < 2 then
			return placeOf(value.spot or value.at or value.cframe or value.position or value.pos or value.cf, plot, depth + 1)
		end
	end
	if x == nil or z == nil then
		return nil
	end
	local r = plot.rect
	if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
		return { x = x, y = y or 0, z = z }
	end
	local w = plot.warehouse
	local wx, wz = w.x + x, w.z + z -- (relative to the warehouse's middle)
	if wx >= r.x0 and wx <= r.x1 and wz >= r.z0 and wz <= r.z1 then
		return { x = wx, y = (y or 0) + w.y, z = wz }
	end
	return nil
end

-- A plot's display stands (index = the stand's number, Collection.display's `stand`), found once.
local function standsOf(plotId: number): { [number]: SandboxSteps.Place }
	local known = standSpots[plotId]
	if known then
		return known
	end
	local list: { [number]: SandboxSteps.Place } = {}
	local plot = SandboxMap.Plots[plotId]
	local layout = warehouseLayout()
	if plot and layout then
		local raw: any = nil
		for _, name in { "stands", "standSpots", "Stands", "spots" } do
			local field = layout[name]
			if type(field) == "function" then
				local ok, got = pcall(field, plotId)
				if not (ok and type(got) == "table") then
					ok, got = pcall(field, plot)
				end
				raw = if ok and type(got) == "table" then got else nil
			elseif type(field) == "table" then
				raw = field
			end
			if raw then
				break
			end
		end
		if type(raw) == "table" then
			for index, value in raw do
				local place = if type(index) == "number" then placeOf(value, plot, 0) else nil
				if place then
					list[index] = place
				end
			end
		end
	end
	standSpots[plotId] = list
	return list
end

-- The display stands a warehouse has (Config.Warehouse.Stands, else the layout's count; nil: not known).
local function standCount(): number?
	local warehouse = (Config :: any).Warehouse
	if type(warehouse) == "table" and type(warehouse.Stands) == "number" then
		return warehouse.Stands
	end
	local plot = player:GetAttribute("Plot")
	local count = if type(plot) == "number" then #standsOf(plot) else 0
	return if count > 0 then count else nil
end

-- The van the move fills (yours, or on a crew the owner's: the player attribute MoveWith): looked up at most once a
-- second, kept while it stays.
local function van(): Model?
	local owner = if move and not mine and type(player:GetAttribute("MoveWith")) == "number" then player:GetAttribute("MoveWith") else player.UserId
	local known = world.van
	if known and known.Parent and known:GetAttribute("OwnerId") == owner then
		return known
	end
	world.van = nil
	local now = os.clock()
	if now < (world.vanLookAt or 0) then
		return nil
	end
	world.vanLookAt = now + 1
	local cars = workspace:FindFirstChild("Cars")
	if cars then
		for _, car in cars:GetChildren() do
			if car:IsA("Model") and car:GetAttribute("OwnerId") == owner then
				world.van = car
				return car
			end
		end
	end
	return nil
end

-- The van's back (its CargoDoor attachment, server/Vehicles.luau; else behind the chassis).
local function vanBack(): Vector3?
	local model = van()
	local chassis = model and model.PrimaryPart
	if not chassis then
		return nil
	end
	local door = chassis:FindFirstChild("CargoDoor")
	if door and door:IsA("Attachment") then
		return door.WorldPosition
	end
	return (chassis.CFrame * CFrame.new(0, 0, chassis.Size.Z / 2 + 2)).Position
end

-- Where the step's target is and its tag's name (nil: nothing to point at now).
local function targetOf(kind: string?, px: number, pz: number): (Vector3?, string?)
	if kind == nil then
		return nil, nil
	end
	local plotId = state.plot
	local plot = if plotId then SandboxMap.Plots[plotId] else nil
	local house = SandboxMap.House
	if kind == "board" then
		if plot then
			return Vector3.new(plot.board.x, plot.board.y + 4, plot.board.z), LABELS.board
		end
	elseif kind == "curb" then
		return Vector3.new(house.curb.x, house.curb.y, house.curb.z), LABELS.curb
	elseif kind == "door" then
		return Vector3.new(house.door.x, house.door.y + 3, house.door.z), LABELS.door
	elseif kind == "van" then
		local back = vanBack()
		if back then
			return back, LABELS.van
		end
	elseif kind == "unload" then
		local drop = move and move.dropOff
		if plot and mine then
			return Vector3.new(plot.unload.x, SandboxMap.RoadTop, plot.unload.z), LABELS.unload
		elseif type(drop) == "table" and type(drop.x) == "number" and type(drop.z) == "number" then
			return Vector3.new(drop.x, SandboxMap.RoadTop, drop.z), LABELS.unload
		end
	elseif kind == "stand" then
		if plotId and plot then
			local spots = standsOf(plotId)
			local owned = world.ownedStands -- (8.1: only the stands this warehouse has bought: never a locked one)
			if type(owned) == "number" and owned < #spots then
				local some = world.someSpots -- (8.2 perf: one table, refilled: a look makes none)
				table.clear(some)
				for i = 1, owned do
					some[i] = spots[i]
				end
				spots = some
			end
			local index = SandboxSteps.nearestFree(px, pz, spots, summary.taken)
			local spot = if index then spots[index] else nil
			if spot then
				return Vector3.new(spot.x, spot.y + 3, spot.z), LABELS.stand
			end
			return Vector3.new(plot.door.x, plot.door.y + 4, plot.door.z), LABELS.warehouse
		end
	end
	return nil, nil
end

-- ── The hint line ──────────────────────────────────────────────────────────

local function fadeTo(visible: boolean)
	local holder = ui.holder
	if not holder then
		return
	end
	for _, tween in ui.tweens or {} do
		tween:Cancel()
	end
	if visible then
		holder.Visible = true
	end
	local info = TweenInfo.new(G.Fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local gone = if visible then 0 else 1
	ui.tweens = {
		TweenService:Create(ui.pill, info, { BackgroundTransparency = if visible then Theme.PanelTransparency else 1 }),
		TweenService:Create(ui.edge, info, { BackgroundTransparency = gone }),
		TweenService:Create(ui.words, info, { TextTransparency = gone }),
		TweenService:Create(ui.close, info, { TextTransparency = if visible then 0.25 else 1 }),
	}
	if not visible then
		ui.tweens[1].Completed:Connect(function(playback: Enum.PlaybackState)
			if playback ~= Enum.PlaybackState.Cancelled and not ui.shown then
				holder.Visible = false -- (gone from the top's blocks too)
			end
		end)
	end
	for _, tween in ui.tweens do
		tween:Play()
	end
end

-- The rects of the top's sides' HUD (the money …): their direct pieces, a level deeper for a piece as wide as the
-- screen. Returns the left side's right edge, the right side's left edge and their bottom (px in `origin`'s space).
local function sides(origin: Vector2, W: number, band: number): (number, number, number)
	local left, right, bottom = 0, W, 0
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local function visit(object: Instance, depth: number)
		if not object:IsA("GuiObject") or not object.Visible then
			return
		end
		local p, s = object.AbsolutePosition, object.AbsoluteSize
		local x0, y0 = p.X - origin.X, p.Y - origin.Y
		if s.X < 1 or s.Y < 1 or y0 > band then
			return
		end
		if s.X > W / 2 then
			if depth < 1 then
				for _, child in object:GetChildren() do
					visit(child, depth + 1)
				end
			end
			return
		end
		if x0 + s.X / 2 < W / 2 then
			left = math.max(left, x0 + s.X)
		else
			right = math.min(right, x0)
		end
		bottom = math.max(bottom, y0 + s.Y)
	end
	for _, name in SIDE_GUIS do
		local gui = playerGui and playerGui:FindFirstChild(name)
		if gui and gui:IsA("ScreenGui") and gui.Enabled then
			for _, child in gui:GetChildren() do
				visit(child, 0)
			end
		end
	end
	return left, right, bottom
end

-- The lowest edge of the top's middle blocks that show (px in `origin`'s space; G.Top when none): the line goes under.
local function under(origin: Vector2, S: number): number
	local top = G.Top
	for _, name in ABOVE do
		local block = TopBlocks.get(name)
		if block and block.Visible and block.AbsoluteSize.Y >= 1 then
			local holderGui = block:FindFirstAncestorWhichIsA("ScreenGui")
			if holderGui == nil or holderGui.Enabled ~= false then
				top = math.max(top, block.AbsolutePosition.Y - origin.Y + block.AbsoluteSize.Y + G.Gap * S)
			end
		end
	end
	return top
end

-- Where the line goes and how big it is, for its words now: under the top's middle blocks, clear of its sides.
local function layout()
	local holder, root = ui.holder, ui.root
	if not holder or not root then
		return
	end
	local size = Ui.screenSize()
	local W, H = size.X, size.Y
	local S = Ui.screenScale()
	local touch = Ui.touchLayout()
	local hs = if touch then math.max(S, G.TouchScale) else S
	local origin = root.AbsolutePosition
	local top = under(origin, S)
	ui.under = top
	-- the room between the top's sides (each side's HUD, at least SideClear)
	local gap = G.Gap * S
	local left, right, sideBottom = sides(origin, W, top + 40 * hs)
	if not touch then -- (Roblox's player list at the top right of a computer, when it is on and reaches down here)
		local listOn = true
		pcall(function()
			listOn = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
		end)
		if listOn and top < math.min(H * 0.45, 52 + 40 * #Players:GetPlayers()) then
			right = math.min(right, W - 16 - MoveLayout.PLAYER_LIST_W)
		end
	end
	local half = math.min(W / 2 - math.max(left + gap, G.SideClear * S), math.min(right - gap, W - G.SideClear * S) - W / 2)
	local room = 2 * half
	if room < MIN_ROOM * hs then -- (a narrow screen: under the sides' HUD, nearly as wide as the screen)
		top = math.max(top, sideBottom + gap)
		local _, _, below = sides(origin, W, top + 40 * hs) -- (8.2 review: and under what stands there too, the TASKS chip)
		top = math.max(top, below + gap)
		room = W - 32
	end
	room = math.min(room, G.HintWidth * hs)
	local closeW = if touch then math.max(CLOSE_W, Ui.MinTouch / hs) else CLOSE_W
	local closeShown = ui.closeShown ~= false
	local right0 = if closeShown then closeW else PAD_R + 8
	local inner = math.max(40, room / hs - PAD_L - right0)
	local textW = TextService:GetTextSize(ui.text or "", G.TextSize, Theme.Font, Vector2.new(100000, 1000)).X
	local lines = math.clamp(math.ceil(textW / inner - 0.001), 1, 3)
	local w = if lines == 1 then textW + PAD_L + right0 + 2 else inner + PAD_L + right0
	local h = lines * LINE_H + PAD_V * 2
	-- on a touch screen the ✕ is a finger tall: it may stand out over and under the line, never onto what is above
	local hit = if touch and closeShown then math.max(h, Ui.MinTouch / hs) else h
	local y = top + (hit - h) / 2 * hs
	holder.Size = UDim2.fromOffset(math.ceil(w), h)
	holder.Position = UDim2.new(0.5, 0, 0, y)
	ui.scale.Scale = hs
	ui.words.Size = UDim2.new(1, -(PAD_L + right0), 1, 0)
	ui.close.Size = UDim2.fromOffset(closeW, hit)
	ui.close.Visible = closeShown
	local chip = ui.chip
	if chip then
		chip.Position = UDim2.new(0.5, 0, 0, top)
	end
	ui.laidAt = os.clock()
end

local function setHint(visible: boolean, text: string, closeShown: boolean)
	if visible and (text ~= ui.text or closeShown ~= ui.closeShown or not ui.shown) then
		ui.text = text
		ui.closeShown = closeShown
		ui.words.Text = text
		layout() -- (coming back: where it goes now)
	end
	if visible ~= (ui.shown == true) then
		ui.shown = visible
		fadeTo(visible)
	end
end

local function build()
	local playerGui = player:WaitForChild("PlayerGui")
	local root = Ui.make("ScreenGui", {
		Name = "SandboxGuide",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 6, -- (under the move's cards, client/MovingHud.luau's 7)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	ui.root = root
	local holder = Ui.make("Frame", {
		Name = "SandboxHint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, G.Top),
		Size = UDim2.fromOffset(240, LINE_H + PAD_V * 2),
		BackgroundTransparency = 1,
		Visible = false,
	}, root)
	ui.holder = holder
	ui.scale = Ui.make("UIScale", { Name = "Scale", Scale = 1 }, holder)
	local pill = Ui.make("Frame", {
		Name = "Pill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, holder)
	Ui.corner(pill, 8)
	ui.pill = pill
	ui.edge = Ui.make("Frame", {
		Name = "Edge",
		Size = UDim2.new(0, 3, 1, -8),
		Position = UDim2.fromOffset(5, 4),
		BackgroundColor3 = COLOR,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, pill)
	ui.words = Ui.label(pill, "", UDim2.new(1, -(PAD_L + CLOSE_W), 1, 0), {
		Name = "Words",
		Position = UDim2.fromOffset(PAD_L, 0),
		Font = Theme.Font,
		TextSize = G.TextSize,
		TextColor3 = K.text,
		TextTransparency = 1,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	local close = Ui.make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(CLOSE_W, LINE_H + PAD_V * 2),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "✕",
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.secondary,
		TextTransparency = 1,
	}, holder)
	close.Activated:Connect(function()
		SandboxGuide.setEnabled(false)
	end)
	ui.close = close
	-- a touch screen has no G to hold: the guide hidden leaves a small 💡 that brings it back
	local chip = Ui.make("TextButton", {
		Name = "GuideOn",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, G.Top),
		Size = UDim2.fromOffset(Ui.MinTouch, Ui.MinTouch),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "💡",
		TextSize = 20,
		Visible = false,
	}, root)
	Ui.corner(chip, 22)
	chip.Activated:Connect(function()
		SandboxGuide.setEnabled(true)
	end)
	ui.chip = chip
	TopBlocks.set("SandboxGuide", holder)
	TopBlocks.onChanged(function()
		if ui.shown then
			layout()
		end
	end)
end

-- ── The 3D guide ───────────────────────────────────────────────────────────

local function bar(parent: Instance, color: Color3, w: number, h: number, x: number, y: number, rotation: number, z: number)
	Ui.make("Frame", {
		Size = UDim2.fromOffset(w, h),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Rotation = rotation,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
end

local function buildWorld()
	local terrain = workspace.Terrain
	local folder = Instance.new("Folder")
	folder.Name = "SandboxGuide"
	folder.Parent = workspace
	world.folder = folder
	world.points = {}
	world.pointAt = {} -- (8.2 perf: where each point is: only a point that moved is written, the beams redrawn)
	world.beams = {}
	world.someSpots = {} -- (the bought stands' spots, refilled by targetOf)
	for i = 1, MAX_POINTS do
		world.points[i] = Ui.make("Attachment", { Name = `SandboxGuidePoint{i}` }, terrain)
	end
	local alpha = NumberSequence.new(G.PathAlpha)
	for i = 1, MAX_POINTS - 1 do
		world.beams[i] = Ui.make("Beam", {
			Name = `Path{i}`,
			Attachment0 = world.points[i],
			Attachment1 = world.points[i + 1],
			FaceCamera = true,
			Segments = 1,
			Width0 = G.PathWidth,
			Width1 = G.PathWidth,
			LightEmission = 1,
			LightInfluence = 0,
			Color = ColorSequence.new(COLOR),
			Transparency = alpha,
			Enabled = false,
		}, folder)
	end
	world.target = Ui.make("Attachment", { Name = "SandboxGuideTarget" }, terrain)
	local marker = Ui.make("BillboardGui", {
		Name = "SandboxGuideMarker",
		Adornee = world.target,
		Size = UDim2.fromOffset(220, 78),
		StudsOffsetWorldSpace = Vector3.new(0, G.ChevronHeight, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 100000,
		ResetOnSpawn = false,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	world.marker = marker
	-- the chevron (pointing down, a charcoal outline under the orange), bobbing
	local chevron = Ui.make("Frame", {
		Name = "Chevron",
		Size = UDim2.fromOffset(44, 30),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundTransparency = 1,
	}, marker)
	for layer = 1, 2 do
		local grow = if layer == 1 then 4 else 0
		local color = if layer == 1 then K.charcoal else COLOR
		bar(chevron, color, 26 + grow, 9 + grow, 13, 13, 40, layer)
		bar(chevron, color, 26 + grow, 9 + grow, 31, 13, -40, layer)
	end
	world.bob = TweenService:Create(chevron, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Position = UDim2.new(0.5, 0, 0, 8),
	})
	local tag = Ui.make("Frame", {
		Name = "Tag",
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, marker)
	Ui.corner(tag, 6)
	Ui.make("UIStroke", { Color = COLOR, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tag)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, tag)
	world.tag = Ui.label(tag, "", UDim2.fromOffset(0, 26), {
		Name = "Distance",
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = K.text,
		TextWrapped = false,
	})
	world.pathOn = 0 -- the beams lit now
end

local function hideWorld()
	if world.marker and world.marker.Enabled then
		world.marker.Enabled = false
		world.bob:Pause()
	end
	for i = 1, world.pathOn or 0 do
		world.beams[i].Enabled = false
	end
	world.pathOn = 0
end

-- The chevron over `at` with its tag, the path from the player (px, pz) to it along the roads.
local function showWorld(at: Vector3, label: string, px: number, pz: number)
	if at ~= world.targetAt then -- (8.2 perf: the marker moved only when its target did)
		world.targetAt = at
		world.target.WorldPosition = at
	end
	local marker = world.marker
	if not marker.Enabled then
		marker.Enabled = true
		world.bob:Play()
	end
	local dx, dz = at.X - px, at.Z - pz
	local metres = math.floor(math.sqrt(dx * dx + dz * dz) + 0.5)
	if label ~= world.tagLabel or metres ~= world.tagMetres then
		world.tagLabel, world.tagMetres = label, metres
		world.tag.Text = `{label} · {metres} m`
	end
	local count = 0
	if metres > G.Near then
		count = SandboxSteps.route(px, pz, at.X, at.Z, path, G.Direct)
	end
	local y = SandboxMap.RoadTop + G.PathLift
	for i = 1, count do
		local point = Vector3.new(path[i * 2 - 1], y, path[i * 2])
		if point ~= world.pointAt[i] then
			world.pointAt[i] = point
			world.points[i].WorldPosition = point
		end
	end
	local lit = math.max(0, count - 1)
	for i = 1, MAX_POINTS - 1 do
		local beam = world.beams[i]
		local want = i <= lit
		if beam.Enabled ~= want then
			beam.Enabled = want
		end
	end
	world.pathOn = lit
end

-- ── The loop ───────────────────────────────────────────────────────────────

local function look()
	local root = rootPart()
	local px, pz = 0, 0
	if root then
		local at = root.Position
		px, pz = at.X, at.Z
	end
	local plot = player:GetAttribute("Plot")
	state.plot = if type(plot) == "number" then plot else nil
	state.atHouse = root ~= nil and SandboxSteps.atHouse(px, pz, G.HouseMargin)
	state.seated = seated()
	state.stock, state.shown, state.freeStands = summary.stock, summary.shown, summary.free
	if summary.free == nil and summary.stock > 0 then
		local count = standCount()
		state.freeStands = if count then math.max(0, count - summary.shown) else nil
	end
	SandboxSteps.doneBy(state, done, last)
	local step = SandboxSteps.decide(state)
	if step ~= current then
		current = step
		seen = 0
	end
	local hint, guide = SandboxSteps.visible(step, done, state.seated)
	if hint and on and step.info then
		seen += G.Every
		if seen >= G.InfoSeconds then
			done[step.id] = true -- (said long enough)
			hint, guide = SandboxSteps.visible(step, done, state.seated)
		end
	end
	-- a held G: the guide off or on (once a hold)
	if gDownAt and not gUsed and os.clock() - gDownAt >= G.HideHold then
		gUsed = true
		SandboxGuide.setEnabled(not on)
		return
	end
	local touch = Ui.touchLayout()
	if not on then
		local note = os.clock() < offUntil
		setHint(note, if touch then "Guide off · tap 💡 to bring it back" else "Guide off · hold G to bring it back", false)
		ui.chip.Visible = touch and not note
		hideWorld()
	else
		ui.chip.Visible = false
		if step ~= ui.textStep or touch ~= ui.textTouch then -- (the words made once a step, not every look)
			ui.textStep, ui.textTouch = step, touch
			ui.stepText = SandboxSteps.text(step, touch)
		end
		setHint(hint, ui.stepText, true)
	end
	if (ui.shown or ui.chip.Visible) and (os.clock() - (ui.laidAt or 0) > 1 or under(ui.root.AbsolutePosition, Ui.screenScale()) ~= ui.under) then
		layout() -- (what is above moved: at once; the sides' HUD may have moved: a second's look is enough)
	end
	if not on then
		return
	end
	local at, label = nil, nil
	if guide and root and not state.inside then
		at, label = targetOf(step.target, px, pz)
	end
	if at and label then
		showWorld(at, label, px, pz)
	else
		hideWorld()
	end
end

-- ── API ────────────────────────────────────────────────────────────────────

function SandboxGuide.setEnabled(value: boolean)
	if on == value then
		return
	end
	on = value
	offUntil = if value then 0 else os.clock() + G.OffNote
	if started then
		pcall(look)
	end
end

function SandboxGuide.enabled(): boolean
	return on
end

function SandboxGuide.step(): string?
	return if current then current.id else nil
end

function SandboxGuide.hint(): GuiObject?
	return ui.holder
end

function SandboxGuide.start()
	if started or not Config.Sandbox.On then
		return
	end
	started = true
	build()
	buildWorld()
	-- the move (client/MovingHud.luau reads the same remote), its planning, the collection (when it is there)
	local moving = Net.get("Moving")
	moving.OnClientEvent:Connect(function(kind: any, view: any)
		if kind == "state" then
			readMove(view)
		end
	end)
	local lobby = Net.get("MoveLobby")
	lobby.OnClientEvent:Connect(function(kind: any, view: any)
		if kind == "lobby" then
			state.planning = type(view) == "table"
			state.planningMine = type(view) == "table" and view.mine == true
		end
	end)
	task.spawn(function()
		local ok, collection = pcall(Net.get, "Collection")
		if not ok then
			return -- (no collection on this server: the steps after the move never show)
		end
		collection.OnClientEvent:Connect(function(msg: any, extra: any)
			local body = if type(msg) == "table" then msg elseif msg == "state" then extra else nil
			if type(body) == "table" and (body.kind == "state" or msg == "state") then
				if not world.collectionSeen then
					world.collectionSeen = true
					last.shown = nil -- (the first state: what the save had on show is not something you did now)
				end
				-- (8.1 merge: the server's own count, the UPGRADES desk's More stands included; else the warehouse's)
				world.ownedStands = if type(body.stands) == "number" then body.stands else nil
				summary = SandboxSteps.collection(body, if type(body.stands) == "number" then body.stands else standCount())
			end
		end)
		collection:FireServer({ kind = "state" })
	end)
	moving:FireServer("state") -- (a move already running: its state again, for this listener too)
	-- G held (not while you carry: G puts a piece down; not with a tool in your hand: G sets it down)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode ~= Enum.KeyCode.G or processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local character = player.Character
		if state.carrying or (character and character:FindFirstChildOfClass("Tool")) then
			return
		end
		gDownAt, gUsed = os.clock(), false
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.G then
			gDownAt = nil
		end
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			pcall(layout)
		end)
	end
	task.spawn(function()
		while true do
			local ok, err = pcall(look :: any) -- (an error is said once and waited out, the loop goes on)
			if not ok then
				warn(`[SandboxGuide] {err}`)
				task.wait(2)
			end
			task.wait(G.Every)
		end
	end)
end

return SandboxGuide
