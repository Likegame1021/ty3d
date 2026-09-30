extends RefCounted

const max_health := 5
const max_boss_hp := 12
var health := max_health
var boss_hp := max_boss_hp
var invulnerable := 0.0
var elapsed := 0.0
var outcome := "playing"
var chicken_seen := false
var tin_taken := false
var mouth_cleared := false
var canal_open := false
var dense_entered := false
var stones_thrown := 0
var fence_vaulted := false
var board_taken := false
var cart_moved := false
var launcher_taken := false
var boss_active := false
var corn_spilled := false
var corn_gun := false
var boss_defeated := false

func see_chicken() -> bool:
	if outcome != "playing" or chicken_seen:
		return false
	chicken_seen = true
	return true

func take_tin() -> bool:
	if outcome != "playing" or not chicken_seen or tin_taken:
		return false
	tin_taken = true
	return true

func clear_mouth() -> bool:
	if outcome != "playing" or not tin_taken or mouth_cleared:
		return false
	mouth_cleared = true
	return true

func open_canal() -> bool:
	if outcome != "playing" or not mouth_cleared or canal_open:
		return false
	canal_open = true
	return true

func enter_dense() -> bool:
	if outcome != "playing" or not canal_open or dense_entered:
		return false
	dense_entered = true
	return true

func throw_stone() -> bool:
	if outcome != "playing" or not dense_entered:
		return false
	stones_thrown += 1
	return true

func vault_fence() -> bool:
	if outcome != "playing" or not dense_entered:
		return false
	fence_vaulted = true
	return true

func take_board() -> bool:
	if outcome != "playing" or not dense_entered or board_taken:
		return false
	board_taken = true
	return true

func move_cart() -> bool:
	if outcome != "playing" or not board_taken or cart_moved:
		return false
	cart_moved = true
	return true

func take_launcher() -> bool:
	if outcome != "playing" or not cart_moved or launcher_taken:
		return false
	launcher_taken = true
	return true

func enter_boss() -> bool:
	if outcome != "playing" or not launcher_taken or boss_active:
		return false
	boss_active = true
	return true

func hurt_boss(amount: int) -> bool:
	if outcome != "playing" or not boss_active or boss_defeated or amount <= 0:
		return false
	boss_hp = maxi(0 if corn_gun else 1, boss_hp - amount)
	if boss_hp <= max_boss_hp / 2:
		corn_spilled = true
	if boss_hp == 0:
		boss_defeated = true
	return true

func make_corn_gun() -> bool:
	if outcome != "playing" or not corn_spilled or corn_gun:
		return false
	corn_gun = true
	return true

func win() -> bool:
	if outcome != "playing" or not boss_defeated or not corn_gun or not tin_taken:
		return false
	outcome = "won"
	return true

func take_damage() -> bool:
	if outcome != "playing" or invulnerable > 0.0:
		return false
	health = maxi(0, health - 1)
	invulnerable = 1.1
	if health == 0:
		outcome = "lost"
	return true

func tick(delta: float) -> void:
	if outcome != "playing":
		return
	elapsed += delta
	invulnerable = maxf(0.0, invulnerable - delta)

func environment_flags() -> Dictionary:
	return {"mouth_cleared": mouth_cleared, "canal_open": canal_open, "cart_moved": cart_moved, "launcher_taken": launcher_taken, "boss_active": boss_active, "corn_spilled": corn_spilled, "boss_defeated": boss_defeated}

func reset() -> void:
	health = max_health
	boss_hp = max_boss_hp
	invulnerable = 0.0
	elapsed = 0.0
	outcome = "playing"
	chicken_seen = false
	tin_taken = false
	mouth_cleared = false
	canal_open = false
	dense_entered = false
	stones_thrown = 0
	fence_vaulted = false
	board_taken = false
	cart_moved = false
	launcher_taken = false
	boss_active = false
	corn_spilled = false
	corn_gun = false
	boss_defeated = false
