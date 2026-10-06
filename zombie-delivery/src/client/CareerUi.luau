--!strict
-- 4.6, the career on the client (shared/Career.luau builds the road from Config; the server gives the rewards,
-- server/PlayerData.luau):
--
--   * The CAREER window (C, or MENU → CAREER), a courier's career path in the contract look (design/ui-contract/):
--     on the left YOUR CAREER: the rank you hold, the level, the XP bar, the NEXT GOAL (the next level: the XP to go,
--     about how many deliveries that is, what it unlocks, its reward), 4.7 the LICENCES (the ★★★ and ★★★★ board jobs:
--     the level and the good jobs each needs, shared/JobRules.luau) with your streak, and the ladder of the ranks; on the right THE
--     ROAD: every level from 1 to the top as a slim row on a line, done ones ticked, the current one raised with the
--     red rule (YOU ARE HERE), the next one marked NEXT with its progress, the rest LOCKED (dim) with the XP they
--     need. Each row says what the level unlocks (the job board's tiers and special jobs, cars, the stages of the
--     cars you own, gear, guns, car guns, campaigns, garages, homes) and its reward. A narrow screen drops the left
--     side: the same summary sits on top of the road.
--   * The LEVEL-UP card: when the XP attribute crosses a level, a short centred card: "LEVEL 5 · ROAD WARRIOR", what
--     it unlocked, the reward (paid by the server), then "NEXT: LEVEL 6 — …" with the XP to go. OK or Space closes
--     it (client/DialogKeys.luau), CAREER opens the window. It waits while the DELIVERY result or a mission's card is
--     up (CareerUi.blocked, set by Main), and a jump over several levels shows them as one card.
-- While the window or the card is open the mouse is free (Main: CameraRig.mouseNeeded).
-- 5.0: the road starts on foot (shared/Career.luau): level 1 the on-foot runs and the personal gear (Config.Kit, with
-- its price at Last Stop Supplies), the bikes as a "coming in 5.1" line, the Old Van and the car tiers at their new
-- levels (all from Config). Below the first car tier the next goal counts on-foot runs. The phone's CAREER app
-- (client/Phone.luau) reads CareerUi.unlockText and CareerUi.toGo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Career = require(Shared.Career)
local JobRules = require(Shared.JobRules)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local DialogKeys = require(script.Parent.DialogKeys)
local P = require(script.Parent.HudContract)

local K = Theme.Contract
local CareerUi = {}

-- Set by Main: opening the window closes the other windows (one window at a time).
CareerUi.onOpen = nil :: (() -> ())?
-- Set by Main: while this says so, the level-up card waits (the DELIVERY result, a mission's cleared card).
CareerUi.blocked = nil :: (() -> boolean)?

local player = Players.LocalPlayer
local WIDTH, HEIGHT = 920, 580 -- the window at scale 1 (Ui.screenScale)
local LEFT_W = 300
local NARROW = 760 -- a window narrower than this (at scale) drops the left side
local CARD_W = 480
local CARD_SECONDS = 30 -- the level-up card closes by itself after this long
local KEY = Enum.KeyCode.C

local state: any = nil
local gui: ScreenGui? = nil
local window: any = nil
local chrome: any = nil
local scale: any = nil
local refs: { [string]: any } = {}

-- ── Small helpers ──────────────────────────────────────────────────────────

local function myXp(): number
	local xp = tonumber(player:GetAttribute("Xp"))
	if xp == nil and state and type(state.xp) == "number" then
		xp = state.xp
	end
	return xp or 0
end

-- Is the HUD on (not the start screen)? Its ScreenGui's Enabled (client/Hud.luau).
local function hudOn(): boolean
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	return not (hud and hud:IsA("ScreenGui")) or hud.Enabled
end

-- "12,345".
local function num(n: number): string
	return string.sub(Career.money(n), 2)
end

local function owned(): { [string]: boolean }
	return if state and type(state.cars) == "table" then state.cars else {}
end

local KIND_ICON: { [string]: string } = {
	job = "📋",
	car = "🚚",
	stage = "🔧",
	gun = "🔫",
	cargun = "🎯",
	campaign = "⭐",
	garage = "🅿",
	estate = "🏠",
	foot = "🚶", -- 5.0: the on-foot runs
	soon = "🚲", -- 5.0: what the next release brings (the bikes, 5.1)
}

-- An unlock as the road shows it: its kind's mark and its name ("🔧 Work Van (Old Van)" for a stage).
local function unlockText(unlock: Career.Unlock): string
	local icon = KIND_ICON[unlock.kind]
	if unlock.kind == "gear" then
		local gear = Economy.findGear(unlock.id)
		return `{if gear then gear.icon else "🧰"} {unlock.name} (gear)`
	elseif unlock.kind == "kit" then
		-- 5.0: personal gear, at Last Stop Supplies
		for _, kit in Config.Kit do
			if kit.id == unlock.id then
				return `{kit.icon} {unlock.name} ({Career.money(kit.price)} at Last Stop Supplies)`
			end
		end
		return `🎒 {unlock.name}`
	elseif unlock.kind == "stage" then
		local car = Economy.findCar(unlock.car or "")
		return `{icon} {unlock.name}{if car then ` ({car.name} stage)` else ""}`
	end
	return if icon then `{icon} {unlock.name}` else unlock.name
end

-- The unlocks of a level worth showing: a stage only for a car you own.
local function shownUnlocks(unlocks: { Career.Unlock }): { Career.Unlock }
	local mine = owned()
	local out: { Career.Unlock } = {}
	for _, unlock in unlocks do
		if unlock.kind ~= "stage" or mine[unlock.car or ""] then
			table.insert(out, unlock)
		end
	end
	return out
end

local function unlockLine(unlocks: { Career.Unlock }, max: number?): string
	local parts: { string } = {}
	local list = shownUnlocks(unlocks)
	for index, unlock in list do
		if max and index > max then
			table.insert(parts, `and {#list - max} more`)
			break
		end
		table.insert(parts, unlockText(unlock))
	end
	return table.concat(parts, "   ·   ")
end

-- About how many deliveries the XP to go is: a delivery of the best danger level open to you, 3 pieces, a few kills.
-- 5.0: below the first car tier (no danger level open yet) an on-foot run: stars 0 (the words say "on-foot runs").
-- Its XP is Config.Jobs.Foot's (xp: a number, or { min, max }) when Stream A's band says it, else a ★ job's with 2
-- pieces and no kills.
local function deliveriesFor(xpLeft: number, level: number): (number, number)
	local stars = 0
	for _, tier in Config.Jobs.Tiers do
		if tier.level <= level then
			stars = math.max(stars, tier.stars)
		end
	end
	local each: number
	if stars == 0 then
		local foot = (Config.Jobs :: any).Foot
		local xp = if type(foot) == "table" then foot.xp else nil
		if type(xp) == "number" then
			each = xp
		elseif type(xp) == "table" and type(xp[1]) == "number" and type(xp[2]) == "number" then
			each = (xp[1] + xp[2]) / 2
		else
			each = Levels.jobXp(1, 2, 0, false, true)
		end
	else
		each = Levels.jobXp(stars, 3, 5, false, true)
	end
	return math.max(1, math.ceil(xpLeft / math.max(1, each))), stars
end

-- "about 6 ★★ deliveries" / "about 8 on-foot runs".
local function deliveriesText(count: number, stars: number): string
	if stars == 0 then
		return `{count} on-foot {if count == 1 then "run" else "runs"}`
	end
	return `{count} {string.rep("★", stars)} {if count == 1 then "delivery" else "deliveries"}`
end

-- 5.0, for the phone's CAREER app (client/Phone.luau): an unlock in the road's words, and the XP to go as work
-- ("8 on-foot runs").
CareerUi.unlockText = unlockText
function CareerUi.toGo(xpLeft: number, level: number): string
	local count, stars = deliveriesFor(xpLeft, level)
	return deliveriesText(count, stars)
end

local function label(parent: Instance, text: string, props: { [string]: any }?): any
	local made = Ui.label(parent, text, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = P.ink2,
		RichText = true,
	})
	if props then
		for key, value in props do
			made[key] = value
		end
	end
	return made
end

local function caps(parent: Instance, text: string, order: number, color: Color3?): any
	return P.caps(parent, text, UDim2.new(1, 0, 0, 16), { LayoutOrder = order, TextStrokeTransparency = 1, TextColor3 = color or P.ink2 })
end

-- ── The driver: rank, level, XP, the next goal, the ranks ───────────────────

-- Fills `parent` (a vertical list) with the summary of your career.
local function driverPanel(parent: Instance, road: { Career.Step })
	local xp = myXp()
	local level = Levels.levelFor(xp)
	local max = Config.Levels.MaxLevel
	local rank = Levels.rank(level)
	caps(parent, "Your career", 1)
	label(parent, string.upper(rank), { LayoutOrder = 2, Font = Theme.DisplayFont, TextSize = 24, TextColor3 = P.ink })
	label(parent, `LEVEL {level} OF {max}  ·  {num(xp)} XP`, { LayoutOrder = 3, Font = Theme.HeadingFont, TextSize = 13 })
	local barRow = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = 4 }, parent)
	local _, fill = P.bar(barRow, UDim2.new(1, 0, 0, 4), P.accent)
	fill.Size = UDim2.fromScale(Levels.progress(xp), 1)
	P.rule(parent, UDim2.new(1, 0, 0, 1), { LayoutOrder = 5 })
	local nextStep = road[level + 1]
	if nextStep then
		local left = math.max(0, nextStep.xp - xp)
		local count, stars = deliveriesFor(left, level)
		caps(parent, "Next goal", 6, P.danger)
		label(parent, `<b>LEVEL {nextStep.level}</b>{if nextStep.newRank then `  ·  {string.upper(nextStep.rank)}` else ""}`, { LayoutOrder = 7, TextSize = 17, Font = Theme.HeadingFont, TextColor3 = P.ink })
		label(parent, `{num(left)} XP to go: about {deliveriesText(count, stars)}. Missions, kills and night jobs give more.`, { LayoutOrder = 8 })
		local opens = unlockLine(nextStep.unlocks, 5)
		if opens ~= "" then
			label(parent, `<b>Opens</b>  {opens}`, { LayoutOrder = 9, TextColor3 = P.ink })
		end
		local parts = Career.rewardParts(nextStep.reward)
		if #parts > 0 then
			label(parent, `<b>Reward</b>  <font color="{P.hex(P.good)}">{table.concat(parts, "  ·  ")}</font>`, { LayoutOrder = 10, TextColor3 = P.ink })
		end
	else
		caps(parent, "The top", 6, P.danger)
		label(parent, "You reached the last level. Every car, gun and job is open: the road is yours.", { LayoutOrder = 7, TextColor3 = P.ink })
	end
	P.rule(parent, UDim2.new(1, 0, 0, 1), { LayoutOrder = 11 })
	-- 4.7: the licences for the dangerous board jobs (Config.Jobs.Licences) and the streak of good jobs.
	caps(parent, "Licences", 12)
	local held = if state and type(state.licences) == "table" then state.licences else {}
	local counts = if state and type(state.licenceJobs) == "table" then state.licenceJobs else {}
	for index, def in Config.Jobs.Licences do
		local stars = string.rep("★", def.tier)
		local text: string
		if JobRules.hasLicence(def.tier, level, held, counts) then
			text = `<b>{stars} LICENCE</b>  <font color="{P.hex(P.good)}">✓ held</font>`
		else
			local have, need = JobRules.progress(def.tier, counts)
			local levelText = if level >= def.level then `✓ level {def.level}` else `level {def.level}`
			text = `<b>{stars} LICENCE</b>  {levelText}  ·  {have} / {need} jobs rated ★★+ at {string.rep("★", def.atTier)} or harder`
		end
		label(parent, text, { LayoutOrder = 12 + index, TextColor3 = P.ink })
	end
	local streak = if state and type(state.streak) == "number" then state.streak else 0
	label(parent, `<b>Streak</b>  {streak} good {if streak == 1 then "job" else "jobs"} in a row: +{math.floor(JobRules.streakBonus(streak) * 100 + 0.5)}% pay. A job rated ★★ or better keeps it, ★ or a failed one ends it; ★★★ pays +20% and ×1.25 XP.`, { LayoutOrder = 16 })
	P.rule(parent, UDim2.new(1, 0, 0, 1), { LayoutOrder = 17 })
	caps(parent, "The ranks", 18)
	for index, entry in Config.Levels.Ranks do
		local here = rank == entry.name
		local done = level >= entry.level
		local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 18 + index }, parent)
		if here then
			P.marker(row, 6, { Position = UDim2.fromOffset(0, 6) })
		end
		Ui.label(row, `LV {entry.level}`, UDim2.fromOffset(44, 18), { Position = UDim2.fromOffset(12, 0), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = if done then P.ink2 else P.line, TextWrapped = false })
		Ui.label(row, string.upper(entry.name), UDim2.new(1, -60, 0, 18), {
			Position = UDim2.fromOffset(58, 0),
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = if here then P.ink elseif done then P.ink2 else P.line,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
end

-- ── The road ───────────────────────────────────────────────────────────────

-- One level of the road. Returns the row (the current one is scrolled to).
local function roadRow(step: Career.Step, level: number, xp: number, order: number, last: boolean): any
	local done = step.level < level
	local here = step.level == level
	local nextOne = step.level == level + 1
	local locked = step.level > level
	local row = Ui.make("Frame", {
		Name = `Level{step.level}`,
		Size = UDim2.new(1, -8, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = if here then P.raised else P.surface,
		BackgroundTransparency = if here then 0 else 1,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, refs.road)
	if here then
		Ui.make("Frame", { Name = "Selected", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = P.red, BorderSizePixel = 0, ZIndex = 2 }, row)
	end
	-- The milestone: a line down the road through a square with the level's number.
	-- (it starts at the first stone's middle and ends at the last one's)
	local railTop = if step.level == 1 then 26 else 0
	local rail = Ui.make("Frame", {
		Size = if last then UDim2.fromOffset(2, 26 - railTop) else UDim2.new(0, 2, 1, -railTop),
		Position = UDim2.fromOffset(31, railTop),
		BackgroundColor3 = if done or here then P.ink2 else P.line,
		BackgroundTransparency = if done or here then 0.2 else 0.6,
		BorderSizePixel = 0,
	}, row)
	rail.ZIndex = 1
	local stone = Ui.label(row, tostring(step.level), UDim2.fromOffset(32, 32), {
		Position = UDim2.fromOffset(16, 10),
		BackgroundColor3 = if done then P.ink2 elseif here then P.red else K.charcoal,
		BackgroundTransparency = 0,
		Font = Theme.HeadingFont,
		TextSize = 15,
		TextColor3 = if done or here then K.charcoal else (if nextOne then P.ink else P.line),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 3,
	})
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if nextOne then P.ink else P.line, Thickness = 1, Transparency = if locked and not nextOne then 0.5 else 0 }, stone)
	-- The words.
	local text = Ui.make("Frame", {
		Size = UDim2.new(1, -72, 0, 0),
		Position = UDim2.fromOffset(64, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, row)
	Ui.list(text, true, 3)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 8) }, text)
	local dim = if locked and not nextOne then 0.35 else 0
	local head = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1 }, text)
	Ui.label(head, `LEVEL {step.level}{if step.newRank then `  ·  {string.upper(step.rank)}` else ""}`, UDim2.new(1, -150, 1, 0), {
		Font = Theme.HeadingFont,
		TextSize = 15,
		TextColor3 = P.ink,
		TextTransparency = dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local status = if here then "YOU ARE HERE" elseif done then "✓ DONE" elseif nextOne then "NEXT" else `🔒 {num(step.xp)} XP`
	local tag = P.tag(head, status, if here or nextOne then P.danger elseif done then P.good else P.line)
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.new(1, 0, 0, 1)
	if nextOne then
		-- The way to it: the share of the XP between your level and this one.
		local from = Levels.xpFor(level)
		local share = math.clamp((xp - from) / math.max(1, step.xp - from), 0, 1)
		local barRow = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 2 }, text)
		local back, fill = P.bar(barRow, UDim2.new(1, -150, 0, 3), P.danger)
		back.Position = UDim2.fromOffset(0, 7)
		fill.Size = UDim2.fromScale(share, 1)
		Ui.label(barRow, `{num(math.max(0, step.xp - xp))} XP TO GO`, UDim2.fromOffset(140, 16), {
			Position = UDim2.new(1, 0, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextColor3 = P.ink2,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextWrapped = false,
		})
	end
	local opens = unlockLine(step.unlocks)
	if step.level == 1 then
		opens = `{opens}{if opens ~= "" then "   ·   " else ""}{Career.money(Config.StartMoney)} to start`
	end
	if opens ~= "" then
		label(text, `<b>{if step.level == 1 then "START" else "UNLOCKS"}</b>   {opens}`, { LayoutOrder = 3, TextColor3 = P.ink, TextTransparency = dim })
	end
	local parts = Career.rewardParts(step.reward)
	if #parts > 0 then
		local color = if done then P.ink2 else P.good
		label(text, `<b>REWARD</b>   <font color="{P.hex(color)}">{table.concat(parts, "  ·  ")}</font>{if done then "  (given)" else ""}`, { LayoutOrder = 4, TextColor3 = P.ink, TextTransparency = dim })
	end
	return row
end

-- ── The window ─────────────────────────────────────────────────────────────

local function build()
	if gui then
		return
	end
	local made = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryCareer",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
		IgnoreGuiInset = false,
	}, player:WaitForChild("PlayerGui"))
	gui = made
	local content
	window, content, chrome = Ui.window(made, "Career", "Dead End Dispatch · your road as a courier", "🎖", UDim2.fromOffset(WIDTH, HEIGHT))
	window.Visible = false
	scale = window:FindFirstChildOfClass("UIScale") or Ui.make("UIScale", {}, window)
	chrome.onClose = function()
		CareerUi.close()
	end
	-- The left side: your career (a scrolling list: a small screen still reaches the ranks).
	local left = Ui.make("ScrollingFrame", {
		Name = "Driver",
		Size = UDim2.new(0, LEFT_W, 1, 0),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = P.line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, content)
	-- (the fine line between the sides lives on the content: the panel's own children are cleared on every render)
	refs.leftLine = Ui.make("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromOffset(LEFT_W - 1, 0), BackgroundColor3 = K.rule, BorderSizePixel = 0, ZIndex = 2 }, content)
	Ui.list(left, true, 8)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingRight = UDim.new(0, 20), PaddingTop = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18) }, left)
	refs.left = left
	-- The right side: the road.
	local right = Ui.make("Frame", { Name = "Road", Size = UDim2.new(1, -LEFT_W, 1, 0), Position = UDim2.fromOffset(LEFT_W, 0), BackgroundTransparency = 1 }, content)
	refs.right = right
	refs.roadTitle = P.caps(right, "", UDim2.new(1, -48, 0, 16), { Position = UDim2.fromOffset(24, 16), TextStrokeTransparency = 1 })
	local road = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -30, 1, -44),
		Position = UDim2.fromOffset(16, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = P.ink2,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, right)
	Ui.list(road, true, 0)
	Ui.make("UIPadding", { PaddingBottom = UDim.new(0, 12) }, road)
	refs.road = road
end

-- The window's size on this screen: the design size scaled, never wider or taller than the screen. Narrow: the road
-- alone (the summary on top of it).
local function fit(): boolean
	local s = Ui.screenScale()
	local screen = Ui.screenSize()
	scale.Scale = s
	local width = math.floor(math.min(WIDTH, (screen.X - 16) / s))
	window.Size = UDim2.fromOffset(width, math.floor(math.min(HEIGHT, (screen.Y - 16) / s)))
	local narrow = width < NARROW
	refs.left.Visible = not narrow
	refs.leftLine.Visible = not narrow
	refs.right.Size = if narrow then UDim2.fromScale(1, 1) else UDim2.new(1, -LEFT_W, 1, 0)
	refs.right.Position = if narrow then UDim2.new() else UDim2.fromOffset(LEFT_W, 0)
	return narrow
end

local function render()
	if not window then
		return
	end
	local narrow = fit()
	local road = Career.road()
	local xp = myXp()
	local level = Levels.levelFor(xp)
	Ui.clear(refs.left)
	Ui.clear(refs.road)
	driverPanel(refs.left, road)
	refs.roadTitle.Text = `THE ROAD  ·  LEVEL 1 → {Config.Levels.MaxLevel}`
	local order = 0
	if narrow then
		-- The summary on top of the road.
		local top = Ui.make("Frame", { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = K.row, BorderSizePixel = 0, LayoutOrder = 0 }, refs.road)
		Ui.list(top, true, 8)
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) }, top)
		driverPanel(top, road)
	end
	local current: any = nil
	for _, step in road do
		order += 1
		local row = roadRow(step, level, xp, order, step.level == #road)
		if step.level == level then
			current = row
		end
	end
	chrome.context.Text = `<b>LEVEL {level} · {string.upper(Levels.rank(level))}</b> · {num(xp)} XP{if Ui.touchLayout() then "" else " · C TO CLOSE"}`
	-- Scrolled so the current level sits near the top (once the rows are laid out; a narrow screen starts at the
	-- summary on top).
	task.delay(0.1, function()
		local list = refs.road
		if current and current.Parent and not narrow and CareerUi.isOpen() then
			local y = (current.AbsolutePosition.Y - list.AbsolutePosition.Y) / math.max(0.01, scale.Scale) + list.CanvasPosition.Y
			list.CanvasPosition = Vector2.new(0, math.max(0, y - 60))
		end
	end)
end

function CareerUi.setState(newState: any)
	state = newState
end

function CareerUi.isOpen(): boolean
	return window ~= nil and window.Visible == true
end

function CareerUi.close()
	if window and window.Visible then
		window.Visible = false
		Ui.gamepadRelease(window)
	end
end

function CareerUi.open()
	build()
	local hook = CareerUi.onOpen
	if hook then
		pcall(hook)
	end
	window.Visible = true
	render()
	Ui.gamepadFocus(chrome.close)
end

function CareerUi.toggle()
	if CareerUi.isOpen() then
		CareerUi.close()
	else
		CareerUi.open()
	end
end

-- ── The level-up card ──────────────────────────────────────────────────────

local card: any = nil
local cardRefs: { [string]: any } = {}
local cardToken = 0
local pendingFrom: number? = nil -- the level before the jump that waits to be shown
local pendingTo = 0
local waiting = false

local function buildCard()
	if card then
		return
	end
	local made = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryLevelUp",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 7,
		IgnoreGuiInset = false,
	}, player:WaitForChild("PlayerGui"))
	card = Ui.make("Frame", {
		Name = "LevelUpCard",
		Size = UDim2.fromOffset(CARD_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
	}, made)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1 }, card)
	cardRefs.scale = Ui.make("UIScale", {}, card)
	Ui.list(card, true, 8)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 28), PaddingRight = UDim.new(0, 28), PaddingTop = UDim.new(0, 22), PaddingBottom = UDim.new(0, 22) }, card)
	local top = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 1 }, card)
	P.marker(top, 7, { Position = UDim2.fromOffset(0, 4) })
	P.caps(top, "Level up  ·  Dead End Dispatch", UDim2.new(1, -16, 1, 0), { Position = UDim2.fromOffset(16, 0), TextStrokeTransparency = 1 })
	cardRefs.title = label(card, "", { LayoutOrder = 2, Font = Theme.DisplayFont, TextSize = 26, TextColor3 = P.ink })
	cardRefs.rank = label(card, "", { LayoutOrder = 3, Font = Theme.HeadingFont, TextSize = 13, TextColor3 = P.danger })
	P.rule(card, UDim2.new(1, 0, 0, 1), { LayoutOrder = 4 })
	cardRefs.unlocks = label(card, "", { LayoutOrder = 5, TextColor3 = P.ink, TextSize = 15 })
	cardRefs.reward = label(card, "", { LayoutOrder = 6, TextColor3 = P.ink, TextSize = 15 })
	P.rule(card, UDim2.new(1, 0, 0, 1), { LayoutOrder = 7 })
	cardRefs.nextLine = label(card, "", { LayoutOrder = 8, TextSize = 14 })
	local buttons = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 9 }, card)
	Ui.list(buttons, false, 10)
	local function closeCard()
		cardToken += 1
		if card.Visible then
			card.Visible = false
			Ui.gamepadRelease(card)
		end
	end
	cardRefs.close = closeCard
	local hint = DialogKeys.hint()
	cardRefs.ok = P.button(buttons, if hint ~= "" then `OK   ·   {hint}` else "OK", UDim2.fromOffset(200, 44), "main", closeCard)
	cardRefs.ok.LayoutOrder = 1
	local more = P.button(buttons, "CAREER  ·  THE ROAD", UDim2.fromOffset(200, 44), "quiet", function()
		closeCard()
		CareerUi.open()
	end)
	more.LayoutOrder = 2
	DialogKeys.watch("careerLevelUp", card, closeCard, { layer = 2 })
end

-- Shows the card for a jump from level `from` to `to` (several levels: all their unlocks and rewards).
local function showCard(from: number, to: number)
	buildCard()
	local road = Career.road()
	local step = road[to]
	if not step then
		return
	end
	cardRefs.scale.Scale = math.clamp(Ui.screenScale(), 0.6, 1.05)
	cardRefs.title.Text = `LEVEL {to}  ·  {string.upper(step.rank)}`
	local newRank = Levels.rank(from) ~= step.rank
	cardRefs.rank.Text = if newRank then "A NEW RANK" else `YOU STAY A {string.upper(step.rank)}`
	cardRefs.rank.TextColor3 = if newRank then P.danger else P.ink2
	local unlocks: { Career.Unlock } = {}
	local money = 0
	local others: { string } = {}
	for level = from + 1, to do
		local at = road[level]
		if at then
			for _, unlock in at.unlocks do
				table.insert(unlocks, unlock)
			end
			local reward = at.reward
			if reward then
				money += reward.money or 0
				local parts = Career.rewardParts({ items = reward.items, paint = reward.paint, title = reward.title })
				for _, part in parts do
					table.insert(others, part)
				end
			end
		end
	end
	local opens = unlockLine(unlocks, 6)
	cardRefs.unlocks.Text = if opens ~= "" then `<b>UNLOCKED</b>   {opens}` else "<b>UNLOCKED</b>   better pay and harder roads."
	local paid: { string } = {}
	if money > 0 then
		table.insert(paid, Career.money(money))
	end
	for _, part in others do
		table.insert(paid, part)
	end
	cardRefs.reward.Text = if #paid > 0 then `<b>REWARD</b>   <font color="{P.hex(P.good)}">{table.concat(paid, "  ·  ")}</font>` else ""
	cardRefs.reward.Visible = #paid > 0
	local nextStep = road[to + 1]
	if nextStep then
		local left = math.max(0, nextStep.xp - myXp())
		local summary = Career.summary(shownUnlocks(nextStep.unlocks), 3)
		cardRefs.nextLine.Text = `<b>NEXT: LEVEL {nextStep.level}</b>{if summary ~= "" then ` — {summary}` else ""}  ·  {num(left)} XP to go`
	else
		cardRefs.nextLine.Text = "<b>THE TOP OF THE ROAD.</b>  Every car, gun and job is yours."
	end
	cardToken += 1
	local mine = cardToken
	card.Visible = true
	Ui.gamepadFocus(cardRefs.ok)
	task.delay(CARD_SECONDS, function()
		if cardToken == mine then
			cardRefs.close()
		end
	end)
end

-- A level-up: shown now, or once nothing covers the middle of the screen (several in a row become one card).
local function levelUp(from: number, to: number)
	pendingFrom = math.min(pendingFrom or from, from)
	pendingTo = math.max(pendingTo, to)
	if waiting then
		return
	end
	waiting = true
	task.spawn(function()
		task.wait(0.6) -- (the DELIVERY result comes with the level)
		local waited = 0
		while waited < 120 do
			local blocked = CareerUi.blocked
			if hudOn() and not (blocked and blocked()) then
				break
			end
			waited += task.wait(0.25)
		end
		waiting = false
		local a, b = pendingFrom or from, pendingTo
		pendingFrom, pendingTo = nil, 0
		if b > a then
			showCard(a, b)
		end
	end)
end

-- Is the level-up card on screen?
function CareerUi.cardOpen(): boolean
	return card ~= nil and card.Visible == true
end

function CareerUi.start()
	-- The level shown (nil until the save loaded: the first value is no level-up).
	local shown: number? = nil
	local function onXp()
		local xp = tonumber(player:GetAttribute("Xp"))
		if xp == nil then
			return
		end
		local level = Levels.levelFor(xp)
		local before = shown
		shown = level
		if before ~= nil and level > before then
			levelUp(before, level)
		end
		if CareerUi.isOpen() then
			render()
		end
	end
	player:GetAttributeChangedSignal("Xp"):Connect(onXp)
	onXp()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() or input.KeyCode ~= KEY then
			return
		end
		if hudOn() then
			CareerUi.toggle()
		end
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if CareerUi.isOpen() then
				render()
			end
		end)
	end
end

return CareerUi
