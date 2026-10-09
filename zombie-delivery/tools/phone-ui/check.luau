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
-- 6.12.5: the MAIN apps first (JOBS across, MISSIONS and TASKS under it, red-edged, with their live lines and bars),
-- then six smaller tiles; MORE keeps the other seven.
check("home: JOBS across the top, then MISSIONS and TASKS side by side",named("jobsApp").Parent==named("Main") and appIds(named("MainPair"))=="missions,tasks" and named("Main").LayoutOrder<named("Tiles").LayoutOrder)
for _,id in {"jobs","missions","tasks"} do
	local cell=named(`{id}App`)
	check(`the MAIN {id} tile: the red edge and a live line`,cell:FindFirstChildOfClass("UIStroke").Color==M.Theme.Contract.red and cell:FindFirstChild("Edge")~=nil and cell:FindFirstChild("Sub")~=nil and cell:FindFirstChild("Sub").Text~="")
end
check("MISSIONS and TASKS carry a progress bar",named("missionsApp"):FindFirstChild("Progress")~=nil and named("tasksApp"):FindFirstChild("Progress")~=nil and named("jobsApp"):FindFirstChild("Progress")==nil)
check("home: the six tiles MAP, SHOP, BAG & ITEMS, GARAGE, STYLE, MORE in order",appIds(named("Tiles"))=="map,shop,bag,garage,style,more")
for _,name in {"MAP","SHOP","BAG & ITEMS","GARAGE","STYLE","MORE"} do
	local label=text(name)
	check(`the {name} tile has its name and a one-line subtitle`,label~=nil and label.Parent.Parent==named("Tiles") and label.Parent:FindFirstChild("Sub")~=nil and label.Parent:FindFirstChild("Sub").Text~="")
end
check("MORE: career, crew, top, estate, bank, messages, settings",appIds(named("Rows"))=="career,crew,top,estate,bank,messages,settings")
-- 6.12.5: MISSIONS' line is the chapter you are at (Phone.missionInfo: MissionsUi.summary), with its bar and NEW.
do
	local info={name="First Shift",done=0,total=6,open=false,why="Level 4",new=false}
	Phone.missionInfo=function() return info end
	Phone.close();Phone.open()
	check("MISSIONS shut: why, in grey, no badge",named("missionsApp"):FindFirstChild("Sub").Text=="🔒 First Shift · Level 4" and not named("missionsApp"):FindFirstChild("Badge").Visible)
	info={name="First Shift",done=0,total=6,open=true,new=true}
	Phone.close();Phone.open()
	check("a chapter newly open: NEW on MISSIONS",named("missionsApp"):FindFirstChild("Badge").Visible and named("missionsApp"):FindFirstChild("Badge").Text=="NEW")
	info={name="Code Red",done=2,total=6,open=true,new=false}
	Phone.close();Phone.open()
	local fill=all(named("missionsApp"):FindFirstChild("Progress"),function(object) return object.ClassName=="Frame" end)
	check("MISSIONS on the way: the chapter, its missions done and the bar",named("missionsApp"):FindFirstChild("Sub").Text=="Code Red · 2 / 6" and #fill>0 and math.abs(fill[#fill].Size.X.Scale-1/3)<1e-6 and not named("missionsApp"):FindFirstChild("Badge").Visible)
	Phone.missionInfo=nil
end
check("MORE waits behind the tiles",named("Home").Visible and not named("More").Visible)
check("all sixteen apps constructed",#all(M.gui,function(object) return string.match(object.Name,"App$") and object.ClassName=="TextButton" end)==16)
check("the messages row is always on home",named("MessagesRow")~=nil and named("MessagesRow").Visible and text("No new messages")~=nil)
check("glyphs work with empty uploaded IDs",#all(M.gui,function(object) return object.Name=="NativeGlyph" end)==16)
do
	local icons=require("./Icons")
	icons.Ids.app_settings="rbxassetid://12345"
	local parent=M.make("Frame",{},M.gui)
	require("./PhoneContract").glyph(parent,"settings",30)
	check("uploaded icons resolve to asset IDs",parent:FindFirstChild("AppGlyph").Image=="rbxassetid://12345")
	icons.Ids.app_settings="";parent:Destroy()
end
check("no job has honest empty contract",text("READY FOR YOUR NEXT RUN")~=nil)
named("HomeContract").Activated:Fire()
-- 5.5: the board is in the phone; 6.0.1: in its centred popup. FULL BOARD opens the Dispatch board.
check("empty contract opens the board in the popup",Phone.isOpen() and showing("board") and text("JOB BOARD")~=nil and text("Calling the dispatcher...")~=nil)
check("the board asks the server for offers",M.sent[#M.sent].name=="RequestOffers")
check("the phone stays upright under the popup",upright() and named("Home").Visible and blur()~=nil and Phone.appOpen())
tap("FULL BOARD  [J]")
check("FULL BOARD opens the real board, the popup and its blur go",boards==1 and not Phone.isOpen() and popup()==nil and blur()==nil)
Phone.open()
check("home stands upright, no popup",upright() and popup()==nil and not Phone.appOpen())
local payload={stopLabel="Harbor warehouse",customer="Earl",cargo="Parcels",total=2,pay=180,endsAt=376,timeLimit=400,position=M.Vector3.new(150,0,100),mode="foot",stopCount=2,stopIndex=2,orders={{id=1,state="open",focused=true,pay=180,endsAt=376,stops={{label="ZDC DEPOT",kind="pickup",done=true},{label="HARBOR WAREHOUSE",kind="drop",current=true}}},{id=2,state="open",title="Medicine",pay=80,stops={{label="Clinic",current=true}}}}}
M.remotes.Job.OnClientEvent:Fire(payload)
check("home reflects incoming order",text("HARBOR WAREHOUSE")~=nil and text("$180")~=nil)
-- 6.5: during a run JOBS counts the open orders. 6.12.8: it opens the job list (BOARD), YOUR RUN on top; its DETAILS
-- (and the home's contract card) open ORDERS.
local jobsBadge=named("jobsApp"):FindFirstChild("Badge")
check("JOBS' badge counts the open orders",jobsBadge.Visible and jobsBadge.Text=="2" and named("jobsApp"):FindFirstChild("Sub").Text=="Your run · 2 orders")
named("jobsApp").Activated:Fire()
check("6.12.8: JOBS opens BOARD during a run, not ORDERS",showing("board") and text("JOB BOARD")~=nil and text("ORDERS")==nil)
check("6.12.8: YOUR RUN heads the board with DETAILS",named("YourRun")~=nil and text("Your run · 2 orders · $260")~=nil and text("DETAILS")~=nil)
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
check("bag opens in the same popup",(M.bagRendered or 0)>0 and Phone.isOpen() and showing("bag") and #all(M.gui,function(object) return object.Name=="AppPopup" end)==1 and named("BagRows")~=nil and upright())
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
tap("CYCLE SOUND MODE")
check("settings uses existing sound cycle",M.soundCycles==1)
check("gamepad focus moves into the popup",M.focus==text("CYCLE SOUND MODE"))
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
check("ESC in MORE goes back to the tiles",named("Home").Visible and not named("More").Visible and Phone.isOpen() and M.focus==named("jobsApp"))
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
-- The board: sections, two columns, locks, ACCEPT, a banner for a new board.
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
check("board sections: on foot, bike, each danger level",text("On foot · 1")~=nil and text("Bike · 1")~=nil and text("★★ Risky · 2")~=nil and text("★★★ Deadly · 1")~=nil)
check("the footNote heads ON FOOT",text("Two shops near you are shut.")~=nil)
check("a wide popup: two columns of cards",named("Columns")~=nil and named("Left")~=nil and named("Right")~=nil)
check("a card: the cargo → the customer, the pickup, the pay",text("LETTERS → ANN")~=nil and text("Post office → 12 Elm St, Old Town")~=nil and text("$40")~=nil)
tap("🔒 LEVEL 7")
check("a locked offer says why",string.find(toasts[#toasts] or "","level 7",1,true)~=nil and lastSent("AcceptJob")==nil)
tap("📦 NEEDS 6 SLOTS")
check("a too-big offer says why",toasts[#toasts]=="Your van holds 4.")
tap("ACCEPT")
check("ACCEPT fires AcceptJob with the offer's index",lastSent("AcceptJob").args[1]==11)
check("after ACCEPT the popup shows ORDERS",showing("orders") and text("ORDERS")~=nil and upright())
-- A run that takes more orders: + ADD ORDER keeps the board open.
local run={cargo="Letters",customer="Ann",total=1,pay=40,endsAt=M.now+100,timeLimit=200,position=M.Vector3.new(10,0,10),mode="foot",stack={can=true}}
M.remotes.Job.OnClientEvent:Fire(run)
for _,offer in offers do if offer.index==12 then offer.addOrder=true end end
check("an accepted offer leaves the phone's board",offers[1].index==12)
M.remotes.Offers.OnClientEvent:Fire(offers,M.now+240,{})
Phone.open("board")
tap("+ ADD")
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
	check("6.12.8: JOBS opens BOARD during a run",showing("board") and text("JOB BOARD")~=nil and text("You are on a delivery")==nil)
	-- YOUR RUN: one line an open order (what, from → to · pay · clock), the run's pay, the next stop.
	check("YOUR RUN: the open orders and what they pay together",named("YourRun")~=nil and text("Your run · 2 orders · $160")~=nil)
	check("YOUR RUN: one line an order, what and from → to",text("🚶  Pizza → Bob · Luigi's Pizza → 3 Oak Ave")~=nil and text("🚶  Letters → Ann · Post Office → 12 Elm St")~=nil and text("🚶  Cake → Flo")==nil)
	check("YOUR RUN: each line's pay and clock",text("$120 · 03:20")~=nil and text("$40 · 01:30")~=nil)
	check("YOUR RUN: the next stop",text("Next stop: PICK UP at Luigi's Pizza")~=nil)
	M.now+=10;require("./OrdersUi").tick()
	check("YOUR RUN's clocks tick",text("$120 · 03:10")~=nil and text("$40 · 01:20")~=nil)
	-- NEXT UP: the queue in order, what, where, pay, the next one's reason to wait, ✕.
	check("NEXT UP under YOUR RUN, in order",named("NextUp")~=nil and named("NextUp").LayoutOrder>named("YourRun").LayoutOrder and text("Next up · 2 / 6")~=nil and text("▶ They start on their own")~=nil
		and text("1  ★★  Crates → Cid")~=nil and text("2  🚶  Soup → Flo")~=nil)
	check("NEXT UP: where and the pay",text("Depot → Harbor")~=nil and text("Wok Dead → 9 Oak Ave")~=nil and text("$300")~=nil and text("$70")~=nil)
	check("NEXT UP: the next one says why it waits",text("⏸ Waits: needs your car: CALL CAR")~=nil and #all(M.gui,function(object) return object.Name=="Why" end)==1)
	named("Drop").Activated:Fire()
	check("NEXT UP's ✕ drops it through the JobQueue remote",M.lastSent("JobQueue").args[1]=="drop" and M.lastSent("JobQueue").args[2]==5)
	-- The rows: + QUEUE (the run is full, or another transport waiting for your bike), the locks, the queue full.
	check("the board's rows come under NEXT UP",named("AddAll").LayoutOrder>named("NextUp").LayoutOrder)
	local queueButtons=all(named("AppPopup"),function(object) return object.Text=="+ QUEUE" end)
	check("+ QUEUE on a row the full run can't take and on one waiting for your bike",#queueButtons==2 and text("🚲 RIDE YOUR BIKE")==nil and text("+ ADD")==nil)
	check("a locked row keeps its lock, a special and the paper round say why they can't",text("🔒 LEVEL 7")~=nil and #all(named("AppPopup"),function(object) return object.Text=="FINISH YOUR RUN" end)==2)
	tap("QUEUE FULL (6/6)")
	check("a full queue says so",toasts[#toasts]=="NEXT UP holds 6 jobs." and M.lastSent("JobQueue").args[1]=="drop")
	check("every row shows its pay",text("$55")~=nil and text("$130")~=nil and text("$50")~=nil and named("Pay")~=nil)
	queueButtons[1].Activated:Fire()
	check("+ QUEUE fires JobQueue with the offer's index and stays on the board",M.lastSent("JobQueue").args[1]=="queue" and M.lastSent("JobQueue").args[2]==21 and showing("board"))
	check("a queued offer leaves the phone's board",list[1].index==22 and text("$55")==nil)
	-- ADD ALL · $total sends the right request.
	check("ADD ALL shows what it adds and pays (not the special, not the round)",text("ADD ALL · $235")~=nil and text("3 jobs: 3 wait in NEXT UP.")~=nil)
	tap("ADD ALL · $235")
	check("ADD ALL fires JobQueue addAll",M.lastSent("JobQueue").args[1]=="addAll" and #M.lastSent("JobQueue").args==1)
	-- review: PAUSE, CLEAR ALL; the idle start's "Starts in a few seconds"; PAUSED with RESUME.
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
	-- A run that takes no more orders (a mission): the board still shows, its rows queue.
	M.remotes.Job.OnClientEvent:Fire({cargo="Gold",customer="Dee",total=1,pay=900,endsAt=M.now+100,stars=3,address="Vault",mission={name="Code Red"}})
	Phone.open("board")
	check("6.12.8: on a mission the board shows YOUR RUN and + QUEUE, not 'You are on a delivery'",text("You are on a delivery")==nil and text("Your run · 1 order · $900")~=nil and text("★★★  Gold → Dee · Vault")~=nil and text("+ QUEUE")~=nil)
	-- Off duty the rows are ACCEPT again; the queue's state clears.
	M.remotes.Job.OnClientEvent:Fire(nil)
	M.remotes.JobQueue.OnClientEvent:Fire("state",{max=6,list={}})
	Phone.open("board")
	check("off duty: ACCEPT, no YOUR RUN, no NEXT UP",text("ACCEPT")~=nil and text("+ QUEUE")==nil and named("YourRun")==nil and named("NextUp")==nil)
	check("6.12.8: no warnings on the board",#M.warnings==0)
	Phone.close()
end

-- 6.12.11: the job pictures (shared/JobThumbs.luau, client/JobThumbUi.luau). A row's card opens with its business's
-- picture: while the image id is empty a slim banner (the cargo emoji and the business's name), once uploaded an
-- ImageLabel with that id (cropped to about 2.4 : 1) with the name over it; a row without a picture (no business: an
-- older server's) has neither. NEXT UP's rows: a small square once uploaded, nothing while empty.
do
	local JobThumbs=require("./JobThumbs")
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
	local function cardOf(title) local label=text(title);return label and label.Parent and label.Parent.Parent end
	local function inPopup(name) return all(named("AppPopup"),function(object) return object.Name==name end) end
	local pizza=cardOf("PIZZAS → HANNAH")
	local banner=pizza and pizza:FindFirstChild("ThumbBanner")
	check("6.12.11: an empty image id: a slim banner on top of the card, the business's name and its emoji",banner~=nil and banner.LayoutOrder<text("PIZZAS → HANNAH").Parent.LayoutOrder
		and banner:FindFirstChild("Business").Text=="LUIGI'S PIZZA" and banner:FindFirstChild("Emoji").Text=="🍕" and banner.Size.Y.Offset<=30)
	check("… a special's by its job type, the round's, none for a row without a business",cardOf("CASH TRANSPORT: CASH"):FindFirstChild("ThumbBanner"):FindFirstChild("Business").Text=="FIRST ZOMBIE BANK"
		and cardOf("MORNING PAPERS → 12 DOORS ON ELM ST"):FindFirstChild("ThumbBanner"):FindFirstChild("Business").Text=="THE DAILY UNDEAD"
		and cardOf("CRATES → CID"):FindFirstChild("ThumbBanner")==nil and #inPopup("ThumbBanner")==3)
	check("… no image while the ids are empty, NEXT UP's row as before",#inPopup("Picture")==0 and #inPopup("Thumb")==0 and #inPopup("ThumbSquare")==0 and text("1  🚶  Soup → Flo").Position.X.Offset==0)
	JobThumbs.Images.pizzeria="rbxassetid://424242"
	JobThumbs.Images.noodles="rbxassetid://515151"
	Phone.close();Phone.open("board")
	pizza=cardOf("PIZZAS → HANNAH")
	local strip=pizza and pizza:FindFirstChild("Thumb")
	local picture=strip and strip:FindFirstChild("Picture")
	check("6.12.11: an uploaded id: an ImageLabel with that id across the top of the card, cropped",picture~=nil and picture.ClassName=="ImageLabel" and picture.Image=="rbxassetid://424242"
		and picture.ScaleType.Name=="Crop" and strip.LayoutOrder<text("PIZZAS → HANNAH").Parent.LayoutOrder and pizza:FindFirstChild("ThumbBanner")==nil)
	check("… the business's name on a dark label over its bottom-left corner",strip:FindFirstChild("Business").Text=="LUIGI'S PIZZA" and strip:FindFirstChild("Business").AnchorPoint.Y==1 and strip.ClipsDescendants==true)
	local size=strip.AbsoluteSize
	check("… about 2.4 : 1 (its height follows its width)",size.Y>0 and math.abs(size.X/size.Y-2.4)<0.05)
	check("… the rest of the card unchanged: the pay, the route, the chips, ACCEPT",text("$60")~=nil and text("Luigi's Pizza → 3 Oak Ave")~=nil and pizza:FindFirstChild("Chips")~=nil and #inPopup("ThumbBanner")==2)
	local square=named("NextUp") and all(named("NextUp"),function(object) return object.Name=="ThumbSquare" end)[1]
	check("6.12.11: NEXT UP's row: a small square of the picture, its words beside it",square~=nil and square.Image=="rbxassetid://515151" and square.ScaleType.Name=="Crop" and text("1  🚶  Soup → Flo").Position.X.Offset==44)
	tap("ACCEPT")
	check("… ACCEPT still takes the row",lastSent("AcceptJob").args[1]==31)
	JobThumbs.Images.pizzeria=""
	JobThumbs.Images.noodles=""
	M.remotes.Job.OnClientEvent:Fire(nil)
	M.remotes.JobQueue.OnClientEvent:Fire("state",{max=6,list={}})
	check("6.12.11: no warnings with the pictures",#M.warnings==0)
	Phone.close()
end

-- CAREER and SHOP: two columns in the wide popup, the phone upright.
for _,id in {"career","shop"} do
	Phone.open(id)
	check(`{id} opens in the popup in two columns`,showing(id) and upright() and named("Columns")~=nil and #M.warnings==0)
end
-- GARAGE: BRING MY CAR, MY BIKE, CALL CAR.
local bike,car
for _,def in Config.Cars do
	if def.bike and not bike then bike=def.id end
	if not def.bike and not def.company and not car then car=def.id end
end
Phone.setState({phone=true,money=1600,kit={},cars={[bike]=true,[car]=true}})
Phone.open("garage")
check("garage opens in the popup",showing("garage") and upright())
tap("BRING MY CAR")
check("BRING MY CAR fires SpawnCar and puts the phone away",lastSent("SpawnCar")~=nil and not Phone.isOpen())
Phone.open("garage");tap("🚲 MY BIKE")
check("MY BIKE rides the bike",lastSent("Equip").args[1]=="ride")
Phone.open("garage");tap("🚐 CALL CAR")
check("CALL CAR calls the car",lastSent("Equip").args[1]=="drive")
-- 5.6: ZDC RIDE, the nearest rental dock and the GPS to it.
Phone.open("garage")
local rideLine=all(M.gui,function(object) return type(object.Text)=="string" and string.find(object.Text,"ZDC RIDE · nearest dock",1,true)~=nil end)[1]
check("garage names the nearest ZDC RIDE dock",rideLine~=nil and #M.warnings==0)
local waypoints=0
local setWaypoint=M.MapView.setWaypoint
M.MapView.setWaypoint=function() waypoints+=1 end
text("📍 GPS").Parent.Activated:Fire()
check("ZDC RIDE's GPS sets the waypoint",waypoints==1)
M.MapView.setWaypoint=setWaypoint
-- SETTINGS: the keys and the version; BANK: what you earned since you joined.
local sounds=0
Phone.onSound=function() sounds+=1 end
Phone.open("settings")
check("settings lists every key and the version",text("Weapon wheel")~=nil and text("Sprint")~=nil and text(`ZDC courier terminal · Zombie Delivery {Config.Version}`)~=nil)
tap("CYCLE SOUND MODE")
check("settings' sound goes through Phone.onSound",sounds==1)
Phone.open("bank")
check("bank shows what you earned since you joined",text("+$360")~=nil)
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
named("Close").Activated:Fire()
check("read: the count goes",not named("Unread").Visible and text("No new messages")~=nil)
-- 6.0.1: every app opens in the popup and closes back to home; the phone never turns.
-- 6.5: the tiles (JOBS off duty: the board) and MORE's rows; each closes back to the page it came from.
for _,entry in {{"jobs","board"},{"shop","shop"},{"bag","bag"},{"garage","garage"},{"career","career",true},{"tasks","tasks"},{"messages","messages",true},{"bank","bank",true},{"settings","settings",true}} do
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
-- 6.12.7: five shops: the bikes are Dead End Motors' (its CARS and BIKES counters), no Spoke & Chain row.
check("SHOP lists the five shops first",named("Shops")~=nil and named("Shops").LayoutOrder<named("Columns").LayoutOrder
	and named("Shop_bags")~=nil and named("Shop_supplies")~=nil and named("Shop_guns")~=nil and named("Shop_dealer")~=nil and named("Shop_mechanic")~=nil
	and named("Shop_bikes")==nil and named("Shop_guns").LayoutOrder<named("Shop_dealer").LayoutOrder and named("Shop_dealer").LayoutOrder<named("Shop_mechanic").LayoutOrder)
check("6.6: ZDC Bags first, the bags there; no backpack anywhere",named("Shop_bags").LayoutOrder<named("Shop_supplies").LayoutOrder and text("ZDC Bags")~=nil and text("Bags (sprint with your deliveries)")~=nil
	and all(M.gui,function(object) return type(object.Text)=="string" and string.find(string.lower(object.Text),"backpack",1,true)~=nil end)[1]==nil)
check("each shop says what it sells",text("Last Stop Supplies")~=nil and text("Items and vests, next to the bags")~=nil and text("Lead & Co.")~=nil and text("Guns, gun upgrades, a baseball bat")~=nil
	and text("Dead End Motors")~=nil and text("Cars, vans, trucks · bikes, the E-Scooter, bike gear")~=nil and text("Wrench Garage")~=nil and text("Stages, car upgrades, gear, paint, car guns, repairs")~=nil) -- (6.7: what each really sells; 6.12.7: the bikes at Dead End Motors)
check("6.12.7: Spoke & Chain is gone from SHOP, its bikes named as part of Dead End Motors",all(M.gui,function(object) return type(object.Text)=="string" and string.find(string.upper(object.Text),"SPOKE",1,true)~=nil end)[1]==nil
	and caps("Dead End Motors · bikes")~=nil and caps("Dead End Motors · vehicles")~=nil
	and all(M.gui,function(object) return type(object.Text)=="string" and string.find(object.Text,"Dead End Motors, the BIKES counter",1,true)==1 end)[1]~=nil)
do
	-- 6.12.7: the bikes' Set GPS goes to the BIKES counter in Dead End Motors (Map.Shops.bikes), named as part of it.
	local waypoint
	local setWaypoint=M.MapView.setWaypoint
	M.MapView.setWaypoint=function(at) waypoint=at end
	local header=caps("Dead End Motors · bikes").Parent
	local pill=all(header,function(object) return object.Name=="Pill" end)[1]
	pill.Activated:Fire()
	local counter=require("./Map").Shops.bikes
	check("the bikes' Set GPS: the BIKES counter at Dead End Motors",waypoint~=nil and waypoint.X==counter.x and waypoint.Z==counter.z and toasts[#toasts]=="GPS: Dead End Motors · Bikes")
	M.MapView.setWaypoint=setWaypoint
end
do
	local waypoint
	local setWaypoint=M.MapView.setWaypoint
	M.MapView.setWaypoint=function(at) waypoint=at end
	named("Shop_supplies").Activated:Fire()
	local gear=require("./Map").Shops.supplies -- (6.12.2: Last Stop Supplies is the gear stall's GEAR counter at the depot)
	check("a shop's tap sets the GPS there, puts the phone away and says so",waypoint~=nil and waypoint.X==gear.x and waypoint.Z==gear.z and not Phone.isOpen() and toasts[#toasts]=="GPS set: Last Stop Supplies")
	M.MapView.setWaypoint=setWaypoint
end
-- 6.5: BAG & ITEMS, the I window's tabs: ITEMS (USE through the bottom bar's path), BAGS; BAG during a run.
Phone.setState({phone=true,money=1600,kit={},cars={},items={medkit=2}})
Phone.open();named("bagApp").Activated:Fire()
check("off duty BAG & ITEMS opens on ITEMS, no BAG tab",showing("bag") and text("BAG & ITEMS")~=nil and named("Tab_items")~=nil and named("Tab_bags")~=nil and named("Tab_bag")==nil and text("➕  MEDKIT")~=nil and text("×2")~=nil)
check("6.7: no car, no car items in ITEMS (the energy drink is there)",text("🔧  REPAIR KIT")==nil and text("⛽  JERRY CAN")==nil and text("🥤  ENERGY DRINK")~=nil)
check("an item names its key in the bottom bar",all(M.gui,function(object) return type(object.Text)=="string" and string.find(object.Text,"Key 5.",1,true)~=nil end)[1]~=nil)
for _,button in all(named("AppPopup"),function(object) return object.Text=="USE" end) do
	if button.Parent==text("➕  MEDKIT").Parent.Parent then button.Activated:Fire() end
end
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
	check("TASKS' live line on home: the reward waiting and today's dailies",named("tasksApp"):FindFirstChild("Sub").Text=="1 to claim · 1 / 3 today")
	local fill=all(named("tasksApp"):FindFirstChild("Progress"),function(object) return object.ClassName=="Frame" end)
	check("TASKS' bar: a third of the dailies done",#fill>0 and math.abs(fill[#fill].Size.X.Scale-1/3)<1e-6)
	named("tasksApp").Activated:Fire()
	check("TASKS opens in the popup",showing("tasks") and text("TASKS")~=nil and upright() and #M.warnings==0)
	check("three daily cards, the bonus card and the weekly card",named("Task_1")~=nil and named("Task_2")~=nil and named("Task_3")~=nil and named("Task_bonus")~=nil and named("Task_weekly")~=nil)
	check("a card: its title, its progress and its reward",text("Ride a zip line")~=nil and text("0 / 1")~=nil and text("$120 · 80 XP")~=nil and text("20 / 150")~=nil)
	check("money tasks read in dollars",text("$40 / $80")~=nil)
	check("how long until the tasks are new",text("New tasks in 3 h 2 min · at 00:00 UTC")~=nil and text("New in 2 d 1 h · Monday 00:00 UTC")~=nil)
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
	check("every daily done: CLAIM BONUS",named("Claim_bonus")~=nil and M.focus==named("Claim_bonus"))
	named("Claim_bonus").Activated:Fire()
	check("CLAIM BONUS asks for the bonus",lastSent("Tasks").args[1]=="claim" and lastSent("Tasks").args[2]=="bonus")
	check("before the reset the countdown runs",text("New tasks in 3 h 2 min · at 00:00 UTC")~=nil)
	M.now=state.dayEnds+1;require("./TasksApp").tick()
	check("the phone's ticker counts down to the reset",text("New tasks in 0 s · at 00:00 UTC")~=nil)
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
	Phone.setState({phone=true,money=300,kit={},cars={},style={owned={},worn={}}})
	Phone.open()
	check("home's STYLE tile: your looks",named("styleApp").Parent==named("Tiles") and text("Your looks")~=nil)
	named("styleApp").Activated:Fire()
	check("the line under the tabs says who sells them",text("Buy them from Dot at the gear stall; wear them from here, anywhere. Looks only: no item changes a number of the game; your own look stays under them.")~=nil)
	check("STYLE opens in the popup on COURIER",showing("style") and text("STYLE")~=nil and named("Tab_courier")~=nil and named("Tab_vehicle")~=nil and named("Tab_courier"):FindFirstChild("Underline")~=nil)
	check("its sections: hats, jackets, the vest's and the bag's colours",text("Hats · your own")~=nil and text("Jackets · your own")~=nil and text("Courier Vest colour · your own")~=nil and text("Bag colour · your own")~=nil)
	check("the live preview shows the courier with the first item",#M.previews>0 and M.previews[#M.previews].tab=="courier" and M.previews[#M.previews].id=="cap_red" and named("Preview")~=nil)
	check("a card an item: its colours, name, price",named("Style_cap_red")~=nil and text("BACKWARDS CAP · ZDC RED")~=nil and inCard("cap_red","Colour1")~=nil and inCard("cap_red","Colour2")~=nil and text("$120")~=nil)
	check("a reward is flagged",inCard("cap_gold","Main")~=nil and inCard("cap_gold","Main").Text=="REWARD ONLY" and text("🏆 REWARD")~=nil)
	check("a level's lock shows",text("🔒 LEVEL 4")~=nil)
	check("two columns of cards in a wide popup",named("Columns")~=nil)
	inCard("cap_red","Main").Activated:Fire()
	check("BUY asks the server with the item",styleSent()~=nil and styleSent().args[1]=="buy" and styleSent().args[2]=="cap_red")
	local before=#M.sent
	inCard("cap_gold","Main").Activated:Fire()
	check("a reward is never bought: it says so",#M.sent==before and string.find(toasts[#toasts] or "","not for sale",1,true)~=nil)
	inCard("leather_black","Main").Activated:Fire()
	check("too dear or too early: it says why",#M.sent==before and string.find(toasts[#toasts] or "","unlocks at level 6",1,true)~=nil)
	inCard("hoodie_grey","Main").Activated:Fire()
	check("not enough money: it says so",#M.sent==before and toasts[#toasts]=="Not enough money: Hoodie · Grey costs $350.")
	inCard("beanie_grey","Try").Activated:Fire()
	check("TRY previews it, no remote",#M.sent==before and M.previews[#M.previews].id=="beanie_grey" and named("Style_beanie_grey"):FindFirstChild("Accent")~=nil and named("Style_beanie_grey"):FindFirstChild("Accent").Visible)
	-- the state brings the purchase back: "cash", OWNED → WEAR, WEARING → TAKE OFF
	Phone.setState({phone=true,money=380,kit={},cars={},style={owned={cap_red=true},worn={hat="cap_red"}}})
	check("the purchase plays cash once",M.played[#M.played]=="cash" and #M.played==1)
	check("WEARING and TAKE OFF",text("WEARING")~=nil and inCard("cap_red","Main").Text=="TAKE OFF" and text("Hats · Backwards Cap · ZDC Red")~=nil)
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
	check("at the gear stall a wrap is sold at Wrench Garage",inCard("wrap_sand","Main").Text=="AT WRENCH GARAGE")
	M.waypoint=nil
	press(M.Enum.KeyCode.Return)
	check("ENTER does the picked item's action (a wrap away from Gus: where, and the GPS)",toasts[#toasts]=="Gus sells it at Wrench Garage. It's on your GPS."
		and M.waypoint~=nil and M.waypoint.X==garage.x and M.waypoint.Z==garage.z and showing("style"))
	M.stand(garage.x,garage.z);StyleApp.tick()
	check("walked up to Wrench Garage: the cards follow, BUY there",inCard("wrap_sand","Main").Text=="BUY · $800" and inCard("bike_mint","Main").Text=="BUY · $150")
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
	check("away: a look for sale says where (AT THE GEAR STALL)",inCard("beanie_orange","Main").Text=="AT THE GEAR STALL" and inCard("cap_red","Main").Text=="WEAR")
	check("away: a reward and a level's lock as before",inCard("cap_gold","Main").Text=="REWARD ONLY" and inCard("cowboy","Main").Text=="BUY · $450")
	M.waypoint=nil
	inCard("beanie_orange","Main").Activated:Fire()
	check("its press: who sells it and the GPS to the gear stall, no remote",#M.sent==before and toasts[#toasts]=="Dot sells it at the gear stall. It's on your GPS."
		and M.waypoint~=nil and M.waypoint.X==gear.x and M.waypoint.Z==gear.z and showing("style"))
	inCard("beanie_orange","Try").Activated:Fire()
	check("away: TRY previews, the caption says who sells it",M.previews[#M.previews].id=="beanie_orange" and text("BEANIE · SAFETY ORANGE · Dot sells it at the gear stall.")~=nil and #M.sent==before)
	inCard("cap_red","Main").Activated:Fire()
	check("away: WEAR works anywhere",lastSent("Style").args[1]=="wear" and lastSent("Style").args[2]=="cap_red")
	local drawn=#M.previews
	StyleApp.tick()
	check("standing still draws nothing again",#M.previews==drawn)
	M.stand(gear.x,gear.z);StyleApp.tick()
	check("back at the gear stall: BUY again",inCard("beanie_orange","Main").Text=="BUY · $150")
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
for _,screen in {{320,448},{844,350},{1280,800}} do
	Phone.close();M.width,M.height=screen[1],screen[2];M.touch=true
	Phone.open()
	check(`resize {M.width}x{M.height} opens`,Phone.isOpen() and #M.warnings==0)
	check("home remains scrollable",named("Home").ClassName=="ScrollingFrame")
	check("the phone stays upright",upright())
	Phone.open("board")
	local size=popup().Size
	check(`the popup fits {M.width}x{M.height}`,size.X.Offset<=M.width*.92+.001 and size.Y.Offset<=M.height*.86+.001 and showing("board"))
	check("two columns only in a wide popup",(named("Columns")~=nil)==(size.X.Offset>=600))
end
-- The screen turns while an app is open: the popup fits again and the columns follow.
M.width,M.height=390,800
M.workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Fire();M.flush()
check("a resized popup fits the narrow screen in one column",popup().Size.X.Offset<=390*.92+.001 and named("Columns")==nil and upright() and #M.warnings==0)
Phone.close()
check("hold lifecycle clears phone",M.sent[#M.sent].name=="PhoneHold" and M.sent[#M.sent].args[1]==false)
print("ALL CHECKS PASSED")
