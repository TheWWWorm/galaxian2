extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Dictionary) -> bool:
	if data.get("threshold_comparison") != "greater" or data.get("maximum_comparison") != "greater_or_equal": return false
	var bodies: Variant = data.get("body_resource_ids")
	var children: Variant = data.get("child_resource_ids")
	if not bodies is Array or bodies.is_empty() or bodies.size()>64 or not children is Array or children.size()!=bodies.size(): return false
	for i in bodies.size():
		for row in [bodies[i],children[i]]:
			if not row is Array or row.size()!=2: return false
			for id in row:
				if not Numbers.integer(id,0,65535): return false
			if row[0]==65535 and row[1]!=65535: return false
		if children[i][0]!=65535 and ((bodies[i][0]==65535) or (children[i][1]==65535)!=(bodies[i][1]==65535)): return false
	var distances: Variant = data.get("distances")
	if not distances is Array or distances.size()!=2: return false
	if not Numbers.integer(distances[0],1,1000000) or not Numbers.integer(distances[1],distances[0]+1,1000000) or not Numbers.integer(data.get("maximum_distance"),distances[1]+1,1000000): return false
	var boundaries: Variant = data.get("detail_boundaries")
	var factors: Variant = data.get("squared_distance_factors")
	if not boundaries is Array or not factors is Array or boundaries.size() not in [0,2] or factors.size()!=boundaries.size()+1: return false
	for values in [boundaries,factors]:
		var previous := 0.0
		for value in values:
			if not (value is float or value is int) or not is_finite(value) or value<=previous or value>1.0: return false
			previous=float(value)
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Missing ship LOD declarations"
	if data.is_empty(): return ""
	if not parameters(data): return "Invalid ship LOD parameters"
	var expected := {}
	if architecture=="x86_64":
		expected={"body":57,"fill":74,"step":66,"child":51,"child_copy":64,"limit":13,"select":122,"cull":44,"square":19,"detail":68,"detail_low":4,"detail_high":4,"detail_first":4,"detail_pair":8,"limit_setter":17,"body_table":732,"child_table":732}
		if data.body_resource_ids.size()!=61 or data.detail_boundaries.size()!=2: return "Ship LOD profile mismatch"
	elif architecture=="armv7":
		expected={"body":54,"fill":38,"step":42,"child":44,"child_copy":28,"limit":24,"select":52,"cull":48,"square":30,"limit_setter":22,"body_table":768,"child_table":768}
		if data.body_resource_ids.size()!=64 or not data.detail_boundaries.is_empty() or data.squared_distance_factors!=[1.0]: return "Ship LOD profile mismatch"
	var provenance: Variant = data.get("provenance")
	if expected.is_empty() or not provenance is Dictionary or provenance.size()!=expected.size(): return "Invalid ship LOD provenance"
	var spans := []
	for key in expected:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[expected[key]],executable_bytes): return "Invalid ship LOD extent: "+key
		var begin := int(row.offset); var end := begin+int(row.bytes)
		for span in spans:
			if begin<span.y and end>span.x: return "Overlapping ship LOD declarations"
		spans.append(Vector2i(begin,end))
	return ""
