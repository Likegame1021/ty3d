extends RefCounted
## The catalog is the single source of upgrade arithmetic and display values.
## Ranks are {builds_by_weapon: {weapon_id: {id: rank}}, global_builds: {id: rank}}.
const MAX_RANK := 2
const WEAPON_IDS := ["stick", "corn"]
const IDS := ["damage", "arc", "reach", "knockback", "recovery", "clear_heal"]
const DEFINITIONS := {
	"damage": {
		"id": "damage", "name": "夯实枝节", "label": "打击伤害",
		"description": "每级打击伤害 +15%，按当前武器的基础伤害相加。",
		"scope": "weapon", "weapons": ["stick", "corn"], "max_rank": MAX_RANK,
		"effect_key": "damage_multiplier", "base": 1.0, "per_rank": 0.15, "operation": "add", "unit": "percent",
	},
	"arc": {
		"id": "arc", "name": "开垄横扫", "label": "横扫角度",
		"description": "每级横扫角度 +12°，更容易扫中两侧的敌人。",
		"scope": "weapon", "weapons": ["stick"], "max_rank": MAX_RANK,
		"effect_key": "arc_bonus_degrees", "base": 0.0, "per_rank": 12.0, "operation": "add", "unit": "degrees",
	},
	"reach": {
		"id": "reach", "name": "接长枝梢", "label": "有效长度",
		"description": "每级有效攻击长度 +10%，按树枝的基础长度相加。",
		"scope": "weapon", "weapons": ["stick"], "max_rank": MAX_RANK,
		"effect_key": "reach_multiplier", "base": 1.0, "per_rank": 0.10, "operation": "add", "unit": "percent",
	},
	"knockback": {
		"id": "knockback", "name": "震退劲道", "label": "击退力度",
		"description": "每级击退力度 +25%，为当前武器多留一点周旋空间。",
		"scope": "weapon", "weapons": ["stick", "corn"], "max_rank": MAX_RANK,
		"effect_key": "knockback_multiplier", "base": 1.0, "per_rank": 0.25, "operation": "add", "unit": "percent",
	},
	"recovery": {
		"id": "recovery", "name": "回手利落", "label": "收招时间",
		"description": "每级收招时间 ×0.92；只缩短有效命中结束后的动作，不改变有效命中窗口。",
		"scope": "weapon", "weapons": ["stick"], "max_rank": MAX_RANK,
		"effect_key": "recovery_multiplier", "base": 1.0, "per_rank": 0.92, "operation": "multiply", "unit": "percent",
	},
	"clear_heal": {
		"id": "clear_heal", "name": "收工回气", "label": "清场回复",
		"description": "每级清场回复 +3 点体力，本局所有武器共用。",
		"scope": "global", "weapons": ["stick", "corn"], "max_rank": MAX_RANK,
		"effect_key": "clear_heal", "base": 0.0, "per_rank": 3.0, "operation": "add", "unit": "health",
	},
}

static func allowed_ids(weapon_id: String, ranks: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if weapon_id not in WEAPON_IDS:
		return result
	for id in IDS:
		if _applies(id, weapon_id) and rank_for(id, ranks, weapon_id) < MAX_RANK:
			result.append(id)
	return result

static func get_definition(id: String) -> Dictionary:
	return DEFINITIONS.get(id, {}).duplicate(true)

static func rank_for(id: String, ranks: Dictionary, weapon_id: String) -> int:
	if not _applies(id, weapon_id):
		return 0
	var container: Variant = ranks.get("global_builds", {})
	if DEFINITIONS[id].scope == "weapon":
		var by_weapon: Variant = ranks.get("builds_by_weapon", {})
		if not by_weapon is Dictionary:
			return 0
		container = by_weapon.get(weapon_id, {})
	if not container is Dictionary:
		return 0
	var value: Variant = container.get(id, 0)
	if not _whole_number(value):
		return 0
	return clampi(int(value), 0, MAX_RANK)

static func is_valid_ranks(ranks: Dictionary) -> bool:
	var by_weapon: Variant = ranks.get("builds_by_weapon", {})
	var global_ranks: Variant = ranks.get("global_builds", {})
	if not by_weapon is Dictionary or not global_ranks is Dictionary:
		return false
	for weapon_id in by_weapon:
		if not by_weapon[weapon_id] is Dictionary:
			return false
		for id in by_weapon[weapon_id]:
			if DEFINITIONS.has(id) and not _valid_rank(by_weapon[weapon_id][id]):
				return false
	for id in global_ranks:
		if DEFINITIONS.has(id) and not _valid_rank(global_ranks[id]):
			return false
	return true

static func effect_value(id: String, rank_value: int) -> float:
	if not DEFINITIONS.has(id):
		return 0.0
	var definition: Dictionary = DEFINITIONS[id]
	var safe_rank := clampi(rank_value, 0, MAX_RANK)
	if definition.operation == "multiply":
		return float(definition.base) * pow(float(definition.per_rank), safe_rank)
	return float(definition.base) + float(definition.per_rank) * safe_rank

static func describe(id: String, ranks: Dictionary, weapon_id: String) -> Dictionary:
	if not _applies(id, weapon_id):
		return {}
	var definition := get_definition(id)
	var current_rank := rank_for(id, ranks, weapon_id)
	var next_rank := mini(MAX_RANK, current_rank + 1)
	var current_value := effect_value(id, current_rank)
	var next_value := effect_value(id, next_rank)
	var before := _format_value(current_value, str(definition.unit))
	var after := _format_value(next_value, str(definition.unit))
	return {
		"id": id, "name": definition.name, "description": definition.description,
		"current_rank": current_rank, "next_rank": next_rank, "max_rank": MAX_RANK,
		"current_value": current_value, "next_value": next_value,
		"effect_before": before, "effect_after": after,
		"change_text": "%s：%s → %s" % [definition.label, before, after],
		"weapon_id": weapon_id, "scope": definition.scope,
	}

static func _applies(id: String, weapon_id: String) -> bool:
	return DEFINITIONS.has(id) and weapon_id in DEFINITIONS[id].weapons

static func _whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(value) and value == floorf(value) and value >= -2147483648.0 and value <= 2147483647.0

static func _valid_rank(value: Variant) -> bool:
	return _whole_number(value) and value >= 0 and value <= MAX_RANK

static func _format_value(value: float, unit: String) -> String:
	if unit == "percent":
		var amount := value * 100.0
		if is_equal_approx(amount, roundf(amount)):
			return "%d%%" % roundi(amount)
		return "%.2f%%" % amount
	if unit == "degrees":
		return "+%d°" % roundi(value)
	return "%d 点体力" % roundi(value)
