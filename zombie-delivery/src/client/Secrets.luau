--!strict
-- The lost packages on this client (Zombie Delivery 3.1). The server builds one at every place (server/World.luau:
-- models "LostPackage" with the attribute Secret in workspace.World.Secrets) and tells this client which ones its
-- player has found (the "Challenges" remote: ("state", S) with S.secrets). A found package vanishes for this player
-- only: every part's LocalTransparencyModifier goes to 1 and its prompt, its "?" and its glow switch off here (the
-- other players still see theirs). A reset (the admin's challengesReset) brings them back.
--
-- The ones not found yet come a little alive when the player is close: a gentle bob and sway, a pulsing glow and a few
-- sparkles, so somebody walking past notices one. Cheap: the nearby ones are looked for twice a second (at most
-- MAX_ALIVE of them), and they move 30 times a second only while there are any.
--
-- The packages may stream in and out (StreamingEnabled; each streams as a whole): the folder is watched and every
-- package that arrives gets the look it should have.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Secrets = {}

local NEAR = 45 -- the unfound packages within this many studs of the player come alive
local MAX_ALIVE = 4
local SCAN = 0.5 -- seconds between looks for the nearby ones
local STEP = 1 / 30 -- the animation's step
local BOB = 0.08 -- studs: the box rises 0 … 2 × BOB (never below its floor)
local SWAY = math.rad(4)
local GLOW = 0.6 -- the glow's brightness as World builds it

type Package = {
	model: Model,
	id: string,
	home: CFrame, -- its pivot as the server built it (the bob moves it around this)
	hidden: boolean, -- found: hidden for this player
	alive: boolean,
	phase: number,
	glow: PointLight?,
	sparkle: ParticleEmitter?,
	added: RBXScriptConnection,
}

local packages: { [Model]: Package } = {}
local found: { [string]: boolean } = {}
local alive: { Package } = {}
local stepper: RBXScriptConnection? = nil
local started = false

-- Shows or hides one thing of a package (a part, the prompt, the "?", the glow, the sparkles).
local function show(thing: Instance, visible: boolean)
	if thing:IsA("BasePart") then
		thing.LocalTransparencyModifier = if visible then 0 else 1
	elseif thing:IsA("ProximityPrompt") then
		thing.Enabled = visible
	elseif thing:IsA("BillboardGui") then
		thing.Enabled = visible
	elseif thing:IsA("Light") then
		thing.Enabled = visible
	elseif thing:IsA("ParticleEmitter") then
		thing.Enabled = visible
	end
end

-- Stops a package's animation: back to where the server put it, the glow as it was, the sparkles gone.
local function calm(pkg: Package)
	pkg.alive = false
	if pkg.model.Parent then
		pkg.model:PivotTo(pkg.home)
	end
	if pkg.glow then
		pkg.glow.Brightness = GLOW
	end
	if pkg.sparkle then
		pkg.sparkle:Destroy()
		pkg.sparkle = nil
	end
	local index = table.find(alive, pkg)
	if index then
		table.remove(alive, index)
	end
end

-- Gives a package the look it should have for this player (found: hidden).
local function apply(pkg: Package)
	local hidden = found[pkg.id] == true
	pkg.hidden = hidden
	if hidden and pkg.alive then
		calm(pkg)
	end
	for _, thing in pkg.model:GetDescendants() do
		show(thing, not hidden)
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or model.Name ~= "LostPackage" or packages[model] then
		return
	end
	local id = model:GetAttribute("Secret")
	if type(id) ~= "string" then
		return
	end
	local glow = model:FindFirstChild("Glow", true)
	local pkg: Package = {
		model = model,
		id = id,
		home = model:GetPivot(),
		hidden = false,
		alive = false,
		phase = (#id * 1.7) % (math.pi * 2),
		glow = if glow and glow:IsA("PointLight") then glow else nil,
		-- A part that streams in late gets the same look as the rest.
		added = model.DescendantAdded:Connect(function(thing)
			local current = packages[model]
			if current then
				show(thing, not current.hidden)
			end
		end),
	}
	packages[model] = pkg
	apply(pkg)
end

local function untrack(model: Instance)
	local pkg = packages[model :: Model]
	if not pkg then
		return
	end
	pkg.added:Disconnect()
	if pkg.alive then
		calm(pkg)
	end
	packages[model :: Model] = nil
end

-- The server's ("state", S): S.secrets = { [id] = true } for the ones this player has found.
local function setState(state: any)
	if type(state) ~= "table" or type(state.secrets) ~= "table" then
		return
	end
	local now: { [string]: boolean } = {}
	for id, value in state.secrets do
		if type(id) == "string" and value then
			now[id] = true
		end
	end
	found = now
	for _, pkg in packages do
		if (found[pkg.id] == true) ~= pkg.hidden then
			apply(pkg)
		end
	end
end

-- The bob, the sway, the pulsing glow of the nearby unfound ones (30 times a second, only while there are any).
local function animate()
	local clock = os.clock()
	for _, pkg in alive do
		local t = clock * 2.2 + pkg.phase
		local lift = BOB * (1 + math.sin(t))
		local turn = SWAY * math.sin(t * 0.5)
		pkg.model:PivotTo(pkg.home * CFrame.new(0, lift, 0) * CFrame.Angles(0, turn, 0))
		if pkg.glow then
			pkg.glow.Brightness = GLOW * (1.25 + 0.5 * math.sin(t * 1.3))
		end
	end
end

local function wake(pkg: Package)
	pkg.alive = true
	table.insert(alive, pkg)
	local box = pkg.model.PrimaryPart
	if box then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "Sparkle"
		sparkle.Rate = 3
		sparkle.Lifetime = NumberRange.new(0.8, 1.4)
		sparkle.Speed = NumberRange.new(0.4, 1.2)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 226, 140))
		sparkle.LightEmission = 1
		sparkle.Acceleration = Vector3.new(0, 0.6, 0)
		sparkle.Parent = box
		pkg.sparkle = sparkle
	end
end

-- Where the player is: the character (on foot or in a seat), else the camera.
local function focus(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.Focus.Position else nil
end

-- Which unfound packages are near now: wake the new ones, calm the ones left behind; run the stepper only when needed.
local function scan()
	local at = focus()
	local near: { { pkg: Package, distance: number } } = {}
	if at then
		for _, pkg in packages do
			if not pkg.hidden and pkg.model.Parent then
				local distance = (pkg.home.Position - at).Magnitude
				if distance < NEAR then
					table.insert(near, { pkg = pkg, distance = distance })
				end
			end
		end
	end
	table.sort(near, function(a, b)
		return a.distance < b.distance
	end)
	local want: { [Package]: boolean } = {}
	for n = 1, math.min(#near, MAX_ALIVE) do
		want[near[n].pkg] = true
	end
	for _, pkg in table.clone(alive) do
		if not want[pkg] then
			calm(pkg)
		end
	end
	for pkg in want do
		if not pkg.alive then
			wake(pkg)
		end
	end
	if #alive > 0 and not stepper then
		local since = 0
		stepper = RunService.RenderStepped:Connect(function(dt: number)
			since += dt
			if since >= STEP then
				since = 0
				animate()
			end
		end)
	elseif #alive == 0 and stepper then
		stepper:Disconnect()
		stepper = nil
	end
end

-- A child that may not be there yet (the server builds the world piece by piece), without the infinite-yield warning.
local function childOf(parent: Instance, name: string): Instance
	local child = parent:FindFirstChild(name)
	while child == nil do
		parent.ChildAdded:Wait()
		child = parent:FindFirstChild(name)
	end
	return child :: Instance
end

function Secrets.start()
	if started then
		return
	end
	started = true
	Net.get("Challenges").OnClientEvent:Connect(function(kind: any, payload: any)
		if kind == "state" then
			setState(payload)
		end
	end)
	task.spawn(function()
		local folder = childOf(childOf(workspace, "World"), "Secrets")
		folder.ChildAdded:Connect(track)
		folder.ChildRemoved:Connect(untrack)
		for _, child in folder:GetChildren() do
			track(child)
		end
		while true do
			task.wait(SCAN)
			local ok, err = pcall(function()
				scan()
			end)
			if not ok then
				warn(`[Secrets] {err}`)
				task.wait(5)
			end
		end
	end)
end

return Secrets
