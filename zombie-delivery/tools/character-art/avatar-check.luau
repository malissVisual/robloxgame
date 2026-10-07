-- 5.9.2: the server only installs the template (no tracks, no loop); the template's Animate LocalScript is the
-- locomotion controller on the owning client. Both run against service/event recorders; no physics or animation
-- asset decoding.
local M = require("./mock")
local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			local connection = { connected = true }
			function connection:Disconnect() self.connected = false end
			table.insert(callbacks, { callback = callback, connection = connection })
			return connection
		end,
		Fire = function(_, ...)
			for _, entry in table.clone(callbacks) do
				if entry.connection.connected then entry.callback(...) end
			end
		end,
		Count = function()
			local n = 0
			for _, entry in callbacks do if entry.connection.connected then n += 1 end end
			return n
		end,
	}
end
local players = M.Instance.new("Folder")
players.PlayerAdded, players.PlayerRemoving = signal(), signal()
local list = {}
function players:GetPlayers() return table.clone(list) end
local starter = M.Instance.new("Folder")
starter.CharacterWalkSpeed = 14
local run = { Heartbeat = signal() }
local pending = {}
local allTracks = {}
local oldNew = M.Instance.new
M.Instance.new = function(class)
	local p = oldNew(class)
	if class == "Model" then p.Destroying = signal() end
	if class == "Humanoid" then
		p.BuildRigFromAttachments = function(self) self.built = true end
		p.Health, p.Sit, p.state = 100, false, "Running"
		p.GetState = function(self) return { Name = self.state } end
	elseif class == "Animator" then
		p.LoadAnimation = function(_, animation)
			local track = { id = animation.AnimationId, playing = false, destroyed = false }
			function track:Play(_, _, rate) self.playing, self.rate = true, rate end
			function track:Stop() self.playing = false end
			function track:AdjustSpeed(rate) self.rate = rate end
			function track:Destroy() self.destroyed = true end
			table.insert(allTracks, track)
			return track
		end
	end
	return p
end
-- The server may not ask for RunService any more (no animation loop there).
M.game = { GetService = function(_, name)
	if name == "Players" then return players end
	if name == "StarterPlayer" then return starter end
	if name == "ReplicatedStorage" then return {} end
	error("the server asked for " .. name)
end }
M.task = { defer = function(callback) table.insert(pending, callback) end }
local animate = M.Instance.new("LocalScript")
animate.Name = "Animate"
M.script = { Parent = { CharacterArt = { Animate = animate } } }
local Avatar = require("./Avatar")
local function player()
	local p = M.Instance.new("Player")
	p.Parent = players
	p.CharacterAdded, p.CharacterRemoving = signal(), signal()
	function p:LoadCharacterAsync()
		self.loads = (self.loads or 0) + 1
		if self.Character then self.CharacterRemoving:Fire(self.Character) end
		local body = starter:FindFirstChild("StarterCharacter"):Clone()
		body.Destroying = signal()
		body.PrimaryPart.AssemblyLinearVelocity = M.Vector3.zero
		body.Parent = M.workspace
		self.Character = body
		self.CharacterAdded:Fire(body)
	end
	table.insert(list, p)
	players.PlayerAdded:Fire(p)
	return p
end
Avatar.start()
Avatar.start() -- idempotent: one template and one player watcher
local template = starter:FindFirstChild("StarterCharacter")
assert(template and template:GetAttribute("CharacterArt") == "courier" and not starter.LoadCharacterAppearance)
assert(template:FindFirstChild("Animate"):IsA("LocalScript"))
assert(template:FindFirstChildOfClass("Humanoid").WalkSpeed == 14)
assert(template:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator"), "the template brings the Animator")
local a, b = player(), player()
a:LoadCharacterAsync()
b:LoadCharacterAsync()
assert(#allTracks == 0, "the server loads no tracks")
assert(a.loads == 1 and b.loads == 1 and #pending == 0, "a courier body is not replaced")
-- Joining with an already spawned personal avatar causes exactly one replacement.
local c = player()
local oldBody = M.Instance.new("Model")
oldBody.Parent = M.workspace
c.Character = oldBody
c.CharacterAdded:Fire(oldBody)
c.CharacterAdded:Fire(oldBody)
assert(#pending == 1)
table.remove(pending, 1)()
assert(c.loads == 1 and c.Character:GetAttribute("CharacterArt") == "courier" and #pending == 0)
players.PlayerRemoving:Fire(c)
c.CharacterAdded:Fire(oldBody)
assert(#pending == 0, "a player who left is no longer watched")

-- The client controller: Animate.client.luau run on the owning client, in its character.
local Animate = require("./Animate")
local clientGame = { GetService = function(_, name)
	if name == "RunService" then return run end
	if name == "ReplicatedStorage" then return {} end
	error("the controller asked for " .. name)
end }
local function waitable(obj)
	obj.WaitForChild = function(self, name) return assert(self:FindFirstChild(name), name) end
end
local function control(body)
	waitable(body)
	waitable(body:FindFirstChildOfClass("Humanoid"))
	Animate({ game = clientGame, script = { Parent = body } })
end
control(a.Character)
control(b.Character)
assert(#allTracks == 18, "nine common tracks per body")
run.Heartbeat:Fire(1 / 60)
local function playing(from)
	for i = from, from + 8 do if allTracks[i].playing then return allTracks[i] end end
	return nil
end
assert(playing(1).id == "rbxassetid://507766388" and playing(10).id == playing(1).id, "idle at rest")
a.Character.PrimaryPart.AssemblyLinearVelocity = M.Vector3.new(0, 0, 28)
run.Heartbeat:Fire(1 / 60)
assert(playing(1).id == "rbxassetid://507767714", "a run from the actual velocity")
assert(math.abs(playing(1).rate - 28 / 24 / (2.2 / 2)) < 1e-6, "the pace matches the speed (6.7: and the legs)")
assert(playing(10).id == "rbxassetid://507766388", "each body its own")
a.Character:FindFirstChildOfClass("Humanoid").Sit = true
run.Heartbeat:Fire(1 / 60)
assert(playing(1).id == "rbxassetid://2506281703", "the sit track in a seat")
a.Character:FindFirstChildOfClass("Humanoid").Health = 0
run.Heartbeat:Fire(1 / 60)
assert(playing(1) == nil, "nothing plays on a dead body")
-- A respawn: the old body's controller lets its tracks go, the new body brings its own.
local before = run.Heartbeat:Count()
a.Character.Destroying:Fire()
for i = 1, 9 do assert(allTracks[i].destroyed) end
assert(run.Heartbeat:Count() == before - 1, "the old body's loop is disconnected")
b.Character.Parent = nil
run.Heartbeat:Fire(1 / 60)
for i = 10, 18 do assert(allTracks[i].destroyed) end
assert(run.Heartbeat:Count() == before - 2, "a body that left stops too")
a:LoadCharacterAsync()
control(a.Character)
assert(#allTracks == 27 and a.loads == 2)
run.Heartbeat:Fire(1 / 60)
assert(playing(19).id == "rbxassetid://507766388")
print("ALL CHECKS PASSED: server template only, client locomotion (common animations, actual velocity, sitting/death), respawn, initial replacement, cleanup")
