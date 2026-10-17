-- 8.0 SANDBOX, the warehouse: the real server/Warehouse.luau (WarehouseServer.luau, built by tests/run_tests.py) on the
-- recorder with a fake SandboxPlots, a fake Collection and a fake Upgrades (tests/runtime/WarehouseRuntime.luau), and
-- the real server/WarehouseMesh.luau with a stand-in of the owner's Blender import (Runtime.fakeArt: every level):
--   * every plot's warehouse is built, within Config.Warehouse.MaxParts, everything anchored; FOR RENT on a free plot,
--     "<Name>'s Warehouse" on an owned one (an owner from before the start too)
--   * the stands' prompts are the owner's only: none on a free plot; tagged for client/CargoPrompts.luau with the
--     owner's UserId; a stranger's use does nothing but a notice; the owner's "Display" opens the picker
--   * a piece on show builds its model on its stand (anchored, in the podium's middle, on its top, looking south), its
--     tag (name, rarity, +$X/min) and swaps the stand's prompts to Take down / Sell; the STOCK board counts
--   * Take down and Sell go through the Collection and take the model away; two pieces share the income by worth
--   * the owner leaves: the pieces go, the sign is FOR RENT, the prompts go; a new owner gets fresh prompts
--   * 8.1, the upgrades (on Ana's Big Warehouse, level 4: the warehouse of 8.0 – 8.2): it has all 20 stands; the
--     owner's first Collection.stands stand there, the rest are only their painted spot (podium, top and plate hidden,
--     not solid, no Display); More stands bought opens 13 and 14 (a corner stand's piece and prompts look north), the
--     board counts them, losing them hides them again; the tags are × Collection.boost; the UPGRADES desk's prompt is
--     the owner's (Upgrades.open), a stranger's use a notice, a free plot none, a new owner a fresh one
--   * 8.3, the warehouse's levels: a free plot is the garage FOR RENT (Config.Warehouse.FreeLevel); a plot is built at
--     its owner's level (Upgrades.levels: before the start, at a claim, when their save loads), the Model's attribute
--     Level and workspace.Warehouses' Level<id> say which; a new owner (level 1) has the garage's 2 stands; buying the
--     ZDC Warehouse up to level 5 rebuilds the plot each time (a new Model, the old one gone with its pieces and
--     prompts): the level's stands (all of them open), the pieces back on their stands at the level's spots, the
--     prompts (the stands' and the desk's, on their fronts) the owner's and working, the board, the sign, the API
--     (model, shown, terminal, isOpen, level) the new building's, the parts its layout's; another upgrade (or the same
--     level again) rebuilds nothing; More stands at level 5 opens its 8 small stands; the admin's RESET back to the
--     garage keeps the pieces on stands 1 and 2; the owner leaving takes it back to the garage FOR RENT; somebody's
--     levels without a plot change nothing. WarehouseMesh dresses every build in its own level (WarehouseMesh.level:
--     the Model's Level; Config's ArtLevel only for a model without one)
-- Run with tests/run_tests.py.
local W = require("./WarehouseRuntime")
local Warehouse = require("./WarehouseServer")
local WarehouseMesh = require("./WarehouseMesh")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local WarehouseLayout = require("./WarehouseLayout")

local M = W.Mock
local T = Config.Warehouse
local FREE = T.FreeLevel
local BIG = WarehouseLayout.count(4) -- the Big Warehouse's big stands (the 12 of 8.0 – 8.2)
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

-- The layout's parts of a warehouse (not the pieces on show when skipShown; never the Blender model's clones under
-- WarehouseMesh: they are the import's, not the layout's) and whether they are all anchored.
local function parts(model: any, skipShown: boolean): (number, boolean)
	local count, anchored = 0, true
	local shownFolder, art = model:FindFirstChild("Shown"), model:FindFirstChild("WarehouseMesh")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not (skipShown and shownFolder and d:IsDescendantOf(shownFolder)) and not (art and d:IsDescendantOf(art)) then
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
-- 8.3: plot `id` at the level its warehouse is built at now (the Model's attribute Level)
local function siteOf(id: number): any
	return WarehouseLayout.site(SandboxMap.Plots[id], Warehouse.model(id):GetAttribute("Level"))
end
-- 8.3: an attachment's place in the world (its part's frame × its offset)
local function worldOf(anchor: any): any
	return anchor.Parent.CFrame * anchor.CFrame.Position
end
-- 8.3: every stand's prompts on its podium's front (the side its piece looks to) and the desk's on the desk's front
-- (WarehouseLayout.terminal's yaw), inside the hall's walls → ok, the first that is not
local function frontsOk(id: number): (boolean, string)
	local site = siteOf(id)
	local hall = WarehouseLayout.inside(site)
	local function ahead(part: any, at: any, yaw: number): boolean
		local lx, lz = -math.sin(math.rad(yaw)), -math.cos(math.rad(yaw))
		return (at.X - part.Position.X) * lx + (at.Z - part.Position.Z) * lz > 0
			and at.X > hall.x0 and at.X < hall.x1 and at.Z > hall.z0 and at.Z < hall.z1
	end
	for i = 1, WarehouseLayout.capacity(site.level) do
		local podium = stand(id, i)
		local spot = WarehouseLayout.stand(site, i) :: WarehouseLayout.Stand
		if not ahead(podium, worldOf(podium:FindFirstChild("Prompts")), spot.yaw) then
			return false, `stand {i}`
		end
	end
	local desk = Warehouse.terminal(id) :: any
	if not ahead(desk, worldOf(desk:FindFirstChild("Prompts")), WarehouseLayout.terminal(site).yaw) then
		return false, "the desk"
	end
	return true, ""
end
-- 8.3: the Model dressed by WarehouseMesh in its own level (MeshArt, WarehouseLevel, only that level's clones) with
-- the layout's visual parts hidden under it and its stands seen
local function dressedOk(id: number): boolean
	local model = Warehouse.model(id)
	local level = model:GetAttribute("Level")
	local art = model:FindFirstChild("WarehouseMesh")
	if not (model:GetAttribute("MeshArt") == true and model:GetAttribute("WarehouseLevel") == level and art ~= nil and WarehouseMesh.level(model) == level) then
		return false
	end
	local own, other = 0, 0
	for _, d in art:GetChildren() do
		if string.find(d.Name, `^lvl{level}_`) then
			own += 1
		else
			other += 1
		end
	end
	local hidden, visual = true, 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute(WarehouseMesh.Attribute) == true then
			visual += 1
			hidden = hidden and d.Transparency == 1
		end
	end
	return own == 2 and other == 0 and visual > 0 and hidden and stand(id, 1).Transparency == 0
end

-- 8.3: the owner's Blender import is there (every warehouse wears its own level of it)
W.fakeArt()

-- Ana owns plot 2 before the warehouses are built, with the Big Warehouse (level 4: the 8.0 and 8.1 checks below are
-- about her stands, as before 8.3); plot 1 stays free.
local ana = W.player(101, "Ana", M.Vector3.new(-65, 3, -150))
local bob = W.player(202, "Bob", M.Vector3.new(-65, 3, -152))
W.levels[ana] = { warehouse = 3 }
W.claim(2, ana)
Warehouse.start()

local folder = M.workspace:FindFirstChild("Warehouses")
check("four warehouses under workspace.Warehouses", folder ~= nil and #folder:GetChildren() == #SandboxMap.Plots, folder and #folder:GetChildren())
local budgetOk, anchoredOk, most = true, true, 0
for _, plot in SandboxMap.Plots do
	local count, anchored = parts(Warehouse.model(plot.id), true)
	most = math.max(most, count)
	budgetOk = budgetOk and count <= T.MaxParts and count == #WarehouseLayout.pieces(siteOf(plot.id))
	anchoredOk = anchoredOk and anchored
end
print(`  {most} parts a warehouse (the budget {T.MaxParts})`)
check("every warehouse is its level's layout's pieces, within the part budget, all anchored", budgetOk and anchoredOk, most)
check("8.3: a free plot is the garage (Level FreeLevel on its Model and workspace.Warehouses' Level1); Ana's, bought before the start, the Big Warehouse (level 4)",
	FREE == 1 and Warehouse.model(1):GetAttribute("Level") == FREE and folder:GetAttribute("Level1") == FREE and Warehouse.level(1) == FREE
		and Warehouse.model(2):GetAttribute("Level") == 4 and folder:GetAttribute("Level2") == 4 and Warehouse.level(2) == 4
		and folder:GetAttribute("Level3") == FREE and folder:GetAttribute("Level4") == FREE)
check("8.3: WarehouseMesh dresses each in its own level (the garage in level 1, Ana's in level 4), the layout's visual parts hidden", dressedOk(1) and dressedOk(2) and dressedOk(3))

local sign1 = Warehouse.model(1):FindFirstChild("OwnerSign")
local sign2 = Warehouse.model(2):FindFirstChild("OwnerSign")
check("a free plot's sign: FOR RENT", line(sign1, 1) == "FOR RENT", line(sign1, 1))
check("an owner from before the start: Ana's Warehouse", line(sign2, 1) == "Ana's Warehouse" and line(sign2, 2) == "DELIVEROS STORAGE · PLOT 2", line(sign2, 1))

-- the prompts: the owner's only
local free = stand(1, 1):FindFirstChild("Prompts")
check("a free plot's stands have no prompts", free ~= nil and #free:GetChildren() == 0)
local allOk = true
for i = 1, BIG do
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
local spot = WarehouseLayout.stand(SandboxMap.Plots[2], 3) :: WarehouseLayout.Stand
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
check("the STOCK board: 📦 1 piece in stock · $6/min, 1 of 12 on show", line(board, 2) == "📦 1 piece in stock · $6/min" and line(board, 3) == `1 of {BIG} stands on show`, line(board, 2))

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
check("…the board: 2 pieces in stock, 0 on show", line(board, 2) == "📦 2 pieces in stock · $58/min" and line(board, 3) == `0 of {BIG} stands on show`, line(board, 2))

-- a stand number past the warehouse's: never shown
W.give(ana, { uid = "u9", item = "box", variant = 1, condition = 1, name = "Box", stand = BIG + 1, got = 0 })
local stray = false
for i = 1, BIG do
	stray = stray or Warehouse.shown(2, i) ~= nil
end
check("an entry on a stand the warehouse lacks is not shown", not stray)

-- ── 8.1: the upgrade stands and the UPGRADES desk (Ana's Big Warehouse) ────────
local ALL = WarehouseLayout.capacity(4)
local function partsOf(id: number, i: number): (any, any, any)
	local model = Warehouse.model(id)
	return model:FindFirstChild(`Stand{i}`), model:FindFirstChild(`StandTop{i}`), model:FindFirstChild(`Plate{i}`)
end
local function hidden(id: number, i: number): boolean
	local podium, top, plate = partsOf(id, i)
	return podium.Transparency == 1 and podium.CanCollide == false and podium.CanQuery == false and top.Transparency == 1 and top.CanCollide == false
		and plate.Transparency == 1 and plate:FindFirstChild("WordsFront").Enabled == false and not Warehouse.isOpen(id, i)
end
local function standing(id: number, i: number): boolean
	local podium, top, plate = partsOf(id, i)
	return podium.Transparency == 0 and podium.CanCollide == true and podium.CanQuery == true and top.CanCollide == true
		and plate.Transparency == 0 and plate:FindFirstChild("WordsFront").Enabled ~= false and Warehouse.isOpen(id, i)
end
local freeOk, anaOk = true, true
for i = 1, WarehouseLayout.capacity(FREE) do
	freeOk = freeOk and (if i <= WarehouseLayout.count(FREE) then standing(1, i) else hidden(1, i))
end
for i = 1, ALL do
	anaOk = anaOk and (if i <= BIG then standing(2, i) else hidden(2, i) and promptsOf(2, i).display.Enabled == false)
end
check(`8.1: the Big Warehouse has all {ALL} stands, the upgrade stands only their painted spot (hidden, not solid); 8.3: a free plot the garage's {WarehouseLayout.capacity(FREE)}, standing, none past them`,
	ALL == 20 and freeOk and Warehouse.model(2):FindFirstChild("SpotText13") ~= nil and partsOf(1, WarehouseLayout.capacity(FREE) + 1) == nil and not Warehouse.isOpen(1, WarehouseLayout.capacity(FREE) + 1))
check("8.1: the owner with the level's 12 stands: 13 – 20 hidden, no Display on them; the piece on stand 13 not shown", anaOk and Warehouse.shown(2, 13) == nil)
W.upgrade(ana, { warehouse = 3, stands = 1 }) -- (More stands bought: Upgrades' listeners, then the collection's change)
W.changed(ana)
check("8.1: More stands bought (Collection.stands 14): stands 13 and 14 stand there, 15 still only its spot; 8.3: the same level, no rebuild", standing(2, 13) and standing(2, 14) and hidden(2, 15)
	and Warehouse.model(2):FindFirstChild("StockBoard") == board)
local corner = Warehouse.shown(2, 13)
local cornerRoot = corner and corner.PrimaryPart
check("8.1: … the piece on stand 13 shows now, looking north (a corner stand looks at the front row's aisle)", cornerRoot ~= nil and math.abs(cornerRoot.CFrame.LookVector.Z + 1) < 1e-6)
check("8.1: … its prompts at its north edge: Take down and Sell on; stand 14's Display on", stand(2, 13):FindFirstChild("Prompts").CFrame.Position.Z < 0 and promptsOf(2, 13).takeDown.Enabled == true
	and promptsOf(2, 14).display.Enabled == true and promptsOf(2, 15).display.Enabled == false, `{stand(2, 13):FindFirstChild("Prompts").CFrame.Position.Z} {promptsOf(2, 13).takeDown.Enabled} {promptsOf(2, 14).display.Enabled} {promptsOf(2, 15).display.Enabled}`)
check("8.1: … the board counts 14 stands", line(board, 3) == `1 of {BIG + 2} stands on show`, line(board, 3))
W.boosts[ana] = 1.61 -- (the lights at their top: 8.3 economy, a box's $/min is small, ×1.21 rounds the same)
W.changed(ana)
local _, _, lit = tagText(2, 13)
local boxEntry = { item = "box", condition = 1 }
check("8.1: the Showroom lights (Collection.boost 1.61): the tag's $/min × 1.61", lit == WarehouseLayout.tagLines("Box", CollectionRules.rarityOf(CollectionRules.defOf("box")), CollectionRules.income(boxEntry, 1.61))[2].text and lit ~= tagOf(boxEntry), lit)
W.boosts[ana] = nil

-- the UPGRADES desk: the owner's prompt
local desk2, desk1 = Warehouse.terminal(2), Warehouse.terminal(1)
local deskPrompt = desk2 and desk2:FindFirstChild("Prompts") and desk2:FindFirstChild("Prompts"):FindFirstChild("Upgrades")
check("8.1: the UPGRADES desk: the owner's \"Upgrades\" prompt (E), tagged as Ana's for CargoPrompts; a free plot's desk has none", deskPrompt ~= nil and deskPrompt.ActionText == "Upgrades"
	and deskPrompt.KeyboardKeyCode == "E" and deskPrompt:GetAttribute("CargoOwner") == 101 and deskPrompt:GetAttribute("Tag_" .. Config.Cargo.PromptTag) == true
	and desk1 ~= nil and #desk1:FindFirstChild("Prompts"):GetChildren() == 0 and desk2.Name == "TerminalDesk")
local fronts, which = frontsOk(2)
local frontsFree, whichFree = frontsOk(1)
check("8.3: every stand's prompts on its podium's front, the desk's on the desk's front (into the hall), on the garage too", fronts and frontsFree, which .. whichFree)
W.later()
deskPrompt.Triggered:Fire(bob)
check("8.1: … a stranger's use: no window, a notice", W.lastCall("openUpgrades") == nil and W.lastNotice(bob) == "This is Ana's warehouse.", W.lastNotice(bob))
W.later()
deskPrompt.Triggered:Fire(ana)
local opened = W.lastCall("openUpgrades")
check("8.1: … the owner's: Upgrades.open (the window)", opened ~= nil and opened[2] == ana)
W.upgrade(ana, { warehouse = 3 })
W.changed(ana)
check("8.1: More stands gone again (back to the level's 12): 13 and 14 only their spot, nothing shown on them", hidden(2, 13) and hidden(2, 14) and Warehouse.shown(2, 13) == nil and corner ~= nil and corner.destroyed == true)

-- Ana leaves: her pieces go, FOR RENT, no prompts; Bob claims it: fresh prompts for him
W.give(ana, { uid = "u4", item = "wardrobe", variant = 1, condition = 1, name = "Wardrobe", stand = 5, got = 0 })
local wardrobe = Warehouse.shown(2, 5)
local oldDisplay = promptsOf(2, 2).display
local anaModel = Warehouse.model(2)
W.free(2)
sign2 = Warehouse.model(2):FindFirstChild("OwnerSign")
check("the owner leaves: the pieces on show go", wardrobe ~= nil and wardrobe.destroyed == true and Warehouse.shown(2, 5) == nil)
check("…FOR RENT, the prompts gone", line(sign2, 1) == "FOR RENT" and #stand(2, 2):FindFirstChild("Prompts"):GetChildren() == 0 and oldDisplay.destroyed == true)
check("8.3: …the plot is the garage again (a new Model at FreeLevel, workspace.Warehouses' Level2 too; her Big Warehouse's gone)", Warehouse.model(2) ~= anaModel and anaModel.destroyed == true
	and Warehouse.model(2):GetAttribute("Level") == FREE and folder:GetAttribute("Level2") == FREE and Warehouse.model(2).Parent == folder and dressedOk(2)
	and #WarehouseLayout.pieces(siteOf(2)) == (parts(Warehouse.model(2), true)))
W.changed(ana)
check("…a change to her collection after she left builds nothing", Warehouse.shown(2, 5) == nil)
local garage = Warehouse.model(2)
W.claim(2, bob)
local fresh = promptsOf(2, 2)
check("a new owner: Bob's Warehouse, fresh prompts with his UserId", line(sign2, 1) == "Bob's Warehouse" and fresh.display ~= oldDisplay and fresh.display:GetAttribute("CargoOwner") == 202 and fresh.display.Enabled == true)
local bobDesk = Warehouse.terminal(2):FindFirstChild("Prompts"):FindFirstChild("Upgrades")
check("8.1: … and a fresh UPGRADES prompt for him (Ana's gone)", bobDesk ~= nil and bobDesk ~= deskPrompt and deskPrompt.destroyed == true and bobDesk:GetAttribute("CargoOwner") == 202)

-- ── 8.3: the warehouse's levels ───────────────────────────────────────────────
check("8.3: Bob, a new player (level 1): the garage he claimed is his as it stood (no rebuild), its 2 stands his (Display on both), no third",
	Warehouse.model(2) == garage and Warehouse.level(2) == 1 and promptsOf(2, 1).display.Enabled == true and promptsOf(2, 2).display.Enabled == true
		and Warehouse.isOpen(2, 1) and Warehouse.isOpen(2, 2) and stand(2, 3) == nil and not Warehouse.isOpen(2, 3))
-- Cara (the Storehouse in her save) claims plot 4: built at her level at once
local cara = W.player(303, "Cara", M.Vector3.new(60, 3, -150))
W.levels[cara] = { warehouse = 2 }
local free4 = Warehouse.model(4)
W.claim(4, cara)
check("8.3: an owner with a higher level claims a plot: rebuilt at her level at once (the Storehouse, 8 stands, her sign, her prompts)", Warehouse.model(4) ~= free4 and free4.destroyed == true
	and Warehouse.level(4) == 3 and folder:GetAttribute("Level4") == 3 and Warehouse.isOpen(4, 8) and stand(4, 9) == nil
	and line(Warehouse.model(4):FindFirstChild("OwnerSign"), 1) == "Cara's Warehouse" and promptsOf(4, 8).display:GetAttribute("CargoOwner") == 303 and dressedOk(4))
-- Dan claims plot 3 before his save loads (level 1 then); it loads: the Big Warehouse (a save from before 8.3)
local dan = W.player(404, "Dan", M.Vector3.new(20, 3, -150))
local free3 = Warehouse.model(3)
W.claim(3, dan)
local danGarage = Warehouse.model(3)
W.upgrade(dan, { warehouse = 3 }) -- (Upgrades tells its listeners when a save has loaded)
check("8.3: a plot claimed before its owner's save loads: the garage, then (Upgrades.onChanged on the load) his Big Warehouse", danGarage == free3 and Warehouse.model(3) ~= danGarage
	and danGarage.destroyed == true and Warehouse.level(3) == 4 and Warehouse.isOpen(3, 12) and promptsOf(3, 12).display:GetAttribute("CargoOwner") == 404)

-- Bob's pieces: a sofa on stand 1, a TV on stand 2, a box in his stock
W.income[bob] = 10
W.give(bob, { uid = "b1", item = "sofa", variant = 1, condition = 1, name = "Sofa", stand = 1, got = 0 })
W.give(bob, { uid = "b2", item = "tv", variant = 1, condition = 1, name = "Old TV", stand = 2, got = 0 })
W.give(bob, { uid = "b3", item = "box", variant = 1, condition = 1, name = "Box", got = 0 })
check("8.3: (Bob's sofa and TV on the garage's stands 1 and 2)", Warehouse.shown(2, 1) ~= nil and Warehouse.shown(2, 2) ~= nil)
-- the pieces on show at their stand's spot of the level built now
local function onSpots(id: number, uids: { [number]: string }): boolean
	local site = siteOf(id)
	for index, uid in uids do
		local model = Warehouse.shown(id, index)
		local where = WarehouseLayout.stand(site, index) :: WarehouseLayout.Stand
		local base = model and model.PrimaryPart
		if not (model and base and model:GetAttribute("Uid") == uid and math.abs(base.Position.X - where.x) < 1e-6 and math.abs(base.Position.Z - where.z) < 1e-6) then
			return false
		end
	end
	return true
end
check("8.3: … each at its stand's spot in the garage", onSpots(2, { "b1", "b2" }))

-- Bob buys the ZDC Warehouse level by level up to the Logistics Center (5)
for k = 1, 4 do
	local level = k + 1
	local before, sofaBefore = Warehouse.model(2), Warehouse.shown(2, 1)
	local deskBefore = Warehouse.terminal(2):FindFirstChild("Prompts"):FindFirstChild("Upgrades")
	W.upgrade(bob, { warehouse = k })
	local model = Warehouse.model(2)
	local name = WarehouseLayout.level(level).name
	check(`8.3: level {level} ({name}) bought: the plot rebuilt (a new Model, the old one gone with its pieces), Level {level} on it and on workspace.Warehouses`,
		model ~= before and before.destroyed == true and sofaBefore.destroyed == true and model.Parent == folder and model:GetAttribute("Level") == level
			and folder:GetAttribute("Level2") == level and Warehouse.level(2) == level and model:GetAttribute("Plot") == 2)
	local count, anchored = parts(model, true)
	local open = true
	for i = 1, WarehouseLayout.capacity(level) do
		open = open and Warehouse.isOpen(2, i) == (i <= WarehouseLayout.count(level)) and stand(2, i) ~= nil
	end
	check(`8.3: … its layout's {count} parts (the budget {T.MaxParts}), anchored; its {WarehouseLayout.count(level)} big stands open, its small spots only painted, none past {WarehouseLayout.capacity(level)}`,
		count == #WarehouseLayout.pieces(siteOf(2)) and count <= T.MaxParts and anchored and open and stand(2, WarehouseLayout.capacity(level) + 1) == nil)
	check(`8.3: … the sofa and the TV still on stands 1 and 2, at the level's spots, their tags on; the board and the sign the new building's`, onSpots(2, { "b1", "b2" })
		and (tagText(2, 1)) and line(model:FindFirstChild("StockBoard"), 3) == `2 of {WarehouseLayout.count(level)} stands on show`
		and line(model:FindFirstChild("StockBoard"), 2) == "📦 1 piece in stock · $10/min" and line(model:FindFirstChild("OwnerSign"), 1) == "Bob's Warehouse")
	local last = WarehouseLayout.count(level)
	local p = promptsOf(2, last)
	W.later()
	p.display.Triggered:Fire(bob)
	local picked = W.lastCall("openPicker")
	local frontOk, frontWhy = frontsOk(2)
	check(`8.3: … fresh prompts, his: stand {last}'s Display opens his picker for it (the handlers hold the plot as it is now); 1's Take down / Sell on; all on their fronts`,
		p.display.Enabled == true and p.display:GetAttribute("CargoOwner") == 202 and picked ~= nil and picked[2] == bob and picked[3] == last
			and promptsOf(2, 1).takeDown.Enabled == true and promptsOf(2, 1).sell.Enabled == true and frontOk, frontWhy)
	local deskNow = Warehouse.terminal(2)
	local upgradesPrompt = deskNow:FindFirstChild("Prompts"):FindFirstChild("Upgrades")
	W.later()
	upgradesPrompt.Triggered:Fire(bob)
	local window = W.lastCall("openUpgrades")
	check("8.3: … the desk's (Warehouse.terminal: the new desk) prompt his, the old one gone; it opens his window", deskNow:IsDescendantOf(model) and upgradesPrompt ~= deskBefore
		and deskBefore.destroyed == true and upgradesPrompt:GetAttribute("CargoOwner") == 202 and window ~= nil and window[2] == bob)
	check(`8.3: … WarehouseMesh dresses the new Model in level {level} (WarehouseMesh.level: its Level; the plot id: workspace.Warehouses')`, dressedOk(2) and WarehouseMesh.level(2) == level)
end
local center = Warehouse.model(2)
W.upgrade(bob, { warehouse = 4, lights = 2 })
W.upgrade(bob, { warehouse = 4, lights = 2 })
check("8.3: another upgrade (and the same levels again): nothing rebuilt", Warehouse.model(2) == center and center.destroyed ~= true)
W.upgrade(bob, { warehouse = 4, lights = 2, stands = 4 })
W.changed(bob)
local allOpen = true
for i = 1, WarehouseLayout.capacity(5) do
	allOpen = allOpen and Warehouse.isOpen(2, i)
end
W.give(bob, { uid = "b4", item = "box", variant = 1, condition = 1, name = "Box", stand = 25, got = 0 })
check("8.3: More stands at its top in the Logistics Center: all 32 stand there (its 8 small ones too), no rebuild; a piece on small stand 25 shows",
	allOpen and WarehouseLayout.capacity(5) == 32 and Warehouse.model(2) == center and Warehouse.shown(2, 25) ~= nil and promptsOf(2, 26).display.Enabled == true)
local sofaAt5 = Warehouse.shown(2, 1)
W.upgrade(bob, {}) -- (the admin's RESET: back to the garage; the collection sends what stood on 3 … 32 to the stock)
W.changed(bob)
check("8.3: the admin's RESET: the garage again (rebuilt), the sofa and the TV still on stands 1 and 2, nothing on a stand it lacks",
	Warehouse.model(2) ~= center and center.destroyed == true and sofaAt5.destroyed == true and Warehouse.level(2) == 1 and onSpots(2, { "b1", "b2" })
		and Warehouse.shown(2, 25) == nil and stand(2, 3) == nil and line(Warehouse.model(2):FindFirstChild("StockBoard"), 3) == "2 of 2 stands on show")
W.upgrade(bob, { warehouse = 4 })
local leaving = Warehouse.model(2)
W.free(2)
check("8.3: Bob leaves the Logistics Center: the plot is the garage FOR RENT (rebuilt), nothing on show, no prompts", Warehouse.model(2) ~= leaving and leaving.destroyed == true
	and Warehouse.level(2) == FREE and line(Warehouse.model(2):FindFirstChild("OwnerSign"), 1) == "FOR RENT" and Warehouse.shown(2, 1) == nil
	and #stand(2, 1):FindFirstChild("Prompts"):GetChildren() == 0 and #Warehouse.terminal(2):FindFirstChild("Prompts"):GetChildren() == 0)
local models = { Warehouse.model(1), Warehouse.model(2), Warehouse.model(3), Warehouse.model(4) }
W.upgrade(ana, { warehouse = 4 })
W.upgrade(bob, { warehouse = 2 })
check("8.3: somebody's levels when they have no plot (Ana and Bob left): no warehouse changes", Warehouse.model(1) == models[1] and Warehouse.model(2) == models[2]
	and Warehouse.model(3) == models[3] and Warehouse.model(4) == models[4])
local bare = M.Instance.new("Model")
check("8.3: WarehouseMesh.level without a Level (a model from before 8.3): Config's ArtLevel", WarehouseMesh.level(bare) == T.ArtLevel and WarehouseMesh.level(nil) == T.ArtLevel)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
