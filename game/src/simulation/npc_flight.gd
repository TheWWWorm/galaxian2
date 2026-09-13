extends RefCounted
## Native ordinary NPC steering and bank response in source units. A controller
## must explicitly select direction, speed, steering and travel permissions.
## No target selection, avoidance, dodge, weapons or mission state is inferred.
const Definitions = preload("res://src/content/npc_flight_definitions.gd")
const Library = preload("res://src/content/library.gd")
const Vitals = preload("res://src/simulation/combat_vitals.gd")
const Vectors = preload("res://src/simulation/source_vectors.gd")
var error := ""
var _identity := {}
var _definition := {}
var _root := Transform3D.IDENTITY
var _bank := 0.0
var _target_bank := 0.0
var _history: Array = []
var _cursor := 0
var _wrapped := false

func configure(bindings: RefCounted, initial_pose: Variant) -> bool:
	clear()
	if bindings==null or not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id): return reject("NPC flight requires content and binding identities")
	var data: Variant = bindings.opening_actors.get("npc_initialization",{}).get("flight",{})
	if not Definitions.parameters(data): return reject("Ordinary NPC flight is unavailable in this content pack")
	if not rigid_pose(initial_pose): return reject("NPC flight requires a finite unscaled initial pose")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_definition=data.duplicate(true)
	_root=initial_pose
	_history.resize(int(data.bank_samples))
	_history.fill(0.0)
	return true

func advance(delta_ms: Variant, desired_direction: Variant, speed: Variant, steering_enabled: Variant, travel_enabled: Variant = true) -> Dictionary:
	error=""
	if _definition.is_empty(): return fail("Configure NPC flight before advancing")
	if not Vitals.integer(delta_ms) or delta_ms<0 or delta_ms>2147483647/int(_definition.turn_numerator): return fail("NPC flight duration exceeds supported integer bounds")
	if not desired_direction is Vector3 or not desired_direction.is_finite() or not steering_enabled is bool or not travel_enabled is bool: return fail("NPC flight requires an explicit finite direction and permissions")
	if (not speed is float and not speed is int) or not is_finite(float(speed)) or speed<0 or not is_finite(Vitals.single(float(speed))): return fail("NPC speed must be finite and nonnegative")
	var distance := Vitals.single(Vitals.single(float(delta_ms))*Vitals.single(float(speed))) if travel_enabled else 0.0
	if not is_finite(distance) or distance>=2147483648.0: return fail("NPC travel exceeds supported integer bounds")
	distance=Vitals.single(float(int(distance)))
	var staged: RefCounted = fork_for_frame()
	var turn_angle := 0.0
	if steering_enabled:
		var desired := Vectors.normalized(desired_direction)
		var correction := Vectors.normalized(Vectors.added(desired,-_root.basis.z))
		var step := Vitals.single(Vitals.single(float(delta_ms*int(_definition.turn_numerator)))*float(_definition.turn_scale))
		var forward := Vectors.normalized(Vectors.added(_root.basis.z,Vectors.scaled(correction,step)))
		var difference := Vectors.added(forward,-desired).abs()
		var separation := Vitals.single(Vitals.single(difference.x+difference.y)+difference.z)
		if separation<float(_definition.heading_snap_l1): forward=desired
		if not desired.is_finite() or not forward.is_finite(): return fail("NPC heading exceeds supported precision")
		var cosine := Vectors.dot(Vectors.normalized(_root.basis.z),forward)
		if cosine>-1 and cosine<1: turn_angle=Vitals.single(acos(cosine))
		var side := Vectors.dot(_root.basis.x,forward)
		if side>=-1 and side<=1 and Vitals.single(acos(side))<float(_definition.bank_sign_angle): turn_angle=-turn_angle
		staged.record_turn(turn_angle)
		var right := Vectors.normalized(Vectors.cross(_root.basis.y,forward))
		var up := Vectors.normalized(Vectors.cross(forward,right))
		staged._root.basis=Basis(right,up,forward)
	else:
		staged._target_bank=0.0
		staged._cursor=0
		staged._wrapped=false
		staged._history.fill(0.0)
	var bank_step := Vitals.single(Vitals.single(Vitals.single(float(delta_ms))*float(_definition.bank_slew_numerator))/float(_definition.bank_slew_divisor))
	if _bank<staged._target_bank: staged._bank=minf(Vitals.single(_bank+bank_step),staged._target_bank)
	elif _bank>staged._target_bank: staged._bank=maxf(Vitals.single(_bank-bank_step),staged._target_bank)
	staged._root.origin=Vectors.added(_root.origin,Vectors.scaled(staged._root.basis.z,distance))
	if not rigid_pose(staged._root) or not staged.banked_pose().is_finite(): return fail("NPC flight produced an unsupported pose")
	_root=staged._root; _bank=staged._bank; _target_bank=staged._target_bank
	_history=staged._history; _cursor=staged._cursor; _wrapped=staged._wrapped
	var result := snapshot()
	result.travel_units=distance
	result.signed_turn_angle=turn_angle
	return result

func record_turn(angle: float) -> void:
	_history[_cursor]=angle
	var count := _history.size() if _wrapped else _cursor
	var mean := angle
	if count>0:
		mean=0.0
		for i in count: mean=Vitals.single(mean+float(_history[i]))
		mean=Vitals.single(mean/float(count))
	_cursor+=1
	if _cursor==_history.size(): _cursor=0; _wrapped=true
	_target_bank=clampf(Vitals.single(Vitals.single(mean*float(_definition.bank_limit))*float(_definition.bank_gain)),-float(_definition.bank_limit),float(_definition.bank_limit))

func apply_scripted_pose(pose: Variant) -> bool:
	error=""
	if _definition.is_empty() or not rigid_pose(pose): return reject("Scripted NPC motion requires a configured flight owner and finite unscaled pose")
	# A cinematic body override does not enter ordinary steering or reset its
	# bank history. Even a zero-duration ordinary update would change that state.
	_root=pose
	return true

func banked_pose() -> Transform3D:
	if _definition.is_empty(): return Transform3D.IDENTITY
	return _root*Transform3D(bank_basis(),Vector3.ZERO)

func bank_basis() -> Basis:
	if _definition.is_empty():return Basis.IDENTITY
	var radians := Vitals.single(Vitals.single(_bank*float(_definition.bank_angle_scale))*float(_definition.pi))
	return Basis.from_euler(Vector3(0,0,radians),EULER_ORDER_XYZ)

func snapshot() -> Dictionary:
	if _definition.is_empty(): return {}
	var state := _identity.duplicate()
	state.merge({"root_pose":_root,"pose":banked_pose(),"bank":_bank,"target_bank":_target_bank,"history":_history.duplicate(),"history_cursor":_cursor,"history_wrapped":_wrapped})
	return state

func fork_for_frame() -> RefCounted:
	var staged: RefCounted = get_script().new()
	staged._identity=_identity.duplicate(); staged._definition=_definition.duplicate(true)
	staged._root=_root; staged._bank=_bank; staged._target_bank=_target_bank
	staged._history=_history.duplicate(); staged._cursor=_cursor; staged._wrapped=_wrapped
	return staged

static func rigid_pose(value: Variant) -> bool:
	if not value is Transform3D or not value.is_finite(): return false
	var basis: Basis = value.basis
	return absf(basis.determinant()-1)<0.0001 and (basis.transposed()*basis).is_equal_approx(Basis.IDENTITY)

func clear() -> void:
	error=""; _identity={}; _definition={}; _root=Transform3D.IDENTITY
	_bank=0.0; _target_bank=0.0; _history=[]; _cursor=0; _wrapped=false

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
