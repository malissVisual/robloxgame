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
-- Run with tests/run_tests.py.
local W = require("./WarehouseRuntime")
local Warehouse = require("./WarehouseServer")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local WarehouseLayout = require("./WarehouseLayout")

local M = W.Mock
local T = Config.Warehouse
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
W.claim(2, ana)
Warehouse.start()

local folder = M.workspace:FindFirstChild("Warehouses")
check("four warehouses under workspace.Warehouses", folder ~= nil and #folder:GetChildren() == #SandboxMap.Plots, folder and #folder:GetChildren())
local budgetOk, anchoredOk, most = true, true, 0
for _, plot in SandboxMap.Plots do
	local count, anchored = parts(Warehouse.model(plot.id), true)
	most = math.max(most, count)
	budgetOk = budgetOk and count <= T.MaxParts and count == #WarehouseLayout.pieces(plot)
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
for i = 1, T.Stands do
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
check("the STOCK board: 📦 1 piece in stock · $6/min, 1 of 12 on show", line(board, 2) == "📦 1 piece in stock · $6/min" and line(board, 3) == `1 of {T.Stands} stands on show`, line(board, 2))

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
check("…the board: 2 pieces in stock, 0 on show", line(board, 2) == "📦 2 pieces in stock · $58/min" and line(board, 3) == `0 of {T.Stands} stands on show`, line(board, 2))

-- a stand number past the warehouse's: never shown
W.give(ana, { uid = "u9", item = "box", variant = 1, condition = 1, name = "Box", stand = T.Stands + 1, got = 0 })
local stray = false
for i = 1, T.Stands do
	stray = stray or Warehouse.shown(2, i) ~= nil
end
check("an entry on a stand the warehouse lacks is not shown", not stray)

-- Ana leaves: her pieces go, FOR RENT, no prompts; Bob claims it: fresh prompts for him
W.give(ana, { uid = "u4", item = "wardrobe", variant = 1, condition = 1, name = "Wardrobe", stand = 5, got = 0 })
local wardrobe = Warehouse.shown(2, 5)
local oldDisplay = promptsOf(2, 2).display
W.free(2)
check("the owner leaves: the pieces on show go", wardrobe ~= nil and wardrobe.destroyed == true and Warehouse.shown(2, 5) == nil)
check("…FOR RENT, the prompts gone", line(sign2, 1) == "FOR RENT" and #stand(2, 2):FindFirstChild("Prompts"):GetChildren() == 0 and oldDisplay.destroyed == true)
W.changed(ana)
check("…a change to her collection after she left builds nothing", Warehouse.shown(2, 5) == nil)
W.claim(2, bob)
local fresh = promptsOf(2, 2)
check("a new owner: Bob's Warehouse, fresh prompts with his UserId", line(sign2, 1) == "Bob's Warehouse" and fresh.display ~= oldDisplay and fresh.display:GetAttribute("CargoOwner") == 202 and fresh.display.Enabled == true)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
