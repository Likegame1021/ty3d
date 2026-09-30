extends RefCounted

var stage := 0
var chicken_discovered := false
var item_collected := false
var pickup_count := 0
var enemy_seen := false
var enemy_repelled := false
var health := 3
var outcome := "playing"
var elapsed := 0.0
var invulnerable := 0.0

func discover_chicken() -> bool:
	if outcome != "playing" or chicken_discovered:
		return false
	chicken_discovered = true
	stage = 1
	return true

func collect_item() -> bool:
	if outcome != "playing" or not chicken_discovered or item_collected:
		return false
	item_collected = true
	pickup_count = 1
	stage = 2
	return true

func notice_enemy() -> bool:
	if outcome != "playing" or enemy_seen:
		return false
	enemy_seen = true
	return true

func try_finish() -> bool:
	if outcome != "playing" or not item_collected:
		return false
	outcome = "won"
	stage = 3
	return true

func take_damage() -> bool:
	if outcome != "playing" or invulnerable > 0.0:
		return false
	health = maxi(0, health - 1)
	invulnerable = 1.25
	if health == 0:
		outcome = "lost"
		stage = 3
	return true

func tick(delta: float, paused: bool) -> void:
	if paused or outcome != "playing":
		return
	elapsed += delta
	invulnerable = maxf(0.0, invulnerable - delta)

func reset() -> void:
	stage = 0
	chicken_discovered = false
	item_collected = false
	pickup_count = 0
	enemy_seen = false
	enemy_repelled = false
	health = 3
	outcome = "playing"
	elapsed = 0.0
	invulnerable = 0.0
