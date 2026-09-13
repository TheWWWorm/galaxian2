extends RefCounted
## Prospective fixed-camera passes for the fresh escape. The world supplies its
## shared random stream; a failed view never consumes the caller's stream.
const Definitions=preload("res://src/content/opening_escape_camera_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const CameraView=preload("res://src/simulation/camera_view.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Poses=preload("res://src/simulation/opening_player_motion.gd")
var error:=""
var _identity:={}
var _rules:={}

func configure(bindings: RefCounted) -> bool:
	error="";_identity={};_rules={}
	if bindings==null or not Definitions.parameters(bindings.opening_staging.get("escape_camera",{})):
		return reject("Fresh escape camera declarations are unavailable")
	if bindings.opening_staging.get("escape",{}).is_empty() or not bindings.opening_camera.get("inherit_target_up",false):
		return reject("Escape camera requires its choreography and target up")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id):return reject("Escape camera identity is unavailable")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_rules=bindings.opening_staging.escape_camera.duplicate(true)
	return true

func evaluate(delta_ms: Variant, escape: Dictionary, player_pose: Transform3D, preceding_view: Dictionary, random_state: Dictionary) -> Dictionary:
	error=""
	if _identity.is_empty() or not Numbers.integer(delta_ms,0,150):return fail("Escape camera requires an ordinary frame")
	for key in _identity:
		if escape.get(key)!=_identity[key] or preceding_view.get(key)!=_identity[key]:return fail("Escape camera belongs to another opening")
	if not Numbers.integer(escape.get("phase"),5,16) or not Poses.valid_pose(player_pose):return fail("Invalid escape camera phase or player pose")
	if not valid_parameters(escape):return fail("Invalid escape camera eye or shake parameters")
	if not valid_view(preceding_view):return fail("Escape camera requires its preceding view")
	var operations: Variant=escape.get("frame",{}).get("camera_operations")
	if not operations is Array or operations.size()>1:return fail("Unsupported immediate escape camera operations")
	var random:=Random.new()
	if not random.restore(random_state):return fail(random.error)
	var prior:=preceding_view.duplicate(true)
	var immediate:={}
	for operation in operations:
		if not operation is Dictionary or operation.get("immediate")!=true:return fail("Invalid immediate escape camera pass")
		immediate=resolve(operation,player_pose,random)
		if immediate.is_empty():return {}
		prior=immediate
	if int(delta_ms)>=int(_rules.ordinary_minimum_ms):
		prior=resolve(escape,player_pose,random)
		if prior.is_empty():return {}
	# A zero-time ordinary frame retains the preceding renderer view, even when
	# the controller cut its stored eye. A pan's immediate pass still runs.
	var shot:=_identity.duplicate()
	shot.merge({"phase":int(escape.phase),"mode":"fixed_eye","target":"player","actor_id":-1,
		"eye":escape.eye,"inherit_target_up":true})
	return {"camera":{"shot":shot,"view":prior},"immediate_view":immediate,"random_state":random.snapshot()}

func resolve(parameters: Dictionary, player_pose: Transform3D, random: RefCounted) -> Dictionary:
	if not valid_parameters(parameters):return fail("Invalid escape camera eye or shake parameters")
	var eye: Variant=parameters.get("eye")
	var strength: Variant=parameters.get("shake_strength")
	var radius: Variant=parameters.get("shake_radius")
	var look:=player_pose.origin
	if strength>0:
		for axis in _rules.look_shake_axes:
			var draw: int=random.next_int(int(radius)*int(_rules.random_bound_radius_multiplier))-int(radius)
			if not random.error.is_empty():return fail(random.error)
			look[int(axis)]=single(look[int(axis)]+single(single(float(strength)*float(draw))*float(_rules.look_shake_scale)))
	var view:=CameraView.fixed_eye(eye,Transform3D(player_pose.basis,look),_rules.inherit_target_up)
	if view.has("error"):return fail(view.error)
	var result:=_identity.duplicate()
	result.merge({"eye":eye,"look":look,"pose":view.pose,"mode":"fixed_eye"})
	return result

static func valid_view(view: Dictionary) -> bool:
	return view.get("pose") is Transform3D and Poses.valid_pose(view.pose) and view.get("eye") is Vector3 and view.eye==view.pose.origin and view.get("look") is Vector3 and view.look.is_finite()
static func valid_parameters(parameters: Dictionary) -> bool:
	var eye: Variant=parameters.get("eye")
	var strength: Variant=parameters.get("shake_strength")
	var radius: Variant=parameters.get("shake_radius")
	return eye is Vector3 and eye.is_finite() and (strength is int or strength is float) and is_finite(strength) and strength>=0.0 and strength<=1.0 and Numbers.integer(radius,0,20) and radius in [0,20] and (strength==0 or radius>0)
static func single(value: float) -> float:return PackedFloat32Array([value])[0]
func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}
