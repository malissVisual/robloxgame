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

	-- Pohyb: mág STOJÍ a střílí, kdykoli má někoho v dosahu. Jde dopředu jen, když nemá nikoho, a zastaví v okamžiku,
	-- kdy nejbližšího nepřítele v dosahu má. Necouvá; z telegrafované plochy nepřítele vystoupí.
	ArenaMargin = 3, -- studů od okraje plošiny, kam mág nevkročí
	HazardExit = 2, -- o kolik studů za okraj telegrafované plochy mág vystoupí …
	HazardExitLong = 4, -- … a u trvalých ploch (louže, kind "puddle"), aby se k nim hned nevracel
	HazardHold = 0.5, -- sekund stojí po vystoupení z plochy (žádné „tam a zpátky“ mezi útěkem a přiblížením)
	HazardLookahead = 2, -- studů před sebou mág kontroluje plochu při chůzi a obchází ji kolmo
	SurroundDistance = 6, -- nepřátelé do této vzdálenosti se počítají jako obklíčení …
	SurroundedCount = 2, -- … a od tolika mág blinkne pryč (má-li teleport)

	-- Zdroje.
	Mana = { Max = 100, Start = 70, Regen = 11 }, -- regenerace za sekundu bitvy
	-- TRACKING: the mage always turns to its target (or the nearest enemy) smoothly, at most TurnRate rad/s, also
	-- while it waits, recovers or stands far away; the body never snaps around.
	TurnRate = 8,
	-- GLIDE: a mage moves like a mage. While it walks it floats up Height studs, leans Lean radians into the motion
	-- and bobs (Bob studs, BobSpeed rad/s); a few arcane sparks trail under it every SparkEvery seconds. Time = the
	-- seconds it takes to lift off / settle down. (Rig plays no run animation for a gliding rig.)
	Glide = { Height = 0.7, Lean = 0.14, Bob = 0.12, BobSpeed = 6, Time = 0.25, SparkEvery = 0.2 },

	-- Paměť.
	TargetHold = 1.5, -- sekundy, po které drží cíl, pokud se neobjeví výrazně lepší
	SwitchMargin = 0.25, -- o kolik musí být nový cíl lepší, aby přepnul dřív
	HateGain = 1.0, -- kolik „nenávisti“ přidá zásah od nepřítele
	HateDecay = 0.35, -- za sekundu

	-- Výběr cíle: váhy složek skóre (blízkost, nízké HP, hrozba, typ nepřítele).
	Target = { InRange = 0.5, Proximity = 0.35, LowHp = 0.3, Hate = 0.25, Type = 0.2, Casting = 0.5 }, -- InRange: co už je v dosahu, má přednost; Casting: nepřítel právě sesílá (ai.state == "windup")
	TypePriority = { Archer = 1.0, Shaman = 0.9, Chief = 0.5, RiftKing = 0.6, Grunt = 0.4, Brute = 0.2, Totem = 1.1, Treasure = 1.2 },
	ChampionBonus = 0.3, -- bonus skóre cíle pro šampiona vlny (fighter.champion)

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
		Repel = 0.9, -- obklíčený a má odražení (repel): odhodí nepřátele místo toho, aby sám utíkal
	},

	-- Telegraf před silným kouzlem (hráč pozná, že mág něco chystá).
	Telegraph = { Brightness = 2.5, Range = 1.6, Scale = 1.25 },
	-- Zvednutí paže s holí (otočení ramenního kloubu) při castu.
	ArmRaise = 80, -- stupně dopředu
	-- Předstih střelby na pohybující se cíl (násobek rychlosti × čas castu) a jeho chyba.
	Lead = { Factor = 1.0, Error = 1.5 },

	-- REAKCE: mág má jeden „reakční slot“ a schránku událostí (zásah, zabití, pád spojence, nabíhající Brute, cast
	-- šamana, poslední nepřítel, kouzlo hráče…). Emotivní reakce se spustí hned, DOVEDNOSTNÍ (hop, podražení,
	-- protikouzlo, strážce, kombo) až po reakční době podle levelu (ReactionTime), takže level je vidět.
	-- Barvy: fialová = cast, červená = bolest/vztek, zlatá = ochrana, bílá = poprava/přerušení, oranžová = nebezpečí
	-- zblízka, azurová = kombo.
	Reactions = {
		PopRate = 0.8, -- sekund mezi dvěma textovými „popy“ jednoho mága (výstražné „!“ limit obchází)
		PopsPerTick = 6, -- strop popů za tick bitvy (BattleFx)
		SkillDelay = true, -- dovednostní reakce čekají reakční dobu levelu
		ChipFraction = 0.05, -- zásah bez útočníka (louže, bouře) pod tímto zlomkem max HP je jen „oděrka“: žádný Fury ani škubnutí
		Flinch = { Cooldown = 2, Duration = 0.25, SnapShot = 0.3 }, -- škubnutí po zásahu; SnapShot = o kolik se zkrátí čekání na další střelu
		Fury = { PerHit = 12, PerKill = 20, PerMultiKill = 15, PerAllyHurt = 8, Decay = 6, DecayDelay = 3, Max = 100 },
		Overcharge = { Duration = 6, CooldownFactor = 0.6, CastFactor = 0.7, ManaFactor = 0.5, Hover = 1.2, HoverTime = 0.3, RuneCount = 3, RuneRadius = 2.6, RuneSpin = 180, EndRing = 8 },
		Avenger = { Duration = 0.6, HateBonus = 3, DamageBonus = 0.5, MarkTime = 4, Ring = 8 }, -- padl spojenec: označí vraha
		Guardian = { AllyBelow = 0.4, Range = 14, Reduction = 0.25, Time = 2, Cooldown = 10, MinLevel = 5, CastTime = 0.4 }, -- ochrana zraněného spojence
		ChargeAlert = { HopDistance = 5, HopTime = 0.25, HopCooldown = 8, HopMinLevel = 8, HopTrigger = 3, HopRecover = 0.3, Afterimages = 3, TripMult = 0.5, TripSlow = 0.5, TripTime = 1.2, TripCooldown = 5, AllyTrigger = 4 },
		Counter = { Cooldown = 6, CastTime = 0.15, ExtraRange = 3 }, -- protikouzlo na cast šamana / léčení bosse
		LastStand = { Below = 0.3, Duration = 4, Reduction = 0.5, FuryBonus = 40 },
		-- BLINK DODGE: a melee enemy (range <= MeleeRange) gets within Trigger studs → the mage teleports away, to the
		-- spot around it that is farthest from every enemy, preferring the OTHER side of the attacker, still within
		-- shooting range; it lands looking back at the attacker. Cooldown from CooldownLow (level 1) to CooldownTop
		-- (level 16). The knockback (repel) answers first when it is ready.
		BlinkDodge = { MinLevel = 1, Trigger = 5.5, MeleeRange = 6, Distance = 11, CooldownLow = 9, CooldownTop = 4, Recover = 0.25, OtherSide = 4, OutOfRange = 6 },
		Finish = { Below = 0.35, Mult = 1.5, CastTime = 0.5, Scale = 1.6 }, -- poprava posledního nepřítele
		Combo = { Window = 1.5, Bonus = 0.25, ShatterMin = 2, ShatterBonus = 0.3 }, -- kombo s kouzlem hráče / rozbití zpomalených
		MultiKillWindow = 0.5,
		Fidget = { 3, 5 }, -- sekund mezi dvěma gesty, když se nic neděje
		Salute = 0.6, -- pozdrav na začátku bitvy (zvednutí hole)
		Victory = 1.2, -- vítězná póza
		Priority = { lastStand = 10, avenger = 9, chargeAlert = 8, counter = 7, guardian = 6, combo = 5, finish = 4, flinch = 3, flourish = 2, fidget = 1 },
	},

	-- Krátké hlášky nad hlavou (anglicky, aby seděly ke zbytku UI); vybírá se náhodně z variant.
	Lines = {
		kill = { "HA!", "NEXT.", "TOO SLOW" },
		dodge = { "NOPE.", "MISSED!", "OVER HERE!" },
		hit = { "OW!", "RUDE." },
		allyHurt = { "HOLD ON!" },
		allyDown = { "NO!" },
		hop = { "NOPE." },
		counter = { "SILENCED!" },
		finish = { "FINISH!" },
		lastStand = { "LAST STAND!" },
		overcharge = { "OVERCHARGE!" },
		combo = { "COMBO!" },
		shatter = { "SHATTER!" },
		repel = { "BACK!" },
		multi = { "DOUBLE!", "TRIPLE!" },
		victory = { "EASY.", "WHO'S NEXT?" },
		ambush = { "BEHIND US!" },
		reinforcements = { "MORE OF THEM!", "HERE THEY COME!" },
		champion = { "BIG ONE." },
		treasure = { "GET HIM!" },
	},
}

return MageConfig
