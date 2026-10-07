--!strict
-- 3.9: the gun away and the hands on foot, on this client. B holsters the gun or draws it (a gamepad: the d-pad down);
-- V swings: a punch while holstered, a strike with the gun while it is out (a touch screen: the HUD's small buttons
-- next to FIRE). You start holstered after every spawn. Aiming (right mouse), shooting (left mouse, F, FIRE) or picking
-- a gun on the weapon wheel while holstered draws the gun first: that press does not fire (client/CameraRig.luau,
-- client/Shooting.luau, client/WeaponWheel.luau ask pressDraws / drawIfHolstered), then the usual raise time applies.
-- The server keeps the real state (server/CloseCombat.luau: the character's Holstered attribute) and checks every
-- swing; this client shows its own choice at once (a short prediction until the attribute agrees) and starts its own
-- arm swing on the key press (client/ArmPose.luau reads localSwing; the server's MeleeAt does not swing it twice).
-- Only on foot: in a car seat B and V do nothing and the holster changes nothing (window shots, the car gun).
-- 6.0: without a gun (a new courier: fists only; Holster.setArmed from the State) B draws nothing and V punches.
-- (No Roblox UI here and nothing that requires CameraRig or ArmPose: both read this module.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Melee = require(Shared.Melee)
local Net = require(Shared.Net)
local Sounds = require(script.Parent.Sounds)

local Holster = {}

local player = Players.LocalPlayer
local enabled = false -- after PLAY (Main)
local PREDICT = 1.5 -- seconds this client's own choice wins before the server's attribute is trusted again
local pending: boolean? = nil -- the choice sent, until the attribute agrees
local pendingAt = 0
local drawnBy: InputObject? = nil -- the press that drew the gun (several listeners ask about the same press)
local nextSwing = 0
local swingAt: number? = nil -- os.clock() when this client's own swing started
local swingKind = "punch"
local armed = true -- 6.0: you own a gun (client/Shooting.luau's setState); without one nothing draws, V punches

function Holster.setEnabled(on: boolean)
	enabled = on
end

-- 6.0: does the State name a gun in your hand? (A new courier has fists only: the server refuses a draw too.)
function Holster.setArmed(on: boolean)
	armed = on
	if not on then
		pending = nil
	end
end

function Holster.armed(): boolean
	return armed
end

-- Is the gun away right now (as this client shows it)?
function Holster.holstered(): boolean
	local character = player.Character
	local server = character ~= nil and character:GetAttribute("Holstered") == true
	if pending ~= nil then
		if pending == server or os.clock() - pendingAt > PREDICT then
			pending = nil
		else
			return pending
		end
	end
	return server
end

-- Can the hands do anything now: in the game, alive, on foot, the hands free?
local function handsFree(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not enabled or not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if humanoid.SeatPart ~= nil or humanoid.Sit then
		return false
	end
	local carrying = character:GetAttribute("Carrying")
	return not (type(carrying) == "string" and carrying ~= "")
end

-- Holster (true) or draw (false) the gun: shown here at once, told to the server.
function Holster.set(holstered: boolean)
	if Holster.holstered() == holstered or (not holstered and not armed) then
		return
	end
	pending = holstered
	pendingAt = os.clock()
	Net.get("Holster"):FireServer(holstered)
	pcall(Sounds.play, "pickup", 0.35, if holstered then 0.8 else 1.15)
end

-- B: holster or draw (on foot, the hands free).
function Holster.toggle()
	if handsFree() then
		Holster.set(not Holster.holstered())
	end
end

-- The gun out, if it is holstered and the hands are free. True when this drew it (the caller's press does not fire).
function Holster.drawIfHolstered(): boolean
	if not armed or not handsFree() or not Holster.holstered() then
		return false
	end
	Holster.set(false)
	return true
end

-- A shooting or aiming press (left / right mouse, F): true when this press drew the gun. Every listener of the same
-- press gets the same answer (CameraRig and Shooting both ask), until the press ends.
function Holster.pressDraws(input: InputObject): boolean
	if drawnBy == input then
		return true
	end
	if Holster.drawIfHolstered() then
		drawnBy = input
		return true
	end
	return false
end

-- Where a swing goes along the ground: the camera's way on a computer (the mouse is locked, the crosshair is the aim),
-- else where the body faces.
local function swingDirection(root: BasePart): Vector3
	local camera = workspace.CurrentCamera
	local look = root.CFrame.LookVector
	if camera and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		look = camera.CFrame.LookVector
	end
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
end

-- V: a punch (holstered) or a strike with the gun. The arm swings here at once; the server decides what it hits.
function Holster.melee()
	if not handsFree() then
		return
	end
	local now = os.clock()
	if now < nextSwing then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local kind = Melee.kindOf(Holster.holstered())
	nextSwing = now + Melee.def(kind).cooldown
	swingAt = now
	swingKind = kind
	local dir = swingDirection(root)
	-- Turn to the swing (the body faces where the fist or the gun goes).
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	Net.get("Melee"):FireServer(dir)
	pcall(Sounds.play, "putdown", 0.4, if kind == "punch" then 1.9 else 1.5)
end

-- ArmPose: this client's own swing (os.clock() when it started, or nil) and its kind.
function Holster.localSwing(): (number?, string)
	return swingAt, swingKind
end

function Holster.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		-- (a gamepad: d-pad right holsters, d-pad left swings; d-pad down is Roblox's emote menu)
		if key == Enum.KeyCode.B or key == Enum.KeyCode.DPadRight then
			Holster.toggle()
		elseif key == Enum.KeyCode.V or key == Enum.KeyCode.DPadLeft then
			Holster.melee()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == drawnBy then
			drawnBy = nil
		end
	end)
	-- A new character starts holstered (the server sets it): no old choice carries over.
	player.CharacterAdded:Connect(function()
		pending = nil
		drawnBy = nil
		swingAt = nil
	end)
end

return Holster
