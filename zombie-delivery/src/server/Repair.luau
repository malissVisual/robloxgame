--!strict
-- 3.4, the repair shops (Map.RepairShops: Wrench Garage and Rust Bridge Repairs; their bays World.RepairBays). Drive
-- your car into a bay, stop and get out: after Config.Repair.StandStill s the mechanics take it. The car is locked on
-- the lift (Vehicles.setRepairing: anchored, its passengers step out) and repaired in Economy.repairTime(missing)
-- seconds (20 – 60 s, by the damage); then it is as good as new and the fee (Economy.repairFee, $20 – $300 by the
-- damage) is paid. Getting back in (Vehicles.beforeDrive), calling the car away, a garage swap or a wreck cancels it
-- (nothing to pay: the fee is charged at the end; then the damage the car took on the lift counts too, and without
-- the money the repair is cancelled). The bay's billboard shows who is being repaired and the time
-- left; the owner's HUD gets the "Repair" remote (client/GarageUi.luau): ({ car, shop, seconds, total, fee }) when it
-- starts, (nil) when it ends. A job's clock keeps running while you wait: your choice.
-- Any car can be repaired, a company vehicle lent for a job too (at the same fee). There are no free repairs.
-- 6.20: Known at the Shop (Config.Skills) takes a share off the fee, at every repair shop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)

local Server = script.Parent
local World = require(Server.World)
local Vehicles = require(Server.Vehicles)
local PlayerData = require(Server.PlayerData)

local Repair = {}

local Tuning = Config.Repair
local STEP = 0.25 -- seconds between two checks of the bays
local SLACK = 2 -- studs a car may stand outside its bay's lines and still count

type Bay = World.RepairBay
type Running = {
	car: Vehicles.Car,
	bay: Bay,
	total: number,
	endsAt: number,
	fee: number,
	name: string,
}
type Board = { gui: BillboardGui, title: TextLabel, info: TextLabel, fill: Frame }

local notice = Net.get("Notice")
local remote = Net.get("Repair")
local running: { [Player]: Running } = {}
local waiting: { [Player]: { bay: Bay, since: number } } = {}
local told: { [Player]: string } = {} -- the last "nothing to repair" / "not enough money" said for this bay visit
local takenBy: { [Bay]: Player } = {}
local quiet: { [Player]: Bay } = {} -- a repair just ended in this bay: nothing more until the car leaves it
local boards: { [Bay]: Board } = {}

-- "$1,234" (the server has no client/Ui).
local function money(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

-- ── The billboards over the bays ───────────────────────────────────────────

local function board(bay: Bay): Board
	local existing = boards[bay]
	if existing then
		return existing
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RepairBoard"
	gui.Size = UDim2.fromOffset(220, 62)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Adornee = bay.anchor
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 28, 26)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = back
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -12, 0, 26)
	title.Position = UDim2.fromOffset(6, 3)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(245, 179, 79)
	title.Parent = back
	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, -12, 0, 18)
	info.Position = UDim2.fromOffset(6, 29)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.GothamBold
	info.TextScaled = true
	info.TextColor3 = Color3.fromRGB(246, 241, 224)
	info.Parent = back
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -16, 0, 5)
	bar.Position = UDim2.new(0, 8, 1, -10)
	bar.BackgroundColor3 = Color3.fromRGB(10, 16, 13)
	bar.BorderSizePixel = 0
	bar.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(170, 218, 137)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	gui.Parent = bay.anchor
	local made: Board = { gui = gui, title = title, info = info, fill = fill }
	boards[bay] = made
	return made
end

local function idle(bay: Bay)
	local b = board(bay)
	b.title.Text = `🔧 BAY {bay.index} · REPAIRS`
	b.info.Text = "Drive in, stop, get out and wait"
	b.fill.Size = UDim2.fromScale(0, 1)
end

local function show(bay: Bay, job: Running, now: number)
	local b = board(bay)
	local left = math.max(0, job.endsAt - now)
	b.title.Text = `🔧 REPAIRING · {math.ceil(left)} s`
	b.info.Text = `{job.car.owner.DisplayName}'s {job.name} · {money(job.fee)}`
	b.fill.Size = UDim2.fromScale(math.clamp(1 - left / math.max(1, job.total), 0, 1), 1)
end


-- ── The bays ───────────────────────────────────────────────────────────────

-- The bay the car stands in (its middle inside the lines), or nil.
local function bayOf(car: Vehicles.Car): Bay?
	local position = car.chassis.Position
	for _, bay in World.RepairBays do
		local at = bay.cframe:PointToObjectSpace(position)
		if math.abs(at.X) <= bay.size.X / 2 + SLACK and math.abs(at.Z) <= bay.size.Z / 2 + SLACK and math.abs(at.Y) < 8 then
			return bay
		end
	end
	return nil
end

local function missingOf(car: Vehicles.Car): number
	return math.clamp(1 - car.health / math.max(1, car.stats.health), 0, 1)
end

-- 6.20: the fee for this player: Economy.repairFee less Known at the Shop's share (Config.Skills, server/Skills.luau).
local function feeFor(player: Player, missing: number): number
	local share = math.max(0, 1 - require(Server.Skills).effect(player, "repair"))
	return math.floor(Economy.repairFee(missing) * share + 0.5)
end

local function carName(car: Vehicles.Car): string
	local def = Economy.findCar(car.id)
	return if def then def.name else "car"
end

local function say(player: Player, key: string, text: string)
	if told[player] ~= key then
		told[player] = key
		notice:FireClient(player, text)
	end
end

local function release(player: Player, job: Running)
	running[player] = nil
	quiet[player] = job.bay
	if takenBy[job.bay] == player then
		takenBy[job.bay] = nil
	end
	idle(job.bay)
	if not job.car.wrecked then
		Vehicles.setRepairing(job.car, false)
	end
	remote:FireClient(player, nil)
end

-- Stops a running repair (nothing to pay). reason: the toast, or nil for none.
function Repair.cancel(player: Player, reason: string?)
	local job = running[player]
	if not job then
		return
	end
	release(player, job)
	if reason then
		notice:FireClient(player, reason)
	end
end

local function begin(player: Player, car: Vehicles.Car, bay: Bay)
	local missing = missingOf(car)
	local fee = feeFor(player, missing)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	if profile.money < fee then
		say(player, `money{bay.index}{bay.shop}`, `The repair of your {carName(car)} costs {money(fee)}: not enough money.`)
		return
	end
	local total = Economy.repairTime(missing)
	local now = os.clock()
	local job: Running = { car = car, bay = bay, total = total, endsAt = now + total, fee = fee, name = carName(car) }
	running[player] = job
	takenBy[bay] = player
	-- The car goes on the lift (Vehicles.setRepairing: its passengers step out).
	if Vehicles.backOpen(car) then
		Vehicles.setBack(car, false)
	end
	Vehicles.setRepairing(car, true)
	show(bay, job, now)
	remote:FireClient(player, { car = job.name, shop = bay.name, seconds = total, total = total, fee = fee })
	notice:FireClient(player, `{bay.name}: the mechanics take your {job.name}. {total} s, {money(fee)} when it is done. Get back in to cancel.`)
end

local function finish(player: Player, job: Running)
	local car = job.car
	-- The fee in full, never less: the damage the car took on the lift costs too, and money spent while waiting is
	-- not there any more (no repair then).
	local fee = math.max(job.fee, feeFor(player, missingOf(car)))
	if not PlayerData.spend(player, fee, "Repair", car.id) then
		release(player, job)
		notice:FireClient(player, `The repair of your {job.name} costs {money(fee)}: not enough money. Repair cancelled.`)
		return
	end
	Vehicles.repair(car, 1)
	release(player, job)
	notice:FireClient(player, `Your {job.name} is repaired ({money(fee)}). As good as new!`)
end

local function step()
	local now = os.clock()
	for player, job in running do
		local car = Vehicles.get(player)
		if car ~= job.car or job.car.wrecked or not player.Parent then
			-- The car went (a call, a garage, a wreck, the player left): no repair, nothing to pay.
			release(player, job)
			if player.Parent then
				notice:FireClient(player, "Repair cancelled: your car left the bay.")
			end
		elseif now >= job.endsAt then
			finish(player, job)
		else
			show(job.bay, job, now)
		end
	end
	for _, player in Players:GetPlayers() do
		if running[player] then
			continue
		end
		local car = Vehicles.get(player)
		local bay = if car and not car.chauffeured then bayOf(car) else nil
		if not car or not bay then
			waiting[player] = nil
			told[player] = nil
			quiet[player] = nil
			continue
		end
		if quiet[player] == bay then
			continue
		end
		local other = takenBy[bay]
		local empty = car.seat.Occupant == nil
		local still = Vehicles.speed(car) <= Tuning.MaxSpeed
		if missingOf(car) < Tuning.MinMissing then
			waiting[player] = nil
			if empty then
				say(player, `fine{bay.index}{bay.shop}`, `Your {carName(car)} is in perfect shape: nothing to repair.`)
			end
			continue
		end
		if other and other ~= player then
			waiting[player] = nil
			say(player, `busy{bay.index}{bay.shop}`, `Bay {bay.index} is busy: park in the other one.`)
			continue
		end
		if not empty or not still then
			waiting[player] = nil
			if not empty and still then
				say(player, `out{bay.index}{bay.shop}`, `Repair bay {bay.index}: get out (E) and wait. {Economy.repairTime(missingOf(car))} s, {money(feeFor(player, missingOf(car)))}.`)
			end
			continue
		end
		local wait = waiting[player]
		if not wait or wait.bay ~= bay then
			waiting[player] = { bay = bay, since = now }
		elseif now - wait.since >= Tuning.StandStill then
			waiting[player] = nil
			begin(player, car, bay)
		end
	end
end

function Repair.start()
	for _, bay in World.RepairBays do
		idle(bay)
	end
	Vehicles.beforeDrive = function(player: Player, car: Vehicles.Car)
		local job = running[player]
		if job and job.car == car then
			Repair.cancel(player, "You took the car back: repair cancelled, nothing to pay.")
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		local job = running[player]
		if job then
			release(player, job)
		end
		waiting[player] = nil
		told[player] = nil
		quiet[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(STEP)
			local ok, err = pcall(function()
				step()
			end)
			if not ok then
				warn(`[Repair] {err}`)
			end
		end
	end)
end

return Repair
