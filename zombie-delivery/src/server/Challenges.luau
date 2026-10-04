--!strict
-- The challenges, secrets and rewards on the server (3.1): counts the stats (Challenges.Counters) from the game's
-- events, marks places visited and secret packages found (World.SecretPrompts), checks the challenges and pays them,
-- gives the campaign / secrets / all-challenges rewards (Config.Rewards: exclusive guns and paints, titles), shows
-- the chosen title over the player's head, and answers the "Challenges" remote.
-- [contract stub: stream "challenges-server" writes it]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Challenges = {}

-- Count a stat (a Challenges.Counters name) for a player.
function Challenges.add(_player: Player, _stat: string, _amount: number?) end

-- A campaign was finished (server/Missions.luau): its reward (Config.Rewards.Campaigns).
function Challenges.campaignDone(_player: Player, _campaignId: string) end

-- Check every challenge now (after anything that changes the profile-derived stats).
function Challenges.check(_player: Player) end

function Challenges.start()
	Net.get("Challenges")
end

return Challenges
