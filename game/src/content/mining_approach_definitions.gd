extends RefCounted
## Source first-mining approach; drilling and missions have separate owners.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Targeting=preload("res://src/content/mining_targeting_definitions.gd")
const VALUES := {"scope":"first_mining_approach","campaign_cursor":2,"max_frame_ms":150,"stand_off_scale":2500.0,"close_margin":2000,"near_distance_limit":20000,"response_add":2.700000047683716,"maximum_gain":4.0,"turn_fraction":0.000244140625,"alignment_angle":0.20000000298023224,"tilt_limit":-1024.0,"tilt_rate":-0.3499999940395355,"angle_fraction":1.52587890625e-05,"angle_tau":6.2831854820251465,"drill_wait_shift":1,"visual_forward_axis":2,"alignment_reference_axis":1,"model_is_child":true,"close_freezes_camera":true,"cancel_restores_camera":true,"cancel_retains_alignment_state":true,"creation_frame_advances_drill":false,"guidance_bank_affects_mining_pose":false,"ordinary_movement_during_approach":false,"engine_stop_event":2,"drill_start_event":1}
const SPANS := {"start_and_cancel":[586674,293],"distance_and_guidance":[587041,432],"dock_and_close":[587473,194],"alignment":[587667,647],"wait_and_drill_creation":[588314,211],"player_dispatch":[577022,84],"ordinary_movement_gate":[578932,90],"ordinary_banking_gate":[579171,40],"guidance_heading":[568223,340],"guidance_move":[569043,89],"guidance_stats":[569543,122],"model_parent":[554618,102],"camera_update_gate":[905887,23],"camera_enable_setter":[905074,10],"asteroid_scale":[546095,16],"asteroid_spin_initial":[546627,9],"asteroid_base_flag":[546829,6],"spin_setter":[547406,10],"initial_alignment":[550792,7],"initial_capture":[551475,8],"local_forward":[-724330,26],"local_up":[-724304,26],"matrix_forward":[1241306,82],"matrix_up":[1241210,82],"local_pitch_matrix":[1242570,480],"matrix_product":[1237994,832]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, targeting: Dictionary) -> String:
	if not data is Dictionary:return "Missing mining approach declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Targeting.parameters(targeting):return "Unsupported mining approach declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Mining approach lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid mining approach provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid mining approach extent: "+key
	return ""
