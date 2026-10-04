--!strict
-- The road network as a graph (from shared/Map.luau's segments: the district grids, bridges, highways, the ice road)
-- and the shortest drive between two points along it, for the GPS route on the maps (like GTA). Pure Luau (no
-- Roblox types), so tests/roads_test.luau runs it outside Roblox.
-- [STUB: stream D "map" fills this in.]

local Roads = {}

export type Point = { x: number, z: number }

-- The drive from (fromX, fromZ) to (toX, toZ) along the roads: points from where you are to the target (the last
-- bits off the road are straight lines). Just the two ends if there is no way.
function Roads.route(fromX: number, fromZ: number, toX: number, toZ: number): { Point }
	return { { x = fromX, z = fromZ }, { x = toX, z = toZ } }
end

return Roads
