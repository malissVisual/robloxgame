--!strict
-- Crews (Config.Crew): invite another player into your job; members help, ride along or follow, and share the pay.
--
-- One player leads a crew (the owner: the one whose job it is), up to Config.Crew.MaxMembers others join it by
-- invitation. The owner may invite with or without a job running; the crew stays together until a member leaves
-- (LEAVE), the owner breaks it up (LEAVE / DISBAND), the owner's job ends (Jobs calls Crew.disband) or somebody leaves
-- the game. A member who takes a job of their own leaves the crew on their own.
--
-- Everything is checked here on the server; the client (client/CrewPanel.luau) only asks. Jobs (server/Jobs.luau)
-- counts `Crew.members(owner)` as crew exactly like the riders in the owner's car: they may handle the cargo, their
-- kills count, they get XP and their share of the pay (Economy.crewSplit).
--
-- Remotes (shared/Net.luau):
--   CrewInvite   client → server (userId)                  invite that player into my crew
--                server → client (fromUserId, jobName?)    an invitation came (the panel shows it, a toast says so)
--   CrewAnswer   client → server (fromUserId, accepted)    answer an invitation
--                client → server ("leave")                 leave the crew (the owner: break it up)
--                client → server ("kick", userId)          the owner removes a member
--                client → server ("cancel", userId)        the owner takes an invitation back
--   CrewState    client → server ()                        send me my crew state (after loading)
--                server → client (state | nil)             my crew, the invitations and the owner's job (see stateFor)
-- The state goes to everybody involved on every change and every ~2 s while the owner has a job (so the members'
-- GPS follows the owner's next stop).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local PlayerData = require(script.Parent.PlayerData)

local Crew = {}

-- Set by Main: does this player have a job running (server/Jobs.luau Jobs.active)?
Crew.hasJob = function(_player: Player): boolean
	return false
end

-- Set by Main: what the members should see of the owner's job (server/Jobs.luau Jobs.crewStatus): a table with
-- name, step, position (Vector3), stars, endsAt — or nil when the owner has no job.
Crew.statusOf = function(_owner: Player): { [string]: any }?
	return nil
end

type Invite = {
	from: Player, -- the owner (or a player without a crew yet)
	to: Player,
	expiresAt: number, -- workspace:GetServerTimeNow(), so the clients count down to the same moment
	job: string?, -- the owner's job when it was sent
}

local ACTION_GAP = 0.3 -- seconds between two requests of one player (a spam guard)
local DECLINED_WAIT = 20 -- after a "no", the same invitation waits this long before it can come again
local TICK = 0.5 -- the loop: invitations expire, members on their own job leave
local STATUS_EVERY = 2 -- while the owner has a job, the crew gets the job status this often

local crews: { [Player]: { Player } } = {} -- owner → members in the order they joined (no entry = no members)
local leaders: { [Player]: Player } = {} -- member → owner
local invites: { Invite } = {} -- pending invitations (a few at most: a plain list)
local declined: { [Player]: { [Player]: number } } = {} -- invited → inviter → os.clock() of the "no"
local lastAction: { [Player]: number } = {}
local lastRefresh: { [Player]: number } = {}
local hadJob: { [Player]: boolean } = {} -- owners: was a job running at the last tick (a change sends the state)
local dirty: { [Player]: boolean } = {} -- needs a fresh state
local sent: { [Player]: boolean } = {} -- the client holds a (non-nil) state

local notice = Net.get("Notice")
local inviteRemote = Net.get("CrewInvite")
local answerRemote = Net.get("CrewAnswer")
local stateRemote = Net.get("CrewState")

-- ── Helpers ────────────────────────────────────────────────────────────────

local function say(player: Player, text: string)
	if player.Parent then
		notice:FireClient(player, text)
	end
end

local function nameOf(player: Player): string
	return player.DisplayName
end

local function hasJob(player: Player): boolean
	local ok, result = pcall(Crew.hasJob, player)
	return ok and result == true
end

-- The crew this player belongs to (as owner with members, or as member): its owner, else nil.
local function leaderOf(player: Player): Player?
	local owner = leaders[player]
	if owner then
		return owner
	end
	local members = crews[player]
	return if members and #members > 0 then player else nil
end

local function membersOf(owner: Player): { Player }
	return crews[owner] or {}
end

local function mark(player: Player)
	dirty[player] = true
end

-- The owner and every member get a fresh state.
local function markCrew(owner: Player)
	mark(owner)
	for _, member in membersOf(owner) do
		mark(member)
	end
end

local function findInvite(from: Player, to: Player): (Invite?, number?)
	for index, invite in invites do
		if invite.from == from and invite.to == to then
			return invite, index
		end
	end
	return nil, nil
end

local function outgoing(from: Player): number
	local count = 0
	for _, invite in invites do
		if invite.from == from then
			count += 1
		end
	end
	return count
end

-- Removes every invitation the filter picks; both sides get a fresh state.
local function dropInvites(pick: (Invite) -> boolean)
	for index = #invites, 1, -1 do
		local invite = invites[index]
		if pick(invite) then
			table.remove(invites, index)
			mark(invite.from)
			mark(invite.to)
		end
	end
end

-- Toasts to the owner and every member, except `skip`.
local function tellCrew(owner: Player, text: string, skip: Player?)
	if owner ~= skip then
		say(owner, text)
	end
	for _, member in membersOf(owner) do
		if member ~= skip then
			say(member, text)
		end
	end
end

-- What a member sees of the owner's job: a plain copy of the simple values of Crew.statusOf (strings, numbers,
-- booleans, Vector3), so a broken hook or an odd value never breaks the state.
local function statusFor(owner: Player): { [string]: any }?
	local ok, status = pcall(Crew.statusOf, owner)
	if not ok then
		warn(`[Crew] statusOf failed: {status}`)
		return nil
	end
	if type(status) ~= "table" then
		return nil
	end
	local copy: { [string]: any } = {}
	for key, value in status :: { [any]: any } do
		local kind = typeof(value)
		if type(key) == "string" and (kind == "string" or kind == "number" or kind == "boolean" or kind == "Vector3") then
			copy[key] = value
		end
	end
	return copy
end

local function entry(player: Player): { [string]: any }
	local level = PlayerData.level(player)
	return { userId = player.UserId, name = nameOf(player), level = level, rank = Levels.rank(level) }
end

-- The state of one player's crew for their client (nil: no crew and no invitations at all).
--   role       "owner" | "member" | nil (no crew yet)
--   owner      { userId, name, level, rank } (the crew's leader; also set for an owner without members yet)
--   members    { { userId, name, level, rank } }
--   split      { owner, member, members } % of the job's pay for the owner and for each member with `members`
--              members (at least 1: the preview before anybody joined; Economy.crewSplit, nobody loses money, the
--              shares come on top), ownerPay / memberPay in $ when the job's status tells its pay (`pay`)
--   status     the owner's job (Crew.statusOf: name, step, position, stars, endsAt …) or nil
--   invites    incoming: { { userId, name, job?, expiresAt } }
--   pending    outgoing: { { userId, name, expiresAt } }
--   maxMembers, inviteTimeout
local function stateFor(player: Player): { [string]: any }?
	local incoming = {}
	local pending = {}
	for _, invite in invites do
		if invite.to == player then
			table.insert(incoming, { userId = invite.from.UserId, name = nameOf(invite.from), job = invite.job, expiresAt = invite.expiresAt })
		elseif invite.from == player then
			table.insert(pending, { userId = invite.to.UserId, name = nameOf(invite.to), expiresAt = invite.expiresAt })
		end
	end
	local owner = leaderOf(player)
	if not owner and #incoming == 0 and #pending == 0 then
		return nil
	end
	-- An owner without members yet (invitations out) still sees their job and the split they would get.
	local lead = owner or player
	local members = {}
	for _, member in membersOf(lead) do
		table.insert(members, entry(member))
	end
	local count = math.max(#members, 1)
	local ownerShare, memberShare = Economy.crewSplit(100, count)
	local split: { [string]: any } = { owner = ownerShare, member = memberShare, members = count }
	local status = statusFor(lead)
	if status and type(status.pay) == "number" then
		local ownerPay, memberPay = Economy.crewSplit(status.pay, count)
		split.ownerPay = ownerPay
		split.memberPay = memberPay
	end
	return {
		role = if owner == nil then nil elseif owner == player then "owner" else "member",
		owner = entry(lead),
		members = members,
		split = split,
		status = status,
		invites = incoming,
		pending = pending,
		maxMembers = Config.Crew.MaxMembers,
		inviteTimeout = Config.Crew.InviteTimeout,
	}
end

-- Sends the fresh states (and a nil to a client that holds one it no longer has).
local function flush()
	for player in dirty do
		dirty[player] = nil
		if not player.Parent then
			continue
		end
		local state = stateFor(player)
		if state then
			sent[player] = true
			stateRemote:FireClient(player, state)
		elseif sent[player] then
			sent[player] = nil
			stateRemote:FireClient(player, nil)
		end
	end
end

-- A spam guard: false when the player asked too soon again (`last`: one table per kind of request).
local function allowed(player: Player, last: { [Player]: number }?): boolean
	local times = last or lastAction
	local now = os.clock()
	if now - (times[player] or -math.huge) < ACTION_GAP then
		return false
	end
	times[player] = now
	return true
end

-- ── Membership ─────────────────────────────────────────────────────────────

local function join(owner: Player, member: Player)
	local members = crews[owner]
	if not members then
		members = {}
		crews[owner] = members
	end
	table.insert(members, member)
	leaders[member] = owner
	-- The new member's other invitations are void now (in and out), and so are the owner's to other crews.
	dropInvites(function(invite: Invite): boolean
		return invite.to == member or invite.from == member or invite.to == owner
	end)
	local status = statusFor(owner)
	tellCrew(owner, `{nameOf(member)} joined the crew.`, member)
	say(member, if status and type(status.name) == "string"
		then `You joined {nameOf(owner)}'s crew: {status.name}. Follow the purple GPS route.`
		else `You joined {nameOf(owner)}'s crew. You help with their next job and share the pay.`)
	markCrew(owner)
end

-- Takes a member out of their crew (the crew stays while it has members).
local function removeMember(member: Player)
	local owner = leaders[member]
	if not owner then
		return
	end
	leaders[member] = nil
	local members = crews[owner]
	if members then
		local index = table.find(members, member)
		if index then
			table.remove(members, index)
		end
		if #members == 0 then
			crews[owner] = nil
		end
	end
	mark(member)
	markCrew(owner)
end

-- The crew of `owner` breaks up: every member is out, the owner's open invitations are void.
local function breakUp(owner: Player, text: string?)
	local members = crews[owner]
	crews[owner] = nil
	if members then
		for _, member in members do
			if leaders[member] == owner then
				leaders[member] = nil
			end
			mark(member)
			if text then
				say(member, text)
			end
		end
	end
	dropInvites(function(invite: Invite): boolean
		return invite.from == owner
	end)
	mark(owner)
end

-- ── Requests ───────────────────────────────────────────────────────────────

local function invite(from: Player, userId: any)
	if type(userId) ~= "number" or not allowed(from) then
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or not target.Parent then
		say(from, "That player is not here any more.")
		return
	end
	if target == from then
		return
	end
	local myLeader = leaders[from]
	if myLeader then
		say(from, `You are in {nameOf(myLeader)}'s crew: only the leader invites.`)
		return
	end
	local theirLeader = leaderOf(target)
	if theirLeader then
		say(from, if theirLeader == target then `{nameOf(target)} leads a crew of their own.` else `{nameOf(target)} is already in a crew.`)
		return
	end
	if hasJob(target) then
		say(from, `{nameOf(target)} is on a job of their own.`)
		return
	end
	if findInvite(from, target) then
		say(from, `You already invited {nameOf(target)}: waiting for an answer.`)
		return
	end
	local max = Config.Crew.MaxMembers
	if #membersOf(from) >= max then
		say(from, `Your crew is full ({max} members).`)
		return
	end
	if #membersOf(from) + outgoing(from) >= max then
		say(from, `Your crew is full with the invitations you sent ({max} members). Wait for an answer.`)
		return
	end
	local saidNo = declined[target] and declined[target][from]
	if saidNo and os.clock() - saidNo < DECLINED_WAIT then
		say(from, `{nameOf(target)} just said no. Try again in a moment.`)
		return
	end
	local status = statusFor(from)
	local jobName = if status and type(status.name) == "string" then status.name else nil
	table.insert(invites, {
		from = from,
		to = target,
		expiresAt = workspace:GetServerTimeNow() + Config.Crew.InviteTimeout,
		job = jobName,
	})
	inviteRemote:FireClient(target, from.UserId, jobName)
	say(target, `{nameOf(from)} invites you into their crew{if jobName then `: {jobName}` else ""}. Open CREW (K) to answer.`)
	say(from, `Invitation sent to {nameOf(target)}.`)
	mark(from)
	mark(target)
	flush()
end

local function respond(player: Player, fromId: number, accepted: boolean)
	local from = Players:GetPlayerByUserId(fromId)
	local found: Invite?, index: number? = nil, nil
	if from then
		found, index = findInvite(from, player)
	end
	if not from or not found or not index then
		say(player, "That invitation is no longer valid.")
		mark(player)
		flush()
		return
	end
	if not accepted then
		table.remove(invites, index)
		mark(from)
		mark(player)
		local list = declined[player]
		if not list then
			list = {}
			declined[player] = list
		end
		list[from] = os.clock()
		say(from, `{nameOf(player)} said no.`)
		flush()
		return
	end
	-- Your own crew or your own job: the invitation waits (until it runs out) while you sort that out.
	local mine = leaderOf(player)
	if mine == player then
		say(player, "You lead a crew of your own: break it up first (LEAVE).")
		return
	elseif mine then
		say(player, `You are in {nameOf(mine)}'s crew: leave it first.`)
		return
	elseif hasJob(player) then
		say(player, "Finish or cancel your own job first.")
		return
	end
	table.remove(invites, index)
	mark(from)
	mark(player)
	if leaders[from] then
		say(player, `{nameOf(from)} has joined another crew.`)
	elseif #membersOf(from) >= Config.Crew.MaxMembers then
		say(player, `{nameOf(from)}'s crew is full.`)
	else
		join(from, player)
	end
	flush()
end

local function leave(player: Player)
	local owner = leaders[player]
	if owner then
		removeMember(player)
		say(player, `You left {nameOf(owner)}'s crew.`)
		tellCrew(owner, `{nameOf(player)} left the crew.`)
	elseif crews[player] then
		breakUp(player, `{nameOf(player)} broke the crew up.`)
		say(player, "You broke the crew up.")
	else
		say(player, "You are not in a crew.")
		mark(player)
	end
	flush()
end

local function kick(owner: Player, userId: any)
	local target = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if not target or leaders[target] ~= owner then
		return
	end
	removeMember(target)
	say(target, `{nameOf(owner)} took you out of the crew.`)
	tellCrew(owner, `{nameOf(target)} is out of the crew.`)
	flush()
end

local function cancel(from: Player, userId: any)
	local target = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	if not target then
		return
	end
	local found, index = findInvite(from, target)
	if found and index then
		table.remove(invites, index)
		mark(from)
		mark(target)
		flush()
	end
end

local function answer(player: Player, first: any, second: any)
	if not allowed(player) then
		return
	end
	if type(first) == "number" then
		respond(player, first, second == true)
	elseif first == "leave" then
		leave(player)
	elseif first == "kick" then
		kick(player, second)
	elseif first == "cancel" then
		cancel(player, second)
	end
end

-- ── The loop ───────────────────────────────────────────────────────────────

local sinceStatus = 0

local function step()
	-- Invitations nobody answered.
	local now = workspace:GetServerTimeNow()
	for index = #invites, 1, -1 do
		local pending = invites[index]
		if now >= pending.expiresAt then
			table.remove(invites, index)
			say(pending.from, `{nameOf(pending.to)} did not answer the invitation.`)
			mark(pending.from)
			mark(pending.to)
		end
	end
	-- A member who took a job of their own works on that one now.
	for member, owner in leaders do
		if hasJob(member) then
			removeMember(member)
			say(member, `You took a job of your own and left {nameOf(owner)}'s crew.`)
			tellCrew(owner, `{nameOf(member)} took a job of their own and left the crew.`)
		end
	end
	-- The owner's job started or ended: the crew sees it at once; while it runs, every STATUS_EVERY seconds.
	sinceStatus += TICK
	local periodic = sinceStatus >= STATUS_EVERY
	if periodic then
		sinceStatus = 0
	end
	for owner in crews do
		local running = hasJob(owner)
		if running ~= (hadJob[owner] == true) or (running and periodic) then
			markCrew(owner)
		end
		if running then
			hadJob[owner] = true
		else
			hadJob[owner] = nil
		end
	end
	-- An owner without members but with invitations out: their job shows in the invitations they sent.
	for owner in hadJob do
		if not crews[owner] then
			hadJob[owner] = nil
		end
	end
	flush()
end

-- ── API ────────────────────────────────────────────────────────────────────

-- The players who joined `owner`'s job by invitation (not the owner). A copy: safe to keep while the crew changes.
function Crew.members(owner: Player): { Player }
	local list = {}
	for _, member in membersOf(owner) do
		if member.Parent then
			table.insert(list, member)
		end
	end
	return list
end

-- Whose job does this player work on (nil = nobody's / their own)?
function Crew.ownerOf(player: Player): Player?
	return leaders[player]
end

-- The job of `owner` ended: the crew breaks up (Jobs calls this). Safe for a player without a crew.
function Crew.disband(owner: Player)
	if crews[owner] then
		breakUp(owner, `{nameOf(owner)}'s job is over. The crew broke up.`)
	else
		-- No members: the invitations that came with the job are void too.
		dropInvites(function(invite: Invite): boolean
			return invite.from == owner
		end)
	end
	hadJob[owner] = nil
	flush()
end

function Crew.start()
	inviteRemote.OnServerEvent:Connect(invite)
	answerRemote.OnServerEvent:Connect(answer)
	-- A client that loaded asks for its state (an invitation may already be waiting).
	stateRemote.OnServerEvent:Connect(function(player: Player)
		if allowed(player, lastRefresh) then
			mark(player)
			flush()
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		if crews[player] then
			breakUp(player, `{nameOf(player)} left the game. The crew broke up.`)
		elseif leaders[player] then
			local owner = leaders[player]
			removeMember(player)
			if owner then
				tellCrew(owner, `{nameOf(player)} left the game.`)
			end
		end
		dropInvites(function(pending: Invite): boolean
			return pending.from == player or pending.to == player
		end)
		declined[player] = nil
		for _, list in declined do
			list[player] = nil
		end
		lastAction[player] = nil
		lastRefresh[player] = nil
		hadJob[player] = nil
		dirty[player] = nil
		sent[player] = nil
		flush()
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(function()
				step()
			end)
			if not ok then
				warn(`[Crew] {err}`)
			end
		end
	end)
end

return Crew
