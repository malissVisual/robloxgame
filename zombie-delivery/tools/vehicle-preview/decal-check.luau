--!strict
-- 6.12: the vehicles' cosmetics on the real Vehicles factory (its bodies as built for a player, every stage; bare, and
-- with every gear, upgrade and a car gun on the roof), put on by the real shared/StyleBuild.luau with the property
-- recorder. Every decal look: laid only on the body's painted panels (the hood, the roofs, the cargo sides, the front
-- fenders; never a door), each part lying on its panel's face, inside its edges, clear of every other visible part
-- (lamps, glass, labels, stripes, racks, ladders, the gun, the kit, the doors), within the part budget, welded to the
-- chassis, massless and out of the physics. A wrap covers every painted panel; a bike's and the E-Scooter's paint
-- takes their frames and gives them back. Run by check_fleet.py next to the fleet and bike audits.
local Mock = require('./roblox-mock')
local Vehicles = require('./Vehicles')
local Config = require('./Config')
local Economy = require('./Economy')
local Style = require('./Style')
local StyleBuild = require('./StyleBuild')
local StyleLooks = require('./StyleLooks')

local Fit = Config.Cosmetics.Fit
local CANVAS = { Hood = true, CabRoof = true, CargoRoof = true, RearDeck = true, CargoSide = true, FrontFender = true }
local TOL = 0.012
-- what every body shows of a look at the least: the logo on both sides (or the hood), two stripes, a checker band a
-- side or one, flames on the hood or a side, two pinstripes
local LEAST: { [string]: number } = { logo = 2, stripes = 2, checker = 2, flames = 6, pinstripe = 4 }

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if not ok then
		failures += 1
		if failures <= 60 then
			print('FAIL  ' .. name .. (if detail ~= nil then '  (' .. tostring(detail) .. ')' else ''))
		end
	end
end

local function under(p: any, names: { [string]: boolean }, top: any): boolean
	local at = p
	while at and at ~= top do
		if names[at.Name] then
			return true
		end
		at = at.Parent
	end
	return false
end

local function overlap(a: any, b: any, tol: number): boolean
	for i = 1, 3 do
		if a.max[i] <= b.min[i] + tol or a.min[i] >= b.max[i] - tol then
			return false
		end
	end
	return true
end

-- One decal item of each look.
local looks: { any } = {}
local seen: { [string]: boolean } = {}
for _, def in Style.items('decal') do
	if not seen[def.look] then
		seen[def.look] = true
		table.insert(looks, def)
	end
end

local gunId: string? = nil
for _, gun in Config.CarGuns do
	gunId = gunId or gun.id
end

local laid, most, builds = 0, 0, 0
local least: { [string]: number } = {}
local rows: { string } = {}
for _, def in Config.Cars do
	if def.company or def.bike then
		continue
	end
	for stage = 0, Economy.maxStage(def.id) do
		for _, full in { false, true } do
			local gun = if full and Economy.canMount(def.id) then gunId else nil
			local built = Vehicles.__testBuild(def, Mock.Color3.fromRGB(table.unpack(def.color)), Mock.CFrame.identity, false, gun, nil, stage)
			local model, chassis = built.model, built.chassis
			if full then
				local gear = {}
				for _, piece in Config.Gear do
					if Economy.gearFits(def.id, piece.id) then
						gear[piece.id] = true
					end
				end
				Vehicles.__testBuildKit(model, chassis, Vehicles.__testStyle(def, stage), { engine = 5, handling = 5, armor = 5, plow = 5 }, def.id, gear)
			end
			builds += 1
			local label = `{def.id}:{stage}{if full then ' kitted' else ''}`
			-- the wrap: every painted panel (the doors' too) in its colour
			local wrap = Style.find('wrap_teal') :: any
			StyleBuild.wrap(built.paintParts, wrap)
			local wrapped = true
			for _, p in built.paintParts do
				wrapped = wrapped and p.Color.R == Mock.Color3.fromRGB(wrap.color[1], wrap.color[2], wrap.color[3]).R and p:GetAttribute('StylePaint') == true
			end
			check(`{label}: the wrap on every painted panel`, wrapped and #built.paintParts > 10, #built.paintParts)
			local counts: { string } = {}
			for _, item in looks do
				local folder = StyleBuild.decals(model, chassis, item)
				local parts: { any } = {}
				for _, d in (if folder then folder:GetDescendants() else {}) do
					if d:IsA('BasePart') then
						table.insert(parts, d)
					end
				end
				local tag = `{label} {item.look}`
				check(`{tag}: laid`, folder ~= nil and folder.Parent == model and #parts > 0, #parts)
				check(`{tag}: within the budget`, #parts <= Fit.Budget, #parts)
				check(`{tag}: enough of it shows`, #parts >= (LEAST[item.look] or 1), #parts)
				laid += #parts
				most = math.max(most, #parts)
				least[item.look] = math.min(least[item.look] or math.huge, #parts)
				table.insert(counts, `{item.look} {#parts}`)
				-- the car's own parts: its painted canvases and every other visible part
				local canvases, others = {}, {}
				for _, d in model:GetDescendants() do
					if d:IsA('BasePart') and d.Transparency < 0.95 and not under(d, { StyleDecals = true }, model) then
						local b = StyleBuild.box(chassis.CFrame, d)
						if CANVAS[d.Name] and d:GetAttribute('FleetFinish') == 'paint' and not under(d, { CarDoor = true, BackDoor = true }, model) then
							table.insert(canvases, b)
						else
							table.insert(others, b)
						end
					end
				end
				for _, p in parts do
					local weld = p:FindFirstChild('StyleWeld')
					check(`{tag}: {p.Name} welded to the chassis`, weld ~= nil and weld.Part0 == chassis and weld.Part1 == p)
					check(`{tag}: {p.Name} loose, light and out of the physics`, not p.Anchored and p.Massless and not p.CanCollide and not p.CanQuery and not p.CanTouch and not p.CastShadow)
					local b = StyleBuild.box(chassis.CFrame, p)
					local thin = 1
					local size = { b.max[1] - b.min[1], b.max[2] - b.min[2], b.max[3] - b.min[3] }
					if size[2] < size[thin] then thin = 2 end
					if size[3] < size[thin] then thin = 3 end
					-- it lies on a canvas: its inner face on the canvas' outer face, its footprint inside the canvas
					local support: any = nil
					for _, c in canvases do
						local onFace = false
						if thin == 2 then
							onFace = math.abs(b.min[2] - c.max[2]) <= Fit.Lift + 0.006 + TOL
						elseif thin == 1 then
							onFace = (b.min[1] > 0 and math.abs(b.min[1] - c.max[1]) <= Fit.Lift + 0.006 + TOL) or (b.max[1] < 0 and math.abs(c.min[1] - b.max[1]) <= Fit.Lift + 0.006 + TOL)
						end
						local inside = true
						for i = 1, 3 do
							if i ~= thin and (b.min[i] < c.min[i] - TOL or b.max[i] > c.max[i] + TOL) then
								inside = false
							end
						end
						if onFace and inside then
							support = c
							break
						end
					end
					check(`{tag}: {p.Name} lies on a painted panel`, support ~= nil, string.format('%.2f %.2f %.2f', (b.min[1] + b.max[1]) / 2, (b.min[2] + b.max[2]) / 2, (b.min[3] + b.max[3]) / 2))
					local clash = nil
					for _, o in others do
						if overlap(b, o, 1e-3) then
							clash = o
							break
						end
					end
					check(`{tag}: {p.Name} clear of the car's other parts`, clash == nil, clash and string.format('%.2f %.2f %.2f', (clash.min[1] + clash.max[1]) / 2, (clash.min[2] + clash.max[2]) / 2, (clash.min[3] + clash.max[3]) / 2))
					-- and of the other canvases (it lies on one, never in another)
					for _, c in canvases do
						if c ~= support then
							check(`{tag}: {p.Name} not in another panel`, not overlap(b, c, 1e-3))
						end
					end
				end
			end
			StyleBuild.decals(model, chassis, nil)
			check(`{label}: TAKE OFF leaves no decal`, model:FindFirstChild(StyleBuild.Decals) == nil)
			if not full then
				table.insert(rows, string.format('  %-14s %s', label, table.concat(counts, ', ')))
			end
		end
	end
end
for _, row in rows do
	print(row)
end

-- The bikes and the E-Scooter: the frame in the paint, then its own colours again.
local framed = 0
for _, def in Config.Cars do
	if not def.bike then
		continue
	end
	local built = Vehicles.__testBuild(def, Mock.Color3.fromRGB(table.unpack(def.color)), Mock.CFrame.identity, false, nil, nil, 0)
	local paint = Style.find('bike_mint') :: any
	local own: { [any]: any } = {}
	for _, d in built.model:GetDescendants() do
		if d:IsA('BasePart') then
			own[d] = d.Color
		end
	end
	StyleBuild.paintBike(built.model, paint)
	local painted, lamps = 0, true
	for d, color in own do
		if d.Color ~= color then
			painted += 1
			check(`{def.id}: {d.Name} painted is a frame part`, table.find(StyleLooks.BikeFrame, d.Name) ~= nil and d:GetAttribute('StyleBase') ~= nil)
		end
		if d:GetAttribute('NightLamp') == true and d.Color ~= color then
			lamps = false
		end
	end
	check(`{def.id}: its frame painted`, painted >= 4, painted)
	check(`{def.id}: its lamps keep their colours`, lamps)
	framed += painted
	StyleBuild.paintBike(built.model, nil)
	local back = true
	for d, color in own do
		back = back and d.Color == color and d:GetAttribute('StyleBase') == nil
	end
	check(`{def.id}: its own colours again`, back)
end

local summary = {}
for _, item in looks do
	table.insert(summary, `{item.look} ≥ {least[item.look]}`)
end
print(`Decal PASS: {#looks} looks on {builds} builds (every stage, bare and kitted with a gun): {laid} parts laid, at most {most} a decal (budget {Fit.Budget}); the fewest: {table.concat(summary, ', ')}; the wrap on every painted panel; {framed} bike frame parts painted and given back`)
if failures > 0 then
	print(`{failures} CHECK(S) FAILED`)
	error('decal check failed')
end
