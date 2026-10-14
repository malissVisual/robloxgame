--!strict
-- 8.1 SANDBOX, the sandbox's own sounds (the owner: "make the sandbox sound right"; art/audio/sfx4.ogg's 8.1 part, until
-- it is up their stand-ins, shared/SoundSheet.luau Fallback; what plays when: shared/SoundPlan.luau,
-- Config.Soundscape.Sandbox). Heard from what the sandbox already sends, no hooks in its modules:
--   the "Collection" remote (server/Collection.luau)
--     state      one after the other (SoundPlan.collectionCues): a piece put on a stand (a soft thunk and a sparkle) or
--                taken down, pieces that came home (the trip home: a small fanfare; not when the move's result card
--                has just played its own jingle: the Moving remote's "result", StoredQuiet s before)
--     sold       the till's ka-ching
--   the State remote's money going up (SoundPlan.incomeClink): the stands' income, a soft coin clink, at most every
--                IncomeGap s, only while pieces are on show, never with the warehouse's window open
--                (client/WarehouseUi.luau isOpen) and not right after a sale (its money comes in then: SoldQuiet s)
--   every ZDC Sprinter near the camera (workspace.Cars, its SlideOpen attribute, server/Vehicles.luau): its sliding
--                door rolling open and slammed shut, 3D at the door (SoundPlan.slideSound)
--   the walk-in step: your feet onto a Sprinter's rear or side step (your Humanoid's floor changed: a ray down, solid
--                parts only, SoundPlan.isStep): a hollow clonk and the van's springs, at most every StepGap s
-- The rest of the sandbox's sound is client/SoundScape.luau's (the meadow, the warehouse's hall, the chalet's room, the
-- far cowbells, the room's echo, the Sprinter's back doors); client/Sounds.luau leaves the sandbox's money to this
-- module and plays everything (Sounds.play / playAt: the SOUND setting, the stand-ins).
--   SandboxSounds.start()   listens (once; nothing when Config.Sandbox.On is false; client/Main.client.luau starts it)
-- Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SoundPlan = require(Shared.SoundPlan)
local Sounds = require(script.Parent.Sounds)

local SandboxSounds = {}

local B = Config.Soundscape.Sandbox
local player = Players.LocalPlayer
local started = false

local collection: any = nil -- the last "Collection" state (nil: none yet)
local earning = false -- pieces on show earn (its income over 0)
local money: number? = nil -- the last State's money (nil: none yet)
local soldAt = -math.huge
local resultAt = -math.huge
local clinkAt = -math.huge

-- Is the warehouse's window open (client/WarehouseUi.luau, when it is there)?
local function windowOpen(): boolean
	local module = script.Parent:FindFirstChild("WarehouseUi")
	if not module or not module:IsA("ModuleScript") then
		return false
	end
	local ok, open = pcall(function(): any
		return (require(module) :: any).isOpen()
	end)
	return ok and open == true
end

-- ── The collection, a sale, the income ──────────────────────────────────────

local function onCollection(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.kind == "state" then
		local was = collection
		collection = message
		earning = (tonumber(message.income) or 0) > 0
		for _, c in SoundPlan.collectionCues(was, message, os.clock() - resultAt) do
			Sounds.play(c.name, c.volume, c.pitch)
		end
	elseif message.kind == "sold" then
		soldAt = os.clock()
		Sounds.play("sale_register", B.Sold)
	end
end

local function onState(state: any)
	if type(state) ~= "table" or type(state.money) ~= "number" then
		return
	end
	local was = money
	money = state.money
	if was == nil then
		return -- (the first State: nothing came in)
	end
	local now = os.clock()
	if SoundPlan.incomeClink(state.money - was, now, clinkAt, soldAt, windowOpen(), earning) then
		clinkAt = now
		Sounds.play("coin", B.Income, 0.94)
	end
end

-- ── The Sprinter's sliding door ────────────────────────────────────────────

local function watchCar(car: Instance)
	if not car:IsA("Model") then
		return
	end
	local was = car:GetAttribute("SlideOpen")
	car:GetAttributeChangedSignal("SlideOpen"):Connect(function()
		local now = car:GetAttribute("SlideOpen")
		local before = was
		was = now
		if type(before) ~= "boolean" or type(now) ~= "boolean" or now == before then
			return -- (set for the first time as it is built: no sound)
		end
		local chassis = car.PrimaryPart
		local point = chassis and chassis:FindFirstChild("SlidePoint")
		local at = if point and point:IsA("Attachment") then point.WorldPosition else car:GetPivot().Position
		Sounds.playAt(SoundPlan.slideSound(now), at, B.Slide, 1, B.SlideRange)
	end)
end

local function watchCars()
	local cars = workspace:WaitForChild("Cars", 60)
	if not cars then
		return
	end
	for _, car in cars:GetChildren() do
		watchCar(car)
	end
	cars.ChildAdded:Connect(watchCar)
end

-- ── The walk-in step ────────────────────────────────────────────────────────

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true -- (a step folded away is still there, not solid)

local function watchFeet(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local onStep = false
	local stepAt = -math.huge
	humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") or humanoid.SeatPart ~= nil then
			onStep = false
			return
		end
		params.FilterDescendantsInstances = { character }
		local reach = humanoid.HipHeight + root.Size.Y / 2 + 1
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params)
		local now = hit ~= nil and SoundPlan.isStep(hit.Instance.Name) and hit.Instance:GetAttribute("SprinterDoor") ~= nil
		if now and not onStep and os.clock() - stepAt >= B.StepGap then
			stepAt = os.clock()
			Sounds.play("van_step_up", B.Step, 0.95 + math.random() * 0.1)
		end
		onStep = now
	end)
end

function SandboxSounds.start()
	if started or not Config.Sandbox.On then
		return
	end
	started = true
	task.spawn(function()
		local ok, remote = pcall(Net.get, "Collection")
		if ok then
			remote.OnClientEvent:Connect(onCollection)
		else
			warn(`[SandboxSounds] no Collection remote: {remote}`)
		end
	end)
	Net.get("State").OnClientEvent:Connect(onState)
	Net.get("Moving").OnClientEvent:Connect(function(kind: any)
		if kind == "result" then
			resultAt = os.clock() -- (its card plays its jingle: no fanfare for the pieces that came with it)
		end
	end)
	task.spawn(watchCars)
	if player.Character then
		task.spawn(watchFeet, player.Character)
	end
	player.CharacterAdded:Connect(watchFeet)
end

return SandboxSounds
