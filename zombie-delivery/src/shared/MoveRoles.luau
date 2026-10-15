--!strict
-- 7.0 planning (the owner's rework, design/rework/NAVRH.md §2–3: "the planning, a lobby like GTA's", the roles; the
-- owner took the Technician out, so three): the roles of a move and the planning lobby's rules, pure (no Roblox at the
-- top level: tests/moveroles_test.luau).
-- server/MoveLobby.luau runs the lobby with these, server/Moving.luau the roles' abilities on a move, client/
-- MoveLobbyUi.luau and client/MovingHud.luau show them, client/QuickChat.luau sends MoveRoles.Chat. The numbers are
-- Config.MoveRoles'.
--
--   The roles (MoveRoles.Roles, in MoveRoles.Order; MoveRoles.loadout(id): its kit as one line, from the numbers)
--     🚚 driver   no wait at the truck's Load / Unload; the truck (and its load) takes Driver.TruckDamage of a hit while
--                 a Driver is at its wheel; "Call truck to door" once a move
--     💪 mover    carries a pair thing ALONE (Mover.Alone × the walk, held up, not dragged), × Mover.Carry on the rest
--                 (never over the walk); no slowdown up stairs and slopes (the others: × Mover.Climb)
--     🛡️ guard    × Guard.Damage weapon damage on the move; Guard.Barricades plank barricades outside; the zombies
--                 outlined through walls within Guard.XRay studs
--   The lobby (plain data by user id, so the tests run it with numbers; the owner is members[1]): one role each while
--   there are no more players than roles (three), doubles beyond that
--     MoveRoles.newLobby(owner, contract, now)     a lobby with its owner in it (and their role)
--     MoveRoles.sync(lobby, ids) -> changed        the members now (the owner first): newcomers get a free role, NOT
--                                                  READY; leavers go; a doubled role (no room for doubles) is fixed
--     MoveRoles.doubles(count)                     may a role be doubled (more players than roles)?
--     MoveRoles.taken(lobby, role, who)            somebody else has it (and it may not be doubled)
--     MoveRoles.freeRole(roles, members, who)      the first role nobody else has (Order[1] when all are taken)
--     MoveRoles.choose(lobby, who, role) -> ok, why   take a role (your READY goes off)
--     MoveRoles.setReady(lobby, who, on) -> ok, why   a member's READY (the owner launches instead)
--     MoveRoles.canLaunch(lobby, who) -> ok, why   the owner; everybody with a role, no double; every member READY
--                                                  (solo: at once: READY is LAUNCH)
--     MoveRoles.waiting(lobby)                     how many members LAUNCH waits for
--   On a move
--     MoveRoles.canSwitch(roles, members, who, role, last, now) -> ok, why, wait   a role switch: a role nobody else
--                                                  has (unless doubles), Switch s after the last one (wait: s to go)
--     MoveRoles.speedFactor(role, mode, base)      × the walk with a thing (mode: MovingRules.mode's; base its factor)
--     MoveRoles.holdMode(role, mode)               how it is held ("pair": a Mover with a pair thing alone, held up)
--     MoveRoles.climbing(rise, run)                is this step up stairs or a slope (Mover.Rise)?
--     MoveRoles.climbFactor(role, mode)            × the walk going up with it (1: a Mover, a thing in one hand)
--     MoveRoles.weaponFactor(role, cause)          × a hit's damage (a Guard's guns and fists; not the car, the others)
--     MoveRoles.truckFactor(driverAtWheel)         × a hit on the truck
--     MoveRoles.canCall(role, used) / canBarricade(role, placed) -> ok, why
--     MoveRoles.wear(hp, zombies, seconds)         a barricade's hp after `zombies` bit it for `seconds`
--   MoveRoles.Chat                                 the quick chat's six lines (an id, an icon, the words)
--   MoveRoles.whyText(why)                         what the player is told
-- 8.8 (the owner: "I don't want roles in the game. Everyone is simply the same."): MoveRoles.on() says whether a move
-- has roles at all: Config.MoveRoles.On, and only in the city (Config.Sandbox.On false: the sandbox never has them).
-- Off, nobody has a role and every rule above answers as it does for nobody's: the lobby gives none and waits for none
-- (newLobby, sync, setReady, canLaunch; choose and canSwitch refuse, "noroles"); the carry, the climb, the hits and the
-- truck are everybody's alike (speedFactor, holdMode, climbFactor, weaponFactor, truckFactor: no Mover's pair alone or
-- stairs, no Guard's damage, no Driver's truck); the call is anybody's, once a move (canCall: whoever is first); no
-- barricade (canBarricade, "noroles"). The quick chat stays (it is no role's).

local Config = require(script.Parent.Config)

local MoveRoles = {}

export type Role = {
	id: string,
	name: string,
	icon: string,
	color: { number }, -- r, g, b
	blurb: string, -- what it does, in a few words
	hint: string, -- the move's HUD: what only it does
}
export type Lobby = {
	owner: number,
	contract: string,
	members: { number }, -- the owner first, then the crew in the order they came
	roles: { [number]: string },
	ready: { [number]: boolean },
	openedAt: number,
}

local function tune(): any
	return (Config :: any).MoveRoles
end

MoveRoles.Order = tune().Order :: { string }

-- 8.8: does a move have roles (Config.MoveRoles.On, the city only)? Read at every call: a test turns the world over.
function MoveRoles.on(): boolean
	local sandbox = (Config :: any).Sandbox
	return tune().On == true and not (sandbox ~= nil and sandbox.On == true)
end

MoveRoles.Roles = {
	driver = {
		id = "driver",
		name = "Driver",
		icon = "🚚",
		color = { 240, 132, 44 },
		blurb = "Drives the truck, loads it fast",
		hint = "No wait at the truck's back · Tab: CALL TRUCK TO DOOR",
	},
	mover = {
		id = "mover",
		name = "Mover",
		icon = "💪",
		color = { 126, 196, 120 },
		blurb = "Lifts the heavy things alone",
		hint = "Lift a sofa alone · no slowdown on stairs",
	},
	guard = {
		id = "guard",
		name = "Guard",
		icon = "🛡️",
		color = { 215, 74, 70 },
		blurb = "Holds the door, fights the dead",
		hint = "Tab: PUT UP A BARRICADE · zombies seen through walls",
	},
} :: { [string]: Role }

-- The quick chat (client/QuickChat.luau: hold T): six lines, by number.
MoveRoles.Chat = {
	{ id = "door", icon = "✋", text = "Hold the door" },
	{ id = "hand", icon = "🙏", text = "Need a hand here" }, -- (the crew hears it; 8.3: Danny is hired and given pieces, never called by it)
	{ id = "zombies", icon = "🧟", text = "Zombies!" },
	{ id = "truck", icon = "🚚", text = "Truck's here" },
	{ id = "pickup", icon = "🏃", text = "I'll come pick you up" },
	{ id = "done", icon = "✅", text = "Done — let's go" },
} :: { { id: string, icon: string, text: string } }

function MoveRoles.get(id: any): Role?
	return if type(id) == "string" then MoveRoles.Roles[id] else nil
end

local function percent(factor: number): string
	return `{math.floor((factor - 1) * 100 + 0.5)}%`
end

-- The role's kit as one line (the lobby's role card), its numbers from Config.MoveRoles.
function MoveRoles.loadout(id: string): string
	local t = tune()
	if id == "driver" then
		return `🔑 Truck keys · ⚡ No wait loading · 🛡 −{math.floor((1 - t.Driver.TruckDamage) * 100 + 0.5)}% truck damage · 📍 Call truck ×1`
	elseif id == "mover" then
		return `🧤 Straps · 🛋 Lifts pairs alone · +{percent(t.Mover.Carry)} carry speed · 🪜 Stairs`
	elseif id == "guard" then
		return `🔫 +{percent(t.Guard.Damage)} damage · 🪵 {t.Guard.Barricades} barricades · 👁 Zombies through walls`
	end
	return ""
end

-- ── The lobby ──────────────────────────────────────────────────────────────

-- May a role be doubled: more players than roles.
function MoveRoles.doubles(count: number): boolean
	return count > #MoveRoles.Order
end

-- Somebody of `members` but `who` has `role` (and it may not be doubled).
local function heldByOther(roles: { [number]: string }, members: { number }, role: string, who: number): boolean
	if MoveRoles.doubles(#members) then
		return false
	end
	for _, id in members do
		if id ~= who and roles[id] == role then
			return true
		end
	end
	return false
end

function MoveRoles.taken(lobby: Lobby, role: string, who: number): boolean
	return heldByOther(lobby.roles, lobby.members, role, who)
end

-- The first role (in Order) nobody of `members` but `who` has; Order[1] when every one is taken.
function MoveRoles.freeRole(roles: { [number]: string }, members: { number }, who: number): string
	for _, role in MoveRoles.Order do
		if not heldByOther(roles, members, role, who) then
			return role
		end
	end
	return MoveRoles.Order[1]
end

function MoveRoles.newLobby(owner: number, contract: string, now: number): Lobby
	local lobby: Lobby = { owner = owner, contract = contract, members = { owner }, roles = {}, ready = {}, openedAt = now }
	if MoveRoles.on() then -- (8.8: no roles: nobody gets one)
		lobby.roles[owner] = MoveRoles.freeRole(lobby.roles, lobby.members, owner)
	end
	return lobby
end

local function isMember(lobby: Lobby, who: number): boolean
	return table.find(lobby.members, who) ~= nil
end

-- The members now (`ids`; the owner first, then whoever stays in the order they came, then the newcomers): a newcomer
-- gets the first free role and is NOT READY, a leaver's role and READY go, and a role doubled when there is no room
-- for doubles (the crew shrank under the roles' count) goes back to the later one's free role. True when anything
-- changed. (8.8 no roles: the members and their READY only; a newcomer is NOT READY all the same.)
function MoveRoles.sync(lobby: Lobby, ids: { number }): boolean
	local list: { number } = { lobby.owner }
	for _, id in lobby.members do
		if id ~= lobby.owner and table.find(ids, id) and not table.find(list, id) then
			table.insert(list, id)
		end
	end
	for _, id in ids do
		if id ~= lobby.owner and not table.find(list, id) then
			table.insert(list, id)
		end
	end
	local changed = #list ~= #lobby.members
	for index, id in list do
		if lobby.members[index] ~= id then
			changed = true
		end
	end
	for id in lobby.roles do
		if not table.find(list, id) then
			lobby.roles[id] = nil
			lobby.ready[id] = nil
			changed = true
		end
	end
	for id in lobby.ready do -- (8.8: without roles a leaver's READY goes by itself)
		if not table.find(list, id) then
			lobby.ready[id] = nil
			changed = true
		end
	end
	lobby.members = list
	if not MoveRoles.on() then
		return changed
	end
	for index, id in list do
		local role = lobby.roles[id]
		local doubled = false
		if role and not MoveRoles.doubles(#list) then
			for earlier = 1, index - 1 do
				if lobby.roles[list[earlier]] == role then
					doubled = true
				end
			end
		end
		if not role or doubled then
			lobby.roles[id] = nil
			lobby.roles[id] = MoveRoles.freeRole(lobby.roles, list, id)
			if id ~= lobby.owner then
				lobby.ready[id] = false
			end
			changed = true
		end
	end
	return changed
end

function MoveRoles.choose(lobby: Lobby, who: number, role: any): (boolean, string?)
	if not MoveRoles.on() then
		return false, "noroles"
	elseif not isMember(lobby, who) then
		return false, "member"
	elseif not MoveRoles.get(role) then
		return false, "role"
	elseif lobby.roles[who] == role then
		return true, nil
	elseif MoveRoles.taken(lobby, role, who) then
		return false, "taken"
	end
	lobby.roles[who] = role
	if who ~= lobby.owner then
		lobby.ready[who] = false
	end
	return true, nil
end

function MoveRoles.setReady(lobby: Lobby, who: number, on: boolean): (boolean, string?)
	if not isMember(lobby, who) then
		return false, "member"
	elseif who == lobby.owner then
		return false, "owner"
	elseif on and MoveRoles.on() and not MoveRoles.get(lobby.roles[who]) then
		return false, "norole"
	end
	lobby.ready[who] = on
	return true, nil
end

function MoveRoles.waiting(lobby: Lobby): number
	local count = 0
	for _, id in lobby.members do
		if id ~= lobby.owner and lobby.ready[id] ~= true then
			count += 1
		end
	end
	return count
end

function MoveRoles.canLaunch(lobby: Lobby, who: number): (boolean, string?)
	if who ~= lobby.owner then
		return false, "owner"
	end
	for _, id in (if MoveRoles.on() then lobby.members else {}) :: { number } do -- (8.8 no roles: READY only)
		local role = lobby.roles[id]
		if not MoveRoles.get(role) then
			return false, "norole"
		elseif heldByOther(lobby.roles, lobby.members, role :: string, id) then
			return false, "taken"
		end
	end
	if MoveRoles.waiting(lobby) > 0 then
		return false, "notready"
	end
	return true, nil
end

-- ── On a move ──────────────────────────────────────────────────────────────

-- A role switch on a move: `last` the time of this player's last one (nil: none yet). Returns ok, why and, for a
-- cooldown, the whole seconds to wait.
function MoveRoles.canSwitch(roles: { [number]: string }, members: { number }, who: number, role: any, last: number?, now: number): (boolean, string?, number?)
	if not MoveRoles.on() then
		return false, "noroles", nil
	elseif not MoveRoles.get(role) then
		return false, "role", nil
	elseif roles[who] == role then
		return false, "same", nil
	elseif heldByOther(roles, members, role, who) then
		return false, "taken", nil
	end
	local gap = tune().Switch
	if last and now - last < gap then
		return false, "cooldown", math.ceil(gap - (now - last))
	end
	return true, nil, nil
end

-- × the walk with a thing for `role`: `mode` MovingRules.mode's ("hand", "both", "pair", "drag"), `base` its factor
-- (MovingRules.speedFactor). A Mover carries a pair thing alone (drag) at Mover.Alone, the rest × Mover.Carry. (8.8
-- no roles: `base` for everybody.)
function MoveRoles.speedFactor(role: string?, mode: string, base: number): number
	if role ~= "mover" or not MoveRoles.on() then
		return base
	end
	local t = tune().Mover
	if mode == "drag" then
		return math.max(base, t.Alone)
	end
	return math.max(base, math.min(1, base * t.Carry))
end

-- How the thing is held: a Mover holds a pair thing alone up in front ("pair"), not dragged low. (8.8 no roles: a pair
-- thing alone is dragged by everybody.)
function MoveRoles.holdMode(role: string?, mode: string): string
	if role == "mover" and mode == "drag" and MoveRoles.on() then
		return "pair"
	end
	return mode
end

-- Is a step of `rise` studs up over `run` studs along a climb (stairs, a slope)?
function MoveRoles.climbing(rise: number, run: number): boolean
	if rise ~= rise or run ~= run or rise <= 0.25 then
		return false
	end
	return rise >= tune().Mover.Rise * math.max(run, 0.5)
end

-- × the walk up a climb with it: Mover.Climb unless it is in one hand or a Mover carries it (8.8 no roles: everybody's
-- Mover.Climb, as it was for anybody but a Mover).
function MoveRoles.climbFactor(role: string?, mode: string): number
	if (role == "mover" and MoveRoles.on()) or mode == "hand" then
		return 1
	end
	return tune().Mover.Climb
end

-- × a hit's damage by a player of `role` (Zombies.damage's cause: a Guard's guns, blasts and fists; never the car's
-- ram, nor the hits nobody made).
local NOT_WEAPON: { [string]: boolean } = { car = true, other = true, buddy = true }

function MoveRoles.weaponFactor(role: string?, cause: string?): number
	if role ~= "guard" or not MoveRoles.on() or (cause and NOT_WEAPON[cause]) then
		return 1
	end
	return tune().Guard.Damage
end

function MoveRoles.truckFactor(driverAtWheel: boolean): number
	return if driverAtWheel and MoveRoles.on() then tune().Driver.TruckDamage else 1
end

-- "Call truck to door": the Driver's, once a move (8.8 no roles: anybody's, once a move: whoever is first).
function MoveRoles.canCall(role: string?, used: boolean): (boolean, string?)
	if role ~= "driver" and MoveRoles.on() then
		return false, "driver"
	elseif used then
		return false, "called"
	end
	return true, nil
end

function MoveRoles.canBarricade(role: string?, placed: number): (boolean, string?)
	if not MoveRoles.on() then
		return false, "noroles"
	elseif role ~= "guard" then
		return false, "guard"
	elseif placed >= tune().Guard.Barricades then
		return false, "nomore"
	end
	return true, nil
end

-- A barricade's hp after `zombies` bit it for `seconds`.
function MoveRoles.wear(hp: number, zombies: number, seconds: number): number
	if zombies <= 0 or seconds <= 0 or seconds ~= seconds then
		return hp
	end
	return math.max(0, hp - zombies * tune().Guard.Bite * seconds)
end

local WHY: { [string]: string } = {
	member = "You are not in this planning.",
	role = "No such role.",
	taken = "A crew mate has that role: pick another.",
	owner = "Only the move's leader launches it.",
	norole = "Pick a role first.",
	notready = "Waiting for the crew: everybody READY first.",
	same = "That is your role already.",
	cooldown = "You switched a moment ago.",
	driver = "Only the Driver calls the truck.",
	called = "The van was called once already this move.",
	guard = "Only the Guard puts up barricades.",
	nomore = "No barricades left.",
	noroles = "Everybody does everything on a move.", -- (8.8: no roles)
}

function MoveRoles.whyText(why: string?): string
	return WHY[why or ""] or "You can't do that now."
end

return MoveRoles
