--!strict
-- The interface: money and the driver level (the rank, a hairline XP line; the numbers on hover; a banner on a
-- level-up), the minimap (client/MapView.luau) and your health, the vehicle (speed, condition, cargo slots), the
-- active job (the contract group: what it is, where, the objectives, the deadline and the pay; the hold progress),
-- the actions (MAP, CREW and MENU with every other action and its key), the consumables (items, keys 1-5), the
-- employers (their car and gun rewards), the shops (opened by their counters; earned guns are not sold; the car guns at
-- Wrench Garage), the weapon (your gun, or the car gun while you drive a car that has one), the backpack (with the
-- job's cargo), the delivery result (with the XP, a level-up and the crew's pay split), toasts, the FIRE button for
-- touch screens and the way to the target (the park circle with a beam, on foot the pile / the person or the
-- vehicle's back, a small waypoint with the name and the distance).
-- Driver levels (shared/Levels.luau): what your level does not reach yet shows LEVEL N (cars at the dealer, guns,
-- car guns, an employer's job); the server refuses it anyway.
-- The job board is client/DispatchUi.luau (3.6): J, the JOBS entry, the depot counter and NEXT JOB run Hud.onJobs.
-- CREW, ESTATE, MISSIONS, SOUND run the hooks Hud.onCrew (client/CrewPanel.luau), Hud.onEstate (client/EstateUi.luau),
-- Hud.onMissions (client/MissionsUi.luau) and Hud.onSound (client/Sounds.luau), set by the client's Main; Hud.setBadge
-- and Hud.flashButton mark an action (the crew's invitations). Hud.topSlot gives other modules a place in the contract
-- column, under the contract group (the tutorial's hint, the crew strip and the invitation card, the mission banner,
-- the repair timer). Calling your car (the CarCall remote, server/CarCall.luau): a status line "Your car is on the
-- way · 9 s" in that column, a marker over the car in the world and on the maps.
-- Where everything sits on a computer and on a touch screen, so nothing overlaps: see ── Layout ── below.
-- 3.8, the contract UI (Codex's design/ui-contract/, approved by the owner): the world is the main view. Compact white
-- type over the scene on a localized charcoal scrim (or a text stroke), flat square shapes, fine lines and small red
-- accents (the contract marker, the destination, urgent states); the colours and the small pieces are in
-- client/HudContract.luau (P below). Upper left the contract group, upper right MAP [M] CREW [K] MENU, lower left the
-- cash and rank over the monochrome minimap and a thin health bar, lower right the weapon (or the cargo in your hands)
-- and the vehicle line ("OLD VAN / 72% / CARGO 3 OF 4", the speed while driving) over INVENTORY [I], lower centre one
-- contextual action in a key box with a fine progress line. The windows' rows are slim charcoal rows.
-- 3.9: the bag moved to I (B holsters / draws the gun, V punches or strikes: client/Holster.luau); on foot the weapon
-- line says HANDS · [B] DRAW · [V] PUNCH or the gun · [B] HOLSTER · [V] STRIKE; a touch screen gets PUNCH / STRIKE
-- and DRAW / HOLSTER buttons over FIRE.
-- A shop card whose def has `requires` (a campaign, or a list of them) shows "🔒 FINISH IRON SUPPLY" until it is done.
-- 4.2, touch: the buttons on the right are placed by client/TouchLayout.luau (FIRE, PUNCH / STRIKE, DRAW / HOLSTER and
-- client/TouchControls.luau's SPRINT and EXIT / PUT DOWN, which share the hand button's place); a tap on the weapon
-- line opens the weapon wheel (Hud.onWeaponWheel); the hints drop the (E) / (G) keys a touch screen has no keys for.
-- A gamepad: Y opens MENU with the selection on its first entry (A takes it).
-- 5.0: Last Stop Supplies has two tabs, ITEMS and KIT (personal gear, client/KitShop.luau); with no vehicle yet the
-- hint says "On foot · J for the board · Supplies for a backpack"; the PHONE action over the weapon line belongs to
-- client/Phone.luau (it reads this HUD's RightStack / WeaponBar to sit there).

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
-- 3.8: the contract palette and its small pieces (client/HudContract.luau: ink, ink2, line, danger, good, warn,
-- accent, surface, raised; P.text, P.caps, P.scrim, P.rule, P.bar, P.keyBox, P.action, P.button, P.row, P.tag ...).
-- One local for both: Hud.luau sits at the 200-register limit.
local P = require(script.Parent.HudContract)
local Hud = {}

local player = Players.LocalPlayer
local state: any = nil
local job: any = nil

local gui = Ui.make("ScreenGui", {
	Name = "ZombieDeliveryHud",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- clear of a phone's notch, rounded corners and Roblox's top bar
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

-- Lower left on a computer (the chat is top left), top left on a touch screen (the thumbstick is bottom left): the
-- cash and the rank, the minimap, the health row. `view` holds the refs of the pieces that change often (the health
-- row, the vehicle, the contract group, the menu, the inventory): one table instead of a local each (Hud.luau sits at
-- the 200-register limit).
local touchLayout: any, LEFT_H: any, LEFT_W: any, leftStack: any, moneyLabel: any, levelChip: any, rankLabel: any, xpLabel: any, view: any, xpFill: any
do -- (its own block: the locals below stay out of the 200-register limit)
touchLayout = Ui.touchLayout()
view = {}
-- The cash line, the minimap and the health row share one column (one scale), so they can never overlap.
local MONEY_HEIGHT, HEALTH_HEIGHT = 30, 18
LEFT_W = MapView.MiniSize.X
LEFT_H = MONEY_HEIGHT + 6 + MapView.MiniSize.Y + 6 + HEALTH_HEIGHT
leftStack = placed(Ui.make("Frame", {
	Name = "LeftStack",
	Size = UDim2.fromOffset(LEFT_W, LEFT_H),
	Position = if touchLayout then UDim2.fromOffset(16, 16) else UDim2.new(0, 16, 1, -16),
	AnchorPoint = if touchLayout then Vector2.zero else Vector2.new(0, 1),
	BackgroundTransparency = 1,
}, gui))
Ui.list(leftStack, true, 6)
-- 3.8: "$12,480 / LV 7 ROAD RAT" in compact white type, a hairline of the XP under it; the XP numbers only on hover
-- (or a tap on a touch screen), quietly to the right of the line (3.1.4+).
local moneyHolder = Ui.make("Frame", { Name = "Cash", Size = UDim2.fromOffset(LEFT_W, MONEY_HEIGHT), BackgroundTransparency = 1, LayoutOrder = 1 }, leftStack)
P.scrim(moneyHolder, 0.5, { Size = UDim2.new(1, 24, 1, 0), Position = UDim2.fromOffset(-8, 0) })
local line = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, moneyHolder)
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, line)
moneyLabel = P.text(line, "$0", UDim2.fromOffset(0, 22), { AutomaticSize = Enum.AutomaticSize.X, Font = Theme.HeadingFont, TextSize = 16, LayoutOrder = 1 })
P.text(line, "/", UDim2.fromOffset(0, 22), { AutomaticSize = Enum.AutomaticSize.X, TextSize = 14, TextColor3 = P.ink2, LayoutOrder = 2 })
levelChip = P.caps(line, "LV 1", UDim2.fromOffset(0, 22), { AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, TextColor3 = P.ink, LayoutOrder = 3 })
rankLabel = P.caps(line, "", UDim2.fromOffset(0, 22), { AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, LayoutOrder = 4 })
local xpBack
xpBack, xpFill = P.bar(moneyHolder, UDim2.new(1, 0, 0, 2), P.ink2)
xpBack.Position = UDim2.fromOffset(0, 25)
xpLabel = P.caps(moneyHolder, "", UDim2.fromOffset(0, 22), {
	AutomaticSize = Enum.AutomaticSize.X,
	Position = UDim2.new(1, 12, 0, 0), -- to the right of the line
	TextSize = 12,
	Visible = false,
	ZIndex = 5,
})
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
-- Your health under the minimap: a plus, a thin bar and the number.
local health = Ui.make("Frame", { Name = "Health", Size = UDim2.fromOffset(LEFT_W, HEALTH_HEIGHT), BackgroundTransparency = 1, LayoutOrder = 3 }, leftStack)
P.text(health, "+", UDim2.fromOffset(14, HEALTH_HEIGHT), { Font = Theme.HeadingFont, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center })
local healthBack
healthBack, view.healthFill = P.bar(health, UDim2.new(1, -66, 0, 2), P.ink)
healthBack.Position = UDim2.new(0, 22, 0.5, 0)
healthBack.AnchorPoint = Vector2.new(0, 0.5)
view.healthText = P.text(health, "100", UDim2.fromOffset(38, HEALTH_HEIGHT), {
	Position = UDim2.new(1, 0, 0, 0),
	AnchorPoint = Vector2.new(1, 0),
	Font = Theme.MonoFont,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Right,
})
view.health = -1 -- the health shown (the row redraws only when it changes)
end

-- ── Top stack ──────────────────────────────────────────────────────────────
-- 3.8: the contract column, upper left (at the left margin under the top bar on a computer, under the native chat
-- while it is open; right of the minimap column on a touch screen), one column that grows downward (a UIListLayout:
-- a hidden entry takes no room, so nothing overlaps):
--   1 the contract group (your own job; with none and nothing else on top, the small OFF DUTY line)
--   2 the tutorial's hint (client/TutorialUi.luau sets its slot's order 2), the crew slot (a member's view of the
--     leader's job, an invitation: client/CrewPanel.luau, through Hud.topSlot)
--   3 the mission banner (3.0: client/MissionsUi.luau)
--   4 the car call line ("Your car is on the way · 9 s") or the repair timer (client/GarageUi.luau)
--   5 the level-up banner
--   6 the toasts (the newest last, MAX_TOASTS at most)
-- The contract group, the crew strip and the invitation card never show at the same time (a job of your own, a crew
-- member without one, neither); the rest stacks under whichever shows. Everything is left-aligned.

local TOP_W: any, topStack: any
do -- (its own block: the locals below stay out of the 200-register limit)
TOP_W = 380 -- the column's width at scale 1
topStack = placed(Ui.make("Frame", {
	Name = "TopStack",
	Size = UDim2.fromOffset(TOP_W, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.fromOffset(16, 14),
	BackgroundTransparency = 1,
}, gui))
Ui.list(topStack, true, 8)
-- (a toast or a banner under the contract makes the column taller: lay out again for its real height)
topStack:GetPropertyChangedSignal("AbsoluteSize"):Connect(requestLayout)

local SLOT_ORDER: { [string]: number } = { job = 1, crew = 2, roadevent = 2, mission = 3, carcall = 4, repair = 4, levelup = 5, toasts = 6 } -- (4.8: roadevent, client/RoadEventUi.luau)
local slots: { [string]: Frame } = {}

-- A place in the contract column for another module's panel, by name ("crew"; an unknown name goes under the toasts).
-- The slot is as wide as the column and as tall as what is visible in it (its children top down by LayoutOrder,
-- left-aligned). It is scaled with the column: the panels in it take no UIScale of their own.
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
	Ui.list(slot, true, 8)
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

-- 3.8: a toast is a compact charcoal strip (a thin white rule on its left, white text) that fades in and, after 3 s,
-- out again. No movement.
function Hud.toast(text: string)
	-- Too many: the oldest goes (they never pile up down the screen).
	local shown: { any } = {}
	for _, child in toasts:GetChildren() do
		if child:GetAttribute("Toast") == true and child:GetAttribute("Leaving") ~= true then
			if child:GetAttribute("Text") == text then
				return -- 4.5.1: these words are on screen already (a repeated notice): no second strip fading in
			end
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
	local strip = Ui.make("CanvasGroup", {
		Name = "Toast",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		LayoutOrder = toastOrder,
	}, toasts)
	strip:SetAttribute("Toast", true)
	strip:SetAttribute("Text", text)
	-- (the padding moves the children: the rule goes back out to the edge)
	Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 2, 1, 14), Position = UDim2.fromOffset(-14, -7), BackgroundColor3 = P.ink, BorderSizePixel = 0 }, strip)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }, strip)
	local label = Ui.label(strip, text, UDim2.fromOffset(0, 0), {
		AutomaticSize = Enum.AutomaticSize.XY,
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = P.ink,
		TextWrapped = true,
	})
	-- 340: with the padding it stays inside the narrowest contract column.
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(340, math.huge) }, label)
	P.fade(strip, true, 0.18)
	task.delay(3, function()
		if not strip.Parent then
			return
		end
		strip:SetAttribute("Leaving", true)
		P.fade(strip, false, 0.3)
		task.wait(0.35)
		strip:Destroy()
	end)
end
end

-- ── Windows ────────────────────────────────────────────────────────────────

local windows: { any } = {}

-- Does the interface need the mouse right now (a window or the big map is open)?
function Hud.anyWindowOpen(): boolean
	if MapView.isOpen() or (view and view.menu and view.menu.Visible) then
		return true -- (the MENU list frees the mouse like a window: CAR and GIVE UP have no key)
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
		view.menu.Visible = false -- (the MENU list)
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

-- The window (Ui.window: its chrome, the header with the title and the subtitle, the close button, the footer with
-- ESC and the context on the right, window.footer) with a scrolling body of slim rows.
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
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = P.line,
		ScrollBarImageTransparency = 0.3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, content)
	Ui.list(body, true, 6)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 4) }, body)
	table.insert(windows, frame)
	return { frame = frame, body = body, title = chrome.title, subtitle = chrome.subtitle, icon = chrome.icon, footer = chrome.context }
end

-- 3.8: a list row is a slim charcoal row (P.row); the one that matters here (`highlight`) raised with a narrow red rule
-- on its left. (`plain` is kept for the callers: every row is plain now.) Its children are placed like the old card's.
local function card(parent: any, height: number, order: number, highlight: boolean?, plain: boolean?): any
	local _ = plain
	return P.row(parent, height, order, highlight)
end

-- name / stats / description on the left of a card.
local function cardText(c: any, name: string, stats: string, description: string, left: number?)
	local x = left or 16
	Ui.label(c, name, UDim2.new(1, -190 - x, 0, 24), { Position = UDim2.fromOffset(x, 7), TextSize = 17, Font = Theme.HeadingFont, TextColor3 = P.ink, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.label(c, stats, UDim2.new(1, -190 - x, 0, 20), { Position = UDim2.fromOffset(x, 33), TextColor3 = P.ink, TextTransparency = 0.15, TextSize = 13, Font = Theme.Font, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.label(c, description, UDim2.new(1, -190 - x, 0, 20), { Position = UDim2.fromOffset(x, 55), TextColor3 = P.ink2, TextSize = 13, Font = Theme.Font })
end

-- The button of a card, in the column on its right: the main action a light face (a secondary one, `color` C.blue or
-- C.grey, an outline), what you cannot press a dim one with the reason in it.
local function cardButton(parent: any, text: string, color: Color3, enabled: boolean, onClick: () -> (), slot: number?): any
	local function press()
		if enabled then
			onClick()
		end
	end
	local kind: P.ButtonKind = if not enabled then "off" elseif color == C.blue or color == C.grey then "quiet" else "main"
	local button = P.button(parent, text, UDim2.fromOffset(150, 40), kind, press)
	button.TextSize = 14
	local n = slot or 0
	button.Position = UDim2.new(1, -162, 0, if n == 0 then 21 else 2 + (n - 1) * 44)
	return button
end

-- The tabs of a window: the open one a light face, the others outlined.
local function tabs(parent: any, list: { { string } }, selected: string, onPick: (string) -> ())
	local row = Ui.make("Frame", { Size = UDim2.new(1, -12, 0, 40), BackgroundTransparency = 1, LayoutOrder = 0 }, parent)
	Ui.list(row, false, 6)
	for _, entry in list do
		local on = entry[1] == selected
		local button = P.button(row, entry[2], UDim2.fromOffset(132, 36), if on then "main" else "quiet", function()
			onPick(entry[1])
		end)
		button.TextSize = 13
	end
end

-- A line of text in a window (C.red: a warning, in the contract red).
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
Hud.onJobsKey = nil :: (() -> ())? -- 4.0.2: the J key: opens the board, or closes it when it is open (Main)
Hud.onCrew = nil :: (() -> ())?
Hud.oldLevelBanner = false -- 4.6: off: client/CareerUi.luau shows the level-up card (true brings the old banner back)
Hud.onEstate = nil :: (() -> ())?
Hud.onSound = nil :: (() -> ())? -- client/Sounds.luau: music and effects on / music off / all off
Hud.onMissions = nil :: (() -> ())? -- client/MissionsUi.luau: the MISSIONS window
Hud.onCareer = nil :: (() -> ())? -- 4.6 client/CareerUi.luau: the CAREER window (C)
Hud.onWeaponWheel = nil :: (() -> ())? -- 4.2, touch: a tap on the weapon line opens the weapon wheel (WeaponWheel.openTouch)

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
		local pallets = Economy.palletsOf(def.id, Economy.stageOf(def.id, levels)) -- 4.0
		return `{prefix}Speed {math.floor(stats.maxSpeed + 0.5)} · Health {stats.health} · 📦 {Economy.capacity(def.id, levels)} slots{if pallets > 0 then ` · {pallets} pallet{if pallets > 1 then "s" else ""}` else ""}`
	end
	local most = Economy.maxCapacity(def.id)
	local pallets = Economy.palletsOf(def.id, Economy.maxStage(def.id)) -- 4.0: what it takes at its last stage
	return `Speed {def.maxSpeed} · Health {def.health} · Ram x{def.ramPower} · 📦 {if most > def.capacity then `{def.capacity} → {most}` else def.capacity} slots{if pallets > 0 then ` · {pallets} pallet{if pallets > 1 then "s" else ""}` else ""}`
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
		elseif exclusive == "career" then
			return "REWARD", "a career level (CAREER, C)" -- 4.6: Config.Levels.Rewards
		end
		for _, campaign in require(Shared.Missions).Campaigns do
			if campaign.id == exclusive then
				return "REWARD", `finish {campaign.name}`
			end
		end
		return "REWARD", "a reward"
	end
		local function badge(c: any, text: string, color: Color3, y: number)
		-- 3.8: a small outlined tag over the button: an exclusive (Ui.Gps) in white, a reward in the warm good.
		local chip = P.tag(c, text, if color == Ui.Gps then P.ink else P.warn)
		chip.Position = UDim2.new(1, -162, 0, y)
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
		button.TextSize = 12
		button.TextWrapped = true
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
		bikes = { "🚲", "Bikes and bike gear" }, -- 5.1
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
			if yes and def and not def.company and not def.bike then -- (5.1: a bike needs no garage slot)
				owned += 1
			end
		end
		local full = owned >= (tonumber(player:GetAttribute("CarSlots")) or Config.Estate.BaseCarSlots)
		-- 3.5: not "the next van": every car has a role, and its own stages at Wrench Garage (📦 from → to).
		note(shop.body, "The catalog. Every car has a role and builds up in stages at Wrench Garage (📦 slots from → to; more room makes the body longer). A van ends at 4 slots: more needs the High-Roof Van, the Box Truck or the Freight Truck (pallets).", C.dim, 1)
		for order, def in Config.Cars do
			if def.company or def.bike then
				continue -- (5.1: the bikes are Spoke & Chain's)
			end
			local c = card(shop.body, 100, order + 1, def.id == shopFocus)
			local lock = if state.cars[def.id] then nil else lockedAt(def.level)
			local need = needs(def, state.cars[def.id] == true)
			-- 5.0: the Old Van is sold privately (Config.VanQuest: Earl, Marge's quest), not here.
			local private = def.id == Config.VanQuest.Car and not state.cars[def.id]
			cardText(c, def.name, carStats(def) .. (if private then ` · {Config.VanQuest.DealerNote}` elseif lock then ` · from level {lock}` else "") .. (if need then ` · {need}` else ""), def.description)
			if def.role then
				Ui.label(c, `ROLE · {string.upper(def.role)}`, UDim2.new(1, -206, 0, 16), { Position = UDim2.fromOffset(16, 78), TextColor3 = P.ink2, TextSize = 11, Font = Theme.HeadingFont })
			end
			if state.car == def.id then
				cardButton(c, "YOUR CAR", C.grey, false, function() end)
			elseif state.cars[def.id] then
				-- 3.4: your cars wait in your garages; you switch them only there.
				cardButton(c, "IN GARAGE", C.grey, true, function()
					Hud.toast("Switch cars at one of your garages (🅿 GARAGE), or at the depot lot for your starting van.")
				end)
			elseif private then
				local sold = cardButton(c, "🔒 SOLD PRIVATELY", C.grey, true, function()
					Hud.toast(`{Config.VanQuest.DealerNote} {Config.VanQuest.Seller} sells it at {Config.VanQuest.Place}, far out west.`)
				end)
				sold.TextSize = 12
				sold.TextColor3 = P.ink2
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
	elseif shopId == "bikes" then
		-- 5.1: Spoke & Chain: BIKES and GEAR (client/BikeShop.luau; it keeps the open tab).
		tabs(shop.body, { { "bikes", "BIKES" }, { "gear", "GEAR" } }, require(script.Parent.BikeShop).tab, function(id)
			require(script.Parent.BikeShop).tab = id
			renderShop()
		end)
		require(script.Parent.BikeShop).render(shop.body, state, here, shopFocus)
	elseif shopId == "supplies" then
		-- 5.0: two tabs: ITEMS (the consumables) and KIT (personal gear, client/KitShop.luau; it keeps the open tab).
		tabs(shop.body, { { "items", "ITEMS" }, { "kit", "KIT" } }, require(script.Parent.KitShop).currentTab(state), function(id)
			require(script.Parent.KitShop).tab = id
			renderShop()
		end)
		if require(script.Parent.KitShop).currentTab(state) == "kit" then
			require(script.Parent.KitShop).render(shop.body, state, here)
			return
		end
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
		tabs(shop.body, { { "upgrades", "UPGRADES" }, { "gear", "GEAR" }, { "paint", "PAINT" }, { "carguns", "CAR GUNS" } }, mechanicTab, function(id)
			mechanicTab = id
			renderShop()
		end)
		if mechanicTab == "upgrades" then
			-- 3.3: the car tracks belong to the equipped car (its own levels, shown on it); the gun tracks to every gun.
			local upCar = Economy.findCar(state.car)
			local carOk = upCar ~= nil and Economy.canUpgrade(upCar.id)
			local carLevels = Economy.carLevels(state.carUpgrades, state.car)
			if carOk then
				note(shop.body, `Upgrades for: {Economy.carTitle(state.car, carLevels)} (📦 {Economy.capacity(state.car, carLevels)} cargo slots). They stay on this car and show on it (new tyres and rims, a bull bar, plates, a scoop); a STAGE rebuilds the car itself, the trolley and the other gear are in GEAR. Repairs: drive into a repair bay here, get out and wait.`, C.dim, 1)
			else
				-- 5.0: on foot, no vehicle yet
				note(shop.body, if upCar then `Your {upCar.name} is a company vehicle: it can't be upgraded. Take one of your own cars out of your garage.` else `You don't have a vehicle yet: the Old Van comes from {Config.VanQuest.Where}.`, C.red, 1)
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
					elseif def.car and not Economy.upgradeFits(state.car, def.id) then
						cardButton(c, "VANS & TRUCKS", C.grey, false, function() end) -- 4.0: the Hand Trolley
					elseif cost then
						cardButton(c, `UPGRADE {Ui.money(cost)}`, C.green, here and money >= cost, function()
							Net.get("Upgrade"):FireServer(def.id)
						end)
					else
						cardButton(c, "MAX", C.grey, false, function() end)
					end
				end
			end
		elseif mechanicTab == "gear" then
			require(script.Parent.GearShop).render(shop.body, state, here) -- 4.6: the car's gear and its slots
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
				Ui.stroke(swatch, if def.material == "Neon" then swatchColor:Lerp(P.ink, 0.5) else P.line, 1)
				Ui.label(c, def.name, UDim2.new(1, -260, 0, 24), { Position = UDim2.fromOffset(70, 9), TextSize = 17, Font = Theme.HeadingFont, TextColor3 = P.ink })
				-- The finish (PaintDef.material) after the price: "Owned · Neon finish".
				local finish = if def.material then ` · {def.material} finish` else ""
				Ui.label(c, (if state.paints[def.id] then "Owned" elseif def.exclusive then "Never sold" else Ui.money(def.price)) .. finish, UDim2.new(1, -260, 0, 20), { Position = UDim2.fromOffset(70, 36), TextColor3 = P.ink2, TextSize = 13, Font = Theme.Font })
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
	Ui.label(row, name, UDim2.new(1, -200, 0, 24), { Position = UDim2.fromOffset(64, 8), TextSize = 17, Font = Theme.HeadingFont, TextColor3 = P.ink })
	Ui.label(row, if owned then "YOURS" else `{math.min(done, at)}/{at} jobs`, UDim2.fromOffset(120, 24), {
		Position = UDim2.new(1, -132, 0, 8),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = if owned then P.good else P.ink2,
		TextSize = 15,
		Font = Theme.MonoFont,
	})
	local back, fill = P.bar(row, UDim2.new(1, -78, 0, 3), if owned then P.good else P.accent)
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
	Ui.label(body, string.upper(employer.person), UDim2.new(1, -10, 0, 20), { LayoutOrder = 1, TextColor3 = P.ink2, TextSize = 12, Font = Theme.HeadingFont })
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
		iconText(about, info.art, info.icon, "", `  {jobType.name}`, UDim2.new(1, -190, 0, 24), { Position = UDim2.fromOffset(12, 8), TextSize = 17, Font = Theme.HeadingFont, TextColor3 = P.ink })
		local needs = if jobType.level and jobType.level > 1 then `LV {jobType.level}+ · ` else ""
		Ui.label(about, `{needs}Danger {string.rep("★", jobType.tier)}`, UDim2.fromOffset(170, 24), {
			Position = UDim2.new(1, -182, 0, 8),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = if jobType.tier >= 3 then P.danger else P.ink2,
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
		Ui.label(body, "Finish your current delivery first (or give it up: MENU).", UDim2.new(1, -10, 0, 24), { LayoutOrder = 7, TextColor3 = P.danger, TextSize = 16 })
	elseif lock then
		local button = P.button(body, `🔒 LEVEL {lock}`, UDim2.fromOffset(240, 46), "off", function() end)
		button.LayoutOrder = 7
		Ui.label(body, `{employer.person} hires drivers from level {lock} ({Levels.rank(lock)}) on. You are level {myLevel()}: deliveries give XP.`, UDim2.new(1, -10, 0, 0), {
			LayoutOrder = 8,
			AutomaticSize = Enum.AutomaticSize.Y,
			TextColor3 = P.ink2,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
		})
	else
		local take = P.button(body, "TAKE THE JOB", UDim2.fromOffset(240, 46), "main", function()
			Net.get("AcceptEmployer"):FireServer(employer.id)
			employerWindow.frame.Visible = false
		end)
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
	if id == "supplies" and (focus == "kit" or focus == "items") then
		require(script.Parent.KitShop).tab = focus -- 5.0: the phone's SHOP app and the server may open a tab
	elseif id == "bikes" then
		require(script.Parent.BikeShop).tab = if focus == "gear" then "gear" else "bikes" -- 5.1 (a display bike: BIKES)
	end
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
	Ui.caps(c, "On this job", UDim2.new(1, -24, 0, 18), { Position = UDim2.fromOffset(16, 8), TextColor3 = P.ink2, TextSize = 12 })
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
					local chip = P.tag(c, "★ EXCLUSIVE", P.ink)
					chip.Position = UDim2.new(1, -162, 0, 2)
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
-- 4.4.1: Space (Enter, the gamepad's A) closes it like OK while it shows (client/DialogKeys.luau).
require(script.Parent.DialogKeys).watch("result", result.frame, function()
	result.frame.Visible = false
end)

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
	if type(r) == "table" and r.midJob == true then
		-- 5.2: one order of a run done while the others go on: a toast, not this window (a lost one: the server's
		-- notice says it already).
		if r.success then
			local got = if type(r.rating) == "table" then math.clamp(math.floor(tonumber(r.rating.stars) or 0), 0, 3) else 0
			local left = if type(r.order) == "table" then tonumber(r.order.left) or 0 else 0
			Hud.toast(`ORDER DONE{if got > 0 then ` {string.rep("★", got)}{string.rep("☆", 3 - got)}` else ""} · +{Ui.money(tonumber(r.total) or 0)} · {r.cargo or "cargo"} for {r.customer or "the customer"}{if left > 0 then ` · {left} to go` else ""}`)
			-- 5.2 review: what the window would say of an employer (the jobs done, the next reward) and a new car or gun.
			local employer = if type(r.employer) == "table" then r.employer else nil
			if employer then
				local done = tonumber(employer.done) or 0
				local gunAt = tonumber(employer.weaponAt)
				local nextUp = if employer.weapon and gunAt and done < gunAt then ` · {gunAt - done} more for the {employer.weapon}`
					elseif type(employer.needed) == "number" and done < employer.needed and employer.reward ~= "" then ` · {employer.needed - done} more for the {employer.reward}`
					else ""
				Hud.toast(`{employer.name}: {done} jobs done{nextUp}`)
			end
			local newCar = r.unlockedCar or (employer and employer.unlocked)
			if type(newCar) == "string" then
				Hud.toast(`🚚 NEW CAR: the {newCar} is yours!`)
			end
			if type(r.unlockedWeapon) == "string" then
				local gun = Economy.findWeapon(r.unlockedWeapon)
				Hud.toast(`🔫 NEW GUN: the {if gun then gun.name else r.unlockedWeapon} is yours!`)
			end
		end
		return
	end
	closeWindows()
	Ui.clear(result.body)
	result.frame.Visible = true
	-- 3.6: the header says how it went, the footer where NEXT JOB goes.
	result.title.Text = if r.success then "Delivered" else "Delivery failed"
	result.icon.Text = if r.success then "📦" else "⚠"
	result.subtitle.Text = if r.cargo then `{r.cargo}{if r.customer then ` for {r.customer}` else ""}` else ""
	result.footer.Text = "Next job · the Dispatch board"
	-- 3.8: a short accent rule over the headline: the good green, or the red when it failed.
	P.rule(result.body, UDim2.fromOffset(48, 2), { LayoutOrder = 0, BackgroundColor3 = if r.success then P.good else P.danger, BackgroundTransparency = 0 })
	local function line(text: string, value: string?, color: Color3?, order: number): any
		-- 3.2: the headline (order 1) and the TOTAL bigger, the other lines calmer. 3.8: light text on the charcoal
		-- (green: good news, red: bad, white: the money and the XP, dim: the details).
		local big = order == 1 or text == "TOTAL"
		local ink = if color == C.green then P.good elseif color == C.red then P.danger elseif color == C.yellow then P.ink elseif color == C.dim then P.ink2 else P.ink
		local row = Ui.make("Frame", { Size = UDim2.new(1, -12, 0, if order == 1 then 36 else 26), BackgroundTransparency = 1, LayoutOrder = order }, result.body)
		Ui.label(row, text, UDim2.new(1, if value then -120 else 0, 1, 0), {
			TextColor3 = ink,
			TextSize = if order == 1 then 24 elseif big then 18 else 15,
			Font = if big then Theme.HeadingFont else Theme.Font,
		})
		if value then
			Ui.label(row, value, UDim2.new(0, 120, 1, 0), {
				Position = UDim2.new(1, -120, 0, 0),
				TextColor3 = ink,
				TextSize = if big then 18 else 15,
				Font = Theme.MonoFont,
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
		if type(r.rating) == "table" and tonumber(r.rating.stars) then
			-- 4.7: the owner's rating of the job.
			local got = math.clamp(math.floor(tonumber(r.rating.stars) or 1), 1, 3)
			line(`Job rated {string.rep("★", got)}{string.rep("☆", 3 - got)}`, nil, C.dim, 4)
		end
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
		-- 4.7: the rating (★ … ★★★, why), the streak of good jobs and the licence it counts toward (not a mission).
		local rating = if type(r.rating) == "table" then r.rating else nil
		if rating and tonumber(rating.freshness) then
			-- 4.8: food: its freshness took this off the pay.
			line(`Freshness {math.floor((tonumber(rating.freshness) or 1) * 100 + 0.5)}%`, if (tonumber(rating.freshPay) or 0) < 0 then "-" .. Ui.money(-(tonumber(rating.freshPay) or 0)) else nil, if (tonumber(rating.freshness) or 1) < 0.7 then C.red else nil, 9)
		end
		if rating then
			local got = math.clamp(math.floor(tonumber(rating.stars) or 2), 1, 3)
			local ratingPay = tonumber(rating.ratingPay) or 0
			local percentText = if got == 3 then " (+20% pay)" elseif got == 1 then " (−10% pay)" else ""
			line(`RATED {string.rep("★", got)}{string.rep("☆", 3 - got)}{percentText}`, if ratingPay > 0 then "+" .. Ui.money(ratingPay) elseif ratingPay < 0 then "-" .. Ui.money(-ratingPay) else nil, if got == 3 then C.green elseif got == 1 then C.red else C.yellow, 10)
			local why: { string } = {}
			if type(rating.checks) == "table" then
				for _, check in rating.checks do
					if type(check) == "table" and type(check.text) == "string" then
						table.insert(why, `{if check.ok then "✓" else "✗"} {check.text}`)
					end
				end
			end
			if #why > 0 then
				Ui.label(result.body, table.concat(why, "   "), UDim2.new(1, -10, 0, 0), {
					LayoutOrder = 11,
					AutomaticSize = Enum.AutomaticSize.Y,
					TextColor3 = P.ink2,
					TextSize = 13,
					Font = Theme.Font,
				})
			end
			local streak = tonumber(rating.streak) or 0
			local streakPay = tonumber(rating.streakPay) or 0
			if got >= 2 and streak > 0 then
				local bonus = math.floor((tonumber(rating.streakBonus) or 0) * 100 + 0.5)
				line(`Streak: {streak} good {if streak == 1 then "job" else "jobs"} in a row (+{bonus}%)`, if streakPay > 0 then "+" .. Ui.money(streakPay) else nil, C.green, 12)
			else
				line("Streak ended: a ★ job (★★ or better keeps it)", nil, C.red, 12)
			end
			local licence = if type(rating.licence) == "table" then rating.licence else nil
			if licence and licence.earned == true then
				line(`🪪 {licence.stars} LICENCE EARNED: {licence.stars} jobs are on your board!`, nil, C.green, 13)
			elseif licence then
				line(`🪪 {licence.stars} licence: {licence.have} / {licence.need} jobs rated ★★+ at {licence.atStars}{if myLevel() < (tonumber(licence.level) or 0) then ` · level {licence.level}` else ""}`, nil, C.dim, 13)
			end
		end
		local crewBonus = tonumber(r.crewBonus) or 0
		if riders > 0 and crewBonus > 0 then
			line(`Crew bonus ({riders} in the crew)`, "+" .. Ui.money(crewBonus), nil, 14)
		elseif riders > 0 and crewBonus < 0 then
			line(`Shared with the crew ({riders})`, "-" .. Ui.money(-crewBonus), C.dim, 14)
		end
		line("TOTAL", Ui.money(r.total), C.yellow, 20)
		local employer = r.employer
		if employer then
			line(`{employer.name}: {employer.done} jobs done`, nil, C.yellow, 21)
			-- The next reward of that employer (the gun comes first, then the vehicle).
			local done = tonumber(employer.done) or 0
			local gunAt = tonumber(employer.weaponAt)
			local nextUp = if employer.weapon and gunAt and done < gunAt then `{gunAt - done} more for the {employer.weapon}`
				elseif type(employer.needed) == "number" and done < employer.needed and employer.reward ~= "" then `{employer.needed - done} more for the {employer.reward}`
				else nil
			if nextUp then
				line(nextUp, nil, C.dim, 22)
			end
		end
		local newCar = r.unlockedCar or (employer and employer.unlocked)
		if newCar then
			line(`🚚 NEW CAR: the {newCar} is yours!`, nil, C.green, 23)
		end
		if type(r.unlockedWeapon) == "string" then
			local gun = Economy.findWeapon(r.unlockedWeapon)
			line(`🔫 NEW GUN: the {if gun then gun.name else r.unlockedWeapon} is yours!`, nil, C.green, 24)
		end
	else
		line("DELIVERY FAILED", nil, C.red, 1)
		Ui.label(result.body, r.reason or "", UDim2.new(1, -10, 0, 60), { LayoutOrder = 2, TextColor3 = P.ink })
		local lostStreak = tonumber(r.streakLost)
		if lostStreak and lostStreak > 0 then
			-- 4.7: a failed job ends the streak of good jobs.
			line(`Streak of {lostStreak} good {if lostStreak == 1 then "job" else "jobs"} lost`, nil, C.red, 3)
		end
	end
	-- The XP of the job, the level bar and a level-up with what it unlocks.
	local xp = tonumber(r.xp)
	if xp and xp > 0 then
		local level = tonumber(r.level) or myLevel()
		local rank = if type(r.rank) == "string" then r.rank else Levels.rank(level)
		local topRated = type(r.rating) == "table" and tonumber(r.rating.stars) == 3 and not r.rider -- 4.7: ★★★ × 1.25 XP
		line(if topRated then "Driver XP (★★★ ×1.25)" elseif r.success then "Driver XP" else "Driver XP (a failed job still counts)", `+{xp} XP`, C.yellow, 30)
		local row = Ui.make("Frame", { Size = UDim2.new(1, -10, 0, 22), BackgroundTransparency = 1, LayoutOrder = 31 }, result.body)
		Ui.label(row, `LV {level} · {rank}`, UDim2.new(0.5, 0, 1, 0), { TextColor3 = P.ink2, TextSize = 14, Font = Enum.Font.GothamMedium, TextWrapped = false })
		local back, fill = P.bar(row, UDim2.new(0.5, 0, 0, 2), P.accent)
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
				-- You: a quiet charcoal highlight and a narrow red rule.
				row.BackgroundTransparency = 0
				row.BackgroundColor3 = P.raised
				Ui.make("Frame", { Name = "Selected", Size = UDim2.new(0, 2, 1, 0), Position = UDim2.fromOffset(-6, 0), BackgroundColor3 = P.danger, BorderSizePixel = 0 }, row)
			end
		end
	end
	-- One clear action (NEXT JOB) and a quiet OK, side by side.
	local actions = Ui.make("Frame", { Size = UDim2.new(1, -12, 0, 44), BackgroundTransparency = 1, LayoutOrder = 90 }, result.body)
	Ui.list(actions, false, 8)
	local next = P.button(actions, "NEXT JOB  →", UDim2.fromOffset(170, 44), "main", function()
		result.frame.Visible = false
		openDispatch()
	end)
	next.LayoutOrder = 1
	local ok = P.button(actions, "OK", UDim2.fromOffset(110, 44), "quiet", function()
		result.frame.Visible = false
	end)
	ok.LayoutOrder = 2
	-- 4.4.1: the key that does OK too (none on a touch screen).
	Ui.label(actions, require(script.Parent.DialogKeys).hint(), UDim2.fromOffset(0, 44), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.MonoFont,
		TextSize = 11,
		TextColor3 = P.ink2,
		TextWrapped = false,
		LayoutOrder = 3,
	})
end

-- Is the DELIVERY result window open (client/MissionsUi.luau waits with its celebration card until it is closed)?
function Hud.resultOpen(): boolean
	return result ~= nil and result.frame.Visible == true
end
end

-- ── Buttons ────────────────────────────────────────────────────────────────

-- 3.8, the actions (upper right): the quiet text actions MAP [M], CREW [K] and MENU. MENU opens a slim charcoal list of
-- every other action with its key: JOBS (J), MISSIONS (U), CAREER (C, 4.6), BAG (I; 3.9, B before), CAR, TOP (L), ESTATE (H), SOUND (N) and, while a
-- job runs, GIVE UP (twice). Hover brightens an action and draws a thin red line under it; a touch screen drops the
-- keys and keeps 44 px hit areas. Other modules hook in (Hud.onJobs, Hud.onCrew, Hud.onEstate, Hud.onMissions,
-- Hud.onSound). layout() scales and places the row: on a computer left of (or under) Roblox's player list, on touch
-- top right under ADMIN; the list opens downward.

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
	{ id = "career", menu = true, icon = "🎖", text = "CAREER", key = "C", onClick = function() -- 4.6
		hook("career window", Hud.onCareer)
	end },
	{ id = "bag", menu = true, icon = "🎒", text = "BAG", key = "I", onClick = function()
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

-- The row: MAP [M]  CREW [K]  MENU, right-aligned in a frame of a fixed size (layout() reads it).
local ROW_W, ROW_H = if touchLayout then 210 else 250, 44
buttonGrid = placed(Ui.make("Frame", {
	Name = "HudButtons",
	Size = UDim2.fromOffset(ROW_W, ROW_H),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
	BackgroundTransparency = 1,
	ZIndex = 2, -- the open list draws on top and takes the taps
}, gui))
-- (the actions in a row of their own: the list under MENU is not laid out with them)
local actions = Ui.make("Frame", { Name = "Row", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, buttonGrid)
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, if touchLayout then 6 else 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, actions)
hudButtons = {}

-- The list under MENU: a charcoal surface, a thin line, one slim row per action (its key on the right).
-- (a touch screen: two columns of 44 px rows, so the list stays short under the row)
local COLUMNS = if touchLayout then 2 else 1
local ENTRY_W, ENTRY_H = if touchLayout then 150 else 220, if touchLayout then 44 else 34
local menu = Ui.make("Frame", {
	Name = "Menu",
	Size = UDim2.fromOffset(COLUMNS * ENTRY_W + (COLUMNS - 1) * 4 + 12, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 1, 4),
	BackgroundColor3 = P.surface,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 6,
}, buttonGrid)
Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = P.lineAlpha }, menu)
Ui.padding(menu, 6)
if COLUMNS > 1 then
	Ui.make("UIGridLayout", { CellSize = UDim2.fromOffset(ENTRY_W, ENTRY_H), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder }, menu)
else
	Ui.list(menu, true, 2)
end
view.menu = menu
view.badges = {} -- the counts on the menu's entries (MENU shows a dot while any is on)

-- A quiet action of the row ("MAP  [M]"; a touch screen drops the key).
local function utility(def: ButtonDef?, order: number): any
	local text = if def then def.text else "MENU"
	local button = P.action(actions, if def and def.key and not touchLayout then `{text}  [{def.key}]` else text, {
		Name = if def then `{def.id}Button` else "moreButton",
		Size = UDim2.fromOffset(0, ROW_H),
		LayoutOrder = order,
		ZIndex = 3,
	})
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, button)
	Ui.make("UISizeConstraint", { MinSize = Vector2.new(44, 44) }, button)
	return button
end

-- An entry of the list: the name on the left, the key on the right; hover: a raised row, a red rule, white text.
local function entry(def: ButtonDef, order: number): any
	local button = Ui.make("TextButton", {
		Name = `{def.id}Button`,
		Size = UDim2.fromOffset(ENTRY_W, ENTRY_H),
		BackgroundColor3 = P.raised,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = def.text,
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = if def.id == "giveup" then P.danger else P.ink2,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = order,
		ZIndex = 7,
	}, menu)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10) }, button)
	local edge = Ui.make("Frame", { Name = "Edge", Size = UDim2.new(0, 2, 1, 0), Position = UDim2.fromOffset(-12, 0), BackgroundColor3 = P.red, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 8 }, button)
	if def.key and not touchLayout then
		P.caps(button, def.key, UDim2.fromOffset(24, ENTRY_H), {
			Position = UDim2.new(1, 0, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextStrokeTransparency = 1,
			ZIndex = 8,
		})
	end
	P.hover(button, edge)
	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = 0
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = 1
	end)
	button.SelectionGained:Connect(function()
		button.BackgroundTransparency = 0
	end)
	button.SelectionLost:Connect(function()
		button.BackgroundTransparency = 1
	end)
	return button
end

local order = 0
local entries = 0
for _, def in BUTTONS do
	order += 1
	local button: any
	if def.menu then
		entries += 1
		if def.id == "giveup" then
			-- A thin line before GIVE UP (it shows only while a job runs, with its line).
			view.giveUpRule = P.rule(if COLUMNS > 1 then nil :: any else menu, UDim2.fromOffset(ENTRY_W, 1), { LayoutOrder = order, Visible = false })
			order += 1
		end
		button = entry(def, order)
		if def.id == "giveup" then
			button.Visible = false -- only while a job runs (Hud.setJob)
		end
		P.dot(button, { Position = UDim2.new(1, -30, 0.5, 0), ZIndex = 9 })
	else
		button = utility(def, order)
		P.dot(button)
	end
	button.Activated:Connect(function()
		if def.menu then
			local click = Ui.onClick
			if click then
				click()
			end
		end
		if def.menu and def.id ~= "giveup" then
			Ui.gamepadRelease(menu) -- (a gamepad: the window it opens takes the selection, or none)
			menu.Visible = false
		end
		def.onClick()
	end)
	hudButtons[def.id] = button
end
view.menuHeight = math.ceil(entries / COLUMNS) * (ENTRY_H + 4) + 16 -- px at scale 1, GIVE UP shown
-- MENU: opens and closes the list.
local more = utility(nil, order + 1)
P.dot(more)
more.Activated:Connect(function()
	local click = Ui.onClick
	if click then
		click()
	end
	menu.Visible = not menu.Visible
	Ui.gamepadFocus(if menu.Visible then hudButtons.jobs else more) -- 4.2, a gamepad: on to the first entry
end)
hudButtons.more = more

-- MENU wears a dot while any of its entries has a count.
local function menuDot()
	local any = 0
	for _, count in view.badges do
		any += count
	end
	local badge = more:FindFirstChild("Badge")
	if badge and badge:IsA("TextLabel") then
		badge.Visible = any > 0
		badge.Text = ""
	end
end

-- A small red dot with a count on an action or a menu entry ("crew": the invitations waiting); 0 hides it.
function Hud.setBadge(id: string, count: number)
	local button = hudButtons[id]
	local badge = button and button:FindFirstChild("Badge")
	if badge and badge:IsA("TextLabel") then
		badge.Visible = count > 0
		badge.Text = if count > 9 then "9+" elseif count > 1 then tostring(count) else ""
		badge.Size = UDim2.fromOffset(if count > 9 then 20 else 14, 14)
	end
	local def: ButtonDef? = nil
	for _, d in BUTTONS do
		if d.id == id then
			def = d
		end
	end
	if def and def.menu then
		view.badges[id] = math.max(0, count)
		menuDot()
	end
end

-- An action lights up in `color` for `seconds` (an invitation just came: CREW): its text white and its line in that
-- colour. An entry inside the closed list lights MENU instead.
function Hud.flashButton(id: string, color: Color3?, seconds: number?)
	local button = hudButtons[id]
	if not button then
		return
	end
	if not menu.Visible and button.Parent == menu then
		button = more
	end
	local line = button:FindFirstChild("Underline") or button:FindFirstChild("Edge")
	if not (line and line:IsA("Frame")) then
		return
	end
	line.BackgroundColor3 = color or P.red
	line.BackgroundTransparency = 0
	button.TextColor3 = P.ink
	task.delay(seconds or 1.5, function()
		line.BackgroundColor3 = P.red
		line.BackgroundTransparency = 1
		local rest = button:GetAttribute("RestColor")
		if typeof(rest) == "Color3" then
			button.TextColor3 = rest
		end
	end)
end
end

-- ── Hotbar ─────────────────────────────────────────────────────────────────

-- 3.8, the lower right column (one frame, view.right; layout() scales and places it), bottom up: INVENTORY [I] with
-- the consumables (keys 1-5 and their counts; hidden while you carry), the vehicle line (── Car panel ──), a thin
-- rule, and the weapon (a small icon, the gun's name and state, Q) or, while you carry, the cargo in your hands and
-- what carrying stops ("2 × PIZZA BOXES / HANDS FULL · NO GUN, NO SPRINT"). Hidden pieces take no room.
local HOTBAR_H: any, hotbar: any, weaponBar: any, weaponBarKey: any, shownWeaponBar: any, renderWeapons: any, nextWeapon: any, hotbarCounts: any, FIRE_SIZE: any, fire: any
do -- (its own block: the locals below stay out of the 200-register limit)
local RIGHT_W = 300
HOTBAR_H = if touchLayout then 76 else 54
local right = placed(Ui.make("Frame", {
	Name = "RightStack",
	Size = UDim2.fromOffset(RIGHT_W, 190),
	Position = UDim2.new(1, -16, 1, -16),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundTransparency = 1,
}, gui))
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, right)
-- (no backing: the column's text wears the faint charcoal stroke of P.text, the world stays open)
view.right = right
weaponBar = Ui.make("Frame", {
	Name = "WeaponBar",
	Size = UDim2.fromOffset(RIGHT_W, 40),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
}, right)
view.rightRule = P.rule(right, UDim2.fromOffset(RIGHT_W - 70, 1), { LayoutOrder = 2 })
local weaponRow = Ui.make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, weaponBar)
local Holster = require(script.Parent.Holster) -- 3.9: the gun away (B) and the melee (V)
local touchHands: any = {} -- 3.9: the touch buttons over FIRE (melee, holster), made with FIRE below

-- What the weapon line shows depends on where you are: on foot your gun; driving a car with a car gun that gun; in any
-- other seat your gun, WINDOW READY when it is one-handed, ON FOOT ONLY when it is not (it does not fire there);
-- with cargo in your hands the cargo and what carrying stops; while the cargo loads, HOLSTERED and dimmed.
-- 3.9, on foot: the gun holstered (B) shows HANDS and [B] DRAW · [V] PUNCH, the gun out [B] HOLSTER · [V] STRIKE.
local function seatView(): (boolean, Config.CarGunDef?)
	local seatedIn, driving = Drive.seatedCar()
	return seatedIn ~= nil, if seatedIn and driving then Shooting.carGunOf(seatedIn) else nil
end

local function loading(): boolean
	return myCarrying() ~= nil or (job ~= nil and (tonumber(job.progress) or 0) > 0)
end

-- How many pieces are in your hands (the character's CarryCount, 3.7; one when it is not set).
local function carryCount(): number
	local character = player.Character
	local count = character and tonumber(character:GetAttribute("CarryCount"))
	return if count and count > 0 then math.floor(count) else 1
end

-- (everything renderWeapons reads that can change: the gun in your hand is the only part of the State it shows)
function weaponBarKey(): string
	local seated, carGun = seatView()
	local holding = myCarrying()
	local gun = if state then tostring(state.weapon) else "-"
	return `{seated}|{if carGun then carGun.id else ""}|{loading()}|{holding or ""}|{if holding then carryCount() else 0}|{Holster.holstered()}|{gun}`
end
shownWeaponBar = ""

-- A right-aligned row of parts (the weapon line): one horizontal list, its children in LayoutOrder.
local function lineRow(parent: any, height: number, gap: number?): any
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1 }, parent)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	return row
end

-- The weapon line: the gun's small icon, its name and its state in small caps, Q in a key box (hold it: the weapon
-- wheel, client/WeaponWheel.luau). A click or a tap on it takes the next gun. While you carry: the cargo instead.
function renderWeapons()
	Ui.clear(weaponRow)
	shownWeaponBar = weaponBarKey()
	local holding = myCarrying()
	-- 3.9: the touch buttons over FIRE: on foot with free hands, PUNCH / STRIKE and DRAW / HOLSTER as it is now.
	local seatedNow = seatView()
	local away = Holster.holstered()
	if touchHands.melee then
		touchHands.melee.Visible = not seatedNow and not holding
		touchHands.melee.Text = if away then "PUNCH" else "STRIKE"
		touchHands.holster.Visible = not seatedNow and not holding
		touchHands.holster.Text = if away then "DRAW" else "HOLSTER"
	end
	if not state then
		return
	end
	if holding then
		-- 3.8: the cargo in your hands and the restriction, never a usable-looking gun.
		local held = heldInfo(holding)
		local count = carryCount()
		local top = lineRow(weaponRow, 22)
		iconText(top, held.art, held.icon, "", "", UDim2.fromOffset(22, 22), { TextSize = 16, TextColor3 = P.ink, LayoutOrder = 1 })
		P.text(top, string.upper(`{count} × {if count == 1 then held.one else held.many}`), UDim2.fromOffset(0, 22), {
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Theme.HeadingFont,
			TextSize = 16,
			LayoutOrder = 2,
		})
		local note = P.caps(weaponRow, if holding == "horse" then "Leading · no gun, no sprint" else "Hands full · no gun, no sprint", UDim2.new(1, 0, 0, 16), {
			Position = UDim2.fromOffset(0, 24),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = P.warn,
		})
		note.Name = "Restriction"
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
	-- 3.9: on foot the holster (B) and the melee (V): empty hands, or the gun with what B and V do now.
	local hands = not seated and not holstered and away
	local status = if holstered then "Holstered"
		elseif carGun then "On the roof"
		elseif not usable then "⚠ On foot only"
		elseif seated then "Window ready"
		elseif touchLayout then (if hands then "Holstered · tap DRAW or PUNCH" else "Ready · tap here to switch gun")
		elseif hands then "[B] Draw · [V] Punch"
		else "[B] Holster · [V] Strike"
	local group = Ui.make("CanvasGroup", {
		Name = "GunLine",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = if holstered or not usable then 0.45 else 0,
	}, weaponRow)
	local top = lineRow(group, 24)
	Ui.icon(top, if hands then nil else Icons.weapon(def.id), if hands then "✊" elseif def.splash > 0 then "💥" elseif def.pellets > 1 then "🎯" else "🔫", UDim2.fromOffset(34, 22), {
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ImageColor3 = P.ink,
		LayoutOrder = 1,
	})
	P.text(top, if hands then "HANDS" else string.upper(def.name), UDim2.fromOffset(0, 24), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = 16,
		LayoutOrder = 2,
	})
	if not carGun and not touchLayout then
		-- Q: how to switch (hold: the wheel).
		P.keyBox(top, "Q", 20, { LayoutOrder = 3 })
	end
	P.caps(group, status, UDim2.new(1, 0, 0, 14), {
		Position = UDim2.fromOffset(0, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = if not usable and not holstered then P.danger else P.ink2,
	})
	if not carGun then
		-- A click: the next gun. 4.2, a tap on a touch screen: the weapon wheel (a tap on a gun takes it).
		local tap = Ui.make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 2 }, weaponRow)
		tap.Activated:Connect(function()
			local wheel = Hud.onWeaponWheel
			if touchLayout and wheel then
				wheel()
			else
				nextWeapon()
			end
		end)
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
	Holster.drawIfHolstered() -- 3.9: the gun picked comes into the hand (as on the weapon wheel)
	Net.get("Equip"):FireServer("weapon", owned[index % #owned + 1])
end

-- The inventory: the consumables as compact tokens (the key, the item's small icon, the count; the name over it on
-- hover or gamepad focus; a click or a tap uses it), and INVENTORY [I] (the backpack) under them.
hotbar = Ui.make("Frame", {
	Name = "Hotbar",
	Size = UDim2.fromOffset(RIGHT_W, HOTBAR_H),
	BackgroundTransparency = 1,
	LayoutOrder = 4,
}, right)
local tokens = lineRow(hotbar, 30, 4)
tokens.Name = "Items"
hotbarCounts = {}
for index, def in Config.Items do
	local token = Ui.make("TextButton", {
		Name = `{def.id}Tag`,
		Size = UDim2.fromOffset(if touchLayout then 44 else 48, 30),
		BackgroundColor3 = P.raised,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = index,
	}, tokens)
	local outline = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = 0.7 }, token)
	if not touchLayout then
		P.caps(token, tostring(index), UDim2.fromOffset(12, 12), { Position = UDim2.fromOffset(3, 1), TextSize = 10, TextStrokeTransparency = 1 })
	end
	Ui.icon(token, Icons.item(def.id), def.icon, UDim2.fromOffset(18, 18), {
		Position = UDim2.new(0, if touchLayout then 5 else 13, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ImageColor3 = P.ink,
	})
	local count = P.text(token, "0", UDim2.fromOffset(16, 30), {
		Position = UDim2.new(1, -4, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.MonoFont,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	-- None left: the token dims (its name still says what it is).
	count:GetPropertyChangedSignal("Text"):Connect(function()
		count.TextTransparency = if count.Text == "0" then 0.5 else 0
	end)
	count.TextTransparency = 0.5
	hotbarCounts[def.id] = count
	-- The name over the token while the mouse (or the gamepad) is on it.
	local name = P.caps(token, def.name, UDim2.fromOffset(0, 18), {
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(1, 0, 0, -6),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.15,
		TextColor3 = P.ink,
		Visible = false,
		ZIndex = 5,
	})
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, name)
	local function show(on: boolean)
		name.Visible = on and not touchLayout
		outline.Transparency = if on then 0.1 else 0.7
		token.BackgroundTransparency = if on then 0.3 else 1
	end
	token.MouseEnter:Connect(function()
		show(true)
	end)
	token.MouseLeave:Connect(function()
		show(false)
	end)
	token.SelectionGained:Connect(function()
		show(true)
	end)
	token.SelectionLost:Connect(function()
		show(false)
	end)
	token.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		useItem(def.id)
	end)
end
P.action(hotbar, if touchLayout then "INVENTORY" else "INVENTORY  [I]", {
	Name = "Inventory",
	Size = UDim2.fromOffset(0, if touchLayout then 44 else 22),
	Position = UDim2.new(1, -2, 0, 32),
	AnchorPoint = Vector2.new(1, 0),
	TextSize = 12,
}, function()
	toggleBackpack()
end)

-- FIRE for touch screens (auto-aim): a square with a thin line on a charcoal backing; layout() keeps it above
-- Roblox's jump button.
FIRE_SIZE = 96
fire = placed(Ui.make("TextButton", {
	Name = "Fire",
	Size = UDim2.fromOffset(FIRE_SIZE, FIRE_SIZE),
	Position = UDim2.new(1, -40, 1, -190),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundColor3 = P.surface,
	BackgroundTransparency = 0.35,
	Text = "FIRE",
	TextColor3 = P.ink,
	Font = Theme.HeadingFont,
	TextSize = 20,
	Visible = false,
	AutoButtonColor = false,
}, gui))
Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.ink, Thickness = 1, Transparency = 0.2 }, fire)
Ui.make("Frame", { Name = "Accent", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = P.red, BorderSizePixel = 0 }, fire)
fire.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		fire.BackgroundTransparency = 0.15 -- (pressed)
		Shooting.setAutoHeld(true)
	end
end)
fire.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		fire.BackgroundTransparency = 0.35
		Shooting.setAutoHeld(false)
	end
end)
-- 3.9: the hands on a touch screen, stacked over FIRE (its children: they move, scale and hide with it): PUNCH /
-- STRIKE (the melee, client/Holster.luau) right over it and DRAW / HOLSTER over that. renderWeapons sets their words
-- and shows them on foot with free hands.
local function handButton(name: string, text: string, height: number, above: number, onClick: () -> ()): any
	local button = Ui.make("TextButton", {
		Name = name,
		Size = UDim2.fromOffset(FIRE_SIZE, height),
		Position = UDim2.new(1, 0, 0, -above),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.35,
		Text = text,
		TextColor3 = P.ink,
		Font = Theme.HeadingFont,
		TextSize = if height > 36 then 16 else 13,
		AutoButtonColor = false,
		Visible = false,
	}, fire)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.ink, Thickness = 1, Transparency = 0.3 }, button)
	button.Activated:Connect(onClick)
	return button
end
touchHands.melee = handButton("Melee", "PUNCH", 44, 8, Holster.melee)
touchHands.holster = handButton("Holster", "DRAW", 30, 60, Holster.toggle)
view.touchHands = touchHands -- 4.2: layout() places them on a touch layout (client/TouchLayout.luau)
-- 4.2: SPRINT and EXIT / PUT DOWN (a touch layout only; layout() places them).
require(script.Parent.TouchControls).build(gui)
end

-- ── Car panel ──────────────────────────────────────────────────────────────

-- 3.8, the vehicle line in the lower right column (no round dial): while you drive the speed in compact type with its
-- unit, then "OLD VAN / 72% / CARGO 3 OF 4" (the car's or its stage's name, its condition, occupied / total cargo
-- slots at its stage). On foot it stays as a quieter line with PARKED; without a car it says how to get one.
-- RenderStepped fills it (view.vehicle; only what changed).
local carPanel: any, hint: any
do -- (its own block: the locals below stay out of the 200-register limit)
carPanel = Ui.make("Frame", {
	Name = "Vehicle",
	Size = UDim2.fromOffset(view.right.Size.X.Offset, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 3,
}, view.right)
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, carPanel)
local v: any = {}
v.speedRow = Ui.make("Frame", { Name = "Speed", Size = UDim2.fromOffset(view.right.Size.X.Offset, 30), BackgroundTransparency = 1, LayoutOrder = 1, Visible = false }, carPanel)
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, v.speedRow)
v.speed = P.text(v.speedRow, "0", UDim2.fromOffset(0, 30), { AutomaticSize = Enum.AutomaticSize.X, Font = Theme.HeadingFont, TextSize = 28, LayoutOrder = 1 })
v.unit = P.caps(v.speedRow, "KM/H", UDim2.fromOffset(0, 22), { AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 })
v.line = P.caps(carPanel, "", UDim2.fromOffset(view.right.Size.X.Offset, 18), {
	TextSize = 13,
	TextColor3 = P.ink,
	TextXAlignment = Enum.TextXAlignment.Right,
	RichText = true,
	LayoutOrder = 2,
})
v.shown = "" -- what the line shows (it redraws only when it changes)
view.vehicle = v

-- Every frame (RenderStepped): your car (nil: none out) and the car you sit in. The line redraws only when its
-- words change; the speed only while you are inside.
function view.drawVehicle(car: Model?, seatedIn: Model?)
	if not car then
		if v.shown ~= "none" then
			v.shown = "none"
			v.speedRow.Visible = false
			v.line.Text = "NO CAR  /  MENU → CAR"
			v.line.TextTransparency = 0.2
		end
		return
	end
	local carId = tostring(car:GetAttribute("CarId"))
	local stage = tonumber(car:GetAttribute("Stage")) or 0
	local health = (car:GetAttribute("Health") or 0) :: number
	local maxHealth = math.max(1, (car:GetAttribute("MaxHealth") or 1) :: number)
	local share = math.clamp(health / maxHealth, 0, 1)
	local capacity = Economy.stageCapacity(carId, stage)
	local loaded = tonumber(car:GetAttribute("CargoCount")) or inVehicle() or 0
	local inside = seatedIn == car
	local pct = math.floor(share * 100 + 0.5)
	local shown = `{carId}|{stage}|{pct}|{capacity}|{loaded}|{inside}`
	if v.shown ~= shown then
		v.shown = shown
		local def = Economy.findCar(carId)
		local stageDef = Economy.stageDef(carId, stage)
		local name = string.upper(if stageDef then stageDef.name elseif def then def.name else "Car")
		-- The condition: white, the warm warn under half, the red with a ⚠ from a quarter down.
		local tint = if share <= 0.25 then P.danger elseif share <= 0.5 then P.warn else P.ink
		local condition = `<font color="{P.hex(tint)}">{if share <= 0.25 then "⚠ " else ""}{pct}%</font>`
		local cargo = if capacity > 0 then `CARGO {math.min(loaded, capacity)} OF {capacity}` else "NO CARGO SLOTS"
		v.line.Text = `{view.esc(name)}  /  {condition}  /  {cargo}{if inside then "" else "  /  PARKED"}`
		v.line.TextTransparency = if inside then 0 else 0.2
		v.speedRow.Visible = inside
	end
	if inside then
		local chassis = car.PrimaryPart
		local velocity = if chassis then chassis.AssemblyLinearVelocity else Vector3.zero
		local text = (if Drive.boosting() then "⚡" else "") .. tostring(math.floor(Vector3.new(velocity.X, 0, velocity.Z).Magnitude))
		if v.speed.Text ~= text then
			v.speed.Text = text
		end
	end
end

-- The contextual action, lower centre (layout() places and scales it): one key in a square outline, the action in
-- white caps, a short instruction under it, and a fine progress line while a hold runs (the loading, unloading,
-- boarding or serving the server reports: Hud.setJob's progress). The centre of the world stays clear. Hidden while it
-- has nothing to say.
hint = placed(Ui.make("Frame", {
	Name = "Hint",
	Size = UDim2.fromOffset(0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	Position = UDim2.new(0.5, 0, 1, -40),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundTransparency = 1,
	Visible = false,
}, gui))
Ui.make("UISizeConstraint", { Name = "Max", MaxSize = Vector2.new(480, math.huge) }, hint)
-- A soft charcoal backing, strongest in the middle (the action reads over a bright street).
-- (it fills the hint exactly; the column's padding makes the room around the words)
local glow = Ui.make("Frame", { Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.surface, BorderSizePixel = 0, ZIndex = 0 }, hint)
Ui.make("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.22, 0.5),
		NumberSequenceKeypoint.new(0.78, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, glow)
local column = Ui.make("Frame", { Name = "Column", Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1 }, hint)
Ui.list(column, true, 6)
Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 34), PaddingRight = UDim.new(0, 34), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }, column)
local row = Ui.make("Frame", { Name = "Row", Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, LayoutOrder = 1 }, column)
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, row)
local a: any = {}
a.key = P.keyBox(row, "E", 30, { LayoutOrder = 1, Visible = false })
local words = Ui.make("Frame", { Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, LayoutOrder = 2 }, row)
Ui.list(words, true, 2)
a.main = P.text(words, "", UDim2.fromOffset(0, 0), {
	AutomaticSize = Enum.AutomaticSize.XY,
	Font = Theme.HeadingFont,
	TextSize = 15,
	TextWrapped = true,
	LayoutOrder = 1,
})
Ui.make("UISizeConstraint", { MaxSize = Vector2.new(360, math.huge) }, a.main)
a.sub = P.caps(words, "", UDim2.fromOffset(0, 0), {
	AutomaticSize = Enum.AutomaticSize.XY,
	TextWrapped = true,
	TextTruncate = Enum.TextTruncate.None,
	Visible = false,
	LayoutOrder = 2,
})
Ui.make("UISizeConstraint", { MaxSize = Vector2.new(360, math.huge) }, a.sub)
a.column = column
a.shown = ""
view.action = a
end

-- ── Job panel ──────────────────────────────────────────────────────────────
-- 3.8, the contract group (upper left, the first entry of the contract column), replacing the 3.6 tilted ticket and
-- its timer stub. On a soft charcoal scrim:
--   ■ DELIVERY CONTRACT · PIZZA RUN · ★★ · STOP 1/2     (a mission: ■ MISSION 3 · NAME)
--   THE DESTINATION                                      (the stop's place, large white caps)
--   □ the objectives: the stop's action and its pieces ("Pick up: 0 of 3 pizza boxes loaded"), the modifier, and
--     what went wrong (pieces lost, a battered cargo: a ⚠ and words, never the colour alone)
--   ─────
--   04:36 REMAINING / EST. $640 / 420 M                  (the time red when it runs short; night pay, a wave)
-- What to do right now (the job's step: "Get out and open the back (E)") is the contextual action, lower centre.
-- With no job and nothing else in the column: a small OFF DUTY line that opens the Dispatch board.

local LOAD_H: any, loadFill: any, loadBack: any, loadText: any
do -- (its own block: the locals below stay out of the 200-register limit)
local slot = Hud.topSlot("job")
local t: any = {}
view.ticket = t

-- RichText needs its own escapes, and colours as hex.
function view.esc(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
view.hex = P.hex

-- The group's holder in the column (the column lays it out).
t.wrap = Ui.make("Frame", { Name = "Contract", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false, LayoutOrder = 1 }, slot)
P.scrim(t.wrap, 0.6)
local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, t.wrap)
Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, body)
Ui.list(body, true, 5)
local labelRow = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 1 }, body)
P.marker(labelRow, 8, { Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
t.label = P.caps(labelRow, "", UDim2.new(1, -16, 1, 0), { Position = UDim2.fromOffset(16, 0) })
t.title = P.text(body, "", UDim2.new(1, 0, 0, 0), {
	AutomaticSize = Enum.AutomaticSize.Y,
	Font = Theme.HeadingFont,
	TextSize = 22,
	TextWrapped = true,
	LayoutOrder = 2,
})
P.rule(body, UDim2.new(1, 0, 0, 1), { LayoutOrder = 3 })
local list = Ui.make("Frame", { Name = "Objectives", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4 }, body)
Ui.list(list, true, 3)
-- The objective rows (a pool of six; 4.8: the cargo's rules and the road event): a square box (filled when done) and
-- the words; a warning has no box but a ⚠.
t.rows = {}
for n = 1, 6 do
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = n, Visible = false }, list)
	local box = Ui.make("Frame", { Name = "Box", Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(1, 5), BackgroundColor3 = P.ink, BackgroundTransparency = 1, BorderSizePixel = 0 }, row)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.ink, Thickness = 1, Transparency = 0.1 }, box)
	local text = P.text(row, "", UDim2.new(1, -20, 0, 0), {
		Position = UDim2.fromOffset(20, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 14,
		TextWrapped = true,
		LineHeight = 1.05,
	})
	table.insert(t.rows, { row = row, box = box, text = text })
end
P.rule(body, UDim2.new(0.82, 0, 0, 1), { LayoutOrder = 5 })
t.timer = P.caps(body, "", UDim2.new(1, 0, 0, 18), { TextSize = 13, RichText = true, LayoutOrder = 6 })
t.meta0 = ""
t.clock0 = ""

-- (the title wraps by itself now; layout() still calls this)
function view.fitTicket() end

-- "DELIVER to Bob, 42 Maple St" → "DELIVER", "Bob, 42 Maple St": the label's shouted words (the action) and the rest
-- (the place; a leading "at" / "to" / "for" dropped).
local function split(text: string): (string, string)
	local words = string.split(text, " ")
	local cut = #words + 1
	for index, word in words do
		-- (a house number starts the place: "UNLOAD AT THE NEW HOME, 42 Maple St")
		if word:upper() ~= word or string.match(word, "^%d") then
			cut = index
			break
		end
	end
	local action = table.concat(words, " ", 1, cut - 1)
	local place = table.concat(words, " ", cut)
	-- "DELIVER THE AMMO TO" + "Military Base": the action without its "to" / "at" / "for".
	for _, tail in { " TO", " AT", " FOR" } do
		if #action > #tail and string.sub(action, -#tail) == tail then
			action = string.sub(action, 1, -#tail - 1)
		end
	end
	local first = string.lower(words[cut] or "")
	if first == "at" or first == "to" or first == "for" then
		place = table.concat(words, " ", cut + 1)
	end
	return action, place
end

local function sentence(text: string): string
	local lower = string.lower(text)
	return lower:sub(1, 1):upper() .. lower:sub(2)
end

-- One objective row: kind "todo" (an empty box), "done" (a filled box), "warn" (a ⚠, the contract red), "quiet".
local function objective(n: number, kind: string?, text: string?)
	local r = t.rows[n]
	if not r then
		return
	end
	r.row.Visible = kind ~= nil
	if not kind then
		return
	end
	r.box.Visible = kind == "todo" or kind == "done"
	r.box.BackgroundTransparency = if kind == "done" then 0 else 1
	r.text.Position = UDim2.fromOffset(if r.box.Visible then 20 else 0, 0)
	r.text.Size = UDim2.new(1, if r.box.Visible then -20 else 0, 0, 0)
	r.text.Text = text or ""
	r.text.TextColor3 = if kind == "warn" then P.danger elseif kind == "quiet" then P.ink2 else P.ink
	r.text.TextTransparency = if kind == "done" then 0.35 else 0
end

-- The parts of the group that change with a job update (Hud.setJob).
function view.fillTicket()
	if not job then
		return
	end
	local index, count = tonumber(job.stopIndex) or 1, tonumber(job.stopCount) or 1
	local stars = string.rep("★", tonumber(job.stars) or 0)
	local mission = job.mission
	local kind = if type(mission) == "table" and mission.number then `Mission {mission.number} · {mission.name or ""}`
		else `Delivery contract · {if job.jobType then job.jobType.name else tostring(job.cargo or "")}`
	t.label.Text = string.upper(`{kind}{if stars ~= "" then ` · {stars}` else ""}{if count > 1 then ` · stop {index}/{count}` else ""}`)
	local action, place = split(tostring(job.stopLabel or job.cargo or ""))
	t.title.Text = string.upper(if place ~= "" then place else action)
	t.action = if place ~= "" and action ~= "" then sentence(action) elseif job.stage == "pickup" then "Pick up" else "Deliver"
	t.meta0 = "" -- (the objectives are drawn again on the next frame)
end

-- The group's live parts (every frame from RenderStepped): the deadline line and, when they change, the objectives.
function view.tickTicket(distance: number?)
	if not job then
		return
	end
	local left = job.endsAt - workspace:GetServerTimeNow()
	local clock = Ui.clock(left)
	local urgent = left < 30
	local wave = tonumber(job.wave) or 0
	local footer = `{clock}|{urgent}|{job.pay}|{distance}|{job.night}|{wave}`
	if footer ~= t.clock0 then
		t.clock0 = footer
		local parts = { `<font color="{P.hex(if urgent then P.danger else P.ink)}">{clock}</font> REMAINING`, `EST. {Ui.money(job.pay)}` }
		if job.night == true then
			table.insert(parts, "NIGHT PAY")
		end
		if wave > 0 then
			table.insert(parts, `WAVE {wave}`)
		end
		if distance then
			table.insert(parts, `{distance} M`)
		end
		t.timer.Text = table.concat(parts, "  /  ")
	end
	-- The objectives: the stop's action and its pieces, the modifier, then what went wrong.
	local needed = tonumber(job.needed) or 0
	local done = tonumber(job.delivered) or 0
	local lost = tonumber(job.lost) or 0
	local condition = tonumber(job.condition) or 1
	-- 5.0, on foot: the backpack ("Backpack 1/2"; the PackCount / PackRoom attributes are live, the payload's pack
	-- and packRoom the fallback).
	local packRoom = if job.mode == "foot" or job.mode == "bike" then tonumber(player:GetAttribute("PackRoom")) or tonumber(job.packRoom) or 0 else 0
	local packed = tonumber(player:GetAttribute("PackCount")) or tonumber(job.pack) or 0
	local signature = `{t.action}|{needed}|{done}|{lost}|{math.floor(condition * 100 + 0.5)}|{job.modifier and job.modifier.name}|{job.stage}|{job.ruleLine}|{job.eventLine}|{packed}/{packRoom}|{job.ordersLine}`
	if signature == t.meta0 then
		return
	end
	t.meta0 = signature
	local cargo = jobCargo()
	local n = 0
	local function add(kind: string, text: string)
		n += 1
		objective(n, kind, text)
	end
	if needed > 0 and job.handling ~= "drive" then
		local verb = if job.stage == "pickup" then "loaded" else "delivered"
		add(if done >= needed then "done" else "todo", `{t.action}: {math.min(done, needed)} of {needed} {if needed == 1 then cargo.one else cargo.many} {verb}`)
	else
		add("todo", tostring(t.action))
	end
	-- 5.2: the other orders of the run ("+2 ORDERS · …"; every one on the phone's ORDERS app).
	if type(job.ordersLine) == "string" then
		add("quiet", job.ordersLine)
	end
	if packRoom > 0 then
		add(if packed >= packRoom then "warn" else "quiet", `{if job.mode == "bike" then "🚲 On the bike" else "🎒 Backpack"} {packed}/{packRoom}{if packed >= packRoom then " · full" else ""}`)
	end
	local modifier = job.modifier
	if type(modifier) == "table" and modifier.name then
		add("todo", `{sentence(tostring(modifier.name))}: {string.lower(tostring(modifier.description or ""))}`)
	end
	-- 4.8: the cargo's rules ("Fresh 82% · Fragile: brake gently"; stale food in the contract red) and the road event.
	if type(job.ruleLine) == "string" then
		add(if (tonumber(job.freshness) or 1) < 0.35 then "warn" else "quiet", job.ruleLine)
	end
	if type(job.eventLine) == "string" then
		add("todo", job.eventLine)
	end
	if lost > 0 then
		add("warn", `⚠  {lost} {if lost == 1 then cargo.one else cargo.many} lost`)
	end
	if condition < 0.4 then
		add("warn", `⚠  Cargo condition {math.floor(condition * 100 + 0.5)}%`)
	elseif condition < 0.995 and n < 4 then
		add("quiet", `Cargo condition {math.floor(condition * 100 + 0.5)}%`)
	end
	for k = n + 1, #t.rows do
		objective(k, nil, nil)
	end
end

-- The OFF DUTY line: no job, nothing else in the column. A click (a tap) opens the Dispatch board.
local idle = Ui.make("Frame", { Name = "OffDuty", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Visible = false, LayoutOrder = 2 }, slot)
local idleRow = Ui.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, idle)
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, idleRow)
P.marker(idleRow, 8, { BackgroundColor3 = P.ink2, LayoutOrder = 1 })
P.caps(idleRow, "Off duty", UDim2.fromOffset(0, 44), { AutomaticSize = Enum.AutomaticSize.X, TextColor3 = P.ink, LayoutOrder = 2 })
P.action(idleRow, if touchLayout then "DISPATCH BOARD" else "PICK A RUN  [J]", { LayoutOrder = 3, TextSize = 12 }, openDispatch)
t.idle = idle
t.idleAt = 0

-- Shows the OFF DUTY line when the column has nothing on it (no job; no crew strip, invitation or mission banner).
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

-- The hold progress (loading / unloading / boarding / serving, from the server's Job payload): a fine line under the
-- contextual action and its words in small caps. loadBack is the holder (shown while it runs), loadFill the line.
LOAD_H = 20
local column = view.action.column
loadBack = Ui.make("Frame", { Name = "Progress", Size = UDim2.new(1, 0, 0, LOAD_H), BackgroundTransparency = 1, Visible = false, LayoutOrder = 3 }, column)
local track
track, loadFill = P.bar(loadBack, UDim2.new(1, 0, 0, 2), P.ink)
track.Position = UDim2.fromOffset(0, 2)
loadText = P.caps(loadBack, "", UDim2.new(1, 0, 0, 14), { Position = UDim2.fromOffset(0, 6), TextSize = 11 })
-- (the bar's holder keeps a width when the words above it are short)
Ui.make("UISizeConstraint", { MinSize = Vector2.new(220, LOAD_H) }, loadBack)
end

-- ── The way to the target ──────────────────────────────────────────────────
-- The park circle (a ring and a light beam) and, on foot during a carry step, a small ring at the pile / the
-- person with a thin beam over their head; a floating waypoint. 4.5.2: no arrow over the car or your head (the
-- route on the maps, the circle, the beam and the waypoint show the way).
-- 3.8: the contract's red for the job's stop, white for the pile / the person / the vehicle's back and the GPS point.
-- The waypoint is small and monochrome: a red (or white) square, the name in white caps, the distance under it, and a
-- fine line down to the spot.
-- 4.4.1 (minimal): the circles are thin outlines on the ground (a SurfaceGui on a flat invisible part), not filled
-- neon discs; the light is a thin beam that fades out upwards.

local beacon: any, ring: any, pileRing: any, label: any, labelText: any, HIDDEN: any, PICKUP_COLOR: any, PILE_COLOR: any, UPRIGHT: any, hideGuide: any, placeGuide: any, GPS_COLOR: any, gps: any, myPosition: any, footTarget: any
do -- (its own block: the locals below stay out of the 200-register limit)
local guide = Instance.new("Folder")
guide.Name = "DeliveryGuide"
guide.Parent = workspace
-- The job's stop: the contract red (like the job's route on the maps: client/MapView.luau).
view.guideColor = P.red

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

-- 4.4.1: a circle as a thin outline: a SurfaceGui on the Right face of a flat invisible part. Stood up with UPRIGHT
-- (like the old cylinders) that face looks up, so the code placing the circles stays the same. The outline (and a
-- faint fill, `fill` its transparency) follows the part's Color. `stroke` is in studs.
local function outlinePart(name: string, diameter: number, stroke: number, fill: number): Part
	local p = guidePart(name, Vector3.new(0.05, diameter, diameter), 1)
	local surface = Ui.make("SurfaceGui", {
		Face = Enum.NormalId.Right,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 16,
		LightInfluence = 0,
		AlwaysOnTop = false, -- (parked under the map it is out of sight)
	}, p)
	local width = stroke * 16
	local disc = Ui.make("Frame", {
		Size = UDim2.new(1, -width * 2, 1, -width * 2),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = p.Color,
		BackgroundTransparency = fill,
		BorderSizePixel = 0,
	}, surface)
	Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, disc)
	local line = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = p.Color, Thickness = width, Transparency = 0.1 }, disc)
	p:GetPropertyChangedSignal("Color"):Connect(function()
		disc.BackgroundColor3 = p.Color
		line.Color = p.Color
	end)
	return p
end

-- The light over the spot: an invisible carrier part (stood up, 240 long) with a thin Beam along it, faint at the
-- bottom and gone at the top. Narrow over the circle, narrower still over the pile / the person.
local BEACON_WIDE = 1.2
local BEACON_THIN = 0.5
beacon = guidePart("Beacon", Vector3.new(240, 0.2, 0.2), 1)
local beamBottom = Ui.make("Attachment", { Position = Vector3.new(-120, 0, 0) }, beacon)
local beamTop = Ui.make("Attachment", { Position = Vector3.new(120, 0, 0) }, beacon)
local light = Ui.make("Beam", {
	Attachment0 = beamBottom,
	Attachment1 = beamTop,
	FaceCamera = true,
	LightEmission = 0,
	LightInfluence = 0,
	Segments = 1,
	Width0 = BEACON_WIDE,
	Width1 = BEACON_WIDE,
	Color = ColorSequence.new(view.guideColor),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.45, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, beacon)
ring = outlinePart("Ring", Config.Jobs.DeliverRadius * 2, 0.35, 0.93)
pileRing = outlinePart("PileRing", 5, 0.22, 1)
label = guidePart("Label", Vector3.new(0.2, 0.2, 0.2), 1)
-- 3.8: the waypoint over the spot. Its bottom (a small dot at the end of a fine line) sits on the label point; over it
-- the square in the guide's colour, the name in white caps and the distance (view.mark writes both). White on a faint
-- charcoal stroke: it reads over a night street and a sunny one alike.
local labelGui = Ui.make("BillboardGui", { Size = UDim2.fromOffset(240, 78), SizeOffset = Vector2.new(0, 0.5), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 100000 }, label)
local words = Ui.make("Frame", { Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.fromScale(0.5, 0), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, labelGui)
Ui.make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Padding = UDim.new(0, 7),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, words)
view.markSquare = P.marker(words, 8, { LayoutOrder = 1 })
Ui.make("UIPadding", { PaddingTop = UDim.new(0, 4) }, words)
labelText = P.text(words, "", UDim2.fromOffset(0, 36), {
	AutomaticSize = Enum.AutomaticSize.X,
	Font = Theme.HeadingFont,
	TextSize = 14,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextStrokeTransparency = 0.45,
	RichText = true,
	LineHeight = 1.1,
	LayoutOrder = 2,
})
-- The fine line down to the spot and the dot at its end.
Ui.make("Frame", { Name = "Stem", Size = UDim2.fromOffset(1, 30), Position = UDim2.new(0.5, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = P.ink, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, labelGui)
Ui.make("Frame", { Name = "Dot", Size = UDim2.fromOffset(4, 4), Position = UDim2.new(0.5, 0, 1, 0), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = P.ink, BorderSizePixel = 0 }, labelGui)

-- The waypoint's words: the name in caps over the distance.
function view.mark(name: string, distance: number): string
	return `{view.esc(string.upper(name))}\n<font size="12" color="{P.hex(P.ink2)}">{distance} m</font>`
end
HIDDEN = CFrame.new(0, -1000, 0)
PICKUP_COLOR = P.red -- (a pick-up is the job's stop too; the waypoint says PICK UP)
PILE_COLOR = P.ink -- the pile, the person, the vehicle's back: white
UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis is X: stood up

function hideGuide()
	beacon.CFrame = HIDDEN
	ring.CFrame = HIDDEN
	pileRing.CFrame = HIDDEN
	label.CFrame = HIDDEN
	-- 4.4.1: the waypoint is drawn on top of everything, so parked under the map it still showed: switch it off.
	labelGui.Enabled = false
end
hideGuide()

local function paintGuide(color: Color3)
	if beacon.Color == color then
		return
	end
	for _, part in { beacon, ring } do
		part.Color = color
	end
	light.Color = ColorSequence.new(color)
	view.markSquare.BackgroundColor3 = color
end

-- 4.3: a spot on the real surface. A spot below it (a raised lot, a ramp, a yard over the road level) comes up onto it,
-- so the circle and the waypoint never sit in the ground; a spot on the ground stays. Two spots are remembered (the
-- circle and the person), so it casts only when one moves.
local snapParams = RaycastParams.new()
snapParams.FilterType = Enum.RaycastFilterType.Exclude
snapParams.RespectCanCollide = true
local snaps: { { from: Vector3, to: Vector3 } } = {}
local function onSurface(spot: Vector3): Vector3
	for _, s in snaps do
		if s.from == spot then
			return s.to
		end
	end
	local skip: { Instance } = { guide }
	for _, name in { "Cars", "Npcs", "Zombies", "Animals", "Loot", "Equipment", "Effects" } do
		local child = workspace:FindFirstChild(name)
		if child then
			table.insert(skip, child)
		end
	end
	if player.Character then
		table.insert(skip, player.Character)
	end
	snapParams.FilterDescendantsInstances = skip
	local to = spot
	-- Just over the spot: the floor under it (a little higher than the spot when it is a little buried).
	local near = workspace:Raycast(spot + Vector3.new(0, 3, 0), Vector3.new(0, -5, 0), snapParams)
	if near then
		if near.Position.Y > spot.Y then
			to = Vector3.new(spot.X, near.Position.Y, spot.Z)
		end
	else
		-- Nothing right under it: deep in the ground (a ray starting inside a part does not hit it). Look from higher.
		local top = workspace:Raycast(spot + Vector3.new(0, 40, 0), Vector3.new(0, -40, 0), snapParams)
		if top and top.Position.Y > spot.Y and top.Position.Y < spot.Y + 12 then -- (not a roof over a gap)
			to = Vector3.new(spot.X, top.Position.Y, spot.Z)
		end
	end
	table.insert(snaps, 1, { from = spot, to = to })
	snaps[3] = nil
	return to
end

-- The park circle at p with the beam over it (or a thin beam over the pile / the person at `beamAt`), the label
-- over `labelAt` (default p).
function placeGuide(spot: Vector3, color: Color3, beamSpot: Vector3?, labelSpot: Vector3?)
	local p = onSurface(spot)
	local beamAt = if beamSpot then onSurface(beamSpot) else nil
	-- (a label without a beam is over your vehicle's back: it moves with the car and needs no ground)
	local labelAt = if labelSpot and beamSpot then (if labelSpot == beamSpot then beamAt else onSurface(labelSpot)) else labelSpot
	paintGuide(color)
	ring.CFrame = CFrame.new(p + Vector3.new(0, 0.15, 0)) * UPRIGHT
	if beamAt then
		light.Width0 = BEACON_THIN
		light.Width1 = BEACON_THIN
		-- Starts over the person's head, so it never hides them.
		beacon.CFrame = CFrame.new(beamAt + Vector3.new(0, 127, 0)) * UPRIGHT
	else
		light.Width0 = BEACON_WIDE
		light.Width1 = BEACON_WIDE
		beacon.CFrame = CFrame.new(p + Vector3.new(0, 120, 0)) * UPRIGHT
	end
	label.CFrame = CFrame.new((labelAt or p) + Vector3.new(0, 10, 0))
	labelGui.Enabled = true
end

-- The GPS: a place picked on the big map (the job's target goes first).
GPS_COLOR = P.ink -- white, like the GPS route on the maps (client/MapView.luau)
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
	-- (an empty trolley or pallet jack, 4.0 Pushing, holds nothing yet)
	local me = player.Character
	local holding = myCarrying() ~= nil and not (me and me:GetAttribute("Pushing") ~= nil and me:GetAttribute("CarryCount") == nil)
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
-- A banner in the contract column (under the contract group; a level-up mostly comes as the job ends): LEVEL UP, the
-- new level and rank, what it unlocks; the XP line flashes. Under the windows, so it never hides the delivery result.
-- 3.8: a charcoal strip with a thin good-green rule on its left, white type; it fades in and out (no bounce).

local refreshLevel: () -> ()
do -- (a block of its own: its locals stay out of the module's 200-register limit)
local levelUpFrame = Ui.make("CanvasGroup", {
	Name = "LevelUp",
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = P.surface,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Visible = false,
	ZIndex = 4,
}, Hud.topSlot("levelup"))
Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = P.good, BorderSizePixel = 0 }, levelUpFrame)
local levelUpBody = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, levelUpFrame)
Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10) }, levelUpBody)
Ui.list(levelUpBody, true, 3)
P.caps(levelUpBody, "⬆  Level up", UDim2.new(1, 0, 0, 14), { TextColor3 = P.good, TextStrokeTransparency = 1, LayoutOrder = 1 })
local levelUpTitle = Ui.label(levelUpBody, "", UDim2.new(1, 0, 0, 0), {
	AutomaticSize = Enum.AutomaticSize.Y, -- a long rank wraps on a narrow column
	TextSize = 20,
	Font = Theme.HeadingFont,
	TextColor3 = P.ink,
	LayoutOrder = 2,
})
local levelUpUnlocks = Ui.label(levelUpBody, "", UDim2.new(1, 0, 0, 0), {
	AutomaticSize = Enum.AutomaticSize.Y,
	TextSize = 13,
	Font = Theme.Font,
	TextColor3 = P.ink2,
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
	levelUpTitle.Text = `LEVEL {to}  /  {rank:upper()}`
	levelUpUnlocks.Text = if #unlocked > 0 then `🔓  {table.concat(unlocked, "  ·  ")}` else "Better jobs, missions and cars wait on the next levels."
	levelUpStamp += 1
	local mine = levelUpStamp
	P.fade(levelUpFrame, true, 0.25)
	-- The XP line and the level flash the good green.
	xpFill.BackgroundColor3 = P.good
	levelChip.TextColor3 = P.good
	TweenService:Create(xpFill, TweenInfo.new(1.2), { BackgroundColor3 = P.ink2 }):Play()
	TweenService:Create(levelChip, TweenInfo.new(1.2), { TextColor3 = P.ink }):Play()
	Hud.toast(`LEVEL {to}! You are a {rank} now.`)
	task.delay(4.5, function()
		if levelUpStamp ~= mine then
			return
		end
		P.fade(levelUpFrame, false, 0.5)
	end)
end

-- The level shown (nil until the save loaded: the first value is no level-up).
local shownLevel: number? = nil

-- The level, the rank, the XP line; a level-up flashes and the open shop shows what it unlocked.
function refreshLevel()
	local xp = myXp()
	if xp == nil then
		levelChip.Text = "LV 1"
		rankLabel.Text = string.upper(Levels.rank(1))
		xpLabel.Text = ""
		xpFill.Size = UDim2.fromScale(0, 1)
		return
	end
	local level = Levels.levelFor(xp)
	levelChip.Text = `LV {level}`
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
	-- (4.6: the level-up card is client/CareerUi.luau's: what you unlocked, the reward, what comes next; the old banner
	-- would say it twice)
	if before ~= nil and level > before and Hud.oldLevelBanner then
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
local CALL_COLOR = P.ink -- white while it comes; the good green when it is here, warn when it could not come
local CALL_DONE_SHOWN = 3 -- seconds "Your car is here" stays
local CALL_STALE = 20

-- 3.8: a compact charcoal strip with a thin rule on its left (its colour says how it goes), white text, the distance
-- in small caps on the right and a fine line along the bottom that fills as the car comes.
local callLine = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = P.surface, BackgroundTransparency = 0.22, BorderSizePixel = 0 }, Hud.topSlot("carcall"))
callLine.Name = "CarCall"
callLine.Visible = false
local callStroke = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = CALL_COLOR, Thickness = 1, Transparency = 0.85 }, callLine)
local callEdge = Ui.make("Frame", { Name = "Edge", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = CALL_COLOR, BorderSizePixel = 0 }, callLine)
local callText = Ui.label(callLine, "", UDim2.new(1, -112, 0, 24), {
	Position = UDim2.fromOffset(14, 4),
	TextSize = 14,
	Font = Theme.HeadingFont,
	TextColor3 = P.ink,
	TextWrapped = false,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
local callDistance = P.caps(callLine, "", UDim2.fromOffset(84, 24), {
	Position = UDim2.new(1, -96, 0, 4),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextStrokeTransparency = 1,
})
local callBack, callFill = P.bar(callLine, UDim2.new(1, -28, 0, 2), CALL_COLOR)
callBack.Position = UDim2.new(0, 14, 1, -7)

-- The marker over the car in the world (seen through walls, like the delivery waypoint).
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
-- 3.8: white caps on a faint charcoal stroke (it reads over a night street and a sunny one), the time and the
-- distance under it, a small ▼ in the line's colour.
local markerPill = Ui.make("Frame", {
	Size = UDim2.new(1, -20, 0, 42),
	Position = UDim2.fromOffset(10, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, callMarker)
local markerText = P.text(markerPill, "", UDim2.new(1, 0, 0, 22), {
	Position = UDim2.fromOffset(0, 3),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 15,
	Font = Theme.HeadingFont,
	TextStrokeTransparency = 0.45,
})
local markerSub = P.caps(markerPill, "", UDim2.new(1, 0, 0, 14), {
	Position = UDim2.fromOffset(0, 24),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextStrokeTransparency = 0.45,
})
Ui.label(callMarker, "▼", UDim2.new(1, 0, 0, 18), {
	Position = UDim2.fromOffset(0, 42),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 14,
	Font = Theme.HeadingFont,
	TextColor3 = CALL_COLOR,
	TextStrokeColor3 = P.surface,
	TextStrokeTransparency = 0.45,
})

local callLoop = false

local function carPart(car: Model?): BasePart?
	if not car or not car.Parent then
		return nil
	end
	return car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")
end

local function setCarButton(text: string)
	-- (the CAR entry of the MENU list)
	local button = hudButtons.car
	if button and button.Text ~= text then
		button.Text = text
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
		markerText.Text = "YOUR CAR"
		markerSub.Text = if distance then `here · {distance} m` else "here"
		setCarButton("CAR")
	else
		local left = math.max(0, math.ceil(current.arriveAt - now))
		callText.Text = if left > 0 then `🚗  Your car is on the way · {left} s` else "🚗  Your car is almost here"
		callStroke.Color = CALL_COLOR
		callFill.BackgroundColor3 = CALL_COLOR
		callEdge.BackgroundColor3 = CALL_COLOR
		callFill.Size = UDim2.fromScale(math.clamp(1 - (current.arriveAt - now) / current.total, 0, 1), 1)
		markerText.Text = "YOUR CAR"
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
-- again when the screen changes, the native chat window moves or resizes, players come and go (the player list
-- grows) or the ADMIN button comes or goes. 3.8, the contract composition:
--
--   COMPUTER (keyboard and mouse)                       TOUCH, held sideways (phone or tablet, no keyboard)
--   ┌──────────────────────────────────────────────┐    ┌──────────────────────────────────────────────┐
--   │ (chat)                MAP CREW MENU (players)│    │ cash    ■ CONTRACT          MAP CREW MENU    │
--   │ ■ CONTRACT                                   │    │ minimap DESTINATION                          │
--   │ DESTINATION                                  │    │ health  □ objectives                         │
--   │ □ objectives                                 │    │         04:36 / EST.  (column)               │
--   │ 04:36 REMAINING / EST.                       │    │                                  ┌weapon─┐  │
--   │ (column: tutorial, crew, ...)       ┌weapon─┐│    │ (thumb-                          │vehicle│(FIRE)
--   │ cash / rank                         │vehicle││    │  stick)     [E] ACTION           │items  │(jump)
--   │ minimap         [E] ACTION          │items  ││    │             ─────                └───────┘  │
--   │ + health        ─────               └───────┘│    └──────────────────────────────────────────────┘
--   └──────────────────────────────────────────────┘
--
--   * Margins 16 px, gaps 8 px. The ADMIN button (client/AdminPanel.luau, 90 × 32 at 16 px from the right, 56 from
--     the top, unscaled) keeps the top right corner (down to ADMIN_BOTTOM) while it shows (admins, Studio).
--   * Left: cash + minimap + health, one column (LEFT_W × LEFT_H × S): bottom left on a computer (the chat is top
--     left), top left on touch (the thumbstick is bottom left).
--   * Upper left: the contract column, at the left margin under Roblox's top bar on a computer; under the native
--     chat window while it is open (its rectangle from TextChatService's ChatWindowConfiguration; 4.5.2: never right
--     of it, and a closed chat takes no room), right of the minimap
--     column on touch (under it when a screen held upright has no room beside it). TOP_W × S wide (narrower down to
--     TOP_MIN_W before it gets smaller) and as tall as the room over the lower panels allows (TOP_EST_H).
--   * Upper right: MAP CREW MENU. A computer has Roblox's player list (leaderstats) top right: the row sits left of
--     it (PLAYER_LIST_W), or under it when the screen is too narrow. On touch top right, under ADMIN. MENU's list opens
--     downward (upward when it would leave the screen).
--   * Lower right: the weapon / cargo line, the vehicle line and the inventory, right-aligned in one column. Touch:
--     the FIRE button just over Roblox's jump button (70 px at 95 / 90 px from the corner on a small screen, 120 px at
--     170 / 210 px on a big one), the column left of them. A touch screen with a keyboard: FIRE left of the column.
--   * Lower centre: the contextual action (key box, words, the fine hold progress line), its bottom HINT_BOTTOM × S over
--     the margin, between the left column (touch: the thumbstick's corner) and the right column. client/Stamina.luau's
--     breath bar sits higher (16 + 170 × S from the bottom), clear of it.

do -- (its own block: the locals below stay out of the 200-register limit)
local MARGIN = 16
local GAP = 8
local ADMIN_BOTTOM = 96 -- client/AdminPanel.luau: the ADMIN button at (1, -16, 0, 56), 90 × 32, unscaled
local TOUCH_BUTTON_MIN = 0.8
local TOP_EST_H = 200 -- the contract column's usual height (unscaled): the group with its objectives, a hint or a line under it
local TOP_MIN_W = 300 -- a narrow span first makes the contract column narrower (down to this), then smaller
local PLAYER_LIST_W = 370 -- Roblox's player list with this game's three leaderstats (px, not scaled by us)
local HINT_BOTTOM = 18 -- the contextual action's bottom over the margin (unscaled)
local HINT_W = 480 -- its widest (unscaled)

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

-- Is a native Roblox interface on (StarterGui:GetCoreGuiEnabled; on when it cannot be asked)?
local function coreOn(kind: Enum.CoreGuiType): boolean
	local ok, on = pcall(function()
		return game:GetService("StarterGui"):GetCoreGuiEnabled(kind)
	end)
	return not ok or on == true
end

-- 4.5.2: is the native chat window open (Roblox's chat button toggles it; StarterGui's "ChatActive")? Open when it
-- cannot be asked. ChatWindowConfiguration keeps Enabled and its rectangle while the window is closed, so before
-- 4.5.2 a closed chat still pushed the contract column down, and then (no room under it) to its right: the column
-- stood near the middle of the screen. Hud.start looks at this twice a second (there is no signal for it).
function view.chatShown(): boolean
	local ok, active = pcall(function()
		return game:GetService("StarterGui"):GetCore("ChatActive")
	end)
	return not ok or active ~= false
end

-- The native chat window's rectangle on a computer (TextChatService's ChatWindowConfiguration), in this HUD's
-- coordinates; nil when there is none or it is closed.
local function chatBox(): Box?
	view.chatOpen = view.chatShown()
	if touchLayout or not coreOn(Enum.CoreGuiType.Chat) or not view.chatOpen then
		return nil
	end
	local ok, found = pcall(function(): Box?
		local TextChatService = game:GetService("TextChatService")
		if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
			return box(0, 0, 400, 200) -- the legacy chat: top left, about this big
		end
		local config = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
		if not config or not config.Enabled then
			return nil
		end
		local position, size = config.AbsolutePosition - gui.AbsolutePosition, config.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return nil
		end
		return box(position.X, position.Y, position.X + size.X, position.Y + size.Y)
	end)
	return if ok then found else nil
end

layout = function()
	local size = screenArea()
	local W, H = size.X, size.Y
	local S = Ui.scaleFor(size)
	for _, s in scales do
		s.Scale = S
	end
	-- What the contract column and the action must stay clear of.
	local below: { Box } = {}

	-- Left: the cash line, the minimap and the health row.
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

	-- Lower right: FIRE over the jump button (touch); the column of the weapon, the vehicle and the inventory.
	local admin = adminButtonShown()
	local right = view.right
	local rightW, rightH = right.Size.X.Offset * S, right.Size.Y.Offset * S
	local fireSize = FIRE_SIZE * S
	setScale(fire, S)
	setScale(right, S)
	fire.AnchorPoint = Vector2.new(1, 1)
	local columnRight = W - MARGIN
	local columnBottom = H - MARGIN
	local thumb: Box? = nil
	local cluster: any = nil
	if touchLayout then
		-- 4.2 (client/TouchLayout.luau): FIRE over Roblox's jump button, SPRINT / the hand button (PUNCH, EXIT, PUT
		-- DOWN) / DRAW in a column left of them, each at least 44 px; the right column left of them (or over them).
		local TouchLayout = require(script.Parent.TouchLayout)
		cluster = TouchLayout.cluster(W, H, S)
		local c = cluster
		setScale(fire, (c.fire.x1 - c.fire.x0) / FIRE_SIZE)
		fire.Position = UDim2.fromOffset(c.fire.x1, c.fire.y1)
		local textSize = math.max(12, math.floor(14 * math.max(S, 0.8) + 0.5))
		for key, b in ({ melee = c.act, holster = c.holster } :: { [string]: any }) do
			local button = view.touchHands[key]
			button.Parent = gui -- (out of FIRE: its own size, not FIRE's scale)
			button.AnchorPoint = Vector2.zero
			button.Position = UDim2.fromOffset(math.floor(b.x0 + 0.5), math.floor(b.y0 + 0.5))
			button.Size = UDim2.fromOffset(math.floor(b.x1 - b.x0 + 0.5), math.floor(b.y1 - b.y0 + 0.5))
			button.TextSize = textSize
			button.TextWrapped = true
		end
		require(script.Parent.TouchControls).place(c.sprint, c.act, textSize)
		view.touchBoxes = TouchLayout.buttons(c)
		for _, b in view.touchBoxes do
			table.insert(below, b)
		end
		table.insert(below, c.jump)
		-- The right column: under it the actions' row (and ADMIN) must stay clear when it goes over the buttons.
		local rowBottom = (if admin then ADMIN_BOTTOM else MARGIN) + buttonGrid.Size.Y.Offset * math.max(S, TOUCH_BUTTON_MIN)
		local placedColumn = TouchLayout.column(c, W, H, rightW, rightH, rowBottom)
		table.insert(view.touchBoxes, placedColumn)
		columnRight, columnBottom = placedColumn.x1, placedColumn.y1
		-- Roblox's thumbstick lives in the bottom left corner: nothing of ours goes there.
		thumb = c.thumb
	elseif UserInputService.TouchEnabled then
		-- A touch screen with a keyboard: FIRE left of the column.
		local fireRight = W - MARGIN - rightW - 12
		fire.Position = UDim2.fromOffset(fireRight, H - MARGIN)
		table.insert(below, box(fireRight - fireSize, H - MARGIN - fireSize, fireRight, H - MARGIN))
	end
	right.AnchorPoint = Vector2.new(1, 1)
	right.Position = UDim2.fromOffset(columnRight, columnBottom)
	local column = box(columnRight - rightW, columnBottom - rightH, columnRight, columnBottom)
	table.insert(below, column)
	local cornerLeft = column.x0
	for _, b in below do
		if b ~= left and b.y1 > H * 0.5 then
			cornerLeft = math.min(cornerLeft, b.x0)
		end
	end

	-- Lower centre: the contextual action, between the left column (or the thumbstick) and the right one.
	setScale(hint, S)
	local spanLeft = (if thumb then thumb.x1 elseif touchLayout then MARGIN else left.x1) + 12
	local spanRight = cornerLeft - 12
	local hintW = math.max(160, math.min(HINT_W * S, spanRight - spanLeft))
	local hintX = math.clamp(W / 2, spanLeft + hintW / 2, math.max(spanLeft + hintW / 2, spanRight - hintW / 2))
	local hintBottom = H - (if touchLayout then GAP else MARGIN) - HINT_BOTTOM * S
	if cluster then
		-- 4.2: between the thumbstick and the touch buttons or the column (narrower on a narrow phone; upright, over
		-- them), and the breath bar (client/Stamina.luau) right over it.
		hintX, hintBottom, hintW = require(script.Parent.TouchLayout).hint(cluster, view.touchBoxes, W, H, S)
		require(script.Parent.Stamina).place(hintX, hintBottom - 108 * S)
	end
	local hintMax = hint:FindFirstChild("Max")
	if hintMax and hintMax:IsA("UISizeConstraint") then
		hintMax.MaxSize = Vector2.new(hintW / S, math.huge)
	end
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.fromOffset(hintX, hintBottom)
	table.insert(below, box(hintX - hintW / 2, hintBottom - 96 * S, hintX + hintW / 2, hintBottom))

	-- Upper right: MAP CREW MENU (its Size is the unscaled row).
	local base = if touchLayout then math.max(S, TOUCH_BUTTON_MIN) else S
	local gw, gh = buttonGrid.Size.X.Offset, buttonGrid.Size.Y.Offset
	local buttonScale = math.clamp(base, 0.45, base)
	setScale(buttonGrid, buttonScale)
	local rowW, rowH = gw * buttonScale, gh * buttonScale
	local rowRight, rowTop = W - MARGIN, if admin then ADMIN_BOTTOM else MARGIN
	if not touchLayout then
		rowTop = 4 -- (in line with the top of the chat and the player list)
		if coreOn(Enum.CoreGuiType.PlayerList) then
			if W - MARGIN - PLAYER_LIST_W - rowW >= MARGIN + TOP_MIN_W * S + 24 then
				rowRight = W - MARGIN - PLAYER_LIST_W -- left of the player list
			else
				-- Too narrow: under the player list (about 40 px a player and its header).
				local listBottom = math.min(H * 0.45, 52 + 40 * #Players:GetPlayers())
				rowTop = math.max(listBottom, if admin then ADMIN_BOTTOM else 0) + GAP
			end
		end
	end
	buttonGrid.AnchorPoint = Vector2.new(1, 0)
	buttonGrid.Position = UDim2.fromOffset(rowRight, rowTop)
	local grid = box(rowRight - rowW, rowTop, rowRight, rowTop + rowH)
	-- MENU's list opens downward, upward when it would leave the screen.
	local menu = view.menu
	local menuH = (4 + view.menuHeight) * buttonScale
	if grid.y1 + menuH > H - MARGIN and grid.y0 - menuH >= 0 then
		menu.AnchorPoint = Vector2.new(1, 1)
		menu.Position = UDim2.new(1, 0, 0, -4)
	else
		menu.AnchorPoint = Vector2.new(1, 0)
		menu.Position = UDim2.new(1, 0, 1, 4)
	end

	-- The column's real height (unscaled): the contract with the toasts, the banners and the hints under it.
	-- 4.5.1: with hysteresis. The height is measured through the scale this sets (text heights round to whole pixels,
	-- a wrapped line can flip), so a fresh measurement each time made scale → height → scale chase each other: the
	-- column (the contract, Marge's hint) resized every frame, a flicker. It now follows a real change only: taller by
	-- more than a few px (smaller now), or shorter by more than a toast or two (bigger again).
	local stackScale = topStack:FindFirstChild("LayoutScale")
	local tall = view.topTall or TOP_EST_H
	if stackScale and stackScale:IsA("UIScale") and stackScale.Scale > 0.01 then
		local measured = math.max(TOP_EST_H, topStack.AbsoluteSize.Y / stackScale.Scale)
		if view.topTall == nil or measured > tall + 10 or measured < tall - 56 then
			tall = measured
		end
	end
	view.topTall = tall
	-- The contract column: as big as the span (from x0 to x1 at y) and the room under it allow.
	local function fit(y: number, x0: number, x1: number): (number, number)
		local span = x1 - x0
		local width = math.clamp(span / S, TOP_MIN_W, TOP_W)
		local scale = math.min(S, span / width)
		local floor = ceilingBelow(below, x0, x0 + width * scale, y, H)
		scale = math.min(scale, (floor - GAP - y) / tall)
		return scale, width
	end
	-- Its right end: the row of actions when the row is beside it (else the screen's edge, or ADMIN).
	local function rightLimit(y: number): number
		local limit = W - MARGIN
		if grid.y1 > y and grid.y0 < y + tall * S then
			limit = math.min(limit, grid.x0 - GAP)
		end
		if admin then
			limit = math.min(limit, W - 16 - 90 - GAP)
		end
		return limit
	end
	-- 4.5.2: always at the left margin on a computer, under Roblox's top bar (the ScreenGui's CoreUISafeInsets).
	-- An open chat window over it pushes it down, under the chat, still at the left (no longer beside the chat:
	-- on a wide screen that put the column near the middle). Little room under the chat makes it smaller instead.
	local topX, topY = MARGIN, 14
	if touchLayout then
		topX, topY = left.x1 + GAP, MARGIN
	end
	local chat = chatBox()
	if chat and chat.x0 < topX + TOP_W * S and chat.x1 > topX then
		if chat.y0 < H * 0.5 then
			if chat.y1 > topY then
				topY = chat.y1 + GAP -- under the chat window
			end
		else
			table.insert(below, chat) -- (a chat moved to the bottom: the column stays clear of it)
		end
	end
	local topScale, topWidth = fit(topY, topX, rightLimit(topY))
	if touchLayout and topScale < S * 0.8 then
		-- No room beside the minimap and the actions (upright): under them, the whole width.
		local y = math.max(left.y1, grid.y1) + GAP
		local scale, width = fit(y, MARGIN, W - MARGIN)
		if scale > topScale then
			topX, topY, topScale, topWidth = MARGIN, y, scale, width
		end
	end
	-- Never smaller than readable (the 3.7 floor 0.3 made 4 px text): rather overlap the lower panels a little.
	topScale = math.max(topScale, 0.7 * S)
	setScale(topStack, topScale)
	topStack.Size = UDim2.fromOffset(topWidth, 0)
	topStack.Position = UDim2.fromOffset(topX, topY)
	view.fitTicket()
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
	-- Most States change money or items only: the weapon line is rebuilt when what it shows changed.
	if weaponBarKey() ~= shownWeaponBar then
		renderWeapons()
	end
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
		view.giveUpRule.Visible = job ~= nil
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
	loadText.Text = string.upper(if job.handling == "board" then (if pickup then "Getting on… wait in the circle" else "Getting off… wait in the circle")
		elseif job.handling == "serve" then "Serving… hold still"
		elseif pickup then "Loading… hold still"
		else "Unloading… hold them off!")
	hint.Visible = hint.Visible or loadBack.Visible
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

-- 3.8, the contextual action (lower centre): what to do right now in white caps, a short instruction under it and
-- its key in the key box (`key`, or a "(E)" at the end of the words; none on a touch screen). Shown while it has
-- something to say or a hold runs.
local function setHint(main: string, sub: string?, key: string?)
	local a = view.action
	local words, found = string.match(main, "^(.-)%s*%(([%w%s]+)%)%s*$")
	if words and found and #found <= 5 then
		main, key = words, key or found
	end
	if touchLayout then
		key = nil
		-- 4.2: no keys on a touch screen: "Put it down (G) and open the back (E)" reads "Put it down and open the back"
		-- (the PUT DOWN button and the prompts are tapped).
		main = (string.gsub(main, "%s*%([EGQ]%)", ""))
		sub = if sub then (string.gsub(sub, "%s*%([EGQ]%)", "")) else nil
	end
	local signature = `{main}|{sub}|{key}`
	if a.shown ~= signature then
		a.shown = signature
		a.main.Text = string.upper(main)
		a.sub.Text = string.upper(sub or "")
		a.sub.Visible = sub ~= nil and sub ~= ""
		a.key.Visible = key ~= nil
		a.key.Text = string.upper(key or "")
	end
	local visible = main ~= "" or loadBack.Visible
	if hint.Visible ~= visible then
		hint.Visible = visible
	end
end

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		return
	end
	local now = os.clock()
	view.checkIdle(now)
	-- The car: the vehicle line.
	local car = Drive.myCar()
	local seatedIn, driving = Drive.seatedCar()
	view.drawVehicle(car, seatedIn)

	-- Your health (the Humanoid's).
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local life = if humanoid then math.ceil(humanoid.Health) else 0
	if life ~= view.health then
		view.health = life
		local most = if humanoid then math.max(1, humanoid.MaxHealth) else 100
		view.healthText.Text = tostring(life)
		view.healthFill.Size = UDim2.fromScale(math.clamp(life / most, 0, 1), 1)
		view.healthFill.BackgroundColor3 = if life / most > 0.3 then P.ink else P.danger
		view.healthText.TextColor3 = if life / most > 0.3 then P.ink else P.danger
	end

	-- Got in / out, cargo in your hands, or the car gun changed: the weapon line shows what fires now (or what you
	-- carry); the consumables hide while you carry.
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
		-- Picked up / put down: the backpack shows it, the consumables hide while you carry.
		lastHolding = holding
		hotbar.Visible = holding == nil
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
		if holding == "horse" then
			setHint("Leading a horse", `no gun, no sprint · {if touch then "tap LET GO" else "G lets go"}`)
		else
			setHint("Load it or hand it over", `no gun, no sprint · {if touch then "tap PUT DOWN" else "G puts it down"} to shoot`, "E")
		end
	elseif inShop then
		setHint(Map.Shops[inShop].name, "walk to the counter", "E")
	elseif seatedIn and not driving then
		local gun = if state then Economy.findWeapon(state.weapon) else nil
		if touchLayout then
			setHint("Riding along", if gun and not gun.oneHanded then `the {gun.name} is too big for the window · tap the gun line for a pistol, revolver or SMG` else "FIRE shoots out of the window · EXIT gets out")
		else
			setHint("Riding along", if gun and not gun.oneHanded then `the {gun.name} is too big for the window · Q to a pistol, revolver or SMG` else "right mouse aims, left mouse shoots out of the window · E gets out")
		end
	elseif safe and not job then
		setHint("Dispatch board", if touch then "safe zone · OFF DUTY → DISPATCH BOARD for a run" else "safe zone · shops around the depot", "J")
	elseif not car and state and type(state.car) ~= "string" then
		-- 5.0: no vehicle yet (the career starts on foot): the board, the backpack at Last Stop Supplies.
		-- (with a backpack already: the phone says what to save up for next)
		setHint("On foot", (if touchLayout then "the board in MENU" else "J for the board")
			.. (if require(Shared.Transport).handsRoom(if type(state.kit) == "table" then state.kit else {}) > Config.Cargo.HandsMax then " · your phone says what's next" else " · Supplies for a backpack"), if touchLayout then nil else "J")
	elseif not car then
		setHint("No car out", "MENU → CAR calls it")
	elseif not seatedIn and not job then
		setHint("On foot", if touchLayout then "FIRE shoots · SPRINT runs · tap the prompt at your car's door" elseif touch then "FIRE shoots · E at your car to drive" else "right mouse aims, left mouse shoots · E at your car to drive")
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
			labelText.Text = view.mark(footText or (if pickup then "PICK UP" else (person or tostring(job.customer))), distance)
		end
		view.tickTicket(distance)
	elseif gps then
		local position = myPosition()
		if position then
			local flat = Vector3.new(gps.position.X - position.X, 0, gps.position.Z - position.Z)
			local distance = math.floor(flat.Magnitude)
			labelText.Text = view.mark(gps.name, distance)
			if distance < 30 then
				Hud.toast(`You are at {gps.name}.`)
				gps = nil
				MapView.setWaypoint(nil)
				hideGuide()
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
	-- 3.8: the contract column follows the native chat window; the actions follow the player list.
	pcall(function()
		local config = game:GetService("TextChatService"):FindFirstChildOfClass("ChatWindowConfiguration")
		if config then
			config:GetPropertyChangedSignal("AbsoluteSize"):Connect(requestLayout)
			config:GetPropertyChangedSignal("AbsolutePosition"):Connect(requestLayout)
			config:GetPropertyChangedSignal("Enabled"):Connect(requestLayout)
		end
	end)
	-- 4.5.2: the chat window opened or closed (Roblox's chat button; no signal for it): the column follows.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if gui.Enabled and view.chatShown() ~= view.chatOpen then
				requestLayout()
			end
		end
	end)
	Players.PlayerAdded:Connect(requestLayout)
	Players.PlayerRemoving:Connect(requestLayout)
	MapView.start(gui, leftStack)
	-- Calling your car (server/CarCall.luau).
	local ok, err = pcall(function()
		Net.get("CarCall").OnClientEvent:Connect(onCarCall)
	end)
	if not ok then
		warn(`[Hud] no CarCall remote: {err}`)
	end
	-- 3.6: ESC closes the open window (the footers say so: the HUD's and, through Hud.onCloseWindows, the other
	-- modules'), the big map and the MENU list. Roblox's menu takes the Escape key itself, hence MenuOpened as well.
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
		if key == Enum.KeyCode.I then
			toggleBackpack() -- 3.9: the bag (B holsters the gun now, client/Holster.luau)
			return
		end
		if key == Enum.KeyCode.M then
			MapView.toggle()
		elseif key == Enum.KeyCode.ButtonY then
			-- 4.2, a gamepad: Y opens MENU (every window is in it, MAP and CREW beside it) with the selection on JOBS.
			view.menu.Visible = not view.menu.Visible
			if view.menu.Visible then
				Ui.gamepadFocus(hudButtons.jobs)
			else
				Ui.gamepadRelease(view.menu)
			end
		elseif key == Enum.KeyCode.J then
			local toggle = Hud.onJobsKey
			if toggle then
				toggle()
			else
				openDispatch()
			end
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
