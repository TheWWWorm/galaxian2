extends RefCounted
## First mining briefing and entry clocks, separate from mission completion.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Flight=preload("res://src/content/first_flight_definitions.gd")
const Desktop=preload("res://src/content/desktop_text_definitions.gd")
const Presentation=preload("res://src/content/station_presentation_definitions.gd")
const VALUES := {"scope":"first_mining_briefing","campaign_cursor":2,"mission_kind":154,"mode":0,"entry_release_ms":7001,"briefing_minimum_ms":5001,"max_frame_ms":150,"briefing_before_controller_update":true,"modal_stops_simulation":true,"final_acknowledgement_clears_pending":true,"final_acknowledgement_completes_mission":false,"next_text_id":179,"final_text_id":180,"key_token":"#KEY_DOCK","events":[{"speaker_id":0,"text_id":1699,"voice_event_id":177},{"speaker_id":2,"text_id":1700,"voice_event_id":178},{"speaker_id":0,"text_id":1701,"voice_event_id":179},{"speaker_id":2,"text_id":1702,"voice_event_id":180},{"speaker_id":16,"text_id":1703,"voice_event_id":-1}]}
const SPANS := {"count_prefix":[1554602,12],"events":[1555922,40],"voice_events":[1560266,32],"index_table":[-694459,60],"dialogue_mode":[-693624,144],"speaker_selection":[-692286,155],"text_selection":[-692078,65],"line_count":[-686407,60],"next_line":[-686457,41],"previous_line":[-685046,45],"acknowledgement":[-685001,56],"hud_initial":[338262,51],"hud_modal_clock_gate":[364625,11],"hud_clock":[365124,19],"hud_modal_dispatch":[368096,39],"briefing_start":[385208,516],"controller_order":[377622,24],"modal_update_dispatch":[376727,41],"modal_update":[377346,51],"final_acknowledgement":[351489,102],"unfinished_mission":[352080,40],"post_briefing":[356073,40],"clear_pending":[233366,18]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary, presentation: Dictionary, desktop: Dictionary) -> String:
	if not data is Dictionary:return "Missing mining briefing declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Flight.parameters(flight) or not Presentation.parameters(presentation) or not Desktop.parameters(desktop):return "Unsupported mining briefing"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Mining briefing lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid mining briefing provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid mining briefing extent: "+key
	return ""
