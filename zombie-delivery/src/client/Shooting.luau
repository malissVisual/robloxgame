--!strict
-- The gun on the client. Hold the left mouse button to shoot where the mouse points, or hold FIRE (the round button,
-- or F) to shoot the nearest zombie (the ones hanging on your car first). What fires (Economy.fireMode, the server
-- decides the same in server/Gun.luau):
--   on foot      the gun in your hand
--   driver       the car gun on the roof, when the car has one (the car model's CarGun attribute)
--   any seat     otherwise a one-handed gun (pistol, revolver, SMG) out of the side window; a two-handed gun does not
--                fire from a car: no shot, no tracer, a short hint instead
-- Here are the inputs, the tracers, the hit feedback (with the dot in client/CameraRig.luau) and the money pop-ups.
-- Nothing fires while your hands hold cargo.
-- 3.9: on foot nothing fires while the gun is holstered (client/Holster.luau): the first press of the left mouse, F or
-- FIRE draws it instead (that press does not shoot).
-- 6.0: a new courier has no gun (fists only): nothing fires, a press says where to buy one (now and then).
-- 6.16 (the owner: "upgrade the visuals and the feel"): every shot kicks the aiming camera (client/ShotKick.luau) and the
-- arms (client/ArmPose.luau), flashes at the muzzle, throws a casing and shows where its rounds stop (sparks, dust, a mark,
-- a dark-red puff on a zombie: client/ShotFx.luau); other players' shots flash and hit the same from their tracers; every
-- hit draws the X (client/HitMarker.luau). All of it is this client's picture: the server decides the hits.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)
local Drive = require(script.Parent.Drive)
local CameraRig = require(script.Parent.CameraRig)
local ArmPose = require(script.Parent.ArmPose)
local Holster = require(script.Parent.Holster)
local ShotFeel = require(Shared.ShotFeel)
local ShotFx = require(script.Parent.ShotFx)
local ShotKick = require(script.Parent.ShotKick)
local HitMarker = require(script.Parent.HitMarker)

local Shooting = {}

local player = Players.LocalPlayer
local fireRemote = Net.get("Fire")

local mouseHeld = false
local autoHeld = false
local nextShot = 0
local weapon: string? = nil -- 6.0: nil = no gun yet (fists only)
local upgrades: { [string]: number } = {}

local effects = ShotFx.folder -- (6.16: made there, the same LocalEffects folder)

function Shooting.setState(state: any)
	weapon = if type(state.weapon) == "string" then state.weapon else nil
	upgrades = state.upgrades
	Holster.setArmed(weapon ~= nil) -- 6.0: fists only until a gun is bought
end

function Shooting.setAutoHeld(held: boolean)
	-- 6.1.1: the gun away, the press does not draw it (3 or B does) and does not fire.
	autoHeld = held and not Holster.firePressAway()
end

-- Set by Main: shows a short text (a toast).
Shooting.notify = function(_text: string) end

-- The car gun installed on a car model (its CarGun attribute, set by server/Vehicles.luau), or nil.
function Shooting.carGunOf(car: Model?): Config.CarGunDef?
	local id = car and car:GetAttribute("CarGun")
	return if type(id) == "string" then Economy.findCarGun(id) else nil
end

-- What a shot of the local player fires right now: "hand" | "cargun" | "window" | nil (a two-handed gun in a car),
-- and the car gun when it is that.
function Shooting.mode(): (string?, Config.CarGunDef?)
	local car, driving = Drive.seatedCar()
	local carGun = if car and driving then Shooting.carGunOf(car) else nil
	return Economy.fireMode(car ~= nil, driving, weapon, if carGun then carGun.id else nil), carGun
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

-- ── Hit feedback ───────────────────────────────────────────────────────────
-- 6.16: the X on every hit (white; a kill red, a headshot gold and bigger, a skull on a kill), around the crosshair or
-- at the spot hit, with the dot's pulse: client/HitMarker.luau.

-- kind: "hit" | "kill" | "head" (a headshot; it counts as a kill unless `killed` says otherwise); position: the spot hit.
function Shooting.hitmarker(kind: string, killed: boolean?, position: Vector3?)
	HitMarker.show(kind, killed, position)
end

-- The muzzle of the gun in a character's hand (on foot), if it is close enough to be the real one.
local function handMuzzle(character: Model?): Attachment?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local gun = character and character:FindFirstChild("HandGun")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not gun or not humanoid or humanoid.SeatPart or not root or not root:IsA("BasePart") then
		return nil
	end
	local found = gun:FindFirstChild("Muzzle", true)
	if found and found:IsA("Attachment") and (found.WorldPosition - root.Position).Magnitude < 8 then
		return found
	end
	return nil
end

-- A shot from a gun in the hand: the flash at the muzzle, the arms kick, a casing flies out to the side (6.16:
-- client/ShotFx.luau; once per shot: a shotgun's pellets arrive as several tracers).
local lastFlash: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local function muzzleFlash(character: Model, at: Attachment)
	local now = os.clock()
	if now - (lastFlash[character] or 0) < 0.05 then
		return
	end
	lastFlash[character] = now
	ShotFx.flash(at.WorldCFrame)
	ArmPose.kick(character)
	local gun = character:FindFirstChild("HandGun")
	local id = gun and gun:GetAttribute("Weapon")
	local kick = ShotFeel.kick(if type(id) == "string" then id else nil)
	local casing = kick.casing
	if casing then
		local delay = kick.casingDelay
		if delay and delay > 0 then
			task.delay(delay, ShotFx.eject, at, casing, character)
		else
			ShotFx.eject(at, casing, character)
		end
	end
end

-- 6.16: a shot from a car (the roof gun, a gun out of the window): the flash where it starts (once per shot).
local function carFlash(character: Model?, from: Vector3, to: Vector3)
	local now = os.clock()
	if character then
		if now - (lastFlash[character] or 0) < 0.05 then
			return
		end
		lastFlash[character] = now
	end
	if (to - from).Magnitude > 0.5 then
		ShotFx.flash(CFrame.lookAt(from, to))
	end
end

-- ── Aiming ─────────────────────────────────────────────────────────────────

-- Where a shot from the car starts: the car gun's muzzle (the "Muzzle" attachment on the CarGun model's "Barrel"),
-- or out of the side window beside my seat (the same point as server/Vehicles.luau windowPoint).
local function muzzle(car: Model, fromRoof: boolean): Vector3?
	local chassis = car.PrimaryPart
	if fromRoof then
		local gun = car:FindFirstChild("CarGun")
		local barrel = gun and gun:FindFirstChild("Barrel")
		local attachment = barrel and barrel:FindFirstChild("Muzzle")
		if attachment and attachment:IsA("Attachment") then
			return attachment.WorldPosition
		end
		return if chassis then chassis.Position + Vector3.new(0, 6, 0) else nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat then
		return nil
	end
	if not chassis or not chassis:IsA("BasePart") then
		return seat.Position + Vector3.new(0, 2.6, 0)
	end
	local at = chassis.CFrame:PointToObjectSpace(seat.Position)
	local side = if at.X >= 0 then 1 else -1
	return (chassis.CFrame * CFrame.new(side * (chassis.Size.X / 2 + 0.6), at.Y + 2.6, at.Z)).Position
end

-- A two-handed gun in a car seat: say why nothing fires (not more often than every few seconds). (6.7: the 6.0 "no gun
-- yet: buy a pistol" note is gone: every courier starts with the pistol, Config.Arms; before the State names it,
-- nothing fires and nothing is said.)
local lastRefusal = 0
local function refuse(driving: boolean)
	local def = Economy.findWeapon(weapon)
	if not def then
		return
	end
	local now = os.clock()
	if now - lastRefusal < 3 then
		return
	end
	lastRefusal = now
	local name = def.name
	Shooting.notify(if driving
		then `{name}: too big to fire from a car. Pistol, revolver or SMG out of the window, or mount a car gun at Wrench Garage.`
		else `{name}: too big to fire from a car. Switch to a pistol, revolver or SMG (T) to shoot out of the window.`)
end

-- A zombie hanging on a car (server/Zombies.luau latch: the LatchedTo attribute): the part aimed at goes to the server
-- with the shot. The car (and the zombie on it) runs on the driver's machine, the server sees it a little behind, and a
-- shot from the window starts right next to it: the server's own ray would miss what you clearly hit here.
local function latchedPart(instance: Instance?): BasePart?
	if not instance or not instance:IsA("BasePart") then
		return nil
	end
	local model = instance:FindFirstAncestorOfClass("Model")
	return if model and model:GetAttribute("LatchedTo") ~= nil then instance else nil
end

local function mouseTarget(car: Model?): (Vector3, BasePart?)
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
	if result then
		return result.Position, latchedPart(result.Instance)
	end
	return ray.Origin + ray.Direction * 600, nil
end

-- The nearest living zombie in range, the ones hanging on my car first. Aims at the chest.
local function autoTarget(from: Vector3, range: number): (Vector3?, BasePart?)
	local folder = workspace:FindFirstChild("Zombies")
	if not folder then
		return nil
	end
	local best: Vector3? = nil
	local bestPart: BasePart? = nil -- the best one's torso when it hangs on a car (latchedPart)
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
					bestPart = latchedPart(torso)
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
					bestPart = nil
				end
			end
		end
	end
	return best, bestPart
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
		return (autoTarget(from, 80)) or from + look * 40
	end
	return (mouseTarget(car))
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
	-- Cargo in the hands, or the gun holstered (3.9): no shooting (the server ignores it too).
	if not car and (CameraRig.carrying() or Holster.holstered()) then
		return -- (6.7: no "buy a pistol" note: everybody has one)
	end
	-- What fires: the hand gun, the car gun, a one-handed gun out of the window, or nothing (two-handed, in a car).
	local mode, carGun = Shooting.mode()
	if not mode then
		refuse(driving)
		return
	end
	-- On foot: start raising the gun, the shot comes once it is up.
	if not CameraRig.canShoot() then
		CameraRig.noteFire()
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	-- On foot: from the gun in your hand.
	local gunMuzzle = if car then nil else handMuzzle(character)
	local from = if car then muzzle(car, carGun ~= nil)
		elseif gunMuzzle then gunMuzzle.WorldPosition
		else root.Position + Vector3.new(0, 1.5, 0) + root.CFrame.LookVector
	if not from then
		return
	end
	-- The rate, range and tracer colour of what really fires.
	local stats = if carGun then Economy.carGunStats(carGun.id, upgrades) else Economy.weaponStats(weapon, upgrades)
	local target: Vector3? = nil
	local aimed: BasePart? = nil -- a zombie on a car under the aim (latchedPart)
	if autoHeld then
		target, aimed = autoTarget(from, stats.range)
		if not target then
			local forward = if car and car.PrimaryPart then car.PrimaryPart.CFrame.LookVector else root.CFrame.LookVector
			target = from + forward * stats.range
		end
	else
		target, aimed = mouseTarget(car)
	end
	if not target then
		return
	end
	nextShot = now + stats.interval
	CameraRig.noteFire()
	fireRemote:FireServer(target, aimed)
	-- 6.16: the kick, the flash, the casing and where the rounds stop (the shot already went where the crosshair was).
	-- 6.20: Steady Hand (Config.Skills recoil, the player attribute Skills) softens a hand gun's kick (not the roof gun's)
	local steady = if carGun then 1 else ShotKick.steady(player:GetAttribute("Skills"))
	ShotKick.shot(if carGun then carGun.id else weapon, (if mode == "window" then Config.Shots.WindowShare else 1) * steady)
	if gunMuzzle and character then
		muzzleFlash(character, gunMuzzle)
	else
		carFlash(character, from, target)
	end
	ShotFx.shot(from, target, stats.range, stats.pellets, stats.spread, if car then { character :: Instance, car } else { character :: Instance })
	local def = Economy.findWeapon(weapon)
	local look: { number }? = if carGun then carGun.color elseif def then def.color else nil
	local color = if look then Color3.fromRGB(look[1], look[2], look[3]) else Color3.new(1, 1, 0.6)
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
		-- 6.1.1: the gun away, the press neither draws nor fires (client/Holster.luau pressDraws).
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHeld = not Holster.pressDraws(input)
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			autoHeld = not Holster.pressDraws(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseHeld = false
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			autoHeld = false
		end
	end)
	-- Alt-Tab swallows the button's InputEnded: without this the gun kept firing in the background.
	UserInputService.WindowFocusReleased:Connect(function()
		mouseHeld = false
		autoHeld = false
	end)
	RunService.Heartbeat:Connect(step)

	Net.get("Tracer").OnClientEvent:Connect(function(from: Vector3, to: Vector3, color: Color3, shooter: number)
		if shooter ~= player.UserId then
			-- A far-off fight (both ends out of sight) is not drawn: a busy server sends many, each a part and a tween.
			local camera = workspace.CurrentCamera
			if camera then
				local eye = camera.CFrame.Position
				if (from - eye).Magnitude > 400 and (to - eye).Magnitude > 400 then
					return
				end
			end
			-- From the gun in their hand as this client shows it (the server shoots from their shoulder).
			local other = Players:GetPlayerByUserId(shooter)
			local character = other and other.Character
			local at = handMuzzle(character)
			if at and character and (at.WorldPosition - from).Magnitude < 8 then
				from = at.WorldPosition
				muzzleFlash(character, at)
			elseif character then
				carFlash(character, from, to) -- 6.16: a car's roof gun, a gun out of a window
			end
			Shooting.tracer(from, to, color)
			ShotFx.impactAt(from, to) -- 6.16: sparks, dust, a mark, a puff where it ended (yours are drawn as you shoot)
		end
	end)
	ShotFx.start()
	HitMarker.start()
	Net.get("Hit").OnClientEvent:Connect(function(position: Vector3, _damage: number, crit: boolean, killed: any)
		local kind, dead = ShotFeel.hitKind(crit, killed)
		Shooting.hitmarker(kind, dead, if typeof(position) == "Vector3" then position else nil)
	end)
	Net.get("Reward").OnClientEvent:Connect(function(position: Vector3, amount: number)
		Shooting.floatText(position + Vector3.new(0, 1, 0), `+${amount}`, Color3.fromRGB(120, 240, 110), 26)
	end)
	Net.get("Bump").OnClientEvent:Connect(function(keep: number)
		Drive.bump(keep)
	end)
end

return Shooting
