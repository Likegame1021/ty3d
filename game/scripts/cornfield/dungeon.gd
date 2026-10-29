extends RefCounted
## Tree topology makes the elite an unavoidable cut vertex on the red-room path.
const Catalog = preload("res://scripts/cornfield/room_catalog.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP]
const OBJECTIVE_NAMES: Dictionary = {"ANVIL":"田边磨石","LEVEL":"树荫歇脚处","REWARD":"旧物收藏点","ELITE":"田间强敌","EVENT":"田间偶遇","SHOP":"田边小卖点","BOSS":"虫巢前哨"}

static func generate(seed_value: int, floor_number: int, node_id: String, content_revision: int = 3) -> Dictionary:
	if content_revision not in [2,3]:return {}
	var selected: String = "BOSS" if floor_number == 3 else node_id
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = ("3D|%d|%d|%s" % [seed_value,floor_number,selected]).hash()
	var count: int = rng.randi_range(5,8)
	var main_count: int = rng.randi_range(maxi(3,count-4),mini(5,count-1))
	var rooms: Dictionary = {}
	var links: Array = []
	var main_path: Array[String] = []
	var occupied: Dictionary = {}
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	occupied[Vector2i.ZERO] = true
	for index in range(1,main_count):
		var options: Array[Vector2i] = []
		for direction in DIRECTIONS:
			var next: Vector2i = cells[-1] + direction
			if _can_place(next,occupied):
				options.append(next)
		var chosen: Vector2i = options[rng.randi_range(0,options.size()-1)]
		cells.append(chosen)
		occupied[chosen] = true
	var template_offset: int = rng.randi_range(0,Catalog.TEMPLATE_COUNT-1)
	for index in range(main_count):
		var id: String = "entry" if index == 0 else ("exit" if index == main_count-1 else "fight_%d" % index)
		var template_index: int = (template_offset + index * 7) % Catalog.TEMPLATE_COUNT
		if index == main_count-1 and floor_number == 3:
			template_index = 23
		var room: Dictionary = Catalog.make_template(template_index)
		room.merge({"id":id,"grid":cells[index],"node_type":selected,"floor":floor_number,"content_revision":content_revision,"melee_fallback":"beetle"},true)
		room.completion = index == main_count-1
		room.elite = index == 1
		room.encounter = "none" if index == 0 else ("elite" if index == 1 else "swarm")
		room.kind = "entry" if index == 0 else "combat"
		if room.elite:
			room.title = "田埂强敌 · " + room.title
		if room.completion:
			room.kind = "exit"
			room.encounter = "boss" if floor_number == 3 else ("shop" if selected == "SHOP" else "swarm")
			room.title = "巨型玉米螟巢" if floor_number == 3 else ("田边小卖点" if selected == "SHOP" else "红旗 · " + room.title)
		rooms[id] = room
		main_path.append(id)
		if index > 0:
			_connect(rooms,links,main_path[index-1],id)
	# One or two short branches; each can have a second optional room.
	var branch_tips: Array[String] = []
	var branch_depths: Dictionary = {}
	for index in range(count-main_count):
		var candidates: Array = []
		var parents: Array = main_path.slice(0,main_path.size()-1) if branch_tips.size() < 2 else []
		# New runs can prepare before the mandatory elite. Revision2 preserves
		# its exact RNG/candidate sequence for existing node checkpoints.
		if content_revision>=3 and index==0 and floor_number<=2:
			parents=["entry"]
		if branch_tips.size() == 2:
			for tip in branch_tips:
				if branch_depths[tip] < 2:
					parents.append(tip)
		for parent_id in parents:
			for direction in DIRECTIONS:
				var next: Vector2i = rooms[parent_id].grid + direction
				if _can_place(next,occupied):
					candidates.append({"parent":parent_id,"cell":next})
		assert(not candidates.is_empty(),"A short branch must have an outward extension; never add a third branch or lengthen past two rooms")
		var choice: Dictionary = candidates[rng.randi_range(0,candidates.size()-1)]
		var id: String = "optional_%d" % index
		var room: Dictionary = Catalog.make_template(template_offset + (main_count+index)*7)
		room.merge({"id":id,"grid":choice.cell,"node_type":selected,"floor":floor_number,"optional":true,"content_revision":content_revision,"melee_fallback":"beetle"},true)
		room.kind = "objective" if index == 0 else ("event" if index == 1 else "combat")
		room.has_toolheap = index == 0 and floor_number <= 2
		room.encounter = "none" if index < 2 else "swarm"
		room.title = OBJECTIVE_NAMES.get(selected,"田间拾趣") if index == 0 else "田边岔路 · " + room.title
		rooms[id] = room
		occupied[choice.cell] = true
		_connect(rooms,links,choice.parent,id)
		branch_depths[id] = int(branch_depths.get(choice.parent,0))+1
		room.branch_depth = branch_depths[id]
		if branch_tips.has(choice.parent):
			branch_tips.erase(choice.parent)
		branch_tips.append(id)
	for id in rooms:
		var room: Dictionary = rooms[id]
		var center: Vector3 = Vector3(room.size.x*.5,0,room.size.y*.5)
		var arrival: String = room.get("arrival_side", "")
		if arrival != "":
			room.entry_position = Catalog.door_position(arrival,room.size) + Catalog.door_inward(arrival)*4.0
		var departure: String = room.get("departure_side", "")
		var endpoint: Vector3 = Catalog.door_position(departure,room.size) + Catalog.door_inward(departure)*6.0 if departure != "" else center + Vector3(0,0,-room.size.y*.22)
		room.main_route = PackedVector3Array([room.entry_position,center,endpoint])
		if id == "entry" and departure != "":
			# The first safe arrival is five walking units from its main-route
			# gate. The optional field remains explorable without forcing a long
			# empty walk before the first elite encounter.
			var inward: Vector3 = Catalog.door_inward(departure)
			var door: Vector3 = Catalog.door_position(departure,room.size)
			room.entry_position = door+inward*8.0
			room.main_route = PackedVector3Array([room.entry_position,door+inward*3.0])
			room.service_position = room.entry_position+inward.cross(Vector3.UP)*2.2
			room.reward_position = room.entry_position+inward*1.5
	return {"entry":"entry","objective":"optional_0","exit":"exit","main_path":main_path,"rooms":rooms,"links":links,"node_type":selected,"floor":floor_number,"content_revision":content_revision}

static func _can_place(cell: Vector2i, occupied: Dictionary) -> bool:
	if occupied.has(cell):
		return false
	var neighbors: int = 0
	for direction in DIRECTIONS:
		if occupied.has(cell+direction):
			neighbors += 1
	return neighbors == 1

static func _connect(rooms: Dictionary, links: Array, first: String, second: String) -> void:
	var delta: Vector2i = rooms[second].grid-rooms[first].grid
	var side: String = "east" if delta.x > 0 else ("west" if delta.x < 0 else ("south" if delta.y > 0 else "north"))
	rooms[first].doors[side] = second
	rooms[second].doors[Catalog.opposite_side(side)] = first
	rooms[second].arrival_side = Catalog.opposite_side(side)
	if not rooms[first].has("departure_side"):
		rooms[first].departure_side = side
	links.append([first,second])
