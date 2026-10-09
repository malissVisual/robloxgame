"""Build a portable level-by-level Career gallery and Roblox upload mapping from actual data."""
import argparse
import csv
import hashlib
import html
import json
from pathlib import Path
from PIL import Image
from inventory import ROOT

ART=ROOT/'art/career-thumbnails'
DESIGN=ROOT/'design/career-thumbnails'

def key(unlock):
    result=f"{unlock['kind']}:{unlock['id']}"
    return result

def filename(asset_key):
    return asset_key.replace(':','_').replace(' ','_')+'.png'

def reward_entries(reward):
    entries=[]
    if reward.get('money'):entries.append(('cash:money',f"${reward['money']:,}"))
    for item,count in reward.get('items',{}).items():entries.append(('item:'+item,f'{count} × {item}'))
    for kind in ['kit','paint','title']:
        if reward.get(kind):entries.append((kind+':'+reward[kind],reward[kind]))
    return entries

PAGE='''<!doctype html><html lang="cs"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>ZDC · Career thumbnails</title>
<style>
:root{color-scheme:dark;--bg:#101315;--panel:#1b2024;--line:#363d43;--red:#db4a45;--text:#f0f0ed;--muted:#aab2b7}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px system-ui,sans-serif}header{padding:28px max(24px,calc((100vw - 1320px)/2));border-bottom:1px solid var(--line)}h1{margin:0 0 10px;font-size:27px}h1:before{content:"";display:inline-block;width:12px;height:12px;background:var(--red);margin-right:12px}p{color:var(--muted);line-height:1.6}main{max-width:1320px;margin:auto;padding:24px}.tools{display:flex;flex-wrap:wrap;gap:10px;position:sticky;top:0;background:var(--bg);padding:12px 0;z-index:2}input,select,button{padding:10px;background:var(--panel);color:var(--text);border:1px solid var(--line);font:inherit}input{min-width:250px;flex:1}button{cursor:pointer}.level{border-top:1px solid var(--line);padding:25px 0}h2{font-size:20px;margin:0 0 18px}.level-number{background:var(--red);padding:6px 10px;margin-right:12px}h3{color:var(--muted);font-size:11px;letter-spacing:1.3px;margin:20px 0 12px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:12px}.card{background:var(--panel);border:1px solid var(--line);text-decoration:none;color:inherit;overflow:hidden}.card:hover{border-color:var(--red)}.card img{display:block;width:100%;aspect-ratio:16/9;object-fit:cover}.info{padding:12px}.name{font-weight:650;line-height:1.4}.tag,.code{font-size:11px;color:var(--muted);margin-top:6px}.tag{color:#c8ad77}.reward{border-left:3px solid #76a76c}.reward .tag{color:#8cbe81}.note{font-size:12px;color:var(--muted);margin-top:12px}dialog{max-width:1100px;width:95%;background:var(--bg);color:var(--text);border:1px solid var(--line);padding:20px}dialog::backdrop{background:#000c}dialog img{width:100%;max-height:72vh;object-fit:contain}.detail-footer{display:flex;justify-content:space-between;gap:15px;margin-top:12px}.download{color:var(--text)}small{color:var(--muted)}
</style><header><h1>CAREER · VŠECHNY NÁHLEDY</h1><p>90 odemčení · 15 levelů · samostatné obrázky odměn. Dostupné věci a automatické odměny jsou oddělené.<br>47 renderů skutečných modelů; zbývající obrázky jsou ilustrační návrhy k posouzení. Kliknutím zobrazíš celý PNG.</p></header>
<main><div class="tools"><input id="search" placeholder="Najít auto, práci, výbavu…" aria-label="Vyhledávání"><select id="level"><option value="">Všechny levely</option></select><select id="kind"><option value="">Všechny kategorie</option></select></div><div id="road"></div></main>
<dialog id="detail"><button id="close">Zavřít</button><h2 id="detail-name"></h2><img id="detail-image" alt=""><div class="detail-footer"><small id="detail-note"></small><a class="download" id="download" download>Stáhnout PNG</a></div></dialog>
<script id="career-data" type="application/json">DATA_HERE</script>
<script>
const data=JSON.parse(document.getElementById('career-data').textContent), assets=Object.fromEntries(data.assets.map(a=>[a.key,a]));
const labels={foot:'Pěší práce',kit:'Výbava',gun:'Zbraně',bike:'Kola a koloběžky',gear:'Doplňky',garage:'Garáže',tier:'Obtížnost',job:'Práce',car:'Auta',stage:'Stupně aut',campaign:'Kampaně',estate:'Nemovitosti',cash:'Peníze',item:'Spotřební věci',paint:'Laky',title:'Tituly'};
const level=document.getElementById('level'),kind=document.getElementById('kind'),search=document.getElementById('search');
data.road.forEach(r=>{const o=document.createElement('option');o.value=r.level;o.textContent=`Level ${r.level} · ${r.rank}`;level.append(o)});
Object.keys(labels).forEach(k=>{const o=document.createElement('option');o.value=k;o.textContent=labels[k];kind.append(o)});
function match(a,name){return (!kind.value||a.kind===kind.value)&&(!search.value||`${name} ${a.key}`.toLowerCase().includes(search.value.toLowerCase()))}
function card(entry,reward=false){const a=assets[entry.key];const link=document.createElement('a');link.href='../../art/career-thumbnails/'+a.file;link.className='card'+(reward?' reward':'');
const img=document.createElement('img');img.src=link.href;img.alt=entry.name;img.loading='lazy';link.append(img);
const info=document.createElement('div');info.className='info';const name=document.createElement('div');name.className='name';name.textContent=entry.name;info.append(name);
const tag=document.createElement('div');tag.className='tag';tag.textContent=reward?'DOSTANEŠ AUTOMATICKY':labels[a.kind]+' · ODEMČENÍ';info.append(tag);
const code=document.createElement('div');code.className='code';code.textContent=a.key;info.append(code);link.append(info);
link.onclick=e=>{e.preventDefault();document.getElementById('detail-name').textContent=entry.name;document.getElementById('detail-image').src=link.href;document.getElementById('detail-image').alt=entry.name;document.getElementById('detail-note').textContent=a.source==='actual-factory'?'Render skutečného modelu ze hry.':'Ilustrační návrh; není přesným renderem aktuální hry.';document.getElementById('download').href=link.href;document.getElementById('detail').showModal()};return link}
function render(){const road=document.getElementById('road');road.replaceChildren();data.road.forEach(r=>{if(level.value&&r.level!==Number(level.value))return;
const unlocked=r.unlocks.filter(u=>match(assets[u.key],u.name));const rewards=r.rewardEntries.filter(u=>match(assets[u.key],u.name));if(!unlocked.length&&!rewards.length)return;
const section=document.createElement('section');section.className='level';const heading=document.createElement('h2');const badge=document.createElement('span');badge.className='level-number';badge.textContent=r.level;heading.append(badge,document.createTextNode(r.rank));section.append(heading);
const add=(title,entries,reward)=>{if(!entries.length)return;const h=document.createElement('h3');h.textContent=title;section.append(h);const grid=document.createElement('div');grid.className='grid';entries.forEach(e=>grid.append(card(e,reward)));section.append(grid)};
add('ODEMČENO · MOŽNOST KOUPIT / ZAČÍT',unlocked,false);add('ODMĚNA ZA LEVEL · DOSTANEŠ',rewards,true);if(r.reward?.text){const note=document.createElement('div');note.className='note';note.textContent=r.reward.text;section.append(note)}road.append(section)})}
[search,level,kind].forEach(x=>x.addEventListener('input',render));document.getElementById('close').onclick=()=>document.getElementById('detail').close();render();
</script></html>'''

def build(inventory, sources):
    names={key(u):u['name'] for row in inventory['road'] for u in row['unlocks']}
    for row in inventory['road']:
        for k,name in reward_entries(row.get('reward',{})):names.setdefault(k,name)
    names['cash:money']='Cash reward'
    assets=[]
    for k,name in names.items():
        path=ART/filename(k)
        with Image.open(path) as image:w,h=image.size
        assets.append({'key':k,'kind':k.split(':')[0],'name':name,'file':path.name,
            'source':sources[k],'width':w,'height':h,'sha256File':hashlib.sha256(path.read_bytes()).hexdigest(),'robloxImage':''})
    road=[]
    for row in inventory['road']:
        r=dict(row);r['unlocks']=[dict(u,key=key(u)) for u in row['unlocks']]
        r['rewardEntries']=[{'key':k,'name':name} for k,name in reward_entries(row.get('reward',{}))];road.append(r)
    data={'schema':1,'sourceRevision':'882c11c','date':'2026-10-09','status':'Review thumbnails only; no gameplay/UI wiring or Roblox uploads.','assets':assets,'road':road}
    (ART/'manifest.json').write_text(json.dumps(data,indent=2)+'\n')
    DESIGN.mkdir(parents=True,exist_ok=True)
    payload=json.dumps(data,ensure_ascii=False).replace('</','<\\/')
    (DESIGN/'index.html').write_text(PAGE.replace('DATA_HERE',payload))
    with (DESIGN/'upload.csv').open('w',newline='') as stream:
        writer=csv.writer(stream);writer.writerow(['key','name','file','source','roblox_image_id'])
        writer.writerows((a['key'],a['name'],a['file'],a['source'],'') for a in assets)
    print(f'Built gallery: {len(assets)} unique images / {sum(len(r["unlocks"]) for r in road)} unlocks')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('inventory',type=Path);p.add_argument('sources',type=Path)
    a=p.parse_args();build(json.loads(a.inventory.read_text()),json.loads(a.sources.read_text()))
