--!strict
-- Execute the actual Vehicles factory, audit moving-part welds and serialize its resulting display geometry.
-- 10.6 (only the sandbox is the game): the one van it builds, the ZDC Sprinter (Config.Sandbox.Van): its working build
-- audited (its hinges, its wheels, its sliding door, its back's attachment; no seats) and its display build printed.
local Mock = require('./roblox-mock')
local Vehicles = require('./Vehicles')
local Config = require('./Config')
local function encode(v)
	local kind=type(v)
	if kind=='string' then return (string.gsub(string.format('%q',v),'\\\n','\\n')) end -- (8.0: %q writes a label's newline as a backslash and a newline)
	if kind=='number' or kind=='boolean' then return tostring(v) end
	if kind=='nil' then return 'null' end
	local out={}
	if #v>0 then for _,x in v do table.insert(out,encode(x)) end; return '['..table.concat(out,',')..']' end
	for k,x in v do table.insert(out,encode(k)..':'..encode(x)) end
	return '{'..table.concat(out,',')..'}'
end
local function triple(v) return {v.X,v.Y,v.Z} end
local function audit(built, display)
	local model=built.model
	local welds={}
	for _,p in model:GetDescendants() do if p.ClassName=='WeldConstraint' then welds[p.Part1]=p.Part0 end end
	for _,p in model:GetDescendants() do
		if p:IsA('BasePart') and p:GetAttribute('FleetFinish') then
			assert(not p.CanCollide and not p.CanQuery and not p.CanTouch and p.Massless, p.Name..' affects physics')
			assert(welds[p]~=nil,p.Name..' has no weld')
			if p.Shape=='Cylinder' then assert(math.abs(p.Size.Y-p.Size.Z)<.00001,p.Name..' has a flattened cylinder') end
			if p.Parent.Name=='BackDoor' then assert(welds[p]==p.Parent,p.Name..' will not follow its door') end
		end
		if p:IsA('BasePart') then
			for _,s in triple(p.Size) do assert(s>0 and s<2048 and s==s) end
		end
		assert(p.ClassName~='Seat' and p.ClassName~='VehicleSeat','a seat in the van (10.6: nobody sits in it)')
	end
	if not display then
		assert(model.PrimaryPart:FindFirstChild('CargoDoor') and model.PrimaryPart.Anchored,'no back, or not anchored')
		local wheels,backs,slides=0,0,0
		for _,p in model:GetDescendants() do
			if p.Name=='WheelMotor' then wheels+=1 elseif p.Name=='BackHinge' then backs+=1 elseif p.Name=='SlideMotor' then slides+=1 end
		end
		assert(wheels==4 and backs==2 and slides==1,'lost moving joints')
	end
end
local function physics(built)
    local out={ hulls={}, seats={}, joints={}, attachments={} }
    for _,p in built.model:GetDescendants() do
        local pose={position=triple(p.Position),rotation=p.CFrame.R}
        if p:IsA('BasePart') and p.CanCollide then
            table.insert(out.hulls,{name=p.Name,size=triple(p.Size),pose=pose,group=p.CollisionGroup,massless=p.Massless})
        elseif p.ClassName=='Motor6D' then
            table.insert(out.joints,{name=p.Name,part=p.Part1.Name,c0={triple(p.C0.Position),p.C0.R},c1={triple(p.C1.Position),p.C1.R},attributes=p:GetAttributes()})
        elseif p.ClassName=='Attachment' then
            table.insert(out.attachments,{name=p.Name,position=triple(p.Position)})
        end
    end
    return out
end
local def=nil
for _,car in Config.Cars do if car.id==Config.Sandbox.Van then def=car end end
assert(def,'no Config.Sandbox.Van in Config.Cars')
local color=Mock.Color3.fromRGB(unpack(def.color))
local working=Vehicles.__testBuild(def,color,Mock.CFrame.identity,false)
audit(working,false)
local invariant=physics(working)
local model=Vehicles.__testBuild(def,color,Mock.CFrame.identity,true).model
audit({model=model},true)
local parts={};local nodeIds={};local all={model};for _,v in model:GetDescendants() do table.insert(all,v) end
for _,v in all do nodeIds[v]=v.uid end
for _,p in all do
	local item={id=p.uid,parent=if p.Parent then nodeIds[p.Parent] else nil,name=p.Name,class=p.ClassName,attributes=p:GetAttributes()}
	if p:IsA('BasePart') then
		assert(p.Anchored,'unanchored display part')
		item.size=triple(p.Size);item.position=triple(p.Position);item.rotation=p.CFrame.R
		item.color={p.Color.R,p.Color.G,p.Color.B};item.material=p.Material;item.opacity=1-p.Transparency;item.shape=p.Shape
		item.reflectance=p.Reflectance;item.castShadow=p.CastShadow
		item.canCollide=p.CanCollide;item.canQuery=p.CanQuery;item.canTouch=p.CanTouch;item.massless=p.Massless
	elseif p.ClassName=='WeldConstraint' then item.part0=nodeIds[p.Part0];item.part1=nodeIds[p.Part1]
	elseif p.ClassName=='TextLabel' then item.text=p.Text
	end
	table.insert(parts,item)
end
print(encode({id=def.id,style=def.style,stage=0,name=def.name,upgraded=false,capacity=def.capacity,parts=parts,physics=invariant,sandboxOnly=def.sandboxOnly==true}))
