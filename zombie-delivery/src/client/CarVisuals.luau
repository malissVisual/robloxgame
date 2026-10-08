--!strict
-- What every client does for every car: spins the tyres with the speed and turns the front ones, shows only the
-- prompts that fit (Drive at your own car's driver's door, Ride along at a friend's car's door with a free seat
-- behind it; 3.7: every door has its own, server/Vehicles.luau doorsOf) and puts the owner's name over other players'
-- cars.
-- 3.7: swings the cabin doors (the Motor6Ds "DoorHinge") open and shut: somebody gets in or out. 3.10: from their
-- attributes DoorOpenAt to DoorCloseAt (server times, server/Vehicles.luau), open in Config.Cargo.DoorSwingSeconds,
-- shut in DoorShutSeconds (shared/Boarding.luau); getting out, your own door opens at once (Drive.doorHeld). No door
-- prompts while a chauffeur drives the car (Chauffeured), your hands are full (the Carrying attribute: you could not
-- get in anyway), you sit in a car or are getting in (3.10: E gets you out there), or the seat is taken or reserved.
-- 3.2: swings the back that opens (rear doors, a tailgate, a trunk lid, a ramp: the Motor6Ds "BackHinge" on the
-- chassis, server/Vehicles.luau) toward the car's attribute BackOpen, a short eased swing.
-- The back's prompt shows only to the owner and the crew of the owner's job (the attribute BackCrew, server/Cargo.luau).
-- 3.6: the owner's name sits on a cream pill in ink (Theme.Postage.pill), readable over a night street and a sunny one.
-- 4.0: the Rusty Van's exhaust smokes (the car's attribute Smoky, server/Vehicles.luau: till Engine level 1): a cheap
-- ParticleEmitter at its Attachment "Exhaust", made the first time it is near, puffing more at idle than on the move.
-- 5.1, a bike (the car's attribute Bike, server/Vehicles.luau): its frame leans into the turns (the Motor6D BikeLean,
-- by how fast it turns at its speed: only the look, the physics stay upright), the cranks and pedals turn with the
-- speed (CrankMotor), the front wheel does not steer (the fork is part of the frame), and the rider sits posed
-- (client/BikeRider.luau: leaning forward, hands on the grips, legs pumping with the crank). A trailer's wheels are in
-- the kit: found again when the car's KitBuilt changes.
-- 5.1.1, the E-Scooter (the car's attributes Bike and BikeStand): it leans the same way, has no cranks, and its rider
-- stands (BikeRider.pose's stand: the legs straight on the deck, the hands on the bar).
-- 6.10, the scooter's wheelie (shared/ScooterRide.luau): the BikeLean also pitches the deck back round the rear axle
-- (the rear WheelMotor's place on the BikeFrame), the rider and the load on the frame with it, the rider sitting back
-- (BikeRider.pose's wheelie). Your own scooter from client/Drive.luau at once (Drive.wheelie), everybody else's from
-- its attribute WheelieAt (server/Wheelie.luau), popped up and dropped at the same pace. It leans on Config.Scooter's
-- numbers (a bike on LEAN_MAX, LEAN_RATE).
-- 6.12: says when a cabin door starts to open or is shut and when the back starts to open or to close
-- (CarVisuals.onSwing, set by client/SoundScape.luau: the doors' and the back's sounds where they are); the back's kind
-- (two rear doors, a roll-up door, a tailgate / trunk lid / ramp) from its hinge (shared/SoundPlan.luau backKind). A car
-- just seen (streamed in, its back already open) stays quiet its first second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Boarding = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Boarding"))
local ScooterRide = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ScooterRide"))
local SoundPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundPlan"))

local BikeRider = require(script.Parent.BikeRider)
local Drive = require(script.Parent.Drive)
local Theme = require(script.Parent.Theme)

local CarVisuals = {}

-- 6.12: set by client/SoundScape.luau. what: "door" or the back's kind (SoundPlan.backKind); moment: "opening" (it
-- starts to open), "closing" (the back starts to close) or "shut"; part: the leaf that moves.
CarVisuals.onSwing = nil :: ((what: string, moment: string, part: BasePart) -> ())?

type Wheel = { motor: Motor6D, front: boolean, radius: number }
type Hinge = { motor: Motor6D, axis: Vector3, angle: number } -- angle: the open turn in radians
type DoorHinge = { motor: Motor6D, angle: number, open: number, door: number } -- open: 0 shut … 1 open
type DoorPrompt = { prompt: ProximityPrompt, driver: boolean, seats: { Seat } }
type CarState = {
	wheels: { Wheel },
	hinges: { Hinge },
	doorHinges: { DoorHinge },
	doorPrompts: { DoorPrompt },
	back: number,
	spin: number,
	steer: number,
	tagged: boolean,
	backReach: number?, -- the BackPrompt's own reach (the server's), before it was hidden here
	trolleyReach: number?, -- 4.0: the same for the trolley's "Take trolley" (server/Equipment.luau, TrolleyTake)
	smoke: ParticleEmitter?, -- 4.0: the exhaust smoke (made when first needed)
	-- 5.1, a bike: its lean and crank joints, how far it leans and where the crank is, the rider posed, the kit seen.
	lean: Motor6D?,
	crankMotor: Motor6D?,
	tilt: number,
	crank: number,
	rider: Model?,
	kitBuilt: any,
	-- 6.10, a scooter: the rear axle on its BikeFrame (the wheelie's pivot), how far up it is drawn and since when.
	axle: Vector3?,
	wheelie: number,
	wheelieTime: number,
	-- 6.12: the back's kind for its sounds, and no sounds before this (os.clock: a car just seen).
	backKind: string,
	quietUntil: number,
}

local player = Players.LocalPlayer
local states: { [Model]: CarState } = {}
local RANGE = 260
local RIDER_RANGE = 160 -- 5.1: riders posed this close to the camera
local LEAN_MAX = 0.16 -- 5.1: radians (about 9°) a bike leans at most (its load, welded to the hull, does not lean)
local LEAN_RATE = 0.006 -- per (rad/s of turning × stud/s of speed)
local CADENCE = 0.42 -- 5.1: crank turns per wheel turn
local BACK_TIME = 0.45 -- seconds for the back to swing open or shut

local function stateOf(car: Model): CarState?
	local state = states[car]
	if state then
		return state
	end
	local chassis = car.PrimaryPart
	if not chassis then
		return nil
	end
	local wheels: { Wheel } = {}
	local hinges: { Hinge } = {}
	local doorHinges: { DoorHinge } = {}
	local doorPrompts: { DoorPrompt } = {}
	local lean: Motor6D?, crankMotor: Motor6D? = nil, nil
	local axle: Vector3? = nil
	local backKind = "swing"
	-- 3.7: the seats behind each door (their attribute Door).
	local seatsAt: { [number]: { Seat } } = {}
	for _, child in car:GetChildren() do
		local index = child:GetAttribute("Door")
		if child:IsA("Seat") and type(index) == "number" then
			local list = seatsAt[index] or {}
			seatsAt[index] = list
			table.insert(list, child)
		end
	end
	for _, child in chassis:GetChildren() do
		if child:IsA("Motor6D") and child.Name == "WheelMotor" then
			table.insert(wheels, {
				motor = child,
				front = child:GetAttribute("Front") == true,
				radius = (child:GetAttribute("Radius") or 1.3) :: number,
			})
			if child:GetAttribute("Front") == false and child.Part0 and child.Part0.Name == "BikeFrame" then
				axle = child.C0.Position -- 6.10: the rear wheel's axle on the frame (the wheelie turns round it)
			end
		elseif child:IsA("Motor6D") and child.Name == "BikeLean" then
			lean = child
		elseif child:IsA("Motor6D") and child.Name == "CrankMotor" then
			crankMotor = child
		elseif child:IsA("Motor6D") and child.Name == "BackHinge" then
			local angle = child:GetAttribute("Angle")
			if #hinges == 0 then
				-- 6.12: C1 = the hinge from the leaf's middle (server/Vehicles.luau buildBack): a roll-up door hangs from
				-- its top, a tailgate stands on its bottom edge
				backKind = SoundPlan.backKind(if child:GetAttribute("Axis") == "X" then "X" else "Y", child.C1.Position.Y)
			end
			table.insert(hinges, {
				motor = child,
				axis = if child:GetAttribute("Axis") == "X" then Vector3.xAxis else Vector3.yAxis,
				angle = math.rad(if type(angle) == "number" then angle else 90),
			})
		elseif child:IsA("Motor6D") and child.Name == "DoorHinge" then
			local angle = child:GetAttribute("Angle")
			local index = child:GetAttribute("Door")
			table.insert(doorHinges, {
				motor = child,
				angle = math.rad(if type(angle) == "number" then angle else 70),
				open = 0,
				door = if type(index) == "number" then index else 0,
			})
		elseif child:IsA("Attachment") and string.sub(child.Name, 1, 4) == "Door" then
			local prompt = child:FindFirstChildOfClass("ProximityPrompt")
			local index = prompt and prompt:GetAttribute("Door")
			if prompt then
				table.insert(doorPrompts, {
					prompt = prompt,
					driver = prompt.Name == "DrivePrompt",
					seats = if type(index) == "number" then seatsAt[index] or {} else {},
				})
			end
		end
	end
	state = {
		wheels = wheels,
		hinges = hinges,
		doorHinges = doorHinges,
		doorPrompts = doorPrompts,
		back = 0,
		spin = 0,
		steer = 0,
		tagged = false,
		backReach = nil,
		trolleyReach = nil,
		smoke = nil,
		lean = lean,
		crankMotor = crankMotor,
		tilt = 0,
		crank = 0,
		rider = nil,
		kitBuilt = nil,
		axle = axle,
		wheelie = 0,
		wheelieTime = 0,
		backKind = backKind,
		quietUntil = os.clock() + 1,
	}
	states[car] = state
	car.Destroying:Connect(function()
		local rider = state and state.rider
		if rider then
			BikeRider.release(rider)
		end
		states[car] = nil
	end)
	return state
end

-- 5.1: the wheels in the car's kit (a bike trailer's: WheelMotors under UpgradeKit) replace the old kit's.
local function kitWheels(car: Model, state: CarState)
	local chassis = car.PrimaryPart
	local kept: { Wheel } = {}
	for _, wheel in state.wheels do
		if wheel.motor.Parent == chassis then
			table.insert(kept, wheel)
		end
	end
	local kit = car:FindFirstChild("UpgradeKit")
	if kit then
		for _, d in kit:GetDescendants() do
			if d:IsA("Motor6D") and d.Name == "WheelMotor" then
				table.insert(kept, { motor = d, front = false, radius = (d:GetAttribute("Radius") or 1.3) :: number })
			end
		end
	end
	state.wheels = kept
end

-- 5.1: the rider on a bike's saddle near the camera is posed (client/BikeRider.luau), the one before let go.
local function poseRider(car: Model, state: CarState, near: boolean)
	local seat = car:FindFirstChild("DriverSeat")
	local occupant = if near and seat and seat:IsA("VehicleSeat") then seat.Occupant else nil
	local character = occupant and occupant.Parent
	local rider: Model? = if character and character:IsA("Model") and occupant and occupant.Health > 0 then character else nil
	if state.rider and state.rider ~= rider then
		BikeRider.release(state.rider)
	end
	state.rider = rider
	if rider then
		BikeRider.pose(rider, state.crank, car:GetAttribute("BikeStand") == true, state.wheelie) -- (5.1.1: the E-Scooter: standing; 6.10: its wheelie)
	end
end

-- 4.0: a thin grey-blue puff out of the exhaust pipe, drifting back and up.
local SMOKE_RANGE = 140
local function makeSmoke(at: Attachment): ParticleEmitter
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ExhaustSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 122, 128), Color3.fromRGB(170, 170, 172))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1.8) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.0, 1.6)
	smoke.Speed = NumberRange.new(1.5, 2.5)
	smoke.SpreadAngle = Vector2.new(18, 18)
	smoke.EmissionDirection = Enum.NormalId.Back -- out of the back of the car
	smoke.Acceleration = Vector3.new(0, 1.4, 0)
	smoke.Drag = 1
	smoke.LightInfluence = 1
	smoke.Rate = 0
	smoke.Parent = at
	return smoke
end

local function nameTag(car: Model, chassis: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerTag"
	gui.Size = UDim2.fromOffset(200, 30)
	gui.StudsOffset = Vector3.new(0, 10, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.Parent = chassis
	local label = Instance.new("TextLabel")
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.Position = UDim2.fromScale(0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.BackgroundColor3 = Theme.Postage.pill
	label.BackgroundTransparency = 0.05
	label.Text = `{car:GetAttribute("OwnerName") or "?"}'s {if car:GetAttribute("Bike") == true then "bike" else "car"}`
	label.TextColor3 = Theme.Postage.ink
	label.Font = Theme.HeadingFont
	label.TextSize = 15
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Postage.line
	stroke.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = label
end

local function freeSeat(seats: { Seat }): boolean
	for _, seat in seats do
		if seat.Occupant == nil and seat:GetAttribute("Reserved") == nil then
			return true
		end
	end
	return false
end

-- 3.10: the driver's seat is empty and nobody is getting into it.
local function driverFree(car: Model): boolean
	local seat = car:FindFirstChild("DriverSeat")
	return seat ~= nil and seat:IsA("VehicleSeat") and seat.Occupant == nil and seat:GetAttribute("Reserved") == nil
end

-- 5.9.2: every car, one list kept and built again only when a car comes or goes (no new table every frame).
local CAR_FOLDERS = { "Cars", "BanditCars" }
local carList: { Instance } = {}
local carFolders: { [string]: Instance } = {}
local carListDirty = true

local function allCars(): { Instance }
	for _, name in CAR_FOLDERS do
		local known = carFolders[name]
		if known and known.Parent == workspace then
			continue
		end
		local folder = workspace:FindFirstChild(name)
		if folder ~= known then
			carListDirty = true
			if folder then
				carFolders[name] = folder
				local function changed()
					carListDirty = true
				end
				folder.ChildAdded:Connect(changed)
				folder.ChildRemoved:Connect(changed)
			else
				carFolders[name] = nil
			end
		end
	end
	if carListDirty then
		carListDirty = false
		table.clear(carList)
		for _, name in CAR_FOLDERS do
			local folder = carFolders[name]
			if folder then
				for _, car in folder:GetChildren() do
					table.insert(carList, car)
				end
			end
		end
	end
	return carList
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local seatedIn = Drive.seatedCar()
	local character = player.Character
	local handsFull = character ~= nil and character:GetAttribute("Carrying") ~= nil
	local boarding = character ~= nil and character:GetAttribute("Boarding") ~= nil -- 3.10: on the way into a seat
	local now = workspace:GetServerTimeNow()
	for _, car in allCars() do
		if not car:IsA("Model") then
			continue
		end
		local chassis = car.PrimaryPart
		local state = stateOf(car)
		if not chassis or not state then
			continue
		end
		local mine = car:GetAttribute("OwnerId") == player.UserId

		-- Prompts: 3.7, one at every door.
		local enterable = car:GetAttribute("Chauffeured") ~= true and not handsFull and not boarding and seatedIn == nil
			and (car:GetAttribute("Health") or 0) > 0
		for _, entry in state.doorPrompts do
			local want = if entry.driver
				then enterable and mine and driverFree(car)
				else enterable and not mine and car:GetAttribute("Repairing") ~= true and freeSeat(entry.seats)
			if entry.prompt.Enabled ~= want then
				entry.prompt.Enabled = want
			end
		end
		-- 3.2: the back's prompt only for the owner and the crew of the owner's job (the car's BackCrew, server/Cargo.luau);
		-- out of reach for everybody else, so a stranger's car does not take the E. (Enabled is the server's: one E at a time.)
		local door = chassis:FindFirstChild("CargoDoor")
		local back = door and door:FindFirstChild("BackPrompt")
		local crew = car:GetAttribute("BackCrew")
		-- (3.10: not from a seat: E there gets you out.)
		local usable = seatedIn == nil and (mine or (type(crew) == "string" and string.find(`,{crew},`, `,{player.UserId},`, 1, true) ~= nil))
		if back and back:IsA("ProximityPrompt") then
			local reach: number = state.backReach or back.MaxActivationDistance
			state.backReach = reach
			local want = if usable then reach else 0
			if back.MaxActivationDistance ~= want then
				back.MaxActivationDistance = want
			end
		end
		-- 4.0: the trolley's "Take trolley" (server/Equipment.luau, the chassis' TrolleyTake) the same way, and only with
		-- empty hands (the server refuses everybody else anyway).
		local take = chassis:FindFirstChild("TrolleyTake")
		local takePrompt = take and take:FindFirstChildOfClass("ProximityPrompt")
		if takePrompt then
			local reach: number = state.trolleyReach or takePrompt.MaxActivationDistance
			state.trolleyReach = reach
			local want = if usable and not handsFull then reach else 0
			if takePrompt.MaxActivationDistance ~= want then
				takePrompt.MaxActivationDistance = want
			end
		end
		if not mine and not state.tagged and car:GetAttribute("OwnerId") ~= nil then
			state.tagged = true
			nameTag(car, chassis)
		end

		-- 4.0: the smoking exhaust, near the camera only.
		local distance = (chassis.Position - eye).Magnitude
		local smoky = car:GetAttribute("Smoky") == true and distance < SMOKE_RANGE
		local smoke = state.smoke
		if smoky and not smoke then
			local exhaust = chassis:FindFirstChild("Exhaust")
			if exhaust and exhaust:IsA("Attachment") then
				smoke = makeSmoke(exhaust)
				state.smoke = smoke
			end
		end
		if smoke then
			local rate = if not smoky then 0 elseif chassis.AssemblyLinearVelocity.Magnitude < 6 then 7 else 2.5
			if smoke.Rate ~= rate then
				smoke.Rate = rate
			end
		end

		-- Wheels.
		local bike = state.lean ~= nil
		if bike then
			poseRider(car, state, distance <= RIDER_RANGE)
		end
		if distance > RANGE then
			continue
		end
		local forward = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
		local targetSteer: number
		if bike then
			targetSteer = 0 -- 5.1: the fork is part of the frame (it leans instead)
		elseif mine and Drive.isDriving() then
			targetSteer = -Drive.steer() * 0.45
		else
			targetSteer = math.clamp(chassis.AssemblyAngularVelocity.Y * 0.35, -0.45, 0.45) * (if forward >= 0 then 1 else -1)
		end
		state.steer += (targetSteer - state.steer) * math.min(1, dt * 10)
		for _, wheel in state.wheels do
			if not wheel.motor.Parent then
				continue
			end
			local spin = state.spin * 1.3 / wheel.radius
			local turn = if wheel.front then CFrame.Angles(0, state.steer, 0) else CFrame.identity
			wheel.motor.Transform = turn * CFrame.Angles(spin, 0, 0)
		end
		state.spin -= forward / 1.3 * dt

		-- 5.1, a bike: the lean into the turn (how fast it turns at its speed), the cranks with the wheels, the kit's
		-- trailer wheels found again after a new kit.
		local leanMotor = state.lean
		if leanMotor and leanMotor.Parent then
			local scooter = car:GetAttribute("BikeStand") == true
			local goal = if scooter then ScooterRide.lean(chassis.AssemblyAngularVelocity.Y, forward)
				else math.clamp(chassis.AssemblyAngularVelocity.Y * forward * LEAN_RATE, -LEAN_MAX, LEAN_MAX)
			state.tilt += (goal - state.tilt) * math.min(1, dt * 6)
			local axle = state.axle
			if scooter and axle then
				-- 6.10: the wheelie: the deck pitched back round the rear axle (yours from your Drive, the others' from
				-- WheelieAt), then the lean
				local at = car:GetAttribute("WheelieAt")
				if mine and Drive.isDriving() then
					state.wheelie, state.wheelieTime = Drive.wheelie(car)
				else
					state.wheelie = ScooterRide.amountStep(state.wheelie, type(at) == "number", dt)
					state.wheelieTime = if type(at) == "number" then now - at else state.wheelieTime
				end
				local pitch = ScooterRide.pitch(state.wheelie, state.wheelieTime)
				leanMotor.Transform = if pitch ~= 0 then CFrame.new(axle) * CFrame.Angles(pitch, 0, 0) * CFrame.new(-axle) * CFrame.Angles(0, 0, state.tilt)
					else CFrame.Angles(0, 0, state.tilt)
			else
				leanMotor.Transform = CFrame.Angles(0, 0, state.tilt)
			end
			local crankMotor = state.crankMotor
			state.crank -= forward / 1.3 * CADENCE * dt
			if crankMotor and crankMotor.Parent then
				crankMotor.Transform = CFrame.Angles(state.crank, 0, 0)
			end
			local built = car:GetAttribute("KitBuilt")
			if built ~= state.kitBuilt then
				state.kitBuilt = built
				kitWheels(car, state)
			end
		end

		-- 3.7: the cabin doors swing open and shut (eased; held while open). 3.10: from DoorOpenAt to DoorCloseAt.
		for _, swing in state.doorHinges do
			local openAt, closeAt = swing.motor:GetAttribute("DoorOpenAt"), swing.motor:GetAttribute("DoorCloseAt")
			local target = Boarding.doorGoal(now, if type(openAt) == "number" then openAt else nil, if type(closeAt) == "number" then closeAt else 0)
			if Drive.doorHeld(car, swing.door) then
				target = 1
			end
			local before = swing.open
			swing.open = Boarding.doorStep(before, target, dt)
			if (swing.open > 0 or before > 0) and swing.motor.Parent then
				local t = swing.open * swing.open * (3 - 2 * swing.open)
				swing.motor.Transform = CFrame.fromAxisAngle(Vector3.yAxis, swing.angle * t)
			end
			-- 6.12: the latch as it opens, the thunk as it shuts
			local onSwing = CarVisuals.onSwing
			local leaf = swing.motor.Part1
			if onSwing and leaf and (before == 0) ~= (swing.open == 0) and os.clock() > state.quietUntil then
				onSwing("door", if before == 0 then "opening" else "shut", leaf)
			end
		end

		-- 3.2: the back swings toward BackOpen (eased); held there every frame while it is open.
		if #state.hinges > 0 then
			local target = if car:GetAttribute("BackOpen") == true then 1 else 0
			local before = state.back
			if before ~= target then
				state.back = if target > before then math.min(target, before + dt / BACK_TIME) else math.max(target, before - dt / BACK_TIME)
				-- 6.12: its sound as it starts to move (made to the swing's length) and as it is shut
				local onSwing = CarVisuals.onSwing
				local leaf = state.hinges[1].motor.Part1
				if onSwing and leaf and os.clock() > state.quietUntil then
					if before == 1 - target then
						onSwing(state.backKind, if target == 1 then "opening" else "closing", leaf)
					elseif state.back == 0 then
						onSwing(state.backKind, "shut", leaf)
					end
				end
			end
			if state.back > 0 or before > 0 then
				local t = state.back * state.back * (3 - 2 * state.back)
				for _, hinge in state.hinges do
					if hinge.motor.Parent then
						hinge.motor.Transform = CFrame.fromAxisAngle(hinge.axis, hinge.angle * t)
					end
				end
			end
		end
	end
end

function CarVisuals.start()
	RunService.Stepped:Connect(function(_time, dt)
		step(dt)
	end)
end

return CarVisuals
