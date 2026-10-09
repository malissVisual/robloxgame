"""Audit full Career coverage against the current real Luau data, image bytes and gallery links."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
from PIL import Image
from inventory import ROOT, export
from gallery import key, reward_entries, filename


def check(luau):
    actual=export(luau)
    art=ROOT/'art/career-thumbnails';design=ROOT/'design/career-thumbnails'
    saved=json.loads((art/'manifest.json').read_text())
    expected={key(u) for r in actual['road'] for u in r['unlocks']}
    for row in actual['road']:
        expected.update(k for k,_ in reward_entries(row.get('reward',{})))
    assets={a['key']:a for a in saved['assets']}
    assert len(assets)==len(saved['assets']), 'Duplicate asset keys'
    assert expected==set(assets), f'Missing {expected-set(assets)}; extra {set(assets)-expected}'
    assert {p.name for p in art.glob('*.png')}=={a['file'] for a in assets.values()}
    for row,live in zip(saved['road'],actual['road'],strict=True):
        row=dict(row);entry=row.pop('rewardEntries')
        assert entry==[{'key':k,'name':n} for k,n in reward_entries(live.get('reward',{}))]
        row['unlocks']=[{k:v for k,v in u.items() if k!='key'} for u in row['unlocks']]
        assert row==live, f'Stale Career level {live["level"]}'
    for k,a in assets.items():
        assert a['file']==filename(k) and ':' not in a['file'], 'Windows-safe filename expected'
        path=art/a['file']
        with Image.open(path) as image:
            image.verify()
        with Image.open(path) as image:
            assert image.format=='PNG' and image.size==(a['width'],a['height'])
            assert abs(image.width/image.height-16/9)<.015
        assert hashlib.sha256(path.read_bytes()).hexdigest()==a['sha256File']
        assert a['source'] in {'actual-factory','representative-art','concept-scene','concept-business'}
        assert not a['robloxImage'], 'Do not fabricate Roblox IDs'
    gallery=(design/'index.html').read_text()
    payload=gallery.split('<script id="career-data" type="application/json">')[1].split('</script>')[0]
    assert json.loads(payload)==saved, 'Gallery snapshot differs'
    with (design/'upload.csv').open(newline='') as f:
        rows=list(csv.DictReader(f))
    assert len(rows)==len(assets) and {r['key'] for r in rows}==set(assets)
    for r in rows:
        assert r['file']==assets[r['key']]['file'] and not r['roblox_image_id']
    print(f'Career coverage PASS: {sum(len(r["unlocks"]) for r in actual["road"])} unlocks, {len(assets)} images, all level rewards')
    print('PNG integrity, aspect ratios, file hashes, Windows names, gallery and upload map PASS')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('luau');check(p.parse_args().luau)
