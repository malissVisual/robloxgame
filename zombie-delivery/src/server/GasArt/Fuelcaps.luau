--!strict
-- Pure filler positions for all 17 fleet styles, relative to Chassis CENTER. No parts, prompts or vehicle edits.
local Fuelcaps = {}
type Mount = { width: number, length: number, bodyWidth: number, y: number, z: number }
local mounts: { [string]: Mount } = {
	van = { width = 6.6, length = 13, bodyWidth = 6.6, y = 1.8, z = 2.3 },
	courier = { width = 6.2, length = 12, bodyWidth = 6.2, y = 1.7, z = 2.1 },
	highroof = { width = 6.8, length = 14, bodyWidth = 6.8, y = 1.9, z = 2.6 },
	pickup = { width = 6.4, length = 13, bodyWidth = 6.4, y = 1.1, z = 2.4 },
	boxtruck = { width = 7.4, length = 17, bodyWidth = 7.4, y = 2, z = 3 },
	muscle = { width = 6.4, length = 13.5, bodyWidth = 6.4, y = 1.1, z = 4.35 },
	freighttruck = { width = 9, length = 30, bodyWidth = 9, y = 2.3, z = 6.1 },
	armorvan = { width = 7, length = 14.5, bodyWidth = 7, y = 2.2, z = 2.6 },
	rallyvan = { width = 6.6, length = 13.2, bodyWidth = 6.6, y = 1.8, z = 2.4 },
	icecream = { width = 6.8, length = 14, bodyWidth = 6.8, y = 1.8, z = 2.5 },
	armored = { width = 7.4, length = 15, bodyWidth = 7.4, y = 2.1, z = 2.8 },
	bus = { width = 8, length = 24, bodyWidth = 8, y = 1.7, z = 8.4 },
	movingtruck = { width = 7.4, length = 17, bodyWidth = 7.6, y = 2, z = 3.2 },
	monster = { width = 8, length = 14, bodyWidth = 7, y = 1.45, z = 2.3 },
	livestock = { width = 7.6, length = 20, bodyWidth = 7.6, y = 1.2, z = 3.4 },
	fueltruck = { width = 7.2, length = 16, bodyWidth = 6.4, y = 1.2, z = 2.1 },
	ambulance = { width = 7, length = 15, bodyWidth = 7.4, y = 1.7, z = 2.8 },
}
function Fuelcaps.styles(): { string }
	local result = {}
	for id in mounts do table.insert(result, id) end
	table.sort(result)
	return result
end
function Fuelcaps.point(style: string, currentWidth: number?, currentLength: number?): any
	local m = mounts[style]
	assert(m, "Unknown fleet filler style: " .. style)
	local width, length = currentWidth or m.width, currentLength or m.length
	assert(width > 0 and width < 100 and length > 0 and length < 100, "Invalid filler dimensions")
	-- Follow the enlarged cargo quarter after a stage stretch. Normal points stay behind the cab door, above arches.
	return { name = "FuelFiller", attach = "Chassis", at = { m.bodyWidth / 2 * width / m.width + .04, m.y + .6, m.z + (length - m.length) * .7 }, turn = { 0, -90, 0 } }
end
return Fuelcaps
