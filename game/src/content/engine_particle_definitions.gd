extends RefCounted
## Mac Betty nozzle content. Attachments remain in the original weapons table.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Damage=preload("res://src/content/damage_particle_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const VALUES = {"scope":"mac_betty_nozzle_particles","ship_id":0,"attachment_category":3,"nozzle_count":4,"first_preset":29,"scale_multiplier":1.5,"scale_limit":1.0,"initial_emitting":true,"material_type":3,"texture_id":24202,"preset":{"preset_id":29,"material_id":20090,"flags":17,"capacity":20,"size_jitter":0,"lifetime_ms":80,"even_spacing":1,"fade_in_ms":0,"size_growth_per_second":-1000,"scatter_xz":0,"scatter_y":0,"velocity_scatter":100,"animation_frames":0,"size":250.0,"distance_spacing":8.0,"relative_velocity_factor":0.800000011920929,"local_velocity_z":-4000.0,"local_offset_x":0.0,"local_offset_y":0.0,"local_offset_z":0.0,"local_offset_z_jitter":0.0,"minimum_squared_speed":1,"start_rgba":[221,221,221,255],"end_rgba":[0,0,0,0],"uv_rect":[0.005859375,0.005859375,0.119140625,0.119140625]}}
const SPANS = {"defaults":[483042,211],"basic_and_four_copies":[483319,2344],"nozzle_setup":[61403,694],"nozzle_constants":[1582362,32],"size_constant":[1575358,4],"speed_constant":[1575098,4],"hull_color":[1576010,4],"color_cases":[64294,36],"manager":[-43546,44],"attachment_positions":[-36633,278]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return Damage.sprite_preset(data.preset)

static func validate(data: Variant,source_bytes: int,arch: String,arrival: Dictionary,damage: Dictionary) -> String:
	if not data is Dictionary:return "Missing player exhaust declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Damage.emitter_parameters(damage):return "Unsupported player exhaust declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Player exhaust lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid player exhaust provenance"
	for key in SPANS:
		var span: Variant=data.provenance.get(key);var rule: Array=SPANS[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid player exhaust extent: "+key
	return ""

static func resolve(bindings: RefCounted,mounts: RefCounted,ship_id: Variant) -> Dictionary:
	if bindings==null or not mounts is Mounts:return {"error":"Player exhaust requires imported bindings and attachments"}
	if bindings.source_architecture!="x86_64" or not parameters(bindings.engine_particles):return {"error":"This content has no verified player exhaust"}
	var data: Dictionary=bindings.engine_particles
	if not Numbers.integer(ship_id,int(data.ship_id),int(data.ship_id)):return {"error":"Player exhaust for this hull is not supported"}
	var source: Dictionary=mounts.snapshot()
	if not Library.valid_hash(bindings.binding_id) or not Library.valid_hash(bindings.base_content_id) or source.get("base_content_id")!=bindings.base_content_id:return {"error":"Nozzle attachments belong to another content identity"}
	var groups: Array=source.get("ships",{}).get(int(ship_id),{}).get("groups",[])
	if groups.size()!=4 or groups[3].size()!=int(data.nozzle_count):return {"error":"Unsupported player nozzle attachment count"}
	var rows:=[]
	for index in groups[3].size():
		var mount: Dictionary=groups[3][index]
		var position: Variant=mount.get("position");var scale: Variant=mount.get("additional_vector")
		if mount.get("category")!=3 or mount.get("slot")!=index or not position is Vector3 or not position.is_finite() or not scale is Vector3 or not scale.is_finite() or scale.x<=0:return {"error":"Invalid player nozzle attachment"}
		var row: Dictionary=data.preset.duplicate(true)
		row.preset_id=int(data.first_preset)+index
		row.local_offset_x=position.x;row.local_offset_y=position.y;row.local_offset_z=position.z
		row.size=single(scale.x*float(data.preset.size))
		# Source lifetime and local speed use double precision before truncation
		# or the final float store. The nozzle's X scale drives both values.
		var factor:=minf(float(data.scale_limit),float(scale.x)*float(data.scale_multiplier))
		row.lifetime_ms=int(factor*float(data.preset.lifetime_ms))
		row.local_velocity_z=single(factor*float(data.preset.local_velocity_z))
		if not Damage.sprite_preset(row):return {"error":"Player nozzle exceeds supported particle bounds"}
		rows.append(row)
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"ship_id":int(ship_id),"presets":rows,"attachment_provenance":source.provenance.duplicate(true)}

static func single(value: float) -> float:
	var bytes:=PackedByteArray();bytes.resize(4);bytes.encode_float(0,value);return bytes.decode_float(0)
