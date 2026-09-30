extends Node3D

const Shapes = preload("res://scripts/entry_shapes.gd")
const HOME := Vector3(-3.5, 0, 36)
var time := 0.0
var discovered := false
var figure: Node3D
var caption: Label3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	figure = Node3D.new()
	add_child(figure)
	Shapes.sphere(figure, Vector3(0, 0.25, 0), Vector3(0.45, 0.43, 0.48), Color("fff0c7"))
	Shapes.sphere(figure, Vector3(0, 0.48, 0.17), Vector3(0.29, 0.29, 0.27), Color("fff6da"))
	Shapes.box(figure, Vector3(0, 0.46, 0.33), Vector3(0.12, 0.07, 0.13), Color("e4a43f"))
	for side in [-1.0, 1.0]:
		Shapes.sphere(figure, Vector3(side * 0.12, 0.52, 0.25), Vector3.ONE * 0.038, Color("29312a"))
		Shapes.sphere(figure, Vector3(side * 0.22, 0.28, -0.02), Vector3(0.14, 0.2, 0.25), Color("ead4a5"))
	caption = Shapes.caption(self, "小鸡 · 无害", 0.95, Color("fff1c6"))
	reset_chicken()

func _process(delta: float) -> void:
	time += delta
	position = HOME + Vector3(sin(time * 0.73) * 0.42, 0, cos(time * 0.61) * 0.42)
	figure.rotation.y = atan2(cos(time * 0.73), -sin(time * 0.61))
	figure.position.y = absf(sin(time * 8)) * 0.018
	caption.visible = discovered

func reset_chicken() -> void:
	time = 0
	position = HOME
	discovered = false
	if caption:
		caption.visible = false
