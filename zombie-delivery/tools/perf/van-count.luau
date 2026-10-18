-- 8.2: the van's side of tools/perf/sandbox_count.py: the real vehicle factory (server/Vehicles.luau on
-- tools/vehicle-preview's stand-in, as export_fleet.py runs it) builds the sandbox's van (Config.Sandbox.Van, the ZDC
-- Sprinter's parts model: without the owner's Blender import) and prints its census rows. (10.6: no stages, no kit:
-- the one van as every player has it, the row van/stage0.)
local Mock = require("./roblox-mock")
local Vehicles = require("./Vehicles")
local Config = require("./Config")
local Census = require("./census")

local def = nil
for _, car in Config.Cars do
	if car.id == Config.Sandbox.Van then
		def = car
	end
end
assert(def, "no Config.Sandbox.Van in Config.Cars")
-- The sandbox's fixed afternoon (workspace attribute Night false): server/DayNight.luau's nightLight puts a night light
-- and the lights in it out as it registers them (the stand-in only marks them).
local function byDay(model: any)
	for _, d in model:GetDescendants() do
		if d:GetAttribute("NightLight") then
			if d.ClassName == "PointLight" or d.ClassName == "SpotLight" or d.ClassName == "SurfaceLight" then
				d.Enabled = false
			end
			for _, child in d:GetChildren() do
				if child.ClassName == "PointLight" or child.ClassName == "SpotLight" or child.ClassName == "SurfaceLight" then
					child.Enabled = false
				end
			end
		end
	end
end

local built = Vehicles.__testBuild(def, Mock.Color3.fromRGB(unpack(def.color)), Mock.CFrame.identity, false)
byDay(built.model)
print(Census.line("van/stage0", Census.under(built.model)))
for _, line in Census.detail(Census.list(built.model)) do
	print(`DETAIL van\t{line}`)
end
