-- Native rig/kit compatibility, connected R15 skeleton and the shared locomotion state contract.
local Geometry = require("./CharacterGeometry")
local Motion = require("./CourierMotion")
local Config = require("./Config")
local KitFit = require("./KitFit")
local count = 0
local function check(ok: boolean, message: string)
	assert(ok, message)
	count += 1
end
local function near(a: number, b: number): boolean return math.abs(a - b) < 1e-6 end

for _, id in Geometry.ids do
	local def = Config.Zombies[id]
	local spec = if def then Geometry.spec(id, def.scale, def.skin, def.shirt, def.pants) else Geometry.spec(id)
	check(#spec.bones == 16 and #spec.joints == 15, id .. ": complete R15")
	check(#spec.bones + #spec.pieces <= spec.budget, id .. ": part budget")
	local bones, names, children = {}, {}, {}
	for _, b in spec.bones do
		check(not bones[b.name], id .. ": unique bone")
		bones[b.name] = b
		for i = 1, 3 do check(b.size[i] > 0 and b.size[i] < 15, id .. ": finite body size") end
	end
	children.HumanoidRootPart = true
	for _, j in spec.joints do
		check(bones[j.parent] ~= nil and bones[j.child] ~= nil, id .. ": joint endpoints")
		check(not names[j.name] and not children[j.child], id .. ": no duplicate joint or parent")
		names[j.name], children[j.child] = true, true
	end
	-- Follow the parent chain for every bone: no disconnected island or cycle.
	for _, b in spec.bones do
		local current, hops = b.name, 0
		while current ~= "HumanoidRootPart" do
			local nextParent = nil
			for _, j in spec.joints do if j.child == current then nextParent = j.parent end end
			check(nextParent ~= nil and hops < 15, id .. ": connected acyclic skeleton")
			current = nextParent
			hops += 1
		end
	end
	for _, p in spec.pieces do
		check(bones[p.attach] ~= nil and not names[p.name], id .. ": unique attached decoration")
		names[p.name] = true
		for i = 1, 3 do check(p.size[i] >= 0.02 and p.size[i] < 15, id .. ": valid art size") end
	end
	local root, foot = bones.HumanoidRootPart, bones.LeftFoot
	check(near(-foot.at[2] + foot.size[2] / 2, root.size[2] / 2 + spec.hipHeight), id .. ": sole matches hip clearance")
	if id == "courier" then
		-- 6.7: the realistic body's proportions (the owner: "not blocks any more"): 5.6 – 6 studs from the sole to the
		-- crown, the head about 1/6.5 of it, slim arms (0.6 – 0.7) and legs (0.75 – 0.85 deep), forearms nearly as long as
		-- the upper arms, the fingertips at mid-thigh.
		local function top(b): number return b.at[2] + b.size[2] / 2 end
		local function bottom(b): number return b.at[2] - b.size[2] / 2 end
		local sole = bottom(bones.LeftFoot)
		local tall = top(bones.Head) - sole
		check(tall >= 5.6 and tall <= 6, "a grown-up's height")
		check(bones.Head.size[2] / tall > 1 / 7 and bones.Head.size[2] / tall < 1 / 6, "the head about 1/6.5 of the height")
		check(bones.RightUpperArm.size[1] >= 0.6 and bones.RightUpperArm.size[1] <= 0.7, "slim upper arms")
		check(bones.RightLowerArm.size[1] < bones.RightUpperArm.size[1], "the forearms slimmer still")
		check(bones.RightUpperLeg.size[3] >= 0.75 and bones.RightUpperLeg.size[3] <= 0.85, "slim legs")
		check(bones.RightLowerArm.size[2] > 0.8 * bones.RightUpperArm.size[2], "long forearms")
		local tips = bottom(bones.RightHand) - 0.25 - sole
		check(tips > top(bones.RightLowerLeg) - sole and tips < top(bones.RightUpperLeg) - sole, "the fingertips at mid-thigh")
		check(bones.LeftUpperLeg.at[1] + bones.LeftUpperLeg.size[1] / 2 < bones.RightUpperLeg.at[1] - bones.RightUpperLeg.size[1] / 2, "a gap between the legs")
		-- The grips in both fists (where a handle sits: under the palm, among the fingers), the fist's pieces there.
		for _, hand in { "LeftHand", "RightHand" } do
			local grip = spec.grips[hand]
			check(grip ~= nil and grip[2] < -bones[hand].size[2] / 2 and grip[2] > -bones[hand].size[2] / 2 - 0.25, hand .. ": its grip under the palm")
			local s = if hand == "LeftHand" then "L" else "R"
			check(names["Fingers" .. s] and names["Thumb" .. s], hand .. ": fingers and a thumb")
		end
		check(spec.grips.RightHand[1] < 0 and spec.grips.LeftHand[1] > 0, "the palms face the body")
		-- The purchased kit is authored on the block body (KitFit.Nominal) and scaled onto this one, unclamped, per axis;
		-- the fist takes the hand's one factor and holds the art in its palm (KitFit.Palm).
		for bone, nominal in KitFit.Nominal do
			if string.match(bone, "Hand$") then
				local f = KitFit.factors(bone, bones[bone].size)
				check(f[1] == KitFit.HandMin and f[1] < KitFit.SlabHand and KitFit.Palm[bone] ~= nil, bone .. ": the art in the palm")
			else
				local f = KitFit.factors(bone, bones[bone].size)
				for i = 1, 3 do
					check(near(f[i], bones[bone].size[i] / nominal[i]) and f[i] > KitFit.Min and f[i] < KitFit.Max, "purchased kit fits " .. bone)
				end
			end
		end
		check(names.JacketL and names.CapBrimBack and not names.Backpack, "uniform does not grant paid gear")
		-- 6.0.1: the red vest is bought kit (Config.Kit "hivis"): not on the body; the jacket under it is hidden by it
		-- (6.7: the vest as worn, KitFit-scaled onto this torso).
		check(not names.VestL and not names.VestBack and not names.DispatchBadge, "a new courier starts without the vest")
		local vest = Geometry.hivis()
		check(#vest == 11 and #spec.bones + #spec.pieces + #vest <= spec.budget, "the vest: Codex's 11 pieces, within the budget worn")
		local worn = KitFit.fit(vest, { UpperTorso = KitFit.factors("UpperTorso", bones.UpperTorso.size) })
		local boxes = {}
		for _, v in worn do
			check(v.attach == "UpperTorso" and not names[v.name], "the vest's pieces on the torso, their own names")
			if not v.turn then table.insert(boxes, v) end
		end
		local function inside(p, v): boolean
			for i = 1, 3 do
				if p.at[i] - p.size[i] / 2 < v.at[i] - v.size[i] / 2 - 1e-9 or p.at[i] + p.size[i] / 2 > v.at[i] + v.size[i] / 2 + 1e-9 then
					return false
				end
			end
			return true
		end
		for _, p in spec.pieces do
			if string.match(p.name, "^Jacket") or string.match(p.name, "^PocketFlap") then
				local hidden = false
				for _, v in boxes do hidden = hidden or inside(p, v) end
				check(hidden and p.attach == "UpperTorso", p.name .. " lies inside a vest panel (worn, the vest covers it)")
			end
		end
		local torso = bones.UpperTorso
		for _, v in boxes do
			check(math.abs(v.at[3]) - v.size[3] / 2 >= torso.size[3] / 2 - 1e-6, v.name .. " lies on the torso, not in it")
		end
		check(Geometry.hivis()[1] ~= vest[1] and Geometry.hivis()[1].color ~= vest[1].color, "fresh vest tables")
	elseif id == "person" then
		-- 6.7: the people (server/Npcs.luau) wear the same body; every part names the colour their look gives it.
		for _, b in spec.bones do check(b.paint ~= nil, "person: " .. b.name .. " takes a colour") end
		for _, p in spec.pieces do
			check(p.paint ~= nil or string.match(p.name, "^Eye") ~= nil or p.name == "Mouth", "person: " .. p.name .. " takes a colour")
		end
		local kid = Geometry.spec("person", 0.75)
		check(near(kid.hipHeight, spec.hipHeight * 0.75) and near(kid.grips.RightHand[2], spec.grips.RightHand[2] * 0.75), "a kid: the same body, smaller")
	elseif def then
		for i = 1, 3 do check(bones.Head.color[i] == def.skin[i], "enemy palette remains type-readable") end
	end
	local original = spec.bones[1].size[1]
	spec.bones[1].size[1] = 999
	local fresh = if def then Geometry.spec(id, def.scale) else Geometry.spec(id)
	check(fresh.bones[1].size[1] == original, "fresh specs do not mutate another spawn")
end
check(not pcall(function() Geometry.spec("bandit") end), "human bandits keep their separate art path")

local function pose(state: string, speed: number, vy: number, seated: boolean, expected: string?, expectedRate: number?)
	local selected, rate = Motion.select(state, speed, vy, seated)
	check(selected == expected, "motion " .. state .. ": " .. tostring(expected))
	check(rate >= 0 and rate <= 2, "bounded playback rate")
	if expectedRate then check(near(rate, expectedRate), "pace matches travelled distance") end
end
pose("Running", 0, 0, false, "idle", 1)
pose("Running", 12.8, 0, false, "walk", 1)
pose("Running", 28, 0, false, "run", 28 / 24)
pose("Running", 7, 0, false, "walk", 7 / 12.8)
pose("Seated", 60, 0, true, "sit", 1)
pose("Jumping", 14, 40, false, "jump")
pose("Freefall", 14, -40, false, "fall")
pose("Climbing", 0, -5, false, "climb", 1)
pose("Climbing", 0, 0, false, "climb", 0)
pose("Swimming", 0, 0, false, "swimidle")
pose("Swimming", 0, 10, false, "swim", 1)
pose("Dead", 20, 0, true, nil)
pose("PlatformStanding", 20, 0, false, nil)
pose("Physics", 20, 0, false, nil)
for _, id in Motion.Animations do check(string.match(id, "^rbxassetid://%d+$") ~= nil, "valid common asset id") end
print("ALL CHECKS PASSED (" .. count .. " character / motion checks)")
