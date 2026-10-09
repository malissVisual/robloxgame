--!strict
-- 6.14: the GPS to a place by its id: one of Map.Shops (the counters: "bikes", "supplies" …) or Map.Landmarks ("earl",
-- an employer, a mission place). It sets the white route on both maps (MapView.setWaypoint) and the HUD's beam and label
-- (MapView.onWaypoint, set by client/Hud.luau), the way the phone's SHOP always did (client/Phone.luau gpsTo uses it).
-- The READY CHECK's rows (client/ReadyCheck.luau) and the level-up card's GPS buttons (client/CareerUi.luau) too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Map = require(Shared.Map)
local MapView = require(script.Parent.MapView)

local Gps = {}

-- The place's spot and name, nil when the id is neither a shop nor a landmark. 6.14 review: or a property of
-- Config.Estate (Map.EstatePlots: the garage where one of your cars waits, the READY CHECK's cargo row).
function Gps.find(id: string): (number?, number?, string?, Map.Landmark?)
	local shop = Map.Shops[id]
	local landmark: Map.Landmark? = nil
	for _, entry in Map.Landmarks do
		if entry.id == id then
			landmark = entry
		end
	end
	local x = if shop then shop.x elseif landmark then landmark.x else nil
	local z = if shop then shop.z elseif landmark then landmark.z else nil
	local name = if shop then shop.name elseif landmark then landmark.name else nil
	local plot = if x == nil then Map.EstatePlots[id] else nil
	if plot then
		x, z = plot.x, plot.z
		for _, def in Config.Estate.Properties do
			if def.id == id then
				name = def.name
			end
		end
	end
	return x, z, name, landmark
end

-- Sets the GPS there; returns the place's name (nil: no such place, nothing changed).
function Gps.to(id: string): string?
	local x, z, name, landmark = Gps.find(id)
	if x == nil or z == nil then
		return nil
	end
	MapView.setWaypoint(Vector3.new(x, Map.RoadTop, z))
	pcall(function()
		MapView.onWaypoint(landmark or { id = id, name = name or id, icon = if Map.EstatePlots[id] or id == "depot" then "🅿" else "🛒", x = x :: number, z = z :: number, kind = "shop", description = "" })
	end)
	return name
end

return Gps
