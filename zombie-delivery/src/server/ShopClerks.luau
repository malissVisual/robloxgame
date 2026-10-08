--!strict
-- 6.12.1, a clerk behind every shop counter (the owner: "the things are bought only from the people in the shops, for
-- the vibe"): server/World.luau's shop counters (World.ShopPrompts: Last Stop Supplies, Lead & Co., Spoke & Chain,
-- Dead End Motors, Wrench Garage, the ZDC Bags kiosk) each get a person behind the counter (server/Npcs.luau, a look of
-- their own and a name over the head), and the counter's "Shop" prompt moves onto them: you shop by talking to the
-- clerk. They greet you (a wave, a line) and look at you when you come to the counter. server/Shops.luau keeps its own
-- handler on the same prompt (it opens the shop); a counter without room for a clerk keeps its prompt.
-- 6.12.2: Dot (Last Stop Supplies) and Nell (ZDC Bags) stand side by side, behind the GEAR and BAGS counters of the
-- gear stall at the spawn (server/GearStall.luau); Last Stop's old building has no counter, so nobody stands there.
-- 6.12, the looks (the owner: "things are bought only from the NPCs in the shops, for the vibe"): the clerks who sell
-- them (Config.Cosmetics.Counters: Dot at the gear stall, Gus at Wrench Garage, Kip at Spoke & Chain) get a second
-- prompt under "Shop": "Style" on R (the gamepad's L2), so both show at once (E is "Shop"'s). It greets you as "Shop"
-- does and opens the phone's STYLE app on their tab (StyleWear.invite: COURIER at Dot, VEHICLE at Gus and Kip), where
-- BUY works while you stand at the shop (server/StyleWear.luau checks it).
--   Why R and L2: nothing else in the game uses them. The keyboard's E, G, X, F, H, Q, T, Y, V, B, J, M, I, U, C, K, L,
--   N, P, the numbers, Tab and Shift are taken (client/KeyHints.luau, PhoneApps' KEYS); the gamepad's X is every E
--   prompt's, B the G prompts' and the phone's back, Y the menu, L1 / R1 the holster, a throw, a seat and STYLE's tabs,
--   the D-pad the phone, the weapon wheel and the hands, L3 the camera, R2 the gun.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Map = require(Shared:WaitForChild("Map"))
local World = require(script.Parent.World)
local Npcs = require(script.Parent.Npcs)
local StyleWear = require(script.Parent.StyleWear)

local ShopClerks = {}

type Clerk = { name: string, title: string, role: string, lines: { string } }

-- Who stands behind which counter (the shop ids of World.ShopPrompts).
local CLERKS: { [string]: Clerk } = {
	supplies = { name = "Dot", title = "Last Stop Supplies", role = "townsperson", lines = { "Vests, medkits, a drink for the road. Take a look.", "Stock up, courier. The night is long." } }, -- (6.12.2: at the gear stall)
	guns = { name = "Ray", title = "Lead & Co.", role = "townsperson", lines = { "Looking for something with a kick?", "Every round counts out there." } },
	bikes = { name = "Kip", title = "Spoke & Chain", role = "townsperson", lines = { "Two wheels beat two feet. Have a look.", "Fresh chains, fresh tyres." } },
	dealer = { name = "Sal", title = "Dead End Motors", role = "townsperson", lines = { "Every one of these runs. Mostly.", "Need more room in the back? Let's talk." } },
	mechanic = { name = "Gus", title = "Wrench Garage", role = "townsperson", lines = { "Bring it in, I'll make it purr.", "Armour, tyres, a bigger engine?" } },
	bags = { name = "Nell", title = "ZDC Bags", role = "townsperson", lines = { "A good bag and you can sprint with the goods.", "Pick a bag, any bag." } }, -- (6.12.2: next to Dot)
}

local BEHIND = 1.6 -- studs behind the counter's back face where the clerk stands
local STYLE_KEY = Enum.KeyCode.R -- the looks' prompt (see the header: free on the keyboard …)
local STYLE_PAD = Enum.KeyCode.ButtonL2 -- (… and on a gamepad)
local STYLE_BELOW = 1.9 -- studs under the "Shop" prompt's attachment: the two prompts one over the other
local started = false

-- The floor under the counter (its bottom) and the spot behind it, facing the customers (the counter's front: its
-- LookVector, the shop's street side, as World builds every counter in the shop's frame).
local function spotBehind(desk: BasePart): CFrame
	local behind = desk.CFrame * CFrame.new(0, 0, desk.Size.Z / 2 + BEHIND)
	local feet = Vector3.new(behind.X, desk.Position.Y - desk.Size.Y / 2, behind.Z)
	local front = desk.CFrame.LookVector
	return CFrame.lookAt(feet, feet + Vector3.new(front.X, 0, front.Z))
end

local function place(prompt: ProximityPrompt, shop: string)
	local clerk = CLERKS[shop]
	local desk = prompt.Parent
	if not clerk or not desk or not desk:IsA("BasePart") then
		return
	end
	local npc = Npcs.spawn(Npcs.look(clerk.role, clerk.name, clerk.title), spotBehind(desk))
	local root = npc.PrimaryPart
	if not root then
		return
	end
	-- The prompt on the clerk's chest: "Shop · Ray (Lead & Co.)"
	local chest = Instance.new("Attachment")
	chest.Name = "ShopPromptAt"
	chest.Position = Vector3.new(0, 1, 0)
	chest.Parent = root
	prompt.ObjectText = `{clerk.name} · {(Map.Shops[shop] and Map.Shops[shop].name) or clerk.title}`
	prompt.ActionText = "Shop"
	prompt.Parent = chest
	local said = 0
	-- The clerk turns to you, waves and says a line (at most every 8 s): either prompt.
	local function greet(player: Player)
		local character = player.Character
		local body = character and character:FindFirstChild("HumanoidRootPart")
		if body and body:IsA("BasePart") then
			Npcs.face(npc, body.Position)
		end
		Npcs.act(npc, "wave")
		local now = os.clock()
		if now - said > 8 then
			said = now
			Npcs.say(npc, clerk.lines[math.random(1, #clerk.lines)], 4)
		end
	end
	prompt.Triggered:Connect(greet)
	-- 6.12, the looks: "Style · Gus · Looks for your rides" under "Shop", on its own key (both show at once).
	local counter = Config.Cosmetics.Counters[shop]
	if counter then -- (its clerk is this one: tests/run_tests.py compares the names)
		local below = Instance.new("Attachment")
		below.Name = "StylePromptAt"
		below.Position = chest.Position - Vector3.new(0, STYLE_BELOW, 0)
		below.Parent = root
		local style = Instance.new("ProximityPrompt")
		style.Name = "StylePrompt"
		style.ActionText = "Style"
		style.ObjectText = `{clerk.name} · {counter.pitch}`
		style.KeyboardKeyCode = STYLE_KEY
		style.GamepadKeyCode = STYLE_PAD
		style.HoldDuration = 0
		style.MaxActivationDistance = prompt.MaxActivationDistance
		style.RequiresLineOfSight = false
		style.Parent = below
		style.Triggered:Connect(function(player: Player)
			greet(player)
			StyleWear.invite(player, counter.tab)
		end)
	end
	-- A look at whoever comes up to the counter (cheap: every 0.5 s, the nearest player in reach)
	task.spawn(function()
		while npc.Parent do
			task.wait(0.5)
			local nearest: Vector3? = nil
			local best = prompt.MaxActivationDistance + 4
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local body = character and character:FindFirstChild("HumanoidRootPart")
				if body and body:IsA("BasePart") then
					local d = (body.Position - root.Position).Magnitude
					if d < best then
						best, nearest = d, body.Position
					end
				end
			end
			if nearest then
				Npcs.glance(npc, nearest)
			end
		end
	end)
end

function ShopClerks.start()
	if started then
		return
	end
	started = true
	for _, entry in World.ShopPrompts do
		local ok, err = pcall(function()
			place(entry.prompt, entry.shop)
		end)
		if not ok then
			warn(`[ShopClerks] no clerk at {entry.shop}: {err}`)
		end
	end
end

return ShopClerks
