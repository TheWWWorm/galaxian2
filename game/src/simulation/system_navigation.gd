extends RefCounted
## Routes and guidance from the retained system availability and source catalogues.
## Planning has no effects on the current location, visits, missions or inventory.
const Definitions=preload("res://src/content/free_navigation_definitions.gd")
const ContractNavigation=preload("res://src/simulation/contract_navigation.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _identity:={}
var _systems:=[]
var _stations:=[]
var _availability:=[]
var _rules:={}

func configure(bindings: RefCounted,cat: RefCounted,availability: Variant) -> bool:
	error=""
	if not Definitions.available(bindings) or not cat is Catalogues or cat.content_id!=bindings.base_content_id:return reject("System navigation requires matching imported content and route declarations")
	var base: Dictionary=bindings.early_contracts.base_navigation
	if not ContractNavigation.valid_availability(base,availability):return reject("System navigation requires retained availability for every system")
	if cat.tables.get("systems",[]).size()!=int(base.system_count) or cat.tables.get("stations",[]).size()!=int(base.global_station_bound):return reject("System navigation requires complete source catalogues")
	var rules: Dictionary=bindings.mido_travel.free_navigation
	var systems:=[]
	for row in cat.tables.systems:
		var gate:=int(row.fields[int(rules.gate_station_field)])
		if gate!=-1 and (not Numbers.integer(gate,0,cat.tables.stations.size()-1) or not row.station_ids.has(gate) or cat.tables.stations[gate].system_id!=row.id):return reject("The system jumpgate must belong to its source station list")
		var links:=Array(row.linked_system_ids)
		if not links.all(func(id):return Numbers.integer(id,0,cat.tables.systems.size()-1)):return reject("A system route names an absent system")
		systems.append({"id":int(row.id),"station_ids":row.station_ids.duplicate(),"links":links.duplicate(),"gate_station_id":gate})
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_systems=systems;_stations=cat.tables.stations.duplicate(true)
	_availability=availability.duplicate();_rules=rules.duplicate(true)
	return true

func route(from_system: int,to_system: int) -> Array:
	error=""
	if _identity.is_empty() or not Numbers.integer(from_system,0,_systems.size()-1) or not Numbers.integer(to_system,0,_systems.size()-1):reject("Choose source systems from the imported catalogue");return []
	# Normalize the zero-hop route to one node; an empty result means unreachable.
	if from_system==to_system:return [from_system]
	var predecessors:={from_system:-1}
	var queue:=[from_system]
	var index:=0
	while index<queue.size():
		var current: int=queue[index];index+=1
		for neighbor in _systems[current].links:
			if not _availability[neighbor] or predecessors.has(neighbor):continue
			predecessors[neighbor]=current
			if neighbor==to_system:
				var result:=[to_system]
				var previous: int=current
				while previous!=-1:
					result.push_front(previous);previous=predecessors[previous]
				return result
			queue.append(neighbor)
	reject("No route connects these systems through currently available destinations")
	return []

func course(from_station: int,to_station: int) -> Dictionary:
	error=""
	if _identity.is_empty() or not Numbers.integer(from_station,0,_stations.size()-1) or not Numbers.integer(to_station,0,_stations.size()-1):reject("Choose source stations from the imported catalogue");return {}
	var origin: int=_stations[from_station].system_id
	var destination: int=_stations[to_station].system_id
	var path:=route(origin,destination)
	if path.is_empty():return {}
	var guidance:={"kind":"clear"}
	if from_station!=to_station:
		if origin==destination:
			guidance={"kind":"planet","station_id":to_station,"planet_index":_systems[origin].station_ids.find(to_station)}
		else:
			var gate: int=_systems[origin].gate_station_id
			if gate<0:reject("This system has no ordinary jumpgate");return {}
			guidance={"kind":"gate","station_id":gate,"environment_object_index":int(_rules.gate_environment_object_index)} if from_station==gate else {"kind":"planet","station_id":gate,"planet_index":_systems[origin].station_ids.find(gate)}
	var result:=_identity.duplicate()
	result.merge({"from_station_id":from_station,"destination_station_id":to_station,
		"system_path":path,"jump_count":path.size()-1,"guidance":guidance})
	return result

func snapshot() -> Dictionary:
	return {} if _identity.is_empty() else {"base_content_id":_identity.base_content_id,"binding_id":_identity.binding_id,"system_availability":_availability.duplicate()}

func fork() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._systems=_systems.duplicate(true);copy._stations=_stations.duplicate(true)
	copy._availability=_availability.duplicate();copy._rules=_rules.duplicate(true)
	return copy

func reject(message: String) -> bool:
	error=message
	return false
