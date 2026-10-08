-- 6.8: runs the real MISSIONS window (client/MissionsUi.luau, client/MissionsLayout.luau, client/Portrait.luau) with
-- the shared data against recorded instances (tools/phone-ui/missions_mock.luau): the clients' cards, the chosen
-- client's chapter (the hero, the action card, the story path, the finale's reward), START, the locks, a replay, the
-- DUO chapter, a phone's narrow layout, the banner and the cleared card. Behaviour, not looks: Studio shows those.
local M = require("./missions_mock")
local Missions = require("./Missions")
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
check("a shut chapter says why: Ellie waits for Marge's chapter", has(named(clients, "clinic"), "🔒 Finish Marge's chapter first"))
check("… the DUO chapter says so", has(named(clients, "duo"), "🤝 DUO"))
check("the hero: Marge, her role and place, the pitch", named(chapter, "Hero") ~= nil and has(named(chapter, "Hero"), "Marge") and has(named(chapter, "Hero"), "Dispatcher  ·  Dead End Dispatch"))
local action = named(chapter, "Action")
check("the action card shows the next mission: Dead Letter Office, its briefing, FIRST TIME pay", has(action, "▶ NEXT · MISSION 4 OF 6") and has(action, "Dead Letter Office") and has(action, "Timmy's uncle Percy") and has(action, "FIRST TIME"))
-- 6.8 review: START and the pay line in the action bar under the chapter (never scrolled away).
local bar = named(window, "ActionBar")
local start = button(bar, "START ▶")
check("a big START in the action bar with the pay, selected for a gamepad", start ~= nil and start.Name == "Start" and M.focus == start and has(bar, "FIRST TIME · ≈") and has(bar, "XP") and has(bar, "Dead Letter Office"))
-- START is in view: in the bar (not in a scrolling list) under the chapter, inside the window's content.
local function startInView(): (boolean, string)
	local now = named(bar, "Start")
	if not now or not bar.Visible or not now.Visible then
		return false, "no START"
	end
	local node = now.Parent
	while node and node ~= window do
		if node.ClassName == "ScrollingFrame" then
			return false, "START in a scrolling list"
		end
		node = node.Parent
	end
	local content = named(window, "Content")
	local contentH = window.Size.Y.Offset + content.Size.Y.Offset -- (the window less its header and footer)
	local top, bottom = bar.Position.Y.Offset, bar.Position.Y.Offset + bar.Size.Y.Offset
	local chapterBottom = chapter.Position.Y.Offset + chapter.Size.Y.Offset
	local wide = bar.Position.X.Offset + bar.AbsoluteSize.X
	local ok = top >= chapterBottom and bottom <= contentH and now.Size.Y.Offset <= bar.Size.Y.Offset
		and now.Size.X.Offset + 10 <= bar.AbsoluteSize.X and wide <= window.Size.X.Offset
	return ok, `bar {top} – {bottom} of {contentH}, chapter ends {chapterBottom}`
end
check("… START in view at 1280 × 800: under the chapter, inside the window", startInView())
-- 6.8 review: the server's reply to ("open") (the same state) draws nothing again: START keeps the selection.
M.remotes.Missions.OnClientEvent:Fire("state", state)
M.flush()
check("the same state again: nothing rebuilt, START still selected", start.Parent ~= nil and named(chapter, "Action") == action and M.focus == start)
-- A state that changes the page rebuilds it: the selection goes back to the new START (its Name).
state.capacity = 3
M.remotes.Missions.OnClientEvent:Fire("state", state)
M.flush()
check("a new state rebuilds: the new START selected", start.Parent == nil and M.focus == named(bar, "Start") and M.focus ~= nil)
state.capacity = 2
M.remotes.Missions.OnClientEvent:Fire("state", state)
M.flush()
start = button(bar, "START ▶")
local path = {}
for _, def in Missions.ofCampaign("dispatch") do
	table.insert(path, named(chapter, def.id))
end
check("the story path: six steps in order", #path == 6)
check("… done ones replay: REPLAY and their stars", has(path[1], "REPLAY") and has(path[1], "★★★"))
check("… the next one: FIRST TIME and its XP", has(path[4], "FIRST TIME") and has(path[4], "XP"))
check("… later ones locked: Finish \"Dead Letter Office\" first", has(path[5], "🔒 Finish \"Dead Letter Office\" first") and has(path[6], "🔒"))
check("the finale's reward: money, the Dispatch Yellow paint, the title", has(named(chapter, "Finale"), "Dispatch Yellow paint") and has(named(chapter, "Finale"), "Dispatcher's Favourite"))
start.Activated:Fire()
local sent = M.sent[#M.sent]
check("START asks the server for the next mission", sent.name == "Missions" and sent.args[1] == "start" and sent.args[2] == "dispatch_8")

-- A done mission on the path: PLAY AGAIN at the replay's pay. 6.8 review: chosen with a gamepad, the step keeps it.
M.focus = path[2]
path[2].Activated:Fire()
M.flush()
action = named(chapter, "Action")
check("a done mission clicked on the path: PLAY AGAIN, REPLAY pay", button(bar, "PLAY AGAIN ▶") ~= nil and has(bar, "REPLAY · ≈") and has(action, "REPLAY") and has(action, "✓ DONE · MISSION 2 OF 6"))
check("… the gamepad's selection back on that step (rebuilt)", path[2].Parent == nil and M.focus ~= nil and M.focus.Name == "dispatch_2" and M.focus.Parent ~= nil)
-- A locked one: START is off and says why.
path[6].Activated:Fire()
check("a locked one: why beside START", has(bar, "🔒 Finish \"Dead Letter Office\" first"))

-- Another client: Rosa & Rico (open after First Shift's finale at level 6).
state.progress = { dispatch_1 = 3, dispatch_2 = 2, dispatch_3 = 1, dispatch_8 = 2, dispatch_9 = 1, dispatch_10 = 1 }
state.level = 6
M.remotes.Missions.OnClientEvent:Fire("state", state)
M.flush()
-- 6.8 review: a client chosen with a gamepad keeps the selection on its (rebuilt) card.
local duoCard = named(clients, "duo")
M.focus = duoCard
duoCard.Activated:Fire()
M.flush()
action = named(chapter, "Action")
check("the twins: both names, NEEDS A PARTNER, START waits for a partner", has(named(chapter, "Hero"), "Rosa & Rico") and has(named(chapter, "Hero"), "NEEDS A PARTNER") and has(bar, "NEEDS A PARTNER") and button(bar, "🔎 FIND CREW") ~= nil)
check("… the gamepad's selection back on the twins' card", duoCard.Parent == nil and M.focus ~= nil and M.focus.Name == "duo" and M.focus.Parent == clients)
named(clients, "clinic").Activated:Fire()
M.flush()
check("Ellie's chapter opens after Marge's: NEW, her first mission next", has(named(clients, "clinic"), "NEW") and has(named(chapter, "Action"), "House Call"))
named(clients, "exodus").Activated:Fire()
M.flush()
check("a far chapter: shut, says what to do and GO TO", has(named(chapter, "Action"), "IS STILL SHUT") and has(bar, "IS STILL SHUT") and button(bar, "GO TO DOCTOR ELLIE ▶") ~= nil)
M.focus = button(bar, "GO TO DOCTOR ELLIE ▶")
M.focus.Activated:Fire()
M.flush()
check("… GO TO opens that client, the gamepad's selection on its START", named(clients, "clinic"):GetAttribute("Selected") == true and M.focus == named(bar, "Start"))

-- A phone held sideways: the clients on a strip on top, the chapter under them.
M.width, M.height = 667, 339
M.workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Fire()
M.flush()
local list = clients:FindFirstChildOfClass("UIListLayout")
check("narrow: the clients become a strip on top", list.FillDirection == M.Enum.FillDirection.Horizontal and clients.Position.Y.Offset < chapter.Position.Y.Offset and not named(M.gui, "Column").Visible)
check("… the slim chrome (no subtitle), still every card and the chapter", not named(window, "Subtitle").Visible and #all(clients, function(object)
	return object.ClassName == "TextButton"
end) == #Missions.Campaigns and named(chapter, "Hero") ~= nil)
check("… START in view on an iPhone SE sideways (6.8 review)", startInView())
check("… a small hero portrait (6.8 review)", named(named(chapter, "Hero"), "Portrait").Size.X.Offset <= 80)
M.width, M.height = 1280, 684
M.workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Fire()
M.flush()
check("back on a monitor: the column again", list.FillDirection == M.Enum.FillDirection.Vertical and named(M.gui, "Column").Visible)
check("… START in view at 1280 × 720 (6.8 review)", startInView())

-- The other tabs still work.
named(window, "challengesTab").Activated:Fire()
M.flush()
check("CHALLENGES: the chapter page hides", not clients.Visible and not chapter.Visible and not bar.Visible)
named(window, "missionsTab").Activated:Fire()
M.flush()
check("MISSIONS again", clients.Visible and chapter.Visible and bar.Visible)

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
check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL MISSIONS WINDOW CHECKS PASSED")
