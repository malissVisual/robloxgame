--!strict
-- 6.0: throwing a delivery at a home's door, the aim (the server decides: server/Cargo.luau, the "Throw" remote).
-- While the server says a throw is possible (your player's ThrowTo attribute: the door's spot, with ThrowStop and
-- ThrowFragile) and you are on foot, X (a gamepad's R1; on a touch screen Roblox's action button THROW) is bound:
--   * hold it: a dotted arc from your hand shows where the piece lands (the same maths and rays the server uses,
--     shared/Throws.luau), the landing ring turns green over the door's spot (Config.Throw.DoorRadius, its own ring
--     shows meanwhile); the power swings from the weakest to the strongest and back while you hold
--     (Throws.charge); the camera aims: where you look, lifted by Config.Throw.Lift;
--   * release: thrown (direction and power to the server).
-- Too far (Config.Throw.Range) or only fragile pieces: a toast says so and nothing is aimed. Within the range a quiet
-- line under the middle of the screen says the key.
-- 6.1 (the owner: "after pressing X nothing shows"): X was bound only while the server's ThrowTo was set (a home's
-- door is the current stop and a piece for it is with you), so anywhere else it did nothing at all. Now it is bound
-- whenever you could throw at all (the server's ThrowReady: a light piece in your hands, or the bag in your hand with
-- one in it; or the bag in your hand, or a ThrowTo) and a press without a door in range says why (Holding.throwText:
-- "Get within 45 studs of the delivery door to throw", "Too fragile to throw", "Nothing to throw"). When the piece lands at the door the server says so ("landed"):
-- a banner, "TRICKSHOT! +$n" and what earned it (far, over something, off a wall), or "AT THE DOOR".
-- 6.2, the auto-aim (the owner: "auto aim, and a perfect hit gets a bigger tip from the customer"): the camera no
-- longer aims. Pressing X picks the throw's angle (the first of Config.Throw.AutoAngles whose solved arc, traced with
-- the world's rays, comes down on the door: over a fence when it has to), turns your body to the door and keeps the
-- arc on it; you only time the power. A meter over the line shows the swinging power, the green zone (it lands at the
-- door) and the gold PERFECT zone (within PerfectRadius of the door's spot: the customer tips PerfectTip; the server
-- decides, server/Cargo.luau throwAt). The banner says "PERFECT! Customer tip +$n".
-- Nothing runs per frame unless you aim; the binding and the line are looked at every CHECK seconds.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Throws = require(Shared.Throws)
local Holding = require(Shared.Holding) -- 6.1: what X says
local Theme = require(script.Parent.Theme)

local Throw = {}

-- A toast (client/Hud.luau's, set by Main).
Throw.notify = nil :: ((string) -> ())?

local ACTION = "ZDThrow"
local CHECK = 0.2 -- seconds between the looks at the binding and the line
local T = Config.Throw
local K = Theme.Contract
local player = Players.LocalPlayer

type Preview = { folder: Folder, dots: { BasePart }, ring: BasePart, door: BasePart }
type State = {
	bound: string?,
	aiming: boolean,
	since: number, -- when the aim started (the power swings from there)
	preview: Preview?,
	params: RaycastParams?,
	render: RBXScriptConnection?,
	direction: Vector3?, -- the last frame's aim …
	power: number, -- … and power: what release throws
	angle: number, -- 6.2: the auto-aim's angle (degrees over the flat) for this throw
	clear: boolean, -- 6.2 review: its arc reaches the door (else the meter's zones are not shown: something is in the way)
	zonedFrom: Vector3?, -- 6.2 review: the release point the meter's zones were laid out from
	from: Vector3?, -- 6.2 review: the last frame's release point (sent with the throw)
	meter: Frame?, -- 6.2: the power meter (its Needle, Green and Gold frames)
	gui: ScreenGui?,
	line: TextLabel?,
	banner: Frame?,
}
local state: State = { bound = nil, aiming = false, since = 0, power = 0, angle = 45, clear = false }
local HOLD_STILL = "ZDThrowHoldStill" -- 6.2 review: no walking while aiming (the zones are laid out from where you stand)

local function say(text: string)
	local notify = Throw.notify
	if notify then
		notify(text)
	end
end

local function vec(v: Vector3): Throws.Vec
	return { v.X, v.Y, v.Z }
end

local function v3(v: Throws.Vec): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

-- The door's spot while a throw is possible (the server's ThrowTo), else nil.
local function doorSpot(): Vector3?
	local to = player:GetAttribute("ThrowTo")
	return if typeof(to) == "Vector3" then to else nil
end

-- Your body on foot and alive (nil seated, dead, missing).
local function rootOnFoot(): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart ~= nil or not root or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- The rays of the preview: the world only, like the server's (the people, the cargo and the preview let it through).
local function rayParams(preview: Preview): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local skip: { Instance } = { preview.folder }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(skip, other.Character)
		end
	end
	for _, name in { "Cargo", "Npcs", "Zombies", "Animals", "Effects", "Loot" } do
		local child = workspace:FindFirstChild(name)
		if child then
			table.insert(skip, child)
		end
	end
	params:AddToFilter(skip)
	return params
end

local function marker(parent: Instance, name: string, size: Vector3, color: Color3, shape: Enum.PartType): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
	part.Parent = parent
	return part
end

-- The dotted arc, the landing ring and the door's ring (local parts under the camera: nobody else sees them).
local function showPreview(): Preview
	local existing = state.preview
	if existing and existing.folder.Parent then
		existing.folder.Parent = workspace.CurrentCamera
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "ThrowPreview"
	local dots: { BasePart } = {}
	for i = 1, T.Dots do
		local dot = marker(folder, "Dot", Vector3.new(0.32, 0.32, 0.32), K.text, Enum.PartType.Ball)
		dot.Transparency = 0.15 + 0.5 * i / T.Dots
		table.insert(dots, dot)
	end
	local ring = marker(folder, "Landing", Vector3.new(0.12, 2.6, 2.6), K.text, Enum.PartType.Cylinder)
	ring.Transparency = 0.25
	local door = marker(folder, "Door", Vector3.new(0.08, T.DoorRadius * 2, T.DoorRadius * 2), K.warn, Enum.PartType.Cylinder)
	door.Transparency = 0.7
	folder.Parent = workspace.CurrentCamera
	local made: Preview = { folder = folder, dots = dots, ring = ring, door = door }
	state.preview = made
	return made
end

local function hidePreview()
	local preview = state.preview
	if preview then
		preview.folder.Parent = nil
	end
end

local FLAT_DISC = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder lying flat (its axis up)

local screen: () -> ScreenGui? -- (the line and the banner's ScreenGui: further down)

-- 6.2: turn the body to the door (flat): the release point the server computes from your facing is the one aimed from.
local function faceDoor(root: BasePart, door: Vector3)
	local flatDoor = Vector3.new(door.X, root.Position.Y, door.Z)
	if (flatDoor - root.Position).Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, flatDoor)
	end
end

-- 6.2: the auto-aim's angle for this throw: the first AutoAngles angle whose solved arc (a throw at its PERFECT power)
-- comes down on the door with the world's rays; else the first one the power can reach (it may bounce off something:
-- a trickshot by luck); nil when none can.
local function pickAngle(from: Throws.Vec, door: Vector3, params: RaycastParams): (number?, boolean)
	local fallback: number? = nil
	for _, angle in T.AutoAngles do
		local speed = Throws.solve(from, vec(door), angle)
		local power = speed and Throws.powerFor(speed)
		local direction = Throws.direction(from, vec(door), angle)
		local velocity = power and direction and Throws.velocity(direction, power)
		if velocity then
			fallback = fallback or angle
			local trace = Throws.trace(from, velocity, function(a: Throws.Vec, b: Throws.Vec): Throws.Hit?
				local hit = workspace:Raycast(v3(a), v3(b) - v3(a), params)
				return if hit then { at = vec(hit.Position), normal = vec(hit.Normal) } else nil
			end)
			if trace.grounded and Throws.landed(trace.land, vec(door)) then
				return angle, true
			end
		end
	end
	return fallback, false
end

-- 6.2: the power meter: the bar, the green zone (lands at the door), the gold zone (PERFECT) and the needle.
local function meterFrame(): Frame?
	local existing = state.meter
	if existing and existing.Parent then
		return existing
	end
	local gui = screen()
	if not gui then
		return nil
	end
	local bar = Instance.new("Frame")
	bar.Name = "PowerMeter"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -266) -- (over the line)
	bar.Size = UDim2.fromOffset(260, 14)
	bar.BackgroundColor3 = K.charcoal
	bar.BackgroundTransparency = 0.25
	bar.BorderSizePixel = 0
	bar.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = bar
	local stroke = Instance.new("UIStroke")
	stroke.Color = K.text
	stroke.Transparency = 0.6
	stroke.Parent = bar
	local function zone(name: string, color: Color3, order: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundColor3 = color
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromScale(0, 1)
		frame.ZIndex = order
		frame.Parent = bar
		return frame
	end
	zone("Green", K.good, 2).BackgroundTransparency = 0.35
	zone("Gold", K.warn, 3)
	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.Position = UDim2.fromScale(0, 0.5)
	needle.Size = UDim2.new(0, 3, 1, 8)
	needle.BackgroundColor3 = K.text
	needle.BorderSizePixel = 0
	needle.ZIndex = 4
	needle.Parent = bar
	local label = Instance.new("TextLabel")
	label.Name = "Perfect"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Size = UDim2.fromOffset(80, 14)
	label.BackgroundTransparency = 1
	label.Font = Theme.HeadingFont
	label.TextSize = 11
	label.TextColor3 = K.warn
	label.TextStrokeTransparency = 0.5
	label.Text = "PERFECT"
	label.ZIndex = 4
	label.Parent = bar
	bar.Parent = gui
	state.meter = bar
	return bar
end

-- A zone of powers (0 … 1, by 0.01) where `hits` holds on the parabola at the door's height: its first and last.
local function zoneOf(from: Throws.Vec, direction: Throws.Vec, door: Vector3, hits: (Throws.Vec, Throws.Vec) -> boolean): (number?, number?)
	local first: number?, last: number? = nil, nil
	for i = 0, 100 do
		local power = i / 100
		local velocity = Throws.velocity(direction, power)
		local land = velocity and Throws.landFlat(from, velocity, door.Y)
		if land and hits(land, vec(door)) then
			first = first or power
			last = power
		end
	end
	return first, last
end

local function setZone(bar: Frame, name: string, first: number?, last: number?)
	local frame = bar:FindFirstChild(name)
	if not frame or not frame:IsA("Frame") then
		return
	end
	frame.Visible = first ~= nil
	if first and last then
		frame.Position = UDim2.fromScale(first, 0)
		frame.Size = UDim2.fromScale(math.max(0.012, last - first + 0.01), 1)
	end
end

-- 6.2: the meter's zones for this throw (once, when the aim starts: the angle is fixed, the body turned).
local function showZones(from: Throws.Vec, door: Vector3)
	local bar = meterFrame()
	local direction = Throws.direction(from, vec(door), state.angle)
	if not bar or not direction then
		return
	end
	state.zonedFrom = v3(from)
	local g0: number?, g1: number?, p0: number?, p1: number? = nil, nil, nil, nil
	if state.clear then -- (6.2 review: something in the way: the ring alone tells)
		g0, g1 = zoneOf(from, direction, door, Throws.landed)
		if player:GetAttribute("ThrowToss") ~= true then -- (a round's papers: no PERFECT tip)
			p0, p1 = zoneOf(from, direction, door, Throws.perfect)
		end
	end
	setZone(bar, "Green", g0, g1)
	setZone(bar, "Gold", p0, p1)
	local label = bar:FindFirstChild("Perfect")
	if label and label:IsA("TextLabel") then
		label.Visible = p0 ~= nil
		label.Position = UDim2.new(if p0 and p1 then (p0 + p1) / 2 else 0.5, 0, 0, -2)
	end
	bar.Visible = true
end

-- One frame of the aim: the direction (6.2: auto, at the door), the power, the arc and the rings.
local function aimFrame()
	local root = rootOnFoot()
	local door = doorSpot()
	local camera = workspace.CurrentCamera
	local preview = state.preview
	local params = state.params
	if not root or not door or not camera or not preview or not params then
		return
	end
	faceDoor(root, door)
	local from = Throws.release(vec(root.Position), vec(root.CFrame.LookVector))
	local aimed = Throws.direction(from, vec(door), state.angle)
	if not aimed then
		return
	end
	local power = Throws.charge(os.clock() - state.since)
	local velocity = Throws.velocity(aimed, power)
	if not velocity then
		return
	end
	state.direction, state.power, state.from = v3(aimed), power, v3(from)
	local zoned = state.zonedFrom
	if zoned and (zoned - v3(from)).Magnitude > 0.2 then
		showZones(from, door) -- (6.2 review: the body moved anyway: the zones follow)
	end
	local meter = state.meter
	if meter then
		local needle = meter:FindFirstChild("Needle")
		if needle and needle:IsA("Frame") then
			needle.Position = UDim2.fromScale(power, 0.5)
		end
	end
	local trace = Throws.trace(from, velocity, function(a: Throws.Vec, b: Throws.Vec): Throws.Hit?
		local hit = workspace:Raycast(v3(a), v3(b) - v3(a), params)
		return if hit then { at = vec(hit.Position), normal = vec(hit.Normal) } else nil
	end)
	for i, dot in preview.dots do
		dot.CFrame = CFrame.new(v3(Throws.at(trace, trace.time * i / (#preview.dots + 1))))
	end
	local land = v3(trace.land)
	local hits = trace.grounded and Throws.landed(trace.land, vec(door))
	local perfect = hits and Throws.perfect(trace.land, vec(door))
	preview.ring.CFrame = CFrame.new(land + Vector3.new(0, 0.08, 0)) * FLAT_DISC
	preview.ring.Color = if perfect then K.warn elseif hits then K.good else K.text
	preview.door.CFrame = CFrame.new(door + Vector3.new(0, 0.06, 0)) * FLAT_DISC
end

local function stopAim()
	state.aiming = false
	local render = state.render
	if render then
		render:Disconnect()
		state.render = nil
	end
	hidePreview()
	local meter = state.meter
	if meter then
		meter.Visible = false
	end
	ContextActionService:UnbindAction(HOLD_STILL)
end

local function startAim()
	local root = rootOnFoot()
	local door = doorSpot()
	if not root then
		return
	end
	-- 6.1: no door here, too far, too fragile, nothing to throw: say so (else aim).
	local ready = player:GetAttribute("ThrowReady")
	local text = Holding.throwText(if type(ready) == "string" then ready else nil, door ~= nil, door ~= nil and flat(root.Position, door) > T.Range,
		player:GetAttribute("ThrowFragile") == true, T.Range)
	if text or not door then
		say(text or `Get within {T.Range} studs of the delivery door to throw.`)
		return
	end
	local preview = showPreview()
	local params = rayParams(preview)
	state.params = params
	-- 6.2: the auto-aim: face the door, pick the angle, lay out the meter's zones
	faceDoor(root, door)
	local from = Throws.release(vec(root.Position), vec(root.CFrame.LookVector))
	local angle, clear = pickAngle(from, door, params)
	if not angle then
		hidePreview()
		say("Too close or too high to throw from here: step back a little.")
		return
	end
	state.angle, state.clear = angle, clear
	showZones(from, door)
	-- 6.2 review: stand still while aiming (the keys and the gamepad's stick; the zones follow if you move anyway)
	ContextActionService:BindActionAtPriority(HOLD_STILL, function(): Enum.ContextActionResult
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Thumbstick1, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	state.aiming = true
	state.since = os.clock()
	state.direction, state.from = nil, nil
	if not state.render then
		state.render = RunService.RenderStepped:Connect(aimFrame)
	end
	aimFrame()
end

local function release()
	if not state.aiming then
		return
	end
	-- (6.2 review: the power of the last drawn frame, the needle you let go on; no new frame here)
	local direction = state.direction
	local from = state.from
	local stop = player:GetAttribute("ThrowStop")
	stopAim()
	if direction and type(stop) == "number" and doorSpot() and rootOnFoot() then
		Net.get("Throw"):FireServer(stop, direction, state.power, from)
	end
end

local function onAction(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		startAim()
	elseif inputState == Enum.UserInputState.End then
		release()
	elseif inputState == Enum.UserInputState.Cancel then
		stopAim()
	end
	return Enum.ContextActionResult.Sink
end

-- The quiet line under the middle of the screen, and the landing banner (one ScreenGui of this module's).
screen = function(): ScreenGui?
	local existing = state.gui
	if existing and existing.Parent then
		return existing
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ThrowUi"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0.5, 1)
	line.Position = UDim2.new(0.5, 0, 1, -232) -- (6.0.1: over the bottom bar, the action and the breath bar)
	line.Size = UDim2.fromOffset(0, 26)
	line.AutomaticSize = Enum.AutomaticSize.X
	line.BackgroundColor3 = K.charcoal
	line.BackgroundTransparency = K.scrim
	line.BorderSizePixel = 0
	line.Font = Theme.HeadingFont
	line.TextSize = 14
	line.TextColor3 = K.text
	line.Visible = false
	line.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = line
	gui.Parent = playerGui
	state.gui, state.line = gui, line
	return gui
end

-- The key's words for this device.
local function keyText(): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Hold THROW"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Hold R1"
	end
	return "Hold [X]"
end

local function showLine(text: string?)
	local line = state.line
	if not text then
		if line then
			line.Visible = false
		end
		return
	end
	if not screen() then
		return
	end
	local shown = state.line
	if shown then
		shown.Text = text
		shown.Visible = true
	end
end

-- Every CHECK seconds: bind the key while a throw is possible, say it within the range.
local function check()
	local door = doorSpot()
	local root = rootOnFoot()
	-- 6.1: bound whenever you could throw at all. "full" (a door's ThrowTo, a throwable piece): X, R1 and the touch THROW
	-- button; "explain" (only the bag in your hand, or only fragile pieces): X alone, for the toast that says why (review:
	-- no THROW button on screen and no R1 taken all the time)
	local character = player.Character
	local want: string? = nil
	if root ~= nil then
		if door ~= nil or player:GetAttribute("ThrowReady") == "piece" then
			want = "full"
		elseif player:GetAttribute("ThrowReady") ~= nil or (character ~= nil and character:GetAttribute("Hand") == "bag") then
			want = "explain"
		end
	end
	if want ~= state.bound then
		if state.bound ~= nil then
			ContextActionService:UnbindAction(ACTION)
		end
		state.bound = want
		if want ~= "full" then
			stopAim()
		end
		if want == "full" then
			ContextActionService:BindActionAtPriority(ACTION, onAction, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.X, Enum.KeyCode.ButtonR1)
			ContextActionService:SetTitle(ACTION, "THROW")
		elseif want == "explain" then
			ContextActionService:BindActionAtPriority(ACTION, onAction, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.X)
		end
	end
	if door and root and not state.aiming and flat(root.Position, door) <= T.Range then
		showLine(if player:GetAttribute("ThrowFragile") == true then "Too fragile to throw: hand it over at the door"
			elseif player:GetAttribute("ThrowToss") == true then `{keyText()} to toss it at the door`
			else `{keyText()} to throw it at the door · let go in the gold zone for a PERFECT tip`)
	elseif state.aiming then
		showLine(if state.clear and player:GetAttribute("ThrowToss") ~= true then "Let go in the gold zone: PERFECT"
			else "Let go when the ring is on the door")
	else
		showLine(nil)
	end
end

-- The banner when the piece lands at the door.
local function landed(info: any)
	if type(info) ~= "table" then
		return
	end
	local gui = screen()
	if not gui then
		return
	end
	local old = state.banner
	if old then
		old:Destroy()
	end
	local tip = tonumber(info.tip) or 0
	local perfect = tonumber(info.perfect) or 0 -- 6.2: the customer's PERFECT tip (0: none, or the job's cap reached)
	local isPerfect = info.isPerfect == true
	local parts: { string } = {}
	if isPerfect then
		table.insert(parts, if perfect > 0 then `CUSTOMER TIP +${perfect}` else "RIGHT ON THE MAT")
	end
	local far, over, wall = tonumber(info.far) or 0, tonumber(info.over) or 0, tonumber(info.wall) or 0
	if far > 0 then
		table.insert(parts, `FAR {tonumber(info.span) or 0} STUDS +${far}`)
	end
	if over > 0 then
		table.insert(parts, `OVER IT +${over}`)
	end
	if wall > 0 then
		table.insert(parts, `OFF THE WALL +${wall}`)
	end
	local frame = Instance.new("Frame")
	frame.Name = "Landed"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.fromScale(0.5, 0.2)
	frame.Size = UDim2.fromOffset(420, 70)
	frame.BackgroundTransparency = 1
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 42)
	title.BackgroundTransparency = 1
	title.Font = Theme.DisplayFont
	title.TextSize = 36
	title.TextColor3 = if tip > 0 or isPerfect then K.warn else K.text
	title.TextStrokeColor3 = K.charcoal
	title.TextStrokeTransparency = 0.3
	title.Text = if isPerfect then (if tip + perfect > 0 then `PERFECT! +${tip + perfect}` else "PERFECT!")
		elseif tip > 0 then `TRICKSHOT! +${tip}`
		else "AT THE DOOR!"
	title.Parent = frame
	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromOffset(0, 42)
	sub.Size = UDim2.new(1, 0, 0, 22)
	sub.BackgroundTransparency = 1
	sub.Font = Theme.HeadingFont
	sub.TextSize = 15
	sub.TextColor3 = K.text
	sub.TextStrokeColor3 = K.charcoal
	sub.TextStrokeTransparency = 0.4
	sub.Text = if #parts > 0 then table.concat(parts, "  ·  ") else `{tonumber(info.span) or 0} studs`
	sub.Parent = frame
	frame.Parent = gui
	state.banner = frame
	task.delay(1.8, function()
		if frame.Parent then
			local fade = TweenInfo.new(0.4)
			TweenService:Create(title, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(sub, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.45, function()
				frame:Destroy()
			end)
		end
	end)
end

function Throw.start()
	Net.get("Throw").OnClientEvent:Connect(function(kind: any, info: any)
		if kind == "landed" then
			landed(info)
		end
	end)
	player.CharacterAdded:Connect(function()
		stopAim()
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK)
			local ok, err = pcall(function()
				check()
			end)
			if not ok then
				warn(`[Throw] {err}`)
			end
		end
	end)
end

return Throw
