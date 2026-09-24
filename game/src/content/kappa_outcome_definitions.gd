extends RefCounted
## Original rescue result and acknowledged failure exit.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"kappa_rescue_result","campaign_cursor":21,"station_id":55,"mission":{"kind":4,"station_id":55,"reward":0,"bonus":0,"source_parameter":0},"completion_first":true,"completion_hud_minimum_ms":5001,"failure_requires_completion_poll":false,"acknowledgement_required":true,"success":{"events":[{"speaker_id":1,"text_id":1861,"voice_event_id":286}],"next_cursor":22,"next_mission":{"kind":11,"station_id":55,"reward":0,"bonus":0,"source_parameter":0},"reward_credits":0},"failure":{"speaker_id":16,"text_ids":[381,308],"separator":"\n\n\n","voice_event_id":-1,"line_count":1,"continue_source_state":1,"reward_credits":0}}
const SPANS = {"kappa_outcome_poll_order":[377572,30],"kappa_outcome_completion_clock":[385853,59],"kappa_outcome_failure_modal":[388546,198],"kappa_outcome_modal_setup":[-693644,164],"kappa_outcome_failure_flag":[400478,20],"kappa_outcome_speaker":[-692286,137],"kappa_outcome_text_branch":[-691916,13],"kappa_outcome_failure_text":[-691516,310],"kappa_outcome_empty_text":[1815814,1],"kappa_outcome_newlines":[1682291,8],"kappa_outcome_count":[-686407,35],"kappa_outcome_no_auto_ack":[-686563,59],"kappa_outcome_input":[-685001,56],"kappa_outcome_final_line":[-686464,48],"kappa_outcome_exit":[351489,192],"kappa_outcome_runtime_reset":[880642,47],"kappa_outcome_success_event":[1547490,8],"kappa_outcome_return_factory":[861778,43],"kappa_outcome_voices":[1560154,12032]}

# Native composition.
const Rescue=preload("res://src/content/kappa_rescue_definitions.gd")
const Return=preload("res://src/content/kappa_return_definitions.gd")
const Lines=preload("res://src/content/dialogue_lines.gd")

const MAC_SPANS = {"kappa_outcome_poll_order":[378084,30],"kappa_outcome_completion_clock":[386369,59],"kappa_outcome_failure_modal":[389062,198],"kappa_outcome_modal_setup":[-699540,164],"kappa_outcome_failure_flag":[400994,20],"kappa_outcome_speaker":[-698182,137],"kappa_outcome_text_branch":[-697805,13],"kappa_outcome_failure_text":[-697405,310],"kappa_outcome_empty_text":[1792206,1],"kappa_outcome_newlines":[1657371,8],"kappa_outcome_count":[-692295,35],"kappa_outcome_no_auto_ack":[-692451,59],"kappa_outcome_input":[-690889,56],"kappa_outcome_final_line":[-692352,48],"kappa_outcome_exit":[351203,192],"kappa_outcome_runtime_reset":[881274,47],"kappa_outcome_success_event":[1522474,8],"kappa_outcome_return_factory":[862410,43],"kappa_outcome_voices":[1535218,12032]}
const MAC_VALUES = {"scope":"kappa_rescue_result","campaign_cursor":21,"station_id":55,"mission":{"kind":4,"station_id":55,"reward":0,"bonus":0,"source_parameter":0},"completion_first":true,"completion_hud_minimum_ms":5001,"failure_requires_completion_poll":false,"acknowledgement_required":true,"success":{"events":[{"speaker_id":1,"text_id":1875,"voice_event_id":286}],"next_cursor":22,"next_mission":{"kind":11,"station_id":55,"reward":0,"bonus":0,"source_parameter":0},"reward_credits":0},"failure":{"speaker_id":16,"text_ids":[381,308],"separator":"\n\n\n","voice_event_id":-1,"line_count":1,"continue_source_state":1,"reward_credits":0}}

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES) or Equal.equal_value(data,MAC_VALUES)

static func available(bindings: RefCounted) -> bool:
	return Rescue.available(bindings) and Return.available(bindings) and parameters(bindings.mido_travel.get("kappa_outcome"))

static func selected(bindings: RefCounted,cursor: Variant,mission: Variant) -> bool:
	return available(bindings) and cursor is int and cursor==int(VALUES.campaign_cursor) and Equal.equal_value(mission,VALUES.mission)

static func conversation(bindings: RefCounted,cursor: Variant,mission: Variant) -> Dictionary:
	if not selected(bindings,cursor,mission):return {}
	var data: Dictionary=bindings.mido_travel.kappa_outcome
	var result: Dictionary=data.success.duplicate(true)
	for key in ["campaign_cursor","station_id","mission","acknowledgement_required"]:result[key]=data[key]
	return result

static func failure_lines(bindings: RefCounted,library: RefCounted) -> Array:
	if not available(bindings):return []
	var data: Dictionary=bindings.mido_travel.kappa_outcome.failure
	var events:=[]
	for id in data.text_ids:events.append({"speaker_id":int(data.speaker_id),"text_id":int(id),"voice_event_id":int(data.voice_event_id)})
	var reader:=Lines.new();var parts:=reader.read(bindings,library,events)
	if parts.size()!=events.size():return []
	var line: Dictionary=parts[0].duplicate(true)
	for key in ["text","desktop_text"]:
		var texts:=PackedStringArray()
		for part in parts:texts.append(part[key])
		line[key]=String(data.separator).join(texts)
	return [line]
