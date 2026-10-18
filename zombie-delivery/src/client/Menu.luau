--!strict
-- The start screen (8.0, design/sandbox/KONTRAKT.md): a charcoal card with the mark (8.9: DELIVEROS) over its slogan
-- MOVE · FIND · GROW and the version, over a charcoal scrim that fades out to the right; the camera drifts slowly over
-- the lobby (shared/SandboxMap.luau: its plaza, its portals, your plot's warehouse). PLAY (ENTER) fades to black, gives
-- the camera back to your character and runs onPlay (the server's Play).
-- 8.3 (design/warehouse-levels/KONTRAKT.md): the two shots of your warehouse look at the building of its level
-- (WarehouseLayout.site: 1 the Garage … 5 the Logistics Center).
-- 10.1 (Config.SaveSlots): the card lists your save slots (CONTINUE, NEW GAME, LOOK, START OVER; the Slots remote,
-- server/SaveSlots.luau) and opens the character creator (client/CharacterCreator.luau); the game starts once the
-- server says the save is in. Up, it sets the player attribute StartScreen (the loading screen's cue to go).
-- Its sounds (Sounds.play, art/audio/sfx6.ogg): a save picked (menu_select), START OVER's question (menu_warn) and
-- CANCEL (menu_back), the game starting (menu_start, as the fade begins); the creator plays its own.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SandboxMap = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SandboxMap")) -- (the lobby's shots)
local WarehouseLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WarehouseLayout")) -- 8.3: its level's building
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")) -- 10.1: the Slots remote
local CharacterLooks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterLooks")) -- 10.1: the slots' busts
local SaveSlotRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SaveSlotRules")) -- 10.1: the slots' lines
local Ui = require(script.Parent.Ui)
local CharacterCreator = require(script.Parent.CharacterCreator) -- 10.1: NEW GAME, LOOK, START OVER
local Sounds = require(script.Parent.Sounds) -- 10.1: the start screen's sounds (art/audio/sfx6.ogg)
local Theme = require(script.Parent.Theme)

local Menu = {}

local player = Players.LocalPlayer
local gui: any = nil
local flying = false

local shots: { { Vector3 } } = {} -- (sandboxShots, below)
local shotSeconds = 12 -- one camera move

local function shot(n: number): CFrame
	local s = shots[(n - 1) % #shots + 1]
	return CFrame.lookAt(s[1], s[2])
end

-- 8.3: the level of the warehouse the shots look at: yours (the player attribute WarehouseLevel) on your plot, else the
-- one the server built there (workspace.Warehouses' Level<id>), else 4 (the building of before 8.3).
local function warehouseLevel(id: number, mine: boolean): number
	local level = if mine then player:GetAttribute(Config.SandboxUpgrades.WarehouseAttribute) else nil
	if type(level) ~= "number" then
		local folder = workspace:FindFirstChild("Warehouses")
		level = if folder then folder:GetAttribute(`Level{id}`) else nil
	end
	return if type(level) == "number" then level else 4
end

-- 8.0: the slow drift over the game's world (shared/SandboxMap.luau), looped. 9.7 runs: over the lobby (its
-- plaza from the south, 10.4 its PLAY circle from the west, your plot's warehouse (the player's Plot attribute; the first plot
-- before the server gave you one; 8.3: the building of its level, the shot pulling back with its footprint), its bay
-- and the plaza from high up).
local function sandboxShots(): { { Vector3 } }
	local L = SandboxMap.Lobby
	local b = L.bounds
	local cx, cz = (b.x0 + b.x1) / 2, (b.z0 + b.z1) / 2
	local plaza = Vector3.new(cx, 3, (L.plaza.z0 + L.plaza.z1) / 2)
	local mine = SandboxMap.Plots[tonumber(player:GetAttribute("Plot")) or 0]
	local plot = mine or SandboxMap.Plots[1]
	local w = (WarehouseLayout.site(plot, warehouseLevel(plot.id, mine ~= nil)) or plot).warehouse
	local front, far = w.z + w.sz / 2, math.sqrt(w.sx * w.sx + w.sz * w.sz) / 100
	return {
		{ Vector3.new(cx + 150, 60, b.z1 + 40), plaza },
		{ Vector3.new(L.play.x - 70, 30, L.play.z + 40), Vector3.new(L.play.x, 2, L.play.z) },
		{ Vector3.new(w.x + 60 * far, 40 * far, front + 87 * far), Vector3.new(w.x, w.sy * 0.4, front) },
		{ Vector3.new(w.x - 50, 26, front + 50), Vector3.new(w.x, 6, front + 10) },
		{ Vector3.new(cx - 40, 110, b.z1 + 110), Vector3.new(cx, 0, cz) },
	}
end

local function fly()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	flying = true
	task.spawn(function()
		local n = 1
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = shot(n)
		while flying do
			camera.CameraType = Enum.CameraType.Scriptable
			shots = sandboxShots() -- (8.3: your plot and warehouse level can come after the start screen)
			local tween = TweenService:Create(camera, TweenInfo.new(shotSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = shot(n + 1) })
			tween:Play()
			local started = os.clock()
			while flying and os.clock() - started < shotSeconds do
				task.wait(0.1)
			end
			tween:Cancel()
			n += 1
		end
	end)
end

-- Freezes / frees your character while the start screen is up. Never waits long (a missing PlayerModule must not
-- hold the start screen up).
local function controls(enabled: boolean)
	pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 5)
		local module = scripts and scripts:WaitForChild("PlayerModule", 5)
		if not module or not module:IsA("ModuleScript") then
			return
		end
		local playerModule = require(module) :: any
		local c = playerModule:GetControls()
		if enabled then
			c:Enable()
		else
			c:Disable()
		end
	end)
end

-- 10.1: a slot card's little bust: a made courier in flat blocks (its hat, hair, skin and top), your own avatar's head
-- shot (Roblox's thumbnail) for base "own" or a save without a courier, a "+" on an empty slot.
local function bust(parent: Instance, summary: any): any
	local K = Theme.Contract
	local frame = Ui.make("Frame", {
		Name = "Bust", Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(12, 14),
		BackgroundColor3 = K.recessed, BorderSizePixel = 0, ClipsDescendants = true,
	}, parent)
	if summary.empty then
		Ui.label(frame, "+", UDim2.fromScale(1, 1), { TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = K.secondary })
		return frame
	end
	local look = if type(summary.look) == "table" then CharacterLooks.clean(summary.look) else nil
	if not look or not CharacterLooks.custom(look) then
		Ui.make("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Image = `rbxthumb://type=AvatarHeadShot&id={player.UserId}&w=150&h=150`,
		}, frame)
		return frame
	end
	local function block(c: { number }?, x: number, y: number, w: number, h: number)
		local v = c or { 128, 128, 128 }
		Ui.make("Frame", {
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = Color3.fromRGB(v[1], v[2], v[3]), BorderSizePixel = 0,
		}, frame)
	end
	local colors = CharacterLooks.colors(look)
	local hair = CharacterLooks.option("hairColor", look.hairColor)
	local hat = CharacterLooks.option("hatColor", look.hatColor)
	block(colors.TorsoColor, 8, 46, 48, 18)
	if look.hair == "long" or look.hair == "afro" then
		block(hair and hair.rgb, 16, 14, 32, 30)
	end
	block(colors.HeadColor, 20, 18, 24, 26)
	block({ 30, 30, 34 }, 26, 27, 3, 4)
	block({ 30, 30, 34 }, 35, 27, 3, 4)
	if look.hair ~= "none" and look.hat == "none" then
		block(hair and hair.rgb, 18, if look.hair == "afro" then 6 else 12, 28, if look.hair == "afro" then 14 else 8)
	end
	if look.hat ~= "none" then
		block(hat and hat.rgb, 17, 8, 30, 11)
	end
	return frame
end

-- 10.1: one slot's card (shared/SaveSlotRules.luau's summary): its bust, its courier's name, the warehouse's level, the
-- money, the collection, the moves, the time played, when it was saved; CONTINUE (red on the save played last), LOOK
-- and START OVER, or NEW GAME on an empty slot.
local function slotCard(parent: Instance, summary: any, y: number, latest: boolean, act: (string, number) -> ()): any
	local K = Theme.Contract
	local card, body = Ui.ticket(parent, UDim2.fromOffset(512, 92), UDim2.fromOffset(24, y))
	card.Parent.Name = `Slot{summary.slot}`
	if latest then
		Ui.selectRow(card, true)
	end
	bust(body, summary)
	local name = if summary.empty then "Empty" else summary.name or player.DisplayName
	Ui.label(body, `SLOT {summary.slot}  ·  {string.upper(name)}`, UDim2.fromOffset(256, 22), {
		Position = UDim2.fromOffset(88, 10), TextSize = 17, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local now = os.time()
	local line2 = if summary.empty then "Start a new game here." else `LEVEL {summary.level} · {summary.levelName}  ·  {SaveSlotRules.money(summary.money)}`
	local bits = {}
	if not summary.empty then
		table.insert(bits, `{summary.pieces} pieces`)
		table.insert(bits, `{summary.moves} moves`)
		local played = SaveSlotRules.played(summary.played)
		if played ~= "" then
			table.insert(bits, played)
		end
		local ago = SaveSlotRules.ago(summary.savedAt, now)
		if ago ~= "" then
			table.insert(bits, `saved {ago}`)
		end
	end
	Ui.label(body, line2, UDim2.fromOffset(256, 20), {
		Position = UDim2.fromOffset(88, 36), TextSize = 15, Font = Theme.Font, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.label(body, table.concat(bits, " · "), UDim2.fromOffset(256, 18), {
		Position = UDim2.fromOffset(88, 60), TextSize = 13, Font = Theme.Font, TextColor3 = K.line, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if summary.empty then
		local new = Ui.button(body, "NEW GAME", UDim2.fromOffset(150, 44), if latest then K.red else Theme.Colors.yellow, function()
			act("new", summary.slot)
		end)
		new.Position, new.TextSize = UDim2.fromOffset(350, 24), 17
		return card
	end
	local continue = Ui.button(body, "CONTINUE", UDim2.fromOffset(150, 40), if latest then K.red else Theme.Colors.yellow, function()
		act("play", summary.slot)
	end)
	continue.Position, continue.TextSize = UDim2.fromOffset(350, 8), 17
	local look = Ui.ghostButton(body, "LOOK", UDim2.fromOffset(64, 34), nil, function()
		act("look", summary.slot)
	end)
	look.Position, look.TextSize = UDim2.fromOffset(350, 52), 13
	local restart = Ui.ghostButton(body, "START OVER", UDim2.fromOffset(84, 34), Theme.Colors.red, function()
		act("restart", summary.slot)
	end)
	restart.Position, restart.TextSize = UDim2.fromOffset(418, 52), 13
	return card
end

-- The start screen: the charcoal card, the mark (8.9: DELIVEROS), its slogan and the version; PLAY fades out and runs
-- onPlay (the server's Play).
-- 10.1 (Config.SaveSlots.On): the card lists your save slots (slotCard) in place of PLAY. CONTINUE asks the server for
-- that save (the Slots remote), NEW GAME and LOOK open the character creator (client/CharacterCreator.luau), START OVER
-- asks first, then the creator: a fresh game in the slot. While the save loads the card says so; once the server says
-- it is in ("ready") the fade runs as PLAY's did. ENTER (a gamepad's A) continues the save played last (none: a new
-- game in the first empty slot). Without slots: PLAY (ENTER) as before.
function Menu.show(onPlay: () -> ())
	gui = Ui.make("ScreenGui", {
		Name = "StartScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 20,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	local C = Theme.Colors
	local P = Theme.Postage
	local K = Theme.Contract
	local slotsOn = Config.SaveSlots.On
	local veil = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.45, BorderSizePixel = 0, Active = false, ZIndex = 2,
	}, gui)
	Ui.make("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.8) }),
	}, veil)
	local W, H = if slotsOn then 560 else 520, if slotsOn then 492 else 292
	local center = Ui.make("Frame", {
		Name = "SandboxMenu", Size = UDim2.fromOffset(W, H),
		Position = UDim2.new(0.08, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1, ZIndex = 5,
	}, gui)
	local menuScale = Ui.make("UIScale", {}, center)
	local face = Ui.ticket(center, UDim2.fromScale(1, 1), UDim2.new())
	face.BackgroundColor3 = K.charcoal
	face.BackgroundTransparency = 0.06
	face.Parent.Name = "ShiftCard"
	face.Parent.ZIndex = 5
	local brand = Ui.brand(face, 24, { Position = UDim2.fromOffset(24, 16), ZIndex = 6 })
	for _, part in brand:GetChildren() do
		if part:IsA("GuiObject") then
			part.ZIndex = 6
		end
	end
	local title = Ui.label(face, "MOVE · FIND · GROW", UDim2.fromOffset(W - 48, if slotsOn then 44 else 56), { -- (8.9: the mark above says DELIVEROS)
		Name = "Title", Position = UDim2.fromOffset(24, 62), TextSize = 42, TextScaled = true, Font = Theme.DisplayFont, ZIndex = 6,
	})
	Ui.make("UITextSizeConstraint", { MaxTextSize = if slotsOn then 34 else 42 }, title)
	local touchLayout = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local hint = Ui.label(face, if touchLayout then "Tap PLAY to begin" else "Press ENTER to begin", UDim2.fromOffset(W - 48, 36), {
		Position = UDim2.fromOffset(24, H - 68), TextSize = 15, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7,
	})
	local version = Ui.make("TextLabel", {
		Name = "Version", Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(1, -12, 1, -10), AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 0, BackgroundColor3 = P.pill, Text = `version {Config.Version}`,
		TextSize = 14, Font = Theme.MonoFont, TextColor3 = C.dim, ZIndex = 6,
	}, gui)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, version)

	-- The card follows the screen (centred on a narrow one, at the left on a wide one).
	local viewportConnection: RBXScriptConnection? = nil
	local function fitMenu()
		local camera = workspace.CurrentCamera
		local v = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		menuScale.Scale = math.max(0.35, math.min((v.X - 32) / W, (v.Y - 64) / H, 1.05))
		center.Position = if v.X < 900 then UDim2.fromScale(0.5, 0.5) else UDim2.new(0.08, 0, 0.5, 0)
		center.AnchorPoint = if v.X < 900 then Vector2.new(0.5, 0.5) else Vector2.new(0, 0.5)
	end
	local function watchCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		viewportConnection = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitMenu) else nil
		fitMenu()
	end
	local cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()

	local fade = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.veil, BackgroundTransparency = 1,
		Visible = false, Active = false, ZIndex = 50,
	}, gui)
	local pressed = false
	local keyConnection: RBXScriptConnection? = nil
	local slotConnection: RBXScriptConnection? = nil
	local function start()
		if pressed then
			return
		end
		pressed = true
		if viewportConnection then viewportConnection:Disconnect() end
		cameraConnection:Disconnect()
		if keyConnection then
			keyConnection:Disconnect()
		end
		if slotConnection then
			slotConnection:Disconnect()
		end
		CharacterCreator.close()
		fade.Visible = true
		TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
		task.wait(0.45)
		flying = false
		for _, child in gui:GetChildren() do
			if child ~= fade then
				child:Destroy()
			end
		end
		local cam = workspace.CurrentCamera
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if cam then
			cam.CameraType = Enum.CameraType.Custom
			if humanoid then
				cam.CameraSubject = humanoid
			end
		end
		task.spawn(controls, true)
		local ok, err = pcall(function()
			onPlay()
		end)
		if not ok then
			warn("[Menu] starting the game failed: " .. tostring(err))
		end
		task.wait(0.6)
		TweenService:Create(fade, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.wait(0.65)
		gui:Destroy()
		gui = nil
	end

	-- 10.1: the slots (or PLAY without them)
	local enter: () -> () = function()
		task.spawn(start)
	end
	if slotsOn then
		local remote = Net.get("Slots")
		local area = Ui.make("Frame", { Name = "Slots", Size = UDim2.fromOffset(W, H - 190), Position = UDim2.fromOffset(0, 120), BackgroundTransparency = 1, ZIndex = 6 }, face)
		Ui.caps(face, "Your saves", UDim2.fromOffset(200, 16), { Position = UDim2.fromOffset(24, 112), ZIndex = 7 })
		local status = Ui.label(face, "Loading your saves…", UDim2.fromOffset(W - 260, 36), {
			Position = UDim2.fromOffset(24, H - 68), TextSize = 14, Font = Theme.Font, TextColor3 = C.dim, ZIndex = 7,
		})
		hint.Size = UDim2.fromOffset(200, 36)
		hint.Position = UDim2.fromOffset(W - 224, H - 68)
		hint.Text = ""
		local phase = "list" -- "list" | "loading" | "creator"
		local summaries: { any } = {}
		local latest: number? = nil
		local offline = false
		local asked = 0
		local rows: any = nil
		local sent: { [string]: any }? = nil -- the pick sent last, and when; sent again while the server has not taken it
		local sentAt, taken = 0, false
		local slotAction: (string, number) -> () = function() end -- (below: CONTINUE, NEW GAME, LOOK, START OVER)
		local function ask()
			asked = os.clock()
			remote:FireServer({ kind = "list" })
		end
		local function render()
			if rows then
				rows:Destroy()
			end
			rows = Ui.make("Frame", { Name = "Rows", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, area)
			if phase ~= "list" or #summaries == 0 then
				return
			end
			local first = latest
			if not first then
				for _, summary in summaries do
					if summary.empty then
						first = summary.slot
						break
					end
				end
			end
			for i, summary in summaries do
				slotCard(rows, summary, 8 + (i - 1) * 100, summary.slot == first, function(action: string, slot: number)
					if phase == "list" then
						slotAction(action, slot)
					end
				end)
			end
			status.Text = if offline then "Saving is off here (Studio without API access): games are not kept." else ""
			hint.Text = if touchLayout then "" elseif latest then `ENTER: continue slot {latest}` else "ENTER: a new game"
		end
		local function choose(kind: string, slot: number, look: any?)
			phase = "loading"
			render()
			status.Text = if kind == "new" then `Starting a new game in slot {slot}…` else `Loading slot {slot}…`
			hint.Text = ""
			sent, sentAt, taken = { kind = kind, slot = slot, look = look }, os.clock(), false
			remote:FireServer(sent)
		end
		local function summaryOf(slot: number): any
			for _, summary in summaries do
				if summary.slot == slot then
					return summary
				end
			end
			return nil
		end
		local function creator(title: string, action: string, look: any?, onDone: (any) -> ())
			phase = "creator"
			render()
			face.Parent.Visible = false
			CharacterCreator.open(gui, {
				title = title, action = action, look = look,
				onDone = function(chosen)
					face.Parent.Visible = true
					onDone(chosen)
				end,
				onBack = function()
					face.Parent.Visible = true
					phase = "list"
					render()
				end,
			})
		end
		local confirm: any = nil
		slotAction = function(action: string, slot: number)
			local summary = summaryOf(slot)
			if action == "play" then
				Sounds.play("menu_select")
				choose("play", slot, nil)
			elseif action == "new" then
				creator(`New courier · slot {slot}`, "START THE GAME", nil, function(look)
					choose("new", slot, look)
				end)
			elseif action == "look" then
				creator(`Your courier · slot {slot}`, "SAVE & CONTINUE", summary and summary.look, function(look)
					choose("play", slot, look)
				end)
			elseif action == "restart" and summary then
				if confirm then
					confirm:Destroy()
				end
				Sounds.play("menu_warn")
				phase = "confirm"
				confirm = Ui.make("Frame", {
					Name = "Confirm", Size = UDim2.fromOffset(512, 150), Position = UDim2.fromOffset(24, 150),
					BackgroundColor3 = K.raised, BorderSizePixel = 0, ZIndex = 20,
				}, face)
				Ui.stroke(confirm, K.red, 1)
				Ui.label(confirm, `START OVER IN SLOT {slot}?`, UDim2.fromOffset(480, 26), { Position = UDim2.fromOffset(16, 12), TextSize = 19, ZIndex = 21 })
				Ui.label(confirm, `Level {summary.level} · {summary.levelName}, {SaveSlotRules.money(summary.money)}, {summary.pieces} pieces and everything else in this save are gone for good. You make your courier again.`, UDim2.fromOffset(480, 44), {
					Position = UDim2.fromOffset(16, 40), TextSize = 14, Font = Theme.Font, TextColor3 = K.secondary, ZIndex = 21,
				})
				local yes = Ui.button(confirm, "START OVER", UDim2.fromOffset(200, 40), Theme.Colors.red, function()
					confirm:Destroy()
					confirm = nil
					phase = "list"
					creator(`Start over · slot {slot}`, "START OVER", summary.look, function(look)
						choose("new", slot, look)
					end)
				end)
				yes.Position, yes.ZIndex = UDim2.fromOffset(16, 96), 22
				local no = Ui.ghostButton(confirm, "CANCEL", UDim2.fromOffset(120, 40), nil, function()
					Sounds.play("menu_back")
					confirm:Destroy()
					confirm = nil
					phase = "list"
				end)
				no.Position, no.ZIndex = UDim2.fromOffset(376, 96), 22
			end
		end
		enter = function()
			if phase ~= "list" or #summaries == 0 then
				return
			end
			if latest then
				slotAction("play", latest)
				return
			end
			for _, summary in summaries do
				if summary.empty then
					slotAction("new", summary.slot)
					return
				end
			end
		end
		slotConnection = remote.OnClientEvent:Connect(function(message: any)
			if type(message) ~= "table" then
				return
			end
			if message.kind == "list" and type(message.slots) == "table" then
				summaries, latest, offline = message.slots, message.latest, message.offline == true
				if type(message.picked) == "number" and phase == "list" then
					phase = "loading" -- (a pick from before this screen: the fallback)
					status.Text = `Loading slot {message.picked}…`
				end
				render()
			elseif message.kind == "loading" then
				phase, taken = "loading", true
				render()
				status.Text = `Loading slot {message.slot}…`
			elseif message.kind == "ready" then
				status.Text = ""
				Sounds.play("menu_start")
				task.spawn(start)
			elseif message.kind == "refused" then
				status.Text = tostring(message.text)
				if phase ~= "loading" or message.text ~= "Your save is already loading." then
					phase = "list"
					ask()
				end
			end
		end)
		ask()
		task.spawn(function() -- (a list that never came: asked again; a pick the server never took: sent again)
			while gui and not pressed do
				task.wait(1)
				if #summaries == 0 and os.clock() - asked > 6 then
					ask()
				elseif phase == "loading" and sent and not taken and os.clock() - sentAt > 5 then
					sentAt = os.clock()
					remote:FireServer(sent)
				end
			end
		end)
	else
		local play = Ui.button(face, "PLAY", UDim2.fromOffset(W - 48, 72), K.red, function() end)
		play.Position = UDim2.fromOffset(24, 136)
		play.TextSize = 26
		play.ZIndex = 7
		play.Activated:Connect(start)
	end
	keyConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() or CharacterCreator.isOpen() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonA then
			enter()
		end
	end)

	task.spawn(controls, false)
	shots = sandboxShots()
	fly()
	player:SetAttribute("StartScreen", true) -- 10.1: the loading screen (ReplicatedFirst) may go: the start screen is up
end

return Menu
