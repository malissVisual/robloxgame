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
-- line under the middle of the screen says the key. When the piece lands at the door the server says so ("landed"):
-- a banner, "TRICKSHOT! +$n" and what earned it (far, over something, off a wall), or "AT THE DOOR".
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
	bound: boolean,
	aiming: boolean,
	since: number, -- when the aim started (the power swings from there)
	preview: Preview?,
	params: RaycastParams?,
	render: RBXScriptConnection?,
	direction: Vector3?, -- the last frame's aim …
	power: number, -- … and power: what release throws
	gui: ScreenGui?,
	line: TextLabel?,
	banner: Frame?,
}
local state: State = { bound = false, aiming = false, since = 0, power = 0 }

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

-- One frame of the aim: the direction, the power, the arc and the rings.
local function aimFrame()
	local root = rootOnFoot()
	local door = doorSpot()
	local camera = workspace.CurrentCamera
	local preview = state.preview
	local params = state.params
	if not root or not door or not camera or not preview or not params then
		return
	end
	local look = camera.CFrame.LookVector
	local aimed = Throws.aim(vec(look)) or Throws.aim(vec(root.CFrame.LookVector))
	if not aimed then
		return
	end
	local power = Throws.charge(os.clock() - state.since)
	local velocity = Throws.velocity(aimed, power)
	if not velocity then
		return
	end
	state.direction, state.power = v3(aimed), power
	local from = Throws.release(vec(root.Position), vec(root.CFrame.LookVector))
	local trace = Throws.trace(from, velocity, function(a: Throws.Vec, b: Throws.Vec): Throws.Hit?
		local hit = workspace:Raycast(v3(a), v3(b) - v3(a), params)
		return if hit then { at = vec(hit.Position), normal = vec(hit.Normal) } else nil
	end)
	for i, dot in preview.dots do
		dot.CFrame = CFrame.new(v3(Throws.at(trace, trace.time * i / (#preview.dots + 1))))
	end
	local land = v3(trace.land)
	local hits = trace.grounded and Throws.landed(trace.land, vec(door))
	preview.ring.CFrame = CFrame.new(land + Vector3.new(0, 0.08, 0)) * FLAT_DISC
	preview.ring.Color = if hits then K.good else K.text
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
end

local function startAim()
	local root = rootOnFoot()
	local door = doorSpot()
	if not root or not door then
		return
	end
	if player:GetAttribute("ThrowFragile") == true then
		say("Too fragile to throw: hand it over at the door.")
		return
	end
	if flat(root.Position, door) > T.Range then
		say(`Too far to throw: come within {T.Range} studs of the door.`)
		return
	end
	local preview = showPreview()
	state.params = rayParams(preview)
	state.aiming = true
	state.since = os.clock()
	state.direction = nil
	if not state.render then
		state.render = RunService.RenderStepped:Connect(aimFrame)
	end
	aimFrame()
end

local function release()
	if not state.aiming then
		return
	end
	aimFrame()
	local direction = state.direction
	local stop = player:GetAttribute("ThrowStop")
	stopAim()
	if direction and type(stop) == "number" and doorSpot() and rootOnFoot() then
		Net.get("Throw"):FireServer(stop, direction, state.power)
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
local function screen(): ScreenGui?
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
	local want = door ~= nil and root ~= nil
	if want and not state.bound then
		state.bound = true
		ContextActionService:BindActionAtPriority(ACTION, onAction, true, Enum.ContextActionPriority.High.Value, Enum.KeyCode.X, Enum.KeyCode.ButtonR1)
		ContextActionService:SetTitle(ACTION, "THROW")
	elseif not want and state.bound then
		state.bound = false
		stopAim()
		ContextActionService:UnbindAction(ACTION)
	end
	if door and root and not state.aiming and flat(root.Position, door) <= T.Range then
		showLine(if player:GetAttribute("ThrowFragile") == true then "Too fragile to throw: hand it over at the door"
			else `{keyText()} to throw it at the door · trickshots tip`)
	elseif state.aiming then
		showLine("Release to throw · the ring goes green over the door")
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
	local parts: { string } = {}
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
	title.TextColor3 = if tip > 0 then K.warn else K.text
	title.TextStrokeColor3 = K.charcoal
	title.TextStrokeTransparency = 0.3
	title.Text = if tip > 0 then `TRICKSHOT! +${tip}` else "AT THE DOOR!"
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
