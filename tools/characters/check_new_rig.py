import bpy, json
from mathutils import Matrix
from pathlib import Path

root = Path("G:/Game/vallage")
bpy.ops.wm.open_mainfile(filepath=str(root / "art/characters/boy/blender/boy-rigged-v003.blend"))
old = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
old_bones = {b.name: b.matrix_local.copy() for b in old.data.bones}
before = set(bpy.context.scene.objects)
bpy.ops.import_scene.gltf(filepath=str(root / "art/characters/boy/meshy/v002/animations/animations.glb"))
added = set(bpy.context.scene.objects) - before
new = next(o for o in added if o.type == "ARMATURE")
new.data.transform(Matrix.Scale(new.scale.x, 4))
new.scale = (1, 1, 1)
new_bones = {b.name: b.matrix_local.copy() for b in new.data.bones}
assert set(old_bones) == set(new_bones), (set(old_bones) - set(new_bones), set(new_bones) - set(old_bones))
differences = {}
for name, old_matrix in old_bones.items():
    new_matrix = new_bones[name]
    differences[name] = max(abs(old_matrix[i][j] - new_matrix[i][j]) for i in range(4) for j in range(4))
report = {
    "old_arm": old.name,
    "new_arm": new.name,
    "same_names": True,
    "max_matrix_difference": max(differences.values()),
    "worst_bone": max(differences, key=differences.get),
    "bone_differences": differences,
}
(root / "art/characters/boy/blender/new-rig-compatibility.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("NEW_RIG_COMPATIBILITY", json.dumps({k: report[k] for k in ["same_names", "max_matrix_difference", "worst_bone"]}), flush=True)
