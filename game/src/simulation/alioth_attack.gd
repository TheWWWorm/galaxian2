extends RefCounted
const Frames=preload("res://src/simulation/frame_clock.gd")
## Native attack choreography. The owning flight applies these prospective cues
## to its actual actors, portal and camera before accepting a frame. This owner
## neither kills freighters nor awards progress; radio observes their real hulls.
const Definitions=preload("res://src/content/alioth_attack_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Library=preload("res://src/content/library.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
enum Stage { ATTACK, FREIGHTER_VIEW, BATTLE, ESCAPE_READY, ESCAPE_VIEW, FAREWELL, RETURN_FLIGHT }
var error:=""
var _state:={}
var _rules:={}
var _radio:={}
var _frame:={}
var _max_ms:=0

func configure(bindings: RefCounted) -> bool:
	error="";_state={};_rules={};_radio={};_frame={};_max_ms=0
	if not Definitions.available(bindings):return reject("Alioth attack declarations are unavailable")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id):return reject("Alioth attack requires a verified content identity")
	if not Numbers.integer(bindings.frame_clock.get("max_frame_milliseconds"),1,150):return reject("Alioth attack requires the ordinary frame clock")
	_rules=bindings.mido_travel.alioth_attack.duplicate(true)
	_max_ms=Frames.simulation_limit(bindings)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(_rules.campaign_cursor),
		"phase":Stage.ATTACK,"elapsed_ms":0,"revision":0,"input_blocked":false,"player_update_suspended":false,"hud_visible":true,"completion_ready":false}
	return true

func advance(delta_ms: Variant, radio: Dictionary, actors: Dictionary, player_pose: Transform3D, portal_pose: Transform3D, random_state: Dictionary) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(delta_ms,0,_max_ms):return reject("Alioth attack requires an ordinary frame")
	if not Flight.rigid_pose(player_pose) or not Flight.rigid_pose(portal_pose):return reject("Alioth attack requires finite current player and portal poses")
	if not _valid_actors(actors) or not _valid_radio(radio):return false
	if int(_state.elapsed_ms)>2147483647-int(delta_ms):return reject("Alioth attack clock exceeds its source range")
	var random:=Random.new()
	if not random.restore(random_state):return reject(random.error)
	var next:=_state.duplicate(true)
	next.elapsed_ms+=int(delta_ms)
	next.revision+=1
	var frame:={"camera_operations":[],"portal_operations":[],"actor_overrides":[],"retire_actor_ids":[],
		"cancel_player_actions":false,"reset_follow_offsets":false,"reset_starfield":false,"completion_became_ready":false,
		"input_random_state":random.snapshot(),"random_state":random.snapshot()}
	var rules: Dictionary=_rules.choreography
	match int(next.phase):
		Stage.ATTACK:
			if radio.started[int(rules.first_event_started)]:
				next.phase=Stage.FREIGHTER_VIEW
				_enter_view(next,frame,bool(rules.first_view_suspends_player_update))
				var id:=int(rules.first_view_actor_id)
				frame.camera_operations=[{"action":"follow_actor","actor_id":id},
					{"action":"set_eye","position":Vectors.added(actors.actors[id].body_pose.origin,vec(rules.first_eye_offset))}]
		Stage.FREIGHTER_VIEW:
			frame.camera_operations=[{"action":"offset","delta":rate_delta(delta_ms,rules.first_camera_per_ms)}]
			frame.reset_starfield=true
			if radio.finished[int(rules.first_view_event_finished)]:
				next.phase=Stage.BATTLE
				_leave_view(next,frame)
		Stage.BATTLE:
			if next.elapsed_ms>=int(rules.portal_close_at_ms):
				next.phase=Stage.ESCAPE_READY
				frame.portal_operations=[portal_command(false)]
		Stage.ESCAPE_READY:
			if radio.started[int(rules.escape_event_started)]:
				next.phase=Stage.ESCAPE_VIEW
				_enter_view(next,frame,bool(rules.escape_suspends_player_update))
				frame.portal_operations=[portal_command(true)]
				frame.camera_operations=[{"action":"follow_environment","slot":int(_rules.portal.environment_slot)},
					{"action":"set_eye","position":Vectors.added(portal_pose.origin,vec(rules.escape_eye_offset))}]
				frame.actor_overrides=_escape_actors(portal_pose.origin,random)
				if frame.actor_overrides.is_empty():return false
		Stage.ESCAPE_VIEW:
			frame.camera_operations=[{"action":"offset","delta":rate_delta(delta_ms,rules.escape_camera_per_ms)}]
			if radio.finished[int(rules.retire_event_finished)]:
				next.phase=Stage.FAREWELL
				for row in _rules.population.actors:
					if int(row.actor_kind)==int(rules.escaping_actor_kind):frame.retire_actor_ids.append(int(row.actor_id))
				frame.portal_operations=[portal_command(false)]
				frame.reset_starfield=true
		Stage.FAREWELL:
			if radio.finished[int(rules.restore_event_finished)]:
				next.phase=Stage.RETURN_FLIGHT
				_leave_view(next,frame)
	# Source condition22 observes the last event, independently of actor deaths
	# or the sequence phase. The flight owner retains acknowledgement policy.
	next.completion_ready=bool(radio.finished[int(_rules.completion.last_radio_event)])
	frame.completion_became_ready=next.completion_ready and not _state.completion_ready
	frame.random_state=random.snapshot()
	for op in frame.camera_operations:
		if op.has("position") and not op.position.is_finite():return reject("Alioth camera exceeded source coordinates")
	_state=next;_frame=frame
	_radio={"started":radio.started.duplicate(),"finished":radio.finished.duplicate()}
	return true

func _enter_view(next: Dictionary, frame: Dictionary, suspend_player: bool) -> void:
	next.input_blocked=true;next.hud_visible=false;next.player_update_suspended=suspend_player
	frame.cancel_player_actions=true;frame.reset_follow_offsets=true;frame.reset_starfield=true

func _leave_view(next: Dictionary, frame: Dictionary) -> void:
	next.input_blocked=false;next.hud_visible=true;next.player_update_suspended=false
	frame.camera_operations.append({"action":"follow_player"})
	frame.reset_follow_offsets=true;frame.reset_starfield=true

func portal_command(opening: bool) -> Dictionary:
	var data: Dictionary=_rules.portal
	var op:={"slot":int(data.environment_slot),"elapsed_ms":int(data.open_elapsed_ms if opening else data.close_elapsed_ms),
		"extent":int(data.open_extent if opening else data.close_extent)}
	if opening:op.visible=true
	return op

func _escape_actors(portal_position: Vector3, random: RefCounted) -> Array:
	var rules: Dictionary=_rules.choreography
	var target:=Vectors.added(portal_position,vec(rules.escape_route_offset))
	for axis in 3:
		if not is_finite(target[axis]) or target[axis]<-2147483648.0 or target[axis]>=2147483648.0:
			reject("Alioth escape route exceeds the source integer range")
			return []
		target[axis]=int(target[axis])
	var base:=Vectors.added(portal_position,vec(rules.escape_position_offset))
	var rows:=[]
	for actor in _rules.population.actors:
		if int(actor.actor_kind)!=int(rules.escaping_actor_kind):continue
		var position:=base
		for axis in [1,2]:
			position[axis]=Vitals.single(Vitals.single(position[axis]+float(rules.escape_jitter_offset))+float(random.next_int(int(rules.escape_jitter_bound))))
		var forward:=Vectors.normalized(Vectors.added(portal_position,-position))
		var right:=Vectors.normalized(Vectors.cross(Vector3.UP,forward))
		var up:=Vectors.normalized(Vectors.cross(forward,right))
		var pose:=Transform3D(Basis(right,up,forward),position)
		if not Flight.rigid_pose(pose):
			reject("Alioth escape produced an invalid actor pose")
			return []
		rows.append({"actor_id":int(actor.actor_id),"body_pose":pose,"clear_targets":true,
			"route_points":[target],"route_initial_index":int(_rules.population.route_initial_index),"route_loop":bool(_rules.population.route_loop)})
	return rows

func _valid_actors(context: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if context.get(key)!=_state[key]:return reject("Alioth actors belong to another encounter")
	var rows: Variant=context.get("actors")
	var expected: Array=_rules.population.actors
	if not rows is Array or rows.size()!=expected.size():return reject("Alioth attack requires its complete authored cast")
	for id in rows.size():
		if not rows[id] is Dictionary:return reject("Alioth attack lost an authored actor")
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:
			if rows[id].get(key)!=int(expected[id][key]):return reject("Alioth attack changed its authored actor membership")
		if not Flight.rigid_pose(rows[id].get("body_pose")):return reject("Alioth attack requires current actor poses")
	return true

func _valid_radio(radio: Dictionary) -> bool:
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if radio.get(key)!=_state[key]:return reject("Alioth radio belongs to another encounter")
	var count: int=_rules.radio_events.size()
	for key in ["started","finished"]:
		var flags: Variant=radio.get(key)
		if not flags is Array or flags.size()!=count:return reject("Alioth radio is incomplete")
		for i in count:
			if not flags[i] is bool or (_radio.has(key) and _radio[key][i] and not flags[i]):return reject("Alioth radio regressed or changed type")
	for i in count:
		if radio.finished[i] and not radio.started[i]:return reject("Alioth radio finished before it started")
	return true

static func vec(values: Array) -> Vector3:return Vector3(values[0],values[1],values[2])

static func rate_delta(delta_ms: int, rates: Array) -> Vector3:
	return Vector3(Vitals.single(delta_ms*float(rates[0])),Vitals.single(delta_ms*float(rates[1])),Vitals.single(delta_ms*float(rates[2])))

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true);result.frame=_frame.duplicate(true)
	return result

func clear_frame_cues() -> void:
	_frame={}

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._rules=_rules.duplicate(true);copy._radio=_radio.duplicate(true)
	copy._frame=_frame.duplicate(true);copy._max_ms=_max_ms
	return copy

func reject(message: String) -> bool:
	error=message
	return false
