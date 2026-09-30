extends "res://scripts/main.gd"

signal shot_fired(charged: bool)

const ProgressScript = preload("res://scripts/full_progress.gd")
const ChickenScript = preload("res://scripts/full_chicken.gd")
const PursuerScript = preload("res://scripts/full_pursuer.gd")
const BossScript = preload("res://scripts/full_boss.gd")
const MinionScript = preload("res://scripts/full_minion.gd")
const FullHudScript = preload("res://ui/full_hud.gd")
const Shapes = preload("res://scripts/entry_shapes.gd")
const SPAWN := Vector3(0, 0.05, 40)
const TIN := Vector3(-5, 0, 31)
const MOUTH := Vector3(0, 0, 22)
const GATE := Vector3(5, 0, 20)
const FENCE := Vector3(-5, 0, 3)
const BOARD := Vector3(12, 0, -9)
const CART := Vector3(16, 0, -13)
const LAUNCHER := Vector3(17, 0, -18)
const BOSS_ENTRY := Vector3(0, 0, -27)
const CORN_GUN := Vector3(5, 0, -33)
const WEATHER_ORDER := ["sunny", "rain", "snow"]
const CORN_CHARGE_SECONDS := 0.55
const CORN_FIRE_INTERVAL := 0.14
const CORN_SCATTER_INTERVAL := 0.40

var progress = ProgressScript.new()
var chicken: Node3D
var tin: Node3D
var pursuer: CharacterBody3D
var boss: StaticBody3D
var minions: Array[CharacterBody3D] = []
var props := {}
var weather := "sunny"
var gun_equipped := false
var charging := false
var charge_time := 0.0
var fire_cooldown := 0.0
var paused_menu := false
var audio_listener: AudioListener3D
var boss_gate_shape: CollisionShape3D
var boss_gate_mesh: MeshInstance3D
var cart_gate_shape: CollisionShape3D
var cart_gate_mesh: MeshInstance3D
var gun_model: Node3D
var gun_fx: Node3D
var fire_held := false
var mouse_aim_active := false
var aim_screen := Vector2.ZERO
var camera_kick := 0.0
var kick_clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_input()
	for action_key in [["throw_stone", KEY_F], ["switch_weapon", KEY_Q], ["weather_cycle", KEY_F6]]:
		if not InputMap.has_action(action_key[0]):
			InputMap.add_action(action_key[0])
		var event := InputEventKey.new()
		event.physical_keycode = action_key[1]
		if not InputMap.action_has_event(action_key[0], event):
			InputMap.action_add_event(action_key[0], event)
	if not InputMap.has_action("charge_shot"):
		InputMap.add_action("charge_shot")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	if not InputMap.action_has_event("charge_shot", right_click):
		InputMap.action_add_event("charge_shot", right_click)
	if ResourceLoader.exists("res://environment/full_field.gd"):
		environment = load("res://environment/full_field.gd").new()
		environment.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(environment)
	else:
		build_fallback_ground()
		push_warning("M2 temporary floor: full_field.gd is not delivered")
	player = PlayerScript.new()
	player.name = "Boy"
	player.spawn_position = SPAWN
	player.world_min = Vector2(-27.5, -47.5)
	player.world_max = Vector2(27.5, 47.5)
	player.attack_group = "full_enemies"
	add_child(player)
	player.collision_mask = 1 | 4
	player.struck.connect(on_branch_strike)
	build_gun_visual()
	gun_fx = load("res://weapons/corn_gun_fx.gd").new()
	gun_fx.name = "CornGunEffects"
	add_child(gun_fx)
	shot_fired.connect(on_corn_shot_feedback)
	chicken = ChickenScript.new()
	chicken.name = "HarmlessChicken"
	add_child(chicken)
	tin = make_prop("MarbleTin", TIN, "弹珠铁盒", Color("86978a"), Vector3(0.34, 0.18, 0.28))
	props["tin"] = tin
	props["mouth"] = make_marker("WaterMouth", MOUTH, "清理堵住的水口", Color("87b2a0"))
	props["gate"] = make_marker("SluiceGate", GATE, "打开水闸", Color("92b8a2"))
	props["fence"] = make_marker("LowFence", FENCE, "翻过矮栏", Color("d1b777"))
	props["board"] = make_prop("WoodBoard", BOARD, "旧木板", Color("a78653"), Vector3(0.92, 0.11, 0.35))
	props["cart"] = make_marker("FarmCart", CART, "垫轮移动板车", Color("caa974"))
	props["launcher"] = make_prop("OldLauncher", LAUNCHER, "旧发射器", Color("8a8468"), Vector3(0.65, 0.28, 0.45))
	props["corn_gun"] = make_prop("CornGunParts", CORN_GUN, "组合玉米枪", Color("efca78"), Vector3(0.8, 0.32, 0.55))
	make_fence_collision()
	make_cart_blocker()
	make_boss_gate()
	pursuer = PursuerScript.new()
	pursuer.name = "CornfieldPursuer"
	add_child(pursuer)
	pursuer.strike_attempt.connect(on_player_hurt)
	pursuer.telegraphed.connect(func(): hud.show_message("田鼠停下来了，快侧移或翻过矮栏！", 1.5))
	boss = BossScript.new()
	boss.name = "FieldScarecrow"
	add_child(boss)
	boss.strike_attempt.connect(on_player_hurt)
	boss.summon_requested.connect(summon_minions)
	boss.skill_warned.connect(on_boss_warned)
	boss.hit_received.connect(on_boss_hit)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15.0
	camera.near = 0.1
	camera.far = 170.0
	add_child(camera)
	camera.current = true
	audio_listener = AudioListener3D.new()
	audio_listener.position.y = 0.7
	player.add_child(audio_listener)
	audio_listener.make_current()
	hud = FullHudScript.new()
	add_child(hud)
	hud.resume_requested.connect(func(): set_paused(false))
	hud.retry_requested.connect(reset_run)
	hud.weather_requested.connect(set_weather)
	reset_run()

func make_prop(name: String, at: Vector3, title: String, color: Color, size: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.position = at
	add_child(node)
	Shapes.box(node, Vector3(0, size.y * 0.5 + 0.02, 0), size, color)
	var caption := Shapes.caption(node, "E · " + title, maxf(0.75, size.y + 0.45))
	caption.name = "Hint"
	caption.visible = false
	var ring := Shapes.ring(node, maxf(0.45, size.x * 0.7), Color("f0d38c"))
	ring.name = "Ring"
	ring.visible = false
	return node

func make_marker(name: String, at: Vector3, title: String, color: Color) -> Node3D:
	var node := Node3D.new()
	node.name = name
	node.position = at
	add_child(node)
	var caption := Shapes.caption(node, "E · " + title, 1.15, color)
	caption.name = "Hint"
	caption.visible = false
	var ring := Shapes.ring(node, 0.65, color)
	ring.name = "Ring"
	ring.visible = false
	return node

func make_fence_collision() -> void:
	var fence := StaticBody3D.new()
	fence.name = "VaultFenceCollision"
	fence.position = FENCE
	add_child(fence)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 0.7, 0.25)
	collider.shape = box
	collider.position.y = 0.35
	fence.add_child(collider)

func make_boss_gate() -> void:
	var gate := StaticBody3D.new()
	gate.name = "BossApproachGate"
	gate.position = BOSS_ENTRY
	add_child(gate)
	boss_gate_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(55.0, 2.0, 0.4)
	boss_gate_shape.shape = box
	boss_gate_shape.position.y = 1.0
	gate.add_child(boss_gate_shape)
	boss_gate_mesh = Shapes.box(gate, Vector3(0, 0.52, 0), Vector3(55.0, 1.05, 0.42), Color("8f7452"))

func make_cart_blocker() -> void:
	var gate := StaticBody3D.new()
	gate.name = "CartShedBlocker"
	gate.position = Vector3(17, 0, -15.7)
	add_child(gate)
	cart_gate_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.25, 1.15, 0.38)
	cart_gate_shape.shape = box
	cart_gate_shape.position.y = 0.58
	gate.add_child(cart_gate_shape)
	cart_gate_mesh = Shapes.box(gate, Vector3(0, 0.71, 0), Vector3(6.25, 0.16, 0.35), Color("9b744b"))
	for side in [-2.8, 2.8]:
		Shapes.box(gate, Vector3(side, 0.55, 0), Vector3(0.13, 1.1, 0.13), Color("795739"))

func build_gun_visual() -> void:
	gun_model = load("res://weapons/corn_gun_visual.gd").new()
	gun_model.name = "CornGunInHand"
	add_child(gun_model)
	update_weapon_visual()

func update_weapon_visual() -> void:
	player.ranged_stance = gun_equipped and progress.corn_gun
	if not player.ranged_stance:
		player.aim_direction = Vector3.ZERO
	if gun_model:
		gun_model.visible = gun_equipped and progress.corn_gun
	if player and player.branch_pivot and player.branch_pivot.has_node("Branch"):
		player.branch_pivot.get_node("Branch").visible = not (gun_equipped and progress.corn_gun)
	update_gun_transform()

func update_gun_transform() -> void:
	if not is_instance_valid(gun_model) or not is_instance_valid(player):
		return
	# The grip follows the actual hand; the barrel remains aligned with the aim.
	gun_model.global_position = player.branch_pivot.global_position
	gun_model.global_basis = Basis.looking_at(player.facing, Vector3.UP)
	gun_model.set_charge(clampf(charge_time / CORN_CHARGE_SECONDS, 0, 1) if charging else 0.0)

func cancel_gun_input(reset_aim := false) -> void:
	fire_held = false
	charging = false
	charge_time = 0.0
	if is_instance_valid(gun_model):
		gun_model.set_charge(0.0)
	if is_instance_valid(gun_fx):
		gun_fx.set_charge(Vector3.ZERO, 0.0)
	if reset_aim:
		mouse_aim_active = false
		player.aim_direction = Vector3.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(player):
		cancel_gun_input()

func update_corn_aim() -> void:
	if not gun_equipped or not progress.corn_gun or not mouse_aim_active:
		return
	var from: Vector3 = camera.project_ray_origin(aim_screen)
	var ray: Vector3 = camera.project_ray_normal(aim_screen)
	var point = Plane(Vector3.UP, player.global_position.y + 0.45).intersects_ray(from, ray)
	# A visible body sits above the ground plane. Aim through its actual collider
	# so a close diagonal click on a head or bullseye still points at that actor.
	var query := PhysicsRayQueryParameters3D.create(from, from + ray * camera.far, 1 | 4)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider.is_in_group("full_enemies") and hit.collider.get("active") != false:
		point = hit.collider.global_position
	if point == null:
		return
	var direction: Vector3 = point - player.global_position
	direction.y = 0
	if direction.length_squared() > 0.025:
		player.aim_direction = direction.normalized()
		player.facing = player.aim_direction

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("reset"):
		reset_run()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if progress.outcome == "playing":
			set_paused(not paused_menu)
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused or progress.outcome != "playing":
		return
	if event.is_action_pressed("night"):
		set_night(not night)
	elif event.is_action_pressed("weather_cycle"):
		set_weather(WEATHER_ORDER[(WEATHER_ORDER.find(weather) + 1) % WEATHER_ORDER.size()])
	elif event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("throw_stone"):
		throw_stone()
	elif event.is_action_pressed("switch_weapon"):
		if progress.corn_gun:
			cancel_gun_input(true)
			gun_equipped = not gun_equipped
			update_weapon_visual()
			hud.show_message("玉米枪在手 · 按住左键连射，右键蓄力后松开散射。" if gun_equipped else "换回树枝剑。", 2.0)
		else:
			hud.show_message("旧发射器还缺一件东西。先用树枝应对。", 2.0)
	elif event.is_action_pressed("attack"):
		if gun_equipped:
			if event is InputEventMouseButton:
				aim_screen = event.position
				mouse_aim_active = true
				update_corn_aim()
			fire_held = true
			if not charging:
				fire_gun(false)
		else:
			player.request_attack()
	elif event.is_action_pressed("charge_shot"):
		if gun_equipped and progress.corn_gun:
			if event is InputEventMouseButton:
				aim_screen = event.position
				mouse_aim_active = true
				update_corn_aim()
			charging = true
			charge_time = 0

func _input(event: InputEvent) -> void:
	if event.is_action_released("attack"):
		fire_held = false
	if event is InputEventMouseMotion and gun_equipped and progress.corn_gun and not get_tree().paused and progress.outcome == "playing":
		aim_screen = event.position
		mouse_aim_active = true
		update_corn_aim()
	# Mouse release may be consumed by GUI routing; an active charge must never stick.
	if event.is_action_released("charge_shot") and charging:
		if not get_tree().paused and progress.outcome == "playing":
			fire_gun(charge_time >= CORN_CHARGE_SECONDS)
		charging = false
		charge_time = 0

func _physics_process(delta: float) -> void:
	if get_tree().paused or progress.outcome != "playing":
		return
	progress.tick(delta)
	fire_cooldown = maxf(0, fire_cooldown - delta)
	update_corn_aim()
	if charging:
		charge_time = minf(2.0, charge_time + delta)
	elif fire_held:
		fire_gun(false)
	if not progress.chicken_seen and flat_distance(player.position, chicken.position) < 2.5:
		if progress.see_chicken():
			chicken.discovered = true
			hud.show_message("原来是小鸡，一点也不危险。\n沿入口左边找回弹珠铁盒。", 4.0)
	if progress.canal_open and player.position.z < 13 and not progress.dense_entered:
		progress.enter_dense()
		hud.show_message("玉米里有脚步声。F 投石引开田鼠，或靠近矮栏按 E 翻过去。", 4.0)
	if progress.launcher_taken and player.position.z <= -26.8 and not progress.boss_active:
		if progress.enter_boss():
			boss.active = true
			hud.show_message("稻草人在动！留意预警，趁收招时挥枝。", 4.0)
			sync_environment()
	pursuer.player_position = player.global_position
	boss.player_position = player.global_position
	update_hints()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if not get_tree().paused:
		update_camera(delta)
		kick_clock += delta
		camera_kick = move_toward(camera_kick, 0.0, delta * 0.8)
		camera.h_offset = sin(kick_clock * 83.0) * camera_kick
		camera.v_offset = cos(kick_clock * 61.0) * camera_kick * 0.55
		update_gun_transform()
		if gun_fx:
			gun_fx.set_charge(gun_model.muzzle.global_position, clampf(charge_time / CORN_CHARGE_SECONDS, 0, 1) if charging else 0.0)
		audio_listener.global_basis = camera.global_basis
		if environment:
			environment.set_player_position(player.global_position)
			if environment.has_method("set_actor_sources"):
				var far_source := Vector3(1000, 0, 1000)
				var sources: Array[Vector3] = [chicken.global_position, pursuer.global_position if pursuer.active else far_source, boss.global_position if boss.active else far_source]
				for minion in minions:
					if is_instance_valid(minion) and minion.active:
						sources.append(minion.global_position)
				environment.set_actor_sources(sources)
	hud.update_full(progress, context_text(), weather, night, gun_equipped, charge_time if charging else -1.0)
	if hud.has_method("update_corn_aim"):
		hud.update_corn_aim(aim_screen, mouse_aim_active and gun_equipped and progress.outcome == "playing" and not get_tree().paused, clampf(charge_time / CORN_CHARGE_SECONDS, 0, 1) if charging else 0.0)
	var use_reticle: bool = mouse_aim_active and gun_equipped and progress.outcome == "playing" and not get_tree().paused and get_window().has_focus() and get_viewport().get_visible_rect().has_point(get_viewport().get_mouse_position())
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if use_reticle else Input.MOUSE_MODE_VISIBLE

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func near(point: Vector3, radius: float = 2.0) -> bool:
	return flat_distance(player.position, point) <= radius

func update_hints() -> void:
	set_hint("tin", not progress.tin_taken and near(TIN, 2.7))
	set_hint("mouth", not progress.mouth_cleared and near(MOUTH, 2.7))
	set_hint("gate", not progress.canal_open and near(GATE, 2.7))
	set_hint("fence", progress.dense_entered and near(FENCE, 2.6))
	set_hint("board", not progress.board_taken and near(BOARD, 2.7))
	set_hint("cart", not progress.cart_moved and near(CART, 2.7))
	set_hint("launcher", not progress.launcher_taken and near(LAUNCHER, 2.7))
	set_hint("corn_gun", progress.corn_spilled and not progress.corn_gun and near(CORN_GUN, 3.1))

func set_hint(key: String, value: bool) -> void:
	var prop: Node3D = props[key]
	prop.get_node("Hint").visible = value and prop.visible
	prop.get_node("Ring").visible = value and prop.visible

func context_text() -> String:
	if progress.outcome == "lost":
		return "体力用完了 · 按 R 再出发"
	if progress.outcome == "won":
		return "荒田恢复平静 · 按 R 可以重走一遍"
	if near(CORN_GUN, 3.0) and progress.corn_spilled and not progress.corn_gun:
		return "[ E ] 将旧发射器与玉米组合成玉米枪"
	if near(TIN) and not progress.tin_taken:
		return "[ E ] 拾起弹珠铁盒" if progress.chicken_seen else "先看看入口旁玉米里的小鸡"
	if near(MOUTH) and not progress.mouth_cleared:
		return "[ E ] 清理堵塞的水口"
	if near(GATE) and not progress.canal_open:
		return "[ E ] 打开水闸" if progress.mouth_cleared else "先去水口清理堵塞"
	if near(FENCE, 2.5) and progress.dense_entered:
		return "[ E ] 翻过矮栏 · 田鼠不会立刻追过来"
	if near(BOARD) and not progress.board_taken:
		return "[ E ] 拿起旧木板"
	if near(CART) and not progress.cart_moved:
		return "[ E ] 用木板垫轮，移动板车" if progress.board_taken else "板车轮子卡住了，先找块木板"
	if near(LAUNCHER) and not progress.launcher_taken:
		return "[ E ] 取走棚里的旧发射器" if progress.cart_moved else "先把板车移开，才能进棚"
	if progress.boss_active:
		if progress.corn_gun:
			return "玉米枪已解锁 · Q 切换武器；按住左键连射，右键蓄力后松开近距散射"
		return "稻草人收招时靠近挥枝；看到玉米散落后去储存架按 E 组合"
	if not progress.chicken_seen:
		return "入口左边的玉米在动，靠近看看是不是小鸡"
	if not progress.tin_taken:
		return "沿入口左边的小路找弹珠铁盒（西侧、前方）"
	if not progress.canal_open:
		return "沿路去水渠，先清水口，再开闸门"
	if not progress.board_taken:
		return "过桥后沿北路穿过高密玉米，到东北农具区找旧木板"
	if not progress.cart_moved:
		return "木板在手，去农具区的板车旁垫轮（东侧）"
	if not progress.launcher_taken:
		return "板车移开了，进入后方工具棚取旧发射器"
	return "继续向北，进入荒田"

func interact() -> void:
	if get_tree().paused or progress.outcome != "playing":
		return
	var message := "这里暂时没有可操作的东西。"
	if near(CORN_GUN, 2.7) and progress.corn_spilled and not progress.corn_gun:
		if progress.make_corn_gun():
			player.play_context_action("pick_up")
			gun_equipped = true
			update_weapon_visual()
			props["corn_gun"].visible = false
			message = "玉米枪组好了！鼠标瞄准，按住左键连射；右键蓄力后松开，近距离散射。"
			if progress.boss_defeated and progress.win():
				finish_run()
	elif near(TIN, 1.8) and not progress.tin_taken:
		if progress.take_tin():
			player.play_context_action("pick_up")
			tin.visible = false
			message = "弹珠铁盒找到了。沿大路去水渠。"
		else:
			message = "先靠近入口玉米里的小鸡，看看是什么动静。"
	elif near(MOUTH, 2.0) and not progress.mouth_cleared:
		if progress.clear_mouth():
			player.play_context_action("interact")
			message = "水口清通了，去旁边的闸门开闸。"
		else:
			message = "先找回弹珠铁盒，再沿路到水口。"
	elif near(GATE, 2.0) and not progress.canal_open:
		if progress.open_canal():
			player.play_context_action("interact")
			message = "闸门打开了，北边的路通了。"
		else:
			message = "水口还堵着，先清理。"
	elif near(FENCE, 2.25) and progress.dense_entered:
		if progress.vault_fence():
			player.play_context_action("vault")
			player.position = Vector3(FENCE.x, 0.05, FENCE.z - 1.2 if player.position.z >= FENCE.z else FENCE.z + 1.2)
			player.velocity = Vector3.ZERO
			pursuer.mode = "return"
			message = "翻过矮栏！田鼠一时追不上。"
	elif near(BOARD, 2.0) and not progress.board_taken:
		if progress.take_board():
			player.play_context_action("pick_up")
			props["board"].visible = false
			message = "捡到一块旧木板，可以用来垫板车的轮子。"
		else:
			message = "先沿水渠北边的小路过来。"
	elif near(CART, 2.1) and not progress.cart_moved:
		if progress.move_cart():
			player.play_context_action("push")
			message = "轮子垫好了！板车让开棚门。"
		else:
			message = "板车卡住了，附近找块旧木板。"
	elif near(LAUNCHER, 2.1) and not progress.launcher_taken:
		if progress.take_launcher():
			player.play_context_action("pick_up")
			props["launcher"].visible = false
			message = "拿到旧发射器，似乎还缺合适的弹药。去北边看看。"
		else:
			message = "板车堵着棚门，先把它移开。"
	hud.show_message(message, 3.4)
	sync_environment()

func throw_stone() -> void:
	if get_tree().paused or progress.outcome != "playing":
		return
	if not progress.throw_stone():
		hud.show_message("先过水渠，到了高密玉米区再用石头引开动静。", 2.4)
		return
	var point: Vector3 = player.global_position + player.facing * 4.0
	point.y = 0.05
	if flat_distance(point, pursuer.position) < 10.0:
		pursuer.distract(point)
	show_projectile(player.global_position + Vector3.UP * 0.8, point + Vector3.UP * 0.2, Color("b8a889"), 0.28)
	hud.show_message("石子落进玉米里，田鼠朝声响跑去了。", 2.2)

func fire_gun(charged: bool) -> void:
	if get_tree().paused or progress.outcome != "playing" or not progress.corn_gun or not gun_equipped or fire_cooldown > 0:
		return
	fire_cooldown = CORN_SCATTER_INTERVAL if charged else CORN_FIRE_INTERVAL
	var reach := 5.5 if charged else 9.0
	var amount := 3 if charged else 1
	update_gun_transform()
	var muzzle: Vector3 = gun_model.muzzle.global_position
	shot_fired.emit(charged)
	var candidates: Array[Node3D] = []
	for target in get_tree().get_nodes_in_group("full_enemies"):
		if target.is_queued_for_deletion() or target.get("active") == false:
			continue
		if target == boss and (not boss.active or boss.collision_layer == 0):
			continue
		var offset: Vector3 = target.global_position - player.global_position
		offset.y = 0
		var distance := offset.length()
		var depth: float = player.facing.dot(offset)
		var side: float = absf(player.facing.cross(offset).y)
		var radius := 0.64 if target == boss else 0.34
		var in_arc: bool = depth > 0 and (depth / maxf(distance, 0.01) >= cos(deg_to_rad(30.0)) if charged else side <= radius + depth * 0.025)
		if distance <= reach and distance > 0.01 and in_arc and player.can_reach(target, reach):
			candidates.append(target)
	if charged:
		# A blast is one attack, even when several visual grains cross a target.
		for index in 7:
			var direction: Vector3 = Basis(Vector3.UP, deg_to_rad((index - 3) * 9.0)) * player.facing
			var end: Vector3 = clip_corn_tracer(muzzle, muzzle + direction * reach)
			gun_fx.tracer(muzzle, end, true, index)
		for target in candidates:
			apply_corn_hit(target, amount, true)
	else:
		var nearest: Node3D = null
		var nearest_distance := INF
		for target in candidates:
			var distance := flat_distance(target.global_position, player.global_position)
			if distance < nearest_distance:
				nearest = target
				nearest_distance = distance
		var end: Vector3 = clip_corn_tracer(muzzle, muzzle + player.facing * reach)
		if nearest:
			end = corn_target_point(nearest)
			gun_fx.tracer(muzzle, end, false, 0)
			apply_corn_hit(nearest, amount, false)
		else:
			gun_fx.tracer(muzzle, end, false, 0)
			if muzzle.distance_to(end) < reach - 0.1:
				gun_fx.impact(end, player.facing, false)

func clip_corn_tracer(from: Vector3, to: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else to

func corn_target_point(target: Node3D) -> Vector3:
	return target.global_position + Vector3.UP * (1.0 if target == boss else 0.42)

func apply_corn_hit(target: Node3D, amount: int, charged: bool) -> void:
	var point := corn_target_point(target)
	if target == boss:
		var before: int = progress.boss_hp
		boss.receive_projectile(amount)
		if before == progress.boss_hp:
			return
	elif target.has_method("receive_projectile"):
		target.receive_projectile(amount)
	else:
		target.receive_hit(player.facing)
	gun_fx.impact(point, player.facing, charged)
	gun_fx.damage_number(point + Vector3.UP * 0.3, amount, charged)
	if hud.has_method("show_corn_hit"):
		hud.show_corn_hit(charged)

func on_corn_shot_feedback(charged: bool) -> void:
	gun_model.kick(charged)
	gun_fx.muzzle_flash(gun_model.muzzle.global_position, player.facing, charged)
	camera_kick = maxf(camera_kick, 0.075 if charged else 0.023)

func show_projectile(from: Vector3, to: Vector3, color: Color, duration: float, pellet_name := "FieldStone") -> void:
	var pellet := MeshInstance3D.new()
	pellet.name = pellet_name
	var mesh := SphereMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.22
	pellet.mesh = mesh
	pellet.material_override = Shapes.material(color, true)
	add_child(pellet)
	pellet.global_position = from
	var tween := create_tween().bind_node(pellet)
	tween.tween_property(pellet, "global_position", to, duration)
	tween.tween_callback(pellet.queue_free)

func on_branch_strike(target: Node3D) -> void:
	if target == boss:
		if boss.hit_cooldown <= 0:
			hud.show_message("树枝碰到了稻草人；趁它收招时再挥。", 1.2)
	else:
		hud.show_message("田鼠被树枝赶开了。", 1.2)

func on_boss_warned(skill: String) -> void:
	var words := {"sweep_windup":"稻草人举起了横杆！后退避开横扫。", "burrow_windup":"它钻进玉米里了！看玉米移动和地上的预警。", "summon_windup":"它正在召来小田鼠，准备迎击。"}
	hud.show_message(words.get(skill, "留意它的动作。"), 1.6)

func on_boss_hit(amount: int) -> void:
	if progress.hurt_boss(amount):
		if progress.corn_spilled and not progress.corn_gun and progress.boss_hp == progress.max_boss_hp / 2:
			props["corn_gun"].visible = true
			boss.stagger_for_gun()
			hud.show_message("它撞坏了玉米储存架！趁它停住，去右侧按 E 组合玉米枪。", 5.0)
		elif progress.boss_defeated:
			boss.active = false
			if progress.win():
				finish_run()
		sync_environment()

func summon_minions() -> void:
	if progress.outcome != "playing" or not progress.boss_active:
		return
	for minion in minions:
		if is_instance_valid(minion):
			minion.retreat()
	minions.clear()
	for index in (2 if boss.skill_index < 5 else 3):
		var minion = MinionScript.new()
		minion.name = "SummonedMouse%d" % index
		minion.position = boss.position + Vector3(-2.0 + index * 2.0, 0.05, 1.5)
		minion.player = player
		add_child(minion)
		minion.strike_attempt.connect(on_player_hurt)
		minions.append(minion)
	hud.show_message("田鼠从玉米里跑出来了，先拉开距离！", 2.0)

func on_player_hurt() -> void:
	if get_tree().paused or progress.outcome != "playing":
		return
	if progress.take_damage():
		player.play_context_action("hurt")
		hud.show_damage()
		hud.show_message("体力少了一格，短时间内不会再次受伤。", 1.8)
		if progress.outcome == "lost":
			finish_run()

func finish_run() -> void:
	paused_menu = false
	cancel_gun_input()
	player.cancel_actions()
	for minion in minions:
		if is_instance_valid(minion):
			minion.retreat()
	minions.clear()
	hud.reset_feedback()
	hud.show_menu(progress.outcome, progress)
	sync_environment()
	get_tree().paused = true

func set_paused(value: bool) -> void:
	if progress.outcome != "playing":
		return
	paused_menu = value
	cancel_gun_input()
	get_tree().paused = value
	if value:
		hud.show_menu("pause", progress)
	else:
		hud.hide_menu()

func set_weather(value: String) -> void:
	if value not in WEATHER_ORDER:
		return
	weather = value
	if environment and environment.has_method("set_weather"):
		environment.set_weather(value)
	if hud and progress.outcome == "playing":
		hud.show_message({"sunny":"阳光又照进田里。", "rain":"雨落在玉米叶上。", "snow":"雪花轻轻落下。"}[value], 1.6)

func reset_run() -> void:
	get_tree().paused = false
	paused_menu = false
	cancel_gun_input(true)
	if gun_fx:
		gun_fx.clear_effects()
	if gun_model:
		gun_model.reset_visual()
	camera_kick = 0
	camera.h_offset = 0
	camera.v_offset = 0
	progress.reset()
	player.reset_player()
	chicken.reset_chicken()
	pursuer.reset_pursuer()
	boss.reset_boss()
	for minion in minions:
		if is_instance_valid(minion):
			minion.retreat()
	minions.clear()
	gun_equipped = false
	update_weapon_visual()
	charging = false
	charge_time = 0
	fire_cooldown = 0
	for key in ["tin", "board", "launcher"]:
		props[key].visible = true
	props["corn_gun"].visible = false
	boss_gate_shape.set_deferred("disabled", false)
	boss_gate_mesh.visible = true
	cart_gate_shape.set_deferred("disabled", false)
	cart_gate_mesh.visible = true
	hud.reset_feedback()
	if environment and environment.has_method("reset_field"):
		environment.reset_field()
	set_night(false)
	set_weather("sunny")
	sync_environment()
	camera_focus = player.position + Vector3(0, 0.7, -2.8)
	update_camera(1.0)
	hud.update_full(progress, context_text(), weather, night, gun_equipped)
	hud.show_message("从入口出发，看看玉米里轻轻晃动的是什么。", 4.0)

func sync_environment() -> void:
	boss_gate_shape.set_deferred("disabled", progress.launcher_taken)
	boss_gate_mesh.visible = not progress.launcher_taken
	cart_gate_shape.set_deferred("disabled", progress.cart_moved)
	cart_gate_mesh.visible = not progress.cart_moved
	if environment and environment.has_method("set_progress"):
		environment.set_progress(progress.environment_flags())
