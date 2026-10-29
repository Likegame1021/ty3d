extends SceneTree
## Packaging-only resource audit. Does not change any game script or scene.
var checks := 0
var failures := 0
func check(value: bool, label: String):
 checks += 1
 if not value:
  failures += 1
  push_error(label)
func _initialize():
 call_deferred("run")
func verify_scene(world, phase: String):
 check(world.hero.multi_visual.ready, phase + ": new hero is ready")
 check(world.hero.visual.texture is AtlasTexture, phase + ": new hero atlas is applied")
 check(world.hero.textures.is_empty(), phase + ": old hero sheets released")
 check(world.enemies.size() == 8, phase + ": eight monsters")
 var profile = JSON.parse_string(FileAccess.get_file_as_string("res://profiles/monster_strike_v1.json"))
 for enemy in world.enemies:
  check(enemy.multi_visual.ready and enemy.display_error.is_empty(), phase + ": monster profile ready")
  check(enemy.visual.texture is Texture2D and enemy.last_display.get("valid", false), phase + ": monster texture applied")
  check(enemy.multi_visual.clips.size() == 4, phase + ": four monster clips")
  for action in ["idle", "run", "hurt", "attack"]:
   check(enemy.multi_visual.clips.has(action), phase + ": clip present " + action)
   if not enemy.multi_visual.clips.has(action): continue
   var clip = enemy.multi_visual.clips[action]
   check(clip.ready and clip.textures.size() == 8, phase + ": eight directions in " + action)
   for row in range(8):
    if row >= clip.textures.size(): continue
    check(clip.textures[row].size() == 8, phase + ": eight frames in " + action)
    for column in range(8):
     if column >= clip.textures[row].size(): continue
     var payload = clip.frame_payload(row, column)
     check(payload.get("valid", false) and payload.texture is Texture2D, phase + ": valid frame")
     if payload.get("texture") is Texture2D:
      var path: String = payload.texture.resource_path
      check(path.begins_with(str(profile.clips[action].asset_directory) + "/"), phase + ": correct original clip path")
      check(FileAccess.get_sha256(path) == profile.clips[action].frame_sha256.get(path.get_file(), ""), phase + ": original frame hash")
 for name in ["RouteWell", "RouteHarvestSacks", "RoadWest", "RoadFirstTurn", "RoadVertical", "RoadSecondTurn", "RoadEast", "RoadGateWest", "RoadGateEast", "RouteGatehouse"]:
  check(world.get_node_or_null(name) is Node3D, phase + ": environment prop " + name)
func run():
 var world = load("res://scenes/corn_route_new_pixel_hero_static_v1.tscn").instantiate()
 root.add_child(world)
 await physics_frame
 world.process_mode = Node.PROCESS_MODE_DISABLED
 verify_scene(world, "startup")
 world.restart_candidate()
 verify_scene(world, "reset")
 world.queue_free()
 await process_frame
 var baseline = load("res://main.tscn").instantiate()
 root.add_child(baseline)
 # The frame signal precedes actor callbacks; let one full physics tick run.
 await physics_frame
 await physics_frame
 baseline.process_mode = Node.PROCESS_MODE_DISABLED
 for actor in [baseline.hero, baseline.monster, baseline.villager]:
  check(actor.visual.texture is Texture2D, "unchanged default main actor has texture")
  check(actor.textures.has("idle") and actor.textures.has("run"), "unchanged default main idle/run available")
 check(ProjectSettings.get_setting("application/run/main_scene") == "res://main.tscn", "default main unchanged")
 baseline.queue_free()
 print("SMALL SAMPLE RESOURCE AUDIT checks=", checks, " failures=", failures)
 quit(1 if failures else 0)
