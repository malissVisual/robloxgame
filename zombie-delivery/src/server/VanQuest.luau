--!strict
-- 5.0 – 6.x, Earl's van (Config.VanQuest; the words in shared/VanQuest.luau): the first vehicle was bought second-hand
-- from Earl at Earl's Used Wheels after Marge's text at level 4. 7.x (one car, Config.CompanyVan): retired. Every
-- courier owns the ZDC Van from the start, so there is no quest, no purchase and no text from Marge any more. Earl's lot
-- stays (server/World.luau builds it: the plate says "FOR SALE · SOLD", Earl stands by the gate with his prompt,
-- World.VanSeller): his old van stands there for show (the Rusty Van, the "van" body of Config.AmbientCars, anchored,
-- with a tag) and talking to him gets one of his lines, in turn.
--
--   VanQuest.start()   the old van on his lot, his prompt's answer

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Rules = require(Shared.VanQuest)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local Npcs = require(script.Parent.Npcs)

local VanQuest = {}

local DISPLAY = "van" -- the body of his old van (Config.AmbientCars), at its first stage: the Rusty Van

local said: { [Player]: number } = {} -- how many of his lines a player heard (the next one comes next)
local lastTalk: { [Player]: number } = {}

-- His prompt ("Talk"): he turns to you and says his next line.
local function talk(player: Player)
	local now = os.clock()
	if now - (lastTalk[player] or 0) < 1 then
		return
	end
	lastTalk[player] = now
	local npc = World.VanSeller.npc
	if not npc or not npc.Parent then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		Npcs.glance(npc, root.Position)
	end
	local n = (said[player] or 0) + 1
	said[player] = n
	Npcs.say(npc, Rules.line(n), 5)
end

-- Earl's old van: the real body at its first stage, anchored, with a tag over it.
local function buildDisplay()
	local def = Economy.findCar(DISPLAY)
	if not def then
		return
	end
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
	label.Text = `{def.name}\n{Rules.tag()}`
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
		warn(`[VanQuest] no old van at Earl's: {err}`)
	end
	local prompt = World.VanSeller.prompt
	if prompt then
		prompt.ObjectText = Config.VanQuest.Seller
		prompt.Triggered:Connect(talk)
	end
	Players.PlayerRemoving:Connect(function(player)
		said[player] = nil
		lastTalk[player] = nil
	end)
end

return VanQuest
