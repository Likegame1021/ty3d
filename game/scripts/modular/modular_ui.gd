extends "res://scripts/cornfield/game_ui.gd"
## Map-only HUD: tile position and observed combat state use separate labels.
var battle_caption: Label
func _ready() -> void:
	super._ready()
	for child in base.get_children():
		if child is Label and child.text=="备好工具，再往深处走":
			battle_caption=child
			battle_caption.text="战斗未开始 · 出口锁定"
			battle_caption.size=Vector2(140,16)
			break
func refresh_map_status(living:int,state:String) -> void:
	wallet.text="全图场上存活 %d 只"%living
	if is_instance_valid(battle_caption):battle_caption.text=state
func refresh_controls_hint(_weapon_id: String) -> void:
	controls_hint="WASD 跑动 · 松开即停 · 左键挥棍 · Esc 暂停"
func _process(delta:float) -> void:
	notice_time-=delta
	if notice_time<=0:notice.text=controls_hint
