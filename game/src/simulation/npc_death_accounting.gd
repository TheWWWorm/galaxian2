extends RefCounted
const Readonly=preload("res://src/simulation/readonly_state.gd")
const FreeLife=preload("res://src/content/free_lifecycle_definitions.gd")
const Kappa=preload("res://src/content/kappa_population_definitions.gd")
const Alioth=preload("res://src/content/alioth_population_definitions.gd")
## Counter changes in the configured encounter. Save totals and
## mission/achievement outcomes require their own verified state owners.
const Definitions = preload("res://src/content/npc_death_accounting_definitions.gd")
const FullHold = preload("res://src/content/full_hold_destruction_definitions.gd")
const Appearance=preload("res://src/content/full_hold_appearance_definitions.gd")
const Training=preload("res://src/content/combat_training_destruction_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const ContractLife=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const Convoy=preload("res://src/content/convoy_world_definitions.gd")
const Junk=preload("res://src/content/contract_junk_definitions.gd")
const Ambient=preload("res://src/content/ambient_combat_definitions.gd")
const Freighter=preload("res://src/content/freighter_destruction_definitions.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Lifecycle=preload("res://src/content/ambient_lifecycle_definitions.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error := ""
var _identity := {}
var _rules := {}
var _events := []
var _totals := {}
var _population := 3
var _training := {}
var _generations := []

func configure(bindings: RefCounted) -> bool:
	error="";_identity={};_rules={};_events=[];_totals={};_population=3;_training={};_generations=[]
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

func configure_local_traffic(bindings: RefCounted, data: Dictionary) -> bool:
	if not Travel.destruction_parameters(bindings,data):return reject("Local death accounting requires its verified population")
	if not configure(bindings):return false
	_training=data.duplicate(true);_identity.campaign_cursor=int(data.campaign_cursor);_population=int(data.actor_count)
	_totals.nonhostile_remaining=0
	return true

func configure_ambient(bindings: RefCounted,construction: RefCounted) -> bool:
	if bindings==null or not construction is Construction or not Freighter.parameters(bindings.freighter_destruction):return reject("Ambient death accounting requires its supported construction")
	var packet: Dictionary=construction.snapshot()
	var ordinary:=FreeLife.population(bindings,packet) if packet.has("free_context") else {}
	if (packet.has("free_context") and ordinary.is_empty()) or (not packet.has("free_context") and Ambient.population(bindings,packet,0,0.5).is_empty()):return reject("Ambient death accounting population is invalid")
	if not configure(bindings):return false
	_training={"actors":packet.actors.duplicate(true),"nonhostile_remaining_delta":int(bindings.freighter_destruction.nonhostile_remaining_delta),"pirate_kills_delta":int(bindings.freighter_destruction.pirate_kills_delta)}
	if not ordinary.is_empty():_training.free_lifecycle=ordinary.free_lifecycle.duplicate(true)
	_identity.campaign_cursor=int(packet.campaign_cursor);_population=packet.actors.size()
	_totals.nonhostile_remaining=0
	if Lifecycle.recycling_parameters(bindings.ambient_lifecycle):_generations.resize(_population);_generations.fill(0)
	return true

func register_relaunch(actor: Dictionary) -> bool:
	error=""
	if _generations.is_empty():return reject("This death history does not support recycled traffic")
	for key in _identity:
		if actor.get(key)!=_identity[key]:return reject("Recycled death accounting belongs to another encounter")
	var id: Variant=actor.get("actor_id")
	if not Numbers.integer(id,0,_population-1):return reject("Recycled death actor is outside the population")
	for key in ["actor_kind","hull_catalogue_id","subtype","population_group"]:
		if actor.get(key)!=_training.actors[id].get(key):return reject("Recycled death actor changed its construction")
	if actor.get("population_group") not in ["patrol","travel"] or actor.get("spawn_generation")!=_generations[id]+1 or actor.get("active")!=true or actor.get("actor_mode")!=1 or actor.get("vitals",{}).get("hull",0)<=0:return reject("Death accounting requires the next restored small ship")
	_generations[id]+=1
	return true

func configure_contract(bindings: RefCounted,construction: RefCounted) -> bool:
	if not construction is Construction:return reject("Contract death accounting requires its accepted population")
	var data:=ContractLife.population(bindings,construction.snapshot())
	if data.is_empty():data=Junk.population(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported contract death accounting")
	if not configure(bindings):return false
	_training=data;_population=int(data.actor_count);_identity.campaign_cursor=int(data.campaign_cursor)
	_totals.nonhostile_remaining=0
	if int(data.mission.kind)==7:_totals.debris_destroyed=0
	return true

func configure_convoy(bindings: RefCounted,construction: RefCounted) -> bool:
	if not construction is Construction:return reject("Convoy accounting requires its generated encounter")
	var data:=Convoy.lifecycle(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported convoy death accounting")
	if not configure(bindings):return false
	_training=data;_population=int(data.actor_count);_identity.campaign_cursor=int(data.campaign_cursor)
	_totals.nonhostile_remaining=0;_totals.capital_ship_kills=0
	return true

func configure_alioth_attack(bindings: RefCounted,construction: RefCounted) -> bool:
	if not construction is Construction:return reject("Alioth accounting requires its generated encounter")
	var data:=Alioth.lifecycle(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported Alioth death accounting")
	if not configure(bindings):return false
	_training=data;_population=int(data.actor_count);_identity.campaign_cursor=int(data.campaign_cursor)
	_totals.nonhostile_remaining=0
	return true

func configure_kappa_rescue(bindings: RefCounted,construction: RefCounted) -> bool:
	if not construction is Construction:return reject("Kappa accounting requires its generated encounter")
	var data:=Kappa.lifecycle(bindings,construction.snapshot())
	if data.is_empty():return reject("Unsupported Kappa death accounting")
	if not configure(bindings):return false
	_training=data;_population=int(data.actor_count);_identity.campaign_cursor=int(data.campaign_cursor)
	_totals.nonhostile_remaining=0
	return true

func _configure_story(bindings: RefCounted,data: Dictionary) -> bool:
	if not configure(bindings):return false
	_training=data;_population=int(data.actor_count);_identity.campaign_cursor=int(data.campaign_cursor)
	_totals.nonhostile_remaining=0
	return true

func _record(actor: Dictionary, scripted_restart: bool) -> Dictionary:
	error=""
	if _identity.is_empty(): return fail("Configure death accounting before recording a death")
	for key in _identity:
		if actor.get(key)!=_identity[key]: return fail("NPC death belongs to another content identity")
	var id: Variant=actor.get("actor_id")
	if not id is int or id<0 or id>=_population: return fail("NPC death is outside the configured population")
	var kind: int=int(_rules.actor_kind) if _training.is_empty() else int(_training.actors[id].actor_kind)
	var local: bool=_identity.get("campaign_cursor") in [10,11,12,13,14] or _training.has("kappa_lifecycle") or _training.has("alioth_lifecycle") or _training.has("free_lifecycle") or _training.get("authored_story",false)
	var hostile: bool=bool(actor.get("hostile",false)) if local else (true if _training.is_empty() else bool(_training.actors[id].hostile))
	var modes: Array=[0,1] if local or (not _training.is_empty() and id==int(_training.initial_mode_death_actor)) else [1]
	if not _generations.is_empty():
		if actor.get("spawn_generation")!=_generations[id]:return fail("Death belongs to an earlier traffic instance")
		if actor.get("population_group")=="travel":modes.append(6)
	if not actor.get("actor_kind") is int or actor.actor_kind!=kind or not actor.get("hostile") is bool or actor.hostile!=hostile or not actor.get("active") is bool or not actor.active or not actor.get("actor_mode") is int or actor.actor_mode not in modes:
		return fail("NPC death requires a fresh active actor with its source hostility")
	if not actor.get("vitals") is Dictionary or not actor.vitals.get("hull") is int or actor.vitals.hull!=0 or not actor.get("nonplayer_kill") is bool:
		return fail("NPC death requires exhausted hull and retained kill attribution")
	var prior_count:=0
	for prior in _events:
		if prior.actor_id==id and (_generations.is_empty() or prior.get("spawn_generation")==_generations[id]):prior_count+=1
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
	if _identity.get("campaign_cursor") in [13,14] or _training.has("kappa_lifecycle") or _training.has("alioth_lifecycle") or _training.has("free_lifecycle") or _training.get("authored_story",false):
		delta.pirate_kills=int(_rules.pirate_kills_delta) if hostile and kind==8 and player_credit else 0
	elif local:delta.pirate_kills=int(_training.pirate_kills_delta)
	if _training.has("capital_death"):
		# The source battleship counter is independent of current hostility.
		# Script retirement never enters this fresh, active death path.
		delta.capital_ship_kills=int(_training.capital_death.capital_kills_delta) if actor.get("population_group")=="capital" and player_credit else 0
	if _training.get("mission",{}).get("kind")==7:
		for key in delta:delta[key]=0
		delta.hostile_remaining=int(_training.lifecycle.hostile_remaining_delta)
		delta.debris_destroyed=int(_training.lifecycle.debris_destroyed_delta)
	var event := _identity.duplicate()
	event.merge({"actor_id":id,"nonplayer_kill":actor.nonplayer_kill,"counter_deltas":delta})
	if not _generations.is_empty():event.spawn_generation=_generations[id]
	if scripted_restart:event.scripted_restart=true
	_events.append(event)
	for key in delta: _totals[key]+=delta[key]
	return event.duplicate(true)

func snapshot() -> Dictionary:
	if _identity.is_empty(): return {}
	var result := _identity.duplicate()
	result.events=_events.duplicate(true)
	result.counter_deltas=_totals.duplicate()
	# An ordinary courier world still owns an empty traffic-generation ledger.
	if not _generations.is_empty() or (_population==0 and _training.has("free_lifecycle")):result.spawn_generations=_generations.duplicate()
	return result

func fork_for_frame() -> RefCounted:
	# Configuration is fixed after preparation; detach live state only.
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._rules=Readonly.freeze(_rules)
	copy._events=_events.duplicate(true);copy._totals=_totals.duplicate()
	copy._population=_population
	copy._training=Readonly.freeze(_training)
	copy._generations=_generations.duplicate()
	return copy

func reject(message: String) -> bool:
	error=message
	return false

func fail(message: String) -> Dictionary:
	reject(message)
	return {}
