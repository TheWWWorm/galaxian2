extends RefCounted
## Derive the incoming position from generated scenery and retained location order.
## Travel owns authorization, equipment relocation and the final state transaction.
const Definitions=preload("res://src/content/local_arrival_environment_definitions.gd")
const Planets=preload("res://src/simulation/opening_planet_layout.gd")
const Gates=preload("res://src/simulation/gate_environment.gd")
const Cache=preload("res://src/simulation/lounge_cache.gd")
var error:=""
var _state:={}

func configure(bindings: RefCounted,catalogues: RefCounted,station_id: int,locations: RefCounted) -> bool:
	error=""
	if not Definitions.location_supported(bindings,catalogues,station_id,18) or not locations is Cache:return reject("Local arrival requires matching ordinary scenery and retained locations")
	var cache: Dictionary=locations.snapshot()
	if cache.get("base_content_id")!=bindings.base_content_id or cache.get("binding_id")!=bindings.binding_id or cache.get("current_station_id")!=station_id:return reject("Local arrival locations do not select this destination")
	var gates:=Gates.new()
	if not gates.configure(bindings,catalogues,station_id):return reject(gates.error)
	var planets:=Planets.new();var layout:=planets.for_lounge(bindings,catalogues,station_id,18)
	if layout.is_empty():return reject(planets.error)
	var rules: Dictionary=bindings.mido_travel.local_arrival_environment.arrival
	var gate_state: Dictionary=gates.snapshot()
	var cache_index:=int(rules.cache_index)
	var has_cached_planet: bool=cache.locations.size()>cache_index
	var cached_station: int=int(cache.locations[cache_index].station_id) if has_cached_planet else -1
	var position:=Vector3.ZERO;var facing:=false;var source:="gate";var planet_index:=-1
	if station_id==int(gate_state.gate_station_id) or not has_cached_planet:
		var incoming: Variant=gates.arrival_position()
		if not incoming is Vector3:return reject(gates.error)
		position=incoming
	else:
		var system: Dictionary=catalogues.tables.systems[int(layout.system_id)]
		var source_index: int=system.arrays[int(rules.system_station_array)].find(cached_station)
		position=Vector3(rules.fallback_planet_position[0],rules.fallback_planet_position[1],rules.fallback_planet_position[2])
		source="fallback_planet"
		if source_index>=0:
			planet_index=source_index+int(rules.planet_index_offset)
			if planet_index>=layout.entries.size():return reject("The cached station's planet index is absent from generated scenery")
			position=layout.entries[planet_index].origin;source="cached_planet"
		position*=float(rules.planet_multiplier)
		facing=bool(rules.face_origin)
	if not position.is_finite() or (facing and position.is_zero_approx()):return reject("The original arrival position cannot define a flight heading")
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":18,
		"station_id":station_id,"system_id":int(layout.system_id),"position":position,"face_origin":facing,
		"source":source,"cache_station_id":cached_station,"planet_index":planet_index,
		"location_order":cache.locations.map(func(entry):return int(entry.station_id)),
		"planets":layout,"gates":gate_state}
	return true

func player_pose(initial_basis: Basis) -> Variant:
	if _state.is_empty() or not initial_basis.is_finite() or absf(initial_basis.determinant()-1.0)>0.0001:
		reject("Arrival requires the ordinary initial player heading");return null
	# Flight's forward direction is positive local Z. Looking toward the origin
	# therefore uses the model-front convention; gate arrivals keep source yaw.
	var basis: Basis=Basis.looking_at(-_state.position,Vector3.UP,true) if _state.face_origin else initial_basis
	return Transform3D(basis,_state.position)

func snapshot() -> Dictionary:return _state.duplicate(true)
func reject(message: String) -> bool:error=message;return false
