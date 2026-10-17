--!strict
-- What every client does for every van (the run's truck parked at its house's curb, server/Runs.luau; nobody drives
-- since 10.0): the back that opens (rear doors, a roll-up door, a tailgate: the Motor6Ds "BackHinge" on the chassis,
-- server/Vehicles.luau) swings toward the car's attribute BackOpen, a short eased swing; the back's prompt shows only
-- to the owner and the crew (the attribute BackCrew); its cabin doors' prompts (Drive, Ride along) stay off (9.7: a
-- run's truck is never driven nor ridden, its seats off); the owner's name sits over other players' vans on a cream
-- pill in ink (Theme.Postage.pill).
-- 6.12: says when the back starts to open or to close and when it is shut (CarVisuals.onSwing, set by
-- client/SoundScape.luau: the back's sounds where it is); the back's kind (two rear doors, a roll-up door, a tailgate)
-- from its hinge (shared/SoundPlan.luau backKind). A van just seen (streamed in, its back already open) stays quiet its
-- first second.
-- 6.13.1 (performance): the prompts and the name tags are looked at PROMPT_EVERY seconds (not every frame); only the vans
-- within RANGE of the camera swing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SoundPlan = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundPlan"))

local Theme = require(script.Parent.Theme)
local DeviceBudget = require(script.Parent.DeviceBudget)

local CarVisuals = {}

-- 6.12: set by client/SoundScape.luau. what: the back's kind (SoundPlan.backKind); moment: "opening" (it starts to open),
-- "closing" (it starts to close) or "shut"; part: the leaf that moves.
CarVisuals.onSwing = nil :: ((what: string, moment: string, part: BasePart) -> ())?

type Hinge = { motor: Motor6D, axis: Vector3, angle: number } -- angle: the open turn in radians
type CarState = {
	hinges: { Hinge },
	doorPrompts: { ProximityPrompt },
	back: number,
	tagged: boolean,
	backReach: number?, -- the BackPrompt's own reach (the server's), before it was hidden here
	-- 6.12: the back's kind for its sounds, and no sounds before this (os.clock: a van just seen).
	backKind: string,
	quietUntil: number,
}

local player = Players.LocalPlayer
local states: { [Model]: CarState } = {}
local RANGE = 260
local PROMPT_EVERY = 0.1 -- 6.13.1: seconds between the looks at the prompts
local promptClock = { at = 0 }
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
	local hinges: { Hinge } = {}
	local doorPrompts: { ProximityPrompt } = {}
	local backKind = "swing"
	for _, child in chassis:GetChildren() do
		if child:IsA("Motor6D") and child.Name == "BackHinge" then
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
		elseif child:IsA("Attachment") and string.sub(child.Name, 1, 4) == "Door" then
			local prompt = child:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				table.insert(doorPrompts, prompt)
			end
		end
	end
	state = {
		hinges = hinges,
		doorPrompts = doorPrompts,
		back = 0,
		tagged = false,
		backReach = nil,
		backKind = backKind,
		quietUntil = os.clock() + 1,
	}
	states[car] = state
	car.Destroying:Connect(function()
		states[car] = nil
	end)
	return state
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
	label.Text = `{car:GetAttribute("OwnerName") or "?"}'s van`
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

-- 5.9.2: every van, one list kept and built again only when a van comes or goes (no new table every frame).
local carList: { Instance } = {}
local carFolder: { folder: Instance? } = { folder = nil }
local carListDirty = true

local function allCars(): { Instance }
	local known = carFolder.folder
	if not (known and known.Parent == workspace) then
		local folder = workspace:FindFirstChild("Cars")
		if folder ~= known then
			carListDirty = true
			carFolder.folder = folder
			if folder then
				local function changed()
					carListDirty = true
				end
				folder.ChildAdded:Connect(changed)
				folder.ChildRemoved:Connect(function(child: Instance)
					carListDirty = true
					-- 6.13.1 (StreamingEnabled): a van that streams out is forgotten here too
					if child:IsA("Model") then
						states[child] = nil
					end
				end)
			end
		end
	end
	if carListDirty then
		carListDirty = false
		table.clear(carList)
		local folder = carFolder.folder
		if folder then
			for _, car in folder:GetChildren() do
				table.insert(carList, car)
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
	-- 6.13.1: the prompts a few times a second; the range a phone's
	local clock = os.clock()
	local prompts = clock - promptClock.at >= PROMPT_EVERY
	if prompts then
		promptClock.at = clock
	end
	local range = DeviceBudget.range(RANGE)
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

		if prompts then
			-- The cabin doors: nobody gets in (9.7 runs: a truck parked at a run's house is never driven nor ridden).
			for _, prompt in state.doorPrompts do
				if prompt.Enabled then
					prompt.Enabled = false
				end
			end
			-- 3.2: the back's prompt only for the owner and the crew (the car's BackCrew); out of reach for everybody else,
			-- so a stranger's van does not take the E. (Enabled is the server's: one E at a time.)
			local door = chassis:FindFirstChild("CargoDoor")
			local back = door and door:FindFirstChild("BackPrompt")
			local crew = car:GetAttribute("BackCrew")
			local usable = mine or (type(crew) == "string" and string.find(`,{crew},`, `,{player.UserId},`, 1, true) ~= nil)
			if back and back:IsA("ProximityPrompt") then
				local reach: number = state.backReach or back.MaxActivationDistance
				state.backReach = reach
				local want = if usable then reach else 0
				if back.MaxActivationDistance ~= want then
					back.MaxActivationDistance = want
				end
			end
			if not mine and not state.tagged and car:GetAttribute("OwnerId") ~= nil then
				state.tagged = true
				nameTag(car, chassis)
			end
		end

		if (chassis.Position - eye).Magnitude > range then
			continue
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
