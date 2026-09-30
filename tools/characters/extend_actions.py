"""Add same-rig Meshy actions to the v003 master without replacing its body or old clips."""

import bpy
import hashlib
import json
import math
import struct
from pathlib import Path
from mathutils import Matrix

ROOT = Path("G:/Game/vallage")
OUT = ROOT / "art/characters/boy/blender"
SOURCE = ROOT / "art/characters/boy/meshy/v002/animations/animations.glb"
MASTER = OUT / "boy-rigged-v003.blend"
V004 = OUT / "boy-rigged-v004.blend"
EXPORT = ROOT / "game/assets/characters/boy/boy.glb"
MAPPING = {
    "Hit_Reaction": ("hurt", 0.82, 1.0, 1.0),
    "Male_Bend_Over_Pick_Up": ("pick_up", 1.60, 1.0, 0.50),
    "open_door": ("interact", 1.30, 1.0, 1.0),
    "Push_Forward_and_Stop": ("push", 1.45, 0.20, 1.0),
    "Unarmed_Vault": ("vault", 0.87, 0.20, 1.0),
}
ORIGINAL = {"idle", "walk", "run", "attack_branch"}


def curves(action):
    return [fc for layer in action.layers for strip in layer.strips for bag in strip.channelbags for fc in bag.fcurves]


def state_digest(arm, mesh, actions):
    state = {
        "bones": [(b.name, b.parent.name if b.parent else None, [[float(x) for x in row] for row in b.matrix_local]) for b in arm.data.bones],
        "mesh": {
            "vertices": [list(v.co) for v in mesh.data.vertices],
            "polygons": [list(p.vertices) for p in mesh.data.polygons],
            "uv": [[list(uv.uv) for uv in layer.data] for layer in mesh.data.uv_layers],
            "materials": [(m.name, [(n.name, n.type) for n in m.node_tree.nodes], [(l.from_node.name, l.from_socket.name, l.to_node.name, l.to_socket.name) for l in m.node_tree.links]) for m in mesh.data.materials],
        },
        "actions": [(
            action.name,
            [(slot.identifier, slot.target_id_type) for slot in action.slots],
            [(fc.data_path, fc.array_index, [(list(k.co), list(k.handle_left), list(k.handle_right), k.interpolation) for k in fc.keyframe_points]) for fc in curves(action)],
        ) for action in sorted(actions, key=lambda a: a.name)],
    }
    return hashlib.sha256(json.dumps(state, sort_keys=True).encode()).hexdigest()


bpy.ops.wm.open_mainfile(filepath=str(MASTER))
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
original_actions = [a for a in bpy.data.actions if a.name in ORIGINAL]
assert {a.name for a in original_actions} == ORIGINAL
original_frames = {a.name: list(a.frame_range) for a in original_actions}
baseline = state_digest(arm, mesh, original_actions)
old_bones = {b.name: b.matrix_local.copy() for b in arm.data.bones}
old_objects = set(bpy.context.scene.objects)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
imported = set(bpy.context.scene.objects) - old_objects
source_arm = next(o for o in imported if o.type == "ARMATURE")
source_mesh = next(o for o in imported if o.type == "MESH" and any(mod.type == "ARMATURE" for mod in o.modifiers))
new_actions = [a for a in bpy.data.actions if a.name not in ORIGINAL]
assert {a.name for a in new_actions} == set(MAPPING), {a.name for a in new_actions}
factor = source_arm.scale.x
assert abs(factor - 0.01) < 1e-4
source_arm.data.transform(Matrix.Scale(factor, 4))
source_mesh.data.transform(Matrix.Scale(factor, 4))
source_arm.scale = (1, 1, 1)
source_bones = {b.name: b.matrix_local.copy() for b in source_arm.data.bones}
assert set(source_bones) == set(old_bones)
assert max(abs(source_bones[name][i][j] - old_bones[name][i][j]) for name in old_bones for i in range(4) for j in range(4)) < 1e-7
for track in list(source_arm.animation_data.nla_tracks):
    source_arm.animation_data.nla_tracks.remove(track)
source_arm.animation_data.action = None

scene = bpy.context.scene
fps = scene.render.fps
print("MERGE_SCENE_FPS", fps, flush=True)
rest_hips = source_arm.data.bones["Hips"].matrix_local.translation.copy()
report = {"source": str(SOURCE), "master": str(MASTER), "base_sha256": baseline, "fps": fps, "new_actions": {}}

for action in new_actions:
    original_name = action.name
    new_name, target_seconds, vertical_scale, keep_fraction = MAPPING[original_name]
    full_source_seconds = (action.frame_range[1] - action.frame_range[0]) / fps
    action.name = new_name
    for fc in curves(action):
        if fc.data_path.endswith(".location"):
            for key in fc.keyframe_points:
                key.co.y *= factor
                key.handle_left.y *= factor
                key.handle_right.y *= factor
    if keep_fraction < 1.0:
        first, last = map(float, action.frame_range)
        cutoff = first + (last - first) * keep_fraction
        # The bend, reach and return are in the first half; the long remaining
        # idle/arm extension is omitted rather than accelerating it fourfold.
        for fc in curves(action):
            end_value = fc.evaluate(cutoff)
            for index in reversed(range(len(fc.keyframe_points))):
                if fc.keyframe_points[index].co.x > cutoff + 1e-5:
                    fc.keyframe_points.remove(fc.keyframe_points[index], fast=True)
            if not any(abs(key.co.x - cutoff) < 1e-5 for key in fc.keyframe_points):
                fc.keyframe_points.insert(cutoff, end_value, options={"FAST"})
            fc.update()
    source_seconds = (action.frame_range[1] - action.frame_range[0]) / fps
    source_arm.animation_data.action = action
    source_arm.animation_data.action_slot = action.slots[0]
    start, end = map(float, action.frame_range)
    frames = sorted(set([float(frame) for frame in range(math.ceil(start), math.floor(end) + 1)] + [start, end]))
    samples = []
    for frame in frames:
        scene.frame_set(int(frame), subframe=frame - int(frame))
        bpy.context.view_layer.update()
        hips = source_arm.pose.bones["Hips"].matrix.copy()
        hips.translation.x = rest_hips.x
        hips.translation.y = rest_hips.y
        hips.translation.z = rest_hips.z + (hips.translation.z - rest_hips.z) * vertical_scale
        samples.append((frame, hips))
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in list(bag.fcurves):
                    if fc.data_path == 'pose.bones["Hips"].location':
                        bag.fcurves.remove(fc)
    for frame, matrix in samples:
        scene.frame_set(int(frame), subframe=frame - int(frame))
        source_arm.pose.bones["Hips"].matrix = matrix
        source_arm.pose.bones["Hips"].keyframe_insert(data_path="location", frame=frame, group="Hips")
    for fc in curves(action):
        if fc.data_path == 'pose.bones["Hips"].location':
            for key in fc.keyframe_points:
                key.interpolation = "LINEAR"
    start = float(action.frame_range[0])
    ratio = target_seconds / source_seconds
    for fc in curves(action):
        for key in fc.keyframe_points:
            key.co.x = start + (key.co.x - start) * ratio
            key.handle_left.x = start + (key.handle_left.x - start) * ratio
            key.handle_right.x = start + (key.handle_right.x - start) * ratio
        fc.update()
    report["new_actions"][new_name] = {"source_name": original_name, "full_source_seconds": full_source_seconds, "used_source_seconds": source_seconds, "kept_fraction": keep_fraction, "target_seconds": target_seconds, "actual_seconds": (action.frame_range[1] - action.frame_range[0]) / fps, "vertical_scale": vertical_scale, "root_horizontal_removed": True}
    source_arm.animation_data.action = None

# The new clips use exactly the same rest skeleton, so evaluate them on the v003 body.
for action in new_actions:
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    start, end = map(float, action.frame_range)
    poses = []
    for fraction in (0, 0.25, 0.5, 0.75, 1):
        frame = start + (end - start) * fraction
        scene.frame_set(int(frame), subframe=frame - int(frame))
        bpy.context.view_layer.update()
        evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
        points = [evaluated.matrix_world @ v.co for v in evaluated.data.vertices]
        low = [min(p[i] for p in points) for i in range(3)]
        high = [max(p[i] for p in points) for i in range(3)]
        poses.append({"fraction": fraction, "min": low, "max": high})
        assert high[2] - low[2] < 1.9 and high[0] - low[0] < 1.9, (action.name, fraction, low, high)
    report["new_actions"][action.name]["sampled_bounds"] = poses
    arm.animation_data.action = None

assert baseline == state_digest(arm, mesh, original_actions), "v003 bones, mesh, material or original action keys changed"
assert original_frames == {a.name: list(a.frame_range) for a in original_actions}
for action in new_actions:
    track = arm.animation_data.nla_tracks.new()
    track.name = action.name
    strip = track.strips.new(action.name, 1, action)
    strip.action_slot = action.slots[0]
    track.mute = True
for item in imported:
    bpy.data.objects.remove(item, do_unlink=True)
arm.animation_data.action = None
for track in arm.animation_data.nla_tracks:
    track.mute = True
for pose_bone in arm.pose.bones:
    pose_bone.matrix_basis = Matrix.Identity(4)
scene.frame_set(0)
assert baseline == state_digest(arm, mesh, original_actions)
bpy.ops.wm.save_as_mainfile(filepath=str(V004))
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.export_scene.gltf(filepath=str(EXPORT), export_format="GLB", use_selection=True, export_yup=True, export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_range=False, export_optimize_animation_size=True)
with EXPORT.open("rb") as file:
    file.read(12)
    length, chunk_kind = struct.unpack("<II", file.read(8))
    gltf = json.loads(file.read(length))
assert set(animation["name"] for animation in gltf["animations"]) == ORIGINAL | {item[0] for item in MAPPING.values()}
assert gltf["meshes"] and gltf["materials"]
report["exported_clips"] = [animation["name"] for animation in gltf["animations"]]
report["v004"] = str(V004)
report["export"] = str(EXPORT)
(OUT / "actions-v004-verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("BOY_V004_EXPORT_OK", json.dumps({k: round(v["actual_seconds"], 3) for k, v in report["new_actions"].items()}), flush=True)
