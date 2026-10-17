--!strict
-- The start screen: the camera drifts over the city (the zombies roam the streets), the title, your company's
-- money and deliveries, and PLAY. PLAY fades to black, gives the camera back to your character and asks the server
-- for your car.
-- 3.8 (the contract UI, design/ui-contract/): the card is a flat charcoal rectangle with a thin red rule, over a
-- charcoal scrim that fades out to the right (the city stays the main view); PLAY is the main action (a red rule
-- under it); the controls are a second card.
-- 5.8 (the courier phone's look, design/phone-ui/): the card carries the ZDC mark (the red square, the wordmark, a
-- thin rule, COURIER TERMINAL), PLAY is the phone's red primary action, the company line and the controls are slim
-- hairline rows (no corners), and the controls card has the ZDC heading.
-- 8.0 SANDBOX (Config.Sandbox.On, design/sandbox/KONTRAKT.md): a simple screen instead (showSandbox): the mark
-- (8.9: DELIVEROS) over its slogan MOVE · FIND · GROW, PLAY (ENTER) and the version; the camera drifts slowly over the
-- sandbox (shared/SandboxMap.luau: the farmstead, Pražská, your plot), never over the old city. PLAY does what the
-- city's does.
-- 8.3 (design/warehouse-levels/KONTRAKT.md): the two shots of your warehouse look at the building of its level
-- (WarehouseLayout.site: 1 the Garage … 5 the Logistics Center).
-- 9.6 (Config.SaveSlots): the sandbox's card lists your save slots (CONTINUE, NEW GAME, LOOK, START OVER; the Slots
-- remote, server/SaveSlots.luau) and opens the character creator (client/CharacterCreator.luau); the game starts once
-- the server says the save is in. Up, it sets the player attribute StartScreen (the loading screen's cue to go).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SandboxMap = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SandboxMap")) -- 8.0 SANDBOX
local WarehouseLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WarehouseLayout")) -- 8.3: its level's building
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")) -- 9.6: the Slots remote
local CharacterLooks = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterLooks")) -- 9.6: the slots' busts
local SaveSlotRules = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SaveSlotRules")) -- 9.6: the slots' lines
local Ui = require(script.Parent.Ui)
local CharacterCreator = require(script.Parent.CharacterCreator) -- 9.6: NEW GAME, LOOK, START OVER
local Theme = require(script.Parent.Theme)

local Menu = {}

local player = Players.LocalPlayer
local gui: any = nil
local infoLabel: any = nil
local flying = false
local lastState: any = nil

-- Camera stops around the depot (close enough to be streamed in), looped. 6.11: the Central Park's pond in the middle
-- first, then over it to the depot north-east of it (Map.Park, Map.Depot).
local SHOTS = {
	{ Vector3.new(-200, 60, 230), Vector3.new(0, 6, 0) },
	{ Vector3.new(-30, 34, 70), Vector3.new(144, 18, -150) },
	{ Vector3.new(560, 45, 140), Vector3.new(840, 0, 72) },
	{ Vector3.new(300, 110, -420), Vector3.new(0, 0, -150) },
	{ Vector3.new(-420, 40, -200), Vector3.new(-200, 5, 0) },
}

local shots = SHOTS -- (8.0 SANDBOX: sandboxShots instead)
local shotSeconds = 9 -- one camera move

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

-- 8.0 SANDBOX: the slow drift over the sandbox (shared/SandboxMap.luau), looped: the chalet from the turnaround, then
-- from its other side, up Pražská toward the plots, your plot's warehouse (the player's Plot attribute; the first
-- plot before the server gave you one; 8.3: the building of its level), your van's spot at its roller door, back down
-- the street. 8.3: every level's front wall is on the door's line; the shot at it pulls back with the building's
-- footprint (far 1: the Big Warehouse's 80 × 60, the 8.0 shot: 60 east, 40 up, 87 in front of the door; the Garage
-- close, the Logistics Center from further off).
local function sandboxShots(): { { Vector3 } }
	local house = SandboxMap.House.house
	local door = SandboxMap.House.door
	local turn = SandboxMap.Turnaround
	local mine = SandboxMap.Plots[tonumber(player:GetAttribute("Plot")) or 0]
	local plot = mine or SandboxMap.Plots[1]
	local w, van = (WarehouseLayout.site(plot, warehouseLevel(plot.id, mine ~= nil)) or plot).warehouse, plot.vanSpot
	local front, far = w.z + w.sz / 2, math.sqrt(w.sx * w.sx + w.sz * w.sz) / 100
	-- (8.1: the house is the owner's Blender house's box, its roof over house.sy; 8.2.1: the big one again, 44 wide:
	-- the two shots as far out as before 8.1)
	local chalet = Vector3.new(house.x, house.y + house.sy * 0.8, house.z)
	return {
		{ Vector3.new(house.x + 64, 30, door.z - 70), chalet },
		{ Vector3.new(house.x - 70, 44, door.z - 110), chalet },
		{ Vector3.new(turn.x + 40, 70, turn.z - 30), Vector3.new(turn.x, 0, (turn.z + van.z) / 2) },
		{ Vector3.new(w.x + 60 * far, 40 * far, front + 87 * far), Vector3.new(w.x, w.sy * 0.4, front) },
		{ Vector3.new(w.x - 50, 26, van.z + 40), Vector3.new(van.x, van.y + 4, van.z) },
		{ Vector3.new(turn.x - 30, 60, van.z + 90), Vector3.new(turn.x, 0, (turn.z + van.z) / 2) },
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
			if Config.Sandbox.On then
				shots = sandboxShots() -- (8.3: your plot and warehouse level can come after the start screen)
			end
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

function Menu.setState(state: any)
	lastState = state
	if infoLabel and state then
		infoLabel.Text = `{Ui.money(state.money)}  ·  {state.deliveries} deliveries  ·  {state.kills} kills`
	end
end

-- 9.6: a slot card's little bust: a made courier in flat blocks (its hat, hair, skin and top), your own avatar's head
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

-- 9.6: one slot's card (shared/SaveSlotRules.luau's summary): its bust, its courier's name, the warehouse's level, the
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

-- 8.0 SANDBOX: the sandbox's start screen. The city's charcoal card, smaller: the mark (8.9: DELIVEROS), its slogan and
-- the version; PLAY fades out the same way and runs onPlay (the server's Play).
-- 9.6 (Config.SaveSlots.On): the card lists your save slots (slotCard) in place of PLAY. CONTINUE asks the server for
-- that save (the Slots remote), NEW GAME and LOOK open the character creator (client/CharacterCreator.luau), START OVER
-- asks first, then the creator: a fresh game in the slot. While the save loads the card says so; once the server says
-- it is in ("ready") the fade runs as PLAY's did. ENTER (a gamepad's A) continues the save played last (none: a new
-- game in the first empty slot). Without slots: PLAY (ENTER) as before.
local function showSandbox(onPlay: () -> ())
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

	-- 9.6: the slots (or PLAY without them)
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
	shots, shotSeconds = sandboxShots(), 12
	fly()
	player:SetAttribute("StartScreen", true) -- 9.6: the loading screen (ReplicatedFirst) may go: the start screen is up
end

function Menu.show(onPlay: () -> ())
	if Config.Sandbox.On then
		showSandbox(onPlay)
		return
	end
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
	if Theme.Images.menuBackground ~= "" then
		Ui.make("ImageLabel", {
			Name = "MenuArtwork", Size = UDim2.fromScale(1, 1), Image = Theme.Images.menuBackground,
			ScaleType = Enum.ScaleType.Crop, BackgroundTransparency = 1, ZIndex = 1,
		}, gui)
	end
	-- A localized charcoal scrim (opaque on the left, gone on the right) keeps the real-time city the focal point.
	local veil = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.45, BorderSizePixel = 0, Active = false, ZIndex = 2,
	}, gui)
	Ui.make("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.8) }),
		Rotation = 0,
	}, veil)

	local center = Ui.make("Frame", {
		Name = "DispatchMenu", Size = UDim2.fromOffset(560, 500),
		Position = UDim2.new(0.08, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1, ZIndex = 5,
	}, gui)
	local menuScale = Ui.make("UIScale", {}, center)
	-- The shift card: a flat charcoal rectangle with the ZDC mark at its top (the phone's brand).
	local face = Ui.ticket(center, UDim2.fromScale(1, 1), UDim2.new())
	face.BackgroundColor3 = K.charcoal
	face.BackgroundTransparency = 0.06
	local faceTicket = face.Parent
	faceTicket.Name = "ShiftCard"
	faceTicket.ZIndex = 5
	local brand = Ui.brand(face, 24, { Position = UDim2.fromOffset(24, 16), ZIndex = 6 })
	for _, part in brand:GetChildren() do
		if part:IsA("GuiObject") then
			part.ZIndex = 6
		end
	end
	local brandEnd = 24 + brand.Size.X.Offset
	Ui.make("Frame", {
		Name = "BrandRule", Size = UDim2.fromOffset(1, 20), Position = UDim2.fromOffset(brandEnd + 10, 22),
		BackgroundColor3 = K.rule, BorderSizePixel = 0, ZIndex = 6,
	}, face)
	Ui.caps(face, "Courier terminal   ·   Dead End Dispatch", UDim2.fromOffset(536 - (brandEnd + 22), 20), {
		Position = UDim2.fromOffset(brandEnd + 22, 22), TextSize = 13, ZIndex = 6,
	})
	local topTitle = Ui.label(face, "ZOMBIE", UDim2.fromOffset(510, 76), {
		Position = UDim2.fromOffset(24, 60), TextSize = 64, Font = Theme.DisplayFont, ZIndex = 6,
	})
	local bottomTitle = Ui.label(face, "DELIVERY", UDim2.fromOffset(510, 76), {
		Position = UDim2.fromOffset(24, 128), TextSize = 64, TextColor3 = K.text, Font = Theme.DisplayFont, ZIndex = 6,
	})
	if Theme.Images.logo ~= "" then
		topTitle.Visible, bottomTitle.Visible = false, false
		Ui.make("ImageLabel", {
			Size = UDim2.fromOffset(510, 158), Position = UDim2.fromOffset(24, 52),
			Image = Theme.Images.logo, ScaleType = Enum.ScaleType.Fit, BackgroundTransparency = 1, ZIndex = 6,
		}, face)
	end
	local tagline = Ui.label(face, "Deliver. Survive. Get paid.", UDim2.fromOffset(510, 30), {
		Position = UDim2.fromOffset(24, 216), TextSize = 22, Font = Theme.Font, TextColor3 = C.dim, ZIndex = 6,
	})
	-- Your company: a slim hairline row.
	local company = Ui.make("Frame", {
		Size = UDim2.fromOffset(512, 64), Position = UDim2.fromOffset(24, 264),
		BackgroundColor3 = K.row, BorderSizePixel = 0, ZIndex = 6,
	}, face)
	Ui.stroke(company, K.line, 1).Transparency = Ui.HAIRLINE
	Ui.caps(company, "Your company", UDim2.fromOffset(488, 16), {
		Position = UDim2.fromOffset(12, 10), ZIndex = 7,
	})
	infoLabel = Ui.label(company, "Loading your company...", UDim2.fromOffset(488, 24), {
		Position = UDim2.fromOffset(12, 30), TextSize = 17, ZIndex = 7,
	})
	Menu.setState(lastState)
	-- PLAY: the phone's red primary action (Contract.red: a red face, white caps, square).
	local play = Ui.button(face, "PLAY  /  START YOUR SHIFT", UDim2.fromOffset(512, 72), K.red, function() end)
	play.Position = UDim2.fromOffset(24, 344)
	play.TextSize = 23
	play.ZIndex = 7

	-- Controls live on a separate card so the start screen remains readable on phones.
	local help = Ui.ticket(center, UDim2.fromScale(1, 1), UDim2.new())
	help.BackgroundColor3 = K.charcoal
	help.BackgroundTransparency = 0.06
	local helpTicket = help.Parent
	helpTicket.Name = "ControlsCard"
	helpTicket.ZIndex, helpTicket.Visible = 15, false
	-- The ZDC heading: [■ ZDC] | [glyph] CONTROLS.
	local helpHeading = Ui.heading(help, "Controls", { glyph = "settings", textSize = 22, height = 38 })
	helpHeading.frame.Size = UDim2.fromOffset(380, 38)
	helpHeading.frame.Position = UDim2.fromOffset(24, 25)
	for _, part in helpHeading.frame:GetDescendants() do
		if part:IsA("GuiObject") then
			part.ZIndex = 16
		end
	end
	local closeHelp = Ui.ghostButton(help, "‹  BACK", UDim2.fromOffset(116, 48), nil, function()
		helpTicket.Visible, faceTicket.Visible = false, true
	end)
	closeHelp.Position, closeHelp.ZIndex = UDim2.fromOffset(420, 20), 16
	local touchLayout = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local controlsText: { { string } } = if touchLayout then {
		{ "MOVE", "Left thumbstick    ·    SPRINT: on / off (breath)" }, { "SHOOT", "FIRE button (take the gun first: DRAW)" },
		{ "HANDS", "DRAW / PUNCH buttons left of FIRE" },
		{ "CARGO", "Tap prompts to pick up and load" }, { "PUT DOWN", "PUT DOWN / LET GO / SET DOWN button" },
		{ "WEAPONS", "Tap the weapon line: the wheel" }, { "ITEMS", "Tap the item tags" },
		{ "NAVIGATE", "MAP / CREW / MENU buttons" }, { "EXIT CAR", "EXIT button or the jump button" },
	} else {
		{ "MOVE", "WASD / arrows    ·    Shift: sprint (breath)" }, { "COMBAT", "Mouse: aim    ·    RMB: aim    ·    LMB: shoot" },
		{ "HANDS", "B: holster / draw    ·    V: punch / strike" },
		{ "CARGO", "E: pick up / load    ·    G: put down" }, { "EQUIPMENT", "T: switch weapon    ·    Q: phone    ·    1–5: items" },
		{ "WINDOWS", "J: jobs  ·  M: map  ·  I: bag  ·  C: career" }, { "MOUSE", "Alt: free cursor" },
		{ "VEHICLE", "E: get in / get out    ·    Space: out too" }, { "ADMIN", "P: admin (when authorized)" },
	}
	local rows = {}
	for i, entry in controlsText do
		local row = Ui.make("Frame", {
			Size = UDim2.fromOffset(512, 40), Position = UDim2.fromOffset(24, 84 + (i - 1) * 42), -- 3.9: nine rows fit
			BackgroundColor3 = K.row, BackgroundTransparency = if i % 2 == 0 then 1 else 0,
			BorderSizePixel = 0, ZIndex = 16,
		}, help)
		Ui.label(row, entry[1], UDim2.fromOffset(128, 40), { Position = UDim2.fromOffset(10, 0), TextSize = 14, TextColor3 = K.secondary, ZIndex = 17 })
		Ui.label(row, entry[2], UDim2.fromOffset(366, 40), { Position = UDim2.fromOffset(140, 0), TextSize = 16, Font = Theme.Font, ZIndex = 17 })
		table.insert(rows, row)
	end
	local controlsButton = Ui.ghostButton(face, "CONTROLS", UDim2.fromOffset(240, 44), nil, function()
		helpTicket.Visible, faceTicket.Visible = true, false
	end)
	controlsButton.Position, controlsButton.ZIndex = UDim2.fromOffset(24, 430), 7
	local enterHint = Ui.label(face, if touchLayout then "Tap PLAY to begin" else "Press ENTER to begin", UDim2.fromOffset(244, 44), {
		Position = UDim2.fromOffset(292, 430), TextSize = 15, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 7,
	})
	-- Over the world: a compact charcoal label behind the text.
	local version = Ui.make("TextLabel", {
		Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(1, -12, 1, -10), AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 0, BackgroundColor3 = P.pill, Text = `version {Config.Version}`,
		TextSize = 14, Font = Theme.MonoFont, TextColor3 = C.dim, ZIndex = 6,
	}, gui)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, version)

	local viewportConnection: RBXScriptConnection? = nil
	local cameraConnection: RBXScriptConnection? = nil
	local function fitMenu()
		local camera = workspace.CurrentCamera
		local v = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local compact = v.Y < 480
		local narrow = v.X < 600 and not compact
		local height = if compact then 440 elseif narrow and helpTicket.Visible then 820 elseif narrow then 650 else 500
		local factor = math.max(0.35, math.min((v.X - 32) / 560, (v.Y - 64) / height, 1.05))
		menuScale.Scale = factor
		center.Size = UDim2.fromOffset(560, height)
		center.Position = if v.X < 900 then UDim2.fromScale(0.5, 0.5) else UDim2.new(0.08, 0, 0.5, 0)
		center.AnchorPoint = if v.X < 900 then Vector2.new(0.5, 0.5) else Vector2.new(0, 0.5)
		topTitle.Position = UDim2.fromOffset(24, if compact then 48 else 60)
		bottomTitle.Position = UDim2.fromOffset(24, if compact then 110 else 128)
		tagline.Position = UDim2.fromOffset(24, if compact then 192 else 216)
		company.Position = UDim2.fromOffset(24, if compact then 234 else 264)
		company.Size = UDim2.fromOffset(512, if narrow then 112 else 64)
		infoLabel.TextSize = math.max(17, 14 / factor)
		infoLabel.Size = UDim2.fromOffset(488, if narrow then 70 else 24)
		tagline.TextSize = math.max(22, 14 / factor)
		enterHint.TextSize = math.max(15, 12 / factor)
		play.Position = UDim2.fromOffset(24, if compact then 308 elseif narrow then 392 else 344)
		play.Size = UDim2.fromOffset(512, math.max(if compact then 56 else 72, 44 / factor))
		local controlY = if compact then 374 elseif narrow then 498 else 430
		controlsButton.Position = UDim2.fromOffset(24, controlY)
		controlsButton.Size = UDim2.fromOffset(240, math.max(44, 44 / factor))
		enterHint.Position = UDim2.fromOffset(292, controlY)
		closeHelp.Size = UDim2.fromOffset(116, math.max(48, 44 / factor))
		for i, row in rows do
			local gap = if compact then 38 elseif narrow then 82 else 46 -- (3.9: nine rows still fit the card)
			local rowHeight = if narrow then 80 else 44
			row.Position = UDim2.fromOffset(24, 84 + (i - 1) * gap)
			row.Size = UDim2.fromOffset(512, rowHeight)
			for _, child in row:GetChildren() do
				if child:IsA("TextLabel") then
					child.Size = UDim2.new(child.Size.X.Scale, child.Size.X.Offset, 0, rowHeight)
					child.TextSize = math.max(16, 13 / factor)
				end
			end
		end
	end
	local function watchCamera()
		if viewportConnection then viewportConnection:Disconnect() end
		local camera = workspace.CurrentCamera
		viewportConnection = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitMenu) else nil
		fitMenu()
	end
	cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
	watchCamera()
	helpTicket:GetPropertyChangedSignal("Visible"):Connect(fitMenu)

	-- The black fade only shows (and only exists in front of PLAY) after PLAY was pressed.
	local fade = Ui.make("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = P.veil,
		BackgroundTransparency = 1,
		Visible = false,
		Active = false,
		ZIndex = 50,
	}, gui)

	local pressed = false
	local keyConnection: RBXScriptConnection? = nil
	local function start()
		if pressed then
			return
		end
		pressed = true
		if viewportConnection then viewportConnection:Disconnect() end
		if cameraConnection then cameraConnection:Disconnect() end
		if keyConnection then
			keyConnection:Disconnect()
		end
		fade.Visible = true
		local t = TweenService:Create(fade, TweenInfo.new(0.4), { BackgroundTransparency = 0 })
		t:Play()
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
		infoLabel = nil
	end
	play.Activated:Connect(start)
	keyConnection = UserInputService.InputBegan:Connect(function(input, processed)
		-- (not the Enter that sends a chat line, nor a press a button already took)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonA then
			task.spawn(start)
		end
	end)

	task.spawn(controls, false)
	fly()
	player:SetAttribute("StartScreen", true) -- 9.6: the loading screen (ReplicatedFirst) may go
end

return Menu
