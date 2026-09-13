extends RefCounted
## Verified Mac starter destruction clocks and effect contract. Application
## routing, damage particles and game-over art have separate owners.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Flight=preload("res://src/content/full_hold_flight_definitions.gd")
const NPC=preload("res://src/content/npc_destruction_definitions.gd")
const VALUES := {"scope":"mac_starter_player_destruction","departure_cursor":4,"story_cursors":[4,5],"ship_id":0,"escape_equipment_category":27,"escape_equipment_absent":true,"effect_type":0,"model_ids":[16821,16820],"fragment_count":0,"construction_random_draws":0,"initial_elapsed_ms":0,"spin_per_update":0.029999999329447746,"rotation_order":"XYZ","rotation_accumulates_euler":true,"spin_on_zero_delta":true,"breakup_ms":3000,"effect_update_after_ms":3000,"failure_after_ms":8000,"failure_delay_ms":3000,"fade_ms":4000,"failure_text_id":308,"continue_text_id":188,"game_over_image_id":1313,"continue_source_state":1,"breakup_sound_base":18,"breakup_sound_bound":2,"failure_sound":37,"stop_sound_ids":[27,35,2261,2260,2252,1095,1096,1097],"camera_follow_enabled":false,"statistics_active":false,"hide_hud_on_start":true,"body_visible_before_breakup":true,"model_rotation_after_statistics":true,"effect_uses_current_physical_position":true,"effect_overshoot_discarded":true,"poll_reenables_emission":true,"breakup_disables_particle_drawing":true,"player_stops_at_fade_end":true,"world_continues":true,"grants_rewards":false}
const SPANS := {"player_constructor":[549940,3862],"escape_equipment_binding":[554604,988],"escape_branch":[598780,178],"living_station_predicate":[562952,38],"death_poll":[388290,794],"death_start":[599954,278],"effect_constructor":[-684728,1466],"effect_wrapper":[-684738,10],"effect_trigger":[-681366,484],"effect_sound_choice":[-681822,456],"effect_update":[-679920,280],"effect_reset":[-682904,424],"player_delta":[571164,138],"death_update":[584311,533],"death_ready":[600700,32],"player_draw":[602902,98],"euler_accumulation":[-723090,140],"spin_constant":[1582622,4],"camera_attach":[232166,136],"camera_enable":[905074,10],"camera_update_gate":[905887,23],"failure_clock":[365116,27],"player_update_gate":[366264,126],"poll_order":[377531,91],"input_gate":[378646,39],"failure_display":[390050,435],"failure_input":[341589,102],"world_after_player":[390882,354]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary, actors: Dictionary) -> String:
	if not data is Dictionary:return "Missing player destruction declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported player destruction declarations"
	if not Flight.parameters(flight) or not NPC.parameters(actors.get("npc_initialization",{}).get("destruction")):return "Player destruction lacks its verified departure or shared effect context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Player destruction lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid player destruction provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid player destruction extent: "+key
	return ""
