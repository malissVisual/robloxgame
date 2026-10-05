--!strict
-- The interface: money and the driver level (the level circle, the rank, the XP bar; a flash on a level-up), the
-- minimap (client/MapView.luau) and your health, the speed dial (the car's speed, its condition, the cargo slots), the
-- active job (the objective ticket: what to do now, the route, the slots, the pay, the timer in its stub; the loading
-- bar), the utilities (MAP, CREW and the "…" menu with every other action), the consumable tags (items, keys 1-5),
-- the employers (their car and gun rewards), the shops (opened by their counters; earned guns are not sold; the car
-- guns at Wrench Garage), the weapon label (your gun, or the car gun while you drive a car that has one), the
-- backpack (with the job's cargo), the delivery result (with the XP, a level-up and the crew's pay split), toasts, the
-- FIRE button for touch screens and the way to the target (the park circle with a beam, on foot the pile / the person
-- or the vehicle's back, an arrow).
-- Driver levels (shared/Levels.luau): what your level does not reach yet shows LEVEL N (cars at the dealer, guns,
-- car guns, an employer's job); the server refuses it anyway.
-- The job board is client/DispatchUi.luau (3.6): J, the JOBS entry, the depot counter and NEXT JOB run Hud.onJobs.
-- CREW, ESTATE, MISSIONS, SOUND run the hooks Hud.onCrew (client/CrewPanel.luau), Hud.onEstate (client/EstateUi.luau),
-- Hud.onMissions (client/MissionsUi.luau) and Hud.onSound (client/Sounds.luau), set by the client's Main; Hud.setBadge
-- and Hud.flashButton mark a button (the crew's invitations). Hud.topSlot gives other modules a place in the top centre
-- stack (the crew strip and the invitation card, the mission banner, the repair timer). Calling your car (the CarCall
-- remote, server/CarCall.luau): a status line "Your car is on the way · 9 s" in the top stack, a marker over the car
-- in the world and on the maps.
-- Where everything sits on a computer and on a touch screen, so nothing overlaps: see ── Layout ── below.
-- 3.6, "Postage & Trouble" (Codex's concept, design/ui-concept/): light cream paper and powder lavender with dark plum
-- ink (Theme.Postage, through P below). The objective is a slightly tilted delivery ticket with a perforated timer stub
-- (Ui.ticket); the money and rank on a paper card over the minimap's paper frame; the weapon on a rounded label over a
-- round cream speed dial; the items as tilted pastel tags that lift, straighten and grow under the mouse (Ui.tactile);
-- MAP, CREW and a round "…" menu with every other action and its key; the windows lavender with a header (an icon
-- circle, the title, a subtitle, a round close button that turns on hover) and a footer (ESC, the context), their rows
-- paper tickets. Not everything at once: the ticket shows the job, or a small OFF DUTY ticket when the top stack is
-- empty.
-- A shop card whose def has `requires` (a campaign, or a list of them) shows "🔒 FINISH IRON SUPPLY" until it is done.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Icons = require(Shared.Icons)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Drive = require(script.Parent.Drive)
local Shooting = require(script.Parent.Shooting)
local MapView = require(script.Parent.MapView)
local Leaderboard = require(script.Parent.Leaderboard)

local C = Ui.Colors
-- 3.6: the Postage tokens (Theme.Postage: paper, lavender, the inks, sage, good / warn / danger, track, pill ...).
local P = Theme.Postage
local Hud = {}

local player = Players.LocalPlayer
local state: any = nil
local job: any = nil

local gui = Ui.make("ScreenGui", {
	Name = "ZombieDeliveryHud",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, player:WaitForChild("PlayerGui"))

-- Every top-level panel gets a UIScale so the interface fits phones too. The windows and the loading bar take the
-- screen's scale (Ui.scaleFor); the panels of the layout get theirs from layout() (── Layout ──).
local scales: { any } = {}
local function scaled(frame: any): any
	table.insert(scales, Ui.make("UIScale", {}, frame))
	return frame
end
-- A panel placed by layout(): its own UIScale, not in the list above.
local function placed(frame: any): any
	Ui.make("UIScale", { Name = "LayoutScale" }, frame)
	return frame
end
local function setScale(frame: any, value: number)
	local s = frame:FindFirstChild("LayoutScale")
	if s and s:IsA("UIScale") and math.abs(s.Scale - value) > 0.001 then
		s.Scale = value
	end
end
-- Lays the HUD out again (defined in ── Layout ──; panels that change their size ask for it).
local layoutQueued = false
local layout: () -> () = function() end
local function requestLayout()
	if layoutQueued then
		return
	end
	layoutQueued = true
	task.defer(function()
		layoutQueued = false
		layout()
	end)
end

local function myRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function nearShop(shop: string): boolean
	local root = myRoot()
	local info = Map.Shops[shop]
	return root ~= nil and info ~= nil and Vector3.new(root.Position.X - info.x, 0, root.Position.Z - info.z).Magnitude < Map.ShopRadius
end

-- ── Cargo ──────────────────────────────────────────────────────────────────

-- How one piece of each kind of cargo (Config.JobTypes itemKind) looks in the interface: the emoji, the names and
-- (art) its icon in shared/Icons.luau, shown instead of the emoji once the icon's id is filled in.
type ItemInfo = { icon: string, one: string, many: string, art: string? }
local ITEMS: { [string]: ItemInfo } = {
	crate = { icon = "📦", one = "crate", many = "crates" },
	ammo = { icon = "🧰", one = "ammo box", many = "ammo boxes" },
	sack = { icon = "🌽", one = "sack", many = "sacks" },
	barrel = { icon = "🛢️", one = "barrel", many = "barrels" },
	icebox = { icon = "🍦", one = "ice box", many = "ice boxes" },
	furniture = { icon = "🛋️", one = "furniture", many = "pieces of furniture" },
	soup = { icon = "🍲", one = "soup pot", many = "soup pots" },
	horse = { icon = "🐴", one = "horse", many = "horses" },
	kid = { icon = "🧒", one = "kid", many = "kids" },
}

local function itemInfo(kind: string?): ItemInfo
	local info = ITEMS[kind or "crate"] or { icon = "📦", one = kind or "piece", many = (kind or "piece") .. "s" }
	return { icon = info.icon, one = info.one, many = info.many, art = Icons.cargo(kind or "crate") }
end

-- The icon of a job's pieces: an ordinary delivery's business has its own look (pizza, parcel, medicine; matched by
-- the piece's name, Config.Jobs.Businesses), else the kind's.
local function cargoArt(kind: string?, piece: any): string?
	if type(piece) == "string" then
		for _, business in Config.Jobs.Businesses do
			if business.piece == piece and business.kind == kind then
				return Icons.cargo(business.look) or Icons.cargo(kind)
			end
		end
	end
	return Icons.cargo(kind or "crate")
end

-- What your hands hold right now (the Carrying attribute the server sets; the job payload as a fallback).
local function myCarrying(): string?
	local character = player.Character
	if character then
		local value = character:GetAttribute("Carrying")
		return if type(value) == "string" and value ~= "" then value else nil
	end
	return if job and type(job.carrying) == "string" then job.carrying else nil
end

-- The cargo of the job: its kind (the payload may name it; else the job type's, else what the vehicle carries).
local function jobItemKind(): string
	if not job then
		return "crate"
	end
	if type(job.itemKind) == "string" then
		return job.itemKind
	end
	if job.jobType then
		for _, def in Config.JobTypes do
			if def.name == job.jobType.name then
				return def.itemKind
			end
		end
	end
	local car = Drive.myCar()
	local kind = car and car:GetAttribute("CargoKind")
	return if type(kind) == "string" then kind else "crate"
end

-- The job's cargo for the texts: its icon and the payload's own names ("pizza box" / "pizza boxes"), else the kind's.
local function jobCargo(): ItemInfo
	local info = itemInfo(jobItemKind())
	if not job then
		return info
	end
	local one = if type(job.piece) == "string" and job.piece ~= "" then job.piece else info.one
	local many = if type(job.pieces) == "string" and job.pieces ~= "" then job.pieces else info.many
	return { icon = info.icon, one = one, many = many, art = cargoArt(jobItemKind(), job.piece) }
end

-- What is in your hands, named like the job names it when it is the job's cargo.
local function heldInfo(kind: string): ItemInfo
	return if job and kind == jobItemKind() then jobCargo() else itemInfo(kind)
end

-- Pieces riding in your vehicle (the payload, else the vehicle's CargoCount attribute).
local function inVehicle(): number?
	if job and type(job.inCar) == "number" then
		return job.inCar
	end
	local car = Drive.myCar()
	local count = car and car:GetAttribute("CargoCount")
	return if type(count) == "number" then count else nil
end

local function findEmployer(id: string?): Config.EmployerDef?
	for _, def in Config.Employers do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- ── Money ──────────────────────────────────────────────────────────────────

-- On a computer the chat sits top left: money goes bottom left above the minimap. On a touch screen top left.
-- `view` holds the refs of the 3.6 pieces that change often (the health row, the dial, the ticket, the menu, the
-- tags): one table instead of a local each (Hud.luau sits at the 200-register limit).
local touchLayout: any, LEFT_H: any, LEFT_W: any, leftStack: any, moneyLabel: any, levelChip: any, rankLabel: any, xpLabel: any, view: any, xpFill: any
do -- (its own block: the locals below stay out of the 200-register limit)
touchLayout = Ui.touchLayout()
view = {}
-- Money, the minimap and the health row share one column (one scale), so they can never overlap.
local MONEY_HEIGHT, HEALTH_HEIGHT = 76, 24
LEFT_W = 230
LEFT_H = MONEY_HEIGHT + 8 + MapView.MiniSize.Y + 8 + HEALTH_HEIGHT
leftStack = placed(Ui.make("Frame", {
	Name = "LeftStack",
	Size = UDim2.fromOffset(LEFT_W, LEFT_H),
	Position = if touchLayout then UDim2.fromOffset(16, 16) else UDim2.new(0, 16, 1, -16),
	AnchorPoint = if touchLayout then Vector2.zero else Vector2.new(0, 1),
	BackgroundTransparency = 1,
}, gui))
Ui.list(leftStack, true, 8)
-- 3.6: a paper card (the concept's wallet): the level in a lavender circle, the money big over AVAILABLE CASH, the
-- rank and a thin XP bar along the bottom; the XP numbers only on hover (or a tap on a touch screen), in a pill
-- beside the card (3.2.3).
local moneyCard = Ui.ticket(leftStack, UDim2.fromOffset(LEFT_W, MONEY_HEIGHT), UDim2.new())
local moneyHolder = moneyCard.Parent
moneyHolder.LayoutOrder = 1
levelChip = Ui.label(moneyCard, "1", UDim2.fromOffset(40, 40), {
	Position = UDim2.fromOffset(12, 9),
	BackgroundTransparency = 0,
	BackgroundColor3 = P.lavender,
	Font = Theme.DisplayFont,
	TextSize = 17,
	TextColor3 = P.ink,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = false,
	Rotation = -8,
})
Ui.corner(levelChip, 20)
Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1.5 }, levelChip)
moneyLabel = Ui.label(moneyCard, "$0", UDim2.new(1, -74, 0, 28), {
	Position = UDim2.fromOffset(62, 7),
	TextColor3 = P.ink,
	TextSize = 26,
	Font = Theme.DisplayFont,
	TextWrapped = false,
	TextScaled = true,
})
Ui.make("UITextSizeConstraint", { MaxTextSize = 26 }, moneyLabel)
Ui.caps(moneyCard, "Available cash", UDim2.new(1, -74, 0, 14), { Position = UDim2.fromOffset(62, 35), TextSize = 12, TextColor3 = P.ink2 })
local levelRow = Ui.make("Frame", { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.new(0, 12, 1, -21), BackgroundTransparency = 1 }, moneyCard)
rankLabel = Ui.caps(levelRow, "", UDim2.new(0.62, 0, 1, 0), { TextSize = 12, TextColor3 = P.ink, TextScaled = true })
Ui.make("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 9 }, rankLabel) -- (the longer ranks shrink a little)
local xpBack
xpBack, xpFill = Ui.bar(levelRow, UDim2.new(0.38, -8, 0, 5), P.violet)
xpBack.Position = UDim2.new(0.62, 8, 0.5, 0)
xpBack.AnchorPoint = Vector2.new(0, 0.5)
xpLabel = Ui.caps(moneyCard, "", UDim2.fromOffset(0, 26), {
	AutomaticSize = Enum.AutomaticSize.X,
	Position = UDim2.new(1, 14, 0.5, 0), -- to the right of the card
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundTransparency = 0,
	BackgroundColor3 = P.paper,
	TextSize = 12,
	TextColor3 = P.ink,
	Visible = false,
	ZIndex = 5,
})
Ui.corner(xpLabel, 8)
Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1 }, xpLabel)
Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, xpLabel)
moneyHolder.MouseEnter:Connect(function()
	xpLabel.Visible = xpLabel.Text ~= ""
end)
moneyHolder.MouseLeave:Connect(function()
	xpLabel.Visible = false
end)
moneyHolder.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch then
		xpLabel.Visible = not xpLabel.Visible and xpLabel.Text ~= ""
	end
end)
-- (the minimap goes between them: LayoutOrder 2, client/MapView.luau)
-- Your health under the minimap: a heart, a thin bar and the number, on a cream pill (it floats over the world).
local health = Ui.make("Frame", {
	Name = "Health",
	Size = UDim2.fromOffset(LEFT_W, HEALTH_HEIGHT),
	BackgroundColor3 = P.paper,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	LayoutOrder = 3,
}, leftStack)
Ui.corner(health, 12)
Ui.label(health, "♥", UDim2.fromOffset(22, HEALTH_HEIGHT), { Position = UDim2.fromOffset(8, 0), TextSize = 15, TextColor3 = P.danger, TextXAlignment = Enum.TextXAlignment.Center })
local healthBack
healthBack, view.healthFill = Ui.bar(health, UDim2.new(1, -84, 0, 5), P.violet)
healthBack.Position = UDim2.new(0, 36, 0.5, 0)
healthBack.AnchorPoint = Vector2.new(0, 0.5)
view.healthText = Ui.label(health, "100", UDim2.fromOffset(40, HEALTH_HEIGHT), {
	Position = UDim2.new(1, -10, 0, 0),
	AnchorPoint = Vector2.new(1, 0),
	TextSize = 14,
	Font = Theme.DisplayFont,
	TextColor3 = P.ink,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextWrapped = false,
})
view.health = -1 -- the health shown (the row redraws only when it changes)
end

-- ── Top stack ──────────────────────────────────────────────────────────────
-- Top centre, one column that grows downward (a UIListLayout: a hidden entry takes no room, so nothing overlaps):
--   1 the objective ticket (your own job; with none and nothing else on top, the small OFF DUTY ticket)
--   2 the crew slot (a member's view of the leader's job, an invitation: client/CrewPanel.luau, through Hud.topSlot)
--   3 the mission banner (3.0: client/MissionsUi.luau)
--   4 the car call line ("Your car is on the way · 9 s") or the repair timer (client/GarageUi.luau)
--   5 the level-up banner
--   6 the toasts (the newest last, MAX_TOASTS at most)
-- The ticket, the crew strip and the invitation card never show at the same time (a job of your own, a crew
-- member without one, neither); the rest stacks under whichever shows.

local TOP_W: any, topStack: any
do -- (its own block: the locals below stay out of the 200-register limit)
TOP_W = 440 -- 3.6: the objective ticket's width (the concept's 424 px)
topStack = placed(Ui.make("Frame", {
	Name = "TopStack",
	Size = UDim2.fromOffset(TOP_W, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.new(0.5, 0, 0, 14),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
}, gui))
Ui.list(topStack, true, 8, Enum.HorizontalAlignment.Center)

local SLOT_ORDER: { [string]: number } = { job = 1, crew = 2, mission = 3, carcall = 4, repair = 4, levelup = 5, toasts = 6 }
local slots: { [string]: Frame } = {}

-- A place in the top stack for another module's panel, by name ("crew"; an unknown name goes under the toasts).
-- The slot is as wide as the stack and as tall as what is visible in it (its children top down by LayoutOrder,
-- centred). It is scaled with the stack: the panels in it take no UIScale of their own.
function Hud.topSlot(name: string): Frame
	local existing = slots[name]
	if existing then
		return existing
	end
	local count = 0
	for _ in slots do
		count += 1
	end
	local slot: Frame = Ui.make("Frame", {
		Name = `Slot_{name}`,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = SLOT_ORDER[name] or (10 + count),
	}, topStack)
	Ui.list(slot, true, 8, Enum.HorizontalAlignment.Center)
	slots[name] = slot
	return slot
end
end

-- ── Toasts ─────────────────────────────────────────────────────────────────

local toasts: any
do -- (its own block: the locals below stay out of the 200-register limit)
toasts = Hud.topSlot("toasts")
local MAX_TOASTS = if touchLayout then 2 else 3
local toastOrder = 0

-- 3.6: a toast is a paper pill (a violet dot, the ink text, a thin line around it) that slides down into its place and
-- fades away up again.
function Hud.toast(text: string)
	-- Too many: the oldest goes (they never pile up into the middle of the screen).
	local shown: { any } = {}
	for _, child in toasts:GetChildren() do
		if child:GetAttribute("Toast") == true and child:GetAttribute("Leaving") ~= true then
			table.insert(shown, child)
		end
	end
	table.sort(shown, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 1, #shown - MAX_TOASTS + 1 do
		shown[index]:Destroy()
	end
	toastOrder += 1
	-- The holder keeps the place in the stack; the pill inside it moves.
	local holder = Ui.make("Frame", {
		Name = "Toast",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = toastOrder,
	}, toasts)
	holder:SetAttribute("Toast", true)
	local pill = Ui.make("Frame", {
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -14),
		BackgroundColor3 = P.paper,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, holder)
	Ui.corner(pill, 14)
	local border = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = 1 }, pill)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }, pill)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pill)
	local dot = Ui.make("Frame", { Size = UDim2.fromOffset(6, 6), BackgroundColor3 = P.violet, BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 1 }, pill)
	Ui.corner(dot, 3)
	local label = Ui.label(pill, text, UDim2.fromOffset(0, 0), {
		AutomaticSize = Enum.AutomaticSize.XY,
		TextSize = 15,
		Font = Theme.HeadingFont,
		TextColor3 = P.ink,
		TextTransparency = 1,
		LayoutOrder = 2,
	})
	-- 320: with the padding, the dot and the gap the pill stays inside the narrowest top stack (TOP_MIN_W 380).
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(320, math.huge) }, label)
	-- In: slide down and fade in. Out: up and away.
	local function fade(info: TweenInfo, y: number, gone: boolean)
		local t = if gone then 1 else 0
		TweenService:Create(pill, info, { Position = UDim2.new(0.5, 0, 0, y), BackgroundTransparency = if gone then 1 else 0.04 }):Play()
		TweenService:Create(border, info, { Transparency = t }):Play()
		TweenService:Create(dot, info, { BackgroundTransparency = t }):Play()
		TweenService:Create(label, info, { TextTransparency = t }):Play()
	end
	fade(TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), 0, false)
	task.delay(3, function()
		if not holder.Parent then
			return
		end
		holder:SetAttribute("Leaving", true)
		fade(TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), -10, true)
		task.wait(0.4)
		holder:Destroy()
	end)
end
end

-- ── Windows ────────────────────────────────────────────────────────────────

local windows: { any } = {}

-- Does the interface need the mouse right now (a window or the big map is open)?
function Hud.anyWindowOpen(): boolean
	if MapView.isOpen() or (view and view.menu and view.menu.Visible) then
		return true -- (the "…" menu frees the mouse like a window: CAR and GIVE UP have no key)
	end
	for _, w in windows do
		if w.Visible then
			return true
		end
	end
	return false
end

-- Set by client/Main.client.luau: closes the windows outside the HUD too (the crew window).
Hud.onCloseWindows = nil :: (() -> ())?

local function closeWindows()
	for _, w in windows do
		w.Visible = false
	end
	if view.menu then
		view.menu.Visible = false -- (the "…" menu, 3.6)
	end
	Leaderboard.close()
	local cb = Hud.onCloseWindows
	if cb then
		cb()
	end
end
Hud.closeWindows = closeWindows
-- One window at a time: the leaderboard (L) closes the HUD's windows too.
Leaderboard.onOpen = closeWindows

type Window = { frame: any, body: any, title: any, subtitle: any, icon: any, footer: any }

-- 3.6: the concept's window (Ui.window, design/ui-concept/previews/garage.png): a lavender surface; a header with an
-- icon in a sage circle, the title and a subtitle, the round close button; the body scrolls; a footer with ESC · Close
-- window and the context on the right (window.footer, set by each window).
local function window(title: string, size: Vector2, icon: string, subtitle: string): Window
	local frame, content, chrome = Ui.window(gui, title, subtitle, icon, UDim2.fromOffset(size.X, size.Y))
	scaled(frame)
	frame.Visible = false
	frame.ZIndex = 5
	local body = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -28, 1, -12),
		Position = UDim2.fromOffset(14, 6),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = P.violet,
		ScrollBarImageTransparency = 0.4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, content)
	Ui.list(body, true, 10)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 4) }, body)
	table.insert(windows, frame)
	return { frame = frame, body = body, title = chrome.title, subtitle = chrome.subtitle, icon = chrome.icon, footer = chrome.context }
end

-- 3.6: a list row is a paper ticket: a soft shadow under it, and (unless `plain`) a perforation with two notches
-- left of the button column. Returns the ticket (its children are placed like the old card's).
local function card(parent: any, height: number, order: number, highlight: boolean?, plain: boolean?): any
	local holder = Ui.make("Frame", {
		Size = UDim2.new(1, -12, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)
	local shadow = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 4),
		BackgroundColor3 = P.line,
		BorderSizePixel = 0,
	}, holder)
	Ui.corner(shadow, 8)
	local frame = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.ticket,
		BorderSizePixel = 0,
	}, holder)
	Ui.corner(frame, 8)
	if not plain then
		Ui.make("Frame", { Size = UDim2.new(0, 1, 1, -16), Position = UDim2.new(1, -174, 0, 8), BackgroundColor3 = P.line, BorderSizePixel = 0 }, frame)
		for _, y in { 0, 1 } do
			local notch = Ui.make("Frame", {
				Size = UDim2.fromOffset(12, 12),
				Position = UDim2.new(1, -174, y, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = P.lavender,
				BorderSizePixel = 0,
			}, frame)
			Ui.corner(notch, 6)
		end
	end
	if highlight then
		-- The one that matters here: a violet line around it and a violet edge.
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.violet, Thickness = 1.5 }, frame)
		Ui.edge(frame, P.violet, 5)
	end
	return frame
end

-- name / stats / description on the left of a card.
local function cardText(c: any, name: string, stats: string, description: string, left: number?)
	local x = left or 16
	Ui.label(c, name, UDim2.new(1, -190 - x, 0, 26), { Position = UDim2.fromOffset(x, 6), TextSize = 19, Font = Theme.DisplayFont, TextColor3 = P.ink, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.label(c, stats, UDim2.new(1, -190 - x, 0, 20), { Position = UDim2.fromOffset(x, 33), TextColor3 = P.violet, TextSize = 14, Font = Theme.HeadingFont, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.label(c, description, UDim2.new(1, -190 - x, 0, 20), { Position = UDim2.fromOffset(x, 55), TextColor3 = P.ink2, TextSize = 14, Font = Theme.Font })
end

-- The button of a card, right of its perforation: the main action sage (a secondary one, `color` C.blue, lavender),
-- what you cannot press a quiet lavender one with the reason in it.
local function cardButton(parent: any, text: string, color: Color3, enabled: boolean, onClick: () -> (), slot: number?): any
	local function press()
		if enabled then
			onClick()
		end
	end
	local button = if enabled then Ui.button(parent, text, UDim2.fromOffset(150, 42), if color == C.blue then P.lavenderDeep else P.sage, press) else Ui.ghostButton(parent, text, UDim2.fromOffset(150, 42), nil, press)
	button.AutoButtonColor = enabled
	button.TextSize = 15
	button.TextColor3 = if enabled then P.ink else P.ink2
	if not enabled then
		button.BackgroundColor3 = P.lavenderDeep
		button.BackgroundTransparency = 0
		Ui.stroke(button, P.line, 1).Transparency = 0
	end
	local n = slot or 0
	button.Position = UDim2.new(1, -162, 0, if n == 0 then 21 else 2 + (n - 1) * 44)
	return button
end

local function tabs(parent: any, list: { { string } }, selected: string, onPick: (string) -> ())
	local row = Ui.make("Frame", { Size = UDim2.new(1, -12, 0, 40), BackgroundTransparency = 1, LayoutOrder = 0 }, parent)
	Ui.list(row, false, 8)
	for _, entry in list do
		-- 3.6: the open tab sage, the others quiet lavender.
		local on = entry[1] == selected
		local button = if on then Ui.button(row, entry[2], UDim2.fromOffset(140, 36), P.sage, function()
				onPick(entry[1])
			end)
			else Ui.ghostButton(row, entry[2], UDim2.fromOffset(140, 36), nil, function()
				onPick(entry[1])
			end)
		button.TextSize = 14
		button.TextColor3 = if on then P.ink else P.ink2
		if not on then
			button.BackgroundColor3 = P.lavenderDeep
			button.BackgroundTransparency = 0
		end
	end
end

-- A line of text in a window (C.red: a warning, in the danger ink).
local function note(parent: any, text: string, color: Color3, order: number)
	Ui.label(parent, text, UDim2.new(1, -12, 0, 22), { LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = if color == C.red then P.danger else P.ink2, TextSize = 14, Font = Theme.Font })
end

-- ── Driver level ───────────────────────────────────────────────────────────
-- The XP comes with the player attribute Xp (server/PlayerData.luau), or the state's xp; nil until the save loaded.

local function myXp(): number?
	local xp = tonumber(player:GetAttribute("Xp"))
	if xp == nil and state and type(state.xp) == "number" then
		xp = state.xp
	end
	return xp
end

local function myLevel(): number
	return Levels.levelFor(myXp() or 0)
end

-- The level something needs (its level field) when yours is lower, else nil.
local function lockedAt(level: number?): number?
	return if level ~= nil and level > myLevel() then level else nil
end

-- A card's button for something your level does not reach yet.
local function lockButton(c: any, level: number): any
	local button = cardButton(c, `🔒 LEVEL {level}`, C.grey, false, function() end)
	button.TextColor3 = P.ink2
	return button
end

-- What a level unlocks, in words: danger levels, special jobs, cars, guns and car guns.
local function unlocksAt(level: number): { string }
	local list: { string } = {}
	for _, tier in Config.Jobs.Tiers do
		if tier.level == level and level > 1 then
			table.insert(list, `{string.rep("★", tier.stars)} {tier.name} jobs`)
		end
	end
	for _, def in Config.JobTypes do
		if def.level == level and level > 1 then
			table.insert(list, def.name)
		end
	end
	for _, def in Config.Cars do
		if def.level == level and not def.company then
			table.insert(list, def.name)
		end
		-- 3.5: a stage of a car you own (Wrench Garage).
		local stages: { Config.StageDef } = def.stages or {}
		for n, stage in stages do
			if n > 1 and stage.level == level and state and type(state.cars) == "table" and state.cars[def.id] then
				table.insert(list, `the {stage.name} stage`)
			end
		end
	end
	for _, def in Config.Weapons do
		if def.level == level and not def.earned then
			table.insert(list, def.name)
		end
	end
	for _, def in Config.CarGuns do
		if def.level == level then
			table.insert(list, def.name)
		end
	end
	return list
end

-- ── Icons ──────────────────────────────────────────────────────────────────
-- The icon set (shared/Icons.luau). While an icon's id is empty everything below draws exactly what the interface
-- always drew (the emoji); a filled-in id swaps the emoji for the picture.

-- The picture on the left of a shop / backpack card (the icon, else the emoji; nothing when there is neither).
-- Returns where the card's text starts (nil = the usual place).
local function cardIcon(c: any, iconName: string?, fallback: string?, y: number): number?
	if fallback == nil and not Icons.get(iconName) then
		return nil
	end
	Ui.icon(c, iconName, fallback or "", UDim2.fromOffset(50, 50), { Position = UDim2.fromOffset(10, y), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center })
	return 70
end

-- A line of text with an icon in it: before .. icon .. after. Without the icon's id it is the one label it always
-- was (the emoji inside the text); with it a row of the text before, the icon (tinted like the text) and the rest.
local ROW_KEYS = { Position = true, AnchorPoint = true, LayoutOrder = true }
local function iconText(parent: any, iconName: string?, emoji: string, before: string, after: string, size: UDim2, props: { [string]: any }): any
	if not Icons.get(iconName) then
		return Ui.label(parent, before .. emoji .. after, size, props)
	end
	local row = Ui.make("Frame", { Size = size, BackgroundTransparency = 1, ClipsDescendants = true }, parent)
	local textProps: { [string]: any } = {}
	for key, value in props do
		if ROW_KEYS[key] then
			row[key] = value
		else
			textProps[key] = value
		end
	end
	if textProps.AutomaticSize == Enum.AutomaticSize.Y then
		textProps.AutomaticSize = nil
	end
	if textProps.ZIndex then
		row.ZIndex = textProps.ZIndex
	end
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local textSize = tonumber(textProps.TextSize) or 18
	local function part(text: string, order: number)
		if text == "" then
			return
		end
		local label = Ui.label(row, text, UDim2.new(0, 0, 1, 0), textProps)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.TextWrapped = false
		label.LayoutOrder = order
	end
	part((before:gsub("%s+$", "")), 1)
	Ui.icon(row, iconName, emoji, UDim2.fromOffset(textSize + 4, textSize + 4), { LayoutOrder = 2, ImageColor3 = textProps.TextColor3 or P.ink, ZIndex = textProps.ZIndex })
	part((after:gsub("^%s+", "")), 3)
	return row
end

-- ── Job board ──────────────────────────────────────────────────────────────
-- 3.6: the job board is the Dispatch board (client/DispatchUi.luau): J, the JOBS entry of the "…" menu, the depot's
-- job counter (OpenShop "jobs"), the OFF DUTY ticket and NEXT JOB run Hud.onJobs.

-- Set by client/Main.client.luau: JOBS opens / closes the Dispatch board (DispatchUi.toggle); CREW the crew window
-- (CrewPanel.toggle), ESTATE the list of every property (EstateUi.toggleList), MISSIONS the missions window, SOUND the
-- sound setting. Unset, the button says what it is for (CrewPanel.start sets onCrew by itself too).
Hud.onJobs = nil :: (() -> ())? -- 3.6 client/DispatchUi.luau: the Dispatch board (J / JOBS)
Hud.onCrew = nil :: (() -> ())?
Hud.onEstate = nil :: (() -> ())?
Hud.onSound = nil :: (() -> ())? -- client/Sounds.luau: music and effects on / music off / all off
Hud.onMissions = nil :: (() -> ())? -- client/MissionsUi.luau: the MISSIONS window

local openDispatch: () -> ()
do -- (its own block: the locals below stay out of the 200-register limit)
function openDispatch()
	local cb = Hud.onJobs
	if cb then
		cb()
	else
		Hud.toast("The dispatch board is not ready yet.")
	end
end
end

-- ── Shops ──────────────────────────────────────────────────────────────────

local shop = window("Shop", Vector2.new(700, 540), "🏪", "")
local shopId = "dealer"
local shopFocus: string? = nil
local mechanicTab = "upgrades"

-- 3.5: with a car's own levels its stage's numbers (the stage's name first); without (the dealer's catalog) the room
-- it has from stage 0 to its last stage.
local function carStats(def: Config.CarDef, levels: { [string]: number }?): string
	if levels then
		local stats = Economy.carStats(def.id, levels)
		local stage = Economy.stageDef(def.id, Economy.stageOf(def.id, levels))
		local prefix = if stage and stage.name ~= def.name then `{stage.name} · ` else ""
		return `{prefix}Speed {math.floor(stats.maxSpeed + 0.5)} · Health {stats.health} · 📦 {Economy.capacity(def.id, levels)} slots`
	end
	local most = Economy.maxCapacity(def.id)
	return `Speed {def.maxSpeed} · Health {def.health} · Ram x{def.ramPower} · 📦 {if most > def.capacity then `{def.capacity} → {most}` else def.capacity} slots`
end

-- Damage, rate, range (and pellets, blast) of a hand gun or a car gun.
local function gunStats(def: { damage: number, pellets: number, fireRate: number, range: number, splash: number }): string
	local pellets = if def.pellets > 1 then ` x{def.pellets}` else ""
	local splash = if def.splash > 0 then ` · Blast {def.splash}` else ""
	return `Damage {def.damage}{pellets} · {def.fireRate}/s · Range {def.range}{splash}`
end

-- The cars a car gun fits on (CarDef.mount), by name.
local function mountableCars(): string
	local names = {}
	for _, def in Config.Cars do
		if def.mount then
			table.insert(names, def.name)
		end
	end
	return table.concat(names, ", ")
end

local function renderShop()
	Ui.clear(shop.body)
	if not state then
		return
	end
	-- 3.1: the exclusive guns and paints (WeaponDef / PaintDef.exclusive) are never sold. Not yours yet: a dimmed card
	-- with a REWARD chip and how to earn it (Config.Rewards: a campaign, every lost package, or a secret: the
	-- every-challenge gun keeps even its stats hidden). Yours: the normal card with an EXCLUSIVE badge.
	-- (Locals in here, not at the top: Hud.luau sits at the 200-register limit.)
	local function rewardHow(exclusive: string): (string, string)
		if exclusive == "challenges" then
			return "???", "a secret reward"
		elseif exclusive == "secrets" then
			return "REWARD", "find every lost package"
		end
		for _, campaign in require(Shared.Missions).Campaigns do
			if campaign.id == exclusive then
				return "REWARD", `finish {campaign.name}`
			end
		end
		return "REWARD", "a reward"
	end
	local function badge(c: any, text: string, color: Color3, y: number)
		-- 3.6: an exclusive (Ui.Gps) on violet with paper text, a reward on sage with ink.
		local chip = Ui.chip(c, text, if color == Ui.Gps then P.violet else P.sage, if color == Ui.Gps then P.paper else P.ink)
		chip.Size = UDim2.fromOffset(0, 18)
		chip.Position = UDim2.new(1, -162, 0, y)
		chip.TextSize = 12
		chip.ZIndex = 3
	end
	local function rewardCard(c: any, exclusive: string)
		-- Dim what is on the card so far (the name, the stats, the swatch), then the bright chip and the how-to.
		c.BackgroundTransparency = 0.45
		for _, d in c:GetChildren() do
			if d:IsA("TextLabel") then
				d.TextTransparency = 0.35
			elseif d:IsA("Frame") then
				d.BackgroundTransparency = 0.35
			end
		end
		local chip, how = rewardHow(exclusive)
		badge(c, if chip == "???" then "???  SECRET" else "🏆 REWARD", C.yellow, 2)
		local button = cardButton(c, how, C.grey, false, function() end)
		button.TextSize = 13
		button.TextWrapped = true
		button.TextColor3 = P.ink
	end
	-- 3.2: a def may need a campaign finished first (`requires`: a campaign id or a list of them; the server checks
	-- it too). The first one not finished yet, as "Finish Iron Supply", else nil.
	local function needs(def: any, owned: boolean): string?
		local list: any = def.requires
		if owned or list == nil then
			return nil
		end
		if type(list) == "string" then
			list = { list }
		end
		if type(list) ~= "table" then
			return nil
		end
		local Missions = require(Shared.Missions)
		for _, id in list do
			if type(id) ~= "string" or (type(state.campaigns) == "table" and state.campaigns[id] == true) then
				continue
			end
			local missions = Missions.ofCampaign(id)
			local finale = missions[#missions]
			if not (finale and type(state.missions) == "table" and state.missions[finale.id]) then
				local campaign = Missions.findCampaign(id)
				return `Finish {if campaign then campaign.name else id}`
			end
		end
		return nil
	end
	local function needsButton(c: any, text: string)
		local button = cardButton(c, `🔒 {string.upper(text)}`, C.grey, false, function() end)
		button.TextSize = 12
		button.TextWrapped = true
		button.Activated:Connect(function()
			Hud.toast(`{text} first: it opens with that campaign (MISSIONS, U).`)
		end)
	end
	local money = state.money
	local here = nearShop(shopId)
	-- 3.6: the header (the shop's name, what it sells, its icon) and the footer (at the counter or not, your money).
	shop.title.Text = Map.Shops[shopId] and Map.Shops[shopId].name or "Shop"
	local about = ({
		dealer = { "🚗", "The catalog · every car has a role" },
		depot = { "🅿", "Your cars at the depot lot" },
		guns = { "🔫", "Guns for your hands" },
		supplies = { "🧰", "Supplies for the road" },
		mechanic = { "🔧", "Upgrades, stages, paint and car guns" },
	} :: { [string]: { string } })[shopId] or { "🏪", "" }
	shop.icon.Text = about[1]
	shop.subtitle.Text = about[2]
	shop.footer.Text = `{if here then "At the counter" else "Walk in to buy"} · {Ui.money(money)}`
	if not here then
		note(shop.body, "Walk into the shop to buy here.", C.red, 1)
	end
	if shopId == "dealer" then
		-- 3.4: every car you own takes a garage slot (the company vehicles none); a new one needs a free one.
		local owned = 0
		for id, yes in state.cars do
			local def = Economy.findCar(id)
			if yes and def and not def.company then
				owned += 1
			end
		end
		local full = owned >= (tonumber(player:GetAttribute("CarSlots")) or Config.Estate.BaseCarSlots)
		-- 3.5: not "the next van": every car has a role, and its own stages at Wrench Garage (📦 from → to).
		note(shop.body, "The catalog. Every car has a role and builds up in stages at Wrench Garage (📦 slots from → to). A van ends at 4 slots: more needs the High-Roof Van or the Box Truck.", C.dim, 1)
		for order, def in Config.Cars do
			if def.company then
				continue
			end
			local c = card(shop.body, 100, order + 1, def.id == shopFocus)
			local lock = if state.cars[def.id] then nil else lockedAt(def.level)
			local need = needs(def, state.cars[def.id] == true)
			cardText(c, def.name, carStats(def) .. (if lock then ` · from level {lock}` else "") .. (if need then ` · {need}` else ""), def.description)
			if def.role then
				Ui.label(c, `ROLE · {string.upper(def.role)}`, UDim2.new(1, -206, 0, 16), { Position = UDim2.fromOffset(16, 78), TextColor3 = P.violet, TextSize = 12, Font = Theme.HeadingFont })
			end
			if state.car == def.id then
				cardButton(c, "YOUR CAR", C.grey, false, function() end)
			elseif state.cars[def.id] then
				-- 3.4: your cars wait in your garages; you switch them only there.
				cardButton(c, "IN GARAGE", C.grey, true, function()
					Hud.toast("Switch cars at one of your garages (🅿 GARAGE), or at the depot lot for your starting van.")
				end)
			elseif lock then
				lockButton(c, lock)
			elseif need then
				needsButton(c, need)
			elseif full then
				local garage = cardButton(c, "🅿 NEEDS A GARAGE", C.grey, true, function()
					Hud.toast("No free garage slot. Buy or rent a garage (ESTATE, H) first.")
				end)
				garage.TextSize = 12
				garage.TextColor3 = P.ink2
			else
				cardButton(c, `BUY {Ui.money(def.price)}`, C.green, here and money >= def.price, function()
					Net.get("Buy"):FireServer("car", def.id)
				end)
			end
		end
	elseif shopId == "depot" then
		note(shop.body, "Your cars. The depot lot keeps your starting van; the others wait in your garages (🅿 GARAGE). Buy new ones at Dead End Motors (next door, east).", C.dim, 1)
		for order, def in Config.Cars do
			if not state.cars[def.id] then
				continue
			end
			local c = card(shop.body, 84, order + 1)
			cardText(c, def.name, carStats(def, Economy.carLevels(state.carUpgrades, def.id)), def.description)
			if state.car == def.id then
				cardButton(c, "DRIVING", C.grey, false, function() end)
			else
				cardButton(c, "TAKE IT", C.blue, here, function()
					Net.get("Equip"):FireServer("car", def.id)
				end)
			end
		end
	elseif shopId == "guns" then
		note(shop.body, "Guns for your hands. One-handed ones (pistol, revolver, SMG) also fire out of a car window; car guns are at Wrench Garage.", C.dim, 1)
		for order, def in Config.Weapons do
			local c = card(shop.body, 84, order + 1)
			local lock = if state.weapons[def.id] or def.earned or def.exclusive then nil else lockedAt(def.level)
			local need = if def.earned or def.exclusive then nil else needs(def, state.weapons[def.id] == true)
			local exclusive = def.exclusive
			if exclusive and exclusive == "challenges" and not state.weapons[def.id] then
				-- The gun nobody else has: an ink silhouette, nothing given away.
				Ui.icon(c, Icons.weapon(def.id), "❔", UDim2.fromOffset(50, 50), { Position = UDim2.fromOffset(10, 17), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, ImageColor3 = P.ink })
				cardText(c, "???", "Damage ??? · ???/s · Range ???", "Nobody has ever seen it. Some say it waits for the courier who does everything.", 70)
			else
				cardText(c, def.name, gunStats(def) .. (if def.pierce then ` · Pierces {def.pierce}` else "") .. (if def.oneHanded then " · One-handed" else "") .. (if lock then ` · from level {lock}` else "") .. (if need then ` · {need}` else ""), def.description, cardIcon(c, Icons.weapon(def.id), nil, 17))
			end
			if exclusive and state.weapons[def.id] then
				badge(c, "★ EXCLUSIVE", Ui.Gps, 2)
			end
			if exclusive and not state.weapons[def.id] then
				rewardCard(c, exclusive)
			elseif state.weapon == def.id then
				cardButton(c, "IN HAND", C.grey, false, function() end)
			elseif state.weapons[def.id] then
				cardButton(c, "EQUIP", C.blue, true, function()
					Net.get("Equip"):FireServer("weapon", def.id)
				end)
			elseif def.earned then
				-- Not for sale: you earn it by working.
				local employer = findEmployer(def.earned)
				local button = cardButton(c, `Earned at {if employer then employer.name else def.earned}`, C.grey, false, function() end)
				button.TextSize = 13
				button.TextWrapped = true
			elseif lock then
				lockButton(c, lock)
			elseif need then
				needsButton(c, need)
			else
				cardButton(c, `BUY {Ui.money(def.price)}`, C.green, here and money >= def.price, function()
					Net.get("Buy"):FireServer("weapon", def.id)
				end)
			end
		end
	elseif shopId == "supplies" then
		for order, def in Config.Items do
			local c = card(shop.body, 90, order + 1)
			local have = state.items[def.id] or 0
			cardText(c, def.name, `{Ui.money(def.price)} each · you have {have}/{def.max}`, def.description, cardIcon(c, Icons.item(def.id), def.icon, 18))
			cardButton(c, `BUY 1  {Ui.money(def.price)}`, C.green, here and money >= def.price and have < def.max, function()
				Net.get("Buy"):FireServer("item", def.id, 1)
			end, 1)
			cardButton(c, `BUY 5  {Ui.money(def.price * 5)}`, C.green, here and money >= def.price * 5 and have + 5 <= def.max, function()
				Net.get("Buy"):FireServer("item", def.id, 5)
			end, 2)
		end
	elseif shopId == "mechanic" then
		tabs(shop.body, { { "upgrades", "UPGRADES" }, { "paint", "PAINT" }, { "carguns", "CAR GUNS" } }, mechanicTab, function(id)
			mechanicTab = id
			renderShop()
		end)
		if mechanicTab == "upgrades" then
			-- 3.3: the car tracks belong to the equipped car (its own levels, shown on it); the gun tracks to every gun.
			local upCar = Economy.findCar(state.car)
			local carOk = upCar ~= nil and Economy.canUpgrade(upCar.id)
			local carLevels = Economy.carLevels(state.carUpgrades, state.car)
			if carOk then
				note(shop.body, `Upgrades for: {Economy.carTitle(state.car, carLevels)} (📦 {Economy.capacity(state.car, carLevels)} cargo slots). They stay on this car and show on it (bull bar, plates, scoop); a STAGE rebuilds the car itself. Repairs: drive into a repair bay here, get out and wait.`, C.dim, 1)
			else
				note(shop.body, `Your {if upCar then upCar.name else "vehicle"} is a company vehicle: it can't be upgraded. Take one of your own cars out of your garage.`, C.red, 1)
			end
			local row = 1
			-- 3.5: the STAGE card: the car's next stage (its new look, its room, before → after) or its last one.
			if carOk and upCar and Economy.maxStage(upCar.id) > 0 then
				row += 1
				local stage = Economy.stageOf(upCar.id, carLevels)
				local last = Economy.maxStage(upCar.id)
				local now = Economy.stageDef(upCar.id, stage)
				local nextStage = Economy.stageDef(upCar.id, stage + 1)
				local c = card(shop.body, 112, row, nextStage ~= nil)
				local pips = string.rep("■", stage) .. string.rep("□", last - stage)
				local nowName = if now then now.name else upCar.name
				if nextStage then
					local after = table.clone(carLevels)
					after.stage = stage + 1
					local a, b = Economy.carStats(upCar.id, carLevels), Economy.carStats(upCar.id, after)
					cardText(c, `STAGE {stage + 1}/{last}: {nextStage.name}`, `{pips}  {nowName} → {nextStage.name}`, `Adds {nextStage.adds}.`)
					Ui.label(c, `📦 {Economy.capacity(upCar.id, carLevels)} → {nextStage.capacity} slots · Health {a.health} → {b.health} · Speed {math.floor(a.maxSpeed + 0.5)} → {math.floor(b.maxSpeed + 0.5)}`, UDim2.new(1, -206, 0, 18), {
						Position = UDim2.fromOffset(16, 80),
						TextColor3 = P.good,
						TextSize = 14,
						Font = Theme.HeadingFont,
					})
					local lock = lockedAt(nextStage.level)
					if lock then
						lockButton(c, lock)
					else
						cardButton(c, `STAGE UP {Ui.money(nextStage.price)}`, C.green, here and money >= nextStage.price, function()
							Net.get("Upgrade"):FireServer("stage")
						end)
					end
				else
					cardText(c, `STAGE {stage}/{last}: {nowName}`, `{pips}  the last stage · 📦 {Economy.capacity(upCar.id, carLevels)} slots`, `Your {upCar.name} is all it can be. More room needs a bigger vehicle (Dead End Motors).`)
					cardButton(c, "LAST STAGE", C.grey, false, function() end)
				end
			end
			for pass = 1, 2 do
				if pass == 2 then
					row += 1
					note(shop.body, "For all your guns (car guns too):", C.dim, row)
				end
				for _, def in Config.Upgrades do
					if (def.car == true) ~= (pass == 1) then
						continue
					end
					row += 1
					local c = card(shop.body, 84, row)
					local level = Economy.level(if def.car then carLevels else state.upgrades, def.id)
					cardText(c, def.name, string.rep("■", level) .. string.rep("□", def.maxLevel - level) .. `  Lv {level}/{def.maxLevel}`, def.description)
					local cost = Economy.upgradeCost(def.id, level)
					if def.car and not carOk then
						cardButton(c, "COMPANY CAR", C.grey, false, function() end)
					elseif cost then
						cardButton(c, `UPGRADE {Ui.money(cost)}`, C.green, here and money >= cost, function()
							Net.get("Upgrade"):FireServer(def.id)
						end)
					else
						cardButton(c, "MAX", C.grey, false, function() end)
					end
				end
			end
		elseif mechanicTab == "carguns" then
			-- One gun on the roof of the car you have equipped; the driver fires it.
			local carDef = Economy.findCar(state.car)
			local carName = if carDef then carDef.name else "car"
			local canMount = carDef ~= nil and carDef.mount == true
			local carGuns = state.carGuns or {}
			local installed: string? = if canMount then carGuns[state.car] else nil
			if canMount then
				local current = if installed then Economy.findCarGun(installed) else nil
				note(shop.body, `CAR GUNS for your {carName}: {if current then current.name else "no gun yet"}. On the roof, the driver fires it. A new one replaces the old one (no refund); Gun Damage and Fire Rate upgrades work for car guns too.`, C.dim, 1)
			else
				note(shop.body, `This vehicle can't carry a gun (your {carName}). Car guns fit: {mountableCars()}.`, C.red, 1)
			end
			for order, def in Config.CarGuns do
				local c = card(shop.body, 84, order + 1, installed == def.id)
				local lock = if installed == def.id then nil else lockedAt(def.level)
				local need = needs(def, installed == def.id)
				cardText(c, def.name, `{gunStats(def)} · {Ui.money(def.price)}` .. (if lock then ` · from level {lock}` else "") .. (if need then ` · {need}` else ""), def.description)
				if installed == def.id then
					cardButton(c, "INSTALLED", C.grey, false, function() end)
				elseif not canMount then
					cardButton(c, "CAN'T MOUNT", C.grey, false, function() end)
				elseif lock then
					lockButton(c, lock)
				elseif need then
					needsButton(c, need)
				else
					cardButton(c, `BUY {Ui.money(def.price)}`, C.green, here and money >= def.price, function()
						Net.get("Buy"):FireServer("cargun", def.id)
					end)
				end
			end
		else
			local carDef = Economy.findCar(state.car)
			note(shop.body, `Paint for your {if carDef then carDef.name else "car"}. Bought paints are yours for every car.`, C.dim, 1)
			local current = state.carPaint[state.car] or "factory"
			for order, def in Config.Paints do
				-- 3.1: an exclusive paint's card is taller (its chip sits above the button).
				local c = card(shop.body, if def.exclusive then 84 else 70, order + 1)
				local swatchColor = if def.color then Color3.fromRGB(def.color[1], def.color[2], def.color[3]) elseif carDef then Color3.fromRGB(carDef.color[1], carDef.color[2], carDef.color[3]) else C.grey
				local swatch = Ui.make("Frame", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(12, if def.exclusive then 20 else 13), BackgroundColor3 = swatchColor }, c)
				Ui.corner(swatch, 8)
				Ui.stroke(swatch, if def.material == "Neon" then swatchColor:Lerp(P.paper, 0.5) else P.ink, 2)
				Ui.label(c, def.name, UDim2.new(1, -260, 0, 26), { Position = UDim2.fromOffset(70, 8), TextSize = 20, Font = Enum.Font.GothamBlack, TextColor3 = P.ink })
				-- The finish (PaintDef.material) after the price: "Owned · Neon finish".
				local finish = if def.material then ` · {def.material} finish` else ""
				Ui.label(c, (if state.paints[def.id] then "Owned" elseif def.exclusive then "Never sold" else Ui.money(def.price)) .. finish, UDim2.new(1, -260, 0, 20), { Position = UDim2.fromOffset(70, 36), TextColor3 = P.violet, TextSize = 15 })
				local exclusive = def.exclusive
				if exclusive then
					if state.paints[def.id] then
						badge(c, "★ EXCLUSIVE", Ui.Gps, 2)
					else
						rewardCard(c, exclusive)
						continue
					end
				end
				local y = if exclusive then 22 else 15
				if current == def.id then
					cardButton(c, "ON YOUR CAR", C.grey, false, function() end).Position = UDim2.new(1, -162, 0, y)
				elseif state.paints[def.id] then
					cardButton(c, "APPLY", C.blue, here, function()
						Net.get("Paint"):FireServer(def.id)
					end).Position = UDim2.new(1, -162, 0, y)
				else
					cardButton(c, `BUY {Ui.money(def.price)}`, C.green, here and money >= def.price, function()
						Net.get("Paint"):FireServer(def.id)
					end).Position = UDim2.new(1, -162, 0, y)
				end
			end
		end
	end
end

-- ── Employers ──────────────────────────────────────────────────────────────

do -- (its own block: the locals below stay out of the 200-register limit)
local employerWindow = window("Work", Vector2.new(580, 560), "💼", "")

-- How the cargo of a job type gets in and out, in a few words.
local HANDLING_TEXT: { [string]: string } = {
	carry = "you carry them by hand",
	lead = "you lead them on a rope",
	board = "they get on and off by themselves",
	serve = "the customers come to your truck",
}

-- A reward row of the employer window: what, a bar of the jobs done toward it, yours or not yet.
-- (iconName: the reward's icon in shared/Icons.luau, nil = the emoji `icon`.)
local function rewardRow(parent: any, order: number, iconName: string?, icon: string, name: string, done: number, at: number, owned: boolean)
	local row = card(parent, 64, order, owned, true)
	Ui.icon(row, iconName, icon, UDim2.fromOffset(40, 40), { Position = UDim2.fromOffset(12, 12), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, ImageColor3 = P.ink })
	Ui.label(row, name, UDim2.new(1, -200, 0, 24), { Position = UDim2.fromOffset(64, 8), TextSize = 19, Font = Enum.Font.GothamBlack, TextColor3 = P.ink })
	Ui.label(row, if owned then "YOURS" else `{math.min(done, at)}/{at} jobs`, UDim2.fromOffset(120, 24), {
		Position = UDim2.new(1, -132, 0, 8),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = if owned then P.good else P.violet,
		TextSize = 17,
		Font = Enum.Font.GothamBlack,
	})
	local back, fill = Ui.bar(row, UDim2.new(1, -78, 0, 10), if owned then P.good else P.violet)
	back.Position = UDim2.fromOffset(64, 40)
	fill.Size = UDim2.fromScale(if owned then 1 else math.clamp(done / math.max(at, 1), 0, 1), 1)
end

local function openEmployer(id: string)
	closeWindows()
	local employer = findEmployer(id)
	if not employer or not state then
		return
	end
	local jobType: Config.JobTypeDef? = nil
	for _, def in Config.JobTypes do
		if def.id == employer.jobType then
			jobType = def
		end
	end
	local reward = Economy.findCar(employer.reward)
	local gun = if employer.weapon then Economy.findWeapon(employer.weapon) else nil
	local body = employerWindow.body
	Ui.clear(body)
	employerWindow.title.Text = employer.name
	employerWindow.icon.Text = employer.icon
	employerWindow.subtitle.Text = `{employer.person} · they lend you the vehicle`
	employerWindow.footer.Text = `{state.rep[employer.id] or 0} jobs done here`
	employerWindow.frame.Visible = true
	-- The person who runs it, and what they say.
	Ui.label(body, employer.person, UDim2.new(1, -10, 0, 20), { LayoutOrder = 1, TextColor3 = P.violet, TextSize = 15 })
	Ui.label(body, `"{employer.pitch}"`, UDim2.new(1, -10, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		TextColor3 = P.ink,
		TextSize = 18,
		Font = Enum.Font.GothamMedium,
	})
	if jobType then
		local info = itemInfo(jobType.itemKind)
		local how = HANDLING_TEXT[jobType.load] or "loaded for you"
		local about = card(body, 80, 3, false, true)
		iconText(about, info.art, info.icon, "", `  {jobType.name}`, UDim2.new(1, -190, 0, 24), { Position = UDim2.fromOffset(12, 8), TextSize = 19, Font = Enum.Font.GothamBlack, TextColor3 = P.ink })
		local needs = if jobType.level and jobType.level > 1 then `LV {jobType.level}+ · ` else ""
		Ui.label(about, `{needs}Danger {string.rep("★", jobType.tier)}`, UDim2.fromOffset(170, 24), {
			Position = UDim2.new(1, -182, 0, 8),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = if jobType.tier >= 3 then P.danger else P.violet,
			TextSize = 15,
		})
		local who = if jobType.giver == jobType.receiver then `for {jobType.giver}` else `from {jobType.giver} to {jobType.receiver}`
		Ui.label(about, `{jobType.items} {if jobType.items == 1 then info.one else info.many} {who}: {how}.`, UDim2.new(1, -24, 0, 38), {
			Position = UDim2.fromOffset(12, 36),
			TextColor3 = P.ink2,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end
	Ui.caps(body, `Rewards  ·  they lend you the {if reward then reward.name else "vehicle"} for every job`, UDim2.new(1, -10, 0, 22), {
		LayoutOrder = 4,
		TextSize = 12,
		TextColor3 = P.ink2,
	})
	local done = state.rep[employer.id] or 0
	if reward then
		rewardRow(body, 5, nil, "🚚", reward.name, done, employer.needed, state.cars[reward.id] == true)
	end
	if gun and employer.weaponAt then
		rewardRow(body, 6, Icons.weapon(gun.id), "🔫", gun.name, done, employer.weaponAt, state.weapons[gun.id] == true)
	end
	local lock = if jobType then lockedAt(jobType.level) else nil
	if job then
		Ui.label(body, "Finish your current delivery first (or give it up: the … menu).", UDim2.new(1, -10, 0, 24), { LayoutOrder = 7, TextColor3 = P.danger, TextSize = 16 })
	elseif lock then
		local button = Ui.ghostButton(body, `🔒 LEVEL {lock}`, UDim2.fromOffset(240, 50), nil, function() end)
		button.TextColor3 = P.ink2
		button.BackgroundColor3 = P.lavenderDeep
		button.BackgroundTransparency = 0
		button.LayoutOrder = 7
		Ui.label(body, `{employer.person} hires drivers from level {lock} ({Levels.rank(lock)}) on. You are level {myLevel()}: deliveries give XP.`, UDim2.new(1, -10, 0, 0), {
			LayoutOrder = 8,
			AutomaticSize = Enum.AutomaticSize.Y,
			TextColor3 = P.ink2,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
		})
	else
		local take = Ui.button(body, "TAKE THE JOB", UDim2.fromOffset(240, 50), P.sage, function()
			Net.get("AcceptEmployer"):FireServer(employer.id)
			employerWindow.frame.Visible = false
		end)
		take.TextColor3 = P.ink
		take.LayoutOrder = 7
	end
end

function Hud.openShop(id: string, focus: string?)
	if id == "jobs" then
		openDispatch()
		return
	elseif id == "employer" then
		openEmployer(focus or "")
		return
	end
	closeWindows()
	shopId = id
	shopFocus = focus
	shop.frame.Visible = true
	renderShop()
end
end

-- ── Backpack ───────────────────────────────────────────────────────────────

local backpack: any, renderBackpack: any, useItem: any, toggleBackpack: any
do -- (its own block: the locals below stay out of the 200-register limit)
backpack = window("Backpack", Vector2.new(640, 540), "🎒", "Your items, cars and guns")
local backpackTab = "items"
-- (renderBackpack is declared above the block)

function useItem(id: string)
	local count = if state then state.items[id] or 0 else 0
	if count <= 0 then
		local def = Economy.findItem(id)
		Hud.toast(`No {if def then def.name else id} left. Buy more at Last Stop Supplies.`)
		return
	end
	Net.get("UseItem"):FireServer(id, Shooting.aimPoint())
end

-- During a job: what is in your hands and in your vehicle.
local function cargoCard(parent: any)
	if not job then
		return
	end
	local info = jobCargo()
	local holding = myCarrying()
	local aboard = inVehicle()
	local car = Drive.myCar()
	local carDef = car and Economy.findCar(tostring(car:GetAttribute("CarId")))
	local lost = tonumber(job.lost) or 0
	local c = card(parent, if lost > 0 then 118 else 96, -1, true, true)
	Ui.caps(c, "On this job", UDim2.new(1, -24, 0, 18), { Position = UDim2.fromOffset(16, 8), TextColor3 = P.violet, TextSize = 13 })
	local held = if holding then heldInfo(holding) else nil
	iconText(c, if held then held.art else nil, if held then held.icon else "", if held then "✋  In your hands: " else "✋  Your hands are free", if held then ` {held.one}` else "", UDim2.new(1, -24, 0, 24), {
		Position = UDim2.fromOffset(16, 30),
		TextSize = 18,
		TextColor3 = if held then P.ink else P.ink2,
	})
	local vehicle = if carDef then carDef.name else "your vehicle"
	-- The text before the cargo's icon, the icon and the text after it (only "in the vehicle" has the icon).
	local before, emoji, after = `🚚  {vehicle}: {job.cargo}`, "", ""
	if aboard ~= nil and aboard > 0 then
		before, emoji, after = `🚚  In the {vehicle}: {aboard} × `, info.icon, ` {if aboard == 1 then info.one else info.many}`
	elseif aboard ~= nil then
		before = `🚚  The {vehicle} is empty`
	end
	if type(job.total) == "number" then
		local arrived = tonumber(job.deliveredTotal)
		after ..= if arrived then `  ·  {arrived}/{job.total} delivered` else `  ·  {job.total} in all`
	end
	iconText(c, if emoji ~= "" then info.art else nil, emoji, before, after, UDim2.new(1, -24, 0, 24), { Position = UDim2.fromOffset(16, 60), TextSize = 16, TextColor3 = P.ink, Font = Enum.Font.GothamMedium })
	if lost > 0 then
		Ui.label(c, `⚠  Lost on the way: {lost} {if lost == 1 then info.one else info.many}`, UDim2.new(1, -24, 0, 20), {
			Position = UDim2.fromOffset(16, 88),
			TextSize = 15,
			TextColor3 = P.danger,
			Font = Enum.Font.GothamMedium,
		})
	end
end

function renderBackpack()
	Ui.clear(backpack.body)
	if not state then
		return
	end
	cargoCard(backpack.body)
	backpack.footer.Text = `{Ui.money(state.money)} · level {myLevel()}`
	tabs(backpack.body, { { "items", "ITEMS" }, { "cars", "CARS" }, { "guns", "GUNS" } }, backpackTab, function(id)
		backpackTab = id
		renderBackpack()
	end)
	if backpackTab == "items" then
		for order, def in Config.Items do
			local c = card(backpack.body, 84, order + 1)
			local have = state.items[def.id] or 0
			cardText(c, `{def.name}  x{have}`, `Key {order}`, def.description, cardIcon(c, Icons.item(def.id), def.icon, 16))
			cardButton(c, "USE", C.green, have > 0, function()
				useItem(def.id)
			end)
		end
	elseif backpackTab == "cars" then
		note(backpack.body, "Switch cars at one of your garages (🅿 GARAGE), the starting van at the depot lot. Repairs: Wrench Garage and Rust Bridge Repairs. Buy at Dead End Motors, or earn one by working (M = map).", C.dim, 1)
		for order, def in Config.Cars do
			if not state.cars[def.id] and def.employer then
				-- Not yours yet: who gives it to you.
				local employer = findEmployer(def.employer)
				if employer then
					local c = card(backpack.body, 84, order + 1)
					local done = state.rep[employer.id] or 0
					cardText(c, `{def.name}  (locked)`, `Work for {employer.name}: {math.min(done, employer.needed)}/{employer.needed} jobs`, def.description)
				end
				continue
			end
			if state.cars[def.id] then
				local c = card(backpack.body, 84, order + 1)
				local gunId = if def.mount and state.carGuns then state.carGuns[def.id] else nil
				local gun = if gunId then Economy.findCarGun(gunId) else nil
				cardText(c, def.name, carStats(def, Economy.carLevels(state.carUpgrades, def.id)) .. (if gun then ` · 🔫 {gun.name}` else "") .. (if type(state.carHealth) == "table" and type(state.carHealth[def.id]) == "number" and state.carHealth[def.id] < 0.995 then ` · 🔧 {math.floor(state.carHealth[def.id] * 100 + 0.5)}%` else ""), def.description)
				if state.car == def.id then
					cardButton(c, "DRIVING", C.grey, false, function() end)
				end
			end
		end
	else
		for order, def in Config.Weapons do
			if state.weapons[def.id] then
				local c = card(backpack.body, 84, order + 1)
				cardText(c, def.name, gunStats(def) .. (if def.pierce then ` · Pierces {def.pierce}` else "") .. (if def.oneHanded then " · One-handed" else ""), def.description, cardIcon(c, Icons.weapon(def.id), nil, 17))
				if def.exclusive then
					-- 3.1: a reward nobody can buy (Config.Rewards).
					local chip = Ui.chip(c, "★ EXCLUSIVE", P.violet, P.paper)
					chip.Size = UDim2.fromOffset(0, 18)
					chip.Position = UDim2.new(1, -162, 0, 2)
					chip.TextSize = 12
				end
				if state.weapon == def.id then
					cardButton(c, "IN HAND", C.grey, false, function() end)
				else
					cardButton(c, "EQUIP", C.blue, true, function()
						Net.get("Equip"):FireServer("weapon", def.id)
					end)
				end
			elseif def.earned then
				-- Earned by working, not bought.
				local employer = findEmployer(def.earned)
				if employer then
					local c = card(backpack.body, 84, order + 1)
					local done = state.rep[employer.id] or 0
					local at = employer.weaponAt or employer.needed
					cardText(c, `{def.name}  (locked)`, `Earned at {employer.name}: {math.min(done, at)}/{at} jobs`, def.description)
				end
			end
		end
	end
end

function toggleBackpack()
	if backpack.frame.Visible then
		backpack.frame.Visible = false
	else
		closeWindows()
		backpack.frame.Visible = true
		renderBackpack()
	end
end
end

-- ── Delivery result ────────────────────────────────────────────────────────

local result: any
do -- (its own block: the locals below stay out of the 200-register limit)
result = window("Delivery", Vector2.new(480, 580), "📦", "")

-- The crew of a job (r.crew): a number (riders, older payloads) or the list of everyone paid { { name, pay } }
-- (the owner too; an entry may say owner = true).
local function crewList(r: any): { { name: string, pay: number, owner: boolean } }
	local list = {}
	if type(r.crew) == "table" then
		for _, entry in r.crew do
			if type(entry) == "table" and entry.name ~= nil then
				table.insert(list, { name = tostring(entry.name), pay = tonumber(entry.pay) or 0, owner = entry.owner == true })
			end
		end
	end
	return list
end

function Hud.showResult(r: any)
	closeWindows()
	Ui.clear(result.body)
	result.frame.Visible = true
	-- 3.6: the header says how it went, the footer where NEXT JOB goes.
	result.title.Text = if r.success then "Delivered" else "Delivery failed"
	result.icon.Text = if r.success then "📦" else "⚠"
	result.subtitle.Text = if r.cargo then `{r.cargo}{if r.customer then ` for {r.customer}` else ""}` else ""
	result.footer.Text = "Next job · the Dispatch board"
	local function line(text: string, value: string?, color: Color3?, order: number): any
		-- 3.2: the headline (order 1) and the TOTAL big in DisplayFont, the other lines calmer. 3.6: in ink on the
		-- lavender (green: good news, red: bad, gold: the money and the XP, dim: the details).
		local big = order == 1 or text == "TOTAL"
		local ink = if color == C.green then P.good elseif color == C.red then P.danger elseif color == C.yellow then P.violet elseif color == C.dim then P.ink2 else P.ink
		local row = Ui.make("Frame", { Size = UDim2.new(1, -12, 0, if order == 1 then 36 else 26), BackgroundTransparency = 1, LayoutOrder = order }, result.body)
		Ui.label(row, text, UDim2.new(1, if value then -120 else 0, 1, 0), {
			TextColor3 = ink,
			TextSize = if order == 1 then 28 elseif big then 20 else 16,
			Font = if big then Theme.DisplayFont else Theme.HeadingFont,
		})
		if value then
			Ui.label(row, value, UDim2.new(0, 120, 1, 0), {
				Position = UDim2.new(1, -120, 0, 0),
				TextColor3 = ink,
				TextSize = if big then 20 else 16,
				Font = if big then Theme.DisplayFont else Theme.HeadingFont,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
		end
		return row
	end
	local crew = crewList(r)
	local riders = if type(r.crew) == "number" then r.crew else math.max(0, #crew - 1)
	if r.success and r.rider then
		line("CREW DELIVERY!", nil, C.green, 1)
		line(`You helped {r.driver} deliver {r.cargo}.`, nil, C.dim, 2)
		line("Your share", Ui.money(r.total), C.yellow, 3)
	elseif r.success then
		local payout = r.payout
		line("DELIVERED!", nil, C.green, 1)
		line(`{r.cargo} for {r.customer}`, nil, C.dim, 2)
		-- The pieces: how many arrived, and how many bandits or crashes took.
		local pieces = tonumber(r.pieces)
		if pieces and pieces > 0 then
			local delivered = tonumber(r.delivered) or pieces
			local lost = tonumber(r.lost) or 0
			local name = if pieces == 1 then (r.piece or "piece") else (r.piecesName or "pieces")
			line(`Delivered {delivered}/{pieces} {name}`, nil, if delivered >= pieces then C.green else C.yellow, 3)
			if lost > 0 then
				line(`Lost on the way: {lost}`, nil, C.red, 4)
			end
		end
		line("Pay", Ui.money(payout.base), nil, 5)
		line(`Cargo condition {math.floor(r.condition * 100 + 0.5)}%`, Ui.money(payout.conditionPay), nil, 6)
		line("Speed bonus", "+" .. Ui.money(payout.fastBonus), nil, 7)
		line(`Enemies killed ({r.kills})`, "+" .. Ui.money(payout.killBonus), nil, 8)
		local nightBonus = tonumber(payout.nightBonus) or 0
		if nightBonus > 0 then
			line("Night bonus", "+" .. Ui.money(nightBonus), nil, 9)
		end
		local crewBonus = tonumber(r.crewBonus) or 0
		if riders > 0 and crewBonus > 0 then
			line(`Crew bonus ({riders} in the crew)`, "+" .. Ui.money(crewBonus), nil, 10)
		elseif riders > 0 and crewBonus < 0 then
			line(`Shared with the crew ({riders})`, "-" .. Ui.money(-crewBonus), C.dim, 10)
		end
		line("TOTAL", Ui.money(r.total), C.yellow, 11)
		local employer = r.employer
		if employer then
			line(`{employer.name}: {employer.done} jobs done`, nil, C.yellow, 12)
			-- The next reward of that employer (the gun comes first, then the vehicle).
			local done = tonumber(employer.done) or 0
			local gunAt = tonumber(employer.weaponAt)
			local nextUp = if employer.weapon and gunAt and done < gunAt then `{gunAt - done} more for the {employer.weapon}`
				elseif type(employer.needed) == "number" and done < employer.needed and employer.reward ~= "" then `{employer.needed - done} more for the {employer.reward}`
				else nil
			if nextUp then
				line(nextUp, nil, C.dim, 13)
			end
		end
		local newCar = r.unlockedCar or (employer and employer.unlocked)
		if newCar then
			line(`🚚 NEW CAR: the {newCar} is yours!`, nil, C.green, 14)
		end
		if type(r.unlockedWeapon) == "string" then
			local gun = Economy.findWeapon(r.unlockedWeapon)
			line(`🔫 NEW GUN: the {if gun then gun.name else r.unlockedWeapon} is yours!`, nil, C.green, 15)
		end
	else
		line("DELIVERY FAILED", nil, C.red, 1)
		Ui.label(result.body, r.reason or "", UDim2.new(1, -10, 0, 60), { LayoutOrder = 2, TextColor3 = P.ink })
	end
	-- The XP of the job, the level bar and a level-up with what it unlocks.
	local xp = tonumber(r.xp)
	if xp and xp > 0 then
		local level = tonumber(r.level) or myLevel()
		local rank = if type(r.rank) == "string" then r.rank else Levels.rank(level)
		line(if r.success then "Driver XP" else "Driver XP (a failed job still counts)", `+{xp} XP`, C.yellow, 30)
		local row = Ui.make("Frame", { Size = UDim2.new(1, -10, 0, 22), BackgroundTransparency = 1, LayoutOrder = 31 }, result.body)
		Ui.label(row, `LV {level} · {rank}`, UDim2.new(0.5, 0, 1, 0), { TextColor3 = P.ink2, TextSize = 14, Font = Enum.Font.GothamMedium, TextWrapped = false })
		local back, fill = Ui.bar(row, UDim2.new(0.5, 0, 0, 5), P.violet)
		back.Position = UDim2.new(0.5, 0, 0.5, -2)
		local mine = myXp()
		fill.Size = UDim2.fromScale(if mine then Levels.progress(mine) else 0, 1)
		if r.levelUp == true then
			line(`⬆ LEVEL UP! Level {level}: {rank}`, nil, C.green, 32)
			local unlocked = unlocksAt(level)
			if #unlocked > 0 then
				Ui.label(result.body, `Unlocked: {table.concat(unlocked, " · ")}`, UDim2.new(1, -10, 0, 0), {
					LayoutOrder = 33,
					AutomaticSize = Enum.AutomaticSize.Y,
					TextColor3 = P.good,
					TextSize = 15,
					Font = Enum.Font.GothamMedium,
				})
			end
		end
	end
	-- The crew's pay split: everyone paid on this job.
	if #crew > 1 then
		line(`CREW PAY · split between {#crew}`, nil, C.yellow, 40)
		for index, entry in crew do
			local me = entry.name == player.DisplayName or entry.name == player.Name
			local row = line(`{if entry.owner then "🚚" else "👤"}  {entry.name}{if me then "  (you)" else ""}`, Ui.money(entry.pay), if me then C.yellow else C.text, 40 + index)
			if me then
				row.BackgroundTransparency = 0
				row.BackgroundColor3 = P.lavenderDeep
				Ui.corner(row, 6)
			end
		end
	end
	local ok = Ui.ghostButton(result.body, "OK", UDim2.fromOffset(160, 44), nil, function()
		result.frame.Visible = false
	end)
	ok.LayoutOrder = 90
	ok.TextColor3 = P.ink2
	ok.BackgroundColor3 = P.lavenderDeep
	ok.BackgroundTransparency = 0
	local next = Ui.button(result.body, "NEXT JOB  →", UDim2.fromOffset(160, 44), P.sage, function()
		result.frame.Visible = false
		openDispatch()
	end)
	next.TextColor3 = P.ink
	next.LayoutOrder = 91
end

-- Is the DELIVERY result window open (client/MissionsUi.luau waits with its celebration card until it is closed)?
function Hud.resultOpen(): boolean
	return result ~= nil and result.frame.Visible == true
end
end

-- ── Buttons ────────────────────────────────────────────────────────────────

-- 3.6, the utilities (the concept's top right): MAP and CREW as soft square buttons and a round "…" that opens the
-- menu with every other action and its key: JOBS (J), MISSIONS (U), BAG (B), CAR, TOP (L), ESTATE (H), SOUND (N) and,
-- while a job runs, GIVE UP (twice). A computer shows a button's name and key over it on hover; a touch screen keeps
-- the names under the buttons. Other modules hook in (Hud.onJobs, Hud.onCrew, Hud.onEstate, Hud.onMissions,
-- Hud.onSound). layout() scales and places the row: top right on a touch screen, on a computer clear of Roblox's
-- player list (leaderstats), just over the weapon label; the menu opens toward the middle of the screen.

type ButtonDef = { id: string, text: string, icon: string, menu: boolean?, key: string?, onClick: () -> () }
local BUTTONS: { ButtonDef }, buttonGrid: any, hudButtons: { [string]: any }
do -- (its own block: the locals below stay out of the 200-register limit)
local function hook(name: string, cb: (() -> ())?)
	if cb then
		cb()
	else
		Hud.toast(`The {name} is not ready yet.`)
	end
end
local giveUpAt = 0 -- the first press of GIVE UP (a second one within 4 s gives the job up)

-- (type declared above)
BUTTONS = {
	{ id = "map", icon = "🗺️", text = "MAP", key = "M", onClick = function()
		MapView.toggle()
	end },
	{ id = "crew", icon = "👥", text = "CREW", key = "K", onClick = function()
		hook("crew panel", Hud.onCrew)
	end },
	{ id = "jobs", menu = true, icon = "📋", text = "JOBS", key = "J", onClick = openDispatch },
	{ id = "missions", menu = true, icon = "⭐", text = "MISSIONS", key = "U", onClick = function()
		hook("missions window", Hud.onMissions)
	end },
	{ id = "bag", menu = true, icon = "🎒", text = "BAG", key = "B", onClick = function()
		toggleBackpack()
	end },
	{ id = "car", menu = true, icon = "🚗", text = "CAR", onClick = function()
		Net.get("SpawnCar"):FireServer()
	end },
	{ id = "top", menu = true, icon = "🏆", text = "TOP", key = "L", onClick = function()
		Leaderboard.toggle()
	end },
	{ id = "estate", menu = true, icon = "🏠", text = "ESTATE", key = "H", onClick = function()
		hook("real estate list", Hud.onEstate)
	end },
	{ id = "sound", menu = true, icon = "🔊", text = "SOUND", key = "N", onClick = function()
		hook("sound setting", Hud.onSound)
	end },
	{ id = "giveup", menu = true, icon = "🏳", text = "GIVE UP", onClick = function()
		if not job then
			return
		end
		local now = os.clock()
		if now - giveUpAt > 4 then
			giveUpAt = now
			Hud.toast("Give up this delivery? Press GIVE UP again.")
			return
		end
		giveUpAt = 0
		view.menu.Visible = false
		Net.get("CancelJob"):FireServer()
	end },
}

-- The row: MAP, CREW, "…" (UTIL px squares, GAP apart; on touch a name pill under each).
local UTIL, GAP, NAME_H = 46, 8, if touchLayout then 20 else 0
buttonGrid = placed(Ui.make("Frame", {
	Name = "HudButtons",
	Size = UDim2.fromOffset(3 * UTIL + 2 * GAP, UTIL + 6 + NAME_H),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
	BackgroundTransparency = 1,
	ZIndex = 2, -- over the weapon label and FIRE: the open menu draws on top and takes the taps
}, gui))
hudButtons = {}

-- The menu: a lavender card of entries (two columns), hidden until "…".
local CELL_W, CELL_H = 150, 40
local menu = Ui.make("Frame", {
	Name = "Menu",
	Size = UDim2.fromOffset(2 * CELL_W + 6 + 20, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, 0, 0, -10),
	BackgroundColor3 = P.lavender,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 6,
}, buttonGrid)
Ui.corner(menu, 16)
Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1.5 }, menu)
Ui.padding(menu, 10)
Ui.make("UIGridLayout", {
	CellSize = UDim2.fromOffset(CELL_W, CELL_H),
	CellPadding = UDim2.fromOffset(6, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, menu)
view.menu = menu

-- A soft square (or the round "…") for the row, with a shadow under it; hover lifts it (Ui.tactile).
local function utility(def: ButtonDef?, index: number): any
	local x = (index - 1) * (UTIL + GAP)
	local shadow = Ui.make("Frame", {
		Size = UDim2.fromOffset(UTIL, UTIL),
		Position = UDim2.fromOffset(x, 4),
		BackgroundColor3 = P.line,
		BorderSizePixel = 0,
	}, buttonGrid)
	local button = Ui.make("TextButton", {
		Name = if def then `{def.id}Button` else "moreButton",
		Size = UDim2.fromOffset(UTIL, UTIL),
		Position = UDim2.fromOffset(x, 0),
		BackgroundColor3 = if def then P.lavender else P.tags[4],
		Text = if def then def.icon else "•••",
		TextScaled = def ~= nil,
		TextSize = 16,
		Font = Theme.DisplayFont,
		TextColor3 = P.ink,
		AutoButtonColor = false,
	}, buttonGrid)
	local round = if def then 14 else UTIL // 2
	Ui.corner(shadow, round)
	Ui.corner(button, round)
	Ui.stroke(button, P.line, 1).Transparency = 0.4
	if def then
		Ui.make("UIPadding", { PaddingTop = UDim.new(0, 11), PaddingBottom = UDim.new(0, 11), PaddingLeft = UDim.new(0, 11), PaddingRight = UDim.new(0, 11) }, button)
	end
	Ui.tactile(button, 4, 1.04)
	local name = if def then def.text else "MORE"
	if touchLayout then
		-- A touch screen has no hover: the name stays under the button, on a paper pill (it floats over the world).
		local pill = Ui.caps(buttonGrid, name, UDim2.fromOffset(UTIL + 4, 16), {
			Position = UDim2.fromOffset(x + UTIL / 2, UTIL + 8),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 0.1,
			BackgroundColor3 = P.paper,
			TextSize = 12,
			TextColor3 = P.ink,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Ui.corner(pill, 8)
	else
		-- A computer: the name and the key over the button while the mouse is on it.
		local tip = Ui.caps(button, if def and def.key then `{name} · {def.key}` else name, UDim2.fromOffset(0, 24), {
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.new(0.5, 0, 0, -16),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 0,
			BackgroundColor3 = P.paper,
			TextSize = 12,
			TextColor3 = P.ink,
			TextXAlignment = Enum.TextXAlignment.Center,
			Visible = false,
			ZIndex = 4,
		})
		Ui.corner(tip, 8)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1 }, tip)
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, tip)
		button.MouseEnter:Connect(function()
			tip.Visible = not menu.Visible
		end)
		button.MouseLeave:Connect(function()
			tip.Visible = false
		end)
	end
	return button
end

-- A count in a red dot on the corner (Hud.setBadge); the button's UIPadding moves its children, so out by that much.
local function badgeOn(button: any)
	local pad = button:FindFirstChildOfClass("UIPadding")
	local badge = Ui.make("TextLabel", {
		Name = "Badge",
		Size = UDim2.fromOffset(20, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, (if pad then pad.PaddingRight.Offset else 0) - 2, 0, 2 - (if pad then pad.PaddingTop.Offset else 0)),
		BackgroundColor3 = P.danger,
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = P.paper,
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		Visible = false,
		ZIndex = 3,
	}, button)
	Ui.corner(badge, 10)
end

local index = 0
local entries = 0
for order, def in BUTTONS do
	local button: any
	if def.menu then
		-- An entry of the menu: the icon and the name on paper, the key in a chip on the right.
		entries += 1
		button = Ui.make("TextButton", {
			Name = `{def.id}Button`,
			BackgroundColor3 = P.ticket,
			Text = `{def.icon}  {def.text}`,
			TextSize = 14,
			Font = Theme.HeadingFont,
			TextColor3 = P.ink,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutoButtonColor = false,
			LayoutOrder = order,
			ZIndex = 7,
		}, menu)
		Ui.corner(button, 10)
		Ui.stroke(button, P.line, 1).Transparency = 0.4
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, if def.key and not touchLayout then 34 else 8) }, button)
		if def.key and not touchLayout then
			local key = Ui.label(button, def.key, UDim2.fromOffset(22, 22), {
				Position = UDim2.new(1, 26, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				TextSize = 12,
				TextColor3 = P.ink2,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 8,
			})
			Ui.corner(key, 6)
			Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1 }, key)
		end
		button.MouseEnter:Connect(function()
			button.BackgroundColor3 = P.sage
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundColor3 = P.ticket
		end)
		if def.id == "giveup" then
			button.Visible = false -- only while a job runs (Hud.setJob)
			button.TextColor3 = P.danger
		end
	else
		index += 1
		button = utility(def, index)
	end
	button.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		if def.menu and def.id ~= "giveup" then
			menu.Visible = false
		end
		def.onClick()
	end)
	badgeOn(button)
	hudButtons[def.id] = button
end
view.menuHeight = math.ceil(entries / 2) * (CELL_H + 6) - 6 + 20 -- px at scale 1, GIVE UP shown
-- "…": opens and closes the menu.
local more = utility(nil, index + 1)
more.Activated:Connect(function()
	local click = Ui.onClick
	if click then
		click()
	end
	menu.Visible = not menu.Visible
end)
hudButtons.more = more

-- A red dot with a count on a HUD button ("crew": the invitations waiting); 0 hides it.
function Hud.setBadge(id: string, count: number)
	local button = hudButtons[id]
	local badge = button and button:FindFirstChild("Badge")
	if badge and badge:IsA("TextLabel") then
		badge.Visible = count > 0
		badge.Text = if count > 9 then "9+" else tostring(count)
	end
end

-- The border of a HUD button lights up in `color` for `seconds` (an invitation just came: the CREW button).
function Hud.flashButton(id: string, color: Color3?, seconds: number?)
	local button = hudButtons[id]
	local stroke = button and button:FindFirstChild("UiBorder")
	if not (stroke and stroke:IsA("UIStroke")) then
		return
	end
	stroke.Color = color or P.violet
	stroke.Thickness = 2.5
	stroke.Transparency = 0
	task.delay(seconds or 1.5, function()
		stroke.Color = P.line
		stroke.Thickness = 1
		stroke.Transparency = 0.4
	end)
end
end

-- ── Hotbar ─────────────────────────────────────────────────────────────────

-- 3.6: the consumable tags (items, keys 1-5) bottom centre, and the weapon label (the gun in your hands; hold Q: the
-- wheel) on top of the speed dial, bottom right (on a touch screen left of FIRE). layout() places them.
local BAR_W: any, HOTBAR_H: any, hotbar: any, weaponBar: any, weaponBarKey: any, shownWeaponBar: any, renderWeapons: any, nextWeapon: any, hotbarCounts: any, FIRE_SIZE: any, fire: any
do -- (its own block: the locals below stay out of the 200-register limit)
local TAG_W, TAG_H, TAG_GAP = 48, 54, 12
BAR_W = #Config.Items * TAG_W + (#Config.Items - 1) * TAG_GAP
HOTBAR_H = TAG_H + 8
hotbar = placed(Ui.make("Frame", {
	Name = "Hotbar",
	Size = UDim2.fromOffset(BAR_W, HOTBAR_H),
	Position = UDim2.new(0.5, 0, 1, -16),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundTransparency = 1,
}, gui))
weaponBar = placed(Ui.make("Frame", {
	Name = "WeaponBar",
	Size = UDim2.fromOffset(236, 58),
	Position = UDim2.new(1, -16, 1, -230),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundTransparency = 1,
}, gui))
local weaponRow = Ui.make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, weaponBar)

-- What the weapon label shows depends on where you are: on foot your gun; driving a car with a car gun that gun; in
-- any other seat your gun, WINDOW READY when it is one-handed, ON FOOT ONLY when it is not (it does not fire there);
-- with cargo in your hands, or while the cargo loads, HOLSTERED and dimmed.
local function seatView(): (boolean, Config.CarGunDef?)
	local seatedIn, driving = Drive.seatedCar()
	return seatedIn ~= nil, if seatedIn and driving then Shooting.carGunOf(seatedIn) else nil
end

local function loading(): boolean
	return myCarrying() ~= nil or (job ~= nil and (tonumber(job.progress) or 0) > 0)
end

function weaponBarKey(): string
	local seated, carGun = seatView()
	return `{seated}|{if carGun then carGun.id else ""}|{loading()}`
end
shownWeaponBar = ""

-- The weapon label (the concept's curved label): the gun's icon, its state in small caps over its name, and Q in a
-- round chip (hold it: the weapon wheel, client/WeaponWheel.luau). A click or a tap on it takes the next gun.
function renderWeapons()
	Ui.clear(weaponRow)
	shownWeaponBar = weaponBarKey()
	if not state then
		return
	end
	local seated, carGun = seatView()
	local gun = if carGun then nil else Economy.findWeapon(state.weapon)
	local def: any = carGun or gun
	if not def then
		return
	end
	local usable = carGun ~= nil or not seated or (gun ~= nil and gun.oneHanded == true)
	local holstered = carGun == nil and loading()
	local status = if holstered then "Holstered"
		elseif carGun then "On the roof"
		elseif not usable then "⚠ On foot only"
		elseif seated then "Window ready"
		else "Ready"
	local card = Ui.make("CanvasGroup", {
		Name = "GunCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.lavender,
		BorderSizePixel = 0,
		GroupTransparency = if holstered or not usable then 0.4 else 0,
	}, weaponRow)
	Ui.corner(card, 22)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1 }, card)
	Ui.icon(card, Icons.weapon(def.id), if def.splash > 0 then "💥" elseif def.pellets > 1 then "🎯" else "🔫", UDim2.fromOffset(44, 32), {
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ImageColor3 = P.ink,
	})
	local right = if carGun or touchLayout then 16 else 50
	Ui.caps(card, status, UDim2.new(1, -66 - right, 0, 14), {
		Position = UDim2.fromOffset(66, 10),
		TextSize = 12,
		TextColor3 = if not usable and not holstered then P.danger else P.ink2,
	})
	local name = Ui.label(card, def.name, UDim2.new(1, -66 - right, 0, 24), {
		Position = UDim2.fromOffset(66, 25),
		Font = Theme.DisplayFont,
		TextScaled = true,
		TextWrapped = false,
		TextColor3 = P.ink,
	})
	Ui.make("UITextSizeConstraint", { MaxTextSize = 19 }, name)
	if not carGun and not touchLayout then
		-- Q, how to switch: a round chip with a thin line (hold: the wheel).
		local key = Ui.label(card, "Q", UDim2.fromOffset(28, 28), {
			Position = UDim2.new(1, -14, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Font = Theme.HeadingFont,
			TextSize = 13,
			TextColor3 = P.ink2,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Ui.corner(key, 14)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1.5 }, key)
	end
	if not carGun then
		-- A tap (touch) or a click: the next gun.
		local tap = Ui.make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 2 }, weaponRow)
		tap.Activated:Connect(nextWeapon)
	end
end

-- The next gun you own (tap Q: client/WeaponWheel.luau has its own; hold Q opens the wheel).
function nextWeapon()
	if not state then
		return
	end
	local owned = {}
	for _, def in Config.Weapons do
		if state.weapons[def.id] then
			table.insert(owned, def.id)
		end
	end
	if #owned < 2 then
		Hud.toast("Buy more guns at Lead & Co., or earn them by working.")
		return
	end
	local index = table.find(owned, state.weapon) or 0
	Net.get("Equip"):FireServer("weapon", owned[index % #owned + 1])
end

-- The consumable tags: soft pastel tags, tilted one way and the other; under the mouse (or selected) a tag lifts 9 px,
-- straightens and grows to 1.12 with its name over it, a press sinks it (Ui.tactile). The key top left, the count
-- bottom right.
Ui.list(hotbar, false, TAG_GAP)
local list = hotbar:FindFirstChildOfClass("UIListLayout")
if list then
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
end
hotbarCounts = {}
for index, def in Config.Items do
	local slot = Ui.make("Frame", { Size = UDim2.fromOffset(TAG_W, HOTBAR_H), BackgroundTransparency = 1, LayoutOrder = index }, hotbar)
	local tilt = if index % 2 == 1 then -4 else 4
	local shadow = Ui.make("Frame", {
		Size = UDim2.fromOffset(TAG_W, TAG_H),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		Rotation = tilt,
		BackgroundColor3 = P.line,
		BorderSizePixel = 0,
	}, slot)
	Ui.corner(shadow, 11)
	local tag = Ui.make("TextButton", {
		Name = `{def.id}Tag`,
		Size = UDim2.fromOffset(TAG_W, TAG_H),
		Position = UDim2.new(0, 0, 1, -5),
		AnchorPoint = Vector2.new(0, 1),
		Rotation = tilt,
		BackgroundColor3 = P.tags[(index - 1) % #P.tags + 1],
		Text = "",
		AutoButtonColor = false,
		ZIndex = 2,
	}, slot)
	Ui.corner(tag, 11)
	Ui.icon(tag, Icons.item(def.id), def.icon, UDim2.fromOffset(26, 26), {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ImageColor3 = P.ink,
		ZIndex = 2,
	})
	Ui.label(tag, tostring(index), UDim2.fromOffset(14, 14), { Position = UDim2.fromOffset(5, 3), TextSize = 12, Font = Theme.HeadingFont, TextColor3 = P.ink2, ZIndex = 2 })
	hotbarCounts[def.id] = Ui.label(tag, "0", UDim2.new(1, -6, 0, 14), {
		Position = UDim2.new(0, 0, 1, -16),
		TextSize = 12,
		Font = Theme.HeadingFont,
		TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
	})
	-- The name over the tag while the mouse is on it.
	local name = Ui.caps(tag, def.name, UDim2.fromOffset(0, 24), {
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0.5, 0, 0, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = P.paper,
		TextSize = 12,
		TextColor3 = P.ink,
		Visible = false,
		ZIndex = 5,
	})
	Ui.corner(name, 7)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1 }, name)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, name)
	local function show(on: boolean)
		name.Visible = on and not touchLayout
		tag.ZIndex = if on then 4 else 2
	end
	tag.MouseEnter:Connect(function()
		show(true)
	end)
	tag.MouseLeave:Connect(function()
		show(false)
	end)
	tag.SelectionGained:Connect(function()
		show(true)
	end)
	tag.SelectionLost:Connect(function()
		show(false)
	end)
	Ui.tactile(tag, 9, 1.12)
	tag.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		useItem(def.id)
	end)
end

-- FIRE for touch screens (auto-aim): big, sage, on the right; layout() keeps it above Roblox's jump button.
FIRE_SIZE = 110
fire = placed(Ui.make("TextButton", {
	Name = "Fire",
	Size = UDim2.fromOffset(FIRE_SIZE, FIRE_SIZE),
	Position = UDim2.new(1, -40, 1, -190),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundColor3 = P.sage,
	Text = "FIRE",
	TextColor3 = P.ink,
	Font = Theme.DisplayFont,
	TextSize = 26,
	Visible = false,
	AutoButtonColor = true,
}, gui))
Ui.corner(fire, FIRE_SIZE // 2)
Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.sageLip, Thickness = 3 }, fire)
fire.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		Shooting.setAutoHeld(true)
	end
end)
fire.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		Shooting.setAutoHeld(false)
	end
end)
end

-- ── Car panel ──────────────────────────────────────────────────────────────

-- 3.6: the speed dial (the concept's round instrument): a cream disc with ticks and a violet pointer; the car's name
-- (its stage's), the speed big over KM/H, the vehicle's condition (a bar and the %) and its cargo slots (a pip each,
-- the loaded ones filled, "3 / 4 cargo slots"). On foot it dims and keeps the parked car's condition; without a car it
-- says how to get one. RenderStepped fills it (view.dial; only what changed).
local carPanel: any, hint: any
do -- (its own block: the locals below stay out of the 200-register limit)
local DIAL = 196
local R = DIAL / 2
carPanel = placed(Ui.make("Frame", {
	Name = "SpeedDial",
	Size = UDim2.fromOffset(DIAL, DIAL),
	Position = UDim2.new(1, -16, 1, -16),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundTransparency = 1,
}, gui))
local shadow = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = P.line, BorderSizePixel = 0 }, carPanel)
Ui.corner(shadow, DIAL)
local group = Ui.make("CanvasGroup", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.paper, BorderSizePixel = 0 }, carPanel)
Ui.corner(group, DIAL)
-- The ticks: from -135° to 135° every 15°, a longer one every 45°.
for k = 0, 18 do
	local angle = math.rad(-135 + k * 15)
	local major = k % 3 == 0
	local r = R - (if major then 12 else 10)
	Ui.make("Frame", {
		Size = UDim2.fromOffset(2, if major then 10 else 6),
		Position = UDim2.fromOffset(R + math.sin(angle) * r, R - math.cos(angle) * r),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = math.deg(angle),
		BackgroundColor3 = if major then P.ink2 else P.line,
		BorderSizePixel = 0,
	}, group)
end
-- The pointer: a short violet bar on the tick ring, turned with the speed (its holder turns about the centre).
local needle = Ui.make("Frame", { Size = UDim2.fromOffset(DIAL - 12, DIAL - 12), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Rotation = -135 }, group)
local pointer = Ui.make("Frame", { Size = UDim2.fromOffset(4, 18), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = P.violet, BorderSizePixel = 0 }, needle)
Ui.corner(pointer, 2)
local function centred(text: string, y: number, h: number, props: { [string]: any }): any
	local label = Ui.label(group, text, UDim2.fromOffset(DIAL - 60, h), {
		Position = UDim2.fromOffset(30, y),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	for key, value in props do
		label[key] = value
	end
	return label
end
local d: any = { group = group, needle = needle }
d.name = centred("", 38, 14, { Font = Theme.HeadingFont, TextSize = 12, TextColor3 = P.ink2 })
d.speed = centred("–", 52, 50, { Font = Theme.DisplayFont, TextSize = 50, TextColor3 = P.ink })
d.unit = centred("KM/H", 102, 14, { Font = Theme.HeadingFont, TextSize = 12, TextColor3 = P.ink2 })
Ui.caps(group, "Condition", UDim2.fromOffset(80, 14), { Position = UDim2.fromOffset(34, 122), TextSize = 12, TextColor3 = P.ink2 })
d.condText = Ui.label(group, "", UDim2.fromOffset(60, 14), {
	Position = UDim2.fromOffset(DIAL - 34, 122),
	AnchorPoint = Vector2.new(1, 0),
	TextSize = 12,
	Font = Theme.HeadingFont,
	TextColor3 = P.ink,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextWrapped = false,
})
local condBack
condBack, d.condFill = Ui.bar(group, UDim2.fromOffset(DIAL - 68, 5), P.violet)
condBack.Position = UDim2.fromOffset(34, 140)
d.pips = Ui.make("Frame", { Size = UDim2.fromOffset(DIAL - 60, 10), Position = UDim2.fromOffset(30, 151), BackgroundTransparency = 1 }, group)
Ui.list(d.pips, false, 3, Enum.HorizontalAlignment.Center)
d.slots = centred("", 164, 14, { Font = Theme.Font, TextSize = 12, TextColor3 = P.ink2 })
d.shown = "" -- what the dial shows (the slow parts redraw only when it changes)
view.dial = d

-- The cargo slots: one pip per slot (at most 12 drawn), the loaded ones filled.
function view.drawPips(capacity: number, loaded: number)
	Ui.clear(d.pips)
	for n = 1, math.min(capacity, 12) do
		local pip = Ui.make("Frame", {
			Size = UDim2.fromOffset(12, 9),
			BackgroundColor3 = if n <= loaded then P.violet else P.paper,
			BorderSizePixel = 0,
			LayoutOrder = n,
		}, d.pips)
		Ui.corner(pip, 2)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if n <= loaded then P.violet else P.line, Thickness = 1 }, pip)
	end
	d.slots.Text = if capacity > 0 then `{math.min(loaded, capacity)} / {capacity} cargo slots` else "no cargo slots"
end

-- What to do right now: a cream pill over the tags (layout() gives it the most width it may take, its "Max"
-- constraint; a long one wraps upward), the main line in ink and, under it, a quieter line (RichText). Hidden while it
-- has nothing to say.
hint = Ui.label(gui, "", UDim2.fromOffset(0, 0), {
	Name = "Hint",
	Position = UDim2.new(0.5, 0, 1, -104),
	AnchorPoint = Vector2.new(0.5, 1),
	AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundTransparency = 0.06,
	BackgroundColor3 = P.paper,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = P.ink,
	TextSize = 15,
	Font = Theme.HeadingFont,
	RichText = true,
	Visible = false,
})
Ui.corner(hint, 12)
Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1 }, hint)
Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, hint)
Ui.make("UISizeConstraint", { Name = "Max", MaxSize = Vector2.new(560, math.huge) }, hint)
end

-- ── Job panel ──────────────────────────────────────────────────────────────
-- 3.6: the objective ticket, top centre (the first entry of the top stack): a paper delivery ticket tilted -0.6° with a
-- perforated stub (Ui.ticket). On it: the stage in small caps (DELIVERY IN PROGRESS / PICKUP · STEP 1 OF 3, the danger
-- stars, a modifier), the stop (big), a pin line (the job, the stop, the distance), the cargo slots (loaded / your
-- car's), the estimated pay and what went wrong (cargo condition, pieces lost, a wave). The timer sits in the stub.
-- What to do right now (the job's step: "Get out and open the back (E)") is the hint over the tags.
-- With no job and nothing else on top: a small OFF DUTY ticket that opens the Dispatch board.

local LOAD_H: any, loadFill: any, loadBack: any, loadText: any
do -- (its own block: the locals below stay out of the 200-register limit)
local TextService = game:GetService("TextService")
local STUB = 96
local slot = Hud.topSlot("job")
local t: any = {}
view.ticket = t

-- RichText needs its own escapes, and colours as hex.
function view.esc(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
function view.hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

-- The ticket's holder in the stack (the stack lays it out; the ticket inside it is free to tilt).
t.wrap = Ui.make("Frame", { Name = "JobTicket", Size = UDim2.new(1, 0, 0, 116), BackgroundTransparency = 1, Visible = false, LayoutOrder = 1 }, slot)
local ticketCard, body, stub = Ui.ticket(t.wrap, UDim2.new(1, -8, 1, -6), UDim2.fromOffset(4, 0), nil, STUB, -0.6)
t.card = ticketCard
Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 12) }, body)
t.label = Ui.caps(body, "", UDim2.fromOffset(0, 18), {
	AutomaticSize = Enum.AutomaticSize.X,
	TextSize = 12,
	TextColor3 = P.ink2,
	BackgroundColor3 = P.lavenderDeep,
	BackgroundTransparency = 1,
})
Ui.corner(t.label, 9)
Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, t.label)
Ui.make("UISizeConstraint", { MaxSize = Vector2.new(TOP_W - STUB - 40, 18) }, t.label)
t.title = Ui.label(body, "", UDim2.new(1, 0, 0, 24), {
	Position = UDim2.fromOffset(0, 22),
	TextSize = 20,
	Font = Theme.DisplayFont,
	TextColor3 = P.ink,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
t.pin = Ui.label(body, "", UDim2.new(1, 0, 0, 18), {
	Position = UDim2.fromOffset(0, 50),
	TextSize = 14,
	Font = Theme.Font,
	TextColor3 = P.ink2,
	TextWrapped = false,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
t.meta = Ui.label(body, "", UDim2.new(1, 0, 0, 18), {
	Position = UDim2.fromOffset(0, 74),
	TextSize = 14,
	Font = Theme.HeadingFont,
	TextColor3 = P.ink,
	RichText = true,
	TextWrapped = false,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
-- The stub: a clock and the time left, big.
Ui.label(stub, "⏱", UDim2.new(1, 0, 0, 18), { Position = UDim2.new(0, 0, 0.5, -26), TextSize = 15, TextColor3 = P.ink2, TextXAlignment = Enum.TextXAlignment.Center })
t.timer = Ui.label(stub, "", UDim2.new(1, -8, 0, 30), {
	Position = UDim2.new(0, 4, 0.5, -6),
	TextSize = 24,
	Font = Theme.DisplayFont,
	TextColor3 = P.ink,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = false,
	TextScaled = true,
})
Ui.make("UITextSizeConstraint", { MaxTextSize = 24 }, t.timer)
t.lines = 1
t.meta0 = ""

-- The title in one line or two (the ticket grows): measured at the stack's width (layout() calls it too).
function view.fitTicket()
	local width = math.max(100, topStack.Size.X.Offset - 8 - STUB - 30)
	local size = TextService:GetTextSize(t.title.Text, 20, Theme.DisplayFont, Vector2.new(width, 1000))
	local lines = if size.Y > 26 then 2 else 1
	if lines == t.lines then
		return
	end
	t.lines = lines
	local extra = (lines - 1) * 23
	t.title.Size = UDim2.new(1, 0, 0, 24 + extra)
	t.pin.Position = UDim2.fromOffset(0, 50 + extra)
	t.meta.Position = UDim2.fromOffset(0, 74 + extra)
	t.wrap.Size = UDim2.new(1, 0, 0, 116 + extra)
end

-- "DELIVER to Bob, 42 Maple St" → "Deliver to Bob, 42 Maple St": the label's shouted words in sentence case.
local function sentence(text: string): string
	local words = string.split(text, " ")
	for index, word in words do
		if word:upper() ~= word then
			break
		end
		words[index] = word:lower()
	end
	local joined = table.concat(words, " ")
	return joined:sub(1, 1):upper() .. joined:sub(2)
end

-- The parts of the ticket that change with a job update (Hud.setJob).
function view.fillTicket()
	if not job then
		return
	end
	local pickup = job.stage == "pickup"
	local index, count = tonumber(job.stopIndex) or 1, tonumber(job.stopCount) or 1
	local stage = if pickup then `Pickup · step {index} of {count}` elseif index < count then `Drop-off · step {index} of {count}` else "Delivery in progress"
	local stars = string.rep("★", tonumber(job.stars) or 0)
	t.label.Text = string.upper(`{if pickup then "" else "•  "}{stage}  ·  {stars}{if job.modifier then `  ·  {job.modifier.name}` else ""}`)
	t.label.TextColor3 = if pickup then P.violet else P.ink2
	t.label.BackgroundTransparency = if pickup then 0 else 1
	t.title.Text = sentence(tostring(job.stopLabel or job.cargo or ""))
	view.fitTicket()
end

-- The ticket's live parts (every frame from RenderStepped): the timer, the pin line, the meta line.
function view.tickTicket(distance: number?)
	if not job then
		return
	end
	local left = job.endsAt - workspace:GetServerTimeNow()
	local clock = Ui.clock(left)
	if t.timer.Text ~= clock then
		t.timer.Text = clock
		t.timer.TextColor3 = if left < 15 then P.danger else P.ink
	end
	local name = if job.jobType then job.jobType.name else tostring(job.cargo)
	local person = if type(job.person) == "string" and job.person ~= "" then `  ·  {job.person}` else ""
	local pin = `📍 {name}{person}  ·  stop {job.stopIndex}/{job.stopCount}{if distance then `  ·  {distance} m` else ""}`
	if t.pin.Text ~= pin then
		t.pin.Text = pin
	end
	-- What went wrong first (the line is cut at its end), then 📦 loaded / slots (by hand only), the pay, the rest.
	local car = Drive.myCar()
	local carId = car and tostring(car:GetAttribute("CarId"))
	local capacity = if car and carId then Economy.stageCapacity(carId, tonumber(car:GetAttribute("Stage")) or 0) else 0
	local byHand = job.handling == "carry" or job.handling == "lead" or (job.handling == "drive" and type(job.total) == "number" and job.total > 0)
	local aboard = inVehicle() or 0
	local lost = tonumber(job.lost) or 0
	local condition = tonumber(job.condition) or 1
	local wave = tonumber(job.wave) or 0
	local signature = `{byHand}|{aboard}|{capacity}|{job.pay}|{lost}|{math.floor(condition * 100 + 0.5)}|{wave}|{job.night}`
	if signature == t.meta0 then
		return
	end
	t.meta0 = signature
	local danger = view.hex(P.danger)
	local quiet = view.hex(P.ink2)
	local parts: { string } = {}
	if lost > 0 then
		table.insert(parts, `<font color="{danger}">⚠ {lost} lost</font>`)
	end
	if condition < 0.4 then
		table.insert(parts, `<font color="{danger}">⚠ cargo {math.floor(condition * 100 + 0.5)}%</font>`)
	end
	if byHand and capacity > 0 then
		table.insert(parts, `📦 {aboard} / {capacity} <font color="{quiet}">slots</font>`)
	end
	table.insert(parts, `EST. {Ui.money(job.pay)}` .. (if job.night == true then ` <font color="{quiet}">🌙 night</font>` else ""))
	if condition < 0.995 and condition >= 0.4 then
		table.insert(parts, `<font color="{quiet}">cargo {math.floor(condition * 100 + 0.5)}%</font>`)
	end
	if wave > 0 then
		table.insert(parts, `<font color="{quiet}">🌊 wave {wave}</font>`)
	end
	t.meta.Text = table.concat(parts, "   ")
end

-- The OFF DUTY ticket: no job, nothing else on top. A click (a tap) opens the Dispatch board.
local idle = Ui.make("TextButton", { Name = "OffDuty", Size = UDim2.fromOffset(310, 60), BackgroundTransparency = 1, Text = "", Visible = false, LayoutOrder = 2 }, slot)
local idleCard, idleBody, idleStub = Ui.ticket(idle, UDim2.new(1, -8, 1, -6), UDim2.fromOffset(4, 0), nil, 64, -0.6)
Ui.caps(idleBody, "•  Off duty", UDim2.new(1, -24, 0, 14), { Position = UDim2.fromOffset(16, 10), TextSize = 12, TextColor3 = P.ink2 })
Ui.label(idleBody, "Pick a run at the Dispatch board", UDim2.new(1, -24, 0, 20), { Position = UDim2.fromOffset(16, 26), TextSize = 14, Font = Theme.HeadingFont, TextColor3 = P.ink, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
local chip = Ui.label(idleStub, if touchLayout then "OPEN" else "J", UDim2.fromOffset(if touchLayout then 48 else 28, 26), {
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 0,
	BackgroundColor3 = P.violet,
	TextSize = 13,
	Font = Theme.HeadingFont,
	TextColor3 = P.paper,
	TextXAlignment = Enum.TextXAlignment.Center,
})
Ui.corner(chip, 8)
Ui.tactile(idleCard.Parent, 4, 1.03)
idle.Activated:Connect(function()
	local click = Ui.onClick
	if click then
		click()
	end
	openDispatch()
end)
t.idle = idle
t.idleAt = 0

-- Shows the OFF DUTY ticket when the top stack has nothing on it (no job; no crew strip, invitation or mission banner).
function view.checkIdle(now: number)
	if now < t.idleAt then
		return
	end
	t.idleAt = now + 0.3
	local busy = job ~= nil
	if not busy then
		for _, name in { "crew", "mission" } do
			for _, child in Hud.topSlot(name):GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					busy = true
				end
			end
		end
	end
	if idle.Visible == busy then
		idle.Visible = not busy
	end
end

-- Loading / unloading / boarding bar under the middle of the screen (layout() keeps it over the bottom panels): a
-- cream pill, a sage fill (its deeper lip shade, so it shows on the cream) inside it, the words over it in ink.
LOAD_H = 28
loadBack, loadFill = Ui.bar(gui, UDim2.fromOffset(340, LOAD_H), P.sageLip)
scaled(loadBack)
loadBack.AnchorPoint = Vector2.new(0.5, 0.5)
loadBack.Position = UDim2.fromScale(0.5, 0.62)
loadBack.Visible = false
loadBack.BackgroundColor3 = P.paper
loadBack:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, LOAD_H // 2)
loadFill:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, LOAD_H // 2)
Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1.5 }, loadBack)
loadText = Ui.label(loadBack, "", UDim2.fromScale(1, 1), { TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, ZIndex = 2, Font = Theme.DisplayFont, TextColor3 = P.ink })
end

-- ── The way to the target ──────────────────────────────────────────────────
-- The park circle (a ring and a light beam) and, on foot during a carry step, a small ring at the pile / the
-- person with a thin beam over their head; a floating label and an arrow (over the car, or over your head on foot).

local beacon: any, ring: any, pileRing: any, label: any, labelText: any, HIDDEN: any, PICKUP_COLOR: any, PILE_COLOR: any, UPRIGHT: any, hideGuide: any, placeGuide: any, pointArrow: any, GPS_COLOR: any, gps: any, myPosition: any, footTarget: any
do -- (its own block: the locals below stay out of the 200-register limit)
local guide = Instance.new("Folder")
guide.Name = "DeliveryGuide"
guide.Parent = workspace
-- The delivery's gold (the 3D guide's own colour, like the route on the maps: client/MapView.luau).
view.guideColor = Color3.fromRGB(245, 179, 79)

local function guidePart(name: string, size: Vector3, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = view.guideColor
	p.Size = size
	p.Transparency = transparency
	p.Parent = guide
	return p
end

local BEACON_WIDE = Vector3.new(240, 5, 5)
local BEACON_THIN = Vector3.new(240, 1.2, 1.2)
beacon = guidePart("Beacon", BEACON_WIDE, 0.55)
beacon.Shape = Enum.PartType.Cylinder
ring = guidePart("Ring", Vector3.new(0.2, Config.Jobs.DeliverRadius * 2, Config.Jobs.DeliverRadius * 2), 0.5)
ring.Shape = Enum.PartType.Cylinder
pileRing = guidePart("PileRing", Vector3.new(0.2, 7, 7), 0.35)
pileRing.Shape = Enum.PartType.Cylinder
label = guidePart("Label", Vector3.new(0.2, 0.2, 0.2), 1)
-- 3.6: the words (who, how far) in ink on a cream pill lined in the guide's colour: they read over a night street and
-- a sunny one alike.
local labelGui = Ui.make("BillboardGui", { Size = UDim2.fromOffset(260, 64), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 100000 }, label)
labelText = Ui.label(labelGui, "", UDim2.new(), {
	AutomaticSize = Enum.AutomaticSize.XY,
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 0.04,
	BackgroundColor3 = P.pill,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = P.ink,
	TextSize = 17,
	Font = Theme.DisplayFont,
	TextWrapped = false,
})
Ui.corner(labelText, 12)
Ui.stroke(labelText, view.guideColor, 2.5)
Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, labelText)
-- The arrow: a shaft and two sides of a head, pointing along -Z of its frame.
local arrowParts = {
	{ part = guidePart("ArrowShaft", Vector3.new(0.6, 0.4, 3.6), 0), offset = CFrame.new(0, 0, 0.8) },
	{ part = guidePart("ArrowLeft", Vector3.new(0.6, 0.4, 2.6), 0), offset = CFrame.lookAt(Vector3.new(-0.84, 0, -0.6), Vector3.new(0, 0, -1.6)) },
	{ part = guidePart("ArrowRight", Vector3.new(0.6, 0.4, 2.6), 0), offset = CFrame.lookAt(Vector3.new(0.84, 0, -0.6), Vector3.new(0, 0, -1.6)) },
}
HIDDEN = CFrame.new(0, -1000, 0)
PICKUP_COLOR = Color3.fromRGB(110, 190, 255)
PILE_COLOR = Color3.fromRGB(120, 235, 140)
UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis is X: stood up

function hideGuide()
	beacon.CFrame = HIDDEN
	ring.CFrame = HIDDEN
	pileRing.CFrame = HIDDEN
	label.CFrame = HIDDEN
	for _, a in arrowParts do
		a.part.CFrame = HIDDEN
	end
end
hideGuide()

local function paintGuide(color: Color3)
	if beacon.Color == color then
		return
	end
	for _, part in { beacon, ring } do
		part.Color = color
	end
	for _, a in arrowParts do
		a.part.Color = color
	end
	Ui.stroke(labelText, color, 2.5)
end

-- The park circle at p with the beam over it (or a thin beam over the pile / the person at `beamAt`), the label
-- over `labelAt` (default p).
function placeGuide(p: Vector3, color: Color3, beamAt: Vector3?, labelAt: Vector3?)
	paintGuide(color)
	ring.CFrame = CFrame.new(p + Vector3.new(0, 0.15, 0)) * UPRIGHT
	if beamAt then
		beacon.Size = BEACON_THIN
		-- Starts over the person's head, so it never hides them.
		beacon.CFrame = CFrame.new(beamAt + Vector3.new(0, 127, 0)) * UPRIGHT
	else
		beacon.Size = BEACON_WIDE
		beacon.CFrame = CFrame.new(p + Vector3.new(0, 120, 0)) * UPRIGHT
	end
	label.CFrame = CFrame.new((labelAt or p) + Vector3.new(0, 10, 0))
end

-- The arrow at `origin` pointing along `flat` (scale < 1: the small one over your head on foot).
function pointArrow(origin: Vector3?, flat: Vector3, scale: number)
	if origin and flat.Magnitude > 6 then
		local frame = CFrame.lookAt(origin, origin + flat.Unit)
		for _, a in arrowParts do
			a.part.CFrame = frame * (a.offset.Rotation + a.offset.Position * scale)
		end
	else
		for _, a in arrowParts do
			a.part.CFrame = HIDDEN
		end
	end
end

-- The GPS: a place picked on the big map (the job's target goes first).
GPS_COLOR = Color3.fromRGB(176, 92, 255) -- the purple of the GPS route on the maps (client/MapView.luau)
gps = nil

MapView.onWaypoint = function(landmark)
	if landmark then
		gps = { position = Vector3.new(landmark.x, Map.RoadTop, landmark.z), name = landmark.name }
		Hud.toast(`GPS: {landmark.name}`)
	else
		gps = nil
	end
	if not job then
		if gps then
			placeGuide(gps.position, GPS_COLOR)
		else
			hideGuide()
		end
	end
end

-- Seated: the car. On foot: you.
function myPosition(): Vector3?
	local seated = Drive.seatedCar()
	if seated and seated.PrimaryPart then
		return seated.PrimaryPart.Position
	end
	local root = myRoot()
	if root then
		return root.Position
	end
	local car = Drive.myCar()
	return if car and car.PrimaryPart then car.PrimaryPart.Position else nil
end

-- Where to go now on foot at a carry / lead stop: to the pile or the person (to pick a piece up, or to hand it
-- over), or to the back of your vehicle (to load what you hold, or to take the next one out).
-- Returns the point, its label and whether it is the vehicle; nil = the park circle (seated, or not a carry stop).
function footTarget(): (Vector3?, string?, boolean)
	if not job or Drive.seatedCar() then
		return nil, nil, false
	end
	local handling = job.handling
	if handling ~= "carry" and handling ~= "lead" then
		return nil, nil, false
	end
	local pickup = job.stage == "pickup"
	local holding = myCarrying() ~= nil
	local aboard = inVehicle() or 0
	if not holding and typeof(job.looseAt) == "Vector3" then
		-- A piece put down (G): the step says to pick it up again first.
		return job.looseAt, if handling == "lead" then "CATCH IT" else "PICK IT UP", false
	end
	local toVehicle = if pickup then holding else (not holding and aboard > 0)
	if toVehicle then
		local car = Drive.myCar()
		local chassis = car and car.PrimaryPart
		local root = myRoot()
		-- The vehicle's back (its CargoDoor attachment), if the vehicle is not far away.
		if chassis and root and (chassis.Position - root.Position).Magnitude < 150 then
			local door = chassis:FindFirstChild("CargoDoor")
			local back = if door and door:IsA("Attachment") then door.WorldPosition else (chassis.CFrame * CFrame.new(0, 0, chassis.Size.Z / 2 + 2)).Position
			local text = if pickup then (if handling == "lead" then "LEAD IT IN" else "LOAD IT HERE") else (if handling == "lead" then "LEAD ONE OUT" else "TAKE ONE OUT")
			return back, text, true
		end
		return nil, nil, false
	end
	local pile = job.pile
	if typeof(pile) ~= "Vector3" then
		return nil, nil, false
	end
	local person = if type(job.person) == "string" and job.person ~= "" then job.person:upper() else (if pickup then "PICK UP" else "HAND IT OVER")
	return pile, person, false
end
end

-- ── Level up ───────────────────────────────────────────────────────────────
-- A banner in the top stack (under the job panel; a level-up mostly comes as the job ends): LEVEL UP, the new level
-- and rank, what it unlocks; the XP bar flashes. Under the windows, so it never hides the delivery result.

local refreshLevel: () -> ()
do -- (a block of its own: its locals stay out of the module's 200-register limit)
local levelUpFrame = Ui.make("CanvasGroup", {
	Name = "LevelUp",
	Size = UDim2.new(0.82, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = P.paper,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Visible = false,
	ZIndex = 4,
}, Hud.topSlot("levelup"))
-- 3.6: paper with a violet line around it; LEVEL UP in small caps over the level (DisplayFont, ink), the rank, then
-- what it unlocks.
local levelUpPop = Ui.make("UIScale", { Scale = 1 }, levelUpFrame)
Ui.corner(levelUpFrame, 12)
Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.violet, Thickness = 1.5 }, levelUpFrame)
Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12) }, levelUpFrame)
Ui.list(levelUpFrame, true, 2, Enum.HorizontalAlignment.Center)
Ui.caps(levelUpFrame, "⬆  Level up", UDim2.new(1, 0, 0, 14), {
	TextSize = 12,
	TextColor3 = P.violet,
	TextXAlignment = Enum.TextXAlignment.Center,
	LayoutOrder = 1,
})
local levelUpTitle = Ui.label(levelUpFrame, "", UDim2.new(1, 0, 0, 30), {
	AutomaticSize = Enum.AutomaticSize.Y, -- a long rank wraps on a narrow stack
	TextSize = 26,
	Font = Theme.DisplayFont,
	TextColor3 = P.ink,
	TextXAlignment = Enum.TextXAlignment.Center,
	LayoutOrder = 2,
})
local levelUpUnlocks = Ui.label(levelUpFrame, "", UDim2.new(1, 0, 0, 0), {
	AutomaticSize = Enum.AutomaticSize.Y,
	TextSize = 14,
	Font = Theme.HeadingFont,
	TextColor3 = P.ink2,
	TextXAlignment = Enum.TextXAlignment.Center,
	LayoutOrder = 3,
})
local levelUpStamp = 0

local function showLevelUp(from: number, to: number)
	local unlocked: { string } = {}
	for level = from + 1, to do
		for _, name in unlocksAt(level) do
			table.insert(unlocked, name)
		end
	end
	local rank = Levels.rank(to)
	levelUpTitle.Text = `LEVEL {to}  ·  {rank:upper()}`
	levelUpUnlocks.Text = if #unlocked > 0 then `🔓  {table.concat(unlocked, "  ·  ")}` else "Better jobs, missions and cars wait on the next levels."
	levelUpStamp += 1
	local mine = levelUpStamp
	levelUpFrame.Visible = true
	levelUpPop.Scale = 0.8
	local pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(levelUpFrame, pop, { GroupTransparency = 0 }):Play()
	TweenService:Create(levelUpPop, pop, { Scale = 1 }):Play()
	-- The XP bar and the level circle flash sage.
	xpFill.BackgroundColor3 = P.sage
	levelChip.BackgroundColor3 = P.sage
	TweenService:Create(xpFill, TweenInfo.new(1.2), { BackgroundColor3 = P.violet }):Play()
	TweenService:Create(levelChip, TweenInfo.new(1.2), { BackgroundColor3 = P.lavender }):Play()
	Hud.toast(`LEVEL {to}! You are a {rank} now.`)
	task.delay(4.5, function()
		if levelUpStamp ~= mine then
			return
		end
		TweenService:Create(levelUpFrame, TweenInfo.new(0.5), { GroupTransparency = 1 }):Play()
		task.wait(0.55)
		if levelUpStamp == mine then
			levelUpFrame.Visible = false
		end
	end)
end

-- The level shown (nil until the save loaded: the first value is no level-up).
local shownLevel: number? = nil

-- The level circle, the rank, the XP bar; a level-up flashes and the open shop shows what it unlocked.
function refreshLevel()
	local xp = myXp()
	if xp == nil then
		levelChip.Text = "1"
		rankLabel.Text = string.upper(Levels.rank(1))
		xpLabel.Text = ""
		xpFill.Size = UDim2.fromScale(0, 1)
		return
	end
	local level = Levels.levelFor(xp)
	levelChip.Text = tostring(level)
	rankLabel.Text = string.upper(Levels.rank(level))
	if level >= Config.Levels.MaxLevel then
		xpLabel.Text = "MAX LEVEL"
	else
		local from = Levels.xpFor(level)
		xpLabel.Text = `{math.floor(xp - from)} / {Levels.xpFor(level + 1) - from} XP  ·  NEXT LV {level + 1}`
	end
	xpFill.Size = UDim2.fromScale(Levels.progress(xp), 1)
	local before = shownLevel
	if before == level then
		return
	end
	shownLevel = level
	if before ~= nil and level > before then
		showLevelUp(before, level)
	end
	if before ~= nil and shop.frame.Visible then
		renderShop()
	end
end
end

-- ── Car call ───────────────────────────────────────────────────────────────
-- The CarCall remote (server/CarCall.luau): (seconds left, the car's model) while a chauffeur drives your car to
-- you, nil when it is there or the call is over (a string instead of the model, or a table { seconds, car, reason },
-- is understood too). The top stack shows "Your car is on the way · 9 s" with a bar and how far it is, a marker
-- floats over the car (MapView pins it on the maps) and the CAR button counts down. The count runs on here between
-- two messages (a loop at 10 Hz, only while a call is on); a call that never ends gives up CALL_STALE s late.

type CarCallState = { arriveAt: number, total: number, car: Model?, doneAt: number?, doneText: string? }
local call: CarCallState? = nil
local callMarker: any
local onCarCall: (any, any) -> ()
-- (A block of its own: its locals do not count toward the module's 200-register limit.)
do
local CALL_COLOR = P.violet
local CALL_DONE_SHOWN = 3 -- seconds "Your car is here" stays
local CALL_STALE = 20

-- 3.6: a compact paper card, a violet edge and line (green when the car is here), a thin bar at the bottom.
local callLine = Ui.make("Frame", { Size = UDim2.new(0.78, 0, 0, 42), BackgroundColor3 = P.paper, BorderSizePixel = 0 }, Hud.topSlot("carcall"))
Ui.corner(callLine, 12)
callLine.Name = "CarCall"
callLine.Visible = false
local callStroke = Ui.stroke(callLine, CALL_COLOR, 1.5)
callStroke.Transparency = 0.35
local callEdge = Ui.edge(callLine, CALL_COLOR)
local callText = Ui.label(callLine, "", UDim2.new(1, -112, 0, 24), {
	Position = UDim2.fromOffset(18, 5),
	TextSize = 15,
	Font = Theme.DisplayFont,
	TextColor3 = P.ink,
	TextWrapped = false,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
local callDistance = Ui.caps(callLine, "", UDim2.fromOffset(84, 24), {
	Position = UDim2.new(1, -96, 0, 5),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 12,
	TextColor3 = P.ink2,
})
local callBack, callFill = Ui.bar(callLine, UDim2.new(1, -32, 0, 3), CALL_COLOR)
callBack.Position = UDim2.new(0, 18, 1, -9)

-- The marker over the car in the world (seen through walls, like the delivery label).
callMarker = Ui.make("BillboardGui", {
	Name = "CarCallMarker",
	Size = UDim2.fromOffset(200, 64),
	StudsOffsetWorldSpace = Vector3.new(0, 7, 0),
	AlwaysOnTop = true,
	LightInfluence = 0,
	MaxDistance = 3000,
	ResetOnSpawn = false,
	Enabled = false,
}, player:WaitForChild("PlayerGui"))
-- 3.6: on a cream pill with a violet line (it reads over a night street and a sunny one), the ▼ under it.
local markerPill = Ui.make("Frame", {
	Size = UDim2.new(1, -20, 0, 42),
	Position = UDim2.fromOffset(10, 0),
	BackgroundColor3 = P.pill,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
}, callMarker)
Ui.corner(markerPill, 12)
Ui.stroke(markerPill, CALL_COLOR, 2)
local markerText = Ui.label(markerPill, "", UDim2.new(1, 0, 0, 22), {
	Position = UDim2.fromOffset(0, 3),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 17,
	Font = Theme.DisplayFont,
	TextColor3 = P.ink,
	TextWrapped = false,
})
local markerSub = Ui.label(markerPill, "", UDim2.new(1, 0, 0, 14), {
	Position = UDim2.fromOffset(0, 24),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 12,
	Font = Theme.HeadingFont,
	TextColor3 = P.ink2,
	TextWrapped = false,
})
Ui.label(callMarker, "▼", UDim2.new(1, 0, 0, 22), {
	Position = UDim2.fromOffset(0, 42),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 20,
	Font = Enum.Font.GothamBlack,
	TextColor3 = CALL_COLOR,
	TextStrokeColor3 = P.pill,
	TextStrokeTransparency = 0,
})

local callLoop = false

local function carPart(car: Model?): BasePart?
	if not car or not car.Parent then
		return nil
	end
	return car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")
end

local function setCarButton(text: string)
	-- (the CAR entry of the "…" menu: its icon, then the text)
	local button = hudButtons.car
	if button and button.Text ~= `🚗  {text}` then
		button.Text = `🚗  {text}`
	end
end

local function hideCall()
	callLine.Visible = false
	callMarker.Enabled = false
	callMarker.Adornee = nil
	setCarButton("CAR")
	MapView.setCar(nil)
end

-- One beat of the call: the line, the marker, the button. False when there is nothing more to show.
local function updateCall(): boolean
	local current = call
	if not current then
		hideCall()
		return false
	end
	local now = os.clock()
	local doneAt = current.doneAt
	if (doneAt and now > doneAt) or (not doneAt and now > current.arriveAt + CALL_STALE) then
		call = nil
		hideCall()
		return false
	end
	local part = carPart(current.car)
	local root = myRoot()
	local distance = if part and root then math.floor(Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z).Magnitude + 0.5) else nil
	callLine.Visible = true
	callDistance.Text = if distance then `{distance} m` else ""
	if doneAt then
		callText.Text = current.doneText or "✔  Your car is here"
		callStroke.Color = if current.doneText then P.warn else P.good
		callFill.BackgroundColor3 = if current.doneText then P.warn else P.good
		callEdge.BackgroundColor3 = callFill.BackgroundColor3
		callFill.Size = UDim2.fromScale(1, 1)
		markerText.Text = "🚗  YOUR CAR"
		markerSub.Text = if distance then `here · {distance} m` else "here"
		setCarButton("CAR")
	else
		local left = math.max(0, math.ceil(current.arriveAt - now))
		callText.Text = if left > 0 then `🚗  Your car is on the way · {left} s` else "🚗  Your car is almost here"
		callStroke.Color = CALL_COLOR
		callFill.BackgroundColor3 = CALL_COLOR
		callEdge.BackgroundColor3 = CALL_COLOR
		callFill.Size = UDim2.fromScale(math.clamp(1 - (current.arriveAt - now) / current.total, 0, 1), 1)
		markerText.Text = "🚗  YOUR CAR"
		markerSub.Text = (if left > 0 then `{left} s` else "arriving") .. (if distance then `  ·  {distance} m` else "")
		setCarButton(if left <= 0 then "CAR" elseif touchLayout then `CAR {left}s` else `CAR · {left} s`)
	end
	if callMarker.Adornee ~= part then
		callMarker.Adornee = part
	end
	callMarker.Enabled = part ~= nil and gui.Enabled
	return true
end

function onCarCall(first: any, second: any)
	local seconds, car, reason = first, second, nil
	if type(first) == "table" then
		seconds = first.seconds or first.left or first.eta
		car = first.car or first.model
		reason = first.reason or first.text
	end
	if type(second) == "string" then
		reason = second
	end
	local model: Model? = if typeof(car) == "Instance" and car:IsA("Model") then car else nil
	local now = os.clock()
	local old = call
	local running = old ~= nil and old.doneAt == nil
	if type(seconds) == "number" and seconds >= 0 then
		call = {
			arriveAt = now + seconds,
			-- The bar fills over the whole trip: the first message says how long it is.
			total = if running and old then math.max(old.total, seconds, 1) else math.max(seconds, 1),
			car = model or (if running and old then old.car else nil),
		}
	elseif old or reason then
		local failed = type(reason) == "string" and reason ~= ""
		call = {
			arriveAt = now,
			total = 1,
			-- A call that failed (car wrecked, cancelled) has no car to mark.
			car = if failed then nil else model or (if old then old.car else nil),
			doneAt = now + CALL_DONE_SHOWN,
			doneText = if type(reason) == "string" and reason ~= "" then `🚗  {reason}` else nil,
		}
	else
		return
	end
	MapView.setCar(if call then call.car else nil)
	if callLoop then
		return
	end
	callLoop = true
	task.spawn(function()
		while true do
			local ok, more = pcall(updateCall)
			if not ok then
				warn(`[Hud] car call: {more}`)
				call = nil
				pcall(hideCall)
				break
			end
			if not more then
				break
			end
			task.wait(0.1)
		end
		callLoop = false
	end)
end
end

-- ── Layout ─────────────────────────────────────────────────────────────────
-- Everything outside the windows is placed from the size of the screen: the ScreenGui's area under Roblox's top
-- bar, W × H pixels, and one scale S = Ui.scaleFor(W × H) (1 at 1150 × 680, from 0.55 on phones to 1.1). It runs
-- again when the screen changes or the ADMIN button comes or goes. 3.6, the concept's regions:
--
--   COMPUTER (keyboard and mouse)                       TOUCH, held sideways (phone or tablet, no keyboard)
--   ┌──────────────────────────────────────────────┐    ┌──────────────────────────────────────────────┐
--   │ chat     ┌── top stack ──┐   (player list)   │    │ money   ┌── top stack ──┐   MAP CREW …      │
--   │ (Roblox) │ ticket / crew │                   │    │ minimap │ ticket / crew │                   │
--   │          │ car call      │                   │    │ health  │ car call      │                   │
--   │          │ level up      │      MAP CREW …   │    │         │ toasts        │                   │
--   │          │ toasts        │      ┌weapon───┐  │    │         └───────────────┘                   │
--   │ money    └───────────────┘      └─────────┘  │    │            (loading bar)  ┌weapon┐  (FIRE)   │
--   │ minimap        (loading bar)      ╭─────╮    │    │ (thumb-        hint       ╭─────╮           │
--   │ health        hint                │dial │    │    │  stick)     tags 1-5     │dial │   (jump)   │
--   │               tags 1-5            ╰─────╯    │    │                          ╰─────╯           │
--   └──────────────────────────────────────────────┘    └──────────────────────────────────────────────┘
--
--   * Margins 16 px, gaps 8 px. The ADMIN button (client/AdminPanel.luau, 90 × 32 at 16 px from the right, 56 from
--     the top, unscaled) keeps the top right corner (down to ADMIN_BOTTOM) while it shows (admins, Studio).
--   * Left: money + minimap + health, one column (LEFT_W × LEFT_H × S): bottom left on a computer (the chat is top
--     left), top left on touch (the thumbstick is bottom left).
--   * Bottom right: the speed dial in the corner, the weapon label on it. Touch: the FIRE button just over Roblox's jump
--     button (70 px at 95 / 90 px from the corner on a small screen, 120 px at 170 / 210 px on a big one), the dial and
--     the weapon label left of them. A touch screen with a keyboard: FIRE left of the dial.
--   * Bottom centre: the tags between the left column (touch: the thumbstick's corner) and the dial, the hint over them
--     (over the dial when there is no room).
--   * The utilities (MAP, CREW, "…"): a computer has the player list (leaderstats) top right, so they sit just over the
--     weapon label and the menu opens upward; on touch top right (under ADMIN) and the menu opens downward.
--   * Top stack: centred, TOP_W × S wide (narrower down to TOP_MIN_W before it gets smaller), between the minimap
--     (touch) and the utilities / ADMIN, and as tall as the room over the bottom panels allows (TOP_EST_H: the ticket,
--     the mission banner and the car call line, with the loading bar's room under it); smaller when it has to. On a
--     touch screen with no room beside them (upright) it goes under the minimap and the utilities.
--   * The loading bar: at 62 % of the height, under the top stack and over the panels at the bottom.

do -- (its own block: the locals below stay out of the 200-register limit)
local MARGIN = 16
local GAP = 8
local ADMIN_BOTTOM = 96 -- client/AdminPanel.luau: the ADMIN button at (1, -16, 0, 56), 90 × 32, unscaled
local ADMIN_LEFT = 16 + 90 + GAP
local TOUCH_BUTTON_MIN = 0.8
local TOP_EST_H = 300 -- the top stack's usual height (unscaled): the ticket, the mission banner (up to 80) and the car call line
local TOP_MIN_W = 380 -- a narrow span first makes the top stack narrower (down to this), then smaller
local HINT_LINES = 2 -- the hint: a main line and a quiet one

type Box = { x0: number, y0: number, x1: number, y1: number }

local function box(x0: number, y0: number, x1: number, y1: number): Box
	return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

-- The top edge of the highest box that starts at or under `y` and shares columns with x0 .. x1 (else `floor`).
local function ceilingBelow(boxes: { Box }, x0: number, x1: number, y: number, floor: number): number
	local limit = floor
	for _, b in boxes do
		if b.y0 >= y and math.min(b.x1, x1) - math.max(b.x0, x0) > 0 then
			limit = math.min(limit, b.y0)
		end
	end
	return limit
end

local function screenArea(): Vector2
	local size = gui.AbsoluteSize
	if size.X < 2 or size.Y < 2 then
		return Ui.screenSize()
	end
	return size
end

-- The ADMIN button shows (the same rule as client/AdminPanel.luau).
local function adminButtonShown(): boolean
	return player:GetAttribute("Admin") == true or (Config.Admin.InStudio and RunService:IsStudio())
end

layout = function()
	local size = screenArea()
	local W, H = size.X, size.Y
	local S = Ui.scaleFor(size)
	for _, s in scales do
		s.Scale = S
	end
	-- What the top stack and the loading bar must stay above.
	local below: { Box } = {}

	-- Left: money, the minimap and the health row.
	setScale(leftStack, S)
	local left: Box
	if touchLayout then
		leftStack.AnchorPoint = Vector2.zero
		leftStack.Position = UDim2.fromOffset(MARGIN, MARGIN)
		left = box(MARGIN, MARGIN, MARGIN + LEFT_W * S, MARGIN + LEFT_H * S)
	else
		leftStack.AnchorPoint = Vector2.new(0, 1)
		leftStack.Position = UDim2.new(0, MARGIN, 1, -MARGIN)
		left = box(MARGIN, H - MARGIN - LEFT_H * S, MARGIN + LEFT_W * S, H - MARGIN)
		table.insert(below, left)
	end

	-- Bottom right: FIRE over the jump button (touch); the dial and the weapon label. cornerLeft: where they begin.
	local admin = adminButtonShown()
	local rightTop = if admin then ADMIN_BOTTOM else MARGIN
	local fireSize = FIRE_SIZE * S
	local dialSize = carPanel.Size.X.Offset * S
	local weaponW, weaponH = weaponBar.Size.X.Offset * S, weaponBar.Size.Y.Offset * S
	setScale(fire, S)
	setScale(carPanel, S)
	setScale(weaponBar, S)
	fire.AnchorPoint = Vector2.new(1, 1)
	local columnRight = W - MARGIN
	local columnBottom = H - MARGIN
	local thumb: Box? = nil
	if touchLayout then
		local small = math.min(W, H) <= 500
		local jumpSize = if small then 70 else 120
		local jump = box(W - (if small then 95 else 170), H - (if small then 90 else 210), 0, 0)
		jump.x1, jump.y1 = jump.x0 + jumpSize, jump.y0 + jumpSize
		local fireBottom = jump.y0 - 10
		fire.Position = UDim2.fromOffset(W - 40, fireBottom)
		local fireBox = box(W - 40 - fireSize, fireBottom - fireSize, W - 40, fireBottom)
		table.insert(below, fireBox)
		table.insert(below, jump)
		columnRight = math.min(jump.x0, fireBox.x0) - GAP
		columnBottom = H - GAP
		-- Roblox's thumbstick lives in the bottom left corner: nothing of ours goes there.
		thumb = box(0, H - (if small then 190 else 260), math.max(if small then 170 else 230, W * 0.22), H)
	elseif UserInputService.TouchEnabled then
		-- A touch screen with a keyboard: FIRE left of the dial.
		fire.Position = UDim2.fromOffset(W - MARGIN - math.max(dialSize, weaponW) - 12, H - MARGIN)
		local fireBox = box(W - MARGIN - math.max(dialSize, weaponW) - 12 - fireSize, H - MARGIN - fireSize, W - MARGIN - math.max(dialSize, weaponW) - 12, H - MARGIN)
		table.insert(below, fireBox)
	end
	carPanel.AnchorPoint = Vector2.new(1, 1)
	carPanel.Position = UDim2.fromOffset(columnRight - 8 * S, columnBottom)
	local dialTop = columnBottom - dialSize
	weaponBar.AnchorPoint = Vector2.new(1, 1)
	weaponBar.Position = UDim2.fromOffset(columnRight, dialTop - GAP)
	local weaponTop = dialTop - GAP - weaponH
	local columnLeft = columnRight - math.max(weaponW, dialSize)
	local column = box(columnLeft, weaponTop, columnRight, columnBottom)
	table.insert(below, column)
	local cornerLeft = columnLeft
	for _, b in below do
		if b ~= left and b.y1 > H * 0.5 then
			cornerLeft = math.min(cornerLeft, b.x0)
		end
	end

	-- Bottom centre: the tags with the hint over them.
	local spanLeft = (if thumb then thumb.x1 else left.x1) + 12
	local spanRight = cornerLeft - 12
	local tagScale = math.clamp((spanRight - spanLeft) / BAR_W, 0.45, S)
	local tagsX = math.clamp(W / 2, spanLeft + BAR_W * tagScale / 2, math.max(spanLeft + BAR_W * tagScale / 2, spanRight - BAR_W * tagScale / 2))
	local tagsBottom = H - (if touchLayout then GAP else MARGIN)
	if spanRight - spanLeft < BAR_W * tagScale then
		-- No room between them: over the dial's column, right-aligned with it.
		tagsX = columnRight - BAR_W * tagScale / 2
		tagsBottom = weaponTop - GAP
	end
	setScale(hotbar, tagScale)
	hotbar.AnchorPoint = Vector2.new(0.5, 1)
	hotbar.Position = UDim2.fromOffset(tagsX, tagsBottom)
	local tagsTop = tagsBottom - HOTBAR_H * tagScale
	table.insert(below, box(tagsX - BAR_W * tagScale / 2, tagsTop, tagsX + BAR_W * tagScale / 2, tagsBottom))
	local hintWidth = math.max(BAR_W * tagScale, 2 * math.min(tagsX - spanLeft, spanRight - tagsX))
	local hintAt = tagsTop - 48 * tagScale -- room for a lifted tag's name (lift 9, 10 + 24 px pill at 1.12, 4 spare)
	local hintSize = math.max(11, math.floor(15 * S + 0.5))
	hint.TextSize = hintSize
	view.hintSub = math.max(10, math.floor(13 * S + 0.5))
	local hintMax = hint:FindFirstChild("Max")
	if hintMax and hintMax:IsA("UISizeConstraint") then
		hintMax.MaxSize = Vector2.new(math.max(140, hintWidth), math.huge)
	end
	hint.Position = UDim2.fromOffset(tagsX, hintAt)
	table.insert(below, box(tagsX - hintWidth / 2, hintAt - HINT_LINES * (hintSize + 4) - 12, tagsX + hintWidth / 2, hintAt))

	-- The utilities: a row (its Size is the unscaled row), over the weapon label (computer) or top right (touch).
	local base = if touchLayout then math.max(S, TOUCH_BUTTON_MIN) else S
	local gw, gh = buttonGrid.Size.X.Offset, buttonGrid.Size.Y.Offset
	local buttonScale: number
	local gridTop: number
	if touchLayout then
		buttonScale = math.clamp(base, 0.45, base)
		gridTop = rightTop
	else
		local room = math.max(0, weaponTop - 12 - rightTop)
		buttonScale = math.clamp(room / gh, 0.45, base)
		gridTop = math.max(rightTop, weaponTop - 12 - gh * buttonScale)
	end
	setScale(buttonGrid, buttonScale)
	buttonGrid.AnchorPoint = Vector2.new(1, 0)
	buttonGrid.Position = UDim2.fromOffset(W - MARGIN, gridTop)
	local grid = box(W - MARGIN - gw * buttonScale, gridTop, W - MARGIN, gridTop + gh * buttonScale)
	local gridHigh = grid.y0 < H * 0.45
	-- The menu opens toward the middle: down from a high row (left of it when the weapon label or FIRE is in the
	-- way), up from a low one.
	local menu = view.menu
	local menuW = menu.Size.X.Offset * buttonScale
	local fitsDown = grid.y1 + (8 + view.menuHeight) * buttonScale <= ceilingBelow(below, grid.x1 - menuW, grid.x1, grid.y1, H)
	if gridHigh and not fitsDown then
		menu.AnchorPoint = Vector2.new(1, 0)
		menu.Position = UDim2.new(0, -8, 0, 0)
	else
		menu.AnchorPoint = Vector2.new(1, if gridHigh then 0 else 1)
		menu.Position = if gridHigh then UDim2.new(1, 0, 1, 8) else UDim2.new(1, 0, 0, -10)
	end

	-- The top stack: as big as the span (spanL .. spanR from y) and the room under it allow.
	local loadRoom = GAP + LOAD_H * S + GAP
	local function fit(y: number, spanL: number, spanR: number): (number, number, number)
		local span = spanR - spanL
		local width = math.clamp(span / S, TOP_MIN_W, TOP_W)
		local scale = math.min(S, span / width)
		local half = width * scale / 2
		local cx = math.clamp(W / 2, spanL + half, math.max(spanL + half, spanR - half))
		local floor = ceilingBelow(below, cx - half, cx + half, y, H)
		scale = math.min(scale, (floor - loadRoom - y) / TOP_EST_H)
		return scale, cx, width
	end
	local topY = 14
	local spanL, spanR = MARGIN, W - MARGIN
	if touchLayout then
		spanL = left.x1 + GAP
	end
	if gridHigh then
		spanR = math.min(spanR, grid.x0 - GAP)
	end
	if admin then
		spanR = math.min(spanR, W - ADMIN_LEFT)
	end
	local topScale, topX, topWidth = fit(topY, spanL, spanR)
	if touchLayout and topScale < S * 0.8 then
		-- No room beside the minimap and the utilities (upright): under them, the whole width.
		local y = math.max(left.y1, if gridHigh then grid.y1 else 0) + GAP
		local scale, x, width = fit(y, MARGIN, W - MARGIN)
		if scale > topScale then
			topY, topScale, topX, topWidth = y, scale, x, width
		end
	end
	topScale = math.max(topScale, 0.3)
	setScale(topStack, topScale)
	topStack.Size = UDim2.fromOffset(topWidth, 0)
	topStack.Position = UDim2.fromOffset(topX, topY)
	view.fitTicket()

	-- The loading bar: at 62 % of the height, under the top stack, over the bottom panels.
	local loadHalf = LOAD_H * S / 2
	local topBottom = topY + TOP_EST_H * topScale
	local loadFloor = ceilingBelow(below, W / 2 - 170 * S, W / 2 + 170 * S, topBottom, H)
	local loadY = math.min(H * 0.62, loadFloor - GAP - loadHalf)
	if loadY - loadHalf < topBottom + GAP then
		loadY = math.min(topBottom + GAP + loadHalf, loadFloor - GAP - loadHalf)
	end
	loadBack.Position = UDim2.fromOffset(W / 2, loadY)
end
end

-- ── Updates ────────────────────────────────────────────────────────────────

function Hud.setState(newState: any)
	state = newState
	moneyLabel.Text = Ui.money(state.money)
	refreshLevel()
	for id, count in hotbarCounts do
		count.Text = tostring(state.items[id] or 0)
	end
	renderWeapons()
	if shop.frame.Visible then
		renderShop()
	end
	if backpack.frame.Visible then
		renderBackpack()
	end
end

function Hud.setJob(newJob: any)
	job = newJob
	view.ticket.wrap.Visible = job ~= nil
	view.ticket.meta0 = ""
	view.ticket.idleAt = 0
	local giveUp = hudButtons.giveup
	if giveUp then
		giveUp.Visible = job ~= nil
	end
	if backpack.frame.Visible then
		renderBackpack()
	end
	if not job then
		hideGuide()
		loadBack.Visible = false
		MapView.setTarget(nil)
		if gps then
			placeGuide(gps.position, GPS_COLOR)
		end
		return
	end
	view.fillTicket()
	MapView.setTarget(job.position)
	-- Loading / unloading / boarding progress.
	local pickup = job.stage == "pickup"
	local progress = job.progress or 0
	loadBack.Visible = progress > 0
	loadFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	loadText.Text = if job.handling == "board" then (if pickup then "GETTING ON... wait in the circle" else "GETTING OFF... wait in the circle")
		elseif job.handling == "serve" then "SERVING... hold still"
		elseif pickup then "LOADING... hold still"
		else "UNLOADING... hold them off!"
end

function Hud.setVisible(visible: boolean)
	gui.Enabled = visible
	MapView.setVisible(visible)
	if visible then
		requestLayout()
	end
	callMarker.Enabled = visible and call ~= nil and callMarker.Adornee ~= nil
end

local lastShop: string? = nil
local lastHolding: string? = nil

-- 3.6, the hint over the tags: what to do right now in ink, a quieter line under it (RichText; both escaped).
local function setHint(main: string, sub: string?)
	local text = if main == "" then "" else view.esc(main)
	if text ~= "" and sub and sub ~= "" then
		text ..= `\n<font size="{view.hintSub or 13}" color="{view.hex(P.ink2)}">{view.esc(sub)}</font>`
	end
	if hint.Text ~= text then
		hint.Text = text
		hint.Visible = text ~= ""
	end
end

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		return
	end
	local now = os.clock()
	view.checkIdle(now)
	-- The car: the speed dial.
	local car = Drive.myCar()
	local seatedIn, driving = Drive.seatedCar()
	local d = view.dial
	if car then
		local carId = tostring(car:GetAttribute("CarId"))
		local stage = tonumber(car:GetAttribute("Stage")) or 0
		local health = (car:GetAttribute("Health") or 0) :: number
		local maxHealth = math.max(1, (car:GetAttribute("MaxHealth") or 1) :: number)
		local share = math.clamp(health / maxHealth, 0, 1)
		local capacity = Economy.stageCapacity(carId, stage)
		local loaded = tonumber(car:GetAttribute("CargoCount")) or inVehicle() or 0
		local inside = seatedIn == car
		local pct = math.floor(share * 100 + 0.5)
		-- The slow parts: only when they change.
		local shown = `{carId}|{stage}|{pct}|{capacity}|{loaded}|{inside}`
		if d.shown ~= shown then
			d.shown = shown
			local def = Economy.findCar(carId)
			local stageDef = Economy.stageDef(carId, stage)
			d.name.Text = string.upper(if stageDef then stageDef.name elseif def then def.name else "Car")
			d.condText.Text = if share <= 0.25 then `⚠ {pct}%` else `{pct}%`
			d.condText.TextColor3 = if share <= 0.25 then P.danger else P.ink
			d.condFill.Size = UDim2.fromScale(share, 1)
			d.condFill.BackgroundColor3 = if share > 0.5 then P.violet elseif share > 0.25 then P.warn else P.danger
			view.drawPips(capacity, loaded)
			-- On foot the dial dims and keeps your parked car's condition.
			d.group.GroupTransparency = if inside then 0 else 0.35
			d.unit.Text = if inside then "KM/H" else "PARKED"
		end
		if inside then
			local chassis = car.PrimaryPart
			local v = if chassis then chassis.AssemblyLinearVelocity else Vector3.zero
			local speed = math.floor(Vector3.new(v.X, 0, v.Z).Magnitude)
			local boost = Drive.boosting()
			local text = (if boost then "⚡" else "") .. tostring(speed)
			if d.speed.Text ~= text then
				d.speed.Text = text
				d.speed.TextColor3 = if boost then P.violet else P.ink
				local top = math.max(1, tonumber(car:GetAttribute("MaxSpeed")) or 80)
				d.needle.Rotation = -135 + 270 * math.clamp(speed / top, 0, 1)
			end
		elseif d.speed.Text ~= "–" then
			d.speed.Text = "–"
			d.speed.TextColor3 = P.ink2
			d.needle.Rotation = -135
		end
	elseif d.shown ~= "none" then
		d.shown = "none"
		d.name.Text = "NO CAR"
		d.speed.Text = "–"
		d.speed.TextColor3 = P.ink2
		d.unit.Text = "CALL IT: … → CAR"
		d.condText.Text = ""
		d.condFill.Size = UDim2.fromScale(0, 1)
		d.needle.Rotation = -135
		d.group.GroupTransparency = 0.35
		view.drawPips(0, 0)
	end

	-- Your health (the Humanoid's).
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local life = if humanoid then math.ceil(humanoid.Health) else 0
	if life ~= view.health then
		view.health = life
		local most = if humanoid then math.max(1, humanoid.MaxHealth) else 100
		view.healthText.Text = tostring(life)
		view.healthFill.Size = UDim2.fromScale(math.clamp(life / most, 0, 1), 1)
		view.healthFill.BackgroundColor3 = if life / most > 0.3 then P.violet else P.danger
	end

	-- Got in / out, cargo in your hands, or the car gun changed: the weapon label shows what fires now.
	if weaponBarKey() ~= shownWeaponBar then
		renderWeapons()
	end

	local touch = UserInputService.TouchEnabled
	fire.Visible = touch
	-- Which shop am I in?
	local inShop: string? = nil
	for id in Map.Shops do
		if nearShop(id) and id ~= "depot" then
			inShop = id
		end
	end
	local root = myRoot()
	local safe = root ~= nil and Map.isSafe(root.Position.X, root.Position.Z)
	local holding = myCarrying()
	if holding ~= lastHolding then
		-- Picked up / put down: the backpack shows it.
		lastHolding = holding
		if backpack.frame.Visible then
			renderBackpack()
		end
	end
	-- The hint: during a job its step (and how far this stop is), else what this place is about.
	local step = if job and type(job.step) == "string" then job.step else ""
	if job and step ~= "" then
		local needed = tonumber(job.needed) or 0
		local done = tonumber(job.delivered) or 0
		local progress = if needed > 0 and job.handling ~= "drive" then `{math.min(done, needed)} of {needed} {if job.stage == "pickup" then "loaded" else "delivered"}` else ""
		local hands = if holding == "horse" then "leading a horse: no gun, no sprint" elseif holding then "hands full: no gun, no sprint" else ""
		setHint(step, if progress ~= "" and hands ~= "" then `{progress} · {hands}` else progress .. hands)
	elseif holding then
		-- G is the server's "Put down" / "Let go" prompt key (server/Cargo.luau); touch screens tap the prompt.
		setHint(if holding == "horse" then "🐴  Leading a horse" else "✋  Hands full", if holding == "horse" then `no gun, no sprint · {if touch then "tap LET GO" else "G lets go"}` else `no gun, no sprint · E loads / hands over · {if touch then "tap PUT DOWN" else "G puts it down"} to shoot`)
	elseif inShop then
		setHint(`🏪  {Map.Shops[inShop].name}`, "walk to the counter and press E")
	elseif seatedIn and not driving then
		local gun = if state then Economy.findWeapon(state.weapon) else nil
		setHint("🪟  Riding along", if gun and not gun.oneHanded then `the {gun.name} is too big for the window · Q to a pistol, revolver or SMG` else "right mouse aims, left mouse shoots out of the window · Space gets out")
	elseif safe and not job then
		setHint("🛡️  Safe zone", `shops around the depot · {if touch then "OFF DUTY ticket" else "J"} for the Dispatch board`)
	elseif not car then
		setHint("🚗  No car out", "the … menu → CAR calls it")
	elseif not seatedIn and not job then
		setHint("🚶  On foot", if touch then "FIRE shoots · E at your car to drive" else "right mouse aims, left mouse shoots · E at your car to drive")
	else
		setHint("")
	end
	if inShop ~= lastShop then
		lastShop = inShop
		if shop.frame.Visible then
			renderShop()
		end
	end

	-- The job.
	if job then
		local circle: Vector3 = job.position
		local pickup = job.stage == "pickup"
		-- The pile / the person of a carry stop gets a small ring of its own.
		local pile = job.pile
		if typeof(pile) == "Vector3" and (job.handling == "carry" or job.handling == "lead") then
			pileRing.CFrame = CFrame.new(pile + Vector3.new(0, 0.2, 0)) * UPRIGHT
			pileRing.Color = PILE_COLOR
		else
			pileRing.CFrame = HIDDEN
		end
		local footAt, footText, atVehicle = footTarget()
		local target: Vector3 = footAt or circle
		if footAt then
			placeGuide(circle, PILE_COLOR, if atVehicle then nil else footAt, footAt)
			if atVehicle then
				beacon.CFrame = HIDDEN -- no beam through your own truck
			end
		else
			placeGuide(circle, if pickup then PICKUP_COLOR else view.guideColor)
		end
		local person = if type(job.person) == "string" and job.person ~= "" then job.person else nil
		local position = myPosition()
		local distance: number? = nil
		if position then
			local flat = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
			distance = math.floor(flat.Magnitude)
			labelText.Text = if footText then `{footText}\n{distance} m` else (if pickup then "PICK UP" else string.upper(person or job.customer)) .. `\n{distance} m`
			local chassis = if seatedIn then seatedIn.PrimaryPart else nil
			if chassis then
				pointArrow(chassis.Position + Vector3.new(0, 11, 0), flat, 1)
			elseif root then
				pointArrow(root.Position + Vector3.new(0, 4.5, 0), flat, 0.6)
			end
		end
		view.tickTicket(distance)
	elseif gps then
		local position = myPosition()
		if position then
			local flat = Vector3.new(gps.position.X - position.X, 0, gps.position.Z - position.Z)
			local distance = math.floor(flat.Magnitude)
			labelText.Text = `{gps.name}\n{distance} m`
			if distance < 30 then
				Hud.toast(`You are at {gps.name}.`)
				gps = nil
				MapView.setWaypoint(nil)
				hideGuide()
			else
				local chassis = if seatedIn then seatedIn.PrimaryPart else nil
				if chassis then
					pointArrow(chassis.Position + Vector3.new(0, 11, 0), flat, 1)
				elseif root then
					pointArrow(root.Position + Vector3.new(0, 4.5, 0), flat, 0.6)
				end
			end
		end
	end
end)

function Hud.start()
	layout()
	refreshLevel()
	player:GetAttributeChangedSignal("Xp"):Connect(refreshLevel)
	-- The layout follows the screen (a resized window, a phone turned), and the ADMIN button.
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(requestLayout)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(requestLayout)
	end
	player:GetAttributeChangedSignal("Admin"):Connect(requestLayout)
	MapView.start(gui, leftStack)
	-- Calling your car (server/CarCall.luau).
	local ok, err = pcall(function()
		Net.get("CarCall").OnClientEvent:Connect(onCarCall)
	end)
	if not ok then
		warn(`[Hud] no CarCall remote: {err}`)
	end
	-- 3.6: ESC closes the open window (the footers say so: the HUD's and, through Hud.onCloseWindows, the other
	-- modules'), the big map and the "…" menu. Roblox's menu takes the Escape key itself, hence MenuOpened as well.
	local function escape()
		if MapView.isOpen() then
			MapView.toggle()
		end
		closeWindows()
	end
	game:GetService("GuiService").MenuOpened:Connect(escape)
	-- Keys.
	UserInputService.InputBegan:Connect(function(input, processed)
		if not gui.Enabled or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Escape then
			escape()
			return
		end
		if processed then
			return
		end
		if key == Enum.KeyCode.M then
			MapView.toggle()
		elseif key == Enum.KeyCode.J then
			openDispatch()
		elseif key == Enum.KeyCode.B then
			toggleBackpack()
		else -- (Q: the weapon wheel, client/WeaponWheel.luau)
			local numbers = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
			local index = table.find(numbers, key)
			if index and Config.Items[index] then
				useItem(Config.Items[index].id)
			end
		end
	end)
end

return Hud
