--!strict
-- 6.1, what you hold in your hand (the owner's wish: "you choose to hold the pistol or the bag; when there is cargo in
-- the bag you can only put it down, you can't hide it and pretend you have nothing"): the pure rules (no Roblox at the
-- top level: tests/holding_test.luau). The server keeps the real hand (server/Hand.luau: the character attribute Hand,
-- the Hand remote), server/Cargo.luau what the bag holds, the client shows it (client/Hotbar.luau's hand slots, keys
-- 1 / 2 / 3, client/Holster.luau) and asks.
--
--   fists  the gun holstered, the hands free: V punches
--   bag    the plastic bag (Config.Courier.BagKit) in the left hand, the gun holstered: what you pick up drops into it,
--          you throw from it (X at a home's door)
--   gun    the gun you equipped drawn (the weapon wheel, T, still says which one; B draws and holsters as before)
-- A bag that leaves the hand: loaded, it is set down on the ground where you stand with its cargo in it (pick it up
-- again: E, "Pick up bag"), empty, it is stowed (nothing shows, its room is not yours).
--
--   Holding.Order                              the hands in key order (1 fists, 2 bag, 3 gun)
--   Holding.valid(hand)                        one of them?
--   Holding.keyOf(hand) / Holding.ofKey(key)   1 … 3 and back
--   Holding.can(hand, ownsBag, hasGun, bagDown)  may you take it now: (true) or (false, why: "nobag" | "bagdown" | "nogun")
--   Holding.whyText(why)                       what the player is told
--   Holding.cycle(hand, step, ownsBag, hasGun, bagDown)  the next hand you may take that way (a gamepad's d-pad)
--   Holding.atSpawn(ownsBag, bagDown)          a new body: the bag when it is yours and with you, else fists
--   Holding.afterHolster(last, ownsBag, bagDown)  B puts the gun away: back to what you held before (the bag, if it is
--                                              still with you), else fists
--   Holding.bagLeaves(count, stays)            the bag leaves your hand with `count` pieces in it: "down" | "stow";
--                                              6.4: "back" for a bag that stays on you (Config.Kit stays: the tote,
--                                              the messenger, the duffel swing onto your back, their pieces with you)
--   Holding.wornAs(hand, carry, stays, seated)  6.4: where the bag shows: "hand" | "shoulder" | "hip" | "back" | nil
--   Holding.bikeNear(seated, distance, reach)  6.6: is your bike's own bag within reach: you sit on it, or it stands
--                                              `distance` studs from you, no more than `reach` (Config.Cargo.BikeReach);
--                                              nil distance: no bike out
--   Holding.bikeAction(held, fits, bikeFree, onBike, drop)  6.19: what E at your bike's rack does (server/Cargo.luau's
--                                              prompt on it): "load" (the `held` pieces in your hands all `fits` the
--                                              bike's bag and it has `bikeFree` room for one), "take" (empty hands at a
--                                              `drop` with `onBike` pieces on it: one into your hands), else nil (off)
--   Holding.bikeText(action, piece, count, room)  6.19: the prompt's words: ("Load onto bike", "Your bike: pizza 1 / 3")
--   Holding.place(light, bikeNear, bikeFree, bagHeld, bagFree)  6.6: where a piece you pick up goes: "bike" (a light
--                                              piece, the bike within reach with room on it), else "bag" (a light
--                                              piece, the bag in your hand with room in it), else "hands". A heavy
--                                              piece only ever the hands. (6.6: no backpack, one carrying item)
--   Holding.throwText(ready, door, far, fragile, range)  pressing X: nil = aim, else the toast. `ready` the server's
--                                              ThrowReady ("piece" | "fragile" | nil: what you could throw anywhere),
--                                              `door` a home's door for it (ThrowTo), `far` farther than `range`,
--                                              `fragile` the door's pieces are too fragile (ThrowFragile)

local Holding = {}

Holding.Order = { "fists", "bag", "gun" }

local WHY: { [string]: string } = {
	nobag = "No bag this game: buy one at ZDC Bags (by the spawn).", -- (6.6: the bag kiosk by the spawn; 6.23: Config.BagShop.NoBag)
	bagdown = "Your bag is on the ground where you set it down: go back and pick it up (E).",
	nogun = "No gun in your hands yet: Lead & Co. sells guns. Till then, your fists.", -- (6.7: the pistol is every courier's, not sold)
	seated = "Get out first.",
	busy = "Your hands are full: put it down (G) first.",
}

function Holding.valid(hand: any): boolean
	return type(hand) == "string" and table.find(Holding.Order, hand) ~= nil
end

function Holding.keyOf(hand: string): number?
	return table.find(Holding.Order, hand)
end

function Holding.ofKey(key: number): string?
	return Holding.Order[key]
end

function Holding.can(hand: string, ownsBag: boolean, hasGun: boolean, bagDown: boolean): (boolean, string?)
	if hand == "fists" then
		return true, nil
	elseif hand == "bag" then
		if not ownsBag then
			return false, "nobag"
		elseif bagDown then
			return false, "bagdown"
		end
		return true, nil
	elseif hand == "gun" then
		if not hasGun then
			return false, "nogun"
		end
		return true, nil
	end
	return false, nil
end

function Holding.whyText(why: string?): string
	return if why then WHY[why] or "You can't take that now." else "You can't take that now."
end

function Holding.cycle(hand: string, step: number, ownsBag: boolean, hasGun: boolean, bagDown: boolean): string
	local count = #Holding.Order
	local at = Holding.keyOf(hand) or 1
	local way = if step < 0 then -1 else 1
	for n = 1, count do
		local other = Holding.Order[(at - 1 + way * n) % count + 1]
		if Holding.can(other, ownsBag, hasGun, bagDown) then
			return other
		end
	end
	return hand
end

function Holding.atSpawn(ownsBag: boolean, bagDown: boolean): string
	return if ownsBag and not bagDown then "bag" else "fists"
end

function Holding.afterHolster(last: string?, ownsBag: boolean, bagDown: boolean): string
	if last == "bag" and Holding.can("bag", ownsBag, false, bagDown) then
		return "bag"
	end
	return "fists"
end

function Holding.bagLeaves(count: number, stays: boolean?): string
	if stays then
		return "back" -- 6.4: a shoulder / cross-body / slung bag stays on you, loaded or not
	end
	return if count > 0 then "down" else "stow"
end

-- 6.4: where the active bag shows on you: while it is the hand its carry ("hand" | "shoulder" | "hip"; in a seat a bag
-- that stays goes on the back, a hand bag is put away), else "back" for one that stays, nil (stowed or on the ground).
function Holding.wornAs(hand: string, carry: string?, stays: boolean?, seated: boolean): string?
	if hand == "bag" and not seated then
		return if carry == "shoulder" or carry == "hip" then carry else "hand"
	end
	return if stays then "back" else nil
end

function Holding.bikeNear(seated: boolean, distance: number?, reach: number): boolean
	if seated then
		return true
	end
	return distance ~= nil and distance == distance and distance <= reach
end

function Holding.bikeAction(held: number, fits: boolean, bikeFree: number, onBike: number, drop: boolean): string?
	if held > 0 then
		return if fits and bikeFree > 0 then "load" else nil
	end
	return if drop and onBike > 0 then "take" else nil
end

function Holding.bikeText(action: string?, piece: string, count: number, room: number): (string, string)
	local object = `Your bike: {piece} {count} / {room}`
	if action == "take" then
		return "Take off bike", object
	end
	return "Load onto bike", object
end

function Holding.place(light: boolean, bikeNear: boolean, bikeFree: number, bagHeld: boolean, bagFree: number): string
	if not light then
		return "hands"
	elseif bikeNear and bikeFree > 0 then
		return "bike"
	elseif bagHeld and bagFree > 0 then
		return "bag"
	end
	return "hands"
end

function Holding.throwText(ready: string?, door: boolean, far: boolean, fragile: boolean, range: number): string?
	local near = `Get within {range} studs of the delivery door to throw.`
	if door then
		if fragile then
			return "Too fragile to throw: hand it over at the door."
		end
		return if far then near else nil
	end
	if ready == "piece" then
		return near
	elseif ready == "fragile" then
		return "Too fragile to throw: hand it over at the door."
	end
	return "Nothing to throw: hold the bag (2) with a delivery in it, or a light piece in your hands."
end

return Holding
