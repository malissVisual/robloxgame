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
--           joined to the hand by a Motor6D "BagSwing" (KitArt "bag"); every client swings it (6.1: client/BagSway.luau,
--           the only writer of its Transform). 6.1: only while it is what you hold (the character attribute Hand =
--           "bag", server/Hand.luau); put away while you push something or sit. It stays while the hands carry cargo:
--           6.0 took it off and built it again every time the hands took or gave a piece (the Carrying attribute
--           toggling: the "blinking" bag). KitWear.bagArt builds the same bag on any part (server/Cargo.luau's bag set
--           down on the ground). 6.4: the ACTIVE bag (shared/Transport.luau activeBag: profile.activeBag, else the best
--           owned): the plastic bag, the tote, the thermal, the padded messenger or the duffel, each its own KitArt id;
--           the pivot's Bag attribute names it (client/BagSway.luau swings each one its own way), and switching the
--           bag builds the new one (the slot's key is the bag's id). KitWear.bagDrop(id): how far it hangs.
--           6.4, the ways of wearing it (Config.Kit carry / stays, Holding.wornAs, Config.Courier.BagPlaces): the
--           plastic and the thermal bag in the left hand, the tote over the left shoulder, the messenger cross-body on
--           the left hip, the duffel in the hand; out of the hand the tote and the duffel are slung on the back and
--           the messenger slid behind the hip (a strap across the torso: slot "strap", KitArt.straps), the hand bags
--           go as in 6.1. The slot key is "id@place"; the character's BagWorn attribute says where it is, BagSwitchAt
--           (the server time) when it moved between the front and the back, with the "sling" / "unsling" gesture.
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
--
-- 6.4.1, the bag shows again: 6.4's slot key "id@place" went to KitArt.pieces as a look ("Unknown kit id: bag@hand"),
-- which threw inside every refresh, so no bag was ever built (and nothing after it in that refresh). The hand slot no
-- longer asks KitArt for its key (KitFit.parseBagKey gives the look), and one slot that fails to build only warns:
-- the rest of the outfit is still put on. An R6 body wears the kit too (KitFit.R6: the bag under "Left Arm", the
-- straps, the pack and the bag's places on the "Torso"). What is in the bag shows (shared/BagFill.luau): the pieces
-- (the player's BagCount / BagLooks attributes, server/Cargo.luau) stick out of its opening and the body swells; only
-- the bag's art is built again when they change (the pivot and its swinging joint stay). tools/character-art/check.py
-- builds every bag in every place on the courier's R15 body and on an R6 body offline.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local KitFit = require(Shared.KitFit)
local Net = require(Shared.Net)
local TransportRules = require(Shared.Transport) -- 6.4: the active bag
local Holding = require(Shared.Holding) -- 6.4: where the bag is worn
local BagFill = require(Shared.BagFill) -- 6.4.1: what is in the bag shows
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
local NAMES: { [string]: string } = { pack = "KitPack", load = "KitParcel", shoes = "KitShoes", jacket = "KitJacket", phone = "HeldPhone", hand = "KitBag", vest = "KitVest", strap = "KitBagStrap" }
-- What a change of these character attributes can change: the phone is put away for the hands' other work.
local HANDS_BUSY: { [string]: boolean } = { Carrying = true, Pushing = true, Aiming = true }
-- 6.0: … and the bag is put away for these (aiming, the left hand only steadies the gun: the bag stays). 6.1: not for
-- Carrying any more (the cargo is held over it; taking it off and on was the blink), and the Hand attribute decides.
local BAG_BUSY: { [string]: boolean } = { Pushing = true, Hand = true }

-- (6.0: `pivot` = the bag's part hung from the hand, removed with the slot. 6.4.1: `fill` = what its art shows in it,
-- "count:looks")
type Slot = { key: string, built: Builder.Built, parts: { [string]: BasePart }, sizes: { [string]: Vector3 }, pivot: BasePart?, fill: string? }
export type Fill = { count: number, looks: { string }, key: string }
type Wearer = { character: Model, slots: { [string]: Slot }, connections: { RBXScriptConnection }, sized: { [BasePart]: boolean }, hand: any? }

local wearers: { [Player]: Wearer } = {}
local wantPhone: { [Player]: boolean } = {} -- the phone window is open (what the client last said)
local queued: { [Player]: boolean } = {}
local vests: { [Player]: string | false } = {} -- 6.0: the vest worn at the last look (false: none; nil: not looked yet)

-- 6.4.1: a body part by its R15 name, or its stand-in on an R6 body (KitFit.R6: "Left Arm" for the LeftHand, the
-- "Torso" for the UpperTorso …).
local function bodyPart(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	if not part then
		local stand = KitFit.R6[name]
		part = if stand then character:FindFirstChild(stand) else nil
	end
	return if part and part:IsA("BasePart") then part else nil
end

-- The art's pieces for a slot (fresh tables: the fit copies them anyway). Never the hand slot (its key is "id@place").
local function piecesFor(slot: string, id: string): { any }
	if slot == "strap" then
		-- 6.4: a worn bag's strap on the torso (the key "id@place": KitArt.straps)
		local bag, place = string.match(id, "^([^@]+)@(%w+)")
		return if bag and place then KitArt.straps(bag, place) else {}
	end
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
-- before the art is built on it. Nil without a left hand. 6.4: `place` (Config.Courier.BagPlaces: "hand", or
-- "shoulder" / "hip" / "back" / "hipBack" on the UpperTorso, scaled to it; `packed`: a backpack is worn, a slung bag
-- hangs PackPush further back); the pivot's Bag and Worn attributes tell client/BagSway.luau which bag hangs where.
-- 6.4.1: the spot is KitFit.bagGrip's (tested); on an R6 body the "Left Arm" / the "Torso" (KitFit.R6).
local function hangBag(character: Model, id: string, place: string, packed: boolean): (BasePart?, BasePart?)
	local spot = Config.Courier.BagPlaces[place]
	local name = if spot then spot.part else "LeftHand"
	local hand = bodyPart(character, name)
	if not hand then
		return nil, nil
	end
	local pivot = Instance.new("Part")
	pivot.Name = "KitBagPivot"
	pivot:SetAttribute("Bag", id) -- 6.4: which bag (client/BagSway.luau's tuning)
	pivot:SetAttribute("Worn", if place == "hipBack" then "back" else place) -- 6.4: its motion
	pivot.Size = Vector3.new(0.2, 0.2, 0.2)
	pivot.Transparency = 1
	pivot.Anchored = false -- (never anchored: joined to the body, it would freeze it)
	pivot.Massless, pivot.CanCollide, pivot.CanQuery, pivot.CanTouch, pivot.CastShadow = true, false, false, false, false
	local at, turn = KitFit.bagGrip(id, place, name, { hand.Size.X, hand.Size.Y, hand.Size.Z }, packed)
	local grip = CFrame.new(at[1], at[2], at[3]) * CFrame.Angles(math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3]))
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

-- 6.1: the bag's art on `pivot` (its grip: the bag hangs down -Y), its plastic see-through; under `parent`. 6.4: `id`
-- the bag (a Config.Kit bag with a KitArt look; nil or unknown: the plastic bag). 6.4.1: `count` pieces in it (their
-- `looks`, in order; missing ones show as parcels) stick out of its opening, up to its room, and its body swells
-- (shared/BagFill.luau).
function KitWear.bagArt(parent: Instance, pivot: BasePart, id: string?, count: number?, looks: { string }?): Builder.Built?
	local look = if id and KitArt.bags[id] then id else Config.Courier.BagKit
	local ok, made = pcall(function(): Builder.Built
		local pieces: { any } = KitArt.pieces(look)
		local mouth = Config.Courier.BagFill.Mouth[look]
		local def = TransportRules.findKit(look)
		local room = if def and def.extra then def.extra else 0
		local inside = math.max(0, math.floor(count or 0))
		if mouth and inside > 0 then
			pieces = BagFill.swell(pieces, mouth, inside, room)
			for _, piece in BagFill.pieces(mouth, inside, room, looks) do
				table.insert(pieces, piece)
			end
		end
		local spec: Builder.Spec = { id = NAMES.hand, pieces = pieces :: any }
		return Builder.build(parent, spec, { BagPivot = pivot })
	end)
	if not ok then
		warn(`[KitWear] bag {look}: {made}`)
		return nil
	end
	local built = made :: Builder.Built
	seeThrough(built)
	return built
end

-- 6.4: how far under its grip a bag's art reaches (studs; server/Cargo.luau stands a set-down bag on its bottom).
local drops: { [string]: number } = {}
function KitWear.bagDrop(id: string?): number
	local look = if id and KitArt.bags[id] then id else Config.Courier.BagKit
	local known = drops[look]
	if known then
		return known
	end
	local low = 0
	for _, piece in KitArt.pieces(look) do
		local r = piece.turn or { 0, 0, 0 }
		local turn = CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
		-- (the half height of a turned box: each of its axes' share of up)
		local half = (math.abs(turn.RightVector.Y) * piece.size[1] + math.abs(turn.UpVector.Y) * piece.size[2] + math.abs(turn.LookVector.Y) * piece.size[3]) / 2
		low = math.max(low, half - piece.at[2])
	end
	drops[look] = low
	return low
end

-- One slot built on the character, fitted to its body parts; nil when a body part is missing. 6.4.1: `fill` what the
-- bag shows in it (the hand slot). The offline check (tools/character-art/check.py) calls it as KitWear.build.
local function build(character: Model, slot: string, id: string, fill: Fill?): Slot?
	if slot == "hand" then
		-- 6.0: the bag, on its pivot (not fitted: it hangs, the hand's size does not shape it). 6.4: the key is
		-- "id@place" (KitFit.bagKey), "+" at the end while a backpack is worn; 6.4.1: only `bagId` is a KitArt look.
		local bagId, place, packed = KitFit.parseBagKey(id)
		if not bagId or not place then
			return nil
		end
		local hand, pivot = hangBag(character, bagId, place, packed)
		if not hand or not pivot then
			return nil
		end
		local bag = KitWear.bagArt(character, pivot, bagId, if fill then fill.count else 0, if fill then fill.looks else nil)
		if not bag then
			pivot:Destroy()
			return nil
		end
		return { key = id, built = bag, parts = { [hand.Name] = hand }, sizes = { [hand.Name] = hand.Size }, pivot = pivot, fill = if fill then fill.key else "" }
	end
	local pieces = piecesFor(slot, id)
	local parts: { [string]: BasePart } = {}
	local sizes: { [string]: Vector3 } = {}
	local scales: { [string]: KitFit.Scale } = {}
	for _, piece in pieces do
		local bone: string = piece.attach
		if not parts[bone] then
			local part = bodyPart(character, bone) -- (6.4.1: an R6 body's stand-in, scaled to it below)
			if not part then
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
KitWear.build = build

-- 6.4.1: what the bag in the hand slot shows (the pieces in it: the player's BagCount and BagLooks attributes).
local function fillOf(player: Player): Fill
	local count = math.max(0, math.floor(tonumber(player:GetAttribute("BagCount")) or 0))
	local looks = if count > 0 then BagFill.looks(player:GetAttribute("BagLooks")) else {}
	return { count = count, looks = looks, key = if count > 0 then `{count}:{table.concat(looks, ",")}` else "" }
end

-- Still on the same body parts, of the same size (the avatar may replace or rescale them after the spawn)?
local function fits(character: Model, slot: Slot): boolean
	for bone, part in slot.parts do
		-- (6.4.1: by the part's own name: an R6 stand-in is filed under the R15 name it stands for)
		if part.Parent ~= character or part.Size ~= slot.sizes[bone] or character:FindFirstChild(part.Name) ~= part then
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

-- 6.0: is the left hand free for the bag (nothing pushed, not seated)? 6.1: and is the bag what you hold? 6.4: where
-- the active bag shows (Holding.wornAs: "hand" | "shoulder" | "hip" | "back", nil: not shown) and its slot key
-- ("id@place", "+" with a backpack worn: a slung bag hangs behind it).
local function bagWorn(character: Model, humanoid: Humanoid, bag: Config.KitDef?): string?
	if not bag then
		return nil
	end
	local pushing = character:GetAttribute("Pushing")
	local busy = humanoid.Sit or humanoid.SeatPart ~= nil or (pushing ~= nil and pushing ~= false)
	local hand = character:GetAttribute("Hand")
	return Holding.wornAs(if type(hand) == "string" then hand else "fists", bag.carry, bag.stays, busy)
end

local function bagKey(bag: Config.KitDef, worn: string, packed: boolean): string
	local place = if worn == "back" and bag.carry == "hip" then "hipBack" else worn
	return KitFit.bagKey(bag.id, place, packed and worn == "back")
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
	local worn: string? = nil
	if humanoid and humanoid.Health > 0 and profile and player.Character == character and character.Parent then
		local bag = TransportRules.activeBag(profile.kit, profile.activeBag) -- 6.4: the bag in your hand
		wanted = KitFit.outfit(profile.kit, (tonumber(player:GetAttribute("PackCount")) or 0) > 0, if bag then bag.id else "")
		if holdsPhone(player, character, humanoid) then
			wanted.phone = "phone"
		end
		-- 6.4: the bag where it is carried now (the hand, the shoulder, the hip, the back) and its strap
		worn = if wanted.hand then bagWorn(character, humanoid, bag) else nil
		if bag and worn then
			local key = bagKey(bag, worn, wanted.pack ~= nil)
			wanted.hand = key
			local _, place = KitFit.parseBagKey(key)
			if #KitArt.straps(bag.id, place or worn) > 0 then
				wanted.strap = key
			end
		else
			(wanted :: any).hand = nil
		end
	end
	-- 6.4: the BagWorn attribute (every client: client/BagSway.luau's motion) and, when the bag moves between the
	-- front and the back while you stand, BagSwitchAt (the server time: the bag's move) and the sling / unsling gesture
	local wornBefore = character:GetAttribute("BagWorn")
	-- (6.4 review: the gesture only for a change of hand (1 / 2 / 3, B), not a bike's or a trolley's let-go)
	local handNow = character:GetAttribute("Hand")
	local handChanged = wearer.hand ~= handNow
	wearer.hand = handNow
	if wornBefore ~= worn and character.Parent then
		character:SetAttribute("BagWorn", worn)
		local seated = humanoid ~= nil and (humanoid.Sit or humanoid.SeatPart ~= nil)
		if type(wornBefore) == "string" and worn ~= nil and not seated and handChanged then
			character:SetAttribute("BagSwitchAt", workspace:GetServerTimeNow())
			if worn == "back" then
				Npcs.act(character, "sling")
			elseif wornBefore == "back" then
				Npcs.act(character, "unsling")
			end
		end
	end
	for slot, current in wearer.slots do
		if wanted[slot] ~= current.key or not fits(character, current) then
			remove(current)
			wearer.slots[slot] = nil
		end
	end
	local fill = fillOf(player)
	for slot, id in wanted do
		if not wearer.slots[slot] then
			-- (6.4.1: one slot that fails says so and the others are still put on: 6.4's bag error stopped them all)
			local ok, made = pcall(build, character, slot, id, if slot == "hand" then fill else nil)
			if not ok then
				warn(`[KitWear] {slot} {id}: {made}`)
			elseif made then
				wearer.slots[slot] = made
			end
		end
	end
	-- 6.4.1: the pieces in the bag changed: only its art is built again, on the same pivot (its joint keeps swinging)
	local bagSlot = wearer.slots.hand
	if bagSlot and bagSlot.pivot and bagSlot.fill ~= fill.key then
		local art = KitWear.bagArt(character, bagSlot.pivot, (KitFit.parseBagKey(bagSlot.key)), fill.count, fill.looks)
		if art then
			Builder.destroy(bagSlot.built)
			bagSlot.built = art
			bagSlot.fill = fill.key
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
	-- 6.4.1: the pieces in the bag (its art shows them)
	player:GetAttributeChangedSignal("BagCount"):Connect(function()
		schedule(player)
	end)
	player:GetAttributeChangedSignal("BagLooks"):Connect(function()
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
