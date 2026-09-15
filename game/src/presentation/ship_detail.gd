extends RefCounted
## Native selection from imported ordinary-ship LOD declarations. The scene must
## provide the source reference distance and Mac detail input explicitly.
const Definitions = preload("res://src/content/ship_lod_definitions.gd")
const GeometryDetail = preload("res://src/presentation/geometry_detail.gd")
const Ambient = preload("res://src/content/ambient_population_definitions.gd")
const Convoy = preload("res://src/content/convoy_ship_definitions.gd")
const FreePopulation=preload("res://src/content/free_population_definitions.gd")
const Alioth = preload("res://src/content/alioth_attack_definitions.gd")
var error := ""
var _selector := GeometryDetail.new()

func configure(data: Dictionary, ship_id: int) -> bool:
	_selector.clear(); error=""
	if not Definitions.parameters(data) or ship_id<0 or ship_id>=data.body_resource_ids.size(): return reject("Ship LOD declarations are unavailable")
	if ship_id in [13,14,15]: return reject("Special ship LOD construction is not implemented")
	var count := 0
	for id in data.body_resource_ids[ship_id]:
		if id!=65535: count+=1
	if not _selector.configure(data.distances,count,int(data.maximum_distance),data.detail_boundaries,data.squared_distance_factors):return reject(_selector.error)
	return true

func configure_freighter(data: Dictionary, ordinary_detail: Dictionary) -> bool:
	_selector.clear();error=""
	if not Ambient.parameters(data) or not Definitions.parameters(ordinary_detail):return reject("Freighter detail declarations are unavailable")
	# This special factory declares one alternate and retains the model's zero
	# maximum-distance default. Ordinary ships set a separate distance cull.
	if not _selector.configure([int(data.freighter.assembly.lod_distance)],1,0,ordinary_detail.detail_boundaries,ordinary_detail.squared_distance_factors):return reject(_selector.error)
	return true

func select(distance_squared: Variant, detail: Variant) -> Dictionary:
	var selected := _selector.select(distance_squared,detail)
	error=_selector.error
	return selected

func configure_convoy(data: Dictionary,ordinary_detail: Dictionary) -> bool:
	_selector.clear();error=""
	if not Convoy.parameters(data) or not Definitions.parameters(ordinary_detail):return reject("Convoy ship detail declarations are unavailable")
	return _configure_assembly(data.assembly,ordinary_detail)

func configure_alioth_freighter(data: Dictionary,ordinary_detail: Dictionary) -> bool:
	_selector.clear();error=""
	if not Alioth.parameters(data) or not Definitions.parameters(ordinary_detail):return reject("Alioth freighter detail declarations are unavailable")
	return _configure_assembly(data.population.freighter_assembly,ordinary_detail)

func configure_assembly(bindings: RefCounted,assembly: Dictionary) -> bool:
	_selector.clear();error=""
	if bindings==null:return reject("Ship detail requires content declarations")
	if FreePopulation.available(bindings) and bindings.mido_travel.free_population.freighter_assemblies.values().has(assembly):
		if not Definitions.parameters(bindings.ship_lod):return reject("Ordinary ship detail declarations are unavailable")
		return _configure_assembly(assembly,bindings.ship_lod)
	var alioth: Dictionary=bindings.mido_travel.get("alioth_attack",{})
	if Alioth.parameters(alioth) and assembly==alioth.population.freighter_assembly:
		return configure_alioth_freighter(alioth,bindings.ship_lod)
	var convoy: Dictionary=bindings.mido_travel.get("convoy_ship",{})
	if Convoy.parameters(convoy) and assembly==convoy.assembly:
		return configure_convoy(convoy,bindings.ship_lod)
	if Ambient.assembly_matches(bindings.ambient_population,assembly):
		return configure_freighter(bindings.ambient_population,bindings.ship_lod)
	return reject("Ship detail requires an original supported assembly")

func _configure_assembly(assembly: Dictionary,ordinary_detail: Dictionary) -> bool:
	if not _selector.configure(assembly.lod_distances,assembly.body_resource_ids.size()-1,int(assembly.maximum_distance),ordinary_detail.detail_boundaries,ordinary_detail.squared_distance_factors):return reject(_selector.error)
	return true

func is_configured() -> bool:
	return _selector.is_configured()

func has_alternates() -> bool:
	return _selector.has_alternates()

static func single(value: float) -> float:
	return GeometryDetail.single(value)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._selector = _selector.fork_for_frame()
	return copy

func reject(message: String) -> bool:
	error=message
	return false
