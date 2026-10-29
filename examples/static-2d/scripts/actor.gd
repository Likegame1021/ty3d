extends CharacterBody3D
const Logic = preload("res://scripts/actor_logic.gd")
const PixelVisual = preload("res://scripts/pixel_actor_visual.gd")
var kind := "hero"
var state := "idle"
var state_time := 0.0
var phase := 0.0
var direction := 0
var speed := 3.1
var health := 3
var invincible := 0.0
var hit_sent := false
var target: Node3D
var visual: Sprite3D
var logic = Logic.new()
var textures := {}
var presentation = PixelVisual.new()
var home := Vector3.ZERO
var life := 0.0
var manual_motion := Vector2.ZERO
var automation := false
signal strike(actor)
func _ready():
 home = position
 var collider := CollisionShape3D.new()
 var capsule := CapsuleShape3D.new()
 capsule.radius = 0.23
 capsule.height = 1.0
 collider.shape = capsule
 collider.position.y = 0.5
 add_child(collider)
 visual = Sprite3D.new()
 visual.pixel_size = 0.039
 visual.billboard = BaseMaterial3D.BILLBOARD_ENABLED
 visual.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
 visual.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
 visual.alpha_scissor_threshold = 0.4
 visual.shaded = false
 visual.no_depth_test = false
 visual.offset = presentation.foot_offset
 visual.hframes = 8
 visual.vframes = 8
 add_child(visual)
 for action in ["idle", "run", "attack", "hurt"]:
  var path: String = "res://assets/" + kind + "_" + action + ".png"
  if ResourceLoader.exists(path): textures[action] = load(path)
 presentation.available_actions.assign(textures.keys())
 # Preserve this trial's existing clip cadence; gameplay duration stays owned here.
 presentation.clip_span = {"attack":8.0 / (14.0 * 0.64), "hurt":8.0 / (18.0 * 0.48)}
 var shadow := MeshInstance3D.new()
 var disc := CylinderMesh.new()
 disc.top_radius = 0.34
 disc.bottom_radius = 0.34
 disc.height = 0.008
 disc.radial_segments = 20
 shadow.mesh = disc
 var mat := StandardMaterial3D.new()
 mat.albedo_color = Color(0.12,0.10,0.065,0.33)
 mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 shadow.material_override = mat
 shadow.position.y = 0.015
 add_child(shadow)
func change_state(next: String):
 if state == next: return
 state = next
 state_time = 0.0
 hit_sent = false
func attack():
 if state not in ["attack", "hurt", "recover"]:
  change_state("attack")
func damage(from: Vector3):
 if invincible > 0.0: return
 health -= 1
 invincible = 1.1
 change_state("hurt")
 var knock := (global_position - from).normalized()
 velocity = knock * 3.5
 velocity.y = 0
func _physics_process(delta):
 life += delta
 phase += delta
 state_time += delta
 invincible = maxf(0.0, invincible - delta)
 var motion := Vector2.ZERO
 if state == "attack":
  velocity.x = 0
  velocity.z = 0
  if state_time >= 0.27 and not hit_sent:
   hit_sent = true
   strike.emit(self)
  if state_time >= 0.64: change_state("recover")
 elif state == "hurt":
  velocity.x = move_toward(velocity.x, 0, delta * 9)
  velocity.z = move_toward(velocity.z, 0, delta * 9)
  if state_time >= 0.48: change_state("recover")
 elif state == "recover":
  velocity.x = 0
  velocity.z = 0
  if state_time >= 0.22: change_state("idle")
 else:
  if kind == "hero":
   motion = manual_motion if automation else Input.get_vector("move_left", "move_right", "move_up", "move_down")
   if not automation and Input.is_action_just_pressed("attack"): attack()
  elif kind == "monster" and is_instance_valid(target):
   var offset := target.global_position - global_position
   if offset.length() < 6.0 and offset.length() > 1.15:
    motion = Vector2(offset.x, offset.z).normalized()
   elif offset.length() <= 1.15 and fmod(life, 2.2) < 0.07:
    attack()
  elif kind == "villager":
   var destination := home + Vector3(sin(life * .26) * 1.8, 0, 0)
   var offset := destination - position
   if offset.length() > 0.16: motion = Vector2(offset.x, offset.z).normalized() * .35
  if motion.length() > 0.05:
   direction = logic.direction_for(motion, direction)
   if state != "attack": change_state("run")
  elif state != "attack": change_state("idle")
  velocity.x = motion.x * speed
  velocity.z = motion.y * speed
 velocity.y -= 18.0 * delta
 move_and_slide()
 if health <= 0:
  health = 3
  position = home
  change_state("hurt")
 refresh_visual()
func refresh_visual():
 var angle := direction * PI / 4.0
 var facing := Vector3(sin(angle),0,cos(angle))
 # This trial uses the fixed, unrotated camera. An adapter for a different
 # camera passes that camera's global basis without changing gameplay facing.
 var duration := 0.64 if state == "attack" else 0.48 if state == "hurt" else 1.0
 var output: Dictionary = presentation.sample(state,state_time,duration,facing,
  Basis.IDENTITY,phase,state == "hurt",false,direction)
 if textures.has(output.action):
  visual.texture = textures[output.action]
  visual.frame = output.frame
 visual.modulate = output.tint
 visual.offset = output.offset
