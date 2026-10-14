--!strict
-- 8.3: the few services the real server/Npcs.luau needs in the Luau CLI (tests/npcs_runtime_test.luau through
-- tests/run_tests.py, which builds NpcsServer.luau from src/server/Npcs.luau with one line on top: setfenv to this
-- runtime's environment, so its requires and globals are these). The instances are tools/fixtures/item-mock.luau's
-- recorder with what a person's body uses: Players:CreateHumanoidModelFromDescription (a classic R15's parts, its
-- Humanoid and Animator), a Humanoid's states (SetStateEnabled / GetStateEnabled / ChangeState / GetState, every
-- ChangeState and every PlatformStand written kept in order), Move / MoveTo, an Animator's tracks (Play / Stop /
-- AdjustSpeed, IsPlaying, Speed), SetNetworkOwner, signals. No physics, no tweens run; task.spawn keeps the function
-- (a walk's loop never runs), os.clock is the runtime's.
local Mock = require("./ItemMock") :: any

local R: any = {
	clock = 10,
	states = {}, -- { { humanoid, state } } every ChangeState
	platform = {}, -- { { humanoid, value } } every PlatformStand written
	spawned = {}, -- the functions task.spawn was given
	moved = {}, -- { { humanoid, to } } every MoveTo
}
R.Mock = Mock

local O = getmetatable(Mock.Instance.new("Model"))
local F = getmetatable(Mock.CFrame.new())
local BASE = getfenv(1)

-- (a CFrame's LookVector, Rotation and X / Y / Z, as tests/runtime/MovingRuntime.luau gives them)
F.__index = function(self: any, key: string): any
	if key == "Rotation" then
		return setmetatable({ Position = Mock.Vector3.new(), R = self.R }, F)
	elseif key == "LookVector" then
		return Mock.Vector3.new(-self.R[3], -self.R[6], -self.R[9])
	elseif key == "X" then
		return self.Position.X
	elseif key == "Y" then
		return self.Position.Y
	elseif key == "Z" then
		return self.Position.Z
	end
	return rawget(F, key)
end

local function signal(): any
	local s: any = { handlers = {} }
	function s.Connect(self: any, fn: any): any
		table.insert(self.handlers, fn)
		return { Disconnect = function() end, Connected = true }
	end
	function s.Fire(self: any, ...: any)
		for _, fn in self.handlers do
			fn(...)
		end
	end
	return s
end

local create = Mock.Instance.new
Mock.Instance.new = function(class: string): any
	local obj = create(class)
	obj.Destroying = signal()
	if class == "Humanoid" then
		obj.props.State = "Running"
		obj.props.AutoRotate = true
		obj.props.Jump = false
		obj.props.PlatformStand = false
	end
	return obj
end

-- (a Humanoid's PlatformStand written: kept, in order)
local baseNew = O.__newindex
O.__newindex = function(self: any, key: string, value: any)
	if key == "PlatformStand" and self.ClassName == "Humanoid" then
		table.insert(R.platform, { humanoid = self, value = value })
	end
	baseNew(self, key, value)
end

-- (each humanoid's own: the recorder's Clone copies the props' tables by reference)
local enabled: { [any]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any
function O.SetStateEnabled(self: any, state: string, on: boolean)
	local own = enabled[self] or {}
	enabled[self] = own
	own[state] = on
end
function O.GetStateEnabled(self: any, state: string): boolean
	local own = enabled[self]
	return not own or own[state] ~= false
end
function O.ChangeState(self: any, state: string)
	if not O.GetStateEnabled(self, state) then
		return
	end
	self.props.State = state
	table.insert(R.states, { humanoid = self, state = state })
end
function O.GetState(self: any): string
	return self.props.State
end
function O.Move(self: any, direction: any)
	self.props.MoveDirection = direction
end
function O.MoveTo(self: any, to: any)
	table.insert(R.moved, { humanoid = self, to = to })
end
function O.SetNetworkOwner(self: any, owner: any)
	self.props.NetworkOwner = if owner == nil then false else owner
end
-- An Animator's tracks: by their animation's id (the walk, the idle, the run).
function O.LoadAnimation(self: any, animation: any): any
	local track: any = { id = animation.AnimationId, IsPlaying = false, Speed = 1, Looped = false, Length = 1, TimePosition = 0, plays = 0 }
	function track.Play(t: any, _fade: number?, _weight: number?, speed: number?)
		t.IsPlaying, t.Speed, t.plays = true, speed or 1, t.plays + 1
	end
	function track.Stop(t: any)
		t.IsPlaying = false
	end
	function track.AdjustSpeed(t: any, speed: number)
		t.Speed = speed
	end
	self.props.Tracks = self.props.Tracks or {}
	self.props.Tracks[animation.AnimationId] = track
	return track
end

-- A classic R15 from a HumanoidDescription: its parts (the root 2 × 2 × 1, the head, the torso, the limbs), a Humanoid
-- with the stock HipHeight (2) and its Animator.
local function rig(): any
	local model = Mock.Instance.new("Model")
	local function part(name: string, size: any, y: number): any
		local p = Mock.Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = Mock.CFrame.new(0, y, 0)
		p.Parent = model
		return p
	end
	local root = part("HumanoidRootPart", Mock.Vector3.new(2, 2, 1), 3)
	part("LowerTorso", Mock.Vector3.new(2, 0.4, 1), 2.2)
	part("UpperTorso", Mock.Vector3.new(2, 1.6, 1), 3.2)
	part("Head", Mock.Vector3.new(1.2, 1.2, 1.2), 4.6)
	for _, name in { "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "LeftUpperArm", "RightUpperArm", "LeftLowerArm",
		"RightLowerArm", "LeftHand", "RightHand" } do
		part(name, Mock.Vector3.new(1, 1, 1), 1)
	end
	model.PrimaryPart = root
	local humanoid = Mock.Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.HipHeight = 2
	humanoid.Parent = model
	local animator = Mock.Instance.new("Animator")
	animator.Name = "Animator"
	animator.Parent = humanoid
	return model
end

local function token(name: string): any
	return { Name = name, WaitForChild = function(_: any, child: string): any
		return token(child)
	end }
end

local services: { [string]: any } = {
	Players = {
		CreateHumanoidModelFromDescription = function(_: any, _description: any, _rig: any): any
			return rig()
		end,
		GetPlayers = function(): any
			return {}
		end,
	},
	PhysicsService = {
		RegisterCollisionGroup = function() end,
		CollisionGroupSetCollidable = function() end,
	},
	ReplicatedStorage = token("ReplicatedStorage"),
	TextService = {
		GetTextSize = function(): any
			return Mock.Vector2.new(120, 20)
		end,
	},
	TweenService = {
		Create = function(_: any, obj: any, _info: any, goal: any): any
			return {
				Completed = signal(),
				PlaybackState = "Completed",
				Play = function()
					for key, value in goal do
						obj[key] = value
					end
				end,
				Cancel = function() end,
			}
		end,
	},
}
R.game = { GetService = function(_: any, name: string): any
	assert(services[name], `NpcsRuntime: unmocked service {name}`)
	return services[name]
end }

local workspace = Mock.workspace
workspace.Name = "Workspace"
R.workspace = workspace

local G: any = {
	game = R.game,
	workspace = workspace,
	Instance = Mock.Instance,
	Vector3 = setmetatable({ one = Mock.Vector3.new(1, 1, 1) }, { __index = Mock.Vector3 }),
	Vector2 = Mock.Vector2,
	CFrame = Mock.CFrame,
	Color3 = Mock.Color3,
	Enum = Mock.Enum,
	UDim2 = { new = function(...: any): any
		return { ... }
	end, fromOffset = function(...: any): any
		return { ... }
	end, fromScale = function(...: any): any
		return { ... }
	end },
	UDim = { new = function(...: any): any
		return { ... }
	end },
	TweenInfo = { new = function(...: any): any
		return { ... }
	end },
	task = {
		spawn = function(fn: any, ...: any)
			table.insert(R.spawned, fn) -- (kept, not run: a walk's loop)
			local _ = ...
		end,
		delay = function() end,
		wait = function(): number
			return 0
		end,
	},
	os = setmetatable({ clock = function(): number
		return R.clock
	end }, { __index = os }),
	warn = function(...: any)
		print("WARN", ...)
	end,
	-- the Shared modules: `ReplicatedStorage:WaitForChild("Shared"):WaitForChild(name)` is a token with its name
	require = function(module: any): any
		if type(module) == "table" and module.Name then
			return require(`./{module.Name}`)
		end
		return require(module)
	end,
}
R.env = setmetatable({}, { __index = function(_: any, key: string): any
	local value = G[key]
	if value ~= nil then
		return value
	end
	return BASE[key]
end })

-- A person's tracks by their animation's id.
function R.tracks(model: any): any
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	return (animator and animator.props.Tracks) or {}
end

return R
