class_name EncounterRecipe
extends RefCounted
## Pure deterministic revision-3 room roster; callers own spawning and rewards.

const Catalog = preload("res://scripts/cornfield/enemy_catalog.gd")
const MELEE_SPECIES: Array[String] = ["beetle", "locust", "mouse", "rooster"]
const RANGED_SPECIES: Array[String] = ["snail", "corn_borer"]
const INTRO_ROSTER: Array[String] = ["beetle", "beetle", "mouse", "beetle", "mouse", "beetle", "mouse", "beetle"]

## species must be a nonempty Array of ordinary Catalog String IDs. The
## explicit melee_fallback is required even if the authored pool has melee.
## First species has weight 3; each later authored entry has weight 1.
## Stable segment/group indices advance the cycle by one slot each. No call
## history, placement attempt, template hash, or global RNG affects the result.
## Empty means invalid content; callers must report it, never fake a clear.
static func roster(room: Dictionary, floor_number: int, segment_index: int, group_index: int, count: int, intro_group: bool) -> Array[String]:
	if count < 1 or count > 12:
		return []
	var raw_pool: Variant = room.get("species")
	var raw_fallback: Variant = room.get("melee_fallback")
	if not raw_pool is Array or raw_pool.is_empty():
		return []
	if not raw_fallback is String or not raw_fallback in MELEE_SPECIES:
		return []
	var pool: Array[String] = []
	var melee: Array[String] = []
	for id: Variant in raw_pool:
		if not id is String or not Catalog.SPECIES.has(id) or id == "boss_borer":
			return []
		pool.append(id)
		if id in MELEE_SPECIES:
			melee.append(id)

	# The teaching identity is fixed, including when a stale intro flag reaches
	# a later request. Validation above must also apply to the teaching room.
	if intro_group and floor_number == 1 and segment_index == 0 and group_index == 0 and count == 8:
		return INTRO_ROSTER.duplicate()

	var cycle: Array[String] = [pool[0], pool[0], pool[0]]
	for index in range(1, pool.size()):
		cycle.append(pool[index])
	var phase: int = (posmod(segment_index, cycle.size()) + posmod(group_index, cycle.size())) % cycle.size()
	var melee_phase := 0
	if not melee.is_empty():
		melee_phase = (posmod(segment_index, melee.size()) + posmod(group_index, melee.size())) % melee.size()
	var ranged_limit: int = floori(float(count) / 4.0)
	var ranged_used := 0
	var result: Array[String] = []
	for index in range(count):
		var id: String = cycle[(phase + index) % cycle.size()]
		if id in RANGED_SPECIES:
			if ranged_used < ranged_limit:
				ranged_used += 1
			elif not melee.is_empty():
				id = melee[melee_phase]
				melee_phase = (melee_phase + 1) % melee.size()
			else:
				id = raw_fallback
		result.append(id)
	return result
