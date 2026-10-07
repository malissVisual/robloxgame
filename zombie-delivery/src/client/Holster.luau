--!strict
-- 3.9: the gun away and the hands on foot, on this client. B holsters the gun or draws it (a gamepad: the d-pad down);
-- V swings: a punch while holstered, a strike with the gun while it is out (a touch screen: the HUD's small buttons
-- next to FIRE). You start holstered after every spawn. Picking a gun on the weapon wheel while holstered draws it
-- (client/WeaponWheel.luau asks drawIfHolstered). 6.1.1: aiming (right mouse) or shooting (left mouse, F, FIRE) with the
-- gun away does NOT draw it any more (client/CameraRig.luau, client/Shooting.luau ask pressDraws / firePressAway): with
-- fists the left mouse punches, else a note says "press 3".
-- The server keeps the real state (server/CloseCombat.luau: the character's Holstered attribute) and checks every
-- swing; this client shows its own choice at once (a short prediction until the attribute agrees) and starts its own
-- arm swing on the key press (client/ArmPose.luau reads localSwing; the server's MeleeAt does not swing it twice).
-- Only on foot: in a car seat B and V do nothing and the holster changes nothing (window shots, the car gun).
-- 6.0: without a gun (a new courier: fists only; Holster.setArmed from the State) B draws nothing and V punches.
-- 6.1, what you hold (shared/Holding.luau, server/Hand.luau: the character's Hand attribute): fists, the plastic bag or
-- the gun. Holster.choose asks the server (the Hand remote: keys 1 / 2 / 3 through client/Hotbar.luau, a tap on a hand
-- slot) and shows the choice at once (a short prediction, as the holster's); a gamepad's d-pad left / right cycles
-- (Holster.cycle), the melee moved to L1 (6.1 review: the right stick's click is the default camera's zoom). B still draws and holsters (the server makes the gun the
-- hand, or goes back to the bag / fists). A loaded bag in your hand is not set down by an aim or a shot press (only
-- 3, B or the wheel do that, on purpose): such a press tells you so instead of drawing.
-- (No Roblox UI here and nothing that requires CameraRig or ArmPose: both read this module.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Holding = require(Shared.Holding)
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
local bagOwned = false -- 6.1: the plastic bag is yours (the State's kit: Holster.setBag)
local handPending: string? = nil -- 6.1: the hand asked for, until the attribute agrees
local handAt = 0
local toldAt = -math.huge -- 6.1: the last "your bag is loaded" note

-- Set by client/Main.client.luau: a toast.
Holster.notify = nil :: ((string) -> ())?

local function say(text: string)
	local notify = Holster.notify
	if notify then
		notify(text)
	end
end

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

-- 6.1: does the State's kit hold the plastic bag?
-- 6.4: `stays`: the bag in use stays on you out of the hand (Config.Kit stays: slung on the back, never set down)
local bagStays = false
function Holster.setBag(owned: boolean, stays: boolean?)
	bagOwned = owned
	bagStays = stays == true
end

local function bagDown(): boolean
	return typeof(player:GetAttribute("BagDown")) == "Vector3"
end

-- 6.1: what you hold now, as this client shows it ("fists" | "bag" | "gun").
function Holster.hand(): string
	local character = player.Character
	local value = character and character:GetAttribute("Hand")
	local server = if Holding.valid(value) then value :: string elseif character and character:GetAttribute("Holstered") == false then "gun" else "fists"
	if handPending ~= nil then
		if handPending == server or os.clock() - handAt > Config.Hand.Predict then
			handPending = nil
		else
			return handPending
		end
	end
	return server
end

-- 6.1: the bag in your hand has cargo in it (it would be set down if it left the hand; 6.4: not a bag that stays).
local function bagLoaded(): boolean
	return Holster.hand() == "bag" and not bagStays and (tonumber(player:GetAttribute("BagCount")) or 0) > 0 and not bagDown()
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
	if not holstered then
		handPending, handAt = "gun", os.clock() -- 6.1: the gun is the hand
	end
	Net.get("Holster"):FireServer(holstered)
	pcall(Sounds.play, "pickup", 0.35, if holstered then 0.8 else 1.15)
end

-- 6.1: hold this (key 1 / 2 / 3, a hand slot): checked here for the words, decided on the server.
function Holster.choose(hand: string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not enabled or not character or not humanoid or humanoid.Health <= 0 or not Holding.valid(hand) then
		return
	end
	if humanoid.SeatPart ~= nil or humanoid.Sit then
		return -- (in a seat the hands do nothing: window shots, the car gun)
	end
	if Holster.hand() == hand then
		return
	end
	local ok, why = Holding.can(hand, bagOwned, armed, bagDown())
	if not ok then
		say(Holding.whyText(why))
		return
	end
	if hand == "gun" and not handsFree() then
		say(Holding.whyText("busy"))
		return
	end
	handPending, handAt = hand, os.clock()
	pending, pendingAt = hand ~= "gun", os.clock()
	Net.get("Hand"):FireServer(hand)
	pcall(Sounds.play, "pickup", 0.35, if hand == "gun" then 1.15 elseif hand == "bag" then 1.4 else 0.8)
end

-- 6.1: the next hand you may take (a gamepad's d-pad: -1 left, +1 right).
function Holster.cycle(step: number)
	Holster.choose(Holding.cycle(Holster.hand(), step, bagOwned, armed, bagDown()))
end

-- B: holster or draw (on foot, the hands free).
function Holster.toggle()
	if handsFree() then
		Holster.set(not Holster.holstered())
	end
end

-- The gun out, if it is holstered and the hands are free (an explicit choice: a gun picked on the weapon wheel). True
-- when this drew it.
function Holster.drawIfHolstered(): boolean
	if not armed or not handsFree() or not Holster.holstered() then
		return false
	end
	if bagLoaded() then
		-- 6.1: only 3 or B set a loaded bag down (on purpose)
		if os.clock() - toldAt > 3 then
			toldAt = os.clock()
			say("Your bag has deliveries in it: press 3 to set it down and draw your gun.")
		end
		return false
	end
	Holster.set(false)
	return true
end

-- 6.1.1: a shooting or aiming press (left / right mouse, F, the touch FIRE) while the gun is away no longer draws it
-- (the owner: "with my fists I can still shoot, weird"): what you hold decides, 3 or B takes the gun. With fists the
-- left mouse punches; anything else shows a short note now and then. True when the press was used here (no shot, no
-- aim). Every listener of the same press gets the same answer (CameraRig and Shooting both ask), until it ends.
local function awayPress(input: InputObject?): boolean
	if not handsFree() or not Holster.holstered() then
		return false
	end
	if input and input.UserInputType == Enum.UserInputType.MouseButton1 and Holster.hand() == "fists" then
		Holster.melee()
		return true
	end
	if armed and os.clock() - toldAt > 4 then
		toldAt = os.clock()
		say(if bagLoaded() then "Your bag has deliveries in it: press 3 to set it down and take your gun."
			else "Your gun is away: press 3 (or B) to take it.")
	end
	return true
end

function Holster.pressDraws(input: InputObject): boolean
	if drawnBy == input then
		return true
	end
	if awayPress(input) then
		drawnBy = input
		return true
	end
	return false
end

-- The touch FIRE button (client/Shooting.luau setAutoHeld): the same rule, true when the press was used here.
function Holster.firePressAway(): boolean
	return awayPress(nil)
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
		-- (a gamepad, 6.1: the d-pad's left and right cycle what you hold, L1 swings; the d-pad's up
		-- is the weapon wheel, its down the phone)
		if key == Enum.KeyCode.B then
			Holster.toggle()
		elseif key == Enum.KeyCode.V or key == Enum.KeyCode.ButtonL1 then
			Holster.melee()
		elseif key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.DPadRight then
			Holster.cycle(if key == Enum.KeyCode.DPadLeft then -1 else 1)
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
		handPending = nil
	end)
end

return Holster
