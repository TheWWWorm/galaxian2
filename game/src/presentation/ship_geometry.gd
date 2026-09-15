extends Node3D
## Passive body/light LOD assembly with optional original player nozzle glow.
## Exhaust particles and equipment have separate owners.
## Caller owns source reference position, detail setting and authored visibility.
const Resources = preload("res://src/presentation/model_resources.gd")
const Detail = preload("res://src/presentation/ship_detail.gd")
const Ambient = preload("res://src/content/ambient_population_definitions.gd")
const Convoy = preload("res://src/content/convoy_ship_definitions.gd")
const FreePopulation=preload("res://src/content/free_population_definitions.gd")
const Alioth = preload("res://src/content/alioth_attack_definitions.gd")
var error := ""
var levels: Array[Node3D] = []
var selection := {}
var engine_glow: Node3D
var _detail: RefCounted

func build(ship_id: int, library: RefCounted, visuals: RefCounted, bindings: RefCounted, quality := "high", shared_resources: RefCounted = null, with_player_glow := false) -> bool:
	clear()
	error = ""
	var selected: Dictionary = bindings.resolve_ship_detail(ship_id)
	if selected.is_empty(): return reject(bindings.error)
	var detail := Detail.new()
	if not detail.configure(bindings.ship_lod,ship_id): return reject(detail.error)
	return _build(ship_id,selected,detail,library,visuals,bindings,quality,shared_resources,with_player_glow)

func build_freighter(assembly: Dictionary,library: RefCounted,visuals: RefCounted,bindings: RefCounted,quality := "high",shared_resources: RefCounted=null) -> bool:
	clear();error=""
	if bindings==null or not Ambient.assembly_matches(bindings.ambient_population,assembly):return reject("Unsupported freighter assembly")
	var detail:=Detail.new()
	if not detail.configure_freighter(bindings.ambient_population,bindings.ship_lod):return reject(detail.error)
	var selected:={"levels":[]}
	for index in 2:
		var id:=int(assembly.root_model_id if index==0 else assembly.lod_model_id)
		var parts:=[]
		# The engine is the source factory's last shared child and is attached
		# to both body levels. The light mesh exists only on the detailed hull.
		if index==0:parts.append({"resource_id":int(assembly.light_model_id)})
		parts.append({"resource_id":int(assembly.engine_model_id)})
		for container in int(assembly.container_count):
			parts.append({"resource_id":int(assembly.container_model_id if index==0 else assembly.container_lod_model_id),
				"offset":Vector3(0,0,float(assembly.container_positions_z[container]))})
		for part in parts:
			part.path=bindings.resolve(part.resource_id,"mesh")
			if part.path.is_empty():return reject(bindings.error)
		var path: String=bindings.resolve(id,"mesh")
		if path.is_empty():return reject(bindings.error)
		selected.levels.append({"resource_id":id,"path":path,"parts":parts})
	return _build(int(bindings.ambient_population.freighter.hull_catalogue_id),selected,detail,library,visuals,bindings,quality,shared_resources,false)

func build_convoy(library: RefCounted,visuals: RefCounted,bindings: RefCounted,quality := "high",shared_resources: RefCounted=null) -> bool:
	clear();error=""
	if not Convoy.available(bindings):return reject("Convoy ship assembly is unavailable")
	var data: Dictionary=bindings.mido_travel.convoy_ship
	var detail:=Detail.new()
	if not detail.configure_convoy(data,bindings.ship_lod):return reject(detail.error)
	return _build_assembly(int(data.hull_catalogue_id),data.assembly,detail,library,visuals,bindings,quality,shared_resources)

func build_alioth_freighter(library: RefCounted,visuals: RefCounted,bindings: RefCounted,quality := "high",shared_resources: RefCounted=null) -> bool:
	clear();error=""
	if not Alioth.available(bindings):return reject("Alioth freighter assembly is unavailable")
	var data: Dictionary=bindings.mido_travel.alioth_attack
	var detail:=Detail.new()
	if not detail.configure_alioth_freighter(data,bindings.ship_lod):return reject(detail.error)
	return _build_assembly(int(data.population.actors[0].hull_catalogue_id),data.population.freighter_assembly,detail,library,visuals,bindings,quality,shared_resources)

func build_population_assembly(assembly: Dictionary,library: RefCounted,visuals: RefCounted,bindings: RefCounted) -> bool:
	clear();error=""
	if FreePopulation.available(bindings) and bindings.mido_travel.free_population.freighter_assemblies.values().has(assembly):
		var detail:=Detail.new()
		if not detail.configure_assembly(bindings,assembly):return reject(detail.error)
		return _build_assembly(15,assembly,detail,library,visuals,bindings,"high",null)
	if Alioth.available(bindings) and assembly==bindings.mido_travel.alioth_attack.population.freighter_assembly:
		return build_alioth_freighter(library,visuals,bindings)
	if Convoy.available(bindings) and assembly==bindings.mido_travel.convoy_ship.assembly:
		return build_convoy(library,visuals,bindings)
	return build_freighter(assembly,library,visuals,bindings)

func _build_assembly(ship_id: int,assembly: Dictionary,detail: RefCounted,library: RefCounted,visuals: RefCounted,bindings: RefCounted,quality: String,shared_resources: RefCounted) -> bool:
	var selected:={"levels":[]}
	for index in assembly.body_resource_ids.size():
		var id:=int(assembly.body_resource_ids[index])
		var path: String=bindings.resolve(id,"mesh")
		if path.is_empty():return reject(bindings.error)
		var parts:=[]
		for child in assembly.child_resource_ids[index]:
			var child_path: String=bindings.resolve(int(child),"mesh")
			if child_path.is_empty():return reject(bindings.error)
			parts.append({"resource_id":int(child),"path":child_path})
		selected.levels.append({"resource_id":id,"path":path,"parts":parts,"model_scale":float(assembly.model_scale)})
	return _build(ship_id,selected,detail,library,visuals,bindings,quality,shared_resources,false)

func _build(ship_id: int,selected: Dictionary,detail: RefCounted,library: RefCounted,visuals: RefCounted,bindings: RefCounted,quality: String,shared_resources: RefCounted,with_player_glow: bool) -> bool:
	var paths := []
	for level in selected.levels:
		paths.append(level.path)
		for part in level.get("parts",level.get("lights",[])):paths.append(part.path)
	var glow: Dictionary={}
	if with_player_glow:
		glow=bindings.resolve_player_engine_glow(ship_id,quality)
		if glow.is_empty():return reject(bindings.error)
		paths.append(glow.path)
	var resources: RefCounted = shared_resources if shared_resources!=null else Resources.new()
	if shared_resources==null:
		if not resources.prepare(paths,library,visuals,bindings,quality,true): return reject(resources.error)
	elif not resources.covers(paths,bindings,quality,true) or library.manifest.get("content_id", "")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id:
		return reject("Shared ship resources do not match this content, quality or static mesh set")
	for level in selected.levels:
		var body: Node3D = resources.instantiate(level.path)
		body.set_meta("source_resource_id",level.resource_id)
		body.set_meta("source_detail_level",levels.size())
		body.scale*=float(level.get("model_scale",1.0))
		add_child(body)
		for part in level.get("parts",level.get("lights",[])):
			var child: Node3D = resources.instantiate(part.path)
			child.set_meta("source_resource_id",part.resource_id)
			child.position=part.get("offset",Vector3.ZERO)
			body.add_child(child)
		body.hide()
		levels.append(body)
	if with_player_glow:
		engine_glow=resources.instantiate(glow.path)
		engine_glow.name="EngineGlow"
		engine_glow.set_meta("source_resource_id",glow.resource_id)
		add_child(engine_glow)
		engine_glow.hide()
	if shared_resources==null: resources.clear()
	_detail=detail
	set_meta("source_ship_id",ship_id)
	return true

func apply_detail(distance_squared: Variant, detail: Variant) -> bool:
	error = ""
	if _detail==null: return reject("Build ship geometry before selecting its detail")
	var next: Dictionary = _detail.select(distance_squared,detail)
	if next.is_empty(): return reject(_detail.error)
	return apply_selection(next)

func apply_selection(next: Dictionary) -> bool:
	error = ""
	if not valid_selection(next): return reject("Invalid or unconfigured ship detail selection")
	for i in levels.size(): levels[i].visible=next.visible and next.level==i
	# The source attaches the same glow child to each body LOD. One native
	# sibling retains that shared pose and follows the selected body's cull gate.
	if engine_glow!=null:engine_glow.visible=next.visible
	selection=next.duplicate(true)
	return true

func valid_selection(next: Variant) -> bool:
	if _detail==null or not next is Dictionary or not next.get("visible") is bool or not next.get("level") is int: return false
	return (next.visible and next.level>=0 and next.level<levels.size()) or (not next.visible and next.level==-1)

func clear() -> void:
	for child in get_children(): child.free()
	levels.clear()
	engine_glow=null
	selection={}
	_detail=null
	if has_meta("source_ship_id"): remove_meta("source_ship_id")

func reject(message: String) -> bool:
	error=message
	return false
