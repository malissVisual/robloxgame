-- 6.13.1: a permissive Roblox stand-in for tools/perf/world_count.py: enough to run server/World.luau (and the builders
-- it calls) in the Luau CLI and count what it built. Not a simulation: values, instances, attributes and tags only
-- (UnionAsync makes one part, rays and part queries find nothing, task.spawn runs a loop to its first wait). The
-- modules get it with setfenv(1, require(".../mock").env), so no module gains a local (the -O0 register limit).
local M = {}
local BASE = getfenv(1)

-- ── Vector3 ────────────────────────────────────────────────────────────────
local V3 = {}
local Vector3 = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m < 1e-12 then
			return v3(0, 0, 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	end
	return V3[k]
end
V3.__type = "Vector3"
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(v)
	return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z)
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	return a + (b - a) * t
end
function V3.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function V3.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function V3.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3.FuzzyEq(a, b, e)
	return (a - b).Magnitude <= (e or 1e-5)
end
Vector3.new = v3
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

-- ── CFrame (rotation matrix rows m[1..9]: columns right, up, back) ─────────
local CF = {}
local CFrame = {}
local ID = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function cf(x, y, z, m)
	return setmetatable({ x = x, y = y, z = z, m = m or ID }, CF)
end
local function mulm(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local s = 0
			for k = 0, 2 do
				s += a[i * 3 + k + 1] * b[k * 3 + j + 1]
			end
			r[i * 3 + j + 1] = s
		end
	end
	return r
end
local function rot(m, v)
	return v3(m[1] * v.X + m[2] * v.Y + m[3] * v.Z, m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z)
end
local function transpose(m)
	return { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
end
CF.__type = "CFrame"
CF.__index = function(c, k)
	local m = c.m
	if k == "Position" or k == "p" then
		return v3(c.x, c.y, c.z)
	elseif k == "LookVector" then
		return v3(-m[3], -m[6], -m[9])
	elseif k == "RightVector" then
		return v3(m[1], m[4], m[7])
	elseif k == "UpVector" then
		return v3(m[2], m[5], m[8])
	elseif k == "XVector" then
		return v3(m[1], m[4], m[7])
	elseif k == "YVector" then
		return v3(m[2], m[5], m[8])
	elseif k == "ZVector" then
		return v3(m[3], m[6], m[9])
	elseif k == "X" then
		return c.x
	elseif k == "Y" then
		return c.y
	elseif k == "Z" then
		return c.z
	elseif k == "Rotation" then
		return cf(0, 0, 0, m)
	end
	return CF[k]
end
CF.__mul = function(a, b)
	if getmetatable(b) == V3 then
		local r = rot(a.m, b)
		return v3(a.x + r.X, a.y + r.Y, a.z + r.Z)
	end
	local p = rot(a.m, v3(b.x, b.y, b.z))
	return cf(a.x + p.X, a.y + p.Y, a.z + p.Z, mulm(a.m, b.m))
end
CF.__add = function(a, v)
	return cf(a.x + v.X, a.y + v.Y, a.z + v.Z, a.m)
end
CF.__sub = function(a, v)
	return cf(a.x - v.X, a.y - v.Y, a.z - v.Z, a.m)
end
CF.__eq = function(a, b)
	if a.x ~= b.x or a.y ~= b.y or a.z ~= b.z then
		return false
	end
	for i = 1, 9 do
		if a.m[i] ~= b.m[i] then
			return false
		end
	end
	return true
end
function CF.Inverse(a)
	local t = transpose(a.m)
	local p = rot(t, v3(-a.x, -a.y, -a.z))
	return cf(p.X, p.Y, p.Z, t)
end
function CF.ToObjectSpace(a, b)
	return a:Inverse() * b
end
function CF.ToWorldSpace(a, b)
	return a * b
end
function CF.PointToObjectSpace(a, v)
	return a:Inverse() * v
end
function CF.PointToWorldSpace(a, v)
	return a * v
end
function CF.VectorToWorldSpace(a, v)
	return rot(a.m, v)
end
function CF.VectorToObjectSpace(a, v)
	return rot(transpose(a.m), v)
end
function CF.Lerp(a, b, t)
	local m = if t < 0.5 then a.m else b.m
	return cf(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, m)
end
function CF.GetComponents(a)
	local m = a.m
	return a.x, a.y, a.z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9]
end
CF.components = CF.GetComponents
function CF.ToOrientation(a)
	local m = a.m
	local x = math.asin(math.clamp(-m[6], -1, 1))
	local y = math.atan2(m[3], m[9])
	local z = math.atan2(m[4], m[5])
	return x, y, z
end
CF.ToEulerAnglesYXZ = CF.ToOrientation
function CF.ToEulerAnglesXYZ(a)
	local m = a.m
	local y = math.asin(math.clamp(m[3], -1, 1))
	local x = math.atan2(-m[6], m[9])
	local z = math.atan2(-m[2], m[1])
	return x, y, z
end
function CF.ToAxisAngle(a)
	return v3(0, 1, 0), 0
end
local function rx(a)
	local c, s = math.cos(a), math.sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function ry(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rz(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end
local function lookAt(at, target, upv)
	local look = (target - at).Unit
	if look.Magnitude < 1e-9 then
		look = v3(0, 0, -1)
	end
	local up = upv or v3(0, 1, 0)
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(v3(0, 0, 1))
		if right.Magnitude < 1e-6 then
			right = v3(1, 0, 0)
		end
	end
	right = right.Unit
	local up2 = right:Cross(look)
	return cf(at.X, at.Y, at.Z, { right.X, up2.X, -look.X, right.Y, up2.Y, -look.Y, right.Z, up2.Z, -look.Z })
end
function CFrame.new(a, b, c, ...)
	if type(a) == "table" then
		if b ~= nil and type(b) == "table" then
			return lookAt(a, b)
		end
		return cf(a.X, a.Y, a.Z, ID)
	end
	local rest = { ... }
	if #rest == 9 then
		return cf(a, b, c, rest)
	end
	return cf(a or 0, b or 0, c or 0, ID)
end
function CFrame.Angles(a, b, c)
	return cf(0, 0, 0, mulm(mulm(rx(a or 0), ry(b or 0)), rz(c or 0)))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(a, b, c)
	return cf(0, 0, 0, mulm(mulm(ry(b or 0), rx(a or 0)), rz(c or 0)))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
CFrame.lookAt = lookAt
function CFrame.lookAlong(at, direction, up)
	return lookAt(at, at + direction, up)
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	local z = vz or vx:Cross(vy)
	return cf(pos.X, pos.Y, pos.Z, { vx.X, vy.X, z.X, vx.Y, vy.Y, z.Y, vx.Z, vy.Z, z.Z })
end
function CFrame.fromAxisAngle(axis, angle)
	local u = axis.Unit
	local c, s, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
	local x, y, z = u.X, u.Y, u.Z
	return cf(0, 0, 0, {
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c,
	})
end
CFrame.identity = cf(0, 0, 0, ID)

-- ── Colours and the small value types ──────────────────────────────────────
local C3 = {}
C3.__type = "Color3"
C3.__index = C3
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
local Color3 = {}
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	return Color3.new(v, v, v)
end
function Color3.fromHex()
	return Color3.new(0.5, 0.5, 0.5)
end
function C3.Lerp(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3.ToHSV(c)
	return 0, 0, math.max(c.R, c.G, c.B)
end
function C3.ToHex()
	return "808080"
end

local V2 = {}
V2.__type = "Vector2"
V2.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	end
	return V2[k]
end
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return v2(b.X * a, b.Y * a)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b)
	return v2(a.X / b, a.Y / b)
end
local Vector2 = { new = v2, zero = v2(0, 0), one = v2(1, 1) }

local function opaque(name)
	local mt = { __type = name }
	return {
		new = function(...)
			return setmetatable({ ... }, mt)
		end,
		fromScale = function(...)
			return setmetatable({ ... }, mt)
		end,
		fromOffset = function(...)
			return setmetatable({ ... }, mt)
		end,
		fromEnum = function(...)
			return setmetatable({ ... }, mt)
		end,
	}
end

local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, group)
		local items = enumCache[group]
		if not items then
			items = setmetatable({}, {
				__index = function(t, item)
					local made = setmetatable({ Name = item, EnumType = group, Value = #item }, { __type = "EnumItem", __tostring = function()
						return "Enum." .. group .. "." .. item
					end })
					rawset(t, item, made)
					return made
				end,
			})
			enumCache[group] = items
		end
		return items
	end,
})

local Random = {}
function Random.new(seed)
	local state = math.floor(seed or 1) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local function nxt()
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
	return {
		NextNumber = function(_, a, b)
			if a == nil then
				return nxt()
			end
			return a + (b - a) * nxt()
		end,
		NextInteger = function(_, a, b)
			return a + math.floor(nxt() * (b - a + 1))
		end,
		NextUnitVector = function()
			return v3(0, 1, 0)
		end,
		Shuffle = function() end,
		Clone = function(self)
			return self
		end,
	}
end

-- ── Signals and instances ──────────────────────────────────────────────────
local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end, Connected = true }
		end,
		Once = function()
			return { Disconnect = function() end, Connected = true }
		end,
		Wait = function() end,
		Fire = function() end,
	}
end
local EVENTS = {
	Touched = true, TouchEnded = true, Triggered = true, TriggerEnded = true, PromptButtonHoldBegan = true, Changed = true,
	ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true, Destroying = true,
	AncestryChanged = true, Heartbeat = true, Stepped = true, RenderStepped = true, PreSimulation = true,
	PostSimulation = true, PlayerAdded = true, PlayerRemoving = true, Activated = true, MouseButton1Click = true,
	Died = true, Event = true, OnServerEvent = true, OnClientEvent = true, CharacterAdded = true, Completed = true,
	Ended = true, Played = true, Seated = true, StateChanged = true, MoveToFinished = true, PromptShown = true,
	PromptHidden = true, PromptTriggered = true, ProximityPromptTriggered = true,
}
local PARTS = {
	Part = true, WedgePart = true, CornerWedgePart = true, TrussPart = true, SpawnLocation = true, Seat = true,
	VehicleSeat = true, MeshPart = true, UnionOperation = true, PartOperation = true, NegateOperation = true,
}
local KINDS = {
	BasePart = PARTS,
	PVInstance = setmetatable({ Model = true }, { __index = PARTS }),
	FormFactorPart = { Part = true, WedgePart = true, CornerWedgePart = true, SpawnLocation = true, Seat = true, VehicleSeat = true },
	Part = { Part = true, SpawnLocation = true, Seat = true, VehicleSeat = true },
	Light = { PointLight = true, SpotLight = true, SurfaceLight = true },
	GuiObject = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, TextBox = true, CanvasGroup = true },
	GuiBase2d = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, TextBox = true, CanvasGroup = true, SurfaceGui = true, BillboardGui = true, ScreenGui = true },
	LayerCollector = { SurfaceGui = true, BillboardGui = true, ScreenGui = true },
	SurfaceGuiBase = { SurfaceGui = true },
	JointInstance = { Weld = true, Motor6D = true, ManualWeld = true, Snap = true, Glue = true },
	Constraint = { WeldConstraint = false, HingeConstraint = true, RopeConstraint = true, AlignPosition = true, AlignOrientation = true, LinearVelocity = true, AngularVelocity = true, SpringConstraint = true, BallSocketConstraint = true, PrismaticConstraint = true, RodConstraint = true, AnimationConstraint = true, NoCollisionConstraint = true },
	ValueBase = { StringValue = true, NumberValue = true, IntValue = true, BoolValue = true, ObjectValue = true, CFrameValue = true, Vector3Value = true, Color3Value = true },
	Model = { Model = true, Actor = true, WorldModel = true },
	ParticleEmitter = { ParticleEmitter = true },
	Decal = { Decal = true, Texture = true },
	FaceInstance = { Decal = true, Texture = true },
}
M.ALL = {}
M.tags = {} -- tag → { instance → true }
local methods = {}
local IMT = {}
local function children(self)
	return rawget(self, "__children")
end
local function new(className)
	local i = setmetatable({ __children = {}, __attrs = {}, __props = { ClassName = className, Name = className } }, IMT)
	local props = rawget(i, "__props")
	if PARTS[className] then
		props.Size = v3(4, 1, 2)
		props.CFrame = CFrame.identity
		props.Anchored = false
		props.CanCollide = true
		props.CanQuery = true
		props.CanTouch = true
		props.CastShadow = true
		props.Transparency = 0
		props.Color = Color3.new(0.6, 0.6, 0.6)
		props.Material = Enum.Material.Plastic
		props.Shape = Enum.PartType.Block
		props.Massless = false
		props.Reflectance = 0
	elseif KINDS.Light[className] then
		props.Enabled = true
		props.Shadows = false
		props.Brightness = 1
		props.Range = 8
	elseif className == "Attachment" then
		props.CFrame = CFrame.identity
	elseif className == "Model" then
		props.ModelStreamingMode = Enum.ModelStreamingMode.Default
	end
	table.insert(M.ALL, i)
	return i
end
IMT.__type = "Instance"
IMT.__tostring = function(self)
	return rawget(self, "__props").Name
end
IMT.__index = function(self, k)
	local props = rawget(self, "__props")
	if k == "Parent" then
		return rawget(self, "__parent")
	end
	local v = props[k]
	if v ~= nil then
		return v
	end
	local m = methods[k]
	if m then
		return m
	end
	if EVENTS[k] then
		return signal()
	end
	if k == "Position" then
		local c = props.CFrame
		return if c then c.Position else nil
	elseif k == "Orientation" then
		return v3(0, 0, 0)
	elseif k == "WorldPosition" or k == "WorldCFrame" then
		local parent = rawget(self, "__parent")
		local base = if parent and rawget(parent, "__props").CFrame then rawget(parent, "__props").CFrame else CFrame.identity
		local world = base * (props.CFrame or CFrame.identity)
		return if k == "WorldPosition" then world.Position else world
	elseif k == "AssemblyLinearVelocity" or k == "AssemblyAngularVelocity" or k == "Velocity" then
		return v3(0, 0, 0)
	elseif k == "AssemblyMass" or k == "Mass" then
		return 1
	elseif k == "WorldPivot" then
		return methods.GetPivot(self)
	end
	-- a child by name (instance.ChildName)
	for _, c in children(self) do
		if rawget(c, "__props").Name == k then
			return c
		end
	end
	return nil
end
IMT.__newindex = function(self, k, v)
	local props = rawget(self, "__props")
	if k == "Parent" then
		local old = rawget(self, "__parent")
		if old then
			local list = children(old)
			for n, c in list do
				if c == self then
					table.remove(list, n)
					break
				end
			end
		end
		rawset(self, "__parent", v)
		if v then
			table.insert(children(v), self)
		end
		return
	end
	if k == "Position" and props.CFrame then
		local c = props.CFrame
		props.CFrame = cf(v.X, v.Y, v.Z, c.m)
		return
	end
	if k == "WorldPivot" then
		props.__pivot = v
		return
	end
	props[k] = v
end
function methods.SetAttribute(self, k, v)
	rawget(self, "__attrs")[k] = v
end
function methods.GetAttribute(self, k)
	return rawget(self, "__attrs")[k]
end
function methods.GetAttributes(self)
	return table.clone(rawget(self, "__attrs"))
end
function methods.GetAttributeChangedSignal()
	return signal()
end
function methods.GetPropertyChangedSignal()
	return signal()
end
function methods.GetChildren(self)
	return table.clone(children(self))
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(i)
		for _, c in children(i) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name, recursive)
	for _, c in children(self) do
		if rawget(c, "__props").Name == name then
			return c
		end
	end
	if recursive then
		for _, c in children(self) do
			local found = methods.FindFirstChild(c, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods.WaitForChild(self, name)
	return methods.FindFirstChild(self, name)
end
local function isA(className, cls)
	if cls == className or cls == "Instance" then
		return true
	end
	local kind = KINDS[cls]
	return kind ~= nil and kind[className] == true
end
function methods.IsA(self, cls)
	return isA(rawget(self, "__props").ClassName, cls)
end
function methods.FindFirstChildOfClass(self, cls)
	for _, c in children(self) do
		if rawget(c, "__props").ClassName == cls then
			return c
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, cls, recursive)
	for _, c in children(self) do
		if methods.IsA(c, cls) then
			return c
		end
	end
	if recursive then
		for _, c in children(self) do
			local found = methods.FindFirstChildWhichIsA(c, cls, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function methods.FindFirstAncestor(self, name)
	local p = rawget(self, "__parent")
	while p do
		if rawget(p, "__props").Name == name then
			return p
		end
		p = rawget(p, "__parent")
	end
	return nil
end
function methods.FindFirstAncestorOfClass(self, cls)
	local p = rawget(self, "__parent")
	while p do
		if rawget(p, "__props").ClassName == cls then
			return p
		end
		p = rawget(p, "__parent")
	end
	return nil
end
methods.FindFirstAncestorWhichIsA = methods.FindFirstAncestorOfClass
function methods.IsDescendantOf(self, other)
	local p = rawget(self, "__parent")
	while p do
		if p == other then
			return true
		end
		p = rawget(p, "__parent")
	end
	return false
end
function methods.IsAncestorOf(self, other)
	return methods.IsDescendantOf(other, self)
end
function methods.Destroy(self)
	self.Parent = nil
	rawset(self, "__destroyed", true)
	for _, c in table.clone(children(self)) do
		methods.Destroy(c)
	end
end
function methods.ClearAllChildren(self)
	for _, c in table.clone(children(self)) do
		methods.Destroy(c)
	end
end
function methods.Clone(self)
	local copy = new(rawget(self, "__props").ClassName)
	for k, v in rawget(self, "__props") do
		rawget(copy, "__props")[k] = v
	end
	for k, v in rawget(self, "__attrs") do
		rawget(copy, "__attrs")[k] = v
	end
	for tag, set in M.tags do
		if set[self] then
			set[copy] = true
		end
	end
	for _, c in children(self) do
		local cc = methods.Clone(c)
		cc.Parent = copy
	end
	return copy
end
function methods.GetPivot(self)
	local props = rawget(self, "__props")
	if props.__pivot then
		return props.__pivot
	end
	if props.CFrame then
		return props.CFrame
	end
	local primary = props.PrimaryPart
	if primary then
		return rawget(primary, "__props").CFrame
	end
	for _, d in methods.GetDescendants(self) do
		local c = rawget(d, "__props").CFrame
		if c and PARTS[rawget(d, "__props").ClassName] then
			return c
		end
	end
	return CFrame.identity
end
function methods.PivotTo(self, target)
	local current = methods.GetPivot(self)
	local delta = target * current:Inverse()
	local props = rawget(self, "__props")
	if props.CFrame then
		props.CFrame = delta * props.CFrame
	end
	for _, d in methods.GetDescendants(self) do
		local dp = rawget(d, "__props")
		if dp.CFrame and PARTS[dp.ClassName] then
			dp.CFrame = delta * dp.CFrame
		end
	end
	if props.__pivot then
		props.__pivot = target
	end
end
function methods.SetPrimaryPartCFrame(self, target)
	methods.PivotTo(self, target)
end
function methods.GetBoundingBox(self)
	return methods.GetPivot(self), v3(10, 10, 10)
end
function methods.GetExtentsSize()
	return v3(10, 10, 10)
end
function methods.UnionAsync(self)
	local u = new("UnionOperation")
	local props = rawget(u, "__props")
	props.CFrame = rawget(self, "__props").CFrame
	props.Size = rawget(self, "__props").Size
	return u
end
function methods.SubtractAsync(self)
	return methods.UnionAsync(self)
end
function methods.AddPersistentPlayer() end
function methods.RemovePersistentPlayer() end
function methods.Play() end
function methods.Stop() end
function methods.Emit() end
function methods.Clear() end
function methods.FillBlock() end
function methods.FillBall() end
function methods.FillCylinder() end
function methods.FillWedge() end
function methods.FillRegion() end
function methods.ReplaceMaterial() end
function methods.SetMaterialColor() end
function methods.BreakJoints() end
function methods.MakeJoints() end
function methods.SetNetworkOwner() end
function methods.ApplyImpulse() end
function methods.MoveTo() end
function methods.LoadAnimation()
	return { Play = function() end, Stop = function() end, AdjustSpeed = function() end, Looped = false }
end
function methods.GetTextSize(_, text, size)
	return v2(#tostring(text) * size * 0.6, size)
end
function methods.GetPlayers()
	return {}
end
function methods.GetPlayerFromCharacter()
	return nil
end
function methods.GetPartBoundsInBox()
	return {}
end
function methods.GetPartBoundsInRadius()
	return {}
end
function methods.GetPartsInPart()
	return {}
end
function methods.Raycast()
	return nil
end
function methods.Blockcast()
	return nil
end
function methods.Spherecast()
	return nil
end
function methods.GetServerTimeNow()
	return os.clock()
end
function methods.IsStudio()
	return false
end
function methods.IsServer()
	return true
end
function methods.IsClient()
	return false
end
function methods.Create()
	return { Play = function() end, Cancel = function() end, Completed = signal() }
end
function methods.AddItem() end
-- CollectionService
function methods.AddTag(self, instance, tag)
	if tag == nil then
		-- instance:AddTag(tag)
		tag, instance = instance, self
	end
	M.tags[tag] = M.tags[tag] or {}
	M.tags[tag][instance] = true
end
function methods.RemoveTag(self, instance, tag)
	if tag == nil then
		tag, instance = instance, self
	end
	if M.tags[tag] then
		M.tags[tag][instance] = nil
	end
end
function methods.HasTag(self, instance, tag)
	if tag == nil then
		tag, instance = instance, self
	end
	return M.tags[tag] ~= nil and M.tags[tag][instance] == true
end
function methods.GetTagged(_, tag)
	local out = {}
	for i in M.tags[tag] or {} do
		table.insert(out, i)
	end
	return out
end
function methods.GetInstanceAddedSignal()
	return signal()
end
function methods.GetInstanceRemovedSignal()
	return signal()
end
function methods.CollisionGroupSetCollidable() end
function methods.RegisterCollisionGroup() end
function methods.CreateCollisionGroup() end
function methods.GetService(self, name)
	return rawget(self, "__services")[name]
end
function methods.GetAsync()
	return nil
end

-- ── The data model ─────────────────────────────────────────────────────────
local game = new("DataModel")
local workspace = new("Workspace")
workspace.Name = "Workspace"
workspace.Parent = game
local terrain = new("Terrain")
terrain.Name = "Terrain"
terrain.Parent = workspace
local services = { Workspace = workspace }
for _, name in { "Lighting", "ReplicatedStorage", "ServerStorage", "ServerScriptService", "Players", "RunService", "CollectionService", "TextService", "PhysicsService", "TweenService", "Debris", "HttpService", "SoundService", "StarterPlayer", "Teams", "PathfindingService", "MarketplaceService", "DataStoreService", "MessagingService", "TeleportService", "BadgeService", "ProximityPromptService" } do
	local s = new(name)
	s.Name = name
	s.Parent = game
	services[name] = s
end
rawset(game, "__services", services)
local shared = new("Folder")
shared.Name = "Shared"
shared.Parent = services.ReplicatedStorage

local spawned = setmetatable({}, { __mode = "k" })
local task = {
	wait = function()
		local co = coroutine.running()
		if co and spawned[co] then
			coroutine.yield() -- (a spawned loop: it stops here for good)
		end
		return 0
	end,
	spawn = function(f, ...)
		local co = coroutine.create(f)
		spawned[co] = true
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			print("[task.spawn error] " .. tostring(err))
		end
		return co
	end,
	defer = function() end,
	delay = function() end,
	cancel = function() end,
}

local function typeof(v)
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if mt and mt.__type then
			return mt.__type
		end
	end
	return t
end

local G = {
	Vector3 = Vector3,
	CFrame = CFrame,
	Color3 = Color3,
	Vector2 = Vector2,
	UDim = opaque("UDim"),
	UDim2 = opaque("UDim2"),
	NumberSequence = opaque("NumberSequence"),
	NumberSequenceKeypoint = opaque("NumberSequenceKeypoint"),
	ColorSequence = opaque("ColorSequence"),
	ColorSequenceKeypoint = opaque("ColorSequenceKeypoint"),
	NumberRange = opaque("NumberRange"),
	PhysicalProperties = opaque("PhysicalProperties"),
	BrickColor = opaque("BrickColor"),
	TweenInfo = opaque("TweenInfo"),
	Font = opaque("Font"),
	Rect = opaque("Rect"),
	Region3 = opaque("Region3"),
	Ray = opaque("Ray"),
	OverlapParams = { new = function() return {} end },
	RaycastParams = { new = function() return {} end },
	Enum = Enum,
	Random = Random,
	Instance = { new = function(className, parent)
		local i = new(className)
		if parent then
			i.Parent = parent
		end
		return i
	end },
	game = game,
	workspace = workspace,
	task = task,
	typeof = typeof,
	tick = os.clock,
	time = os.clock,
	wait = task.wait,
	warn = function(...)
		print("[warn]", ...)
	end,
	settings = function()
		return {}
	end,
	UserSettings = function()
		return {}
	end,
}
M.globals = G
M.workspace = workspace
M.game = game
M.isA = isA
M.PARTS = PARTS
M.env = setmetatable({}, {
	__index = function(_, k)
		local v = G[k]
		if v ~= nil then
			return v
		end
		return BASE[k]
	end,
})
return M
