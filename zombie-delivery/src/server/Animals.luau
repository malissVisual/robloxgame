--!strict
-- Animals: the horses of Silver Spur Ranch. A horse is a model built from parts (body, neck, head, mane, tail, four
-- legs on joints the clients swing when it walks), moved by its own Humanoid. It can stand, walk to a point, and
-- follow someone on a lead rope (a visible rope from the halter to the leader's hand).
-- [STUB: stream B "world" fills this in; the API below is the contract.]

local Animals = {}

-- A horse standing at `at` (hooves on the ground at at.Position, facing at.LookVector). Parented to workspace.Animals.
function Animals.horse(at: CFrame, coat: { number }?): Model
	local model = Instance.new("Model")
	model.Name = "Horse"
	return model
end

-- Follow `leader` (a character) on a rope, a few studs behind; nil lets go (the horse stands).
function Animals.lead(horse: Model, leader: Model?) end

-- Walk to a point, then call `arrived`.
function Animals.walkTo(horse: Model, point: Vector3, arrived: ((boolean) -> ())?) end

-- Put the horse at a spot without walking (into a vehicle's stall: anchored and welded so it rides along), or free it.
function Animals.stable(horse: Model, at: CFrame?, weldTo: BasePart?) end

function Animals.remove(horse: Model)
	horse:Destroy()
end

function Animals.start() end

return Animals
