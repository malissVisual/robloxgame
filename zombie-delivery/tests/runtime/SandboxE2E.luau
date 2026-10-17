--!nocheck
-- 8.2 e2e: the Roblox stand-in the whole sandbox loop runs on in the Luau CLI (tests/sandbox_e2e_runtime_test.luau
-- through tests/run_tests.py). The REAL server modules of the loop are staged as E2E<Name>.luau, each with this
-- environment (setfenv(1, SandboxE2E.env): no module gains a local, the -O0 register limit): SandboxBoot (the real
-- boot), SandboxWorld and HouseMesh (the map), PlayerData, SandboxPlots, Collection, Warehouse, Upgrades, Moving with
-- MoveLobby, MoveHelper, MoveGreeters, PairHold and MoveSites, HouseInterior and FurnitureMesh, and shared/Net.luau
-- (E2ENet: its real RemoteEvents and rate limits); 8.3: VanPaint (the PAINT shop: it paints the fake vans through its
-- prompts' loop, shared/VanLook.luau on the recorder). The shared modules are the pure copies run_tests.py made
-- (FurnitureLooks and HouseLayout on tools/fixtures/item-mock.luau, the recorder this stands on).
--
-- What is mocked: Roblox itself, and the server modules that are Roblox through and through (physics, rigs, AI):
--   * the instances: the item recorder, patched to behave: lazily made signals that fire (Triggered, ChildAdded,
--     AncestryChanged, Died, HealthChanged, AttributeChanged, GetPropertyChangedSignal …), Position and CFrame kept
--     in step, attachments' WorldPosition, PivotTo on parts and models, IsA by class families, WaitForChild that waits,
--     Destroy (Destroying, children), Clone without shared signals;
--   * the scheduler: the test's clock (os.clock, os.time, workspace:GetServerTimeNow) moves only with E.advance, which
--     wakes every task.wait / task.delay thread at its own time; task.spawn and every signal's handlers run at once in
--     their own thread (they may yield); task.defer runs at E.flush (advance flushes). An error in a thread is kept in
--     E.errors (the test fails on it), never thrown at the caller;
--   * the services: Players (E.join / E.leave: PlayerAdded, the character with CharacterAdded, PlayerRemoving), one
--     DataStore that keeps what JSON would (a copy; NaN, functions, mixed tables are errors) and yields a moment like the
--     real one, OrderedDataStores (E.ordered: whole numbers), CollectionService's tags, Workspace's rays (the ground, the road, an interior's floor), PhysicsService,
--     PathfindingService (no path: Danny walks straight, E.mover), RunService (the server, not Studio) …;
--   * the fakes of the Roblox-heavy server modules: Vehicles (a Sprinter with the real numbers: SprinterLooks' CargoDoor,
--     the chassis' height, the cargo slots, the BackPrompt with Vehicles' rules: owner or crew, on foot, a hand free, the
--     van standing; workspace.Cars and its OwnerId / SpeedMult attributes), Zombies, Npcs (Danny's body), Crew (nobody
--     in a crew), Hand, and the boot's other services' start (no-ops). server/Analytics.luau is the real one: Roblox's
--     AnalyticsService under it records every call (E.analytics);
--   * the "physics": a WeldConstraint to a character's root or a van's chassis keeps its piece where it was welded
--     (E.settleWelds after every thread step: a carried piece walks with its carrier, a loaded one drives with the van).
--
-- The test's hands and feet: E.join / E.spawn / E.leave, E.fire (a client's request on a remote), E.trigger (a prompt:
-- only enabled and within its reach, as Roblox checks; a hold advances the clock), E.walk (the root in 0.1 s steps at a
-- walk, the clock moving: the game sees a walk, not a teleport; it stops when the game moves the body, a door's fade),
-- E.seat / E.unseat / E.drive (the van along waypoints at a speed, its driver and its welded load with it), E.waitUntil.
-- The client: E.clients[player] = fn(remoteName, ...) hears every FireClient to that player (it may answer with
-- task.delay + E.fire). E.sent keeps every FireClient: E.messages / E.lastNotice / E.heard read it.
local Mock = require("./ItemMock")
local Config = require("./Config")
local SandboxMapReal = require("./SandboxMap")
local SprinterLooks = require("./SprinterLooks")
local Economy = require("./Economy")
local Map = require("./Map")

local BASE = getfenv(1)

local E: any = {
	clock = 100, -- os.clock()
	now = 5000, -- workspace:GetServerTimeNow()
	wall = 1760000000, -- os.time()
	frame = 1 / 30, -- task.wait()'s least wait
	errors = {}, -- errors in threads
	warnings = {}, -- warn(...)
	printed = {}, -- print(...) from the modules
	sent = {}, -- { remote, player, args } every FireClient
	saves = {}, -- the DataStore: key → value
	writes = 0,
	welds = {}, -- { weld, offset } welds to a character's root or a van's chassis (E.settleWelds)
	clients = {}, -- player → fn(remote, ...) the player's client
	unknownServices = {}, -- GetService names this stand-in does not know (a permissive instance each)
	storeLatency = 0.05, -- s a DataStore call yields
	ping = 0.08, -- s: every player's Player:GetNetworkPing()
	tags = {}, -- CollectionService: tag → { instance → true }
	Mock = Mock,
	Config = Config,
}

local O = getmetatable(Mock.Instance.new("Folder"))
local F = getmetatable(Mock.CFrame.new())
local V = getmetatable(Mock.Vector3.new())
local C = getmetatable(Mock.Color3.new(0, 0, 0))
local V3 = Mock.Vector3.new
E.O, E.F, E.V = O, F, V

-- ── The scheduler ─────────────────────────────────────────────────────────

local sleeping: { any } = {}
local deferred: { any } = {}
local order = 0

local function report(text: string)
	table.insert(E.errors, text)
	print("THREAD ERROR " .. text)
end

local function step(co: thread, ...: any)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		report(debug.traceback(co, tostring(err)))
	end
	E.settleWelds()
end

local task: any = {}
function task.spawn(fn: any, ...: any): thread
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	step(co, ...)
	return co
end
function task.defer(fn: any, ...: any): thread
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	table.insert(deferred, { co = co, args = table.pack(...) })
	return co
end
function task.delay(seconds: number?, fn: any, ...: any): thread
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	order += 1
	table.insert(sleeping, { co = co, wake = E.clock + math.max(0, seconds or 0), args = table.pack(...), order = order })
	return co
end
function task.wait(seconds: number?): number
	local wait = math.max(seconds or 0, E.frame)
	if coroutine.isyieldable() then
		local start = E.clock
		order += 1
		table.insert(sleeping, { co = coroutine.running(), wake = E.clock + wait, order = order })
		coroutine.yield()
		return E.clock - start
	end
	E.advance(wait) -- (the main thread: the time passes, every thread waiting wakes)
	return wait
end
function task.cancel(co: thread)
	for index = #sleeping, 1, -1 do
		if sleeping[index].co == co then
			table.remove(sleeping, index)
		end
	end
	for index = #deferred, 1, -1 do
		if deferred[index].co == co then
			table.remove(deferred, index)
		end
	end
end
task.synchronize = function() end
task.desynchronize = function() end
E.task = task

-- Runs every deferred thread (and the ones they defer).
function E.flush()
	local guard = 0
	while #deferred > 0 do
		guard += 1
		assert(guard < 200000, "SandboxE2E: task.defer loops")
		local job = table.remove(deferred, 1)
		if coroutine.status(job.co) == "suspended" then
			step(job.co, table.unpack(job.args, 1, job.args.n))
		end
	end
end

local function pass(dt: number)
	E.clock += dt
	E.now += dt
	E.wall += dt
end

-- Moves the clock `seconds` on, waking every waiting thread at its own time (in order), the deferred ones after each.
function E.advance(seconds: number)
	local target = E.clock + math.max(0, seconds)
	E.flush()
	while true do
		local best, at, first = nil, math.huge, math.huge
		for index, entry in sleeping do
			if entry.wake <= target + 1e-9 and (entry.wake < at or (entry.wake == at and entry.order < first)) then
				best, at, first = index, entry.wake, entry.order
			end
		end
		if not best then
			break
		end
		local entry = table.remove(sleeping, best)
		if entry.wake > E.clock then
			pass(entry.wake - E.clock)
		end
		if coroutine.status(entry.co) == "suspended" then
			if entry.args then
				step(entry.co, table.unpack(entry.args, 1, entry.args.n))
			else
				step(entry.co)
			end
		end
		E.flush()
	end
	if target > E.clock then
		pass(target - E.clock)
	end
end

-- Advances in `every` s steps until fn() is true (→ true) or `timeout` s went by (→ false).
function E.waitUntil(fn: () -> boolean, timeout: number, every: number?): boolean
	local waited = 0
	while not fn() do
		if waited >= timeout then
			return false
		end
		E.advance(every or 0.1)
		waited += every or 0.1
	end
	return true
end

-- ── Signals ───────────────────────────────────────────────────────────────

local SignalMT: any = {}
SignalMT.__index = SignalMT
function SignalMT.Connect(self: any, fn: any): any
	local handlers = self.handlers
	if #handlers > 24 then -- (drop the disconnected ones now and then)
		local kept = {}
		for _, h in handlers do
			if h.on then
				table.insert(kept, h)
			end
		end
		self.handlers = kept
		handlers = kept
	end
	local h = { fn = fn, on = true }
	table.insert(handlers, h)
	local connection: any = { Connected = true }
	function connection.Disconnect()
		h.on = false
		connection.Connected = false
	end
	return connection
end
SignalMT.connect = SignalMT.Connect
function SignalMT.Once(self: any, fn: any): any
	local connection: any = nil
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end
function SignalMT.Wait(self: any): ...any
	assert(coroutine.isyieldable(), "SandboxE2E: Signal:Wait on the main thread")
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end
function SignalMT.Fire(self: any, ...: any)
	if #self.handlers > 0 then
		for _, h in table.clone(self.handlers) do
			if h.on then
				task.spawn(h.fn, ...)
			end
		end
	end
	if #self.waiting > 0 then
		local waiting = self.waiting
		self.waiting = {}
		for _, co in waiting do
			step(co, ...)
		end
	end
end
local function signal(): any
	return setmetatable({ handlers = {}, waiting = {} }, SignalMT)
end
E.signal = signal
E.SignalMT = SignalMT

-- ── Vector3, CFrame, Color3 and the small types (the recorder's, completed) ─

V.__eq = function(a: any, b: any): boolean
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V.__mul = function(a: any, b: any): any
	if type(a) == "number" then
		return V3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return V3(a.X * b, a.Y * b, a.Z * b)
	end
	return V3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a: any, b: any): any
	if type(b) == "number" then
		return V3(a.X / b, a.Y / b, a.Z / b)
	end
	return V3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V.__tostring = function(v: any): string
	return string.format("%.2f, %.2f, %.2f", v.X, v.Y, v.Z)
end
function V.Lerp(a: any, b: any, t: number): any
	return a + (b - a) * t
end
function V.Min(a: any, b: any): any
	return V3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function V.Max(a: any, b: any): any
	return V3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function V.Abs(a: any): any
	return V3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V.FuzzyEq(a: any, b: any, eps: number?): boolean
	return (a - b).Magnitude <= (eps or 1e-5)
end
function V.Angle(a: any, b: any): number
	local m = a.Magnitude * b.Magnitude
	return if m < 1e-12 then 0 else math.acos(math.clamp(a:Dot(b) / m, -1, 1))
end
Mock.Vector3.one = V3(1, 1, 1)

local function frame(p: any, r: any): any
	return setmetatable({ Position = p, R = r }, F)
end
local function rotate(r: any, v: any): any
	return V3(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
local function transpose(r: any): any
	return { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
end
local ID = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
F.__index = function(self: any, k: any): any
	local method = rawget(F, k)
	if method ~= nil then
		return method
	end
	local r = rawget(self, "R")
	if k == "LookVector" then
		return V3(-r[3], -r[6], -r[9])
	elseif k == "RightVector" or k == "XVector" then
		return V3(r[1], r[4], r[7])
	elseif k == "UpVector" or k == "YVector" then
		return V3(r[2], r[5], r[8])
	elseif k == "ZVector" then
		return V3(r[3], r[6], r[9])
	elseif k == "Rotation" then
		return frame(V3(0, 0, 0), r)
	elseif k == "X" then
		return rawget(self, "Position").X
	elseif k == "Y" then
		return rawget(self, "Position").Y
	elseif k == "Z" then
		return rawget(self, "Position").Z
	elseif k == "p" then
		return rawget(self, "Position")
	end
	return nil
end
F.__add = function(a: any, v: any): any
	return frame(a.Position + v, a.R)
end
F.__sub = function(a: any, v: any): any
	return frame(a.Position - v, a.R)
end
F.__tostring = function(a: any): string
	return "CFrame(" .. tostring(a.Position) .. ")"
end
function F.ToOrientation(self: any): (number, number, number)
	local m = self.R
	return math.asin(math.clamp(-m[6], -1, 1)), math.atan2(m[3], m[9]), math.atan2(m[4], m[5])
end
F.ToEulerAnglesYXZ = F.ToOrientation
function F.ToEulerAnglesXYZ(self: any): (number, number, number)
	local m = self.R
	return math.atan2(-m[6], m[9]), math.asin(math.clamp(m[3], -1, 1)), math.atan2(-m[2], m[1])
end
function F.PointToWorldSpace(self: any, v: any): any
	return self * v
end
function F.ToWorldSpace(self: any, other: any): any
	return self * other
end
function F.VectorToWorldSpace(self: any, v: any): any
	return rotate(self.R, v)
end
function F.VectorToObjectSpace(self: any, v: any): any
	return rotate(transpose(self.R), v)
end
function F.Lerp(a: any, b: any, t: number): any
	return frame(a.Position + (b.Position - a.Position) * t, if t < 0.5 then a.R else b.R)
end
function F.FuzzyEq(a: any, b: any, eps: number?): boolean
	return (a.Position - b.Position).Magnitude <= (eps or 1e-5)
end
F.components = F.GetComponents
-- The frame with its rotation made orthonormal again (Gram–Schmidt on its right and up vectors). A pivot inverted by its
-- transpose must be a rotation: else every move of a piece that follows a body (a weld, a PivotTo) squares its error.
local function orthonormal(cf: any): any
	local r = cf.R
	local x = V3(r[1], r[4], r[7]).Unit
	local y = V3(r[2], r[5], r[8])
	y = (y - x * x:Dot(y)).Unit
	local z = x:Cross(y)
	return frame(cf.Position, { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z })
end
E.orthonormal = orthonormal
F.Orthonormalize = orthonormal
local baseNew = Mock.CFrame.new
local function lookAt(at: any, target: any, upv: any?): any
	local look = target - at
	if look.Magnitude < 1e-9 then
		look = V3(0, 0, -1)
	end
	look = look.Unit
	local up = upv or V3(0, 1, 0)
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(V3(0, 0, 1))
		if right.Magnitude < 1e-6 then
			right = V3(1, 0, 0)
		end
	end
	right = right.Unit
	local up2 = right:Cross(look)
	return frame(at, { right.X, up2.X, -look.X, right.Y, up2.Y, -look.Y, right.Z, up2.Z, -look.Z })
end
Mock.CFrame.new = function(a: any, b: any, c: any, ...: any): any
	if type(a) == "table" and type(b) == "table" then
		return lookAt(a, b)
	elseif a == nil then
		return frame(V3(0, 0, 0), ID)
	end
	return baseNew(a, b, c, ...)
end
Mock.CFrame.lookAt = lookAt
Mock.CFrame.lookAlong = function(at: any, direction: any, up: any?): any
	return lookAt(at, at + direction, up)
end
Mock.CFrame.identity = frame(V3(0, 0, 0), ID)
Mock.CFrame.fromEulerAnglesXYZ = Mock.CFrame.Angles
Mock.CFrame.fromEulerAnglesYXZ = function(x: number, y: number, z: number): any
	return Mock.CFrame.Angles(0, y, 0) * Mock.CFrame.Angles(x, 0, 0) * Mock.CFrame.Angles(0, 0, z)
end
Mock.CFrame.fromOrientation = Mock.CFrame.fromEulerAnglesYXZ
Mock.CFrame.fromMatrix = function(pos: any, vx: any, vy: any, vz: any?): any
	local z = vz or vx:Cross(vy)
	return frame(pos, { vx.X, vy.X, z.X, vx.Y, vy.Y, z.Y, vx.Z, vy.Z, z.Z })
end
Mock.CFrame.fromAxisAngle = function(axis: any, angle: number): any
	local u = axis.Unit
	local c, s, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
	local x, y, z = u.X, u.Y, u.Z
	return frame(V3(0, 0, 0), {
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c,
	})
end

C.__eq = function(a: any, b: any): boolean
	return a.R == b.R and a.G == b.G and a.B == b.B
end
function C.ToHSV(c: any): (number, number, number)
	return 0, 0, math.max(c.R, c.G, c.B)
end
function C.ToHex(): string
	return "808080"
end
Mock.Color3.fromHSV = function(_h: number, _s: number, v: number): any
	return Mock.Color3.new(v, v, v)
end
Mock.Color3.fromHex = function(): any
	return Mock.Color3.new(0.5, 0.5, 0.5)
end

local function opaque(name: string): any
	local mt = { __type = name }
	local function make(...: any): any
		return setmetatable({ ... }, mt)
	end
	return { new = make, fromScale = make, fromOffset = make, fromEnum = make, fromName = make, random = make }
end
Mock.UDim = opaque("UDim")
Mock.UDim2 = opaque("UDim2")
Mock.Vector2 = { new = function(x: number?, y: number?): any
	return { X = x or 0, Y = y or 0 }
end, zero = { X = 0, Y = 0 }, one = { X = 1, Y = 1 } }

-- Random.new(seed): a Park–Miller generator (deterministic; no seed: the next of a fixed sequence).
local randomSerial = 0
local Random: any = {}
function Random.new(seed: number?): any
	randomSerial += 1
	local state = math.floor(seed or (7919 * randomSerial)) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local function nxt(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
	return {
		NextNumber = function(_: any, a: number?, b: number?): number
			if a == nil then
				return nxt()
			end
			return a + ((b :: number) - a) * nxt()
		end,
		NextInteger = function(_: any, a: number, b: number): number
			return a + math.floor(nxt() * (b - a + 1))
		end,
		NextUnitVector = function(): any
			return V3(0, 1, 0)
		end,
		Shuffle = function() end,
		Clone = function(self: any): any
			return self
		end,
	}
end

-- ── Instances (the recorder, patched) ─────────────────────────────────────

local PARTS = { Part = true, WedgePart = true, CornerWedgePart = true, TrussPart = true, SpawnLocation = true, Seat = true, VehicleSeat = true, MeshPart = true, UnionOperation = true }
local KINDS: { [string]: { [string]: boolean } } = {
	BasePart = PARTS,
	PVInstance = setmetatable({ Model = true, Actor = true }, { __index = PARTS }),
	FormFactorPart = { Part = true, WedgePart = true, CornerWedgePart = true, SpawnLocation = true, Seat = true, VehicleSeat = true },
	Part = { Part = true, SpawnLocation = true, Seat = true, VehicleSeat = true },
	Model = { Model = true, Actor = true, WorldModel = true, Workspace = true },
	Light = { PointLight = true, SpotLight = true, SurfaceLight = true },
	GuiObject = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, TextBox = true, CanvasGroup = true },
	GuiBase2d = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, TextBox = true, CanvasGroup = true, SurfaceGui = true, BillboardGui = true, ScreenGui = true },
	LayerCollector = { SurfaceGui = true, BillboardGui = true, ScreenGui = true },
	SurfaceGuiBase = { SurfaceGui = true },
	JointInstance = { Weld = true, Motor6D = true, ManualWeld = true },
	Constraint = { HingeConstraint = true, RopeConstraint = true, AlignPosition = true, AlignOrientation = true, LinearVelocity = true, AngularVelocity = true, SpringConstraint = true, BallSocketConstraint = true, PrismaticConstraint = true, RodConstraint = true, AnimationConstraint = true, NoCollisionConstraint = true, VectorForce = true },
	ValueBase = { StringValue = true, NumberValue = true, IntValue = true, BoolValue = true, ObjectValue = true, CFrameValue = true, Vector3Value = true, Color3Value = true },
	Decal = { Decal = true, Texture = true },
	FaceInstance = { Decal = true, Texture = true },
	LuaSourceContainer = { ModuleScript = true, Script = true, LocalScript = true },
	PostEffect = { ColorCorrectionEffect = true, BloomEffect = true, BlurEffect = true, SunRaysEffect = true, DepthOfFieldEffect = true },
}

local function classOf(self: any): string
	return rawget(self, "props").ClassName
end
local function isA(className: string, cls: string): boolean
	if cls == className or cls == "Instance" then
		return true
	end
	local kind = KINDS[cls]
	return kind ~= nil and kind[className] == true
end

local EVENTS = {
	Triggered = true, TriggerEnded = true, PromptButtonHoldBegan = true, PromptButtonHoldEnded = true, PromptShown = true,
	PromptHidden = true, AncestryChanged = true, Died = true, HealthChanged = true, StateChanged = true, AttributeChanged = true,
	CharacterAdded = true, CharacterRemoving = true, CharacterAppearanceLoaded = true, Destroying = true, ChildAdded = true,
	ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true, Changed = true, Touched = true, TouchEnded = true,
	OnServerEvent = true, OnClientEvent = true, Event = true, PlayerAdded = true, PlayerRemoving = true, Seated = true,
	Running = true, Jumping = true, FreeFalling = true, MoveToFinished = true, Activated = true, Completed = true, Heartbeat = true,
	Stepped = true, RenderStepped = true, PreSimulation = true, PostSimulation = true, PreRender = true, PreAnimation = true,
	Blocked = true, Error = true, Chatted = true, Idled = true, ProximityPromptTriggered = true, PromptTriggered = true,
}

local watched = setmetatable({}, { __mode = "k" }) -- instances with an AncestryChanged signal

local function isDescendantOf(node: any, ancestor: any): boolean
	local at = rawget(node, "props").Parent
	while at do
		if at == ancestor then
			return true
		end
		local props = rawget(at, "props")
		at = props and props.Parent
	end
	return false
end

local trackWeld: (any) -> ()

local function reparent(self: any, parent: any)
	local props = rawget(self, "props")
	local old = props.Parent
	if old == parent then
		return
	end
	if old then
		local list = rawget(old, "children")
		if list then
			for index, child in list do
				if child == self then
					table.remove(list, index)
					break
				end
			end
		end
	end
	props.Parent = parent
	if parent then
		table.insert(rawget(parent, "children"), self)
	end
	if old then
		local oldProps = rawget(old, "props")
		local removed = oldProps and oldProps.ChildRemoved
		if removed then
			removed:Fire(self)
		end
	end
	if parent then
		local parentProps = rawget(parent, "props")
		local added = parentProps and parentProps.ChildAdded
		if added then
			added:Fire(self)
		end
		local node = parent
		while node do
			local nodeProps = rawget(node, "props")
			if not nodeProps then
				break
			end
			local descendant = nodeProps.DescendantAdded
			if descendant then
				descendant:Fire(self)
			end
			node = nodeProps.Parent
		end
		if props.ClassName == "WeldConstraint" then
			trackWeld(self)
		end
	end
	if next(watched) ~= nil then
		for inst in watched do
			if inst == self or isDescendantOf(inst, self) then
				local changed = rawget(inst, "props").AncestryChanged
				if changed then
					changed:Fire(self, parent)
				end
			end
		end
	end
end

O.__index = function(self: any, k: any): any
	local method = rawget(O, k)
	if method ~= nil then
		return method
	end
	local props = rawget(self, "props")
	if k == "Position" then
		local cf = props.CFrame
		return if cf then cf.Position else props.Position
	end
	local value = props[k]
	if value ~= nil then
		return value
	end
	if EVENTS[k] then
		local made = signal()
		props[k] = made
		if k == "AncestryChanged" then
			watched[self] = true
		end
		return made
	end
	if k == "WorldPosition" or k == "WorldCFrame" then
		local parent = props.Parent
		local base = if parent and rawget(parent, "props") and rawget(parent, "props").CFrame and isA(classOf(parent), "BasePart") then rawget(parent, "props").CFrame else Mock.CFrame.identity
		local world = base * (props.CFrame or Mock.CFrame.identity)
		return if k == "WorldPosition" then world.Position else world
	elseif k == "AssemblyLinearVelocity" or k == "AssemblyAngularVelocity" or k == "Velocity" or k == "RotVelocity" then
		return V3(0, 0, 0)
	elseif k == "Orientation" then
		return V3(0, 0, 0)
	end
	return nil
end

O.__newindex = function(self: any, k: any, v: any)
	local props = rawget(self, "props")
	if k == "Parent" then
		reparent(self, v)
		return
	end
	if k == "Position" then
		local cf = props.CFrame
		if cf then
			v = frame(v, cf.R)
			k = "CFrame"
		end
	end
	local old = props[k]
	props[k] = v
	if old ~= v then
		local signals = rawget(self, "psignals")
		local changed = signals and signals[k]
		if changed then
			changed:Fire()
		end
		if k == "Health" and props.ClassName == "Humanoid" and type(v) == "number" and type(old) == "number" then
			local health = props.HealthChanged
			if health then
				health:Fire(v)
			end
			if v <= 0 and old > 0 then
				local died = props.Died
				if died then
					died:Fire()
				end
			end
		end
	end
end

local create = Mock.Instance.new
Mock.Instance.new = function(class: string, parent: any?): any
	local obj = create(class)
	local props = rawget(obj, "props")
	if class == "ProximityPrompt" then
		props.Enabled = true
		props.MaxActivationDistance = 10
		props.HoldDuration = 0
		props.RequiresLineOfSight = true
		props.ActionText = ""
		props.ObjectText = ""
		props.KeyboardKeyCode = "E"
	elseif class == "Humanoid" then
		props.Health = 100
		props.MaxHealth = 100
		props.HipHeight = 2
		props.WalkSpeed = 16
		props.FloorMaterial = "Plastic"
	elseif class == "WeldConstraint" then
		props.Enabled = true
	elseif class == "Model" then
		props.ModelStreamingMode = "Default"
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end
local Instance = Mock.Instance

function O.IsA(self: any, cls: string): boolean
	return isA(classOf(self), cls)
end
function O.GetChildren(self: any): { any }
	return table.clone(rawget(self, "children"))
end
function O.GetDescendants(self: any): { any }
	local out = {}
	local function walk(node: any)
		for _, child in rawget(node, "children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end
function O.FindFirstChild(self: any, name: string, recursive: boolean?): any
	for _, child in rawget(self, "children") do
		if child.Name == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "children") do
			local found = child.FindFirstChild and child:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function O.WaitForChild(self: any, name: string, timeout: number?): any
	local found = self:FindFirstChild(name)
	if found or not coroutine.isyieldable() then
		return found
	end
	local waited, limit = 0, timeout or 30
	while waited < limit do
		waited += task.wait(0.1)
		found = self:FindFirstChild(name)
		if found then
			return found
		end
	end
	return nil
end
function O.FindFirstChildOfClass(self: any, class: string): any
	for _, child in rawget(self, "children") do
		if child.ClassName == class then
			return child
		end
	end
	return nil
end
function O.FindFirstChildWhichIsA(self: any, class: string, recursive: boolean?): any
	for _, child in rawget(self, "children") do
		if child.IsA and child:IsA(class) then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "children") do
			local found = child.FindFirstChildWhichIsA and child:FindFirstChildWhichIsA(class, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function O.FindFirstAncestor(self: any, name: string): any
	local at = self.Parent
	while at do
		if at.Name == name then
			return at
		end
		at = at.Parent
	end
	return nil
end
function O.FindFirstAncestorWhichIsA(self: any, class: string): any
	local at = self.Parent
	while at do
		if at.IsA and at:IsA(class) then
			return at
		end
		at = at.Parent
	end
	return nil
end
O.FindFirstAncestorOfClass = function(self: any, class: string): any
	local at = self.Parent
	while at do
		if at.ClassName == class then
			return at
		end
		at = at.Parent
	end
	return nil
end
function O.IsDescendantOf(self: any, ancestor: any): boolean
	return isDescendantOf(self, ancestor)
end
function O.IsAncestorOf(self: any, other: any): boolean
	return isDescendantOf(other, self)
end
function O.GetFullName(self: any): string
	local names = {}
	local at = self
	while at do
		table.insert(names, 1, tostring(at.Name))
		at = at.Parent
	end
	return table.concat(names, ".")
end
function O.ClearAllChildren(self: any)
	for _, child in table.clone(rawget(self, "children")) do
		child:Destroy()
	end
end
function O.Destroy(self: any)
	if rawget(self, "destroyed") then
		return
	end
	rawset(self, "destroyed", true)
	local destroying = rawget(self, "props").Destroying
	if destroying then
		destroying:Fire()
	end
	for _, child in table.clone(rawget(self, "children")) do
		child:Destroy()
	end
	self.Parent = nil
end
function O.SetAttribute(self: any, k: string, v: any)
	local attrs = rawget(self, "attributes")
	local old = attrs[k]
	attrs[k] = v
	if old ~= v then
		local signals = rawget(self, "asignals")
		local one = signals and signals[k]
		if one then
			one:Fire()
		end
		local any = rawget(self, "props").AttributeChanged
		if any then
			any:Fire(k)
		end
	end
end
function O.GetAttributeChangedSignal(self: any, k: string): any
	local signals = rawget(self, "asignals")
	if not signals then
		signals = {}
		rawset(self, "asignals", signals)
	end
	signals[k] = signals[k] or signal()
	return signals[k]
end
function O.GetPropertyChangedSignal(self: any, k: string): any
	local signals = rawget(self, "psignals")
	if not signals then
		signals = {}
		rawset(self, "psignals", signals)
	end
	signals[k] = signals[k] or signal()
	return signals[k]
end
function O.GetPivot(self: any): any
	local props = rawget(self, "props")
	if PARTS[props.ClassName] then
		return props.CFrame
	end
	local primary = props.PrimaryPart
	if primary then
		return primary.CFrame
	end
	if props.WorldPivot then
		return props.WorldPivot
	end
	local any = false
	for _, d in self:GetDescendants() do
		if PARTS[d.ClassName] then
			any = true
			break
		end
	end
	return if any then (self:GetBoundingBox()) else Mock.CFrame.identity
end
-- (the pivot part lands exactly on `target`, the others by a true rotation: no error that grows with every move)
function O.PivotTo(self: any, target: any)
	local props = rawget(self, "props")
	if PARTS[props.ClassName] then
		self.CFrame = target
		return
	end
	local primary = props.PrimaryPart
	local delta = orthonormal(target * orthonormal(self:GetPivot()):Inverse())
	for _, d in self:GetDescendants() do
		if d == primary then
			d.CFrame = target
		elseif PARTS[d.ClassName] then
			d.CFrame = delta * d.CFrame
		end
	end
	if props.WorldPivot then
		props.WorldPivot = delta * props.WorldPivot
	end
end
O.SetPrimaryPartCFrame = O.PivotTo
function O.Clone(self: any): any
	local map: { [any]: any } = {}
	local function copy(node: any): any
		local made = create(classOf(node))
		map[node] = made
		local into = rawget(made, "props")
		for k, v in rawget(node, "props") do
			if k ~= "Parent" and getmetatable(v) ~= SignalMT then
				into[k] = v
			end
		end
		rawset(made, "attributes", table.clone(rawget(node, "attributes")))
		for _, child in rawget(node, "children") do
			copy(child).Parent = made
		end
		return made
	end
	local root = copy(self)
	for _, made in map do
		local props = rawget(made, "props")
		for k, v in props do
			if map[v] then
				props[k] = map[v] -- (PrimaryPart, Part0 / Part1, Adornee: the copies')
			end
		end
	end
	return root
end
function O.SetNetworkOwner(self: any, owner: any)
	rawget(self, "props").NetworkOwner = if owner == nil then false else owner
end
function O.GetNetworkOwner(self: any): any
	local owner = rawget(self, "props").NetworkOwner
	return if owner == false then nil else owner
end
function O.SetNetworkOwnershipAuto() end
function O.CanSetNetworkOwnership(): boolean
	return true
end
function O.ApplyImpulse() end
function O.ApplyAngularImpulse() end
function O.BreakJoints() end
function O.MakeJoints() end
function O.GetMass(): number
	return 1
end
function O.GetConnectedParts(): { any }
	return {}
end
function O.GetTouchingParts(): { any }
	return {}
end
function O.RequestStreamAroundAsync() end
function O.GetNetworkPing(): number
	return E.ping -- (s: a player's round trip, Moving's grip lag cap)
end
function O.Kick(self: any, why: string?)
	rawget(self, "props").Kicked = why or true
end
function O.LoadAnimation(): any
	return { Play = function() end, Stop = function() end, AdjustSpeed = function() end, AdjustWeight = function() end, Looped = false, IsPlaying = false, Stopped = signal() }
end
function O.MoveTo(self: any, at: any)
	rawget(self, "props").MoveToTarget = at
end
function O.ChangeState(self: any, state: any)
	rawget(self, "props").State = state
end
function O.GetState(self: any): any
	return rawget(self, "props").State or "Running"
end
function O.TakeDamage(self: any, amount: number)
	self.Health = math.max(0, (self.Health or 0) - amount)
end
function O.GetPlayingAnimationTracks(): { any }
	return {}
end
function O.AddTag(self: any, tag: string)
	E.tags[tag] = E.tags[tag] or setmetatable({}, { __mode = "k" })
	E.tags[tag][self] = true
end
function O.RemoveTag(self: any, tag: string)
	if E.tags[tag] then
		E.tags[tag][self] = nil
	end
end
function O.HasTag(self: any, tag: string): boolean
	return E.tags[tag] ~= nil and E.tags[tag][self] == true
end
function O.GetTags(self: any): { string }
	local out = {}
	for tag, set in E.tags do
		if set[self] then
			table.insert(out, tag)
		end
	end
	return out
end
-- RemoteEvent / BindableEvent
function O.FireClient(self: any, player: any, ...: any)
	table.insert(E.sent, { remote = self.Name, player = player, args = table.pack(...) })
	local client = E.clients[player]
	if client then
		local ok, err = pcall(client, self.Name, ...)
		if not ok then
			report(`the test's client: {err}`)
		end
	end
end
function O.FireAllClients(self: any, ...: any)
	for _, player in E.Players:GetPlayers() do
		self:FireClient(player, ...)
	end
end
function O.Fire(self: any, ...: any)
	self.Event:Fire(...)
end

-- ── Welds: a piece welded to a moving body goes with it ───────────────────

-- A weld whose Part0 is a character's root or a van's chassis (the attribute E2EMover): its Part1 kept where it was
-- welded to it (the furniture's own welds inside a piece are left alone: its model moves whole).
trackWeld = function(weld: any)
	local p0, p1 = weld.Part0, weld.Part1
	if p0 and p1 and p0:GetAttribute("E2EMover") then
		table.insert(E.welds, { weld = weld, offset = orthonormal(orthonormal(p0.CFrame):Inverse() * p1.CFrame) })
	end
end

function E.settleWelds()
	local list = E.welds
	for index = #list, 1, -1 do
		local entry = list[index]
		local weld = entry.weld
		local p0, p1 = weld.Part0, weld.Part1
		if rawget(weld, "destroyed") or weld.Parent == nil or not p0 or not p1 then
			table.remove(list, index)
			continue
		end
		local want = orthonormal(p0.CFrame * entry.offset)
		local have = p1.CFrame
		local moved = (want.Position - have.Position).Magnitude > 1e-4
		if not moved then
			for i = 1, 9 do
				if math.abs(want.R[i] - have.R[i]) > 1e-6 then
					moved = true
					break
				end
			end
		end
		if moved then
			local model = p1.Parent
			if model and model.ClassName == "Model" and model.PrimaryPart == p1 then
				model:PivotTo(want)
			else
				p1.CFrame = want
			end
		end
	end
end

-- ── The data model and the services ───────────────────────────────────────

local function service(class: string, name: string?): any
	local s = Instance.new(class)
	s.Name = name or class
	return s
end

local game = service("DataModel", "Game")
game.JobId = "e2e-server"
game.PlaceId = 0
game.PlaceVersion = 82
game.CreatorId = 0
E.game = game

local workspace = service("Workspace")
workspace.Parent = game
local terrain = service("Terrain")
terrain.Parent = workspace
workspace.Terrain = terrain
workspace.Gravity = 196.2
workspace.StreamingEnabled = true
E.workspace = workspace
local ground = Instance.new("Part") -- (what the rays hit outside: the meadow)
ground.Name = "E2EGround"
E.ground = ground

local Players = service("Players")
Players.Parent = game
Players.MaxPlayers = Config.Sandbox.MaxPlayers
Players.GetPlayers = function(self: any): { any }
	local out = {}
	for _, child in rawget(self, "children") do
		if child.ClassName == "Player" then
			table.insert(out, child)
		end
	end
	return out
end
Players.GetPlayerByUserId = function(self: any, id: number): any
	for _, player in self:GetPlayers() do
		if player.UserId == id then
			return player
		end
	end
	return nil
end
Players.GetPlayerFromCharacter = function(self: any, character: any): any
	for _, player in self:GetPlayers() do
		if character ~= nil and player.Character == character then
			return player
		end
	end
	return nil
end
E.Players = Players

local ReplicatedStorage = service("ReplicatedStorage")
ReplicatedStorage.Parent = game
E.ReplicatedStorage = ReplicatedStorage

local RunService = service("RunService")
RunService.IsServer = function(): boolean
	return true
end
RunService.IsClient = function(): boolean
	return false
end
RunService.IsStudio = function(): boolean
	return E.studio == true
end
RunService.IsRunning = function(): boolean
	return true
end
RunService.IsRunMode = function(): boolean
	return false
end

local CollectionService = service("CollectionService")
CollectionService.AddTag = function(_: any, obj: any, tag: string)
	O.AddTag(obj, tag)
end
CollectionService.RemoveTag = function(_: any, obj: any, tag: string)
	O.RemoveTag(obj, tag)
end
CollectionService.HasTag = function(_: any, obj: any, tag: string): boolean
	return O.HasTag(obj, tag)
end
CollectionService.GetTags = function(_: any, obj: any): { string }
	return O.GetTags(obj)
end
CollectionService.GetTagged = function(_: any, tag: string): { any }
	local out = {}
	for obj in E.tags[tag] or {} do
		if not rawget(obj, "destroyed") then
			table.insert(out, obj)
		end
	end
	return out
end
CollectionService.GetInstanceAddedSignal = function(): any
	return signal()
end
CollectionService.GetInstanceRemovedSignal = function(): any
	return signal()
end

-- One DataStore that keeps what JSON would (tests/runtime/CollectionRuntime.luau's): a copy; a value a DataStore cannot
-- hold is an error. Every call yields E.storeLatency s (in a thread), as the real one does.
local function stored(value: any, path: string): any
	local kind = type(value)
	if kind == "nil" or kind == "boolean" or kind == "string" then
		return value
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error(`a DataStore cannot keep {value} at {path}`)
		end
		return value
	elseif kind ~= "table" or getmetatable(value) ~= nil then
		error(`a DataStore cannot keep a {kind} at {path}`)
	end
	local count, strings = 0, 0
	for key in value do
		count += 1
		if type(key) == "string" then
			strings += 1
		end
	end
	local out = {}
	if strings == count then
		for key, item in value do
			out[key] = stored(item, `{path}.{key}`)
		end
	elseif strings == 0 and #value == count then
		for index, item in value do
			out[index] = stored(item, `{path}[{index}]`)
		end
	else
		error(`a DataStore cannot keep the mixed or sparse table at {path}`)
	end
	return out
end
E.stored = stored
local dataStore: any = {}
local function latency()
	if coroutine.isyieldable() and E.storeLatency > 0 then
		task.wait(E.storeLatency)
	end
end
function dataStore.UpdateAsync(_self: any, key: string, transform: (any, any) -> any): any
	latency()
	local old = E.saves[key]
	local new = transform(if old ~= nil then stored(old, key) else nil, nil)
	if new ~= nil then
		E.saves[key] = stored(new, key)
		E.writes += 1
	end
	return new
end
function dataStore.GetAsync(_self: any, key: string): any
	latency()
	local value = E.saves[key]
	return if value ~= nil then stored(value, key) else nil
end
function dataStore.SetAsync(_self: any, key: string, value: any)
	latency()
	E.saves[key] = stored(value, key)
	E.writes += 1
end
function dataStore.RemoveAsync(_self: any, key: string)
	E.saves[key] = nil
end
local DataStoreService = service("DataStoreService")
DataStoreService.GetDataStore = function(_: any, name: string): any
	E.storeName = name
	return dataStore
end
-- An OrderedDataStore per name (E.ordered[name][key]: whole numbers only, as Roblox's), its calls yielding as above.
E.ordered = {}
DataStoreService.GetOrderedDataStore = function(_: any, name: string): any
	local values = E.ordered[name] or {}
	E.ordered[name] = values
	local function keep(key: string, value: any)
		if value ~= nil and (type(value) ~= "number" or value ~= math.floor(value) or value ~= value) then
			error(`an OrderedDataStore keeps only whole numbers ({key}: {tostring(value)})`)
		end
		values[key] = value
	end
	return {
		GetAsync = function(_: any, key: string): any
			latency()
			return values[key]
		end,
		SetAsync = function(_: any, key: string, value: any)
			latency()
			keep(key, value)
		end,
		UpdateAsync = function(_: any, key: string, transform: (any, any) -> any): any
			latency()
			local new = transform(values[key], nil)
			if new ~= nil then
				keep(key, new)
			end
			return values[key]
		end,
		GetSortedAsync = function(_: any, ascending: boolean, size: number): any
			latency()
			local rows = {}
			for key, value in values do
				table.insert(rows, { key = key, value = value })
			end
			table.sort(rows, function(a, b)
				return if ascending then a.value < b.value else a.value > b.value
			end)
			return { GetCurrentPage = function()
				return { table.unpack(rows, 1, math.min(#rows, size or 100)) }
			end, IsFinished = true }
		end,
	}
end
DataStoreService.GetRequestBudgetForRequestType = function(): number
	return 100
end

local PhysicsService = service("PhysicsService")
local groups: { [string]: boolean } = { Default = true }
PhysicsService.RegisterCollisionGroup = function(_: any, name: string)
	groups[name] = true
end
PhysicsService.IsCollisionGroupRegistered = function(_: any, name: string): boolean
	return groups[name] == true
end
PhysicsService.CollisionGroupSetCollidable = function() end
PhysicsService.CollisionGroupsAreCollidable = function(): boolean
	return true
end
PhysicsService.GetRegisteredCollisionGroups = function(): { any }
	local out = {}
	for name in groups do
		table.insert(out, { name = name })
	end
	return out
end

local PathfindingService = service("PathfindingService")
PathfindingService.CreatePath = function(): any
	local path: any = { Status = "NoPath", Blocked = signal() }
	function path.ComputeAsync(self: any)
		self.Status = "NoPath"
	end
	function path.GetWaypoints(): { any }
		return {}
	end
	function path.Destroy() end
	return path
end

local TweenService = service("TweenService")
TweenService.Create = function(_: any, obj: any, _info: any, goal: any): any
	return {
		Play = function()
			for k, v in goal or {} do
				obj[k] = v -- (at once: no tweening here)
			end
		end,
		Cancel = function() end,
		Pause = function() end,
		Completed = signal(),
	}
end
local Debris = service("Debris")
Debris.AddItem = function(_: any, obj: any, seconds: number?)
	task.delay(seconds or 10, function()
		obj:Destroy()
	end)
end
local HttpService = service("HttpService")
local guid = 0
HttpService.GenerateGUID = function(): string
	guid += 1
	return `e2e-{guid}`
end
HttpService.JSONEncode = function(): string
	return "{}"
end
HttpService.JSONDecode = function(): any
	return {}
end
local MessagingService = service("MessagingService")
MessagingService.PublishAsync = function() end
MessagingService.SubscribeAsync = function(): any
	return { Disconnect = function() end }
end
-- AnalyticsService (Roblox's): every call recorded in E.analytics ({ method, args }), the real server/Analytics.luau's.
E.analytics = {}
local AnalyticsService = service("AnalyticsService")
for _, method in { "LogCustomEvent", "LogOnboardingFunnelStepEvent", "LogFunnelStepEvent", "LogEconomyEvent", "LogProgressionEvent" } do
	AnalyticsService[method] = function(_: any, ...: any)
		table.insert(E.analytics, { method = method, args = table.pack(...) })
	end
end
local TextService = service("TextService")
TextService.GetTextSize = function(_: any, text: string, size: number): any
	return Mock.Vector2.new(#tostring(text) * size * 0.6, size)
end

local services: { [string]: any } = {
	Workspace = workspace,
	Players = Players,
	ReplicatedStorage = ReplicatedStorage,
	RunService = RunService,
	CollectionService = CollectionService,
	DataStoreService = DataStoreService,
	PhysicsService = PhysicsService,
	PathfindingService = PathfindingService,
	TweenService = TweenService,
	Debris = Debris,
	HttpService = HttpService,
	MessagingService = MessagingService,
	TextService = TextService,
	AnalyticsService = AnalyticsService,
}
for _, name in { "ServerStorage", "ServerScriptService", "Lighting", "StarterPlayer", "StarterGui", "StarterPack", "Teams", "SoundService", "ProximityPromptService", "ScriptContext", "MarketplaceService", "BadgeService", "TeleportService", "GroupService", "LocalizationService", "Chat", "TextChatService", "PolicyService", "SocialService", "UserInputService", "ContextActionService", "GuiService" } do
	local s = service(name)
	s.Parent = game
	services[name] = s
end
E.services = services
game.GetService = function(_: any, name: string): any
	local found = services[name]
	if not found then
		E.unknownServices[name] = true
		found = service(name)
		services[name] = found
	end
	return found
end
game.FindService = function(_: any, name: string): any
	return services[name]
end
game.BindToClose = function(_: any, fn: any)
	E.onClose = fn
end
game.IsLoaded = function(): boolean
	return true
end

-- The world's rays: down onto an interior's floor (within 400 studs of a house's slot: its origin's height), else the
-- road (SandboxMap.Roads, RoadTop) or the meadow (GroundTop); sideways and up: nothing.
local interiorOrigins: { any }? = nil
local function originsOf(): { any }
	if not interiorOrigins then
		local made = {}
		local ok, interior = pcall(function()
			return E.require(E.server.HouseInterior)
		end)
		if ok and interior then
			for index = 1, Config.Moving.Slots do
				table.insert(made, interior.slot(index))
			end
		end
		interiorOrigins = made
	end
	return interiorOrigins :: { any }
end
E.interiorOrigins = originsOf
function E.groundY(x: number, z: number): number
	for _, road in SandboxMapReal.Roads do
		if x >= road.x0 and x <= road.x1 and z >= road.z0 and z <= road.z1 then
			return SandboxMapReal.RoadTop
		end
	end
	return SandboxMapReal.GroundTop
end
function E.interiorAt(at: any): any
	for _, origin in originsOf() do
		if (at - origin.Position).Magnitude < 400 then
			return origin
		end
	end
	return nil
end
workspace.Raycast = function(_: any, origin: any, direction: any, _params: any): any
	if direction.Y >= 0 then
		return nil
	end
	local inside = E.interiorAt(origin)
	local floor = if inside then inside.Position.Y else E.groundY(origin.X, origin.Z)
	if origin.Y < floor - 1e-6 or origin.Y + direction.Y > floor then
		return nil
	end
	return { Position = V3(origin.X, floor, origin.Z), Normal = V3(0, 1, 0), Material = "Plastic", Instance = ground, Distance = origin.Y - floor }
end
workspace.Blockcast = function(): any
	return nil
end
workspace.Spherecast = function(): any
	return nil
end
workspace.Shapecast = function(): any
	return nil
end
workspace.GetServerTimeNow = function(): number
	return E.now
end
-- The parts of the include list whose middle is within the box (in the box's own frame).
workspace.GetPartBoundsInBox = function(_: any, box: any, size: any, params: any): { any }
	local found = {}
	if params and params.FilterType == "Include" then
		for _, model in params.FilterDescendantsInstances or {} do
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					local d = box:PointToObjectSpace(part.CFrame.Position)
					if math.abs(d.X) <= size.X / 2 and math.abs(d.Y) <= size.Y / 2 and math.abs(d.Z) <= size.Z / 2 then
						table.insert(found, part)
					end
				end
			end
		end
	end
	return found
end
workspace.GetPartBoundsInRadius = function(): { any }
	return {}
end
workspace.GetPartsInPart = function(): { any }
	return {}
end

-- ── The modules: Shared, the server folder, require ───────────────────────

local TokenMethods = {}
function TokenMethods.IsA(_self: any, cls: string): boolean
	return cls == "ModuleScript" or cls == "LuaSourceContainer" or cls == "Instance"
end
function TokenMethods.GetAttribute(): any
	return nil
end
function TokenMethods.FindFirstChild(): any
	return nil
end
function TokenMethods.GetChildren(): { any }
	return {}
end
TokenMethods.GetDescendants = TokenMethods.GetChildren
local TokenMT = { __index = TokenMethods }
local function token(kind: string, name: string): any
	return setmetatable({ __e2e = kind, Name = name, ClassName = "ModuleScript" }, TokenMT)
end

-- E.real: the server modules staged as E2E<Name>.luau (tests/run_tests.py stages these); E.fakes: the stand-ins.
E.real = {
	PlayerData = true, Collection = true, Warehouse = true, SandboxPlots = true, Upgrades = true, Moving = true, MoveLobby = true,
	MoveHelper = true, MoveGreeters = true, PairHold = true, MoveSites = true, SandboxBoot = true, SandboxWorld = true,
	HouseMesh = true, HouseInterior = true, FurnitureMesh = true, Analytics = true, SandboxAnalytics = true, CollectionBook = true,
	SandboxTasks = true, SandboxLeaders = true, WarehouseMesh = true, VanPaint = true,
	Visitors = true, VisitorOffers = true, -- 8.3: the showroom's visitors (tests/visitors_runtime_test.luau; off in the e2e)
	SandboxBadges = true, -- 8.3: the Roblox badges (every id 0 here: it listens and counts the moves, it never calls BadgeService)
	PlayerTrade = true, -- 8.7: trading between players (the stands' trade prompts: Warehouse.onTrade)
	VillageWorld = true, -- 8.9: Jinočany's village on the map (SandboxWorld builds it)
	FixtureMesh = true, -- 8.9.1: the houses' fixtures in the owner's Blender model (no import here: the parts' look)
	SaveSlots = true, -- 10.1: the save slots (E.join picks slot 1 on the start screen: CONTINUE)
	LobbyWorld = true, Runs = true, -- 9.7: the lobby (SandboxWorld builds it) and the runs (the portals' pads, the parties)
	Loot = true, -- 9.x loot: every piece of the house gets its rarity, stars and value (Moving's hook)
	RunDanger = true, -- 10.x danger: a run's locks and keys, its vault, its hazards (Runs starts it; Zombies is the fake's)
	HelperCrew = true, -- 10.1 the helpers' crew (MoveHelper's hooks, the lobby's stands, the Crew remote)
}
E.fakes = {}

local function folderOf(kind: string, name: string, has: (string) -> boolean): any
	local tokens: { [string]: any } = {}
	local function get(child: string): any
		if not has(child) then
			return nil
		end
		tokens[child] = tokens[child] or token(kind, child)
		return tokens[child]
	end
	local methods = {
		FindFirstChild = function(_: any, child: string): any
			return get(child)
		end,
		WaitForChild = function(_: any, child: string): any
			return get(child)
		end,
		GetChildren = function(): { any }
			return {}
		end,
		GetDescendants = function(): { any }
			return {}
		end,
		IsA = function(_: any, cls: string): boolean
			return cls == "Folder" or cls == "Instance"
		end,
		IsDescendantOf = function(): boolean
			return false
		end,
		GetAttribute = function(): any
			return nil
		end,
	}
	return setmetatable({ Name = name, ClassName = "Folder", __e2eFolder = kind, children = {}, props = {} }, {
		__index = function(_: any, k: string): any
			local method = methods[k]
			if method then
				return method
			elseif k == "Parent" then
				return nil
			end
			local found = get(k)
			if found then
				return found
			end
			error(`SandboxE2E: no {kind} module {k} (a real one: E.real and run_tests.py; else a fake in E.fakes)`, 2)
		end,
	})
end
local shared = folderOf("shared", "Shared", function(): boolean
	return true
end)
table.insert(rawget(ReplicatedStorage, "children"), shared) -- (ReplicatedStorage:WaitForChild("Shared"))
local server = folderOf("server", "Server", function(name: string): boolean
	return E.real[name] == true or E.fakes[name] ~= nil
end)
E.server = server
E.shared = shared
local script: any = setmetatable({ Name = "Module", ClassName = "ModuleScript", Parent = server }, { __index = TokenMethods })
E.script = script

-- shared/SandboxMap.luau's numbers with SandboxMap.cframe on this CFrame (the pure copy has no Roblox CFrame).
E.SandboxMap = setmetatable({
	cframe = function(spot: any): any
		return Mock.CFrame.new(spot.x, spot.y, spot.z) * Mock.CFrame.Angles(0, math.rad(spot.yaw), 0)
	end,
}, { __index = SandboxMapReal })

function E.require(target: any): any
	if type(target) == "table" and rawget(target, "__e2e") then
		local name = rawget(target, "Name")
		if rawget(target, "__e2e") == "shared" then
			if name == "Net" then
				return require("./E2ENet")
			elseif name == "SandboxMap" then
				return E.SandboxMap
			end
			return require("./" .. name)
		end
		local fake = E.fakes[name]
		if fake ~= nil then
			return fake
		end
		return require("./E2E" .. name)
	end
	error(`SandboxE2E: require of {tostring(target)} (not a module of this game)`, 2)
end

-- A real server module by name (the same one the game's modules get).
function E.module(name: string): any
	return E.require(server[name])
end

-- ── The fakes: the Roblox-heavy server modules ────────────────────────────

local function noop() end
local function stub(name: string, fields: { [string]: any }): any
	return setmetatable(fields, { __index = function(_, key)
		error(`SandboxE2E: unmocked {name}.{tostring(key)}`, 2)
	end })
end
for _, name in { "CarRighting", "Admin", "Transport", "KitWear", "Horn", "SprinterMesh", "Clipboard" } do -- (8.5: Danny's clipboard, its own test)
	E.fakes[name] = stub(name, { start = noop })
end
E.fakes.CourierAvatar = stub("CourierAvatar", { start = noop, setLook = noop }) -- (10.1: SaveSlots puts the slot's courier on)
E.fakes.DayNight = stub("DayNight", { nightLight = noop, start = noop, isNight = function()
	return false
end })
E.fakes.Hand = stub("Hand", { holster = noop, start = noop })
E.fakes.Crew = stub("Crew", {
	members = function(): { any }
		return {}
	end,
	ownerOf = function(): any
		return nil
	end,
	hasJob = function(): boolean
		return false
	end,
	start = noop,
})
E.zombies = {}
E.fakes.Zombies = stub("Zombies", {
	ambient = true,
	start = noop,
	hunts = function(): boolean
		return false
	end,
	onCarDamaged = noop,
	findSpot = function(center: any): any
		return center
	end,
	pickKind = function(): string
		return "walker"
	end,
	spawn = function(kind: string, at: any): any
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.CFrame = Mock.CFrame.new(at.X, at.Y, at.Z)
		root.Parent = model
		model.Parent = workspace
		local z = { kind = kind, at = at, dead = false, model = model, root = root }
		table.insert(E.zombies, z)
		return z
	end,
	march = noop,
	damage = function(): boolean
		return false
	end,
	noise = noop,
	all = function(): { any }
		return E.zombies
	end,
	extraTargets = function(): { any }
		return {}
	end,
	releaseCar = noop,
	clearOwner = noop,
})
-- Npcs: a body (a root and a humanoid in workspace.Npcs) where it is put; what it says (E.said).
E.said = {}
E.fakes.Npcs = stub("Npcs", {
	start = noop,
	look = function(role: string, name: string, title: string?): any
		return { role = role, name = name, title = title }
	end,
	spawn = function(look: any, at: any): any
		local folder = workspace:FindFirstChild("Npcs")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Npcs"
			folder.Parent = workspace
		end
		local position = if getmetatable(at) == F then at.Position else at
		local model = Instance.new("Model")
		model.Name = look.name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = V3(2, 2, 1)
		root.CFrame = Mock.CFrame.new(position.X, position.Y + 3, position.Z)
		root.Parent = model
		model.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		humanoid.Name = "Humanoid"
		humanoid.MaxHealth = 1e6
		humanoid.Health = 1e6
		humanoid.RootPart = root
		humanoid.Parent = model
		model.Parent = folder
		return model
	end,
	say = function(_npc: any, text: string)
		table.insert(E.said, text)
	end,
	act = noop,
	glance = noop,
	face = noop, -- (8.3: a visitor turns to the piece it looks at)
	remove = function(npc: any)
		npc:Destroy()
	end,
	stop = noop,
	pace = noop,
	walkTo = noop,
	stride = noop,
	carried = noop,
})
-- Danny's walk (server/MoveHelper.luau useMover): a straight step of speed × dt toward his goal (no pathfinding here).
E.mover = {
	move = function(body: any, to: any, speed: number, dt: number)
		local root = body.root
		local here = root.Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		local length = way.Magnitude
		if length > 1e-6 then
			local stride = math.min(length, speed * dt)
			root.CFrame = Mock.CFrame.new(here.X + way.X / length * stride, here.Y, here.Z + way.Z / length * stride)
		end
		body.walking = true
	end,
	halt = function(body: any)
		body.walking = false
	end,
}

-- ── The fake Vehicles: a Sprinter with the real numbers ───────────────────

local CHASSIS_HEIGHT = 1.2 -- (server/Vehicles.luau's)
local S = Config.Sprinter
local cars: { [any]: any } = {}
E.cars = cars
E.vehicleCalls = {} -- { name, player, … } what the game asked of Vehicles
local Vehicles: any = {}
E.fakes.Vehicles = Vehicles

local function carsFolder(): any
	local folder = workspace:FindFirstChild("Cars")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Cars"
		folder.Parent = workspace
	end
	return folder
end

local function rootOf(player: any): any
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end
E.rootOf = rootOf
local function humanoidOf(player: any): any
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end
E.humanoidOf = humanoidOf

-- The BackPrompt pressed (server/Vehicles.luau toggleBack's rules): on foot, the owner or the crew (backAllowed), a
-- hand free (nothing carried, or one light piece: CarryHands 1), the van standing.
local notice: any = nil
local function say(player: any, text: string)
	notice = notice or E.require(shared.Net).get("Notice")
	notice:FireClient(player, text)
end
local function toggleBack(car: any, player: any)
	local character = player.Character
	local humanoid = humanoidOf(player)
	if car.wrecked or not character or not humanoid or humanoid.Health <= 0 then
		return
	end
	if humanoid.SeatPart then
		say(player, "Get out first.")
		return
	end
	if player ~= car.owner and not Vehicles.backAllowed(player, car) then
		say(player, "This is not your car.")
		return
	end
	local open = Vehicles.backOpen(car)
	if character:GetAttribute("Carrying") ~= nil and character:GetAttribute("CarryHands") ~= 1 then
		say(player, `Your hands are full. Put it down (G), then {Vehicles.backVerb(car, not open)} (E).`)
		return
	end
	if Vehicles.speed(car) > Config.Cargo.MaxCarSpeed then
		say(player, "Stop the vehicle first.")
		return
	end
	Vehicles.setBack(car, not open)
end

-- A player's Sprinter, its chassis' middle at `frame` (CHASSIS_HEIGHT / 2 + the clearance over the ground).
local function build(player: any, carId: string, frame: any): any
	local def = Economy.findCar(carId)
	local model = Instance.new("Model")
	model.Name = `{player.Name}'s {if def then def.name else carId}`
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = V3(S.Width, CHASSIS_HEIGHT, SprinterLooks.Length)
	chassis.CFrame = frame
	chassis:SetAttribute("E2EMover", true)
	chassis.Parent = model
	model.PrimaryPart = chassis
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriveSeat"
	seat.Size = V3(2, 1, 2)
	seat.CFrame = frame * Mock.CFrame.new(SprinterLooks.Seat[1], CHASSIS_HEIGHT / 2 + SprinterLooks.Seat[2] - SprinterLooks.Top, SprinterLooks.Seat[3])
	seat.Parent = model
	local door = Instance.new("Attachment")
	door.Name = "CargoDoor"
	door.Position = V3(0, CHASSIS_HEIGHT / 2 + SprinterLooks.CargoDoor[2] - SprinterLooks.Top, SprinterLooks.CargoDoor[3])
	door.Parent = chassis
	local back = Instance.new("ProximityPrompt")
	back.Name = "BackPrompt"
	back.ActionText = "Open doors"
	back.ObjectText = if def then def.name else carId
	back.HoldDuration = Config.Cargo.HoldDuration
	back.MaxActivationDistance = 9
	back.RequiresLineOfSight = false
	back.Parent = door
	model:SetAttribute("BackOpen", false)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("CarId", carId)
	model:SetAttribute("SpeedMult", 1) -- (Vehicles' spawn: before it is parented; server/Upgrades.luau tunes it)
	local car = { owner = player, id = carId, model = model, chassis = chassis, seat = seat, wrecked = false, lent = false, rental = false, health = 1, speed = 0, passengers = {} }
	back.Triggered:Connect(function(by: any)
		toggleBack(car, by)
	end)
	model.Parent = carsFolder()
	return car
end

function Vehicles.start()
	Players.PlayerRemoving:Connect(function(player: any)
		Vehicles.remove(player) -- (the real one's: a leaving player's car goes)
	end)
end
Vehicles.onWrecked = function() end
Vehicles.onSpawned = function() end
Vehicles.backAllowed = function(): boolean
	return false
end
Vehicles.backChanged = function() end
Vehicles.callCar = nil
Vehicles.homeGarage = function(): any
	return nil
end
function Vehicles.get(player: any): any
	local car = cars[player]
	return if car and not car.wrecked then car else nil
end
function Vehicles.all(): { any }
	local list = {}
	for _, car in cars do
		if not car.wrecked then
			table.insert(list, car)
		end
	end
	return list
end
function Vehicles.remove(player: any)
	local old = cars[player]
	if old then
		cars[player] = nil
		old.model:Destroy()
	end
end
function Vehicles.driveOut(_player: any, _carId: string?): (number, number)
	local length = SprinterLooks.Length
	return if length > 17 then length / 2 - (Map.GarageApron - 1) else 0, length
end
function Vehicles.groundY(x: number, z: number, _refY: number?): number
	return E.groundY(x, z)
end
-- Vehicles.placeAt: the van stands Vehicles.driveOut studs out along the spot's look (a garage's way); its chassis on the
-- ground there (the real one: groundY + its clearance), seated or not.
function Vehicles.placeAt(player: any, carId: string?, spot: any, seat: boolean?): any
	table.insert(E.vehicleCalls, { name = "placeAt", player = player, carId = carId, spot = spot, seat = seat })
	local look = V3(spot.LookVector.X, 0, spot.LookVector.Z)
	look = if look.Magnitude > 0.01 then look.Unit else V3(0, 0, 1)
	local out = Vehicles.driveOut(player, carId)
	Vehicles.remove(player)
	local at = spot.Position + look * out
	local y = E.groundY(at.X, at.Z) + S.Clearance + CHASSIS_HEIGHT / 2
	local position = V3(at.X, y, at.Z)
	local id = carId or "sprinter"
	local car = build(player, id, Mock.CFrame.lookAt(position, position + look))
	cars[player] = car
	if seat then
		E.seat(player, car)
	end
	return car
end
function Vehicles.spawnAt(player: any, carId: string?, ground: any, seat: boolean): any
	table.insert(E.vehicleCalls, { name = "spawnAt", player = player, carId = carId })
	Vehicles.remove(player)
	local position = ground.Position + V3(0, S.Clearance + CHASSIS_HEIGHT / 2, 0)
	local car = build(player, carId or "sprinter", Mock.CFrame.lookAt(position, position + ground.LookVector))
	cars[player] = car
	if seat then
		E.seat(player, car)
	end
	return car
end
function Vehicles.placeNear(player: any, carId: string?): string?
	table.insert(E.vehicleCalls, { name = "placeNear", player = player, carId = carId })
	local root = rootOf(player)
	local at = if root then root.CFrame else Mock.CFrame.identity
	Vehicles.spawnAt(player, carId, at, true)
	return nil
end
function Vehicles.spawn(player: any, force: boolean?, carId: string?): string?
	table.insert(E.vehicleCalls, { name = "spawn", player = player, carId = carId })
	local call = Vehicles.callCar
	if not force and call then
		return call(player, carId)
	end
	return Vehicles.placeNear(player, carId)
end
function Vehicles.repair(car: any, share: number)
	car.health = share
end
function Vehicles.damage(car: any, amount: number): number
	car.health = math.max(0, car.health - amount / 1000)
	return amount
end
function Vehicles.cooldown(): string?
	return nil
end
function Vehicles.clearFor(_car: any, ground: any): any
	return ground
end
function Vehicles.isBike(): boolean
	return false
end
function Vehicles.cargoDoor(car: any): any
	local door = car.chassis:FindFirstChild("CargoDoor")
	return if door and door:IsA("Attachment") then door else nil
end
function Vehicles.backPrompt(car: any): any
	local door = Vehicles.cargoDoor(car)
	local prompt = door and door:FindFirstChild("BackPrompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end
function Vehicles.hasBack(car: any): boolean
	return not car.wrecked and Vehicles.backPrompt(car) ~= nil
end
function Vehicles.backOpen(car: any): boolean
	return car.model:GetAttribute("BackOpen") == true
end
function Vehicles.backNoun(): string
	return "doors"
end
function Vehicles.backVerb(_car: any, opening: boolean): string
	return if opening then "open the back doors" else "close the back doors"
end
function Vehicles.setBack(car: any, open: boolean)
	if not Vehicles.hasBack(car) or Vehicles.backOpen(car) == open then
		return
	end
	car.model:SetAttribute("BackOpen", open)
	local prompt = Vehicles.backPrompt(car)
	if prompt then
		prompt.ActionText = if open then "Close doors" else "Open doors"
	end
	Vehicles.backChanged(car)
end
function Vehicles.speed(car: any): number
	return car.speed or 0
end
-- The Sprinter's slots (Vehicles' STYLES.sprinter cargo), from the chassis' middle: its floor CHASSIS_HEIGHT / 2 up.
local SLOTS = { { -1.6, -1.2 }, { 1.6, -1.2 }, { -1.6, 2.2 }, { 1.6, 2.2 }, { -1.6, 5.6 }, { 1.6, 5.6 }, { -1.6, 9.0 }, { 1.6, 9.0 } }
function Vehicles.cargoSlots(_car: any): { any }
	local list = {}
	for _, slot in SLOTS do
		table.insert(list, Mock.CFrame.new(slot[1], CHASSIS_HEIGHT / 2, slot[2]))
	end
	return list
end
function Vehicles.cargoHolder(car: any): any
	return car.chassis
end
function Vehicles.bodyPart(car: any): any
	return car.chassis
end
function Vehicles.seatedIn(player: any): (any, boolean, any)
	local humanoid = humanoidOf(player)
	local seat = humanoid and humanoid.SeatPart
	if not seat then
		return nil, false, nil
	end
	for _, car in cars do
		if not car.wrecked and seat:IsDescendantOf(car.model) then
			return car, seat == car.seat, seat
		end
	end
	return nil, false, nil
end
function Vehicles.isDriving(player: any): boolean
	local car, driving = Vehicles.seatedIn(player)
	return car ~= nil and driving
end
function Vehicles.standUp() end
function Vehicles.capacity(): number
	return #SLOTS
end

-- ── The players ───────────────────────────────────────────────────────────

function E.player(userId: number, name: string): any
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	player.AccountAge = 365
	player.MembershipType = "None"
	return player
end

-- A new body for the player (Roblox's CharacterAutoLoads): a root and a humanoid at `at` (default: the world's
-- SpawnLocation, the origin), Character set, in the workspace, CharacterAdded.
function E.spawn(player: any, at: any?): any
	local old = player.Character
	if old then
		old:Destroy()
	end
	local position = at or V3(0, 3, 0)
	local character = Instance.new("Model")
	character.Name = player.Name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V3(2, 2, 1)
	root.CFrame = Mock.CFrame.new(position.X, position.Y, position.Z)
	root:SetAttribute("E2EMover", true)
	root.Parent = character
	character.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.RootPart = root
	humanoid.Parent = character
	player.Character = character
	character.Parent = workspace
	player.CharacterAdded:Fire(character)
	return character
end

-- The player joins (PlayerAdded: their save loads, a plot is claimed …), their body comes a moment later.
function E.join(userId: number, name: string): any
	local player = E.player(userId, name)
	player.Parent = Players
	Players.PlayerAdded:Fire(player)
	E.fire(player, "Slots", { kind = "play", slot = 1 }) -- 10.1: the start screen's CONTINUE (slot 1: the save of before)
	E.advance(0.3)
	E.spawn(player)
	E.advance(0.5)
	return player
end

-- The player leaves: PlayerRemoving (while still in the game), then their body and the player go; the leave save runs.
function E.leave(player: any)
	Players.PlayerRemoving:Fire(player)
	E.flush()
	local character = player.Character
	if character then
		character:Destroy()
	end
	player.Parent = nil
	E.advance(1)
end

-- ── The test's hands: remotes, prompts, walking, the van ──────────────────

function E.remote(name: string): any
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild(name)
	assert(remote, `SandboxE2E: no remote {name}`)
	return remote
end

-- A client's request on a remote (OnServerEvent), the deferred work after it.
function E.fire(player: any, name: string, ...: any)
	E.remote(name).OnServerEvent:Fire(player, ...)
	E.flush()
end

-- Every FireClient to `player` on `remote` since index `from` of E.sent: their arguments (packed).
function E.received(player: any, remote: string, from: number?): { any }
	local out = {}
	for index = (from or 0) + 1, #E.sent do
		local sent = E.sent[index]
		if sent.player == player and sent.remote == remote then
			table.insert(out, sent.args)
		end
	end
	return out
end
-- The first arguments of those (a Notice's text, a Collection message's table).
function E.messages(player: any, remote: string, from: number?): { any }
	local out = {}
	for _, args in E.received(player, remote, from) do
		table.insert(out, args[1])
	end
	return out
end
-- The last ("Moving", kind) message's arguments to `player` (the Moving remote's style: kind first), or nil.
function E.lastOf(player: any, remote: string, kind: string, from: number?): any
	local list = E.received(player, remote, from)
	for index = #list, 1, -1 do
		if list[index][1] == kind then
			return list[index]
		end
	end
	return nil
end
-- The last Collection / Upgrades message of `kind` (their style: a table with kind).
function E.lastKind(player: any, remote: string, kind: string, from: number?): any
	local list = E.messages(player, remote, from)
	for index = #list, 1, -1 do
		local m = list[index]
		if type(m) == "table" and m.kind == kind then
			return m
		end
	end
	return nil
end
function E.lastNotice(player: any, from: number?): string
	local list = E.messages(player, "Notice", from)
	return tostring(list[#list] or "")
end
function E.heard(player: any, text: string, from: number?): boolean
	for _, m in E.messages(player, "Notice", from) do
		if string.find(tostring(m), text, 1, true) then
			return true
		end
	end
	return false
end

-- Where a prompt is (its parent's place).
function E.promptAt(prompt: any): any
	local parent = prompt.Parent
	if parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent:IsA("BasePart") then
		return parent.Position
	end
	return parent:GetPivot().Position
end

-- A prompt used by `player` the way Roblox lets one be: it is in the world, enabled, and within its reach of the
-- player's root (anybody's client can fire any prompt in reach; hiding it on a client is no check). A hold advances the
-- clock. → true, or false and why not.
function E.trigger(prompt: any, player: any): (boolean, string?)
	if not prompt or rawget(prompt, "destroyed") or not prompt:IsDescendantOf(workspace) then
		return false, "no such prompt"
	end
	if not prompt.Enabled then
		return false, "disabled"
	end
	local root = rootOf(player)
	if not root then
		return false, "no body"
	end
	local distance = (root.Position - E.promptAt(prompt)).Magnitude
	if distance > prompt.MaxActivationDistance + 0.05 then
		return false, string.format("out of reach (%.1f > %.1f)", distance, prompt.MaxActivationDistance)
	end
	local hold = prompt.HoldDuration or 0
	if hold > 0 then
		E.advance(hold)
	end
	prompt.Triggered:Fire(player)
	E.flush()
	return true, nil
end

-- The first prompt under `model` whose ActionText starts with `action` (and that passes `filter`).
function E.promptIn(model: any, action: string, filter: ((any) -> boolean)?): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not rawget(d, "destroyed") and string.find(tostring(d.ActionText), action, 1, true) == 1 and (filter == nil or filter(d)) then
			return d
		end
	end
	return nil
end

-- Stands the player at `at` (a teleport: only for a test's setup) looking along `look` (flat).
function E.place(player: any, at: any, look: any?)
	local root = rootOf(player)
	local dir = look or root.CFrame.LookVector
	local flat = V3(dir.X, 0, dir.Z)
	flat = if flat.Magnitude > 1e-6 then flat.Unit else V3(0, 0, -1)
	root.CFrame = Mock.CFrame.lookAt(at, at + flat)
	E.settleWelds()
end

-- The player turns to look along `look` (flat).
function E.face(player: any, look: any)
	local root = rootOf(player)
	E.place(player, root.Position, look)
end

-- The speed a player walks now: what they carry's CarrySpeed (the server's walk with it), else the plain walk; × 0.95.
function E.walkSpeed(player: any): number
	local character = player.Character
	local carry = character and character:GetAttribute("CarrySpeed")
	return (if type(carry) == "number" then carry else Config.Movement.Walk) * 0.95
end

-- Walks the player's root to `to` (its height eased there too) in 0.1 s steps at their walk, the clock moving, facing
-- the way they go. Stops early (false) when the game moved the body itself (a door's fade, a respawn).
function E.walk(player: any, to: any, speed: number?): boolean
	local root = rootOf(player)
	local expected = root.Position
	local dt = 0.1
	for _ = 1, 100000 do
		local here = root.Position
		if (here - expected).Magnitude > 0.05 then
			root.AssemblyLinearVelocity = V3(0, 0, 0)
			return false
		end
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		local length = way.Magnitude
		if length < 1e-3 then
			root.AssemblyLinearVelocity = V3(0, 0, 0)
			root.CFrame = Mock.CFrame.lookAt(V3(to.X, to.Y, to.Z), V3(to.X, to.Y, to.Z) + root.CFrame.LookVector)
			E.settleWelds()
			return true
		end
		local stride = math.min(length, (speed or E.walkSpeed(player)) * dt)
		local dir = way / length
		local t = stride / length
		local nextAt = V3(here.X + dir.X * stride, here.Y + (to.Y - here.Y) * t, here.Z + dir.Z * stride)
		root.CFrame = Mock.CFrame.lookAt(nextAt, nextAt + dir)
		root.AssemblyLinearVelocity = dir * (stride / dt) -- (the walk's speed, as Roblox reports it)
		expected = nextAt
		E.settleWelds()
		E.advance(dt)
	end
	return false
end

-- Walks along a list of points (stops as walk does).
function E.walkPath(player: any, points: { any }, speed: number?): boolean
	for _, at in points do
		if not E.walk(player, at, speed) then
			return false
		end
	end
	return true
end

-- Into the van's driver's seat (the Drive prompt's end: SeatPart set, its Seated) and out at the driver's door.
function E.seat(player: any, car: any)
	local humanoid = humanoidOf(player)
	humanoid.SeatPart = car.seat
	car.seat.Occupant = humanoid
	local root = rootOf(player)
	root.CFrame = car.seat.CFrame * Mock.CFrame.new(0, 1.5, 0)
	E.settleWelds()
end
function E.unseat(player: any)
	local humanoid = humanoidOf(player)
	local seat = humanoid.SeatPart
	humanoid.SeatPart = nil
	if seat then
		seat.Occupant = nil
		local out = seat.CFrame * V3(-(S.Width / 2 + 2), 0, 0)
		local y = E.groundY(out.X, out.Z) + 3
		E.place(player, V3(out.X, y, out.Z), seat.CFrame.LookVector)
	end
end

-- Drives the van along `points` ({ x, z, yaw }: its pivot's flat place and the way its nose looks, SandboxMap's yaw)
-- at `speed` studs / s in 0.1 s steps, on the ground (the chassis' clearance over the road or the meadow), its driver
-- and its welded load with it; it stands still at the end.
function E.drive(car: any, points: { any }, speed: number?)
	local v = speed or 40
	local dt = 0.1
	local function frameAt(x: number, z: number, yaw: number): any
		local y = E.groundY(x, z) + S.Clearance + CHASSIS_HEIGHT / 2
		return Mock.CFrame.new(x, y, z) * Mock.CFrame.Angles(0, math.rad(yaw), 0)
	end
	local driver = car.seat.Occupant
	for _, point in points do
		for _ = 1, 100000 do
			local here = car.chassis.Position
			local way = V3(point.x - here.X, 0, point.z - here.Z)
			local length = way.Magnitude
			local stride = math.min(length, v * dt)
			local at = if length > 1e-6 then here + way / length * stride else here
			car.model:PivotTo(frameAt(at.X, at.Z, point.yaw))
			car.speed = if length > 1e-3 then v else 0
			if driver and driver.Parent and driver.RootPart then
				driver.RootPart.CFrame = car.seat.CFrame * Mock.CFrame.new(0, 1.5, 0)
			end
			E.settleWelds()
			E.advance(dt)
			if length <= stride + 1e-6 then
				break
			end
		end
	end
	car.speed = 0
	E.advance(0.3)
end

-- ── The environment the staged modules run in ─────────────────────────────

local osE = setmetatable({
	clock = function(): number
		return E.clock
	end,
	time = function(t: any?): number
		if t ~= nil then
			return os.time(t)
		end
		return math.floor(E.wall)
	end,
}, { __index = os })
E.os = osE

local function warnE(...: any)
	local parts = {}
	for index = 1, select("#", ...) do
		table.insert(parts, tostring((select(index, ...))))
	end
	table.insert(E.warnings, table.concat(parts, " "))
end
local function printE(...: any)
	local parts = {}
	for index = 1, select("#", ...) do
		table.insert(parts, tostring((select(index, ...))))
	end
	table.insert(E.printed, table.concat(parts, " "))
end

local function typeofE(x: any): string
	local kind = type(x)
	if kind == "table" then
		local mt = getmetatable(x)
		if mt == O or rawget(x, "__e2e") or rawget(x, "__e2eFolder") then
			return "Instance"
		elseif mt == V then
			return "Vector3"
		elseif mt == F then
			return "CFrame"
		elseif mt == C then
			return "Color3"
		elseif mt == SignalMT then
			return "RBXScriptSignal"
		elseif type(mt) == "table" and type(mt.__type) == "string" then
			return mt.__type
		end
	end
	return kind
end
E.typeof = typeofE

local G: { [string]: any } = {
	game = game,
	workspace = workspace,
	Workspace = workspace,
	script = script,
	task = task,
	os = osE,
	require = function(target: any): any
		return E.require(target)
	end,
	warn = warnE,
	print = printE,
	typeof = typeofE,
	Instance = Instance,
	Vector3 = Mock.Vector3,
	CFrame = Mock.CFrame,
	Color3 = Mock.Color3,
	Vector2 = Mock.Vector2,
	UDim = Mock.UDim,
	UDim2 = Mock.UDim2,
	Enum = Mock.Enum,
	PhysicalProperties = Mock.PhysicalProperties,
	Random = Random,
	RaycastParams = { new = function(): any
		return { FilterDescendantsInstances = {}, FilterType = "Exclude" }
	end },
	OverlapParams = { new = function(): any
		return { FilterDescendantsInstances = {}, FilterType = "Exclude" }
	end },
	NumberSequence = opaque("NumberSequence"),
	NumberSequenceKeypoint = opaque("NumberSequenceKeypoint"),
	ColorSequence = opaque("ColorSequence"),
	ColorSequenceKeypoint = opaque("ColorSequenceKeypoint"),
	NumberRange = opaque("NumberRange"),
	BrickColor = opaque("BrickColor"),
	TweenInfo = opaque("TweenInfo"),
	Font = opaque("Font"),
	Rect = opaque("Rect"),
	Region3 = opaque("Region3"),
	Ray = opaque("Ray"),
	tick = function(): number
		return E.clock
	end,
	time = function(): number
		return E.clock
	end,
	wait = task.wait,
	delay = task.delay,
	spawn = task.spawn,
	settings = function(): any
		return {}
	end,
	UserSettings = function(): any
		return {}
	end,
}
E.globals = G
E.env = setmetatable({}, { __index = function(_, k: string): any
	local v = G[k]
	if v ~= nil then
		return v
	end
	return BASE[k]
end })

return E
