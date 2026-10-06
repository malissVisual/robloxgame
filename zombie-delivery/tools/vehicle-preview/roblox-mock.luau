--!strict
-- Property recorder and rigid-frame maths for executing the real vehicle factory outside Studio. No simulation.
local Mock = {}
local V = {}; V.__index = function(v,k)
	if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
	if k == "Unit" then return v / math.max(v.Magnitude, 1e-12) end
	return V[k]
end
local function vec(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},V) end
V.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
V.__sub=function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
V.__unm=function(a) return vec(-a.X,-a.Y,-a.Z) end
V.__mul=function(a,b) if type(a)=='number' then a,b=b,a end; return vec(a.X*b,a.Y*b,a.Z*b) end
V.__div=function(a,b) return vec(a.X/b,a.Y/b,a.Z/b) end
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function V:Cross(b) return vec(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
Mock.Vector3={new=vec,zero=vec(0,0,0),xAxis=vec(1,0,0),yAxis=vec(0,1,0),zAxis=vec(0,0,1)}
Mock.Vector2={new=function(x,y) return {X=x,Y=y} end,zero={X=0,Y=0}}
local F={}; F.__index=F
local function frame(p,r) return setmetatable({Position=p,R=r},F) end
local function rotate(r,v) return vec(r[1]*v.X+r[2]*v.Y+r[3]*v.Z,r[4]*v.X+r[5]*v.Y+r[6]*v.Z,r[7]*v.X+r[8]*v.Y+r[9]*v.Z) end
function F.__mul(a,b)
	if getmetatable(b)==V then return a.Position+rotate(a.R,b) end
	local out={}
	for i=0,2 do for j=0,2 do local sum=0; for k=0,2 do sum+=a.R[i*3+k+1]*b.R[k*3+j+1] end; out[i*3+j+1]=sum end end
	return frame(a.Position+rotate(a.R,b.Position),out)
end
function F:Inverse()
	local r=self.R; local inv={r[1],r[4],r[7],r[2],r[5],r[8],r[3],r[6],r[9]}
	return frame(rotate(inv,-self.Position),inv)
end
function F:PointToObjectSpace(v) return self:Inverse()*v end
function F:ToObjectSpace(other) return self:Inverse()*other end
Mock.CFrame={new=function(x,y,z,...)
	local r={...}
	return frame(if type(x)=='table' then x else vec(x,y,z),if #r==9 then r else {1,0,0,0,1,0,0,0,1})
end,Angles=function(x,y,z)
	local sx,cx,sy,cy,sz,cz=math.sin(x),math.cos(x),math.sin(y),math.cos(y),math.sin(z),math.cos(z)
	return frame(vec(),{cy*cz,-cy*sz,sy,cx*sz+sx*sy*cz,cx*cz-sx*sy*sz,-sx*cy,sx*sz-cx*sy*cz,sx*cz+cx*sy*sz,cx*cy})
end}
Mock.CFrame.lookAt=function(eye,target)
    local look=(target-eye).Unit;local right=look:Cross(vec(0,1,0)).Unit;local up=right:Cross(look)
    return frame(eye,{right.X,up.X,-look.X,right.Y,up.Y,-look.Y,right.Z,up.Z,-look.Z})
end
Mock.CFrame.identity=Mock.CFrame.new()
local C={}; C.__index=C
function C:Lerp(b,t) return setmetatable({R=self.R+(b.R-self.R)*t,G=self.G+(b.G-self.G)*t,B=self.B+(b.B-self.B)*t},C) end
Mock.Color3={new=function(r,g,b) return setmetatable({R=r,G=g,B=b},C) end}
Mock.Color3.fromRGB=function(r,g,b) return Mock.Color3.new(r/255,g/255,b/255) end
Mock.Enum=setmetatable({},{__index=function(t,key)
	local bucket=setmetatable({},{__index=function(_,name) return name end}); rawset(t,key,bucket);return bucket
end})
Mock.PhysicalProperties={new=function(...) return {...} end}
Mock.UDim2={fromScale=function(x,y) return {x,y} end}
local O={}; local serial=0
local function remove(parent,item)
	if not parent then return end
	for i,v in parent.children do if v==item then table.remove(parent.children,i); break end end
end
O.__index=function(self,k)
	if O[k] then return O[k] end
	if k=='Position' and self.props.CFrame then return self.props.CFrame.Position end
	return self.props[k]
end
O.__newindex=function(self,k,v)
	if k=='Parent' then remove(self.props.Parent,self); if v then table.insert(v.children,self) end end
	self.props[k]=v
end
function O:IsA(class)
	return self.ClassName==class or (class=='JointInstance' and ({Motor6D=true,Weld=true})[self.ClassName]==true) or (class=='Constraint' and ({LinearVelocity=true,AngularVelocity=true})[self.ClassName]==true) or (class=='BasePart' and ({Part=true,WedgePart=true,VehicleSeat=true,Seat=true})[self.ClassName]==true) or (class=='Light' and ({SpotLight=true,PointLight=true})[self.ClassName]==true)
end
function O:GetChildren() return table.clone(self.children) end
function O:GetDescendants()
	local out={}; for _,c in self.children do table.insert(out,c); for _,d in c:GetDescendants() do table.insert(out,d) end end; return out
end
function O:FindFirstChild(name) for _,c in self.children do if c.Name==name then return c end end; return nil end
function O:FindFirstChildOfClass(class) for _,c in self.children do if c.ClassName==class then return c end end; return nil end
function O:SetAttribute(k,v) self.attributes[k]=v end
function O:GetAttribute(k) return self.attributes[k] end
function O:GetAttributes() return table.clone(self.attributes) end
function O:GetBoundingBox()
    local lo,hi=vec(math.huge,math.huge,math.huge),vec(-math.huge,-math.huge,-math.huge)
    for _,p in self:GetDescendants() do
        if p:IsA('BasePart') then
            local r,s=p.CFrame.R,p.Size*.5
            local a=vec(math.abs(r[1])*s.X+math.abs(r[2])*s.Y+math.abs(r[3])*s.Z,math.abs(r[4])*s.X+math.abs(r[5])*s.Y+math.abs(r[6])*s.Z,math.abs(r[7])*s.X+math.abs(r[8])*s.Y+math.abs(r[9])*s.Z)
            local l,h=p.Position-a,p.Position+a
            lo=vec(math.min(lo.X,l.X),math.min(lo.Y,l.Y),math.min(lo.Z,l.Z));hi=vec(math.max(hi.X,h.X),math.max(hi.Y,h.Y),math.max(hi.Z,h.Z))
        end
    end
    return Mock.CFrame.new((lo+hi)*.5),hi-lo
end
function O:PivotTo(target)
    local pivot=if self.PrimaryPart then self.PrimaryPart.CFrame else self:GetBoundingBox()
    local delta=target*pivot:Inverse()
    for _,p in self:GetDescendants() do if p:IsA('BasePart') then p.CFrame=delta*p.CFrame end end
end
function O:Clone()
    local originals={self};for _,p in self:GetDescendants() do table.insert(originals,p) end
    local copies={}
    for _,p in originals do copies[p]=Mock.Instance.new(p.ClassName) end
    for _,p in originals do
        local c=copies[p];for k,v in p.props do if k~='Parent' then c[k]=copies[v] or v end end
        c.attributes=table.clone(p.attributes)
        if p~=self then c.Parent=copies[p.Parent] end
    end
    return copies[self]
end
function O:Destroy() for _,c in self:GetChildren() do c:Destroy() end; self.Parent=nil end
Mock.Instance={new=function(class)
	serial+=1
	return setmetatable({uid=serial,children={},attributes={},props={ClassName=class,Name=class,Size=vec(1,1,1),CFrame=Mock.CFrame.identity,C0=Mock.CFrame.identity,C1=Mock.CFrame.identity,Color=Mock.Color3.new(1,1,1),Material='Plastic',Transparency=0,Reflectance=0,Anchored=false,CanCollide=true,CanQuery=true,CanTouch=true,Massless=false,CastShadow=true,Archivable=true}},O)
end}
Mock.game={GetService=function(_,name)
	if name=='Players' then return {LocalPlayer={UserId=1}} end
	if name=='ReplicatedStorage' then return {WaitForChild=function() return {} end} end
	if name=='CollectionService' then return {AddTag=function(_,obj,tag) obj:SetAttribute('Tag_'..tag,true) end,RemoveTag=function() end} end
	return {}
end}
Mock.workspace=Mock.Instance.new("Folder")
Mock.typeof=function(x) if getmetatable(x)==V then return 'Vector3' elseif getmetatable(x)==F then return 'CFrame' elseif getmetatable(x)==C then return 'Color3' end; return type(x) end
Mock.nightLight=function(obj,lit,dim,material) obj:SetAttribute('NightLight',true) end
return Mock
