extends RefCounted
## Complete ordinary target membership for verified opening and training worlds.
## Unknown equipment groups and changed source populations remain unsupported.
const Opening = preload("res://src/content/opening_sky_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Vehicle = preload("res://src/content/vehicle_definitions.gd")
const Loadout = preload("res://src/simulation/opening_loadout.gd")
const Actors = preload("res://src/simulation/opening_actor_state.gd")
const Population = preload("res://src/simulation/scenery_population.gd")
const Ores = preload("res://src/simulation/scenery_ores.gd")
const Field = preload("res://src/simulation/scenery_field.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Training=preload("res://src/content/combat_training_weapon_definitions.gd")
const REQUIRED_EQUIPMENT_TYPE := 33
var error := ""
var _state := {}
var _actors := []
var _scenery := []

func configure(bindings: RefCounted, catalogues: RefCounted, opening_field: Dictionary) -> bool:
	clear()
	if bindings==null or catalogues==null or not Opening.parameters(bindings.opening_sky):
		return reject("Target inventory requires the verified fresh opening context")
	if not Vehicle.valid_parameters(bindings.vehicle_response):
		return reject("Target inventory requires the source installed equipment type schema")
	var loadout := Loadout.new()
	if not loadout.configure(bindings,catalogues,bindings.base_content_id):return reject(loadout.error)
	var source := loadout.snapshot()
	var actors := Actors.new()
	if not actors.configure(bindings,catalogues,bindings.base_content_id):return reject(actors.error)
	var population := Population.new()
	if not population.configure(bindings):return reject(population.error)
	var count: Dictionary = population.for_station(source.station_id)
	if count.is_empty():return reject(population.error)
	count.center=Vector3.ZERO
	return _configure_source(bindings,catalogues,source,actors.snapshot().actors,opening_field,count)

func configure_combat_training(bindings: RefCounted, catalogues: RefCounted, player: RefCounted, scenery: RefCounted) -> bool:
	clear()
	# Scenery also owns primary contact staging; avoid a preload cycle through
	# its primary owner while still requiring the native scenery implementation.
	if bindings==null or not player is Player or scenery==null or scenery.get_script()==null or scenery.get_script().resource_path!="res://src/simulation/opening_scenery.gd" or not Training.parameters(bindings.combat_training_weapons):return reject("Training targets require the native equipped player and scenery")
	var source: Dictionary=player.loadout();var field: Dictionary=scenery.snapshot()
	if source.get("campaign_cursor")!=7 or source.get("binding_id")!=bindings.binding_id or source.get("base_content_id")!=bindings.base_content_id:return reject("Training target equipment has a different identity")
	var world: RefCounted=scenery.world_initialization_owner()
	if world==null or world.snapshot().get("campaign_cursor")!=7:return reject("Training targets require completed world construction")
	var population:=Population.new()
	if not population.configure(bindings):return reject(population.error)
	var count:=population.for_departure(source.station_id,world.snapshot().entry_conditions,7)
	if count.is_empty():return reject(population.error)
	return _configure_source(bindings,catalogues,source,world.snapshot().npc_construction.actors,field,count)

func _configure_source(bindings: RefCounted, catalogues: RefCounted, source: Dictionary, actor_rows: Array, opening_field: Dictionary, count: Dictionary) -> bool:
	if catalogues==null or catalogues.content_id!=bindings.base_content_id or not Vehicle.valid_parameters(bindings.vehicle_response):return reject("Target inventory requires matching equipment type declarations")
	var type_index := int(bindings.vehicle_response.item_type_value_index)
	for id in source.equipment_ids:
		var values: Variant = catalogues.tables.items[id].arrays[2]
		if values.size()<=type_index or not Numbers.integer(values[type_index],0,65535):
			return reject("Opening equipment has no supported source type")
		if int(values[type_index])==REQUIRED_EQUIPMENT_TYPE:
			return reject("Opening equipment requires an unsupported additional target group")
	for key in ["base_content_id","binding_id","station_id","system_id"]:
		if not exact_value(opening_field.get(key),source[key]):return reject("Opening target field has a different identity or location")
	if not opening_field.get("center") is Vector3 or opening_field.center!=count.center:
		return reject("Ordinary targets require the source scenery center")
	var rows: Variant = opening_field.get("objects")
	if not rows is Array or rows.size()!=count.count:
		return reject("Opening target scenery count differs from its source population")
	var large_count: Variant = opening_field.get("large_count")
	if not large_count is int or large_count<Field.LARGE_COUNT_BASE or large_count>=Field.LARGE_COUNT_BASE+Field.LARGE_COUNT_BOUND:
		return reject("Opening target scenery has an invalid size-class boundary")
	var ores := Ores.new()
	if not ores.configure(bindings,catalogues,source.station_id,false,false,int(source.get("campaign_cursor",0))):return reject(ores.error)
	var possible_ores := {}
	var ore_rows: Array = ores.snapshot().rows
	for index in int(bindings.scenery_resources.sample_rows):
		var ore: Dictionary = ore_rows[index]
		if ore.weight>0 and ores.accepted_id(ore.item_id):possible_ores[ore.item_id]=true
	var variant := 2 if source.system_id==22 else 0
	var model_id := int(bindings.scenery_resources.model_ids[variant])
	var scenery := []
	var indices := []
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary or not row.get("index") is int or row.index!=index:
			return reject("Opening scenery targets must retain source array order")
		if not row.get("model_variant") is int or row.model_variant!=variant or not row.get("model_id") is int or row.model_id!=model_id:
			return reject("Opening scenery target model differs from its fresh source variant")
		if not row.get("item_id") is int or not possible_ores.has(row.item_id):
			return reject("Opening scenery target ore is outside its source population")
		if not row.get("large") is bool or row.large!=(index<large_count):
			return reject("Opening scenery target size classes are out of order")
		if not row.get("position") is Vector3 or not row.position.is_finite():
			return reject("Opening scenery target position is unavailable")
		var half_width := float(Field.LARGE_WIDTH if row.large else Field.SMALL_WIDTH)*0.5
		for axis in 3:
			if row.position[axis]<count.center[axis]-half_width or row.position[axis]>=count.center[axis]+half_width:
				return reject("Opening scenery target lies outside its source field")
		var minimum_scale := Field.f32(float(120 if row.large else 30)*Field.f32(0.01))
		var maximum_scale := Field.f32(float(219 if row.large else 99)*Field.f32(0.01))
		if not row.get("scale") is float or not is_finite(row.scale) or row.scale!=Field.f32(row.scale) or row.scale<minimum_scale or row.scale>maximum_scale:
			return reject("Opening scenery target scale is outside its source size class")
		scenery.append({"index":index,"model_id":model_id,"item_id":row.item_id,
			"scale":row.scale,"large":row.large,"position":row.position})
		indices.append(index)
	var npc_ids := []
	var cast:=[]
	for actor in actor_rows:
		var model: String=bindings.resolve_ship_model(int(actor.hull_catalogue_id))
		if model.is_empty():return reject(bindings.error)
		npc_ids.append(actor.actor_id)
		cast.append({"actor_id":actor.actor_id,"actor_kind":actor.actor_kind,
			"hull_catalogue_id":actor.hull_catalogue_id,"hull_resource":model})
	var canonical := {}
	for key in ["base_content_id","binding_id","ship_id","slots","equipment_ids"]:canonical[key]=source[key]
	if source.has("campaign_cursor"):canonical.campaign_cursor=source.campaign_cursor
	_state={"base_content_id":source.base_content_id,"binding_id":source.binding_id,
		"station_id":source.station_id,"system_id":source.system_id,"ship_id":source.ship_id,
		"equipment_ids":source.equipment_ids.duplicate(),"npc_ids":npc_ids,"scenery_indices":indices,
		"third_group_absence":"missing_equipment_type","required_equipment_type":REQUIRED_EQUIPMENT_TYPE,
		"loadout":canonical.duplicate(true)}
	_actors=cast;_scenery=scenery
	return true

func validate_loadout(loadout: Dictionary) -> bool:
	error=""
	if _state.is_empty():return reject("Configure fresh opening targets before validating equipment")
	for key in _state.loadout:
		if not exact_value(loadout.get(key),_state.loadout[key]):
			return reject("Current equipment differs from the verified fresh opening loadout")
	return true

func validate_owners(combat: Dictionary, bodies: Dictionary) -> bool:
	error=""
	if _state.is_empty():return reject("Configure fresh opening targets before validating owners")
	for owner in [combat,bodies]:
		for key in ["base_content_id","binding_id"]:
			if owner.get(key)!=_state[key]:return reject("Target owner belongs to another content identity")
	var actors: Variant = combat.get("actors")
	var scenery: Variant = bodies.get("objects")
	if not actors is Array or actors.size()!=_actors.size() or not scenery is Array or scenery.size()!=_scenery.size():
		return reject("Target owner omits or adds source targets")
	for index in actors.size():
		var actor: Variant = actors[index]
		if not actor is Dictionary:return reject("Invalid target actor record")
		for key in ["actor_id","hull_catalogue_id","hull_resource","actor_kind"]:
			if not exact_value(actor.get(key),_actors[index][key]):return reject("Target actor identity or source order changed")
		for key in ["base_content_id","binding_id"]:
			if actor.get(key)!=_state[key]:return reject("Target actor belongs to another content identity")
	for index in scenery.size():
		var row: Variant = scenery[index]
		if not row is Dictionary:return reject("Invalid scenery target record")
		for key in _scenery[index]:
			if not exact_value(row.get(key),_scenery[index][key]):return reject("Scenery target identity, order or placement changed")
	return true

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func clear() -> void:
	error="";_state={};_actors=[];_scenery=[]

static func exact_value(left: Variant, right: Variant) -> bool:
	if typeof(left)!=typeof(right):return false
	if left is Array:
		if left.size()!=right.size():return false
		for index in left.size():
			if not exact_value(left[index],right[index]):return false
		return true
	if left is Dictionary:
		if left.size()!=right.size():return false
		for key in left:
			if not right.has(key) or not exact_value(left[key],right[key]):return false
		return true
	return left==right

func reject(message: String) -> bool:
	error=message;return false
