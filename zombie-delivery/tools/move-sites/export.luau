-- The ZDC dispatch kiosk: the real server/MoveSites.luau run on the recorder (tools/fixtures/item-mock.luau over
-- tools/vehicle-preview/roblox-mock.luau) in the Luau CLI, as server/LobbyWorld.luau calls it (MoveSites.kiosk at
-- SandboxMap.Lobby.dispatch). One JSON line a part (where, its turn, size, colour, material, shape, flags, its lights,
-- its text), then a summary. check.py writes MoveSitesServer.luau and the shared modules next to it and checks the
-- lines. 10.6: the city's moving world (the depot's kiosk, the Wall's checkpoint, the houses, the farm, the banner, the
-- evacuation spots, the plots' kiosks) went with the city.
local M = require("./ItemMock")
local MoveSites = require("./MoveSitesServer")
local Looks = require("./MoveSiteLooks")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")

local function encode(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		return string.format("%.5f", v)
	elseif type(v) == "boolean" then
		return tostring(v)
	elseif type(v) == "table" then
		local out = {}
		if #v > 0 then
			for _, x in v do
				table.insert(out, encode(x))
			end
			return "[" .. table.concat(out, ",") .. "]"
		end
		for k, x in v do
			table.insert(out, encode(tostring(k)) .. ":" .. encode(x))
		end
		return "{" .. table.concat(out, ",") .. "}"
	elseif v == nil then
		return "null"
	end
	error("unsupported " .. type(v))
end

local function rgb(c: any): { number }
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end
local function v3(v: any): { number }
	return { v.X, v.Y, v.Z }
end

local function wordsOf(p: any): { any }
	local list = {}
	for _, gui in p:GetChildren() do
		if gui.ClassName == "SurfaceGui" then
			local entry: any = { face = gui.Face, pps = gui.PixelsPerStud, range = gui.MaxDistance, light = gui.LightInfluence, lines = {} }
			local holder = gui
			local back = gui:FindFirstChild("Back")
			if back then
				entry.back = rgb(back.BackgroundColor3)
				entry.inset = back.Position[1]
				holder = back
			end
			for _, label in holder:GetChildren() do
				if label.ClassName == "TextLabel" then
					table.insert(entry.lines, { text = label.Text, color = rgb(label.TextColor3), size = label.Size[2], font = label.Font, order = label.LayoutOrder, scaled = label.TextScaled })
				end
			end
			table.sort(entry.lines, function(a: any, b: any): boolean
				return a.order < b.order
			end)
			table.insert(list, entry)
		end
	end
	return list
end

local count = 0
local function exportPart(set: string, model: string, p: any, kind: string?)
	local lights = {}
	for _, child in p:GetChildren() do
		if child.ClassName == "PointLight" then
			table.insert(lights, { range = child.Range, color = rgb(child.Color), night = child:GetAttribute("NightLight") == true, shadows = child.Shadows })
		end
	end
	local lit = p:GetAttribute("LitColor")
	print(encode({
		kind = kind or "part",
		set = set,
		model = model,
		name = p.Name,
		class = p.ClassName,
		position = v3(p.Position),
		rotation = p.CFrame.R,
		size = v3(p.Size),
		color = rgb(p.Color),
		material = p.Material,
		shape = if p.ClassName == "WedgePart" then "Wedge" else p.Shape or "Block",
		transparency = p.Transparency,
		anchored = p.Anchored,
		collide = p.CanCollide,
		query = p.CanQuery,
		touch = p.CanTouch,
		shadow = p.CastShadow,
		night = p:GetAttribute("NightLight") == true,
		lit = if lit then rgb(lit) else nil,
		lights = lights,
		words = wordsOf(p),
	}))
	if kind == nil then
		count += 1
	end
end

local function exportModel(set: string, model: any)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			exportPart(set, model.Name, p)
		end
	end
end

-- ── The kiosk, built as server/LobbyWorld.luau builds it ──────────────────────────────────────────────────────────────

local world = M.Instance.new("Folder")
world.Name = "Lobby"
local spot = SandboxMap.Lobby.dispatch
local model, corkboard = MoveSites.kiosk(world, spot, "ZdcDispatch")
exportModel("kiosk", model)
print(encode({
	kind = "summary",
	parts = count,
	pieces = #Looks.board(),
	budget = Config.MoveSites.Budget,
	lights = Config.MoveSites.Lights,
	textRange = Config.MoveSites.TextRange,
	mode = tostring(model.ModelStreamingMode),
	primary = if model.PrimaryPart then model.PrimaryPart.Name else nil,
	corkboard = corkboard.Name,
	spot = { spot.x, spot.z },
	groundTop = SandboxMap.GroundTop,
}))
