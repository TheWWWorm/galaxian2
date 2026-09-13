extends RefCounted
## Authored training dialogue and the acknowledged return transition.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Training=preload("res://src/content/combat_training_definitions.gd")
const Destruction=preload("res://src/content/combat_training_destruction_definitions.gd")
const SharedStory=preload("res://src/content/full_hold_story_definitions.gd")
const Briefing=preload("res://src/content/mining_briefing_definitions.gd")
const Objective=preload("res://src/content/mining_objective_definitions.gd")
const Voice=preload("res://src/content/radio_audio_definitions.gd")
const FirstFlight=preload("res://src/content/first_flight_definitions.gd")

const VALUES := {"scope":"combat_training_story","campaign_cursor":7,"mission_kind":4,"station_id":78,"system_id":15,"briefing_events":[{"speaker_id":2,"text_id":1726,"voice_event_id":189},{"speaker_id":16,"text_id":1727,"voice_event_id":-1},{"speaker_id":16,"text_id":1728,"voice_event_id":-1}],"completion_events":[{"speaker_id":2,"text_id":1733,"voice_event_id":439},{"speaker_id":0,"text_id":1734,"voice_event_id":440},{"speaker_id":2,"text_id":1735,"voice_event_id":441},{"speaker_id":0,"text_id":1736,"voice_event_id":442},{"speaker_id":2,"text_id":1737,"voice_event_id":443}],"radio_events":[{"speaker_id":2,"text_id":1731,"voice_event_id":543,"condition":16,"values":[0]},{"speaker_id":0,"text_id":1732,"voice_event_id":544,"condition":6,"values":[0]}],"radio_timing":{"display_delay_ms":2000,"base_duration_ms":1500,"per_line_ms":2000},"radio_actor_ids":[0,1,2,3],"radio_excludes_scenery":true,"radio_requires_active":true,"radio_requires_not_friendly":true,"radio_requires_positive_hull":false,"defeat_condition":{"kind":18,"begin":0,"end":3,"actor_mode":4},"cursor_after_acknowledgement":8,"next_kind":11,"reward":0,"bonus":0,"unprotect_installed_equipment":true,"unprotect_cargo_equipment":true,"price_reset_index":"slot_position","price_minimum_value_index":15,"price_maximum_value_index":17,"price_midpoint_rounding":"truncate_toward_zero"}
const SPANS := {"mode0_counts":[1554602,32],"mode0_events":[1555970,24],"mode1_counts":[1555258,32],"mode1_events":[1546650,40],"briefing_voice":[1560362,8],"completion_voices":[1562362,40],"radio_voices":[1563194,16],"radio_dispatch":[104514,4],"radio_declaration":[83574,176],"active_condition_dispatch":[686370,4],"active_condition":[685457,82],"dependency_dispatch":[686330,4],"dependency_condition":[685352,23],"scenery_getter":[535540,28],"active_getter":[540924,14],"friendly_getter":[535680,14],"next_dispatch":[871434,4],"next_mission_and_equipment":[860799,240],"installed_getter":[730042,10],"cargo_getter":[730052,10],"protection_setter":[-84714,10],"price_getter":[-84640,10],"price_setter":[-84576,10],"departure_equipment_gate":[437109,243],"item_table_load":[-228846,15],"item_constructor":[-84910,22],"item_price_initialization":[-84866,140],"ordinary_entry_dispatch":[138774,13],"ordinary_story_dispatch":[152039,247],"ordinary_story_flag":[121726,10],"special_side_mission_gate":[137141,73],"ordinary_story_tail":[230121,22],"early_campaign_predicate":[858140,16],"entry_selection_0":[143263,24],"entry_selection_1":[143646,24],"entry_selection_2":[144596,24],"entry_selection_3":[147008,24],"entry_selection_4":[149098,24],"entry_selection_5":[150245,31],"entry_selection_6":[150276,24],"entry_selection_7":[150300,20],"entry_selection_8":[150320,20],"entry_selection_9":[150340,20],"entry_selection_10":[150360,22],"entry_selection_11":[150382,22],"entry_selection_12":[150404,26]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, training: Dictionary, destruction: Dictionary, briefing: Dictionary, objective: Dictionary, dialogue: Dictionary, shared_story: Dictionary) -> String:
	if not data is Dictionary:return "Missing training story declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported training story declarations"
	if not Training.parameters(training) or not Destruction.parameters(destruction) or not Briefing.parameters(briefing) or not Objective.parameters(objective) or not SharedStory.parameters(shared_story):return "Training story lacks its encounter and shared dialogue context"
	if dialogue.get("campaign_cursor")!=0 or not Equal.equal_value(dialogue.get("timing"),VALUES.radio_timing) or not Voice.parameters(dialogue.get("voice")):return "Training radio lacks its source timing and voice context"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Training story lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid training story provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid training story extent: "+key
	return ""

static func radio(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.combat_training_story):return {}
	var shared: Dictionary=bindings.opening_dialogue
	if not Voice.parameters(shared.get("voice")):return {}
	var data: Dictionary=bindings.combat_training_story
	var voice: Dictionary=shared.voice.duplicate(true)
	voice.event_ids=data.radio_events.map(func(row):return int(row.voice_event_id))
	voice.text_ids=data.radio_events.map(func(row):return int(row.text_id))
	return {"campaign_cursor":7,"events":data.radio_events.duplicate(true),"timing":data.radio_timing.duplicate(true),"voice":voice}

static func briefing(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.combat_training_story) or not Briefing.parameters(bindings.mining_briefing):return {}
	var result: Dictionary=bindings.mining_briefing.duplicate(true)
	result.campaign_cursor=7;result.mission_kind=4
	result.events=bindings.combat_training_story.briefing_events.duplicate(true)
	result.key_token="#KEY_PRIMARY"
	return result

static func flight(bindings: RefCounted) -> Dictionary:
	if bindings==null or not parameters(bindings.combat_training_story) or not FirstFlight.parameters(bindings.first_flight) or not Training.parameters(bindings.combat_training):return {}
	var result: Dictionary=bindings.first_flight.duplicate(true)
	result.campaign_cursor=7;result.mission_kind=4;result.actor_count=4
	return result
