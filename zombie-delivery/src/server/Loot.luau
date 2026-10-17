--!strict
-- 9.x LOOT (the owner: "like Dungeon Quest: you go into a house and you get loot there ... outlines with their own colour
-- by how rare it is, and stars by rarity, so it has value"; Config.Loot, the rules shared/LootRules.luau). Every
-- carryable piece of a house gets its rarity here, on the server, as the move's pieces are made: server/Moving.luau's
-- one hook (setupItem) calls Loot.tag for each. The house is rolled once, when its first piece is tagged, every piece
-- at once (LootRules.roll: the plan's seed and the contract's difficulty, contract.difficulty; nil: Normal, the
-- rarities as before), so Nightmare's floor sees the whole house; the rolls are kept with the move (weakly: they go
-- with it). The client only shows what the models carry (client/LootOutline.luau, client/LootStars.luau).
--   Loot.tag(model, spot, s)   the piece of move `s` (its move, plan and contract) at `spot`: its model gets the
--                              attributes Rarity (the tier's id), Stars (1 … 5) and Value ($: its worth in the warehouse)
--                              and the CollectionService tag Config.Loot.Tag; the move's thing its value (its worth at
--                              that rarity: the move's facts count it) and its rarity (thing.rarity: the trip home stores
--                              it with the piece, Collection.add's `rarity`). Never in the move's way: anything wrong is a
--                              warning and the piece stays as it was (its own rarity)
--   Loot.rollOf(s)             the house's rolls of move `s` ({ [spot] = LootRules.Roll }), rolled now if not yet
--   Loot.rarityOf(thing)       the rarity Loot gave a move's thing (nil: none)
--   10.x danger: Loot.boost(s, spot, steps, floor?)   the piece at `spot` of move `s` lifted `steps` tiers and at least
--                              to `floor` (LootRules.lift: a locked room's pieces a tier, a vault's to Epic or Legendary,
--                              server/RunDanger.luau): its roll, its thing's value and rarity and its model's attributes
--                              anew; the rarity it has now (nil: no such piece). Never in the run's way (a warning)

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local LootRules = require(Shared.LootRules)

local Loot = {}

local rolls: { [any]: { [number]: LootRules.Roll } } = setmetatable({}, { __mode = "k" }) :: any

function Loot.rollOf(s: any): { [number]: LootRules.Roll }
	local move = s.move
	local made = rolls[move]
	if made then
		return made
	end
	local pieces: { LootRules.Piece } = {}
	for _, spot in move.order do
		local thing = move.things[spot]
		if thing then
			table.insert(pieces, { spot = spot, item = thing.item, value = thing.value })
		end
	end
	local plan = s.plan
	local contract = s.contract
	local seed = if type(plan) == "table" and type(plan.seed) == "number" then plan.seed else 0
	local difficulty = if type(contract) == "table" then contract.difficulty else nil
	local rolled = LootRules.roll(pieces, difficulty, seed)
	rolls[move] = rolled
	return rolled
end

-- (Loot.tag's work: in a pcall there, never in the move's way)
local function apply(model: Model, spot: number, s: any)
	local roll = Loot.rollOf(s)[spot]
	local thing = s.move.things[spot]
	if not roll or not thing then
		return
	end
	thing.value = roll.value
	thing.rarity = roll.rarity
	for key, value in LootRules.attributes(roll.rarity, roll.value) do
		model:SetAttribute(key, value)
	end
	CollectionService:AddTag(model, Config.Loot.Tag)
end

function Loot.tag(model: Model, spot: number, s: any)
	local ok, err = pcall(apply :: any, model, spot, s)
	if not ok then
		warn(`[Loot] the piece at spot {spot} kept its own rarity: {err}`)
	end
end

function Loot.boost(s: any, spot: number, steps: number, floor: string?): string?
	local ok, result = pcall(function(): string?
		local rolled = Loot.rollOf(s)
		local roll = rolled[spot]
		local thing = s.move.things[spot]
		if not roll or not thing then
			return nil
		end
		local lifted = LootRules.lift(roll, steps, floor)
		rolled[spot] = lifted
		thing.value = lifted.value
		thing.rarity = lifted.rarity
		local item = s.items and s.items[spot]
		local model = item and item.model
		if model then
			for key, value in LootRules.attributes(lifted.rarity, lifted.value) do
				model:SetAttribute(key, value)
			end
			CollectionService:AddTag(model, Config.Loot.Tag)
		end
		return lifted.rarity
	end)
	if not ok then
		warn(`[Loot] the piece at spot {spot} kept its rarity: {result}`)
		return nil
	end
	return result
end

function Loot.rarityOf(thing: any): string?
	local rarity = if type(thing) == "table" then thing.rarity else nil
	return if type(rarity) == "string" then rarity else nil
end

return Loot
