--!strict
-- 6.12: the cosmetics (Config.Cosmetics; the owner: "something to spend the game's money on, looks only") on the
-- server: the wardrobe in the profile (profile.style = { owned, worn }, server/PlayerData.luau saves it), the Style
-- remote (client/StyleApp.luau, the phone's STYLE app) and the looks on everybody's courier and vehicles.
--
--   The Style remote: ("buy", id) an item that exists, is sold (not a reward), is not yours, at your level, while you
--   stand at one of the shops that sell it (the clerks, the owner: "things are bought only from the NPCs in the shops,
--   for the vibe": Style.shopAt, server/Shops.luau's nearShop test; away from them "Buy it from Gus at Wrench
--   Garage."), for its price through PlayerData.spend (the game's one money path); bought, it is worn at once.
--   ("wear", id) one you own, in its slot (one item a slot), and ("unwear", slot) off again: anywhere. Rate limited
--   (Config.Robust.Limits.Style); every answer is a toast (the Notice remote, shared/Style.luau's words); the state
--   (State, Main) carries the wardrobe back. server → client: ("open", tab) the phone's STYLE app on that tab
--   (StyleWear.invite: a clerk's "Style" prompt, server/ShopClerks.luau).
--   StyleWear.give(player, id) gives an item without money (the rewards of later tasks, events and passes).
--
--   The looks (shared/StyleBuild.luau, shared/StyleLooks.luau): all decorative parts, massless, never colliding,
--   touching or hit by rays, welded to what they ride; no joint of the body is touched.
--     hat, jacket  built on the character's real parts (6.9: Roblox's classic blocky R15 with the player's own head and
--                  look, server/CourierAvatar.luau): the hat fitted to the head's visible size, the player's own hat and
--                  hair accessories hidden under it (StyleBuild.hideOwn; shown again when it comes off); the jacket's
--                  thin shells over the torso and the arms, under KitWear's vest and bag. Built again on a respawn,
--                  when the avatar replaces or rescales a part (CourierAvatar's ApplyDescriptionAsync), and taken off
--                  at death. Nothing per frame: events, at most every REFRESH seconds.
--     vest, bag    the Courier Vest's cloth and the active bag's body recoloured through KitWear's tint hook
--                  (KitWear.tint: every time KitWear builds the vest or the bag again, KitWear.retint on a change).
--     wrap         every own car's painted panels (Vehicles' paintParts) over Wrench Garage's paint; TAKE OFF: the
--                  paint again (Vehicles.repaint)
--     bikepaint    every own bike's and the E-Scooter's frame (StyleBuild.paintBike)
--     decal        thin parts on every own car's painted panels, round its lamps, racks, labels and doors
--                  (StyleBuild.decals); built again when the car spawns, gets a new paint, kit or gun
--   Vehicles.onStyle (called after a spawn, a repaint, a kit or a gun change) puts the vehicle's looks on. A rental, a
--   lent company vehicle and an NPC's car never take any.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local KitFit = require(Shared.KitFit)
local Net = require(Shared.Net)
local Style = require(Shared.Style)
local StyleBuild = require(Shared.StyleBuild)
local StyleLooks = require(Shared.StyleLooks)
local PlayerData = require(script.Parent.PlayerData)
local Vehicles = require(script.Parent.Vehicles)
local KitWear = require(script.Parent.KitWear)

local StyleWear = {}

local REFRESH = 0.1 -- seconds: a burst of events (the avatar loading) gives one look
local COURIER = { "hat", "jacket" }
local VEHICLE: { [string]: boolean } = { wrap = true, bikepaint = true, decal = true }

type Wearer = { character: Model, built: { [string]: StyleBuild.Built }, connections: { RBXScriptConnection }, sized: { [BasePart]: boolean } }

local wearers: { [Player]: Wearer } = {}
local queued: { [Player]: boolean } = {}
local notice: RemoteEvent? = nil

local function tell(player: Player, text: string)
	if notice then
		notice:FireClient(player, text)
	end
end

local function wardrobe(player: Player): Style.Wardrobe?
	local profile = PlayerData.get(player)
	return if profile then profile.style else nil
end

-- ── The courier ───────────────────────────────────────────────────────────

local function takeOff(wearer: Wearer)
	for slot, built in wearer.built do
		built.model:Destroy()
		wearer.built[slot] = nil
	end
end

-- What the character should wear (the hat, the jacket) against what it wears: the differences are built again.
local function refresh(player: Player)
	local wearer = wearers[player]
	if not wearer then
		return
	end
	local character = wearer.character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local style = wardrobe(player)
	local alive = humanoid ~= nil and humanoid.Health > 0 and player.Character == character and character.Parent ~= nil
	for _, slot in COURIER do
		local def = if alive and style then Style.worn(style, slot) else nil
		local have = wearer.built[slot]
		if have and (def == nil or have.model:GetAttribute("StyleLook") ~= def.id or not StyleBuild.fits(have)) then
			have.model:Destroy()
			wearer.built[slot] = nil
		end
		if def and not wearer.built[slot] then
			local ok, made = pcall(StyleBuild.courier, character, def)
			if not ok then
				warn(`[StyleWear] {player.Name}'s {def.id}: {made}`)
			elseif made then
				wearer.built[slot] = made
			end
		end
	end
	if character.Parent then
		StyleBuild.hideOwn(character, wearer.built.hat ~= nil)
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
end

-- A new character: follow what can change its look (its parts replaced or rescaled, its accessories, its death).
local function dress(player: Player, character: Model)
	forget(player)
	local wearer: Wearer = { character = character, built = {}, connections = {}, sized = {} }
	wearers[player] = wearer
	local function follow(child: Instance)
		if StyleLooks.Nominal[child.Name] and child:IsA("BasePart") and not wearer.sized[child] then
			wearer.sized[child] = true
			table.insert(wearer.connections, child:GetPropertyChangedSignal("Size"):Connect(function()
				schedule(player)
			end))
		end
	end
	for _, child in character:GetChildren() do
		follow(child)
	end
	table.insert(wearer.connections, character.ChildAdded:Connect(function(child)
		if StyleLooks.Nominal[child.Name] then
			follow(child)
			schedule(player)
		elseif child:IsA("Accessory") then
			schedule(player) -- (the avatar's own hat or hair: hidden again under a STYLE hat)
		end
	end))
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") or wearers[player] ~= wearer then
			return
		end
		table.insert(wearer.connections, humanoid.Died:Connect(function()
			takeOff(wearer) -- at once: the body falls apart, loose pieces would drop through the world
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
	if player.Character then
		dress(player, player.Character)
	end
end

-- KitWear's tint hook: the Courier Vest's cloth (the vest slot's "hivis") and the bag's body (the hand slot, its key
-- "id@place") in the worn colour, or their own.
local function tint(player: Player, slot: string, key: string, built: any)
	local style = wardrobe(player)
	if slot == "vest" and key == Config.Courier.VestKit then
		StyleBuild.tint(built.parts, StyleLooks.Vest, if style then Style.worn(style, "vest") else nil)
	elseif slot == "hand" then
		local bagId = KitFit.parseBagKey(key)
		local shares = if bagId then StyleLooks.Bags[bagId] else nil
		if shares then
			StyleBuild.tint(built.parts, shares, if style then Style.worn(style, "bag") else nil)
		end
	end
end

StyleWear.tintKit = tint -- (the offline check, tools/character-art/style-check.luau, calls it on the real KitWear's builds)

-- ── The vehicles ──────────────────────────────────────────────────────────

local function styleCar(car: Vehicles.Car)
	if car.rental or car.lent then
		return
	end
	local def = Economy.findCar(car.id)
	local style = wardrobe(car.owner)
	if not def or def.company or not style then
		return
	end
	if Style.forVehicle("bikepaint", def) then
		StyleBuild.paintBike(car.model, Style.worn(style, "bikepaint"))
		return
	end
	if not Style.forVehicle("wrap", def) then
		return
	end
	local wrap = Style.worn(style, "wrap")
	if wrap then
		StyleBuild.wrap(car.paintParts, wrap)
	else
		for _, p in car.paintParts do
			p:SetAttribute("StylePaint", true) -- (the STYLE preview finds the panels a wrap would take)
		end
	end
	local decal = Style.worn(style, "decal")
	local old = car.model:FindFirstChild(StyleBuild.Decals)
	if decal == nil and old == nil then
		return
	end
	if decal and car.model:GetAttribute("FleetArt") ~= true then
		return -- (only the fleet's own bodies have the panels a decal lies on)
	end
	StyleBuild.decals(car.model, car.chassis, decal)
	if car.model.Parent then
		-- the new parts joined the car's assembly: its driver keeps simulating it (as Vehicles.refreshStats does)
		pcall(function()
			car.chassis:SetNetworkOwner(if car.chauffeured then nil else car.owner)
		end)
	end
end

-- After a change of a slot: the courier's look, KitWear's colours, the live vehicle.
local function apply(player: Player, slot: string)
	if slot == "hat" or slot == "jacket" then
		schedule(player)
	elseif slot == "vest" or slot == "bag" then
		KitWear.retint(player)
	elseif VEHICLE[slot] then
		Vehicles.repaint(player) -- (the garage's paint first, then Vehicles.onStyle: the wrap, the frame, the decal)
	end
end

-- ── The remote ────────────────────────────────────────────────────────────

local function onStyle(player: Player, action: any, arg: any)
	local profile = PlayerData.get(player)
	if not profile or type(action) ~= "string" then
		return
	end
	local style = profile.style
	local slot = ""
	if action == "buy" then
		local def = Style.find(arg)
		if not def then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local shop = if root and root:IsA("BasePart") then Style.shopAt(def, root.Position.X, root.Position.Z) else nil
		local ok, why = Style.canBuyAt(style, def, profile.money, PlayerData.level(player), shop)
		if not ok then
			tell(player, Style.say(why or "money", def))
			return
		end
		if not PlayerData.spend(player, def.price) then
			tell(player, Style.say("money", def))
			return
		end
		style.owned[def.id] = true
		style.worn[def.slot] = def.id
		slot = def.slot
		tell(player, Style.say("bought", def))
	elseif action == "wear" then
		local def = Style.find(arg)
		if not def then
			return
		end
		if not Style.canWear(style, def) then
			tell(player, Style.say("notOwned", def))
			return
		end
		if style.worn[def.slot] == def.id then
			return
		end
		style.worn[def.slot] = def.id
		slot = def.slot
		tell(player, Style.say("wear", def))
	elseif action == "unwear" then
		local found = Style.slot(arg)
		if not found or style.worn[found.id] == nil then
			return
		end
		local was = Style.find(style.worn[found.id])
		style.worn[found.id] = nil
		slot = found.id
		tell(player, Style.say("off", was, found.id))
	else
		return
	end
	PlayerData.notify(player)
	apply(player, slot)
end

StyleWear.handle = onStyle -- (the offline check, tools/character-art/style-check.luau, calls it as the remote would)

-- 6.12: an item given without money (later: the rewards of the daily tasks, events and passes). True when it is new;
-- `wear`: put it on too.
function StyleWear.give(player: Player, id: string, wear: boolean?): boolean
	local profile = PlayerData.get(player)
	local def = Style.find(id)
	if not profile or not def or profile.style.owned[def.id] then
		return false
	end
	profile.style.owned[def.id] = true
	if wear then
		profile.style.worn[def.slot] = def.id
		apply(player, def.slot)
	end
	PlayerData.notify(player)
	return true
end

-- The clerks: a clerk's "Style" prompt (server/ShopClerks.luau) opens the phone's STYLE app on `tab` ("courier" |
-- "vehicle") for that player; without the phone (Marge gives it) a toast says so.
function StyleWear.invite(player: Player, tab: string)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if profile.phone ~= true then
		tell(player, "No phone yet: Marge by the job board gives you one. The looks are in its STYLE app.")
		return
	end
	Net.get("Style"):FireClient(player, "open", tab)
end

function StyleWear.start()
	notice = Net.get("Notice")
	KitWear.tint = tint
	Vehicles.onStyle = function(car: Vehicles.Car)
		local ok, err = pcall(function()
			styleCar(car)
		end)
		if not ok then
			warn(`[StyleWear] {car.owner.Name}'s {car.id}: {err}`)
		end
	end
	local limit = Config.Robust.Limits.Style
	Net.get("Style").OnServerEvent:Connect(function(player: Player, action: any, arg: any)
		if Net.limit(player, "Style", limit) then
			onStyle(player, action, arg)
		end
	end)
	-- a profile loaded (or anything of it changed): the worn looks are compared (most changes are money: nothing to do)
	PlayerData.Changed:Connect(schedule)
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		forget(player)
		queued[player] = nil
	end)
	-- the vehicles already out (a late start), and a vest or a bag KitWear built before the tint hook was set
	for _, car in Vehicles.all() do
		Vehicles.onStyle(car)
	end
	for _, player in Players:GetPlayers() do
		KitWear.retint(player)
	end
end

return StyleWear
