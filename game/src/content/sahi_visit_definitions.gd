extends RefCounted
## Original Sahi selected-arrival briefing. No encounter completion is declared.
const Equal = preload("res://src/content/opening_escape_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const Layouts = preload("res://src/content/declaration_layouts.gd")
const VALUES = {"scope":"sahi_selected_arrival_briefing","campaign_cursor":24,"system_id":9,"mission":{"kind":4,"station_id":48,"reward":0,"bonus":0,"source_parameter":0},"preferred_course":{"system_id":9,"station_id":48},"briefing":{"mode":0,"selected_story_only":true,"controller_ready_required":true,"pending_required":true,"hud_minimum_ms":5001,"events":[{"speaker_id":6,"text_id":1888,"voice_event_id":169},{"speaker_id":0,"text_id":1889,"voice_event_id":170},{"speaker_id":6,"text_id":1890,"voice_event_id":171},{"speaker_id":0,"text_id":1891,"voice_event_id":172}]},"result_event_count":0,"selected_world":{"ordinary_population":false}}
const SPANS = {"sahi_selection":[856965,661],"sahi_briefing_start":[385208,536],"sahi_briefing_caller":[375756,79],"sahi_empty_mission":[400436,14],"sahi_story_flag":[400856,16],"sahi_briefing_pending":[400464,14],"sahi_population_selection":[-42348,319],"sahi_dialogue_offsets":[-694459,60],"sahi_dialogue_speaker":[-692188,33],"sahi_dialogue_text":[-691916,45],"sahi_voice_lookup":[-215198,41],"sahi_mission_constructor":[399256,448],"sahi_controller_ready":[233384,11],"sahi_has_briefing":[-692532,33],"sahi_factory_dispatch":[871498,4],"sahi_factory":[861879,65],"sahi_briefing_counts":[1554602,100],"sahi_result_counts":[1555258,100],"sahi_briefing_events":[1556050,32],"sahi_briefing_voices":[1560202,32],"sahi_count_selector":[-694455,56],"sahi_completed":[400488,10],"sahi_failed":[400508,12]}
const MAC_VALUES = {"scope":"sahi_selected_arrival_briefing","campaign_cursor":24,"system_id":9,"mission":{"kind":4,"station_id":48,"reward":0,"bonus":0,"source_parameter":0},"preferred_course":{"system_id":9,"station_id":48},"briefing":{"mode":0,"selected_story_only":true,"controller_ready_required":true,"pending_required":true,"hud_minimum_ms":5001,"events":[{"speaker_id":6,"text_id":1902,"voice_event_id":169},{"speaker_id":0,"text_id":1903,"voice_event_id":170},{"speaker_id":6,"text_id":1904,"voice_event_id":171},{"speaker_id":0,"text_id":1905,"voice_event_id":172}]},"result_event_count":0,"selected_world":{"ordinary_population":false}}
const MAC_SPANS = {"sahi_selection":[857597,661],"sahi_briefing_start":[385724,536],"sahi_briefing_caller":[376268,79],"sahi_empty_mission":[400952,14],"sahi_story_flag":[401372,16],"sahi_briefing_pending":[400980,14],"sahi_population_selection":[-42348,319],"sahi_dialogue_offsets":[-700355,60],"sahi_dialogue_speaker":[-698084,33],"sahi_dialogue_text":[-697805,45],"sahi_voice_lookup":[-216154,41],"sahi_mission_constructor":[399772,448],"sahi_controller_ready":[233396,11],"sahi_has_briefing":[-698428,33],"sahi_factory_dispatch":[872130,4],"sahi_factory":[862511,65],"sahi_briefing_counts":[1529586,100],"sahi_result_counts":[1530242,100],"sahi_briefing_events":[1531050,32],"sahi_briefing_voices":[1535266,32],"sahi_count_selector":[-700351,56],"sahi_completed":[401004,10],"sahi_failed":[401024,12]}

# Native composition.
static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data, VALUES) or Equal.equal_value(data, MAC_VALUES)

static func validate(data: Variant, provenance: Variant, executable_bytes: int, architecture: String, arrival: Dictionary) -> String:
	if data is Dictionary and data.is_empty():
		return "" if provenance is Dictionary and provenance.is_empty() else "Unexpected Sahi arrival provenance"
	if architecture != "x86_64" or not parameters(data):return "Unsupported Sahi arrival declarations"
	var source: Variant = arrival.get("provenance")
	if not source is Dictionary:return "Sahi arrival lacks its staging anchor"
	var anchor: Variant = source.get("actor")
	if not Fonts.extent(anchor, "offset", "bytes", [315], executable_bytes):return "Sahi arrival lacks its staging anchor"
	var spans: Dictionary = SPANS if Equal.equal_value(data, VALUES) else MAC_SPANS
	return "" if Layouts.matches(provenance, int(anchor.offset), executable_bytes, [spans]) else "Disconnected Sahi arrival declarations"

static func available(bindings: RefCounted) -> bool:
	return bindings != null and parameters(bindings.mido_travel.get("sahi_visit"))

static func selected(travel: Dictionary, context: Dictionary) -> bool:
	if not parameters(travel.get("sahi_visit")):return false
	if not Equal.equal_value(context.get("mission_story"), true):return false
	for field in ["mission_completed", "mission_failed"]:
		if not Equal.equal_value(context.get(field), false):return false
	var rules: Dictionary = travel.sahi_visit
	var expected := {"campaign_cursor": int(rules.campaign_cursor), "system_id": int(rules.system_id),
		"station_id": int(rules.mission.station_id), "mission_kind": int(rules.mission.kind)}
	for field in expected:
		if not context.get(field) is int or context[field] != expected[field]:return false
	return true

static func briefing(travel: Dictionary, context: Dictionary) -> Array:
	return travel.sahi_visit.briefing.events.duplicate(true) if selected(travel, context) else []

static func can_start_briefing(travel: Dictionary, context: Dictionary) -> bool:
	if not selected(travel, context):return false
	if not Equal.equal_value(context.get("controller_ready"), true) or not Equal.equal_value(context.get("briefing_pending"), true):return false
	if not Equal.equal_value(context.get("dialogue_active"), false):return false
	var elapsed: Variant = context.get("hud_elapsed_ms")
	return elapsed is int and elapsed >= int(travel.sahi_visit.briefing.hud_minimum_ms)
