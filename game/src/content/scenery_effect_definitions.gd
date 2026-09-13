extends RefCounted
## Edition-local effect resources and the supported fresh-instance speed rule.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")

static func parameters(data: Variant, resources: Dictionary = {}) -> bool:
	if not data is Dictionary or data.size()!=5 or not data.get("provenance") is Dictionary: return false
	if not data.get("variants") is Array or data.variants.size()!=4: return false
	for key in {"speed_threshold":1,"speed_base":1,"speed_scale":3}:
		if not Numbers.integer(data.get(key),0,3) or data[key]!={"speed_threshold":1,"speed_base":1,"speed_scale":3}[key]: return false
	if not resources.is_empty() and (not resources.get("model_ids") is Array or resources.model_ids.size()!=4): return false
	var seen := {}
	for index in range(4):
		var row: Variant = data.variants[index]
		if not row is Dictionary or row.size()!=3 or not Numbers.integer(row.get("base_model_id"),0,65535) or seen.has(int(row.base_model_id)): return false
		seen[int(row.base_model_id)]=true
		if not Numbers.integer(row.get("effect_type"),index+2,index+2) or not row.get("model_ids") is Array or row.model_ids.size()!=2: return false
		for id in row.model_ids:
			if not Numbers.integer(id,0,65535): return false
		if row.model_ids[0]==row.model_ids[1]: return false
		if not resources.is_empty() and (not Numbers.integer(resources.model_ids[index],0,65535) or row.base_model_id!=resources.model_ids[index]): return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String, resources: Dictionary) -> String:
	if not data is Dictionary: return "Missing scenery effect declarations"
	if data.is_empty(): return ""
	if resources.is_empty() or not parameters(data,resources): return "Invalid scenery effect declarations"
	var sizes := {"outer":62,"actor_wrapper":10,"actor":437,"effect_wrapper":10,"constructor":173,"switch":52,"default":29,"ordinary":62,"void":89,"ice":82,"magma":85,"scale":357,"speed_setter":32,"threshold":4,"speed_scale":4} if architecture=="x86_64" else {"outer":42,"actor_wrapper":48,"actor":468,"effect_wrapper":14,"constructor":136,"switch":26,"default":36,"ordinary":64,"void":92,"ice":92,"magma":92,"scale":314,"speed_setter":30} if architecture=="armv7" else {}
	if sizes.is_empty() or data.provenance.size()!=sizes.size(): return "Invalid scenery effect provenance"
	var spans := []
	for key in sizes:
		var row: Variant = data.provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes): return "Invalid scenery effect extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x: return "Overlapping scenery effect extents"
		spans.append(span)
	var models: Variant = resources.get("provenance",{}).get("models")
	if not models is Dictionary or not Numbers.integer(models.get("offset"),0,executable_bytes) or not Numbers.integer(models.get("bytes"),1,executable_bytes): return "Missing scenery effect variant provenance"
	if data.provenance.outer.offset<models.offset+models.bytes or data.provenance.outer.offset>models.offset+4096: return "Disconnected scenery effect variants"
	if architecture=="armv7" and data.provenance.switch.offset!=data.provenance.constructor.offset+data.provenance.constructor.bytes: return "Disconnected scenery effect switch"
	return ""
