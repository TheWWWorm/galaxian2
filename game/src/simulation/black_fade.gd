extends RefCounted
## Shared source black-fade arithmetic. Scene owners validate request ordering
## and adopt these states only after their prospective world frame succeeds.
const Numbers=preload("res://src/content/opening_definitions.gd")
const Colors=preload("res://src/presentation/effect_color.gd")

static func start(state: Dictionary, request: Dictionary) -> bool:
	if request.size()!=3 or not Numbers.integer(request.get("duration_ms"),5000,5000) or not Numbers.integer(request.get("source_direction"),0,1) or not Numbers.integer(request.get("source_color_argument"),255,255):return false
	state.active=true;state.elapsed_ms=0;state.duration_ms=int(request.duration_ms);state.source_direction=int(request.source_direction)
	return true

static func advance(state: Dictionary, delta_ms: Variant) -> bool:
	if not Numbers.integer(delta_ms,0,150) or not state.get("active") is bool:return false
	if state.active:
		state.elapsed_ms+=int(delta_ms)
		if state.elapsed_ms>state.duration_ms:
			state.active=false;state.elapsed_ms=0
	return true

static func alpha(state: Dictionary) -> int:
	if state.get("black_plate",false):return 255
	if not state.get("active",false):return 0
	var fraction:=Colors.single(float(state.elapsed_ms)/float(state.duration_ms))
	if state.get("source_direction",1)==0:fraction=Colors.single(1.0-fraction)
	fraction=minf(1.0,fraction)
	return int(Colors.single(fraction*255.0)) if fraction>0 else 0
