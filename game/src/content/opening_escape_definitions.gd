extends RefCounted
## Declarative timing, resource and camera cues for the fresh opening escape.
## This capability does not establish support for the following mission scene.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const Layouts = preload("res://src/content/declaration_layouts.gd")
const VALUES := {"scope":"fresh_opening_escape","entry_phase":4,"entry_after_event_finished":10,"first_phase":5,"slowdown_after_event_finished":12,"initial_cruise_speed":2.0,"cruise_decay_per_update":0.9800000190734863,"pan_after_event_finished":13,"pan_x_per_ms_double":0.3,"pan_z_per_ms":-0.20000000298023224,"disturbance_after_event_started":14,"effect_after_event_finished":15,"effect_resource_id":15027,"entry_yaw":1.5707963705062866,"entry_eye_offset":[25000.0,-200.0,-1000.0],"shake_radius":20,"shake_rise_ms":4000.0,"hide_ship_at_ms":2001,"after_exit_wait_ms":4001,"after_exit_falloff_ms":3000.0,"jump_position":[0.0,0.0,0.0],"jump_forward":[0.0,0.0,-1.0],"jump_up":[0.0,1.0,0.0],"jump_model_rotation":[0.7853981852531433,0.7853981852531433,0.7853981852531433],"jump_eye":[5000.0,500.0,-10000.0],"arrival_effect_after_ms":2001,"arrival_shake_rise_ms":2000.0,"arrival_ship_restore_after_ms":2501,"arrival_shake_falloff_ms":2500.0,"drift_cut_after_event_finished":17,"drift_roll_divisor":3000.0,"drift_eye_offset":[-2000.0,-2000.0,-5000.0],"second_cut_after_ms":6001,"second_roll_divisor":4000.0,"second_eye_offset":[700.0,0.0,-1700.0],"last_cut_after_ms":12001,"last_roll_divisor":5000.0,"last_eye_offset":[-3000.0,3500.0,-6700.0],"last_pan_z_per_ms":-2.0,"fade_after_event_finished":22,"fade_duration_ms":5000,"fade_source_direction":1,"fade_source_color_argument":255,"phase6_effect_start_modes":[3,1],"jump_effect_modes":[0,3],"arrival_effect_mode":1,"entry_music_id":143,"drive_sound_ids":[157,158,161],"exit_sound_id":160,"jump_music_id":141,"arrival_sound_id":159,"arrival_engine_sound_id":156,"jump_sky_mesh_id":17809,"jump_sky_texture_id":10074,"jump_planet_texture_id":10042,"jump_planet_scale_multiplier":2.0}
const SPANS := {"x86_64":{"camera_backward_getter":[1119279,82],"heading_setter":[-846025,480],"effect_constructor":[387,43],"jump_sky":[-1899,110],"jump_planet":[725575,164],"entry_gate":[17889,21],"entry":[28585,306],"slowdown_and_pan":[17910,559],"departure":[18469,431],"exit_effect":[18900,420],"jump_wait":[19320,192],"jump":[19512,305],"arrival_effect":[19817,227],"arrival":[20044,369],"drift":[20413,235],"second_cut":[20648,200],"last_cut":[20848,259],"arrival_gate":[21107,39],"fade":[108788,50],"cruise_getter":[482969,14],"cruise_setter":[482879,14],"camera_shake_setter":[787467,20],"model_rotation_setter":[477699,126],"cruise_decay_constant":[1460543,4],"pan_x_constant":[1460815,8],"pan_z_constant":[1423555,4],"entry_yaw_constant":[1452903,4],"entry_x_constant":[1453039,4],"entry_y_constant":[1460531,4],"entry_z_constant":[1453315,4],"shake_rise_constant":[1460455,4],"jump_falloff_constant":[1453195,4],"arrival_rise_constant":[1451843,4],"arrival_falloff_constant":[1453051,4],"jump_angle_constant":[1460539,4],"jump_eye_x_constant":[1423963,4],"jump_eye_y_constant":[1460407,4],"jump_eye_z_constant":[1453243,4],"unit_constant":[1422583,4],"initial_speed_constant":[1435055,4],"drift_roll_constant":[1423983,4]},"armv7":{"camera_backward_getter":[1841186,48],"heading_setter":[-1192206,256],"effect_constructor":[368,36],"jump_sky":[-1790,88],"jump_planet":[669190,94],"entry_gate":[39860,34],"entry":[39894,376],"slowdown_and_pan":[54426,548],"slowdown_literals":[55454,20],"last_roll_literal":[69854,4],"dispatch":[55474,42],"departure":[55516,448],"exit_effect":[66878,458],"jump_wait":[67336,236],"jump":[67572,342],"arrival_effect":[67914,264],"arrival":[68178,388],"drift":[68566,254],"second_cut":[68820,222],"last_cut":[69042,278],"arrival_gate":[89782,50],"fade":[69320,68],"cruise_getter":[426374,6],"cruise_setter":[426354,6],"camera_shake_setter":[726842,10],"model_rotation_setter":[422538,110]}}

const MAC_ALTERNATE := {"camera_backward_getter":[1112071,82],"heading_setter":[-851921,480],"effect_constructor":[387,43],"jump_sky":[-1899,110],"jump_planet":[726207,164],"entry_gate":[17889,21],"entry":[28585,306],"slowdown_and_pan":[17910,559],"departure":[18469,431],"exit_effect":[18900,420],"jump_wait":[19320,192],"jump":[19512,305],"arrival_effect":[19817,227],"arrival":[20044,369],"drift":[20413,235],"second_cut":[20648,200],"last_cut":[20848,259],"arrival_gate":[21107,39],"fade":[108802,50],"cruise_getter":[483517,14],"cruise_setter":[483427,14],"camera_shake_setter":[788099,20],"model_rotation_setter":[478247,126],"cruise_decay_constant":[1435607,4],"pan_x_constant":[1435879,8],"pan_z_constant":[1398539,4],"entry_yaw_constant":[1427967,4],"entry_x_constant":[1428103,4],"entry_y_constant":[1435595,4],"entry_z_constant":[1428379,4],"shake_rise_constant":[1435519,4],"jump_falloff_constant":[1428259,4],"arrival_rise_constant":[1426907,4],"arrival_falloff_constant":[1428115,4],"jump_angle_constant":[1435603,4],"jump_eye_x_constant":[1398947,4],"jump_eye_y_constant":[1435471,4],"jump_eye_z_constant":[1428307,4],"unit_constant":[1397567,4],"initial_speed_constant":[1410055,4],"drift_roll_constant":[1398967,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not equal_value(data.get(key),VALUES[key]):return false
	return true

static func equal_value(value: Variant, expected: Variant) -> bool:
	if expected is int:return Numbers.integer(value,expected,expected)
	if expected is float:return (value is int or value is float) and value==expected
	if expected is Array:
		if not value is Array or value.size()!=expected.size():return false
		for i in expected.size():
			if not equal_value(value[i],expected[i]):return false
		return true
	if expected is Dictionary:
		if not value is Dictionary or value.size()!=expected.size():return false
		for key in expected:
			if not value.has(key) or not equal_value(value[key],expected[key]):return false
		return true
	return typeof(value)==typeof(expected) and value==expected

static func validate(data: Variant, executable_bytes: int, architecture: String, staging: Dictionary) -> String:
	if not data is Dictionary:return "Invalid opening escape capability"
	if data.is_empty():return ""
	if not parameters(data) or not SPANS.has(architecture):return "Unsupported opening escape declarations"
	var initial: Variant=staging.get("provenance",{}).get("initial")
	if not Fonts.extent(initial,"offset","bytes",[366 if architecture=="x86_64" else 320],executable_bytes):return "Opening escape lacks its staging anchor"
	if data.provenance.size()!=SPANS[architecture].size():return "Invalid opening escape provenance"
	var layouts: Array=[SPANS[architecture]]
	if architecture=="x86_64":layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,int(initial.offset),executable_bytes,layouts) else "Disconnected opening escape declaration"
