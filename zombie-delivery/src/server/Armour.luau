--!strict
-- 6.0: the one place a player is hurt by the world (a zombie's bite or blow, a bloater's blast). 10.5: no vest takes a
-- share off and no Second Wind turns a lethal hit (the city's kit and skills went); the hit goes through
-- Humanoid:TakeDamage, so a ForceField (a spawn's) still stops all of it.
--
--   Armour.hurt(humanoid, amount)   deals the hit

local Armour = {}

function Armour.hurt(humanoid: Humanoid, amount: number)
	if amount > 0 then
		humanoid:TakeDamage(amount)
	end
end

return Armour
