extends SceneTree

var failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

func _initialize() -> void:
	var progress = load("res://scripts/entry_progress.gd").new()
	check(not progress.try_finish(), "exit refuses missing marble box")
	check(not progress.collect_item(), "box cannot bypass chicken discovery step")
	check(progress.discover_chicken(), "observing harmless chicken unlocks search")
	check(progress.stage == 1, "chicken discovery advances objective")
	check(not progress.discover_chicken(), "chicken reveals only once")
	check(progress.collect_item(), "box collected after clue")
	check(not progress.collect_item() and progress.pickup_count == 1, "item cannot be collected twice")
	check(progress.notice_enemy(), "danger encounter recorded")
	progress.tick(12.0, false)
	check(progress.elapsed == 12.0, "active gameplay time recorded")
	progress.tick(5.0, true)
	check(progress.elapsed == 12.0, "paused time excluded")
	check(progress.try_finish(), "collected box reaches completion")
	check(progress.outcome == "won" and progress.stage == 3, "completion is terminal")
	check(not progress.take_damage() and progress.health == 3, "victory freezes danger")
	progress.reset()
	check(progress.stage == 0 and progress.health == 3 and progress.elapsed == 0.0 and not progress.item_collected and not progress.enemy_seen, "retry fully resets progress")
	check(progress.take_damage() and progress.health == 2, "first readable attack removes one heart")
	check(not progress.take_damage() and progress.health == 2, "invulnerability prevents repeated contact damage")
	progress.tick(1.3, false)
	check(progress.take_damage() and progress.health == 1, "next attack after invulnerability removes one heart")
	progress.tick(1.3, false)
	check(progress.take_damage() and progress.health == 0 and progress.outcome == "lost", "three separated hits cause failure")
	check(not progress.try_finish(), "failed run cannot complete")
	progress.reset()
	check(progress.outcome == "playing" and progress.health == 3 and progress.pickup_count == 0, "failed run retries cleanly")
	print("Entry progression: %d failures" % failures)
	quit(1 if failures else 0)
