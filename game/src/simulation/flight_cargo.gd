extends RefCounted
const FlightStages=preload("res://src/content/flight_stages.gd")
## Cargo retains source item order and mission markers between station and
## flight. Asteroid extraction additionally requires the prepared field identity.
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Departure=preload("res://src/content/station_departure_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Equipment=preload("res://src/simulation/station_equipment.gd")
const Stats=preload("res://src/simulation/equipment_stats.gd")
const Contracts=preload("res://src/content/early_contract_definitions.gd")
const Recovery=preload("res://src/simulation/tractor_recovery.gd")
const RecoveryRules=preload("res://src/content/tractor_recovery_definitions.gd")
var error:=""
var _state:={}
var _item_count:=0
var _field_identity: RefCounted
var _mined_indices:=[]
var _mission_cargo_id:=-1
var _recovery_cargo_ids:=[]
var _equipment_ids:=[]
var _recovery_identity: RefCounted
var _recovery_serial:=0

func configure_departure(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted) -> bool:
	error=""
	if bindings==null or catalogues==null or construction==null or construction.get_script()!=Construction or not Departure.parameters(bindings.station_departure):return reject("Cargo requires a prepared first departure")
	var entry: Dictionary=construction.snapshot()
	if entry.is_empty() or entry.get("base_content_id")!=bindings.base_content_id or entry.get("binding_id")!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id:return reject("Cargo belongs to another departure identity")
	if OrdinaryFlight.for_departure(bindings,entry).is_empty():return reject("Cargo requires a supported ordinary departure")
	var equipped: bool=entry.campaign_cursor in FlightStages.EQUIPPED
	var ship_id:=int(bindings.station_departure.ship_id)
	var ships: Array=catalogues.tables.get("ships",[])
	if entry.campaign_cursor in FlightStages.POST_SAHI or load("res://src/content/free_campaign_definitions.gd").supported(bindings.mido_travel,entry.campaign_cursor):
		if not Numbers.integer(entry.departure.loadout.get("ship_id"),0,ships.size()-1):return reject("Ordinary cargo requires its actual equipped ship")
		ship_id=int(entry.departure.loadout.ship_id)
	if entry.departure.loadout.ship_id!=ship_id or ship_id>=ships.size() or (not equipped and entry.departure.cargo_used!=0) or int(bindings.station_departure.initial_cargo_used)!=0:return reject("Unsupported initial cargo or ship")
	var capacity: Variant=ships[ship_id].get("stats",{}).get("cargo_capacity")
	if not Numbers.integer(capacity,0,2147483647):return reject("Ship cargo capacity is unavailable")
	var item_count: int=catalogues.tables.get("items",[]).size()
	if item_count==0:return reject("Cargo requires the item catalogue")
	var candidate: RefCounted=get_script().new()
	candidate._state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":ship_id,
		"capacity":int(capacity),"used":0,"entries":[]}
	candidate._item_count=item_count
	if equipped:
		var equipment: RefCounted=construction.equipment_owner()
		if equipment==null:return reject("Training cargo requires its retained equipment owner")
		var hold: Dictionary=equipment.snapshot().cargo
		if entry.departure.get("cargo")!=hold or not candidate.configure_equipment(bindings,catalogues,equipment):return reject("Flight cargo differs from the retained hold: "+candidate.error)
	_state=candidate._state.duplicate(true)
	_item_count=item_count;_field_identity=construction.scenery_owner().presentation_identity()
	_mined_indices=[];_mission_cargo_id=candidate._mission_cargo_id
	_recovery_cargo_ids=candidate._recovery_cargo_ids;_equipment_ids=candidate._equipment_ids
	_recovery_identity=null;_recovery_serial=0
	return true

func configure_equipment(bindings: RefCounted, catalogues: RefCounted, equipment: RefCounted) -> bool:
	error=""
	if bindings==null or catalogues==null or not equipment is Equipment:return reject("Flight cargo requires the native equipped inventory")
	var owned: Dictionary=equipment.snapshot()
	if owned.is_empty():return reject("Flight cargo requires its retained equipment state")
	var seed: Dictionary=owned.loadout
	if catalogues.content_id!=bindings.base_content_id or seed.base_content_id!=bindings.base_content_id or seed.binding_id!=bindings.binding_id:return reject("Flight cargo belongs to another content identity")
	if not Numbers.integer(seed.ship_id,0,catalogues.tables.ships.size()-1):return reject("The equipped cargo ship is absent")
	var capacity: Variant=Stats.cargo_capacity(bindings,catalogues,seed)
	if not Numbers.integer(capacity,0,2147483647):return reject("The equipped ship lacks its cargo capacity")
	var candidate: RefCounted=get_script().new()
	candidate._state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":seed.ship_id,"capacity":int(capacity),"used":0,"entries":[]}
	candidate._item_count=catalogues.tables.items.size()
	if Contracts.acceptance_parameters(bindings.early_contracts):candidate._mission_cargo_id=int(bindings.early_contracts.courier.cargo_item_id)
	candidate._recovery_cargo_ids=RecoveryRules.cargo_marker_ids(bindings)
	if not owned.get("cargo") is Dictionary:return reject("Equipped cargo lacks its retained rows")
	var hold: Dictionary=owned.cargo
	if candidate._recovery_cargo_ids.is_empty():
		if owned.get("cargo_cache_stale",true) or not hold.get("entries") is Array or not candidate.add_entries(hold.entries) or candidate.snapshot()!=hold:return reject("Equipped cargo differs from its source capacity or retained rows")
	else:
		if not candidate._valid_retained_hold(hold) or not owned.get("cargo_cache_stale") is bool or owned.cargo_cache_stale!=(hold.used!=candidate._used(hold.entries)):return reject("Equipped cargo differs from its retained quantities or used-space cache")
		candidate._state.entries=hold.entries.duplicate(true);candidate._state.used=hold.used
	_state=candidate._state;_item_count=candidate._item_count;_mission_cargo_id=candidate._mission_cargo_id
	_recovery_cargo_ids=candidate._recovery_cargo_ids;_equipment_ids=seed.equipment_ids.duplicate()
	_recovery_identity=null;_recovery_serial=0
	_field_identity=null;_mined_indices=[]
	return true

func add_entries(entries: Array) -> bool:
	error=""
	if _state.is_empty():return reject("Configure the cargo hold before adding items")
	var staged: Array=_state.entries.duplicate(true)
	var used:=int(_state.used)
	for entry in entries:
		if not entry is Dictionary or entry.size()!=2+int(entry.has("mission")) or not Numbers.integer(entry.get("item_id"),0,_item_count-1) or not Numbers.integer(entry.get("quantity"),1,2147483647):return reject("Invalid cargo item or quantity")
		if not _valid_marker(entry):return reject("Invalid mission cargo marker")
		if entry.quantity>_state.capacity-used:return reject("Cargo exceeds the available hold space")
		var found:=false
		for row in staged:
			if row.item_id==entry.item_id:row.quantity+=entry.quantity;found=true;break
		if not found:staged.append(entry.duplicate())
		# Ordinary list insertion/merge refreshes the cache; tractor fast-stack
		# transfers have their separately verified native owner below.
		used=_used(staged)
		if used>2147483647:return reject("Cargo exceeds the source quantity range")
	_state.entries=staged;_state.used=used
	return true

## Bind one equipped tractor history to this hold; prospective frame forks
## share that identity. A new world/device cannot replay an old transfer.
func bind_recovery(owner: RefCounted) -> bool:
	error=""
	if _state.is_empty() or _recovery_cargo_ids.is_empty() or not owner is Recovery or _recovery_identity!=null:return reject("Cargo recovery requires one prepared native tractor")
	var state: Dictionary=owner.snapshot();var equipped: Dictionary=owner.equipment_loadout()
	if not owner.same_identity(_state) or owner.transaction_identity()==null or state.get("transfer_serial")!=0 or equipped.get("ship_id")!=_state.ship_id or equipped.get("equipment_ids")!=_equipment_ids:return reject("The tractor differs from this hold's equipped departure")
	_recovery_identity=owner.transaction_identity();_recovery_serial=0
	return true

## Called only on the cargo fork belonging to the enclosing wreck transaction.
## Take the plan from its typed owner, never from a public snapshot dictionary.
func retain_recovery(owner: RefCounted) -> bool:
	error=""
	if not owner is Recovery or _recovery_identity==null or owner.transaction_identity()!=_recovery_identity or not owner.same_identity(_state):return reject("Cargo transfer belongs to another tractor history")
	var state: Dictionary=owner.snapshot();var frame: Dictionary=state.get("frame",{})
	var plan: Dictionary=frame.get("transfer",{})
	if frame.get("phase")!="pickup" or plan.is_empty() or plan.get("serial")!=_recovery_serial+1 or state.transfer_serial!=plan.serial or plan.get("expected_hold")!=snapshot():return reject("Cargo transfer is stale, repeated or belongs to another retained hold")
	var next:=snapshot();next.entries=plan.inventory_entries.duplicate(true);next.used=plan.used;next.free_space=next.capacity-next.used
	if not _valid_retained_hold(next):return reject("The native recovery plan has invalid retained cargo")
	_state.entries=next.entries;_state.used=next.used;_recovery_serial=plan.serial
	return true

func _valid_retained_hold(hold: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","ship_id","capacity"]:
		if hold.get(key)!=_state.get(key):return false
	if not hold.get("used") is int or not Numbers.integer(hold.used,0,2147483647) or not hold.get("free_space") is int or hold.free_space!=int(hold.capacity)-int(hold.used) or not hold.get("entries") is Array:return false
	var used:=0
	for row in hold.entries:
		if not row is Dictionary or row.size()!=2+int(row.has("mission")) or not row.get("item_id") is int or not Numbers.integer(row.item_id,0,_item_count-1) or not row.get("quantity") is int or not Numbers.integer(row.quantity,1,2147483647-used) or not _valid_marker(row):return false
		used+=row.quantity
	return true

func _valid_marker(row: Dictionary) -> bool:
	return not row.has("mission") or (row.mission is bool and row.mission and (row.item_id==_mission_cargo_id or row.item_id in _recovery_cargo_ids))

func _used(entries: Array) -> int:
	var used:=0
	for row in entries:used+=int(row.quantity)
	return used

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
	copy._mission_cargo_id=_mission_cargo_id
	copy._recovery_cargo_ids=_recovery_cargo_ids;copy._equipment_ids=_equipment_ids
	copy._recovery_identity=_recovery_identity;copy._recovery_serial=_recovery_serial
	return copy
func clear() -> void:
	error="";_state={};_item_count=0;_field_identity=null;_mined_indices=[];_mission_cargo_id=-1
	_recovery_cargo_ids=[];_equipment_ids=[];_recovery_identity=null;_recovery_serial=0
func reject(message: String) -> bool:error=message;return false
