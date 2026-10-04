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

-- Every top-level panel gets a UIScale so the interface fits phones too.
local scales: { any } = {}
local function scaled(frame: any): any
	table.insert(scales, Ui.make("UIScale", {}, frame))
	return frame
end
local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local value = math.clamp(math.min(size.X / 1150, size.Y / 680), 0.55, 1.1)
	for _, s in scales do
		s.Scale = math.max(value, tonumber(s:GetAttribute("MinimumScale")) or 0)
	end
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
local touchLayout = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
-- Money and the minimap share one column (one scale), so they can never overlap.
local MONEY_HEIGHT = 110 -- money, the stats, the level and the XP bar
local leftStack = scaled(Ui.make("Frame", {
	Name = "LeftStack",
	Size = UDim2.fromOffset(230, MONEY_HEIGHT + 8 + 230),
	Position = if touchLayout then UDim2.fromOffset(16, 16) else UDim2.new(0, 16, 1, -16),
	AnchorPoint = if touchLayout then Vector2.zero else Vector2.new(0, 1),
	BackgroundTransparency = 1,
}, gui))
Ui.list(leftStack, true, 8)
local moneyPanel = Ui.panel(leftStack, UDim2.fromOffset(230, MONEY_HEIGHT), UDim2.new())
moneyPanel.LayoutOrder = 1
Ui.padding(moneyPanel, 8)
local moneyLabel = Ui.label(moneyPanel, "$0", UDim2.new(1, 0, 0, 32), { TextColor3 = C.money, TextSize = 30, Font = Enum.Font.GothamBlack })
local statsLabel = Ui.label(moneyPanel, "", UDim2.new(1, 0, 0, 16), { Position = UDim2.fromOffset(0, 34), TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })
-- The driver level: a LV chip and the rank name, under them the XP bar and the XP into this level.
local levelRow = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 54), BackgroundTransparency = 1, ClipsDescendants = true }, moneyPanel)
Ui.list(levelRow, false, 6)
local levelChip = Ui.chip(levelRow, "LV 1", C.yellow, Color3.new(0.04, 0.05, 0.04))
levelChip.Font = Enum.Font.GothamBlack
levelChip.TextSize = 13
levelChip.LayoutOrder = 1
local rankLabel = Ui.label(levelRow, "", UDim2.new(0, 0, 1, 0), {
	AutomaticSize = Enum.AutomaticSize.X,
	TextWrapped = false,
	TextSize = 13,
	TextColor3 = C.yellow,
	LayoutOrder = 2,
})
local xpLabel = Ui.label(moneyPanel, "", UDim2.fromOffset(84, 16), {
	Position = UDim2.new(1, -84, 0, 77),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 12,
	TextColor3 = C.dim,
	Font = Enum.Font.GothamMedium,
	TextWrapped = false,
})
local xpBack, xpFill = Ui.bar(moneyPanel, UDim2.new(1, -90, 0, 7), C.yellow)
xpBack.Position = UDim2.fromOffset(0, 82)

-- ── Toasts ─────────────────────────────────────────────────────────────────

local toasts = scaled(Ui.make("Frame", {
	Size = UDim2.fromOffset(520, 200),
	Position = UDim2.new(0.5, 0, 0, 200),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
}, gui))
Ui.list(toasts, true, 6, Enum.HorizontalAlignment.Center)

function Hud.toast(text: string)
	local label = Ui.label(toasts, text, UDim2.fromOffset(500, 34), {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.25,
		BackgroundColor3 = C.panel,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = 18,
	})
	Ui.corner(label, 8)
	task.delay(3, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.45)
		label:Destroy()
	end)
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

local function closeWindows()
	for _, w in windows do
		w.Visible = false
	end
	Leaderboard.close()
end
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

local jobs = window("JOB BOARD", Vector2.new(600, 470))
local offersRemote = Net.get("RequestOffers")

local function jobsMessage(text: string)
	Ui.clear(jobs.body)
	Ui.label(jobs.body, text, UDim2.new(1, -10, 0, 60), { TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center })
end

local function openJobs()
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

local STAR_COLORS = { C.green, C.yellow, C.red, Color3.fromRGB(200, 80, 255) }

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
			local lock = if state.weapons[def.id] or def.earned then nil else lockedAt(def.level)
			cardText(c, def.name, gunStats(def) .. (if def.oneHanded then " · One-handed" else "") .. (if lock then ` · from level {lock}` else ""), def.description, cardIcon(c, Icons.weapon(def.id), nil, 17))
			if state.weapon == def.id then
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
				local c = card(shop.body, 70, order + 1)
				local swatchColor = if def.color then Color3.fromRGB(def.color[1], def.color[2], def.color[3]) elseif carDef then Color3.fromRGB(carDef.color[1], carDef.color[2], carDef.color[3]) else C.grey
				local swatch = Ui.make("Frame", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(12, 13), BackgroundColor3 = swatchColor }, c)
				Ui.corner(swatch, 8)
				Ui.stroke(swatch, Color3.new(0, 0, 0), 2)
				Ui.label(c, def.name, UDim2.new(1, -260, 0, 26), { Position = UDim2.fromOffset(70, 8), TextSize = 20, Font = Enum.Font.GothamBlack })
				Ui.label(c, if state.paints[def.id] then "Owned" else Ui.money(def.price), UDim2.new(1, -260, 0, 20), { Position = UDim2.fromOffset(70, 36), TextColor3 = C.yellow, TextSize = 15 })
				if current == def.id then
					cardButton(c, "ON YOUR CAR", C.grey, false, function() end).Position = UDim2.new(1, -162, 0, 15)
				elseif state.paints[def.id] then
					cardButton(c, "APPLY", C.blue, here, function()
						Net.get("Paint"):FireServer(def.id)
					end).Position = UDim2.new(1, -162, 0, 15)
				else
					cardButton(c, `BUY {Ui.money(def.price)}`, C.green, here and money >= def.price, function()
						Net.get("Paint"):FireServer(def.id)
					end).Position = UDim2.new(1, -162, 0, 15)
				end
			end
		end
	end
end

-- ── Employers ──────────────────────────────────────────────────────────────

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

-- ── Backpack ───────────────────────────────────────────────────────────────

local backpack = window("BACKPACK", Vector2.new(640, 500))
local backpackTab = "items"
local renderBackpack: () -> ()

local function useItem(id: string)
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
				cardText(c, def.name, gunStats(def) .. (if def.oneHanded then " · One-handed" else ""), def.description, cardIcon(c, Icons.weapon(def.id), nil, 17))
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

local function toggleBackpack()
	if backpack.frame.Visible then
		backpack.frame.Visible = false
	else
		closeWindows()
		backpack.frame.Visible = true
		renderBackpack()
	end
end

-- ── Delivery result ────────────────────────────────────────────────────────

local result = window("DELIVERY", Vector2.new(460, 540))

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
		local crewBonus = tonumber(r.crewBonus) or 0
		if riders > 0 and crewBonus > 0 then
			line(`Crew bonus ({riders} in the crew)`, "+" .. Ui.money(crewBonus), nil, 9)
		elseif riders > 0 and crewBonus < 0 then
			line(`Shared with the crew ({riders})`, "-" .. Ui.money(-crewBonus), C.dim, 9)
		end
		line("TOTAL", Ui.money(r.total), C.yellow, 10)
		local employer = r.employer
		if employer then
			line(`{employer.name}: {employer.done} jobs done`, nil, Color3.fromRGB(255, 200, 60), 11)
			-- The next reward of that employer (the gun comes first, then the vehicle).
			local done = tonumber(employer.done) or 0
			local gunAt = tonumber(employer.weaponAt)
			local nextUp = if employer.weapon and gunAt and done < gunAt then `{gunAt - done} more for the {employer.weapon}`
				elseif type(employer.needed) == "number" and done < employer.needed and employer.reward ~= "" then `{employer.needed - done} more for the {employer.reward}`
				else nil
			if nextUp then
				line(nextUp, nil, C.dim, 12)
			end
		end
		local newCar = r.unlockedCar or (employer and employer.unlocked)
		if newCar then
			line(`🚚 NEW CAR: the {newCar} is yours!`, nil, C.green, 13)
		end
		if type(r.unlockedWeapon) == "string" then
			local gun = Economy.findWeapon(r.unlockedWeapon)
			line(`🔫 NEW GUN: the {if gun then gun.name else r.unlockedWeapon} is yours!`, nil, C.green, 14)
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

-- ── Buttons ────────────────────────────────────────────────────────────────

local side = scaled(Ui.make("Frame", {
	Size = UDim2.fromOffset(150, 5 * 52 + 4 * 10),
	Position = UDim2.new(1, -16, 0.42, 0),
	AnchorPoint = Vector2.new(1, 0.5),
	BackgroundTransparency = 1,
}, gui))
if touchLayout then
	local sideScale = side:FindFirstChildOfClass("UIScale")
	if sideScale then sideScale:SetAttribute("MinimumScale", 44 / 52) end
end
Ui.list(side, true, 10)
Ui.button(side, "JOBS  [J]", UDim2.fromOffset(150, 52), C.yellow, function()
	if jobs.frame.Visible then
		jobs.frame.Visible = false
	else
		openJobs()
	end
end).TextColor3 = Color3.new(0, 0, 0)
Ui.button(side, "MAP  [M]", UDim2.fromOffset(150, 52), C.panelLight, function()
	MapView.toggle()
end)
Ui.button(side, "BAG  [B]", UDim2.fromOffset(150, 52), C.panelLight, toggleBackpack)
Ui.button(side, "TOP  [L]", UDim2.fromOffset(150, 52), C.panelLight, function()
	Leaderboard.toggle()
end)
Ui.button(side, "CAR", UDim2.fromOffset(150, 52), C.panelLight, function()
	Net.get("SpawnCar"):FireServer()
end)

-- ── Hotbar ─────────────────────────────────────────────────────────────────

-- The inventory bar: items (keys 1-5) and above them the guns you own (Q switches). Bottom right on a computer,
-- bottom centre on a touch screen (the FIRE button is bottom right there).
local hotbar = scaled(Ui.make("Frame", {
	Size = UDim2.fromOffset(5 * 64 + 4 * 8, 64),
	Position = if touchLayout then UDim2.new(0.5, 0, 1, -112) else UDim2.new(1, -16, 1, -16),
	AnchorPoint = if touchLayout then Vector2.new(0.5, 1) else Vector2.new(1, 1),
	BackgroundTransparency = 1,
}, gui))
local weaponBar = scaled(Ui.make("Frame", {
	Size = UDim2.fromOffset(5 * 64 + 4 * 8, 78),
	Position = if touchLayout then UDim2.new(0.5, 0, 1, -184) else UDim2.new(1, -16, 1, -88),
	AnchorPoint = if touchLayout then Vector2.new(0.5, 1) else Vector2.new(1, 1),
	BackgroundTransparency = 1,
}, gui))
local weaponTitle = Ui.label(weaponBar, "WEAPON  ·  Q to switch", UDim2.new(1, 0, 0, 16), {
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 13,
	TextColor3 = C.yellow,
	TextStrokeTransparency = 0.4,
})
local weaponRow = Ui.make("Frame", {
	Size = UDim2.new(1, 0, 0, 58),
	Position = UDim2.fromOffset(0, 18),
	BackgroundTransparency = 1,
}, weaponBar)

local SHORT_NAMES: { [string]: string } = {
	pistol = "PISTOL",
	smg = "SMG",
	shotgun = "SHOTGUN",
	rifle = "RIFLE",
	minigun = "MINIGUN",
	launcher = "LAUNCHER",
	revolver = "REVOLVER",
	carbine = "CARBINE",
	roofmg = "ROOF MG",
	roofminigun = "ROOF MINIGUN",
	rooflauncher = "ROOF LAUNCHER",
}

-- What the weapon bar shows depends on where you are: on foot your guns; driving a car with a car gun that gun; in
-- any other seat your guns, the one-handed ones tagged WINDOW, the two-handed ones greyed out (they do not fire).
local function seatView(): (boolean, Config.CarGunDef?)
	local seatedIn, driving = Drive.seatedCar()
	return seatedIn ~= nil, if seatedIn and driving then Shooting.carGunOf(seatedIn) else nil
end

local function weaponBarKey(): string
	local seated, carGun = seatView()
	return `{seated}|{if carGun then carGun.id else ""}`
end
local shownWeaponBar = ""

-- A small tag in the top left corner of a weapon slot.
local function slotTag(slot: any, text: string, color: Color3)
	local tag = Ui.label(slot, text, UDim2.fromOffset(0, 13), {
		Position = UDim2.fromOffset(3, 3),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = color,
		TextColor3 = Color3.new(0, 0, 0),
		TextSize = 9,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
	Ui.corner(tag, 4)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3) }, tag)
end

local function renderWeapons()
	Ui.clear(weaponRow)
	shownWeaponBar = weaponBarKey()
	if not state then
		return
	end
	local seated, carGun = seatView()
	if carGun then
		-- Driving a car with a car gun: that is what fires.
		weaponTitle.Text = "CAR GUN  ·  on the roof"
		weaponBar.Size = UDim2.fromOffset(5 * 64 + 4 * 8, 18 + 58)
		weaponRow.Size = UDim2.new(1, 0, 0, 58)
		local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1 }, weaponRow)
		Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right }, row)
		local slot = Ui.make("Frame", { Size = UDim2.fromOffset(140, 58), BackgroundColor3 = C.panelLight, BackgroundTransparency = 0.1 }, row)
		Ui.corner(slot, 10)
		Ui.stroke(slot, C.blue, 2.5)
		-- (The car guns have no icon of their own: Icons.weapon gives nil, the emoji stays.)
		Ui.icon(slot, Icons.weapon(carGun.id), if carGun.splash > 0 then "💥" else "🔫", UDim2.new(1, 0, 0, 30), { TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center })
		local name = Ui.label(slot, SHORT_NAMES[carGun.id] or carGun.name, UDim2.new(1, -4, 0, 18), {
			Position = UDim2.fromOffset(2, 34),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(150, 210, 255),
		})
		Ui.make("UITextSizeConstraint", { MaxTextSize = 12 }, name)
		slotTag(slot, "ROOF", Color3.fromRGB(150, 210, 255))
		return
	end
	weaponTitle.Text = if seated then "WEAPON  ·  one-handed out of the window" else "WEAPON  ·  Q to switch"
	local owned: { Config.WeaponDef } = {}
	for _, def in Config.Weapons do
		if state.weapons[def.id] then
			table.insert(owned, def)
		end
	end
	-- Five guns a row; more (the earned ones too) take a second row and the bar grows upward.
	local PER_ROW = 5
	local rowCount = math.max(1, math.ceil(#owned / PER_ROW))
	weaponBar.Size = UDim2.fromOffset(5 * 64 + 4 * 8, 18 + rowCount * 64 - 6)
	weaponRow.Size = UDim2.new(1, 0, 0, rowCount * 64 - 6)
	local rows = {}
	for r = 1, rowCount do
		local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 58), Position = UDim2.fromOffset(0, (r - 1) * 64), BackgroundTransparency = 1 }, weaponRow)
		Ui.make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		rows[r] = row
	end
	for index, def in owned do
		local current = state.weapon == def.id
		-- In a car seat only the one-handed guns fire (out of the window); the others are greyed out.
		local usable = not seated or def.oneHanded == true
		local slot = Ui.make("TextButton", {
			Size = UDim2.fromOffset(if current then 96 else 70, 58),
			BackgroundColor3 = if current and usable then C.panelLight else C.panel,
			BackgroundTransparency = if usable then 0.1 else 0.45,
			Text = "",
			LayoutOrder = index,
			AutoButtonColor = true,
		}, rows[(index - 1) // PER_ROW + 1])
		Ui.corner(slot, 10)
		Ui.stroke(slot, if current and usable then C.yellow else C.grey, if current then 2.5 else 1)
		Ui.icon(slot, Icons.weapon(def.id), if def.splash > 0 then "💥" elseif def.pellets > 1 then "🎯" else "🔫", UDim2.new(1, 0, 0, 30), {
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = if usable then 0 else 0.65,
			ImageTransparency = if usable then 0 else 0.65,
		})
		local name = Ui.label(slot, SHORT_NAMES[def.id] or def.name, UDim2.new(1, -4, 0, 18), {
			Position = UDim2.fromOffset(2, 34),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true,
			TextColor3 = if not usable then C.grey elseif current then C.yellow else C.text,
		})
		Ui.make("UITextSizeConstraint", { MaxTextSize = 12 }, name)
		if seated and usable then
			slotTag(slot, "WINDOW", C.green)
		end
		slot.Activated:Connect(function()
			Net.get("Equip"):FireServer("weapon", def.id)
		end)
	end
end

-- Q: the next gun you own.
local function nextWeapon()
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
Ui.list(hotbar, false, 8)
local hotbarCounts: { [string]: any } = {}
for index, def in Config.Items do
	local art = Icons.item(def.id)
	local slot = Ui.make("TextButton", {
		Size = UDim2.fromOffset(64, 64),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		Text = if Icons.get(art) then "" else def.icon, -- the emoji until the item's icon is filled in
		TextSize = 30,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.new(1, 1, 1),
		LayoutOrder = index,
		AutoButtonColor = true,
	}, hotbar)
	Ui.corner(slot, 10)
	Ui.stroke(slot, C.yellow, 1.5)
	if Icons.get(art) then
		Ui.icon(slot, art, def.icon, UDim2.fromOffset(34, 34), { Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5) })
	end
	Ui.label(slot, tostring(index), UDim2.fromOffset(16, 16), { Position = UDim2.fromOffset(4, 2), TextSize = 13, TextColor3 = C.yellow })
	hotbarCounts[def.id] = Ui.label(slot, "0", UDim2.new(1, -6, 0, 16), {
		Position = UDim2.new(0, 0, 1, -18),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	slot.Activated:Connect(function()
		useItem(def.id)
	end)
end

-- FIRE for touch screens (auto-aim).
local fire = scaled(Ui.make("TextButton", {
	Size = UDim2.fromOffset(110, 110),
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

-- ── Car panel ──────────────────────────────────────────────────────────────

local carPanel = scaled(Ui.panel(gui, UDim2.fromOffset(380, 86), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1)))
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
local hint = Ui.label(gui, "", UDim2.fromOffset(640, 22), {
	Position = UDim2.new(0.5, 0, 1, if touchLayout then -262 else -104),
	AnchorPoint = Vector2.new(0.5, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextColor3 = C.dim,
	TextSize = 15,
	TextStrokeTransparency = 0.5,
	Font = Enum.Font.GothamMedium,
})

-- ── Job panel ──────────────────────────────────────────────────────────────
-- Top centre: the job and the clock, what to do now (big), the stop and the person, the cargo (in your hands,
-- at this stop, in the vehicle) and the cargo's condition.

local jobPanel = scaled(Ui.panel(gui, UDim2.fromOffset(540, 0), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0)))
jobPanel.AutomaticSize = Enum.AutomaticSize.Y
jobPanel.Visible = false
Ui.padding(jobPanel, 12)
local jobStroke = Ui.stroke(jobPanel, C.yellow, 2)
Ui.list(jobPanel, true, 6)
local jobHeader = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, jobPanel)
local jobTitle = Ui.label(jobHeader, "", UDim2.new(1, -80, 1, 0), { TextSize = 15, TextColor3 = C.dim, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
local jobTimer = Ui.label(jobHeader, "", UDim2.new(0, 80, 1, 0), {
	Position = UDim2.new(1, -80, 0, 0),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextSize = 22,
	Font = Enum.Font.GothamBlack,
})
local jobStep = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 0), {
	AutomaticSize = Enum.AutomaticSize.Y,
	LayoutOrder = 2,
	TextSize = 24,
	Font = Enum.Font.GothamBlack,
})
local jobInfo = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 18), { LayoutOrder = 3, TextColor3 = C.dim, TextSize = 15, Font = Enum.Font.GothamMedium })
local cargoRow = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 4, Visible = false }, jobPanel)
Ui.list(cargoRow, false, 6)
local conditionBack, conditionFill = Ui.bar(jobPanel, UDim2.new(1, 0, 0, 8), C.yellow)
conditionBack.LayoutOrder = 5
local conditionText = Ui.label(jobPanel, "", UDim2.new(1, 0, 0, 0), {
	AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6,
	TextXAlignment = Enum.TextXAlignment.Left, TextSize = 14, TextColor3 = C.dim, ZIndex = 2,
})

-- Loading / unloading / boarding bar in the middle of the screen.
local loadBack, loadFill = Ui.bar(gui, UDim2.fromOffset(340, 26), C.blue)
scaled(loadBack)
loadBack.AnchorPoint = Vector2.new(0.5, 0.5)
loadBack.Position = UDim2.fromScale(0.5, 0.62)
loadBack.Visible = false
local loadText = Ui.label(loadBack, "", UDim2.fromScale(1, 1), { TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, ZIndex = 2, Font = Enum.Font.GothamBlack })

local cargoSignature = ""

-- The cargo chips: what you hold, the pieces of this stop (done ones bright), how many ride in the vehicle.
local function renderCargoRow()
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

-- ── The way to the target ──────────────────────────────────────────────────
-- The park circle (a ring and a light beam) and, on foot during a carry step, a small ring at the pile / the
-- person with a thin beam over their head; a floating label and an arrow (over the car, or over your head on foot).

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
local beacon = guidePart("Beacon", BEACON_WIDE, 0.55)
beacon.Shape = Enum.PartType.Cylinder
local ring = guidePart("Ring", Vector3.new(0.2, Config.Jobs.DeliverRadius * 2, Config.Jobs.DeliverRadius * 2), 0.5)
ring.Shape = Enum.PartType.Cylinder
local pileRing = guidePart("PileRing", Vector3.new(0.2, 7, 7), 0.35)
pileRing.Shape = Enum.PartType.Cylinder
local label = guidePart("Label", Vector3.new(0.2, 0.2, 0.2), 1)
local labelGui = Ui.make("BillboardGui", { Size = UDim2.fromOffset(260, 60), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 100000 }, label)
local labelText = Ui.label(labelGui, "", UDim2.fromScale(1, 1), {
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
local HIDDEN = CFrame.new(0, -1000, 0)
local PICKUP_COLOR = Color3.fromRGB(110, 190, 255)
local PILE_COLOR = Color3.fromRGB(120, 235, 140)
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis is X: stood up

local function hideGuide()
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
local function placeGuide(p: Vector3, color: Color3, beamAt: Vector3?, labelAt: Vector3?)
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
local function pointArrow(origin: Vector3?, flat: Vector3, scale: number)
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
local GPS_COLOR = Color3.fromRGB(176, 92, 255) -- the purple of the GPS route on the maps (client/MapView.luau)
local gps: { position: Vector3, name: string }? = nil

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
local function myPosition(): Vector3?
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
local function footTarget(): (Vector3?, string?, boolean)
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

-- ── Level up ───────────────────────────────────────────────────────────────
-- A banner at the top (where the job panel is; a level-up mostly comes as the job ends): LEVEL UP, the new level and
-- rank, what it unlocks; the XP bar flashes. Under the windows, so it never hides the delivery result.

local levelUpFrame = scaled(Ui.make("CanvasGroup", {
	Size = UDim2.fromOffset(440, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.new(0.5, 0, 0, 14),
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = C.panel,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Visible = false,
	ZIndex = 4,
}, gui))
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
	levelUpFrame.Position = UDim2.new(0.5, 0, 0, -10)
	TweenService:Create(levelUpFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, 14) }):Play()
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
local function refreshLevel()
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
	updateScale()
	refreshLevel()
	player:GetAttributeChangedSignal("Xp"):Connect(refreshLevel)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	MapView.start(gui, leftStack)
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
		elseif key == Enum.KeyCode.Q then
			nextWeapon()
		else
			local numbers = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
			local index = table.find(numbers, key)
			if index and Config.Items[index] then
				useItem(Config.Items[index].id)
			end
		end
	end)
end

return Hud
