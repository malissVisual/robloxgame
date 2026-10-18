--!strict
-- 8.3 SANDBOX: the PAINT shop on the server (the owner: players earn money from their collection, give them a way to
-- make their van their own). Config.VanPaint has the catalogue and the prices, shared/VanPaintRules.luau the rules,
-- shared/VanLook.luau paints a van, client/VanPaintUi.luau is the window. Cosmetic only: a van's collision, cargo bay
-- and doors never change.
--   * What you own and wear is in the save (profile.vanPaint = { owned, worn }, server/PlayerData.luau: read only from a
--     real save written with its flag). Each item is bought once (PlayerData.spend, the reason "VanPaint", the item's id
--     its SKU) and kept for good; it goes on the van at once. Wearing an item you own is free.
--   * Every van of a player's is painted as it is built (the hook Vehicles.onStyle: a run's van, a round's, 10.6 the
--     only ways one is parked), and again when its owner wears something else: for everybody to see (the server's
--     parts and attributes replicate). The owner's Blender look (server/SprinterMesh.luau) takes it too.
--   * The 🎨 Paint van prompt (the ProximityPrompt "PaintPrompt" on the chassis' Attachment "PaintPoint": the driver's
--     side of the cargo box, Config.VanPaint.Prompt.At) is on every player's van, its owner's only (client/CargoPrompts
--     .luau hides it from the others: Config.Cargo.PromptTag, CargoOwner), enabled while the van stands at its plot's
--     vanSpot (looked at every Prompt.Every s; checked again when it is pressed). It opens the window.
--   * Collector gold and the like unlock with a collection book milestone the book has paid (profile.collectionBookPaid,
--     server/CollectionBook.luau): the window's locks follow (a state goes out when the paid milestones changed).
--
--   VanPaint.saved(player)           a copy of profile.vanPaint (nil before the save loads)
--   VanPaint.buy(player, id)         → ok, why: bought (VanPaintRules.check: known, not yours yet, unlocked, the money),
--                                    then worn
--   VanPaint.wear(player, id)        → ok, why: an item you own on your van
--   VanPaint.open(player)            the prompt's: the state, then { kind = "open" }
--   VanPaint.paint(car)              that van in its owner's look, its prompt made (a player's sandbox van only)
--   VanPaint.repaint(player)         the player's van out now in their look
--   VanPaint.atHome(player, car)     is the van at the player's plot's vanSpot (Prompt.Home), standing (Prompt.Still)?
--   VanPaint.admin(player, what)     the admin panel's SANDBOX tab: "all" every item owned (free), "reset" nothing
--                                    bought and the factory's look → what to say
--   VanPaint.start()                 the remote, the hook on Vehicles.onStyle, the prompts' loop, joining and leaving
--
-- The "VanPaint" remote (Config.Robust.Limits.VanPaint requests a second; every input checked, a refusal comes back as a
-- Notice with its why):
--   client → server   { kind = "state" } | { kind = "buy", id } | { kind = "wear", id }
--   server → client   { kind = "state", owned = { ids }, worn = { paint, livery }, money, paid = { milestone ids } }
--                     when the save has loaded, when asked, after every change (once a frame) and when the book paid a
--                     milestone; { kind = "open" } opens the window; { kind = "bought", id } | { kind = "worn", id }

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.VanPaintRules)
local VanLook = require(Shared.VanLook)
local PlayerData = require(script.Parent.PlayerData)
local Vehicles = require(script.Parent.Vehicles)
local SandboxPlots = require(script.Parent.SandboxPlots)

local VanPaint = {}

local T = Config.VanPaint
local remote: RemoteEvent? = nil
local notice: RemoteEvent? = nil
local known: { [Player]: boolean } = {} -- the save has loaded (the first state went out)
local pushing: { [Player]: boolean } = {} -- a state push waits for the frame's end
local paidKey: { [Player]: string } = {} -- the paid milestones the last state carried
local started = false

local function say(player: Player, text: string)
	local target = notice
	if target and player.Parent then
		target:FireClient(player, text)
	end
end

-- The player's paint in their profile (nil: no save yet); a profile without one gets the empty one.
local function savedOf(player: Player): Rules.Saved?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	if type(profile.vanPaint) ~= "table" then
		profile.vanPaint = Rules.empty()
	end
	return profile.vanPaint
end

-- The collection book's paid milestones ({ [id] = true }; none before the save loads).
local function paidOf(player: Player): { [string]: boolean }
	local profile = PlayerData.get(player)
	local paid = if profile then profile.collectionBookPaid else nil
	return if type(paid) == "table" then paid else {}
end

local function sorted(set: { [string]: boolean }): { string }
	local list: { string } = {}
	for id, on in set do
		if on == true and type(id) == "string" then
			table.insert(list, id)
		end
	end
	table.sort(list)
	return list
end

local function sendState(player: Player)
	pushing[player] = nil
	local profile = PlayerData.get(player)
	local saved = savedOf(player)
	local target = remote
	if not profile or not saved or not target or not player.Parent then
		return
	end
	local paid = sorted(paidOf(player))
	paidKey[player] = table.concat(paid, ",")
	target:FireClient(player, {
		kind = "state",
		owned = sorted(saved.owned),
		worn = { paint = saved.worn.paint, livery = saved.worn.livery },
		money = profile.money,
		paid = paid,
	})
end

-- The state goes out once at the frame's end, however many changes it had.
local function pushState(player: Player)
	if pushing[player] then
		return
	end
	pushing[player] = true
	task.defer(function()
		if pushing[player] then
			sendState(player)
		end
	end)
end

-- A player's own sandbox van (the Sprinter: 10.6 every van is one).
local function isVan(car: Vehicles.Car): boolean
	return car.model:GetAttribute("SprinterArt") ~= nil or car.id == Config.Sandbox.Van
end

local function promptOf(car: Vehicles.Car): ProximityPrompt?
	local point = car.chassis and car.chassis:FindFirstChild("PaintPoint")
	local prompt = point and point:FindFirstChild("PaintPrompt")
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

function VanPaint.atHome(player: Player, car: Vehicles.Car): boolean
	local plot = SandboxPlots.of(player)
	local chassis = car.chassis
	if not plot or car.wrecked or not chassis or not chassis.Parent then
		return false
	end
	local spot = plot.vanSpot
	local at = chassis.Position
	local dx, dz = at.X - spot.x, at.Z - spot.z
	if dx * dx + dz * dz > T.Prompt.Home * T.Prompt.Home then
		return false
	end
	local velocity: any = chassis.AssemblyLinearVelocity
	return typeof(velocity) ~= "Vector3" or velocity.Magnitude <= T.Prompt.Still
end

local function refreshPrompt(car: Vehicles.Car)
	local prompt = promptOf(car)
	if prompt then
		local on = VanPaint.atHome(car.owner, car)
		if prompt.Enabled ~= on then
			prompt.Enabled = on
		end
	end
end

-- The 🎨 Paint van prompt on the van (once): its owner's only, pressed at home it opens the window.
local function makePrompt(car: Vehicles.Car)
	if promptOf(car) or not car.chassis then
		return
	end
	local at = T.Prompt.At
	local point = Instance.new("Attachment")
	point.Name = "PaintPoint"
	point.Position = Vector3.new(at[1], at[2] - Config.Sprinter.Bay.Floor + car.chassis.Size.Y / 2, at[3]) -- (the van's frame from the chassis' middle)
	point.Parent = car.chassis
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PaintPrompt"
	prompt.ActionText = "🎨 Paint van"
	prompt.ObjectText = "PAINT SHOP"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = T.Prompt.Reach
	prompt.RequiresLineOfSight = true -- (never offered through the van's wall to somebody in the cargo bay)
	prompt.Enabled = false
	prompt:SetAttribute("CargoOwner", car.owner.UserId) -- (the owner's only: client/CargoPrompts.luau hides it from others)
	CollectionService:AddTag(prompt, Config.Cargo.PromptTag)
	prompt.Parent = point
	prompt.Triggered:Connect(function(by: Player)
		if by ~= car.owner then
			return
		end
		if not VanPaint.atHome(by, car) then
			say(by, "Park your van at your warehouse to paint it.")
			return
		end
		VanPaint.open(by)
	end)
	refreshPrompt(car)
end

-- ── The API ────────────────────────────────────────────────────────────────

function VanPaint.saved(player: Player): Rules.Saved?
	local saved = savedOf(player)
	return if saved then { owned = table.clone(saved.owned), worn = table.clone(saved.worn) } else nil
end

function VanPaint.paint(car: Vehicles.Car)
	if not isVan(car) then
		return
	end
	local saved = savedOf(car.owner)
	VanLook.apply(car.model, Rules.look(if saved then saved.worn else Rules.Default), { paintParts = car.paintParts })
	makePrompt(car)
end

function VanPaint.repaint(player: Player)
	local car = Vehicles.get(player)
	if car then
		VanPaint.paint(car)
	end
end

function VanPaint.buy(player: Player, id: any): (boolean, string?)
	local profile = PlayerData.get(player)
	local saved = savedOf(player)
	if not profile or not saved then
		return false, "Your save isn't loaded yet."
	end
	local ok, why, price = Rules.check(saved, id, profile.money, paidOf(player))
	local item = Rules.find(id)
	if not ok or not item then
		sendState(player) -- (the window showed something stale: it is drawn again)
		return false, why
	end
	if price > 0 and not PlayerData.spend(player, price, "VanPaint", item.id) then
		return false, `{item.name} costs {Rules.money(price)}: you have {Rules.money(profile.money)}.`
	end
	Rules.buy(saved, item.id)
	VanPaint.repaint(player)
	pushState(player)
	local target = remote
	if target then
		target:FireClient(player, { kind = "bought", id = item.id })
	end
	return true, nil
end

function VanPaint.wear(player: Player, id: any): (boolean, string?)
	local saved = savedOf(player)
	if not saved then
		return false, "Your save isn't loaded yet."
	end
	local ok, why = Rules.wear(saved, id)
	if not ok then
		sendState(player)
		return false, why
	end
	VanPaint.repaint(player)
	pushState(player)
	local target = remote
	if target then
		target:FireClient(player, { kind = "worn", id = id })
	end
	return true, nil
end

function VanPaint.open(player: Player)
	if not savedOf(player) then
		say(player, "Your save isn't loaded yet.")
		return
	end
	sendState(player)
	local target = remote
	if target then
		target:FireClient(player, { kind = "open" })
	end
end

function VanPaint.admin(player: Player, what: string): string
	local profile = PlayerData.get(player)
	local saved = savedOf(player)
	if not profile or not saved then
		return "ADMIN: no save loaded (the paints are in it)."
	end
	if what == "all" then
		local all = Rules.all()
		local count = 0
		for id in all.owned do
			saved.owned[id] = true
			count += 1
		end
		pushState(player)
		return `ADMIN: every paint and livery of the PAINT shop is yours ({count} items): wear them at your van.`
	end
	profile.vanPaint = Rules.empty()
	VanPaint.repaint(player)
	pushState(player)
	return "ADMIN: the paints reset: nothing bought, your van in Deliveros cream with the Deliveros classic stripe."
end

-- ── Joining, leaving, the remote, the prompts ─────────────────────────────

-- PlayerData.Changed: the save loaded (the first state), or the money moved, maybe a milestone paid (the locks).
local function onChanged(player: Player)
	if not player.Parent or not savedOf(player) then
		return
	end
	if not known[player] then
		known[player] = true
		pushState(player)
	elseif table.concat(sorted(paidOf(player)), ",") ~= paidKey[player] then
		pushState(player)
	end
end

local function left(player: Player)
	known[player] = nil
	pushing[player] = nil
	paidKey[player] = nil
end

local function onRemote(player: Player, message: any)
	if not Net.limit(player, "VanPaint", Config.Robust.Limits.VanPaint) then
		return
	end
	if type(message) ~= "table" then
		return
	end
	local ok, why = true, nil
	if message.kind == "state" then
		sendState(player)
	elseif message.kind == "buy" then
		ok, why = VanPaint.buy(player, message.id)
	elseif message.kind == "wear" then
		ok, why = VanPaint.wear(player, message.id)
	end
	if not ok and why then
		say(player, why)
	end
end

-- Every few tenths of a second: each van's prompt on while it stands at home (a van built without the hook: painted).
local function watchPrompts()
	while true do
		task.wait(T.Prompt.Every)
		for _, player in Players:GetPlayers() do
			local car = Vehicles.get(player)
			if car and isVan(car) then
				if promptOf(car) then
					refreshPrompt(car)
				else
					local ok, err = pcall(function(): any
						VanPaint.paint(car)
						return nil
					end)
					if not ok then
						warn(`[VanPaint] painting {player.Name}'s van failed: {err}`)
					end
				end
			end
		end
	end
end

function VanPaint.start()
	if started then
		return
	end
	started = true
	local target = Net.get("VanPaint")
	remote = target
	notice = Net.get("Notice")
	target.OnServerEvent:Connect(onRemote)
	PlayerData.Changed:Connect(onChanged)
	for _, player in Players:GetPlayers() do
		onChanged(player)
	end
	Players.PlayerRemoving:Connect(left)
	-- every van as it is built (after its paint and kit; before it is in the world): its owner's look and its prompt
	local before = Vehicles.onStyle
	Vehicles.onStyle = function(car: Vehicles.Car)
		if before then
			before(car)
		end
		local ok, err = pcall(function(): any
			VanPaint.paint(car)
			return nil
		end)
		if not ok then
			warn(`[VanPaint] painting a van failed: {err}`)
		end
	end
	task.spawn(watchPrompts)
	-- 9.7 runs: the lobby's PAINT shop booth (server/LobbyWorld.luau: its counter's prompt, attribute PaintShop) opens the
	-- window for anybody with a save, no van needed (the truck wears it in the runs)
	local world = workspace:FindFirstChild("Sandbox")
	if world then
		for _, d in world:GetDescendants() do
			if d:IsA("ProximityPrompt") and d:GetAttribute("PaintShop") == true then
				VanPaint.booth(d)
			end
		end
	end
end

-- 9.7 runs: a PAINT shop booth's prompt opens the window (the lobby's: no van parked there any more).
function VanPaint.booth(prompt: ProximityPrompt)
	prompt.Triggered:Connect(function(player: Player)
		VanPaint.open(player)
	end)
end

return VanPaint
