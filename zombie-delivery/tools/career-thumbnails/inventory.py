"""Export the real Career.road() and the supporting Config records with the Luau CLI."""
import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

ENCODE = '''local function encode(v)
 if type(v)=="nil" then return "null" end
 if type(v)=="string" then return string.format("%q",v) end
 if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
 local out={}
 if #v>0 then for _,x in v do table.insert(out,encode(x)) end return "["..table.concat(out,",").."]" end
 for k,x in v do table.insert(out,encode(tostring(k))..":"..encode(x)) end return "{"..table.concat(out,",").."}"
end
'''


def export(luau):
    with tempfile.TemporaryDirectory() as folder:
        tmp = Path(folder)
        for source in (ROOT / "src/shared").glob("*.luau"):
            text = re.sub(r'require\(script\.Parent\.(\w+)\)', r'require("./\1")', source.read_text())
            (tmp / source.name).write_text(text)
        (tmp / "inventory.luau").write_text(ENCODE + '''local Career=require("./Career")
local Config=require("./Config")
local Missions=require("./Missions")
print(encode({road=Career.road(),kit=Config.Kit,gear=Config.Gear,weapons=Config.Weapons,
carguns=Config.CarGuns,cars=Config.Cars,properties=Config.Estate.Properties,
campaigns=Missions.Campaigns,items=Config.Items,paints=Config.Paints}))
''')
        result = subprocess.run([str(Path(luau).resolve()), "inventory.luau"], cwd=tmp,
                                text=True, capture_output=True, check=True)
        return json.loads(result.stdout)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("luau")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = export(args.luau)
    args.output.write_text(json.dumps(data, indent=2) + "\n")
    print("Actual Career inventory:", sum(len(s["unlocks"]) for s in data["road"]), "unlocks")
