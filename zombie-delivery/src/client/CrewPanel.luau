--!strict
-- The crew panel: invite a player into your job, answer invitations, see your crew and the pay shares.
--
-- K or the CREW button (the Hud's own, in its button column: Hud.onCrew = CrewPanel.toggle) opens a window with:
--   * what your crew does right now (the leader's job: its step, the clock, how far the stop is),
--   * your crew (the leader and the members, level and distance; the leader may KICK a member),
--   * the pay split (Economy.crewSplit: the leader +15 % per member, each member half the pay, on top),
--   * the invitations you got (ACCEPT / DECLINE, they run out after Config.Crew.InviteTimeout) and the ones you sent,
--   * LOOKING FOR CREW (3.0, the CrewBoard remote): your own toggle and every player on the crew board (name, level,
--     the mission they want, INVITE); MISSIONS' FIND CREW puts you on it for a co-op mission and opens this window,
--   * every other player on the server (name, level, distance) with INVITE,
--   * LEAVE (the leader: break the crew up). Crews outlive the jobs (3.0): play mission after mission together.
-- Outside the window:
--   * the number of invitations waiting on the CREW button (Hud.setBadge), which flashes when one comes,
--   * an invitation card at the top (ACCEPT / DECLINE right there, or K for the panel),
--   * for a member: the leader's job at the top (like your own job panel; on a mission its
--     number, name and twists), the GPS set to the
--     leader's next stop (MapView.setWaypoint: the white GPS route on the minimap and the big map) and a thin white
--     beam over it in the world (4.4.1: white like the GPS on the maps, it was purple),
--   * a small tag over your crewmates' heads.
-- The card and the member's strip sit in the Hud's top stack (Hud.topSlot("crew"), under Roblox's top bar, scaled
-- with it), so they never overlap the job panel, the car call line, the level-up banner or the toasts.
-- The server (server/Crew.luau) checks everything; this module only asks and shows. While the window is open the
-- mouse is free (Main: CameraRig.mouseNeeded checks CrewPanel.isOpen()).
-- 3.8 (the contract UI, design/ui-contract/): the charcoal window (Ui.window), flat rows, the pay split on dark
-- faces; the strip and the invitation card are charcoal scrims with a thin rule on their left (white for the strip,
-- red for an invitation waiting); the tags over heads are compact charcoal labels with light text.
-- 5.8 (the courier phone's look, design/phone-ui/): the ZDC window header with the crew glyph; the section heads carry
-- the phone's small red marker and a thin line; the rows are slim (square, a hairline; a highlighted one raised with a
-- narrow rule on its left: red for the job / an invitation / a co-op seeker, amber for the leader and your own board
-- entry); ACCEPT (in the window and on the invitation card) is the red primary action; KICK, DECLINE, STOP and LEAVE
-- keep the dark danger face, INVITE / LOOK the main one; the pay split is a square bar (the leader's part red).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Missions = require(Shared.Missions)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local MapView = require(script.Parent.MapView)
local Hud = require(script.Parent.Hud)

local C = Ui.Colors
local P = Theme.Postage -- 3.8: remapped to the contract values (see Theme)
local K = Theme.Contract
local GPS = Ui.Gps -- the old GPS purple: on a row it means "highlight" (the maps' GPS route is white now)
local VIOLET = P.violet -- the crew's text accent (3.8: a light accent on charcoal)
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
local boardRemote: RemoteEvent? = nil

-- The crew board (server/Crew.luau boardList): who is looking for a crew, the newest first.
local board: { any } = {}

local gui: any = nil
local window: any = nil
local chrome: any = nil
local body: any = nil
local strip: any = nil -- a member's view of the leader's job (top centre)
local stripTitle: any = nil
local stripTimer: any = nil
local stripStep: any = nil
local stripInfo: any = nil
local stripMission: any = nil -- the leader's mission: its twists, the crew, the defend countdown
local card: any = nil -- an invitation (top centre)
local cardTitle: any = nil
local cardTimer: any = nil
local cardText: any = nil
local cardFrom: number? = nil -- whose invitation the card shows
local scale: any = nil -- the window's UIScale
local beam: Part? = nil -- the thin white beam over the leader's next stop (members)
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

-- ── Missions (3.0) ─────────────────────────────────────────────────────────

-- The mission part of a job status (Jobs.crewStatus `mission`), or nil.
local function missionOf(job: any): any
	local mission = if type(job) == "table" then job.mission else nil
	return if type(mission) == "table" and type(mission.id) == "string" then mission else nil
end

-- "🎯 MISSION 3/10 · Name".
local function missionTitle(mission: any): string
	local number = if type(mission.number) == "number" then `{mission.number}/10` else ""
	return `🎯 MISSION {number}  ·  {tostring(mission.name or "?")}`
end

-- The twists (icon and name), the CO-OP badge and, while holding out, the countdown: one line. 6.15: first the
-- mission's enemies ("🧟 7/20", delivered: "🧟 3 LEFT").
local function missionLine(mission: any, short: boolean?): string
	local parts = {}
	local enemies = mission.enemies
	if type(enemies) == "table" and type(enemies.total) == "number" and enemies.total > 0 then
		table.insert(parts, if mission.clearing == true then `🧟 {tonumber(enemies.left) or 0} LEFT` else `🧟 {math.min(tonumber(enemies.killed) or 0, enemies.total)}/{enemies.total}`)
	end
	if type(mission.defendLeft) == "number" and mission.defendLeft > 0 then
		table.insert(parts, `🛡 HOLD OUT {Ui.clock(mission.defendLeft)}`)
	end
	for _, id in (if type(mission.twists) == "table" then mission.twists else {}) do
		local info = Config.Missions.Twists[id]
		if info then
			table.insert(parts, if short then info.icon else `{info.icon} {info.name}`)
		end
	end
	if mission.coop == true then
		table.insert(parts, "👥 CO-OP")
	end
	return if #parts > 0 then table.concat(parts, "  ·  ") else "no twists"
end

-- What a crew-board entry wants: "MISSION 3/10 · Name" (CO-OP), or any mission.
local function wantText(item: any): string
	if type(item.missionName) == "string" then
		local campaign = if type(item.campaign) == "string" then Missions.findCampaign(item.campaign) else nil
		local number = if type(item.number) == "number" then ` {item.number}/10` else ""
		return `{if campaign then campaign.icon .. " " else ""}MISSION{number} · {item.missionName}{if item.coop then "  ·  CO-OP" else ""}`
	end
	return "any mission or job"
end

local function ago(since: any): string
	local seconds = if type(since) == "number" then math.max(0, now() - since) else 0
	return if seconds < 60 then "just now" else `{math.floor(seconds / 60)} min ago`
end

-- My entry on the crew board, or nil.
local function myBoardEntry(): any
	for _, item in board do
		if type(item) == "table" and item.userId == player.UserId then
			return item
		end
	end
	return nil
end

local function lookFor(mission: string?)
	if boardRemote then
		boardRemote:FireServer(mission)
	end
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

-- The same rule as the Hud's windows (Ui.scaleFor), so the window matches them on every screen.
local function updateScale()
	if scale then
		scale.Scale = Ui.screenScale()
	end
end

-- ── The window ─────────────────────────────────────────────────────────────

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

-- A section head (5.8: the phone's "■ ACTIVE ORDER"): the small red marker, the caps and a thin line under them.
local function heading(text: string)
	local frame = Ui.make("Frame", { Size = UDim2.new(1, -10, 0, 30), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, body)
	Ui.make("Frame", {
		Name = "Marker",
		Size = UDim2.fromOffset(7, 7),
		Position = UDim2.new(0, 2, 0.5, 2),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = K.red,
		BorderSizePixel = 0,
	}, frame)
	Ui.caps(frame, text, UDim2.new(1, -18, 1, -4), { Position = UDim2.fromOffset(18, 4), TextSize = 13, TextColor3 = C.dim })
	Ui.make("Frame", { Name = "Rule", Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, frame)
end

local function note(text: string, color: Color3?)
	Ui.label(body, text, UDim2.new(1, -10, 0, 0), {
		LayoutOrder = nextOrder(),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = color or C.dim,
	})
end

-- 5.8: a slim row like the phone's (square, a hairline). A highlighted row is raised with a narrow rule on its left
-- and a brighter hairline (red for the GPS / crew highlight, else the caller's colour, e.g. the leader's amber).
local function row(height: number, highlight: Color3?): any
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -10, 0, height),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
		LayoutOrder = nextOrder(),
	}, body)
	Ui.stroke(frame, K.line, 1).Transparency = Ui.HAIRLINE
	if highlight then
		Ui.selectRow(frame, true)
		local rule = frame:FindFirstChild("Rule")
		if rule and rule:IsA("Frame") and highlight ~= GPS then
			rule.BackgroundColor3 = highlight
		end
	end
	return frame
end

-- The name (big) and a line under it on the left of a row; returns the line (for live updates).
local function rowText(frame: any, name: string, sub: string, nameColor: Color3?, buttons: number): any
	local width = -24 - buttons * 120
	Ui.label(frame, name, UDim2.new(1, width, 0, 24), {
		Position = UDim2.fromOffset(14, 6),
		TextSize = 18,
		Font = Theme.DisplayFont,
		TextColor3 = nameColor or C.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return Ui.label(frame, sub, UDim2.new(1, width, 0, 18), {
		Position = UDim2.fromOffset(14, 31),
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = C.dim,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end

-- A button on the right of a row (slot 1 = the rightmost; 112 × 36, square like the phone's); `color` says what it
-- means (Theme.Contract.red: the primary action, Theme.Colors.red: danger, green: the main one); a disabled one is
-- grey and does nothing.
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
			note(`No job yet: {ownerName} picks a mission (U), a job at the board (J) or an employer's, and you work on it together.`, C.text)
		elseif myRole == "owner" then
			note("Pick a mission (U, the CO-OP ones are made for a crew) or take a job (J, or an employer's WORK HERE board): your crew works on it with you. The crew stays together after the job.", C.text)
		end
		return
	end
	local mission = missionOf(job)
	local frame = row(if mission then 106 else 84, GPS)
	Ui.label(frame, if mission then missionTitle(mission) else `{stars(job.stars)}{tostring(job.name or "Job")}`, UDim2.new(1, -110, 0, 22), {
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
		Font = Theme.MonoFont,
	})
	Ui.label(frame, tostring(job.step or ""), UDim2.new(1, -28, 0, 24), {
		Position = UDim2.fromOffset(14, 30),
		TextSize = 19,
		Font = Theme.DisplayFont,
		TextColor3 = VIOLET,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local info = Ui.label(frame, "", UDim2.new(1, -28, 0, 18), {
		Position = UDim2.fromOffset(14, 58),
		TextSize = 14,
		Font = Theme.Font,
		TextColor3 = C.dim,
	})
	local twistLabel = if mission
		then Ui.label(frame, "", UDim2.new(1, -28, 0, 18), {
			Position = UDim2.fromOffset(14, 80),
			TextSize = 14,
			Font = Enum.Font.GothamBold,
			TextColor3 = C.yellow,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		else nil
	table.insert(live, function()
		local left = if type(job.endsAt) == "number" then job.endsAt - now() else nil
		timer.Text = if left then Ui.clock(left) else ""
		timer.TextColor3 = if left and left < 15 then C.red else C.text
		local position = if typeof(job.position) == "Vector3" then job.position else nil
		info.Text = if myRole == "member" then `{meters(distanceTo(position))} to the stop  ·  the GPS route leads there`
			else `{meters(distanceTo(position))} to the stop`
		-- The newest state's mission (the defend countdown moves without a new render).
		local fresh = missionOf(status())
		if twistLabel and fresh then
			twistLabel.Text = missionLine(fresh)
		end
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
		Font = Theme.HeadingFont,
		TextColor3 = C.dim,
	})
	-- The bar: every part as wide as its share of everything paid out (5.8: square; the leader's part red, the members'
	-- two greys in turn, light names).
	local bar = Ui.make("Frame", {
		Size = UDim2.new(1, -28, 0, 20),
		Position = UDim2.fromOffset(14, 30),
		BackgroundColor3 = K.recessed,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, frame)
	local total = ownerShare + memberShare * count
	local x = 0
	local leaderIsMe = crew ~= nil and type(crew.owner) == "table" and crew.owner.userId == player.UserId
	local parts = { { share = ownerShare, color = K.red, text = if preview or leaderIsMe then "LEADER (YOU)" else "LEADER" } }
	for index = 1, count do
		table.insert(parts, { share = memberShare, color = if index % 2 == 1 then K.track else K.track:Lerp(K.line, 0.3), text = names[index] or (if index > #names and not preview then "RIDER" else "MEMBER") })
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
			TextSize = 12,
			Font = Theme.HeadingFont,
			TextColor3 = C.text,
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
		Font = Theme.HeadingFont,
		TextColor3 = C.money,
	})
	local bonus = math.floor(Config.Jobs.CrewDriverBonus * 100 + 0.5)
	Ui.label(frame, `The leader +{bonus} % per member, every member a share on top: nobody loses money.`, UDim2.new(1, -28, 0, 16), {
		Position = UDim2.fromOffset(14, 78),
		TextSize = 13,
		Font = Theme.Font,
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
			rowButton(frame, "KICK", C.red, true, 1, function()
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
			rowButton(frame, "ACCEPT", K.red, not blocked, 2, function()
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

-- The INVITE button of another player (the players list and the crew board): its text and whether it works.
local function inviteState(id: number, myRole: string?): (string, boolean)
	if crewIds()[id] then
		return "IN CREW", false
	elseif myRole == "member" then
		return "LEADER ONLY", false
	end
	for _, item in listOf("pending") do
		if item.userId == id then
			return "INVITED", false
		end
	end
	for _, item in listOf("invites") do
		if item.userId == id then
			return "ASKED YOU", false
		end
	end
	local max = if crew and type(crew.maxMembers) == "number" then crew.maxMembers else Config.Crew.MaxMembers
	if #listOf("members") + #listOf("pending") >= max then
		return "CREW FULL", false
	end
	return "INVITE", true
end

-- The crew board: my own toggle, then everybody looking for a crew (INVITE them).
local function renderBoard(myRole: string?)
	local others = {}
	for _, item in board do
		if type(item) == "table" and type(item.userId) == "number" and item.userId ~= player.UserId then
			table.insert(others, item)
		end
	end
	heading(`🔎 LOOKING FOR CREW{if #others > 0 then `  ·  {#others}` else ""}`)
	-- Me.
	local mine = myBoardEntry()
	if myRole == nil then
		local frame = row(56, if mine then C.yellow else nil)
		if mine then
			local sub = rowText(frame, "You are on the crew board", "", C.yellow, 1)
			local function refresh()
				sub.Text = `for {wantText(mine)}  ·  {ago(mine.since)}`
			end
			refresh()
			table.insert(live, refresh)
			rowButton(frame, "STOP", C.red, true, 1, function()
				lookFor(nil)
			end)
		else
			rowText(frame, "Looking for a crew?", "Go on the board: players see you and can invite you.", C.text, 1)
			rowButton(frame, "LOOK", C.green, not ownJob, 1, function()
				lookFor("any")
			end)
		end
	end
	if #others == 0 then
		note(if myRole == "member" then "Nobody is looking for a crew right now." else "Nobody is looking for a crew right now. FIND CREW on a co-op mission (U) puts you on the board.")
		return
	end
	for _, item in others do
		local id: number = item.userId
		local frame = row(56, if item.coop then GPS else nil)
		local level = if type(item.level) == "number" then item.level else nil
		local sub = rowText(frame, `🔎 {tostring(item.name)}`, "", C.text, 1)
		local busy = item.busy == true
		local function refresh()
			sub.Text = `{levelText(level)}  ·  {wantText(item)}  ·  {if busy then "on a job" else ago(item.since)}`
		end
		refresh()
		table.insert(live, refresh)
		local text, enabled = inviteState(id, myRole)
		if enabled and busy then
			text, enabled = "ON A JOB", false
		end
		rowButton(frame, text, C.green, enabled, 1, function()
			invite(id)
		end)
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
	local onBoard: { [number]: boolean } = {}
	for _, item in board do
		if type(item) == "table" and type(item.userId) == "number" then
			onBoard[item.userId] = true
		end
	end
	for _, item in others do
		local other: Player = item.player
		local id = other.UserId
		local frame = row(56)
		local sub = rowText(frame, other.DisplayName, "", C.text, 1)
		local looking = if onBoard[id] then "  ·  🔎 looking" else ""
		local function refresh()
			local distance = distanceToPlayer(other)
			local near = distance ~= nil and distance <= Config.Crew.InviteRange
			sub.Text = `{levelText(levelOf(other))}  ·  {meters(distance)}{if near then "  ·  nearby" else ""}{looking}`
			sub.TextColor3 = if near then C.green else C.dim
		end
		refresh()
		table.insert(live, refresh)
		local text, enabled = inviteState(id, myRole)
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
		note("Invite players into your job: they carry, shoot and ride along, and each gets a share of the pay. You can invite with or without a job, and the crew stays together for the next one.", C.text)
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
	renderBoard(myRole)
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
		stripStep.Text = `Waiting for {ownerName} to pick a mission or a job`
		stripInfo.Text = "K: the crew panel  ·  U: the missions"
		stripMission.Visible = false
		return
	end
	local mission = missionOf(job)
	stripTitle.Text = string.upper(if mission then `👥  CREW  ·  {missionTitle(mission)}` else `👥  CREW  ·  {stars(job.stars)}{tostring(job.name or "")}`)
	stripMission.Visible = mission ~= nil
	if mission then
		stripMission.Text = string.upper(missionLine(mission))
	end
	local left = if type(job.endsAt) == "number" then job.endsAt - now() else nil
	stripTimer.Text = if left then Ui.clock(left) else ""
	stripTimer.TextColor3 = if left and left < 15 then C.red else C.text
	stripStep.Text = tostring(job.step or "")
	local position = if typeof(job.position) == "Vector3" then job.position else nil
	local owner = Players:GetPlayerByUserId(crew.owner.userId)
	local ownerDistance = if owner then distanceToPlayer(owner) else nil
	stripInfo.Text = `Stop {meters(distanceTo(position))}  ·  {ownerName} {meters(ownerDistance)}  ·  follow the GPS`
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
			-- Over the world: a compact charcoal label behind the light name.
			local pill = Ui.label(billboard, "", UDim2.fromScale(0, 1), {
				Name = "Text",
				AutomaticSize = Enum.AutomaticSize.X,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				BackgroundTransparency = 0.2,
				BackgroundColor3 = P.pill,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = 14,
				Font = Theme.HeadingFont,
				TextColor3 = VIOLET,
				TextWrapped = false,
			})
			Ui.corner(pill)
			Ui.stroke(pill, P.line, 1).Transparency = 0
			Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, pill)
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

-- How many invitations wait: a red dot with the count on the Hud's CREW button.
local function updateBadge()
	Hud.setBadge("crew", #listOf("invites"))
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
		local mission = missionOf(job)
		add(if mission then mission.id else "")
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
	-- The state carries the crew board too (the CrewBoard remote sends it on its own on every change).
	if crew and type(crew.lfg) == "table" then
		board = crew.lfg
	end
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

local function build()
	gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryCrew",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2,
		Enabled = hudOn(),
	}, playerGui)

	-- The window.
	local content
	window, content, chrome = Ui.window(gui, "Crew", "Work together · share the pay", "👥", UDim2.fromOffset(640, 620), { glyph = "crew" })
	scale = Ui.make("UIScale", {}, window)
	window.Visible = false
	window.ZIndex = 5
	chrome.onClose = function()
		setOpen(false)
	end
	chrome.context.Text = "K · CREW · crews stay together after the job"
	body = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -28, 1, -20),
		Position = UDim2.fromOffset(16, 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = K.line,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, content)
	Ui.list(body, true, 8)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10) }, body)

	-- A member's view of the leader's job: the top stack's crew slot, where your own job panel would be (a member
	-- has none). As wide as the job panel; the slot is scaled with the stack.
	-- 3.2: the Hud's job panel style (an accent edge, small caps over a bold step); 3.8: a charcoal scrim (Ui.panel)
	-- with a thin white rule on its left, the text light.
	local slot = Hud.topSlot("crew")
	strip = Ui.panel(slot, UDim2.new(1, 0, 0, 0), UDim2.new(), nil)
	strip.Name = "CrewStrip"
	strip.LayoutOrder = 1
	strip.AutomaticSize = Enum.AutomaticSize.Y
	strip.Visible = false
	strip.BackgroundTransparency = K.scrim
	Ui.edge(strip, K.text, 0)
	local stripBody = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, strip)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 11) }, stripBody)
	Ui.list(stripBody, true, 4)
	local header = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1 }, stripBody)
	stripTitle = Ui.caps(header, "", UDim2.new(1, -86, 1, 0), {
		TextSize = 12,
		TextColor3 = VIOLET,
	})
	stripTimer = Ui.label(header, "", UDim2.new(0, 86, 1, 0), {
		Position = UDim2.new(1, -86, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 20,
		TextWrapped = false,
		Font = Theme.MonoFont,
	})
	stripStep = Ui.label(stripBody, "", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		TextSize = 19,
		Font = Theme.DisplayFont,
	})
	stripInfo = Ui.label(stripBody, "", UDim2.new(1, 0, 0, 16), { LayoutOrder = 3, TextColor3 = C.dim, TextSize = 13, Font = Theme.HeadingFont, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	stripMission = Ui.caps(stripBody, "", UDim2.new(1, 0, 0, 16), {
		LayoutOrder = 4,
		Visible = false,
		TextColor3 = C.yellow,
		TextSize = 12,
	})

	-- The invitation card: in the crew slot too (shown only without a job of your own and without a crew).
	-- 3.8: the same card with a red rule (it waits for your answer); ACCEPT the one main action, DECLINE plain text.
	card = Ui.panel(slot, UDim2.new(1, 0, 0, 0), UDim2.new(), nil)
	card.Name = "CrewInvitation"
	card.LayoutOrder = 2
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Visible = false
	card.BackgroundTransparency = 0.15
	Ui.edge(card, K.red, 0)
	local cardBody = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, card)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12) }, cardBody)
	Ui.list(cardBody, true, 6)
	local cardHeader = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1 }, cardBody)
	cardTitle = Ui.caps(cardHeader, "", UDim2.new(1, -86, 1, 0), { TextSize = 12, TextColor3 = VIOLET })
	cardTimer = Ui.label(cardHeader, "", UDim2.new(0, 86, 1, 0), {
		Position = UDim2.new(1, -86, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 17,
		TextWrapped = false,
		Font = Theme.MonoFont,
	})
	cardText = Ui.label(cardBody, "", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		TextSize = 18,
		Font = Theme.DisplayFont,
	})
	local buttons = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 3 }, cardBody)
	Ui.list(buttons, false, 8)
	local accept = Ui.button(buttons, "✔  ACCEPT", UDim2.fromOffset(130, 36), K.red, function()
		if cardFrom then
			answer(cardFrom, true)
		end
	end)
	accept.LayoutOrder = 1
	accept.TextSize = 15
	local decline = Ui.ghostButton(buttons, "DECLINE", UDim2.fromOffset(110, 36), C.red, function()
		if cardFrom then
			answer(cardFrom, false)
		end
	end)
	decline.LayoutOrder = 2
	decline.TextSize = 15
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	Ui.caps(buttons, if touch then "or CREW for the panel" else "K: the crew panel · Alt frees the mouse", UDim2.new(1, -270, 1, 0), {
		LayoutOrder = 3,
		TextSize = 12,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
	})

	-- The beam over the leader's next stop (a member's guide in the world, like the job's own beam). 4.4.1: thin and
	-- white, like the GPS route on the maps (client/MapView.luau) and the Hud's GPS guide.
	local part = Instance.new("Part")
	part.Name = "CrewBeam"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Shape = Enum.PartType.Cylinder
	part.Color = K.text
	part.Transparency = 0.75
	part.Size = Vector3.new(240, 1.2, 1.2)
	part.CFrame = HIDDEN
	part.Parent = workspace
	beam = part
end

-- ── API ────────────────────────────────────────────────────────────────────

function CrewPanel.start()
	build()
	-- The Hud's CREW button opens the window (client/Main.client.luau sets the same; this keeps it working alone).
	if Hud.onCrew == nil then
		Hud.onCrew = CrewPanel.toggle
	end
	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	inviteRemote = Net.get("CrewInvite")
	answerRemote = Net.get("CrewAnswer")
	boardRemote = Net.get("CrewBoard")
	-- The crew board changed: the open window shows it.
	Net.get("CrewBoard").OnClientEvent:Connect(function(list: any)
		board = if type(list) == "table" then list else {}
		if window.Visible then
			render()
		end
	end)
	local stateRemote = Net.get("CrewState")
	stateRemote.OnClientEvent:Connect(apply)
	-- An invitation: the card shows it with the next state (it comes with the invitation); the CREW button flashes.
	Net.get("CrewInvite").OnClientEvent:Connect(function()
		Hud.flashButton("crew", C.yellow, 1.5)
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

-- Opens the window (MISSIONS' FIND CREW: MissionsUi.onFindCrew, wired in Main).
function CrewPanel.open()
	if window and not window.Visible then
		setOpen(true)
	end
end

-- Puts me on the crew board for a mission ("any" = anything) or takes me off (nil): the server checks it.
function CrewPanel.lookFor(mission: string?)
	lookFor(mission)
end

-- Opens the window, or closes it when it is open (K, the Hud's CREW button through Hud.onCrew).
function CrewPanel.toggle()
	if window then
		setOpen(not window.Visible)
	end
end

function CrewPanel.isOpen(): boolean
	return window ~= nil and window.Visible == true
end

return CrewPanel
