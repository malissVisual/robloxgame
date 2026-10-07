-- 6.4.1: the worn bag built by the real server/KitWear.luau (its build and bagArt, the real ModelArt Builder, the real
-- shared rules) against the property recorder, on the courier's real R15 body (CharacterArt Rig) and on a classic R6
-- body: every bag, in every way it can be worn (Holding.wornAs; a backpack worn or not), empty and full. 6.4 built no
-- bag at all (its slot key went to KitArt as a look); this fails loudly on anything like it. At rest (the joint's
-- Transform the identity, as client/BagSway.luau leaves it hanging): the pivot joined to the right body part, nothing
-- anchored, colliding or near-invisible, every part within 3 studs of the hand (or of the torso it hangs on), the
-- pieces in it shown. Run by tools/character-art/check.py. No physics: Studio decides the rest.
local M = require("./mock")
local Instance, Vector3, CFrame = M.Instance, M.Vector3, M.CFrame
local Geometry = require("./Geometry")
local Rig = require("./Rig")
local Config = require("./Config")
local KitFit = require("./KitFit")
local Holding = require("./Holding")
local Transport = require("./Transport")
local BagFill = require("./BagFill")
local KitWear = require("./KitWear")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- The courier's real R15 body, standing.
local courier = Rig.build(Geometry.spec("courier"))
courier:PivotTo(CFrame.new(0, Geometry.spec("courier").hipHeight + 1, 0))
-- A classic R6 body (its parts' standard sizes), standing.
local r6 = Instance.new("Model")
r6.Name = "R6"
for _, p in {
	{ "HumanoidRootPart", { 2, 2, 1 }, { 0, 3, 0 } },
	{ "Torso", { 2, 2, 1 }, { 0, 3, 0 } },
	{ "Head", { 2, 1, 1 }, { 0, 4.5, 0 } },
	{ "Left Arm", { 1, 2, 1 }, { -1.5, 3, 0 } },
	{ "Right Arm", { 1, 2, 1 }, { 1.5, 3, 0 } },
	{ "Left Leg", { 1, 2, 1 }, { -0.5, 1, 0 } },
	{ "Right Leg", { 1, 2, 1 }, { 0.5, 1, 0 } },
} do
	local part = Instance.new("Part")
	part.Name = p[1]
	part.Size = Vector3.new(p[2][1], p[2][2], p[2][3])
	part.CFrame = CFrame.new(p[3][1], p[3][2], p[3][3])
	part.Parent = r6
end

local bodies = { { model = courier, name = "R15 courier", hand = "LeftHand", torso = "UpperTorso" }, { model = r6, name = "R6", hand = "Left Arm", torso = "Torso" } }
local looks = { "pizza", "bouquet", "mail", "newspaper", "cake", "burger" }
local built, shown = 0, 0

for _, body in bodies do
	local model = body.model
	for _, def in Config.Kit do
		if not Transport.isBag(def) then
			continue
		end
		local places = { Holding.wornAs("bag", def.carry, def.stays, false) :: string }
		local away = Holding.wornAs("gun", def.carry, def.stays, false)
		if away then
			table.insert(places, if def.carry == "hip" then "hipBack" else away)
		end
		for _, place in places do
			for _, packed in { false, true } do
				for _, count in { 0, def.extra or 0 } do
					local key = KitFit.bagKey(def.id, place, packed and (place == "back" or place == "hipBack"))
					local label = `{body.name} {key} with {count}`
					local inBag = table.move(looks, 1, count, 1, {})
					local ok, slot = pcall(KitWear.build, model, "hand", key, { count = count, looks = inBag, key = `{count}` })
					check(`{label}: built without an error`, ok, slot)
					check(`{label}: built`, ok and slot ~= nil)
					if not ok or not slot then
						continue
					end
					built += 1
					local spot = Config.Courier.BagPlaces[place]
					local on = model:FindFirstChild(if spot then body.torso else body.hand)
					local pivot = slot.pivot
					local joint = pivot and pivot:FindFirstChild("BagSwing")
					check(`{label}: the pivot in the body`, pivot ~= nil and pivot.Parent == model and pivot.Name == "KitBagPivot")
					check(`{label}: the pivot never anchored, colliding or weighing`, pivot ~= nil and not pivot.Anchored and not pivot.CanCollide and pivot.Massless)
					check(`{label}: the joint from the {on.Name}`, joint ~= nil and joint.ClassName == "Motor6D" and joint.Part0 == on and joint.Part1 == pivot)
					check(`{label}: the pivot where the joint holds it`, joint ~= nil and ((on.CFrame * joint.C0).Position - pivot.Position).Magnitude < 1e-6)
					check(`{label}: the art in the body`, slot.built.model.Parent == model and slot.built.model.Name == "KitBagArt")
					local far, fill, clear = 0, 0, 0
					for _, part in slot.built.parts do
						far = math.max(far, (part.Position - on.Position).Magnitude)
						if string.match(part.Name, "^Fill%d") then
							fill += 1
						end
						if part.Transparency < 0.5 then
							clear += 1
						end
						local weld = part:FindFirstChild("ArtWeld")
						check(`{label}: {part.Name} welded to the pivot, loose and light`, weld ~= nil and weld.Part0 == pivot and weld.Part1 == part and not part.Anchored and part.Massless and not part.CanCollide and not part.CanQuery and not part.CanTouch)
					end
					check(`{label}: every part within 3 studs of the {on.Name}`, far <= 3, far)
					check(`{label}: most of it clearly visible`, clear >= #slot.built.parts * 0.8, `{clear}/{#slot.built.parts}`)
					check(`{label}: its pieces stick out of it`, (fill > 0) == (count > 0), fill)
					if count > 0 then
						shown += 1
					end
					slot.built.model:Destroy()
					if pivot then
						pivot:Destroy()
					end
				end
			end
			-- its strap, where it has one (on the torso: an R6 body's Torso)
			local key = KitFit.bagKey(def.id, place, false)
			local ok, strap = pcall(KitWear.build, model, "strap", key)
			check(`{body.name} {key}: the strap built without an error`, ok, strap)
			if ok and strap then
				for _, part in strap.built.parts do
					check(`{body.name} {key}: {part.Name} on the {body.torso}`, part:FindFirstChild("ArtWeld").Part0 == model:FindFirstChild(body.torso))
				end
				strap.built.model:Destroy()
			end
		end
	end
	-- the pack and the vest go on an R6 Torso too
	for _, slotId in { { "pack", "backpack" }, { "vest", "kevlar" } } do
		local ok, slot = pcall(KitWear.build, model, slotId[1], slotId[2])
		check(`{body.name} {slotId[2]}: built`, ok and slot ~= nil, slot)
		if ok and slot then
			slot.built.model:Destroy()
		end
	end
end

-- The bag set down on the ground (server/Cargo.luau): its pieces show too.
local base = Instance.new("Part")
base.Name = "BagPivot"
base.Anchored = true
local ground = Instance.new("Model")
base.Parent = ground
local art = KitWear.bagArt(ground, base, "bag", 2, { "pizza", "bouquet" })
local fill = 0
for _, part in (if art then art.parts else {}) do
	if string.match(part.Name, "^Fill%d") then
		fill += 1
	end
end
check("the bag set down shows its pizza box and its bouquet", art ~= nil and fill == #BagFill.pieces(Config.Courier.BagFill.Mouth.bag, 2, 2, { "pizza", "bouquet" }), fill)
check("6.4's key no longer reaches KitArt", pcall(KitWear.build, courier, "hand", "bag@hand"))

print(`bags built: {built} (on both bodies, every place, a backpack or not, empty and full), {shown} with their pieces`)
if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
