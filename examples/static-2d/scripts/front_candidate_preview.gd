extends Node3D
## Independent static-front preview; no original gameplay or animations.
func _ready():
 var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/candidates/hero_front_isolated_v1.json"))
 var texture = load(metadata.texture)
 var profile = load("res://scripts/pixel_sprite_profile.gd").new()
 var error: String = profile.configure(metadata,texture.get_size())
 if not error.is_empty():
  push_error(error)
  return
 var sprite := Sprite3D.new()
 sprite.name = "StaticFrontCandidate"
 sprite.texture = texture
 var sampler = load("res://scripts/pixel_actor_visual.gd").new()
 profile.apply_settings(sprite,sampler)
 add_child(sprite)
 profile.apply_sample(sprite,sampler.sample("idle",0,1,Vector3.BACK,Basis.IDENTITY,0,false,false,0))
 var ground := MeshInstance3D.new()
 var plane := PlaneMesh.new()
 plane.size = Vector2(5,5)
 ground.mesh = plane
 var material := StandardMaterial3D.new()
 material.albedo_color = Color("766e58")
 material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 ground.material_override = material
 ground.position.y = -.01
 add_child(ground)
 var camera := Camera3D.new()
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.size = 2.7
 camera.position = Vector3(0,1.35,3)
 add_child(camera)
 camera.look_at(Vector3(0,.7,0))
 camera.current = true
 var environment := WorldEnvironment.new()
 environment.environment = Environment.new()
 environment.environment.background_mode = Environment.BG_COLOR
 environment.environment.background_color = Color("343c3f")
 add_child(environment)
 var overlay := CanvasLayer.new()
 var label := Label.new()
 label.text = "STATIC FRONT CANDIDATE · ONE IMAGE\nMaterial alpha cut 0.4 · No animation / no eight-way claim"
 label.position = Vector2(24,24)
 label.add_theme_font_size_override("font_size",18)
 overlay.add_child(label)
 add_child(overlay)
