-- 8.5 Danny's clipboard, orders mode (the owner: "I'll hold a paper in my hand, like a notepad … a kind of ordering mode
-- and I click on what he should carry"): the real server/Clipboard.luau (ClipboardServer.luau, its art by the real
-- server/ModelArt/Builder.luau) beside the real server/Moving.luau and server/MoveHelper.luau on tests/runtime/
-- MovingRuntime.luau's fakes (tests/run_tests.py builds them). The recorder's SetAttribute fires the instance's
-- AttributeChanged here, as Roblox does (server/Clipboard.luau listens to it; Moving and MoveHelper listen to none), and
-- a seat's SeatPart change is fired by the test (Roblox's property signal).
--   * Out only while a helper works for your move: refused with no move (a notice: your helper comes with you into a
--     run); 10.1 out from the move's start (free, no hire): a model "Clipboard" in your character (a board, a sheet of paper, a clip, lines) welded to the
--     right hand, massless, never colliding, touched or hit by rays; the character attribute ClipboardHeld.
--   * The assign remote (Danny's list): refused while the clipboard is away (a notice, nothing on his list, a piece of
--     his list never taken back), allowed with it out; the rate limit kept (MoveHelperAssign) and its own
--     (Config.Robust.Limits.Clipboard). 9.0: with it out the server's piece prompts stay as they are (each client hides
--     its own player's: client/DannyOrders.luau; E sends this same assign).
--   * Away by itself: a pick (you can't carry with it: the pick puts it away), a seat, death, a weapon up, the move's
--     end; refused while you carry or sit.
--   * A crew mate may hold it too (Danny with the whole crew); garbage requests; leaving.
local E = require("./MovingRuntime")
local M = E.Mock

-- (Roblox: an attribute set fires the instance's AttributeChanged; the recorder's does not by itself)
local O = getmetatable(M.Instance.new("Model"))
local setAttribute = O.SetAttribute
O.SetAttribute = function(self: any, key: string, value: any)
	local before = self.attributes[key]
	setAttribute(self, key, value)
	local changed = self.props.AttributeChanged
	if before ~= value and changed then
		changed:Fire(key)
	end
end

local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Clipboard = require("./ClipboardServer")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Moving
local H = Config.MoveHelper
local V3 = M.Vector3.new
local workspace = M.workspace

local HOUSE = "lone_house" -- (10.5: a run on the lone house, the van at its curb)
local door, facing, outside = E.doorOf(SandboxMap.house(HOUSE))
local lobby = V3(SandboxMap.Lobby.spawn.x, 3, SandboxMap.Lobby.spawn.z)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0)
end
MoveHelper.useMover({
	move = function(body: any, to: any, speed: number, dt: number)
		local root = body.root
		local here = root.Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		local length = way.Magnitude
		if length > 1e-6 then
			local step = math.min(length, speed * dt)
			root.CFrame = M.CFrame.new(here.X + way.X / length * step, here.Y, here.Z + way.Z / length * step)
		end
		body.walking = true
	end,
	halt = function(body: any)
		body.walking = false
	end,
})

-- Ann (the move's owner) and Bob (a crew mate later), each with a right hand (the courier's: 0.22 × 0.36 × 0.4)
local depot = lobby -- (10.5: the lobby; the runs on the lone house)
local ann = E.player(71, "Ann", depot)
local bob = E.player(72, "Bob", depot + V3(4, 0, 0))
local function giveHand(player: any): any
	local hand = M.Instance.new("Part")
	hand.Name = "RightHand"
	hand.Size = V3(0.22, 0.36, 0.4)
	hand.CFrame = E.rootOf(player).CFrame * M.CFrame.new(1, -0.6, 0)
	hand.Parent = player.Character
	return hand
end
local annHand = giveHand(ann)
giveHand(bob)
Moving.useArt(E.art)
Moving.parkVan = E.parkVan
Moving.start()
Clipboard.start()

local remote = E.Net.get("Clipboard")
local function ask(player: any, out: any)
	remote.OnServerEvent:Fire(player, out)
end
local function held(player: any): boolean
	return player.Character:GetAttribute("ClipboardHeld") == true and Clipboard.out(player) and player.Character:FindFirstChild("Clipboard") ~= nil
end
local function away(player: any): boolean
	return player.Character:GetAttribute("ClipboardHeld") == nil and not Clipboard.out(player) and player.Character:FindFirstChild("Clipboard") == nil
end
local function told(player: any, text: string, from: number): boolean
	for index = from + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) then
			return true
		end
	end
	return false
end
local function promptIn(model: any, action: string): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and string.find(tostring(d.ActionText), action, 1, true) == 1 then
			return d
		end
	end
	return nil
end
local function itemModel(spot: number): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
local function run(seconds: number)
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		MoveHelper.step(0.1)
		if index % 2 == 0 then
			Moving.step()
		end
	end
	Moving.step()
end
local function humanoidOf(player: any): any
	return player.Character:FindFirstChildOfClass("Humanoid")
end

-- ── Only while Danny works for your move ────────────────────────────────────

local noticeAt = #E.messages
ask(ann, true)
check("no move, no Danny: the clipboard stays away, a notice says why (your helper comes into a run)", away(ann) and told(ann, "your helper", noticeAt), E.lastNotice(ann))
local started = E.startRun(ann, HOUSE)
local truck = E.cars[ann]
truck.model:SetAttribute("BackOpen", true)
Moving.step()
local danny = MoveHelper.find(ann)
check("10.1 a run: Danny comes, free, Ann's from the start", started == nil and danny ~= nil and danny.hirer == ann
	and ann:GetAttribute("MoveHelper") == "hired", started)
ask(ann, true)
check("…the clipboard out at once (ClipboardHeld, a model \"Clipboard\" in her character)", held(ann))
local model = ann.Character:FindFirstChild("Clipboard")
local names: { [string]: boolean } = {}
local welded, light, ghost = true, true, true
for _, part in model:GetChildren() do
	if part:IsA("BasePart") then
		names[part.Name] = true
		local weld = part:FindFirstChild("ArtWeld")
		welded = welded and weld ~= nil and weld.Part0 == annHand and weld.Part1 == part
		light = light and part.Massless == true and part.Anchored == false
		ghost = ghost and part.CanCollide == false and part.CanTouch == false and part.CanQuery == false
	end
end
check("…a board, a sheet of paper, a clip, lines", names.Board == true and names.Paper == true and names.Clip == true and names.Line1 == true, model and #model:GetChildren())
check("…every part welded to her right hand (ArtWeld), massless, never colliding, touched or hit by rays", welded and light and ghost)
local board = model:FindFirstChild("Board")
check("…a clipboard's size in the courier's hand (about 0.6 × 0.9 studs, thin)", board ~= nil and math.max(board.Size.X, board.Size.Y, board.Size.Z) < 1
	and math.max(board.Size.X, board.Size.Y, board.Size.Z) > 0.75 and math.min(board.Size.X, board.Size.Y, board.Size.Z) < 0.06)
ask(ann, true)
check("…asked again: still the one clipboard", held(ann) and #(function()
	local list = {}
	for _, child in ann.Character:GetChildren() do
		if child.Name == "Clipboard" then
			table.insert(list, child)
		end
	end
	return list
end)() == 1)

-- ── Orders: the assign remote with and without it ───────────────────────────

local site = workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{HOUSE}`)
E.place(ann, outside)
promptIn(site, "Enter house").Triggered:Fire(ann)
local lamp = itemModel(1)
E.place(ann, lamp.PrimaryPart.Position + V3(3, 0, 0))
ask(ann, false)
check("put away (the remote's false): ClipboardHeld gone, the model gone", away(ann))
noticeAt = #E.messages
E.request(ann, "helper", "assign", lamp)
check("8.5 a click on the Lamp with the clipboard away: refused (\"📋 Take out your clipboard (Q)\"), not on his list", #danny.queue == 0
	and told(ann, "📋 Take out your clipboard (Q) to give Danny pieces.", noticeAt) and lamp:GetAttribute("DannyQueue") == nil, E.lastNotice(ann))
ask(ann, true)
local lampPick = promptIn(lamp, "Pick up") or promptIn(lamp, "Lift")
check("9.0 the clipboard out changes none of the pieces' prompts on the server (Ann's client hides hers on her screen only, client/DannyOrders.luau: a crew mate still sees Pick up)",
	held(ann) and lampPick ~= nil and lampPick.Enabled == true and lampPick.MaxActivationDistance == Config.Moving.Reach.Item)
noticeAt = #E.messages
E.request(ann, "helper", "assign", lamp)
check("…with it out: on his list (\"Danny will take the Lamp.\")", held(ann) and #danny.queue == 1 and danny.queue[1] == 1 and told(ann, "Danny will take the Lamp.", noticeAt))
ask(ann, false)
E.request(ann, "helper", "assign", lamp)
check("…a click on it again with the clipboard away: still his (never a stray take-back)", #danny.queue == 1)
ask(ann, true)
E.request(ann, "helper", "assign", lamp)
check("…with it out: taken back", #danny.queue == 0)
local limits: { string } = {}
local realLimit = E.Net.limit
E.Net.limit = function(_player: any, name: string, _rate: number): boolean
	table.insert(limits, name)
	return name ~= "MoveHelperAssign"
end
E.request(ann, "helper", "assign", lamp)
check("…the rate limit kept (MoveHelperAssign): over it, nothing", #danny.queue == 0 and table.find(limits, "MoveHelperAssign") ~= nil)
E.Net.limit = function(_player: any, name: string, _rate: number): boolean
	table.insert(limits, name)
	return name ~= "Clipboard"
end
ask(ann, false)
check("the Clipboard remote's own rate limit (Config.Robust.Limits.Clipboard): over it, nothing changes", held(ann) and table.find(limits, "Clipboard") ~= nil)
E.Net.limit = realLimit
ask(ann, "yes")
ask(ann, nil)
ask(ann, 1)
check("garbage (not a boolean): nothing changes", held(ann))

-- ── Away by itself ──────────────────────────────────────────────────────────

-- a pick: you can't carry with it out, the pick puts it away first
E.place(ann, lamp.PrimaryPart.Position + V3(2, 0, 0))
promptIn(lamp, "Pick up").Triggered:Fire(ann)
check("8.5 carry: Ann picks up the Lamp with it out: the clipboard goes, the Lamp in her hands", away(ann) and ann.Character:GetAttribute("Carrying") ~= nil
	and ann.Character:GetAttribute("MoveCarry") == 1, ann.Character:GetAttribute("Carrying"))
noticeAt = #E.messages
ask(ann, true)
check("…asked while she carries: refused (\"Put down what you carry first (G)\")", away(ann) and told(ann, "Put down what you carry first (G)", noticeAt), E.lastNotice(ann))
E.Net.get("PutDown").OnServerEvent:Fire(ann)
ask(ann, true)
check("…put down: out again", ann.Character:GetAttribute("Carrying") == nil and held(ann))
-- a seat
local humanoid = humanoidOf(ann)
truck.passengers[1]:Sit(humanoid)
humanoid:GetPropertyChangedSignal("SeatPart"):Fire()
check("8.5 seat: Ann sits in the van: the clipboard goes", humanoid.SeatPart ~= nil and away(ann))
noticeAt = #E.messages
ask(ann, true)
check("…asked while she sits: refused (\"Get out first\")", away(ann) and told(ann, "Get out first", noticeAt), E.lastNotice(ann))
truck.passengers[1]:FindFirstChild("SeatWeld"):Destroy()
humanoid.Sit = false
humanoid:GetPropertyChangedSignal("SeatPart"):Fire()
ask(ann, true)
check("…out of the seat: out again", humanoid.SeatPart == nil and held(ann))
-- a weapon up (the run's bat: Aiming)
ann.Character:SetAttribute("Aiming", true)
check("a gun up (Aiming): the clipboard goes", away(ann))
ann.Character:SetAttribute("Aiming", nil)
-- death
ask(ann, true)
check("(out again)", held(ann))
humanoid.Health = 0
humanoid.Died:Fire()
check("8.5 death: the clipboard goes at once", away(ann))
noticeAt = #E.messages
ask(ann, true)
check("…dead: refused, no notice", away(ann) and #E.messages == noticeAt)
humanoid.Health = 100
-- the move's end
ask(ann, true)
check("(alive again: out)", held(ann))
Moving.endRun(ann)
run(0.5)
check("8.5 the move's end: Danny gone, the clipboard with him", MoveHelper.find(ann) == nil and ann:GetAttribute("MoveHelper") == nil and away(ann))
noticeAt = #E.messages
ask(ann, true)
check("…no move: refused (your helper comes into a run)", away(ann) and told(ann, "your helper", noticeAt))

-- ── A crew mate: the clipboard theirs too; off the move, theirs goes ─────────

E.startRun(ann, HOUSE)
truck = E.cars[ann]
truck.model:SetAttribute("BackOpen", true)
Moving.step()
E.crew[ann] = { bob }
Moving.step()
danny = MoveHelper.find(ann)
check("a second move, Bob in Ann's crew: Danny with both (10.1 free: Ann's, he stays when the crew grows)", danny ~= nil and danny.hirer == ann
	and ann:GetAttribute("MoveHelper") == "hired" and bob:GetAttribute("MoveHelper") == "hired")
ask(ann, true)
ask(bob, true)
check("Ann and Bob may both hold the clipboard (any of the crew)", held(ann) and held(bob))
E.crew[ann] = {}
Moving.step()
check("8.5 Bob leaves the move: his clipboard goes (off the move: no helper of his); Ann's stays", bob:GetAttribute("MoveHelper") == nil and away(bob)
	and ann:GetAttribute("MoveHelper") == "hired" and held(ann), ann:GetAttribute("MoveHelper"))

-- ── Leaving ─────────────────────────────────────────────────────────────────

ask(ann, true)
check("Ann's clipboard out", danny.hirer == ann and held(ann))
local character = ann.Character
E.leave(ann)
check("Ann leaves the game: it goes with her (nothing kept for her)", not Clipboard.out(ann) and character:GetAttribute("ClipboardHeld") == nil and character:FindFirstChild("Clipboard") == nil)
run(0.2)
E.leave(bob)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
