--!strict
-- 5.5: the courier phone's motion (client/Phone.luau), in the approved look (design/phone-ui/): no new surfaces.
--   * turn(body, scaler, from, to, position, scale, done): the phone turns sideways for a big app (BOARD, CAREER,
--     SHOP, BAG) or back upright: its Rotation, its place and its scale in one 0.28 s tween, then `done` (Phone builds
--     the body again in the new shape). Under reduced motion: no tween, `done` at once.
--   * banner(screen, top, from, text, onTap): a new message or a new board drops from the top of the open phone for
--     2.5 s, drawn like the home screen's message row (a charcoal row, a fine line, the sender in caps, the text in
--     the secondary colour); a tap opens it. A newer banner replaces the last one.
-- Presentation only.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)

local K = Theme.Contract
local PhoneMotion = {}

local TURN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local DROP = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local banner: any = nil

function PhoneMotion.reducedMotion(): boolean
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

-- A tween; `done` once it has played to the end.
local function play(target: Instance, info: TweenInfo, goal: { [string]: any }, done: (() -> ())?)
	local tween = TweenService:Create(target, info, goal)
	if done then
		tween.Completed:Connect(function(state: Enum.PlaybackState)
			if state ~= Enum.PlaybackState.Cancelled then
				done()
			end
		end)
	end
	tween:Play()
end

-- Turns the body (AnchorPoint 0.5, 0.5) from `from` to `to` degrees while it moves to `position` and its UIScale goes
-- to `scale`, then `done`.
function PhoneMotion.turn(body: GuiObject, scaler: UIScale, from: number, to: number, position: UDim2, scale: number, done: () -> ())
	body.Rotation = from
	if PhoneMotion.reducedMotion() then
		body.Rotation = to
		body.Position = position
		scaler.Scale = scale
		done()
		return
	end
	play(scaler, TURN, { Scale = scale })
	play(body, TURN, { Rotation = to, Position = position }, done)
end

-- The notification banner under the status bar (`top` px down the screen).
function PhoneMotion.banner(screen: Instance, top: number, from: string, text: string, onTap: () -> ())
	if banner then
		banner:Destroy()
		banner = nil
	end
	local made = Ui.make("TextButton", {
		Name = "Banner",
		Size = UDim2.new(1, -24, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0, top + 4),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = K.row,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 30,
	}, screen)
	banner = made
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, made)
	Ui.list(made, true, 2)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 9) }, made)
	Ui.make("Frame", { Name = "Accent", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = K.red, BorderSizePixel = 0, ZIndex = 31 }, made)
	P.caps(made, string.upper(from), UDim2.new(1, 0, 0, 16), { LayoutOrder = 1, TextStrokeTransparency = 1, TextColor3 = K.text, TextSize = 11, ZIndex = 31 })
	local body = Ui.label(made, text, UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Font = Theme.Font,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 31,
	})
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(math.huge, 32) }, body)
	local reduced = PhoneMotion.reducedMotion()
	if not reduced then
		local shown = made.Position
		made.Position = UDim2.new(0.5, 0, 0, top - 80)
		play(made, DROP, { Position = shown })
	end
	local function dismiss()
		if banner == made then
			banner = nil
		end
		if not made.Parent then
			return
		end
		if reduced then
			made:Destroy()
			return
		end
		play(made, DROP, { Position = UDim2.new(0.5, 0, 0, top - 80) }, function()
			made:Destroy()
		end)
	end
	made.Activated:Connect(function()
		local sound = Ui.onClick
		if sound then
			sound()
		end
		dismiss()
		onTap()
	end)
	task.delay(2.5, function()
		if banner == made then
			dismiss()
		end
	end)
	return made
end

return PhoneMotion
