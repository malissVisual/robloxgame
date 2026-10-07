--!strict
-- Worn glass transit shelter; pure native geometry, named live-board slots and a clear sidewalk.
local Builder = require(script.Parent.Parent.PolishArt.Builder)
local Shelter = {}
function Shelter.build(line: Builder.Triple, stop: string, lines: string, chips: {Builder.Triple}?): Builder.Spec
 local pieces: { Builder.Piece } = {}
 local metal,glass,red = {24,27,32},{87,112,119},{215,74,70}
 local function add(name: string,size: Builder.Triple,at: Builder.Triple,color: Builder.Triple,material: string?): Builder.Piece
  local p: Builder.Piece={name=name,size=size,at=at,color=color,material=material or "Metal"};table.insert(pieces,p);return p
 end
 for _, x in {-5,5} do
  for _, z in {.25,2.8} do add("Frame"..x..z,{.15,7.3,.15},{x,3.65,z},metal) end
  local pane=add("SideGlass"..x,{.08,5.7,2.35},{x,3.7,1.5},glass,"Glass");pane.transparency=.56
  add("SideSkirting"..x,{.12,.6,2.65},{x,.5,1.5},metal)
 end
 for n,x in {-3.32,0,3.32} do
  local pane=add("BackGlass"..n,{3.2,5.7,.08},{x,3.7,2.84},glass,"Glass");pane.transparency=.56
  if n<3 then add("Mullion"..n,{.1,6.4,.12},{x+1.65,3.5,2.85},metal) end
 end
 add("Roof",{10.4,.22,3},{0,7.4,1.5},metal)
 local fascia=add("RouteFascia",{10.3,.42,.1},{0,7.45,.07},line);fascia.lineColor=true
 add("BackRail",{10,.1,.1},{0,1.1,2.8},metal)
 add("BenchSeat",{5.8,.25,.85},{-.85,1.65,2.13},{108,98,81},"Wood")
 add("BenchBack",{5.8,.8,.14},{-.85,2.25,2.56},{108,98,81},"Wood")
 for _,x in {-2.8,1.1} do add("BenchLeg"..x,{.18,1.5,.65},{x,.8,2.13},metal) end
 add("SignPole",{.14,7.8,.14},{5.45,3.9,.4},metal)
 local stopBoard=add("StopPlate",{2.2,1.2,.14},{5.45,7.2,.35},metal)
 stopBoard.slots={{name="StopName",text=stop,at={.04,.08},size={.92,.43}},{name="Lines",text=lines,at={.04,.54},size={.92,.26}}}
 local routeColors=chips or {line}
 assert(#routeColors>=1 and #routeColors<=3,"One to three line chips required")
 for n,color in routeColors do add("LineChip"..n,{.32,.16,.04},{5.45+(n-(#routeColors+1)/2)*.6,6.73,.25},color,"SmoothPlastic") end
 local badge=add("BusPlate",{2.2,.55,.16},{5.45,8.08,.35},line);badge.lineColor=true;badge.slots={{name="Bus",text="BUS / ZDC"}}
 local arrivals=add("ArrivalsBoard",{3.8,1.25,.14},{-2.5,5.9,2.65},metal)
 arrivals.slots={{name="Arrivals",text="NEXT BUS  /  -- MIN"}}
 add("AdCase",{2.3,5,.25},{3.48,3.5,2.65},metal)
 local ad=add("AdPoster",{2.05,4.7,.06},{3.48,3.5,2.48},{193,184,161},"Glass");ad.night=true
 ad.slots={{name="AdHeadline",text="ZDC",at={.05,.1},size={.9,.25}},{name="AdTagline",text="THE CITY STILL NEEDS YOU.",at={.06,.57},size={.88,.3}}}
 add("AdRedStripe",{2.05,.24,.07},{3.48,2.2,2.42},red)
 add("Bin",{.9,1.7,.8},{-4.25,.85,2.23},metal)
 add("BinLid",{.95,.14,.85},{-4.25,1.78,2.23},{106,116,110})
 add("BinSlot",{.58,.22,.05},{-4.25,1.52,1.8},{8,9,10})
 add("KerbLine",{10.4,.025,.3},{0,.018,-.4},{216,175,56},"SmoothPlastic")
 local lamp=add("CeilingLight",{2.4,.08,.18},{0,7.24,1.25},{202,187,153},"Glass");lamp.night=true;lamp.light=12
 return {id="transit-shelter",pieces=pieces}
end
return Shelter
