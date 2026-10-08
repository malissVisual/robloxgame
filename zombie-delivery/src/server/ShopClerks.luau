--!strict
-- 6.12.1, a clerk behind every shop counter (the owner: "the things are bought only from the people in the shops, for
-- the vibe"): server/World.luau's shop counters (World.ShopPrompts: Last Stop Supplies, Lead & Co., Spoke & Chain,
-- Dead End Motors, Wrench Garage, the ZDC Bags kiosk) each get a person behind the counter (server/Npcs.luau, a look of
-- their own and a name over the head), and the counter's "Shop" prompt moves onto them: you shop by talking to the
-- clerk. They greet you (a wave, a line) and look at you when you come to the counter. server/Shops.luau keeps its own
-- handler on the same prompt (it opens the shop); a counter without room for a clerk keeps its prompt.
local Players = game:GetService("Players")

local Map = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Map"))
local World = require(script.Parent.World)
local Npcs = require(script.Parent.Npcs)

local ShopClerks = {}

type Clerk = { name: string, title: string, role: string, lines: { string } }

-- Who stands behind which counter (the shop ids of World.ShopPrompts).
local CLERKS: { [string]: Clerk } = {
	supplies = { name = "Dot", title = "Last Stop Supplies", role = "townsperson", lines = { "Vests, bags, a drink for the road. Take a look.", "Stock up, courier. The night is long." } },
	guns = { name = "Ray", title = "Lead & Co.", role = "townsperson", lines = { "Looking for something with a kick?", "Every round counts out there." } },
	bikes = { name = "Kip", title = "Spoke & Chain", role = "townsperson", lines = { "Two wheels beat two feet. Have a look.", "Fresh chains, fresh tyres." } },
	dealer = { name = "Sal", title = "Dead End Motors", role = "townsperson", lines = { "Every one of these runs. Mostly.", "Need more room in the back? Let's talk." } },
	mechanic = { name = "Gus", title = "Wrench Garage", role = "townsperson", lines = { "Bring it in, I'll make it purr.", "Armour, tyres, a bigger engine?" } },
	bags = { name = "Nell", title = "ZDC Bags", role = "townsperson", lines = { "A good bag and you can sprint with the goods.", "Pick a bag, any bag." } },
}

local BEHIND = 1.6 -- studs behind the counter's back face where the clerk stands
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
	prompt.Triggered:Connect(function(player: Player)
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
	end)
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
