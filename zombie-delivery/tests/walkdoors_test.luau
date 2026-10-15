-- 8.5.1 (the owner: "The doors, when you go into the house, just disappear. I'd like them to open nicely"): the sandbox
-- house's door leaves as the real server/SandboxWorld.luau builds them (on tools/perf/world-mock.luau: the chalet's own
-- leaves, and the Blender house's doors copied as leaves, SandboxWorld.doorLeaves on a dressed house), each one as a
-- client gets it (its parts, frames, attributes and its DoorLeaf tag, tests/runtime/ClientRuntime.luau), swung by the
-- real client/WalkDoors.luau (WalkDoorsClient.luau) frame by frame:
--   * the leaves are seen (not see-through) and open Config.Moving.Doors.Wide degrees, past square (square to the wall
--     they were edge-on to a player walking up: the door seemed to vanish);
--   * open (DoorOpen, as server/Moving.luau's WalkIn.open says it): a swing over Open s (0.25 … 0.35), never a pop (no
--     frame turns it more than a quadratic start would, half its time not even 80 % of the way), out of the house: its
--     free end toward whoever walks up outside;
--   * the dark doorway (DoorDark) shows where it stood while it is open; dressed, in front of the Blender house's own
--     door (it stays drawn in its pocket behind the copies: covered shut by them, open by the dark doorway);
--   * shut again over Close s, back in its frame;
--   * a leaf a client first sees while it is opening (its DoorOpen came with its tag, it streamed in as it opened: its
--     DoorOpenAt, the server's time it opened) swings on from where it is by now; one long open stands open at once.
local W = require("./WorldMock")
local G = W.globals
local Config = require("./Config")
local DoorSwing = require("./DoorSwing")
local SandboxMap = require("./SandboxMap")
local SandboxWorld = require("./SandboxWorldServer")
local HouseArt = require("./HouseArt")
local C = require("./ClientRuntime")
local WalkDoors = require("./WalkDoorsClient")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local D = Config.Moving.Doors
local H = SandboxMap.House
local FRAME = 1 / 60

-- ── The leaves as the server builds them ─────────────────────────────────────

local world = SandboxWorld.build()
local chalet = world:FindFirstChild("TheOldFarmstead")
local plain: { any } = {}
for _, d in (if chalet then chalet:GetDescendants() else {}) do
	if d:GetAttribute("DoorLeaf") ~= nil then
		table.insert(plain, d)
	end
end
-- a house dressed in the owner's model (as the import does: sandboxworld_test's way), its doors copied as leaves
local dressedHouse = G.Instance.new("Model")
local dressedBody = G.Instance.new("Model")
dressedBody.Name = "House_" .. H.id
dressedBody:SetAttribute("MeshArt", true)
dressedBody.Parent = dressedHouse
local copies = SandboxWorld.doorLeaves(dressedHouse)
check("the chalet's three leaves (FrontLeafWest, FrontLeafEast, BackLeaf) and, dressed, the Blender house's doors copied as three",
	#plain == 3 and #copies == 3, `{#plain} {#copies}`)
local wideOk = true
for _, leaf in { table.unpack(plain), table.unpack(copies) } do
	wideOk = wideOk and leaf:GetAttribute("DoorAngle") == D.Wide and leaf:GetAttribute("DoorSwing") == -1 and leaf:GetAttribute("DoorDark") == true
end
check(`8.5.1 every one opens Wide ({D.Wide}°: past square, never edge-on to a player walking up), out of the house (DoorSwing -1), a dark doorway behind`,
	wideOk and D.Wide > 90 and D.Wide <= 120 and D.Angle < D.Wide)

-- The client's copy of a leaf (a part, or a model and its parts): frames, sizes, looks, attributes; tagged DoorLeaf.
local function cf(frame: any): any
	return C.CFrame.new(frame:GetComponents())
end
local function v3(v: any): any
	return C.Vector3.new(v.X, v.Y, v.Z)
end
local holder = C.new("Folder", "Leaves", C.workspace)
local function mirror(inst: any, parent: any): any
	local copy = C.new(inst.ClassName, inst.Name, parent)
	if inst.ClassName ~= "Model" then
		copy.CFrame, copy.Size, copy.Transparency = cf(inst.CFrame), v3(inst.Size), inst.Transparency or 0
	end
	for name, value in inst:GetAttributes() do
		copy:SetAttribute(name, value)
	end
	for _, child in inst:GetChildren() do
		local made = mirror(child, copy)
		if inst.ClassName == "Model" and inst.PrimaryPart == child then
			copy.PrimaryPart = made
		end
	end
	return copy
end
local function primary(leaf: any): any
	return if leaf.ClassName == "Model" then leaf.PrimaryPart else leaf
end
-- the dark doorway this client made for it (in it, or beside a model: where it stood shut)
local function darkOf(leaf: any, shut: any): any
	for _, d in (if leaf.ClassName == "Model" then leaf.Parent else leaf):GetChildren() do
		if d.Name == "DoorDark" and (d.CFrame.Position - shut.Position).Magnitude < 1e-6 then
			return d
		end
	end
	return nil
end

WalkDoors.start()
local function frames(seconds: number, each: (() -> ())?)
	for _ = 1, math.ceil(seconds / FRAME - 1e-9) do
		C.clock += FRAME
		C.now += FRAME
		C.heartbeat:Fire(FRAME)
		if each then
			each()
		end
	end
end

-- One leaf swung open and shut on the client: its frame each frame (its turn from shut, about its hinge's upright, in
-- degrees), its free end's way (out of the house: -Z of its door's frame), the dark doorway. `door`: its door's frame
-- (H.door's, H.back's: -Z out).
local function swingOf(server: any, door: any): any
	local leaf = mirror(server, holder)
	C.CollectionService:AddTag(leaf, "DoorLeaf")
	local part = primary(leaf)
	local shut = part.CFrame
	local seen = part.Transparency < 0.99
	for _, d in (if leaf.ClassName == "Model" then leaf:GetDescendants() else {}) do
		seen = seen and d.Transparency < 0.99
	end
	local function turned(): number
		local rel = shut:Inverse() * part.CFrame
		return math.deg(math.atan2(rel.R[3], rel.R[1]))
	end
	local hinge = DoorSwing.pieces(part.Size.X, part.Size.Z, leaf:GetAttribute("DoorLeaf"), leaf:GetAttribute("DoorSwing"), leaf:GetAttribute("DoorAngle"))[1]
	-- (its free end: the far end of its width from its hinge)
	local function freeEnd(): any
		return part.CFrame * C.Vector3.new(-hinge.hx, 0, 0)
	end
	local start = door:PointToObjectSpace(G.Vector3.new(freeEnd().X, freeEnd().Y, freeEnd().Z))
	leaf:SetAttribute("DoorOpenAt", C.now) -- (WalkIn.open)
	leaf:SetAttribute("DoorOpen", true)
	local t, angles, biggest, half, at = 0, {}, 0, nil, 0
	local was = 0
	frames(D.Open + 0.2, function()
		t += FRAME
		local a = math.abs(turned())
		table.insert(angles, a)
		biggest = math.max(biggest, a - was)
		was = a
		if half == nil and t >= D.Open / 2 then
			half = a
		end
		if at == 0 and a >= D.Wide - 0.01 then
			at = t
		end
	end)
	local stop = door:PointToObjectSpace(G.Vector3.new(freeEnd().X, freeEnd().Y, freeEnd().Z))
	local dark = darkOf(leaf, shut)
	local darkOpen = dark ~= nil and dark.Transparency == 0
	local result = { leaf = leaf, seen = seen, angles = angles, biggest = biggest, half = half, reached = at, out = stop.Z - start.Z, final = math.abs(turned()),
		dark = dark, darkOpen = darkOpen }
	leaf:SetAttribute("DoorOpen", false)
	frames(D.Close + 0.2)
	result.shutAgain = (part.CFrame.Position - shut.Position).Magnitude < 1e-6 and math.abs(turned()) < 1e-6 and (dark == nil or dark.Transparency == 1)
	return result
end
local frontFrame = G.CFrame.new(H.door.x, H.door.y, H.door.z) * G.CFrame.Angles(0, math.rad(H.door.yaw), 0)
local backFrame = G.CFrame.new(H.back.x, H.back.y, H.back.z) * G.CFrame.Angles(0, math.rad(H.back.yaw), 0)
local quadStep = math.deg(math.rad(D.Wide) * 2 * FRAME / D.Open) + 0.01 -- (a quadratic start's first frame)
local function judge(label: string, server: any, door: any)
	local r = swingOf(server, door)
	check(`8.5.1 {label}: seen (not see-through), it swings open over Open s ({D.Open}), never a pop, to Wide ({D.Wide}°)`, r.seen
		and math.abs(r.final - D.Wide) < 0.01 and r.reached >= D.Open - FRAME - 1e-6 and r.reached <= D.Open + FRAME + 1e-6
		and r.biggest <= quadStep and r.half ~= nil and r.half <= 0.8 * D.Wide and r.half >= 0.5 * D.Wide,
		`final {r.final}, reached {r.reached} s, biggest frame {r.biggest}°, at half its time {r.half}°`)
	check(`…out of the house, toward whoever walks up to it (its free end {string.format("%.2f", -r.out)} studs out)`, r.out < -1)
	check("…the dark doorway shown while it is open, gone with it shut, back in its frame", r.darkOpen and r.shutAgain)
	return r
end
local byName: { [string]: any } = {}
for _, leaf in plain do
	byName[leaf.Name] = leaf
end
judge("the chalet's front door, its west leaf", byName.FrontLeafWest, frontFrame)
judge("…its east leaf", byName.FrontLeafEast, frontFrame)
judge("the chalet's back door's leaf", byName.BackLeaf, backFrame)
local copyRuns: { any } = {}
for n, leaf in copies do
	table.insert(copyRuns, judge(`dressed: the Blender house's {if n <= 2 then "front" else "back"} door's copy {n}`, leaf, if n <= 2 then frontFrame else backFrame))
end
-- dressed: the Blender house's own door stays drawn (part of its mesh), in its pocket behind the copies; open, the dark
-- doorways (the front copies') cover all of it in front of it
local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
local house = G.CFrame.new(H.house.x, H.house.y, H.house.z) * G.CFrame.Angles(0, math.rad(H.door.yaw), 0)
for n = 1, 2 do
	local dark = copyRuns[n].dark
	if dark then
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = dark.CFrame * C.Vector3.new(sx * dark.Size.X / 2, sy * dark.Size.Y / 2, sz * dark.Size.Z / 2)
					local q = house:PointToObjectSpace(G.Vector3.new(p.X, p.Y, p.Z))
					lo = { math.min(lo[1], q.X), math.min(lo[2], q.Y), math.min(lo[3], q.Z) }
					hi = { math.max(hi[1], q.X), math.max(hi[2], q.Y), math.max(hi[3], q.Z) }
				end
			end
		end
	end
end
local a = HouseArt.door
check("8.5.1 dressed: open, the copies' dark doorways cover the Blender house's own door (drawn in its pocket) from the front: never seen through them",
	lo[1] <= a.x0 + 1e-6 and hi[1] >= a.x1 - 1e-6 and lo[2] <= a.y0 + 0.02 and hi[2] >= a.y1 - 0.02 and hi[3] <= a.z0,
	string.format("dark %.2f … %.2f, %.2f … %.2f, %.2f … %.2f; the model's door %.2f … %.2f, %.2f … %.2f, from %.2f", lo[1], hi[1], lo[2], hi[2], lo[3], hi[3],
		a.x0, a.x1, a.y0, a.y1, a.z0))

-- ── First seen while opening, or long open ─────────────────────────────────

-- its DoorOpen and DoorOpenAt there before its tag reaches this client (as they come together, or it streamed in)
local function firstSeen(server: any, ago: number): (number, number)
	local leaf = mirror(server, holder)
	leaf:SetAttribute("DoorOpenAt", C.now - ago)
	leaf:SetAttribute("DoorOpen", true)
	local part = primary(leaf)
	local shut = part.CFrame
	local function turned(): number
		local rel = shut:Inverse() * part.CFrame
		return math.abs(math.deg(math.atan2(rel.R[3], rel.R[1])))
	end
	C.CollectionService:AddTag(leaf, "DoorLeaf")
	local first = turned()
	frames(FRAME)
	local next = turned()
	frames(D.Open)
	return first, next, turned()
end
local first, after, final = firstSeen(copies[1], 0.1)
local want = DoorSwing.ease(0.1 / D.Open, true) * D.Wide
check("8.5.1 first seen 0.1 s into its swing (its DoorOpen came with its tag): on from where it is by now, never stood open at once",
	math.abs(first - want) < 0.5 and after > first and first < D.Wide * 0.75 and math.abs(final - D.Wide) < 0.01, `{first}° (want {want}°) → {after}° → {final}°`)
first = firstSeen(copies[2], 5)
check("…first seen long open (it streamed in, you joined late): open at once", math.abs(first - D.Wide) < 0.01, first)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
