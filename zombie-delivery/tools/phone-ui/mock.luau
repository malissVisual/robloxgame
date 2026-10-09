-- Narrow instance/service recorder for phone behavior checks. Not a Roblox layout/physics emulator.
local M = { warnings = {}, sent = {}, deferred = {}, touch = false, width = 1280, height = 800, now = 100 }
local function signal()
	local s = { connections = {} }
	function s:Connect(fn)
		local connection = { fn = fn, Connected = true }
		function connection:Disconnect() self.Connected = false end
		table.insert(self.connections,connection)
		return connection
	end
	function s:Fire(...)
		for _, c in table.clone(self.connections) do if c.Connected then c.fn(...) end end
	end
	return s
end
M.signal = signal
local vector = {}
function vector.__sub(a,b) return M.Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
function vector.__index(a,key) if key == "Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end end
M.Vector3 = { new = function(x,y,z) return setmetatable({X=x,Y=y,Z=z,kind="Vector3"},vector) end }
M.Vector2 = { new = function(x,y) return {X=x,Y=y,kind="Vector2"} end }
M.Vector2.zero = M.Vector2.new(0,0)
M.UDim = { new = function(scale,offset) return {Scale=scale,Offset=offset} end }
M.UDim2 = { new = function(x,a,y,b) return {X=M.UDim.new(x or 0,a or 0),Y=M.UDim.new(y or 0,b or 0)} end }
function M.UDim2.fromScale(x,y) return M.UDim2.new(x,0,y,0) end
function M.UDim2.fromOffset(x,y) return M.UDim2.new(0,x,0,y) end
M.Color3 = {new = function(r,g,b) return {R=r,G=g,B=b} end}
function M.Color3.fromRGB(r,g,b) return M.Color3.new(r/255,g/255,b/255) end
M.Enum = setmetatable({}, {__index=function(t,key)
	local values = setmetatable({}, {__index=function(v,k) local made={Name=k};rawset(v,k,made);return made end})
	rawset(t,key,values); return values
end})
local methods = {}
M.methods = methods -- (6.8: tools/phone-ui/missions_mock.luau adds the few the MISSIONS window needs)
local events = {Activated=true,MouseEnter=true,MouseLeave=true,SelectionGained=true,SelectionLost=true,InputBegan=true,InputEnded=true,Destroying=true,Completed=true}
local object = {
	__index = function(self,key)
		if methods[key] then return methods[key] end
		if key == "AbsolutePosition" then return M.Vector2.zero end
		if key == "AbsoluteSize" then
			if self._p.ClassName == "PlayerGui" or self._p.ClassName == "ScreenGui" then return M.Vector2.new(M.width,M.height) end
			local base = if self._p.Parent then self._p.Parent.AbsoluteSize else M.Vector2.new(M.width,M.height)
			local size = self._p.Size or M.UDim2.new()
			return M.Vector2.new(base.X*size.X.Scale+size.X.Offset,base.Y*size.Y.Scale+size.Y.Offset)
		end
		if events[key] then self._p[key] = self._p[key] or signal() end
		return self._p[key]
	end,
	__newindex = function(self,key,value)
		if key == "Parent" then
			local old = self._p.Parent
			if old then local index=table.find(old._children,self);if index then table.remove(old._children,index) end end
			if value then table.insert(value._children,self) end
		end
		self._p[key] = value
	end,
}
function M.make(class,props,parent)
	local made=setmetatable({_p={ClassName=class,Name=class,Visible=true,Enabled=true,Size=M.UDim2.new(),Position=M.UDim2.new(),Text=""},_children={},_attrs={},_signals={}},object)
	for key,value in props or {} do made[key]=value end
	made.Parent=parent
	return made
end
function methods:GetChildren() return table.clone(self._children) end
function methods:IsA(class) return class==self.ClassName or class=="GuiObject" and not string.match(self.ClassName,"^UI") and self.ClassName~="ScreenGui" end
function methods:FindFirstChild(name)
	for _, child in self._children do if child.Name==name then return child end end
	return nil
end
function methods:FindFirstChildOfClass(class)
	for _, child in self._children do if child.ClassName==class then return child end end
	return nil
end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:SetAttribute(key,value) self._attrs[key]=value end
function methods:GetAttribute(key) return self._attrs[key] end
function methods:GetPropertyChangedSignal(key) self._signals[key]=self._signals[key] or signal(); return self._signals[key] end
methods.GetAttributeChangedSignal=methods.GetPropertyChangedSignal
function methods:Destroy()
	self.Destroying:Fire()
	for _, child in self:GetChildren() do child:Destroy() end
	self.Parent=nil
end
M.gui = M.make("PlayerGui")
M.make("ScreenGui",{Name="ZombieDeliveryHud"},M.gui)
M.player=M.make("Player",{UserId=14,DisplayName="Courier",Character=M.make("Model")})
M.gui.Parent=M.player
M.root=M.make("BasePart",{Name="HumanoidRootPart",Position=M.Vector3.new(0,0,0)},M.player.Character)
M.player:SetAttribute("Xp",0)
M.workspace=M.make("Workspace",{CurrentCamera=M.make("Camera",{ViewportSize=M.Vector2.new(1280,800)})})
function M.workspace:GetServerTimeNow() return M.now end
local storage = { Shared=setmetatable({}, {__index=function(_,key) return "./"..key end}) }
function storage:WaitForChild() return self.Shared end
local input={InputBegan=signal()}
function input:GetFocusedTextBox() return nil end
-- 6.0.1: Lighting is an instance (the popup's BlurEffect goes in it); GuiService has the Roblox menu's signal.
M.lighting=M.make("Lighting",{ClockTime=21.133})
M.services={Players={LocalPlayer=M.player},ReplicatedStorage=storage,GuiService={ReducedMotionEnabled=true,MenuOpened=signal()},Lighting=M.lighting,UserInputService=input,TextService={}}
function M.services.TextService:GetTextSize(value,size) return M.Vector2.new(#value*size*.55,size) end
M.services.TweenService={Create=function(_,target,_,props)
	local tween={Completed=signal()}
	function tween:Play() for key,value in props do target[key]=value end;self.Completed:Fire() end
	function tween:Cancel() end
	return tween
end}
M.game={GetService=function(_,name) assert(M.services[name],name);return M.services[name] end}
M.task={}
function M.task.spawn(fn)
	local thread=coroutine.create(fn)
	local ok,err=coroutine.resume(thread)
	assert(ok,err)
	return thread
end
function M.task.wait() coroutine.yield() end
function M.task.defer(fn) table.insert(M.deferred,fn) end
function M.task.delay(_,fn) table.insert(M.deferred,fn) end
function M.flush()
	local pending=M.deferred;M.deferred={}
	for _,fn in pending do fn() end
end
M.typeof=function(value) return if type(value)=="table" and value.kind then value.kind else typeof(value) end
M.warn=function(value) table.insert(M.warnings,value) end
M.TweenInfo={new=function() return {} end}
M.remotes={}
M.Net={get=function(name)
	if not M.remotes[name] then
		local remote={OnClientEvent=signal()}
		function remote:FireServer(...) table.insert(M.sent,{name=name,args={...}}) end
		M.remotes[name]=remote
	end
	return M.remotes[name]
end}
M.Theme={Font=M.Enum.Font.Gotham,HeadingFont=M.Enum.Font.GothamBold,DisplayFont=M.Enum.Font.GothamBold,Contract={},WindowTransparency=0.02}
for key,value in {text={242,242,240},secondary={196,199,203},charcoal={20,23,28},line={133,139,147},red={215,74,70},row={26,30,36},raised={32,36,42},good={180,200,180},warn={200,180,100},rule={82,87,93}} do
	M.Theme.Contract[key]=M.Color3.fromRGB(unpack(value))
end
M.Ui={make=M.make}
function M.Ui.label(parent,value,size,props)
	local made=M.make("TextLabel",{Text=value,Size=size,BackgroundTransparency=1},parent)
	for key,v in props or {} do made[key]=v end
	return made
end
function M.Ui.clear(parent) for _,child in parent:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end end
function M.Ui.list(parent,vertical,gap) return M.make("UIListLayout",{Padding=M.UDim.new(0,gap)},parent) end
function M.Ui.corner(parent,size) return M.make("UICorner",{CornerRadius=M.UDim.new(0,size)},parent) end
function M.Ui.screenSize() return M.Vector2.new(M.width,M.height) end
function M.Ui.screenScale() return 1 end
function M.Ui.touchLayout() return M.touch end
function M.Ui.gamepadFocus(target) M.focus=target end
function M.Ui.gamepadRelease() M.focus=nil end
-- 6.0.1, the popup's header (Ui.window's language): the glyph through the real PhoneContract, the title in caps, the ✕.
function M.Ui.glyph(slot,id,size)
	for _,child in slot:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
	slot:SetAttribute("Glyph",id)
	if id~="" then require("./PhoneContract").glyph(slot,id,size or 24) end
end
function M.Ui.heading(parent,title,options)
	local frame=M.make("Frame",{Name="Heading"},parent)
	M.make("Frame",{Name="Brand"},frame)
	local slot=M.make("Frame",{Name="Glyph",Size=M.UDim2.fromOffset(24,24)},frame)
	M.Ui.glyph(slot,options and options.glyph or "",24)
	local label=M.Ui.label(frame,string.upper(title),M.UDim2.new(1,0,1,0),{Name="Title"})
	return {frame=frame,glyph=slot,title=label}
end
function M.Ui.closeButton(parent,fn)
	local made=M.make("TextButton",{Name="Close",Text="✕",Size=M.UDim2.fromOffset(40,40)},parent)
	made.Activated:Connect(fn);return made
end
function M.Ui.money(value) return "$"..tostring(value) end
function M.Ui.clock(value) return string.format("%02d:%02d",math.floor(value/60),math.floor(value%60)) end
M.P={text=M.Ui.label,caps=M.Ui.label,hover=function() end,hex=function() return "ffffff" end}
function M.P.rule(parent,size,props) local made=M.make("Frame",{Size=size},parent);for k,v in props or {} do made[k]=v end;return made end
function M.P.marker(parent,size,props) local made=M.make("Frame",{Size=M.UDim2.fromOffset(size,size)},parent);for k,v in props or {} do made[k]=v end;return made end
function M.P.bar(parent,size,color) return M.make("Frame",{Size=size,BackgroundColor3=color},parent),M.make("Frame",{Size=size,BackgroundColor3=color},parent) end
function M.P.button(parent,value,size,kind,fn)
	local made=M.make("TextButton",{Text=value,Size=size},parent)
	made.Activated:Connect(fn);return made
end
function M.P.dot(parent,props) return M.Ui.label(parent,"",M.UDim2.fromOffset(14,14),props) end
function M.P.tag(parent,value) return M.Ui.label(parent,value,M.UDim2.fromOffset(100,20)) end
M.MapView={isOpen=function() return M.mapOpen==true end,toggle=function() M.mapOpen=not M.mapOpen end,setWaypoint=function(at) M.waypoint=at end}
-- 6.12, the clerks: where the local character stands (STYLE's BUY only at a shop that sells the look; the GPS above)
function M.stand(x,z) M.root.Position=M.Vector3.new(x,0,z) end
M.KitShop={owned=function(state) return state.kit or {} end,roomText=function() return "HANDS 2 / PACK 3" end}
M.CareerUi={toGo=function() return "8 runs" end,unlockText=function() return "Next unlock" end}
M.BagUi={line=function() return nil end,open=function() M.bagOpen=true end,render=function(parent,job,order) M.bagRendered=(M.bagRendered or 0)+1;M.make("Frame",{Name="BagRows",LayoutOrder=order},parent);return order+1 end}
-- 6.5: BAG & ITEMS' BAGS tab and ITEMS' USE (the bottom bar's path).
M.BagUi.bags=function(parent,state,order) M.bagsRendered=(M.bagsRendered or 0)+1;M.make("Frame",{Name="BagsRows",LayoutOrder=order},parent);return order+1 end
M.Hotbar={slotOf=function(id) return if id=="medkit" then 5 else nil end}
M.Hotbar.onUse=function(id) M.used=id end
M.Sounds={cycle=function() M.soundCycles=(M.soundCycles or 0)+1 end}
-- 6.12: STYLE's sound on a purchase, its 3D preview (client/StylePreview.luau: recorded, not drawn) and its keys
M.played={}
M.Sounds.play=function(name) table.insert(M.played,name) end
M.previews={}
M.StylePreview={show=function(holder,tab,def) table.insert(M.previews,{holder=holder,tab=tab,id=def and def.id}); return "courier",nil end,clear=function() M.previewCleared=(M.previewCleared or 0)+1 end}
M.actions={}
M.services.ContextActionService={
	BindActionAtPriority=function(_,name,fn,_,priority,...) M.actions[name]={fn=fn,keys={...},priority=priority} end,
	UnbindAction=function(_,name) M.actions[name]=nil end,
}
M.Enum.ContextActionPriority.High.Value=3000
M.Discovery={grid={X0=-2200,Z0=-3000,Size=120,Rows=40,Cols=36},changed=signal(),uncoveredCell=function() return M.discovered==true end}
-- 6.12.8, the NEXT UP queue: what the client last sent on a remote, and the server's data for a run on the board
-- (a Job payload with two open orders and one done, the board's rows with their + QUEUE / lock / queue-full fields and
-- ADD ALL's plan, the JobQueue remote's state with the head waiting for its car).
function M.lastSent(name) for index=#M.sent,1,-1 do if M.sent[index].name==name then return M.sent[index] end end return nil end
M.queueFixture={
	run=function(now) return {cargo="Pizza",customer="Bob",total=2,pay=120,endsAt=now+200,mode="foot",stopLabel="PICK UP at Luigi's Pizza",stack={can=true,open=2,max=2},
		orders={{id=1,state="open",focused=true,title="Pizza → Bob",pay=120,endsAt=now+200,mode="foot",from="Luigi's Pizza",to="3 Oak Ave"},
			{id=2,state="open",title="Letters → Ann",pay=40,endsAt=now+90,mode="foot",from="Post Office",to="12 Elm St"},
			{id=3,state="done",title="Cake → Flo",pay=60}}} end,
	board=function() return {
		{index=21,mode="foot",cargo="Flowers",customer="Cy",first="Bloom",address="7 Ash St",distance=200,time=150,pay=55,stars=1,orderButton="ORDERS FULL (2/2)",queue=true},
		{index=22,mode="bike",cargo="Parcels",customer="Di",first="Post Office",address="Harbor",distance=700,time=240,pay=130,stars=1,tooBig=true,lockButton="🚲 RIDE YOUR BIKE",lockText="Bike jobs are ridden.",queue=true},
		{index=23,mode="car",cargo="Gold",customer="Dee",first="Bank",address="Vault",distance=1200,time=300,pay=900,stars=3,tierName="Deadly",locked=true,level=7},
		{index=24,mode="foot",cargo="Bread",customer="Ed",first="Bakery",address="2 Elm St",distance=150,time=120,pay=50,stars=1,queueButton="QUEUE FULL (6/6)",queueText="NEXT UP holds 6 jobs."},
		{index=25,mode="car",cargo="Cash",customer="Vault",first="Bank",address="Depot",distance=900,time=300,pay=700,stars=2,tierName="Risky",jobType={name="Cash Transport",description=""}},
		{index=26,mode="foot",cargo="Morning papers",customer="12 doors on Elm St",first="The Daily Undead",address="Elm St",distance=600,time=420,pay=95,stars=1,round=true},
	} end,
	-- review: the rows as server/JobQueue.luau's plan sees them (Jobs.queueApi.candidate): locked, a special or the
	-- round never queue; the bike job waits for your bike; ★ / ★★ and the light runs stack.
	candidates=function(rows)
		local out={}
		for _,row in rows do
			local special=type(row.jobType)=="table"
			table.insert(out,{id=row.index,mode=row.mode,pieces=1,pay=row.pay,stackable=not special and not row.round and (row.mode~="car" or (row.stars or 1)<=2),
				queueable=not special and not row.round and row.locked~=true,ready=row.tooBig~=true and row.locked~=true,locked=row.locked==true,fits=false})
		end
		return out
	end,
	info={onDuty=true,addAll={count=2,total=185,started=0,added=0,queued=2},queue={size=2,max=6}},
	queue={max=6,list={
		{id=5,title="Crates → Cid",cargo="Crates",customer="Cid",mode="car",stars=2,from="Depot",to="Harbor",pay=300,why="needs your car: CALL CAR"},
		{id=6,title="Soup → Flo",cargo="Soup",customer="Flo",mode="foot",stars=1,from="Wok Dead",to="9 Oak Ave",pay=70},
	}},
	-- review: the idle start waiting its StartDelay, and the queue PAUSED after a failed delivery
	starting={max=6,list={
		{id=6,title="Soup → Flo",cargo="Soup",customer="Flo",mode="foot",stars=1,from="Wok Dead",to="9 Oak Ave",pay=70,starting=true},
	}},
	paused={max=6,paused=true,pausedWhy="after a failed delivery",list={
		{id=5,title="Crates → Cid",cargo="Crates",customer="Cid",mode="car",stars=2,from="Depot",to="Harbor",pay=300,why="needs your car: CALL CAR"},
		{id=6,title="Soup → Flo",cargo="Soup",customer="Flo",mode="foot",stars=1,from="Wok Dead",to="9 Oak Ave",pay=70},
	}},
}
return M
