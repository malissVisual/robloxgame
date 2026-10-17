-- 8.2: the counting side of tools/perf/sandbox_count.py (copied next to the stand-in as main.luau): builds the 8.x
-- SANDBOX with the real server modules and prints what each piece costs to draw (tools/perf/census.luau's rows; the
-- worst case is summed on the Python side). Server/Collection, SandboxPlots and Upgrades are sandbox_count.py's
-- stand-ins: four owners, each with every display stand open and full.
--   world/<folder>       server/SandboxWorld.luau's map, folder by folder
--   kiosks               the four Moving contracts kiosks (server/MoveSites.luau plotBoard, server/Moving.luau's
--                        sandbox boards)
--   warehouses/building  the four ZDC warehouses (server/Warehouse.luau): the hall, every stand open, the prompts
--   warehouses/shown     the pieces on show in them: every stand full, the heaviest pieces (FurnitureLooks' part count;
--                        8.3: each on a stand it fits, WarehouseLayout.fits; 10.4: the showroom's plinths full too)
--   interior             the house's inside while a move runs (server/HouseInterior.luau): the largest of SEEDS plans
--                        (8.3: the sandbox's house's kind: the big plan; 8.9: the biggest of the houses' kinds,
--                        the farmstead's, Config.Moving.Sandbox.Houses)
--   danny                Danny's body (server/Npcs.luau on the stand-in's classic R15)
--   visitors             8.3: the showroom's visitors at the server's cap (Config.Visitors.Cap; server/Visitors.luau's
--                        bodies, every kind's look in turn, each with the box of a sale: the most it can be)
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
-- (8.3: the big plan; 8.9: the biggest of the houses' contracts' kinds, "big" the farmstead's, else "house")
local KIND = "house"
for _, c in (Config.Moving.Sandbox :: any).Houses or {} do
	if c.Kind == "big" then
		KIND = "big"
	end
end

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

-- the scenery by its folders (8.9: the lamps and the signpost; the Alps' trees, flowers and fence in an older
-- checkout) and 8.8's Auction House's parts (built once Config.Auction.On, off here: sandbox_count.py adds them to the
-- map's against its budget; has-auction.luau, sandbox_count.py's, says whether this checkout has it)
local scenery = world:FindFirstChild("Scenery")
if scenery then
	for _, child in scenery:GetChildren() do
		emit("scenery/" .. child.Name, Census.under(child))
	end
end
if require("./has-auction") then
	local auction = #require("./shared/AuctionHouseLayout").parts()
	emit("auction", { parts = auction, visible = auction })
end

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
-- 8.3: the Logistics Center's stands, its 24 big ones and More stands' 8 small ones (the top level with every upgrade:
-- the stand-in Upgrades gives every owner that)
local LEVEL = WarehouseLayout.Levels
local stands = WarehouseLayout.capacity(LEVEL)
-- 10.4: and its showroom's plinths, every one (Config.Showroom's Most there), numbered past its Base
local show = WarehouseLayout.showCapacity(LEVEL)
local numbers: { number } = {}
for i = 1, stands do
	table.insert(numbers, i)
end
for k = 1, show do
	table.insert(numbers, WarehouseLayout.ShowBase + k)
end
-- 8.3: each piece where it may stand (WarehouseLayout.fits at that level: a piece only on a stand it fits), the heaviest
-- first, each on the smallest free stand it fits (so the big stands stay free for the big pieces): the heaviest the hall
-- can show
local onStand: { [number]: { id: string, n: number } } = {}
local shownParts, placed, lightest = 0, 0, nil :: { id: string, n: number }?
for _, piece in pieces do
	if placed >= #numbers then
		break
	end
	local size = FurnitureLooks.Items[piece.id].size
	local best, bestArea = nil :: number?, math.huge
	for _, i in numbers do
		local sx, sz = WarehouseLayout.standSize(i, LEVEL)
		if not onStand[i] and sx and sz and WarehouseLayout.fits(i, size, LEVEL) and sx * sz < bestArea then
			best, bestArea = i, sx * sz
		end
	end
	if best then
		onStand[best] = piece
		placed += 1
		shownParts += piece.n
		lightest = piece
	end
end
print(string.format("INFO pieces\t%d pieces, %.1f parts each on average; the %d heaviest that fit their stands (WarehouseLayout.fits): %d parts, %s %d … %s %d", #pieces, total / #pieces, placed, shownParts, pieces[1].id, pieces[1].n, if lightest then lightest.id else "-", if lightest then lightest.n else 0))
for _, plot in SandboxMap.Plots do
	local owner = { UserId = plot.id, DisplayName = `Player{plot.id}`, Name = `Player{plot.id}`, Parent = workspace }
	local entries = {}
	for _, i in numbers do
		local piece = onStand[i]
		if piece then
			table.insert(entries, { uid = `p{plot.id}s{i}`, item = piece.id, variant = 1, condition = 1, name = piece.id, stand = i })
		end
	end
	Collection.__own(owner, entries, stands, show)
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
	local model = HouseInterior.build(HouseLayout.plan(seed, KIND), HouseInterior.slot(0))
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
print(string.format("INFO interior\t%d plans of kind %s: %d – %d parts, %.0f on average", SEEDS, KIND, fewest, largestParts, sum / SEEDS))
emit("interior", largestRow :: any)
modes("interior", largest :: Model)
detail("interior", Census.list(largest))

-- ── Danny ──────────────────────────────────────────────────────────────────
local helper = Config.MoveHelper
local danny = Npcs.spawn(Npcs.look("mover", helper.Name, helper.Title), CFrame.new(0, 0, 0))
emit("danny", Census.under(danny))
detail("danny", Census.list(danny))

-- ── 8.3: the showroom's visitors (the server's cap, each with a sale's box) ─────────────────────────────────────
local Visitors = require("./server/Visitors")
local VisitorRules = require("./shared/Visitors")
local crowd = {}
local kinds = VisitorRules.kinds()
for index = 1, Config.Visitors.Cap do
	local kind = kinds[(index - 1) % #kinds + 1]
	local body = Visitors.body(kind, kind.names[1], CFrame.new(index * 5, 0, 40))
	Visitors.carry(body)
	for _, d in Census.list(body) do
		table.insert(crowd, d)
	end
end
emit("visitors", Census.of(crowd))
detail("visitors", crowd)
