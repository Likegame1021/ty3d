extends SceneTree
const Game=preload("res://scripts/cornfield/game.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, label: String) -> void:
 checks+=1
 print("PASS: " if ok else "FAIL: ",label)
 if not ok: failures+=1
func fixture() -> Node3D:
 var g:=Game.new();g.test_mode=true;g.save_path="user://independent_%d.json"%Time.get_ticks_usec()
 root.add_child(g);await process_frame
 g._start_new_run(5);g._choose_route(str(g.run.data.offers[0]));g.set_process(false)
 g._enter_room("optional_0");g.player.set_physics_process(false)
 return g
func button_with(ui: Node, fragment: String) -> Button:
 for button in ui.overlay.find_children("*","Button",true,false):
  if fragment in button.text:return button
 return null
func find_meta(ui: Node, key: String, value: String = "") -> Button:
 for button in ui.overlay.find_children("*","Button",true,false):
  if button.has_meta(key) and (value.is_empty() or str(button.get_meta(key))==value): return button
 return null
func _run() -> void:
 var g:=await fixture()
 g.run.act_on_toolheap("skip");g.dungeon.rooms[g.current_room].node_type="SHOP";g.player.hp=30;g.run.data.coins=25
 g._show_service()
 var stale_buy:=button_with(g.ui,"冰汽水")
 check(stale_buy!=null and g.ui.panel_kind=="service" and paused,"real service panel opens")
 g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
 stale_buy.pressed.emit()
 check(g.player.hp==30 and g.run.data.coins==25,"actual panel dispatch refuses focus-lost purchase")
 g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
 check(not stale_buy.disabled and not g.ui._display_submitted,"focus regain preserves a retryable service panel")
 stale_buy.pressed.emit()
 check(g.player.hp==65 and g.run.data.coins==15,"same service panel accepts one focused retry")
 g._close_panel();g.player.hp=30;g.run.data.coins=25
 stale_buy.pressed.emit()
 check(g.player.hp==30 and g.run.data.coins==25,"real stale button is harmless after close")
 g._buy_heal()
 check(g.player.hp==30 and g.run.data.coins==25,"authoritative buy callback rejects a closed modal")
 # Raw service guards must reject dead and terminal even with matching real panel.
 g.player.hp=0;g.pending_terminal="FAILED";g._show_service();g._buy_heal()
 check(g.player.hp==0,"matching panel cannot buy-heal a pending fatal result")
 paused=false;g.queue_free();await process_frame
 # Repeat the same real-dispatch rejection at both shared and per-view latch layers.
 for kind in ["toolheap","map","route"]:
  g=await fixture()
  if kind=="map":g._enter_room("entry");g._show_map()
  elif kind=="route":g.node_complete=true;g.next_offers=g.run.next_node_offers();g._show_routes()
  else:g._show_service()
  var key:String="toolheap_action" if kind=="toolheap" else "room_id" if kind=="map" else "offer_id"
  var value:String="accept" if kind=="toolheap" else "optional_0" if kind=="map" else ""
  var button:=find_meta(g.ui,key,value)
  var before:Dictionary=g.run.data.duplicate(true)
  var room_before:String=g.current_room
  check(button!=null and not button.disabled,"real active %s choice exists"%kind)
  g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT);button.pressed.emit()
  check(g.run.data==before and g.current_room==room_before,"real %s callback refuses focus-lost mutation"%kind)
  g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
  check(not button.disabled and not g.ui._display_submitted,"focus regain leaves %s panel retryable"%kind)
  paused=false;g.queue_free();await process_frame
 # A real route save failure rebuilds the display, invalidates old button and allows one retry.
 g=await fixture();g.node_complete=true;g.next_offers=g.run.next_node_offers();g._show_routes()
 var original_path:String=g.run._save_path;var source_room:String=g.current_room
 var route_button:=find_meta(g.ui,"offer_id")
 g.run._save_path="res://scripts";route_button.pressed.emit()
 check(int(g.run.data.floor)==1 and g.current_room==source_room and g.ui.panel_kind=="route" and paused,"route disk failure retains original node and route modal")
 g.run._save_path=original_path
 route_button.pressed.emit()
 check(int(g.run.data.floor)==1,"old route button after retry rebuild cannot advance")
 var retry_button:=find_meta(g.ui,"offer_id");retry_button.pressed.emit()
 check(int(g.run.data.floor)==2 and not g.ui.opened and not paused,"fresh route button commits successful retry")
 retry_button.pressed.emit()
 check(int(g.run.data.floor)==2,"consumed successful route button cannot advance again")
 paused=false;g.queue_free();await process_frame
 # Door request rechecks a target that ceases to exist before its deferred callback.
 g=await fixture();g._enter_room("entry");g.player.set_physics_process(false)
 var side:String=g.dungeon.rooms.entry.doors.keys()[0]
 var target:String=g.dungeon.rooms.entry.doors[side]
 g.player.position=g.world.get_door_position(side)+Game.INWARD[side]*.5;g.gameplay_time=2;g.last_door_time=0
 g._check_doors();var ticket:int=g._door_ticket
 check(g.room_change_pending,"door fixture schedules")
 var target_def:Dictionary=g.dungeon.rooms[target].duplicate(true)
 g.dungeon.rooms.erase(target)
 check(not g._commit_door_transition(ticket) and not g.room_change_pending and g.current_room=="entry","commit rejects removed target and clears its request")
 g.dungeon.rooms[target]=target_def
 paused=false;g.queue_free();await process_frame
 print("TASK4_INDEPENDENT_ADVERSE %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
