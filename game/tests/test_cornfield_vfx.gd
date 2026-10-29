extends SceneTree
## The renderer consumes a real attack clock and branch transform. No fixture
## can damage a target; authoritative combat integration is checked separately.
const Feedback = preload("res://scripts/cornfield/combat_feedback.gd")
const Attack = preload("res://scripts/attack_state.gd")
var checks := 0
var failures: Array[String] = []

class SourcePlayer extends Node3D:
	var attack = Attack.new()
	var branch_pivot: Node3D
	var hp := 100.0
	var controls_enabled := true
	var weapon_id := "stick"
	var ranged_stance := false
	func _ready() -> void:
		attack.configure(1.5416666,.59,.63)
		branch_pivot = Node3D.new()
		add_child(branch_pivot)
		var branch := MeshInstance3D.new()
		branch.name = "Branch"
		var shaft := CylinderMesh.new()
		shaft.height = .7
		shaft.top_radius = .012
		shaft.bottom_radius = .026
		branch.mesh = shaft
		branch.position.y = .28
		branch_pivot.add_child(branch)

func _initialize() -> void: call_deferred("run_checks")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ",label)
func finish() -> void:
	print("CORNFIELDS_VFX: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func run_checks() -> void:
	var feedback = Feedback.new()
	root.add_child(feedback)
	feedback.set_process(false)
	check(feedback.has_method("bind_player"),"feedback binds the actual branch owner instead of inventing a ground slash")
	check(feedback.has_method("trail_snapshot"),"bounded actual-tip sampling is inspectable")
	if failures.size() > 0:
		feedback.free()
		finish()
		return
	var player := SourcePlayer.new()
	root.add_child(player)
	feedback.bind_player(player)
	feedback._process(.016)
	check(feedback.trail_snapshot().is_empty(),"idle does not leave a trail")
	player.attack.begin(false)
	for index in 25:
		player.attack.tick(.016,false)
		player.branch_pivot.position.x += .03
		feedback._process(.016)
	check(feedback.trail_snapshot().is_empty(),"early anticipation remains clean")
	player.attack.tick(.105,false)
	for index in 8:
		player.branch_pivot.position.x += .04
		feedback._process(.008)
		player.attack.tick(.008,false)
	var samples: Array = feedback.trail_snapshot()
	check(samples.size() > 1 and samples.size() <= 12,"contact approach produces bounded actual-position samples")
	var branch: MeshInstance3D = player.branch_pivot.get_node("Branch")
	var exact_tip := branch.to_global(Vector3(0,branch.mesh.get_aabb().end.y,0))
	check(samples[-1].tip.is_equal_approx(exact_tip),"newest trail point is on the visible wood tip")
	check(samples[-1].tip.y > .5,"trail is not a broad ground-plane attack-radius arc")
	var band:float=samples[-1].tip.distance_to(samples[-1].inner)
	check(band>=.16 and band<=.20,"readable ribbon occupies only the distal18cm of the real stick")
	var trail_arrays:Array=feedback._trail_mesh.surface_get_arrays(0)
	var peak_alpha:=0.0
	var trail_edge:=false
	for color:Color in trail_arrays[Mesh.ARRAY_COLOR]:
		peak_alpha=maxf(peak_alpha,color.a)
		trail_edge=trail_edge or maxf(color.r,maxf(color.g,color.b))<.4
	check(peak_alpha>=.8 and peak_alpha<=.9 and trail_edge,"two-tone ribbon resolves a cream core and restrained brown edge")
	check(not feedback._trail_node.material_override.emission_enabled,"readability adds no glow or emissive sword material")
	var before_clock: float = player.attack.elapsed
	feedback.emit_feedback("slash",{"position":player.position,"direction":Vector3.FORWARD,"reach":1.35})
	check(feedback.active_count()==0,"bound slash event cannot also draw the obsolete ground arc")
	check(player.attack.elapsed == before_clock,"effects never advance the authoritative attack clock")
	var frozen: Array = feedback.trail_snapshot()
	paused = true
	feedback._process(.5)
	check(feedback.trail_snapshot()==frozen,"pause freezes trail samples and ages")
	feedback.emit_feedback("hit",{"position":Vector3.ZERO})
	check(feedback.active_count()==0,"pause rejects new impact decoration")
	paused = false
	feedback.clear_all()
	check(feedback.trail_snapshot().is_empty() and feedback.active_count()==0,"synchronous clear removes every trail and burst")
	for blocked in ["dead","disabled","corn","hidden","cancelled"]:
		player.hp = 0.0 if blocked=="dead" else 100.0
		player.controls_enabled = blocked!="disabled"
		player.weapon_id = "corn" if blocked=="corn" else "stick"
		branch.visible = blocked!="hidden"
		if blocked=="cancelled": player.attack.reset()
		feedback._process(.016)
		check(feedback.trail_snapshot().is_empty(),blocked+" cannot resurrect a stale slash")
	player.hp=100;player.controls_enabled=true;player.weapon_id="stick";branch.visible=true
	player.attack.begin(false)
	player.attack.tick(.55,false)
	for index in 80:
		player.branch_pivot.position.x += .01
		feedback._process(.001)
	check(feedback.trail_snapshot().size() <= 12,"high-render-rate sampling respects the twelve-point hard cap")
	feedback._process(.08)
	check(not feedback.trail_snapshot().is_empty(),"short100ms trail survives one80ms presentation gap")
	player.position += Vector3(10,0,0)
	feedback._process(.016)
	check(feedback.trail_snapshot().size() <= 1,"teleport cannot create a screen-wide ribbon")
	player.attack.reset()
	feedback._process(.016)
	check(feedback.trail_snapshot().is_empty(),"cancel/reset destroys the incomplete trail immediately")
	feedback.bind_player(null)
	player.free()
	for index in 100:
		feedback.emit_feedback("hit",{"position":Vector3.ZERO,"direction":Vector3.RIGHT,"species":"beetle"})
	check(feedback.active_count()==30,"one hundred repeated impacts remain at the existing thirty-slot cap")
	check(feedback.get_child_count() <= 31,"particles add no per-fragment scene nodes")
	for slot in feedback._slots:
		check(slot.node.mesh.get_surface_count()==1,"one draw surface per live burst")
		check(slot.node.material_override is ShaderMaterial,"small burst pieces use the shared ballistic shader")
		var array: Array = slot.node.mesh.surface_get_arrays(0)
		check(array[Mesh.ARRAY_TEX_UV].size() > 0 and array[Mesh.ARRAY_TEX_UV2].size() > 0,"burst geometry carries fragment velocity, not a scaling static confetti disc")
		var dark_edge:=false
		var flash_radius:=0.0
		var filled_centres:=0
		for vertex in array[Mesh.ARRAY_VERTEX].size():
			if array[Mesh.ARRAY_TEX_UV][vertex].y<0:
				var tint:Color=array[Mesh.ARRAY_COLOR][vertex]
				dark_edge=dark_edge or maxf(tint.r,maxf(tint.g,tint.b))<.5
				flash_radius=maxf(flash_radius,array[Mesh.ARRAY_VERTEX][vertex].length())
				if array[Mesh.ARRAY_VERTEX][vertex].length_squared()<.000001:filled_centres+=1
		check(dark_edge and flash_radius>=.17 and flash_radius<=.21,"localized cream contact tick has a small high-contrast wood-brown edge")
		check(filled_centres>=16,"contact accent has a filled readable centre rather than only hairline strokes")
		var flash_life=slot.debris_material.get_shader_parameter("flash_life")
		check(flash_life is float and flash_life>=.12 and flash_life<=.16,"declared shader support is120–160ms; visible frame duration is a separate native gate")
	feedback._process(.15)
	check(feedback.active_count()==30,"impact has a readable short lifetime")
	feedback._process(1.0)
	check(feedback.active_count()==0,"all fragments expire back into the bounded pool")
	feedback.clear_all()
	check(feedback.get_children().all(func(node):return not node is CollisionObject3D),"VFX contains no collision or damage nodes")
	feedback.free()
	await process_frame
	finish()
