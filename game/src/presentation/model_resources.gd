extends RefCounted
## Stage source meshes and textures once, then instantiate independent materials
## over shared geometry. Call clear after assembly to release staging nodes.
const Tracks = preload("res://src/content/animation_tracks.gd")
const AEM = preload("res://src/content/aem.gd")
const Model = preload("res://src/presentation/imported_model.gd")
const Materials = preload("res://src/presentation/material_library.gd")
var error := ""
var _prototypes := {}
var _base := ""
var _binding := ""
var _quality := ""
var _static := false
var _source_uv := false

func prepare(paths: Array, library: RefCounted, visuals: RefCounted, bindings: RefCounted, quality := "high", require_static := false, source_uv := true) -> bool:
	clear()
	error = ""
	if library.manifest.get("content_id", "") != bindings.base_content_id or visuals.base_content_id != bindings.base_content_id:
		return reject("Model resources belong to different content identities")
	var images := {}
	var texture_cache := {}
	for path in paths:
		if _prototypes.has(path): continue
		var descriptor: Dictionary = bindings.material_for_mesh(path, quality)
		if descriptor.is_empty(): return reject(path.get_file() + ": " + bindings.error)
		if not Materials.supports(descriptor):
			return reject("%s: material mode %d is not implemented" % [path.get_file(), descriptor.render_type])
		var mode := int(descriptor.render_type)
		var texture_paths := [descriptor.texture_paths[0], descriptor.texture_paths[1] if mode == 28 else ""]
		for texture_path in texture_paths:
			if texture_path.is_empty() or images.has(texture_path): continue
			var image: Image = visuals.load_image(texture_path)
			if image == null: return reject(texture_path.get_file() + ": " + visuals.error)
			images[texture_path] = image
		var bytes: PackedByteArray = library.read_resource(path, AEM.MAX_BYTES)
		if bytes.is_empty(): return reject(path.get_file() + ": " + library.error)
		var reader := AEM.new()
		var decoded := reader.decode(bytes)
		if decoded.is_empty(): return reject(path.get_file() + ": " + reader.error)
		if require_static and not Tracks.has_identity_tracks(decoded.surfaces):
			return reject(path.get_file() + ": source animation semantics are not yet supported in this scene")
		var prototype := Model.new()
		prototype.build(decoded, images.get(texture_paths[0]), images.get(texture_paths[1]), mode, texture_cache, source_uv)
		_prototypes[path] = prototype
	_base=bindings.base_content_id
	_binding=bindings.binding_id
	_quality=quality
	_static=require_static
	_source_uv=source_uv
	return true

func covers(paths: Array, bindings: RefCounted, quality: String, require_static: bool, source_uv := true) -> bool:
	if _base!=bindings.base_content_id or _binding!=bindings.binding_id or _quality!=quality or (require_static and not _static) or _source_uv!=source_uv: return false
	for path in paths:
		if not _prototypes.has(path): return false
	return true

func instantiate(path: String) -> Node3D:
	if not _prototypes.has(path):
		error = "Model was not prepared: " + path
		return null
	var model := Model.new()
	model.copy_from(_prototypes[path])
	return model

func clear() -> void:
	for prototype in _prototypes.values(): prototype.free()
	_prototypes.clear()
	_base="";_binding="";_quality="";_static=false;_source_uv=false

func reject(message: String) -> bool:
	clear()
	error = message
	return false
