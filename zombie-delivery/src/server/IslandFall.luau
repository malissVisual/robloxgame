--!strict
-- 10.6 THE FLOATING ISLANDS, the fall catch (Config.Islands.Fall; the owner's islands float in the sky, nothing under
-- them): whoever falls off an island is put back on its top. Every Fall.Every s it looks at every body there is: every
-- player's character and the helpers in workspace.Npcs (MoveHelper: Danny, the crew); a piece being carried is welded to
-- its carrier (server/Moving.luau weldTo) and goes with them.
--   * A body over an island's top (its root within a few studs under it, or over it) is on that island: the island it
--     came from from now on; standing there (its humanoid on a floor), Fall.Inset studs inside the island's walls at
--     least (the lobby's bounds, a run zone's edge), that is where it stood last (a good spot to come back to).
--   * A body Fall.Below studs under its island's bottom (its top less its depth: the island it came from; never on one:
--     the one under it, else the lobby's) is caught: put back on that island's top where it stood last, Fall.Up studs
--     over it, still (its fall's speed gone), looking at the island's home; with no good spot of its own, at the
--     island's home (SandboxMap.Islands' home: the lobby's spawn, a run zone's arrive, facing the door). A player first
--     goes black (the Moving remote's "fade", as a door's trip: client/Fade.luau), is moved while it is black, what
--     they carried goes down where they land (server/Moving.luau runDrop: a run's piece), the black lifts and a notice
--     says what happened (Fall.Notice); a helper is moved at once. A caught body is left alone Fall.Hold s (it falls on
--     a moment before its move).
--   * Somebody in a house's inside (server/HouseInterior.luau's slots: far off, high over every island) is over no
--     island and far over every bottom: left alone; falling out of it, they come back to the island they came from.
-- workspace.FallenPartsDestroyHeight (Config.Islands.Destroy: server/SandboxWorld.luau sets it) is far under every
-- island: a body is caught long before Roblox would remove it.
--   IslandFall.start()                     its loop (server/SandboxBoot.luau, sandbox mode)
--   IslandFall.step(now)                   one look at every body (the loop's; the checks')
--   IslandFall.fallen(island, y) -> boolean    under the island's bottom by Fall.Below (caught)
--   IslandFall.inside(island, x, z, inset) -> boolean   inside the island's walls by `inset`
--   IslandFall.spot(island, at?) -> CFrame    where a body caught off `island` goes (at: where it stood last)
--   IslandFall.markOf(key) -> Mark?        what it knows of a body (its island, where it stood last, when caught)
-- Its hooks (tests/islandfall_runtime_test.luau sets its own): IslandFall.bodies() -> { Body } (the bodies looked at),
-- IslandFall.fade(player, way, seconds, arrival?), IslandFall.after(seconds, fn), IslandFall.drop(player) (what they
-- carry goes down), IslandFall.say(player, text).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SandboxMap = require(Shared.SandboxMap)

local IslandFall = {}

local F = Config.Islands.Fall
local ON = 4 -- studs under an island's top a body's root may be and still be over it (its feet on the grass: it is there)
local OVER = 60 -- … and over it at most (a jump, a hill of hay: still that island's)

export type Body = { key: any, root: BasePart, model: Instance, humanoid: Humanoid?, player: Player?, kind: string }
export type Mark = { island: string?, at: Vector3?, caught: number? }

local marks: { [any]: Mark } = setmetatable({}, { __mode = "k" }) :: any
local started = false

-- ── The rules ──────────────────────────────────────────────────────────────

function IslandFall.fallen(island: SandboxMap.Island, y: number): boolean
	return y < island.top - island.depth - F.Below
end

function IslandFall.inside(island: SandboxMap.Island, x: number, z: number, inset: number): boolean
	local w = island.walls
	return x >= w.x0 + inset and x <= w.x1 - inset and z >= w.z0 + inset and z <= w.z1 - inset
end

function IslandFall.spot(island: SandboxMap.Island, at: Vector3?): CFrame
	local home = island.home
	local homeAt = Vector3.new(home.x, home.y + F.Up, home.z)
	if at and IslandFall.inside(island, at.X, at.Z, F.Inset) then
		local put = at + Vector3.new(0, F.Up, 0)
		local toward = Vector3.new(homeAt.X, put.Y, homeAt.Z)
		if (toward - put).Magnitude > 1 then
			return CFrame.lookAt(put, toward)
		end
		return CFrame.new(put) * CFrame.Angles(0, math.rad(home.yaw), 0)
	end
	return CFrame.new(homeAt) * CFrame.Angles(0, math.rad(home.yaw), 0)
end

function IslandFall.markOf(key: any): Mark?
	return marks[key]
end

-- ── The hooks ──────────────────────────────────────────────────────────────

-- Every player's character and every helper in workspace.Npcs (MoveHelper), each with its root.
function IslandFall.bodies(): { Body }
	local out: { Body } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			table.insert(out, { key = player, root = root, model = character, humanoid = character:FindFirstChildOfClass("Humanoid"), player = player, kind = "player" })
		end
	end
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		for _, model in npcs:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("MoveHelper") ~= nil then
				local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
				if root and root:IsA("BasePart") then
					table.insert(out, { key = model, root = root, model = model, humanoid = model:FindFirstChildOfClass("Humanoid"), player = nil, kind = "helper" })
				end
			end
		end
	end
	return out
end

function IslandFall.fade(player: Player, way: string, seconds: number, arrival: { [string]: any }?)
	if player.Parent then
		Net.get("Moving"):FireClient(player, "fade", way, seconds, arrival)
	end
end

function IslandFall.after(seconds: number, fn: () -> ())
	task.delay(seconds, fn)
end

function IslandFall.drop(player: Player)
	local moving = script.Parent:FindFirstChild("Moving")
	if moving and moving:IsA("ModuleScript") then
		pcall(function()
			(require(moving) :: any).runDrop(player, "fell", 0)
		end)
	end
end

function IslandFall.say(player: Player, text: string)
	if player.Parent then
		Net.get("Notice"):FireClient(player, text)
	end
end

-- ── The look ───────────────────────────────────────────────────────────────

local function standing(body: Body): boolean
	local humanoid = body.humanoid
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

-- Puts a body at `frame`, still.
local function put(body: Body, frame: CFrame)
	pcall(function()
		(body.model :: any):PivotTo(frame)
		body.root.AssemblyLinearVelocity = Vector3.zero
		body.root.AssemblyAngularVelocity = Vector3.zero
	end)
end

local function catch(body: Body, island: SandboxMap.Island, mark: Mark, now: number)
	mark.caught = now
	local frame = IslandFall.spot(island, mark.at)
	local player = body.player
	if not player then
		put(body, frame)
		return
	end
	IslandFall.fade(player, "out", F.Fade.Out)
	IslandFall.after(F.Fade.Out + 0.05, function()
		if body.model.Parent == nil then
			return
		end
		put(body, frame)
		IslandFall.drop(player) -- (what they carried goes down where they land)
		IslandFall.fade(player, "in", F.Fade.In, { at = frame.Position, look = frame.LookVector, dark = 0.1, wait = 2, near = 8 })
		IslandFall.say(player, F.Notice)
	end)
end

function IslandFall.step(now: number)
	for _, body in IslandFall.bodies() do
		local p = body.root.Position
		local mark = marks[body.key]
		if not mark then
			mark = {}
			marks[body.key] = mark
		end
		local m = mark :: Mark
		local under = SandboxMap.islandAt(p.X, p.Z)
		if under and p.Y >= under.top - ON and p.Y <= under.top + OVER then
			m.island = under.id -- (on it now: the island it comes from)
			if standing(body) and IslandFall.inside(under, p.X, p.Z, F.Inset) then
				m.at = p
			elseif m.at and SandboxMap.islandAt(m.at.X, m.at.Z) ~= under then
				m.at = nil -- (a good spot of another island's: none here yet)
			end
		end
		local island = SandboxMap.island(m.island) or under or SandboxMap.Islands[1]
		if IslandFall.fallen(island, p.Y) and (m.caught == nil or now - (m.caught :: number) >= F.Hold) then
			catch(body, island, m, now)
		end
	end
end

function IslandFall.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			task.wait(F.Every)
			local ok, err = pcall(function()
				IslandFall.step(os.clock())
			end)
			if not ok then
				warn(`[IslandFall] {err}`)
			end
		end
	end)
end

return IslandFall
