extends MultiMeshInstance3D
## Visual-only instancing. Every projectile remains a separate authoritative
## node with its unchanged swept raycast, lifetime, source and damage.
const CAPACITY:=80
const HALF_SIZE:=Vector3(.11,.11,.11)
func _ready() -> void:
	name="HostileProjectileVisuals"
	multimesh=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.mesh=make_mesh()
	multimesh.instance_count=CAPACITY
	multimesh.visible_instance_count=0
	material_override=make_material()
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
func sync_projectiles(projectiles:Array) -> void:
	var cursor:=0
	var bounds:=AABB()
	var inverse:=global_transform.affine_inverse()
	for projectile in projectiles:
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():continue
		if cursor>=CAPACITY:break # Same hard cap enforced by the room director.
		var local_transform:Transform3D=inverse*projectile.global_transform
		multimesh.set_instance_transform(cursor,local_transform)
		var box:AABB=local_transform*AABB(-HALF_SIZE,HALF_SIZE*2)
		bounds=box if cursor==0 else bounds.merge(box)
		cursor+=1
	# Explicit current bounds avoid any renderer readback and off-origin culling.
	custom_aabb=bounds
	multimesh.visible_instance_count=cursor
func clear() -> void:
	if multimesh!=null:multimesh.visible_instance_count=0
static func make_mesh() -> SphereMesh:
	var sphere:=SphereMesh.new()
	sphere.radius=.11;sphere.height=.22
	sphere.radial_segments=16;sphere.rings=8
	return sphere
static func make_material() -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(.93,.72,.22)
	return material
