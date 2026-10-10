--!strict
-- 6.22, the cargo's looks (factored out of server/Cargo.luau unchanged, so the client can draw them too): every piece
-- of cargo built as a model at the origin, the bottom centre its pivot, the front -Z, the first part the main one.
-- server/Cargo.luau builds every piece in the world with it; client/ItemModel.luau (through shared/ItemLooks.luau)
-- draws the same model in BAG & ITEMS and the bottom bar. Nothing here runs per frame or knows a player.
--
--   CargoLooks.build(look, variant)   a piece of `look` (Config.Cargo.Kinds looks, the storefronts' looks; an unknown
--                                     look is a plain crate), `variant` its colour / size pick; a light look
--                                     (Config.Cargo.LightLooks) at its real size (LightScale, LookScale). Its Height
--                                     and Depth attributes say how big it is.
--   CargoLooks.Looks                  every look it draws a model of its own for (the rest are a crate)
--   CargoLooks.UPRIGHT                a cylinder standing up (a part's turn)

local Config = require(script.Parent.Config)

local Tuning = Config.Cargo
local CargoLooks = {}

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
CargoLooks.UPRIGHT = UPRIGHT

-- The missions' cargo (3.0, Config.Cargo.Kinds), built into `model` like buildLook's (the bottom centre is the pivot,
-- the front is -Z; the first part is the main one). False for a look it does not know.
local function missionLook(model: Model, look: string, variant: number): boolean
	local black = Color3.new(0, 0, 0)
	local function block(name: string, size: Vector3, at: Vector3, color: Color3, material: Enum.Material): Part
		return newPart(model, name, size, CFrame.new(at), color, material)
	end
	-- A cylinder `length` long: standing up, or lying along Z (a disc facing the front, a stick front to back) or X.
	local function cylinder(name: string, length: number, diameter: number, at: Vector3, color: Color3, material: Enum.Material, axis: string?): Part
		local turn = if axis == "z" then CFrame.Angles(0, math.rad(90), 0) elseif axis == "x" then CFrame.identity else UPRIGHT
		local p = newPart(model, name, Vector3.new(length, diameter, diameter), CFrame.new(at) * turn, color, material)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	local function ball(name: string, diameter: number, at: Vector3, color: Color3, material: Enum.Material): Part
		local p = block(name, Vector3.new(diameter, diameter, diameter), at, color, material)
		p.Shape = Enum.PartType.Ball
		return p
	end

	if look == "water" then
		-- A big water jug: clear plastic, the water inside, a blue cap.
		local body = cylinder("Body", 1.9, 1.5, Vector3.new(0, 0.95, 0), rgb(176, 214, 240), Enum.Material.Glass)
		body.Transparency = 0.4
		cylinder("Water", 1.55, 1.34, Vector3.new(0, 0.82, 0), rgb(70, 150, 230), Enum.Material.SmoothPlastic).Transparency = 0.2
		for _, y in { 0.45, 1.45 } do
			cylinder("Ring", 0.12, 1.56, Vector3.new(0, y, 0), rgb(150, 196, 232), Enum.Material.Glass).Transparency = 0.3
		end
		cylinder("Neck", 0.35, 0.6, Vector3.new(0, 2.07, 0), rgb(176, 214, 240), Enum.Material.Glass).Transparency = 0.3
		cylinder("Cap", 0.22, 0.7, Vector3.new(0, 2.33, 0), rgb(40, 90, 200), Enum.Material.SmoothPlastic)
	elseif look == "generator" then
		-- An orange generator in a black tube frame: the fuel tank on top, the control panel at the front.
		local frame = rgb(36, 36, 40)
		local body = block("Body", Vector3.new(2.5, 1.4, 1.6), Vector3.new(0, 0.95, 0), rgb(232, 132, 32), Enum.Material.SmoothPlastic)
		block("Tank", Vector3.new(1.6, 0.42, 1.2), Vector3.new(-0.2, 1.86, 0), rgb(220, 120, 26), Enum.Material.SmoothPlastic)
		cylinder("FuelCap", 0.14, 0.4, Vector3.new(0.3, 2.13, 0), frame, Enum.Material.Metal)
		for _, z in { -0.85, 0.85 } do
			block("Skid", Vector3.new(2.9, 0.22, 0.22), Vector3.new(0, 0.11, z), frame, Enum.Material.Metal)
			block("Rail", Vector3.new(2.9, 0.18, 0.18), Vector3.new(0, 2.05, z), frame, Enum.Material.Metal)
			for _, x in { -1.36, 1.36 } do
				block("Post", Vector3.new(0.18, 2.0, 0.18), Vector3.new(x, 1.08, z), frame, Enum.Material.Metal)
			end
		end
		block("Panel", Vector3.new(0.9, 0.7, 0.05), Vector3.new(0.6, 0.95, -0.82), frame, Enum.Material.Metal)
		block("Socket", Vector3.new(0.2, 0.2, 0.05), Vector3.new(0.4, 0.95, -0.85), rgb(240, 240, 235), Enum.Material.SmoothPlastic)
		block("Lamp", Vector3.new(0.14, 0.14, 0.05), Vector3.new(0.85, 1.15, -0.85), rgb(90, 255, 90), Enum.Material.Neon)
		cylinder("Exhaust", 0.6, 0.28, Vector3.new(-1.45, 1.35, 0.4), rgb(120, 120, 126), Enum.Material.Metal, "x")
		stencil(body, "POWER", frame, { Enum.NormalId.Back })
	elseif look == "battery" then
		-- A heavy battery pack: the terminals, a yellow band, 12V.
		local body = block("Body", Vector3.new(2.0, 1.3, 1.3), Vector3.new(0, 0.65, 0), rgb(36, 38, 42), Enum.Material.SmoothPlastic)
		block("Top", Vector3.new(2.05, 0.15, 1.35), Vector3.new(0, 1.37, 0), rgb(62, 64, 70), Enum.Material.SmoothPlastic)
		block("Band", Vector3.new(2.02, 0.2, 1.32), Vector3.new(0, 1.15, 0), rgb(240, 200, 40), Enum.Material.SmoothPlastic)
		cylinder("Plus", 0.28, 0.34, Vector3.new(-0.62, 1.58, -0.3), rgb(210, 40, 36), Enum.Material.Metal)
		cylinder("Minus", 0.28, 0.34, Vector3.new(0.62, 1.58, -0.3), rgb(150, 150, 156), Enum.Material.Metal)
		block("Handle", Vector3.new(1.0, 0.12, 0.25), Vector3.new(0, 1.62, 0.3), rgb(24, 24, 26), Enum.Material.SmoothPlastic)
		stencil(body, "12V", rgb(240, 200, 40), FRONT_BACK)
	elseif look == "tnt" then
		-- A dynamite crate: red sticks bundled on the lid, a fuse, DANGER.
		local wood = rgb(150, 104, 62)
		local body = block("Body", Vector3.new(2.2, 1.5, 1.5), Vector3.new(0, 0.75, 0), wood, Enum.Material.WoodPlanks)
		local dark = wood:Lerp(black, 0.35)
		for _, y in { 0.12, 1.38 } do
			block("Rim", Vector3.new(2.3, 0.25, 1.6), Vector3.new(0, y, 0), dark, Enum.Material.Wood)
		end
		for n, z in { -0.36, 0, 0.36 } do
			cylinder("Stick", 1.5, 0.34, Vector3.new(0.05 * n, 1.68, z), rgb(200, 36, 30), Enum.Material.SmoothPlastic, "x")
		end
		block("Band", Vector3.new(0.22, 0.4, 1.14), Vector3.new(0, 1.7, 0), rgb(30, 30, 30), Enum.Material.Fabric)
		block("Fuse", Vector3.new(0.5, 0.08, 0.08), Vector3.new(1.0, 1.82, 0), rgb(40, 34, 30), Enum.Material.Fabric)
		stencil(body, "TNT", rgb(210, 30, 24), FRONT_BACK)
		stencil(body, "DANGER", rgb(210, 30, 24), { Enum.NormalId.Left, Enum.NormalId.Right })
	elseif look == "documents" then
		-- A briefcase with gold clasps and a TOP SECRET tag.
		local leather = if variant % 2 == 0 then rgb(74, 48, 30) else rgb(32, 32, 36)
		local dark = leather:Lerp(black, 0.35)
		block("Body", Vector3.new(2.0, 1.4, 0.55), Vector3.new(0, 0.7, 0), leather, Enum.Material.Leather)
		block("Seam", Vector3.new(2.04, 0.08, 0.59), Vector3.new(0, 1.12, 0), dark, Enum.Material.Leather)
		block("Handle", Vector3.new(0.72, 0.14, 0.18), Vector3.new(0, 1.62, 0), dark, Enum.Material.Leather)
		for _, x in { -0.32, 0.32 } do
			block("Grip", Vector3.new(0.12, 0.24, 0.18), Vector3.new(x, 1.5, 0), dark, Enum.Material.Leather)
		end
		for _, x in { -0.65, 0.65 } do
			block("Clasp", Vector3.new(0.22, 0.16, 0.05), Vector3.new(x, 1.12, -0.3), rgb(222, 180, 60), Enum.Material.Metal)
		end
		local tag = block("Tag", Vector3.new(0.8, 0.42, 0.03), Vector3.new(0.45, 0.55, -0.29), rgb(240, 236, 220), Enum.Material.SmoothPlastic)
		stencil(tag, "TOP SECRET", rgb(200, 30, 30), { Enum.NormalId.Front })
	elseif look == "electronics" then
		-- A grey crate of radio parts: a circuit board at the front, a blinking light, an antenna.
		local body = block("Body", Vector3.new(2.2, 1.5, 1.6), Vector3.new(0, 0.75, 0), rgb(112, 120, 112), Enum.Material.Metal)
		block("Lid", Vector3.new(2.3, 0.2, 1.7), Vector3.new(0, 1.6, 0), rgb(82, 88, 82), Enum.Material.Metal)
		block("Board", Vector3.new(1.1, 0.7, 0.05), Vector3.new(-0.4, 0.8, -0.82), rgb(40, 124, 62), Enum.Material.SmoothPlastic)
		for n = 0, 2 do
			block("Chip", Vector3.new(0.2, 0.16, 0.04), Vector3.new(-0.75 + n * 0.32, 0.9, -0.86), rgb(26, 26, 28), Enum.Material.SmoothPlastic)
		end
		block("Led", Vector3.new(0.14, 0.14, 0.04), Vector3.new(0.6, 1.2, -0.82), rgb(255, 64, 40), Enum.Material.Neon)
		cylinder("Knob", 0.12, 0.3, Vector3.new(0.6, 0.7, -0.84), rgb(30, 30, 32), Enum.Material.SmoothPlastic, "z")
		block("Antenna", Vector3.new(0.08, 0.9, 0.08), Vector3.new(0.85, 2.15, 0.5), rgb(40, 40, 44), Enum.Material.Metal)
		stencil(body, "RADIO PARTS", rgb(240, 240, 230), { Enum.NormalId.Back })
	elseif look == "weapons" then
		-- A long hard case (rifles inside), army green, the latches at the back.
		local body = block("Body", Vector3.new(3.2, 0.9, 1.3), Vector3.new(0, 0.45, 0), rgb(42, 46, 36), Enum.Material.SmoothPlastic)
		block("Lid", Vector3.new(3.24, 0.12, 1.34), Vector3.new(0, 0.62, 0), rgb(58, 64, 50), Enum.Material.SmoothPlastic)
		for _, x in { -1.0, 0, 1.0 } do
			block("Latch", Vector3.new(0.25, 0.25, 0.06), Vector3.new(x, 0.6, 0.68), rgb(150, 150, 156), Enum.Material.Metal)
		end
		block("Handle", Vector3.new(0.8, 0.12, 0.2), Vector3.new(0, 0.97, 0), rgb(20, 20, 22), Enum.Material.SmoothPlastic)
		for _, x in { -0.5, 0.5 } do
			block("Grip", Vector3.new(0.12, 0.3, 0.2), Vector3.new(x, 0.8, 0), rgb(20, 20, 22), Enum.Material.SmoothPlastic)
		end
		stencil(body, "ARMY", rgb(222, 204, 124), { Enum.NormalId.Front })
	elseif look == "painting" then
		-- A framed painting (hills and a sun), cardboard corners against the knocks.
		local canvases = { rgb(90, 140, 200), rgb(220, 150, 90), rgb(120, 90, 160) }
		block("Frame", Vector3.new(2.6, 2.0, 0.25), Vector3.new(0, 1.0, 0), rgb(200, 160, 62), Enum.Material.Wood)
		block("Canvas", Vector3.new(2.2, 1.6, 0.05), Vector3.new(0, 1.0, -0.14), canvases[variant % #canvases + 1], Enum.Material.SmoothPlastic)
		block("Hill", Vector3.new(2.2, 0.5, 0.04), Vector3.new(0, 0.45, -0.17), rgb(70, 130, 64), Enum.Material.SmoothPlastic)
		block("Hill", Vector3.new(1.0, 0.75, 0.04), Vector3.new(-0.55, 0.55, -0.18), rgb(56, 110, 54), Enum.Material.SmoothPlastic)
		cylinder("Sun", 0.04, 0.45, Vector3.new(0.6, 1.4, -0.18), rgb(250, 212, 80), Enum.Material.SmoothPlastic, "z")
		for _, x in { -1.2, 1.2 } do
			for _, y in { 0.15, 1.85 } do
				block("Corner", Vector3.new(0.42, 0.42, 0.36), Vector3.new(x, y, 0), rgb(196, 158, 108), Enum.Material.Cardboard)
			end
		end
	elseif look == "mail" then
		-- A canvas mail sack, letters sticking out of the top.
		local canvas = if variant % 2 == 0 then rgb(70, 92, 142) else rgb(150, 140, 110)
		local body = block("Body", Vector3.new(1.7, 1.6, 1.2), Vector3.new(0, 0.8, 0), canvas, Enum.Material.Fabric)
		block("Top", Vector3.new(1.2, 0.5, 0.85), Vector3.new(0, 1.85, 0), canvas, Enum.Material.Fabric)
		block("Tie", Vector3.new(1.25, 0.14, 0.9), Vector3.new(0, 1.7, 0), rgb(150, 110, 60), Enum.Material.Fabric)
		for n, x in { -0.25, 0.2 } do
			newPart(model, "Letter", Vector3.new(0.6, 0.42, 0.04), CFrame.new(x, 2.18, 0.05 * n) * CFrame.Angles(0, 0, math.rad(if n == 1 then 14 else -10)), rgb(245, 240, 226), Enum.Material.SmoothPlastic)
		end
		stencil(body, "MAIL", rgb(240, 240, 240), FRONT_BACK)
	elseif look == "tires" then
		-- Two or three tires stacked flat.
		for n = 0, 1 + variant % 2 do
			local y = 0.3 + n * 0.62
			cylinder("Tire", 0.6, 2.0, Vector3.new(0, y, 0), rgb(30, 30, 32), Enum.Material.Rubber)
			cylinder("Rim", 0.62, 0.95, Vector3.new(0, y, 0), rgb(176, 176, 182), Enum.Material.Metal)
		end
	elseif look == "plants" then
		-- A tray of seedlings in dark soil.
		block("Tray", Vector3.new(2.2, 0.4, 1.5), Vector3.new(0, 0.2, 0), rgb(56, 48, 40), Enum.Material.SmoothPlastic)
		block("Soil", Vector3.new(2.0, 0.08, 1.3), Vector3.new(0, 0.42, 0), rgb(82, 58, 38), Enum.Material.Ground)
		local greens = { rgb(84, 160, 70), rgb(110, 180, 80), rgb(70, 140, 60) }
		for i = 0, 2 do
			for j = 0, 1 do
				local x, z = -0.7 + i * 0.7, -0.35 + j * 0.7
				block("Stem", Vector3.new(0.08, 0.5, 0.08), Vector3.new(x, 0.7, z), rgb(70, 120, 50), Enum.Material.Grass)
				ball("Leaves", 0.5, Vector3.new(x, 1.0, z), greens[(i + j + variant) % #greens + 1], Enum.Material.Grass)
			end
		end
	elseif look == "survivor" then
		-- A survivor in the vehicle: a dirty jacket, a beanie, the backpack they never put down.
		local jackets = { rgb(104, 92, 66), rgb(88, 96, 74), rgb(120, 84, 60), rgb(76, 82, 92) }
		local skins = { rgb(255, 214, 180), rgb(200, 150, 110), rgb(140, 95, 65), rgb(240, 190, 150) }
		block("Body", Vector3.new(1.5, 1.4, 0.8), Vector3.new(0, 0.7, 0), jackets[variant % #jackets + 1], Enum.Material.Fabric)
		ball("Head", 1.0, Vector3.new(0, 1.95, 0), skins[variant % #skins + 1], Enum.Material.SmoothPlastic)
		block("Beanie", Vector3.new(1.02, 0.4, 1.02), Vector3.new(0, 2.33, 0.03), rgb(70, 64, 58), Enum.Material.Fabric)
		block("Backpack", Vector3.new(1.1, 1.1, 0.5), Vector3.new(0, 0.85, 0.62), rgb(62, 82, 52), Enum.Material.Fabric)
		block("Dirt", Vector3.new(0.5, 0.3, 0.03), Vector3.new(-0.3, 0.6, -0.41), rgb(70, 56, 40), Enum.Material.Fabric)
	elseif look == "pallet" then
		-- 4.0: a wooden pallet with eight boxes in shrink wrap, about 4 × 4 × 4. A pallet jack's forks go in from the
		-- front between the stringers. The wrap is the main part (you walk round it, the prompt sits on it).
		local wrap = block("Body", Vector3.new(3.9, 3.2, 3.9), Vector3.new(0, 2.24, 0), rgb(214, 226, 232), Enum.Material.SmoothPlastic)
		wrap.Transparency = 0.55
		wrap.Reflectance = 0.15
		local wood = rgb(176, 136, 88)
		for _, x in { -1.75, 0, 1.75 } do
			block("Stringer", Vector3.new(0.4, 0.5, 4), Vector3.new(x, 0.25, 0), wood:Lerp(black, 0.15), Enum.Material.WoodPlanks)
		end
		for n = 0, 4 do
			block("Board", Vector3.new(4, 0.12, 0.66), Vector3.new(0, 0.56, -1.6 + n * 0.8), wood, Enum.Material.WoodPlanks)
		end
		local colors = { rgb(196, 158, 108), rgb(60, 110, 170), rgb(90, 150, 80), rgb(200, 70, 50) }
		local color = colors[variant % #colors + 1]
		local cardboard = rgb(196, 158, 108)
		for layer = 0, 1 do
			for i, x in { -0.96, 0.96 } do
				for j, z in { -0.96, 0.96 } do
					block("Box", Vector3.new(1.86, 1.55, 1.86), Vector3.new(x, 1.41 + layer * 1.57, z), if (i + j + layer) % 2 == 0 then color else cardboard, Enum.Material.Cardboard)
				end
			end
		end
		for _, x in { -1, 1 } do
			block("Strap", Vector3.new(0.14, 3.24, 3.96), Vector3.new(x, 2.24, 0), rgb(40, 40, 44), Enum.Material.Fabric)
		end
		local sheet = block("Sheet", Vector3.new(1.4, 1, 0.04), Vector3.new(0.9, 2.6, -1.98), rgb(245, 245, 240), Enum.Material.SmoothPlastic)
		stencil(sheet, "FREIGHT", rgb(30, 30, 34), { Enum.NormalId.Front })
	-- 5.3, the storefronts' own pieces (Config.Jobs.Businesses looks).
	elseif look == "burger" then
		-- Last Bite's paper bag, folded over at the top, a burger sticker.
		local paper = rgb(176, 132, 84)
		local body = block("Body", Vector3.new(1.3, 1.5, 0.9), Vector3.new(0, 0.75, 0), paper, Enum.Material.Cardboard)
		block("Fold", Vector3.new(1.32, 0.3, 0.6), Vector3.new(0, 1.62, 0), paper:Lerp(black, 0.15), Enum.Material.Cardboard)
		cylinder("Sticker", 0.04, 0.6, Vector3.new(0, 0.85, -0.46), rgb(220, 60, 40), Enum.Material.SmoothPlastic, "z")
		stencil(body, "LAST BITE", rgb(250, 230, 160), { Enum.NormalId.Back })
	elseif look == "noodles" then
		-- Two white take-out boxes with wire handles, Wok Dead's red mark.
		for n = 0, 1 do
			local y = 0.4 + n * 0.82
			block("Box", Vector3.new(1.0 - n * 0.1, 0.8, 0.9 - n * 0.1), Vector3.new(0, y, 0), rgb(246, 244, 238), Enum.Material.SmoothPlastic)
			block("Mark", Vector3.new(0.4, 0.4, 0.03), Vector3.new(0, y, -0.46 + n * 0.05), rgb(200, 36, 36), Enum.Material.SmoothPlastic)
		end
		block("Handle", Vector3.new(0.06, 0.4, 0.7), Vector3.new(0, 1.85, 0), rgb(170, 170, 176), Enum.Material.Metal)
	elseif look == "pastry" then
		-- A paper pastry bag, a croissant peeking out.
		block("Body", Vector3.new(1.1, 1.3, 0.7), Vector3.new(0, 0.65, 0), rgb(236, 226, 206), Enum.Material.Cardboard)
		block("Band", Vector3.new(1.12, 0.25, 0.72), Vector3.new(0, 0.9, 0), rgb(46, 110, 70), Enum.Material.SmoothPlastic)
		local croissant = newPart(model, "Croissant", Vector3.new(0.9, 0.35, 0.35), CFrame.new(0, 1.42, 0) * CFrame.Angles(0, 0, math.rad(12)), rgb(214, 156, 74), Enum.Material.SmoothPlastic)
		croissant.Shape = Enum.PartType.Cylinder
	elseif look == "newspaper" then
		-- The morning paper, rolled and held with a rubber band.
		cylinder("Body", 1.3, 0.42, Vector3.new(0, 0.21, 0), rgb(232, 230, 222), Enum.Material.SmoothPlastic, "x")
		cylinder("Band", 0.08, 0.45, Vector3.new(0, 0.21, 0), rgb(200, 50, 40), Enum.Material.SmoothPlastic, "x")
		block("Headline", Vector3.new(0.5, 0.1, 0.02), Vector3.new(0.35, 0.3, -0.2), rgb(30, 30, 32), Enum.Material.SmoothPlastic)
	elseif look == "bouquet" then
		-- Flowers in paper: a cone of kraft paper, the blooms on top.
		block("Paper", Vector3.new(0.9, 1.4, 0.9), Vector3.new(0, 0.7, 0), rgb(214, 186, 140), Enum.Material.Cardboard)
		block("Ribbon", Vector3.new(0.94, 0.15, 0.94), Vector3.new(0, 0.55, 0), rgb(220, 70, 120), Enum.Material.Fabric)
		local blooms = { rgb(230, 60, 80), rgb(250, 220, 70), rgb(240, 140, 190), rgb(250, 250, 245) }
		for n, at in { Vector3.new(-0.25, 1.6, 0), Vector3.new(0.25, 1.65, 0.1), Vector3.new(0, 1.75, -0.2), Vector3.new(0.05, 1.6, 0.3) } do
			ball("Bloom", 0.5, at, blooms[(n + variant) % #blooms + 1], Enum.Material.SmoothPlastic)
		end
		ball("Leaves", 0.9, Vector3.new(0, 1.45, 0), rgb(70, 130, 60), Enum.Material.Grass)
	elseif look == "icecream" then
		-- Frosty's insulated bag, a tub of ice cream on top of it.
		local body = block("Body", Vector3.new(1.5, 1.1, 1.1), Vector3.new(0, 0.55, 0), rgb(60, 140, 220), Enum.Material.Fabric)
		block("Zip", Vector3.new(1.52, 0.08, 1.12), Vector3.new(0, 1.0, 0), rgb(240, 240, 244), Enum.Material.Fabric)
		cylinder("Tub", 0.5, 0.8, Vector3.new(0, 1.35, 0), rgb(250, 236, 214), Enum.Material.SmoothPlastic)
		cylinder("Lid", 0.08, 0.84, Vector3.new(0, 1.62, 0), rgb(240, 120, 160), Enum.Material.SmoothPlastic)
		stencil(body, "FROSTY'S", rgb(255, 255, 255), { Enum.NormalId.Back })
	elseif look == "gadget" then
		-- Volt's printed box: a radio on the front.
		local body = block("Body", Vector3.new(1.8, 1.3, 1.2), Vector3.new(0, 0.65, 0), rgb(40, 50, 64), Enum.Material.Cardboard)
		block("Picture", Vector3.new(1.0, 0.7, 0.03), Vector3.new(-0.2, 0.7, -0.61), rgb(230, 200, 60), Enum.Material.SmoothPlastic)
		block("Bolt", Vector3.new(0.25, 0.5, 0.03), Vector3.new(0.6, 0.75, -0.61), rgb(250, 220, 60), Enum.Material.Neon)
		stencil(body, "VOLT · FRAGILE", rgb(250, 220, 60), { Enum.NormalId.Back })
	else
		return false
	end
	return true
end

-- A piece of cargo built at the origin: the bottom centre is the pivot, the front is -Z.
function CargoLooks.build(look: string, variant: number): Model
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
		-- A strongbox (the bank's gold, the cash transport's sacks of cash ride in these).
		local body = block("Body", Vector3.new(2, 1.2, 1.4), Vector3.new(0, 0.6, 0), rgb(60, 62, 66), Enum.Material.DiamondPlate)
		block("Trim", Vector3.new(2.05, 0.15, 1.45), Vector3.new(0, 1.2, 0), rgb(230, 180, 50), Enum.Material.Metal)
		block("Lock", Vector3.new(0.4, 0.4, 0.05), Vector3.new(0, 0.8, -0.72), rgb(230, 180, 50), Enum.Material.Metal)
		stencil(body, "$", rgb(230, 180, 50), { Enum.NormalId.Back })
	elseif look == "patient" then
		-- The patient on a stretcher under a blanket, the head toward the front (the ambulance's stretcher bay).
		local metal = rgb(186, 190, 196)
		local skins = { rgb(255, 214, 180), rgb(200, 150, 110), rgb(140, 95, 65), rgb(240, 190, 150) }
		block("Body", Vector3.new(2.2, 0.35, 5.2), Vector3.new(0, 1.3, 0), rgb(245, 245, 245), Enum.Material.SmoothPlastic)
		block("Frame", Vector3.new(2.3, 0.15, 5.4), Vector3.new(0, 1.05, 0), metal, Enum.Material.Metal)
		for _, z in { -2.2, 2.2 } do
			block("Leg", Vector3.new(1.9, 0.75, 0.15), Vector3.new(0, 0.6, z), metal, Enum.Material.Metal)
			for _, x in { -0.85, 0.85 } do
				local wheel = block("Wheel", Vector3.new(0.4, 0.4, 0.4), Vector3.new(x, 0.2, z), rgb(40, 40, 44), Enum.Material.SmoothPlastic)
				wheel.Shape = Enum.PartType.Ball
			end
		end
		block("Blanket", Vector3.new(2.0, 0.5, 3.6), Vector3.new(0, 1.72, 0.6), rgb(70, 120, 190), Enum.Material.Fabric)
		for _, size in { Vector3.new(0.8, 0.04, 0.25), Vector3.new(0.25, 0.04, 0.8) } do
			block("Cross", size, Vector3.new(0, 1.98, 0.6), rgb(210, 30, 30), Enum.Material.SmoothPlastic)
		end
		block("Pillow", Vector3.new(1.5, 0.3, 0.9), Vector3.new(0, 1.62, -2.0), rgb(250, 250, 250), Enum.Material.Fabric)
		local head = block("Head", Vector3.new(0.9, 0.9, 0.9), Vector3.new(0, 2.05, -1.9), skins[variant % #skins + 1], Enum.Material.SmoothPlastic)
		head.Shape = Enum.PartType.Ball
		local bandage = newPart(model, "Bandage", Vector3.new(0.3, 0.95, 0.95), CFrame.new(0, 2.25, -1.9) * UPRIGHT, rgb(250, 250, 248), Enum.Material.Fabric)
		bandage.Shape = Enum.PartType.Cylinder
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
	elseif not missionLook(model, look, variant) then
		crate(Vector3.new(2.2, 2, 2.2), rgb(163, 120, 74))
	end

	local main = model:FindFirstChildWhichIsA("BasePart")
	if main then
		model.PrimaryPart = main
		main.PivotOffset = main.CFrame:Inverse()
		-- 6.7: a light piece at its real size (about the pivot: the bottom centre stays at the origin)
		local scale = if Tuning.LightLooks[look] then Tuning.LookScale[look] or Tuning.LightScale else 1
		if scale ~= 1 then
			model:ScaleTo(scale)
		end
	end
	local size = model:GetExtentsSize()
	model:SetAttribute("Height", size.Y)
	model:SetAttribute("Depth", size.Z)
	return model
end

-- (the looks with a model of their own: buildLook's and missionLook's branches above)
CargoLooks.Looks = {
	crate = true,
	tools = true,
	ammo = true,
	sack = true,
	bread = true,
	barrel = true,
	icebox = true,
	vaccine = true,
	sample = true,
	soup = true,
	parcel = true,
	groceries = true,
	medicine = true,
	pizza = true,
	gold = true,
	patient = true,
	cake = true,
	furniture = true,
	kid = true,
	water = true,
	generator = true,
	battery = true,
	tnt = true,
	documents = true,
	electronics = true,
	weapons = true,
	painting = true,
	mail = true,
	tires = true,
	plants = true,
	survivor = true,
	pallet = true,
	burger = true,
	noodles = true,
	pastry = true,
	newspaper = true,
	bouquet = true,
	icecream = true,
	gadget = true,
} :: { [string]: boolean }

return CargoLooks
