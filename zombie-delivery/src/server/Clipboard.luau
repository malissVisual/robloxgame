--!strict
-- 8.5 SANDBOX, Danny's clipboard (the owner: "When I want to give work to my employee, the helper, I'll hold a paper in
-- my hand, like a notepad. At that moment I'm in a kind of ordering mode and I click on what he should carry."): a small
-- paper notepad in your right hand while Danny works for your move, everybody sees it; holding it is ORDERS MODE. The
-- server decides; the client only asks (the Clipboard remote: (out boolean), Config.Robust.Limits.Clipboard;
-- client/DannyOrders.luau: the key Config.MoveHelper.Clipboard.Key, the gamepad's R1, the touch 📋 button, Danny's
-- status line's 📋 ORDERS, his card's 📋 CLIPBOARD). Started by server/SandboxBoot.luau (the city has no list to give).
--   * Out: shared/ClipboardRules.luau's check (Danny hired on your move: your player attribute MoveHelper = "hired",
--     server/MoveHelper.luau's; alive, on foot, your right hand there, your hands free, the phone away, no gun up); a
--     refusal says why in a notice (ClipboardRules.why). Its art (ClipboardRules.pieces: a board, a sheet of paper, a
--     clip, a few lines) is built by server/ModelArt/Builder.luau on the RightHand the way server/KitWear.luau builds the
--     phone (KitFit.fit: in a small hand's palm), welded, massless, never colliding, touched or hit by rays, a model
--     "Clipboard" in your character. The character attribute ClipboardHeld (only this server sets it) tells every
--     client: client/ArmPose.luau holds it up like the phone (its kind "clipboard"), and server/MoveHelper.luau's assign
--     takes a piece only from a player who holds it (MoveHelperBrain.assignCheck's "clipboard").
--   * Away: asked (the remote's false), or by itself when the check fails, looked at again on whatever can end it: the
--     hire over (your MoveHelper no longer "hired": the move's end clears it, its hirer leaving the move makes it
--     "offer" again: Danny let go), a piece picked up or carried (Carrying: you can't carry with it out, so a pick puts
--     it away), a seat (the humanoid's SeatPart), death (at once), a new body, leaving. (10.6: the city's trolley, phone
--     and guns went: no Pushing, PhoneHeld, Aiming.) A right hand replaced meanwhile (the avatar loading) gets it again at the next look.
-- Nothing runs per frame: events only.
--   Clipboard.start()                      the remote and the players
--   Clipboard.out(player) -> boolean       is it out
--   Clipboard.set(player, out) -> (boolean, string?)   take it out / put it away as the remote does: out after, and why
--                                          not (ClipboardRules.check's reason)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local KitFit = require(Shared.KitFit)
local Rules = require(Shared.ClipboardRules)
local Builder = require(script.Parent.ModelArt.Builder)

local Clipboard = {}

local HAND = "RightHand"
local ATTRIBUTE = "ClipboardHeld"
local MODEL = "Clipboard"
-- The character attributes a change of which can end it (the hands' other work, the phone, a gun up).
local BUSY: { [string]: boolean } = { Carrying = true }

type Held = { character: Model, hand: BasePart, built: Builder.Built }

local held: { [Player]: Held } = {}
local bodies: { [Player]: { RBXScriptConnection } } = {} -- a player's body's hooks (their attributes, the humanoid)
local own: { [Player]: { RBXScriptConnection } } = {} -- the player's own (their attributes, a new body)
local notice: RemoteEvent? = nil

local function handOf(character: Model): BasePart?
	local part = character:FindFirstChild(HAND)
	return if part and part:IsA("BasePart") then part else nil
end

-- May it be out now? (ClipboardRules.check on what the server sees.)
local function can(player: Player): (boolean, string?)
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local function busy(name: string): boolean
		local value = if character then character:GetAttribute(name) else nil
		return value ~= nil and value ~= false
	end
	return Rules.check({
		hired = player:GetAttribute("MoveHelper") == "hired",
		alive = humanoid ~= nil and humanoid.Health > 0,
		hand = character ~= nil and handOf(character) ~= nil,
		seated = humanoid ~= nil and (humanoid.Sit == true or humanoid.SeatPart ~= nil),
		carrying = busy("Carrying"),
	})
end

local function takeOff(player: Player)
	local was = held[player]
	if not was then
		return
	end
	held[player] = nil
	pcall(Builder.destroy, was.built)
	if was.character:GetAttribute(ATTRIBUTE) ~= nil then
		was.character:SetAttribute(ATTRIBUTE, nil)
	end
end

-- Its art on the right hand (fitted to the hand as the phone is) and the attribute: true when it is there.
local function build(player: Player, character: Model): boolean
	local hand = handOf(character)
	if not hand then
		return false
	end
	local size = hand.Size
	local scales = { [HAND] = KitFit.factors(HAND, { size.X, size.Y, size.Z }) }
	local spec: Builder.Spec = { id = MODEL, pieces = KitFit.fit(Rules.pieces(), scales) :: any }
	local ok, built = pcall(Builder.build, character, spec, { [HAND] = hand })
	if not ok then
		warn(`[Clipboard] {player.Name}: {built}`)
		return false
	end
	local made = built :: Builder.Built
	made.model.Name = MODEL
	held[player] = { character = character, hand = hand, built = made }
	character:SetAttribute(ATTRIBUTE, true)
	return true
end

-- Looked at again (something that can end it changed): away when the check fails; a replaced hand gets it again.
local function look(player: Player)
	local was = held[player]
	if not was then
		return
	end
	local character = player.Character
	if not character or character ~= was.character or not (can(player)) then
		takeOff(player)
	elseif handOf(character) ~= was.hand then
		takeOff(player)
		build(player, character)
	end
end

function Clipboard.out(player: Player): boolean
	return held[player] ~= nil
end

function Clipboard.set(player: Player, out: boolean): (boolean, string?)
	if not out then
		takeOff(player)
		return false, nil
	end
	if held[player] then
		look(player)
		return held[player] ~= nil, nil
	end
	local ok, why = can(player)
	local character = player.Character
	if not ok or not character then
		return false, why
	end
	return build(player, character), nil
end

-- A body's hooks: its attributes (the hands' other work), its humanoid (a seat, death). A new body has nothing in its hand.
local function onBody(player: Player, character: Model)
	local list = bodies[player]
	if list then
		for _, connection in list do
			connection:Disconnect()
		end
	end
	takeOff(player)
	local hooks: { RBXScriptConnection } = {}
	bodies[player] = hooks
	table.insert(hooks, character.AttributeChanged:Connect(function(name: string)
		if BUSY[name] then
			look(player)
		end
	end))
	local function humanoidHooks(humanoid: Humanoid)
		table.insert(hooks, humanoid.Died:Connect(function()
			takeOff(player) -- (at once: the body falls apart)
		end))
		table.insert(hooks, humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			look(player)
		end))
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoidHooks(humanoid)
	else
		task.spawn(function()
			local found = character:WaitForChild("Humanoid", 10)
			if found and found:IsA("Humanoid") and bodies[player] == hooks then
				humanoidHooks(found)
			end
		end)
	end
end

local function watch(player: Player)
	if own[player] then
		return
	end
	own[player] = {
		player.AttributeChanged:Connect(function(name: string)
			if name == "MoveHelper" then
				look(player) -- (the hire over: the move's end, its hirer gone)
			end
		end),
		player.CharacterAdded:Connect(function(character: Model)
			onBody(player, character)
		end),
	}
	local character = player.Character
	if character then
		onBody(player, character)
	end
end

local function forget(player: Player)
	takeOff(player)
	local function cut(list: { RBXScriptConnection }?)
		if list then
			for _, connection in list do
				connection:Disconnect()
			end
		end
	end
	cut(bodies[player])
	cut(own[player])
	bodies[player], own[player] = nil, nil
end

function Clipboard.start()
	local remote = Net.get("Clipboard")
	notice = Net.get("Notice")
	remote.OnServerEvent:Connect(function(player: Player, out: any)
		if type(out) ~= "boolean" or not Net.limit(player, "Clipboard", Config.Robust.Limits.Clipboard) then
			return
		end
		local now, why = Clipboard.set(player, out)
		local say = notice
		local text = if out and not now then Rules.why(why) else nil
		if text and say then
			say:FireClient(player, text)
		end
	end)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(forget)
end

return Clipboard
