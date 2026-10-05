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
	Material = { Metal = "Metal", Concrete = "Concrete", Brick = "Brick", Glass = "Glass", SmoothPlastic = "SmoothPlastic", Wood = "Wood", WoodPlanks = "WoodPlanks", Slate = "Slate", CorrodedMetal = "CorrodedMetal", Rubber = "Rubber" },
	PartType = { Cylinder = "Cylinder" }, NormalId = { Front = "Front" }, Font = { GothamMedium = "GothamMedium" },
	SurfaceGuiSizingMode = { PixelsPerStud = "PixelsPerStud" },
}
local Frame = {}
Frame.__index = Frame
function Frame.__mul(a, b)
	-- Blueprints use translations and zero rotation. Record the composition to prove World supplies the frame.
	return setmetatable({ position = Mock.Vector3.new(a.position.X + b.position.X, a.position.Y + b.position.Y, a.position.Z + b.position.Z) }, Frame)
end
Mock.CFrame = {
	new = function(x, y, z) return setmetatable({ position = Mock.Vector3.new(x, y, z) }, Frame) end,
	Angles = function(x, y, z)
		assert(x == 0 and y == 0 and z == 0, "Extend the geometry validator before adding rotated details")
		return setmetatable({ position = Mock.Vector3.new(0, 0, 0) }, Frame)
	end,
}
return Mock
