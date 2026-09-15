extends RefCounted
## First-departure asteroid acquisition. Selection grants no cargo, movement or
## mission progress. The flight supplies committed poses and its retained aim.
const Definitions=preload("res://src/content/mining_targeting_definitions.gd")
const OrdinaryFlight=preload("res://src/content/ordinary_flight_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const TargetProjection=preload("res://src/presentation/target_projection.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
var error:=""
var _rules:={}
var _perspective:={}
var _identity:={}
var _field_identity: RefCounted
var _radii:=Vector2.ZERO
var _frames:=0
var _duration:=0
var _scanner_id:=-1
var _drill_id:=-1
var _selected:=-1
var _candidate:=-1
var _elapsed:=0
var _sample:={}

func configure(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted, frame_radii: Vector2, animation_frames: int) -> bool:
	error=""
	if bindings==null or catalogues==null or construction==null or construction.get_script()!=Construction or not Definitions.parameters(bindings.mining_targeting):return reject("Asteroid selection requires a supported mining departure")
	var entry: Dictionary=construction.snapshot()
	if entry.is_empty() or entry.get("base_content_id")!=bindings.base_content_id or entry.get("binding_id")!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id or OrdinaryFlight.for_departure(bindings,entry).is_empty():return reject("Asteroid selection belongs to another departure")
	var projection:=TargetProjection.new()
	if not projection.configure(bindings.flight_projection,Vector2i.ONE,frame_radii):return reject(projection.error)
	if animation_frames<1 or animation_frames>1024:return reject("Invalid source acquisition filmstrip")
	var rules: Dictionary=bindings.mining_targeting
	var scanner:=-1;var drill:=-1
	var items: Array=catalogues.tables.get("items",[])
	for id in entry.departure.loadout.equipment_ids:
		if not Numbers.integer(id,0,items.size()-1):return reject("Asteroid selection equipment is unavailable")
		var properties: Dictionary=items[id].properties
		# Installed primaries share the loadout but do not supply the equipment
		# subtypes used by the scanner and drill getters.
		if properties.get(int(rules.item_kind_property))!=int(rules.equipment_kind):continue
		var category: Variant=properties.get(int(rules.category_property))
		if category==int(rules.unsupported_device_category):return reject("Special tractor devices require a separate selection owner")
		if category==int(rules.scanner_category):scanner=id
		if category==int(rules.drill_category):drill=id
	var duration:=int(rules.default_duration_ms)
	if scanner>=0:
		var value: Variant=items[scanner].properties.get(int(rules.duration_property))
		if not Numbers.integer(value,int(rules.animation_delay_ms)+1,2147483647):return reject("Unsupported asteroid acquisition duration")
		duration=int(value)
	_rules=rules.duplicate(true);_perspective=bindings.flight_projection.duplicate(true)
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_field_identity=construction.scenery_owner().presentation_identity()
	_radii=frame_radii;_frames=animation_frames;_duration=duration;_scanner_id=scanner;_drill_id=drill
	_selected=-1;_candidate=-1;_elapsed=0;_sample={}
	return true

func advance(scenery: RefCounted, player: Transform3D, camera: Transform3D, aim: Dictionary, delta_ms: Variant, enabled: bool, approaching:=false) -> bool:
	error=""
	if _rules.is_empty() or scenery==null or scenery.get_script()!=Scenery or scenery.presentation_identity()!=_field_identity or not Numbers.integer(delta_ms,0,int(_rules.max_frame_ms)):return reject("Invalid asteroid selection field or frame")
	for key in _identity:
		if aim.get(key)!=_identity[key]:return reject("Asteroid selection aim belongs to another identity")
	var point: Variant=aim.get("point");var viewport: Variant=aim.get("viewport_size")
	if not point is Vector3 or not point.is_finite() or not TargetProjection.safe_pixel(point.x) or not TargetProjection.safe_pixel(point.y) or not viewport is Vector2i or not player.is_finite() or not camera.is_finite() or not camera.basis.is_equal_approx(camera.basis.orthonormalized()) or camera.basis.determinant()<=0:return reject("Invalid asteroid selection aim or pose")
	var projection:=TargetProjection.new()
	if not projection.configure(_perspective,viewport,_radii):return reject(projection.error)
	var radius:=int(viewport.x)/int(_rules.window_divisor)
	var lower:=Vector2(TargetProjection.single(point.x-float(radius)),TargetProjection.single(point.y-float(radius)))
	for value in [lower.x,lower.y,lower.x+radius*2,lower.y+radius*2]:
		if not TargetProjection.safe_pixel(value):return reject("Asteroid selection window exceeds source pixel coordinates")
	var low:=Vector2i(int(lower.x),int(lower.y));var high:=low+Vector2i(radius*2,radius*2)
	var field: Dictionary=scenery.snapshot()
	for key in _identity:
		if field.get(key)!=_identity[key] or field.get("bodies",{}).get(key)!=_identity[key]:return reject("Asteroid bodies belong to another content identity")
	var bodies: Variant=field.get("bodies",{}).get("objects")
	var lifecycles: Array=field.get("destruction",[])
	if not bodies is Array or bodies.size()!=field.objects.size() or (not lifecycles.is_empty() and lifecycles.size()!=bodies.size()):return reject("Asteroid selection requires complete live bodies")
	var markers:=[];var candidates:=[];var kinds:={}
	for index in bodies.size():
		var body: Variant=bodies[index]
		if not body is Dictionary or body.get("index")!=index or not body.get("active") is bool or not body.get("position") is Vector3 or not body.position.is_finite() or not Numbers.integer(body.get("source_size_value"),4,7) or body.position!=field.objects[index].position or body.model_id!=field.objects[index].model_id:return reject("Invalid asteroid body sample")
		var state:=0 if lifecycles.is_empty() else int(lifecycles[index].lifecycle.actor_state)
		if state not in [0,3,4]:return reject("Unsupported asteroid selection lifecycle")
		if not body.active and state in [3,4]:continue
		if not enabled:continue
		var projected:=projection.project(camera,body.position)
		if projected.has("error"):return reject(projection.error)
		var pixel: Vector2i=projected.pixels
		var inside: bool=projected.in_view and pixel.x>low.x and pixel.x<high.x and pixel.y>low.y and pixel.y<high.y
		var kind:="debris" if body.active and state in [3,4] else "asteroid"
		markers.append({"object_index":index,"pixels":pixel,"in_view":projected.in_view,"in_scan_window":inside,"selected":index==_selected,"kind":kind,"item_id":body.item_id})
		kinds[index]=kind
		if inside and not body.get("mined",false) and candidates.size()<int(_rules.candidate_limit):candidates.append(index)
	var selected:=_selected;var candidate:=_candidate;var elapsed:=_elapsed
	var nearest:=-1;var nearest_distance:=int(_rules.candidate_distance_limit)
	var events:=[];var animation:=-1
	if enabled:
		for index in candidates:
			var offset:=Vectors.added(bodies[index].position,-player.origin)
			var length:=TargetProjection.single(sqrt(Vectors.dot(offset,offset)))
			if not is_finite(length) or length>2147483647.0:return reject("Asteroid target distance exceeds source range")
			var distance:=int(length)
			if distance<nearest_distance:nearest=index;nearest_distance=distance
		selected=-1
		if nearest<0 or approaching:
			candidate=-1;elapsed=0
		else:
			if candidate!=nearest:elapsed=0
			candidate=nearest
			if elapsed>2147483647-int(delta_ms):return reject("Asteroid acquisition time exceeds source range")
			elapsed+=int(delta_ms)
			if elapsed>_duration-int(_rules.acquisition_lead_ms):
				if kinds[candidate]=="debris":events.append({"kind":"notification","source_id":int(_rules.missing_tractor_notification),"object_index":candidate})
				elif _drill_id<0:events.append({"kind":"notification","source_id":int(_rules.missing_drill_notification),"object_index":candidate})
				else:
					selected=candidate
					if _selected!=selected:events.append({"kind":"sound","source_id":int(_rules.acquisition_sound_id),"unless_source_id_playing":0,"object_index":selected})
			if elapsed>int(_rules.animation_delay_ms):
				if selected==candidate:animation=_frames-1
				else:
					var progress:=TargetProjection.single(TargetProjection.single(float(elapsed-int(_rules.animation_delay_ms)))/TargetProjection.single(float(_duration-int(_rules.animation_delay_ms))))
					var frame:=int(TargetProjection.single(float(_frames-1)*progress))
					if frame<_frames-1:animation=frame
	_selected=selected;_candidate=candidate;_elapsed=elapsed
	_sample={"visible":enabled,"markers":markers,"candidate_indices":candidates,"nearest_index":nearest,
		"events":events,"animation_frame":animation,"aim_pixels":Vector2i(int(point.x),int(point.y)),"viewport_size":viewport}
	return true

func snapshot() -> Dictionary:
	if _rules.is_empty():return {}
	var state:=_identity.duplicate()
	state.merge({"selected_object_index":_selected,"candidate_object_index":_candidate,"elapsed_ms":_elapsed,
		"scanner_id":_scanner_id,"drill_id":_drill_id,"duration_ms":_duration,"animation_frames":_frames})
	state.merge(_sample.duplicate(true))
	return state

func clear_selection() -> void:_selected=-1
func field_identity() -> RefCounted:return _field_identity
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules;copy._perspective=_perspective;copy._identity=_identity;copy._field_identity=_field_identity
	copy._radii=_radii;copy._frames=_frames;copy._duration=_duration;copy._scanner_id=_scanner_id;copy._drill_id=_drill_id
	copy._selected=_selected;copy._candidate=_candidate;copy._elapsed=_elapsed;copy._sample=_sample.duplicate(true)
	return copy
func clear() -> void:
	error="";_rules={};_perspective={};_identity={};_field_identity=null;_sample={}
	_radii=Vector2.ZERO;_frames=0;_duration=0;_scanner_id=-1;_drill_id=-1;_selected=-1;_candidate=-1;_elapsed=0
func reject(message: String) -> bool:error=message;return false
