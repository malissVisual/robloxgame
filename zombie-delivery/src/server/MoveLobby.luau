--!strict
-- 7.0 planning (the owner's rework, design/rework/NAVRH.md §2: "the planning: a lobby like GTA's heists"): the move's
-- planning lobby and the crew's quick chat, on the server. shared/MoveRoles.luau has the rules (tests/
-- moveroles_test.luau); client/MoveLobbyUi.luau shows the lobby, client/QuickChat.luau the chat; server/Moving.luau
-- opens a lobby (the contract card's START) and starts the move on its LAUNCH (MoveLobby.onLaunch).
--
--   * The lobby: the owner and their crew (server/Crew.luau Crew.members, live: whoever joins the crew is in it, whoever
--     leaves the crew is out; INVITE on the lobby opens the crew panel). Each member has a role (a newcomer the first
--     free one; one each while there are no more players than roles) and READY; the owner LAUNCHes once everybody is
--     READY (solo: at once) and the move starts with those roles. CANCEL (the owner) calls it off; it closes when its
--     owner leaves the game or joins another crew, after Config.MoveRoles.Lobby.Timeout, or on LAUNCH. While you are
--     in one your player attribute MoveLobby is its owner's UserId (client/QuickChat.luau reads it).
--   * The quick chat (the remote's "chat", 1 … 6: MoveRoles.Chat; Config.Robust.Limits.QuickChat): the line goes to
--     the sender's crew on a move (MoveLobby.moveCrew: Moving's) or in a lobby, never to anybody else;
--     MoveLobby.onQuickChat hears it too (an AI helper may answer it).
--   Everything is checked here; the remote (MoveLobby) is rate limited (Config.Robust.Limits.MoveLobby).
--   MoveLobby.open(owner, card) -> string?   opens the owner's lobby for that contract card (or shows it again)
--   MoveLobby.close(owner, why?)              closes it; everybody in it hears `why`
--   MoveLobby.of(player)                      the lobby a player is in (their own, or their crew's owner's), or nil
--   MoveLobby.step()                          one tick (the loop's; tests/moving_runtime_test.luau calls it)
--   MoveLobby.start()                         the remote, the loop, the players leaving

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MoveRoles = require(Shared.MoveRoles)
local Net = require(Shared.Net)
local Crew = require(script.Parent.Crew)

local T = Config.MoveRoles
local MoveLobby = {}

-- Set by server/Moving.luau: start the move with these roles (nil: started; else why not).
MoveLobby.onLaunch = function(_owner: Player, _contract: string, _roles: { [number]: string }): string?
	return "Moving is not ready in this place yet."
end
-- Set by server/Moving.luau: why the owner can't start a move now (nil: they can).
MoveLobby.canStart = function(_owner: Player): string?
	return nil
end
-- Set by server/Moving.luau: everybody on this player's move (nil: no move).
MoveLobby.moveCrew = function(_player: Player): { Player }?
	return nil
end
-- Set by whoever listens (an AI helper): a quick chat line was said (its number in MoveRoles.Chat).
MoveLobby.onQuickChat = nil :: ((player: Player, index: number) -> ())?

export type Entry = {
	lobby: MoveRoles.Lobby,
	owner: Player,
	card: { [string]: any }, -- the contract card's summary (server/Moving.luau openCard's)
	players: { Player }, -- in the lobby now (the owner first)
	dirty: boolean,
}

local lobbies: { [Player]: Entry } = {} -- by owner
local remote = Net.get("MoveLobby")
local notice = Net.get("Notice")
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function say(player: Player, text: string)
	if player.Parent then
		notice:FireClient(player, text)
	end
end

local function setAttribute(player: Player, value: number?)
	if player.Parent and player:GetAttribute("MoveLobby") ~= value then
		player:SetAttribute("MoveLobby", value)
	end
end

-- The owner and their crew now.
local function crewOf(owner: Player): { Player }
	local list: { Player } = { owner }
	for _, member in Crew.members(owner) do
		if member ~= owner then
			table.insert(list, member)
		end
	end
	return list
end

function MoveLobby.of(player: Player): Entry?
	local own = lobbies[player]
	if own then
		return own
	end
	local owner = Crew.ownerOf(player)
	local theirs = if owner then lobbies[owner] else nil
	if theirs and table.find(theirs.players, player) then
		return theirs
	end
	return nil
end

-- What one player sees of the lobby (client/MoveLobbyUi.luau).
local function viewFor(entry: Entry, player: Player): { [string]: any }
	local lobby = entry.lobby
	local members = {}
	for _, member in entry.players do
		local id = member.UserId
		table.insert(members, {
			userId = id,
			name = member.DisplayName,
			role = lobby.roles[id],
			ready = id == lobby.owner or lobby.ready[id] == true,
			owner = id == lobby.owner,
			you = member == player,
		})
	end
	local ok, why = MoveRoles.canLaunch(lobby, lobby.owner)
	return {
		owner = lobby.owner,
		ownerName = entry.owner.DisplayName,
		mine = player == entry.owner,
		card = entry.card,
		members = members,
		role = lobby.roles[player.UserId],
		ready = lobby.ready[player.UserId] == true,
		canLaunch = ok,
		why = if ok then nil else MoveRoles.whyText(why),
		waiting = MoveRoles.waiting(lobby),
		doubles = MoveRoles.doubles(#lobby.members),
		maxCrew = Config.Crew.MaxMembers + 1,
		closesAt = lobby.openedAt + T.Lobby.Timeout,
	}
end

local function send(entry: Entry)
	entry.dirty = false
	for _, player in entry.players do
		if player.Parent then
			remote:FireClient(player, "lobby", viewFor(entry, player))
		end
	end
end

-- Who is in it now (the crew changes): newcomers get a role and hear of it, leavers lose the lobby.
local function sync(entry: Entry)
	local players = crewOf(entry.owner)
	local ids: { number } = {}
	for _, player in players do
		table.insert(ids, player.UserId)
	end
	if MoveRoles.sync(entry.lobby, ids) then
		entry.dirty = true
	end
	for _, old in entry.players do
		if not table.find(players, old) then
			setAttribute(old, nil)
			if old.Parent then
				remote:FireClient(old, "lobby", nil)
			end
			entry.dirty = true
		end
	end
	for _, new in players do
		if not table.find(entry.players, new) then
			setAttribute(new, entry.owner.UserId)
			if new ~= entry.owner then
				say(new, `📋 {entry.owner.DisplayName} is planning a move: {entry.card.name}. Pick your role and get READY.`)
			end
			entry.dirty = true
		end
	end
	entry.players = players
end

function MoveLobby.close(owner: Player, why: string?)
	local entry = lobbies[owner]
	if not entry then
		return
	end
	lobbies[owner] = nil
	for _, player in entry.players do
		setAttribute(player, nil)
		if player.Parent then
			remote:FireClient(player, "lobby", nil)
			if why then
				say(player, why)
			end
		end
	end
end

-- Opens the owner's lobby for this contract card (server/Moving.luau checked START), or shows the open one again.
function MoveLobby.open(owner: Player, card: { [string]: any }): string?
	local leader = Crew.ownerOf(owner)
	if leader then
		return `You are in {leader.DisplayName}'s crew: they plan the move (or leave the crew).`
	end
	local entry: Entry? = lobbies[owner]
	if entry and entry.lobby.contract ~= tostring(card.id) then
		MoveLobby.close(owner, nil)
		entry = nil
	end
	if not entry then
		local made: Entry = {
			lobby = MoveRoles.newLobby(owner.UserId, tostring(card.id), now()),
			owner = owner,
			card = card,
			players = {},
			dirty = true,
		}
		lobbies[owner] = made
		entry = made
	end
	local open = entry :: Entry
	sync(open)
	send(open)
	return nil
end

-- LAUNCH: everybody READY, the owner free to start; the move starts with the lobby's roles and the lobby closes.
local function launch(entry: Entry)
	local owner = entry.owner
	local ok, why = MoveRoles.canLaunch(entry.lobby, owner.UserId)
	if not ok then
		say(owner, MoveRoles.whyText(why))
		send(entry)
		return
	end
	local busy = MoveLobby.canStart(owner)
	if busy then
		say(owner, busy)
		return
	end
	local err = MoveLobby.onLaunch(owner, entry.lobby.contract, table.clone(entry.lobby.roles))
	if err then
		say(owner, err)
		return
	end
	lobbies[owner] = nil
	for _, player in entry.players do
		setAttribute(player, nil)
		if player.Parent then
			remote:FireClient(player, "lobby", nil)
		end
	end
end

-- A quick chat line (its number in MoveRoles.Chat) to the sender's crew on a move or in a lobby.
local function chat(player: Player, index: any)
	if type(index) ~= "number" or index % 1 ~= 0 or not MoveRoles.Chat[index] then
		return
	end
	local crew = MoveLobby.moveCrew(player)
	if not crew then
		local entry = MoveLobby.of(player)
		crew = if entry then entry.players else nil
	end
	if not crew or not table.find(crew, player) then
		return
	end
	local line = { from = player.UserId, name = player.DisplayName, index = index }
	for _, member in crew do
		if member.Parent then
			remote:FireClient(member, "chat", line)
		end
	end
	local hook = MoveLobby.onQuickChat
	if hook then
		local ok, err = pcall(function()
			hook(player, index)
		end)
		if not ok then
			warn(`[MoveLobby] onQuickChat: {err}`)
		end
	end
end

local function onRequest(player: Player, action: any, arg: any)
	if action == "chat" then
		if Net.limit(player, "QuickChat", Config.Robust.Limits.QuickChat) then
			chat(player, arg)
		end
		return
	end
	if not Net.limit(player, "MoveLobby", Config.Robust.Limits.MoveLobby) then
		return
	end
	local entry = MoveLobby.of(player)
	if action == "state" then
		if entry then
			sync(entry)
		end
		remote:FireClient(player, "lobby", if entry and table.find(entry.players, player) then viewFor(entry, player) else nil)
		return
	end
	if not entry then
		return
	end
	sync(entry)
	local lobby = entry.lobby
	local id = player.UserId
	if action == "role" then
		local ok, why = MoveRoles.choose(lobby, id, arg)
		if not ok then
			say(player, MoveRoles.whyText(why))
		end
		entry.dirty = true
	elseif action == "ready" then
		local ok, why = MoveRoles.setReady(lobby, id, arg == true)
		if not ok then
			say(player, MoveRoles.whyText(why))
		end
		entry.dirty = true
	elseif action == "launch" then
		if player == entry.owner then
			launch(entry)
		end
		return
	elseif action == "cancel" then
		if player == entry.owner then
			MoveLobby.close(player, `📋 {player.DisplayName} called the planning off.`)
		end
		return
	end
	if entry.dirty then
		send(entry)
	end
end

-- One tick: the owners still here and free, the crews joining and leaving, the time.
function MoveLobby.step()
	local t = now()
	for owner, entry in lobbies do
		if not owner.Parent then
			MoveLobby.close(owner, `📋 The planning was called off: {owner.DisplayName} left.`)
		elseif Crew.ownerOf(owner) then
			MoveLobby.close(owner, "📋 The planning was called off: its leader joined another crew.")
		elseif t - entry.lobby.openedAt > T.Lobby.Timeout then
			MoveLobby.close(owner, "📋 The planning ran out of time: take the contract again at the depot's board.")
		else
			sync(entry)
			if entry.dirty then
				send(entry)
			end
		end
	end
end

function MoveLobby.start()
	if started then
		return
	end
	started = true
	remote.OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player: Player)
		if lobbies[player] then
			MoveLobby.close(player, `📋 The planning was called off: {player.DisplayName} left the game.`)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(T.Lobby.Tick)
			local ok, err = pcall(function()
				MoveLobby.step()
			end)
			if not ok then
				warn(`[MoveLobby] {err}`)
			end
		end
	end)
end

return MoveLobby
