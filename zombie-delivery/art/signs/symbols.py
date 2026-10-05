"""Original vector mascots for Zombie Delivery signs (160 x 160 view box)."""

def draw(kind, p):
    ink, paper = p['ink'], p['paper']
    sage, coral, lilac, blue, teal = (p[k] for k in ('sage', 'coral', 'lavender', 'blue', 'teal'))
    def path(d, fill='none', sw=7):
        return f'<path d="{d}" fill="{fill}" stroke-width="{sw}"/>'
    def rect(x,y,w,h,fill,rx=5,sw=7):
        return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke-width="{sw}"/>'
    def circle(x,y,r,fill,sw=7):
        return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke-width="{sw}"/>'
    def eyes(x=70,y=85):
        return circle(x,y,3,ink,0)+circle(x+18,y,3,ink,0)+path(f'M{x+1} {y+13}q8 9 16 0',sw=4)
    def skull(x=80,y=89):
        return circle(x,y,13,paper,0)+rect(x-8,y+8,16,10,paper,0,0)+circle(x-5,y,3,ink,0)+circle(x+5,y,3,ink,0)
    if kind == 'parcel':
        art = path('M22 91 79 69l58 23v50l-58 15-57-19Z',lilac)
        art += path('M79 69v88M22 91l57 19 58-18')
        art += path('M51 78 46 63l-7-14q-4-9 2-11t12 10l5 4-3-29q-1-10 6-10t9 11l3 20 5-26q2-9 9-7t5 12l-3 22 11-16q6-8 11-3t-1 14l-12 20 15-6q9-2 10 5t-16 18l-9 18Z',sage,6)
        art += rect(33,108,28,25,paper,1,3)+path('M39 114h15m-15 6h11m-11 6h15',sw=3)
        art += path('M97 125v-11m-5 5 5-5 5 5m13 3v-11m-5 5 5-5 5 5',sw=4)
    elif kind == 'van':
        art = path('M12 46h91l40 39v46H12Z',paper)
        art += path('M103 46v48h40M12 100h131',coral,6)
        art += path('M108 57v29h25Z',blue,5)+rect(23,59,46,24,blue,2,5)
        art += rect(24,108,24,12,coral,2,0)+rect(126,104,13,13,sage,1,3)
        art += circle(43,129,18,ink,4)+circle(43,129,8,lilac,0)+circle(119,129,18,ink,4)+circle(119,129,8,lilac,0)
        art += skull(83,70)+path('M8 128q-11 1-6 10m71-28 9 4',sw=4)
    elif kind == 'ammo':
        art = ''
        for x,y in [(30,18),(65,8),(100,25)]:
            art += path(f'M{x} {y+55}V{y+20}q10-35 20 0v35Z',paper,5)
            art += path(f'M{x} {y+20}h20',coral,4)
        art += path('M15 77 52 65l88 12-9 68-84 9-32-13Z',sage)
        art += path('M47 83v68M15 77l32 8 93-8',sw=5)+skull(87,111)
        art += path('M23 105h12m-13 9h13',sw=4)
    elif kind == 'wrench':
        art = path('M73 21q-33 8-30 37l8 18-29 63q-5 16 9 17t21-10l24-64q34-1 43-36l-21 16-22-9-5-17 2-15Z',paper)
        art += path('M46 123l-10 23',sw=5)+eyes(66,61)
        art += path('M52 23 57 8l40 4 11 25-19-3-24-3Z',lilac,5)
        art += path('M128 115v-15q0-9 9-8t8 11l-1 8 10 5v29l-26 6-18-6v-20Z',sage,5)
        art += path('M8 66l12 5m103-45 9-10',sw=4)
    elif kind == 'supplies':
        art = rect(30,60,100,81,sage,8)+rect(41,23,76,32,teal,14,5)
        art += path('M56 26q-5 14 0 26m-12 32 71 47m-5-47-66 47',p['tape'],10)
        art += rect(3,95,49,51,paper,5,5)+path('M18 105h20v10H28v20H18v-20H8v-10Z',ink,0)
        art += path('M128 85h18v61h-28V99l10-5Z',coral,5)+path('M126 108l12 24m0-24-12 24',sw=4)
    elif kind == 'bridge':
        art = path('M8 85h144v45H8Z',paper,5)+path('M17 75V37m126 38V37M17 47l32 38 31-38 32 38 31-38',sw=7)
        art += path('M6 138q18-15 36 0t36 0t36 0t40 0',blue,5)
        art += path('M62 94h36l7 20-27 8-22-7Z',sage,4)+path('M71 99l15 12',sw=5)
    elif kind == 'parking':
        art = rect(29,22,102,117,paper,17)+path('M59 116V46h25q31 0 31 25T84 96H59',teal,12)
        art += path('M39 144h86',sw=6)
    elif kind == 'anchor':
        art = circle(80,30,15,paper,6)+path('M80 45v95M49 72h62M19 106q8 35 61 36 53-1 61-36',sw=10)
        art += path('M16 118l3-20 20 7m85 0 17-7 4 20',paper,6)
        art += path('M14 150q17-9 33 0t32 0t32 0t32 0',blue,4)
    elif kind == 'sun':
        art = circle(80,80,40,paper)+eyes(70,75)
        for d in ['M80 7v15','M80 138v15','M7 80h15','M138 80h15','M29 29l11 11','M120 120l11 11','M29 131l11-11','M120 40l11-11']:
            art += path(d,sw=6)
    elif kind == 'helmet':
        art = path('M24 94q0-71 56-71t56 71l12 7H12Z',sage)+path('M78 27v62M30 101l7 30 43 14 43-14 7-30',paper,5)
        art += path('m80 41 5 12h13l-11 8 4 13-11-8-11 8 4-13-11-8h13Z',paper,3)
    elif kind == 'icecream':
        art = path('M44 76h73L80 151Z',paper)+path('M52 84l48 37m-4-37-35 36',sw=3)
        art += path('M36 76q-16-28 6-38 3-27 29-26 31-9 42 20 30-1 28 26 11 18-13 28H46Z',coral,6)
        art += eyes(71,48)+path('M39 88h91',sw=5)
    elif kind in ('moving','crates'):
        art = rect(49,25,75,67,paper,2,5)+rect(18,82,76,64,lilac,2,5)+rect(98,94,47,52,sage,2,5)
        art += path('M75 29v25h22V29M43 87v21h23V87m46 15v18h19v-18',sw=4)
        if kind == 'moving':
            art += path('M2 53h38m-11-10 11 10-11 10',coral,6)
    elif kind == 'corn':
        art = path('M47 111q-12-66 25-87 34-3 40 68l-28 49Z',paper,6)
        art += path('M28 60q-7 86 61 89-2-58-61-89Z',sage,6)+path('M130 55q9 67-44 94 1-64 44-94Z',sage,6)
        art += path('M71 35v31m17-35 4 44M63 46h36M59 59h43',sw=3)
    elif kind == 'horse':
        art = path('M103 12 80 22 62 59 34 68 14 95l18 25 39-5 13 36h48l-18-41 17-42-4-39-16 9Z',paper,6)
        art += path('M92 23l-14 17 9 12-11 16 11 9-5 30',teal,8)+circle(109,59,4,ink,0)
        art += path('M28 91l19 3m-19 14 40-4 12-31',sw=5)
    elif kind in ('medical','pills'):
        art = rect(23,35,114,112,paper,14)+path('M58 35V17h44v18',sw=7)
        if kind == 'medical':
            art += path('M66 57h28v22h22v28H94v22H66v-22H44V79h22Z',coral,0)
        else:
            art += path('M48 110q-20-20 0-40l16-16q20-20 40 0t0 40l-16 16q-20 20-40 0Z',coral,5)+path('M54 64l40 40',paper,5)
    elif kind == 'pump':
        art = rect(25,24,76,116,paper,10)+rect(35,37,56,37,blue,4,5)
        art += path('M101 58h16q13 0 13 16v50q0 15 16 7V51l-19-17',sw=7)
        art += path('M56 84q-26 34 5 40 28-6-5-40Z',coral,4)+path('M16 147h94',sw=7)
    elif kind in ('bank','hall'):
        art = path('M15 60 80 16l65 44Z',paper,6)+rect(14,130,132,17,paper,2,5)
        for x in (30,71,112): art += rect(x,68,17,62,lilac,2,4)
        art += circle(80,44,11,sage,3)
        if kind == 'hall': art += path('M80 16V2h30l-4 9H80',coral,3)
    elif kind == 'basket':
        art = path('M14 66h132l-15 73H31Z',sage,6)+path('M47 65l22-40m44 40L91 25',sw=7)
        art += path('M51 85v35m29-35v35m29-35v35',sw=5)+path('M48 56q5-37 30-24 24-27 37 11',paper,5)
    elif kind == 'fire':
        art = path('M79 7q7 39-30 62 6-25-11-33-24 37-15 67 8 44 59 44 46-1 56-42 11-27-12-60-2 35-19 27 4-36-28-65Z',coral,6)
        art += path('M81 67q-33 43-13 56 23 15 35-5 13-13-22-51Z',paper,4)
    elif kind == 'badge':
        art = path('m80 12 20 40 44-4-20 35 22 34-45-1-21 35-20-35-44 1 21-34-20-35 43 4Z',paper,6)
        art += circle(80,84,26,blue,5)+path('M62 85l13 13 26-31',sw=6)
    elif kind == 'tower':
        art = path('M32 147V42l48-26 48 26v105Z',paper,6)+path('M80 16v131',sw=5)
        for y in (52,76,100): art += rect(45,y,19,12,blue,1,0)+rect(94,y,19,12,lilac,1,0)
        art += rect(63,122,34,25,teal,2,4)+path('M16 147h128',sw=6)
    elif kind == 'barrel':
        art = rect(40,18,81,132,paper,11)+path('M40 50h81m-81 66h81',sw=9)
        art += path('M81 61q-38 41-2 47 36-2 2-47Z',coral,4)
    elif kind == 'bolt':
        art = circle(80,82,61,paper,6)+path('M89 20 42 91h32l-8 53 54-77H88Z',sage,6)
        art += path('M15 13l13 13m102 99 15 15m-1-120-12 12',sw=5)
    elif kind == 'water':
        art = path('M80 11q-68 80-48 112 23 37 63 17 65-27-15-129Z',paper,6)
        art += path('M46 110q3 18 21 18',blue,6)+path('M11 152q17-10 34 0t34 0t34 0t35 0',blue,4)
    elif kind == 'train':
        art = rect(31,18,98,115,paper,16)+rect(43,36,74,43,blue,5,5)
        art += circle(54,111,9,coral,3)+circle(106,111,9,coral,3)+path('M42 136l-17 20m94-20 17 20M32 149h96',sw=6)
    elif kind == 'radio':
        art = path('M80 27 52 147h56ZM80 57v88',paper,6)+circle(80,24,8,coral,4)
        art += path('M57 47q-28-25-3-44m52 44q28-25 3-44M40 62Q1 26 37 0m85 62q38-36 3-62',sw=6)
        art += path('M57 119h46M62 97h36',sw=4)
    elif kind == 'mountain':
        art = path('M4 134 61 22l34 65 22-41 39 88Z',blue,6)
        art += path('m42 61 19-39 18 34-11-7-9 11-8-5Z',paper,3)
        art += path('M29 140h101m-88 12 4-10m68 10-4-10',sw=6)
    elif kind == 'plane':
        art = path('M75 7q6-7 13 0l6 52 58 28v14l-61-7-3 33 21 16v10l-29-7-29 7v-10l21-16-3-33-61 7V87l58-28Z',paper,6)
    elif kind == 'flask':
        art = path('M54 13h52m-45 0v51l-39 57q-12 25 14 28h90q25-4 13-28L99 64V13Z',paper,6)
        art += path('M44 99h73l18 31q4 12-13 12H39q-13-2-8-11Z',sage,4)+circle(64,119,7,paper,2)+circle(98,129,5,lilac,2)
        art += circle(81,49,6,coral,2)+circle(75,80,7,sage,2)
    elif kind == 'lock':
        art = path('M39 71V47q0-38 41-38t41 38v24H99V48q0-17-19-17T61 48v23Z',paper,6)
        art += rect(25,70,110,79,lilac,8,6)+circle(80,102,10,ink,0)+path('M76 108v19h8v-19',ink,0)
    elif kind == 'lighthouse':
        art = path('M52 144 65 54h31l15 90Z',paper,6)+rect(55,31,51,26,blue,2,5)
        art += path('M49 31 81 10l31 21ZM59 96h44m-47 21h50',coral,6)+path('M7 45l34-6m83 0 28 6',sw=6)
        art += path('M7 153q20-10 39 0t39 0t39 0t29 0',blue,4)
    elif kind == 'tent':
        art = path('M6 140 79 31l74 109Z',paper,6)+path('M44 140 80 81l34 59Z',sage,6)
        art += path('M79 31v-19m-70 128-6 11m149-11 5 11M80 81v59',sw=5)
        art += circle(126,31,13,coral,4)
    elif kind == 'stadium':
        art = '<ellipse cx="80" cy="96" rx="72" ry="49" fill="'+paper+'" stroke-width="6"/>'
        art += '<ellipse cx="80" cy="76" rx="72" ry="30" fill="'+blue+'" stroke-width="6"/>'
        art += '<ellipse cx="80" cy="76" rx="45" ry="16" fill="'+sage+'" stroke-width="4"/>'
        art += path('M17 29v22m-8-22h16m110 0v22m-8-22h16M41 107v27m37-28v34m39-33v27',sw=5)
    elif kind in ('house','mansion'):
        art = path('M28 143V66h103v77ZM13 67 80 16l66 51Z',paper,6)
        art += rect(64,96,32,47,teal,2,4)+rect(38,81,17,23,lilac,1,4)+rect(105,81,17,23,lilac,1,4)
        if kind == 'mansion': art += path('M43 73v65m74-65v65M23 144h112',sw=6)
    elif kind == 'pine':
        art = path('M80 8 42 62h17l-33 44h28l-37 36h126l-37-36h28l-33-44h17Z',sage,6)+path('M80 132v24',sw=8)
    elif kind == 'leaf':
        art = path('M22 133Q6 19 140 20q-1 109-98 119Z',sage,6)+path('M12 151 118 42M55 105l-4-39m3 40 41-2m-9-32-3-29',sw=5)
    elif kind == 'briefcase':
        art = rect(13,46,134,98,paper,9)+path('M55 46V23h51v23',sw=7)+path('M13 85q63 35 134 0',sw=6)+rect(67,84,27,29,lilac,3,4)
        art += path('M44 60h72',sw=4)
    else:
        raise ValueError(f'Unknown symbol: {kind}')
    return f'<g stroke="{ink}" stroke-linejoin="round" stroke-linecap="round">{art}</g>'
