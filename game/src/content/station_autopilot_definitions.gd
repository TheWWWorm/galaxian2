extends RefCounted
## Ordinary guidance toward the current first-mining station; no arrival transition.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Flight=preload("res://src/content/first_flight_definitions.gd")
const VALUES := {"scope":"first_mining_station_autopilot","station_id":78,"system_id":15,"max_frame_ms":150,"near_distance_limit":20000,"response_add":2.700000047683716,"maximum_gain":4.0,"turn_fraction":0.000244140625,"bank_samples":5,"bank_sign_angle":1.5707963705062866,"bank_limit_numerator":750.0,"bank_limit_divisor":63.0,"bank_limit_scale":1.2000000476837158,"bank_gain":15.13935661315918,"bank_slew_scale":0.012345679104328156,"bank_angle_scale":-0.000244140625,"angle_tau":6.2831854820251465,"pitch_angle_scale":6.103515625e-05,"target_position":[0,0,0],"start_throttle":1.0,"start_notice":10,"cancel_notice":6,"camera_target":"logical_player","visual_rotation_order":"xyz","cancel_resets_history_only":true,"warmup_excludes_current_sample":true,"initial_bank_requires_manual_sample":true,"docking_transition_supported":false,"avoidance_supported":false}
const SPANS := {"station_menu":[358266,88],"target_setter":[562440,134],"station_position":[649750,22],"ordinary_branch":[578473,459],"ordinary_movement_else":[578932,90],"guidance":[568150,1486],"bank_constructor":[553143,107],"manual_retained_bank":[565055,32],"bank_visual":[579171,493],"effective_handling":[729296,106],"response_scale":[552215,60],"matrix_xyz":[1242570,478],"matrix_right_column":[1241114,81],"model_matrix_set":[-724186,23],"camera_target":[232198,24],"camera_attach":[905084,10],"camera_target_read":[905478,79],"bank_constructor_floats":[1587782,8],"handling_scale":[1545694,4],"gain_and_bank_floats":[1587862,12],"maximum_gain":[1575050,4],"angle_tau":[1575058,4],"pitch_floats":[1587970,24],"bank_sign_angle":[1574930,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary) -> String:
	if not data is Dictionary:return "Missing station autopilot declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Flight.parameters(flight):return "Unsupported station autopilot declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Station autopilot lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid station autopilot provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid station autopilot extent: "+key
	return ""
