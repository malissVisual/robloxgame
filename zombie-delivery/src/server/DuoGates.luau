--!strict
-- The DUO missions' TWIN SWITCHES twist (3.2, Config.Missions.Twists.switches, Config.Missions.Duo). server/Jobs.luau
-- drives it: when a job reaches a gated stop (the last drop, or every pick-up with MissionDef.gates = "pickup") it
-- builds a gate here and blocks the stop (Cargo.setBlocked) until DuoGates.isOpen says the gate is open.
--
-- The gate: two lever posts Config.Missions.Duo.LeverApart studs apart, side by side between the stop's pile and the
-- road, with a red boom bar between them and a sign "TWIN SWITCHES". Each lever has a ProximityPrompt "Pull". A pull
-- holds its lever down (the lamp turns yellow) for LeverWindow seconds; the gate opens only when both levers are down
-- at the same time, pulled by two DIFFERENT players of the job (the `allowed` rule Jobs gives: the owner and the crew).
-- Then the bar swings up, both lamps turn green, and Jobs unblocks the stop. A lever let go springs back up (red).
-- Jobs clears the gate when the stop is done, the job ends or the owner leaves.
--
-- Cheap: a handful of anchored parts per gate, one gate per job at most, no loops (prompt events and task.delay).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DuoGates = {}

type Lever = {
	name: string,
	arm: BasePart,
	lamp: BasePart,
	prompt: ProximityPrompt,
	up: CFrame, -- the arm's resting pose
	down: CFrame, -- pulled
	pulledBy: Player?,
	pulledAt: number, -- os.clock() of the last pull
}

type Gate = {
	owner: Player,
	key: string, -- the stop it guards (Jobs: the stop's index)
	model: Model,
	levers: { Lever },
	bar: BasePart,
	openFrame: CFrame, -- the bar swung up
	open: boolean,
	allowed: (Player) -> boolean,
	changed: () -> (), -- something to send to the HUD (a lever pulled or let go, the gate open)
}

local LAMP_CLOSED = Color3.fromRGB(230, 60, 50)
local LAMP_PULLED = Color3.fromRGB(255, 200, 60)
local LAMP_OPEN = Color3.fromRGB(90, 230, 110)
local POST_COLOR = Color3.fromRGB(70, 72, 80)
local BAR_COLOR = Color3.fromRGB(220, 56, 44)
local BAR_HEIGHT = 3.4 -- studs above the ground
local TOWARD_ROAD = 5 -- the gate stands this far from the pile toward the road
local ARM_TILT = math.rad(38)
local LEVER_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BAR_TWEEN = TweenInfo.new(1.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local gates: { [Player]: Gate } = {}
local folder: Folder? = nil
local notice: RemoteEvent? = nil

local function tell(player: Player, text: string)
	if not notice then
		notice = Net.get("Notice")
	end
	(notice :: RemoteEvent):FireClient(player, text)
end

local function getFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local made = Instance.new("Folder")
	made.Name = "DuoGates"
	made.Parent = workspace
	folder = made
	return made
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- The ground under a point (the stop's pile is at the road's top; a sidewalk or a yard may be a little higher).
local function groundAt(position: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = table.clone(ignore)
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -16, 0), params)
	return if hit then hit.Position.Y else position.Y
end

local function tween(target: Instance, info: TweenInfo, goal: { [string]: any })
	TweenService:Create(target, info, goal):Play()
end

local function setLamp(lever: Lever, color: Color3)
	lever.lamp.Color = color
end

-- The lever springs back up (its pull ran out, or the gate was reset).
local function release(lever: Lever)
	lever.pulledBy = nil
	tween(lever.arm, LEVER_TWEEN, { CFrame = lever.up })
	setLamp(lever, LAMP_CLOSED)
end

local function openGate(gate: Gate)
	if gate.open then
		return
	end
	gate.open = true
	for _, lever in gate.levers do
		lever.prompt.Enabled = false
		tween(lever.arm, LEVER_TWEEN, { CFrame = lever.down })
		setLamp(lever, LAMP_OPEN)
	end
	tween(gate.bar, BAR_TWEEN, { CFrame = gate.openFrame })
	local sign = gate.model:FindFirstChild("Sign", true)
	local label = sign and sign:FindFirstChildWhichIsA("TextLabel")
	if label then
		label.Text = "✅ GATE OPEN"
		label.TextColor3 = LAMP_OPEN
	end
	gate.changed()
end

local function pull(gate: Gate, lever: Lever, player: Player)
	if gate.open or gates[gate.owner] ~= gate then
		return
	end
	if not gate.allowed(player) then
		tell(player, "Only the mission's crew can pull these levers.")
		return
	end
	local window = Config.Missions.Duo.LeverWindow
	local now = os.clock()
	-- The other lever, still held down by somebody else: together!
	for _, other in gate.levers do
		if other ~= lever and other.pulledBy and now - other.pulledAt <= window then
			if other.pulledBy == player then
				tell(player, "Your partner has to pull the other lever at the same time!")
				return
			end
			lever.pulledBy = player
			lever.pulledAt = now
			openGate(gate)
			return
		end
	end
	lever.pulledBy = player
	lever.pulledAt = now
	tween(lever.arm, LEVER_TWEEN, { CFrame = lever.down })
	setLamp(lever, LAMP_PULLED)
	gate.changed()
	-- It springs back unless the other one comes in time.
	task.delay(window, function()
		-- (A gate cleared meanwhile is gone: nothing to reset.)
		if gates[gate.owner] == gate and not gate.open and lever.pulledAt == now and lever.pulledBy == player then
			release(lever)
			tell(player, "Too slow! Both levers at the same moment: count to three together.")
			gate.changed()
		end
	end)
end

local function buildLever(gate: Gate, name: string, base: Vector3, right: Vector3, facing: Vector3): Lever
	local model = gate.model
	local up = Vector3.yAxis
	local post = part(model, `{name}Post`, Vector3.new(0.9, 4.2, 0.9), CFrame.fromMatrix(base + up * 2.1, right, up), POST_COLOR, Enum.Material.Metal)
	post.CanQuery = true -- the prompt's line of sight is off anyway; a click target for touch
	part(model, `{name}Foot`, Vector3.new(1.8, 0.4, 1.8), CFrame.fromMatrix(base + up * 0.2, right, up), POST_COLOR, Enum.Material.Metal)
	local lamp = part(model, `{name}Lamp`, Vector3.new(0.7, 0.7, 0.7), CFrame.new(base + up * 3.2 + facing * 0.55), LAMP_CLOSED, Enum.Material.Neon)
	lamp.Shape = Enum.PartType.Ball
	-- The arm turns about the post's top (around `right`): tilted back at rest, forward when pulled.
	local pivot = CFrame.fromMatrix(base + up * 4.2, right, up)
	local length = 2.6
	local restFrame = pivot * CFrame.Angles(-ARM_TILT, 0, 0) * CFrame.new(0, length / 2, 0)
	local pulledFrame = pivot * CFrame.Angles(ARM_TILT, 0, 0) * CFrame.new(0, length / 2, 0)
	local arm = part(model, `{name}Arm`, Vector3.new(0.32, length, 0.32), restFrame, Color3.fromRGB(40, 40, 44), Enum.Material.Metal)
	local knob = part(arm, "Knob", Vector3.new(0.75, 0.75, 0.75), restFrame * CFrame.new(0, length / 2, 0), BAR_COLOR)
	knob.Shape = Enum.PartType.Ball
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = arm
	weld.Part1 = knob
	weld.Parent = arm
	knob.Anchored = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pull"
	prompt.ObjectText = name
	prompt.HoldDuration = 0 -- 4.0.1: at once
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = post
	local lever: Lever = {
		name = name,
		arm = arm,
		lamp = lamp,
		prompt = prompt,
		up = restFrame,
		down = pulledFrame,
		pulledBy = nil,
		pulledAt = 0,
	}
	prompt.Triggered:Connect(function(player: Player)
		pull(gate, lever, player)
	end)
	return lever
end

-- ── API (server/Jobs.luau) ─────────────────────────────────────────────────

-- Builds the gate of `owner`'s job at a stop (any gate of theirs before is removed): `pile` the stop's pile, `facing`
-- the way its person faces (toward the road). `allowed` = who may pull, `changed` = send the HUD.
function DuoGates.build(owner: Player, key: string, pile: Vector3, facing: Vector3, allowed: (Player) -> boolean, changed: () -> ())
	DuoGates.clear(owner)
	local flat = Vector3.new(facing.X, 0, facing.Z)
	local forward = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	local right = forward:Cross(Vector3.yAxis).Unit
	local apart = Config.Missions.Duo.LeverApart
	local center = pile + forward * TOWARD_ROAD
	local model = Instance.new("Model")
	model.Name = `DuoGate_{owner.UserId}`
	local spotA = center - right * (apart / 2)
	local spotB = center + right * (apart / 2)
	local baseA = Vector3.new(spotA.X, groundAt(spotA, { getFolder() }), spotA.Z)
	local baseB = Vector3.new(spotB.X, groundAt(spotB, { getFolder() }), spotB.Z)
	-- The bar: from post A to post B at BAR_HEIGHT, hinged at A (it swings up when the gate opens).
	local barY = (baseA.Y + baseB.Y) / 2 + BAR_HEIGHT
	local hingeAt = Vector3.new(baseA.X, barY, baseA.Z) + right * 0.6
	local length = math.max(4, apart - 1.2)
	local hinge = CFrame.fromMatrix(hingeAt, right, Vector3.yAxis)
	local closedFrame = hinge * CFrame.new(length / 2, 0, 0)
	local openFrame = hinge * CFrame.Angles(0, 0, math.rad(78)) * CFrame.new(length / 2, 0, 0)
	local bar = part(model, "Bar", Vector3.new(length, 0.45, 0.45), closedFrame, BAR_COLOR)
	-- White bands on the bar (welded, they swing with it).
	for n = 1, 4 do
		local band = part(bar, "Band", Vector3.new(0.9, 0.5, 0.5), closedFrame * CFrame.new(-length / 2 + n * length / 5, 0, 0), Color3.fromRGB(240, 240, 240))
		band.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = bar
		weld.Part1 = band
		weld.Parent = band
	end
	-- The sign over the middle.
	local signPart = part(model, "SignAnchor", Vector3.new(0.2, 0.2, 0.2), CFrame.new(center.X, barY + 3.2, center.Z), BAR_COLOR)
	signPart.Transparency = 1
	local sign = Instance.new("BillboardGui")
	sign.Name = "Sign"
	sign.Size = UDim2.fromOffset(250, 34)
	sign.AlwaysOnTop = false
	sign.MaxDistance = 90
	sign.Parent = signPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(14, 18, 22)
	label.BackgroundTransparency = 0.2
	label.Text = "🎛 TWIN SWITCHES · PULL BOTH TOGETHER"
	label.TextColor3 = LAMP_PULLED
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = sign
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local gate: Gate = {
		owner = owner,
		key = key,
		model = model,
		levers = {},
		bar = bar,
		openFrame = openFrame,
		open = false,
		allowed = allowed,
		changed = changed,
	}
	table.insert(gate.levers, buildLever(gate, "Lever A", baseA, right, forward))
	table.insert(gate.levers, buildLever(gate, "Lever B", baseB, right, forward))
	model.PrimaryPart = bar
	model.Parent = getFolder()
	gates[owner] = gate
end

-- Does `owner`'s job have a gate right now (open or not)?
function DuoGates.has(owner: Player): boolean
	return gates[owner] ~= nil
end

-- Is the gate of `owner`'s job open (true without a gate: nothing blocks)?
function DuoGates.isOpen(owner: Player): boolean
	local gate = gates[owner]
	return gate == nil or gate.open
end

-- How many levers are down right now (0 … 2; 2 = open).
function DuoGates.pulled(owner: Player): number
	local gate = gates[owner]
	if not gate then
		return 0
	end
	if gate.open then
		return 2
	end
	local count = 0
	for _, lever in gate.levers do
		if lever.pulledBy then
			count += 1
		end
	end
	return count
end

-- The HUD's hint while the gate is shut, else nil.
function DuoGates.hint(owner: Player): string?
	local gate = gates[owner]
	if not gate or gate.open then
		return nil
	end
	return `Pull both levers together! ({DuoGates.pulled(owner)}/2) · one of you on each`
end

-- The admin tools: open it now.
function DuoGates.forceOpen(owner: Player)
	local gate = gates[owner]
	if gate then
		openGate(gate)
	end
end

-- Removes the gate of `owner`'s job (the stop is done, the job ended, the owner left). Safe without one.
function DuoGates.clear(owner: Player)
	local gate = gates[owner]
	if not gate then
		return
	end
	gates[owner] = nil
	gate.model:Destroy()
end

return DuoGates
