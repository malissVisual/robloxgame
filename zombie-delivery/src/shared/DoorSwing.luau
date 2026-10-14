--!strict
-- 8.3 walk-in doors: a door's leaf swinging on its hinge (the owner: "when I go into the house, the door should open,
-- and then it teleports me smoothly"). Pure, plain numbers (tests/doorswing_test.luau). server/Moving.luau says when a
-- leaf is open (its attribute DoorOpen, Config.Moving.Doors), client/WalkDoors.luau swings it with this for everybody.
--
-- A leaf is any part, or any model (its pivot; the PrimaryPart's size, else its box's), with the attribute DoorLeaf,
-- standing at a doorway as it is shut (the house builders put it there: server/SandboxWorld.luau's FrontDoor, server/
-- HouseInterior.luau's front door leaves). Its own frame says the rest: its width is its longer side of X and Z, its
-- thickness the other one, up is its Y.
--   DoorLeaf    (number) the hinge: 1 at the + end of its width, -1 at the - end; 0 a double door (a part only: two
--               leaves, each half its width, hinged at its two ends, meeting in its middle; a model swings as 1)
--   DoorSwing   (number, 1 when not given) the side of its thickness it opens to: 1 its + side (Z, or X for a leaf
--               wider along Z), -1 its - side. Into the house, or out onto a porch.
--   DoorAngle   (number, degrees, Config.Moving.Doors.Angle when not given) how far it opens (more than 0, at most 180)
--   DoorDark    (true) a dark doorway shows where it stood while it is open (a house's solid body behind the leaf, no
--               real opening there)
--   DoorOpen    (the server's, replicated) open now
-- The hinge is at its end on the face it swings to (it opens clear of its frame); open, it has turned Angle about its
-- hinge's upright line, its free end toward the swing side.
--
--   DoorSwing.read(hinge, swing, angle, default) -> (hinge, swing, angle)?   the attributes checked: nil when it is no
--                                     leaf (DoorLeaf not -1, 0 or 1), the swing ±1, the angle in degrees
--   DoorSwing.pieces(sx, sz, hinge, swing, angle) -> { Piece }   the leaf's swinging pieces in its own frame (one, two
--                                     for a double door): each one's middle and size, its hinge from its middle, its
--                                     turn open (radians about +Y, signed); a piece at openness u stands at
--                                     leaf * T(ox + hx, 0, oz + hz) * Ry(yaw * u) * T(-hx, 0, -hz)
--   DoorSwing.ease(t, opening) -> number   the swing's openness at t (0 … 1 of its time): opening fast then easing
--                                     into the stop (cubic out), shutting slow then quicker into the frame (quad in)
--   DoorSwing.dark(sx, sy, sz) -> (number, number, number)   the dark doorway's size (DoorDark): the leaf's face less
--                                     a hair round it, thin, in its middle plane

local DoorSwing = {}

export type Piece = {
	ox: number, -- its middle in the leaf's frame (0, 0: the whole leaf)
	oz: number,
	sx: number, -- its size along the leaf's X and Z
	sz: number,
	hx: number, -- its hinge from its middle (the leaf's axes)
	hz: number,
	yaw: number, -- its turn open about +Y (radians, signed)
}

local function sign(x: number): number
	return if x < 0 then -1 else 1
end

function DoorSwing.read(hinge: any, swing: any, angle: any, default: number): (number?, number, number)
	if type(hinge) ~= "number" or hinge ~= hinge then
		return nil, 1, default
	end
	local h = if math.abs(hinge) < 0.5 then 0 else sign(hinge)
	local s = if type(swing) == "number" and swing == swing and swing ~= 0 then sign(swing) else 1
	local a = if type(angle) == "number" and angle == angle and angle > 0 and angle <= 180 then angle else default
	return h, s, a
end

function DoorSwing.pieces(sx: number, sz: number, hinge: number, swing: number, angle: number): { Piece }
	local alongX = sx >= sz
	local width = if alongX then sx else sz
	local thick = if alongX then sz else sx
	local turn = math.rad(angle)
	-- one leaf `w` wide, its middle `offset` along the width, hinged at its end `h` (-1 / 1)
	local function one(offset: number, w: number, h: number): Piece
		local along, across = h * w / 2, swing * thick / 2
		-- (its free end, -h along the width from the hinge, turns toward the swing side: about +Y a turn of θ takes +X
		-- toward -Z and +Z toward +X)
		local yaw = (if alongX then 1 else -1) * swing * h * turn
		if alongX then
			return { ox = offset, oz = 0, sx = w, sz = thick, hx = along, hz = across, yaw = yaw }
		end
		return { ox = 0, oz = offset, sx = thick, sz = w, hx = across, hz = along, yaw = yaw }
	end
	if hinge == 0 then
		return { one(-width / 4, width / 2, -1), one(width / 4, width / 2, 1) }
	end
	return { one(0, width, sign(hinge)) }
end

function DoorSwing.ease(t: number, opening: boolean): number
	local x = math.clamp(t, 0, 1)
	if opening then
		local r = 1 - x
		return 1 - r * r * r
	end
	return x * x
end

function DoorSwing.dark(sx: number, sy: number, sz: number): (number, number, number)
	local thin = 0.05
	if sx >= sz then
		return math.max(sx - 0.1, thin), math.max(sy - 0.05, thin), thin
	end
	return thin, math.max(sy - 0.05, thin), math.max(sz - 0.1, thin)
end

return DoorSwing
