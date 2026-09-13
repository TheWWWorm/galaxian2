extends RefCounted
## Counter changes in the configured encounter. Save totals and
## mission/achievement outcomes require their own verified state owners.
const Definitions = preload("res://src/content/npc_death_accounting_definitions.gd")
const FullHold = preload("res://src/content/full_hold_destruction_definitions.gd")
const Appearance=preload("res://src/content/full_hold_appearance_definitions.gd")
const Training=preload("res://src/content/combat_training_destruction_definitions.gd")
var error := ""
var _identity := {}
var _rules := {}
var _events := []
var _totals := {}
var _population := 3
var _training := {}

func configure(bindings: RefCounted) -> bool:
	error="";_identity={};_rules={};_events=[];_totals={};_population=3;_training={}
	if bindings==null: return reject("NPC death accounting requires content bindings")
	var rules: Variant=bindings.opening_actors.get("npc_initialization",{}).get("death_accounting",{})
	if not Definitions.parameters(rules): return reject("This content profile has no supported NPC death accounting")
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_rules=rules.duplicate(true)
	for key in ["hostile_remaining","hostile_deaths","world_player_kills","world_other_kills","player_kills","pirate_kills"]: _totals[key]=0
	return true

func configure_full_hold(bindings: RefCounted) -> bool:
	if not configure(bindings):return false
	if not FullHold.parameters(bindings.full_hold_destruction):
		_identity={};_rules={};_totals={}
		return reject("Second-trip kill accounting requires its verified context")
	_identity.campaign_cursor=int(bindings.full_hold_destruction.campaign_cursor)
	_population=int(bindings.full_hold_destruction.counter_population)
	return true

func record(actor: Dictionary) -> Dictionary:
	return _record(actor,false)

func configure_combat_training(bindings: RefCounted) -> bool:
	if not configure(bindings):return false
	if not Training.parameters(bindings.combat_training_destruction):
		_identity={};_rules={};_totals={}
		return reject("Training death accounting requires its verified declarations")
	_training=bindings.combat_training_destruction.duplicate(true)
	_identity.campaign_cursor=int(_training.campaign_cursor);_population=int(_training.actor_count)
	_totals.nonhostile_remaining=0
	return true

func record_scripted_restart(actor: Dictionary, declarations: Dictionary) -> Dictionary:
	if not Appearance.parameters(declarations) or _identity.get("campaign_cursor")!=4 or _population!=1 or actor.get("appearance_applied")!=true:return fail("Repeated death counters require the verified one-time appearance")
	return _record(actor,true)

func _record(actor: Dictionary, scripted_restart: bool) -> Dictionary:
	error=""
	if _identity.is_empty(): return fail("Configure death accounting before recording a death")
	for key in _identity:
		if actor.get(key)!=_identity[key]: return fail("NPC death belongs to another content identity")
	var id: Variant=actor.get("actor_id")
	if not id is int or id<0 or id>=_population: return fail("NPC death is outside the configured population")
	var kind: int=int(_rules.actor_kind) if _training.is_empty() else int(_training.actors[id].actor_kind)
	var hostile: bool=true if _training.is_empty() else bool(_training.actors[id].hostile)
	var modes: Array=[0,1] if not _training.is_empty() and id==int(_training.initial_mode_death_actor) else [1]
	if not actor.get("actor_kind") is int or actor.actor_kind!=kind or not actor.get("hostile") is bool or actor.hostile!=hostile or not actor.get("active") is bool or not actor.active or not actor.get("actor_mode") is int or actor.actor_mode not in modes:
		return fail("NPC death requires a fresh active actor with its source hostility")
	if not actor.get("vitals") is Dictionary or not actor.vitals.get("hull") is int or actor.vitals.hull!=0 or not actor.get("nonplayer_kill") is bool:
		return fail("NPC death requires exhausted hull and retained kill attribution")
	var prior_count:=0
	for prior in _events:
		if prior.actor_id==id:prior_count+=1
	if prior_count!=(1 if scripted_restart else 0):return fail("NPC death was already recorded or lacks its prior scripted death")
	var player_credit: bool=not actor.nonplayer_kill
	var delta := {"hostile_remaining":int(_rules.hostile_remaining_delta),"hostile_deaths":int(_rules.hostile_deaths_delta),
		"world_player_kills":int(_rules.world_player_kills_delta) if player_credit else 0,
		"world_other_kills":0 if player_credit else int(_rules.world_other_kills_delta),
		"player_kills":int(_rules.player_kills_delta) if player_credit else 0,
		"pirate_kills":int(_rules.pirate_kills_delta) if player_credit else 0}
	if not _training.is_empty():
		if not hostile:
			for key in delta:delta[key]=0
		delta.nonhostile_remaining=int(_training.nonhostile_remaining_delta) if not hostile else 0
	var event := _identity.duplicate()
	event.merge({"actor_id":id,"nonplayer_kill":actor.nonplayer_kill,"counter_deltas":delta})
	if scripted_restart:event.scripted_restart=true
	_events.append(event)
	for key in delta: _totals[key]+=delta[key]
	return event.duplicate(true)

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate()
	result.events=_events.duplicate(true)
	result.counter_deltas=_totals.duplicate()
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._rules=_rules.duplicate(true)
	copy._events=_events.duplicate(true);copy._totals=_totals.duplicate()
	copy._population=_population
	copy._training=_training.duplicate(true)
	return copy

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
