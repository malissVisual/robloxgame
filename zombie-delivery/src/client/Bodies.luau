--!strict
-- 5.9.2: the per-frame loops over everybody's characters (client/ArmPose.luau, client/BusRide.luau, client/ZipRide.luau,
-- client/CarBoarding.luau) share this, so a frame does no child lookups and builds no new player list:
--   * Bodies.players(): the players in the game, a list kept up to date by PlayerAdded / PlayerRemoving (read it, never
--     change it).
--   * Bodies.of(character): its Humanoid and HumanoidRootPart, looked up once and kept while both are still in the
--     character; a body still loading (or streamed out) is looked up again at most every RETRY seconds.
--   * Bodies.near(character, eye, range): its humanoid and root when the root is within `range` of `eye`, else nil:
--     the early skip of the far ones.
-- The characters that are gone are forgotten now and then (plain tables: Roblox may collect an Instance's Lua handle
-- from a weak table while the Instance still exists).

local Players = game:GetService("Players")

local Bodies = {}

local RETRY = 0.5 -- seconds between new lookups of a body that is missing its humanoid or root
local SWEEP = 5 -- seconds between the clean-ups of the characters that are gone

type Body = { humanoid: Humanoid?, root: BasePart?, retry: number }

local cache: { [Model]: Body } = {}
local list: { Player } = {}
local watching = false
local sweptAt = 0

local function watch()
	if watching then
		return
	end
	watching = true
	list = Players:GetPlayers()
	Players.PlayerAdded:Connect(function(player: Player)
		if not table.find(list, player) then
			table.insert(list, player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local at = table.find(list, player)
		if at then
			table.remove(list, at)
		end
	end)
end

function Bodies.players(): { Player }
	watch()
	return list
end

local function sweep(now: number)
	if now - sweptAt < SWEEP then
		return
	end
	sweptAt = now
	for character in cache do
		if not character.Parent then
			cache[character] = nil
		end
	end
end

function Bodies.of(character: Model): (Humanoid?, BasePart?)
	local body = cache[character]
	if body then
		local humanoid, root = body.humanoid, body.root
		if humanoid and root and humanoid.Parent == character and root.Parent == character then
			return humanoid, root
		end
	end
	local now = os.clock()
	if body and now < body.retry then
		local humanoid, root = body.humanoid, body.root
		return if humanoid and humanoid.Parent == character then humanoid else nil, if root and root.Parent == character then root else nil
	end
	sweep(now)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local found = character:FindFirstChild("HumanoidRootPart")
	local root = if found and found:IsA("BasePart") then found else nil
	cache[character] = { humanoid = humanoid, root = root, retry = now + RETRY }
	return humanoid, root
end

function Bodies.near(character: Model, eye: Vector3, range: number): (Humanoid?, BasePart?)
	local humanoid, root = Bodies.of(character)
	if not root or (root.Position - eye).Magnitude > range then
		return nil, nil
	end
	return humanoid, root
end

return Bodies
