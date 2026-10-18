-- 10.6 THE FLOATING ISLANDS, the fall catch: the real server/IslandFall.luau (as IslandFallServer.luau on
-- tools/perf/world-mock.luau, tests/run_tests.py) with its hooks the test's own (the bodies looked at, the fades, the
-- moves' drop, the words) and the real islands (shared/SandboxMap.luau Islands, Config.Islands.Fall):
--   * a body standing on an island, Fall.Inset inside its walls, is on it: where it stood last is kept; in the air (a
--     jump) its island is kept but not that spot; at the walls' very edge neither
--   * a player Fall.Below under its island's bottom: the screen black first (Fall.Fade.Out), moved while black (where
--     they stood last, Fall.Up over it, still, looking at the island's home), what they carried dropped there, the black
--     lifted with an arrival there (Fall.Fade.In), a notice; caught again only after Fall.Hold s
--   * no good spot of their own: the island's home (a run zone's arrive, the lobby's spawn); never on an island at all:
--     the lobby's
--   * a helper (Danny) moved at once (no fade, nothing dropped)
--   * somebody in a house's inside (far off, high over every island) left alone; falling out of it, back on the island
--     they came from; a run's jump to another island makes that one theirs
--   * the bodies it looks at: every player's character and the helpers in workspace.Npcs (MoveHelper)
--   * workspace.FallenPartsDestroyHeight (Config.Islands.Destroy) far under every island's bottom
-- Run with tests/run_tests.py.
local Mock = require("./WorldMock")
local G = Mock.globals
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local IslandFall = require("./IslandFallServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local F = Config.Islands.Fall
local V3, CF = G.Vector3.new, G.CFrame.new
local function near(a: number, b: number, e: number?): boolean
	return math.abs(a - b) <= (e or 1e-6)
end
local function at(b: any): any
	return b.root.Position
end

-- ── The fakes ──────────────────────────────────────────────────────────────
local list: { any } = {}
local fades: { any } = {}
local waits: { number } = {}
local drops: { any } = {}
local said: { any } = {}
local realBodies = IslandFall.bodies
IslandFall.bodies = function(): { any }
	return list
end
IslandFall.fade = function(player: any, way: string, seconds: number, arrival: any)
	table.insert(fades, { player = player, way = way, seconds = seconds, arrival = arrival })
end
IslandFall.after = function(seconds: number, fn: () -> ())
	table.insert(waits, seconds)
	fn() -- (while it is black: at once here)
end
IslandFall.drop = function(player: any)
	table.insert(drops, player)
end
IslandFall.say = function(player: any, text: string)
	table.insert(said, { player = player, text = text })
end

-- A body: a Model with its HumanoidRootPart and a Humanoid (standing on grass), a player's (with a fake Player) or a
-- helper's, its root at `p`.
local function body(name: string, kind: string, p: any): any
	local model = G.Instance.new("Model")
	model.Name = name
	local root = G.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = V3(2, 2, 1)
	root.CFrame = CF(p.X, p.Y, p.Z)
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = G.Instance.new("Humanoid")
	humanoid.FloorMaterial = G.Enum.Material.Grass
	humanoid.Parent = model
	model.Parent = G.workspace
	local player = if kind == "player" then { Name = name, DisplayName = name, UserId = #list + 1, Parent = G.game, Character = model } else nil
	local b = { key = player or model, root = root, model = model, humanoid = humanoid, player = player, kind = kind }
	table.insert(list, b)
	return b
end
local function move(b: any, p: any)
	b.model:PivotTo(CF(p.X, p.Y, p.Z))
end

local farm = SandboxMap.island("farm") :: SandboxMap.Island
local pond = SandboxMap.island("pond") :: SandboxMap.Island
local lodge = SandboxMap.island("lodge") :: SandboxMap.Island
local lobby = SandboxMap.Islands[1]
local function under(island: SandboxMap.Island): number
	return island.top - island.depth - F.Below - 1
end

-- ── The rules ──────────────────────────────────────────────────────────────
do
	local ok = true
	for _, island in SandboxMap.Islands do
		local w = island.walls
		ok = ok and IslandFall.fallen(island, under(island)) and not IslandFall.fallen(island, island.top - island.depth - F.Below + 0.5)
			and not IslandFall.fallen(island, island.top + 3) and IslandFall.inside(island, (w.x0 + w.x1) / 2, (w.z0 + w.z1) / 2, F.Inset)
			and not IslandFall.inside(island, w.x0 + F.Inset - 1, (w.z0 + w.z1) / 2, F.Inset) and IslandFall.inside(island, island.home.x, island.home.z, F.Inset)
			and Config.Islands.Destroy < island.top - island.depth - 300
	end
	check("every island: fallen under its bottom by Fall.Below, inside its walls by Fall.Inset, its home inside them; FallenPartsDestroyHeight far under it", ok)
	check("the lobby island first (the fall catch's last resort: a body never on an island)", lobby.id == "lobby" and lobby.house == nil)
	local home = IslandFall.spot(farm, nil)
	check("no spot of its own: the island's home, Fall.Up over it, facing its way", near(home.Position.X, farm.home.x) and near(home.Position.Y, farm.home.y + F.Up)
		and near(home.Position.Z, farm.home.z) and home.LookVector:Dot(V3(-math.sin(math.rad(farm.home.yaw)), 0, -math.cos(math.rad(farm.home.yaw)))) > 0.999)
	local w = farm.walls
	local edge = IslandFall.spot(farm, V3(w.x0 + 2, farm.top + 3, (w.z0 + w.z1) / 2))
	check("… a spot at its walls' very edge is no good: its home", near(edge.Position.X, farm.home.x) and near(edge.Position.Z, farm.home.z))
end

-- ── A player falls off the farm ────────────────────────────────────────────
local h = farm.home
local spotOn = V3(h.x + 30, farm.top + 3, h.z + 4)
local ann = body("Ann", "player", spotOn)
IslandFall.step(0)
local mark = IslandFall.markOf(ann.player)
check("standing on the farm, well inside its walls: on it, where she stood kept", mark ~= nil and mark.island == "farm" and mark.at ~= nil and (mark.at - spotOn).Magnitude < 1e-6
	and #fades == 0)
move(ann, V3(farm.rect.x0 - 40, under(farm), h.z))
IslandFall.step(1)
local put = at(ann)
check("off the edge and under the farm's bottom: black first (Fall.Fade.Out), moved while black", #fades == 2 and fades[1].way == "out" and fades[1].player == ann.player
	and fades[1].seconds == F.Fade.Out and waits[1] ~= nil and waits[1] >= F.Fade.Out, #fades)
check("… back where she stood, Fall.Up over it, looking at the island's home", near(put.X, spotOn.X) and near(put.Y, spotOn.Y + F.Up) and near(put.Z, spotOn.Z)
	and ann.model:GetPivot().LookVector:Dot((V3(h.x, put.Y, h.z) - put).Unit) > 0.99, tostring(put))
check("… what she carried dropped there (Moving.runDrop), the black lifted with an arrival there (Fall.Fade.In), a notice", #drops == 1 and drops[1] == ann.player
	and fades[2].way == "in" and fades[2].seconds == F.Fade.In and fades[2].arrival ~= nil and (fades[2].arrival.at - put).Magnitude < 1e-6
	and #said == 1 and said[1].text == F.Notice)
move(ann, V3(farm.rect.x0 - 40, under(farm), h.z))
IslandFall.step(1 + F.Hold - 0.5)
check("… caught again only after Fall.Hold s (she falls on a moment before her move)", #fades == 2)
IslandFall.step(1 + F.Hold + 0.1)
check("… and then again", #fades == 4 and #drops == 2 and near(at(ann).X, spotOn.X))

-- ── No good spot of their own ──────────────────────────────────────────────
local bo = body("Bo", "player", V3(farm.walls.x1 - 3, farm.top + 3, h.z))
IslandFall.step(10)
local bm = IslandFall.markOf(bo.player)
check("at the walls' very edge: on the farm, no spot of his own", bm ~= nil and bm.island == "farm" and bm.at == nil)
move(bo, V3(farm.walls.x1 + 40, under(farm), h.z))
IslandFall.step(11)
check("… caught: at the farm's home (the run zone's arrive), facing the door", near(at(bo).X, h.x) and near(at(bo).Y, h.y + F.Up) and near(at(bo).Z, h.z), tostring(at(bo)))
local cy = body("Cy", "player", V3(pond.home.x, pond.top + 8, pond.home.z))
cy.humanoid.FloorMaterial = G.Enum.Material.Air -- (a jump)
IslandFall.step(20)
local cm = IslandFall.markOf(cy.player)
check("in the air over the pond (a jump): the pond hers, no spot", cm ~= nil and cm.island == "pond" and cm.at == nil)
move(cy, V3(pond.rect.x1 + 30, under(pond), pond.home.z))
IslandFall.step(21)
check("… under the pond's bottom: at the pond's home", near(at(cy).X, pond.home.x) and near(at(cy).Z, pond.home.z) and near(at(cy).Y, pond.home.y + F.Up))
local dee = body("Dee", "player", V3(lobby.rect.x0 - 900, lobby.top - lobby.depth - 400, lobby.rect.z0 - 900))
IslandFall.step(30)
check("never on an island, falling in the sky: the lobby's home (its spawn)", near(at(dee).X, lobby.home.x) and near(at(dee).Z, lobby.home.z)
	and IslandFall.markOf(dee.player) ~= nil and IslandFall.markOf(dee.player).caught == 30)

-- ── A helper ───────────────────────────────────────────────────────────────
local before = #fades
local dropsBefore = #drops
local danny = body("Danny", "helper", V3(lodge.home.x + 12, lodge.top + 3, lodge.home.z + 20))
IslandFall.step(40)
local dm = IslandFall.markOf(danny.model)
check("Danny standing on the lodge's island: on it, his spot kept", dm ~= nil and dm.island == "lodge" and dm.at ~= nil)
move(danny, V3(lodge.rect.x0 - 20, under(lodge), lodge.home.z))
IslandFall.step(41)
check("… under its bottom: back on his spot at once (no fade, nothing dropped)", near(at(danny).X, lodge.home.x + 12) and near(at(danny).Z, lodge.home.z + 20)
	and #fades == before and #drops == dropsBefore)

-- ── A house's inside, a run's jump ─────────────────────────────────────────
before = #fades
move(ann, V3(9000, 400, 9000)) -- (a house's inside: server/HouseInterior.luau's slots)
IslandFall.step(50)
check("in a house's inside (far off, high over every island): left alone, the farm still hers", #fades == before and IslandFall.markOf(ann.player).island == "farm")
move(ann, V3(9000, under(farm) - 50, 9000))
IslandFall.step(51)
check("… falling out of it: back on the farm where she stood", #fades == before + 2 and near(at(ann).X, spotOn.X) and near(at(ann).Z, spotOn.Z))
local lodgeSpot = V3(lodge.home.x - 10, lodge.top + 3, lodge.home.z + 8)
move(ann, lodgeSpot) -- (a run's jump: the lodge's yard)
IslandFall.step(60)
check("a run's jump to the lodge: the lodge hers now, her spot there", IslandFall.markOf(ann.player).island == "lodge" and (IslandFall.markOf(ann.player).at - lodgeSpot).Magnitude < 1e-6)
move(ann, V3(lodge.rect.x1 + 30, under(lodge), lodge.home.z))
IslandFall.step(61)
check("… falling off it: back on the lodge", near(at(ann).X, lodgeSpot.X) and near(at(ann).Y, lodgeSpot.Y + F.Up))

-- ── The bodies it looks at ─────────────────────────────────────────────────
do
	local npcs = G.Instance.new("Folder")
	npcs.Name = "Npcs"
	npcs.Parent = G.workspace
	local helper = G.Instance.new("Model")
	helper.Name = "Danny"
	helper:SetAttribute("MoveHelper", 1)
	local root = G.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = helper
	helper.Parent = npcs
	local stranger = G.Instance.new("Model") -- (not a helper: a greeter)
	stranger.Name = "Greeter"
	local sroot = G.Instance.new("Part")
	sroot.Name = "HumanoidRootPart"
	sroot.Parent = stranger
	stranger.Parent = npcs
	local found = realBodies()
	check("the bodies: every player's character and the helpers in workspace.Npcs (MoveHelper) with their roots", #found == 1 and found[1].kind == "helper"
		and found[1].key == helper and found[1].root == root and found[1].player == nil, #found)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
