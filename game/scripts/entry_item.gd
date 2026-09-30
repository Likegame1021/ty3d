extends Node3D

const Shapes = preload("res://scripts/entry_shapes.gd")
const HOME := Vector3(-5.5, 0, 1)
var caption: Label3D
var halo: MeshInstance3D
var clock := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	position = HOME
	var box := Shapes.box(self, Vector3(0, 0.08, 0), Vector3(0.3, 0.13, 0.23), Color("617c70"))
	var metal := Shapes.material(Color("617c70"))
	metal.metallic = 0.55
	metal.roughness = 0.72
	box.material_override = metal
	Shapes.box(self, Vector3(0, 0.155, 0), Vector3(0.32, 0.026, 0.25), Color("9caa8c"))
	Shapes.box(self, Vector3(0, 0.17, 0), Vector3(0.17, 0.014, 0.11), Color("b9ae77"))
	caption = Shapes.caption(self, "E · 弹珠铁盒", 0.65)
	halo = Shapes.ring(self, 0.38, Color("e8cf91"))
	set_hint(false)

func _process(delta: float) -> void:
	clock += delta
	halo.scale = Vector3.ONE * (1.0 + sin(clock * 2.0) * 0.07)

func set_hint(value: bool) -> void:
	caption.visible = value
	halo.visible = value

func reset_item() -> void:
	visible = true
	clock = 0.0
	set_hint(false)
