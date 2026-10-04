--!strict
-- The missions on the server (3.0, shared/Missions.luau): the MISSIONS window's state (each player's best ratings,
-- what is open, the campaigns), starting a mission (checked: open, level, no job running, not in somebody else's
-- crew; then server/Jobs.luau startMission plays it), and the rewards when one is done (Jobs.onMissionComplete):
-- the first clear's reward, every new star, the campaign's reward, the crew's credit.
-- [contract stub: stream "missions-server" writes it]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Missions = {}

-- The progress a player's MISSIONS window shows (sent on "open", after every change).
function Missions.send(_player: Player) end

-- Jobs.onMissionComplete is wired to this in Main: the owner and everyone paid with them (members), the rating.
function Missions.onComplete(_owner: Player, _missionId: string, _stars: number, _members: { Player }) end

function Missions.start()
	Net.get("Missions")
end

return Missions
