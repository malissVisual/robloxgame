--!strict
-- 4.2: the touch buttons for what a keyboard has keys for (a phone or a tablet without a keyboard, Ui.touchLayout):
--   * SPRINT (Shift on a computer, the left stick click on a gamepad): a toggle next to Roblox's jump button. On, you
--     sprint whenever you move and have breath, on the same breath (client/Stamina.luau, through
--     CameraRig.setTouchSprint); it turns itself off when the breath runs dry, in a seat or on death. Lit while on.
--     Shown on foot with free hands.
--   * The hand button's place (Hud's PUNCH / STRIKE on foot, client/Holster.luau) says:
--       EXIT      while you sit in a car seat: out at your door the way E does it (CarBoarding.exit). Roblox's jump
--                 button still gets you out too (the seat's own jump, like Space).
--       PUT DOWN  while you carry a piece, LET GO while you lead a horse, SET DOWN while you push the trolley or the
--                 pallet jack: what the G prompt in your hands does (the "PutDown" remote; the server checks it,
--                 server/Cargo.luau, server/Equipment.luau). The prompt itself still works when you tap it.
--   * WHEELIE (6.10; Shift on a computer, R1 on a gamepad): in SPRINT's place while you ride an E-Scooter: hold it and
--     the scooter pops onto its back wheel (client/Drive.luau, Drive.setWheelieHeld), let go and it comes down. Lit
--     while held.
-- Hud builds them into its ScreenGui (TouchControls.build) and its layout() places them (TouchControls.place, the boxes
-- of client/TouchLayout.luau), so they hide with the HUD. The 3.8 contract look, like FIRE and the hand buttons: a
-- charcoal face, white type, a fine light line, the red accent; at least 44 px each way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local Theme = require(script.Parent.Theme)
local Ui = require(script.Parent.Ui)
local CameraRig = require(script.Parent.CameraRig)
local CarBoarding = require(script.Parent.CarBoarding)
local Drive = require(script.Parent.Drive)

local TouchControls = {}

local K = Theme.Contract
local REST = 0.35 -- the charcoal face's transparency (FIRE's)
local LIT = 0.08 -- SPRINT on

type Box = { x0: number, y0: number, x1: number, y1: number }
type Parts = {
	sprint: TextButton,
	sprintStroke: UIStroke,
	sprintAccent: Frame,
	act: TextButton,
	actKind: string, -- "" (hidden) | "exit" | "put"
	wheelie: TextButton, -- 6.10: in SPRINT's place on an E-Scooter (held)
	wheelieHeld: boolean,
}

local player = Players.LocalPlayer
local parts: Parts? = nil

-- A square touch button in the contract look (Hud's FIRE and hand buttons).
local function button(parent: Instance, name: string, text: string): (TextButton, UIStroke, Frame)
	local made: TextButton = Ui.make("TextButton", {
		Name = name,
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = REST,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = K.text,
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextWrapped = true,
		AutoButtonColor = false,
		Visible = false,
	}, parent)
	local stroke: UIStroke = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.text, Thickness = 1, Transparency = 0.3 }, made)
	local accent: Frame = Ui.make("Frame", { Name = "Accent", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = K.red, BorderSizePixel = 0 }, made)
	-- A brief dip on the press (no bounce).
	made.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			made.BackgroundTransparency = math.max(0, made.BackgroundTransparency - 0.2)
		end
	end)
	return made, stroke, accent
end

-- What the hand button's place says now: "exit" in a car seat, "put" with something in your hands (and its word).
local function actFor(character: Model?, humanoid: Humanoid?): (string, string)
	if not character or not humanoid or humanoid.Health <= 0 then
		return "", ""
	end
	if CarBoarding.seated() then
		return "exit", "EXIT"
	end
	local carrying = character:GetAttribute("Carrying")
	if type(carrying) ~= "string" or carrying == "" then
		return "", ""
	end
	if character:GetAttribute("Pushing") ~= nil then
		return "put", "SET DOWN"
	end
	return "put", if carrying == "horse" then "LET GO" else "PUT DOWN"
end

local function refresh(p: Parts)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local kind, words = actFor(character, humanoid)
	p.actKind = kind
	p.act.Visible = kind ~= ""
	if words ~= "" and p.act.Text ~= words then
		p.act.Text = words
	end
	-- SPRINT: on foot, free hands, alive, out of any seat.
	local onFoot = character ~= nil and humanoid ~= nil and humanoid.Health > 0 and humanoid.SeatPart == nil and not CarBoarding.seated()
	local free = onFoot and character ~= nil and character:GetAttribute("Carrying") == nil
	p.sprint.Visible = free
	local on, running = CameraRig.touchSprint()
	local face = if on then LIT else REST
	if p.sprint.GuiState ~= Enum.GuiState.Press then
		p.sprint.BackgroundTransparency = face
	end
	p.sprint.BackgroundColor3 = if on then K.raised else K.charcoal
	p.sprintStroke.Color = if on then K.red else K.text
	p.sprintStroke.Transparency = if on then 0 else 0.3
	p.sprintAccent.Size = if running then UDim2.new(0, 4, 1, 0) else UDim2.new(0, 2, 1, 0)
	if p.act.GuiState ~= Enum.GuiState.Press then
		p.act.BackgroundTransparency = REST
	end
	-- 6.10: WHEELIE while you drive an E-Scooter (let go when it goes)
	local car, driving = Drive.seatedCar()
	local riding = driving and car ~= nil and car:GetAttribute("BikeStand") == true and CarBoarding.seated()
	p.wheelie.Visible = riding
	if not riding and p.wheelieHeld then
		p.wheelieHeld = false
		Drive.setWheelieHeld(false)
	end
	p.wheelie.BackgroundTransparency = if p.wheelieHeld then LIT else REST
	p.wheelie.BackgroundColor3 = if p.wheelieHeld then K.raised else K.charcoal
end

-- Builds the buttons into the HUD's ScreenGui (only on a touch layout; a computer has the keys).
function TouchControls.build(gui: Instance)
	if parts or not Ui.touchLayout() then
		return
	end
	local sprint, sprintStroke, sprintAccent = button(gui, "Sprint", "SPRINT")
	local act = button(gui, "TouchAct", "EXIT")
	local wheelie = button(gui, "Wheelie", "WHEELIE")
	local made: Parts = {
		sprint = sprint,
		sprintStroke = sprintStroke,
		sprintAccent = sprintAccent,
		act = act,
		actKind = "",
		wheelie = wheelie,
		wheelieHeld = false,
	}
	parts = made
	-- 6.10: held, not tapped: up while the finger is on it. 6.10 review: that finger's own input lets go, also when it
	-- slid off the button before it lifted (the button's InputEnded does not come then); a second finger is ignored.
	local holding: InputObject? = nil
	local function letGo()
		holding = nil
		made.wheelieHeld = false
		Drive.setWheelieHeld(false)
		refresh(made)
	end
	wheelie.InputBegan:Connect(function(input: InputObject)
		if holding ~= nil or (input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1) then
			return
		end
		holding = input
		made.wheelieHeld = true
		Drive.setWheelieHeld(true)
		refresh(made)
		local watch: RBXScriptConnection? = nil
		watch = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			local state = input.UserInputState
			if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				if watch then
					watch:Disconnect()
				end
				if holding == input then
					letGo()
				end
			end
		end)
	end)
	wheelie.InputEnded:Connect(function(input: InputObject)
		if input == holding then
			letGo()
		end
	end)
	sprint.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		local on = CameraRig.touchSprint()
		CameraRig.setTouchSprint(not on)
		refresh(made)
	end)
	act.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		if made.actKind == "exit" then
			CarBoarding.exit()
		elseif made.actKind == "put" then
			Net.get("PutDown"):FireServer()
		end
	end)
	-- A few times a second is plenty for what they show (a seat, the hands, the toggle).
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since < 0.1 then
			return
		end
		since = 0
		refresh(made)
	end)
	refresh(made)
end

local function put(object: GuiObject, b: Box)
	object.AnchorPoint = Vector2.zero
	object.Position = UDim2.fromOffset(math.floor(b.x0 + 0.5), math.floor(b.y0 + 0.5))
	object.Size = UDim2.fromOffset(math.floor(b.x1 - b.x0 + 0.5), math.floor(b.y1 - b.y0 + 0.5))
end

-- Hud's layout(): SPRINT next to the jump button, EXIT / PUT DOWN in the hand button's place (px in the HUD's gui).
function TouchControls.place(sprint: Box, act: Box, textSize: number)
	local p = parts
	if not p then
		return
	end
	put(p.sprint, sprint)
	put(p.act, act)
	put(p.wheelie, sprint) -- (6.10: SPRINT hides in a seat)
	p.sprint.TextSize = textSize
	p.act.TextSize = textSize
	p.wheelie.TextSize = textSize
end

return TouchControls
