extends RefCounted
## Native 48-bit linear congruential generator for reproducible source scenery.
## No dependency on Godot's platform/version-specific random sequences.
const MASK := 0xffffffffffff
const MULTIPLIER := 0x5deece66d
const ADDEND := 11
const LIMB_MASK := 0xffffff
var error := ""
var _state := 0
var _seeded := false

func seed_from(value: Variant) -> bool:
	error=""
	if not value is int: return reject("Random seed must be an integer")
	_state=(value ^ MULTIPLIER) & MASK
	_seeded=true
	return true

func next_bits(count: Variant) -> int:
	error=""
	if not _seeded or not count is int or count<1 or count>32:
		reject("Seed the generator and request between 1 and 32 bits")
		return -1
	# Two 24-bit limbs keep all intermediate products below signed 64-bit
	# overflow. Only the low 48 bits contribute to the next state.
	var low := _state & LIMB_MASK
	var high := _state >> 24
	var multiplier_low := MULTIPLIER & LIMB_MASK
	var multiplier_high := MULTIPLIER >> 24
	var product := low*multiplier_low+ADDEND
	var next_high := ((product >> 24)+high*multiplier_low+low*multiplier_high) & LIMB_MASK
	_state=(next_high << 24) | (product & LIMB_MASK)
	return _state >> (48-count)

func next_int(bound: Variant) -> int:
	error=""
	if not _seeded or not bound is int or bound<1 or bound>2147483647:
		reject("Random bound must be an integer from 1 through 2147483647")
		return -1
	var bits := next_bits(31)
	if (bound & (bound-1))==0: return (bound*bits) >> 31
	# Rejection removes modulo bias. The source checks this sum as a signed
	# 32-bit value; comparing against 2^31 avoids relying on integer overflow.
	var value: int = bits % bound
	while bits-value+bound-1>=2147483648:
		bits=next_bits(31)
		value=bits % bound
	return value

func snapshot() -> Dictionary:
	return {"state":_state} if _seeded else {}

func restore(value: Variant) -> bool:
	error=""
	if not value is Dictionary or not value.get("state") is int or value.state<0 or value.state>MASK:
		return reject("Invalid 48-bit random state")
	_state=value.state
	_seeded=true
	return true

func fork() -> RefCounted:
	var result: RefCounted = get_script().new()
	result._state=_state
	result._seeded=_seeded
	return result

func clear() -> void:
	_state=0;_seeded=false;error=""

func reject(message: String) -> bool:
	error=message
	return false
