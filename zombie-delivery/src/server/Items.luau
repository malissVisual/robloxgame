--!strict
-- The consumables (used from the hotbar) and the supply crates lying around the world.
--
--   Repair Kit  +40 % car health          Medkit   full player health
--   Nitro       a speed boost (client)     Molotov  a burning patch where you aim
--   Landmine    dropped behind the car, blows up when a zombie steps close
--   Jerry Can   5.4: +10 L of fuel into your car, standing by it or sitting in it (server/Fuel.luau pourCan)
--   Energy Drink  6.7: on foot: the character's EnergyUntil = now + EnergyTime (server time); client/Stamina.luau fills
--               the breath and stretches the sprint (× EnergyBreath) until then
-- 6.7: a supply crate gives a player only the items that are for them (Economy.itemsFor: the car-only items, Config.Items
-- car, only to a player who owns a car). Using one still only needs a car at hand (a lent one too), as before.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy) -- 6.7: the car-only items
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)
local BanditCars = require(script.Parent.BanditCars)
local PlayerData = require(script.Parent.PlayerData)

local Tuning = Config.ItemTuning
local Items = {}

local lastUse: { [Player]: number } = {}
local rng = Random.new()
local notice = Net.get("Notice")

local effects: Instance = workspace

local function effectPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Parent = effects
	return p
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The ground under a point (a road is at RoadTop, the yards too).
local function ground(point: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Cars") or workspace.Terrain, workspace:FindFirstChild("Zombies") or workspace.Terrain, effects }
	local result = workspace:Raycast(point + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return if result then result.Position else Vector3.new(point.X, World.RoadTop, point.Z)
end

-- ── The items ──────────────────────────────────────────────────────────────

local function molotov(player: Player, target: Vector3?): string?
	local car = Vehicles.seatedIn(player)
	local root = rootOf(player)
	local from = if car then car.chassis.Position + Vector3.new(0, 5, 0) elseif root then root.Position else nil
	if not from then
		return "You cannot throw now."
	end
	local aim = target or (from + (if car then car.chassis.CFrame.LookVector else Vector3.new(0, 0, -1)) * 40)
	local offset = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z)
	if offset.Magnitude > Tuning.MolotovRange then
		offset = offset.Unit * Tuning.MolotovRange
	end
	local landing = ground(from + offset)
	Net.get("Tracer"):FireAllClients(from, landing, Color3.fromRGB(255, 140, 40), 0)
	local radius = Tuning.MolotovRadius
	local patch = effectPart("Fire", Vector3.new(0.3, radius * 2, radius * 2), CFrame.new(landing + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 110, 30), Enum.Material.Neon)
	patch.Shape = Enum.PartType.Cylinder
	patch.Transparency = 0.45
	for n = 1, 4 do
		local angle = n * math.pi / 2
		local spot = effectPart("Flame", Vector3.new(1, 1, 1), CFrame.new(landing + Vector3.new(math.cos(angle), 0, math.sin(angle)) * radius * 0.5), Color3.new(1, 0.5, 0), Enum.Material.Neon)
		spot.Transparency = 1
		local fire = Instance.new("Fire")
		fire.Size = 10
		fire.Heat = 12
		fire.Parent = spot
		spot.Parent = patch
	end
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 140, 60)
	glow.Range = radius * 2.5
	glow.Brightness = 3
	glow.Parent = patch
	task.spawn(function()
		local ends = os.clock() + Tuning.MolotovTime
		while os.clock() < ends do
			Zombies.damageArea(landing, radius, Tuning.MolotovDps * 0.5, player)
			BanditCars.damageArea(landing, radius, Tuning.MolotovDps * 0.5, player)
			task.wait(0.5)
		end
		patch:Destroy()
	end)
	return nil
end

local mines: { [Player]: { Part } } = {}

local function explodeMine(owner: Player, mine: Part)
	local list = mines[owner]
	if list then
		local index = table.find(list, mine)
		if index then
			table.remove(list, index)
		end
	end
	if not mine.Parent then
		return
	end
	local position = mine.Position
	mine:Destroy()
	local blast = Instance.new("Explosion")
	blast.BlastPressure = 0
	blast.DestroyJointRadiusPercent = 0
	blast.BlastRadius = Tuning.MineRadius
	blast.Position = position
	blast.Parent = workspace
	local by = if owner.Parent then owner else nil
	Zombies.damageArea(position, Tuning.MineRadius, Tuning.MineDamage, by)
	BanditCars.damageArea(position, Tuning.MineRadius, Tuning.MineDamage, by)
end

local function dropMine(player: Player): string?
	local car, driving = Vehicles.seatedIn(player)
	if not car or not driving then
		return "Drive your car to drop a mine."
	end
	local list = mines[player] or {}
	mines[player] = list
	if #list >= Tuning.MineMax then
		explodeMine(player, list[1])
	end
	local behind = (car.chassis.CFrame * CFrame.new(0, 0, car.size.Z / 2 + 4)).Position
	local at = ground(behind)
	local mine = effectPart("Landmine", Vector3.new(0.6, 3, 3), CFrame.new(at + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(50, 56, 44), Enum.Material.Metal)
	mine.Shape = Enum.PartType.Cylinder
	local dot = effectPart("Blink", Vector3.new(0.6, 0.6, 0.6), CFrame.new(at + Vector3.new(0, 0.8, 0)), Color3.fromRGB(255, 30, 30), Enum.Material.Neon)
	dot.Parent = mine
	table.insert(list, mine)
	task.spawn(function()
		local born = os.clock()
		while mine.Parent do
			if os.clock() - born > Tuning.MineLife then
				mine:Destroy()
				break
			end
			dot.Transparency = if dot.Transparency == 0 then 0.7 else 0
			if os.clock() - born > 1 and BanditCars.near(at, Tuning.MineTrigger + 4) then
				explodeMine(player, mine)
				break
			end
			if os.clock() - born > 1 then
				for _, z in Zombies.all() do
					if not z.dead and (z.root.Position - at).Magnitude < Tuning.MineTrigger * z.def.scale then
						explodeMine(player, mine)
						break
					end
				end
			end
			task.wait(0.2)
		end
		local index = table.find(list, mine)
		if index then
			table.remove(list, index)
		end
	end)
	return nil
end

-- Returns an error text, or nil when the item was used.
local function apply(player: Player, id: string, target: Vector3?): string?
	local body = player.Character
	if (id == "repair" or id == "molotov" or id == "jerrycan") and body and body:GetAttribute("Carrying") ~= nil then
		return "Your hands are full. Put it down first (G)."
	end
	if id == "repair" then
		local car = Vehicles.get(player)
		local root = rootOf(player)
		if not car or not root or (car.chassis.Position - root.Position).Magnitude > 30 then
			return "Stand next to your car to repair it."
		end
		if car.health >= car.stats.health then
			return "Your car is not damaged."
		end
		Vehicles.repair(car, Tuning.RepairShare)
		notice:FireClient(player, "Car repaired!")
		return nil
	elseif id == "medkit" then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or humanoid.Health >= humanoid.MaxHealth then
			return "You are not hurt."
		end
		humanoid.Health = humanoid.MaxHealth
		return nil
	elseif id == "nitro" then
		if not Vehicles.isDriving(player) then
			return "Drive your car to use nitro."
		end
		Net.get("Boost"):FireClient(player, Tuning.NitroTime, Tuning.NitroMultiplier)
		return nil
	elseif id == "molotov" then
		return molotov(player, target)
	elseif id == "mine" then
		return dropMine(player)
	elseif id == "jerrycan" then
		return require(script.Parent.Fuel).pourCan(player) -- 5.4
	elseif id == "energy" then
		-- 6.7: on foot, alive: the breath full and the sprint longer for EnergyTime (a second can starts it over)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then
			return "You cannot drink that now."
		end
		if humanoid.SeatPart ~= nil then
			return "Drink it on foot: it's for the sprint."
		end
		character:SetAttribute("EnergyUntil", workspace:GetServerTimeNow() + Tuning.EnergyTime)
		notice:FireClient(player, `🥤 Breath full, and ×{Tuning.EnergyBreath} breath for {Tuning.EnergyTime} s.`)
		return nil
	end
	return "Unknown item."
end

local function onUse(player: Player, id: any, target: any)
	if type(id) ~= "string" then
		return
	end
	local profile = PlayerData.get(player)
	if not profile or (profile.items[id] or 0) <= 0 then
		return
	end
	local now = os.clock()
	if lastUse[player] and now - lastUse[player] < Tuning.UseCooldown then
		return
	end
	lastUse[player] = now
	local aim: Vector3? = if typeof(target) == "Vector3" and target == target then target else nil
	local err = apply(player, id, aim)
	if err then
		notice:FireClient(player, err)
		return
	end
	-- 6.20: Field Medic (Config.Skills): one medkit a job or a mission is not spent (server/Skills.luau's charge)
	if id == "medkit" and require(script.Parent.Skills).freeMedkit(player) then
		notice:FireClient(player, "➕ Field Medic: that medkit was free.")
		return
	end
	PlayerData.addItem(player, id, -1)
end

-- ── Supply crates ──────────────────────────────────────────────────────────

local crates: { Part } = {}

local function placeCrate(folder: Instance)
	local addresses = Map.addresses()
	local spot: Vector3? = nil
	for _ = 1, 10 do
		local a = addresses[rng:NextInteger(1, #addresses)]
		local candidate = Vector3.new(a.x + rng:NextNumber(-6, 6), World.RoadTop, a.z + rng:NextNumber(-6, 6))
		local free = true
		for _, other in crates do
			if (other.Position - candidate).Magnitude < 150 then
				free = false
				break
			end
		end
		if free then
			spot = candidate
			break
		end
	end
	if not spot then
		return
	end
	local crate = Instance.new("Part")
	crate.Name = "SupplyCrate"
	crate.Anchored = true
	crate.CanCollide = false
	crate.CanTouch = false
	crate.Size = Vector3.new(3.4, 3.4, 3.4)
	crate.CFrame = CFrame.new(spot + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0)
	crate.Color = Color3.fromRGB(160, 120, 70)
	crate.Material = Enum.Material.WoodPlanks
	local band = Instance.new("Part")
	band.Name = "Band"
	band.Anchored = true
	band.CanCollide = false
	band.CanQuery = false
	band.CanTouch = false
	band.Size = Vector3.new(3.5, 0.6, 3.5)
	band.CFrame = crate.CFrame
	band.Color = Color3.fromRGB(255, 200, 40)
	band.Material = Enum.Material.Neon
	band.Parent = crate
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 210, 80)
	glow.Range = 16
	glow.Brightness = 2
	glow.Parent = crate
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(40, 40)
	tag.StudsOffset = Vector3.new(0, 4, 0)
	tag.AlwaysOnTop = true
	tag.MaxDistance = 140
	tag.Parent = crate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "?"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255, 210, 60)
	label.TextStrokeTransparency = 0.2
	label.Parent = tag
	crate.Parent = folder
	table.insert(crates, crate)
end

local function article(noun: string): string
	return if string.find("AEIOUaeiou", string.sub(noun, 1, 1), 1, true) then "an " .. noun else "a " .. noun
end

local function collect(player: Player, crate: Part)
	local index = table.find(crates, crate)
	if index then
		table.remove(crates, index)
	end
	local position = crate.Position
	crate:Destroy()
	local loot = Config.Loot
	local gotItem = false
	local profile = PlayerData.get(player)
	-- 6.7: only the items that are for this player (no car items without a car: Economy.itemsFor)
	local pool = Economy.itemsFor(if profile then profile.cars else nil)
	if rng:NextNumber() < loot.ItemChance and #pool > 0 then
		local def = pool[rng:NextInteger(1, #pool)]
		if PlayerData.addItem(player, def.id, 1) then
			notice:FireClient(player, `Supply crate: found {article(def.name)} {def.icon} → in your item bar`) -- (6.3 review: no slot number: a touch screen shows fewer slots and no keys)
			gotItem = true
		end
	end
	if not gotItem then
		local amount = rng:NextInteger(loot.MoneyMin, loot.MoneyMax)
		PlayerData.addMoney(player, amount, "CrateLoot")
		Net.get("Reward"):FireClient(player, position + Vector3.new(0, 3, 0), amount)
		notice:FireClient(player, `Supply crate: +${amount}`)
	end
end

function Items.start()
	effects = workspace:FindFirstChild("Effects") or workspace
	Net.get("UseItem").OnServerEvent:Connect(onUse)
	Players.PlayerRemoving:Connect(function(player)
		lastUse[player] = nil
		local list = mines[player]
		if list then
			for _, mine in table.clone(list) do
				mine:Destroy()
			end
		end
		mines[player] = nil
	end)

	local folder = Instance.new("Folder")
	folder.Name = "Loot"
	folder.Parent = workspace
	for _ = 1, Config.Loot.Count do
		placeCrate(folder)
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		elapsed = 0
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if not root then
				continue
			end
			for _, crate in table.clone(crates) do
				if (crate.Position - root.Position).Magnitude < Config.Loot.Reach + (if root.AssemblyRootPart ~= root then 5 else 0) then
					collect(player, crate)
					task.delay(Config.Loot.Respawn, placeCrate, folder)
				end
			end
		end
	end)
end

return Items
