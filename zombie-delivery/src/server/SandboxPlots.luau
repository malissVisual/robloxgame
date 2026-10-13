--!strict
-- 8.0 SANDBOX: who owns which plot (shared/SandboxMap.luau's Plots, design/sandbox/KONTRAKT.md). A player who joins
-- gets the lowest free plot (the player's attribute Plot = its id) and keeps it until they leave; the warehouse, the
-- van spot, the spawn and the contracts board on it are theirs. More players than plots: none (Plot stays nil; the
-- place's max players is Config.Sandbox.MaxPlayers) until a plot is freed: 8.0.1, a player who leaves hands theirs to
-- the first player here without one (Players:GetPlayers()' order: who came first).
--
--   SandboxPlots.start()            claims for the players here and every one who joins, frees on leaving (and
--                                   gives the freed plot to a player waiting for one)
--   SandboxPlots.of(player)         the player's plot (SandboxMap.Plot) or nil
--   SandboxPlots.owner(id)          the player on plot `id` or nil
--   SandboxPlots.onChanged(fn)      fn(plotId, player?) when a plot is claimed (player) or freed (nil)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SandboxMap = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SandboxMap"))

local SandboxPlots = {}

local owners: { [number]: Player? } = {}
local listeners: { (number, Player?) -> () } = {}
local leaving: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- (gone or going: never handed a plot)

local function fire(id: number, player: Player?)
	for _, fn in listeners do
		task.spawn(fn, id, player)
	end
end

local function claim(player: Player)
	if player:GetAttribute("Plot") ~= nil then
		return
	end
	for _, plot in SandboxMap.Plots do
		if owners[plot.id] == nil then
			owners[plot.id] = player
			player:SetAttribute("Plot", plot.id)
			fire(plot.id, player)
			return
		end
	end
end

local function release(player: Player)
	leaving[player] = true
	local freed = false
	for id, owner in owners do
		if owner == player then
			owners[id] = nil
			freed = true
			fire(id, nil)
		end
	end
	if not freed then
		return
	end
	-- the freed plot to the first player here without one (whoever is leaving may still be in the list while they go)
	for _, waiting in Players:GetPlayers() do
		if not leaving[waiting] and waiting:GetAttribute("Plot") == nil then
			claim(waiting)
			return
		end
	end
end

function SandboxPlots.of(player: Player): SandboxMap.Plot?
	for id, owner in owners do
		if owner == player then
			return SandboxMap.Plots[id]
		end
	end
	return nil
end

function SandboxPlots.owner(id: number): Player?
	return owners[id]
end

function SandboxPlots.onChanged(fn: (number, Player?) -> ())
	table.insert(listeners, fn)
end

function SandboxPlots.start()
	Players.PlayerAdded:Connect(claim)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		claim(player)
	end
end

return SandboxPlots
