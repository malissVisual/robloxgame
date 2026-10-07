--!strict
-- 5.7: the pay of a short run as a float. A foot or bike run done gets a toast and this, not the DELIVERY window
-- (client/Hud.luau showResult): "+$85 · +90 XP" rises from under the money line of the HUD and fades out in about
-- two seconds. Reduced motion (the GuiService setting): it only fades, no rise.
--
--   PayFloat.show(anchor, text)   floats `text` from just under `anchor` (a GuiObject in a ScreenGui: the money label)

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local PayFloat = {}

local RISE = 34 -- px
local SECONDS = 1.9

function PayFloat.show(anchor: GuiObject, text: string)
	local gui = anchor:FindFirstAncestorWhichIsA("ScreenGui")
	if not gui then
		return
	end
	local at = anchor.AbsolutePosition + Vector2.new(0, anchor.AbsoluteSize.Y + 4)
	local label = Instance.new("TextLabel")
	label.Name = "PayFloat"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.Position = UDim2.fromOffset(at.X, at.Y)
	label.Font = Theme.HeadingFont
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(120, 220, 140)
	label.TextStrokeColor3 = Color3.fromRGB(16, 18, 20)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.ZIndex = 20
	label.Parent = gui
	local reduced = false
	pcall(function()
		reduced = (GuiService :: any).ReducedMotionEnabled == true
	end)
	local info = TweenInfo.new(SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local goal: { [string]: any } = { TextTransparency = 1, TextStrokeTransparency = 1 }
	if not reduced then
		goal.Position = UDim2.fromOffset(at.X, at.Y - RISE)
	end
	TweenService:Create(label, info, goal):Play()
	task.delay(SECONDS + 0.1, function()
		label:Destroy()
	end)
end

return PayFloat
