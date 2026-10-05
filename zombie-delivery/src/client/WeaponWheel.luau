--!strict
-- The weapon wheel: hold Q and the guns you own come up on a ring around the middle of the screen; point the mouse
-- at one and let go of Q (or click it) to take it. A quick tap of Q still takes the next gun, as before.
-- The look (GTA-like, in the Dead End Dispatch colours): a dark ring cut into one segment per gun, the segment under
-- the mouse lit with a pointer from the middle, and in the middle the gun's picture, name and bars for its damage,
-- fire rate and range. It pops open (a short scale and fade).
-- In a car seat the two-handed guns are greyed out (only one-handed guns fire out of a window). While the wheel is
-- open the mouse is free (Main adds WeaponWheel.isOpen to CameraRig.mouseNeeded) and a click does not shoot.
-- Keyboard and mouse only: touch screens keep the BAG and the weapon bar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
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
-- The ring, in pixels at scale 1: the band between RING_IN and RING_OUT holds the guns (at SLOT_R).
local RING_OUT = 230
local RING_IN = 118
local SLOT_R = (RING_OUT + RING_IN) / 2
local ICON = 58
local DEAD_ZONE = 60 -- the mouse this close to the middle: no gun picked (letting go keeps yours)
local LIT = C.yellow

local player = Players.LocalPlayer
local state: any = nil

type Slot = { id: string, def: Config.WeaponDef, usable: boolean, angle: number, icon: GuiObject, name: TextLabel, holder: Frame, width: number }

-- The wheel's parts (built once, on the first open).
type Parts = {
	gui: ScreenGui,
	cover: TextButton,
	root: Frame,
	scale: UIScale,
	group: CanvasGroup,
	segments: Frame, -- the separators and the gun slots (rebuilt for the guns you own)
	glow: Frame, -- the lit segment's blob behind the slot under the mouse
	pointer: Frame, -- the diamond on the inner edge, toward the slot under the mouse
	centreIcon: Frame,
	centreName: TextLabel,
	centreTag: TextLabel,
	bars: { { fill: Frame, value: TextLabel } },
	hint: TextLabel,
}
local parts: Parts? = nil
local slots: { Slot } = {}
local open = false
local pressedAt: number? = nil
local hovered: string? = nil
local maxDamage, maxRate, maxRange = 1, 1, 1

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

local function fallbackEmoji(def: Config.WeaponDef): string
	return if def.splash > 0 then "💥" elseif def.pellets > 1 then "🎯" else "🔫"
end

-- Tint an icon (an ImageLabel, or the emoji fallback's TextLabel).
local function tint(icon: Instance, color: Color3, transparency: number)
	if icon:IsA("ImageLabel") then
		icon.ImageColor3 = color
		icon.ImageTransparency = transparency
	elseif icon:IsA("TextLabel") then
		icon.TextTransparency = transparency
	end
end

local function circle(parent: Instance, name: string, diameter: number, color: Color3, transparency: number): Frame
	local frame = Ui.make("Frame", {
		Name = name,
		Size = UDim2.fromOffset(diameter, diameter),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
	}, parent)
	Ui.corner(frame, math.floor(diameter / 2))
	return frame
end

-- ── Building ───────────────────────────────────────────────────────────────

local function build(): Parts
	local screen = Instance.new("ScreenGui")
	screen.Name = "WeaponWheel"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 20
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")
	-- A dark veil over the world; clicks land here (not on the world), so a click while choosing never shoots.
	local cover = Ui.make("TextButton", {
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
	}, screen)
	cover.Activated:Connect(function()
		WeaponWheel.close(true)
	end)
	local side = 2 * RING_OUT + 40
	local root = Ui.make("Frame", {
		Name = "Wheel",
		Size = UDim2.fromOffset(side, side),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, screen)
	local scale = Ui.make("UIScale", { Scale = 1 }, root)
	local group = Ui.make("CanvasGroup", {
		Name = "Group",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 0,
	}, root)

	-- The ring: an outer disc, a thin gold rim, and the darker hole in the middle.
	local outer = circle(group, "Outer", 2 * RING_OUT, C.panel, 0.12)
	local rim = Ui.stroke(outer, LIT, 2)
	rim.Transparency = 0.55
	-- The lit segment: a soft gold disc with a bright rim behind the gun under the mouse.
	local glow = circle(group, "Glow", RING_OUT - RING_IN - 6, LIT, 0.82)
	Ui.stroke(glow, LIT, 2).Transparency = 0.15
	glow.Visible = false
	local segments = Ui.make("Frame", { Name = "Segments", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, group)
	local inner = circle(group, "Inner", 2 * RING_IN, Color3.fromRGB(10, 14, 13), 0.05)
	Ui.stroke(inner, C.grey, 1.5).Transparency = 0.2
	-- The pointer: a gold diamond on the inner edge, turned toward the gun under the mouse.
	local pointer = Ui.make("Frame", {
		Name = "Pointer",
		Size = UDim2.fromOffset(16, 16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = LIT,
		BorderSizePixel = 0,
		Rotation = 45,
		Visible = false,
	}, group)

	-- The middle: the picture, the name, a tag (EQUIPPED / WINDOW / ON FOOT ONLY) and three bars.
	local centreIcon = Ui.make("Frame", {
		Name = "CentreIcon",
		Size = UDim2.fromOffset(78, 56),
		Position = UDim2.new(0.5, 0, 0.5, -60),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, group)
	local centreName = Ui.label(group, "", UDim2.fromOffset(2 * RING_IN - 40, 24), {
		Position = UDim2.new(0.5, 0, 0.5, -18),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = Theme.DisplayFont,
		TextColor3 = C.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.make("UITextSizeConstraint", { MaxTextSize = 20 }, centreName)
	local centreTag = Ui.label(group, "", UDim2.fromOffset(2 * RING_IN - 60, 16), {
		Position = UDim2.new(0.5, 0, 0.5, 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = Theme.HeadingFont,
		TextColor3 = C.dim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.make("UITextSizeConstraint", { MaxTextSize = 12 }, centreTag)
	local bars: { { fill: Frame, value: TextLabel } } = {}
	for index, label in { "DAMAGE", "RATE", "RANGE" } do
		local y = 22 + (index - 1) * 17
		local row = Ui.make("Frame", {
			Name = label,
			Size = UDim2.fromOffset(150, 12),
			Position = UDim2.new(0.5, 0, 0.5, y),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
		}, group)
		Ui.label(row, label, UDim2.fromOffset(52, 12), {
			Font = Theme.HeadingFont,
			TextColor3 = C.dim,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local track = Ui.make("Frame", {
			Size = UDim2.fromOffset(70, 6),
			Position = UDim2.new(0, 54, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = C.grey,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
		}, row)
		Ui.corner(track, 3)
		local fill = Ui.make("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = LIT,
			BorderSizePixel = 0,
		}, track)
		Ui.corner(fill, 3)
		local value = Ui.label(row, "", UDim2.fromOffset(24, 12), {
			Position = UDim2.new(0, 128, 0, 0),
			Font = Theme.HeadingFont,
			TextColor3 = C.text,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		table.insert(bars, { fill = fill, value = value })
	end
	-- Under the ring: what to do.
	local hint = Ui.label(group, "MOVE THE MOUSE  ·  LET GO OF Q TO TAKE IT", UDim2.fromOffset(2 * RING_OUT, 18), {
		Position = UDim2.new(0.5, 0, 1, -6),
		AnchorPoint = Vector2.new(0.5, 1),
		Font = Theme.HeadingFont,
		TextColor3 = C.dim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.make("UITextSizeConstraint", { MaxTextSize = 13 }, hint)

	for _, def in Config.Weapons do
		maxDamage = math.max(maxDamage, def.damage * def.pellets)
		maxRate = math.max(maxRate, def.fireRate)
		maxRange = math.max(maxRange, def.range)
	end
	local built: Parts = {
		gui = screen,
		cover = cover,
		root = root,
		scale = scale,
		group = group,
		segments = segments,
		glow = glow,
		pointer = pointer,
		centreIcon = centreIcon,
		centreName = centreName,
		centreTag = centreTag,
		bars = bars,
		hint = hint,
	}
	parts = built
	return built
end

-- The middle shows this gun (the one under the mouse, else the one in your hands).
local function showCentre(p: Parts, def: Config.WeaponDef?, usable: boolean)
	for _, child in p.centreIcon:GetChildren() do
		child:Destroy()
	end
	if not def then
		p.centreName.Text = ""
		p.centreTag.Text = ""
		for _, bar in p.bars do
			bar.fill.Size = UDim2.fromScale(0, 1)
			bar.value.Text = ""
		end
		return
	end
	local icon = Ui.icon(p.centreIcon, Icons.weapon(def.id), fallbackEmoji(def), UDim2.fromScale(1, 1), {
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	tint(icon, if usable then C.text else C.grey, if usable then 0 else 0.4)
	p.centreName.Text = string.upper(def.name)
	p.centreName.TextColor3 = if usable then C.text else C.grey
	local equipped = state and state.weapon == def.id
	if not usable then
		p.centreTag.Text = "ON FOOT ONLY"
		p.centreTag.TextColor3 = C.red
	elseif equipped then
		p.centreTag.Text = "IN YOUR HANDS"
		p.centreTag.TextColor3 = LIT
	elseif def.oneHanded then
		p.centreTag.Text = "FIRES FROM A CAR WINDOW"
		p.centreTag.TextColor3 = C.green
	else
		p.centreTag.Text = if def.splash > 0 then "EXPLOSIVE" elseif def.pellets > 1 then "SPREAD SHOT" else "TWO-HANDED"
		p.centreTag.TextColor3 = C.dim
	end
	local damage = def.damage * def.pellets
	local shares: { number } = { damage / maxDamage, def.fireRate / maxRate, def.range / maxRange }
	local texts: { string } = { tostring(math.floor(damage)), tostring(def.fireRate), tostring(def.range) }
	for index, bar in p.bars do
		local share = math.clamp(shares[index], 0.04, 1)
		TweenService:Create(bar.fill, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(share, 1) }):Play()
		bar.fill.BackgroundColor3 = if usable then LIT else C.grey
		bar.value.Text = texts[index]
	end
end

local function defOf(id: string): Config.WeaponDef?
	for _, def in Config.Weapons do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- The ring for the guns you own now: a separator between every two, a slot (picture + short name) in each segment.
local function fill(p: Parts)
	for _, child in p.segments:GetChildren() do
		child:Destroy()
	end
	table.clear(slots)
	local list = owned()
	local seated = Drive.seatedCar() ~= nil
	local count = #list
	local step = 2 * math.pi / math.max(count, 1)
	-- Many guns: the slots get narrower so neighbours never overlap.
	local width = math.min(ICON + 40, 2 * SLOT_R * math.sin(step / 2) - 8)
	for index, def in list do
		-- Clockwise from the top.
		local angle = -math.pi / 2 + (index - 1) * step
		-- The separator before this segment: a thin line across the band.
		local edge = angle - step / 2
		Ui.make("Frame", {
			Name = "Separator",
			Size = UDim2.fromOffset(RING_OUT - RING_IN - 10, 2),
			Position = UDim2.new(0.5, math.cos(edge) * SLOT_R, 0.5, math.sin(edge) * SLOT_R),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = math.deg(edge),
			BackgroundColor3 = C.grey,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
		}, p.segments)
		local usable = not seated or def.oneHanded == true
		local holder = Ui.make("Frame", {
			Name = def.id,
			Size = UDim2.fromOffset(width, ICON + 26),
			Position = UDim2.new(0.5, math.cos(angle) * SLOT_R, 0.5, math.sin(angle) * SLOT_R),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, p.segments)
		local icon = Ui.icon(holder, Icons.weapon(def.id), fallbackEmoji(def), UDim2.fromOffset(ICON, ICON * 0.72), {
			Position = UDim2.new(0.5, 0, 0, 4),
			AnchorPoint = Vector2.new(0.5, 0),
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local current = state and state.weapon == def.id
		tint(icon, if not usable then C.grey elseif current then LIT else C.text, if usable then 0 else 0.5)
		local name = Ui.label(holder, string.upper(def.name), UDim2.new(1, 0, 0, 14), {
			Position = UDim2.new(0.5, 0, 1, -16),
			AnchorPoint = Vector2.new(0.5, 0),
			Font = Theme.HeadingFont,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = if not usable then C.grey elseif current then LIT else C.dim,
		})
		Ui.make("UITextSizeConstraint", { MaxTextSize = 11 }, name)
		if current then
			-- A small dot under the gun in your hands.
			local dot = circle(holder, "Equipped", 6, LIT, 0)
			dot.Position = UDim2.new(0.5, 0, 1, 2)
		end
		table.insert(slots, { id = def.id, def = def, usable = usable, angle = angle, icon = icon, name = name, holder = holder, width = width })
	end
end

-- The slot under the mouse (by its direction from the middle), lit; nil in the dead zone (the middle shows your gun).
local function pick()
	local p = parts
	local camera = workspace.CurrentCamera
	if not p or not camera or #slots == 0 then
		return
	end
	-- The wheel sits in the middle of the whole screen (IgnoreGuiInset); the mouse is measured from the same corner.
	local offset = UserInputService:GetMouseLocation() - camera.ViewportSize / 2
	local chosen: number? = nil
	if offset.Magnitude > DEAD_ZONE * p.scale.Scale then
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
		local current = state and state.weapon == slot.id
		tint(slot.icon, if not slot.usable then (if on then C.red else C.grey) elseif on or current then LIT else C.text, if slot.usable then 0 else 0.5)
		slot.name.TextColor3 = if not slot.usable then (if on then C.red else C.grey) elseif on then LIT else (if current then LIT else C.dim)
		TweenService:Create(slot.holder, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
			Size = if on then UDim2.fromOffset(slot.width * 1.18, (ICON + 26) * 1.18) else UDim2.fromOffset(slot.width, ICON + 26),
		}):Play()
	end
	if chosen then
		local slot = slots[chosen]
		local x, y = math.cos(slot.angle), math.sin(slot.angle)
		p.glow.Visible = true
		p.glow.BackgroundColor3 = if slot.usable then LIT else C.red
		TweenService:Create(p.glow, TweenInfo.new(0.1, Enum.EasingStyle.Quad), {
			Position = UDim2.new(0.5, x * SLOT_R, 0.5, y * SLOT_R),
		}):Play()
		p.pointer.Visible = true
		p.pointer.BackgroundColor3 = if slot.usable then LIT else C.red
		p.pointer.Position = UDim2.new(0.5, x * (RING_IN + 2), 0.5, y * (RING_IN + 2))
		showCentre(p, slot.def, slot.usable)
	else
		p.glow.Visible = false
		p.pointer.Visible = false
		local mine = state and defOf(state.weapon)
		showCentre(p, mine, true)
	end
end

-- ── Open / close ───────────────────────────────────────────────────────────

local function openWheel()
	if #owned() < 2 then
		say("Buy more guns at Lead & Co., or earn them by working.")
		return
	end
	local p = parts or build()
	fill(p)
	hovered = "" -- force the first highlight
	local camera = workspace.CurrentCamera
	local size = if camera then math.min(camera.ViewportSize.X, camera.ViewportSize.Y) else 720
	local target = math.clamp(size / 640, 0.55, 1.15)
	open = true
	p.gui.Enabled = true
	-- Pop open: a little smaller and see-through, to full size in a blink.
	p.scale.Scale = target * 0.88
	p.group.GroupTransparency = 0.6
	p.cover.BackgroundTransparency = 1
	local info = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(p.scale, info, { Scale = target }):Play()
	TweenService:Create(p.group, info, { GroupTransparency = 0 }):Play()
	TweenService:Create(p.cover, info, { BackgroundTransparency = 0.45 }):Play()
	pick()
end

-- Close the wheel; `take`: equip the gun under the mouse (a usable one).
function WeaponWheel.close(take: boolean?)
	if not open then
		return
	end
	open = false
	local p = parts
	if p then
		p.gui.Enabled = false
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
			local p = parts
			if open and p then
				fill(p)
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
