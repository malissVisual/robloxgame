-- Logic test of the 3.1 exclusive gear (Config.Weapons / Config.Paints with `exclusive`, Config.Rewards): the
-- piercing rounds in Economy.weaponStats, the paint finishes server/Vehicles.luau turns into Enum.Material, and every
-- exclusive item being a reward somebody can actually earn. Standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
local Missions = require("./Missions")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- Piercing ----------------------------------------------------------------------

check("the pistol does not pierce", Economy.weaponStats("pistol", {}).pierce == 0)
check("Walt's Lever Rifle pierces 1", Economy.weaponStats("lever", {}).pierce == 1)
check("Dead End pierces 3", Economy.weaponStats("deadend", {}).pierce == 3)
check("a car gun does not pierce", Economy.carGunStats("roofmg", {}).pierce == 0)
check("an unknown gun falls back to the first, no pierce", Economy.weaponStats("nope", {}).pierce == 0)
for _, def in Config.Weapons do
	if def.pierce then
		check(`{def.id}: a piercing gun has no blast`, def.splash == 0)
		check(`{def.id}: a sane pierce`, def.pierce >= 1 and def.pierce <= 5, def.pierce)
	end
end

-- Paint finishes: the names server/Vehicles.luau looks up in Enum.Material ----------------------------------------

local MATERIALS = {
	Plastic = true, SmoothPlastic = true, Neon = true, Wood = true, WoodPlanks = true, Marble = true, Slate = true,
	Concrete = true, Granite = true, Brick = true, Pebble = true, CorrodedMetal = true, DiamondPlate = true, Foil = true,
	Metal = true, Grass = true, Ice = true, Sand = true, Fabric = true, Glass = true, ForceField = true, Cobblestone = true,
}
for _, def in Config.Paints do
	if def.material then
		check(`{def.id}: material {def.material} is an Enum.Material`, MATERIALS[def.material] == true)
	end
end

-- Exclusive items are rewards, and every reward is an exclusive item --------------------------------------------

local campaignIds: { [string]: boolean } = {}
for _, campaign in Missions.Campaigns do
	campaignIds[campaign.id] = true
end
local function earnable(exclusive: string): boolean
	return exclusive == "secrets" or exclusive == "challenges" or campaignIds[exclusive] == true
end
for _, def in Config.Weapons do
	if def.exclusive then
		check(`{def.id}: earned from a real reward`, earnable(def.exclusive), def.exclusive)
		check(`{def.id}: not for sale and no level`, def.price == 0 and def.level == nil and def.earned == nil)
	end
end
for _, def in Config.Paints do
	if def.exclusive then
		check(`{def.id}: earned from a real reward`, earnable(def.exclusive), def.exclusive)
		check(`{def.id}: has its own colour`, def.color ~= nil)
	end
end
for id, reward in Config.Rewards.Campaigns do
	local weapon = reward.weapon and Economy.findWeapon(reward.weapon)
	local paint = reward.paint and Economy.findPaint(reward.paint)
	check(`campaign {id}: a gun or a paint`, weapon ~= nil or paint ~= nil)
	check(`campaign {id}: its item is exclusive to it`, ((weapon and weapon.exclusive) or (paint and paint.exclusive)) == id)
end
local deadEnd = Economy.findWeapon(Config.Rewards.Challenges.weapon)
check("the challenges gun is Dead End, exclusive to the challenges", deadEnd ~= nil and deadEnd.exclusive == "challenges")
local phantom = Economy.findPaint(Config.Rewards.Secrets.paint)
check("the secrets paint is exclusive to the secrets", phantom ~= nil and phantom.exclusive == "secrets")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
