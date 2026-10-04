--!strict
-- People in the world: realistic R15 characters (built from a HumanoidDescription) who stand at their place, play an
-- idle animation, turn to you, say a line in a speech bubble and can walk somewhere. The employers stand at their
-- WORK HERE boards, the givers hand cargo over at pick-ups, the receivers take it at the drops, kids board the bus.
-- [STUB: stream B "world" fills this in; the API below is the contract.]

local Npcs = {}

export type Look = {
	name: string, -- shown over the head
	title: string?, -- a second line ("Rancher", "Sergeant")
	skin: { number }?, -- r, g, b
	shirt: { number }?,
	pants: { number }?,
	hat: string?, -- none | cap | cowboy | hardhat | beanie | chef
	child: boolean?, -- a kid (smaller)
}

-- A person standing at `at` (feet on the ground at at.Position, facing at.LookVector). Parented to workspace.Npcs.
function Npcs.spawn(look: Look, at: CFrame): Model
	local model = Instance.new("Model")
	model.Name = look.name
	return model
end

-- A line in a speech bubble over the head for a few seconds.
function Npcs.say(npc: Model, text: string, seconds: number?) end

-- Turn to face a point (smoothly, on the spot).
function Npcs.face(npc: Model, point: Vector3) end

-- Walk to a point (walk animation), then call `arrived` (false if it could not get there within `timeout` s).
function Npcs.walkTo(npc: Model, point: Vector3, arrived: ((boolean) -> ())?, timeout: number?) end

function Npcs.remove(npc: Model)
	npc:Destroy()
end

-- A quick look for a role (consistent outfits): "rancher", "soldier", "farmer", "worker", "teacher", "kid",
-- "shopkeeper", "mover", "cook", "clerk", anything else = a random townsperson.
function Npcs.look(role: string, name: string, title: string?): Look
	return { name = name, title = title }
end

function Npcs.start() end

return Npcs
