--!strict
-- Exercise the real Kit.build with recorded instances and World's helper contract.
local Kit = require("./Kit")
local Mock = require("./roblox-mock")
-- Rotated tube/disc blueprints need real composition, not translation-only recording.
local rotated = Mock.CFrame.Angles(0, 0, math.pi / 2) * Mock.CFrame.new(2, 0, 0)
assert(math.abs(rotated.position.X) < 1e-8 and math.abs(rotated.position.Y - 2) < 1e-8)
local Blueprints = require("./blueprint-list")
local parts, decorated, lights = {}, {}, {}
local function part(parent, name, size, pose, color, material)
	local item = Mock.Instance.new("Part")
	item.Name, item.Size, item.CFrame, item.Color, item.Material = name, size, pose, color, material
	item.Anchored, item.CanCollide, item.CanQuery, item.CanTouch = true, true, true, false
	item.Parent = parent
	table.insert(parts, item)
	return item
end
local function deco(item)
	item.CanCollide, item.CanQuery = false, false
	decorated[item] = true
	return item
end
local function nightLight(item, lit, dim, material)
	assert(material == "Glass" and lit.R == 255 and dim == item.Color)
	lights[item] = true
end
for _, blueprint in Blueprints do
	if type(blueprint) == "function" then blueprint = blueprint({ -30, -6, 18 }) end
	table.clear(parts)
	table.clear(decorated)
	table.clear(lights)
	table.clear(Mock.instances)
	local parent = Mock.Instance.new("Folder")
	local frame = Mock.CFrame.new(100, 10, 200)
	local model = Kit.build(parent, frame, blueprint, { part = part, deco = deco, nightLight = nightLight })
	assert(model.Parent == parent and model:GetAttribute("Building") == blueprint.id)
	-- 4.3: an interior hall adds its ceiling panels after the details (one, two from 48 studs wide).
	local extra = if blueprint.interior then (if blueprint.width >= 48 then 2 else 1) else 0
	assert(model:GetAttribute("DetailCount") == #blueprint.details and #parts == #blueprint.details + extra)
	for n = 1, extra do
		local p = parts[#blueprint.details + n]
		assert(p.Name == "InteriorLight" .. n and decorated[p] and not p.CanCollide and not p.CanQuery and not p.CanTouch)
	end
	for i, d in blueprint.details do
		local p = parts[i]
		assert(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch and decorated[p])
		assert(p.Parent == model and p.Name == d.name and p.Material ~= nil)
		assert(p.CFrame.position.X == 100 + d.position[1] and p.CFrame.position.Y == 10 + d.position[2] and p.CFrame.position.Z == 200 + d.position[3])
		assert((lights[p] == true) == (d.night == true))
		local labels, beams = 0, 0
		for _, object in Mock.instances do
			if object.Parent == p and object.ClassName == "PointLight" then
				beams += 1
				assert(object.Range == d.beam and not object.Shadows)
			elseif object.Parent == p and object.ClassName == "SurfaceGui" then
				labels += 1
				assert(object.Face == "Front")
				local found = false
				for _, text in Mock.instances do
					if text.Parent == object and text.ClassName == "TextLabel" then
						assert(text.Text == d.label and text.TextScaled and text.BackgroundTransparency == 1)
						found = true
					end
				end
				assert(found)
			end
		end
		assert(labels == (if d.label then 1 else 0) and beams == (if d.beam then 1 else 0))
	end
	print("Renderer PASS: " .. blueprint.id .. " (" .. #parts .. " anchored, nonblocking parts)")
end
