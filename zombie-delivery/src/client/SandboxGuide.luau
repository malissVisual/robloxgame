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
--     its distance tag ("THE OLD CHALET · 420 m"). Inside the house only the hint (no target there).
--   * The steps come from shared/SandboxSteps.luau (pure, tested) on a state read from what the client sees: the player
--     attribute Plot (server/SandboxPlots.luau); the Moving remote's "state" (as client/MovingHud.luau reads it: a move
--     runs, `inside` the house, the van's load counts.out, counts.delivered, your piece in your hands: an item `mine` and
--     "carried"); the MoveLobby remote's "lobby" (the planning: LAUNCH); the Collection remote's "state" (the stock, the
--     pieces on show and their stands); where you stand and whether you sit in a vehicle.
--   * Each step goes quiet once done (per session: SandboxSteps.doneBy); the arrow to the house and home stays while you
--     drive. Hold G (not while you carry: G puts a piece down) or the ✕ hides the guide ("Guide off" for a moment); hold G
--     again, or on a touch screen the 💡 chip left in its place, brings it back. SandboxGuide.setEnabled for a settings row.
--   * 8.3 keys (shared/SandboxPad.luau, client/PadGlyph.luau): the line's words are the device's used now, a gamepad
--     used last first: a prompt's E is the gamepad's X ("X at the back"; a touch screen's "tap at the back"), "Guide off ·
--     hold G / hold B / tap 💡 to bring it back". With a gamepad B held does what a held G does (B puts a piece down
--     as G does; not while a window holds the gamepad's selection: B closes it). They follow a gamepad picked up or put
--     down at the next look.
--   * 8.3, the soft steps (SandboxSteps.choose; the core loop always wins): "Your warehouse is full: grow it at the
--     UPGRADES desk ($1,500)" and another upgrade in reach (the chevron over the desk, shared/WarehouseLayout.luau
--     terminal at your warehouse's level: the player attribute Config.SandboxUpgrades.WarehouseAttribute), "🔥 Your Jukebox is
--     hot today: sell it or show it" (the nearest free stand; with none an orange ring round the HUD's 📦 STOCK chip,
--     client/SandboxHud.luau's "StockChip"), "🎨 Make your van your own: E at its side opens the PAINT SHOP" (the van's
--     🎨 prompt, its Attachment "PaintPoint"). Read from the State remote (your money), the Upgrades remote's state
--     (the levels), the Collection remote's state (its market) and the VanPaint remote's state (what you own). Never
--     while something covers the screen or a first-time hint talks (client/SandboxHintsUi.luau: isCovered, window,
--     busy), Config.SandboxGuide.SoftGap s apart; each shows SoftSeconds at most,
--     and the ✕ on one dismisses that step alone for the session (the guide stays on; on a core step the ✕ hides the
--     guide as before).
--   * 8.4, Danny for hire (SandboxSteps.danny: in a move, before its own step, each said once as a soft step):
--     "Hire Danny to carry with you" while he is for hire and your money pays him (the chevron over his body: the
--     model in workspace.Npcs whose MoveHelper is your player attribute MoveHelperId, as client/MoveHelperCard.luau
--     finds it), "Pick a piece to give it to Danny" in the house once he is hired with his list empty, "Heavy piece:
--     press Lift and wait for Danny" the first time a two-person piece of your move is within Config.SandboxGuide
--     .HeavyNear studs (its own Lift prompt, tagged MovePrompt, looked for at most once a second and only while that
--     step may still show). Read from your player attributes (MoveHelper, MoveHelperPrice, MoveHelperQueue,
--     MoveHelperCall: every look) and the Moving state (its two-person pieces left: readMove). In a move with him, what
--     covers the screen and what talks are asked too (his card, the move's cards, a grip check, a hint): his steps
--     wait for them. A gamepad's words end in its button: "(L1)" at him, "(R1)" at a piece (SandboxSteps.onDevice).
--   * 8.9, trading between players (8.7), the last soft step: "🏷 Sell to players: set a price on a piece on show" while
--     Config.SandboxGuide.SellPlayers players are on the server (counted at most once a second, only while it may
--     show) and SellShown pieces of yours are on show with no FOR SALE sign (the Collection remote's state: its views'
--     `sale`); the chevron over your nearest piece on show (its Set price prompt, SET PRICE); done once a sign is set.
--   * Cheap: one loop every Config.SandboxGuide.Every seconds (no frame-by-frame work, no tables made in it: the state,
--     the path's points and the instances are made once and reused; a string only when the words or the metres change).
--   * 8.3 (design/warehouse-levels/KONTRAKT.md): your warehouse has a level (1 Garage … 5 Logistics Center, the player
--     attribute Config.SandboxUpgrades.WarehouseAttribute; 4 until the server sets it), every level its own building:
--     the stands' spots are WarehouseLayout.stands(WarehouseLayout.site(plot, level)) (all the level has, the bought
--     ones pointed at), found once a plot and level, so a level up moves the arrow to the new building's stands.
-- Everything waits for Config.Sandbox.On (client/Main.client.luau starts it in the sandbox).
--   SandboxGuide.start()            builds it and starts the loop (once; nothing outside the sandbox)
--   SandboxGuide.setEnabled(on)     shows or hides the guide (the G hold, the ✕, a settings row)
--   SandboxGuide.enabled()          is it on?
--   SandboxGuide.close()            the hint's ✕ (8.3: a soft step dismissed, else the guide off)
--   SandboxGuide.step()             the step now (its id, SandboxSteps.Steps), nil before the first look
--   SandboxGuide.hint()             the hint line (a top block), for the layout checks
--   SandboxGuide.covered / windowOpen   8.3 hooks: what covers the screen, the sandbox window open now (nil: asked of
--                                   client/SandboxHintsUi.luau)
-- Presentation only.

local CollectionService = game:GetService("CollectionService") -- 8.4: the move's pieces' prompts (a heavy one near)
local GuiService = game:GetService("GuiService")
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
local SandboxPad = require(Shared.SandboxPad) -- 8.3 keys: the device's words
local Ui = require(script.Parent.Ui)
local PadGlyph = require(script.Parent.PadGlyph) -- 8.3 keys: the device used now
local Theme = require(script.Parent.Theme)
local TopBlocks = require(script.Parent.TopBlocks)
local MoveLayout = require(script.Parent.MoveLayout) -- (Roblox's player list's width on a computer)

local SandboxGuide = {}

SandboxGuide.covered = nil :: (() -> boolean)?
SandboxGuide.windowOpen = nil :: (() -> string?)?

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
	desk = "UPGRADES DESK", -- 8.3
	paint = "PAINT SHOP", -- 8.3
	danny = string.upper(Config.MoveHelper.Name), -- 8.4
	sale = "SET PRICE", -- 8.9
}
local RING = 4 -- 8.3: px the ring round the 📦 STOCK chip stands out of it

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
	money = nil, -- 8.3, the soft steps' (SandboxSteps.State)
	levels = nil,
	hot = nil,
	hotCount = 0,
	hotSold = false,
	day = nil,
	painted = nil,
	vanHome = false,
	window = nil,
	covered = false,
	hush = false,
	helper = nil, -- 8.4, Danny for hire (SandboxSteps.State)
	helperPrice = nil,
	helperQueue = nil,
	waiting = false,
	heavy = 0,
	heavyNear = false,
	clipboard = false, -- 8.5 Danny's clipboard out (orders mode)
	players = nil, -- 8.9, the sell step (SandboxSteps.State)
	signs = nil,
}
local softAfter = 0 -- 8.3: os.clock() before which no soft step shows (one just ended: Config.SandboxGuide.SoftGap)
local hintsUi: any = nil -- 8.3: client/SandboxHintsUi.luau (looked for once; false: not there)
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
local standSpots: { [number]: { [number]: { [number]: SandboxSteps.Place } } } = {} -- a plot's display stands, by level (found once)

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

-- 8.4: Danny on your move, from your player attributes (server/MoveHelper.luau's: for hire or hired, his price, his
-- list, your call to him): every look and every Moving state (they change without one). 8.5: your clipboard out (your
-- character's ClipboardHeld, server/Clipboard.luau's: the give step's words then).
local function readHelper()
	local helper = player:GetAttribute("MoveHelper")
	local price, queue = player:GetAttribute("MoveHelperPrice"), player:GetAttribute("MoveHelperQueue")
	local call = player:GetAttribute("MoveHelperCall")
	state.helper = if move ~= nil and (helper == "offer" or helper == "hired") then helper else nil
	state.helperPrice = if type(price) == "number" then price else nil
	state.helperQueue = if type(queue) == "number" then queue else nil
	state.waiting = type(call) == "string" and call ~= ""
	local character = player.Character
	state.clipboard = character ~= nil and character:GetAttribute("ClipboardHeld") == true
end

-- The Moving remote's state: what the steps read from it (once a message, not every look).
local function readMove(view: any)
	move = if type(view) == "table" then view else nil
	local carrying, inVan, delivered, heavy = false, 0, 0, 0
	if move then
		local counts = if type(move.counts) == "table" then move.counts else {}
		inVan = tonumber(counts.out) or 0
		delivered = tonumber(counts.delivered) or 0
		if type(move.items) == "table" then
			for _, item in move.items do
				if type(item) == "table" then
					if item.mine == true and item.state == "carried" then
						carrying = true
					end
					if item.class == "pair" and (item.state == "home" or item.state == "ground") then
						heavy += 1 -- 8.4: a two-person piece still to carry out (Danny's "press Lift and wait")
					end
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
	state.heavy = heavy -- 8.4
	readHelper() -- 8.4 (Danny's part: your player attributes)
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

-- 8.3: your warehouse's level (the player attribute, 1 … 5, server/Upgrades.luau); 4 until the server sets it (a plain
-- Plot's: the building of before 8.3).
local function warehouseLevel(): number
	local level = player:GetAttribute(Config.SandboxUpgrades.WarehouseAttribute)
	return if type(level) == "number" then level else 4
end

-- A plot's display stands at your warehouse's level (index = the stand's number, Collection.display's `stand`): every
-- spot that level's building has (8.3: WarehouseLayout.site, its capacity; targetOf keeps the bought ones), found once a
-- plot and level.
local function standsOf(plotId: number): { [number]: SandboxSteps.Place }
	local level = warehouseLevel()
	local byLevel = standSpots[plotId]
	if not byLevel then
		byLevel = {}
		standSpots[plotId] = byLevel
	end
	local known = byLevel[level]
	if known then
		return known
	end
	local list: { [number]: SandboxSteps.Place } = {}
	local plot = SandboxMap.Plots[plotId]
	local layout = warehouseLayout()
	if plot and layout and type(layout.stands) == "function" then
		local site: any = plot
		if type(layout.site) == "function" then
			local ok, got = pcall(layout.site, plotId, level)
			site = if ok and type(got) == "table" then got else plot
		end
		local count: number? = nil
		if type(layout.capacity) == "function" then
			local ok, got = pcall(layout.capacity, level)
			count = if ok and type(got) == "number" then got else nil
		end
		local ok, raw = pcall(layout.stands, site, count)
		if ok and type(raw) == "table" then
			for index, value in raw do
				local place = if type(index) == "number" then placeOf(value, site, 0) else nil
				if place then
					list[index] = place
				end
			end
		end
	end
	byLevel[level] = list
	return list
end

-- The display stands a warehouse starts with (8.3: its level's, WarehouseLayout.count; else Config.Warehouse.Stands,
-- else the spots found; nil: not known).
local function standCount(): number?
	local layout = warehouseLayout()
	if layout and type(layout.count) == "function" then
		local ok, count = pcall(layout.count, warehouseLevel())
		if ok and type(count) == "number" then
			return count
		end
	end
	local warehouse = (Config :: any).Warehouse
	if type(warehouse) == "table" and type(warehouse.Stands) == "number" then
		return warehouse.Stands
	end
	local plot = player:GetAttribute("Plot")
	local count = if type(plot) == "number" then #standsOf(plot) else 0
	return if count > 0 then count else nil
end

-- 8.3: the UPGRADES desk of a plot at the warehouse's level (shared/WarehouseLayout.luau terminal: at the back wall's
-- middle, so every level has it somewhere else), found once a level (nil: no layout).
local function deskOf(plotId: number, plot: SandboxMap.Plot): Vector3?
	local level = warehouseLevel()
	local key = plotId * 100 + math.clamp(math.floor(level), 0, 99)
	if world.deskKey == key then
		return world.deskAt
	end
	world.deskKey, world.deskAt = key, nil
	local layout = warehouseLayout()
	local terminal = layout and layout.terminal
	if type(terminal) == "function" then
		local site: any = plot -- (the plot at the level: WarehouseLayout.site; a plain Plot is level 4)
		if type(layout.site) == "function" then
			local found, got = pcall(layout.site, plotId, level)
			site = if found and type(got) == "table" then got else plot
		end
		local ok, spot = pcall(terminal, site)
		if ok and type(spot) == "table" and type(spot.x) == "number" and type(spot.z) == "number" then
			world.deskAt = Vector3.new(spot.x, (tonumber(spot.y) or 0) + 2, spot.z)
		end
	end
	return world.deskAt
end

-- ── 8.3: what the soft steps read ─────────────────────────────────────────

-- client/SandboxHintsUi.luau (what covers the screen, the window open, the hints' queue), looked for once.
local function hints(): any
	if hintsUi == nil then
		local ok, found = pcall(function(): any
			return require(script.Parent.SandboxHintsUi)
		end)
		hintsUi = if ok and type(found) == "table" then found else false
	end
	return if hintsUi then hintsUi else nil
end

local function ask(hook: (() -> any)?, question: string): any
	local fn: any = hook
	if fn == nil then
		local module = hints()
		fn = module and module[question]
	end
	if type(fn) ~= "function" then
		return nil
	end
	local ok, answer = pcall(fn)
	return if ok then answer else nil
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

-- 8.3: your van stands at your plot's van spot (Config.VanPaint.Prompt.Home: its 🎨 Paint van prompt is on there).
local function vanHome(): boolean
	local plotId = state.plot
	local plot = if plotId then SandboxMap.Plots[plotId] else nil
	local model = if plot then van() else nil
	local chassis = model and model.PrimaryPart
	local at = chassis and chassis.Position
	if not plot or not at then
		return false
	end
	local spot, reach = plot.vanSpot, Config.VanPaint.Prompt.Home
	local dx, dz = at.X - spot.x, at.Z - spot.z
	return dx * dx + dz * dz <= reach * reach
end

-- 8.4: Danny's body on your move (the model in workspace.Npcs whose MoveHelper is your player attribute MoveHelperId,
-- as client/MoveHelperCard.luau finds it): looked up at most once a second, kept while it stays.
local function dannyRoot(): BasePart?
	local id = player:GetAttribute("MoveHelperId")
	local known = world.danny
	if type(id) ~= "number" then
		world.danny = nil
		return nil
	elseif not (known and known.Parent and known:GetAttribute("MoveHelper") == id) then
		world.danny, known = nil, nil
		local now = os.clock()
		local folder = workspace:FindFirstChild("Npcs")
		if folder and now >= (world.dannyLookAt or 0) then
			world.dannyLookAt = now + 1
			for _, child in folder:GetChildren() do
				if child:IsA("Model") and child:GetAttribute("MoveHelper") == id then
					world.danny, known = child, child
					break
				end
			end
		end
	end
	local root = known and (known.PrimaryPart or known:FindFirstChild("HumanoidRootPart"))
	return if root and root:IsA("BasePart") then root else nil
end

-- 8.4: is a two-person piece of your move within Config.SandboxGuide.HeavyNear studs of `at`, its Lift shown (its own
-- prompt, tagged MovePrompt, with your move's owner: MovingHud's rule)? Looked for at most once a second.
local function heavyNear(at: Vector3): boolean
	local now = os.clock()
	if now < (world.heavyAt or 0) then
		return world.heavyNear == true
	end
	world.heavyAt = now + 1
	local with = player:GetAttribute("MoveWith")
	local found = false
	for _, prompt in CollectionService:GetTagged("MovePrompt") do
		local part = prompt.Parent
		if prompt:IsA("ProximityPrompt") and prompt.Enabled and string.sub(prompt.ActionText, 1, 4) == "Lift" and part and part:IsA("BasePart") then
			local owner = prompt:GetAttribute("MoveOwner")
			if (owner == player.UserId or (owner ~= nil and owner == with)) and (part.Position - at).Magnitude <= G.HeavyNear then
				found = true
				break
			end
		end
	end
	world.heavyNear = found
	return found
end

-- The nearest empty stand of the ones this warehouse has bought (8.1: never a locked one; 8.3: the server's count, else
-- the level's own stands, the spots being all the level has; nil: none, or not known).
local function freeStand(plotId: number, px: number, pz: number): Vector3?
	local spots = standsOf(plotId)
	local owned = if type(world.ownedStands) == "number" then world.ownedStands else standCount()
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
	return if spot then Vector3.new(spot.x, spot.y + 3, spot.z) else nil
end

-- 8.9: the nearest of your stands with a piece on show (its Set price prompt; nil: none known).
local function shownStand(plotId: number, px: number, pz: number): Vector3?
	local spots = standsOf(plotId)
	local index = SandboxSteps.nearestShown(px, pz, spots, summary.taken)
	local spot = if index then spots[index] else nil
	return if spot then Vector3.new(spot.x, spot.y + 3, spot.z) else nil
end

-- 8.9: the players on the server (you too), counted at most once a second.
local function playerCount(): number
	local now = os.clock()
	if now >= (world.playersAt or 0) then
		world.playersAt = now + 1
		world.players = #Players:GetPlayers()
	end
	return world.players
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
	elseif kind == "stand" or kind == "hot" then
		if plotId and plot then
			local spot = freeStand(plotId, px, pz)
			if spot then
				return spot, LABELS.stand
			elseif kind == "stand" then
				return Vector3.new(plot.door.x, plot.door.y + 4, plot.door.z), LABELS.warehouse
			end -- (8.3, a hot piece and no free stand: the ring round the 📦 STOCK chip instead)
		end
	elseif kind == "desk" then -- 8.3: the UPGRADES desk at your warehouse's level
		if plotId and plot then
			local desk = deskOf(plotId, plot)
			if desk then
				return desk, LABELS.desk
			end
			return Vector3.new(plot.door.x, plot.door.y + 4, plot.door.z), LABELS.warehouse
		end
	elseif kind == "paint" then -- 8.3: the van's 🎨 Paint van prompt (server/VanPaint.luau's PaintPoint)
		local model = van()
		local chassis = model and model.PrimaryPart
		if chassis then
			local point = chassis:FindFirstChild("PaintPoint")
			if point and point:IsA("Attachment") then
				return point.WorldPosition, LABELS.paint
			end
			return chassis.Position, LABELS.paint
		end
	elseif kind == "danny" then -- 8.4: Danny, for hire on your move
		local root = dannyRoot()
		if root then
			return root.Position + Vector3.new(0, 2, 0), LABELS.danny
		end
	elseif kind == "sale" then -- 8.9: your nearest piece on show (its Set price prompt), else your warehouse
		if plotId and plot then
			local spot = shownStand(plotId, px, pz)
			if spot then
				return spot, LABELS.sale
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

-- 8.3: the HUD's 📦 STOCK chip (client/SandboxHud.luau's "StockChip" in its ScreenGui "SandboxHud"): kept while it
-- stays, looked for at most once a second.
local function stockChip(): GuiObject?
	local known = ui.stockChip
	if known and known.Parent then
		return known
	end
	ui.stockChip = nil
	local now = os.clock()
	if now < (ui.chipLookAt or 0) then
		return nil
	end
	ui.chipLookAt = now + 1
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("SandboxHud")
	local found = hud and hud:FindFirstChild("StockChip", true)
	if found and found:IsA("GuiObject") then
		ui.stockChip = found
		return found
	end
	return nil
end

-- 8.3: the orange ring round the 📦 STOCK chip (a hot piece and no free stand: "sell it or show it" from the list),
-- pulsing; moved only when the chip did.
local function pointChip(wanted: boolean)
	local ring = ui.ring
	if not ring then
		return
	end
	local chip = if wanted then stockChip() else nil
	local hud = chip and chip:FindFirstAncestorWhichIsA("ScreenGui")
	if chip and chip.Visible and (hud == nil or hud.Enabled) and chip.AbsoluteSize.X >= 1 then
		local origin = ui.root.AbsolutePosition
		local p, s = chip.AbsolutePosition, chip.AbsoluteSize
		local x, y, w, h = p.X - origin.X - RING, p.Y - origin.Y - RING, s.X + 2 * RING, s.Y + 2 * RING
		if x ~= ui.ringX or y ~= ui.ringY or w ~= ui.ringW or h ~= ui.ringH then
			ui.ringX, ui.ringY, ui.ringW, ui.ringH = x, y, w, h
			ring.Position = UDim2.fromOffset(x, y)
			ring.Size = UDim2.fromOffset(w, h)
		end
		if not ring.Visible then
			ring.Visible = true
			ui.ringPulse:Play()
		end
	elseif ring.Visible then
		ring.Visible = false
		ui.ringPulse:Pause()
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
		SandboxGuide.close()
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
	-- 8.3: the ring round the HUD's 📦 STOCK chip (pointChip): an orange outline, no fill, no input of its own
	local ring = Ui.make("Frame", {
		Name = "StockRing",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Visible = false,
	}, root)
	Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
	local stroke = Ui.make("UIStroke", { Color = COLOR, Thickness = 2.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Transparency = 0 }, ring)
	ui.ring = ring
	ui.ringPulse = TweenService:Create(stroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transparency = 0.65,
	})
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
	-- 8.3, the soft steps: the market's (the Collection's state), and only off a move what covers the screen, the
	-- window open, the van at home (only while a paint step could come), something else talking. 8.4: Danny on your
	-- move (your attributes), a heavy piece near (only while its step may still show), and in a move with him what
	-- covers the screen and what talks too (his steps wait for them as the soft ones do)
	state.hot, state.hotCount, state.day, state.hotSold = summary.hotName, summary.hot, summary.day, summary.hotSold
	readHelper()
	state.heavyNear = root ~= nil and state.helper == "hired" and done.lift ~= true and (state.heavy or 0) > 0 and not state.carrying
		and not state.seated and not state.waiting and heavyNear(root.Position)
	local calm = not state.move and not state.planning
	-- 8.9: the sell step's: your signs (the Collection's state) and the players here (only while it may show)
	state.signs = if world.collectionSeen then summary.signs else nil
	state.players = if calm and done.sell ~= true and summary.signs == 0 and summary.shown >= G.SellShown then playerCount() else nil
	local asks = calm or state.helper ~= nil
	state.covered = asks and ask(SandboxGuide.covered, "isCovered") == true
	local window = if state.covered then ask(SandboxGuide.windowOpen, "window") else nil -- (a window open covers it)
	state.window = if type(window) == "string" then window else nil
	state.vanHome = calm and state.painted == false and vanHome()
	state.hush = asks and (os.clock() < softAfter or ask(nil, "busy") == true) -- (a first-time hint talks)
	SandboxSteps.doneBy(state, done, last)
	local step = SandboxSteps.choose(state, done)
	if step ~= current then
		if current and current.soft then
			softAfter = os.clock() + G.SoftGap -- (a soft step ended: the next one waits)
			if step.soft then
				state.hush = true
				step = SandboxSteps.choose(state, done)
			end
		end
		current = step
		seen = 0
	end
	local hint, guide = SandboxSteps.visible(step, done, state.seated)
	if hint and on and (step.info or step.soft) then
		seen += G.Every
		if seen >= (if step.soft then G.SoftSeconds else G.InfoSeconds) then
			done[step.id] = true -- (said long enough)
			hint, guide = SandboxSteps.visible(step, done, state.seated)
		end
	end
	-- a held G (8.3 keys: or the gamepad's B): the guide off or on (once a hold)
	if gDownAt and not gUsed and os.clock() - gDownAt >= G.HideHold then
		gUsed = true
		SandboxGuide.setEnabled(not on)
		return
	end
	local device = PadGlyph.device() -- 8.3 keys: the words of the device used now (a gamepad used last first)
	local touch = device == "touch"
	if not on then
		local note = os.clock() < offUntil
		if device ~= ui.offDevice then -- (the words made once a device, not every look)
			ui.offDevice = device
			local how = SandboxPad.howTo("guide", device) or "Hold G"
			ui.offText = `Guide off · {string.lower(string.sub(how, 1, 1))}{string.sub(how, 2)} to bring it back`
		end
		setHint(note, ui.offText, false)
		ui.chip.Visible = touch and not note
		hideWorld()
		pointChip(false)
	else
		ui.chip.Visible = false
		-- (the words made once a step, not every look; 8.3: a soft step's again when its price or piece changes)
		local a, b = SandboxSteps.detail(step, state)
		if step ~= ui.textStep or device ~= ui.textDevice or a ~= ui.textA or b ~= ui.textB then
			ui.textStep, ui.textDevice, ui.textA, ui.textB = step, device, a, b
			local words = SandboxSteps.words(step, state)
			-- (8.3 keys: a gamepad's "X at the back", a touch screen's "tap at the back"; 8.4: a gamepad's "(R1)" after
			-- Danny's "Pick a piece …")
			ui.stepText = SandboxSteps.onDevice(step, words, device)
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
	pointChip(hint and step.target == "hot" and at == nil) -- (8.3: a hot piece, no free stand: the 📦 STOCK chip)
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

-- The hint's ✕: 8.3, on a soft step that step alone is dismissed (for the session; the next soft one waits SoftGap s),
-- the guide stays on; on a core step the guide goes off ("Guide off").
function SandboxGuide.close()
	local step = current
	if on and step and step.soft and ui.shown and SandboxSteps.dismiss(step, done) then
		softAfter = os.clock() + G.SoftGap
		if started then
			pcall(look)
		end
		return
	end
	SandboxGuide.setEnabled(false)
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
					last.hot, last.day = nil, nil -- (8.3: nor its hot pieces, nor the market's day)
				end
				-- (8.1 merge: the server's own count, the UPGRADES desk's More stands included; else the warehouse's)
				world.ownedStands = if type(body.stands) == "number" then body.stands else nil
				summary = SandboxSteps.collection(body, if type(body.stands) == "number" then body.stands else standCount())
			end
		end)
		collection:FireServer({ kind = "state" })
	end)
	-- 8.3, the soft steps: your money (the State remote; the windows' states carry it too), the UPGRADES' levels and
	-- what the PAINT shop has sold you (each when it is there; their states asked for this listener too)
	local function money(data: any)
		local value = if type(data) == "table" then data.money else nil
		if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
			state.money = value
		end
	end
	local listeners: { [string]: (any) -> () } = {
		State = money,
		Upgrades = function(msg: any)
			if type(msg) == "table" and msg.kind == "state" then
				state.levels = if type(msg.levels) == "table" then msg.levels else {} -- (UpgradeRules.level checks each)
				money(msg)
			end
		end,
		VanPaint = function(msg: any)
			if type(msg) ~= "table" then
				return
			elseif msg.kind == "state" then
				state.painted = type(msg.owned) == "table" and next(msg.owned) ~= nil
				money(msg)
			elseif msg.kind == "bought" then
				state.painted = true
			end
		end,
	}
	for name, listener in listeners do
		task.spawn(function()
			local ok, remote = pcall(Net.get, name)
			if not ok then
				return
			end
			remote.OnClientEvent:Connect(listener)
			if name ~= "State" then
				remote:FireServer({ kind = "state" })
			end
		end)
	end
	moving:FireServer("state") -- (a move already running: its state again, for this listener too)
	-- G held (not while you carry: G puts a piece down; not with a tool in your hand: G sets it down); 8.3 keys: the
	-- gamepad's B the same (shared/SandboxPad.luau "guide"; not while a window holds the selection: B closes it)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local pad = input.KeyCode == Enum.KeyCode.ButtonB
		if (input.KeyCode ~= Enum.KeyCode.G and not pad) or processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if pad and GuiService.SelectedObject ~= nil then
			return
		end
		local character = player.Character
		if state.carrying or (character and character:FindFirstChildOfClass("Tool")) then
			return
		end
		gDownAt, gUsed = os.clock(), false
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.ButtonB then
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
