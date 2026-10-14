--!strict
-- 8.3 SANDBOX, the light (the owner: "too bright: in the house I cannot see my own character, the warehouse is a
-- flashbang"): the rules of the sandbox's light, its numbers Config.SandboxLight's. Pure (no Roblox at its top level):
-- client/SandboxLight.luau eases the screen with them; tests/sandboxlight_test.luau and
-- tests/sandboxlight_runtime_test.luau measure the house's, the hall's and the van's lights with the same model.
--
--   SandboxLightRules.Places                  the places the eyes know: "outdoors", "house", "warehouse", "van"
--   SandboxLightRules.place(x, y, z, inside, inVan)   where you are for the eyes: "van" in a Sprinter's walk-in bay, else
--                                             what the sandbox's sounds say (shared/SoundPlan.luau sandboxPlace: inside
--                                             the move's house, far off the map where the interiors stand, in a plot's
--                                             warehouse, else outdoors)
--   SandboxLightRules.look(place, lite?)      the place's whole look (Config.SandboxLight.Places over Sky.Exposure; an
--                                             unknown place outdoors'): exposure, bloom, size, threshold, brightness,
--                                             contrast, saturation, tint { r, g, b }, rays. lite: a phone's bloom
--                                             (× LiteBloom)
--   SandboxLightRules.ease(from, to, dt)      one step of the eyes (a new look): every number moved from `from` toward
--                                             `to` by 1 - e^(-3 dt / Ease) of the way (95 % in Ease s), dt at most Step
--                                             (a hitch never jumps); never past `to`
--   SandboxLightRules.settled(a, b)           are two looks the same as far as the screen shows (nothing to write)?
--   SandboxLightRules.copy(look)              a look of its own (its tint too)
--   SandboxLightRules.inBay(dx, dy, dz)       is a point inside the Sprinter's walk-in bay? (dx, dy, dz: from its
--                                             BayLight, in the van's frame: shared/SprinterLooks.luau's Bay and Light)
--   SandboxLightRules.falloff(d, range)       a light's share at d studs: (1 - (d / range)²)² inside its range, else 0
--                                             (the model the budget is held in: smooth to nothing at its range)
--   SandboxLightRules.lux(lights, x, y, z)    the light at a point: Σ brightness × falloff (lights: { x, y, z,
--                                             brightness, range })
--   SandboxLightRules.load(lights)            Σ brightness × range (a room's or a hall's light budget)
--   SandboxLightRules.luma(color)             a { r, g, b } colour's luma (Rec. 709, 0 … 255)

local Config = require(script.Parent.Config)
local SoundPlan = require(script.Parent.SoundPlan)
local SprinterLooks = require(script.Parent.SprinterLooks)

local L = Config.SandboxLight

local SandboxLightRules = {}

SandboxLightRules.Places = { "outdoors", "house", "warehouse", "van" }

export type Look = {
	exposure: number,
	bloom: number,
	size: number,
	threshold: number,
	brightness: number,
	contrast: number,
	saturation: number,
	tint: { number },
	rays: number,
}
export type Light = { x: number, y: number, z: number, brightness: number, range: number }

local SLACK = 0.5 -- studs round the bay's box that still count as in it (a body against its lining)

-- ── Where you are ─────────────────────────────────────────────────────────────

function SandboxLightRules.place(x: number, y: number, z: number, inside: boolean, inVan: boolean): string
	if inVan and not inside then
		return "van"
	end
	return SoundPlan.sandboxPlace(x, y, z, inside)
end

function SandboxLightRules.inBay(dx: number, dy: number, dz: number): boolean
	local bay, light = SprinterLooks.Bay, SprinterLooks.Light
	return dx >= bay.x0 - light[1] - SLACK and dx <= bay.x1 - light[1] + SLACK
		and dy >= bay.y0 - light[2] - SLACK and dy <= bay.y1 - light[2] + SLACK
		and dz >= bay.z0 - light[3] - SLACK and dz <= bay.z1 - light[3] + SLACK
end

-- ── The looks ─────────────────────────────────────────────────────────────────

function SandboxLightRules.look(place: string, lite: boolean?): Look
	local p = (L.Places :: any)[place] or L.Places.outdoors
	local tint = p.Grade.Tint
	return {
		exposure = L.Sky.Exposure + p.Exposure,
		bloom = p.Bloom.Intensity * (if lite then L.LiteBloom else 1),
		size = p.Bloom.Size,
		threshold = p.Bloom.Threshold,
		brightness = p.Grade.Brightness,
		contrast = p.Grade.Contrast,
		saturation = p.Grade.Saturation,
		tint = { tint[1], tint[2], tint[3] },
		rays = p.Rays,
	}
end

function SandboxLightRules.copy(look: Look): Look
	local c = table.clone(look)
	c.tint = table.clone(look.tint)
	return c
end

local FIELDS = { "exposure", "bloom", "size", "threshold", "brightness", "contrast", "saturation", "rays" }

function SandboxLightRules.ease(from: Look, to: Look, dt: number): Look
	local step = math.clamp(dt, 0, L.Step)
	local share = 1 - math.exp(-3 * step / math.max(L.Ease, 1e-3))
	local out = SandboxLightRules.copy(from)
	local o = out :: any
	local a, b = from :: any, to :: any
	for _, key in FIELDS do
		o[key] = a[key] + (b[key] - a[key]) * share
	end
	for i = 1, 3 do
		out.tint[i] = from.tint[i] + (to.tint[i] - from.tint[i]) * share
	end
	return out
end

-- (what a write would show: a hundredth of a stop, a hundredth of the grade, a fifth of a pixel of bloom, a colour step)
local CLOSE: { [string]: number } = { exposure = 0.003, bloom = 0.003, size = 0.2, threshold = 0.005, brightness = 0.002, contrast = 0.002, saturation = 0.002, rays = 0.002 }

function SandboxLightRules.settled(a: Look, b: Look): boolean
	local x, y = a :: any, b :: any
	for _, key in FIELDS do
		if math.abs(x[key] - y[key]) > CLOSE[key] then
			return false
		end
	end
	for i = 1, 3 do
		if math.abs(a.tint[i] - b.tint[i]) > 0.5 then
			return false
		end
	end
	return true
end

-- ── The model (the budget) ────────────────────────────────────────────────────

function SandboxLightRules.falloff(d: number, range: number): number
	if range <= 0 or d >= range then
		return 0
	end
	local q = 1 - (d / range) ^ 2
	return q * q
end

function SandboxLightRules.lux(lights: { Light }, x: number, y: number, z: number): number
	local sum = 0
	for _, l in lights do
		sum += l.brightness * SandboxLightRules.falloff(math.sqrt((l.x - x) ^ 2 + (l.y - y) ^ 2 + (l.z - z) ^ 2), l.range)
	end
	return sum
end

function SandboxLightRules.load(lights: { Light }): number
	local sum = 0
	for _, l in lights do
		sum += l.brightness * l.range
	end
	return sum
end

function SandboxLightRules.luma(c: { number }): number
	return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
end

return SandboxLightRules
