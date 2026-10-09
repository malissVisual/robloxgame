"""Build an offline review gallery and upload checklist; images remain unmodified."""

import html
from pathlib import Path

from check import ROOT, run


def escape(value):
    return html.escape(str(value), quote=True)


def build():
    manifest = run()
    design = ROOT / "design/job-thumbnails"
    cards = []
    for asset in manifest["assets"]:
        uses = ["delivery:" + key for key, value in manifest["ordinary"].items() if value == asset["id"]]
        uses += ["special:" + key for key, value in manifest["special"].items() if value == asset["id"]]
        if asset["id"] == manifest["round"]:
            uses.append("newspaper-round")
        if asset["id"] == manifest["tutorial"]:
            uses.append("tutorial-letters")
        src = "../../art/job-thumbnails/" + asset["file"]
        cards.append(f'<article data-search="{escape(asset["name"] + " " + " ".join(uses))}">'
                     f'<a href="{src}"><img src="{src}" alt="{escape(asset["name"])}" loading="lazy"></a>'
                     f'<div class="body"><h2>{escape(asset["name"])}</h2>'
                     f'<p>{escape(" · ".join(uses))}</p><a download href="{src}">Stáhnout PNG</a></div></article>')
    page = '''<!doctype html><html lang="cs"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>ZDC · Náhledy všech prací</title><style>
*{box-sizing:border-box}body{margin:0;background:#111519;color:#f2f3f4;font:15px/1.5 system-ui,sans-serif}
header,main{max-width:1440px;margin:auto;padding:24px}header{border-bottom:1px solid #42484d}
h1{font-size:26px;margin:0 0 8px}h1:before{content:'■ ';color:#d74a46}p{color:#b8bec4}
input{width:100%;max-width:540px;padding:12px;background:#20252b;border:1px solid #555;color:white;font:inherit}
.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px}article{background:#1b2025;border:1px solid #454b50}
img{display:block;width:100%;height:auto}.body{padding:14px}h2{font-size:18px;margin:0}article p{font-size:12px;min-height:36px}
a{color:#f2f3f4;text-underline-offset:4px}.preview{display:block;margin:12px 0 32px;border:1px solid #454b50}
[hidden]{display:none!important}@media(max-width:950px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:560px){.grid{grid-template-columns:1fr}header,main{padding:14px}}footer{margin:32px 0;color:#b8bec4}
</style><header><h1>ZDC · Náhledy všech prací</h1>
<p>25 obrázků · 19 běžných rozvozů · 12 speciálních prací. Společný podnik používá stejný náhled.</p>
<p>Obrázky pro UI; zatím nejsou zapojené ve hře. Návrhy vzhledu, nikoli fotografie ze Studia nebo nové 3D modely.</p>
<label for="search">Najít podnik nebo ID práce</label><br><input id="search" type="search" placeholder="Luigi, freightrun, cake…">
</header><main><section class="grid">''' + "\n".join(cards) + '''</section>
<h2>Career · obrázkové karty a samostatné odměny</h2><p>Návrh rozložení. Odemčené nabídky a automaticky získané odměny jsou oddělené.</p>
<a class="preview" href="career-preview.png"><img src="career-preview.png" alt="Návrh Career s náhledy a okénky odměn"></a>
<h2>Job board · náhled zadávajícího podniku</h2>
<a class="preview" href="job-board-preview.png"><img src="job-board-preview.png" alt="Návrh job boardu s náhledy podniků"></a>
<footer>Popisky, ceny, příjemci a průběh musí být živým textem UI. PNG je pouze obrázek.<br>
Roblox upload IDs zatím nejsou vyplněné; přiřazení všech prací je v manifest.json.</footer></main>
<script>document.getElementById('search').addEventListener('input',function(){const q=this.value.toLowerCase();
document.querySelectorAll('article').forEach(a=>a.hidden=!a.dataset.search.toLowerCase().includes(q))});</script></html>'''
    (design / "index.html").write_text(page)
    checklist = "asset_id,file,roblox_image\n" + "\n".join(
        f'{a["id"]},{a["file"]},{a["robloxImage"]}' for a in manifest["assets"]) + "\n"
    (design / "upload.csv").write_text(checklist)
    print("Built offline gallery and 25-row Roblox upload checklist.")


if __name__ == "__main__":
    build()
