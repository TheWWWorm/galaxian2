extends RefCounted
## Rescue observations produce prospective actor cues. The flight owns damage,
## population, radio, and applying cues; the session owns failure and progress.
const Definitions=preload("res://src/content/kappa_rescue_definitions.gd")
const Radio=preload("res://src/simulation/radio_sequence.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Library=preload("res://src/content/library.gd")
var error:=""
var _state:={}
var _rules:={}
var _radio:={}
var _flight_identity: RefCounted

func configure(bindings: RefCounted) -> bool:
	error=""
	if not Definitions.available(bindings):return reject("Kappa rescue declarations are unavailable")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id):return reject("Kappa rescue requires a verified content identity")
	_rules=bindings.mido_travel.kappa_rescue.duplicate(true)
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(_rules.campaign_cursor),
		"phase":int(_rules.choreography.initial_phase),"completion_ready":false,"failure_ready":false,"force_hostile_actor_ids":[]}
	_radio={}
	_flight_identity=null
	return true

## A detached predicate observation cannot authorize earned career progress.
## The encounter attaches its native flight identity before exposing a result.
func bind_flight(controller: RefCounted) -> bool:
	error=""
	if not is_instance_of(controller,load("res://src/simulation/combat_training_control.gd")):return reject("Rescue observations require the actual native flight")
	var context: Dictionary=controller.kappa_context()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if _state.is_empty() or context.get(key)!=_state.get(key):return reject("Rescue observations belong to another native flight")
	var identity: RefCounted=controller.flight_identity()
	if identity==null or (_flight_identity!=null and _flight_identity!=identity):return reject("Rescue observations cannot change their retained flight")
	_flight_identity=identity
	return true

func matches_flight(controller: RefCounted) -> bool:
	return _flight_identity!=null and is_instance_of(controller,load("res://src/simulation/combat_training_control.gd")) and controller.flight_identity()==_flight_identity

func advance(radio: RefCounted,combat: Dictionary) -> bool:
	error=""
	if _state.is_empty() or not radio is Radio:return reject("Kappa rescue requires its configured radio owner")
	var observed: Dictionary=radio.snapshot()
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if observed.get(key)!=_state[key] or combat.get(key)!=_state[key]:return reject("Kappa rescue observations belong to another encounter")
	for key in ["started","finished"]:
		var flags: Variant=observed.get(key)
		if not flags is Array or flags.size()!=_rules.radio_events.size():return reject("Kappa rescue radio is incomplete")
		for i in flags.size():
			if not flags[i] is bool or (_radio.has(key) and _radio[key][i] and not flags[i]):return reject("Kappa rescue radio regressed")
	var actors: Variant=combat.get("actors")
	if not actors is Array or actors.size()!=_rules.population.actor_count:return reject("Kappa rescue requires its complete authored cast")
	for id in actors.size():
		var actor: Variant=actors[id]
		if not actor is Dictionary:return reject("Kappa rescue lost an authored actor")
		for key in ["actor_id","actor_kind","hull_catalogue_id"]:
			if actor.get(key)!=int(_rules.population.actors[id][key]):return reject("Kappa rescue actor membership changed")
		if not actor.get("hostile") is bool or not Numbers.integer(actor.get("actor_mode"),0,5):return reject("Kappa rescue requires current hostility and life modes")
	var next:=_state.duplicate(true)
	next.force_hostile_actor_ids=[]
	if next.phase==int(_rules.choreography.initial_phase):
		var activate: bool=observed.started[int(_rules.choreography.escort_activation_event_started)]
		var provoked: bool=_rules.choreography.escort_actor_ids.any(func(id):return actors[int(id)].hostile)
		if activate or provoked:next.force_hostile_actor_ids=_rules.choreography.escort_actor_ids.map(func(id):return int(id))
		if activate:next.phase+=1
	next.completion_ready=observed.finished[int(_rules.completion.last_radio_event)]
	# Failure waits for retirement; zero hull and dormant inactivity differ.
	# Readiness is independent of the earlier completion-poll eligibility gate.
	next.failure_ready=true
	for id in int(_rules.failure.first_actor_count):
		next.failure_ready=next.failure_ready and actors[id].actor_mode==int(_rules.failure.actor_mode)
	_state=next
	_radio={"started":observed.started.duplicate(),"finished":observed.finished.duplicate()}
	return true

## The ordinary flight checks eligible completion before failure and leaves
## that pass immediately when a completion panel opens. Failure is still checked
## when completion polling is gated. Selection is prospective: only the session
## may present/acknowledge a result or advance an earned campaign.
func poll_outcome(completion_allowed: bool) -> String:
	error=""
	if _state.is_empty():reject("Kappa outcome requires its configured rescue observations");return ""
	if completion_allowed and _state.completion_ready:return "completed"
	if _state.failure_ready:return "failed"
	return ""

func snapshot() -> Dictionary:return _state.duplicate(true)

func fork() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._rules=_rules.duplicate(true);copy._radio=_radio.duplicate(true)
	copy._flight_identity=_flight_identity
	return copy

func reject(message: String) -> bool:
	error=message
	return false
