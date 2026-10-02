--!strict
-- RemoteEvents. The server creates them on first require, the client waits for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"Buy", -- client → server: summon soldiers at an altar (1 = the basic altar, "better" = the better summoner)
	"Battle", -- client → server: Q pressed, start the battle
	"Interact", -- client → server: a soldier was dragged from one pad onto another (from, to)
	"Equip", -- client → server: equip a soldier from the inventory into the battle squad (slot id)
	"Unequip", -- client → server: move a squad soldier back to the inventory (squad slot id)
	"RollResult", -- server → client: play the UI roll (pool of classes, the classes it lands on, their level)
	"AutoMerge", -- client → server: merge every possible pair on the merge board
	"EquipBest", -- client → server: put the strongest soldiers into the battle squad
	"UpgradeLevel", -- client → server: buy the next start level for bought soldiers (only at the lobby station)
	"UnlockTier", -- client → server: buy the next merge level of one soldier class (class name)
	"AdminProgress", -- client → server: admin only, +1 wave and coins
	"AdminUnlock", -- client → server: admin only, unlocks everything
	"AdminReset", -- client → server: admin only, wipes the whole progress
	"AdminCommand", -- client → server: admin only, the test tools (command, a, b): coins, wave, spawn, spawnall, clear, slots, startlevel
	"BossIntro", -- server → client: a boss wave starts (boss name)
	"BossHp", -- server → client: the boss health bar (name, fraction of health, enraged); fraction 0 hides it
	"WaveIntro", -- server → client: the wave's twists banner + chips ({ title, subtitle, color = {r,g,b}, chips = { { label, subtitle, color } } }) or nil to clear
	"AutoFight", -- client → server: turn auto fight on / off (starts the next wave by itself)
	"Sell", -- client → server: sell a soldier of the inventory / squad for coins (slot id)
	"BattleSpeed", -- client → server: cycle the battle speed (1x / 2x)
	"Sfx", -- server → client: play a sound (name of Config/Sounds)
	"SetSetting", -- client → server: change a setting (key, value)
	"WelcomeBack", -- server → client: the offline-income popup (coins, hours)
	"Upgrade", -- client → server: R pressed, unlock more merge slots
	"SetWave", -- client → server: choose the wave to fight / repeat (only inside the arena)
	"SetDifficulty", -- client → server: choose the difficulty (only inside the arena)
	"Notice", -- server → client: short message (text)
	"Countdown", -- server → client: 3, 2, 1, 0 before the battle starts (0 = FIGHT!)
	"WaveResult", -- server → client: result screen (drop, lucky drop) or defeat
	"CollectDrops", -- client → server: the drop cards landed in the inventory panel, deliver them
	"CoinDrop", -- server → client: XP orbs dropped by a kill (list of {id, value}, position, bonus multiplier)
	"CollectCoin", -- client → server: an XP orb was picked up (id)
	"CoinsClear", -- server → client: every XP orb on the ground was given, make them fly away
	"RequestState", -- client → server: asks for the bottom-bar state after loading
	"State", -- server → client: coins, cost, wave, rolling, battling, timings
}

local folder: Folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local Net = {}

function Net.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Net
