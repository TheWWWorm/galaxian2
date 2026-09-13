extends RefCounted
## Authored first-station orientation and independent native sinusoidal drift.
## Camera randomness is isolated from campaign, combat and audio state.
const Definitions=preload("res://src/content/station_presentation_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var error:=""
var _rules:={}
var _random: RefCounted
var _axes: Array=[]
var _position:=Vector3.ZERO
var _basis:=Basis.IDENTITY
var _elapsed_ms:=0

func configure(data: Dictionary, seed_value: int) -> bool:
	error="";_rules={};_axes=[];_elapsed_ms=0
	if not Definitions.parameters(data):return reject("Station camera declarations are unavailable")
	_rules=data.camera.duplicate(true)
	_random=Random.new();_random.seed_from(seed_value)
	_position=vector(_rules.position)
	_basis=Basis.from_euler(vector(_rules.angles),EULER_ORDER_YXZ)
	var y_negative: bool=_random.next_int(20)<10
	var x_negative: bool=_random.next_int(20)>10
	var z_negative: bool=_random.next_int(20)<10
	var flags: Array=[x_negative,y_negative,z_negative]
	for axis in 3:
		var base: float=_rules.position[axis]
		_axes.append({"start":base,"target":base,"phase":float(_rules.phase_start),"negative":flags[axis]})
		_position[axis]+=float(_random.next_int(int(_rules.initial_jitter_bound)))*(-1.0 if flags[axis] else 1.0)
	return true

func advance(milliseconds: int) -> bool:
	error=""
	if _rules.is_empty() or milliseconds<0 or milliseconds>int(_rules.max_frame_ms):return reject("Invalid station camera frame")
	for axis in 3:
		var row: Dictionary=_axes[axis]
		var direction: float=(-1.0 if row.negative else 1.0)*(1.0 if axis==0 else -1.0)
		row.phase=f32(minf(f32(row.phase+milliseconds*direction*_rules.phase_rate),_rules.phase_limit))
		# Retain the source float32 phase and sine, with native interpolation.
		var weight: float=0.5+0.5*f32(sin(row.phase))
		_position[axis]=f32(row.start+f32(row.target-row.start)*weight)
		if absf(_position[axis]-row.target)<=float(_rules.endpoint_tolerance):
			row.negative=not row.negative
			var distance: int=int(_rules.endpoint_min[axis])+_random.next_int(int(_rules.endpoint_range[axis]))
			row.start=_position[axis]
			row.target=f32(float(_rules.position[axis])+distance*(1.0 if row.negative else -1.0))
			row.phase=float(_rules.phase_start)
	_elapsed_ms+=milliseconds
	return true

func snapshot() -> Dictionary:
	if _rules.is_empty():return {}
	return {"pose":Transform3D(_basis,_position),"elapsed_ms":_elapsed_ms,"axes":_axes.duplicate(true),"random":_random.snapshot()}

func fork() -> RefCounted:
	var result: RefCounted=get_script().new()
	result._rules=_rules.duplicate(true);result._random=_random.fork();result._axes=_axes.duplicate(true)
	result._position=_position;result._basis=_basis;result._elapsed_ms=_elapsed_ms
	return result

static func vector(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
static func f32(value: float) -> float:return PackedFloat32Array([value])[0]
func reject(message: String) -> bool:error=message;return false
