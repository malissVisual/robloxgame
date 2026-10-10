-- 6.8: runs the real MISSIONS window (client/MissionsUi.luau, client/MissionsLayout.luau, client/Portrait.luau) with
-- the shared data against recorded instances (tools/phone-ui/missions_mock.luau): the clients' cards, the chosen
-- client's chapter (the hero, the action card, the story path, the finale's reward), START, the locks, a replay, the
-- DUO chapter, a phone's narrow layout, the banner and the cleared card. Behaviour, not looks: Studio shows those.
-- 6.12.13: the chapter's picture banner (client/MissionArtUi.luau, shared/MissionArt.luau): a fallback business
-- picture, a chapter's own, a dimmed shut one, none for a chapter without one, on a phone above the story path.
-- 6.18 (the UI kit, client/CardKit.luau): the tabs as chips, the clients as compact rows, the chapter as ONE hero (the
-- next mission: its picture or its emoji's mark, the pay big, START / PLAY AGAIN / GET READY / FIND CREW / GO TO, START
-- in view on every screen) beside the missions' rows (stars, the pay big, the lock), the finale's reward a row, the
-- details (ⓘ: 6.8's banner, client and action card, ‹ BACK) and GET READY through MissionsUi.onGetReady.
local M = require("./missions_mock")
local Missions = require("./Missions")
local MissionArt = require("./MissionArt")
local JobThumbs = require("./JobThumbs")
local Portrait = require("./Portrait")
local MissionsUi = require("./MissionsUi")

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
local function texts(root)
	local list = {}
	for _, object in all(root, function(object)
		return type(object.Text) == "string" and object.Text ~= ""
	end) do
		table.insert(list, object.Text)
	end
	return list
end
local function has(root, pattern)
	for _, text in texts(root) do
		if string.find(text, pattern, 1, true) then
			return true
		end
	end
	return false
end
local function button(root, text)
	return all(root, function(object)
		return object.ClassName == "TextButton" and object.Text == text
	end)[1]
end

-- ── The portraits ─────────────────────────────────────────────────────────────
do
	local holder = M.make("Frame", { Name = "Holder" }, M.gui)
	local ok = Portrait.mount(holder, Portrait.people("ellie"), M.Color3.fromRGB(240, 80, 80))
	local back = holder:FindFirstChild("PortraitBack")
	local viewport = back and back:FindFirstChild("Portrait")
	local busts = viewport and viewport:FindFirstChild("Busts")
	check("a client's portrait is a 3D bust in a ViewportFrame over the chapter's colour", ok and viewport ~= nil and viewport.ClassName == "ViewportFrame" and viewport.CurrentCamera ~= nil and busts ~= nil and #busts:GetChildren() == 1, M.warnings[1])
	local bust = busts:GetChildren()[1]
	check("… dressed like the NPC: Doctor Ellie's coat and tie, a face", named(bust, "CoatFront") ~= nil and named(bust, "Tie") ~= nil and named(bust, "face") ~= nil and named(bust, "Head") ~= nil)
	check("… the same portrait twice is not rebuilt", Portrait.mount(holder, Portrait.people("ellie"), M.Color3.fromRGB(240, 80, 80)) and holder:FindFirstChild("PortraitBack") == back)
	local twins = M.make("Frame", { Name = "Twins" }, M.gui)
	Portrait.mount(twins, Portrait.people("rosa", "rico"), M.Color3.fromRGB(236, 92, 60))
	check("the DUO twins: two busts side by side", #named(twins, "Busts"):GetChildren() == 2)
	local carlos = M.make("Frame", { Name = "Carlos" }, M.gui)
	Portrait.mount(carlos, Portrait.people("carlos"), M.Color3.fromRGB(255, 120, 40))
	check("Chief Carlos wears the fire helmet", named(carlos, "Hardhat") ~= nil)
	local flat = M.make("Frame", { Name = "Flat" }, M.gui)
	Portrait.flat(flat, M.Color3.fromRGB(110, 200, 90), "grocer", true)
	check("the flat stand-in: a silhouette and the role's emoji", has(flat, "🛒"))
	for _, frame in { holder, twins, carlos, flat } do
		frame:Destroy()
	end
end

-- ── The window ────────────────────────────────────────────────────────────────
-- 6.18: the MISSIONS page in the UI kit (client/CardKit.luau): the tabs as chips, the clients as compact rows, the
-- chosen chapter as ONE hero (the next mission: the picture, the name, the pay big, START / GET READY) beside the
-- missions' rows, the finale's reward a row; ⓘ opens 6.8's chapter (the banner, the client, the action card).
local Kit = require("./CardKit")
MissionsUi.start()
local state = {
	progress = { dispatch_1 = 3, dispatch_2 = 2, dispatch_3 = 1, dispatch_4 = 3 }, -- (dispatch_4: a retired id of an old save)
	level = 4, hasCar = true, capacity = 2, carName = "Old Van", carId = "van", carStage = 0, crewSize = 0,
}
M.remotes.Missions.OnClientEvent:Fire("state", state)
MissionsUi.open()
M.flush()
local window = named(M.gui, "Window")
local clients = named(M.gui, "Clients")
local chapter = named(M.gui, "Chapter")
check("U opens the window on the MISSIONS page", MissionsUi.isOpen() and window.Visible and clients.Visible and chapter.Visible)
check("6.18: the page tabs are the kit's chips, MISSIONS lit; the stars a chip", named(window, "missionsTab") ~= nil and named(window, "missionsTab"):FindFirstChildOfClass("UIStroke").Transparency == 0
	and named(window, "challengesTab"):FindFirstChildOfClass("UIStroke").Transparency > 0.5 and has(named(window, "Tabs"), "CHALLENGES") and string.find(named(window, "Stars").Text, "★ ", 1, true) == 1)
check("… no action bar under the chapter any more (START is the hero's)", named(window, "ActionBar") == nil)
local cards = {}
for _, child in clients:GetChildren() do
	if child.ClassName == "TextButton" then
		table.insert(cards, child)
	end
end
check("a card for every client (11), each with a portrait", #cards == #Missions.Campaigns and #all(clients, function(object)
	return object.Name == "PortraitBack"
end) == #Missions.Campaigns, #cards)
check("the story's place: Marge's chapter is chosen, 3 / 6 done", named(clients, "dispatch"):GetAttribute("Selected") == true and has(named(clients, "dispatch"), "3 / 6"))
check("6.18: a client card is the kit's compact row: its edge in the chapter's colour, its name in caps", named(named(clients, "dispatch"), "Edge") ~= nil and has(named(clients, "dispatch"), "MARGE")
	and named(clients, "dispatch"):FindFirstChildOfClass("UICorner") ~= nil)
check("a shut chapter says why: Ellie waits for Marge's chapter", has(named(clients, "clinic"), "🔒 Finish Marge's chapter first"))
check("… the DUO chapter says so", has(named(clients, "duo"), "🤝 DUO"))
local function orders(): { [number]: number }
	local seen = {}
	for _, child in chapter:GetChildren() do
		if child:IsA("GuiObject") then
			seen[child.LayoutOrder] = (seen[child.LayoutOrder] or 0) + 1
		end
	end
	return seen
end
local function distinct(): boolean
	for _, count in orders() do
		if count > 1 then
			return false
		end
	end
	return true
end
local hero = named(chapter, "Hero")
check("6.18: the chapter is the kit's hero beside the rows (a chapter 600 px wide)", hero ~= nil and named(chapter, "Cards") ~= nil
	and named(chapter, "Cards"):FindFirstChildOfClass("UIListLayout").FillDirection == M.Enum.FillDirection.Horizontal and hero.Parent.Name == "Left" and distinct())
check("… the hero: Marge and n/N on the ribbon, the next mission's name, FIRST TIME, the pay big in green", has(hero, "MARGE · 4/6") and has(hero, "DEAD LETTER OFFICE")
	and named(hero, "Countdown").Text == "FIRST TIME" and string.match(named(hero, "Pay").Text, "^%$[%d,]+$") ~= nil and named(hero, "Pay").TextColor3 == Kit.Color.money)
check("… one facts line: the zombies, the cargo, the first-time XP; the chapter's bar", string.find(named(hero, "Facts").Text, "🧟", 1, true) ~= nil and has(hero, "XP") and named(hero, "Progress") ~= nil)
-- 6.12.13: First Shift has no picture yet (Dead End Dispatch has no business picture): its emoji is the hero's mark.
check("no picture for First Shift yet: the chapter's emoji as the hero's mark, no banner", named(hero, "Picture") == nil and named(hero, "Emoji") ~= nil and named(chapter, "ChapterArt") == nil)
-- START: the hero's one button (green), selected for a gamepad.
local start = button(chapter, "START ▶")
check("a big START in the hero (green), selected for a gamepad", start ~= nil and start.Name == "Start" and start:IsDescendantOf(hero) and M.focus == start and start.BackgroundColor3 == M.MTheme.Contract.good)
-- 6.18: START in view: the hero heads the chapter, no taller than the chapter's view (MissionsLayout.heroRoom).
local function startInView(): (boolean, string)
	local now = named(chapter, "Start")
	local card = named(chapter, "Hero")
	if not now or not card or not now.Visible then
		return false, "no START"
	end
	local content = named(window, "Content")
	local contentH = window.Size.Y.Offset + content.Size.Y.Offset -- (the window less its header and footer)
	local holder = named(chapter, "Cards")
	local first = math.huge
	for _, child in chapter:GetChildren() do
		if child:IsA("GuiObject") then
			first = math.min(first, child.LayoutOrder)
		end
	end
	local ok = now:IsDescendantOf(card) and holder.LayoutOrder == first and card.Size.Y.Offset <= chapter.Size.Y.Offset - 13
		and chapter.Position.Y.Offset + chapter.Size.Y.Offset <= contentH and card.Size.Y.Offset >= 150
	return ok, `hero {card.Size.Y.Offset} in a view of {chapter.Size.Y.Offset}, the chapter ends {chapter.Position.Y.Offset + chapter.Size.Y.Offset} of {contentH}`
end
check("… START in view at 1280 × 800: the hero heads the chapter, as tall as its view at most", startInView())
-- ⓘ: the chapter's details (6.8's client card and action card).
named(hero, "Details").Activated:Fire()
M.flush()
local action = named(chapter, "Action")
check("6.18 ⓘ: the details: ‹ BACK on top", named(chapter, "Back") ~= nil and named(chapter, "Back").LayoutOrder == 0)
check("… the client and the action card as in 6.8", named(chapter, "Client") ~= nil and has(named(chapter, "Client"), "Marge") and has(named(chapter, "Client"), "Dispatcher  ·  Dead End Dispatch")
	and action ~= nil and has(action, "▶ NEXT · MISSION 4 OF 6") and has(action, "Dead Letter Office") and has(action, "Timmy's uncle Percy") and has(action, "FIRST TIME") and named(chapter, "Hero") == nil)
named(chapter, "Back").Activated:Fire()
M.flush()
hero = named(chapter, "Hero")
start = button(chapter, "START ▶")
check("… ‹ BACK: the hero and the rows again", hero ~= nil and named(chapter, "Action") == nil and start ~= nil)
M.focus = start
-- 6.8 review: the server's reply to ("open") (the same state) draws nothing again: START keeps the selection.
M.remotes.Missions.OnClientEvent:Fire("state", state)
M.flush()
check("the same state again: nothing rebuilt, START still selected", start.Parent ~= nil and named(chapter, "Hero") == hero and M.focus == start)
-- A state that changes the page rebuilds it: the selection goes back to the new START (its Name).
state.capacity = 3
M.remotes.Missions.OnClientEvent:Fire("state", state)
M.flush()
check("a new state rebuilds: the new START selected", start.Parent == nil and M.focus == named(chapter, "Start") and M.focus ~= nil)
state.capacity = 2
M.remotes.Missions.OnClientEvent:Fire("state", state)
M.flush()
start = button(chapter, "START ▶")
local path = {}
for _, def in Missions.ofCampaign("dispatch") do
	table.insert(path, named(chapter, def.id))
end
check("the story: six rows in order", #path == 6 and path[1].LayoutOrder < path[6].LayoutOrder and path[1].Parent.Name == "Right")
check("… done ones replay: REPLAY and their stars", has(path[1], "REPLAY") and has(path[1], "★★★"))
check("… the next one: FIRST TIME and its XP, its pay big, the hero's (raised)", has(path[4], "FIRST TIME") and has(path[4], "XP") and named(path[4], "Pay") ~= nil and path[4]:GetAttribute("Selected") == true)
check("… later ones locked: Finish \"Dead Letter Office\" first, the pay dim, the lock", has(path[5], "🔒 Finish \"Dead Letter Office\" first") and has(path[6], "🔒")
	and named(path[5], "Pay").TextColor3 == Kit.Color.dim and named(path[5], "Add").Text == "🔒")
check("the finale's reward: money, the Dispatch Yellow paint, the title", has(named(chapter, "Finale"), "Dispatch Yellow paint") and has(named(chapter, "Finale"), "Dispatcher's Favourite")
	and named(named(chapter, "Finale"), "Pay").TextColor3 == Kit.Color.gold)
start.Activated:Fire()
local sent = M.sent[#M.sent]
check("START asks the server for the next mission", sent.name == "Missions" and sent.args[1] == "start" and sent.args[2] == "dispatch_8")

-- A done mission's row: the hero shows it, PLAY AGAIN at the replay's pay. 6.8 review: chosen with a gamepad, it keeps it.
M.focus = path[2]
path[2].Activated:Fire()
M.flush()
hero = named(chapter, "Hero")
check("a done mission tapped: the hero on it, PLAY AGAIN, ✓ and its stars, REPLAY", button(chapter, "PLAY AGAIN ▶") ~= nil and has(hero, "MARGE · 2/6") and named(hero, "Countdown").Text == "✓ ★★☆" and has(hero, "↻ REPLAY"))
check("… the gamepad's selection back on that row (rebuilt)", path[2].Parent == nil and M.focus ~= nil and M.focus.Name == "dispatch_2" and M.focus.Parent ~= nil)
-- A locked one: the hero's button is grey and its facts say why.
path = {}
for _, def in Missions.ofCampaign("dispatch") do
	table.insert(path, named(chapter, def.id))
end
path[6].Activated:Fire()
M.flush()
check("a locked one: why in the hero's facts, its button grey", has(named(chapter, "Hero"), "🔒 Finish \"Dead Letter Office\" first") and button(chapter, "🔒 LOCKED") ~= nil
	and button(chapter, "🔒 LOCKED").BackgroundColor3 == Kit.Buttons.shut.face)

-- 6.18: GET READY: something missing (no car of yours) opens the phone's READY CHECK (MissionsUi.onGetReady).
do
	named(chapter, "dispatch_8").Activated:Fire() -- (the chapter's next one in the hero again)
	M.flush()
	state.hasCar = false
	M.remotes.Missions.OnClientEvent:Fire("state", state)
	M.flush()
	local ready = button(chapter, "GET READY ›")
	local asked = nil
	MissionsUi.onGetReady = function(id)
		asked = id
	end
	check("6.18: not ready (on foot): GET READY in red, why in the facts", ready ~= nil and ready.Name == "Start" and ready.BackgroundColor3 == M.MTheme.Contract.red and has(named(chapter, "Hero"), "🚐"))
	ready.Activated:Fire()
	check("… GET READY opens the READY CHECK for that mission", asked == "dispatch_8")
	MissionsUi.onGetReady = nil
	state.hasCar = true
	M.remotes.Missions.OnClientEvent:Fire("state", state)
	M.flush()
end

-- Another client: Rosa & Rico (open after First Shift's finale at level 6).
state.progress = { dispatch_1 = 3, dispatch_2 = 2, dispatch_3 = 1, dispatch_8 = 2, dispatch_9 = 1, dispatch_10 = 1 }
state.level = 6
M.remotes.Missions.OnClientEvent:Fire("state", state)
M.flush()
-- 6.8 review: a client chosen with a gamepad keeps the selection on its (rebuilt) card.
local duoCard = named(clients, "duo")
M.focus = duoCard
MissionArt.Images.duo = "rbxassetid://4242" -- (6.12.13: as if the chapter's own picture were uploaded)
duoCard.Activated:Fire()
M.flush()
hero = named(chapter, "Hero")
check("a chapter's own picture (uploaded) fills the hero", named(hero, "Picture") ~= nil and named(hero, "Picture").Image == "rbxassetid://4242" and named(hero, "Picture").ScaleType.Name == "Crop")
check("the twins: both names, NEEDS A PARTNER, FIND CREW is the hero's button", has(hero, "ROSA & RICO") and has(hero, "NEEDS A PARTNER") and button(chapter, "🔎 FIND CREW") ~= nil
	and button(chapter, "🔎 FIND CREW"):IsDescendantOf(hero) and button(chapter, "START ▶") == nil)
check("… the gamepad's selection back on the twins' card", duoCard.Parent == nil and M.focus ~= nil and M.focus.Name == "duo" and M.focus.Parent == clients)
named(hero, "Details").Activated:Fire()
M.flush()
local duoArt = named(chapter, "ChapterArt")
check("… ⓘ: the chapter's banner, the twins on the label", duoArt ~= nil and named(duoArt, "Picture").Image == "rbxassetid://4242"
	and duoArt:GetAttribute("Art") == "chapter" and has(duoArt, "🤝  PARTNERS IN CRIME") and has(duoArt, "Rosa & Rico  ·  Survivor Camp"))
MissionArt.Images.duo = ""
named(clients, "clinic").Activated:Fire()
M.flush()
check("Ellie's chapter opens after Marge's: NEW, her first mission in the hero (a client opens on the hero)", has(named(clients, "clinic"), "NEW") and has(named(chapter, "Hero"), "HOUSE CALL") and named(chapter, "Back") == nil)
-- 6.12.13: Code Red opens with the City Clinic's picture (the job list's, until the chapter's own is uploaded).
local picture = named(named(chapter, "Hero"), "Picture")
check("Code Red's hero: the City Clinic's picture, cropped", picture ~= nil and picture.Image == JobThumbs.Images.clinic and picture.Image ~= "" and picture.ScaleType.Name == "Crop"
	and picture.ImageColor3 == Kit.Color.white)
check("… START still in view", startInView())
named(named(chapter, "Hero"), "Details").Activated:Fire()
M.flush()
local art = named(chapter, "ChapterArt")
check("… its details open with the banner above the client", art ~= nil and named(art, "Picture").Image == JobThumbs.Images.clinic and art:GetAttribute("Art") == "clinic"
	and art.LayoutOrder < named(chapter, "Client").LayoutOrder and distinct())
check("… the chapter's and the client's names on a dark label, a dark gradient under it", has(art, "🏥  CODE RED") and has(art, "Doctor Ellie  ·  City Clinic")
	and named(art, "Label").BackgroundTransparency < 0.5 and named(art, "Rule") ~= nil and named(art, "Shade"):FindFirstChildOfClass("UIGradient") ~= nil)
local artWide = art.AbsoluteSize.X
check("… about 2.6 : 1 across the chapter, never over the layout's art", math.abs(artWide / art.Size.Y.Offset - 2.6) < 0.05 and art.Size.Y.Offset <= 260, `{artWide} × {art.Size.Y.Offset}`)
named(chapter, "Back").Activated:Fire()
M.flush()
named(clients, "market").Activated:Fire()
M.flush()
hero = named(chapter, "Hero")
check("a shut chapter's hero: its picture greyed (Empty Shelves: FreshMart), IS STILL SHUT, the reward dim", named(hero, "Picture") ~= nil and named(hero, "Picture").ImageColor3 == Kit.Color.grey
	and has(hero, "IS STILL SHUT") and named(hero, "Pay").TextColor3 == Kit.Color.dim)
named(clients, "exodus").Activated:Fire()
M.flush()
hero = named(chapter, "Hero")
check("a far chapter: shut, says what to do and GO TO", has(hero, "IS STILL SHUT") and button(chapter, "GO TO DOCTOR ELLIE ▶") ~= nil and button(chapter, "GO TO DOCTOR ELLIE ▶"):IsDescendantOf(hero))
check("… no picture for Last Convoy yet: its emoji, no banner", named(hero, "Picture") == nil and named(chapter, "ChapterArt") == nil and distinct())
M.focus = button(chapter, "GO TO DOCTOR ELLIE ▶")
M.focus.Activated:Fire()
M.flush()
check("… GO TO opens that client, the gamepad's selection on its START", named(clients, "clinic"):GetAttribute("Selected") == true and M.focus == named(chapter, "Start"))

-- 6.14 review: the Roof Rack's slots count for light pieces in the window too (the state's gear), as the server counts
-- them: Empty Shelves' first mission takes 3 bags of groceries, the Old Van holds 2.
do
	local saved, savedLevel = state.progress, state.level
	local open = {}
	for _, id in { "dispatch", "clinic" } do
		for _, def in Missions.ofCampaign(id) do
			open[def.id] = 2
		end
	end
	state.progress, state.level = open, 6
	M.remotes.Missions.OnClientEvent:Fire("state", state)
	M.flush()
	named(clients, "market").Activated:Fire()
	M.flush()
	check("6.14 review: 3 bags of groceries in an Old Van that holds 2: needs 3 slots, GET READY", has(chapter, "needs 3 slots") and button(chapter, "GET READY ›") ~= nil)
	state.gear = { roofrack = true }
	M.remotes.Missions.OnClientEvent:Fire("state", state)
	M.flush()
	check("… with the Roof Rack (2 more slots for light pieces): room, START", not has(chapter, "needs 3 slots") and button(chapter, "START ▶") ~= nil)
	state.gear, state.progress, state.level = nil, saved, savedLevel
	M.remotes.Missions.OnClientEvent:Fire("state", state)
	M.flush()
	named(clients, "clinic").Activated:Fire()
	M.flush()
end

-- A phone held sideways: the clients on a strip on top, the chapter under them (its hero still beside the rows).
M.width, M.height = 667, 339
M.workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Fire()
M.flush()
local list = clients:FindFirstChildOfClass("UIListLayout")
check("narrow: the clients become a strip on top", list.FillDirection == M.Enum.FillDirection.Horizontal and clients.Position.Y.Offset < chapter.Position.Y.Offset and not named(M.gui, "Column").Visible)
check("… the slim chrome (no subtitle), still every card and the chapter", not named(window, "Subtitle").Visible and #all(clients, function(object)
	return object.ClassName == "TextButton"
end) == #Missions.Campaigns and named(chapter, "Hero") ~= nil)
check("… START in view on an iPhone SE sideways (6.8 review; 6.18: the hero no taller than the view)", startInView())
check("6.18: … the hero still beside the rows (the chapter is 875 px wide at the window's scale)", named(chapter, "Cards"):FindFirstChildOfClass("UIListLayout").FillDirection == M.Enum.FillDirection.Horizontal)
named(named(chapter, "Hero"), "Details").Activated:Fire()
M.flush()
local phoneArt = named(chapter, "ChapterArt")
check("… Code Red's banner in the details, short enough for the chapter's view", phoneArt ~= nil and phoneArt.Size.Y.Offset <= 132 and distinct(), phoneArt and phoneArt.Size.Y.Offset)
named(chapter, "Back").Activated:Fire()
M.flush()
M.width, M.height = 1280, 684
M.workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Fire()
M.flush()
check("back on a monitor: the column again", list.FillDirection == M.Enum.FillDirection.Vertical and named(M.gui, "Column").Visible)
check("… START in view at 1280 × 720 (6.8 review)", startInView())
check("… the hero's picture again", named(named(chapter, "Hero"), "Picture") ~= nil)

-- The other tabs still work.
named(window, "challengesTab").Activated:Fire()
M.flush()
check("CHALLENGES: the chapter page hides, its chip lit", not clients.Visible and not chapter.Visible and named(window, "challengesTab"):FindFirstChildOfClass("UIStroke").Transparency == 0)
named(window, "missionsTab").Activated:Fire()
M.flush()
check("MISSIONS again", clients.Visible and chapter.Visible and named(chapter, "Hero") ~= nil)

-- The banner during a mission: "MISSION 3/6".
M.remotes.Job.OnClientEvent:Fire({ mission = { id = "clinic_4", name = "Many Hands", campaign = "clinic", number = 3, of = 6, twists = { "lift" }, coop = true } })
local banner = named(M.gui, "MissionBanner")
check("the banner: 3/6 and the twist", banner.Visible and has(banner, "3/6") and has(banner, "TWO-MAN LIFT"))
M.remotes.Job.OnClientEvent:Fire(nil)

-- The cleared card: a replay says what it paid; the first time its reward and XP.
MissionsUi.close()
M.remotes.Missions.OnClientEvent:Fire("cleared", { id = "dispatch_2", name = "Mail Call", number = 2, of = 6, stars = 2, best = 2, newStars = 0, replay = true, paid = 55, reward = 0, xp = 0, nextId = "clinic_1" })
M.resume()
local cleared = named(M.gui, "MissionCleared")
check("a replay's card: REPLAY · $55, no reward", cleared ~= nil and cleared.Visible and has(cleared, "REPLAY  ·  $55") and not has(cleared, "First time"))
M.remotes.Missions.OnClientEvent:Fire("cleared", { id = "clinic_1", name = "House Call", number = 1, of = 6, stars = 3, best = 3, newStars = 3, first = true, replay = false, paid = 180, reward = 550, xp = 120, starBonus = 450, nextId = "clinic_2" })
M.resume()
check("a first clear's card: FIRST CLEAR!, the reward, the XP, NEXT: Code Blue", has(cleared, "FIRST CLEAR!") and has(cleared, "First time  +$550") and has(cleared, "First-time XP  +120") and button(cleared, "NEXT: Code Blue ▶") ~= nil)
check("6.19: … House Call unlocks nothing: no NEW line", not named(cleared, "Unlocks").Visible)
-- 6.19: Mail Call's first clear unlocks the SMG: "🔓 NEW: SMG at Lead & Co.'s range" and the GPS to the range.
M.remotes.Missions.OnClientEvent:Fire("cleared", { id = "dispatch_2", name = "Mail Call", number = 2, of = 6, stars = 2, best = 2, newStars = 2, first = true, replay = false, paid = 120, reward = 550, xp = 100, nextId = "dispatch_3" })
M.resume()
check("6.19: Mail Call's first clear: 🔓 NEW: SMG at Lead & Co.'s range, 📍 GPS: LEAD & CO.'S RANGE", named(cleared, "Unlocks").Visible and has(named(cleared, "Unlocks"), "🔓 NEW: SMG at Lead &amp; Co.'s range")
	and button(cleared, "📍 GPS: LEAD & CO.'S RANGE") ~= nil and button(cleared, "📍 GPS: LEAD & CO.'S RANGE").Visible)
M.remotes.Missions.OnClientEvent:Fire("cleared", { id = "dispatch_2", name = "Mail Call", number = 2, of = 6, stars = 2, best = 2, newStars = 0, replay = true, paid = 55, reward = 0, xp = 0, nextId = "dispatch_3" })
M.resume()
check("6.19: … its replay: no NEW line", not named(cleared, "Unlocks").Visible)
-- 6.19: MISSIONS says what a mission unlocks: the finale's hero "🔓 Unlocks: Shotgun"; openMission opens it.
do
	local saved, savedLevel = state.progress, state.level
	state.progress, state.level = { dispatch_1 = 3, dispatch_2 = 2, dispatch_3 = 1, dispatch_8 = 1, dispatch_9 = 1 }, 5
	M.remotes.Missions.OnClientEvent:Fire("state", state)
	MissionsUi.openMission("dispatch_10")
	M.flush()
	check("6.19: openMission opens MISSIONS on Rush Hour of the Dead, its hero: 🔓 Unlocks: Shotgun", MissionsUi.isOpen() and has(named(chapter, "Hero"), "RUSH HOUR OF THE DEAD")
		and has(named(chapter, "Hero"), "🔓 Unlocks: Shotgun"))
	state.progress, state.level = saved, savedLevel
	M.remotes.Missions.OnClientEvent:Fire("state", state)
end
check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL MISSIONS WINDOW CHECKS PASSED")
