# Blender renders of recorded parts

`render.py` draws what a recorder export holds (a JSON list of models, each with its Parts, WedgeParts and
Cylinders: their size, place, turn, colour and material) in Blender, one PNG a model, with neutral studio light. It
imports no meshes: Blender shows exactly the recorded shapes. Today `design/character-models/` uses it for the native
bodies that `tools/character-art/check.py` exports:

```sh
python3 zombie-delivery/tools/character-art/check.py /path/to/luau zombie-delivery/design/character-models/geometry.json
blender -b -t 4 --python zombie-delivery/tools/model-art/render.py -- zombie-delivery/design/character-models/geometry.json /tmp/renders --workbench
```

`--workbench` uses Blender's Workbench engine (no noise); a third argument after the output folder renders one model id
only. 10.5: the city's art handoff tools that lived here (the kit's, the bikes', the phone's and the gas station's
exports, contact sheets, the icons' rasterizer, the building blueprints) went with the city; they are in git's history
up to 10.4.
