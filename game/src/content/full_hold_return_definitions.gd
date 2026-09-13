extends RefCounted
## Second mining return and the next station equipment instruction.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const First=preload("res://src/content/station_return_definitions.gd")
const Story=preload("res://src/content/full_hold_story_definitions.gd")
const VALUES := {"scope":"full_hold_station_return","station_id":78,"system_id":15,"departing_cursor":4,"campaign_cursor":5,"source_state":5,"contact_radius":16000.0,"contact_before_motion":true,"volume_after_motion":true,"requires_station_target":true,"mission_kind":11,"restricted_mission_kind":154,"restricted_notice":21,"minimum_delivered_cargo":25,"cache_pools":["hull","armor","shield","gamma"],"cache_truncates":["shield","gamma"],"cargo_preserved_on_arrival":true,"clear_cargo_after_acknowledgement":true,"mode":1,"next_text_id":179,"final_text_id":180,"cursor_after_acknowledgement":6,"next_mission_kind":158,"next_mission_parameter":0,"reward_credits":0,"bonus_credits":0,"events":[{"speaker_id":2,"text_id":1719,"voice_event_id":433},{"speaker_id":0,"text_id":1720,"voice_event_id":434},{"speaker_id":2,"text_id":1721,"voice_event_id":435},{"speaker_id":0,"text_id":1722,"voice_event_id":436},{"speaker_id":2,"text_id":1723,"voice_event_id":437},{"speaker_id":16,"text_id":1724,"voice_event_id":-1}],"refresh_cargo_after_acknowledgement":false}
const SPANS := {"mode1_counts":[1555258,24],"mode1_return_events":[1546594,48],"voice_table":[1560154,12032],"cursor6_dispatch":[871426,4],"cursor6_factory":[860701,50],"factory_install":[860545,16],"cargo_list_dispose":[730856,54],"mission_constructor":[399266,448],"station_acknowledgement":[429803,1908],"station_dialogue_selection":[447318,69],"dialogue_mission_binding":[-693644,28],"mission_voice_actor":[401310,10],"silent_voice_lookup":[-215216,68],"silent_voice_return":[-212901,14],"next_mission_equipment":[874532,126]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func select(bindings: RefCounted, campaign_cursor: Variant) -> Dictionary:
	if bindings==null or not campaign_cursor is int:return {}
	if campaign_cursor==3 and First.parameters(bindings.station_return):return bindings.station_return.duplicate(true)
	if campaign_cursor==5 and parameters(bindings.full_hold_return):return bindings.full_hold_return.duplicate(true)
	return {}

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, first: Dictionary, story: Dictionary) -> String:
	if not data is Dictionary:return "Missing second station return declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported second station return declarations"
	if not First.parameters(first) or not Story.parameters(story):return "Second station return lacks verified docking or cargo context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Second station return lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid second station return provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid second station return extent: "+key
	return ""
