-- 6.13.1: the counting side of tools/perf/world_count.py (copied next to the stand-in as main.luau): builds the city
-- with the real server/World.luau and prints what it made, piece by piece (design/performance/REPORT.md).
setfenv(1, require("./mock").env)
local Mock = require("./mock")
local World = require("./server/World")
local started = os.clock()
World.build()
print(string.format("build ran in %.1f s", os.clock() - started))

local ws = Mock.workspace
local function props(i)
	return rawget(i, "__props")
end
local function isPart(i)
	return Mock.PARTS[props(i).ClassName] == true
end
local function visible(i)
	return (props(i).Transparency or 0) < 1
end
local nightTagged = Mock.tags["NightLight"] or {}

type Row = { parts: number, visible: number, shadows: number, smallShadowless: number, lights: { [string]: number }, nightLights: number, alwaysLights: number, guis: number, guisFar: number }
local function newRow(): Row
	return { parts = 0, visible = 0, shadows = 0, smallShadowless = 0, lights = {}, nightLights = 0, alwaysLights = 0, guis = 0, guisFar = 0 }
end
local total = newRow()
local byPiece: { [string]: Row } = {}
local modes: { [string]: number } = {}
local depotParts = 0

local function count(row: Row, item)
	local p = props(item)
	if isPart(item) then
		row.parts += 1
		if visible(item) then
			row.visible += 1
			if p.CastShadow then
				row.shadows += 1
			end
		end
	elseif Mock.isA(p.ClassName, "Light") then
		row.lights[p.ClassName] = (row.lights[p.ClassName] or 0) + 1
		local parent = item.Parent
		if nightTagged[item] or (parent and nightTagged[parent]) then
			row.nightLights += 1
		else
			row.alwaysLights += 1
		end
	elseif p.ClassName == "SurfaceGui" then
		row.guis += 1
		if (p.MaxDistance or 0) == 0 or p.MaxDistance > 1000 then
			row.guisFar += 1
		end
	end
end

local function walk(item, piece: string?)
	for _, child in rawget(item, "__children") do
		local name = piece
		local cp = props(child)
		if cp.ClassName == "Model" then
			local mode = tostring(cp.ModelStreamingMode)
			modes[mode] = (modes[mode] or 0) + 1
		end
		count(total, child)
		if name then
			byPiece[name] = byPiece[name] or newRow()
			count(byPiece[name], child)
		end
		walk(child, name)
	end
end
local world = ws.World
for _, child in rawget(ws, "__children") do
	if child ~= world then
		local name = "workspace." .. props(child).Name
		byPiece[name] = byPiece[name] or newRow()
		count(total, child)
		count(byPiece[name], child)
		walk(child, name)
	end
end
if world then
	for _, child in rawget(world, "__children") do
		local name = props(child).Name
		byPiece[name] = byPiece[name] or newRow()
		count(total, child)
		count(byPiece[name], child)
		walk(child, name)
	end
end
-- The depot (its own count: the Persistent model)
for _, item in Mock.ALL do
	if props(item).Name == "Depot" and (props(item).ClassName == "Model" or props(item).ClassName == "Folder") and item.Parent then
		for _, d in item:GetDescendants() do
			if isPart(d) then
				depotParts += 1
			end
		end
	end
end

local function lightText(row: Row): string
	local out = {}
	for class, n in row.lights do
		table.insert(out, `{class} {n}`)
	end
	table.sort(out)
	return table.concat(out, ", ")
end
local names = {}
for name in byPiece do
	table.insert(names, name)
end
table.sort(names, function(a, b)
	return byPiece[a].parts > byPiece[b].parts
end)
print("piece | parts | visible | cast shadow | lights (night / always) | SurfaceGuis (no MaxDistance)")
for _, name in names do
	local r = byPiece[name]
	print(`{name} | {r.parts} | {r.visible} | {r.shadows} | {lightText(r)} ({r.nightLights} / {r.alwaysLights}) | {r.guis} ({r.guisFar})`)
end
print(`TOTAL | {total.parts} | {total.visible} | {total.shadows} | {lightText(total)} ({total.nightLights} / {total.alwaysLights}) | {total.guis} ({total.guisFar})`)
local modeText = {}
for mode, n in modes do
	table.insert(modeText, `{mode} {n}`)
end
table.sort(modeText)
print("models by streaming mode: " .. table.concat(modeText, ", "))
print(`depot parts: {depotParts}`)
local tagCount = 0
for _ in nightTagged do
	tagCount += 1
end
print(`NightLight-tagged instances: {tagCount}`)

-- (the always-on lights: class, parent's name, range)
local always: { [string]: number } = {}
for _, item in Mock.ALL do
	local p = props(item)
	if Mock.isA(p.ClassName, "Light") and item.Parent and item:IsDescendantOf(ws) then
		local parent = item.Parent
		if not (nightTagged[item] or (parent and nightTagged[parent])) then
			local key = `{p.ClassName} in {props(parent).Name} ({props(parent).ClassName}) range {p.Range} on {tostring(p.Enabled)}`
			always[key] = (always[key] or 0) + 1
		end
	end
end
local keys = {}
for k in always do
	table.insert(keys, k)
end
table.sort(keys, function(a, b)
	return always[a] > always[b]
end)
for _, k in keys do
	print(`ALWAYS {always[k]} × {k}`)
end

-- (the SurfaceGuis drawn at any distance: by their part's name and the gui's name)
local far: { [string]: number } = {}
for _, item in Mock.ALL do
	local p = props(item)
	if p.ClassName == "SurfaceGui" and item.Parent and item:IsDescendantOf(ws) and ((p.MaxDistance or 0) == 0) then
		local key = `{props(item.Parent).Name} / {p.Name}`
		far[key] = (far[key] or 0) + 1
	end
end
local farKeys = {}
for k in far do
	table.insert(farKeys, k)
end
table.sort(farKeys, function(a, b)
	return far[a] > far[b]
end)
for n, k in farKeys do
	if n <= 25 then
		print(`GUI {far[k]} × {k}`)
	end
end
