--!strict
-- 3.7: the map you discover. Every Config.Explore.Every seconds it uncovers the cells (shared/Explore.luau) within
-- Config.Explore.Radius of each player with a character, on foot or in a car; a fast car uncovers the way between two
-- checks too (a jump farther than Config.Explore.Teleport is a teleport: not the way between). The uncovered cells are
-- the player's profile.explored (decoded once on joining into a set kept here, encoded again whenever it grows: one
-- short string, at most once a check, saved with the profile).
--
-- The places: a landmark (Map.Landmarks: the shops, the employers, the far places, the towers, the estate; the same
-- the maps show) is known once its cell is uncovered, so the save needs nothing more. When one becomes known the
-- client hears it once (the "NEW LOCATION DISCOVERED" banner). Coming within Config.Explore.PlaceRadius of a landmark
-- uncovers its cell whatever the radius. (The explorer challenges still count the Map.Places you reach:
-- profile.visited, server/Challenges.luau.)
--
-- A new player (an empty profile.explored: a new save or one from before 3.7) starts with the depot's area uncovered
-- (Config.Explore.StartHalf), so nobody starts lost.
--
-- Remote "Explore", server → client:
--   ("state", cells, places)   on joining: the save string (shared/Explore.decode reads it) and the known landmarks' ids
--   ("cells", list)            cell indexes newly uncovered
--   ("place", id, name)        a landmark just discovered (once ever)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Grid = require(Shared.Explore)
local PlayerData = require(script.Parent.PlayerData)

local Explore = {}

local CFG = Config.Explore

type State = {
	set: Grid.Set,
	last: Vector3?, -- where the player was at the last check
	character: Model?, -- whose position `last` is: a new character (a respawn) is not a drive from the death spot
}

local states: { [Player]: State } = {}
local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	local r = remote
	if not r then
		r = Net.get("Explore")
		remote = r
	end
	return r :: RemoteEvent
end

-- Uncovers the cells in `list`; the new ones go into `fresh`.
local function uncoverList(state: State, list: { number }, fresh: { number })
	local set = state.set
	for _, index in list do
		if not set[index] then
			set[index] = true
			table.insert(fresh, index)
		end
	end
end

-- Tells the client what was uncovered (and which landmarks that made known) and keeps the save string up to date.
local function commit(player: Player, fresh: { number })
	if #fresh == 0 then
		return
	end
	local state = states[player]
	local profile = PlayerData.get(player)
	if not state or not profile then
		return
	end
	profile.explored = Grid.encode(state.set)
	local r = getRemote()
	r:FireClient(player, "cells", fresh)
	for _, index in fresh do
		local landmarks = Grid.landmarksIn(index)
		if landmarks then
			for _, landmark in landmarks do
				r:FireClient(player, "place", landmark.id, landmark.name)
			end
		end
	end
end

-- The profile is in: its cells, the depot's area for a new player, and the state to the client.
local function onLoaded(player: Player)
	local profile = PlayerData.get(player)
	if not profile or states[player] then
		return
	end
	local set = Grid.decode(profile.explored)
	local state: State = { set = set, last = nil }
	if next(set) == nil then
		uncoverList(state, Grid.cellsInSquare(0, 0, CFG.StartHalf), {})
	end
	states[player] = state
	-- Encoded again every time: an older grid's string (another cell size) is now on this grid.
	profile.explored = Grid.encode(set)
	getRemote():FireClient(player, "state", profile.explored, Grid.known(set))
end

-- Where the player is: their character (seated, the character rides in the car).
local function positionOf(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local p = root.Position
	if p.X ~= p.X or p.Z ~= p.Z then
		return nil
	end
	return p
end

local function check(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local position = positionOf(player)
	if not position then
		state.last = nil
		return
	end
	if state.character ~= player.Character then
		state.character = player.Character
		state.last = nil
	end
	local fresh: { number } = {}
	-- The way since the last check (a fast car), in steps of the radius; the point itself last.
	local last = state.last
	if last then
		local way = Vector3.new(position.X - last.X, 0, position.Z - last.Z)
		local length = way.Magnitude
		if length > CFG.Radius and length <= CFG.Teleport then
			local steps = math.ceil(length / CFG.Radius)
			for k = 1, steps - 1 do
				local at = last + way * (k / steps)
				uncoverList(state, Grid.cellsAround(at.X, at.Z, CFG.Radius), fresh)
			end
		end
	end
	state.last = position
	uncoverList(state, Grid.cellsAround(position.X, position.Z, CFG.Radius), fresh)
	-- Right by a landmark: its cell, whatever the radius is tuned to.
	local near2 = CFG.PlaceRadius * CFG.PlaceRadius
	for _, landmark in Map.Landmarks do
		local dx, dz = landmark.x - position.X, landmark.z - position.Z
		if dx * dx + dz * dz <= near2 then
			local index = Grid.landmarkCell(landmark.id)
			if index and not state.set[index] then
				uncoverList(state, { index }, fresh)
			end
		end
	end
	commit(player, fresh)
end

-- Uncovers the cells within `radius` of a point for a player (for other systems: a tutorial, a story beat). Returns
-- whether anything new was uncovered.
function Explore.uncover(player: Player, x: number, z: number, radius: number): boolean
	local state = states[player]
	if not state or type(x) ~= "number" or type(z) ~= "number" or type(radius) ~= "number" then
		return false
	end
	local fresh: { number } = {}
	uncoverList(state, Grid.cellsAround(x, z, math.clamp(radius, 0, 2000)), fresh)
	commit(player, fresh)
	return #fresh > 0
end

-- Does the player know this landmark (Map.Landmarks id)?
function Explore.knows(player: Player, landmarkId: string): boolean
	local state = states[player]
	return state ~= nil and Grid.knows(state.set, landmarkId)
end

function Explore.start()
	getRemote() -- (server → client only: nothing to listen to)
	PlayerData.Changed:Connect(function(player: Player)
		if not states[player] and PlayerData.get(player) then
			onLoaded(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) then
			task.spawn(onLoaded, player)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CFG.Every)
			for player in states do
				if not player.Parent then
					states[player] = nil
					continue
				end
				local ok, err = pcall(function()
					check(player)
				end)
				if not ok then
					warn(`[Explore] check failed: {err}`)
				end
			end
		end
	end)
end

return Explore
