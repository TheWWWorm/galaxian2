extends RefCounted
## Original ordinary hangar pricing, transfers and departure capacity boundary.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"ordinary_station_shopping","catalogue":{"origin_property":4,"maximum_origin_property":5,"minimum_price_property":7,"maximum_price_property":8,"system_coordinate_fields":[3,4]},"pricing":{"distance_percent_scale":100.0,"ratio_maximum":1.0,"variation_fraction":0.019999999552965164,"percent_fraction":0.009999999776482582,"special_multiplier":1.0499999523162842,"minimum_variation":1,"nonpositive_price_unchanged":true,"list_order":["cargo","installed","stock"],"special_mission_kind":25},"transfer":{"unit_quantity":1,"buy_capacity_guard":false,"free_mode_station_id":108,"free_mode_story_value":3,"maximum_credit_delta":1000000000,"minimum_credits":0,"overfilled_departure_text_id":193,"protected_item_text_id":312,"insufficient_credits_text_id":192,"repeat_acceleration_ms":4000,"repeat_quantity":1,"accelerated_quantity":5}}
const SPANS = {"shopping_hangar_entry":[-172628,157],"shopping_prices":[877404,892],"shopping_item_constructor":[-85882,172],"shopping_system_x":[734968,10],"shopping_system_y":[734978,10],"shopping_distance":[-658544,46],"shopping_root_input":[-192316,10],"shopping_root":[1248266,48],"shopping_station_match":[853288,22],"shopping_cargo_list":[730052,10],"shopping_installed_list":[730042,10],"shopping_unit_transfer":[-84322,104],"shopping_wallet":[872054,48],"shopping_wallet_commit":[-163098,33],"shopping_funds_message":[-163710,97],"shopping_protected_transfer":[-164060,118],"shopping_combine":[-82728,782],"shopping_split":[-83178,244],"shopping_list_commit":[-166486,78],"shopping_cargo_setter":[730926,112],"shopping_stock_setter":[851930,226],"shopping_repeat_quantity":[-167068,47],"shopping_overfilled_departure":[437002,87],"shopping_reseed":[1120906,64],"shopping_distance_percent_scale":[1556926,4],"shopping_ratio_maximum":[1544610,4],"shopping_variation_fraction":[1582590,4],"shopping_percent_fraction":[1556914,4],"shopping_special_multiplier":[1573882,4]}

# Native composition.
const Worlds=preload("res://src/content/ordinary_world_definitions.gd")

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("ordinary_shopping")) and Worlds.available(bindings)

static func location(bindings: RefCounted,cat: RefCounted,station_id: Variant) -> Dictionary:
	return Worlds.catalogue_location(bindings,cat,station_id) if available(bindings) else {}

static func valid_stock(rows: Variant,item_count: int) -> bool:
	if not rows is Array or rows.size()>4096:return false
	for row in rows:
		if not row is Dictionary or row.size()!=3:return false
		for key in ["item_id","quantity","unit_price"]:
			if not row.get(key) is int:return false
		if row.item_id<0 or row.item_id>=item_count or row.quantity<1 or row.quantity>2147483647 or row.unit_price<0 or row.unit_price>2147483647:return false
	return true
