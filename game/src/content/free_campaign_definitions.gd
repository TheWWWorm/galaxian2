extends RefCounted
## Native support for the verified story states after the travel unlock.
const Visit=preload("res://src/content/suttnar_visit_definitions.gd")
const Preparation=preload("res://src/content/kappa_preparation_definitions.gd")
const Return=preload("res://src/content/kappa_return_definitions.gd")
const Outcome=preload("res://src/content/kappa_outcome_definitions.gd")
const Departure=preload("res://src/content/kappa_departure_definitions.gd")
const Post=preload("res://src/content/post_sahi_definitions.gd")
const Thynome=preload("res://src/content/thynome_expedition_definitions.gd")
const DimaReturn=preload("res://src/content/dima_return_definitions.gd")
const PostProbe=preload("res://src/content/post_probe_visit_definitions.gd")

static func result_rules(bindings: RefCounted,cursor: Variant,mission: Variant) -> Dictionary:
	return Outcome.conversation(bindings,cursor,mission)

static func result_presentation(bindings: RefCounted,cursor: Variant,mission: Variant,failed:=false) -> Dictionary:
	var rules:=result_rules(bindings,cursor,mission)
	if rules.is_empty():return {}
	var presentation: Dictionary=load("res://src/content/full_hold_story_definitions.gd").briefing(bindings,2)
	if presentation.is_empty():return {}
	presentation.campaign_cursor=int(cursor);presentation.mission_kind=int(rules.mission.kind)
	presentation.events=rules.events.duplicate(true)
	if failed:
		var failure: Dictionary=bindings.mido_travel.kappa_outcome.failure
		presentation.events=[{"speaker_id":int(failure.speaker_id),"text_id":int(failure.text_ids[0]),"voice_event_id":int(failure.voice_event_id)}]
	return presentation

## Preparing original dialogue does not authorize a campaign departure.
static func dialogue_rules(bindings: RefCounted,cursor: Variant,mission: Variant,station_only:=false) -> Dictionary:
	if station_only:
		if Preparation.selected(bindings,cursor,mission,"fitting"):return bindings.mido_travel.kappa_preparation.fitting.duplicate(true)
		if bindings!=null and expedition_available(bindings.mido_travel) and cursor==27:return Thynome.conversation(bindings,cursor,mission)
		if bindings!=null and post_probe_available(bindings.mido_travel) and cursor==31:return PostProbe.conversation(bindings,cursor,mission)
		return Return.conversation(bindings,cursor,mission)
	if Visit.selected(bindings,cursor,mission):return bindings.mido_travel.suttnar_visit.duplicate(true)
	if Preparation.selected(bindings,cursor,mission,"visit"):return bindings.mido_travel.kappa_preparation.visit.duplicate(true)
	if bindings!=null and expedition_available(bindings.mido_travel) and cursor==30:return DimaReturn.conversation(bindings,cursor,mission)
	return {}

static func dialogue_presentation(bindings: RefCounted,cursor: Variant,mission: Variant,station_only:=false) -> Dictionary:
	var rules:=dialogue_rules(bindings,cursor,mission,station_only)
	if rules.is_empty():return {}
	var presentation: Dictionary=load("res://src/content/full_hold_story_definitions.gd").briefing(bindings,2)
	if presentation.is_empty():return {}
	presentation.campaign_cursor=int(cursor);presentation.mission_kind=int(rules.mission.kind)
	presentation.events=rules.events.duplicate(true)
	return presentation

static func supported(travel: Dictionary,cursor: Variant) -> bool:
	if not cursor is int or not travel.has("free_flight"):return false
	if cursor==27:return Post.parameters(travel.get("post_sahi",{}))
	if cursor in [28,30,31]:return expedition_available(travel)
	if cursor==32:return post_probe_available(travel)
	return cursor==int(travel.free_flight.campaign_cursor) or (Visit.parameters(travel.get("suttnar_visit")) and cursor==int(travel.suttnar_visit.next_cursor)) or (chapter_available(travel) and cursor in [20,21,22,23,24])

static func chapter_available(travel: Dictionary) -> bool:
	return Departure.parameters(travel.get("kappa_departure")) and Preparation.parameters(travel.get("kappa_preparation")) and Return.parameters(travel.get("kappa_return")) and Outcome.parameters(travel.get("kappa_outcome"))

static func expedition_available(travel: Dictionary) -> bool:
	return Post.portal_available(travel,30)

static func post_probe_available(travel: Dictionary) -> bool:
	return expedition_available(travel) and PostProbe.parameters(travel.get("post_probe_visits"))

static func mission(travel: Dictionary,cursor: int) -> Dictionary:
	if not supported(travel,cursor):return {}
	if cursor==28:return Thynome.mission_values(travel.thynome_expedition.mission28)
	if cursor==30:
		var result:={}
		for key in ["kind","station_id","reward"]:result[key]=int(travel.void_probe.mission30_declaration[key])
		result.bonus=0;result.source_parameter=0
		return result
	if cursor==31:return DimaReturn.next_mission(travel.dima_return)
	if cursor==32:return PostProbe.mission_values(travel.post_probe_visits.missions["32"])
	if cursor==27:
		var result:={}
		for key in ["kind","station_id","reward","bonus","source_parameter"]:result[key]=int(travel.post_sahi.missions["27"][key])
		return result
	if cursor==int(travel.free_flight.campaign_cursor):
		var rules: Dictionary=travel.alioth_return
		return {"kind":int(rules.next_kind),"station_id":int(rules.next_station_id),"reward":0,"bonus":0,"source_parameter":0}
	if chapter_available(travel):
		for rules in [travel.kappa_preparation.visit,travel.kappa_preparation.fitting]+travel.kappa_return.conversations:
			if cursor==int(rules.campaign_cursor):return _mission(rules.mission)
			if cursor==int(rules.next_cursor):return _mission(rules.next_mission)
	var result:={}
	for key in travel.suttnar_visit.next_mission:result[key]=int(travel.suttnar_visit.next_mission[key])
	return result

static func visit_at(travel: Dictionary,cursor: Variant,station_id: Variant) -> bool:
	if cursor==30 and expedition_available(travel):return station_id==int(travel.void_probe.mission30_declaration.station_id)
	if Visit.parameters(travel.get("suttnar_visit")) and cursor is int and cursor==int(travel.suttnar_visit.campaign_cursor) and station_id==int(travel.suttnar_visit.mission.station_id):return true
	return chapter_available(travel) and cursor is int and cursor==int(travel.kappa_preparation.visit.campaign_cursor) and station_id==int(travel.kappa_preparation.visit.mission.station_id)

static func active_visit(travel: Dictionary,context: Dictionary) -> bool:
	return visit_at(travel,context.get("campaign_cursor"),context.get("station_id")) and empty_story(travel,context)

## These selected story scenes share the original actor-free cast tail. Their
## clocks/dialogue still belong to the visit or station conversation owners.
static func ordinary_story_at(travel: Dictionary,cursor: Variant,station_id: Variant) -> bool:
	if visit_at(travel,cursor,station_id):return true
	if cursor==27 and expedition_available(travel):return station_id==int(travel.post_sahi.missions["27"].station_id)
	if cursor==31 and post_probe_available(travel):return station_id==int(travel.post_probe_visits.missions["31"].station_id)
	if not chapter_available(travel) or cursor not in [20,22,23]:return false
	return station_id==mission(travel,cursor).get("station_id")

static func empty_story(travel: Dictionary,context: Dictionary) -> bool:
	if not ordinary_story_at(travel,context.get("campaign_cursor"),context.get("station_id")) or context.get("mission_story")!=true or context.get("mission_completed")!=false:return false
	var expected:=mission(travel,context.campaign_cursor)
	var system:=18 if context.campaign_cursor==30 else 6 if context.campaign_cursor in [23,27] else 11
	if context.campaign_cursor==31:system=int(travel.post_probe_visits.missions["31"].system_id)
	return context.get("system_id")==system and context.get("mission_kind")==expected.get("kind")

static func rescue_at(travel: Dictionary,cursor: Variant,station_id: Variant) -> bool:
	return chapter_available(travel) and cursor==int(travel.kappa_departure.rescue_cursor) and station_id==int(travel.kappa_preparation.fitting.next_mission.station_id)

static func sahi_at(travel: Dictionary,cursor: Variant,station_id: Variant) -> bool:
	if cursor==28 and expedition_available(travel):return station_id==int(travel.thynome_expedition.mission28.station_id)
	return Post.parameters(travel.get("post_sahi",{})) and load("res://src/content/sahi_encounter_definitions.gd").coherent(travel) and cursor==int(travel.sahi_visit.campaign_cursor) and station_id==int(travel.sahi_visit.mission.station_id)

static func _mission(source: Dictionary) -> Dictionary:
	var result:={}
	for key in source:result[key]=int(source[key])
	return result
