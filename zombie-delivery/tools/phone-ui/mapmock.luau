-- 7.2: the stand-ins the real client/MapView.luau runs on in tools/phone-ui/mapview.luau, on top of
-- missions_mock.luau's recorder (no layout, no fonts): the services MapView reads (Players, RunService.RenderStepped,
-- UserInputService), the camera, your character, client/Discovery.luau's grid (the real shared/Explore.luau) with the
-- cells the check uncovers, client/DeviceBudget.luau, the Ui and Theme helpers, NumberSequence from numbers too, and
-- a count of every instance made (M.made) so a check can see that nothing is made frame after frame.
local M = require("./missions_mock")
local Explore = require("./Explore")

-- Every instance made, counted (mock.luau's make, wrapped).
M.made = 0
local make = M.make
M.make = function(class, props, parent)
	M.made += 1
	return make(class, props, parent)
end
M.MUi.make = M.make
M.Instance.new = function(class)
	return M.make(class)
end

-- NumberSequence.new(a, b) (two numbers: a fade) or NumberSequence.new({ keypoints }).
M.NumberSequence = { new = function(a, b)
	if type(a) == "number" then
		return { Keypoints = { { Time = 0, Value = a }, { Time = 1, Value = if type(b) == "number" then b else a } }, kind = "NumberSequence" }
	end
	return { Keypoints = a, kind = "NumberSequence" }
end }
M.ColorSequence = { new = function(a, b)
	return { a = a, b = b or a, kind = "ColorSequence" }
end }

-- UDim2 with + and - (the fog's soft edge sits a few pixels up and left of its core).
local udim2 = {}
M.UDim2.new = function(xs, xo, ys, yo)
	return setmetatable({ X = M.UDim.new(xs or 0, xo or 0), Y = M.UDim.new(ys or 0, yo or 0), kind = "UDim2" }, udim2)
end
udim2.__add = function(a, b)
	return M.UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
udim2.__sub = function(a, b)
	return M.UDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end

-- Your character: where you stand, which way you face, how fast you go.
M.root.AssemblyLinearVelocity = M.Vector3.new(0, 0, 0)
M.root.CFrame = { LookVector = M.Vector3.new(0, 0, -1) }
M.player.Character.Name = "Courier"
function M.place(x, z, lookX, lookZ)
	M.root.Position = M.Vector3.new(x, 0, z)
	M.root.CFrame = { LookVector = M.Vector3.new(lookX or 0, 0, lookZ or -1) }
end

-- The camera: its look (the minimap turns with it) and the screen's size.
M.camera = M.workspace.CurrentCamera
M.camera.CFrame = { LookVector = M.Vector3.new(0, -0.5, -1) }
function M.look(x, z)
	M.camera.CFrame = { LookVector = M.Vector3.new(x, -0.5, z) }
end
function M.screen(width, height)
	M.width, M.height = width, height
	M.camera.ViewportSize = M.Vector2.new(width, height)
	local changed = M.camera._signals.ViewportSize
	if changed then
		changed:Fire()
	end
end

-- Services.
M.services.Players.GetPlayers = function()
	return { M.player }
end
M.services.RunService.RenderStepped = M.signal()
M.services.UserInputService.TouchEnabled = false
M.services.UserInputService.KeyboardEnabled = true

-- task.defer: queued until the next frame (Roblox runs it when the code running now is done), then a thread of its own
-- that M.resume() steps through its waits (MapView's Alps wait a frame at a time).
local queued = {}
M.task.defer = function(fn)
	table.insert(queued, fn)
end
function M.frame(dt)
	local now = queued
	queued = {}
	for _, fn in now do
		M.task.spawn(fn)
	end
	M.services.RunService.RenderStepped:Fire(dt or 1 / 60)
end

-- client/Discovery.luau: the real grid; the cells uncovered and the landmarks known are the check's.
M.uncovered = {}
M.known = {}
M.Discovery = {
	grid = Explore,
	cellSize = Explore.Size,
	ready = true,
	changed = M.signal(),
	uncoveredCell = function(cx, cz)
		return M.uncovered[cz * Explore.Cols + cx] == true
	end,
	knows = function(id)
		return M.known[id] == true
	end,
	knownCount = function()
		local n, total = 0, 0
		for _, landmark in require("./Map").Landmarks do
			total += 1
			if M.known[landmark.id] then
				n += 1
			end
		end
		return n, total
	end,
	setShown = function() end,
}
-- Uncover every cell whose middle passes `keep(x, z)` (nil: all of them) and tell MapView which.
function M.uncover(keep)
	local cells = {}
	for cz = 0, Explore.Rows - 1 do
		for cx = 0, Explore.Cols - 1 do
			local x, z = Explore.X0 + (cx + 0.5) * Explore.Size, Explore.Z0 + (cz + 0.5) * Explore.Size
			local index = cz * Explore.Cols + cx
			if not M.uncovered[index] and (keep == nil or keep(x, z)) then
				M.uncovered[index] = true
				table.insert(cells, index)
			end
		end
	end
	M.Discovery.changed:Fire(cells)
	return #cells
end

M.DeviceBudget = {
	rate = function(hz)
		return hz
	end,
	moveRate = function()
		return math.huge
	end,
}

-- The Ui helpers MapView calls that missions_mock.luau's Ui has not.
function M.MUi.closeButton(parent, fn)
	local made = M.make("TextButton", { Name = "Close", Text = "✕", Size = M.UDim2.fromOffset(40, 40) }, parent)
	made.Activated:Connect(fn)
	return made
end

-- The ScreenGui MapView builds into and the column the minimap goes in (Hud's left stack).
M.hud = M.make("ScreenGui", { Name = "ZombieDeliveryHud" }, M.gui)
M.column = M.make("Frame", { Name = "LeftStack", Size = M.UDim2.fromOffset(200, 300), BackgroundTransparency = 1 }, M.hud)

-- Every GuiObject under `root` (it too), and every instance.
function M.walk(root, visit)
	visit(root)
	for _, child in root._children do
		M.walk(child, visit)
	end
end
function M.count(root, class)
	local n = 0
	M.walk(root, function(node)
		if node ~= root and (class == nil and node:IsA("GuiObject") or node.ClassName == class) then
			n += 1
		end
	end)
	return n
end

return M
