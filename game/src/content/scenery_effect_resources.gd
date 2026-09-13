extends RefCounted
## Source model pairs and integer playback ranges for fresh scenery effects.
## This provider retains only metadata, not decoded geometry or animation values.
## It does not establish interpolation, alpha orientation or rendering fidelity.
const AEM = preload("res://src/content/aem.gd")
const Definitions = preload("res://src/content/scenery_effect_definitions.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Library = preload("res://src/content/library.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const PATHS := [
	["resources/data/assets/main/3d/meshes/misc/asteroid_explosion_anim_alpha.aem",
	 "resources/data/assets/main/3d/meshes/misc/asteroid_01_explosion_anim.aem"],
	["resources/data/assets/main/3d/meshes/misc/asteroid_explosion_anim_alpha.aem",
	 "resources/data/assets/main/3d/meshes/misc/asteroid_void_explosion_anim.aem"],
	["resources/data/assets/valkyrie/3d/meshes/misc/v_asteroid_ice_explosion_anim_alpha.aem",
	 "resources/data/assets/valkyrie/3d/meshes/misc/v_asteroid_ice_explosion_anim.aem"],
	["resources/data/assets/supernova/3d/meshes/misc/sn_asteroid_magma_explosion_anim_alpha.aem",
	 "resources/data/assets/supernova/3d/meshes/misc/sn_asteroid_magma_explosion_anim.aem"]]
# The verified loader initializes its minimum-positive search at this value.
# Reject later-key layouts rather than infer a different range initialization.
const MAX_KEY_TIME := 1000000.0
var error := ""
var _state := {}

func configure(library: RefCounted, bindings: RefCounted) -> bool:
	clear()
	if library==null or bindings==null or bindings.get_script()!=Bindings:
		return reject("Scenery effects require a content library and resource bindings")
	var manifest: Variant = library.get("manifest")
	if not manifest is Dictionary or not library.has_method("read_resource"):
		return reject("Scenery effect content library is unavailable")
	if bindings.scenery_effects.is_empty() or not Definitions.parameters(bindings.scenery_effects,bindings.scenery_resources):
		return reject("Scenery effect declarations are unavailable or unsupported")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id) or manifest.get("content_id")!=bindings.base_content_id:
		return reject("Scenery effect resources belong to different content identities")
	var effects := {}
	var models := {}
	for variant_index in bindings.scenery_effects.variants.size():
		var variant: Dictionary = bindings.scenery_effects.variants[variant_index]
		var selected := []
		for model_index in 2:
			var id := int(variant.model_ids[model_index])
			var path: String = bindings.resolve(id,"mesh")
			if path.is_empty(): return reject(bindings.error)
			if path!=PATHS[variant_index][model_index]: return reject("Scenery effect model is outside the verified source set: "+path)
			if not models.has(id):
				var bytes: PackedByteArray = library.read_resource(path,AEM.MAX_BYTES)
				if bytes.is_empty(): return reject(path.get_file()+": "+library.error)
				var reader := AEM.new()
				var decoded := reader.decode(bytes)
				if decoded.is_empty(): return reject(path.get_file()+": "+reader.error)
				if decoded.version!=(4 if variant_index<2 else 5): return reject(path.get_file()+": unsupported effect mesh version")
				var timing := playback_range(decoded.surfaces)
				if timing.is_empty(): return reject(path.get_file()+": unsupported effect key timing")
				models[id]={"model_id":id,"resource":path,"start_ms":timing.start_ms,"end_ms":timing.end_ms}
			elif models[id].resource!=path: return reject("Scenery effect model identity is ambiguous")
			selected.append(models[id].duplicate(true))
		var effect := {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
			"base_model_id":int(variant.base_model_id),"effect_type":int(variant.effect_type),
			"models":selected,"duration_ms":maxi(selected[0].end_ms,selected[1].end_ms)}
		if not effect_parameters(effect,bindings): return reject("Invalid prepared scenery effect metadata")
		effects[effect.base_model_id]=effect
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"effects":effects}
	return true

func effect_for_model(base_model_id: Variant) -> Dictionary:
	error=""
	if _state.is_empty() or not base_model_id is int or not _state.effects.has(base_model_id):
		error="Scenery effect was not prepared for this base model"
		return {}
	return _state.effects[base_model_id].duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func clear() -> void:
	error="";_state={}

static func effect_parameters(effect: Variant, bindings: RefCounted) -> bool:
	if bindings==null or bindings.get_script()!=Bindings: return false
	if bindings.scenery_effects.is_empty() or not Definitions.parameters(bindings.scenery_effects,bindings.scenery_resources) or not effect is Dictionary or effect.size()!=6: return false
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id): return false
	for key in ["base_content_id","binding_id"]:
		if effect.get(key)!=bindings.get(key): return false
	if not effect.get("effect_type") is int or effect.effect_type<2 or effect.effect_type>5 or not effect.get("base_model_id") is int: return false
	var index: int = effect.effect_type-2
	var declaration: Dictionary = bindings.scenery_effects.variants[index]
	if effect.base_model_id!=int(declaration.base_model_id): return false
	var models: Variant = effect.get("models")
	if not models is Array or models.size()!=2: return false
	for model_index in 2:
		var model: Variant = models[model_index]
		if not model is Dictionary or model.size()!=4 or not model.get("model_id") is int or model.model_id!=int(declaration.model_ids[model_index]): return false
		if model.get("resource")!=PATHS[index][model_index]: return false
		if not model.get("start_ms") is int or not model.get("end_ms") is int or not Numbers.integer(model.start_ms,0,int(MAX_KEY_TIME)) or not Numbers.integer(model.end_ms,maxi(1,model.start_ms),int(MAX_KEY_TIME)): return false
	return effect.get("duration_ms") is int and effect.duration_ms==maxi(models[0].end_ms,models[1].end_ms)

static func playback_range(surfaces: Variant, allow_static:=false) -> Dictionary:
	if not surfaces is Array or surfaces.is_empty() or surfaces.size()>AEM.MAX_SUBMESHES: return {}
	var first := INF
	var last := 0
	var total_keys := 0
	for surface in surfaces:
		if not surface is Dictionary or not surface.get("tracks") is Dictionary: return {}
		for name in surface.tracks:
			var group: Variant = surface.tracks[name]
			if not group is Array: return {}
			var dimensions := 1
			if name in ["translation","rotation","scale"]:
				if group.size() not in [0,1,3]: return {}
				dimensions=3 if group.size()==1 else 1
			elif name=="scalar":
				if group.size()!=1: return {}
			elif name=="uv":
				if group.size()!=7: return {}
			else: return {}
			for track in group:
				if not track is Dictionary or not track.get("dimensions") is int or track.dimensions!=dimensions or not track.get("keys") is PackedFloat32Array: return {}
				var keys: PackedFloat32Array = track.keys
				if name=="uv" and not keys.is_empty(): return {}
				var stride := dimensions+1
				if keys.size()%stride!=0: return {}
				total_keys+=int(keys.size()/stride)
				if total_keys>AEM.MAX_KEYS: return {}
				var previous := -INF
				for offset in range(0,keys.size(),stride):
					var time: float = keys[offset]
					if not is_finite(time) or time<0.0 or time>MAX_KEY_TIME or time<previous: return {}
					previous=time
					if time>0.0: first=minf(first,time)
					last=maxi(last,int(time))
					for component in dimensions:
						if not is_finite(keys[offset+component+1]): return {}
	if total_keys==0 and allow_static:return {"start_ms":0,"end_ms":0}
	if not is_finite(first) or last<1: return {}
	return {"start_ms":int(first),"end_ms":last}

func reject(message: String) -> bool:
	clear();error=message;return false
