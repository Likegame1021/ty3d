extends Node3D

const Shapes = preload("res://scripts/entry_shapes.gd")
const HOME := Vector3(-3.8, 0, 7)
var time := 0.0
var discovered := false
var figure: Node3D
var caption: Label3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	figure = Node3D.new()
	add_child(figure)
	Shapes.sphere(figure, Vector3(0, 0.26, 0), Vector3(0.45, 0.42, 0.5), Color("fff2ca"))
	Shapes.sphere(figure, Vector3(0, 0.48, 0.18), Vector3(0.28, 0.29, 0.28), Color("fff7df"))
	Shapes.box(figure, Vector3(0, 0.45, 0.34), Vector3(0.12, 0.07, 0.14), Color("dfa334"))
	Shapes.box(figure, Vector3(0, 0.64, 0.19), Vector3(0.065, 0.11, 0.17), Color("d46445"))
	for side in [-1.0, 1.0]:
		Shapes.sphere(figure, Vector3(side * 0.11, 0.52, 0.25), Vector3.ONE * 0.035, Color("282b28"))
		Shapes.sphere(figure, Vector3(side * 0.2, 0.29, -0.02), Vector3(0.12, 0.22, 0.28), Color("ecd7a9"))
		Shapes.box(figure, Vector3(side * 0.085, 0.07, 0.02), Vector3(0.03, 0.13, 0.035), Color("d29a35"))
		Shapes.box(figure, Vector3(side * 0.085, 0.02, 0.08), Vector3(0.1, 0.035, 0.16), Color("d29a35"))
	caption = Shapes.caption(self, "小鸡 · 无害", 0.95, Color("fff2bc"))
	reset_animal()

func _process(delta: float) -> void:
	time += delta
	position = HOME + Vector3(sin(time * 0.85) * 0.55, 0, cos(time * 0.67) * 0.55)
	figure.rotation.y = atan2(cos(time * 0.85), -sin(time * 0.67))
	figure.position.y = absf(sin(time * 8.0)) * 0.018
	caption.visible = discovered

func reset_animal() -> void:
	time = 0.0
	position = HOME
	discovered = false
	if figure:
		figure.position = Vector3.ZERO
		figure.rotation = Vector3.ZERO
