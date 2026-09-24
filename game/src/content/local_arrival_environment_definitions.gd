extends RefCounted
## Source planet sizing and local arrival selection.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"augmenta_local_arrival_environment","planet_sizes":{"initial_bound":20000,"initial_add":20000,"scale":1.52587890625e-05,"replacement_groups":[{"types":[6,11,12,17],"bound":15000,"add":35000},{"types":[9,16],"bound":13000,"add":32500}]},"arrival":{"cache_index":1,"system_station_array":1,"planet_index_offset":1,"planet_multiplier":4.0,"fallback_planet_position":[0.0,0.0,25000.0],"face_origin":true,"up":[0.0,1.0,0.0],"gate_keeps_initial_heading":true,"gate_object_index":2}}
const SPANS = {"local_arrival_planet_initial":[843293,157],"local_arrival_planet_sizes":[842473,103],"local_arrival_special_planet":[872426,80],"local_arrival_planet_type":[851424,10],"local_arrival_pose_selection":[-43078,586],"local_arrival_cache_getter":[855368,14],"local_arrival_station_list":[735294,10],"local_arrival_list_constructor":[734132,236],"local_arrival_list_loader":[-673478,1100],"local_arrival_face_origin":[-723998,480],"local_arrival_planet_scale":[1575014,4],"local_arrival_distance_scale":[1575050,4]}

# Native composition.
const SUPPORTED_TYPES=[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19]
const MAC_SPANS = {"local_arrival_planet_initial":[843925,157],"local_arrival_planet_sizes":[843105,103],"local_arrival_special_planet":[873058,80],"local_arrival_planet_type":[852056,10],"local_arrival_pose_selection":[-43078,586],"local_arrival_cache_getter":[856000,14],"local_arrival_station_list":[735926,10],"local_arrival_list_constructor":[734764,236],"local_arrival_list_loader":[-679366,1100],"local_arrival_face_origin":[-729894,480],"local_arrival_planet_scale":[1550078,4],"local_arrival_distance_scale":[1550114,4]}

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.mido_travel.get("local_arrival_environment")) and load("res://src/content/gate_environment_definitions.gd").available(bindings)

static func location_supported(bindings: RefCounted,catalogues: RefCounted,station_id: int,cursor: int) -> bool:
	if not available(bindings) or catalogues==null or catalogues.content_id!=bindings.base_content_id:return false
	var data: Dictionary=bindings.mido_travel
	var story_system: int=9 if cursor==26 and station_id==48 and load("res://src/content/post_sahi_definitions.gd").available(bindings) else 18 if cursor==28 and station_id==91 and load("res://src/content/thynome_expedition_definitions.gd").available(bindings) else -1
	if story_system>=0:
		if station_id>=catalogues.tables.stations.size():return false
		var station: Dictionary=catalogues.tables.stations[station_id]
		return station.system_id==story_system and station.planet_type in SUPPORTED_TYPES
	if not load("res://src/content/free_campaign_definitions.gd").supported(data,cursor):return false
	var world: Dictionary=load("res://src/content/ordinary_world_definitions.gd").catalogue_location(bindings,catalogues,station_id)
	return not world.is_empty() and world.planet_type in SUPPORTED_TYPES
