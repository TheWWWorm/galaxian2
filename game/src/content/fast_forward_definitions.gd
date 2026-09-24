extends RefCounted
## Held acceleration of existing navigation; one simulation pass, separate camera passes.
const Layouts = preload("res://src/content/declaration_layouts.gd")
const Equal = preload("res://src/content/opening_escape_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

const VALUES := {
	"scope": "mac_flight_fast_forward",
	"input": {
		"delivery": "hold_until_release",
		"press_requires_new_down_edge": true,
		"repeat_down_ignored": true,
		"release_reset_scope": "any_flight_control",
		"automatic_reset_rearms_held_key": false
	},
	"timing": {
		"normal_multiplier": 1.0,
		"fast_multiplier": 5.0,
		"real_frame_min_ms": 0,
		"real_frame_max_ms": 150,
		"simulation_frame_max_ms": 750,
		"simulation_passes": 1,
		"normal_camera_passes": 1,
		"fast_camera_passes": 5,
		"simulation_step": "f32_multiply_then_truncate",
		"fast_camera_step": "f32_divide_scaled_step_then_truncate",
		"wall_time_unscaled": true,
		"campaign_time_unscaled": true,
		"cancel_before_scaling": true,
		"pause_skips_active_updates": true
	},
	"activation": {
		"navigation_any": [
			"existing_autopilot",
			"mining_approach",
			"later_approach"
		],
		"excluded_approach_mode": 1,
		"refuse_battle": true,
		"refuse_near_target": true,
		"radio_disables_hud": true,
		"direct_press_checks_radio": false,
		"training_waypoint_grants_eligibility": false,
		"selects_target": false,
		"assigns_waypoint": false,
		"sets_throttle": false
	},
	"cancellation": {
		"checks": [
			"radar_battle",
			"player_near_target",
			"active_radio"
		],
		"near_target_sample": "previous_player_update",
		"reevaluates_navigation": false,
		"clears_navigation": false
	},
	"navigation": {
		"near_distance_limit": 20000,
		"near_distance_measure": "truncated_length_less_than_limit",
		"autopilot_gain_add": 2.700000047683716,
		"autopilot_gain_max": 4.0
	},
	"camera": {
		"input_policy": "relative_mouse_capture",
		"captured_refresh": "current_handling",
		"uncaptured_refresh": "fixed_normal_rates",
		"initial_cached_handling": 100.0,
		"fixed_normal_look_rate": 0.004999999888241291,
		"fixed_normal_eye_rate": 0.006000000052154064,
		"handling_scale": 0.009999999776482582,
		"look_complement": 1.0,
		"look_scale": 0.014999998733401299,
		"look_add": 0.003000000026077032,
		"eye_scale": 0.010999999940395355,
		"eye_add": 0.0010000000474974513,
		"rate_precision": "f32_each_operation",
		"fast_transition_recalculates_rates": true,
		"rate_update_rebuilds_coefficients": true,
		"fast_suppresses_normal_refresh": true,
		"normal_refresh_requires_dirty": true,
		"handling_refresh_updates_cache": true,
		"fixed_refresh_preserves_cache": true,
		"release_and_cancel_mark_dirty": true,
		"reset_refresh_phase": "next_player_update",
		"changes_fov": false
	},
	"supported_scope": {
		"existing_autopilot": true,
		"mining_approach": true,
		"later_approach": false,
		"slow_motion_combination": false
	}
}

const SPANS := {
	"arrival_actor": [
		0,
		315
	],
	"press_mask_source": [
		341691,
		27
	],
	"press_mask_branch": [
		341874,
		29
	],
	"press_fast_forward": [
		345576,
		103
	],
	"release_reset": [
		348340,
		39
	],
	"default_multiplier": [
		338356,
		10
	],
	"clock_clamp_and_unscaled_totals": [
		363155,
		83
	],
	"pause_gate": [
		364625,
		11
	],
	"slow_motion_gate": [
		364636,
		15
	],
	"frame_cancel_and_scale": [
		364913,
		129
	],
	"player_world_schedule": [
		366252,
		143
	],
	"camera_schedule": [
		378346,
		108
	],
	"autopilot_active": [
		562682,
		14
	],
	"mining_approach_active": [
		600806,
		28
	],
	"later_approach_active": [
		595386,
		28
	],
	"near_target_active": [
		600732,
		14
	],
	"radio_active": [
		683776,
		14
	],
	"autopilot_setter": [
		562440,
		134
	],
	"autopilot_target_steering_near": [
		578473,
		459
	],
	"near_target_reset": [
		576110,
		16
	],
	"camera_fast_flag": [
		910050,
		408
	],
	"keyboard_down": [
		956721,
		239
	],
	"keyboard_up": [
		957454,
		152
	],
	"pointer_down_dispatch": [
		1359674,
		125
	],
	"pointer_up_dispatch": [
		1360746,
		135
	],
	"hud_hit_rect": [
		-89322,
		54
	],
	"hud_eligibility": [
		-98504,
		114
	],
	"keyboard_hud_position": [
		-92596,
		269
	],
	"battle_counter_loop": [
		668117,
		340
	],
	"battle_flag_set": [
		676926,
		34
	],
	"battle_flag_clear": [
		677297,
		14
	],
	"battle_counter_reset": [
		677880,
		17
	],
	"active_actor_getter": [
		540924,
		14
	],
	"destroyed_getter": [
		-77838,
		16
	],
	"inactive_getter": [
		-77822,
		16
	],
	"campaign_elapsed_increment": [
		876556,
		14
	],
	"camera_owner_link": [
		337924,
		54
	],
	"battle_owner_link": [
		338027,
		35
	],
	"radio_owner_link": [
		337710,
		28
	],
	"player_camera_refresh": [
		584200,
		74
	],
	"mining_near_target": [
		587345,
		128
	],
	"camera_rate_scale": [
		909930,
		120
	],
	"camera_cached_defaults": [
		904179,
		40
	],
	"camera_fast_getter": [
		910550,
		12
	],
	"camera_handling_rates": [
		910458,
		92
	],
	"camera_normal_rates": [
		910574,
		38
	],
	"fast_forward_keyboard_record": [
		2423682,
		104
	],
	"flight_vtable": [
		2397562,
		104
	],
	"navigation_world_binding": [
		-41918,
		24
	],
	"navigation_player_binding": [
		559872,
		14
	],
	"navigation_player_advance": [
		581940,
		104
	],
	"shared_guidance": [
		568150,
		1486
	],
	"shared_effective_handling": [
		729296,
		106
	],
	"scalar_0": [
		1544610,
		4
	],
	"scalar_1": [
		1575050,
		4
	],
	"scalar_2": [
		1587862,
		4
	],
	"scalar_3": [
		1587862,
		4
	],
	"scalar_4": [
		1556914,
		4
	],
	"scalar_5": [
		1544610,
		4
	],
	"scalar_6": [
		1591754,
		4
	],
	"scalar_7": [
		1584146,
		4
	],
	"scalar_8": [
		1591758,
		4
	],
	"scalar_9": [
		1546078,
		4
	],
	"scalar_10": [
		1556914,
		4
	],
	"scalar_11": [
		1544610,
		4
	],
	"scalar_12": [
		1591754,
		4
	],
	"scalar_13": [
		1584146,
		4
	],
	"scalar_14": [
		1591758,
		4
	],
	"scalar_15": [
		1546078,
		4
	],
	"input_policy_flagsChanged": [
		932451,
		316
	],
	"input_policy_flagsChanged_metadata": [
		2378898,
		24
	],
	"input_policy_flagsChanged_selector": [
		2143869,
		14
	],
	"input_policy_rightMouseDown": [
		933267,
		242
	],
	"input_policy_rightMouseDown_metadata": [
		2378994,
		24
	],
	"input_policy_rightMouseDown_selector": [
		2143903,
		16
	],
	"input_policy_animationTimer": [
		929634,
		1267
	],
	"input_policy_animationTimer_metadata": [
		2378658,
		24
	],
	"input_policy_animationTimer_selector": [
		2142702,
		16
	],
	"input_policy_onQuit": [
		940661,
		461
	],
	"input_policy_onQuit_metadata": [
		2381122,
		24
	],
	"input_policy_onQuit_selector": [
		2145933,
		8
	],
	"input_policy_capture_transition": [
		958498,
		720
	]
}

const MAC_ALTERNATE := {
	"arrival_actor": [
		0,
		315
	],
	"press_mask_source": [
		341405,
		27
	],
	"press_mask_branch": [
		341588,
		29
	],
	"press_fast_forward": [
		345290,
		103
	],
	"release_reset": [
		348054,
		39
	],
	"default_multiplier": [
		338056,
		10
	],
	"clock_clamp_and_unscaled_totals": [
		362878,
		83
	],
	"pause_gate": [
		364348,
		11
	],
	"slow_motion_gate": [
		364359,
		15
	],
	"frame_cancel_and_scale": [
		364636,
		129
	],
	"player_world_schedule": [
		365975,
		143
	],
	"camera_schedule": [
		378858,
		108
	],
	"autopilot_active": [
		563218,
		14
	],
	"mining_approach_active": [
		601354,
		28
	],
	"later_approach_active": [
		595934,
		28
	],
	"near_target_active": [
		601280,
		14
	],
	"radio_active": [
		684324,
		14
	],
	"autopilot_setter": [
		562976,
		134
	],
	"autopilot_target_steering_near": [
		579009,
		459
	],
	"near_target_reset": [
		576646,
		16
	],
	"camera_fast_flag": [
		910682,
		408
	],
	"keyboard_down": [
		957449,
		239
	],
	"keyboard_up": [
		958182,
		152
	],
	"pointer_down_dispatch": [
		1351266,
		125
	],
	"pointer_up_dispatch": [
		1352322,
		135
	],
	"hud_hit_rect": [
		-89322,
		54
	],
	"hud_eligibility": [
		-98931,
		114
	],
	"keyboard_hud_position": [
		-92613,
		269
	],
	"battle_counter_loop": [
		668665,
		340
	],
	"battle_flag_set": [
		677474,
		34
	],
	"battle_flag_clear": [
		677845,
		14
	],
	"battle_counter_reset": [
		678428,
		17
	],
	"active_actor_getter": [
		541460,
		14
	],
	"destroyed_getter": [
		-77838,
		16
	],
	"inactive_getter": [
		-77822,
		16
	],
	"campaign_elapsed_increment": [
		877188,
		14
	],
	"camera_owner_link": [
		337624,
		54
	],
	"battle_owner_link": [
		337727,
		35
	],
	"radio_owner_link": [
		337410,
		28
	],
	"player_camera_refresh": [
		584736,
		74
	],
	"mining_near_target": [
		587881,
		128
	],
	"camera_rate_scale": [
		910562,
		120
	],
	"camera_cached_defaults": [
		904811,
		40
	],
	"camera_fast_getter": [
		911182,
		12
	],
	"camera_handling_rates": [
		911090,
		92
	],
	"camera_normal_rates": [
		911206,
		38
	],
	"fast_forward_keyboard_record": [
		2401114,
		104
	],
	"flight_vtable": [
		2374994,
		104
	],
	"navigation_world_binding": [
		-41918,
		24
	],
	"navigation_player_binding": [
		560408,
		14
	],
	"navigation_player_advance": [
		582476,
		104
	],
	"shared_guidance": [
		568686,
		1486
	],
	"shared_effective_handling": [
		729920,
		106
	],
	"scalar_0": [
		1519594,
		4
	],
	"scalar_1": [
		1550114,
		4
	],
	"scalar_2": [
		1562926,
		4
	],
	"scalar_3": [
		1562926,
		4
	],
	"scalar_4": [
		1531914,
		4
	],
	"scalar_5": [
		1519594,
		4
	],
	"scalar_6": [
		1566850,
		4
	],
	"scalar_7": [
		1559210,
		4
	],
	"scalar_8": [
		1566854,
		4
	],
	"scalar_9": [
		1521062,
		4
	],
	"scalar_10": [
		1531914,
		4
	],
	"scalar_11": [
		1519594,
		4
	],
	"scalar_12": [
		1566850,
		4
	],
	"scalar_13": [
		1559210,
		4
	],
	"scalar_14": [
		1566854,
		4
	],
	"scalar_15": [
		1521062,
		4
	],
	"input_policy_flagsChanged": [
		933175,
		316
	],
	"input_policy_flagsChanged_metadata": [
		2356330,
		24
	],
	"input_policy_flagsChanged_selector": [
		2121749,
		14
	],
	"input_policy_rightMouseDown": [
		933991,
		242
	],
	"input_policy_rightMouseDown_metadata": [
		2356426,
		24
	],
	"input_policy_rightMouseDown_selector": [
		2121783,
		16
	],
	"input_policy_animationTimer": [
		930358,
		1267
	],
	"input_policy_animationTimer_metadata": [
		2356090,
		24
	],
	"input_policy_animationTimer_selector": [
		2120582,
		16
	],
	"input_policy_onQuit": [
		941385,
		461
	],
	"input_policy_onQuit_metadata": [
		2358554,
		24
	],
	"input_policy_onQuit_selector": [
		2123813,
		8
	],
	"input_policy_capture_transition": [
		959226,
		720
	]
}

const RADAR_VALUES := {
	"scope": "ordinary_radar_battle",
	"scanner_equipment_type": 17,
	"inactive_modes": [
		3,
		4
	],
	"initial_battle": false,
	"publication_phase": "hud_after_world",
	"hidden_radar_retains_battle": true,
	"absent_scanner_skips_npc_loop": true,
	"distance_filter": false,
	"cargo_grants_battle": false,
	"hull_substitutes_for_mode": false,
	"debris_is_junk": true,
	"ordinary_asteroid": false,
	"ordinary_radar_hidden": false,
	"supported_actor_kinds": [
		0,
		1,
		2,
		3,
		8
	],
	"guarded_actor_kinds": [
		9,
		10
	],
	"guarded_music_id": 143
}

const RADAR_SPANS := {
	"asteroid_identity": [
		546824,
		29
	],
	"freighter_constructor": [
		631244,
		1108
	],
	"junk_constructor": [
		640188,
		52
	],
	"junk_factory_link": [
		67950,
		16
	],
	"type10_cloak_gate": [
		610036,
		75
	],
	"type10_cloak_hidden": [
		610450,
		57
	],
	"type10_cloak_visible": [
		610574,
		31
	],
	"cargo_presence": [
		-77020,
		46
	],
	"cargo_collected_flags": [
		-78783,
		48
	],
	"small_ship_drop_flag": [
		619502,
		29
	],
	"freighter_drop_flag": [
		634808,
		45
	],
	"hidden_attachment_factory": [
		53336,
		408
	],
	"radar_update_draw_order": [
		1349934,
		335
	],
	"flight_radar_draw_call": [
		390485,
		95
	],
	"radar_entry_gate": [
		662162,
		56
	],
	"radar_world_list_binding": [
		662428,
		15
	],
	"world_npc_list_getter": [
		105960,
		14
	],
	"radar_scanner_lookup": [
		660734,
		31
	],
	"installed_equipment_lookup": [
		730168,
		116
	],
	"radar_scanner_presence": [
		660807,
		127
	],
	"radar_scanner_loop_gate": [
		667656,
		69
	],
	"radar_loop_ordinary_exit": [
		668457,
		44
	],
	"radar_loop_tail": [
		670648,
		98
	],
	"radar_music_publication_gate": [
		676904,
		22
	],
	"radar_initial_counter_battle": [
		657413,
		27
	],
	"radar_initial_enabled": [
		661052,
		27
	],
	"flight_update_draw_vtable": [
		2397658,
		24
	],
	"base_constructor": [
		-81548,
		948
	],
	"ordinary_constructor": [
		605172,
		2562
	],
	"ordinary_update": [
		610766,
		17180
	]
}

const RADAR_MAC_ALTERNATE := {
	"asteroid_identity": [
		547360,
		29
	],
	"freighter_constructor": [
		631792,
		1108
	],
	"junk_constructor": [
		640736,
		52
	],
	"junk_factory_link": [
		67950,
		16
	],
	"type10_cloak_gate": [
		610584,
		75
	],
	"type10_cloak_hidden": [
		610998,
		57
	],
	"type10_cloak_visible": [
		611122,
		31
	],
	"cargo_presence": [
		-77020,
		46
	],
	"cargo_collected_flags": [
		-78783,
		48
	],
	"small_ship_drop_flag": [
		620050,
		29
	],
	"freighter_drop_flag": [
		635356,
		45
	],
	"hidden_attachment_factory": [
		53336,
		408
	],
	"radar_update_draw_order": [
		1342050,
		335
	],
	"flight_radar_draw_call": [
		391001,
		95
	],
	"radar_entry_gate": [
		662710,
		56
	],
	"radar_world_list_binding": [
		662976,
		15
	],
	"world_npc_list_getter": [
		105960,
		14
	],
	"radar_scanner_lookup": [
		661282,
		31
	],
	"installed_equipment_lookup": [
		730792,
		124
	],
	"radar_scanner_presence": [
		661355,
		127
	],
	"radar_scanner_loop_gate": [
		668204,
		69
	],
	"radar_loop_ordinary_exit": [
		669005,
		44
	],
	"radar_loop_tail": [
		671196,
		98
	],
	"radar_music_publication_gate": [
		677452,
		22
	],
	"radar_initial_counter_battle": [
		657961,
		27
	],
	"radar_initial_enabled": [
		661600,
		27
	],
	"flight_update_draw_vtable": [
		2375090,
		24
	],
	"base_constructor": [
		-81548,
		948
	],
	"ordinary_constructor": [
		605720,
		2562
	],
	"ordinary_update": [
		611314,
		17180
	]
}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size() != VALUES.size() + (2 if data.has("radar") else 1) or not data.get("provenance") is Dictionary:
		return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key), VALUES[key]):
			return false
	return not data.has("radar") or radar_parameters(data.radar)

static func radar_parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=RADAR_VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in RADAR_VALUES:
		if not Equal.equal_value(data.get(key),RADAR_VALUES[key]):return false
	return true

static func radar_available(data: Variant) -> bool:
	return parameters(data) and data.has("radar")

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary) -> String:
	if not data is Dictionary:
		return "Missing Fast Forward declarations"
	if data.is_empty():
		return ""
	if arch != "x86_64" or not parameters(data):
		return "Invalid Fast Forward parameters"
	var arrival_proof: Variant = arrival.get("provenance")
	if not arrival_proof is Dictionary:
		return "Fast Forward needs verified arrival declarations"
	var origin: Variant = arrival_proof.get("actor")
	if not Fonts.extent(origin, "offset", "bytes", [315], source_bytes):
		return "Fast Forward needs verified arrival declarations"
	for pair in [[SPANS,RADAR_SPANS],[MAC_ALTERNATE,RADAR_MAC_ALTERNATE]]:
		if not Layouts.matches(data.provenance,int(origin.offset),source_bytes,[pair[0]]):continue
		if not data.has("radar") or Layouts.matches(data.radar.provenance,int(origin.offset),source_bytes,[pair[1]]):return ""
	return "Invalid or mixed Fast Forward provenance"
