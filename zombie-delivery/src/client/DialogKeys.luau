--!strict
-- 4.4.1: Space for the dialogs you click through. A dialog registers here while it is open (DialogKeys.open / close,
-- or DialogKeys.watch for a frame whose Visible says it): Space, Enter or the gamepad's A then does what its main
-- button does (Marge's CONTINUE, a result card's OK) for the topmost one (the highest layer, then the newest).
--
--   * The keys are bound (ContextActionService, high priority) only while a dialog is open, so Space jumps (and gets
--     you out of a seat) again as soon as the last one closes. While one is open they do nothing else.
--   * Not while typing (a focused TextBox: the chat) and not over a gamepad's selected button (A presses that).
--   * A key pressed right as a dialog opens does not skip it (`guard` seconds: a jump, a radio coming mid-drive).
--   * DialogKeys.hint(): "SPACE" for the button's key hint on a keyboard device, "" on touch.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local DialogKeys = {}

local ACTION = "DialogKeysAdvance"
local KEYS = { Enum.KeyCode.Space, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.ButtonA }
local GUARD = 0.3 -- seconds after opening when the keys do nothing yet (default)

export type Options = {
	guard: number?, -- seconds the keys wait after it opens (default GUARD)
	layer: number?, -- a higher layer wins over a newer dialog of a lower one (default 1)
	shown: (() -> boolean)?, -- is it really on screen now (default: yes while registered)
}

type Entry = { id: string, advance: () -> (), openedAt: number, guard: number, layer: number, shown: (() -> boolean)? }

local stack: { Entry } = {}
local bound = false

-- The dialog the keys go to: the highest layer, then the newest; nil when none is on screen.
local function topmost(): Entry?
	local best: Entry? = nil
	for _, entry in stack do
		local shown = entry.shown
		if (shown == nil or shown()) and (best == nil or entry.layer >= best.layer) then
			best = entry
		end
	end
	return best
end

local function handle(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if UserInputService:GetFocusedTextBox() then
		return Enum.ContextActionResult.Pass
	end
	if input.KeyCode == Enum.KeyCode.ButtonA and GuiService.SelectedObject ~= nil then
		return Enum.ContextActionResult.Pass
	end
	local entry = topmost()
	if not entry then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin and os.clock() - entry.openedAt > entry.guard then
		task.spawn(entry.advance)
	end
	return Enum.ContextActionResult.Sink
end

local function rebind()
	local want = #stack > 0
	if want == bound then
		return
	end
	bound = want
	if want then
		ContextActionService:BindActionAtPriority(ACTION, handle, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(KEYS))
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

-- Is the dialog `id` registered?
function DialogKeys.isOpen(id: string): boolean
	for _, entry in stack do
		if entry.id == id then
			return true
		end
	end
	return false
end

-- The dialog `id` is closed: the keys stop going to it (unbound when it was the last one).
function DialogKeys.close(id: string)
	for index = #stack, 1, -1 do
		if stack[index].id == id then
			table.remove(stack, index)
		end
	end
	rebind()
end

-- The dialog `id` opened (again: it becomes the newest): the keys run `advance`, its main button's action.
function DialogKeys.open(id: string, advance: () -> (), options: Options?)
	DialogKeys.close(id)
	local o: Options = options or {}
	table.insert(stack, {
		id = id,
		advance = advance,
		openedAt = os.clock(),
		guard = o.guard or GUARD,
		layer = o.layer or 1,
		shown = o.shown,
	})
	rebind()
end

-- A dialog that is open while `frame` is Visible (and its ScreenGui enabled): registered and closed with it.
function DialogKeys.watch(id: string, frame: GuiObject, advance: () -> (), options: Options?)
	local o: Options = options or {}
	local function shown(): boolean
		local gui = frame:FindFirstAncestorWhichIsA("LayerCollector")
		return frame.Visible and frame.Parent ~= nil and (gui == nil or gui.Enabled)
	end
	local function update()
		if frame.Visible then
			if not DialogKeys.isOpen(id) then
				DialogKeys.open(id, advance, { guard = o.guard, layer = o.layer, shown = shown })
			end
		else
			DialogKeys.close(id)
		end
	end
	frame:GetPropertyChangedSignal("Visible"):Connect(update)
	frame.Destroying:Connect(function()
		DialogKeys.close(id)
	end)
	update()
end

-- The key's name for a hint next to the main button: "SPACE" with a keyboard, nothing on a touch screen.
function DialogKeys.hint(): string
	if UserInputService.KeyboardEnabled then
		return "SPACE"
	end
	return ""
end

return DialogKeys
