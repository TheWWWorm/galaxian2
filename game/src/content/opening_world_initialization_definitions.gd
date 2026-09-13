extends RefCounted
## Fresh opening initialization declarations; no general mission construction.
const Values = preload("res://src/content/npc_construction_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const EXPECTED = {
  "world_type": 3,
  "campaign_cursor": 0,
  "initial_companions_empty": true,
  "absent_equipment_types": [
    33,
    39
  ],
  "absent_hull_ids": [
    45,
    51
  ],
  "weapon_item_sequence": [
    0,
    19
  ],
  "weapon_effect_sequence": [
    14600,
    14605
  ],
  "weapon_effect_capacity": 4,
  "weapon_effect_random_bound": 2,
  "zero_means_flipped": true
}
const SIZES = {
  "armv7": {
    "weapon_main": 154,
    "selection": 132,
    "base_call": 30,
    "before": 42,
    "after": 132,
    "equipment33": 62,
    "station_gate": 30,
    "cursor_gate": 18,
    "equipment39": 62,
    "companion_gate": 22,
    "companion_getter": 4,
    "companion_reset": 4,
    "effect_setter": 248,
    "hull_gate": 6,
    "hull_gate_tail": 4,
    "base_flags": 98,
    "weapon_secondary": 42,
    "secondary_getter": 6,
    "weapon_wrapper_call": 26,
    "weapon_wrapper": 24,
    "weapon_effect_gate": 116,
    "weapon_overrides": 34,
    "weapon_overrides_tail": 90,
    "weapon_mission": 130,
    "weapon_hull": 66,
    "weapon_kind": 12,
    "weapon_extra": 12,
    "weapon_extra_branch": 4,
    "weapon_extra_hull": 10,
    "effect_model_0": 4,
    "effect_model_19": 4
  },
  "x86_64": {
    "weapon_main": 180,
    "selection": 119,
    "base_call": 14,
    "before": 49,
    "after": 119,
    "equipment33": 30,
    "station_gate": 55,
    "cursor_gate": 24,
    "equipment39": 37,
    "companion_gate": 24,
    "companion_getter": 10,
    "companion_reset": 8,
    "effect_setter": 238,
    "hull_gate": 25,
    "base_flags": 20,
    "base_secondary": 7,
    "weapon_secondary": 56,
    "secondary_getter": 13,
    "weapon_wrapper_call": 32,
    "weapon_wrapper": 10,
    "weapon_effect_gate": 17,
    "weapon_overrides": 41,
    "weapon_overrides_tail": 345,
    "weapon_extra": 49,
    "weapon_extra_hull": 30,
    "effect_model_0": 4,
    "effect_model_19": 4
  }
}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=EXPECTED.size()+1 or not data.get("provenance") is Dictionary: return false
	for key in EXPECTED:
		if not Values.matches(data.get(key),EXPECTED[key]): return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing opening world initialization declaration"
	if data.is_empty(): return ""
	if not parameters(data): return "Unsupported opening world initialization parameters"
	var sizes: Dictionary=SIZES.get(architecture,{})
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid world initialization provenance"
	var spans := []
	for key in sizes:
		var row: Variant=data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid world initialization extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping world initialization extents"
		spans.append(span)
	return ""
