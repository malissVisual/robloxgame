--!strict
-- Industrial rooftop zip deck and caged native Truss ladder. Caller retains load-bearing/climb gameplay hulls.
local Builder = require(script.Parent.Parent.PolishArt.Builder)
local Zip = {}
local dark,red,steel={24,27,32},{215,74,70},{124,133,133}
local function add(pieces: {Builder.Piece},name: string,size: Builder.Triple,at: Builder.Triple,color: Builder.Triple): Builder.Piece
 local p: Builder.Piece={name=name,size=size,at=at,color=color,material="Metal"};table.insert(pieces,p);return p
end
function Zip.platform(size: number, height: number, name: string): Builder.Spec
 assert(size>=5 and size<=10 and height>=5 and height<=10,"Zip dimensions outside art range")
 local pieces: {Builder.Piece}={}
 local half=size/2
 add(pieces,"Platform",{size,.2,size},{0,-.1,0},dark)
 for _,side in {-1,1} do
  add(pieces,"SideRail"..side,{.12,.12,size},{side*(half-.08),3,0},steel)
  add(pieces,"SideToe"..side,{.12,.25,size},{side*(half-.08),.2,0},red)
  for _,z in {-half+.2,half-.2} do add(pieces,"Post"..side..z,{.14,3,.14},{side*(half-.08),1.5,z},steel) end
 end
 add(pieces,"BackRail",{size,.12,.12},{0,3,half-.08},steel)
 add(pieces,"BackToe",{size,.25,.12},{0,.2,half-.08},red)
 for _,side in {-1,1} do add(pieces,"GantryLeg"..side,{.24,height,.24},{side*2.35,height/2,0},dark) end
 add(pieces,"GantryBeam",{5.25,.32,.32},{0,height,0},dark)
 add(pieces,"CableSaddle",{.5,.5,.65},{0,height,0},red)
 local board=add(pieces,"ZipBoard",{2.5,.85,.12},{-2.35,4.5,-.2},dark);board.slots={{name="ZipName",text=name},{name="ZipInstruction",text=""}}
 local lamp=add(pieces,"ReadyLamp",{.18,.18,.18},{2.35,height-.4,-.2},red);lamp.material="Glass";lamp.night=true;lamp.light=8
 add(pieces,"LaunchStripe",{size-.6,.025,.22},{0,.025,-half+.32},red)
 add(pieces,"DeckSeam",{.06,.025,size},{0,.025,0},steel)
 return {id="zip-platform",pieces=pieces,attachments={{name="CableAnchor",attach="GantryBeam",at={0,height,0}}}}
end
function Zip.ladder(height: number): Builder.Spec
 assert(height>=2 and height<=100,"Finite ladder height required")
 local pieces: {Builder.Piece}={}
 local ladder=add(pieces,"ClimbTruss",{2,height,2},{0,height/2,0},steel);ladder.shape="Truss"
 if height>10 then
  local bottom=math.min(10.2,height-.3)
  local top=height-.15
  for n,y in {bottom,top} do
   for _,side in {-1,1} do add(pieces,"CageSide"..n..side,{.1,.12,1.9},{side*1.05,y,-.65},red) end
   add(pieces,"CageFront"..n,{2.2,.12,.1},{0,y,-1.55},red)
  end
  for _,side in {-1,1} do add(pieces,"CageSpine"..side,{.08,top-bottom,.08},{side*1.05,(bottom+top)/2,-1.55},dark) end
 end
 return {id="zip-ladder",pieces=pieces,attachments={{name="ClimbTop",attach="ClimbTruss",at={0,height,1.6}}}}
end
return Zip
