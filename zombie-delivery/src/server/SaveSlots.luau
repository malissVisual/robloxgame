--!strict
-- 10.1, the save slots on the server (Config.SaveSlots; the rules: shared/SaveSlotRules.luau; the start screen:
-- client/Menu.luau and client/CharacterCreator.luau). A player picks a slot before their save loads: CONTINUE a save
-- (its courier changed or not), NEW GAME in an empty slot, START OVER a used one (a fresh game written over it). Until
-- then PlayerData.load waits (PlayerData.chooseSlot, set here): nothing of the save is read or locked, and the game
-- shows the start screen. The courier made goes on the body as soon as the save is in (server/CourierAvatar.luau
-- setLook: their own avatar for base "own" or a save without a courier).
--
--   SaveSlots.start()            the Slots remote and PlayerData.chooseSlot (before PlayerData.start: SandboxBoot)
--   SaveSlots.fallback(player)   a PLAY with no pick (an old client, a start screen that failed): the slot saved last,
--                                CONTINUE (SandboxBoot's Play)
--
-- The Slots remote (one RemoteEvent, a table each way; shared/Net.luau, Config.Robust.Limits.Slots):
--   client → { kind = "list" }                 the slots' summaries (each slot read with GetAsync at most every
--                                              Config.SaveSlots.Read s; sooner: the ones read last)
--            { kind = "play", slot, look? }    CONTINUE (look: the courier changed: CharacterLooks.clean, its name
--                                              filtered by Roblox's TextService; a name it cannot filter is dropped)
--            { kind = "new", slot, look }      a fresh game in the slot (NEW GAME, START OVER)
--   server → { kind = "list", slots = { Summary }, latest, picked, offline }   (offline: the slots could not be read:
--                                              Studio without API access, the DataStore down; NEW GAME still plays)
--            { kind = "loading", slot }        the pick taken, the save loads
--            { kind = "ready", slot }          the save is in: the client fades in and sends PLAY
--            { kind = "refused", text }        a pick that cannot be taken (already picked, a bad slot)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local CharacterLooks = require(Shared.CharacterLooks)
local SaveSlotRules = require(Shared.SaveSlotRules)

local PlayerData = require(script.Parent.PlayerData)
local CourierAvatar = require(script.Parent.CourierAvatar)

local SaveSlots = {}

local remote: RemoteEvent = nil :: any
local picks: { [Player]: PlayerData.Choice } = {}
local ready: { [Player]: boolean } = {}
local read: { [Player]: { at: number, slots: { SaveSlotRules.Summary }, offline: boolean } } = {}
local reading: { [Player]: boolean } = {}

-- Every slot of this player, read at once (each GetAsync in its own thread); offline when one could not be read.
local function readSlots(player: Player): ({ SaveSlotRules.Summary }, boolean)
	local out: { SaveSlotRules.Summary } = {}
	local offline = false
	local left = Config.SaveSlots.Count
	for slot = 1, Config.SaveSlots.Count do
		task.spawn(function()
			local ok, saved = PlayerData.peek(player, slot)
			out[slot] = SaveSlotRules.summary(slot, if ok then saved else nil)
			offline = offline or not ok
			left -= 1
		end)
	end
	local waited = 0
	while left > 0 and waited < 30 and player.Parent do
		waited += task.wait(0.05)
	end
	for slot = 1, Config.SaveSlots.Count do
		out[slot] = out[slot] or SaveSlotRules.summary(slot, nil)
	end
	return out, offline
end

local function send(player: Player, message: { [string]: any })
	if player.Parent then
		remote:FireClient(player, message)
	end
end

local function list(player: Player)
	local last = read[player]
	local summaries: { SaveSlotRules.Summary }, offline = if last then last.slots else {}, if last then last.offline else false
	if not last or os.clock() - last.at >= Config.SaveSlots.Read then
		if reading[player] then
			return -- (the read in flight answers)
		end
		reading[player] = true
		summaries, offline = readSlots(player)
		reading[player] = nil
		read[player] = { at = os.clock(), slots = summaries, offline = offline }
	end
	local pick = picks[player]
	send(player, {
		kind = "list",
		slots = summaries,
		latest = SaveSlotRules.latest(summaries),
		picked = if pick then pick.slot else nil,
		offline = offline,
	})
end

-- The courier's name through Roblox's filter (as everybody may see it); nil when it cannot be filtered.
local function filtered(player: Player, name: string?): string?
	if not name then
		return nil
	end
	local ok, text = pcall(function(): string
		local result = TextService:FilterStringAsync(name, player.UserId)
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(text) ~= "string" then
		warn(`[SaveSlots] {player.Name}'s courier name could not be filtered: {text}`)
		return nil
	end
	return CharacterLooks.name(text)
end

local function pick(player: Player, message: { [string]: any })
	local slot = SaveSlotRules.slot(message.slot)
	if not slot then
		send(player, { kind = "refused", text = "That save slot does not exist." })
		return
	elseif picks[player] then
		send(player, { kind = "refused", text = "Your save is already loading." })
		return
	end
	local fresh = message.kind == "new"
	local look: CharacterLooks.Look? = nil
	if fresh or type(message.look) == "table" then
		local clean = CharacterLooks.clean(message.look)
		clean.name = filtered(player, clean.name)
		look = clean
	end
	if picks[player] or not player.Parent then
		return -- (the filter yields: a second pick or a leave may have come meanwhile)
	end
	picks[player] = { slot = slot, fresh = fresh, character = look }
	send(player, { kind = "loading", slot = slot })
end

-- PlayerData.chooseSlot: waits for the pick (nil: they left first).
local function choose(player: Player): PlayerData.Choice?
	while player.Parent and not picks[player] do
		task.wait(0.1)
	end
	return if player.Parent then picks[player] else nil
end

-- The save is in (PlayerData's first Changed with a profile after the pick): the courier on the body, READY.
local function loaded(player: Player)
	if ready[player] or not picks[player] then
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	ready[player] = true
	local ok, err = pcall(function()
		CourierAvatar.setLook(player, profile.character)
	end)
	if not ok then
		warn(`[SaveSlots] {player.Name}'s courier did not go on: {err}`)
	end
	read[player] = nil -- (the next list reads the slots again: this one is played now)
	send(player, { kind = "ready", slot = PlayerData.slot(player) })
end

function SaveSlots.fallback(player: Player)
	if picks[player] or not Config.SaveSlots.On then
		return
	end
	local last = read[player]
	local slot = if last then SaveSlotRules.latest(last.slots) else nil
	picks[player] = { slot = slot or 1, fresh = false, character = nil }
	send(player, { kind = "loading", slot = slot or 1 })
end

function SaveSlots.start()
	remote = Net.get("Slots")
	if not Config.SaveSlots.On then
		return
	end
	PlayerData.chooseSlot = choose
	remote.OnServerEvent:Connect(function(player: Player, message: any)
		if type(message) ~= "table" or not Net.limit(player, "Slots", Config.Robust.Limits.Slots) then
			return
		end
		if message.kind == "list" then
			list(player)
		elseif message.kind == "play" or message.kind == "new" then
			pick(player, message)
		end
	end)
	PlayerData.Changed:Connect(loaded)
	Players.PlayerRemoving:Connect(function(player: Player)
		picks[player], ready[player], read[player], reading[player] = nil, nil, nil, nil
	end)
end

return SaveSlots
