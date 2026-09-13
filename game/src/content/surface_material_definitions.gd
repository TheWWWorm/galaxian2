extends RefCounted
const Fonts = preload("res://src/content/font_definitions.gd")
const ROLES := ["ambient", "diffuse", "specular", "power"]

static func number(value: Variant, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value>=0 and value<=maximum

static func parameters(data: Dictionary) -> bool:
	for key in ["ambient_rgb", "diffuse_rgb", "specular_rgb"]:
		var row: Variant = data.get(key)
		if not row is Array or row.size()!=3:return false
		for value in row:
			if not number(value,16):return false
	return number(data.get("specular_power"),1024) and data.specular_power>0

static func validate(data: Variant, executable_bytes: int, architecture: String, colors: Dictionary) -> String:
	if not data is Dictionary:return "Missing surface material declarations"
	if data.is_empty():return ""
	if data.size()!=6 or not parameters(data):return "Invalid surface material parameters"
	var mac := architecture=="x86_64"
	var sizes := {"setup":118,"rim":48,"renderer":21,"ambient":70,"diffuse":70,"specular":70,"power":34} if mac else {"setup":90,"rim":80,"renderer":14,"ambient":92,"diffuse":92,"specular":92,"power":44} if architecture=="armv7" else {}
	var provenance: Variant = data.get("provenance")
	var sources: Variant = data.get("value_sources")
	if sizes.is_empty() or not provenance is Dictionary or provenance.size()!=sizes.size() or not sources is Dictionary or sources.size()!=4:return "Invalid surface material provenance"
	var spans := []
	for key in sizes:
		var row: Variant = provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes):return "Invalid surface material extent: "+key
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		for previous in spans:
			if span.x<previous.y and span.y>previous.x:return "Overlapping surface material contexts"
		spans.append(span)
	if provenance.rim!=colors.get("provenance",{}).get("rim") or int(provenance.setup.offset)!=int(provenance.rim.offset)+int(provenance.rim.bytes):return "Surface material is not linked to the active environment setup"
	var value_spans := []
	var arm_offsets := {"ambient":8,"diffuse":32,"specular":56,"power":80}
	for role in ROLES:
		var row: Variant = sources.get(role)
		if not Fonts.extent(row,"offset","bytes",[4 if mac else 6 if role=="power" else 12],executable_bytes):return "Invalid material value extent: "+role
		var span := Vector2i(int(row.offset),int(row.offset)+int(row.bytes))
		if mac:
			for context in spans:
				if span.x<context.y and span.y>context.x:return "Material constant overlaps a code context"
			for previous in value_spans:
				if span!=previous and span.x<previous.y and span.y>previous.x:return "Partially overlapping material constants"
		else:
			if int(row.offset)!=int(provenance.setup.offset)+arm_offsets[role]:return "Material immediate is outside its setup field"
		value_spans.append(span)
	return ""
