extends RefCounted
## Synthetic catalogues and identities; contains no original game data.
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")

static func make() -> Array:
	var bindings := Bindings.new();var catalogues := Catalogues.new()
	bindings.base_content_id="a".repeat(64);bindings.binding_id="b".repeat(64);catalogues.content_id=bindings.base_content_id
	bindings.scenery_resources={"ore_item_ids":[0,1,2,3,4,5,6,7,8,9],"fallback_item_id":10,"override_item_id":11,"weight_base":100,"weight_minimum":50,"location_weight":100,"rank_discount":2,"sample_rows":6,"draw_bound":100,"override_cursor":90,"item_origin_index":9,"system_position_indices":[3,4],"model_ids":[400,500,600,700],"provenance":{}}
	catalogues.tables={"stations":[{"system_id":0}],"systems":[],"items":[]}
	for point in [[0,0],[3,4],[30,40],[51,0],[50,0],[49,0],[100,100],[0,0],[31,40],[1,0]]:
		catalogues.tables.systems.append({"fields":[0,0,0,point[0],point[1],0,0,0]})
	for id in 12:catalogues.tables.items.append({"arrays":[[],[],[0,id,1,4,2,23,3,1,4,mini(id,9)]]})
	bindings.scenery_population={"count_base":10,"count_bound":4,"provenance":{}}
	return [bindings,catalogues]

