-- 5.6, the zip lines (shared/ZipLines.luau): 6 – 10 cables from a taller Downtown tower's roof over a road to a lower
-- roof, about 120 – 260 studs, never through a building (the cable stays Clearance over every roof it crosses but its
-- own two), the platforms on their roofs, the ladders on a street wall, and the ride's numbers; in the standalone
-- Luau CLI. 6.10: the ladders' trusses (climbed for real, clear of the riders), getting on with a jump or the Zip
-- prompt from anywhere on the start platform.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local ZipLines = require("./ZipLines")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local tuning = Config.ZipLines
local lines = ZipLines.lines()
check("6 – 10 lines", #lines >= 6 and #lines <= 10, #lines)
-- 6.8 review: the rider's feet are the courier's (its root HipHeight + 1 over the soles), and the handle hangs under
-- the cable within the arms' reach of the shoulders (client/ZipRide.luau bends the elbows to it)
-- 6.9: the couriers wear Roblox's classic blocky R15 (server/CourierAvatar.luau); its stand-in is the native block body
-- (CharacterArt's 6.0 body, the infected's: the classic R15's proportions and joints, HipHeight 1.97 against 2)
local courier = require("./CharacterGeometry").spec("walker")
check("the rider's feet are the courier's", math.abs(ZipLines.Feet - (courier.hipHeight + 1)) < 0.05, ZipLines.Feet)
do
	local shoulderY, elbowY, wristY = 0, 0, 0
	for _, j in courier.joints do
		if j.name == "RightShoulder" then
			shoulderY = j.at[2]
		elseif j.name == "RightElbow" then
			elbowY = j.at[2]
		elseif j.name == "RightWrist" then
			wristY = j.at[2]
		end
	end
	local reach = (shoulderY - elbowY) + (elbowY - wristY) + 0.46 -- (the wrist to the grip in the fist)
	local up = tuning.Hang - tuning.HandleDrop - shoulderY
	check("the handle within the arms' reach, the elbows bent a little", tuning.HandleDrop > 0.2 and up < reach - 0.1 and up > reach * 0.75, up)
end
check("the lines are cached", ZipLines.lines() == lines)
-- 6.10: you walk onto a platform through the gap in its back rail (the body is 2 wide), two pieces of rail beside it
check("the back rail's gap lets a body through", tuning.RailGap >= 2.4 and (tuning.Platform - tuning.RailGap) / 2 >= 1, tuning.RailGap)

-- Every Downtown lot's building as a box (the towers, the storefronts …), straight from Map.lots.
local boxes: { ZipLines.Box } = {}
for _, lots in Map.lots("downtown") do
	for _, lot in lots do
		local box = ZipLines.boxOf(lot)
		if box then
			table.insert(boxes, box)
		end
	end
end
check("the towers are boxes", #boxes > 100, #boxes)

local usedTower: { [Map.Lot]: boolean } = {}
for _, line in lines do
	local s, e = line.start, line.finish
	print(string.format("  %s: (%d, %d) %.0f high → (%d, %d) %.0f high, %.0f studs, sag %.1f, a ride of %.1f s", line.name, s.i, s.j, s.h + Map.WalkTop, e.i, e.j, e.h + Map.WalkTop, line.length, line.sag, line.duration))
	check(`{line.name}: from a tower to a tower`, (s.kind == "tower" or s.kind == "apartment") and (e.kind == "tower" or e.kind == "apartment"))
	check(`{line.name}: Downtown, two blocks`, s.district == "downtown" and e.district == "downtown" and (s.i ~= e.i or s.j ~= e.j))
	check(`{line.name}: no tower in two lines`, not usedTower[s] and not usedTower[e])
	usedTower[s], usedTower[e] = true, true
	check(`{line.name}: about 120 – 260 studs`, line.length >= tuning.MinLength and line.length <= tuning.MaxLength, line.length)
	check(`{line.name}: downhill`, line.ay - line.by >= tuning.MinDrop and (line.ay - line.by) / line.length <= tuning.MaxSlope, line.ay - line.by)
	-- The platforms on their own roofs, at the edge toward each other; the cable's ends over them.
	for _, pair in { { line.a, s }, { line.b, e } } do
		local p, lot = pair[1], pair[2]
		local box = ZipLines.boxOf(lot) :: ZipLines.Box
		local P = tuning.Platform / 2
		check(`{line.name}: a platform on its roof`, p.x - P >= box.x0 and p.x + P <= box.x1 and p.z - P >= box.z0 and p.z + P <= box.z1 and math.abs(p.floor - (box.top + 0.5)) < 1e-6)
	end
	check(`{line.name}: the cable's ends over the platforms`, line.ax == line.a.x and line.az == line.a.z and math.abs(line.ay - (line.a.floor + tuning.CableHeight)) < 1e-6 and line.bx == line.b.x and line.bz == line.b.z and math.abs(line.by - (line.b.floor + tuning.CableHeight)) < 1e-6)
	-- The clearance: sample the cable every stud against every box; over every roof it crosses but its own two it
	-- stays Clearance (3) or more; it never crosses a special block or leaves Downtown; over the ground it stays high.
	local worstRoof, worstGround, overRoad = math.huge, math.huge, false
	local special = false
	local steps = math.ceil(line.length)
	for n = 0, steps do
		local x, y, z = ZipLines.cable(line, n / steps)
		local inBox = false
		for _, box in boxes do
			if x >= box.x0 and x <= box.x1 and z >= box.z0 and z <= box.z1 then
				inBox = true
				if box.lot ~= s and box.lot ~= e then
					worstRoof = math.min(worstRoof, y - box.top)
				end
			end
		end
		local kind, top = ZipLines.surfaceAt(x, z)
		if kind == "special" or kind == "outside" then
			special = true
		elseif not inBox then
			worstGround = math.min(worstGround, y - top)
		end
		overRoad = overRoad or kind == "road"
	end
	check(`{line.name}: at least {tuning.Clearance} studs over every roof it crosses`, worstRoof >= tuning.Clearance, worstRoof)
	check(`{line.name}: high over the streets and the open lots (lamps, trees)`, worstGround >= tuning.OverStreet, worstGround)
	check(`{line.name}: over a road`, overRoad)
	check(`{line.name}: never over a special block or out of Downtown`, not special)
	-- It sags: the middle is lower than the straight line between the ends.
	local _, ym = ZipLines.cable(line, 0.5)
	check(`{line.name}: it sags in the middle`, math.abs((line.ay + line.by) / 2 - ym - line.sag) < 1e-6 and line.sag > 0)
	-- The ladders: on an outer wall of their tower, facing the street (an apartment's other street side).
	for _, pair in { { line.ladderA, s }, { line.ladderB, e } } do
		local ladder, lot = pair[1], pair[2]
		local d = Map.districtById(lot.district)
		local cx, cz = d.ox + lot.i * Map.Cell, d.oz + lot.j * Map.Cell
		local outward = (ladder.nx ~= 0 and math.sign(lot.x - cx) == ladder.nx) or (ladder.nz ~= 0 and math.sign(lot.z - cz) == ladder.nz)
		local onWall = (ladder.nx ~= 0 and math.abs(ladder.x - (lot.x + ladder.nx * lot.w / 2)) < 1e-6 and math.abs(ladder.z - lot.z) < lot.d / 2)
			or (ladder.nz ~= 0 and math.abs(ladder.z - (lot.z + ladder.nz * lot.d / 2)) < 1e-6 and math.abs(ladder.x - lot.x) < lot.w / 2)
		check(`{line.name}: a ladder on its tower's street wall`, outward and onWall and ladder.top > ladder.base)
		local entrance = lot.kind == "apartment" and lot.facing.x == ladder.nx and lot.facing.z == ladder.nz
		check(`{line.name}: the ladder off the apartment's entrance`, not entrance)
		if lot.home then
			local dd = math.sqrt((lot.home.door.x - ladder.x) ^ 2 + (lot.home.door.z - ladder.z) ^ 2)
			check(`{line.name}: the ladder well away from the door`, dd > 8, dd)
		end
		-- 6.10: a real ladder, a truss the body climbs by itself: a multiple of 2 high, against its wall, from the
		-- sidewalk (its foot in it) to a little over the roof, so a climber gets off onto the roof
		local tx, ty, tz, height = ZipLines.truss(ladder)
		local top, bottom = ty + height / 2, ty - height / 2
		check(`{line.name}: the truss a multiple of 2 high`, height >= 2 and height % 2 == 0, height)
		check(`{line.name}: the truss from the sidewalk to a little over the roof`, bottom <= ladder.base + 1e-6 and bottom > ladder.base - 2 and top >= ladder.top and top <= ladder.top + 1, `{bottom} … {top}`)
		local out, along = (tx - ladder.x) * ladder.nx + (tz - ladder.z) * ladder.nz, (tx - ladder.x) * ladder.nz - (tz - ladder.z) * ladder.nx
		check(`{line.name}: the truss against its wall`, math.abs(out - 1.05) < 1e-6 and math.abs(along) < 1e-6, out)
		-- … and solid now: the rider never touches it. Where the body (2 wide, 1 deep round the root, turned any way)
		-- is over the truss's 2 × 2, its lowest solid part (the root's bottom, 1 under its middle) stays over its top.
		local worst = math.huge
		local t = 0
		while t <= line.duration do
			local x, y, z = ZipLines.rider(line, t)
			local dx, dz = math.max(0, math.abs(x - tx) - 1), math.max(0, math.abs(z - tz) - 1)
			if dx * dx + dz * dz < 1.2 * 1.2 then
				worst = math.min(worst, y - 1 - top)
			end
			t += 0.01
		end
		check(`{line.name}: the rider clears the ladder's top`, worst >= 0.3, worst)
	end
	-- 6.10: onto the zip line with a jump (ZipLines.startAt) or the Zip prompt (the server's ZipLines.canStart): from
	-- anywhere on the start platform, a jump on its way up too; not beside it, not from the street or the ladder, not
	-- from the end platform.
	do
		local a, b = line.a, line.b
		local lift = ZipLines.Feet
		local half = tuning.Platform / 2
		local anywhere = true
		for _, corner in { { 0, 0 }, { half, half }, { -half, half }, { half, -half }, { -half, -half } } do
			local x, z = a.x + corner[1], a.z + corner[2]
			anywhere = anywhere and ZipLines.startAt(x, a.floor + lift, z, lift) == line and ZipLines.startAt(x, a.floor + lift + 5, z, lift) == line
			anywhere = anywhere and ZipLines.canStart(line, x, a.floor + lift, z, lift)
		end
		check(`{line.name}: a jump anywhere on the start platform grabs`, anywhere)
		check(`{line.name}: not beside the platform`, ZipLines.startAt(a.x + half + 2, a.floor + lift, a.z, lift) == nil and ZipLines.startAt(a.x, a.floor + lift, a.z - half - 2, lift) == nil)
		check(`{line.name}: not from the street, nor over a whole jump`, ZipLines.startAt(a.x, Map.WalkTop + lift, a.z, lift) == nil and ZipLines.startAt(a.x, a.floor + lift + tuning.GrabRise + 1, a.z, lift) == nil)
		check(`{line.name}: no ride from the end platform`, ZipLines.startAt(b.x, b.floor + lift, b.z, lift) == nil and not ZipLines.canStart(line, b.x, b.floor + lift, b.z, lift))
		-- the Zip from the roof behind the platform (walking in), not from the ladder's top
		local behind = ZipLines.canStart(line, a.x - a.fx * (half + 1.5), a.floor - 0.5 + lift, a.z - a.fz * (half + 1.5), lift)
		local l = line.ladderA
		local cx, cz = l.x + l.nx * 2.5, l.z + l.nz * 2.5 -- (a climber's root, out of the truss)
		local fromLadder = ZipLines.canStart(line, cx, l.top - 2 + lift, cz, lift)
		check(`{line.name}: the Zip from the roof behind the platform, not from the ladder`, behind and not fromLadder)
		-- the Zip prompt in the platform's middle: every spot on it within PromptReach (the root 0.5 over the prompt),
		-- the climber on the ladder beyond it
		local corner = math.sqrt(2 * (half + 0.5) ^ 2 + 0.5 ^ 2)
		local ladderAway = math.sqrt((cx - a.x) ^ 2 + (cz - a.z) ^ 2)
		check(`{line.name}: the Zip prompt reaches the whole platform, not the ladder`, corner <= tuning.PromptReach and ladderAway > tuning.PromptReach, ladderAway)
	end
	-- The ride: from standing, about Speed along the cable, over at `duration`, gentle at the end.
	local x0, y0, z0 = ZipLines.at(line, 0)
	local x1, y1, z1, over = ZipLines.at(line, line.duration)
	check(`{line.name}: the ride starts at the start's anchor and ends at the end's`, math.abs(x0 - line.ax) + math.abs(y0 - line.ay) + math.abs(z0 - line.az) < 1e-6 and math.abs(x1 - line.bx) + math.abs(y1 - line.by) + math.abs(z1 - line.bz) < 1e-6 and over)
	local fastest, last, backwards = 0, 0, false
	local dt = 0.02
	local t = 0
	while t < line.duration + 0.5 do
		local d = ZipLines.travelled(line, t)
		backwards = backwards or d < last - 1e-9
		fastest = math.max(fastest, (d - last) / dt)
		last = d
		t += dt
	end
	check(`{line.name}: never backwards, never faster than Speed`, not backwards and fastest <= tuning.Speed + 1e-6, fastest)
	check(`{line.name}: the ride takes about its length at Speed`, line.duration > line.span / tuning.Speed and line.duration < line.span / tuning.Speed + tuning.Ramp + 1.5, line.duration)
	local endSpeed = (ZipLines.travelled(line, line.duration) - ZipLines.travelled(line, line.duration - 0.05)) / 0.05
	check(`{line.name}: it slows down to arrive`, endSpeed < tuning.Speed * 0.5, endSpeed)
	-- The rider lands on the end platform: the feet just over its floor.
	local _, ry = ZipLines.rider(line, line.duration)
	local feet = ry - ZipLines.Feet - line.b.floor
	check(`{line.name}: the rider arrives with the feet just over the end platform`, feet > 0 and feet < 1.5, feet)
	-- Letting go: never in the middle (over the road), yes at the end over the end's roof.
	check(`{line.name}: no letting go in the middle`, not ZipLines.canLetGo(line, line.duration / 2))
	check(`{line.name}: letting go over the end platform`, ZipLines.canLetGo(line, line.duration))
	local unsafe = 0
	t = 0
	while t <= line.duration do
		if ZipLines.canLetGo(line, t) then
			local x, y, z = ZipLines.rider(line, t)
			local kind, top = ZipLines.surfaceAt(x, z)
			if kind ~= "box" or y - ZipLines.Feet - top > tuning.SafeDrop then
				unsafe += 1
			end
		end
		t += 0.05
	end
	check(`{line.name}: letting go only low over a roof`, unsafe == 0, unsafe)
end

-- Two lines never share a block, their middles apart.
for n, a in lines do
	for m, b in lines do
		if n < m then
			local apart = math.sqrt(((a.ax + a.bx) / 2 - (b.ax + b.bx) / 2) ^ 2 + ((a.az + a.bz) / 2 - (b.az + b.bz) / 2) ^ 2)
			check(`{a.name} and {b.name} apart`, apart >= tuning.Spread, apart)
		end
	end
end
check("the surface: a road between blocks, a block's sidewalk, outside Downtown", ZipLines.surfaceAt(Map.Cell / 2, 0) == "road" and (ZipLines.surfaceAt(0, 0)) == "special" and ZipLines.surfaceAt(5000, 0) == "outside")

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
