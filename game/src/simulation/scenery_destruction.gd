extends RefCounted
## One ordinary scenery actor's destruction lifecycle. The world supplies its
## current body, pose and shared RNG state, and commits returned body/accounting
## changes. Cargo remains an actor-owned candidate, never player inventory.
const Clock = preload("res://src/simulation/scenery_effect_clock.gd")
const Resources = preload("res://src/content/scenery_effect_resources.gd")
const Random = preload("res://src/simulation/seeded_random.gd")
const Numbers = preload("res://src/content/opening_definitions.gd")
const CargoPaths := ["resources/data/assets/main/3d/meshes/misc/asteroid_01_junk.aem",
	"resources/data/assets/main/3d/meshes/misc/asteroid_void_junk.aem"]
var error := ""
var _state := {}
var _body := {}
var _identity := {}
var _cargo_models := []
var _effect: RefCounted
var _max_ms := 0
var _item_count := 0
var _read_snapshot:={}

func configure(bindings: RefCounted, catalogues: RefCounted, body_state: Dictionary, object_index: Variant, descriptor: Dictionary) -> bool:
	clear()
	if not Resources.effect_parameters(descriptor,bindings):return reject("Scenery destruction requires verified effect metadata")
	if catalogues==null or catalogues.content_id!=descriptor.base_content_id or not catalogues.tables.get("items") is Array:
		return reject("Scenery destruction requires matching item catalogues")
	for key in ["base_content_id","binding_id"]:
		if body_state.get(key)!=descriptor[key]:return reject("Scenery destruction body belongs to another content identity")
	var objects: Variant=body_state.get("objects")
	if not objects is Array or not Numbers.integer(object_index,0,objects.size()-1):return reject("Scenery destruction body is unavailable")
	var row: Variant=objects[object_index]
	if not row is Dictionary or row.get("index")!=object_index or row.get("model_id")!=descriptor.base_model_id:
		return reject("Scenery destruction model differs from its body")
	_item_count=catalogues.tables.items.size()
	if not Numbers.integer(row.get("item_id"),0,_item_count-1) or not Numbers.integer(row.get("source_size_value"),4,7):
		return reject("Unsupported scenery destruction ore or class")
	var effect := Clock.new()
	if not effect.configure(bindings,descriptor,row.get("scale")):return reject(effect.error)
	for index in 2:
		var id := 16926+index
		var path: String=bindings.resolve(id,"mesh")
		if path!=CargoPaths[index]:return reject("Unsupported source scenery cargo model binding")
		_cargo_models.append({"model_id":id,"resource":path})
	for key in ["index","item_id","model_id","source_size_value","scale"]:_body[key]=row[key]
	_identity={"base_content_id":descriptor.base_content_id,"binding_id":descriptor.binding_id}
	_state={"actor_state":0,"update_enabled":true,"drop_allowed":true,"cargo":{}}
	_effect=effect;_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	if current_body(body_state).is_empty():var message:=error;clear();return reject(message)
	return true

func update(delta_ms: Variant, body_state: Dictionary, pose: Transform3D, random_state: Variant) -> Dictionary:
	_read_snapshot={}
	error=""
	if _effect==null:return fail("Configure scenery destruction before updating it")
	if not Numbers.integer(delta_ms,0,_max_ms):return fail("Invalid scenery destruction frame duration")
	var body := current_body(body_state)
	if body.is_empty():return {}
	if not pose.is_finite() or pose.origin!=body.position:return fail("Scenery destruction pose differs from its body")
	var random := Random.new()
	if not random.restore(random_state):return fail(random.error)
	var result := {"object_index":_body.index,"statistics_active":body.active,
		"motion_scalar":body.motion_scalar,"skip_motion":delta_ms==0,"events":[]}
	var next := _state.duplicate(true)
	var effect: RefCounted=_effect.fork_for_frame()
	if delta_ms>0:
		if not body.active and next.actor_state==4:
			next.update_enabled=false;result.skip_motion=true
		elif not next.update_enabled:
			return fail("Retired scenery cannot be reactivated by this lifecycle")
		elif body.vitals.hull==0 and next.actor_state==0:
			if body.motion_scalar!=0.0:return fail("Displaced scenery destruction is not implemented")
			if not effect.trigger(pose):return fail(effect.error)
			var cargo := candidate(next.drop_allowed,random)
			if cargo.has("error"):return fail(cargo.error)
			# The source positions a fresh junk model. It does not copy the
			# asteroid's rotation or scale into that model.
			if not cargo.is_empty():cargo.pose=Transform3D(Basis.IDENTITY,pose.origin)
			next.actor_state=3;next.cargo=cargo
			if cargo.is_empty():next.drop_allowed=false
			result.events.append({"kind":"destruction_started","object_index":_body.index,
				"world_scenery_count_delta":-1,"destruction_count_delta":1,"cargo":cargo.duplicate(true)})
			# The triggering actor returns before either effect time or spin work.
			result.skip_motion=true
		elif next.actor_state==3:
			if body.motion_scalar!=0.0:return fail("Displaced scenery destruction is not implemented")
			if not effect.update(delta_ms):return fail(effect.error)
			if not effect.snapshot().active:
				next.actor_state=4;result.motion_scalar=0.0
		elif next.actor_state==4:
			result.statistics_active=false;result.motion_scalar=0.0
	# On state 3 and the active state-4 retirement tick, original intact-model
	# spin still runs. Its captured breakup pose is independent of that spin.
	result.random_state=random.snapshot()
	_state=next;_effect=effect
	return result

func candidate(allowed: bool, random: RefCounted) -> Dictionary:
	if not allowed or random.next_int(100)>=20:return {}
	var core: bool=_body.source_size_value==7
	var item: int=_body.item_id
	if core:item=218 if item==217 else item+11
	if item<0 or item>=_item_count:return {"error":"Scenery cargo item is absent from this catalogue"}
	var result: Dictionary=_cargo_models[1 if _body.item_id==164 else 0].duplicate()
	result.item_id=item;result.quantity=1 if core else random.next_int(3)+1
	return result

func retire_without_destruction() -> bool:
	_read_snapshot={}
	error=""
	if _effect==null:return reject("Configure scenery before retiring its lifecycle")
	# Scripted removal bypasses damage and the state-0 destruction trigger. Cargo
	# and effect history remain owned; state 4 suppresses intact/effect drawing.
	_state.actor_state=4
	return true

func disable_drop() -> void:
	_read_snapshot={}
	# A future mining owner must separately own earned quantity and accounting.
	# This eligibility change alone never means mining succeeded.
	if not _state.is_empty():_state.drop_allowed=false

func snapshot() -> Dictionary:
	if _effect==null:return {}
	var result := _identity.duplicate()
	result.object_index=_body.index;result.lifecycle=_state.duplicate(true)
	result.effect=_effect.snapshot()
	return result

func read_snapshot() -> Dictionary:
	if _read_snapshot.is_empty():_read_snapshot=preload("res://src/simulation/readonly_state.gd").freeze(snapshot())
	return _read_snapshot

func presentation_clock() -> RefCounted:
	return null if _effect==null else _effect.fork_for_frame()

func actor_state() -> int:
	return int(_state.get("actor_state",-1))

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._read_snapshot=_read_snapshot
	copy._state=_state.duplicate(true);copy._body=_body.duplicate();copy._identity=_identity.duplicate()
	copy._cargo_models=_cargo_models;copy._max_ms=_max_ms;copy._item_count=_item_count
	copy._effect=null if _effect==null else _effect.fork_for_frame()
	return copy

func current_body(body_state: Dictionary) -> Dictionary:
	for key in ["base_content_id","binding_id"]:
		if body_state.get(key)!=_identity.get(key):return fail("Scenery destruction body identity changed")
	var objects: Variant=body_state.get("objects")
	if not objects is Array or _body.index>=objects.size():return fail("Scenery destruction body disappeared")
	var row: Variant=objects[_body.index]
	if not row is Dictionary:return fail("Invalid scenery destruction body")
	for key in _body:
		if row.get(key)!=_body[key]:return fail("Scenery destruction body content changed")
	if not row.get("active") is bool or not row.get("position") is Vector3 or not row.position.is_finite():return fail("Invalid scenery destruction body state")
	if not row.get("vitals") is Dictionary or not Numbers.integer(row.vitals.get("hull"),0,2147483647):return fail("Invalid scenery destruction hull")
	if not (row.get("motion_scalar") is int or row.get("motion_scalar") is float) or not is_finite(row.motion_scalar):return fail("Invalid scenery impact scalar")
	return row

func clear() -> void:
	_read_snapshot={}
	error="";_state={};_body={};_identity={};_cargo_models=[];_effect=null;_max_ms=0;_item_count=0

func reject(message: String) -> bool:
	error=message;return false

func fail(message: String) -> Dictionary:
	error=message;return {}
