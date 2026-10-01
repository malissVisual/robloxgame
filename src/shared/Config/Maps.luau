--!strict
-- Maps (arenas). A map has 20 phases of 5 waves (100 waves), its enemy roster (Config/Enemies.luau) and its
-- look. There is one map, the Training Camp; a new one would be a new block in `Defs` and in `Order`.

-- A phase = Balance.PhaseLength (5) waves: the enemy kinds that appear (repeated entries appear
-- more often) and the boss of the phase's last wave.
export type Phase = {
	name: string,
	kinds: { string },
	boss: string,
}

export type Def = {
	label: string,
	arena: string, -- location name shown on the gate
	floorColor: Color3,
	floorMaterial: Enum.Material,
	laneColor: Color3,
	laneMaterial: Enum.Material,
	fenceColor: Color3,
	decor: string?, -- the designed look of the arena (services/DecorData + ArenaDecor.luau)
	enemyName: string, -- what the enemies are called in the wave heading
	waves: number, -- how many waves the map has (a multiple of Balance.PhaseLength)
	phases: { Phase }, -- 5 waves each: new, better enemies every 5 waves
}

-- Every phase adds ONE new mob (<prefix>Mob<n>) to the ones of the last three phases and ends with its
-- own boss (<prefix>Boss<n>).
local function makePhases(prefix: string, names: { string }): { Phase }
	local phases: { Phase } = {}
	for n, name in names do
		local kinds: { string } = {}
		for mob = n, math.max(1, n - 3), -1 do
			table.insert(kinds, prefix .. "Mob" .. mob)
			if mob == n then
				table.insert(kinds, prefix .. "Mob" .. mob) -- the newest mob is twice as common
			end
		end
		phases[n] = { name = name, kinds = kinds, boss = prefix .. "Boss" .. n }
	end
	return phases
end

local Maps = {}

Maps.First = "Training"
Maps.Order = { "Training" }

Maps.Defs = {
	Training = {
		label = "Training Camp",
		arena = "ARENA 1",
		floorColor = Color3.fromRGB(214, 190, 140), -- the sand of the designed Training Arena 1
		floorMaterial = Enum.Material.Sand,
		laneColor = Color3.fromRGB(190, 162, 110),
		laneMaterial = Enum.Material.Sand,
		fenceColor = Color3.fromRGB(92, 58, 28),
		decor = "TrainingArena1",
		enemyName = "monsters",
		waves = 100,
		phases = makePhases("", {
			"Goblin Scouts", "Goblin Raiders", "Goblin Warband", "Shaman's Circle",
			"Hobgoblin Patrol", "Hobgoblin Marksmen", "Hobgoblin Siege Party", "Hobgoblin Hex Pack",
			"Orc Vanguard", "Orc Hunters", "Orc Crushers", "Orc Warlocks",
			"Troll Ambush", "Troll Stalkers", "Troll Stampede", "Troll Witchcraft",
			"Demon Scouts", "Demon Archers", "Demon Legion", "The Emperor's Court",
		}),
	},
} :: { [string]: Def }

function Maps.isValid(id: any): boolean
	return type(id) == "string" and Maps.Defs[id] ~= nil
end

return Maps
