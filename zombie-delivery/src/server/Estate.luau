--!strict
-- Real estate (Config.Estate): homes (mansions, villas, houses), garages and offices you buy with the money you made.
-- Every player owns their own copy (profile.properties, saved by server/PlayerData.luau): two owners of the same
-- mansion on one server both use it.
--
--   * Buy: at the property's FOR SALE sign (the EstatePrompt opens its listing on the client, client/EstateUi.luau),
--     with the driver level (def.level), the campaigns it requires (3.2, def.requires: their finale done, see
--     Estate.finished), the money, and not owned yet. Your first home becomes your home.
--   * Sell: anywhere, for Config.Estate.SellBack × the price. Not the home you spawn at: switch first (another home
--     or the depot). Your cars stay even when the slots shrink; you just cannot buy more until there is room.
--   * Home: an owned mansion / villa / house. You spawn there (World.EstateSpawns[home]) after every death and after
--     PLAY on the start screen (behind the start screen you wait at the depot); server/Vehicles.luau brings your car
--     out of its garage (World.EstateGarages).
--   * Car slots: Config.Estate.BaseCarSlots + every owned property's garageSlots (server/Shops.luau checks them when
--     you buy a car; company cars earned from employers do not count).
--   * Office: the biggest owned office runs your company (server/Business.luau, Estate.officeOf).
--   * Name plates over the FOR SALE signs: "FOR SALE $x · LEVEL n" (and "· after <campaign>") or "Owned by A, B"
--     (the owners on this server).
--
-- The "Estate" remote: client → server (action, id): "buy" | "sell" | "home" (id or "depot") | "view" | "state";
-- server → client (open id or nil, state): open that property's listing (the sign was used) and/or the new state
-- { owned = { [id] = true }, home, office, slots, used, owners = { [id] = { names } }, finished = { [campaign] = true } }
-- (finished: 3.2, the campaigns some property requires whose finale you have done).
-- The player attributes Estates ("id,id,…"), Home, Office and CarSlots carry the same to every client.
--
-- The world (server/World.luau, shared/Map.luau) is read through the 2.6 contract and every piece is optional (a
-- missing one only turns its feature off): World.EstatePrompts { { prompt, estate } }, World.EstateSpawns[id]
-- (CFrame), Map.EstatePlots[id] { x, z, facing, district }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local MissionData = require(Shared.Missions)
local Net = require(Shared.Net)

local Server = script.Parent
local World = require(Server.World)
local PlayerData = require(Server.PlayerData)

local Estate = {}

local HOME_KINDS = { mansion = true, villa = true, house = true }
local SIGN_RANGE = 45 -- studs from a FOR SALE sign that count as "at the property" (buying)
local PLOT_RANGE = 110 -- … or from the plot's middle (Map.EstatePlots)
local ACTION_GAP = 0.3 -- seconds between two actions of one player (a double click does not buy twice)
local PROFILE_WAIT = 15 -- seconds a fresh character waits for the save to load

-- The plate colours (client/Theme.luau's Dead End Dispatch tokens: the server cannot require the client).
local PLATE = {
	panel = Color3.fromRGB(20, 28, 26),
	text = Color3.fromRGB(246, 241, 224),
	yellow = Color3.fromRGB(245, 179, 79),
	money = Color3.fromRGB(170, 218, 137),
	dim = Color3.fromRGB(175, 187, 169),
}

local notice = Net.get("Notice")
local remote = Net.get("Estate")

local byId: { [string]: Config.EstateDef } = {}
-- 3.2: the campaigns some property requires, and the id of each one's finale (its last mission).
local finales: { [string]: string } = {}
for _, def in Config.Estate.Properties do
	byId[def.id] = def
	local requires: { string } = def.requires or {}
	for _, campaignId in requires do
		local list = MissionData.ofCampaign(campaignId)
		local last = list[#list]
		finales[campaignId] = if last then last.id else `{campaignId}_10`
	end
end

local lastAction: { [Player]: number } = {}
local signatures: { [Player]: string } = {} -- what the player's clients were last told (see refresh)
local owning: { [Player]: string } = {} -- the owned ids, for the plates
local played: { [Player]: boolean } = {}
local platesDirty = true

-- ── Lookups ────────────────────────────────────────────────────────────────

function Estate.find(id: any): Config.EstateDef?
	return if type(id) == "string" then byId[id] else nil
end

-- Can you live there (mansion, villa, house)?
function Estate.isHome(id: any): boolean
	local def = Estate.find(id)
	return def ~= nil and HOME_KINDS[def.kind] == true
end

function Estate.owns(player: Player, id: string): boolean
	local profile = PlayerData.get(player)
	return profile ~= nil and profile.properties[id] == true
end

-- The home you spawn at, or nil (the depot).
function Estate.homeOf(player: Player): string?
	local profile = PlayerData.get(player)
	local home = if profile then profile.home else nil
	if home and profile and profile.properties[home] and Estate.isHome(home) then
		return home
	end
	return nil
end

-- How many cars you can own: Config.Estate.BaseCarSlots + every owned home's and garage's garageSlots.
function Estate.carSlots(player: Player): number
	local slots = Config.Estate.BaseCarSlots
	local profile = PlayerData.get(player)
	if profile then
		for id in profile.properties do
			local def = byId[id]
			if def then
				slots += def.garageSlots
			end
		end
	end
	return slots
end

-- The cars that take a slot: every owned car that is not a company vehicle (those come from the employers).
function Estate.carsOwned(player: Player): number
	local profile = PlayerData.get(player)
	local count = 0
	if profile then
		for id, owned in profile.cars do
			local def = Economy.findCar(id)
			if owned and def and not def.company and not def.bike then -- (5.1: a bike needs no garage slot)
				count += 1
			end
		end
	end
	return count
end

-- 3.2: the campaigns some property requires whose finale this player has done (profile.missions), or whose reward was
-- paid (profile.campaigns: every mission of it done).
function Estate.finished(player: Player): { [string]: boolean }
	local done: { [string]: boolean } = {}
	local profile = PlayerData.get(player)
	if profile then
		for campaignId, finale in finales do
			if profile.campaigns[campaignId] or (profile.missions[finale] or 0) >= 1 then
				done[campaignId] = true
			end
		end
	end
	return done
end

-- The name of a campaign ("Iron Supply"), for the messages.
local function campaignName(id: string): string
	local campaign = MissionData.findCampaign(id)
	return if campaign then campaign.name else id
end

-- The office you run your company from (the biggest owned one), or nil.
function Estate.officeOf(player: Player): string?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local best: Config.EstateDef? = nil
	for id in profile.properties do
		local def = byId[id]
		if def and def.kind == "office" then
			local current = best
			if not current or (def.couriers or 0) > (current.couriers or 0) or ((def.couriers or 0) == (current.couriers or 0) and def.price > current.price) then
				best = def
			end
		end
	end
	return if best then best.id else nil
end

-- ── The world (2.6 contract, all optional) ─────────────────────────────────

local function worldTable(name: string): { [any]: any }
	local value = (World :: any)[name]
	return if type(value) == "table" then value else {}
end

local function spawnOf(id: string): CFrame?
	local spot = worldTable("EstateSpawns")[id]
	return if typeof(spot) == "CFrame" then spot else nil
end

local function plotOf(id: string): Vector3?
	local plots = (Map :: any).EstatePlots
	local plot = if type(plots) == "table" then plots[id] else nil
	if type(plot) == "table" and type(plot.x) == "number" and type(plot.z) == "number" then
		return Vector3.new(plot.x, 0, plot.z)
	end
	return nil
end

-- Where a prompt is in the world (on a part, an attachment or a model).
local function promptPosition(prompt: Instance): Vector3?
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("Model") then
		return parent:GetPivot().Position
	end
	return nil
end

type Sign = { prompt: ProximityPrompt, estate: string }

local function signs(): { Sign }
	local list: { Sign } = {}
	for _, entry in worldTable("EstatePrompts") do
		if type(entry) == "table" and typeof(entry.prompt) == "Instance" and entry.prompt:IsA("ProximityPrompt") and byId[entry.estate] then
			table.insert(list, { prompt = entry.prompt, estate = entry.estate })
		end
	end
	return list
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Is the player at the property (its FOR SALE sign or its plot)? A property the world does not place anywhere
-- (an older World) can be bought from anywhere.
local function atProperty(player: Player, id: string): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local known = false
	local position = if root and root:IsA("BasePart") then root.Position else nil
	for _, sign in signs() do
		if sign.estate == id then
			local at = promptPosition(sign.prompt)
			if at then
				known = true
				if position and (position - at).Magnitude <= SIGN_RANGE then
					return true
				end
			end
		end
	end
	local plot = plotOf(id)
	if plot then
		known = true
		if position and flatDistance(position, plot) <= PLOT_RANGE then
			return true
		end
	end
	return not known
end

-- ── State for the clients ──────────────────────────────────────────────────

local function ownedList(player: Player): { string }
	local profile = PlayerData.get(player)
	local list: { string } = {}
	if profile then
		for id, owned in profile.properties do
			if owned and byId[id] then
				table.insert(list, id)
			end
		end
	end
	table.sort(list)
	return list
end

-- Who owns what among the players on this server (display names, sorted).
local function ownersOnServer(): { [string]: { string } }
	local owners: { [string]: { string } } = {}
	for _, other in Players:GetPlayers() do
		local profile = PlayerData.get(other)
		if profile then
			for id, owned in profile.properties do
				if owned and byId[id] then
					local names = owners[id] or {}
					owners[id] = names
					table.insert(names, other.DisplayName)
				end
			end
		end
	end
	for _, names in owners do
		table.sort(names)
	end
	return owners
end

local function stateFor(player: Player): { [string]: any }?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local owned: { [string]: boolean } = {}
	for _, id in ownedList(player) do
		owned[id] = true
	end
	return {
		owned = owned,
		home = Estate.homeOf(player),
		office = Estate.officeOf(player),
		slots = Estate.carSlots(player),
		used = Estate.carsOwned(player),
		owners = ownersOnServer(),
		finished = Estate.finished(player),
	}
end

local function sendState(player: Player, open: string?)
	local state = stateFor(player)
	if state then
		remote:FireClient(player, open, state)
	end
end

-- Opens a property's listing on the player's screen (the FOR SALE sign, the ESTATE list's VIEW).
function Estate.openListing(player: Player, id: string)
	if byId[id] then
		sendState(player, id)
	end
end

-- After any change of the profile (PlayerData.Changed): the attributes, the client's state and the plates follow when
-- something of the estate changed (a money change alone costs a string compare).
local function refresh(player: Player)
	local profile = PlayerData.get(player)
	if not profile or not player.Parent then
		return
	end
	local ids = table.concat(ownedList(player), ",")
	local home = Estate.homeOf(player)
	local office = Estate.officeOf(player)
	local slots = Estate.carSlots(player)
	local used = Estate.carsOwned(player)
	-- 3.2: a finale done opens a property (requires): that has to reach the window too.
	local finishedIds: { string } = {}
	for campaignId in Estate.finished(player) do
		table.insert(finishedIds, campaignId)
	end
	table.sort(finishedIds)
	local signature = `{ids}|{home or ""}|{used}|{table.concat(finishedIds, ",")}`
	if signatures[player] == signature then
		return
	end
	signatures[player] = signature
	if owning[player] ~= ids then
		owning[player] = ids
		platesDirty = true
	end
	player:SetAttribute("Estates", ids)
	player:SetAttribute("Home", home)
	player:SetAttribute("Office", office)
	player:SetAttribute("CarSlots", slots)
	sendState(player, nil)
end

-- ── The plates over the FOR SALE signs ─────────────────────────────────────

type Plate = { title: TextLabel, status: TextLabel }
local plates: { [string]: { Plate } } = {}

local function money(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

local function buildPlate(sign: Sign): Plate?
	local def = byId[sign.estate]
	local part = sign.prompt.Parent
	local adornee: BasePart? = nil
	if part and part:IsA("BasePart") then
		adornee = part
	elseif part and part:IsA("Attachment") and part.Parent and part.Parent:IsA("BasePart") then
		adornee = part.Parent :: BasePart
	end
	if not def or not adornee then
		return nil
	end
	local old = adornee:FindFirstChild("EstatePlate")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "EstatePlate"
	gui.Size = UDim2.fromOffset(240, 64)
	gui.StudsOffsetWorldSpace = Vector3.new(0, adornee.Size.Y / 2 + 3.2, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = PLATE.panel
	back.BackgroundTransparency = 0.18
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = PLATE.yellow
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = back
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -12, 0.5, -2)
	title.Position = UDim2.fromOffset(6, 3)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = PLATE.text
	title.Text = def.name
	title.Parent = back
	local status = Instance.new("TextLabel")
	status.Size = UDim2.new(1, -12, 0.5, -4)
	status.Position = UDim2.new(0, 6, 0.5, 1)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextScaled = true
	status.TextColor3 = PLATE.money
	status.Text = ""
	status.Parent = back
	gui.Parent = adornee
	-- The prompt says what it is (World may have set its own texts).
	if sign.prompt.ObjectText == "" then
		sign.prompt.ObjectText = def.name
	end
	if sign.prompt.ActionText == "" or sign.prompt.ActionText == "Interact" then
		sign.prompt.ActionText = "View"
	end
	return { title = title, status = status }
end

local function updatePlates()
	platesDirty = false
	local owners = ownersOnServer()
	local boards = worldTable("EstateSigns")
	for id, def in byId do
		local names = owners[id]
		local owned = names ~= nil and #names > 0
		local shown = if names and owned then table.concat(names, ", ", 1, math.min(#names, 3)) .. (if #names > 3 then ` +{#names - 3}` else "") else ""
		local needs = if def.requires and def.requires[1] then ` · after {campaignName(def.requires[1])}` else ""
		local text = if owned then `Owned by {shown}` else `FOR SALE {money(def.price)}{if def.level and def.level > 1 then ` · LEVEL {def.level}` else ""}{needs}`
		local color = if owned then PLATE.yellow else PLATE.money
		for _, plate in plates[id] or ({} :: { Plate }) do
			plate.status.Text = text
			plate.status.TextColor3 = color
		end
		-- The boards World painted (SurfaceGui "Plate" > "Status") follow too.
		local labels = boards[id]
		for _, label in if type(labels) == "table" then labels else {} do
			if typeof(label) == "Instance" and label:IsA("TextLabel") and label.Parent then
				label.Text = if owned then `OWNED\n{shown}` else `FOR SALE\n{money(def.price)}`
				label.TextColor3 = if owned then Color3.fromRGB(40, 140, 60) else Color3.fromRGB(196, 40, 36)
			end
		end
	end
end

local function pushOwnersToAll()
	for _, player in Players:GetPlayers() do
		sendState(player, nil)
	end
end

-- ── Actions ────────────────────────────────────────────────────────────────

local function say(player: Player, text: string)
	notice:FireClient(player, text)
end

-- Buys a property (the checks: known, not owned, at its sign, the level, the money). Returns an error or nil.
function Estate.buy(player: Player, id: string): string?
	local profile = PlayerData.get(player)
	local def = byId[id]
	if not profile or not def then
		return "Still loading..."
	end
	if profile.properties[id] then
		return `{def.name} is already yours.`
	end
	if not atProperty(player, id) then
		return `Go to the FOR SALE sign of {def.name} to buy it (GPS in the ESTATE list, H).`
	end
	local level = PlayerData.level(player)
	if def.level and level < def.level then
		return `{def.name} needs driver level {def.level} ({Levels.rank(def.level)}). You are level {level}: deliveries give XP.`
	end
	local missing = Economy.missingCampaign(def.requires, Estate.finished(player))
	if missing then
		return `Finish {campaignName(missing)} first: {def.name} opens after its finale (MISSIONS, U).`
	end
	if not PlayerData.spend(player, def.price) then
		return `Not enough money: {def.name} costs {money(def.price)}.`
	end
	profile.properties[id] = true
	local extra = ""
	if HOME_KINDS[def.kind] and not Estate.homeOf(player) then
		profile.home = id
		extra = " It is your home now: you spawn here."
	elseif HOME_KINDS[def.kind] then
		extra = " SET AS HOME to spawn here."
	end
	if def.garageSlots > 0 then
		extra ..= ` +{def.garageSlots} car slots ({Estate.carSlots(player)} now).`
	end
	if def.kind == "office" then
		extra ..= ` Use the office computer to run your company (up to {def.couriers or 0} couriers).`
	end
	PlayerData.notify(player)
	say(player, `You bought {def.name}!{extra}`)
	return nil
end

-- Sells a property for SellBack × its price. Not the home you spawn at.
function Estate.sell(player: Player, id: string): string?
	local profile = PlayerData.get(player)
	local def = byId[id]
	if not profile or not def then
		return "Still loading..."
	end
	if not profile.properties[id] then
		return `{def.name} is not yours.`
	end
	if profile.home == id then
		return `{def.name} is your home: set another home (or the depot) first.`
	end
	profile.properties[id] = nil
	local refund = math.floor(def.price * Config.Estate.SellBack)
	-- Selling is not earning: the money comes back without counting as "earned" (the leaderboard).
	profile.money += refund
	local extra = ""
	if def.kind == "office" and not Estate.officeOf(player) then
		extra = " Your company has no office now."
	end
	if def.garageSlots > 0 and Estate.carsOwned(player) > Estate.carSlots(player) then
		extra ..= " Your cars stay, but you cannot buy more until you have room."
	end
	PlayerData.notify(player)
	say(player, `You sold {def.name} for {money(refund)}.{extra}`)
	return nil
end

-- The home you spawn at: an owned mansion / villa / house, or nil / "depot" for the depot.
function Estate.setHome(player: Player, id: string?): string?
	local profile = PlayerData.get(player)
	if not profile then
		return "Still loading..."
	end
	if id == nil or id == "depot" then
		profile.home = nil
		PlayerData.notify(player)
		say(player, "You spawn at the depot now.")
		return nil
	end
	local def = byId[id]
	if not def or not HOME_KINDS[def.kind] then
		return "You can only live in a mansion, a villa or a house."
	end
	if not profile.properties[id] then
		return `{def.name} is not yours.`
	end
	if profile.home == id then
		return `{def.name} is already your home.`
	end
	profile.home = id
	PlayerData.notify(player)
	say(player, `{def.name} is your home: you spawn here and your car comes out of its garage.`)
	return nil
end

-- Gives a property for free (the admin tools): an id or "all". A first home becomes the home (with "all" the
-- biggest). Returns how many were new.
function Estate.give(player: Player, id: string): number
	local profile = PlayerData.get(player)
	if not profile then
		return 0
	end
	local given = 0
	local bestHome: Config.EstateDef? = nil
	for _, def in Config.Estate.Properties do
		if id == "all" or def.id == id then
			if not profile.properties[def.id] then
				profile.properties[def.id] = true
				given += 1
			end
			local current = bestHome
			if HOME_KINDS[def.kind] and (not current or def.price > current.price) then
				bestHome = def
			end
		end
	end
	if bestHome and not Estate.homeOf(player) then
		profile.home = bestHome.id
	end
	PlayerData.notify(player)
	return given
end

-- Takes every property (the admin tools, to try buying again). Returns how many.
function Estate.clear(player: Player): number
	local profile = PlayerData.get(player)
	if not profile then
		return 0
	end
	local count = 0
	for _ in profile.properties do
		count += 1
	end
	table.clear(profile.properties)
	profile.home = nil
	PlayerData.notify(player)
	return count
end

local function onAction(player: Player, action: any, id: any)
	if type(action) ~= "string" then
		return
	end
	if action == "state" then
		sendState(player, nil)
		return
	end
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < ACTION_GAP then
		return
	end
	lastAction[player] = now
	local err: string? = nil
	if action == "home" and (id == nil or id == "depot") then
		err = Estate.setHome(player, nil)
	elseif type(id) ~= "string" or not byId[id] then
		return
	elseif action == "buy" then
		err = Estate.buy(player, id)
	elseif action == "sell" then
		err = Estate.sell(player, id)
	elseif action == "home" then
		err = Estate.setHome(player, id)
	elseif action == "view" then
		Estate.openListing(player, id)
		return
	else
		return
	end
	if err then
		say(player, err)
		-- The client's buttons may be out of date: send the truth.
		sendState(player, nil)
	end
end

-- ── Spawning at home ───────────────────────────────────────────────────────

-- Puts the character at its home's spawn spot (inside, near the door), standing on the floor there.
-- 4.0.4: set by Main.server.luau: on a job or a mission a new character goes back near where the last one fell, not
-- home (nil: home as always).
Estate.respawnAt = nil :: ((player: Player) -> CFrame?)?

local function sendHome(player: Player, character: Model?)
	if not character then
		return
	end
	local back = Estate.respawnAt
	if back and back(player) then
		return -- (Main puts this one back on the job)
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") then
		return
	end
	local waited = 0
	while player.Parent and not PlayerData.get(player) and waited < PROFILE_WAIT do
		waited += task.wait(0.5)
	end
	local home = Estate.homeOf(player)
	local spot = if home then spawnOf(home) else nil
	if not spot or player.Character ~= character then
		return
	end
	if flatDistance(root.Position, spot.Position) < 6 then
		return -- already there
	end
	pcall(function()
		player:RequestStreamAroundAsync(spot.Position, 5)
	end)
	if player.Character ~= character or not character.Parent then
		return
	end
	-- The floor under the spot (it may be a little above or below it).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(spot.Position + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
	local floor = if hit then hit.Position.Y else spot.Position.Y
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local lift = (if humanoid then humanoid.HipHeight else 2) + root.Size.Y / 2 + 0.3
	local at = Vector3.new(spot.Position.X, floor + lift, spot.Position.Z)
	character:PivotTo(CFrame.new(at) * spot.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- Behind the start screen the character waits at the depot (the safe zone); from PLAY on, every new character goes
-- home.
local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		if played[player] then
			task.spawn(sendHome, player, character)
		end
	end)
end

-- ── Start ──────────────────────────────────────────────────────────────────

-- PLAY on the start screen: from the depot (where the character stood behind the menu) to the home. Called by
-- Main.server.luau's one Play handler (a PLAY queued while the world was building reaches only the first listener).
function Estate.onPlay(player: Player)
	if not played[player] then
		played[player] = true
		task.spawn(sendHome, player, player.Character)
	end
end

function Estate.start()
	for _, sign in signs() do
		local plate = buildPlate(sign)
		if plate then
			local list = plates[sign.estate] or {}
			plates[sign.estate] = list
			table.insert(list, plate)
		end
		local id = sign.estate
		sign.prompt.Triggered:Connect(function(player)
			Estate.openListing(player, id)
		end)
	end
	if #signs() == 0 then
		warn("[Estate] no FOR SALE signs in the world (World.EstatePrompts): the properties are bought from the ESTATE list (H)")
	end
	remote.OnServerEvent:Connect(onAction)
	PlayerData.Changed:Connect(refresh)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
		refresh(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		signatures[player] = nil
		played[player] = nil
		if owning[player] and owning[player] ~= "" then
			platesDirty = true
		end
		owning[player] = nil
	end)
	-- The plates (and the owners in everybody's listing) follow ownership changes, at most once a second.
	task.spawn(function()
		while true do
			if platesDirty then
				updatePlates()
				pushOwnersToAll()
			end
			task.wait(1)
		end
	end)
end

return Estate
