extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Verified ordinary hits and source freighter boxes. No travel permission.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Ambient=preload("res://src/content/ambient_population_definitions.gd")
const FreeTraffic=preload("res://src/content/free_traffic_definitions.gd")
const ControlRules=preload("res://src/content/combat_training_control_definitions.gd")
const VALUES = {"scope":"early_mido_ambient_combat","campaign_cursor":11,"station_id":79,"system_id":15,"actor_kind":3,"supported_ranks":[0,1,2],"initial_actor_mode":0,"initial_active":true,"freighter":{"subtype":1,"hull_catalogue_id":15,"hull_multiplier":5,"point_geometry":true,"boxes":[{"offset":[0,-199,4708],"half_extents":[490,765,620]},{"offset":[0,-14,-98],"half_extents":[2250,702.5,4430]}]}}
const SPANS = {"factory":[77944,3478],"base_actor":[-81548,948],"statistics":[534164,980],"freighter_constructor":[631244,1108],"normal_hit":[538936,1846],"point_wrapper":[-76580,26],"freighter_point":[638832,218],"box_constructor":[-710254,138],"box_point":[-710024,122],"freighter_position":[633042,280],"projectile_point_selection":[-181241,192],"freighter_hostility":[634203,154],"box_values":[1575362,32],"half_extent_scale":[1544586,4]}

const MAC_SPANS = {"factory":[77944,3478],"base_actor":[-81548,948],"statistics":[534700,980],"freighter_constructor":[631792,1108],"normal_hit":[539472,1846],"point_wrapper":[-76580,26],"freighter_point":[639380,218],"box_constructor":[-716150,138],"box_point":[-715920,122],"freighter_position":[633590,280],"projectile_point_selection":[-181733,192],"freighter_hostility":[634751,154],"box_values":[1550426,32],"half_extent_scale":[1519570,4]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant,source_bytes: int,arch: String,arrival: Dictionary,population: Dictionary) -> String:
	if not data is Dictionary:return "Missing ambient combat declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Ambient.parameters(population):return "Unsupported ambient combat declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Ambient combat lacks its source anchor"
	if not Layouts.matches(data.provenance,int(origin.offset),source_bytes,[SPANS,MAC_SPANS]):return "Invalid ambient combat source layout"
	return ""

static func population(bindings: RefCounted,packet: Dictionary,rank: Variant,difficulty: Variant) -> Dictionary:
	if bindings==null or not parameters(bindings.ambient_combat) or not Ambient.parameters(bindings.ambient_population) or not ControlRules.parameters(bindings.combat_training_control):return {}
	if packet.has("free_context"):
		var ordinary:=FreeTraffic.population(bindings,packet,rank,difficulty)
		return _common_scalars(bindings,ordinary) if not ordinary.is_empty() else {}
	var rules:=for_context(bindings,packet.get("campaign_cursor"),packet.get("population",{}).get("station_id"))
	if rules.is_empty():return {}
	if not rank is int or not rules.supported_ranks.any(func(value):return int(value)==rank):return {}
	if (not difficulty is int and not difficulty is float) or not bindings.ambient_population.supported_difficulties.any(func(value):return float(value)==float(difficulty)):return {}
	for key in ["base_content_id","binding_id"]:
		if packet.get(key)!=bindings.get(key):return {}
	if packet.get("campaign_cursor")!=int(rules.campaign_cursor):return {}
	var source: Variant=packet.get("population")
	var actors: Variant=packet.get("actors")
	if not source is Dictionary or not source.get("groups") is Dictionary or not actors is Array or actors.is_empty() or actors.size()>Ambient.maximum_actor_count(bindings.ambient_population,bindings.mido_travel.departure_traffic):return {}
	for key in ["campaign_cursor","station_id","system_id"]:
		if source.get(key)!=int(rules[key]):return {}
	var count:=0
	for role in bindings.ambient_population.group_order:
		var n: Variant=source.groups.get(role)
		if not n is int or n<0 or n>actors.size():return {}
		for i in n:
			if count>=actors.size():return {}
			var actor: Variant=actors[count]
			if not actor is Dictionary or actor.get("actor_id")!=count or actor.get("actor_kind")!=int(rules.actor_kind) or actor.get("population_group")!=role:return {}
			if role=="freighter":
				if actor.get("subtype")!=int(rules.freighter.subtype) or actor.get("hull_catalogue_id")!=int(rules.freighter.hull_catalogue_id) or actor.get("world_flag")!=true or not Ambient.assembly_matches(bindings.ambient_population,actor.get("assembly")):return {}
			elif actor.get("subtype")!=0 or not bindings.mido_travel.departure_traffic.hull_candidates.any(func(value):return int(value)==actor.get("hull_catalogue_id")):return {}
			count+=1
	if count!=actors.size() or source.get("actor_count")!=count:return {}
	var data: Dictionary=rules.duplicate(true)
	data.actor_count=count
	return _common_scalars(bindings,data)

static func _common_scalars(bindings: RefCounted,data: Dictionary) -> Dictionary:
	for key in ["rank_base","rank_multiplier","cursor_multiplier","difficulty_offset","percentage_scale","engagement_half_extent","initial_model_draw_enabled","initial_node_draw_requested","initial_engine_draw_enabled"]:
		data[key]=bindings.combat_training_control[key]
	for key in ["initial_hostile","friendly","initial_actor_targeting_blocked","initial_statistics_targeting_blocked"]:
		data[key]=bindings.mido_travel.traffic_control[key]
	return data

static func live_population(bindings: RefCounted, combat: Dictionary) -> bool:
	if combat.has("free_context"):return load("res://src/content/free_lifecycle_definitions.gd").live_population(bindings,combat)
	if bindings==null or not parameters(bindings.ambient_combat) or not Ambient.parameters(bindings.ambient_population):return false
	var rules:=for_context(bindings,combat.get("campaign_cursor"),combat.get("provocation",{}).get("station_id"))
	if rules.is_empty():return false
	for key in ["base_content_id","binding_id"]:
		if combat.get(key)!=bindings.get(key):return false
	if combat.get("campaign_cursor")!=int(rules.campaign_cursor) or combat.get("provocation",{}).get("station_id")!=int(rules.station_id):return false
	var actors: Variant=combat.get("actors")
	if not actors is Array or actors.is_empty() or actors.size()>Ambient.maximum_actor_count(bindings.ambient_population,bindings.mido_travel.departure_traffic):return false
	var previous:=-1
	for id in actors.size():
		var actor: Variant=actors[id]
		if not actor is Dictionary or actor.get("actor_id")!=id or actor.get("actor_kind")!=int(rules.actor_kind) or actor.get("ambient_traffic")!=true:return false
		var group: int=bindings.ambient_population.group_order.find(actor.get("population_group"))
		if group<previous or group<0:return false
		previous=group
		if actor.population_group=="freighter":
			if actor.get("subtype")!=int(rules.freighter.subtype) or actor.get("hull_catalogue_id")!=int(rules.freighter.hull_catalogue_id):return false
		elif actor.get("subtype")!=0 or not bindings.mido_travel.departure_traffic.hull_candidates.any(func(value):return int(value)==actor.get("hull_catalogue_id")):return false
	return true

static func for_context(bindings: RefCounted,cursor: Variant,station_id: Variant=null) -> Dictionary:
	if bindings==null or not parameters(bindings.ambient_combat) or not cursor is int:return {}
	for context in Ambient.contexts(bindings):
		if not context.mixed or context.campaign_cursor!=cursor or (station_id!=null and context.station_id!=station_id):continue
		var result: Dictionary=bindings.ambient_combat.duplicate(true)
		result.campaign_cursor=cursor;result.station_id=int(context.station_id)
		return result
	return {}
