extends RefCounted
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const COUNTS := {"sun_textures":19,"near_textures":27,"far_textures":27}

static func parameters(data: Dictionary) -> bool:
	if data.get("scope")!="fresh_opening_planet_resources":return false
	for key in ["mesh_id","opening_texture_id"]:
		if not Numbers.integer(data.get(key),0,65533):return false
	for key in COUNTS:
		var rows: Variant=data.get(key)
		if not rows is Array or rows.size()!=COUNTS[key]:return false
		for value in rows:
			if not Numbers.integer(value,0,65533):return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary:return "Missing planet resource declarations"
	if data.is_empty():return ""
	if not parameters(data):return "Invalid planet resource parameters"
	var sizes:={"sun":61,"current":64,"near":61,"far":66,"mesh":50,"system":13,"sky_index":9,"cursor":12,"planet_type":9} if architecture=="x86_64" else {"sun":48,"current":56,"near":60,"far":58,"mesh":40,"system":6,"sky_index":4,"cursor":6,"planet_type":4} if architecture=="armv7" else {}
	if sizes.is_empty():return "Unsupported planet resource architecture"
	for key in COUNTS:sizes[key]=COUNTS[key]*4
	var provenance: Variant=data.get("provenance")
	if not provenance is Dictionary or provenance.size()!=sizes.size():return "Invalid planet resource provenance"
	var spans:=[]
	for key in sizes:
		var row: Variant=provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes):return "Invalid planet resource extent: "+key
		var begin:=int(row.offset);var end:=begin+int(row.bytes)
		for span in spans:
			if begin<span.y and end>span.x:return "Overlapping planet resource declarations"
		spans.append(Vector2i(begin,end))
	var p: Dictionary=provenance
	if int(p.sun.offset)+int(p.sun.bytes)>mini(int(p.current.offset),int(p.near.offset)) or maxi(int(p.current.offset)+int(p.current.bytes),int(p.near.offset)+int(p.near.bytes))>int(p.far.offset) or int(p.far.offset)>=int(p.mesh.offset) or int(p.mesh.offset)+int(p.mesh.bytes)-int(p.sun.offset)>=4096:
		return "Unlinked planet resource declarations"
	return ""
