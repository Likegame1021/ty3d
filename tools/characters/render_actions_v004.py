import bpy
from pathlib import Path
from mathutils import Vector

root = Path("G:/Game/vallage")
out = root / "art/characters/boy/blender"
bpy.ops.wm.open_mainfile(filepath=str(out / "boy-rigged-v004.blend"))
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 650
scene.render.resolution_y = 780
scene.render.resolution_percentage = 100
scene.world.color = (0.12, 0.12, 0.12)
scene.view_settings.view_transform = "AgX"
center = Vector((0, 0, 0.62))
for pos, power, size in [((2, -3, 4), 700, 3), ((-3, -1, 2), 350, 3), ((1, 3, 3), 500, 3)]:
    bpy.ops.object.light_add(type="AREA", location=pos)
    light = bpy.context.object
    light.data.energy = power
    light.data.shape = "DISK"
    light.data.size = size
    light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()
bpy.ops.object.camera_add(location=(1.5, -3.8, 1.5))
camera = bpy.context.object
camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.65
scene.camera = camera
for name, fraction in [("hurt", 0.32), ("pick_up", None), ("interact", 0.48), ("push", 0.53), ("vault", 0.50)]:
    action = bpy.data.actions[name]
    arm.animation_data.action = action
    arm.animation_data.action_slot = action.slots[0]
    if name == "pick_up":
        # Show the actual low hand pose in the retained bend/reach/stand segment.
        sampled = []
        for sample in range(61):
            candidate = 0.1 + 0.8 * sample / 60
            probe = action.frame_range[0] + (action.frame_range[1] - action.frame_range[0]) * candidate
            scene.frame_set(int(probe), subframe=probe - int(probe))
            hand = arm.matrix_world @ arm.pose.bones["RightHand"].matrix
            sampled.append((hand.translation.z, candidate))
        hand_height, fraction = min(sampled)
        print("PICKUP_LOWEST_RIGHT_HAND", fraction, hand_height, flush=True)
    frame = action.frame_range[0] + (action.frame_range[1] - action.frame_range[0]) * fraction
    scene.frame_set(int(frame), subframe=frame - int(frame))
    scene.render.filepath = str(out / f"pose-{name}-v004.png")
    bpy.ops.render.render(write_still=True)
    print("V004_PREVIEW", name, frame, flush=True)
print("V004_PREVIEWS_OK", flush=True)
