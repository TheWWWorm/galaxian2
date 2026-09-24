extends RefCounted
## Edition-local count for the source's ordinary scenery actor group. Positions,
## resource selection, bodies and later population changes are separate work.
const FirstFlight=preload("res://src/content/first_flight_definitions.gd")
const FullHold=preload("res://src/content/full_hold_flight_definitions.gd")
const Training=preload("res://src/content/combat_training_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const VoidCrystals=preload("res://src/content/void_crystal_definitions.gd")
const Definitions = preload("res://src/content/scenery_population_definitions.gd")
const Generator = preload("res://src/simulation/seeded_random.gd")
const Library = preload("res://src/content/library.gd")
const Arrival = preload("res://src/content/arrival_world_initialization_definitions.gd")
var error := ""
var _identity := {}
var _parameters := {}
var _arrival := {}
var _departure := {}
var _full_hold := {}
var _training := {}
var _travel := {}
var _void_crystal_field := {}
var _alioth := false
var _free := false
var _kappa := false
var _sahi := false

func clear() -> void:
	error=""
	_identity={}
	_parameters={}
	_arrival={}
	_departure={}
	_full_hold={}
	_training={}
	_travel={}
	_void_crystal_field={}
	_alioth=false
	_free=false
	_kappa=false
	_sahi=false

func configure(bindings: RefCounted) -> bool:
	clear()
	if bindings==null or not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id):
		return reject("Scenery population requires content and binding identities")
	if not Definitions.parameters(bindings.scenery_population):
		return reject("Source scenery population is unavailable")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_parameters=bindings.scenery_population.duplicate(true)
	_arrival=bindings.arrival_world_initialization.duplicate(true)
	_departure=bindings.first_flight.duplicate(true)
	_full_hold=bindings.full_hold_flight.duplicate(true)
	_training=bindings.combat_training.duplicate(true)
	_travel=bindings.mido_travel.duplicate(true)
	_void_crystal_field=void_crystal_field(bindings)
	_alioth=load("res://src/content/alioth_flight_definitions.gd").available(bindings)
	_free=load("res://src/content/free_flight_definitions.gd").available(bindings)
	_kappa=load("res://src/content/kappa_lifecycle_definitions.gd").available(bindings)
	_sahi=load("res://src/content/sahi_encounter_definitions.gd").coherent(bindings.mido_travel)
	return true

func for_station(station_id: Variant) -> Dictionary:
	error=""
	if _identity.is_empty(): return fail("Configure source scenery population first")
	if not station_id is int or station_id < -2147483648 or station_id > 2147483647:
		return fail("Scenery population requires a signed source station ID")
	var random := Generator.new()
	random.seed_from(station_id)
	var result := _identity.duplicate()
	result.station_id=station_id
	result.count=int(_parameters.count_base)+random.next_int(int(_parameters.count_bound))
	# This is the state immediately after counting. Source center selection draws
	# follow, then the generator is reseeded before actual scenery placement.
	result.random_state=random.snapshot()
	return result

func for_arrival(station_id: Variant, entry_conditions: Variant) -> Dictionary:
	error=""
	if not Arrival.parameters(_arrival):return fail("Rescue scenery center is unavailable; prepare current resource bindings")
	if station_id!=78 or not Arrival.entry_conditions(entry_conditions):return fail("Rescue scenery requires its retained station, ordinary location and no companions")
	return _ordinary_center(station_id,int(_arrival.campaign_cursor))

func for_departure(station_id: Variant, entry_conditions: Variant, cursor: int=2) -> Dictionary:
	error=""
	if not Arrival.parameters(_arrival):return fail("Ordinary scenery center is unavailable")
	var post=load("res://src/content/post_sahi_definitions.gd")
	if cursor in [25,29]:
		if not post.portal_available(_travel,cursor) or station_id!=-1 or entry_conditions!=load("res://src/content/story_encounter_definitions.gd").entry_conditions(cursor):return fail("Void scenery requires its selected special-location entry")
		var result:=for_station(station_id)
		if result.is_empty():return {}
		var field: Dictionary=_travel.post_sahi.void.field
		result.center=Vector3(field.center[0],field.center[1],field.center[2])
		result.campaign_cursor=cursor;result.count_random_state=result.random_state.duplicate(true)
		return result
	var data: Dictionary
	if cursor==2 and FirstFlight.parameters(_departure):data=_departure
	elif cursor==4 and FullHold.parameters(_full_hold):data=_full_hold
	elif cursor==7 and Training.parameters(_training):data=_training
	elif cursor==10 and Travel.parameters(_travel):data=_travel.arrival_flight if station_id==79 else _travel.departure_traffic
	elif cursor in [11,12] and station_id is int and not Travel.journey(_travel,cursor).is_empty() and not Travel.player_entry(_travel,int(station_id),cursor).is_empty():data={"station_id":station_id}
	elif cursor==16 and station_id==98 and _alioth:data={"station_id":station_id}
	elif cursor==21 and _kappa and station_id==int(_travel.kappa_rescue.station_id):data={"station_id":station_id}
	elif cursor==24 and _sahi and station_id==int(_travel.sahi_encounter.station_id):data={"station_id":station_id}
	elif cursor==26 and post.parameters(_travel.get("post_sahi",{})) and station_id==48:data={"station_id":station_id}
	elif cursor==28 and load("res://src/content/thynome_expedition_definitions.gd").coherent(_travel) and station_id==91:data={"station_id":station_id}
	elif load("res://src/content/free_campaign_definitions.gd").supported(_travel,cursor) and _free and station_id is int and not load("res://src/content/ordinary_world_definitions.gd").location(_travel,station_id).is_empty():data={"station_id":station_id}
	elif cursor==14 and station_id==79 and not Travel.player_entry(_travel,station_id,cursor).is_empty():data={"station_id":station_id}
	elif Travel.navigation_available(_travel,cursor) and station_id is int and Travel.navigation_stations(_travel,cursor,station_id).has(station_id):data={"station_id":station_id}
	else:return fail("This departure has no supported scenery center")
	if not station_id is int or station_id!=int(data.station_id) or not FirstFlight.entry_conditions(entry_conditions):return fail("Departure scenery requires its ordinary station and empty companion list")
	return _ordinary_center(station_id,cursor)

## Detached cursor33 scenery preparation. The caller must already have produced
## the selected sentinel and retained Void location; this grants no world entry.
func for_void_crystals(context: Variant) -> Dictionary:
	error=""
	if _identity.is_empty() or _void_crystal_field.is_empty():return fail("Void crystal scenery requires its source capability")
	if not context is Dictionary or not VoidCrystals.selected_void(_travel,context):return fail("Void crystal scenery requires the selected and retained Void sentinel")
	if not context.get("companions_empty") is bool or not context.companions_empty or not context.get("special_placement") is bool or context.special_placement:return fail("Void crystal scenery requires ordinary empty-companion placement")
	var result:=for_station(int(_void_crystal_field.station_seed))
	if result.is_empty():return {}
	result.center=Vector3(float(_void_crystal_field.center[0]),float(_void_crystal_field.center[1]),float(_void_crystal_field.center[2]))
	result.campaign_cursor=int(_travel.void_crystals.mission33.campaign_cursor)
	result.count_random_state=result.random_state.duplicate(true)
	return result

static func void_crystal_field(bindings: RefCounted) -> Dictionary:
	if bindings==null or not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id):return {}
	var travel: Variant=bindings.get("mido_travel")
	if not travel is Dictionary or not Travel.parameters(travel) or not VoidCrystals.parameters(travel.get("void_crystals")):
		return {}
	if not VoidCrystals.shared_field(bindings.scenery_population,bindings.scenery_resources):return {}
	return travel.void_crystals.field.duplicate(true)

func _ordinary_center(station_id: int, cursor: int) -> Dictionary:
	var result:=for_station(station_id)
	if result.is_empty():return {}
	var random:=Generator.new()
	if not random.restore(result.random_state):return fail(random.error)
	result.count_random_state=result.random_state.duplicate(true)
	var center:=Vector3.ZERO
	for axis in 3:center[axis]=int(_arrival.center_offsets[axis])+random.next_int(int(_arrival.center_random_bound))
	result.center=center;result.random_state=random.snapshot()
	result.campaign_cursor=cursor
	return result

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	error=message
	return {}
