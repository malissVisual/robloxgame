--!strict
-- A run's party (10.6: the city's crews, their invitations, the crew board and the CREW panel's remotes are gone; the
-- client has no crew panel any more). server/Runs.luau sets both hooks as it starts: a run's party is its host's, the
-- players who stepped onto the portal's pads with them. server/Moving.luau asks them for whoever is on a run.
--
--   Crew.members(owner)   the players in `owner`'s party, the owner left out (none until Runs sets it)
--   Crew.ownerOf(player)  the host of the party `player` is in, not themselves (nil: none, or they host it)

local Crew = {}

Crew.members = function(_owner: Player): { Player }
	return {}
end

Crew.ownerOf = function(_player: Player): Player?
	return nil
end

return Crew
