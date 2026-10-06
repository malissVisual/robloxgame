--!strict
-- Execute the actual Vehicles factory, audit moving-part welds and serialize its resulting display geometry.
local Mock = require('./roblox-mock')
local Vehicles = require('./Vehicles')
local Config = require('./Config')
local Economy = require('./Economy')
local function encode(v)
	local kind=type(v)
	if kind=='string' then return string.format('%q',v) end
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
			if p.Parent.Name=='CarDoor' or p.Parent.Name=='BackDoor' then assert(welds[p]==p.Parent,p.Name..' will not follow its door') end
			if p.Parent.Name=='FleetWheel' then assert(welds[p].Name=='Tyre',p.Name..' will not rotate with its tyre') end
		end
		if p:IsA('BasePart') then
			for _,s in triple(p.Size) do assert(s>0 and s<2048 and s==s) end
		end
	end
	if not display then
		assert(built.seat~=nil and model.PrimaryPart:FindFirstChild('CargoDoor') and model.PrimaryPart:FindFirstChild('Drive'))
		local wheels,doors,backs=0,0,0
		for _,p in model:GetDescendants() do
			if p.Name=='WheelMotor' then wheels+=1 elseif p.Name=='DoorHinge' then doors+=1 elseif p.Name=='BackHinge' then backs+=1 end
		end
		assert(wheels>=4 and doors>=2 and backs>=1,'lost moving joints')
	end
end
local function physics(built)
    local out={ hulls={}, seats={}, joints={}, attachments={} }
    for _,p in built.model:GetDescendants() do
        local pose={position=triple(p.Position),rotation=p.CFrame.R}
        if p:IsA('BasePart') and p.CanCollide then
            table.insert(out.hulls,{name=p.Name,size=triple(p.Size),pose=pose,group=p.CollisionGroup,massless=p.Massless})
        elseif p.ClassName=='VehicleSeat' or p.ClassName=='Seat' then
            table.insert(out.seats,{name=p.Name,size=triple(p.Size),pose=pose,door=p:GetAttribute('Door')})
        elseif p.ClassName=='Motor6D' then
            table.insert(out.joints,{name=p.Name,part=p.Part1.Name,c0={triple(p.C0.Position),p.C0.R},c1={triple(p.C1.Position),p.C1.R},attributes=p:GetAttributes()})
        elseif p.ClassName=='Attachment' then
            table.insert(out.attachments,{name=p.Name,position=triple(p.Position)})
        end
    end
    return out
end
for _,def in Config.Cars do
	-- 5.1: the bikes (CarDef.bike) are not in the fleet's garage data: bike-check.luau audits them.
	if not def.company and not def.bike then
		for stage=0,Economy.maxStage(def.id) do
			local player=Vehicles.__testBuild(def,Mock.Color3.fromRGB(unpack(def.color)),Mock.CFrame.identity,false,nil,nil,stage)
			audit(player,false)
			local invariant = physics(player)
			local function wheels()
				local out={}
				for _,p in player.model:GetChildren() do if p.Name=='Tyre' then out[p]=p:FindFirstChild('FleetWheel') or false end end
				return out
			end
			local stock=wheels()
			Vehicles.__testBuildKit(player.model,player.chassis,Vehicles.__testStyle(def,stage),{},def.id)
			for tyre,folder in wheels() do assert(folder==stock[tyre],'stock kit dressed the wheels again') end
			-- 4.6: every piece of gear that fits the car (the trolley, the straps, the cooler, the roof rack) on the kit too.
			local gear={}
			for _,piece in Config.Gear do if Economy.gearFits(def.id,piece.id) then gear[piece.id]=true end end
			Vehicles.__testBuildKit(player.model,player.chassis,Vehicles.__testStyle(def,stage),{engine=5,handling=5,armor=5,plow=5},def.id,gear)
			audit(player,false)
			local fitted=wheels()
			Vehicles.__testBuildKit(player.model,player.chassis,Vehicles.__testStyle(def,stage),{engine=5,handling=4,armor=3,plow=5},def.id,gear)
			for tyre,folder in wheels() do assert(folder==fitted[tyre] and (folder==false or folder.Parent==tyre),'a kit change without a new tyre look dressed the wheels again') end
			for _,upgraded in {false,true} do
				local levels=if upgraded then {engine=5,handling=5,armor=5,plow=5} else nil
				local model=Vehicles.displayModel(def,Mock.CFrame.identity,stage,levels,if upgraded then gear else nil)
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
				print(encode({id=def.id,style=def.style,stage=stage,name=(Economy.stageDef(def.id,stage) or def).name,upgraded=upgraded,capacity=Economy.stageCapacity(def.id,stage),parts=parts,physics=invariant}))
			end
		end
	end
end
