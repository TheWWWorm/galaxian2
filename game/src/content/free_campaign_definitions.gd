extends RefCounted
## Native support for the verified story states after the travel unlock.
const Visit=preload("res://src/content/suttnar_visit_definitions.gd")

static func supported(travel: Dictionary,cursor: Variant) -> bool:
	if not cursor is int or not travel.has("free_flight"):return false
	return cursor==int(travel.free_flight.campaign_cursor) or (Visit.parameters(travel.get("suttnar_visit")) and cursor==int(travel.suttnar_visit.next_cursor))

static func mission(travel: Dictionary,cursor: int) -> Dictionary:
	if not supported(travel,cursor):return {}
	if cursor==int(travel.free_flight.campaign_cursor):
		var rules: Dictionary=travel.alioth_return
		return {"kind":int(rules.next_kind),"station_id":int(rules.next_station_id),"reward":0,"bonus":0,"source_parameter":0}
	var result:={}
	for key in travel.suttnar_visit.next_mission:result[key]=int(travel.suttnar_visit.next_mission[key])
	return result

static func visit_at(travel: Dictionary,cursor: Variant,station_id: Variant) -> bool:
	return Visit.parameters(travel.get("suttnar_visit")) and cursor is int and cursor==int(travel.suttnar_visit.campaign_cursor) and station_id==int(travel.suttnar_visit.mission.station_id)

static func active_visit(travel: Dictionary,context: Dictionary) -> bool:
	return visit_at(travel,context.get("campaign_cursor"),context.get("station_id")) and context.get("system_id")==int(travel.suttnar_visit.system_id) and context.get("mission_kind")==int(travel.suttnar_visit.mission.kind) and context.get("mission_story")==true and context.get("mission_completed")==false
