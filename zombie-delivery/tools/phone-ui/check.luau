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
Phone.setState({phone=true,money=1240,kit={backpack=true},cars={}})
Phone.open()
check("phone opens without warning",Phone.isOpen() and #M.warnings==0)
-- 5.5: the eight approved apps and the HUD MENU's six (missions, bag, garage, crew, top, estate)
check("all fourteen apps constructed",#all(M.gui,function(object) return string.match(object.Name,"App$") and object.ClassName=="TextButton" end)==14)
check("glyphs work with empty uploaded IDs",#all(M.gui,function(object) return object.Name=="NativeGlyph" end)==14)
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
named("settingsApp").Activated:Fire()
named("Close").Activated:Fire()
check("home returns gamepad focus to the tapped tile",M.focus==named("settingsApp"))
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
	Phone.open();named(`{id}App`).Activated:Fire()
	check(`{id} app opens its window and puts the phone away`,windows[id]==true and not Phone.isOpen())
end
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
tap("+ ADD ORDER")
check("+ ADD ORDER fires AcceptJob and stays on the board",lastSent("AcceptJob").args[1]==12 and showing("board") and Phone.isOpen())
-- GIVE UP: two presses within 4 s.
Phone.open("orders")
local cancels=0
for _,sent in M.sent do if sent.name=="CancelJob" then cancels+=1 end end
named("GiveUp").Activated:Fire()
check("GIVE UP asks once first",lastSent("CancelJob")==nil and named("GiveUp").Text=="PRESS AGAIN TO GIVE IT UP")
named("GiveUp").Activated:Fire()
check("a second press gives the delivery up",lastSent("CancelJob")~=nil)
M.remotes.Job.OnClientEvent:Fire(nil)
-- On a delivery that takes no more orders the board says so.
M.remotes.Job.OnClientEvent:Fire({cargo="Gold",customer="Dee",total=1,pay=900,endsAt=M.now+100})
Phone.open("board")
check("on a delivery the board points to ORDERS",text("You are on a delivery")~=nil and text("OPEN ORDERS")~=nil)
M.remotes.Job.OnClientEvent:Fire(nil)
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
-- 6.0.1: every app opens in the popup and closes back to home; the phone never turns.
for _,id in {"orders","board","career","shop","messages","bank","settings","bag","garage"} do
	Phone.close();Phone.open()
	named(`{id}App`).Activated:Fire()
	check(`{id} opens in the centred popup`,showing(id) and upright() and blur()~=nil and named("Heading")~=nil and named("Glyph"):FindFirstChild("NativeGlyph")~=nil and #M.warnings==0)
	named("Close").Activated:Fire()
	check(`{id} closes back to the phone's home`,popup()==nil and blur()==nil and Phone.isOpen() and named("Home").Visible and upright())
end
-- The popup with motion (reduced motion off): it lands centred at full scale, dim and blurred; back on close.
M.services.GuiService.ReducedMotionEnabled=false
Phone.close();Phone.open()
named("boardApp").Activated:Fire()
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
