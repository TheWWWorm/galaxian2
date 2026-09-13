extends Node3D
## Passive ordinary body/light LOD assembly. No engine effects or equipment yet.
## Caller owns source reference position, detail setting and authored visibility.
const Resources = preload("res://src/presentation/model_resources.gd")
const Detail = preload("res://src/presentation/ship_detail.gd")
var error := ""
var levels: Array[Node3D] = []
var selection := {}
var _detail: RefCounted

func build(ship_id: int, library: RefCounted, visuals: RefCounted, bindings: RefCounted, quality := "high", shared_resources: RefCounted = null) -> bool:
	clear()
	error = ""
	var selected: Dictionary = bindings.resolve_ship_detail(ship_id)
	if selected.is_empty(): return reject(bindings.error)
	var detail := Detail.new()
	if not detail.configure(bindings.ship_lod,ship_id): return reject(detail.error)
	var paths := []
	for level in selected.levels:
		paths.append(level.path)
		for light in level.lights: paths.append(light.path)
	var resources: RefCounted = shared_resources if shared_resources!=null else Resources.new()
	if shared_resources==null:
		if not resources.prepare(paths,library,visuals,bindings,quality,true): return reject(resources.error)
	elif not resources.covers(paths,bindings,quality,true) or library.manifest.get("content_id", "")!=bindings.base_content_id or visuals.base_content_id!=bindings.base_content_id:
		return reject("Shared ship resources do not match this content, quality or static mesh set")
	for level in selected.levels:
		var body: Node3D = resources.instantiate(level.path)
		body.set_meta("source_resource_id",level.resource_id)
		body.set_meta("source_detail_level",levels.size())
		add_child(body)
		for light in level.lights:
			var child: Node3D = resources.instantiate(light.path)
			child.set_meta("source_resource_id",light.resource_id)
			body.add_child(child)
		body.hide()
		levels.append(body)
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
	selection=next.duplicate(true)
	return true

func valid_selection(next: Variant) -> bool:
	if _detail==null or not next is Dictionary or not next.get("visible") is bool or not next.get("level") is int: return false
	return (next.visible and next.level>=0 and next.level<levels.size()) or (not next.visible and next.level==-1)

func clear() -> void:
	for child in get_children(): child.free()
	levels.clear()
	selection={}
	_detail=null
	if has_meta("source_ship_id"): remove_meta("source_ship_id")

func reject(message: String) -> bool:
	error=message
	return false
