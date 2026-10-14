-- 8.0 SANDBOX, the warehouse: the real server/Warehouse.luau (WarehouseServer.luau, built by tests/run_tests.py) on the
-- recorder with a fake SandboxPlots and a fake Collection (tests/runtime/WarehouseRuntime.luau):
--   * every plot's warehouse is built, within Config.Warehouse.MaxParts, everything anchored; FOR RENT on a free plot,
--     "<Name>'s Warehouse" on an owned one (an owner from before the start too)
--   * the stands' prompts are the owner's only: none on a free plot; tagged for client/CargoPrompts.luau with the
--     owner's UserId; a stranger's use does nothing but a notice; the owner's "Display" opens the picker
--   * a piece on show builds its model on its stand (anchored, in the podium's middle, on its top, looking south), its
--     tag (name, rarity, +$X/min) and swaps the stand's prompts to Take down / Sell; the STOCK board counts
--   * Take down and Sell go through the Collection and take the model away; two pieces share the income by worth
--   * the owner leaves: the pieces go, the sign is FOR RENT, the prompts go; a new owner gets fresh prompts
--   * 8.1, the upgrades: the tags are × Collection.boost; the UPGRADES desk's prompt is the owner's (Upgrades.open), a
--     stranger's use a notice, a free plot none, a new owner a fresh one
--   * 8.3, the levels: a free plot's warehouse is the start's Garage, an owner's their level's (Upgrades.warehouseLevel:
--     the Model's Level, its stands, its parts the layout's); growing (4 → 5) builds a new Model in place (the old one
--     gone), the pieces on show back on their stands (one past the old level's shows now), the sign, the board and fresh
--     prompts with it; a player the new stands would catch is moved to the receiving zone, one in the aisle stays; the
--     same level again builds nothing; shrinking (the admin's) hides what is past the stands; the owner leaving: the
--     start's level again; a new owner: theirs
-- Run with tests/run_tests.py.
local W = require("./WarehouseRuntime")
local Warehouse = require("./WarehouseServer")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local WarehouseLayout = require("./WarehouseLayout")

local M = W.Mock
local T = Config.Warehouse
local STANDS = Config.WarehouseLevels.List[4].stands -- (Ana's: the Big warehouse's 12)
local CollectionRules = require("./CollectionRules")
-- (8.0 merge) a shown piece's tag line as the collection's rules have it: its rarity and its own income a minute
local function tagOf(entry: any): string
	return WarehouseLayout.tagLines(entry.name, CollectionRules.rarityOf(CollectionRules.defOf(entry.item)), CollectionRules.income(entry))[2].text
end

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function parts(model: any, skipShown: boolean): (number, boolean)
	local count, anchored = 0, true
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not (skipShown and d:IsDescendantOf(model:FindFirstChild("Shown"))) then
			count += 1
			anchored = anchored and d.Anchored == true
		end
	end
	return count, anchored
end
local function line(part: any, n: number): string
	local gui = part and part:FindFirstChild("WordsFront")
	local label = gui and gui:FindFirstChild(`Line{n}`)
	return if label then tostring(label.Text) else "?"
end
local function stand(id: number, i: number): any
	return Warehouse.model(id):FindFirstChild(`Stand{i}`)
end
local function promptsOf(id: number, i: number): any
	local anchor = stand(id, i):FindFirstChild("Prompts")
	return {
		display = anchor:FindFirstChild("Display"),
		takeDown = anchor:FindFirstChild("TakeDown"),
		sell = anchor:FindFirstChild("Sell"),
	}
end
local function tagText(id: number, i: number): (boolean, string, string)
	local tag = stand(id, i):FindFirstChild("Tag")
	local back = tag:FindFirstChild("Back")
	return tag.Enabled == true, tostring(back:FindFirstChild("Line1").Text), tostring(back:FindFirstChild("Line2").Text)
end

-- Ana owns plot 2 before the warehouses are built; plot 1 stays free.
local ana = W.player(101, "Ana", M.Vector3.new(-65, 3, -150))
local bob = W.player(202, "Bob", M.Vector3.new(-65, 3, -152))
W.levels[ana] = 4 -- (8.3: her warehouse is the Big warehouse, 12 stands)
W.claim(2, ana)
Warehouse.start()

local folder = M.workspace:FindFirstChild("Warehouses")
check("four warehouses under workspace.Warehouses", folder ~= nil and #folder:GetChildren() == #SandboxMap.Plots, folder and #folder:GetChildren())
local budgetOk, anchoredOk, most = true, true, 0
for _, plot in SandboxMap.Plots do
	local count, anchored = parts(Warehouse.model(plot.id), true)
	most = math.max(most, count)
	budgetOk = budgetOk and count <= T.MaxParts and count == #WarehouseLayout.pieces(plot, Warehouse.level(plot.id))
	anchoredOk = anchoredOk and anchored
end
print(`  {most} parts a warehouse (the budget {T.MaxParts})`)
check("every warehouse is its layout's pieces, within the part budget, all anchored", budgetOk and anchoredOk, most)

local sign1 = Warehouse.model(1):FindFirstChild("OwnerSign")
local sign2 = Warehouse.model(2):FindFirstChild("OwnerSign")
check("a free plot's sign: FOR RENT", line(sign1, 1) == "FOR RENT", line(sign1, 1))
check("an owner from before the start: Ana's Warehouse", line(sign2, 1) == "Ana's Warehouse" and line(sign2, 2) == "ZDC STORAGE · PLOT 2", line(sign2, 1))

-- the prompts: the owner's only
local free = stand(1, 1):FindFirstChild("Prompts")
check("a free plot's stands have no prompts", free ~= nil and #free:GetChildren() == 0)
local allOk = true
for i = 1, STANDS do
	local p = promptsOf(2, i)
	allOk = allOk
		and p.display and p.takeDown and p.sell
		and p.display.Enabled == true and p.takeDown.Enabled == false and p.sell.Enabled == false
		and p.display:GetAttribute("CargoOwner") == 101 and p.sell:GetAttribute("CargoOwner") == 101
		and p.display:GetAttribute("Tag_" .. Config.Cargo.PromptTag) == true and p.takeDown:GetAttribute("Tag_" .. Config.Cargo.PromptTag) == true
		and p.display.ActionText == "Display" and p.display.KeyboardKeyCode == "E"
		and p.sell.ActionText == "Sell" and p.sell.KeyboardKeyCode == "F" and p.sell.HoldDuration == T.SellHold
		and p.takeDown.ActionText == "Take down"
end
check("an owned plot's every stand: Display on (E), Take down and Sell (hold F) off; tagged as Ana's (CargoOwner) for CargoPrompts", allOk)

local p3 = promptsOf(2, 3)
p3.display.Triggered:Fire(bob)
check("a stranger's Display: no picker, a notice", W.lastCall("openPicker") == nil and W.lastNotice(bob) == "This is Ana's warehouse.", W.lastNotice(bob))
p3.display.Triggered:Fire(ana)
local pick = W.lastCall("openPicker")
check("the owner's Display opens the picker for that stand (Collection.openPicker)", pick ~= nil and pick[2] == ana and pick[3] == 3)

-- a piece on show on stand 3, another in stock
W.income[ana] = 6
W.give(ana, { uid = "u1", item = "sofa", variant = 2, condition = 0.8, name = "Sofa", stand = 3, got = 0 })
W.give(ana, { uid = "u2", item = "lamp_unknown", variant = 1, condition = 1, name = "Box", got = 0 })
local sofa = Warehouse.shown(2, 3)
local spot = WarehouseLayout.stand(SandboxMap.Plots[2], 3, 4) :: WarehouseLayout.Stand
local root = sofa and sofa.PrimaryPart
local placed = root ~= nil
	and math.abs(root.Position.X - spot.x) < 1e-6 and math.abs(root.Position.Z - spot.z) < 1e-6
	and math.abs(root.Position.Y - root.Size.Y / 2 - spot.y) < 1e-6
	and math.abs(root.CFrame.LookVector.Z - 1) < 1e-6 -- (looking south, +Z)
local anchoredPiece = false
if sofa then
	anchoredPiece = select(2, parts(sofa, false))
end
check("a shown entry builds its model on its stand: in the podium's middle, on its top, looking south", placed, root and root.Position)
check("…anchored, in the warehouse's Shown folder, its FurnitureId and stand", anchoredPiece and sofa.Parent == Warehouse.model(2):FindFirstChild("Shown") and sofa:GetAttribute("FurnitureId") == "sofa" and sofa:GetAttribute("Stand") == 3)
check("…no other stand shows anything", Warehouse.shown(2, 1) == nil and Warehouse.shown(2, 4) == nil and Warehouse.shown(1, 3) == nil)
local on, name, info = tagText(2, 3)
local sofaEntry = { uid = "u1", item = "sofa", variant = 2, condition = 0.8, name = "Sofa", stand = 3, got = 0 }
check("…its tag: Sofa, its rarity · +$X/min (the collection's rules: CollectionRules.income)", on and name == "Sofa" and info == tagOf(sofaEntry), info)
check("…an empty stand's tag is off", not (tagText(2, 4)))
p3 = promptsOf(2, 3)
check("…its prompts: Take down and Sell on, Display off", p3.display.Enabled == false and p3.takeDown.Enabled == true and p3.sell.Enabled == true and p3.sell.ObjectText == "Sofa")
local board = Warehouse.model(2):FindFirstChild("StockBoard")
check("the STOCK board: 📦 1 piece in stock · $6/min, 1 of 12 on show", line(board, 2) == "📦 1 piece in stock · $6/min" and line(board, 3) == `1 of {STANDS} stands on show`, line(board, 2))

-- the same change again: the model stays (only changed stands are rebuilt)
W.changed(ana)
check("a change that leaves stand 3 as it was keeps its model", Warehouse.shown(2, 3) == sofa)

-- two on show share the income by worth (value × condition): the TV (300 × 1) and the sofa (350 × 0.8 = 280)
W.income[ana] = 58
W.give(ana, { uid = "u3", item = "tv", variant = 1, condition = 1, name = "Old TV", stand = 1, got = 0 })
local _, _, tvInfo = tagText(2, 1)
local _, _, sofaInfo = tagText(2, 3)
check("two on show: each its own rarity and income (the collection's rules)", tvInfo == tagOf({ item = "tv", condition = 1, name = "Old TV" }) and sofaInfo == tagOf(sofaEntry), `{tvInfo} / {sofaInfo}`)

-- Take down (the owner): through the Collection, the model goes
local tv = Warehouse.shown(2, 1)
W.later()
promptsOf(2, 1).takeDown.Triggered:Fire(ana)
local down = W.lastCall("undisplay")
check("Take down: Collection.undisplay of that stand's piece, the model gone, a notice", down ~= nil and down[3] == "u3" and Warehouse.shown(2, 1) == nil and tv.destroyed == true and W.lastNotice(ana) == "Old TV is back in your stock.", W.lastNotice(ana))
check("…the stand offers Display again", promptsOf(2, 1).display.Enabled == true and promptsOf(2, 1).sell.Enabled == false)
-- a stranger's Sell does nothing; the owner's twice at once sells once
W.later()
promptsOf(2, 3).sell.Triggered:Fire(bob)
check("a stranger's Sell: no sale", W.lastCall("sell") == nil and Warehouse.shown(2, 3) ~= nil)
local sellPrompt = promptsOf(2, 3).sell
sellPrompt.Triggered:Fire(ana)
sellPrompt.Triggered:Fire(ana)
local sold = W.lastCall("sell")
local sales = 0
for _, call in W.calls do
	sales += if call[1] == "sell" then 1 else 0
end
check("the owner's Sell: Collection.sell of that piece, the model gone", sold ~= nil and sold[3] == "u1" and sales == 1 and Warehouse.shown(2, 3) == nil and sofa.destroyed == true)
check("…the board: 2 pieces in stock, 0 on show", line(board, 2) == "📦 2 pieces in stock · $58/min" and line(board, 3) == `0 of {STANDS} stands on show`, line(board, 2))

-- a stand number past the warehouse's: never shown
W.give(ana, { uid = "u9", item = "box", variant = 1, condition = 1, name = "Box", stand = STANDS + 1, got = 0 })
local stray = false
for i = 1, STANDS do
	stray = stray or Warehouse.shown(2, i) ~= nil
end
check("an entry on a stand the warehouse lacks is not shown", not stray and Warehouse.shown(2, STANDS + 1) == nil)

-- ── 8.3: the levels ─────────────────────────────────────────────────────────
local function hasStand(id: number, i: number): boolean
	return Warehouse.model(id):FindFirstChild(`Stand{i}`) ~= nil
end
local function standsBuilt(id: number): number
	local n = 0
	while hasStand(id, n + 1) do
		n += 1
	end
	return n
end
local function partsOfLevel(id: number): boolean
	local count = parts(Warehouse.model(id), true)
	return count == #WarehouseLayout.pieces(SandboxMap.Plots[id], Warehouse.level(id)) and count <= T.MaxParts
end
check("8.3: a free plot's warehouse is the start's Garage (level 1: 2 stands, the model's Level 1), FOR RENT", Warehouse.level(1) == 1 and Warehouse.model(1):GetAttribute("Level") == 1
	and standsBuilt(1) == 2 and line(Warehouse.model(1):FindFirstChild("OwnerSign"), 1) == "FOR RENT" and partsOfLevel(1))
check("8.3: Ana's (an owner from before the start) is her level's, the Big warehouse (4: 12 stands)", Warehouse.level(2) == 4 and Warehouse.model(2):GetAttribute("Level") == 4
	and standsBuilt(2) == 12 and partsOfLevel(2))

-- the Showroom lights: the tags × Collection.boost
W.give(ana, { uid = "u5", item = "tv", variant = 1, condition = 1, name = "Old TV", stand = 2, got = 0 })
local tvBefore = Warehouse.shown(2, 2)
W.boosts[ana] = 1.21
W.changed(ana)
local _, _, lit = tagText(2, 2)
local tvEntry = { item = "tv", condition = 1 }
check("8.1: the Showroom lights (Collection.boost 1.21): the tag's $/min × 1.21", lit == WarehouseLayout.tagLines("Old TV", CollectionRules.rarityOf(CollectionRules.defOf("tv")), CollectionRules.income(tvEntry, 1.21))[2].text
	and lit ~= tagOf(tvEntry), lit)
W.boosts[ana] = nil
W.changed(ana)

-- the UPGRADES desk: the owner's prompt
local desk2, desk1 = Warehouse.terminal(2), Warehouse.terminal(1)
local deskPrompt = desk2 and desk2:FindFirstChild("Prompts") and desk2:FindFirstChild("Prompts"):FindFirstChild("Upgrades")
check("8.1: the UPGRADES desk: the owner's \"Upgrades\" prompt (E), tagged as Ana's for CargoPrompts; a free plot's desk has none", deskPrompt ~= nil and deskPrompt.ActionText == "Upgrades"
	and deskPrompt.KeyboardKeyCode == "E" and deskPrompt:GetAttribute("CargoOwner") == 101 and deskPrompt:GetAttribute("Tag_" .. Config.Cargo.PromptTag) == true
	and desk1 ~= nil and #desk1:FindFirstChild("Prompts"):GetChildren() == 0 and desk2.Name == "TerminalDesk")
W.later()
deskPrompt.Triggered:Fire(bob)
check("8.1: … a stranger's use: no window, a notice", W.lastCall("openUpgrades") == nil and W.lastNotice(bob) == "This is Ana's warehouse.", W.lastNotice(bob))
W.later()
deskPrompt.Triggered:Fire(ana)
local opened = W.lastCall("openUpgrades")
check("8.1: … the owner's: Upgrades.open (the window)", opened ~= nil and opened[2] == ana)

-- growing: level 4 → 5 (the UPGRADES desk's Warehouse card; Collection.upgrade tells the warehouse through onChanged)
local plot2 = SandboxMap.Plots[2]
local old = Warehouse.model(2)
local oldSign = old:FindFirstChild("OwnerSign")
local stand19 = WarehouseLayout.stand(plot2, 19, 5) :: WarehouseLayout.Stand
local cy = W.player(303, "Cy", M.Vector3.new(stand19.x, 3, stand19.z)) -- (behind the Big warehouse: where stand 19 will stand)
W.place(bob, M.Vector3.new(plot2.door.x, 3, plot2.door.z - 40)) -- (in the middle aisle at both levels)
W.levels[ana] = 5
W.changed(ana)
local grown = Warehouse.model(2)
check("8.3: grown to the Logistics centre: a new Model (Level 5) in place of the old one (gone), 20 stands, within the budget", grown ~= old and old.destroyed == true
	and grown:GetAttribute("Level") == 5 and Warehouse.level(2) == 5 and standsBuilt(2) == 20 and partsOfLevel(2) and grown.Parent == M.workspace:FindFirstChild("Warehouses"))
local tvAfter = Warehouse.shown(2, 2)
local spot2 = WarehouseLayout.stand(plot2, 2, 5) :: WarehouseLayout.Stand
local tvRoot = tvAfter and tvAfter.PrimaryPart
check("8.3: … the pieces on show stay on their stands: the TV on stand 2 again (its new place), the box on 13 shows now", tvAfter ~= nil and tvAfter ~= tvBefore and tvBefore.destroyed == true
	and tvRoot ~= nil and math.abs(tvRoot.Position.X - spot2.x) < 1e-6 and math.abs(tvRoot.Position.Z - spot2.z) < 1e-6 and Warehouse.shown(2, 13) ~= nil and tvAfter:GetAttribute("Uid") == "u5")
check("8.3: … her sign and board on the new building (20 stands), fresh prompts for her on every stand and the desk", oldSign.destroyed == true
	and line(grown:FindFirstChild("OwnerSign"), 1) == "Ana's Warehouse" and line(grown:FindFirstChild("StockBoard"), 3) == "2 of 20 stands on show"
	and promptsOf(2, 20).display.Enabled == true and promptsOf(2, 20).display:GetAttribute("CargoOwner") == 101 and promptsOf(2, 2).takeDown.Enabled == true
	and Warehouse.terminal(2):FindFirstChild("Prompts"):FindFirstChild("Upgrades") ~= nil and deskPrompt.destroyed == true, line(grown:FindFirstChild("StockBoard"), 3))
local zone = WarehouseLayout.receiving(plot2, 5)
local cyAt, bobAt = W.rootOf(cy).Position, W.rootOf(bob).Position
check("8.3: … nobody trapped: Cy (where stand 19 stands now) moved to the receiving zone; Bob in the aisle stays", cyAt.X > zone.x0 and cyAt.X < zone.x1 and cyAt.Z > zone.z0 and cyAt.Z < zone.z1
	and math.abs(bobAt.Z - (plot2.door.z - 40)) < 1e-6 and math.abs(bobAt.X - plot2.door.x) < 1e-6, `{cyAt} {bobAt}`)
W.changed(ana)
check("8.3: a change that leaves the level as it was builds nothing new", Warehouse.model(2) == grown and Warehouse.shown(2, 2) == tvAfter)
check("8.3: the free plot and the others untouched", Warehouse.level(1) == 1 and Warehouse.level(3) == 1)

-- shrinking (the admin's 🏗 LEVEL 2): the Workshop, 4 stands; a piece past them not shown (the real collection sends it
-- back to the stock: Collection.upgrade's fitStands)
W.levels[ana] = 2
W.changed(ana)
local small = Warehouse.model(2)
check("8.3: shrunk to the Workshop (the admin's): Level 2, 4 stands, the TV on stand 2, nothing on 13", small ~= grown and grown.destroyed == true and Warehouse.level(2) == 2
	and standsBuilt(2) == 4 and Warehouse.shown(2, 2) ~= nil and Warehouse.shown(2, 13) == nil and partsOfLevel(2) and line(small:FindFirstChild("StockBoard"), 3) == "1 of 4 stands on show")

-- Ana leaves: her pieces go, the plot FOR RENT at the start's level, no prompts; Bob claims it at his level: fresh prompts
W.give(ana, { uid = "u4", item = "wardrobe", variant = 1, condition = 1, name = "Wardrobe", stand = 3, got = 0 })
local wardrobe = Warehouse.shown(2, 3)
local oldDisplay = promptsOf(2, 2).display
W.free(2)
local rented = Warehouse.model(2)
check("the owner leaves: the pieces on show go", wardrobe ~= nil and wardrobe.destroyed == true and Warehouse.shown(2, 3) == nil and Warehouse.shown(2, 2) == nil)
check("…FOR RENT, the prompts gone; 8.3: back to the start's Garage", line(rented:FindFirstChild("OwnerSign"), 1) == "FOR RENT" and #stand(2, 2):FindFirstChild("Prompts"):GetChildren() == 0
	and oldDisplay.destroyed == true and Warehouse.level(2) == 1 and small.destroyed == true)
W.changed(ana)
check("…a change to her collection after she left builds nothing", Warehouse.shown(2, 3) == nil and Warehouse.model(2) == rented)
W.levels[bob] = 3
W.claim(2, bob)
local fresh = promptsOf(2, 2)
check("a new owner: Bob's Warehouse at his level (8.3: the Warehouse, 3: 8 stands), fresh prompts with his UserId", line(Warehouse.model(2):FindFirstChild("OwnerSign"), 1) == "Bob's Warehouse"
	and Warehouse.level(2) == 3 and standsBuilt(2) == 8 and fresh.display ~= oldDisplay and fresh.display:GetAttribute("CargoOwner") == 202 and fresh.display.Enabled == true)
local bobDesk = Warehouse.terminal(2):FindFirstChild("Prompts"):FindFirstChild("Upgrades")
check("8.1: … and a fresh UPGRADES prompt for him", bobDesk ~= nil and bobDesk:GetAttribute("CargoOwner") == 202)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
