extends RefCounted
## Original Sahi portal-stage declarations and transition boundary.
const Equal = preload("res://src/content/opening_escape_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const Layouts = preload("res://src/content/declaration_layouts.gd")
const Encounter = preload("res://src/content/sahi_encounter_definitions.gd")
const VALUES = {"scope":"sahi_portal_stage_declarations","campaign_cursor":24,"mission_kind":4,"system_id":9,"station_id":48,"sequence":{"initial_phase":0,"view_phase":1,"open_phase":2,"condition_kind":31,"condition_value":0,"generic_condition_succeeds":false,"view_event_started":3,"open_event_started":4,"spin_on_open_frame":true,"completion_owner":"living_player_portal_entry"},"view":{"input_blocked":true,"hud_visible":false,"target_overlay_visible":false,"primary_trigger":false,"damage_enabled":false,"scripted_coast":true,"discard_flight_weapons":true,"clear_npc_weapon_targets":true,"player_updates_continue":true,"physical_rotation":[0.0,1.5707963705062866,0.0],"camera_target":"player_physical_pose","camera_eye_offset":[10500.0,700.0,1000.0],"rebase_starfield":true},"portal":{"environment_slot":3,"model_id":16994,"forward_offset":45000.0,"open_elapsed_ms":-3000,"open_extent":0,"open_duration_ms":3000,"close_start_ms":60000,"hide_at_ms":63001,"maximum_extent":4096},"spin":{"visual_only":true,"rotation_axes":[1.0,1.0,1.0],"rotation_divisor_ms":5000.0,"sound_event_id":34,"sound_position":"camera_eye","sound_velocity":[0.0,0.0,0.0],"shake_kind":3,"shake_amount":50.0},"contact":{"cube_half_extent":40000.0,"cube_boundary":"exclusive","distance_rounding":"truncate","pull_radius":40000,"pull_distance_shift":8,"pull_step":"per_contact_update","entry_distance_maximum":999,"requires_visible":true,"requires_not_closing":true,"requires_inactive_mining":true},"transition":{"requires_positive_hull":true,"next_cursor":25,"clear_world_conditions":true,"clear_active_mission":true,"adopt_pending_station_when_distinct":true,"retain_pending_station":true,"reload_flight":true,"retain_current_hull":true,"retain_current_shield":true,"retain_current_armor":true,"retain_emp_state":true},"next_factory":{"campaign_cursor":25,"mission_kind":156,"target_station_id":-1,"protected_cargo_item_id":131,"protect_first_matching_row":true,"grants_cargo":false}}
const SPANS = {"sahi_stage_selected_factory_dispatch":[871498,4],"sahi_stage_selected_factory":[861879,65],"sahi_stage_mission_constructor":[399256,448],"sahi_stage_story_flag":[400856,16],"sahi_stage_cast":[6321,570],"sahi_stage_story_dispatch":[152245,16],"sahi_stage_radio_started":[684372,12],"sahi_stage_starfield_rebase":[255876,222],"sahi_stage_weapon_targets_clear":[535982,246],"sahi_stage_portal_reset":[655330,38],"sahi_stage_portal_open":[655434,26],"sahi_stage_portal_vtable":[2401610,192],"sahi_stage_portal_update":[655588,1380],"sahi_stage_protected_cargo_getter":[-81574,10],"sahi_stage_sequence":[158023,933],"sahi_stage_initial_phase":[121650,8],"sahi_stage_story_gate":[151961,78],"sahi_stage_condition_constructor":[480550,46],"sahi_stage_condition_dispatch":[481000,44],"sahi_stage_condition_false_return":[482036,9],"sahi_stage_primary_trigger":[558760,86],"sahi_stage_camera_scripted":[909920,10],"sahi_stage_damage_enabled":[537626,14],"sahi_stage_scripted_coast":[562416,14],"sahi_stage_clear_flight_weapons":[542012,66],"sahi_stage_camera_target":[905084,10],"sahi_stage_camera_eye":[905204,36],"sahi_stage_camera_eye_offset":[905250,88],"sahi_stage_portal_visible":[-80112,32],"sahi_stage_camera_eye_getter":[905240,10],"sahi_stage_camera_shake":[909494,20],"sahi_stage_visual_rotation":[599726,126],"sahi_stage_player_yaw":[1574930,4],"sahi_stage_eye_x":[1582742,4],"sahi_stage_eye_y":[1546006,4],"sahi_stage_eye_z":[1556930,4],"sahi_stage_portal_forward":[1575154,4],"sahi_stage_shake_amount":[1557078,4],"sahi_stage_spin_divisor":[1545990,4],"sahi_stage_direct_damage":[537770,90],"sahi_stage_mining_operation":[588370,8],"sahi_stage_mining_assignment":[588458,8],"sahi_stage_mining_constructor_wrapper":[393042,10],"sahi_stage_mining_category":[393297,10],"sahi_stage_portal_contact":[585200,684],"sahi_stage_portal_closing":[655460,20],"sahi_stage_portal_point_xyz":[642072,96],"sahi_stage_portal_point_xyz_wrapper":[642202,12],"sahi_stage_portal_point_wrapper":[-76580,26],"sahi_stage_portal_constructor":[655150,180],"sahi_stage_contact_extent_setter":[535780,10],"sahi_stage_entry_ready":[562952,38],"sahi_stage_application_transition":[379337,542],"sahi_stage_story_advance":[859802,81],"sahi_stage_clear_world_conditions":[118602,22],"sahi_stage_clear_active_mission":[858112,14],"sahi_stage_same_station":[858058,26],"sahi_stage_station_equal":[853288,22],"sahi_stage_adopt_pending_station":[855714,78],"sahi_stage_pending_station_selection":[856506,1552],"sahi_stage_next_factory_dispatch":[871502,4],"sahi_stage_next_factory":[861944,107],"sahi_stage_protect_cargo_item":[-84714,10],"sahi_stage_next_cargo_loop":[871388,8],"sahi_stage_current_hull":[537554,12],"sahi_stage_current_shield":[537302,14],"sahi_stage_current_armor":[537354,12],"sahi_stage_emp_state":[537378,14]}
const MAC_SPANS = {"sahi_stage_selected_factory_dispatch":[872130,4],"sahi_stage_selected_factory":[862511,65],"sahi_stage_mission_constructor":[399772,448],"sahi_stage_story_flag":[401372,16],"sahi_stage_cast":[6321,570],"sahi_stage_story_dispatch":[152245,16],"sahi_stage_radio_started":[684920,12],"sahi_stage_starfield_rebase":[255888,222],"sahi_stage_weapon_targets_clear":[536518,246],"sahi_stage_portal_reset":[655878,38],"sahi_stage_portal_open":[655982,26],"sahi_stage_portal_vtable":[2379042,192],"sahi_stage_portal_update":[656136,1380],"sahi_stage_protected_cargo_getter":[-81574,10],"sahi_stage_sequence":[158023,933],"sahi_stage_initial_phase":[121650,8],"sahi_stage_story_gate":[151961,78],"sahi_stage_condition_constructor":[481078,46],"sahi_stage_condition_dispatch":[481528,44],"sahi_stage_condition_false_return":[482564,9],"sahi_stage_primary_trigger":[559296,86],"sahi_stage_camera_scripted":[910552,10],"sahi_stage_damage_enabled":[538162,14],"sahi_stage_scripted_coast":[562952,14],"sahi_stage_clear_flight_weapons":[542548,66],"sahi_stage_camera_target":[905716,10],"sahi_stage_camera_eye":[905836,36],"sahi_stage_camera_eye_offset":[905882,88],"sahi_stage_portal_visible":[-80112,32],"sahi_stage_camera_eye_getter":[905872,10],"sahi_stage_camera_shake":[910126,20],"sahi_stage_visual_rotation":[600274,126],"sahi_stage_player_yaw":[1549994,4],"sahi_stage_eye_x":[1557806,4],"sahi_stage_eye_y":[1520990,4],"sahi_stage_eye_z":[1531930,4],"sahi_stage_portal_forward":[1550218,4],"sahi_stage_shake_amount":[1532078,4],"sahi_stage_spin_divisor":[1520974,4],"sahi_stage_direct_damage":[538306,90],"sahi_stage_mining_operation":[588906,8],"sahi_stage_mining_assignment":[589005,8],"sahi_stage_mining_constructor_wrapper":[393558,10],"sahi_stage_mining_category":[393813,10],"sahi_stage_portal_contact":[585736,684],"sahi_stage_portal_closing":[656008,20],"sahi_stage_portal_point_xyz":[642620,96],"sahi_stage_portal_point_xyz_wrapper":[642750,12],"sahi_stage_portal_point_wrapper":[-76580,26],"sahi_stage_portal_constructor":[655698,180],"sahi_stage_contact_extent_setter":[536316,10],"sahi_stage_entry_ready":[563488,38],"sahi_stage_application_transition":[379849,542],"sahi_stage_story_advance":[860434,81],"sahi_stage_clear_world_conditions":[118602,22],"sahi_stage_clear_active_mission":[858744,14],"sahi_stage_same_station":[858690,26],"sahi_stage_station_equal":[853920,22],"sahi_stage_adopt_pending_station":[856346,78],"sahi_stage_pending_station_selection":[857138,1552],"sahi_stage_next_factory_dispatch":[872134,4],"sahi_stage_next_factory":[862576,107],"sahi_stage_protect_cargo_item":[-84714,10],"sahi_stage_next_cargo_loop":[872020,8],"sahi_stage_current_hull":[538090,12],"sahi_stage_current_shield":[537838,14],"sahi_stage_current_armor":[537890,12],"sahi_stage_emp_state":[537914,14]}

# Native composition.
static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data, VALUES)

static func validate(data: Variant, provenance: Variant, executable_bytes: int, architecture: String, arrival: Dictionary) -> String:
	if data is Dictionary and data.is_empty():
		return "" if provenance is Dictionary and provenance.is_empty() else "Unexpected Sahi stage provenance"
	if architecture != "x86_64" or not parameters(data):return "Unsupported Sahi stage declarations"
	var source: Variant = arrival.get("provenance")
	if not source is Dictionary:return "Sahi stage lacks its staging anchor"
	var anchor: Variant = source.get("actor")
	if not Fonts.extent(anchor, "offset", "bytes", [315], executable_bytes):return "Sahi stage lacks its staging anchor"
	return "" if Layouts.matches(provenance, int(anchor.offset), executable_bytes, [SPANS, MAC_SPANS]) else "Disconnected Sahi stage declarations"

static func coherent(travel: Dictionary) -> bool:
	return parameters(travel.get("sahi_stage")) and Encounter.coherent(travel)

static func selected(travel: Dictionary, context: Dictionary) -> bool:
	return coherent(travel) and Encounter.selected(travel, context)

## The caller owns elapsed time, earned radio observations and all state changes.
static func declarations(travel: Dictionary, context: Dictionary) -> Dictionary:
	return travel.sahi_stage.duplicate(true) if selected(travel, context) else {}

## A newly entered view cannot skip directly to the open phase in one update.
static func phase_for_started_events(travel: Dictionary, context: Dictionary, phase: Variant, started_events: Variant) -> int:
	if not selected(travel, context) or not phase is int or not started_events is Array:return -1
	var sequence: Dictionary = travel.sahi_stage.sequence
	if phase < sequence.initial_phase or phase > sequence.open_phase:return -1
	if started_events.size() != travel.sahi_encounter.radio_events.size():return -1
	for started in started_events:
		if not started is bool:return -1
	if phase == sequence.initial_phase and started_events[sequence.view_event_started]:return sequence.view_phase
	if phase == sequence.view_phase and started_events[sequence.open_event_started]:return sequence.open_phase
	return phase

## Report the source contact thresholds without moving a body or setting an
## entry flag. The existing environment owner decides whether contact runs.
static func portal_contact(travel: Dictionary, context: Dictionary, observation: Dictionary) -> Dictionary:
	if not selected(travel, context):return {}
	return preload("res://src/simulation/portal_contact.gd").evaluate(travel.sahi_stage.contact,int(travel.sahi_stage.portal.close_start_ms),observation)

## Portal contact is earned separately. A completed radio or elapsed timer does
## not satisfy the application transition, and a destroyed player cannot enter.
static func transition_ready(travel: Dictionary, context: Dictionary, observation: Dictionary) -> bool:
	if not selected(travel, context):return false
	var entered: Variant = observation.get("portal_entered")
	var hull: Variant = observation.get("player_hull")
	return entered is bool and entered and hull is int and hull > 0
