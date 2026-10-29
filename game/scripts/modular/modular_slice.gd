extends Node3D
## Isolated continuous-layout playtest; existing chapter scenes/save data unchanged.
const Layout = preload("res://scripts/modular/modular_layout.gd")
const Store = preload("res://scripts/modular/layout_store.gd")
const ModuleWorld = preload("res://scripts/modular/modular_world.gd")
const Player = preload("res://scripts/cornfield/player.gd")
const Director = preload("res://scripts/cornfield/encounter_director.gd")
const UI = preload("res://scripts/modular/modular_ui.gd")
const Audio = preload("res://weapons/corn_gun_fx.gd")
const Feedback = preload("res://scripts/cornfield/combat_feedback.gd")
const SAVE := "user://r26_modular_layout.json"
var manifest: Dictionary = {}
var world: Node3D
var player: CharacterBody3D
var director: Node3D
var camera: Camera3D
var ui: CanvasLayer
var gameplay: Node3D
var weapon_controller: Node3D
var feedback: Node3D
var camera_target := Vector3.ZERO
var quitting := false
var exit_started := false
var rebuilding := false
var focused := true
var finished := false
var content_error := ""
var current_module := 0
var coins := 0

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit=false
	get_window().title="田埂上的暑假 · 乡间小路试玩"
	_setup_inputs()
	gameplay=Node3D.new();gameplay.process_mode=Node.PROCESS_MODE_PAUSABLE;add_child(gameplay)
	var env:=WorldEnvironment.new();env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("afc6b0")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("fff1cc");env.environment.ambient_light_energy=.55;add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-28,0);sun.light_color=Color("ffe5b2");sun.light_energy=.9;sun.shadow_enabled=true;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL;add_child(sun)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=15;camera.near=.1;camera.far=55;add_child(camera);camera.make_current()
	ui=UI.new();ui.process_mode=Node.PROCESS_MODE_ALWAYS;ui.input_guard=func()->bool:return focused and not quitting and not rebuilding
	add_child(ui)
	ui.controls_hint="WASD 跑动 · 左键挥棍 · Esc 暂停"
	ui.refresh_controls_hint("stick");ui.update_minimap({"visible":false})
	if FileAccess.file_exists(SAVE):
		var result:=Store.load_layout(SAVE)
		if not result.ok:_fail(str(result.error));return
		manifest=result.manifest
	else:
		var requested:=OS.get_environment("R26_SEED")
		manifest=Layout.generate(int(requested) if requested.is_valid_int() else 20)
		var error:=Store.save_layout(SAVE,manifest)
		if not error.is_empty():_fail(error);return
	_install()

func _setup_inputs() -> void:
	for action: String in ["move_left","move_right","move_up","move_down","run","pause"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		var event:=InputEventKey.new()
		event.physical_keycode={"move_left":KEY_A,"move_right":KEY_D,"move_up":KEY_W,"move_down":KEY_S,"run":KEY_SHIFT,"pause":KEY_ESCAPE}[action]
		if not InputMap.action_has_event(action,event):InputMap.action_add_event(action,event)
	for action: String in ["attack","charge_shot"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT if action=="attack" else MOUSE_BUTTON_RIGHT
		if not InputMap.action_has_event(action,event):InputMap.action_add_event(action,event)

func _install() -> void:
	world=ModuleWorld.new();gameplay.add_child(world);world.build(Layout.materialize(manifest))
	if not world.spawn_domain_error().is_empty():_fail(world.spawn_domain_error());return
	player=Player.new();gameplay.add_child(player);player.configure(camera,"stick")
	player.position=world.definition.entry_position+Vector3.UP*.05;player.spawn_position=player.position
	player.world_min=Vector2.ONE*.25;player.world_max=world.definition.size-Vector2.ONE*.25
	player.died.connect(_died)
	feedback=Feedback.new();gameplay.add_child(feedback);feedback.bind_player(player)
	player.feedback_requested.connect(feedback.emit_feedback)
	world.set_occlusion_target(camera,player)
	camera_target=player.position+Vector3(0,.7,-2.8);_follow_camera(1)
	director=Director.new();gameplay.add_child(director)
	director.encounter_error.connect(_fail)
	director.feedback_requested.connect(feedback.emit_feedback)
	director.enemy_defeated.connect(func(_position:Vector3,reward:int):coins+=reward)
	director.configure(world,player,world.definition,1);director.set_spawn_visibility_ui(ui)
	var readability=preload("res://scripts/modular/map_readability.gd").new()
	gameplay.add_child(readability);readability.bind(player,director)
	for region: Dictionary in world.definition.module_regions:
		var label:=Label3D.new();label.text=str(region.landmark.title)
		label.position=Vector3(region.landmark.rect.get_center().x,2.1,region.landmark.rect.get_center().y);label.font_size=32;label.pixel_size=.007;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;world.add_child(label)
	ui.toast("从村口出发，认老井、粮袋和红砖墙，沿土路清虫后到红旗回家。田地不能穿过；仅保存布局。")
	_refresh_map_ui()

func _process(delta: float) -> void:
	if quitting or rebuilding or not is_instance_valid(player):return
	_follow_camera(delta)
	for region: Dictionary in world.definition.module_regions:
		if region.rect.has_point(Vector2(player.position.x,player.position.z)):current_module=region.index
	_refresh_map_ui()
	if not finished and director.is_complete() and player.position.distance_to(world.definition.reward_position)<2:
		finished=true;_panel("赶在饭前回家","虫群散了，这条乡间小路已经走通。布局已保存；重新打开会从村口重新试玩。",[{"text":"退出试玩","action":quit_slice}],"settlement")

func _refresh_map_ui() -> void:
	if not is_instance_valid(ui) or not is_instance_valid(player) or not is_instance_valid(director):return
	var living:=0
	for enemy in director.enemies:
		if is_instance_valid(enemy) and not enemy.dead:living+=1
	var started:bool=director._spawned>0 or not director._warnings.is_empty()
	for segment:Dictionary in director.segments:
		started=started or int(segment.activations)>0
	var state:="战斗进行中 · 出口锁定" if started else "战斗未开始 · 出口锁定"
	var objective:=_progress_hint()
	if director.is_complete():state="虫群已清理 · 前往红旗"
	if finished and player.hp>0:
		state="本轮已走通";objective="本轮试玩结束 · 可退出试玩"
	if get_tree().paused:
		state="已暂停 · 出口开放" if director.is_complete() else "已暂停 · 出口锁定"
		objective="已暂停 · 继续后前往红旗" if director.is_complete() else "已暂停 · 继续后恢复战斗"
	if player.hp<=0:
		state="本轮结束";objective="体力耗尽 · 可退出试玩"
	elif finished:
		state="本轮已走通";objective="本轮试玩结束 · 可退出试玩"
	if not content_error.is_empty():state="地图状态异常";objective="请查看提示后退出试玩"
	if rebuilding:state="准备新路线";objective="正在准备新路线"
	if exit_started:state="退出未完成";objective="请重试退出试玩"
	if quitting:state="正在退出";objective="正在退出试玩"
	world.set_return_open(director.is_complete())
	ui.update_status({"hp":player.hp,"max_hp":player.max_hp,"title":"%s · %d / %d"%[str(world.definition.module_regions[current_module].landmark.title),current_module+1,manifest.modules.size()],"weapon_label":"正手木棍","build_summary":"零花钱 %d · 布局 %d"%[coins,int(manifest.seed)],"coins":coins})
	ui.refresh_map_status(living,state)
	ui.hint.text=objective

func _progress_hint() -> String:
	if director.is_complete():return "虫群已清理 · 沿土路走到红旗出口"
	var living:=0
	var nearest:Node3D=null
	var near_exit:bool=player.position.distance_to(world.definition.reward_position)<2.5
	for enemy in director.enemies:
		if is_instance_valid(enemy) and not enemy.dead:
			living+=1
			if nearest==null or player.position.distance_to(enemy.position)<player.position.distance_to(nearest.position):nearest=enemy
	if near_exit:
		var target:Vector3=nearest.position if nearest!=null else director.next_encounter_hint_target()
		var direction:String=_screen_direction(target) if target.is_finite() else "来路"
		return "出口未开放 · 虫群尚未清理 · 向%s沿土路返回"%direction
	if living>0:return "虫群来了 · 场上 %d 只 · 留意地面预警"%living
	if not director._warnings.is_empty():return "前方预警亮起 · 留出退路"
	var target:Vector3=director.next_encounter_hint_target()
	if not target.is_finite():return "沿土路推进，击退虫群后前往出口"
	if director._hint_probe_active():return "已到推进点 · 稍停观察地面，留出退路"
	return "前方还有虫群 · 向%s沿路推进"%_screen_direction(target)

func _screen_direction(target:Vector3) -> String:
	# When the target is around a field, point along the authored road first.
	if not world.segment_clear(player.position,target,.23):
		var route:PackedVector3Array=world.definition.main_route
		var player_progress:float=_route_progress(player.position,route)
		var target_progress:float=_route_progress(target,route)
		var progress:=0.0
		if target_progress>player_progress:
			for index in range(1,route.size()):
				progress+=route[index-1].distance_to(route[index])
				if progress>player_progress+.5:target=route[index];break
		else:
			var previous:Vector3=route[0]
			for index in range(1,route.size()):
				progress+=route[index-1].distance_to(route[index])
				if progress>=player_progress-.5:target=previous;break
				previous=route[index]
	var offset:=camera.unproject_position(target)-camera.unproject_position(player.position)
	var directions:=["右方","右下方","下方","左下方","左方","左上方","上方","右上方"]
	return directions[posmod(roundi(atan2(offset.y,offset.x)/(PI*.25)),8)]

func _route_progress(point:Vector3,route:PackedVector3Array) -> float:
	var distance:=INF;var result:=0.0;var progress:=0.0
	for index in range(1,route.size()):
		var nearest:=Geometry3D.get_closest_point_to_segment(point,route[index-1],route[index])
		if point.distance_squared_to(nearest)<distance:
			distance=point.distance_squared_to(nearest);result=progress+route[index-1].distance_to(nearest)
		progress+=route[index-1].distance_to(route[index])
	return result

func _follow_camera(delta: float) -> void:
	camera_target=camera_target.lerp(player.position+Vector3(0,.7,-2.8),1-exp(-delta*4))
	camera.position=camera_target+Vector3(15,19,15);camera.look_at(camera_target,Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if quitting or rebuilding or not focused or event.is_echo():return
	if event.is_action_pressed("attack") and not get_tree().paused and is_instance_valid(player):player.request_attack();get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and not finished:
		if ui.opened and content_error.is_empty():_resume()
		elif not ui.opened:_panel("暂停试玩","仅保存地图布局；退出重开回入口，战斗进度不保留。",[{"text":"继续","action":_resume},{"text":"生成另一条玉米路线","action":new_layout},{"text":"退出试玩","action":quit_slice}])

func _resume() -> void:
	if quitting or exit_started or rebuilding or not focused or finished or not content_error.is_empty():return
	ui.close_panel();get_tree().paused=false
	if is_instance_valid(player):player.controls_enabled=true
	_refresh_map_ui()
func _panel(title:String,body:String,choices:Array,kind:String="pause") -> void:
	if is_instance_valid(player):player.controls_enabled=false;player.cancel_actions()
	ui.show_panel(title,body,choices,kind);get_tree().paused=true
	_refresh_map_ui()
func _died() -> void:
	finished=true;_panel("体力耗尽","本轮试玩结束。仅保存布局；退出重开回入口，战斗进度不保留。",[{"text":"退出试玩","action":quit_slice}],"settlement")
func _fail(reason:String) -> void:
	content_error=reason
	push_error("R26 content: "+reason)
	if is_instance_valid(ui):_panel("地图未能安全建立",reason,[{"text":"退出试玩","action":quit_slice}])
func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(ui):quit_slice()
	elif what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused=false
		for action:String in ["move_left","move_right","move_up","move_down","attack","charge_shot"]:
			if InputMap.has_action(action):Input.action_release(action)
		if is_instance_valid(player):player.controls_enabled=false;player.cancel_actions()
		if is_instance_valid(ui) and not quitting and not exit_started and not rebuilding and not ui.opened:
			_panel("已暂停","回到窗口后选择继续。",[{"text":"继续","action":_resume},{"text":"退出试玩","action":quit_slice}])
		get_tree().paused=true
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN:focused=true

func new_layout(seed_value:int=-1) -> bool:
	if quitting or exit_started or rebuilding or not focused:return false
	rebuilding=true
	var candidate:=Layout.generate(seed_value if seed_value>=0 else int(Time.get_ticks_usec()%2147483647))
	_panel("准备新路线","正在保存布局。",[])
	if not await Audio.await_owned_shutdown(get_tree()):
		rebuilding=false
		_panel("暂不能更换路线","声音收尾尚未完成，当前布局已保留。",[{"text":"返回","action":_resume}]);return false
	var error:=Store.save_layout(SAVE,candidate)
	if not error.is_empty():
		rebuilding=false
		_panel("布局保存失败",error+"；当前布局保留。",[{"text":"返回","action":_resume}]);return false
	if is_instance_valid(director):director.shutdown()
	for child in gameplay.get_children():child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	manifest=candidate;finished=false;content_error="";coins=0;current_module=0
	_install();rebuilding=false
	if content_error.is_empty():_resume();return true
	return false

func quit_slice() -> void:
	if quitting or rebuilding:return
	exit_started=true
	quitting=true
	_panel("正在退出","等待声音收尾。",[])
	if is_instance_valid(player):player.controls_enabled=false;player.cancel_actions()
	if is_instance_valid(director):director.shutdown()
	if not await Audio.await_owned_shutdown(get_tree()):
		quitting=false;_panel("声音收尾尚未完成","请重试退出。",[{"text":"重试","action":quit_slice}]);return
	get_tree().paused=false
	get_tree().quit()
