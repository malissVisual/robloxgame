--!strict
-- 4.0, equipment you push (shared/Freight.luau has the rules): the HAND TROLLEY of a car with the "trolley" upgrade
-- and the PALLET JACK (ještěrka) of the warehouses and the Freight Truck.
--
--   where they live  a car's trolley folds inside its back (Stream V: the Attachment TrolleyMount and the folded look;
--                    this module builds the usable one only while it is out). A truck with the Attachment JackMount
--                    (the Freight Truck) carries a jack there, welded on. The jacks of the docks stand on their spots
--                    (shared/Map.luau FreightDocks jacks, ReceivingDocks jack).
--   take it          "Take trolley" (E): at the TrolleyMount while the back is open, at the back corner while it is
--                    shut; "Take pallet jack" (E) on a jack. Only with empty hands, on foot; a car's tool only for its
--                    owner and the job's crew (Equipment.mayTake, set by server/Cargo.luau).
--   push it          welded in front of you, massless and not colliding; the character attributes Pushing = "trolley"
--                    | "jack", Carrying (the gun, sprint and aim stay down, client/CameraRig.luau), CarryHands = 1 (a
--                    hand is free for the back's doors) and CarrySpeed (Config.Cargo TrolleySpeed, JackSpeed; server/
--                    Cargo.luau sets them while it carries pieces).
--   let it go        G: at your car's open back an empty trolley is stowed ("Stow trolley"), at its truck a jack too,
--                    on its spot a dock's jack is parked; anywhere else it is set down standing ("Take ..." again) with
--                    what is on it. Death, leaving and sitting set it down.
--   left behind      a tool set down with nobody within Config.Cargo.ToolNearby goes home quietly after
--                    TrolleyReturnSeconds / JackReturnSeconds (what was on it goes on the ground first, server/Cargo).
--
-- Cargo owns the pieces on a tool (it counts them exactly like the ones in the hands): the hooks below tell it when a
-- tool is taken, set down or goes home.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Freight = require(Shared.Freight)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Vehicles = require(script.Parent.Vehicles)
local PlayerData = require(script.Parent.PlayerData)

local Tuning = Config.Cargo
local Equipment = {}

export type Tool = {
	kind: string, -- "trolley" | "jack"
	state: string, -- "home" (at its mount or spot) | "pushed" | "parked" (set down somewhere)
	model: Model?, -- the tool you see (a car's trolley has none at home: the folded one is the car's)
	base: BasePart?, -- the model's main part: everything (the load too) is welded to it
	deck: CFrame, -- where the load stands, relative to `base` (the trolley's toe plate, the jack's forks)
	owner: Player?, -- a car's tool: the car's owner (nil for a dock's jack)
	carModel: Model?, -- the car it belongs to right now (a new body after a stage, a new car after a wreck)
	mountName: string, -- "TrolleyMount" | "JackMount" ("" for a dock's jack)
	spot: CFrame?, -- a dock's jack: its parking spot on the ground
	pusher: Player?,
	character: Model?,
	root: BasePart?,
	rootWeld: WeldConstraint?,
	takePrompt: ProximityPrompt?,
	letGo: ProximityPrompt?,
	anchor: Attachment?, -- a car's trolley at home: the Take prompt's attachment on the chassis
	since: number, -- os.clock() when it was set down
	last: CFrame, -- where it was last on the ground (a pusher's feet, where it stands)
}

local folder: Instance = workspace
local notice = Net.get("Notice")
local trolleys: { [Player]: Tool } = {} -- a car owner's trolley
local carJacks: { [Player]: Tool } = {} -- a car owner's jack (JackMount)
local spotJacks: { Tool } = {} -- the docks' jacks
local pushing: { [Player]: Tool } = {}
local mountCache: { [Model]: { trolley: Attachment?, jack: Attachment?, at: number } } = {}

local TROLLEY_AHEAD = 2.5 -- the trolley's wheels this far in front of the pusher's feet
local JACK_AHEAD = 2.8
local TROLLEY_TILT = math.rad(18) -- tipped back onto its wheels while pushed
local SPOT_REACH = 5 -- G this close to a dock jack's spot parks it there
local MOUNT_CHECK = 3 -- seconds between looking for a car's mounts again (the upgrade may come)

-- ── Hooks (set by server/Cargo.luau) ───────────────────────────────────────

-- How many pieces are on the tool (pushed or set down).
Equipment.loadOf = function(_tool: Tool): number
	return 0
end
-- May this player take the tool (a car's: the owner and the job's crew; a load of another job's: no)? The why.
Equipment.mayTake = function(player: Player, tool: Tool): (boolean, string?)
	if tool.owner == nil or tool.owner == player then
		return true, nil
	end
	return false, "That is somebody else's."
end
-- The tool was taken (its load comes along), set down (its load stays on it) or goes home (its load goes down).
Equipment.taken = function(_player: Player, _tool: Tool) end
Equipment.released = function(_player: Player, _tool: Tool) end
Equipment.returned = function(_tool: Tool) end

-- ── The models ─────────────────────────────────────────────────────────────

local function newPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Parent = model
	return p
end

local function cylinder(model: Model, name: string, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = newPart(model, name, Vector3.new(length, diameter, diameter), cframe, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A bar between two points (its length along Y).
local function bar(model: Model, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3): Part
	local middle = (a + b) / 2
	return newPart(model, name, Vector3.new(thickness, (b - a).Magnitude, thickness), CFrame.lookAt(middle, b) * CFrame.Angles(-math.pi / 2, 0, 0), color, Enum.Material.Metal)
end

-- Every part welded to the base; the base is the pivot (the build's origin: on the ground under the tool's middle,
-- the front -Z) and the invisible box you walk around when it stands.
local function finish(model: Model, base: Part, deck: CFrame): CFrame
	base.Transparency = 1
	base.Massless = true
	model.PrimaryPart = base
	base.PivotOffset = base.CFrame:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= base then
			d.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = base
			weld.Part1 = d
			weld.Parent = d
		end
	end
	return base.CFrame:ToObjectSpace(deck)
end

-- A hand trolley (a hand truck): two red rails, cross bars, a steel toe plate at the front, two wheels behind, the
-- handle bent back at the top.
local function buildTrolley(): (Model, Part, CFrame)
	local model = Instance.new("Model")
	model.Name = "HandTrolley"
	local red = Color3.fromRGB(196, 44, 36)
	local steel = Color3.fromRGB(160, 162, 168)
	local black = Color3.fromRGB(28, 28, 30)
	local base = newPart(model, "Base", Vector3.new(2.8, 3.4, 1.8), CFrame.new(0, 1.9, -0.3), red, Enum.Material.SmoothPlastic)
	for _, x in { -1.1, 1.1 } do
		newPart(model, "Rail", Vector3.new(0.2, 3.4, 0.2), CFrame.new(x, 1.9, 0), red, Enum.Material.Metal)
		bar(model, "HandleBend", Vector3.new(x, 3.55, 0), Vector3.new(x, 3.75, 0.45), 0.18, red)
	end
	for _, y in { 1.2, 2.3, 3.3 } do
		newPart(model, "CrossBar", Vector3.new(2.3, 0.15, 0.15), CFrame.new(0, y, 0), red, Enum.Material.Metal)
	end
	newPart(model, "Handle", Vector3.new(2.5, 0.2, 0.2), CFrame.new(0, 3.75, 0.5), black, Enum.Material.Rubber)
	newPart(model, "ToePlate", Vector3.new(2.6, 0.12, 1.5), CFrame.new(0, 0.1, -0.75), steel, Enum.Material.DiamondPlate)
	newPart(model, "ToeLip", Vector3.new(2.6, 0.35, 0.12), CFrame.new(0, 0.3, 0), steel, Enum.Material.Metal)
	cylinder(model, "Axle", 2.8, 0.14, CFrame.new(0, 0.5, 0.35), steel, Enum.Material.Metal)
	for _, x in { -1.3, 1.3 } do
		cylinder(model, "Wheel", 0.4, 1.0, CFrame.new(x, 0.5, 0.35), black, Enum.Material.Rubber)
		cylinder(model, "Hub", 0.44, 0.4, CFrame.new(x, 0.5, 0.35), steel, Enum.Material.Metal)
	end
	return model, base, finish(model, base, CFrame.new(0, 0.16, 0))
end

-- A hand pallet jack: two yellow forks, the pump housing over the steering wheel, the pump, the handle with its loop.
local function buildJack(): (Model, Part, CFrame)
	local model = Instance.new("Model")
	model.Name = "PalletJack"
	local yellow = Color3.fromRGB(240, 196, 40)
	local dark = Color3.fromRGB(48, 48, 52)
	local black = Color3.fromRGB(26, 26, 28)
	local base = newPart(model, "Base", Vector3.new(2.2, 1.2, 6.2), CFrame.new(0, 0.6, -1.4), yellow, Enum.Material.SmoothPlastic)
	for _, x in { -0.75, 0.75 } do
		newPart(model, "Fork", Vector3.new(0.55, 0.3, 4.4), CFrame.new(x, 0.3, -2.4), yellow, Enum.Material.Metal)
		cylinder(model, "Roller", 0.4, 0.28, CFrame.new(x, 0.14, -4.3), dark, Enum.Material.Metal)
	end
	newPart(model, "Housing", Vector3.new(2.1, 0.9, 0.9), CFrame.new(0, 0.6, 0.35), yellow, Enum.Material.Metal)
	cylinder(model, "Pump", 1.0, 0.5, CFrame.new(0, 1.45, 0.4) * CFrame.Angles(0, 0, math.rad(90)), dark, Enum.Material.Metal)
	cylinder(model, "SteerWheel", 0.35, 0.7, CFrame.new(0, 0.35, 0.75), black, Enum.Material.Rubber)
	bar(model, "Handle", Vector3.new(0, 1.0, 0.6), Vector3.new(0, 3.6, 2.0), 0.2, dark)
	newPart(model, "Grip", Vector3.new(1.2, 0.22, 0.22), CFrame.new(0, 3.6, 2.0), black, Enum.Material.Rubber)
	for _, x in { -0.55, 0.55 } do
		newPart(model, "GripSide", Vector3.new(0.18, 0.5, 0.18), CFrame.new(x, 3.4, 1.95), black, Enum.Material.Rubber)
	end
	return model, base, finish(model, base, CFrame.new(0, 0.45, -2.4))
end

-- ── Helpers ────────────────────────────────────────────────────────────────

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- The walkable ground at x, z near `around` (not a car, a character, a piece of cargo or a tool).
local function groundAt(x: number, z: number, around: number): number
	local skip: { Instance } = { folder }
	for _, name in { "Cars", "Zombies", "Npcs", "Animals", "Effects", "Loot", "Showroom", "Cargo" } do
		local child = workspace:FindFirstChild(name)
		if child then
			table.insert(skip, child)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = skip
	local result = workspace:Raycast(Vector3.new(x, around + 8, z), Vector3.new(0, -24, 0), groundParams)
	return if result then result.Position.Y else around
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function tell(player: Player, text: string)
	notice:FireClient(player, text)
end

local function nameOf(tool: Tool): string
	return if tool.kind == "jack" then "pallet jack" else "trolley"
end

-- The tool's parts: anchored where it stands, or loose and welded to whatever carries it.
local function setAnchored(tool: Tool, anchored: boolean)
	local model = tool.model
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = anchored
		end
	end
end

local function dropRootWeld(tool: Tool)
	if tool.rootWeld then
		tool.rootWeld:Destroy()
		tool.rootWeld = nil
	end
end

local function clearPrompts(tool: Tool)
	if tool.takePrompt then
		tool.takePrompt:Destroy()
		tool.takePrompt = nil
	end
	if tool.letGo then
		tool.letGo:Destroy()
		tool.letGo = nil
	end
end

-- The car this tool belongs to now (the owner's live car with the tool's mount), or nil.
local function carOf(tool: Tool): Vehicles.Car?
	local owner = tool.owner
	local car = if owner then Vehicles.get(owner) else nil
	if car and car.model.Parent and tool.carModel == car.model then
		return car
	end
	return nil
end

-- The car's mounts (looked up again every MOUNT_CHECK s: the upgrade may come, a stage builds a new body).
local function mountsOf(car: Vehicles.Car): (Attachment?, Attachment?)
	local now = os.clock()
	local cached = mountCache[car.model]
	if cached and now - cached.at <= MOUNT_CHECK then
		return cached.trolley, cached.jack
	end
	local trolley = car.model:FindFirstChild("TrolleyMount", true)
	local jack = car.model:FindFirstChild("JackMount", true)
	local entry = {
		trolley = if trolley and trolley:IsA("Attachment") then trolley else nil,
		jack = if jack and jack:IsA("Attachment") then jack else nil,
		at = now,
	}
	mountCache[car.model] = entry
	return entry.trolley, entry.jack
end

-- Has the car the Hand Trolley upgrade (Stream V: "trolley", a car track)? Without the upgrade defined yet, the mount
-- alone says so.
local function hasTrolley(car: Vehicles.Car): boolean
	if not Economy.findUpgrade("trolley") then
		return true
	end
	local profile = PlayerData.get(car.owner)
	local levels = if profile then Economy.carLevels(profile.carUpgrades, car.id) else {}
	local gate = (Economy :: any).hasTrolley -- Stream V: which cars take it, and this one's level
	if type(gate) == "function" then
		local ok, yes = pcall(gate, car.id, levels)
		if ok then
			return yes == true
		end
	end
	return Economy.level(levels, "trolley") >= 1
end

-- Stream V's folded trolley at the mount (car.model.UpgradeKit.FoldedTrolley): hidden while the real one is out.
local function showFolded(model: Model, shown: boolean)
	local kit = model:FindFirstChild("UpgradeKit")
	local folded = kit and kit:FindFirstChild("FoldedTrolley")
	if not folded then
		return
	end
	local parts: { Instance } = folded:GetDescendants()
	if folded:IsA("BasePart") then
		table.insert(parts, folded)
	end
	for _, d in parts do
		if d:IsA("BasePart") then
			local was = d:GetAttribute("ShownTransparency")
			if not shown and was == nil then
				d:SetAttribute("ShownTransparency", d.Transparency)
				d.Transparency = 1
			elseif shown and type(was) == "number" then
				d.Transparency = was
				d:SetAttribute("ShownTransparency", nil)
			end
		end
	end
end

local function mountOf(tool: Tool): Attachment?
	local car = carOf(tool)
	if not car then
		return nil
	end
	local trolley, jack = mountsOf(car)
	return if tool.kind == "jack" then jack else trolley
end

-- ── Attributes ─────────────────────────────────────────────────────────────

-- The pusher's attributes for an empty tool (server/Cargo.luau sets Carrying, CarryCount and CarrySpeed while it
-- carries pieces on it, and calls this when they are gone).
function Equipment.restore(player: Player)
	local tool = pushing[player]
	local character = tool and tool.character
	if not tool or not character or not character.Parent then
		return
	end
	character:SetAttribute("Pushing", tool.kind)
	character:SetAttribute("Carrying", tool.kind)
	character:SetAttribute("CarryCount", nil)
	character:SetAttribute("CarryHands", 1)
	character:SetAttribute("CarrySpeed", Freight.walkSpeed(tool.kind, 0))
end

local function undress(character: Model?)
	if character and character.Parent then
		for _, name in { "Pushing", "Carrying", "CarryCount", "CarryHands", "CarrySpeed" } do
			character:SetAttribute(name, nil)
		end
	end
end

-- ── Prompts ────────────────────────────────────────────────────────────────

local takeTool: (Player, Tool) -> ()
local letGo: (Player) -> ()

local function newPrompt(parent: Instance, action: string, object: string, key: Enum.KeyCode, reach: number, hold: number): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key
	if key == Enum.KeyCode.G then
		p.GamepadKeyCode = Enum.KeyCode.ButtonB
	end
	p.HoldDuration = hold
	p.MaxActivationDistance = reach
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- "Take trolley" / "Take pallet jack" (E) on the tool where it stands (on the trolley's car: the chassis' anchor).
local function armTake(tool: Tool, parent: Instance)
	clearPrompts(tool)
	local p = newPrompt(parent, if tool.kind == "jack" then "Take pallet jack" else "Take trolley", "", Enum.KeyCode.E, 8, Tuning.HoldDuration)
	p.Triggered:Connect(function(player)
		takeTool(player, tool)
	end)
	tool.takePrompt = p
end

-- G on the pushed tool: set it down, stow it, park it (Equipment's tick keeps the text right).
local function armLetGo(tool: Tool)
	clearPrompts(tool)
	local base = tool.base
	local pusher = tool.pusher
	if not base or not pusher then
		return
	end
	local p = newPrompt(base, `Set down {nameOf(tool)}`, "", Enum.KeyCode.G, 6, 0)
	p.Triggered:Connect(function(player)
		if player == tool.pusher and pushing[player] == tool then
			letGo(player)
		end
	end)
	tool.letGo = p
end

-- ── States ─────────────────────────────────────────────────────────────────

local function ensureModel(tool: Tool)
	if tool.model and tool.model.Parent then
		return
	end
	local model: Model, base: Part, deck: CFrame
	if tool.kind == "jack" then
		model, base, deck = buildJack()
	else
		model, base, deck = buildTrolley()
	end
	model.Parent = folder
	tool.model = model
	tool.base = base
	tool.deck = deck
end

local function destroyModel(tool: Tool)
	clearPrompts(tool)
	dropRootWeld(tool)
	if tool.model then
		tool.model:Destroy()
	end
	tool.model = nil
	tool.base = nil
end

-- Standing on the ground at `frame` (upright), with its Take prompt.
local function standAt(tool: Tool, frame: CFrame)
	ensureModel(tool)
	local model = tool.model :: Model
	dropRootWeld(tool)
	setAnchored(tool, true)
	model:PivotTo(frame)
	local base = tool.base
	if base then
		base.CanCollide = true
		armTake(tool, base)
	end
	tool.last = frame
end

-- Home: a dock's jack on its spot; a car's jack welded at its JackMount; a car's trolley folded away (no model, the
-- Take prompt on the chassis). False when it has no home any more (its car is gone).
local function goHome(tool: Tool): boolean
	tool.pusher, tool.character, tool.root = nil, nil, nil
	if tool.spot then
		standAt(tool, tool.spot)
		tool.state = "home"
		return true
	end
	local mount = mountOf(tool)
	local car = carOf(tool)
	if not mount or not car then
		return false
	end
	if tool.kind == "jack" then
		ensureModel(tool)
		local model = tool.model :: Model
		dropRootWeld(tool)
		setAnchored(tool, true)
		model:PivotTo(mount.WorldCFrame)
		local base = tool.base :: BasePart
		base.CanCollide = false
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Massless = true
			end
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = car.chassis
		weld.Part1 = base
		weld.Parent = base
		tool.rootWeld = weld
		setAnchored(tool, false)
		armTake(tool, base)
	else
		destroyModel(tool)
		car.model:SetAttribute("TrolleyOut", nil)
		showFolded(car.model, true)
	end
	tool.state = "home"
	return true
end

-- Gone for good: the owner left, or the car without its mount took it along.
local function remove(tool: Tool)
	destroyModel(tool)
	if tool.anchor then
		tool.anchor:Destroy()
		tool.anchor = nil
	end
	tool.state = "gone"
end

-- The pushed tool's frame in front of the pusher (welded to the root).
local function pushedFrame(tool: Tool, root: BasePart, humanoid: Humanoid): CFrame
	local drop = humanoid.HipHeight + root.Size.Y / 2
	local at = root.CFrame * CFrame.new(0, -drop, -(if tool.kind == "jack" then JACK_AHEAD else TROLLEY_AHEAD))
	if tool.kind == "trolley" then
		at = at * CFrame.new(0, 0.5, 0.35) * CFrame.Angles(TROLLEY_TILT, 0, 0) * CFrame.new(0, -0.5, -0.35)
	end
	return at
end

takeTool = function(player: Player, tool: Tool)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(character)
	if not character or not humanoid or not root or humanoid.Health <= 0 or tool.state == "pushed" or tool.state == "gone" then
		return
	end
	if humanoid.SeatPart then
		tell(player, "Get out first.")
		return
	end
	local current = pushing[player]
	if current then
		tell(player, `You already push a {nameOf(current)}. Set it down (G) first.`)
		return
	end
	if character:GetAttribute("Carrying") ~= nil then
		tell(player, "Your hands are full.")
		return
	end
	local ok, why = Equipment.mayTake(player, tool)
	if not ok then
		tell(player, why or "That is somebody else's.")
		return
	end
	local car = carOf(tool)
	if tool.state == "home" and car and Vehicles.speed(car) > Tuning.MaxCarSpeed then
		tell(player, "Stop the vehicle first.")
		return
	end
	ensureModel(tool)
	local model = tool.model :: Model
	local base = tool.base :: BasePart
	clearPrompts(tool)
	dropRootWeld(tool)
	setAnchored(tool, true)
	model:PivotTo(pushedFrame(tool, root, humanoid))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
		end
	end
	setAnchored(tool, false)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = base
	weld.Parent = base
	tool.rootWeld = weld
	tool.state = "pushed"
	tool.pusher, tool.character, tool.root = player, character, root
	pushing[player] = tool
	if tool.kind == "trolley" and car then
		car.model:SetAttribute("TrolleyOut", true)
		showFolded(car.model, false) -- the real one is out: the folded one goes
	end
	Equipment.restore(player)
	armLetGo(tool)
	Equipment.taken(player, tool)
end

-- Where a tool set down stands: in front of where the pusher stood, upright, on the ground.
local function setDownFrame(tool: Tool): CFrame
	local root = tool.root
	local feet = tool.last
	if root and root.Parent then
		local character = tool.character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local drop = if humanoid then humanoid.HipHeight + root.Size.Y / 2 else 3
		feet = root.CFrame * CFrame.new(0, -drop, 0)
	end
	local look = feet.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local spot = feet.Position + flat * (if tool.kind == "jack" then JACK_AHEAD else TROLLEY_AHEAD)
	local y = groundAt(spot.X, spot.Z, feet.Position.Y)
	local at = Vector3.new(spot.X, y, spot.Z)
	return CFrame.lookAt(at, at + flat)
end

-- The pusher lets go: it stands where they were (with its load: Equipment.released).
local function release(player: Player)
	local tool = pushing[player]
	if not tool then
		return
	end
	local frame = setDownFrame(tool)
	pushing[player] = nil
	local character = tool.character
	tool.pusher, tool.character, tool.root = nil, nil, nil
	undress(character)
	standAt(tool, frame)
	tool.state = "parked"
	tool.since = os.clock()
	Equipment.released(player, tool)
end

-- Is the pusher at the tool's home (its car's mount, a dock jack's spot) so G puts it away? The trolley needs the
-- back open and nothing on it.
local function canStow(tool: Tool): boolean
	local root = tool.root
	if not root or Equipment.loadOf(tool) > 0 then
		return false
	end
	local spot = tool.spot
	if spot then
		local p = spot.Position
		return Vector3.new(p.X - root.Position.X, 0, p.Z - root.Position.Z).Magnitude <= SPOT_REACH
	end
	local mount = mountOf(tool)
	local car = carOf(tool)
	if not mount or not car or Vehicles.speed(car) > Tuning.MaxCarSpeed then
		return false
	end
	if Vehicles.hasBack(car) and not Vehicles.backOpen(car) then
		return false -- both mounts are inside the back
	end
	local m = mount.WorldPosition
	return Vector3.new(m.X - root.Position.X, 0, m.Z - root.Position.Z).Magnitude <= Tuning.ToolReach
end

letGo = function(player: Player)
	local tool = pushing[player]
	if not tool then
		return
	end
	if canStow(tool) then
		pushing[player] = nil
		local character = tool.character
		undress(character)
		goHome(tool)
		return
	end
	release(player)
end

-- ── API ────────────────────────────────────────────────────────────────────

-- The tool this player pushes, or nil.
function Equipment.pushing(player: Player): Tool?
	return pushing[player]
end

-- The owner's car trolley (home, pushed or set down), or nil without one.
function Equipment.trolleyOf(owner: Player): Tool?
	return trolleys[owner]
end

-- Sets down what the player pushes (G, or they died, left, sat down; server/Cargo.luau too).
function Equipment.setDown(player: Player)
	release(player)
end

-- Where the load stands on a tool, in the world (its toe plate or forks), and the part to weld it to.
function Equipment.deck(tool: Tool): (BasePart?, CFrame)
	local base = tool.base
	if not base then
		return nil, tool.last
	end
	return base, base.CFrame * tool.deck
end

-- Would G put the pushed tool away right now (the hints)?
function Equipment.atHome(player: Player): boolean
	local tool = pushing[player]
	return tool ~= nil and canStow(tool)
end

-- ── The tick ───────────────────────────────────────────────────────────────

local function newCarTool(kind: string, owner: Player, car: Vehicles.Car): Tool
	return {
		kind = kind,
		state = "gone",
		model = nil,
		base = nil,
		deck = CFrame.identity,
		owner = owner,
		carModel = car.model,
		mountName = if kind == "jack" then "JackMount" else "TrolleyMount",
		spot = nil,
		pusher = nil,
		character = nil,
		root = nil,
		rootWeld = nil,
		takePrompt = nil,
		letGo = nil,
		anchor = nil,
		since = os.clock(),
		last = car.chassis.CFrame,
	}
end

-- The car's trolley Take prompt at home: at the mount while the back is open, at the back's corner while it is shut
-- (Vehicles' CargoDoor and the car's width). Off while the car moves or a chauffeur drives it.
local function placeTrolleyAnchor(tool: Tool, car: Vehicles.Car, mount: Attachment)
	local anchor = tool.anchor
	if not anchor or anchor.Parent ~= car.chassis then
		if anchor then
			anchor:Destroy()
		end
		local made = Instance.new("Attachment")
		made.Name = "TrolleyTake"
		made.Parent = car.chassis
		anchor = made
		tool.anchor = made
		clearPrompts(tool)
	end
	local a = anchor :: Attachment
	if not tool.takePrompt then
		armTake(tool, a)
	end
	local open = not Vehicles.hasBack(car) or Vehicles.backOpen(car)
	local spot: Vector3
	if open then
		spot = car.chassis.CFrame:PointToObjectSpace(mount.WorldPosition)
	else
		local door = Vehicles.cargoDoor(car)
		local back = if door then door.Position else Vector3.new(0, 0, car.size.Z / 2)
		spot = Vector3.new(car.size.X / 2 - 0.4, back.Y, back.Z + 0.8)
	end
	if (a.Position - spot).Magnitude > 0.05 then
		a.Position = spot
	end
	local prompt = tool.takePrompt
	if prompt then
		local want = not car.chauffeured and not car.repairing and Vehicles.speed(car) <= Tuning.MaxCarSpeed
		if prompt.Enabled ~= want then
			prompt.Enabled = want
		end
	end
end

-- Follows the owners' cars: a trolley for a car with the upgrade and its mount, a jack for a car with a JackMount; a
-- new body (a stage, a respawn) takes its tools over; a car without the mount any more drops a tool that is home.
local function syncCars()
	local seen: { [Player]: boolean } = {}
	for _, car in Vehicles.all() do
		local owner = car.owner
		if seen[owner] or Vehicles.get(owner) ~= car or not car.model.Parent then
			continue
		end
		seen[owner] = true
		local trolleyMount, jackMount = mountsOf(car)
		for _, kind in { "trolley", "jack" } do
			local list: { [Player]: Tool } = if kind == "jack" then carJacks else trolleys
			local mount = if kind == "jack" then jackMount else (if trolleyMount and hasTrolley(car) then trolleyMount else nil)
			local tool = list[owner]
			if tool and tool.carModel ~= car.model then
				-- A new body or another car: home tools follow (or go), tools out keep going until they come home.
				local old = tool.carModel
				tool.carModel = car.model
				if tool.state == "home" then
					destroyModel(tool)
					if tool.anchor then
						tool.anchor:Destroy()
						tool.anchor = nil
					end
					if not mount or not goHome(tool) then
						remove(tool)
						list[owner] = nil
					end
				end
				if old then
					mountCache[old] = nil
				end
			elseif not tool and mount then
				local made = newCarTool(kind, owner, car)
				list[owner] = made
				goHome(made)
			end
			tool = list[owner]
			if tool and kind == "trolley" and tool.state == "home" then
				if mount then
					placeTrolleyAnchor(tool, car, mount)
				else
					remove(tool)
					list[owner] = nil
				end
			elseif tool and tool.anchor and tool.state ~= "home" then
				tool.anchor:Destroy()
				tool.anchor = nil
			end
			if tool and kind == "jack" and tool.state == "home" and not mount then
				remove(tool)
				list[owner] = nil
			end
			-- Stream V hides the folded trolley at the mount while the real one is out.
			local out = if kind == "trolley" and list[owner] and (list[owner] :: Tool).state ~= "home" then true else nil
			if kind == "trolley" and car.model:GetAttribute("TrolleyOut") ~= out then
				car.model:SetAttribute("TrolleyOut", out)
				showFolded(car.model, not out)
			end
			-- The truck's jack rides inside its back: taken only through the open back.
			local home = list[owner]
			if kind == "jack" and home and home.state == "home" and home.takePrompt then
				local want = (not Vehicles.hasBack(car) or Vehicles.backOpen(car)) and Vehicles.speed(car) <= Tuning.MaxCarSpeed and not car.chauffeured
				if home.takePrompt.Enabled ~= want then
					home.takePrompt.Enabled = want
				end
			end
		end
	end
	-- Owners without a car: their home tools go (they come back with the car); tools out wait to be returned.
	for _, list in { trolleys, carJacks } do
		for owner, tool in list do
			if not seen[owner] and tool.state == "home" then
				remove(tool)
				list[owner] = nil
			end
		end
	end
	for model in mountCache do
		if not model.Parent then
			mountCache[model] = nil
		end
	end
end

-- Is anybody (on foot or in a car) within Config.Cargo.ToolNearby of the tool?
local function somebodyNear(tool: Tool): boolean
	local at = tool.last.Position
	for _, player in Players:GetPlayers() do
		local root = rootOf(player.Character)
		if root and (root.Position - at).Magnitude <= Tuning.ToolNearby then
			return true
		end
	end
	return false
end

-- A parked tool left long enough goes home quietly (its load goes down first: Equipment.returned).
local function returnHome(tool: Tool, list: { [Player]: Tool }?, owner: Player?)
	Equipment.returned(tool)
	if not goHome(tool) then
		remove(tool)
		if list and owner then
			list[owner] = nil
		end
	end
end

local function tick()
	syncCars()
	local now = os.clock()
	-- The pushers: dead, gone, sitting, rebuilt: set it down. The G's words follow where you are.
	for player, tool in table.clone(pushing) do
		local character = tool.character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = rootOf(character)
		local fine = player.Parent ~= nil and character ~= nil and player.Character == character and humanoid ~= nil and humanoid.Health > 0
			and humanoid.SeatPart == nil and root ~= nil and root == tool.root and tool.rootWeld ~= nil and tool.rootWeld.Parent ~= nil
		if not fine then
			release(player)
			continue
		end
		if root then
			local humanoidNow = humanoid :: Humanoid
			tool.last = root.CFrame * CFrame.new(0, -(humanoidNow.HipHeight + root.Size.Y / 2), 0)
		end
		local prompt = tool.letGo
		if prompt then
			local text = if canStow(tool) then (if tool.spot then "Park pallet jack" else `Stow {nameOf(tool)}`) else `Set down {nameOf(tool)}`
			if prompt.ActionText ~= text then
				prompt.ActionText = text
			end
		end
	end
	-- The tools left somewhere.
	for _, list in { trolleys, carJacks } do
		for owner, tool in table.clone(list) do
			if tool.state == "parked" and Freight.returnsHome(tool.kind, now - tool.since, not somebodyNear(tool)) then
				returnHome(tool, list, owner)
			end
		end
	end
	for _, tool in spotJacks do
		if tool.state == "parked" and Freight.returnsHome(tool.kind, now - tool.since, not somebodyNear(tool)) then
			returnHome(tool, nil, nil)
		end
	end
end

-- The docks' jacks on their spots (shared/Map.luau).
local function placeSpotJacks()
	local spots: { Map.JackSpot } = {}
	for _, hub in Map.FreightDocks do
		for _, spot in hub.jacks do
			table.insert(spots, spot)
		end
	end
	for _, dock in Map.ReceivingDocks do
		table.insert(spots, dock.jack)
	end
	for _, spot in spots do
		local y = groundAt(spot.x, spot.z, Map.WalkTop + 3)
		local at = Vector3.new(spot.x, y, spot.z)
		local frame = CFrame.lookAt(at, at + Vector3.new(spot.facing.x, 0, spot.facing.z))
		local tool: Tool = {
			kind = "jack",
			state = "home",
			model = nil,
			base = nil,
			deck = CFrame.identity,
			owner = nil,
			carModel = nil,
			mountName = "",
			spot = frame,
			pusher = nil,
			character = nil,
			root = nil,
			rootWeld = nil,
			takePrompt = nil,
			letGo = nil,
			anchor = nil,
			since = os.clock(),
			last = frame,
		}
		standAt(tool, frame)
		table.insert(spotJacks, tool)
	end
end

local started = false

function Equipment.start()
	if started then
		return
	end
	started = true
	local existing = workspace:FindFirstChild("Equipment")
	if existing then
		folder = existing
	else
		local made = Instance.new("Folder")
		made.Name = "Equipment"
		made.Parent = workspace
		folder = made
	end
	placeSpotJacks()
	Players.PlayerRemoving:Connect(function(player)
		release(player)
		for _, list in { trolleys, carJacks } do
			local tool = list[player]
			if tool then
				local pusher = tool.pusher
				if pusher then
					release(pusher)
				end
				Equipment.returned(tool)
				remove(tool)
				list[player] = nil
			end
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.2 then
			return
		end
		elapsed = 0
		tick()
	end)
end

return Equipment
