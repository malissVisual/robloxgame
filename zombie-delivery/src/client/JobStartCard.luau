--!strict
-- 6.19.1, the JOB STARTED card (the owner: "when you take a job, something else pops up like SHOW ROUTE, that's boring:
-- only for missions, and a nicer UI"). Taking a job (the phone's JOBS, J's board) no longer opens ORDERS: the phone
-- closes and this card slides in at the top of the screen for a few seconds, in the UI kit's look (client/CardKit.luau):
--   * the business's picture on the left (shared/JobThumbs.luau; its emoji while none is uploaded);
--   * "JOB STARTED" in red with how it travels (🚶 / 🚲 / the stars), the business's name, then where it goes;
--   * the pay big and green at the right, the clock under it; the first stop's words ("Pick up at Luigi's") under all;
--   * a thin red line at its foot running out while it shows. The GPS already draws the route (no SHOW ROUTE).
-- Missions keep their own briefing (client/MissionsUi.luau) and the server's notice; the tutorial its own steps: no card
-- for them. A crew member's job (the owner's, followed) shows none either: only a job that is new for you.
-- Presentation only: the server decides every job.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local JobThumbs = require(Shared.JobThumbs)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)
local PhoneMotion = require(script.Parent.PhoneMotion)

local JobStartCard = {}

local player = Players.LocalPlayer
local K = Theme.Contract
local C = CardKit.Color

local SHOW = 4 -- seconds on screen
local WIDTH = 400 -- px at most (narrower screens: their width less the gutters)
local HEIGHT = 96
local TOP = 0.14 -- of the screen's height: under the HUD's top strip and the event banner

local gui: ScreenGui? = nil
local current: Instance? = nil
local had = false -- a job was running at the last update

local function screen(): ScreenGui?
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local made = Ui.make("ScreenGui", {
		Name = "JobStartCard",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 6,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	gui = made
	return made
end

local function sound()
	pcall(function()
		require(script.Parent.Sounds).play("notify", 0.7)
	end)
end

-- The lines a job shows: (title, where, chip, step).
function JobStartCard.words(job: any): (string, string, string, string)
	local _, business = JobThumbs.forJob(job)
	local title = if type(job.jobType) == "table" and type(job.jobType.name) == "string" then job.jobType.name
		elseif business then business
		elseif type(job.cargo) == "string" then job.cargo
		else "Delivery"
	local customer = if type(job.customer) == "string" and job.customer ~= "" then job.customer else nil
	local address = if type(job.address) == "string" then job.address else ""
	local where = if customer then `→ {customer} · {address}` else `→ {address}`
	if type(job.district) == "string" and job.district ~= "" then
		where ..= `, {job.district}`
	end
	local chip = if job.mode == "foot" then "🚶 ON FOOT" elseif job.mode == "bike" then "🚲 BY BIKE" else string.rep("★", math.max(1, tonumber(job.stars) or 1))
	local step = if type(job.stopLabel) == "string" then job.stopLabel else ""
	if job.timed == true then
		step ..= " · rush, beat the clock!"
	elseif (tonumber(job.banditBoost) or 1) > 1 then
		step ..= " · bandits want this cargo!"
	end
	return string.upper(title), where, chip, step
end

local function text(parent: Instance, value: string, props: { [string]: any }): any
	local label = Ui.label(parent, value, UDim2.fromOffset(0, 0), {
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})
	for key, prop in props do
		label[key] = prop
	end
	return label
end

function JobStartCard.show(job: any): Instance?
	local root = screen()
	if not root or type(job) ~= "table" then
		return nil
	end
	if current then
		current:Destroy()
	end
	local title, where, chip, step = JobStartCard.words(job)
	local image, _, emoji = JobThumbs.forJob(job)
	local holder = Ui.make("Frame", {
		Name = "JobStarted",
		Size = UDim2.new(1, -32, 0, HEIGHT),
		Position = UDim2.fromScale(0.5, TOP),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
	}, root)
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(WIDTH, HEIGHT) }, holder)
	current = holder
	local card = Ui.make("CanvasGroup", {
		Name = "Card",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.card,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	}, holder)
	Ui.make("UICorner", { CornerRadius = UDim.new(0, 12) }, card)
	local stroke = Ui.make("UIStroke", { Color = C.primary, Thickness = 1, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, holder)
	stroke.Name = "Edge"
	Ui.make("UICorner", { CornerRadius = UDim.new(0, 12) }, holder)
	-- The picture.
	local thumb = Ui.make("Frame", { Name = "Thumb", Size = UDim2.fromOffset(HEIGHT, HEIGHT), BackgroundColor3 = K.charcoal, BorderSizePixel = 0, ZIndex = 2 }, card)
	CardKit.picture(thumb, { image = image, emoji = emoji or "📦" } :: any, false, 40, 2)
	-- The words.
	local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, -HEIGHT - 24, 1, -16), Position = UDim2.fromOffset(HEIGHT + 12, 8), BackgroundTransparency = 1, ZIndex = 3 }, card)
	text(body, `JOB STARTED · {chip}`, { Name = "Head", Size = UDim2.new(1, -96, 0, 14), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = K.red })
	text(body, title, { Name = "Title", Size = UDim2.new(1, -96, 0, 22), Position = UDim2.fromOffset(0, 15), Font = Theme.HeadingFont, TextSize = 18, TextColor3 = C.title })
	text(body, where, { Name = "Where", Size = UDim2.new(1, -96, 0, 16), Position = UDim2.fromOffset(0, 38), Font = Theme.Font, TextSize = 13, TextColor3 = C.faint })
	text(body, step, { Name = "Step", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 60), Font = Theme.Font, TextSize = 13, TextColor3 = C.text })
	text(body, Ui.money(tonumber(job.pay) or 0), { Name = "Pay", Size = UDim2.fromOffset(92, 30), Position = UDim2.new(1, -92, 0, 4), Font = Theme.HeadingFont, TextSize = 26, TextColor3 = C.money, TextXAlignment = Enum.TextXAlignment.Right })
	local left = if type(job.endsAt) == "number" then job.endsAt - workspace:GetServerTimeNow() else nil
	if left and left > 0 then
		text(body, `⏱ {Ui.clock(left)}`, { Name = "Clock", Size = UDim2.fromOffset(92, 16), Position = UDim2.new(1, -92, 0, 38), Font = Theme.HeadingFont, TextSize = 13, TextColor3 = C.secondary, TextXAlignment = Enum.TextXAlignment.Right })
	end
	-- The line running out at its foot.
	local line = Ui.make("Frame", { Name = "Time", Size = UDim2.new(1, 0, 0, 3), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = C.primary, BorderSizePixel = 0, ZIndex = 4 }, card)
	TweenService:Create(line, TweenInfo.new(SHOW, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 3) }):Play()
	-- In: a slide down and a fade (reduced motion: the fade only); out: a fade.
	local still = PhoneMotion.reducedMotion()
	if not still then
		holder.Position = UDim2.new(0.5, 0, TOP, -18)
		TweenService:Create(holder, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, TOP) }):Play()
	end
	TweenService:Create(card, TweenInfo.new(0.2), { GroupTransparency = 0 }):Play()
	sound()
	task.delay(SHOW, function()
		if not holder.Parent then
			return
		end
		TweenService:Create(card, TweenInfo.new(0.35), { GroupTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		task.wait(0.4)
		holder:Destroy()
		if current == holder then
			current = nil
		end
	end)
	return holder
end

-- Every Job update (Main: the "Job" remote): a job that is new for you (none before), not a mission nor the tutorial nor
-- a crew member's, shows the card.
function JobStartCard.onJob(job: any)
	local now = type(job) == "table"
	local fresh = now and not had
	had = now
	if not fresh then
		return
	end
	if job.mission ~= nil or job.tutorial == true or job.crew == true or job.follower == true then
		return
	end
	JobStartCard.show(job)
end

-- A job ended: the card goes at once.
function JobStartCard.hide()
	if current then
		current:Destroy()
		current = nil
	end
end

return JobStartCard
