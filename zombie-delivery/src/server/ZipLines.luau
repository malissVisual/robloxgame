--!strict
-- 5.6, the zip lines between Downtown's rooftops (shared/ZipLines.luau has where; Config.ZipLines the numbers).
--
-- Built when this starts (after World), at most 30 native parts a line (28): on each of its two roofs a landing
-- platform (a floor, a red rail on three sides, open toward the cable, the back one in two pieces since 6.10, a gantry
-- of two posts and a crossbar the cable hangs from; the start's with a ZIP sign and a lamp that glows at night), a
-- ladder (a TrussPart against the street wall) and the cable in 8 black segments along its sag. The roof boxes World
-- put where a platform stands are taken off. A Model per line in workspace.World.ZipLines (Atomic streaming).
--
-- 6.10 (the owner: "like a building you climb up by yourself, and onto the zip line you just jump"): the ladders are
-- real. Each truss is solid and queried, so the Humanoid climbs it by itself (Roblox's own climb and its animation),
-- from the sidewalk to a little over the roof (shared/ZipLines.luau truss). You walk across the roof and onto the
-- platform through the gap in the middle of its back rail (RailGap; the floor is 0.5 up). Getting down is yours too:
-- the ladder again, or a jump (no fall damage). The 5.7 climbs are gone: the "Climb" and "Climb down" prompts, the
-- route every client played and the end the server set.
-- A ride starts with the "Zip" prompt in the start platform's middle (PromptReach: from anywhere on it) or with a jump
-- there (the Zip remote's "grab" with the line's id; client/ZipRide.luau asks only on the platform). Both are checked
-- the same here: alive, on foot (not seated, not getting in), not on a ride already, past the Cooldown, where
-- ZipLines.canStart allows it (within Reach of the platform's middle, the feet from the roof up to a jump over the
-- floor, not on the ladder), nothing in the hands and no trolley ("Hands full: pack it first"; the bag's pieces ride
-- along). The character's attributes ZipLine (the line's id) and ZipAt (the server time it starts) tell every client:
-- the rider's own one moves the body along the cable (shared/ZipLines.luau ZipLines.at), every one poses the hands up
-- on a trolley. The end is the server's: Grace seconds after the ride's end a rider who is not at the end platform is
-- put there (no teleporting off a cable). The Zip remote's "letgo" (Space) ends it early only where ZipLines.canLetGo
-- allows it (low over one of the line's roofs); anywhere else it is ignored. A death, a reset or leaving ends it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local ZipData = require(Shared.ZipLines)
local Vehicles = require(script.Parent.Vehicles)
local Cargo = require(script.Parent.Cargo)
local DayNight = require(script.Parent.DayNight)
local Tasks = require(script.Parent.Tasks) -- 6.12: a ride counts for the zip-line task

local ZipLines = {}

local Tuning = Config.ZipLines
local TICK = 0.1
local SEGMENTS = 8
local LEAD = 0.15 -- seconds between the Zip and the ride's start (the attributes reach the client first)
local CABLE = Color3.fromRGB(22, 22, 24)
local METAL = Color3.fromRGB(40, 42, 46)
local FLOOR = Color3.fromRGB(96, 98, 100)
local RED = Color3.fromRGB(196, 52, 46)
local LAMP_LIT = Color3.fromRGB(255, 226, 170)
local LAMP_DIM = Color3.fromRGB(120, 120, 116)

type Ride = { line: ZipData.Line, start: number, character: Model }

local rides: { [Player]: Ride } = {}
local lastRide: { [Player]: number } = {} -- (the end of a ride: the Cooldown before the next)
local started = false

local function tell(player: Player, text: string)
	Net.get("Notice"):FireClient(player, text)
end

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.Parent = parent
	return p
end

local function prompt(parent: Instance, name: string, action: string, object: string, hold: number, reach: number): ProximityPrompt
	local holder = Instance.new("Attachment")
	holder.Name = name
	holder.Parent = parent
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.MaxActivationDistance = reach
	p.RequiresLineOfSight = false
	p.Parent = holder
	return p
end

local function signFace(board: BasePart, face: Enum.NormalId, line: ZipData.Line)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Parent = board
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(24, 27, 32)
	back.BorderSizePixel = 0
	back.Parent = gui
	local function row(text: string, y: number, h: number, font: Enum.Font, color: Color3)
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0.9, 0, h, 0)
		label.Position = UDim2.new(0.05, 0, y, 0)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = font
		label.TextColor3 = color
		label.Parent = back
	end
	row("ZIP ⇢", 0.08, 0.56, Enum.Font.GothamBlack, Color3.fromRGB(242, 242, 240))
	row(string.upper(line.ladderA.street), 0.66, 0.26, Enum.Font.GothamMedium, Color3.fromRGB(169, 174, 180))
end

-- Takes off the roof boxes World stood where a platform goes.
local function clearRoof(world: Instance, platform: ZipData.Platform)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { world }
	local size = Vector3.new(Tuning.Platform + 1, 8, Tuning.Platform + 1)
	for _, hit in workspace:GetPartBoundsInBox(CFrame.new(platform.x, platform.floor + 3, platform.z), size, params) do
		if hit.Name == "RoofBox" then
			hit:Destroy()
		end
	end
end

-- A platform: the floor, the rail (open toward the cable; 6.10: its back in two pieces, a RailGap between them to walk
-- in through from the roof), the gantry over its middle. Returns its frame (-Z toward the cable, the origin on the
-- floor's middle) and its floor.
local function platform(model: Instance, p: ZipData.Platform, start: boolean, line: ZipData.Line): (CFrame, BasePart)
	local P = Tuning.Platform
	local centre = Vector3.new(p.x, p.floor, p.z)
	local frame = CFrame.lookAt(centre, centre + Vector3.new(p.fx, 0, p.fz))
	local floor = part(model, "Floor", Vector3.new(P, 0.5, P), frame * CFrame.new(0, -0.25, 0), FLOOR, Enum.Material.DiamondPlate, true)
	local back = (P - Tuning.RailGap) / 2
	for _, side in { -1, 1 } do
		part(model, "Rail", Vector3.new(back, 1.1, 0.2), frame * CFrame.new(side * (P - back) / 2, 0.55, P / 2 - 0.1), RED, Enum.Material.Metal, true)
	end
	for _, side in { -1, 1 } do
		part(model, "Rail", Vector3.new(0.2, 1.1, P), frame * CFrame.new(side * (P / 2 - 0.1), 0.55, 0), RED, Enum.Material.Metal, true)
	end
	local h = Tuning.CableHeight
	for _, side in { -1, 1 } do
		part(model, "GantryPost", Vector3.new(0.35, h + 0.6, 0.35), frame * CFrame.new(side * (P / 2 - 0.35), (h + 0.6) / 2, 0), METAL, Enum.Material.Metal, true)
	end
	part(model, "Crossbar", Vector3.new(P - 0.4, 0.35, 0.35), frame * CFrame.new(0, h + 0.4, 0), METAL, Enum.Material.Metal)
	if start then
		local board = part(model, "ZipSign", Vector3.new(3.2, 1.4, 0.15), frame * CFrame.new(0, h + 1.35, 0), Color3.fromRGB(24, 27, 32), Enum.Material.Metal)
		signFace(board, Enum.NormalId.Front, line)
		signFace(board, Enum.NormalId.Back, line)
		local lamp = part(model, "Lamp", Vector3.new(1.2, 0.2, 0.6), frame * CFrame.new(0, h + 0.12, 0.5), LAMP_DIM, Enum.Material.SmoothPlastic)
		DayNight.nightLight(lamp, LAMP_LIT, LAMP_DIM, "SmoothPlastic")
	end
	return frame, floor
end

-- `lift`: the root over the feet (6.8 review: the body's own, HipHeight + half the root; it was 3, under the 3.8 body)
local function landing(line: ZipData.Line, lift: number): CFrame
	local at = Vector3.new(line.b.x, line.b.floor + lift, line.b.z)
	return CFrame.lookAt(at, at + Vector3.new(line.dx, 0, line.dz))
end

local function rootOf(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	return character, humanoid, root
end

-- On foot, free to go (not seated, not getting in, not riding, the Cooldown past the last ride)? Else what to say (or
-- "": nothing).
local function busy(player: Player, character: Model, humanoid: Humanoid): string?
	if rides[player] then
		return ""
	end
	if humanoid.SeatPart ~= nil or Vehicles.seatedIn(player) ~= nil or character:GetAttribute("Boarding") ~= nil then
		return "Get out first."
	end
	if os.clock() - (lastRide[player] or -math.huge) < Tuning.Cooldown then
		return ""
	end
	return nil
end

-- A ride, asked by the Zip prompt or a jump on the start platform (6.10: the Zip remote's "grab"); see the top.
local function zip(player: Player, line: ZipData.Line)
	local character, humanoid, root = rootOf(player)
	if not character or not humanoid or not root then
		return
	end
	local why = busy(player, character, humanoid)
	if why then
		if why ~= "" then
			tell(player, why)
		end
		return
	end
	-- (6.10: anywhere on the start platform or the roof by it, a jump on its way up too, not the ladder; the body's own
	-- root over its feet)
	local at = root.Position
	local lift = if humanoid.RigType == Enum.HumanoidRigType.R15 then humanoid.HipHeight + root.Size.Y / 2 else ZipData.Feet
	if not ZipData.canStart(line, at.X, at.Y, at.Z, lift) then
		return
	end
	if Cargo.carrying(character) ~= nil or character:GetAttribute("Pushing") ~= nil then
		tell(player, "Hands full: pack it first.")
		return
	end
	local startAt = workspace:GetServerTimeNow() + LEAD
	rides[player] = { line = line, start = startAt, character = character }
	lastRide[player] = os.clock()
	character:SetAttribute("ZipAt", startAt)
	character:SetAttribute("ZipLine", line.id)
	Tasks.note(player, "zip", 1) -- 6.12: the daily task "Ride a zip line"
end

-- The ride is over: off the cable (putDown: at the end platform, when the rider is not there already).
local function stop(player: Player, ride: Ride, putDown: boolean)
	rides[player] = nil
	lastRide[player] = os.clock()
	local character = ride.character
	if putDown and player.Character == character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.RootPart
		local spot = landing(ride.line, if humanoid and root then humanoid.HipHeight + root.Size.Y / 2 else ZipData.Feet)
		if humanoid and root and humanoid.Health > 0 and (root.Position - spot.Position).Magnitude > 6 then
			root.AssemblyLinearVelocity = Vector3.zero
			character:PivotTo(spot)
		end
	end
	if character.Parent then
		character:SetAttribute("ZipLine", nil)
		character:SetAttribute("ZipAt", nil)
	end
end

local function onZip(player: Player, action: any, id: any)
	if not Net.limit(player, "Zip", Config.Robust.Limits.Zip) then
		return -- (6.10 review: a flood of jumps or lets-go)
	end
	if action == "grab" then
		-- 6.10: a jump on the line's start platform (client/ZipRide.luau), checked as the Zip prompt
		local line = if type(id) == "number" then ZipData.line(id) else nil
		if line then
			zip(player, line)
		end
		return
	end
	if action ~= "letgo" then
		return
	end
	local ride = rides[player]
	if not ride then
		return
	end
	local t = workspace:GetServerTimeNow() - ride.start
	-- (the client's clock may be a little off the server's)
	if ZipData.canLetGo(ride.line, t) or ZipData.canLetGo(ride.line, t - 0.3) or ZipData.canLetGo(ride.line, t + 0.3) then
		stop(player, ride, false)
		return
	end
	-- (the client let go already: a lag past the window must not leave the ride running and teleport them later. If
	-- they really stand on one of the line's roofs, the ride ends where they are.)
	local _, _, root = rootOf(player)
	if root then
		local at = root.Position
		for _, lot in { ride.line.start, ride.line.finish } do
			local box = ZipData.boxOf(lot)
			if box and at.X >= box.x0 - 2 and at.X <= box.x1 + 2 and at.Z >= box.z0 - 2 and at.Z <= box.z1 + 2 and math.abs(at.Y - box.top) <= 8 then
				stop(player, ride, false)
				return
			end
		end
	end
end

local function check()
	local now = workspace:GetServerTimeNow()
	for player, ride in table.clone(rides) do
		local character = ride.character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if player.Parent == nil or player.Character ~= character or not humanoid or humanoid.Health <= 0 then
			stop(player, ride, false)
		elseif now >= ride.start + ride.line.duration + Tuning.Grace then
			stop(player, ride, true)
		end
	end
end

local function build(folder: Instance, world: Instance, line: ZipData.Line)
	local model = Instance.new("Model")
	model.Name = line.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("ZipLine", line.id)
	clearRoof(world, line.a)
	clearRoof(world, line.b)
	local frameA, floorA = platform(model, line.a, true, line)
	platform(model, line.b, false, line)
	-- The cable, along its sag.
	for n = 0, SEGMENTS - 1 do
		local x0, y0, z0 = ZipData.cable(line, n / SEGMENTS)
		local x1, y1, z1 = ZipData.cable(line, (n + 1) / SEGMENTS)
		local p0, p1 = Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
		local cable = part(model, "Cable", Vector3.new((p1 - p0).Magnitude + 0.1, 0.22, 0.22), CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, math.pi / 2, 0), CABLE, Enum.Material.Metal)
		cable.Shape = Enum.PartType.Cylinder
	end
	-- 6.10: the ladders, real ones: a truss the Humanoid climbs by itself (solid and queried: its climbing finds it), up
	-- to a little over the roof (its foot in the sidewalk as deep as the 2-stud steps need)
	for _, ladder in { line.ladderA, line.ladderB } do
		local x, y, z, height = ZipData.truss(ladder)
		local truss = Instance.new("TrussPart")
		truss.Name = "Ladder"
		truss.Anchored = true
		truss.CanCollide = true
		truss.CanQuery = true
		truss.CanTouch = false
		truss.Size = Vector3.new(2, height, 2)
		truss.CFrame = CFrame.new(x, y, z)
		truss.Color = METAL
		truss.Material = Enum.Material.Metal
		truss.Parent = model
	end
	-- The Zip in the start platform's middle (6.10: PromptReach, from anywhere on it; a jump there does the same).
	local go = prompt(floorA, "ZipPrompt", "Zip", line.name, 0, Tuning.PromptReach)
	;(go.Parent :: Attachment).WorldCFrame = frameA * CFrame.new(0, 2.5, 0)
	go.Triggered:Connect(function(player: Player)
		zip(player, line)
	end)
	model.Parent = folder
end

function ZipLines.start()
	if started then
		return
	end
	started = true
	local world = workspace:FindFirstChild("World") or workspace
	local folder = Instance.new("Folder")
	folder.Name = "ZipLines"
	folder.Parent = world
	for _, line in ZipData.lines() do
		local ok, err = pcall(function()
			build(folder, world, line)
		end)
		if not ok then
			warn(`[ZipLines] {line.name}: {err}`)
		end
	end
	Net.get("Zip").OnServerEvent:Connect(onZip)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < TICK then
			return
		end
		acc = 0
		check()
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		rides[player] = nil
		lastRide[player] = nil
	end)
end

-- Is this player on a zip line now?
function ZipLines.riding(player: Player): boolean
	return rides[player] ~= nil
end

return ZipLines
