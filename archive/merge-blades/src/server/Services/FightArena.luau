--!strict
-- The fight arena: a big ROUND platform ONE STEP UP between your squad and the enemies. Nobody is teleported
-- onto it: both sides start the fight where they stand (your six on their pads, the wave in its row) and walk
-- up the step toward each other.
--
-- This is a PLACEHOLDER so you can replace it with your own design. The rest of the game only
-- needs what `FightArena.build` returns (an `Arena`):
--   heightAt(worldPos)        world y of the ground at that position (so fighters walk up the step and down again)
--   spot(side, index, count)  a world position on the platform for a fighter (side 1 = your squad, index = squad
--                             slot 1 … 6; side 2 = the enemy wave, index 1 … count), one row per side — kept for
--                             anything that needs "a place on the platform" (nobody is moved there any more)
--   center / radius           the middle of the platform's top and its radius (the brains, the boss and the
--                             twists keep their business inside this circle)
-- Everything else in `build` (shape, materials, decorations, walls) is free to change.
-- Coordinates are relative to the plot: `origin` is the top of the plot's floor, +z points from
-- your squad toward the enemies. The squad stands at z = 43 and the enemy row at z = 204; the round
-- arena (z = 56 … 196, 140 across) sits between them. The plot is 160 wide.

local HEIGHT = 2 -- the arena is one step (2 studs) above the floor
local STEP = 1 -- height of the low ring step around the platform
local Z0 = 56 -- where the platform begins (z, plot-relative), just past the squad's row
local RADIUS = 70 -- the platform is 140 studs across (twice the old arena's depth)
local STAIR_DEPTH = 2.5 -- the ring step reaches this far out of the platform
local PLAYER_SPACING = 12 -- between your six on the platform (one row), the same as their pads
local PAD_TOP = 0.6 -- height of the staging pads above the floor

export type Arena = {
	zone: Part, -- invisible box over the raised arena (a marker of the fight place)
	center: Vector3, -- world position of the middle of the platform's top
	radius: number, -- of the round platform (studs)
	heightAt: (worldPos: Vector3) -> number,
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

-- A flat disc standing on the floor: a cylinder part turned so its axis points up.
local function disc(parent: Instance, name: string, height: number, radius: number, position: Vector3, color: Color3, material: Enum.Material): Part
	local p = block(parent, name, Vector3.new(height, radius * 2, radius * 2), position, color, material)
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return p
end

function FightArena.build(parent: Instance, origin: Vector3, color: Color3, material: Enum.Material): Arena
	local top = origin.Y + HEIGHT
	local centerZ = Z0 + RADIUS
	local center = origin + Vector3.new(0, HEIGHT, centerZ)

	-- The round platform, a darker rim around its edge and a low ring step all around (placeholder geometry).
	local platform = disc(parent, "FightArena", HEIGHT, RADIUS, origin + Vector3.new(0, HEIGHT / 2, centerZ), color, material)
	platform:SetAttribute("TopY", top) -- the client aims spells on this plane
	disc(parent, "FightArenaRim", HEIGHT - 0.1, RADIUS + 0.8, origin + Vector3.new(0, HEIGHT / 2 - 0.05, centerZ), color:Lerp(Color3.new(0, 0, 0), 0.3), material)
	disc(parent, "FightArenaStep", STEP, RADIUS + STAIR_DEPTH, origin + Vector3.new(0, STEP / 2, centerZ), color, material)

	-- Small sign, only visible when you are close.
	local sign = block(parent, "FightArenaSign", Vector3.one, origin + Vector3.new(0, top + 0.5, centerZ), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
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

	local function heightAt(worldPos: Vector3): number
		local dx, dz = worldPos.X - center.X, worldPos.Z - center.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= RADIUS then
			return top
		elseif d <= RADIUS + STAIR_DEPTH then
			return origin.Y + STEP
		end
		return origin.Y + PAD_TOP
	end

	local function spot(side: number, index: number, count: number): Vector3
		-- One row per side on the platform: yours near its near edge, the wave's near the far edge.
		local columns = if side == 1 then 6 else math.max(1, count)
		local spacing = if side == 1 then PLAYER_SPACING else math.min(9, (RADIUS * 1.6) / math.max(1, columns - 1))
		local x = (index - 1 - (columns - 1) / 2) * spacing
		local z = if side == 1 then centerZ - RADIUS * 0.6 else centerZ + RADIUS * 0.6
		return origin + Vector3.new(x, HEIGHT, z)
	end

	-- The battle zone: an invisible box over the raised arena. Walking up onto the arena puts you in
	-- it, and the battle panel (difficulty, wave, start) opens; the server checks the same box.
	-- If you redesign the arena, keep a part named "BattleZone" over the place where the fight is.
	local zone = block(parent, "BattleZone", Vector3.new(RADIUS * 2, 14, RADIUS * 2), origin + Vector3.new(0, HEIGHT + 5, centerZ), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false

	return { heightAt = heightAt, spot = spot, zone = zone, center = center, radius = RADIUS }
end

return FightArena
