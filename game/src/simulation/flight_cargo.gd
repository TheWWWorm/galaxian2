extends RefCounted
## Owned cargo for the verified first departure. Capacity comes from the fresh
## ship catalogue; upgrades, equipment changes and saved holds need later owners.
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Departure=preload("res://src/content/station_departure_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
var error:=""
var _state:={}
var _item_count:=0
var _field_identity: RefCounted
var _mined_indices:=[]

func configure_departure(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted) -> bool:
	error=""
	if bindings==null or catalogues==null or construction==null or construction.get_script()!=Construction or not Departure.parameters(bindings.station_departure):return reject("Cargo requires a prepared first departure")
	var entry: Dictionary=construction.snapshot()
	if entry.is_empty() or entry.get("base_content_id")!=bindings.base_content_id or entry.get("binding_id")!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return reject("Cargo belongs to another departure identity")
	if OrdinaryFlight.select(bindings,entry.get("campaign_cursor")).is_empty():return reject("Cargo requires a supported ordinary departure")
	var training: bool=entry.campaign_cursor==7
	var ship_id:=int(bindings.station_departure.ship_id)
	var ships: Array=catalogues.tables.get("ships",[])
	if entry.departure.loadout.ship_id!=ship_id or ship_id>=ships.size() or (not training and entry.departure.cargo_used!=0) or int(bindings.station_departure.initial_cargo_used)!=0:return reject("Unsupported initial cargo or ship")
	var capacity: Variant=ships[ship_id].get("stats",{}).get("cargo_capacity")
	if not Numbers.integer(capacity,0,2147483647):return reject("Ship cargo capacity is unavailable")
	var item_count: int=catalogues.tables.get("items",[]).size()
	if item_count==0:return reject("Cargo requires the item catalogue")
	var candidate: RefCounted=get_script().new()
	candidate._state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":ship_id,
		"capacity":int(capacity),"used":0,"entries":[]}
	candidate._item_count=item_count
	if training:
		var equipment: RefCounted=construction.equipment_owner()
		if equipment==null:return reject("Training cargo requires its retained equipment owner")
		var hold: Dictionary=equipment.snapshot().cargo
		if entry.departure.get("cargo")!=hold or not candidate.add_entries(hold.entries) or candidate.snapshot()!=hold:return reject("Training cargo differs from the earned hold or capacity")
	_state=candidate._state.duplicate(true)
	_item_count=item_count;_field_identity=construction.scenery_owner().presentation_identity()
	_mined_indices=[]
	return true

func add_entries(entries: Array) -> bool:
	error=""
	if _state.is_empty():return reject("Configure the cargo hold before adding items")
	var staged: Array=_state.entries.duplicate(true)
	var used:=int(_state.used)
	for entry in entries:
		if not entry is Dictionary or entry.size()!=2 or not Numbers.integer(entry.get("item_id"),0,_item_count-1) or not Numbers.integer(entry.get("quantity"),1,2147483647):return reject("Invalid cargo item or quantity")
		if entry.quantity>_state.capacity-used:return reject("Cargo exceeds the available hold space")
		var found:=false
		for row in staged:
			if row.item_id==entry.item_id:row.quantity+=entry.quantity;found=true;break
		if not found:staged.append(entry.duplicate())
		used+=entry.quantity
	_state.entries=staged;_state.used=used
	return true

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true);result.free_space=result.capacity-result.used
	return result

func field_identity() -> RefCounted:return _field_identity

func matches_mined_field(field: Dictionary) -> bool:
	# Prospective branches share a world identity. Also require the same mining
	# history so combining an old field with a newer hold cannot duplicate ore.
	if _state.is_empty() or field.get("base_content_id")!=_state.base_content_id or field.get("binding_id")!=_state.binding_id:return false
	# A prepared motion-only field has no body/mining owner yet. Its initial
	# empty history can still participate in ordinary cargo objective polling.
	if not field.has("bodies"):return _mined_indices.is_empty() and not field.has("mined_count")
	if field.get("mined_count",0)!=_mined_indices.size():return false
	var actual:=[]
	for row in field.get("bodies",{}).get("objects",[]):
		if row.get("mined",false):actual.append(int(row.index))
	actual.sort()
	return actual==_mined_indices

func _record_mining(object_index: int) -> bool:
	if _state.is_empty() or object_index<0 or _mined_indices.has(object_index):return reject("Cargo already records this asteroid extraction")
	_mined_indices.append(object_index);_mined_indices.sort()
	return true

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new();copy._state=_state.duplicate(true)
	copy._item_count=_item_count;copy._field_identity=_field_identity
	copy._mined_indices=_mined_indices.duplicate()
	return copy
func clear() -> void:error="";_state={};_item_count=0;_field_identity=null;_mined_indices=[]
func reject(message: String) -> bool:error=message;return false
