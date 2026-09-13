extends RefCounted
## Connects a verified docked approach to drilling and atomic extraction.
## Candidates leave every accepted owner unchanged. The flight must accept the
## session, cargo, field and continued random stream together, then release the
## approach and resume ordinary motion when requested. Missions remain separate.
const Definitions=preload("res://src/content/mining_session_definitions.gd")
const MiningFlight=preload("res://src/content/full_hold_flight_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Approach=preload("res://src/simulation/mining_approach.gd")
const Drill=preload("res://src/simulation/mining_drill.gd")
const Extraction=preload("res://src/simulation/mining_extraction.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Scenery=preload("res://src/simulation/opening_scenery.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var error:=""
var _rules:={}
var _identity:={}
var _bindings: RefCounted
var _catalogues: RefCounted
var _field_identity: RefCounted
var _equipment:=[]
var _center:=Vector2.ZERO
var _hard:=false
var _drill: RefCounted
var _phase:="idle"
var _last_drill:={}
var _receipt:={}
var _events:=[]

func configure(bindings: RefCounted, catalogues: RefCounted, construction: RefCounted, hard_difficulty: bool, reference_center:=Vector2.ZERO) -> bool:
	error=""
	if bindings==null or catalogues==null or construction==null or construction.get_script()!=Construction or not Definitions.parameters(bindings.mining_session):return reject("Mining session requires supported departure declarations")
	var entry: Dictionary=construction.snapshot()
	if entry.is_empty() or entry.get("base_content_id")!=bindings.base_content_id or entry.get("binding_id")!=bindings.binding_id or catalogues.content_id!=bindings.base_content_id or MiningFlight.flight(bindings,entry.get("campaign_cursor")).is_empty():return reject("Mining session belongs to another departure")
	if not reference_center.is_finite() or reference_center!=reference_center.floor() or absf(reference_center.x)>16384 or absf(reference_center.y)>16384:return reject("Mining session requires fixed integer drill coordinates")
	_rules=bindings.mining_session.duplicate(true);_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_bindings=bindings;_catalogues=catalogues;_field_identity=construction.scenery_owner().presentation_identity()
	_equipment=entry.departure.loadout.equipment_ids.duplicate();_center=reference_center;_hard=hard_difficulty
	_drill=null;_phase="idle";_last_drill={};_receipt={};_events=[]
	return true

func begin(approach: RefCounted, scenery: RefCounted, cargo: RefCounted, command:=Vector2.ZERO) -> bool:
	error=""
	if _drill!=null or not _context(scenery,cargo):return reject("Mining session requires its idle, matching field and cargo")
	if approach==null or approach.get_script()!=Approach or approach.field_identity()!=_field_identity:return reject("Mining session requires its actual completed approach")
	var state: Dictionary=approach.snapshot()
	for key in _identity:
		if state.get(key)!=_identity[key]:return reject("Mining approach belongs to another profile")
	if state.get("phase")!="drill_required" or state.get("camera_update_enabled",true) or state.get("spin_enabled",true):return reject("Approach and settling have not completed")
	if cargo.snapshot().free_space<=0:return reject("The cargo hold has no space for mining")
	var body:=_target(scenery,state.get("object_index"))
	if body.is_empty():return false
	if not Approach.intact(body):return reject("The docked asteroid is no longer intact")
	if state.object_index not in scenery.snapshot().get("spin_disabled_indices",[]):return reject("The flight has not applied the docked asteroid's spin stop")
	var drill:=Drill.new()
	if not drill.configure_for_scenery(_bindings,_catalogues,_equipment,scenery,int(state.object_index),_center):return reject(drill.error)
	if not drill.set_command(command):return reject(drill.error)
	# Construction does not call advance or consume random draws. Input may be
	# latched later on this frame, but can first move the point on the next one.
	_drill=drill;_phase="drilling";_last_drill={};_receipt={};_events=[]
	return true

func evaluate(scenery: RefCounted, cargo: RefCounted, delta_ms: Variant, shared_random_state: Variant, command:=Vector2.ZERO, paused:=false, latch_command:=true) -> Dictionary:
	error=""
	if _drill==null or not _context(scenery,cargo) or not Numbers.integer(delta_ms,0,int(_rules.max_frame_ms)) or not command.is_finite() or absf(command.x)>1 or absf(command.y)>1:return fail("Invalid active mining frame or input")
	var random:=Random.new()
	if not random.restore(shared_random_state):return fail(random.error)
	var body:=_target(scenery,_drill.snapshot().object_index)
	if body.is_empty():return {}
	var next:=fork_for_frame()
	var result:={"session":next,"scenery":scenery.fork_for_frame(),"cargo":cargo.fork_for_frame(),
		"random_state":random.snapshot(),"release_approach":false,"resume_motion":false,"outcome":"drilling"}
	if paused:return result
	next._events=[]
	if not Approach.intact(body):
		# The player's invalid-target path cancels directly, before calling the
		# drill update or extraction. Do not reward or retire a combat casualty.
		next._last_drill=next._drill.snapshot();next._drill=null;next._phase="cancelled";next._receipt={}
		result.release_approach=true;result.outcome="target_unavailable"
		return result
	if not next._drill.advance(delta_ms,shared_random_state):return fail(next._drill.error)
	var sample: Dictionary=next._drill.snapshot()
	result.random_state=sample.random_state.duplicate(true)
	if sample.phase!="drilling":
		if not next._finish(result,true):return fail(next.error)
	elif latch_command:
		# Source input is applied after this update. Keeping it here preserves
		# one-frame latency; callers explicitly provide zero on release.
		if not next._drill.set_command(command):return fail(next._drill.error)
	# If the later input pass is gated (including exhausted player hull), the
	# drill keeps its preceding command. Its ordinary clocks and outcome still
	# advance; this is independent of an explicit application pause.
	return result

func stop(scenery: RefCounted, cargo: RefCounted, shared_random_state: Variant) -> Dictionary:
	error=""
	if _drill==null or not _context(scenery,cargo):return fail("No active matching mining session can be stopped")
	var random:=Random.new()
	if not random.restore(shared_random_state):return fail(random.error)
	var body:=_target(scenery,_drill.snapshot().object_index)
	if body.is_empty() or not Approach.intact(body):return fail("An unavailable asteroid cannot grant stopped-mining cargo")
	var next:=fork_for_frame()
	if not next._drill.stop():return fail(next._drill.error)
	var result:={"session":next,"scenery":scenery.fork_for_frame(),"cargo":cargo.fork_for_frame(),
		"random_state":random.snapshot(),"release_approach":false,"resume_motion":false,"outcome":"stopped"}
	if not next._finish(result,false):return fail(next.error)
	return result

func set_command(command: Vector2) -> bool:
	# The enclosing flight can perform contact/mission checks before deciding
	# whether this later input pass occurs. This never advances the drill.
	error=""
	if _drill==null:return reject("No active drill can accept controls")
	if not _drill.set_command(command):return reject(_drill.error)
	return true

func _finish(candidate: Dictionary, automatic: bool) -> bool:
	var extractor:=Extraction.new()
	var transaction:=extractor.evaluate(_bindings,_catalogues,_drill,candidate.scenery,candidate.cargo,_hard)
	if transaction.is_empty():return reject(extractor.error)
	_last_drill=_drill.snapshot();_drill=null;_phase="finished";_receipt=transaction.extraction.duplicate(true);_events=[]
	for id in _rules.stop_audio_events:_events.append({"kind":"stop_audio_event","source_id":int(id)})
	if _last_drill.phase=="failed":_events.append({"kind":"notification","source_id":int(_rules.failure_notification),"text_id":int(_rules.failure_text_id)})
	candidate.scenery=transaction.scenery;candidate.cargo=transaction.cargo
	candidate.release_approach=true;candidate.resume_motion=automatic
	candidate.outcome=_last_drill.phase
	return true

func _context(scenery: RefCounted, cargo: RefCounted) -> bool:
	if _rules.is_empty() or scenery==null or scenery.get_script()!=Scenery or cargo==null or cargo.get_script()!=Cargo or scenery.presentation_identity()!=_field_identity or cargo.field_identity()!=_field_identity:return false
	return cargo.matches_mined_field(scenery.snapshot())

func _target(scenery: RefCounted, index: Variant) -> Dictionary:
	var field: Dictionary=scenery.snapshot();var bodies: Array=field.get("bodies",{}).get("objects",[])
	if not Numbers.integer(index,0,bodies.size()-1) or field.get("destruction",[]).size()!=bodies.size():reject("Mining requires the actual asteroid and its lifecycle");return {}
	var body: Dictionary=bodies[index]
	if body.get("index")!=index or not body.get("position") is Vector3 or not body.position.is_finite() or body.position!=field.objects[index].position or body.get("model_id")!=field.objects[index].model_id:reject("Mining asteroid and geometry have diverged");return {}
	body.lifecycle_state=int(field.destruction[index].lifecycle.actor_state)
	return body

func drill_owner() -> RefCounted:return null if _drill==null else _drill.fork()
func has_active_drill() -> bool:return _drill!=null
func snapshot() -> Dictionary:
	if _rules.is_empty():return {}
	var result:=_identity.duplicate()
	result.merge({"phase":_phase,"hard_difficulty":_hard,"drill":{} if _drill==null else _drill.snapshot(),
		"last_drill":_last_drill.duplicate(true),"extraction":_receipt.duplicate(true),"events":_events.duplicate(true)})
	return result
func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules;copy._identity=_identity;copy._bindings=_bindings;copy._catalogues=_catalogues;copy._field_identity=_field_identity
	copy._equipment=_equipment;copy._center=_center;copy._hard=_hard;copy._phase=_phase
	copy._drill=null if _drill==null else _drill.fork()
	copy._last_drill=_last_drill.duplicate(true);copy._receipt=_receipt.duplicate(true);copy._events=_events.duplicate(true)
	return copy
func clear() -> void:
	error="";_rules={};_identity={};_bindings=null;_catalogues=null;_field_identity=null;_equipment=[];_center=Vector2.ZERO;_hard=false
	_drill=null;_phase="idle";_last_drill={};_receipt={};_events=[]
func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:error=message;return {}
