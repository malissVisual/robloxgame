--!strict
-- 5.0, Earl's van (Config.VanQuest; the rules in shared/VanQuest.luau): the first vehicle is bought second-hand, not at
-- Dead End Motors. When a player reaches the van's level without owning it (on a level-up, or on PLAY when they are
-- already there) Marge texts them (the Tutorial remote's "message" to client/Phone.luau's MESSAGES, with the GPS set to
-- Earl, and a toast) and profile.vanQuest becomes "open". Earl stands at Earl's Used Wheels far out on the West
-- Highway (Map.VanSeller, built by server/World.luau with his "Buy the van" prompt, World.VanSeller) next to his rusty
-- Old Van for sale (a display model built here, there for everybody always). Buying is checked here: close to Earl,
-- the level, the quest open, no van yet, not on a job with a lent vehicle, the money. Then the money goes, the van is
-- yours (PlayerData.giveCar, and it is the car you drive), quest "done", and the real van is parked beside the one for
-- sale with you in the driver's seat (Earl hands you the keys); Marge texts again. Not enough money or level: Earl
-- says so.
--
--   VanQuest.onPlay(player)   Main's PLAY: Marge's message when it is due, or her reminder while the quest is open
--   VanQuest.start()          the display van, Earl's prompt, the level-up watch

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Rules = require(Shared.VanQuest)
local World = require(script.Parent.World)
local PlayerData = require(script.Parent.PlayerData)
local Vehicles = require(script.Parent.Vehicles)
local Npcs = require(script.Parent.Npcs)
local Explore = require(script.Parent.Explore)
local Jobs = require(script.Parent.Jobs)

local VanQuest = {}

local MESSAGE_DELAY = 6 -- seconds after PLAY before Marge's text (the client's windows are up, the welcome is read)
local REVEAL = 140 -- studs of the map around Earl's lot uncovered when Marge tells you about it

local notice = Net.get("Notice")
local playing: { [Player]: boolean } = {}
local busy: { [Player]: boolean } = {}

local function ownsVan(profile: PlayerData.Profile): boolean
	return profile.cars[Config.VanQuest.Car] == true
end

-- A text from Marge into the phone's MESSAGES (with Earl on the GPS when `gps`).
local function margeSays(player: Player, text: string, gps: boolean)
	local seller = Map.VanSeller
	Net.get("Tutorial"):FireClient(player, "message", {
		from = "Marge",
		text = text,
		gps = if gps then { x = seller.earl.x, z = seller.earl.z, id = "earl" } else nil,
	})
end

-- The quest opens: Earl's lot on the map, Marge's message and a toast.
local function open(player: Player, profile: PlayerData.Profile)
	profile.vanQuest = "open"
	PlayerData.notify(player)
	local seller = Map.VanSeller
	Explore.uncover(player, seller.earl.x, seller.earl.z, REVEAL)
	margeSays(player, Config.VanQuest.Unlock, true)
	notice:FireClient(player, `📱 Marge: {Config.VanQuest.Unlock}`)
end

-- Is Marge's message due (the van's level reached, no van, not told yet)? Only while playing (the client listens).
local function check(player: Player)
	local profile = PlayerData.get(player)
	if not playing[player] or not profile then
		return
	end
	if Rules.shouldOpen(profile.vanQuest, ownsVan(profile), Levels.levelFor(profile.xp)) then
		open(player, profile)
	end
end

function VanQuest.onPlay(player: Player)
	playing[player] = true
	task.delay(MESSAGE_DELAY, function()
		local profile = PlayerData.get(player)
		if not player.Parent or not profile then
			return
		end
		if profile.vanQuest == "open" and not ownsVan(profile) then
			margeSays(player, Config.VanQuest.Reminder, true) -- (the phone's messages are not saved: a reminder)
		else
			check(player)
		end
	end)
end

local function earlSays(text: string)
	local npc = World.VanSeller.npc
	if npc and npc.Parent then
		Npcs.say(npc, text, 5)
	end
end

local function distanceToEarl(player: Player): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return math.huge
	end
	local earl = Map.VanSeller.earl
	return Vector3.new(root.Position.X - earl.x, 0, root.Position.Z - earl.z).Magnitude
end

-- The "Buy the van" prompt: every check on the server.
local function buy(player: Player)
	local profile = PlayerData.get(player)
	if busy[player] or not profile then
		return
	end
	local npc = World.VanSeller.npc
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if npc and root and root:IsA("BasePart") then
		Npcs.glance(npc, root.Position)
	end
	local level = Levels.levelFor(profile.xp)
	if Rules.shouldOpen(profile.vanQuest, ownsVan(profile), level) then
		open(player, profile) -- (came before Marge's text could: it counts as told)
	end
	local ok, why = Rules.canBuy({
		distance = distanceToEarl(player),
		level = level,
		quest = profile.vanQuest,
		ownsVan = ownsVan(profile),
		money = profile.money,
	})
	if not ok then
		if why ~= "far" then
			earlSays(Rules.sellerLine(why))
		end
		if why == "money" then
			notice:FireClient(player, `The Old Van costs {Rules.priceText()}. You have ${profile.money}: the ON FOOT runs (J) pay.`)
		end
		return
	end
	-- A company vehicle lent for a job is out: the van would take its place mid-job.
	if Jobs.vehicleFor(player) ~= nil then
		earlSays("Finish your job first, kid. The van ain't going anywhere.")
		return
	end
	if not PlayerData.spend(player, Rules.price()) then
		earlSays(Rules.sellerLine("money"))
		return
	end
	busy[player] = true
	PlayerData.giveCar(player, Config.VanQuest.Car) -- (it marks the quest done)
	profile.car = Config.VanQuest.Car -- the van you just bought is the one you drive
	profile.vanQuest = "done"
	PlayerData.notify(player)
	task.spawn(PlayerData.save, player) -- (a big purchase: saved now, not at the next autosave)
	-- Earl hands you the keys: the real van beside the one for sale, you in the driver's seat.
	local seller = Map.VanSeller
	local spot = Vector3.new(seller.parking.x, Map.RoadTop, seller.parking.z)
	local car = Vehicles.placeAt(player, nil, CFrame.lookAt(spot, spot + Vector3.new(seller.facing.x, 0, seller.facing.z)), true)
	earlSays(Rules.sellerLine(nil))
	notice:FireClient(player, if car then "🔑 Earl hands you the keys: the Old Van is yours! The ★ car jobs are on your board now."
		else "🔑 The Old Van is yours! Press CAR to call it.")
	margeSays(player, Config.VanQuest.Bought, false)
	busy[player] = nil
end

-- Earl's old van for sale: the real car's look at its first stage (the Rusty Van), anchored, with a tag over it.
local function buildDisplay()
	local def = Rules.def()
	local seller = Map.VanSeller
	local at = Vector3.new(seller.x, Map.RoadTop, seller.z)
	local model = Vehicles.displayModel(def, CFrame.lookAt(at, at + Vector3.new(seller.facing.x, 0, seller.facing.z)), 0)
	model.Name = "EarlsVan"
	local folder = Instance.new("Folder")
	folder.Name = "EarlsVan"
	folder.Parent = workspace
	model.Parent = folder
	local chassis = model.PrimaryPart
	if not chassis then
		return
	end
	local tag = Instance.new("BillboardGui")
	tag.Size = UDim2.fromOffset(180, 50)
	tag.StudsOffset = Vector3.new(0, 9, 0)
	tag.MaxDistance = 60
	tag.Parent = chassis
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = `{def.name} · FOR SALE\n{Rules.priceText()} · ask {Config.VanQuest.Seller}`
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255, 220, 120)
	label.TextStrokeTransparency = 0.2
	label.Parent = tag
end

function VanQuest.start()
	local ok, err = pcall(function()
		buildDisplay()
	end)
	if not ok then
		warn(`[VanQuest] no van for sale at Earl's: {err}`)
	end
	local prompt = World.VanSeller.prompt
	if prompt then
		prompt.Triggered:Connect(buy)
	end
	-- A level-up (or any change of the profile) may make Marge's message due.
	PlayerData.Changed:Connect(check)
	Players.PlayerRemoving:Connect(function(player)
		playing[player] = nil
		busy[player] = nil
	end)
end

return VanQuest
