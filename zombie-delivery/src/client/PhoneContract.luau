--!strict
-- Approved phone presentation: native white glyphs, depot silhouette, live contract card and red actions.
-- UI only. Values and callbacks come from Phone; uploaded app art remains optional through shared/Icons.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Icons = require(ReplicatedStorage:WaitForChild("Shared").Icons)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local K = Theme.Contract
local Contract = {}

-- Straight line segments in a 32 × 32 glyph box, drawn with native Frames when image IDs are empty.
local GLYPHS: { [string]: { { number } } } = {
	orders = {{4,9,16,3},{16,3,28,9},{28,9,16,16},{16,16,4,9},{4,9,4,24},{4,24,16,30},{16,30,28,24},{28,24,28,9},{16,16,16,30},{10,6,22,13}},
	board = {{10,5,5,5},{5,5,5,29},{5,29,27,29},{27,29,27,5},{27,5,22,5},{10,3,22,3},{22,3,22,8},{22,8,10,8},{10,8,10,3},{10,14,22,14},{10,20,22,20},{10,25,19,25}},
	career = {{5,29,5,23},{12,29,12,18},{19,29,19,12},{26,29,26,5},{7,17,25,3},{19,3,25,3},{25,3,25,9}},
	shop = {{5,11,27,11},{27,11,29,29},{29,29,3,29},{3,29,5,11},{10,14,10,6},{10,6,13,3},{13,3,19,3},{19,3,22,6},{22,6,22,14}},
	map = {{16,2,7,5},{7,5,4,13},{4,13,16,30},{16,30,28,13},{28,13,25,5},{25,5,16,2},{12,10,20,10},{20,10,20,16},{20,16,12,16},{12,16,12,10}},
	messages = {{3,4,29,4},{29,4,29,23},{29,23,13,23},{13,23,6,30},{6,30,6,23},{6,23,3,23},{3,23,3,4}},
	bank = {{2,10,16,2},{16,2,30,10},{30,10,2,10},{5,14,5,25},{12,14,12,25},{20,14,20,25},{27,14,27,25},{3,27,29,27},{1,31,31,31}},
	-- 5.5: the HUD MENU's apps
	missions = {{16,2,20,12},{20,12,30,12},{30,12,22,19},{22,19,25,30},{25,30,16,23},{16,23,7,30},{7,30,10,19},{10,19,2,12},{2,12,12,12},{12,12,16,2}},
	bag = {{7,9,25,9},{25,9,25,30},{25,30,7,30},{7,30,7,9},{12,9,12,4},{12,4,20,4},{20,4,20,9},{11,19,21,19},{21,19,21,26},{21,26,11,26},{11,26,11,19}},
	garage = {{3,20,29,20},{29,20,29,26},{29,26,3,26},{3,26,3,20},{7,20,10,12},{10,12,22,12},{22,12,25,20},{7,26,7,29},{7,29,11,29},{11,29,11,26},{21,26,21,29},{21,29,25,29},{25,29,25,26}},
	crew = {{6,6,12,6},{12,6,12,12},{12,12,6,12},{6,12,6,6},{3,26,3,18},{3,18,15,18},{15,18,15,26},{20,6,26,6},{26,6,26,12},{26,12,20,12},{20,12,20,6},{17,26,17,18},{17,18,29,18},{29,18,29,26}},
	top = {{8,4,24,4},{24,4,22,15},{22,15,10,15},{10,15,8,4},{8,6,3,6},{3,6,5,12},{5,12,9,12},{24,6,29,6},{29,6,27,12},{27,12,23,12},{16,15,16,23},{10,23,22,23},{8,28,24,28},{10,23,8,28},{22,23,24,28}},
	estate = {{3,15,16,4},{16,4,29,15},{6,13,6,29},{26,13,26,29},{6,29,26,29},{13,29,13,20},{13,20,19,20},{19,20,19,29}},
	settings = {{12,2,20,2},{20,2,22,8},{22,8,29,11},{29,11,29,21},{29,21,22,24},{22,24,20,30},{20,30,12,30},{12,30,10,24},{10,24,3,21},{3,21,3,11},{3,11,10,8},{10,8,12,2},{12,12,20,12},{20,12,20,20},{20,20,12,20},{12,20,12,12}},
}

function Contract.glyph(parent: Instance, id: string, size: number)
	local icon = Icons.get(Icons.app(id))
	if icon then
		Ui.make("ImageLabel", { Name = "AppGlyph", Size = UDim2.fromOffset(size, size), Position = UDim2.fromScale(.5,.5), AnchorPoint = Vector2.new(.5,.5), BackgroundTransparency = 1, Image = icon, ImageColor3 = K.text }, parent)
		return
	end
	local box = Ui.make("Frame", { Name = "NativeGlyph", Size = UDim2.fromOffset(size,size), Position = UDim2.fromScale(.5,.5), AnchorPoint = Vector2.new(.5,.5), BackgroundTransparency = 1 }, parent)
	for _, s in GLYPHS[id] or GLYPHS.orders do
		local dx, dy = s[3]-s[1], s[4]-s[2]
		Ui.make("Frame", { Size = UDim2.fromOffset(math.sqrt(dx*dx+dy*dy)*size/32, 1.5), Position = UDim2.fromOffset((s[1]+s[3])*size/64,(s[2]+s[4])*size/64), AnchorPoint = Vector2.new(.5,.5), Rotation = math.deg(math.atan2(dy,dx)), BackgroundColor3 = K.text, BorderSizePixel = 0 }, box)
	end
end

function Contract.brand(parent: Instance, order: number): any
	local header = Ui.make("Frame", { Name = "CourierBrand", Size = UDim2.new(1,0,0,94), BackgroundColor3 = K.charcoal, BorderSizePixel = 0, ClipsDescendants = true, LayoutOrder = order }, parent)
	-- Native silhouette, no wallpaper upload needed; kept behind high-contrast text.
	for n, height in {18,27,20,40,31,24,45,23,33,19,37} do
		Ui.make("Frame", { Name = "Skyline", Size = UDim2.new(1/11,0,0,height), Position = UDim2.new((n-1)/11,0,1,-height), BackgroundColor3 = Color3.fromRGB(28,32,39), BorderSizePixel = 0 }, header)
	end
	P.marker(header, 16, { Position = UDim2.fromOffset(12,16) })
	P.text(header, "ZDC", UDim2.new(1,-48,0,32), { Position = UDim2.fromOffset(40,8), Font = Theme.DisplayFont, TextSize = 30, TextStrokeTransparency = 1 })
	P.caps(header, "COURIER TERMINAL", UDim2.new(1,-24,0,18), { Position = UDim2.fromOffset(12,46), TextSize = 12, TextStrokeTransparency = 1 })
	return header
end

function Contract.card(parent: Instance, onActivate: () -> (), order: number): any
	local hit = Ui.make("TextButton", { Name = "HomeContract", Size = UDim2.new(1,0,0,140), BackgroundColor3 = K.charcoal, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = order }, parent)
	P.rule(hit, UDim2.new(1,0,0,1))
	P.marker(hit, 7, { Position = UDim2.fromOffset(10,13) })
	local tag = P.caps(hit, "", UDim2.new(1,-36,0,18), { Position = UDim2.fromOffset(24,7), TextSize = 12, TextStrokeTransparency = 1 })
	local title = P.text(hit, "", UDim2.new(1,-20,0,42), { Position = UDim2.fromOffset(10,29), Font = Theme.HeadingFont, TextSize = 19, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, TextStrokeTransparency = 1 })
	local meta = P.text(hit, "", UDim2.new(1,-20,0,20), { Position = UDim2.fromOffset(10,75), TextSize = 13, TextColor3 = K.secondary, TextStrokeTransparency = 1 })
	local clock = P.text(hit, "", UDim2.new(.58,-10,0,22), { Position = UDim2.fromOffset(10,97), TextSize = 14, TextStrokeTransparency = 1 })
	local pay = P.text(hit, "", UDim2.new(.42,-10,0,22), { Position = UDim2.new(.58,0,0,97), Font = Theme.HeadingFont, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 1 })
	local track, fill = P.bar(hit, UDim2.new(1,-20,0,3), K.red)
	track.Position = UDim2.fromOffset(10,130)
	local underline = P.rule(hit, UDim2.new(1,0,0,1), { Position = UDim2.new(0,0,1,-1), BackgroundColor3 = K.red, BackgroundTransparency = 1 })
	P.hover(hit, underline, title)
	hit.Activated:Connect(onActivate)
	return { hit = hit, tag = tag, title = title, meta = meta, clock = clock, pay = pay, fill = fill, track = track }
end

function Contract.updateCard(card: any, summary: any)
	card.tag.Text = if summary.active then `ACTIVE ORDER{if (summary.count or 1) > 1 then ` · {summary.count} ON THE GO` else ""}` else "DISPATCH BOARD"
	card.title.Text = summary.title
	card.meta.Text = summary.meta
	card.clock.Text = if summary.left then `LEFT {Ui.clock(summary.left)}` elseif summary.active then "VIEW ORDER  →" else "OPEN BOARD  →"
	card.clock.TextColor3 = if summary.left and summary.left < 30 then K.red else K.text
	card.pay.Text = if summary.active then Ui.money(summary.pay) else ""
	card.track.Visible = summary.left ~= nil
	card.fill.Size = UDim2.fromScale(summary.share,1)
end

function Contract.primary(button: any)
	button.BackgroundColor3 = K.red
	button.TextColor3 = K.text
end

return Contract
