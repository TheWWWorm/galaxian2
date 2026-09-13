extends RefCounted
## Source declarations for fresh opening NPC construction only.
const Fonts = preload("res://src/content/font_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const EXPECTED = {
  "spawn_origin": [
    -20000,
    -20000,
    -20000
  ],
  "spawn_bound": 40000,
  "cargo_count_bound": 3,
  "cargo_attempts": 100,
  "chance_bound": 100,
  "category_weights": [
    10,
    40,
    2,
    10,
    100
  ],
  "excluded_items": [
    164,
    175,
    217,
    218
  ],
  "category_index": 3,
  "rank_index": 7,
  "chance_index": 13,
  "price_low_index": 15,
  "price_high_index": 17,
  "maximum_rank": 7,
  "commodity_category": 4,
  "quantity_minimum": 1,
  "quantity_bound": 3,
  "commodity_quantity_bound": 9,
  "fallback_item_minimum": 154,
  "fallback_item_bound": 10,
  "special_ship_ids": [
    37,
    38,
    40
  ],
  "special_equipment_type": 18,
  "special_item": 122,
  "special_chance_maximum": 9,
  "fragment_count_minimum": 3,
  "fragment_count_bound": 7,
  "fragment_resource": 14292,
  "rotation_bound": 360,
  "rotation_divisor": 180.0,
  "rotation_multiplier": 3.1415927410125732,
  "scale_minimum": 50,
  "scale_bound": 50,
  "scale_divisor": 100.0,
  "opening_discards_cargo": true
}

static func matches(value: Variant, expected: Variant) -> bool:
	if expected is bool: return value is bool and value==expected
	if expected is int: return Numbers.integer(value,expected,expected)
	if expected is float: return (value is float or value is int) and is_finite(value) and value==expected
	if expected is Array:
		if not value is Array or value.size()!=expected.size(): return false
		for i in expected.size():
			if not matches(value[i],expected[i]): return false
		return true
	return false

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=EXPECTED.size()+1 or not data.get("provenance") is Dictionary: return false
	for key in EXPECTED:
		if not matches(data.get(key),EXPECTED[key]): return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening NPC construction declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Unsupported opening NPC construction parameters"
	var sizes: Dictionary=SIZES.get(architecture,{})
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid NPC construction provenance"
	var spans := []
	for key in sizes:
		var row: Variant=data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid NPC construction extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping NPC construction extents"
		spans.append(span)
	return ""

const SIZES = {
  "armv7": {
    "effect_wrapper":14, "effect_zero":22,
    "spawn": 150,
    "tail": 114,
    "cargo": 570,
    "category": 4,
    "rank": 4,
    "price": 4,
    "chance": 4,
    "requirements": 4,
    "item_layout": 84,
    "item_arrays": 22,
    "fragments": 398,
    "fragment_gate": 52,
    "predicate": 40,
    "selection": 132,
    "equipment_table": 30,
    "special_equipment_case": 4,
    "rotation_divisor": 4,
    "rotation_multiplier": 4,
    "scale_divisor": 4,
    "category_weights": 20,
    "cargo_zero": 4,
    "cargo_discard": 4
  },
  "x86_64": {
    "effect_wrapper":10, "effect_zero":8,
    "spawn": 111,
    "tail": 121,
    "cargo": 723,
    "category": 10,
    "rank": 10,
    "price": 10,
    "chance": 10,
    "requirements": 10,
    "item_layout": 140,
    "item_arrays": 22,
    "fragments": 364,
    "fragment_gate": 31,
    "predicate": 42,
    "selection": 119,
    "equipment_table": 120,
    "special_equipment_case": 5,
    "rotation_divisor": 4,
    "rotation_multiplier": 4,
    "scale_divisor": 4,
    "category_weights": 20,
    "cargo_discard": 8
  }
}
