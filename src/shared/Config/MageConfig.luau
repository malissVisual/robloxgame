--!strict
-- Všechna laditelná čísla bojové AI mága (server/Services/MageBrain.luau). Kouzla jsou v MageSpells.luau.
-- Mág přemýšlí každých ThinkInterval sekund (s náhodným posunem, aby nemysleli všichni ve stejný tick),
-- každou možnou akci ohodnotí skóre 0–1 (utility AI) a provede tu nejlepší; pohyb a efekty běží každý tick.

local MageConfig = {
	Debug = false, -- BillboardGui nad hlavou s akcí, cílem a skóre; za běhu i workspace:SetAttribute("MageDebug", true)

	ThinkInterval = { 0.2, 0.4 }, -- sekundy bitvy mezi dvěma rozhodnutími (náhodně v rozsahu)
	-- Reakční doba na novou situaci (přepnutí cíle, nová hrozba): lineárně od levelu 1 k levelu 30.
	ReactionTime = { L1 = 0.6, L30 = 0.15 },
	-- Pravděpodobnost „lidské“ chyby při rozhodnutí: zaváhání nebo mírně vedle mířené AoE. Klesá s levelem.
	MistakeChance = { L1 = 0.18, L30 = 0.02 },
	Hesitation = { 0.3, 0.6 }, -- jak dlouho zaváhání trvá (sekundy)
	AimError = 2.5, -- studů vedle u chybně mířeného AoE (násobeno 1 - level/30)

	-- Pohyb: mág STOJÍ a střílí, kdykoli má někoho v dosahu. Jde dopředu jen, když nemá nikoho, a zastaví, jakmile
	-- má nejbližšího nepřítele v StopAtRange × dosah. Necouvá; z telegrafované plochy nepřítele vystoupí.
	StopAtRange = 0.85,
	ArenaMargin = 3, -- studů od okraje plošiny, kam mág nevkročí
	SurroundDistance = 6, -- nepřátelé do této vzdálenosti se počítají jako obklíčení …
	SurroundedCount = 2, -- … a od tolika mág blinkne pryč (má-li teleport)

	-- Zdroje.
	Mana = { Max = 100, Start = 60, Regen = 9 }, -- regenerace za sekundu bitvy

	-- Paměť.
	TargetHold = 1.5, -- sekundy, po které drží cíl, pokud se neobjeví výrazně lepší
	SwitchMargin = 0.25, -- o kolik musí být nový cíl lepší, aby přepnul dřív
	HateGain = 1.0, -- kolik „nenávisti“ přidá zásah od nepřítele
	HateDecay = 0.35, -- za sekundu

	-- Výběr cíle: váhy složek skóre (blízkost, nízké HP, hrozba, typ nepřítele).
	Target = { InRange = 0.5, Proximity = 0.35, LowHp = 0.3, Hate = 0.25, Type = 0.2 }, -- InRange: co už je v dosahu, má přednost
	TypePriority = { Archer = 1.0, Shaman = 0.9, Chief = 0.5, RiftKing = 0.6, Grunt = 0.4, Brute = 0.2 },

	-- Utility: základní hodnoty akcí (a bonusy), výsledek se ořízne na 0–1.
	Utility = {
		Inertia = 0.1, -- bonus pro právě prováděnou akci (proti přeskakování)
		AttackBase = 0.55,
		StrongPerEnemy = 0.2, -- AoE: za každého nepřítele ve shluku (od dvou)
		StrongFinish = 0.7, -- silné kouzlo na cíl, kterého dorazí
		HazardEscape = 0.95, -- stojí v telegrafované AoE nepřítele → ven
		ShieldBelowHp = 0.35,
		ShieldScore = 0.8,
		BlinkScore = 0.85,
		SupportBelowHp = 0.45,
		SupportBase = 0.5,
		ApproachBase = 0.5,
		IdleScore = 0.15,
	},

	-- Telegraf před silným kouzlem (hráč pozná, že mág něco chystá).
	Telegraph = { Brightness = 2.5, Range = 1.6, Scale = 1.25 },
	-- Zvednutí paže s holí (otočení ramenního kloubu) při castu.
	ArmRaise = 80, -- stupně dopředu
	-- Předstih střelby na pohybující se cíl (násobek rychlosti × čas castu) a jeho chyba.
	Lead = { Factor = 1.0, Error = 1.5 },
}

return MageConfig
