extends RefCounted
## Scenery shares the ordinary geometry selector and periodic source manager.
## The owner supplies the source display context and camera at the update point.
const Group = preload("res://src/presentation/ship_detail_group.gd")
const Detail = preload("res://src/presentation/geometry_detail.gd")
const Resources = preload("res://src/content/scenery_resource_definitions.gd")
const SharedDetail = preload("res://src/content/ship_lod_definitions.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const LARGE_DISTANCES = [60000,100000,120000]
const SMALL_DISTANCES = [40000,70000,90000]
const LARGE_DISPLAY_DISTANCES = [100000,120000,150000]
var error := ""
var _group := Group.new()
var _positions := {}

func configure(bindings: RefCounted, field: Dictionary, large_display: bool) -> bool:
	clear()
	if bindings==null or not Resources.parameters(bindings.scenery_resources) or not SharedDetail.parameters(bindings.ship_lod):return reject("Scenery detail requires source resource and shared detail declarations")
	if field.get("base_content_id")!=bindings.base_content_id or field.get("binding_id")!=bindings.binding_id:return reject("Scenery detail belongs to another content identity")
	var rows: Variant = field.get("objects")
	if not rows is Array or rows.is_empty() or rows.size()>8192 or not Numbers.integer(field.get("large_count"),0,rows.size()):return reject("Invalid scenery detail object list")
	var selectors := {};var positions := {}
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary or not Numbers.integer(row.get("index"),index,index) or not row.get("large") is bool or row.large!=(index<int(field.large_count)):return reject("Invalid scenery detail order or size group")
		if not Numbers.integer(row.get("model_variant"),0,3) or not Numbers.integer(row.get("model_id"),0,65532) or row.model_id!=bindings.scenery_resources.model_ids[int(row.model_variant)]:return reject("Invalid scenery detail resource alternative")
		if not row.get("position") is Vector3 or not row.position.is_finite():return reject("Invalid scenery detail position")
		var selector := Detail.new()
		var distances: Array = LARGE_DISPLAY_DISTANCES if large_display else LARGE_DISTANCES if row.large else SMALL_DISTANCES
		if not selector.configure(distances,3,0,bindings.ship_lod.detail_boundaries,bindings.ship_lod.squared_distance_factors):return reject(selector.error)
		selectors[index]=selector;positions[index]=row.position
	if not _group.configure_selectors(bindings,selectors):return reject(_group.error)
	positions.make_read_only()
	_positions=positions
	return true

func update(delta_ms: Variant, reference: Variant, detail: Variant, suppressed: Variant) -> bool:
	var ok := _group.update(delta_ms,_positions,reference,detail,suppressed)
	error=_group.error;return ok

func refresh(reference: Variant, detail: Variant) -> bool:
	var ok := _group.refresh(_positions,reference,detail)
	error=_group.error;return ok

func snapshot() -> Dictionary:
	return _group.snapshot()

func clear() -> void:
	error="";_positions={};_group.clear()

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._group=_group.fork_for_frame();copy._positions=_positions
	return copy

func reject(message: String) -> bool:
	error=message;return false
