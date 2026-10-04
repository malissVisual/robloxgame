--!strict
-- Real estate (Config.Estate): buying, selling, the home you spawn at, car slots from garages, owner name plates.
-- [STUB: stream "estate-logic" fills this in.]

local Estate = {}

function Estate.owns(_player: Player, _id: string): boolean
	return false
end

-- The home you spawn at, or nil (the depot).
function Estate.homeOf(_player: Player): string?
	return nil
end

-- How many cars you can own: Config.Estate.BaseCarSlots + every owned home's and garage's garageSlots.
function Estate.carSlots(_player: Player): number
	return 1000
end

-- The office you run your company from (the biggest owned one), or nil.
function Estate.officeOf(_player: Player): string?
	return nil
end

function Estate.start() end

return Estate
