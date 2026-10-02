--!strict
-- Achievements: one-time goals with a reward (coins + XP) and a title shown over your head. Progress
-- comes from `profile.stats` (see PlayerData) or from the profile itself (the account level). The order
-- here is the order of the list in the UI.

export type Def = {
	id: string,
	label: string, -- the title you get
	text: string, -- what to do
	stat: string, -- key of profile.stats, or "level"
	target: number,
	coins: number,
	xp: number,
}

local Achievements = {}

Achievements.List = {
	{ id = "kills100", label = "Recruit", text = "Defeat 100 enemies", stat = "kills", target = 100, coins = 150, xp = 80 },
	{ id = "kills1000", label = "Veteran", text = "Defeat 1 000 enemies", stat = "kills", target = 1000, coins = 800, xp = 400 },
	{ id = "kills10000", label = "Warlord", text = "Defeat 10 000 enemies", stat = "kills", target = 10000, coins = 5000, xp = 2500 },
	{ id = "merges50", label = "Tinkerer", text = "Merge 50 times", stat = "merges", target = 50, coins = 200, xp = 100 },
	{ id = "merges500", label = "Master Smith", text = "Merge 500 times", stat = "merges", target = 500, coins = 1500, xp = 700 },
	{ id = "tier5", label = "Rising Star", text = "Create a level 5 character", stat = "maxTier", target = 5, coins = 300, xp = 150 },
	{ id = "tier9", label = "Legend Maker", text = "Create a level 9 character", stat = "maxTier", target = 9, coins = 3000, xp = 1500 },
	{ id = "ascended", label = "Ascended", text = "Create an Ascended character (merge two level 9)", stat = "ascended", target = 1, coins = 6000, xp = 3000 },
	{ id = "waves25", label = "Camper", text = "Win 25 waves", stat = "wavesWon", target = 25, coins = 300, xp = 150 },
	{ id = "waves250", label = "Arena Regular", text = "Win 250 waves", stat = "wavesWon", target = 250, coins = 2500, xp = 1200 },
	{ id = "boss10", label = "Boss Hunter", text = "Beat 10 boss waves", stat = "bossKills", target = 10, coins = 1000, xp = 500 },
	{ id = "nightmare25", label = "Nightmare Walker", text = "Win 25 waves on Nightmare", stat = "nightmareWaves", target = 25, coins = 2500, xp = 1200 },
	{ id = "summons100", label = "Summoner", text = "Summon 100 characters", stat = "summons", target = 100, coins = 400, xp = 200 },
	{ id = "level10", label = "Apprentice", text = "Reach account level 10", stat = "level", target = 10, coins = 500, xp = 0 },
	{ id = "level25", label = "Champion", text = "Reach account level 25", stat = "level", target = 25, coins = 2500, xp = 0 },
} :: { Def }

Achievements.ById = {} :: { [string]: Def }
for _, def in Achievements.List do
	Achievements.ById[def.id] = def
end

-- The stats every profile counts (all start at 0).
Achievements.StatKeys = { "kills", "merges", "maxTier", "ascended", "wavesWon", "bossKills", "nightmareWaves", "summons" }

return Achievements
