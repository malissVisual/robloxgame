--!strict
-- Cargo you handle on foot: crates, sacks, barrels, ice boxes, furniture you pick up and carry in your hands, horses
-- you lead on a rope, kids who walk in and out by themselves. Loaded pieces ride visibly in the vehicle.
--
-- server/Jobs.luau opens a Session for every job and gives it one stop (a Plan) at a time:
--   carry  the giver stands at the pile with the pieces: "Pick up" (E) puts one in your hands (the character
--          attribute Carrying = its kind, the model is welded in front of the chest), "Load" at the back of the
--          vehicle puts it in a cargo slot. At the drop "Take out" at the back, then "Hand over" at the receiver.
--   lead   the same with horses: "Lead" takes one on the rope (Carrying = "horse"), "Load" puts it in a stall.
--   board  park in the circle and wait: the kids walk from the house to the bus door (and at the school out of it).
--   serve  park in the circle and hold still while the customers buy (the ice cream route).
-- "Put down" (G) drops what you hold where you stand (to shoot); it also drops when the carrier dies, leaves or sits.
-- Only the job's owner and their crew (who rode in the owner's car) may use the prompts, checked here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Vehicles = require(script.Parent.Vehicles)
local Npcs = require(script.Parent.Npcs)
local Animals = require(script.Parent.Animals)

local Tuning = Config.Cargo
local Cargo = {}

-- One stop as Jobs sees it.
export type Plan = {
	stage: string, -- pickup | drop
	mode: string, -- carry | lead | board | serve
	needed: number, -- pieces handled at this stop
	park: Vector3, -- the circle (the vehicle stops here)
	pile: Vector3, -- where the cargo stands / the receiver waits
	facing: Vector3, -- the way the person faces (flat, unit)
	person: Npcs.Look?, -- the giver / the receiver
	hold: number, -- serve: seconds to hold still
	keep: number, -- serve: pieces left in the vehicle after this stop
}

-- What the job is about, given when it starts.
export type Info = {
	kind: string, -- the Carrying kind: crate | ammo | sack | barrel | icebox | furniture | soup | horse | kid
	look: string, -- the model of a piece
	piece: string, -- "ammo crate"
	plural: string,
	total: number,
	handles: boolean, -- some stop is carry / lead (the vehicle gets the Load prompt)
	allowed: (Player) -> boolean, -- the owner and the crew
	changed: () -> (), -- something to send to the HUD
}

type Piece = {
	kind: string,
	look: string,
	variant: number,
	origin: number, -- the stop it was picked up at
	horse: Model?, -- a horse (lead)
	model: Model?, -- the visible piece where it is now (pile, hands, ground, a slot in the vehicle)
	npc: Model?, -- a kid standing or walking
	walkingSince: number?,
}

type Held = { piece: Piece, character: Model, root: BasePart, prompt: ProximityPrompt?, last: CFrame }
type Loose = { piece: Piece, prompt: ProximityPrompt, handle: Part? }

export type Session = {
	owner: Player,
	info: Info,
	load: { Piece }, -- in the vehicle, in slot order
	held: { [Player]: Held },
	loose: { Loose }, -- put down somewhere
	lost: number, -- stolen, wrecked
	deliveredTotal: number,
	nextVariant: number,
	-- the current stop
	plan: Plan?,
	stop: number,
	built: boolean,
	greeted: boolean,
	pile: { Piece },
	walking: { Piece },
	moved: number, -- loaded at this pick-up / handed over at this drop
	hold: number, -- serve: seconds held still
	served: boolean,
	customers: boolean,
	nextKid: number,
	person: Model?,
	pilePart: Part?,
	pilePrompt: ProximityPrompt?,
	props: { Instance }, -- the stop's people, delivered pieces
	propHorses: { Model },
	-- the vehicle
	car: Vehicles.Car?,
	carPrompt: ProximityPrompt?,
	shown: { Model },
	ended: boolean,
}

export type Status = {
	inCar: number,
	delivered: number,
	needed: number,
	total: number,
	deliveredTotal: number,
	lost: number,
	carrying: string?,
	person: string?,
	pile: Vector3?,
	progress: number,
}

local folder: Instance = workspace
local rng = Random.new()
local notice = Net.get("Notice")

local KID_NAMES = { "Tommy", "Lily", "Max", "Sophie", "Leo", "Mia", "Ben", "Zoe", "Sam", "Ava", "Noah", "Ella" }
local LINES = {
	take = { "Careful, it's heavy!", "Lift with your legs!", "Got it?", "Easy, that one's fragile.", "Watch your back out there." },
	horse = { "Easy now, she's gentle.", "Walk him slowly up the ramp.", "Keep the rope short." },
	loaded = { "That's all of it. Drive safe!", "All loaded. Watch out for bandits!" },
	thanks = { "Thanks!", "Perfect, thank you!", "Just in time!", "Great work!", "Put it right there." },
	done = { "That's everything. Thank you!", "All here. You're a lifesaver!" },
	kidOn = { "Bye mom!", "Hi driver!", "Can I sit at the back?" },
	kidOff = { "Bye!", "Thanks for the ride!", "School, yay..." },
	customer = { "Vanilla, please!", "Chocolate!", "Two scoops!", "Strawberry, please!" },
}

local function line(list: { string }): string
	return list[rng:NextInteger(1, #list)]
end

local function tell(player: Player, text: string)
	notice:FireClient(player, text)
end

local function article(noun: string): string
	local first = string.lower(string.sub(noun, 1, 1))
	return if string.find("aeiou", first, 1, true) then "an " .. noun else "a " .. noun
end

local function capital(text: string): string
	return string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Is this character carrying something (the kind) or leading an animal ("horse")?
function Cargo.carrying(character: Model?): string?
	if not character then
		return nil
	end
	local value = character:GetAttribute("Carrying")
	return if type(value) == "string" then value else nil
end

-- ── The ground ─────────────────────────────────────────────────────────────

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- The height of the walkable ground at x, z (near `around`): not a roof, a tree or a car.
local function groundY(x: number, z: number, around: number): number
	local skip: { Instance } = { folder }
	for _, name in { "Cars", "Zombies", "Npcs", "Animals", "Effects", "Loot", "Showroom" } do
		local child = workspace:FindFirstChild(name)
		if child then
			table.insert(skip, child)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = skip
	local result = workspace:Raycast(Vector3.new(x, around + 25, z), Vector3.new(0, -60, 0), groundParams)
	if result and result.Position.Y < around + 6 and result.Position.Y > around - 10 then
		return result.Position.Y
	end
	return around
end

local function onGround(position: Vector3): Vector3
	return Vector3.new(position.X, groundY(position.X, position.Z, position.Y), position.Z)
end

-- ── The pieces ─────────────────────────────────────────────────────────────

local function newPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Parent = model
	return p
end

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Text printed on a side of a part (a stencil on a crate).
local function stencil(part: BasePart, text: string, color: Color3, faces: { Enum.NormalId })
	for _, face in faces do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.9, 0.5)
		label.Position = UDim2.fromScale(0.05, 0.25)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = color
		label.Parent = gui
		gui.Parent = part
	end
end

local FRONT_BACK = { Enum.NormalId.Front, Enum.NormalId.Back }
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder standing up

-- A piece of cargo built at the origin: the bottom centre is the pivot, the front is -Z.
local function buildLook(look: string, variant: number): Model
	local model = Instance.new("Model")
	model.Name = "Cargo"
	local function block(name: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material): Part
		return newPart(model, name, size, CFrame.new(at), color, material)
	end
	local function cylinder(name: string, height: number, diameter: number, y: number, color: Color3, material: Enum.Material): Part
		local p = newPart(model, name, Vector3.new(height, diameter, diameter), CFrame.new(0, y, 0) * UPRIGHT, color, material)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	local function crate(size: Vector3, wood: Color3): Part
		local body = block("Body", size, Vector3.new(0, size.Y / 2, 0), wood, Enum.Material.WoodPlanks)
		local dark = wood:Lerp(Color3.new(0, 0, 0), 0.3)
		block("Rim", Vector3.new(size.X + 0.1, 0.25, size.Z + 0.1), Vector3.new(0, size.Y - 0.12, 0), dark, Enum.Material.Wood)
		block("Rim", Vector3.new(size.X + 0.1, 0.25, size.Z + 0.1), Vector3.new(0, 0.12, 0), dark, Enum.Material.Wood)
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				block("Post", Vector3.new(0.28, size.Y, 0.28), Vector3.new(x * (size.X / 2 - 0.1), size.Y / 2, z * (size.Z / 2 - 0.1)), dark, Enum.Material.Wood)
			end
		end
		return body
	end
	local function cardboard(size: Vector3): Part
		local body = block("Body", size, Vector3.new(0, size.Y / 2, 0), rgb(196, 158, 108), Enum.Material.Cardboard)
		block("Tape", Vector3.new(0.45, size.Y + 0.02, size.Z + 0.02), Vector3.new(0, size.Y / 2, 0), rgb(222, 200, 160), Enum.Material.SmoothPlastic)
		return body
	end

	if look == "crate" or look == "tools" then
		local body = crate(Vector3.new(2.2, 2, 2.2), rgb(163, 120, 74))
		if look == "tools" then
			stencil(body, "TOOLS", rgb(190, 40, 30), FRONT_BACK)
		end
	elseif look == "ammo" then
		local olive = rgb(84, 96, 58)
		local body = block("Body", Vector3.new(2.6, 1.4, 1.5), Vector3.new(0, 0.7, 0), olive, Enum.Material.Metal)
		block("Lid", Vector3.new(2.7, 0.25, 1.6), Vector3.new(0, 1.45, 0), olive:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Metal)
		for _, x in { -1.4, 1.4 } do
			block("Handle", Vector3.new(0.25, 0.3, 0.8), Vector3.new(x, 1.0, 0), rgb(40, 42, 40), Enum.Material.Metal)
		end
		stencil(body, "7.62 AMMO", rgb(235, 205, 70), FRONT_BACK)
	elseif look == "sack" or look == "bread" then
		local colors = { rgb(186, 160, 112), rgb(170, 140, 95), rgb(200, 178, 126) }
		local color = if look == "bread" then rgb(228, 210, 172) else colors[variant % #colors + 1]
		local body = block("Body", Vector3.new(1.8, 1.5, 1.2), Vector3.new(0, 0.75, 0), color, Enum.Material.Fabric)
		block("Top", Vector3.new(1.3, 0.45, 0.9), Vector3.new(0, 1.7, 0), color, Enum.Material.Fabric)
		block("Tie", Vector3.new(1.35, 0.14, 0.95), Vector3.new(0, 1.55, 0), rgb(120, 90, 50), Enum.Material.Fabric)
		if look == "bread" then
			for n, x in { -0.35, 0.3 } do
				local loaf = newPart(model, "Baguette", Vector3.new(1.6, 0.35, 0.35), CFrame.new(x, 2.05, 0) * CFrame.Angles(0, 0, math.rad(if n == 1 then 75 else 100)), rgb(212, 150, 70), Enum.Material.SmoothPlastic)
				loaf.Shape = Enum.PartType.Cylinder
			end
			stencil(body, "BREAD", rgb(120, 70, 30), FRONT_BACK)
		else
			stencil(body, "OLD FARM", rgb(90, 60, 30), FRONT_BACK)
		end
	elseif look == "barrel" then
		local colors = { rgb(190, 50, 40), rgb(40, 80, 170), rgb(214, 170, 40) }
		local color = colors[variant % #colors + 1]
		cylinder("Body", 3, 2.2, 1.5, color, Enum.Material.Metal)
		for _, y in { 0.15, 1.0, 2.0, 2.85 } do
			cylinder("Rib", 0.16, 2.3, y, color:Lerp(Color3.new(0, 0, 0), 0.35), Enum.Material.Metal)
		end
		cylinder("Lid", 0.06, 2.0, 3.0, rgb(70, 70, 74), Enum.Material.Metal)
		local label = block("Label", Vector3.new(1, 0.8, 0.05), Vector3.new(0, 1.55, -1.1), rgb(240, 240, 235), Enum.Material.SmoothPlastic)
		stencil(label, "FUEL", rgb(200, 30, 30), { Enum.NormalId.Front })
	elseif look == "icebox" or look == "vaccine" then
		local lid = if look == "vaccine" then rgb(200, 40, 40) else rgb(60, 140, 220)
		local body = block("Body", Vector3.new(2.4, 1.5, 1.6), Vector3.new(0, 0.75, 0), rgb(240, 244, 248), Enum.Material.SmoothPlastic)
		block("Lid", Vector3.new(2.5, 0.35, 1.7), Vector3.new(0, 1.65, 0), lid, Enum.Material.SmoothPlastic)
		block("Handle", Vector3.new(1.4, 0.2, 0.3), Vector3.new(0, 1.92, 0), rgb(60, 60, 64), Enum.Material.Metal)
		stencil(body, if look == "vaccine" then "VACCINE" else "FROSTY'S", lid, FRONT_BACK)
	elseif look == "sample" then
		local body = block("Body", Vector3.new(2.2, 1.4, 1.4), Vector3.new(0, 0.7, 0), rgb(160, 165, 170), Enum.Material.DiamondPlate)
		block("Window", Vector3.new(1.2, 0.5, 0.05), Vector3.new(0, 0.75, -0.72), rgb(90, 255, 90), Enum.Material.Neon)
		block("Handle", Vector3.new(1.2, 0.2, 0.3), Vector3.new(0, 1.5, 0), rgb(50, 50, 54), Enum.Material.Metal)
		stencil(body, "BIOHAZARD", rgb(230, 200, 40), { Enum.NormalId.Back })
	elseif look == "soup" then
		local body = block("Body", Vector3.new(2, 1.6, 1.6), Vector3.new(0, 0.8, 0), rgb(230, 120, 40), Enum.Material.SmoothPlastic)
		block("Lid", Vector3.new(2.1, 0.3, 1.7), Vector3.new(0, 1.75, 0), rgb(70, 70, 74), Enum.Material.SmoothPlastic)
		block("Handle", Vector3.new(1.2, 0.2, 0.3), Vector3.new(0, 2.0, 0), rgb(40, 40, 44), Enum.Material.Metal)
		stencil(body, "HOT SOUP", rgb(255, 255, 255), FRONT_BACK)
		local steam = Instance.new("Smoke")
		steam.Color = rgb(255, 255, 255)
		steam.Opacity = 0.08
		steam.Size = 0.6
		steam.RiseVelocity = 2
		steam.Parent = body
	elseif look == "parcel" then
		local sizes = { Vector3.new(1.8, 1.4, 1.4), Vector3.new(2.2, 1.6, 1.6), Vector3.new(1.6, 1.2, 1.3) }
		local size = sizes[variant % #sizes + 1]
		cardboard(size)
		block("Label", Vector3.new(0.7, 0.5, 0.03), Vector3.new(0.45, size.Y * 0.55, -size.Z / 2 - 0.02), rgb(245, 245, 240), Enum.Material.SmoothPlastic)
	elseif look == "groceries" then
		block("Body", Vector3.new(2.2, 1.3, 1.6), Vector3.new(0, 0.65, 0), rgb(196, 158, 108), Enum.Material.Cardboard)
		for n, color in { rgb(200, 40, 40), rgb(240, 150, 40), rgb(110, 170, 60) } do
			local fruit = block("Fruit", Vector3.new(0.6, 0.6, 0.6), Vector3.new(-0.7 + (n - 1) * 0.7, 1.35, (n % 2) * 0.3 - 0.15), color, Enum.Material.SmoothPlastic)
			fruit.Shape = Enum.PartType.Ball
		end
	elseif look == "medicine" then
		block("Body", Vector3.new(2, 1.4, 1.4), Vector3.new(0, 0.7, 0), rgb(245, 245, 245), Enum.Material.SmoothPlastic)
		for _, z in { -0.71, 0.71 } do
			block("Cross", Vector3.new(0.8, 0.25, 0.03), Vector3.new(0, 0.75, z), rgb(210, 30, 30), Enum.Material.SmoothPlastic)
			block("Cross", Vector3.new(0.25, 0.8, 0.03), Vector3.new(0, 0.75, z), rgb(210, 30, 30), Enum.Material.SmoothPlastic)
		end
	elseif look == "pizza" then
		for n = 0, 2 + variant % 2 do
			block("Box", Vector3.new(2, 0.32, 2), Vector3.new(0, 0.16 + n * 0.34, 0), rgb(214, 184, 140), Enum.Material.Cardboard)
		end
		block("Logo", Vector3.new(0.9, 0.04, 0.9), Vector3.new(0, 0.34 * (3 + variant % 2) + 0.01, 0), rgb(200, 40, 30), Enum.Material.SmoothPlastic)
	elseif look == "gold" then
		block("Body", Vector3.new(2, 1.2, 1.4), Vector3.new(0, 0.6, 0), rgb(60, 62, 66), Enum.Material.DiamondPlate)
		block("Trim", Vector3.new(2.05, 0.15, 1.45), Vector3.new(0, 1.2, 0), rgb(230, 180, 50), Enum.Material.Metal)
		block("Lock", Vector3.new(0.4, 0.4, 0.05), Vector3.new(0, 0.8, -0.72), rgb(230, 180, 50), Enum.Material.Metal)
	elseif look == "cake" then
		block("Body", Vector3.new(1.8, 1.8, 1.8), Vector3.new(0, 0.9, 0), rgb(250, 248, 245), Enum.Material.SmoothPlastic)
		local pink = rgb(240, 120, 170)
		block("Ribbon", Vector3.new(0.3, 1.82, 1.82), Vector3.new(0, 0.9, 0), pink, Enum.Material.Fabric)
		block("Ribbon", Vector3.new(1.82, 1.82, 0.3), Vector3.new(0, 0.9, 0), pink, Enum.Material.Fabric)
		block("Bow", Vector3.new(0.8, 0.3, 0.4), Vector3.new(0, 1.95, 0), pink, Enum.Material.Fabric)
	elseif look == "furniture" then
		local fabric = ({ rgb(150, 50, 50), rgb(60, 110, 80), rgb(60, 80, 140), rgb(170, 140, 100) })[variant % 4 + 1]
		local wood = rgb(110, 76, 46)
		local kind = variant % 6
		if kind == 0 then
			local body = cardboard(Vector3.new(2.2, 2, 2.2))
			stencil(body, "FRAGILE", rgb(200, 30, 30), FRONT_BACK)
		elseif kind == 1 then -- an armchair
			block("Seat", Vector3.new(2.4, 0.8, 2.2), Vector3.new(0, 0.9, 0), fabric, Enum.Material.Fabric)
			block("Back", Vector3.new(2.4, 1.8, 0.5), Vector3.new(0, 1.9, 0.85), fabric, Enum.Material.Fabric)
			for _, x in { -1.1, 1.1 } do
				block("Arm", Vector3.new(0.45, 1.0, 2.2), Vector3.new(x, 1.3, 0), fabric:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Fabric)
				for _, z in { -0.9, 0.9 } do
					block("Leg", Vector3.new(0.25, 0.5, 0.25), Vector3.new(x, 0.25, z), wood, Enum.Material.Wood)
				end
			end
		elseif kind == 2 then -- a floor lamp
			cylinder("Base", 0.2, 1.2, 0.1, rgb(50, 50, 54), Enum.Material.Metal)
			block("Pole", Vector3.new(0.15, 3.2, 0.15), Vector3.new(0, 1.7, 0), rgb(50, 50, 54), Enum.Material.Metal)
			cylinder("Shade", 1, 1.4, 3.4, rgb(240, 225, 190), Enum.Material.Fabric)
		elseif kind == 3 then -- a television
			block("Body", Vector3.new(2.4, 1.6, 0.7), Vector3.new(0, 0.8, 0), rgb(30, 30, 34), Enum.Material.SmoothPlastic)
			block("Screen", Vector3.new(2.1, 1.3, 0.05), Vector3.new(0, 0.82, -0.36), rgb(25, 35, 50), Enum.Material.Glass)
		elseif kind == 4 then -- a chair
			block("Seat", Vector3.new(1.6, 0.25, 1.6), Vector3.new(0, 1.1, 0), wood, Enum.Material.Wood)
			block("Back", Vector3.new(1.6, 1.5, 0.25), Vector3.new(0, 1.95, 0.7), wood, Enum.Material.Wood)
			for _, x in { -0.65, 0.65 } do
				for _, z in { -0.65, 0.65 } do
					block("Leg", Vector3.new(0.22, 1.0, 0.22), Vector3.new(x, 0.5, z), wood, Enum.Material.Wood)
				end
			end
		else -- a potted plant
			cylinder("Pot", 1.1, 1.2, 0.55, rgb(170, 90, 60), Enum.Material.Slate)
			local leaves = block("Leaves", Vector3.new(1.9, 1.9, 1.9), Vector3.new(0, 1.9, 0), rgb(70, 130, 60), Enum.Material.Grass)
			leaves.Shape = Enum.PartType.Ball
		end
	elseif look == "kid" then
		-- A kid in the bus window: shoulders and a head.
		local shirts = { rgb(220, 60, 60), rgb(60, 120, 220), rgb(250, 200, 60), rgb(90, 180, 90), rgb(200, 100, 200) }
		local skins = { rgb(255, 214, 180), rgb(200, 150, 110), rgb(140, 95, 65), rgb(240, 190, 150) }
		block("Body", Vector3.new(1.1, 1.0, 0.6), Vector3.new(0, 0.5, 0), shirts[variant % #shirts + 1], Enum.Material.Fabric)
		local head = block("Head", Vector3.new(0.9, 0.9, 0.9), Vector3.new(0, 1.45, 0), skins[variant % #skins + 1], Enum.Material.SmoothPlastic)
		head.Shape = Enum.PartType.Ball
		block("Hair", Vector3.new(0.92, 0.3, 0.92), Vector3.new(0, 1.8, 0.05), rgb(70, 45, 25), Enum.Material.Fabric)
	else
		crate(Vector3.new(2.2, 2, 2.2), rgb(163, 120, 74))
	end

	local main = model:FindFirstChildWhichIsA("BasePart")
	if main then
		model.PrimaryPart = main
		main.PivotOffset = main.CFrame:Inverse()
	end
	local size = model:GetExtentsSize()
	model:SetAttribute("Height", size.Y)
	model:SetAttribute("Depth", size.Z)
	return model
end

local function buildPiece(piece: Piece): Model
	local model = buildLook(piece.look, piece.variant)
	model.Parent = folder
	return model
end

local function unweld(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
end

-- Weld a piece to a part (the chassis, the carrier's root) with its pivot at `at`.
local function weldTo(model: Model, target: BasePart, at: CFrame)
	unweld(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	model:PivotTo(at)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
			d.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = target
			weld.Part1 = d
			weld.Parent = d
		end
	end
end

-- Put a piece on the ground (anchored, solid: you walk around it).
local function setDown(model: Model, at: CFrame)
	unweld(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.Massless = false
			d.CanCollide = d == model.PrimaryPart
		end
	end
	model:PivotTo(at)
	model.Parent = folder
end

-- In front of the chest: the piece's middle at chest height, its back against the body.
local function carryFrame(model: Model): CFrame
	local height = model:GetAttribute("Height")
	local depth = model:GetAttribute("Depth")
	local h = if type(height) == "number" then height else 2
	local d = if type(depth) == "number" then depth else 2
	return CFrame.new(0, 1.1 - h / 2, -(0.6 + d / 2))
end

local function prompt(parent: Instance, action: string, object: string, key: Enum.KeyCode?, hold: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.KeyboardKeyCode = key or Enum.KeyCode.E
	if key == Enum.KeyCode.G then
		p.GamepadKeyCode = Enum.KeyCode.ButtonB
	end
	p.HoldDuration = hold or Tuning.HoldDuration
	p.MaxActivationDistance = Tuning.PromptDistance
	p.RequiresLineOfSight = false
	p.Parent = parent
	return p
end

-- A horse's body part (prompts go there), if the horse has one.
local function horsePart(horse: Model): BasePart?
	return horse.PrimaryPart or horse:FindFirstChildWhichIsA("BasePart", true)
end

local function removeNpc(npc: Model?)
	if npc and npc.Parent then
		Npcs.remove(npc)
	end
end

local function say(npc: Model?, text: string)
	if npc and npc.Parent then
		Npcs.say(npc, text, 3)
	end
end

-- ── The session ─────────────────────────────────────────────────────────────

local function newPiece(session: Session): Piece
	session.nextVariant += 1
	return { kind = session.info.kind, look = session.info.look, variant = session.nextVariant, origin = session.stop }
end

local function heldCount(session: Session): number
	local n = 0
	for _ in session.held do
		n += 1
	end
	return n
end

-- The pieces this drop can still get: what it needs, or less when pieces were lost on the way.
local function neededNow(session: Session): number
	local plan = session.plan
	if not plan then
		return 0
	end
	if plan.stage == "pickup" then
		return plan.needed
	end
	return math.min(plan.needed, session.moved + #session.load + heldCount(session) + #session.loose + #session.walking)
end

-- The owner's car standing in the stop's circle.
local function parkedCar(session: Session): Vehicles.Car?
	local car = Vehicles.get(session.owner)
	local plan = session.plan
	if not car or not plan then
		return nil
	end
	if flat(car.chassis.Position, plan.park) > Config.Jobs.DeliverRadius or Vehicles.speed(car) > Config.Jobs.HoldMaxSpeed then
		return nil
	end
	return car
end

local function ownerPosition(session: Session): Vector3?
	local car = Vehicles.seatedIn(session.owner)
	if car then
		return car.chassis.Position
	end
	local root = rootOf(session.owner.Character)
	return if root then root.Position else nil
end

local function refresh(session: Session)
	local plan = session.plan
	local horse = session.info.kind == "horse"
	local carPrompt = session.carPrompt
	local car = session.car
	if carPrompt and car then
		local handling = plan ~= nil and (plan.mode == "carry" or plan.mode == "lead")
		local takeOut = handling and plan ~= nil and plan.stage == "drop" and #session.load > 0
		carPrompt.Enabled = heldCount(session) > 0 or takeOut
		carPrompt.ActionText = if takeOut then (if horse then "Lead out" else "Take out") else (if horse then "Lead in" else "Load")
		carPrompt.ObjectText = `{capital(Vehicles.cargoNoun(car))}: {#session.load} inside`
	end
	local pilePrompt = session.pilePrompt
	if pilePrompt and plan then
		if plan.stage == "pickup" then
			pilePrompt.Enabled = #session.pile > 0
			pilePrompt.ObjectText = `{capital(if horse then "horse" else session.info.piece)} ({#session.pile} left)`
		else
			pilePrompt.Enabled = session.moved < neededNow(session)
			pilePrompt.ObjectText = if plan.person then plan.person.name else "Receiver"
		end
	end
end

-- Show the load in the vehicle: every piece in its slot (the horses in their stalls).
local function render(session: Session)
	for _, model in session.shown do
		model:Destroy()
	end
	table.clear(session.shown)
	local car = session.car
	if not car or car.wrecked then
		return
	end
	car.model:SetAttribute("CargoCount", #session.load)
	car.model:SetAttribute("CargoKind", if #session.load > 0 then session.info.kind else nil)
	local slots = Vehicles.cargoSlots(car)
	for index, piece in session.load do
		local slot = slots[index]
		local horse = piece.horse
		if horse then
			local stall = slot or slots[#slots]
			if stall then
				Animals.stable(horse, car.chassis.CFrame * stall, car.chassis)
			end
		elseif slot then
			local model = buildLook(piece.look, piece.variant)
			weldTo(model, car.chassis, car.chassis.CFrame * slot)
			model.Parent = car.model
			table.insert(session.shown, model)
		end
	end
end

local function clearHeld(session: Session, player: Player): Held?
	local held = session.held[player]
	if not held then
		return nil
	end
	session.held[player] = nil
	if held.character.Parent then
		held.character:SetAttribute("Carrying", nil)
	end
	if held.prompt then
		held.prompt:Destroy()
	end
	return held
end

local onLoose: (Session, Player, Loose) -> ()
local putDown: (Session, Player) -> ()

-- Into the hands (or on the rope).
local function take(session: Session, player: Player, piece: Piece): boolean
	local character = player.Character
	local root = rootOf(character)
	if not character or not root then
		return false
	end
	local held: Held = { piece = piece, character = character, root = root, prompt = nil, last = root.CFrame }
	local horse = piece.horse
	if horse then
		Animals.stable(horse, nil)
		Animals.lead(horse, character)
		local part = horsePart(horse)
		if part then
			local letGo = prompt(part, "Let go", "Horse", Enum.KeyCode.G, 0)
			letGo.MaxActivationDistance = 9 -- the horse walks a few studs behind
			held.prompt = letGo
		end
	else
		local model = piece.model or buildPiece(piece)
		piece.model = model
		model.Parent = folder
		weldTo(model, root, root.CFrame * carryFrame(model))
		local main = model.PrimaryPart
		if main then
			local down = prompt(main, "Put down", capital(session.info.piece), Enum.KeyCode.G, 0)
			down.MaxActivationDistance = 4 -- only for the one holding it
			held.prompt = down
		end
	end
	local p = held.prompt
	if p then
		p.Triggered:Connect(function(by)
			if by == player and session.held[player] == held then
				putDown(session, player)
				session.info.changed()
			end
		end)
	end
	session.held[player] = held
	character:SetAttribute("Carrying", piece.kind)
	refresh(session)
	return true
end

-- Drop what the player holds right where they are; anybody of the crew can pick it up again.
putDown = function(session: Session, player: Player)
	local held = clearHeld(session, player)
	if not held then
		return
	end
	local piece = held.piece
	local front = held.last * CFrame.new(0, 0, -2.2)
	local spot = onGround(Vector3.new(front.Position.X, held.last.Position.Y - 3, front.Position.Z))
	local look = held.last.LookVector
	local frame = CFrame.lookAt(spot, spot + Vector3.new(look.X, 0, look.Z))
	local loose: Loose
	local horse = piece.horse
	if horse then
		Animals.lead(horse, nil)
		local at = horse:GetPivot().Position
		local handle = Instance.new("Part")
		handle.Name = "LooseHorse"
		handle.Size = Vector3.new(1, 1, 1)
		handle.Transparency = 1
		handle.Anchored = true
		handle.CanCollide = false
		handle.CanQuery = false
		handle.CanTouch = false
		handle.Position = if at.Magnitude > 0 then at + Vector3.new(0, 3, 0) else spot + Vector3.new(0, 3, 0)
		handle.Parent = folder
		loose = { piece = piece, prompt = prompt(handle, "Lead", "Horse"), handle = handle }
	else
		local model = piece.model or buildPiece(piece)
		piece.model = model
		setDown(model, frame)
		local main = model.PrimaryPart :: BasePart
		loose = { piece = piece, prompt = prompt(main, "Pick up", capital(session.info.piece)), handle = nil }
	end
	loose.prompt.Triggered:Connect(function(by)
		onLoose(session, by, loose)
	end)
	table.insert(session.loose, loose)
	refresh(session)
end

local function allowed(session: Session, player: Player): boolean
	if session.ended then
		return false
	end
	if session.info.allowed(player) then
		return true
	end
	tell(player, "This is not your delivery.")
	return false
end

local function handsFull(session: Session, player: Player): boolean
	if not session.held[player] and not Cargo.carrying(player.Character) then
		return false
	end
	tell(player, "Your hands are full.")
	return true
end

onLoose = function(session: Session, player: Player, loose: Loose)
	if not allowed(session, player) or handsFull(session, player) then
		return
	end
	local index = table.find(session.loose, loose)
	if not index then
		return
	end
	table.remove(session.loose, index)
	loose.prompt:Destroy()
	if loose.handle then
		loose.handle:Destroy()
	end
	take(session, player, loose.piece)
	session.info.changed()
end

-- Where the receiver puts the delivered pieces: a neat stack at their left.
local function stackFrame(plan: Plan, index: number, side: number): CFrame
	local right = plan.facing:Cross(Vector3.yAxis)
	local col = (index - 1) % 3
	local row = math.floor((index - 1) / 3)
	local spot = plan.pile + right * side * (3 + col * 2.8) - plan.facing * (row * 2.8 + 0.5)
	spot = onGround(spot)
	return CFrame.lookAt(spot, spot + plan.facing) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0)
end

local function handOver(session: Session, player: Player)
	local plan = session.plan
	if not plan then
		return
	end
	if session.moved >= neededNow(session) then
		tell(player, `{if plan.person then plan.person.name else "They"} has everything. Put it back in the vehicle.`)
		return
	end
	local held = clearHeld(session, player)
	if not held then
		return
	end
	local piece = held.piece
	session.moved += 1
	session.deliveredTotal += 1
	local horse = piece.horse
	if horse then
		-- The receiver takes the rope: the horse walks over to the paddock behind them.
		Animals.lead(horse, nil)
		local right = plan.facing:Cross(Vector3.yAxis)
		local paddock = plan.pile - plan.facing * 9 + right * (session.moved * 5 - 7)
		Animals.walkTo(horse, onGround(paddock))
		table.insert(session.propHorses, horse)
	else
		local model = piece.model or buildPiece(piece)
		piece.model = nil
		setDown(model, stackFrame(plan, session.moved, -1))
		table.insert(session.props, model)
	end
	say(session.person, if session.moved >= neededNow(session) then line(LINES.done) else line(LINES.thanks))
	refresh(session)
end

local function onPile(session: Session, player: Player)
	local plan = session.plan
	if not plan or not allowed(session, player) then
		return
	end
	if plan.stage == "drop" then
		if not session.held[player] then
			local car = session.car
			tell(player, `Take {article(session.info.piece)} out of the {if car then Vehicles.cargoNoun(car) else "vehicle"} first (E at the back).`)
			return
		end
		handOver(session, player)
		session.info.changed()
		return
	end
	if handsFull(session, player) then
		return
	end
	local piece = table.remove(session.pile)
	if not piece then
		return
	end
	if take(session, player, piece) then
		say(session.person, if piece.horse then line(LINES.horse) else line(LINES.take))
	else
		table.insert(session.pile, piece)
	end
	session.info.changed()
end

-- The back of the vehicle: load what you hold, or take a piece out at a drop.
local function onCar(session: Session, player: Player)
	local plan = session.plan
	local car = session.car
	if not car or car.wrecked or not allowed(session, player) then
		return
	end
	if Vehicles.speed(car) > Tuning.MaxCarSpeed then
		tell(player, "Stop the vehicle first.")
		return
	end
	local held = session.held[player]
	if held then
		clearHeld(session, player)
		local piece = held.piece
		local horse = piece.horse
		if horse then
			Animals.lead(horse, nil)
		elseif piece.model then
			piece.model:Destroy()
			piece.model = nil
		end
		table.insert(session.load, piece)
		if plan and plan.stage == "pickup" and piece.origin == session.stop then
			session.moved += 1
			if session.moved >= plan.needed then
				say(session.person, line(LINES.loaded))
			end
		end
		render(session)
		refresh(session)
		session.info.changed()
		return
	end
	if plan and plan.stage == "drop" and (plan.mode == "carry" or plan.mode == "lead") then
		local piece = table.remove(session.load)
		if not piece then
			tell(player, `The {Vehicles.cargoNoun(car)} is empty.`)
			return
		end
		render(session)
		local horse = piece.horse
		if horse then
			-- Down the ramp: the horse stands behind the truck, on the rope.
			Animals.stable(horse, nil)
			local behind = (car.chassis.CFrame * CFrame.new(0, 0, car.size.Z / 2 + 5)).Position
			local spot = onGround(Vector3.new(behind.X, car.chassis.Position.Y - 2, behind.Z))
			horse:PivotTo(CFrame.lookAt(spot, spot + car.chassis.CFrame.LookVector))
		end
		if not take(session, player, piece) then
			table.insert(session.load, piece)
			render(session)
		end
		session.info.changed()
		return
	end
	tell(player, `Pick up {article(session.info.piece)} first.`)
end

local function attachCar(session: Session)
	if session.carPrompt then
		session.carPrompt:Destroy()
		session.carPrompt = nil
	end
	local car = session.car
	if not car or not session.info.handles then
		return
	end
	local door = Vehicles.cargoDoor(car)
	if not door then
		return
	end
	local p = prompt(door, "Load", "")
	p.MaxActivationDistance = 9
	p.Triggered:Connect(function(player)
		onCar(session, player)
	end)
	session.carPrompt = p
	refresh(session)
end

-- The stop's people and pieces: built when the owner gets close.
local function build(session: Session)
	local plan = session.plan
	if not plan or session.built then
		return
	end
	session.built = true
	local base = onGround(plan.pile)
	local right = plan.facing:Cross(Vector3.yAxis)
	if plan.person then
		local npc = Npcs.spawn(plan.person, CFrame.lookAt(base, base + plan.facing))
		session.person = npc
		table.insert(session.props, npc)
	end
	if plan.mode == "carry" or plan.mode == "lead" then
		local part = Instance.new("Part")
		part.Name = "CargoPile"
		part.Size = Vector3.new(1, 1, 1)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Position = base + right * 1.5 + Vector3.new(0, 2.5, 0)
		part.Parent = folder
		session.pilePart = part
		table.insert(session.props, part)
		local horse = plan.mode == "lead"
		local action = if plan.stage == "pickup" then (if horse then "Lead" else "Pick up") else "Hand over"
		local p = prompt(part, action, "")
		p.MaxActivationDistance = Tuning.PromptDistance + 2
		p.Triggered:Connect(function(player)
			onPile(session, player)
		end)
		session.pilePrompt = p
	end
	if plan.stage ~= "pickup" then
		refresh(session)
		return
	end
	for n = 1, plan.needed do
		local piece = newPiece(session)
		if plan.mode == "carry" then
			local model = buildPiece(piece)
			setDown(model, stackFrame(plan, n, 1))
			piece.model = model
		elseif plan.mode == "lead" then
			local spot = onGround(base + right * (4 + (n - 1) * 4.5) - plan.facing * 3)
			piece.horse = Animals.horse(CFrame.lookAt(spot, spot + plan.facing))
		elseif plan.mode == "board" then
			local spot = onGround(base + right * (1.5 + n * 1.8) - plan.facing * 0.5)
			local name = KID_NAMES[piece.variant % #KID_NAMES + 1]
			piece.npc = Npcs.spawn(Npcs.look("kid", name, nil), CFrame.lookAt(spot, spot + plan.facing))
		end
		table.insert(session.pile, piece)
	end
	refresh(session)
end

-- Removes what the stop left in the world (people, delivered pieces, the pile); `linger` leaves them a moment.
local function clearStop(session: Session, linger: boolean)
	local props = session.props
	local horses = session.propHorses
	local npcs: { Model } = {}
	local models: { Instance } = {}
	for _, piece in session.pile do
		if piece.horse then
			table.insert(horses, piece.horse)
		end
		if piece.npc then
			table.insert(npcs, piece.npc)
		end
		if piece.model then
			table.insert(models, piece.model)
		end
	end
	for _, piece in session.walking do
		if piece.npc then
			table.insert(npcs, piece.npc)
		end
	end
	session.props = {}
	session.propHorses = {}
	session.pile = {}
	session.walking = {}
	session.person = nil
	session.pilePart = nil
	session.pilePrompt = nil
	local function destroy()
		for _, instance in props do
			if instance:IsA("Model") and instance.Parent and instance:FindFirstChildOfClass("Humanoid") then
				removeNpc(instance)
			else
				instance:Destroy()
			end
		end
		for _, npc in npcs do
			removeNpc(npc)
		end
		for _, model in models do
			model:Destroy()
		end
		for _, horse in horses do
			if horse.Parent then
				Animals.remove(horse)
			end
		end
	end
	if linger then
		-- The prompts go now, the people stay a moment (the receiver says thanks while you drive off).
		for _, instance in props do
			for _, d in instance:GetDescendants() do
				if d:IsA("ProximityPrompt") then
					d:Destroy()
				end
			end
		end
		task.delay(Tuning.Linger, destroy)
	else
		destroy()
	end
end

-- ── Kids and customers ─────────────────────────────────────────────────────

local function kidArrived(session: Session, piece: Piece, stop: number, timedOut: boolean)
	local index = table.find(session.walking, piece)
	if session.ended or session.stop ~= stop or not index then
		return
	end
	local plan = session.plan
	if not plan then
		return
	end
	if plan.stage == "pickup" then
		local car = parkedCar(session)
		local npc = piece.npc
		local close = car ~= nil and npc ~= nil and npc.Parent ~= nil and flat(npc:GetPivot().Position, Vehicles.cargoEntry(car)) < 9
		if not car or not (close or timedOut) then
			-- The bus is not there (any more): wait where you are.
			table.remove(session.walking, index)
			piece.walkingSince = nil
			table.insert(session.pile, piece)
			return
		end
		table.remove(session.walking, index)
		removeNpc(npc)
		piece.npc = nil
		table.insert(session.load, piece)
		session.moved += 1
		render(session)
	else
		table.remove(session.walking, index)
		removeNpc(piece.npc)
		piece.npc = nil
		session.moved += 1
		session.deliveredTotal += 1
		if session.moved >= neededNow(session) then
			say(session.person, "Good morning, everybody! Inside, quick!")
		end
	end
	session.info.changed()
end

local function walkKid(session: Session, piece: Piece, target: Vector3)
	local npc = piece.npc
	if not npc then
		return
	end
	piece.walkingSince = os.clock()
	table.insert(session.walking, piece)
	local stop = session.stop
	Npcs.walkTo(npc, target, function(ok: boolean)
		-- Could not get there in time (a curb, a car in the way): close enough, count it.
		kidArrived(session, piece, stop, not ok)
	end, Tuning.WalkTimeout)
end

local function updateBoard(session: Session, plan: Plan, now: number)
	-- Walkers who never arrive (stuck on a curb) count as arrived after a while.
	for _, piece in table.clone(session.walking) do
		if piece.walkingSince and now - piece.walkingSince > Tuning.WalkTimeout + 1 then
			kidArrived(session, piece, session.stop, true)
		end
	end
	local car = parkedCar(session)
	if not car or now < session.nextKid then
		return
	end
	if plan.stage == "pickup" then
		local piece = table.remove(session.pile, 1)
		if piece then
			session.nextKid = now + Tuning.KidGap
			if session.moved == 0 and #session.walking == 0 then
				say(session.person, "There's the bus! Off you go.")
			end
			if piece.npc then
				say(piece.npc, line(LINES.kidOn))
			end
			walkKid(session, piece, Vehicles.cargoEntry(car))
		end
	elseif session.moved + #session.walking < neededNow(session) then
		local piece = table.remove(session.load)
		if piece then
			session.nextKid = now + Tuning.KidGap
			render(session)
			local door = Vehicles.cargoEntry(car)
			local spot = onGround(door)
			local name = KID_NAMES[piece.variant % #KID_NAMES + 1]
			piece.npc = Npcs.spawn(Npcs.look("kid", name, nil), CFrame.lookAt(spot, Vector3.new(plan.pile.X, spot.Y, plan.pile.Z)))
			say(piece.npc, line(LINES.kidOff))
			walkKid(session, piece, onGround(plan.pile))
			session.info.changed()
		end
	end
end

local function updateServe(session: Session, plan: Plan, dt: number)
	local car = parkedCar(session)
	local holding = car ~= nil and Vehicles.isDriving(session.owner)
	if not holding or not car then
		if session.hold > 0 then
			session.hold = 0
			session.info.changed()
		end
		return
	end
	if not session.customers then
		-- Two kids come to the serving window (the right side).
		session.customers = true
		for n, z in { 0.5, 3.5 } do
			local spot = onGround((car.chassis.CFrame * CFrame.new(car.size.X / 2 + 2.6, 0, z)).Position)
			local npc = Npcs.spawn(Npcs.look("kid", KID_NAMES[rng:NextInteger(1, #KID_NAMES)], nil), CFrame.lookAt(spot, spot - car.chassis.CFrame.RightVector))
			table.insert(session.props, npc)
			task.delay(n * 0.6, say, npc, line(LINES.customer))
		end
	end
	session.hold += dt
	session.info.changed()
	if session.hold >= plan.hold and not session.served then
		session.served = true
		while #session.load > plan.keep do
			local piece = table.remove(session.load)
			if piece and piece.model then
				piece.model:Destroy()
			end
			session.deliveredTotal += 1
		end
		session.moved = plan.needed
		render(session)
	end
end

-- ── API (server/Jobs.luau) ─────────────────────────────────────────────────

function Cargo.begin(owner: Player, info: Info): Session
	local session: Session = {
		owner = owner,
		info = info,
		load = {},
		held = {},
		loose = {},
		lost = 0,
		deliveredTotal = 0,
		nextVariant = rng:NextInteger(0, 11),
		plan = nil,
		stop = 0,
		built = false,
		greeted = false,
		pile = {},
		walking = {},
		moved = 0,
		hold = 0,
		served = false,
		customers = false,
		nextKid = 0,
		person = nil,
		pilePart = nil,
		pilePrompt = nil,
		props = {},
		propHorses = {},
		car = nil,
		carPrompt = nil,
		shown = {},
		ended = false,
	}
	return session
end

-- Pieces that start in the vehicle (an ice cream truck that starts loaded, the admin tools).
function Cargo.fill(session: Session, count: number)
	for _ = 1, count do
		table.insert(session.load, newPiece(session))
	end
	render(session)
	refresh(session)
end

-- The next stop; the last one's people stay a moment.
function Cargo.setStop(session: Session, plan: Plan)
	if session.plan then
		clearStop(session, true)
	end
	session.stop += 1
	session.plan = plan
	session.built = false
	session.greeted = false
	session.moved = 0
	session.hold = 0
	session.served = false
	session.customers = false
	session.nextKid = 0
	refresh(session)
end

-- Every job tick (Jobs, 0.2 s): follow the car, check the carriers, build the stop, walk the kids, serve.
function Cargo.update(session: Session, dt: number)
	if session.ended then
		return
	end
	local car = Vehicles.get(session.owner)
	if car ~= session.car then
		session.car = car
		attachCar(session)
		render(session)
	end

	-- Dead, gone, sitting: the piece falls where it was.
	local dropped = false
	for player, held in table.clone(session.held) do
		local character = held.character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = rootOf(character)
		local fine = player.Parent ~= nil and player.Character == character and humanoid ~= nil and humanoid.Health > 0 and root ~= nil and humanoid.SeatPart == nil
		if fine and root then
			if root ~= held.root then
				-- The body was rebuilt (the avatar loaded): hold it in the new one.
				held.root = root
				local model = held.piece.model
				if model then
					weldTo(model, root, root.CFrame * carryFrame(model))
				end
			end
			held.last = root.CFrame
		else
			putDown(session, player)
			dropped = true
		end
	end
	if dropped then
		session.info.changed()
	end

	local plan = session.plan
	if not plan then
		return
	end
	local position = ownerPosition(session)
	if not session.built and position and flat(position, plan.park) < Tuning.SpawnDistance then
		build(session)
	end
	if session.built and not session.greeted and position and flat(position, plan.pile) < 45 then
		session.greeted = true
		local handling = plan.mode == "carry" or plan.mode == "lead"
		if plan.stage == "pickup" and handling then
			say(session.person, if plan.needed == 1 then `Over here! One {session.info.piece}, handle it with care.` else `Over here! {plan.needed} {session.info.plural} to load.`)
		elseif plan.stage == "drop" and handling then
			say(session.person, "Finally! Bring it over here.")
		end
	end
	if plan.mode == "board" then
		updateBoard(session, plan, os.clock())
	elseif plan.mode == "serve" then
		updateServe(session, plan, dt)
	end
end

-- Is the current stop done (everything loaded / handed over / served)?
function Cargo.stopDone(session: Session): boolean
	local plan = session.plan
	if not plan then
		return false
	end
	if plan.mode == "serve" then
		return session.served
	end
	if #session.walking > 0 then
		return false
	end
	if plan.stage == "pickup" then
		return session.built and session.moved >= plan.needed and #session.pile == 0 and heldCount(session) == 0 and #session.loose == 0
	end
	return session.moved >= neededNow(session)
end

-- Pieces still somewhere on the way (in the vehicle, in hands, put down, at the current pile, walking).
function Cargo.remaining(session: Session): number
	local pile = #session.pile
	local plan = session.plan
	if plan and plan.stage == "pickup" and not session.built then
		pile = plan.needed
	end
	return #session.load + heldCount(session) + #session.loose + pile + #session.walking
end

-- Bandits at the car carry a piece off (not the kids). Returns the piece's name, or nil.
function Cargo.steal(session: Session): string?
	if session.info.kind == "kid" or #session.load == 0 then
		return nil
	end
	local piece = table.remove(session.load) :: Piece
	if piece.horse then
		Animals.remove(piece.horse)
	end
	session.lost += 1
	render(session)
	refresh(session)
	session.info.changed()
	return session.info.piece
end

-- A wreck: `share` of the load is ruined (at least one piece). The rest moves to the next vehicle. Returns how many.
function Cargo.wreck(session: Session, share: number): number
	if session.info.kind == "kid" or #session.load == 0 then
		return 0
	end
	local count = math.clamp(math.floor(#session.load * share + 0.5), 1, #session.load)
	for _ = 1, count do
		local piece = table.remove(session.load) :: Piece
		if piece.horse then
			Animals.remove(piece.horse)
		end
		session.lost += 1
	end
	render(session)
	refresh(session)
	session.info.changed()
	return count
end

-- For the HUD (Jobs.payload).
function Cargo.status(session: Session): Status
	local plan = session.plan
	local held = session.held[session.owner]
	local handling = plan ~= nil and (plan.mode == "carry" or plan.mode == "lead")
	local progress = 0
	if plan and plan.mode == "serve" then
		progress = math.clamp(session.hold / math.max(plan.hold, 0.1), 0, 1)
	elseif plan and plan.needed > 0 then
		progress = math.clamp(session.moved / plan.needed, 0, 1)
	end
	return {
		inCar = #session.load,
		delivered = session.moved,
		needed = if plan then neededNow(session) else 0,
		total = session.info.total,
		deliveredTotal = session.deliveredTotal,
		lost = session.lost,
		carrying = if held then held.piece.kind else nil,
		person = if plan and plan.person then plan.person.name else nil,
		pile = if plan and handling then plan.pile else nil,
		progress = progress,
	}
end

-- What to do now, for the HUD: (handling, step). handling = drive | carry | lead | board | serve.
function Cargo.step(session: Session): (string, string)
	local plan = session.plan
	if not plan then
		return "drive", ""
	end
	local owner = session.owner
	local held = session.held[owner]
	local car = session.car
	local noun = if car then Vehicles.cargoNoun(car) else "vehicle"
	local circle = if plan.stage == "pickup" then "blue" else "yellow"
	local seatedCar, driving = Vehicles.seatedIn(owner)
	local position = ownerPosition(session)
	local near = position ~= nil and flat(position, plan.park) < Tuning.ApproachDistance
	if not held and not near and heldCount(session) == 0 then
		return "drive", `Drive to the {circle} circle`
	end
	local parked = parkedCar(session) ~= nil
	local mode = plan.mode
	local who = if plan.person then plan.person.name else "the receiver"
	local piece = session.info.piece
	if mode == "serve" then
		if parked and driving then
			return mode, "Hold still while the kids buy ice cream"
		end
		return mode, `Park in the {circle} circle and hold still`
	elseif mode == "board" then
		if not parked then
			return mode, `Park in the {circle} circle`
		end
		local needed = neededNow(session)
		if plan.stage == "pickup" then
			return mode, `Wait while the kids get on ({session.moved}/{needed})`
		end
		return mode, `Wait while the kids get off ({session.moved}/{needed})`
	end
	local horse = session.info.kind == "horse"
	if held then
		if plan.stage == "pickup" or session.moved >= neededNow(session) then
			return mode, if horse then `Lead the horse into the {noun} (E)` else `Load it into the back of the {noun} (E)`
		end
		return mode, if horse then `Lead the horse to {who} (E)` else `Carry it to {who} (E)`
	end
	if driving and not parked then
		return mode, `Park in the {circle} circle`
	end
	if #session.loose > 0 then
		return mode, if horse then "Catch the horse you let go (E)" else `Pick up the {piece} you put down (E)`
	end
	if plan.stage == "pickup" then
		if #session.pile > 0 or not session.built then
			if seatedCar then
				return mode, if horse then `Get out and take a horse from {who} (E)` else `Get out and pick up {article(piece)} (E)`
			end
			return mode, if horse then `Take a horse from {who} (E)` else `Pick up {article(piece)} from {who} (E)`
		end
		return mode, "Wait for your crew to load"
	end
	if #session.load > 0 and session.moved < neededNow(session) then
		if seatedCar then
			return mode, if horse then `Get out and lead a horse out of the {noun} (E)` else `Get out and take {article(piece)} out of the {noun} (E)`
		end
		return mode, if horse then `Lead a horse out of the {noun} (E)` else `Take {article(piece)} out of the {noun} (E)`
	end
	return mode, "Wait for your crew"
end

-- Is anybody of the job handling cargo on foot at the current stop (the enemies come on foot then)?
function Cargo.onFoot(session: Session): boolean
	local plan = session.plan
	if not plan or (plan.mode ~= "carry" and plan.mode ~= "lead") then
		return false
	end
	if heldCount(session) > 0 then
		return true
	end
	local position = ownerPosition(session)
	return position ~= nil and Vehicles.seatedIn(session.owner) == nil and flat(position, plan.park) < Tuning.ApproachDistance
end

-- The admin tools: the current stop is done at once (loaded / handed over / served).
function Cargo.adminFinish(session: Session): boolean
	local plan = session.plan
	if not plan or session.ended then
		return false
	end
	for player in table.clone(session.held) do
		local held = clearHeld(session, player)
		if held then
			if held.piece.horse then
				Animals.lead(held.piece.horse, nil)
			end
			if held.piece.model then
				held.piece.model:Destroy()
				held.piece.model = nil
			end
			table.insert(session.load, held.piece)
		end
	end
	for _, loose in session.loose do
		loose.prompt:Destroy()
		if loose.handle then
			loose.handle:Destroy()
		end
		if loose.piece.model then
			loose.piece.model:Destroy()
			loose.piece.model = nil
		end
		table.insert(session.load, loose.piece)
	end
	table.clear(session.loose)
	if plan.mode == "serve" then
		session.hold = plan.hold
		session.served = true
		while #session.load > plan.keep do
			table.remove(session.load)
			session.deliveredTotal += 1
		end
		session.moved = plan.needed
	elseif plan.stage == "pickup" then
		build(session)
		for _, piece in session.pile do
			removeNpc(piece.npc)
			piece.npc = nil
			if piece.model then
				piece.model:Destroy()
				piece.model = nil
			end
			table.insert(session.load, piece)
		end
		for _, piece in session.walking do
			removeNpc(piece.npc)
			piece.npc = nil
			table.insert(session.load, piece)
		end
		table.clear(session.pile)
		table.clear(session.walking)
		session.moved = plan.needed
	else
		for _, piece in session.walking do
			removeNpc(piece.npc)
			piece.npc = nil
			session.moved += 1
			session.deliveredTotal += 1
		end
		table.clear(session.walking)
		while session.moved < plan.needed and #session.load > 0 do
			local piece = table.remove(session.load) :: Piece
			if piece.horse then
				Animals.remove(piece.horse)
			end
			session.moved += 1
			session.deliveredTotal += 1
		end
		session.moved = math.max(session.moved, neededNow(session))
	end
	render(session)
	refresh(session)
	session.info.changed()
	return true
end

-- The job is over: everything goes (the last stop's people stay a moment when `linger`).
function Cargo.finish(session: Session, linger: boolean?)
	if session.ended then
		return
	end
	for player in table.clone(session.held) do
		local held = clearHeld(session, player)
		if held then
			if held.piece.horse then
				Animals.lead(held.piece.horse, nil)
				Animals.remove(held.piece.horse)
			end
			if held.piece.model then
				held.piece.model:Destroy()
			end
		end
	end
	session.ended = true
	for _, loose in session.loose do
		loose.prompt:Destroy()
		if loose.handle then
			loose.handle:Destroy()
		end
		if loose.piece.horse then
			Animals.remove(loose.piece.horse)
		end
		if loose.piece.model then
			loose.piece.model:Destroy()
		end
	end
	table.clear(session.loose)
	for _, piece in session.load do
		if piece.horse then
			Animals.remove(piece.horse)
		end
	end
	table.clear(session.load)
	for _, model in session.shown do
		model:Destroy()
	end
	table.clear(session.shown)
	if session.carPrompt then
		session.carPrompt:Destroy()
		session.carPrompt = nil
	end
	local car = session.car
	if car and car.model.Parent then
		car.model:SetAttribute("CargoCount", 0)
		car.model:SetAttribute("CargoKind", nil)
	end
	clearStop(session, linger == true)
	session.plan = nil
end

function Cargo.start()
	local existing = workspace:FindFirstChild("Cargo")
	if existing then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = "Cargo"
		created.Parent = workspace
		folder = created
	end
end

return Cargo
