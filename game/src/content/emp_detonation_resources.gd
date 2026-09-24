extends RefCounted
## Original single-model EMP burst metadata. Geometry and audio remain local
## imported content; this provider never creates equipment or mission progress.
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Ownership = preload("res://src/content/secondary_ownership_definitions.gd")
const AEM = preload("res://src/content/aem.gd")
const Timing = preload("res://src/content/scenery_effect_resources.gd")
const MODEL_ID := 16805
const MODEL_PATH := "resources/data/assets/main/3d/meshes/fx/explosion_emp_anim_lookat_add.aem"
const ITEM_IDS := [41, 42, 43]
const SOUND_IDS := [15, 16, 17]
const CAMERA_RANGE := 30000.0
const CAMERA_DECAY_MS := 2000
const CAMERA_SPREAD := 50
var error := ""
var _state := {}

func configure(library: RefCounted, bindings: RefCounted) -> bool:
	_state = {}; error = ""
	if not library is Library or not bindings is Bindings or not Ownership.available(bindings):
		return reject("EMP detonation requires supported secondary content")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id) or library.manifest.get("content_id") != bindings.base_content_id:
		return reject("EMP detonation resources belong to another content identity")
	if bindings.resolve(MODEL_ID, "mesh") != MODEL_PATH or bindings.material_for_mesh(MODEL_PATH, "high").get("render_type") != 2:
		return reject("EMP detonation lost its original additive model mapping")
	var bytes: PackedByteArray = library.read_resource(MODEL_PATH, AEM.MAX_BYTES)
	if bytes.is_empty(): return reject(library.error)
	var reader := AEM.new()
	var mesh: Dictionary = reader.decode(bytes)
	if mesh.is_empty(): return reject(reader.error)
	if mesh.get("version") != 4: return reject("Unsupported EMP detonation mesh version")
	var timing := Timing.playback_range(mesh.surfaces)
	if timing.is_empty(): return reject("Unsupported EMP detonation animation timing")
	_state = {"base_content_id": bindings.base_content_id, "binding_id": bindings.binding_id,
		"effect_type": 7, "models": [{"model_id": MODEL_ID, "resource": MODEL_PATH,
		"start_ms": timing.start_ms, "end_ms": timing.end_ms}], "duration_ms": timing.end_ms}
	return true

func snapshot() -> Dictionary: return _state.duplicate(true)
func reject(message: String) -> bool: error = message; return false
