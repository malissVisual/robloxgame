--!strict
-- 5.0: the kit you own, worn on your character for everybody to see, and the phone in your hand while you use it.
-- The art is Codex's (server/KitArt/Geometry.luau, server/PhoneArt/Geometry.luau, design/kit-models/ and
-- design/phone-art/), built by server/ModelArt/Builder.luau: native parts welded to the R15 body parts (UpperTorso,
-- the upper arms, the feet, the right hand), massless and never colliding, touching or hit by rays. The joints are
-- never touched (no C0); the parts ride the body parts wherever the animation puts them, seated in a car too.
--
--   pack    the best backpack owned (Config.Kit: the Big Backpack, else the Courier Backpack) on the back
--   load    the one parcel on it while the pack holds something (the player's PackCount attribute > 0, server/Cargo.luau
--           on a foot job): on the Courier Backpack's top, strapped on the Big Backpack's lid
--   shoes   the Running Shoes on both feet
--   jacket  the Thermal Jacket on the torso, its sleeves on the upper arms
--   hand    6.0: the plastic bag (Config.Courier.BagKit) in the left hand: its art hangs from a small part, BagPivot,
--           joined to the hand by a Motor6D "BagSwing" (KitArt "bag"); every client swings it behind a running body
--           (client/SprintPose.luau, its Transform). Put away while the hands carry or push something, or seated.
--   vest    6.0: the best vest owned (stream 2's armour: Config.Kit "heavy", else "kevlar") over the courier's jacket. A
--           vest that changes while you play (bought, a better one) is put on with the "vest" gesture (arms over the
--           head, then down: shared/Gestures.luau, played by client/ArmPose.luau for everybody). 6.0.1: else the
--           Courier Vest (Config.Kit "hivis"): Codex's red reflective vest, the pieces that were part of the courier's
--           body (server/CharacterArt/Geometry.luau Geometry.hivis), in their own colours; bought, it is put on too.
--   phone   the field phone in the right hand while the phone window is open (the PhoneHold remote, client/Phone.luau)
--           and you are on foot: not seated, not carrying or pushing anything, not aiming. The character attribute
--           PhoneHeld (only this server sets it) tells every client: client/ArmPose.luau raises the arm and hides the
--           gun, like it does for cargo.
--
-- The art is authored for a nominal block R15 body; every piece is scaled per axis to the size of the body part it
-- sits on (shared/KitFit.luau: a wider torso, a deeper foot …; clamped, the hand with one factor). Nothing runs per
-- frame: a player's pieces are compared with what they should wear after an event (a spawn, the avatar loading or
-- rescaling a body part, the profile changing, PackCount, sitting, the Carrying / Pushing / Aiming attributes, the
-- phone remote), at most every REFRESH seconds, and only what changed is built again (Builder.destroy first). Death
-- takes everything off at once; leaving cleans up.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local KitFit = require(Shared.KitFit)
local Net = require(Shared.Net)
local PlayerData = require(script.Parent.PlayerData)
local Builder = require(script.Parent.ModelArt.Builder)
local Npcs = require(script.Parent.Npcs) -- 6.0: the vest's put-on gesture
local KitArt = require(script.Parent.KitArt.Geometry)
local PhoneArt = require(script.Parent.PhoneArt.Geometry)
local CharacterArt = require(script.Parent.CharacterArt.Geometry) -- 6.0.1: the Courier Vest's pieces

local KitWear = {}

local REFRESH = 0.1 -- seconds: events in a burst (the avatar loading, a flood of the remote) give one look
local BIGPACK_LOAD_Y = 1.3 -- the parcel on the Big Backpack's lid (the art puts it on the Courier Backpack's top)
local HIVIS = Config.Courier.VestKit -- 6.0.1: the Courier Vest ("hivis": KitFit.outfit's vest when no armour is owned)
local NAMES: { [string]: string } = { pack = "KitPack", load = "KitParcel", shoes = "KitShoes", jacket = "KitJacket", phone = "HeldPhone", hand = "KitBag", vest = "KitVest" }
-- What a change of these character attributes can change: the phone is put away for the hands' other work.
local HANDS_BUSY: { [string]: boolean } = { Carrying = true, Pushing = true, Aiming = true }
-- 6.0: … and the bag is put away for these (aiming, the left hand only steadies the gun: the bag stays)
local BAG_BUSY: { [string]: boolean } = { Carrying = true, Pushing = true }

-- (6.0: `pivot` = the bag's part hung from the hand, removed with the slot)
type Slot = { key: string, built: Builder.Built, parts: { [string]: BasePart }, sizes: { [string]: Vector3 }, pivot: BasePart? }
type Wearer = { character: Model, slots: { [string]: Slot }, connections: { RBXScriptConnection }, sized: { [BasePart]: boolean } }

local wearers: { [Player]: Wearer } = {}
local wantPhone: { [Player]: boolean } = {} -- the phone window is open (what the client last said)
local queued: { [Player]: boolean } = {}
local vests: { [Player]: string | false } = {} -- 6.0: the vest worn at the last look (false: none; nil: not looked yet)

-- The art's pieces for a slot (fresh tables: the fit copies them anyway).
local function piecesFor(slot: string, id: string): { any }
	if slot == "phone" then
		return PhoneArt.pieces("phone")
	end
	if slot == "load" then
		local parcel = KitArt.load()
		if id == "bigpack" then
			parcel.at = { parcel.at[1], BIGPACK_LOAD_Y, parcel.at[3] }
		end
		return { parcel }
	end
	if slot == "vest" and id == HIVIS then
		-- 6.0.1: the courier's own vest, as kit pieces (any finish: dye() gives them their real colours after the build)
		local out: { any } = {}
		for _, piece in CharacterArt.hivis() do
			table.insert(out, { name = piece.name, attach = piece.attach, size = piece.size, at = piece.at, turn = piece.turn, finish = "red" })
		end
		return out
	end
	return KitArt.pieces(id)
end

-- 6.0.1: the Courier Vest's parts in the colour and cloth of the courier art (as server/CharacterArt/Rig.luau paints).
local function dye(built: Builder.Built)
	local looks: { [string]: CharacterArt.Piece } = {}
	for _, piece in CharacterArt.hivis() do
		looks[piece.name] = piece
	end
	for _, part in built.parts do
		local look = looks[part.Name]
		if look then
			part.Color = Color3.fromRGB(look.color[1], look.color[2], look.color[3])
			part.Material = if look.material == "Fabric" then Enum.Material.Fabric else Enum.Material.SmoothPlastic
		end
	end
end

-- 6.0: the see-through pieces (the bag's plastic).
local function seeThrough(built: Builder.Built)
	for _, part in built.parts do
		local amount = KitArt.translucent[part.Name]
		if amount then
			part.Transparency = amount
		end
	end
end

-- 6.0: the bag's pivot, hung from the left hand by the BagSwing Motor6D (the clients write its Transform), placed
-- before the art is built on it. Nil without a left hand (an R6 avatar).
local function hangBag(character: Model): (BasePart?, BasePart?)
	local hand = character:FindFirstChild("LeftHand")
	if not hand or not hand:IsA("BasePart") then
		return nil, nil
	end
	local pivot = Instance.new("Part")
	pivot.Name = "KitBagPivot"
	pivot.Size = Vector3.new(0.2, 0.2, 0.2)
	pivot.Transparency = 1
	pivot.Massless, pivot.CanCollide, pivot.CanQuery, pivot.CanTouch, pivot.CastShadow = true, false, false, false, false
	local grip = CFrame.new(0, -hand.Size.Y / 2 - Config.Courier.Bag.Grip, 0)
	pivot.CFrame = hand.CFrame * grip
	local joint = Instance.new("Motor6D")
	joint.Name = "BagSwing"
	joint.Part0 = hand
	joint.Part1 = pivot
	joint.C0 = grip
	joint.Parent = pivot
	pivot.Parent = character
	return hand, pivot
end

-- One slot built on the character, fitted to its body parts; nil when a body part is missing (an R6 avatar).
local function build(character: Model, slot: string, id: string): Slot?
	local pieces = piecesFor(slot, id)
	local parts: { [string]: BasePart } = {}
	local sizes: { [string]: Vector3 } = {}
	local scales: { [string]: KitFit.Scale } = {}
	if slot == "hand" then
		-- 6.0: the bag, on its pivot (not fitted: it hangs, the hand's size does not shape it)
		local hand, pivot = hangBag(character)
		if not hand or not pivot then
			return nil
		end
		local bagSpec: Builder.Spec = { id = NAMES.hand, pieces = pieces :: any }
		local ok, made = pcall(Builder.build, character, bagSpec, { BagPivot = pivot })
		if not ok then
			warn(`[KitWear] {slot} {id}: {made}`)
			pivot:Destroy()
			return nil
		end
		local bag = made :: Builder.Built
		seeThrough(bag)
		return { key = id, built = bag, parts = { LeftHand = hand }, sizes = { LeftHand = hand.Size }, pivot = pivot }
	end
	for _, piece in pieces do
		local bone: string = piece.attach
		if not parts[bone] then
			local part = character:FindFirstChild(bone)
			if not part or not part:IsA("BasePart") then
				return nil
			end
			parts[bone], sizes[bone] = part, part.Size
			scales[bone] = KitFit.factors(bone, { part.Size.X, part.Size.Y, part.Size.Z })
		end
	end
	local spec: Builder.Spec = { id = NAMES[slot] or slot, pieces = KitFit.fit(pieces, scales) :: any }
	local ok, built = pcall(Builder.build, character, spec, parts)
	if not ok then
		warn(`[KitWear] {slot} {id}: {built}`)
		return nil
	end
	if slot == "vest" and id == HIVIS then
		dye(built :: Builder.Built)
	end
	return { key = id, built = built :: Builder.Built, parts = parts, sizes = sizes }
end

-- Still on the same body parts, of the same size (the avatar may replace or rescale them after the spawn)?
local function fits(character: Model, slot: Slot): boolean
	for bone, part in slot.parts do
		if part.Parent ~= character or part.Size ~= slot.sizes[bone] or character:FindFirstChild(bone) ~= part then
			return false
		end
	end
	local pivot = slot.pivot
	return slot.built.model.Parent == character and (pivot == nil or pivot.Parent == character)
end

local function remove(slot: Slot)
	Builder.destroy(slot.built)
	if slot.pivot then
		slot.pivot:Destroy()
	end
end

local function takeOff(wearer: Wearer)
	for slot, current in wearer.slots do
		remove(current)
		wearer.slots[slot] = nil
	end
end

-- 6.0: is the left hand free for the bag (nothing carried or pushed, not seated)?
local function bagFree(character: Model, humanoid: Humanoid): boolean
	if humanoid.Sit or humanoid.SeatPart ~= nil then
		return false
	end
	for name in BAG_BUSY do
		local value = character:GetAttribute(name)
		if value ~= nil and value ~= false then
			return false
		end
	end
	return true
end

local function holdsPhone(player: Player, character: Model, humanoid: Humanoid): boolean
	local profile = PlayerData.get(player)
	if not wantPhone[player] or not profile or profile.phone ~= true then
		return false
	end
	if humanoid.Sit or humanoid.SeatPart ~= nil then
		return false
	end
	for name in HANDS_BUSY do
		local value = character:GetAttribute(name)
		if value ~= nil and value ~= false then
			return false
		end
	end
	return true
end

-- What the character should wear now, against what it wears: the differences are built again.
local function refresh(player: Player)
	local wearer = wearers[player]
	if not wearer then
		return
	end
	local character = wearer.character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local profile = PlayerData.get(player)
	local wanted: { [string]: string } = {}
	if humanoid and humanoid.Health > 0 and profile and player.Character == character and character.Parent then
		wanted = KitFit.outfit(profile.kit, (tonumber(player:GetAttribute("PackCount")) or 0) > 0)
		if holdsPhone(player, character, humanoid) then
			wanted.phone = "phone"
		end
		if wanted.hand and not bagFree(character, humanoid) then
			(wanted :: any).hand = nil
		end
	end
	for slot, current in wearer.slots do
		if wanted[slot] ~= current.key or not fits(character, current) then
			remove(current)
			wearer.slots[slot] = nil
		end
	end
	for slot, id in wanted do
		if not wearer.slots[slot] then
			local made = build(character, slot, id)
			if made then
				wearer.slots[slot] = made
			end
		end
	end
	-- 6.0: a vest put on while you play (not the one you joined or respawned with): the put-on gesture.
	if profile and humanoid and humanoid.Health > 0 and player.Character == character then
		local vest: string | false = wanted.vest or false
		local before = vests[player]
		if before ~= nil and before ~= vest and vest ~= false and wearer.slots.vest ~= nil then
			Npcs.act(character, "vest")
		end
		vests[player] = vest
	end
	local held = if wearer.slots.phone then true else nil
	if character:GetAttribute("PhoneHeld") ~= held then
		character:SetAttribute("PhoneHeld", held)
	end
end

local function schedule(player: Player)
	if queued[player] then
		return
	end
	queued[player] = true
	task.delay(REFRESH, function()
		queued[player] = nil
		if player.Parent then
			refresh(player)
		end
	end)
end

local function forget(player: Player)
	local wearer = wearers[player]
	if not wearer then
		return
	end
	wearers[player] = nil
	for _, connection in wearer.connections do
		connection:Disconnect()
	end
	takeOff(wearer)
	if wearer.character.Parent then
		wearer.character:SetAttribute("PhoneHeld", nil)
	end
end

-- A new character: follow what can change its look (its body parts, sitting, dying, the hands' attributes).
local function dress(player: Player, character: Model)
	forget(player)
	local wearer: Wearer = { character = character, slots = {}, connections = {}, sized = {} }
	wearers[player] = wearer
	local function follow(part: Instance)
		if KitFit.Nominal[part.Name] and part:IsA("BasePart") and not wearer.sized[part] then
			wearer.sized[part] = true
			table.insert(wearer.connections, part:GetPropertyChangedSignal("Size"):Connect(function()
				schedule(player)
			end))
		end
	end
	for _, child in character:GetChildren() do
		follow(child)
	end
	table.insert(wearer.connections, character.ChildAdded:Connect(function(child)
		if KitFit.Nominal[child.Name] then
			follow(child)
			schedule(player)
		end
	end))
	table.insert(wearer.connections, character.AttributeChanged:Connect(function(name)
		if HANDS_BUSY[name] or BAG_BUSY[name] then
			schedule(player)
		end
	end))
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") or wearers[player] ~= wearer then
			return
		end
		table.insert(wearer.connections, humanoid.Seated:Connect(function()
			schedule(player)
		end))
		table.insert(wearer.connections, humanoid.Died:Connect(function()
			takeOff(wearer) -- at once: the body falls apart, loose pieces would drop through the world
			character:SetAttribute("PhoneHeld", nil)
		end))
		schedule(player)
	end)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		dress(player, character)
	end)
	player.CharacterAppearanceLoaded:Connect(function()
		schedule(player)
	end)
	player:GetAttributeChangedSignal("PackCount"):Connect(function()
		schedule(player)
	end)
	if player.Character then
		dress(player, player.Character)
	end
end

function KitWear.start()
	-- The phone window opened (true) or closed (false). Only the wish is kept: a flood of these rewrites it, the look
	-- follows at most every REFRESH seconds, and the server decides whether the phone shows (owned, on foot, hands free).
	Net.get("PhoneHold").OnServerEvent:Connect(function(player: Player, holding: any)
		if type(holding) ~= "boolean" then
			return
		end
		if (wantPhone[player] == true) ~= holding then
			if holding then
				wantPhone[player] = true
			else
				wantPhone[player] = nil
			end
			schedule(player)
		end
	end)
	-- A purchase (profile.kit) or the phone given: the outfit is compared (most changes are money: nothing to build).
	PlayerData.Changed:Connect(schedule)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		forget(player)
		wantPhone[player] = nil
		queued[player] = nil
		vests[player] = nil
	end)
end

return KitWear
