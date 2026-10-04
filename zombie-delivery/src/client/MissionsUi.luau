--!strict
-- The MISSIONS window (3.0, key U and the MISSIONS button): the ten campaigns (shared/Missions.luau) with their
-- progress and stars, each campaign's ten missions (open / locked / done with the rating), the briefing, the twists,
-- the CO-OP badge and START (server/Missions.luau checks it). During a mission: its banner and the twists in the
-- Hud's top stack; when it is done: the rating.
-- [contract stub: stream "missions-ui" writes it]

local MissionsUi = {}

-- Set by Main: opening this window closes the others.
MissionsUi.onOpen = nil :: (() -> ())?

local open = false

function MissionsUi.isOpen(): boolean
	return open
end

function MissionsUi.close()
	open = false
end

function MissionsUi.toggle()
	open = false
end

function MissionsUi.start() end

return MissionsUi
