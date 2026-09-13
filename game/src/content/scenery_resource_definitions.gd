extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=14 or not data.get("provenance") is Dictionary: return false
	if not data.get("ore_item_ids") is Array or data.ore_item_ids.size()!=10 or not data.get("model_ids") is Array or data.model_ids.size()!=4: return false
	var seen := {}
	for id in data.ore_item_ids:
		if not Numbers.integer(id,0,65535) or seen.has(int(id)): return false
		seen[int(id)]=true
	for id in data.model_ids:
		if not Numbers.integer(id,0,65532): return false
	for key in ["fallback_item_id","override_item_id"]:
		if not Numbers.integer(data.get(key),0,65535) or seen.has(int(data[key])): return false
		seen[int(data[key])]=true
	if not Numbers.integer(data.get("weight_base"),1,100) or not Numbers.integer(data.get("weight_minimum"),1,int(data.weight_base)): return false
	for key in {"location_weight":100,"rank_discount":2,"sample_rows":6,"draw_bound":100,"override_cursor":90,"item_origin_index":9}:
		if not Numbers.integer(data.get(key),0,2147483647) or int(data[key])!={"location_weight":100,"rank_discount":2,"sample_rows":6,"draw_bound":100,"override_cursor":90,"item_origin_index":9}[key]: return false
	return data.get("system_position_indices") is Array and data.system_position_indices.size()==2 and Numbers.integer(data.system_position_indices[0],3,3) and Numbers.integer(data.system_position_indices[1],4,4)

static func validate(data: Variant, executable_bytes: int, architecture: String, population: Dictionary) -> String:
	if not data is Dictionary:return "Missing scenery resource declarations"
	if data.is_empty():return ""
	if population.is_empty() or not parameters(data):return "Invalid scenery resource declarations"
	var sizes := {"entry":12,"probability":710,"station_system":9,"system_x":9,"system_y":9,"item_origin":9,"item":140,"sqrt_wrapper":10,"sqrt":33,"selector":157,"models":91,"model_table":16} if architecture=="x86_64" else {"entry":6,"probability":538,"station_system":4,"system_x":4,"system_y":4,"item_origin":4,"item":82,"sqrt_wrapper":6,"sqrt":34,"selector":88,"models":36,"model_table":16} if architecture=="armv7" else {}
	if sizes.is_empty() or data.provenance.size()!=sizes.size():return "Invalid scenery resource provenance"
	var spans := []
	for key in sizes:
		var row: Variant = data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes):return "Invalid scenery resource extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x:return "Overlapping scenery resource extents"
		spans.append(span)
	if data.provenance.entry.offset+data.provenance.entry.bytes!=population.provenance.count.offset:return "Disconnected scenery resource entry"
	if data.provenance.item.offset+(280 if architecture=="x86_64" else 176)!=data.provenance.item_origin.offset:return "Disconnected scenery item schema"
	return ""
