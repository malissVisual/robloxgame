-- 6.12: the courier's cosmetics built by the real shared/StyleBuild.luau (and server/StyleWear.luau's tint hook through
-- the real server/KitWear.luau) against the property recorder, on the couriers' body: Roblox's classic blocky R15
-- (6.9), for which server/CharacterArt's native block body "walker" stands in (the classic R15's part sizes and joints;
-- its head a box of 1.6 × 1.35 × 1.4, the classic head's place), and on the native courier's R15 body (the fallback).
-- Every hat and every jacket of Config.Cosmetics: built without an error, every part welded to its body part, loose,
-- massless and out of the physics; a hat's crown wider than the head and over its top, its rim above the eyes, near
-- the head; a jacket's shells round their parts (thin), its details on them, its torso under the Courier Vest's cloth.
-- A replaced head (the avatar loading) is noticed; the player's own hat and hair hide under a STYLE hat and come back.
-- The vest's and every bag's colour go on (and off) through KitWear's tint hook. 6.12, the clerks: the Style remote's
-- "buy" (StyleWear.handle) only where the look is sold, by where the character stands; wear and take off anywhere.
-- Run by tools/character-art/check.py.
local M = require("./mock")
local Instance, Vector3, CFrame = M.Instance, M.Vector3, M.CFrame
local Geometry = require("./Geometry")
local Rig = require("./Rig")
local Config = require("./Config")
local KitFit = require("./KitFit")
local Style = require("./Style")
local StyleLooks = require("./StyleLooks")
local StyleBuild = require("./StyleBuild")
local KitWear = require("./KitWear")
local PlayerData = require("./StylePlayerData")
local StyleWear = require("./StyleWear")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- A part's corners in `frame`'s space: (lo, hi).
local function box(frame: any, part: any): (any, any)
	local b = StyleBuild.box(frame, part)
	return b.min, b.max
end

local function body(id: string): any
	local spec = Geometry.spec(id)
	local model = Rig.build(spec)
	model:PivotTo(CFrame.new(0, spec.hipHeight + 1, 0))
	return model
end

local bodies = {
	{ model = body("walker"), name = "classic R15 (walker stand-in)" },
	{ model = body("courier"), name = "native courier" },
}

local built, parts = 0, 0
local lowest, widest = math.huge, 0
for _, entry in bodies do
	local model = entry.model
	local head = model:FindFirstChild("Head")
	for _, def in Config.Cosmetics.Items do
		if def.slot ~= "hat" and def.slot ~= "jacket" then
			continue
		end
		local label = `{entry.name} {def.id}`
		local ok, made = pcall(StyleBuild.courier, model, def)
		check(`{label}: built without an error`, ok, made)
		check(`{label}: built`, ok and made ~= nil)
		if not ok or not made then
			continue
		end
		built += 1
		parts += #made.parts
		check(`{label}: in the character as {StyleBuild.Names[def.slot]}`, made.model.Parent == model and made.model.Name == StyleBuild.Names[def.slot] and made.model:GetAttribute("StyleLook") == def.id)
		check(`{label}: still fits`, StyleBuild.fits(made))
		for _, part in made.parts do
			local weld = part:FindFirstChild("StyleWeld")
			local bone = weld and weld.Part0
			check(`{label}: {part.Name} welded to a body part`, weld ~= nil and weld.ClassName == "WeldConstraint" and weld.Part1 == part and bone ~= nil and bone.Parent == model)
			check(`{label}: {part.Name} loose, light and out of the physics`, not part.Anchored and part.Massless and not part.CanCollide and not part.CanQuery and not part.CanTouch and not part.CastShadow)
		end
		if def.slot == "hat" then
			-- in the head's space: the crown wider than the head and over its top, the rim above the eyes
			local h = head.Size
			local crown, low, high, far = 0, math.huge, -math.huge, 0
			for _, part in made.parts do
				local lo, hi = box(head.CFrame, part)
				high = math.max(high, hi[2])
				far = math.max(far, (part.Position - head.Position).Magnitude)
				if part.Shape == "Cylinder" and part.Size.X >= 0.25 then
					crown = math.max(crown, math.min(part.Size.Y, part.Size.Z))
					low = math.min(low, lo[2])
				end
			end
			check(`{label}: the crown wider than the head`, crown >= math.max(h.X, h.Z) * 0.92, `{crown} vs {h.X} x {h.Z}`)
			check(`{label}: over the head's top`, high > h.Y / 2 + 0.03, `{high} vs {h.Y / 2}`)
			check(`{label}: its rim above the eyes, on the head`, low > h.Y * 0.08 and low < h.Y / 2 - 0.05, low)
			check(`{label}: near the head`, far < math.max(h.X, h.Y, h.Z) * 1.4, far)
			lowest = math.min(lowest, low / h.Y)
			widest = math.max(widest, far)
		else
			-- the shells round their parts, thin; the details on them
			for _, part in made.parts do
				local weld = part:FindFirstChild("StyleWeld")
				local bone = weld and weld.Part0
				if not bone then
					continue
				end
				local lo, hi = box(bone.CFrame, part)
				local half = bone.Size / 2
				if string.match(part.Name, "^Jacket") or string.match(part.Name, "^Sleeve") or string.match(part.Name, "^Forearm") then
					local thick = math.max(-lo[1] - half.X, hi[1] - half.X, -lo[3] - half.Z, hi[3] - half.Z)
					check(`{label}: {part.Name} round the {bone.Name}`, -lo[1] >= half.X and hi[1] >= half.X and -lo[3] >= half.Z and hi[3] >= half.Z)
					check(`{label}: {part.Name} thin`, thick <= 0.06, thick)
				else
					-- a detail: within 0.45 studs of its part's faces
					local out = math.max(-lo[1] - half.X, hi[1] - half.X, -lo[2] - half.Y, hi[2] - half.Y, -lo[3] - half.Z, hi[3] - half.Z)
					check(`{label}: {part.Name} on the {bone.Name}`, out <= 0.45, out)
				end
			end
			-- under the Courier Vest's cloth (the real KitWear's vest on this body)
			local vest = KitWear.build(model, "vest", Config.Courier.VestKit)
			local torso = made.model:FindFirstChild("JacketTorso")
			local frame = model:FindFirstChild("UpperTorso").CFrame
			if vest and torso then
				local vestFront, vestBack = 0, 0
				for _, part in vest.built.parts do
					if string.match(part.Name, "^Vest") then
						local lo, hi = box(frame, part)
						vestFront, vestBack = math.min(vestFront, lo[3]), math.max(vestBack, hi[3])
					end
				end
				local lo, hi = box(frame, torso)
				check(`{label}: the torso's shell under the vest's cloth`, lo[3] > vestFront and hi[3] < vestBack, `{lo[3]} > {vestFront}, {hi[3]} < {vestBack}`)
				vest.built.model:Destroy()
			end
		end
		made.model:Destroy()
	end
end

-- A replaced head (the avatar's own going on) is noticed; the build goes on the new one.
do
	local model = bodies[1].model
	local cap = Style.find("cap_red") :: any
	local made = StyleBuild.courier(model, cap) :: any
	local old = model:FindFirstChild("Head")
	local new = Instance.new("Part")
	new.Name = "Head"
	new.Size = Vector3.new(1.2, 1.2, 1.2)
	new.CFrame = old.CFrame
	old.Parent = nil
	new.Parent = model
	check("a replaced head: the hat no longer fits", not StyleBuild.fits(made))
	made.model:Destroy()
	local again = StyleBuild.courier(model, cap) :: any
	check("… and goes on the new head", again ~= nil and again.parts[1]:FindFirstChild("StyleWeld").Part0 == new)
	again.model:Destroy()
	new.Parent = nil
	old.Parent = model
end

-- The player's own hat and hair hide under a STYLE hat and come back; glasses stay.
do
	local model = bodies[1].model
	local function accessory(name: string, point: string, transparency: number): any
		local a = Instance.new("Accessory")
		a.Name = name
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Transparency = transparency
		local at = Instance.new("Attachment")
		at.Name = point
		at.Parent = handle
		handle.Parent = a
		a.Parent = model
		return handle
	end
	local hat = accessory("OwnHat", "HatAttachment", 0)
	local hair = accessory("OwnHair", "HairAttachment", 0.2)
	local glasses = accessory("Glasses", "FaceFrontAttachment", 0)
	StyleBuild.hideOwn(model, true)
	check("own hat and hair hidden under a STYLE hat", hat.Transparency == 1 and hair.Transparency == 1 and glasses.Transparency == 0)
	StyleBuild.hideOwn(model, true)
	StyleBuild.hideOwn(model, false)
	check("… and back as they were (twice hidden, once shown)", hat.Transparency == 0 and hair.Transparency == 0.2 and hat:GetAttribute("StyleHid") == nil)
	for _, h in { hat, hair, glasses } do
		h.Parent.Parent = nil
	end
end

-- The Courier Vest's colour and the bags' through KitWear's tint hook (server/StyleWear.luau's, on the real builds).
local tinted = 0
do
	local model = bodies[1].model
	local player = { Name = "Courier" }
	local profile = { style = Style.empty(), money = 0 }
	PlayerData.profile = profile
	local function rgb(c: any): string
		return string.format("%d,%d,%d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
	end
	local vest = KitWear.build(model, "vest", Config.Courier.VestKit) :: any
	local own: { [string]: string } = {}
	for _, part in vest.built.parts do
		own[part.Name] = rgb(part.Color)
	end
	for _, def in Style.items("vest") do
		profile.style.owned[def.id] = true
		profile.style.worn.vest = def.id
		StyleWear.tintKit(player :: any, "vest", Config.Courier.VestKit, vest.built)
		for _, part in vest.built.parts do
			local share = StyleLooks.Vest[part.Name]
			if share then
				check(`vest {def.id}: {part.Name} in its colour`, rgb(part.Color) == rgb(M.Color3.fromRGB(math.floor(def.color[1] * share), math.floor(def.color[2] * share), math.floor(def.color[3] * share))))
				tinted += 1
			else
				check(`vest {def.id}: {part.Name} keeps its own colour`, rgb(part.Color) == own[part.Name])
			end
		end
	end
	profile.style.worn.vest = nil
	StyleWear.tintKit(player :: any, "vest", Config.Courier.VestKit, vest.built)
	for _, part in vest.built.parts do
		check(`vest off: {part.Name} back to its own colour`, rgb(part.Color) == own[part.Name])
	end
	vest.built.model:Destroy()
	local bag = Style.find("bag_mint") :: any
	profile.style.owned[bag.id] = true
	for bagId, shares in StyleLooks.Bags do
		local key = KitFit.bagKey(bagId, "hand")
		local slot = KitWear.build(model, "hand", key, { count = 0, looks = {}, key = "" }) :: any
		check(`bag {bagId}: built`, slot ~= nil)
		if not slot then
			continue
		end
		profile.style.worn.bag = bag.id
		StyleWear.tintKit(player :: any, "hand", key, slot.built)
		local body = 0
		for _, part in slot.built.parts do
			if shares[part.Name] then
				body += 1
				tinted += 1
				check(`bag {bagId}: {part.Name} in mint`, rgb(part.Color) == rgb(M.Color3.fromRGB(math.floor(bag.color[1] * shares[part.Name]), math.floor(bag.color[2] * shares[part.Name]), math.floor(bag.color[3] * shares[part.Name]))))
			end
		end
		check(`bag {bagId}: its body found`, body >= 1, body)
		profile.style.worn.bag = nil
		StyleWear.tintKit(player :: any, "hand", key, slot.built)
		for _, part in slot.built.parts do
			check(`bag {bagId} off: {part.Name} has no STYLE colour left`, part:GetAttribute("StyleBase") == nil)
		end
		slot.built.model:Destroy()
		if slot.pivot then
			slot.pivot:Destroy()
		end
	end
end

-- 6.12, the clerks (the owner: "things are bought only from the NPCs in the shops, for the vibe"): the Style remote's
-- handler on the server, with the character's HumanoidRootPart at the gear stall, at Wrench Garage, at the BIKES counter
-- and far from any shop (Map.Shops; the money through PlayerData.spend).
local bought = 0
do
	local Map = require("./Map")
	local repainted = 0
	local Vehicles = require("./Stub") :: any -- (StyleWear's Vehicles here: a vehicle look bought repaints your cars)
	Vehicles.repaint = function()
		repainted += 1
	end
	local character = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = character
	local player = { Name = "Buyer", Character = character }
	local profile = { style = Style.empty(), money = 5000 }
	PlayerData.profile = profile
	local function stand(x: number, z: number)
		root.CFrame = CFrame.new(x, 3, z)
	end
	local function at(id: string)
		stand(Map.Shops[id].x, Map.Shops[id].z)
	end
	local function buy(id: string): boolean
		local money = profile.money
		StyleWear.handle(player :: any, "buy", id)
		local def = Style.find(id) :: any
		local got = profile.style.owned[id] == true
		if got then
			bought += 1
			check(`{id}: paid and worn`, profile.money == money - def.price and profile.style.worn[def.slot] == id, profile.money)
		else
			check(`{id}: refused, no money taken`, profile.money == money)
		end
		return got
	end
	at("mechanic")
	check("a vest colour at Wrench Garage: refused", not buy("vest_orange"))
	stand(1e5, 1e5)
	check("a bag colour far from any shop: refused", not buy("bag_black"))
	at("supplies")
	check("a vest colour at Dot's GEAR counter: bought", buy("vest_orange"))
	at("bags")
	check("a bag colour at Nell's BAGS counter, beside Dot: bought", buy("bag_black"))
	check("a wrap at the gear stall: refused", not buy("wrap_teal"))
	at("bikes")
	check("a wrap at Dead End Motors' BIKES counter (6.12.7; Spoke & Chain before): refused", not buy("wrap_teal"))
	check("bike paint at Kip's BIKES counter: bought", buy("bike_mint"))
	at("mechanic")
	check("bike paint at Wrench Garage too: bought", buy("bike_sky"))
	check("a vehicle look bought: your cars repainted", repainted == 2, repainted)
	check("a reward at its shop: never", not buy("vest_gold"))
	stand(1e5, 1e5)
	StyleWear.handle(player :: any, "unwear", "vest")
	check("TAKE OFF anywhere", profile.style.worn.vest == nil and profile.style.owned.vest_orange == true)
	StyleWear.handle(player :: any, "wear", "vest_orange")
	check("WEAR anywhere", profile.style.worn.vest == "vest_orange")
	player.Character = nil :: any
	check("no character: no purchase", not buy("vest_blue"))
end

print(`style looks built: {built} (every hat and jacket on both bodies, {parts} parts); a crown's rim at {string.format("%.2f", lowest)} of the head's height at the lowest, a part {string.format("%.2f", widest)} from the head's middle at the farthest; {tinted} vest and bag parts dyed and undyed; {bought} looks bought only at their shops, refused elsewhere`)
if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
