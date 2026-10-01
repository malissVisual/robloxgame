--!strict
-- The fight arena: a platform ONE STEP UP where both sides march to and fight.
--
-- This is a PLACEHOLDER so you can replace it with your own design. The rest of the game only
-- needs what `FightArena.build` returns (an `Arena`):
--   heightAt(worldZ)          world y of the ground at that z (so fighters can walk up the steps)
--   spot(side, index, count)  world position where a fighter stands when the fight starts;
--                             side 1 = your squad (index = squad slot 1 … 6),
--                             side 2 = the enemy wave (index 1 … count, front row first)
-- Everything else in `build` (shape, materials, decorations, walls) is free to change.
-- Coordinates are relative to the plot: `origin` is the top of the plot's floor, +z points from
-- your squad toward the enemies. The squad stands at z = 37 … 49 and the enemy preview at
-- z = 136 … 150; the arena (z = 56 … 128) sits between them.

local HEIGHT = 2 -- the arena is one step (2 studs) above the floor
local STEP = 1 -- height of the small stair step on each side
local Z0, Z1 = 56, 128 -- platform start / end (z, plot-relative): a big arena, 72 studs deep
local HALF_WIDTH = 38 -- 76 studs wide (the plot is 84)
local STAIR_WIDTH = 36
local STAIR_DEPTH = 2
local PLAYER_SPACING = 16 -- between your fighters in a row: the formation is spread over the arena, so the column
local ENEMY_SPACING = 13 -- of a pad decides in which lane the character fights
local ROW_GAP = 10 -- between rows
local PLAYER_Z, ENEMY_Z = 66, 104 -- your back row / the enemies' front row (your 2 rows are a ROW_GAP apart)
local PAD_TOP = 0.6 -- height of the staging pads above the floor

export type Arena = {
	zone: Part, -- invisible box over the raised arena (a marker of the fight place)
	center: Vector3, -- world position of the middle of the platform's top
	heightAt: (worldZ: number) -> number,
	spot: (side: number, index: number, count: number) -> Vector3,
}

local FightArena = {}

local function block(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.Parent = parent
	return p
end

function FightArena.build(parent: Instance, origin: Vector3, color: Color3, material: Enum.Material): Arena
	local top = origin.Y + HEIGHT

	-- Platform and one stair step on each side (placeholder geometry).
	block(parent, "FightArena", Vector3.new(HALF_WIDTH * 2, HEIGHT, Z1 - Z0), origin + Vector3.new(0, HEIGHT / 2, (Z0 + Z1) / 2), color, material)
	block(parent, "FightArenaStepNear", Vector3.new(STAIR_WIDTH, STEP, STAIR_DEPTH), origin + Vector3.new(0, STEP / 2, Z0 - STAIR_DEPTH / 2), color, material)
	block(parent, "FightArenaStepFar", Vector3.new(STAIR_WIDTH, STEP, STAIR_DEPTH), origin + Vector3.new(0, STEP / 2, Z1 + STAIR_DEPTH / 2), color, material)

	-- Small sign, only visible when you are close.
	local sign = block(parent, "FightArenaSign", Vector3.one, origin + Vector3.new(0, top + 0.5, (Z0 + Z1) / 2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	sign.Transparency = 1
	sign.CanCollide = false
	sign.CanQuery = false
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 45
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.RichText = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.6
	label.Text = '<font size="13" color="#9aa0aa">PLACEHOLDER — DESIGN HERE</font>\n<font size="24">FIGHT ARENA</font>'
	label.Parent = gui

	local function heightAt(worldZ: number): number
		local z = worldZ - origin.Z
		if z >= Z0 and z <= Z1 then
			return top
		elseif (z >= Z0 - STAIR_DEPTH and z < Z0) or (z > Z1 and z <= Z1 + STAIR_DEPTH) then
			return origin.Y + STEP
		end
		return origin.Y + PAD_TOP
	end

	local function spot(side: number, index: number, count: number): Vector3
		local columns = if side == 1 then 3 else 4 -- your squad is 3 wide, the enemy wave 4 wide
		local row = (index - 1) // columns
		local column = (index - 1) % columns
		local inRow = columns -- the enemies keep the fixed 4-column grid (so they line up with the slots)
		local x = (column + 1 - (inRow + 1) / 2) * (if side == 1 then PLAYER_SPACING else ENEMY_SPACING)
		local z = if side == 1 then PLAYER_Z + row * ROW_GAP else ENEMY_Z + row * ROW_GAP
		return origin + Vector3.new(x, HEIGHT, z)
	end

	-- The battle zone: an invisible box over the raised arena. Walking up onto the arena puts you in
	-- it, and the battle panel (difficulty, wave, start) opens; the server checks the same box.
	-- If you redesign the arena, keep a part named "BattleZone" over the place where the fight is.
	local zone = block(parent, "BattleZone", Vector3.new(HALF_WIDTH * 2, 14, Z1 - Z0), origin + Vector3.new(0, HEIGHT + 5, (Z0 + Z1) / 2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false

	return { heightAt = heightAt, spot = spot, zone = zone, center = origin + Vector3.new(0, HEIGHT, (Z0 + Z1) / 2) }
end

return FightArena
