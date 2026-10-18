--!strict
-- 8.3 SANDBOX: what the real server/VanPaint.luau needs on top of tests/runtime/CollectionRuntime.luau (players, the
-- DataStore, the clock, Net) for tests/vanpaint_runtime_test.luau (tests/run_tests.py builds VanPaintServer.luau with
-- these in place of `game`, `Instance` and server/Vehicles.luau):
--   * a CollectionService that records the tags (P.tags: tag → { instance → true });
--   * Instance.new whose ProximityPrompt has a Triggered signal (the test presses it: prompt.Triggered:Fire(player));
--   * the vans: a fake Vehicles (get, onStyle: the hook VanPaint wraps) over Car records whose model has what the paint
--     touches and what it must leave alone (P.van(player, ground)): the chassis (colliding, the PrimaryPart), the body
--     that sways (BodyRoot), a hull box and a seat (colliding), the parts look's panels (car.paintParts: FleetFinish
--     "paint", and the sliding door without one), its stripes (FleetFinish "stripe"), glass, the ZDC logo's label
--     (its letters in the stripe's ink) and the company's name (trim ink), and the owner's Blender look's pieces (the
--     folder "SprinterMesh": Body_paint, Body_stripe, Body_glass with their factory look, as server/SprinterMesh.luau
--     leaves them).
local E = require("./CollectionRuntime") :: any
local Mock = E.Mock

local P: any = { E = E, Mock = Mock }

P.tags = {} -- tag → { [instance] = true }
local collection = {
	AddTag = function(_self: any, instance: any, tag: string)
		P.tags[tag] = P.tags[tag] or {}
		P.tags[tag][instance] = true
	end,
	RemoveTag = function(_self: any, instance: any, tag: string)
		if P.tags[tag] then
			P.tags[tag][instance] = nil
		end
	end,
	HasTag = function(_self: any, instance: any, tag: string): boolean
		return P.tags[tag] ~= nil and P.tags[tag][instance] == true
	end,
}
P.game = setmetatable({
	GetService = function(_self: any, name: string): any
		if name == "CollectionService" then
			return collection
		end
		return E.game:GetService(name)
	end,
}, { __index = E.game })

P.Instance = {
	new = function(class: string): any
		local obj = E.Instance.new(class)
		if class == "ProximityPrompt" then
			obj.Triggered = E.signal()
		end
		return obj
	end,
}

-- ── The vans ───────────────────────────────────────────────────────────────

local V, C = Mock.Vector3.new, Mock.CFrame.new
P.cars = {} -- player → Car
P.styled = {} -- the cars the hook before VanPaint's saw
P.Vehicles = {}
P.Vehicles.onStyle = function(car: any)
	table.insert(P.styled, car)
end
function P.Vehicles.get(player: any): any
	local car = P.cars[player]
	return if car and not car.wrecked then car else nil
end

local function part(model: any, name: string, size: any, at: any, color: any, props: { [string]: any }?): any
	local p = Mock.Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = at
	p.Color = color
	p.Material = "SmoothPlastic"
	for key, value in props or {} do
		p[key] = value
	end
	p.Parent = model
	return p
end

local CREAM, RED, TRIM = Mock.Color3.fromRGB(232, 226, 210), Mock.Color3.fromRGB(179, 38, 30), Mock.Color3.fromRGB(32, 35, 38)
P.CREAM, P.RED, P.TRIM = CREAM, RED, TRIM
P.MESH_CREAM = Mock.Color3.fromRGB(217, 204, 176)

-- A player's sandbox van standing on `ground` (the ground under its middle), not in the world's Cars yet; then the
-- build's hook, as server/Vehicles.luau's spawnAt calls it: Vehicles.onStyle(car). `meshed`: the owner's Blender look
-- already on it (server/SprinterMesh.luau dresses a van after it is put out; a rebuild, a test). (10.6: no rentals,
-- no lent vehicles: every van is a player's own Sprinter.)
function P.van(player: any, ground: any, meshed: boolean?): any
	local model = Mock.Instance.new("Model")
	model.Name = `{player.Name}'s Deliveros Sprinter`
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("CarId", "sprinter")
	model:SetAttribute("SprinterArt", true)
	local chassis = part(model, "Chassis", V(7.6, 1.2, 21.8), ground * C(0, 1.8, 0), CREAM, { CanCollide = true })
	model.PrimaryPart = chassis
	part(model, "BodyRoot", V(0.4, 0.4, 0.4), chassis.CFrame, CREAM, { Transparency = 1, CanCollide = false })
	part(model, "Hull", V(8, 7.6, 14), ground * C(0, 6.2, 4), CREAM, { Transparency = 1, CanCollide = true })
	part(model, "DriveSeat", V(2, 1, 2), ground * C(-1.7, 3.7, -5.75), CREAM, { Transparency = 1, CanCollide = false })
	local look = { CanCollide = false, CanQuery = false, CanTouch = false, Massless = true }
	local paint = {}
	for index, at in { { -3.93, 6.5, 4 }, { 3.93, 6.5, 6.6 }, { 0, 10.3, 2.9 } } do
		local p = part(model, if index == 3 then "Roof" else "CargoSide", V(0.14, 7.5, 14), ground * C(at[1], at[2], at[3]), CREAM, look)
		p:SetAttribute("FleetFinish", "paint")
		table.insert(paint, p)
	end
	local slide = part(model, "SideDoor", V(0.14, 6.9, 5), ground * C(4.07, 5.85, -0.35), CREAM, look) -- (a paint part without FleetFinish)
	table.insert(paint, slide)
	for _, x in { -4.02, 4.02 } do
		local stripe = part(model, "Stripe", V(0.04, 0.45, 15), ground * C(x, 3.6, 3.5), RED, look)
		stripe:SetAttribute("FleetFinish", "stripe")
	end
	local badge = part(model, "Badge", V(0.08, 0.7, 0.7), ground * C(0, 3.25, -10.95), RED, look)
	badge:SetAttribute("FleetFinish", "stripe")
	local glass = part(model, "Windscreen", V(7.2, 3.5, 0.08), ground * C(0, 6.5, -9), Mock.Color3.fromRGB(40, 58, 68), look)
	glass:SetAttribute("FleetFinish", "glass")
	local function label(name: string, ink: any)
		local plate = part(model, name, V(6, 2.4, 0.02), ground * C(-4.03, 7.6, 4), Mock.Color3.new(1, 1, 1), look)
		plate.Transparency = 1
		plate:SetAttribute("FleetFinish", "plate")
		local gui = Mock.Instance.new("SurfaceGui")
		gui.Name = "FleetLabel"
		gui.Parent = plate
		local text = Mock.Instance.new("TextLabel")
		text.TextColor3 = ink
		text.Parent = gui
	end
	label("Logo", RED)
	label("CompanyName", TRIM)
	if meshed then
		P.dress(model)
	end
	local car = { owner = player, id = "sprinter", model = model, chassis = chassis, paintParts = paint, wrecked = false }
	P.cars[player] = car
	P.Vehicles.onStyle(car) -- (spawnAt: its STYLE looks, before it is in the world)
	return car
end

-- The owner's Blender look on a van as server/SprinterMesh.luau leaves it: its pieces "<group>_<finish>" in the folder
-- "SprinterMesh", the paint and stripe ones with their factory look.
function P.dress(model: any)
	local folder = Mock.Instance.new("Folder")
	folder.Name = "SprinterMesh"
	local ground = model.PrimaryPart.CFrame * C(0, -1.8, 0)
	for _, spec in { { "Body_paint", P.MESH_CREAM, "SmoothPlastic" }, { "BackDoorL_paint", P.MESH_CREAM, "SmoothPlastic" }, { "Body_stripe", RED, "SmoothPlastic" }, { "Body_glass", Mock.Color3.fromRGB(22, 33, 42), "Glass" } } do
		local p = part(folder, spec[1], V(7.8, 9.2, 21.6), ground * C(0, 5.8, 0), spec[2], { CanCollide = false, CanQuery = false, CanTouch = false, Massless = true })
		p.Material = spec[3]
		if string.find(spec[1], "_paint", 1, true) or string.find(spec[1], "_stripe", 1, true) then
			p:SetAttribute("FactoryColor", spec[2])
			p:SetAttribute("FactoryMaterial", spec[3])
		end
	end
	folder.Parent = model
	model:SetAttribute("SprinterMesh", true)
end

return P
