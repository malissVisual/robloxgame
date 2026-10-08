--!strict
-- 6.12.2, the JOBS spot (the owner: "where I have the spawn and the jobs, make the jobs have a proper look"): the
-- depot's job board (server/World.luau buildDepot: its "jobs" prompt, Config.Goal.BoardSpot, the client's board marker)
-- stays where it is, and a dispatch booth is built round it that reads from the yard: a dark back panel with ZDC red
-- edges, a canopy over the board with its red fascia and a lamp, a big JOBS sign on the canopy that glows at night
-- (DayNight.nightLight on the frame behind it), a ticker over the board, two screens beside it, a floor mat with a red
-- edge, a bench and a stack of ZDC parcels to the west. Native parts, about 30; what could be walked into is
-- non-colliding (deco), the bench, the parcels and the panel behind the board are solid. Nothing of it reaches Marge
-- (Config.Tutorial.NpcSpot, east of the board), the garage terminal or the spawn.
--
-- server/World.luau's buildDepot calls JobsSpot.build with the board and its own helpers (no new top-level locals
-- there: the -O0 register limit), as it does for server/GearStall.luau.

local JobsSpot = {}

export type Tools = {
	part: (parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?) -> Part,
	deco: (p: Part) -> Part,
	sign: (parent: Instance, text: string, size: Vector3, cframe: CFrame, color: Color3, background: Color3?, art: string?, artHeight: number?) -> (),
	prompt: (parent: BasePart, shop: string, action: string, object: string) -> (),
	nightLight: (item: Instance, lit: Color3?, dim: Color3?, dimMaterial: string?) -> (),
}

local RED = Color3.fromRGB(190, 44, 38) -- the ZDC red (the depot's accents, the gear stall's awning)
local CREAM = Color3.fromRGB(236, 230, 214)
local CHARCOAL = Color3.fromRGB(38, 43, 47)
local SCREEN = Color3.fromRGB(14, 24, 34)
local WIDE = 24 -- the booth's width (the board is 14)

-- Builds the booth under `parent` (the depot's folder) round `board` (the JobBoard part: its front, -Z, faces the yard).
function JobsSpot.build(parent: Instance, board: BasePart, tools: Tools)
	local part, deco = tools.part, tools.deco
	local folder = Instance.new("Folder")
	folder.Name = "JobsSpot"
	folder.Parent = parent
	-- The booth's frame: the board's middle on the walk (y = the board's bottom - 1: World stands it 1 stud up), -Z out.
	local f = CFrame.new(board.Position.X, board.Position.Y - board.Size.Y / 2 - 1, board.Position.Z) * board.CFrame.Rotation
	-- The floor mat in front of the board and its red edge (flat: deco).
	deco(part(folder, "FloorMat", Vector3.new(WIDE, 0.08, 8), f * CFrame.new(0, 0.04, -3), CHARCOAL, Enum.Material.SmoothPlastic))
	deco(part(folder, "FloorEdge", Vector3.new(WIDE, 0.1, 0.4), f * CFrame.new(0, 0.05, -6.8), RED, Enum.Material.SmoothPlastic))
	-- The back panel behind the board (solid) with red edges.
	part(folder, "BackPanel", Vector3.new(WIDE, 11.6, 0.4), f * CFrame.new(0, 5.8, 1), CHARCOAL, Enum.Material.Metal)
	for _, side in { -1, 1 } do
		deco(part(folder, "PanelEdge", Vector3.new(0.5, 11.6, 0.12), f * CFrame.new(side * (WIDE / 2 - 0.25), 5.8, 0.74), RED, Enum.Material.Metal))
		-- the braces from the panel up to the canopy's front
		local from, to = Vector3.new(side * (WIDE / 2 - 1), 8.6, 0.7), Vector3.new(side * (WIDE / 2 - 1), 11.6, -5.6)
		deco(part(folder, "CanopyBrace", Vector3.new(0.3, 0.3, (to - from).Magnitude), f * CFrame.lookAt((from + to) / 2, to), CHARCOAL, Enum.Material.Metal))
	end
	-- The canopy over the board, its red fascia with a cream line, the lamp under it (warm at night). (Low enough that
	-- the JOBS sign on it stays under the hall front's DISPATCH plate, seen from the yard and the street.)
	part(folder, "Canopy", Vector3.new(WIDE + 1, 0.5, 7.6), f * CFrame.new(0, 11.85, -2.6), CHARCOAL, Enum.Material.Metal)
	deco(part(folder, "CanopyFascia", Vector3.new(WIDE + 1, 1.1, 0.3), f * CFrame.new(0, 11.35, -6.5), RED, Enum.Material.Metal))
	deco(part(folder, "CanopyLine", Vector3.new(WIDE + 1, 0.18, 0.32), f * CFrame.new(0, 11.5, -6.52), CREAM, Enum.Material.Metal))
	local lamp = deco(part(folder, "Lamp", Vector3.new(WIDE - 6, 0.2, 0.6), f * CFrame.new(0, 11.5, -4.6), Color3.fromRGB(156, 146, 122), Enum.Material.Glass))
	local glow = Instance.new("SpotLight")
	glow.Face = Enum.NormalId.Bottom
	glow.Range = 16
	glow.Brightness = 1.4
	glow.Angle = 100
	glow.Color = Color3.fromRGB(255, 226, 170)
	glow.Shadows = false
	glow.Parent = lamp
	tools.nightLight(lamp, Color3.fromRGB(255, 220, 150), lamp.Color, "Glass")
	-- The big JOBS sign on the canopy, facing the yard: red with cream letters, a frame behind it that glows at night.
	local frame = deco(part(folder, "JobsSignGlow", Vector3.new(15.8, 4.2, 0.2), f * CFrame.new(0, 14.2, -5.3), CHARCOAL, Enum.Material.Metal))
	tools.nightLight(frame, Color3.fromRGB(255, 196, 70), frame.Color, "Metal")
	tools.sign(folder, "JOBS", Vector3.new(15, 3.6, 0.4), f * CFrame.new(0, 14.25, -5.6), CREAM, RED)
	-- The ticker over the board and the two screens beside it (their text lit, LightInfluence 0; the bezels glow at night).
	tools.sign(folder, "TAKE A JOB · DELIVER · GET PAID", Vector3.new(14, 1.6, 0.3), f * CFrame.new(0, 10.4, 0.65), Color3.fromRGB(255, 214, 120), SCREEN)
	for _, screen in { { x = 9.4, text = "NEW RUNS", lit = Color3.fromRGB(120, 230, 255) }, { x = -9.4, text = "TOP PAY", lit = Color3.fromRGB(255, 214, 120) } } do
		local bezel = deco(part(folder, "ScreenBezel", Vector3.new(4.1, 2.8, 0.15), f * CFrame.new(screen.x, 6.2, 0.72), CHARCOAL, Enum.Material.Metal))
		tools.nightLight(bezel, screen.lit, bezel.Color, "Metal")
		tools.sign(folder, screen.text, Vector3.new(3.8, 2.4, 0.2), f * CFrame.new(screen.x, 6.2, 0.6), screen.lit, SCREEN)
	end
	-- A bench to the west of the booth, facing the yard, and a stack of ZDC parcels behind it (solid).
	local bench = f * CFrame.new(16, 0, -2)
	part(folder, "BenchSeat", Vector3.new(5, 0.35, 1.5), bench * CFrame.new(0, 1.6, 0), Color3.fromRGB(128, 94, 62), Enum.Material.WoodPlanks)
	deco(part(folder, "BenchBack", Vector3.new(5, 1.3, 0.25), bench * CFrame.new(0, 2.6, 0.7), Color3.fromRGB(128, 94, 62), Enum.Material.WoodPlanks))
	for _, side in { -1, 1 } do
		deco(part(folder, "BenchLeg", Vector3.new(0.35, 1.45, 1.3), bench * CFrame.new(side * 2.1, 0.72, 0), CHARCOAL, Enum.Material.Metal))
	end
	local cardboard = Color3.fromRGB(196, 152, 98)
	part(folder, "Parcel", Vector3.new(2.6, 2.2, 2.2), f * CFrame.new(16.6, 1.1, 2.2), cardboard, Enum.Material.SmoothPlastic)
	part(folder, "Parcel", Vector3.new(2.1, 1.7, 1.9), f * CFrame.new(16.4, 3.05, 2.1) * CFrame.Angles(0, math.rad(14), 0), cardboard, Enum.Material.SmoothPlastic)
	part(folder, "Parcel", Vector3.new(1.9, 1.6, 1.8), f * CFrame.new(13.9, 0.8, 2.4), cardboard, Enum.Material.SmoothPlastic)
	deco(part(folder, "ParcelTape", Vector3.new(2.64, 0.3, 2.24), f * CFrame.new(16.6, 1.5, 2.2), RED, Enum.Material.SmoothPlastic))
	deco(part(folder, "ParcelTape", Vector3.new(1.94, 0.26, 1.84), f * CFrame.new(13.9, 1.0, 2.4), RED, Enum.Material.SmoothPlastic))
end

return JobsSpot
