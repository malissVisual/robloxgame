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

	-- Pohyb: drží si 70–85 % dosahu základního kouzla; couvá šikmo (ne rovně dozadu).
	OptimalRange = { 0.7, 0.85 },
	KiteDistance = 8, -- nepřítel blíž než tohle je nebezpečný
	StrafeAngle = 50, -- stupně odchylky od směru „přímo pryč“
	ArenaMargin = 3, -- studů od okraje plošiny, kam mág nevkročí
	SurroundedCount = 2, -- tolik nepřátel do KiteDistance = obklíčení (blink)
	RetreatBurst = 0.8, -- sekund couvání v jedné dávce …
	RetreatPause = 1.5, -- … a pak tolik sekund raději střílí, i když je nepřítel blízko (není-li HP pod 40 %)

	-- Zdroje.
	Mana = { Max = 100, Start = 60, Regen = 9 }, -- regenerace za sekundu bitvy

	-- Paměť.
	TargetHold = 1.5, -- sekundy, po které drží cíl, pokud se neobjeví výrazně lepší
	SwitchMargin = 0.25, -- o kolik musí být nový cíl lepší, aby přepnul dřív
	HateGain = 1.0, -- kolik „nenávisti“ přidá zásah od nepřítele
	HateDecay = 0.35, -- za sekundu

	-- Výběr cíle: váhy složek skóre (blízkost, nízké HP, hrozba, typ nepřítele).
	Target = { Proximity = 0.35, LowHp = 0.3, Hate = 0.25, Type = 0.2 },
	TypePriority = { Archer = 1.0, Shaman = 0.9, Chief = 0.5, RiftKing = 0.6, Grunt = 0.4, Brute = 0.2 },

	-- Utility: základní hodnoty akcí (a bonusy), výsledek se ořízne na 0–1.
	Utility = {
		Inertia = 0.1, -- bonus pro právě prováděnou akci (proti přeskakování)
		AttackBase = 0.55,
		StrongPerEnemy = 0.2, -- AoE: za každého nepřítele ve shluku (od dvou)
		StrongFinish = 0.7, -- silné kouzlo na cíl, kterého dorazí
		RetreatBase = 0.6,
		HazardRetreat = 0.95, -- stojí v telegrafované AoE nepřítele
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
