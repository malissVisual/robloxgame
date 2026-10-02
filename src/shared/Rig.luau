--!nonstrict
-- R15 characters for the game's fighters.
--   Rig.base()            the plain R15 rig the Soldier class is cloned from. The SERVER makes it once
--                         (Players:CreateHumanoidModelFromDescription) and keeps it in ReplicatedStorage as
--                         "R15Base", so the client can clone it too (UI previews, the drag ghost).
--   Rig.animate(model…)   registers a rig for animations; Rig.setMoving / attack / cast / die play them.
--                         All of them do nothing on a model that is not a registered rig (block models).

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Rig = {}

local BASE_NAME = "R15Base"
local baseState = "none" -- none | loading | ready | failed
local baseRig: Model? = nil

-- The base rig, or nil when it does not exist (the caller falls back to a block model). On the server the
-- first call makes it (it yields for a moment); the client only looks for it and never waits.
function Rig.base(): Model?
	if not RunService:IsServer() then
		return ReplicatedStorage:FindFirstChild(BASE_NAME)
	end
	if baseState == "none" then
		baseState = "loading"
		local ok, result = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		local rig = if ok then result else nil
		local root = rig and rig:FindFirstChild("HumanoidRootPart")
		local foot = rig and rig:FindFirstChild("LeftFoot")
		if rig and root and foot and rig:FindFirstChild("Head") and rig:FindFirstChild("RightHand") and rig:FindFirstChildOfClass("Humanoid") then
			for _, item in rig:GetDescendants() do
				if item:IsA("LuaSourceContainer") or item:IsA("BodyColors") or item:IsA("Accessory") or item:IsA("Clothing") then
					item:Destroy()
				end
			end
			root.Anchored = true
			rig.PrimaryPart = root
			rig.Name = BASE_NAME
			-- The pivot (HumanoidRootPart) down to the soles, at scale 1.
			rig:SetAttribute("Lift", root.Position.Y - (foot.Position.Y - foot.Size.Y / 2))
			rig.Parent = ReplicatedStorage
			baseRig = rig
			baseState = "ready"
			print("[Rig] R15 base rig ready")
		else
			warn("[Rig] the R15 rig could not be made, block models are used:", if ok then "parts missing" else result)
			baseState = "failed"
		end
	end
	while baseState == "loading" do
		task.wait()
	end
	return baseRig
end

-- ── Animations (Roblox's own R15 animations: they work in every place) ──
local ANIMATIONS = {
	idle = 507766666,
	run = 507767714,
	hold = 507768375, -- the weapon hand is held up
	slash = 522635514,
	lunge = 522638767,
	cast = 507770677, -- both arms up
	jump = 507765000,
}
local PRIORITY = {
	idle = Enum.AnimationPriority.Core,
	run = Enum.AnimationPriority.Idle,
	hold = Enum.AnimationPriority.Movement,
	slash = Enum.AnimationPriority.Action,
	lunge = Enum.AnimationPriority.Action,
	cast = Enum.AnimationPriority.Action,
	jump = Enum.AnimationPriority.Action,
}

local registered = setmetatable({}, { __mode = "k" }) -- model → { attack, hold }
local loaded = setmetatable({}, { __mode = "k" }) -- model → { tracks, moving }

-- The rig's tracks (loaded the first time the model is in the world); nil for a block model.
local function rigOf(model: Model)
	local rig = loaded[model]
	if rig then
		return rig
	end
	local info = registered[model]
	if not info or not model:IsDescendantOf(workspace) then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local tracks = {}
	for name, id in ANIMATIONS do
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://" .. id
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Priority = PRIORITY[name]
			track.Looped = name == "idle" or name == "run" or name == "hold"
			tracks[name] = track
		end
	end
	rig = { tracks = tracks, moving = nil, attack = info.attack, glide = info.glide }
	loaded[model] = rig
	if info.hold and tracks.hold then
		tracks.hold:Play(0.1)
	end
	return rig
end

-- Run while walking to the target, idle while standing.
function Rig.setMoving(model: Model, moving: boolean)
	local rig = rigOf(model)
	if not rig or rig.moving == moving then
		return
	end
	rig.moving = moving
	if rig.glide then
		return -- a gliding rig (the Mage) keeps its idle pose: the server floats and leans it instead of a run
	end
	local on, off = rig.tracks[if moving then "run" else "idle"], rig.tracks[if moving then "idle" else "run"]
	if off then
		off:Stop(0.15)
	end
	if on then
		on:Play(0.15)
	end
end

-- Registers a rig: `attack` = its attack animation ("slash" | "lunge" | "cast"), `hold` = the weapon hand is
-- held up, `glide` = no run animation (the Mage floats; MageBrain moves it). The idle animation starts as soon as
-- the caller has put the model into the world.
function Rig.animate(model: Model, attack: string, hold: boolean, glide: boolean?)
	registered[model] = { attack = attack, hold = hold, glide = glide == true }
	task.spawn(function()
		for _ = 1, 30 do
			if model:IsDescendantOf(workspace) then
				Rig.setMoving(model, false)
				return
			end
			task.wait(0.1)
		end
	end)
end

-- The attack swing. `speed` = the battle speed.
function Rig.attack(model: Model, speed: number?)
	local rig = rigOf(model)
	local track = rig and rig.tracks[rig.attack]
	if track then
		track:Play(0.05, 1, 1.3 * (speed or 1))
	end
end

-- Raises the weapon hand (the forearm comes up, the weapon points forward) for `duration` seconds, then lowers
-- it again: the mage's charge pose. Nothing happens for a rig that holds its hand up all the time anyway.
function Rig.raise(model: Model, duration: number)
	local rig = rigOf(model)
	local info = registered[model]
	local track = rig and rig.tracks.hold
	if not track or (info and info.hold) then
		return
	end
	track:Play(0.12)
	task.delay(duration, function()
		if track.IsPlaying then
			track:Stop(0.25)
		end
	end)
end

-- One animation by name (a boss ability): "jump", "cast", "lunge", "slash".
function Rig.cast(model: Model, name: string)
	local rig = rigOf(model)
	local track = rig and rig.tracks[name]
	if track then
		track:Play(0.05, 1, 1)
	end
end

-- The death: the fighter falls on its back and fades away. Returns false for a block model (the caller
-- destroys it).
function Rig.die(model: Model): boolean
	local root = model.PrimaryPart
	if not registered[model] or not root or not model.Parent then
		return false
	end
	local rig = loaded[model]
	if rig then
		for _, track in rig.tracks do
			track:Stop(0.1)
		end
	end
	local info = model:FindFirstChild("Info", true)
	if info then
		info:Destroy()
	end
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			-- Loose anchored extras (a halo) are welded so they fall with the body.
			if item ~= root and item.Anchored then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = item
				weld.Parent = item
				item.Anchored = false
			end
			if item.Transparency < 1 then
				TweenService:Create(item, TweenInfo.new(0.3, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 0.35), { Transparency = 1 }):Play()
			end
		elseif item:IsA("ParticleEmitter") or item:IsA("Sparkles") or item:IsA("PointLight") or item:IsA("Highlight") then
			item:Destroy()
		end
	end
	TweenService:Create(root, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = root.CFrame * CFrame.new(0, -root.Size.Y * 1.1, 0) * CFrame.Angles(math.rad(85), 0, 0) }):Play()
	Debris:AddItem(model, 0.7)
	return true
end

return Rig
