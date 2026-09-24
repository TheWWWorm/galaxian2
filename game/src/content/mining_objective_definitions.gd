extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Total cargo objective and acknowledged return instructions; docking is separate.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Flight=preload("res://src/content/first_flight_definitions.gd")
const VALUES := {"scope":"first_mining_cargo_objective","campaign_cursor":2,"mission_kind":154,"station_id":78,"required_cargo":10,"cargo_metric":"total_used","poll_minimum_ms":5001,"max_frame_ms":150,"initial_clock_held":false,"entry_controller_holds_clock":true,"idle_poll_discards_overshoot":true,"completion_opening_holds_camera":true,"mode":1,"cursor_after_acknowledgement":3,"next_kind":11,"reward_credits":0,"bonus_credits":0,"station_return_required":true,"next_text_id":179,"final_text_id":180,"events":[{"speaker_id":2,"text_id":1706,"voice_event_id":327},{"speaker_id":0,"text_id":1707,"voice_event_id":328},{"speaker_id":16,"text_id":1708,"voice_event_id":-1}],"desktop_instruction":[1708,1709],"key_tokens":["#KEY_AUTOPILOT","#KEY_DOCK"]}
const SPANS := {"mode1_counts":[1555258,12],"mode1_events":[1546514,24],"voice_events":[1561466,16],"cargo_getter":[729972,10],"parameter_getter":[400574,12],"shown_getter":[400508,10],"shown_setter":[400498,10],"cargo_dispatch":[875250,4],"cargo_predicate":[873791,24],"cargo_compare":[874658,22],"cargo_success":[875180,18],"poll_gate":[385853,89],"poll_reset":[388744,22],"completion_order":[377531,73],"completion_dialogue_test":[387006,61],"completion_dialogue_start":[387235,69],"dialogue_mode":[-693532,52],"mission_next":[859851,23],"next_dispatch":[871414,4],"next_mission":[860512,49],"final_advance":[352276,37],"final_reward":[352369,64],"final_cleanup":[352952,122],"final_reset":[356086,27],"clock_initial":[338262,51],"clock_modal_gate":[364625,11],"clock_increment":[365124,19],"controller_initial_hold":[121658,5],"controller_initial_override":[121716,5],"controller_release":[151090,87],"controller_return":[230741,7],"controller_clock_order":[377622,24],"controller_override_clock":[378039,14],"initial_briefing_dispatch":[375756,113],"initial_player_mode":[550660,7],"player_mode_getter":[559186,14]}

const MAC_ALTERNATE := {"mode1_counts":[1530242,12],"mode1_events":[1521498,24],"voice_events":[1536530,16],"cargo_getter":[730596,10],"parameter_getter":[401090,12],"shown_getter":[401024,10],"shown_setter":[401014,10],"cargo_dispatch":[875882,4],"cargo_predicate":[874423,24],"cargo_compare":[875290,22],"cargo_success":[875812,18],"poll_gate":[386369,89],"poll_reset":[389260,22],"completion_order":[378043,73],"completion_dialogue_test":[387522,61],"completion_dialogue_start":[387751,69],"dialogue_mode":[-699428,52],"mission_next":[860483,23],"next_dispatch":[872046,4],"next_mission":[861144,49],"final_advance":[351990,37],"final_reward":[352083,64],"final_cleanup":[352666,122],"final_reset":[355800,27],"clock_initial":[337962,51],"clock_modal_gate":[364348,11],"clock_increment":[364847,19],"controller_initial_hold":[121658,5],"controller_initial_override":[121716,5],"controller_release":[151090,87],"controller_return":[230755,7],"controller_clock_order":[378134,24],"controller_override_clock":[378551,14],"initial_briefing_dispatch":[376268,113],"initial_player_mode":[551196,7],"player_mode_getter":[559722,14]}
const MAC_VALUES := {"scope":"first_mining_cargo_objective","campaign_cursor":2,"mission_kind":154,"station_id":78,"required_cargo":10,"cargo_metric":"total_used","poll_minimum_ms":5001,"max_frame_ms":150,"initial_clock_held":false,"entry_controller_holds_clock":true,"idle_poll_discards_overshoot":true,"completion_opening_holds_camera":true,"mode":1,"cursor_after_acknowledgement":3,"next_kind":11,"reward_credits":0,"bonus_credits":0,"station_return_required":true,"next_text_id":179,"final_text_id":180,"events":[{"speaker_id":2,"text_id":1717,"voice_event_id":327},{"speaker_id":0,"text_id":1718,"voice_event_id":328},{"speaker_id":16,"text_id":1719,"voice_event_id":-1}],"desktop_instruction":[1719,1720],"key_tokens":["#KEY_AUTOPILOT","#KEY_DOCK"]}

static func parameters(data: Variant) -> bool:
	return _parameters(data,VALUES) or _parameters(data,MAC_VALUES)

static func _parameters(data: Variant,expected: Dictionary) -> bool:
	if not data is Dictionary or data.size()!=expected.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in expected:
		if not Equal.equal_value(data.get(key),expected[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary) -> String:
	if not data is Dictionary:return "Missing mining objective declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Flight.parameters(flight):return "Unsupported mining objective declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Mining objective lacks its source anchor"
	var layouts: Array=[]
	if _parameters(data,VALUES):layouts.append(SPANS)
	if _parameters(data,MAC_VALUES):layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid mining objective extents"
