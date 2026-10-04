--!strict
-- Cargo you handle on foot: crates, sacks, barrels, ice boxes, furniture you pick up and carry in your hands, horses
-- you lead on a rope, passengers who walk in by themselves. Loaded pieces ride visibly in the vehicle.
-- [STUB: stream A "gameplay" fills this in, driven by server/Jobs.luau.]

local Cargo = {}

-- Is this character carrying something (the kind) or leading an animal ("horse")?
function Cargo.carrying(character: Model?): string?
	if not character then
		return nil
	end
	local value = character:GetAttribute("Carrying")
	return if type(value) == "string" then value else nil
end

function Cargo.start() end

return Cargo
