--!strict
-- Parameterized native tower trim. Protected bays are omitted; World retains its shell, windows and gameplay.
local Kit = require(script.Parent.Parent.BuildingLooks.Kit)
local Facade = {}
export type Wall = { nx: number, nz: number, door: number?, ladders: { number }?, zipRoof: boolean? }
local charcoal, stone, red, rust = {24,27,32}, {118,119,115}, {215,74,70}, {99,67,51}
function Facade.build(style: string, w: number, d: number, h: number, walls: { Wall }): Kit.Blueprint
 assert(w >= 36 and w <= 43 and d >= 36 and d <= 43 and h >= 16 and h <= 89, "Tower dimensions outside brief")
 assert(#walls>=1 and #walls<=2, "One or two street walls required")
 local details: { Kit.Detail } = {}
 local roofClear = false
 local function add(item: Kit.Detail)
  assert(#details < 30, "Tower art budget")
  item.transparency = item.transparency or 0 -- Kit disables small-detail shadows when transparency is explicit.
  table.insert(details, item)
 end
 for _, wall in walls do
  assert(math.abs(wall.nx)+math.abs(wall.nz)==1 and (wall.nx==0 or wall.nz==0), "Cardinal street wall required")
  if wall.door then assert(wall.door==wall.door and math.abs(wall.door)<1e6, "Finite door coordinate required") end
  for _, ladder in wall.ladders or {} do assert(ladder==ladder and math.abs(ladder)<1e6, "Finite ladder coordinate required") end
  if wall.zipRoof then roofClear = true end
 end
 for index, wall in walls do
  local span = if wall.nx ~= 0 then d else w
  local half = if wall.nx ~= 0 then w/2 else d/2
  local function on(name: string, along: number, y: number, out: number, wide: number, tall: number, deep: number, color: {number}, material: string?, label: string?, night: boolean?, beam: number?): boolean
   if y-tall/2 < 0 or y+tall/2 > h or math.abs(along)+wide/2 > span/2 then return false end
   if out+deep/2 > .8 and y-tall/2 < 7 then return false end
   if wall.door and y-tall/2 < 12 and math.abs(along-wall.door) < wide/2+6 then return false end
   for _, ladder in wall.ladders or {} do if math.abs(along-ladder) < wide/2+6 then return false end end
   if style ~= "boarded" then
    for floor=1,math.floor((h-4)/9) do
     if y-tall/2 < floor*9+1.5 and y+tall/2 > floor*9-1.5 and math.abs(along)-wide/2 < span/2-2 then return false end
    end
   end
   local x,z = along,wall.nz*(half+out)
   local size = {wide,tall,deep}
   local rotation = {0,if wall.nz==1 then 180 else 0,0}
   if wall.nx~=0 then x,z=wall.nx*(half+out),along;rotation={0,-wall.nx*90,0} end
   add({name=name..index,position={x,y,z},size=size,color=color,material=material or "Metal",rotation=rotation,label=label,night=night,beam=beam})
   return true
  end
  for _, side in {-1,1} do
   on("CornerPier"..side,side*(span/2-.5),h/2,.18,.65,h-.2,.25,stone,"Concrete")
  end
  -- String courses sit in the blank spandrels, not the caller's luminous window strips.
  for _, floor in {1,3,5} do
   if floor*9+2.2 < h then on("StringCourse"..floor,0,floor*9+2.2,.23,span-.2,.3,.4,stone,"Concrete") end
  end
  if style == "shopfront" then
   local along = span/2-5.0
   on("ShopGlass",along,3.9,.15,6.4,5.4,.12,{44,57,61},"Glass",nil,true)
   on("Shutter",along,5.8,.25,6.5,1.5,.15,charcoal,"Metal")
   for n=1,3 do on("ShutterRib"..n,along,5.2+n*.35,.35,6.3,.07,.05,stone) end
   on("ShopSill",along,1.1,.24,6.8,.22,.4,stone,"Concrete")
   on("ShopFascia",along,7.2,.3,6.8,.7,.2,charcoal,"Metal","ZDC PICKUP")
   on("ShopAwning",along,8.1,1.15,7,.2,2.1,charcoal)
   on("AwningRedEdge",along,8.05,2.16,7,.25,.08,red)
   if index==1 then on("PickUpLight",along,7.8,.3,1,.1,.2,{192,179,142},"Glass",nil,true,12) end
  elseif style == "boarded" then
   for n,along in {-9,9} do
    for floor=1,math.min(2,math.floor((h-4)/9)) do
     local y=floor*9
     on("Plywood"..n..floor,along,y,.22,4.6,3.5,.18,{126,100,70},"Wood","X  /  NO ENTRY")
     on("BoardBrace"..n..floor,along,y+.85,.36,4.8,.18,.08,rust,"Wood")
    end
   end
  elseif style == "fireescape" and index==1 then
   local along=span/2-.85 -- narrow industrial access stack beside the window strips
   local levels=math.min(2,math.floor((h-4)/9))
   for floor=1,levels do
    local y=floor*9+2.2
    on("EscapeDeck"..floor,along,y,1.3,1.35,.18,2.4,charcoal)
    on("EscapeRail"..floor,along,y+2,2.48,1.35,.12,.1,rust)
    on("EscapePost"..floor,along+.5,y+1,2.48,.1,2,.1,charcoal)
    if floor>1 then
     -- A compact alternating-tread access stair: central spine and three deep treads.
     if on("StairSpine"..floor,along,y-4.5,1.3,.15,9.2,.15,rust) then details[#details].rotation=if wall.nx~=0 then {0,-wall.nx*90,0} else {-15,if wall.nz==1 then 180 else 0,0} end
     for step=1,8 do on("StairTread"..floor..step,along,y-9+step,2.45-step*.25,1.35,.12,.4,charcoal) end
    end
   end
   on("DropLadderRail",along,4.6,.32,.12,6.7,.12,rust)
   for step=1,2 do on("DropRung"..step,along,2+step*1.7,.32,1.35,.1,.12,charcoal) end
  end
 end
 if style=="rooftop" and not roofClear then
  -- Roof furniture is separate from the shell; every piece stays within h..h+3.
  for _, side in {-1,1} do
   add({name="RoofParapetX"..side,position={side*(w/2-.2),h+.4,0},size={.4,.8,d},color=stone,material="Concrete"})
   add({name="RoofParapetZ"..side,position={0,h+.4,side*(d/2-.2)},size={w-.8,.8,.4},color=stone,material="Concrete"})
  end
  add({name="TankStand",position={-8,h+.3,6},size={5,.6,5},color=charcoal,material="Metal"})
  add({name="WaterTank",position={-8,h+1.55,6},size={1.9,4.4,4.4},rotation={0,0,90},shape="Cylinder",color=rust,material="CorrodedMetal"})
  add({name="TankCap",position={-8,h+2.6,6},size={.2,4.6,4.6},rotation={0,0,90},shape="Cylinder",color=charcoal,material="Metal"})
  add({name="TankRoofCrown",position={-8,h+2.8,6},size={.2,2.9,2.9},rotation={0,0,90},shape="Cylinder",color=charcoal,material="Metal"})
  add({name="ACUnit",position={7,h+.7,7},size={4,1.4,3},color=stone,material="Metal"})
  add({name="FanGrille",position={7,h+1.43,7},size={.06,2.3,2.3},rotation={0,0,90},shape="Cylinder",color=charcoal,material="Metal"})
  add({name="StairBulkhead",position={5,h+1.25,-5},size={5,2.5,4},color=stone,material="Concrete"})
  add({name="BulkheadDoor",position={5,h+1.1,-7.05},size={1.6,2.1,.1},color=charcoal,material="Metal",label="ROOF"})
 end
 return {id="tower-"..style,width=w,depth=d,height=h,details=details}
end
return Facade
