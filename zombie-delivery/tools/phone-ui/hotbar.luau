-- 6.21, the clean hotbar (client/Hotbar.luau) run for real against the recorder (tools/phone-ui/mock.luau): a
-- computer's bar (HotbarLive) and a touch screen's (HotbarTouch). It checks the slots and their sizes, the slot in
-- your hand (lifted, grown, the red frame and glow) and the line over the bar, the count pills, the bag slot's fill
-- ring and "5/6" pill (6.21: it replaces the CARRYING pill; 6.20 Strong Back counted), that a slot, a key and the pill
-- go the same ways as before (Hud's useItem through Hotbar.onUse, Holster.choose, BagUi.open), MORE, and a touch
-- screen's filled slots only at 48 px or more. Not Studio's layout or fonts.
local M=require("./mock")
local Config=require("./Config")
local Inventory=require("./Inventory")
local BagUi=require("./BagUi")
local H=Config.Hotbar
local function check(name,condition,detail) assert(condition,name..(if detail~=nil then "  ("..tostring(detail)..")" else ""));print("ok    "..name) end
local function find(root,name) return root:FindFirstChild(name,true) end
local function near(a,b) return math.abs(a-b)<1e-6 end
local function sameColor(a,b) return a~=nil and b~=nil and near(a.R,b.R) and near(a.G,b.G) and near(a.B,b.B) end
local function stroke(button) return button:FindFirstChildOfClass("UIStroke") end
local pistol=require("./Economy").findWeapon("pistol")
local car=nil
for _,def in Config.Cars do if not def.bike and car==nil then car=def.id end end

-- ── A computer's bar ──────────────────────────────────────────────────────
M.touch=false
local Bar=require("./HotbarLive")
local gui=M.make("ScreenGui",{Name="HotbarHud"},M.gui)
local used,toasts,opened,more={},{},0,0
Bar.onUse=function(id) table.insert(used,id) end
Bar.toast=function(t) table.insert(toasts,t) end
Bar.onMore=function() more+=1 end
BagUi.onOpen=function() opened+=1 end
local state={items={medkit=4,molotov=1},kit={bag=true,tote=true},bag="tote",weapon="pistol",cars={}}
M.hand="gun"
Bar.setState(state)
Bar.start(gui)
local bar=gui:FindFirstChild("BottomBar")
local tray=bar and bar:FindFirstChild("Tray")
check("the bottom bar and its frosted tray",bar~=nil and tray~=nil and tray.BackgroundTransparency>0 and tray.BackgroundTransparency<1)
local width,height=Inventory.size(3+Config.ItemTuning.BarSlots)
check("the bar's size: eight slots, the line over them",bar.Size.X.Offset==width and bar.Size.Y.Offset==height and Bar.size().X==width,`{bar.Size.X.Offset} x {bar.Size.Y.Offset}`)
local slotsOk=true
for index=1,3 do slotsOk=slotsOk and tray:FindFirstChild(`Hand{index}`)~=nil end
for index=1,5 do slotsOk=slotsOk and tray:FindFirstChild(`Slot{index}`)~=nil and tray:FindFirstChild(`Slot{index}`).Visible end
check("three hand slots and five item slots, the empty ones shown on a computer",slotsOk and tray:FindFirstChild("Slot6")==nil)
check("no CARRYING pill any more (the bag slot carries it)",find(bar,"Carried")==nil)
local hand1,hand2,hand3=tray:FindFirstChild("Hand1"),tray:FindFirstChild("Hand2"),tray:FindFirstChild("Hand3")
check("a slot 72 px with its key small and grey",hand1.Size.X.Offset==H.Tile and hand1:FindFirstChild("Key").Text=="1" and hand1:FindFirstChild("Key").Visible and sameColor(hand1:FindFirstChild("Key").TextColor3,M.P.ink2))
check("the gun in your hand: lifted 12 px, 80 px, the red frame and glow",hand3.Size.X.Offset==H.Selected and hand3.Position.Y.Offset==-(H.PadY+H.Lift)
	and hand3:FindFirstChild("Glow").Visible and sameColor(stroke(hand3).Color,M.P.red) and stroke(hand3).Thickness==2)
check("the others not lifted, no glow",hand1.Position.Y.Offset==-H.PadY and not hand1:FindFirstChild("Glow").Visible and hand1.Size.X.Offset==H.Tile)
local line=bar:FindFirstChild("Selected")
check("the line over the bar: PISTOL and its damage (no ammo: the game has none)",line:FindFirstChild("Name").Text=="PISTOL" and line:FindFirstChild("Count").Text==`{pistol.damage*math.max(1,pistol.pellets)} DMG`,line:FindFirstChild("Count").Text)
local slot1,slot2,slot3=tray:FindFirstChild("Slot1"),tray:FindFirstChild("Slot2"),tray:FindFirstChild("Slot3")
check("the counts as pills at the bottom right corner",slot1:FindFirstChild("Count").Text=="4" and slot1:FindFirstChild("Count").Visible and slot1:FindFirstChild("Count").AnchorPoint.X==1
	and slot1:FindFirstChild("Count").Position.X.Offset==H.Overhang and slot2:FindFirstChild("Count").Text=="1")
check("an empty slot: no pill, dim",not slot3:FindFirstChild("Count").Visible and slot3.BackgroundTransparency>0.4)
check("the item keys 4 and 5 (Hotbar.slotOf)",Bar.slotOf("medkit")==4 and Bar.slotOf("molotov")==5 and slot1:FindFirstChild("Key").Text=="4")
check("the slots in a row: a slot and a gap apart",slot1.Position.X.Offset-hand3.Position.X.Offset==H.Tile+H.Gap and hand1.Position.X.Offset==Inventory.slotX(1))
slot1.Activated:Fire()
check("a slot's tap uses it through Hud's useItem (Hotbar.onUse)",used[#used]=="medkit")
Bar.useKey(5)
check("key 5: the molotov, the same path",used[#used]=="molotov")
Bar.useKey(6)
check("an empty slot's key: a toast",#toasts==1 and string.find(toasts[1],"Key 6 is empty",1,true)~=nil)
hand1.Activated:Fire()
check("a hand slot's tap asks for that hand (Holster.choose)",M.chosen[#M.chosen]=="fists")
Bar.useKey(2)
check("key 2: the bag, the same path",M.chosen[#M.chosen]=="bag")

-- The bag slot: the fill ring and its pill (what you carry on foot, 6.20 Strong Back counted).
local pill=hand2:FindFirstChild("Count")
local ring=hand2:FindFirstChild("Ring")
check("the bag slot has its fill ring (a track and two halves)",ring~=nil and ring:FindFirstChild("Track")~=nil and ring:FindFirstChild("Right")~=nil and ring:FindFirstChild("Left")~=nil and ring.Visible)
check("off duty, the gun out: your hands' room (the tote holds nothing while the gun is out)",pill.Text=="0/2" and pill.Visible and sameColor(pill.BackgroundColor3,BagUi.tint("cargo")),pill.Text)
M.hand="bag"
Bar.setState(state)
check("the bag in your hand: the hands and the tote (0/5)",pill.Text=="0/5",pill.Text)
check("the bag in your hand lifts instead",hand2.Size.X.Offset==H.Selected and hand3.Size.X.Offset==H.Tile and line:FindFirstChild("Name").Text=="CANVAS TOTE" and line:FindFirstChild("Count").Text=="0 / 5")
M.player:SetAttribute("Skills","strongBack:1")
Bar.setState(state)
check("6.20 Strong Back: a piece more in the hands and in the bag (0/7)",pill.Text=="0/7",pill.Text)
local function rotations() return find(ring:FindFirstChild("Right"),"UIGradient").Rotation,find(ring:FindFirstChild("Left"),"UIGradient").Rotation end
local right,left=rotations()
check("an empty bag: an empty ring",right==0 and left==180)
M.player:SetAttribute("BagRoom",4)
M.player:SetAttribute("PackRoom",4)
local job={mode="foot",packRoom=4,carried={{look="pizza",where="bag",order=1},{look="pizza",where="bag",order=1},{look="parcel",where="hands",order=2}}}
Bar.setJob(job)
check("on a run: what you carry over your room (3/7, the server's BagRoom)",pill.Text=="3/7" and line:FindFirstChild("Count").Text=="3 / 7",pill.Text)
right,left=rotations()
local r,l=Inventory.ring(3/7)
check("the ring 3/7 full",near(right,r) and near(left,l) and right<180 and left==180)
for _=1,3 do table.insert(job.carried,{look="cake",where="bag",order=3}) end
Bar.setJob(job)
right,left=rotations()
check("6 of 7: the right half full, the left half most of the way",pill.Text=="6/7" and right==180 and near(left,6/7*360),pill.Text)
check("the pill's tap opens BAG & ITEMS on what you carry (BagUi.open)",(function() pill:FindFirstChild("Open").Activated:Fire();return opened==1 end)())
slot2.MouseEnter:Fire()
check("hovering a slot puts its name in the line",line:FindFirstChild("Name").Text=="MOLOTOV" and line:FindFirstChild("Count").Text=="×1")
slot2.MouseLeave:Fire()
check("… and back to what is in your hand",line:FindFirstChild("Name").Text=="CANVAS TOTE")
M.player:SetAttribute("BagDown",M.Vector3.new(1,0,1))
M.hand="fists"
Bar.setState(state)
check("the bag on the ground: DOWN, no ring, the slot dim",pill.Text=="DOWN" and not ring.Visible and hand2.BackgroundTransparency>0.4)
M.player:SetAttribute("BagDown",nil)
Bar.setJob(nil)
M.player:SetAttribute("BagRoom",nil)
M.player:SetAttribute("PackRoom",nil)
M.player:SetAttribute("Skills",nil)

-- 6.7: more kinds than slots: the last slot is MORE (+N, the I window).
state={items={medkit=4,energy=2,molotov=1,repair=1,nitro=1,mine=2},kit={bag=true},bag="bag",weapon="pistol",cars={[car]=true}}
Bar.setState(state)
local slot5=tray:FindFirstChild("Slot5")
check("six kinds for five slots: the last is MORE (+2)",find(slot5,"More")~=nil and find(slot5,"More").Text=="+2" and not slot5:FindFirstChild("Count").Visible and Bar.slotOf("mine")==nil)
slot5.Activated:Fire()
check("MORE opens the I window's ITEMS (Hotbar.onMore)",more==1)
check("the line names MORE",(function() slot5.MouseEnter:Fire();local ok=line:FindFirstChild("Name").Text=="MORE ITEMS";slot5.MouseLeave:Fire();return ok end)())

-- ── A touch screen's bar ──────────────────────────────────────────────────
M.touch=true
local Touch=require("./HotbarTouch")
Touch.onUse=Bar.onUse
local gui2=M.make("ScreenGui",{Name="TouchHud"},M.gui)
M.hand="gun"
Touch.setState({items={medkit=4},kit={bag=true},bag="bag",weapon="pistol",cars={}})
Touch.start(gui2)
local tbar=gui2:FindFirstChild("BottomBar")
local ttray=tbar:FindFirstChild("Tray")
local size,least=Touch.size()
check("a touch screen: two item slots",Touch.SLOTS==2 and ttray:FindFirstChild("Slot2")~=nil and ttray:FindFirstChild("Slot3")==nil)
check("its slots never under 48 px (TouchMin)",H.Tile*least>=48-1e-6 and least<0.7,least)
check("its bar fits the 640 px phone's room (300 px at most at the least scale)",size.X*least<=300 and size.X==Inventory.size(5,true),size.X*least)
check("only the filled slots show: the empty one hidden, the tray shrinks to them",ttray:FindFirstChild("Slot1").Visible and not ttray:FindFirstChild("Slot2").Visible
	and ttray.Size.X.Offset==Inventory.size(4,true),ttray.Size.X.Offset)
check("no keys on a touch screen",not ttray:FindFirstChild("Hand1"):FindFirstChild("Key").Visible and not ttray:FindFirstChild("Slot1"):FindFirstChild("Key").Visible)
check("the bag's fill ring kept",ttray:FindFirstChild("Hand2"):FindFirstChild("Ring")~=nil and ttray:FindFirstChild("Hand2"):FindFirstChild("Count").Text=="0/2")
Touch.setState({items={medkit=4,energy=1},kit={bag=true},bag="bag",weapon="pistol",cars={}})
check("a second item: its slot shows, the tray grows",ttray:FindFirstChild("Slot2").Visible and ttray.Size.X.Offset==Inventory.size(5,true))
ttray:FindFirstChild("Slot2").Activated:Fire()
check("a tap uses it (the same path)",used[#used]=="energy")
print("ALL HOTBAR CHECKS PASSED")
