--!strict
-- 6.1, what you hold (shared/Holding.luau has the rules): fists, the plastic bag or your gun. The server decides; every
-- client sees it through the character's attributes:
--   Hand       "fists" | "bag" | "gun" (server/KitWear.luau hangs the bag in the left hand only for "bag"; the bottom
--              bar's hand slots, client/Hotbar.luau)
--   Holstered  true unless the gun is the hand (server/Gun.luau fires no hand-gun shot while it is set; client/ArmPose
--              hides the gun) — the holster of 3.9 (server/CloseCombat.luau's B goes through Hand.holster)
-- The client asks with the Hand remote (keys 1 / 2 / 3, a tap on a hand slot, the d-pad), at most every
-- Config.Hand.Cooldown. Refused: seated (Get out first), the gun with your hands full of cargo, the bag you do not own
-- or that lies on the ground (the player attribute BagDown, server/Cargo.luau), a gun you do not have. A new body holds
-- the bag when it is yours and with you, else its fists (Holding.atSpawn; the save still loading: as soon as it is in).
-- A purchase or a sale that takes the hand away (the last gun, the bag) goes back to fists.
-- Hand.onChanged(fn(player, old, new)): server/Cargo.luau sets a loaded bag down when it leaves the hand (6.4: a hand
-- bag; a bag that stays, Config.Kit stays, is slung on the back instead: server/KitWear.luau, Holding.bagLeaves).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Holding = require(Shared.Holding)
local Net = require(Shared.Net)
local TransportRules = require(Shared.Transport) -- 6.4: which bag is yours
local PlayerData = require(script.Parent.PlayerData)

local Hand = {}

local current: { [Player]: string } = {}
local lastFree: { [Player]: string } = {} -- what B's holster goes back to (fists or the bag)
local switchedAt: { [Player]: number } = {}
local unsettled: { [Player]: boolean? } = {} -- a body whose hand was chosen before the save was in
local listeners: { (Player, string, string) -> () } = {}

-- (6.4: any bag: the active one is in the hand, shared/Transport.luau activeBag)
local function ownsBag(player: Player): boolean
	local profile = PlayerData.get(player)
	return profile ~= nil and TransportRules.activeBag(profile.kit, profile.activeBag) ~= nil
end

local function hasGun(player: Player): boolean
	local profile = PlayerData.get(player)
	return profile ~= nil and profile.weapon ~= nil
end

local function bagDown(player: Player): boolean
	return typeof(player:GetAttribute("BagDown")) == "Vector3"
end

-- The character's attributes for this hand.
local function show(character: Model, hand: string)
	if character:GetAttribute("Hand") ~= hand then
		character:SetAttribute("Hand", hand)
	end
	local holstered = hand ~= "gun"
	if character:GetAttribute("Holstered") ~= holstered then
		character:SetAttribute("Holstered", holstered)
	end
	if holstered and character:GetAttribute("Aiming") == true then
		character:SetAttribute("Aiming", false) -- (no empty hands held up)
	end
end

-- The hand now (fists without a body or before the first spawn).
function Hand.get(player: Player): string
	return current[player] or "fists"
end

-- fn(player, old, new) after every change.
function Hand.onChanged(fn: (Player, string, string) -> ())
	table.insert(listeners, fn)
end

local function change(player: Player, character: Model, hand: string)
	local old = Hand.get(player)
	current[player] = hand
	if hand ~= "gun" then
		lastFree[player] = hand
	end
	show(character, hand)
	if old ~= hand then
		for _, fn in listeners do
			local ok, err: any = pcall(function()
				fn(player, old, hand)
			end)
			if not ok then
				warn(`[Hand] {err}`)
			end
		end
	end
end

-- Take `hand` (checked). `pickup`: server/Cargo.luau picked the bag up from the ground (it is with you again). True when
-- the hand is that now; else false and why (Holding.whyText's key).
function Hand.set(player: Player, hand: string, pickup: boolean?): (boolean, string?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or not Holding.valid(hand) then
		return false, nil
	end
	if Hand.get(player) == hand then
		show(character, hand)
		return true, nil
	end
	if humanoid.SeatPart ~= nil or humanoid.Sit then
		return false, "seated"
	end
	local ok, why = Holding.can(hand, ownsBag(player), hasGun(player), bagDown(player) and not pickup)
	if not ok then
		return false, why
	end
	if hand == "gun" and character:GetAttribute("Carrying") ~= nil then
		return false, "busy"
	end
	change(player, character, hand)
	return true, nil
end

-- server/CloseCombat.luau's B (the Holster remote; aiming or shooting draws too): drawn = the gun, holstered = back to
-- what you held before it (the bag, still with you) or fists.
function Hand.holster(player: Player, holstered: boolean)
	if not holstered then
		Hand.set(player, "gun")
		return
	end
	if Hand.get(player) == "gun" then
		Hand.set(player, Holding.afterHolster(lastFree[player], ownsBag(player), bagDown(player)))
	end
end

-- A new body: its hand (Holding.atSpawn), holstered.
local function spawned(player: Player, character: Model)
	local profile = PlayerData.get(player)
	local hand = Holding.atSpawn(ownsBag(player), bagDown(player))
	local old = Hand.get(player)
	current[player] = hand
	lastFree[player] = hand
	unsettled[player] = if profile then nil else true
	show(character, hand)
	if old ~= hand then
		for _, fn in listeners do
			pcall(function()
				fn(player, old, hand)
			end)
		end
	end
end

-- The profile changed (a purchase, the save coming in): a hand you lost goes back to fists; a body that spawned before
-- the save was in takes its spawn hand now.
local function profileChanged(player: Player)
	local character = player.Character
	if not character or not PlayerData.get(player) then
		return
	end
	if unsettled[player] then
		unsettled[player] = nil
		local hand = Holding.atSpawn(ownsBag(player), bagDown(player))
		if hand ~= Hand.get(player) then
			Hand.set(player, hand)
		end
		return
	end
	local hand = Hand.get(player)
	if not Holding.can(hand, ownsBag(player), hasGun(player), false) then
		change(player, character, "fists")
	end
end

function Hand.start()
	Net.get("Hand").OnServerEvent:Connect(function(player: Player, hand: any)
		if not Holding.valid(hand) then
			return
		end
		local now = os.clock()
		if now - (switchedAt[player] or -math.huge) < Config.Hand.Cooldown then
			return
		end
		switchedAt[player] = now
		local ok, why = Hand.set(player, hand)
		if not ok and why then
			Net.get("Notice"):FireClient(player, Holding.whyText(why))
			local character = player.Character
			if character then
				show(character, Hand.get(player)) -- (the client's guess goes back to the real hand)
			end
		end
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			spawned(player, character)
		end)
		if player.Character then
			spawned(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	PlayerData.Changed:Connect(profileChanged)
	Players.PlayerRemoving:Connect(function(player)
		current[player] = nil
		lastFree[player] = nil
		switchedAt[player] = nil
		unsettled[player] = nil
	end)
end

return Hand
