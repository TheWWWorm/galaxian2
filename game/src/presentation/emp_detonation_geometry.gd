extends Node3D
## Original animated additive EMP burst. Simulation owns its lifetime; rejected
## samples never alter the visible mesh, animation state or material parameters.
const Burst = preload("res://src/simulation/emp_detonation.gd")
const Resources = preload("res://src/content/emp_detonation_resources.gd")
const Models = preload("res://src/presentation/model_resources.gd")
const Sampler = preload("res://src/presentation/scenery_animation.gd")
const Billboard = preload("res://src/presentation/scenery_effect_pose.gd")
const Colors = preload("res://src/presentation/effect_color.gd")
const Additive = preload("res://src/presentation/effect_additive.gdshader")
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var model: Node3D
var _sampler: RefCounted
var _identity: RefCounted
var _descriptor := {}
var _edition := ""
var _generation: RefCounted
var _revision := 0

func build(burst: RefCounted, library: RefCounted, visuals: RefCounted, bindings: RefCounted) -> bool:
	clear()
	if not burst is Burst or burst.presentation_identity() == null: return reject("EMP geometry requires its retained burst owner")
	var state: Dictionary = burst.snapshot()
	if library == null or visuals == null or bindings == null or library.manifest.get("content_id") != state.base_content_id or visuals.base_content_id != state.base_content_id or bindings.base_content_id != state.base_content_id or bindings.binding_id != state.binding_id:
		return reject("EMP burst geometry belongs to another content identity")
	var resources := Resources.new()
	if not resources.configure(library, bindings): return reject(resources.error)
	var data := resources.snapshot()
	var timing: Dictionary = state.effect.models[0]
	for key in ["model_id", "resource", "start_ms", "end_ms"]:
		if timing.get(key) != data.models[0][key]: return reject("EMP burst geometry changed its original animation metadata")
	if state.effect.duration_ms != data.duration_ms: return reject("EMP burst geometry changed its duration")
	var edition: Variant = library.manifest.get("profile", {}).get("edition")
	if edition not in ["mac-full-hd", "ios-hd"]: return reject("Unsupported EMP burst content edition")
	var models := Models.new()
	if not models.prepare([Resources.MODEL_PATH], library, visuals, bindings, "high", false, true): return reject(models.error)
	model = models.instantiate(Resources.MODEL_PATH)
	models.clear()
	if model == null: return reject("Original EMP burst could not be instantiated")
	add_child(model); model.set_meta("source_resource_id", Resources.MODEL_ID)
	_sampler = Sampler.new()
	if not _sampler.configure(model.surfaces): return reject(_sampler.error)
	if _sampler.snapshot().range != {"start_ms": timing.start_ms, "end_ms": timing.end_ms}: return reject("EMP sampler changed its playback range")
	for index in model.surfaces.size():
		var surface: Dictionary = model.surfaces[index]
		if surface.uvs.is_empty() or surface.normals.is_empty() or not surface.colors.is_empty(): return reject("Unsupported EMP burst vertex attributes")
		var material := ShaderMaterial.new()
		material.shader = Additive
		material.set_shader_parameter("diffuse_texture", model.materials[index].get_shader_parameter("diffuse_texture"))
		model.materials[index] = material; model.instances[index].material_override = material
		# The sampled root is already in world space, including camera roll.
		model.instances[index].top_level = true
	_identity = burst.presentation_identity(); _descriptor = state; _edition = edition
	_generation = RefCounted.new()
	visible = false
	return true

func prepare_effect(burst: RefCounted, camera: Transform3D, parent_rgba: PackedByteArray, global_tint: Vector4, darken: Variant) -> Dictionary:
	error = ""
	if _identity == null or not burst is Burst or burst.presentation_identity() != _identity: return failed("EMP geometry follows one retained burst generation")
	var state: Dictionary = burst.snapshot()
	for key in ["base_content_id", "binding_id", "item_id"]:
		if state.get(key) != _descriptor[key]: return failed("EMP burst identity changed")
	var effect: Variant = state.get("effect")
	if not effect is Dictionary or not effect.get("active") is bool or not effect.get("models") is Array or effect.models.size() != 1 or effect.get("duration_ms") != _descriptor.effect.duration_ms:
		return failed("EMP burst changed its single-model effect")
	var clock: Variant = effect.models[0]
	if not clock is Dictionary: return failed("EMP burst has no animation clock")
	for key in ["model_id", "resource", "start_ms", "end_ms"]:
		if clock.get(key) != _descriptor.effect.models[0][key]: return failed("EMP burst changed its prepared model")
	if not Numbers.integer(effect.get("elapsed_ms"), 0, effect.duration_ms) or not Numbers.integer(clock.get("time_ms"), clock.start_ms, clock.end_ms) or not clock.get("playing") is bool:
		return failed("EMP burst has an invalid animation time")
	if not camera.is_finite() or Colors.tint(parent_rgba, global_tint).is_empty() or not (darken is float or darken is int) or not is_finite(darken) or not is_finite(Colors.single(darken)):
		return failed("Invalid EMP burst camera or color")
	if not effect.active: return {"generation": _generation, "revision": _revision + 1, "visible": false}
	if not effect.get("position") is Vector3: return failed("EMP burst has no finite position")
	var root := Billboard.alpha_root(camera, effect.position, 1.0)
	if root.has("error"): return failed(root.error)
	var sampler: RefCounted = _sampler.fork_for_frame()
	var sampled: Dictionary = sampler.sample(clock.time_ms, root.pose)
	if sampled.is_empty(): return failed(sampler.error)
	for surface in sampled.surfaces:
		var color := Colors.tint(parent_rgba, global_tint, surface.get("color_byte", -1))
		if color.is_empty(): return failed("EMP burst exceeded source color precision")
		surface.tint = color.value
	return {"generation": _generation, "revision": _revision + 1,
		"visible": true, "sampler": sampler, "surfaces": sampled.surfaces,
		"darken": Colors.single(darken) if _edition == "mac-full-hd" else 1.0}

func commit_effect(prepared: Dictionary) -> void:
	error = ""
	# A retained frame must not revive a retired effect or address replaced
	# meshes after clear/build, even when the same simulation owner is reused.
	if _generation == null or prepared.get("generation") != _generation or prepared.get("revision") != _revision + 1:
		error = "EMP geometry cannot commit a stale prepared frame"; return
	_revision += 1
	visible = prepared.visible
	if not visible: return
	for index in model.instances.size():
		var row: Dictionary = prepared.surfaces[index]
		model.instances[index].transform = row.pose
		model.materials[index].set_shader_parameter("effect_tint", row.tint)
		model.materials[index].set_shader_parameter("darken_value", prepared.darken)
	_sampler = prepared.sampler

func clear() -> void:
	if is_instance_valid(model): model.free()
	model = null; _sampler = null; _identity = null; _descriptor = {}; _edition = ""; error = ""; visible = false
	_generation = null; _revision = 0
func reject(message: String) -> bool: clear(); error = message; return false
func failed(message: String) -> Dictionary: error = message; return {}
