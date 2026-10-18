--!strict
-- 8.3 SANDBOX: the first-time hints on the screen (the 8.2 review: the new features need a word the first time they
-- matter; their rules and words: shared/SandboxHints.luau). Heard from what the sandbox already sends, no hooks in the
-- other modules:
--   the "CollectionBook" remote's states   the first piece ever in your book (its state had none): "book"
--   the "SandboxTasks" remote              a task "done": "tasks" (its states say whether a reward still waits)
--   the "Collection" remote's states       pieces came home and FILL BEST has something to show: "fill"; 8.9:
--                                          PriceShown pieces of yours on show, none with a FOR SALE sign: "price"
--   8.9 the "PlayerTrade" remote           another player's offer for your piece ({ kind = "offer", player = true }):
--                                          "deal" (its offer card covers the screen: the hint comes after it)
--   8.9, a look every Hints.Look s (only until both are said)   your character's ClipboardHeld (server/Clipboard.luau:
--                                          your clipboard out, orders mode): "orders"; where you stand: in another
--                                          player's warehouse (SandboxHints.hallAt at its level, workspace.Warehouses'
--                                          Level<id>) with a piece of theirs on show (a stand's trade prompt on, tagged
--                                          Config.PlayerTrade.PromptTag with its owner's UserId): "visit"; 10.4: in
--                                          a party lobby away from the PLAY circle (client/RunUi.luau's play()): "lobby"
-- (8.9: visit, price and deal only while trading is on, Config.PlayerTrade.On.)
-- A hint is one toast (SandboxHintsUi.notify: client/SandboxHud.luau's), in this device's words (client/PadGlyph.luau),
-- once a session, one at a time, never while something covers the screen: a grip check (client/CarryGripUi.luau active),
-- the move's cards with its result (client/MovingHud.luau isOpen), a sandbox window (the warehouse's, the UPGRADES
-- desk's, the book, the TASKS panel, Danny's command card, 8.3: the PAINT shop's, 8.3 review: a visitor's offer card,
-- 8.9: a player's offer card and the trade's window, client/TradeUi.luau) or the start screen (the ScreenGui
-- "SandboxHud" off). A hint no longer true when its turn comes (the reward claimed, FILL BEST used; 8.9: the clipboard
-- put away, the warehouse left, a sign set) is left out; one
-- whose window the player opened alone while it waited (the book, the TASKS panel) is not needed any more.
-- client/SandboxHud.luau starts it.
--   SandboxHintsUi.start()            listens (once)
--   SandboxHintsUi.step()             looks once: the hint due now (the loop does it every Hints.Every s while one waits)
--   SandboxHintsUi.queue()            the hints' queue (SandboxHints.Queue: seen, waiting)
--   SandboxHintsUi.isCovered()        8.3: does something cover the screen now (as the hints wait for it)?
--   SandboxHintsUi.window()           8.3: the sandbox window open now (its module's name: "WarehouseUi", "UpgradeUi",
--                                     "VanPaintUi", …; nil: none)
--   SandboxHintsUi.busy()             8.3: a hint waits or has just shown (SandboxHints.busy)
--   (8.3: client/SandboxGuide.luau asks these three: its soft steps wait as the hints do, and while a hint talks)
--   SandboxHintsUi.around()           8.9: looks once at your clipboard and where you stand (the look's loop does it
--                                     every Hints.Look s until both hints are said)
--   SandboxHintsUi.notify / covered / now   hooks: the toast; what covers the screen (nil: its own look, above); the
--                                     clock (nil: os.clock)
-- Presentation only.

local CollectionService = game:GetService("CollectionService") -- 8.9: the stands' trade prompts (a visit)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SandboxHints = require(Shared.SandboxHints)
local PadGlyph = require(script.Parent.PadGlyph)

local SandboxHintsUi = {}

SandboxHintsUi.notify = nil :: ((text: string) -> ())?
SandboxHintsUi.covered = nil :: (() -> boolean)?
SandboxHintsUi.now = nil :: (() -> number)?

local H = Config.SandboxHud.Hints

local started = false
local queue = SandboxHints.new()
local looking = false
local bookFound: number? = nil -- the pieces in the book's last state (nil: no state yet)
local stockSeen: number? = nil -- the pieces in the Collection's last state (nil: no state yet)
local tasksReady = 0 -- rewards waiting to be claimed (the TASKS' last state)
local fillNow = false -- the Collection's last state: FILL BEST would put something on show
local priceNow = false -- 8.9: the Collection's last state: PriceShown on show, no FOR SALE sign yet
local clipboardOut = false -- 8.9: your clipboard out at the last look
local visitNow = false -- 8.9: in another player's warehouse with a piece of theirs on show at the last look
local lobbyAway = false -- 10.4: in a party lobby, away from the PLAY circle, at the last look
local watching = false -- 8.9: the look's loop runs
local spots: { SandboxHints.Spot } = {} -- 8.9: the trade prompts on (refilled by a look in a warehouse)

local function clock(): number
	local now = SandboxHintsUi.now
	return if now then now() else os.clock()
end

function SandboxHintsUi.queue(): SandboxHints.Queue
	return queue
end

-- ── What covers the screen ─────────────────────────────────────────────────

-- The client's modules it asks (each looked for once, when first asked: they are all loaded by then).
local LOADERS: { [string]: () -> any } = {
	CarryGripUi = function(): any
		return require(script.Parent.CarryGripUi)
	end,
	MovingHud = function(): any
		return require(script.Parent.MovingHud)
	end,
	WarehouseUi = function(): any
		return require(script.Parent.WarehouseUi)
	end,
	UpgradeUi = function(): any
		return require(script.Parent.UpgradeUi)
	end,
	CollectionBookUi = function(): any
		return require(script.Parent.CollectionBookUi)
	end,
	SandboxTasksUi = function(): any
		return require(script.Parent.SandboxTasksUi)
	end,
	MoveHelperCard = function(): any
		return require(script.Parent.MoveHelperCard)
	end,
	VanPaintUi = function(): any
		return require(script.Parent.VanPaintUi)
	end,
	OfferCard = function(): any -- (8.3 review)
		return require(script.Parent.OfferCard)
	end,
	TradeUi = function(): any -- (8.9: the trade's window, 8.7)
		return require(script.Parent.TradeUi)
	end,
	RunUi = function(): any -- (10.4: the PLAY view, the "lobby" hint)
		return require(script.Parent.RunUi)
	end,
}
local modules: { [string]: any } = {}
local function client(name: string): any
	local known = modules[name]
	if known == nil then
		local load = LOADERS[name]
		local ok, made = pcall(function(): any
			return if load then load() else nil
		end)
		known = if ok and type(made) == "table" then made else false
		modules[name] = known
	end
	return if known == false then nil else known
end

local function says(name: string, question: string): boolean
	local module = client(name)
	local ask = module and module[question]
	if type(ask) ~= "function" then
		return false
	end
	local ok, yes = pcall(ask)
	return ok and yes == true
end

local function hudHidden(): boolean
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local hud = if playerGui then playerGui:FindFirstChild("SandboxHud") else nil
	return hud ~= nil and hud:IsA("ScreenGui") and (hud :: ScreenGui).Enabled == false
end

local WINDOWS = { "WarehouseUi", "UpgradeUi", "CollectionBookUi", "SandboxTasksUi", "MoveHelperCard", "VanPaintUi", "OfferCard", "TradeUi" } -- (8.3: Danny's card, the PAINT shop too; 8.3 review: a visitor's offer; 8.9: the trade's window)

local function covered(): boolean
	local hook = SandboxHintsUi.covered
	if hook then
		local ok, yes = pcall(hook)
		return ok and yes == true
	end
	if hudHidden() or says("CarryGripUi", "active") or says("MovingHud", "isOpen") then
		return true
	end
	for _, name in WINDOWS do
		if says(name, "isOpen") then
			return true
		end
	end
	return false
end

function SandboxHintsUi.isCovered(): boolean
	return covered()
end

function SandboxHintsUi.window(): string?
	for _, name in WINDOWS do
		if says(name, "isOpen") then
			return name
		end
	end
	return nil
end

function SandboxHintsUi.busy(): boolean
	return SandboxHints.busy(queue, clock())
end

-- ── The queue ───────────────────────────────────────────────────────────────

local function still(id: string): boolean
	if id == "tasks" then
		return tasksReady > 0
	elseif id == "fill" then
		return fillNow
	elseif id == "price" then -- (8.9: a sign set meanwhile)
		return priceNow
	elseif id == "orders" then -- (8.9: put away meanwhile: said the next time it comes out)
		return clipboardOut
	elseif id == "visit" then -- (8.9: out of that warehouse meanwhile)
		return visitNow
	elseif id == "lobby" then -- (10.4: out of the lobby, or back in the circle, meanwhile)
		return lobbyAway
	end
	return true
end

local function show(text: string)
	local notify = SandboxHintsUi.notify
	if notify then
		notify(text)
		return
	end
	pcall(function()
		require(script.Parent.Hud).toast(text)
	end)
end

function SandboxHintsUi.step()
	-- (the player found it alone while its hint waited: no hint for it)
	if says("CollectionBookUi", "isOpen") then
		SandboxHints.found(queue, "book")
	end
	if says("SandboxTasksUi", "isOpen") then
		SandboxHints.found(queue, "tasks")
	end
	local id = SandboxHints.take(queue, clock(), covered(), still)
	if id then
		show(SandboxHints.text(id, PadGlyph.device()))
	end
end

-- The loop: every Hints.Every s while a hint waits (none: it stops).
local function look()
	if looking then
		return
	end
	looking = true
	task.spawn(function()
		while #queue.waiting > 0 do
			task.wait(H.Every)
			SandboxHintsUi.step()
		end
		looking = false
	end)
end

local function offer(id: string)
	if SandboxHints.offer(queue, id, clock()) then
		look()
	end
end

-- ── The remotes ─────────────────────────────────────────────────────────────

local function amount(value: any): number
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then math.floor(value) else 0
end

local function onBook(message: any)
	if type(message) ~= "table" or message.kind ~= "state" then
		return
	end
	local found, new = 0, 0
	if type(message.book) == "table" then
		for item, entry in message.book do
			if type(item) == "string" and type(entry) == "table" then
				found += 1
			end
		end
	end
	if type(message.new) == "table" then
		for _, item in message.new do
			if type(item) == "string" then
				new += 1
			end
		end
	end
	if SandboxHints.firstPiece(bookFound, found, new) then
		offer("book")
	end
	bookFound = found
end

local function onTasks(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.kind == "state" then
		tasksReady = math.max(0, amount(message.ready))
	elseif message.kind == "done" then
		tasksReady = math.max(tasksReady, 1) -- (its state comes after it)
		offer("tasks")
	end
end

local function onCollection(message: any)
	if type(message) ~= "table" or message.kind ~= "state" or type(message.stock) ~= "table" then
		return
	end
	local count = #message.stock
	fillNow = SandboxHints.fillWorth(message.stock, message.stands)
	if fillNow and stockSeen ~= nil and count > stockSeen then
		offer("fill") -- (pieces came home: you are at your warehouse)
	end
	stockSeen = count
	-- 8.9: pieces enough on show and no sign yet (a save's too: a player of before 8.7 hears it once)
	priceNow = SandboxHints.tradeOn() and SandboxHints.priceWorth(message.stock)
	if priceNow then
		offer("price")
	end
end

-- 8.9: another player's offer for your piece (its card first: the hint waits for it).
local function onTrade(message: any)
	if SandboxHints.tradeOn() and SandboxHints.playerOffer(message) then
		offer("deal")
	end
end

-- ── 8.9: your clipboard and where you stand ─────────────────────────────────

local player = Players.LocalPlayer

-- A warehouse's level (server/Warehouse.luau's attribute Level<id> on workspace.Warehouses; nil: not there yet, 4).
local function levelOf(plotId: number): number?
	local halls = workspace:FindFirstChild("Warehouses")
	local level = if halls then halls:GetAttribute(`Level{plotId}`) else nil
	return if type(level) == "number" then level else nil
end

-- Do you stand in another player's warehouse with a piece of theirs on show (a stand's trade prompt on)?
local function visiting(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local at = (root :: BasePart).Position
	local plot = SandboxHints.hallAt(at.X, at.Z, levelOf)
	if plot == nil or plot == player:GetAttribute("Plot") then
		return false -- (in no warehouse, or in your own: most looks end here)
	end
	local trade = Config.PlayerTrade
	table.clear(spots)
	for _, prompt in CollectionService:GetTagged(trade.PromptTag) do
		local seller = prompt:GetAttribute(trade.SellerAttribute)
		local anchor = prompt.Parent
		if prompt:IsA("ProximityPrompt") and (prompt :: ProximityPrompt).Enabled and type(seller) == "number" and anchor then
			local where: Vector3? = if anchor:IsA("Attachment") then (anchor :: Attachment).WorldPosition
				elseif anchor:IsA("BasePart") then (anchor :: BasePart).Position
				else nil
			if where then
				table.insert(spots, { x = where.X, z = where.Z, seller = seller })
			end
		end
	end
	return SandboxHints.visiting(at.X, at.Z, player.UserId, spots, levelOf)
end

function SandboxHintsUi.around()
	local character = player.Character
	clipboardOut = character ~= nil and character:GetAttribute("ClipboardHeld") == true
	if clipboardOut then
		offer("orders")
	end
	if SandboxHints.tradeOn() and not SandboxHints.seen(queue, "visit") then
		visitNow = visiting()
		if visitNow then
			offer("visit")
		end
	end
	-- 10.4: in a party lobby, away from the PLAY circle (client/RunUi.luau's PLAY view)
	local runUi = client("RunUi")
	local ok, play = pcall(function(): any
		return if runUi and type(runUi.play) == "function" then runUi.play() else nil
	end)
	lobbyAway = ok and type(play) == "table" and type(play.lobby) == "table" and play.circle ~= true
	if lobbyAway then
		offer("lobby")
	end
end

-- The look's loop: every Hints.Look s until the clipboard's hint and a visit's are both said (then it stops).
local function done(): boolean
	return SandboxHints.seen(queue, "orders") and (SandboxHints.seen(queue, "visit") or not SandboxHints.tradeOn()) and SandboxHints.seen(queue, "lobby")
end

local function watch()
	if watching then
		return
	end
	watching = true
	task.spawn(function()
		local warned = false
		while not done() do
			task.wait(H.Look)
			local ok, why = pcall(SandboxHintsUi.around :: any) -- (an error is said once, the loop goes on)
			if not ok and not warned then
				warned = true
				warn(`[SandboxHintsUi] {why}`)
			end
		end
		watching = false
	end)
end

function SandboxHintsUi.start()
	if started then
		return
	end
	started = true
	local listeners: { [string]: (any) -> () } = { CollectionBook = onBook, SandboxTasks = onTasks, Collection = onCollection, PlayerTrade = onTrade } -- (8.9: PlayerTrade)
	for name, listener in listeners do
		task.spawn(function()
			local ok, remote = pcall(Net.get, name)
			if ok then
				remote.OnClientEvent:Connect(listener)
			else
				warn(`[SandboxHintsUi] no {name} remote: {remote}`)
			end
		end)
	end
	watch() -- (8.9: your clipboard, where you stand)
end

return SandboxHintsUi
