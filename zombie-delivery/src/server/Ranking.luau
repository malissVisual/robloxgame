--!strict
-- The server's leaderboard: the best couriers on this server. A client asks over the Leaderboard remote (the window,
-- client/Leaderboard.luau, asks when it opens and every few seconds while it stays open) and gets every player's row:
-- name, level, rank, XP, mission stars (3.0, shared/Missions.luau), deliveries, kills, money earned and whether they are
-- out on a job, and the title they show (3.1). Sorted by level, then mission stars, then money earned, then deliveries. Rows are built from the profiles (server/PlayerData.luau) on demand: nothing runs
-- while nobody looks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Levels = require(Shared.Levels)
local Missions = require(Shared.Missions)
local Net = require(Shared.Net)

local Server = script.Parent
local PlayerData = require(Server.PlayerData)
local Jobs = require(Server.Jobs)

local Ranking = {}

export type Row = {
	userId: number,
	name: string, -- the display name
	user: string, -- the @user name
	level: number,
	rank: string,
	xp: number,
	progress: number, -- 0 … 1 into the level
	stars: number, -- the mission stars collected (the best rating of every mission, summed)
	starsMax: number, -- the most there are
	deliveries: number,
	kills: number,
	earned: number,
	onJob: boolean,
	title: string?, -- 3.1: the title they show (server/Challenges.luau), nil = none
}

local MIN_GAP = 0.5 -- seconds between two answers to one player (a spammed remote costs nothing)
local lastAsk: { [Player]: number } = {}

-- Better first: level, then mission stars, then money earned, then deliveries, then the name (stable).
local function better(a: Row, b: Row): boolean
	if a.level ~= b.level then
		return a.level > b.level
	end
	if a.stars ~= b.stars then
		return a.stars > b.stars
	end
	if a.earned ~= b.earned then
		return a.earned > b.earned
	end
	if a.deliveries ~= b.deliveries then
		return a.deliveries > b.deliveries
	end
	return a.name:lower() < b.name:lower()
end

-- Every player whose save has loaded, best first.
function Ranking.rows(): { Row }
	local rows: { Row } = {}
	for _, player in Players:GetPlayers() do
		local profile = PlayerData.get(player)
		if not profile then
			continue
		end
		local level = Levels.levelFor(profile.xp)
		local stars, starsMax = Missions.stars(profile.missions, nil)
		table.insert(rows, {
			userId = player.UserId,
			name = player.DisplayName,
			user = player.Name,
			level = level,
			rank = Levels.rank(level),
			xp = profile.xp,
			progress = Levels.progress(profile.xp),
			stars = stars,
			starsMax = starsMax,
			deliveries = profile.deliveries,
			kills = profile.kills,
			earned = profile.earned,
			onJob = Jobs.involved(player), -- their own job, or in the crew of one
			title = profile.title,
		})
	end
	table.sort(rows, better)
	return rows
end

function Ranking.start()
	local remote = Net.get("Leaderboard")
	remote.OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if lastAsk[player] and now - lastAsk[player] < MIN_GAP then
			return
		end
		lastAsk[player] = now
		remote:FireClient(player, Ranking.rows())
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAsk[player] = nil
	end)
end

return Ranking
