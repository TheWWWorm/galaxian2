extends RefCounted
## Native selection from imported ordinary-ship LOD declarations. The scene must
## provide the source reference distance and Mac detail input explicitly.
const Definitions = preload("res://src/content/ship_lod_definitions.gd")
const GeometryDetail = preload("res://src/presentation/geometry_detail.gd")
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

func select(distance_squared: Variant, detail: Variant) -> Dictionary:
	var selected := _selector.select(distance_squared,detail)
	error=_selector.error
	return selected

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
