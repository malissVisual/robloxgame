-- 6.24: the gait's key poses (shared/Gait.luau, run as it runs in the game: scenarios of frames at 60 a second) on
-- server/CharacterArt's block body (the classic R15's proportions and joints), as one JSON line per pose: every body
-- part's world box. tools/character-art/gait_sheet.py copies the modules next to this file, runs it and draws the sheet.
-- The joints the gait leaves to the animation stand at rest here (the stock idle's own motion is not drawn).
local Geometry = require("./CharacterGeometry")
local Gait = require("./Gait")

local spec = Geometry.spec("walker")
local centers, sizes = {}, {}
for _, bone in spec.bones do
	centers[bone.name], sizes[bone.name] = bone.at, bone.size
end
local slotOf = {}
for j, name in Gait.Names do
	slotOf[name] = j
end

-- 3x4 frames: { r00, r01, r02, r10, r11, r12, r20, r21, r22, x, y, z }
local function mul(a, b)
	return {
		a[1] * b[1] + a[2] * b[4] + a[3] * b[7], a[1] * b[2] + a[2] * b[5] + a[3] * b[8], a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
		a[4] * b[1] + a[5] * b[4] + a[6] * b[7], a[4] * b[2] + a[5] * b[5] + a[6] * b[8], a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
		a[7] * b[1] + a[8] * b[4] + a[9] * b[7], a[7] * b[2] + a[8] * b[5] + a[9] * b[8], a[7] * b[3] + a[8] * b[6] + a[9] * b[9],
		a[1] * b[10] + a[2] * b[11] + a[3] * b[12] + a[10],
		a[4] * b[10] + a[5] * b[11] + a[6] * b[12] + a[11],
		a[7] * b[10] + a[8] * b[11] + a[9] * b[12] + a[12],
	}
end
local function tr(x, y, z)
	return { 1, 0, 0, 0, 1, 0, 0, 0, 1, x, y, z }
end
local function yaw(a)
	return { math.cos(a), 0, math.sin(a), 0, 1, 0, -math.sin(a), 0, math.cos(a), 0, 0, 0 }
end

-- The joint's Transform as the client writes it: the pose laid over the rest pose by its weight.
local function transform(pose, j)
	local o, m, w = (j - 1) * 12, pose.m, pose.w[j]
	local t = { m[o + 4], m[o + 5], m[o + 6], m[o + 7], m[o + 8], m[o + 9], m[o + 10], m[o + 11], m[o + 12], m[o + 1], m[o + 2], m[o + 3] }
	if w >= 0.999 then
		return t
	end
	local id = { 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0 }
	for k = 1, 12 do
		t[k] = id[k] + (t[k] - id[k]) * w
	end
	return t
end

local function frames(pose, root)
	local out = { HumanoidRootPart = root }
	for _, joint in spec.joints do
		local parent = out[joint.parent]
		local cp, cc, at = centers[joint.parent], centers[joint.child], joint.at
		local slot = slotOf[joint.name]
		local t = if slot then transform(pose, slot) else tr(0, 0, 0)
		out[joint.child] = mul(mul(mul(parent, tr(at[1] - cp[1], at[2] - cp[2], at[3] - cp[3])), t), tr(cc[1] - at[1], cc[2] - at[2], cc[3] - at[3]))
	end
	return out
end

local function emit(title, pose, root, note, floor)
	local f = frames(pose, root)
	local parts = {}
	for name, frame in f do
		if name ~= "HumanoidRootPart" then
			local size = sizes[name]
			table.insert(parts, string.format('{"name":"%s","size":[%.4f,%.4f,%.4f],"cf":[%s]}', name, size[1], size[2], size[3],
				table.concat((function()
					local list = {}
					for k = 1, 12 do
						list[k] = string.format("%.5f", frame[k])
					end
					return list
				end)(), ",")))
		end
	end
	print(string.format('{"title":"%s","note":"%s","ground":%.4f,"rooty":%.4f,"lift":%.4f,"parts":[%s]}', title, note or "", -2.97, root[11], root[11] - (floor or 0), table.concat(parts, ",")))
end

-- A scenario: a fresh body, `setup(input, t)` each frame for `seconds`; the pose at the end (root advanced by the speed).
local DT = 1 / 60
local function run(seconds, setup, seed)
	local s, i, pose = Gait.new(seed or 0.37), Gait.input(), Gait.pose()
	local x, y, z, facing = 0, 0, 0, 0
	local t = 0
	while t < seconds - 1e-9 do
		i.dt = DT
		setup(i, t, s)
		Gait.step(s, i, Gait.Classic, pose)
		local c, sn = math.cos(facing), math.sin(facing)
		-- (the root's frame to the world: the velocity turned by the facing)
		x += (i.vx * c + i.vz * sn) * DT
		z += (-i.vx * sn + i.vz * c) * DT
		y = i.y
		facing += i.yawRate * DT
		t += DT
	end
	return pose, mul(tr(0, y, 0), yaw(facing)), s
end

local function walking(speed, way)
	return function(i)
		i.vx, i.vz = speed * math.sin(way or 0), -speed * math.cos(way or 0)
	end
end

-- The brisk walk (14) through one cycle, from the right heel's strike.
local cycle = 1 / (14 / Gait.stride(14, Gait.Classic.leg))
local function walkAt(phase)
	-- (run until the phase comes round: whole cycles after the stride has opened)
	local pose, root, s
	local target = 2 + phase
	pose, root, s = run(0.6, walking(14))
	local turns = 0
	local last = s.phase
	local inp = Gait.input()
	while true do
		inp.dt = DT
		inp.vx, inp.vz = 0, -14
		Gait.step(s, inp, Gait.Classic, pose)
		if s.phase < last then
			turns += 1
		end
		last = s.phase
		if turns + s.phase >= target then
			break
		end
	end
	return pose
end
for _, phase in { 0, 0.15, 0.3, 0.5, 0.65, 0.8 } do
	emit(string.format("Walk 14 · %.2f", phase), walkAt(phase), tr(0, 0, 0), if phase == 0 then string.format("%.2f steps/s", 2 / cycle) else "")
end

-- Speeds and ways.
local function at(speed, seconds, way, extra)
	return run(seconds, function(i, t, s)
		i.vx, i.vz = speed * math.sin(way or 0), -speed * math.cos(way or 0)
		if extra then
			extra(i, t, s)
		end
	end)
end
local pose, root = at(5, 1.37)
emit("Stroll 5", pose, root)
pose, root = at(3.5, 1.3, math.rad(90), function(i)
	i.aiming, i.hands = true, "busy"
end)
emit("Aim strafe right 3.5", pose, root, "hips to the way, chest to the aim")
pose, root = at(3.5, 1.2, math.rad(180), function(i)
	i.aiming, i.hands = true, "busy"
end)
emit("Aim walk back 3.5", pose, root)
pose, root = at(8, 1.25, 0, function(i)
	i.hands, i.heavy = "carry", 1
end)
emit("Carry heavy 8", pose, root, "arms: ArmPose's")
pose, root = at(14, 1.21, 0, function(i)
	i.hands = "gun"
end)
emit("Walk, gun low 14", pose, root)
pose, root = at(14, 1.3, 0, function(i)
	i.hands = "bag"
end)
emit("Walk, bag 14", pose, root)

-- The run and the sprint.
pose, root = at(18, 1.3)
emit("Run 18", pose, root)
pose, root = at(28, 1.32, 0, function(i)
	i.breath = 1
end)
emit("Sprint 28", pose, root)
pose, root = at(28, 1.32, 0, function(i)
	i.breath = 0.04
end)
emit("Sprint, out of breath", pose, root)
-- starting and stopping
pose, root = run(0.2, function(i, t)
	local v = math.min(14, 28 * t)
	i.vx, i.vz = 0, -v
end)
emit("Start (0.2 s)", pose, root, "leaning into it")
pose, root = run(1.6, function(i, t)
	local v = if t < 1 then 14 else math.max(0, 14 - 38 * (t - 1))
	i.vx, i.vz = 0, -v
end)
emit("Stop (settling)", pose, root, "0.23 s after the stop")
pose, root = run(1.3, function(i)
	i.vx, i.vz = 0, -14
	i.yawRate = 3
end)
emit("Turn left 14", pose, root, "leaning in")
pose, root = run(1.3, function(i)
	i.vx, i.vz = 0, -8
	i.slopeF = 0.35
end)
emit("Uphill 8", pose, root)

-- Idle.
pose, root = run(1, function(i)
	i.vx, i.vz = 0, 0
end)
emit("Idle", pose, root, "stock idle + BodyLife")
pose, root = run(1, function(i)
	i.hands = "gun"
end)
emit("Idle, gun out", pose, root)
pose, root = run(4.6, function(i, t)
	local v = if t < 2 then 28 else math.max(0, 28 - 38 * (t - 2))
	i.vx, i.vz = 0, -v
	i.breath = 0.03
end)
emit("Catch the breath", pose, root, "spent, stopped")
local function fidget(kind, at)
	return run(at, function(i, t, s)
		if t == 0 then
			s.fidget, s.fidgetT, s.fidgetCut, s.last = kind, 0, 1, kind -- (this one, now)
		end
		i.hands = if kind == "checkgun" then "gun" elseif kind == "peek" then "bag" else "free"
	end)
end
for _, f in { { "stretch", 1.4 }, { "watch", 1.0 }, { "look", 0.9 }, { "checkgun", 1.2 }, { "peek", 1.0 }, { "shoulders", 0.6 } } do
	local p, r = fidget(f[1], f[2])
	emit("Fidget: " .. f[1], p, r, string.format("%.1f s in", f[2]))
end

-- The jump.
local function jump(until_, height, speed)
	local v0 = math.sqrt(2 * 196.2 * 6.4)
	local fall = height or 0
	return run(until_, function(i, t)
		local up = v0 * t - 0.5 * 196.2 * t * t
		local air = t > 0 and up > -fall
		i.air = air
		i.vy = if air then v0 - 196.2 * t else 0
		i.y = if air then up else -fall
		i.vx, i.vz = 0, -(speed or 0)
	end)
end
pose, root = jump(0.034)
emit("Jump: take-off", pose, root, "out of the crouch")
pose, root = jump(0.15)
emit("Jump: rising", pose, root)
pose, root = jump(0.4)
emit("Jump: falling", pose, root)
pose, root = jump(0.15, 0, 14)
emit("Running jump", pose, root)
local tLand = 2 * math.sqrt(2 * 196.2 * 6.4) / 196.2
pose, root = jump(tLand + 0.11)
emit("Land from 6.4 studs", pose, root, "the squash")
pose, root = jump(1.3, 400)
emit("Falling long", pose, root, "1.3 s in the air: a flail", -400)
local tFall = (math.sqrt(2 * 196.2 * 6.4) + math.sqrt(2 * 196.2 * (6.4 + 25))) / 196.2
pose, root = jump(tFall + 0.13, 25)
emit("Land from 31 studs", pose, root, "the deep squash", -25)
