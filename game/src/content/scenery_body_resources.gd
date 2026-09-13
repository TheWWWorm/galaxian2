extends RefCounted
## Collision radii for the verified static scenery bases, read from authored
## AEM spheres. Render bounds and LOD alternatives do not define body radii.
const AEM = preload("res://src/content/aem.gd")
const Tracks = preload("res://src/content/animation_tracks.gd")
const Library = preload("res://src/content/library.gd")
const Definitions = preload("res://src/content/scenery_resource_definitions.gd")
const BASE_PATHS := [
	"resources/data/assets/main/3d/meshes/misc/asteroid_01.aem",
	"resources/data/assets/main/3d/meshes/misc/asteroid_void.aem",
	"resources/data/assets/valkyrie/3d/meshes/misc/v_asteroid_ice.aem",
	"resources/data/assets/supernova/3d/meshes/misc/sn_asteroid_magma.aem"]
const VERSIONS := [4,4,5,5]
var error := ""
var _state := {}

func configure(library: RefCounted, bindings: RefCounted) -> bool:
	clear()
	if library==null or bindings==null or not Definitions.parameters(bindings.scenery_resources):
		return reject("Scenery bodies require source resource declarations")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id) or library.manifest.get("content_id")!=bindings.base_content_id:
		return reject("Scenery body resources belong to different content identities")
	var radii := {}
	for index in BASE_PATHS.size():
		var id := int(bindings.scenery_resources.model_ids[index])
		if radii.has(id):return reject("Scenery base models must be distinct")
		var path: String = bindings.resolve(id,"mesh")
		if path.is_empty():return reject(bindings.error)
		if path!=BASE_PATHS[index]:return reject("Scenery body model is outside the verified base set: "+path)
		var bytes: PackedByteArray = library.read_resource(path,AEM.MAX_BYTES)
		if bytes.is_empty():return reject(path.get_file()+": "+library.error)
		var reader := AEM.new()
		var decoded := reader.decode(bytes)
		if decoded.is_empty():return reject(path.get_file()+": "+reader.error)
		if decoded.version!=VERSIONS[index] or decoded.surfaces.size()!=1:
			return reject(path.get_file()+": unsupported scenery sphere layout")
		var surface: Dictionary = decoded.surfaces[0]
		if surface.pivot!=Vector3.ZERO or not Tracks.has_identity_tracks(decoded.surfaces):
			return reject(path.get_file()+": transformed scenery body bounds are not supported")
		var sphere: Vector4 = surface.sphere
		if not sphere.is_finite() or sphere.w<=0.0:
			return reject(path.get_file()+": invalid scenery body radius")
		radii[id]=sphere.w
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"radii":radii}
	return true

func model_radius(model_id: Variant) -> float:
	error=""
	if _state.is_empty() or not model_id is int or not _state.radii.has(model_id):
		error="Scenery base model radius was not prepared"
		return -1.0
	return _state.radii[model_id]

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func clear() -> void:
	_state={};error=""

func reject(message: String) -> bool:
	clear();error=message;return false
