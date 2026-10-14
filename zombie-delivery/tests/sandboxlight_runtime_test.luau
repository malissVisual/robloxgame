-- 8.3 SANDBOX, the light in the house (the owner: "in the house I cannot see my own character, it is so bright"): the
-- real server/HouseInterior.luau builds house plans (shared/HouseLayout.luau) on the recorder (tools/fixtures/
-- item-mock.luau), and every interior's light is measured with shared/SandboxLightRules.luau's model (a light gives
-- brightness × (1 - (d / range)²)² at d studs; its lights never shadowed, so a lamp next door counts too):
--   * every light within Config.SandboxLight.Caps (Brightness, Range); a room's own ceiling lights within RoomLoad
--   * every room at a face's height (Caps.HeadY over the floor) at most Caps.Peak on screen (× 2^the house's exposure,
--     Config.SandboxLight.Places.house), its floor not dark (a mean of Caps.Floor at least): 8.2's house had 2.15
--   * the Neon of the house's shell and dress (not the furniture): a face bigger than NeonArea (a lamp looking down,
--     a pane, the porch's wall of daylight) no brighter than NeonLuma; the lamps' discs small, looking down
--   * the walls' plaster a warm off-white (luma at most WallLuma), never a white
-- Run with tests/run_tests.py.
local M = require("./ItemMock")
local Config = require("./Config")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")
local Rules = require("./SandboxLightRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local L = Config.SandboxLight
local CAP = L.Caps
local EYES = 2 ^ L.Places.house.Exposure

local function rgbOf(c: any): { number }
	return { c.R * 255, c.G * 255, c.B * 255 }
end

-- A part's face looking down (or up) and its biggest face, studs² (a cylinder's ends are discs).
local function faces(p: any): (number, number)
	local s, r = p.Size, p.CFrame.R
	local sizes = { s.X, s.Y, s.Z }
	local cylinder = p.Shape == "Cylinder" or p.Shape == M.Enum.PartType.Cylinder
	local function area(k: number): number
		if cylinder then
			local d = math.min(s.Y, s.Z)
			return if k == 1 then math.pi * (d / 2) ^ 2 else s.X * d
		end
		local a, b = sizes[k % 3 + 1], sizes[(k + 1) % 3 + 1]
		return a * b
	end
	local up, most = 1, -1
	for k = 1, 3 do
		local y = math.abs(r[3 + k]) -- (the world's Y of the part's axis k)
		if y > most then
			up, most = k, y
		end
	end
	return area(up), math.max(area(1), area(2), area(3))
end

-- One interior measured: its lights, every room's load, peak and floor, its big or white Neon, its white walls.
type Result = { lights: number, strong: number, long: number, over: { string }, neon: { string }, walls: { string }, discs: number, peak: number, floor: number, load: number }
local function measure(seed: number): Result
	local plan = HouseLayout.plan(seed, "house")
	local origin = HouseInterior.slot(seed)
	local model = HouseInterior.build(plan, origin)
	local o = origin.Position
	local lights: { Rules.Light } = {}
	local points: { Rules.Light } = {} -- (the ceiling lamps: a room's own)
	local r: Result = { lights = 0, strong = 0, long = 0, over = {}, neon = {}, walls = {}, discs = 0, peak = 0, floor = math.huge, load = 0 }
	local dress: { [any]: boolean } = {} -- (the shell's and the dress' parts: not the furniture)
	for _, name in { "Shell", "Decor" } do
		for _, d in model:FindFirstChild(name):GetDescendants() do
			dress[d] = true
		end
	end
	local neon: { [string]: string } = {}
	local walls: { [string]: string } = {}
	for _, d in model:GetDescendants() do
		if d.ClassName == "PointLight" or d.ClassName == "SurfaceLight" or d.ClassName == "SpotLight" then
			local at = d.Parent.CFrame.Position - o
			local l = { x = at.X, y = at.Y, z = at.Z, brightness = d.Brightness, range = d.Range }
			table.insert(lights, l)
			if d.ClassName == "PointLight" then
				table.insert(points, l)
			end
			r.strong, r.long = math.max(r.strong, d.Brightness), math.max(r.long, d.Range)
		end
		if d:IsA("BasePart") and dress[d] then
			if d.Material == "Neon" or d.Material == M.Enum.Material.Neon then
				local down, biggest = faces(d)
				local luma = Rules.luma(rgbOf(d.Color))
				if biggest > CAP.NeonArea and luma > CAP.NeonLuma then
					neon[d.Name] = `{d.Name} {math.floor(biggest)} studs² luma {math.floor(luma)}`
				end
				if d.Name == "Lamp" then
					r.discs += 1
					if down > CAP.NeonArea or luma > CAP.GlowLuma then
						neon[d.Name] = `{d.Name} disc {string.format("%.1f", down)} studs² luma {math.floor(luma)}`
					end
				end
			end
			if (d.Name == "Wall" or d.Name == "Header") and Rules.luma(rgbOf(d.Color)) > CAP.WallLuma then
				walls[d.Name] = `{d.Name} luma {math.floor(Rules.luma(rgbOf(d.Color)))}`
			end
		end
	end
	r.lights = #lights
	for _, what in neon do
		table.insert(r.neon, what)
	end
	for _, what in walls do
		table.insert(r.walls, what)
	end
	for _, room in plan.rooms do
		local x0, x1, z0, z1 = room.min.X, room.max.X, room.min.Z, room.max.Z
		local own: { Rules.Light } = {}
		for _, l in points do
			if l.x >= x0 and l.x <= x1 and l.z >= z0 and l.z <= z1 then
				table.insert(own, l)
			end
		end
		local load = Rules.load(own)
		local peak, sum, n = 0, 0, 0
		for i = 0, 8 do
			for j = 0, 8 do
				local x = x0 + 0.5 + (x1 - x0 - 1) * i / 8
				local z = z0 + 0.5 + (z1 - z0 - 1) * j / 8
				peak = math.max(peak, Rules.lux(lights, x, CAP.HeadY, z))
				sum += Rules.lux(lights, x, 0, z)
				n += 1
			end
		end
		local floor = sum / n
		r.peak, r.floor, r.load = math.max(r.peak, peak * EYES), math.min(r.floor, floor), math.max(r.load, load)
		if load > CAP.RoomLoad or peak * EYES > CAP.Peak or floor < CAP.Floor then
			table.insert(r.over, `{room.id} ({room.kind}): load {load}, peak {string.format("%.2f", peak * EYES)}, floor {string.format("%.2f", floor)}`)
		end
	end
	return r
end

local worstPeak, darkest, heaviest = 0, math.huge, 0
local seeds = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 174, 409, 647, 1955 } -- (as tests/houseinterior_test.luau; 1955 Marge's House)
local built = 0
for _, seed in seeds do
	local tag = `seed {seed}`
	local ok, r = pcall(measure, seed)
	if not ok then
		check(`{tag}: builds`, false, r)
		continue
	end
	built += 1
	worstPeak, darkest, heaviest = math.max(worstPeak, r.peak), math.min(darkest, r.floor), math.max(heaviest, r.load)
	check(`{tag}: {r.lights} lights, each at most {CAP.Brightness} bright and {CAP.Range} long`, r.lights > 0 and r.strong <= CAP.Brightness and r.long <= CAP.Range, `{r.strong} / {r.long}`)
	check(`{tag}: every room within its load, its peak on screen and not dark`, #r.over == 0, table.concat(r.over, "; "))
	check(`{tag}: {r.discs} ceiling lamps' discs small and warm, no big bright Neon (panes, the porch's wall)`, #r.neon == 0 and r.discs > 0, table.concat(r.neon, ", "))
	check(`{tag}: the plaster a warm off-white, never a white`, #r.walls == 0, table.concat(r.walls, ", "))
end
check(`every house built ({built} of {#seeds})`, built == #seeds)
print(string.format("     (the houses: the brightest face height %.2f on screen, the darkest floor %.2f, the heaviest room %.1f)", worstPeak, darkest, heaviest))

do -- 8.2's numbers (its lamps 0.9 out to 30, two past 40; the porch's 1.6 out to 18 and its white wall): the caps bite
	local H = L.House
	local keep = { H.Lamp.Brightness, H.Lamp.Range, H.Lamp.Long, H.Porch.Brightness, H.Porch.Range, H.Daylight }
	H.Lamp.Brightness, H.Lamp.Range, H.Lamp.Long = 0.9, 30, 40
	H.Porch.Brightness, H.Porch.Range, H.Daylight = 1.6, 18, { 236, 240, 228 }
	local ok, r = pcall(measure, 1)
	H.Lamp.Brightness, H.Lamp.Range, H.Lamp.Long, H.Porch.Brightness, H.Porch.Range, H.Daylight = keep[1], keep[2], keep[3], keep[4], keep[5], keep[6]
	check(`8.2's house breaks the caps: its brightest face height {if ok then string.format("%.2f", r.peak) else "?"} on screen, its porch's white wall`,
		ok and r.peak > CAP.Peak and #r.over > 0 and #r.neon > 0, if ok then nil else r)
	check("… and the house's numbers are back", measure(1).peak <= CAP.Peak)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
