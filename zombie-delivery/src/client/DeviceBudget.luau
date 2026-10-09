--!strict
-- 6.13.1, performance and mobile (design/performance/REPORT.md): how much cosmetic per-frame work this device gets. A
-- phone or a tablet (a touch screen without a keyboard, Ui.touchLayout's test) is "lite": the per-frame poses and
-- motions reach Config.Performance.Lite.Range of their distance on a computer (client/BodyLife.luau, SprintPose,
-- BagSway, ZombieAnimator, AnimalAnimator, TrafficAnimator, CarVisuals, ShopPropMotion, WorldFx's flicker), the posed
-- bodies Lite.Count of their number, the night's real lights are fewer and closer (shared/RenderBudget.luau numbers,
-- client/WorldFx.luau), the minimap's routes and markers redraw Lite.MapHz times a second and its turning picture moves
-- Lite.MapMoveHz times a second (client/MapView.luau).
-- Nothing that plays changes: only how far from the camera the eye candy runs.
-- The users read it every time (a field and a multiplication), so the admin's performance overlay
-- (client/PerfOverlay.luau) can switch it to compare: DeviceBudget.setLite.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DeviceBudget = {}

local Lite = Config.Performance.Lite

-- Is this a phone or a tablet (as the game starts; a keyboard plugged in later does not change it)?
DeviceBudget.touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
DeviceBudget.lite = DeviceBudget.touch

-- `studs` (a range tuned on a computer) on this device.
function DeviceBudget.range(studs: number): number
	return if DeviceBudget.lite then studs * Lite.Range else studs
end

-- `n` (a count tuned on a computer) on this device, at least 1.
function DeviceBudget.count(n: number): number
	return if DeviceBudget.lite then math.max(1, math.floor(n * Lite.Count + 0.5)) else n
end

-- Times a second for the minimap's heavy redraws (`hz` on a computer).
function DeviceBudget.rate(hz: number): number
	return if DeviceBudget.lite then math.min(hz, Lite.MapHz) else hz
end

-- Times a second the turning minimap moves (every frame on a computer: math.huge).
function DeviceBudget.moveRate(): number
	return if DeviceBudget.lite then Lite.MapMoveHz else math.huge
end

-- The admin's overlay: lite on or off on this client only (to compare the frame rate).
function DeviceBudget.setLite(on: boolean)
	DeviceBudget.lite = on
end

return DeviceBudget
