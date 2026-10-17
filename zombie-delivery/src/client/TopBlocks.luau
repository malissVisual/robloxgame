--!strict
-- 7.0 review: the panels that hold the top of the screen in the middle (the move's panel, client/MovingHud.luau; the
-- depot helper's strip under it, client/MoveHelperHud.luau), so what else draws there keeps clear of them: the guide's
-- line (client/SandboxGuide.luau), the grip check, the quick chat's lines (client/QuickChat.luau), Danny's card and
-- orders mode, a visitor's offer, the run's danger strip and the minimap go under them or beside them. Every ScreenGui has its own origin: the rectangles come relative to the one
-- given (a gui's AbsolutePosition), from the panels' AbsolutePosition / AbsoluteSize.
--   TopBlocks.set(name, object?)        a panel (nil: gone); its moves, sizes and showing are watched
--   TopBlocks.get(name)                 the panel by name
--   TopBlocks.rects(origin?)            the ones showing: { x0, y0, x1, y1 } relative to `origin`
--   TopBlocks.bottom(origin?, x0?, x1?) the lowest edge of the ones showing (across x0 … x1 when given), nil: none
--   TopBlocks.onChanged(fn) -> stop     fn() whenever one is set, moves, resizes, shows or hides
-- Presentation only.

local TopBlocks = {}

export type Rect = { x0: number, y0: number, x1: number, y1: number }

local blocks: { [string]: GuiObject } = {}
local hooks: { [string]: { RBXScriptConnection } } = {}
local listeners: { [number]: () -> () } = {}
local nextListener = 0

local function changed()
	for _, fn in listeners do
		pcall(fn)
	end
end

function TopBlocks.set(name: string, object: GuiObject?)
	local old = hooks[name]
	if old then
		for _, hook in old do
			hook:Disconnect()
		end
		hooks[name] = nil
	end
	local watched = object
	if not watched then
		blocks[name] = nil
	else
		blocks[name] = watched
		hooks[name] = {
			watched:GetPropertyChangedSignal("AbsoluteSize"):Connect(changed),
			watched:GetPropertyChangedSignal("AbsolutePosition"):Connect(changed),
			watched:GetPropertyChangedSignal("Visible"):Connect(changed),
		}
	end
	changed()
end

function TopBlocks.get(name: string): GuiObject?
	return blocks[name]
end

-- Showing: visible itself, with a size, still in a gui (its own ScreenGui enabled).
local function showing(object: GuiObject): boolean
	if not object.Visible or not object.Parent then
		return false
	end
	local size = object.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return false
	end
	local holder = object:FindFirstAncestorWhichIsA("ScreenGui")
	return holder == nil or holder.Enabled ~= false
end

function TopBlocks.rects(origin: Vector2?): { Rect }
	local ox, oy = 0, 0
	if origin then
		ox, oy = origin.X, origin.Y
	end
	local list: { Rect } = {}
	for _, object in blocks do
		if showing(object) then
			local p, s = object.AbsolutePosition, object.AbsoluteSize
			table.insert(list, { x0 = p.X - ox, y0 = p.Y - oy, x1 = p.X - ox + s.X, y1 = p.Y - oy + s.Y })
		end
	end
	return list
end

function TopBlocks.bottom(origin: Vector2?, x0: number?, x1: number?): number?
	local lowest: number? = nil
	for _, r in TopBlocks.rects(origin) do
		if (x0 == nil or r.x1 > x0) and (x1 == nil or r.x0 < x1) then
			lowest = math.max(lowest or r.y1, r.y1)
		end
	end
	return lowest
end

function TopBlocks.onChanged(fn: () -> ()): () -> ()
	nextListener += 1
	local id = nextListener
	listeners[id] = fn
	return function()
		listeners[id] = nil
	end
end

return TopBlocks
