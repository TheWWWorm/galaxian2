extends RefCounted
## Ordinary source frame timing. The caller supplies monotonic microseconds and
## explicit simulation blocking; pause transitions rebase instead of catching up.
const Library = preload("res://src/content/library.gd")
var error := ""
var binding_id := ""
var base_content_id := ""
var _max_ms := 0
var _last_ms := -1

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy.binding_id=binding_id;copy.base_content_id=base_content_id
	copy._max_ms=_max_ms;copy._last_ms=_last_ms
	return copy

static func valid_parameters(data: Dictionary) -> bool:
	var value: Variant = data.get("max_frame_milliseconds")
	return data.get("time_unit") == "milliseconds" and (value is int or value is float) \
		and is_finite(value) and value == floor(value) and value >= 1 and value <= 1000

static func validate(data: Variant, executable_bytes: int, architecture: String) -> String:
	if not data is Dictionary: return "Invalid frame clock definition"
	if data.is_empty(): return ""
	if not valid_parameters(data): return "Unsupported frame clock parameters"
	var sizes := [62, 28] if architecture == "armv7" else [72, 28]
	if not data.get("provenance") is Array or data.provenance.size() != 2: return "Missing frame clock provenance"
	for i in 2:
		var row: Variant = data.provenance[i]
		if not row is Dictionary or row.get("bytes") != sizes[i]: return "Unsupported frame clock layout"
		var offset: Variant = row.get("offset")
		if not (offset is int or offset is float) or not is_finite(offset) or offset != floor(offset) or offset < 0 or offset > executable_bytes - sizes[i]:
			return "Invalid frame clock source extent"
	return ""

func configure(bindings: RefCounted, content_id: String) -> bool:
	clear()
	if not Library.valid_hash(content_id) or bindings.base_content_id != content_id or not Library.valid_hash(bindings.binding_id):
		error = "Frame clock belongs to another or unavailable content identity"
		return false
	if not valid_parameters(bindings.frame_clock):
		error = "This content has no supported ordinary frame clock"
		return false
	_max_ms = int(bindings.frame_clock.max_frame_milliseconds)
	binding_id = bindings.binding_id
	base_content_id = content_id
	return true

func clear() -> void:
	error = ""
	binding_id = ""
	base_content_id = ""
	_max_ms = 0
	_last_ms = -1

func rebase(now_microseconds: int) -> bool:
	error = ""
	if binding_id.is_empty() or now_microseconds < 0:
		error = "Invalid frame clock context or timestamp"
		return false
	@warning_ignore("integer_division")
	_last_ms = now_microseconds / 1000
	return true

func sample(now_microseconds: int, blocked: bool) -> float:
	error = ""
	if binding_id.is_empty() or now_microseconds < 0:
		error = "Invalid frame clock context or timestamp"
		return 0.0
	@warning_ignore("integer_division")
	var now_ms: int = now_microseconds / 1000
	var delta := 0 if _last_ms < 0 else clampi(now_ms - _last_ms, 0, _max_ms)
	_last_ms = now_ms
	return 0.0 if blocked else float(delta) / 1000.0
