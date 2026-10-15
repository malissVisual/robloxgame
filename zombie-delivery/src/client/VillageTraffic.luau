--!strict
-- 8.9 SANDBOX, Jinočany: the D5's cars (design/jinocany/NAVRH.md §4: "a few cars that move only on the clients"). This
-- screen's own (made here, never sent anywhere): Config.VillageWorld.Cars' cars on the D5's four lanes
-- (shared/VillageScenery.luau lanes: the carriageways of server/VillageWorld.luau's Motorway, a Persistent model every
-- client has, run on past the Bounds onto the far view's D5, where they go round again unseen). Northbound on the
-- carriageway east of the middle, southbound on the other (right-hand traffic). A car is two parts, its body and its
-- cabin (anchored, never colliding nor in a ray's way, no shadows), each sliding along its lane by a TweenService tween
-- (no code of ours every frame): from where it starts to the lane's end once, then from the lane's start to its end
-- over and over.
--
--   VillageTraffic.start()   once (client/Main.client.luau, the sandbox's own modules); nothing without the D5
--   VillageTraffic.cars()    the cars made ({ body, cabin } each)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local VillageScenery = require(Shared.VillageScenery)

local VillageTraffic = {}

export type Car = { body: Part, cabin: Part }

local C = Config.VillageWorld.Cars
local LIFT = 0.35 -- studs from the asphalt to a car's body (its wheels, unseen at this distance)

local started = false
local made: { Car } = {}

-- The dice: a Lehmer generator (the same cars on every screen).
local state = 90210
local function roll(): number
	state = (state * 48271) % 2147483647
	return (state - 1) / 2147483646
end

local function piece(parent: Instance, name: string, size: Vector3, color: Color3, look: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = look
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Slides a part from `at` to `to` (its own turn kept), then from `from` to `to` again and again, `speed` studs/s.
local function drive(part: BasePart, from: CFrame, at: CFrame, to: CFrame, speed: number)
	local first = TweenService:Create(part, TweenInfo.new((to.Position - at.Position).Magnitude / speed, Enum.EasingStyle.Linear), { CFrame = to })
	first.Completed:Once(function()
		part.CFrame = from
		TweenService:Create(part, TweenInfo.new((to.Position - from.Position).Magnitude / speed, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { CFrame = to }):Play()
	end)
	part.CFrame = at
	first:Play()
end

function VillageTraffic.start()
	if started then
		return
	end
	started = true
	local lanes = VillageScenery.lanes()
	if #lanes == 0 then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "VillageTraffic"
	holder.Parent = workspace
	local w, h, l = C.Size[1], C.Size[2], C.Size[3]
	for n = 1, C.Count do
		local lane = lanes[(n - 1) % #lanes + 1]
		local share = (math.floor((n - 1) / #lanes) + roll() * 0.6) / math.ceil(C.Count / #lanes) -- (spread along the lane)
		local speed = C.Speed * (1 + (roll() * 2 - 1) * C.Spread)
		local z0, z1 = if lane.dz < 0 then lane.z1 else lane.z0, if lane.dz < 0 then lane.z0 else lane.z1
		local turn = CFrame.Angles(0, if lane.dz < 0 then 0 else math.pi, 0) -- (its front, -Z, the way it goes)
		local color = C.Colors[math.floor(roll() * #C.Colors) % #C.Colors + 1]
		local y = lane.y + LIFT + h / 2
		local body = piece(holder, "Car", Vector3.new(w, h, l), Color3.fromRGB(color[1], color[2], color[3]), Enum.Material.SmoothPlastic)
		local cabin = piece(holder, "CarCabin", Vector3.new(w - 0.6, C.Cabin[2], l * C.Cabin[1]), Color3.fromRGB(48, 58, 66), Enum.Material.Glass)
		local up = CFrame.new(0, h / 2 + C.Cabin[2] / 2, l * 0.08) -- (on the body, a little back)
		for _, p in { { part = body :: BasePart, off = CFrame.new() }, { part = cabin :: BasePart, off = up } } do
			local from = CFrame.new(lane.x, y, z0) * turn * p.off
			local to = CFrame.new(lane.x, y, z1) * turn * p.off
			local at = CFrame.new(lane.x, y, z0 + (z1 - z0) * share) * turn * p.off
			drive(p.part, from, at, to, speed)
		end
		table.insert(made, { body = body, cabin = cabin })
	end
end

function VillageTraffic.cars(): { Car }
	return made
end

return VillageTraffic
