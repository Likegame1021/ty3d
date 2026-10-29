extends RefCounted
## Immutable V4 footprints, authored corner cuts and volumetric terrain.
## All positions are ground XZ world units; one unit equals 32 legacy pixels.

const Legacy = preload("res://scripts/cornfield/legacy_room_content.gd")
const TEMPLATE_COUNT: int = 24
const SIZE_SCALE: float = 2.2
const PLAYER_RADIUS: float = 0.22
const ENTRY_SAFE_RADIUS: float = 3.5
const DOOR_WIDTH: float = 3.6
const CORNER_CUTS: Array = [
	[.08,.11,.09,.07], [.13,.07,.11,.09], [.08,.12,.08,.12], [.11,.09,.07,.13],
	[.10,.08,.13,.07], [.07,.11,.12,.10], [.06,.12,.06,.11], [.12,.07,.10,.09],
	[.13,.12,.06,.07], [.11,.07,.13,.09], [.08,.13,.10,.06], [.12,.08,.07,.12],
	[.09,.11,.13,.06], [.07,.13,.08,.11], [.11,.06,.10,.13], [.13,.09,.06,.10],
	[.09,.07,.12,.13], [.06,.10,.13,.08], [.12,.11,.07,.08], [.08,.13,.09,.12],
	[.10,.12,.11,.07], [.13,.06,.09,.11], [.07,.09,.12,.13], [.10,.10,.10,.10],
]
const HEIGHTS: Dictionary = {"corn":1.25,"hay":1.25,"tree":2.6,"water":0.4,"fence":1.4,"brick":2.1,"well":1.2,"stone":0.85,"tools":1.7}

static func make_template(index: int) -> Dictionary:
	var template_index: int = posmod(index, TEMPLATE_COUNT)
	var authored: Dictionary = Legacy.TEMPLATES[template_index]
	var baseline: Vector2 = Legacy.BASELINE_SIZES[authored.baseline] / 32.0
	var size: Vector2 = baseline * SIZE_SCALE
	var cuts: Array = CORNER_CUTS[template_index]
	var a: float = cuts[0]
	var b: float = cuts[1]
	var c: float = cuts[2]
	var d: float = cuts[3]
	var normalized: Array[Vector2] = [Vector2(a,0),Vector2(1-b,0),Vector2(1-b,b),Vector2(1,b),Vector2(1,1-c),Vector2(1-c,1-c),Vector2(1-c,1),Vector2(d,1),Vector2(d,1-d),Vector2(0,1-d),Vector2(0,a),Vector2(a,a)]
	if template_index == 23:
		# A separately authored nest: generous octagonal core and four approach arms.
		normalized = [Vector2(.12,0),Vector2(.88,0),Vector2(1,.12),Vector2(1,.86),Vector2(.86,1),Vector2(.14,1),Vector2(0,.86),Vector2(0,.14)]
	var outline: Array[Vector2] = []
	for point in normalized:
		outline.append(point * size)
	var obstacles: Array = []
	for block in authored.blocks:
		var kind: String = block[0]
		var height: float = 1.85 if str(authored.id) == "hay_yard" and kind == "hay" else HEIGHTS.get(kind,1.2)
		obstacles.append({"id":"terrain_%d" % obstacles.size(),"kind":kind,"rect":Rect2(Vector2(block[1],block[2])*size,Vector2(block[3],block[4])*size),"height":height})
	var presentation := _presentation(str(authored.id),size)
	# A crossing is one authoritative opening: its water, banks, navigation and
	# no-spawn zone all meet the same 2.7m deck edges, not legacy 11m dry gaps.
	if str(authored.id) == "irrigation_bank":
		for zone: Rect2 in presentation.bridge_zones:
			for obstacle in obstacles:
				var channel: Rect2 = obstacle.rect
				if obstacle.kind != "water" or not is_equal_approx(channel.get_center().x,zone.get_center().x):
					continue
				if channel.get_center().y < zone.get_center().y:
					channel.size.y = zone.position.y-channel.position.y
				else:
					var end := channel.end.y
					channel.position.y = zone.end.y
					channel.size.y = end-channel.position.y
				obstacle.rect = channel
	var entry: Vector3 = Vector3(size.x * .5, 0, size.y * .66)
	return {"id":authored.id,"template_id":authored.id,"content_version":2,"title":authored.title,"presentation":presentation,
		"kind":"combat","grid":Vector2i.ZERO,"size":size,"doors":{},"completion":false,
		"encounter":"swarm","elite":false,"outline":outline,"obstacles":obstacles,
		"main_route":PackedVector3Array([entry,Vector3(size.x*.5,0,size.y*.5),Vector3(size.x*.5,0,7)]),
		"entry_position":entry,"baseline_size":baseline,"baseline_area":baseline.x*baseline.y,
		"species":authored.species.duplicate(),"door_width":DOOR_WIDTH,"ground_y":0.0,
		"reward_position":Vector3(size.x*.5,0,size.y*.43),"service_position":Vector3(size.x*.5,0,size.y*.46),
		"breakables":[{"id":"prop_0","kind":"jar","position":Vector3(size.x*.13,0,size.y*.42),"hp":12},
			{"id":"prop_1","kind":"crate","position":Vector3(size.x*.87,0,size.y*.60),"hp":12},
			{"id":"prop_2","kind":"hay","position":Vector3(size.x*.41,0,size.y*.87),"hp":12}]}

static func door_inward(side: String) -> Vector3:
	return {"north":Vector3.BACK,"south":Vector3.FORWARD,"east":Vector3.LEFT,"west":Vector3.RIGHT}.get(side,Vector3.ZERO)

static func opposite_side(side: String) -> String:
	return {"north":"south","south":"north","east":"west","west":"east"}.get(side,"")

static func door_position(side: String, size: Vector2) -> Vector3:
	return {"north":Vector3(size.x*.5,0,0),"south":Vector3(size.x*.5,0,size.y),"east":Vector3(size.x,0,size.y*.5),"west":Vector3(0,0,size.y*.5)}.get(side,Vector3.ZERO)

static func _presentation(id: String,size: Vector2) -> Dictionary:
	var bridges: Array[Rect2] = []
	if id=="irrigation_bank":
		# The channel endpoints are derived from these crossings in make_template.
		# The ground-level deck is passable; its complete approach excludes spawns.
		for center in [Vector2(.2425,.525),Vector2(.7525,.49)]:
			bridges.append(Rect2(center*size-Vector2(size.x*.045+.9,2.7)*.5,Vector2(size.x*.045+.9,2.7)))
	return {"profile":id,"bridge_zones":bridges,"key_room":id in ["long_furrows","broken_wall","irrigation_bank","hay_yard","pump_corner","borer_nest"],"soil_tint":Color("796440"),"furrow_direction":Vector2.RIGHT if id=="long_furrows" else Vector2.DOWN}
