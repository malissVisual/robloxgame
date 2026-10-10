--!strict
-- 6.22, every thing in the inventory has a look (the owner: "every thing must look like something, not only an icon"):
-- a thing (a shared/ItemLooks.luau key: "gun:pistol", "item:medkit", "kit:tote", "cargo:pizza", "fists" …) drawn as
-- a small 3D model in a ViewportFrame, the same studio look everywhere: the 3/4 angle, a soft key light and fill
-- (Config.ItemModel: Ambient, LightColor, LightDirection), a transparent background, the camera fitted to the model's
-- box. The bottom bar's slots (client/Hotbar.luau), BAG & ITEMS (client/BagUi.luau: the hero, the rows, the cargo
-- stack; client/CardKit.luau's picture `model`) use it; the icon or the emoji is only the fallback when a model can't
-- be built.
--   ItemModel.view(parent, key, spec?) -> ViewportFrame?   a ViewportFrame "ItemModel" in `parent` (its Look attribute
--       the key) with a copy of the model; nil when the key has no look or its build failed (the caller shows the
--       icon). spec: size (UDim2, default the parent), position, anchor, z, aspect (width over height, default 1),
--       dim (a slot you can't take now: faint), shut (a locked row: greyed), spin (the hero's slow turn)
--   ItemModel.has(key)   whether the key has a look of its own
-- Each model is built once a key (the cache) and copied into each view; the views are still pictures (no per-frame
-- work) except a spinning hero, turned SpinRate times a second by one shared loop while it is on screen and never with
-- Reduced Motion (client/PhoneMotion.luau). The copies are inert: anchored parts only, no lights, labels or smoke.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemLooks = require(Shared.ItemLooks)
local Ui = require(script.Parent.Ui)
local PhoneMotion = require(script.Parent.PhoneMotion)

local ItemModel = {}

local LOOK = Config.ItemModel
local NAME = "ItemModel"
local GREY = Color3.fromRGB(150, 152, 156)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function vec(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

-- A model a key (false: its build failed once, not tried again).
local cache: { [string]: any } = {}

-- What a view does not need: only the parts stay.
local INERT = { "SurfaceGui", "BillboardGui", "Smoke", "ParticleEmitter", "Light", "Attachment", "WeldConstraint", "JointInstance" }

local function template(key: string): Model?
	local known = cache[key]
	if known ~= nil then
		return if known == false then nil else known
	end
	local ok, made = pcall(ItemLooks.build, key)
	if not ok or not made then
		warn(`[ItemModel] {key}: {made}`)
		cache[key] = false
		return nil
	end
	local model = made :: Model
	for _, obj in model:GetDescendants() do
		for _, class in INERT do
			if obj:IsA(class) then
				obj:Destroy()
				break
			end
		end
	end
	cache[key] = model
	return model
end

function ItemModel.has(key: string?): boolean
	if not key or key == "" then
		return false
	end
	local ok, has = pcall(ItemLooks.has, key)
	return ok and has == true
end

-- ── The spinning heroes ─────────────────────────────────────────────────────

type Spinner = { viewport: any, camera: any, centre: Vector3, radius: number, height: number, angle: number }
local spinners: { Spinner } = {}
local loop: RBXScriptConnection? = nil
local since = 0

local function place(s: Spinner)
	local a = math.rad(s.angle)
	local eye = s.centre + Vector3.new(math.sin(a) * s.radius, s.height, -math.cos(a) * s.radius)
	s.camera.CFrame = CFrame.lookAt(eye, s.centre)
end

local function spinStep(dt: number)
	since += dt
	if since < 1 / LOOK.SpinRate then
		return
	end
	local step = since
	since = 0
	for index = #spinners, 1, -1 do
		local s = spinners[index]
		if not s.viewport.Parent then
			table.remove(spinners, index)
		elseif s.viewport.Visible then
			s.angle = (s.angle + LOOK.Spin * step) % 360
			place(s)
		end
	end
	if #spinners == 0 and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function spin(s: Spinner)
	table.insert(spinners, s)
	if not loop then
		since = 0
		loop = RunService.Heartbeat:Connect(spinStep)
	end
end

-- ── A view ──────────────────────────────────────────────────────────────────

export type Spec = { size: UDim2?, position: UDim2?, anchor: Vector2?, z: number?, aspect: number?, dim: boolean?, shut: boolean?, spin: boolean?, name: string? }

function ItemModel.view(parent: Instance, key: string?, spec: Spec?): any
	if not key or key == "" then
		return nil
	end
	local model = template(key)
	if not model then
		return nil
	end
	local s: Spec = spec or {}
	local copy = model:Clone()
	local viewport = Ui.make("ViewportFrame", {
		Name = s.name or NAME,
		Size = s.size or UDim2.fromScale(1, 1),
		Position = s.position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = s.anchor or Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Ambient = rgb(LOOK.Ambient),
		LightColor = rgb(LOOK.LightColor),
		LightDirection = vec(LOOK.LightDirection),
		ImageTransparency = if s.dim then LOOK.Dim elseif s.shut then LOOK.Shut else 0,
		ImageColor3 = if s.shut then GREY else Color3.new(1, 1, 1),
		ZIndex = s.z or 1,
	}, parent)
	viewport:SetAttribute("Look", key)
	copy.Parent = viewport
	local lo, hi = ItemLooks.bounds(copy)
	local turning = s.spin == true and not PhoneMotion.reducedMotion()
	local eye, centre = ItemLooks.frame(lo, hi, s.aspect or 1, turning)
	local camera = Ui.make("Camera", { FieldOfView = LOOK.Fov }, viewport)
	camera.CFrame = CFrame.lookAt(vec(eye), vec(centre))
	viewport.CurrentCamera = camera
	if turning then
		local dx, dz = eye[1] - centre[1], eye[3] - centre[3]
		spin({ viewport = viewport, camera = camera, centre = vec(centre), radius = math.sqrt(dx * dx + dz * dz), height = eye[2] - centre[2], angle = LOOK.Yaw })
		viewport:SetAttribute("Spin", true)
	end
	return viewport
end

return ItemModel
