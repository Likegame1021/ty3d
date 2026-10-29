extends Node3D
## 3D chapter adapter: shares save transactions and UI, never the old screen physics.

const CornAudio = preload("res://weapons/corn_gun_fx.gd")
const RunState = preload("res://scripts/cornfield/run_state.gd")
const UI = preload("res://scripts/cornfield/game_ui.gd")
const Player = preload("res://scripts/cornfield/player.gd")
const World = preload("res://scripts/cornfield/room_world.gd")
const Dungeon = preload("res://scripts/cornfield/dungeon.gd")
const Director = preload("res://scripts/cornfield/encounter_director.gd")
const Village = preload("res://scripts/cornfield/village.gd")
const Feedback = preload("res://scripts/cornfield/combat_feedback.gd")
const Services = preload("res://scripts/cornfield/service_catalog.gd")
const BuildCatalog = preload("res://scripts/cornfield/build_catalog.gd")
const Loot = preload("res://scripts/cornfield/field_loot.gd")
const NAMES := {"ANVIL":"田头工具堆","LEVEL":"老树歇脚","REWARD":"田间拾遗","ELITE":"虫王盘踞","EVENT":"田边奇遇","SHOP":"桂花小卖点","BOSS":"玉米螟巢穴"}
const OPPOSITE := {"north":"south","south":"north","east":"west","west":"east"}
const INWARD := {"north":Vector3.BACK,"south":Vector3.FORWARD,"east":Vector3.LEFT,"west":Vector3.RIGHT}

var _quit_in_progress := false
var pending_terminal := ""
var _level_content_error := ""
var prepared_weapon := "stick"
var weapon_controller: Node3D
var feedback: Node3D
var _tutorial_step := 0
var _tutorial_seen := false
var _last_boss_stage := 0
var save_path := "user://cornfield_chapter_v1.json"
var test_mode := false
var run: RefCounted
var ui: CanvasLayer
var gameplay: Node3D
var camera: Camera3D
var player: CharacterBody3D
var world: Node3D
var director: Node3D
var village: Node3D
var dungeon: Dictionary = {}
var room_states: Dictionary = {}
var current_room := ""
var phase := "village"
var node_complete := false
var next_offers: Array = []
var focused := true
var room_change_pending := false
var _room_epoch := 0
var _door_ticket := 0
var _pending_door_transition: Dictionary = {}
var last_door_time := 0.0
var gameplay_time := 0.0
var save_timer := 0.0
var damage_buff_time := 0.0
var speed_buff_time := 0.0
var service_marker: Label3D
var camera_target := Vector3.ZERO
var perf_samples: Array[float] = []
var recovered_save_paths: Array[String] = []
var save_recovery_blocked := false

func _ready() -> void:
	get_window().title = "田埂上的暑假 · 3D 玉米地"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_inputs()
	get_tree().auto_accept_quit = false
	run = RunState.new(save_path)
	var loaded: bool = run.load_save()
	recovered_save_paths.append_array(run.recovered_paths)
	save_recovery_blocked = run.recovery_error
	if not loaded and (FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path+".bak")):
		save_recovery_blocked = not _preserve_unreadable_save()
	gameplay = Node3D.new()
	gameplay.name = "Gameplay"
	gameplay.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(gameplay)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("afc6b0")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("fff1cc")
	environment.environment.ambient_light_energy = 0.55
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-28,0)
	sun.light_color = Color("ffe5b2")
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	# Fixed orthographic view: one full-resolution shadow projection avoids
	# redundant perspective cascades. Far plane bounds it to visible space.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 15.0
	camera.near = 0.1
	camera.far = 55
	camera.rotation_degrees = Vector3(-41.848,45,0)
	add_child(camera)
	camera.make_current()
	ui = UI.new()
	ui.input_guard = func() -> bool: return focused
	ui.controls_hint = "WASD 跑动 · 松开即停 · 左键攻击 · E 互动 · M 地图 · N 路线 · Esc 暂停"
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	var preferences := ConfigFile.new()
	_tutorial_seen = preferences.load("user://cornfield_tutorial_v1.cfg") == OK and bool(preferences.get_value("onboarding","seen",false))
	_show_village()
	if run.data.status in ["FAILED","FORFEIT","VICTORY_PENDING_SETTLEMENT"]:
		_settlement()
	elif not test_mode:
		_show_welcome()
	if loaded and not recovered_save_paths.is_empty():
		ui.toast("已从完整备份恢复。损坏的原档已另存保留，没有覆盖。")
	elif run.recovery_error:
		ui.toast("已读取备份，但损坏原档尚未安全保留；暂不能写入存档。")

func _setup_inputs() -> void:
	var keys := {"move_left":KEY_A,"move_right":KEY_D,"move_up":KEY_W,"move_down":KEY_S,"run":KEY_SHIFT,"interact":KEY_E,"map":KEY_M,"node_map":KEY_N,"pause":KEY_ESCAPE}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		if not InputMap.action_has_event(action,event):
			InputMap.action_add_event(action,event)
	if not InputMap.has_action("charge_shot"):
		InputMap.add_action("charge_shot")
	var secondary := InputEventMouseButton.new()
	secondary.button_index = MOUSE_BUTTON_RIGHT
	if not InputMap.action_has_event("charge_shot", secondary):
		InputMap.action_add_event("charge_shot", secondary)
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
	var attack := InputEventMouseButton.new()
	attack.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("attack",attack):
		InputMap.action_add_event("attack",attack)

func _process(delta: float) -> void:
	if _quit_in_progress:
		return
	if not is_instance_valid(player):
		return
	var active: bool = focused and phase == "floor" and ui.panel_kind not in ["pause","settlement","confirm"]
	run.tick(delta,active)
	if not get_tree().paused:
		gameplay_time += delta
		damage_buff_time = maxf(0,damage_buff_time-delta)
		speed_buff_time = maxf(0,speed_buff_time-delta)
		_sync_stats()
		if phase == "floor":
			_check_doors()
			_update_occlusion()
	save_timer += delta if active else 0.0
	if save_timer >= 10:
		save_timer = 0
		if not run.save():
			ui.toast("时长保存失败；当前游戏可以继续，退出前请重试。")
	_follow_camera(delta)
	_update_hud()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		_refresh_pause()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
		_refresh_pause()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()

func _unhandled_input(event: InputEvent) -> void:
	if _quit_in_progress:
		return
	if event.is_action_pressed("attack") and not event.is_echo() and not get_tree().paused and is_instance_valid(player) and player.weapon_id == "stick":
		player.request_attack()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if ui.panel_kind == "tutorial":
			_finish_tutorial()
		elif ui.opened and ui.panel_kind != "settlement":
			_close_panel()
		elif not ui.opened:
			_show_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("node_map") and phase == "floor":
		if ui.panel_kind == "route":
			_close_panel()
		elif ui.panel_kind in ["","map","service"]:
			_show_routes()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and phase == "floor":
		if ui.panel_kind == "map":
			_close_panel()
		elif not ui.opened:
			_show_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not ui.opened:
		_interact()
		get_viewport().set_input_as_handled()

func _refresh_pause() -> void:
	if not is_instance_valid(ui):
		return
	if is_instance_valid(player) and (not focused or ui.opened or phase == "settlement"):
		player.cancel_actions()
		if is_instance_valid(feedback):
			feedback.clear_all()
	if is_instance_valid(weapon_controller) and (not focused or ui.opened):
		weapon_controller.cancel_gun_input()
	get_tree().paused = _quit_in_progress or not focused or ui.opened
	if is_instance_valid(player):
		player.controls_enabled = not _quit_in_progress and focused and not ui.opened and phase != "settlement"

func _panel(title: String, body: String, choices: Array, kind: String = "service") -> void:
	ui.show_panel(title,body,choices,kind)
	_refresh_pause()

func _close_panel() -> void:
	ui.close_panel()
	_refresh_pause()

func _clear_space() -> void:
	_level_content_error = ""
	_reset_door_transition()
	if is_instance_valid(feedback):
		feedback.clear_all()
	if is_instance_valid(director):
		director.shutdown()
	for child in gameplay.get_children():
		gameplay.remove_child(child)
		child.queue_free()
	director = null
	weapon_controller = null
	feedback = null
	world = null
	village = null
	service_marker = null
	_last_boss_stage = 0
	ui.update_boss({})

func _spawn_player(at: Vector3) -> void:
	player = Player.new()
	gameplay.add_child(player)
	# Preparation uses the current branch; Continue preserves the saved run binding.
	var selected_weapon := str(run.data.weapon) if phase == "floor" else prepared_weapon
	player.configure(camera,selected_weapon)
	ui.controls_hint = "WASD 跑动 · 松开即停 · 左键%s · E 互动 · M 地图 · N 路线 · Esc 暂停" % ("挥砍" if selected_weapon == "stick" else "连射 · 右键蓄力")
	player.position = at+Vector3.UP*0.05
	player.spawn_position = player.position
	player.world_min = Vector2(0.25,0.25)
	player.world_max = (Vector2(world.definition.size) if is_instance_valid(world) else Village.SIZE)-Vector2.ONE*0.25
	if selected_weapon == "corn":
		weapon_controller = load("res://scripts/cornfield/weapon_controller.gd").new()
		weapon_controller.player = player
		weapon_controller.camera = camera
		weapon_controller.hud = ui
		gameplay.add_child(weapon_controller)
	player.hp = float(run.data.hp) if phase == "floor" else 100.0
	player.health_changed.connect(_health_changed)
	player.died.connect(_player_died)
	player.feedback_requested.connect(_feedback_event)
	if ui.has_method("refresh_controls_hint"):
		ui.refresh_controls_hint(selected_weapon)
	_sync_stats()
	camera_target = at+Vector3.UP*0.4
	_follow_camera(1.0)

func _show_village() -> void:
	_close_panel()
	phase = "village"
	current_room = ""
	_clear_space()
	_spawn_player(Village.SPAWN)
	village = Village.new()
	gameplay.add_child(village)
	village.install(player)
	ui.toast("村口出发点 · E 准备武器或出发 · Esc 打开菜单")

func _show_welcome() -> void:
	var choices: Array = []
	if run.data.status == "ACTIVE":
		choices.append({"text":"继续玉米地 · 第 %d 节点" % int(run.data.floor),"action":_continue_run})
	choices.append({"text":"带树枝出发","action":_prepare_and_start.bind("stick")})
	choices.append({"text":"带玉米枪出发","action":_prepare_and_start.bind("corn")})
	choices.append({"text":"先逛逛榆树湾","action":_close_panel})
	var recovery := ""
	if save_recovery_blocked:
		recovery = "\n旧档无法读取且恢复副本未保存，暂不能覆盖旧档。"
	elif not recovered_save_paths.is_empty():
		recovery = "\n旧档无法读取，原始内容已单独保留为恢复副本，可以开始新的一趟。"
	_panel("槐荫下，暑假正长", "穿过三片玉米地，带着见闻回家。\n前两片田里各有一处免费工具堆；想好这一趟怎么出手。\n"+ui.controls_hint+recovery,choices,"welcome")

func _prepare_and_start(weapon: String) -> void:
	prepared_weapon = weapon
	_request_new_run()

func _request_new_run() -> void:
	if run.data.status == "ACTIVE":
		_panel("重新出发？","当前这趟尚未结束。确认后先记录放弃，再开始新的一趟。",[{"text":"确认重新出发","action":_replace_run},{"text":"保留当前这趟","action":_close_panel}],"confirm")
	else:
		_start_new_run()

func _replace_run() -> void:
	if not run.end_run("FORFEIT") or not run.settle():
		_panel("旧的一趟尚未结算","保存失败，请重试；不会开始新的一趟。",[{"text":"重试结算并出发","action":_replace_run}],"confirm")
		_save_error("未能结束旧的一趟。")
		return
	_start_new_run()

func _start_new_run(seed_value: int = 0) -> bool:
	if save_recovery_blocked:
		_save_error("旧存档无法读取且备份未完成；原文件已保留，不能覆盖。")
		return false
	if not run.new_run(seed_value,prepared_weapon):
		_show_welcome()
		_save_error("未能创建新档。")
		return false
	_reset_door_transition()
	_level_content_error = ""
	pending_terminal = ""
	_close_panel()
	phase = "floor"
	dungeon.clear()
	room_states.clear()
	current_room = ""
	node_complete = false
	damage_buff_time = 0
	speed_buff_time = 0
	player.hp = 100
	_show_routes()
	return true

func _preserve_unreadable_save() -> bool:
	# Copy before permitting any new-run write, including the rolling .bak.
	var suffix := ".recovery_%d_%d" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
	for path: String in [save_path,save_path+".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var destination := path+suffix
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(destination)) != OK:
			return false
		if FileAccess.get_file_as_bytes(path) != FileAccess.get_file_as_bytes(destination):
			return false
		recovered_save_paths.append(destination)
	return true

func _continue_run() -> void:
	if run.data.status != "ACTIVE":
		return
	_reset_door_transition()
	_close_panel()
	phase = "floor"
	damage_buff_time = 0
	speed_buff_time = 0
	if str(run.data.selected).is_empty():
		dungeon.clear()
		node_complete = false
		_show_routes()
	else:
		_install_node(str(run.data.selected))
		_close_panel()
		_enter_room(str(dungeon.entry))

func _preview_offers(floor_number: int, ids: Array) -> Array:
	var result: Array = []
	for id in ids:
		var preview: Dictionary = Dungeon.generate(int(run.data.seed),floor_number,str(id),int(run.data.get("content_revision",2)))
		var service := Services.describe(str(id))
		result.append({"id":id,"title":service.get("title",id),"description":service.get("short_description",""),"room_count":preview.rooms.size(),"rooms":preview.rooms,"links":preview.links})
	return result

func _history(destination: int) -> Array:
	var records: Array = run.data.route_history.duplicate(true)
	if int(run.data.floor)<destination and not str(run.data.selected).is_empty():
		records.append({"floor":run.data.floor,"offers":run.data.offers,"selected":run.data.selected})
	var result: Array = []
	for record in records:
		result.append({"floor":record.floor,"offers":_preview_offers(int(record.floor),record.offers),"selected":record.selected})
	return result

func _show_routes() -> void:
	if not _can_travel_action("route"):
		return
	if not dungeon.is_empty() and not node_complete:
		ui.toast("先通过地图上的红色房间，才能传送到下一节点。")
		return
	if node_complete and int(run.data.floor) == 3:
		_finish_chapter()
		return
	var destination := int(run.data.floor)+(1 if node_complete else 0)
	var offers: Array = next_offers if node_complete else run.data.offers
	ui.show_route_choices({"floor":destination,"offers":_preview_offers(destination,offers),"previous_complete":node_complete,"history":_history(destination)},_choose_route,_close_panel)
	_refresh_pause()

func _choose_route(node: String) -> bool:
	if not _can_travel_action("route"):
		return false
	if node_complete:
		run.data.hp = player.hp
		if not run.advance_to_node(node,next_offers):
			_show_routes()
			_save_error("路线保存失败，仍留在当前节点。")
			return false
		damage_buff_time = 0
		speed_buff_time = 0
	elif not run.choose_route(node):
		_show_routes()
		_save_error("选择保存失败，未传送。")
		return false
	_install_node(node)
	_close_panel()
	_enter_room(str(dungeon.entry))
	if not test_mode and not _tutorial_seen and int(run.data.floor)==1:
		_show_tutorial(0)
	return true

func _install_node(node: String) -> void:
	_reset_door_transition()
	dungeon = Dungeon.generate(int(run.data.seed),int(run.data.floor),node,int(run.data.get("content_revision",2)))
	room_states.clear()
	for id in dungeon.rooms:
		room_states[id] = {"visited":false,"cleared":false,"resolved":false,"broken":{},"drops":{},"loot":0}
	node_complete = false
	next_offers.clear()
	run.data.visited = []

func _enter_room(id: String, from_side: String = "") -> void:
	if not dungeon.rooms.has(id):
		return
	if is_instance_valid(player) and phase == "floor" and not current_room.is_empty():
		run.data.hp = player.hp
	_clear_space()
	current_room = id
	room_change_pending = false
	last_door_time = gameplay_time
	var definition: Dictionary = dungeon.rooms[id]
	var state: Dictionary = room_states[id]
	state.visited = true
	if not run.data.visited.has(id):
		run.data.visited.append(id)
	world = World.new()
	gameplay.add_child(world)
	world.build(definition,state)
	world.set_exit_labels(World.exit_labels_for(dungeon,id))
	definition = world.definition
	dungeon.rooms[id] = definition
	var entry: Vector3 = definition.get("entry_position",Vector3(definition.size.x*0.5,0,definition.size.y*0.85))
	if not from_side.is_empty():
		entry = world.get_door_position(from_side)+INWARD[from_side]*4.0
	feedback = Feedback.new()
	gameplay.add_child(feedback)
	_spawn_player(entry)
	feedback.bind_player(player)
	world.set_occlusion_target(camera,player)
	_spawn_props(definition,state)
	if not state.cleared:
		director = Director.new()
		gameplay.add_child(director)
		director.encounter_error.connect(_show_content_error)
		director.cleared.connect(_room_cleared)
		director.enemy_defeated.connect(_enemy_defeated)
		director.boss_status.connect(_boss_status)
		director.feedback_requested.connect(_feedback_event)
		director.configure(world,player,definition,int(run.data.floor))
		director.set_spawn_visibility_ui(ui)
		if director.is_complete():
			_room_cleared()
	world.set_doors_open(bool(state.cleared))
	world.set_route_unlocked(node_complete)
	_make_service_marker(definition)
	_refresh_pause()
	ui.toast(str(definition.title)+(" · 红色通关房" if definition.get("completion",false) else " · 沿田埂推进，小心前方虫群"))

func _hostile_room() -> bool:
	return is_instance_valid(director) and not director.is_complete()

func _room_cleared() -> void:
	if not room_states.has(current_room) or room_states[current_room].cleared:
		return
	room_states[current_room].cleared = true
	var effects: Dictionary = run.build_effects()
	if float(effects.clear_heal)>0 and is_instance_valid(player) and player.hp>0 and pending_terminal!="FAILED" and str(dungeon.rooms[current_room].get("encounter","")) in ["swarm","combat","elite","boss"]:
		player.heal(float(effects.clear_heal))
		_feedback_event("pickup",{"position":player.position,"strength":1.0})
	world.set_doors_open(true)
	ui.update_boss({})
	var definition: Dictionary = dungeon.rooms[current_room]
	if definition.get("completion",false) and definition.get("encounter","") not in ["shop","event","service"]:
		_unlock_next()
	ui.toast("这片田埂清静了。绿色门已打开；M 可回访已清理的房间。")

func _unlock_next() -> void:
	if node_complete or not is_instance_valid(player) or player.hp<=0 or pending_terminal=="FAILED":
		return
	node_complete = true
	if is_instance_valid(world):
		world.set_route_unlocked(true)
	next_offers = run.next_node_offers()
	if int(run.data.floor) == 3:
		call_deferred("_finish_chapter")
	else:
		ui.toast("红色房间已通过。可以继续逛，按 N 查看下一节点，选择后才传送。")

# All travel mutations use this policy, including callbacks from paused map UI.
func _can_travel_action(action: String, target_room: String = "", ticket: int = -1) -> bool:
	if action not in ["door_request","door_commit","revisit","route"]:
		return false
	if not _can_mutate_floor() or _hostile_room():
		return false
	if room_change_pending and action!="door_commit":
		return false
	var allowed_panels: Array = ["","map","route"] if action=="route" else (["","map"] if action=="revisit" else [""])
	if ui.panel_kind not in allowed_panels or (ui.opened and ui.panel_kind==""):
		return false
	if get_tree().paused and not (ui.opened and ui.panel_kind in ["map","route"]):
		return false
	if action=="route":
		return dungeon.is_empty() or node_complete
	if not dungeon.get("rooms",{}).has(current_room) or not dungeon.rooms.has(target_room) or not is_instance_valid(world):
		return false
	if action=="revisit":
		return target_room!=current_room and dungeon.rooms.has(target_room) and room_states.has(target_room) and bool(room_states[target_room].visited) and bool(room_states[target_room].cleared)
	if action=="door_commit":
		if not room_change_pending or _pending_door_transition.is_empty() or int(_pending_door_transition.ticket)!=ticket:
			return false
		var request := _pending_door_transition
		if request.run_id!=run.data.run_id or int(request.floor)!=int(run.data.floor) or request.source!=current_room or int(request.epoch)!=_room_epoch or request.target!=target_room:
			return false
		if dungeon.rooms[current_room].doors.get(request.side,"")!=target_room:
			return false
	for side: String in dungeon.rooms[current_room].doors:
		if str(dungeon.rooms[current_room].doors[side])==target_room:
			var at: Vector3 = world.get_door_position(side)
			return Vector2(player.position.x-at.x,player.position.z-at.z).length()<1.3
	return false

func _can_mutate_floor() -> bool:
	return phase=="floor" and run.data.status=="ACTIVE" and focused and _level_content_error.is_empty() and pending_terminal.is_empty() and is_instance_valid(player) and player.hp>0

func _can_service_action(kind: String) -> bool:
	if kind not in ["service","toolheap"] or not _can_mutate_floor() or room_change_pending or _hostile_room() or not room_states.has(current_room) or not dungeon.get("rooms",{}).has(current_room):
		return false
	var definition: Dictionary = dungeon.rooms[current_room]
	if not _is_service(definition):
		return false
	var modal := "toolheap" if kind=="toolheap" else "service"
	if not ui.opened or ui.panel_kind!=modal:
		return false
	if get_tree().paused and not (ui.opened and ui.panel_kind==modal):
		return false
	var unresolved_heap: bool = definition.get("has_toolheap",false) and not run.current_toolheap().get("resolved",true)
	if kind=="toolheap":
		return unresolved_heap and ui.opened and ui.panel_kind=="toolheap"
	return not unresolved_heap

func _reset_door_transition() -> void:
	_room_epoch += 1
	_pending_door_transition.clear()
	room_change_pending = false

func _check_doors() -> void:
	if not _can_mutate_floor() or not is_instance_valid(world) or room_change_pending or ui.opened or get_tree().paused or gameplay_time-last_door_time<0.8 or not dungeon.get("rooms",{}).has(current_room):
		return
	var definition: Dictionary = dungeon.rooms[current_room]
	for side: String in definition.doors:
		var at: Vector3 = world.get_door_position(side)
		if Vector2(player.position.x-at.x,player.position.z-at.z).length()<1.3:
			# Preserve the encounter's existing backtracking/wave-drain check.
			if _hostile_room():
				director.request_exit_check()
				return
			var target := str(definition.doors[side])
			if not _can_travel_action("door_request",target):
				return
			_door_ticket += 1
			_pending_door_transition = {"ticket":_door_ticket,"run_id":run.data.run_id,"floor":run.data.floor,"source":current_room,"epoch":_room_epoch,"target":target,"side":side,"arrival":OPPOSITE[side]}
			room_change_pending = true
			call_deferred("_commit_door_transition",_door_ticket)
			return

func _commit_door_transition(ticket: int) -> bool:
	# A stale callback must not cancel a newer valid request.
	if _pending_door_transition.is_empty() or int(_pending_door_transition.ticket)!=ticket:
		return false
	var request := _pending_door_transition.duplicate()
	if not _can_travel_action("door_commit",str(request.target),ticket):
		_pending_door_transition.clear()
		room_change_pending = false
		return false
	run.data.hp = player.hp
	_enter_room(str(request.target),str(request.arrival))
	return true

func _show_content_error(reason: String) -> void:
	if not _level_content_error.is_empty():
		return
	_level_content_error = reason
	_panel("这片田地暂时走不通",reason+"\n本房不会自动通关或发奖。可以结束这趟回村，或保存当前节点记录后退出。",[{"text":"结束这趟并回村","action":_end_run.bind("FORFEIT")},{"text":"保存记录并退出","action":_quit_game}],"confirm")

func _make_service_marker(definition: Dictionary) -> void:
	if not _is_service(definition):
		return
	var route: PackedVector3Array = definition.get("main_route",PackedVector3Array())
	var at: Vector3 = route[int(route.size()/2)] if not route.is_empty() else player.position+Vector3(2,0,-3)
	if int(run.data.get("content_revision",2))>=3:
		var anchor: Dictionary = world.resolve_service_anchor()
		if not anchor.get("ok",false) or not Vector3(anchor.get("position",Vector3.INF)).is_finite():
			_show_content_error("田间设施没有安全、可达的放置点。")
			return
		at = anchor.position
	service_marker = Label3D.new()
	service_marker.font_size = 30
	service_marker.pixel_size = 1.0/64
	service_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	service_marker.outline_size = 6
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei","sans-serif"])
	service_marker.font = font
	service_marker.position = at+Vector3.UP*2
	gameplay.add_child(service_marker)
	var prop: Node3D = load("res://assets/environment/crate.glb").instantiate()
	prop.position = at
	gameplay.add_child(prop)
	_refresh_service_marker()

func _refresh_service_marker() -> void:
	if not is_instance_valid(service_marker) or not dungeon.get("rooms",{}).has(current_room):
		return
	var definition: Dictionary = dungeon.rooms[current_room]
	var service := Services.for_room(definition)
	if definition.get("has_toolheap",false) and not run.current_toolheap().get("resolved",true):
		service_marker.text = ui.input_label("interact")+" · 工具堆 · 免费强化"
	elif room_states[current_room].resolved and not service.get("repeatable",false):
		service_marker.text = "已处理 · "+str(service.get("title","田间设施"))
	else:
		service_marker.text = ui.input_label("interact")+" · "+str(service.get("title","田间设施"))

func _is_shop(definition: Dictionary) -> bool:
	return Services.for_room(definition).get("service_kind","")=="shop"

func _is_service(definition: Dictionary) -> bool:
	return not Services.for_room(definition).is_empty()

func _interact() -> void:
	if phase == "village":
		var npc: Dictionary = village.nearest_npc(player.position)
		if not npc.is_empty():
			_panel(str(npc.name)+" · "+str(npc.role),"\n".join(npc.dialogue),[{"text":npc.label,"action":_village_action.bind(str(npc.action))},{"text":"再逛逛","action":_close_panel}])
		return
	if phase != "floor" or current_room.is_empty() or _hostile_room():
		return
	if is_instance_valid(service_marker) and Vector2(player.position.x-service_marker.position.x,player.position.z-service_marker.position.z).length()<=3:
		_show_service()

func _village_action(action: String) -> void:
	match action:
		"start":
			_request_new_run()
		"prepare":
			_panel("出门的家伙", "保留这份 3D 工程的树枝和玉米枪。出发时选一把，当前一趟不切换。",[{"text":"带树枝出发","action":_prepare_and_start.bind("stick")},{"text":"带玉米枪出发","action":_prepare_and_start.bind("corn")},{"text":"再逛逛","action":_close_panel}])
		"train":
			_panel("晒谷场练手", "靠近草靶，面朝它，按左键单手挥砍。\n挥完树枝落回身侧。草靶只记伤害，不掉东西。",[{"text":"去草靶前练习","action":_go_training},{"text":"知道了","action":_close_panel}])
		"journal":
			_panel("见闻簿", "已保存的发现点：%d\n田里有甲虫、蝗虫、蜗牛、田鼠、公鸡与玉米螟。\n冬日打雪仗、书包组合留在后续设计。" % int(run.data.meta),[{"text":"收好见闻簿","action":_close_panel}])
		_:
			_panel("田里的门道", "红色房间通关后还可以继续逛。N 随时开关下一节点路线，选择才离开。\n小卖点可以什么都不买，捡到的碎物能换零花钱。",[{"text":"记住了","action":_close_panel}])

func _go_training() -> void:
	_close_panel()
	player.position = Vector3(25.7,0,23)
	ui.toast("面朝草靶，%s单手挥砍；移动键跑动，松开即停。" % ui.input_label("attack"))

func _show_service() -> void:
	if not _can_mutate_floor() or room_change_pending or _hostile_room() or not dungeon.get("rooms",{}).has(current_room):
		return
	var definition: Dictionary = dungeon.rooms[current_room]
	var service := Services.for_room(definition)
	if service.is_empty():
		return
	var state: Dictionary = room_states[current_room]
	if definition.get("has_toolheap",false) and not run.current_toolheap().get("resolved",true):
		_show_toolheap()
		return
	if service.repeatable:
		_panel(service.title,"零花钱 %d 元 / 可售拾物 %d 件\n不消费也能通过。"%[int(run.data.coins),int(run.data.loot.get("田间拾物",0))],[{"text":"冰汽水 · %d 元，恢复 %d 体力"%[service.cost,service.heal],"disabled":int(run.data.coins)<int(service.cost) or player.hp>=player.max_hp,"action":_buy_heal},{"text":"卖出拾物 · 每件 %d 元"%int(service.sell_price),"disabled":int(run.data.loot.get("田间拾物",0))<=0,"action":_sell_loot},{"text":"离开小卖点，继续走","action":_resolve_service.bind("skip")}])
	elif state.resolved:
		ui.toast("这里已经处理过了，可以从绿色门继续走。")
	else:
		var action := str(service.allowed_actions[0])
		_panel(service.title,service.short_description+"\n领一次或者跳过，都可以继续前进。",[{"text":"吃块西瓜 · %d 元"%int(service.cost) if action=="watermelon" else "收下补给" if int(service.coins)>0 else "歇歇脚，记录见闻","disabled":int(run.data.coins)<int(service.cost),"action":_resolve_service.bind(action)},{"text":"先不拿，继续走","action":_resolve_service.bind("skip")}])

func _resolve_service(choice: String) -> void:
	if not _can_service_action("service"):
		return
	var service := Services.for_room(dungeon.rooms[current_room])
	if not service.get("allowed_actions",[]).has(choice) or (service.get("repeatable",false) and choice!="skip"):
		return
	var state: Dictionary = room_states[current_room]
	if not state.resolved:
		if choice!="skip":
			if int(run.data.coins)<int(service.cost):
				return
			if int(service.meta)>0 and not run.grant_meta("3d_node_%d_level"%int(run.data.floor),int(service.meta)):
				_show_service()
				_save_error("见闻保存失败，请重试。")
				return
			run.data.coins += int(service.coins)-int(service.cost)
			if int(service.heal)>0:player.heal(float(service.heal))
			if int(service.loot)>0:run.data.loot["田间拾物"] = int(run.data.loot.get("田间拾物",0))+int(service.loot)
		state.resolved = true
	if dungeon.rooms[current_room].get("completion",false):
		_unlock_next()
	_close_panel()
	_refresh_service_marker()
	_sync_stats()

func _buy_heal() -> void:
	if not _can_service_action("service"):
		return
	var service := Services.for_room(dungeon.rooms[current_room])
	if not service.get("allowed_actions",[]).has("buy_heal") or int(run.data.coins)<int(service.cost) or player.hp>=player.max_hp:
		return
	run.data.coins -= int(service.cost)
	player.heal(float(service.heal))
	_refresh_service_marker()
	_show_service()

func _sell_loot() -> void:
	if not _can_service_action("service"):
		return
	var service := Services.for_room(dungeon.rooms[current_room])
	if not service.get("allowed_actions",[]).has("sell_loot"):
		return
	run.data.coins += int(run.data.loot.get("田间拾物",0))*int(service.sell_price)
	run.data.loot["田间拾物"] = 0
	_refresh_service_marker()
	_show_service()

func _show_map() -> void:
	if dungeon.is_empty():
		_show_routes()
		return
	var rooms: Array = []
	for id in dungeon.rooms:
		var definition: Dictionary = dungeon.rooms[id]
		var state: Dictionary = room_states[id]
		var outline: Array[Vector2] = []
		for point: Vector2 in definition.outline:
			outline.append(point/Vector2(definition.size))
		var gates: Array = []
		for side: String in definition.doors:
			var point: Vector3 = World.Catalog.door_position(side,definition.size)
			gates.append({"pos":Vector2(point.x,point.z)/Vector2(definition.size),"side":side,"open":state.cleared})
		var service := Services.for_room(definition) if state.visited else {}
		var map_kind := str(definition.kind)
		if map_kind=="entry":map_kind="start"
		elif not service.is_empty():map_kind={"shop":"shop","event":"event","rest":"tree","supply":"objective","loot":"reward"}.get(str(service.service_kind),map_kind)
		rooms.append({"service_title":service.get("title",""),"service_description":service.get("short_description",""),"service_resolved":state.resolved,"service_repeatable":service.get("repeatable",false),"gates":gates,"id":id,"title":definition.title,"grid":definition.grid,"size":definition.size*32,"outline":outline,"visited":state.visited,"cleared":state.cleared,"can_travel":_can_travel_action("revisit",str(id)),"kind":map_kind,"completion":definition.get("completion",false),"has_toolheap":definition.get("has_toolheap",false),"toolheap_resolved":run.current_toolheap().get("resolved",true)})
	ui.show_room_map({"current":current_room,"floor":run.data.floor,"node_title":NAMES.get(run.data.selected,"玉米地"),"rooms":rooms,"links":dungeon.links,"combat_locked":_hostile_room()},_travel_to,_close_panel)
	_refresh_pause()

func _travel_to(id: String) -> bool:
	if not _can_travel_action("revisit",id):
		return false
	run.data.hp = player.hp
	_close_panel()
	_enter_room(id)
	return true

func _spawn_props(definition: Dictionary, state: Dictionary) -> void:
	var route: PackedVector3Array = definition.get("main_route",PackedVector3Array())
	var candidates: Array[Vector3] = []
	for i in range(1,route.size()-1):
		for offset in [Vector3(2.1,0,1.4),Vector3(-2.1,0,-1.4)]:
			var at: Vector3 = route[i]+offset
			if world.contains_ground(at,0.6):
				candidates.append(at)
	if not world.validate_field_prop_candidates(candidates):
		_spawn_props(definition,state)
		return
	for index in mini(5,candidates.size()):
		var id := "%s_prop_%d" % [current_room,index]
		if state.broken.has(id):
			continue
		var value := posmod(int(run.data.seed)+current_room.hash()+index*37,100)
		var drop := "" if value<30 else ("coins" if value<55 else ("heal" if value<75 else ("candy" if value<88 else "mint")))
		var prop := Loot.new()
		prop.configure(id,["jar","crate","hay"][index%3],drop)
		prop.position = candidates[index]
		prop.broken.connect(_prop_broken)
		gameplay.add_child(prop)
		world.register_dynamic_obstacle(id,prop.position,prop.collision_radius)
	world.validate_field_spawned_content()
	for id in state.drops:
		var record: Dictionary = state.drops[id]
		_spawn_pickup(str(id),record.position,str(record.kind))

func _prop_broken(id: String, at: Vector3, drop: String) -> void:
	var state: Dictionary = room_states[current_room]
	state.broken[id] = true
	world.remove_dynamic_obstacle(id)
	if not drop.is_empty():
		state.drops[id] = {"position":at,"kind":drop}
		_spawn_pickup(id,at,drop)

func _spawn_pickup(id: String, at: Vector3, kind: String) -> void:
	var pickup := Loot.Pickup.new()
	pickup.setup(id,kind,player)
	pickup.position = at
	pickup.collected.connect(_pickup_collected)
	gameplay.add_child(pickup)

func _pickup_collected(id: String, kind: String) -> void:
	room_states[current_room].drops.erase(id)
	match kind:
		"coins":
			run.data.coins += 3
			ui.toast("拾到零花钱 · +3 元")
		"heal":
			player.heal(20)
			ui.toast("田间红枣 · 恢复 20 体力")
		"candy":
			damage_buff_time = 20
			ui.toast("麦芽糖 · 20 秒内伤害 +20%")
		"mint":
			speed_buff_time = 20
			ui.toast("薄荷叶 · 20 秒内移动速度 +20%")
	_feedback_event("pickup",{"position":player.position,"strength":1.0})
	_sync_stats()

func _enemy_defeated(at: Vector3, reward: int) -> void:
	if phase == "floor":
		run.data.coins += reward
		_feedback_event("defeat",{"position":at,"strength":1.0})

func _health_changed(value: float, _maximum: float) -> void:
	if phase == "floor":
		run.data.hp = value

func _player_died() -> void:
	if phase == "floor":
		if is_instance_valid(feedback):
			feedback.clear_all()
		pending_terminal = "FAILED"
		call_deferred("_end_run","FAILED")

func _sync_stats() -> void:
	if is_instance_valid(player):
		var effects: Dictionary = run.build_effects(player.weapon_id)
		player.apply_build_effects(effects)
		player.damage_multiplier = float(effects.damage_multiplier)*(1.2 if damage_buff_time>0 else 1.0)
		player.movement_multiplier = 1.2 if speed_buff_time>0 else 1.0

func _finish_chapter() -> void:
	if phase == "floor" and node_complete and int(run.data.floor)==3:
		_end_run("VICTORY_PENDING_SETTLEMENT")

func _end_run(result: String) -> void:
	if run.data.status != "ACTIVE" or result not in ["FAILED","FORFEIT","VICTORY_PENDING_SETTLEMENT"]:
		return
	if player.hp<=0 or pending_terminal=="FAILED":
		result = "FAILED"
	elif not pending_terminal.is_empty():
		result = pending_terminal
	pending_terminal = result
	run.data.hp = maxf(0,player.hp)
	if not run.end_run(result):
		_panel("结果尚未保存","保存失败，不能继续或回档复活。请重试。",[{"text":"重试保存结果","action":_end_run.bind(result)}],"settlement")
		return
	pending_terminal = ""
	_settlement()

func _settlement() -> void:
	phase = "settlement"
	var title := "玉米地又安静下来" if run.data.status=="VICTORY_PENDING_SETTLEMENT" else "这一趟，先回家"
	_panel(title,"经过 %d 个节点 / 零花钱 %d / 本局用时 %.1f 分钟\n结果已保存。结算中退出也不会回到战斗。" % [int(run.data.floor),int(run.data.coins),float(run.data.elapsed)/60.0],[{"text":"结算并回到村口","action":_settle}],"settlement")

func _settle() -> void:
	if not run.settle():
		_settlement()
		_save_error("结算保存失败，请重试。")
		return
	_show_village()

func _show_pause() -> void:
	var choices: Array = [{"text":"继续","action":_close_panel}]
	if phase == "floor":
		choices.append({"text":"放弃本局并回村","action":_confirm_forfeit})
	elif phase == "village":
		choices.append({"text":"去村口准备出发","action":_show_welcome})
	choices.append({"text":"退出游戏 · 下次从当前节点起点继续","action":_quit_game})
	_panel("歇一会儿", "本局固定一把武器。地图、商店与路线界面仍计入本局用时；暂停与失焦不计时。",choices,"pause")

func _confirm_forfeit() -> void:
	_panel("放弃这一趟？","放弃会正式结束本局，不能继续。",[{"text":"确认放弃","action":_end_run.bind("FORFEIT")},{"text":"继续这趟","action":_close_panel}],"confirm")

func _save_before_quit() -> bool:
	if run == null or run.data.status == "COMPLETE":
		return true
	if not pending_terminal.is_empty():
		if not run.end_run(pending_terminal):
			return false
		pending_terminal = ""
	return run.save()

func _quit_game() -> void:
	if _quit_in_progress:
		return
	_quit_in_progress = true
	if not _save_before_quit():
		_quit_in_progress = false
		_panel("退出前还没存好","保存失败，游戏仍保留在当前状态。",[{"text":"重试保存并退出","action":_quit_game}],"settlement" if phase=="settlement" else "pause")
		_save_error("退出前保存失败，请重试。")
		return
	_panel("正在退出", "正在收拾行装，请稍候。",[],"settlement" if phase=="settlement" else "pause")
	if not await CornAudio.await_owned_shutdown(get_tree()):
		_quit_in_progress = false
		_panel("暂时还没退出", "退出尚未完成，可以重试。",[{"text":"重试退出","action":_quit_game},{"text":"返回结算" if phase=="settlement" else "继续这趟","action":_settlement if phase=="settlement" else _close_panel}],"settlement" if phase=="settlement" else "pause")
		return
	get_tree().paused = false
	get_tree().quit()

func _save_error(message: String) -> void:
	ui.toast(message)

func _follow_camera(delta: float) -> void:
	var desired := player.global_position+Vector3(0,0.7,-2.8)
	camera_target = camera_target.lerp(desired,1.0-exp(-delta*4.0))
	camera.global_position = camera_target+Vector3(15,19,15)
	camera.look_at(camera_target,Vector3.UP)
	if is_instance_valid(weapon_controller):
		camera.h_offset = sin(weapon_controller.kick_clock*83.0)*weapon_controller.camera_kick
		camera.v_offset = cos(weapon_controller.kick_clock*61.0)*weapon_controller.camera_kick*0.55

func _update_occlusion() -> void:
	if is_instance_valid(world) and world.has_method("update_occlusion"):
		world.update_occlusion(camera,player.global_position)

func _update_hud() -> void:
	ui.heading.text = "榆树湾 · 出发前" if phase == "village" else "玉米地 %d / 3 · %s" % [int(run.data.floor),NAMES.get(run.data.selected,"选一条田埂")]
	var weapon_label := "树枝 · 挥击" if player.weapon_id == "stick" else "玉米枪 · 连射 / 蓄力散射"
	var build_texts: Array[String] = []
	var ranks: Dictionary = run.data.builds_by_weapon.get(player.weapon_id,{})
	for id in ranks:
		if int(ranks[id])>0:
			build_texts.append("%s%d" % [str(BuildCatalog.get_definition(id).get("name",id)),int(ranks[id])])
	if int(run.data.global_builds.get("clear_heal",0))>0:
		build_texts.append("清场回复%d" % int(run.data.global_builds.clear_heal))
	if ui.has_method("update_status"):
		ui.update_status({"hp":player.hp,"max_hp":player.max_hp,"weapon_label":weapon_label,"build_summary":" · ".join(build_texts),"coins":int(run.data.coins),"dice":int(run.data.dice),"title":ui.heading.text})
	else:
		ui.stats.text = "%s   零花钱 %d   骰子 %d" % [weapon_label,int(run.data.coins),int(run.data.dice)]
	ui.health.max_value = player.max_hp
	ui.health.value = player.hp
	ui.health_text.text = "体力 %d / %d" % [int(player.hp),int(player.max_hp)]
	if phase == "village":
		var nearest: Dictionary = village.nearest_npc(player.position) if is_instance_valid(village) else {}
		ui.hint.text = ui.input_label("interact")+" · "+str(nearest.name)+" · "+str(nearest.label) if not nearest.is_empty() else "沿土路到田埂路牌按 %s 出发；%s 可整理装备。" % [ui.input_label("interact"),ui.input_label("pause")]
		ui.update_minimap({"visible":false})
		return
	ui.hint.text = "红房已通关 · %s 选择下一节点，也可以继续探索" % ui.input_label("node_map") if node_complete else "沿田埂前进 · 绿色门通往其他房间 · 红色房间解锁下一节点"
	if is_instance_valid(director) and _hostile_room():
		ui.hint.text = _combat_hint()
	if is_instance_valid(service_marker) and player.position.distance_to(service_marker.position-Vector3.UP*2)<3:
		ui.hint.text = "%s · 与田间设施互动（不购买也能离开）" % ui.input_label("interact")
	if not is_instance_valid(world) or not dungeon.get("rooms",{}).has(current_room):
		ui.update_minimap({"visible":false})
		return
	var definition: Dictionary = dungeon.rooms[current_room]
	var extent: Vector2 = definition.size
	var gates: Array = []
	for side: String in definition.doors:
		var point: Vector3 = world.get_door_position(side)
		gates.append({"pos":Vector2(point.x,point.z)/extent,"side":side,"open":room_states[current_room].cleared})
	var contacts: Array = []
	if is_instance_valid(director):
		for enemy in director.get_children():
			if enemy is CharacterBody3D and not bool(enemy.get("dead")):
				contacts.append({"pos":Vector2(enemy.position.x,enemy.position.z)/extent,"elite":enemy.get("elite")==true,"boss":enemy.get("boss")==true})
	ui.update_minimap({"visible":true,"outline":world.get_outline_normalized(),"gates":gates,"contacts":contacts,"player":Vector2(player.position.x,player.position.z)/extent,"title":definition.title,"completion":definition.get("completion",false)})

func metrics() -> Dictionary:
	var visited := 0
	var combat := 0
	var optional := 0
	for id in room_states:
		visited += int(room_states[id].visited)
		combat += int(dungeon.rooms[id].get("encounter","") in ["combat","swarm","boss","elite"])
		optional += int(not dungeon.main_path.has(id))
	return {"generated_room_count":dungeon.get("rooms",{}).size(),"visited_unique_room_count":visited,"combat_room_count":combat,"optional_room_count":optional,"elapsed":run.data.elapsed,"path_time":run.data.path_time}

func _show_toolheap() -> void:
	var heap: Dictionary = run.current_toolheap()
	if heap.is_empty() or heap.resolved or _hostile_room():
		return
	var info: Dictionary = BuildCatalog.describe(str(heap.candidate_id),run._rank_payload(),str(run.data.weapon))
	info.merge({"heap_id":heap.heap_id,"dice":run.data.dice,"resolved":heap.resolved,"layer":1,"total_layers":1,"can_reroll":int(run.data.dice)>0 and BuildCatalog.allowed_ids(str(run.data.weapon),run._rank_payload()).size()>1,"weapon_label":"树枝剑" if run.data.weapon=="stick" else "玉米枪"},true)
	ui.show_toolheap(info,_on_toolheap_action,_close_panel)
	_refresh_pause()

func _on_toolheap_action(action: String) -> void:
	if not _can_service_action("toolheap"):
		return
	var result: Dictionary = run.act_on_toolheap(action)
	if not result.ok:
		_show_toolheap()
		ui.toast("这次操作没有生效，请重新选择。")
		return
	_sync_stats()
	if action=="reroll":
		_show_toolheap()
		return
	_close_panel()
	if action=="accept":
		_feedback_event("upgrade",{"position":player.position,"strength":1.3})
		ui.toast("农具已经顺手了。强化会带到下一节点；%s 可继续查看田间设施。" % ui.input_label("interact"))
	else:
		ui.toast("这一堆先不拿。可以照常继续前进。")
	_refresh_service_marker()

func _feedback_event(kind: String,payload: Dictionary) -> void:
	if is_instance_valid(feedback):
		feedback.emit_feedback(kind,payload)

func _show_tutorial(step: int) -> void:
	_tutorial_step = step
	ui.show_tutorial(step,_next_tutorial,_finish_tutorial)
	_refresh_pause()

func _next_tutorial() -> void:
	if _tutorial_step>=2:
		_finish_tutorial()
	else:
		_show_tutorial(_tutorial_step+1)

func _finish_tutorial() -> void:
	_tutorial_seen = true
	var preferences := ConfigFile.new()
	preferences.set_value("onboarding","seen",true)
	preferences.save("user://cornfield_tutorial_v1.cfg")
	_close_panel()

func _combat_hint() -> String:
	if not is_instance_valid(director):
		return "沿田埂前进"
	var living: Array[Node3D] = []
	for enemy in director.enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			living.append(enemy)
	if living.size() in [1,2]:
		var nearest: Node3D = living[0]
		for enemy in living:
			if player.global_position.distance_squared_to(enemy.global_position)<player.global_position.distance_squared_to(nearest.global_position):
				nearest=enemy
		var distance := Vector2(nearest.global_position.x-player.global_position.x,nearest.global_position.z-player.global_position.z).length()
		return "场上余 %d 只 · %s %d 米 · 清理后沿田埂继续"%[living.size(),_screen_direction_to(nearest.global_position),roundi(distance)]
	if not living.is_empty():
		return "虫群来了 · 场上 %d 只 · 留意橙色边界，绕到空处再出手"%living.size()
	if not director._warnings.is_empty():
		return "地面预警亮起 · 下一群正在出现，离开标记留出退路"
	for group in director.group_schedule():
		if int(group.spawned)+int(group.reserved)<int(group.count):
			var point: Vector3 = director.next_encounter_hint_target()
			if not point.is_finite(): return "前方还有虫群 · 清理完成后门会打开"
			if director._spawned==0 and director._hint_probe_active():
				return "已到推进点 · 稍停观察地面，留出退路"
			return "前方还有虫群 · 向%s推进 · 清理完成后门会打开"%_screen_direction_to(point)
	return "这片田埂快清静了 · 留意四周和绿色门"

func _screen_direction_to(point: Vector3) -> String:
	if not is_instance_valid(camera) or not is_instance_valid(player):
		return "前方"
	var offset := camera.unproject_position(point)-camera.unproject_position(player.global_position)
	if offset.length_squared()<16:
		return "附近"
	var directions := ["右方","右下方","下方","左下方","左方","左上方","上方","右上方"]
	return directions[posmod(roundi(atan2(offset.y,offset.x)/(PI*.25)),8)]

func _boss_status(info: Dictionary) -> void:
	if info.is_empty():
		_last_boss_stage=0
		ui.update_boss({})
		return
	var stage:=int(info.get("stage",1))
	var display:=info.duplicate(true)
	display.title=str(info.get("title","巨型玉米螟"))+" · "+("第二阶段" if stage>=2 else "第一阶段")
	ui.update_boss(display)
	if stage>=2 and _last_boss_stage<2:
		ui.toast("玉米螟急躁了 · 留意连冲和环形弹幕，等收招空当再出手")
	_last_boss_stage=stage
