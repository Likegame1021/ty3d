extends RefCounted
## Parameters live here; attack execution and readable warnings live in FieldEnemy.

const SPECIES := {
	"beetle": {"name":"硬壳甲虫","hp":48.0,"speed":43.0,"damage":9.0,"range":108.0,"windup":0.65,"strike":0.36,"recovery":0.90,"attack":"charge","burst_speed":185.0,"radius":9.0},
	"locust": {"name":"田埂蚂蚱","hp":34.0,"speed":58.0,"damage":8.0,"range":148.0,"windup":0.58,"strike":0.44,"recovery":0.85,"attack":"leap","burst_speed":265.0,"radius":8.0},
	"mouse": {"name":"偷粮田鼠","hp":38.0,"speed":73.0,"damage":7.0,"range":95.0,"windup":0.48,"strike":0.30,"recovery":0.76,"attack":"flank","burst_speed":230.0,"radius":8.0},
	"rooster": {"name":"护窝公鸡","hp":57.0,"speed":49.0,"damage":6.0,"range":54.0,"windup":0.50,"strike":0.15,"recovery":1.05,"attack":"peck","burst_speed":105.0,"radius":10.0},
	"snail": {"name":"厚壳蜗牛","hp":70.0,"speed":26.0,"damage":8.0,"range":212.0,"windup":0.78,"strike":0.22,"recovery":1.40,"attack":"spit","burst_speed":0.0,"radius":10.0},
	"corn_borer": {"name":"玉米螟","hp":44.0,"speed":40.0,"damage":7.0,"range":228.0,"windup":0.76,"strike":0.24,"recovery":1.15,"attack":"fan","burst_speed":0.0,"radius":9.0},
	"boss_borer": {"name":"巨型玉米螟","hp":620.0,"speed":49.0,"damage":16.0,"range":248.0,"windup":0.92,"strike":0.58,"recovery":1.12,"attack":"charge","burst_speed":245.0,"radius":20.0}
}

static func profile(id: String, is_elite := false) -> Dictionary:
	var result: Dictionary = SPECIES.get(id,SPECIES.beetle).duplicate(true)
	result.combo = 2 if id == "rooster" else 1
	result.sense = 360.0 if id == "boss_borer" else 330.0
	if is_elite and id != "boss_borer":
		result.hp *= 1.6
		result.speed *= 1.12
		result.damage *= 1.15
		result.recovery *= 0.86
		result.combo += 1
	return result
