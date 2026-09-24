extends RefCounted
## Source Euler spin, with lifecycle skip decisions supplied by the world.
## Displaced bodies and mining require separate motion ownership.
const Library = preload("res://src/content/library.gd")
const Field = preload("res://src/simulation/scenery_field.gd")
const Frames = preload("res://src/simulation/frame_clock.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var _field := {}
var _max_ms := 0

func configure(bindings: RefCounted, field: Dictionary) -> bool:
	clear()
	if bindings==null or not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id) or not Frames.valid_parameters(bindings.frame_clock):return reject("Scenery motion requires a source frame clock")
	if field.get("base_content_id")!=bindings.base_content_id or field.get("binding_id")!=bindings.binding_id:return reject("Scenery motion belongs to another content identity")
	var rows: Variant = field.get("objects")
	if not rows is Array or rows.size()>8192:return reject("Invalid scenery motion field")
	for index in rows.size():
		var row: Variant = rows[index]
		if not row is Dictionary or row.get("index")!=index:return reject("Invalid scenery motion object order")
		for key in ["angles","spin"]:
			if not row.get(key) is Vector3 or not row[key].is_finite():return reject("Invalid scenery motion vector")
		if not row.get("basis") is Basis or not row.basis.is_equal_approx(Basis.from_euler(row.angles,EULER_ORDER_XYZ)):return reject("Scenery orientation does not match its angles")
		if maxf(absf(row.spin.x),maxf(absf(row.spin.y),absf(row.spin.z)))>1.0:return reject("Unsupported scenery spin")
	_field=field.duplicate(true);_max_ms=Frames.simulation_limit(bindings)
	for row in _field.objects:
		if row.has("ore_draws"):preload("res://src/simulation/readonly_state.gd").freeze(row.ore_draws)
	return true

func update(presentation_delta_ms: Variant, skip_motion: Array = []) -> bool:
	error=""
	if _field.is_empty():return reject("Configure scenery motion before updating")
	if not Numbers.integer(presentation_delta_ms,0,_max_ms):return reject("Invalid scenery presentation duration")
	if not skip_motion.is_empty() and (skip_motion.size()!=_field.objects.size() or not skip_motion.all(func(value):return value is bool)):
		return reject("Scenery motion mask must match the ordered field")
	if presentation_delta_ms==0:return true
	var seconds := Field.f32(Field.f32(float(presentation_delta_ms))*Field.f32(0.001))
	for row in _field.objects:
		if not skip_motion.is_empty() and skip_motion[row.index]:continue
		var angles: Vector3 = row.angles
		for axis in 3:angles[axis]=Field.f32(angles[axis]+Field.f32(row.spin[axis]*seconds))
		row.angles=angles
		row.basis=Basis.from_euler(angles,EULER_ORDER_XYZ)
	return true

## Tractor translation changes the physical model only. Statistics and contact
## bounds belong to the scenery body and deliberately retain their old origin.
func _retain_recovery_frame(index: int,frame: Dictionary) -> void:
	if frame.actor_changes.has("body_pose"):_field.objects[index].position=frame.actor_changes.body_pose.origin

func snapshot() -> Dictionary:
	return _field.duplicate(true)

func frame_snapshot() -> Dictionary:
	var result:=_field.duplicate()
	if not result.is_empty():result.objects=_field.objects.map(func(row):return row.duplicate())
	return result

func identity() -> Dictionary:
	return {} if _field.is_empty() else {"base_content_id":_field.base_content_id,"binding_id":_field.binding_id}

func fork_for_frame() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy._field=frame_snapshot();copy._max_ms=_max_ms
	return copy

func clear() -> void:
	error="";_field={};_max_ms=0

func reject(message: String) -> bool:
	error=message;return false
