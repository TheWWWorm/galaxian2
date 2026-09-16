extends RefCounted
## Systems integrity is separate from hull, armor and shields. The owning actor
## supplies its source capacity, recovery duration, active state and permission.
const Definitions=preload("res://src/content/emp_bombs_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
var error:=""
var _state:={}

func configure(bindings: RefCounted,capacity: Variant,recovery_ms: Variant) -> bool:
	error=""
	if not Definitions.available(bindings) or not Vitals.integer(capacity) or capacity<1 or capacity>Vitals.MAX_SHIELD or not Vitals.integer(recovery_ms) or recovery_ms<1:return reject("Invalid ship systems capacity or recovery duration")
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"capacity":capacity,"integrity":capacity,"recovery_ms":recovery_ms,"elapsed_ms":0,"disabled":false}
	return true

func hit(amount: Variant,hull: Variant,active: Variant,damage_allowed: Variant) -> Dictionary:
	error=""
	if _state.is_empty() or not Vitals.integer(amount) or not Vitals.integer(hull) or not active is bool or not damage_allowed is bool:return fail("Invalid systems damage context")
	var before:=snapshot()
	var accepted: bool=active and damage_allowed and hull>0 and _state.integrity>0
	if accepted:
		_state.integrity=maxi(0,_state.integrity-amount)
		if _state.integrity==0:_state.disabled=true;_state.elapsed_ms=0
	return {"accepted":accepted,"before":before,"after":snapshot(),"disabled_now":accepted and _state.disabled and not before.disabled}

func advance(delta_ms: Variant) -> bool:
	error=""
	if _state.is_empty() or not Vitals.integer(delta_ms):return reject("Invalid systems recovery frame")
	if not _state.disabled:return true
	if _state.elapsed_ms>Vitals.MAX_INTEGER-delta_ms:return reject("Systems recovery time exceeds supported milliseconds")
	var elapsed: int=_state.elapsed_ms+delta_ms
	var ratio:=Vitals.single(Vitals.single(float(elapsed))/Vitals.single(float(_state.recovery_ms)))
	var recovered:=int(Vitals.single(Vitals.single(float(_state.capacity))*ratio))
	# The source clears disabled only after the truncated result exceeds capacity.
	# At exactly full integrity the actor remains disabled for a later frame.
	_state.integrity=mini(recovered,_state.capacity)
	_state.disabled=recovered<=_state.capacity
	_state.elapsed_ms=elapsed if _state.disabled else 0
	return true

func snapshot() -> Dictionary:return _state.duplicate(true)
func fork() -> RefCounted:
	var copy: RefCounted=get_script().new();copy._state=_state.duplicate(true);return copy
func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}
