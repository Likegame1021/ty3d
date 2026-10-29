extends RefCounted
## Pure descriptions of actual room services. This directory never grants rewards.
## Toolheap growth is available separately and is not an ANVIL-exclusive benefit.

static func describe(node_id: String) -> Dictionary:
	match node_id:
		"ANVIL":
			return _entry("田头工具堆","整理好的工具旁，可领一次 8 元补给。","supply",8,0,0,0,0,0,["ANVIL","skip"],false)
		"LEVEL":
			return _entry("老树歇脚","恢复 30 体力，记录 2 发现点。","rest",0,30,2,0,0,0,["LEVEL","skip"],false)
		"REWARD":
			return _entry("田间拾遗","可领一次 18 元和 3 件田间拾物。","loot",18,0,0,3,0,0,["REWARD","skip"],false)
		"ELITE":
			return _entry("虫王盘踞","必经精英；支路可领 18 元和 3 件田间拾物。","loot",18,0,0,3,0,0,["ELITE","skip"],false)
		"EVENT":
			return _entry("树荫下的西瓜摊","花 8 元吃西瓜，恢复 40 体力；也可摆手离开。","event",0,40,0,0,8,0,["watermelon","skip"],false)
		"SHOP":
			return _entry("桂花小卖点","汽水 10 元恢复 35 体力；拾物每件卖 3 元，可直接离开。","shop",0,35,0,0,10,3,["buy_heal","sell_loot","skip"],true)
		"BOSS":
			# Boss victory is a terminal run result, not a room-service payout.
			return _entry("玉米螟巢穴","最后节点，击退玉米螟王。","boss",0,0,0,0,0,0,[],false)
	return {}

static func for_room(definition: Dictionary) -> Dictionary:
	var node_id: String = str(definition.get("node_type",""))
	if describe(node_id).is_empty():
		return {}
	var kind: String = str(definition.get("kind",""))
	var encounter: String = str(definition.get("encounter",""))
	if encounter == "boss":
		return {}
	# The room's authored event role outranks its macro node, including SHOP.
	if kind == "event" or encounter == "event":
		return describe("EVENT")
	if kind == "shop" or encounter == "shop":
		return describe("SHOP")
	if node_id == "SHOP" and kind != "objective":
		return {}
	if kind not in ["objective","reward","rest","service"] and encounter != "service":
		return {}
	if node_id == "BOSS":
		return _entry("虫巢前哨","可领一次 18 元和 3 件田间拾物。","loot",18,0,0,3,0,0,["BOSS","skip"],false)
	return describe(node_id)

static func _entry(title: String,short_description: String,service_kind: String,coins: int,heal: int,meta: int,loot: int,cost: int,sell_price: int,allowed_actions: Array,repeatable: bool) -> Dictionary:
	return {"title":title,"short_description":short_description,"service_kind":service_kind,
		"coins":coins,"heal":heal,"meta":meta,"loot":loot,"cost":cost,"sell_price":sell_price,
		"allowed_actions":allowed_actions,"repeatable":repeatable}
