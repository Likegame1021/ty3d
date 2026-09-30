extends Control

const HIT_DURATION := 0.16

var charge_ratio := 0.0
var hit_time := 0.0
var charged_hit := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_aim(screen_position: Vector2, ratio: float) -> void:
	global_position = screen_position
	charge_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()

func show_hit(charged: bool = false) -> void:
	charged_hit = charged
	hit_time = HIT_DURATION
	queue_redraw()

func reset_feedback() -> void:
	hit_time = 0.0
	charge_ratio = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if get_tree().paused or hit_time <= 0.0:
		return
	hit_time = maxf(0.0, hit_time - delta)
	queue_redraw()

func _draw() -> void:
	var ink := Color("213b2b")
	var warm := Color("fff0b4")
	var ready := Color("c9e294")
	var accent := ready if charge_ratio >= 1.0 else warm
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(direction * 5.0, direction * 10.0, ink, 4.0, true)
		draw_line(direction * 5.0, direction * 10.0, accent, 1.8, true)
	draw_circle(Vector2.ZERO, 2.5, ink)
	draw_circle(Vector2.ZERO, 1.2, accent)
	if charge_ratio > 0.0:
		draw_arc(Vector2.ZERO, 17.0, -PI * 0.5, PI * 1.5, 48, Color(0.10, 0.20, 0.14, 0.68), 4.0, true)
		draw_arc(Vector2.ZERO, 17.0, -PI * 0.5, -PI * 0.5 + TAU * charge_ratio, 48, accent, 2.5, true)
	if hit_time > 0.0:
		var hit_color := Color("f5d071") if charged_hit else warm
		hit_color.a = minf(1.0, hit_time / 0.08)
		var outer := 16.0 if charged_hit else 13.0
		for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var diagonal: Vector2 = direction.normalized()
			draw_line(diagonal * 7.0, diagonal * outer, ink, 4.0, true)
			draw_line(diagonal * 7.0, diagonal * outer, hit_color, 2.3, true)
