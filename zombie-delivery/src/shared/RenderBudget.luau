--!strict
-- 6.13.1, performance and mobile (design/performance/REPORT.md): the pure rules that keep a mid-range phone smooth,
-- with their numbers in Config.Performance. Pure (no Roblox at its top level; tests/renderbudget_test.luau runs it in the
-- plain Luau CLI).
--   * RenderBudget.casts(a, b, c, flatUp, height): does a part of size a × b × c throw a shadow worth its cost? Only
--     when its longest side is at least ShadowLong and its second side at least ShadowWide (a pole or a wall does; a
--     rail, a strip, a rod, a frame or a small box does not), and not when it is a thin plate lying flat on the ground
--     (its thinnest side at most ShadowFlat and that side pointing up: `flatUp` is how upright the thin side's axis is
--     in the world, 0 … 1; its middle at most ShadowFlatHeight high: a raised canopy, an awning or a palm's leaves
--     keep theirs). RenderBudget.shadowFor(size, cframe) works it out for a part (World's part(), BuildingLooks/Kit,
--     the props).
--   * RenderBudget.choose(units, count, range): which lights shine (client/WorldFx.luau). A unit is one lamp or a
--     vehicle's lights together (`size` of them); the nearest units are taken while their lights fit in `count` and they
--     are within `range`. One that shines already keeps shining out to range × LightHoldRange and LightHoldExtra lights
--     over the count, so nothing blinks at the edge. Returns the chosen indices as a set.
--   * RenderBudget.numbers(lite): the light budget for this device (Config.Performance, its Lite numbers on a phone).
--   * RenderBudget.signRange: how close the small text on signs and plates is drawn (SurfaceGui.MaxDistance).

local Config = require(script.Parent.Config)

local RenderBudget = {}

local Tuning = Config.Performance

-- Studs: the small text on signs, plates and boards is drawn only this close (SurfaceGui.MaxDistance).
RenderBudget.signRange = Tuning.SignRange

-- a, b, c: the part's three sides (any order); flatUp: |the world Y| of the thinnest side's axis (1 = lying flat);
-- height: the part's middle in world studs (nil: not known, taken as on the ground).
function RenderBudget.casts(a: number, b: number, c: number, flatUp: number?, height: number?): boolean
	local long = math.max(a, b, c)
	local short = math.min(a, b, c)
	local middle = a + b + c - long - short
	if long < Tuning.ShadowLong or middle < Tuning.ShadowWide then
		return false
	end
	if short <= Tuning.ShadowFlat and (flatUp or 0) >= 0.9 and (height or 0) <= Tuning.ShadowFlatHeight then
		return false -- a plate lying on the ground: its shadow is under it
	end
	return true
end

-- The same for a part: its Size and CFrame (anything with X, Y, Z, Position and RightVector, UpVector, LookVector).
function RenderBudget.shadowFor(size: Vector3, cframe: CFrame): boolean
	local x, y, z = size.X, size.Y, size.Z
	local axis = if x <= y and x <= z then cframe.RightVector elseif y <= z then cframe.UpVector else cframe.LookVector
	return RenderBudget.casts(x, y, z, math.abs(axis.Y), cframe.Position.Y)
end

-- One light, or a vehicle's lights together: how far from the camera, how many lights, whether they shine now.
export type Unit = { distance: number, size: number, on: boolean }

-- The units that shine (see the top): { [index]: true }.
function RenderBudget.choose(units: { Unit }, count: number, range: number): { [number]: boolean }
	local order: { number } = {}
	for index, unit in units do
		if unit.distance <= (if unit.on then range * Tuning.LightHoldRange else range) then
			table.insert(order, index)
		end
	end
	table.sort(order, function(i: number, j: number): boolean
		return units[i].distance < units[j].distance
	end)
	local chosen: { [number]: boolean } = {}
	local used = 0
	for _, index in order do
		local unit = units[index]
		if used + unit.size <= (if unit.on then count + Tuning.LightHoldExtra else count) then
			chosen[index] = true
			used += unit.size
		end
	end
	return chosen
end

-- The light budget: how many real lights shine at most, within how many studs of the camera.
function RenderBudget.numbers(lite: boolean): (number, number)
	if lite then
		return Tuning.Lite.MaxLights, Tuning.Lite.LightRange
	end
	return Tuning.MaxLights, Tuning.LightRange
end

return RenderBudget
