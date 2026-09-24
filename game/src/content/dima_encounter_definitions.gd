extends RefCounted
## Selected Dima28 cast composition from the guarded Thynome declarations.
## The environment owner supplies its already-relocated portal position.
const Thynome=preload("res://src/content/thynome_expedition_definitions.gd")

static func selected(travel: Dictionary,context: Dictionary) -> bool:
	if not Thynome.coherent(travel):return false
	if not load("res://src/content/sahi_encounter_definitions.gd").coherent(travel):return false
	var mission: Dictionary=travel.thynome_expedition.mission28
	for key in ["campaign_cursor","system_id","station_id","kind"]:
		var field: String="mission_kind" if key=="kind" else key
		if not context.get(field) is int or context[field]!=int(mission[key]):return false
	if context.get("mission_story")!=true or context.get("mission_completed")!=false or context.get("mission_failed")!=false:return false
	return true

static func population(travel: Dictionary,context: Dictionary) -> Dictionary:
	if not selected(travel,context):return {}
	var candidate: Variant=context.get("portal_position")
	if not candidate is Vector3 or not candidate.is_finite():return {}
	var cast: Dictionary=travel.thynome_expedition.world28.cast
	var groups: Array=cast.groups
	var anchor: Vector3=candidate
	var data: Dictionary=travel.sahi_encounter.population.duplicate(true)
	data.waypoints=[[anchor.x,anchor.y,anchor.z]]
	data.actor_route_ids=[];data.actor_route_waypoint_indices=[]
	data.actors=[]
	for group in groups:
		for _index in int(group.count):
			data.actors.append({"actor_id":data.actors.size(),"actor_kind":int(group.actor_kind),
				"subtype":int(group.subtype),"hull_catalogue_id":int(group.hull_catalogue_id)})
	data.actor_count=data.actors.size();data.construction_order=range(data.actor_count)
	data.freighter_hull_divisor=int(groups[1].hull_scaling.divisor)
	data.freighter_cruise_enabled=bool(groups[1].cruise_enabled)
	data.freighter_cargo_cleared=bool(groups[1].generated_cargo_cleared_after_factory)
	data.dima={"target_memberships":cast.target_memberships.duplicate(true),
		"player_target_id":int(cast.player_target_id),"hull_scaling":groups[1].hull_scaling.duplicate(true)}
	return data
