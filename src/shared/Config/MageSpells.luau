--!strict
-- Kouzla mága podle epochy (Era) a levelu. Každé kouzlo: druh (kind), cena many, cooldown, čas castu, násobek
-- poškození (× útok mága), poloměr a barvy. MageBrain je sesílá; MageSpells.forLevel(level) říká, která má mág
-- k dispozici: level 1–10 jedno až dvě, 11–20 tři, 21–30 čtyři plus podporu (léčení).
--   bolt    základní střela na jeden cíl (ohnivá koule mága, splash přes jeho pasivku)
--   aoe     plošné kouzlo do těžiště skupiny (volitelně zpomalení)
--   chain   řetěz: cíl a pak další nepřátelé v okolí
--   shield  bariéra: mág bere méně poškození
--   heal    podpora: vyléčí spojence s nejnižším HP
--   blink   teleport: skok do bezpečí
--   pull    singularita: stáhne nepřátele k bodu a zraní je
--   repel   odražení: nepřátelé kolem mága odletí o `push` studů, krátce omráčení (mág se nehýbe, hýbou se ONI)

export type Spell = {
	id: string,
	label: string,
	era: number, -- 1 pravěk … 6 budoucnost
	minLevel: number,
	kind: string,
	basic: boolean?, -- základní útok epochy (bez many)
	mana: number,
	cooldown: number,
	castTime: number,
	damage: number, -- × útok mága (0 u podpory)
	radius: number?, -- aoe / pull / heal
	range: number?, -- vlastní dosah (jinak dosah mága)
	slow: { factor: number, time: number }?,
	shield: { reduction: number, time: number }?,
	heal: number?, -- část max HP spojence
	jumps: number?, -- chain
	blink: number?, -- studů
	pull: number?, -- studů stažení
	push: number?, -- repel: studů odhození
	stun: number?, -- repel: sekund omráčení
	allyCast: boolean?, -- shield: lze seslat i na spojence (reakce Strážce)
	interrupt: boolean?, -- (nastavuje brain na castu) protikouzlo: přeruší cast cíle
	color: Color3,
	color2: Color3,
}

local C = Color3.fromRGB
local PURPLE, INDIGO = C(190, 110, 255), C(90, 60, 200)
local WHITE, AZURE = C(240, 245, 255), C(100, 220, 255)

local MageSpells = {}

MageSpells.Defs = {
	-- PRAVĚK
	{ id = "fireStone", label = "Ohnivý kámen", era = 1, minLevel = 1, kind = "bolt", basic = true, mana = 0, cooldown = 0, castTime = 0.4, damage = 1.0, color = C(255, 140, 60), color2 = C(255, 220, 140) },
	{ id = "sparkSwarm", label = "Roj jisker", era = 1, minLevel = 3, kind = "aoe", mana = 35, cooldown = 7, castTime = 0.7, damage = 1.3, radius = 5, color = C(255, 180, 80), color2 = C(255, 240, 170) },
	{ id = "healingLight", label = "Léčivé světlo", era = 1, minLevel = 2, kind = "heal", mana = 40, cooldown = 14, castTime = 0.5, damage = 0, heal = 0.3, radius = 30, color = C(120, 255, 170), color2 = WHITE }, -- the old player's Heal, now the Mage's from level 2
	{ id = "arcanePush", label = "Arkánový úder", era = 1, minLevel = 5, kind = "repel", mana = 30, cooldown = 10, castTime = 0.35, damage = 0.6, radius = 7, push = 8, stun = 0.6, color = PURPLE, color2 = WHITE },
	-- STAROVĚK
	{ id = "sunRay", label = "Sluneční paprsek", era = 2, minLevel = 6, kind = "bolt", basic = true, mana = 0, cooldown = 0, castTime = 0.35, damage = 1.05, color = C(255, 210, 90), color2 = WHITE },
	{ id = "sandstorm", label = "Písečná bouře", era = 2, minLevel = 8, kind = "aoe", mana = 40, cooldown = 8, castTime = 0.8, damage = 1.2, radius = 7, slow = { factor = 0.6, time = 2.5 }, color = C(230, 190, 110), color2 = C(255, 235, 190) },
	-- STŘEDOVĚK
	{ id = "magicMissile", label = "Magická střela", era = 3, minLevel = 11, kind = "bolt", basic = true, mana = 0, cooldown = 0, castTime = 0.32, damage = 1.1, color = PURPLE, color2 = C(235, 205, 255) },
	{ id = "chainLightning", label = "Řetězový blesk", era = 3, minLevel = 12, kind = "chain", mana = 35, cooldown = 7, castTime = 0.6, damage = 0.9, jumps = 3, radius = 9, color = C(170, 200, 255), color2 = WHITE },
	{ id = "iceBarrier", label = "Ledová bariéra", era = 3, minLevel = 14, kind = "shield", mana = 30, cooldown = 12, castTime = 0.3, damage = 0, shield = { reduction = 0.5, time = 3 }, allyCast = true, color = C(150, 220, 255), color2 = WHITE },
	-- PRŮMYSLOVÝ VĚK
	{ id = "arcBolt", label = "Elektrická střela", era = 4, minLevel = 16, kind = "bolt", basic = true, mana = 0, cooldown = 0, castTime = 0.3, damage = 1.15, color = C(120, 200, 255), color2 = WHITE },
	{ id = "steamBlast", label = "Parní exploze", era = 4, minLevel = 17, kind = "aoe", mana = 45, cooldown = 8, castTime = 0.8, damage = 1.8, radius = 6, color = C(220, 220, 230), color2 = C(255, 170, 90) },
	{ id = "electricArc", label = "Elektrický oblouk", era = 4, minLevel = 19, kind = "chain", mana = 40, cooldown = 7, castTime = 0.55, damage = 1.0, jumps = 4, radius = 10, color = C(140, 220, 255), color2 = WHITE },
	{ id = "shockwave", label = "Rázová vlna", era = 4, minLevel = 18, kind = "repel", mana = 30, cooldown = 10, castTime = 0.3, damage = 0.7, radius = 8, push = 9, stun = 0.6, color = C(220, 220, 230), color2 = C(255, 170, 90) },
	{ id = "insulation", label = "Izolační pole", era = 4, minLevel = 18, kind = "shield", mana = 30, cooldown = 12, castTime = 0.3, damage = 0, shield = { reduction = 0.5, time = 3 }, allyCast = true, color = C(255, 200, 90), color2 = WHITE },
	-- MODERNÍ DOBA
	{ id = "plasmaBeam", label = "Plazmový paprsek", era = 5, minLevel = 21, kind = "bolt", basic = true, mana = 0, cooldown = 0, castTime = 0.28, damage = 1.2, color = C(120, 255, 220), color2 = WHITE },
	{ id = "empSlow", label = "EMP zpomalení", era = 5, minLevel = 22, kind = "aoe", mana = 40, cooldown = 9, castTime = 0.7, damage = 1.0, radius = 8, slow = { factor = 0.5, time = 2.5 }, color = C(120, 200, 255), color2 = WHITE },
	{ id = "medDrone", label = "Dron-strážce", era = 5, minLevel = 21, kind = "heal", mana = 40, cooldown = 10, castTime = 0.5, damage = 0, heal = 0.2, radius = 30, color = C(120, 255, 170), color2 = WHITE },
	{ id = "energyShield", label = "Energetický štít", era = 5, minLevel = 23, kind = "shield", mana = 30, cooldown = 12, castTime = 0.25, damage = 0, shield = { reduction = 0.55, time = 3 }, allyCast = true, color = C(120, 220, 255), color2 = WHITE },
	-- BUDOUCNOST
	{ id = "quantumBolt", label = "Kvantová střela", era = 6, minLevel = 26, kind = "bolt", basic = true, mana = 0, cooldown = 0, castTime = 0.25, damage = 1.3, color = AZURE, color2 = WHITE },
	{ id = "quantumBlink", label = "Kvantový teleport", era = 6, minLevel = 26, kind = "blink", mana = 25, cooldown = 10, castTime = 0.15, damage = 0, blink = 14, color = AZURE, color2 = WHITE },
	{ id = "singularity", label = "Gravitační singularita", era = 6, minLevel = 27, kind = "pull", mana = 60, cooldown = 12, castTime = 0.9, damage = 1.5, radius = 10, pull = 6, color = INDIGO, color2 = C(200, 160, 255) },
	{ id = "starRain", label = "Hvězdný déšť", era = 6, minLevel = 29, kind = "aoe", mana = 70, cooldown = 14, castTime = 1.0, damage = 2.2, radius = 9, color = WHITE, color2 = AZURE },
	{ id = "nanoHeal", label = "Nanoléčení", era = 6, minLevel = 28, kind = "heal", mana = 45, cooldown = 10, castTime = 0.4, damage = 0, heal = 0.3, radius = 30, color = C(160, 255, 230), color2 = WHITE },
} :: { Spell }

-- Epocha levelu (1 … 6).
function MageSpells.era(level: number): number
	return math.clamp(math.ceil(level / 5), 1, 6)
end

-- Kouzla, která má mág daného levelu: základní útok své epochy a nejnovější odemčená silná kouzla
-- (1–10: celkem 2, 11–20: 3, 21–30: 4) plus nejnovější odražení (repel, od levelu 5) a nejnovější kouzlo podpory
-- (léčení, od levelu 2 — hráč už kouzla nemá, léčí mág) — ty dvě mimo strop silných kouzel. Vrací (základní, ostatní).
function MageSpells.forLevel(level: number): (Spell, { Spell })
	local era = MageSpells.era(level)
	local basic: Spell? = nil
	local others: { Spell } = {}
	local support: { Spell } = {}
	local repel: Spell? = nil
	for _, spell in MageSpells.Defs do
		if spell.minLevel > level then
			continue
		end
		if spell.basic then
			if spell.era <= era and (not basic or spell.era > (basic :: Spell).era) then
				basic = spell
			end
		elseif spell.kind == "heal" then
			table.insert(support, spell)
		elseif spell.kind == "repel" then
			if not repel or spell.minLevel > (repel :: Spell).minLevel then
				repel = spell
			end
		else
			table.insert(others, spell)
		end
	end
	-- Nejnovější kouzla první (vyšší minLevel), ponechat tolik, kolik level dovolí.
	table.sort(others, function(a, b)
		return a.minLevel > b.minLevel
	end)
	local count = if level <= 10 then 1 elseif level <= 20 then 2 else 3
	while #others > count do
		table.remove(others)
	end
	if repel then
		table.insert(others, repel)
	end
	table.sort(support, function(a, b)
		return a.minLevel > b.minLevel
	end)
	if support[1] then
		table.insert(others, support[1])
	end
	return basic :: Spell, others
end

return MageSpells
