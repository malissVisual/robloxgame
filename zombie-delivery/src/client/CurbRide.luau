--!strict
-- 6.10: up the curb smoothly in the vehicle you drive (your client owns and moves it: client/Drive.luau). The kerb
-- round every block is a slope (shared/CurbShape.luau) that the frictionless wheels ride up anywhere; at speed the
-- slope would also throw the vehicle into the air (its rise per stud times the speed: 15 studs / s up at 60, half a
-- stud of hop over the walk). After every physics step, while the vehicle is over a kerb (its nose, middle, tail or a
-- corner of it near a block's edge, its floor near the walk's level), its upward speed is held to Config.City.CurbHop:
-- the slope still lifts it as far as it must, only the fling past its top is gone. Down the curb nothing is touched.
-- Not a chauffeur's car (the server drives it then) and nothing while you only ride along.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local CurbShape = require(Shared.CurbShape)
local Map = require(Shared.Map)
local Drive = require(script.Parent.Drive)

local CurbRide = {}

local started = false
local NEAR = 2 -- studs on either side of the kerb's slope that still count (the tyres reach past the chassis)
local HIGH = 4 -- the chassis' bottom at most this far over the walk (a car on its wheels: up to 2.6 clearance)

-- Is a chassis over (or right at) a kerb: one of its six points (nose, middle, tail; the four corners) near the slope?
local function overKerb(chassis: BasePart): boolean
	if chassis.Position.Y - chassis.Size.Y / 2 > Map.WalkTop + HIGH then
		return false
	end
	local frame = chassis.CFrame
	local halfX, halfZ = chassis.Size.X / 2, chassis.Size.Z / 2
	for _, at in { Vector3.new(0, 0, -halfZ), Vector3.zero, Vector3.new(0, 0, halfZ), Vector3.new(-halfX, 0, -halfZ), Vector3.new(halfX, 0, -halfZ), Vector3.new(-halfX, 0, halfZ), Vector3.new(halfX, 0, halfZ) } do
		local p = frame * at
		local out = CurbShape.outside(p.X, p.Z)
		if out > -NEAR and out < CurbShape.Run + NEAR then
			return true
		end
	end
	return false
end

local function step()
	if not Drive.isDriving() then
		return
	end
	local car = Drive.myCar()
	local chassis = car and car.PrimaryPart
	if not car or not chassis or car:GetAttribute("Chauffeured") == true or chassis.Anchored then
		return
	end
	local velocity = chassis.AssemblyLinearVelocity
	local hop = Config.City.CurbHop
	if velocity.Y > hop and overKerb(chassis) then
		chassis.AssemblyLinearVelocity = Vector3.new(velocity.X, hop, velocity.Z)
	end
end

function CurbRide.start()
	if started then
		return
	end
	started = true
	RunService.Heartbeat:Connect(step)
end

return CurbRide
