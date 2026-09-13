extends RefCounted
## Stateless cinematic flight. Current scene pose remains the sole authority;
## scripted relocation happens later in the opening controller's own pass.
const EscapeDefinitions=preload("res://src/content/opening_escape_definitions.gd")
const Definitions = preload("res://src/content/opening_player_motion_definitions.gd")
const Cruise = preload("res://src/simulation/cruise_motion.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var _identity := {}
var _rules := {}
var _cruise: RefCounted
var _escape_rules:={}

func configure(bindings: RefCounted) -> bool:
	error="";_identity={};_rules={};_cruise=null;_escape_rules={}
	if bindings==null: return reject("Scripted player motion requires content bindings")
	var rules: Variant=bindings.opening_staging.get("player_motion",{})
	if not Definitions.parameters(rules): return reject("This content profile has no supported scripted player motion")
	var cruise := Cruise.new()
	if not cruise.configure(bindings,bindings.base_content_id): return reject(cruise.error)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_rules=rules.duplicate(true);_cruise=cruise
	if EscapeDefinitions.parameters(bindings.opening_staging.get("escape",{})):_escape_rules=bindings.opening_staging.escape.duplicate(true)
	return true

func evaluate(scene: Dictionary, phase: Variant, delta_ms: Variant) -> Dictionary:
	error=""
	if _identity.is_empty(): return fail("Configure scripted player motion before updating")
	for key in _identity:
		if scene.get(key)!=_identity[key]: return fail("Scripted player motion belongs to another scene")
	if not Numbers.integer(phase,0,int(_rules.release_phase)-1) or not Numbers.integer(delta_ms,0,150):
		return fail("Scripted player motion requires an ordinary frame before the handoff")
	var prior: Variant=scene.get("player_pose")
	if not prior is Transform3D or not valid_pose(prior): return fail("Scripted player pose must be a finite proper rotation")
	# This path uses the current cruise speed directly, without throttle or input
	# steering. The same source forward-vector helper serves ordinary cruise.
	var pose: Transform3D=_cruise.advance(prior,1.0,float(delta_ms)/1000.0)
	if not _cruise.error.is_empty(): return fail(_cruise.error)
	var result := _identity.duplicate()
	result.prior_pose=prior;result.pose=pose
	return result

func evaluate_escape(scene: Dictionary, escape: Dictionary, delta_ms: Variant) -> Dictionary:
	error=""
	if _escape_rules.is_empty() or not Numbers.integer(delta_ms,0,150) or not Numbers.integer(escape.get("phase"),5,16):return fail("Unsupported escape player motion")
	for key in _identity:
		if scene.get(key)!=_identity[key] or escape.get(key)!=_identity[key]:return fail("Escape movement belongs to another opening")
	var speed: Variant=escape.get("cruise_speed")
	if not (speed is int or speed is float) or not is_finite(speed) or speed<0.0 or speed>_escape_rules.initial_cruise_speed:return fail("Unsupported escape cruise speed")
	var prior: Variant=scene.get("player_pose")
	if not prior is Transform3D or not valid_pose(prior):return fail("Invalid escape movement pose")
	var pose: Transform3D=_cruise.advance(prior,float(speed)/float(_escape_rules.initial_cruise_speed),float(delta_ms)/1000.0)
	if not _cruise.error.is_empty():return fail(_cruise.error)
	var result:=_identity.duplicate()
	result.prior_pose=prior;result.pose=pose
	return result

static func valid_pose(pose: Transform3D) -> bool:
	return pose.is_finite() and pose.basis.is_equal_approx(pose.basis.orthonormalized()) and pose.basis.determinant()>0.0

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
