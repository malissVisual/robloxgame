--!nocheck
-- 8.5.1: the few Roblox pieces two real client modules run on in the Luau CLI (tests/run_tests.py builds
-- ArmPoseClient.luau from client/ArmPose.luau for tests/armpose_npc_test.luau and WalkDoorsClient.luau from
-- client/WalkDoors.luau for tests/walkdoors_test.luau, with these in place of their globals and their client modules;
-- their shared modules are the real ones). Not a Roblox simulator:
--   * Vector3, CFrame, Color3: tools/vehicle-preview/roblox-mock.luau's (rbxmock), with CFrame Lerp (each entry of the
--     frame straight between the two: the tests compare the modules' own blends), == (within a hair) and GetComponents;
--   * instances (E.new(class, name, parent), Instance.new): a name, a class (IsA by its family), a parent and children
--     (setting Parent moves it), attributes
--     with AttributeChanged and GetAttributeChangedSignal, GetPropertyChangedSignal, ChildAdded / ChildRemoved,
--     Destroy, a model's pivot (its PrimaryPart's frame) and PivotTo (its parts moved with it); E.body(name, at) makes an
--     R15 body (its parts, each joint a Motor6D of Roblox's name in its part, a Humanoid, a HumanoidRootPart);
--   * workspace (its CurrentCamera, GetServerTimeNow: E.now), Players (a LocalPlayer with no character), os.clock
--     (E.clock), CollectionService (tags, their added and removed signals), RunService (Heartbeat: E.heartbeat, fired by
--     the test);
--   * the client modules they require: Bodies (a body's Humanoid and root; no players), CameraRig and Holster (no aim,
--     no swing; CameraRig.face takes the arrival's look), GaitPose (standing), DeviceBudget (the full range),
--     PoseLedger (what ArmPose writes on a joint: E.writes, E.released; its stage's step: E.step), Sounds (what plays:
--     E.sounds), Fade (its onArrive hook).
local Mock = require("./rbxmock")

local E: any = { clock = 10, now = 1000, writes = {}, released = 0, step = nil, sounds = {} }

local F = getmetatable(Mock.CFrame.new())
function F.Lerp(a: any, b: any, t: number): any
	local r = {}
	for i = 1, 9 do
		r[i] = a.R[i] + (b.R[i] - a.R[i]) * t
	end
	return Mock.CFrame.new(a.Position + (b.Position - a.Position) * t, nil, nil, table.unpack(r))
end
function F.GetComponents(a: any): ...number
	local r = a.R
	return a.Position.X, a.Position.Y, a.Position.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
F.__eq = function(a: any, b: any): boolean
	if (a.Position - b.Position).Magnitude > 1e-9 then
		return false
	end
	for i = 1, 9 do
		if math.abs(a.R[i] - b.R[i]) > 1e-9 then
			return false
		end
	end
	return true
end
E.CFrame = Mock.CFrame
E.Vector3 = Mock.Vector3
E.Color3 = Mock.Color3
E.Enum = Mock.Enum

local function signal(): any
	local s: any = { handlers = {} }
	function s.Connect(self: any, fn: any)
		local handler = { fn = fn, on = true }
		table.insert(self.handlers, handler)
		return { Connected = true, Disconnect = function()
			handler.on = false
		end }
	end
	function s.Fire(self: any, ...: any)
		for _, handler in table.clone(self.handlers) do
			if handler.on then
				handler.fn(...)
			end
		end
	end
	function s.Connected(self: any): boolean
		for _, handler in self.handlers do
			if handler.on then
				return true
			end
		end
		return false
	end
	return s
end
E.signal = signal

local FAMILY: { [string]: { [string]: boolean } } = {
	Part = { BasePart = true, PVInstance = true },
	MeshPart = { BasePart = true, PVInstance = true },
	Model = { PVInstance = true },
	Motor6D = { JointInstance = true },
}
local I: any = {}
I.__index = function(self: any, key: string): any
	if key == "Parent" then
		return rawget(self, "_parent")
	end
	return I[key]
end
I.__newindex = function(self: any, key: string, value: any)
	if key == "Parent" then
		I.SetParent(self, value)
	else
		rawset(self, key, value)
	end
end
function I.IsA(self: any, class: string): boolean
	return self.ClassName == class or class == "Instance" or (FAMILY[self.ClassName] or {})[class] == true
end
function I.GetChildren(self: any): { any }
	return table.clone(self.children)
end
function I.GetDescendants(self: any): { any }
	local out = {}
	for _, child in self.children do
		table.insert(out, child)
		for _, d in child:GetDescendants() do
			table.insert(out, d)
		end
	end
	return out
end
function I.FindFirstChild(self: any, name: string): any
	for _, child in self.children do
		if child.Name == name then
			return child
		end
	end
	return nil
end
function I.FindFirstChildOfClass(self: any, class: string): any
	for _, child in self.children do
		if child.ClassName == class then
			return child
		end
	end
	return nil
end
function I.GetAttribute(self: any, name: string): any
	return self.attributes[name]
end
function I.GetAttributes(self: any): { [string]: any }
	return table.clone(self.attributes)
end
function I.SetAttribute(self: any, name: string, value: any)
	if self.attributes[name] ~= value then
		self.attributes[name] = value
		self.AttributeChanged:Fire(name)
		local named = self.changed[name]
		if named then
			named:Fire()
		end
	end
end
function I.GetAttributeChangedSignal(self: any, name: string): any
	local named = self.changed[name] or signal()
	self.changed[name] = named
	return named
end
function I.GetPropertyChangedSignal(self: any, name: string): any
	return I.GetAttributeChangedSignal(self, "property:" .. name)
end
function I.SetParent(self: any, parent: any)
	local old = rawget(self, "_parent")
	if old then
		local index = table.find(old.children, self)
		if index then
			table.remove(old.children, index)
		end
		old.ChildRemoved:Fire(self)
	end
	rawset(self, "_parent", parent)
	if parent then
		table.insert(parent.children, self)
		parent.ChildAdded:Fire(self)
	end
end
function I.Destroy(self: any)
	for _, child in self:GetChildren() do
		child:Destroy()
	end
	self:SetParent(nil)
	self.destroyed = true
end
function I.GetPivot(self: any): any
	if self.ClassName == "Model" then
		return self.PrimaryPart.CFrame
	end
	return self.CFrame
end
function I.PivotTo(self: any, target: any)
	local delta = target * self:GetPivot():Inverse()
	for _, d in self:GetDescendants() do
		if d.CFrame then
			d.CFrame = delta * d.CFrame
		end
	end
end
function E.new(class: string, name: string?, parent: any?): any
	local obj = setmetatable({ ClassName = class, Name = name or class, children = {}, attributes = {}, changed = {}, AttributeChanged = signal(),
		ChildAdded = signal(), ChildRemoved = signal(), Transparency = 0, LocalTransparencyModifier = 0 }, I)
	if parent then
		obj:SetParent(parent)
	end
	return obj
end
E.Instance = { new = function(class: string): any
	return E.new(class)
end }

E.workspace = E.new("Workspace", "Workspace")
E.workspace.CurrentCamera = { CFrame = Mock.CFrame.new(0, 6, 14), Focus = Mock.CFrame.new(0, 3, 0), CameraType = "Custom" }
function E.workspace.GetServerTimeNow(_: any): number
	return E.now
end
E.Players = { LocalPlayer = { Name = "Me", UserId = 1, Character = nil } }
E.heartbeat = signal()
E.RunService = { Heartbeat = E.heartbeat }
-- CollectionService: the tags on instances, their added and removed signals.
local tagged: { [string]: { any } } = {}
local added: { [string]: any } = {}
local removed: { [string]: any } = {}
E.CollectionService = {
	GetTagged = function(_: any, tag: string): { any }
		return table.clone(tagged[tag] or {})
	end,
	GetTags = function(_: any, inst: any): { string }
		local out = {}
		for tag, list in tagged do
			if table.find(list, inst) then
				table.insert(out, tag)
			end
		end
		return out
	end,
	AddTag = function(_: any, inst: any, tag: string)
		local list = tagged[tag] or {}
		tagged[tag] = list
		if not table.find(list, inst) then
			table.insert(list, inst)
			if added[tag] then
				added[tag]:Fire(inst)
			end
		end
	end,
	RemoveTag = function(_: any, inst: any, tag: string)
		local list = tagged[tag] or {}
		local index = table.find(list, inst)
		if index then
			table.remove(list, index)
			if removed[tag] then
				removed[tag]:Fire(inst)
			end
		end
	end,
	GetInstanceAddedSignal = function(_: any, tag: string): any
		added[tag] = added[tag] or signal()
		return added[tag]
	end,
	GetInstanceRemovedSignal = function(_: any, tag: string): any
		removed[tag] = removed[tag] or signal()
		return removed[tag]
	end,
}
E.game = { GetService = function(_: any, name: string): any
	if name == "Players" then
		return E.Players
	elseif name == "CollectionService" then
		return E.CollectionService
	elseif name == "RunService" then
		return E.RunService
	elseif name == "ReplicatedStorage" then
		return { WaitForChild = function(): any
			return {} -- (its requires are the staged copies')
		end }
	end
	return {}
end }
E.os = { clock = function(): number
	return E.clock
end, time = os.time }

-- An R15 body (a Model): its parts, each joint (a Motor6D, Roblox's name) in the part it moves, a Humanoid.
local R15 = {
	{ "UpperTorso", "Waist" }, { "LowerTorso", "Root" }, { "Head", "Neck" },
	{ "RightUpperArm", "RightShoulder" }, { "RightLowerArm", "RightElbow" }, { "RightHand", "RightWrist" },
	{ "LeftUpperArm", "LeftShoulder" }, { "LeftLowerArm", "LeftElbow" }, { "LeftHand", "LeftWrist" },
	{ "RightUpperLeg", "RightHip" }, { "RightLowerLeg", "RightKnee" }, { "RightFoot", "RightAnkle" },
	{ "LeftUpperLeg", "LeftHip" }, { "LeftLowerLeg", "LeftKnee" }, { "LeftFoot", "LeftAnkle" },
}
function E.body(name: string, at: any): any
	local model = E.new("Model", name)
	local root = E.new("Part", "HumanoidRootPart", model)
	root.Size = Mock.Vector3.new(2, 2, 1)
	root.CFrame = Mock.CFrame.new(at.X, at.Y, at.Z)
	root.Position = at
	model.PrimaryPart = root
	for _, pair in R15 do
		local part = E.new("Part", pair[1], model)
		part.Size = Mock.Vector3.new(1, 1, 1)
		E.new("Motor6D", pair[2], part)
	end
	local humanoid = E.new("Humanoid", "Humanoid", model)
	humanoid.Health = 100
	humanoid.Sit = false
	humanoid.RootPart = root
	return model
end

-- The client modules they require.
E.Bodies = {
	of = function(model: any): (any, any)
		return model:FindFirstChildOfClass("Humanoid"), model:FindFirstChild("HumanoidRootPart")
	end,
	players = function(): { any }
		return {}
	end,
}
E.CameraRig = {
	aimPose = function(): (boolean, number)
		return false, 0
	end,
	raiseTime = function(): number
		return 0.2
	end,
	face = function(_look: any): boolean
		return true
	end,
}
E.Holster = {
	holstered = function(): boolean
		return false
	end,
	localSwing = function(): (number?, string?)
		return nil, nil
	end,
}
E.GaitPose = {
	moving = function(): boolean
		return false
	end,
	onFoot = function(): boolean
		return true
	end,
}
E.DeviceBudget = {
	range = function(r: number): number
		return r
	end,
}
E.PoseLedger = {
	now = function(_joint: any): any
		return Mock.CFrame.identity -- (the animation's own value under the layer)
	end,
	write = function(joint: any, value: any)
		E.writes[joint] = value
	end,
	release = function(joint: any)
		E.writes[joint] = nil
		E.released += 1
	end,
	stage = function(_order: number, _name: string, fn: any)
		E.step = fn
	end,
}
E.Sounds = {
	playAt = function(name: string, ...: any)
		table.insert(E.sounds, name)
	end,
}
E.Fade = {}

return E
