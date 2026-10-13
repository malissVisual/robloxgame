-- 7.0, the moves' story "The Last Move" (shared/MoveStory.luau, Config.MoveStory): every chapter complete (the client,
-- the place, the hook, the keepsakes, the briefing, the taunt, Marge's texts and the client's thanks for every
-- outcome), unique ids and titles, every text non-empty and inside its card's limit, a valid unlock order, the prologue
-- the one playable chapter (its contract on the board), the speakers real people (shared/Cast.luau, Dana of Big Move
-- Movers), the outcomes, the phone texts, the seen flags of the save; then the real server/Moving.luau (MovingServer
-- on tests/runtime/MovingRuntime.luau's fakes) sends Marge's texts through its MoveStory hook at START and at the end.
local MoveStory = require("./MoveStory")
local Config = require("./Config")
local Cast = require("./Cast")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local L = Config.MoveStory.Limits
local chapters = MoveStory.Chapters

-- A text: a string, not blank, no stray spaces at its ends, at most `limit` characters (★ counts as one).
local function fits(text: any, limit: number): (boolean, string)
	if type(text) ~= "string" then
		return false, "not a string"
	end
	local length = utf8.len(text) or #text
	if string.match(text, "^%s*$") then
		return false, "blank"
	elseif string.match(text, "^%s") or string.match(text, "%s$") then
		return false, `spaces at the ends: "{text}"`
	elseif length > limit then
		return false, `{length} > {limit}: "{text}"`
	end
	return true, ""
end
local function checkText(name: string, text: any, limit: number)
	local ok, why = fits(text, limit)
	check(name, ok, if ok then nil else why)
end
-- A sentence ends like one.
local function sentence(text: string): boolean
	return string.match(text, "[%.!%?']$") ~= nil
end

-- The story road ------------------------------------------------------------------------------------------------------

check("eight chapters: the prologue, six chapters, the finale", #chapters == 8, #chapters)
local ids, titles = {}, {}
for index, chapter in chapters do
	check(`{chapter.id}: its number is its place on the road ({index - 1})`, chapter.number == index - 1, chapter.number)
	check(`{chapter.id}: a unique id`, ids[chapter.id] == nil and string.match(chapter.id, "^%l+$") ~= nil)
	ids[chapter.id] = true
	check(`{chapter.id}: a unique title`, titles[chapter.title] == nil)
	titles[chapter.title] = true
end
check("the labels: PROLOGUE, CHAPTER 1 … 6, FINALE", MoveStory.label(chapters[1]) == "PROLOGUE" and MoveStory.label(chapters[2]) == "CHAPTER 1"
	and MoveStory.label(chapters[7]) == "CHAPTER 6" and MoveStory.label(chapters[8]) == "FINALE")
check("the clients of the owner's design, in its order", (function()
	local want = { "marge", "walt", "ellie", "raj", "rosa", "ivan", "ruth", "marge" }
	for index, chapter in chapters do
		if chapter.clientId ~= want[index] then
			return false
		end
	end
	return chapters[5].partnerId == "rico" and chapters[6].partnerId == "hiro"
end)())

-- Every chapter complete ----------------------------------------------------------------------------------------------

for _, chapter in chapters do
	local id = chapter.id
	checkText(`{id}: the title`, chapter.title, L.Title)
	checkText(`{id}: the place`, chapter.place, L.Place)
	checkText(`{id}: the client's name`, chapter.client, L.Client)
	checkText(`{id}: the icon`, chapter.icon, 4)
	local person = Cast.find(chapter.clientId)
	check(`{id}: the client is a Cast person (the portrait)`, person ~= nil, chapter.clientId)
	check(`{id}: the partner too`, chapter.partnerId == nil or Cast.find(chapter.partnerId) ~= nil, chapter.partnerId)
	-- (the name on the cards: theirs, at least the last word of it: "Ivan" of Engineer Ivan; the finale is everybody's)
	local partner = if chapter.partnerId then Cast.find(chapter.partnerId) else nil
	local function named(who: Cast.Person?): boolean
		local first = if who then string.match(who.name, "(%S+)$") else nil
		return first ~= nil and string.find(chapter.client, first, 1, true) ~= nil
	end
	check(`{id}: the name on the cards is theirs`, (named(person) and (chapter.partnerId == nil or named(partner))) or chapter.id == "finale", chapter.client)
	local c = chapter.color
	check(`{id}: a colour`, #c == 3 and c[1] >= 0 and c[1] <= 255 and c[2] >= 0 and c[2] <= 255 and c[3] >= 0 and c[3] <= 255)
	checkText(`{id}: the hook`, chapter.hook, L.Hook)
	local _, sentences = string.gsub(chapter.hook, "[%.!%?] ", "")
	check(`{id}: the hook is two or three sentences`, sentence(chapter.hook) and sentences >= 1 and sentences <= 2, sentences + 1)
	checkText(`{id}: the client's blurb`, chapter.blurb, L.Blurb)
	check(`{id}: three or four keepsakes (the ★ things)`, #chapter.keepsakes >= 3 and #chapter.keepsakes <= 4, #chapter.keepsakes)
	for _, keepsake in chapter.keepsakes do
		check(`{id}: keepsake {keepsake.item} is an item id`, string.match(keepsake.item, "^[%l_]+$") ~= nil)
		checkText(`{id}: keepsake {keepsake.item}'s name`, keepsake.name, L.Title + 6)
		checkText(`{id}: keepsake {keepsake.item}'s story`, keepsake.story, L.Keepsake)
	end
	local B = Config.MoveStory.Briefing
	check(`{id}: a briefing of {B[1]} to {B[2]} lines`, #chapter.briefing >= B[1] and #chapter.briefing <= B[2], #chapter.briefing)
	local clientSpeaks = false
	for index, line in chapter.briefing do
		check(`{id}: briefing line {index} has a speaker`, MoveStory.speaker(line.who) ~= nil, line.who)
		checkText(`{id}: briefing line {index}`, line.text, L.Line)
		if line.who == chapter.clientId or line.who == chapter.partnerId then
			clientSpeaks = true
		end
	end
	check(`{id}: the client speaks in the briefing (or it is Marge's own)`, clientSpeaks or chapter.id == "finale")
	checkText(`{id}: Big Move Movers' taunt`, chapter.taunt, L.Line)
	checkText(`{id}: Marge's text at the start`, chapter.dispatch, L.Text)
	for _, outcome in MoveStory.Outcomes do
		checkText(`{id}: Marge's debrief ({outcome})`, (chapter.debrief :: any)[outcome], L.Text)
		checkText(`{id}: the client's thanks ({outcome})`, (chapter.thanks :: any)[outcome], L.Quote)
	end
end

-- The unlock order ----------------------------------------------------------------------------------------------------

check("the prologue needs nothing", #chapters[1].requires == 0)
for index, chapter in chapters do
	if index > 1 then
		local earlier = true
		for _, need in chapter.requires do
			local other = MoveStory.find(need)
			if not other or other.number >= chapter.number then
				earlier = false
			end
		end
		check(`{chapter.id}: it needs only chapters before it`, #chapter.requires >= 1 and earlier)
		check(`{chapter.id}: it needs the chapter right before it`, table.find(chapter.requires, chapters[index - 1].id) ~= nil)
	end
end
check("the finale needs every chapter", #chapters[8].requires == 7)

-- Playable now: the prologue only -------------------------------------------------------------------------------------

local prologue = chapters[1]
local contract = Config.Moving.Contracts[1]
check("the prologue plays Marge's House (Config.Moving.Contracts)", MoveStory.status(prologue) == "play" and prologue.contract == contract.id and prologue.soon ~= true)
for index = 2, #chapters do
	local chapter = chapters[index]
	check(`{chapter.id}: 🔒 SOON (no contract yet)`, chapter.soon == true and MoveStory.status(chapter) == "soon")
end
check("the contract by its id and by its name (the result card's)", MoveStory.forContract("marge") == prologue and MoveStory.forContract(contract.name) == prologue
	and MoveStory.forContract("nobody") == nil and MoveStory.forContract(nil) == nil and MoveStory.forContract("") == nil)
check("every contract on the board has its chapter", (function()
	for _, c in Config.Moving.Contracts do
		if not MoveStory.forContract(c.id) then
			return false
		end
	end
	return true
end)())
check("Marge's House's keepsakes: the furniture's four sentimental pieces, Grandpa's clock first", prologue.keepsakes[1].item == "grandfather_clock"
	and string.find(prologue.keepsakes[1].story, "father built it", 1, true) ~= nil and #prologue.keepsakes == 4)
check("… her briefing names the three ★ pieces of her house (seed 1955: the clock, the record player, the rocking horse)", (function()
	local said = ""
	for _, line in prologue.briefing do
		said ..= string.lower(line.text) .. " "
	end
	for index = 1, 3 do
		local name = string.gsub(string.lower(prologue.keepsakes[index].name), "^the ", "")
		if not string.find(said, name, 1, true) then
			return false
		end
	end
	return string.find(said, "photo", 1, true) == nil
end)())
check("Marge's text at its start", MoveStory.dispatchText("marge") == "Grandpa's clock is in the living room. Don't you dare drop it.")

-- The intro, the speakers, the villain --------------------------------------------------------------------------------

local I = Config.MoveStory.Intro
check(`Marge's intro: {I[1]} to {I[2]} cards, hers first and last`, #MoveStory.Intro >= I[1] and #MoveStory.Intro <= I[2] and MoveStory.Intro[1].who == "marge"
	and MoveStory.Intro[#MoveStory.Intro].who == "marge")
local introText = ""
for index, line in MoveStory.Intro do
	check(`intro card {index} has a speaker`, MoveStory.speaker(line.who) ~= nil, line.who)
	checkText(`intro card {index}`, line.text, L.Line)
	introText ..= line.text .. " "
end
check("the intro tells the evacuation, the Wall and the new name", string.find(introText, "evacuat", 1, true) ~= nil and string.find(introText, "Wall", 1, true) ~= nil
	and string.find(introText, MoveStory.Company, 1, true) ~= nil and string.find(introText, MoveStory.Tagline, 1, true) ~= nil)
local dana = MoveStory.speaker(MoveStory.Villain.id)
check("Dana speaks for Big Move Movers (a mover's look)", dana ~= nil and dana.name == "Dana" and dana.look == "mover")
check("… the boss of Config.Employers' Big Move Movers", (function()
	for _, employer in Config.Employers do
		if employer.id == "movers" then
			return string.find(employer.person, MoveStory.Villain.name, 1, true) == 1 and employer.name == MoveStory.Villain.place
		end
	end
	return false
end)())
check("an unknown speaker is nobody", MoveStory.speaker("nobody") == nil)

-- The outcomes and the texts ------------------------------------------------------------------------------------------

local G = Config.MoveStory.Great
check("done with Great stars or more: great; fewer: ok", MoveStory.outcome("done", G) == "great" and MoveStory.outcome("done", 5) == "great" and MoveStory.outcome("done", G - 1) == "ok"
	and MoveStory.outcome("done", nil) == "ok")
check("late: late; called off, lost or anything else: failed", MoveStory.outcome("late", 5) == "late" and MoveStory.outcome("cancelled", 5) == "failed"
	and MoveStory.outcome("failed", 1) == "failed" and MoveStory.outcome(nil, nil) == "failed")
check("Marge's debrief and the client's thanks follow the outcome", MoveStory.debriefText("marge", "done", 5) == prologue.debrief.great
	and MoveStory.debriefText("Marge's House", "done", 2) == prologue.debrief.ok and MoveStory.thanksLine("marge", "late", 3) == prologue.thanks.late
	and MoveStory.thanksLine("marge", "cancelled", 0) == prologue.thanks.failed)
check("no chapter, no text", MoveStory.dispatchText("nowhere") == nil and MoveStory.debriefText("nowhere", "done", 5) == nil and MoveStory.thanksLine(nil, "done", 5) == nil)
check("the phone's sender is Marge (a Cast name)", Cast.named(MoveStory.Sender) ~= nil)

-- The seen flags (the save, the attribute) ----------------------------------------------------------------------------

check("the intro is a seen key, nothing else is", MoveStory.isSeenKey("intro") and not MoveStory.isSeenKey("money") and not MoveStory.isSeenKey(1) and not MoveStory.isSeenKey(nil))
local cleaned = MoveStory.cleanSeen({ intro = true, money = true, [1] = true })
check("a saved table keeps only known keys set to true", cleaned.intro == true and (cleaned :: any).money == nil and next(MoveStory.cleanSeen({ intro = "yes" })) == nil
	and next(MoveStory.cleanSeen(nil)) == nil and next(MoveStory.cleanSeen("intro")) == nil)
check("encoded for the attribute and back", MoveStory.encodeSeen({ intro = true }) == "intro" and MoveStory.encodeSeen({}) == "" and MoveStory.encodeSeen(nil) == ""
	and MoveStory.decodeSeen("intro").intro == true and next(MoveStory.decodeSeen("")) == nil and next(MoveStory.decodeSeen("bogus,,x")) == nil
	and next(MoveStory.decodeSeen(nil)) == nil)

-- The real server/Moving.luau: Marge's texts through the MoveStory hook -----------------------------------------------

local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local Map = require("./Map")
local T = Config.Moving
local V3 = E.Mock.Vector3.new

local home = Map.home(T.Contracts[1].home) :: any
E.truckAt = V3(home.park.x, 2, home.park.z)
local depot = V3(Map.Depot.x, 3, Map.Depot.z)
local ann = E.player(11, "Ann", depot)
local bob = E.player(22, "Bob", depot + V3(3, 0, 0))
local cid = E.player(33, "Cid", depot + V3(-90, 0, 0))
E.crew[ann] = { bob }
Moving.useArt(E.art)
Moving.start()

-- Marge's texts to `player` (the Tutorial remote's "message"), in order.
local function texts(player: any): { any }
	local list = {}
	for _, m in E.messages do
		if m.player == player and m.remote == "Tutorial" and m.kind == "message" then
			table.insert(list, m.a)
		end
	end
	return list
end

Moving.admin(ann, "start")
Moving.step()
local annTexts, bobTexts = texts(ann), texts(bob)
check("START: Marge texts the owner about Grandpa's clock", #annTexts == 1 and annTexts[1].from == "Marge" and annTexts[1].text == prologue.dispatch, #annTexts)
check("… and the crew too, a stranger nothing", #bobTexts == 1 and bobTexts[1].text == prologue.dispatch and #texts(cid) == 0)
check("… on the phone only: no toast of its own (the move's toasts stay as they were)", (function()
	for _, m in E.messages do
		if m.remote == "Notice" and string.find(tostring(m.kind), "Grandpa's clock", 1, true) then
			return false
		end
	end
	return true
end)())
Moving.admin(ann, "deliver")
annTexts = texts(ann)
local result = E.last(ann, "Moving", "result")
local delivered = MoveStory.outcome(result and result.a.how, result and result.a.stars)
check("delivered: her debrief for the outcome, after the result card", #annTexts == 2 and annTexts[2].text == (prologue.debrief :: any)[delivered] and #texts(bob) == 2, delivered)
Moving.admin(ann, "start")
Moving.step()
Moving.admin(ann, "time")
E.now += 61
Moving.step()
annTexts = texts(ann)
check("the clock ran out: the late debrief", #annTexts == 4 and annTexts[3].text == prologue.dispatch and annTexts[4].text == prologue.debrief.late, #annTexts)
Moving.admin(ann, "start")
Moving.step()
Moving.admin(ann, "end")
annTexts = texts(ann)
check("called off: the failed one", #annTexts == 6 and annTexts[6].text == prologue.debrief.failed, #annTexts)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
