--!strict
-- 8.0.2, the owner's imported Blender models out of the world the moment the server starts. Studio's Import 3D leaves
-- each model in Workspace with its MeshParts unanchored and overlapping, so the moment a Play test (or a live server)
-- starts, physics throws them about (the owner's screenshot: the European house lying in pieces over the sandbox's road)
-- and the markers the dressers read their turn and scale from move with them. server/Main.server.luau calls
-- ArtStash.stash() first of all, before the world, the sandbox or any dresser: every such model is anchored where it
-- was put and moved to ServerStorage, where server/VanMesh.luau, FurnitureMesh.luau, HouseMesh.luau and
-- SprinterMesh.luau look first. A model already in ServerStorage is left alone (nothing simulates there).
--
--   ArtStash.stash()   the models moved (0: none in Workspace)
--   ArtStash.Models    the imports by name → a marker only that model has (a renamed import is found by it, with mark_o
--                      or SprinterMark_o)
local ServerStorage = game:GetService("ServerStorage")

local ArtStash = {}

ArtStash.Models = {
	ZDCVanArt = "mark_w", -- the ZDC Van (6.25, design/blender-van)
	ZDCFurnitureArt = "mark_sofa", -- the moves' furniture (7.1, design/blender-furniture)
	ZDCHouseArt = "mark_box", -- Marge's house (7.2, design/blender-house)
	ZDCSprinterArt = "SprinterMark_w", -- the Sprinter (8.0, design/blender-sprinter)
} :: { [string]: string }

local function isArt(child: Instance): boolean
	if not (child:IsA("Model") or child:IsA("Folder")) then
		return false
	end
	if ArtStash.Models[child.Name] then
		return true
	end
	if not (child:FindFirstChild("mark_o", true) or child:FindFirstChild("SprinterMark_o", true)) then
		return false
	end
	for _, marker in ArtStash.Models do
		if child:FindFirstChild(marker, true) then
			return true
		end
	end
	return false
end

function ArtStash.stash(): number
	local moved = 0
	for _, child in workspace:GetChildren() do
		if isArt(child) then
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
				end
			end
			child.Parent = ServerStorage
			moved += 1
		end
	end
	return moved
end

return ArtStash
