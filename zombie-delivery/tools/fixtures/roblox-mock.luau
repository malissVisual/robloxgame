--!strict
-- Minimal instance/property recorder for the architectural renderer, not a Roblox simulator.
local Mock = {}
Mock.instances = {}
local Object = {}
Object.__index = Object
function Object:SetAttribute(key, value) self.attributes[key] = value end
function Object:GetAttribute(key) return self.attributes[key] end
Mock.Instance = { new = function(class)
	local item = setmetatable({ ClassName = class, attributes = {} }, Object)
	table.insert(Mock.instances, item)
	return item
end }
Mock.Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
Mock.Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }
Mock.UDim2 = { fromScale = function(x, y) return { X = x, Y = y } end }
Mock.Enum = {
	Material = { Metal = "Metal", Concrete = "Concrete", Brick = "Brick", Glass = "Glass", SmoothPlastic = "SmoothPlastic", Wood = "Wood", WoodPlanks = "WoodPlanks", Slate = "Slate", CorrodedMetal = "CorrodedMetal", Rubber = "Rubber", Neon = "Neon" },
	PartType = { Cylinder = "Cylinder" }, NormalId = { Front = "Front", Bottom = "Bottom" }, Font = { GothamMedium = "GothamMedium" },
	SurfaceGuiSizingMode = { PixelsPerStud = "PixelsPerStud" },
}
local Frame = {}
Frame.__index = Frame
function Frame.__mul(a, b)
	local r, p = a.rotation, b.position
	local out = {}
	for i = 0, 2 do for j = 0, 2 do
		local sum = 0
		for k = 0, 2 do sum += r[i * 3 + k + 1] * b.rotation[k * 3 + j + 1] end
		out[i * 3 + j + 1] = sum
	end end
	return setmetatable({ rotation = out, position = Mock.Vector3.new(
		a.position.X + r[1] * p.X + r[2] * p.Y + r[3] * p.Z,
		a.position.Y + r[4] * p.X + r[5] * p.Y + r[6] * p.Z,
		a.position.Z + r[7] * p.X + r[8] * p.Y + r[9] * p.Z) }, Frame)
end
Mock.CFrame = {
	new = function(x, y, z) return setmetatable({ position = Mock.Vector3.new(x, y, z), rotation = { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, Frame) end,
	Angles = function(x, y, z)
		local sx, cx, sy, cy, sz, cz = math.sin(x), math.cos(x), math.sin(y), math.cos(y), math.sin(z), math.cos(z)
		return setmetatable({ position = Mock.Vector3.new(0, 0, 0), rotation = {
			cy * cz, -cy * sz, sy, cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy,
			sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy,
		} }, Frame)
	end,
}
return Mock
