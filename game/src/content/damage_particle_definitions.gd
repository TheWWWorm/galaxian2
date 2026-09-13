extends RefCounted
## Two supported sprite presets. v70 also supplies proven emitter defaults.
const Numbers=preload("res://src/content/opening_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Owners=preload("res://src/content/damage_particle_owner_definitions.gd")
const FLOATS=["size","emission_per_second","relative_velocity_factor","local_velocity_z","local_offset_y","local_offset_z","local_offset_z_jitter"]

static func preset(row: Variant) -> bool:
	# Preserve the existing smoke/fire contract. Manual sprites are accepted only
	# by the shared appearance validator and their separate content owner.
	return sprite_preset(row) and row.flags==0x02000021 and row.even_spacing==1

static func sprite_preset(row: Variant) -> bool:
	if not row is Dictionary or row.size()!=23:return false
	if not Numbers.integer(row.get("preset_id"),0,47) or not Numbers.integer(row.get("material_id"),0,65534):return false
	if not Numbers.integer(row.get("flags"),0x02000021,0x02000101) or not Numbers.integer(row.get("even_spacing"),0,1):return false
	if not ((row.flags==0x02000021 and row.even_spacing==1) or (row.flags==0x02000101 and row.even_spacing==0)):return false
	for rule in [["capacity",1,4096],["lifetime_ms",1,60000],["size_jitter",0,32767],["size_growth_per_second",-32768,32767],["scatter_xz",0,32767],["scatter_y",0,32767],["velocity_scatter",0,32767],["animation_frames",1,256]]:
		if not Numbers.integer(row.get(rule[0]),rule[1],rule[2]):return false
	if not Numbers.integer(row.get("fade_in_ms"),0,int(row.lifetime_ms)):return false
	for key in FLOATS:
		var value: Variant=row.get(key)
		if not (value is float or value is int) or not is_finite(value) or absf(value)>1e6:return false
	if row.size<=0 or row.size+row.size_jitter>32767 or row.emission_per_second<=0 or row.emission_per_second>10000 or row.local_offset_z_jitter<0:return false
	for key in ["start_rgba","end_rgba"]:
		var color: Variant=row.get(key)
		if not color is Array or color.size()!=4:return false
		for value in color:
			if not Numbers.integer(value,0,255):return false
	var rect: Variant=row.get("uv_rect")
	if not rect is Array or rect.size()!=4:return false
	for value in rect:
		if not (value is float or value is int) or not is_finite(value):return false
	return rect[0]>=0 and rect[0]<rect[2] and rect[2]<=1 and rect[1]>=0 and rect[1]<rect[3] and rect[3]<=1 and (rect[2]-rect[0])*(rect[3]-rect[1])*row.animation_frames<=1.000001

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.get("scope")!="damage_particle_sprite_presets":return false
	var rows: Variant=data.get("presets")
	if not rows is Array or rows.size()!=2:return false
	for index in 2:
		if not preset(rows[index]) or rows[index].preset_id!=[15,42][index]:return false
	return rows[0].material_id!=rows[1].material_id

static func emitter_parameters(data: Variant) -> bool:
	if not parameters(data):return false
	var defaults: Variant=data.get("emitter_defaults")
	var shape:={"auxiliary_sizes":2,"velocity_size_factor":0,"initial_fade_ms":0,"velocity_base":3,"local_velocity_xy":2,"local_offset_x":0,"minimum_squared_speed":0}
	if not defaults is Dictionary or defaults.size()!=shape.size():return false
	for key in shape:
		var values: Variant=defaults.get(key)
		if shape[key]>0:
			if not values is Array or values.size()!=shape[key]:return false
		else:values=[values]
		for value in values:
			if not (value is float or value is int) or value!=0:return false
	return true

static func validate(data: Variant,executable_bytes: int,architecture: String) -> String:
	if not data is Dictionary:return "Missing damage particle sprite declarations"
	if data.is_empty():return ""
	if not parameters(data):return "Invalid damage particle sprite parameters"
	if data.has("owners"):
		var owner_error:=Owners.validate(data.owners,executable_bytes,architecture)
		if not owner_error.is_empty():return owner_error
	var sizes:={"presets":616,"smoke_material":41,"fire_material":41} if architecture=="x86_64" else {"presets":454,"smoke_material":48,"fire_material":30} if architecture=="armv7" else {}
	if sizes.is_empty():return "Unsupported damage particle architecture"
	if data.has("emitter_defaults"):
		if not emitter_parameters(data):return "Unsupported damage particle emitter defaults"
		sizes.defaults=278 if architecture=="x86_64" else 230
	var provenance: Variant=data.get("provenance")
	if not provenance is Dictionary or provenance.size()!=sizes.size():return "Invalid damage particle provenance"
	var spans:=[]
	for key in sizes:
		var row: Variant=provenance.get(key)
		if not Fonts.extent(row,"offset","bytes",[sizes[key]],executable_bytes):return "Invalid damage particle extent: "+key
		var begin:=int(row.offset);var end:=begin+int(row.bytes)
		for span in spans:
			if begin<span.y and end>span.x:return "Overlapping damage particle declarations"
		spans.append(Vector2i(begin,end))
	return ""
