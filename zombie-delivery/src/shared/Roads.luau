--!strict
-- The road network as a graph (from shared/Map.luau's segments: the district grids, bridges, highways, the ice road)
-- and the shortest drive between two points along it, for the GPS route on the maps (like GTA).
-- [STUB: stream D "map" fills this in.]

local Roads = {}

-- The drive from `from` to `to` along the roads: a list of points (x, z), starting where you are and ending at the
-- target (the last bits off the road are straight lines). Empty if there is no way.
function Roads.route(fromX: number, fromZ: number, toX: number, toZ: number): { Vector2 }
	return { Vector2.new(fromX, fromZ), Vector2.new(toX, toZ) }
end

return Roads
