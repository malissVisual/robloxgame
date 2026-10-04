--!strict
-- The gun on the client. On foot (the pistol in your hand) or in any seat of a car (the driver fires the roof gun,
-- a passenger out of the window) hold
-- the left mouse button to shoot where the mouse points, or hold FIRE (the round button, or F) to shoot the nearest
-- zombie (the ones hanging on your car first). The server checks every shot (server/Gun.luau); here are the inputs,
-- the tracers, the hit numbers and the money pop-ups.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)
local Drive = require(script.Parent.Drive)
local CameraRig = require(script.Parent.CameraRig)

local Shooting = {}

local player = Players.LocalPlayer
local fireRemote = Net.get("Fire")

local mouseHeld = false
local autoHeld = false
local nextShot = 0
local weapon = "pistol"
local upgrades: { [string]: number } = {}

local effects = Instance.new("Folder")
effects.Name = "LocalEffects"
effects.Parent = workspace

function Shooting.setState(state: any)
	weapon = state.weapon
	upgrades = state.upgrades
end

function Shooting.setAutoHeld(held: boolean)
	autoHeld = held
end

-- ── Effects ────────────────────────────────────────────────────────────────

function Shooting.tracer(from: Vector3, to: Vector3, color: Color3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Size = Vector3.new(0.18, 0.18, length)
	beam.CFrame = CFrame.lookAt((from + to) / 2, to)
	beam.Parent = effects
	TweenService:Create(beam, TweenInfo.new(0.12), { Transparency = 1, Size = Vector3.new(0.05, 0.05, length) }):Play()
	Debris:AddItem(beam, 0.15)
	local spark = Instance.new("Part")
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.CanTouch = false
	spark.Shape = Enum.PartType.Ball
	spark.Material = Enum.Material.Neon
	spark.Color = color
	spark.Size = Vector3.new(0.8, 0.8, 0.8)
	spark.Position = to
	spark.Parent = effects
	TweenService:Create(spark, TweenInfo.new(0.15), { Transparency = 1, Size = Vector3.new(1.6, 1.6, 1.6) }):Play()
	Debris:AddItem(spark, 0.2)
end

-- A number / text floating up from a point in the world.
function Shooting.floatText(position: Vector3, text: string, color: Color3, size: number)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = effects
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size
	label.Font = Enum.Font.GothamBlack
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	TweenService:Create(anchor, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = position + Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.85)
end

-- ── The hit marker (GTA style): an X around the crosshair, no numbers ────────
-- white = a hit, red = a kill, big red X with a ring = a headshot.

local markerBars: { Frame } = {}
local markerScale: UIScale? = nil
local markerRing: Frame? = nil
local markerStroke: UIStroke? = nil

local function makeHitmarker()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hitmarker"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 6
	gui.Parent = player:WaitForChild("PlayerGui")
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromOffset(48, 48)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = holder
	markerScale = scale
	for _, info in { { -1, -1, -45 }, { 1, 1, -45 }, { 1, -1, 45 }, { -1, 1, 45 } } do
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromOffset(3, 11)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.new(0.5, info[1] * 10, 0.5, info[2] * 10)
		bar.Rotation = info[3]
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.new(1, 1, 1)
		bar.BackgroundTransparency = 1
		bar.Parent = holder
		table.insert(markerBars, bar)
	end
	local ring = Instance.new("Frame")
	ring.Size = UDim2.fromOffset(20, 20)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Parent = holder
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 60, 50)
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = ring
	markerRing = ring
	markerStroke = stroke
end

function Shooting.hitmarker(kind: string)
	local color = if kind == "hit" then Color3.new(1, 1, 1) else Color3.fromRGB(255, 60, 50)
	local time = if kind == "head" then 0.45 elseif kind == "kill" then 0.35 else 0.2
	for _, bar in markerBars do
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = 0
		TweenService:Create(bar, TweenInfo.new(time), { BackgroundTransparency = 1 }):Play()
	end
	if markerScale then
		markerScale.Scale = if kind == "head" then 1.7 elseif kind == "kill" then 1.3 else 1
		TweenService:Create(markerScale, TweenInfo.new(time), { Scale = if kind == "head" then 1.3 else 1 }):Play()
	end
	local ring, stroke = markerRing, markerStroke
	if kind == "head" and ring and stroke then
		ring.Size = UDim2.fromOffset(18, 18)
		stroke.Transparency = 0
		TweenService:Create(ring, TweenInfo.new(0.4), { Size = UDim2.fromOffset(56, 56) }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 1 }):Play()
	end
end

-- ── Aiming ─────────────────────────────────────────────────────────────────

local function muzzle(car: Model, driving: boolean): Vector3?
	if not driving then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		return if seat then seat.Position + Vector3.new(0, 3, 0) else nil
	end
	local barrel = car:FindFirstChild("Barrel")
	local attachment = barrel and barrel:FindFirstChild("Muzzle")
	if attachment and attachment:IsA("Attachment") then
		return attachment.WorldPosition
	end
	local chassis = car.PrimaryPart
	return if chassis then chassis.Position + Vector3.new(0, 6, 0) else nil
end

local function mouseTarget(car: Model?): Vector3
	local camera = workspace.CurrentCamera
	local location = UserInputService:GetMouseLocation()
	-- Locked mouse (GTA aiming): the crosshair in the middle of the screen.
	local ray = CameraRig.aimRay() or camera:ViewportPointToRay(location.X, location.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { effects }
	if car then
		table.insert(exclude, car)
	end
	if player.Character then
		table.insert(exclude, player.Character)
	end
	params.FilterDescendantsInstances = exclude
	local result = workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	return if result then result.Position else ray.Origin + ray.Direction * 600
end

-- The nearest living zombie in range, the ones hanging on my car first. Aims at the chest.
local function autoTarget(from: Vector3, range: number): Vector3?
	local folder = workspace:FindFirstChild("Zombies")
	if not folder then
		return nil
	end
	local best: Vector3? = nil
	local bestScore = math.huge
	for _, model in folder:GetChildren() do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local torso = (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")) :: BasePart?
		if humanoid and torso and humanoid.Health > 0 then
			local distance = (torso.Position - from).Magnitude
			if distance <= range then
				local score = distance
				if model:GetAttribute("LatchedTo") == player.UserId then
					score -= 1000
				end
				if score < bestScore then
					best, bestScore = torso.Position, score
				end
			end
		end
	end
	-- Bandit cars come first (after the zombies hanging on your car).
	local cars = workspace:FindFirstChild("BanditCars")
	if cars then
		for _, model in cars:GetChildren() do
			local chassis = if model:IsA("Model") then model.PrimaryPart else nil
			if chassis and ((model:GetAttribute("Health") or 0) :: number) > 0 then
				local distance = (chassis.Position - from).Magnitude
				if distance <= range and distance - 300 < bestScore then
					best, bestScore = chassis.Position + Vector3.new(0, 2, 0), distance - 300
				end
			end
		end
	end
	return best
end

-- Where a thrown item lands: the mouse on a computer, the nearest zombie (or 40 studs ahead) on a touch screen.
function Shooting.aimPoint(): Vector3?
	local car = Drive.seatedCar()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if car and car.PrimaryPart then car.PrimaryPart.Position elseif root then root.Position else nil
	if not from then
		return nil
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		local look = if car and car.PrimaryPart then car.PrimaryPart.CFrame.LookVector elseif root then root.CFrame.LookVector else Vector3.zAxis
		return autoTarget(from, 80) or from + look * 40
	end
	return mouseTarget(car)
end

local function step()
	if not (mouseHeld or autoHeld) then
		return
	end
	local car, driving = Drive.seatedCar()
	local now = os.clock()
	if now < nextShot then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	-- On foot: from the pistol in your hand.
	local from = if car then muzzle(car, driving) else root.Position + Vector3.new(0, 1.5, 0) + root.CFrame.LookVector
	if not from then
		return
	end
	local stats = Economy.weaponStats(weapon, upgrades)
	local target: Vector3? = nil
	if autoHeld then
		target = autoTarget(from, stats.range)
		if not target then
			local forward = if car and car.PrimaryPart then car.PrimaryPart.CFrame.LookVector else root.CFrame.LookVector
			target = from + forward * stats.range
		end
	else
		target = mouseTarget(car)
	end
	if not target then
		return
	end
	nextShot = now + stats.interval
	CameraRig.noteFire()
	fireRemote:FireServer(target)
	local def = Economy.findWeapon(weapon)
	local color = if def then Color3.fromRGB(def.color[1], def.color[2], def.color[3]) else Color3.new(1, 1, 0.6)
	local direction = (target - from)
	local reach = math.min(direction.Magnitude, stats.range)
	if reach > 0.5 then
		Shooting.tracer(from, from + direction.Unit * reach, color)
	end
end

function Shooting.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHeld = true
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			autoHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHeld = false
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			autoHeld = false
		end
	end)
	RunService.Heartbeat:Connect(step)

	Net.get("Tracer").OnClientEvent:Connect(function(from: Vector3, to: Vector3, color: Color3, shooter: number)
		if shooter ~= player.UserId then
			Shooting.tracer(from, to, color)
		end
	end)
	makeHitmarker()
	Net.get("Hit").OnClientEvent:Connect(function(_position: Vector3, _damage: number, crit: boolean, killed: boolean)
		Shooting.hitmarker(if crit then "head" elseif killed then "kill" else "hit")
	end)
	Net.get("Reward").OnClientEvent:Connect(function(position: Vector3, amount: number)
		Shooting.floatText(position + Vector3.new(0, 1, 0), `+${amount}`, Color3.fromRGB(120, 240, 110), 26)
	end)
	Net.get("Bump").OnClientEvent:Connect(function(keep: number)
		Drive.bump(keep)
	end)
end

return Shooting
