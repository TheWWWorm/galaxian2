extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Verified Mac scene time and player target for the Opening rescue.
const Values=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"opening_rescue_session","campaign_cursor":1,"initial_elapsed_ms":0,"clock_owner":"scene_controller","clock_before_controller":true,"player_target_excluded":false,"actor_target_ids":["player"],"target_index":0,"quest_kind":11,"actor_count":1,"player_update_enabled":false}
const SPANS := {"clock_initial":[121689,8],"clock_advance":[365042,21],"radio_clock":[390701,27],"radio_condition_input":[682207,26],"elapsed_condition":[685337,15],"elapsed_condition_slot":[686326,4],"target_initial":[534407,4],"target_list_initial":[535007,8],"population_cursor":[-33,33],"opening_only_exclusion":[3106,9],"target_population":[59632,954],"target_append_gate":[536398,31],"target_append_empty":[536706,25],"target_fallback":[616370,26],"target_getter":[536982,22]}

const MAC_ALTERNATE := {"clock_initial":[121689,8],"clock_advance":[364765,21],"radio_clock":[391217,27],"radio_condition_input":[682755,26],"elapsed_condition":[685885,15],"elapsed_condition_slot":[686874,4],"target_initial":[534943,4],"target_list_initial":[535543,8],"population_cursor":[-33,33],"opening_only_exclusion":[3106,9],"target_population":[59632,954],"target_append_gate":[536934,31],"target_append_empty":[537242,25],"target_fallback":[616918,26],"target_getter":[537518,22]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Values.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, bytes: int, arch: String, arrival: Dictionary, motion: Dictionary, world: Dictionary, handoff: Dictionary) -> String:
	if not data is Dictionary:return "Missing rescue session capability"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported rescue session declarations"
	if motion.is_empty() or world.is_empty() or handoff.is_empty() or arrival.get("player_update_enabled")!=false:return "Rescue session lacks its world, motion or handoff"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],bytes):return "Rescue session lacks its scene anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid rescue session provenance"
	var layouts: Array=[SPANS,MAC_ALTERNATE]
	return "" if Layouts.matches(data.provenance,int(origin.offset),bytes,layouts) else "Disconnected rescue session declaration"
