-- 9.x LOOT on the server: the real server/Loot.luau (LootServer.luau through tests/run_tests.py, on
-- tests/runtime/MovingRuntime.luau's fakes: its CollectionService marks a tag as the attribute Tag_<tag>), the way
-- server/Moving.luau's one hook calls it (setupItem: Loot.tag(model, spot, session)).
--   * Normal (a contract without a difficulty): every piece its own rarity and its catalogue value; the model's Rarity,
--     Stars and Value and the loot tag; the move's thing its rarity (the trip home's Collection.add) and its value.
--   * Nightmare: the house rolled once for all its pieces (one Epic or better at least), the same seed the same loot,
--     the things' values lifted with their rarities (the move's facts count them).
--   * Never in the move's way: a broken session warns and the piece stays as it was.
-- (tests/sandboxmove_runtime_test.luau checks the hook in a real move: the pieces' attributes, the rarity stored home.)
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./MovingRuntime")
local Config = require("./Config")
local LootRules = require("./LootRules")
local CollectionRules = require("./CollectionRules")
local Loot = require("./LootServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local M = E.Mock
local TAG = "Tag_" .. Config.Loot.Tag

-- A move as server/Moving.luau keeps it: its things (MovingRules' Thing: item, name, value …), their order, the plan's
-- seed and the contract.
local ITEMS = { "dining_chair", "sofa", "piano", "tv", "bowling_trophy", "box", "armchair", "floor_lamp" }
local function session(seed: number, difficulty: string?): any
	local things, order = {}, {}
	for spot, item in ITEMS do
		local def = CollectionRules.defOf(item)
		things[spot] = { spot = spot, item = item, name = if def then def.name else item, value = if def then def.value else 0, condition = 1, state = "home" }
		table.insert(order, spot)
	end
	return { move = { things = things, order = order }, plan = { seed = seed }, contract = { id = "test", difficulty = difficulty } }
end
local function models(s: any): { any }
	local out = {}
	for spot in s.move.things do
		local model = M.Instance.new("Model")
		model.Name = `Piece{spot}`
		out[spot] = model
		Loot.tag(model, spot, s)
	end
	return out
end

do -- Normal: as before 9.x
	local s = session(41, nil)
	local made = models(s)
	local own, tagged, values = true, true, true
	for spot, model in made do
		local thing = s.move.things[spot]
		local def = CollectionRules.defOf(thing.item)
		local rarity = CollectionRules.rarityOf(def)
		own = own and model:GetAttribute("Rarity") == rarity and model:GetAttribute("Stars") == LootRules.rank(rarity) and thing.rarity == rarity
		values = values and model:GetAttribute("Value") == def.value and thing.value == def.value
		tagged = tagged and model:GetAttribute(TAG) == true
	end
	check("Normal (no difficulty on the contract): every piece its own rarity, on its model and its thing", own)
	check("… its catalogue value on the model (Value) and the thing (the move's facts)", values)
	check("… and the loot tag (CollectionService) on every model", tagged)
	check("Loot.rarityOf: the thing's rarity", Loot.rarityOf(s.move.things[3]) == "rare" and Loot.rarityOf({}) == nil and Loot.rarityOf(nil) == nil)
end

do -- Nightmare: the whole house rolled at once
	local best = math.huge
	local same = true
	local lifted = false
	for seed = 1, 40 do
		local s = session(seed, "nightmare")
		local made = models(s)
		local top = 0
		for spot, model in made do
			local thing = s.move.things[spot]
			top = math.max(top, model:GetAttribute("Stars"))
			local def = CollectionRules.defOf(thing.item)
			same = same and thing.value == model:GetAttribute("Value") and thing.rarity == model:GetAttribute("Rarity")
				and thing.value == LootRules.valueOf(def.value, CollectionRules.rarityOf(def), thing.rarity)
			lifted = lifted or thing.value > def.value
		end
		best = math.min(best, top)
		local again = session(seed, "nightmare")
		local made2 = models(again)
		for spot, model in made2 do
			same = same and model:GetAttribute("Rarity") == made[spot]:GetAttribute("Rarity")
		end
	end
	check("Nightmare: every house holds an Epic or better (its best piece lifted when the dice gave none)", best >= 4, best)
	check("… the model, the thing and the rules agree on the rarity and the value; the same seed, the same loot", same)
	check("… some pieces come rarer, worth more (their thing's value lifted)", lifted)
end

do -- never in the move's way (Loot.tag warns: "WARN [Loot] the piece at spot 1 kept its own rarity")
	local model = M.Instance.new("Model")
	local ok = pcall(Loot.tag, model, 1, { move = nil })
	check("a broken session: no error out of Loot.tag, the piece untouched", ok and model:GetAttribute("Rarity") == nil and model:GetAttribute(TAG) == nil)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
