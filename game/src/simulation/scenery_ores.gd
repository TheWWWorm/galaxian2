extends RefCounted
## Native catalogue-derived ore availability and ordered sampling. The scene owner
## supplies explicit campaign conditions and interleaves the returned RNG state
## with placement/scale/rotation draws. This component never seeds that stream.
const Definitions = preload("res://src/content/scenery_resource_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Generator = preload("res://src/simulation/seeded_random.gd")
const MAX_ATTEMPTS := 100000
var error := ""
var _identity := {}
var _parameters := {}
var _rows: Array = []
var _location_match := false
var _station_id := -1

func clear() -> void:
	error="";_identity={};_parameters={};_rows=[];_location_match=false;_station_id=-1

func configure(bindings: RefCounted, catalogues: RefCounted, station_id: Variant, location_match: Variant, special_ore_flag: Variant, campaign_cursor: Variant) -> bool:
	clear()
	if bindings==null or catalogues==null or not Library.valid_hash(bindings.base_content_id) or bindings.base_content_id!=catalogues.content_id or not Library.valid_hash(bindings.binding_id):return reject("Scenery ores require matching content and binding identities")
	var data: Dictionary = bindings.scenery_resources
	if not Definitions.parameters(data):return reject("Source scenery resources are unavailable")
	if not location_match is bool or not special_ore_flag is bool or not campaign_cursor is int or campaign_cursor<0 or campaign_cursor>2147483647:return reject("Scenery ores require explicit source campaign conditions")
	var stations: Variant = catalogues.tables.get("stations")
	var systems: Variant = catalogues.tables.get("systems")
	var items: Variant = catalogues.tables.get("items")
	if not stations is Array or not systems is Array or not items is Array or not station_id is int or station_id<0 or station_id>=stations.size():return reject("Scenery station is outside its catalogue")
	var system_id: Variant = stations[station_id].get("system_id")
	if not Numbers.integer(system_id,0,systems.size()-1):return reject("Scenery station system is unavailable")
	var here: Variant = map_position(systems[int(system_id)],data)
	if here==null:return reject("Scenery system map position is unavailable")
	var rows := []
	for identifier in data.ore_item_ids:
		var id := int(identifier)
		if id>=items.size():return reject("Scenery ore is outside its catalogue")
		var weight := 0
		if not location_match:
			var arrays: Variant = items[id].get("arrays")
			if not arrays is Array or arrays.size()!=3 or not (arrays[2] is Array or arrays[2] is PackedInt32Array) or arrays[2].size()<=int(data.item_origin_index):return reject("Scenery ore origin is unavailable")
			var origin: Variant = arrays[2][int(data.item_origin_index)]
			if not Numbers.integer(origin,0,systems.size()-1):return reject("Scenery ore origin system is outside its catalogue")
			var there: Variant = map_position(systems[int(origin)],data)
			if there==null:return reject("Scenery ore origin position is unavailable")
			var dx: int = there[0]-here[0];var dy: int = there[1]-here[1]
			# Bound supported arithmetic before multiplying, rather than silently
			# changing signed source overflow into a different distribution.
			if absi(dx)>46340 or absi(dy)>46340 or dx*dx+dy*dy>2147483647:return reject("Scenery map distance exceeds supported source arithmetic")
			var distance := int(f32(sqrt(f32(float(dx*dx+dy*dy)))))
			weight=int(data.weight_base)-distance
			if weight<int(data.weight_minimum):weight=0
		rows.append({"item_id":id,"weight":weight,"source_order":rows.size()})
	if int(data.fallback_item_id)>=items.size() or int(data.override_item_id)>=items.size():return reject("Scenery special ore is outside its catalogue")
	rows.append({"item_id":int(data.fallback_item_id),"weight":int(data.location_weight) if location_match else 0,"source_order":rows.size()})
	# Explicit tie order reproduces source stable ordering without depending on
	# the sorting algorithm used by the engine runtime.
	rows.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.weight>b.weight or a.weight==b.weight and a.source_order<b.source_order)
	for rank in rows.size():
		if rows[rank].weight>0:rows[rank].weight-=int(data.rank_discount)*rank
		if special_ore_flag and campaign_cursor>=int(data.override_cursor):rows[rank].item_id=int(data.override_item_id)
		rows[rank].erase("source_order")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_parameters=data.duplicate(true);_rows=rows;_location_match=location_match;_station_id=station_id
	return true

func snapshot() -> Dictionary:
	if _identity.is_empty():return {}
	var result := _identity.duplicate()
	result.station_id=_station_id;result.location_match=_location_match;result.rows=_rows.duplicate(true)
	return result

func choose(random_state: Variant, cursor: Variant) -> Dictionary:
	error=""
	if _identity.is_empty():return fail("Configure scenery ores first")
	if not cursor is int or cursor<0 or cursor>=int(_parameters.sample_rows):return fail("Invalid scenery ore cursor")
	var random := Generator.new()
	if not random.restore(random_state):return fail(random.error)
	if _location_match:return choice(int(_parameters.fallback_item_id),cursor,random.snapshot(),0)
	var possible := false
	for index in int(_parameters.sample_rows):
		if _rows[index].weight>0 and accepted_id(_rows[index].item_id):possible=true
	if not possible:return fail("No source-supported scenery ore can be sampled")
	var position: int = cursor
	for attempt in MAX_ATTEMPTS:
		var row: Dictionary = _rows[position]
		if random.next_int(int(_parameters.draw_bound))>=row.weight:
			position=0
			continue
		position=(position+1)%int(_parameters.sample_rows)
		if accepted_id(row.item_id):return choice(row.item_id,position,random.snapshot(),attempt+1)
	return fail("Scenery ore sampling exceeded the work limit; no random state committed")

func accepted_id(id: int) -> bool:
	return id<int(_parameters.fallback_item_id) or id==int(_parameters.override_item_id)

func choice(id: int, cursor: int, state: Dictionary, draws: int) -> Dictionary:
	var result := _identity.duplicate()
	result.item_id=id;result.cursor=cursor;result.random_state=state;result.draws=draws
	return result

static func map_position(system: Variant, data: Dictionary) -> Variant:
	if not system is Dictionary:return null
	var fields: Variant = system.get("fields")
	if not (fields is Array or fields is PackedInt32Array) or fields.size()!=8:return null
	var result := []
	for index in data.system_position_indices:
		if not Numbers.integer(fields[int(index)],-2147483648,2147483647):return null
		result.append(int(fields[int(index)]))
	return result

static func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

func reject(message: String) -> bool:
	error=message;return false

func fail(message: String) -> Dictionary:
	error=message;return {}
