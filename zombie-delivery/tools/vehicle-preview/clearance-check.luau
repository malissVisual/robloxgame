--!strict
-- 6.12.15: the footbridge over Bone St (shared/Map.luau Map.Footbridge) clears every vehicle by 3 studs: its `tallest`
-- must be at least as tall as anything the real factory builds. Every car of Config.Cars at every stage, with its full
-- kit, all the gear that fits it and a roof gun where one mounts, the bikes, and the city bus (Vehicles.buildBus: the
-- traffic's bus with its line's stripe and sign), each standing on the ground (y = 0): the top of every part (the
-- hidden hulls too). Run by check_fleet.py.
local Mock = require("./roblox-mock")
local Vehicles = require("./Vehicles")
local Config = require("./Config")
local Economy = require("./Economy")
local Map = require("./Map")

local function top(model: any): (number, string)
	local high, name = -math.huge, ""
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local r, s = p.CFrame.R, p.Size -- (the mock's rotation, row by row: its second row is the world's up)
			local reach = math.abs(r[4]) * s.X / 2 + math.abs(r[5]) * s.Y / 2 + math.abs(r[6]) * s.Z / 2
			if p.Position.Y + reach > high then
				high, name = p.Position.Y + reach, p.Name
			end
		end
	end
	return high, name
end

local tallest, who = 0, ""
for _, def in Config.Cars do
	local gear = {}
	for _, piece in Config.Gear do
		if Economy.gearFits(def.id, piece.id) then
			gear[piece.id] = true
		end
	end
	for stage = 0, Economy.maxStage(def.id) do
		for _, gunId in { false, "roofmg", "roofminigun", "rooflauncher" } do
			if gunId and not def.mount then
				continue
			end
			local built = Vehicles.__testBuild(def, Mock.Color3.fromRGB(200, 200, 200), Mock.CFrame.identity, false, gunId or nil, nil, stage)
			Vehicles.__testBuildKit(built.model, built.chassis, Vehicles.__testStyle(def, stage), { engine = 5, handling = 0, armor = 5, plow = 5 }, def.id, gear)
			local high, name = top(built.model)
			if high > tallest then
				tallest, who = high, `{def.id} stage {stage}{if gunId then " " .. gunId else ""} ({name})`
			end
		end
	end
end
local bus = Vehicles.buildBus(Economy.findCar("bus") :: Config.CarDef, Mock.CFrame.identity, Mock.Color3.fromRGB(226, 228, 222), Mock.Color3.fromRGB(200, 40, 40))
local busTop, busPart = top(bus.model)
if busTop > tallest then
	tallest, who = busTop, `the city bus ({busPart})`
end
local F = Map.Footbridge
assert(tallest <= F.tallest + 1e-6, `{who} is {tallest} tall: over Map.Footbridge.tallest ({F.tallest}); raise the footbridge`)
assert(F.deck - F.thick - Map.WalkTop >= F.tallest + 3 - 1e-6, "the footbridge's beams are less than the tallest vehicle + 3 over the walk")
print(string.format("Footbridge clearance PASS: the tallest vehicle %.2f (%s), the bridge holds %.2f, its beams %.2f over the walk", tallest, who, F.tallest, F.deck - F.thick - Map.WalkTop))
