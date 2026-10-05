--!strict
-- 3.7: what this player has discovered (server/Explore.luau tells it through the "Explore" remote): the uncovered
-- cells of the map's grid (shared/Explore.luau) and the landmarks known (a landmark is known once its cell is
-- uncovered). The big map and the minimap (client/MapView.luau) draw fog over the rest and show only the known
-- landmarks; they listen to Discovery.changed.
--
-- A place discovered shows the "NEW LOCATION DISCOVERED" banner, in the contract style (design/ui-contract): small red
-- caps over the place's name in large white, a fine line, on a subtle charcoal scrim. It fades and slides in at the top
-- centre for Config.Explore.Banner seconds; several at once wait in a queue (shorter each while more wait). It has its
-- own ScreenGui, over the HUD and under the windows, and waits while the HUD is hidden (the start screen).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Explore)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Sounds = require(script.Parent.Sounds)

local Discovery = {}

Discovery.cellSize = Grid.Size
Discovery.grid = Grid -- the grid's shape (Cols, Rows, X0, Z0, Size) and its cell helpers
Discovery.ready = false -- the server's state came (until then everything is fog)

local set: Grid.Set = {}
local known: { [string]: boolean } = {}

-- ── The signal ─────────────────────────────────────────────────────────────
-- Discovery.changed:Connect(function(cells) … end): `cells` the indexes just uncovered, nil = everything may have
-- changed (the state on joining).

type Listener = (cells: { number }?) -> ()
local listeners: { Listener } = {}

Discovery.changed = {
	Connect = function(_self: any, listener: Listener): { Disconnect: () -> () }
		table.insert(listeners, listener)
		return {
			Disconnect = function()
				local at = table.find(listeners, listener)
				if at then
					table.remove(listeners, at)
				end
			end,
		}
	end,
}

local function fire(cells: { number }?)
	for _, listener in table.clone(listeners) do
		local ok, err = pcall(function()
			listener(cells)
		end)
		if not ok then
			warn(`[Discovery] a listener failed: {err}`)
		end
	end
end

-- ── Questions ──────────────────────────────────────────────────────────────

-- Is the point's cell uncovered?
function Discovery.uncovered(x: number, z: number): boolean
	return set[Grid.indexAt(x, z)] == true
end

-- Is this cell (column, row of shared/Explore.luau's grid) uncovered?
function Discovery.uncoveredCell(cx: number, cz: number): boolean
	return set[cz * Grid.Cols + cx] == true
end

-- Is this landmark (Map.Landmarks id) known?
function Discovery.knows(landmarkId: string): boolean
	return known[landmarkId] == true
end

-- How many landmarks are known, of how many.
function Discovery.knownCount(): (number, number)
	local n = 0
	for _, landmark in Map.Landmarks do
		if known[landmark.id] then
			n += 1
		end
	end
	return n, #Map.Landmarks
end

-- ── The banner ─────────────────────────────────────────────────────────────

local TEXT = Color3.fromRGB(242, 242, 240) -- #F2F2F0
local CHARCOAL = Color3.fromRGB(20, 23, 28) -- #14171C
local LINE = Color3.fromRGB(133, 139, 147) -- #858B93
local RED = Color3.fromRGB(215, 74, 70) -- #D74A46

local BANNER_W, BANNER_H = 420, 92
local FADE_IN, FADE_OUT = 0.35, 0.45

local queue: { string } = {}
local showing = false
local shown = false -- the HUD is up (MapView.setVisible tells us)
local banner: any = nil
local bannerName: any = nil
local bannerScale: any = nil

local function buildBanner()
	local gui = Ui.make("ScreenGui", {
		Name = "Discovery",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1, -- over the HUD, under the windows
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	-- A CanvasGroup: the whole banner fades as one.
	banner = Ui.make("CanvasGroup", {
		Name = "NewLocation",
		Size = UDim2.fromOffset(BANNER_W, BANNER_H),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.27, 0),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
	}, gui)
	bannerScale = Ui.make("UIScale", {}, banner)
	-- The scrim: charcoal, strongest in the middle, gone at the sides (subtle, only where the text is).
	local scrim = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = CHARCOAL,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, banner)
	Ui.make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.22, 0),
			NumberSequenceKeypoint.new(0.78, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, scrim)
	-- Small red caps, the place's name in large white, a fine line with a short red mark in its middle.
	Ui.make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 12),
		BackgroundTransparency = 1,
		Text = "N E W   L O C A T I O N   D I S C O V E R E D",
		TextSize = 12,
		Font = Theme.HeadingFont,
		TextColor3 = RED,
	}, banner)
	bannerName = Ui.make("TextLabel", {
		Size = UDim2.new(1, -40, 0, 36),
		Position = UDim2.fromOffset(20, 30),
		BackgroundTransparency = 1,
		Text = "",
		TextSize = 30,
		Font = Theme.DisplayFont,
		TextColor3 = TEXT,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextStrokeColor3 = CHARCOAL,
		TextStrokeTransparency = 0.6,
	}, banner)
	Ui.make("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 18 }, bannerName)
	bannerName.TextScaled = true
	local line = Ui.make("Frame", {
		Size = UDim2.new(0.62, 0, 0, 1),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		BackgroundColor3 = LINE,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}, banner)
	Ui.make("Frame", {
		Size = UDim2.fromOffset(28, 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = RED,
		BorderSizePixel = 0,
	}, line)
end

local pump: () -> ()

-- One banner: fade and slide in, stay, fade out; then the next one.
local function showNext()
	local name = table.remove(queue, 1)
	if not name or not banner then
		showing = false
		return
	end
	showing = true
	bannerScale.Scale = Ui.screenScale()
	bannerName.Text = string.upper(name)
	banner.Visible = true
	banner.GroupTransparency = 1
	banner.Position = UDim2.new(0.5, 0, 0.27, -10)
	TweenService:Create(banner, TweenInfo.new(FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
		Position = UDim2.new(0.5, 0, 0.27, 0),
	}):Play()
	pcall(Sounds.play, "notify", 0.7)
	-- Shorter while more wait (a burst of places shows them all, not for half a minute).
	local stay = if #queue > 0 then math.max(1.4, Config.Explore.Banner * 0.55) else Config.Explore.Banner
	task.delay(FADE_IN + stay, function()
		local out = TweenService:Create(banner, TweenInfo.new(FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
			Position = UDim2.new(0.5, 0, 0.27, -6),
		})
		out:Play()
		task.delay(FADE_OUT + 0.15, function()
			banner.Visible = false
			showing = false
			pump()
		end)
	end)
end

function pump()
	if showing or not shown or not banner or #queue == 0 then
		return
	end
	showNext()
end

local function announce(name: string)
	if table.find(queue, name) then
		return
	end
	table.insert(queue, name)
	-- A flood (a teleport across the map): the oldest go, the newest few stay.
	while #queue > 6 do
		table.remove(queue, 1)
	end
	pump()
end

-- The HUD is shown or hidden (client/MapView.luau MapView.setVisible): the banners wait for it.
function Discovery.setShown(visible: boolean)
	shown = visible
	if banner and not visible and not showing then
		banner.Visible = false
	end
	pump()
end

-- ── The remote ─────────────────────────────────────────────────────────────

-- The landmarks the cells made known.
local function learn(cells: { number })
	for _, index in cells do
		local landmarks = Grid.landmarksIn(index)
		if landmarks then
			for _, landmark in landmarks do
				known[landmark.id] = true
			end
		end
	end
end

local function onEvent(kind: any, a: any, b: any)
	if kind == "state" then
		if type(a) ~= "string" then
			return
		end
		set = Grid.decode(a)
		table.clear(known)
		local all: { number } = {}
		for index in set do
			table.insert(all, index)
		end
		learn(all)
		if type(b) == "table" then
			for _, id in b do
				if type(id) == "string" then
					known[id] = true
				end
			end
		end
		Discovery.ready = true
		fire(nil)
	elseif kind == "cells" then
		if type(a) ~= "table" then
			return
		end
		local fresh: { number } = {}
		for _, index in a do
			if type(index) == "number" and index >= 0 and index < Grid.Count and index == math.floor(index) and not set[index] then
				set[index] = true
				table.insert(fresh, index)
			end
		end
		if #fresh > 0 then
			learn(fresh)
			fire(fresh)
		end
	elseif kind == "place" then
		if type(a) ~= "string" then
			return
		end
		local wasKnown = known[a] == true
		known[a] = true
		if not wasKnown then
			fire({})
		end
		announce(if type(b) == "string" and b ~= "" then b else a)
	end
end

function Discovery.start()
	buildBanner()
	Net.get("Explore").OnClientEvent:Connect(onEvent)
end

return Discovery
