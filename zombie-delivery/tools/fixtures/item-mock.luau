--!strict
-- 6.22: the recorder that builds the inventory's looks outside Studio (tests/itemlooks_test.luau through
-- tests/run_tests.py, tools/item-models/export.luau): tools/vehicle-preview/roblox-mock.luau (copied next to it as
-- rbxmock.luau) plus the few things the cargo and item builders use that it lacks: Model:ScaleTo about its pivot,
-- GetExtentsSize, FindFirstChildWhichIsA, CFrame:GetComponents. Not a Roblox simulator.
local M = require("./rbxmock") :: any

local O = getmetatable(M.Instance.new("Model"))
local F = getmetatable(M.CFrame.new())

function F.GetComponents(self: any)
	local r = self.R
	return self.Position.X, self.Position.Y, self.Position.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end

local function isPart(obj: any): boolean
	return obj:IsA("BasePart") or obj.ClassName == "TrussPart"
end

function O.FindFirstChildWhichIsA(self: any, class: string)
	for _, child in self.children do
		if child:IsA(class) then
			return child
		end
	end
	return nil
end

-- The model's pivot: its primary part's frame with its PivotOffset (the cargo's: the bottom centre), else the origin.
local function pivotOf(model: any): any
	local main = model.PrimaryPart
	if main then
		return main.CFrame * (main.PivotOffset or M.CFrame.identity)
	end
	return M.CFrame.identity
end

function O.ScaleTo(self: any, scale: number)
	local pivot = pivotOf(self)
	local back = pivot:Inverse()
	for _, p in self:GetDescendants() do
		if isPart(p) then
			local rel = back * p.CFrame
			local moved = M.CFrame.new(rel.Position * scale, nil, nil, table.unpack(rel.R))
			p.CFrame = pivot * moved
			p.Size = p.Size * scale
		end
	end
	self:SetAttribute("Scale", scale)
end

function O.GetExtentsSize(self: any)
	local _, size = self:GetBoundingBox()
	return size
end

return M
