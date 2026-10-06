--!strict
-- The Post Office (Map.Venues "postoffice", 5.3): the storefront (Kit.storefront) under a blue and yellow awning, a
-- blue mailbox on the walk right of the door, the parcel shelf inside, a flag on the roof. Decoration only.
local Kit = require(script.Parent.Kit)

local BLUE, YELLOW, STEEL = { 40, 80, 170 }, { 230, 200, 60 }, { 150, 154, 158 }

return Kit.storefront({
	id = "venue_postoffice",
	awning = { 32, 60, 120 },
	stripe = YELLOW,
	trim = { 70, 74, 80 },
	counter = { 150, 140, 120 },
	menu = "LETTERS · PARCELS · STAMPS",
	poster = "OPEN",
	extras = {
		{ name = "Mailbox", position = { 11.5, 1.8, -13.6 }, size = { 1.8, 3.2, 1.6 }, color = BLUE, material = "Metal" },
		{ name = "MailboxTop", position = { 11.5, 3.4, -13.6 }, size = { 1.6, 1.8, 1.8 }, color = BLUE, material = "Metal", rotation = { 0, 90, 0 }, shape = "Cylinder" },
		{ name = "ParcelShelf", position = { 13.9, 5, 2 }, size = { 1.2, 0.25, 10 }, color = { 150, 140, 120 }, material = "Wood" },
		{ name = "Parcels", position = { 13.9, 5.8, 2 }, size = { 1, 1.4, 8 }, color = { 176, 140, 96 }, material = "SmoothPlastic" },
		{ name = "FlagPole", position = { -12, 15.5, 8 }, size = { 0.3, 5, 0.3 }, color = STEEL, material = "Metal" },
		{ name = "Flag", position = { -11, 17.3, 8 }, size = { 2, 1.2, 0.1 }, color = BLUE, material = "SmoothPlastic" },
	},
})
