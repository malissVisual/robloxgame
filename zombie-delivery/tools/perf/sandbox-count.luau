-- 8.2: the counting side of tools/perf/sandbox_count.py (copied next to the stand-in as main.luau): builds the 8.x
-- SANDBOX with the real server modules and prints what each piece costs to draw (tools/perf/census.luau's rows; the
-- worst case is summed on the Python side). Server/Collection, SandboxPlots and Upgrades are sandbox_count.py's
-- stand-ins: four owners, each with every display stand open and full.
--   world/<folder>       server/SandboxWorld.luau's map, folder by folder
--   kiosks               the four Moving contracts kiosks (server/MoveSites.luau plotBoard, server/Moving.luau's
--                        sandbox boards)
--   warehouses/building  the four ZDC warehouses (server/Warehouse.luau): the hall, every stand open, the prompts
--   warehouses/shown     the pieces on show in them: every stand full, the heaviest pieces (FurnitureLooks' part count)
--   interior             the house's inside while a move runs (server/HouseInterior.luau): the largest of SEEDS plans
--   danny                Danny's body (server/Npcs.luau on the stand-in's classic R15)
setfenv(1, require("./mock").env)
local Census = require("./census")
local Config = require("./shared/Config")
local SandboxMap = require("./shared/SandboxMap")
local FurnitureLooks = require("./shared/FurnitureLooks")
local WarehouseLayout = require("./shared/WarehouseLayout")
local HouseLayout = require("./shared/HouseLayout")
local SandboxWorld = require("./server/SandboxWorld")
local MoveSites = require("./server/MoveSites")
local HouseInterior = require("./server/HouseInterior")
local Npcs = require("./server/Npcs")
local Collection = require("./server/Collection") -- (the stand-in)
local SandboxPlots = require("./server/SandboxPlots") -- (the stand-in)

local SEEDS = 24 -- house plans tried for the interior's worst case

local function emit(label: string, row: { [string]: number })
	print(Census.line(label, row))
end

-- the costly ones by name (Census.detail)
local function detail(label: string, list: { Instance })
	for _, line in Census.detail(list) do
		print(`DETAIL {label}\t{line}`)
	end
end

local function modes(label: string, root: Instance)
	local out = {}
	for mode, n in Census.modes(root) do
		table.insert(out, `{mode} {n}`)
	end
	table.sort(out)
	print(`MODES {label}\t{table.concat(out, ", ")}`)
end

-- ── The map ────────────────────────────────────────────────────────────────
local world = SandboxWorld.build()
for _, child in world:GetChildren() do
	emit("world/" .. child.Name, Census.under(child))
end
modes("world", world)
detail("world", Census.list(world))

-- ── The kiosks ─────────────────────────────────────────────────────────────
local kiosks = Instance.new("Folder")
kiosks.Name = "MovingBoards"
kiosks.Parent = workspace
for _, plot in SandboxMap.Plots do
	MoveSites.plotBoard(kiosks, plot)
end
emit("kiosks", Census.under(kiosks))
modes("kiosks", kiosks)
detail("kiosks", Census.list(kiosks))

-- ── The warehouses: four owners, every stand open, the heaviest pieces on show ─────────────────────────────────
local pieces = {}
local total = 0
for _, id in FurnitureLooks.Order do
	local n = FurnitureLooks.parts(id)
	total += n
	table.insert(pieces, { id = id, n = n })
end
table.sort(pieces, function(a, b)
	return if a.n == b.n then a.id < b.id else a.n > b.n
end)
local stands = WarehouseLayout.capacity()
local shownParts = 0
for i = 1, stands do
	shownParts += pieces[i].n
end
print(string.format("INFO pieces\t%d pieces, %.1f parts each on average; the %d heaviest (on every stand): %d parts, %s %d … %s %d", #pieces, total / #pieces, stands, shownParts, pieces[1].id, pieces[1].n, pieces[stands].id, pieces[stands].n))
for _, plot in SandboxMap.Plots do
	local owner = { UserId = plot.id, DisplayName = `Player{plot.id}`, Name = `Player{plot.id}`, Parent = workspace }
	local entries = {}
	for i = 1, stands do
		local piece = pieces[i]
		table.insert(entries, { uid = `p{plot.id}s{i}`, item = piece.id, variant = 1, condition = 1, name = piece.id, stand = i })
	end
	Collection.__own(owner, entries, stands)
	SandboxPlots.__own(plot.id, owner)
end
local Warehouse = require("./server/Warehouse")
Warehouse.start()
local halls = workspace:FindFirstChild("Warehouses") :: Instance
local building, shown = {}, {}
for _, d in halls:GetDescendants() do
	if d:FindFirstAncestor("Shown") then
		table.insert(shown, d)
	else
		table.insert(building, d)
	end
end
emit("warehouses/building", Census.of(building))
emit("warehouses/shown", Census.of(shown))
modes("warehouses", halls)
detail("warehouses/building", building)
detail("warehouses/shown", shown)

-- ── The house's inside (the largest of SEEDS plans) ────────────────────────
local largest: Model? = nil
local largestRow, largestParts, sum, fewest = nil, -1, 0, math.huge
for seed = 1, SEEDS do
	local model = HouseInterior.build(HouseLayout.plan(seed, "house"), HouseInterior.slot(0))
	local row = Census.under(model)
	sum += row.parts
	fewest = math.min(fewest, row.parts)
	if row.parts > largestParts then
		if largest then
			largest:Destroy()
		end
		largest, largestRow, largestParts = model, row, row.parts
	else
		model:Destroy()
	end
end
print(string.format("INFO interior\t%d plans: %d – %d parts, %.0f on average", SEEDS, fewest, largestParts, sum / SEEDS))
emit("interior", largestRow :: any)
modes("interior", largest :: Model)
detail("interior", Census.list(largest))

-- ── Danny ──────────────────────────────────────────────────────────────────
local helper = Config.MoveHelper
local danny = Npcs.spawn(Npcs.look("mover", helper.Name, helper.Title), CFrame.new(0, 0, 0))
emit("danny", Census.under(danny))
detail("danny", Census.list(danny))
