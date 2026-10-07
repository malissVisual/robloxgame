--!strict
-- Non-blocking city-bus finish, relative to the chassis TOP (CFrame.new(0,.6,0)); no gameplay changes.
local Builder = require(script.Parent.Parent.PolishArt.Builder)
local Bus = {}
function Bus.build(): Builder.Spec
 local pieces: { Builder.Piece } = {}
 local dark,red,grime={24,27,32},{215,74,70},{78,70,57}
 local function add(name: string,size: Builder.Triple,at: Builder.Triple,color: Builder.Triple,line: boolean?): Builder.Piece
  local p: Builder.Piece={name=name,size=size,at=at,color=color,material="Metal",lineColor=line};table.insert(pieces,p);return p
 end
 add("LineBandLeft",{.08,.5,23.5},{-4.08,1.9,0},red,true)
 -- Deliberately split around the front-right boarding opening at z=-9.6.
 add("LineBandRightFront",{.08,.5,.35},{4.08,1.9,-11.82},red,true)
 add("LineBandRightRear",{.08,.5,19},{4.08,1.9,2.5},red,true)
 add("LineBandBack",{8.1,.5,.08},{0,1.9,12.08},red,true)
 add("LineBandFront",{8.1,.5,.08},{0,1.9,-12.08},red,true)
 local roof=add("TransitRoofSign",{6.9,.56,.08},{0,6.4,-12.16},dark);roof.slots={{name="TransitBrand",text="ZDC TRANSIT"}}
 local board=add("DestinationBoard",{6.4,1.1,.08},{0,5.5,-11.27},dark)
 board.slots={{name="LineNumber",text="01",at={.02,.06},size={.2,.88}},{name="LineName",text="DOWNTOWN",at={.25,.06},size={.73,.88}}}
 for _,side in {-1,1} do
  add("MirrorArm"..side,{.65,.12,.12},{side*3.88,4.35,-11.3},dark)
  local mirror=add("Mirror"..side,{.14,.9,.48},{side*4.15,4.05,-11.4},{126,137,140});mirror.material="Glass"
  for n,z in {-5.5,0,5.5,9} do
   add("WindowMullion"..side..n,{.08,2.8,.1},{side*4.06,4.5,z},dark)
  end
  local finish=add("SkirtGrime"..side,{.06,.28,if side==1 then 18.8 else 23.4},{side*4.1,.2,if side==1 then 2.5 else 0},grime);finish.material="CorrodedMetal"
  for _,z in {-9.9,9.9} do
   if side==-1 or z>0 then -- Preserve the front-right door instead of painting over it.
    add("ArchTop"..side..z,{.1,.2,2.4},{side*4.16,1.22,z},dark)
    for _,endSign in {-1,1} do
     local edge=add("ArchEdge"..side..z..endSign,{.1,.18,1.25},{side*4.16,.8,z+endSign*1.55},dark)
     edge.rotation={endSign*42,0,0}
    end
   end
  end
 end
 local plate=add("BackFleetPlate",{2.2,.55,.08},{0,.6,12.11},dark);plate.rotation={0,180,0};plate.slots={{name="FleetCode",text="ZDC / 5.8"}}
 return {id="city-bus-livery",pieces=pieces}
end
return Bus
