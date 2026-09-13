extends RefCounted
## The opening's one black fade, followed by its retained arrival plate. The
## session advances this timer before the mission owner can request a new fade.
const Frame=preload("res://src/simulation/opening_escape_frame.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const BlackFade=preload("res://src/simulation/black_fade.gd")
var error:=""
var _identity: RefCounted
var _state:={}

func configure(owner: RefCounted) -> bool:
	error="";_identity=null;_state={}
	if not owner is Frame or owner.presentation_identity()==null:return reject("Fade requires a configured opening escape")
	var escape: Dictionary=owner.snapshot()
	if escape.phase!=4:return reject("Configure the fade before the escape begins")
	_identity=owner.presentation_identity()
	_state={"base_content_id":escape.base_content_id,"binding_id":escape.binding_id,
		"requested":false,"active":false,"elapsed_ms":0,"duration_ms":0,"black_plate":false}
	return true

func advance(delta_ms: Variant) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(delta_ms,0,150):return reject("Fade requires ordinary frame milliseconds")
	BlackFade.advance(_state,delta_ms)
	return true

func apply_escape(owner: RefCounted) -> bool:
	error=""
	if not owner is Frame or _identity==null or owner.presentation_identity()!=_identity:return reject("Fade follows one configured escape")
	var escape: Dictionary=owner.snapshot()
	if escape.base_content_id!=_state.base_content_id or escape.binding_id!=_state.binding_id:return reject("Fade content identity changed")
	var request: Dictionary=escape.frame.get("fade_request",{})
	if not request.is_empty():
		if _state.requested or escape.phase!=16 or request!={"duration_ms":5000,"source_direction":1,"source_color_argument":255}:
			return reject("Unsupported opening fade request")
	if not escape.boundary.is_empty() and (escape.boundary!="arrival_transition_required" or not _state.requested or _state.active):
		return reject("Arrival requires the completed opening fade")
	if not request.is_empty():
		_state.requested=true;_state.active=true;_state.elapsed_ms=0;_state.duration_ms=request.duration_ms
	if not escape.boundary.is_empty():_state.black_plate=true
	return true

func is_active() -> bool:return _state.get("active",false)
func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true)
	result.alpha_byte=BlackFade.alpha(result)
	return result
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new();copy._identity=_identity;copy._state=_state.duplicate(true);return copy
func reject(message: String) -> bool:error=message;return false
