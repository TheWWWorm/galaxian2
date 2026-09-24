extends RefCounted
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES:={"scope":"sahi_void_and_return","missions":{"25":{"campaign_cursor":25,"kind":156,"station_id":-1,"reward":0,"bonus":0,"source_parameter":0,"story":true,"briefing_events":[],"result_events":[{"speaker_id":6,"text_id":1911,"voice_event_id":310},{"speaker_id":0,"text_id":1912,"voice_event_id":311},{"speaker_id":6,"text_id":1913,"voice_event_id":312}]},"26":{"campaign_cursor":26,"kind":4,"station_id":48,"reward":0,"bonus":0,"source_parameter":0,"story":true,"briefing_events":[{"speaker_id":6,"text_id":1917,"voice_event_id":173},{"speaker_id":0,"text_id":1918,"voice_event_id":174},{"speaker_id":6,"text_id":1919,"voice_event_id":175}],"result_events":[{"speaker_id":6,"text_id":1920,"voice_event_id":313},{"speaker_id":0,"text_id":1921,"voice_event_id":314}]},"27":{"campaign_cursor":27,"kind":11,"station_id":10,"reward":0,"bonus":0,"source_parameter":0,"story":true,"briefing_events":[],"result_events":[{"speaker_id":6,"text_id":1922,"voice_event_id":315},{"speaker_id":0,"text_id":1923,"voice_event_id":316},{"speaker_id":17,"text_id":1924,"voice_event_id":318},{"speaker_id":6,"text_id":1925,"voice_event_id":319},{"speaker_id":0,"text_id":1926,"voice_event_id":320},{"speaker_id":6,"text_id":1927,"voice_event_id":321},{"speaker_id":0,"text_id":1928,"voice_event_id":322},{"speaker_id":6,"text_id":1929,"voice_event_id":323},{"speaker_id":0,"text_id":1930,"voice_event_id":324},{"speaker_id":6,"text_id":1931,"voice_event_id":325},{"speaker_id":0,"text_id":1932,"voice_event_id":317}]}},"void":{"campaign_cursor":25,"station_id":-1,"system_id":-1,"return_station_id":48,"return_system_id":9,"completion":{"kind":156,"elapsed_greater_than_ms":10000,"requires_not_landed":true},"radio":[{"speaker_id":0,"text_id":1914,"voice_event_id":513,"condition_kind":5,"condition_value":20000},{"speaker_id":6,"text_id":1915,"voice_event_id":514,"condition_kind":6,"condition_value":0},{"speaker_id":0,"text_id":1916,"voice_event_id":515,"condition_kind":6,"condition_value":1}],"population":{"count":3,"actor_kind":9,"hull_catalogue_id":8,"subtype":0,"sign_bound":2,"positive_sign_draw":1,"magnitude_offset":20000,"magnitude_bound":80000},"field":{"station_id":-1,"location_match":true,"center":[-30000,0,30000],"floating_debris":false},"sky":{"star_mesh_id":17852,"star_texture_id":10088,"sky_mesh_id":17810,"sky_texture_id":10075,"cubemap_id":12040},"station":{"environment_slot":0,"model_ids":[16443,16446,16449],"position":[0,0,0],"docking_available":false},"gate":{"environment_slot":2,"model_ids":[15000,15002,15001,15003],"position_bounds":[1,20000,50000],"position_offsets":[0,-10000,170000],"faces_origin":true,"player_entry":true},"absent_environment_slots":[1]},"pursuers":{"campaign_cursor":26,"station_id":48,"system_id":9,"count":2,"actor_kind":9,"hull_catalogue_id":8,"subtype":0,"forward_distance":8000.0,"axis_bound":1400,"axis_offset":-700,"completion_condition_kind":7,"completion_condition_value":2}}
const SPANS:={"post_sahi_cast25":[6906,376],"post_sahi_cast26":[7287,535],"post_sahi_world_selection":[-40533,507],"post_sahi_void_gate_placement":[-38236,287],"post_sahi_environment_selection":[-40026,1790],"post_sahi_world_fallback_entry":[-42555,49],"post_sahi_field_selection":[-35306,441],"post_sahi_no_floating_debris":[-32748,298],"post_sahi_void_station_models":[643528,223],"post_sahi_void_station_defaults":[851441,77],"post_sahi_gate_parts":[1551410,8],"post_sahi_pursuit_distance":[1550390,4],"post_sahi_mission25":[862576,102],"post_sahi_result25":[1522674,24],"post_sahi_mission26":[862688,55],"post_sahi_briefing26":[1531082,24],"post_sahi_result26":[1522698,16],"post_sahi_mission27":[862753,33],"post_sahi_result27":[1522714,88],"post_sahi_voice1911":[1536394,8],"post_sahi_voice1912":[1536402,8],"post_sahi_voice1913":[1536410,8],"post_sahi_voice1917":[1535298,8],"post_sahi_voice1918":[1535306,8],"post_sahi_voice1919":[1535314,8],"post_sahi_voice1920":[1536418,8],"post_sahi_voice1921":[1536426,8],"post_sahi_voice1922":[1536434,8],"post_sahi_voice1923":[1536442,8],"post_sahi_voice1924":[1536458,8],"post_sahi_voice1925":[1536466,8],"post_sahi_voice1926":[1536474,8],"post_sahi_voice1927":[1536482,8],"post_sahi_voice1928":[1536490,8],"post_sahi_voice1929":[1536498,8],"post_sahi_voice1930":[1536506,8],"post_sahi_voice1931":[1536514,8],"post_sahi_voice1932":[1536450,8],"post_sahi_voice1914":[1538018,8],"post_sahi_voice1915":[1538026,8],"post_sahi_voice1916":[1538034,8],"post_sahi_radio25":[85231,213]}

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("post_sahi",{}))

static func parameters(data: Dictionary) -> bool:return Equal.equal_value(data,VALUES)

static func mission(bindings: RefCounted,cursor: int) -> Dictionary:
	if not available(bindings):return {}
	if cursor in [29,30]:
		if not portal_available(bindings.mido_travel,cursor):return {}
		var source: Dictionary=bindings.mido_travel.void_probe.mission29 if cursor==29 else bindings.mido_travel.void_probe.mission30_declaration
		var result: Dictionary=source.duplicate(true)
		result.bonus=0;result.source_parameter=0
		if cursor==30:
			result.briefing_events=bindings.mido_travel.dima_return.result30.briefing_events.duplicate(true)
			result.result_events=bindings.mido_travel.dima_return.result30.result_events.duplicate(true)
		return result
	if not VALUES.missions.has(str(cursor)):return {}
	return bindings.mido_travel.post_sahi.missions[str(cursor)]

static func active_mission(bindings: RefCounted,cursor: int) -> Dictionary:
	var source:=mission(bindings,cursor)
	if source.is_empty():return {}
	var result:={}
	for key in ["kind","station_id","reward","bonus","source_parameter"]:result[key]=int(source[key])
	return result

static func location(cursor: int) -> Dictionary:
	if cursor in [25,29]:return {"station_id":-1,"system_id":-1}
	if cursor==26:return {"station_id":48,"system_id":9}
	if cursor==30:return {"station_id":91,"system_id":18}
	return {}

static func portal_available(travel: Dictionary,cursor: int) -> bool:
	if not parameters(travel.get("post_sahi",{})):return false
	if cursor in [25,26]:return true
	if cursor not in [29,30] or not load("res://src/content/thynome_expedition_definitions.gd").coherent(travel) or not load("res://src/content/void_probe_definitions.gd").parameters(travel.get("void_probe")):return false
	return cursor==29 or load("res://src/content/dima_return_definitions.gd").parameters(travel.get("dima_return"))

static func selected(travel: Dictionary,context: Dictionary) -> bool:
	var cursor: Variant=context.get("campaign_cursor")
	if not cursor is int or cursor not in [25,26,29] or not portal_available(travel,cursor):return false
	var where:=location(cursor)
	for key in ["station_id","system_id"]:
		if not context.get(key) is int or context[key]!=where[key]:return false
	var kind:=int(travel.void_probe.mission29.kind) if cursor==29 else int(VALUES.missions[str(cursor)].kind)
	return context.get("mission_kind")==kind and context.get("mission_story")==true and context.get("mission_failed")==false

static func population(travel: Dictionary,context: Dictionary) -> Dictionary:
	if not selected(travel,context):return {}
	var rules: Dictionary=travel.post_sahi["void"].population if context.campaign_cursor in [25,29] else travel.post_sahi.pursuers
	var result: Dictionary=travel.sahi_encounter.population.duplicate(true)
	result.actor_count=int(rules.count);result.construction_order=range(int(rules.count))
	result.waypoints=[[0,0,0]];result.actors=[];result.post_sahi=rules
	for id in int(rules.count):
		result.actors.append({"actor_id":id,"actor_kind":int(rules.actor_kind),"subtype":int(rules.subtype),"hull_catalogue_id":int(rules.hull_catalogue_id)})
	return result
