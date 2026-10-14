--!strict
-- 8.3 SANDBOX: the first-time hints on the screen (the 8.2 review: the new features need a word the first time they
-- matter; their rules and words: shared/SandboxHints.luau). Heard from what the sandbox already sends, no hooks in the
-- other modules:
--   the "CollectionBook" remote's states   the first piece ever in your book (its state had none): "book"
--   the "SandboxTasks" remote              a task "done": "tasks" (its states say whether a reward still waits)
--   the "Collection" remote's states       pieces came home and FILL BEST has something to show: "fill"
-- A hint is one toast (SandboxHintsUi.notify: client/SandboxHud.luau's), in this device's words (client/PadGlyph.luau),
-- once a session, one at a time, never while something covers the screen: a grip check (client/CarryGripUi.luau active),
-- the move's cards with its result (client/MovingHud.luau isOpen), a sandbox window (the warehouse's, the UPGRADES
-- desk's, the book, the TASKS panel, Danny's command card, 8.3: the PAINT shop's, 8.3 review: a visitor's offer card)
-- or the start screen (the ScreenGui "SandboxHud" off). A hint no longer true when its turn comes (the reward claimed, FILL BEST used) is left out; one
-- whose window the player opened alone while it waited (the book, the TASKS panel) is not needed any more.
-- client/SandboxHud.luau starts it.
--   SandboxHintsUi.start()            listens (once; nothing when Config.Sandbox.On is false)
--   SandboxHintsUi.step()             looks once: the hint due now (the loop does it every Hints.Every s while one waits)
--   SandboxHintsUi.queue()            the hints' queue (SandboxHints.Queue: seen, waiting)
--   SandboxHintsUi.isCovered()        8.3: does something cover the screen now (as the hints wait for it)?
--   SandboxHintsUi.window()           8.3: the sandbox window open now (its module's name: "WarehouseUi", "UpgradeUi",
--                                     "VanPaintUi", …; nil: none)
--   SandboxHintsUi.busy()             8.3: a hint waits or has just shown (SandboxHints.busy)
--   (8.3: client/SandboxGuide.luau asks these three: its soft steps wait as the hints do, and while a hint talks)
--   SandboxHintsUi.notify / covered / now   hooks: the toast; what covers the screen (nil: its own look, above); the
--                                     clock (nil: os.clock)
-- Presentation only.

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

local WINDOWS = { "WarehouseUi", "UpgradeUi", "CollectionBookUi", "SandboxTasksUi", "MoveHelperCard", "VanPaintUi", "OfferCard" } -- (8.3: Danny's card, the PAINT shop too; 8.3 review: a visitor's offer)

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
end

local function sandboxOn(): boolean
	local sandbox = (Config :: any).Sandbox
	return type(sandbox) == "table" and sandbox.On == true
end

function SandboxHintsUi.start()
	if started or not sandboxOn() then
		return
	end
	started = true
	local listeners: { [string]: (any) -> () } = { CollectionBook = onBook, SandboxTasks = onTasks, Collection = onCollection }
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
end

return SandboxHintsUi
