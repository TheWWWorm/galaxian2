extends RefCounted
## Atomic escape choreography, camera and retained effect orientation. Rendering,
## world replacement, audio and the fade remain explicit scene-owner work.
const Escape=preload("res://src/simulation/opening_escape.gd")
const Camera=preload("res://src/simulation/opening_escape_camera.gd")
const EffectPose=preload("res://src/presentation/scenery_effect_pose.gd")
var error:=""
var _escape: RefCounted
var _camera: RefCounted
var _state:={}

func configure(bindings: RefCounted, library: RefCounted) -> bool:
	error="";_escape=null;_camera=null;_state={}
	var escape:=Escape.new();var camera:=Camera.new()
	if not escape.configure(bindings,library):return reject(escape.error)
	if not camera.configure(bindings):return reject(camera.error)
	_escape=escape;_camera=camera
	_state=escape.snapshot()
	_state.model_rotation=Vector3.ZERO
	_state.effect_pose=Transform3D.IDENTITY
	_state.camera={};_state.immediate_view={};_state.random_state={}
	return true

func advance(delta_ms: Variant, radio: Dictionary, player_pose: Transform3D, preceding_view: Dictionary, context: Dictionary) -> bool:
	error=""
	if _escape==null or not context.get("random_state") is Dictionary or not context.get("fade_active") is bool:
		return reject("Escape frame requires its world stream and fade state")
	if not Camera.valid_view(preceding_view):return reject("Escape frame requires a preceding camera")
	var escape: RefCounted=_escape.fork_for_frame()
	if not escape.advance(delta_ms,radio,player_pose,preceding_view.pose,context.fade_active):return reject(escape.error)
	var next: Dictionary=escape.snapshot()
	next.model_rotation=_state.model_rotation+next.frame.model_rotation_delta
	next.effect_pose=Transform3D(_state.effect_pose.basis,next.effect.position)
	next.camera={};next.immediate_view={};next.random_state=context.random_state.duplicate(true)
	if next.phase>Escape.Stage.WAITING:
		var target: Transform3D=player_pose if next.frame.player_pose_override==null else next.frame.player_pose_override
		var views: Dictionary=_camera.evaluate(delta_ms,next,target,preceding_view,context.random_state)
		if views.is_empty():return reject(_camera.error)
		next.camera=views.camera;next.immediate_view=views.immediate_view;next.random_state=views.random_state
		var orientation: Dictionary=next.frame.effect_orientation
		if not orientation.is_empty():
			var backward: Vector3
			if orientation.view=="immediate":
				if views.immediate_view.is_empty():return reject("Hyperdrive orientation requires its immediate camera")
				backward=views.immediate_view.pose.basis.z
			else:backward=orientation.backward
			var right:=EffectPose.normalized(EffectPose.cross(orientation.up,backward))
			var up:=EffectPose.normalized(EffectPose.cross(backward,right))
			next.effect_pose.basis=Basis(right,up,backward)
	if not next.model_rotation.is_finite() or not next.effect_pose.is_finite():return reject("Escape presentation pose overflowed")
	_escape=escape;_state=next
	return true

func presentation_identity() -> RefCounted:return null if _escape==null else _escape.presentation_identity()
func snapshot() -> Dictionary:return _state.duplicate(true)
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	if _escape!=null:copy._escape=_escape.fork_for_frame()
	copy._camera=_camera;copy._state=_state.duplicate(true)
	return copy
func reject(message: String) -> bool:error=message;return false
