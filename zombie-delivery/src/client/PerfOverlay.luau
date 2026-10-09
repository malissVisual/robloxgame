--!strict
-- 6.13.1, the admin's performance overlay (design/performance/NAVOD.md: the owner opens the live game on a phone and
-- sends a screenshot). Only for admins (the "Admin" attribute, or everybody in a Studio Play test like the P panel):
-- the P panel's WORLD tab turns it on and off (AdminPanel.onPerformance, set by client/Main.client.luau). A small
-- charcoal box at the top in the middle, taps go through it but for its two buttons:
--   FPS        frames a second (the last half second) and the worst frame of the last 5 s, as frames a second
--   CPU / GPU  the render's milliseconds a frame and the draw calls and triangles (Stats, where Roblox lets a script read)
--   MEMORY     this client's memory (Stats:GetTotalMemoryUsageMb) and Lua's share; PING (Player:GetNetworkPing)
--   WORLD      the instances and parts in the workspace now (with StreamingEnabled: only what streamed in), the parts
--              that throw a shadow, the lights and how many shine (and of the night lights, the budget's:
--              client/WorldFx.luau); counted every Overlay.Count seconds, Overlay.PerFrame instances a frame, never
--              all at once (the count itself must not make the hitch it measures)
--   STREAMING  on or off (workspace.StreamingEnabled), the device (PHONE / COMPUTER, LITE or FULL: client/DeviceBudget),
--              the screen in px, the graphics quality (Roblox's slider, AUTO when Roblox picks) and the version
-- LITE swaps this client between the phone's and the computer's budgets (to compare the frame rate on one device);
-- ✕ closes the overlay. Nothing here touches the game: it only reads.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local DeviceBudget = require(script.Parent.DeviceBudget)
local WorldFx = require(script.Parent.WorldFx)

local PerfOverlay = {}

local K = Theme.Contract
local Tuning = Config.Performance.Overlay
local player = Players.LocalPlayer

type Counts = { instances: number, parts: number, shadows: number, lights: number, shining: number, at: number }

local state = {
	on = false,
	gui = nil :: ScreenGui?,
	text = nil :: TextLabel?,
	liteButton = nil :: TextButton?,
	frame = nil :: RBXScriptConnection?,
	frames = 0, -- frames since the last refresh
	elapsed = 0, -- seconds since the last refresh
	worst = {} :: { number }, -- the longest frame of each of the last refreshes (seconds)
	counts = nil :: Counts?,
	counting = false,
	run = 0, -- a new run of the counting loop stops the old one
}

-- In a Studio Play test everybody is an admin (Config.Admin.InStudio), like the P panel.
local function isAdmin(): boolean
	return player:GetAttribute("Admin") == true or (Config.Admin.InStudio and RunService:IsStudio())
end

local function thousands(n: number): string
	local text = tostring(math.floor(n + 0.5))
	local out = string.reverse(text):gsub("(%d%d%d)", "%1,")
	local result = string.reverse(out)
	return if string.sub(result, 1, 1) == "," then string.sub(result, 2) else result
end

-- A Stats number Roblox may not let a script read (nil then).
local function stat(read: () -> number): number?
	local ok, value = pcall(read)
	return if ok and type(value) == "number" then value else nil
end

-- Roblox's graphics quality: "3/10", or "AUTO" when Roblox picks it.
local function quality(): string
	local shown = "?"
	pcall(function()
		local saved = UserSettings().GameSettings.SavedQualityLevel
		shown = if saved == Enum.SavedQualitySetting.Automatic then "AUTO" else `{saved.Value}/10`
	end)
	return shown
end

-- The workspace, counted a few instances a frame (Overlay.PerFrame), from the top down.
local function countWorld(run: number): Counts?
	local counts: Counts = { instances = 0, parts = 0, shadows = 0, lights = 0, shining = 0, at = os.clock() }
	local stack: { Instance } = { workspace }
	local done = 0
	while #stack > 0 do
		if state.run ~= run or not state.on then
			return nil
		end
		local item = table.remove(stack) :: Instance
		for _, child in item:GetChildren() do
			counts.instances += 1
			if child:IsA("BasePart") then
				counts.parts += 1
				if child.CastShadow and child.Transparency < 1 then
					counts.shadows += 1
				end
			elseif child:IsA("Light") then
				counts.lights += 1
				if child.Enabled then
					counts.shining += 1
				end
			end
			table.insert(stack, child)
			done += 1
			if done >= Tuning.PerFrame then
				done = 0
				task.wait()
				if state.run ~= run or not state.on then
					return nil
				end
			end
		end
	end
	return counts
end

local function startCounting()
	state.run += 1
	local run = state.run
	task.spawn(function()
		while state.on and state.run == run do
			local counts = countWorld(run)
			if counts then
				state.counts = counts
			end
			task.wait(Tuning.Count)
		end
	end)
end

local function refresh()
	local label = state.text
	if not label then
		return
	end
	local fps = if state.elapsed > 0 then state.frames / state.elapsed else 0
	local worst = 0
	for _, seconds in state.worst do
		worst = math.max(worst, seconds)
	end
	local lines: { string } = {}
	local worstFps = if worst > 0 then 1 / worst else 0
	table.insert(lines, `<b>FPS {math.floor(fps + 0.5)}</b>   worst 5 s: {math.floor(worstFps + 0.5)}`)
	local cpu = stat(function()
		return Stats.RenderCPUFrameTime
	end)
	local gpu = stat(function()
		return Stats.RenderGPUFrameTime
	end)
	local calls = stat(function()
		return Stats.SceneDrawcallCount
	end)
	local tris = stat(function()
		return Stats.SceneTriangleCount
	end)
	local render = {}
	if cpu then
		table.insert(render, string.format("CPU %.1f ms", cpu))
	end
	if gpu then
		table.insert(render, string.format("GPU %.1f ms", gpu))
	end
	if calls then
		table.insert(render, `{thousands(calls)} draws`)
	end
	if tris then
		table.insert(render, string.format("%.0fk tris", tris / 1000))
	end
	if #render > 0 then
		table.insert(lines, table.concat(render, " · "))
	end
	local memory = stat(function()
		return Stats:GetTotalMemoryUsageMb()
	end)
	local scripts = stat(function()
		return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.LuaHeap)
	end)
	local ping = stat(function()
		return player:GetNetworkPing()
	end)
	table.insert(lines, `MEMORY {if memory then math.floor(memory) else "?"} MB{if scripts then ` (Lua {math.floor(scripts)})` else ""}   PING {if ping then math.floor(ping * 1000 + 0.5) else "?"} ms`)
	local counts = state.counts
	if counts then
		table.insert(lines, `INSTANCES {thousands(counts.instances)}   PARTS {thousands(counts.parts)}`)
		table.insert(lines, `SHADOWS {thousands(counts.shadows)} parts   LIGHTS {counts.shining} on / {counts.lights}`)
	else
		table.insert(lines, "INSTANCES …   PARTS … (counting)")
	end
	local known, shining = WorldFx.lightCount()
	table.insert(lines, `NIGHT LIGHTS {shining} shine of {known} (budget)`)
	local streaming = workspace.StreamingEnabled
	table.insert(lines, `STREAMING {if streaming then "ON" else "<font color=\"#D74A46\">OFF</font>"}   {if DeviceBudget.touch then "PHONE" else "COMPUTER"} · {if DeviceBudget.lite then "LITE" else "FULL"}`)
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.zero
	table.insert(lines, `SCREEN {math.floor(size.X)}×{math.floor(size.Y)}   QUALITY {quality()}   v{Config.Version}`)
	label.Text = table.concat(lines, "\n")
	local lite = state.liteButton
	if lite then
		lite.Text = if DeviceBudget.lite then "LITE · ON" else "LITE · OFF"
	end
end

local function build(): ScreenGui
	local gui: ScreenGui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryPerformance",
		ResetOnSpawn = false,
		DisplayOrder = 60,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	local box = Ui.make("Frame", {
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.fromOffset(330, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Active = false, -- (taps go through to the game)
	}, gui)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1 }, box)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, box)
	Ui.make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, box)
	state.text = Ui.make("TextLabel", {
		Name = "Numbers",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		RichText = true,
		Text = "PERFORMANCE …",
		TextColor3 = K.text,
		TextSize = 13,
		Font = Theme.MonoFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		LayoutOrder = 1,
	}, box)
	local row = Ui.make("Frame", { Name = "Buttons", Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 2 }, box)
	local function button(name: string, text: string, x: number, width: number, onClick: () -> ()): TextButton
		local made: TextButton = Ui.make("TextButton", {
			Name = name,
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(width, 32),
			BackgroundColor3 = K.raised,
			BorderSizePixel = 0,
			Text = text,
			TextColor3 = K.text,
			TextSize = 13,
			Font = Theme.HeadingFont,
			AutoButtonColor = true,
		}, row)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1 }, made)
		made.Activated:Connect(onClick)
		return made
	end
	state.liteButton = button("Lite", "LITE", 0, 120, function()
		DeviceBudget.setLite(not DeviceBudget.lite)
		refresh()
	end)
	button("Close", "✕", 130, 44, function()
		PerfOverlay.setOn(false)
	end)
	return gui
end

function PerfOverlay.isOn(): boolean
	return state.on
end

function PerfOverlay.setOn(on: boolean)
	on = on and isAdmin()
	if on == state.on then
		return
	end
	state.on = on
	local gui: ScreenGui = state.gui or build()
	state.gui = gui
	gui.Enabled = on
	local connection = state.frame
	if connection then
		connection:Disconnect()
		state.frame = nil
	end
	if not on then
		state.run += 1 -- (the counting loop stops)
		state.counts = nil
		return
	end
	state.frames, state.elapsed = 0, 0
	table.clear(state.worst)
	local longest = 0
	state.frame = RunService.RenderStepped:Connect(function(dt: number)
		state.frames += 1
		state.elapsed += dt
		longest = math.max(longest, dt)
		if state.elapsed >= Tuning.Refresh then
			table.insert(state.worst, longest)
			while #state.worst > math.max(1, math.floor(5 / Tuning.Refresh)) do
				table.remove(state.worst, 1)
			end
			refresh()
			state.frames, state.elapsed, longest = 0, 0, 0
		end
	end)
	startCounting()
	refresh()
end

function PerfOverlay.toggle()
	PerfOverlay.setOn(not state.on)
end

function PerfOverlay.start()
	-- An admin who stops being one (the attribute taken away) loses the overlay.
	player:GetAttributeChangedSignal("Admin"):Connect(function()
		if state.on and not isAdmin() then
			PerfOverlay.setOn(false)
		end
	end)
end

return PerfOverlay
