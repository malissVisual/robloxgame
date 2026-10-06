--!strict
-- 4.5: the admin's test buddies: NPC companions that play along with their owner (follow on foot, ride in the
-- owner's car as passengers, fight the zombies and bandits around them). Only the admin tools make them (server/Admin
-- commands "buddy", "buddyDismiss", "buddyMode"). Contract stub: the real behaviour comes in this file.

local Buddy = {}

export type Mode = "follow" | "stay" | "guard"

-- Makes `count` buddies for the owner (capped); returns how many the owner has now.
function Buddy.spawn(owner: Player, count: number?): number
	return 0
end

-- Removes the owner's buddies.
function Buddy.dismiss(owner: Player)
end

-- follow: with you (on foot, and into your car); stay: where they stand (they still fight); guard: they stand and
-- fight anything that comes near, and run back to their spot.
function Buddy.setMode(owner: Player, mode: Mode)
end

-- How many buddies the owner has.
function Buddy.count(owner: Player): number
	return 0
end

function Buddy.start() end

return Buddy
