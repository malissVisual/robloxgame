--!strict
-- Pure station assembly blueprint for a 70x50 lot. Relative component frames, route/entry points and parking details.
return {
	id = "gasstation", width = 70, depth = 50,
	components = {
		{ name = "Forecourt", model = "island", at = { -16, 0, -6 } },
		{ name = "Shop", blueprint = "GasKiosk", at = { 18, 0, 12 } },
		{ name = "RoadPrice", model = "pricesign", at = { 32, 0, -19 } },
	} :: { any },
	-- ModelArt pieces (lot-frame targets); markings have no collision or query effect.
	pieces = {
		{ name = "BayLine1", attach = "Frame", finish = "reflector", size = { .08, .025, 14 }, at = { 5, .025, -6 } },
		{ name = "BayLine2", attach = "Frame", finish = "reflector", size = { .08, .025, 14 }, at = { 13.5, .025, -6 } },
		{ name = "BayLine3", attach = "Frame", finish = "reflector", size = { .08, .025, 14 }, at = { 22, .025, -6 } },
		{ name = "BayLine4", attach = "Frame", finish = "reflector", size = { .08, .025, 14 }, at = { 30.5, .025, -6 } },
		{ name = "ParkingStop1", attach = "Frame", finish = "worn", size = { 4, .12, .25 }, at = { 9.25, .06, .65 } },
		{ name = "ParkingStop2", attach = "Frame", finish = "worn", size = { 4, .12, .25 }, at = { 17.75, .06, .65 } },
		{ name = "ParkingStop3", attach = "Frame", finish = "worn", size = { 4, .12, .25 }, at = { 26.25, .06, .65 } },
	},
	points = {
		{ name = "EntranceLeft", at = { -21.2, 0, -24 } }, { name = "EntranceRight", at = { -10.8, 0, -24 } },
		{ name = "ExitLeft", at = { -21.2, 0, 24 } }, { name = "ExitRight", at = { -10.8, 0, 24 } },
		{ name = "KioskEntry", at = { 18, 0, 2.8 } },
	},
}
