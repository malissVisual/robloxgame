--!strict
-- 6.15, the enemies' subtle outline (the owner: "I'd outline the zombies: a red outline, but just subtle"): the pure
-- rules behind client/EnemyOutline.luau, with their numbers in Config.Outline. Pure (no Roblox at its top level;
-- tests/outline_test.luau runs it in the plain Luau CLI).
--   * OutlinePick.tone(kind, bandit): "human" (orange) for the people the server marks Bandit (the bandits, the gunners,
--     the bandits' pickups) and any kind Config.Outline.HumanKinds names true; else "zombie" (red).
--   * OutlinePick.color(tone): that tone's { r, g, b }.
--   * OutlinePick.limit: the most outlines ever drawn on a client: Config.Outline.Count, but never past Roblox's 31
--     Highlights less Config.Outline.Spare (room for anything else that highlights).
--   * OutlinePick.choose(entries, count, range): which enemies get an outline. Only the living ones within `range`, the
--     nearest first, at most `count` (and never over the limit). One outlined already keeps it out to range ×
--     HoldRange and counts HoldRange times nearer, so two at about the same distance never swap back and forth and one
--     at the edge does not blink. Returns { [index]: tone }.

local Config = require(script.Parent.Config)

local OutlinePick = {}

local Tuning = Config.Outline

export type Tone = "zombie" | "human"

-- One enemy as the client sees it now: how far from the camera, alive (a corpse, a wreck: false), a person, and
-- whether it wears an outline already.
export type Entry = { distance: number, alive: boolean, human: boolean, outlined: boolean }

-- Roblox draws at most 31 Highlights at once on a client.
OutlinePick.ROBLOX_MAX = 31

OutlinePick.limit = math.max(0, math.min(Tuning.Count, OutlinePick.ROBLOX_MAX - Tuning.Spare))

-- kind: the model's Zombie attribute (nil for a pickup); bandit: its Bandit attribute is true.
function OutlinePick.tone(kind: string?, bandit: boolean): Tone
	if bandit or (kind ~= nil and Tuning.HumanKinds[kind] == true) then
		return "human"
	end
	return "zombie"
end

function OutlinePick.color(tone: Tone): { number }
	return if tone == "human" then Tuning.Human else Tuning.Zombie
end

-- The enemies that wear an outline (see the top): { [index]: tone }.
function OutlinePick.choose(entries: { Entry }, count: number, range: number): { [number]: Tone }
	local order: { number } = {}
	local score: { [number]: number } = {}
	for index, entry in entries do
		if entry.alive and entry.distance <= (if entry.outlined then range * Tuning.HoldRange else range) then
			table.insert(order, index)
			score[index] = if entry.outlined then entry.distance / Tuning.HoldRange else entry.distance
		end
	end
	table.sort(order, function(i: number, j: number): boolean
		if score[i] ~= score[j] then
			return score[i] < score[j]
		end
		return i < j
	end)
	local chosen: { [number]: Tone } = {}
	local most = math.min(math.floor(count), OutlinePick.limit)
	for n = 1, math.min(most, #order) do
		local index = order[n]
		local tone: Tone = if entries[index].human then "human" else "zombie"
		chosen[index] = tone
	end
	return chosen
end

return OutlinePick
