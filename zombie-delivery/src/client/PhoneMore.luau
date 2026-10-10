--!strict
-- 6.18 wave 2, the phone's other apps in the UI kit (client/CardKit.luau; design/ui-kit/README.md; the owner: "every
-- window like JOBS"). client/Phone.luau draws them in its centred popup and lends what they read (`Ctx`):
--   * CAREER (the phone's): the NEXT LEVEL is the hero (the rank and the level on the ribbon, "NEXT: LEVEL 6", the XP to
--     go big in gold, about how much work that is and its reward on one line, the XP bar, FULL CAREER [C] the one
--     button); the road after it as the kit's rows (the level's number, what it unlocks, its reward money, 🔒 LV n).
--     6.20: two tabs on top, ROAD (the above) and SKILLS ("SKILLS · 2" with free points; client/SkillsView.luau: the
--     skill points, RESET · FREE, the three branches, a skill's details with +1 POINT).
--   * BANK: the cash is the hero (AVAILABLE CASH, the money big in green, FIND A DELIVERY), what you earned since you
--     joined a row (its money big).
--   * MESSAGES: a row a message, the newest first (the sender's initial on its colour, "MARGE · 21:04", the message's
--     first line, a red dot while unread); a tap opens it whole ("‹ MESSAGES" goes back).
--   * SETTINGS: a row a setting (SOUND · CYCLE, ENEMY OUTLINES · ON / OFF, Marge's tours ›), PUT PHONE AWAY the one
--     button, then the keys and the version (client/PhoneApps.luau keys).
-- Presentation only: every action keeps its old path (Phone.onCareer, Phone.onSound / Sounds.cycle, Phone.onOutline,
-- Phone.onTour, the board through Phone's launch).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Career = require(Shared.Career)
local Levels = require(Shared.Levels)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local OrdersUi = require(script.Parent.OrdersUi)
local PhoneContract = require(script.Parent.PhoneContract)
local CardKit = require(script.Parent.CardKit)
local SkillsView = require(script.Parent.SkillsView) -- 6.20: CAREER's SKILLS tab

local K = Theme.Contract
local KIT = Config.UiKit
local C = CardKit.Color
local PhoneMore = {}

-- What Phone lends the apps.
export type Message = { from: string, text: string, time: string, kind: string, unread: boolean }
export type Ctx = {
	wide: boolean,
	room: number, -- the popup's room (the hero's height)
	redraw: () -> (), -- the app again (a sub-view, a toggle)
	-- CAREER
	xp: number?,
	level: number?,
	cars: { [string]: boolean }?,
	toGo: ((xpLeft: number, level: number) -> string)?, -- CareerUi.toGo
	skills: { [string]: number }?, -- 6.20: the skills' ranks (the state's)
	onCareer: (() -> ())?, -- FULL CAREER: the window (Phone.onCareer)
	-- BANK
	money: number?,
	earned: number?,
	onBoard: (() -> ())?, -- FIND A DELIVERY: the board
	-- MESSAGES
	messages: { Message }?,
	-- SETTINGS
	onSound: (() -> ())?,
	outlineOn: (() -> boolean)?,
	onOutline: (() -> boolean)?,
	notify: ((text: string) -> ())?,
	onClose: (() -> ())?, -- PUT PHONE AWAY
	onTour: ((kind: string) -> ())?,
	keys: ((list: Instance, look: OrdersUi.Kit, order: number) -> ())?, -- PhoneApps.keys
}

-- MESSAGES' sub-view: the message open whole (its index), nil the list.
PhoneMore.open = nil :: number?
-- 6.20: CAREER's tab: "road" or "skills".
PhoneMore.careerTab = "road"

-- An app glyph as a picture (client/PhoneContract.luau).
local function glyph(id: string): CardKit.Picture
	return { glyph = function(face: Instance, size: number)
		PhoneContract.glyph(face, id, size)
	end }
end

-- The hero and the rows of an app: side by side in a wide popup, else stacked. Returns the left and right columns.
local function columns(list: Instance, name: string, ctx: Ctx, hero: boolean): (any, any, number)
	local height = CardKit.Layout.heroHeight(ctx.room)
	local _, left, right = CardKit.columns(list, { name = name, order = 1, side = ctx.wide, hero = hero, heroHeight = height })
	return left, right, height
end

-- ── CAREER ───────────────────────────────────────────────────────────────

function PhoneMore.career(list: Instance, _look: OrdersUi.Kit, ctx: Ctx)
	local xp = ctx.xp or 0
	local level = ctx.level or 1
	-- 6.20: the ROAD / SKILLS tabs (the free points on SKILLS' chip)
	local free = SkillsView.free(ctx.skills, level)
	CardKit.tabList(list, { { id = "road", text = "ROAD" }, { id = "skills", text = if free > 0 then `SKILLS · {free}` else "SKILLS" } }, function(id: string)
		if id ~= PhoneMore.careerTab then
			PhoneMore.careerTab = id
			SkillsView.open = nil
			ctx.redraw()
		end
	end, PhoneMore.careerTab)
	if PhoneMore.careerTab == "skills" then
		SkillsView.draw(list, { wide = ctx.wide, level = level, skills = ctx.skills or {}, heroHeight = math.min(CardKit.Layout.heroHeight(ctx.room), 200), redraw = ctx.redraw }, 1)
		return
	end
	local road = Career.road()
	local owned = ctx.cars or {}
	local nextStep = road[level + 1]
	local left, right, height = columns(list, "CareerView", ctx, true)
	local function full()
		local open = ctx.onCareer
		if open then
			open()
		end
	end
	local action = { name = "FullCareer", text = if Ui.touchLayout() then "FULL CAREER" else "FULL CAREER  [C]", kind = "primary", onClick = full }
	if nextStep then
		local xpLeft = math.max(0, nextStep.xp - xp)
		local toGo = ctx.toGo
		local work = if toGo then toGo(xpLeft, level) else nil
		local reward = Career.rewardParts(nextStep.reward)
		local facts = { if work then `about {work}` else "deliveries give XP" }
		if reward[1] then
			table.insert(facts, `🎁 {reward[1]}`)
		end
		CardKit.hero(left, {
			name = "NextLevel",
			height = height,
			picture = glyph("career"),
			title = `NEXT: LEVEL {nextStep.level}{if nextStep.newRank then ` · {string.upper(nextStep.rank)}` else ""}`,
			value = `{string.sub(Career.money(xpLeft), 2)} XP`,
			valueColor = C.gold,
			facts = table.concat(facts, " · "),
			bar = { share = Levels.progress(xp), color = C.gold },
			ribbon = { text = `LV {level} · {string.upper(Levels.rank(level))}`, face = K.raised, ink = K.text },
			corner = { text = `LV {level} / {Config.Levels.MaxLevel}`, ink = K.text, width = 96 },
			action = action,
			onOpen = full,
			silent = true,
		})
	else
		CardKit.hero(left, {
			name = "NextLevel",
			height = height,
			picture = glyph("career"),
			title = string.upper(Levels.rank(level)),
			value = `LEVEL {level}`,
			valueColor = C.gold,
			facts = "The top of the road",
			ribbon = { text = "🏆 TOP LEVEL", face = C.gold, ink = C.goldInk },
			action = action,
			onOpen = full,
			silent = true,
		})
	end
	-- What the next level unlocks, then the road ahead (three more levels).
	CardKit.sectionHeader(right, { name = "RoadHead", text = "THE ROAD AHEAD", order = 0 })
	local order = 0
	for n = level + 2, math.min(level + 4, Config.Levels.MaxLevel) do
		local step = road[n]
		if not step then
			break
		end
		order += 1
		local summary = Career.summary(step.unlocks, 3, owned)
		local reward = step.reward
		CardKit.row(right, {
			name = `Level_{n}`,
			order = order,
			accent = K.line,
			picture = { emoji = tostring(n) },
			thumb = KIT.Icon,
			emojiSize = 20,
			shut = true,
			title = `LEVEL {n}{if step.newRank then ` · {string.upper(step.rank)}` else ""}`,
			facts = if summary ~= "" then summary else "better pay and harder roads",
			value = if reward and reward.money and reward.money > 0 then Career.money(reward.money) else nil,
			valueColor = C.money,
			lock = `🔒 LV {n}`,
			silent = true,
			onOpen = full,
		})
	end
	if order == 0 then
		CardKit.sectionHeader(right, { name = "RoadEnd", text = "THE TOP OF THE ROAD IS CLOSE", order = 1 })
	end
end

-- ── BANK ─────────────────────────────────────────────────────────────────

function PhoneMore.bank(list: Instance, _look: OrdersUi.Kit, ctx: Ctx)
	local left, right, height = columns(list, "BankView", ctx, true)
	CardKit.hero(left, {
		name = "Balance",
		height = height,
		picture = glyph("bank"),
		title = "ZDC COURIER ACCOUNT",
		value = Ui.money(ctx.money or 0),
		valueColor = C.money,
		facts = "Deliveries pay into it",
		ribbon = { text = "AVAILABLE CASH", face = C.goodFace, ink = C.money },
		action = { name = "FindDelivery", text = "FIND A DELIVERY", kind = "primary", onClick = function()
			local board = ctx.onBoard
			if board then
				board()
			end
		end },
		onOpen = function() end,
		silent = true,
	})
	CardKit.row(right, {
		name = "Earned",
		order = 1,
		accent = K.good,
		picture = { emoji = "💵" },
		thumb = KIT.Icon,
		title = "EARNED SINCE YOU JOINED",
		facts = "This session",
		value = `+{Ui.money(ctx.earned or 0)}`,
		valueColor = C.money,
		silent = true,
		onOpen = function() end,
	})
end

-- ── MESSAGES ─────────────────────────────────────────────────────────────

local function avatar(message: Message): CardKit.Picture
	local face = if message.kind == "marge" then K.red elseif message.kind == "level" then K.text else K.charcoal
	return { emoji = string.upper(string.sub(message.from, 1, 1)), face = face }
end

function PhoneMore.messages(list: Instance, look: OrdersUi.Kit, ctx: Ctx)
	local messages = ctx.messages or {}
	if #messages == 0 then
		PhoneMore.open = nil
		look.emptyState(list, "✉️", "No messages yet", nil, 1)
		return
	end
	local open = PhoneMore.open
	local message = if open then messages[open] else nil
	if message then
		-- One message whole: ‹ MESSAGES, who and when, the words.
		CardKit.details(list, look, { back = "‹ MESSAGES", name = "BackToMessages", order = 1, onBack = function()
			PhoneMore.open = nil
			ctx.redraw()
		end, draw = function(into: Instance, order: number)
			local card = look.block(into, order)
			card.Parent.Name = "Message"
			look.caps(card, `{message.from} · {message.time}`, 1, K.secondary)
			look.text(card, message.text, UDim2.new(1, 0, 0, 0), { Name = "Words", AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextSize = 15 })
		end })
		return
	end
	PhoneMore.open = nil
	CardKit.sectionHeader(list, { name = "RecentHead", text = "RECENT", order = 0 })
	local order = 0
	for index = #messages, 1, -1 do
		local entry = messages[index]
		order += 1
		local made = CardKit.row(list, {
			name = "Message",
			order = order,
			accent = if entry.unread then K.red else K.line,
			picture = avatar(entry),
			thumb = KIT.Icon,
			emojiSize = 18,
			title = `{string.upper(entry.from)} · {entry.time}`,
			titleColor = if entry.unread then K.text else nil,
			facts = entry.text,
			factsColor = if entry.unread then K.text else nil,
			action = "›",
			onOpen = function()
				PhoneMore.open = index
				ctx.redraw()
			end,
		})
		if entry.unread then
			local dot = Ui.make("Frame", { Name = "Unread", Size = UDim2.fromOffset(8, 8), Position = UDim2.new(1, -54, 0, 10), BackgroundColor3 = K.red, BorderSizePixel = 0, ZIndex = 3 }, made.row)
			Ui.corner(dot, 4)
		end
		local thumb = made.thumb:FindFirstChild("Emoji")
		if thumb and entry.kind == "level" then
			thumb.TextColor3 = K.charcoal
		end
	end
end

-- ── SETTINGS ─────────────────────────────────────────────────────────────

-- A setting's row: its emoji, its name, one line, and its action's word (the row and the word act).
local function setting(parent: Instance, name: string, order: number, emoji: string, title: string, facts: string, word: string, button: string, act: () -> ())
	local made = CardKit.row(parent, {
		name = name,
		order = order,
		accent = K.line,
		picture = { emoji = emoji },
		thumb = KIT.Icon,
		title = title,
		facts = facts,
		word = word,
		onAction = act,
		silent = true,
		onOpen = function()
			CardKit.click()
			act()
		end,
	})
	if made.action then
		made.action.Name = button
	end
end

function PhoneMore.settings(list: Instance, look: OrdersUi.Kit, ctx: Ctx)
	CardKit.sectionHeader(list, { name = "SettingsHead", text = "PHONE", order = 0 })
	local rows = Ui.make("Frame", { Name = "Settings", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, list)
	Ui.list(rows, true, KIT.Gap)
	setting(rows, "SoundRow", 1, "🔊", "SOUND", "Everything on → music off → all off", "CYCLE", "CycleSound", function()
		local cycle = ctx.onSound
		if cycle then
			cycle()
		end
	end)
	local outlineOn, onOutline = ctx.outlineOn, ctx.onOutline -- 6.15: the enemies' subtle outline (client/EnemyOutline.luau)
	if outlineOn and onOutline then
		setting(rows, "OutlineRow", 2, "🧟", "ENEMY OUTLINES", "Zombies red, bandits orange", if outlineOn() then "ON" else "OFF", "Outlines", function()
			local now = onOutline()
			local notify = ctx.notify
			if notify then
				notify(if now then "Enemy outlines on: zombies red, bandits orange" else "Enemy outlines off")
			end
			ctx.redraw()
		end)
	end
	local tour = ctx.onTour -- 6.7: Marge's tours again (client/TutorialUi.luau: the phone closes first)
	if tour then
		setting(rows, "TourScreen", 3, "🗺️", "SHOW ME THE SCREEN", "Marge points at the HUD again", "›", "ShowScreen", function()
			tour("screen")
		end)
		setting(rows, "TourAround", 4, "🚶", "SHOW ME AROUND", "Marge's walk around the depot", "›", "ShowAround", function()
			tour("around")
		end)
	end
	local away = CardKit.bigButton(list, { name = "PutAway", text = "PUT PHONE AWAY", order = 2, onClick = function()
		local close = ctx.onClose
		if close then
			close()
		end
	end })
	away.Size = UDim2.new(1, 0, 0, KIT.Button)
	look.meta(list, if Ui.touchLayout() then "Tap an app to open it; the ✕ or a tap beside it returns to the phone." else "Q opens the phone; Q, ESC or the ✕ close an app, then the phone. Hold right mouse to turn the camera.", 3).Name = "Controls"
	local keys = ctx.keys
	if keys then
		keys(list, look, 4) -- 5.5: every key, the version
	end
end

return PhoneMore
