--!strict
-- The Dispatch board (3.6, Postage & Trouble): the job board as a window of die-cut delivery tickets (J and the JOBS
-- button). Asks the server for offers (RequestOffers), shows them (Offers: the same rows Hud.setOffers got: stars,
-- route, pieces/slots, needs/holds, locked level, special jobs, modifiers, pay, time) and accepts one (AcceptJob).
-- Filters: all / deliveries / special. Locked tickets say why and what to do (level, slots: a stage at Wrench Garage or a
-- bigger car at your garage).
-- [contract stub: stream "dispatch" writes it]

local DispatchUi = {}

-- Set by Main: opening this window closes the others.
DispatchUi.onOpen = nil :: (() -> ())?

local open = false

function DispatchUi.isOpen(): boolean
	return open
end

function DispatchUi.close()
	open = false
end

function DispatchUi.open()
	open = false
end

function DispatchUi.toggle()
	if open then
		DispatchUi.close()
	else
		DispatchUi.open()
	end
end

-- The offers the server sent (Main wires Net "Offers" here too); the state (money, level, car) for the footer.
function DispatchUi.setOffers(_list: { any }) end
function DispatchUi.setState(_state: any) end

function DispatchUi.start() end

return DispatchUi
