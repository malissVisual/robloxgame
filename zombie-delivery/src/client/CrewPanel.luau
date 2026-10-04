--!strict
-- The crew panel: invite a player into your job, answer invitations, see your crew and the pay shares.
--
-- K or the CREW button (in the Hud's button column) opens a window with:
--   * what your crew does right now (the leader's job: its step, the clock, how far the stop is),
--   * your crew (the leader and the members, level and distance; the leader may take a member out),
--   * the pay split (Economy.crewSplit: the leader +15 % per member, each member half the pay, on top),
--   * the invitations you got (ACCEPT / DECLINE, they run out after Config.Crew.InviteTimeout) and the ones you sent,
--   * every other player on the server (name, level, distance) with INVITE,
--   * LEAVE (the leader: break the crew up).
-- Outside the window:
--   * an invitation card at the top (ACCEPT / DECLINE right there, or K for the panel),
--   * for a member: the leader's job at the top (like your own job panel, in the GPS purple), the GPS set to the
--     leader's next stop (MapView.setWaypoint: the purple route on the minimap and the big map) and a purple beam
--     over it in the world,
--   * a small tag over your crewmates' heads.
-- The server (server/Crew.luau) checks everything; this module only asks and shows. While the window is open the
-- mouse is free (Main: CameraRig.mouseNeeded checks CrewPanel.isOpen()).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local MapView = require(script.Parent.MapView)

local C = Ui.Colors
local GPS = Color3.fromRGB(176, 92, 255) -- the GPS purple of the maps (client/MapView.luau)
local HIDDEN = CFrame.new(0, -1000, 0)
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis is X: stood up

local CrewPanel = {}

-- Set by client/Main.client.luau: runs right before the window opens (closes the HUD's windows and the leaderboard).
CrewPanel.onOpen = nil :: (() -> ())?

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local crew: any = nil -- the last CrewState (server/Crew.luau stateFor), nil = no crew and no invitations
local ownJob = false -- a job of my own runs (the Job remote)

local inviteRemote: RemoteEvent? = nil
local answerRemote: RemoteEvent? = nil

local gui: any = nil
local window: any = nil
local body: any = nil
local openButton: any = nil
local badge: any = nil
local strip: any = nil -- a member's view of the leader's job (top centre)
local stripTitle: any = nil
local stripTimer: any = nil
local stripStep: any = nil
local stripInfo: any = nil
local card: any = nil -- an invitation (top centre)
local cardTitle: any = nil
local cardTimer: any = nil
local cardText: any = nil
local cardFrom: number? = nil -- whose invitation the card shows
local scales: { any } = {}
local beam: Part? = nil -- the purple beam over the leader's next stop (members)
local gpsSet: Vector3? = nil -- the waypoint this module set (nil = none of ours)
local tags: { [number]: { gui: BillboardGui, head: Instance? } } = {} -- userId → the tag over a crewmate

-- Updaters of the open window (distances, countdowns): rebuilt with every render, run twice a second.
local live: { () -> () } = {}

-- ── Small helpers ──────────────────────────────────────────────────────────

local function hudOn(): boolean
	local hud = playerGui:FindFirstChild("ZombieDeliveryHud")
	return not (hud and hud:IsA("ScreenGui")) or hud.Enabled
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(other: Player): BasePart?
	local character = other.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function myPosition(): Vector3?
	local root = rootOf(player)
	return if root then root.Position else nil
end

-- Flat distance in studs from me (nil when either is nowhere).
local function distanceTo(position: Vector3?): number?
	local mine = myPosition()
	if not mine or not position then
		return nil
	end
	return math.floor(Vector3.new(position.X - mine.X, 0, position.Z - mine.Z).Magnitude + 0.5)
end

local function distanceToPlayer(other: Player): number?
	local root = rootOf(other)
	return distanceTo(if root then root.Position else nil)
end

local function meters(distance: number?): string
	return if distance then `{distance} m` else "–"
end

-- The level of a player: from the crew state, else the leaderboard (leaderstats Level), else unknown.
local function levelOf(other: Player): number?
	if crew then
		local everyone = { crew.owner }
		for _, member in crew.members or {} do
			table.insert(everyone, member)
		end
		for _, entry in everyone do
			if type(entry) == "table" and entry.userId == other.UserId and type(entry.level) == "number" then
				return entry.level
			end
		end
	end
	local stats = other:FindFirstChild("leaderstats")
	local value: any = stats and stats:FindFirstChild("Level")
	if value and (value:IsA("IntValue") or value:IsA("NumberValue")) then
		return value.Value
	end
	local attribute = other:GetAttribute("Level")
	return if type(attribute) == "number" then attribute else nil
end

local function levelText(level: number?): string
	return if level then `Lv {level} · {Levels.rank(level)}` else "Lv ?"
end

local function role(): string?
	return if crew and (crew.role == "owner" or crew.role == "member") then crew.role else nil
end

local function crewIds(): { [number]: boolean }
	local ids = {}
	if role() then
		if type(crew.owner) == "table" then
			ids[crew.owner.userId] = true
		end
		for _, member in crew.members or {} do
			ids[member.userId] = true
		end
	end
	return ids
end

local function listOf(key: string): { any }
	local list = crew and crew[key]
	return if type(list) == "table" then list else {}
end

local function status(): any
	local s = crew and crew.status
	return if type(s) == "table" then s else nil
end

local function stars(count: any): string
	return if type(count) == "number" and count > 0 then string.rep("★", count) .. "  " else ""
end

local function invite(userId: number)
	if inviteRemote then
		inviteRemote:FireServer(userId)
	end
end

local function answer(first: any, second: any?)
	if answerRemote then
		answerRemote:FireServer(first, second)
	end
end

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	-- The same rule as the Hud, so the panels match it on every screen.
	local value = math.clamp(math.min(size.X / 1150, size.Y / 680), 0.55, 1.1)
	for _, s in scales do
		s.Scale = value
	end
end

local function scaled(frame: any): any
	table.insert(scales, Ui.make("UIScale", {}, frame))
	return frame
end

-- ── The window ─────────────────────────────────────────────────────────────

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function heading(text: string)
	Ui.label(body, text, UDim2.new(1, -10, 0, 24), { LayoutOrder = nextOrder(), TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = C.yellow })
end

local function note(text: string, color: Color3?)
	Ui.label(body, text, UDim2.new(1, -10, 0, 0), {
		LayoutOrder = nextOrder(),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		TextColor3 = color or C.dim,
	})
end

local function row(height: number, highlight: Color3?): any
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -10, 0, height),
		BackgroundColor3 = C.panelLight,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
	}, body)
	Ui.corner(frame, 8)
	Ui.stroke(frame, highlight or C.panelLight:Lerp(C.text, 0.13), if highlight then 1.5 else 1)
	return frame
end

-- The name (big) and a line under it on the left of a row; returns the line (for live updates).
local function rowText(frame: any, name: string, sub: string, nameColor: Color3?, buttons: number): any
	local width = -24 - buttons * 120
	Ui.label(frame, name, UDim2.new(1, width, 0, 24), {
		Position = UDim2.fromOffset(14, 6),
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
		TextColor3 = nameColor or C.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return Ui.label(frame, sub, UDim2.new(1, width, 0, 18), {
		Position = UDim2.fromOffset(14, 31),
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

-- A button on the right of a row (slot 1 = the rightmost); a disabled one is grey and does nothing.
local function rowButton(frame: any, text: string, color: Color3, enabled: boolean, slot: number, onClick: () -> ()): any
	local button = Ui.button(frame, text, UDim2.fromOffset(112, 36), if enabled then color else C.grey, function()
		if enabled then
			onClick()
		end
	end)
	button.TextSize = 14
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -10 - (slot - 1) * 120, 0.5, 0)
	if not enabled then
		button.TextColor3 = C.dim
	end
	return button
end

local function countdown(expiresAt: any): string
	local left = if type(expiresAt) == "number" then math.max(0, math.ceil(expiresAt - now())) else 0
	return `{left} s`
end

-- The leader's job (or what to do while there is none).
local function renderJob(myRole: string?)
	local job = status()
	local ownerName = if crew and type(crew.owner) == "table" then crew.owner.name else "The leader"
	if not job then
		if myRole == "member" then
			note(`No job yet: {ownerName} takes one at the job board (J) or an employer, and you work on it together.`, C.text)
		elseif myRole == "owner" then
			note("Take a job (J, or an employer's WORK HERE board): your crew works on it with you.", C.text)
		end
		return
	end
	local frame = row(84, GPS)
	Ui.label(frame, `{stars(job.stars)}{tostring(job.name or "Job")}`, UDim2.new(1, -110, 0, 22), {
		Position = UDim2.fromOffset(14, 6),
		TextSize = 15,
		TextColor3 = C.dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local timer = Ui.label(frame, "", UDim2.fromOffset(90, 22), {
		Position = UDim2.new(1, -104, 0, 6),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 20,
		Font = Enum.Font.GothamBlack,
	})
	Ui.label(frame, tostring(job.step or ""), UDim2.new(1, -28, 0, 24), {
		Position = UDim2.fromOffset(14, 30),
		TextSize = 19,
		Font = Enum.Font.GothamBlack,
		TextColor3 = GPS:Lerp(C.text, 0.35),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local info = Ui.label(frame, "", UDim2.new(1, -28, 0, 18), {
		Position = UDim2.fromOffset(14, 58),
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.dim,
	})
	table.insert(live, function()
		local left = if type(job.endsAt) == "number" then job.endsAt - now() else nil
		timer.Text = if left then Ui.clock(left) else ""
		timer.TextColor3 = if left and left < 15 then C.red else C.text
		local position = if typeof(job.position) == "Vector3" then job.position else nil
		info.Text = if myRole == "member" then `{meters(distanceTo(position))} to the stop  ·  the purple GPS route leads there`
			else `{meters(distanceTo(position))} to the stop`
	end)
end

-- The pay split: a bar (the leader's part and every member's) and the numbers.
local function renderSplit(names: { string }, preview: boolean)
	local split = crew and crew.split
	-- The server counts the riders in the owner's car too (they are paid like members).
	local count = math.max(#names, if type(split) == "table" and type(split.members) == "number" then split.members else 0, 1)
	local ownerShare, memberShare = Economy.crewSplit(100, count)
	local ownerPay = if type(split) == "table" and type(split.ownerPay) == "number" and split.members == count then split.ownerPay else nil
	local memberPay = if type(split) == "table" and type(split.memberPay) == "number" and split.members == count then split.memberPay else nil

	local frame = row(102)
	Ui.label(frame, if preview and count == 1 then "PAY SPLIT  ·  with one member" else "PAY SPLIT", UDim2.new(1, -28, 0, 20), {
		Position = UDim2.fromOffset(14, 6),
		TextSize = 14,
		Font = Enum.Font.GothamBlack,
		TextColor3 = C.yellow,
	})
	-- The bar: every part as wide as its share of everything paid out.
	local bar = Ui.make("Frame", {
		Size = UDim2.new(1, -28, 0, 18),
		Position = UDim2.fromOffset(14, 30),
		BackgroundColor3 = Color3.fromRGB(10, 16, 13),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, frame)
	Ui.corner(bar, 6)
	local total = ownerShare + memberShare * count
	local x = 0
	local leaderIsMe = crew ~= nil and type(crew.owner) == "table" and crew.owner.userId == player.UserId
	local parts = { { share = ownerShare, color = C.yellow, text = if preview or leaderIsMe then "LEADER (YOU)" else "LEADER" } }
	for index = 1, count do
		table.insert(parts, { share = memberShare, color = if index % 2 == 1 then C.blue else C.green, text = names[index] or (if index > #names and not preview then "RIDER" else "MEMBER") })
	end
	for _, part in parts do
		local width = part.share / total
		local piece = Ui.make("Frame", {
			Size = UDim2.new(width, -2, 1, 0),
			Position = UDim2.fromScale(x, 0),
			BackgroundColor3 = part.color,
			BorderSizePixel = 0,
		}, bar)
		Ui.label(piece, part.text, UDim2.fromScale(1, 1), {
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 11,
			Font = Enum.Font.GothamBlack,
			TextColor3 = Color3.fromRGB(9, 14, 11),
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		x += width
	end
	local numbers = if ownerPay and memberPay then `Base pay: leader {Ui.money(ownerPay)}  ·  each {Ui.money(memberPay)}  (+ bonuses)`
		else `Leader {ownerShare} %  ·  each member {memberShare} % of the job's pay`
	Ui.label(frame, numbers, UDim2.new(1, -28, 0, 20), {
		Position = UDim2.fromOffset(14, 54),
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		TextColor3 = C.money,
	})
	local bonus = math.floor(Config.Jobs.CrewDriverBonus * 100 + 0.5)
	Ui.label(frame, `The leader +{bonus} % per member, every member a share on top: nobody loses money.`, UDim2.new(1, -28, 0, 16), {
		Position = UDim2.fromOffset(14, 78),
		TextSize = 13,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.dim,
	})
end

-- Your crew: the leader and the members.
local function renderCrew(myRole: string)
	local owner = crew.owner
	local members = listOf("members")
	heading(`YOUR CREW  ·  {#members}/{crew.maxMembers or Config.Crew.MaxMembers} members`)
	local everyone = { { entry = owner, leader = true } }
	for _, member in members do
		table.insert(everyone, { entry = member, leader = false })
	end
	for _, item in everyone do
		local entry = item.entry
		if type(entry) ~= "table" then
			continue
		end
		local me = entry.userId == player.UserId
		local other = Players:GetPlayerByUserId(entry.userId)
		local canKick = myRole == "owner" and not item.leader
		local frame = row(56, if item.leader then C.yellow else nil)
		local name = (if item.leader then "👑 " else "") .. tostring(entry.name) .. (if me then "  (you)" else "")
		local sub = rowText(frame, name, "", if item.leader then C.yellow else C.text, if canKick then 1 else 0)
		local level = if type(entry.level) == "number" then entry.level else nil
		local function refresh()
			local where = if me then "" elseif other then `  ·  {meters(distanceToPlayer(other))}` else "  ·  left"
			sub.Text = `{if item.leader then "LEADER  ·  " else ""}{levelText(level)}{where}`
		end
		refresh()
		table.insert(live, refresh)
		if canKick then
			rowButton(frame, "REMOVE", C.red, true, 1, function()
				answer("kick", entry.userId)
			end)
		end
	end
end

local function renderInvitations()
	local incoming = listOf("invites")
	if #incoming > 0 then
		heading("INVITATIONS")
		for _, item in incoming do
			local frame = row(60, GPS)
			local sub = rowText(frame, `📨 {item.name} invites you`, "", C.text, 2)
			local job = if type(item.job) == "string" then `{item.job}  ·  ` else "no job yet  ·  "
			local function refresh()
				sub.Text = `{job}{countdown(item.expiresAt)} to answer`
			end
			refresh()
			table.insert(live, refresh)
			local blocked = ownJob or role() ~= nil
			rowButton(frame, "DECLINE", C.red, true, 1, function()
				answer(item.userId, false)
			end)
			rowButton(frame, "ACCEPT", C.green, not blocked, 2, function()
				answer(item.userId, true)
			end)
		end
		if ownJob then
			note("Finish or cancel your own job first to join a crew.", C.yellow)
		elseif role() then
			note("You are in a crew: leave it first to join another one.", C.yellow)
		end
	end
	local pending = listOf("pending")
	if #pending > 0 then
		heading("SENT")
		for _, item in pending do
			local frame = row(56)
			local sub = rowText(frame, `Waiting for {item.name}…`, "", C.text, 1)
			local function refresh()
				sub.Text = `the invitation runs out in {countdown(item.expiresAt)}`
			end
			refresh()
			table.insert(live, refresh)
			rowButton(frame, "CANCEL", C.panel, true, 1, function()
				answer("cancel", item.userId)
			end)
		end
	end
end

-- Every other player on the server, the nearest first.
local function renderPlayers(myRole: string?)
	heading("PLAYERS ON THIS SERVER")
	local others = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			table.insert(others, { player = other, distance = distanceToPlayer(other) or math.huge })
		end
	end
	table.sort(others, function(a, b)
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.player.DisplayName < b.player.DisplayName
	end)
	if #others == 0 then
		note("Nobody else is here yet. Invite a friend to the game (Roblox menu → Invite Friends), then into your crew.")
		return
	end
	local inCrew = crewIds()
	local invited: { [number]: boolean } = {}
	for _, item in listOf("pending") do
		invited[item.userId] = true
	end
	local invitedMe: { [number]: boolean } = {}
	for _, item in listOf("invites") do
		invitedMe[item.userId] = true
	end
	local max = if crew and type(crew.maxMembers) == "number" then crew.maxMembers else Config.Crew.MaxMembers
	local taken = #listOf("members") + #listOf("pending")
	for _, item in others do
		local other: Player = item.player
		local id = other.UserId
		local frame = row(56)
		local sub = rowText(frame, other.DisplayName, "", C.text, 1)
		local function refresh()
			local distance = distanceToPlayer(other)
			local near = distance ~= nil and distance <= Config.Crew.InviteRange
			sub.Text = `{levelText(levelOf(other))}  ·  {meters(distance)}{if near then "  ·  nearby" else ""}`
			sub.TextColor3 = if near then C.green else C.dim
		end
		refresh()
		table.insert(live, refresh)
		local text, enabled = "INVITE", true
		if inCrew[id] then
			text, enabled = "IN CREW", false
		elseif myRole == "member" then
			text, enabled = "LEADER ONLY", false
		elseif invited[id] then
			text, enabled = "INVITED", false
		elseif invitedMe[id] then
			text, enabled = "ASKED YOU", false
		elseif taken >= max then
			text, enabled = "CREW FULL", false
		end
		rowButton(frame, text, C.green, enabled, 1, function()
			invite(id)
		end)
	end
end

local function render()
	if not window or not window.Visible then
		return
	end
	live = {}
	Ui.clear(body)
	order = 0
	local myRole = role()
	local members = listOf("members")
	if myRole == "member" then
		note(`You are in {crew.owner.name}'s crew: carry, shoot and ride along on their job, and get a share of the pay.`, C.text)
	elseif myRole == "owner" then
		note("You lead the crew: your members work on your job (they may carry the cargo, their kills count) and share the pay.", C.text)
	else
		note("Invite players into your job: they carry, shoot and ride along, and each gets a share of the pay. You can invite with or without a job.", C.text)
	end
	renderJob(myRole)
	if myRole then
		renderCrew(myRole)
	end
	local names = {}
	for _, member in members do
		table.insert(names, if member.userId == player.UserId then "YOU" else string.upper(tostring(member.name)))
	end
	renderSplit(names, myRole == nil)
	renderInvitations()
	renderPlayers(myRole)
	if myRole then
		local leave = Ui.button(body, if myRole == "owner" then "BREAK UP THE CREW" else "LEAVE THE CREW", UDim2.new(1, -10, 0, 44), C.red, function()
			answer("leave")
		end)
		leave.LayoutOrder = nextOrder()
		leave.TextSize = 17
	end
	for _, refresh in live do
		refresh()
	end
end

local function setOpen(open: boolean)
	if not window then
		return
	end
	if open then
		-- One window at a time.
		local cb = CrewPanel.onOpen
		if cb then
			cb()
		end
	end
	window.Visible = open
	if open then
		render()
		-- Asks for a fresh state too (levels, an invitation that arrived while loading).
		Net.get("CrewState"):FireServer()
	end
end

-- ── Outside the window: the invitation card, the member's job strip, the GPS, the tags ─────────────────────

-- The first invitation that can still be answered (the card shows it), or nil.
local function firstInvite(): any
	for _, item in listOf("invites") do
		if type(item.expiresAt) == "number" and item.expiresAt > now() then
			return item
		end
	end
	return nil
end

local function updateCard()
	if not card then
		return
	end
	local item = if not ownJob and role() == nil and not (window and window.Visible) then firstInvite() else nil
	card.Visible = item ~= nil
	if not item then
		cardFrom = nil
		return
	end
	cardFrom = item.userId
	cardTitle.Text = "📨  CREW INVITATION"
	cardTimer.Text = countdown(item.expiresAt)
	local job = if type(item.job) == "string" then `: {item.job}` else " (no job yet)"
	cardText.Text = `{item.name} invites you into their crew{job}.`
end

local function updateStrip()
	if not strip then
		return
	end
	local member = role() == "member"
	strip.Visible = member and not ownJob
	if not strip.Visible then
		return
	end
	local ownerName = tostring(crew.owner.name)
	local job = status()
	if not job then
		stripTitle.Text = `👥  CREW  ·  {string.upper(ownerName)}`
		stripTimer.Text = ""
		stripStep.Text = `Waiting for {ownerName} to take a job`
		stripInfo.Text = "K: the crew panel"
		return
	end
	stripTitle.Text = `👥  CREW  ·  {stars(job.stars)}{tostring(job.name or "")}`
	local left = if type(job.endsAt) == "number" then job.endsAt - now() else nil
	stripTimer.Text = if left then Ui.clock(left) else ""
	stripTimer.TextColor3 = if left and left < 15 then C.red else C.text
	stripStep.Text = tostring(job.step or "")
	local position = if typeof(job.position) == "Vector3" then job.position else nil
	local owner = Players:GetPlayerByUserId(crew.owner.userId)
	local ownerDistance = if owner then distanceToPlayer(owner) else nil
	stripInfo.Text = `Stop {meters(distanceTo(position))}  ·  {ownerName} {meters(ownerDistance)}  ·  follow the purple GPS`
end

-- A member's GPS follows the leader's next stop; it is cleared when there is none any more. Set only when the stop
-- changes, so a place the player picks on the big map meanwhile stays until the leader moves on.
local function updateGps()
	local job = if role() == "member" then status() else nil
	local target: Vector3? = if job and typeof(job.position) == "Vector3" then job.position else nil
	if target then
		if not gpsSet or (target - gpsSet).Magnitude > 1 then
			gpsSet = target
			MapView.setWaypoint(target)
		end
	elseif gpsSet then
		gpsSet = nil
		MapView.setWaypoint(nil)
	end
	if beam then
		beam.CFrame = if target and hudOn() then CFrame.new(target + Vector3.new(0, 127, 0)) * UPRIGHT else HIDDEN
	end
end

-- A small tag over every crewmate's head (re-attached after a respawn).
local function updateTags()
	local wanted = crewIds()
	wanted[player.UserId] = nil
	for userId, tag in tags do
		if not wanted[userId] then
			tag.gui:Destroy()
			tags[userId] = nil
		end
	end
	local leaderId = if crew and type(crew.owner) == "table" then crew.owner.userId else nil
	for userId in wanted do
		local other = Players:GetPlayerByUserId(userId)
		local character = other and other.Character
		local head = character and character:FindFirstChild("Head")
		local tag = tags[userId]
		if not tag then
			local billboard: BillboardGui = Ui.make("BillboardGui", {
				Name = "CrewTag",
				Size = UDim2.fromOffset(170, 26),
				StudsOffset = Vector3.new(0, 2.6, 0),
				AlwaysOnTop = true,
				LightInfluence = 0,
				MaxDistance = 500,
				ResetOnSpawn = false,
			}, playerGui)
			Ui.label(billboard, "", UDim2.fromScale(1, 1), {
				Name = "Text",
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = 15,
				Font = Enum.Font.GothamBlack,
				TextColor3 = GPS:Lerp(C.text, 0.3),
				TextStrokeTransparency = 0.35,
				TextWrapped = false,
			})
			tag = { gui = billboard, head = nil }
			tags[userId] = tag
		end
		local text = tag.gui:FindFirstChild("Text")
		if text and text:IsA("TextLabel") and other then
			text.Text = (if userId == leaderId then "👑 " else "👥 ") .. other.DisplayName
		end
		if tag.head ~= head then
			tag.head = head
			tag.gui.Adornee = if head and head:IsA("BasePart") then head else nil
		end
		tag.gui.Enabled = head ~= nil and hudOn()
	end
end

local function updateBadge()
	if not badge then
		return
	end
	local count = #listOf("invites")
	badge.Visible = count > 0
	badge.Text = tostring(count)
end

-- What the open window shows of a state (not the clock or the distances, those run live): an unchanged one is
-- not built again (the state comes every ~2 s during a job).
local function signature(state: any): string
	if type(state) ~= "table" then
		return "-"
	end
	local parts = { tostring(state.role) }
	local function add(...: any)
		for index = 1, select("#", ...) do
			table.insert(parts, tostring((select(index, ...))))
		end
	end
	local function people(list: any)
		for _, item in (if type(list) == "table" then list else {}) do
			if type(item) == "table" then
				add(item.userId, item.name, item.level, item.job, item.expiresAt)
			end
		end
		add("|")
	end
	people({ state.owner })
	people(state.members)
	people(state.invites)
	people(state.pending)
	local job = state.status
	if type(job) == "table" then
		local p = job.position
		add(job.name, job.step, job.stars, job.endsAt, if typeof(p) == "Vector3" then `{math.floor(p.X)},{math.floor(p.Z)}` else "")
	end
	local split = state.split
	if type(split) == "table" then
		add(split.ownerPay, split.memberPay)
	end
	return table.concat(parts, ";")
end

local shown = ""

-- A new CrewState: everything that shows it.
local function apply(state: any)
	crew = if type(state) == "table" then state else nil
	updateBadge()
	updateCard()
	updateStrip()
	updateGps()
	updateTags()
	local current = signature(crew)
	if current ~= shown or not (window and window.Visible) then
		shown = current
		render()
	end
end

-- ── Building ───────────────────────────────────────────────────────────────

-- The CREW button goes into the Hud's button column (JOBS, MAP, BAG, CAR) when it is there; the column grows to
-- fit. Else a button of its own, top right.
local function buildButton()
	local column: Instance? = nil
	local hud = playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud then
		for _, child in hud:GetChildren() do
			for _, button in child:GetChildren() do
				if button:IsA("TextButton") and string.sub(button.Text, 1, 4) == "JOBS" then
					column = child
				end
			end
		end
	end
	local function toggle()
		setOpen(not window.Visible)
	end
	if column and column:IsA("Frame") then
		openButton = Ui.button(column, "CREW  [K]", UDim2.fromOffset(150, 52), C.panelLight, toggle)
		openButton.LayoutOrder = 100
		column.AutomaticSize = Enum.AutomaticSize.Y
	else
		openButton = Ui.button(gui, "CREW  [K]", UDim2.fromOffset(120, 40), C.panelLight, toggle)
		openButton.AnchorPoint = Vector2.new(1, 0)
		openButton.Position = UDim2.new(1, -16, 0, 100)
		openButton.TextSize = 16
		scaled(openButton)
	end
	Ui.stroke(openButton, GPS, 1.5)
	-- How many invitations wait (a red dot with the count).
	badge = Ui.make("TextLabel", {
		Size = UDim2.fromOffset(24, 24),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -4, 0, 4),
		BackgroundColor3 = C.red,
		BorderSizePixel = 0,
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBlack,
		TextSize = 14,
		Visible = false,
		ZIndex = 3,
	}, openButton)
	Ui.corner(badge, 12)
end

local function build()
	gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryCrew",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2,
		Enabled = hudOn(),
	}, playerGui)

	-- The window.
	window = scaled(Ui.panel(gui, UDim2.fromOffset(620, 560), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5)))
	window.Visible = false
	window.BackgroundTransparency = 0.05
	window.ZIndex = 5
	Ui.stroke(window, GPS, 2)
	Ui.label(window, "CREW", UDim2.new(0, 120, 0, 44), { Position = UDim2.fromOffset(18, 6), TextSize = 26, Font = Enum.Font.GothamBlack, TextColor3 = GPS:Lerp(C.text, 0.25) })
	Ui.label(window, "work together · share the pay · K", UDim2.new(1, -220, 0, 44), {
		Position = UDim2.fromOffset(112, 8),
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.dim,
	})
	local close = Ui.button(window, "X", UDim2.fromOffset(40, 40), C.red, function()
		setOpen(false)
	end)
	close.Position = UDim2.new(1, -50, 0, 8)
	body = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -28, 1, -64),
		Position = UDim2.fromOffset(14, 54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, window)
	Ui.list(body, true, 8)

	-- A member's view of the leader's job: top centre, where your own job panel would be (a member has none).
	strip = scaled(Ui.panel(gui, UDim2.fromOffset(500, 0), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0)))
	strip.AutomaticSize = Enum.AutomaticSize.Y
	strip.Visible = false
	Ui.padding(strip, 12)
	Ui.stroke(strip, GPS, 2)
	Ui.list(strip, true, 4)
	local header = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, strip)
	stripTitle = Ui.label(header, "", UDim2.new(1, -80, 1, 0), {
		TextSize = 15,
		TextColor3 = GPS:Lerp(C.text, 0.35),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
	})
	stripTimer = Ui.label(header, "", UDim2.new(0, 80, 1, 0), {
		Position = UDim2.new(1, -80, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 22,
		Font = Enum.Font.GothamBlack,
	})
	stripStep = Ui.label(strip, "", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		TextSize = 21,
		Font = Enum.Font.GothamBlack,
	})
	stripInfo = Ui.label(strip, "", UDim2.new(1, 0, 0, 18), { LayoutOrder = 3, TextColor3 = C.dim, TextSize = 14, Font = Enum.Font.GothamMedium })

	-- The invitation card: top centre too (shown only without a job of your own and without a crew).
	card = scaled(Ui.panel(gui, UDim2.fromOffset(500, 0), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0)))
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Visible = false
	Ui.padding(card, 12)
	Ui.stroke(card, GPS, 2)
	Ui.list(card, true, 6)
	local cardHeader = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, card)
	cardTitle = Ui.label(cardHeader, "", UDim2.new(1, -80, 1, 0), { TextSize = 15, TextColor3 = GPS:Lerp(C.text, 0.35), TextWrapped = false })
	cardTimer = Ui.label(cardHeader, "", UDim2.new(0, 80, 1, 0), {
		Position = UDim2.new(1, -80, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 18,
		Font = Enum.Font.GothamBlack,
	})
	cardText = Ui.label(card, "", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		TextSize = 19,
		Font = Enum.Font.GothamBlack,
	})
	local buttons = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 3 }, card)
	Ui.list(buttons, false, 10)
	local accept = Ui.button(buttons, "ACCEPT", UDim2.fromOffset(140, 40), C.green, function()
		if cardFrom then
			answer(cardFrom, true)
		end
	end)
	accept.LayoutOrder = 1
	local decline = Ui.button(buttons, "DECLINE", UDim2.fromOffset(140, 40), C.red, function()
		if cardFrom then
			answer(cardFrom, false)
		end
	end)
	decline.LayoutOrder = 2
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	Ui.label(buttons, if touch then "or CREW for the panel" else "K: the crew panel · Alt frees the mouse", UDim2.new(1, -300, 1, 0), {
		LayoutOrder = 3,
		TextSize = 13,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.dim,
	})

	buildButton()

	-- The purple beam over the leader's next stop (a member's guide in the world, like the job's own beam).
	local part = Instance.new("Part")
	part.Name = "CrewBeam"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Cylinder
	part.Color = GPS
	part.Transparency = 0.5
	part.Size = Vector3.new(240, 2, 2)
	part.CFrame = HIDDEN
	part.Parent = workspace
	beam = part
end

-- ── API ────────────────────────────────────────────────────────────────────

function CrewPanel.start()
	build()
	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	inviteRemote = Net.get("CrewInvite")
	answerRemote = Net.get("CrewAnswer")
	local stateRemote = Net.get("CrewState")
	stateRemote.OnClientEvent:Connect(apply)
	-- An invitation: the card shows it with the next state (it comes with the invitation); the CREW button flashes.
	Net.get("CrewInvite").OnClientEvent:Connect(function()
		if openButton then
			local stroke = openButton:FindFirstChild("UiBorder")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Color = C.yellow
				task.delay(1.5, function()
					stroke.Color = GPS
				end)
			end
		end
	end)
	Net.get("Job").OnClientEvent:Connect(function(job: any)
		ownJob = job ~= nil
		updateCard()
		updateStrip()
		if window.Visible then
			render()
		end
	end)

	-- The interface follows the Hud (hidden on the start screen).
	local hud = playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud and hud:IsA("ScreenGui") then
		hud:GetPropertyChangedSignal("Enabled"):Connect(function()
			gui.Enabled = hud.Enabled
			if not hud.Enabled then
				window.Visible = false
			end
			updateGps()
			updateTags()
		end)
	end

	-- Players come and go: the open window lists them.
	local function changed()
		if window.Visible then
			render()
		end
	end
	Players.PlayerAdded:Connect(changed)
	Players.PlayerRemoving:Connect(function()
		task.defer(changed)
	end)

	-- K opens and closes the panel (not while typing, e.g. in the chat).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.K or UserInputService:GetFocusedTextBox() or not hudOn() then
			return
		end
		setOpen(not window.Visible)
	end)

	-- Countdowns, distances and the clock: 4 times a second outside the window, twice a second in it; the tags
	-- every second (a respawned crewmate gets theirs back).
	task.spawn(function()
		local beat = 0
		while true do
			task.wait(0.25)
			beat += 1
			local ok, err = pcall(function()
				updateCard()
				updateStrip()
				if window.Visible and beat % 2 == 0 then
					for _, refresh in live do
						refresh()
					end
				end
				if beat % 4 == 0 and (next(tags) ~= nil or role() ~= nil) then
					updateTags()
				end
			end)
			if not ok then
				warn(`[CrewPanel] {err}`)
			end
		end
	end)

	stateRemote:FireServer()
end

function CrewPanel.close()
	setOpen(false)
end

function CrewPanel.isOpen(): boolean
	return window ~= nil and window.Visible == true
end

return CrewPanel
