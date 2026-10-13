-- 7.0, the moves' story: runs the real client/MovingHud.luau with client/MoveStoryUi.luau (and client/Portrait.luau,
-- client/CardKit.luau, the real shared data) on tools/phone-ui/missions_mock.luau's recorder, through the Moving
-- remote's messages: the contract card without an intro (the profile not loaded, or the intro seen), Marge's intro the
-- first time (her portrait, the pages, NEXT by the keys and by a tap, the server told it was seen, then the card), the
-- card's CHAPTERS (the story road: the prologue ▶ PLAY, six chapters and the finale 🔒 SOON, a tap shows a chapter's
-- hook), START through the briefing (✕ back to the card, Big Move Movers on the radio as its last card, SKIP starts),
-- a briefed chapter starting at once, the client's thanks on the result card by the outcome, and the story card on a
-- phone (in the middle, never wider than the screen, a finger's buttons). Behaviour, not looks: Studio shows those.
local M = require("./missions_mock")

-- The stand-ins MovingHud needs on top of the MISSIONS window's (its prompts' services, the touch rules, the fade).
local function signal()
	return M.signal()
end
M.services.CollectionService = {
	GetTagged = function()
		return {}
	end,
	GetInstanceAddedSignal = function()
		return signal()
	end,
	GetInstanceRemovedSignal = function()
		return signal()
	end,
	HasTag = function()
		return false
	end,
}
M.services.ProximityPromptService = { PromptShown = signal() }
M.scale = 1
M.MUi.closeButton = M.Ui.closeButton
M.MUi.screenScale = function()
	return M.scale
end
M.MUi.touchLayout = function()
	return M.touch
end
M.MTheme.PanelTransparency = 0.12
M.MTheme.WindowTransparency = 0.02
M.keys = {}
M.MKeys = {
	open = function(id, advance, options)
		M.keys[id] = { advance = advance, options = options }
	end,
	close = function(id)
		M.keys[id] = nil
	end,
	isOpen = function(id)
		return M.keys[id] ~= nil
	end,
	hint = function()
		return "SPACE"
	end,
}
M.MFade = { out = function() end, into = function() end }

local MoveStory = require("./MoveStory")
local Config = require("./Config")
local MovingHud = require("./MovingHud")
local MoveStoryUi = require("./MoveStoryUi")

local function check(name, condition, detail)
	if not condition then
		error(`FAIL {name}{if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""}`)
	end
	print("ok    " .. name)
end
local function all(root, predicate)
	local out = {}
	local function visit(object)
		if predicate(object) then
			table.insert(out, object)
		end
		for _, child in object:GetChildren() do
			visit(child)
		end
	end
	visit(root)
	return out
end
local function named(root, name)
	return all(root, function(object)
		return object.Name == name
	end)[1]
end
local function has(root, pattern)
	return #all(root, function(object)
		return type(object.Text) == "string" and string.find(object.Text, pattern, 1, true) ~= nil
	end) > 0
end
local function sentOn(remote)
	local list = {}
	for _, entry in M.sent do
		if entry.name == remote then
			table.insert(list, entry.args)
		end
	end
	return list
end
local function press(object)
	object.Activated:Fire()
end

local prologue = MoveStory.Chapters[1]
local remote = M.remotes.Moving or M.Net.get("Moving")
local card = {
	id = "marge",
	name = "Marge's House",
	client = "Marge",
	icon = "🏠",
	blurb = Config.Moving.Contracts[1].blurb,
	address = "155 Willow Ln",
	stars = { "🕰️ Grandfather Clock", "📔 Family Photos", "🐴 Rocking Horse" },
	items = 20,
	estimate = 9000,
	time = Config.Moving.Time,
	hordeAt = Config.Moving.HordeAt,
	truck = "Moving Truck",
	crew = 0,
}
local function story()
	return named(M.gui, "StoryCard")
end
local function contractCard()
	return named(M.gui, "MoveContract")
end
local function page()
	local label = named(story(), "Page")
	return label and label.Text
end

MovingHud.start()
check("MovingHud starts on the recorder (its panel hidden)", named(M.gui, "MovePanel") ~= nil and named(M.gui, "MovePanel").Visible == false)

-- No intro: the profile not loaded yet, or the intro seen -------------------------------------------------------------

M.player:SetAttribute("MoveStory", nil)
remote.OnClientEvent:Fire("contract", card)
check("the profile not loaded (no MoveStory attribute): the card at once, no intro", contractCard() ~= nil and story() == nil)
press(named(contractCard(), "Close"))
M.player:SetAttribute("MoveStory", "intro")
remote.OnClientEvent:Fire("contract", card)
check("the intro seen (MoveStory = \"intro\"): the card at once", contractCard() ~= nil and story() == nil)
press(named(contractCard(), "Close"))
check("the card closed: nothing open", not MovingHud.isOpen())

-- Marge's intro, the first time, on a phone ---------------------------------------------------------------------------

M.touch, M.width, M.height, M.scale = true, 844, 390, 0.55
M.player:SetAttribute("MoveStory", "")
remote.OnClientEvent:Fire("contract", card)
local intro = story()
check("the first board: Marge's intro before the card", intro ~= nil and contractCard() == nil and MoveStoryUi.isOpen() and MovingHud.isOpen())
check("… her portrait, her name, the company, the line", named(intro, "PortraitBack") ~= nil and has(intro, "MARGE") and has(intro, string.upper(MoveStory.Company))
	and has(intro, MoveStory.Intro[1].text) and has(intro, "ZDC Moving & Evacuation"))
check("… page 1 / 4, SKIP and NEXT, no ✕ (no way back)", page() == `1 / {#MoveStory.Intro}` and named(intro, "Skip") ~= nil and named(intro, "Next").Text == "NEXT ›"
	and named(intro, "Close") == nil)
local scale = named(intro, "Scale").Scale
local width = intro.Size.X.Offset
check("a phone: in the middle, readable (0.8), never wider than the screen", intro.AnchorPoint.X == 0.5 and intro.AnchorPoint.Y == 0.5 and scale == 0.8
	and width * scale <= M.width - 2 * 16 * scale, width * scale)
check("… a finger's buttons (52)", named(intro, "Footer").Size.Y.Offset == 52)
check("… the keys turn the pages (Space / Enter / A)", M.keys.movestory ~= nil and M.keys.movestory.options.guard == Config.MoveStory.Guard)
check("… the gamepad lands on NEXT", M.focus == named(intro, "Next"))
M.width, M.height = 360, 740 -- (a narrow phone held upright for the next page)
M.keys.movestory.advance()
intro = story()
check("page 2: Captain Maria on the Wall (her own portrait and role)", page() == `2 / {#MoveStory.Intro}` and has(intro, "CAPTAIN MARIA") and has(intro, MoveStory.Intro[2].text)
	and has(intro, "Base commander · Military Base"))
check("… a narrow phone: the card fits, the portrait smaller", intro.Size.X.Offset * 0.8 <= 360 - 2 * 16 * 0.8 + 0.01 and named(intro, "Face").Size.X.Offset == 84, intro.Size.X.Offset)
press(intro)
press(named(story(), "Next"))
intro = story()
check("a tap on the card or NEXT turns the page; the last says SHOW ME THE JOB, no SKIP", page() == `4 / {#MoveStory.Intro}` and named(intro, "Next").Text == "SHOW ME THE JOB"
	and named(intro, "Skip") == nil)
check("… nothing told the server yet", #sentOn("Tutorial") == 0)
press(named(intro, "Next"))
local told = sentOn("Tutorial")
check("the intro's end: the server keeps it seen (Tutorial: story, intro)", #told == 1 and told[1][1] == "story" and told[1][2] == "intro")
check("… and the contract card opens after it", story() == nil and contractCard() ~= nil and M.keys.movestory == nil)
press(named(contractCard(), "Close"))
remote.OnClientEvent:Fire("contract", card)
check("once a game: the next board opens on the card (the attribute may come later)", story() == nil and contractCard() ~= nil)

-- The card's CHAPTERS -------------------------------------------------------------------------------------------------

M.touch, M.width, M.height, M.scale = false, 1280, 800, 1
press(named(contractCard(), "Close"))
remote.OnClientEvent:Fire("contract", card)
local chaptersBox = named(contractCard(), "MoveStoryChapters")
check("the card: THE LAST MOVE · CHAPTERS under START", chaptersBox ~= nil and chaptersBox.LayoutOrder > named(contractCard(), "Start").LayoutOrder
	and has(chaptersBox, "THE LAST MOVE · CHAPTERS") and has(chaptersBox, "1 OF 8 OPEN"))
local road = named(chaptersBox, "Road")
local tiles = {}
for _, child in road:GetChildren() do
	if child.ClassName == "TextButton" then
		table.insert(tiles, child)
	end
end
check("the story road scrolls sideways: a tile for every chapter, in order", road.ClassName == "ScrollingFrame" and road.ScrollingDirection.Name == "X" and #tiles == #MoveStory.Chapters
	and tiles[1].Name == "Chapter_prologue" and tiles[#tiles].Name == "Chapter_finale")
local first = named(road, "Chapter_prologue")
check("the prologue: ▶ PLAY, its title, Marge, her portrait, lit (it is this contract)", has(first, "▶ PLAY") and has(first, prologue.title) and has(first, "Marge") and has(first, "PROLOGUE")
	and named(first, "PortraitBack") ~= nil and named(first, "Lit").Transparency == 0)
local soon = 0
for index = 2, #MoveStory.Chapters do
	local chapter = MoveStory.Chapters[index]
	local made = named(road, `Chapter_{chapter.id}`)
	if made and has(made, "🔒 SOON") and has(made, chapter.title) and has(made, chapter.client) and has(made, MoveStory.label(chapter)) then
		soon += 1
	end
end
check("the six chapters and the finale: 🔒 SOON with their title, client and label", soon == #MoveStory.Chapters - 1, soon)
local detail = named(chaptersBox, "Detail")
check("under the road: Marge's blurb for this contract", string.find(detail.Text, prologue.blurb, 1, true) ~= nil)
press(named(road, "Chapter_ranch"))
local ranch = MoveStory.Chapters[2]
check("a tap on Walt's chapter: its hook, SOON, its tile lit (the prologue's not)", string.find(detail.Text, ranch.hook, 1, true) ~= nil and string.find(detail.Text, "SOON", 1, true) ~= nil
	and named(named(road, "Chapter_ranch"), "Lit").Transparency == 0 and named(first, "Lit").Transparency > 0.5)

-- START through the briefing ------------------------------------------------------------------------------------------

local startsBefore = #sentOn("Moving")
press(named(contractCard(), "StartMove"))
local brief = story()
local pages = #prologue.briefing + 1
check("START: the card closes, the prologue's briefing opens, nothing started yet", contractCard() == nil and brief ~= nil and #sentOn("Moving") == startsBefore
	and has(brief, "PROLOGUE · EVERYTHING MUST GO") and has(brief, prologue.briefing[1].text) and page() == `1 / {pages}`)
check("… on a computer: low in the middle, over the bottom bar", brief.AnchorPoint.Y == 1 and named(brief, "Footer").Size.Y.Offset == 40)
press(named(brief, "Close"))
check("its ✕: back to the contract card, still not started", story() == nil and contractCard() ~= nil and #sentOn("Moving") == startsBefore)
press(named(contractCard(), "StartMove"))
for _ = 1, pages - 1 do
	M.keys.movestory.advance()
end
brief = story()
check("its last card: Big Move Movers on the radio (Dana, her taunt), ▶ START THE MOVE", page() == `{pages} / {pages}` and has(brief, "ON THE RADIO") and has(brief, "DANA")
	and has(brief, prologue.taunt) and named(brief, "Next").Text == "▶ START THE MOVE" and has(brief, "Boss · Big Move Movers"))
press(named(brief, "Close"))
press(named(contractCard(), "StartMove"))
check("✕ again, START again: the briefing again (not finished)", story() ~= nil and page() == `1 / {pages}`)
press(named(story(), "Skip"))
local starts = sentOn("Moving")
check("SKIP: the move starts (Moving: start, marge)", story() == nil and #starts == startsBefore + 1 and starts[#starts][1] == "start" and starts[#starts][2] == "marge"
	and not MovingHud.isOpen())
remote.OnClientEvent:Fire("contract", card)
press(named(contractCard(), "StartMove"))
starts = sentOn("Moving")
check("briefed this game: START starts at once", story() == nil and contractCard() == nil and #starts == startsBefore + 2 and starts[#starts][1] == "start")

-- The result card's thanks --------------------------------------------------------------------------------------------

remote.OnClientEvent:Fire("state", {
	id = 1, contract = "marge", name = "Marge's House", icon = "🏠", client = "Marge", owner = "Courier", mine = true,
	endsAt = M.now + 600, hordeAt = M.now + 420, seconds = Config.Moving.Time, horde = false, items = {},
	counts = { total = 20, out = 4, stars = 3, starsOut = 3, broken = 0, carried = 0, home = 16 }, fill = 0.4,
	truck = true, backOpen = false, house = { x = 0, z = 0 }, door = { x = 0, z = 0 }, dropOff = { x = 40, z = 40 }, inside = false,
})
local function result(how, stars)
	return { name = "Marge's House", icon = "🏠", how = how, howText = "", delivered = 4, left = 16, broken = 0, total = 20, starsOut = 3, starsTotal = 3, stars = stars,
		pay = 4000, money = 4000, xp = 300, base = 3000, starBonus = 600, timeBonus = 400, fine = 0, crew = 1 }
end
remote.OnClientEvent:Fire("result", result("done", 5))
local resultCard = named(M.gui, "MoveResult")
local thanks = resultCard and named(resultCard, "MoveStoryThanks")
check("a great move: Marge's thanks on the result card, by her portrait, above OK", thanks ~= nil and has(thanks, prologue.thanks.great) and has(thanks, "MARGE")
	and named(thanks, "PortraitBack") ~= nil and thanks.LayoutOrder < named(resultCard, "Ok").LayoutOrder)
remote.OnClientEvent:Fire("state", nil)
remote.OnClientEvent:Fire("result", result("done", 2))
check("a so-so one (the move's state gone: found by the contract's name): her ok line", has(named(M.gui, "MoveResult"), prologue.thanks.ok))
remote.OnClientEvent:Fire("result", result("late", 3))
check("late: the late line", has(named(M.gui, "MoveResult"), prologue.thanks.late))
remote.OnClientEvent:Fire("result", result("failed", 0))
check("lost: the failed line", has(named(M.gui, "MoveResult"), prologue.thanks.failed))
local other = result("done", 5)
other.name = "Somebody's Flat"
remote.OnClientEvent:Fire("result", other)
check("a contract without a chapter: no thanks row", named(M.gui, "MoveResult") ~= nil and named(M.gui, "MoveStoryThanks") == nil)
check("no warnings (every portrait a 3D bust)", #M.warnings == 0, M.warnings[1])
print("ALL MOVESTORY CHECKS PASSED")
