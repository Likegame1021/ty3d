extends RefCounted
## Single-layer state machine. Every result owns its nested dictionaries.
## The game owns persistence, run resources, input locks and receipt transactions.
const Catalog = preload("res://scripts/cornfield/build_catalog.gd")
const STARTING_DICE := 2
const RANDOM_MODULUS := 2147483647
const MAX_REROLL_INDEX := 2147483646

static func create(run_id: String, seed: int, floor: int, weapon_id: String, ranks: Dictionary) -> Dictionary:
	if run_id.is_empty() or floor not in [1, 2] or weapon_id not in Catalog.WEAPON_IDS or not Catalog.is_valid_ranks(ranks):
		return {}
	var small_seed := posmod(seed, RANDOM_MODULUS)
	var heap := {
		"heap_id": "%s:%d:toolheap" % [run_id, floor],
		"seed": small_seed, "floor": floor, "weapon_id": weapon_id,
		"candidate_id": "", "reroll_index": 0, "resolved": false,
	}
	heap.candidate_id = _pick(Catalog.allowed_ids(weapon_id, ranks), small_seed, floor, 0, weapon_id)
	return heap

static func act(heap: Dictionary, action: String, dice: int, ranks: Dictionary, weapon_id: String) -> Dictionary:
	# Failure results are the unchanged input values, including invalid inputs.
	var result := {"ok": false, "heap": heap.duplicate(true), "dice": dice, "ranks": ranks.duplicate(true), "error": ""}
	if action not in ["accept", "skip", "reroll"]:
		return _reject(result, "invalid_action")
	if dice < 0:
		return _reject(result, "invalid_dice")
	if not _valid_heap(heap):
		return _reject(result, "invalid_heap")
	if not Catalog.is_valid_ranks(ranks):
		return _reject(result, "invalid_ranks")
	if weapon_id != heap.weapon_id:
		return _reject(result, "weapon_mismatch")
	if heap.resolved:
		return _reject(result, "already_resolved")
	if action == "skip":
		result.heap.resolved = true
		return _complete(result)
	var allowed := Catalog.allowed_ids(weapon_id, ranks)
	var candidate: String = heap.candidate_id
	if candidate.is_empty():
		return _reject(result, "no_candidate")
	if not allowed.has(candidate):
		return _reject(result, "candidate_not_allowed")
	if action == "reroll":
		if dice == 0:
			return _reject(result, "no_dice")
		if int(heap.reroll_index) >= MAX_REROLL_INDEX:
			return _reject(result, "reroll_limit")
		if allowed.size() > 1:
			allowed.erase(candidate)
		result.heap.reroll_index = int(heap.reroll_index) + 1
		result.heap.candidate_id = _pick(allowed, int(heap.seed), int(heap.floor), int(result.heap.reroll_index), weapon_id)
		result.dice = dice - 1
	else:
		var rank_value := Catalog.rank_for(candidate, ranks, weapon_id) + 1
		var definition := Catalog.get_definition(candidate)
		if definition.scope == "global":
			if not result.ranks.has("global_builds"):
				result.ranks.global_builds = {}
			result.ranks.global_builds[candidate] = rank_value
		else:
			if not result.ranks.has("builds_by_weapon"):
				result.ranks.builds_by_weapon = {}
			if not result.ranks.builds_by_weapon.has(weapon_id):
				result.ranks.builds_by_weapon[weapon_id] = {}
			result.ranks.builds_by_weapon[weapon_id][candidate] = rank_value
		result.heap.resolved = true
	return _complete(result)

static func _valid_heap(heap: Dictionary) -> bool:
	for key in ["heap_id", "candidate_id", "weapon_id"]:
		if not heap.get(key) is String:
			return false
	if str(heap.heap_id).is_empty() or heap.weapon_id not in Catalog.WEAPON_IDS:
		return false
	if typeof(heap.get("resolved")) != TYPE_BOOL:
		return false
	for key in ["seed", "floor", "reroll_index"]:
		var value: Variant = heap.get(key)
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return false
		if not is_finite(float(value)) or float(value) != floorf(float(value)):
			return false
	if heap.seed < 0 or heap.seed >= RANDOM_MODULUS or int(heap.floor) not in [1, 2] or heap.reroll_index < 0 or heap.reroll_index > MAX_REROLL_INDEX:
		return false
	if not str(heap.candidate_id).is_empty() and Catalog.get_definition(heap.candidate_id).is_empty():
		return false
	return true

static func _pick(allowed: Array[String], seed: int, floor: int, reroll_index: int, weapon_id: String) -> String:
	if allowed.is_empty():
		return ""
	# All arithmetic stays well inside int64 and the saved state fits exact JSON numbers.
	# Do not use global RNG state, run UUID hashes, or 64-bit RNG state serialization.
	var value := seed
	for part in [floor, reroll_index + 1]:
		value = (value * 48271 + int(part) * 69621 + 1) % RANDOM_MODULUS
	for byte in weapon_id.to_utf8_buffer():
		value = (value * 31 + int(byte)) % RANDOM_MODULUS
	return allowed[value % allowed.size()]

static func _reject(result: Dictionary, error: String) -> Dictionary:
	result.error = error
	return result

static func _complete(result: Dictionary) -> Dictionary:
	# JSON decodes numbers as floats; successful transitions emit canonical integers.
	for key in ["seed", "floor", "reroll_index"]:
		result.heap[key] = int(result.heap[key])
	result.ok = true
	return result
