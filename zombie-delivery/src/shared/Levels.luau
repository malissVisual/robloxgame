--!strict
-- Driver levels: the XP curve, the rank names and the XP a delivery is worth (Config.Levels). Pure Luau, tested in
-- tests/levels_test.luau. The profile keeps the XP (server/PlayerData.luau); the level always comes from it.

local Config = require(script.Parent.Config)

local Levels = {}

-- Total XP needed to reach `level` on a curve (base, growth).
local function curveXp(level: number, base: number, growth: number): number
	local total = 0
	for n = 2, math.clamp(level, 1, Config.Levels.MaxLevel) do
		total += math.floor(base * growth ^ (n - 2) + 0.5)
	end
	return total
end

-- Total XP needed to reach `level` (level 1 = 0).
function Levels.xpFor(level: number): number
	return curveXp(level, Config.Levels.XpBase, Config.Levels.XpGrowth)
end

-- 3.2: XP saved on the 3.1 curve (Config.Levels.Legacy) moved onto the current one: the same level and the same share
-- of the way to the next, never less than saved. PlayerData converts a save once (no xpCurve = Config.Levels.Curve).
function Levels.fromLegacy(xp: number): number
	local legacy = Config.Levels.Legacy
	local max = Config.Levels.MaxLevel
	local level = 1
	while level < max and xp >= curveXp(level + 1, legacy.XpBase, legacy.XpGrowth) do
		level += 1
	end
	local moved = Levels.xpFor(level)
	if level < max then
		local from, to = curveXp(level, legacy.XpBase, legacy.XpGrowth), curveXp(level + 1, legacy.XpBase, legacy.XpGrowth)
		local share = math.clamp((xp - from) / math.max(1, to - from), 0, 1)
		moved += math.floor((Levels.xpFor(level + 1) - moved) * share)
	end
	return math.max(xp, moved)
end

-- The level reached with this much XP.
function Levels.levelFor(xp: number): number
	local level = 1
	while level < Config.Levels.MaxLevel and xp >= Levels.xpFor(level + 1) do
		level += 1
	end
	return level
end

-- The rank name of a level.
function Levels.rank(level: number): string
	local name = Config.Levels.Ranks[1].name
	for _, rank in Config.Levels.Ranks do
		if level >= rank.level then
			name = rank.name
		end
	end
	return name
end

-- How far into the current level (0 … 1), for the HUD bar.
function Levels.progress(xp: number): number
	local level = Levels.levelFor(xp)
	if level >= Config.Levels.MaxLevel then
		return 1
	end
	local from, to = Levels.xpFor(level), Levels.xpFor(level + 1)
	return math.clamp((xp - from) / math.max(1, to - from), 0, 1)
end

-- The XP a delivery is worth.
function Levels.jobXp(stars: number, pieces: number, kills: number, night: boolean, success: boolean): number
	local L = Config.Levels
	local xp = stars * L.XpPerStar + pieces * L.XpPerPiece + kills * L.XpPerKill
	if night then
		xp *= L.XpNightBonus
	end
	if not success then
		xp *= L.XpFailed
	end
	return math.floor(xp + 0.5)
end

return Levels
