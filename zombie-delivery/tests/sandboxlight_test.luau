-- 8.3 SANDBOX, the light (the owner: "too bright: in the house I cannot see my own character, the warehouse is a
-- flashbang"): Config.SandboxLight and shared/SandboxLightRules.luau, pure:
--   * every place's look within Roblox's ranges (ExposureCompensation -3 … 3, Bloom Intensity 0 … 1, Size 0 … 56,
--     Threshold 0.8 … 4, the grade -1 … 1, SunRays 0 … 1); indoors calmer than outdoors (less bloom, a higher threshold:
--     never a white wall glowing, no sun rays); two places a cut apart at most a third of a stop (even a hard cut is
--     no flash); look(): the map's exposure plus the place's, a phone's bloom LiteBloom as much
--   * the eyes: ease() goes the whole way without overshoot, 95 % in Ease s (on a 60 fps computer and a 10 fps phone),
--     never more than Caps.Step of exposure in one step, a 2 s hitch no jump; settled() once there
--   * where you are: a Sprinter's walk-in bay (inBay round its BayLight) is the van, the move's house wins over it, a
--     plot's hall the warehouse, the interiors far off the map the house, the road outdoors
--   * the budget (the model: brightness × (1 - (d / range)²)²): every plot's hall (WarehouseLayout.pieces) and the van's
--     bay within Caps (one light, the hall's load, the peak at a face's height × 2^exposure, the floor not dark), the
--     lamps' Neon small and dim, a big Neon face dim; 8.2's numbers break those caps (so they bite). The house's rooms
--     are built for real in tests/sandboxlight_runtime_test.luau. Run with tests/run_tests.py.
local Config = require("./Config")
local Rules = require("./SandboxLightRules")
local SandboxMap = require("./SandboxMap")
local SandboxScenery = require("./SandboxScenery")
local SprinterLooks = require("./SprinterLooks")
local WarehouseLayout = require("./WarehouseLayout")

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
local function within(x: number, lo: number, hi: number): boolean
	return type(x) == "number" and x == x and x >= lo and x <= hi
end

-- ── The places' looks ─────────────────────────────────────────────────────────

do
	local bad: { string } = {}
	for _, place in Rules.Places do
		local p = (L.Places :: any)[place]
		if not p then
			table.insert(bad, place .. ": none")
			continue
		end
		local b, g = p.Bloom, p.Grade
		local ok = within(p.Exposure + L.Sky.Exposure, -3, 3) and within(p.Exposure, -0.5, 0.5)
			and within(b.Intensity, 0, 1) and within(b.Size, 0, 56) and within(b.Threshold, 0.8, 4)
			and within(g.Brightness, -0.1, 0.1) and within(g.Contrast, -0.2, 0.2) and within(g.Saturation, -0.3, 0.3)
			and within(g.Tint[1], 0, 255) and within(g.Tint[2], 0, 255) and within(g.Tint[3], 0, 255)
			and within(p.Rays, 0, 1)
		if not ok then
			table.insert(bad, place)
		end
	end
	check("every place has a look within Roblox's ranges (exposure ±0.5 of the map's, bloom, grade, rays)", #bad == 0, table.concat(bad, ", "))
	local out = L.Places.outdoors
	local calm = true
	for _, place in { "house", "warehouse", "van" } do
		local p = (L.Places :: any)[place]
		calm = calm and p.Bloom.Intensity <= out.Bloom.Intensity and p.Bloom.Threshold >= math.max(out.Bloom.Threshold, 1.8) and p.Rays == 0
	end
	check("indoors blooms less than outdoors, only past a threshold of 1.8 (Neon, never a lit wall), no sun rays", calm)
	local most = 0
	for _, a in Rules.Places do
		for _, b in Rules.Places do
			most = math.max(most, math.abs((L.Places :: any)[a].Exposure - (L.Places :: any)[b].Exposure))
		end
	end
	check(`two places are at most a third of a stop apart (even a hard cut is no flash): {most}`, most <= 0.33, most)
	check("eased over 0.3 … 1.5 s, a step at most 0.25 s, where you are looked at every 0.05 … 0.5 s, a phone blooms less",
		within(L.Ease, 0.3, 1.5) and within(L.Step, 0.01, 0.25) and within(L.Every, 0.05, 0.5) and within(L.LiteBloom, 0, 1) and within(L.RaySpread, 0, 1))
	local house = Rules.look("house")
	check("look(): the map's exposure plus the place's", math.abs(house.exposure - (L.Sky.Exposure + L.Places.house.Exposure)) < 1e-9)
	check("look(): a phone's bloom LiteBloom as much", math.abs(Rules.look("house", true).bloom - L.Places.house.Bloom.Intensity * L.LiteBloom) < 1e-9)
	check("look(): an unknown place is outdoors'", Rules.settled(Rules.look("nowhere"), Rules.look("outdoors")))
	local copy = Rules.copy(house)
	copy.tint[1] = 0
	check("copy(): a look of its own (its tint too)", house.tint[1] ~= 0)
end

-- ── The eyes ──────────────────────────────────────────────────────────────────

do
	local function run(from: string, to: string, fps: number): (number, number, boolean, number)
		local a, b = Rules.look(from), Rules.look(to)
		local shown = Rules.copy(a)
		local biggest, over, t = 0, false, 0
		local dt = 1 / fps
		local at95 = math.huge
		local span = b.exposure - a.exposure
		while t < 3 do
			local was = shown.exposure
			shown = Rules.ease(shown, b, dt)
			t += dt
			biggest = math.max(biggest, math.abs(shown.exposure - was))
			if span ~= 0 and (shown.exposure - b.exposure) * (a.exposure - b.exposure) < -1e-9 then
				over = true -- (past the target)
			end
			if at95 == math.huge and (span == 0 or math.abs(shown.exposure - a.exposure) >= 0.95 * math.abs(span) - 1e-9) then
				at95 = t
			end
		end
		return at95, biggest, over, math.abs(shown.exposure - b.exposure)
	end
	local slow, jumps, overs, left = 0, 0, 0, 0
	local worst = ""
	for _, fps in { 60, 30, 10 } do
		for _, a in Rules.Places do
			for _, b in Rules.Places do
				local at95, biggest, over, rest = run(a, b, fps)
				if at95 > L.Ease + 1.5 / fps + 1e-6 then
					slow += 1
					worst = `{a} → {b} at {fps} fps: {at95} s`
				end
				if biggest > CAP.Step then
					jumps += 1
				end
				if over then
					overs += 1
				end
				left = math.max(left, rest)
			end
		end
	end
	check(`the eyes reach 95 % of a new place in Ease ({L.Ease} s), at 60, 30 and 10 fps`, slow == 0, worst)
	check(`never more than {CAP.Step} of a stop in one step (no flash at a door)`, jumps == 0, jumps)
	check("never past the new place's look, and there after 3 s", overs == 0 and left < 1e-3, left)
	local a, b = Rules.look("outdoors"), Rules.look("warehouse")
	local hitch = Rules.ease(a, b, 2)
	local share = (hitch.exposure - a.exposure) / (b.exposure - a.exposure)
	check("a 2 s hitch moves only one Step's share (no jump)", share > 0 and share <= 1 - math.exp(-3 * L.Step / L.Ease) + 1e-9, share)
	check("every number and the tint ease together", math.abs((hitch.bloom - a.bloom) / (b.bloom - a.bloom) - share) < 1e-9 and math.abs((hitch.threshold - a.threshold) / (b.threshold - a.threshold) - share) < 1e-9)
	local shown = Rules.copy(a)
	local steps = 0
	while not Rules.settled(shown, b) and steps < 1000 do
		shown = Rules.ease(shown, b, 1 / 60)
		steps += 1
	end
	check(`settled() once there (after {steps} frames at 60 fps), not before`, steps < 2 * 60 * L.Ease and steps > 3 and not Rules.settled(a, b), steps)
	check("ease(0) changes nothing", Rules.settled(Rules.ease(a, b, 0), a))
end

-- ── Where you are ─────────────────────────────────────────────────────────────

do
	local bay, light = SprinterLooks.Bay, SprinterLooks.Light
	local mid = (bay.z0 + bay.z1) / 2 - light[3]
	local feet = bay.y0 - light[2] -- (the bay's floor, from its light)
	check("in the bay: its middle at a body's middle", Rules.inBay(0, feet + 3, mid))
	check("in the bay: against its lining, at its back doors", Rules.inBay(bay.x1 - light[1] - 0.2, feet + 3, mid) and Rules.inBay(0, feet + 3, bay.z1 - light[3] - 0.1))
	check("not in the bay: beside the van, over its roof, under its floor, behind its back doors", not Rules.inBay(bay.x1 - light[1] + 2, feet + 3, mid) and not Rules.inBay(0, bay.y1 - light[2] + 2, mid)
		and not Rules.inBay(0, feet - 2, mid) and not Rules.inBay(0, feet + 3, bay.z1 - light[3] + 2))
	check("not in the bay: in the cab", not Rules.inBay(0, feet + 3, bay.z0 - light[3] - 3))
	local plot = SandboxMap.Plots[1]
	local w = WarehouseLayout.box(plot, nil) -- (8.3: no level known: the start's, a free plot's)
	check("a plot's hall is the warehouse", Rules.place(w.x, 3, w.z, false, false) == "warehouse")
	check("the interiors far off the map are the house", Rules.place(9000, 403, 9000, false, false) == "house")
	check("the move's house says inside: the house (even by a van's bay)", Rules.place(0, 3, 0, true, false) == "house" and Rules.place(0, 3, 0, true, true) == "house")
	check("in a van's bay: the van (even in front of a warehouse)", Rules.place(plot.vanSpot.x, 3, plot.vanSpot.z, false, true) == "van")
	check("Main Street is outdoors", Rules.place(0, 3, 100, false, false) == "outdoors")
end

-- ── The budget ────────────────────────────────────────────────────────────────

check("the model: full at the light, nothing at its range, smooth in between", Rules.falloff(0, 10) == 1 and Rules.falloff(10, 10) == 0 and Rules.falloff(12, 10) == 0
	and math.abs(Rules.falloff(5, 10) - 0.5625) < 1e-9 and Rules.falloff(1, 0) == 0)
check("luma: white 255, black 0, green the brightest primary", math.abs(Rules.luma({ 255, 255, 255 }) - 255) < 1e-6 and Rules.luma({ 0, 0, 0 }) == 0 and Rules.luma({ 0, 255, 0 }) > Rules.luma({ 255, 0, 0 }))
check("the map's afternoon is Config.SandboxLight.Sky (SandboxScenery.Light)", SandboxScenery.Light == L.Sky)
check("the sky: the sun at most 2, the shade's light under the open air's, no lift (no grey haze over the picture)",
	L.Sky.Brightness <= 2 and Rules.luma(L.Sky.Ambient) < Rules.luma(L.Sky.Outdoor) and Rules.luma(L.Sky.Outdoor) <= 128 and L.Sky.Lift <= 0.01 and L.Sky.Specular <= 0.6)

-- A hall's lights (WarehouseLayout.pieces: its PointLights) and the measure of its floor at the floor and a face's height.
type Measure = { peak: number, floor: number, load: number, count: number, strongest: number, longest: number }
local function hall(plot: SandboxMap.Plot, lamp: { Brightness: number, Range: number }?, level: number): Measure
	local lights: { Rules.Light } = {}
	local strongest, longest = 0, 0
	for _, p in WarehouseLayout.pieces(plot, level) do
		local l = p.light
		if l then
			local b = if lamp then lamp.Brightness else l.brightness
			local r = if lamp then lamp.Range else l.range
			table.insert(lights, { x = p.at[1], y = p.at[2], z = p.at[3], brightness = b, range = r })
			strongest, longest = math.max(strongest, b), math.max(longest, r)
		end
	end
	local inside = WarehouseLayout.inside(plot, level)
	local peak, sum, n = 0, 0, 0
	for i = 0, 16 do
		for j = 0, 16 do
			local x = inside.x0 + (inside.x1 - inside.x0) * i / 16
			local z = inside.z0 + (inside.z1 - inside.z0) * j / 16
			peak = math.max(peak, Rules.lux(lights, x, WarehouseLayout.FloorTop + CAP.HeadY, z))
			sum += Rules.lux(lights, x, WarehouseLayout.FloorTop, z)
			n += 1
		end
	end
	return { peak = peak, floor = sum / n, load = Rules.load(lights), count = #lights, strongest = strongest, longest = longest }
end

do
	local seen = 0
	local eyes = 2 ^ L.Places.warehouse.Exposure
	-- 8.3: every warehouse level's hall (Config.WarehouseLevels: the Garage's 1 lamp … the Logistics centre's 12, where
	-- the owner's Blender lamps hang; Config.SandboxLight.Warehouse.Levels their light). The Caps are level 4's hall's
	-- (6 lamps hanging `hang` over the floor): a level's load cap is HallLoad × its lamps / level 4's, and a hall whose
	-- lamps hang higher gets their reach in proportion (Range and the load × its hang / level 4's: they must reach its
	-- floor); its lamps no denser on its floor than level 4's × LAMP_DENSITY (one lamp at least). A bigger hall is no
	-- brighter: the peak at a face's height and the floor are held to the same Caps on every level.
	local LEVELS = Config.WarehouseLevels.List
	local LAMP_DENSITY = 1.4 -- (tests/warehouse_test.luau's bound: the Workshop's 2 and the Warehouse's 4 a third denser)
	local function lampsOf(n: number): (number, number)
		local count, hang = 0, 0
		for _, p in WarehouseLayout.pieces(SandboxMap.Plots[1], n) do
			if p.light then
				count += 1
				hang = math.max(hang, p.at[2] - WarehouseLayout.FloorTop)
			end
		end
		return count, hang
	end
	local fourLamps, fourHang = lampsOf(4)
	local fourArea = LEVELS[4].size[1] * LEVELS[4].size[3]
	for n, def in LEVELS do
		local lamps, hang = lampsOf(n)
		local higher = math.max(1, hang / fourHang)
		local cap, reach = CAP.HallLoad * lamps / fourLamps * higher, CAP.Range * higher
		local area = def.size[1] * def.size[3]
		check(`level {n} ({def.name}): {lamps} lamps {string.format("%.1f", hang)} over the floor, at most {LAMP_DENSITY} × level 4's per floor (one a {math.floor(fourArea / fourLamps)} studs²) or one`,
			lamps >= 1 and lamps <= math.max(1, LAMP_DENSITY * area * fourLamps / fourArea), lamps / area * fourArea / fourLamps)
		for _, plot in SandboxMap.Plots do
			local m = hall(plot, nil, n)
			seen += 1
			local tag = `plot {plot.id}'s hall at level {n}`
			check(`{tag}: {m.count} lamps, each at most {CAP.Brightness} bright and {string.format("%.1f", reach)} long ({m.longest})`, m.count > 0 and m.strongest <= CAP.Brightness and m.longest <= reach)
			check(`{tag}: Σ brightness × range {string.format("%.1f", m.load)} ≤ {string.format("%.1f", cap)} (HallLoad × {m.count} / {fourLamps}{if higher > 1 then string.format(" × %.2f", higher) else ""})`, m.load <= cap + 1e-9, m.load)
			check(`{tag}: at a face's height at most {CAP.Peak} on screen ({string.format("%.2f", m.peak * eyes)})`, m.peak * eyes <= CAP.Peak, m.peak * eyes)
			check(`{tag}: its floor not dark (a mean of {string.format("%.2f", m.floor)})`, m.floor >= CAP.Floor, m.floor)
		end
	end
	check("every plot's hall measured at every level", seen == #SandboxMap.Plots * #LEVELS and seen > 0)
	check("level 4's hall is the one HallLoad was measured on (6 lamps)", fourLamps == 6)
	-- 8.2's hall (6 lamps of 1.3 out to 40, never shadowed): the flashbang the caps now stop
	local old = hall(SandboxMap.Plots[1], { Brightness = 1.3, Range = 40 }, 4)
	check(`8.2's hall breaks the caps (peak {string.format("%.2f", old.peak)}, load {old.load}): they bite`, old.peak > CAP.Peak and old.load > CAP.HallLoad)

	-- the hall's Neon (8.3: every level's): its lamps' discs face the floor, small and not white; nothing bigger glows bright
	local bad: { string } = {}
	for n in LEVELS do
		for _, p in WarehouseLayout.pieces(SandboxMap.Plots[1], n) do
			if p.material == "Neon" then
				local s = p.size
				local down = if p.shape == "Cylinder" then math.pi * (math.min(s[2], s[3]) / 2) ^ 2 else math.max(s[1] * s[3], s[1] * s[2], s[2] * s[3])
				if down > CAP.NeonArea and Rules.luma(p.color) > CAP.NeonLuma then
					table.insert(bad, `{p.name}@{n} {math.floor(down)} studs²`)
				elseif Rules.luma(p.color) > CAP.GlowLuma then
					table.insert(bad, `{p.name}@{n} luma {math.floor(Rules.luma(p.color))}`)
				end
			end
		end
	end
	check("every level's hall Neon: no face over NeonArea bright, no lamp glow whiter than GlowLuma", #bad == 0, table.concat(bad, ", "))
	check("the lamps' own Neon (the house's discs and tube, the hall's discs, the Blender hall's lamps) under GlowLuma; 8.2's over it",
		Rules.luma(L.House.Glow) <= CAP.GlowLuma and Rules.luma(L.House.Tube) <= CAP.GlowLuma and Rules.luma(L.Warehouse.Glow) <= CAP.GlowLuma
			and Rules.luma(L.Warehouse.MeshGlow) <= CAP.GlowLuma and Rules.luma({ 255, 244, 224 }) > CAP.GlowLuma and Rules.luma({ 255, 241, 214 }) > CAP.GlowLuma)
	check("the house's daylight Neon (the windows, the porch's wall: big faces) at most NeonLuma; 8.2's porch over it",
		Rules.luma(L.House.Window) <= CAP.NeonLuma and Rules.luma(L.House.BathWindow) <= CAP.NeonLuma and Rules.luma(L.House.Daylight) <= CAP.NeonLuma
			and Rules.luma({ 236, 240, 228 }) > CAP.NeonLuma)
end

do -- the van's walk-in bay: its one light, close over your head
	local function bay(b: number, r: number): number
		local box, at = SprinterLooks.Bay, SprinterLooks.Light
		local lights = { { x = at[1], y = at[2], z = at[3], brightness = b, range = r } }
		local peak = 0
		for i = 0, 6 do
			for j = 0, 6 do
				local x = box.x0 + 0.5 + (box.x1 - box.x0 - 1) * i / 6
				local z = box.z0 + 0.5 + (box.z1 - box.z0 - 1) * j / 6
				peak = math.max(peak, Rules.lux(lights, x, box.y0 + CAP.HeadY, z))
			end
		end
		return peak
	end
	local v = L.Van.Bay
	local now = bay(v.Brightness, v.Range) * 2 ^ L.Places.van.Exposure
	check(`the van's bay light: one light within the caps, at a face's height {string.format("%.2f", now)} on screen`, v.Brightness <= CAP.Brightness and v.Range <= CAP.Range and now <= CAP.Peak, now)
	check(`… and it still lights the bay (the floor's far corner within its range)`, (function(): boolean
		local box, at = SprinterLooks.Bay, SprinterLooks.Light
		local far = math.sqrt((box.x1 - at[1]) ^ 2 + (box.y0 - at[2]) ^ 2 + math.max(box.z1 - at[3], at[3] - box.z0) ^ 2)
		return v.Range >= far - 1
	end)())
	check("8.2's bay light (1.4 out to 13) breaks the cap", bay(1.4, 13) > CAP.Peak)
end

do -- the house's numbers (the rooms themselves: tests/sandboxlight_runtime_test.luau)
	local h = L.House
	check("the house's lamps: each within the caps, two in a room longer than Long, a room's two within RoomLoad",
		h.Lamp.Brightness <= CAP.Brightness and h.Lamp.Range <= CAP.Range and 2 * h.Lamp.Brightness * h.Lamp.Range <= CAP.RoomLoad and h.Lamp.Long >= 2 * 8)
	check("the porch's daylight: a modest SurfaceLight", h.Porch.Brightness <= CAP.Brightness and h.Porch.Range <= CAP.Range)
	check("8.2's one ceiling lamp (0.9 out to 30) already breaks a room's budget", 0.9 * 30 > CAP.RoomLoad)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
