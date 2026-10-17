--!strict
-- 8.6 (the owner: "Somewhere I'd like to see an indicator of what Danny is doing right now"; the status line under the
-- move's panel went unnoticed): what Danny does, in a small bubble over his head for his move's crew only (a
-- BillboardGui this client makes in its PlayerGui, adorned to his head: nobody else sees it). Its words are the
-- server's (your player attribute MoveHelperBubble: shared/MoveHelperBrain.luau's bubble, made from the same action as
-- the status line's MoveHelperDoing, so the two never disagree: "📦 Carrying: Sofa → van", "⏳ Waiting at: Piano (needs
-- you)"; MoveHelperAlert: the movers' orange, he needs you or is in trouble; 10.1 "🆘 Down! Hold E to revive" in a
-- run), and "list: 3" beside them while his list holds pieces (MoveHelperQueue). His body by your MoveHelperId (his
-- body's MoveHelper), as his card finds it. (10.1: any helper of the crew, Bruno's, Lucy's …: no "for hire" any more.)
--   * Where: over his name tag ("Danny / ZDC Moving", server/Npcs.luau's on his head), or over his speech while he
--     talks (it takes the tag's place there): its bottom Config.MoveHelper.Bubble.Gap px over theirs at every distance
--     (all three are a fixed size on the screen: DannyBubble.lift).
--   * Readable but small: Bubble.Text px words in the HUD's charcoal pill (Theme), Bubble.Wide px at most (cut with
--     "…"); from Bubble.Near studs (the camera's) it fades out to nothing at Bubble.Far, its MaxDistance
--     (DannyBubble.fade); AlwaysOnTop only within Bubble.Top studs (near, a piece or the van never hides it; farther,
--     walls do: never through another house's).
--   * Throttled: one look every Bubble.Tick s (his body, the distance, the stack under it); the words drawn again only
--     when they change. Nothing per frame.
--   * 8.9 his whistle (art/audio/sfx5.ogg, client/SandboxSounds.luau event "danny_whistle"): the bubble turned orange
--     because he needs you (its icon: shared/MoveHelperBrain.luau Doing's alert action, one of
--     Config.Soundscape.Danny.WhistleFor: "needs", a piece of his list for two waiting for you), heard as its words are
--     drawn (shared/SoundPlan.luau whistleCue: not on the first look, not while it stays so), at most every WhistleGap s.
-- Presentation only.
--   DannyBubble.start()                          listens (nothing shows without Danny on your move)
--   DannyBubble.gui()                            the BillboardGui (the checks; nil before built)
--   DannyBubble.fade(distance) -> (number, boolean)   its transparency at that many studs (0 … 1) and AlwaysOnTop
--   DannyBubble.lift(under, tall) -> number      its SizeOffset.Y: `tall` px high, standing Gap px over `under` px (the
--                                                tag or the speech standing on his head's point)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Brain = require(Shared.MoveHelperBrain)
local SoundPlan = require(Shared.SoundPlan) -- 8.9 (his whistle)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local DannyBubble = {}

local B = Config.MoveHelper.Bubble
local K = Theme.Contract
local player = Players.LocalPlayer
local ORANGE = Color3.fromRGB(240, 132, 44) -- the movers' colour (client/MovingHud.luau's)
local CHIP_TEXT = 11 -- px: "list: 3"
local CHIP_PAD = 6 -- px round the chip's words, and between the words and the chip
local EDGE = 0.35 -- the pill's orange edge's own transparency

local started = false
local parts: { [string]: any } = {}
local found: Model? = nil -- his body (found by MoveHelperId)
local drawn = "" -- the words, the counter and the tone drawn now
local faded = -1 -- the transparency applied now
local alertWas: string? = nil -- 8.9 his alert's kind as last drawn ("": none; nil: not drawn yet)

function DannyBubble.fade(distance: number): (number, boolean)
	local alpha = math.clamp((distance - B.Near) / math.max(B.Far - B.Near, 1e-3), 0, 1)
	return alpha, distance <= B.Top
end

function DannyBubble.lift(under: number, tall: number): number
	return 0.5 + (math.max(under, 0) + B.Gap) / math.max(tall, 1)
end

function DannyBubble.gui(): BillboardGui?
	return parts.gui
end

-- His body by your MoveHelperId (nil: none on your move, or not streamed in).
local function body(): Model?
	local id = player:GetAttribute("MoveHelperId")
	if type(id) ~= "number" then
		found = nil
		return nil
	end
	local was = found
	if was and was.Parent and was:GetAttribute("MoveHelper") == id then
		return was
	end
	found = nil
	local folder = workspace:FindFirstChild("Npcs")
	for _, child in (if folder then folder:GetChildren() else {}) :: { Instance } do
		if child:IsA("Model") and child:GetAttribute("MoveHelper") == id then
			found = child
			return child
		end
	end
	return nil
end

local function widthOf(text: string, size: number, font: Enum.Font): number
	local ok, bounds = pcall(function(): Vector2
		return TextService:GetTextSize(text, size, font, Vector2.new(2000, 100))
	end)
	return math.ceil(if ok and bounds then bounds.X else #text * size * 0.55) + 2
end

local function build(): BillboardGui?
	local made = parts.gui
	if made and made.Parent then
		return made
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local gui = Ui.make("BillboardGui", {
		Name = "DannyBubble",
		ResetOnSpawn = false, -- (kept over a respawn)
		Enabled = false,
		AlwaysOnTop = false,
		LightInfluence = 0,
		Size = UDim2.fromOffset(160, B.Tall),
		SizeOffset = Vector2.new(0, DannyBubble.lift(46, B.Tall)),
		MaxDistance = B.Far,
	}, playerGui)
	local pill = Ui.make("Frame", {
		Name = "Pill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
	}, gui)
	Ui.corner(pill, math.floor(B.Tall / 2))
	parts.edge = Ui.make("UIStroke", { Name = "Edge", Color = ORANGE, Thickness = 1, Transparency = EDGE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
	parts.words = Ui.label(pill, "", UDim2.new(1, -2 * B.Pad, 1, 0), {
		Name = "Words",
		Position = UDim2.fromOffset(B.Pad, 0),
		Font = Theme.Font,
		TextSize = B.Text,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local chip = Ui.make("Frame", {
		Name = "List",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		Size = UDim2.fromOffset(40, B.Tall - 8),
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		Visible = false,
	}, pill)
	Ui.corner(chip, math.floor((B.Tall - 8) / 2))
	parts.count = Ui.label(chip, "", UDim2.fromScale(1, 1), {
		Name = "Count",
		Font = Theme.HeadingFont,
		TextSize = CHIP_TEXT,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
	})
	parts.gui, parts.pill, parts.chip = gui, pill, chip
	drawn, faded = "", -1
	return gui
end

-- 8.9 what his orange is for: the alert action whose icon the bubble starts with (MoveHelperBrain.Doing), "" none.
local function alertKind(text: string, alert: boolean): string
	if not alert then
		return ""
	end
	for action, w in Brain.Doing do
		if w.alert == true and string.sub(text, 1, #w.icon) == w.icon then
			return action
		end
	end
	return "alert"
end

-- 8.9 his whistle when the orange says he needs you (SoundPlan.whistleCue; client/SandboxSounds.luau plays it).
local function whistle(text: string, alert: boolean)
	local kind = alertKind(text, alert)
	local cue = SoundPlan.whistleCue(alertWas, kind)
	alertWas = kind
	if cue then
		pcall(function()
			(require(script.Parent.SandboxSounds) :: any).event(cue)
		end)
	end
end

-- Its words, the counter and the tone, sized to them (only when they changed).
local function paint()
	local gui = parts.gui
	if not gui then
		return
	end
	local raw = player:GetAttribute("MoveHelperBubble")
	local text = if type(raw) == "string" then raw else ""
	local count = if player:GetAttribute("MoveHelper") == "hired" then Brain.listChip(player:GetAttribute("MoveHelperQueue")) else nil
	local alert = player:GetAttribute("MoveHelperAlert") == true
	local key = `{text}|{count or ""}|{alert}`
	if key == drawn then
		return
	end
	drawn, faded = key, -1
	whistle(text, alert) -- 8.9
	local chipW = if count then widthOf(count, CHIP_TEXT, Theme.HeadingFont) + 2 * CHIP_PAD else 0
	local room = if count then chipW + CHIP_PAD else 0
	local width = math.min(B.Wide, B.Pad + widthOf(text, B.Text, Theme.Font) + room + B.Pad)
	gui.Size = UDim2.fromOffset(width, B.Tall)
	parts.words.Text = text
	parts.words.Size = UDim2.new(1, -(2 * B.Pad + room), 1, 0)
	parts.chip.Visible = count ~= nil
	parts.chip.Size = UDim2.fromOffset(chipW, B.Tall - 8)
	parts.count.Text = count or ""
	parts.pill.BackgroundColor3 = if alert then ORANGE else K.charcoal
	parts.words.TextColor3 = if alert then K.charcoal else K.text
	parts.chip.BackgroundColor3 = if alert then K.charcoal else K.raised
	parts.count.TextColor3 = if alert then K.text else K.secondary
end

-- Its fade (`alpha`: 0 as drawn … 1 gone): every part's own transparency toward 1.
local function fadeTo(alpha: number)
	if math.abs(alpha - faded) < 0.02 then
		return
	end
	faded = alpha
	local alert = player:GetAttribute("MoveHelperAlert") == true
	local base = if alert then 0 else Theme.PanelTransparency
	parts.pill.BackgroundTransparency = base + (1 - base) * alpha
	parts.edge.Transparency = EDGE + (1 - EDGE) * alpha
	parts.words.TextTransparency = alpha
	parts.chip.BackgroundTransparency = alpha
	parts.count.TextTransparency = alpha
end

-- One look: his body and head, the stack under the bubble (his speech, else his name tag), the distance.
local function step()
	local gui = build()
	if not gui then
		return
	end
	paint()
	local model = body()
	local head = if model then model:FindFirstChild("Head") or model.PrimaryPart else nil
	local text = player:GetAttribute("MoveHelperBubble")
	local camera = workspace.CurrentCamera
	if not head or not head:IsA("BasePart") or type(text) ~= "string" or text == "" or not camera then
		if gui.Enabled then
			gui.Enabled = false
		end
		return
	end
	local part = head :: BasePart
	if gui.Adornee ~= part then
		gui.Adornee = part
	end
	local speech = part:FindFirstChild("Speech")
	local tag = part:FindFirstChild("NameTag")
	local under = 0
	if speech and speech:IsA("BillboardGui") then
		under = speech.Size.Y.Offset
	elseif tag and tag:IsA("BillboardGui") and tag.Enabled then
		under = tag.Size.Y.Offset
	end
	local offset = Vector3.new(0, part.Size.Y * 0.5 + 0.9, 0) -- (where the tag and the speech stand: server/Npcs.luau's)
	if gui.StudsOffsetWorldSpace ~= offset then
		gui.StudsOffsetWorldSpace = offset
	end
	local lift = Vector2.new(0, DannyBubble.lift(under, B.Tall))
	if gui.SizeOffset ~= lift then
		gui.SizeOffset = lift
	end
	local alpha, top = DannyBubble.fade((camera.CFrame.Position - part.Position).Magnitude)
	fadeTo(alpha)
	if gui.AlwaysOnTop ~= top then
		gui.AlwaysOnTop = top
	end
	local on = alpha < 0.999
	if gui.Enabled ~= on then
		gui.Enabled = on
	end
end

function DannyBubble.start()
	if started then
		return
	end
	started = true
	for _, name in { "MoveHelper", "MoveHelperId", "MoveHelperBubble", "MoveHelperAlert", "MoveHelperQueue" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			pcall(step)
		end)
	end
	task.spawn(function()
		while true do
			local ok, err = pcall(step :: any)
			if not ok then
				warn(`[DannyBubble] {err}`)
			end
			task.wait(B.Tick)
		end
	end)
end

return DannyBubble
