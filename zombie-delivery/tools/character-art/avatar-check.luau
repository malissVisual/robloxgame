-- 5.9.2: the server only installs the template (no tracks, no loop); the template's Animate LocalScript is the
-- locomotion controller on the owning client. Both run against service/event recorders; no physics or animation
-- asset decoding.
-- 6.9: the template is Roblox's classic R15 (Players:CreateHumanoidModelFromDescription; the native block body stands
-- in for it here) and each player's own look goes on it (GetHumanoidDescriptionFromUserId → ApplyDescriptionAsync) with the
-- torso, the arms, the legs, the proportions and the animations reset, the head, the face and the clothes kept.
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
		p.ApplyDescriptionAsync = function(self, description) self.applied = description end
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
M.task = {
	defer = function(callback) table.insert(pending, callback) end,
	spawn = function(callback, ...) callback(...) end, -- (at once: the recorder has no scheduler)
	wait = function() return 0.1 end,
}
local animate = M.Instance.new("LocalScript")
animate.Name = "Animate"
animate:SetAttribute("Ours", true)
M.script = { Parent = { CharacterArt = { Animate = animate } } }
-- 6.9: Roblox's classic R15, made from a description (the block body: the classic R15's proportions and joints), with
-- Roblox's own Animate in it; a player's own avatar (player 1 has one, the others' do not load).
local Geometry = require("./Geometry")
local Rig = require("./Rig")
local AvatarLook = require("./AvatarLook")
local Motion = require("./CourierMotion")
local made = {}
function players:CreateHumanoidModelFromDescription(description, rigType)
	assert(rigType == "R15", "an R15 body")
	table.insert(made, description)
	local body = Rig.build(Geometry.spec("walker"))
	local stock = M.Instance.new("LocalScript")
	stock.Name = "Animate"
	stock.Parent = body
	return body
end
local own = M.Instance.new("HumanoidDescription")
for field, value in { Head = 111, Face = 222, Torso = 333, LeftArm = 334, RightArm = 335, LeftLeg = 336, RightLeg = 337,
	HeightScale = 1.05, WidthScale = 0.9, DepthScale = 0.95, HeadScale = 0.96, BodyTypeScale = 0.5, ProportionScale = 1,
	IdleAnimation = 446, WalkAnimation = 444, RunAnimation = 445, Shirt = 555, Pants = 556, GraphicTShirt = 557,
	HairAccessory = "777", MoodAnimation = 666 } do
	own[field] = value
end
for name, id in { Torso = 333, Head = 111 } do
	local part = M.Instance.new("BodyPartDescription")
	part.BodyPart, part.AssetId = { Name = name }, id
	part.Parent = own
end
function players:GetHumanoidDescriptionFromUserId(id)
	if id == 1 then return own:Clone() end
	error("no avatar for " .. tostring(id))
end
local Avatar = require("./Avatar")
local function player()
	local p = M.Instance.new("Player")
	p.Parent = players
	p.CharacterAdded, p.CharacterRemoving = signal(), signal()
	p.CharacterAppearanceId = #list + 1
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
assert(template:FindFirstChild("Animate"):IsA("LocalScript") and template:FindFirstChild("Animate"):GetAttribute("Ours"), "the game's Animate")
local animates = 0
for _, child in template:GetChildren() do if child.Name == "Animate" then animates += 1 end end
assert(animates == 1, "Roblox's own Animate is gone")
assert(#made == 1, "one template body")
for field, value in AvatarLook.Body do assert(made[1][field] == value, "the template is the classic body: " .. field) end
assert(math.abs(made[1].TorsoColor.R - 40 / 255) < 1e-6 and math.abs(made[1].HeadColor.R - 218 / 255) < 1e-6, "in the workwear")
assert(template:FindFirstChildOfClass("Humanoid").WalkSpeed == 14)
assert(template:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator"), "the template brings the Animator")
local a, b = player(), player()
a:LoadCharacterAsync()
b:LoadCharacterAsync()
assert(#allTracks == 0, "the server loads no tracks")
assert(a.loads == 1 and b.loads == 1 and #pending == 0, "a courier body is not replaced")
-- 6.9: player 1's own look on the classic body; player 2's did not load (the workwear stays)
local applied = a.Character:FindFirstChildOfClass("Humanoid").applied
assert(applied and applied ~= own, "a player's own look goes on their courier body (a copy)")
assert(applied.Head == 111 and applied.Face == 222 and applied.Shirt == 555 and applied.Pants == 556 and applied.GraphicTShirt == 557
	and applied.HairAccessory == "777" and applied.MoodAnimation == 666, "the head, the face, the clothes and the hair stay the player's")
for field, value in AvatarLook.Body do assert(applied[field] == value, "the body is the classic one: " .. field) end
for _, part in applied:GetChildren() do
	assert(part.AssetId == (if part.BodyPart.Name == "Head" then 111 else 0), "the body parts' descriptions too, the head kept")
end
assert(b.Character:FindFirstChildOfClass("Humanoid").applied == nil, "no look of their own: the workwear stays")
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
local leg = Motion.leg(a.Character) :: number
assert(leg and math.abs(leg - 2) < 0.1, "the classic R15's leg, hip to sole: about 2")
assert(math.abs(playing(1).rate - 28 / 24 / (leg / 2)) < 1e-6, "the pace matches the speed (6.7: and the legs; 6.8 review: the leg measured, hip to sole)")
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
print("ALL CHECKS PASSED: server template only (Roblox's classic R15, the game's Animate), the player's own look on it (head, face, clothes kept; body, proportions, animations reset), client locomotion (common animations, actual velocity, sitting/death), respawn, initial replacement, cleanup")
