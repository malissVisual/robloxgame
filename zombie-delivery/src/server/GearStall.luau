--!strict
-- 6.12.2, the gear stall at the spawn (the owner: "next to it [the jobs] make a stall for the bags and that stuff (the
-- gear) ... the shops feel unnecessarily big, so right here next to each other at the spawn give me the gear stall"):
-- one open-air market stall on the west side of the depot's yard, next to the JOBS spot (server/JobsSpot.luau), under
-- one striped awning, facing the yard (+X). Two counters side by side, each with its shop prompt (World's ShopPrompts:
-- "Shop" → the OpenShop remote, client/Hud.luau's shop window as before) and its clerk behind it
-- (server/ShopClerks.luau: Nell, Dot):
--   BAGS  ZDC Bags (Map.Shops.bags, shop id "bags"): the five bags on a pegboard behind it (6.6's kiosk, now here)
--   GEAR  Last Stop Supplies (Map.Shops.supplies, shop id "supplies": the vests and the items; its old building on
--         block (0, -1) is no shop any more): the three vests on a rail behind it, a shelf of energy drinks and medkits
-- a partition between the two, the name board LAST STOP SUPPLIES · ZDC BAGS on the roof, each counter's own board
-- (BAGS, GEAR) under the awning, two lamps that light up at night. Where it stands: Config.GearStall (from the depot's
-- middle, Map.Depot; clear of the spawn pad, the scooter rack, the JOBS spot, the garage terminal and Marge).
-- 6.12.6 (the owner: "that shop has nothing, put those props on my stalls"): a giant prop over each counter on the roof,
-- just behind the name board, both turning slowly on the clients (server/ShopProps.luau, ShopArt "gearvest" and
-- "zdcbag"): over GEAR the hi-vis courier vest that stood on Last Stop's old roof, over BAGS a red ZDC delivery bag.
--
-- server/World.luau's buildDepot calls GearStall.build with its own helpers (no new top-level locals there: the -O0
-- register limit), as it did for 6.6's BagKiosk.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)

local GearStall = {}

export type Tools = {
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	deco: (p: Part) -> Part,
	sign: (parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3, background: Color3?, art: string?, artHeight: number?) -> (),
	prompt: (parent: BasePart, shop: string, action: string, object: string) -> (),
	nightLight: (item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?) -> (),
}

local RED = Color3.fromRGB(190, 44, 38)
local OLIVE = Color3.fromRGB(77, 86, 66) -- Last Stop's colour (its old awning)
local CREAM = Color3.fromRGB(236, 230, 214)
local CHARCOAL = Color3.fromRGB(38, 43, 47)
local WOOD = Color3.fromRGB(128, 94, 62)

-- The bags on the BAGS pegboard, left to right as you face the counter: their look in a few blocks of colour.
local BAGS: { { id: string, size: Vector3, color: Color3, material: Enum.Material } } = {
	{ id = "bag", size = Vector3.new(1.2, 1.5, 0.3), color = Color3.fromRGB(235, 235, 228), material = Enum.Material.SmoothPlastic },
	{ id = "tote", size = Vector3.new(1.5, 1.7, 0.35), color = Color3.fromRGB(214, 196, 158), material = Enum.Material.Fabric },
	{ id = "thermal", size = Vector3.new(1.7, 1.5, 1.1), color = Color3.fromRGB(178, 40, 34), material = Enum.Material.Fabric },
	{ id = "padded", size = Vector3.new(1.7, 1.3, 0.5), color = Color3.fromRGB(110, 114, 120), material = Enum.Material.Fabric },
	{ id = "duffel", size = Vector3.new(2.4, 1.1, 1.1), color = Color3.fromRGB(58, 84, 56), material = Enum.Material.Fabric },
}

-- The vests on the GEAR rail, left to right: the Courier Vest (red, reflective bands), the Kevlar Vest, the Heavy Armour.
local VESTS: { { id: string, size: Vector3, color: Color3, band: Color3? } } = {
	{ id = "hivis", size = Vector3.new(2, 2.4, 0.5), color = Color3.fromRGB(206, 58, 42), band = Color3.fromRGB(214, 216, 210) },
	{ id = "kevlar", size = Vector3.new(2, 2.4, 0.6), color = Color3.fromRGB(44, 52, 64) },
	{ id = "heavy", size = Vector3.new(2.3, 2.6, 0.8), color = Color3.fromRGB(72, 76, 66), band = Color3.fromRGB(52, 55, 50) },
}

-- One counter: the desk with the shop's prompt, its top, its coloured front with a cream stripe and its board.
local function counter(folder: Instance, tools: Tools, frame: CFrame, x: number, width: number, shop: string, name: string, title: string, front: Color3, ink: Color3)
	local part, deco = tools.part, tools.deco
	local desk = part(folder, "Counter", Vector3.new(width, 3.4, 2.2), frame * CFrame.new(x, 1.7, -2.4), WOOD, Enum.Material.WoodPlanks)
	deco(part(folder, "CounterTop", Vector3.new(width + 0.4, 0.2, 2.6), frame * CFrame.new(x, 3.5, -2.4), CHARCOAL, Enum.Material.Metal))
	deco(part(folder, "CounterFront", Vector3.new(width - 0.2, 2.4, 0.1), frame * CFrame.new(x, 1.8, -3.55), front, Enum.Material.Metal))
	deco(part(folder, "CounterStripe", Vector3.new(width - 0.2, 0.25, 0.12), frame * CFrame.new(x, 2.6, -3.6), CREAM, Enum.Material.Metal))
	tools.prompt(desk, shop, "Shop", name)
	tools.sign(folder, title, Vector3.new(5, 1.5, 0.25), frame * CFrame.new(x, 7.7, -4.35), ink, front)
end

-- Builds the stall under `parent` (the depot's folder) at Config.GearStall, facing +X (the yard and the spawn).
function GearStall.build(parent: Instance, tools: Tools)
	local tuning = Config.GearStall
	local part, deco = tools.part, tools.deco
	local folder = Instance.new("Folder")
	folder.Name = "GearStall"
	folder.Parent = parent
	local base = Vector3.new(Map.Depot.x + tuning.X, Map.WalkTop, Map.Depot.z + tuning.Z)
	-- (local -Z is the front, toward the yard; local +X is south: GEAR there, BAGS to the north, as Map.Shops says)
	local frame = CFrame.lookAt(base, base + Vector3.new(1, 0, 0))
	local W, D, H = tuning.Width, tuning.Depth, tuning.Height
	local c = tuning.Counter
	deco(part(folder, "Floor", Vector3.new(W + 1, 0.2, D + 1), frame * CFrame.new(0, 0.1, 0), Color3.fromRGB(150, 146, 138), Enum.Material.Concrete))
	-- The two counters (the north one BAGS, the south one GEAR), the posts at the front and the partition between them.
	counter(folder, tools, frame, -c, W / 2 - 1.6, "bags", Config.BagShop.Name, "BAGS", RED, Color3.fromRGB(255, 255, 255))
	counter(folder, tools, frame, c, W / 2 - 1.6, "supplies", Map.Shops.supplies.name, "GEAR", OLIVE, Color3.fromRGB(190, 255, 160))
	for _, x in { -(W / 2 - 0.25), 0, W / 2 - 0.25 } do
		part(folder, "Post", Vector3.new(0.5, H, 0.5), frame * CFrame.new(x, H / 2, -D / 2 + 0.25), CHARCOAL, Enum.Material.Metal)
	end
	part(folder, "Partition", Vector3.new(0.3, H - 0.5, D - 2), frame * CFrame.new(0, (H - 0.5) / 2, 0.5), CREAM, Enum.Material.Metal)
	-- The back wall with a red band, the side walls and the roof.
	part(folder, "BackWall", Vector3.new(W, H, 0.6), frame * CFrame.new(0, H / 2, D / 2 - 0.3), CHARCOAL, Enum.Material.Metal)
	deco(part(folder, "BackBand", Vector3.new(W, 0.4, 0.1), frame * CFrame.new(0, H - 1, D / 2 - 0.65), RED, Enum.Material.Metal))
	for _, side in { -1, 1 } do
		part(folder, "SideWall", Vector3.new(0.3, H, D - 0.5), frame * CFrame.new(side * (W / 2 - 0.15), H / 2, 0.25), CREAM, Enum.Material.Metal)
	end
	part(folder, "Roof", Vector3.new(W + 1, 0.5, D + 1), frame * CFrame.new(0, H + 0.25, 0), CHARCOAL, Enum.Material.Metal)
	-- One striped awning over both counters.
	local stripes = 14
	local width = (W + 1) / stripes
	for n = 1, stripes do
		deco(part(folder, "Awning", Vector3.new(width, 0.2, 2.6), frame * CFrame.new(-(W + 1) / 2 + (n - 0.5) * width, H - 0.45, -D / 2 - 1.1) * CFrame.Angles(math.rad(-22), 0, 0), if n % 2 == 1 then RED else CREAM, Enum.Material.Fabric))
	end
	-- A lamp over each counter (warm at night, a light in it).
	for _, x in { -c, c } do
		local lamp = deco(part(folder, "Lamp", Vector3.new(W / 2 - 4, 0.2, 0.6), frame * CFrame.new(x, H - 0.2, -1.2), Color3.fromRGB(156, 146, 122), Enum.Material.Glass))
		local light = Instance.new("PointLight")
		light.Range = 14
		light.Brightness = 1.1
		light.Color = Color3.fromRGB(255, 226, 170)
		light.Shadows = false
		light.Parent = lamp
		tools.nightLight(lamp, Color3.fromRGB(255, 220, 150), lamp.Color, "Glass")
	end
	-- BAGS: the five bags on a pegboard behind the counter.
	local back = D / 2 - 0.6 -- the back wall's front face
	deco(part(folder, "Pegboard", Vector3.new(W / 2 - 3, 3.4, 0.1), frame * CFrame.new(-c, 5.6, back - 0.05), CREAM, Enum.Material.WoodPlanks))
	local step = (W / 2 - 5) / math.max(1, #BAGS - 1)
	for index, bag in BAGS do
		local x = -c - (W / 2 - 5) / 2 + (index - 1) * step
		deco(part(folder, "Peg", Vector3.new(0.12, 0.12, 0.4), frame * CFrame.new(x, 6.9, back - 0.3), CHARCOAL, Enum.Material.Metal))
		deco(part(folder, `Bag_{bag.id}`, bag.size, frame * CFrame.new(x, 6.8 - bag.size.Y / 2 - 0.1, back - 0.15 - bag.size.Z / 2), bag.color, bag.material))
	end
	-- GEAR: the three vests on a rail, a shelf of energy drinks and medkits under them.
	deco(part(folder, "Rail", Vector3.new(W / 2 - 4, 0.15, 0.15), frame * CFrame.new(c, 8.3, back - 0.6), Color3.fromRGB(150, 152, 156), Enum.Material.Metal))
	for index, vest in VESTS do
		local x = c + (index - 2) * 2.8
		local z = back - 0.6
		deco(part(folder, "Hook", Vector3.new(0.1, 0.5, 0.1), frame * CFrame.new(x, 8.0, z), Color3.fromRGB(150, 152, 156), Enum.Material.Metal))
		deco(part(folder, `Vest_{vest.id}`, vest.size, frame * CFrame.new(x, 7.75 - vest.size.Y / 2, z), vest.color, Enum.Material.Fabric))
		if vest.band then
			deco(part(folder, "VestBand", Vector3.new(vest.size.X + 0.04, 0.24, vest.size.Z + 0.04), frame * CFrame.new(x, 7.75 - vest.size.Y * 0.62, z), vest.band, Enum.Material.SmoothPlastic))
		end
	end
	deco(part(folder, "Shelf", Vector3.new(W / 2 - 3, 0.25, 1.1), frame * CFrame.new(c, 4.1, back - 0.55), WOOD, Enum.Material.WoodPlanks))
	for n = 0, 2 do
		local can = deco(part(folder, "EnergyDrink", Vector3.new(0.7, 0.42, 0.42), frame * CFrame.new(c - 4 + n * 0.6, 4.58, back - 0.5) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 200, 120), Enum.Material.Metal))
		can.Shape = Enum.PartType.Cylinder
	end
	for n = 0, 1 do
		local x = c + 1.4 + n * 1.6
		deco(part(folder, "Medkit", Vector3.new(1.2, 0.8, 0.7), frame * CFrame.new(x, 4.62, back - 0.55), Color3.fromRGB(236, 236, 232), Enum.Material.SmoothPlastic))
		deco(part(folder, "MedkitCross", Vector3.new(0.5, 0.16, 0.06), frame * CFrame.new(x, 4.62, back - 0.92), Color3.fromRGB(200, 40, 40), Enum.Material.SmoothPlastic))
	end
	-- The name board on the roof, facing the yard (the contract look of every shop's board).
	tools.sign(folder, tuning.Board, Vector3.new(W, 3.2, 0.4), frame * CFrame.new(0, H + 2.1, -D / 2 + 0.6), Color3.fromRGB(255, 255, 255), nil, "supplies")
	-- 6.12.6: the giant props over the counters, behind the board (ShopArt.Mounts: the vest over GEAR, the bag over BAGS).
	local props = require(script.Parent.ShopProps)
	props.place(folder, "gearvest", frame * props.mount("gearvest"))
	props.place(folder, "zdcbag", frame * props.mount("zdcbag"))
end

return GearStall
