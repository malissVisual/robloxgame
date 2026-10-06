--!strict
-- 3.7: the first-day tutorial on screen (server/Tutorial.luau decides, the words are in shared/TutorialSteps.luau).
--
--   * Marge's dialog: a charcoal panel at the lower centre (over the hint and the item tags), the speaker in small caps
--     with a short red rule under it, her line in white, a thin line and the actions: CONTINUE on every page but the
--     last, which says its own action (LET'S GO, ANOTHER JOB, GOT IT); a quiet second action (SKIP TUTORIAL, LATER).
--     Space or Enter (or the gamepad's A) continues, so do a click or a tap on the panel. While it is open those keys
--     do nothing else (no jump) and the mouse is free (CameraRig.mouseNeeded). 4.4.1: the keys go through
--     client/DialogKeys.luau (over the other dialogs: her panel is on top) and work for her radio too (retry, done,
--     say: it comes on its own, mid-jump or mid-drive, so a key waits a little longer before it turns her page).
--   * The hint: one compact line under the objective, in the HUD's top stack (Hud.topSlot("tutorial"), placed right
--     after the ticket), with "FIRST DAY" and SKIP (it asks first). During the job it follows the Job payload
--     (TutorialSteps.jobStep): the same state the ticket shows, never ahead of it.
--   * A marker over Marge (TALK TO MARGE ▼) while she has something for you (welcome, retry).
-- 4.2, a phone: the dialog sits in the middle at a readable size (at least 0.8, as wide as the screen allows), its
-- actions and the hint's SKIP a finger tall (ACTION_H); a tap anywhere on it still continues.
-- Everything lives in ScreenGuis that survive a respawn. The style is the approved "contract" direction
-- (design/ui-contract on codex/ui-contract): white text over a subtle charcoal scrim, fine lines, small red accents,
-- flat square shapes, the Theme fonts and colours (Theme.Contract).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local TutorialSteps = require(Shared.TutorialSteps)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Hud = require(script.Parent.Hud)
local CameraRig = require(script.Parent.CameraRig)
local DialogKeys = require(script.Parent.DialogKeys)

local TutorialUi = {}

-- The contract tokens (design/ui-contract/README.md), from Theme since 3.8.
local CONTRACT = Theme.Contract
local DIALOG_W = 540
local TOUCH = Ui.touchLayout() -- 4.2: a phone or a tablet without a keyboard
local ACTION_H = if TOUCH then 56 else 44 -- the actions' height (unscaled): 44 px or more for a finger at 0.8
local KEYS_ID = "tutorial" -- her dialog's entry in client/DialogKeys.luau
local RADIO_GUARD = 0.8 -- seconds before a key turns a radio page (it comes on its own: maybe mid-jump)

local player = Players.LocalPlayer
local remote: RemoteEvent
local phase: string? = nil -- the server's phase while the tutorial runs (nil: none, or over)
local job: any = nil -- the latest Job payload
local npc: Model? = nil -- Marge

type Shown = { kind: string, dialog: TutorialSteps.Dialog, page: number, openedAt: number }
local shown: Shown? = nil

local view: any = {} -- the instances (one table: few locals)

-- ── Building ───────────────────────────────────────────────────────────────

-- A plain text action: caps, a thin red line under it on hover; at least 44 px tall for a finger.
local function textAction(parent: Instance, text: string, color: Color3, order: number, onClick: () -> ()): any
	local button = Ui.make("TextButton", {
		Size = UDim2.fromOffset(0, ACTION_H),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = text,
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = color,
		LayoutOrder = order,
	}, parent)
	local underline = Ui.make("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0.5, 10),
		BackgroundColor3 = CONTRACT.red,
		BorderSizePixel = 0,
		Visible = false,
	}, button)
	button.MouseEnter:Connect(function()
		underline.Visible = true
		button.TextColor3 = CONTRACT.text
	end)
	button.MouseLeave:Connect(function()
		underline.Visible = false
		button.TextColor3 = color
	end)
	button.Activated:Connect(function()
		local sound = Ui.onClick
		if sound then
			sound()
		end
		onClick()
	end)
	return button
end

local function buildDialog(advance: () -> (), second: () -> ())
	local gui = Ui.make("ScreenGui", {
		Name = "TutorialDialog",
		ResetOnSpawn = false,
		DisplayOrder = 6, -- over the HUD
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	-- The whole panel is a button: a click or a tap anywhere on it continues.
	local panel = Ui.make("TextButton", {
		Name = "Dialog",
		Size = UDim2.fromOffset(DIALOG_W, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = if TOUCH then Vector2.new(0.5, 0.5) else Vector2.new(0.5, 1),
		Position = if TOUCH then UDim2.fromScale(0.5, 0.55) else UDim2.new(0.5, 0, 1, -150),
		BackgroundColor3 = CONTRACT.charcoal,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, gui)
	view.scale = Ui.make("UIScale", {}, panel)
	local stroke = Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = CONTRACT.line, Thickness = 1, Transparency = 0.6 }, panel)
	stroke.Name = "Line"
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20), PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 4) }, panel)
	Ui.list(panel, true, 8)
	panel.Activated:Connect(advance)

	view.speaker = Ui.label(panel, "", UDim2.new(1, 0, 0, 16), {
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = CONTRACT.secondary,
		TextWrapped = false,
		LayoutOrder = 1,
	})
	Ui.make("Frame", { Name = "Rule", Size = UDim2.fromOffset(28, 2), BackgroundColor3 = CONTRACT.red, BorderSizePixel = 0, LayoutOrder = 2 }, panel)
	view.line = Ui.label(panel, "", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Font,
		TextSize = 18,
		LineHeight = 1.1,
		TextColor3 = CONTRACT.text,
		LayoutOrder = 3,
	})
	Ui.make("Frame", { Name = "Sep", Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = CONTRACT.line, BackgroundTransparency = 0.6, BorderSizePixel = 0, LayoutOrder = 4 }, panel)

	local footer = Ui.make("Frame", { Name = "Footer", Size = UDim2.new(1, 0, 0, ACTION_H), BackgroundTransparency = 1, LayoutOrder = 5 }, panel)
	local left = Ui.make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundTransparency = 1 }, footer)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, left)
	view.pageLabel = Ui.label(left, "", UDim2.fromOffset(0, ACTION_H), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.MonoFont,
		TextSize = 12,
		TextColor3 = CONTRACT.secondary,
		TextWrapped = false,
		LayoutOrder = 1,
	})
	view.second = textAction(left, "", CONTRACT.secondary, 2, second)
	local right = Ui.make("Frame", { Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(0.5, 0), BackgroundTransparency = 1 }, footer)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, right)
	view.primary = textAction(right, "", CONTRACT.text, 1, advance)
	view.keyHint = Ui.label(right, if TOUCH then "" else DialogKeys.hint(), UDim2.fromOffset(0, ACTION_H), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.MonoFont,
		TextSize = 11,
		TextColor3 = CONTRACT.secondary,
		TextWrapped = false,
		LayoutOrder = 2,
	})
	view.dialogGui = gui
end

local function buildHint(onSkip: () -> ())
	local slot = Hud.topSlot("tutorial")
	slot.LayoutOrder = 2 -- right under the objective ticket (Hud's slot 1; the crew strip shows only without a job)
	local strip = Ui.make("Frame", {
		Name = "TutorialHint",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = CONTRACT.charcoal,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Visible = false,
	}, slot)
	Ui.make("Frame", { Name = "Accent", Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = CONTRACT.red, BorderSizePixel = 0 }, strip)
	local body = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, strip)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }, body)
	Ui.list(body, true, 2)
	local top = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 1 }, body)
	Ui.label(top, string.upper(`First day · {Config.Tutorial.NpcName}`), UDim2.new(1, -60, 1, 0), {
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = CONTRACT.secondary,
		TextWrapped = false,
	})
	local skip = textAction(top, "SKIP", CONTRACT.secondary, 1, onSkip)
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, 0, 0.5, 0)
	skip.Size = UDim2.fromOffset(0, if TOUCH then 44 else 28) -- 4.2: a finger's height on touch (it reaches over the line)
	skip.ZIndex = 2
	view.hintText = Ui.label(body, "", UDim2.new(1, 0, 0, 0), {
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Font,
		TextSize = 15,
		TextColor3 = CONTRACT.text,
		LayoutOrder = 2,
	})
	view.hint = strip
end

local function buildMarker()
	local marker = Ui.make("BillboardGui", {
		Name = "TutorialMarker",
		Size = UDim2.fromOffset(150, 44),
		StudsOffsetWorldSpace = Vector3.new(0, 5.2, 0), -- over her name tag
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	Ui.list(marker, true, 0, Enum.HorizontalAlignment.Center)
	Ui.label(marker, "", UDim2.new(1, 0, 0, 22), {
		Name = "Text",
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextColor3 = CONTRACT.text,
		TextStrokeColor3 = CONTRACT.charcoal,
		TextStrokeTransparency = 0.3,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		LayoutOrder = 1,
	})
	Ui.label(marker, "▼", UDim2.new(1, 0, 0, 20), {
		Font = Theme.HeadingFont,
		TextSize = 18,
		TextColor3 = CONTRACT.red,
		TextStrokeColor3 = CONTRACT.charcoal,
		TextStrokeTransparency = 0.5,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
	})
	view.marker = marker
end

-- ── Showing ────────────────────────────────────────────────────────────────

-- 4.5.1: the hint on screen (its words, the phase and stop they belong to, since when) and a pending later refresh.
-- The job's step can go back and forth between two server ticks (the 80-stud approach edge: "drive" / "carry", the
-- back open / shut): within one stop a new hint waits until the last one has been up HINT_HOLD seconds, so the card
-- never flips its words (and its height) several times a second.
local HINT_HOLD = 1
local hintShown = { text = "", key = "", at = -math.huge, queued = false }

-- The hint line and the marker for the phase and the job right now.
local function refresh()
	local text = ""
	if phase == "job" or (phase ~= nil and job ~= nil) then
		text = TutorialSteps.hint(TutorialSteps.jobStep(job), job)
	elseif phase ~= nil then
		text = TutorialSteps.hint(phase, nil)
	end
	if TOUCH then
		text = TutorialSteps.forTouch(text) -- 4.2: no keys on a touch screen
	end
	if view.hint then
		local key = if job then `{phase}|{job.stopIndex}|{job.stage}` else tostring(phase)
		if text ~= hintShown.text then
			local wait = hintShown.at + HINT_HOLD - os.clock()
			if key == hintShown.key and wait > 0 then
				if not hintShown.queued then
					hintShown.queued = true
					task.delay(wait, function()
						hintShown.queued = false
						refresh()
					end)
				end
			else
				hintShown.text, hintShown.at = text, os.clock()
				view.hintText.Text = text
				view.hint.Visible = text ~= ""
			end
		end
		hintShown.key = key
	end
	local marker = view.marker
	if marker then
		local head = npc and (npc:FindFirstChild("Head") or npc.PrimaryPart)
		local wanted = head ~= nil and job == nil and (phase == "welcome" or phase == "retry")
		marker.Adornee = if wanted then head else nil
		marker.Enabled = wanted
		local label = marker:FindFirstChild("Text")
		if label and label:IsA("TextLabel") then
			label.Text = string.upper(`Talk to {Config.Tutorial.NpcName}`)
		end
	end
end

-- The mouse is free while a dialog is open (CameraRig asks Main's mouseNeeded; ours is put in front of it).
local wrapped: (() -> boolean)? = nil
local function freeMouse()
	if CameraRig.mouseNeeded == wrapped then
		return
	end
	local previous = CameraRig.mouseNeeded
	local function needed(): boolean
		return TutorialUi.isOpen() or previous()
	end
	wrapped = needed
	CameraRig.mouseNeeded = needed
end

local function render()
	local current = shown
	if not current then
		return
	end
	local dialog = current.dialog
	local count = #dialog.pages
	local last = current.page >= count
	view.speaker.Text = dialog.speaker
	local line = dialog.pages[current.page] or ""
	view.line.Text = if TOUCH then TutorialSteps.forTouch(line) else line
	view.pageLabel.Text = if count > 1 then `{current.page} / {count}` else ""
	view.primary.Text = if last then dialog.primary else "CONTINUE"
	local second = dialog.secondary
	view.second.Text = second or ""
	view.second.Visible = second ~= nil
	local scale = Ui.screenScale()
	if TOUCH then
		-- 4.2: readable on a phone (the HUD's 0.55 would make 10 px text), never wider than the screen.
		scale = math.min(math.max(scale, 0.8), (Ui.screenSize().X - 32) / DIALOG_W)
	end
	view.scale.Scale = scale
end

local function close()
	shown = nil
	if view.dialogGui then
		view.dialogGui.Enabled = false
	end
	DialogKeys.close(KEYS_ID)
end

local function show(kind: string, dialog: TutorialSteps.Dialog?)
	if not dialog or not view.dialogGui then
		return
	end
	shown = { kind = kind, dialog = dialog, page = 1, openedAt = os.clock() }
	render()
	view.dialogGui.Enabled = true
	freeMouse()
	-- Space / Enter / A turn her pages (4.4.1: the radio's too; it comes on its own, maybe mid-jump or mid-drive, so
	-- a key waits a little longer there; a jump pressed just as she starts talking does not skip her first page).
	local radio = kind == "retry" or kind == "done" or kind == "say"
	DialogKeys.open(KEYS_ID, TutorialUi.advance, { guard = if radio then RADIO_GUARD else 0.3, layer = 2 })
end

-- What the last page's actions do.
local function finishDialog(kind: string, primary: boolean)
	if kind == "welcome" then
		remote:FireServer(if primary then "go" else "skip")
	elseif kind == "skip" and primary then
		remote:FireServer("skip")
	elseif kind == "retry" and primary then
		remote:FireServer("go")
	elseif kind == "board" and primary then
		local open = (Hud :: any).onJobs -- (Main: DispatchUi.open)
		if type(open) == "function" then
			open()
		end
	end
end

function TutorialUi.isOpen(): boolean
	return shown ~= nil
end

-- The next page, or the dialog's own action on the last one.
function TutorialUi.advance()
	local current = shown
	if not current then
		return
	end
	if current.page < #current.dialog.pages then
		current.page += 1
		render()
		return
	end
	close()
	finishDialog(current.kind, true)
end

local function secondary()
	local current = shown
	if not current then
		return
	end
	close()
	finishDialog(current.kind, false)
end

local function onTutorial(newPhase: any, data: any)
	local info: { [string]: any } = if type(data) == "table" then data else {}
	if typeof(info.npc) == "Instance" and info.npc:IsA("Model") then
		npc = info.npc
	end
	if type(newPhase) ~= "string" then
		-- Over (skipped): her tutorial dialogs go, a line she said stays.
		phase = nil
		local current = shown
		if current and current.kind ~= "say" and current.kind ~= "done" then
			close()
		end
		refresh()
		return
	end
	if newPhase == "say" then
		show("say", TutorialSteps.dialog("say", info))
		return
	end
	if newPhase == "phone" or newPhase == "message" then
		-- 5.0: Marge gave the phone (client/Phone.luau shows its NEW PHONE moment), or texted it (server/VanQuest.luau:
		-- a message for the phone's MESSAGES); neither is a phase of hers
		return
	end
	phase = if newPhase == "done" then nil else newPhase
	refresh()
	local dialog = TutorialSteps.dialog(newPhase, info)
	if dialog then
		show(newPhase, dialog)
	elseif shown and shown.kind ~= "say" and shown.kind ~= "done" and newPhase == "job" then
		close() -- (a job taken from the board while her welcome was still up)
	end
end

function TutorialUi.start()
	remote = Net.get("Tutorial")
	buildDialog(TutorialUi.advance, secondary)
	buildHint(function()
		show("skip", TutorialSteps.dialog("skip"))
	end)
	buildMarker()
	remote.OnClientEvent:Connect(onTutorial)
	-- (Main connects the HUD to "Job" right after the modules start; no job is sent before PLAY, so nothing queued is
	-- taken from it.)
	Net.get("Job").OnClientEvent:Connect(function(payload)
		job = if type(payload) == "table" then payload else nil
		if phase then
			refresh()
		end
	end)
	-- Marge may have been built before this client joined (her model comes with the welcome too).
	task.defer(function()
		local folder = workspace:FindFirstChild("Npcs")
		if not npc and folder then
			for _, child in folder:GetChildren() do
				if child:IsA("Model") and child:GetAttribute("Dispatcher") == true then
					npc = child
				end
			end
		end
	end)
end

return TutorialUi
