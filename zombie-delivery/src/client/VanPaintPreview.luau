--!strict
-- 8.3 SANDBOX, the PAINT shop's 3D picture (client/VanPaintUi.luau's left): your own van in the paint and the livery you
-- are looking at, before you buy or wear them. A local, still copy of your van out in the world (workspace.Cars: its
-- OwnerId yours; the owner's Blender look too, as it is dressed) in a ViewportFrame, painted with shared/VanLook.luau
-- exactly as the server paints the real one; with no van of yours in reach a copy of the parts look
-- (shared/SprinterLooks.luau) stands in. The copy is made once a window (show keeps it while the window is open, the
-- next look only paints it again; clear drops it) and holds nothing that moves or works: no joints, prompts, seats'
-- welds, lights, sounds or code, every part anchored, nothing collides.
--   VanPaintPreview.show(holder, look)   the van in `look` (VanPaintRules.Look) in a ViewportFrame filling `holder`
--   VanPaintPreview.release()            the window is drawn anew: the copy taken out of its frame (kept for the next
--                                        show), the frame goes
--   VanPaintPreview.clear()              the window closed: the copy and its frame go
--   VanPaintPreview.camera(lo, hi, aspect)   the eye and the middle for a box (Config.VanPaint.Window: Yaw, Pitch, Fov,
--                                        Fill; pure)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local VanLook = require(Shared.VanLook)
local Rules = require(Shared.VanPaintRules)
local SprinterLooks = require(Shared.SprinterLooks)

local VanPaintPreview = {}

local WIN = Config.VanPaint.Window
local LIGHT = Config.ItemModel
local INERT = { "JointInstance", "WeldConstraint", "Constraint", "ProximityPrompt", "BaseScript", "Light", "Sound", "ParticleEmitter", "Smoke", "Fire", "Sparkles", "Attachment", "BillboardGui" }

local copy: Model? = nil -- the van's copy (made once a window)
local source: Instance? = nil -- the live van it was made of (nil: the parts look's stand-in)
local view: ViewportFrame? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Your van out in the world (the newest one in workspace.Cars with your OwnerId).
local function liveVan(): Model?
	local cars = workspace:FindFirstChild("Cars")
	local me = Players.LocalPlayer
	if not cars or not me then
		return nil
	end
	for _, child in cars:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("OwnerId") == me.UserId and (child:GetAttribute("SprinterArt") ~= nil or child:GetAttribute("CarId") == Config.Sandbox.Van) then
			return child
		end
	end
	return nil
end

local function still(model: Model)
	for _, d in model:GetDescendants() do
		local gone = false
		for _, class in INERT do
			if d:IsA(class) then
				gone = true
				break
			end
		end
		if gone then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
		end
	end
end

-- A part of the stand-in: a SprinterLooks piece in its finish (the paint: VanPaintRole "body", the stripes:
-- FleetFinish "stripe", as on the real van).
local function piece(model: Model, p: SprinterLooks.Piece)
	if p.clear then
		return
	end
	local finish = SprinterLooks.Finish[p.finish] or SprinterLooks.Finish.trim
	local part = Instance.new(if p.shape == "Wedge" then "WedgePart" else "Part") :: BasePart
	part.Name = p.name
	part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
	local turn = p.turn or { 0, 0, 0 }
	part.CFrame = CFrame.new(p.at[1], p.at[2], p.at[3]) * CFrame.Angles(math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3]))
	part.Color = if finish.color then rgb(finish.color) else rgb(Rules.look(Rules.Default).body)
	local material = (Enum.Material :: any)[finish.material]
	if material then
		part.Material = material
	end
	part.Transparency = finish.transparency or 0
	part.Reflectance = finish.reflectance or 0
	if p.shape == "Cylinder" then
		(part :: Part).Shape = Enum.PartType.Cylinder
	end
	if finish.color == nil then
		part:SetAttribute("VanPaintRole", "body")
	elseif p.finish == "stripe" then
		part:SetAttribute("FleetFinish", "stripe")
	end
	part.Parent = model
end

-- The parts look's van (shared/SprinterLooks.luau: the body, the cab doors, the sliding door, the back doors, the
-- wheels), its ground under its middle at the origin.
local function standIn(): Model
	local model = Instance.new("Model")
	model.Name = "VanStandIn"
	local S = Config.Sprinter
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(S.Width - 0.4, 1.2, SprinterLooks.Length)
	chassis.CFrame = CFrame.new(0, SprinterLooks.Top - 0.6, 0) -- (its top the floor: VanLook's ground at the origin)
	chassis.Transparency = 1
	chassis.Parent = model
	model.PrimaryPart = chassis
	for _, p in SprinterLooks.body() do
		piece(model, p)
	end
	for _, side in { -1, 1 } do
		for _, p in SprinterLooks.door(side) do
			piece(model, p)
		end
	end
	for _, p in (SprinterLooks.slider()) do
		piece(model, p)
	end
	for _, leaf in SprinterLooks.leaves() do
		piece(model, { name = "BackDoor", size = leaf.size, at = leaf.center, finish = "paint" })
		for _, p in leaf.pieces do
			piece(model, p)
		end
	end
	for _, x in { -SprinterLooks.Track, SprinterLooks.Track } do
		for _, z in { -SprinterLooks.Axle, SprinterLooks.Axle } do
			local tyre = Instance.new("Part")
			tyre.Name = "Tyre"
			tyre.Shape = Enum.PartType.Cylinder
			tyre.Size = Vector3.new(1, 2 * S.Wheel, 2 * S.Wheel)
			tyre.CFrame = CFrame.new(x, S.Wheel, z)
			tyre.Color = Color3.fromRGB(28, 29, 31)
			tyre.Parent = model
		end
	end
	return model
end

function VanPaintPreview.camera(lo: { number }, hi: { number }, aspect: number): ({ number }, { number })
	local c = { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }
	local hx, hy, hz = (hi[1] - lo[1]) / 2, (hi[2] - lo[2]) / 2, (hi[3] - lo[3]) / 2
	local yaw, pitch = math.rad(WIN.Yaw), math.rad(WIN.Pitch)
	local d = { math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch) } -- toward the eye
	local rl = math.sqrt(d[3] * d[3] + d[1] * d[1])
	local right = { -d[3] / rl, 0, d[1] / rl }
	local up = { right[2] * d[3] - right[3] * d[2], right[3] * d[1] - right[1] * d[3], right[1] * d[2] - right[2] * d[1] }
	local function extent(a: { number }): number
		return math.abs(a[1]) * hx + math.abs(a[2]) * hy + math.abs(a[3]) * hz
	end
	local t = math.tan(math.rad(WIN.Fov / 2))
	local fit = math.max(extent(up) / t, extent(right) / (t * math.max(0.2, aspect)))
	local distance = fit / WIN.Fill + extent(d)
	return { c[1] + d[1] * distance, c[2] + d[2] * distance, c[3] + d[3] * distance }, c
end

local function frameIt(frame: ViewportFrame, model: Model, holder: GuiObject)
	local cf, size = model:GetBoundingBox()
	local lo = { cf.Position.X - size.X / 2, cf.Position.Y - size.Y / 2, cf.Position.Z - size.Z / 2 }
	local hi = { cf.Position.X + size.X / 2, cf.Position.Y + size.Y / 2, cf.Position.Z + size.Z / 2 }
	local pixels = holder.AbsoluteSize
	local aspect = if pixels.Y > 0 then pixels.X / pixels.Y else 1.4
	local eye, centre = VanPaintPreview.camera(lo, hi, aspect)
	local camera = frame:FindFirstChildOfClass("Camera") or Instance.new("Camera")
	camera.FieldOfView = WIN.Fov
	camera.CFrame = CFrame.lookAt(Vector3.new(eye[1], eye[2], eye[3]), Vector3.new(centre[1], centre[2], centre[3]))
	camera.Parent = frame
	frame.CurrentCamera = camera
end

function VanPaintPreview.show(holder: GuiObject, look: Rules.Look): boolean
	local live = liveVan()
	if copy and source ~= live then
		VanPaintPreview.clear() -- (a new van of yours came out: copied anew)
	end
	if not copy then
		local made: Model
		if live and live.Archivable then
			made = live:Clone()
			still(made)
			made:PivotTo(CFrame.new()) -- (its chassis at the origin)
		else
			made = standIn()
			still(made)
		end
		copy, source = made, live
	end
	local model = copy :: Model
	VanLook.apply(model, look, { anchored = true })
	local shown = view
	if not shown or shown.Parent ~= holder then
		VanPaintPreview.release()
		local frame = Instance.new("ViewportFrame")
		frame.Name = "VanPreview"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundTransparency = 1
		frame.Ambient = rgb(LIGHT.Ambient)
		frame.LightColor = rgb(LIGHT.LightColor)
		frame.LightDirection = Vector3.new(LIGHT.LightDirection[1], LIGHT.LightDirection[2], LIGHT.LightDirection[3])
		frame.Parent = holder
		local world = Instance.new("WorldModel")
		world.Parent = frame
		model.Parent = world
		view = frame
		frameIt(frame, model, holder)
	end
	return true
end

function VanPaintPreview.release()
	if copy then
		copy.Parent = nil
	end
	if view then
		view:Destroy()
		view = nil
	end
end

function VanPaintPreview.clear()
	if view then
		view:Destroy()
		view = nil
	end
	if copy then
		copy:Destroy()
		copy = nil
	end
	source = nil
end

return VanPaintPreview
