extends SceneTree
const UI=preload("res://scripts/cornfield/game_ui.gd")
const Catalog=preload("res://scripts/cornfield/service_catalog.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _run() -> void:
	root.size=Vector2i(1280,800)
	var ui:=UI.new();root.add_child(ui);await process_frame
	for ids in [["ANVIL","EVENT","LEVEL"],["SHOP","ELITE","REWARD"]]:
		var offers:Array=[]
		for id in ids:
			var descriptor:=Catalog.describe(id);offers.append({"id":id,"title":descriptor.title,"description":descriptor.short_description,"room_count":6})
		ui.show_route_choices({"floor":1,"offers":offers,"history":[]},func(_id):pass,func():pass)
		await process_frame;await process_frame
		for button in ui.overlay.find_children("*","Button",true,false):
			if not button.has_meta("offer_id"):continue
			var id:String=button.get_meta("offer_id")
			var description:String=Catalog.describe(id).short_description
			check(button.tooltip_text.contains(description),"full exact benefit remains in tooltip "+id)
			for label in button.get_children():
				if label is Label and label.text==description:
					check(label.size.x<=130.01 and label.position.x+label.size.x<=button.size.x,"benefit cannot grow across adjacent card "+id)
					check(label.position.y+label.size.y<=146.01,"benefit stays above room-count row "+id)
					check(label.autowrap_mode!=TextServer.AUTOWRAP_OFF and label.max_lines_visible==2,"benefit has bounded two-line wrapping "+id)
					check(label.get_visible_line_count()>=mini(2,label.get_line_count()),"card actually displays both allocated benefit lines "+id)
	ui.queue_free();await process_frame
	print("CORNFIELDS_ROUTE_COPY %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
