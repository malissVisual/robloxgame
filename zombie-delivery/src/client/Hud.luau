--!strict
-- The interface: money and the driver level (the LV chip, the rank, the XP bar; a flash on a level-up), the minimap
-- (client/MapView.luau), the car panel (health, speed, nitro), the active job (what to do now, the person, the cargo
-- in your hands / at this stop / in the vehicle, the timer, the cargo's condition, the loading bar), the JOBS / MAP /
-- BAG / TOP / CAR buttons (TOP: the leaderboard, client/Leaderboard.luau), the hotbar (items, keys 1-5), the job
-- board, the employers (their car and gun rewards), the shops (opened by their counters; earned guns are not sold;
-- the car guns at Wrench Garage), the weapon bar (your guns, or the car gun while you drive a car that has one), the
-- backpack (with the job's cargo), the delivery result (with the XP, a level-up and the crew's pay split), toasts,
-- the FIRE button for touch screens and the way to the target (the park circle with a beam, on foot the pile / the
-- person or the vehicle's back, an arrow).
-- Driver levels (shared/Levels.luau): what your level does not reach yet shows LEVEL N (cars at the dealer, guns,
-- car guns, the job board's locked offers, an employer's job); the server refuses it anyway.
-- The button column (JOBS, MAP, BAG, CAR, TOP, CREW, ESTATE): CREW and ESTATE run the hooks Hud.onCrew
-- (client/CrewPanel.luau) and Hud.onEstate (client/EstateUi.luau), set by the client's Main; Hud.setBadge and
-- Hud.flashButton mark a button (the crew's invitations). Hud.topSlot gives other modules a place in the top centre
-- stack (the crew strip and the invitation card). Calling your car (the CarCall remote, server/CarCall.luau): a status
-- line "Your car is on the way · 9 s" in the top stack, a marker over the car in the world and on the maps.
-- Where everything sits on a computer and on a touch screen, so nothing overlaps: see ── Layout ── below.

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

-- The vehicle in a word ("truck", "bus", "van") for the short texts.
local function vehicleWord(): string
	local car = Drive.myCar()
	local def = car and Economy.findCar(tostring(car:GetAttribute("CarId")))
	local word = if def then def.name:match("(%a+)$") else nil
	return if word then word:lower() else "vehicle"
end

-- ── Money ──────────────────────────────────────────────────────────────────

-- On a computer the chat sits top left: money goes bottom left above the minimap. On a touch screen top left.
local touchLayout: any, LEFT_H: any, LEFT_W: any, leftStack: any, moneyLabel: any, statsLabel: any, levelChip: any, rankLabel: any, xpLabel: any, xpBack: any, xpFill: any
do -- (its own block: the locals below stay out of the 200-register limit)
touchLayout = Ui.touchLayout()
-- Money and the minimap share one column (one scale), so they can never overlap.
local MONEY_HEIGHT = 110 -- money, the stats, the level and the XP bar
LEFT_W, LEFT_H = 230, MONEY_HEIGHT + 8 + 230 -- (the minimap is 230 × 230, client/MapView.luau)
leftStack = placed(Ui.make("Frame", {
	Name = "LeftStack",
	Size = UDim2.fromOffset(LEFT_W, LEFT_H),
	Position = if touchLayout then UDim2.fromOffset(16, 16) else UDim2.new(0, 16, 1, -16),
	AnchorPoint = if touchLayout then Vector2.zero else Vector2.new(0, 1),
	BackgroundTransparency = 1,
}, gui))
Ui.list(leftStack, true, 8)
local moneyPanel = Ui.panel(leftStack, UDim2.fromOffset(230, MONEY_HEIGHT), UDim2.new())
moneyPanel.LayoutOrder = 1
Ui.padding(moneyPanel, 8)
moneyLabel = Ui.label(moneyPanel, "$0", UDim2.new(1, 0, 0, 32), { TextColor3 = C.money, TextSize = 30, Font = Enum.Font.GothamBlack })
statsLabel = Ui.label(moneyPanel, "", UDim2.new(1, 0, 0, 16), { Position = UDim2.fromOffset(0, 34), TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })
-- The driver level: a LV chip and the rank name, under them the XP bar and the XP into this level.
local levelRow = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 54), BackgroundTransparency = 1, ClipsDescendants = true }, moneyPanel)
Ui.list(levelRow, false, 6)
levelChip = Ui.chip(levelRow, "LV 1", C.yellow, Color3.new(0.04, 0.05, 0.04))
levelChip.Font = Enum.Font.GothamBlack
levelChip.TextSize = 13
levelChip.LayoutOrder = 1
rankLabel = Ui.label(levelRow, "", UDim2.new(0, 0, 1, 0), {
	AutomaticSize = Enum.AutomaticSize.X,
	TextWrapped = false,
	TextSize = 13,
	TextColor3 = C.yellow,
	LayoutOrder = 2,
})
xpLabel = Ui.label(moneyPanel, "", UDim2.fromOffset(84, 16), {
	Position = UDim2.new(1, -84, 0, 77),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 12,
	TextColor3 = C.dim,
	Font = Enum.Font.GothamMedium,
	TextWrapped = false,
})
xpBack, xpFill = Ui.bar(moneyPanel, UDim2.new(1, -90, 0, 7), C.yellow)
xpBack.Position = UDim2.fromOffset(0, 82)
end

-- ── Top stack ──────────────────────────────────────────────────────────────
-- Top centre, one column that grows downward (a UIListLayout: a hidden entry takes no room, so nothing overlaps):
--   1 the job panel (your own job)
--   2 the crew slot (a member's view of the leader's job, an invitation: client/CrewPanel.luau, through Hud.topSlot)
--   3 the mission banner (3.0: client/MissionsUi.luau)
--   4 the car call line ("Your car is on the way · 9 s")
--   5 the level-up banner
--   6 the toasts (the newest last, MAX_TOASTS at most)
-- The job panel, the crew strip and the invitation card never show at the same time (a job of your own, a crew
-- member without one, neither); the rest stacks under whichever shows.

local TOP_W: any, topStack: any
do -- (its own block: the locals below stay out of the 200-register limit)
TOP_W = 540
topStack = placed(Ui.make("Frame", {
	Name = "TopStack",
	Size = UDim2.fromOffset(TOP_W, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.new(0.5, 0, 0, 14),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
}, gui))
Ui.list(topStack, true, 8, Enum.HorizontalAlignment.Center)

local SLOT_ORDER: { [string]: number } = { job = 1, crew = 2, mission = 3, carcall = 4, levelup = 5, toasts = 6 }
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

function Hud.toast(text: string)
	-- Too many: the oldest goes (they never pile up into the middle of the screen).
	local shown: { any } = {}
	for _, child in toasts:GetChildren() do
		if child:IsA("TextLabel") and child:GetAttribute("Leaving") ~= true then
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
	local label = Ui.label(toasts, text, UDim2.new(1, -40, 0, 34), {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.25,
		BackgroundColor3 = C.panel,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 18,
		LayoutOrder = toastOrder,
	})
	Ui.corner(label, 8)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, label)
	task.delay(3, function()
		if not label.Parent then
			return
		end
		label:SetAttribute("Leaving", true)
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.45)
		label:Destroy()
	end)
end
end

-- ── Windows ────────────────────────────────────────────────────────────────

local windows: { any } = {}

-- Does the interface need the mouse right now (a window or the big map is open)?
function Hud.anyWindowOpen(): boolean
	if MapView.isOpen() then
		return true
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
	Leaderboard.close()
	local cb = Hud.onCloseWindows
	if cb then
		cb()
	end
end
Hud.closeWindows = closeWindows
-- One window at a time: the leaderboard (L) closes the HUD's windows too.
Leaderboard.onOpen = closeWindows

type Window = { frame: any, body: any, title: any }

local function window(title: string, size: Vector2): Window
	local frame = scaled(Ui.panel(gui, UDim2.fromOffset(size.X, size.Y), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)))
	frame.Visible = false
	frame.BackgroundTransparency = 0.05
	frame.ZIndex = 5
	Ui.stroke(frame, C.panelLight:Lerp(C.text, 0.2), 1)
	local titleLabel = Ui.label(frame, title, UDim2.new(1, -70, 0, 44), { Position = UDim2.fromOffset(18, 6), TextSize = 26, Font = Enum.Font.GothamBold, TextColor3 = C.text })
	local close = Ui.button(frame, "X", UDim2.fromOffset(40, 40), C.red, function()
		frame.Visible = false
	end)
	close.Position = UDim2.new(1, -50, 0, 8)
	local body = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -28, 1, -64),
		Position = UDim2.fromOffset(14, 54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, frame)
	Ui.list(body, true, 8)
	table.insert(windows, frame)
	return { frame = frame, body = body, title = titleLabel }
end

local function card(parent: any, height: number, order: number, highlight: boolean?): any
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -10, 0, height),
		BackgroundColor3 = C.panelLight,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Ui.corner(frame, 8)
	Ui.stroke(frame, C.panelLight:Lerp(C.text, 0.13), 1)
	if highlight then
		Ui.stroke(frame, C.yellow, 1.5)
	end
	return frame
end

-- name / stats / description on the left of a card.
local function cardText(c: any, name: string, stats: string, description: string, left: number?)
	local x = left or 14
	Ui.label(c, name, UDim2.new(1, -190 - x, 0, 26), { Position = UDim2.fromOffset(x, 6), TextSize = 21, Font = Enum.Font.GothamBlack })
	Ui.label(c, stats, UDim2.new(1, -190 - x, 0, 20), { Position = UDim2.fromOffset(x, 34), TextColor3 = C.yellow, TextSize = 15 })
	Ui.label(c, description, UDim2.new(1, -190 - x, 0, 20), { Position = UDim2.fromOffset(x, 56), TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })
end

local function cardButton(parent: any, text: string, color: Color3, enabled: boolean, onClick: () -> (), slot: number?): any
	local button = Ui.button(parent, text, UDim2.fromOffset(150, 40), if enabled then color else C.grey, function()
		if enabled then
			onClick()
		end
	end)
	button.AutoButtonColor = enabled
	button.TextSize = 16
	local n = slot or 0
	button.Position = UDim2.new(1, -162, 0, if n == 0 then 22 else 2 + (n - 1) * 44)
	return button
end

local function tabs(parent: any, list: { { string } }, selected: string, onPick: (string) -> ())
	local row = Ui.make("Frame", { Size = UDim2.new(1, -10, 0, 40), BackgroundTransparency = 1, LayoutOrder = 0 }, parent)
	Ui.list(row, false, 8)
	for _, entry in list do
		local on = entry[1] == selected
		local button = Ui.button(row, entry[2], UDim2.fromOffset(140, 38), if on then C.yellow else C.grey, function()
			onPick(entry[1])
		end)
		button.TextColor3 = if on then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
	end
end

local function note(parent: any, text: string, color: Color3, order: number)
	Ui.label(parent, text, UDim2.new(1, -10, 0, 22), { LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = color, TextSize = 15, Font = Enum.Font.GothamMedium })
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
	button.TextColor3 = C.dim
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
	Ui.icon(row, iconName, emoji, UDim2.fromOffset(textSize + 4, textSize + 4), { LayoutOrder = 2, ImageColor3 = textProps.TextColor3 or C.text, ZIndex = textProps.ZIndex })
	part((after:gsub("^%s+", "")), 3)
	return row
end

-- A chip (Ui.chip) with an icon in front of its text; without the icon's id the chip it always was, the emoji first.
local function iconChip(parent: any, iconName: string?, emoji: string, text: string, color: Color3, textColor: Color3): any
	if not Icons.get(iconName) then
		return Ui.chip(parent, `{emoji} {text}`, color, textColor)
	end
	local chip = Ui.make("Frame", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = color, BorderSizePixel = 0 }, parent)
	Ui.corner(chip, 6)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, chip)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, chip)
	Ui.icon(chip, iconName, emoji, UDim2.fromOffset(18, 18), { LayoutOrder = 1, ImageColor3 = textColor })
	Ui.label(chip, text, UDim2.new(0, 0, 1, 0), { AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false, TextColor3 = textColor, Font = Enum.Font.GothamBold, TextSize = 14, LayoutOrder = 2 })
	return chip
end

-- ── Job board ──────────────────────────────────────────────────────────────

local jobs: any, openJobs: any, STAR_COLORS: any
do -- (its own block: the locals below stay out of the 200-register limit)
jobs = window("JOB BOARD", Vector2.new(600, 470))
local offersRemote = Net.get("RequestOffers")

local function jobsMessage(text: string)
	Ui.clear(jobs.body)
	Ui.label(jobs.body, text, UDim2.new(1, -10, 0, 60), { TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center })
end

function openJobs()
	closeWindows()
	jobs.frame.Visible = true
	if job then
		Ui.clear(jobs.body)
		Ui.label(jobs.body, `You are delivering {job.cargo} to {job.customer}. Finish it first, or give it up.`, UDim2.new(1, -10, 0, 60), { TextColor3 = C.text })
		Ui.button(jobs.body, "GIVE UP THIS DELIVERY", UDim2.fromOffset(280, 46), C.red, function()
			Net.get("CancelJob"):FireServer()
			jobs.frame.Visible = false
		end)
		return
	end
	jobsMessage("Calling the dispatcher...")
	offersRemote:FireServer()
end

STAR_COLORS = { C.green, C.yellow, C.red, Color3.fromRGB(200, 80, 255) }

-- How the cargo of an offer moves, in two or three words (offer.handling: the first stop's mode).
local OFFER_HANDLING: { [string]: string } = {
	carry = "carried by hand",
	lead = "led on a rope",
	board = "they get on",
	serve = "sold from the truck",
}

function Hud.setOffers(list: { any })
	if job then
		return
	end
	Ui.clear(jobs.body)
	for order, offer in list do
		local color = STAR_COLORS[offer.stars] or C.red
		-- The lines of the card from the top; the card grows with them.
		local y = 94
		local modifierY, typeY = 0, 0
		if offer.modifier then
			modifierY = y
			y += 20
		end
		if offer.jobType then
			typeY = y
			y += 36
		end
		-- Above your driver level: offered, but locked (the server refuses it too).
		local lockLevel = if offer.locked == true then (tonumber(offer.level) or myLevel() + 1) else nil
		local c = card(jobs.body, math.max(104, y + 4), order, offer.jobType ~= nil and lockLevel == nil)
		if lockLevel then
			c.BackgroundColor3 = C.panel
		end
		Ui.label(c, string.rep("★", offer.stars), UDim2.fromOffset(110, 26), { Position = UDim2.fromOffset(12, 6), TextColor3 = color, TextSize = 24 })
		Ui.label(c, offer.tierName:upper(), UDim2.fromOffset(110, 18), { Position = UDim2.fromOffset(12, 32), TextColor3 = color, TextSize = 14 })
		if offer.modifier then
			local chip = Ui.label(c, offer.modifier.name, UDim2.fromOffset(100, 22), {
				Position = UDim2.fromOffset(12, 56),
				BackgroundTransparency = 0,
				BackgroundColor3 = C.red,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = 13,
			})
			Ui.corner(chip, 6)
		end
		local headline = if offer.jobType then `{offer.jobType.name}: {offer.cargo}` else `{offer.cargo} → {offer.customer}`
		Ui.label(c, headline, UDim2.new(1, -260, 0, 24), { Position = UDim2.fromOffset(124, 6), TextSize = 18, TextColor3 = if offer.jobType then Color3.fromRGB(130, 200, 255) else C.text })
		Ui.label(c, `First: {offer.first}`, UDim2.new(1, -260, 0, 18), { Position = UDim2.fromOffset(124, 32), TextColor3 = Color3.fromRGB(130, 200, 255), TextSize = 14, Font = Enum.Font.GothamMedium })
		Ui.label(c, `{offer.stops} stops · last: {offer.address}, {offer.district} · {offer.distance} m · {Ui.clock(offer.time)}`, UDim2.new(1, -260, 0, 18), {
			Position = UDim2.fromOffset(124, 52),
			TextColor3 = C.dim,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
		})
		-- The cargo: how many pieces and how they move.
		local count = tonumber(offer.pieces)
		if count and count > 0 then
			local info = itemInfo(offer.itemKind)
			local name = if count == 1 then (offer.piece or info.one) else (offer.piecesName or info.many)
			local how = OFFER_HANDLING[offer.handling or ""]
			iconText(c, cargoArt(offer.itemKind, offer.piece), info.icon, "", ` {count} {name}` .. (if how then ` · {how}` else ""), UDim2.new(1, -260, 0, 18), {
				Position = UDim2.fromOffset(124, 72),
				TextColor3 = C.text,
				TextSize = 14,
				Font = Enum.Font.GothamMedium,
			})
		end
		if offer.modifier then
			Ui.label(c, offer.modifier.description, UDim2.new(1, -260, 0, 18), { Position = UDim2.fromOffset(124, modifierY), TextColor3 = C.red, TextSize = 13, Font = Enum.Font.GothamMedium })
		end
		if offer.jobType then
			local extra = if offer.vehicle then `Company vehicle: {offer.vehicle}. ` else ""
			Ui.label(c, extra .. offer.jobType.description, UDim2.new(1, -260, 0, 34), { Position = UDim2.fromOffset(124, typeY), TextColor3 = C.dim, TextSize = 13, Font = Enum.Font.GothamMedium })
		end
		Ui.label(c, Ui.money(offer.pay), UDim2.fromOffset(110, 30), { Position = UDim2.new(1, -244, 0, 36), TextColor3 = C.money, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Right })
		local nightRate = tonumber(offer.nightPay)
		if nightRate and nightRate > 1 then
			-- It is night: finished now, the job pays this many times more (Config.DayNight.NightPay).
			Ui.label(c, string.format("🌙 NIGHT ×%.1f", nightRate), UDim2.fromOffset(110, 16), { Position = UDim2.new(1, -244, 0, 66), TextColor3 = C.yellow, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right })
		end
		if lockLevel then
			local lock = Ui.button(c, `🔒 LEVEL {lockLevel}`, UDim2.fromOffset(110, 46), C.grey, function()
				local what = if offer.jobType then `The {offer.jobType.name}` else `{offer.tierName} jobs`
				Hud.toast(`{what} need{if offer.jobType then "s" else ""} driver level {lockLevel} ({Levels.rank(lockLevel)}). Deliveries give XP.`)
			end)
			lock.TextColor3 = C.dim
			lock.TextSize = 15
			lock.Position = UDim2.new(1, -122, 0.5, -23)
		else
			local accept = Ui.button(c, "ACCEPT", UDim2.fromOffset(110, 46), C.green, function()
				Net.get("AcceptJob"):FireServer(offer.index)
				jobs.frame.Visible = false
			end)
			accept.Position = UDim2.new(1, -122, 0.5, -23)
		end
	end
	local refresh = Ui.button(jobs.body, "NEW OFFERS", UDim2.fromOffset(180, 40), C.grey, function()
		jobsMessage("Calling the dispatcher...")
		offersRemote:FireServer()
	end)
	refresh.LayoutOrder = 99
end
end

-- ── Shops ──────────────────────────────────────────────────────────────────

local shop = window("SHOP", Vector2.new(700, 500))
local shopId = "dealer"
local shopFocus: string? = nil
local mechanicTab = "upgrades"

local function carStats(def: Config.CarDef): string
	return `Speed {def.maxSpeed} · Health {def.health} · Ram x{def.ramPower}`
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
		local chip = Ui.chip(c, text, color, if color == C.yellow then Color3.new(0, 0, 0) else Color3.new(1, 1, 1))
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
		button.TextColor3 = C.text
	end
	local money = state.money
	local here = nearShop(shopId)
	shop.title.Text = (Map.Shops[shopId] and Map.Shops[shopId].name or "SHOP"):upper()
	if not here then
		note(shop.body, "Walk into the shop to buy here.", C.red, 1)
	end
	if shopId == "dealer" then
		for order, def in Config.Cars do
			if def.company then
				continue
			end
			local c = card(shop.body, 84, order + 1, def.id == shopFocus)
			local lock = if state.cars[def.id] then nil else lockedAt(def.level)
			cardText(c, def.name, carStats(def) .. (if lock then ` · from level {lock}` else ""), def.description)
			if state.car == def.id then
				cardButton(c, "YOUR CAR", C.grey, false, function() end)
			elseif state.cars[def.id] then
				cardButton(c, "TAKE IT", C.blue, here, function()
					Net.get("Equip"):FireServer("car", def.id)
				end)
			elseif lock then
				lockButton(c, lock)
			else
				cardButton(c, `BUY {Ui.money(def.price)}`, C.green, here and money >= def.price, function()
					Net.get("Buy"):FireServer("car", def.id)
				end)
			end
		end
	elseif shopId == "depot" then
		note(shop.body, "Your cars. Buy new ones at Dead End Motors (next door, east).", C.dim, 1)
		for order, def in Config.Cars do
			if not state.cars[def.id] then
				continue
			end
			local c = card(shop.body, 84, order + 1)
			cardText(c, def.name, carStats(def), def.description)
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
			local exclusive = def.exclusive
			if exclusive and exclusive == "challenges" and not state.weapons[def.id] then
				-- The gun nobody else has: a dark silhouette, nothing given away.
				Ui.icon(c, Icons.weapon(def.id), "❔", UDim2.fromOffset(50, 50), { Position = UDim2.fromOffset(10, 17), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, ImageColor3 = Color3.new(0, 0, 0) })
				cardText(c, "???", "Damage ??? · ???/s · Range ???", "Nobody has ever seen it. Some say it waits for the courier who does everything.", 70)
			else
				cardText(c, def.name, gunStats(def) .. (if def.pierce then ` · Pierces {def.pierce}` else "") .. (if def.oneHanded then " · One-handed" else "") .. (if lock then ` · from level {lock}` else ""), def.description, cardIcon(c, Icons.weapon(def.id), nil, 17))
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
			note(shop.body, "Upgrades work for every car you own. Your car is repaired for free in here.", C.dim, 1)
			for order, def in Config.Upgrades do
				local c = card(shop.body, 84, order + 1)
				local level = Economy.level(state.upgrades, def.id)
				cardText(c, def.name, string.rep("■", level) .. string.rep("□", def.maxLevel - level) .. `  Lv {level}/{def.maxLevel}`, def.description)
				local cost = Economy.upgradeCost(def.id, level)
				if cost then
					cardButton(c, `UPGRADE {Ui.money(cost)}`, C.green, here and money >= cost, function()
						Net.get("Upgrade"):FireServer(def.id)
					end)
				else
					cardButton(c, "MAX", C.grey, false, function() end)
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
				cardText(c, def.name, `{gunStats(def)} · {Ui.money(def.price)}` .. (if lock then ` · from level {lock}` else ""), def.description)
				if installed == def.id then
					cardButton(c, "INSTALLED", C.grey, false, function() end)
				elseif not canMount then
					cardButton(c, "CAN'T MOUNT", C.grey, false, function() end)
				elseif lock then
					lockButton(c, lock)
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
				Ui.stroke(swatch, if def.material == "Neon" then swatchColor:Lerp(Color3.new(1, 1, 1), 0.5) else Color3.new(0, 0, 0), 2)
				Ui.label(c, def.name, UDim2.new(1, -260, 0, 26), { Position = UDim2.fromOffset(70, 8), TextSize = 20, Font = Enum.Font.GothamBlack })
				-- The finish (PaintDef.material) after the price: "Owned · Neon finish".
				local finish = if def.material then ` · {def.material} finish` else ""
				Ui.label(c, (if state.paints[def.id] then "Owned" elseif def.exclusive then "Never sold" else Ui.money(def.price)) .. finish, UDim2.new(1, -260, 0, 20), { Position = UDim2.fromOffset(70, 36), TextColor3 = C.yellow, TextSize = 15 })
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
local employerWindow = window("WORK", Vector2.new(580, 520))

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
	local row = card(parent, 64, order, owned)
	Ui.icon(row, iconName, icon, UDim2.fromOffset(40, 40), { Position = UDim2.fromOffset(12, 12), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center })
	Ui.label(row, name, UDim2.new(1, -200, 0, 24), { Position = UDim2.fromOffset(64, 8), TextSize = 19, Font = Enum.Font.GothamBlack })
	Ui.label(row, if owned then "YOURS" else `{math.min(done, at)}/{at} jobs`, UDim2.fromOffset(120, 24), {
		Position = UDim2.new(1, -132, 0, 8),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = if owned then C.green else C.yellow,
		TextSize = 17,
		Font = Enum.Font.GothamBlack,
	})
	local back, fill = Ui.bar(row, UDim2.new(1, -78, 0, 10), if owned then C.green else C.yellow)
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
	employerWindow.title.Text = `{employer.icon}  {employer.name:upper()}`
	employerWindow.frame.Visible = true
	-- The person who runs it, and what they say.
	Ui.label(body, employer.person, UDim2.new(1, -10, 0, 20), { LayoutOrder = 1, TextColor3 = C.yellow, TextSize = 15 })
	Ui.label(body, `"{employer.pitch}"`, UDim2.new(1, -10, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		TextColor3 = C.text,
		TextSize = 18,
		Font = Enum.Font.GothamMedium,
	})
	if jobType then
		local info = itemInfo(jobType.itemKind)
		local how = HANDLING_TEXT[jobType.load] or "loaded for you"
		local about = card(body, 80, 3)
		iconText(about, info.art, info.icon, "", `  {jobType.name}`, UDim2.new(1, -190, 0, 24), { Position = UDim2.fromOffset(12, 8), TextSize = 19, Font = Enum.Font.GothamBlack })
		local needs = if jobType.level and jobType.level > 1 then `LV {jobType.level}+ · ` else ""
		Ui.label(about, `{needs}Danger {string.rep("★", jobType.tier)}`, UDim2.fromOffset(170, 24), {
			Position = UDim2.new(1, -182, 0, 8),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = STAR_COLORS[jobType.tier] or C.red,
			TextSize = 15,
		})
		local who = if jobType.giver == jobType.receiver then `for {jobType.giver}` else `from {jobType.giver} to {jobType.receiver}`
		Ui.label(about, `{jobType.items} {if jobType.items == 1 then info.one else info.many} {who}: {how}.`, UDim2.new(1, -24, 0, 38), {
			Position = UDim2.fromOffset(12, 36),
			TextColor3 = C.dim,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end
	Ui.label(body, `REWARDS  ·  they lend you the {if reward then reward.name else "vehicle"} for every job`, UDim2.new(1, -10, 0, 22), {
		LayoutOrder = 4,
		TextColor3 = C.dim,
		TextSize = 14,
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
		Ui.label(body, "Finish your current delivery first.", UDim2.new(1, -10, 0, 24), { LayoutOrder = 7, TextColor3 = C.red, TextSize = 16 })
	elseif lock then
		local button = Ui.button(body, `🔒 LEVEL {lock}`, UDim2.fromOffset(240, 50), C.grey, function() end)
		button.TextColor3 = C.dim
		button.LayoutOrder = 7
		Ui.label(body, `{employer.person} hires drivers from level {lock} ({Levels.rank(lock)}) on. You are level {myLevel()}: deliveries give XP.`, UDim2.new(1, -10, 0, 0), {
			LayoutOrder = 8,
			AutomaticSize = Enum.AutomaticSize.Y,
			TextColor3 = C.dim,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
		})
	else
		local take = Ui.button(body, "TAKE THE JOB", UDim2.fromOffset(240, 50), C.green, function()
			Net.get("AcceptEmployer"):FireServer(employer.id)
			employerWindow.frame.Visible = false
		end)
		take.LayoutOrder = 7
	end
end

function Hud.openShop(id: string, focus: string?)
	if id == "jobs" then
		openJobs()
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
backpack = window("BACKPACK", Vector2.new(640, 500))
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
	local c = card(parent, if lost > 0 then 118 else 96, -1, true)
	Ui.label(c, "ON THIS JOB", UDim2.new(1, -24, 0, 18), { Position = UDim2.fromOffset(12, 8), TextColor3 = C.yellow, TextSize = 14 })
	local held = if holding then heldInfo(holding) else nil
	iconText(c, if held then held.art else nil, if held then held.icon else "", if held then "✋  In your hands: " else "✋  Your hands are free", if held then ` {held.one}` else "", UDim2.new(1, -24, 0, 24), {
		Position = UDim2.fromOffset(12, 30),
		TextSize = 18,
		TextColor3 = if held then C.text else C.dim,
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
	iconText(c, if emoji ~= "" then info.art else nil, emoji, before, after, UDim2.new(1, -24, 0, 24), { Position = UDim2.fromOffset(12, 60), TextSize = 16, TextColor3 = C.text, Font = Enum.Font.GothamMedium })
	if lost > 0 then
		Ui.label(c, `⚠  Lost on the way: {lost} {if lost == 1 then info.one else info.many}`, UDim2.new(1, -24, 0, 20), {
			Position = UDim2.fromOffset(12, 88),
			TextSize = 15,
			TextColor3 = C.red,
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
		note(backpack.body, "Switch cars at the depot garage. Buy at Dead End Motors, or earn one by working (M = map).", C.dim, 1)
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
				cardText(c, def.name, carStats(def) .. (if gun then ` · 🔫 {gun.name}` else ""), def.description)
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
					local chip = Ui.chip(c, "★ EXCLUSIVE", Ui.Gps, Color3.new(1, 1, 1))
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
result = window("DELIVERY", Vector2.new(460, 540))

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
	local function line(text: string, value: string?, color: Color3?, order: number): any
		local row = Ui.make("Frame", { Size = UDim2.new(1, -10, 0, 28), BackgroundTransparency = 1, LayoutOrder = order }, result.body)
		Ui.label(row, text, UDim2.new(1, if value then -110 else 0, 1, 0), { TextColor3 = color or C.text, TextSize = 18 })
		if value then
			Ui.label(row, value, UDim2.new(0, 110, 1, 0), { Position = UDim2.new(1, -110, 0, 0), TextColor3 = color or C.money, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right })
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
			line(`{employer.name}: {employer.done} jobs done`, nil, Color3.fromRGB(255, 200, 60), 12)
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
		Ui.label(result.body, r.reason or "", UDim2.new(1, -10, 0, 60), { LayoutOrder = 2, TextColor3 = C.text })
	end
	-- The XP of the job, the level bar and a level-up with what it unlocks.
	local xp = tonumber(r.xp)
	if xp and xp > 0 then
		local level = tonumber(r.level) or myLevel()
		local rank = if type(r.rank) == "string" then r.rank else Levels.rank(level)
		line(if r.success then "Driver XP" else "Driver XP (a failed job still counts)", `+{xp} XP`, C.yellow, 30)
		local row = Ui.make("Frame", { Size = UDim2.new(1, -10, 0, 22), BackgroundTransparency = 1, LayoutOrder = 31 }, result.body)
		Ui.label(row, `LV {level} · {rank}`, UDim2.new(0.5, 0, 1, 0), { TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium, TextWrapped = false })
		local back, fill = Ui.bar(row, UDim2.new(0.5, 0, 0, 8), C.yellow)
		back.Position = UDim2.new(0.5, 0, 0.5, -4)
		local mine = myXp()
		fill.Size = UDim2.fromScale(if mine then Levels.progress(mine) else 0, 1)
		if r.levelUp == true then
			line(`⬆ LEVEL UP! Level {level}: {rank}`, nil, C.green, 32)
			local unlocked = unlocksAt(level)
			if #unlocked > 0 then
				Ui.label(result.body, `Unlocked: {table.concat(unlocked, " · ")}`, UDim2.new(1, -10, 0, 0), {
					LayoutOrder = 33,
					AutomaticSize = Enum.AutomaticSize.Y,
					TextColor3 = C.green,
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
				row.BackgroundColor3 = C.panelLight
				Ui.corner(row, 6)
			end
		end
	end
	local ok = Ui.button(result.body, "OK", UDim2.fromOffset(160, 44), C.blue, function()
		result.frame.Visible = false
	end)
	ok.LayoutOrder = 90
	local next = Ui.button(result.body, "NEXT JOB", UDim2.fromOffset(160, 44), C.green, function()
		result.frame.Visible = false
		openJobs()
	end)
	next.LayoutOrder = 91
end

-- Is the DELIVERY result window open (client/MissionsUi.luau waits with its celebration card until it is closed)?
function Hud.resultOpen(): boolean
	return result ~= nil and result.frame.Visible == true
end
end

-- ── Buttons ────────────────────────────────────────────────────────────────

-- The right column: every button is the Hud's own (other modules hook in: Hud.onCrew, Hud.onEstate). layout()
-- arranges them in one column, two or four (a UIGridLayout) to fit the room between the top right corner and the
-- weapon bar (computer) or the FIRE button (touch).

-- Set by client/Main.client.luau: CREW opens / closes the crew window (CrewPanel.toggle), ESTATE the list of every
-- property (EstateUi.toggleList). Unset, the button says what it is for (CrewPanel.start sets onCrew by itself too).
Hud.onCrew = nil :: (() -> ())?
Hud.onEstate = nil :: (() -> ())?
Hud.onSound = nil :: (() -> ())? -- client/Sounds.luau: music and effects on / music off / all off
Hud.onMissions = nil :: (() -> ())? -- client/MissionsUi.luau: the MISSIONS window

type ButtonDef = { id: string, text: string, icon: string, key: string?, color: Color3, stroke: Color3?, onClick: () -> () }
local BUTTONS: { ButtonDef }, buttonGrid: any, buttonLayout: any, hudButtons: { [string]: any }
do -- (its own block: the locals below stay out of the 200-register limit)
local function toggleJobs()
	if jobs.frame.Visible then
		jobs.frame.Visible = false
	else
		openJobs()
	end
end

-- (type declared above)
BUTTONS = {
	{ id = "jobs", icon = "📋", text = "JOBS", key = "J", color = C.yellow, onClick = toggleJobs },
	{ id = "missions", icon = "⭐", text = "MISSIONS", key = "U", color = C.panelLight, stroke = C.yellow, onClick = function()
		local cb = Hud.onMissions
		if cb then
			cb()
		end
	end },
	{ id = "map", icon = "🗺️", text = "MAP", key = "M", color = C.panelLight, onClick = function()
		MapView.toggle()
	end },
	{ id = "bag", icon = "🎒", text = "BAG", key = "B", color = C.panelLight, onClick = function()
		toggleBackpack()
	end },
	{ id = "car", icon = "🚗", text = "CAR", color = C.panelLight, stroke = C.blue, onClick = function()
		Net.get("SpawnCar"):FireServer()
	end },
	{ id = "top", icon = "🏆", text = "TOP", key = "L", color = C.panelLight, onClick = function()
		Leaderboard.toggle()
	end },
	{ id = "crew", icon = "👥", text = "CREW", key = "K", color = C.panelLight, stroke = Theme.Gps, onClick = function()
		local cb = Hud.onCrew
		if cb then
			cb()
		else
			Hud.toast("The crew panel is not here yet. [fallback: Hud.onCrew is not set]")
		end
	end },
	{ id = "estate", icon = "🏠", text = "ESTATE", key = "H", color = C.panelLight, stroke = C.money, onClick = function()
		local cb = Hud.onEstate
		if cb then
			cb()
		else
			Hud.toast("Real estate is not open yet. [fallback: Hud.onEstate is not set]")
		end
	end },
	{ id = "sound", icon = "🔊", text = "SOUND", key = "N", color = C.panelLight, onClick = function()
		local cb = Hud.onSound
		if cb then
			cb()
		end
	end },
}

buttonGrid = placed(Ui.make("Frame", {
	Name = "HudButtons",
	Size = UDim2.fromOffset(52, 9 * 52),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 96),
	BackgroundTransparency = 1,
}, gui))
buttonLayout = Ui.make("UIGridLayout", {
	CellSize = UDim2.fromOffset(52, 52),
	CellPadding = UDim2.fromOffset(8, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	FillDirection = Enum.FillDirection.Vertical,
	StartCorner = Enum.StartCorner.TopRight,
}, buttonGrid)
hudButtons = {}
local buttonStrokes: { [string]: Color3 } = {}

-- The icon rail: a square glass button per entry, its emoji in the middle, the key in the corner (computer) or the
-- name under the icon (touch); on a computer the name slides out to the left while the mouse is on it.
for order, def in BUTTONS do
	local accent = def.stroke or (if def.color == C.yellow then C.yellow else nil)
	local button = Ui.make("TextButton", {
		Name = `{def.id}Button`,
		Size = if touchLayout then UDim2.fromOffset(62, 62) else UDim2.fromOffset(52, 52), -- layout() sets the cells
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.18,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
	}, buttonGrid)
	Ui.corner(button, 12)
	local border = Ui.stroke(button, accent or C.grey, if accent then 1.5 else 1)
	border.Transparency = if accent then 0.15 else 0.45
	buttonStrokes[def.id] = accent or C.grey
	Ui.label(button, def.icon, if touchLayout then UDim2.new(1, 0, 0.62, 0) else UDim2.fromScale(1, 1), {
		Name = "Icon",
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
	})
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, if touchLayout then 2 else 9), PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, button)
	if touchLayout then
		local name = Ui.label(button, def.text, UDim2.new(1, 0, 0.32, 0), {
			Position = UDim2.fromScale(0, 0.66),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Theme.HeadingFont,
			TextColor3 = accent or C.dim,
		})
		Ui.make("UITextSizeConstraint", { MaxTextSize = 11 }, name)
	else
		if def.key then
			-- The key, small in the bottom right corner.
			local key = Ui.label(button, def.key, UDim2.fromOffset(14, 14), {
				Position = UDim2.new(1, 7, 1, 7),
				AnchorPoint = Vector2.new(1, 1),
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromRGB(10, 14, 13),
				TextSize = 10,
				Font = Theme.HeadingFont,
				TextColor3 = accent or C.dim,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 2,
			})
			Ui.corner(key, 4)
		end
		-- The name: a pill to the left of the button while the mouse is on it.
		local tip = Ui.label(button, if def.key then `{def.text}  ·  {def.key}` else def.text, UDim2.fromOffset(0, 26), {
			Name = "Tip",
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.new(0, -18, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 0.08,
			BackgroundColor3 = C.panel,
			TextSize = 13,
			Font = Theme.HeadingFont,
			TextColor3 = accent or C.text,
			Visible = false,
			ZIndex = 4,
		})
		Ui.corner(tip, 8)
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, tip)
		button.MouseEnter:Connect(function()
			tip.Visible = true
			button.BackgroundColor3 = C.panelLight
			border.Transparency = 0
		end)
		button.MouseLeave:Connect(function()
			tip.Visible = false
			button.BackgroundColor3 = C.panel
			border.Transparency = if accent then 0.15 else 0.45
		end)
	end
	button.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		def.onClick()
	end)
	-- A count in a red dot on the corner (Hud.setBadge).
	local badge = Ui.make("TextLabel", {
		Name = "Badge",
		Size = UDim2.fromOffset(20, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, 5, 0, -5),
		BackgroundColor3 = C.red,
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		Visible = false,
		ZIndex = 3,
	}, button)
	Ui.corner(badge, 10)
	hudButtons[def.id] = button
end

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
	stroke.Color = color or C.yellow
	stroke.Transparency = 0
	task.delay(seconds or 1.5, function()
		stroke.Color = buttonStrokes[id] or Theme.Border
		stroke.Transparency = 0.15
	end)
end
end

-- ── Hotbar ─────────────────────────────────────────────────────────────────

-- The inventory bar: items (keys 1-5) and above them the gun card (the gun in your hands; hold Q: the wheel). Bottom right on a computer,
-- bottom centre on a touch screen (the FIRE button is bottom right there). layout() places them.
local BAR_W: any, HOTBAR_H: any, hotbar: any, weaponBar: any, weaponBarKey: any, shownWeaponBar: any, renderWeapons: any, nextWeapon: any, hotbarCounts: any, FIRE_SIZE: any, fire: any
do -- (its own block: the locals below stay out of the 200-register limit)
BAR_W = 5 * 54 + 4 * 6
HOTBAR_H = 54
hotbar = placed(Ui.make("Frame", {
	Name = "Hotbar",
	Size = UDim2.fromOffset(BAR_W, HOTBAR_H),
	Position = if touchLayout then UDim2.new(0.5, 0, 1, -112) else UDim2.new(1, -16, 1, -16),
	AnchorPoint = if touchLayout then Vector2.new(0.5, 1) else Vector2.new(1, 1),
	BackgroundTransparency = 1,
}, gui))
weaponBar = placed(Ui.make("Frame", {
	Name = "WeaponBar",
	Size = UDim2.fromOffset(BAR_W, 66),
	Position = if touchLayout then UDim2.new(0.5, 0, 1, -184) else UDim2.new(1, -16, 1, -88),
	AnchorPoint = if touchLayout then Vector2.new(0.5, 1) else Vector2.new(1, 1),
	BackgroundTransparency = 1,
}, gui))
-- The weapon bar grows upward with a second row of guns: the column above it moves.
weaponBar:GetPropertyChangedSignal("Size"):Connect(requestLayout)
local weaponRow = Ui.make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, weaponBar)

-- What the weapon bar shows depends on where you are: on foot your guns; driving a car with a car gun that gun; in
-- any other seat your guns, the one-handed ones tagged WINDOW, the two-handed ones greyed out (they do not fire).
local function seatView(): (boolean, Config.CarGunDef?)
	local seatedIn, driving = Drive.seatedCar()
	return seatedIn ~= nil, if seatedIn and driving then Shooting.carGunOf(seatedIn) else nil
end

function weaponBarKey(): string
	local seated, carGun = seatView()
	return `{seated}|{if carGun then carGun.id else ""}`
end
shownWeaponBar = ""

-- The gun card: what is in your hands (or on the roof), big and clear; the other guns are on the weapon wheel
-- (hold Q, client/WeaponWheel.luau) or a tap of Q / of the card away. A coloured edge says what fires: gold your gun,
-- blue the car gun, red a two-handed gun in a car seat (it does not fire there).
function renderWeapons()
	Ui.clear(weaponRow)
	shownWeaponBar = weaponBarKey()
	weaponBar.Size = UDim2.fromOffset(BAR_W, 66)
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
	local accent = if carGun then C.blue elseif not usable then C.red else C.yellow
	local card = Ui.make("TextButton", {
		Name = "GunCard",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.12,
		Text = "",
		AutoButtonColor = false,
	}, weaponRow)
	Ui.corner(card, 12)
	Ui.stroke(card, accent, 1.5).Transparency = 0.25
	local edge = Ui.make("Frame", {
		Size = UDim2.new(0, 4, 1, -20),
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
	}, card)
	Ui.corner(edge, 2)
	local icon = Ui.icon(card, Icons.weapon(def.id), if def.splash > 0 then "💥" elseif def.pellets > 1 then "🎯" else "🔫", UDim2.fromOffset(62, 40), {
		Position = UDim2.new(0, 20, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = if usable then C.text else C.grey
	end
	local name = Ui.label(card, string.upper(def.name), UDim2.new(1, -150, 0, 22), {
		Position = UDim2.fromOffset(92, 11),
		Font = Theme.DisplayFont,
		TextScaled = true,
		TextColor3 = if usable then C.text else C.grey,
	})
	Ui.make("UITextSizeConstraint", { MaxTextSize = 18 }, name)
	local damage = math.floor(def.damage * def.pellets)
	local where = if carGun then "ON THE ROOF" elseif not usable then "ON FOOT ONLY" elseif seated then "OUT OF THE WINDOW" else `{damage} DMG  ·  {def.fireRate}/S`
	Ui.label(card, where, UDim2.new(1, -150, 0, 14), {
		Position = UDim2.fromOffset(92, 37),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = if carGun then C.blue elseif not usable then C.red elseif seated then C.green else C.dim,
	})
	if not carGun and not touchLayout then
		-- Q, how to switch.
		local key = Ui.label(card, "Q", UDim2.fromOffset(30, 30), {
			Position = UDim2.new(1, -14, 0.5, -6),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.fromRGB(10, 14, 13),
			Font = Theme.DisplayFont,
			TextSize = 15,
			TextColor3 = C.yellow,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Ui.corner(key, 8)
		Ui.stroke(key, C.yellow, 1).Transparency = 0.5
		Ui.label(card, "HOLD", UDim2.fromOffset(40, 10), {
			Position = UDim2.new(1, -9, 1, -8),
			AnchorPoint = Vector2.new(1, 1),
			Font = Theme.HeadingFont,
			TextSize = 9,
			TextColor3 = C.dim,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end
	if not carGun then
		-- A tap (touch) or a click: the next gun.
		card.Activated:Connect(nextWeapon)
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
Ui.list(hotbar, false, 6)
hotbarCounts = {}
for index, def in Config.Items do
	local art = Icons.item(def.id)
	local slot = Ui.make("TextButton", {
		Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.18,
		Text = if Icons.get(art) then "" else def.icon, -- the emoji until the item's icon is filled in
		TextSize = 26,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		LayoutOrder = index,
		AutoButtonColor = true,
	}, hotbar)
	Ui.corner(slot, 12)
	Ui.stroke(slot, C.grey, 1).Transparency = 0.4
	if Icons.get(art) then
		Ui.icon(slot, art, def.icon, UDim2.fromOffset(28, 28), { Position = UDim2.fromScale(0.5, 0.48), AnchorPoint = Vector2.new(0.5, 0.5) })
	end
	Ui.label(slot, tostring(index), UDim2.fromOffset(14, 14), { Position = UDim2.fromOffset(5, 3), TextSize = 11, Font = Theme.HeadingFont, TextColor3 = C.dim })
	hotbarCounts[def.id] = Ui.label(slot, "0", UDim2.new(1, -6, 0, 14), {
		Position = UDim2.new(0, 0, 1, -16),
		TextSize = 12,
		Font = Theme.HeadingFont,
		TextColor3 = C.yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	slot.Activated:Connect(function()
		useItem(def.id)
	end)
end

-- FIRE for touch screens (auto-aim). layout() keeps it above Roblox's jump button.
FIRE_SIZE = 110
fire = placed(Ui.make("TextButton", {
	Name = "Fire",
	Size = UDim2.fromOffset(FIRE_SIZE, FIRE_SIZE),
	Position = UDim2.new(1, -40, 1, -190),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundColor3 = C.red,
	Text = "FIRE",
	TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBlack,
	TextSize = 26,
	Visible = false,
	AutoButtonColor = true,
}, gui))
Ui.corner(fire, 55)
Ui.stroke(fire, Color3.new(0, 0, 0), 3)
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

local CAR_W, CAR_H = 380, 86
local carPanel = placed(Ui.panel(gui, UDim2.fromOffset(CAR_W, CAR_H), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1)))
carPanel.Name = "CarPanel"
Ui.padding(carPanel, 10)
local carName = Ui.label(carPanel, "", UDim2.new(0.6, 0, 0, 24), { TextSize = 20, Font = Enum.Font.GothamBlack })
local speedLabel = Ui.label(carPanel, "", UDim2.new(0.4, 0, 0, 24), {
	Position = UDim2.fromScale(0.6, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = C.yellow,
	TextSize = 20,
	Font = Enum.Font.GothamBlack,
})
local healthBack, healthFill = Ui.bar(carPanel, UDim2.new(1, 0, 0, 8), C.green)
healthBack.Position = UDim2.fromOffset(0, 32)
local healthText = Ui.label(carPanel, "", UDim2.new(1, 0, 0, 18), {
	Position = UDim2.fromOffset(0, 44), TextXAlignment = Enum.TextXAlignment.Left,
	TextSize = 13, TextColor3 = C.dim, ZIndex = 2,
})
-- What to do right now, in a line over the car panel (layout() gives it the width between the panels around it;
-- a long one wraps upward).
local hint = Ui.label(gui, "", UDim2.fromOffset(640, 22), {
	Name = "Hint",
	Position = UDim2.new(0.5, 0, 1, if touchLayout then -262 else -104),
	AnchorPoint = Vector2.new(0.5, 1),
	AutomaticSize = Enum.AutomaticSize.Y,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = C.dim,
	TextSize = 15,
	TextStrokeTransparency = 0.5,
	Font = Enum.Font.GothamMedium,
})

-- ── Job panel ──────────────────────────────────────────────────────────────
-- Top centre (the first entry of the top stack): the job and the clock, what to do now (big), the stop and the
-- person, the cargo (in your hands, at this stop, in the vehicle) and the cargo's condition.

local jobPanel: any, jobStroke: any, jobTitle: any, jobTimer: any, jobStep: any, jobInfo: any, conditionBack: any, conditionFill: any, conditionText: any, LOAD_H: any, loadFill: any, loadBack: any, loadText: any, cargoSignature: any, renderCargoRow: any
do -- (its own block: the locals below stay out of the 200-register limit)
jobPanel = Ui.panel(Hud.topSlot("job"), UDim2.new(1, 0, 0, 0), UDim2.new(), nil)
jobPanel.Name = "JobPanel"
jobPanel.AutomaticSize = Enum.AutomaticSize.Y
jobPanel.Visible = false
Ui.padding(jobPanel, 12)
jobStroke = Ui.stroke(jobPanel, C.yellow, 2)
Ui.list(jobPanel, true, 6)
local jobHeader = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, jobPanel)
jobTitle = Ui.label(jobHeader, "", UDim2.new(1, -80, 1, 0), { TextSize = 15, TextColor3 = C.dim, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
jobTimer = Ui.label(jobHeader, "", UDim2.new(0, 80, 1, 0), {
	Position = UDim2.new(1, -80, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 22,
	Font = Enum.Font.GothamBlack,
})
jobStep = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 0), {
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = 2,
	TextSize = 24,
	Font = Enum.Font.GothamBlack,
})
jobInfo = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 18), { LayoutOrder = 3, TextColor3 = C.dim, TextSize = 15, Font = Enum.Font.GothamMedium })
local cargoRow = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 4, Visible = false }, jobPanel)
Ui.list(cargoRow, false, 6)
conditionBack, conditionFill = Ui.bar(jobPanel, UDim2.new(1, 0, 0, 8), C.yellow)
conditionBack.LayoutOrder = 5
conditionText = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 0), {
	AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6,
	TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = C.dim, ZIndex = 2,
})

-- Loading / unloading / boarding bar under the middle of the screen (layout() keeps it over the bottom panels).
LOAD_H = 26
loadBack, loadFill = Ui.bar(gui, UDim2.fromOffset(340, LOAD_H), C.blue)
scaled(loadBack)
loadBack.AnchorPoint = Vector2.new(0.5, 0.5)
loadBack.Position = UDim2.fromScale(0.5, 0.62)
loadBack.Visible = false
loadText = Ui.label(loadBack, "", UDim2.fromScale(1, 1), { TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, ZIndex = 2, Font = Enum.Font.GothamBlack })

cargoSignature = ""

-- The cargo chips: what you hold, the pieces of this stop (done ones bright), how many ride in the vehicle.
function renderCargoRow()
	local handling = job and job.handling
	local total = job and job.total
	local show = job ~= nil and type(total) == "number" and total > 0 and handling ~= "drive"
	local holding = myCarrying()
	local kind = jobItemKind()
	local needed = if show then tonumber(job.needed) or 0 else 0
	local done = if show then tonumber(job.delivered) or 0 else 0
	local lost = if show then tonumber(job.lost) or 0 else 0
	local aboard = inVehicle()
	local signature = `{show}|{holding}|{kind}|{needed}|{done}|{lost}|{aboard}|{total}|{handling}|{job and job.stage}`
	if signature == cargoSignature then
		return
	end
	cargoSignature = signature
	cargoRow.Visible = show
	Ui.clear(cargoRow)
	if not show then
		return
	end
	local info = jobCargo() -- the job's cargo (its kind is `kind`)
	local byHand = handling == "carry" or handling == "lead"
	if holding then
		local held = heldInfo(holding)
		iconChip(cargoRow, held.art, held.icon, `{if holding == "horse" then "Leading a" else "Holding"} {held.one}`, C.yellow, Color3.new(0, 0, 0)).LayoutOrder = 1
	elseif byHand then
		Ui.chip(cargoRow, "✋ Hands free", C.panelLight, C.dim).LayoutOrder = 1
	end
	if needed > 0 then
		local pickup = job.stage == "pickup"
		local stop = Ui.make("Frame", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.panelLight, LayoutOrder = 2 }, cargoRow)
		Ui.corner(stop, 6)
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, stop)
		Ui.list(stop, false, 2)
		Ui.label(stop, if pickup then "Loaded " else "Delivered ", UDim2.new(0, 0, 1, 0), { AutomaticSize = Enum.AutomaticSize.X, TextSize = 13, TextColor3 = C.dim, TextWrapped = false, LayoutOrder = 0 })
		for i = 1, math.min(needed, 8) do
			Ui.icon(stop, info.art, info.icon, UDim2.new(0, 20, 1, 0), {
				LayoutOrder = i,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = if i <= done then 0 else 0.7,
				ImageTransparency = if i <= done then 0 else 0.7,
			})
		end
		Ui.label(stop, ` {math.min(done, needed)}/{needed}`, UDim2.new(0, 0, 1, 0), {
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = 14,
			TextWrapped = false,
			TextColor3 = if done >= needed then C.green else C.text,
			LayoutOrder = 99,
		})
	end
	if aboard then
		Ui.chip(cargoRow, `🚚 {aboard} in the {vehicleWord()}`).LayoutOrder = 3
	end
	if total ~= needed then
		-- More stops: how much the whole job moves.
		Ui.chip(cargoRow, `{total} in all`, Color3.fromRGB(30, 33, 38), C.dim).LayoutOrder = 4
	end
	if lost > 0 then
		Ui.chip(cargoRow, `⚠ {lost} lost`, Color3.fromRGB(90, 28, 28), Color3.fromRGB(255, 150, 140)).LayoutOrder = 5
	end
end
end

-- ── The way to the target ──────────────────────────────────────────────────
-- The park circle (a ring and a light beam) and, on foot during a carry step, a small ring at the pile / the
-- person with a thin beam over their head; a floating label and an arrow (over the car, or over your head on foot).

local beacon: any, ring: any, pileRing: any, label: any, labelText: any, HIDDEN: any, PICKUP_COLOR: any, PILE_COLOR: any, UPRIGHT: any, hideGuide: any, placeGuide: any, pointArrow: any, GPS_COLOR: any, gps: any, myPosition: any, footTarget: any
do -- (its own block: the locals below stay out of the 200-register limit)
local guide = Instance.new("Folder")
guide.Name = "DeliveryGuide"
guide.Parent = workspace

local function guidePart(name: string, size: Vector3, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = C.yellow
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
local labelGui = Ui.make("BillboardGui", { Size = UDim2.fromOffset(260, 60), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 100000 }, label)
labelText = Ui.label(labelGui, "", UDim2.fromScale(1, 1), {
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = C.yellow,
	TextSize = 20,
	Font = Enum.Font.GothamBlack,
	TextStrokeTransparency = 0.2,
})
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
	labelText.TextColor3 = color
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
	BackgroundColor3 = C.panel,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Visible = false,
	ZIndex = 4,
}, Hud.topSlot("levelup"))
local levelUpPop = Ui.make("UIScale", { Scale = 1 }, levelUpFrame)
Ui.corner(levelUpFrame, 10)
Ui.stroke(levelUpFrame, C.yellow, 2)
Ui.padding(levelUpFrame, 12)
Ui.list(levelUpFrame, true, 4, Enum.HorizontalAlignment.Center)
Ui.label(levelUpFrame, "⬆  LEVEL UP!", UDim2.new(1, 0, 0, 40), {
	TextSize = 36,
	Font = Enum.Font.GothamBlack,
	TextColor3 = C.yellow,
	TextXAlignment = Enum.TextXAlignment.Center,
	LayoutOrder = 1,
})
local levelUpTitle = Ui.label(levelUpFrame, "", UDim2.new(1, 0, 0, 26), {
	AutomaticSize = Enum.AutomaticSize.Y, -- a long rank wraps on a narrow stack
	TextSize = 22,
	Font = Enum.Font.GothamBlack,
	TextXAlignment = Enum.TextXAlignment.Center,
	LayoutOrder = 2,
})
local levelUpUnlocks = Ui.label(levelUpFrame, "", UDim2.new(1, 0, 0, 0), {
	AutomaticSize = Enum.AutomaticSize.Y,
	TextSize = 15,
	Font = Enum.Font.GothamMedium,
	TextColor3 = C.green,
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
	levelUpUnlocks.Text = if #unlocked > 0 then `Unlocked: {table.concat(unlocked, " · ")}` else "Better jobs, cars and guns wait on the next levels."
	levelUpStamp += 1
	local mine = levelUpStamp
	levelUpFrame.Visible = true
	levelUpPop.Scale = 0.8
	local pop = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(levelUpFrame, pop, { GroupTransparency = 0 }):Play()
	TweenService:Create(levelUpPop, pop, { Scale = 1 }):Play()
	-- The XP bar and the LV chip flash white.
	xpFill.BackgroundColor3 = Color3.new(1, 1, 1)
	levelChip.BackgroundColor3 = Color3.new(1, 1, 1)
	TweenService:Create(xpFill, TweenInfo.new(1.2), { BackgroundColor3 = C.yellow }):Play()
	TweenService:Create(levelChip, TweenInfo.new(1.2), { BackgroundColor3 = C.yellow }):Play()
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

-- The LV chip, the rank, the XP bar; a level-up flashes and the open shop shows what it unlocked.
function refreshLevel()
	local xp = myXp()
	if xp == nil then
		levelChip.Text = "LV 1"
		rankLabel.Text = Levels.rank(1)
		xpLabel.Text = ""
		xpFill.Size = UDim2.fromScale(0, 1)
		return
	end
	local level = Levels.levelFor(xp)
	levelChip.Text = `LV {level}`
	rankLabel.Text = Levels.rank(level)
	if level >= Config.Levels.MaxLevel then
		xpLabel.Text = "MAX"
	else
		local from = Levels.xpFor(level)
		xpLabel.Text = `{math.floor(xp - from)}/{Levels.xpFor(level + 1) - from} XP`
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
local CALL_COLOR = C.blue
local CALL_DONE_SHOWN = 3 -- seconds "Your car is here" stays
local CALL_STALE = 20

local callLine = Ui.panel(Hud.topSlot("carcall"), UDim2.new(0.78, 0, 0, 42), UDim2.new(), nil)
callLine.Name = "CarCall"
callLine.Visible = false
local callStroke = Ui.stroke(callLine, CALL_COLOR, 1.5)
local callText = Ui.label(callLine, "", UDim2.new(1, -110, 0, 26), {
	Position = UDim2.fromOffset(12, 4),
	TextSize = 17,
	Font = Enum.Font.GothamBlack,
	TextWrapped = false,
	TextTruncate = Enum.TextTruncate.AtEnd,
})
local callDistance = Ui.label(callLine, "", UDim2.fromOffset(90, 26), {
	Position = UDim2.new(1, -102, 0, 4),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 15,
	TextColor3 = C.dim,
	Font = Enum.Font.GothamMedium,
	TextWrapped = false,
})
local callBack, callFill = Ui.bar(callLine, UDim2.new(1, -24, 0, 5), CALL_COLOR)
callBack.Position = UDim2.new(0, 12, 1, -10)

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
local MARKER_COLOR = CALL_COLOR:Lerp(Color3.new(1, 1, 1), 0.35)
local markerText = Ui.label(callMarker, "", UDim2.new(1, 0, 0, 24), {
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 19,
	Font = Enum.Font.GothamBlack,
	TextColor3 = MARKER_COLOR,
	TextStrokeTransparency = 0.2,
	TextWrapped = false,
})
local markerSub = Ui.label(callMarker, "", UDim2.new(1, 0, 0, 16), {
	Position = UDim2.fromOffset(0, 24),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 14,
	Font = Enum.Font.GothamBold,
	TextColor3 = C.text,
	TextStrokeTransparency = 0.3,
	TextWrapped = false,
})
Ui.label(callMarker, "▼", UDim2.new(1, 0, 0, 22), {
	Position = UDim2.fromOffset(0, 42),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 20,
	Font = Enum.Font.GothamBlack,
	TextColor3 = MARKER_COLOR,
	TextStrokeTransparency = 0.2,
})

local callLoop = false

local function carPart(car: Model?): BasePart?
	if not car or not car.Parent then
		return nil
	end
	return car.PrimaryPart or car:FindFirstChildWhichIsA("BasePart")
end

local function setCarButton(text: string)
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
		callStroke.Color = if current.doneText then C.yellow else C.green
		callFill.BackgroundColor3 = if current.doneText then C.yellow else C.green
		callFill.Size = UDim2.fromScale(1, 1)
		markerText.Text = "🚗  YOUR CAR"
		markerSub.Text = if distance then `here · {distance} m` else "here"
		setCarButton("CAR")
	else
		local left = math.max(0, math.ceil(current.arriveAt - now))
		callText.Text = if left > 0 then `🚗  Your car is on the way · {left} s` else "🚗  Your car is almost here"
		callStroke.Color = CALL_COLOR
		callFill.BackgroundColor3 = CALL_COLOR
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
-- again when the screen changes, the weapon bar grows a row, or the ADMIN button comes or goes. The regions:
--
--   COMPUTER (keyboard and mouse)                       TOUCH, held sideways (phone or tablet, no keyboard)
--   ┌──────────────────────────────────────────────┐    ┌──────────────────────────────────────────────┐
--   │ chat     ┌── top stack ──┐            ADMIN  │    │ money   ┌── top stack ──┐          ADMIN    │
--   │ (Roblox) │ job / crew    │         ┌───────┐ │    │ minimap │ job / crew    │       ┌────┬────┐ │
--   │          │ car call      │         │ JOBS  │ │    │         │ car call      │       │JOBS│TOP │ │
--   │          │ level up      │         │ MAP   │ │    │         │ level up      │       │ …  │ …  │ │
--   │          │ toasts        │         │ …     │ │    │         │ toasts        │       └────┴────┘ │
--   │          └───────────────┘         │ESTATE │ │    │         └───────────────┘                  │
--   │ money          (loading bar)       └───────┘ │    │ (thumb-     (loading bar)           (FIRE)  │
--   │ minimap        hint           weapon bar     │    │  stick)   hint        weapon bar            │
--   │                car panel      hotbar         │    │           car panel   hotbar        (jump)  │
--   └──────────────────────────────────────────────┘    └──────────────────────────────────────────────┘
--
--   TOUCH, held upright: money and minimap top left, the buttons (two columns) top right, the top stack under them;
--   at the bottom one column (hint, weapon bar, hotbar, car panel) left of FIRE and the jump button.
--
--   * Margins 16 px, gaps 8 px. The ADMIN button (client/AdminPanel.luau, 90 × 32 at 16 px from the right, 56 from
--     the top, unscaled) keeps the top right corner (down to ADMIN_BOTTOM) while it shows (admins, Studio).
--   * Left: money + minimap, one column (LEFT_W × LEFT_H × S): bottom left on a computer (the chat is top left),
--     top left on touch (the thumbstick is bottom left).
--   * Bottom right, computer: the hotbar in the corner, the weapon bar on it (one or two rows of guns). Touch: the
--     FIRE button just over Roblox's jump button (70 px at 95 / 90 px from the corner on a small screen, 120 px at
--     170 / 210 px on a big one).
--   * Bottom centre, computer: the car panel centred between the minimap and the bars (smaller when it has to), the
--     hint over it. Touch: the car panel with the hint over it and, beside it (sideways) or over it (upright), the
--     weapon bar over the hotbar; moved left of FIRE / the jump button, or over them when that is not enough.
--   * The buttons: right edge, from the top (under ADMIN) down to the weapon bar (computer) or FIRE (touch). One
--     column when it fits at a scale of at least 0.6 (computer) or 0.7 (touch: the buttons are 100 × 48 there and
--     never smaller than 0.8 of that), else two columns, else four (two rows). A computer centres them in the room.
--   * Top stack: centred, TOP_W × S wide (narrower down to TOP_MIN_W before it gets smaller), between the minimap (touch) and the buttons / ADMIN, and as tall as the
--     room over the bottom panels allows (TOP_EST_H: a two-line job panel, the mission banner and the car call line, with the loading
--     bar's room under it); smaller when it has to. On a touch screen with no room beside the buttons (upright) it
--     goes under the minimap and the buttons.
--   * The loading bar: at 62 % of the height, under the top stack and over the panels at the bottom.

local MARGIN = 16
local GAP = 8
local ADMIN_BOTTOM = 96 -- client/AdminPanel.luau: the ADMIN button at (1, -16, 0, 56), 90 × 32, unscaled
local ADMIN_LEFT = 16 + 90 + GAP
local BUTTON_W, BUTTON_H = 52, 52
local TOUCH_BUTTON_W, TOUCH_BUTTON_H = 62, 62
local BUTTON_GAP = 8
local TOUCH_BUTTON_MIN = 0.8
local TOP_EST_H = 320 -- the top stack's usual height (unscaled): a two-line job panel, the mission banner (up to 80) and the car call line
local TOP_MIN_W = 400 -- a narrow span first makes the top stack narrower (down to this), then smaller
local HINT_LINES = if touchLayout then 2 else 1 -- the hint may wrap (upward) this far

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

-- The columns of buttons to try, the first that fits wins.
local function columnChoices(width: number, height: number): { number }
	if touchLayout and width < height then
		return { 2, 1, 4 }
	end
	return { 1, 2, 4 }
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

	-- Left: money and the minimap.
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

	-- Bottom right: the bars (computer), or FIRE over the jump button (touch). cornerLeft: where that corner begins.
	local admin = adminButtonShown()
	local rightTop = if admin then ADMIN_BOTTOM else MARGIN
	local rightBottom: number
	local cornerLeft: number
	local fireTop = H
	local fireSize = FIRE_SIZE * S
	local weaponH = weaponBar.Size.Y.Offset
	setScale(fire, S)
	setScale(hotbar, S)
	setScale(weaponBar, S)
	fire.AnchorPoint = Vector2.new(1, 1)
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
		fireTop = fireBox.y0
		rightBottom = fireBox.y0 - GAP
		cornerLeft = math.min(jump.x0, fireBox.x0) - GAP
	else
		hotbar.AnchorPoint = Vector2.new(1, 1)
		hotbar.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
		local hotTop = H - MARGIN - HOTBAR_H * S
		weaponBar.AnchorPoint = Vector2.new(1, 1)
		weaponBar.Position = UDim2.new(1, -MARGIN, 0, hotTop - GAP)
		local weaponTop = hotTop - GAP - weaponH * S
		table.insert(below, box(W - MARGIN - BAR_W * S, weaponTop, W - MARGIN, H - MARGIN))
		rightBottom = weaponTop - 12
		cornerLeft = W - MARGIN - BAR_W * S
		if UserInputService.TouchEnabled then
			-- A touch screen with a keyboard: FIRE left of the bars.
			fire.Position = UDim2.fromOffset(cornerLeft - 12, H - MARGIN)
			local fireBox = box(cornerLeft - 12 - fireSize, H - MARGIN - fireSize, cornerLeft - 12, H - MARGIN)
			table.insert(below, fireBox)
			cornerLeft = fireBox.x0
		end
	end

	-- Bottom centre: the car panel with the hint over it (touch: and the bars).
	local carScale = S
	local carX: number
	local carBottom: number
	local hintWidth: number
	local hintBottom: number? = nil -- nil: just over the car panel
	if touchLayout then
		local carW, barW = CAR_W * S, BAR_W * S
		local sideBySide = W >= H
		local groupW = if sideBySide then carW + GAP + barW else math.max(carW, barW)
		local cx = W / 2
		if cx + groupW / 2 > cornerLeft then
			-- Left of FIRE and the jump button …
			cx = math.max(MARGIN + groupW / 2, cornerLeft - groupW / 2)
		end
		local bottom = H - GAP
		if cx + groupW / 2 > cornerLeft then
			-- … or over them.
			bottom = fireTop - GAP
		end
		local barX: number
		local barBottom: number
		if sideBySide then
			carX = cx - groupW / 2 + carW / 2
			barX = cx + groupW / 2 - barW / 2
			barBottom = bottom
			hintWidth = carW
		else
			carX, barX = cx, cx
			barBottom = bottom - CAR_H * S - 6
			hintWidth = groupW
		end
		carBottom = bottom
		hotbar.AnchorPoint = Vector2.new(0.5, 1)
		hotbar.Position = UDim2.fromOffset(barX, barBottom)
		local weaponBottom = barBottom - HOTBAR_H * S - 6
		weaponBar.AnchorPoint = Vector2.new(0.5, 1)
		weaponBar.Position = UDim2.fromOffset(barX, weaponBottom)
		local weaponTop = weaponBottom - weaponH * S
		table.insert(below, box(barX - barW / 2, weaponTop, barX + barW / 2, barBottom))
		if not sideBySide then
			-- Upright: the hint goes over the weapon bar.
			hintBottom = weaponTop - 4
		end
	else
		local spanLeft, spanRight = left.x1 + 12, cornerLeft - 12
		carScale = math.clamp((spanRight - spanLeft) / CAR_W, 0.4, S)
		local half = CAR_W * carScale / 2
		carX = math.clamp(W / 2, spanLeft + half, math.max(spanLeft + half, spanRight - half))
		carBottom = H - 18
		hintWidth = math.max(half * 2, 2 * math.min(carX - spanLeft, spanRight - carX))
	end
	setScale(carPanel, carScale)
	carPanel.AnchorPoint = Vector2.new(0.5, 1)
	carPanel.Position = UDim2.fromOffset(carX, carBottom)
	local carTop = carBottom - CAR_H * carScale
	table.insert(below, box(carX - CAR_W * carScale / 2, carTop, carX + CAR_W * carScale / 2, carBottom))
	local hintAt = hintBottom or carTop - 6
	local hintSize = math.max(11, math.floor(15 * S + 0.5))
	hint.TextSize = hintSize
	hint.Size = UDim2.fromOffset(hintWidth, 0)
	hint.Position = UDim2.fromOffset(carX, hintAt)
	table.insert(below, box(carX - hintWidth / 2, hintAt - HINT_LINES * (hintSize + 3), carX + hintWidth / 2, hintAt))

	-- The buttons.
	local bw = if touchLayout then TOUCH_BUTTON_W else BUTTON_W
	local bh = if touchLayout then TOUCH_BUTTON_H else BUTTON_H
	local base = if touchLayout then math.max(S, TOUCH_BUTTON_MIN) else S
	local minScale = if touchLayout then 0.7 else 0.6
	local room = math.max(0, rightBottom - rightTop)
	local count = #BUTTONS
	local function gridSize(columns: number): (number, number)
		local rows = math.ceil(count / columns)
		return columns * bw + (columns - 1) * BUTTON_GAP, rows * bh + (rows - 1) * BUTTON_GAP
	end
	local columns, buttonScale = 0, 0
	for _, choice in columnChoices(W, H) do
		local _, h = gridSize(choice)
		local fit = math.min(base, room / h)
		if fit >= minScale then
			columns, buttonScale = choice, fit
			break
		end
	end
	if columns == 0 then
		-- Very little room: the flattest grid, as big as it fits.
		local _, h = gridSize(4)
		columns, buttonScale = 4, math.clamp(room / h, 0.45, base)
	end
	local gw, gh = gridSize(columns)
	buttonGrid.Size = UDim2.fromOffset(gw, gh)
	buttonLayout.CellSize = UDim2.fromOffset(bw, bh)
	buttonLayout.CellPadding = UDim2.fromOffset(BUTTON_GAP, BUTTON_GAP)
	if columns >= 4 then
		-- Rows: JOBS MISSIONS MAP BAG / CAR TOP CREW ESTATE / SOUND.
		buttonLayout.FillDirection = Enum.FillDirection.Horizontal
		buttonLayout.StartCorner = Enum.StartCorner.TopLeft
		buttonLayout.FillDirectionMaxCells = columns
	else
		-- Columns from the screen's edge: JOBS MISSIONS MAP BAG CAR | TOP CREW ESTATE SOUND.
		buttonLayout.FillDirection = Enum.FillDirection.Vertical
		buttonLayout.StartCorner = Enum.StartCorner.TopRight
		buttonLayout.FillDirectionMaxCells = math.ceil(count / columns)
	end
	setScale(buttonGrid, buttonScale)
	-- On a computer the grid sits at the bottom of its room (on the weapon bar), clear of Roblox's player list
	-- (leaderstats) in the top-right corner.
	local gridTop = if touchLayout then rightTop else math.max(rightTop, rightBottom - gh * buttonScale)
	buttonGrid.AnchorPoint = Vector2.new(1, 0)
	buttonGrid.Position = UDim2.fromOffset(W - MARGIN, gridTop)
	local grid = box(W - MARGIN - gw * buttonScale, gridTop, W - MARGIN, gridTop + gh * buttonScale)

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
	local gridHigh = grid.y0 < H * 0.45
	if gridHigh then
		spanR = math.min(spanR, grid.x0 - GAP)
	end
	if admin then
		spanR = math.min(spanR, W - ADMIN_LEFT)
	end
	local topScale, topX, topWidth = fit(topY, spanL, spanR)
	if touchLayout and topScale < S * 0.8 then
		-- No room beside the minimap and the buttons (upright): under them, the whole width.
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

-- ── Updates ────────────────────────────────────────────────────────────────

function Hud.setState(newState: any)
	state = newState
	moneyLabel.Text = Ui.money(state.money)
	statsLabel.Text = `Deliveries {state.deliveries} · Kills {state.kills}`
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
	jobPanel.Visible = job ~= nil
	cargoSignature = ""
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
	local pickup = job.stage == "pickup"
	local stageColor = if pickup then PICKUP_COLOR else C.yellow
	local modifier = if job.modifier then `  [{job.modifier.name}]` else ""
	local name = if job.jobType then job.jobType.name else `{job.cargo} → {job.customer}`
	jobTitle.Text = `{string.rep("★", job.stars)}  {name}{modifier}`
	jobStep.Text = if type(job.step) == "string" and job.step ~= "" then job.step else job.stopLabel
	jobStep.TextColor3 = stageColor
	jobStroke.Color = stageColor
	conditionFill.Size = UDim2.fromScale(math.clamp(job.condition, 0, 1), 1)
	conditionFill.BackgroundColor3 = if job.condition > 0.6 then C.yellow elseif job.condition > 0.3 then Color3.fromRGB(255, 140, 40) else C.red
	local wave = if type(job.wave) == "number" and job.wave > 0 then `  ·  Wave {job.wave}` else ""
	conditionText.Text = `Cargo {math.floor(job.condition * 100 + 0.5)}%  ·  Pay {Ui.money(job.pay)}  ·  Kills {job.kills}{wave}`
	renderCargoRow()
	MapView.setTarget(job.position)
	-- Loading / unloading / boarding progress.
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

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		return
	end
	-- The car.
	local car = Drive.myCar()
	local seatedIn, driving = Drive.seatedCar()
	if car then
		local def = Economy.findCar(tostring(car:GetAttribute("CarId")))
		carName.Text = if def then def.name else "Car"
		local health = (car:GetAttribute("Health") or 0) :: number
		local maxHealth = math.max(1, (car:GetAttribute("MaxHealth") or 1) :: number)
		local share = math.clamp(health / maxHealth, 0, 1)
		healthFill.Size = UDim2.fromScale(share, 1)
		healthFill.BackgroundColor3 = if share > 0.5 then C.green elseif share > 0.25 then Color3.fromRGB(255, 160, 40) else C.red
		healthText.Text = `{math.ceil(health)} / {math.floor(maxHealth)}`
		local chassis = car.PrimaryPart
		local v = if chassis then chassis.AssemblyLinearVelocity else Vector3.zero
		speedLabel.Text = (if Drive.boosting() then "⚡ " else "") .. `{math.floor(Vector3.new(v.X, 0, v.Z).Magnitude)} km/h`
	else
		carName.Text = "No car"
		speedLabel.Text = ""
		healthFill.Size = UDim2.fromScale(0, 1)
		healthText.Text = "Press CAR to get one"
	end

	-- Got in / out, or the car gun changed: the weapon bar shows what fires now.
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
	if holding then
		-- G is the server's "Put down" / "Let go" prompt key (server/Cargo.luau); touch screens tap the prompt.
		local key = if touch then "tap PUT DOWN" else "G puts it down"
		hint.Text = if holding == "horse" then `Leading a horse: no gun, no sprint · {if touch then "tap LET GO" else "G lets go"}`
			else `Hands full: no gun, no sprint · E loads / hands over · {key} to shoot`
		hint.TextColor3 = C.yellow
	elseif inShop then
		hint.Text = `{Map.Shops[inShop].name}: walk to the counter and press E`
		hint.TextColor3 = C.green
	elseif seatedIn and not driving then
		local gun = if state then Economy.findWeapon(state.weapon) else nil
		hint.Text = if gun and not gun.oneHanded then `Riding along: the {gun.name} is too big for the window · Q to a pistol, revolver or SMG`
			else "Riding along: right mouse aims, left mouse shoots out of the window · Space gets out"
		hint.TextColor3 = Color3.fromRGB(140, 210, 255)
	elseif safe and not job then
		hint.Text = "SAFE ZONE · shops around the depot · JOBS to start a delivery"
		hint.TextColor3 = C.green
	elseif not car then
		hint.Text = "Press CAR to call your car"
		hint.TextColor3 = C.dim
	elseif not seatedIn and not job then
		hint.Text = if touch then "On foot: FIRE shoots · E at your car to drive" else "On foot: right mouse aims, left mouse shoots · E at your car to drive"
		hint.TextColor3 = C.dim
	else
		hint.Text = ""
	end
	if inShop ~= lastShop then
		lastShop = inShop
		if shop.frame.Visible then
			renderShop()
		end
	end

	-- The job.
	if job then
		local left = job.endsAt - workspace:GetServerTimeNow()
		jobTimer.Text = Ui.clock(left)
		jobTimer.TextColor3 = if left < 15 then C.red else C.text
		renderCargoRow()
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
			placeGuide(circle, if pickup then PICKUP_COLOR else C.yellow)
		end
		local person = if type(job.person) == "string" and job.person ~= "" then job.person else nil
		local position = myPosition()
		if position then
			local flat = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
			local distance = math.floor(flat.Magnitude)
			jobInfo.Text = `Stop {job.stopIndex}/{job.stopCount}` .. (if person then `  ·  👤 {person}` else "") .. `  ·  {distance} m`
			labelText.Text = if footText then `{footText}\n{distance} m` else (if pickup then "PICK UP" else string.upper(person or job.customer)) .. `\n{distance} m`
			local chassis = if seatedIn then seatedIn.PrimaryPart else nil
			if chassis then
				pointArrow(chassis.Position + Vector3.new(0, 11, 0), flat, 1)
			elseif root then
				pointArrow(root.Position + Vector3.new(0, 4.5, 0), flat, 0.6)
			end
		end
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
	-- Keys.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not gui.Enabled or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.M then
			MapView.toggle()
		elseif key == Enum.KeyCode.J then
			if jobs.frame.Visible then
				jobs.frame.Visible = false
			else
				openJobs()
			end
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
