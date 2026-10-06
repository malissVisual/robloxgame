--!strict
-- Execute the actual garage preview; test snapshot stage/paint selection, live clones, cleanup and caching.
local Mock=require('./roblox-mock')
local Preview=require('./VehiclePreview')
local Vehicles=require('./Vehicles')
local Config=require('./Config')
local holder=Mock.Instance.new('Frame')
local car={id='van',stage=0,out=false,upgrades='stock'}
assert(Preview.show(holder,car))
local first=holder:FindFirstChild('VehicleModelPreview')
assert(first and first.CurrentCamera and first.CurrentCamera.FieldOfView==32)
assert(Preview.show(holder,car) and holder:FindFirstChild('VehicleModelPreview')==first,'preview rebuilt for unchanged data')
car.stage=3; car.paint='camo'
assert(Preview.show(holder,car))
local staged=holder:FindFirstChild('VehicleModelPreview')
assert(staged~=first and first.Parent==nil,'old preview not removed')
local painted=0
for _,p in staged:GetDescendants() do
    if p:IsA('BasePart') then
        assert(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery)
        if math.abs(p.Color.R-74/255)<.00001 then painted+=1 end
    end
end
assert(painted>20,'purchased paint missing')
local cars=Mock.Instance.new('Folder');cars.Name='Cars';cars.Parent=Mock.workspace
local live=Vehicles.displayModel(Config.Cars[1],Mock.CFrame.new(50,0,90),3,{engine=5,handling=5,armor=5,plow=5,trolley=1})
live:SetAttribute('OwnerId',1);live:SetAttribute('CarId','van');live.Parent=cars
car.out=true;car.upgrades='max kit'
assert(Preview.show(holder,car))
local viewport=holder:FindFirstChild('VehicleModelPreview');local ref=viewport:FindFirstChild('LiveSource')
assert(ref.Value==live,'wrong owner or vehicle cloned')
local tread,plow=0,0
for _,p in viewport:GetDescendants() do
    if p:IsA('BasePart') then
        assert(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery)
        if p.Name=='TreadRing' then tread+=1 elseif p.Name=='BullbarCross' then plow+=1 end
    end
    assert(p.ClassName~='Motor6D' and p.ClassName~='WeldConstraint' and p.ClassName~='ProximityPrompt','live mover copied into viewport')
end
assert(tread==8 and plow==2,'actual installed upgrades missing')
assert(Preview.show(holder,car) and holder:FindFirstChild('VehicleModelPreview')==viewport,'live preview rebuilt every state tick')
Preview.clear(holder)
assert(holder:FindFirstChild('VehicleModelPreview')==nil and viewport.Parent==nil,'closed garage keeps its preview')
assert(Preview.show(holder,car) and holder:FindFirstChild('VehicleModelPreview')~=nil,'preview not rebuilt after reopening')
assert(not Preview.show(holder,{id='bus',stage=0}),'company fallback changed')
print('Garage preview PASS: real stage, paint, live kit, cached viewport, cleared on close, sanitized clone and company fallback')
