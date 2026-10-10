# Dovednosti za úrovně: návrh ke schválení (6.19)

Toto je jen návrh. Nic z něj zatím ve hře není. Od 6.19 odemykají zbraně a auta mise (viz README, 6.19). Úroveň proto
bude dávat dvě věci:
1. **Bod dovednosti za každou úroveň.** Úrovně 2 až 15 dají 14 bodů. Body utratíte ve stromu dovedností.
2. **Těžší a lépe placené zakázky.** Patří sem ★★, ★★★, ★★★★ a zaměstnavatelé. Ty už teď hlídá úroveň a tak to zůstane.

## Tři větve
Každý stupeň stojí 1 bod. Vrcholová dovednost stojí 3 body a otevře se, až máte ve stejné větvi aspoň 6 bodů.
Všechny dovednosti dohromady stojí 41 bodů, k dispozici je ale jen 14. Na úrovni 15 tedy vyplníte jednu větev
a kousek další, nebo body rozložíte do šířky. Volba má váhu.

| Větev | Dovednost | Stupně | Co dá každý stupeň (dnes → po posledním stupni) |
|---|---|---|---|
| 📦 **Kurýr** | Silná záda | 1 (2 body) | +1 kus v rukou i v batohu |
| | Dlouhý dech | 3 | sprint +1,5 s (dnes 6 s → 10,5 s) |
| | Úsměv u dveří | 3 | spropitné +5 % (+15 %) |
| | Lehký krok | 2 | rychlost sprintu +4 % (28 → 30,2) |
| | ★ Expres (vrchol) | 1 (3 body) | +10 % výplaty za zakázku doručenou v limitu |
| 🚐 **Řidič** | Tvrdá karoserie | 3 | auto dostane o 8 % menší poškození (−24 %) |
| | Rychlé ruce | 3 | nakládání a vykládání o 10 % rychleji (3 s → 2,1 s) |
| | Lehká noha | 3 | spotřeba paliva −7 % (−21 %) |
| | Známý v dílně | 2 | oprava u Wrench Garage −15 % (−30 %) |
| | ★ Kaskadér (vrchol) | 1 (3 body) | přejetí zombie autu neubere nic, náraz do auta o polovinu méně |
| 🥊 **Bojovník** | Tvrdá pěst | 3 | úder 12 → 15 → 18 → 21 |
| | Klidná ruka | 3 | přebíjení −10 %, zpětný ráz −15 % na stupeň |
| | Výdrž | 3 | +10 zdraví (100 → 130) |
| | Polní lékař | 2 | lékárnička léčí o 20 % rychleji a jednou za misi je zdarma |
| | ★ Druhý dech (vrchol) | 1 (3 body) | jednou za misi přežijete smrtelný zásah s 25 zdravími |

Čísla budou v `Config.Skills`. Ověří je server (`server/Skills.luau`), stejně jako dnes ceny. Klient si jen požádá.

## Přerozdělení bodů
- **Poprvé zdarma.** Hodí se, když se hráči první volba nelíbí.
- Potom za **$2 500 + $500 za každý utracený bod**. Při 14 bodech to dělá $9 500, tedy zhruba 3–4 zakázky ★★★.
- Přerozdělit nejde během zakázky ani mise.

## Kde to hráč uvidí
- **CAREER** dostane záložku **DOVEDNOSTI** v podobě UI kitu: nahoře hero karta s volnými body, pod ní tři sloupce větví.
- **Karta po postupu na úroveň** bude mít navíc řádek „+1 bod dovednosti · OTEVŘÍT“.
- **Domovská obrazovka telefonu:** čip CAREER ukáže tečku, dokud máte volný bod.

```
┌ CAREER ─────────────── [ROAD] [DOVEDNOSTI] ┐
│ ┌ HERO ─────────────────────────────────┐ │
│ │ ⭐ 3 VOLNÉ BODY      úroveň 7 · 6/14    │ │
│ │ [ PŘEROZDĚLIT · ZDARMA ]               │ │
│ └────────────────────────────────────────┘ │
│  📦 KURÝR 4      🚐 ŘIDIČ 2     🥊 BOJ 0    │
│  Silná záda ■   Karoserie ■□□  Pěst □□□    │
│  Dech ■■□       Ruce ■□□       Ruka □□□    │
│  Úsměv □□□      Noha □□□       Výdrž □□□   │
│  Krok □□        Dílna □□       Lékař □□    │
│  ★ Expres 🔒6   ★ Kaskadér 🔒6 ★ Dech 🔒6   │
│  (klepnutí → detail: co dá další stupeň, [+1 BOD])│
└────────────────────────────────────────────┘
```

## Co potřebujeme od vás
1. Souhlasíte se třemi větvemi a s čísly výše? Případně stačí napsat, co upravit.
2. Má být první přerozdělení zdarma a další za peníze?
3. Mají staré uložené hry dostat body zpětně podle své úrovně? Doporučujeme ano: kdo je na úrovni 9, dostane 8 bodů.
