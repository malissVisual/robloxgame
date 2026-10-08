--!strict
-- 5.6, ZDC RIDE: every dock has two prompts (server/Rental.luau, tagged RentalPrompt, attribute Kind): "Rent scooter"
-- and "Return scooter". Here each player sees the one that fits them: Return while they have a rental (the player
-- attribute Rental), Rent otherwise. Switched through Enabled, locally (the server never switches these two), so
-- client/CarBoarding.luau's muting while you sit (through the reach) stays its own; Return carries the attribute
-- Seated and shows from the saddle.
--
-- 5.7, the unclip: a rented scooter slides off the dock's charging rail before its rider gets on (server/Vehicles.luau
-- Vehicles.mount moves it Config.Interact.DockSlide out and marks the model: UnclipAt, the server time, and UnclipFrom,
-- where it stood in the dock). Every client near it plays the slide: the real scooter stays hidden here
-- (LocalTransparencyModifier) while a local copy of it (anchored, nothing of it collides or is clicked) jolts back as
-- the clamp lets go and slides out to it over DockUnclip; then the copy goes and the real one shows. Meanwhile its
-- rider steps to its side and gets on (client/CarBoarding.luau: the mount). 6.10: every docked scooter has its own
-- Ride prompt (Kind "rent" too, so shown the same way); the rider hops on at once while it slides (Config.Interact
-- ScooterHop, DockUnclip), and the dock's own Rent prompt reaches only while the dock is empty.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local RentalUi = {}

local TAG = "RentalPrompt"
local player = Players.LocalPlayer
local SLIDE_RANGE = 250 -- the slide is played within this of the camera
local JOLT = 0.12 -- studs back toward the rail as the clamp lets go …
local JOLT_TIME = 0.12 -- … over this long at the start

local function apply(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local renting = player:GetAttribute("Rental") ~= nil
	local kind = prompt:GetAttribute("Kind")
	local show = if kind == "return" then renting else not renting
	if prompt.Enabled ~= show then
		prompt.Enabled = show
	end
end

local function applyAll()
	for _, prompt in CollectionService:GetTagged(TAG) do
		apply(prompt)
	end
end

-- ── 5.7: the unclip ────────────────────────────────────────────────────────

local sliding: { [Model]: boolean } = {}

local function hide(car: Model, hidden: boolean)
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- A still copy of the scooter's look: its parts anchored, nothing that moves, sits, sounds, lights or is clicked.
local function copyOf(car: Model): Model?
	local wasArchivable = car.Archivable
	car.Archivable = true
	local ok, made = pcall(function(): Instance
		return car:Clone()
	end)
	car.Archivable = wasArchivable
	if not ok or not made or not made:IsA("Model") then
		return nil
	end
	local copy = made :: Model
	for _, d in copy:GetDescendants() do
		if d:IsA("Seat") or d:IsA("VehicleSeat") or d:IsA("LuaSourceContainer") or d:IsA("ProximityPrompt") or d:IsA("Sound")
			or d:IsA("Light") or d:IsA("Constraint") or d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("ParticleEmitter") then
			d:Destroy()
		end
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		end
	end
	copy.Name = "UnclipCopy"
	return copy
end

local function unclip(car: Model)
	local at, from = car:GetAttribute("UnclipAt"), car:GetAttribute("UnclipFrom")
	if type(at) ~= "number" or typeof(from) ~= "CFrame" or sliding[car] then
		return
	end
	local seconds = Config.Interact.DockUnclip
	if at + seconds - workspace:GetServerTimeNow() <= 0.05 then
		return -- (long over: it came into view later)
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - from.Position).Magnitude > SLIDE_RANGE then
		return
	end
	local copy = copyOf(car)
	if not copy then
		return
	end
	sliding[car] = true
	local start: CFrame = from
	copy:PivotTo(start)
	copy.Parent = workspace.CurrentCamera or workspace
	hide(car, true)
	local connection: RBXScriptConnection? = nil
	local function finish()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		copy:Destroy()
		sliding[car] = nil
		if car.Parent then
			hide(car, false)
		end
	end
	connection = RunService.RenderStepped:Connect(function()
		local t = workspace:GetServerTimeNow() - at
		if not car.Parent or t >= seconds then
			finish()
			return
		end
		local target = car:GetPivot()
		local away = target.Position - start.Position
		local out = if away.Magnitude > 1e-3 then away.Unit else Vector3.zero
		local u = math.clamp((t - JOLT_TIME) / math.max(1e-3, seconds - JOLT_TIME), 0, 1)
		local k = u * u * (3 - 2 * u)
		local jolt = JOLT * math.sin(math.pi * math.clamp(t / JOLT_TIME, 0, 1))
		local position = start.Position:Lerp(target.Position, k) - out * jolt
		copy:PivotTo(CFrame.new(position) * start.Rotation:Lerp(target.Rotation, k))
	end)
end

local function watchCar(car: Instance)
	if not car:IsA("Model") then
		return
	end
	car:GetAttributeChangedSignal("UnclipAt"):Connect(function()
		unclip(car)
	end)
	car:GetAttributeChangedSignal("UnclipFrom"):Connect(function()
		unclip(car)
	end)
	unclip(car)
end

function RentalUi.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(apply)
	player:GetAttributeChangedSignal("Rental"):Connect(applyAll)
	applyAll()
	task.spawn(function()
		local cars = workspace:WaitForChild("Cars", 60)
		if not cars then
			return
		end
		cars.ChildAdded:Connect(watchCar)
		for _, car in cars:GetChildren() do
			watchCar(car)
		end
	end)
end

return RentalUi
