extends RefCounted
## Floor-entry checkpoints are separate from live resources and durable receipts.
## Callers must show new floors / terminal screens only after a true return value.

const SAVE_VERSION := 2
const CURRENT_CONTENT_REVISION := 3
const BuildCatalog = preload("res://scripts/cornfield/build_catalog.gd")
const ToolHeapState = preload("res://scripts/cornfield/toolheap_state.gd")
const BuildEffects = preload("res://scripts/cornfield/build_effects.gd")
const WEAPON_BUILD_IDS := ["damage","arc","reach","knockback","recovery"]
const CHAPTER_META_REWARD := 10
const ROUTE_TYPES := ["ANVIL", "LEVEL", "REWARD", "ELITE", "EVENT", "SHOP"]
const WEAPON_IDS := ["stick", "corn"]
const TERMINAL_STATES := ["FAILED", "FORFEIT", "VICTORY_PENDING_SETTLEMENT", "COMPLETE"]

var data: Dictionary = {
	"run_id": "", "seed": 0, "floor": 1, "status": "COMPLETE", "result": "",
	"offers": [], "selected": "", "hp": 100.0, "coins": 25, "tier": 0,
	"loot": {}, "meta": 0, "elapsed": 0.0, "path_time": 0.0, "visited": [],
	"route_history": [], "weapon":"stick", "content_revision":CURRENT_CONTENT_REVISION,
	"builds_by_weapon":{"stick":{},"corn":{}}, "global_builds":{}, "dice":2, "toolheaps":{}, "legacy_damage_bonus":0.0,
}
var _save_path: String
var _baseline: Dictionary = {}
var _receipts: Dictionary = {}
var _revision := 0
var recovered_paths: Array[String] = []
var recovery_error := false

func _init(save_path: String = "user://cornfield_chapter_v1.json") -> void:
	_save_path = save_path

func load_save() -> bool:
	recovered_paths.clear()
	recovery_error = false
	var primary := _read_record(_save_path)
	var backup := _read_record(_save_path+".bak")
	if primary.is_empty() and backup.is_empty():
		return false
	for entry in [{"path":_save_path,"record":primary},{"path":_save_path+".bak","record":backup}]:
		if entry.record.is_empty() and FileAccess.file_exists(str(entry.path)):
			if not _preserve_invalid_copy(str(entry.path)):
				recovery_error = true
	var record := primary
	if record.is_empty() or _record_is_newer(backup,record):
		record = backup
	_revision = int(record.get("revision",0))
	_baseline = _normalize_data(record.baseline)
	_receipts = record.receipts.duplicate(true)
	if record.terminal.is_empty():
		data = _baseline.duplicate(true)
		data.selected = record.selected
		data.elapsed = float(record.elapsed)
		# Old ACTIVE final-shop checkpoints must not skip the new chapter Boss.
		# Terminal records stay untouched so an old settled run cannot resurrect.
		if int(data.floor) == 3:
			data.offers = ["BOSS"]
			data.selected = "BOSS" if not str(data.selected).is_empty() else ""
			_baseline.offers = ["BOSS"]
			_baseline.selected = data.selected
	else:
		data = _normalize_data(record.terminal)
	data.meta = int(record.meta)
	return true

func new_run(seed_value: int = 0, weapon_id: String = "stick") -> bool:
	if weapon_id not in WEAPON_IDS:
		return false
	var before := _snapshot()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var actual_seed := seed_value if seed_value != 0 else int(rng.randi())
	var offers: Array[String] = _make_offers(actual_seed, 1, 0)
	data = {
		"run_id": Crypto.new().generate_random_bytes(16).hex_encode(),
		"seed": actual_seed, "floor": 1, "status": "ACTIVE", "result": "",
		"offers": offers, "selected": "", "hp": 100.0, "coins": 25, "tier": 0,
		"loot": {}, "meta": int(before.data.meta), "elapsed": 0.0,
		"path_time": 0.0, "visited": [], "route_history": [], "weapon":weapon_id, "content_revision":CURRENT_CONTENT_REVISION,
		"builds_by_weapon":{"stick":{},"corn":{}}, "global_builds":{}, "dice":2, "toolheaps":{}, "legacy_damage_bonus":0.0,
	}
	_prepare_toolheap()
	_baseline = data.duplicate(true)
	return _persist_or_restore(before)

func choose_route(node_id: String) -> bool:
	if data.status != "ACTIVE" or not data.offers.has(node_id):
		return false
	if not data.selected.is_empty():
		return data.selected == node_id
	var before := _snapshot()
	data.selected = node_id
	return _persist_or_restore(before)

func resume_floor() -> bool:
	if data.status != "ACTIVE" or _baseline.is_empty():
		return false
	var before := _snapshot()
	data = _baseline.duplicate(true)
	data.selected = before.data.selected
	data.elapsed = before.data.elapsed
	data.meta = before.data.meta
	return _persist_or_restore(before)

func advance_floor() -> bool:
	if data.status != "ACTIVE" or data.floor >= 3 or data.selected.is_empty():
		return false
	var before := _snapshot()
	_archive_current_route()
	data.floor = int(data.floor) + 1
	data.offers = _make_offers(int(data.seed), int(data.floor), int(data.tier))
	data.selected = ""
	data.visited = []
	_prepare_toolheap()
	_baseline = data.duplicate(true)
	return _persist_or_restore(before)

func next_node_offers() -> Array[String]:
	if int(data.floor) >= 3 or data.status != "ACTIVE":
		return []
	return _make_offers(int(data.seed),int(data.floor)+1,int(data.tier))

func advance_to_node(node_id: String, displayed_offers: Array) -> bool:
	# One disk transaction: spending time in the old node is still live progress;
	# only choosing a destination commits the new baseline and its route marker.
	if data.status != "ACTIVE" or data.floor >= 3 or data.selected.is_empty():
		return false
	var destination_floor := int(data.floor) + 1
	if not displayed_offers.has(node_id):
		return false
	if destination_floor == 3:
		if displayed_offers != ["BOSS"] or node_id != "BOSS":
			return false
	elif not _valid_offers(displayed_offers, destination_floor):
		return false
	var before := _snapshot()
	_archive_current_route()
	data.floor = int(data.floor)+1
	data.offers = displayed_offers.duplicate()
	data.selected = node_id
	data.visited = []
	_prepare_toolheap()
	_baseline = data.duplicate(true)
	return _persist_or_restore(before)

func _archive_current_route() -> void:
	# History belongs to the same transaction as the destination checkpoint.
	# Keep the exact offers: upgrades can change what the same seed would offer.
	data.route_history.append({
		"floor": int(data.floor),
		"offers": data.offers.duplicate(),
		"selected": data.selected,
	})

func end_run(result: String) -> bool:
	if result not in ["FAILED", "FORFEIT", "VICTORY_PENDING_SETTLEMENT"]:
		return false
	if data.status != "ACTIVE":
		return data.status == result
	var before := _snapshot()
	data.status = result
	data.result = result
	return _persist_or_restore(before)

func settle() -> bool:
	if data.status == "COMPLETE":
		return not data.run_id.is_empty()
	if data.status not in TERMINAL_STATES:
		return false
	var before := _snapshot()
	if data.status == "VICTORY_PENDING_SETTLEMENT":
		var receipt := _receipt_key("chapter_victory")
		if not _receipts.has(receipt) and not _receipts.has("%s:chapter_victory" % data.run_id):
			_receipts[receipt] = true
			data.meta += CHAPTER_META_REWARD
	data.result = data.status
	data.status = "COMPLETE"
	return _persist_or_restore(before)

func grant_meta(reward_id: String, amount: int) -> bool:
	if reward_id.is_empty() or amount < 0 or data.run_id.is_empty() or data.status == "COMPLETE":
		return false
	var receipt := _receipt_key(reward_id)
	if _receipts.has(receipt) or _receipts.has("%s:%s" % [data.run_id,reward_id]):
		return true
	var before := _snapshot()
	_receipts[receipt] = true
	data.meta += amount
	return _persist_or_restore(before)

func tick(delta: float, active: bool = true) -> void:
	if active and data.status == "ACTIVE" and is_finite(delta) and delta > 0.0:
		data.elapsed += delta
		data.path_time += delta

func save() -> bool:
	if _baseline.is_empty() or recovery_error:
		return false
	var revision := _next_revision()
	var record := {
		"revision":revision,
		"version": SAVE_VERSION,
		"baseline": _baseline.duplicate(true),
		"selected": data.selected,
		"elapsed": data.elapsed,
		"meta": data.meta,
		"receipts": _receipts.duplicate(true),
		"terminal": data.duplicate(true) if data.status in TERMINAL_STATES else {},
	}
	if not _valid_record(record):
		return false
	if not _write_record(record):
		return false
	_revision = revision
	return true

func _make_offers(seed_value: int, floor_number: int, tier: int) -> Array[String]:
	if floor_number >= 3:
		return ["BOSS"]
	var candidates: Array[String] = []
	for route: String in ROUTE_TYPES:
		if route != "ANVIL" or tier < 2:
			candidates.append(route)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + floor_number * 104729
	var offers: Array[String] = []
	for index in range(3):
		var selected := rng.randi_range(0, candidates.size() - 1)
		offers.append(candidates[selected])
		candidates.remove_at(selected)
	return offers

func _receipt_key(reward_id: String) -> String:
	return "%s:%d:%s" % [data.run_id, int(data.floor), reward_id]

func _snapshot() -> Dictionary:
	return {"data": data.duplicate(true), "baseline": _baseline.duplicate(true), "receipts": _receipts.duplicate(true),"revision":_revision}

func _persist_or_restore(before: Dictionary) -> bool:
	if save():
		return true
	data = before.data
	_baseline = before.baseline
	_receipts = before.receipts
	_revision = int(before.revision)
	return false

func _write_record(record: Dictionary) -> bool:
	var target := ProjectSettings.globalize_path(_save_path)
	var temporary := target + ".tmp"
	var backup_temp := target + ".bak.tmp"
	if DirAccess.dir_exists_absolute(target) or DirAccess.dir_exists_absolute(temporary) or DirAccess.dir_exists_absolute(backup_temp) or DirAccess.dir_exists_absolute(target+".bak"):
		return false
	if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
		return false
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or _read_record(temporary).is_empty():
		return false
	# Stage and validate both copies before committing either. Commit backup
	# first: reporting success must never leave an older ACTIVE fallback.
	if DirAccess.copy_absolute(temporary, backup_temp) != OK or _read_record(backup_temp).is_empty():
		return false
	if DirAccess.rename_absolute(backup_temp, target + ".bak") != OK:
		return false
	if DirAccess.rename_absolute(temporary, target) != OK:
		return false
	return true

func _read_record(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		return {}
	var record: Dictionary = parser.data
	return record if _valid_record(record) else {}

func _valid_record(record: Dictionary) -> bool:
	if not _integer(record.get("version")) or int(record.version) not in [1,SAVE_VERSION]:
		return false
	if not _nonnegative_integer(record.get("revision",0)) or float(record.get("revision",0))>2147483646.0:
		return false
	if not record.get("baseline") is Dictionary or not _valid_data(record.baseline):
		return false
	if int(record.version)==1 and _has_build_extension(record.baseline):
		return false
	if int(record.version) == SAVE_VERSION and not _valid_build_data(record.baseline):
		return false
	if record.baseline.status != "ACTIVE":
		return false
	if not record.get("selected") is String or (not record.selected.is_empty() and not record.baseline.offers.has(record.selected)):
		return false
	if not _nonnegative_number(record.get("elapsed")) or not _nonnegative_integer(record.get("meta")):
		return false
	if not record.get("receipts") is Dictionary or not record.get("terminal") is Dictionary:
		return false
	for receipt in record.receipts:
		if not receipt is String or record.receipts[receipt] != true:
			return false
	if not record.terminal.is_empty():
		# Validate primitive fields before any cross-field build references.
		if not _valid_data(record.terminal) or record.terminal.status not in TERMINAL_STATES:
			return false
		if int(record.version)==1 and _has_build_extension(record.terminal):
			return false
		if int(record.version) == SAVE_VERSION and not _valid_build_data(record.terminal):
			return false
		if int(record.terminal.get("content_revision",2)) != int(record.baseline.get("content_revision",2)):
			return false
		if record.terminal.run_id != record.baseline.run_id or record.terminal.floor != record.baseline.floor:
			return false
		if record.terminal.get("route_history", []) != record.baseline.get("route_history", []):
			return false
		if record.terminal.result not in ["FAILED", "FORFEIT", "VICTORY_PENDING_SETTLEMENT"]:
			return false
	return true

func _valid_data(value: Dictionary) -> bool:
	var content_revision=value.get("content_revision",2)
	if not _integer(content_revision) or int(content_revision) not in [2,CURRENT_CONTENT_REVISION]:
		return false
	if not value.get("run_id") is String or value.run_id.is_empty():
		return false
	if not _integer(value.get("seed")) or not _integer(value.get("floor")) or value.floor < 1 or value.floor > 3:
		return false
	if value.get("status") not in ["ACTIVE", "FAILED", "FORFEIT", "VICTORY_PENDING_SETTLEMENT", "COMPLETE"]:
		return false
	if not value.get("result") is String or not value.get("selected") is String:
		return false
	if not _valid_offers(value.get("offers"), int(value.floor)):
		return false
	var unique := {}
	for offer in value.offers:
		unique[offer] = true
	if value.get("weapon", "stick") not in WEAPON_IDS:
		return false
	if not value.selected.is_empty() and not unique.has(value.selected):
		return false
	# Version-one saves written before history existed remain valid. Gaps are
	# allowed after migration; unknown past choices must never be fabricated.
	if not _valid_route_history(value.get("route_history", []), int(value.floor)):
		return false
	if not _number(value.get("hp")) or not _nonnegative_integer(value.get("coins")) or not _nonnegative_integer(value.get("tier")) or int(value.tier)>2:
		return false
	if not _nonnegative_integer(value.get("meta")) or not _nonnegative_number(value.get("elapsed")) or not _nonnegative_number(value.get("path_time")):
		return false
	if not value.get("loot") is Dictionary or not value.get("visited") is Array:
		return false
	for item in value.loot:
		if not item is String or not _nonnegative_integer(value.loot[item]):
			return false
	for room in value.visited:
		if not room is String:
			return false
	return true

func _valid_route_history(history: Variant, current_floor: int) -> bool:
	if not history is Array:
		return false
	var previous_floor := 0
	for entry in history:
		if not entry is Dictionary or not _integer(entry.get("floor")):
			return false
		if entry.floor <= previous_floor or entry.floor >= current_floor:
			return false
		if not entry.get("offers") is Array or entry.offers.size() != 3:
			return false
		var unique := {}
		for offer in entry.offers:
			if not offer is String or offer not in ROUTE_TYPES or unique.has(offer):
				return false
			unique[offer] = true
		if not entry.get("selected") is String or not unique.has(entry.selected):
			return false
		previous_floor = int(entry.floor)
	return true

func _valid_offers(offers: Variant, floor_number: int) -> bool:
	if not offers is Array:
		return false
	if floor_number == 3 and offers == ["BOSS"]:
		return true
	# Retain old three-offer data solely for validation/migration and terminal history.
	if offers.size() != 3:
		return false
	var unique := {}
	for offer in offers:
		if not offer is String or offer not in ROUTE_TYPES or unique.has(offer):
			return false
		unique[offer] = true
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))

func _nonnegative_integer(value: Variant) -> bool:
	return _integer(value) and value >= 0

func _nonnegative_number(value: Variant) -> bool:
	return _number(value) and value >= 0

func _normalize_data(value: Dictionary) -> Dictionary:
	var normalized := value.duplicate(true)
	normalized.content_revision=int(normalized.get("content_revision",2))
	normalized.weapon = normalized.get("weapon", "stick")
	for key in ["seed", "floor", "coins", "tier", "meta"]:
		normalized[key] = int(normalized[key])
	for key in ["hp", "elapsed", "path_time"]:
		normalized[key] = float(normalized[key])
	for key in normalized.loot:
		normalized.loot[key] = int(normalized.loot[key])
	var offers: Array[String] = []
	offers.assign(normalized.offers)
	normalized.offers = offers
	normalized.route_history = normalized.get("route_history", [])
	for entry in normalized.route_history:
		entry.floor = int(entry.floor)
		var historical_offers: Array[String] = []
		historical_offers.assign(entry.offers)
		entry.offers = historical_offers
	# Version-one tiers migrate to one named legacy contribution. Never reapply
	# the old tier formula after this point, including on repeated v2 loads.
	normalized.legacy_damage_bonus = float(normalized.get("legacy_damage_bonus",float(normalized.tier)*0.35))
	normalized.builds_by_weapon = normalized.get("builds_by_weapon",{"stick":{},"corn":{}})
	normalized.global_builds = normalized.get("global_builds",{})
	normalized.dice = int(normalized.get("dice",2))
	normalized.toolheaps = normalized.get("toolheaps",{})
	for heap in normalized.toolheaps.values():
		for key in ["seed","floor","reroll_index"]:
			heap[key] = int(heap[key])
	for weapon in normalized.builds_by_weapon:
		for id in normalized.builds_by_weapon[weapon]:
			normalized.builds_by_weapon[weapon][id] = int(normalized.builds_by_weapon[weapon][id])
	for id in normalized.global_builds:
		normalized.global_builds[id] = int(normalized.global_builds[id])
	if int(normalized.floor)<=2 and not normalized.toolheaps.has(str(normalized.floor)):
		normalized.toolheaps[str(normalized.floor)] = ToolHeapState.create(str(normalized.run_id),int(normalized.seed),int(normalized.floor),str(normalized.weapon),_rank_payload(normalized))
	return normalized

func _rank_payload(source: Dictionary = {}) -> Dictionary:
	var value := data if source.is_empty() else source
	return {"builds_by_weapon":value.builds_by_weapon.duplicate(true),"global_builds":value.global_builds.duplicate(true)}

func _prepare_toolheap() -> void:
	if int(data.floor)<=2 and not data.toolheaps.has(str(data.floor)):
		data.toolheaps[str(data.floor)] = ToolHeapState.create(str(data.run_id),int(data.seed),int(data.floor),str(data.weapon),_rank_payload())

func current_toolheap() -> Dictionary:
	return data.get("toolheaps",{}).get(str(data.floor),{}).duplicate(true)

func build_effects(weapon_id: String = "") -> Dictionary:
	return BuildEffects.compile(_rank_payload(),str(data.weapon) if weapon_id.is_empty() else weapon_id,float(data.legacy_damage_bonus))

func act_on_toolheap(action: String) -> Dictionary:
	# These are live-node resources. The existing transaction commits them at
	# node travel/terminal state; Continue deliberately restores entry baseline.
	if data.status != "ACTIVE" or data.selected.is_empty() or int(data.floor)>2:
		return {"ok":false,"error":"当前没有可用工具堆"}
	var heap := current_toolheap()
	if heap.is_empty():
		return {"ok":false,"error":"当前没有可用工具堆"}
	var result: Dictionary = ToolHeapState.act(heap,action,int(data.dice),_rank_payload(),str(data.weapon))
	if result.ok:
		data.toolheaps[str(data.floor)] = result.heap.duplicate(true)
		data.dice = int(result.dice)
		data.builds_by_weapon = result.ranks.builds_by_weapon.duplicate(true)
		data.global_builds = result.ranks.global_builds.duplicate(true)
	return result

func _valid_build_data(value: Dictionary) -> bool:
	# v1 may omit this field for migration; v2 cross-field checks require it.
	if value.get("weapon") not in WEAPON_IDS:
		return false
	if not value.get("builds_by_weapon") is Dictionary or not value.get("global_builds") is Dictionary or not value.get("toolheaps") is Dictionary:
		return false
	if not _nonnegative_integer(value.get("dice")) or int(value.dice)>2:
		return false
	if not _nonnegative_number(value.get("legacy_damage_bonus")) or float(value.legacy_damage_bonus)>.700001:
		return false
	for weapon in value.builds_by_weapon:
		if weapon not in WEAPON_IDS or not value.builds_by_weapon[weapon] is Dictionary:
			return false
		for id in value.builds_by_weapon[weapon]:
			var rank = value.builds_by_weapon[weapon][id]
			if id not in WEAPON_BUILD_IDS or not _nonnegative_integer(rank) or rank>2:
				return false
	for weapon in WEAPON_IDS:
		if not value.builds_by_weapon.has(weapon):
			return false
	for id in value.global_builds:
		var rank = value.global_builds[id]
		if id != "clear_heal" or not _nonnegative_integer(rank) or rank>2:
			return false
	for key in value.toolheaps:
		if key not in ["1","2"] or not value.toolheaps[key] is Dictionary:
			return false
		var heap: Dictionary = value.toolheaps[key]
		if not heap.get("heap_id") is String or heap.heap_id.is_empty() or not heap.get("candidate_id") is String or not heap.get("resolved") is bool:
			return false
		if not _nonnegative_integer(heap.get("reroll_index")) or int(heap.reroll_index)>2:
			return false
		if not _integer(heap.get("seed")) or int(heap.seed)!=posmod(int(value.seed),ToolHeapState.RANDOM_MODULUS) or not _integer(heap.get("floor")) or int(heap.floor)!=int(key):
			return false
		if heap.get("weapon_id") not in WEAPON_IDS:
			return false
		if int(key)==int(value.floor) and str(heap.weapon_id)!=str(value.weapon):
			return false
		if not heap.candidate_id.is_empty() and heap.candidate_id not in WEAPON_BUILD_IDS+["clear_heal"]:
			return false
		if not heap.resolved and not heap.candidate_id.is_empty() and not BuildCatalog.allowed_ids(str(heap.weapon_id),_rank_payload(value)).has(str(heap.candidate_id)):
			return false
	if int(value.floor)<=2 and not value.toolheaps.has(str(int(value.floor))):
		return false
	return true

func _has_build_extension(value: Dictionary) -> bool:
	# Official v1 records contain none of these fields. Mixed-version records
	# are preserved for recovery rather than bypassing strict v2 validation.
	for key in ["builds_by_weapon","global_builds","dice","toolheaps","legacy_damage_bonus","content_revision"]:
		if value.has(key):
			return true
	return false

func _record_is_newer(candidate: Dictionary,current: Dictionary) -> bool:
	if candidate.is_empty():
		return false
	var candidate_revision := int(candidate.get("revision",0))
	var current_revision := int(current.get("revision",0))
	if candidate_revision != current_revision:
		return candidate_revision>current_revision
	# Pre-revision mirrors: a terminal record for the same run cannot be
	# superseded by its old ACTIVE checkpoint. Different runs prefer primary.
	return candidate.baseline.run_id==current.baseline.run_id and current.terminal.is_empty() and not candidate.terminal.is_empty()

func _next_revision() -> int:
	var latest := _revision
	for path in [_save_path,_save_path+".bak"]:
		var record := _read_record(path)
		if not record.is_empty():
			latest = maxi(latest,int(record.get("revision",0)))
	return latest+1

func _preserve_invalid_copy(path: String) -> bool:
	var destination := path+".recovery_%d_%d"%[int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(destination))!=OK:
		return false
	if FileAccess.get_file_as_bytes(path)!=FileAccess.get_file_as_bytes(destination):
		return false
	recovered_paths.append(destination)
	return true
