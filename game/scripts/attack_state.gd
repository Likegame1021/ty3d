extends RefCounted

var remaining := 0.0
var elapsed := 0.0
var hit_targets := {}
var duration := 0.48
var active_start := 0.10
var active_end := 0.30

func configure(seconds: float, hit_start: float, hit_end: float) -> void:
	duration = maxf(0.1, seconds)
	active_start = clampf(hit_start, 0.0, duration)
	active_end = clampf(hit_end, active_start, duration)

func begin(paused: bool) -> bool:
	if paused or remaining > 0.0:
		return false
	remaining = duration
	elapsed = 0.0
	hit_targets.clear()
	return true

func tick(delta: float, paused: bool) -> void:
	if paused or remaining <= 0.0:
		return
	remaining = maxf(0.0, remaining - delta)
	elapsed += delta

func claim_hit(target_id: int, paused: bool) -> bool:
	if paused or remaining <= 0.0 or elapsed < active_start or elapsed > active_end:
		return false
	if hit_targets.has(target_id):
		return false
	hit_targets[target_id] = true
	return true

func reset() -> void:
	remaining = 0.0
	elapsed = 0.0
	hit_targets.clear()
