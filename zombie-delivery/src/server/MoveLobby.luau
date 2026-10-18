--!strict
-- The quick chat of a run's party, on the server (the module keeps the name of the 7.0 planning lobby it held: gone
-- since 9.7, the lobby's portals start the runs, server/Runs.luau). shared/MoveRoles.luau has the lines
-- (MoveRoles.Chat), client/QuickChat.luau shows the chat.
--
--   * The quick chat (the remote's "chat", 1 … 6: MoveRoles.Chat; Config.Robust.Limits.QuickChat): the line goes to
--     the sender's party on a run (MoveLobby.moveCrew: server/Moving.luau's), never to anybody else. (10.6: the
--     remote's "state", the planning's, is answered no more: no client asks.)
--   MoveLobby.start()   the remote

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MoveRoles = require(Shared.MoveRoles)
local Net = require(Shared.Net)

local MoveLobby = {}

-- Set by server/Moving.luau: everybody on this player's run (nil: not on one).
MoveLobby.moveCrew = function(_player: Player): { Player }?
	return nil
end

local remote = Net.get("MoveLobby")
local started = false

-- A quick chat line (its number in MoveRoles.Chat) to the sender's party on a run.
local function chat(player: Player, index: any)
	if type(index) ~= "number" or index % 1 ~= 0 or not MoveRoles.Chat[index] then
		return
	end
	local crew = MoveLobby.moveCrew(player)
	if not crew or not table.find(crew, player) then
		return
	end
	local line = { from = player.UserId, name = player.DisplayName, index = index }
	for _, member in crew do
		if member.Parent then
			remote:FireClient(member, "chat", line)
		end
	end
end

local function onRequest(player: Player, action: any, arg: any)
	if action == "chat" then
		if Net.limit(player, "QuickChat", Config.Robust.Limits.QuickChat) then
			chat(player, arg)
		end
	end
end

function MoveLobby.start()
	if started then
		return
	end
	started = true
	remote.OnServerEvent:Connect(onRequest)
end

return MoveLobby
