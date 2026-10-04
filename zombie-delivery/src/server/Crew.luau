--!strict
-- Crews (Config.Crew): invite another player into your job; members help, ride along and share the pay.
-- [STUB: stream "coop" fills this in.]

local Crew = {}

-- Set by Main: does this player have a job running (server/Jobs.luau Jobs.active)?
Crew.hasJob = function(_player: Player): boolean
	return false
end

-- Set by Main: what the members should see of the owner's job (server/Jobs.luau Jobs.crewStatus): a table with
-- name, step, position (Vector3), stars, endsAt — or nil when the owner has no job.
Crew.statusOf = function(_owner: Player): { [string]: any }?
	return nil
end

-- The players who joined `owner`'s job by invitation (not the owner).
function Crew.members(owner: Player): { Player }
	return {}
end

-- Whose job does this player work on (nil = nobody's / their own)?
function Crew.ownerOf(player: Player): Player?
	return nil
end

-- The job of `owner` ended: the crew breaks up (Jobs calls this).
function Crew.disband(owner: Player) end

function Crew.start() end

return Crew
