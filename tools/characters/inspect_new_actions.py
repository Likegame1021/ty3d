import bpy
import json
from pathlib import Path

root = Path("G:/Game/vallage")
source = root / "art/characters/boy/meshy/v002/animations/animations.glb"
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(source))
arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
def curves(action):
    return [fc for layer in action.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]
out = {
    "arms": [{"name": arm.name, "scale": list(arm.scale), "bones": [b.name for b in arm.data.bones]} for arm in arms],
    "meshes": [{"name": mesh.name, "vertices": len(mesh.data.vertices), "materials": [m.name for m in mesh.data.materials]} for mesh in meshes],
    "actions": [],
}
for action in bpy.data.actions:
    channels = curves(action)
    hips = [fc for fc in channels if fc.data_path == 'pose.bones["Hips"].location']
    out["actions"].append({
        "name": action.name,
        "frames": list(action.frame_range),
        "seconds": (action.frame_range[1] - action.frame_range[0]) / bpy.context.scene.render.fps,
        "slots": [(s.identifier, s.target_id_type) for s in action.slots],
        "curve_count": len(channels),
        "hips_channels": {str(fc.array_index): [round(k.co.y, 6) for k in fc.keyframe_points] for fc in hips},
    })
output = root / "art/characters/boy/blender/new-action-inspection.json"
output.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
print("NEW_ACTION_INSPECTION_OK", json.dumps({"arms": len(arms), "meshes": len(meshes), "actions": [(a["name"], a["seconds"]) for a in out["actions"]]}), flush=True)
