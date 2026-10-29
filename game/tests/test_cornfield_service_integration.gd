extends SceneTree
const Game=preload("res://scripts/cornfield/game.gd")
const Catalog=preload("res://scripts/cornfield/service_catalog.gd")
class InvalidAnchorWorld:
	extends Game.World
	func resolve_service_anchor() -> Dictionary:
		return {"ok":false,"position":Vector3.INF,"path_length":INF,"short_path":false}
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func all_text(node:Node) -> String:
	var result:String=node.text+"\n" if node is Label or node is Button else ""
	for child in node.get_children():result+=all_text(child)
	return result
func economic(game:Node3D) -> Dictionary:
	return {"hp":game.player.hp,"coins":game.run.data.coins,"loot":game.run.data.loot.duplicate(true),"resolved":game.room_states[game.current_room].resolved}
func _run() -> void:
	var game:=Game.new();game.test_mode=true;game.save_path="user://service_integration_%d.json"%Time.get_ticks_usec()
	root.add_child(game);await process_frame;game.set_process(false)
	game._start_new_run(5);game._choose_route(str(game.run.data.offers[0]))
	for id in ["ANVIL","LEVEL","REWARD","ELITE","EVENT","SHOP","BOSS"]:
		var preview:Dictionary=game._preview_offers(1,[id])[0]
		check(preview.description==Catalog.describe(id).short_description and preview.title==Catalog.describe(id).title,"macro card uses exact service catalog "+id)
	game._enter_room("optional_0");game.player.set_physics_process(false)
	var anchor:Dictionary=game.world.resolve_service_anchor()
	check(anchor.ok and anchor.short_path and game.service_marker.position.is_equal_approx(anchor.position+Vector3.UP*2),"revision3 prop and marker use resolved safe short anchor")
	check(game.service_marker.text.contains("免费强化"),"unresolved heap advertises its one candidate")
	game._show_service();game._on_toolheap_action("skip")
	check(not game.service_marker.text.contains("免费强化"),"heap skip removes free-growth advertisement")
	var actual:Dictionary=game.dungeon.rooms[game.current_room]
	actual.node_type="ANVIL";actual.kind="objective";actual.encounter="none"
	game.run.data.selected="ANVIL";game.room_states[game.current_room].resolved=false
	if game.has_method("_refresh_service_marker"):game._refresh_service_marker()
	game._show_service();var copy:=all_text(game.ui.overlay)
	check(copy.contains("8") and not copy.contains("强化本局武器"),"ANVIL service only promises existing 8-coin supplement")
	var before:=economic(game);game._resolve_service("BOSS")
	check(economic(game)==before,"stale wrong reward action cannot grant a different node payout")
	game._resolve_service("ANVIL")
	check(game.run.data.coins==int(before.coins)+8 and game.room_states[game.current_room].resolved,"catalog supply grants exact existing reward")
	check(game.service_marker.text.contains("已处理"),"one-shot completion updates marker truth")
	game._show_map()
	var map:Control=game.ui.overlay.get_child(0)
	var map_row:Dictionary={}
	for row in map.info.rooms:
		if row.id==game.current_room:map_row=row
		if row.id=="entry":check(row.get("kind","")=="start","safe entry uses the shelter glyph rather than an enemy")
	check(map_row.get("service_title","")==Catalog.describe("ANVIL").title and map_row.get("service_resolved",false),"visited room map exposes true service and completion")
	for button in map.find_children("*","Button",true,false):
		if button.get_meta("room_id","")==game.current_room:check(button.tooltip_text.contains("已处理") and button.tooltip_text.contains(Catalog.describe("ANVIL").title),"known map tooltip states the actual resolved service")
	for row in map.info.rooms:
		if not row.get("visited",false):check(not row.has("service_title") and not row.has("has_toolheap"),"unknown room stays masked")
	game._close_panel()
	actual.node_type="LEVEL";actual.kind="objective";actual.encounter="none";game.run.data.selected="LEVEL";game.room_states[game.current_room].resolved=false
	game.player.hp=40;game.run.data.coins=30
	game._show_service();before=economic(game)
	var real_path:String=game.run._save_path;var meta_before:int=game.run.data.meta
	game.run._save_path="res://scripts";game._resolve_service("LEVEL")
	check(economic(game)==before and game.run.data.meta==meta_before and game.ui.panel_kind=="service","failed meta save preserves service economics and refreshes retry")
	game.run._save_path=real_path;game._resolve_service("LEVEL")
	check(game.player.hp==70 and game.run.data.meta==meta_before+2 and game.room_states[game.current_room].resolved,"rest service grants exact heal/meta once after retry")
	game._resolve_service("LEVEL")
	check(game.player.hp==70 and game.run.data.meta==meta_before+2,"closed rest callback cannot repeat meta or healing")
	# A room-local event overrides the macro node, including SHOP.
	for node in ["REWARD","SHOP"]:
		actual.node_type=node;actual.kind="event";actual.encounter="event"
		game.run.data.selected=node;game.room_states[game.current_room].resolved=false
		game.player.hp=40;game.run.data.coins=30
		game._show_service();copy=all_text(game.ui.overlay)
		check(copy.contains("西瓜") and copy.contains("40") and not copy.contains("汽水"),"event presentation overrides macro "+node)
		before=economic(game);game._buy_heal();game._sell_loot();game._resolve_service(node)
		check(economic(game)==before,"event rejects inherited shop or reward mutations "+node)
		game._resolve_service("watermelon")
		check(game.player.hp==80 and game.run.data.coins==22 and game.room_states[game.current_room].resolved,"event resolves its exact cost/heal "+node)
	actual.node_type="SHOP";actual.kind="objective";actual.encounter="none";game.run.data.selected="SHOP";game.room_states[game.current_room].resolved=false
	game.player.hp=20;game.run.data.coins=30;game.run.data.loot["田间拾物"]=2
	game._show_service();before=economic(game);game._resolve_service("sell_loot")
	check(economic(game)==before,"shop sell action cannot execute through reward resolution")
	game._show_service();game._buy_heal();game._buy_heal();game._sell_loot()
	check(game.player.hp==90 and game.run.data.coins==16 and game.run.data.loot["田间拾物"]==0,"catalog shop remains repeatable with exact prices")
	game._resolve_service("skip")
	check(game.service_marker.text.contains("小卖点") and not game.service_marker.text.contains("已处理"),"repeatable shop marker remains available after exit")
	# Legacy revision preserves its previous physical service position.
	game.run.data.content_revision=2;game._install_node("REWARD");game._enter_room("optional_0")
	var route:PackedVector3Array=game.world.definition.main_route
	check(game.service_marker.position.is_equal_approx(route[int(route.size()/2)]+Vector3.UP*2),"legacy revision2 service anchor is unchanged")
	# A failed anchor must not place a prop at INF or silently finish a room.
	game.run.data.content_revision=3
	game.service_marker.queue_free();game.service_marker=null
	var invalid_world:=InvalidAnchorWorld.new();game.gameplay.add_child(invalid_world)
	invalid_world.definition=game.dungeon.rooms[game.current_room].duplicate(true);game.world=invalid_world
	game._make_service_marker(invalid_world.definition)
	check(game.ui.opened and game.ui.panel_kind=="confirm" and game.service_marker==null,"unsafe service anchor shows a recoverable error and creates no marker")
	# Malformed new content must be recoverable without awarding a fake clear.
	game._start_new_run(5)
	check(game._choose_route(str(game.run.data.offers[0])),"new run clears the previous content error")
	if game.dungeon.is_empty():
		paused=false;game.queue_free();await process_frame
		print("CORNFIELDS_SERVICE_INTEGRATION %d checks, %d failures"%[checks,failures]);quit(1);return
	game.dungeon.rooms[game.dungeon.main_path[1]].species=[]
	game._enter_room(str(game.dungeon.main_path[1]))
	check(game.ui.opened and paused and game.ui.panel_kind=="confirm" and all_text(game.ui.overlay).contains("结束"),"invalid encounter surfaces a recoverable end/exit panel")
	check(not game.room_states[game.current_room].cleared and not game.node_complete and game.director.enemies.is_empty(),"invalid encounter never grants clear or completion")
	check(not game._choose_route("BOSS") and not game._travel_to("entry"),"invalid-content panel cannot bypass progress")
	game._end_run("FORFEIT");check(game.run.data.status=="FORFEIT","invalid-content run can use normal durable forfeit")
	paused=false;game.queue_free();await process_frame
	print("CORNFIELDS_SERVICE_INTEGRATION %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
