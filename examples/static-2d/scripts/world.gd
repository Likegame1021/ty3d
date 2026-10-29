extends Node3D
const Actor = preload("res://scripts/actor.gd")
var hero
var monster
var villager
var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var hud: Label
var late := false
var fx
var random := RandomNumberGenerator.new()
var materials := {}
func _ready():
 random.seed = 8849
 setup_input()
 build_environment()
 build_yard()
 hero = add_actor("hero", Vector3(0, .05, 1.5), "Hero")
 monster = add_actor("monster", Vector3(3.4,.05,0.8), "Monster")
 monster.speed = 1.4
 monster.target = hero
 villager = add_actor("villager", Vector3(-1.8,.05,-3.8), "Villager")
 villager.speed = 1.8
 if ResourceLoader.exists("res://scripts/combat_fx.gd"):
  fx = load("res://scripts/combat_fx.gd").new()
  add_child(fx)
 build_hud()
func setup_input():
 var bindings := {"move_left":[KEY_A,KEY_LEFT], "move_right":[KEY_D,KEY_RIGHT], "move_up":[KEY_W,KEY_UP], "move_down":[KEY_S,KEY_DOWN], "attack":[KEY_SPACE], "light_toggle":[KEY_L], "reset":[KEY_R]}
 for action in bindings:
  if not InputMap.has_action(action): InputMap.add_action(action)
  for key in bindings[action]:
   var event := InputEventKey.new()
   event.physical_keycode = key
   InputMap.action_add_event(action,event)
 var click := InputEventMouseButton.new()
 click.button_index = MOUSE_BUTTON_LEFT
 InputMap.action_add_event("attack",click)
func mat(color: Color) -> StandardMaterial3D:
 var key := color.to_html()
 if materials.has(key): return materials[key]
 var m := StandardMaterial3D.new()
 m.albedo_color = color
 m.roughness = .92
 materials[key] = m
 return m
func box(pos: Vector3, size: Vector3, color: Color, solid := false) -> MeshInstance3D:
 var instance := MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size = size
 instance.mesh = mesh
 instance.material_override = mat(color)
 instance.position = pos
 add_child(instance)
 if solid:
  var body := StaticBody3D.new()
  var collider := CollisionShape3D.new()
  var shape := BoxShape3D.new()
  shape.size = size
  collider.shape = shape
  body.add_child(collider)
  instance.add_child(body)
 return instance
func cylinder(pos: Vector3, radius: float, height: float, color: Color, top := -1.0) -> MeshInstance3D:
 var instance := MeshInstance3D.new()
 var mesh := CylinderMesh.new()
 mesh.top_radius = radius if top < 0 else top
 mesh.bottom_radius = radius
 mesh.height = height
 mesh.radial_segments = 8
 instance.mesh = mesh
 instance.position = pos
 instance.material_override = mat(color)
 add_child(instance)
 return instance
func leaf(pos: Vector3, scale_value: Vector3, color: Color):
 var mesh := SphereMesh.new()
 mesh.radial_segments = 6
 mesh.rings = 3
 var instance := MeshInstance3D.new()
 instance.mesh = mesh
 instance.position = pos
 instance.scale = scale_value
 instance.material_override = mat(color)
 add_child(instance)
 return instance
func build_environment():
 var camera := Camera3D.new()
 camera.name = "Camera3D"
 camera.projection = Camera3D.PROJECTION_ORTHOGONAL
 camera.size = 20.8
 camera.position = Vector3(0, 18, 22)
 add_child(camera)
 camera.look_at(Vector3(0, .2, -.2))
 camera.current = true
 sun = DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-48,-32,0)
 sun.light_color = Color("ffe9bd")
 sun.light_energy = 1.25
 sun.shadow_enabled = true
 sun.directional_shadow_max_distance = 50
 sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
 add_child(sun)
 world_environment = WorldEnvironment.new()
 var environment := Environment.new()
 environment.background_mode = Environment.BG_COLOR
 environment.background_color = Color("b3c5ad")
 environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color = Color("c4dcdb")
 environment.ambient_light_energy = .62
 environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 world_environment.environment = environment
 add_child(world_environment)
func build_yard():
 box(Vector3(0,-.23,0), Vector3(21,.4,18), Color("887750"),true)
 box(Vector3(0,-.025,0), Vector3(19,.06,16), Color("c5aa77"))
 # Earthen paths with fine deterministic mottling.
 for i in range(650):
  var p := Vector3(random.randf_range(-9.4,9.4), .017, random.randf_range(-7.8,7.8))
  var size_value := random.randf_range(.035,.16)
  box(p, Vector3(size_value,.018,size_value * .65), Color("d4bc8b") if i % 3 else Color("a88e61"))
 # Back house: plaster, exposed masonry, dark timber and tiled pitched roof.
 box(Vector3(-2.5,1.45,-5.8), Vector3(7.4,2.9,3.2), Color("b6a183"),true)
 box(Vector3(-2.5,.22,-3.88), Vector3(7.7,.42,.65), Color("999181"),true)
 box(Vector3(-2.5,.08,-3.4), Vector3(2.4,.16,.55), Color("aaa18a"))
 box(Vector3(-2.4,1.12,-4.16), Vector3(1.45,2.2,.12), Color("503a27"))
 for x in [-3.19,-1.62]: box(Vector3(x,1.25,-4.04),Vector3(.13,2.25,.08),Color("a64531"))
 box(Vector3(-2.4,2.48,-4.04),Vector3(1.72,.26,.08),Color("a64531"))
 box(Vector3(-2.37,1.43,-4.06),Vector3(.40,.45,.025),Color("b84b32")).rotation_degrees.z = 45
 for x in [-5.15,.08]:
  box(Vector3(x,1.65,-4.13),Vector3(1.13,.94,.12),Color("353a32"))
  for bar in range(4): box(Vector3(x-.45+bar*.3,1.65,-4.02),Vector3(.06,.95,.08),Color("5b4931"))
  box(Vector3(x,1.65,-3.99),Vector3(1.16,.06,.08),Color("5b4931"))
 for row in range(5):
  for col in range(16):
   if (row+col)%4 == 0:
    box(Vector3(-6+col*.45,.17+row*.21,-4.17),Vector3(.40,.17,.04),Color("8f7964"))
 for side in [-1,1]:
  var roof := box(Vector3(-2.5,3.24,-5.8+side*.99),Vector3(8.1,.14,2.48),Color("4b5754"))
  roof.rotation_degrees.x = side * 27
  for col in range(33):
   for row in range(7):
    var z: float = -5.8 + side*(.10+row*.32)
    var y := 3.81 - row*.163
    var tile := cylinder(Vector3(-6.44+col*.246,y,z),.083,.35,Color("65716b") if (row+col)%4 else Color("788078"))
    tile.rotation_degrees.x = 90+side*27
 for i in range(22): cylinder(Vector3(-6.45+i*.377,3.88,-5.8),.14,.39,Color("73776b")).rotation_degrees.z = 90
 # Courtyard walls, leaving doorways and a route into the corn.
 stone_wall(Vector3(-7.5,0,-1.8),Vector3(.55,1.25,6.5))
 stone_wall(Vector3(6.6,0,-4.6),Vector3(5.4,1.25,.55))
 stone_wall(Vector3(-5.5,0,4.0),Vector3(4.5,.95,.5))
 stone_wall(Vector3(6.2,0,4.0),Vector3(4.5,.95,.5))
 # Irrigation ditch runs across foreground, crossed by a footbridge.
 box(Vector3(0,.018,5.4),Vector3(19,.035,1.45),Color("486f68"))
 for side in [-1,1]:
  for i in range(39): box(Vector3(-9.3+i*.49,.13,5.4+side*.82),Vector3(.46,.23,.31),Color("8b9180"))
 for i in range(35):
  box(Vector3(random.randf_range(-9,9),.045,random.randf_range(4.8,6)),Vector3(random.randf_range(.2,.7),.008,.025),Color("84a394"))
 for i in range(9): box(Vector3(.4,.17,4.55+i*.22),Vector3(1.75,.17,.20),Color("998065"),true)
 # Ditch is impassable apart from bridge.
 for x in [-5.2,5.75]:
  var barrier := box(Vector3(x,.4,5.4),Vector3(9,.8,1.2),Color.TRANSPARENT,true)
  barrier.visible = false
 # Summer corn plots on both sides and beyond the ditch.
 for side in [-1,1]:
  for row in range(11):
   for col in range(4):
    var x: float = side*(5.8+col*.72)+random.randf_range(-.13,.13)
    var z := -2.3+row*.61+random.randf_range(-.12,.12)
    if side < 0 and z < 1.6: x -= 1.5
    corn(Vector3(x,0,z), random.randf_range(1.45,2.12))
 for i in range(52):
  var x := random.randf_range(-9,9)
  if absf(x-.4)>1.3: corn(Vector3(x,0,random.randf_range(6.8,8.2)),random.randf_range(1.25,1.8))
 # Fruit tree and shaded grape arbor.
 cylinder(Vector3(4.65,1.45,-4.65),.25,2.9,Color("69543a"),.15)
 for i in range(19):
  leaf(Vector3(4.65+random.randf_range(-1.8,1.8),3.2+random.randf_range(-.3,.8),-4.65+random.randf_range(-1.1,1.1)),Vector3(1.2,.65,1),Color("6b8040") if i%3 else Color("8c994b"))
 for x in [1.8,5.5]:
  for z in [-3.7,-1.9]: cylinder(Vector3(x,1.18,z),.065,2.36,Color("776342"))
 for i in range(9): box(Vector3(1.8+i*.46,2.33,-2.8),Vector3(.065,.08,2.1),Color("786c45"))
 for i in range(30):
  leaf(Vector3(random.randf_range(1.7,5.6),2.4,random.randf_range(-3.6,-2)),Vector3(.52,.15,.46),Color("58763c") if i%2 else Color("749048"))
 # Well, jars, bench and planted edges.
 for i in range(12):
  var a := i*TAU/12
  box(Vector3(-5.8+cos(a)*.62,.42,-1.6+sin(a)*.62),Vector3(.34,.82,.3),Color("969789"),true).rotation.y = -a
 cylinder(Vector3(-5.8,.20,-1.6),.47,.12,Color("263c35"))
 for x in [-6.4,-5.2]: cylinder(Vector3(x,1.12,-1.6),.06,1.9,Color("6a5137"))
 box(Vector3(-5.8,2.08,-1.6),Vector3(1.45,.14,.18),Color("6a5137"))
 box(Vector3(.1,.55,-3.0),Vector3(1.5,.12,.52),Color("796043"))
 for x in [-.4,.6]: box(Vector3(x,.25,-3),Vector3(.12,.5,.36),Color("594633"))
 for p in [Vector3(-4.0,.3,-3.6),Vector3(.9,.3,-3.6),Vector3(5.8,.3,-3.5)]:
  cylinder(p,.27,.6,Color("806344"),.19)
 for i in range(95):
  var p := Vector3(random.randf_range(-9,9),.08,random.randf_range(-7,7))
  if absf(p.x)<4 and p.z>-3 and p.z<4: continue
  leaf(p,Vector3(.12,.12,.13),Color("728447"))
func stone_wall(origin: Vector3,size_value: Vector3):
 box(origin+Vector3(0,size_value.y*.5,0),size_value,Color("898777"),true)
 var along_x := size_value.x>size_value.z
 var length_value := size_value.x if along_x else size_value.z
 var rows := int(size_value.y/.25)
 var columns := int(length_value/.53)
 for row in range(rows):
  for col in range(columns):
   var offset := -length_value*.5+.27+col*.53+(.16 if row%2 else 0.0)
   var p := origin+Vector3(offset,(row+.5)*.25,0) if along_x else origin+Vector3(0,(row+.5)*.25,offset)
   box(p,Vector3(.50,.23,size_value.z+.04) if along_x else Vector3(size_value.x+.04,.23,.50),Color("a6a38e") if (row+col)%3 else Color("96947f"))
func corn(p: Vector3,height_value: float):
 cylinder(p+Vector3(0,height_value*.5,0),.028,height_value,Color("7d8542"),.012)
 for i in range(4):
  var side := -1 if i%2 else 1
  var mesh = leaf(p+Vector3(side*.22,.45+i*.28,0),Vector3(.45,.075,.16),Color("586e35") if i%2 else Color("75873e"))
  mesh.rotation.z = side*.5
 cylinder(p+Vector3(.09,height_value*.62,0),.065,.29,Color("c2aa4b"),.025)
 cylinder(p+Vector3(0,height_value+.07,0),.035,.25,Color("c7b775"),.008)
func add_actor(kind_value: String,p: Vector3,node_name: String):
 var actor = Actor.new()
 actor.kind = kind_value
 actor.name = node_name
 actor.position = p
 add_child(actor)
 actor.strike.connect(on_strike)
 return actor
func on_strike(actor):
 var a: float = actor.direction*PI/4
 var facing := Vector3(sin(a),0,cos(a))
 if fx: fx.spawn_slash(actor.global_position,facing)
 var victim = monster if actor == hero else hero
 if not is_instance_valid(victim): return
 var difference: Vector3 = victim.global_position-actor.global_position
 if difference.length()<1.95 and facing.dot(difference.normalized())>0.0:
  victim.damage(actor.global_position)
  if fx: fx.spawn_hit(victim.global_position+Vector3(0,.7,0))
func build_hud():
 var layer := CanvasLayer.new()
 add_child(layer)
 var panel := ColorRect.new()
 panel.color = Color(.09,.12,.09,.82)
 panel.position = Vector2(25,23)
 panel.size = Vector2(395,75)
 layer.add_child(panel)
 hud = Label.new()
 hud.position = Vector2(42,32)
 hud.add_theme_font_size_override("font_size",21)
 hud.add_theme_color_override("font_color",Color("f6e6bd"))
 layer.add_child(hud)
 var controls := Label.new()
 controls.position = Vector2(30,750)
 controls.text = "WASD / Arrows  Move    ·    Space / Click  Stick attack    ·    L  Summer / Late light    ·    R  Reset"
 controls.add_theme_font_size_override("font_size",17)
 controls.add_theme_color_override("font_color",Color("fff5d8"))
 controls.add_theme_color_override("font_shadow_color",Color("263327"))
 controls.add_theme_constant_override("shadow_offset_x",2)
 controls.add_theme_constant_override("shadow_offset_y",2)
 layer.add_child(controls)
func _process(_delta):
 if Input.is_action_just_pressed("light_toggle"): toggle_light()
 if Input.is_action_just_pressed("reset"):
  hero.position = hero.home
  hero.health = 3
  monster.position = monster.home
  monster.health = 3
 if hud:
  hud.text = "HENAN · A LONG SUMMER\n" + ("Late afternoon" if late else "Summer daylight") + "  /  Hybrid actor trial  /  HP " + str(hero.health)
func toggle_light():
 late = not late
 sun.rotation_degrees.x = -27 if late else -48
 sun.light_color = Color("ffcc88") if late else Color("ffe9bd")
 sun.light_energy = 1.10 if late else 1.25
 world_environment.environment.ambient_light_energy = .53 if late else .62
