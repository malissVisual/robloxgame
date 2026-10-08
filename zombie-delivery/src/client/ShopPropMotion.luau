--!strict
-- 6.11, the rooftop props that move (server/ShopProps.luau tags their moving part, a Model, "ShopPropMotion"): the
-- bank's gold coin spins on its dome, Luigi's pizza slice bobs and sways. Only on this client and only for the eye:
-- the server never moves them (anchored, no collisions). Cheap: about 30 updates a second, only the props within RANGE
-- of the camera, one PivotTo each. StreamingEnabled: a prop streams as a whole (Atomic); one that streams out leaves the
-- list with its tag, one that streams back in is picked up again and starts from its "Rest" pose (a CFrame attribute;
-- without it, where the prop stood when it came in).
--   Motion "spin": Rate (radians a second) about its pivot's up axis.
--   Motion "bob":  Amplitude (studs) up and down over Period (seconds), turning ±Sway degrees at half that pace.
-- Started from client/Main.client.luau: safely("ShopPropMotion", require(Client.ShopPropMotion).start)

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ShopPropMotion = {}

local TAG = "ShopPropMotion" -- (server/ShopProps.luau ShopProps.Tag)
local STEP = 1 / 30 -- seconds between updates
local RANGE = 700 -- studs from the camera (the coin on the bank's dome is seen from far)
local TAU = 2 * math.pi

local function number(model: Model, name: string): number
	local value = model:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

function ShopPropMotion.start()
	local items: { Model } = {}
	local poses: { [Model]: CFrame } = {} -- (where each stood when it came in, before we moved it)
	local function add(item: Instance)
		if item:IsA("Model") and not table.find(items, item) then
			table.insert(items, item)
			poses[item] = item:GetPivot()
		end
	end
	for _, item in CollectionService:GetTagged(TAG) do
		add(item)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(item: Instance)
		local at = table.find(items, item :: any)
		if at then
			table.remove(items, at)
		end
		poses[item :: any] = nil
	end)
	local clock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		if clock < STEP or #items == 0 then
			return
		end
		clock = 0
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local now = os.clock()
		for _, model in items do
			local saved = model:GetAttribute("Rest")
			local rest: CFrame? = if typeof(saved) == "CFrame" then saved else poses[model]
			if not rest or not model.Parent or (rest.Position - eye).Magnitude > RANGE then
				continue
			end
			local kind = model:GetAttribute("Motion")
			if kind == "spin" then
				model:PivotTo(rest * CFrame.Angles(0, (now * number(model, "Rate")) % TAU, 0))
			elseif kind == "bob" then
				local period = math.max(number(model, "Period"), 0.5)
				local phase = now * TAU / period
				local sway = math.rad(number(model, "Sway")) * math.sin(phase * 0.5)
				model:PivotTo(rest * CFrame.new(0, math.sin(phase) * number(model, "Amplitude"), 0) * CFrame.Angles(0, sway, 0))
			end
		end
	end)
end

return ShopPropMotion
