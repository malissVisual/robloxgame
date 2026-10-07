--!strict
-- ZDC RIDE charging dock: native parts, stable slot mounts and separately animated clamps.
local Builder = require(script.Parent.Parent.PolishArt.Builder)
local Dock = {}
function Dock.build(slots: number, pitch: number, name: string): Builder.Spec
 assert(slots==2 or slots==3, "Two or three rental slots required")
 assert(pitch>=5.6 and pitch<100, "Finite non-overlapping slot pitch required")
 local pieces: { Builder.Piece } = {}
 local mounts: { Builder.Mount } = {}
 local dark,red={24,27,32},{215,74,70}
 local span=(slots-1)*pitch+1.8
 local function add(id: string,size: Builder.Triple,at: Builder.Triple,color: Builder.Triple): Builder.Piece
  local p: Builder.Piece={name=id,size=size,at=at,color=color,material="Metal"};table.insert(pieces,p);return p
 end
 add("ChargingRail",{span,.35,.3},{0,.9,2.45},dark)
 add("RailRedBand",{span,.1,.05},{0,.96,2.27},red)
 for i=1,slots do
  local x=(i-(slots+1)/2)*pitch
  add("Bollard"..i,{.38,1.8,.38},{x,.9,2.45},dark)
  add("Clamp"..i,{.65,.18,.8},{x,.48,1.9},red)
  add("ContactShoe"..i,{.65,.38,.15},{x,.65,1.56},dark)
  table.insert(mounts,{name="Slot"..i,attach="Bollard"..i,at={x,0,1.6}})
 end
 local x=span/2+1.15
 add("PaymentPost",{.75,3.6,.65},{x,1.8,2.2},dark)
 add("PostRedHead",{.86,.75,.7},{x,3.75,2.2},red)
 local screen=add("PaymentScreen",{.58,.66,.05},{x,3,1.85},{132,156,143});screen.material="Glass";screen.night=true
 screen.slots={{name="Payment",text="ZDC / TAP"}}
 add("Reader",{.26,.32,.05},{x,2.38,1.85},{12,14,17})
 local board=add("DockBoard",{3.5,1.0,.12},{x-.8,4.75,2.1},dark)
 board.slots={{name="DockName",text=name,at={.04,.08},size={.92,.4}},{name="Brand",text="ZDC RIDE",at={.04,.53},size={.92,.4}}}
 local lamp=add("DockLamp",{.24,.2,.24},{x,4.25,2.2},red);lamp.material="Glass";lamp.night=true;lamp.light=8
 return {id="rental-dock-"..slots,pieces=pieces,attachments=mounts}
end
return Dock
