extends RefCounted
## Retained projected-forward aim for native ordinary flight. Cursor-directed
## original steering modes and special equipment paths are not implemented here.
const Definitions = preload("res://src/content/player_aim_definitions.gd")
const TargetProjection = preload("res://src/presentation/target_projection.gd")
const Vectors = preload("res://src/simulation/source_vectors.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
var error := ""
var _identity := {}
var _definition := {}
var _perspective := {}
var _point := Vector3.ZERO
var _raw := Vector3.ZERO
var _viewport := Vector2i.ZERO
var _contact := false
var _contact_ms := 0
var _flash := false
var _visible := false

func configure(bindings: RefCounted) -> bool:
	clear()
	if bindings==null or not Definitions.parameters(bindings.opening_staging.get("player_aim",{})):
		return reject("Opening aim requires verified projected-forward declarations")
	var projection := TargetProjection.new()
	if not projection.configure(bindings.flight_projection,Vector2i.ONE):return reject(projection.error)
	_definition=bindings.opening_staging.player_aim.duplicate(true)
	_perspective=bindings.flight_projection.duplicate(true)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	return true

func advance(player: Transform3D, preceding_camera: Transform3D, viewport_size: Vector2i) -> bool:
	error=""
	if _definition.is_empty():return reject("Configure opening aim before advancing")
	if not player.is_finite():return reject("Opening aim requires a finite player pose")
	var projection := TargetProjection.new()
	if not projection.configure(_perspective,viewport_size):return reject(projection.error)
	# Source bodies use positive Z as forward. Camera poses already use Godot's
	# right/up/backward basis. Keep their two coordinate roles distinct.
	var world_point := Vectors.added(player.origin,Vectors.scaled(Vectors.normalized(player.basis.z),_definition.distance))
	var projected: Dictionary=projection.project_point(preceding_camera,world_point)
	if projected.has("error"):return reject(projection.error)
	var raw := Vector3(projected.screen_position.x,projected.screen_position.y,projected.camera_position.z)
	var point := raw if raw.z>0 else Vectors.added(Vectors.scaled(raw,_definition.new_weight),Vectors.scaled(_point,_definition.previous_weight))
	if not point.is_finite() or not TargetProjection.safe_pixel(point.x) or not TargetProjection.safe_pixel(point.y):return reject("Opening aim exceeds supported pixel coordinates")
	_point=point;_raw=raw;_viewport=viewport_size
	return true

func sample_feedback(npc_contact: bool, delta_ms: Variant, draw_enabled: bool) -> bool:
	error=""
	if _definition.is_empty() or not Numbers.integer(delta_ms,0,2147483647):return reject("Opening reticle requires an ordinary integer frame duration")
	var contact := _contact or npc_contact
	var timer := _contact_ms
	var flash := draw_enabled and contact
	if draw_enabled:
		if contact:
			if timer>2147483647-int(delta_ms):return reject("Opening reticle timer exceeds source integer range")
			timer+=int(delta_ms)
			if timer>=int(_definition.contact_limit_ms):contact=false
		else:timer=0
	# The image is sampled before expiry. An idle draw, not another contact,
	# resets the timer. Hidden cinematic frames retain a pending contact flag.
	_contact=contact;_contact_ms=timer;_flash=flash;_visible=draw_enabled
	return true

func snapshot() -> Dictionary:
	if _definition.is_empty():return {}
	var result := _identity.duplicate()
	result.merge({"mode":_definition.mode,"point":_point,"raw_point":_raw,"viewport_size":_viewport,
		"contact_active":_contact,"contact_ms":_contact_ms,"contact_flash":_flash,"visible":_visible,
		"image_id":int(_definition.image_ids[1 if _flash else 0])})
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._definition=_definition;copy._perspective=_perspective
	copy._point=_point;copy._raw=_raw;copy._viewport=_viewport
	copy._contact=_contact;copy._contact_ms=_contact_ms;copy._flash=_flash;copy._visible=_visible
	return copy

func clear() -> void:
	error="";_identity={};_definition={};_perspective={};_point=Vector3.ZERO;_raw=Vector3.ZERO;_viewport=Vector2i.ZERO
	_contact=false;_contact_ms=0;_flash=false;_visible=false

func reject(message: String) -> bool:
	error=message
	return false
