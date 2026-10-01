--!strict
-- Shared server-side battle visuals: every effect is built from plain Parts (Neon), BillboardGui text, Highlights and
-- tweens — no asset ids. Stateless apart from the per-tick pop counter (BattleFx.resetTick is called at the top of
-- every battle tick). BattleService uses it directly; the Mage and enemy brains receive it through their context
-- (`ctx.fx`), because their test harnesses replace the module header and pass a table of no-op functions instead.
--
-- Telegraphs (warningCircle / warningLane / reticle) are visuals only: the caller destroys them at impact, and the
-- data hazards in BattleService (`battle.hazards`) are what the Mage's AI reads — so nothing is counted twice.

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Plots = require(script.Parent.Plots)

local UP = Vector3.new(0, 1, 0)

local BattleFx = {}

-- ── Parts ───────────────────────────────────────────────────────────────────

-- An anchored, non-colliding Neon part.
function BattleFx.newPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Tweens a part to `goal` and removes it afterwards.
function BattleFx.fade(part: BasePart, duration: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	TweenService:Create(part, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(part, duration + 0.1)
end

-- A flat ring that expands on the floor and fades (a shockwave).
function BattleFx.groundRing(parent: Instance, position: Vector3, color: Color3, radius: number, duration: number)
	local ring = BattleFx.newPart(parent, Vector3.new(0.3, 1, 1), CFrame.new(position + UP * 0.3) * CFrame.Angles(0, 0, math.rad(90)), color, 0.2, Enum.PartType.Cylinder)
	BattleFx.fade(ring, duration, { Size = Vector3.new(0.3, radius * 2, radius * 2), Transparency = 1 })
end

-- Small glowing bits that fly out (and up) from a point and fade.
function BattleFx.sparks(parent: Instance, position: Vector3, color: Color3, count: number, spread: number, height: number)
	for _ = 1, count do
		local angle = math.random() * math.pi * 2
		local distance = spread * (0.3 + math.random() * 0.7)
		local size = 0.4 + math.random() * 0.5
		local spark = BattleFx.newPart(parent, Vector3.one * size, CFrame.new(position + UP), color, 0, Enum.PartType.Ball)
		BattleFx.fade(spark, 0.5 + math.random() * 0.4, {
			Position = position + Vector3.new(math.cos(angle) * distance, height * (0.4 + math.random() * 0.6), math.sin(angle) * distance),
			Transparency = 1,
			Size = Vector3.one * 0.1,
		})
	end
end

-- A straight beam between two points (a thin Neon slab) that thins out and fades.
function BattleFx.beam(parent: Instance, a: Vector3, b: Vector3, color: Color3, width: number, duration: number)
	local length = (b - a).Magnitude
	if length < 0.1 then
		return
	end
	local segment = BattleFx.newPart(parent, Vector3.new(width, width, length), CFrame.lookAt((a + b) / 2, b), color, 0)
	BattleFx.fade(segment, duration, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, length) })
end

-- A jagged lightning bolt from `top` down to `bottom`.
function BattleFx.lightning(parent: Instance, top: Vector3, bottom: Vector3, color: Color3, width: number)
	local points = { top }
	local segments = 6
	for i = 1, segments - 1 do
		points[#points + 1] = top:Lerp(bottom, i / segments) + Vector3.new((math.random() - 0.5) * 5, 0, (math.random() - 0.5) * 5)
	end
	points[#points + 1] = bottom
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = (b - a).Magnitude
		local segment = BattleFx.newPart(parent, Vector3.new(width, width, length), CFrame.lookAt((a + b) / 2, b), color, 0)
		BattleFx.fade(segment, 0.35, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, length) })
	end
end

-- A colored glow on a model for a while (frost, shield, enrage).
function BattleFx.tint(model: Instance, color: Color3, duration: number)
	if not model.Parent then
		return
	end
	local glow = Instance.new("Highlight")
	glow.Adornee = model
	glow.FillColor = color
	glow.FillTransparency = 0.55
	glow.OutlineColor = color
	glow.OutlineTransparency = 0.2
	glow.Parent = model
	Debris:AddItem(glow, duration)
end

-- A translucent Neon silhouette left behind by a quick move (an afterimage); it fades in 0.35 s.
function BattleFx.afterimage(folder: Instance, pos: Vector3, lift: number, color: Color3)
	local ghost = BattleFx.newPart(folder, Vector3.new(1.6, 4, 1.2), CFrame.new(pos + UP * lift), color, 0.6)
	BattleFx.fade(ghost, 0.35, { Transparency = 1, Size = Vector3.new(1.2, 4.4, 0.9) })
end

-- ── Text pops ───────────────────────────────────────────────────────────────

local popsThisTick = 0

-- Called at the top of every battle tick: a new budget of pops.
function BattleFx.resetTick()
	popsThisTick = 0
end

-- A short text above a position ("OW!", "COMBO!"): scales in, drifts up and fades. Dropped when the tick's budget is
-- used up (6), so a busy fight never turns into a wall of text.
function BattleFx.pop(parent: Instance, position: Vector3, text: string, color: Color3, size: number?)
	if popsThisTick >= 6 or not parent.Parent then
		return
	end
	popsThisTick += 1
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one * 0.2
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = position
	anchor.Parent = parent
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(140, 44)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 140
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = size or 22
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = billboard
	local scale = Instance.new("UIScale")
	scale.Scale = 1.6
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(billboard, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1)
end

-- A tag above a model's head ("MARKED", "FRENZY", "HEX", "CHAMPION") with a 0.5 s pulse; gone after `duration`.
function BattleFx.mark(model: Instance, text: string, color: Color3, duration: number): Instance
	local head = model:FindFirstChild("Head") or (model :: any).PrimaryPart
	local gui = Instance.new("BillboardGui")
	gui.Name = "Mark"
	gui.Size = UDim2.fromOffset(120, 30)
	gui.StudsOffset = Vector3.new(0, 3.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	if head then
		gui.Adornee = head
	end
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 18
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.25 }):Play()
	gui.Parent = model
	Debris:AddItem(gui, duration)
	return gui
end

-- ── Telegraphs (visual only, no Hazard attribute: the battle's data hazards are the truth) ──

local function pulse(p: BasePart, from: number, to: number)
	TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = to }):Play()
	p.Transparency = from
end

-- A circle on the floor: a bright border and a pulsing translucent fill. Returns the parts (destroy them at impact).
function BattleFx.warningCircle(folder: Instance, pos: Vector3, radius: number, color: Color3, groundY: number): { Instance }
	local turn = CFrame.Angles(0, 0, math.rad(90))
	local border = BattleFx.newPart(folder, Vector3.new(0.28, radius * 2, radius * 2), CFrame.new(pos.X, groundY, pos.Z) * turn, color, 0.05, Enum.PartType.Cylinder)
	local fill = BattleFx.newPart(folder, Vector3.new(0.2, math.max(radius - 0.35, 0.2) * 2, math.max(radius - 0.35, 0.2) * 2), CFrame.new(pos.X, groundY + 0.01, pos.Z) * turn, color, 0.7, Enum.PartType.Cylinder)
	pulse(fill, 0.7, 0.45)
	return { border, fill }
end

-- A lane on the floor along the segment from → to (`width` wide): a translucent slab plus two bright edge lines.
function BattleFx.warningLane(folder: Instance, from: Vector3, to: Vector3, width: number, color: Color3, groundY: number): { Instance }
	local a = Vector3.new(from.X, groundY, from.Z)
	local b = Vector3.new(to.X, groundY, to.Z)
	local length = (b - a).Magnitude
	if length < 0.1 then
		return {}
	end
	local mid = (a + b) / 2
	local look = CFrame.lookAt(mid, b)
	local slab = BattleFx.newPart(folder, Vector3.new(width, 0.2, length), look, color, 0.7)
	pulse(slab, 0.7, 0.45)
	local left = BattleFx.newPart(folder, Vector3.new(0.25, 0.26, length), look * CFrame.new(-width / 2, 0, 0), color, 0.05)
	local right = BattleFx.newPart(folder, Vector3.new(0.25, 0.26, length), look * CFrame.new(width / 2, 0, 0), color, 0.05)
	local cap = BattleFx.newPart(folder, Vector3.new(width, 0.26, 0.25), look * CFrame.new(0, 0, -length / 2), color, 0.05)
	return { slab, left, right, cap }
end

-- A pulsing flat ring where a spell is about to land (the caller destroys it when the spell resolves).
function BattleFx.reticle(folder: Instance, point: Vector3, radius: number, color: Color3, groundY: number): Instance
	local ring = BattleFx.newPart(folder, Vector3.new(0.22, radius * 2, radius * 2), CFrame.new(point.X, groundY, point.Z) * CFrame.Angles(0, 0, math.rad(90)), color, 0.5, Enum.PartType.Cylinder)
	pulse(ring, 0.5, 0.2)
	return ring
end

-- ── The Mage's body language ────────────────────────────────────────────────

-- Every PointLight under model.Weapon flashes `color` at brightness × `intensity` for `duration`, then goes back.
function BattleFx.crystalFlash(model: Instance, color: Color3, duration: number, intensity: number)
	local weapon = model:FindFirstChild("Weapon")
	if not weapon then
		return
	end
	for _, piece in weapon:GetChildren() do
		local light = piece:FindFirstChildOfClass("PointLight")
		if light then
			local brightness, range, original = light.Brightness, light.Range, light.Color
			TweenService:Create(light, TweenInfo.new(math.min(0.1, duration * 0.4), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = brightness * intensity, Range = range * 1.3, Color = color }):Play()
			task.delay(duration, function()
				if light.Parent then
					TweenService:Create(light, TweenInfo.new(0.25), { Brightness = brightness, Range = range, Color = original }):Play()
				end
			end)
		end
	end
end

-- The staff spins once around the hand (RightHand.RightGrip Motor6D C0 through 360° about X in two half turns) and
-- returns to its rest.
function BattleFx.staffSpin(model: Instance, duration: number)
	local hand = model:FindFirstChild("RightHand")
	local grip = hand and hand:FindFirstChild("RightGrip")
	if not (grip and grip:IsA("Motor6D")) then
		return
	end
	local half = TweenInfo.new(duration / 2, Enum.EasingStyle.Linear)
	TweenService:Create(grip, half, { C0 = CFrame.Angles(math.rad(180), 0, 0) }):Play()
	task.delay(duration / 2, function()
		if grip.Parent then
			TweenService:Create(grip, half, { C0 = CFrame.Angles(math.rad(359), 0, 0) }):Play()
			task.delay(duration / 2, function()
				if grip.Parent then
					grip.C0 = CFrame.new()
				end
			end)
		end
	end)
end

export type RuneRing = { update: (center: Vector3, dt: number) -> (), destroy: () -> () }

-- `count` small Neon slabs orbiting a center at 180°/s (the Overcharge runes, a shaman's cast orbs). The caller moves
-- it every tick with update(center, dt) and removes it with destroy().
function BattleFx.runeRing(folder: Instance, color: Color3, count: number, radius: number): RuneRing
	local parts: { Part } = {}
	for _ = 1, count do
		table.insert(parts, BattleFx.newPart(folder, Vector3.new(0.3, 0.3, 1.6), CFrame.new(), color, 0.1))
	end
	local angle = 0
	return {
		update = function(center: Vector3, dt: number)
			angle += math.rad(180) * dt
			for i, part in parts do
				if part.Parent then
					local a = angle + (i - 1) / count * math.pi * 2
					local offset = Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
					part.CFrame = CFrame.new(center + offset, center + offset + Vector3.new(-math.sin(a), 0, math.cos(a)))
				end
			end
		end,
		destroy = function()
			for _, part in parts do
				part:Destroy()
			end
			table.clear(parts)
		end,
	}
end

-- A shield bubble (shieldHp) breaking: a cyan ring, sparks and a "BREAK" pop.
function BattleFx.shieldBreak(parent: Instance, f: any)
	local cyan = Color3.fromRGB(120, 230, 255)
	BattleFx.groundRing(parent, f.pos, cyan, 4, 0.4)
	BattleFx.sparks(parent, f.pos + UP * f.lift, cyan, 6, 2, 3)
	BattleFx.pop(parent, f.pos + UP * (f.lift + 3), "BREAK", cyan, 18)
end

-- ── The player's own character ──────────────────────────────────────────────

-- Every player's character standing in this plot's arena within `radius` of `center` takes `hp` (Humanoid:TakeDamage).
-- Used only inside telegraphed areas (slams, charge lanes, storms), never for ordinary attacks.
function BattleFx.hitPlayers(plot: Plots.Plot, center: Vector3, radius: number, hp: number)
	local c = Vector3.new(center.X, 0, center.Z)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and Plots.isInArena(plot, root.Position) then
			if (Vector3.new(root.Position.X, 0, root.Position.Z) - c).Magnitude <= radius then
				humanoid:TakeDamage(hp)
			end
		end
	end
end

return BattleFx
