--!strict
-- The weapon wheel: hold Q and the guns you own come up in a ring around the middle of the screen; point the mouse
-- at one and let go of Q (or click it) to take it. A quick tap of Q still takes the next gun, as before.
-- In a car seat the two-handed guns are greyed out (only one-handed guns fire out of a window). While the wheel is
-- open the mouse is free (Main adds WeaponWheel.isOpen to CameraRig.mouseNeeded) and a click does not shoot.
-- Keyboard and mouse only: touch screens keep the BAG and the weapon bar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local Net = require(Shared.Net)
local Drive = require(script.Parent.Drive)
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)

local WeaponWheel = {}

-- Set by Main: a short message (no second gun yet).
WeaponWheel.notify = nil :: ((text: string) -> ())?

local C = Ui.Colors
local HOLD = 0.18 -- seconds Q is held before the wheel opens (shorter: a tap, the next gun)
local RADIUS = 150 -- the ring, in pixels at scale 1
local SLOT = 92
local DEAD_ZONE = 40 -- the mouse this close to the middle: no gun picked (letting go keeps yours)

local player = Players.LocalPlayer
local state: any = nil
local gui: ScreenGui? = nil
local ring: Frame? = nil
local scale: UIScale? = nil
local centerName: TextLabel? = nil
local centerInfo: TextLabel? = nil
local slots: { { id: string, frame: Frame, usable: boolean } } = {}
local open = false
local pressedAt: number? = nil
local hovered: string? = nil

function WeaponWheel.isOpen(): boolean
	return open
end

local function owned(): { Config.WeaponDef }
	local list: { Config.WeaponDef } = {}
	if not state or type(state.weapons) ~= "table" then
		return list
	end
	for _, def in Config.Weapons do
		if state.weapons[def.id] then
			table.insert(list, def)
		end
	end
	return list
end

local function say(text: string)
	local notify = WeaponWheel.notify
	if notify then
		notify(text)
	end
end

local function equip(id: string)
	if state and state.weapon ~= id then
		Net.get("Equip"):FireServer("weapon", id)
	end
end

-- A tap of Q: the next gun you own.
local function nextWeapon()
	local list = owned()
	if #list < 2 then
		say("Buy more guns at Lead & Co., or earn them by working.")
		return
	end
	local index = 0
	for i, def in list do
		if def.id == state.weapon then
			index = i
		end
	end
	equip(list[index % #list + 1].id)
end

-- ── Building ───────────────────────────────────────────────────────────────

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WeaponWheel"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 20
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")
	-- A see-through cover: clicks land here (not on the world), so a click while choosing never shoots.
	local cover = Ui.make("TextButton", {
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Text = "",
		AutoButtonColor = false,
	}, screen)
	cover.Activated:Connect(function()
		WeaponWheel.close(true)
	end)
	local frame = Ui.make("Frame", {
		Name = "Ring",
		Size = UDim2.fromOffset(2 * RADIUS + SLOT + 20, 2 * RADIUS + SLOT + 20),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, screen)
	scale = Ui.make("UIScale", { Scale = 1 }, frame)
	-- The middle: the gun under the mouse and what it does.
	local middle = Ui.make("Frame", {
		Name = "Middle",
		Size = UDim2.fromOffset(170, 170),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
	}, frame)
	Ui.corner(middle, 85)
	Ui.stroke(middle, C.yellow, 2)
	centerName = Ui.label(middle, "", UDim2.new(1, -24, 0, 30), {
		Position = UDim2.new(0, 12, 0.5, -34),
		Font = Theme.DisplayFont,
		TextColor3 = C.yellow,
		TextScaled = true,
	})
	centerInfo = Ui.label(middle, "", UDim2.new(1, -28, 0, 44), {
		Position = UDim2.new(0, 14, 0.5, 0),
		TextColor3 = C.dim,
		TextScaled = true,
		TextWrapped = true,
	})
	gui = screen
	ring = frame
end

local function describe(def: Config.WeaponDef?, usable: boolean): (string, string)
	if not def then
		return "KEEP", "your gun"
	end
	local damage = def.damage * def.pellets
	local info = `{math.floor(damage)} dmg · {def.fireRate}/s`
	if not usable then
		info = "two-handed: not from a car seat"
	elseif def.oneHanded then
		info ..= "\nfires from a car window"
	end
	return string.upper(def.name), info
end

-- The ring for the guns you own now.
local function fill()
	local frame = ring
	if not frame then
		return
	end
	for _, slot in slots do
		slot.frame:Destroy()
	end
	table.clear(slots)
	local list = owned()
	local seated = Drive.seatedCar() ~= nil
	local count = #list
	for index, def in list do
		-- Clockwise from the top.
		local angle = -math.pi / 2 + (index - 1) / count * 2 * math.pi
		local usable = not seated or def.oneHanded == true
		local current = state and state.weapon == def.id
		local slot = Ui.make("Frame", {
			Name = def.id,
			Size = UDim2.fromOffset(SLOT, SLOT),
			Position = UDim2.new(0.5, math.cos(angle) * RADIUS, 0.5, math.sin(angle) * RADIUS),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = if current then C.panelLight else C.panel,
			BackgroundTransparency = 0.1,
		}, frame)
		Ui.corner(slot, SLOT // 2)
		Ui.stroke(slot, if current then C.yellow else C.grey, if current then 2.5 else 1.5)
		Ui.icon(slot, Icons.weapon(def.id), if def.splash > 0 then "💥" elseif def.pellets > 1 then "🎯" else "🔫", UDim2.fromOffset(46, 46), {
			Position = UDim2.new(0.5, -23, 0, 12),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTransparency = if usable then 0 else 0.65,
			ImageTransparency = if usable then 0 else 0.65,
		})
		local name = Ui.label(slot, def.name, UDim2.new(1, -12, 0, 16), {
			Position = UDim2.new(0, 6, 1, -26),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true,
			TextColor3 = if not usable then C.grey elseif current then C.yellow else C.text,
		})
		Ui.make("UITextSizeConstraint", { MaxTextSize = 12 }, name)
		table.insert(slots, { id = def.id, frame = slot, usable = usable })
	end
end

-- The slot under the mouse (by its direction from the middle), highlighted; nil in the dead zone.
local function pick()
	local frame = ring
	if not frame or #slots == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	-- The ring sits in the middle of the whole screen (IgnoreGuiInset), the mouse is measured from the same corner.
	local offset = UserInputService:GetMouseLocation() - camera.ViewportSize / 2
	local chosen: number? = nil
	if offset.Magnitude > DEAD_ZONE * (if scale then scale.Scale else 1) then
		local angle = math.atan2(offset.Y, offset.X) + math.pi / 2 -- 0 at the top, clockwise
		local step = 2 * math.pi / #slots
		chosen = math.floor((angle % (2 * math.pi)) / step + 0.5) % #slots + 1
	end
	local id = if chosen then slots[chosen].id else nil
	if id == hovered then
		return
	end
	hovered = id
	for index, slot in slots do
		local on = index == chosen
		slot.frame.Size = UDim2.fromOffset(if on then SLOT + 14 else SLOT, if on then SLOT + 14 else SLOT)
		local border = slot.frame:FindFirstChild("UiBorder")
		if border and border:IsA("UIStroke") then
			border.Color = if on then (if slot.usable then C.yellow else C.red) elseif state and state.weapon == slot.id then C.yellow else C.grey
			border.Thickness = if on then 3 else 1.5
		end
	end
	local def: Config.WeaponDef? = nil
	local usable = true
	if chosen then
		for _, d in Config.Weapons do
			if d.id == slots[chosen].id then
				def = d
			end
		end
		usable = slots[chosen].usable
	end
	local title, info = describe(def, usable)
	if centerName then
		centerName.Text = title
	end
	if centerInfo then
		centerInfo.Text = info
	end
end

-- ── Open / close ───────────────────────────────────────────────────────────

local function openWheel()
	if #owned() < 2 then
		say("Buy more guns at Lead & Co., or earn them by working.")
		return
	end
	if not gui then
		build()
	end
	fill()
	hovered = "" -- force the first highlight
	local camera = workspace.CurrentCamera
	if scale and camera then
		scale.Scale = math.clamp(math.min(camera.ViewportSize.X, camera.ViewportSize.Y) / 720, 0.6, 1.2)
	end
	open = true
	local screen = gui
	if screen then
		screen.Enabled = true
	end
	pick()
end

-- Close the wheel; `take`: equip the gun under the mouse (a usable one).
function WeaponWheel.close(take: boolean?)
	if not open then
		return
	end
	open = false
	local screen = gui
	if screen then
		screen.Enabled = false
	end
	if take and hovered and hovered ~= "" then
		for _, slot in slots do
			if slot.id == hovered then
				if slot.usable then
					equip(slot.id)
				else
					say("Two-handed guns only fire on foot. Get out of the car first.")
				end
			end
		end
	end
	hovered = nil
end

function WeaponWheel.start()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return
	end
	Net.get("State").OnClientEvent:Connect(function(newState: any)
		if type(newState) == "table" then
			state = newState
			if open then
				fill()
				hovered = ""
				pick()
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode ~= Enum.KeyCode.Q or processed or UserInputService:GetFocusedTextBox() then
			return
		end
		pressedAt = os.clock()
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode ~= Enum.KeyCode.Q then
			return
		end
		local since = pressedAt
		pressedAt = nil
		if open then
			WeaponWheel.close(true)
		elseif since and os.clock() - since < HOLD then
			nextWeapon()
		end
	end)
	RunService.RenderStepped:Connect(function()
		local since = pressedAt
		if not open and since and os.clock() - since >= HOLD then
			openWheel()
		end
		if open then
			pick()
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				WeaponWheel.close(false)
			end
		end
	end)
end

return WeaponWheel
