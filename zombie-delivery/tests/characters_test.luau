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
		for bone, nominal in KitFit.Nominal do
			for i = 1, 3 do check(near(bones[bone].size[i], nominal[i]), "purchased kit fits " .. bone) end
		end
		check(names.VestL and names.CapBrimBack and not names.Backpack, "uniform does not grant paid gear")
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
