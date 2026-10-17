-- 8.2: what a piece of the world costs to draw, counted the same way on both Roblox stand-ins (tools/perf/world-mock.luau
-- and tools/vehicle-preview/roblox-mock.luau): only the class names and the properties are read, never IsA. Used by
-- tools/perf/sandbox_count.py (design/performance/REPORT.md).
--   Census.of(instances)        a row: the counts over a list of instances (Census.Keys)
--   Census.list(root)           root and everything under it; Census.under(root) its row
--   Census.detail(instances)    the costly ones by name, one line a kind
--   Census.line(label, row)     the row as one line "ROW <label>\t<json>" (the Python side reads it and sums)
--   Census.modes(root)          the Models under root by their ModelStreamingMode ("Default" when none is set)
local Census = {}

local PARTS = {
	Part = true, WedgePart = true, CornerWedgePart = true, TrussPart = true, SpawnLocation = true, Seat = true,
	VehicleSeat = true, MeshPart = true, UnionOperation = true, PartOperation = true,
}
local LIGHTS = { PointLight = true, SpotLight = true, SurfaceLight = true }
local EFFECTS = { Fire = true, Smoke = true, Sparkles = true }

-- The keys of a row, in the order the report lists them.
Census.Keys = {
	"parts", "meshParts", "specialMeshes", "visible", "seeThrough", "hidden", "shadows", "smallShadows",
	"lights", "lightsOn", "lightsShadowed", "pointLights", "spotLights", "surfaceLights",
	"surfaceGuis", "surfaceGuisFar", "billboards", "billboardsFar", "particles", "beams", "trails", "effects",
	"decals", "prompts",
}

local function newRow(): { [string]: number }
	local row = {}
	for _, key in Census.Keys do
		row[key] = 0
	end
	return row
end

local function read(instance: any, key: string): any
	local ok, value = pcall(function()
		return instance[key]
	end)
	return if ok then value else nil
end

-- RenderBudget's size rule (shared/RenderBudget.luau): a shadow is worth it from a part whose longest side is 2 studs
-- and whose second side is 0.45; a caster under that is "small".
local function small(size: any): boolean
	if size == nil then
		return false
	end
	local x, y, z = size.X, size.Y, size.Z
	local long = math.max(x, y, z)
	local short = math.min(x, y, z)
	local middle = x + y + z - long - short
	return long < 2 or middle < 0.45
end

local function far(distance: any): boolean
	return distance == nil or distance == 0 or distance >= 10000
end

function Census.of(list: { any }): { [string]: number }
	local row = newRow()
	for _, d in list do
		local class = read(d, "ClassName")
		if PARTS[class] then
			row.parts += 1
			if class == "MeshPart" then
				row.meshParts += 1
			end
			local t = read(d, "Transparency") or 0
			if t >= 1 then
				row.hidden += 1
			else
				row.visible += 1
				if t > 0 then
					row.seeThrough += 1
				end
				if read(d, "CastShadow") ~= false then
					row.shadows += 1
					if small(read(d, "Size")) then
						row.smallShadows += 1
					end
				end
			end
		elseif class == "SpecialMesh" then
			row.specialMeshes += 1
		elseif LIGHTS[class] then
			row.lights += 1
			if read(d, "Enabled") ~= false then
				row.lightsOn += 1
			end
			if read(d, "Shadows") == true then
				row.lightsShadowed += 1
			end
			if class == "PointLight" then
				row.pointLights += 1
			elseif class == "SpotLight" then
				row.spotLights += 1
			else
				row.surfaceLights += 1
			end
		elseif class == "SurfaceGui" then
			row.surfaceGuis += 1
			if far(read(d, "MaxDistance")) then
				row.surfaceGuisFar += 1
			end
		elseif class == "BillboardGui" then
			row.billboards += 1
			if far(read(d, "MaxDistance")) then
				row.billboardsFar += 1
			end
		elseif class == "ParticleEmitter" then
			row.particles += 1
		elseif class == "Beam" then
			row.beams += 1
		elseif class == "Trail" then
			row.trails += 1
		elseif EFFECTS[class] then
			row.effects += 1
		elseif class == "Decal" or class == "Texture" then
			row.decals += 1
		elseif class == "ProximityPrompt" then
			row.prompts += 1
		end
	end
	return row
end

function Census.under(root: any): { [string]: number }
	return Census.of(Census.list(root))
end

-- root and everything under it
function Census.list(root: any): { any }
	local list = root:GetDescendants()
	table.insert(list, root)
	return list
end

-- What the costly ones are, by name (a part's own, a gui's or a light's part's): the small shadow casters, the
-- see-through parts, the lights with Shadows on, the lights that are on, the SurfaceGuis drawn at any distance.
-- Returns one line per kind: "<kind>: <name> ×n, …" (the most first).
function Census.detail(list: { any }): { string }
	local kinds: { [string]: { [string]: number } } = { small = {}, seeThrough = {}, shadowedLights = {}, lightsOn = {}, farGuis = {} }
	local function note(kind: string, name: string)
		kinds[kind][name] = (kinds[kind][name] or 0) + 1
	end
	for _, d in list do
		local class = read(d, "ClassName")
		local name = tostring(read(d, "Name"))
		local parent = read(d, "Parent")
		local owner = if parent then tostring(read(parent, "Name")) else "?"
		if PARTS[class] then
			local t = read(d, "Transparency") or 0
			if t < 1 and t > 0 then
				note("seeThrough", name)
			end
			if t < 1 and read(d, "CastShadow") ~= false and small(read(d, "Size")) then
				note("small", name)
			end
		elseif LIGHTS[class] then
			if read(d, "Shadows") == true then
				note("shadowedLights", `{class} in {owner}`)
			end
			if read(d, "Enabled") ~= false then
				note("lightsOn", `{class} in {owner}`)
			end
		elseif class == "SurfaceGui" and far(read(d, "MaxDistance")) then
			note("farGuis", `{name} on {owner}`)
		end
	end
	local lines = {}
	for _, kind in { "small", "seeThrough", "shadowedLights", "lightsOn", "farGuis" } do
		local names = {}
		for name, n in kinds[kind] do
			table.insert(names, { name = name, n = n })
		end
		if #names > 0 then
			table.sort(names, function(a, b)
				return if a.n == b.n then a.name < b.name else a.n > b.n
			end)
			local parts = {}
			for i, entry in names do
				if i > 12 then
					table.insert(parts, "…")
					break
				end
				table.insert(parts, `{entry.name} ×{entry.n}`)
			end
			table.insert(lines, `{kind}: {table.concat(parts, ", ")}`)
		end
	end
	return lines
end

function Census.line(label: string, row: { [string]: number }): string
	local fields = {}
	for _, key in Census.Keys do
		table.insert(fields, `"{key}":{row[key] or 0}`)
	end
	return "ROW " .. label .. "\t{" .. table.concat(fields, ",") .. "}"
end

function Census.modes(root: any): { [string]: number }
	local modes: { [string]: number } = {}
	for _, d in root:GetDescendants() do
		if read(d, "ClassName") == "Model" then
			local mode = read(d, "ModelStreamingMode")
			local name = if mode == nil then "Default" elseif type(mode) == "string" then mode else tostring(read(mode, "Name") or mode)
			modes[name] = (modes[name] or 0) + 1
		end
	end
	return modes
end

return Census
