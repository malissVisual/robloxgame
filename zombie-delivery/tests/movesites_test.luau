-- The ZDC dispatch kiosk (shared/MoveSiteLooks.luau, Config.MoveSites; server/MoveSites.luau builds it in the lobby,
-- server/LobbyWorld.luau at SandboxMap.Lobby.dispatch): sound pieces, the part and light budget, the corkboard solid
-- at a hand's height with the countryside's places to empty on it, nothing solid in front of it; its words the
-- sandbox's (nothing of the city's story: no Marge, no Walt, no Wall, no evacuation). 10.6: the city's moving world
-- (the Wall's checkpoint, the depot's kiosk and banner, the houses' moving-day dress, the evacuation spots, Walt's farm)
-- went with the city. In the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local Looks = require("./MoveSiteLooks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local t = Config.MoveSites
local pieces = Looks.board()
local spot = SandboxMap.Lobby.dispatch
local place: Looks.Place = { x = spot.x, y = spot.y, z = spot.z, yaw = spot.yaw }

-- Its words ------------------------------------------------------------------------------------------------------------

local all: { string } = {}
for _, p in pieces do
	for _, w in p.words or {} do
		for _, l in w.lines do
			table.insert(all, l.text)
		end
	end
end
local text = table.concat(all, " | ")
check(`the corkboard: {#SandboxMap.Houses} PLACES TO EMPTY, THE COUNTRYSIDE, WALK TO A PORTAL, the header DELIVEROS DISPATCH, "Bring it home to your warehouse." (no place by name)`,
	string.find(text, `{#SandboxMap.Houses} PLACES TO EMPTY`, 1, true) ~= nil and string.find(text, "THE COUNTRYSIDE", 1, true) ~= nil
	and string.find(text, "WALK TO A PORTAL", 1, true) ~= nil and string.find(text, "DELIVEROS DISPATCH", 1, true) ~= nil
	and string.find(text, "MOVING CONTRACTS", 1, true) == nil and string.find(text, "THE OLD FARMSTEAD", 1, true) == nil
	and string.find(text, "Bring it home to your warehouse.", 1, true) ~= nil, text)
check("…no Marge, no Walt, no Wall, no evacuation", string.find(text, "MARGE", 1, true) == nil and string.find(text, "WALT", 1, true) == nil
	and string.find(text, "Wall", 1, true) == nil and string.find(string.upper(text), "EVACUAT", 1, true) == nil, text)

-- Sound pieces ---------------------------------------------------------------------------------------------------------

local function finite(list: { number }, count: number): boolean
	if #list ~= count then
		return false
	end
	for _, n in list do
		if n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

local lights = 0
local bad: { string } = {}
local names: { [string]: boolean } = {}
for _, p in pieces do
	local where = p.name
	if names[p.name] then
		table.insert(bad, where .. " twice")
	end
	names[p.name] = true
	if not finite(p.size, 3) or not finite(p.at, 3) or not finite(p.color, 3) then
		table.insert(bad, where .. " numbers")
	end
	for _, n in p.size do
		if n < 0.04 or n > 64 then
			table.insert(bad, where .. " size")
		end
	end
	for _, n in p.color do
		if n < 0 or n > 255 then
			table.insert(bad, where .. " colour")
		end
	end
	if not table.find(Looks.Materials, p.material) then
		table.insert(bad, where .. " material " .. p.material)
	end
	if p.shape and not table.find(Looks.Shapes, p.shape) then
		table.insert(bad, where .. " shape")
	end
	if p.shape == "Cylinder" and math.abs(p.size[2] - p.size[3]) > 1e-9 then
		table.insert(bad, where .. " an oval cylinder")
	end
	if p.light then
		lights += 1
	end
	for _, w in p.words or {} do
		local share = 0
		for _, l in w.lines do
			share += l.size
			if l.text == "" or not finite(l.color, 3) then
				table.insert(bad, where .. " a line")
			end
		end
		if not table.find(Looks.Faces, w.face) or share > 1 or #w.lines == 0 then
			table.insert(bad, where .. " words on " .. w.face)
		end
	end
end
check("sound pieces: unique names, finite sizes and colours, known materials, round cylinders, text that fits", #bad == 0, table.concat(bad, ", "))
check(`the part budget: {#pieces} parts (Config.MoveSites.Budget {t.Budget})`, #pieces <= t.Budget and #pieces > 0, #pieces)
check(`the lights: {lights} (at most {t.Lights})`, lights <= t.Lights, lights)
check("the shadows: the big pieces only (the backing does, a pin does not)", (function(): boolean
	local backing, pin
	for _, p in pieces do
		if p.name == "Backing" then
			backing = Looks.shadow(p, SandboxMap.GroundTop)
		elseif p.name == "PhotoHousePin" then
			pin = Looks.shadow(p, SandboxMap.GroundTop)
		end
	end
	return backing == true and pin == false
end)())
check("the text range: at least Config.MoveSites.TextRange, more for a taller face", Looks.textRange(0.1) >= t.TextRange
	and Looks.textRange(4) >= Looks.textRange(1) and Looks.pixels(4, 2) >= 25 and Looks.pixels(4, 2) <= 100)

-- The corkboard --------------------------------------------------------------------------------------------------------

local board: Looks.Piece? = nil
for _, p in pieces do
	if p.name == "Board" then
		board = p
	end
end
check("the corkboard (the runs' prompt hangs on it) is solid", board ~= nil and board.solid == true)
if board then
	local x0, x1, y0, y1, z0, z1 = Looks.box(place, board)
	local mid = (y0 + y1) / 2 - SandboxMap.GroundTop
	check("…at a hand's height, its box finite", mid > 3.5 and mid < 6.5 and x1 > x0 and z1 > z0, mid)
end
-- nothing solid in front of it (the plaza's side: -Z in the kiosk's frame, 1.5 past the corkboard's face; its low plinth is its foot)
local front = {}
for _, p in pieces do
	if p.solid and p.at[3] - p.size[3] / 2 < (board and board.at[3] - board.size[3] / 2 or 0) - 1.5 then
		table.insert(front, p.name)
	end
end
check("nothing solid stands in front of the kiosk (the plaza's side)", #front == 0, table.concat(front, ", "))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
