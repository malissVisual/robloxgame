--!strict
-- 4.8, the road events' card (server/Jobs.luau, Config.Jobs.RoadEvents): a side pick-up offered on the way ("ADD-ON:
-- +$180 · one more parcel from Old Tom, 140 m off your route") waits for your answer in the contract column (the
-- Hud's top stack, Hud.topSlot("roadevent"), under the contract): TAKE IT (Y, or the button) or NO; it closes on its
-- own when its seconds are up, when the server closes it (nil) or the job ends.
--
-- The server sends the card through the "RoadEvent" remote ({ kind = "addon", title, text, pay, endsAt } or nil) and
-- hears the answer the same way ("accept" | "decline"); it checks everything again (the job, the time, the room).
-- The contract look (client/HudContract.luau): a charcoal scrim, a red rule on the left, white text, flat buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Hud = require(script.Parent.Hud)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)

local RoadEventUi = {}

local remote: RemoteEvent? = nil
local card: any = nil
local refs: { [string]: any } = {}
local endsAt = 0
local open = false

local function close()
	open = false
	if card then
		card.Visible = false
	end
end

local function answer(choice: string)
	if not open then
		return
	end
	close()
	if remote then
		remote:FireServer(choice)
	end
end

local function build()
	if card then
		return
	end
	card = Ui.make("Frame", {
		Name = "RoadEvent",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 1,
	}, Hud.topSlot("roadevent"))
	P.scrim(card, 0.7)
	Ui.make("Frame", { Name = "Edge", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = P.danger, BorderSizePixel = 0, ZIndex = 2 }, card)
	local body = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, card)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 10) }, body)
	Ui.list(body, true, 6)
	local header = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 1 }, body)
	refs.title = P.caps(header, "", UDim2.new(1, -60, 1, 0), { TextColor3 = P.ink })
	refs.time = P.caps(header, "", UDim2.new(0, 60, 1, 0), { Position = UDim2.new(1, -60, 0, 0), TextXAlignment = Enum.TextXAlignment.Right, Font = Theme.MonoFont })
	refs.text = P.text(body, "", UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 14, LayoutOrder = 2 })
	local buttons = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 3 }, body)
	Ui.list(buttons, false, 8)
	local touch = Ui.touchLayout()
	local take = P.button(buttons, if touch then "TAKE IT" else "TAKE IT  [Y]", UDim2.fromOffset(130, 36), "main", function()
		answer("accept")
	end)
	take.LayoutOrder = 1
	local no = P.button(buttons, "NO", UDim2.fromOffset(70, 36), "quiet", function()
		answer("decline")
	end)
	no.LayoutOrder = 2
end

local function show(data: any)
	build()
	if type(data) ~= "table" or data.kind ~= "addon" then
		close()
		return
	end
	refs.title.Text = string.upper(tostring(data.title or "ADD-ON"))
	refs.text.Text = tostring(data.text or "")
	endsAt = tonumber(data.endsAt) or (workspace:GetServerTimeNow() + 15)
	open = true
	card.Visible = true
end

function RoadEventUi.isOpen(): boolean
	return open
end

function RoadEventUi.start()
	remote = Net.get("RoadEvent")
	local event = remote :: RemoteEvent
	event.OnClientEvent:Connect(show)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not open or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Y then
			answer("accept")
		end
	end)
	local shown = -1
	RunService.Heartbeat:Connect(function()
		if not open then
			return
		end
		local left = endsAt - workspace:GetServerTimeNow()
		if left <= 0 then
			close() -- (the server closes it too)
			return
		end
		local seconds = math.ceil(left)
		if seconds ~= shown then
			shown = seconds
			refs.time.Text = `{seconds} S`
		end
	end)
end

return RoadEventUi
