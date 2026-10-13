--!strict
-- 8.0 SANDBOX: the admin panel's 🔍 SHOW ZONES (client/AdminPanel.luau's SANDBOX tab): see-through debug marks, on this
-- screen only, for what the sandbox's code measures against:
--   * each plot's unload circle (green: the van's back or middle inside it unloads into that warehouse) and the house's
--     curb (yellow: the van's spot at the chalet, a van's footprint, its nose marked), from shared/SandboxAdmin.luau's
--     zones;
--   * the warehouses' display stands (violet boxes): the parts that hold a Display / Take down / Sell prompt
--     (server/Warehouse.luau's, design/sandbox/KONTRAKT.md), looked for again every STANDS_EVERY s;
--   * every van's cargo bay (blue: Config.Moving.Beds of its CarId, else the moves' van's): a box on its chassis (the
--     floor at the chassis' top: near enough to see the bed; along the van where the load goes: Back in front of its
--     CargoDoor, else Center), so it drives along; vans that come or go every REFRESH s.
-- Nothing collides or is queried, nothing goes to the server. Off again: every mark goes.
--
--   SandboxZones.isOn()     shown now?
--   SandboxZones.toggle()   on / off; returns isOn()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SandboxAdmin = require(Shared.SandboxAdmin)

local SandboxZones = {}

local REFRESH = 1 -- s between looks for the vans
local STANDS_EVERY = 5 -- s between looks for the stands (one pass over the world's descendants: not often)
local COLORS = {
	unload = Color3.fromRGB(90, 220, 120),
	curb = Color3.fromRGB(255, 205, 70),
	stand = Color3.fromRGB(190, 120, 255),
	bay = Color3.fromRGB(80, 170, 255),
}

local state = {
	on = false,
	serial = 0, -- a new one each toggle: an old loop sees it and stops
	folder = nil :: Folder?,
	bays = {} :: { [Instance]: Instance }, -- a van's chassis → its bay's marks (a BoxHandleAdornment, a tag)
	stands = {} :: { [Instance]: Instance }, -- a stand's part → its marks (a SelectionBox, a tag)
}

-- A name tag over a mark (always on top, gone far away).
local function tag(adornee: Instance, text: string, color: Color3, parent: Instance, height: number)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Tag"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 350
	gui.Size = UDim2.fromOffset(220, 24)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.4
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
end

local function mark(parent: Instance, name: string, size: Vector3, at: CFrame, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.6
	part.Color = color
	part.Size = size
	part.CFrame = at
	part.Parent = parent
	return part
end

-- The fixed marks: the unload circles and the house's curb.
local function drawZones(folder: Folder)
	for _, zone in SandboxAdmin.zones() do
		if zone.shape == "circle" then
			local disc = mark(folder, zone.label, Vector3.new(0.2, zone.r * 2, zone.r * 2), CFrame.new(zone.x, zone.y + 0.12, zone.z) * CFrame.Angles(0, 0, math.rad(90)), COLORS.unload)
			disc.Shape = Enum.PartType.Cylinder
			tag(disc, zone.label, COLORS.unload, disc, 3)
		else
			local at = CFrame.new(zone.x, zone.y + zone.sy / 2 + 0.05, zone.z) * CFrame.Angles(0, math.rad(zone.yaw), 0)
			local box = mark(folder, zone.label, Vector3.new(zone.sx, zone.sy, zone.sz), at, COLORS.curb)
			-- its nose (the spot's look, -Z): a brighter bar across the front end
			mark(box, "Nose", Vector3.new(zone.sx, zone.sy + 0.1, 1), at * CFrame.new(0, 0.05, -zone.sz / 2 + 0.5), COLORS.curb).Transparency = 0.2
			tag(box, zone.label, COLORS.curb, box, 3)
		end
	end
end

-- The stands: every part holding a stand's prompt (Display / Take down / Sell), marked once; gone ones unmarked.
local function scanStands(folder: Folder)
	local seen: { [Instance]: boolean } = {}
	for _, item in workspace:GetDescendants() do
		if item:IsA("ProximityPrompt") then
			local text = string.lower(item.ActionText)
			if string.find(text, "^display") or string.find(text, "^take down") or string.find(text, "^sell") then
				local holder = item.Parent
				local part = if holder and holder:IsA("Attachment") then holder.Parent else holder
				if part and part:IsA("BasePart") and not part:IsDescendantOf(folder) then
					seen[part] = true
					if not state.stands[part] then
						local marks = Instance.new("Folder")
						marks.Name = "Stand"
						local box = Instance.new("SelectionBox")
						box.Adornee = part
						box.Color3 = COLORS.stand
						box.SurfaceColor3 = COLORS.stand
						box.SurfaceTransparency = 0.8
						box.LineThickness = 0.08
						box.Parent = marks
						tag(part, if item.ObjectText ~= "" then `STAND · {item.ObjectText}` else "STAND", COLORS.stand, marks, 4)
						marks.Parent = folder
						state.stands[part] = marks
					end
				end
			end
		end
	end
	for part, marks in state.stands do
		if not seen[part] or not part.Parent then
			marks:Destroy()
			state.stands[part] = nil
		end
	end
end

-- Every van's bay: a box on its chassis (a HandleAdornment: drawn where the chassis is, every frame, for free).
local function scanBays(folder: Folder)
	local seen: { [Instance]: boolean } = {}
	local cars = workspace:FindFirstChild("Cars")
	local beds = Config.Moving.Beds
	for _, car in if cars then cars:GetChildren() else {} do
		if car:IsA("Model") and car:GetAttribute("OwnerId") ~= nil and car:GetAttribute("Bike") ~= true then
			local chassis = car.PrimaryPart or car:FindFirstChild("Chassis")
			local carId = car:GetAttribute("CarId")
			local bed = (if type(carId) == "string" then beds[carId] else nil) or beds[Config.Moving.Van]
			if chassis and chassis:IsA("BasePart") and bed then
				seen[chassis] = true
				if not state.bays[chassis] then
					local bay = Instance.new("Folder")
					bay.Name = "Bay"
					local box = Instance.new("BoxHandleAdornment")
					box.Adornee = chassis
					box.Size = Vector3.new(bed.Width, bed.Height, bed.Length)
					-- (its middle along the van as server/Moving.luau's SB.center puts the load: a bed with Back from the
					-- car's CargoDoor, Back in front of it; else its Center; +Z is the van's back)
					local door = chassis:FindFirstChild("CargoDoor")
					local cz = if bed.Back and door and door:IsA("Attachment") then door.Position.Z - bed.Back - bed.Length / 2 else bed.Center[2]
					box.CFrame = CFrame.new(bed.Center[1], chassis.Size.Y / 2 + bed.Height / 2, cz)
					box.Color3 = COLORS.bay
					box.Transparency = 0.6
					box.AlwaysOnTop = false
					box.ZIndex = 0
					box.Parent = bay
					tag(chassis, string.format("BAY · %s · %.1f × %.1f × %.1f", tostring(carId or "van"), bed.Width, bed.Length, bed.Height), COLORS.bay, bay, bed.Height + 4)
					bay.Parent = folder
					state.bays[chassis] = bay
				end
			end
		end
	end
	for chassis, marks in state.bays do
		if not seen[chassis] or not chassis.Parent then
			marks:Destroy()
			state.bays[chassis] = nil
		end
	end
end

local function clear()
	local folder = state.folder
	state.folder = nil
	table.clear(state.bays)
	table.clear(state.stands)
	if folder then
		folder:Destroy()
	end
end

function SandboxZones.isOn(): boolean
	return state.on
end

function SandboxZones.toggle(): boolean
	state.on = not state.on
	state.serial += 1
	clear()
	if not state.on then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = "SandboxZones"
	folder.Parent = workspace
	state.folder = folder
	drawZones(folder)
	local mine = state.serial
	task.spawn(function()
		local standsAt = -math.huge
		while state.on and state.serial == mine and folder.Parent do
			pcall(scanBays, folder)
			local now = os.clock()
			if now - standsAt >= STANDS_EVERY then
				standsAt = now
				pcall(scanStands, folder)
			end
			task.wait(REFRESH)
		end
	end)
	return true
end

return SandboxZones
