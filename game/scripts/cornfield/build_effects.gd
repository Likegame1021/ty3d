extends RefCounted
## Always compile from stored ranks and base stats, never from a prior snapshot.
## recovery_multiplier applies only after active_end; the compiler owns no hit windows.
const Catalog = preload("res://scripts/cornfield/build_catalog.gd")

static func compile(ranks: Dictionary, weapon_id: String, legacy_damage_bonus: float = 0.0) -> Dictionary:
	var effects := {}
	for id in Catalog.IDS:
		var definition: Dictionary = Catalog.get_definition(id)
		effects[definition.effect_key] = Catalog.effect_value(id, Catalog.rank_for(id, ranks, weapon_id))
	if is_finite(legacy_damage_bonus):
		effects.damage_multiplier += maxf(0.0, legacy_damage_bonus)
	return effects
