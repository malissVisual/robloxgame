--!strict
-- 5.0: how a player gets cargo around — on foot, by bike (5.1) or by car — and how much they can take. Pure: the server
-- (server/Transport.luau Transport.of) and the client fill in a `Kit` (the personal gear owned, Config.Kit) and the
-- vehicle's capacity; everything that used to read the car's capacity (the board, Jobs' room checks, Cargo's hands)
-- asks here instead, so a player without a car can work.
--
-- Pure Luau (tests/transport_test.luau).

local Config = require(script.Parent.Config)

local Transport = {}

export type Mode = "foot" | "bike" | "car"
export type Kit = { [string]: boolean } -- Config.Kit ids owned (personal gear: backpacks, shoes …)
export type Info = {
	mode: Mode,
	room: number, -- pieces you can take on one order (hands + backpack on foot; the vehicle's room otherwise)
	lightOnly: boolean, -- only Config.Cargo.LightLooks (on foot, on a bike)
	speedMult: number, -- walk / ride speed multiplier from the kit (1 = none)
}

-- How many light pieces you carry in your hands and on your back (Config.Cargo.HandsMax + the best backpack's room).
function Transport.handsRoom(kit: Kit): number
	return Config.Cargo.HandsMax
end

-- The walk / sprint multiplier from the kit (running shoes …).
function Transport.speedMult(kit: Kit): number
	return 1
end

-- On foot with this kit.
function Transport.foot(kit: Kit): Info
	return { mode = "foot", room = Transport.handsRoom(kit), lightOnly = true, speedMult = Transport.speedMult(kit) }
end

return Transport
