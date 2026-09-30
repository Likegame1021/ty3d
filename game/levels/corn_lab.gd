extends "res://levels/full.gd"

const CornTarget = preload("res://weapons/corn_target.gd")
var practice_targets: Array[Node3D] = []
var lab_mode := 0
var lab_wave := 0
var wave_delay := 0.0
var lab_ready := false

func _ready() -> void:
	super._ready()
	lab_ready = true
	camera.size = 12.5
	player.spawn_position = Vector3(0, 0.05, -29)
	player.world_min = Vector2(-9, -43)
	player.world_max = Vector2(9, -26.8)
	for point in [Vector3(0, 0, -34), Vector3(-2.5, 0, -34.5), Vector3(2.5, 0, -34.5)]:
		var dummy = CornTarget.new()
		dummy.position = point
		add_child(dummy)
		practice_targets.append(dummy)
	hud.set_corn_lab(true)
	reset_run()

func reset_run() -> void:
	super.reset_run()
	if not lab_ready:
		return
	lab_mode = 0
	lab_wave = 0
	wave_delay = 0
	progress.chicken_seen = true
	progress.tin_taken = true
	progress.mouth_cleared = true
	progress.canal_open = true
	progress.dense_entered = true
	progress.board_taken = true
	progress.cart_moved = true
	progress.launcher_taken = true
	progress.corn_spilled = true
	progress.corn_gun = true
	# Keeps the story entrance trigger inactive while the actual boss rests.
	progress.boss_active = true
	boss.active = false
	boss.visible = false
	boss.collision_layer = 0
	pursuer.active = false
	pursuer.set_physics_process(false)
	gun_equipped = true
	update_weapon_visual()
	for key in props:
		props[key].visible = false
	for dummy in practice_targets:
		dummy.visible = true
		dummy.collision_layer = 4
		dummy.reset_target()
	sync_environment()
	camera_focus = player.position + Vector3(0, 0.7, -2.8)
	update_camera(1.0)
	hud.boss_meter.max_value = 12
	hud.show_message("玉米枪就绪！鼠标瞄准，按住左键连射。\nF 切换清怪 / Boss 挑战，R 随时回木靶。", 5.0)

func sync_environment() -> void:
	super.sync_environment()
	if lab_ready:
		environment.get_node("AbandonedHarvestRing/CornStore").hide()
		environment.get_node("AbandonedHarvestRing/SpilledCornVisual").hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("throw_stone") and not event.is_echo() and not get_tree().paused and progress.outcome == "playing":
		cancel_gun_input()
		if lab_mode == 0:
			start_combat_trial()
		elif lab_mode == 1:
			start_boss_trial()
		else:
			reset_run()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func interact() -> void:
	if lab_mode == 0:
		for dummy in practice_targets:
			dummy.reset_target()
		hud.show_message("木靶已复原 · 靠近一点试试蓄力散射。", 2.0)

func hide_practice_targets() -> void:
	for dummy in practice_targets:
		dummy.active = false
		dummy.visible = false
		dummy.collision_layer = 0
		dummy.reset_time = 0

func start_combat_trial() -> void:
	cancel_gun_input()
	gun_fx.clear_effects()
	hide_practice_targets()
	lab_mode = 1
	lab_wave = 0
	wave_delay = 0
	progress.health = progress.max_health
	progress.invulnerable = 0
	spawn_lab_wave()

func spawn_lab_wave() -> void:
	for minion in minions:
		if is_instance_valid(minion):
			minion.retreat()
	minions.clear()
	lab_wave += 1
	var count := 2 + lab_wave * 2
	var spawn_points: Array[Vector3] = []
	for slot in 16:
		var angle := TAU * float(slot) / 16.0
		var point := Vector3(sin(angle) * 6.7, 0.05, -35 + cos(angle) * 6.7)
		if point.distance_to(player.position) >= 4.5:
			spawn_points.append(point)
	for index in count:
		var minion = MinionScript.new()
		minion.position = spawn_points[index * spawn_points.size() / count]
		minion.player = player
		minion.lifetime = 120
		add_child(minion)
		minion.strike_attempt.connect(on_player_hurt)
		minions.append(minion)
	hud.show_message("第 %d / 3 波 · 边移动边射击，近处蓄力清场！" % lab_wave, 2.5)

func start_boss_trial() -> void:
	cancel_gun_input()
	gun_fx.clear_effects()
	hide_practice_targets()
	for minion in minions:
		if is_instance_valid(minion):
			minion.retreat()
	minions.clear()
	lab_mode = 2
	wave_delay = 0
	progress.health = progress.max_health
	progress.invulnerable = 0
	progress.boss_hp = 36
	progress.boss_defeated = false
	boss.reset_boss()
	boss.active = true
	boss.visible = true
	player.position = Vector3(0, 0.05, -29)
	hud.boss_meter.max_value = 36
	hud.show_message("荒田稻草人 · 36 体力\n绕开横扫，观察钻地，试试持续射击与散射。", 3.5)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not lab_ready or get_tree().paused or progress.outcome != "playing" or lab_mode != 1 or lab_wave > 3:
		return
	var living := 0
	for minion in minions:
		if is_instance_valid(minion) and minion.active:
			living += 1
	if living == 0:
		wave_delay += delta
		if wave_delay > 1.5:
			wave_delay = 0
			if lab_wave < 3:
				spawn_lab_wave()
			else:
				lab_wave = 4
				hud.show_message("三波完成！F 挑战稻草人，R 回木靶继续试枪。", 6.0)

func _process(delta: float) -> void:
	super._process(delta)
	if not lab_ready:
		return
	hud.objective_label.text = ["玉米枪试射 · 木靶", "玉米枪试射 · 清怪", "玉米枪试射 · 稻草人"][lab_mode]
	hud.context_label.text = "鼠标瞄准 · 按住左键连射 · 右键蓄力散射\nF 切换木靶 / 清怪 / Boss　 E 复原木靶　 R 重开　 Esc 暂停"
	hud.controls_label.text = "WASD 移动 · Shift 跑 · Q 切换树枝 / 玉米枪\nTab 日夜 · F6 天气"
	hud.boss_panel.visible = lab_mode == 2
	if lab_mode == 2:
		hud.boss_health_label.text = "荒田稻草人  %d / 36" % progress.boss_hp

func finish_run() -> void:
	super.finish_run()
	hud.menu_title.text = "试射完成！" if progress.outcome == "won" else "歇一会儿，再试一次"
	hud.menu_body.text = "玉米枪试射 · 按 R 或点击下方按钮回到木靶。\n左键持续射击；右键蓄满后松开，清理近处敌群。"
	hud.retry_button.text = "回到木靶 · R"
