--!strict
-- 7.1, the move's sounds (art/audio/sfx4.ogg, shared/SoundSheet.luau Sfx4; what plays when: shared/SoundPlan.luau,
-- Config.Soundscape.Move). Heard from what the move already sends, no hooks in its own modules:
--   the Moving remote's "state" (server/Moving.luau's view of your move; SoundPlan.moveCues): a new move's sting, the
--             horde's siren, the house's front door (in and out), a piece into the truck, a piece broken (glass, else
--             a crash) or jolted hard in your hands (a crash)
--   your character's MoveCarry: your hands taking a piece and putting it down (a box rustles; a piece that went into
--             the truck plays truck_load from the state instead), and a two-person piece dragged alone scraping while
--             you move (a loop in your root, followed every Tick)
-- Started by client/Sounds.luau (MoveSounds.start(api)), which hands over how to play: its regions, its stand-ins
-- (SoundSheet.Fallback) while sfx4.ogg is not uploaded, the SOUND setting.
-- MoveSounds.slipped(): for the grip's UI, the piece slipped from your hands: grip_slip (a whoosh and a thud) now,
-- and the put-down its MoveCarry clearing would play is left out, and so is the state's heavy_drop for the slip's
-- damage (7.1 review: one thud, not two; both for Config.Soundscape.Move.SlipQuiet s).
-- MoveSounds.inside(): 8.1, are you inside the move's house (its state's inside: the interior its door takes you to)?
-- client/SoundScape.luau's ambience asks (the farmstead's quiet room). The state's back plays no ramp (the Sprinter's
-- back doors are heard swinging: client/SoundScape.luau) and the move's end no Wall's gate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SoundPlan = require(Shared.SoundPlan)

local MoveSounds = {}

export type Api = {
	play: (name: string, volume: number?, pitch: number?) -> (),
	make: (name: string, parent: Instance?, looped: boolean) -> Sound?,
	on: () -> boolean,
}

local M = Config.Soundscape.Move
local player = Players.LocalPlayer

local api: Api? = nil
local view: any = nil -- the move's last state (nil: no move)
local pending: { spot: number }? = nil -- your hands just went empty: where did the piece go (the next state says)
local slipAt = -math.huge -- MoveSounds.slipped (its thud is the put-down and the jolt)
local scrape: Sound? = nil

local function cue(c: SoundPlan.Cue)
	local a = api
	if a then
		a.play(c.name, c.volume, c.pitch)
	end
end

-- The piece left your hands: put down, unless the state now has it in the truck (moveCues plays truck_load then) or
-- in a crew mate's hands (you let go of a two-person piece's end: it goes on with them).
local function settle()
	local p = pending
	pending = nil
	local item = if p then SoundPlan.moveItem(view, p.spot) else nil
	if not item or item.state == "truck" or (item.state == "carried" and item.mine ~= true) then
		return
	end
	if os.clock() - slipAt < M.SlipQuiet then
		return -- (it slipped: grip_slip had its thud)
	end
	cue(SoundPlan.carryCue(item, false))
end

function MoveSounds.slipped()
	slipAt = os.clock()
	cue({ name = "grip_slip", volume = M.Slip, pitch = 1 })
end

function MoveSounds.inside(): boolean
	return type(view) == "table" and view.inside == true
end

local function onState(state: any)
	local was = view
	view = if type(state) == "table" then state else nil
	local slipping = os.clock() - slipAt < M.SlipQuiet
	for _, c in SoundPlan.moveCues(was, view, workspace:GetServerTimeNow()) do
		if slipping and c.name == "heavy_drop" then
			continue -- (7.1 review: it slipped: grip_slip had its thud, the slip's damage needs no second one)
		end
		cue(c)
	end
	if pending then
		settle()
	end
end

local function watchCharacter(character: Model)
	local held = character:GetAttribute("MoveCarry")
	character:GetAttributeChangedSignal("MoveCarry"):Connect(function()
		local now = character:GetAttribute("MoveCarry")
		local before = held
		held = now
		if type(now) == "number" then
			pending = nil
			cue(SoundPlan.carryCue(SoundPlan.moveItem(view, now), true))
		elseif type(before) == "number" then
			local p = { spot = before }
			pending = p
			task.delay(M.PutDownWait, function()
				if pending == p then
					settle()
				end
			end)
		end
	end)
end

-- A two-person piece dragged alone: the scrape while you move (its pitch with your speed), quiet standing still.
local function updateScrape()
	local a = api
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local spot = character and character:GetAttribute("MoveCarry")
	local dragging = a ~= nil and root ~= nil and a.on() and SoundPlan.dragged(view, spot)
	local sound = scrape
	if sound and (not dragging or sound.Parent ~= root) then
		sound:Destroy()
		scrape = nil
		sound = nil
	end
	if not dragging or not root or not a then
		return
	end
	if not sound then
		local made = a.make("wood_scrape_loop", root, true) -- (nil until sfx4.ogg is up: no stand-in for a drag)
		if not made then
			return
		end
		made.Volume = 0
		made:Play()
		scrape = made
		sound = made
	end
	assert(sound)
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	sound.Volume += ((if speed > M.ScrapeFrom then M.Scrape else 0) - sound.Volume) * M.ScrapeBlend
	sound.PlaybackSpeed = 0.9 + 0.2 * math.clamp(speed / 8, 0, 1)
end

function MoveSounds.start(how: Api)
	api = how
	Net.get("Moving").OnClientEvent:Connect(function(kind: any, a: any)
		if kind == "state" then
			onState(a)
		end
	end)
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	task.spawn(function()
		while true do
			task.wait(M.Tick)
			local ok, err = pcall(function()
				updateScrape()
			end)
			if not ok then
				warn("[MoveSounds]", err)
				task.wait(5)
			end
		end
	end)
end

return MoveSounds
