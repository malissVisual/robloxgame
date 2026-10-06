--!strict
-- 5.6, the alley shortcuts (shared/Shortcuts.luau has where): built once by server/World.luau (its build list:
-- "alley shortcuts"), after the districts. Each one, 15 native parts: a pale path over the two open lots, a low
-- two-rail fence across each end (it collides: hop it, Config.Shortcuts.FenceHeight), two small lamps that glow at
-- night (one carries a light), and a SHORTCUT sign by the first mouth, on the sidewalk off the people's walk line.
-- The lawn's trees and the parking lot's wreck that stood on the path (World rolls them at random on the lot) are
-- taken away first: nothing blocks the way but the fences. A Folder "Shortcuts", a Model per alley (Atomic streaming).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local ShortcutData = require(Shared.Shortcuts)
local DayNight = require(script.Parent.DayNight)

local Shortcuts = {}

local WALK_TOP = Map.WalkTop
local PATH = Color3.fromRGB(176, 170, 156)
local WOOD = Color3.fromRGB(150, 116, 78)
local METAL = Color3.fromRGB(46, 48, 52)
local LAMP_LIT = Color3.fromRGB(255, 220, 160)
local LAMP_DIM = Color3.fromRGB(150, 150, 144)

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

local function signFace(board: BasePart, face: Enum.NormalId)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(24, 27, 32)
	label.BorderSizePixel = 0
	label.Text = "SHORTCUT ⇢"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(242, 242, 240)
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.14, 0)
	pad.PaddingBottom = UDim.new(0.14, 0)
	pad.Parent = label
end

-- Takes away the trees and the wreck World put on the path (the strip `frame`, `size` big).
local function clearPath(world: Instance, frame: CFrame, size: Vector3)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { world }
	params.RespectCanCollide = false
	local trunks: { BasePart } = {}
	local wrecks: { [Instance]: boolean } = {}
	for _, hit in workspace:GetPartBoundsInBox(frame, size, params) do
		local wreck = hit:FindFirstAncestor("Wreck")
		if wreck and wreck:IsA("Model") then
			wrecks[wreck] = true
		elseif hit.Name == "Trunk" then
			table.insert(trunks, hit)
		end
	end
	for wreck in wrecks do
		wreck:Destroy()
	end
	for _, trunk in trunks do
		-- its crown: the Leaves ball right over it (World's tree())
		local parent = trunk.Parent
		if parent then
			for _, child in parent:GetChildren() do
				if child.Name == "Leaves" and child:IsA("BasePart") and math.abs(child.Position.X - trunk.Position.X) < 0.05 and math.abs(child.Position.Z - trunk.Position.Z) < 0.05 then
					child:Destroy()
				end
			end
		end
		trunk:Destroy()
	end
end

local function build(world: Instance, folder: Instance, alley: ShortcutData.Alley)
	local tuning = Config.Shortcuts
	local model = Instance.new("Model")
	model.Name = `Shortcut {alley.id}`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local a = Vector3.new(alley.x0, WALK_TOP, alley.z0)
	local b = Vector3.new(alley.x1, WALK_TOP, alley.z1)
	local along = (b - a).Unit
	local length = (b - a).Magnitude
	local frame = CFrame.lookAt((a + b) / 2, b) -- -Z along the path, X across it
	clearPath(world, frame * CFrame.new(0, 10, 0), Vector3.new(alley.width + 3, 20, length + 2))

	part(model, "Path", Vector3.new(alley.width, 0.1, length), frame * CFrame.new(0, 0.12, 0), PATH, Enum.Material.Concrete)
	-- The fences across both ends: two posts, two rails (they collide: hop them).
	for _, spot in alley.fences do
		local at = CFrame.lookAt(Vector3.new(spot.x, WALK_TOP, spot.z), Vector3.new(spot.x, WALK_TOP, spot.z) + along)
		local h = tuning.FenceHeight
		for _, side in { -1, 1 } do
			part(model, "FencePost", Vector3.new(0.35, h, 0.35), at * CFrame.new(side * (alley.width / 2 + 0.6), h / 2, 0), WOOD, Enum.Material.Wood, true)
		end
		for _, y in { h * 0.42, h - 0.2 } do
			part(model, "FenceRail", Vector3.new(alley.width + 1.6, 0.3, 0.22), at * CFrame.new(0, y, 0), WOOD, Enum.Material.WoodPlanks, true)
		end
	end
	-- The lamps beside the path (the first one carries a light).
	for n, spot in alley.lamps do
		part(model, "LampPole", Vector3.new(0.3, 8, 0.3), CFrame.new(spot.x, WALK_TOP + 4, spot.z), METAL, Enum.Material.Metal, true)
		local head = part(model, "Lamp", Vector3.new(0.9, 0.35, 0.9), CFrame.new(spot.x, WALK_TOP + 8.1, spot.z), LAMP_DIM, Enum.Material.SmoothPlastic)
		if n == 1 then
			local light = Instance.new("PointLight")
			light.Range = 24
			light.Brightness = 1.4
			light.Color = LAMP_LIT
			light.Shadows = false
			light.Parent = head
		end
		DayNight.nightLight(head, LAMP_LIT, LAMP_DIM, "SmoothPlastic")
	end
	-- The sign by the first mouth, its faces to the street and to the path.
	local sign = alley.sign
	part(model, "SignPost", Vector3.new(0.3, 6, 0.3), CFrame.new(sign.x, WALK_TOP + 3, sign.z), METAL, Enum.Material.Metal, true)
	local board = part(model, "Sign", Vector3.new(4.2, 1.1, 0.15), CFrame.lookAt(Vector3.new(sign.x, WALK_TOP + 5.4, sign.z), Vector3.new(sign.x, WALK_TOP + 5.4, sign.z) - along), Color3.fromRGB(24, 27, 32), Enum.Material.Metal)
	signFace(board, Enum.NormalId.Front)
	signFace(board, Enum.NormalId.Back)
	model:SetAttribute("Shortcut", alley.name)
	model.Parent = folder
end

-- Every alley (server/World.luau's build list, after the districts).
function Shortcuts.build(world: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "Shortcuts"
	folder.Parent = world
	for _, alley in ShortcutData.alleys() do
		local ok, err = pcall(function()
			build(world, folder, alley)
		end)
		if not ok then
			warn(`[Shortcuts] {alley.name}: {err}`)
		end
	end
end

return Shortcuts
