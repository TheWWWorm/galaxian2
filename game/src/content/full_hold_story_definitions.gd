extends RefCounted
## Source dialogue and mission context for the second mining trip.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Flight=preload("res://src/content/full_hold_flight_definitions.gd")
const Briefing=preload("res://src/content/mining_briefing_definitions.gd")
const Objective=preload("res://src/content/mining_objective_definitions.gd")
const VALUES := {"scope":"full_hold_mining_story","campaign_cursor":4,"mission_kind":154,"station_id":78,"required_cargo":25,"cursor_after_acknowledgement":5,"next_kind":11,"briefing_events":[{"speaker_id":2,"text_id":1716,"voice_event_id":188}],"completion_events":[{"speaker_id":0,"text_id":1717,"voice_event_id":431},{"speaker_id":2,"text_id":1718,"voice_event_id":432}]}
const SPANS := {"mode0_counts":[1554602,20],"mode0_events":[1555962,8],"mode1_counts":[1555258,20],"mode1_events":[1546578,16],"briefing_voice":[1560354,8],"completion_voices":[1562298,16],"next_dispatch":[871422,4],"next_mission":[860658,43],"acknowledgement_cleanup":[352080,4033],"entry_controller":[150932,435]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func briefing(bindings: RefCounted, cursor: Variant) -> Dictionary:
	return _select(bindings,cursor,false)

static func objective(bindings: RefCounted, cursor: Variant) -> Dictionary:
	return _select(bindings,cursor,true)

static func _select(bindings: RefCounted, cursor: Variant, completion: bool) -> Dictionary:
	if bindings==null or not cursor is int:return {}
	var shared: Dictionary=bindings.mining_objective if completion else bindings.mining_briefing
	if not (Objective.parameters(shared) if completion else Briefing.parameters(shared)):return {}
	if cursor==2:return shared.duplicate(true)
	if cursor!=4 or not parameters(bindings.full_hold_story) or not Flight.parameters(bindings.full_hold_flight):return {}
	var result: Dictionary=shared.duplicate(true);var data: Dictionary=bindings.full_hold_story
	result.campaign_cursor=int(data.campaign_cursor)
	result.events=data.completion_events.duplicate(true) if completion else data.briefing_events.duplicate(true)
	if completion:
		for key in ["required_cargo","cursor_after_acknowledgement","next_kind","station_id"]:result[key]=int(data[key])
	return result

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary, first_briefing: Dictionary, first_objective: Dictionary) -> String:
	if not data is Dictionary:return "Missing second-trip story declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported second-trip story declarations"
	if not Flight.parameters(flight) or not Briefing.parameters(first_briefing) or not Objective.parameters(first_objective):return "Second-trip story lacks its verified flight, dialogue or cargo context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Second-trip story lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid second-trip story provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid second-trip story extent: "+key
	return ""
