--!strict
-- THE WIZARDS: every mage is one of these types. A type has its element, its RARITY (Common … Mythic), its colors
-- (the card, the aura, the bolts), its stats (the rarity multiplies HP and damage) and its own TRAIT in battle
-- (BattleService applies it to the basic attack). Only two mages of the SAME type and level merge.
--
-- How you get them: wave drops (the type is rolled by rarity; bosses and later waves roll better), the SUMMON PORTAL
-- in the lobby (coins; an Epic or better is guaranteed after Balance.SummonPity summons without one) and the CODEX
-- pays coins for every new type you find. Every wizard you own earns coins per minute (Wizards.income).
--
-- LOOKS: a type with `evolution` (an element of StageModels/WizardEvolution: Fire, Ice, Storm, Nature, Shadow, Arcane)
-- has its own designed models, 16 levels (tools/wizards_evolution.py, the "Merge Wizardi 1–16" design); SoldierRig
-- builds those. A type without it (Void, Celestial) uses the Mage's evolution models, tinted with its colors.

local Wizards = {}

export type Rarity = {
	id: string,
	label: string,
	order: number, -- 1 = Common … 5 = Mythic
	color: Color3,
	weight: number, -- relative chance in a roll at luck 1
	stats: number, -- HP and damage multiplier
	income: number, -- coins per minute for a level 1 wizard
	sell: number, -- sell value multiplier
	discovery: number, -- coins for finding the first one of a type of this rarity (the codex)
}

export type Def = {
	id: string,
	label: string,
	element: string,
	rarity: string,
	color: Color3, -- the main color (card, aura, bolts)
	color2: Color3, -- the bright accent
	trait: string, -- the battle trait id (BattleService)
	traitLabel: string,
	traitText: string,
	evolution: string?, -- the element of its designed models (StageModels/WizardEvolution); nil = the Mage's models, tinted
}

local C = Color3.fromRGB

Wizards.Rarities = {
	Common = { id = "Common", label = "COMMON", order = 1, color = C(170, 176, 190), weight = 60, stats = 1.0, income = 1, sell = 1, discovery = 150 },
	Rare = { id = "Rare", label = "RARE", order = 2, color = C(96, 165, 250), weight = 27, stats = 1.12, income = 2, sell = 2, discovery = 400 },
	Epic = { id = "Epic", label = "EPIC", order = 3, color = C(192, 132, 252), weight = 10, stats = 1.25, income = 4, sell = 4, discovery = 1000 },
	Legendary = { id = "Legendary", label = "LEGENDARY", order = 4, color = C(251, 176, 60), weight = 2.6, stats = 1.42, income = 8, sell = 8, discovery = 3000 },
	Mythic = { id = "Mythic", label = "MYTHIC", order = 5, color = C(255, 90, 120), weight = 0.4, stats = 1.65, income = 16, sell = 16, discovery = 8000 },
} :: { [string]: Rarity }
Wizards.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

Wizards.Types = {
	Arcane = {
		id = "Arcane", label = "Arcane Mage", element = "Arcane", rarity = "Common",
		evolution = "Arcane",
		color = C(180, 100, 210), color2 = C(235, 205, 255),
		trait = "flow", traitLabel = "Arcane Flow", traitText = "every hit restores 4 mana (more spells)",
	},
	Ember = {
		id = "Ember", label = "Ember Mage", element = "Fire", rarity = "Common",
		evolution = "Fire",
		color = C(255, 120, 50), color2 = C(255, 215, 140),
		trait = "burn", traitLabel = "Kindle", traitText = "hits burn the target: 3% max HP per second for 2 s",
	},
	Frost = {
		id = "Frost", label = "Frost Mage", element = "Ice", rarity = "Rare",
		evolution = "Ice",
		color = C(120, 200, 255), color2 = C(225, 245, 255),
		trait = "chill", traitLabel = "Frostbite", traitText = "hits slow the target by 35% for 1.5 s",
	},
	Storm = {
		id = "Storm", label = "Storm Mage", element = "Lightning", rarity = "Rare",
		evolution = "Storm",
		color = C(130, 160, 255), color2 = C(240, 245, 255),
		trait = "chain", traitLabel = "Arc", traitText = "hits jump to one more enemy nearby for 50%",
	},
	Verdant = {
		id = "Verdant", label = "Verdant Mage", element = "Nature", rarity = "Epic",
		evolution = "Nature",
		color = C(100, 210, 110), color2 = C(210, 255, 200),
		trait = "bloom", traitLabel = "Bloom", traitText = "every 2 s heals the most hurt ally nearby by 5% max HP",
	},
	Shadow = {
		id = "Shadow", label = "Shadow Mage", element = "Shadow", rarity = "Epic",
		evolution = "Shadow",
		color = C(110, 70, 150), color2 = C(200, 160, 255),
		trait = "reap", traitLabel = "Reap", traitText = "20% chance of a 2.2x critical hit; heals 10% of the damage",
	},
	Void = {
		id = "Void", label = "Void Mage", element = "Void", rarity = "Legendary",
		color = C(70, 40, 130), color2 = C(230, 120, 255),
		trait = "rift", traitLabel = "Rift", traitText = "18% chance to stun the target for 0.8 s; +25% damage",
	},
	Celestial = {
		id = "Celestial", label = "Celestial Mage", element = "Light", rarity = "Mythic",
		color = C(255, 215, 120), color2 = C(255, 250, 225),
		trait = "starfall", traitLabel = "Starfall", traitText = "every 4th hit calls a star: 160% damage around the target",
	},
} :: { [string]: Def }

-- The numbers of the battle traits (BattleService applies them to the wizard's attacks).
Wizards.Traits = {
	flow = { Mana = 4 },
	burn = { Dps = 0.03, Time = 2 },
	chill = { Factor = 0.65, Time = 1.5 },
	chain = { Radius = 8, Fraction = 0.5 },
	bloom = { Every = 2, Radius = 16, Heal = 0.05 },
	reap = { Chance = 0.2, Mult = 2.2, Lifesteal = 0.1 },
	rift = { Chance = 0.18, Stun = 0.8, Damage = 0.25 },
	starfall = { Every = 4, Mult = 1.6, Radius = 6 },
}

-- The codex / UI order: by rarity, then as listed.
Wizards.Order = { "Arcane", "Ember", "Frost", "Storm", "Verdant", "Shadow", "Void", "Celestial" }
Wizards.Default = "Arcane" -- a mage without a type (old saves) is an Arcane Mage

function Wizards.isValid(id: any): boolean
	return type(id) == "string" and Wizards.Types[id] ~= nil
end

-- The type of a unit (its `variant`), the default for none.
function Wizards.of(unit: any): Def
	local id = if unit then unit.variant else nil
	return Wizards.Types[if Wizards.isValid(id) then id else Wizards.Default]
end

function Wizards.rarityOf(unit: any): Rarity
	return Wizards.Rarities[Wizards.of(unit).rarity]
end

-- The chance of every rarity at `luck` (1 = normal; luck multiplies the weights of Rare and up, more for the rarer).
-- `minOrder` = only rarities of at least this order (the pity roll).
function Wizards.odds(luck: number, minOrder: number?): { [string]: number }
	local total = 0
	local weights: { [string]: number } = {}
	for _, id in Wizards.RarityOrder do
		local r = Wizards.Rarities[id]
		if r.order >= (minOrder or 1) then
			local w = r.weight * (if r.order > 1 then luck ^ (r.order - 1) * 0.5 + 0.5 * luck else 1)
			weights[id] = w
			total += w
		end
	end
	for id, w in weights do
		weights[id] = w / total
	end
	return weights
end

-- Rolls a wizard type: a rarity by the odds, then a type of that rarity.
function Wizards.roll(rng: Random, luck: number, minOrder: number?): string
	local odds = Wizards.odds(luck, minOrder)
	local pick = rng:NextNumber()
	local rarity = Wizards.RarityOrder[1]
	for _, id in Wizards.RarityOrder do
		local chance = odds[id]
		if chance then
			rarity = id
			if pick < chance then
				break
			end
			pick -= chance
		end
	end
	local pool: { string } = {}
	for _, id in Wizards.Order do
		if Wizards.Types[id].rarity == rarity then
			table.insert(pool, id)
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

-- Coins per minute a wizard earns while you own it (level 1 = the rarity's income, +35% per level, Ascended x2).
function Wizards.income(unit: any): number
	local r = Wizards.rarityOf(unit)
	local tier = if unit and type(unit.tier) == "number" then unit.tier else 1
	return r.income * (1 + 0.35 * (tier - 1)) * (if unit and unit.ascended then 2 else 1)
end

-- "Storm Mage" for a unit.
function Wizards.label(unit: any): string
	return Wizards.of(unit).label
end

return Wizards
