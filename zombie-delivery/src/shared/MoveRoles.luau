--!strict
-- A run's quick chat and the climb with a carried piece, pure (no Roblox at the top level: tests/moveroles_test.luau).
-- The module keeps the name of the 7.0 roles it held (8.8 the owner: "I don't want roles in the game. Everyone is
-- simply the same."; 10.9: the roles and the planning lobby deleted). The numbers are Config.MoveRoles'.
--   MoveRoles.Chat                  the quick chat's six lines (an id, an icon, the words): client/QuickChat.luau shows
--                                   them, server/MoveLobby.luau sends one to the run's party
--   MoveRoles.climbing(rise, run)   is this step up stairs or a slope (Climb.Rise studs up a stud along)?
--   MoveRoles.climbFactor(mode)     × the walk going up with a piece (MovingRules.mode's; 1: a piece in one hand)
--   MoveRoles.whyText(why)          what the player is told (server/Moving.luau's van call)

local Config = require(script.Parent.Config)

local MoveRoles = {}

local function tune(): any
	return (Config :: any).MoveRoles
end

-- The quick chat (client/QuickChat.luau: hold T): six lines, by number.
MoveRoles.Chat = {
	{ id = "door", icon = "✋", text = "Hold the door" },
	{ id = "hand", icon = "🙏", text = "Need a hand here" }, -- (the party hears it; 8.3: Danny is given pieces, never called by it)
	{ id = "zombies", icon = "🧟", text = "Zombies!" },
	{ id = "truck", icon = "🚚", text = "Truck's here" },
	{ id = "pickup", icon = "🏃", text = "I'll come pick you up" },
	{ id = "done", icon = "✅", text = "Done — let's go" },
} :: { { id: string, icon: string, text: string } }

-- Is a step of `rise` studs up over `run` studs along a climb (stairs, a slope)?
function MoveRoles.climbing(rise: number, run: number): boolean
	if rise ~= rise or run ~= run or rise <= 0.25 then
		return false
	end
	return rise >= tune().Climb.Rise * math.max(run, 0.5)
end

-- × the walk up a climb with a piece: Climb.Walk unless it is in one hand.
function MoveRoles.climbFactor(mode: string): number
	if mode == "hand" then
		return 1
	end
	return tune().Climb.Walk
end

local WHY: { [string]: string } = {
	called = "The van was called once already this move.",
}

function MoveRoles.whyText(why: string?): string
	return WHY[why or ""] or "You can't do that now."
end

return MoveRoles
