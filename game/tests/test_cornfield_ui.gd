extends SceneTree

var failed := 0
var selected := ""
var broken_count := 0
var pickups := 0

class TestPlayer extends Node3D:
	var hp := 5.0
	var max_hp := 5.0

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failed += 1
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	for path in ["game_ui.gd", "ui/room_map.gd", "ui/route_choices.gd", "field_loot.gd", "village.gd"]:
		check(ResourceLoader.exists("res://scripts/cornfield/" + path), "cornfield component exists: " + path)
	if failed:
		quit(1)
		return
	root.size = Vector2i(1280,800)
	var ui = load("res://scripts/cornfield/game_ui.gd").new()
	root.add_child(ui)
	await process_frame
	check(ui.scale == Vector2(2,2) and ui.base.size == Vector2(640,400), "HUD uses readable 2x logical canvas at 1280x800")
	check(not ui.controls_hint.contains("冲刺") and not ui.controls_hint.contains("Shift") and ui.controls_hint.contains("松开即停"), "HUD accurately describes target weapons and running")
	ui.toast("验证提示")
	check(ui.notice.text == "验证提示" and ui.notice_time > 0, "toast immediately replaces control hint")
	ui.update_minimap({"visible":true,"player":Vector2(0.5,0.5),"outline":[Vector2.ZERO,Vector2.RIGHT,Vector2.ONE],"gates":[],"contacts":[]})
	check(ui.minimap.visible, "room minimap appears from existing interface")
	ui.update_boss({"hp":4,"max_hp":8,"title":"玉米螟"})
	check(ui.boss_panel.visible and ui.boss_health.value == 4, "boss meter preserves health interface")
	var offers := [
		{"id":"REWARD","title":"收获","description":"拾取补给","rooms":{"secret":{"grid":Vector2i(9,9)}}},
		{"id":"ELITE","title":"挑战","description":"迎战精英"},
		{"id":"EVENT","title":"田间","description":"田间见闻"}]
	ui.show_route_choices({"floor":2,"offers":offers,"history":[{"floor":1,"offers":offers,"selected":"ELITE"}]},_select,func():pass)
	await process_frame
	await process_frame
	var route = ui.overlay.get_child(0)
	var current: Array[Node] = []
	var history: Array[Node] = []
	for button in route.find_children("*","Button",true,false):
		if button.has_meta("offer_id"):
			current.append(button)
		if button.has_meta("historical_offer_id"):
			history.append(button)
	check(current.size()==3, "route panel presents exactly three current offers")
	check(history.size()==3 and history.all(func(b):return b.disabled and b.focus_mode==Control.FOCUS_NONE), "all historical offers are noninteractive")
	check(current.all(func(b):return b.preview_rooms.is_empty() and b.preview_links.is_empty()), "unexplored offer geometry is not retained by route cards")
	if current.size()==3:
		var target: Vector2 = current[2].get_global_transform_with_canvas()*(current[2].size*0.5)
		var motion := InputEventMouseMotion.new()
		motion.position = target
		root.push_input(motion)
		var click := InputEventMouseButton.new()
		click.position = target
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		root.push_input(click)
		click = click.duplicate()
		click.pressed = false
		root.push_input(click)
		await process_frame
		check(selected == "EVENT", "2x canvas transforms physical mouse clicks to correct offer")
	var rooms := [
		{"id":"fight_a","title":"入口","grid":Vector2i(0,0),"visited":true,"cleared":true,"can_travel":true},
		{"id":"fight_b","title":"秘密形状","grid":Vector2i(1,0),"outline":[Vector2.ZERO,Vector2(0.2,1),Vector2.ONE],"visited":false},
		{"id":"hidden","title":"深处分支","grid":Vector2i(2,0),"visited":false},
		{"id":"back","title":"来路","grid":Vector2i(-1,0),"visited":true,"cleared":true,"can_travel":true}]
	ui.show_room_map({"current":"fight_a","rooms":rooms,"links":[["fight_a","fight_b"],["fight_b","hidden"],["fight_a","back"]]},_select,func():pass)
	var map = ui.overlay.get_child(0)
	check(not map.locations.has("hidden"), "map does not leak unrevealed deep branches")
	var frontier: Button
	var back: Button
	for button in map.get_children():
		if button is Button and button.get_meta("room_id","")=="fight_b":
			frontier=button
		if button is Button and button.get_meta("room_id","")=="back":
			back=button
	check(frontier!=null and frontier.disabled and not frontier.room.has("outline"), "unexplored frontier is locked and conceals its geometry")
	check(back!=null and not back.disabled,"cleared visited room supports map travel")
	if back!=null:
		back.pressed.emit()
		check(selected=="back","map travel callback preserves room id")
	ui.close_panel()
	check(not ui.opened and ui.panel_kind.is_empty() and not ui.overlay.visible,"closing panel restores HUD state")
	ui.queue_free()
	await process_frame
	var loot_script = load("res://scripts/cornfield/field_loot.gd")
	# Fitting is called by configure before the level attaches the prop to its tree.
	var unattached = loot_script.new()
	var model := Node3D.new()
	unattached.add_child(model)
	var translated := Node3D.new()
	translated.position.y = 5.0
	model.add_child(translated)
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = Vector3(2,2,2)
	mesh.mesh = shape
	translated.add_child(mesh)
	unattached._fit_model(model,1.0)
	check(is_equal_approx(model.position.y+translated.position.y*model.scale.y-model.scale.y,0.0), "prop fitting works before entering scene tree and respects nested transforms")
	unattached.free()
	for kind in ["jar","crate","hay"]:
		var prop = loot_script.new()
		prop.configure("test_"+kind,kind,"heal")
		root.add_child(prop)
		check(prop.is_in_group("full_enemies"),"breakable participates in target weapon group: "+kind)
		check(prop.find_children("*","MeshInstance3D",true,false).size()>0 and prop.find_children("*","Sprite3D",true,false).is_empty(),"prop uses true 3D geometry: "+kind)
		prop.broken.connect(func(_id,_at,_drop):broken_count+=1)
		prop.receive_hit(Vector3.FORWARD)
		check(not prop.destroyed,"first branch strike damages prop without destroying: "+kind)
		prop.receive_projectile(1)
		check(prop.destroyed,"corn projectile breaks damaged prop: "+kind)
		prop.receive_projectile(99)
	await process_frame
	check(broken_count==3,"each prop emits its persistent drop exactly once")
	var actor := TestPlayer.new()
	root.add_child(actor)
	var heal = loot_script.Pickup.new()
	root.add_child(heal)
	heal.setup("heal_1","heal",actor)
	heal.collected.connect(func(_id,_kind):pickups+=1)
	heal._physics_process(1.0)
	check(not heal.done and pickups==0,"healing stays on ground while player is full")
	check(heal.find_children("*","Sprite3D",true,false).is_empty() and heal.find_children("*","MeshInstance3D",true,false).size()>0,"pickup is true 3D geometry")
	actor.hp=4
	heal._physics_process(0.01)
	check(heal.done and pickups==1,"healing collects when wounded player touches it")
	var village = load("res://scripts/cornfield/village.gd").new()
	root.add_child(village)
	village.install(actor)
	check(village.npcs.size()>=2,"prototype departure clearing exposes preparation and departure")
	for npc in village.npcs:
		var info: Dictionary=village.nearest_npc(npc.position)
		check(info.has_all(["name","role","dialogue","label","action"]),"village interaction preserves source schema")
	check(village.nearest_npc(Vector3(1000,0,1000)).is_empty(),"village interactions require proximity")
	check(village.find_children("*","Sprite3D",true,false).is_empty(),"village staging uses 3D assets rather than billboard scenery")
	check(village.find_children("*","Label3D",true,false).any(func(label):return label.text.contains("原型")),"village explicitly identifies prototype scope")
	village.queue_free()
	actor.queue_free()
	await process_frame
	print("Cornfield UI and props: %d failures" % failed)
	quit(1 if failed else 0)

func _select(id: String) -> void:
	selected=id
