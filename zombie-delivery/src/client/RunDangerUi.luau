--!strict
-- 10.x DANGER, the client (server/RunDanger.luau decides everything; the rules shared/DangerRules.luau, the numbers
-- Config.Runs.DangerHud): a run's danger on your screen. Presentation only: the Runs remote's { kind = "danger", … }.
--   * The danger strip, under the move's panel (client/MovingHud.luau's and Danny's strip under it: client/TopBlocks
--     .luau's lowest there; clear of the HUD's chips and the touch controls as Danny's strip is: MoveLayout.stripClear): the
--     difficulty in its colour, the keys found ("🔑 KEYS 1/2"), the vault ("🗝 VAULT LOCKED", "KEY FOUND", "OPEN"),
--     the zombies left and stopped, 🏏 with the run's bat; its second line the latest event for DangerHud.Event s
--     ("🔑 Bedroom key found by Ann"), else a ⚠ hint while a hazard is within DangerHud.Hint studs of you (the tags
--     RunHazard: "⚠ Creaky boards: carry round them, or you drop it"; a shaking ceiling "⚠ The ceiling is coming down:
--     move!"), else the locked doors ("🔒 Bedroom · 🔓 Study").
--   * A horde's banner in the middle of the screen for DangerHud.Banner s, its siren (client/Sounds.luau's sounds by
--     name: an event's `sound`).
--   * Steps aside while a window covers the screen (RunDangerUi.covered: Main's CameraRig.windowOpen). The strip at the
--     screen's scale as the move's panel above it (no buttons: never wider than it on a phone, clear of the money), the
--     banner on a phone at DangerHud.TouchScale at least.
--   RunDangerUi.start()   the remote, the strip
--   RunDangerUi.view()    the run's danger now (the server's view) or nil

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DangerRules = require(Shared.DangerRules)
local Net = require(Shared.Net)
local MoveLayout = require(script.Parent.MoveLayout)
local Theme = require(script.Parent.Theme)
local TopBlocks = require(script.Parent.TopBlocks)
local TouchLayout = require(script.Parent.TouchLayout)
local Ui = require(script.Parent.Ui)

local RunDangerUi = {}

local D = Config.Runs.DangerHud
local K = Theme.Contract
local HIGH = 46 -- px: the strip's height at scale 1
local CHIP_GUIS = { SandboxHud = "MoneyBlock", SandboxTasksChip = "" } -- the HUD's chips (client/MoveHelperHud.luau's)
local GOLD = Color3.fromRGB(255, 206, 92)
local WARN = Color3.fromRGB(255, 150, 70)

RunDangerUi.covered = nil :: (() -> boolean)?

local view: { [string]: any }? = nil
local event: { text: string, untilAt: number }? = nil
local bannerUntil = 0
local gui: ScreenGui? = nil
local strip: Frame? = nil
local banner: TextLabel? = nil
local started = false

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function play(name: any)
	if type(name) ~= "string" then
		return
	end
	pcall(function()
		require(script.Parent.Sounds).play(name)
	end)
end

-- (the strip: the screen's scale, as the move's panel; the banner: on a phone TouchScale at least)
local function scaleNow(banner: boolean?): number
	local s = Ui.screenScale()
	if banner and Ui.touchLayout() then
		s = math.max(s, D.TouchScale)
	end
	return math.min(s, 1)
end

local function build(): (Frame?, TextLabel?)
	if strip and strip.Parent and banner and banner.Parent then
		return strip, banner
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil, nil
	end
	local root = Ui.make("ScreenGui", { Name = "RunDangerUi", ResetOnSpawn = false, DisplayOrder = 21, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	gui = root
	local frame = Ui.make("Frame", {
		Name = "DangerStrip",
		Size = UDim2.fromOffset(D.Width, HIGH),
		Position = UDim2.new(0.5, 0, 0, 132),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Visible = false,
	}, root)
	Ui.make("UIScale", { Name = "Scale", Scale = scaleNow() }, frame)
	Ui.corner(frame, 8)
	Ui.stroke(frame, WARN, 1)
	Ui.make("TextLabel", {
		Name = "Top",
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 4),
		BackgroundTransparency = 1,
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		RichText = true,
		Text = "",
	}, frame)
	Ui.make("TextLabel", {
		Name = "Line",
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 24),
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, frame)
	strip = frame
	local words = Ui.make("TextLabel", {
		Name = "HordeBanner",
		Size = UDim2.fromOffset(520, 48),
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.2,
		Font = Theme.HeadingFont,
		TextSize = 24,
		TextColor3 = K.red,
		Text = "",
		Visible = false,
	}, root)
	Ui.make("UIScale", { Name = "Scale", Scale = scaleNow(true) }, words)
	Ui.corner(words, 10)
	banner = words
	return frame, words
end

-- What the strip keeps clear of, in its ScreenGui's px (client/MoveHelperHud.luau's): the HUD's chips at the top left
-- and, on a touch screen, the touch controls.
local function inTheWay(origin: Vector2, W: number, H: number, s: number): ({ TouchLayout.Box }, { TouchLayout.Box })
	local chips: { TouchLayout.Box } = {}
	local function add(object: Instance?)
		if object and object:IsA("GuiObject") and object.Visible and object.AbsoluteSize.X > 1 and object.AbsoluteSize.Y > 1 then
			local at, size = object.AbsolutePosition - origin, object.AbsoluteSize
			table.insert(chips, TouchLayout.box(at.X, at.Y, at.X + size.X, at.Y + size.Y))
		end
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	for guiName, piece in CHIP_GUIS do
		local holder = playerGui and playerGui:FindFirstChild(guiName)
		if holder and (holder :: any).Enabled ~= false then
			if piece ~= "" then
				add(holder:FindFirstChild(piece, true))
			else
				for _, child in holder:GetChildren() do
					add(child)
				end
			end
		end
	end
	local keep: { TouchLayout.Box } = {}
	if Ui.touchLayout() then
		local cluster = TouchLayout.cluster(W, H, s)
		for _, b in TouchLayout.buttons(cluster) do
			table.insert(keep, b)
		end
		table.insert(keep, cluster.thumb)
		table.insert(keep, cluster.jump)
	end
	return chips, keep
end

-- The ⚠ words for the hazard nearest you (its tag RunHazard, its Kind; a plaster patch shaking: Warn), nil none.
local function hazardHint(): string?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local best: string? = nil
	local far = D.Hint
	for _, part in CollectionService:GetTagged("RunHazard") do
		if not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then
			continue
		end
		local rel = part.CFrame:PointToObjectSpace(root.Position)
		if math.abs(rel.Y) > 12 then
			continue
		end
		local dx = math.max(math.abs(rel.X) - part.Size.X / 2, 0)
		local dz = math.max(math.abs(rel.Z) - part.Size.Z / 2, 0)
		local d = math.sqrt(dx * dx + dz * dz)
		if d <= far then
			far = d
			best = if part:GetAttribute("Warn") == true then "⚠ The ceiling is coming down: move!" else DangerRules.hint(part:GetAttribute("Kind"))
		end
	end
	return best
end

local function topText(v: { [string]: any }): string
	local def = nil
	for _, d in Config.Runs.Difficulties do
		if d.id == v.difficulty then
			def = d
		end
	end
	local color = if def then rgb(def.color) else K.text
	local parts: { string } = {
		string.format('<font color="#%02X%02X%02X">%s</font>', math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255), string.upper(tostring(v.name or ""))),
	}
	local keys = if type(v.keys) == "table" then v.keys else {}
	if #keys > 0 then
		local got = 0
		for _, key in keys do
			if key.found then
				got += 1
			end
		end
		table.insert(parts, `🔑 KEYS {got}/{#keys}`)
	end
	local vault = v.vault
	if type(vault) == "table" then
		table.insert(parts, if vault.open then "🗝 VAULT OPEN" elseif vault.key then "🗝 VAULT KEY ✓" else "🗝 VAULT LOCKED")
	end
	local alive, stopped = tonumber(v.zombies) or 0, tonumber(v.stopped) or 0
	if alive > 0 or stopped > 0 then
		table.insert(parts, `🧟 {alive} · ✖ {stopped}`)
	end
	if v.weapon then
		table.insert(parts, "🏏")
	end
	return table.concat(parts, "  ·  ")
end

local function locksText(v: { [string]: any }): string
	local out: { string } = {}
	for _, key in (if type(v.keys) == "table" then v.keys else {}) :: { any } do
		table.insert(out, if key.open then `🔓 {key.room}` elseif key.found then `🔑 {key.room}` else `🔒 {key.room}`)
	end
	if v.boss then
		table.insert(out, `👑 {v.boss}`)
	end
	return table.concat(out, " · ")
end

local function refresh()
	local covered = false
	local hook = RunDangerUi.covered
	if hook then
		local ok, result = pcall(hook)
		covered = ok and result == true
	end
	local v = view
	if not v and not strip then
		return
	end
	local frame, words = build()
	if not frame or not words then
		return
	end
	for _, thing in { frame, words } :: { GuiObject } do
		local scale = thing:FindFirstChild("Scale")
		if scale and scale:IsA("UIScale") then
			scale.Scale = scaleNow(thing == words)
		end
	end
	local now = os.clock()
	words.Visible = not covered and now < bannerUntil
	if not v or covered then
		frame.Visible = false
		return
	end
	frame.Visible = true
	-- under the move's panel (and Danny's strip), clear of the chips and the touch controls
	local S = scaleNow(false)
	local screen = Ui.screenSize()
	local origin = if gui then gui.AbsolutePosition else Vector2.new(0, 0)
	local w, h = D.Width * S, HIGH * S
	local x0 = screen.X / 2 - w / 2
	local under = TopBlocks.bottom(origin, x0, x0 + w) or MoveLayout.panel(screen.X, S).y1
	local y = math.floor(under + MoveLayout.STRIP_GAP * S + 0.5)
	local wanted = TouchLayout.box(x0, y, x0 + w, y + h)
	local chips, keep = inTheWay(origin, screen.X, screen.Y, S)
	local clear = MoveLayout.stripClear(wanted, screen.X, screen.Y, chips, keep)
	frame.Position = UDim2.new(0.5, math.floor(clear.x0 - wanted.x0 + 0.5), 0, math.floor(clear.y0 + 0.5))
	local top = frame:FindFirstChild("Top") :: TextLabel?
	local line = frame:FindFirstChild("Line") :: TextLabel?
	if top then
		top.Text = topText(v)
	end
	if line then
		local e = event
		local hint = hazardHint()
		if e and now < e.untilAt then
			line.Text = e.text
			line.TextColor3 = GOLD
		elseif hint then
			line.Text = hint
			line.TextColor3 = WARN
		else
			line.Text = locksText(v)
			line.TextColor3 = K.secondary
		end
	end
end

local function onMessage(message: any)
	if type(message) ~= "table" or message.kind ~= "danger" then
		return
	end
	if type(message.event) == "string" then
		event = { text = message.event, untilAt = os.clock() + D.Event }
		if message.banner == true then
			bannerUntil = os.clock() + D.Banner
			local _, words = build()
			if words then
				words.Text = message.event
			end
		end
		play(message.sound)
	elseif message.house ~= nil then
		view = message
	elseif message.sound ~= nil then
		play(message.sound)
	else
		view = nil
		event = nil
		bannerUntil = 0
	end
	refresh()
end

function RunDangerUi.view(): { [string]: any }?
	return view
end

function RunDangerUi.start()
	if started or not Config.Sandbox.On then
		return
	end
	started = true
	Net.get("Runs").OnClientEvent:Connect(onMessage)
	task.spawn(function()
		while true do
			task.wait(D.Every)
			if view or (strip and strip.Visible) or (banner and banner.Visible) then
				local ok, err = pcall(refresh :: any)
				if not ok then
					warn(`[RunDangerUi] {err}`)
				end
			end
		end
	end)
end

return RunDangerUi
