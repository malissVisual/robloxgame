--!strict
-- 6.10, the curbs: the sloped kerb round every city block (shared/CurbShape.luau has its shape and why it is a slope),
-- built by server/World.luau's sidewalk() with each block's slab. Light grey concrete against the dark asphalt, so the
-- curb reads from afar. It collides and answers rays: it is the ground the cars, the bikes and the people go up and
-- down on.
--
-- Cheap: a block's ring (a wedge along each side, a corner wedge at each corner) is ONE part, a union made once and
-- cloned for every block (like the crosswalks; 124 blocks: 124 parts). Its collision is the union's convex hull, which
-- is exact above the road (the hull also fills the ring's middle up to the walk's top, where the slab is anyway). Only
-- when the union cannot be made: the eight pieces themselves for every block (and a warning in the Output).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CurbShape = require(Shared.CurbShape)

local Curbs = {}

local COLOR = Color3.fromRGB(190, 188, 180)
local ORIGIN = CFrame.new(0, -80, 0) -- the template is made down here, out of the way

local state = {
	tried = false,
	template = nil :: BasePart?,
	inside = CFrame.identity, -- the template's frame from ORIGIN (the block's middle at the ground's 0)
}

-- One piece of a ring, `at` the block's middle (the ground's 0 under it).
local function piece(parent: Instance, p: CurbShape.Piece, at: CFrame): BasePart
	local made: BasePart
	if p.kind == "corner" then
		made = Instance.new("CornerWedgePart")
	else
		made = Instance.new("WedgePart")
	end
	made.Name = "Curb"
	made.Anchored = true
	made.Size = Vector3.new(p.sx, p.sy, p.sz)
	made.CFrame = at * CFrame.fromMatrix(Vector3.new(p.x, p.y, p.z), Vector3.new(p.rx, 0, p.rz), Vector3.yAxis)
	made.Color = COLOR
	made.Material = Enum.Material.Concrete
	made.TopSurface = Enum.SurfaceType.Smooth
	made.BottomSurface = Enum.SurfaceType.Smooth
	made.CanTouch = false
	made.Parent = parent
	return made
end

-- The ring as one union, once (it yields: World builds inside a pcall'd piece, like the crosswalks' union).
local function makeTemplate(parent: Instance)
	state.tried = true
	local pieces: { BasePart } = {}
	for _, p in CurbShape.pieces(0, 0) do
		table.insert(pieces, piece(parent, p, ORIGIN))
	end
	local first = table.remove(pieces, 1) :: BasePart
	local ok, result = pcall(function()
		return first:UnionAsync(pieces, Enum.CollisionFidelity.Hull, Enum.RenderFidelity.Automatic)
	end)
	first:Destroy()
	for _, p in pieces do
		p:Destroy()
	end
	if not ok or typeof(result) ~= "Instance" or not result:IsA("BasePart") then
		warn(`[Curbs] the curbs as single pieces (8 parts a block): {result}`)
		return
	end
	local union = result :: BasePart
	union.Name = "Curb"
	union.Anchored = true
	union.CanTouch = false
	union.Color = COLOR
	union.Material = Enum.Material.Concrete
	if union:IsA("UnionOperation") then
		union.UsePartColor = true
	end
	state.template = union
	state.inside = ORIGIN:ToObjectSpace(union.CFrame)
end

-- The ring round the block centred at (cx, cz), into `parent` (where the block's slab is).
function Curbs.ring(parent: Instance, cx: number, cz: number)
	if not state.tried then
		makeTemplate(parent)
	end
	local template = state.template
	if template then
		local copy = template:Clone()
		copy.CFrame = CFrame.new(cx, 0, cz) * state.inside
		copy.Parent = parent
		return
	end
	local at = CFrame.new(cx, 0, cz)
	for _, p in CurbShape.pieces(0, 0) do
		piece(parent, p, at)
	end
end

return Curbs
