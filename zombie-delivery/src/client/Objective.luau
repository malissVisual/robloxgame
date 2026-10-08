--!strict
-- 6.5, the NEXT card (the owner: "When I join I don't know what to do. I can't find my way in anything."): the first
-- thing in the HUD's contract column (client/Hud.luau's slot "job", over the contract group), always there on foot and
-- in a vehicle. One answer to "what do I do now?", its words from shared/Goal.luau:
--
--   ▌ ▶ NEXT                              a small red tag (▶ MISSION 3 during a mission)
--   ▌ Pick up 2 pizzas (E)                the big title (HeadingFont, it wraps)
--   ▌ Tony's Pizza   120 m                the place and the live distance (the target the world marker shows)
--   ▌ ───────────
--   ▌ ▼ DETAILS · 4:12 LEFT · 2 ORDERS    with a job: a click (a tap) unfolds the contract group under the card
--
-- A charcoal panel with a red left edge (the approved mockup, design: the contract look of client/HudContract.luau).
-- With a job the contract group (the orders, the rules, the timer, the warnings: Hud's view.ticket) is folded by
-- default; a click on the card unfolds it (the choice stays for the session). Without one the card replaces the old
-- OFF DUTY line: "Take a delivery job · Press J · or the job board", and a click opens the board. After a delivery it
-- says "Delivered! +$45 · Press J for the next job" for Config.Goal.ResultShown seconds.
-- It follows Marge's first day too: the Tutorial remote's phase (server/Tutorial.luau), read here as
-- client/TutorialUi.luau reads it (this module does not change her tutorial, it only listens).
-- Hud builds it (Objective.build), feeds it ten times a second (Objective.update: the job, the state, the distance) and
-- shows the card's `action` as its pill at the lower centre.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Goal = require(Shared.Goal)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)

local Objective = {}

local G = Config.Goal
local player = Players.LocalPlayer

local refs: any = {} -- the card's instances
local expanded = false -- the contract group unfolded (the session's choice)
local quiet = false -- 6.12.1: the idle "Take a delivery job" card is held back (an experienced courier)
local phase: string? = nil -- the tutorial's phase (nil: none runs)
local lastResult: { success: boolean, total: number?, at: number }? = nil
local current: Goal.Card? = nil
local shown = "" -- what the card shows (it redraws only when this changes)
local hadJob = false

-- The depot's job board (Config.Goal.BoardSpot from the depot's centre, Map.Shops.depot), on the walk level.
function Objective.boardSpot(): Vector3
	local depot = Map.Shops.depot
	local x = (if depot then depot.x else 0) + G.BoardSpot[1]
	local z = (if depot then depot.z else 0) + G.BoardSpot[2]
	return Vector3.new(x, Map.WalkTop, z)
end

-- Does Marge's own marker show now (client/TutorialUi.luau: TALK TO MARGE over her head, while she waits for you)?
function Objective.margeShown(): boolean
	if phase == "welcome" or phase == "retry" then
		return true
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	local marker = playerGui and playerGui:FindFirstChild("TutorialMarker")
	return marker ~= nil and marker:IsA("BillboardGui") and marker.Enabled
end

-- A delivery result (Hud.showResult): the card says how it went for a few seconds. One order of a run (midJob) is
-- not the end of the job: the job's card goes on.
function Objective.result(r: any)
	if type(r) ~= "table" or r.midJob == true then
		return
	end
	lastResult = { success = r.success == true, total = tonumber(r.total), at = os.clock() }
end

-- Builds the card at the top of `slot` (the contract column's "job" slot), over `details` (the contract group).
-- `openBoard` opens the job board (Hud's openDispatch).
function Objective.build(slot: Instance, details: GuiObject, openBoard: () -> ())
	local touch = Ui.touchLayout()
	local card = Ui.make("TextButton", {
		Name = "Goal",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = P.surface,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = 0, -- (the contract group is 1)
		Visible = false,
	}, slot)
	-- The red left edge.
	Ui.make("Frame", { Name = "Edge", Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = P.red, BorderSizePixel = 0 }, card)
	local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, card)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 10) }, body)
	Ui.list(body, true, 3)
	refs.tag = P.caps(body, "▶ NEXT", UDim2.new(1, 0, 0, 14), { TextColor3 = P.red, TextSize = 12, TextStrokeTransparency = 1, LayoutOrder = 1 })
	refs.title = P.text(body, "", UDim2.new(1, 0, 0, 0), {
		Name = "Title",
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.HeadingFont,
		TextSize = G.TitleSize,
		TextWrapped = true,
		TextStrokeTransparency = 1,
		LineHeight = 1.0,
		LayoutOrder = 2,
	})
	local placeRow = Ui.make("Frame", { Name = "Place", Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 3 }, body)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, placeRow)
	refs.place = P.text(placeRow, "", UDim2.fromOffset(0, 20), {
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 14,
		TextColor3 = P.ink2,
		TextStrokeTransparency = 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = 1,
	})
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(G.PlaceMax, 20) }, refs.place)
	refs.distance = P.text(placeRow, "", UDim2.fromOffset(0, 20), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextStrokeTransparency = 1,
		LayoutOrder = 2,
	})
	refs.placeRow = placeRow
	-- With a job: ▼ DETAILS (the time left, the orders) over a fine line.
	local more = Ui.make("Frame", { Name = "Details", Size = UDim2.new(1, 0, 0, if touch then 26 else 22), BackgroundTransparency = 1, LayoutOrder = 4, Visible = false }, body)
	P.rule(more, UDim2.new(1, 0, 0, 1), { Position = UDim2.fromOffset(0, 3) })
	refs.more = P.caps(more, "", UDim2.new(1, 0, 1, -5), { Position = UDim2.fromOffset(0, 5), TextSize = 11, TextStrokeTransparency = 1 })
	refs.moreRow = more
	refs.card = card
	refs.details = details
	details.Visible = false
	card.MouseEnter:Connect(function()
		card.BackgroundTransparency = 0.1
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundTransparency = 0.22
	end)
	card.Activated:Connect(function()
		local now = current
		local click = Ui.onClick
		if click then
			click()
		end
		if now and now.opensBoard then
			openBoard()
		elseif refs.job then
			expanded = not expanded
			shown = ""
			details.Visible = expanded
		end
	end)
end

-- The words of ▼ DETAILS: the time left and the orders of the run.
local function detailsLine(job: any): string
	if expanded then
		return "▲ DETAILS"
	end
	local parts = { "▼ DETAILS" }
	local ends = tonumber(job.endsAt)
	if ends then
		table.insert(parts, `{Ui.clock(ends - workspace:GetServerTimeNow())} LEFT`)
	end
	if type(job.orders) == "table" and #job.orders > 1 then
		table.insert(parts, `{#job.orders} ORDERS`)
	end
	return table.concat(parts, " · ")
end

-- Ten times a second from Hud: the card for the job (nil: none), the state, the distance to the target (studs; the job's,
-- else the job board's) and whether the column shows somebody else's job instead (a crew member without a job of their
-- own: the crew strip says what to do, the card hides). Returns the card (its `action` is the HUD's pill).
-- 6.5 review: "bus" on a city bus (the BusLine attribute: E rings the stop), "seat" in any other seat, nil on foot.
local function seatNow(character: Model?): string?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.SeatPart == nil then
		return nil
	end
	return if typeof(player:GetAttribute("BusLine")) == "string" then "bus" else "seat"
end

function Objective.update(job: any, state: any, distance: number?, hidden: boolean): Goal.Card?
	if not refs.card or type(state) ~= "table" then
		return nil
	end
	local hasJob = type(job) == "table"
	if hasJob and not hadJob then
		lastResult = nil -- (a new job: the result's words go)
	end
	hadJob = hasJob
	refs.job = if hasJob then job else nil
	local result = lastResult
	if result and os.clock() - result.at > G.ResultShown then
		lastResult = nil
		result = nil
	end
	local character = player.Character
	local carrying = character and character:GetAttribute("Carrying")
	-- (6.5 review: the seat's own E for the pill: a bus's stop bell, any other seat's get out)
	local throwTo = player:GetAttribute("ThrowTo")
	local card = Goal.now({
		job = if hasJob then job else nil,
		deliveries = tonumber(state.deliveries) or 0,
		tutorial = phase,
		result = if result then { success = result.success, total = result.total } else nil,
		distance = if distance then math.floor(distance) else nil,
		holding = if type(carrying) == "string" and carrying ~= "" then carrying else nil,
		canThrow = typeof(throwTo) == "Vector3" and player:GetAttribute("ThrowFragile") ~= true,
		touch = Ui.touchLayout(),
		seat = seatNow(character),
	})
	current = card
	-- 6.12.1: no "Take a delivery job" for a courier who knows the way (Config.Goal.HintJobs deliveries done)
	quiet = not hasJob and card.kind == "nojob" and (tonumber(state.deliveries) or 0) >= G.HintJobs
	local visible = not (hidden and not hasJob) and not quiet
	if refs.card.Visible ~= visible then
		refs.card.Visible = visible
	end
	local unfold = hasJob and expanded
	if refs.details.Visible ~= unfold then
		refs.details.Visible = unfold
	end
	local more = if hasJob then detailsLine(job) else ""
	local key = `{card.tag}|{card.title}|{card.place}|{more}`
	if key ~= shown then
		shown = key
		refs.tag.Text = `▶ {card.tag}`
		refs.title.Text = card.title
		refs.place.Text = card.place or ""
		refs.place.Visible = refs.place.Text ~= ""
		refs.more.Text = more
		refs.moreRow.Visible = hasJob
	end
	local far = if card.distance then `{card.distance} m` else ""
	if refs.distance.Text ~= far then
		refs.distance.Text = far
		refs.distance.Visible = far ~= ""
	end
	local row = refs.place.Visible or far ~= ""
	if refs.placeRow.Visible ~= row then
		refs.placeRow.Visible = row
	end
	return card
end

-- 6.12.1: is the idle card held back (an experienced courier with no job)? client/Hud.luau hides the board's marker
-- then too.
function Objective.quiet(): boolean
	return quiet
end

-- Marge's first day: the phase the Tutorial remote says (as client/TutorialUi.luau reads it: a string is the phase,
-- nil ends it; "say", "phone" and "message" are lines and messages, not phases; "done" ends it too).
function Objective.start()
	local ok, err = pcall(function()
		Net.get("Tutorial").OnClientEvent:Connect(function(newPhase: any)
			if type(newPhase) ~= "string" then
				phase = nil
			elseif newPhase ~= "say" and newPhase ~= "phone" and newPhase ~= "message" then
				phase = if newPhase == "done" then nil else newPhase
			end
			shown = ""
		end)
	end)
	if not ok then
		warn(`[Objective] no Tutorial remote: {err}`)
	end
end

return Objective
