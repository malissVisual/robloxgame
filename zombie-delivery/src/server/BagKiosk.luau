--!strict
-- 6.6, ZDC Bags: the depot's bag kiosk (the owner: "you can't have a bag and a backpack at the same time ... I need a
-- shop for them"). A small open stall in the depot's safe yard, east of the spawn pad, its counter facing the spawn:
-- a floor, a counter with the shop prompt (World's ShopPrompts: "Shop" → the OpenShop remote, client/Hud.luau's
-- renderShop draws the BAGS list with client/KitShop.luau), a back wall with the five bags hanging on it, two posts, a
-- striped awning, a lamp for the night and the name board on the roof. Where it stands: Config.BagShop (Map.Shops.bags;
-- clear of the spawn pad, the scooter rack, the job board, the garage terminal and Marge). It sells the bags only
-- (server/Shops.luau onKit: a bag is bought here, the rest of the kit at Last Stop Supplies).
--
-- server/World.luau's buildDepot calls BagKiosk.build with its own helpers (no new top-level locals there: the -O0
-- register limit), the way it hands them to BuildingLooks' Kit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)

local BagKiosk = {}

export type Tools = {
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	deco: (p: Part) -> Part,
	sign: (parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3, background: Color3?, art: string?, artHeight: number?) -> (),
	prompt: (parent: BasePart, shop: string, action: string, object: string) -> (),
	nightLight: (item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?) -> (),
}

-- The bags on the back wall, left to right as you face the counter: their look in a few blocks of colour.
local SHOWN: { { id: string, size: Vector3, color: Color3, material: Enum.Material } } = {
	{ id = "bag", size = Vector3.new(1.2, 1.5, 0.3), color = Color3.fromRGB(235, 235, 228), material = Enum.Material.SmoothPlastic },
	{ id = "tote", size = Vector3.new(1.5, 1.7, 0.35), color = Color3.fromRGB(214, 196, 158), material = Enum.Material.Fabric },
	{ id = "thermal", size = Vector3.new(1.7, 1.5, 1.1), color = Color3.fromRGB(178, 40, 34), material = Enum.Material.Fabric },
	{ id = "padded", size = Vector3.new(1.7, 1.3, 0.5), color = Color3.fromRGB(110, 114, 120), material = Enum.Material.Fabric },
	{ id = "duffel", size = Vector3.new(2.4, 1.1, 1.1), color = Color3.fromRGB(58, 84, 56), material = Enum.Material.Fabric },
}

-- Builds the kiosk under `parent` (the depot's folder) at Config.BagShop, facing -X (the spawn).
function BagKiosk.build(parent: Instance, tools: Tools)
	local shop = Map.Shops.bags
	if not shop then
		return
	end
	local part, deco = tools.part, tools.deco
	local folder = Instance.new("Folder")
	folder.Name = "ZdcBags"
	folder.Parent = parent
	local base = Vector3.new(shop.x, Map.WalkTop, shop.z)
	-- (local -Z is the front: the counter faces the spawn pad to the west)
	local frame = CFrame.lookAt(base, base + Vector3.new(-1, 0, 0))
	local red = Color3.fromRGB(190, 44, 38)
	local cream = Color3.fromRGB(236, 230, 214)
	local charcoal = Color3.fromRGB(38, 43, 47)
	local wood = Color3.fromRGB(128, 94, 62)
	local W, D, H = 11, 7, 9 -- the stall: wide, deep, high (studs)
	deco(part(folder, "Floor", Vector3.new(W + 1, 0.2, D + 1), frame * CFrame.new(0, 0.1, 0.5), Color3.fromRGB(150, 146, 138), Enum.Material.Concrete))
	-- The counter (the shop's prompt) and its red front with the stripe.
	local counter = part(folder, "Counter", Vector3.new(W - 1, 3.4, 2.2), frame * CFrame.new(0, 1.7, -2), wood, Enum.Material.WoodPlanks)
	deco(part(folder, "CounterTop", Vector3.new(W - 0.6, 0.2, 2.6), frame * CFrame.new(0, 3.5, -2), charcoal, Enum.Material.Metal))
	deco(part(folder, "CounterFront", Vector3.new(W - 1.2, 2.4, 0.1), frame * CFrame.new(0, 1.8, -3.15), red, Enum.Material.Metal))
	deco(part(folder, "CounterStripe", Vector3.new(W - 1.2, 0.25, 0.12), frame * CFrame.new(0, 2.6, -3.2), cream, Enum.Material.Metal))
	tools.prompt(counter, "bags", "Shop", shop.name)
	-- The back wall and the bags on it.
	part(folder, "BackWall", Vector3.new(W, H, 0.6), frame * CFrame.new(0, H / 2, D / 2), charcoal, Enum.Material.Metal)
	deco(part(folder, "Pegboard", Vector3.new(W - 1.5, 3.4, 0.1), frame * CFrame.new(0, 5.6, D / 2 - 0.35), cream, Enum.Material.WoodPlanks))
	local step = (W - 3) / math.max(1, #SHOWN - 1)
	for index, bag in SHOWN do
		local x = -(W - 3) / 2 + (index - 1) * step
		deco(part(folder, "Peg", Vector3.new(0.12, 0.12, 0.4), frame * CFrame.new(x, 6.9, D / 2 - 0.55), charcoal, Enum.Material.Metal))
		deco(part(folder, `Bag_{bag.id}`, bag.size, frame * CFrame.new(x, 6.8 - bag.size.Y / 2 - 0.1, D / 2 - 0.4 - bag.size.Z / 2), bag.color, bag.material))
	end
	-- Two posts, the roof and its striped awning.
	for _, side in { -1, 1 } do
		part(folder, "Post", Vector3.new(0.5, H, 0.5), frame * CFrame.new(side * (W / 2 - 0.25), H / 2, -D / 2 + 0.25), charcoal, Enum.Material.Metal)
		deco(part(folder, "SideWall", Vector3.new(0.3, H - 3.6, D - 1), frame * CFrame.new(side * (W / 2 - 0.15), 3.6 + (H - 3.6) / 2, 0.5), cream, Enum.Material.Metal))
	end
	part(folder, "Roof", Vector3.new(W + 1, 0.5, D + 1), frame * CFrame.new(0, H + 0.25, 0.5), charcoal, Enum.Material.Metal)
	local stripes = 8
	for n = 1, stripes do
		local width = (W + 1) / stripes
		deco(part(folder, "Awning", Vector3.new(width, 0.2, 2.2), frame * CFrame.new(-(W + 1) / 2 + (n - 0.5) * width, H - 0.45, -D / 2 - 0.9) * CFrame.Angles(math.rad(-22), 0, 0), if n % 2 == 1 then red else cream, Enum.Material.Fabric))
	end
	-- A lamp under the roof (warm at night).
	local lamp = deco(part(folder, "Lamp", Vector3.new(W - 3, 0.2, 0.6), frame * CFrame.new(0, H - 0.2, -1), Color3.fromRGB(156, 146, 122), Enum.Material.Glass))
	tools.nightLight(lamp, Color3.fromRGB(255, 220, 150), lamp.Color, "Glass")
	-- The name board on the roof, facing the spawn (the contract look of every shop's board).
	tools.sign(folder, string.upper(Config.BagShop.Name) .. "  BAGS FOR COURIERS", Vector3.new(W, 2.6, 0.4), frame * CFrame.new(0, H + 1.9, -D / 2 + 0.6), Color3.fromRGB(255, 255, 255), nil, "bags")
end

return BagKiosk
