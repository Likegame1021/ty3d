extends "res://scripts/main.gd"

const ProgressScript = preload("res://scripts/entry_progress.gd")
const ChickenScript = preload("res://scripts/entry_chicken.gd")
const CreatureScript = preload("res://scripts/entry_creature.gd")
const ItemScript = preload("res://scripts/entry_item.gd")
const EntryHudScript = preload("res://ui/entry_hud.gd")
const ENTRY_SPAWN := Vector3(0, 0.05, 12)
const EXIT := Vector3(0, 0, -13)
var progress = ProgressScript.new()
var chicken: Node3D
var creature: CharacterBody3D
var item: Node3D
var paused_menu := false
var last_stage := -1
var audio_listener: AudioListener3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_input()
	if ResourceLoader.exists("res://environment/entry_field.gd"):
		environment = load("res://environment/entry_field.gd").new()
		environment.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(environment)
	else:
		build_fallback_ground()
		push_warning("M1 temporary floor: entry_field.gd is not delivered yet")
	player = PlayerScript.new()
	player.name = "Boy"
	player.spawn_position = ENTRY_SPAWN
	player.attack_group = "entry_enemies"
	add_child(player)
	player.collision_mask = 1 | 4
	chicken = ChickenScript.new()
	chicken.name = "HarmlessChicken"
	add_child(chicken)
	item = ItemScript.new()
	item.name = "MarbleTin"
	add_child(item)
	creature = CreatureScript.new()
	creature.name = "FieldCreature"
	creature.player = player
	add_child(creature)
	creature.strike_attempt.connect(on_enemy_strike)
	creature.telegraphed.connect(func(): hud.show_message("它停下准备扑过来！往侧面走，或挥枝打断。", 1.6))
	creature.defeated.connect(on_creature_defeated)
	player.struck.connect(func(_enemy): hud.show_message("树枝击退了田鼠！", 1.2))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.5
	camera.near = 0.1
	camera.far = 120.0
	add_child(camera)
	camera.current = true
	audio_listener = AudioListener3D.new()
	audio_listener.name = "PlayerAudioListener"
	audio_listener.position.y = 0.7
	player.add_child(audio_listener)
	audio_listener.make_current()
	hud = EntryHudScript.new()
	add_child(hud)
	hud.resume_requested.connect(func(): set_paused(false))
	hud.retry_requested.connect(reset_run)
	reset_run()

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
	if event.is_action_pressed("attack"):
		player.request_attack()
	elif event.is_action_pressed("interact"):
		interact()
	elif event.is_action_pressed("night"):
		set_night(not night)
		hud.show_message("月色里也能沿着小路前行。" if night else "午后的玉米沙沙作响。")

func _physics_process(delta: float) -> void:
	if get_tree().paused or progress.outcome != "playing":
		return
	progress.tick(delta, false)
	if not progress.chicken_discovered and horizontal_distance(player.position, chicken.position) < 2.4:
		if progress.discover_chicken():
			chicken.discovered = true
			hud.show_message("原来是小鸡！它是无害的。\n沿左侧小路继续往前，找找玉米旁的铁盒。", 5.2)
	if progress.item_collected and not progress.enemy_seen and player.position.z < -3.0:
		progress.notice_enemy()
		hud.show_message("前面的田鼠在巡游。你可以绕过它，或用树枝击退。", 4.5)
	item.set_hint(not progress.item_collected and progress.stage >= 1 and horizontal_distance(player.position, item.position) < 2.6)
	update_story_environment()

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if not get_tree().paused:
		update_camera(delta)
		audio_listener.global_basis = camera.global_basis
		if environment:
			environment.set_player_position(player.global_position)
	hud.update_entry(progress, context_text(), night)

func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func context_text() -> String:
	if progress.outcome == "lost":
		return "体力用完了，按 R 或点击重新开始。"
	if progress.outcome == "won":
		return "弹珠铁盒已找回，按 R 可以再走一次。"
	if horizontal_distance(player.position, EXIT) < 2.0:
		return "[ E ] 把铁盒带出玉米地" if progress.item_collected else "出口还在这里 · 先找回弹珠铁盒"
	if horizontal_distance(player.position, item.position) < 1.6 and not progress.item_collected:
		return "[ E ] 拾起弹珠铁盒" if progress.chicken_discovered else "先看看入口左侧玉米里的动静。"
	if creature.active and creature.mode in ["chase", "windup", "lunge"]:
		return "注意田鼠！前摇时侧移或挥枝，也可以直接跑开。"
	return ["左边的玉米在动，靠近一点看看。", "沿左侧小路往前走，留意玉米旁的小铁盒。", "中央路通向北边出口；田鼠不必击败。"][mini(progress.stage, 2)]

func interaction_clear(destination: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.45, destination + Vector3.UP * 0.45, 1)
	return player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func interact() -> void:
	if get_tree().paused or progress.outcome != "playing":
		return
	if horizontal_distance(player.position, EXIT) < 2.0:
		if progress.try_finish():
			finish_run()
		else:
			hud.show_message("还没有弹珠铁盒。先看看小鸡，再沿左侧小路找到它。", 4.0)
	elif horizontal_distance(player.position, item.position) < 1.6 and interaction_clear(item.position):
		if progress.collect_item():
			item.visible = false
			hud.show_message("铁盒找到了！带着它去北边出口吧。", 4.0)
		elif progress.item_collected:
			hud.show_message("铁盒已经收好了，不会重复拾取。", 2.5)
		else:
			hud.show_message("先去看看入口左侧的动静。", 3.0)
	else:
		hud.show_message("靠近铁盒或北边出口，再按 E。", 2.2)
	update_story_environment()

func on_enemy_strike() -> void:
	if get_tree().paused or progress.outcome != "playing":
		return
	if horizontal_distance(player.position, creature.position) < 1.25 and progress.take_damage():
		hud.show_damage()
		hud.show_message("体力减少了一格。短时间内不会再受伤，快侧移或跑开！", 2.0)
		if progress.outcome == "lost":
			finish_run()

func on_creature_defeated() -> void:
	progress.enemy_repelled = true
	hud.show_message("田鼠退走了。带着铁盒，继续朝出口走吧。", 3.0)

func finish_run() -> void:
	paused_menu = false
	player.attack.reset()
	update_story_environment()
	hud.reset_feedback()
	hud.show_menu(progress.outcome, progress)
	get_tree().paused = true

func set_paused(value: bool) -> void:
	if progress.outcome != "playing":
		return
	paused_menu = value
	get_tree().paused = value
	if value:
		hud.show_menu("pause", progress)
	else:
		hud.hide_menu()

func reset_run() -> void:
	get_tree().paused = false
	paused_menu = false
	progress.reset()
	player.reset_player()
	chicken.reset_animal()
	creature.reset_creature()
	item.reset_item()
	hud.reset_feedback()
	if environment and environment.has_method("reset_story"):
		environment.reset_story()
	last_stage = -1
	set_night(false)
	update_story_environment()
	camera_focus = player.position + Vector3(0, 0.7, -2.8)
	update_camera(1.0)
	hud.update_entry(progress, context_text(), night)
	hud.show_message("弹珠铁盒落在田里了。\n先看看左侧玉米里的动静，再把它带回来。", 5.0)

func update_story_environment() -> void:
	creature.story_revealed = progress.enemy_seen
	if not environment:
		return
	if environment.has_method("set_story_sources"):
		environment.set_story_sources(chicken.global_position, creature.global_position, creature.active and progress.outcome == "playing")
	if environment.has_method("set_story_stage") and last_stage != progress.stage:
		last_stage = progress.stage
		environment.set_story_stage(progress.stage)
