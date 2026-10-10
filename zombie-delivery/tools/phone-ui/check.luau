-- Integration regressions execute the actual client modules with recorded native UI instances.
local M=require("./mock")
local Phone=require("./Phone")
local function check(name,condition) assert(condition,name);print("ok    "..name) end
local function all(root,predicate)
	local out={}
	local function visit(object)
		if predicate(object) then table.insert(out,object) end
		for _,child in object:GetChildren() do visit(child) end
	end
	visit(root);return out
end
local function named(name) return all(M.gui,function(object) return object.Name==name end)[1] end
local function text(value) return all(M.gui,function(object) return object.Text==value end)[1] end
-- (a caps label: the real one writes it in capitals, the recorder as given)
local function caps(value) return all(M.gui,function(object) return type(object.Text)=="string" and string.upper(object.Text)==string.upper(value) end)[1] end
local function tap(value) local target=text(value);assert(target,value);target.Activated:Fire() end
-- 6.0.1: the apps open in a centred popup; the phone never turns.
local function popup() return named("AppPopup") end
local function showing(id) local panel=popup();local glyph=panel and named("Glyph");return panel~=nil and glyph~=nil and glyph:GetAttribute("Glyph")==id end
local function upright() local body=named("Phone");return body.Size.X.Offset==340 and (body.Rotation or 0)==0 end
local function blur() return M.lighting:FindFirstChild("PhoneAppBlur") end
local function key(code) M.services.UserInputService.InputBegan:Fire({KeyCode=code},false) end
local boards=0
Phone.onBoard=function() boards+=1;Phone.close() end
Phone.start()
Phone.setState({phone=true,money=1240,kit={bag=true},cars={}})
Phone.open()
check("phone opens without warning",Phone.isOpen() and #M.warnings==0)
-- 6.15: a Blood Moon says so on WORK first (server/LiveEvents.luau's workspace attribute).
M.workspace:SetAttribute("LiveEvent","bloodmoon")
Phone.close();Phone.open()
check("6.15: JOBS says the Blood Moon's pay (6.18: its row's line)",text("🌕 BLOOD MOON · jobs pay ×2")~=nil)
M.workspace:SetAttribute("LiveEvent",nil)
Phone.close();Phone.open()
check("6.15: … and nothing of it without one",text("🌕 BLOOD MOON · jobs pay ×2")==nil and Phone.isOpen() and #M.warnings==0)
-- 6.5: home is six big tiles in this order; MORE's sub-screen holds the other eight apps (5.5's MENU among them).
-- 6.12: and TASKS (the daily and weekly tasks) after CAREER: nine.
local function appIds(frame)
	local buttons={}
	for _,child in frame:GetChildren() do if child.ClassName=="TextButton" and string.match(child.Name,"App$") then table.insert(buttons,child) end end
	table.sort(buttons,function(a,b) return a.LayoutOrder<b.LayoutOrder end)
	local ids={}
	for _,button in buttons do table.insert(ids,(string.gsub(button.Name,"App$",""))) end
	return table.concat(ids,",")
end
-- 6.12.5: the main apps first, with their live lines. 6.14 (client/ReadyCheck.luau): NEXT MISSION on top. 6.18 (client/
-- PhoneHome.luau, client/CardKit.luau): the header's chips, the hero card (NEXT MISSION; YOUR RUN during a run), then a
-- compact row an app (JOBS first), MESSAGES; MORE keeps the other eight, as rows too.
local function deep(root,name) return root:FindFirstChild(name,true) end
check("6.18 home: the chips, the hero, the app rows, MESSAGES, the switch in order",named("Shift").LayoutOrder<named("HomeHero").LayoutOrder and named("HomeHero").LayoutOrder<named("Apps").LayoutOrder
	and named("Apps").LayoutOrder<named("MessagesRow").LayoutOrder and named("MessagesRow").LayoutOrder<named("Courier").LayoutOrder and named("Main")==nil and named("Tiles")==nil and text("WORK")==nil)
check("6.18 header: the cash chip (green), the level chip with its XP line, the shift chip",named("MoneyChip").Text=="$1240" and named("MoneyChip").TextColor3==require("./CardKit").Color.money
	and named("LevelChip").Text=="LV 1" and named("LevelChip"):FindFirstChild("Xp")~=nil and named("ShiftChip").Text~="")
check("6.18 the hero: NEXT MISSION, a kit hero card (its ribbon, its readiness chip, the mission big, its button on a tall phone)",named("nextApp").ClassName=="TextButton" and named("nextApp").Parent==named("HomeHero")
	and deep(named("nextApp"),"Head").Text=="NEXT MISSION" and deep(named("nextApp"),"Status")~=nil and deep(named("nextApp"),"Mission").Text~="" and deep(named("nextApp"),"Go")~=nil
	and deep(named("nextApp"),"Shade")~=nil and named("nextApp").Visible and not named("HomeContract").Visible)
check("6.18: the gamepad lands on the hero",M.focus==named("nextApp"))
check("6.18 home: the rows JOBS, TASKS, MISSIONS, MAP, SHOP, BAG & ITEMS, GARAGE, STYLE, MORE in order",appIds(named("Apps"))=="jobs,tasks,missions,map,shop,bag,garage,style,more")
for _,name in {"JOBS","TASKS","MISSIONS","MAP","SHOP","BAG & ITEMS","GARAGE","STYLE","MORE"} do
	local label=text(name)
	check(`the {name} row: its icon, its name, one live line, the round ›, a badge`,label~=nil and label.Parent.Parent==named("Apps") and label.Parent:FindFirstChild("Sub")~=nil and label.Parent:FindFirstChild("Sub").Text~=""
		and label.Parent:FindFirstChild("Edge")~=nil and deep(label.Parent,"NativeGlyph")~=nil and label.Parent:FindFirstChild("Add").Text=="›" and label.Parent:FindFirstChild("Badge")~=nil
		and label.Parent.Size.Y.Offset==require("./Config").UiKit.Row)
end
check("JOBS' row: the red edge (the daily work)",named("jobsApp"):FindFirstChild("Edge").BackgroundColor3==M.Theme.Contract.red)
check("MISSIONS and TASKS carry a progress bar",named("missionsApp"):FindFirstChild("Progress")~=nil and named("tasksApp"):FindFirstChild("Progress")~=nil)
-- 6.14: REGULARS after CAREER.
check("MORE: career, regulars, crew, top, estate, bank, messages, settings",appIds(named("Rows"))=="career,regulars,crew,top,estate,bank,messages,settings")
check("6.18: MORE's entries are the kit's rows too",named("careerApp"):FindFirstChild("Edge")~=nil and named("careerApp"):FindFirstChild("Sub").Text=="Your level and what's next")
-- 6.12.5: MISSIONS' line is the chapter you are at (Phone.missionInfo: MissionsUi.summary), with its bar and NEW.
do
	local info={name="First Shift",done=0,total=6,open=false,why="Level 4",new=false}
	Phone.missionInfo=function() return info end
	Phone.close();Phone.open()
	check("MISSIONS shut: why (6.14: the short words), in grey, no badge",named("missionsApp"):FindFirstChild("Sub").Text=="🔒 Level 4" and not named("missionsApp"):FindFirstChild("Badge").Visible)
	info={name="First Shift",done=0,total=6,open=true,new=true}
	Phone.close();Phone.open()
	check("a chapter newly open: NEW on MISSIONS",named("missionsApp"):FindFirstChild("Badge").Visible and named("missionsApp"):FindFirstChild("Badge").Text=="NEW")
	info={name="Code Red",done=2,total=6,open=true,new=false}
	Phone.close();Phone.open()
	local fill=all(named("missionsApp"):FindFirstChild("Progress"),function(object) return object.ClassName=="Frame" end)
	check("MISSIONS on the way: the chapter, its missions done and the bar",named("missionsApp"):FindFirstChild("Sub").Text=="2/6 · Code Red" and #fill>0 and math.abs(fill[#fill].Size.X.Scale-1/3)<1e-6 and not named("missionsApp"):FindFirstChild("Badge").Visible)
	Phone.missionInfo=nil
end
check("MORE waits behind the home",named("Home").Visible and not named("More").Visible)
check("all eighteen apps constructed (6.14: NEXT MISSION, REGULARS)",#all(M.gui,function(object) return string.match(object.Name,"App$") and object.ClassName=="TextButton" end)==18)
check("the messages row is always on home",named("MessagesRow")~=nil and named("MessagesRow").Visible and text("No new messages")~=nil)
check("glyphs work with empty uploaded IDs (6.18: every row's icon and MESSAGES')",#all(M.gui,function(object) return object.Name=="NativeGlyph" end)==18)
do
	local icons=require("./Icons")
	icons.Ids.app_settings="rbxassetid://12345"
	local parent=M.make("Frame",{},M.gui)
	require("./PhoneContract").glyph(parent,"settings",30)
	check("uploaded icons resolve to asset IDs",parent:FindFirstChild("AppGlyph").Image=="rbxassetid://12345")
	icons.Ids.app_settings="";parent:Destroy()
end
check("6.18: no job: no YOUR RUN hero (NEXT MISSION shows), JOBS' line the board's",not named("HomeContract").Visible and named("jobsApp"):FindFirstChild("Sub").Text=="Take a delivery"
	and named("jobsApp"):FindFirstChild("Pay").Text=="")
named("jobsApp").Activated:Fire()
-- 5.5: the board is in the phone; 6.0.1: in its centred popup. FULL BOARD opens the Dispatch board.
check("JOBS off duty opens the board in the popup",Phone.isOpen() and showing("board") and text("JOBS")~=nil and text("Calling the dispatcher...")~=nil)
check("the board asks the server for offers",M.sent[#M.sent].name=="RequestOffers")
check("the phone stays upright under the popup",upright() and named("Home").Visible and blur()~=nil and Phone.appOpen())
tap("FULL BOARD")
check("FULL BOARD opens the real board, the popup and its blur go",boards==1 and not Phone.isOpen() and popup()==nil and blur()==nil)
Phone.open()
check("home stands upright, no popup",upright() and popup()==nil and not Phone.appOpen())
local payload={stopLabel="Harbor warehouse",customer="Earl",cargo="Parcels",total=2,pay=180,endsAt=376,timeLimit=400,position=M.Vector3.new(150,0,100),mode="foot",stopCount=2,stopIndex=2,orders={{id=1,state="open",focused=true,pay=180,endsAt=376,stops={{label="ZDC DEPOT",kind="pickup",done=true},{label="HARBOR WAREHOUSE",kind="drop",current=true}}},{id=2,state="open",title="Medicine",pay=80,stops={{label="Clinic",current=true}}}}}
M.remotes.Job.OnClientEvent:Fire(payload)
check("home reflects incoming order",text("HARBOR WAREHOUSE")~=nil and text("$180")~=nil)
-- 6.18: during a run the hero is YOUR RUN: the next stop, its pay big in green, the orders and the distance, the clock.
do
	local run=named("HomeContract")
	check("6.18: YOUR RUN takes the hero's place (NEXT MISSION hidden)",run.Visible and not named("nextApp").Visible and run.Parent==named("HomeHero") and deep(run,"Ribbon").Text=="▶ YOUR RUN")
	check("… the stop, the pay in green, one facts line, the clock",deep(run,"Stop").Text=="HARBOR WAREHOUSE" and deep(run,"Pay").Text=="$180" and deep(run,"Pay").TextColor3==require("./CardKit").Color.money
		and deep(run,"Meta").Text=="📦 2 orders · 2 pieces · 180 studs away" and deep(run,"Countdown").Text=="⏱ 04:36" and deep(run,"OpenRun")~=nil)
	check("… JOBS' row: the run's line and its pay",named("jobsApp"):FindFirstChild("Pay").Text~="")
end
-- 6.5: during a run JOBS counts the open orders. 6.12.8: it opens the job list (BOARD), YOUR RUN on top; its DETAILS
-- (and the home's contract card) open ORDERS.
local jobsBadge=named("jobsApp"):FindFirstChild("Badge")
check("JOBS' badge counts the open orders",jobsBadge.Visible and jobsBadge.Text=="2" and named("jobsApp"):FindFirstChild("Sub").Text=="Your run · 2 orders")
named("jobsApp").Activated:Fire()
check("6.12.8: JOBS opens BOARD during a run, not ORDERS",showing("board") and text("JOBS")~=nil and text("ORDERS")==nil)
-- 6.17: YOUR RUN is a chip in the popup's header ("▶ YOUR RUN · 2 · $260"); a tap shows its card (DETAILS as before).
check("6.17: the run's chip in the header's bar, not its card on the list",named("RunChip")~=nil and named("RunChip").Text=="▶ YOUR RUN · 2 · $260" and named("RunChip").Parent.Parent==named("HeaderBar") and named("YourRun")==nil)
named("RunChip").Activated:Fire()
check("6.17: the chip opens YOUR RUN with DETAILS and ‹ JOBS",named("YourRun")~=nil and text("Your run · 2 orders · $260")~=nil and text("DETAILS")~=nil and named("BackToJobs")~=nil)
text("DETAILS").Parent.Activated:Fire()
check("6.12.8: YOUR RUN's DETAILS opens ORDERS as before",showing("orders") and text("ORDERS")~=nil)
named("Close").Activated:Fire()
named("HomeContract").Activated:Fire()
M.flush()
check("orders chart builds actual route",named("RoutePreview")~=nil and named("Destination")~=nil)
local function fogCount() return #all(named("Chart"),function(object) return object.ZIndex==3 end) end
check("undiscovered terrain is covered",fogCount()>0)
M.discovered=true;M.Discovery.changed:Fire()
check("discovery removes only terrain fog",fogCount()==0 and named("Destination")~=nil)
M.discovered=false;M.Discovery.changed:Fire()
check("focused and other orders preserved",#all(M.gui,function(object) return type(object.Text)=="string" and string.find(object.Text,"Medicine",1,true)~=nil end)>0)
check("no runtime warnings",#M.warnings==0)
local oldChart=named("RoutePreview")
M.remotes.Job.OnClientEvent:Fire(payload)
check("unchanged destination reuses road/fog instances",named("RoutePreview")==oldChart)
local nextStop=table.clone(payload)
nextStop.position=M.Vector3.new(300,0,450)
M.remotes.Job.OnClientEvent:Fire(nextStop);M.flush()
check("changed stop replaces the chart",named("RoutePreview")~=oldChart and oldChart.Parent==nil)
local pin=text("📌 PIN") or text("📌 Pin")
check("pin action remains present",pin~=nil)
pin.Parent.Activated:Fire()
check("pin uses existing remote",M.sent[#M.sent].name=="PinOrder")
tap("SHOW ROUTE")
check("route opens existing full map and puts phone away",M.mapOpen and not Phone.isOpen())
check("the closed phone leaves no popup",popup()==nil and blur()==nil)
Phone.open("orders");tap("BAG · EMPTY")
check("bag opens in the same popup (6.18 wave 2: client/BagUi.luau for real)",Phone.isOpen() and showing("bag") and #all(M.gui,function(object) return object.Name=="AppPopup" end)==1 and named("BagRows")~=nil and upright())
named("Close").Activated:Fire()
check("the ✕ returns to the phone's home",popup()==nil and blur()==nil and Phone.isOpen() and named("Home").Visible and upright())
for _,app in {"career","shop","messages"} do
	Phone.open(app)
	check(`{app} still renders`,#M.warnings==0 and showing(app))
end
Phone.open("bank")
check("balance uses current money",text("$1240")~=nil)
Phone.setState({phone=true,money=1450,kit={},cars={}})
check("balance updates with server state",text("$1450")~=nil)
Phone.open("settings")
-- 6.18 wave 2 (client/PhoneMore.luau): a row a setting, its action's word (SOUND · CYCLE).
named("CycleSound").Activated:Fire()
check("settings uses existing sound cycle",M.soundCycles==1)
check("gamepad focus moves into the popup (6.18: the SOUND row)",M.focus==named("SoundRow") and named("CycleSound").Text=="CYCLE" and named("SoundRow"):FindFirstChild("Edge")~=nil)
named("SoundRow").Activated:Fire()
check("… the row itself cycles too",M.soundCycles==2)
named("Backdrop").Activated:Fire()
check("a tap on the backdrop returns home",popup()==nil and Phone.isOpen() and named("Home").Visible)
-- 6.5: MORE is a sub-screen in the phone; its apps close back to it, ESC goes back to the tiles, then puts it away.
named("moreApp").Activated:Fire()
check("MORE turns home to its sub-screen",named("More").Visible and not named("Home").Visible and popup()==nil and M.focus==named("careerApp"))
named("settingsApp").Activated:Fire()
check("a MORE app opens in the popup",showing("settings") and Phone.appOpen())
named("Close").Activated:Fire()
check("its ✕ returns to MORE with the focus on the tapped row",named("More").Visible and Phone.isOpen() and M.focus==named("settingsApp"))
key(M.Enum.KeyCode.Escape)
check("ESC in MORE goes back to home (6.18: the gamepad on the hero, YOUR RUN during this run)",named("Home").Visible and not named("More").Visible and Phone.isOpen() and M.focus==named("HomeContract"))
named("moreApp").Activated:Fire();named("MoreBack").Activated:Fire()
check("‹ BACK goes back to the tiles",named("Home").Visible and not named("More").Visible)
named("moreApp").Activated:Fire()
key(M.Enum.KeyCode.Escape);key(M.Enum.KeyCode.Escape)
check("ESC again puts the phone away; it opens on its tiles",not Phone.isOpen())
Phone.open()
check("the phone opens on its tiles",named("Home").Visible and not named("More").Visible)
Phone.open("orders");M.flush()
M.remotes.Job.OnClientEvent:Fire(nil)
check("nil job switches to empty state",text("No active orders")~=nil)
local live=0
for _,connection in M.Discovery.changed.connections do if connection.Connected then live+=1 end end
check("old chart disconnects discovery listener",live==0)
-- ── 5.5: the MENU's apps, the board in the phone, the turn, banners, GIVE UP ──
local Config=require("./Config")
local toasts={}
Phone.notify=function(value) table.insert(toasts,value) end
local function lastSent(name) for index=#M.sent,1,-1 do if M.sent[index].name==name then return M.sent[index] end end return nil end
local windows={}
Phone.onMissions=function() windows.missions=true end
Phone.onCrew=function() windows.crew=true end
Phone.onTop=function() windows.top=true end
Phone.onEstate=function() windows.estate=true end
for _,id in {"missions","crew","top","estate"} do
	Phone.open();named("moreApp").Activated:Fire();named(`{id}App`).Activated:Fire()
	check(`{id} app opens its window and puts the phone away`,windows[id]==true and not Phone.isOpen())
end
M.mapOpen=false
Phone.open();named("mapApp").Activated:Fire()
check("MAP opens the big map and puts the phone away",M.mapOpen and not Phone.isOpen())
M.mapOpen=false
check("Phone.has follows the state",Phone.has())
-- The board: 6.17's hero and rows (client/JobsView.luau, shared/JobPick.luau), locks, ACCEPT, a banner for a new board.
-- (a row by its offer's index; a label in it by its name)
local function rowOf(index) return all(named("AppPopup"),function(object) return object.Name=="JobRow" and object:GetAttribute("Index")==index end)[1] end
local function within(root,name) return root and all(root,function(object) return object.Name==name end)[1] end
local function rowOrder() local rows=all(named("AppPopup"),function(object) return object.Name=="JobRow" end);table.sort(rows,function(a,b) return a.LayoutOrder<b.LayoutOrder end);local out={};for _,row in rows do table.insert(out,row:GetAttribute("Index")) end;return table.concat(out,",") end
Phone.open()
local offers={
	{index=11,mode="foot",cargo="Letters",customer="Ann",first="Post office",address="12 Elm St",district="Old Town",distance=240,time=180,pay=40,stars=1,tierName="Easy"},
	{index=12,mode="bike",cargo="Pizza",customer="Bob",first="Luigi's",address="3 Oak Ave",distance=600,time=200,pay=90,stars=1,tierName="Easy"},
	{index=13,mode="car",cargo="Crates",customer="Cid",first="Depot",address="Harbor",distance=900,time=300,pay=300,stars=2,tierName="Risky",roleName="Long haul",roleIcon="🛣"},
	{index=14,mode="car",cargo="Gold",customer="Dee",first="Bank",address="Vault",distance=1200,time=300,pay=900,stars=3,tierName="Deadly",locked=true,level=7},
	{index=15,mode="car",cargo="Tyres",customer="Eve",first="Garage",address="Yard",distance=500,time=300,pay=200,stars=2,tierName="Risky",tooBig=true,slots=6,lockButton="📦 NEEDS 6 SLOTS",lockText="Your van holds 4."},
}
M.remotes.Offers.OnClientEvent:Fire(offers,M.now+120,{footNote="Two shops near you are shut."})
check("a new board drops a banner on the open phone",named("Banner")~=nil and named("Banner").Parent==named("Screen"))
named("Banner").Activated:Fire()
check("the banner opens the board in the popup",showing("board") and upright())
-- 6.17: the hero is the best-paying job you can take (the locked $900 one is passed over), the rest are compact rows.
local hero=named("Hero")
check("6.17: the hero card: the best-paying job you can take",hero~=nil and hero:GetAttribute("Index")==13 and hero:GetAttribute("Hero")=="best"
	and within(hero,"Pay").Text=="$300" and within(hero,"Take").Text=="TAKE JOB" and within(hero,"Danger").Text=="★★" and within(hero,"Facts").Text=="📍 900    ⏱ 5:00")
check("… no ribbon or countdown for a plain job, its ⓘ",within(hero,"Ribbon")==nil and within(hero,"Countdown")==nil and within(hero,"Details")~=nil and within(hero,"Details").Text=="ⓘ")
check("6.17: N MORE JOBS, the open rows first, the locked ones last",text("4 MORE JOBS")~=nil and rowOrder()=="11,12,14,15",rowOrder())
local walk=rowOf(11)
check("6.17: a row: 🚶, the distance and time, the pay, a red +",within(walk,"Danger").Text=="🚶" and within(walk,"Facts").Text=="📍 240 · ⏱ 3:00" and within(walk,"Pay").Text=="$40"
	and within(walk,"Add").Text=="+" and within(walk,"Add").BackgroundColor3==M.Theme.Contract.red and within(rowOf(12),"Danger").Text=="🚲")
check("… the old card's words are not on the list",text("LETTERS → ANN")==nil and text("Post office → 12 Elm St, Old Town")==nil and text("On foot · 1")==nil)
check("a locked row: 🔒 LV 7 in place of +",within(rowOf(14),"Add").Text=="🔒 LV 7" and within(rowOf(15),"Add").Text=="📦 6 SLOTS")
check("the footNote under the rows",text("Two shops near you are shut.")~=nil and named("FootNote")~=nil)
-- 6.15: rush hour's chip in the header (server/LiveEvents.luau's workspace attributes), its clock from LiveEventEnds.
M.workspace:SetAttribute("LiveEvent","rush");M.workspace:SetAttribute("LiveEventEnds",M.now+192)
Phone.open("board")
check("6.15 / 6.17: rush hour's chip at the header's right with its clock",named("RushChip")~=nil and named("RushChip").Text=="🕑 RUSH ×1.5 · 3:12" and named("RushChip").Parent==named("HeaderBar"))
M.workspace:SetAttribute("LiveEvent",nil);M.workspace:SetAttribute("LiveEventEnds",nil)
Phone.open("board")
check("6.15: no chip without an event that pays",named("RushChip")==nil and #M.warnings==0)
check("6.17: a wide popup: the hero on the left, the rows on the right",named("JobsView")~=nil and named("Left").Size.X.Scale==Config.UiKit.HeroShare and math.abs(named("Right").Size.X.Scale-(1-Config.UiKit.HeroShare))<1e-9
	and named("JobsView"):FindFirstChildOfClass("UIListLayout").FillDirection.Name=="Horizontal" and named("Hero").Parent==named("Left") and rowOf(11).Parent==named("Right"))
check("6.17: the gamepad lands on the hero's button",M.focus==within(named("Hero"),"Take"))
-- 6.17: a tap on a row opens its details: the old full card (the cargo → the customer, the route, the chips, ACCEPT).
rowOf(11).Activated:Fire()
check("6.17: a row's details: the old card, ‹ JOBS",text("LETTERS → ANN")~=nil and text("Post office → 12 Elm St, Old Town")~=nil and text("$40")~=nil and text("ACCEPT")~=nil and named("BackToJobs")~=nil and named("Hero")==nil)
named("BackToJobs").Activated:Fire()
check("… ‹ JOBS goes back to the list",named("Hero")~=nil and text("LETTERS → ANN")==nil)
within(named("Hero"),"Details").Activated:Fire()
check("6.17: the hero's ⓘ opens its details (its role chip there)",text("CRATES → CID")~=nil and caps("🛣 Long haul")~=nil)
tap("‹ JOBS")
within(rowOf(14),"Add").Activated:Fire()
check("a locked offer says why",string.find(toasts[#toasts] or "","level 7",1,true)~=nil and lastSent("AcceptJob")==nil)
within(rowOf(15),"Add").Activated:Fire()
check("a too-big offer says why",toasts[#toasts]=="Your van holds 4.")
rowOf(15).Activated:Fire()
check("… its details say NEEDS 6 SLOTS",text("📦 NEEDS 6 SLOTS")~=nil)
tap("‹ JOBS")
within(rowOf(11),"Add").Activated:Fire()
check("a row's + off duty is ACCEPT: AcceptJob with the offer's index",lastSent("AcceptJob").args[1]==11)
check("6.19.1: after ACCEPT the phone closes (no ORDERS popping up)",not Phone.isOpen())
-- A run that takes more orders: + ADD keeps the board open.
local run={cargo="Letters",customer="Ann",total=1,pay=40,endsAt=M.now+100,timeLimit=200,position=M.Vector3.new(10,0,10),mode="foot",stack={can=true}}
M.remotes.Job.OnClientEvent:Fire(run)
for _,offer in offers do if offer.index==12 then offer.addOrder=true end end
check("an accepted offer leaves the phone's board",offers[1].index==12)
M.remotes.Offers.OnClientEvent:Fire(offers,M.now+240,{})
Phone.open("board")
check("6.17: during a run the hero is the job that joins it: + ADD",named("Hero"):GetAttribute("Index")==12 and within(named("Hero"),"Take").Text=="+ ADD")
within(named("Hero"),"Take").Activated:Fire()
check("+ ADD fires AcceptJob and stays on the board",lastSent("AcceptJob").args[1]==12 and showing("board") and Phone.isOpen())
-- GIVE UP: two presses within 4 s.
Phone.open("orders")
local cancels=0
for _,sent in M.sent do if sent.name=="CancelJob" then cancels+=1 end end
named("GiveUp").Activated:Fire()
check("GIVE UP asks once first",lastSent("CancelJob")==nil and named("GiveUp").Text=="PRESS AGAIN TO GIVE IT UP")
named("GiveUp").Activated:Fire()
check("a second press gives the delivery up",lastSent("CancelJob")~=nil)
M.remotes.Job.OnClientEvent:Fire(nil)
-- 6.12.8: JOBS is the job list during a run too: YOUR RUN (every open order in one line, the run's pay, the next stop),
-- NEXT UP (the queue: what, where, pay, why the next one waits, ✕), every row's one add button (+ ADD / + QUEUE / why
-- neither) and ADD ALL · $total.
do
	local fixture=M.queueFixture
	M.remotes.Job.OnClientEvent:Fire(fixture.run(M.now))
	local list=fixture.board()
	-- review: ADD ALL's plan from the real shared/JobQueue.luau on these rows (as server/JobQueue.luau makes it): the
	-- special (Cash Transport) and the paper round are never taken, the full foot run takes nothing, the rest queue.
	local Rules=require("./JobQueue")
	local plan=Rules.plan({mode="foot",open=2,free=0,stacks=true},{foot=5,bike=8,car=4},fixture.candidates(list),#fixture.queue.list)
	check("review: ADD ALL never takes the special or the paper round",plan.total==55+130+50 and plan.queued==3 and plan.started==0)
	local info=table.clone(fixture.info)
	info.addAll={count=plan.count,total=plan.total,started=plan.started,added=plan.added,queued=plan.queued}
	M.remotes.Offers.OnClientEvent:Fire(list,M.now+300,info)
	M.remotes.JobQueue.OnClientEvent:Fire("state",fixture.queue)
	Phone.close();Phone.open()
	check("6.12.8: JOBS' line: the run's orders and the jobs waiting",named("jobsApp"):FindFirstChild("Sub").Text=="Your run · 2 orders · 2 next")
	named("jobsApp").Activated:Fire()
	check("6.12.8: JOBS opens BOARD during a run",showing("board") and text("JOBS")~=nil and text("You are on a delivery")==nil)
	-- 6.17: YOUR RUN and NEXT UP open from the header's chips (not on top of the list any more).
	check("6.17: the header's chips: YOUR RUN with its pay, NEXT UP with its count",named("RunChip").Text=="▶ YOUR RUN · 2 · $160" and named("NextChip").Text=="NEXT UP · 2"
		and named("YourRun")==nil and named("NextUp")==nil and named("Hero")~=nil)
	named("RunChip").Activated:Fire()
	-- YOUR RUN: one line an open order (what, from → to · pay · clock), the run's pay, the next stop.
	check("YOUR RUN: the open orders and what they pay together",named("YourRun")~=nil and text("Your run · 2 orders · $160")~=nil and named("Hero")==nil)
	check("YOUR RUN: one line an order, what and from → to",text("🚶  Pizza → Bob · Luigi's Pizza → 3 Oak Ave")~=nil and text("🚶  Letters → Ann · Post Office → 12 Elm St")~=nil and text("🚶  Cake → Flo")==nil)
	check("YOUR RUN: each line's pay and clock",text("$120 · 03:20")~=nil and text("$40 · 01:30")~=nil)
	check("YOUR RUN: the next stop",text("Next stop: PICK UP at Luigi's Pizza")~=nil)
	M.now+=10;require("./OrdersUi").tick()
	check("YOUR RUN's clocks tick",text("$120 · 03:10")~=nil and text("$40 · 01:20")~=nil)
	named("RunChip").Activated:Fire()
	check("6.17: the chip again goes back to the list",named("YourRun")==nil and named("Hero")~=nil)
	named("NextChip").Activated:Fire()
	-- NEXT UP: the queue in order, what, where, pay, the next one's reason to wait, ✕.
	check("NEXT UP from its chip, in order",named("NextUp")~=nil and named("YourRun")==nil and text("Next up · 2 / 6")~=nil and text("▶ They start on their own")~=nil
		and text("1  ★★  Crates → Cid")~=nil and text("2  🚶  Soup → Flo")~=nil)
	check("NEXT UP: where and the pay",text("Depot → Harbor")~=nil and text("Wok Dead → 9 Oak Ave")~=nil and text("$300")~=nil and text("$70")~=nil)
	check("NEXT UP: the next one says why it waits",text("⏸ Waits: needs your car: CALL CAR")~=nil and #all(M.gui,function(object) return object.Name=="Why" end)==1)
	named("Drop").Activated:Fire()
	check("NEXT UP's ✕ drops it through the JobQueue remote",M.lastSent("JobQueue").args[1]=="drop" and M.lastSent("JobQueue").args[2]==5)
	tap("‹ JOBS")
	-- The hero and the rows: + QUEUE (the run is full, or another transport waiting for your bike), the locks, the queue full.
	local hero=named("Hero")
	check("6.17: during a full run the hero is the best job that can wait in NEXT UP: + QUEUE",hero:GetAttribute("Index")==22 and within(hero,"Take").Text=="+ QUEUE" and within(rowOf(21),"Add").Text=="+"
		and text("🚲 RIDE YOUR BIKE")==nil and text("+ ADD")==nil)
	check("a locked row keeps its lock, a special and the paper round can't (⏸)",within(rowOf(23),"Add").Text=="🔒 LV 7" and within(rowOf(25),"Add").Text=="⏸" and within(rowOf(26),"Add").Text=="⏸"
		and rowOrder()=="21,23,24,25,26",rowOrder())
	rowOf(25).Activated:Fire()
	check("… its details say why: FINISH YOUR RUN",text("FINISH YOUR RUN")~=nil and text("CASH TRANSPORT: CASH")~=nil)
	tap("‹ JOBS")
	within(rowOf(24),"Add").Activated:Fire()
	check("a full queue says so",toasts[#toasts]=="NEXT UP holds 6 jobs." and M.lastSent("JobQueue").args[1]=="drop")
	check("every row shows its pay",within(rowOf(21),"Pay").Text=="$55" and within(named("Hero"),"Pay").Text=="$130" and within(rowOf(24),"Pay").Text=="$50")
	within(rowOf(21),"Add").Activated:Fire()
	check("a row's + QUEUE fires JobQueue with the offer's index and stays on the board",M.lastSent("JobQueue").args[1]=="queue" and M.lastSent("JobQueue").args[2]==21 and showing("board"))
	check("a queued offer leaves the phone's board",list[1].index==22 and rowOf(21)==nil)
	-- ADD ALL · $total sends the right request, and says what it does.
	check("ADD ALL shows what it pays (not the special, not the round)",named("AddAll").Text=="ADD ALL · $235" and named("AddAll").Parent==named("MoreHead") and text("4 MORE JOBS")~=nil)
	tap("ADD ALL · $235")
	check("ADD ALL fires JobQueue addAll and says what it does",M.lastSent("JobQueue").args[1]=="addAll" and #M.lastSent("JobQueue").args==1 and toasts[#toasts]=="3 jobs: 3 wait in NEXT UP.")
	-- review: PAUSE, CLEAR ALL; the idle start's "Starts in a few seconds"; PAUSED with RESUME.
	named("NextChip").Activated:Fire()
	named("Pause").Activated:Fire()
	check("review: PAUSE pauses NEXT UP through the JobQueue remote",M.lastSent("JobQueue").args[1]=="pause")
	named("ClearAll").Activated:Fire()
	check("review: CLEAR ALL empties it",M.lastSent("JobQueue").args[1]=="clear")
	M.remotes.JobQueue.OnClientEvent:Fire("state",fixture.starting)
	check("review: the next one's idle start says so (PAUSE to wait)",text("▶ Starts in a few seconds · PAUSE to wait")~=nil and named("Starting")~=nil and named("Why")==nil)
	M.remotes.JobQueue.OnClientEvent:Fire("state",fixture.paused)
	check("review: PAUSED after a failed delivery, with RESUME",text("⏸ Paused after a failed delivery · RESUME to go on")~=nil and named("Resume")~=nil and named("Pause")==nil and named("Starting")==nil and named("ClearAll")~=nil)
	named("Resume").Activated:Fire()
	check("review: RESUME goes on through the JobQueue remote",M.lastSent("JobQueue").args[1]=="resume")
	Phone.close();Phone.open()
	check("review: JOBS' line says it is paused",named("jobsApp"):FindFirstChild("Sub").Text=="Your run · 2 orders · 2 next (paused)")
	named("jobsApp").Activated:Fire()
	check("6.17: JOBS opens on its list again",named("Hero")~=nil and named("NextUp")==nil)
	-- A run that takes no more orders (a mission): the board still shows, its rows queue.
	M.remotes.Job.OnClientEvent:Fire({cargo="Gold",customer="Dee",total=1,pay=900,endsAt=M.now+100,stars=3,address="Vault",mission={name="Code Red"}})
	Phone.open("board")
	check("6.12.8: on a mission the board shows + QUEUE, not 'You are on a delivery'",text("You are on a delivery")==nil and named("RunChip").Text=="▶ YOUR RUN · 1 · $900" and text("+ QUEUE")~=nil)
	named("RunChip").Activated:Fire()
	check("… and its YOUR RUN",text("Your run · 1 order · $900")~=nil and text("★★★  Gold → Dee · Vault")~=nil)
	-- Off duty the rows are ACCEPT again; the queue's state clears.
	M.remotes.Job.OnClientEvent:Fire(nil)
	M.remotes.JobQueue.OnClientEvent:Fire("state",{max=6,list={}})
	Phone.open("board")
	check("off duty: TAKE JOB, no chips, no YOUR RUN, no NEXT UP",within(named("Hero"),"Take").Text=="TAKE JOB" and text("+ QUEUE")==nil and named("RunChip")==nil and named("NextChip")==nil and named("YourRun")==nil and named("NextUp")==nil)
	check("6.12.8: no warnings on the board",#M.warnings==0)
	Phone.close()
end

-- 6.12.11: the job pictures (shared/JobThumbs.luau, client/JobThumbUi.luau). A row's card opens with its business's
-- picture: while the image id is empty a slim banner (the cargo emoji and the business's name), once uploaded an
-- ImageLabel with that id (cropped to about 2.4 : 1) with the name over it; a row without a picture (no business: an
-- older server's) has neither. NEXT UP's rows: a small square once uploaded, nothing while empty.
do
	local JobThumbs=require("./JobThumbs")
	-- (6.12.11: the owner uploaded the pictures; these checks start from the ids empty and put them back after)
	local uploadedIds=table.clone(JobThumbs.Images)
	for id in JobThumbs.Images do JobThumbs.Images[id]="" end
	local rows={
		{index=31,mode="foot",cargo="Pizzas",customer="Hannah",first="Luigi's Pizza",address="3 Oak Ave",distance=300,time=150,pay=60,stars=1,business="pizzeria"},
		{index=32,mode="car",cargo="Cash",customer="Vault",first="Bank",address="Depot",distance=900,time=300,pay=700,stars=2,tierName="Risky",special=true,jobType={id="cashrun",name="Cash Transport",description=""}},
		{index=33,mode="foot",cargo="Morning papers",customer="12 doors on Elm St",first="The Daily Undead",address="Elm St",distance=600,time=420,pay=95,stars=1,round=true},
		{index=34,mode="car",cargo="Crates",customer="Cid",first="Depot",address="Harbor",distance=900,time=300,pay=300,stars=2,tierName="Risky"},
	}
	local soup={id=7,title="Soup → Flo",cargo="Soup",customer="Flo",mode="foot",stars=1,from="Wok Dead",to="9 Oak Ave",pay=70,business="noodles"}
	M.remotes.Offers.OnClientEvent:Fire(rows,M.now+300,{})
	M.remotes.JobQueue.OnClientEvent:Fire("state",{max=6,list={soup}})
	Phone.open("board")
	local function inPopup(name) return all(named("AppPopup"),function(object) return object.Name==name end) end
	-- 6.17: the rows and the hero show the picture, or its emoji on charcoal while the id is empty.
	local thumb=within(rowOf(31),"Thumb")
	check("6.17: an empty image id: the row's emoji, no image",within(thumb,"Emoji")~=nil and within(thumb,"Emoji").Text=="🍕" and within(thumb,"Picture")==nil
		and within(rowOf(31),"Business").Text=="LUIGI'S PIZZA")
	check("… the hero's by its job type (a special: the bank), a row without a business: its cargo and a parcel",named("Hero"):GetAttribute("Index")==32 and within(named("Hero"),"Business").Text=="FIRST ZOMBIE BANK  ·"
		and within(rowOf(33),"Business").Text=="THE DAILY UNDEAD" and within(rowOf(34),"Business").Text=="CRATES" and within(within(rowOf(34),"Thumb"),"Emoji").Text=="📦" and #inPopup("Picture")==0)
	rowOf(31).Activated:Fire()
	local function cardOf(title) local label=text(title);return label and label.Parent and label.Parent.Parent end
	local pizza=cardOf("PIZZAS → HANNAH")
	local banner=pizza and pizza:FindFirstChild("ThumbBanner")
	check("6.12.11: its details: a slim banner on top of the card, the business's name and its emoji",banner~=nil and banner.LayoutOrder<text("PIZZAS → HANNAH").Parent.LayoutOrder
		and banner:FindFirstChild("Business").Text=="LUIGI'S PIZZA" and banner:FindFirstChild("Emoji").Text=="🍕" and banner.Size.Y.Offset<=30)
	named("NextChip").Activated:Fire()
	check("… NEXT UP's row as before",#inPopup("ThumbSquare")==0 and text("1  🚶  Soup → Flo").Position.X.Offset==0)
	JobThumbs.Images.pizzeria="rbxassetid://424242"
	JobThumbs.Images.noodles="rbxassetid://515151"
	Phone.close();Phone.open("board")
	local picture=within(within(rowOf(31),"Thumb"),"Picture")
	check("6.17: an uploaded id: the row's picture, cropped, the business's name beside it",picture~=nil and picture.ClassName=="ImageLabel" and picture.Image=="rbxassetid://424242" and picture.ScaleType.Name=="Crop"
		and within(rowOf(31),"Business").Text=="LUIGI'S PIZZA")
	rowOf(31).Activated:Fire()
	pizza=cardOf("PIZZAS → HANNAH")
	local strip=pizza and pizza:FindFirstChild("Thumb")
	local cardPicture=strip and strip:FindFirstChild("Picture")
	check("6.12.11: its details: an ImageLabel with that id across the top of the card, cropped",cardPicture~=nil and cardPicture.Image=="rbxassetid://424242"
		and cardPicture.ScaleType.Name=="Crop" and strip.LayoutOrder<text("PIZZAS → HANNAH").Parent.LayoutOrder and pizza:FindFirstChild("ThumbBanner")==nil)
	check("… the business's name on a dark label over its bottom-left corner",strip:FindFirstChild("Business").Text=="LUIGI'S PIZZA" and strip:FindFirstChild("Business").AnchorPoint.Y==1 and strip.ClipsDescendants==true)
	local size=strip.AbsoluteSize
	check("… about 2.4 : 1 (its height follows its width)",size.Y>0 and math.abs(size.X/size.Y-2.4)<0.05)
	check("… the rest of the card unchanged: the pay, the route, the chips, ACCEPT",text("$60")~=nil and text("Luigi's Pizza → 3 Oak Ave")~=nil and pizza:FindFirstChild("Chips")~=nil and text("ACCEPT")~=nil)
	named("NextChip").Activated:Fire()
	local square=named("NextUp") and all(named("NextUp"),function(object) return object.Name=="ThumbSquare" end)[1]
	check("6.12.11: NEXT UP's row: a small square of the picture, its words beside it",square~=nil and square.Image=="rbxassetid://515151" and square.ScaleType.Name=="Crop" and text("1  🚶  Soup → Flo").Position.X.Offset==44)
	tap("‹ JOBS")
	within(rowOf(31),"Add").Activated:Fire()
	check("… the row's + still takes it",lastSent("AcceptJob").args[1]==31)
	for id,value in uploadedIds do JobThumbs.Images[id]=value end -- (the owner's ids back)
	M.remotes.Job.OnClientEvent:Fire(nil)
	M.remotes.JobQueue.OnClientEvent:Fire("state",{max=6,list={}})
	check("6.12.11: no warnings with the pictures",#M.warnings==0)
	Phone.close()
end

-- 6.14: the regulars (client/RegularsApp.luau) and the golden orders (client/SpecialOrderUi.luau). The State's counts:
-- a tier reached says so (a toast, the level-up sting). MORE → REGULARS: every business (25) as a card with its picture,
-- the highest tier first with its medal, bar and next tier, the ones never met greyed. On the job list a golden order
-- heads the board in a section of its own, its card in gold with its perks and countdown (a toast and the sting when it
-- comes, once); every card names your tier with its business; NEXT UP says when a queued one runs out; a run's toast
-- carries its result lines.
do
	local RegularsApp=require("./RegularsApp")
	local SpecialOrderUi=require("./SpecialOrderUi")
	local said={}
	local function say(value) table.insert(said,value) end
	RegularsApp.start(say)
	SpecialOrderUi.start(say)
	M.remotes.State.OnClientEvent:Fire({regulars={pizzeria=4,clinic=15,nowhere=9}})
	check("6.14: the first State: the counts, no toast",#said==0 and RegularsApp.counts().pizzeria==4 and RegularsApp.counts().nowhere==nil)
	M.remotes.State.OnClientEvent:Fire({regulars={pizzeria=5,clinic=15}})
	check("a tier reached: its toast and the sting",said[#said]=="Luigi's Pizza: you're a BRONZE regular · +5% pay" and M.played[#M.played]=="level_up")
	Phone.close();Phone.open()
	named("moreApp").Activated:Fire()
	named("regularsApp").Activated:Fire()
	check("MORE → REGULARS opens in the popup",showing("regulars") and named("Glyph"):FindFirstChild("NativeGlyph")~=nil and #M.warnings==0)
	local function inPopup(name) return all(named("AppPopup"),function(object) return object.Name==name end) end
	local cards=all(named("AppPopup"),function(object) return string.match(object.Name,"^Regular_")~=nil end)
	check("a card for every business",#cards==25,#cards)
	check("the summary (6.18: chips on top): who knows you, the tiers held",text("2 / 25 KNOW YOU")~=nil and text("🥈 SILVER 1")~=nil and text("🥉 BRONZE 1")~=nil)
	local clinic,pizza,bakery=named("Regular_clinic"),named("Regular_pizzeria"),named("Regular_bakery")
	check("the highest tier first",clinic.LayoutOrder<pizza.LayoutOrder and pizza.LayoutOrder<bakery.LayoutOrder)
	local function within(card,value) return all(card,function(object) return object.Text==value end)[1] end
	check("6.18: your best regular is the hero: its picture, the bonus big in its medal's colour",clinic:FindFirstChild("Shade")~=nil and clinic:FindFirstChild("Pay",true).Text=="+10%"
		and clinic:FindFirstChild("Pay",true).TextColor3==RegularsApp.colorOf("silver") and named("Regular_pizzeria"):FindFirstChild("Edge")~=nil and named("Regular_pizzeria"):FindFirstChild("Pay").Text=="+5%")
	check("a regular's card: its picture, name, medal, bar and the way to the next tier",(clinic:FindFirstChild("Picture")~=nil or clinic:FindFirstChild("Emoji")~=nil) and within(clinic,"CITY CLINIC")~=nil
		and within(clinic,"🥈 SILVER · +10%")~=nil and all(clinic,function(object) return object.Name=="Progress" end)[1]~=nil and within(clinic,"15 deliveries · 25 more for GOLD (+15%)")~=nil)
	local thumb=bakery:FindFirstChild("Thumb")
	local picture=thumb and thumb:FindFirstChild("Picture")
	check("never met: greyed, how to meet them",picture~=nil and picture.ImageColor3==require("./CardKit").Color.grey and within(bakery,"Deliver for them once to meet them.")~=nil and within(bakery,"NOT MET")~=nil)
	named("Close").Activated:Fire()
	check("REGULARS closes back to MORE",popup()==nil and named("More").Visible)
	-- A golden order on the board.
	local golden={index=41,mode="car",cargo="Gold",customer="Vault",first="First Zombie Bank",address="Depot",distance=1200,time=300,pay=2100,stars=3,tierName="Deadly",business="bank",
		specialOrder={kind="golden",expiresAt=M.now+150,seconds=180,pay=3,xp=2,waves=2,boost=2,light=false}}
	local plain={index=42,mode="foot",cargo="Pizzas",customer="Hannah",first="Luigi's Pizza",address="3 Oak Ave",distance=300,time=150,pay=60,stars=1,business="pizzeria"}
	local before=#said
	M.remotes.Offers.OnClientEvent:Fire({golden,plain},M.now+300,{})
	check("6.14: a golden order comes: its toast (the time it has left) and the sting",said[#said]=="★ A GOLDEN ORDER is on your board · 2:30 · ×3 PAY · ×2 XP · MORE DANGER · JOBS" and M.played[#M.played]=="event_start",said[#said])
	M.remotes.Offers.OnClientEvent:Fire({golden,plain},M.now+300,{})
	check("… once",#said==before+1)
	Phone.close();Phone.open("board")
	-- 6.17: a golden order is the hero: the gold frame, its ribbon and countdown, the pay in gold, +2× XP, TAKE GOLDEN ORDER.
	local function part(root,name) return root and all(root,function(object) return object.Name==name end)[1] end
	local hero=named("Hero")
	check("6.17: a golden order is the hero, in gold: the frame, the ribbon, the countdown",hero~=nil and hero:GetAttribute("Index")==41 and hero:GetAttribute("Hero")=="golden" and hero:GetAttribute("SpecialOrder")=="golden"
		and hero:FindFirstChildOfClass("UIStroke").Thickness==2 and hero:FindFirstChildOfClass("UIStroke").Color.R==242/255
		and part(hero,"Ribbon").Text=="★ GOLDEN ORDER ×3" and part(hero,"Countdown").Text=="⏳ 2:30")
	check("… its pay big in gold, its facts with +2× XP, TAKE GOLDEN ORDER",part(hero,"Pay").Text=="$2100" and part(hero,"Pay").TextColor3.R==242/255 and part(hero,"Facts").Text=="📍 1200    ⏱ 5:00    +2× XP"
		and part(hero,"Take").Text=="TAKE GOLDEN ORDER" and text("1 MORE JOB")~=nil)
	check("6.17: a row names your tier with its business by a medal on its picture (Luigi's: Bronze)",part(part(rowOf(42),"Thumb"),"Medal")~=nil and part(part(rowOf(42),"Thumb"),"Medal").Text=="🥉"
		and text("🥉 BRONZE REGULAR +5%")==nil)
	rowOf(42).Activated:Fire()
	check("… its details say it in words",text("🥉 BRONZE REGULAR +5%")~=nil)
	tap("‹ JOBS")
	part(named("Hero"),"Details").Activated:Fire()
	check("… the golden order's details: the old card in gold with its perks",text("GOLD → VAULT")~=nil and text("★ GOLDEN ORDER · ×3 PAY · ×2 XP · MORE DANGER")~=nil)
	tap("‹ JOBS")
	part(named("Hero"),"Take").Activated:Fire()
	check("… TAKE GOLDEN ORDER fires the golden row's id",lastSent("AcceptJob").args[1]==41)
	-- NEXT UP: a queued golden order runs out there too.
	local queued={id=9,title="Gold → Vault",cargo="Gold",customer="Vault",mode="car",stars=3,from="Bank",to="Depot",pay=2100,business="bank",specialOrder=golden.specialOrder}
	M.remotes.Job.OnClientEvent:Fire(M.queueFixture.run(M.now))
	M.remotes.JobQueue.OnClientEvent:Fire("state",{max=6,list={queued}})
	Phone.close();Phone.open("board")
	named("NextChip").Activated:Fire()
	check("NEXT UP: a queued golden order says when it runs out",named("RunsOut")~=nil and named("RunsOut").Text=="★ GOLDEN ORDER · leaves NEXT UP in 2:30",named("RunsOut") and named("RunsOut").Text)
	M.remotes.Job.OnClientEvent:Fire(nil)
	M.remotes.JobQueue.OnClientEvent:Fire("state",{max=6,list={}})
	-- An expired one says nothing; a run's toast carries the result's lines.
	before=#said
	M.remotes.Offers.OnClientEvent:Fire({{index=43,mode="foot",cargo="Bread",customer="Ed",pay=150,stars=1,specialOrder={kind="golden",expiresAt=M.now-1,seconds=180,pay=3,xp=2}}},M.now+300,{})
	check("an expired one comes with no toast",#said==before)
	SpecialOrderUi.toast({success=true,mode="foot",special={golden={pay=3,xp=2},regular={name="Luigi's Pizza",tier="Bronze",money=4}}},say)
	check("a run's toast: the golden order and the regular's bonus",said[#said]=="★ GOLDEN ORDER ×3 · ×2 XP · Regular · Luigi's Pizza (Bronze) +$4",said[#said])
	before=#said
	SpecialOrderUi.toast({success=true,mode="car",special={golden={pay=3,xp=2}}},say)
	check("… not for a car job's window (it shows them as lines)",#said==before)
	check("6.14: no warnings",#M.warnings==0)
	Phone.close()
end

-- CAREER: its hero beside its rows (6.18 wave 2: the kit's columns, client/PhoneMore.luau). SHOP: the kit's hero beside its rows.
Phone.open("career")
check("career opens in the popup in two columns",showing("career") and upright() and named("CareerView")~=nil and named("CareerView"):FindFirstChildOfClass("UIListLayout").FillDirection.Name=="Horizontal" and #M.warnings==0)
Phone.open("shop")
check("shop opens in the popup: SAVE UP, the hero beside the rows",showing("shop") and upright() and named("ShopCards")~=nil and named("ShopCards"):FindFirstChild("Left")~=nil and named("Hero")~=nil and #M.warnings==0)
-- GARAGE: BRING MY CAR, MY BIKE, CALL CAR.
local bike,car
for _,def in Config.Cars do
	if def.bike and not bike then bike=def.id end
	if not def.bike and not def.company and not car then car=def.id end
end
Phone.setState({phone=true,money=1600,kit={},cars={[bike]=true,[car]=true}})
Phone.open("garage")
-- 6.18 wave 2: the vehicle you have out as the hero (BRING MY CAR its big button), MY BIKE / CALL CAR / ZDC RIDE as rows.
check("garage opens in the popup: the hero and the rows",showing("garage") and upright() and named("Hero")~=nil and deep(named("Hero"),"BringCar")~=nil
	and named("Item_bike")~=nil and named("Item_car")~=nil and named("Item_ride")~=nil and M.focus==deep(named("Hero"),"BringCar"))
tap("BRING MY CAR")
check("BRING MY CAR fires SpawnCar and puts the phone away",lastSent("SpawnCar")~=nil and not Phone.isOpen())
Phone.open("garage");deep(named("Item_bike"),"Ride").Activated:Fire()
check("MY BIKE rides the bike",lastSent("Equip").args[1]=="ride")
Phone.open("garage");deep(named("Item_car"),"Call").Activated:Fire()
check("CALL CAR calls the car",lastSent("Equip").args[1]=="drive")
-- 5.6: ZDC RIDE, the nearest rental dock and the GPS to it.
Phone.open("garage")
local rideLine=all(M.gui,function(object) return type(object.Text)=="string" and string.find(object.Text,"ZDC RIDE · nearest dock",1,true)~=nil end)[1]
check("garage names the nearest ZDC RIDE dock",rideLine~=nil and #M.warnings==0)
local waypoints=0
local setWaypoint=M.MapView.setWaypoint
M.MapView.setWaypoint=function() waypoints+=1 end
deep(named("Item_ride"),"Gps").Activated:Fire()
check("ZDC RIDE's GPS sets the waypoint",waypoints==1)
named("Item_ride").Activated:Fire()
check("a row's tap opens its details, ‹ BACK returns",named("ItemHero")~=nil and named("Back")~=nil)
named("Back").Activated:Fire()
check("… back on the list",named("ItemHero")==nil and named("Hero")~=nil)
M.MapView.setWaypoint=setWaypoint
-- SETTINGS: the keys and the version; BANK: what you earned since you joined.
local sounds=0
Phone.onSound=function() sounds+=1 end
Phone.open("settings")
check("settings lists every key and the version",text("Weapon wheel")~=nil and text("Sprint")~=nil and text(`ZDC courier terminal · Zombie Delivery {Config.Version}`)~=nil)
named("CycleSound").Activated:Fire()
check("settings' sound goes through Phone.onSound",sounds==1)
-- 6.15: ENEMY OUTLINES off and on (client/EnemyOutline.luau through Phone.onOutline; no button without it).
check("no outline button before Main wires it",named("Outlines")==nil and named("OutlineRow")==nil)
local outlined=true
Phone.outlineOn=function() return outlined end
Phone.onOutline=function() outlined=not outlined;return outlined end
Phone.open("settings")
check("6.18: ENEMY OUTLINES · ON",named("Outlines").Text=="ON" and text("ENEMY OUTLINES")~=nil)
named("Outlines").Activated:Fire()
check("settings turns the enemies' outline off, says so and shows it",not outlined and toasts[#toasts]=="Enemy outlines off" and named("Outlines").Text=="OFF")
named("Outlines").Activated:Fire()
check("and on again",outlined and toasts[#toasts]=="Enemy outlines on: zombies red, bandits orange" and named("Outlines").Text=="ON")
Phone.outlineOn,Phone.onOutline=nil,nil
Phone.open("bank")
check("bank shows what you earned since you joined",text("+$360")~=nil)
check("6.18 wave 2: BANK's hero: the cash big in green, FIND A DELIVERY its one button",named("Balance")~=nil and named("Balance"):FindFirstChild("Pay",true).TextColor3==require("./CardKit").Color.money
	and named("FindDelivery")~=nil and named("Earned"):FindFirstChild("Pay").Text=="+$360")
-- 6.18 wave 2: CAREER's hero is the next level (the XP to go big, FULL CAREER), the road after it rows.
Phone.open("career")
check("6.18 wave 2: CAREER: the next level the hero, the road its rows",named("NextLevel")~=nil and string.find(named("NextLevel"):FindFirstChild("Pay",true).Text," XP",1,true)~=nil
	and named("FullCareer")~=nil and named("Level_3")~=nil and named("Level_3"):FindFirstChild("Add").Text=="🔒 LV 3")
-- A new message drops a banner while another app shows; it opens MESSAGES.
Phone.open("bank")
M.remotes.Tutorial.OnClientEvent:Fire("message",{from="Marge",text="Earl has a van for you."})
check("a new message drops a banner in the open popup",named("Banner")~=nil and named("Banner").Parent==popup())
named("Banner").Activated:Fire()
check("the message banner opens MESSAGES",showing("messages") and text("MESSAGES")~=nil)
-- 6.5: the home's messages row shows the unread count and the newest line; a tap opens MESSAGES and reads them.
Phone.close();Phone.open()
M.remotes.Tutorial.OnClientEvent:Fire("message",{from="Marge",text="The bike shop is open."})
M.remotes.Tutorial.OnClientEvent:Fire("message",{from="Marge",text="Dead End Motors is on your GPS."})
check("the messages row counts the unread",named("Unread").Visible and named("Unread").Text=="2" and text("Dead End Motors is on your GPS.")~=nil)
named("MessagesRow").Activated:Fire()
check("the messages row opens MESSAGES",showing("messages"))
-- 6.18 wave 2: a row a message (the newest first, the red dot while unread); a tap opens it whole, ‹ MESSAGES back.
local rows=all(named("AppPopup"),function(object) return object.Name=="Message" and object.ClassName=="TextButton" end)
table.sort(rows,function(a,b) return a.LayoutOrder<b.LayoutOrder end)
check("6.18 wave 2: MESSAGES' rows, the newest first, unread dotted",#rows>=2 and rows[1]:FindFirstChild("Facts").Text=="Dead End Motors is on your GPS." and rows[1]:FindFirstChild("Unread")~=nil)
rows[1].Activated:Fire()
check("… a tap opens the message whole, ‹ MESSAGES goes back",showing("messages") and named("BackToMessages")~=nil and named("Words").Text=="Dead End Motors is on your GPS.")
named("BackToMessages").Activated:Fire()
check("… back to the rows",named("BackToMessages")==nil and named("RecentHead")~=nil)
named("Close").Activated:Fire()
check("read: the count goes",not named("Unread").Visible and text("No new messages")~=nil)
-- 6.0.1: every app opens in the popup and closes back to home; the phone never turns.
-- 6.5: the tiles (JOBS off duty: the board) and MORE's rows; each closes back to the page it came from.
for _,entry in {{"next","ready"},{"jobs","board"},{"shop","shop"},{"bag","bag"},{"garage","garage"},{"career","career",true},{"tasks","tasks"},{"regulars","regulars",true},{"messages","messages",true},{"bank","bank",true},{"settings","settings",true}} do
	local id,shows,inMore=entry[1],entry[2],entry[3]==true
	Phone.close();Phone.open()
	if inMore then named("moreApp").Activated:Fire() end
	named(`{id}App`).Activated:Fire()
	check(`{id} opens in the centred popup`,showing(shows) and upright() and blur()~=nil and named("Heading")~=nil and named("Glyph"):FindFirstChild("NativeGlyph")~=nil and #M.warnings==0)
	named("Close").Activated:Fire()
	check(`{id} closes back to the phone's {if inMore then "MORE" else "home"}`,popup()==nil and blur()==nil and Phone.isOpen() and named(if inMore then "More" else "Home").Visible and upright())
end
-- 6.5: SHOP lists the shops and what they sell; a tap sets the GPS, puts the phone away and says so.
Phone.open("shop")
-- 6.18 wave 2: SAVE UP (the goal as the hero, a row a thing to buy, 📍 its counter) and SHOPS, two tabs as chips.
check("SHOP opens on SAVE UP: the tabs, the cash chip, a row a thing to save up for",named("Tab_save")~=nil and named("Tab_shops")~=nil and named("Tab_save"):FindFirstChild("Underline")~=nil
	and named("CashChip")~=nil and #all(M.gui,function(object) return string.match(object.Name,"^Item_")~=nil end)>0)
named("Tab_shops").Activated:Fire()
-- 6.12.7: five shops: the bikes are Dead End Motors' (its CARS and BIKES counters), no Spoke & Chain row.
check("SHOPS lists the five shops",named("Shops")~=nil and named("Tab_shops"):FindFirstChild("Underline")~=nil
	and named("Shop_bags")~=nil and named("Shop_supplies")~=nil and named("Shop_guns")~=nil and named("Shop_dealer")~=nil and named("Shop_mechanic")~=nil
	and named("Shop_bikes")==nil and named("Shop_guns").LayoutOrder<named("Shop_dealer").LayoutOrder and named("Shop_dealer").LayoutOrder<named("Shop_mechanic").LayoutOrder)
check("6.6: ZDC Bags first, the bags there; no backpack anywhere",named("Shop_bags").LayoutOrder<named("Shop_supplies").LayoutOrder and text("ZDC Bags")~=nil and text("Bags (sprint with your deliveries)")~=nil
	and all(M.gui,function(object) return type(object.Text)=="string" and string.find(string.lower(object.Text),"backpack",1,true)~=nil end)[1]==nil)
check("each shop says what it sells",text("Last Stop Supplies")~=nil and text("Items and vests, next to the bags")~=nil and text("Lead & Co.")~=nil and text("Range · guns, gun upgrades, a baseball bat")~=nil
	and text("Dead End Motors")~=nil and text("Cars, vans, trucks · bikes, the E-Scooter, bike gear")~=nil and text("Wrench Garage")~=nil and text("Stages, car upgrades, gear, paint, car guns, repairs")~=nil) -- (6.7: what each really sells; 6.12.7: the bikes at Dead End Motors)
named("Tab_save").Activated:Fire()
check("6.12.7: Spoke & Chain is gone from SHOP, its bikes named as part of Dead End Motors",all(M.gui,function(object) return type(object.Text)=="string" and string.find(string.upper(object.Text),"SPOKE",1,true)~=nil end)[1]==nil
	and all(M.gui,function(object) return type(object.Text)=="string" and string.find(object.Text,"Dead End Motors, the BIKES counter",1,true)==1 end)[1]~=nil)
do
	-- 6.12.7: the bikes' Set GPS goes to the BIKES counter in Dead End Motors (Map.Shops.bikes), named as part of it.
	local waypoint
	local setWaypoint=M.MapView.setWaypoint
	M.MapView.setWaypoint=function(at) waypoint=at end
	-- (the first bike you don't own: a row of its own, or the hero)
	local bike
	local hero=named("Hero")
	for _,def in require("./Config").Cars do if def.bike and not bike and (named(`Item_{def.id}`)~=nil or hero:GetAttribute("Item")==def.id) then bike=def.id end end
	local row=named(`Item_{bike}`)
	check("6.18 wave 2: a bike's row (its price big, a round 📍) or the hero",(row~=nil and row:FindFirstChild("Pay")~=nil and row:FindFirstChild("Add")~=nil) or hero:GetAttribute("Item")==bike)
	if row then row:FindFirstChild("Add").Activated:Fire() else deep(hero,"HeroAction").Activated:Fire() end
	local counter=require("./Map").Shops.bikes
	check("the bikes' Set GPS: the BIKES counter at Dead End Motors",waypoint~=nil and waypoint.X==counter.x and waypoint.Z==counter.z and toasts[#toasts]=="GPS: Dead End Motors · Bikes")
	M.MapView.setWaypoint=setWaypoint
end
do
	-- 6.12.14: Lead & Co.'s row: its range out of the safe zone, the GPS to the range shop's counter (Map.Shops.guns).
	local waypoint
	local setWaypoint=M.MapView.setWaypoint
	M.MapView.setWaypoint=function(at) waypoint=at end
	named("Tab_shops").Activated:Fire()
	named("Shop_guns").Activated:Fire()
	local Map=require("./Map")
	local range=Map.Shops.guns
	check("6.12.14: Lead & Co.'s GPS: its range's counter, out of the safe zone",waypoint~=nil and waypoint.X==range.x and waypoint.Z==range.z and not Map.isSafe(range.x,range.z)
		and math.abs(range.x-Map.GunRange.x)<Map.BlockSize/2 and math.abs(range.z-Map.GunRange.z)<Map.BlockSize/2 and toasts[#toasts]=="GPS set: Lead & Co.")
	M.MapView.setWaypoint=setWaypoint
	Phone.open("shop")
end
do
	local waypoint
	local setWaypoint=M.MapView.setWaypoint
	M.MapView.setWaypoint=function(at) waypoint=at end
	named("Tab_shops").Activated:Fire()
	named("Shop_supplies").Activated:Fire()
	local gear=require("./Map").Shops.supplies -- (6.12.2: Last Stop Supplies is the gear stall's GEAR counter at the depot)
	check("a shop's tap sets the GPS there, puts the phone away and says so",waypoint~=nil and waypoint.X==gear.x and waypoint.Z==gear.z and not Phone.isOpen() and toasts[#toasts]=="GPS set: Last Stop Supplies")
	M.MapView.setWaypoint=setWaypoint
end
-- 6.5: BAG & ITEMS, the I window's tabs: ITEMS (USE through the bottom bar's path), BAGS; BAG during a run.
Phone.setState({phone=true,money=1600,kit={},cars={},items={medkit=2}})
Phone.open();named("bagApp").Activated:Fire()
-- 6.18 wave 2: the bag as the hero, a row an item with its count big and a round USE (client/BagUi.luau).
check("off duty BAG & ITEMS opens on ITEMS, no BAG tab",showing("bag") and text("BAG & ITEMS")~=nil and named("Tab_items")~=nil and named("Tab_bags")~=nil and named("Tab_bag")==nil
	and named("Item_medkit")~=nil and named("Item_medkit"):FindFirstChild("Pay").Text=="×2" and named("Hero")~=nil and named("ItemRows")~=nil)
check("6.7: no car, no car items in ITEMS (the energy drink is there)",named("Item_repair")==nil and named("Item_jerrycan")==nil and named("Item_energy")~=nil)
check("an item names its key in the bottom bar",all(M.gui,function(object) return type(object.Text)=="string" and string.find(object.Text,"Key 5.",1,true)~=nil end)[1]~=nil)
named("Item_medkit"):FindFirstChild("Use").Activated:Fire()
check("USE goes through the bottom bar's path",M.used=="medkit")
named("Tab_bags").Activated:Fire()
check("BAGS shows the bags you own",showing("bag") and named("BagsRows")~=nil and named("Tab_bags"):FindFirstChild("Underline")~=nil)
M.remotes.Job.OnClientEvent:Fire({cargo="Letters",customer="Ann",total=2,pay=40,endsAt=M.now+100,mode="foot",orders={{id=1,state="open"}}})
named("Close").Activated:Fire();named("bagApp").Activated:Fire()
check("during a run it opens on BAG",named("Tab_bag")~=nil and named("BagRows")~=nil)
check("JOBS' badge: one open order",named("jobsApp"):FindFirstChild("Badge").Text=="1" and named("jobsApp"):FindFirstChild("Sub").Text=="Your run · orders")
M.remotes.Job.OnClientEvent:Fire(nil)
check("the run ends: BAG & ITEMS falls back to ITEMS",named("Tab_bag")==nil and named("Tab_items")~=nil)
Phone.close()
-- 6.12: MORE → TASKS: the server's state (the Tasks remote), the cards, CLAIM, the badges and the dot, the toasts.
do
	local asked=false
	for _,sent in M.sent do if sent.name=="Tasks" and sent.args[1]=="open" then asked=true end end
	check("the phone asks for its tasks when it starts",asked)
	local told
	Phone.onUnread=function(count) told=count end
	local state={
		daily={
			{slot=1,id="pizza",title="Deliver 3 pizza stacks",target=3,progress=3,money=180,xp=110,done=true,claimed=false},
			{slot=2,id="zip",title="Ride a zip line",target=1,progress=0,money=120,xp=80,done=false,claimed=false},
			{slot=3,id="tips",title="Earn $80 in tips",target=80,progress=40,unit="$",money=150,xp=100,done=false,claimed=false},
		},
		bonus={money=300,xp=150,done=false,claimed=false},
		weekly={slot="weekly",id="w_kill",title="Kill 150 zombies",target=150,progress=20,money=1400,xp=550,done=false,claimed=false},
		dayEnds=M.now+3*3600+120,weekEnds=M.now+2*86400+3600,ready=1,
	}
	Phone.close();Phone.open()
	M.remotes.Tasks.OnClientEvent:Fire("state",state)
	check("a reward to claim: a badge on TASKS (home) and the HUD's phone dot, none on MORE",named("tasksApp"):FindFirstChild("Badge").Visible and named("tasksApp"):FindFirstChild("Badge").Text=="1" and told==1 and not named("moreApp"):FindFirstChild("Badge").Visible)
	check("TASKS' live line on home: the reward waiting and today's dailies",named("tasksApp"):FindFirstChild("Sub").Text=="1 to claim · 1/3")
	local fill=all(named("tasksApp"):FindFirstChild("Progress"),function(object) return object.ClassName=="Frame" end)
	check("TASKS' bar: a third of the dailies done",#fill>0 and math.abs(fill[#fill].Size.X.Scale-1/3)<1e-6)
	named("tasksApp").Activated:Fire()
	check("TASKS opens in the popup",showing("tasks") and text("TASKS")~=nil and upright() and #M.warnings==0)
	check("three daily cards, the bonus card and the weekly card",named("Task_1")~=nil and named("Task_2")~=nil and named("Task_3")~=nil and named("Task_bonus")~=nil and named("Task_weekly")~=nil)
	-- 6.18 (client/CardKit.luau): the task to claim is the hero (its kind, its progress, the money big, CLAIM · $X in
	-- green); the others are the kit's rows (the name, "0 / 1 · +80 XP", the money big, a bar at the foot).
	local Kit=require("./CardKit")
	local hero=named("Task_1")
	check("6.18: the hero: the task to claim, its ribbon, ✓ DONE, the money big, CLAIM · $180 in green",hero:FindFirstChild("Ribbon").Text=="DAILY TASK" and hero:FindFirstChild("Status").Text=="✓ DONE"
		and hero:FindFirstChild("Pay",true).Text=="$180" and named("Claim_1").Text=="CLAIM · $180" and named("Claim_1").BackgroundColor3==M.Theme.Contract.good and hero:FindFirstChild("Shade")~=nil)
	check("6.18: … the others are rows: an edge, the money big, a bar",named("Task_2"):FindFirstChild("Edge")~=nil and named("Task_2"):FindFirstChild("Pay").Text=="$120"
		and named("Task_2"):FindFirstChild("Pay").TextColor3==Kit.Color.money and named("Task_2"):FindFirstChild("Progress")~=nil and named("Task_weekly"):FindFirstChild("Pay").TextColor3==Kit.Color.gold)
	check("a card: its title, its progress and its reward",text("Ride a zip line")~=nil and text("0 / 1 · +80 XP")~=nil and text("$120")~=nil and text("20 / 150 · +550 XP")~=nil)
	check("money tasks read in dollars",text("$40 / $80 · +100 XP")~=nil)
	check("how long until the tasks are new (6.18: the chips on top)",text("⏱ DAILY · 3 h 2 min")~=nil and text("📅 WEEKLY · 2 d 1 h")~=nil and named("DayClock").Parent.Name=="Chips" and text("1 TO CLAIM")~=nil)
	check("CLAIM only on the done task, the gamepad on it",named("Claim_1")~=nil and named("Claim_2")==nil and named("Claim_weekly")==nil and named("Claim_bonus")==nil and M.focus==named("Claim_1"))
	named("Claim_1").Activated:Fire()
	check("CLAIM asks the server for that task",lastSent("Tasks").args[1]=="claim" and lastSent("Tasks").args[2]==1)
	M.remotes.Tasks.OnClientEvent:Fire("claimed",{title="Deliver 3 pizza stacks",money=180,xp=110})
	check("a claim paid: a toast and the money's sound",toasts[#toasts]=="Deliver 3 pizza stacks: +$180 · +110 XP" and M.played[#M.played]=="cash")
	state.daily[1].claimed=true;state.ready=0
	M.remotes.Tasks.OnClientEvent:Fire("state",state)
	check("the new state: ✓ CLAIMED, no CLAIM, no badges, no dot",showing("tasks") and named("Claim_1")==nil and text("✓ CLAIMED")~=nil and not named("tasksApp"):FindFirstChild("Badge").Visible and told==0)
	M.remotes.Tasks.OnClientEvent:Fire("done",{title="Ride a zip line",weekly=false,money=120,xp=80})
	check("a task done: a toast and a sound",string.find(toasts[#toasts] or "","TASK DONE: Ride a zip line",1,true)~=nil and M.played[#M.played]=="task_done")
	for _,task in state.daily do task.progress=task.target;task.done=true;task.claimed=true end
	state.bonus.done=true;state.ready=1
	M.remotes.Tasks.OnClientEvent:Fire("state",state)
	check("every daily done: CLAIM the bonus (6.18: the hero's)",named("Claim_bonus")~=nil and M.focus==named("Claim_bonus") and named("Task_bonus"):FindFirstChild("Ribbon").Text=="BONUS · EVERY DAILY")
	named("Claim_bonus").Activated:Fire()
	check("CLAIM BONUS asks for the bonus",lastSent("Tasks").args[1]=="claim" and lastSent("Tasks").args[2]=="bonus")
	check("before the reset the countdown runs",text("⏱ DAILY · 3 h 2 min")~=nil)
	M.now=state.dayEnds+1;require("./TasksApp").tick()
	check("the phone's ticker counts down to the reset",text("⏱ DAILY · 0 s")~=nil)
	M.now=100
	named("Close").Activated:Fire()
	check("TASKS closes back to the phone",popup()==nil and Phone.isOpen() and #M.warnings==0)
	Phone.onUnread=nil
end
-- 6.12: STYLE (client/StyleApp.luau): the tabs, the preview, a card an item with its price; BUY / WEAR / TAKE OFF ask
-- the server through the Style remote; what can't be done yet says why; the purchase's "cash"; the keys while open.
-- The clerks: BUY only at a shop that sells the look (the courier stands at the gear stall for it); away from it the
-- button says where ("AT THE GEAR STALL") and a press sets the GPS there; walking up or away redraws the cards (the
-- phone's ticker, StyleApp.tick); a clerk's "Style" prompt (the Style remote's ("open", tab)) opens STYLE on the tab.
-- 6.18 wave 2 (the UI kit): the look you try is the hero (the preview, its price big, HeroMain its full action), a
-- compact row a look (its colours, its price, a round "Main": BUY, WEAR, OFF, 📍; the lock's words); a row's tap TRIES.
do
	M.played={}
	local Map=require("./Map")
	local StyleApp=require("./StyleApp")
	local gear,garage=Map.Shops.supplies,Map.Shops.mechanic
	M.stand(gear.x,gear.z)
	local function inCard(id,name)
		local card=named(`Style_{id}`)
		return card and all(card,function(object) return object.Name==name end)[1]
	end
	local function styleSent() return lastSent("Style") end
	local function hasText(value) return all(M.gui,function(object) return type(object.Text)=="string" and string.find(object.Text,value,1,true)~=nil end)[1]~=nil end
	Phone.setState({phone=true,money=300,kit={},cars={},style={owned={},worn={}}})
	Phone.open()
	check("home's STYLE row: your looks",named("styleApp").Parent==named("Apps") and text("Your looks")~=nil)
	named("styleApp").Activated:Fire()
	check("the line under the tabs says who sells them",text("Buy them from Dot at the gear stall; wear them from here, anywhere. Looks only: no item changes a number of the game; your own look stays under them.")~=nil)
	check("STYLE opens in the popup on COURIER",showing("style") and text("STYLE")~=nil and named("Tab_courier")~=nil and named("Tab_vehicle")~=nil and named("Tab_courier"):FindFirstChild("Underline")~=nil)
	check("6.18 wave 2: the hero (the preview in it, its button) beside the rows; the gamepad on its button",named("Hero")~=nil and named("Hero"):FindFirstChild("Preview")~=nil and deep(named("Hero"),"HeroMain")~=nil
		and named("StyleCards")~=nil and named("StyleCards"):FindFirstChild("Left")~=nil and M.focus==deep(named("Hero"),"HeroMain"))
	check("its sections: hats, jackets, the vest's and the bag's colours",text("Hats · your own")~=nil and text("Jackets · your own")~=nil and text("Courier Vest colour · your own")~=nil and text("Bag colour · your own")~=nil)
	check("the live preview shows the courier with the first item",#M.previews>0 and M.previews[#M.previews].tab=="courier" and M.previews[#M.previews].id=="cap_red" and named("Preview")~=nil)
	check("a card an item: its colours, name, price",named("Style_cap_red")~=nil and text("BACKWARDS CAP · ZDC RED")~=nil and inCard("cap_red","Colour1")~=nil and inCard("cap_red","Colour2")~=nil and text("$250")~=nil) -- (6.19: $120 × Prices.Style, rounded to $50)
	check("a reward is flagged",inCard("cap_gold","Main")~=nil and inCard("cap_gold","Main").Text=="🏆 REWARD")
	check("a level's lock shows",text("🔒 LV 4")~=nil)
	check("the hero's full words: BUY · $250 for the first look",deep(named("Hero"),"HeroMain").Text=="BUY · $250")
	inCard("cap_red","Main").Activated:Fire()
	check("BUY asks the server with the item",styleSent()~=nil and styleSent().args[1]=="buy" and styleSent().args[2]=="cap_red")
	local before=#M.sent
	inCard("cap_gold","Main").Activated:Fire()
	check("a reward is never bought: it says so",#M.sent==before and string.find(toasts[#toasts] or "","not for sale",1,true)~=nil)
	inCard("leather_black","Main").Activated:Fire()
	check("too dear or too early: it says why",#M.sent==before and string.find(toasts[#toasts] or "","unlocks at level 6",1,true)~=nil)
	inCard("hoodie_grey","Main").Activated:Fire()
	check("not enough money: it says so",#M.sent==before and toasts[#toasts]=="Not enough money: Hoodie · Grey costs $700.")
	named("Style_beanie_grey").Activated:Fire()
	check("a row's tap TRIES it, no remote; the hero follows",#M.sent==before and M.previews[#M.previews].id=="beanie_grey" and named("Style_beanie_grey"):FindFirstChild("Accent")~=nil and named("Style_beanie_grey"):FindFirstChild("Accent").Visible
		and deep(named("Hero"),"Business").Text=="BEANIE · HEATHER GREY")
	-- the state brings the purchase back: "cash", OWNED → WEAR, WEARING → TAKE OFF
	Phone.setState({phone=true,money=380,kit={},cars={},style={owned={cap_red=true},worn={hat="cap_red"}}})
	check("the purchase plays cash once",M.played[#M.played]=="cash" and #M.played==1)
	check("WEARING and TAKE OFF",hasText("WEARING") and inCard("cap_red","Main").Text=="OFF" and text("Hats · Backwards Cap · ZDC Red")~=nil)
	inCard("cap_red","Main").Activated:Fire()
	check("TAKE OFF asks the server with the slot",styleSent().args[1]=="unwear" and styleSent().args[2]=="hat")
	Phone.setState({phone=true,money=380,kit={},cars={},style={owned={cap_red=true},worn={}}})
	check("no second cash",#M.played==1)
	inCard("cap_red","Main").Activated:Fire()
	check("WEAR asks the server with the item",inCard("cap_red","Main").Text=="WEAR" and styleSent().args[1]=="wear" and styleSent().args[2]=="cap_red")
	local renders=#M.previews
	Phone.setState({phone=true,money=380,kit={},cars={},style={owned={cap_red=true},worn={}},items={medkit=1}})
	check("a state change STYLE doesn't show draws nothing again",#M.previews==renders)
	-- the keys: bound while open
	local keys=M.actions.ZombieDeliveryStyleKeys
	check("the keys bound while STYLE is open",keys~=nil and keys.priority==3006)
	local function press(code) M.actions.ZombieDeliveryStyleKeys.fn("x",M.Enum.UserInputState.Begin,{KeyCode=code}) end
	local pickedBefore=M.previews[#M.previews].id
	press(M.Enum.KeyCode.Down)
	check("↓ picks the next item (the preview follows)",M.previews[#M.previews].id~=pickedBefore and showing("style"))
	press(M.Enum.KeyCode.Up)
	check("↑ the one before",M.previews[#M.previews].id==pickedBefore)
	press(M.Enum.KeyCode.Tab)
	check("TAB switches to VEHICLE: wraps, bike paint, decals",named("Tab_vehicle"):FindFirstChild("Underline")~=nil and text("Wraps · cars, vans, trucks · your own")~=nil and text("Decals · cars, vans, trucks · your own")~=nil and M.previews[#M.previews].tab=="vehicle")
	check("at the gear stall a wrap is sold at Wrench Garage (📍; the hero says where)",inCard("wrap_sand","Main").Text=="📍" and hasText("AT WRENCH GARAGE"))
	M.waypoint=nil
	press(M.Enum.KeyCode.Return)
	check("ENTER does the picked item's action (a wrap away from Gus: where, and the GPS)",toasts[#toasts]=="Gus sells it at Wrench Garage. It's on your GPS."
		and M.waypoint~=nil and M.waypoint.X==garage.x and M.waypoint.Z==garage.z and showing("style"))
	M.stand(garage.x,garage.z);StyleApp.tick()
	check("walked up to Wrench Garage: the cards follow, BUY there",inCard("wrap_sand","Main").Text=="BUY" and inCard("bike_mint","Main").Text=="BUY" and hasText("BUY · $"))
	press(M.Enum.KeyCode.Return)
	check("ENTER at the shop: a wrap too dear says so",string.find(toasts[#toasts] or "","Not enough money",1,true)~=nil)
	M.stand(gear.x,gear.z);StyleApp.tick()
	press(M.Enum.KeyCode.ButtonL1)
	check("the gamepad's L1 switches back",named("Tab_courier"):FindFirstChild("Underline")~=nil)
	named("Tab_vehicle").Activated:Fire()
	check("a tap on a tab switches it",named("Tab_vehicle"):FindFirstChild("Underline")~=nil)
	named("Tab_courier").Activated:Fire()
	-- away from the gear stall: what you own still WEAR, TRY still previews, the rest says where it is sold
	local before=#M.sent
	M.stand(5000,5000);StyleApp.tick()
	check("away: a look for sale says where (📍)",inCard("beanie_orange","Main").Text=="📍" and inCard("cap_red","Main").Text=="WEAR")
	check("away: a reward and a level's lock as before",inCard("cap_gold","Main").Text=="🏆 REWARD" and string.find(inCard("cowboy","Main").Text,"🔒 LV",1,true)==1)
	M.waypoint=nil
	inCard("beanie_orange","Main").Activated:Fire()
	check("its press: who sells it and the GPS to the gear stall, no remote",#M.sent==before and toasts[#toasts]=="Dot sells it at the gear stall. It's on your GPS."
		and M.waypoint~=nil and M.waypoint.X==gear.x and M.waypoint.Z==gear.z and showing("style"))
	named("Style_beanie_orange").Activated:Fire()
	check("away: TRY previews, the caption says who sells it",M.previews[#M.previews].id=="beanie_orange" and text("BEANIE · SAFETY ORANGE · Dot sells it at the gear stall.")~=nil and #M.sent==before)
	inCard("cap_red","Main").Activated:Fire()
	check("away: WEAR works anywhere",lastSent("Style").args[1]=="wear" and lastSent("Style").args[2]=="cap_red")
	local drawn=#M.previews
	StyleApp.tick()
	check("standing still draws nothing again",#M.previews==drawn)
	M.stand(gear.x,gear.z);StyleApp.tick()
	check("back at the gear stall: BUY again",inCard("beanie_orange","Main").Text=="BUY")
	named("Close").Activated:Fire()
	M.flush()
	check("closed: the keys are free again",M.actions.ZombieDeliveryStyleKeys==nil and Phone.isOpen() and named("Home").Visible)
	-- a clerk's "Style" prompt: the server's ("open", tab) opens the phone on STYLE at that tab
	Phone.close()
	M.remotes.Style.OnClientEvent:Fire("open","vehicle")
	check("Gus's Style prompt opens STYLE on VEHICLE",Phone.isOpen() and showing("style") and named("Tab_vehicle"):FindFirstChild("Underline")~=nil)
	M.remotes.Style.OnClientEvent:Fire("open","courier")
	check("Dot's opens it on COURIER (the phone already open)",showing("style") and named("Tab_courier"):FindFirstChild("Underline")~=nil)
	Phone.close()
	Phone.setState({phone=false,money=380,kit={},cars={},style={owned={cap_red=true},worn={}}})
	M.remotes.Style.OnClientEvent:Fire("open","vehicle")
	check("no phone yet: it says so, nothing opens",not Phone.isOpen() and string.find(toasts[#toasts] or "","No phone yet",1,true)~=nil)
	Phone.setState({phone=true,money=380,kit={},cars={},style={owned={cap_red=true},worn={}}})
	M.stand(0,0)
	check("no warnings in STYLE",#M.warnings==0)
	Phone.close()
end
-- 6.14, get ready for the mission (client/ReadyCheck.luau, shared/Readiness.luau): NEXT MISSION's lines from the State
-- and the Missions state, its READY CHECK (the checklist, each row's action, the savings goal, START / WORK, MISSIONS),
-- WORK's goal line, INVITE (Roblox's game invite, else CREW), the one-time READY toast and the HUD's savings line.
do
	local Ready=require("./ReadyCheck")
	local Levels=require("./Levels")
	local Map=require("./Map")
	local said,started,chapters,crews={},{},{},{}
	Ready.notify=function(value) table.insert(said,value) end
	Ready.toGo=M.CareerUi.toGo
	Ready.onStart=function(id) table.insert(started,id) end
	Ready.onMissions=function(id) table.insert(chapters,id or "-") end
	Ready.onCrew=function(id) table.insert(crews,id or "-") end
	M.played={}
	Ready.start()
	-- A level-2 courier with $640, no vehicle: Paper Trail needs level 4 and Earl's van.
	M.player:SetAttribute("Xp",Levels.xpFor(2)+100)
	Ready.setState({phone=true,money=640,kit={},cars={},items={}})
	check("6.14: the first State asks for the Missions state once",lastSent("Missions")~=nil and lastSent("Missions").args[1]=="open")
	M.remotes.Missions.OnClientEvent:Fire("state",{progress={},level=2,crewSize=0})
	Phone.close();Phone.open()
	local tile=named("nextApp")
	check("6.14 NEXT MISSION: the mission, its chapter and n/N",tile:FindFirstChild("Head",true).Text=="NEXT MISSION" and tile:FindFirstChild("Mission",true).Text=="📦 Paper Trail" and tile:FindFirstChild("Chapter",true).Text=="First Shift · 1/6")
	check("… not ready yet: '0 of 2 ready' in red",tile:FindFirstChild("Status",true).Text=="✖ 0 OF 2 READY" and tile:FindFirstChild("Status",true).TextColor3==M.Theme.Contract.red)
	local bars=all(tile:FindFirstChild("Progress",true),function(object) return object.Name=="Fill" or object.ClassName=="Frame" end)
	check("… the savings goal and its bar: Old Van · $640 / $5,400",tile:FindFirstChild("Goal",true).Text=="🚐 Old Van · $640 / $5,400" and math.abs(bars[#bars].Size.X.Scale-640/5400)<1e-6)
	check("6.14 JOBS: the board's line (6.18: one line; what you earn for is the hero's goal and bar)",named("jobsApp"):FindFirstChild("Sub").Text~="" and named("jobsApp"):FindFirstChild("Goal")==nil and Ready.workLine()=="Earn for the Old Van · $4,760 to go")
	check("6.18: not ready: GET READY on the hero's button, its frame red",tile:FindFirstChild("Go",true).Text=="GET READY ›" and tile:FindFirstChildOfClass("UIStroke").Color==M.Theme.Contract.red)
	check("… the job result's line (client/Hud.luau)",Ready.resultLine(85)=="+$85 · $4,675 to go for the Old Van")
	named("nextApp").Activated:Fire()
	check("6.14: NEXT MISSION opens the READY CHECK in the popup",showing("ready") and text("READY CHECK")~=nil and upright() and #M.warnings==0)
	check("… the mission card: its name, the readiness chip",text("PAPER TRAIL")~=nil and text("✖ 0 OF 2 READY")~=nil)
	check("… the rows: the level, the van (required), a medkit (would help)",named("Check_level")~=nil and named("Check_vehicle")~=nil and named("Check_medkit")~=nil and named("Check_cargo")==nil
		and named("Check_vehicle"):FindFirstChild("Mark").Text=="✖" and named("Check_medkit"):FindFirstChild("Mark").Text=="☆")
	check("… the van's row (6.18: the kit's row, its icon the thumb, ✖ in red, a red edge): where and what it costs, a GPS action",text("A van of your own")~=nil and named("Check_vehicle"):FindFirstChild("Edge").BackgroundColor3==M.Theme.Contract.red and text("Old Van at Earl's Used Wheels · $5,400 · level 4")~=nil and named("Check_vehicle").ClassName=="TextButton"
		and named("Check_vehicle"):FindFirstChild("Action").Text=="📍 GPS  ›")
	check("… the level's row: the XP and about how much work (CareerUi.toGo)",Levels.xpFor(2)+100<1000 and text(`{Levels.xpFor(2)+100} / 2,093 XP · about 8 runs`)~=nil and named("Check_level"):FindFirstChild("Action").Text=="JOBS  ›")
	check("… the savings goal: Old Van, $640 / $5,400, $4,760 to go",named("SavingsGoal")~=nil and text("$640 / $5,400")~=nil and text("$4,760 to go")~=nil)
	check("… not ready: WORK · EARN AND LEVEL UP and OPEN MISSIONS, no START",named("Jobs")~=nil and named("OpenMissions")~=nil and named("Start")==nil)
	-- The van's GPS: Earl's Used Wheels on the map, the phone away so you can go.
	M.waypoint=nil
	named("Check_vehicle").Activated:Fire()
	check("6.14: a row's GPS goes to its shop (Earl's), puts the phone away and says so",M.waypoint~=nil and M.waypoint.X==Map.VanSeller.earl.x and M.waypoint.Z==Map.VanSeller.earl.z and not Phone.isOpen()
		and toasts[#toasts]=="GPS set: Earl's Used Wheels · Old Van")
	Phone.open("ready")
	named("Check_level").Activated:Fire()
	check("… the level's JOBS opens the board",showing("board"))
	Phone.open("ready")
	named("OpenMissions").Activated:Fire()
	check("… OPEN MISSIONS: the window on First Shift, the phone away",chapters[#chapters]=="dispatch" and not Phone.isOpen())
	-- With the van at level 4: READY, the one-time toast and its sting, START through the MISSIONS window.
	M.player:SetAttribute("Xp",Levels.xpFor(4))
	Ready.setState({phone=true,money=300,kit={},cars={van=true},car="van",vanQuest="done",items={medkit=1,repair=1}})
	check("6.14: the mission became ready: the toast and the sting, once",said[#said]=="Ready for Paper Trail · open MISSIONS (U)" and M.played[#M.played]=="task_done")
	local count=#said
	Ready.setState({phone=true,money=310,kit={},cars={van=true},car="van",vanQuest="done",items={medkit=1,repair=1}})
	check("… not again",#said==count)
	Phone.open()
	tile=named("nextApp")
	check("6.14 NEXT MISSION: READY · START in green, nothing to buy",tile:FindFirstChild("Status",true).Text=="✔ READY · START" and tile:FindFirstChild("Status",true).TextColor3==M.Theme.Contract.good
		and tile:FindFirstChild("Goal",true).Text=="Everything it needs is yours" and tile:FindFirstChild("Go",true).Text=="READY · GO ›")
	named("nextApp").Activated:Fire()
	check("… the READY CHECK: every required row ✔, START",named("Start")~=nil and named("Check_vehicle"):FindFirstChild("Mark").Text=="✔" and named("Check_vehicle"):FindFirstChild("Action")==nil and named("SavingsGoal")==nil
		and named("Start").BackgroundColor3==M.Theme.Contract.good and named("MissionCard"):FindFirstChild("Start",true)==named("Start"))
	named("Start").Activated:Fire()
	check("… START goes through the MISSIONS window (ReadyCheck.onStart), the phone away",started[#started]=="dispatch_1" and not Phone.isOpen())
	-- 6.14 review: START only when it can work (the Missions state: carOut, active, crewOwner): no car of yours out
	-- (CALL CAR), the mission running (IN PROGRESS), somebody else's crew (LEADER PICKS).
	M.remotes.Missions.OnClientEvent:Fire("state",{progress={},level=4,crewSize=0,carOut=false})
	Phone.close();Phone.open()
	tile=named("nextApp")
	check("6.14 review: ready, no car of yours out: READY · CALL CAR in amber, the reason under it",tile:FindFirstChild("Status",true).Text=="✔ READY · CALL CAR" and tile:FindFirstChild("Status",true).TextColor3==M.Theme.Contract.warn
		and tile:FindFirstChild("Goal",true).Text=="Call your car first: CALL CAR on your phone's GARAGE",tile:FindFirstChild("Status",true).Text)
	named("nextApp").Activated:Fire()
	check("… the READY CHECK: CALL CAR FIRST, no START",named("CallCar")~=nil and named("Start")==nil and text("✔ READY · CALL CAR")~=nil)
	named("CallCar").Activated:Fire()
	check("… CALL CAR FIRST opens the GARAGE",showing("garage"))
	M.remotes.Missions.OnClientEvent:Fire("state",{progress={},level=4,crewSize=0,carOut=true,active="dispatch_1"})
	Phone.close();Phone.open()
	check("6.14 review: the mission running: IN PROGRESS, not START",named("nextApp"):FindFirstChild("Status",true).Text=="▶ IN PROGRESS",named("nextApp"):FindFirstChild("Status",true).Text)
	M.remotes.Missions.OnClientEvent:Fire("state",{progress={},level=4,crewSize=0,carOut=true,crewOwner="Ann"})
	Phone.close();Phone.open()
	check("6.14 review: in Ann's crew: LEADER PICKS, never READY · START",named("nextApp"):FindFirstChild("Status",true).Text=="👥 LEADER PICKS" and named("nextApp"):FindFirstChild("Status",true).TextColor3==M.Theme.Contract.warn)
	named("nextApp").Activated:Fire()
	check("… the READY CHECK: no START, your leader picks",named("Start")==nil and named("Waiting")~=nil and text("👥 YOUR LEADER PICKS")~=nil)
	check("… no READY toast for any of it",#said==count)
	M.workspace:SetAttribute("Night",false);M.workspace:GetAttributeChangedSignal("Night"):Fire()
	check("… the night changing on a day mission: no warnings, nothing new",#said==count and #M.warnings==0)
	M.workspace:SetAttribute("Night",nil)
	Phone.close()
	-- A co-op mission: bring a friend (INVITE: Roblox's game invite, else the CREW window for that mission).
	M.remotes.Missions.OnClientEvent:Fire("state",{progress={dispatch_1=1,dispatch_2=1,dispatch_3=1,dispatch_8=1},level=4,crewSize=0})
	check("6.14: a new mission ready at once (a clear's NEXT: its card says so) is no news: no toast",#said==count)
	Phone.open("ready")
	check("6.14: Wheels of Commerce (co-op): READY, a friend would help",text("WHEELS OF COMMERCE")~=nil and named("Start")~=nil and named("Check_friend")~=nil and named("Check_friend"):FindFirstChild("Action").Text=="INVITE  ›")
	named("Check_friend").Activated:Fire()
	check("… no game invite here: the CREW window for that mission",crews[#crews]=="dispatch_9")
	M.services.SocialService={CanSendGameInviteAsync=function() return true end,PromptGameInvite=function() M.invited=true end}
	named("Check_friend").Activated:Fire()
	check("… Roblox's game invite when it can be sent, and what to do once they are here",M.invited==true and said[#said]=="Once your friend is here: CREW (K) → INVITE them to your crew" and #crews==1)
	M.services.SocialService=nil
	-- Money only: the READY CHECK is not drawn again for every coin (its ticker keeps the goal's money live).
	M.remotes.Missions.OnClientEvent:Fire("state",{progress={},level=4,crewSize=0})
	Ready.setState({phone=true,money=100,kit={},cars={},vanQuest="open",items={}})
	Phone.open("ready")
	local card=named("MissionCard")
	Ready.setState({phone=true,money=150,kit={},cars={},vanQuest="open",items={}})
	check("6.14: a new coin keeps the READY CHECK (no redraw), its ticker moves the goal",card~=nil and named("MissionCard")==card and card.Parent~=nil and Phone.isOpen())
	Ready.tick()
	check("… $150 / $5,400 now",text("$150 / $5,400")~=nil and text("$5,250 to go")~=nil)
	Ready.setState({phone=true,money=150,kit={},cars={},vanQuest="open",items={medkit=1}})
	check("… a row that changes draws it again",named("MissionCard")~=card and card.Parent==nil and named("Check_medkit")~=nil and named("Check_medkit"):FindFirstChild("Mark").Text=="✔")
	Phone.close()
	-- The HUD's savings line under the cash (client/SavingsLine.luau): it grows the Cash frame and the column while it
	-- shows; quiet through Marge's first day.
	local hud=M.gui:FindFirstChild("ZombieDeliveryHud")
	local stack=M.make("Frame",{Name="LeftStack",Size=M.UDim2.fromOffset(200,258)},hud)
	local cash=M.make("Frame",{Name="Cash",Size=M.UDim2.fromOffset(200,30)},stack)
	local opened=0
	require("./SavingsLine").onOpen=function() opened+=1 end
	require("./SavingsLine").start(Ready)
	local line=cash:FindFirstChild("Savings")
	local height=require("./Config").Readiness.LineHeight
	check("6.14 HUD: the savings line under the cash, the column taller by its height",line~=nil and line.Visible and line:FindFirstChild("Words").Text=="🚐 OLD VAN" and line:FindFirstChild("Money").Text=="$150 / $5,400"
		and cash.Size.Y.Offset==30+height and stack.Size.Y.Offset==258+height)
	-- 6.14 review: the money in a label of its own at the right; the name gets the rest (cut with "…").
	check("… the money at the right, the name left of it",line:FindFirstChild("Money").AnchorPoint.X==1 and line:FindFirstChild("Money").Size.X.Offset>0
		and line:FindFirstChild("Words").Size.X.Scale==1 and line:FindFirstChild("Words").Size.X.Offset==-(line:FindFirstChild("Money").Size.X.Offset+8))
	stack:SetAttribute("SavingsRoom",false);stack:GetAttributeChangedSignal("SavingsRoom"):Fire()
	check("6.14 review: no room over the thumbstick (Hud's SavingsRoom): the line stays away, the column back",not line.Visible and stack.Size.Y.Offset==258 and cash.Size.Y.Offset==30)
	stack:SetAttribute("SavingsRoom",true);stack:GetAttributeChangedSignal("SavingsRoom"):Fire()
	check("… room again: it comes back",line.Visible and stack.Size.Y.Offset==258+height)
	line.Activated:Fire()
	check("… a tap opens the READY CHECK (SavingsLine.onOpen)",opened==1)
	M.remotes.Tutorial.OnClientEvent:Fire("board",{})
	check("… Marge's first day: hidden, the column back",not line.Visible and cash.Size.Y.Offset==30 and stack.Size.Y.Offset==258 and Ready.resultLine(85)==nil)
	M.remotes.Tutorial.OnClientEvent:Fire("done",{})
	Ready.setState({phone=true,money=6000,kit={},cars={},vanQuest="open",items={medkit=1}})
	check("… enough money: buy it, in green",line.Visible and line:FindFirstChild("Money").Text=="✓ BUY IT · $5,400" and line:FindFirstChild("Words").TextColor3==M.Theme.Contract.good)
	-- 6.14 review: the money without the level is no BUY IT (Earl sells at level 4).
	M.player:SetAttribute("Xp",Levels.xpFor(3))
	Ready.setState({phone=true,money=6000,kit={},cars={},vanQuest="open",items={medkit=1}})
	check("6.14 review: the money, not the level: saved, the level to reach, in amber",line.Visible and line:FindFirstChild("Money").Text=="$5,400 SAVED · LEVEL 4" and line:FindFirstChild("Money").TextColor3==M.Theme.Contract.warn,line:FindFirstChild("Money").Text)
	check("… WORK says so too",Ready.workLine()=="Old Van saved · reach level 4 to buy" and Ready.resultLine(85)=="+$85 · the Old Van is saved: level 4 to buy")
	stack:Destroy()
	check("6.14: no warnings",#M.warnings==0)
end
-- The popup with motion (reduced motion off): it lands centred at full scale, dim and blurred; back on close.
M.services.GuiService.ReducedMotionEnabled=false
Phone.close();Phone.open()
named("jobsApp").Activated:Fire() -- (6.5: JOBS off duty is the board)
local panel=popup()
check("the animated popup lands in the centre",panel.Position.X.Scale==.5 and panel.Position.Y.Scale==.5 and panel.Position.X.Offset==0 and panel:FindFirstChildOfClass("UIScale").Scale==1)
check("the backdrop dims and the blur is low",named("Backdrop").BackgroundTransparency==.45 and blur().Size==8 and named("Veil").Visible==false)
check("the desktop popup is 760 x 520",panel.Size.X.Offset==760 and panel.Size.Y.Offset==520)
check("the phone did not turn",upright())
-- Q / ESC / gamepad B close the popup first, then the phone.
key(M.Enum.KeyCode.Q)
check("Q closes the popup first",popup()==nil and blur()==nil and Phone.isOpen())
key(M.Enum.KeyCode.Q)
check("Q again puts the phone away",not Phone.isOpen())
M.services.GuiService.ReducedMotionEnabled=true
Phone.open("shop")
key(M.Enum.KeyCode.Escape)
check("ESC closes the popup first",popup()==nil and Phone.isOpen())
key(M.Enum.KeyCode.Escape)
check("ESC again puts the phone away",not Phone.isOpen())
Phone.open("bank")
key(M.Enum.KeyCode.ButtonB)
check("gamepad B closes the popup first",popup()==nil and Phone.isOpen())
key(M.Enum.KeyCode.ButtonB)
check("gamepad B again puts the phone away",not Phone.isOpen())
Phone.open("orders")
M.services.GuiService.MenuOpened:Fire()
key(M.Enum.KeyCode.Escape)
check("the Roblox menu closes the popup; its ESC leaves the phone open",popup()==nil and Phone.isOpen())
Phone.close()
check("no runtime warnings in the 5.5 apps",#M.warnings==0)
-- 6.17: a board with a hero and rows for the small screens (a run: the header's run chip; rush hour: its chip).
M.remotes.Offers.OnClientEvent:Fire({
	{index=51,mode="foot",cargo="Letters",customer="Ann",first="Post office",address="12 Elm St",distance=240,time=180,pay=40,stars=1,business="pizzeria"},
	{index=52,mode="car",cargo="Crates",customer="Cid",first="Depot",address="Harbor",distance=900,time=300,pay=300,stars=2,addOrder=true},
	{index=53,mode="car",cargo="Gold",customer="Dee",first="Bank",address="Vault",distance=1200,time=300,pay=900,stars=3,locked=true,level=9},
},M.now+300,{})
M.remotes.Job.OnClientEvent:Fire(M.queueFixture.run(M.now))
M.workspace:SetAttribute("LiveEvent","rush");M.workspace:SetAttribute("LiveEventEnds",M.now+192)
for _,screen in {{320,448},{568,320},{844,390},{844,350},{1280,800}} do
	Phone.close();M.width,M.height=screen[1],screen[2];M.touch=true
	Phone.open()
	check(`resize {M.width}x{M.height} opens`,Phone.isOpen() and #M.warnings==0)
	check("home remains scrollable",named("Home").ClassName=="ScrollingFrame")
	check("the phone stays upright",upright())
	-- 6.18: the hero fills the room over JOBS (PhoneLayout.heroHeight); a short phone's hero is the button itself.
	local layout=require("./PhoneLayout")
	local heroH=layout.heroHeight(layout.fit(M.width,M.height,true,1))
	check(`6.18: the hero's height on {M.width}x{M.height}, its button only when tall enough`,named("HomeContract").Size.Y.Offset==heroH and named("HomeHero").Size.Y.Offset==heroH
		and (named("OpenRun")~=nil)==(heroH>=Config.UiKit.ButtonHeroMin) and named("HomeContract").Visible)
	Phone.open("board")
	local size=popup().Size
	check(`the popup fits {M.width}x{M.height}`,size.X.Offset<=M.width*.92+.001 and size.Y.Offset<=M.height*.86+.001 and showing("board"))
	local side=named("JobsView"):FindFirstChildOfClass("UIListLayout").FillDirection.Name=="Horizontal"
	check("6.17: the hero beside the rows only in a wide popup",side==(size.X.Offset>=600) and named("Hero")~=nil and rowOf(51)~=nil)
	local room=size.Y.Offset-64-36
	check(`6.17: the hero fits {M.width}x{M.height} (its height the room, at least {Config.UiKit.HeroMin})`,named("Hero").Size.Y.Offset==math.clamp(math.floor(room),Config.UiKit.HeroMin,Config.UiKit.HeroMax))
	local bar=named("HeaderBar")
	local inBar=named("RunChip").Parent.Parent==bar
	check("6.17: the run chip, long only when wide",named("RunChip").Text==(if side then "▶ YOUR RUN · 2 · $160" else "▶ RUN · 2 · $160"))
	check("6.17: the chips in the header where they fit (from 844 px wide always), else heading the body",(inBar or named("Chips").Parent==popup():FindFirstChild("Body")) and (inBar or M.width<844)
		and (not inBar or bar.AbsoluteSize.X>=named("RunChip").Size.X.Offset+8+(if named("RushChip").Parent==bar then named("RushChip").Size.X.Offset else 0)))
	check("… rush hour's at the header's right only beside the hero",(named("RushChip").Parent==bar)==(side and inBar))
end
M.remotes.Job.OnClientEvent:Fire(nil)
M.workspace:SetAttribute("LiveEvent",nil);M.workspace:SetAttribute("LiveEventEnds",nil)
-- 6.18: off duty, nothing waiting: JOBS' row says how many jobs you can take and the best pay, big in green.
M.remotes.JobQueue.OnClientEvent:Fire("state",{list={}})
Phone.close();Phone.open()
check("6.18: JOBS' row off duty: '2 jobs · best $300' and $300 big",named("jobsApp"):FindFirstChild("Sub").Text=="2 jobs · best $300" and named("jobsApp"):FindFirstChild("Pay").Text=="$300"
	and named("jobsApp"):FindFirstChild("Pay").TextColor3==require("./CardKit").Color.money and named("nextApp").Visible and not named("HomeContract").Visible,named("jobsApp"):FindFirstChild("Sub").Text)
Phone.open("board")
-- The screen turns while an app is open: the popup fits again and the columns follow.
M.width,M.height=390,800
M.workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Fire();M.flush()
check("a resized popup fits the narrow screen in one column",popup().Size.X.Offset<=390*.92+.001 and named("JobsView"):FindFirstChildOfClass("UIListLayout").FillDirection.Name=="Vertical" and upright() and #M.warnings==0)
Phone.close()
check("hold lifecycle clears phone",M.sent[#M.sent].name=="PhoneHold" and M.sent[#M.sent].args[1]==false)
-- 6.18: the UI kit on its own (client/CardKit.luau): a hero, a row (open, locked, a live value), a section header, the
-- columns.
do
	local Kit=require("./CardKit")
	local host=M.make("Frame",{Size=M.UDim2.fromOffset(760,500)},M.gui)
	local opened,acted=0,0
	local hero=Kit.hero(host,{height=300,picture={emoji="🏦"},title="BANK  ·",tag="★★★",value="$1,140",valueColor=Kit.Color.gold,facts="📍 1240",
		action={name="Take",text="TAKE",kind="gold",onClick=function() acted+=1 end},ribbon={text="★ GOLDEN",face=Kit.Color.gold},corner={text="⏳ 2:41",ink=Kit.Color.gold},
		onOpen=function() opened+=1 end,onDetails=function() opened+=10 end})
	check("6.18 kit hero: the picture, the shade, the value big (PayBig on a tall hero), the button gold",hero.card.Name=="Hero" and hero.card:FindFirstChild("Emoji")~=nil and hero.card:FindFirstChild("Shade")~=nil
		and hero.value.TextSize==Config.UiKit.PayBig and hero.action.BackgroundColor3==Kit.Color.gold and hero.action.TextColor3==Kit.Color.goldInk and hero.ribbon.Text=="★ GOLDEN" and hero.corner.Text=="⏳ 2:41")
	hero.action.Activated:Fire();hero.card:FindFirstChild("Open").Activated:Fire();hero.details.Activated:Fire()
	check("… its button acts, the card and ⓘ open the details",acted==1 and opened==11)
	local short=Kit.hero(host,{height=200,picture={emoji="🏁"},title="",value="x",onOpen=function() end})
	check("… a shorter hero: PayMid, no button, no ⓘ",short.value.TextSize==Config.UiKit.PayMid and short.action==nil and short.details==nil)
	local row=Kit.row(host,{name="R",order=1,accent=Kit.Danger[3],picture={emoji="🍕"},tag="★★★",title="LUIGI'S",facts="📍 420",value="$180",action="+",
		onAction=function() acted+=1 end,onOpen=function() opened+=1 end,badge=true})
	check("… a row: its edge in the danger's colour, the value green, the + red, a hidden badge",row.row:FindFirstChild("Edge").BackgroundColor3==Kit.Danger[3] and row.value.TextColor3==Kit.Color.money
		and row.action.Text=="+" and row.action.ClassName=="TextButton" and row.action.BackgroundColor3==M.Theme.Contract.red and row.badge.Visible==false and row.row.Size.Y.Offset==Config.UiKit.Row)
	row.action.Activated:Fire();row.row.Activated:Fire()
	check("… its + acts, its tap opens",acted==2 and opened==12)
	local locked=Kit.row(host,{name="L",order=2,accent=Kit.Danger[1],picture={emoji="📦"},title="X",facts="y",value="$9",lock="🔒 LV 9",shut=true,onOpen=function() end})
	check("… a locked row: the lock's words (no button), the value dim",locked.action.Text=="🔒 LV 9" and locked.value.TextColor3==Kit.Color.dim and locked.action.ClassName=="TextLabel")
	local before=row.title.Size.X.Offset
	Kit.setValue(row,"$10,000",Kit.Color.gold)
	check("… a live value: its text and colour, the name column narrower for it",row.value.Text=="$10,000" and row.value.TextColor3==Kit.Color.gold and row.title.Size.X.Offset<before)
	Kit.setValue(row,"")
	check("… no value: the name has the room",row.title.Size.X.Offset>before)
	local _,label,chip=Kit.sectionHeader(host,{text="7 MORE JOBS",chip={name="All",text="ADD ALL · $3,046"}})
	check("… a section header with its chip at the right",label.Text=="7 MORE JOBS" and chip.Name=="All" and chip.AnchorPoint.X==1)
	local _,left,right=Kit.columns(host,{order=3,side=true,hero=true,heroHeight=300})
	local _,noLeft,whole=Kit.columns(host,{order=4,side=false,hero=false,heroHeight=300})
	check("… the columns: side by side, or the rows whole",left.Size.X.Scale==Config.UiKit.HeroShare and right.Size.X.Scale==1-Config.UiKit.HeroShare and noLeft==nil and whole.Size.X.Scale==1)
	host:Destroy()
end
print("ALL CHECKS PASSED")
